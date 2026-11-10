local _, NS = ...
-- modules/Results_Usage.lua — what a fight used (spec §7, mockup §5), as the fight detail shows it:
-- one row per used entry, the item's icon and its name with a dim detail after it ("x2 at 0:09,
-- 1:12", "active at the start", "time unknown"), or a dim *Nothing used*. Adapted from DPS Race
-- @045f479 (modules/Results_Usage.lua), the detail part: the *Edit* flow (every candidate with a
-- checkbox, Save through Usage.SetUsed) and the History page's "never show" list are plan Tasks 4.4
-- and 4.5, so *Edit* stays grayed until NS.Usage.SetUsed exists, and nothing is hidden yet.
--
-- PLAIN DATA ONLY: the stored record.usage (modules/Usage.lua: { v, used, candidates, edited }).
-- Item names and icons are the client's item data, read at call time and pcall'd. Rows are laid out
-- from the constants here, never from a size read back; Record, Entries, Clock, Detail and Line are
-- pure over the record.

local ResultsUsage = {}
NS.ResultsUsage = ResultsUsage

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT

ResultsUsage.ROW_H = 20
ResultsUsage.ICON = 16
ResultsUsage.EDIT_W = 56
ResultsUsage.BUTTON_H = 18
ResultsUsage.LINE_H = 14
-- The icons of an entry with no item: food's (Spell_Misc_Food) and the question mark, as file ids.
ResultsUsage.FOOD_ICON = 134062
ResultsUsage.UNKNOWN_ICON = 134400

-- ── pure ────────────────────────────────────────────────────────────────────────────────────────

--- A fight's usage record, or nil for a fight with none (Not recorded).
function ResultsUsage.Record(record)
    local u = type(record) == "table" and record.usage
    if type(u) ~= "table" or type(u.used) ~= "table" then return nil end
    return u
end

--- The used entries in drawing order: the gear first, then everything else, each in its stored
--- order. nil when not recorded.
--- @return table|nil entries
function ResultsUsage.Entries(record)
    local u = ResultsUsage.Record(record)
    if not u then return nil end
    local gear, rest = {}, {}
    for _, e in ipairs(u.used) do
        if type(e) == "table" and e.kind ~= "enchant" then
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
--- (a buff on at the pull), or "time unknown" (a bag drop).
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
--- detail).
--- @return string
function ResultsUsage.Line(name, detail)
    name = tostring(name or "")
    if type(detail) ~= "string" or detail == "" then return name end
    local C = NS.ResultsTable.COLORS
    return ("%s|c%s \194\183 %s|r"):format(name, NS.ResultsTable.Hex(C.dim), detail)
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

--- An entry's name: its item's, or "Well Fed" for food with no item.
function ResultsUsage.Name(e)
    if type(e) ~= "table" then return "?" end
    if e.itemID then
        return NS.Secrets.PlainString(ask(itemApi("GetItemNameByID"), e.itemID)) or L["Item %d"]:format(e.itemID)
    end
    if e.kind == "food" then return L["Well Fed"] end
    return "?"
end

--- An entry's icon.
function ResultsUsage.Icon(e)
    if type(e) ~= "table" then return ResultsUsage.UNKNOWN_ICON end
    if e.itemID then return ask(itemApi("GetItemIconByID"), e.itemID) or ResultsUsage.UNKNOWN_ICON end
    if e.kind == "food" then return ResultsUsage.FOOD_ICON end
    return ResultsUsage.UNKNOWN_ICON
end

-- Whether the edit flow exists yet (plan Task 4.4).
local function canEdit()
    return type(NS.Usage.SetUsed) == "function" and type(ResultsUsage.ToggleEdit) == "function"
end

-- ── the section ─────────────────────────────────────────────────────────────────────────────────

local function rowTip(row)
    local tt, e = GameTooltip, row.entry
    if not (tt and e) then return end
    tt:SetOwner(row, "ANCHOR_RIGHT")
    local shown = e.itemID and pcall(tt.SetItemByID, tt, e.itemID)
    if not shown then tt:SetText(ResultsUsage.Name(e), Style.Rgb("gtip.value")) end
    tt:AddLine(ResultsUsage.Detail(e), Style.Rgb("gtip.muted"))
    tt:Show()
end

local function newRow(p)
    local row = CreateFrame("Frame", nil, p.content)
    row:SetHeight(ResultsUsage.ROW_H)
    row:EnableMouse(true)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ResultsUsage.ICON, ResultsUsage.ICON)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    Style.EdgeIcon(row.icon)
    row.label = Style.Text(row, FONT.TEXT, NS.ResultsTable.COLORS.text)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row:SetScript("OnEnter", rowTip)
    row:SetScript("OnLeave", NS.ResultsTable.HideTip)
    return row
end

--- Build the Usage section's parts into the pane `p` (its content `c`), as `p.usage`.
function ResultsUsage.Build(p, c)
    local x = { rows = {} }
    p.usage = x
    x.title = Style.Text(c, FONT.SECTION)
    x.title:SetText(L["Usage"])
    x.edit = Style.Button(c, L["Edit"], function()
        if canEdit() then ResultsUsage.ToggleEdit(p) end
    end)
    x.edit:SetSize(ResultsUsage.EDIT_W, ResultsUsage.BUTTON_H)
    x.edit.tip = { L["Edit"], L["Tick what the fight really used: an item the detection missed, or one it got wrong."] }
    x.none = Style.Text(c, FONT.TEXT, NS.ResultsTable.COLORS.dim)
    return x
end

--- Paint the section from `p.record`.
function ResultsUsage.Fill(p)
    local x = p.usage
    x.entries = ResultsUsage.Entries(p.record)
    for i, e in ipairs(x.entries or {}) do
        local row = x.rows[i] or newRow(p)
        x.rows[i] = row
        row.entry = e
        row.icon:SetTexture(ResultsUsage.Icon(e))
        row.label:SetText(ResultsUsage.Line(ResultsUsage.Name(e), ResultsUsage.Detail(e)))
    end
    for i = #(x.entries or {}) + 1, #x.rows do x.rows[i]:Hide() end
    x.none:SetText(x.entries == nil and L["Not recorded"] or L["Nothing used"])
    Style.SetEnabled(x.edit, canEdit() and x.entries ~= nil)
end

local function place(region, parent, px, py)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", px, py)
end

--- The section at `y` across `cw`, *Edit* at the heading's right; answers the y beneath.
function ResultsUsage.Layout(p, y, cw)
    local x = p.usage
    y = y - Style.SECTION_GAP
    place(x.title, p.content, 0, y)
    place(x.edit, p.content, cw - ResultsUsage.EDIT_W, y)
    y = y - Style.SECTION_H
    local n = x.entries and #x.entries or 0
    x.none:SetShown(n == 0)
    if n == 0 then
        place(x.none, p.content, 0, y)
        x.none:SetWidth(cw)
        return y - ResultsUsage.LINE_H - 8
    end
    for i = 1, n do
        local row = x.rows[i]
        place(row, p.content, 0, y - (i - 1) * ResultsUsage.ROW_H)
        row:SetWidth(cw)
        row:Show()
    end
    return y - n * ResultsUsage.ROW_H - 8
end
