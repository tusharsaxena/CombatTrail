local _, NS = ...
-- modules/Hud_States.lua — the DPS HUD's two bodies (spec §6, mockup §2): `live` (the fight in
-- progress; with nothing to pace against the HUD's state reads noBest) and `over` (the fight-over
-- card). Each is built on first show into the HUD's content frame and answers Update(view), and the
-- live body SetLive(live); modules/Hud.lua owns the shell, decides which body shows and builds the
-- view. Adapted from DPS Race @045f479 (modules/Hud_States.lua) without its race: no idle, armed,
-- Stop! or waiting body, no race length, no late-cast flags, no buttons in the bodies (the title
-- bar's controls are the HUD's acts).
--
-- THE STACK, top down, each part switched by its `hud.layout.*` key: the clock, the target line, the
-- Damage and DPS boxes, on the over card the chips, then the "Damage profile" section (its heading,
-- the pace bar directly under it when there is a fight to pace against, then the damage chart,
-- modules/Hud_Chart.lua) and the "Spell breakdown" section (modules/Hud_Breakdown.lua). The look is
-- DPS Race's (v0.2 Task B2): each heading in FONT.SECTION on Style.SECTION_H with HEAD_GAP of clear
-- space over it, the pace bar on its PACE_H line under the profile heading, and the clock at DPS
-- Race's single-clock size (ClockSize).
-- Every position is a constant offset worked out from the parts shown and the configured sizes
-- (modules/Hud_Appearance.lua); Update answers the stack's height (body.height), which the shell
-- sizes an auto-grow window from. No body reads the size or position of anything that has displayed
-- a meter value; the chips measure their own text (GetStringWidth on a label that only ever holds
-- plain copy), never a value.
--
-- THE ROWS' WINDOW (v0.2 Task B3, plan decision D9). The view carries `bars` (`hud.bars`, or the
-- grip's count while it is dragged) and, in fixed mode, `fitH`: the content's height. The rows shown
-- are `bars`, fewer when fitH leaves no room for them (the over card's chips), and the wheel scrolls
-- the rest in both modes: the offset is clamped to the spells past the window, and the heading's
-- note counts them ("1-5 of 12") beside a thin indicator in the gutter. States.FixedStack is the
-- stack a fixed window reserves, from the configuration alone: every part its layout switch shows,
-- the boxes' pet row and the pace line included whether or not this fight has them, so a pet that
-- arrives mid-fight or a board with no best never moves the window. Every count is plain (the `#` of
-- the meter's own Lua arrays) and every height config.
--
-- SECRETS. The live body hands each opaque meter value to NS.Format.Number and the result straight
-- to SetText, and to the pace bar's, the chart's and the rows' StatusBars: no concatenation, no
-- comparison but the nil test spec §3 allows. The pet's figure is a label and a value side by side,
-- never one joined string. The over card's values are plain (the after-combat read, or the stored
-- record), except the chart's columns, which keep the totals captured in combat.

local States = {}
NS.HudStates = States

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT
local Secrets = NS.Secrets

-- The HUD's palette, every entry a live skin color (modules/Style.lua): the body text and its dim
-- gray, the header gold, and the meaning hues (core/SkinSetup.lua's owner tokens).
local C = {
    text  = Style.Tok("ct.text"),
    dim   = Style.Tok("ct.dim"),
    gold  = Style.GOLD,
    amber = Style.Tok("ct.caution"),
    red   = Style.Tok("sem.statusBad"),
    green = Style.Tok("ct.ahead"),
    info  = Style.Tok("ct.info"),
}
States.COLORS = C

-- The flat box a figure stands in: a faint wash under a faint edge (the skin's Card, D-3).
local BOX = { bg = "list.boxDim", border = "ct.box.border" }

-- The stack's pitches. The clock's and the figures' heights follow their configured sizes.
local CLOCK_PAD = 12
local TARGET_H = 18
local KPI_CHROME = 26          -- a box's caption and padding around its figure
local KPI_PAD, KPI_CAPTION_H = 5, 14
local GAP = 8
local CHIP_HEIGHT, CHIP_GAP = 18, 5
-- A section's heading line (FONT.SECTION), and the clear space over it: the shared SECTION_GAP less
-- the GAP the block above already leaves (DPS Race's HEAD_GAP, 6).
local SECTION_H = Style.SECTION_H
local HEAD_GAP = Style.SECTION_GAP - GAP
-- The gap between the pace bar's line and the plot under it.
local PACE_GAP = 4
-- The clock draws its stored size scaled as DPS Race's single clock does (BIG / CLOCK_PAIR, 40 / 26):
-- the composed Font size row tops out at 32, so the stored 26 is what draws DPS Race's 40.
local CLOCK_SCALE = 40 / 26
-- The bodies' width when the shell hands none: the default 260 less PAD on both sides.
local WIDTH = 236
-- The scroll indicator in the gutter right of the rows: its width, its gap from them, its shortest thumb.
local THUMB_W, THUMB_GAP, THUMB_MIN = 2, 4, 6
States.GAP = GAP
States.HEAD_GAP, States.PACE_GAP, States.SECTION_H = HEAD_GAP, PACE_GAP, SECTION_H

--- The size the clock draws at for a stored `hud.clock.fontSize`, whole points.
--- @param size number
--- @return number
function States.ClockSize(size)
    return math.floor((tonumber(size) or 0) * CLOCK_SCALE + 0.5)
end
local DASH = "\226\128\148"   -- "no figure"

local function appearance() return NS.HudAppearance end

-- ── widgets ─────────────────────────────────────────────────────────────────────────────────────

--- A flat box through the skin's Card, its slots remapped to `tokens` (default BOX).
local function card(parent, tokens)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    NS.Skin.Card(f, { tokens = tokens or BOX })
    return f
end
States.Card = card

-- The width a plain label takes: its own measurement (it never holds a meter value), else an
-- estimate from its length, for a client or a harness that cannot answer yet.
local function textWidth(fs, s)
    local w = fs.GetStringWidth and fs:GetStringWidth()
    if type(w) == "number" and w > 0 then return w end
    return #s * 6
end

--- A figure in a box: a small caption over a large value (LootHistory's Insights card), and a row
--- under the value for the pet's figure, shown only while there is one: a "Pet" label and the
--- value beside it, two strings, so a secret value is never joined to text. The value's face is
--- the `hud.figures` block's.
local function kpi(parent, label, tip)
    local f = card(parent)
    local k = { frame = f, petRow = false }
    k.label = Style.Text(f, FONT.CAPTION, nil, "CENTER")
    k.label:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
    k.label:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -7)
    k.label:SetText(label)
    k.value = Style.PlainText(f, FONT.FIGURE, "CENTER")
    k.petLabel = Style.Text(f, FONT.CAPTION, nil, "RIGHT")
    k.petLabel:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -2, KPI_PAD)
    k.petLabel:SetText(L["Pet"])
    k.petValue = Style.Text(f, FONT.CAPTION, C.green, "LEFT")
    k.petValue:SetPoint("BOTTOMLEFT", f, "BOTTOM", 2, KPI_PAD)
    NS.HudTips.Attach(f, tip)
    return k
end

-- Show or hide the box's pet row; the value moves up over it and the box grows by its height.
local function setPetRow(k, on)
    on = on and true or false
    k.petLabel:SetShown(on)
    k.petValue:SetShown(on)
    if k.petRow == on and k.placed then return end
    k.petRow, k.placed = on, true
    local y = KPI_PAD + (on and KPI_CAPTION_H or 0)
    k.value:ClearAllPoints()
    k.value:SetPoint("BOTTOMLEFT", k.frame, "BOTTOMLEFT", 8, y)
    k.value:SetPoint("BOTTOMRIGHT", k.frame, "BOTTOMRIGHT", -8, y)
end

-- Two boxes side by side at `y`, halves by anchor (no width needed), `h` high.
local function placePair(a, b, parent, y, h)
    a.frame:ClearAllPoints()
    a.frame:SetHeight(h)
    a.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    a.frame:SetPoint("TOPRIGHT", parent, "TOP", -4, y)
    b.frame:ClearAllPoints()
    b.frame:SetHeight(h)
    b.frame:SetPoint("TOPLEFT", parent, "TOP", 4, y)
    b.frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
end

-- ── chips ───────────────────────────────────────────────────────────────────────────────────────

local function newChip(parent)
    local f = Style.FlatBox(parent)
    f:SetHeight(CHIP_HEIGHT)
    f.label = Style.Text(f, FONT.TEXT, C.text, "CENTER")
    f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if not self.tip or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.tip, Style.Rgb("gtip.value"))
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return f
end

local Chips = {}
Chips.__index = Chips

local function chips(parent)
    return setmetatable({ parent = parent, y = 0, pool = NS.Pool.New(), width = WIDTH, shown = {}, lines = 0 },
        Chips)
end

--- Lay out `list` ({ text, color, tip }) left to right from `y`, wrapping at the body's width.
function Chips:Set(list, y)
    NS.Pool.ReleaseAll(self.pool)
    self.shown, self.lines, self.y = {}, 0, y or self.y
    local x, row, parent = 0, self.y, self.parent
    for i, item in ipairs(list or {}) do
        local chip = NS.Pool.Acquire(self.pool, function() return newChip(parent) end)
        local s, c = item.text, item.color or C.text
        chip.label:SetText(s)
        Style.Paint(chip.label, c)
        Style.TintBox(chip, c, Style.CHIP_EDGE_A)
        chip.tip, chip.text = item.tip, s
        local w = math.floor(textWidth(chip.label, s) + 14)
        if x > 0 and x + w > self.width then x, row = 0, row - CHIP_HEIGHT - CHIP_GAP end
        self.lines = math.floor((self.y - row) / (CHIP_HEIGHT + CHIP_GAP) + 0.5) + 1
        chip:SetWidth(w)
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", parent, "TOPLEFT", x, row)
        chip:Show()
        x = x + w + CHIP_GAP
        self.shown[i] = chip
    end
end

--- The chips' height, the GAP under them included; 0 with none. Config only.
function Chips:Height()
    local n = self.lines
    if n == 0 then return 0 end
    return n * CHIP_HEIGHT + (n - 1) * CHIP_GAP + GAP
end

--- The chip texts drawn now, in order (the suites read these).
function Chips:Texts()
    local out = {}
    for i, chip in ipairs(self.shown) do out[i] = chip.text end
    return out
end

-- ── the over card's chips ───────────────────────────────────────────────────────────────────────

-- What each FIGHT_SKIPPED reason says on the card (modules/Recorder.lua's four).
local SKIP_TEXT = {
    filtered = "Not saved: filtered out",
    lost     = "Not saved: the meter lost this fight",
    unknown  = "Not saved: no readable character",
}

--- The "Not saved" chip's words for `reason`; with `showReason` false, the bare "Not saved".
--- @param reason string|nil  "short" | "filtered" | "lost" | "unknown"
--- @param showReason boolean
--- @param minLength number|nil  the recording filter's minimum, for "short"
--- @return string
function States.SkipText(reason, showReason, minLength)
    if not showReason then return L["Not saved"] end
    if reason == "short" then return L["Not saved: shorter than %d s"]:format(tonumber(minLength) or 0) end
    local key = SKIP_TEXT[reason]
    if key then return L[key] end
    return L["Not saved"]
end

--- The over card's chips (spec §6): a New best (with its gain over the best before it), then Saved,
--- or Not saved and why. Nothing while the recorder has not answered yet.
--- @param v table  the HUD's view
--- @return table list  { { text, color, tip }, ... }
function States.OverChips(v)
    local list = {}
    if v.newBest then
        local text = L["New best"]
        if type(v.delta) == "number" then text = L["New best %s"]:format(NS.Format.SignedPct(v.delta)) end
        list[#list + 1] = { text = text, color = C.gold, tip = NS.Compat.ForClient({ "retail" })
            and L["Your best DPS on this boss or target, for this character and spec."]
            or L["Your best DPS on this boss or target, for this character and talent tree."] }
    end
    if v.saved == true then
        list[#list + 1] = { text = L["Saved"], color = C.green, tip = L["Stored in your fight history."] }
    elseif v.saved == false then
        list[#list + 1] = { text = States.SkipText(v.skipReason, v.showSkipReason, v.minLength), color = C.amber,
                            tip = L["Every fight is tracked live; only the ones that pass History > Recording filters are stored."] }
    end
    return list
end

-- ── the shared top of both bodies ───────────────────────────────────────────────────────────────

local function newBody(parent, key)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()
    return { key = key, frame = f, w = {}, parts = {}, height = 0, offset = 0 }
end

-- The clock, the target line and the two boxes every body has.
local function buildTop(body, dpsLabel, tips)
    local f, w = body.frame, body.w
    w.clock = Style.PlainText(f, FONT.FIGURE, "CENTER")
    w.clockZone = CreateFrame("Frame", nil, f)
    w.clockZone:SetAllPoints(w.clock)
    NS.HudTips.Attach(w.clockZone, "clock")
    w.target = Style.Text(f, FONT.TEXT, C.dim, "CENTER")
    w.damage = kpi(f, L["Damage"], tips[1])
    w.dps = kpi(f, dpsLabel, tips[2])
end

--- The clock's line and a box's height (its pet row left out) for the configured fonts.
--- @return number clockH, number kpiH
function States.TopSizes()
    local A = appearance()
    return States.ClockSize(A.Font("clock").size) + CLOCK_PAD, A.Font("figures").size + KPI_CHROME
end

-- The top's look, once per Appearance stamp: the clock's and the figures' blocks, the boxes, and on
-- the over card the DPS figure's color.
local function restyleTop(body)
    local A = appearance()
    if body.topStamp == A.stamp then return end
    body.topStamp = A.stamp
    local w = body.w
    local clock, figures = A.Font("clock"), A.Font("figures")
    clock.size = States.ClockSize(clock.size)
    A.ApplyFont(w.clock, clock)
    A.ApplyFont(w.damage.value, figures)
    local over
    if body.key == "over" then
        local r, g, b, a = A.Swatch("figures", "overColor")
        over = { r = r, g = g, b = b, a = a }
    end
    A.ApplyFont(w.dps.value, figures, over)
    A.ApplyBox(w.damage.frame)
    A.ApplyBox(w.dps.frame)
    body.clockH, body.kpiH = States.TopSizes()
end

-- Lay the top out for the view's layout toggles; answers the y (positive, down) under it.
local function placeTop(body, v)
    restyleTop(body)
    local f, w, layout = body.frame, body.w, v.layout or {}
    local y = 0
    w.clock:SetShown(layout.clock ~= false)
    w.clockZone:SetShown(layout.clock ~= false)
    if layout.clock ~= false then
        w.clock:ClearAllPoints()
        w.clock:SetPoint("TOP", f, "TOP", 0, -4)
        y = y + body.clockH
    end
    w.target:SetShown(layout.target ~= false)
    if layout.target ~= false then
        w.target:ClearAllPoints()
        w.target:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        w.target:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
        y = y + TARGET_H
    end
    local figures = layout.figures ~= false
    w.damage.frame:SetShown(figures)
    w.dps.frame:SetShown(figures)
    if figures then
        local h = body.kpiH + (v.hasPet and KPI_CAPTION_H or 0)
        placePair(w.damage, w.dps, f, -y, h)
        y = y + h + GAP
    end
    return y
end

local function setValue(fs, value)
    if value == nil then fs:SetText(DASH) else fs:SetText(NS.Format.Number(value)) end
end

-- ── the extras: pace bar, damage chart, spell rows ──────────────────────────────────────────────

-- The parts the profile section is built from, on first need: the chart (its heading is the
-- section's) and the pace bar.
local function profileParts(body)
    local parts = body.parts
    if not parts.chart then parts.chart = NS.HudChart.New(body.frame) end
    if not parts.pace then parts.pace = NS.HudChart.NewPace(body.frame) end
    return parts.chart, parts.pace
end

-- Whether the view's pace bar and chart show (each by its layout switch and the view carrying it).
local function profileShown(v)
    local layout = v.layout or {}
    return layout.pace ~= false and v.pace ~= nil and v.paceView ~= nil,
           layout.chart ~= false and v.chartView ~= nil
end

-- The "Damage profile" section at `y` (DPS Race's placeStack): HEAD_GAP of clear space, the heading,
-- the pace bar directly under it when the view carries one (and the layout shows it), then the plot
-- and its time labels when the view carries a chart. The heading stays over the pace bar with the
-- plot off, and goes with both off. Answers the y under the section.
local function placeProfile(body, v, y)
    local pv, view = v.paceView, v.chartView
    local paceOn, chartOn = profileShown(v)
    body.paceShown, body.chartShown = paceOn, chartOn
    if not (paceOn or chartOn) then
        if body.parts.chart then body.parts.chart:SetShown(false) end
        if body.parts.pace then body.parts.pace:SetShown(false) end
        return y
    end
    local chart, pace = profileParts(body)
    local width = v.width or WIDTH
    local paceLine = paceOn and (NS.HudChart.PACE_H + PACE_GAP) or 0
    local top = y + HEAD_GAP
    chart:SetParts(true, chartOn)
    local h = chart:Place(body.frame, -top, width, paceLine)
    if chartOn then
        chart:Draw(view)
    else
        -- No plot, no Draw: the note names the pace bar alone (it has no caption of its own).
        chart:SetNote(L["vs best pace"])
        h = SECTION_H + paceLine
    end
    pace:SetShown(paceOn)
    if paceOn then
        NS.HudTips.Attach(pace.bar, body.key == "over" and "overPace" or "pace")
        pace:Place(body.frame, -(top + SECTION_H), width)
        pace:Set(pv.lo, pv.hi, pv.player, pv.pet, pv.withPet)
    end
    return top + h + GAP
end

-- The spell rows' frame, heading, list and scroll indicator, built on first need. The frame takes
-- the wheel, which scrolls the list whenever there are more spells than rows.
local function spellsPart(body)
    local s = body.parts.spells
    if s then return s end
    s = {}
    s.title = Style.Text(body.frame, FONT.SECTION)
    s.title:SetText(L["Spell breakdown"])
    s.note = Style.Text(body.frame, FONT.CAPTION, nil, "RIGHT")
    s.frame = CreateFrame("Frame", nil, body.frame)
    s.list = NS.HudBreakdown.New(s.frame)
    s.track = body.frame:CreateTexture(nil, "ARTWORK")
    Style.Fill(s.track, "ct.scroll.track")
    s.thumb = body.frame:CreateTexture(nil, "OVERLAY")
    Style.Fill(s.thumb, "ct.scroll.thumb")
    s.frame:EnableMouseWheel(true)
    s.frame:SetScript("OnMouseWheel", function(_, delta)
        body.offset = math.max(0, (body.offset or 0) - (tonumber(delta) or 0))
        if body.onScroll then body.onScroll() end
    end)
    NS.HudTips.Attach(s.frame, body.key == "over" and "overSpells" or "liveSpells")
    body.parts.spells = s
    return s
end

local function setSpellsShown(s, on)
    s.title:SetShown(on)
    s.note:SetShown(on)
    s.frame:SetShown(on)
    if not on then
        s.track:Hide()
        s.thumb:Hide()
    end
end

--- The height of the "Spell breakdown" section holding `n` rows: HEAD_GAP, the heading, the rows and
--- the GAP under them. Config only.
--- @param n number
--- @return number
function States.SpellsHeight(n)
    return HEAD_GAP + SECTION_H + NS.HudBreakdown.Height(n) + GAP
end

-- How many rows show of `total`, and from where: `v.bars`, fewer where the fixed window's room
-- (`v.fitH`) under the heading at `y` holds fewer, the offset clamped to the spells past them.
local function window(body, total, v, y)
    local visible = math.max(0, math.floor(tonumber(v.bars) or 1))
    if v.fitH then
        visible = math.min(visible, NS.HudBreakdown.Capacity(v.fitH - y - SECTION_H - GAP))
    end
    local maxOffset = math.max(0, total - visible)
    body.offset = math.max(0, math.min(body.offset or 0, maxOffset))
    body.visible, body.total = visible, total
    return math.min(visible, total - body.offset), body.offset
end

-- The heading's note: what the rows are, and which of them show while the wheel has more.
local function spellsNote(body, base, drawn)
    if drawn < 1 or body.total <= body.visible then return base end
    return base .. " \194\183 " .. L["%d-%d of %d"]:format(body.offset + 1, body.offset + drawn, body.total)
end

-- The thin scroll indicator right of the rows `h` high: shown while spells are past the window, its
-- thumb as long as the share in view and as far down as the offset. Plain counts and config only.
local function placeThumb(s, body, width, top, h)
    local maxOffset = body.total - body.visible
    local on = maxOffset > 0 and h > 0
    s.track:SetShown(on)
    s.thumb:SetShown(on)
    if not on then return end
    local thumbH = math.max(THUMB_MIN, math.floor(h * body.visible / body.total + 0.5))
    local dy = math.floor((h - thumbH) * body.offset / maxOffset + 0.5)
    s.track:ClearAllPoints()
    s.track:SetPoint("TOPLEFT", body.frame, "TOPLEFT", width + THUMB_GAP, -top)
    s.track:SetSize(THUMB_W, h)
    s.thumb:ClearAllPoints()
    s.thumb:SetPoint("TOPLEFT", body.frame, "TOPLEFT", width + THUMB_GAP, -(top + dy))
    s.thumb:SetSize(THUMB_W, thumbH)
end

-- The "Spell breakdown" section at `y`: HEAD_GAP of clear space, its heading, then the live read's
-- rows (player then pet) or the over card's plain ones; answers the y under them.
local function placeSpells(body, v, y)
    local on = (v.layout or {}).spells ~= false
    local s = (on or body.parts.spells) and spellsPart(body) or nil
    if not on then
        if s then setSpellsShown(s, false) end
        return y
    end
    setSpellsShown(s, true)
    local width = v.width or WIDTH
    y = y + HEAD_GAP
    s.title:ClearAllPoints()
    s.title:SetPoint("TOPLEFT", body.frame, "TOPLEFT", 0, -y)
    s.note:ClearAllPoints()
    s.note:SetPoint("TOPRIGHT", body.frame, "TOPLEFT", width, -y)
    local Breakdown = NS.HudBreakdown
    local drawn, base
    if body.key == "over" then
        local list = v.finalSpells or {}
        local n, offset = window(body, #list, v, y)
        drawn, base = s.list:ShowFinal(list, v.finalTotal, n, offset), L["% of total"]
    else
        local n, offset = window(body, Breakdown.LiveCount(v.live), v, y)
        drawn, base = s.list:ShowLive(v.live, n, offset), L["live order"]
    end
    s.note:SetText(spellsNote(body, base, drawn))
    local h = Breakdown.Height(drawn)
    s.frame:ClearAllPoints()
    s.frame:SetPoint("TOPLEFT", body.frame, "TOPLEFT", 0, -(y + SECTION_H))
    s.frame:SetSize(width, math.max(1, h))
    placeThumb(s, body, width, y + SECTION_H, h)
    return y + SECTION_H + h + GAP
end

-- Everything under the top, from `y`; answers the stack's height.
local function placeExtras(body, v, y)
    body.stackTop = y
    y = placeProfile(body, v, y)
    y = placeSpells(body, v, y)
    return y
end

-- The top a fixed window reserves: the clock, the target line and the boxes with the pet's row.
local function reservedTop(layout)
    local clockH, kpiH = States.TopSizes()
    local y = 0
    if layout.clock ~= false then y = y + clockH end
    if layout.target ~= false then y = y + TARGET_H end
    if layout.figures ~= false then y = y + kpiH + KPI_CAPTION_H + GAP end
    return y
end

--- The stack a fixed window reserves for `bars` rows, from the configuration alone (the shell adds
--- its chrome): every part `layout` shows, the boxes' pet row always, the pace line whenever the
--- layout shows it and the HUD paces (`paceable`), and the spell section's heading over `bars` rows.
--- The live body with a pet, a pace and at least `bars` spells fills it exactly.
--- @param layout table|nil  `hud.layout`
--- @param bars number
--- @param paceable boolean  `hud.paceAgainst` is not "none"
--- @return number
function States.FixedStack(layout, bars, paceable)
    layout = layout or {}
    local y = reservedTop(layout)
    local paceOn, chartOn = layout.pace ~= false and paceable == true, layout.chart ~= false
    local paceLine = paceOn and (NS.HudChart.PACE_H + PACE_GAP) or 0
    if chartOn then
        y = y + HEAD_GAP + NS.HudChart.BlockHeight(NS.HudChart.PlotHeight(), paceLine) + GAP
    elseif paceOn then
        y = y + HEAD_GAP + SECTION_H + paceLine + GAP
    end
    if layout.spells ~= false then y = y + States.SpellsHeight(bars) end
    return y
end

-- ── LIVE ────────────────────────────────────────────────────────────────────────────────────────

local Builders = {}

function Builders.live(parent)
    local body = newBody(parent, "live")
    buildTop(body, L["DPS \194\183 Live"], { "liveDamage", "liveDps" })

    function body.Update(self, v)
        setPetRow(self.w.damage, v.hasPet)
        setPetRow(self.w.dps, v.hasPet)
        self.w.dps.petLabel:SetShown(false)
        self.w.dps.petValue:SetShown(false)
        local y = placeTop(self, v)
        self.w.clock:SetText(NS.Format.Clock(v.clock))
        self.w.target:SetText(v.targetLine or "")
        self:SetLive(v.live)
        self.height = placeExtras(self, v, y)
    end

    --- The live figures: opaque values, straight to the formatter and the labels.
    function body.SetLive(self, live)
        local player = type(live) == "table" and live.player or nil
        local pet = type(live) == "table" and live.pet or nil
        setValue(self.w.damage.value, player and player.total)
        setValue(self.w.dps.value, player and player.dps)
        setValue(self.w.damage.petValue, pet and pet.total)
    end
    return body
end

-- ── OVER ────────────────────────────────────────────────────────────────────────────────────────

-- The card's plain figures: the merged damage and DPS (spec §6: after combat everything merges in
-- plain Lua), and the pet's damage when it had any. Dashes for a fight the meter lost.
local function overFigures(w, v)
    local merged = v.final and v.final.merged or nil
    local pet = v.final and v.final.pet or nil
    setValue(w.damage.value, merged and Secrets.PlainNumber(merged.total))
    setValue(w.dps.value, merged and Secrets.PlainNumber(merged.dps))
    setValue(w.damage.petValue, pet and Secrets.PlainNumber(pet.total))
end

function Builders.over(parent)
    local body = newBody(parent, "over")
    buildTop(body, L["DPS"], { "overDamage", "overDps" })
    body.w.chips = chips(body.frame)

    function body.Update(self, v)
        local w = self.w
        setPetRow(w.damage, v.hasPet)
        setPetRow(w.dps, v.hasPet)
        w.dps.petLabel:SetShown(false)
        w.dps.petValue:SetShown(false)
        local y = placeTop(self, v)
        w.clock:SetText(NS.Format.Clock(v.clock))
        w.target:SetText(v.targetLine or "")
        overFigures(w, v)
        w.chips.width = v.width or w.chips.width
        w.chips:Set(States.OverChips(v), -y)
        self.height = placeExtras(self, v, y + w.chips:Height())
    end
    return body
end

--- Build one body into `parent`.
--- @param key string  "live" | "over"
--- @param parent table
--- @return table|nil body  { key, frame, w, parts, height, stackTop, paceShown, chartShown, Update(view),
---   SetLive(live)? }
function States.Build(key, parent)
    local builder = Builders[key]
    if not builder then return nil end
    return builder(parent)
end
