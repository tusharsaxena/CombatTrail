local _, NS = ...
-- modules/LogTable_View.lua — the Combat Log table's frames (CombatTrail #11, plan item CL-11b): one
-- component every home builds (the DPS HUD's docked drawer, modules/Hud_Log.lua; the detached
-- companion, modules/LogWindow.lua; the Results fight detail's Log tab, modules/Results_Log.lua),
-- drawing the cells modules/LogTable.lua works out.
--
-- THE SHAPE. A column header (its own row, LogTable.HEAD_H, in the list header's gold; `opts.noHeader`
-- leaves it out), then `rows` pooled rows LogTable.ROW_H apart. Each row is a stripe, a wash, one label
-- per column and the spell's icon. The columns are laid by LogTable.Columns from the width the home
-- gives: fixed widths, Spell/School taking the rest, the optional columns dropped while it would be
-- narrower than SPELL_MIN. Laid only when the width or the columns change, never on a paint.
--
-- THE TIME HEADER is a button: a click is the home's `opts.onSort` (it writes `log.view.sort`), and
-- the header carries the sort's arrow (sort-down newest first, sort-up oldest first). THE WHEEL is the
-- home's `opts.onScroll(away)`: lines away from the newest, by the sort's direction.
--
-- A PAINT (View:Draw) is handed the rows' lines, newest first, and the view puts them in the sort's
-- order: newest first top down, or oldest first with the newest at the bottom. A label is painted only
-- when its color moved (Style.Paint keeps the last role), so a repaint of the same rows calls nothing
-- but SetText. A hovered row with a spell shows the client's spell tooltip (Style.PlaceBody).
--
-- SECRETS. A sealed amount reaches a label's SetText through NS.Format.Number and nothing else. No
-- geometry is read back: every place is worked out from the row index and the configured sizes.

local LogTable = NS.LogTable
local L = NS.L
local Style = NS.Style

LogTable.ROW_H = 14
LogTable.HEAD_H = 14
LogTable.ICON = 12
LogTable.COL_GAP = 4
LogTable.SPELL_MIN = 70
-- Each fixed column's width; Spell/School takes the rest.
LogTable.WIDTH = { time = 38, event = 46, source = 46, target = 64, amount = 50, info = 86 }
LogTable.ORDER = { "time", "event", "source", "target", "spell", "amount", "info" }
-- The optional columns a narrow home drops first.
LogTable.DROP = { "source", "target", "info" }
LogTable.HEADS = { time = L["Time"], event = L["Event"], source = L["Source"], target = L["Target"],
                   spell = L["Spell/School"], amount = L["Amount"], info = L["Info"] }
local JUSTIFY = { amount = "RIGHT" }

--- The columns for `width`: which show and where, as { { key, x, w }, ... } in ORDER. `want` is
--- `log.view.columns` (source, target, spell, amount on unless false); `info` whether the home has an
--- Info column at all. Time and Event always show.
--- @return table
function LogTable.Columns(width, want, info)
    want = want or {}
    local on = { time = true, event = true, info = info == true and want.info ~= false }
    for _, key in ipairs({ "source", "target", "spell", "amount" }) do on[key] = want[key] ~= false end
    local function fixed()
        local sum, n = 0, 0
        for _, key in ipairs(LogTable.ORDER) do
            if on[key] then
                n = n + 1
                if key ~= "spell" then sum = sum + LogTable.WIDTH[key] end
            end
        end
        return sum + math.max(0, n - 1) * LogTable.COL_GAP
    end
    for _, key in ipairs(LogTable.DROP) do
        if on.spell and width - fixed() < LogTable.SPELL_MIN then on[key] = false end
    end
    local out, x, spellW = {}, 0, math.max(LogTable.SPELL_MIN, width - fixed())
    for _, key in ipairs(LogTable.ORDER) do
        if on[key] then
            local w = key == "spell" and spellW or LogTable.WIDTH[key]
            out[#out + 1] = { key = key, x = x, w = w }
            x = x + w + LogTable.COL_GAP
        end
    end
    return out
end

local View = {}
View.__index = View

--- The table's height with `rows` rows (its header too, unless `noHeader`).
function LogTable.Height(rows, noHeader)
    return (noHeader and 0 or LogTable.HEAD_H) + rows * LogTable.ROW_H
end

local function hideTip() if GameTooltip then GameTooltip:Hide() end end

local function rowEnter(row)
    if row.spellID == nil or not GameTooltip then return end
    Style.OwnTip(GameTooltip, row)
    if not pcall(GameTooltip.SetSpellByID, GameTooltip, row.spellID) then return GameTooltip:Hide() end
    GameTooltip:Show()
    Style.PlaceBody(GameTooltip, row)
end

-- A left click on a row: the home's `opts.onClick(line)` with the line it shows (the Results Log tab's
-- jump to the Timeline). A live home passes none and its clicks do nothing.
local function rowUp(row, button)
    local view = row.view
    if button == "RightButton" or row.line == nil or not view.opts.onClick then return end
    view.opts.onClick(row.line)
end

local function newRow(self)
    local r = CreateFrame("Frame", nil, self.frame)
    r.view = self
    r.stripe = r:CreateTexture(nil, "BACKGROUND")
    r.stripe:SetTexture(Style.WHITE)
    r.stripe:SetAllPoints(r)
    r.wash = r:CreateTexture(nil, "BORDER")
    r.wash:SetTexture(Style.WHITE)
    r.wash:SetAllPoints(r)
    r.wash:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(LogTable.ICON, LogTable.ICON)
    Style.CropIcon(r.icon)
    r.text = {}
    for _, key in ipairs(LogTable.ORDER) do r.text[key] = Style.Text(r, Style.FONT.TEXT, "ct.text", JUSTIFY[key]) end
    r:EnableMouse(true)
    r:SetScript("OnEnter", rowEnter)
    r:SetScript("OnLeave", hideTip)
    r:SetScript("OnMouseUp", rowUp)
    return r
end

--- A table on `parent`. `opts`: info (the home has an Info column), noHeader, onSort(), onScroll(away),
--- onClick(line) (a left click on a row, with the line it shows).
--- @return table view
function LogTable.New(parent, opts)
    local self = setmetatable({ opts = opts or {}, rows = {}, seqs = {}, cells = {}, cols = {} }, View)
    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    if f.EnableMouseWheel then f:EnableMouseWheel(true) end
    f:SetScript("OnMouseWheel", function(_, delta) self:Wheel(delta) end)
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    head:SetHeight(LogTable.HEAD_H)
    self.head, self.heads = head, {}
    for _, key in ipairs(LogTable.ORDER) do
        self.heads[key] = Style.Text(head, Style.FONT.HEADER, "list.header.text", JUSTIFY[key])
        self.heads[key]:SetText(LogTable.HEADS[key])
    end
    local sorter = CreateFrame("Button", nil, head)
    sorter:SetScript("OnClick", function() if self.opts.onSort then self.opts.onSort() end end)
    self.sorter = sorter
    self.empty = Style.Text(f, Style.FONT.CAPTION, nil, "LEFT")
    head:SetShown(not self.opts.noHeader)
    return self
end

--- The sort the Time header's arrow shows ("newest" | "oldest").
function View:SetSort(sort)
    if self.sort == sort then return end
    self.sort = sort
    local up = sort == "oldest"
    local arrow = up and Style.IconMarkup("sort-up", "Interface\\Buttons\\Arrow-Up-Up", Style.GOLD)
        or Style.IconMarkup("sort-down", "Interface\\Buttons\\Arrow-Down-Up", Style.GOLD)
    self.heads.time:SetText(LogTable.HEADS.time .. " " .. arrow)
end

local function place(fs, row, col)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
    fs:SetWidth(col.w)
end

-- One row's columns laid (and the icon at Spell/School's start, its name after it).
local function layRow(r, cols)
    for _, fs in pairs(r.text) do fs:Hide() end
    for _, col in ipairs(cols) do
        local fs = r.text[col.key]
        fs:Show()
        if col.key == "spell" then
            r.icon:ClearAllPoints()
            r.icon:SetPoint("LEFT", r, "LEFT", col.x, 0)
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", r, "LEFT", col.x + LogTable.ICON + 2, 0)
            fs:SetWidth(math.max(1, col.w - LogTable.ICON - 2))
        else
            place(fs, r, col)
        end
    end
    r.hasSpell = false
    for _, col in ipairs(cols) do if col.key == "spell" then r.hasSpell = true end end
end

-- What a layout depends on, as one string: the width, the rows and each column switch.
local function layoutKey(width, rows, want)
    want = want or {}
    local parts = { width, rows }
    for _, key in ipairs({ "source", "target", "spell", "amount", "info" }) do parts[#parts + 1] = tostring(want[key]) end
    return table.concat(parts, ":")
end

-- The column header laid: each shown column's label, and the Time header's button over its label.
function View:layHead()
    for _, fs in pairs(self.heads) do fs:Hide() end
    for _, col in ipairs(self.cols) do
        local fs = self.heads[col.key]
        fs:Show()
        place(fs, self.head, col)
        if col.key == "time" then
            self.sorter:ClearAllPoints()
            self.sorter:SetPoint("LEFT", self.head, "LEFT", col.x, 0)
            self.sorter:SetSize(col.w, LogTable.HEAD_H)
        end
    end
end

-- The rows laid: `rows` of them (built as needed) under the header, the rest hidden.
function View:layRows(rows)
    local top = self.opts.noHeader and 0 or LogTable.HEAD_H
    for i = 1, math.max(rows, #self.rows) do
        local r = self.rows[i]
        if i <= rows then
            if not r then r = newRow(self); self.rows[i] = r end
            local y = -(top + (i - 1) * LogTable.ROW_H)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, y)
            r:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, y)
            r:SetHeight(LogTable.ROW_H)
            layRow(r, self.cols)
        elseif r then
            r:Hide()
        end
    end
    self.empty:ClearAllPoints()
    self.empty:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 2, -(top + 1))
end

--- Lay the table at `width` with `rows` rows and the columns `want` asks for (`log.view.columns`).
function View:Layout(width, rows, want)
    local key = layoutKey(width, rows, want)
    if self.laid == key then return end
    self.laid, self.nRows = key, rows
    self.cols = LogTable.Columns(width, want, self.opts.info)
    self:layHead()
    self:layRows(rows)
    self.frame:SetHeight(LogTable.Height(rows, self.opts.noHeader))
end

-- The amount's face: the larger one for a critical, set again only when it moves.
local function setBig(r, big)
    if r.big == big then return end
    r.big = big
    local fs = r.text.amount
    local font = big and Style.FONT.HEADING or Style.FONT.TEXT
    fs:SetFontObject(font)
    Style.Paint(fs, r.amountColor or "ct.text", font, true)
end

local function fill(r, c, index, line)
    local t = r.text
    t.time:SetText(c.time)
    Style.Paint(t.time, "ct.dim")
    t.event:SetText(c.tag)
    Style.Paint(t.event, c.tagColor)
    t.source:SetText(c.source)
    Style.Paint(t.source, c.sourceColor)
    t.target:SetText(c.target)
    Style.Paint(t.target, c.targetColor)
    t.spell:SetText(c.spell)
    Style.Paint(t.spell, c.spellColor)
    r.amountColor = c.amountColor or "ct.text"
    setBig(r, c.big == true)
    t.amount:SetText(c.amount)
    Style.Paint(t.amount, r.amountColor)
    t.info:SetText(c.info)
    Style.Paint(t.info, "ct.dim")
    r.icon:SetTexture(c.icon)
    r.icon:SetShown(r.hasSpell and c.icon ~= nil)
    r.spellID = c.spellID
    r.line = line
    Style.Stripe(r.stripe, index)
    if c.wash then
        Style.Vertex(r.wash, c.wash)
        r.wash:Show()
    else
        r.wash:Hide()
    end
    r:Show()
end

--- Paint `n` lines: `seqs[1..n]` newest first, each read by `lineOf(seq)`, through LogTable.Cells with
--- `ctx`; in the sort's order. With none, `emptyText` (muted) in the rows' place.
function View:Draw(seqs, n, lineOf, ctx, emptyText)
    local oldest = self.sort == "oldest"
    for i = 1, self.nRows or 0 do
        local r = self.rows[i]
        local e = i <= n and lineOf(seqs[oldest and (n - i + 1) or i]) or nil
        if e then
            fill(r, LogTable.Cells(e, ctx, self.cells), i, e)
        else
            r.spellID, r.line = nil, nil
            r:Hide()
        end
    end
    local none = n == 0 and emptyText ~= nil
    self.empty:SetText(none and emptyText or "")
    self.empty:SetShown(none)
end

--- A live home's page: up to the laid rows' lines of `feed` (LogTable.Collect, none older than `from`,
--- each `accept`ed), backed up to a full page when scrolled past the oldest (still paused), drawn in
--- `sort`'s order with `ctx`. With no window (`from` nil) the empty text alone. Answers how many.
--- @return number
function View:DrawFeed(feed, from, accept, ctx, sort, emptyText)
    local rows, n = self.nRows or 0, 0
    if from then
        n = LogTable.Collect(feed, rows, from, accept, self.seqs)
        if n < rows and feed.offset > 0 then
            feed.offset = math.max(0, feed.offset - (rows - n))
            n = LogTable.Collect(feed, rows, from, accept, self.seqs)
        end
    end
    self:SetSort(sort)
    self:Draw(self.seqs, n, NS.CombatLog.Line, ctx, emptyText)
    return n
end

--- The wheel: lines away from the newest, by the sort's direction (newest first: down is away).
function View:Wheel(delta)
    if type(delta) ~= "number" or delta == 0 or not self.opts.onScroll then return end
    local away = self.sort == "oldest" and delta or -delta
    self.opts.onScroll(away > 0 and 1 or -1)
end

--- The rows on screen (the suites).
function View:Rows() return self.rows end
