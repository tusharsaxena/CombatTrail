-- tests/test_hud_static.lua — the DPS HUD as one window with static sizes (owner feedback items 7, 12
-- and 16, 2026-11-25, plan item CLF-2). The HUD and the docked log are one frame whose height is the
-- sum of its sections (the title bar, the clock and target, the boxes, one reserved status line, Damage
-- profile, Spell breakdown, the Combat Log and the footer), so nothing inside a fight moves it: only
-- the log opening or closing, a rows setting or the grip. The chart stays on the fight-over card in
-- every state: saved or not, the log open or closed, docked or detached (item 7: the slices store of a
-- skipped fight was forgotten at FIGHT_SKIPPED, so the card that followed had no columns to draw).

local T = _G.CT_TEST
local test, assertEqual, assertTrue =
    T.test, T.assertEqual, T.assertTrue
local H = dofile(T.root .. "/tests/hud_fixture.lua")(T)

local ENEMIES = { { name = "Angry Boar", creatureID = 1985, damage = 40000 } }

local function fightOf(n, duration)
    local spells = {}
    for i = 1, n do spells[i] = { id = 1000 + i, dmg = 1000 * (n - i + 1), dps = 25 * (n - i + 1) } end
    return { damage = 40000, dps = 1000, duration = duration or 40, spells = spells, enemies = ENEMIES }
end

-- Record the sizes the code sets on `f` (the kit's frames answer no geometry unless armed).
local function track(f)
    rawset(f, "SetSize", function(self, w, h) rawset(self, "__w", w); rawset(self, "__h", h) end)
    rawset(f, "SetWidth", function(self, w) rawset(self, "__w", w) end)
    rawset(f, "SetHeight", function(self, h) rawset(self, "__h", h) end)
    return f
end

local function setLog(inst, key, value)
    inst.NS.SetByPath("sequence." .. key, value)
end

-- A fight live from t0, its window tracked, with `heights` noting the window's height at each step.
local function fight(inst, meter, id, session, t0, len, heights)
    local Hud = inst.NS.Hud
    H.start(inst, meter, id, session, t0)
    track(Hud.Frame())
    Hud.Refresh()
    heights[#heights + 1] = Hud.Frame().__h
    local t = t0 + 1.5
    while t <= t0 + len do
        H.run(inst, t)
        heights[#heights + 1] = Hud.Frame().__h
        t = t + 0.25
    end
    H.finish(inst, t0, len)
    heights[#heights + 1] = Hud.Frame().__h
end

local function allSame(list, msg)
    for i = 2, #list do assertEqual(list[i], list[1], msg .. " (step " .. i .. ")") end
end

-- ── item 7: the chart after the fight ───────────────────────────────────────────────────────────

-- The over card's chart for a fight of `len` seconds, the log as `log` says ("closed", "docked",
-- "detached"); `len` under the recording minimum makes it a fight that is not saved.
local function overChart(len, log)
    local inst, meter, Hud = H.fresh()
    if log == "closed" then setLog(inst, "drawer.shown", false)
    else
        setLog(inst, "drawer.shown", true)
        setLog(inst, "home", log)
    end
    local heights = {}
    fight(inst, meter, 2, fightOf(6, len), 100, len, heights)
    return inst, Hud, heights
end

for _, log in ipairs({ "closed", "docked", "detached" }) do
    for _, saved in ipairs({ true, false }) do
        local len = saved and 40 or 6
        test(("hud static: the chart stays on the card after a %s fight, the log %s"):format(
            saved and "saved" or "not saved", log), function()
            local inst, Hud, heights = overChart(len, log)
            assertEqual(Hud.State(), "over")
            local v, body = Hud.View(), H.body(Hud, "over")
            assertEqual(v.saved, saved, "the recorder's answer")
            assertTrue(v.chartView ~= nil, "the card has its columns")
            assertTrue(body.chartShown == true, "the chart shows on the card")
            local chart = body.parts.chart
            local NS = inst.NS
            local plot = NS.HudChart.PlotHeight()
            assertEqual(chart.plotH, plot, "the plot keeps its configured height")
            assertEqual(chart.blockH, NS.HudChart.BlockHeight(plot, NS.HudChart.PACE_H + NS.HudStates.PACE_GAP)
                - (v.pace == nil and (NS.HudChart.PACE_H + NS.HudStates.PACE_GAP) or 0), "the whole block")
            allSame(heights, "the window's height never moved in or after the fight")
            assertEqual(Hud.Frame().__h, Hud.FixedHeight())
        end)
    end
end

test("hud static: a skipped fight's slices are held for its card, and the next skip lets them go", function()
    local inst, meter, Hud = H.fresh()
    local S = inst.NS.Slices
    local heights = {}
    fight(inst, meter, 2, fightOf(3, 6), 100, 6, heights)
    local first = Hud.View().fight.id
    assertTrue(S.Get(first) ~= nil, "held for the card")
    fight(inst, meter, 3, fightOf(3, 6), 200, 6, heights)
    assertTrue(S.Get(first) == nil, "the second skip lets the first go")
    assertTrue(S.Get(Hud.View().fight.id) ~= nil)
    assertTrue(Hud.View().chartView ~= nil)
end)

-- ── item 12 and 16: one window, one height ──────────────────────────────────────────────────────

-- The grip dragged to `w` x `h` and released (the library reads the released size off the frame).
local function gripTo(Hud, M, w, h, hold)
    local f = Hud.Frame()
    f.resizeGrip:__fire("OnMouseDown", "LeftButton")
    M.__now = M.__now + 1 / 60
    f:__fire("OnSizeChanged", w, h)
    if hold then return end
    f:__setGeom(w, h)
    f.resizeGrip:__fire("OnMouseUp")
end

-- A HUD with the log docked open, live on a fight of `n` spells.
local function docked(n)
    local inst, meter, Hud = H.fresh()
    setLog(inst, "drawer.shown", true)
    H.start(inst, meter, 2, fightOf(n or 8), 100)
    track(Hud.Frame())
    Hud.Refresh()
    return inst, meter, Hud
end

test("hud static: the default window is 390 wide and exactly tall enough for 5 bars and 10 log rows", function()
    local inst, _, Hud = docked(8)
    local NS = inst.NS
    assertEqual(NS.defaults.profile.hud.bars, 5)
    assertEqual(NS.defaults.profile.sequence.drawer.rows, 10)
    assertEqual(NS.defaults.profile.sequence.drawer.shown, true, "the log shows by default (item 1)")
    local f = Hud.Frame()
    assertEqual(f.__w, 390)
    assertEqual(#H.body(Hud, "live").parts.spells.list:Rows(), 5, "five bars")
    assertEqual(NS.HudLog.__ui().table.nRows, 10, "ten log rows")
    local chrome = NS.Style.TITLE_BAR_H + 10 + NS.FOOTER_HEIGHT + 8
    local stack = NS.HudStates.FixedStack(NS.GetSetting("hud.layout"), 5, true)
    assertEqual(f.__h, chrome + stack + NS.HudLog.Height(), "the sum of the sections, nothing spare")
    assertEqual(NS.HudLog.Height(), NS.HudLog.GAP + NS.HudLog.HEAD_H + NS.LogTable.Height(10),
        "no chips row by default (R4-CT-04)")
end)

test("hud static: the status line is reserved, so the card's chips never move Damage profile", function()
    local inst, _, Hud = docked(8)
    local live = H.body(Hud, "live").stackTop
    H.finish(inst, 100, 40)
    local over = H.body(Hud, "over")
    assertTrue(#over.w.chips:Texts() >= 1, "the card's chips")
    assertEqual(over.stackTop, live, "Damage profile where it was in the fight")
    assertEqual(live, H.body(Hud, "live").stackTop)
end)

test("hud static: only the log's open and close, a rows setting or the grip move the height", function()
    local inst, _, Hud = docked(8)
    local NS, f = inst.NS, Hud.Frame()
    local open = f.__h
    setLog(inst, "drawer.shown", false)
    assertEqual(f.__h, open - (NS.HudLog.GAP + NS.HudLog.HEAD_H + NS.LogTable.Height(10)),
        "closed: the log's sections given back")
    setLog(inst, "drawer.shown", true)
    assertEqual(f.__h, open, "open again")
    setLog(inst, "drawer.rows", 12)
    assertEqual(f.__h, open + 2 * NS.LogTable.RowH(), "two more log rows")
    setLog(inst, "home", "detached")
    assertEqual(f.__h, Hud.FixedHeight(), "detached: the HUD alone")
    assertEqual(NS.HudLog.Height(), 0)
end)

test("hud static: with the log docked open the grip's extra height goes to the log's rows, the bars kept", function()
    local inst, _, Hud = docked(12)
    local NS, M, f = inst.NS, inst.mocks, Hud.Frame()
    local rowH = NS.LogTable.RowH()
    local h = f.__h
    local b = f.__resizeBounds
    assertEqual(b[2], h - 7 * rowH, "the least: three log rows")
    assertEqual(b[4], h + 10 * rowH, "the most: twenty")
    gripTo(Hud, M, 420, h + 3 * rowH + 5, true)
    assertEqual(NS.HudLog.Rows(), 13, "held: the drawer shows the rows the drag holds")
    assertEqual(#H.body(Hud, "live").parts.spells.list:Rows(), 5, "the bars stay")
    f:__setGeom(420, h + 3 * rowH + 5)
    f.resizeGrip:__fire("OnMouseUp")
    assertEqual(NS.db.profile.sequence.drawer.rows, 13, "stored on release")
    assertEqual(NS.db.profile.hud.bars, 5, "the bars untouched")
    assertEqual(NS.db.profile.hud.width, 420, "the width to every section")
    assertEqual(f.__h, h + 3 * rowH, "snapped to whole rows")
    assertEqual(NS.HudLog.__ui().table.nRows, 13)
    setLog(inst, "drawer.shown", false)
    local closed = f.__h
    gripTo(Hud, M, 420, closed + 2 * 20 + 3)
    assertEqual(NS.db.profile.hud.bars, 7, "closed: the height goes to the bars")
    assertEqual(NS.db.profile.sequence.drawer.rows, 13)
end)

test("hud static: a whole fight with the log open, saved, then skipped, never moves the window", function()
    local inst, meter = H.fresh()
    setLog(inst, "drawer.shown", true)
    local heights = {}
    fight(inst, meter, 2, fightOf(8, 40), 100, 40, heights)
    fight(inst, meter, 3, fightOf(3, 6), 200, 6, heights)
    allSame(heights, "the one height")
end)
