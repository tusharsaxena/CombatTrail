local _, NS = ...
-- modules/LogTable_View.lua — the Combat Log table's frames (CombatTrail #11, plan item CL-11b): one
-- component every home builds (the DPS HUD's docked drawer, modules/Hud_Log.lua; the detached
-- companion, modules/LogWindow.lua; the Results fight detail's Log tab, modules/Results_Log.lua),
-- drawing the cells modules/LogTable.lua works out.
--
-- THE SHAPE. A column header (its own row, LogTable.HEAD_H, in the list header's gold; `opts.noHeader`
-- leaves it out), then `rows` pooled rows LogTable.ROW_H apart. Each row is a stripe, a wash, one label
-- per column and the spell's icon. The columns are laid by LogTable.Columns from the width the home
-- gives: fixed widths, Spell/School taking the rest, Info dropped while it would be narrower than
-- SPELL_MIN. Laid only when the width or the columns change, never on a paint. EVERY COLUMN IS
-- CENTERED, its header and its cells (owner feedback item 8); Spell/School's icon stands at the
-- column's start and its name is centered in the rest.
--
-- THE TIME HEADER is a button: a click is the home's `opts.onSort` (it writes `log.view.sort`), and
-- the header carries the sort's arrow (sort-down newest first, sort-up oldest first). THE WHEEL is the
-- home's `opts.onScroll(away)`: lines away from the newest, by the sort's direction, one line a notch.
-- THE SCROLL INDICATOR (owner feedback item 6) is Spell breakdown's (modules/Hud_States.lua): a thin
-- track (`ct.scroll.track`) and thumb (`ct.scroll.thumb`) in the gutter right of the rows, shown while
-- lines lie past them, the thumb as long as the share in view and as far down as the page
-- (View:SetScroll; DrawFeed sets it for a live home, the Results Log tab from its own page).
--
-- A PAINT (View:Draw) is handed the rows' lines, newest first, and the view puts them in the sort's
-- order: newest first top down, or oldest first with the newest at the bottom. A label is painted only
-- when its color moved (Style.Paint keeps the last role), so a repaint of the same rows calls nothing
-- but SetText. A hovered row with a spell shows the client's spell tooltip (Style.PlaceBody).
--
-- THE SIZES (CL-11c2, the Combat Log page's Order and display tab). `log.view.rowHeight` is the rows'
-- height in pixels (ROW_H_MIN to ROW_H_MAX; ROW_H, 14, by default) and `log.view.fontSize` their text
-- size in points (FONT_MIN to FONT_MAX; FONT_BASE, 10, by default: GameFontHighlightSmall's own). A
-- size other than 10 draws the rows in a named copy of the body font at that size (Style.ScaledText),
-- the fixed columns widened by the same factor and the icon too, up to the row's height. A label keeps
-- the size it was made at (the skin records it at the first paint), so each size has its own pool of
-- rows, built as wanted and kept. The header keeps its size. Every home's
-- height is worked out from LogTable.RowH(), so the HUD and both companions follow a change.
--
-- SECRETS. A sealed amount reaches a label's SetText through NS.Format.Number and nothing else. No
-- geometry is read back: every place is worked out from the row index and the configured sizes.

local LogTable = NS.LogTable
local L = NS.L
local Style = NS.Style

LogTable.ROW_H = 14
LogTable.ROW_H_MIN, LogTable.ROW_H_MAX = 12, 28
LogTable.FONT_BASE = 10
LogTable.FONT_MIN, LogTable.FONT_MAX = 8, 16
LogTable.HEAD_H = 14
LogTable.ICON = 12
LogTable.COL_GAP = 4
LogTable.SPELL_MIN = 70
-- Each fixed column's width; Spell/School takes the rest.
LogTable.WIDTH = { time = 38, event = 46, amount = 50, info = 86 }
LogTable.ORDER = { "time", "event", "spell", "amount", "info" }
-- The optional columns a narrow home drops first.
LogTable.DROP = { "info" }
LogTable.HEADS = { time = L["Time"], event = L["Event"], spell = L["Spell/School"], amount = L["Amount"],
                   info = L["Info"] }
-- Every column's justification: centered, header and cells (item 8).
LogTable.JUSTIFY = "CENTER"
local JUSTIFY = LogTable.JUSTIFY

local function setting(path)
    return NS.GetSetting and NS.GetSetting(path)
end

local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

--- The rows' height in pixels: `log.view.rowHeight`, whole and in range.
--- @return number
function LogTable.RowH()
    local v = NS.Secrets.PlainNumber(setting("log.view.rowHeight")) or LogTable.ROW_H
    return clamp(math.floor(v + 0.5), LogTable.ROW_H_MIN, LogTable.ROW_H_MAX)
end

--- The rows' text size as a factor of FONT_BASE: `log.view.fontSize`, whole and in range, over 10.
--- @return number
function LogTable.FontScale()
    local v = NS.Secrets.PlainNumber(setting("log.view.fontSize")) or LogTable.FONT_BASE
    return clamp(math.floor(v + 0.5), LogTable.FONT_MIN, LogTable.FONT_MAX) / LogTable.FONT_BASE
end

--- The spell icon's size at `rowH` and `scale`: ICON scaled, never taller than the row.
function LogTable.IconSize(rowH, scale)
    return math.max(1, math.min((rowH or LogTable.ROW_H) - 2, math.floor(LogTable.ICON * (scale or 1) + 0.5)))
end

--- The columns for `width`: which show and where, as { { key, x, w }, ... } in ORDER. `want` is
--- `log.view.columns` (spell, amount on unless false); `info` whether the home has an
--- Info column at all; `scale` the text size's factor (default 1), which widens the fixed columns.
--- Time and Event always show.
--- @return table
function LogTable.Columns(width, want, info, scale)
    want = want or {}
    scale = scale or 1
    local function wide(key) return math.floor(LogTable.WIDTH[key] * scale + 0.5) end
    local on = { time = true, event = true, info = info == true and want.info ~= false }
    for _, key in ipairs({ "spell", "amount" }) do on[key] = want[key] ~= false end
    local function fixed()
        local sum, n = 0, 0
        for _, key in ipairs(LogTable.ORDER) do
            if on[key] then
                n = n + 1
                if key ~= "spell" then sum = sum + wide(key) end
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
            local w = key == "spell" and spellW or wide(key)
            out[#out + 1] = { key = key, x = x, w = w }
            x = x + w + LogTable.COL_GAP
        end
    end
    return out
end

local View = {}
View.__index = View

--- The table's height with `rows` rows (its header too, unless `noHeader`), at LogTable.RowH().
function LogTable.Height(rows, noHeader)
    return (noHeader and 0 or LogTable.HEAD_H) + rows * LogTable.RowH()
end

local TEXT_FONT, BIG_FONT = Style.FONT.TEXT, Style.FONT.HEADING
local BIG = (Style.FONT_SIZE[BIG_FONT] or 12) / (Style.FONT_SIZE[TEXT_FONT] or 10)

--- A row label at the text size `scale`: the body text at 1, else its copy at the size
--- (Style.ScaledText). Made at its size, because the skin keeps the size a label had at its first
--- paint (LibKa0s-Skin's font record), so a label is never resized after it: a new size is a new pool.
local function rowText(r, scale, justify)
    if scale == 1 then return Style.Text(r, TEXT_FONT, "ct.text", justify) end
    return Style.ScaledText(r, TEXT_FONT, scale, "ct.text", justify)
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
    r.scale = self.scale or 1
    for _, key in ipairs(LogTable.ORDER) do r.text[key] = rowText(r, r.scale, JUSTIFY) end
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
    local self = setmetatable({ opts = opts or {}, rows = {}, seqs = {}, cells = {}, cols = {}, scale = 1, pools = {},
                                rowH = LogTable.ROW_H }, View)
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
        self.heads[key] = Style.Text(head, Style.FONT.HEADER, "list.header.text", JUSTIFY)
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

-- One row's columns laid (and the icon, `icon` px, at Spell/School's start, its name after it).
local function layRow(r, cols, icon)
    for _, fs in pairs(r.text) do fs:Hide() end
    r.icon:SetSize(icon, icon)
    for _, col in ipairs(cols) do
        local fs = r.text[col.key]
        fs:Show()
        if col.key == "spell" then
            r.icon:ClearAllPoints()
            r.icon:SetPoint("LEFT", r, "LEFT", col.x, 0)
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", r, "LEFT", col.x + icon + 2, 0)
            fs:SetWidth(math.max(1, col.w - icon - 2))
        else
            place(fs, r, col)
        end
    end
    r.hasSpell = false
    for _, col in ipairs(cols) do if col.key == "spell" then r.hasSpell = true end end
end

-- What a layout depends on, as one string: the width, the rows, the row height, the text size and
-- each column switch.
local function layoutKey(width, rows, want, rowH, scale)
    want = want or {}
    local parts = { width, rows, rowH, scale }
    for _, key in ipairs({ "spell", "amount", "info" }) do parts[#parts + 1] = tostring(want[key]) end
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
            local y = -(top + (i - 1) * self.rowH)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, y)
            r:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, y)
            r:SetHeight(self.rowH)
            layRow(r, self.cols, LogTable.IconSize(self.rowH, self.scale))
        elseif r then
            r:Hide()
        end
    end
    self.empty:ClearAllPoints()
    self.empty:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 2, -(top + 1))
end

-- A new text size: the rows built at the old one hidden and kept as that size's pool, and this
-- size's pool (built as rows are wanted) taken up. A size changes only from the settings.
function View:refont(scale)
    if self.scale == scale then return end
    for _, r in ipairs(self.rows) do r:Hide() end
    self.pools[self.scale] = self.rows
    self.rows = self.pools[scale] or {}
    self.scale = scale
end

--- Lay the table at `width` with `rows` rows and the columns `want` asks for (`log.view.columns`), at
--- the configured row height and text size (LogTable.RowH, LogTable.FontScale).
function View:Layout(width, rows, want)
    local rowH, scale = LogTable.RowH(), LogTable.FontScale()
    local key = layoutKey(width, rows, want, rowH, scale)
    if self.laid == key then return end
    self.laid, self.nRows, self.rowH, self.width = key, rows, rowH, width
    self:refont(scale)
    self.cols = LogTable.Columns(width, want, self.opts.info, scale)
    self:layHead()
    self:layRows(rows)
    self.frame:SetHeight(LogTable.Height(rows, self.opts.noHeader))
end

-- The amount's face: the larger one for a critical, set again only when it moves.
local function setBig(r, big)
    if r.big == big then return end
    r.big = big
    local fs, font = r.text.amount, big and BIG_FONT or TEXT_FONT
    if r.scale == 1 then
        fs:SetFontObject(font)
    else
        fs:SetFontObject(Style.ScaledFont(TEXT_FONT, r.scale * (big and BIG or 1)) or TEXT_FONT)
        font = TEXT_FONT
    end
    Style.Paint(fs, r.amountColor or "ct.text", font, true)
end

local function fill(r, c, index, line)
    local t = r.text
    t.time:SetText(c.time)
    Style.Paint(t.time, "ct.dim")
    t.event:SetText(c.tag)
    Style.Paint(t.event, c.tagColor)
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
--- `sort`'s order with `ctx`, the scroll indicator set from the page. With no window (`from` nil) the
--- empty text alone. Answers how many.
--- @return number
function View:DrawFeed(feed, from, accept, ctx, sort, emptyText)
    local rows, n, total = self.nRows or 0, 0, 0
    if from then
        n = LogTable.Collect(feed, rows, from, accept, self.seqs)
        if n < rows and feed.offset > 0 then
            feed.offset = math.max(0, feed.offset - (rows - n))
            n = LogTable.Collect(feed, rows, from, accept, self.seqs)
        end
        total = LogTable.Count(feed, from, accept)
    end
    self:SetSort(sort)
    self:Draw(self.seqs, n, NS.CombatLog.Line, ctx, emptyText)
    -- The page's place from the top of the list: newest first, the offset itself; oldest first (the
    -- newest at the bottom), the rest of the way.
    local most = math.max(0, total - rows)
    self:SetScroll(total, rows, sort == "oldest" and (most - math.min(feed.offset, most)) or feed.offset)
    return n
end

-- The indicator's track and thumb, built on its first want.
local function scrollParts(self)
    if self.track then return end
    self.track = self.frame:CreateTexture(nil, "ARTWORK")
    Style.Fill(self.track, "ct.scroll.track")
    self.thumb = self.frame:CreateTexture(nil, "OVERLAY")
    Style.Fill(self.thumb, "ct.scroll.thumb")
    self.scroll = {}   -- what the indicator shows (the suites read it)
end

--- The scroll indicator for `total` lines, `visible` of them in view, the page `top` lines down from
--- the list's top: shown while lines lie past the rows, in the gutter right of them (Spell
--- breakdown's look: HudStates.THUMB_W wide, THUMB_GAP clear of the rows, never shorter than
--- THUMB_MIN). Plain counts and configured sizes only.
function View:SetScroll(total, visible, top)
    local S = NS.HudStates
    scrollParts(self)
    total, visible = tonumber(total) or 0, tonumber(visible) or 0
    local most, h = total - visible, (self.nRows or 0) * self.rowH
    local on, sc = most > 0 and h > 0 and self.width ~= nil, self.scroll
    if sc.on ~= on then
        self.track:SetShown(on)
        self.thumb:SetShown(on)
        sc.on = on
    end
    if not on then return end
    local thumbH = math.max(S.THUMB_MIN, math.floor(h * visible / total + 0.5))
    local dy = math.floor((h - thumbH) * math.max(0, math.min(most, top or 0)) / most + 0.5)
    local x, y = self.width + S.THUMB_GAP, -(self.opts.noHeader and 0 or LogTable.HEAD_H)
    -- A paint that moved nothing places nothing (the live homes paint at every tick that moved).
    if sc.thumbH == thumbH and sc.dy == dy and sc.h == h and sc.x == x then return end
    self.track:ClearAllPoints()
    self.track:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
    self.track:SetSize(S.THUMB_W, h)
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y - dy)
    self.thumb:SetSize(S.THUMB_W, thumbH)
    sc.thumbH, sc.dy, sc.h, sc.x = thumbH, dy, h, x
end

--- The wheel: lines away from the newest, by the sort's direction (newest first: down is away).
function View:Wheel(delta)
    if type(delta) ~= "number" or delta == 0 or not self.opts.onScroll then return end
    local away = self.sort == "oldest" and delta or -delta
    self.opts.onScroll(away > 0 and 1 or -1)
end

--- The rows on screen (the suites).
function View:Rows() return self.rows end

-- ── the live chips (CL-REV) ─────────────────────────────────────────────────────────────────────
-- A strip of LogTable.CHIPS on a live home (the detached window under its status line, the drawer
-- behind its filter mark): one button per chip, lit ("primary") while LogTable.ChipOn, laid left to
-- right and wrapped at the width it is given. The Results Log tab builds its own (with counts).

LogTable.CHIP_H, LogTable.CHIP_GAP = 18, 4

--- How many lines the chips take at width `w`, wrapped as LogTable.LayChips lays them.
--- @return number
function LogTable.ChipLines(w)
    local x, lines = 0, 1
    for _, chip in ipairs(LogTable.CHIPS) do
        local cw = LogTable.ChipWidth(L[chip.label])
        if x > 0 and x + cw > w then x, lines = 0, lines + 1 end
        x = x + cw + LogTable.CHIP_GAP
    end
    return lines
end

--- The chips' height at width `w`.
--- @return number
function LogTable.ChipsHeight(w)
    local n = LogTable.ChipLines(w)
    return n * LogTable.CHIP_H + (n - 1) * LogTable.CHIP_GAP
end

--- The live chips on `parent`; a click is `onToggle(key)`.
--- @return table strip  { buttons = { [key] = button } }
function LogTable.NewChips(parent, onToggle)
    local strip = { buttons = {} }
    for _, chip in ipairs(LogTable.CHIPS) do
        local text = L[chip.label]
        local b = Style.Button(parent, text, function() onToggle(chip.key) end)
        b:SetHeight(LogTable.CHIP_H)
        b:SetWidth(LogTable.ChipWidth(text))
        b.tip, b.tipBody = { text, L[LogTable.CHIP_TIPS[chip.key]], L["Click to show or hide them in this view."] }, true
        strip.buttons[chip.key] = b
    end
    return strip
end

--- Lay the chips from (x, y) on `anchor`'s top left, wrapping at width `w`, and show them.
function LogTable.LayChips(strip, anchor, x, y, w)
    local cx, rowY = 0, y
    for _, chip in ipairs(LogTable.CHIPS) do
        local b = strip.buttons[chip.key]
        local cw = LogTable.ChipWidth(L[chip.label])
        if cx > 0 and cx + cw > w then cx, rowY = 0, rowY - LogTable.CHIP_H - LogTable.CHIP_GAP end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", anchor, "TOPLEFT", x + cx, rowY)
        b:Show()
        cx = cx + cw + LogTable.CHIP_GAP
    end
end

--- Light each chip by `show` (a view's own).
function LogTable.PaintChips(strip, show)
    for _, chip in ipairs(LogTable.CHIPS) do
        Style.SetButtonStyle(strip.buttons[chip.key], LogTable.ChipOn(show, chip.key) and "primary" or "normal")
    end
end

--- Show or hide every chip.
function LogTable.ShowChips(strip, shown)
    for _, b in pairs(strip.buttons) do b:SetShown(shown) end
end
