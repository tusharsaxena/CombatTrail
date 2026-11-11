local _, NS = ...
-- modules/Hud_Chart.lua — the DPS HUD's damage chart and pace bar (spec §6, plan Task 3.2). The chart
-- is a row of vertical StatusBars, one per time bucket of the fight (modules/Slices.lua's columns),
-- a line for the best's average pace, a zero line and the long cooldowns' icons along its top. The
-- pace bar sets the fight's damage against the paced best's at this point (modules/Hud_Best.lua).
-- Adapted from DPS Race @045f479 (modules/Hud_Chart.lua) without its race: no race length or buzzer
-- (the chart spans the fight, or the best's duration while that is longer), no shared session, and a
-- pace bar that carries the pet. The one race part is the Results detail's (ruling X9): OverView with a
-- race's clock runs the columns from its first hit and marks its buzzer with a line (Strip:drawBuzzer).
--
-- A VISUAL INDICATOR, NO MATH ON A VALUE. A column's value is the player's live total copied at its
-- step: secret in combat, and it stays secret. It goes to StatusBar:SetValue and nowhere else. The
-- columns are the PLAYER's alone (Slices keeps the pet beside them, and the two cannot be summed in
-- combat), so every scale and the best's line are the player's too. The scale is one of three:
--   * live with a best: the best's plain player damage at the chart's end x HEADROOM, with the
--     best's average pace a line from 0:00 to that level;
--   * live with none: the live total itself (SetMinMaxValues takes a secret max), so the newest
--     column is always full; no line;
--   * the fight-over card: the plain final player damage, or with a best the larger of it and the
--     best's at the fight's length, x HEADROOM, with the best's line.
-- Every column draws in the chart's own bar look: a cooldown marks the chart with its icon only, and
-- never recolors a column (owner, 2026-11-10: DPS Race parity, "don't change the chart color").
--
-- THE PACE BAR (spec §6), DPS Race's (modules/Hud_Chart.lua, the owner's call there 2026-10-26,
-- and here 2026-11-11). Two StatusBars split at the on-pace tick in the middle of the bar, over one
-- track. The BEHIND half runs lo to the pace (HudBest.Bounds: the best's pace in the middle) in the
-- spell rows' bar look, with red from its fill's end to the tick (a texture anchored to the fill
-- texture), so behind pace shows red for the shortfall; the AHEAD half runs the pace to hi in green,
-- so ahead shows green past the tick. Both are handed the same total and clamp it (empty or full):
-- nothing compares it and no color is chosen from it; the color is where the fill ends, which the
-- client draws. The total is ONE figure against a reference of the same measure (HudBest.LiveView,
-- OverView): live, the player's source total (on WoW Forever the pet folds into it) against the
-- best's merged pace, or, where the pet has its own source, the player's alone against the best's
-- player damage (two secrets cannot be summed); after the fight, the plain merged total.
--
-- LAYOUT FROM CONFIG. Every size is the width Place() is handed and the configured plot height
-- (`hud.chart.height`); nothing reads a size or position back off a column. The heading is DPS
-- Race's (FONT.SECTION on Style.SECTION_H), and the HUD lays the pace bar on a line between it and
-- the plot (Place's `midH`; Hud_States' placeProfile), keeping the heading over the bar when the plot
-- is off (SetParts).

local Chart = {}
NS.HudChart = Chart

local L = NS.L
local Style = NS.Style

Chart.HEADROOM = 1.15   -- the best's level plus room to pass it
Chart.HEAD_H = Style.SECTION_H   -- the "Damage profile" heading's line (FONT.SECTION)
Chart.AXIS_H = 12       -- the time labels under the plot
Chart.GAP = 2
Chart.INSET = 2         -- the plot's inner padding
Chart.LINE_W = 2        -- the best line's thickness
Chart.ICON = 12         -- a cooldown icon's size
Chart.ICON_GAP = 1      -- between two rows of icons
Chart.RESERVE = Chart.ICON + Chart.ICON_GAP   -- the plot's headroom on top: one row of icons
Chart.PACE_H = 12       -- the pace bar's line: the bar 8px tall, 2px clear over and under it
-- A race's buzzer line (the Results detail and the Timeline, ruling X9): the Timing strip's race hue
-- (modules/Results_RaceDetail.lua RD.RACE), DPS Race's data hue, the same under every skin.
Chart.BUZZER = { 0.53, 0.53, 0.93 }

local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }

-- ── pure ────────────────────────────────────────────────────────────────────────────────────────

--- The configured plot height, in pixels.
function Chart.PlotHeight()
    return NS.HudAppearance.Number("hud.chart.height", 40, 200)
end

--- The configured most columns.
function Chart.MaxColumns()
    return math.floor(NS.HudAppearance.Number("hud.chart.columns", 8, NS.Slices.MAX))
end

--- Each column's left edge and width in whole pixels across `inner`, for `count` columns: edges on
--- x_i = floor(i * inner / count + 0.5), none narrower than 1. Plain config math.
--- @return table xs, table widths
function Chart.ColumnEdges(inner, count)
    local xs, widths = {}, {}
    if count < 1 then return xs, widths end
    local function edge(i) return math.floor(i * inner / count + 0.5) end
    for i = 1, count do
        local x0, x1 = edge(i - 1), edge(i)
        xs[i], widths[i] = x0, math.max(1, x1 - x0)
    end
    return xs, widths
end

--- The plot frame's height for a plot `plotH` tall: the columns and the icons' row on top.
function Chart.FrameHeight(plotH)
    return plotH + Chart.RESERVE
end

--- The chart block's whole height for a plot `plotH` tall: heading, `midH` (default 0: the line the
--- HUD lays the pace bar on), the plot frame, the gap and the time labels.
function Chart.BlockHeight(plotH, midH)
    return Chart.HEAD_H + (midH or 0) + Chart.FrameHeight(plotH) + Chart.GAP + Chart.AXIS_H
end

--- A cast's center x on a plot `width` wide spanning `span` seconds, held inside the plot; nil
--- without a plain time and span.
function Chart.IconX(t, span, width)
    if type(t) ~= "number" or type(span) ~= "number" or span <= 0 then return nil end
    local inner = (tonumber(width) or 0) - 2 * Chart.INSET
    local x = Chart.INSET + math.max(0, math.min(t, span)) / span * inner
    local half = Chart.ICON / 2
    return math.max(half, math.min(x, (tonumber(width) or 0) - half))
end

--- How many rows of icons a plot frame `frameH` tall holds (at least one).
function Chart.IconRowCount(frameH)
    local inner = (tonumber(frameH) or 0) - 2 * Chart.INSET
    return math.max(1, math.floor((inner + Chart.ICON_GAP) / (Chart.ICON + Chart.ICON_GAP)))
end

local function freeRow(last, x, n)
    for r = 1, n do
        if last[r] == nil or x - last[r] >= Chart.ICON then return r end
    end
    return nil
end

local function crowds(xs, spill)
    local out, cur = {}, nil
    for _, i in ipairs(spill) do
        if cur and xs[i] - xs[cur[1]] < Chart.ICON then
            cur[#cur + 1] = i
        else
            cur = { i }
            out[#out + 1] = cur
        end
    end
    return out
end

--- Each icon's row for centers `xs` (in time order) on `maxRows` rows: the first row where it would
--- not overlap the one placed last there. The last row takes the overflow: a lone cast as an icon, a
--- crowd as one mark standing for every cast in it. Nothing is dropped.
--- @return table rows  { [i] = row }, nil for a cast under a mark
--- @return table marks  { { x, row, members = { i, ... } }, ... }
function Chart.IconRows(xs, maxRows)
    maxRows = math.max(1, math.floor(tonumber(maxRows) or 2))
    local rows, last, spill = {}, {}, {}
    for i, x in ipairs(xs) do
        local r = freeRow(last, x, maxRows - 1)
        if r then rows[i], last[r] = r, x else spill[#spill + 1] = i end
    end
    local marks = {}
    for _, crowd in ipairs(crowds(xs, spill)) do
        if #crowd == 1 then
            rows[crowd[1]] = maxRows
        else
            marks[#marks + 1] = { x = xs[crowd[1]], row = maxRows, members = crowd }
        end
    end
    return rows, marks
end

--- A row's center y from the plot frame's top (negative).
function Chart.IconY(row)
    return -(Chart.INSET + Chart.ICON / 2 + (row - 1) * (Chart.ICON + Chart.ICON_GAP))
end

--- The long cooldowns among `casts` (Casts' list: { t, spellID, unit }), by their base cooldowns
--- `spells` ({ [id] = ms }) against `hud.chart.cooldownMin` seconds; nil when the icons are off.
--- @return table|nil { { t, spellID, unit }, ... } in time order
function Chart.Cooldowns(casts, spells)
    local A = NS.HudAppearance
    if not A.On("hud.chart.cooldowns") or type(casts) ~= "table" or type(spells) ~= "table" then return nil end
    local minMs = A.Number("hud.chart.cooldownMin", 1, 600) * 1000
    local out = {}
    for _, c in ipairs(casts) do
        local ms = spells[c.spellID]
        if type(ms) == "number" and ms >= minMs and type(c.t) == "number" then out[#out + 1] = c end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end

-- The view's columns from the fight's store, over `span` seconds from `shift` seconds in (default 0).
local function columnsOf(fightID, span, shift)
    local cols = NS.Slices.Columns(fightID, span, Chart.MaxColumns(), shift)
    if not cols then return nil end
    return { count = cols.count, step = cols.step, values = cols.values, span = cols.count * cols.step }
end

-- The best's line and the plain scale for a best player level `at`, over a plain own level `own`.
local function withBest(view, at, own)
    if type(at) ~= "number" or at <= 0 then
        view.max = own
        return view
    end
    view.max = math.max(own or 0, at) * Chart.HEADROOM
    view.best = at / view.max
    view.note = L["vs best pace"]
    return view
end

--- The live chart's view: the fight's columns over the longer of its clock and the best's duration,
--- scaled to the best (plain) or, with none, to the live total (opaque).
--- @param fight table
--- @param curve table|nil  HudBest.Curve's
--- @param live table|nil  NS.Meter.ReadLive's
--- @param elapsed number  plain seconds since the fight's combat entry (the slices' zero)
--- @param cooldowns table|nil  Chart.Cooldowns'
--- @return table|nil view  { count, step, span, values, max, best, note, cooldowns }
function Chart.LiveView(fight, curve, live, elapsed, cooldowns)
    local span = math.max(tonumber(elapsed) or 0, curve and curve.duration or 0, NS.Slices.STEP)
    local view = columnsOf(fight.id, span)
    if not view then return nil end
    view.cooldowns = cooldowns
    view.note = L["no best yet"]   -- short beside the heading (owner, 2026-11-11), "vs best pace"'s pair
    if curve then
        withBest(view, curve:playerAt(view.span), nil)
    else
        -- Opaque: copied, never truth-tested (`x or nil` would test it).
        local player = type(live) == "table" and live.player
        if type(player) == "table" then view.max = player.total end
    end
    return view
end

-- The fight-over chart's span and its clock: the fight's length (its duration or its steps, the
-- longer) from `shift` seconds in, and never short of the race `length` (0 for a fight).
local function overSpan(rec, final, clock)
    local duration = final and NS.Secrets.PlainNumber(final.duration) or 0
    local shift, length = clock and clock.shift or 0, clock and clock.length or 0
    local steps = (rec.count or 0) * NS.Slices.STEP
    return math.max(duration - shift, steps - shift, length, NS.Slices.STEP), shift, length
end

--- The fight-over card's chart: the fight's columns over its length, scaled to its plain final
--- player damage, against the best it was paced on when there is one. With a race's `clock` (the
--- Results detail, ruling X9) the columns run from its first hit (`shift` seconds in), the span reaches
--- at least its `length`, and `buzzer` is where that length falls (a fraction of the span). Nil when
--- this session holds no columns for it.
--- @param fight table
--- @param curve table|nil
--- @param final table|nil  the after-combat read (plain)
--- @param cooldowns table|nil  on the chart's clock (a race's already moved onto its race clock)
--- @param clock table|nil  { shift, length } (modules/Results_Races.lua Clock)
--- @return table|nil view
function Chart.OverView(fight, curve, final, cooldowns, clock)
    local rec = NS.Slices.Get(fight.id)
    if not rec or (rec.filled or 0) == 0 then return nil end
    local span, shift, length = overSpan(rec, final, clock)
    local view = columnsOf(fight.id, span, shift)
    if not view then return nil end
    if length > 0 then view.buzzer = length / view.span end
    local player = final and final.player and NS.Secrets.PlainNumber(final.player.total)
    if not player or player <= 0 then return nil end
    view.cooldowns, view.note = cooldowns, ""
    withBest(view, curve and curve:playerAt(view.span) or nil, player)
    return view
end

-- ── the chart ───────────────────────────────────────────────────────────────────────────────────

local Strip = {}
Strip.__index = Strip

-- A cast icon's hover: the client's spell tooltip for its plain ID.
local function iconEnter(f)
    if not (f.cast and GameTooltip) then return end
    GameTooltip:SetOwner(f, "ANCHOR_TOP")
    if not pcall(GameTooltip.SetSpellByID, GameTooltip, f.cast.spellID) then return GameTooltip:Hide() end
    GameTooltip:AddLine(L["Cast at %s"]:format(NS.Format.Length(f.cast.t)), Style.Rgb("gtip.muted"))
    GameTooltip:Show()
end

local function markEnter(f)
    if not (f.casts and GameTooltip) then return end
    GameTooltip:SetOwner(f, "ANCHOR_TOP")
    GameTooltip:SetText(L["%d cooldowns"]:format(#f.casts), Style.Rgb("gtip.title"))
    for _, c in ipairs(f.casts) do
        GameTooltip:AddLine(("%s  %s"):format(NS.Format.Length(c.t), tostring(NS.HudBreakdown.SpellName(c.spellID))),
            Style.Rgb("gtip.body"))
    end
    GameTooltip:Show()
end

local function hideTip() if GameTooltip then GameTooltip:Hide() end end

--- A chart built into `parent`: its heading, plot, line, zero line and time labels, placed by Place().
--- @param parent table
--- @return table chart
function Chart.New(parent)
    local s = setmetatable({ parent = parent, cols = {}, iconPool = NS.Pool.New(), markPool = NS.Pool.New(),
                             icons = {}, marks = {} }, Strip)
    s.title = Style.Text(parent, Style.FONT.SECTION)
    s.title:SetText(L["Damage profile"])
    s.note = Style.Text(parent, Style.FONT.CAPTION, nil, "RIGHT")
    s.plot = CreateFrame("Frame", nil, parent)
    s.plot.bg = s.plot:CreateTexture(nil, "BACKGROUND")
    s.plot.bg:SetAllPoints(s.plot)
    Style.Fill(s.plot.bg, "ct.chart.bg")
    s.over = CreateFrame("Frame", nil, s.plot)
    s.over:SetAllPoints(s.plot)
    s.over:SetFrameLevel((s.plot:GetFrameLevel() or 0) + NS.Constants.LAYERS.LEVEL.CHART_OVERLAY)
    s.line = s.over:CreateLine(nil, "OVERLAY")
    s.line:SetThickness(Chart.LINE_W)
    s.buzzer = s.over:CreateTexture(nil, "OVERLAY")
    s.buzzer:SetColorTexture(Chart.BUZZER[1], Chart.BUZZER[2], Chart.BUZZER[3], 1)
    s.buzzer:SetWidth(Chart.LINE_W)
    s.buzzer:Hide()
    s.zero = s.over:CreateTexture(nil, "OVERLAY")
    s.zero:SetHeight(1)
    Style.Fill(s.zero, "ct.chart.grid")
    s.axis = { Style.Text(parent, Style.FONT.CAPTION), Style.Text(parent, Style.FONT.CAPTION, nil, "CENTER"),
               Style.Text(parent, Style.FONT.CAPTION, nil, "RIGHT") }
    NS.HudTips.Attach(s.plot, "chart")
    return s
end

--- Show or hide the heading (its title and note) and the plot (with its time labels) apart: the HUD
--- keeps the heading over the pace bar when the plot is off.
--- @param head boolean
--- @param plot boolean
function Strip:SetParts(head, plot)
    head, plot = head and true or false, plot and true or false
    self.title:SetShown(head)
    self.note:SetShown(head)
    self.plot:SetShown(plot)
    for _, fs in ipairs(self.axis) do fs:SetShown(plot) end
    self.shown = plot
end

--- Show or hide every part.
function Strip:SetShown(on)
    self:SetParts(on, on)
end

--- The note at the heading's right, for a heading shown without its plot (Draw sets it otherwise).
function Strip:SetNote(text)
    self.note:SetText(text or "")
end

--- Place the chart at `y` (negative, from `anchor`'s top) across `width`, `midH` (default 0) left
--- clear between the heading's line and the plot; answers its height.
--- @param anchor table
--- @param y number
--- @param width number
--- @param midH number|nil
--- @return number height
function Strip:Place(anchor, y, width, midH)
    local plotH = Chart.PlotHeight()
    self.width, self.plotH = width, plotH
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, y)
    -- The note sits on the heading's bottom edge, so the small caption lines up with the larger
    -- heading's text instead of hanging from its top (owner, 2026-11-11).
    self.note:ClearAllPoints()
    self.note:SetPoint("BOTTOMRIGHT", self.title, "BOTTOMLEFT", width, 0)
    local py = y - Chart.HEAD_H - (midH or 0)
    self.frameH = Chart.FrameHeight(plotH)
    self.plot:ClearAllPoints()
    self.plot:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, py)
    self.plot:SetSize(width, self.frameH)
    self.zero:ClearAllPoints()
    self.zero:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", Chart.INSET, Chart.INSET)
    self.zero:SetPoint("BOTTOMRIGHT", self.plot, "BOTTOMRIGHT", -Chart.INSET, Chart.INSET)
    local ay = py - self.frameH - Chart.GAP
    local points = { { "TOPLEFT", 0 }, { "TOP", width / 2 }, { "TOPRIGHT", width } }
    for i, fs in ipairs(self.axis) do
        fs:ClearAllPoints()
        fs:SetPoint(points[i][1], anchor, "TOPLEFT", points[i][2], ay)
    end
    self.geometry = nil
    self.blockH = Chart.BlockHeight(plotH, midH)   -- what Place answered last (the suites read it)
    return self.blockH
end

-- The columns' and the line's look, once per Appearance stamp.
function Strip:restyle()
    local A = NS.HudAppearance
    if self.stamp == A.stamp then return end
    self.stamp = A.stamp
    self.look = A.Bar("chart")
    self.line:SetColorTexture(A.Swatch("chart", "bestColor"))
    self.zero:SetShown(A.On("hud.chart.zeroLine"))
    for _, col in ipairs(self.cols) do col.stamp = nil end
end

local function newColumn(plot)
    local col = CreateFrame("StatusBar", nil, plot)
    col:SetOrientation("VERTICAL")
    return col
end

-- Lay `count` columns across the plot on whole-pixel edges, within the configured height from the
-- plot's bottom (the RESERVE row over them is the icons').
function Strip:layoutColumns(count)
    local key = ("%d|%s|%s"):format(count, tostring(self.width), tostring(self.plotH))
    if self.geometry == key then return end
    self.geometry = key
    local inner = math.max(0, (self.width or 0) - 2 * Chart.INSET)
    local xs, widths = Chart.ColumnEdges(inner, count)
    local h = math.max(1, (self.plotH or 0) - 2 * Chart.INSET)
    for i = 1, count do
        local col = self.cols[i] or newColumn(self.plot)
        self.cols[i] = col
        col:ClearAllPoints()
        col:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", Chart.INSET + xs[i], Chart.INSET)
        col:SetSize(widths[i], h)
    end
    self.lineKey = nil
end

-- One column's fill: its look when the stamp changed, then its value against `max`, both opaque,
-- straight to the widget.
function Strip:fill(i, col, value, max)
    if col.stamp ~= self.stamp then
        col.stamp = self.stamp
        NS.HudAppearance.PaintBar(col, self.look)
    end
    if value == nil or max == nil then
        col:SetMinMaxValues(0, 1)
        col:SetValue(0)
    else
        col:SetMinMaxValues(0, max)
        col:SetValue(value)
    end
    col.index = i
    col:Show()
end

-- The best's line: plain geometry from 0:00 to `level` (a plain fraction of the plot's height).
function Strip:drawLine(level)
    self.line:SetShown(level ~= nil)
    if level == nil then return end
    local key = ("%s|%s"):format(tostring(self.geometry), tostring(level))
    if self.lineKey == key then return end
    self.lineKey = key
    local h = (self.plotH or 0) - 2 * Chart.INSET
    self.line:SetStartPoint("BOTTOMLEFT", self.over, Chart.INSET, Chart.INSET)
    self.line:SetEndPoint("BOTTOMLEFT", self.over, (self.width or 0) - Chart.INSET, Chart.INSET + h * level)
end

-- A race's buzzer line at `at` (a plain fraction of the plot's width), up the plot; hidden with none.
function Strip:drawBuzzer(at)
    self.buzzer:SetShown(at ~= nil)
    if at == nil then return end
    local inner = (self.width or 0) - 2 * Chart.INSET
    local x = Chart.INSET + inner * math.max(0, math.min(1, at)) - Chart.LINE_W / 2
    self.buzzer:ClearAllPoints()
    self.buzzer:SetPoint("TOPLEFT", self.over, "TOPLEFT", x, -Chart.INSET)
    self.buzzer:SetHeight(math.max(1, (self.frameH or 0) - 2 * Chart.INSET))
end

--- Draw `view` (Chart.LiveView's or OverView's). Its `max` may be secret (live with no best): it, as
--- each column's value, only reaches SetMinMaxValues and SetValue.
function Strip:Draw(view)
    self:restyle()
    local count = view and view.count or 0
    self:layoutColumns(count)
    for i = 1, count do self:fill(i, self.cols[i], view.values[i], view.max) end
    for i = count + 1, #self.cols do self.cols[i]:Hide() end
    self:drawLine(view and view.best or nil)
    self:drawBuzzer(view and view.buzzer or nil)
    local span = view and view.span or 0
    self:drawIcons(view and view.cooldowns or nil, span)
    self.note:SetText(view and view.note or "")
    self.axis[1]:SetText(NS.Format.Length(0))
    self.axis[2]:SetText(NS.Format.Length(math.floor(span / 2)))
    self.axis[3]:SetText(NS.Format.Length(span))
end

local function newIcon(over)
    local f = CreateFrame("Frame", nil, over)
    f:SetSize(Chart.ICON, Chart.ICON)
    f:EnableMouse(true)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints(f)
    f.tex:SetTexCoord(ICON_CROP[1], ICON_CROP[2], ICON_CROP[3], ICON_CROP[4])
    NS.Skin.IconBorder(f, { fromSkin = true, hud = true })
    f:SetScript("OnEnter", iconEnter)
    f:SetScript("OnLeave", hideTip)
    return f
end

local function newMark(over)
    local f = CreateFrame("Frame", nil, over)
    f:SetSize(Chart.ICON, Chart.ICON)
    f:EnableMouse(true)
    f.bg = f:CreateTexture(nil, "ARTWORK")
    f.bg:SetAllPoints(f)
    Style.Fill(f.bg, "handle.bg")
    f.text = Style.Text(f, Style.FONT.TEXT, nil, "CENTER")
    f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    f:SetScript("OnEnter", markEnter)
    f:SetScript("OnLeave", hideTip)
    return f
end

-- True when `casts` holds the same casts (time and spell, in order) as the last list laid. The HUD
-- builds a fresh list every tick, so identity alone would lay the icons again four times a second.
local function sameCasts(laid, casts, n)
    if type(laid) ~= "table" or #laid ~= n * 2 then return false end
    for i = 1, n do
        if laid[i * 2 - 1] ~= casts[i].t or laid[i * 2] ~= casts[i].spellID then return false end
    end
    return true
end

-- The icons for `casts` over `span`, laid again only when the casts, the span or the geometry
-- changed.
function Strip:drawIcons(casts, span)
    local n = casts and #casts or 0
    if self.iconSpan == span and self.iconGeom == self.geometry and sameCasts(self.iconLaid, casts, n) then
        return
    end
    local laid = {}
    for i = 1, n do laid[i * 2 - 1], laid[i * 2] = casts[i].t, casts[i].spellID end
    self.iconLaid, self.iconSpan, self.iconGeom = laid, span, self.geometry
    NS.Pool.ReleaseAll(self.iconPool, function(f) f.cast = nil end)
    NS.Pool.ReleaseAll(self.markPool, function(f) f.casts = nil end)
    self.icons, self.marks = {}, {}
    local placed, xs = {}, {}
    for i = 1, n do
        local x = Chart.IconX(casts[i].t, span, self.width)
        if x then placed[#placed + 1], xs[#xs + 1] = casts[i], x end
    end
    local rows, marks = Chart.IconRows(xs, Chart.IconRowCount(self.frameH))
    for i, cast in ipairs(placed) do
        if rows[i] then
            local f = NS.Pool.Acquire(self.iconPool, function() return newIcon(self.over) end)
            f.cast = cast
            f.tex:SetTexture(NS.HudBreakdown.SpellIcon(cast.spellID))
            f:ClearAllPoints()
            f:SetPoint("CENTER", self.over, "TOPLEFT", xs[i], Chart.IconY(rows[i]))
            self.icons[#self.icons + 1] = { frame = f, cast = cast, x = xs[i], row = rows[i] }
        end
    end
    for _, m in ipairs(marks) do
        local members = {}
        for k, i in ipairs(m.members) do members[k] = placed[i] end
        local f = NS.Pool.Acquire(self.markPool, function() return newMark(self.over) end)
        f.casts = members
        f.text:SetText(L["+%d"]:format(#members))
        f:ClearAllPoints()
        f:SetPoint("CENTER", self.over, "TOPLEFT", m.x, Chart.IconY(m.row))
        self.marks[#self.marks + 1] = { frame = f, casts = members, x = m.x, row = m.row }
    end
end

--- The icons drawn now, for the suites: { { frame, cast, x, row }, ... }.
function Strip:Icons() return self.icons end

--- The +n marks drawn now, for the suites.
function Strip:Marks() return self.marks end

--- The columns drawn now, in order, for the suites.
function Strip:Columns()
    local out = {}
    for i, col in ipairs(self.cols) do
        if col:IsShown() then out[i] = col end
    end
    return out
end

-- ── the pace bar ────────────────────────────────────────────────────────────────────────────────

local Pace = {}
Pace.__index = Pace

local AHEAD = "ct.ahead"          -- the green past the tick
local BEHIND = "ct.pace.behind"   -- the red shortfall to the tick

-- The red shortfall hangs off the right edge of the behind half's fill texture, to the half's own
-- right edge (the tick): the client places it from the value. Again whenever the fill texture is set
-- (the bar may hand back a new region).
function Pace:anchorShortfall()
    local fill = self.behind:GetStatusBarTexture()
    self.shortfall:ClearAllPoints()
    self.shortfall:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    self.shortfall:SetPoint("BOTTOMRIGHT", self.behind, "BOTTOMRIGHT", 0, 0)
    self.fillAnchor = fill
end

-- The bar's look, once per Appearance stamp: the behind half in the spell rows' bar look, the ahead
-- half in its texture and the green, the shortfall in the red, both at the look's opacity.
function Pace:restyle()
    local A = NS.HudAppearance
    if self.stamp == A.stamp then return end
    self.stamp = A.stamp
    local look = A.Bar("spells")
    A.PaintBar(self.behind, look)
    local r, g, b = Style.Rgb(AHEAD)
    A.PaintBar(self.ahead, look, { r = r, g = g, b = b, a = look.a })
    Style.Fill(self.shortfall, BEHIND, look.a)
    self:anchorShortfall()
end

local function halfBar(parent)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetMinMaxValues(0, 1)
    b:SetValue(0)
    return b
end

--- The pace bar built into `parent`: the track, the behind and ahead halves split at the on-pace
--- tick, the red shortfall, and the tick over both.
--- @param parent table
--- @return table pace
function Chart.NewPace(parent)
    local p = setmetatable({}, Pace)
    p.bar = CreateFrame("Frame", nil, parent)
    p.track = p.bar:CreateTexture(nil, "BACKGROUND")
    p.track:SetAllPoints(p.bar)
    Style.Fill(p.track, "ct.pace.track")
    p.behind = halfBar(p.bar)
    p.ahead = halfBar(p.bar)
    p.shortfall = p.behind:CreateTexture(nil, "ARTWORK")
    p.over = CreateFrame("Frame", nil, p.bar)
    p.over:SetAllPoints(p.bar)
    p.over:SetFrameLevel((p.bar:GetFrameLevel() or 0) + 2)
    p.tick = p.over:CreateTexture(nil, "OVERLAY")
    Style.Fill(p.tick, "ct.pace.tick")
    p.tick:SetWidth(2)
    p:restyle()
    NS.HudTips.Attach(p.bar, "pace")
    return p
end

function Pace:SetShown(on)
    self.bar:SetShown(on and true or false)
end

--- Place it on the PACE_H line at `y` (negative, from `anchor`'s top) across `width`, DPS Race's
--- geometry: the bar 2px under the line's top and 4px shorter than it, the tick in its middle, the
--- behind half left of it and the ahead half right of it; answers the line's height.
--- @return number
function Pace:Place(anchor, y, width)
    self.bar:ClearAllPoints()
    self.bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, y - 2)
    self.barW = math.max(1, width)
    local h = Chart.PACE_H - 4
    self.bar:SetSize(self.barW, h)
    local x = math.floor(self.barW / 2 + 0.5)
    self.tick:ClearAllPoints()
    self.tick:SetPoint("TOP", self.bar, "TOPLEFT", x, 2)
    self.tick:SetPoint("BOTTOM", self.bar, "BOTTOMLEFT", x, -2)
    self.behind:ClearAllPoints()
    self.behind:SetPoint("TOPLEFT", self.bar, "TOPLEFT", 0, 0)
    self.behind:SetSize(math.max(1, x), h)
    self.ahead:ClearAllPoints()
    self.ahead:SetPoint("TOPLEFT", self.bar, "TOPLEFT", x, 0)
    self.ahead:SetSize(math.max(1, self.barW - x), h)
    self:anchorShortfall()
    return Chart.PACE_H
end

--- The range (plain, HudBest.Bounds: the pace in the middle), then the total (opaque live, plain
--- after the fight) straight to both halves, each clamping it: behind pace the behind half stops
--- short of the tick and the red fills the rest; ahead, it is full and the ahead half fills green.
--- @param lo number
--- @param hi number
--- @param total any
function Pace:Set(lo, hi, total)
    self:restyle()
    local mid = (lo + hi) / 2
    self.behind:SetMinMaxValues(lo, mid)
    self.ahead:SetMinMaxValues(mid, hi)
    if total == nil then total = lo end
    self.behind:SetValue(total)
    self.ahead:SetValue(total)
end
