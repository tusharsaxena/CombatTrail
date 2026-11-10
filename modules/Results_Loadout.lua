local _, NS = ...
-- modules/Results_Loadout.lua — the fight detail's Gear and Talents (spec §7, mockup §5): what the
-- fight was fought with. Adapted from DPS Race @045f479 (modules/Results_Loadout.lua) for Combat
-- Trail's record: the gear rides the record as trimmed item strings (modules/Loadouts.lua), the
-- talents are stored once and referenced by key (record.loadout, Loadouts.Get).
--
-- THE GEAR is a row of item icons in the character frame's order, wrapping across the pane, each
-- with its quality edge and item level (mockup §5's gear row); hovering one shows the client's own
-- item tooltip from the stored item string, and Shift-click links it in chat. *Gear view* (the gear
-- and the stats laid out as the character panel does) is modules/Results_Gear.lua's, plan Task 4.4:
-- the button stays grayed until that window exists. A fight with no gear says *Not recorded*.
--
-- THE TALENTS line names the loadout and its hero tree, with *View* (the `talentbuild` link posted to
-- the player's own chat window, and the tree opened read-only through SetItemRef; the Results window
-- steps aside for the tree, modules/Results.lua) and *Copy* (the import string in the copy window).
--
-- THE TAINT RISK IS DPS RACE'S OWNER'S CALL (2026-10-25), kept: SetItemRef from this button shows the
-- talent frame from this addon's execution, and its OnShow writes the action bars' show-grid state
-- tainted, so a later in-combat slot change can end in ADDON_ACTION_BLOCKED (seen once in game).
-- Clicking the posted chat link instead opens the tree without that risk, which is why it is posted.
--
-- PLAIN DATA ONLY: item strings, names and import strings stored out of combat. The row is laid out
-- from the constants here, never from a size read back. Order, ItemID, LinkData, Hyperlink, CanView
-- and TalentsText are pure.

local Loadout = {}
NS.ResultsLoadout = Loadout

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT

Loadout.ICON = 24          -- an item's icon, inside its 1px quality edge
Loadout.PITCH = 28         -- one icon's step across, and one row's down
Loadout.BUTTON_H = 18
Loadout.GEAR_W = 76        -- the Gear view button
Loadout.TALENT_W = 52      -- View and Copy
Loadout.LINE_H = 14
-- The color the client draws a talentbuild link in (NORMAL_FONT_COLOR): a DATA hue, the link's own
-- under every skin, since it is what another player's chat draws.
Loadout.LINK_COLOR = { 1, 0.82, 0 }

-- The character frame's order: its left column (head down to the wrists, then the weapons), then its
-- right (hands down to the trinkets).
Loadout.ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

local SEP = " \194\183 "

-- ── pure ────────────────────────────────────────────────────────────────────────────────────────

--- The record's gear as the row draws it: { { slot, item } } in the character frame's order, only
--- the slots that hold an item. nil when the fight has no gear recorded.
--- @param record table|nil
--- @return table|nil
function Loadout.Order(record)
    local gear = type(record) == "table" and record.gear or nil
    if type(gear) ~= "table" then return nil end
    local out = {}
    for _, slot in ipairs(Loadout.ORDER) do
        local item = gear[slot]
        if type(item) == "string" and item ~= "" then out[#out + 1] = { slot = slot, item = item } end
    end
    return out[1] and out or nil
end

--- A trimmed item string's item ID.
function Loadout.ItemID(item)
    return type(item) == "string" and tonumber(item:match("^(%d+)")) or nil
end

--- The record's talent loadout ({ importString, specID, name, heroSpecID, heroName }), or nil.
function Loadout.TalentsOf(record)
    local key = type(record) == "table" and record.loadout or nil
    if key == nil then return nil end
    return NS.Loadouts.Get(key)
end

--- The talentbuild link's data, "talentbuild:<specID>:<level>:<importString>", or nil without a
--- string.
--- @param t table|nil  a stored loadout
--- @param level number|nil  the character's level when it fought
function Loadout.LinkData(t, level)
    if type(t) ~= "table" or type(t.importString) ~= "string" or t.importString == "" then return nil end
    return ("talentbuild:%d:%d:%s"):format(tonumber(t.specID) or 0, tonumber(level) or 0, t.importString)
end

--- The loadout's chat hyperlink, [text] in the client's link color, or nil.
function Loadout.Hyperlink(t, level, text)
    local data = Loadout.LinkData(t, level)
    if not data then return nil end
    local label = tostring(text or (t.name or L["Talents"])):gsub("[|%[%]]", "")
    return ("%s|H%s|h[%s]|h|r"):format(Style.HueEscape(Loadout.LINK_COLOR), data, label)
end

--- Whether View can open the loadout: it has an import string.
--- @return boolean
function Loadout.CanView(t)
    return Loadout.LinkData(t) ~= nil
end

--- The talents line: the loadout's name, then its hero tree; "Not recorded" with none.
function Loadout.TalentsText(t)
    if type(t) ~= "table" then return L["Not recorded"] end
    local parts = { t.name or L["Unnamed loadout"] }
    if t.heroName then parts[#parts + 1] = t.heroName end
    return table.concat(parts, SEP)
end

-- ── the client's item data ──────────────────────────────────────────────────────────────────────

local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

local function itemApi(name)
    return type(C_Item) == "table" and C_Item[name] or nil
end

-- An item's icon, quality, item level and full link, from its item string (each pcall'd; an item
-- the client has not cached answers what it can).
local function itemInfo(item)
    local s = NS.Loadouts.ItemString(item)
    local id = Loadout.ItemID(item)
    local icon = ask(itemApi("GetItemIconByID"), id)
    local q = ask(itemApi("GetItemQualityByID"), s)
    local ilvl = ask(itemApi("GetDetailedItemLevelInfo"), s)
    local _, link = ask(itemApi("GetItemInfo"), s)
    return icon, q, ilvl, link
end

-- ── the acts ────────────────────────────────────────────────────────────────────────────────────

--- Open the loadout's talent tree, read-only, through SetItemRef with its talentbuild link, after
--- posting the same link to the player's own chat window (the safe way to open it again).
--- @return boolean opened
function Loadout.View(t, level, label)
    if not Loadout.CanView(t) then return false end
    local link = Loadout.Hyperlink(t, level)
    NS.Print(L["Talents for %s: %s. Click the link to see the tree."]:format(label or L["this fight"], link))
    local open = SetItemRef
    if type(open) ~= "function" then return false end
    local ok = pcall(open, Loadout.LinkData(t, level), link, "LeftButton")
    if ok and NS.Results and NS.Results.StepAsideForTree then NS.Results.StepAsideForTree() end
    return ok
end

--- The loadout's import string in the copy window (in chat without the library).
--- @return boolean shown
function Loadout.Copy(t, anchor)
    if type(t) ~= "table" or type(t.importString) ~= "string" then return false end
    if NS.ShowCopy(t.importString, L["Talent loadout"], anchor) then return true end
    NS.Print(t.importString)
    return true
end

--- The fight View names in its chat line: its character and date.
function Loadout.Label(record)
    local w = type(record) == "table" and type(record.who) == "table" and record.who or {}
    return ("%s, %s"):format(tostring(w.name or "?"), NS.ResultsTable.Date(record and record.t, "%d %b %H:%M"))
end

-- Whether the gear view exists yet (plan Task 4.4).
local function hasGearView()
    local G = NS.ResultsGear
    return G ~= nil and type(G.Open) == "function"
end

-- ── the parts ───────────────────────────────────────────────────────────────────────────────────

local function itemTip(cell)
    local tt = GameTooltip
    if not (tt and cell.item) then return end
    tt:SetOwner(cell, "ANCHOR_RIGHT")
    if not pcall(tt.SetHyperlink, tt, NS.Loadouts.ItemString(cell.item)) then
        tt:SetText(L["Item %d"]:format(Loadout.ItemID(cell.item) or 0), Style.Rgb("gtip.value"))
    end
    tt:Show()
end

local function onItemClick(cell)
    local link = cell.link
    if not link then return end
    local handle = HandleModifiedItemClick
    if type(handle) == "function" then pcall(handle, link) end
end

local function newCell(host)
    local cell = CreateFrame("Button", nil, host)
    cell:SetSize(Loadout.ICON + 2, Loadout.ICON + 2)
    cell.edge = cell:CreateTexture(nil, "BORDER")
    cell.edge:SetAllPoints(cell)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(Loadout.ICON, Loadout.ICON)
    cell.icon:SetPoint("CENTER", cell, "CENTER", 0, 0)
    Style.CropIcon(cell.icon)
    cell.ilvl = Style.Text(cell, FONT.TEXT, NS.ResultsTable.COLORS.text, "CENTER")
    cell.ilvl:SetPoint("BOTTOM", cell, "BOTTOM", 0, 1)
    cell:SetScript("OnEnter", itemTip)
    cell:SetScript("OnLeave", NS.ResultsTable.HideTip)
    cell:SetScript("OnClick", onItemClick)
    return cell
end

--- Build the Gear and Talents parts into the pane `p` (its content `c`), as `p.lo`.
function Loadout.Build(p, c)
    local x = { cells = {} }
    p.lo = x
    local C = NS.ResultsTable.COLORS
    x.title = Style.Text(c, FONT.SECTION)
    x.title:SetText(L["Gear and Talents"])
    x.ilvl = Style.Text(c, FONT.CAPTION, C.text)
    x.ilvl:SetPoint("BOTTOMLEFT", x.title, "BOTTOMRIGHT", 6, 2)
    x.gearView = Style.Button(c, L["Gear view"], function()
        if hasGearView() and p.record then NS.ResultsGear.Open(p) end
    end)
    x.gearView:SetSize(Loadout.GEAR_W, Loadout.BUTTON_H)
    x.none = Style.Text(c, FONT.TEXT, C.dim)
    x.none:SetText(L["Gear not recorded"])
    x.grid = CreateFrame("Frame", nil, c)
    x.talents = Style.Text(c, FONT.TEXT, C.text)
    x.view = Style.Button(c, L["View"], function()
        Loadout.View(x.talentsData, nil, Loadout.Label(p.record))
    end)
    x.copy = Style.Button(c, L["Copy"], function()
        Loadout.Copy(x.talentsData, NS.ResultsTable.WindowOf(p.frame))
    end)
    for _, b in ipairs({ x.view, x.copy }) do b:SetSize(Loadout.TALENT_W, Loadout.BUTTON_H) end
    x.gearView.tip = { L["Gear view"], L["The fight's gear and stats, laid out as the character panel does."] }
    x.view.tip = { L["View"], L["Posts the loadout's link to your chat and opens the talent tree, read-only."] }
    x.copy.tip = { L["Copy"], L["The loadout's import string, to paste into the talent frame."] }
    return x
end

local function fillCell(cell, entry)
    cell.slot, cell.item = entry.slot, entry.item
    local icon, q, ilvl, link = itemInfo(entry.item)
    cell.link = link
    local r, g, b = NS.QualityColor(q)
    if r then Style.Fill(cell.edge, { r, g, b }, 1) else Style.Fill(cell.edge, "ct.slot.empty") end
    cell.icon:SetTexture(icon)
    cell.ilvl:SetText(type(ilvl) == "number" and tostring(math.floor(ilvl)) or "")
end

--- Paint the parts from `p.record`.
function Loadout.Fill(p)
    local x, record = p.lo, p.record
    x.items = Loadout.Order(record)
    for i, entry in ipairs(x.items or {}) do
        x.cells[i] = x.cells[i] or newCell(x.grid)
        fillCell(x.cells[i], entry)
    end
    for i = #(x.items or {}) + 1, #x.cells do x.cells[i]:Hide() end
    local w = type(record) == "table" and type(record.who) == "table" and record.who or {}
    x.ilvl:SetText(type(w.ilvl) == "number" and L["ilvl %s"]:format(NS.ResultsTable.Ilvl(w.ilvl)) or "")
    x.talentsData = Loadout.TalentsOf(record)
    x.talents:SetText(L["Talents: %s"]:format(Loadout.TalentsText(x.talentsData)))
    Style.SetEnabled(x.view, Loadout.CanView(x.talentsData))
    Style.SetEnabled(x.copy, x.talentsData ~= nil)
    Style.SetEnabled(x.gearView, hasGearView() and x.items ~= nil)
end

local function place(region, parent, px, py)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", px, py)
end

-- The icons across `cw`, wrapping; answers the y beneath them.
local function layoutGrid(p, x, y, cw)
    local perRow = math.max(1, math.floor((cw + Loadout.PITCH - Loadout.ICON - 2) / Loadout.PITCH))
    local n = #x.items
    local rows = math.ceil(n / perRow)
    place(x.grid, p.content, 0, y)
    x.grid:SetSize(cw, rows * Loadout.PITCH)
    x.grid:Show()
    for i = 1, n do
        local cell = x.cells[i]
        local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
        place(cell, x.grid, col * Loadout.PITCH, -row * Loadout.PITCH)
        cell:Show()
    end
    return y - rows * Loadout.PITCH
end

--- The section at `y` across `cw` (its heading SECTION_GAP under the block above it, Gear view at
--- the heading's right), the gear row and the talents line; answers the y beneath.
function Loadout.Layout(p, y, cw)
    local x = p.lo
    y = y - Style.SECTION_GAP
    place(x.title, p.content, 0, y)
    place(x.gearView, p.content, cw - Loadout.GEAR_W, y)
    y = y - Style.SECTION_H
    x.none:SetShown(x.items == nil)
    if x.items then
        y = layoutGrid(p, x, y, cw) - 4
    else
        x.grid:Hide()
        place(x.none, p.content, 0, y)
        y = y - Loadout.LINE_H - 4
    end
    local tw = Loadout.TALENT_W
    place(x.talents, p.content, 0, y - 3)
    x.talents:SetWidth(math.max(40, cw - 2 * tw - 12))
    place(x.view, p.content, cw - 2 * tw - 4, y)
    place(x.copy, p.content, cw - tw, y)
    return y - Loadout.BUTTON_H - 8
end
