local _, NS = ...
-- modules/Results_Races.lua — races in the Results window's one history (Race mode plan Task D1, spec
-- §7): the Fights / Races / All filter and, under Races, DPS Race's race filters (race length, dummy
-- kind, Hide flagged, Include incomplete, Only best); the race groupings (race length, dummy kind and
-- length, spec and dummy kind and length); what a race row draws (its score, its race DPS, its time
-- raced, and in the target cell its length chip and its flag chip: ruling X11, no Status column); and
-- the race cells' tooltips. Ported from DPS Race @f8078c7 (modules/Results_Runs.lua and
-- modules/Results_Table.lua's race helpers) onto the record's race part (modules/RaceRecord.lua):
-- DPS Race read `run.status`, `run.result` and `run.flags`; here every helper reads `record.race`.
--
-- THE SEAMS. modules/Results_Fights.lua (near the layout cap) keeps its filter loop, its options, its
-- groupings and its bar, and asks this file at CALL time: Races.Pass for each race filter key,
-- Races.Options for the race dropdowns' lists, Races.GROUP_SPECS / GROUPS for the race groupings,
-- Races.Row2 / BuildBar / LayoutBar / PaintBar for the bar's second row, and Races.Chips, Seconds and
-- Score for a race row's cells. modules/Results_Tips.lua asks Races.CellTip.
--
-- CLIENTS (clients-§4, Review focus 3). Every race CONTROL is Retail's (Races.On): the filter, the
-- race filters, the race groupings, the chips. On WoW Forever none of them is built, and a race a
-- Retail character saved in the account-wide history lists as a fight, with its race DPS (the one DPS a
-- record is ranked by, spec §7). Nothing here asks the Race mode switch: a saved race is a fight
-- record with a race part, listed whether Race mode is on or off (spec §8).
--
-- PURE over stored records but for the bar (frames) and Only best (the source's boards).

local Races = {}
NS.ResultsRaces = Races

local L = NS.L
local Tbl = NS.ResultsTable
local C = Tbl.COLORS
local RETAIL = { "retail" }
local DASH = "\226\128\148"
local SEP = " \194\183 "

--- Whether this client has the race controls (Retail).
--- @return boolean
function Races.On()
    return NS.Compat.ForClient(RETAIL) and true or false
end

local function isRace(record) return NS.RaceRecord.IsRace(record) end

--- The race clock a race's chart and Timeline run on (ruling X9): `shift`, the seconds from combat
--- entry to its first hit (0 for a race saved without it), and `length`, where the buzzer line sits.
--- nil for a fight, a race with no length, and on WoW Forever, where a saved race lists as a fight
--- on the fight's own clock, as its detail has no Timing section there (Review focus 3).
--- @param record table|nil
--- @return table|nil clock  { shift, length }
function Races.Clock(record)
    if not (Races.On() and isRace(record)) then return nil end
    local length = record.race.length
    if type(length) ~= "number" or length <= 0 then return nil end
    return { shift = NS.RaceRecord.FirstHit(record), length = length }
end

-- ── colors (DPS Race's, the owner's calls 2026-10-24/25) ────────────────────────────────────────

-- The five preset lengths in muted ROYGBIV hues, shortest to longest; any other length a neutral gray.
Races.LENGTH_COLORS = {
    [30]  = { 0.86, 0.52, 0.52 },
    [60]  = { 0.88, 0.67, 0.46 },
    [120] = { 0.86, 0.81, 0.52 },
    [180] = { 0.56, 0.80, 0.58 },
    [300] = { 0.58, 0.66, 0.92 },
}
Races.LENGTH_NEUTRAL = { 0.76, 0.76, 0.80 }

-- One hue per dummy kind (modules/Dummies.lua CATEGORIES), "other" for a kind no longer known.
Races.KIND_COLORS = {
    single     = { 0.56, 0.72, 1.0 },
    cleave     = { 1.0, 0.72, 0.29 },
    dungeoneer = { 1.0, 0.45, 0.45 },
    boss       = { 0.75, 0.55, 1.0 },
    pvp        = { 0.36, 0.86, 0.46 },
    other      = { 0.62, 0.62, 0.68 },
}

--- A race length's color: a preset's hue, else the neutral gray.
--- @param seconds number|nil
--- @return table color
function Races.LengthColor(seconds)
    return type(seconds) == "number" and Races.LENGTH_COLORS[seconds] or Races.LENGTH_NEUTRAL
end

-- The flag chips, in DPS Race's Status badge colors and icons (the declared set, CLAUDE.md).
Races.STATUS = {
    flagged    = { label = "Flagged", color = C.red, icon = "ph:flag" },
    incomplete = { label = "Incomplete", color = { 1.0, 0.58, 0.16 }, icon = "ph:x" },
    died       = { label = "Died", color = { 1.0, 0.42, 0.72 }, icon = "ph:skull" },
}

-- ── pure: a race's facts ────────────────────────────────────────────────────────────────────────

--- A race's dummy kind as the boards read it now (modules/Bests.lua RaceKind), "other" when it has
--- none; nil for a fight.
--- @return string|nil kind
function Races.KindOf(record)
    if not isRace(record) then return nil end
    return NS.Bests.RaceKind(record) or "other"
end

--- A race's time raced: its length when complete, else its time to combat end (DPS Race's
--- Format.RunSeconds on the race part). nil for a fight, or with neither.
--- @return number|nil seconds
function Races.Seconds(record)
    if not isRace(record) then return nil end
    local race = record.race
    local s = race.status == "complete" and race.length or race.endedAt
    return type(s) == "number" and s or nil
end

--- A race's score (the session's total, player and pet), nil for a fight.
--- @return number|nil
function Races.Score(record)
    if not isRace(record) then return nil end
    return type(record.race.score) == "number" and record.race.score or nil
end

--- Whether a race ended before its buzzer.
--- @return boolean
function Races.IsIncomplete(record)
    return isRace(record) and record.race.status ~= "complete"
end

-- The flags beyond a race's status: incomplete is Include incomplete's, and the chip's own word.
local STATUS_FLAGS = { incomplete = true, lost = true }

--- Whether a race carries a flag beyond its status (DPS Race's Runs.IsFlagged): a counted late
--- cast, a restart, a reload, a session matched by list, a shared session or a death. The late casts
--- are counted against the ignore list now (modules/RaceScoring.lua).
--- @return boolean
function Races.IsFlagged(record)
    if not isRace(record) then return false end
    for _, flag in ipairs(NS.RaceScoring.Flags(record.race)) do
        if not STATUS_FLAGS[flag.key] then return true end
    end
    return false
end

--- A race's flag chip key: "died" or "incomplete" for one that ended before the buzzer, "flagged"
--- for a complete race with a flag, nil for a clean complete race (or a fight). No best tag: the best
--- is only what a row is compared against (owner, 2026-11-10).
--- @return string|nil key
function Races.Status(record)
    if not isRace(record) then return nil end
    local race = record.race
    if race.status ~= "complete" then
        return (type(race.flags) == "table" and race.flags.died) and "died" or "incomplete"
    end
    if Races.IsFlagged(record) then return "flagged" end
    return nil
end

--- The chips a race row draws before its target's name (ruling X11): the race length in its color,
--- then its flag chip, each { text, color, icon }. nil for a fight, and on WoW Forever.
--- @return table|nil chips
function Races.Chips(record)
    if not (Races.On() and isRace(record)) then return nil end
    local length = record.race.length
    local out = { { text = NS.Format.Length(length), color = Races.LengthColor(length) } }
    local key = Races.Status(record)
    if key then
        local tag = Races.STATUS[key]
        out[2] = { text = L[tag.label], color = tag.color, icon = tag.icon }
    end
    return out
end

--- The fight detail's race parts for its "what" line: the dummy kind's label and the race's time
--- ("2:00 +11.1s", "0:20 / 1:00"). nil for a fight, and on WoW Forever.
--- @return string|nil kind, string|nil time
function Races.MetaParts(record)
    if not (Races.On() and isRace(record)) then return nil end
    return NS.Dummies.Label(Races.KindOf(record)), NS.Format.RaceTime(record.race)
end

-- ── the filters ─────────────────────────────────────────────────────────────────────────────────

--- The view keys this file judges, in the bar's order.
Races.FILTER_KEYS = { "kind", "length", "dummyKind", "hideFlagged", "includeIncomplete", "onlyBest" }

--- Whether the view lists races only (Retail, and the kind filter on Races): the race filters apply
--- then, and Bosses only stands aside (no dummy is a boss).
--- @param f table  the view's filters
function Races.UnderRaces(f)
    return Races.On() and type(f) == "table" and f.kind == "races"
end

local function onlyRaces(r, f) return Races.UnderRaces(f) and isRace(r) end

local PASS = {
    kind = function(r, v)
        if not Races.On() then return true end
        if v == "races" then return isRace(r) end
        if v == "fights" then return not isRace(r) end
        return true
    end,
    length = function(r, v, f) return v == "all" or not onlyRaces(r, f) or r.race.length == v end,
    dummyKind = function(r, v, f) return v == "all" or not onlyRaces(r, f) or Races.KindOf(r) == v end,
    hideFlagged = function(r, v, f) return not v or not onlyRaces(r, f) or not Races.IsFlagged(r) end,
    includeIncomplete = function(r, v, f) return v ~= false or not onlyRaces(r, f) or not Races.IsIncomplete(r) end,
    onlyBest = function(r, v, f) return not v or not onlyRaces(r, f) or NS.ResultsSource.IsBest(r) end,
}

--- Whether `record` passes the race filter `key` at `value` under the view's filters `f`.
--- @return boolean
function Races.Pass(key, record, value, f)
    local fn = PASS[key]
    if not fn then return true end
    if value == nil then value = NS.defaults.profile.results.view[key] end
    return fn(record, value, f) and true or false
end

-- ── the options ─────────────────────────────────────────────────────────────────────────────────

local function lengthOptions(records)
    local seen, values = {}, {}
    for _, r in ipairs(records) do
        local len = isRace(r) and r.race.length
        if type(len) == "number" and not seen[len] then
            seen[len] = true
            values[#values + 1] = len
        end
    end
    table.sort(values)
    local list = {}
    for i, len in ipairs(values) do list[i] = { value = len, label = NS.Format.Length(len) } end
    return list
end

-- The kinds present, in the catalog's order, "other" last.
local function kindOptions(records)
    local present, list = {}, {}
    for _, r in ipairs(records) do
        local k = Races.KindOf(r)
        if k then present[k] = true end
    end
    for _, key in ipairs(NS.Dummies.CATEGORIES) do
        if present[key] then list[#list + 1] = { value = key, label = NS.Dummies.Label(key) } end
    end
    if present.other then list[#list + 1] = { value = "other", label = NS.Dummies.Label("other") } end
    return list
end

--- The race dropdowns' options into `out` (Fights.Options'), faceted by `facet(key, lister)`. On WoW
--- Forever nothing is added.
function Races.Options(facet, out)
    if not Races.On() then return out end
    out.kind = {
        { value = "all", label = L["Fights and races"] }, { value = "fights", label = L["Fights only"] },
        { value = "races", label = L["Races only"] },
    }
    out.length = NS.ResultsFights.WithAll(facet("length", lengthOptions), L["Any race length"])
    out.dummyKind = NS.ResultsFights.WithAll(facet("dummyKind", kindOptions), L["All dummy kinds"])
    return out
end

-- ── the groupings (DPS Race's Time, Target + time, Spec + target + time) ───────────────────────
-- Ranks are strings (the table sorts the groups by them, ascending): shortest first, a row with no
-- race length (a fight) last, and the kinds in the catalog's order.

local NO_LENGTH = 9999999
local KIND_RANK = {}
for i, key in ipairs(NS.Dummies.CATEGORIES) do KIND_RANK[key] = i end

local function lengthOf(r)
    local len = isRace(r) and r.race.length
    return type(len) == "number" and len or nil
end

local function colored(text, color) return ("|c%s%s|r"):format(Tbl.Hex(color), text) end

local function lengthText(len)
    return colored(len and NS.Format.Length(len) or DASH, Races.LengthColor(len))
end

local function kindText(kind)
    return colored(NS.Dummies.Label(kind), Races.KIND_COLORS[kind] or Races.KIND_COLORS.other)
end

local function lengthGroup(r)
    local len = lengthOf(r)
    return "length:" .. tostring(len), L["Race length: %s"]:format(lengthText(len)),
        ("%07d"):format(len or NO_LENGTH)
end

local function kindRank(kind) return ("%03d"):format(kind and (KIND_RANK[kind] or 98) or 99) end

local function targetLengthGroup(r)
    local kind, len = Races.KindOf(r), lengthOf(r)
    local label = kind and (kindText(kind) .. SEP .. lengthText(len)) or lengthText(len)
    return "kind:" .. tostring(kind) .. "|" .. tostring(len), label, kindRank(kind) .. "|" .. ("%07d"):format(len or NO_LENGTH)
end

local function specTargetLengthGroup(r)
    local w = type(r.who) == "table" and r.who or {}
    local spec = Tbl.SpecInfo(w.specID, w.specName) or Tbl.ClassName(w.class)
    local kind, len = Races.KindOf(r), lengthOf(r)
    local parts = { colored(tostring(spec), Tbl.ClassColor(w.class)) }
    if kind then parts[2] = kindText(kind) end
    parts[#parts + 1] = lengthText(len)
    local key = ("spec:%s|%s|%s|%s"):format(tostring(w.class), tostring(w.specID), tostring(kind), tostring(len))
    local rank = ("%s|%s|%s|%07d"):format(tostring(Tbl.ClassName(w.class)):lower(), tostring(spec):lower(),
        kindRank(kind), len or NO_LENGTH)
    return key, table.concat(parts, SEP), rank
end

--- The race groupings, Retail only, after the fight groupings (Fights.GroupOrder).
Races.GROUP_SPECS = { { key = "length", clients = RETAIL }, { key = "targetLength", clients = RETAIL },
                      { key = "specTargetLength", clients = RETAIL } }
Races.GROUP_LABELS = { length = "Group: Race length", targetLength = "Group: Dummy kind + length",
                       specTargetLength = "Group: Spec + dummy kind + length" }
Races.GROUPS = {
    length = { of = lengthGroup },
    targetLength = { of = targetLengthGroup },
    specTargetLength = { of = specTargetLengthGroup },
}

--- A race's board as the date groupings' Delta measures it (Fights' boardGroup): its dummy kind and
--- race length, never its dummy's fights (spec §5: a race counts on its race board only). nil for a
--- fight. On both clients: it is the race DPS a race is ranked by.
--- @return string|nil key, string label, string rank
function Races.BoardGroup(r)
    if not isRace(r) then return nil end
    local kind, len = Races.KindOf(r), lengthOf(r)
    local label = NS.Dummies.Label(kind) .. SEP .. (len and NS.Format.Length(len) or DASH)
    return ("race:%s:%s"):format(tostring(kind), tostring(len)), label, label:lower()
end

-- ── the bar's second row ────────────────────────────────────────────────────────────────────────

Races.DROPDOWNS = { { key = "kind", width = 110 }, { key = "length", width = 88, races = true },
                    { key = "dummyKind", width = 100, races = true } }
Races.CHECKS = { { key = "hideFlagged", label = "Hide flagged" },
                 { key = "includeIncomplete", label = "Include incomplete" },
                 { key = "onlyBest", label = "Only best" } }
Races.CHECK_BOX = 20

--- A check box's width with its label (the box, 1 px, and the label's estimate: Tbl.BadgeWidth).
function Races.CheckWidth(label)
    return Races.CHECK_BOX + 1 + Tbl.BadgeWidth(label, false)
end

--- The bar's second row under `filters`, left to right from `x0`, `gap` apart: { key, kind
--- ("dropdown" | "check"), x, w }. On Retail the kind filter leads; under Races the race filters
--- follow it, else Bosses only does. On WoW Forever, Bosses only alone.
--- @return table items
function Races.Row2(filters, x0, gap)
    local items, x = {}, x0
    local function add(key, kind, w)
        items[#items + 1] = { key = key, kind = kind, x = x, w = w }
        x = x + w + gap
    end
    local under = Races.UnderRaces(filters)
    if Races.On() then
        for _, spec in ipairs(Races.DROPDOWNS) do
            if under or not spec.races then add(spec.key, "dropdown", spec.width) end
        end
    end
    if not under then
        add("bossesOnly", "check", Races.CheckWidth(L["Bosses only"]))
        return items
    end
    for _, spec in ipairs(Races.CHECKS) do add(spec.key, "check", Races.CheckWidth(L[spec.label])) end
    return items
end

--- Build the race controls on `bar` into `view.raceBar` (Retail only): the three dropdowns and the
--- three check boxes (`checkbox(view, bar, key, label)`, the bar's own). A load with no widget library
--- draws no dropdown, as the bar's others.
function Races.BuildBar(view, bar, checkbox)
    if not Races.On() then return end
    local rb = {}
    for _, spec in ipairs(Races.DROPDOWNS) do
        local dd = NS.MakeDropdown(bar, spec.width)
        if dd then
            dd.onSelect = function(value) view:SetFilter(spec.key, value) end
            rb[spec.key] = dd
        end
    end
    for _, spec in ipairs(Races.CHECKS) do rb[spec.key] = checkbox(view, bar, spec.key, L[spec.label]) end
    view.raceBar = rb
end

--- Place the second row by `plan.row2` (Fights.BarPlan), each control shown, every other one hidden.
function Races.LayoutBar(view, plan)
    local placed = {}
    local rb = view.raceBar or {}
    for _, item in ipairs(plan.row2) do
        local w = item.key == "bossesOnly" and view.bossesOnly or rb[item.key]
        if w then
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", view.bar, "TOPLEFT", item.x, plan.y + (item.kind == "dropdown" and 2 or 0))
            if item.kind == "dropdown" then w:SetWidth(item.w) end
            w:Show()
            placed[w] = true
        end
    end
    if view.bossesOnly and not placed[view.bossesOnly] then view.bossesOnly:Hide() end
    for _, w in pairs(rb) do
        if not placed[w] then w:Hide() end
    end
end

--- Put the race filters' values on their controls.
function Races.PaintBar(view, options)
    local rb = view.raceBar
    if not rb then return end
    for _, spec in ipairs(Races.DROPDOWNS) do
        local dd = rb[spec.key]
        if dd then
            dd:SetOptions(options[spec.key] or {})
            dd:SelectValue(view.filters[spec.key])
        end
    end
    for _, spec in ipairs(Races.CHECKS) do rb[spec.key]:SetChecked(view.filters[spec.key] == true) end
end

-- ── the cells' tooltips ─────────────────────────────────────────────────────────────────────────

local function dim(text) return { text, NS.Style.Rgb("ct.dim") } end

local TIP = {}

-- What the race DPS divides by: the race length, the time raced, or for a carried-on incomplete race
-- (ruling X16) the first hit to the fight's end, the span its stored DPS was taken over.
local function dpsBasis(r, dps)
    local race = r.race
    if race.status == "complete" then return L["The race's score over its race length."] end
    local flags = type(race.flags) == "table" and race.flags or {}
    local score = race.score
    if flags.carriedOn and type(score) == "number" and type(dps) == "number" and dps > 0 then
        return L["The race's score over %s, its first hit to the fight's end: combat came back inside the grace after it ended before the buzzer."]:format(NS.Format.Length(score / dps))
    end
    return L["The race's score over the time raced: combat ended before the buzzer."]
end

function TIP.dps(r)
    local dps = NS.RaceRecord.Dps(r)
    local lines = { L["%s DPS"]:format(NS.ResultsTips.Grouped(dps)), dpsBasis(r, dps) }
    if type(r.dps) == "number" then
        lines[#lines + 1] = dim(L["The fight around it: %s DPS over its own length."]:format(NS.ResultsTips.Grouped(r.dps)))
    end
    return lines
end

function TIP.damage(r)
    return { L["%s score"]:format(NS.ResultsTips.Grouped(Races.Score(r))),
             L["The race's score: the meter session's total, you and your pet, read after combat."] }
end

function TIP.len(r)
    local race = r.race
    if race.status ~= "complete" then
        return { L["%s of a %s race"]:format(NS.Format.Length(race.endedAt), NS.Format.Length(race.length)),
                 L["Combat ended before the buzzer."] }
    end
    local lines = { L["Race %s"]:format(NS.Format.Length(race.length)), L["The race length you picked."] }
    if type(race.tail) == "number" and race.tail >= 0.05 then
        lines[#lines + 1] = dim(L["Damage stopped %ss after the buzzer."]:format(NS.Format.Seconds(race.tail)))
    end
    return lines
end

--- A race cell's tooltip lines for column `key` (dps, damage, len), or nil for a fight or another
--- column: the cell then takes the fight's (modules/Results_Tips.lua).
--- @return table|nil
function Races.CellTip(key, record)
    local fn = TIP[key]
    if not (fn and isRace(record)) then return nil end
    return fn(record)
end

--- The target tooltip's race lines, appended to `lines` (Retail): the race's flags in red, the
--- ignored late casts dimmed.
function Races.TargetTip(record, lines)
    if not (Races.On() and isRace(record)) then return lines end
    local nameOf = NS.HudBreakdown and NS.HudBreakdown.SpellName
    for _, flag in ipairs(NS.RaceScoring.Flags(record.race, nameOf)) do
        lines[#lines + 1] = { flag.text, C.red[1], C.red[2], C.red[3] }
    end
    local ignored = NS.RaceScoring.IgnoredText(record.race, nameOf)
    if ignored then lines[#lines + 1] = dim(ignored) end
    return lines
end
