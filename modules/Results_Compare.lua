local _, NS = ...
-- modules/Results_Compare.lua — the compare (spec §7, mockup §7): a window from the Results detail's
-- *Compare* button that sets the fight beside another, figure by figure and spell by spell.
-- Adapted from DPS Race @045f479 (modules/Results_Compare.lua) without its race, and drawn as the
-- mockup draws it: its own window over the Results window, where DPS Race drew the compare inside
-- the detail behind a toggle.
--
-- THE OTHER FIGHT (Compare.Pick, the one answer the timeline, the gear view and this window read,
-- through the detail pane's CompareTarget). The fight picked from a row's right-click menu (*Compare
-- With This Fight*, Results.Pick) while it is still stored and is not the fight itself, on any board;
-- else the best on the fight's board (character x spec x board key, modules/Bests.lua); else, when the
-- fight IS that best, the runner-up on it; else none, and the detail's button is grayed. The pick is
-- session-only view state, never stored: it holds until *Clear pick* (here, while it is in use) or
-- the picked fight is deleted.
--
-- THE LAYOUT. A legend bar (this fight's label in yellow, the other's in blue and what it is, a note
-- when a picked fight is on another board, *Clear pick* at its right while a pick is in use); three
-- figure boxes, Damage, DPS and Length (the HUD's order), each "other >> this" and the change; the spell table, every
-- spell either fight cast matched by spell and caster (the pet's marked "(pet)"), each row the other's
-- total -> this one's, a blue and a yellow bar on one scale, and the change; the gear line under the
-- spells: the slots whose gear differs (Gear.ChangedSlots, with the item levels), and the *Different
-- loadout* mark when the two fights' talent loadouts differ; and *Trinkets and consumables* (v0.2 Task
-- C4): every item either fight used (ResultsUsage.Entries: gear first, hidden items and enchants never),
-- a line each, the other's uses then this one's, "not used" on a side without it. The table shows
-- MAX_ROWS rows at once and the mouse wheel scrolls it.
--
-- THE COLORS BY SIDE (v0.2 Task C4, plan D15). The sides are fixed whatever the other fight is (the
-- best, the runner-up or the pick): this fight is always yellow and the other always blue, DPS Race's
-- compare hues from the shared palette (NS.Constants.PALETTE): the bars THIS_BAR and BEST_BAR at BAR_A,
-- every figure and label of a side in THIS_TEXT or BEST_TEXT (escapes, Compare.SideText; the change
-- keeps its green and red). They are data hues, the same under every skin. The tooltips stay plain.
--
-- THE WINDOW is a modal of the ability timeline's kind (modules/Results_Timeline.lua): one strata above
-- the Results window, toplevel, the shared skin made opaque, in UISpecialFrames (Escape closes it
-- first), the Results window's dim cover up while it is open, its size fixed by its content, centered
-- over the Results window on every open and movable by its title bar while open, never stored.
-- `results.scale` acts on it. It closes with the Results window, at the stand-down and on a source
-- switch, and follows the detail (another fight, the pick changed or cleared).
--
-- PLAIN NUMBERS ONLY. Both fights are stored records (every figure went through NS.Secrets on its
-- way in), so they may be divided, compared and sorted. Pick, Target, Default, Spells, Pct, Kpis,
-- DifferentLoadout, SameBoard, BarWidths, ChangeText, PairText, SideText, GearText, UsageRows and Size
-- are pure over the source.

local Compare = { wanted = false }
NS.ResultsCompare = Compare

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT
local Tbl = NS.ResultsTable
local C = Tbl.COLORS
local TL = NS.ResultsTimeline
local PALETTE = NS.Constants.PALETTE

Compare.FRAME_NAME = "CombatTrailCompare"
Compare.WIDTH = 660
Compare.PAD = 12
Compare.LEGEND_H = 26
Compare.KPI_H = 60   -- three centered lines: the label, the figures, the change (owner, 2026-11-11)
Compare.KPI_GAP = 8
Compare.HEAD_H = 20         -- the spell table's header line
Compare.ROW_H = 22          -- one spell row
Compare.MAX_ROWS = 14       -- the rows shown at once; the wheel scrolls the rest
Compare.ICON = 16
Compare.BAR_H = 6           -- each of a row's two bars
Compare.GEAR_TITLE_H = 22
Compare.GEAR_LINE_H = 26
Compare.GEAR_ICON = 20
Compare.USAGE_TITLE_H = 22  -- the Trinkets and consumables heading
Compare.USAGE_ROW_H = 22    -- one used item
Compare.CLEAR_W = 78
Compare.CHIP_W = 112
-- The spell table's columns (mockup §7): the name, "other -> this", the bars, the change.
Compare.NAME_W = 200
Compare.FIGURE_W = 150
Compare.CHANGE_W = 70
Compare.COL_GAP = 8

local HEADER_H = Style.TITLE_BAR_H
local SEP = " \194\183 "
-- Between the other fight's figure and this one's: the mockup draws an arrow; the Latin-1 "»" stands in
-- for it, a mark every client font and skin font carries.
local ARROW = " \194\187 "
local DASH = "\226\128\148"

local ui        -- the built window
local pane      -- the detail pane the window follows
local hiding = false

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Compare", fmt, ...) end
end

-- ── pure: which fight ───────────────────────────────────────────────────────────────────────────

--- Whether a fight can take part in a compare: a stored record with its DPS.
function Compare.Usable(record)
    return type(record) == "table" and type(record.dps) == "number"
end

--- The default other fight: the best on `record`'s board among `records` (the source's fights by
--- default), or the runner-up on it when `record` holds the best; nil with neither.
--- @return table|nil other, string|nil kind  "best" | "runnerUp"
function Compare.Default(record, records)
    if not Compare.Usable(record) then return nil end
    local key = NS.Bests.Key(record)
    if not key then return nil end
    local all = records or NS.ResultsSource.All()
    local best = NS.Bests.Compute(all)[key]
    if best and best.id ~= record.id then return best, "best" end
    local runnerUp = NS.Bests.Compute(all, best)[key]
    if runnerUp and runnerUp.id ~= record.id then return runnerUp, "runnerUp" end
    return nil
end

--- The fight `record` is compared with: the picked fight `pickID` while it is stored, usable and not
--- `record` itself, else the default.
--- @return table|nil other, string|nil kind  "picked" | "best" | "runnerUp"
function Compare.Target(record, pickID)
    if not Compare.Usable(record) then return nil end
    local picked = pickID ~= nil and pickID ~= record.id and NS.ResultsSource.Get(pickID) or nil
    if Compare.Usable(picked) then return picked, "picked" end
    return Compare.Default(record)
end

--- `NS.ResultsCompare.Pick(record) -> other` (the plan's name): the target under the session's pick
--- (Results.Pick, "Compare With This Fight").
--- @return table|nil other, string|nil kind
function Compare.Pick(record)
    local R = NS.Results
    return Compare.Target(record, R and R.Pick and R.Pick() or nil)
end

--- Whether two fights sit on the same board (character, spec and board key).
function Compare.SameBoard(a, b)
    local ka = NS.Bests.Key(a)
    return ka ~= nil and ka == NS.Bests.Key(b)
end

--- Whether the two fights were fought with different talent loadouts: both recorded one, and they
--- differ (a loadout is stored once and named by its key, modules/Loadouts.lua). Unknown is false.
function Compare.DifferentLoadout(a, b)
    local la = type(a) == "table" and a.loadout or nil
    local lb = type(b) == "table" and b.loadout or nil
    if la == nil or lb == nil then return false end
    return la ~= lb
end

-- ── pure: the figures ───────────────────────────────────────────────────────────────────────────

local function num(v) return type(v) == "number" and v or nil end

--- `a` against `b` as a percentage of `b`; nil when either is missing or `b` is not above 0.
function Compare.Pct(a, b)
    a, b = num(a), num(b)
    if not (a and b) or b <= 0 then return nil end
    return (a / b - 1) * 100
end

local function merged(record)
    local d = type(record) == "table" and record.damage or nil
    return type(d) == "table" and num(d.merged) or nil
end

--- The figure boxes: Damage, DPS and Length (the HUD's Damage box left of its DPS box; owner,
--- 2026-11-11), each { key, a (this fight), b (the other), pct }.
--- @return table kpis
function Compare.Kpis(a, b)
    local out = {}
    for _, k in ipairs({
        { key = "damage", va = merged(a), vb = merged(b) },
        { key = "dps", va = num(a and a.dps), vb = num(b and b.dps) },
        { key = "length", va = num(a and a.duration), vb = num(b and b.duration) },
    }) do
        out[#out + 1] = { key = k.key, a = k.va, b = k.vb, pct = Compare.Pct(k.va, k.vb) }
    end
    return out
end

local function keyOf(s) return (s.isPet and "p" or "") .. tostring(s.spellID) end

-- A fight's damage by spell and caster ({ [key] = { spellID, pet, total } }), and its total.
local function bySpell(record)
    local out = {}
    if type(record) ~= "table" then return out end
    for _, s in ipairs(NS.Recorder.Spells(record)) do
        if s.spellID ~= nil then
            local k = keyOf(s)
            local e = out[k] or { spellID = s.spellID, pet = s.isPet == true, total = 0 }
            e.total = e.total + (num(s.total) or 0)
            out[k] = e
        end
    end
    return out
end

local function share(v, total)
    if v and total and total > 0 then return v / total * 100 end
    return nil
end

-- This fight's damage first (a spell it never cast last), then the other's, then the player before
-- the pet, then the spell ID.
local function rowBefore(x, y)
    local ax, ay = x.aTotal or -1, y.aTotal or -1
    if ax ~= ay then return ax > ay end
    local bx, by = x.bTotal or -1, y.bTotal or -1
    if bx ~= by then return bx > by end
    if x.pet ~= y.pet then return not x.pet end
    return (tonumber(x.spellID) or 0) < (tonumber(y.spellID) or 0)
end

--- `NS.ResultsCompare.Spells(a, b) -> rows` (the plan's): every spell either fight cast, matched by
--- spell and caster: { spellID, pet, aTotal, bTotal, aShare, bShare, delta, deltaPct }, by this
--- fight's damage, then the other's. A spell on one side only has nil total and share on the other;
--- `delta` is aTotal - bTotal, a missing side counting 0; `deltaPct` aTotal against bTotal, nil when
--- the other fight has none of it.
--- @return table rows
function Compare.Spells(a, b)
    local sa, sb = bySpell(a), bySpell(b)
    local ta, tb = merged(a), merged(b)
    local rows = {}
    local function add(k)
        local ea, eb = sa[k], sb[k]
        local e = ea or eb
        local va, vb = ea and ea.total, eb and eb.total
        rows[#rows + 1] = { spellID = e.spellID, pet = e.pet, aTotal = va, bTotal = vb,
                            aShare = share(va, ta), bShare = share(vb, tb),
                            delta = (va or 0) - (vb or 0), deltaPct = Compare.Pct(va or 0, vb) }
    end
    for k in pairs(sa) do add(k) end
    for k in pairs(sb) do if sa[k] == nil then add(k) end end
    table.sort(rows, rowBefore)
    return rows
end

--- The largest total either side holds across `rows` (0 with none): the length of a full bar.
function Compare.MaxTotal(rows)
    local top = 0
    for _, r in ipairs(rows or {}) do
        top = math.max(top, r.aTotal or 0, r.bTotal or 0)
    end
    return top
end

--- A row's two bars across `width` on the one scale `max`: the other fight's and this one's widths
--- (0 for a side without the spell).
--- @return number bw, number aw
function Compare.BarWidths(row, max, width)
    if not (max and max > 0) then return 0, 0 end
    local function w(v) return v and math.floor(width * math.min(1, v / max) + 0.5) or 0 end
    return w(row.bTotal), w(row.aTotal)
end

--- A change as the window writes it ("+2.1%"), a dash without one.
function Compare.ChangeText(pct)
    if type(pct) ~= "number" then return DASH end
    return NS.Format.SignedPct(pct)
end

--- A change's color: green up, red down, dim for none. `neutral` (the length: longer is neither
--- better nor worse) keeps the plain text color.
function Compare.ChangeColor(pct, neutral)
    if type(pct) ~= "number" or pct == 0 then return C.dim end
    if neutral then return C.text end
    return pct > 0 and C.green or C.red
end

local function figure(key, v)
    if type(v) ~= "number" then return DASH end
    if key == "length" then return NS.Format.Length(v) end
    return NS.Format.Number(v)
end

--- A figure pair, the other's then this fight's ("182.9K -> 186.9K"), plain (the tooltips').
function Compare.PairText(key, a, b)
    return figure(key, b) .. ARROW .. figure(key, a)
end

-- `s` in data hue `c`.
local function tint(c, s) return Style.HueEscape(c) .. s .. "|r" end

--- The pair as the window writes it: the other fight's figure in blue, this one's in yellow.
function Compare.SideText(key, a, b)
    return tint(PALETTE.BEST_TEXT, figure(key, b)) .. ARROW .. tint(PALETTE.THIS_TEXT, figure(key, a))
end

--- One changed slot's words for the gear line: its slot's name, then the item levels when they
--- differ ("Trinket 1 · 714 -> 727"), else what differs ("gem differs", "enchant differs", "another
--- item", "nothing worn" or "nothing worn before"). `ilvlA`, `ilvlB` are this fight's and the other's;
--- `tinted` writes the levels in their sides' hues (the window's line; plain, its width's estimate).
function Compare.GearText(change, ilvlA, ilvlB, tinted)
    local d = change.diff or {}
    local what
    if type(ilvlA) == "number" and type(ilvlB) == "number" and math.floor(ilvlA) ~= math.floor(ilvlB) then
        local b, a = ("%d"):format(math.floor(ilvlB)), ("%d"):format(math.floor(ilvlA))
        if tinted then b, a = tint(PALETTE.BEST_TEXT, b), tint(PALETTE.THIS_TEXT, a) end
        what = b .. ARROW .. a
    elseif change.item == nil then
        what = L["nothing worn"]
    elseif change.otherItem == nil then
        what = L["nothing worn before"]
    elseif d.item then
        what = L["another item"]
    elseif d.enchant then
        what = L["enchant differs"]
    else
        what = L["gem differs"]
    end
    return NS.ResultsGear.SlotName(change.slot) .. SEP .. what
end

--- The window's height for `n` spell rows, `gearLines` lines of changed gear and `usageLines` used
--- items (each at least one line: a "none" line stands in).
function Compare.Size(n, gearLines, usageLines)
    local shown = math.max(1, math.min(Compare.MAX_ROWS, n or 0))
    local height = HEADER_H + Compare.LEGEND_H + Compare.KPI_H + Compare.KPI_GAP + Compare.HEAD_H
        + shown * Compare.ROW_H + Compare.KPI_GAP + Compare.GEAR_TITLE_H
        + math.max(1, gearLines or 0) * Compare.GEAR_LINE_H
        + Compare.KPI_GAP + Compare.USAGE_TITLE_H + math.max(1, usageLines or 0) * Compare.USAGE_ROW_H
        + Compare.PAD
    return Compare.WIDTH, height
end

-- ── pure: what was used ─────────────────────────────────────────────────────────────────────────

-- A used entry's match across the fights: its item, or its kind for an entry with none (food).
local function usageKey(e)
    if e.itemID ~= nil then return "i" .. tostring(e.itemID) end
    return "k" .. tostring(e.kind)
end

--- `NS.ResultsCompare.UsageRows(a, b)`: every item either fight used (ResultsUsage.Entries: hidden
--- items and enchants never), matched by item (by kind with none): { itemID, kind, a = entry|nil,
--- b = entry|nil }. The gear (trinkets) first, then the consumables, each in this fight's order, then
--- the other's. Also whether each fight recorded its usage at all.
--- @return table rows, boolean aRecorded, boolean bRecorded
function Compare.UsageRows(a, b)
    local U = NS.ResultsUsage
    local ea, eb = U.Entries(a), U.Entries(b)
    local rows, at = {}, {}
    local function add(e, side)
        local k = usageKey(e)
        local row = at[k]
        if not row then
            row = { itemID = e.itemID, kind = e.kind }
            at[k], rows[#rows + 1] = row, row
        end
        if row[side] == nil then row[side] = e end
    end
    for _, gear in ipairs({ true, false }) do
        for _, e in ipairs(ea or {}) do if (e.kind == "gear") == gear then add(e, "a") end end
        for _, e in ipairs(eb or {}) do if (e.kind == "gear") == gear then add(e, "b") end end
    end
    return rows, ea ~= nil, eb ~= nil
end

-- ── the client's item data ──────────────────────────────────────────────────────────────────────

local function itemIcon(item)
    local parts = NS.ResultsGear.ParseItem(item)
    local get = type(C_Item) == "table" and C_Item.GetItemIconByID or nil
    if not (parts and type(get) == "function") then return NS.ResultsGear.MARK_FALLBACK end
    local ok, icon = pcall(get, parts.itemID)
    return ok and icon or NS.ResultsGear.MARK_FALLBACK
end

-- ── the window ──────────────────────────────────────────────────────────────────────────────────

local draw

local function buildChrome(f)
    f.title = Style.PlainText(f, FONT.TITLE, "CENTER")
    f.title:SetText(L["Compare"])
    ui.close = NS.MakeCloseButton(f, function() Compare.Hide() end)
    local drag = CreateFrame("Frame", nil, f)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    -- Moved for as long as it is open: nothing stored, the next open centers it again.
    drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    ui.drag = drag
    Style.Header(f, { title = f.title, drag = drag, right = { ui.close }, n = 1 })
end

local function buildLegend(f)
    local y = -HEADER_H - Compare.LEGEND_H / 2
    ui.legendA = Style.Text(f, FONT.TEXT, PALETTE.THIS_TEXT)
    ui.legendA:SetPoint("LEFT", f, "TOPLEFT", Compare.PAD, y)
    ui.legendB = Style.Text(f, FONT.TEXT, PALETTE.BEST_TEXT)
    ui.legendB:SetPoint("LEFT", ui.legendA, "RIGHT", 16, 0)
    ui.note = Style.Text(f, FONT.CAPTION, C.amber)
    ui.note:SetPoint("LEFT", ui.legendB, "RIGHT", 12, 0)
    ui.clear = Style.Button(f, L["Clear pick"], function() NS.Results.ClearPick() end)
    ui.clear:SetSize(Compare.CLEAR_W, 18)
    ui.clear:SetPoint("RIGHT", f, "TOPRIGHT", -Compare.PAD, y)
    ui.clear.tip = { L["Clear pick"], L["Compare with the best on this fight's board again."] }
end

local KPI_LABELS = { dps = "DPS", damage = "Damage", length = "Length" }

local function buildKpis(f)
    ui.kpis = {}
    local box = math.floor((Compare.WIDTH - 2 * Compare.PAD - 2 * Compare.KPI_GAP) / 3)
    local y = -(HEADER_H + Compare.LEGEND_H)
    for i, key in ipairs({ "damage", "dps", "length" }) do
        local card = NS.HudStates.Card(f)
        card:SetSize(box, Compare.KPI_H)
        card:SetPoint("TOPLEFT", f, "TOPLEFT", Compare.PAD + (i - 1) * (box + Compare.KPI_GAP), y)
        local k = { frame = card, key = key }
        k.label = Style.Text(card, FONT.CAPTION, nil, "CENTER")
        k.label:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -7)
        k.label:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -7)
        k.label:SetText(L[KPI_LABELS[key]])
        k.value = Style.Text(card, FONT.HEADING, C.text, "CENTER")
        k.value:SetPoint("LEFT", card, "LEFT", 8, 0)
        k.value:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        k.change = Style.Text(card, FONT.CAPTION, C.dim, "CENTER")
        k.change:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 8, 7)
        k.change:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 7)
        ui.kpis[i] = k
    end
end

-- The spell table's columns' left edges across the window.
local function columns()
    local x0 = Compare.PAD
    local figX = x0 + Compare.NAME_W + Compare.COL_GAP
    local barX = figX + Compare.FIGURE_W + Compare.COL_GAP
    local changeX = Compare.WIDTH - Compare.PAD - Compare.CHANGE_W
    return x0, figX, barX, changeX - Compare.COL_GAP - barX, changeX
end

local function buildHead(f)
    local x0, figX, barX, _, changeX = columns()
    local y = -(HEADER_H + Compare.LEGEND_H + Compare.KPI_H + Compare.KPI_GAP)
    ui.headY = y
    local function head(text, x, w, justify)
        local fs = Style.Text(f, FONT.HEADER, nil, justify)
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - 4)
        fs:SetWidth(w)
        fs:SetText(text)
        return fs
    end
    ui.headName = head(L["Spell"], x0, Compare.NAME_W)
    ui.headFigure = head("", figX, Compare.FIGURE_W)
    ui.headBars = head("", barX, 120)
    ui.headChange = head(L["Change"], changeX, Compare.CHANGE_W, "RIGHT")
    ui.rule = f:CreateTexture(nil, "ARTWORK")
    ui.rule:SetHeight(1)
    ui.rule:SetPoint("TOPLEFT", f, "TOPLEFT", Compare.PAD, y - Compare.HEAD_H)
    ui.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Compare.PAD, y - Compare.HEAD_H)
    Style.Fill(ui.rule, "ct.rule")
    ui.empty = Style.Text(f, FONT.TEXT, C.dim)
    ui.empty:SetPoint("TOPLEFT", f, "TOPLEFT", Compare.PAD, y - Compare.HEAD_H - 4)
    ui.empty:SetText(L["Neither fight recorded its spells."])
end

local function newRow(f)
    local _, figX, barX, barW, changeX = columns()
    local row = CreateFrame("Frame", nil, f)
    row:SetSize(Compare.WIDTH - 2 * Compare.PAD, Compare.ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetTexture(Style.WHITE)   -- white, so Style.Stripe's tint shows (as the fight list's)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(Compare.ICON, Compare.ICON)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    Style.EdgeIcon(row.icon)
    row.name = Style.Text(row, FONT.TEXT, C.text)
    row.name:SetPoint("LEFT", row, "LEFT", Compare.ICON + 6, 0)
    row.name:SetWidth(Compare.NAME_W - Compare.ICON - 6)
    local px = Compare.PAD
    row.figure = Style.Text(row, FONT.TEXT, C.text)
    row.figure:SetPoint("LEFT", row, "LEFT", figX - px, 0)
    row.figure:SetWidth(Compare.FIGURE_W)
    row.barB = row:CreateTexture(nil, "ARTWORK")
    row.barB:SetPoint("TOPLEFT", row, "LEFT", barX - px, Compare.BAR_H + 1)
    row.barB:SetHeight(Compare.BAR_H)
    Style.Fill(row.barB, PALETTE.BEST_BAR, PALETTE.BAR_A)
    row.barA = row:CreateTexture(nil, "ARTWORK")
    row.barA:SetPoint("TOPLEFT", row, "LEFT", barX - px, -1)
    row.barA:SetHeight(Compare.BAR_H)
    Style.Fill(row.barA, PALETTE.THIS_BAR, PALETTE.BAR_A)
    row.barW = barW
    row.change = Style.Text(row, FONT.TEXT, C.dim, "RIGHT")
    row.change:SetPoint("LEFT", row, "LEFT", changeX - px, 0)
    row.change:SetWidth(Compare.CHANGE_W)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.data then return end
        Tbl.SpellTip(ui.frame, self, self.data.spellID, Compare.RowLines(self.data))
    end)
    row:SetScript("OnLeave", function() Tbl.HideTip() end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) Compare.Scroll(delta) end)
    return row
end

local function buildGear(f)
    ui.gearTitle = Style.Text(f, FONT.SECTION)
    ui.gearTitle:SetText(L["Gear changed"])
    ui.gearNone = Style.Text(f, FONT.TEXT, C.dim)
    ui.gearItems = {}
    ui.chip = CreateFrame("Frame", nil, f, "BackdropTemplate")
    ui.chip:SetSize(Compare.CHIP_W, Tbl.CHIP_H)
    Style.TintBox(ui.chip, C.amber, Style.BADGE_EDGE_A)
    ui.chip.text = Style.Text(ui.chip, FONT.TEXT, C.amber, "CENTER")
    ui.chip.text:SetPoint("CENTER", ui.chip, "CENTER", 0, 0)
    ui.chip.text:SetText(L["Different loadout"])
    ui.chip:EnableMouse(true)
    ui.chip:SetScript("OnEnter", function(self)
        local lines = Compare.LoadoutLines(ui.record, ui.other)
        if lines then Tbl.SideTip(ui.frame, self, lines) end
    end)
    ui.chip:SetScript("OnLeave", function() Tbl.HideTip() end)
end

local function buildUsage(f)
    ui.usageTitle = Style.Text(f, FONT.SECTION)
    ui.usageTitle:SetText(L["Trinkets and consumables"])
    ui.usageNone = Style.Text(f, FONT.TEXT, C.dim)
    ui.usageLines = {}
end

-- A close-stack close, a frame later: the Results window's cover goes unless the window is open again.
local function settle()
    if Compare.IsShown() then return end
    NS.Results.SetCovered(false)
    NS.Results.StepAsideForTree()
end

local function onHide()
    Tbl.HideTip()
    if hiding or (ui and ui.frame:IsShown()) then return end
    -- Escape (UISpecialFrames): the player closed it. The cover stays until the close stack is done,
    -- so the Results window, hidden by the same Escape, still sees it and shows again.
    Compare.wanted = false
    if C_Timer and C_Timer.After then C_Timer.After(0, settle) else settle() end
end

local function ensureWindow()
    if ui then return ui end
    local f = CreateFrame("Frame", Compare.FRAME_NAME, UIParent, "BackdropTemplate")
    ui = { frame = f, rows = {}, gearItems = {}, usageLines = {}, offset = 0, data = {} }
    f:Hide()
    f:SetFrameStrata(NS.Constants.LAYERS.STRATA.MODAL)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetToplevel(true)
    buildChrome(f)
    buildLegend(f)
    buildKpis(f)
    buildHead(f)
    buildGear(f)
    buildUsage(f)
    NS.Skin.Shell(f, TL.SHELL)
    f:SetScript("OnHide", onHide)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) Compare.Scroll(delta) end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Compare.FRAME_NAME) end
    debug("window built")
    return ui
end

-- ── the words in the tooltips ───────────────────────────────────────────────────────────────────

--- What follows the client's spell tooltip on a row: each fight's total and share, and the change.
function Compare.RowLines(row)
    local function side(label, total, pct)
        if not total then return L["%s: not cast"]:format(label) end
        return L["%s: %s (%s of its damage)"]:format(label, NS.Format.Number(total), NS.Format.Pct(pct or 0))
    end
    local lines = { "", side(L["This fight"], row.aTotal, row.aShare),
                    side(ui and ui.otherKind or L["Best"], row.bTotal, row.bShare) }
    if row.deltaPct then lines[#lines + 1] = L["Change: %s"]:format(Compare.ChangeText(row.deltaPct)) end
    if row.pet then lines[#lines + 1] = L["Cast by your pet."] end
    return lines
end

--- The Different loadout mark's tooltip: each fight's loadout by name.
function Compare.LoadoutLines(record, other)
    local Lo = NS.ResultsLoadout
    if not (record and other) then return nil end
    return { L["Different loadout"],
             L["This fight: %s"]:format(Lo.TalentsText(Lo.TalentsOf(record), record.who)),
             L["The other fight: %s"]:format(Lo.TalentsText(Lo.TalentsOf(other), other.who)) }
end

-- ── drawing ─────────────────────────────────────────────────────────────────────────────────────

local function fillLegend(record, other, kind)
    local D = NS.ResultsTimelineData
    ui.legendA:SetText(D.ThisLabel(record))
    ui.otherKind = other and D.KindLabel(kind) or nil
    ui.legendB:SetText(other and D.OtherLabel(other, kind) or L["No fight to compare with"])
    local elsewhere = kind == "picked" and not Compare.SameBoard(record, other)
    ui.note:SetText(elsewhere and L["On another board"] or "")
    local R = NS.Results
    local pickID = R.Pick()
    ui.clear:SetShown(pickID ~= nil and NS.ResultsSource.Get(pickID) ~= nil)
    local otherWord = tint(PALETTE.BEST_TEXT, ui.otherKind or L["Best"])
    ui.headFigure:SetText(otherWord .. ARROW .. tint(PALETTE.THIS_TEXT, L["this"]))
    ui.headBars:SetText(otherWord .. " / " .. tint(PALETTE.THIS_TEXT, L["This"]))
end

local function fillKpis(record, other)
    for i, k in ipairs(Compare.Kpis(record, other)) do
        local box = ui.kpis[i]
        box.value:SetText(Compare.SideText(k.key, k.a, k.b))
        box.change:SetText(k.pct and Compare.ChangeText(k.pct) or "")
        Style.Paint(box.change, Compare.ChangeColor(k.pct, k.key == "length"))
    end
end

local function fillRow(row, data, index)
    row.data = data
    Style.Stripe(row.bg, index)
    row.icon:SetTexture(NS.HudBreakdown.SpellIcon(data.spellID))
    row.name:SetText(NS.ResultsTimelineData.Name({ spellID = data.spellID, pet = data.pet }))
    row.figure:SetText(Compare.SideText("damage", data.aTotal, data.bTotal))
    local bw, aw = Compare.BarWidths(data, ui.maxTotal, row.barW)
    row.barB:SetWidth(math.max(1, bw))
    row.barB:SetShown(bw > 0)
    row.barA:SetWidth(math.max(1, aw))
    row.barA:SetShown(aw > 0)
    row.change:SetText(Compare.ChangeText(data.deltaPct))
    Style.Paint(row.change, Compare.ChangeColor(data.deltaPct))
end

-- The rows on show from the scroll offset, each pooled by its place.
local function layoutRows()
    local top = ui.headY - Compare.HEAD_H - 2
    local shown = math.min(Compare.MAX_ROWS, #ui.data)
    for i = 1, shown do
        local row = ui.rows[i] or newRow(ui.frame)
        ui.rows[i] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", Compare.PAD, top - (i - 1) * Compare.ROW_H)
        fillRow(row, ui.data[i + ui.offset], i + ui.offset)
        row:Show()
    end
    for i = shown + 1, #ui.rows do
        ui.rows[i].data = nil
        ui.rows[i]:Hide()
    end
    ui.empty:SetShown(#ui.data == 0)
    return top - math.max(1, shown) * Compare.ROW_H
end

local function gearItem(i)
    local g = ui.gearItems[i]
    if g then return g end
    g = { icon = ui.frame:CreateTexture(nil, "ARTWORK"), text = Style.Text(ui.frame, FONT.TEXT, C.text) }
    g.icon:SetSize(Compare.GEAR_ICON, Compare.GEAR_ICON)
    Style.EdgeIcon(g.icon)
    g.text:SetPoint("LEFT", g.icon, "RIGHT", 6, 0)
    ui.gearItems[i] = g
    return g
end

-- The changed slots, flowed across the window in lines, the Different loadout mark at the first
-- line's right. Answers how many lines they took.
local function layoutGear(y)
    local G = NS.ResultsGear
    ui.gearTitle:ClearAllPoints()
    ui.gearTitle:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", Compare.PAD, y)
    local different = Compare.DifferentLoadout(ui.record, ui.other)
    ui.chip:SetShown(different)
    ui.chip:ClearAllPoints()
    ui.chip:SetPoint("TOPRIGHT", ui.frame, "TOPRIGHT", -Compare.PAD, y - 2)
    -- With the item levels, so an upgraded item (the same item ID) counts as changed gear too.
    local changes = ui.other and G.ChangedSlots(ui.record, ui.other, G.IlvlOf) or {}
    local recorded = NS.Loadouts.GearOf(ui.record) ~= nil and NS.Loadouts.GearOf(ui.other) ~= nil
    ui.gearNone:SetShown(#changes == 0)
    ui.gearNone:SetText(recorded and L["No gear changed."] or L["Gear not recorded for both fights."])
    ui.gearNone:ClearAllPoints()
    ui.gearNone:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", Compare.PAD, y - Compare.GEAR_TITLE_H)
    local x, line, right = Compare.PAD, 0, Compare.WIDTH - Compare.PAD
    for i, change in ipairs(changes) do
        local g = gearItem(i)
        local ilvlA, ilvlB = G.IlvlOf(change.item), G.IlvlOf(change.otherItem)
        local text = Compare.GearText(change, ilvlA, ilvlB, true)
        local w = Compare.GEAR_ICON + 6 + Tbl.BadgeWidth(Compare.GearText(change, ilvlA, ilvlB), false) + 12
        if x > Compare.PAD and x + w > right then x, line = Compare.PAD, line + 1 end
        g.icon:ClearAllPoints()
        g.icon:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", x, y - Compare.GEAR_TITLE_H - line * Compare.GEAR_LINE_H)
        g.icon:SetTexture(itemIcon(change.item or change.otherItem))
        g.text:SetText(text)
        g.icon:Show()
        g.text:Show()
        x = x + w
    end
    for i = #changes + 1, #ui.gearItems do
        ui.gearItems[i].icon:Hide()
        ui.gearItems[i].text:Hide()
    end
    return #changes == 0 and 1 or line + 1
end

-- A used item's hover: the client's item tooltip (pcall'd), then each side's uses in its hue.
local function usageTip(line)
    local tt, d = GameTooltip, line.data
    if not (tt and d) then return end
    tt:SetOwner(line, "ANCHOR_RIGHT")
    local shown = d.itemID and tt.SetItemByID and pcall(tt.SetItemByID, tt, d.itemID)
    if not shown then tt:SetText(NS.ResultsUsage.Name(d.a or d.b), Style.Rgb("gtip.value")) end
    tt:AddLine(L["This fight: %s"]:format(line.this:GetText() or ""), Style.Rgb(PALETTE.THIS_TEXT))
    tt:AddLine(L["The other fight: %s"]:format(line.other:GetText() or ""), Style.Rgb(PALETTE.BEST_TEXT))
    tt:Show()
end

local function usageLine(i)
    local u = ui.usageLines[i]
    if u then return u end
    local _, figX, barX, barW = columns()
    local px = Compare.PAD
    u = CreateFrame("Frame", nil, ui.frame)
    u:SetSize(Compare.WIDTH - 2 * Compare.PAD, Compare.USAGE_ROW_H)
    u.icon = u:CreateTexture(nil, "ARTWORK")
    u.icon:SetSize(Compare.ICON, Compare.ICON)
    u.icon:SetPoint("LEFT", u, "LEFT", 0, 0)
    Style.EdgeIcon(u.icon)
    u.name = Style.Text(u, FONT.TEXT, C.text)
    u.name:SetPoint("LEFT", u, "LEFT", Compare.ICON + 6, 0)
    u.name:SetWidth(Compare.NAME_W - Compare.ICON - 6)
    u.other = Style.Text(u, FONT.TEXT, PALETTE.BEST_TEXT)
    u.other:SetPoint("LEFT", u, "LEFT", figX - px, 0)
    u.other:SetWidth(Compare.FIGURE_W)
    u.this = Style.Text(u, FONT.TEXT, PALETTE.THIS_TEXT)
    u.this:SetPoint("LEFT", u, "LEFT", barX - px, 0)
    u.this:SetWidth(barW)
    u:EnableMouse(true)
    u:SetScript("OnEnter", usageTip)
    u:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    ui.usageLines[i] = u
    return u
end

-- One side's uses: the entry's detail in the side's hue, else a dim "not used" ("not recorded" when
-- that fight kept no usage).
local function sideUses(fs, e, recorded, hue)
    if e then
        fs:SetText(NS.ResultsUsage.Detail(e))
        Style.Paint(fs, hue)
    else
        fs:SetText(recorded and L["not used"] or L["not recorded"])
        Style.Paint(fs, C.dim)
    end
end

-- The used items, a line each under their heading. Answers how many lines they took.
local function layoutUsage(y)
    local U = NS.ResultsUsage
    ui.usageTitle:ClearAllPoints()
    ui.usageTitle:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", Compare.PAD, y)
    local rows, aRec, bRec = {}, false, false
    if ui.other then rows, aRec, bRec = Compare.UsageRows(ui.record, ui.other) end
    for i, r in ipairs(rows) do
        local u = usageLine(i)
        u.data = r
        u:ClearAllPoints()
        u:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", Compare.PAD, y - Compare.USAGE_TITLE_H - (i - 1) * Compare.USAGE_ROW_H)
        u.icon:SetTexture(U.Icon(r.a or r.b))
        u.name:SetText(U.Name(r.a or r.b))
        sideUses(u.other, r.b, bRec, PALETTE.BEST_TEXT)
        sideUses(u.this, r.a, aRec, PALETTE.THIS_TEXT)
        u:Show()
    end
    for i = #rows + 1, #ui.usageLines do
        ui.usageLines[i].data = nil
        ui.usageLines[i]:Hide()
    end
    ui.usageNone:SetShown(#rows == 0)
    ui.usageNone:SetText((aRec or bRec) and L["None used"] or L["Usage not recorded for both fights."])
    ui.usageNone:ClearAllPoints()
    ui.usageNone:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", Compare.PAD, y - Compare.USAGE_TITLE_H)
    return #rows
end

-- Centered over the Results window (its anchor and its size in the view shown).
local function applyPlacement()
    local point, relativePoint, x, y, width, height = NS.Results.Placement()
    local ch = ui.height or select(2, Compare.Size(0, 1, 1))
    local cx, cy = NS.ResultsGear.CenterOver(point, x, y, width, height, Compare.WIDTH, ch)
    ui.frame:ClearAllPoints()
    ui.frame:SetPoint(point, UIParent, relativePoint, cx, cy)
end

-- Read the followed detail's fight and compare target, and draw them.
function draw()
    local record = pane and type(pane.Record) == "function" and pane:Record() or nil
    local other, kind
    if record then
        if type(pane.CompareTarget) == "function" then other, kind = pane:CompareTarget(true)
        else other, kind = Compare.Pick(record) end
    end
    if ui.record ~= record or ui.other ~= other then ui.offset = 0 end
    ui.record, ui.other, ui.kind = record, other, kind
    if not record then return end
    ui.data = other and Compare.Spells(record, other) or {}
    ui.maxTotal = Compare.MaxTotal(ui.data)
    ui.offset = math.max(0, math.min(ui.offset, #ui.data - Compare.MAX_ROWS))
    fillLegend(record, other, kind)
    fillKpis(record, other)
    local y = layoutRows() - Compare.KPI_GAP
    local lines = layoutGear(y)
    local used = layoutUsage(y - Compare.GEAR_TITLE_H - lines * Compare.GEAR_LINE_H - Compare.KPI_GAP)
    ui.width, ui.height = Compare.Size(#ui.data, lines, used)
    ui.frame:SetSize(ui.width, ui.height)
    Compare.ApplyScale()
    debug("drawn: %d spells", #ui.data)
end

-- ── the public surface ──────────────────────────────────────────────────────────────────────────

--- Open the window on the detail pane `p` (the detail's Compare button) and follow it from now on.
--- Another modal over the Results window closes first (one cover, one modal).
--- @return boolean opened
function Compare.Open(p)
    if NS.IsStoodDown() then return false end
    NS.Results.CloseModals("ResultsCompare")
    pane = p
    Compare.wanted = true
    ensureWindow()
    ui.frame:Show()
    if ui.frame.Raise then ui.frame:Raise() end
    NS.RaiseStaticPopups()
    NS.Results.SetCovered(true)
    draw()
    applyPlacement()
    return true
end

--- Close the window (its close control, the Results window closing): the Results window's cover goes.
function Compare.Hide()
    local was = Compare.wanted
    Compare.wanted = false
    if ui and ui.frame:IsShown() then
        hiding = true
        ui.frame:Hide()
        hiding = false
    end
    if was then
        Tbl.HideTip()
        NS.Results.SetCovered(false)
    end
end

--- Whether the window is open.
function Compare.IsShown()
    return Compare.wanted and ui ~= nil and ui.frame:IsShown() == true
end

--- The detail pane `p` drew a fight or its compare target changed (a pick made or cleared): redraw
--- while open on it. A pane left with no fight closes the window.
function Compare.DetailChanged(p)
    if p ~= pane or not Compare.IsShown() then return end
    if not (type(p.Record) == "function" and p:Record()) then return Compare.Hide() end
    draw()
end

--- One mouse-wheel notch over the window (`delta` > 0 scrolls up), clamped to the spells.
function Compare.Scroll(delta)
    if not (ui and Compare.IsShown()) then return end
    local top = math.max(0, #ui.data - Compare.MAX_ROWS)
    local offset = math.max(0, math.min(top, ui.offset - (delta or 0) * 3))
    if offset == ui.offset then return end
    ui.offset = offset
    layoutRows()
end

--- The Results window's scale on this one (it opens over that window, in its units).
function Compare.ApplyScale()
    local scale = tonumber(NS.GetSetting("results.scale"))
    if ui and scale and scale > 0 then ui.frame:SetScale(scale) end
end

--- The Master controls' Reset position: nothing is stored, so an open window centers again.
function Compare.ResetPosition()
    if Compare.IsShown() then applyPlacement() end
end

--- The spell rows drawn now, for the suites: { row frame, ... } (shown ones only).
function Compare.Rows()
    local out = {}
    for _, row in ipairs(ui and ui.rows or {}) do
        if row:IsShown() then out[#out + 1] = row end
    end
    return out
end

--- The used-item lines drawn now, for the suites: { line frame (name, other, this), ... } (shown ones).
function Compare.UsageLines()
    local out = {}
    for _, u in ipairs(ui and ui.usageLines or {}) do
        if u:IsShown() then out[#out + 1] = u end
    end
    return out
end

--- The built window, for the suites (nil until first opened).
function Compare.__ui() return ui end
