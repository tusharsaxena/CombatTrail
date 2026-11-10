local _, NS = ...
-- modules/Results_Usage.lua — what a fight used (spec §7, mockup §5), as the fight detail shows it,
-- and the player's edit of it. Adapted from DPS Race @045f479 (modules/Results_Usage.lua) without its
-- race and without its Used column (the fight list has none) or its folding heading (spec §7 names one
-- fold arrow, the window's).
--
-- THE SECTION shows what was used: one row per used entry, the item's icon and its name with a dim
-- detail after it ("x2 at 0:09, 1:12", "active at the start", "time unknown"), or a dim *Nothing
-- used*. *Edit* (top right) switches it to every candidate (every on-use gear item and every bag
-- consumable with a use spell at the fight's start) and every used entry no candidate stands for
-- (food), each with a check box whose label is clickable too (Tbl.SetCheckLabel), what was used
-- ticked. *Save*, beside Edit and shown only while editing, is live only while the ticks differ from
-- the stored list; it writes them through Usage.SetUsed (modules/Usage.lua), which keeps a detected
-- entry's times and source, and leaves the edit. *Edit* again, or another fight, leaves it unsaved. A
-- redraw of the same fight mid-edit (another fight saved, an item hidden) keeps the ticks not saved
-- yet, each by its row. While editing, a right-click on an item's row offers *Never show <item>*
-- (Usage.Hide). A sample fight (test mode, the sim) changes in memory only, as its note does. A fight
-- with no usage record says *Not recorded*.
--
-- WHAT IS NEVER LISTED (Usage.Shown): a hidden item (the "never show" list), and an enchant entry. A
-- hidden item the fight used stays in its record: a save keeps it (Edits), so showing it again brings
-- it back.
--
-- PLAIN DATA ONLY: the stored record.usage (modules/Usage.lua: { v, used, candidates, edited }).
-- Item names and icons are the client's item data, read at call time and pcall'd. Rows are laid out
-- from the constants here, never from a size read back; Record, Entries, Rows, UsedRows, Ticks,
-- Edits, Changed, Carry, Clock, Detail and Line are pure over the record and the hidden list.

local ResultsUsage = {}
NS.ResultsUsage = ResultsUsage

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT

ResultsUsage.ROW_H = 22      -- one row: the check box's height and a little air
ResultsUsage.CHECK = 20      -- the check box
ResultsUsage.ICON = 16       -- an item's icon, between the box and its name
ResultsUsage.EDIT_W = 56
ResultsUsage.SAVE_W = 56
ResultsUsage.BUTTON_GAP = 4  -- between Save and Edit
ResultsUsage.BUTTON_H = 18
ResultsUsage.LINE_H = 14
-- The icons of an entry with no item: food's (Spell_Misc_Food) and the question mark, as file ids.
ResultsUsage.FOOD_ICON = 134062
ResultsUsage.UNKNOWN_ICON = 134400

local function Tbl() return NS.ResultsTable end

-- ── pure ────────────────────────────────────────────────────────────────────────────────────────

--- A fight's usage record, or nil for a fight with none (Not recorded).
function ResultsUsage.Record(record)
    local u = type(record) == "table" and record.usage
    if type(u) ~= "table" or type(u.used) ~= "table" then return nil end
    return u
end

--- The used entries in drawing order: the gear first, then everything else, each in its stored
--- order, hidden items and enchant entries left out. nil when not recorded.
--- @return table|nil entries
function ResultsUsage.Entries(record)
    local u = ResultsUsage.Record(record)
    if not u then return nil end
    local hidden, gear, rest = NS.Usage.HiddenSet(), {}, {}
    for _, e in ipairs(u.used) do
        if NS.Usage.Shown(e, hidden) then
            local into = e.kind == "gear" and gear or rest
            into[#into + 1] = e
        end
    end
    for _, e in ipairs(rest) do gear[#gear + 1] = e end
    return gear
end

--- A time on the fight clock as m:ss, a pre-pull one (negative) with its minus sign; one that rounds
--- to the pull itself is 0:00, never -0:00.
function ResultsUsage.Clock(t)
    if type(t) ~= "number" then return "?" end
    if math.floor(t + 0.5) < 0 then return "-" .. NS.Format.Length(-t) end
    return NS.Format.Length(math.max(0, t))
end

--- An entry's detail: how many times and when ("x2 at 0:09, 1:12", "at 0:09"), "active at the start"
--- (a buff on at the pull), or "time unknown" (a bag drop, a manual tick).
function ResultsUsage.Detail(e)
    if type(e) ~= "table" then return "" end
    local n = tonumber(e.n) or 1
    if type(e.times) == "table" and #e.times > 0 then
        local parts = {}
        for i, t in ipairs(e.times) do parts[i] = ResultsUsage.Clock(t) end
        local at = L["at %s"]:format(table.concat(parts, ", "))
        return n > 1 and L["x%d %s"]:format(n, at) or at
    end
    if e.src == "buff" then return L["active at the start"] end
    return n > 1 and L["x%d, time unknown"]:format(n) or L["time unknown"]
end

--- A row's line: the name, then " · " and the detail in the dim color (the name alone with no
--- detail), and the same line plain (what its width is estimated from: Tbl.BadgeWidth).
--- @return string line, string plain
function ResultsUsage.Line(name, detail)
    name = tostring(name or "")
    if type(detail) ~= "string" or detail == "" then return name, name end
    local after = " \194\183 " .. detail
    return ("%s|c%s%s|r"):format(name, Tbl().Hex(Tbl().COLORS.dim), after), name .. after
end

-- Whether used entry `e` is the one candidate `c` stands for: by its item (a gear candidate also by
-- its slot, when the entry has one); a candidate with no item (food the player unticked, kept by
-- Usage.SetUsed) by its kind.
local function stands(c, e)
    if c.itemID ~= nil then
        return e.itemID == c.itemID and (c.kind ~= "gear" or e.slot == nil or e.slot == c.slot)
    end
    return e.itemID == nil and e.kind == c.kind
end

-- The used entry a candidate stands for: the first not yet matched. Answers it and its index.
local function matchOf(used, c, matched)
    for i, e in ipairs(used) do
        if not matched[i] and type(e) == "table" and stands(c, e) then return e, i end
    end
    return nil
end

local function rowOf(src, e)
    return { itemID = src.itemID, kind = src.kind, slot = src.slot, entry = e }
end

-- Every row the record holds: one per candidate (in its stored order), each with the used entry it
-- stands for when there is one, then one per used entry no candidate stands for. Matched before any
-- is left out, so a hidden candidate never takes another row's entry.
local function allRows(u)
    local rows, matched = {}, {}
    for _, c in ipairs(type(u.candidates) == "table" and u.candidates or {}) do
        if type(c) == "table" then
            local e, i = matchOf(u.used, c, matched)
            if i then matched[i] = true end
            rows[#rows + 1] = rowOf(c, e)
        end
    end
    for i, e in ipairs(u.used) do
        if not matched[i] and type(e) == "table" then rows[#rows + 1] = rowOf(e, e) end
    end
    return rows
end

--- The edit's rows: every candidate and every used entry no candidate stands for (food), each with
--- the used entry it stands for, hidden items and enchant entries left out. nil when not recorded.
--- @return table|nil rows  { { itemID?, kind, slot?, entry? }, ... }
function ResultsUsage.Rows(record)
    local u = ResultsUsage.Record(record)
    if not u then return nil end
    local hidden, out = NS.Usage.HiddenSet(), {}
    for _, row in ipairs(allRows(u)) do
        if NS.Usage.Shown(row, hidden) then out[#out + 1] = row end
    end
    return out
end

--- The section's rows outside the edit: one per used entry, in Entries' order. nil when not recorded.
function ResultsUsage.UsedRows(record)
    local entries = ResultsUsage.Entries(record)
    if not entries then return nil end
    local out = {}
    for i, e in ipairs(entries) do out[i] = rowOf(e, e) end
    return out
end

--- The ticks Usage.SetUsed takes for `state` ({ [row index] = true } for a ticked row), in row order.
function ResultsUsage.Ticks(rows, state)
    local out = {}
    for i, row in ipairs(rows or {}) do
        if state[i] then out[#out + 1] = { itemID = row.itemID, kind = row.kind, slot = row.slot } end
    end
    return out
end

--- What a save writes: the ticks, then one for each used entry the edit does not list (a hidden item
--- the fight used), so hiding an item never drops it from the record.
function ResultsUsage.Edits(record, rows, state)
    local out, u = ResultsUsage.Ticks(rows, state), ResultsUsage.Record(record)
    local hidden = NS.Usage.HiddenSet()
    for _, e in ipairs(u and u.used or {}) do
        if type(e) == "table" and e.kind ~= "enchant" and not NS.Usage.Shown(e, hidden) then
            out[#out + 1] = { itemID = e.itemID, kind = e.kind, slot = e.slot }
        end
    end
    return out
end

--- Whether `state` differs from what the rows hold (a row ticked that was not used, or the reverse).
function ResultsUsage.Changed(rows, state)
    for i, row in ipairs(rows or {}) do
        if (row.entry ~= nil) ~= (state[i] == true) then return true end
    end
    return false
end

-- A row's identity across two drawings of the same fight: its item and slot, or its kind.
local function rowKey(row)
    return tostring(row.itemID or row.kind) .. ":" .. tostring(row.slot)
end

--- The ticks for `rows`: what each holds, or, given the rows and ticks of a drawing before
--- (`oldRows`, `oldState`), each row's tick there by its identity (a row new since, what it holds).
function ResultsUsage.Carry(rows, oldRows, oldState)
    local was = {}
    for i, row in ipairs(oldRows or {}) do was[rowKey(row)] = oldState[i] == true end
    local state = {}
    for i, row in ipairs(rows or {}) do
        local on = was[rowKey(row)]
        if on == nil then on = row.entry ~= nil end
        state[i] = on or nil
    end
    return state
end

-- ── the client's item data ──────────────────────────────────────────────────────────────────────

local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return a end
    return nil
end

local function itemApi(name)
    return type(C_Item) == "table" and C_Item[name] or nil
end

--- An entry's (or a row's) name: its item's, or "Well Fed" for food with no item.
function ResultsUsage.Name(e)
    if type(e) ~= "table" then return "?" end
    if e.itemID then
        return NS.Secrets.PlainString(ask(itemApi("GetItemNameByID"), e.itemID)) or L["Item %d"]:format(e.itemID)
    end
    if e.kind == "food" then return L["Well Fed"] end
    return "?"
end

--- An entry's (or a row's) icon.
function ResultsUsage.Icon(e)
    if type(e) ~= "table" then return ResultsUsage.UNKNOWN_ICON end
    if e.itemID then return ask(itemApi("GetItemIconByID"), e.itemID) or ResultsUsage.UNKNOWN_ICON end
    if e.kind == "food" then return ResultsUsage.FOOD_ICON end
    return ResultsUsage.UNKNOWN_ICON
end

-- ── the section ─────────────────────────────────────────────────────────────────────────────────

-- A row's hover: the client's own item tooltip with the row's detail after it (and, in the edit, how
-- to hide an item), or the name alone.
local function rowTip(p, row)
    local tt, data = GameTooltip, row.data
    if not (tt and data) then return end
    tt:SetOwner(row, "ANCHOR_RIGHT")
    local shown = data.itemID and tt.SetItemByID and pcall(tt.SetItemByID, tt, data.itemID)
    if not shown then tt:SetText(ResultsUsage.Name(data), Style.Rgb("gtip.value")) end
    if row.detailText and row.detailText ~= "" then tt:AddLine(row.detailText, Style.Rgb("gtip.muted")) end
    if p.usage.editing and data.itemID then
        tt:AddLine(L["Right-click: never show this item."], Style.Rgb("gtip.muted"))
    end
    tt:Show()
end

--- An item row's right-click while editing: a menu with *Never show <item>* (Usage.Hide; the window
--- redraws from SETTINGS_CHANGED, the ticks not saved yet kept).
--- @return boolean opened
function ResultsUsage.RowMenu(p, row)
    local data = row and row.data
    if not (p.usage.editing and data and data.itemID and NS.CanOpenMenu()) then return false end
    local itemID, name = data.itemID, ResultsUsage.Name(data)
    NS.OpenMenu(row, function(root)
        root:CreateButton(L["Never show %s"]:format(name), function() NS.Usage.Hide(itemID) end)
    end)
    return true
end

-- Save's look: live only while the ticks differ from the stored list; Edit live with a record.
local function paintButtons(x)
    Style.SetEnabled(x.save, x.editing and x.rows ~= nil and ResultsUsage.Changed(x.rows, x.state))
    x.edit.label:SetText(x.editing and L["Cancel"] or L["Edit"])
    Style.SetEnabled(x.edit, x.recorded == true)
end

local function toggle(x, i)
    x.state[i] = not x.state[i] or nil
    x.items[i].check:SetChecked(x.state[i] == true)
    paintButtons(x)
end

local function newRow(p, x, i)
    local row = CreateFrame("Frame", nil, p.content)
    row:SetHeight(ResultsUsage.ROW_H)
    row:EnableMouse(true)
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(ResultsUsage.CHECK, ResultsUsage.CHECK)
    row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ResultsUsage.ICON, ResultsUsage.ICON)
    Style.EdgeIcon(row.icon)
    row.check.label = Style.Text(row, FONT.TEXT, Tbl().COLORS.text)
    row.check.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.check:SetScript("OnClick", function() toggle(x, i) end)
    NS.Skin.Checkbox(row.check)   -- the skin's check box, after its click script
    for _, f in ipairs({ row, row.check }) do
        f:HookScript("OnEnter", function() rowTip(p, row) end)
        f:HookScript("OnLeave", function() Tbl().HideTip() end)
        f:HookScript("OnMouseUp", function(_, button)
            if button == "RightButton" then ResultsUsage.RowMenu(p, row) end
        end)
    end
    return row
end

--- Build the Usage section's parts into the pane `p` (its content `c`), as `p.usage`.
function ResultsUsage.Build(p, c)
    local x = { items = {}, state = {}, editing = false }
    p.usage = x
    x.title = Style.Text(c, FONT.SECTION)
    x.title:SetText(L["Usage"])
    x.save = Style.Button(c, L["Save"], function() ResultsUsage.Save(p) end, "primary")
    x.save:SetSize(ResultsUsage.SAVE_W, ResultsUsage.BUTTON_H)
    x.save.tip = { L["Save"], L["Keep these ticks as what the fight used."] }
    x.edit = Style.Button(c, L["Edit"], function() ResultsUsage.ToggleEdit(p) end)
    x.edit:SetSize(ResultsUsage.EDIT_W, ResultsUsage.BUTTON_H)
    x.edit.tip = { L["Edit"], L["Tick what the fight really used: an item the detection missed, or one it got wrong."] }
    x.none = Style.Text(c, FONT.TEXT, Tbl().COLORS.dim)
    return x
end

-- One row: in the edit its box, ticked or not, then the icon; outside it the icon at the left edge.
-- The name and its detail are one line (ResultsUsage.Line); in the edit the box's click area reaches
-- over it.
local function fillRow(row, data, editing, ticked)
    row.data, row.editing = data, editing
    row.detailText = data.entry and ResultsUsage.Detail(data.entry) or ""
    local line, plain = ResultsUsage.Line(ResultsUsage.Name(data), row.detailText)
    row.lineW = Tbl().BadgeWidth(plain, false)
    row.check:SetShown(editing)
    row.icon:ClearAllPoints()
    if editing then
        row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
        row.check.label:SetText(line)
        row.check:SetChecked(ticked)
        row.left = ResultsUsage.CHECK + 2 + ResultsUsage.ICON + 4
    else
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.check.label:SetText(line)
        row.left = ResultsUsage.ICON + 4
    end
    row.icon:SetTexture(ResultsUsage.Icon(data))
end

local function noneText(x)
    if not x.recorded then return L["Not recorded"] end
    if x.editing then return L["Nothing to list: no on-use item or consumable was found at the start."] end
    return L["Nothing used"]
end

-- Paint the section from `p.record` in the mode `x.editing` says; `carry` keeps the edit's ticks not
-- saved yet (a redraw of the same fight mid-edit), each by its row.
local function draw(p, carry)
    local x = p.usage
    local rows
    if x.editing then rows = ResultsUsage.Rows(p.record) else rows = ResultsUsage.UsedRows(p.record) end
    local state = {}
    if x.editing then state = ResultsUsage.Carry(rows, carry and x.rows or nil, x.state) end
    x.rows, x.state = rows, state
    for i, data in ipairs(rows or {}) do
        x.items[i] = x.items[i] or newRow(p, x, i)
        fillRow(x.items[i], data, x.editing, state[i] == true)
    end
    for i = #(rows or {}) + 1, #x.items do x.items[i]:Hide() end
    x.none:SetText(noneText(x))
    paintButtons(x)
end

--- Read `p.record`'s usage and paint the section, out of the edit. `keep` (the same fight drawn
--- again: another fight saved, a note saved, an item hidden) stays in an edit, with its ticks not
--- saved yet; the redraw a save causes leaves it.
function ResultsUsage.Fill(p, keep)
    local x = p.usage
    x.recorded = ResultsUsage.Record(p.record) ~= nil
    local carry = keep and x.editing and not x.saving and x.recorded
    x.editing, x.saving = carry and true or false, nil
    draw(p, carry)
end

local function relayout(p)
    if p.Layout and p.width then p:Layout(p.width, p.height, p.narrow) end
end

--- *Edit*: into the edit (every candidate, what was used ticked), or out of it unsaved.
--- @return boolean toggled
function ResultsUsage.ToggleEdit(p)
    local x = p.usage
    if not (p.record and x.recorded) then return false end
    x.editing = not x.editing
    draw(p, false)
    relayout(p)
    return true
end

--- Write the ticks (Usage.SetUsed) and leave the edit; the window redraws from the bus (a stored
--- fight) or the source (a sample fight).
--- @return boolean stored
function ResultsUsage.Save(p)
    local x = p.usage
    if not (p.record and x.editing and x.rows and ResultsUsage.Changed(x.rows, x.state)) then return false end
    -- The redraw this save causes starts from the new list, out of the edit.
    x.saving = true
    local stored = NS.Usage.SetUsed(p.record, ResultsUsage.Edits(p.record, x.rows, x.state))
    if x.saving then
        -- No redraw came (the window is hidden): leave the edit here.
        x.saving = nil
        if stored then
            x.editing = false
            draw(p, false)
            relayout(p)
        end
    end
    return stored
end

local function place(region, parent, px, py)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", px, py)
end

-- One row across `cw`: its line from after the icon to the row's right edge; in the edit the box's
-- click area over the line's estimate, never past that edge.
local function layoutRow(p, row, y, cw)
    local lineW = math.max(20, cw - (row.left or 0))
    place(row, p.content, 0, y)
    row:SetWidth(cw)
    row.check.label:SetWidth(lineW)
    if row.editing then
        row.check:SetHitRectInsets(0, -(2 + ResultsUsage.ICON + 4 + math.min(row.lineW or 0, lineW)), 0, 0)
    end
    row:Show()
end

--- The section at `y` across `cw`, *Edit* at the heading's right and *Save* (in the edit) left of
--- it; answers the y beneath.
function ResultsUsage.Layout(p, y, cw)
    local x = p.usage
    y = y - Style.SECTION_GAP
    place(x.title, p.content, 0, y)
    place(x.edit, p.content, cw - ResultsUsage.EDIT_W, y)
    x.save:SetShown(x.editing)
    place(x.save, p.content, cw - ResultsUsage.EDIT_W - ResultsUsage.BUTTON_GAP - ResultsUsage.SAVE_W, y)
    y = y - Style.SECTION_H
    local n = x.rows and #x.rows or 0
    x.none:SetShown(n == 0)
    if n == 0 then
        place(x.none, p.content, 0, y)
        x.none:SetWidth(cw)
        return y - ResultsUsage.LINE_H - 8
    end
    for i = 1, n do layoutRow(p, x.items[i], y - (i - 1) * ResultsUsage.ROW_H, cw) end
    return y - n * ResultsUsage.ROW_H - 8
end
