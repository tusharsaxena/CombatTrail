local _, NS = ...
-- modules/Results_Tips.lua — what the Results window's fight table says on hover: a tooltip for
-- every cell, beside the window (modules/Results_Table.lua's SideTip), one for every group header,
-- and one for every column header, LootHistory's way (the column's name in gold, then what it
-- shows). Adapted from DPS Race @045f479 (modules/Results_Tips.lua) without its race: no race
-- length, tail or late-cast lines, no dummy category. The fight detail's figures, chart and
-- breakdown are Tips.Detail's (below); the compare's hovers join with its pane (plan Task 4.4).
--
-- PURE OVER THE STORED RECORD. Each builder takes a fight record and answers its lines, { title,
-- line, ... }, a line a string or { text, r, g, b }; nothing here reads a meter or a frame. A column
-- may carry its own `tip(record)` (the Delta column, which needs the view), which wins over the
-- builder here by its key.

local Tips = {}
NS.ResultsTips = Tips

local L = NS.L
local DASH = "\226\128\148"
local SEP = " \194\183 "

local function Tbl() return NS.ResultsTable end
local function Fights() return NS.ResultsFights end

-- A whole number with thousands separators: "36,812,345".
local function grouped(n)
    if type(n) ~= "number" then return DASH end
    local s = ("%d"):format(math.floor(n + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""):gsub("^%-,", "-"))
end
Tips.Grouped = grouped

local function dimLine(text) return { text, NS.Style.Rgb("ct.dim") } end

local function who(record) return type(record.who) == "table" and record.who or {} end
local function ident(record) return type(record.identity) == "table" and record.identity or {} end

-- ── one builder per column key ──────────────────────────────────────────────────────────────────

local CELL = {}

function CELL.date(record)
    local lines = { Tbl().Date(record.t, "%A %d %B %Y, %H:%M") }
    local stamp = {}
    if record.build then stamp[#stamp + 1] = L["build %s"]:format(tostring(record.build)) end
    if record.version then stamp[#stamp + 1] = "v" .. tostring(record.version) end
    if #stamp > 0 then lines[#lines + 1] = table.concat(stamp, SEP) end
    return lines
end

function CELL.clsSpec(record)
    local w = who(record)
    local spec = Tbl().SpecInfo(w.specID, w.specName)
    local c = Tbl().ClassColor(w.class)
    local title = spec and ("%s %s"):format(spec, Tbl().ClassName(w.class)) or Tbl().ClassName(w.class)
    return { title, { L["Class color"], c[1], c[2], c[3] } }
end

function CELL.character(record)
    local w = who(record)
    local lines = { ("%s-%s"):format(tostring(w.name or "?"), tostring(w.realm or "?")) }
    if w.petName then
        local pet = w.petFamily and ("%s (%s)"):format(w.petName, w.petFamily) or w.petName
        lines[#lines + 1] = L["Pet: %s"]:format(pet)
    end
    return lines
end

function CELL.ilvl(record)
    return { L["Item level %s"]:format(Tbl().Ilvl(who(record).ilvl)), L["Equipped, read when the fight started."] }
end

function CELL.target(record)
    local i = ident(record)
    local lines = { Fights().TargetName(record) }
    if i.encounterID and i.targetName and i.targetName ~= i.encounterName then
        lines[#lines + 1] = L["Primary target: %s"]:format(i.targetName)
    end
    if type(i.otherTargets) == "number" and i.otherTargets > 0 then
        lines[#lines + 1] = i.otherTargets == 1 and L["1 other target took damage"]
            or L["%d other targets took damage"]:format(i.otherTargets)
    end
    if i.isBoss then lines[#lines + 1] = L["A boss fight"] end
    if i.unknown then lines[#lines + 1] = dimLine(L["No readable target: this fight never counts as a best."]) end
    return lines
end

function CELL.content(record)
    local i = ident(record)
    local text = Tbl().ContentChip(record)
    local lines = { text }
    local where = {}
    if i.instanceName then where[#where + 1] = i.instanceName end
    if i.difficultyName then where[#where + 1] = i.difficultyName end
    if #where > 0 then lines[#lines + 1] = table.concat(where, SEP) end
    local tier = Fights().TierText(record)
    if tier then lines[#lines + 1] = tier end
    return lines
end

function CELL.len(record)
    return { L["Length %s"]:format(NS.Format.Length(record.duration)),
             L["The meter's session, from the first hit to the end of combat."] }
end

function CELL.damage(record)
    local d = type(record.damage) == "table" and record.damage or {}
    local lines = { L["%s damage"]:format(grouped(d.merged)) }
    if type(d.pet) == "number" and d.pet > 0 then
        lines[#lines + 1] = L["You %s, your pet %s"]:format(grouped(d.player), grouped(d.pet))
    end
    lines[#lines + 1] = dimLine(L["Read from Blizzard's meter after combat. The bar runs from the smallest fight in its group to the largest."])
    return lines
end

function CELL.dps(record)
    local lines = { L["%s DPS"]:format(grouped(record.dps)), L["Damage over the fight's length."] }
    if type(record.meterDps) == "number" then
        lines[#lines + 1] = dimLine(L["Blizzard's meter said %s."]:format(grouped(record.meterDps)))
    end
    return lines
end

-- What a fight used: each entry's icon, name and when (modules/Results_Usage.lua); a hidden item is
-- not listed.
function CELL.used(record)
    local U = NS.ResultsUsage
    local entries = U.Entries(record)
    if not entries then
        return { L["Not recorded"], L["This fight was recorded before the addon kept what was used."] }
    end
    if #entries == 0 then
        return { L["Nothing used"], L["No on-use item or consumable was detected or ticked for this fight."] }
    end
    local lines = { #entries == 1 and L["1 item used"] or L["%d items used"]:format(#entries) }
    for _, e in ipairs(entries) do
        lines[#lines + 1] = U.InlineIcon(e) .. " " .. L["%s: %s"]:format(U.Name(e), U.Detail(e))
    end
    lines[#lines + 1] = dimLine(L["Edit the list in the fight's detail."])
    return lines
end

-- A builder's lines with any hole closed up, however many there are.
local function compact(lines)
    local top = 0
    for k in pairs(lines) do
        if type(k) == "number" and k > top then top = k end
    end
    local out = {}
    for i = 1, top do if lines[i] ~= nil then out[#out + 1] = lines[i] end end
    return out
end

--- A cell's tooltip lines: the column's own `tip`, else the builder for its key, else nil.
--- @param col table
--- @param record table
--- @return table|nil
function Tips.Cell(col, record)
    local fn = col.tip or CELL[col.key]
    if not fn then return nil end
    local ok, lines = pcall(fn, record)
    if not ok or type(lines) ~= "table" then return nil end
    return compact(lines)
end

--- A group header's tooltip.
function Tips.Group(g)
    return { g.label, g.count == 1 and L["1 fight"] or L["%d fights"]:format(g.count),
             dimLine(L["Click to fold or unfold the group."]) }
end

-- ── the headers ─────────────────────────────────────────────────────────────────────────────────

local ABOUT = {
    date = "When the fight started. Click to sort.",
    clsSpec = NS.Compat.ForClient({ "retail" }) and "The character's class and spec."
        or "The character's class and talent tree.",
    character = "Who fought. Hover a name for the realm and the pet.",
    ilvl = "Equipped item level when the fight started.",
    target = "The encounter, or the enemy that took the most damage.",
    content = "Where the fight was: a raid, a dungeon, the open world, a training dummy and so on.",
    len = "How long the fight lasted.",
    damage = "Your damage and your pet's, read from Blizzard's meter after combat. The bar runs from the smallest fight in its group to the largest (with no grouping, the whole list).",
    dps = "Damage over the fight's length. The bar runs from the smallest fight in its group to the largest (with no grouping, the whole list).",
    delta = "How far this fight's DPS is from the best fight in its group (with no grouping, the whole list). The best reads 0.0%.",
    status = "Best: your best fight on its board (this character and spec against this encounter or target), whatever the filters show.",
    used = "What the fight used: on-use gear (trinkets first), then potions, flasks, food and the rest. Hover for when; sorted by how many.",
    note = "The note you kept with the fight. Click to sort.",
}

--- A header's tooltip: { title, text }, or nil for a column with nothing to say.
function Tips.About(col)
    local text = col.about or ABOUT[col.key]
    if not text then return nil end
    return { title = col.label, text = L[text] }
end

-- ── the fight detail (modules/Results_Detail.lua) ───────────────────────────────────────────────

local DETAIL = {}

function DETAIL.meta(record)
    local lines = CELL.target(record)
    local stamp = CELL.date(record)
    for i = 1, #stamp do lines[#lines + 1] = stamp[i] end
    return lines
end

function DETAIL.damage(record)
    return CELL.damage(record)
end

function DETAIL.dps(record)
    return CELL.dps(record)
end

function DETAIL.meterDps(record)
    local lines = { L["Meter DPS"], L["What Blizzard's damage meter said the fight's DPS was."] }
    if type(record.meterDps) ~= "number" then lines[#lines + 1] = dimLine(L["The meter did not say."]) end
    return lines
end

function DETAIL.delta(record, ctx)
    -- The detail's best is a group's: the list's group for the fight, or its board when the list's
    -- filters leave it out.
    return Fights().DeltaTip(record, ctx, true)
end

function DETAIL.chart(record)
    local lines = { L["Damage profile"], L["Your damage over the fight, one column a stretch of time; long cooldowns sit along its top."] }
    if not NS.Slices.Drawable(record) then
        lines[#lines + 1] = dimLine(L["The chart lives in memory only, so a fight recorded before your last reload or login has none."])
    end
    return lines
end

function DETAIL.breakdown(record)
    local n = #NS.Recorder.Spells(record)
    return { L["Spell breakdown"], n == 1 and L["1 spell, highest first, with its share of the fight's damage."]
        or L["%d spells, highest first, each with its share of the fight's damage."]:format(n),
        dimLine(L["Your pet's spells carry the paw."]) }
end

--- A detail element's tooltip lines (`key` one of meta, damage, dps, meterDps, delta, chart,
--- breakdown), or nil.
--- @param key string
--- @param record table
--- @param ctx table|nil  the Delta box's context
--- @return table|nil
function Tips.Detail(key, record, ctx)
    local fn = DETAIL[key]
    if not (fn and type(record) == "table") then return nil end
    local ok, lines = pcall(fn, record, ctx)
    if not ok or type(lines) ~= "table" then return nil end
    return compact(lines)
end
