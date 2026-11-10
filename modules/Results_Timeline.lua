local _, NS = ...
-- modules/Results_Timeline.lua — the ability timeline (spec §7, plan Task 4.3; its pure half is
-- modules/Results_TimelineData.lua): a window opened from the Results detail's Timeline button that
-- sets every ability the fight cast on one time axis, beside the fight the detail compares it with.
-- Adapted from DPS Race @045f479 (modules/Results_Timeline.lua) without its race: the axis is the
-- longer fight's length, each fight timed from its own start; and with a pet toggle DPS Race never
-- had (spec §7: "pet abilities (toggle)").
--
-- THE LAYOUT. A legend bar (this fight's date in gold, the compared fight's in blue and what it is:
-- the best, the runner-up or the picked fight; the Pet abilities toggle at its right while either
-- fight has a pet cast), then two sections under their own headings in the Results detail's heading
-- style (FONT.SECTION). Casts: two icon strips on the lanes' time axis, this fight's above the
-- compared fight's, every cast its ability's icon at its time; icons too close to sit apart stack onto
-- extra rows, this fight's upward and the compared fight's downward (away from each other), each
-- strip growing to the most rows it needs (past MAX_STACK rows the rest overlap the row that frees
-- first and say so in their tooltip). By ability: one pair of lanes per ability, its name cell (icon,
-- name, "(pet)" for a pet's, and under the name its cooldown when 29 s or more) beside two lanes, the
-- top one this fight's casts (thin gold ticks), the bottom one the compared fight's (blue), each
-- lane's cast count just past its right end. Long cooldowns first, longest first; the rest by count.
-- The time axis (0, the quarters, the end) is pinned under both sections, which scroll together (the
-- mouse wheel), and drawn again under the compared fight's strip. Every tooltip but the controls'
-- sits beside the window, level with what it is for.
--
-- ZOOM. The controls at the right of the Casts heading line (zoom out, zoom in, reset, scroll left,
-- scroll right, the `?`) step the time axis through ZOOMS for the strips and the lanes together: the
-- time area is laid out ZOOMS[i] times the lanes' width and shown through clipping scroll frames (one
-- over the strips and their axis, one over the lanes, one over the pinned axis) that pan together,
-- the name cells and the counts staying put. Zoomed in, a scrollbar along the window's bottom, its
-- thumb the view's share of the axis, scrolls both sections. The mouse wheel anywhere in the window
-- scrolls up and down; Shift+wheel pans while zoomed in (up toward 0:00); Ctrl+wheel zooms a step
-- (Ctrl wins over Shift), keeping the moment under the cursor where it was when the cursor is over
-- the time area. The client has no horizontal wheel for addons. The level reads from gold to red as
-- the zoom goes up (Data.ZoomColor). The view is kept as the fraction of the axis at its left edge
-- (`pos`), so a resize keeps the same moment at the left. Zoom and pan go back to 1x on another
-- fight or compare target; the pet toggle keeps them.
--
-- WHICH FIGHTS. The detail's: its fight, and its compare target (the pane's CompareTarget once plan
-- Task 4.4's compare gives it one, else Data.CompareTarget). Every detail draw redraws the window
-- while it is open (Timeline.DetailChanged). With no compared fight, or one with no casts, the blue
-- lanes stay empty under a note; a fight with no casts (the button is disabled for one, but the
-- detail may move to one while the window is open) shows a message in place of the lanes.
--
-- THE WINDOW is the Results window's kind (standalone-windows): a plain frame skinned through the
-- skin's Shell, closed through NS.MakeCloseButton, in UISpecialFrames (Escape closes it), clamped,
-- movable by its title bar and resizable (modules/Sizing.lua); `results.scale` acts on it, as on the
-- Results window it sits over. It closes with the Results window. Built on first open. Every open
-- places it exactly over the Results window (Results.Placement), no smaller than this one's minimums.
-- A move or a resize lasts while it is open and is never stored.
--
-- A MODAL. Opened from the Results window, it sits one strata above it (LAYERS.STRATA.MODAL,
-- frame-layering-§1), toplevel, and re-raises a shown StaticPopup when it opens (frame-layering-§4).
-- While it is open the Results window wears its dim cover (Results.SetCovered), which takes that
-- window's mouse; Escape closes this window first (the Results window's onHide shows itself again
-- while covered), and the cover goes when this one closes. Its skin is SHELL: the shared one made
-- fully opaque (the ct.modal.* owner tokens), so nothing of the Results window shows through.
--
-- PLAIN DATA ONLY: the stored record's casts (plain numbers). Every position is computed from the
-- constants and the window's tracked size, never read back off a frame. The one geometry read is the
-- window's left edge, for where a Ctrl+wheel's cursor is (no meter value is anywhere near it).

local Timeline = { wanted = false, showPet = true }
NS.ResultsTimeline = Timeline

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT
local D = NS.ResultsTimelineData
local Tbl = NS.ResultsTable
local C = Tbl.COLORS

Timeline.Data = D
Timeline.FRAME_NAME = "CombatTrailTimeline"

-- The window's own sizes (the shared geometry is Data's).
Timeline.ICON = 16
Timeline.MARK_W = 2         -- a cast's tick, the lane's full height
Timeline.MARK_HIT = 8       -- its hover frame's width
Timeline.LEGEND_H = 26
Timeline.NOTE_H = 16
Timeline.AXIS_H = 20
Timeline.CAST_ICON = 14
Timeline.CLIP_PAD = 8       -- the strips' clip reaches past the lanes at each end: an icon at 0:00 shows whole
Timeline.BOTTOM = 6         -- the pinned axis's (or the scrollbar's) gap to the window's bottom
-- The Casts heading line's controls: each a 16 px box, an icon 11 px, 2 px apart and SCROLL_SEP
-- between the zoom controls and the arrows and between the arrows and the `?`. `-` and `+` are BAR
-- strokes (a font's minus is short and thin at any size), the `?` a 13 px glyph and the level 14 px.
Timeline.CONTROL = 16
Timeline.CONTROL_ICON = 11
Timeline.CONTROL_FONT = "GameFontHighlightLarge"
Timeline.BAR = { 9, 2 }
Timeline.HELP_SIZE = 13
Timeline.LEVEL_SIZE = 14
Timeline.SCROLL_SEP = 8
Timeline.DIM = 0.4

-- The two fights' colors: this fight gold, the compared fight blue (the mockup's). They and the
-- corridors are the fights' identity, data hues, the same under every skin.
Timeline.THIS = { Style.GOLD[1], Style.GOLD[2], Style.GOLD[3] }
Timeline.OTHER = { 0.35, 0.66, 1.0 }
-- The corridors behind them: this fight's strip and lanes a dark gold, the compared fight's a dark
-- blue, each translucent over the window's fill. Read at paint time (Timeline.Repaint).
Timeline.CORRIDOR = { this = { 0.30, 0.24, 0.02, 0.45 }, other = { 0.06, 0.16, 0.32, 0.45 } }
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- a white disc, tinted (the legend's swatches)
local WHITE = "Interface\\Buttons\\WHITE8x8"                      -- a cast's tick, tinted
local TRACK = Style.Tok("ct.chart.bg")
local GRID = Style.Tok("ct.chart.grid")
local HEADER_H = Style.TITLE_BAR_H

-- The skin's Shell made opaque (LibKa0s-Skin-1.0's slot remap, core/SkinSetup.lua's ct.modal.*).
Timeline.SHELL = { tokens = { bg = "ct.modal.bg", inner = "ct.modal.inner", divider = "ct.modal.divider" } }

local ui        -- the built window
local pane      -- the detail pane the window follows
local hiding = false

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Timeline", fmt, ...) end
end

-- ── the window ──────────────────────────────────────────────────────────────────────────────────

local layout, resize, draw

-- A corridor (a strip's track, a lane) in its fight's CORRIDOR color, read now: `side` "a" this fight's.
local function paint(tex, side)
    Style.Fill(tex, Timeline.CORRIDOR[side == "a" and "this" or "other"] or TRACK)
end

local function disc(parent, color, size)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(DISC)
    Style.Vertex(t, color, 0.95)
    t:SetSize(size, size)
    return t
end

local function buildChrome(f)
    f.title = Style.PlainText(f, FONT.TITLE, "CENTER")
    f.title:SetText(L["Ability timeline"])
    ui.close = NS.MakeCloseButton(f, function() Timeline.Hide() end)
    local drag = CreateFrame("Frame", nil, f)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    -- Moved for as long as it is open: nothing stored, the next open goes over the Results window.
    drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    ui.drag = drag
    Style.Header(f, { title = f.title, drag = drag, right = { ui.close }, n = 1 })
end

-- The pet toggle: a session's view state, never stored (the zoom is kept across a flip).
local function buildPetToggle(f)
    local b = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    b:SetSize(20, 20)
    b.label = Tbl.Text(b, FONT.TEXT)
    b.label:SetPoint("LEFT", b, "RIGHT", 1, 0)
    Tbl.SetCheckLabel(b, L["Pet abilities"])
    b:SetScript("OnClick", function() Timeline.SetShowPet(not Timeline.showPet) end)
    NS.Skin.Checkbox(b)   -- the skin's check box, after its click script
    ui.petToggle = b
end

-- The legend bar: a gold disc and this fight's label, a blue one and the compared fight's, then the
-- hint; each anchored after the one before it, the pet toggle at the bar's right. The note sits under
-- the bar.
local function buildLegend(f)
    local y = -HEADER_H - Timeline.LEGEND_H / 2
    ui.swatchA = disc(f, Timeline.THIS, 10)
    ui.swatchA:SetPoint("LEFT", f, "TOPLEFT", D.PAD, y)
    ui.legendA = Style.Text(f, FONT.TEXT, C.text)
    ui.legendA:SetPoint("LEFT", ui.swatchA, "RIGHT", 6, 0)
    ui.swatchB = disc(f, Timeline.OTHER, 10)
    ui.swatchB:SetPoint("LEFT", ui.legendA, "RIGHT", 16, 0)
    ui.legendB = Style.Text(f, FONT.TEXT, C.text)
    ui.legendB:SetPoint("LEFT", ui.swatchB, "RIGHT", 6, 0)
    ui.hint = Style.Text(f, FONT.CAPTION)
    ui.hint:SetPoint("LEFT", ui.legendB, "RIGHT", 16, 0)
    ui.hint:SetText(L["Right: casts in each lane"])
    buildPetToggle(f)
    ui.petToggle:SetPoint("RIGHT", f, "TOPRIGHT", -(D.PAD + Tbl.BadgeWidth(L["Pet abilities"], false) + 1), y)
    ui.note = Style.Text(f, FONT.TEXT, C.amber)
    ui.note:SetPoint("TOPLEFT", f, "TOPLEFT", D.PAD, -HEADER_H - Timeline.LEGEND_H)
    ui.legendLine = f:CreateTexture(nil, "ARTWORK")
    ui.legendLine:SetHeight(1)
    Style.Fill(ui.legendLine, "ct.rule")
end

-- One Casts strip: its track (its fight's corridor, painted as it is placed), its fight's name in the
-- name cell in its color, and the dim note it shows with no casts.
local function buildStrip(color)
    local s = { track = ui.content:CreateTexture(nil, "BACKGROUND") }
    s.label = Style.Text(ui.content, FONT.TEXT, color)
    s.label:SetWidth(D.NAME_W)
    s.note = Style.Text(ui.content, FONT.CAPTION)
    return s
end

-- A clipping scroll frame on `parent` and the layer it shows (its scroll child): the layer is the
-- zoomed time area, and panning scrolls it sideways under the clip.
local function clipLayer(parent)
    local clip = CreateFrame("ScrollFrame", nil, parent)
    local layer = CreateFrame("Frame", nil, clip)
    clip:SetScrollChild(layer)
    return clip, layer
end

-- The `?` control's hover: the mouse controls on bullets, above it as the other controls' tooltips are.
local function helpTip(self)
    local tip, lines = GameTooltip, D.HelpLines()
    if not tip then return end
    tip:SetOwner(self, "ANCHOR_TOP")
    local r, g, b = Style.Rgb("gtip.title")
    tip:SetText(lines[1], r, g, b, 1, true)
    Style.AddTipLines(tip, lines, 2)
    tip:Show()
end

-- The skin's body face at `size` px on `fs` (its color kept): the `?` and the level.
local function sizeFont(fs, size)
    fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    NS.Skin.Font(fs)
end

-- `-` or `+` drawn as strokes: the control's icon a BAR across, and for `+` a stroke down through it,
-- which the strip tints with the icon (Style.PaintStrip); the glyph stays the hidden text.
local function strokes(b, plus)
    local w, h = Timeline.BAR[1], Timeline.BAR[2]
    b.icon:SetTexture(WHITE)
    b.icon:SetSize(w, h)
    b.icon:Show()
    b.glyph:Hide()
    if plus then
        b.stroke = b:CreateTexture(nil, "OVERLAY")
        b.stroke:SetTexture(WHITE)
        b.stroke:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.stroke:SetSize(h, w)
    end
    Style.PaintStrip(ui.zoomStrip)
    return b
end

-- One control on the Casts heading line, over the strips' clip.
local function control(name, glyph, tip, onClick, onEnter)
    local b = Style.ControlButton(ui.content, name, glyph, tip, onClick)
    -- `onEnter` replaces the stock tooltip BEFORE the strip hooks on: a SetScript after AddToStrip
    -- would drop the hook, and the control would never turn gold.
    if onEnter then b:SetScript("OnEnter", onEnter) end
    Style.AddToStrip(ui.zoomStrip, b)
    b:SetFrameLevel(ui.content:GetFrameLevel() + 10)
    b:SetSize(Timeline.CONTROL, Timeline.CONTROL)
    b.icon:SetSize(Timeline.CONTROL_ICON, Timeline.CONTROL_ICON)
    b.glyph:SetFontObject(Timeline.CONTROL_FONT)
    return b
end

-- The controls at the right end of the Casts heading line, right to left: the `?` (on the lanes'
-- right edge, placeControls), scroll right and scroll left, then reset, zoom in, zoom out; the zoom
-- level left of them (read left to right: "1x - + reset < > ?").
local function buildZoom()
    ui.zoomStrip = Style.NewStrip()
    -- Always live; a click does nothing (its tooltip is the point).
    ui.help = control(nil, "?", nil, function() end, helpTip)
    sizeFont(ui.help.glyph, Timeline.HELP_SIZE)
    ui.scrollRight = control("chevron-right", ">", L["Scroll right, toward the end (or Shift+mouse wheel down)"],
        function() Timeline.Pan(-1) end)
    ui.scrollRight:SetPoint("RIGHT", ui.help, "LEFT", -Timeline.SCROLL_SEP, 0)
    ui.scrollLeft = control("chevron-left", "<", L["Scroll left, toward 0:00 (or Shift+mouse wheel up)"],
        function() Timeline.Pan(1) end)
    ui.scrollLeft:SetPoint("RIGHT", ui.scrollRight, "LEFT", -2, 0)
    ui.zoomReset = control("reset", "R", L["Reset zoom"], function() Timeline.ResetZoom() end)
    ui.zoomReset:SetPoint("RIGHT", ui.scrollLeft, "LEFT", -Timeline.SCROLL_SEP, 0)
    ui.zoomIn = strokes(control(nil, "+", L["Zoom in (or Ctrl+mouse wheel up)"], function() Timeline.ZoomBy(1) end), true)
    ui.zoomIn:SetPoint("RIGHT", ui.zoomReset, "LEFT", -2, 0)
    ui.zoomOut = strokes(control(nil, "-", L["Zoom out (or Ctrl+mouse wheel down)"], function() Timeline.ZoomBy(-1) end))
    ui.zoomOut:SetPoint("RIGHT", ui.zoomIn, "LEFT", -2, 0)
    ui.zoomText = Style.PlainText(ui.content, FONT.CAPTION, "RIGHT")
    sizeFont(ui.zoomText, Timeline.LEVEL_SIZE)
    ui.zoomText:SetPoint("RIGHT", ui.zoomOut, "LEFT", -6, 0)
end

-- The controls' right end (the `?`) on the lanes' right edge at this geometry, so the row follows a resize.
local function placeControls(g)
    ui.help:ClearAllPoints()
    ui.help:SetPoint("TOPRIGHT", ui.content, "TOPLEFT", g.laneX + g.laneW, 0)
end

-- One mouse-wheel notch on any part of the window.
local function onWheel(_, delta) Timeline.Wheel(delta) end

-- The scrollbar (zoomed in only): a horizontal slider whose values are the view's left edge in px
-- along the zoomed axis, over its track; its thumb the view's share of it.
local function buildBar(f)
    local bar = CreateFrame("Slider", nil, f)
    bar:SetOrientation("HORIZONTAL")
    bar:SetHeight(D.SCROLL_H)
    bar:EnableMouse(true)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", onWheel)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints(bar)
    Style.Fill(bar.track, "ct.scroll.track")
    bar.thumb = bar:CreateTexture(nil, "OVERLAY")
    Style.Fill(bar.thumb, "ct.scroll.thumbAlt")
    bar:SetThumbTexture(bar.thumb)
    -- Ours (applyPan) set it while `syncing`; the player's drag or click scrolls.
    bar:SetScript("OnValueChanged", function(_, value)
        if not ui.syncing then Timeline.ScrollTo(value) end
    end)
    bar:Hide()
    ui.bar = bar
end

-- The pinned axis's clip on the window and the scrollbar under it.
local function buildAxis(f)
    ui.axisClip, ui.axisLayer = clipLayer(f)
    buildBar(f)
    ui.axis, ui.castsAxis, ui.grid = {}, {}, {}
    ui.axisPool, ui.castsAxisPool = NS.Pool.New(), NS.Pool.New()
    ui.gridPool, ui.laneGridPool = NS.Pool.New(), NS.Pool.New()
end

local function buildBody(f)
    ui.scroll = CreateFrame("ScrollFrame", nil, f)
    ui.content = CreateFrame("Frame", nil, ui.scroll)
    ui.scroll:SetScrollChild(ui.content)
    ui.scroll:EnableMouseWheel(true)
    ui.scroll:SetScript("OnMouseWheel", onWheel)
    -- The time area's two clips over the content (a child frame draws over its parent's textures).
    local level = ui.content:GetFrameLevel() + 5
    ui.castsClip, ui.castsLayer = clipLayer(ui.content)
    ui.lanesClip, ui.marks = clipLayer(ui.content)
    ui.castsClip:SetFrameLevel(level)
    ui.lanesClip:SetFrameLevel(level)
    ui.pairs = NS.Pool.New()
    ui.markPool = NS.Pool.New()
    ui.hitPool = NS.Pool.New()
    ui.iconPool = NS.Pool.New()
    ui.castsHead = Style.Text(ui.content, FONT.SECTION)
    ui.castsHead:SetText(L["Casts"])
    ui.lanesHead = Style.Text(ui.content, FONT.SECTION)
    ui.lanesHead:SetText(L["By ability"])
    ui.strips = { a = buildStrip(Timeline.THIS), b = buildStrip(Timeline.OTHER) }
    ui.empty = Style.Text(f, FONT.EMPTY, nil, "CENTER")
    ui.empty:SetPoint("CENTER", f, "CENTER", 0, 0)
    buildZoom()
    buildAxis(f)
end

-- A close-stack close, a frame later: the Results window's cover goes unless the timeline is open
-- again, and a talent tree that close made way for sends the Results window aside (its own rule).
local function settle()
    if Timeline.IsShown() then return end
    NS.Results.SetCovered(false)
    NS.Results.StepAsideForTree()
end

local function onHide()
    Tbl.HideTip()
    if hiding or (ui and ui.frame:IsShown()) then return end
    -- Escape (UISpecialFrames): the player closed it. The cover stays until the close stack is done,
    -- so the Results window, hidden by the same Escape, still sees it and shows again.
    Timeline.wanted = false
    if C_Timer and C_Timer.After then C_Timer.After(0, settle) else settle() end
end

-- Every size change, the grip's or not: the tracked size the layouts read, never under the minimums.
local function trackSize(width, height)
    if type(width) == "number" then ui.width = math.max(D.MIN_WIDTH, width) end
    if type(height) == "number" then ui.height = math.max(D.MIN_HEIGHT, height) end
end

-- Exactly over the Results window: its anchor and its size in the view shown, no smaller than this
-- window's minimums. Every open; nothing stored.
local function applyPlacement()
    local f = ui.frame
    local point, relativePoint, x, y, width, height = NS.Results.Placement()
    trackSize(width, height)
    f:ClearAllPoints()
    f:SetPoint(point, UIParent, relativePoint, x, y)
    f:SetSize(ui.width, ui.height)
end

local function ensureWindow()
    if ui then return ui end
    local f = CreateFrame("Frame", Timeline.FRAME_NAME, UIParent, "BackdropTemplate")
    ui = { frame = f, rows = {}, castsA = {}, castsB = {}, offset = 0, zoomI = 1, pos = 0,
           width = D.MIN_WIDTH, height = D.MIN_HEIGHT }
    f:Hide()
    f:SetFrameStrata(NS.Constants.LAYERS.STRATA.MODAL)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetToplevel(true)
    buildChrome(f)
    buildLegend(f)
    buildBody(f)
    NS.Skin.Shell(f, Timeline.SHELL)
    f:SetScript("OnHide", onHide)
    -- The wheel anywhere in the window (the scroll frame and the scrollbar take it too).
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", onWheel)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Timeline.FRAME_NAME) end
    -- Smooth resizing (modules/Sizing.lua): while the grip is dragged only `resize` runs, once a frame;
    -- the full `layout` (every pair and tick re-pooled) runs once on release. No `done`: the size is
    -- never stored.
    NS.Sizing.MakeResizable(f, {
        minWidth = D.MIN_WIDTH, minHeight = D.MIN_HEIGHT,
        size = trackSize, layout = function() resize() end, redraw = function() layout() end,
    })
    debug("window built")
    return ui
end

-- ── one pair of lanes ───────────────────────────────────────────────────────────────────────────

local function track(parent)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetHeight(D.LANE_H)
    return t
end

-- The name's hover: the client's spell tooltip beside the window, then both fights' counts.
local function nameTip(pair)
    local row = pair.row
    if not (row and ui) then return end
    Tbl.SpellTip(ui.frame, pair, row.spellID, D.RowLines(row, D.OtherLabel(ui.other, ui.kind)))
end

local function newPair()
    local pair = CreateFrame("Frame", nil, ui.content)
    pair:SetHeight(2 * D.LANE_H + D.LANE_GAP)
    pair.icon = pair:CreateTexture(nil, "ARTWORK")
    pair.icon:SetSize(Timeline.ICON, Timeline.ICON)
    pair.icon:SetPoint("LEFT", pair, "TOPLEFT", 0, -D.LANE_H / 2)
    Style.IconEdge(pair, pair.icon)
    pair.name = Style.Text(pair, FONT.TEXT, C.text)
    pair.name:SetPoint("LEFT", pair.icon, "RIGHT", 6, 0)
    pair.name:SetWidth(D.NAME_W - Timeline.ICON - 6)
    -- The cooldown on the bottom lane's line, under the name.
    pair.cd = Style.Text(pair, FONT.CAPTION, C.dim)
    pair.cd:SetPoint("LEFT", pair, "TOPLEFT", Timeline.ICON + 6, -(1.5 * D.LANE_H + D.LANE_GAP))
    pair.cd:SetWidth(D.NAME_W - Timeline.ICON - 6)
    pair.laneA, pair.laneB = track(pair), track(pair)
    pair.countA = Style.Text(pair, FONT.TEXT, Timeline.THIS)
    pair.countB = Style.Text(pair, FONT.TEXT, Timeline.OTHER)
    pair.hit = CreateFrame("Frame", nil, pair)
    pair.hit:SetPoint("TOPLEFT", pair, "TOPLEFT", 0, 0)
    pair.hit:SetSize(D.NAME_W, 2 * D.LANE_H + D.LANE_GAP)
    pair.hit:EnableMouse(true)
    pair.hit:SetScript("OnEnter", function() nameTip(pair) end)
    pair.hit:SetScript("OnLeave", Tbl.HideTip)
    return pair
end

local function placeLane(pair, lane, count, y, laneX, laneW)
    lane:ClearAllPoints()
    lane:SetPoint("TOPLEFT", pair, "TOPLEFT", laneX, y)
    lane:SetWidth(laneW)
    count:ClearAllPoints()
    count:SetPoint("LEFT", pair, "TOPLEFT", laneX + laneW + D.COUNT_GAP, y - D.LANE_H / 2)
    count:SetWidth(D.COUNT_W)
end

local function fillPair(pair, row, y, g)
    pair.row = row
    pair:ClearAllPoints()
    pair:SetPoint("TOPLEFT", ui.content, "TOPLEFT", 0, y)
    pair:SetWidth(g.cw)
    pair.icon:SetTexture(NS.HudBreakdown.SpellIcon(row.spellID))
    pair.name:SetText(D.Name(row))
    pair.cd:SetText(D.CooldownLine(row))
    placeLane(pair, pair.laneA, pair.countA, 0, g.laneX, g.laneW)
    placeLane(pair, pair.laneB, pair.countB, -(D.LANE_H + D.LANE_GAP), g.laneX, g.laneW)
    paint(pair.laneA, "a")
    paint(pair.laneB, "b")
    pair.countA:SetText(tostring(row.countA))
    pair.countB:SetText(ui.otherHas and tostring(row.countB) or "")
end

-- ── the cast ticks ──────────────────────────────────────────────────────────────────────────────

local function newHit()
    local h = CreateFrame("Frame", nil, ui.marks)
    h:SetSize(Timeline.MARK_HIT, D.LANE_H)
    h:EnableMouse(true)
    h:SetScript("OnEnter", function(self)
        if self.cast and ui then Tbl.SideTip(ui.frame, self, D.MarkLines(self.cast, self.label)) end
    end)
    h:SetScript("OnLeave", Tbl.HideTip)
    return h
end

local function newMark()
    local t = ui.marks:CreateTexture(nil, "OVERLAY")
    t:SetTexture(WHITE)
    t:SetWidth(Timeline.MARK_W)
    t:SetHeight(D.LANE_H)
    return t
end

-- A tick drawn now on the lanes' layer: its x and y are content coordinates as if unpanned (the
-- layer starts at the lanes' left, under the first pair).
local function putMark(d, g)
    local x, y = d.x - g.laneX, d.y + ui.sections.lanes
    d.tex:ClearAllPoints()
    d.tex:SetPoint("CENTER", ui.marks, "TOPLEFT", x, y)
    d.hit:ClearAllPoints()
    d.hit:SetPoint("CENTER", ui.marks, "TOPLEFT", x, y)
end

-- One tick at `x` along the lane whose middle is `y` (content coordinates), the lane's full height.
local function placeMark(cast, x, y, side, g)
    local color = side == "a" and Timeline.THIS or Timeline.OTHER
    local m = NS.Pool.Acquire(ui.markPool, newMark)
    m:SetVertexColor(color[1], color[2], color[3], 0.95)
    local h = NS.Pool.Acquire(ui.hitPool, newHit)
    h.cast, h.label = cast, side == "a" and ui.thisLabel or ui.otherLabel
    local d = { tex = m, hit = h, cast = cast, x = x, y = y, lane = side }
    putMark(d, g)
    ui.drawn[#ui.drawn + 1] = d
end

local function laneMarks(row, side, top, g)
    for _, t in ipairs(row[side]) do
        local x = D.MarkX(t, g.span, g.zoomW)
        if x then
            placeMark({ t = t, spellID = row.spellID, pet = row.pet }, g.laneX + x, top - D.LANE_H / 2, side, g)
        end
    end
end

-- ── the cast icons (Casts) ──────────────────────────────────────────────────────────────────────

-- An icon's hover: the client's spell tooltip, then the cast's time and its fight, beside the window.
local function iconTip(self)
    if not (self.cast and ui) then return end
    Tbl.SpellTip(ui.frame, self, self.cast.spellID, D.IconLines(self.cast, self.label, self.over))
end

local function newIcon()
    local f = CreateFrame("Frame", nil, ui.castsLayer)
    f:SetSize(Timeline.CAST_ICON, Timeline.CAST_ICON)
    f:EnableMouse(true)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints(f)
    Style.CropIcon(f.tex)
    NS.Skin.IconBorder(f, { fromSkin = true })
    f:SetScript("OnEnter", iconTip)
    f:SetScript("OnLeave", Tbl.HideTip)
    return f
end

-- An icon drawn now on the strips' layer, which starts CLIP_PAD left of the lanes, at this fight's strip.
local function putIcon(d, g)
    d.frame:ClearAllPoints()
    d.frame:SetPoint("CENTER", ui.castsLayer, "TOPLEFT", d.x - g.laneX + Timeline.CLIP_PAD, d.y + ui.sections.stripA)
end

-- Each strip's rows at this geometry: the icons' x (content coordinates, on the zoomed axis) and the
-- row each stacks onto.
local function stackOf(list, g)
    local xs = {}
    for n, c in ipairs(list) do xs[n] = g.laneX + (D.MarkX(c.t, g.span, g.zoomW) or 0) end
    local rows, count, over = D.Stack(xs, D.CAST_PITCH, D.MAX_STACK)
    return { xs = xs, rows = rows, count = count, over = over }
end

-- Row `r`'s middle, px down from the content's top: this fight's strip stacks up from its bottom row,
-- the compared fight's down from its top row (both away from each other).
local function rowMid(side, r)
    local s = ui.sections
    if side == "a" then return s.stripA + s.heightA - (r - 0.5) * D.CAST_STEP end
    return s.stripB + (r - 0.5) * D.CAST_STEP
end

local function placeStrip(side, g, label, note)
    local st, suffix = ui.strips[side], side == "a" and "A" or "B"
    paint(st.track, side)
    st.track:ClearAllPoints()
    st.track:SetPoint("TOPLEFT", ui.content, "TOPLEFT", g.laneX, -ui.sections["strip" .. suffix])
    st.track:SetSize(g.laneW, ui.sections["height" .. suffix])
    st.label:ClearAllPoints()
    st.label:SetPoint("LEFT", ui.content, "TOPLEFT", 0, -D.StripMid(ui.sections, side))
    st.label:SetText(label or "")
    st.note:ClearAllPoints()
    st.note:SetPoint("LEFT", ui.content, "TOPLEFT", g.laneX + 6, -rowMid(side, 1))
    st.note:SetText(note or "")
    st.note:SetShown(note ~= nil)
end

local function stripIcons(side, list, stack, label, g)
    for n, cast in ipairs(list) do
        local f = NS.Pool.Acquire(ui.iconPool, newIcon)
        f.cast, f.label, f.over = cast, label, stack.over[n] == true
        f.tex:SetTexture(NS.HudBreakdown.SpellIcon(cast.spellID))
        local d = { frame = f, cast = cast, x = stack.xs[n], y = -rowMid(side, stack.rows[n]), row = stack.rows[n], side = side }
        putIcon(d, g)
        ui.icons[#ui.icons + 1] = d
    end
end

-- The note a strip shows with no casts: none for one with casts.
local function stripNote(list, side)
    if #list > 0 then return nil end
    if side == "b" and not ui.other then return L["No fight to compare with"] end
    return L["No casts recorded"]
end

-- Both strips and the two headings, re-pooling every icon.
local function layoutStrips(g)
    NS.Pool.ReleaseAll(ui.iconPool, function(f) f.cast, f.label, f.over = nil, nil, nil end)
    ui.icons = {}
    ui.castsHead:ClearAllPoints()
    ui.castsHead:SetPoint("TOPLEFT", ui.content, "TOPLEFT", 0, 0)
    ui.lanesHead:ClearAllPoints()
    ui.lanesHead:SetPoint("TOPLEFT", ui.content, "TOPLEFT", 0, -ui.sections.lanesHead)
    placeStrip("a", g, L["This fight"], stripNote(ui.castsA, "a"))
    placeStrip("b", g, ui.other and D.KindLabel(ui.kind) or nil, stripNote(ui.castsB, "b"))
    stripIcons("a", ui.castsA, ui.stackA, ui.thisLabel, g)
    stripIcons("b", ui.castsB, ui.stackB, ui.otherLabel, g)
end

-- While the window is being sized: the strips' tracks to the new lane width and each icon moved along
-- its strip on the row it has (the stacking is redone on release).
local function stretchStrips(g)
    for _, side in ipairs({ "a", "b" }) do ui.strips[side].track:SetWidth(g.laneW) end
    for _, d in ipairs(ui.icons or {}) do
        d.x = g.laneX + (D.MarkX(d.cast.t, g.span, g.zoomW) or 0)
        putIcon(d, g)
    end
end

-- ── the zoom ────────────────────────────────────────────────────────────────────────────────────

local function sized(f, width, height)
    f:SetWidth(width)
    f:SetHeight(height)
end

-- The time area's clips and layers at this geometry: the strips' clip from this fight's strip to the
-- bottom of their axis, CLIP_PAD wider than the lanes at each end; the lanes' clip over the pairs; the
-- pinned axis's under the scrolling content. Each layer is the zoomed axis's width.
local function sizeClips(g)
    local s, pad = ui.sections, Timeline.CLIP_PAD
    local castsH = s.castsAxis + D.CASTS_AXIS_H - s.stripA
    local lanesH = math.max(1, #ui.rows * D.PAIR_H - D.PAIR_GAP)
    ui.castsClip:ClearAllPoints()
    ui.castsClip:SetPoint("TOPLEFT", ui.content, "TOPLEFT", g.laneX - pad, -s.stripA)
    sized(ui.castsClip, g.laneW + 2 * pad, castsH)
    sized(ui.castsLayer, g.zoomW + 2 * pad, castsH)
    ui.lanesClip:ClearAllPoints()
    ui.lanesClip:SetPoint("TOPLEFT", ui.content, "TOPLEFT", g.laneX, -s.lanes)
    sized(ui.lanesClip, g.laneW, lanesH)
    sized(ui.marks, g.zoomW, lanesH)
    ui.axisClip:ClearAllPoints()
    ui.axisClip:SetPoint("BOTTOMLEFT", ui.frame, "BOTTOMLEFT", D.PAD + g.laneX, Timeline.BOTTOM + D.BarBand(g.zoom))
    sized(ui.axisClip, g.laneW, Timeline.AXIS_H - 4)
    sized(ui.axisLayer, g.zoomW, Timeline.AXIS_H - 4)
end

-- The scrollbar along the window's bottom, the lanes' width under the pinned axis: its range the
-- zoomed axis past the lanes' width, its value the view's left edge. Shown only zoomed in.
local function placeBar(g, shown)
    local bar = ui.bar
    bar:SetShown(shown and g.zoom > 1)
    ui.thumbX, ui.thumbW = D.PAD + g.laneX + ui.pos * g.laneW, g.laneW / g.zoom
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", ui.frame, "BOTTOMLEFT", D.PAD + g.laneX, Timeline.BOTTOM)
    bar:SetWidth(g.laneW)
    bar.thumb:SetSize(ui.thumbW, D.SCROLL_H)
    ui.syncing = true
    bar:SetMinMaxValues(0, D.PosRange(g.zoom) * g.zoomW)
    bar:SetValue(ui.hoff)
    ui.syncing = false
end

-- The arrows at this pan: each live only zoomed in on drawn lanes and short of its end of the axis.
local function placeArrows(g)
    local live = g.zoom > 1 and not ui.isEmpty
    local left = live and ui.pos > 0
    local right = live and ui.pos < D.PosRange(g.zoom)
    ui.scrollLeft:SetEnabled(left)
    ui.scrollLeft:SetAlpha(left and 1 or Timeline.DIM)
    ui.scrollRight:SetEnabled(right)
    ui.scrollRight:SetAlpha(right and 1 or Timeline.DIM)
end

-- The view's left edge (`pos`) kept on the axis, and every clip panned to it together.
local function applyPan(g)
    ui.pos = D.ClampPos(ui.pos, g.zoom)
    ui.hoff = ui.pos * g.zoomW
    ui.castsClip:SetHorizontalScroll(ui.hoff)
    ui.lanesClip:SetHorizontalScroll(ui.hoff)
    ui.axisClip:SetHorizontalScroll(ui.hoff)
    placeBar(g, not ui.isEmpty)
    placeArrows(g)
end

-- The zoom level beside the controls in its step's color, and the controls dimmed at the ends.
local function placeZoom(g)
    local i = ui.zoomI or 1
    ui.zoomText:SetText(L["%sx"]:format(("%g"):format(g.zoom)))
    Style.Paint(ui.zoomText, D.ZoomColor(i))
    ui.zoomIn:SetAlpha(i < #D.ZOOMS and 1 or Timeline.DIM)
    ui.zoomOut:SetAlpha(i > 1 and 1 or Timeline.DIM)
    ui.zoomReset:SetAlpha(i > 1 and 1 or Timeline.DIM)
end

-- ── drawing ─────────────────────────────────────────────────────────────────────────────────────

-- The geometry for the window's tracked size and the zoom.
local function geometry()
    local cw, laneX, laneW = D.LaneGeometry(ui.width)
    local zoom = D.ZoomAt(ui.zoomI)
    return { cw = cw, laneX = laneX, laneW = laneW, zoom = zoom, zoomW = laneW * zoom, span = ui.span or 1 }
end

local function layoutLegend(g)
    local shown = ui.record ~= nil
    for _, key in ipairs({ "swatchA", "legendA", "swatchB", "legendB", "hint" }) do ui[key]:SetShown(shown) end
    ui.petToggle:SetShown(shown and ui.hasPet == true)
    ui.note:SetShown(shown and ui.noteText ~= nil)
    ui.note:SetWidth(g.cw)
    local top = HEADER_H + Timeline.LEGEND_H + ((shown and ui.noteText) and Timeline.NOTE_H or 0)
    ui.legendLine:ClearAllPoints()
    ui.legendLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", 1, -top)
    ui.legendLine:SetPoint("TOPRIGHT", ui.frame, "TOPRIGHT", -1, -top)
    return top + 1
end

local function newLine(layer)
    return function()
        local t = layer:CreateTexture(nil, "BACKGROUND")
        Style.Fill(t, GRID)
        t:SetWidth(1)
        return t
    end
end

local function newLabel(layer)
    return function() return Style.Text(layer, FONT.CAPTION) end
end

-- Both axes' labels and both layers' grid lines (at each tick but the first and the last), one per
-- tick at this zoom, re-pooled.
local function buildAxes(g)
    for _, pool in ipairs({ ui.axisPool, ui.castsAxisPool, ui.gridPool, ui.laneGridPool }) do NS.Pool.ReleaseAll(pool) end
    ui.ticks = D.Ticks(g.span, g.zoom)
    ui.axis, ui.castsAxis, ui.grid = {}, {}, {}
    for i, t in ipairs(ui.ticks) do
        local text = NS.Format.Length(t)
        ui.axis[i] = NS.Pool.Acquire(ui.axisPool, newLabel(ui.axisLayer))
        ui.axis[i]:SetText(text)
        ui.castsAxis[i] = NS.Pool.Acquire(ui.castsAxisPool, newLabel(ui.castsLayer))
        ui.castsAxis[i]:SetText(text)
        if i > 1 and i < #ui.ticks then
            ui.grid[#ui.grid + 1] = { t = t, casts = NS.Pool.Acquire(ui.gridPool, newLine(ui.castsLayer)),
                                      lanes = NS.Pool.Acquire(ui.laneGridPool, newLine(ui.marks)) }
        end
    end
end

-- The label at tick `i` of `n`: the first left-aligned on 0:00, the last right-aligned on the end.
local function labelPoint(i, n, side)
    local h = i == 1 and "LEFT" or (i == n and "RIGHT" or "")
    return side .. h, h == "" and "CENTER" or h
end

local function placeLabel(fs, point, justify, layer, x, y)
    fs:SetJustifyH(justify)
    fs:ClearAllPoints()
    fs:SetPoint(point, layer, "TOPLEFT", x, y)
end

-- Both axes' labels and the grid lines at this geometry. Nothing re-pooled: a resize runs it every frame.
local function placeAxes(g, shown)
    ui.axisClip:SetShown(shown)
    local s, n, pad = ui.sections, #ui.ticks, Timeline.CLIP_PAD
    local axisY, stripsH = -(Timeline.AXIS_H - 6), s.stripB + s.heightB - s.stripA
    for i, t in ipairs(ui.ticks) do
        local x = D.MarkX(t, g.span, g.zoomW)
        local point, justify = labelPoint(i, n, "BOTTOM")
        placeLabel(ui.axis[i], point, justify, ui.axisLayer, x, axisY)
        point = labelPoint(i, n, "TOP")
        placeLabel(ui.castsAxis[i], point, justify, ui.castsLayer, x + pad, -(s.castsAxis - s.stripA))
    end
    for _, line in ipairs(ui.grid) do
        local x = D.MarkX(line.t, g.span, g.zoomW)
        line.casts:ClearAllPoints()
        line.casts:SetPoint("TOPLEFT", ui.castsLayer, "TOPLEFT", x + pad, 0)
        line.casts:SetHeight(stripsH)
        line.lanes:ClearAllPoints()
        line.lanes:SetPoint("TOPLEFT", ui.marks, "TOPLEFT", x, 0)
        line.lanes:SetPoint("BOTTOMLEFT", ui.marks, "BOTTOMLEFT", x, 0)
    end
end

local function layoutRows(g)
    NS.Pool.ReleaseAll(ui.pairs, function(pair) pair.row = nil end)
    NS.Pool.ReleaseAll(ui.markPool)
    NS.Pool.ReleaseAll(ui.hitPool, function(h) h.cast, h.label = nil, nil end)
    ui.drawn = {}
    for i, row in ipairs(ui.rows) do
        local y = -ui.sections.lanes - (i - 1) * D.PAIR_H
        fillPair(NS.Pool.Acquire(ui.pairs, newPair), row, y, g)
        laneMarks(row, "a", y, g)
        laneMarks(row, "b", y - D.LANE_H - D.LANE_GAP, g)
    end
end

-- While the window is being sized: the pairs drawn now to the new lane width and each tick moved
-- along its lane, with nothing re-pooled, refilled or recolored.
local function stretchRows(g)
    for _, pair in ipairs(ui.pairs.active) do
        pair:SetWidth(g.cw)
        placeLane(pair, pair.laneA, pair.countA, 0, g.laneX, g.laneW)
        placeLane(pair, pair.laneB, pair.countB, -(D.LANE_H + D.LANE_GAP), g.laneX, g.laneW)
    end
    for _, d in ipairs(ui.drawn or {}) do
        d.x = g.laneX + (D.MarkX(d.cast.t, g.span, g.zoomW) or 0)
        putMark(d, g)
    end
end

-- The empty message for what is missing, or nil when there are rows to draw.
local function emptyText()
    if not ui.record then return L["Select a fight in the Results window to see its timeline."] end
    if not ui.hasCasts then return L["No casts recorded for this fight."] end
    if #ui.rows == 0 then return L["Only pet abilities were cast: turn on Pet abilities to see them."] end
    return nil
end

-- Everything but the lanes: the legend, the empty message, the axes and the scroll frame.
local function layoutFrame(g)
    local top = layoutLegend(g)
    local empty = emptyText()
    ui.empty:SetText(empty or "")
    ui.empty:SetShown(empty ~= nil)
    ui.isEmpty = empty ~= nil
    ui.scroll:SetShown(not ui.isEmpty)
    placeAxes(g, not ui.isEmpty)
    ui.scroll:ClearAllPoints()
    ui.scroll:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", D.PAD, -(top + 8))
    ui.viewH = math.max(1, ui.height - top - 8 - Timeline.AXIS_H - 8 - D.BarBand(g.zoom))
    ui.scroll:SetSize(g.cw, ui.viewH)
    ui.content:SetWidth(g.cw)
end

function layout()
    if not ui then return end
    local g = geometry()
    ui.laidW = g.cw
    ui.stackA, ui.stackB = stackOf(ui.castsA, g), stackOf(ui.castsB, g)
    ui.sections = D.Sections(ui.stackA.count, ui.stackB.count)
    buildAxes(g)
    layoutFrame(g)
    layoutStrips(g)
    layoutRows(g)
    ui.contentH = math.max(1, ui.sections.lanes + #ui.rows * D.PAIR_H - D.PAIR_GAP)
    ui.content:SetHeight(ui.contentH)
    sizeClips(g)
    placeZoom(g)
    placeControls(g)
    applyPan(g)
    Timeline.Scroll(0)
end

-- The cheap half of a resize (modules/Sizing.lua): the frame laid out at the tracked size, the lanes,
-- the strips and the clips stretched only when the width moved; layout re-pools them once, on release.
function resize()
    if not ui then return end
    if not ui.sections then return layout() end
    local g = geometry()
    local widthMoved = g.cw ~= ui.laidW
    ui.laidW = g.cw
    layoutFrame(g)
    if widthMoved then
        stretchStrips(g)
        stretchRows(g)
        sizeClips(g)
        placeControls(g)
    end
    applyPan(g)
    Timeline.Scroll(0)
end

-- Another fight or compare target: back to 1x, from 0:00 (the same pair redrawn keeps the view).
local function followZoom(record, other)
    local key, otherKey = record and record.id, other and other.id
    if ui.recordKey ~= key or ui.otherKey ~= otherKey then ui.zoomI, ui.pos = 1, 0 end
    ui.recordKey, ui.otherKey = key, otherKey
end

-- The followed detail's fight and its compare target.
local function followed()
    local record = pane and type(pane.Record) == "function" and pane:Record() or nil
    if not record then return nil end
    if type(pane.CompareTarget) == "function" then return record, pane:CompareTarget(true) end
    return record, D.CompareTarget(record)
end

local function fillLegend(record, other, kind)
    if not record then return end
    local this, label, note = D.Legend(record, other, kind)
    ui.legendA:SetText(this)
    ui.legendB:SetText(label)
    ui.thisLabel, ui.otherLabel, ui.noteText = this, D.OtherLabel(other, kind), note
    ui.note:SetText(note or "")
    ui.petToggle:SetChecked(Timeline.showPet)
end

-- Read the followed detail's fight and compare target, and draw them.
function draw()
    local record, other, kind = followed()
    if ui.record ~= record then ui.offset = 0 end
    followZoom(record, other)
    ui.record, ui.other, ui.kind = record, other, kind
    local built = D.Build(record, other, { showPet = Timeline.showPet })
    ui.otherHas = D.Has(other)
    ui.hasCasts = D.Has(record)
    ui.hasPet = D.HasPet(record, other)
    ui.rows, ui.castsA, ui.castsB, ui.span = built.rows, built.stripA, built.stripB, built.len
    fillLegend(record, other, kind)
    Timeline.ApplyScale()
    layout()
    debug("drawn: %d abilities", #ui.rows)
end

-- ── the public surface ──────────────────────────────────────────────────────────────────────────

--- Open the window on the detail pane `p` (the detail's Timeline button) and follow it from now on.
--- @return boolean opened
function Timeline.Open(p)
    if NS.IsStoodDown() then return false end
    pane = p
    Timeline.wanted = true
    ensureWindow()
    applyPlacement()
    ui.frame:Show()
    if ui.frame.Raise then ui.frame:Raise() end
    NS.RaiseStaticPopups()
    NS.Results.SetCovered(true)
    draw()
    return true
end

--- Close the window (its close control, the Results window closing): the Results window's cover goes.
function Timeline.Hide()
    Timeline.wanted = false
    if ui and ui.frame:IsShown() then
        hiding = true
        ui.frame:Hide()
        hiding = false
    end
    Tbl.HideTip()
    NS.Results.SetCovered(false)
end

--- Whether the window is open.
function Timeline.IsShown()
    return Timeline.wanted and ui ~= nil and ui.frame:IsShown() == true
end

--- The detail pane `p` drew a fight or changed its compare target: redraw while open on it.
function Timeline.DetailChanged(p)
    if p == pane and Timeline.IsShown() then draw() end
end

--- The pet toggle: the pet's abilities shown (`on`) or left out, for the session (never stored). The
--- zoom and the pan are kept.
function Timeline.SetShowPet(on)
    Timeline.showPet = on and true or false
    if Timeline.IsShown() then draw() end
end

-- How far across the lanes' view the cursor is (Data.CursorAt), or nil off it: the cursor in the
-- window's units less the window's left edge (read: the player may have moved it), against the lanes'
-- left and width from the tracked size.
local function cursorAt()
    if not (ui and GetCursorPosition) then return nil end
    local x = NS.Secrets.PlainNumber(GetCursorPosition())
    local scale = NS.Secrets.PlainNumber(ui.frame:GetEffectiveScale())
    local left = NS.Secrets.PlainNumber(ui.frame:GetLeft())
    if not (x and left and scale) or scale <= 0 then return nil end
    local _, laneX, laneW = D.LaneGeometry(ui.width)
    return D.CursorAt(x / scale - left, D.PAD + laneX, laneW)
end

--- One mouse-wheel notch anywhere in the window (`delta` > 0: the wheel up): up and down at any zoom;
--- with Shift, along the time axis while zoomed in (up toward 0:00), and nothing at 1x; with Ctrl
--- (ahead of Shift when both are down), a zoom step, up in and down out, about the cursor.
function Timeline.Wheel(delta)
    if IsControlKeyDown and IsControlKeyDown() then
        return Timeline.ZoomBy((delta or 0) > 0 and 1 or -1, cursorAt())
    end
    if not (IsShiftKeyDown and IsShiftKeyDown()) then return Timeline.Scroll(delta) end
    if Timeline.Zoom() > 1 then Timeline.Pan(delta) end
end

--- One vertical notch (`delta` > 0 scrolls up), clamped to the lanes.
function Timeline.Scroll(delta)
    if not ui then return end
    local top = math.max(0, (ui.contentH or 0) - (ui.viewH or 0))
    ui.offset = math.max(0, math.min(top, (ui.offset or 0) - (delta or 0) * D.PAIR_H))
    ui.scroll:SetVerticalScroll(ui.offset)
end

--- One step along the time axis (`delta` > 0 pans toward 0:00): PAN of the view, clamped to it (a
--- Shift+wheel notch, an arrow's click).
function Timeline.Pan(delta)
    if not (ui and ui.sections) then return end
    local zoom = D.ZoomAt(ui.zoomI)
    ui.pos = D.ClampPos((ui.pos or 0) - (delta or 0) * D.PAN / zoom, zoom)
    applyPan(geometry())
end

--- The scrollbar moved to `px` along the zoomed axis: the view's left edge there, every clip with it.
function Timeline.ScrollTo(px)
    if not (ui and ui.sections) then return end
    local g = geometry()
    ui.pos = D.ClampPos((tonumber(px) or 0) / g.zoomW, g.zoom)
    applyPan(g)
end

-- To zoom step `i` (clamped), about the point `at` of the way across the view (its middle without),
-- and the full layout (the icons restack).
local function setZoom(i, at)
    if not ui then return false end
    i = math.max(1, math.min(#D.ZOOMS, i))
    if i == ui.zoomI then return false end
    ui.pos = D.Rezoom(ui.pos, D.ZoomAt(ui.zoomI), D.ZoomAt(i), at)
    ui.zoomI = i
    layout()
    debug("zoom %sx", tostring(D.ZoomAt(i)))
    return true
end

--- `steps` zoom steps in (> 0) or out (< 0), about the view's middle, or the point `at` of the way
--- across the view the cursor is on (Ctrl+wheel).
--- @return boolean changed
function Timeline.ZoomBy(steps, at)
    return setZoom((ui and ui.zoomI or 1) + (steps or 0), at)
end

--- Back to 1x (the reset control).
--- @return boolean changed
function Timeline.ResetZoom()
    return setZoom(1)
end

--- The zoom now (1 before the window is built).
function Timeline.Zoom()
    return D.ZoomAt(ui and ui.zoomI or 1)
end

--- The Results window's scale on this one (it opens over that window, in its units).
function Timeline.ApplyScale()
    local scale = tonumber(NS.GetSetting("results.scale"))
    if ui and scale and scale > 0 then ui.frame:SetScale(scale) end
end

--- The Master controls' Reset position: nothing of this window is stored, so an open one goes back
--- over the Results window (reset just before it).
function Timeline.ResetPosition()
    if not Timeline.IsShown() then return end
    applyPlacement()
    layout()
end

--- Paint every corridor drawn now from CORRIDOR again; nothing while closed (the next open paints).
function Timeline.Repaint()
    if not (Timeline.IsShown() and ui.strips) then return end
    for side, st in pairs(ui.strips) do paint(st.track, side) end
    for _, pair in ipairs(ui.pairs.active) do
        paint(pair.laneA, "a")
        paint(pair.laneB, "b")
    end
end

--- The cast ticks drawn now, for the suites: { { tex, hit, cast, x, y, lane = "a" | "b" }, ... }.
function Timeline.Marks()
    return ui and ui.drawn or {}
end

--- The cast icons drawn now, for the suites: { { frame, cast, x, y, row, side = "a" | "b" }, ... }.
function Timeline.Icons()
    return ui and ui.icons or {}
end

--- Where each part of the content starts now (Data.Sections), for the suites.
function Timeline.Layout()
    return ui and ui.sections or nil
end

--- What the window does, for the diagnostics report.
function Timeline.Diagnose()
    return { shown = Timeline.IsShown(), rows = ui and #ui.rows or 0, zoom = Timeline.Zoom(), showPet = Timeline.showPet }
end

--- The built window, for the suites (nil until first opened).
function Timeline.__ui() return ui end
