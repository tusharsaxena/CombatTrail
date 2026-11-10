local _, NS = ...
-- modules/Results_Gear.lua — the gear view (spec §7, mockup §8): a window from the Results detail's
-- *Gear view* button that lays the fight's gear out as the character panel does, without the model,
-- with the stats the fight was pulled with where the model would be. Ported from DPS Race @045f479
-- (modules/Results_Gear.lua) for Combat Trail's record: its gear is an equipment set of trimmed item
-- strings (record.gearSet, read through Loadouts.GearOf), each handed to the client as "item:<string>".
--
-- THE LAYOUT. A legend bar (this fight's label and item level in gold, the compared fight's in blue),
-- then three columns: on the left head, neck, shoulders, back, chest, shirt and tabard (each only when
-- the fight has one: neither is recorded today, Loadouts.GEAR_SLOTS) and wrists; on the right hands,
-- waist, legs, feet, both rings and both trinkets (the ranged slot under them, only when filled); main
-- hand and off hand side by side under the middle. Each slot: the item's icon in its quality's edge, its
-- item level over the icon, its name beside it toward the middle, and under the name its marks: the
-- enchant's (MARK_ENCHANT) and each gem's own icon, read from the stored item string (ParseItem: the
-- enchant and gem IDs after the item ID). Hovering a slot shows the client's item tooltip (and what
-- differs from the compared fight); Shift-click links it in chat. The middle column is Stats.Groups
-- (modules/Stats.lua): Primary, Secondary and Tertiary, each value against the compared fight's, with
-- dashes for a value the fight did not record (on WoW Forever, with no specialization, the primary
-- stat row is a dash).
--
-- THE COMPARE. Against the fight the detail compares with (the pane's CompareTarget, the one answer
-- the timeline and the compare window read too): a slot whose item differs (another item, or one side
-- empty) wears an amber wash; its item level reads green when higher than the compared fight's and
-- red when lower; an enchant or gems that differ on the same item get an amber edge on their marks,
-- and a missing one shows as a dim mark with that edge (Marks). Each stat row shows its delta (+ green,
-- - red); none without the other fight's stats. ChangedSlots is the same comparison over two records,
-- for the compare window's "Gear changed" line.
--
-- THE WINDOW is a modal of the ability timeline's kind (modules/Results_Timeline.lua): one strata above
-- the Results window (LAYERS.STRATA.MODAL), toplevel, the shared skin made opaque (its SHELL), in
-- UISpecialFrames (Escape closes it first), the Results window's dim cover up while it is open. Its
-- size is fixed by its content (Size), never resizable; every open centers it over the Results window
-- (CenterOver), movable by its title bar for as long as it is open, never stored. `results.scale` acts
-- on it. It closes with the Results window, at the stand-down and on a source switch.
--
-- PLAIN DATA ONLY: stored item strings and the fight's plain stats. Every position comes from the
-- constants here (Cells, Size), never read back off a frame; ParseItem, SlotDiff, ChangedSlots, Marks,
-- NoteLines, Cells, Size and CenterOver are pure.

local Gear = { wanted = false }
NS.ResultsGear = Gear

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT
local Tbl = NS.ResultsTable
local C = Tbl.COLORS
local TL = NS.ResultsTimeline

Gear.FRAME_NAME = "CombatTrailGear"
Gear.PAD = 12
Gear.LEGEND_H = 26
Gear.SLOT_W = 190         -- a slot: the icon and its name beside it
Gear.ICON = 36
Gear.PITCH = 44           -- one slot row
Gear.TEXT_GAP = 6         -- between the icon's edge and the name
Gear.MID_W = 300          -- the stats column
Gear.COL_GAP = 14         -- between the columns, and between the two weapons
Gear.WEAPON_GAP = 10      -- above the weapons
Gear.MARK = 12            -- an enchant or gem mark, inside its 1px edge
Gear.MARK_GAP = 3
-- The stats column: a group's heading line, a row, the gap between groups, and its three cells.
Gear.GROUP_H = 22
Gear.STAT_H = 16
Gear.GROUP_GAP = 8
Gear.LABEL_W, Gear.VALUE_W, Gear.DELTA_W = 104, 98, 98

-- The character panel's columns. OPTIONAL slots show only when the fight has an item there.
Gear.LEFT = { 1, 2, 3, 15, 5, 4, 19, 9 }
Gear.RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14, 18 }
Gear.WEAPONS = { 16, 17 }
local OPTIONAL = { [4] = true, [19] = true, [18] = true }

-- The enchant's mark: the Enchanting profession's icon (Trade_Engraving); a gem's is its own icon,
-- the question mark when the client has none for it. File ids.
Gear.MARK_ENCHANT = 136244
Gear.MARK_FALLBACK = 134400

-- Each slot's name, as the compare window's gear line says it.
Gear.SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist", [7] = "Legs",
    [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1",
    [14] = "Trinket 2", [15] = "Back", [16] = "Main hand", [17] = "Off hand", [18] = "Ranged", [19] = "Tabard",
}

--- A slot's name ("Trinket 1").
function Gear.SlotName(slot)
    local name = Gear.SLOT_NAMES[slot]
    return name and L[name] or L["Slot %d"]:format(tonumber(slot) or 0)
end

local HEADER_H = Style.TITLE_BAR_H
local CHANGED_A = 0.16    -- a changed item's caution wash
local SEP = " \194\183 "

local ui        -- the built window
local pane      -- the detail pane the window follows
local hiding = false

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Gear", fmt, ...) end
end

-- ── pure ────────────────────────────────────────────────────────────────────────────────────────

--- An item's parts from a stored item string (trimmed, as modules/Loadouts.lua keeps it), an
--- "item:" string or a full link: its item ID, its enchant ID and its gem IDs, in socket order. nil
--- for anything that is not an item.
--- @return table|nil parts  { itemID, enchantID, gems = { id, ... } }
function Gear.ParseItem(item)
    if type(item) ~= "string" then return nil end
    local body = item:match("item:([%-%d:]*)") or item:match("^([%-%d:]+)$")
    if not body or body == "" then return nil end
    local fields, i = {}, 0
    for field in (body .. ":"):gmatch("([^:]*):") do
        i = i + 1
        fields[i] = tonumber(field)
    end
    if not fields[1] then return nil end
    local gems = {}
    for g = 3, 6 do
        if fields[g] and fields[g] > 0 then gems[#gems + 1] = fields[g] end
    end
    local enchant = fields[2]
    return { itemID = fields[1], enchantID = enchant and enchant > 0 and enchant or nil, gems = gems }
end

local function gemKey(parts)
    return table.concat(parts.gems, ",")
end

--- What differs in one slot between this fight's and the compared fight's: each side `{ item, ilvl }`
--- (a side with no item: an empty slot). `item` (another item, or one side empty), `ilvl` (1 higher,
--- -1 lower, 0 the same or unknown), and on the same item `enchant` and `gems`. nil without both sides.
--- @return table|nil diff
function Gear.SlotDiff(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return nil end
    local pa, pb = Gear.ParseItem(a.item), Gear.ParseItem(b.item)
    local d = { ilvl = 0 }
    if type(a.ilvl) == "number" and type(b.ilvl) == "number" then
        d.ilvl = a.ilvl > b.ilvl and 1 or (a.ilvl < b.ilvl and -1 or 0)
    end
    if not (pa and pb) then
        d.item = (pa ~= nil) ~= (pb ~= nil)
        return d
    end
    d.item = pa.itemID ~= pb.itemID
    if not d.item then
        d.enchant = pa.enchantID ~= pb.enchantID
        d.gems = gemKey(pa) ~= gemKey(pb)
    end
    return d
end

-- The record's gear: its stored set, else a sample's inline gear (Loadouts.GearOf).
local function gearOf(record)
    return NS.Loadouts.GearOf(record)
end

-- One side of a slot for SlotDiff: its item and, given `ilvlOf`, its item level.
local function side(item, ilvlOf)
    return { item = item, ilvl = ilvlOf and item and ilvlOf(item) or nil }
end

--- The slots whose gear differs between `record` and `other` (another item, one side empty, or on
--- the same item another enchant, other gems or, given `ilvlOf`, another item level: an upgrade), in
--- the character frame's order (ResultsLoadout.ORDER): { { slot, item, otherItem, diff } }.
--- `ilvlOf(item)` (optional) gives each side's item level for `diff.ilvl`. Empty when either fight
--- has no gear recorded.
--- @return table changed
function Gear.ChangedSlots(record, other, ilvlOf)
    local a, b, out = gearOf(record), gearOf(other), {}
    if not (a and b) then return out end
    -- One set on both fights: the same item strings, so nothing differs (not even an item level).
    if a == b then return out end
    for _, slot in ipairs(NS.ResultsLoadout.ORDER) do
        local ia, ib = a[slot], b[slot]
        local d = (ia ~= nil or ib ~= nil) and Gear.SlotDiff(side(ia, ilvlOf), side(ib, ilvlOf)) or nil
        if d and (d.item or d.enchant or d.gems or d.ilvl ~= 0) then
            out[#out + 1] = { slot = slot, item = ia, otherItem = ib, diff = d }
        end
    end
    return out
end

--- A slot's marks in order: its enchant, then each gem ({ kind, id, changed }); a missing enchant or
--- missing gems the compared fight had show as one mark each with `missing`.
--- @param parts table|nil  ParseItem's
--- @param diff table|nil  SlotDiff's
--- @return table marks
function Gear.Marks(parts, diff)
    local out = {}
    if not parts then return out end
    diff = diff or {}
    if parts.enchantID then
        out[#out + 1] = { kind = "enchant", id = parts.enchantID, changed = diff.enchant == true }
    elseif diff.enchant then
        out[#out + 1] = { kind = "enchant", missing = true, changed = true }
    end
    for _, id in ipairs(parts.gems) do out[#out + 1] = { kind = "gem", id = id, changed = diff.gems == true } end
    if #parts.gems == 0 and diff.gems then out[#out + 1] = { kind = "gem", missing = true, changed = true } end
    return out
end

--- The lines a slot's tooltip adds under the item for what differs from `label`'s fight (its item's
--- name `otherName`, nil for an empty slot).
--- @return table lines
function Gear.NoteLines(diff, label, otherName)
    local lines = {}
    if type(diff) ~= "table" then return lines end
    if diff.item then
        lines[#lines + 1] = otherName and L["Changed: %s wore %s."]:format(label, otherName)
            or L["Changed: %s had nothing here."]:format(label)
    end
    if diff.enchant then lines[#lines + 1] = L["The enchant differs from %s's."]:format(label) end
    if diff.gems then lines[#lines + 1] = L["The gems differ from %s's."]:format(label) end
    if diff.ilvl ~= 0 then
        lines[#lines + 1] = diff.ilvl > 0 and L["Higher item level than %s's."]:format(label)
            or L["Lower item level than %s's."]:format(label)
    end
    return lines
end

local function columnRows(gear, slots)
    local list = {}
    for _, slot in ipairs(slots) do
        if not OPTIONAL[slot] or gear[slot] ~= nil then list[#list + 1] = slot end
    end
    return list
end

--- The window's size for `gear`: three columns across, the taller side column's rows and the weapons'
--- row down.
--- @return number width, number height, number rows
function Gear.Size(gear)
    gear = type(gear) == "table" and gear or {}
    local rows = math.max(#columnRows(gear, Gear.LEFT), #columnRows(gear, Gear.RIGHT))
    local width = 2 * Gear.PAD + 2 * Gear.SLOT_W + Gear.MID_W + 2 * Gear.COL_GAP
    local height = HEADER_H + Gear.LEGEND_H + Gear.PAD + rows * Gear.PITCH + Gear.WEAPON_GAP + Gear.PITCH
        + Gear.PAD
    return width, height, rows
end

--- Every slot cell for `gear`: { slot, side ("left": the icon on its left, "right": on its right), x, y }
--- from the body's top-left (under the legend bar).
--- @return table cells
function Gear.Cells(gear)
    gear = type(gear) == "table" and gear or {}
    local width, _, rows = Gear.Size(gear)
    local cells = {}
    for i, slot in ipairs(columnRows(gear, Gear.LEFT)) do
        cells[#cells + 1] = { slot = slot, side = "left", x = Gear.PAD, y = -(i - 1) * Gear.PITCH }
    end
    for i, slot in ipairs(columnRows(gear, Gear.RIGHT)) do
        cells[#cells + 1] = { slot = slot, side = "right", x = width - Gear.PAD - Gear.SLOT_W, y = -(i - 1) * Gear.PITCH }
    end
    -- The weapons under the middle, facing each other as the character panel's do.
    local y, mid = -(rows * Gear.PITCH + Gear.WEAPON_GAP), width / 2
    cells[#cells + 1] = { slot = Gear.WEAPONS[1], side = "right", x = mid - Gear.COL_GAP / 2 - Gear.SLOT_W, y = y }
    cells[#cells + 1] = { slot = Gear.WEAPONS[2], side = "left", x = mid + Gear.COL_GAP / 2, y = y }
    return cells
end

-- How far `point`'s spot sits from a frame's center, in its width and height.
local function pointShare(point)
    local hx = point:find("LEFT") and -0.5 or (point:find("RIGHT") and 0.5 or 0)
    local hy = point:find("TOP") and 0.5 or (point:find("BOTTOM") and -0.5 or 0)
    return hx, hy
end

--- The offset that centers a `gw` x `gh` frame over one anchored at `point` (x, y) at `w` x `h`, both
--- anchored by the same point.
--- @return number x, number y
function Gear.CenterOver(point, x, y, w, h, gw, gh)
    local hx, hy = pointShare(type(point) == "string" and point or "CENTER")
    return x + hx * (gw - w), y + hy * (gh - h)
end

-- ── the client's item data ──────────────────────────────────────────────────────────────────────

local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return a end
    return nil
end

local function itemAPI()
    return type(C_Item) == "table" and C_Item or {}
end

local function clientString(item)
    return item and NS.Loadouts.ItemString(item) or nil
end

--- A stored item's item level (the client's, pcall'd), or nil.
function Gear.IlvlOf(item)
    local s = clientString(item)
    return s and NS.Secrets.PlainNumber(ask(itemAPI().GetDetailedItemLevelInfo, s)) or nil
end

--- A stored item's name (the client's, pcall'd), or nil.
function Gear.ItemName(item)
    local parts = Gear.ParseItem(item)
    if not parts then return nil end
    return NS.Secrets.PlainString(ask(itemAPI().GetItemNameByID, parts.itemID))
end

local function qualityColor(item)
    local q = ask(itemAPI().GetItemQualityByID, clientString(item))
    local qr, qg, qb = NS.QualityColor(q)
    if qr then return { qr, qg, qb } end
    return C.dim
end

local function markTexture(m)
    if m.kind == "enchant" then return Gear.MARK_ENCHANT end
    return (m.id and ask(itemAPI().GetItemIconByID, m.id)) or Gear.MARK_FALLBACK
end

-- ── the window ──────────────────────────────────────────────────────────────────────────────────

local function buildChrome(f)
    f.title = Style.PlainText(f, FONT.TITLE, "CENTER")
    f.title:SetText(L["Gear view"])
    ui.close = NS.MakeCloseButton(f, function() Gear.Hide() end)
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
    local y = -HEADER_H - Gear.LEGEND_H / 2
    ui.legendA = Style.Text(f, FONT.TEXT, TL.THIS)
    ui.legendA:SetPoint("LEFT", f, "TOPLEFT", Gear.PAD, y)
    ui.legendB = Style.Text(f, FONT.TEXT, TL.OTHER, "RIGHT")
    ui.legendB:SetPoint("RIGHT", f, "TOPRIGHT", -Gear.PAD, y)
end

-- The stats column: a heading per group and a row of three cells per stat, built once (Stats.GROUPS
-- never changes) and placed from the constants.
local function buildStats(body)
    local col = CreateFrame("Frame", nil, body)
    col:SetPoint("TOPLEFT", body, "TOPLEFT", Gear.PAD + Gear.SLOT_W + Gear.COL_GAP, 0)
    col:SetSize(Gear.MID_W, 1)
    ui.statsCol, ui.groups, ui.statRows = col, {}, {}
    local y = 0
    for gi, g in ipairs(NS.Stats.GROUPS) do
        local head = Style.Text(col, FONT.SECTION)
        head:SetPoint("TOPLEFT", col, "TOPLEFT", 0, y)
        ui.groups[gi] = head
        y = y - Gear.GROUP_H
        for _, key in ipairs(g.rows) do
            local row = { key = key }
            row.label = Style.Text(col, FONT.TEXT, C.dim)
            row.label:SetPoint("TOPLEFT", col, "TOPLEFT", 0, y)
            row.label:SetWidth(Gear.LABEL_W)
            row.value = Style.Text(col, FONT.TEXT, C.text, "RIGHT")
            row.value:SetPoint("TOPLEFT", col, "TOPLEFT", Gear.LABEL_W, y)
            row.value:SetWidth(Gear.VALUE_W)
            row.delta = Style.Text(col, FONT.TEXT, C.dim, "RIGHT")
            row.delta:SetPoint("TOPLEFT", col, "TOPLEFT", Gear.LABEL_W + Gear.VALUE_W, y)
            row.delta:SetWidth(Gear.DELTA_W)
            ui.statRows[#ui.statRows + 1] = row
            y = y - Gear.STAT_H
        end
        y = y - Gear.GROUP_GAP
    end
    ui.statsNote = Style.Text(col, FONT.CAPTION)
    ui.statsNote:SetPoint("TOPLEFT", col, "TOPLEFT", 0, y)
    ui.statsNote:SetWidth(Gear.MID_W)
    ui.statsNote:SetText(L["Stats were not recorded for this fight."])
end

-- A close-stack close, a frame later: the Results window's cover goes unless the view is open again.
local function settle()
    if Gear.IsShown() then return end
    NS.Results.SetCovered(false)
    NS.Results.StepAsideForTree()
end

local function onHide()
    Tbl.HideTip()
    if hiding or (ui and ui.frame:IsShown()) then return end
    -- Escape (UISpecialFrames): the player closed it. The cover stays until the close stack is done,
    -- so the Results window, hidden by the same Escape, still sees it and shows again.
    Gear.wanted = false
    if C_Timer and C_Timer.After then C_Timer.After(0, settle) else settle() end
end

local function ensureWindow()
    if ui then return ui end
    local f = CreateFrame("Frame", Gear.FRAME_NAME, UIParent, "BackdropTemplate")
    ui = { frame = f, cells = {} }
    f:Hide()
    f:SetFrameStrata(NS.Constants.LAYERS.STRATA.MODAL)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetToplevel(true)
    buildChrome(f)
    buildLegend(f)
    ui.body = CreateFrame("Frame", nil, f)
    ui.body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(HEADER_H + Gear.LEGEND_H + Gear.PAD))
    ui.body:SetSize(1, 1)
    buildStats(ui.body)
    NS.Skin.Shell(f, TL.SHELL)
    f:SetScript("OnHide", onHide)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Gear.FRAME_NAME) end
    debug("window built")
    return ui
end

-- ── one slot ────────────────────────────────────────────────────────────────────────────────────

-- A slot's hover: the client's own item tooltip from the stored item, then what differs.
local function slotTip(cell)
    local tt = GameTooltip
    if not tt then return end
    tt:SetOwner(cell, "ANCHOR_RIGHT")
    if not cell.item then
        tt:SetText(L["Empty"], Style.Rgb("gtip.title"))
        tt:AddLine(L["Nothing was equipped in this slot."], Style.Rgb("gtip.muted"))
        return tt:Show()
    end
    local shown = tt.SetHyperlink and pcall(tt.SetHyperlink, tt, clientString(cell.item))
    if not shown then tt:SetText(Gear.ItemName(cell.item) or "?", Style.Rgb("gtip.value")) end
    if cell.notes and cell.notes[1] then
        tt:AddLine(" ")
        Style.AddTipLines(tt, cell.notes, 1, Style.Rgb(C.amber))
    end
    tt:Show()
end

local function onSlotClick(cell)
    if not cell.item then return end
    local _, link = ask(itemAPI().GetItemInfo, clientString(cell.item))
    if type(link) == "string" and type(HandleModifiedItemClick) == "function" then
        pcall(HandleModifiedItemClick, link)
    end
end

local function newMark(cell)
    local m = { edge = cell:CreateTexture(nil, "BORDER"), icon = cell:CreateTexture(nil, "ARTWORK") }
    m.edge:SetSize(Gear.MARK + 2, Gear.MARK + 2)
    m.icon:SetSize(Gear.MARK, Gear.MARK)
    Style.CropIcon(m.icon)
    m.icon:SetPoint("CENTER", m.edge, "CENTER", 0, 0)
    return m
end

local function newCell(body)
    local cell = CreateFrame("Button", nil, body)
    cell:SetSize(Gear.SLOT_W, Gear.PITCH - 4)
    cell.tint = cell:CreateTexture(nil, "BACKGROUND")
    cell.tint:SetAllPoints(cell)
    Style.Fill(cell.tint, C.amber, CHANGED_A)
    cell.edge = cell:CreateTexture(nil, "BORDER")
    cell.edge:SetSize(Gear.ICON + 2, Gear.ICON + 2)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(Gear.ICON, Gear.ICON)
    Style.CropIcon(cell.icon)
    cell.icon:SetPoint("CENTER", cell.edge, "CENTER", 0, 0)
    cell.ilvl = Style.Text(cell, FONT.TEXT, C.text, "CENTER")
    cell.ilvl:SetPoint("BOTTOM", cell.icon, "BOTTOM", 0, 2)
    cell.name = Style.Text(cell, FONT.TEXT, C.text)
    cell.name:SetWidth(Gear.SLOT_W - Gear.ICON - 2 - Gear.TEXT_GAP)
    cell.marks = {}
    for i = 1, 5 do cell.marks[i] = newMark(cell) end
    if cell.RegisterForClicks then cell:RegisterForClicks("LeftButtonUp") end
    cell:SetScript("OnEnter", slotTip)
    cell:SetScript("OnLeave", function() Tbl.HideTip() end)
    cell:SetScript("OnClick", onSlotClick)
    return cell
end

-- The icon at the cell's outer side, the name and the marks toward the middle.
local function placeCell(cell, spec)
    local left = spec.side == "left"
    local corner, dir = left and "TOPLEFT" or "TOPRIGHT", left and 1 or -1
    local textX = Gear.ICON + 2 + Gear.TEXT_GAP
    cell:ClearAllPoints()
    cell:SetPoint("TOPLEFT", ui.body, "TOPLEFT", spec.x, spec.y)
    cell.edge:ClearAllPoints()
    cell.edge:SetPoint(corner, cell, corner, 0, 0)
    cell.name:ClearAllPoints()
    cell.name:SetJustifyH(left and "LEFT" or "RIGHT")
    cell.name:SetPoint(corner, cell, corner, dir * textX, -3)
    for i, m in ipairs(cell.marks) do
        m.edge:ClearAllPoints()
        m.edge:SetPoint(corner, cell, corner, dir * (textX + (i - 1) * (Gear.MARK + 2 + Gear.MARK_GAP)), -20)
    end
    cell.side = spec.side
end

local function paintMarks(cell, marks)
    for i, m in ipairs(cell.marks) do
        local mark = marks[i]
        m.edge:SetShown(mark ~= nil)
        m.icon:SetShown(mark ~= nil)
        if mark then
            Style.Fill(m.edge, mark.changed and C.amber or "icon.border", 1)
            m.icon:SetTexture(markTexture(mark))
            if m.icon.SetDesaturated then m.icon:SetDesaturated(mark.missing == true) end
            m.icon:SetAlpha(mark.missing and 0.35 or 1)
        end
        m.mark = mark
    end
end

local function signColor(sign, same)
    if sign == 1 then return C.green end
    if sign == -1 then return C.red end
    return same
end

-- One slot's look: its item (or Empty), the item change's wash, the item level's color, the marks.
local function fillCell(cell, slot, item, diff, label, otherItem)
    cell.slot, cell.item, cell.diff = slot, item, diff
    cell.changed = diff ~= nil and diff.item == true
    cell.tint:SetShown(cell.changed)
    cell.notes = Gear.NoteLines(diff, label, otherItem and Gear.ItemName(otherItem))
    if not item then
        Style.Fill(cell.edge, "ct.slot.empty")
        cell.icon:SetTexture(nil)
        cell.ilvl:SetText("")
        cell.name:SetText(L["Empty"])
        Style.Paint(cell.name, C.dim)
        return paintMarks(cell, {})
    end
    local q = qualityColor(item)
    Style.Fill(cell.edge, q, 1)
    local parts = Gear.ParseItem(item)
    cell.icon:SetTexture(parts and ask(itemAPI().GetItemIconByID, parts.itemID) or Gear.MARK_FALLBACK)
    local ilvl = Gear.IlvlOf(item)
    cell.ilvl:SetText(ilvl and tostring(math.floor(ilvl)) or "")
    Style.Paint(cell.ilvl, signColor(diff and diff.ilvl, C.text))
    cell.name:SetText(Gear.ItemName(item) or L["Item %d"]:format(parts and parts.itemID or 0))
    Style.Paint(cell.name, q)
    paintMarks(cell, Gear.Marks(parts, diff))
end

local function cellFor(slot)
    local cell = ui.cells[slot]
    if not cell then
        cell = newCell(ui.body)
        ui.cells[slot] = cell
    end
    return cell
end

-- ── drawing ─────────────────────────────────────────────────────────────────────────────────────

local function fillStats(stats, otherStats)
    local i = 0
    for gi, g in ipairs(NS.Stats.Groups(stats, otherStats)) do
        ui.groups[gi]:SetText(g.title)
        for _, r in ipairs(g.rows) do
            i = i + 1
            local row = ui.statRows[i]
            row.label:SetText(r.label)
            row.value:SetText(r.text)
            Style.Paint(row.value, stats and C.text or C.dim)
            row.delta:SetText(r.delta or "")
            Style.Paint(row.delta, signColor(r.sign, C.dim))
            row.data = r
        end
    end
    ui.statsNote:SetShown(stats == nil)
end

local function fillLegend(record, other, kind)
    local D = NS.ResultsTimelineData
    local parts = { D.ThisLabel(record) }
    local w = type(record.who) == "table" and record.who or {}
    if type(w.ilvl) == "number" then parts[#parts + 1] = L["ilvl %s"]:format(Tbl.Ilvl(w.ilvl)) end
    ui.legendA:SetText(table.concat(parts, SEP))
    ui.otherLabel = other and D.KindLabel(kind) or nil
    if other then
        ui.legendB:SetText(L["vs %s"]:format(D.OtherLabel(other, kind)))
        Style.Paint(ui.legendB, TL.OTHER)
    else
        ui.legendB:SetText(L["No fight to compare with"])
        Style.Paint(ui.legendB, C.dim)
    end
end

-- Every slot of the layout filled and placed; a cell left from a fight with more slots hides.
local function fillSlots(gear, otherGear)
    local used = {}
    ui.drawn = Gear.Cells(gear)
    for _, spec in ipairs(ui.drawn) do
        local cell = cellFor(spec.slot)
        local item, otherItem = gear and gear[spec.slot], otherGear and otherGear[spec.slot]
        local diff = otherGear and Gear.SlotDiff({ item = item, ilvl = Gear.IlvlOf(item) },
            { item = otherItem, ilvl = Gear.IlvlOf(otherItem) }) or nil
        fillCell(cell, spec.slot, item, diff, ui.otherLabel, otherItem)
        placeCell(cell, spec)
        cell:Show()
        used[spec.slot] = true
    end
    for slot, cell in pairs(ui.cells) do
        if not used[slot] then cell:Hide() end
    end
end

-- The followed detail's fight and its compare target.
local function followed()
    local record = pane and type(pane.Record) == "function" and pane:Record() or nil
    if not record then return nil end
    if type(pane.CompareTarget) == "function" then return record, pane:CompareTarget(true) end
    return record, NS.ResultsCompare.Pick(record)
end

-- Read the followed detail's fight and compare target, and draw them.
local function draw()
    local record, other, kind = followed()
    ui.record, ui.other, ui.kind = record, other, kind
    if not record then return end
    local gear, otherGear = gearOf(record), gearOf(other)
    fillLegend(record, other, kind)
    -- A compared fight with no gear recorded marks nothing.
    fillSlots(gear, otherGear)
    fillStats(NS.Stats.Of(record), NS.Stats.Of(other))
    ui.width, ui.height = Gear.Size(gear)
    ui.frame:SetSize(ui.width, ui.height)
    Gear.ApplyScale()
    debug("drawn: %d slots", #ui.drawn)
end

-- Centered over the Results window (its anchor and its size in the view shown).
local function applyPlacement()
    local point, relativePoint, x, y, width, height = NS.Results.Placement()
    local record = pane and type(pane.Record) == "function" and pane:Record() or nil
    local gw, gh = Gear.Size(gearOf(record))
    local cx, cy = Gear.CenterOver(point, x, y, width, height, gw, gh)
    ui.frame:ClearAllPoints()
    ui.frame:SetPoint(point, UIParent, relativePoint, cx, cy)
end

-- ── the public surface ──────────────────────────────────────────────────────────────────────────

--- Open the view on the detail pane `p` (the detail's Gear view button) and follow it from now on.
--- Another modal over the Results window closes first (one cover, one modal).
--- @return boolean opened
function Gear.Open(p)
    if NS.IsStoodDown() then return false end
    NS.Results.CloseModals("ResultsGear")
    pane = p
    Gear.wanted = true
    ensureWindow()
    applyPlacement()
    ui.frame:Show()
    if ui.frame.Raise then ui.frame:Raise() end
    NS.RaiseStaticPopups()
    NS.Results.SetCovered(true)
    draw()
    return true
end

--- Close the view (its close control, the Results window closing): the Results window's cover goes.
function Gear.Hide()
    local was = Gear.wanted
    Gear.wanted = false
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

--- Whether the view is open.
function Gear.IsShown()
    return Gear.wanted and ui ~= nil and ui.frame:IsShown() == true
end

--- The detail pane `p` drew a fight or changed its compare target: redraw while open on it. A pane
--- left with no fight (the shown fight was deleted) closes the view.
function Gear.DetailChanged(p)
    if p ~= pane or not Gear.IsShown() then return end
    if not (type(p.Record) == "function" and p:Record()) then return Gear.Hide() end
    draw()
end

-- A new skin: the quality colors may move, so an open view draws again.
Style.OnLooks(function() if Gear.IsShown() then draw() end end)

--- The Results window's scale on this one (it opens over that window, in its units).
function Gear.ApplyScale()
    local scale = tonumber(NS.GetSetting("results.scale"))
    if ui and scale and scale > 0 then ui.frame:SetScale(scale) end
end

--- The Master controls' Reset position: nothing is stored, so an open view centers again.
function Gear.ResetPosition()
    if Gear.IsShown() then applyPlacement() end
end

--- The slot cells drawn now, for the suites: { [slot] = cell } (shown ones only).
function Gear.SlotCells()
    local out = {}
    for slot, cell in pairs(ui and ui.cells or {}) do
        if cell:IsShown() then out[slot] = cell end
    end
    return out
end

--- The built window, for the suites (nil until first opened).
function Gear.__ui() return ui end
