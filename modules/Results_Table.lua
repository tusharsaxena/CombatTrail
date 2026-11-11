local _, NS = ...
-- modules/Results_Table.lua — the Results window's sortable list (spec §7): a header of sort
-- controls over a pooled, scrolling set of row buttons; and the small helpers the window draws a
-- fight with (class and spec icons, the class color, the content chip, the dates). Adapted from DPS
-- Race @045f479 (modules/Results_Table.lua) without its race: no race length colors or chips, no
-- dummy categories, no late-cast flags.
--
-- POOLED AND VIRTUAL. Only the rows that fit are drawn (LibKa0s-Pool, events-frames-taint-§6): a
-- scroll re-binds the same row frames to the next slice of the sorted list, so a 500-fight history
-- costs the rows on screen and no more (Review Focus 5). A row never holds a fight of its own beyond
-- the one it is bound to now.
--
-- LAYOUT FROM CONFIG. Every column has a configured width (one column takes what is left), every row
-- is placed from its index, and no size or position is ever read back off a frame. The window never
-- shows a meter value (only stored, plain records), but it keeps the HUD's rule all the same.
--
-- SORTING IS ON STORED NUMBERS. A fight's figures went through NS.Secrets on their way into the store
-- (modules/Recorder.lua), so comparing them is plain Lua. A missing value sorts last whichever way
-- the column runs; a tie falls to the newer fight, then the id, so the order never depends on pairs().

local Tbl = {}
NS.ResultsTable = Tbl

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT

-- Compact rows under a 20px header, as LootHistory's list draws them (BrowserTable: 18px rows).
-- ROW_H is the shipped row height; the drawn one is `results.rowHeight` (History > Results window),
-- read at each layout through Tbl.RowHeight.
Tbl.ROW_H = 18
Tbl.ROW_H_MIN, Tbl.ROW_H_MAX = 14, 32
Tbl.HEADER_H = 20
Tbl.PAD = 6                 -- the gap between two cells, and the row's inner margin
Tbl.SCROLLBAR_W = NS.Skin.Token("scroll.width") or 8
Tbl.ICON = 16
Tbl.WHEEL_ROWS = 3          -- rows one notch of the mouse wheel moves
-- A bar cell's fill over the row (v0.2 Task C2, D12): DPS Race's bar blue, the shared palette's
-- (core/Constants.lua), at its opacity; never the class color, which stays on the name and the icons.
Tbl.BAR_COLOR = NS.Constants.PALETTE.BAR
Tbl.BAR_ALPHA = NS.Constants.PALETTE.BAR_A
Tbl.BADGE_ICON = 11         -- an icon inside a badge (a column whose text answers one)
Tbl.ICON_GAP = 2            -- between two icons of an items cell (the Used column)

--- The list's row height now (px): `results.rowHeight`, else the shipped one.
function Tbl.RowHeight()
    local h = tonumber(NS.GetSetting and NS.GetSetting("results.rowHeight"))
    if not h then return Tbl.ROW_H end
    return math.max(Tbl.ROW_H_MIN, math.min(Tbl.ROW_H_MAX, math.floor(h + 0.5)))
end

local CLASS_ATLAS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local DASH = "\226\128\148"

-- The window's palette. The chrome and meaning colors are the HUD's live skin colors
-- (modules/Hud_States.lua). The content hues are DATA hues (skinning rung 4: one hue per kind of
-- content, mockup §5), the same under every skin.
local HC = NS.HudStates.COLORS
local C = {
    text  = HC.text,
    dim   = HC.dim,
    gold  = Style.GOLD,
    amber = HC.amber,
    green = HC.green,
    red   = HC.red,
    blue  = NS.Constants.PALETTE.BEST_TEXT,   -- a best's mark (D15's best blue)
}
Tbl.COLORS = C

-- The content chips' colors (mockup §5): one hue per content kind (modules/Identity.lua).
Tbl.CONTENT_COLORS = {
    raid     = { 1.0, 0.50, 0.20 },
    dungeon  = { 0.56, 0.72, 1.0 },
    mplus    = { 0.75, 0.55, 1.0 },
    delve    = { 0.86, 0.73, 0.43 },
    bg       = { 1.0, 0.45, 0.45 },
    arena    = { 1.0, 0.42, 0.72 },
    world    = { 0.36, 0.86, 0.46 },
    dummy    = { 0.62, 0.62, 0.68 },
    scenario = { 0.40, 0.80, 0.80 },
}
Tbl.CONTENT_NEUTRAL = { 0.62, 0.62, 0.68 }

-- The content kinds' names (the content chip, the Content filter and its group headers).
local CONTENT_LABELS = {
    raid = "Raid", dungeon = "Dungeon", mplus = "Mythic+", delve = "Delve", bg = "Battleground",
    arena = "Arena", world = "Open world", dummy = "Dummy", scenario = "Scenario",
}

--- A content kind's name, or "Other" for one this version does not know.
function Tbl.ContentLabel(key)
    return L[CONTENT_LABELS[key] or "Other"]
end

-- ── the fight, as the window draws it ───────────────────────────────────────────────────────────

--- A FontString in one of the shared font objects (modules/Style.lua: Style.FONT), recolored when
--- `color` is given, never wrapping.
Tbl.Text = Style.Text
Tbl.FONT = FONT

--- The class color, else the window's text color.
function Tbl.ClassColor(class)
    local colors = RAID_CLASS_COLORS
    local c = type(colors) == "table" and type(class) == "string" and colors[class]
    if type(c) == "table" and type(c.r) == "number" then return { c.r, c.g, c.b } end
    return C.text
end

--- The class's localized name, else its token.
function Tbl.ClassName(class)
    local names = LOCALIZED_CLASS_NAMES_MALE
    local name = type(names) == "table" and type(class) == "string" and names[class]
    if type(name) == "string" then return name end
    return class and tostring(class) or L["Unknown class"]
end

--- Draw `class`'s icon on `tex` from the character-creation atlas; hidden when it is unknown. The
--- cell is cropped by Style.ICON_CROP of ITS OWN size, inside its coords, so no native edge shows
--- inside the icon's edge.
function Tbl.SetClassIcon(tex, class)
    local coords = type(CLASS_ICON_TCOORDS) == "table" and type(class) == "string" and CLASS_ICON_TCOORDS[class]
    if type(coords) ~= "table" then
        tex:Hide()
        return false
    end
    local z = Style.ICON_CROP
    local w, h = (coords[2] - coords[1]) * z, (coords[4] - coords[3]) * z
    tex:SetTexture(CLASS_ATLAS)
    tex:SetTexCoord(coords[1] + w, coords[2] - w, coords[3] + h, coords[4] - h)
    tex:Show()
    return true
end

--- A spec's name and icon through GetSpecializationInfoByID, with the fight's own name and icon
--- beneath it. On WoW Forever the spec is the predominant talent tree (a "tree:" key, never asked of
--- the client), so its stored name and icon answer; with neither there is no icon, never the class
--- icon a second time.
--- @param specID number|string|nil
--- @param fallbackName string|nil
--- @param fallbackIcon number|string|nil
--- @return string|nil name, any icon
function Tbl.SpecInfo(specID, fallbackName, fallbackIcon)
    local api = GetSpecializationInfoByID
    if type(specID) == "number" and type(api) == "function" then
        local ok, _, name, _, icon = pcall(api, specID)
        if ok and type(name) == "string" then return name, icon end
    end
    return fallbackName, fallbackIcon
end

--- A color as the "aarrggbb" hex an inline |c escape takes.
--- @param color table  { r, g, b }
--- @return string
function Tbl.Hex(color)
    return ("ff%02x%02x%02x"):format(math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5),
        math.floor(color[3] * 255 + 0.5))
end

--- The content chip of a fight: its kind's name ("Mythic+ 12" with a keystone, "Delve 8" with a
--- tier) and its color.
--- @return string text, table color
function Tbl.ContentChip(record)
    local ident = type(record) == "table" and type(record.identity) == "table" and record.identity or {}
    local key = ident.content
    local text = Tbl.ContentLabel(key)
    if key == "mplus" and type(ident.keystoneLevel) == "number" then
        text = L["Mythic+ %d"]:format(ident.keystoneLevel)
    elseif key == "delve" and type(ident.delveTier) == "number" then
        text = L["Delve %d"]:format(ident.delveTier)
    end
    return text, Tbl.CONTENT_COLORS[key] or Tbl.CONTENT_NEUTRAL
end

--- A fight's date in `fmt` (os.date's), or "" when it has none.
function Tbl.Date(t, fmt)
    if type(t) ~= "number" or type(date) ~= "function" then return "" end
    local ok, s = pcall(date, fmt, t)
    return ok and s or ""
end

--- An item level to one decimal, or a dash.
function Tbl.Ilvl(v)
    if type(v) ~= "number" then return DASH end
    return ("%.1f"):format(v)
end

-- ── tooltips ────────────────────────────────────────────────────────────────────────────────────
-- ONE HOVER PER ROW, NOT A SPOT PER CELL: the row follows the cursor across its cells (its OnUpdate,
-- only while hovered) and shows the tooltip of the cell under it (NS.ResultsTips). The tooltip sits
-- beside the WINDOW at the row's height, on its right (LootHistory's), or on its left when the
-- screen has no room for it there. Nothing here holds a meter value, so the geometry read is free.

-- The top-level window a table sits in (the frame whose parent is UIParent).
local function windowOf(frame)
    local w = frame
    while w and w.GetParent do
        local p = w:GetParent()
        if p == nil or p == UIParent then return w end
        w = p
    end
    return frame
end

Tbl.WindowOf = windowOf

-- Lines from `first` on, each a string (light gray) or { text, r, g, b }, on bullets from two lines
-- on (modules/Style.lua).
local addLines = Style.AddTipLines

-- A geometry answer as a plain number, or nil (core/Secrets.lua): every read here goes through it.
local function plainGeom(frame, method)
    local fn = frame and frame[method]
    if type(fn) ~= "function" then return nil end
    return NS.Secrets.PlainNumber(fn(frame))
end

-- The shown tooltip beside `window`, level with `row`: its right, or its left without the room.
local function placeSide(tip, window, row)
    local dy = 0
    local rowTop, winTop = plainGeom(row, "GetTop"), plainGeom(window, "GetTop")
    if rowTop and winTop then dy = rowTop - winTop end
    local scale = plainGeom(window, "GetEffectiveScale") or 1
    local right = (plainGeom(window, "GetRight") or 0) * scale
    local room = (plainGeom(UIParent, "GetRight") or 0) * (plainGeom(UIParent, "GetEffectiveScale") or 1)
    local width = (plainGeom(tip, "GetWidth") or 0) * (plainGeom(tip, "GetEffectiveScale") or 1)
    tip:ClearAllPoints()
    if right + width + 4 <= room then
        tip:SetPoint("TOPLEFT", window, "TOPRIGHT", 4, dy)
    else
        tip:SetPoint("TOPRIGHT", window, "TOPLEFT", -4, dy)
    end
end

--- Show `lines` ({ title, line, ... }; a line is a string or { text, r, g, b }) beside `window`,
--- level with `row`.
function Tbl.SideTip(window, row, lines)
    local tip = GameTooltip
    if not tip or type(lines) ~= "table" or not lines[1] then return end
    tip:SetOwner(window, "ANCHOR_NONE")
    local r, g, b = Style.Rgb("gtip.title")
    tip:SetText(lines[1], r, g, b, 1, true)
    addLines(tip, lines, 2)
    tip:Show()
    placeSide(tip, window, row)
end

--- The client's spell tooltip for `id` beside `window`, level with `row`, then `lines` under a gap
--- (the ability timeline's names and icons). The id is a stored, plain one; SetSpellByID is pcall'd,
--- and the spell's name stands in when the client draws nothing.
function Tbl.SpellTip(window, row, id, lines)
    local tip = GameTooltip
    if not tip then return end
    tip:SetOwner(window, "ANCHOR_NONE")
    local shown = id ~= nil and tip.SetSpellByID ~= nil and pcall(tip.SetSpellByID, tip, id)
    if shown and tip.NumLines then shown = (plainGeom(tip, "NumLines") or 0) > 0 end
    if not shown then
        local r, g, b = Style.Rgb("gtip.value")
        tip:SetText(NS.HudBreakdown.SpellName(id), r, g, b, 1, true)
    end
    if type(lines) == "table" and lines[1] then
        tip:AddLine(" ")
        addLines(tip, lines, 1)
    end
    tip:Show()
    placeSide(tip, window, row)
end

local function hideTip()
    if GameTooltip then GameTooltip:Hide() end
end
Tbl.HideTip = hideTip

-- ── cells ───────────────────────────────────────────────────────────────────────────────────────

local Cells = {}

-- A text cell; a column with `bar` also draws a fill under its text, as long as its value's place
-- between the smallest and the largest in its group (Table:measure, Tbl.BarShare), over the row's own
-- stripe, in the palette's bar blue (Tbl.BAR_COLOR).
-- A column with `chips(record)` also draws up to CHIP_MAX boxed chips before its text (a race row's
-- length and flag chips, modules/Results_Races.lua), each its own part (cell.chip1, ...).
function Cells.text(row, col)
    local cell = { fs = Tbl.Text(row, FONT.TEXT, C.text, col.justify) }
    if col.bar then cell.bar = row:CreateTexture(nil, "BORDER", nil, 2) end
    if col.chips then
        for i = 1, Tbl.CHIP_MAX do
            local chip = Style.FlatBox(row)
            chip:SetHeight(Tbl.CHIP_H)
            chip.fs = Tbl.Text(chip, FONT.TEXT, C.text, "CENTER")
            chip.icon = chip:CreateTexture(nil, "ARTWORK")
            chip.icon:SetSize(Tbl.BADGE_ICON, Tbl.BADGE_ICON)
            chip.icon:SetPoint("LEFT", chip, "LEFT", 4, 0)
            chip:Hide()
            cell["chip" .. i] = chip
        end
    end
    return cell
end

-- The class and spec icons, cropped and outlined.
function Cells.icons(row)
    local cell = { class = row:CreateTexture(nil, "ARTWORK"), spec = row:CreateTexture(nil, "ARTWORK") }
    cell.class:SetSize(Tbl.ICON, Tbl.ICON)
    cell.spec:SetSize(Tbl.ICON, Tbl.ICON)
    Style.EdgeClassIcon(cell.class)
    Style.EdgeIcon(cell.spec)
    return cell
end

-- A row of small icons (the Used column, ported from DPS Race's): as many as the column's configured
-- width holds (Tbl.IconSlots), each its own part (cell.icon1, ...) so a group header's showCells
-- hides it, then "+n" for the rest, or a dash when there is nothing. Each icon is cropped and
-- outlined; its edge shows and hides with it.
function Cells.items(row, col)
    local cell = { more = Tbl.Text(row, FONT.TEXT, C.dim), dash = Tbl.Text(row, FONT.TEXT, C.dim) }
    cell.dash:SetText(DASH)
    cell.slots = Tbl.IconSlots(col.width)
    for i = 1, cell.slots do
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(Tbl.ICON, Tbl.ICON)
        Style.EdgeIcon(icon)
        cell["icon" .. i] = icon
    end
    return cell
end

-- A chip or a tag: its icon (where the column's text names one) before its word, both in the tag's
-- color, in a 1px box tinted that color (the Content column).
function Cells.badge(row)
    local cell = { box = Style.FlatBox(row) }
    cell.box:SetHeight(Tbl.CHIP_H)
    cell.fs = Tbl.Text(cell.box, FONT.TEXT, C.amber, "CENTER")
    cell.fs:SetPoint("CENTER", cell.box, "CENTER", 0, 0)
    cell.icon = cell.box:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(Tbl.BADGE_ICON, Tbl.BADGE_ICON)
    cell.icon:SetPoint("LEFT", cell.box, "LEFT", 4, 0)
    cell.icon:Hide()
    return cell
end

local function paint(fs, color)
    Style.Paint(fs, color or C.text)
end

Tbl.CHIP_H = 16
Tbl.CHIP_MAX = 2            -- the chips a text cell draws before its text
Tbl.CHIP_GAP = 4            -- between two chips, and between the last and the text

local Bind = {}

Tbl.BAR_FLOOR = 0.10        -- the share of the cell the smallest value in the group draws at

--- A bar's share of its cell: linear from the group's smallest value (Tbl.BAR_FLOOR) to its largest
--- (1). One value, or every value equal, draws full; a value that is not a number draws nothing (0).
--- @return number share  0, or BAR_FLOOR..1
function Tbl.BarShare(v, min, max)
    if type(v) ~= "number" or type(min) ~= "number" or type(max) ~= "number" then return 0 end
    if max <= min then return 1 end
    local t = math.max(0, math.min(1, (v - min) / (max - min)))
    return Tbl.BAR_FLOOR + (1 - Tbl.BAR_FLOOR) * t
end

-- The bar's width: the cell's, times the fight's share (Tbl.BarShare) between its group's smallest
-- and largest value (Table:measure). Plain numbers off stored fights, and the cell's width is the
-- column layout's, never a measured one.
local function bindBar(cell, col, record)
    local range = col.barRanges and col.barRanges[col.groupOf and col.groupOf(record) or true] or {}
    local share = Tbl.BarShare(col.bar(record), range.min, range.max)
    local on = share > 0
    cell.bar:SetShown(on)
    if not on then return end
    Style.Fill(cell.bar, Tbl.BAR_COLOR, Tbl.BAR_ALPHA)
    cell.bar:SetWidth(math.max(1, math.floor((cell.barW or 0) * share + 0.5)))
end

-- The tag's icon (a catalog name), tinted the tag's color, before the word: answers the room the
-- word shifts right by.
local function bindBadgeIcon(cell, icon, color)
    local path = icon and NS.Icon(icon)
    cell.icon:SetShown(path ~= nil)
    if not path then return 0 end
    cell.icon:SetTexture(path)
    Style.Vertex(cell.icon, color, 1)
    return Tbl.BADGE_ICON + 2
end

-- Paint one chip ({ text, color, icon }) boxed in its color: answers its width (config, never measured).
local function bindChip(chip, item)
    local color = item.color or C.text
    local extra = bindBadgeIcon(chip, item.icon, color)
    local w = Tbl.BadgeWidth(item.text or "", true, extra)
    chip.fs:SetText(item.text or "")
    paint(chip.fs, color)
    chip.fs:ClearAllPoints()
    chip.fs:SetPoint("CENTER", chip, "CENTER", extra / 2, 0)
    chip.fs:SetWidth(math.max(1, w - 6 - extra))
    Style.TintBox(chip, color, Style.BADGE_EDGE_A)
    chip:SetWidth(w)
    chip:Show()
    return w
end

-- The cell's chips from its left edge (placeCell's x), the text after them: none drawn, the text at
-- its own place.
local function bindChips(cell, col, record)
    local list = col.chips(record) or {}
    local x = 0
    for i = 1, Tbl.CHIP_MAX do
        local chip, item = cell["chip" .. i], list[i]
        if item then
            chip:ClearAllPoints()
            chip:SetPoint("LEFT", cell.rowOf(), "LEFT", cell.x + x, 0)
            x = x + bindChip(chip, item) + Tbl.CHIP_GAP
        else
            chip:Hide()
        end
    end
    cell.fs:ClearAllPoints()
    cell.fs:SetPoint("LEFT", cell.rowOf(), "LEFT", cell.x + x, 0)
    cell.fs:SetWidth(math.max(10, cell.w - x))
end

function Bind.text(cell, col, record)
    local s, color = col.text(record)
    cell.fs:SetText(s or "")
    paint(cell.fs, color)
    if cell.bar then bindBar(cell, col, record) end
    if col.chips and cell.rowOf then bindChips(cell, col, record) end
end

--- How many icons an items cell `width` px wide holds (at least one). Pure.
function Tbl.IconSlots(width)
    return math.max(1, math.floor(((width or 0) + Tbl.ICON_GAP) / (Tbl.ICON + Tbl.ICON_GAP)))
end

--- How many of `count` icons an items cell `width` px wide draws, and the "+n" after them: all of
--- them when they fit, else one slot fewer than fit and the rest counted in the last slot. Pure.
--- @return number shown, number more
function Tbl.IconsFit(count, width)
    local slots = Tbl.IconSlots(width)
    if count <= slots then return count, 0 end
    return slots - 1, count - (slots - 1)
end

-- The column's `items(record)` answers the icons ({ texture, ... }), or nil: a dash for none.
function Bind.items(cell, col, record)
    local list = col.items(record) or {}
    local shown, more = Tbl.IconsFit(#list, col.width)
    for i = 1, cell.slots do
        local icon = cell["icon" .. i]
        icon:SetShown(i <= shown)
        if i <= shown then icon:SetTexture(list[i]) end
    end
    cell.dash:SetShown(#list == 0)
    cell.more:SetShown(more > 0)
    cell.more:SetText(more > 0 and ("+" .. more) or "")
    if more > 0 then
        cell.more:ClearAllPoints()
        cell.more:SetPoint("LEFT", cell.icon1 or cell.dash, "LEFT", shown * (Tbl.ICON + Tbl.ICON_GAP), 0)
    end
end

function Bind.icons(cell, _, record)
    local who = type(record.who) == "table" and record.who or {}
    local specName, specIcon = Tbl.SpecInfo(who.specID, who.specName, who.specIcon)
    Tbl.SetClassIcon(cell.class, who.class)
    cell.spec:SetTexture(specIcon)
    cell.spec:SetShown(specIcon ~= nil)
    cell.specName = specName
end

--- A chip's width from its label's length (config, never a measured width): 6 px a character (a
--- UTF-8 continuation byte adds none: "·" is one), 4 px of pad (14 in a box), plus `extra` for an
--- icon. Pure; the fit tests size columns against it.
--- @param s string
--- @param boxed boolean|nil
--- @param extra number|nil
--- @return number
function Tbl.BadgeWidth(s, boxed, extra)
    local chars = select(2, s:gsub("[^\128-\191]", ""))
    return math.floor(chars * 6 + (boxed and 14 or 4) + (extra or 0))
end

--- Set a checkbox's label (`check.label`, 1px right of the box) and widen its click area over it, so
--- a click on the words toggles it too. The width is the label's estimate (Tbl.BadgeWidth's 6 px a
--- character), never a measured one.
function Tbl.SetCheckLabel(check, text)
    text = text or ""
    check.label:SetText(text)
    check:SetHitRectInsets(0, -(1 + Tbl.BadgeWidth(text, false)), 0, 0)
end

-- The column's text answers the word, its color and, for a tag, its icon's catalog name.
function Bind.badge(cell, col, record)
    local s, color, icon = col.text(record)
    s = s or ""
    color = color or C.amber
    cell.fs:SetText(s)
    paint(cell.fs, color)
    cell.box:SetShown(s ~= "")
    local extra = bindBadgeIcon(cell, s ~= "" and icon or nil, color)
    local w = Tbl.BadgeWidth(s, true, extra)
    if cell.w and w > cell.w then w = math.max(14, cell.w) end
    cell.fs:ClearAllPoints()
    cell.fs:SetPoint("CENTER", cell.box, "CENTER", extra / 2, 0)
    cell.fs:SetWidth(math.max(1, w - 6 - extra))
    Style.TintBox(cell.box, color, Style.BADGE_EDGE_A)
    cell.box:SetWidth(w)
end

-- Place one cell in its column, from the column's x and width alone.
local function placeCell(row, cell, col, x, w)
    local kind = col.kind or "text"
    if kind == "icons" then
        cell.class:ClearAllPoints()
        cell.class:SetPoint("LEFT", row, "LEFT", x, 0)
        cell.spec:ClearAllPoints()
        cell.spec:SetPoint("LEFT", row, "LEFT", x + Tbl.ICON + 3, 0)
        return
    end
    if kind == "badge" then
        cell.box:ClearAllPoints()
        cell.box:SetPoint("LEFT", row, "LEFT", x, 0)
        cell.w = w
        return
    end
    if kind == "items" then
        for i = 1, cell.slots do
            cell["icon" .. i]:ClearAllPoints()
            cell["icon" .. i]:SetPoint("LEFT", row, "LEFT", x + (i - 1) * (Tbl.ICON + Tbl.ICON_GAP), 0)
        end
        cell.dash:ClearAllPoints()
        cell.dash:SetPoint("LEFT", row, "LEFT", x, 0)
        cell.more:SetWidth(math.max(10, Tbl.ICON + 8))
        return
    end
    cell.fs:ClearAllPoints()
    cell.fs:SetPoint("LEFT", row, "LEFT", x, 0)
    cell.fs:SetWidth(math.max(10, w))
    -- Where a chip column's Bind re-anchors its text (a closure: showCells shows every table part).
    cell.rowOf, cell.x, cell.w = function() return row end, x, w
    if not cell.bar then return end
    -- The bar spans the cell and a little of the gap each side; the text sits inside it.
    cell.barW = w + 4
    cell.fs:ClearAllPoints()
    cell.fs:SetPoint("LEFT", row, "LEFT", x + 2, 0)
    cell.fs:SetWidth(math.max(10, w - 2))
    cell.bar:ClearAllPoints()
    cell.bar:SetPoint("TOPLEFT", row, "TOPLEFT", x - 2, -1)
    cell.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x - 2, 1)
end

-- ── the table ───────────────────────────────────────────────────────────────────────────────────

local Table = {}
Table.__index = Table

-- A fixed column's width: a resizable one's dragged width from `widths` (held to its resize range),
-- else its configured one.
local function fixedWidth(col, widths)
    local stored = col.resize and widths and tonumber(widths[col.key])
    if not stored then return col.width end
    return math.max(col.resize.min, math.min(col.resize.max, math.floor(stored + 0.5)))
end

-- Where the flex column would fall below its minimum, the resizable columns give back what their
-- drag took past their configured width, in column order, so the table still fits Tbl.MinWidth.
local function giveBack(columns, ws, short)
    for i, col in ipairs(columns) do
        if short <= 0 then return end
        local over = col.resize and ws[i] - col.width or 0
        if over > 0 then
            local take = math.min(over, short)
            ws[i], short = ws[i] - take, short - take
        end
    end
end

--- Column widths for `width`: each its configured width (a resizable column's dragged width from
--- `widths`, `{ [key] = px }`, when it has one), the flex column what is left (never below its
--- minimum). Answers the x of each column and its width, in column order.
function Tbl.Columns(columns, width, widths)
    local ws, fixed, flexAt = {}, 0, nil
    for i, col in ipairs(columns) do
        if col.flex then flexAt = i else ws[i] = fixedWidth(col, widths); fixed = fixed + ws[i] end
    end
    local inner = width - 2 * Tbl.PAD - Tbl.SCROLLBAR_W - Tbl.PAD * (#columns - 1)
    if flexAt then
        local min = columns[flexAt].min or 40
        giveBack(columns, ws, min - (inner - fixed))
        fixed = 0
        for i in pairs(ws) do fixed = fixed + ws[i] end
        ws[flexAt] = math.max(min, inner - fixed)
    end
    local out, x = {}, Tbl.PAD
    for i = 1, #columns do
        out[i] = { x = x, w = ws[i] }
        x = x + ws[i] + Tbl.PAD
    end
    return out
end

--- The least width the columns fit in (every fixed column, the flex one at its minimum, the pads and
--- the scrollbar). Pure: the shell's minimum width is held to it (tests/test_results_table.lua).
function Tbl.MinWidth(columns)
    local w = 2 * Tbl.PAD + Tbl.SCROLLBAR_W + Tbl.PAD * (#columns - 1)
    for _, col in ipairs(columns) do w = w + (col.flex and (col.min or 40) or col.width) end
    return w
end

-- The sort marks: the catalog's arrows inline after the label, tinted the skin's `icon.arrow` (an
-- inline texture ignores its FontString's color), Blizzard's arrows beneath them (LootHistory's).
-- Markup is a string, so both are built again on a skin change, by a listener registered here, ahead
-- of the one below that redraws every header (Style.OnLooks runs its listeners in registration order).
local ARROW_UP, ARROW_DOWN
local function buildArrows()
    local c = Style.Tok("icon.arrow")
    ARROW_UP = " " .. Style.IconMarkup("sort-up", "Interface\\Buttons\\Arrow-Up-Up", c)
    ARROW_DOWN = " " .. Style.IconMarkup("sort-down", "Interface\\Buttons\\Arrow-Down-Up", c)
end
buildArrows()
Style.OnLooks(buildArrows)

-- The cursor's x in `frame`'s scale.
local function cursorX(frame)
    if not GetCursorPosition then return 0 end
    local scale = frame.GetEffectiveScale and tonumber(frame:GetEffectiveScale()) or 1
    return (tonumber((GetCursorPosition())) or 0) / (scale > 0 and scale or 1)
end

-- A resizable column's grip: the header's right edge, over the gap to the next column, with a rule
-- that shows under the pointer and while held. Held, the column follows the cursor (Table:DragColumn,
-- nothing stored); released, or hidden while held, it stays and the table's onColumnResize stores
-- the width it reached.
local function newGrip(t, b, col)
    local g = CreateFrame("Frame", nil, t.header)
    g:SetWidth(Tbl.PAD + 2)
    g:SetPoint("TOP", b, "TOPRIGHT", Tbl.PAD / 2, 0)
    g:SetPoint("BOTTOM", b, "BOTTOMRIGHT", Tbl.PAD / 2, 0)
    g:SetFrameLevel((b:GetFrameLevel() or 0) + 2)
    g:EnableMouse(true)
    g.rule = g:CreateTexture(nil, "OVERLAY")
    g.rule:SetWidth(1)
    g.rule:SetPoint("TOP", g, "TOP", 0, -2)
    g.rule:SetPoint("BOTTOM", g, "BOTTOM", 0, 2)
    Style.Fill(g.rule, "ct.scroll.thumbAlt")
    g.rule:Hide()
    g:SetScript("OnEnter", function() g.rule:Show() end)
    g:SetScript("OnLeave", function() if not g.from then g.rule:Hide() end end)
    g:SetScript("OnMouseDown", function(_, button)
        if button and button ~= "LeftButton" then return end
        g.from = { x = cursorX(g), w = t:ColumnWidth(col.key) }
        g:SetScript("OnUpdate", function() t:DragColumn(col.key, g.from.w + cursorX(g) - g.from.x) end)
    end)
    local function release()
        if not g.from then return end
        g:SetScript("OnUpdate", nil)
        g.from = nil
        g.rule:Hide()
        t:EndColumnDrag(col.key)
    end
    g:SetScript("OnMouseUp", release)
    -- A window hidden while the edge is held (Escape, or Close when combat starts) never sees the
    -- mouse-up; the hide ends the drag as a release would (modules/Sizing.lua's hookHide, the grip's).
    g:SetScript("OnHide", release)
    return g
end

-- A column header: GameFontNormalSmall in the header gold, Title Case, the sort mark after its label.
local function newHeader(t, i, col)
    local b = CreateFrame("Button", nil, t.header)
    b:SetHeight(Tbl.HEADER_H)
    b.label = Tbl.Text(b, FONT.HEADER, Style.Tok("list.header.text"), col.justify)
    b.label:SetText(col.label or "")
    b.col = col
    if col.sort then
        b:SetScript("OnClick", function() t:SetSort(col.key) end)
    end
    -- The header's tooltip (LootHistory's): the column's name in gold, then what it shows.
    b:SetScript("OnEnter", function(self)
        local about = NS.ResultsTips and NS.ResultsTips.About(col)
        if not (GameTooltip and about) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(col.label ~= "" and col.label or about.title or "", Style.Rgb("gtip.title"))
        local r, g, bl = Style.Rgb("gtip.body")
        GameTooltip:AddLine(about.text, r, g, bl, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", hideTip)
    if col.resize then b.grip = newGrip(t, b, col) end
    t.heads[i] = b
    return b
end

local function rowBackground(row)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    -- White, so Style.Stripe's vertex tint shows: a texture with no file draws nothing, which left the
    -- list unstriped (owner, 2026-11-11; DPS Race sets it the same way).
    row.bg:SetTexture(Style.WHITE)
    row.sel = row:CreateTexture(nil, "BORDER")
    row.sel:SetAllPoints(row)
    Style.Fill(row.sel, "ct.list.sel")   -- the selection and hover washes: the list's own
    row.sel:Hide()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    Style.Fill(hl, "ct.list.hover")
end

local function newRow(t)
    local row = CreateFrame("Button", nil, t.body)
    row:SetHeight(Tbl.RowHeight())
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    rowBackground(row)
    row.cells = {}
    for i, col in ipairs(t.columns) do
        row.cells[col.key] = Cells[col.kind or "text"](row, col)
        row.cells[i] = row.cells[col.key]
    end
    -- A group header (LootHistory's): its chevron, label and count across the row; a click folds it.
    row.groupLabel = Tbl.Text(row, FONT.HEADER, Style.GOLD)
    row.groupLabel:SetPoint("LEFT", row, "LEFT", Tbl.PAD, 0)
    row.groupLabel:Hide()
    -- Left: select (a header folds its group). Right: the row's menu (LootHistory's).
    row:SetScript("OnClick", function(self, button)
        if self.group then return t:ToggleCollapse(self.group.key) end
        if not self.record then return end
        if button == "RightButton" then
            if t.onRightClick then t.onRightClick(self.record, self) end
            return
        end
        if t.onClick then t.onClick(self.record) end
    end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) t:Scroll(delta) end)
    row:SetScript("OnEnter", function(self)
        self.tipCol = nil
        self:SetScript("OnUpdate", function(r) t:HoverCell(r) end)
        t:HoverCell(self)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        self.tipCol = nil
        hideTip()
    end)
    t.made = t.made + 1
    return row
end

-- Every list ever made (weakly held), for a skin change: its header's sort mark, whose markup was
-- built again.
local tables = setmetatable({}, { __mode = "k" })
Style.OnLooks(function() for t in pairs(tables) do t:paintHeader() end end)

local function buildScrollbar(t)
    local bar = CreateFrame("Slider", nil, t.frame)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(Tbl.SCROLLBAR_W)
    bar:SetPoint("TOPRIGHT", t.frame, "TOPRIGHT", -2, -Tbl.HEADER_H - 2)
    bar:SetPoint("BOTTOMRIGHT", t.frame, "BOTTOMRIGHT", -2, 2)
    bar:SetValueStep(1)
    if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints(bar)
    Style.Fill(bar.track, "ct.scroll.track")
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    Style.Fill(thumb, "ct.scroll.thumb")
    thumb:SetSize(Tbl.SCROLLBAR_W - 2, 28)
    bar:SetThumbTexture(thumb)
    bar:SetScript("OnValueChanged", function(_, value)
        if t.syncing then return end
        t:ScrollTo(math.floor((value or 0) + 0.5))
    end)
    t.scrollbar = bar
end

--- A sortable, scrolling list in `parent` (which it fills).
--- @param parent table
--- @param columns table  { key, label, kind = "text"|"icons"|"badge"|"items", width | flex+min,
---                         tip = fn(record) -> lines, about = header text, justify,
---                         sort = fn(record) -> value, desc = default direction, text = fn(record),
---                         bar = fn(record) -> value, scan = fn(list, groupOf) on SetData and SetGroup,
---                         items = fn(record) -> { texture, ... } | nil (an items column),
---                         resize = { min, max } (a fixed column its header's edge drags) }
--- @param opts table  { sortKey, sortDesc, onClick(record), onRightClick(record, row), empty = text,
---                      widths = fn() -> { [key] = px } (the dragged widths of the `resize` columns),
---                      onColumnResize(key, px) (a header edge's release) }
function Tbl.New(parent, columns, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    local t = setmetatable({
        frame = frame, columns = columns, heads = {}, pool = NS.Pool.New(), shown = {}, made = 0,
        data = {}, rows = {}, offset = 0, width = 600, height = 300,
        sortKey = opts.sortKey, sortDesc = opts.sortDesc ~= false,
        onClick = opts.onClick, onRightClick = opts.onRightClick,
        widthsOf = opts.widths, onColumnResize = opts.onColumnResize,
    }, Table)
    t.header = CreateFrame("Frame", nil, frame)
    t.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    t.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    t.header:SetHeight(Tbl.HEADER_H)
    -- The header band LootHistory's takes: the skin's list.header.bg behind the labels (none under
    -- Ka0s Default), and no rule above or below.
    NS.Skin.SortHeaderBar(t.header)
    for i, col in ipairs(columns) do newHeader(t, i, col) end
    t.body = CreateFrame("Frame", nil, frame)
    t.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -Tbl.HEADER_H)
    t.body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    t.body:EnableMouseWheel(true)
    t.body:SetScript("OnMouseWheel", function(_, delta) t:Scroll(delta) end)
    t.empty = Tbl.Text(t.body, FONT.EMPTY, nil, "CENTER")
    t.empty:SetPoint("TOP", t.body, "TOP", 0, -24)
    t.empty:SetText(opts.empty or "")
    buildScrollbar(t)
    t:paintHeader()
    tables[t] = true
    return t
end

function Table:column(key)
    for _, col in ipairs(self.columns) do if col.key == key then return col end end
end

--- The sort mark the header shows now: "" off the sorted column, else the direction's arrow.
function Table:SortMark(key)
    if key ~= self.sortKey then return "" end
    return self.sortDesc and ARROW_DOWN or ARROW_UP
end

function Table:paintHeader()
    for _, b in ipairs(self.heads) do
        b.label:SetText((b.col.label or "") .. self:SortMark(b.col.key))
    end
end

-- `a` before `b` under (key, desc): a missing value last, a tie to the newer fight, then the id.
local function comparator(col, desc)
    local value = col.sort
    return function(a, b)
        local va, vb = value(a), value(b)
        if va ~= vb then
            if va == nil then return false end
            if vb == nil then return true end
            if desc then return va > vb end
            return va < vb
        end
        local ta, tb = a.t or 0, b.t or 0
        if ta ~= tb then return ta > tb end
        return tostring(a.id) > tostring(b.id)
    end
end

--- `list` sorted (a new array) by column `key`, descending when `desc`.
function Tbl.Sort(columns, list, key, desc)
    local out = {}
    for i, record in ipairs(list or {}) do out[i] = record end
    local col
    for _, c in ipairs(columns) do if c.key == key then col = c end end
    if col and col.sort then table.sort(out, comparator(col, desc)) end
    return out
end

--- Sort by `key`: the same column again flips the direction; a new one starts at its own default.
--- `desc` given sets the direction outright (a saved view).
function Table:SetSort(key, desc)
    local col = self:column(key)
    if not (col and col.sort) then return end
    if desc ~= nil then
        self.sortDesc = desc and true or false
    elseif key == self.sortKey then
        self.sortDesc = not self.sortDesc
    else
        self.sortDesc = col.desc ~= false
    end
    self.sortKey = key
    self:paintHeader()
    self.rows = self:group(Tbl.Sort(self.columns, self.data, self.sortKey, self.sortDesc))
    self:Bind()
end

--- The key of the group `record` falls in under `spec` (Table:SetGroup's shape), as Table:group keys
--- it; `true` for every fight of a flat list, which is one group.
function Tbl.GroupKey(spec, record)
    if not spec then return true end
    return tostring((spec.of(record)))
end

-- Measure the list per group. Each bar column's scale is the smallest and the largest value in the
-- fight's own group: every fight of it the filters pass, folded or scrolled out of view or not. A
-- column that reads the whole list (the Delta column) sees it here, with the grouping's key, before
-- a sort. A flat list is one group. Nothing is stored on a record: it is redone on every SetData and
-- SetGroup.
local function barRanges(col, data, groupOf)
    local ranges = {}
    for _, record in ipairs(data) do
        local v = col.bar(record)
        if type(v) == "number" then
            local key = groupOf(record)
            local r = ranges[key]
            if not r then
                r = { min = v, max = v }
                ranges[key] = r
            end
            if v < r.min then r.min = v end
            if v > r.max then r.max = v end
        end
    end
    return ranges
end

function Table:measure()
    local spec = self.grouping
    local function groupOf(record) return Tbl.GroupKey(spec, record) end
    -- The whole-list scan (the Delta column) keys by the grouping's `delta` where it has one.
    local scanOf = groupOf
    if spec and spec.delta then scanOf = function(record) return tostring((spec.delta(record))) end end
    for _, col in ipairs(self.columns) do
        if col.scan then col.scan(self.data, scanOf) end
        if col.bar then
            col.groupOf = groupOf
            col.barRanges = barRanges(col, self.data, groupOf)
        end
    end
end

--- Replace the list (any order) and redraw it sorted, keeping the scroll where it can.
function Table:SetData(list)
    self.data = list or {}
    self:measure()
    self.rows = self:group(Tbl.Sort(self.columns, self.data, self.sortKey, self.sortDesc))
    self:Bind()
end

-- ── grouping (LootHistory's BrowserTableGroup) ─────────────────────────────────────────────────
-- With a grouping set, the sorted fights are partitioned into groups in first-seen order, the groups
-- ordered by their own rank (ascending), and each group is preceded by a header entry { group = {
-- key, label, count, collapsed } }. A collapsed group emits only its header. The row sort still holds
-- inside each group.

--- Group by `spec` ({ of = fn(record) -> key, label, rank }), or nil for a flat list. Redraws.
function Table:SetGroup(spec)
    self.grouping = spec
    self:measure()
    self.rows = self:group(Tbl.Sort(self.columns, self.data or {}, self.sortKey, self.sortDesc))
    self:Bind()
end

--- Fold or unfold the group with `key`.
function Table:ToggleCollapse(key)
    self.collapsed = self.collapsed or {}
    self.collapsed[key] = (not self.collapsed[key]) or nil
    self.rows = self:group(Tbl.Sort(self.columns, self.data or {}, self.sortKey, self.sortDesc))
    self:Bind()
end

local function byRank(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.key < b.key
end

function Table:group(sorted)
    local spec = self.grouping
    if not spec then return sorted end
    self.collapsed = self.collapsed or {}
    local order, byKey = {}, {}
    for _, record in ipairs(sorted) do
        local key, label, rank = spec.of(record)
        key = tostring(key)
        local g = byKey[key]
        if not g then
            g = { key = key, label = label or key, rank = rank or label or key, records = {} }
            byKey[key] = g
            order[#order + 1] = g
        end
        g.records[#g.records + 1] = record
    end
    table.sort(order, byRank)
    local out = {}
    for _, g in ipairs(order) do
        local collapsed = self.collapsed[g.key] == true
        out[#out + 1] = { group = { key = g.key, label = g.label, count = #g.records, collapsed = collapsed } }
        if not collapsed then
            for _, record in ipairs(g.records) do out[#out + 1] = record end
        end
    end
    return out
end

--- The column under the cursor on `row`, or nil.
function Table:columnAt(row)
    if not (self.place and GetCursorPosition and row.GetLeft) then return nil end
    local cx = GetCursorPosition() / (row:GetEffectiveScale() or 1)
    local x = cx - (row:GetLeft() or 0)
    for c, spot in ipairs(self.place) do
        if x >= spot.x - Tbl.PAD / 2 and x < spot.x + spot.w + Tbl.PAD / 2 then return c end
    end
    return nil
end

--- The tooltip lines for `entry` (a fight or a group header) in column `c`, or nil.
function Table:TipLines(entry, c)
    local Tips = NS.ResultsTips
    if not (Tips and entry) then return nil end
    if entry.group then return Tips.Group(entry.group) end
    local col = self.columns[c]
    return col and Tips.Cell(col, entry)
end

--- Show the tooltip of the cell under the cursor on `row`, when it changed column.
function Table:HoverCell(row)
    local entry = row.group and { group = row.group } or row.record
    local c = row.group and 0 or self:columnAt(row)
    if c == row.tipCol then return end
    row.tipCol = c
    local lines = c and self:TipLines(entry, c)
    if lines then Tbl.SideTip(windowOf(self.frame), row, lines) else hideTip() end
end

function Table:visibleCount()
    return math.max(1, math.floor((self.height - Tbl.HEADER_H) / Tbl.RowHeight()))
end

function Table:maxOffset()
    return math.max(0, #self.rows - self:visibleCount())
end

--- Scroll so the list starts at `offset` (clamped).
function Table:ScrollTo(offset)
    offset = math.max(0, math.min(self:maxOffset(), math.floor(offset or 0)))
    if offset == self.offset then return end
    self.offset = offset
    self:Bind()
end

--- One mouse-wheel notch: `delta` > 0 scrolls up.
function Table:Scroll(delta)
    self:ScrollTo(self.offset - (delta or 0) * Tbl.WHEEL_ROWS)
end

--- Bring the fight with `id` into view, if it is in the list.
function Table:Reveal(id)
    for i, record in ipairs(self.rows) do
        if record.group == nil and record.id == id then
            local first, count = self.offset + 1, self:visibleCount()
            if i < first then self:ScrollTo(i - 1) elseif i >= first + count then self:ScrollTo(i - count) end
            return true
        end
    end
    return false
end

--- Mark the fight with `id` as the selected one.
function Table:SetSelected(id)
    self.selected = id
    for _, row in ipairs(self.shown) do row.sel:SetShown(row.record ~= nil and row.record.id == id) end
end

function Table:placeRow(row, i)
    local h = Tbl.RowHeight()
    local y = -(i - 1) * h
    row:SetHeight(h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", self.body, "TOPRIGHT", -Tbl.SCROLLBAR_W - 2, y)
    if row.layout == self.layoutVersion then return end
    row.layout = self.layoutVersion
    for c, col in ipairs(self.columns) do
        local spot = self.place[c]
        placeCell(row, row.cells[c], col, spot.x, spot.w)
    end
end

-- Every drawn part of a row's cells, shown or hidden at once (a header row draws none of them; a
-- fight row shows them all and each Bind hides what it does not draw).
local function showCells(row, on)
    for _, cell in ipairs(row.cells) do
        for _, part in pairs(cell) do
            if type(part) == "table" and part.SetShown then part:SetShown(on) end
        end
    end
end

-- The disclosure marks: the catalog's chevrons, tinted the skin's `icon.arrow` (an inline texture
-- ignores its FontString's color), Blizzard's minus and plus beneath them; built again on a skin
-- change, as the sort marks are.
local CHEVRON_OPEN, CHEVRON_SHUT
local function buildChevrons()
    local c = Style.Tok("icon.arrow")
    CHEVRON_OPEN = Style.IconMarkup("chevron-down", "Interface\\Buttons\\UI-MinusButton-Up", c)
    CHEVRON_SHUT = Style.IconMarkup("chevron-right", "Interface\\Buttons\\UI-PlusButton-Up", c)
end
buildChevrons()
Style.OnLooks(buildChevrons)

local function bindHeader(row, g)
    row.record, row.group = nil, g
    row.sel:Hide()
    showCells(row, false)
    row.groupLabel:SetText(("%s  %s  %s(%d)|r"):format(g.collapsed and CHEVRON_SHUT or CHEVRON_OPEN,
        g.label, NS.SkinEscape("text.disabled") or "", g.count))
    row.groupLabel:Show()
end

function Table:bindRow(row, record, index)
    Style.Stripe(row.bg, index)
    if record.group then return bindHeader(row, record.group) end
    row.record, row.index, row.group = record, index, nil
    row.groupLabel:Hide()
    showCells(row, true)
    row.sel:SetShown(self.selected ~= nil and record.id == self.selected)
    for c, col in ipairs(self.columns) do Bind[col.kind or "text"](row.cells[c], col, record) end
end

function Table:syncScrollbar()
    local bar, top = self.scrollbar, self:maxOffset()
    self.syncing = true
    bar:SetMinMaxValues(0, top)
    bar:SetValue(self.offset)
    self.syncing = false
    bar:SetShown(top > 0)
end

--- Redraw the visible slice from the pool.
---
--- A redraw can run inside another: the first row an open shows can resolve the window's rect, and
--- the client runs its OnSizeChanged right there, a full layout and a Bind inside this one's Acquire.
--- That inner Bind released this one's rows and drew the whole slice; carrying on would draw a
--- second set over it that the list does not hold. So each Bind counts itself, and one that finds a
--- newer Bind ran inside it stops: the newer one's rows stand.
function Table:Bind()
    local pass = (self.binds or 0) + 1
    self.binds = pass
    self.offset = math.max(0, math.min(self.offset, self:maxOffset()))
    NS.Pool.ReleaseAll(self.pool, function(row) row.record, row.group = nil, nil end)
    self.shown, self.spare = {}, {}
    local count = math.min(self:visibleCount(), #self.rows - self.offset)
    for i = 1, count do
        local row = NS.Pool.Acquire(self.pool, function() return newRow(self) end)
        if self.binds ~= pass then return end
        self:placeRow(row, i)
        self:bindRow(row, self.rows[self.offset + i], self.offset + i)
        self.shown[i] = row
    end
    self.empty:SetShown(#self.rows == 0)
    self:syncScrollbar()
end

-- The dragged widths in force: the live drag's over the stored ones.
function Table:widths()
    local stored = self.widthsOf and self.widthsOf() or {}
    if not self.dragging then return stored end
    local out = {}
    for k, v in pairs(stored) do out[k] = v end
    for k, v in pairs(self.dragging) do out[k] = v end
    return out
end

-- The columns at `width` and the header's labels on them; a row's cells follow on its next placeRow.
function Table:placeColumns(width)
    self.width = width
    self.place = Tbl.Columns(self.columns, width, self:widths())
    self.layoutVersion = (self.layoutVersion or 0) + 1
    for i, b in ipairs(self.heads) do
        local spot = self.place[i]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self.header, "TOPLEFT", spot.x, 0)
        b:SetWidth(spot.w)
        b.label:ClearAllPoints()
        b.label:SetAllPoints(b)
    end
end

--- Column `key`'s width as laid out now, or nil.
function Table:ColumnWidth(key)
    for i, col in ipairs(self.columns) do
        if col.key == key then return self.place and self.place[i] and self.place[i].w or col.width end
    end
end

--- While a header edge is held: column `key` at `w` px (held to its range and the room the flex
--- column leaves), the header and the rows shown re-placed, nothing stored and nothing rebound.
function Table:DragColumn(key, w)
    if type(w) ~= "number" then return end
    self.dragging = { [key] = w }
    self:placeColumns(self.width)
    for i, row in ipairs(self.shown) do self:placeRow(row, i) end
end

--- A header edge's release: the width the column reached is handed to onColumnResize to store.
function Table:EndColumnDrag(key)
    if not self.dragging then return end
    local w = self:ColumnWidth(key)
    self.dragging = nil
    if self.onColumnResize and w then self.onColumnResize(key, w) end
    self:placeColumns(self.width)
    for i, row in ipairs(self.shown) do self:placeRow(row, i) end
end

--- Lay the header and the rows out for `width` x `height`.
function Table:Layout(width, height)
    self.height = height
    self:placeColumns(width)
    self:Bind()
end

-- The rows shown to the count that fits now, from the offset held: a row past it hidden and kept
-- spare, a row the new height adds taken from the spares (or the pool) and bound alone.
function Table:fitRows()
    local count = math.max(0, math.min(self:visibleCount(), #self.rows - self.offset))
    self.spare = self.spare or {}
    for i = #self.shown, count + 1, -1 do
        local row = self.shown[i]
        self.shown[i] = nil
        row:Hide()
        self.spare[#self.spare + 1] = row
    end
    local pass = self.binds
    for i = #self.shown + 1, count do
        local row = table.remove(self.spare) or NS.Pool.Acquire(self.pool, function() return newRow(self) end)
        row:Show()
        -- A Bind that ran inside the Show (Table:Bind's note) drew the slice already.
        if self.binds ~= pass then return end
        self:placeRow(row, i)
        self:bindRow(row, self.rows[self.offset + i], self.offset + i)
        self.shown[i] = row
    end
end

--- While the window is being sized (modules/Sizing.lua): the columns at `width`, the rows that fit
--- `height` and the scroll range, with nothing rebound. The rows shown keep what they draw, their
--- cells re-placed when the width moved; the offset holds. The release's Layout rebinds them all.
function Table:Resize(width, height)
    if width ~= self.width then
        self:placeColumns(width)
        for i, row in ipairs(self.shown) do self:placeRow(row, i) end
    end
    self.height = height
    self:fitRows()
    self:syncScrollbar()
end

--- The rows drawn now, top down (the suites read these).
function Table:Visible()
    return self.shown
end

--- How many row frames this list has ever made (the pool's whole size; the suites read it).
function Table:Made()
    return self.made
end
