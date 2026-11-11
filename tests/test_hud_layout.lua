-- tests/test_hud_layout.lua — the DPS HUD's look against DPS Race's (v0.2 Task B2, R:hud-look#1-#8):
-- both headings in FONT.SECTION on Style.SECTION_H with HEAD_GAP of clear space over them, the pace
-- bar directly under the "Damage profile" heading and over the plot (placeProfile), the clock in the
-- skin's HUD face at DPS Race's single-clock size, and DPS Race's width, insets, row height and font
-- and plot height. The live body and the fight-over card stack the same. Every offset read here is
-- one the code set (a region's first anchor), never a size read back off a value-bearing region.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse
local H = dofile(T.root .. "/tests/hud_fixture.lua")(T)

local ENEMIES = { { name = "Angry Boar", creatureID = 1985, damage = 40000 } }
local FIGHT = { damage = 40000, dps = 1000, duration = 40,
                spells = { { id = 11366, dmg = 10000, dps = 250 }, { id = 133, dmg = 30000, dps = 750 } },
                enemies = ENEMIES }

local HEAD_GAP, SECTION_H, PACE_LINE, GAP = 6, 22, 12 + 4, 8
local PLOT_H, RESERVE, AXIS_H = 80, 13, 12

-- `region`'s y offset (its first anchor's), down from the body's top.
local function y(region) return region.__points[1][5] end

-- A frame's anchors and size, recorded the way the paint recorder records a region's: the kit's frames
-- answer no geometry unless a test arms them (tests/_kit/mock_base.lua), so the suite spies on the
-- setters production calls. What is read back is only what the code set.
local function track(f)
    rawset(f, "__points", {})
    rawset(f, "ClearAllPoints", function(self) rawset(self, "__points", {}) end)
    rawset(f, "SetPoint", function(self, ...)
        local list = rawget(self, "__points")
        list[#list + 1] = { ... }
    end)
    rawset(f, "SetSize", function(self, w, h) rawset(self, "__w", w); rawset(self, "__h", h) end)
    rawset(f, "SetWidth", function(self, w) rawset(self, "__w", w) end)
    rawset(f, "SetHeight", function(self, h) rawset(self, "__h", h) end)
    return f
end

-- Track every frame the stack places in `body`, then redraw (a restyle and a render).
local function redraw(Hud, body)
    for _, part in ipairs({ body.parts.chart and body.parts.chart.plot, body.parts.pace and body.parts.pace.bar,
                            body.parts.spells and body.parts.spells.frame }) do
        if part then track(part) end
    end
    Hud.Apply()
    Hud.Refresh()
end

-- A stored best (fight 1), then fight 2 live against it, no pet.
local function paced()
    local inst, meter, Hud = H.fresh()
    H.whole(inst, meter, 1, FIGHT, 10, 40)
    H.start(inst, meter, 2, FIGHT, 100)
    H.tick(inst, 101.25, 104)
    return inst, meter, Hud
end

-- Damage profile with its note, the pace bar directly under it, the plot and its time labels, then
-- Spell breakdown over the rows: each heading FONT.SECTION with HEAD_GAP of clear space over it.
local function assertStack(inst, body)
    local F = inst.NS.Style.FONT
    local chart, pace, spells = body.parts.chart, body.parts.pace, body.parts.spells
    local top = body.stackTop
    assertEqual(chart.title.__text, "Damage profile")
    assertEqual(chart.title.__template, F.SECTION, "the Results detail's heading role")
    assertEqual(spells.title.__text, "Spell breakdown")
    assertEqual(spells.title.__template, F.SECTION)
    assertTrue(chart.title:IsShown() and spells.title:IsShown())
    assertEqual(y(chart.title), -(top + HEAD_GAP), "HEAD_GAP of clear space over the heading")
    -- The note on the heading's line: its bottom edge on the heading's, so the small caption lines up
    -- with the larger heading's text (owner, 2026-11-11).
    local np = chart.note.__points[1]
    assertEqual(np[1], "BOTTOMRIGHT")
    assertEqual(np[2], chart.title, "the note on the heading's line")
    assertEqual(np[3], "BOTTOMLEFT")
    assertEqual(np[5], 0)
    assertEqual(y(pace.bar), y(chart.title) - SECTION_H - 2, "the pace bar directly under the heading")
    assertEqual(pace.bar.__h, 12 - 4, "the bar 8px tall on its 12px line")
    assertEqual(y(chart.plot), y(pace.bar) + 2 - PACE_LINE, "the plot under the pace bar")
    assertEqual(chart.frameH, PLOT_H + RESERVE, "the plot frame: its 80px and the icons' row on top")
    assertEqual(y(chart.axis[1]), y(chart.plot) - PLOT_H - RESERVE - 2, "the time labels under the plot")
    assertEqual(y(spells.title), y(chart.axis[1]) - AXIS_H - GAP - HEAD_GAP, "Spell breakdown under the labels")
    assertEqual(spells.note.__points[1][2], spells.title, "its note on its heading's line")
    assertEqual(spells.note.__points[1][1], "BOTTOMRIGHT")
    assertEqual(spells.note.__points[1][5], 0)
    assertEqual(y(spells.frame), y(spells.title) - SECTION_H, "the rows under their heading")
end

-- ── the stack ───────────────────────────────────────────────────────────────────────────────────

test("hud layout: the live body stacks the top, Damage profile, the pace bar, the plot, Spell breakdown", function()
    local inst, _, Hud = paced()
    assertEqual(Hud.State(), "live")
    local body = H.body(Hud, "live")
    assertTrue(body.paceShown == true and body.chartShown == true)
    redraw(Hud, body)
    assertEqual(body.stackTop, 52 + 18 + 46 + GAP, "the clock's 40 + 12, the target line, the boxes, the gap")
    assertStack(inst, body)
    assertEqual(body.parts.chart.note.__text, "vs best pace")
end)

test("hud layout: the fight-over card stacks the same under its chips", function()
    local inst, _, Hud = paced()
    H.finish(inst, 100, 40)
    assertEqual(Hud.State(), "over")
    local body = H.body(Hud, "over")
    assertTrue(body.paceShown == true and body.chartShown == true)
    redraw(Hud, body)
    assertEqual(body.stackTop, 52 + 18 + 46 + GAP + body.w.chips:Height(), "under the chips")
    assertStack(inst, body)
end)

test("hud layout: with the plot off the heading stays over the pace bar", function()
    local inst, _, Hud = paced()
    local body = H.body(Hud, "live")
    redraw(Hud, body)
    H.setHud(inst, "layout.chart", false)
    Hud.Refresh()
    local chart, pace, spells = body.parts.chart, body.parts.pace, body.parts.spells
    assertTrue(chart.title:IsShown(), "the heading stays with the pace bar")
    assertFalse(chart.plot:IsShown())
    assertFalse(chart.axis[1]:IsShown())
    assertEqual(chart.note.__text, "vs best pace", "the note names the pace bar")
    assertEqual(y(chart.title), -(body.stackTop + HEAD_GAP))
    assertEqual(y(pace.bar), y(chart.title) - SECTION_H - 2)
    assertEqual(y(spells.title), y(pace.bar) + 2 - PACE_LINE - GAP - HEAD_GAP, "Spell breakdown under the bar")
    H.setHud(inst, "layout.pace", false)
    Hud.Refresh()
    assertFalse(chart.title:IsShown(), "nothing to head")
    assertFalse(pace.bar:IsShown())
    assertEqual(y(spells.title), -(body.stackTop + HEAD_GAP), "Spell breakdown right under the boxes")
end)

test("hud layout: with nothing to pace against the plot sits right under its heading", function()
    local inst, meter, Hud = H.fresh()
    H.start(inst, meter, 1, FIGHT, 10)
    H.tick(inst, 11.25, 14)
    local body = H.body(Hud, "live")
    redraw(Hud, body)
    local chart = body.parts.chart
    assertFalse(body.paceShown == true)
    assertTrue(chart.title:IsShown() and chart.plot:IsShown())
    assertEqual(y(chart.title), -(body.stackTop + HEAD_GAP))
    assertEqual(y(chart.plot), y(chart.title) - SECTION_H, "no pace line under the heading")
    assertEqual(chart.note.__text, "no best yet")
end)

-- ── the sizes ───────────────────────────────────────────────────────────────────────────────────

test("hud layout: the defaults are DPS Race's sizes", function()
    local inst = H.fresh()
    local NS = inst.NS
    local d = NS.defaults.profile.hud
    assertEqual(d.width, 260)
    assertEqual(NS.Hud.MIN_WIDTH, 260)
    assertEqual(d.clock.fontFromSkin, true, "the clock in the skin's HUD face, as DPS Race's")
    assertEqual(d.clock.fontSize, 26, "DPS Race's stored clock size (the composed slider tops out at 32)")
    assertEqual(d.clock.fontFlags, "", "the mono role: never outlined")
    assertEqual(NS.HudStates.ClockSize(26), 40, "drawn at DPS Race's single-clock 40")
    assertEqual(d.spells.rowHeight, 18)
    assertEqual(d.spells.fontSize, 10)
    assertEqual(d.spells.fontShadow, true)
    assertEqual(d.chart.height, 80)
    assertEqual(NS.HudChart.HEAD_H, NS.Style.SECTION_H)
    assertEqual(NS.HudChart.PACE_H, 12)
end)

test("hud layout: the window is 260 wide on DPS Race's insets, its height the stack's", function()
    local inst, _, Hud = paced()
    -- An auto-grow window is the stack's height (a fixed one is tests/test_hud_sizing.lua's).
    H.setHud(inst, "sizeMode", "auto")
    local NS = inst.NS
    local f, ui = Hud.Frame(), Hud.__ui()
    local body = H.body(Hud, "live")
    track(f)
    track(ui.content)
    redraw(Hud, body)
    assertEqual(f.__w, 260)
    local headerH, footerH = NS.Style.TITLE_BAR_H, 20
    local tl, br = ui.content.__points[1], ui.content.__points[2]
    assertEqual(tl[1], "TOPLEFT")
    assertEqual(tl[4], 12, "PAD 12")
    assertEqual(tl[5], -(headerH + 10), "the content's top: the title bar + 10")
    assertEqual(br[1], "BOTTOMRIGHT")
    assertEqual(br[4], -12)
    assertEqual(br[5], footerH + 8, "the content's bottom: the footer + 8")
    assertEqual(Hud.View().width, 260 - 24, "the bodies' width: 236")
    assertEqual(f.__h, headerH + 10 + body.height + footerH + 8)
    local rows = body.parts.spells.list:Rows()
    local drawn = #rows
    local profile = HEAD_GAP + SECTION_H + PACE_LINE + PLOT_H + RESERVE + 2 + AXIS_H + GAP
    local spells = HEAD_GAP + SECTION_H + NS.HudBreakdown.Height(drawn) + GAP
    assertEqual(body.height, body.stackTop + profile + spells, "the stack, part by part")
end)

test("hud layout: a spell row is 18 high in a 10 point face, its icon 16", function()
    local _, _, Hud = paced()
    local row = track(H.body(Hud, "live").parts.spells.list:Rows()[1])
    Hud.Apply()
    Hud.Refresh()
    assertEqual(row.__h, 18)
    assertEqual(row.iconSize, 16)
    assertEqual(select(2, row.name:GetFont()), 10)
end)

test("hud layout: the clock draws DPS Race's 40 in the skin's face", function()
    local inst, _, Hud = paced()
    local clock = H.body(Hud, "live").w.clock
    assertEqual(select(2, clock:GetFont()), 40)
    local lib = inst.mocks.LibStub("LibKa0s-Media-1.0", true)
    assertEqual((clock:GetFont()), lib.Font("CombatTrail", inst.NS.Skin.Resolve("hud.font", nil, true)))
end)

test("hud layout: the settings' width floor is the HUD's", function()
    local inst = H.fresh()
    local NS = inst.NS
    local found = NS.FindSchemaRow("hud.width")
    assertTrue(found ~= nil, "the hud.width row")
    assertEqual(found.min, NS.Hud.MIN_WIDTH)
end)
