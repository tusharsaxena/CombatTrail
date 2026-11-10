local _, NS = ...
-- modules/Results_TimelineMarks.lua — the ability timeline's cast marks (v0.2 plan Task D1; DPS Race
-- has the same module, DpsRace#21): what a cast draws in the By ability lanes, and the art every cast
-- icon of the window shares. Its members land on NS.ResultsTimeline (modules/Results_Timeline.lua,
-- which reaches them at call time); the built window is reached through Timeline.__ui() at call
-- time, and the pure geometry and words are modules/Results_TimelineData.lua's.
--
-- THE MODE (`results.timelineMarks`, a stored profile setting: History > Results window > Ability
-- timeline, and the two words at the right of the By ability heading line, which write it through
-- NS.SetByPath; modules/Results.lua hears the write and calls Timeline.Redraw). "icon", the default:
-- each cast is its ability's LANE_ICON icon centered on its time in the lane, with the Casts icon's
-- tooltip (the client's spell tooltip, then *Cast at m:ss* and its fight). A lane is 16 px, so icons
-- in one lane do not stack: casts closer than an icon overlap. The icons are pooled siblings at one
-- frame level, so which of two overlapping icons draws on top (and takes the pointer) is the client's,
-- not the cast order (docs/known-limitations.md). "tick": the thin
-- tick the lane's full height (MARK_W) with its wider hover frame and the tick's tooltip
-- (Data.MarkLines), as before. A redraw keeps the zoom, the pan and the scroll.
--
-- THE CASTER COLORS: a player's cast PALETTE.PLAYER_LINE, a pet's PALETTE.PET_LINE (core/Constants.lua:
-- the spell rows' two hues lifted for 1-2 px lines). A tick is tinted at MARK_A; an icon, in the lanes
-- and in the Casts strips alike, sits on a 1 px edge of its caster's color (a BORDER texture 2 px
-- larger, the gear view's way) in place of the skin's icon outline. They are meaning colors
-- (skinning-§9: the color is the information), the same under every skin; each fight's identity
-- stays on its corridors, its counts and the legend.
--
-- THE CLIP. The lanes' clip reaches CLIP_PAD past the lanes at each end, as the strips' does, in both
-- modes (one geometry path), so an icon at 0:00 or at the end shows whole: half an icon (7) is under
-- the pad (8), which is under the gaps to the name cell and the counts (10).
--
-- PLAIN DATA ONLY: the stored casts (t, spellID, pet); positions come from the constants and the
-- tracked size, never read back off a frame.

local Timeline = NS.ResultsTimeline

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT
local D = NS.ResultsTimelineData
local Tbl = NS.ResultsTable
local C = Tbl.COLORS
local PALETTE = NS.Constants.PALETTE

local WHITE = "Interface\\Buttons\\WHITE8x8"   -- a cast's tick, tinted

Timeline.MARKS_PATH = "results.timelineMarks"
Timeline.MARK_MODES = { icon = true, tick = true }
Timeline.LANE_ICON = Timeline.CAST_ICON   -- 14: a px clear of the 16 px lane at each side
Timeline.MARK_A = 0.95                    -- a tick's alpha
-- The palette's own entries, passed by reference to Style.Fill and read, never written.
Timeline.PLAYER_LINE = PALETTE.PLAYER_LINE
Timeline.PET_LINE = PALETTE.PET_LINE
Timeline.CASTER = { player = Timeline.PLAYER_LINE, pet = Timeline.PET_LINE }
-- The two words on the By ability heading line: each a TOGGLE_W box, TOGGLE_GAP apart.
Timeline.TOGGLE_W = 40
Timeline.TOGGLE_GAP = 4

local function win() return Timeline.__ui() end

--- A cast's caster color: PET_LINE for a pet's, PLAYER_LINE for the player's.
--- @param pet boolean|nil
--- @return table  { r, g, b, a }
function Timeline.CasterColor(pet)
    return pet and Timeline.CASTER.pet or Timeline.CASTER.player
end

--- How By ability draws a cast: "tick" when the setting says so, else "icon".
function Timeline.MarkMode()
    return NS.GetSetting(Timeline.MARKS_PATH) == "tick" and "tick" or "icon"
end

--- Store the mode (the heading line's words): through the seam, whose write redraws an open window.
--- @param mode string  "icon" | "tick"
--- @return boolean stored
function Timeline.SetMarkMode(mode)
    return (NS.SetByPath(Timeline.MARKS_PATH, mode))
end

-- ── a cast icon (the Casts strips' and the lanes') ──────────────────────────────────────────────

-- An icon's hover: the client's spell tooltip, then the cast's time and its fight, beside the window
-- level with the icon.
local function iconTip(self)
    local u = win()
    if not (self.cast and u) then return end
    Tbl.SpellTip(u.frame, self, self.cast.spellID, D.IconLines(self.cast, self.label, self.over))
end

--- A cast icon on `layer`: a plain frame `size` px (it takes the mouse for its tooltip) holding the
--- art, cropped (Style.CropIcon), over its caster edge, `size` + 2 px (Timeline.PaintCast colors it).
--- @return table frame  { tex, edge }; set `cast`, `label` and `over` for its tooltip
function Timeline.NewCastIcon(layer, size)
    local f = CreateFrame("Frame", nil, layer)
    f:SetSize(size, size)
    f:EnableMouse(true)
    f.edge = f:CreateTexture(nil, "BORDER")
    f.edge:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.edge:SetSize(size + 2, size + 2)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints(f)
    Style.CropIcon(f.tex)
    f:SetScript("OnEnter", iconTip)
    f:SetScript("OnLeave", Tbl.HideTip)
    return f
end

--- Paint a cast icon for `cast` ({ t, spellID, pet }): its ability's art and its caster's edge, on
--- every acquire (a pooled icon changes cast and caster).
function Timeline.PaintCast(f, cast)
    f.tex:SetTexture(NS.HudBreakdown.SpellIcon(cast.spellID))
    Style.Fill(f.edge, Timeline.CasterColor(cast.pet), 1)
end

-- ── the lanes' marks ────────────────────────────────────────────────────────────────────────────

-- A tick's hover frame; its tooltip beside the window, level with the tick.
local function newHit()
    local h = CreateFrame("Frame", nil, win().marks)
    h:SetSize(Timeline.MARK_HIT, D.LANE_H)
    h:EnableMouse(true)
    h:SetScript("OnEnter", function(self)
        local u = win()
        if self.cast and u then Tbl.SideTip(u.frame, self, D.MarkLines(self.cast, self.label)) end
    end)
    h:SetScript("OnLeave", Tbl.HideTip)
    return h
end

local function newTick()
    local t = win().marks:CreateTexture(nil, "OVERLAY")
    t:SetTexture(WHITE)
    t:SetWidth(Timeline.MARK_W)
    t:SetHeight(D.LANE_H)
    return t
end

local function newLaneIcon() return Timeline.NewCastIcon(win().marks, Timeline.LANE_ICON) end

local function anchor(region, layer, x, y)
    if not region then return end
    region:ClearAllPoints()
    region:SetPoint("CENTER", layer, "TOPLEFT", x, y)
end

--- A mark drawn now on the lanes' layer, which starts CLIP_PAD left of the lanes: its x and y are
--- content coordinates as if unpanned. Every move of it (a draw, a grip drag) comes through here.
function Timeline.PutMark(d, g)
    local u = win()
    local x, y = d.x - g.laneX + Timeline.CLIP_PAD, d.y + u.sections.lanes
    anchor(d.frame, u.marks, x, y)
    anchor(d.tex, u.marks, x, y)
    anchor(d.hit, u.marks, x, y)
end

local function placeTick(u, cast, label)
    local m = NS.Pool.Acquire(u.markPool, newTick)
    local c = Timeline.CasterColor(cast.pet)
    m:SetVertexColor(c[1], c[2], c[3], Timeline.MARK_A)
    local h = NS.Pool.Acquire(u.hitPool, newHit)
    h.cast, h.label = cast, label
    return { tex = m, hit = h, kind = "tick" }
end

local function placeIcon(u, cast, label)
    local f = NS.Pool.Acquire(u.laneIconPool, newLaneIcon)
    f.cast, f.label, f.over = cast, label, nil
    Timeline.PaintCast(f, cast)
    return { frame = f, kind = "icon" }
end

--- Every mark back to its pool, and the mode read for the draw that follows.
function Timeline.ReleaseMarks()
    local u = win()
    NS.Pool.ReleaseAll(u.markPool)
    NS.Pool.ReleaseAll(u.hitPool, function(h) h.cast, h.label = nil, nil end)
    NS.Pool.ReleaseAll(u.laneIconPool, function(f) f.cast, f.label, f.over = nil, nil, nil end)
    u.drawn = {}
    u.markMode = Timeline.MarkMode()
end

--- One row's marks on lane `side` ("a" this fight's, "b" the compared fight's), the lane's top at
--- `top` (content coordinates): an icon or a tick per cast, in the mode ReleaseMarks read. The lane
--- comes from `side`, never from a color.
function Timeline.LaneMarks(row, side, top, g)
    local u = win()
    local label = side == "a" and u.thisLabel or u.otherLabel
    local place = u.markMode == "tick" and placeTick or placeIcon
    for _, t in ipairs(row[side]) do
        local x = D.MarkX(t, g.span, g.zoomW)
        if x then
            local cast = { t = t, spellID = row.spellID, pet = row.pet }
            local d = place(u, cast, label)
            d.cast, d.x, d.y, d.lane = cast, g.laneX + x, top - D.LANE_H / 2, side
            Timeline.PutMark(d, g)
            u.drawn[#u.drawn + 1] = d
        end
    end
end

-- ── the mode's two words ────────────────────────────────────────────────────────────────────────

local function toggleTip(self)
    local tip = GameTooltip
    if not tip then return end
    tip:SetOwner(self, "ANCHOR_TOP")
    tip:SetText(self.tip, Style.Rgb("gtip.value"))
    tip:Show()
end

local function newToggle(u, mode, text, tip)
    local b = CreateFrame("Button", nil, u.content)
    b:SetSize(Timeline.TOGGLE_W, Timeline.CONTROL)
    b:SetFrameLevel(u.content:GetFrameLevel() + 10)
    b.label = Style.Text(b, FONT.TEXT, C.dim, "CENTER")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.label:SetText(text)
    b.tip = tip
    b:SetScript("OnClick", function() Timeline.SetMarkMode(mode) end)
    b:SetScript("OnEnter", toggleTip)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

--- The lanes' pools and the two words (the window's build).
function Timeline.BuildMarks(u)
    u.markPool, u.hitPool, u.laneIconPool = NS.Pool.New(), NS.Pool.New(), NS.Pool.New()
    u.marksTicks = newToggle(u, "tick", L["Ticks"], L["Show each cast in By ability as a thin line"])
    u.marksIcons = newToggle(u, "icon", L["Icons"], L["Show each cast in By ability as its ability's icon"])
    u.marksIcons:SetPoint("RIGHT", u.marksTicks, "LEFT", -Timeline.TOGGLE_GAP, 0)
end

--- The two words at the right of the By ability heading line, on the lanes' right edge at this
--- geometry, the mode drawn now in gold.
function Timeline.PlaceMarks(u, g)
    u.marksTicks:ClearAllPoints()
    u.marksTicks:SetPoint("TOPRIGHT", u.content, "TOPLEFT", g.laneX + g.laneW, -u.sections.lanesHead)
    local ticks = (u.markMode or Timeline.MarkMode()) == "tick"
    Style.Paint(u.marksTicks.label, ticks and Style.GOLD or C.dim)
    Style.Paint(u.marksIcons.label, ticks and C.dim or Style.GOLD)
end
