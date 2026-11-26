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

test("hud static: the default window is 260 wide and exactly tall enough for 5 bars and 5 sequence rows", function()
    local inst, _, Hud = docked(8)
    local NS = inst.NS
    assertEqual(NS.defaults.profile.hud.bars, 5)
    assertEqual(NS.defaults.profile.sequence.drawer.rows, 5, "five each (owner feedback round 4, R4-CT-07)")
    assertEqual(NS.defaults.profile.sequence.drawer.shown, true, "the log shows by default (item 1)")
    local f = Hud.Frame()
    assertEqual(f.__w, 260)
    assertEqual(#H.body(Hud, "live").parts.spells.list:Rows(), 5, "five bars")
    assertEqual(NS.HudLog.__ui().table.nRows, 5, "five sequence rows")
    local chrome = NS.Style.TITLE_BAR_H + 10 + NS.FOOTER_HEIGHT + 8
    local stack = NS.HudStates.FixedStack(NS.GetSetting("hud.layout"), 5, true)
    assertEqual(f.__h, chrome + stack + NS.HudLog.Height(), "the sum of the sections, nothing spare")
    assertEqual(NS.HudLog.Height(), NS.HudLog.GAP + NS.HudLog.HEAD_H + NS.LogTable.Height(5),
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
    assertEqual(f.__h, open - (NS.HudLog.GAP + NS.HudLog.HEAD_H + NS.LogTable.Height(5)),
        "closed: the log's sections given back")
    setLog(inst, "drawer.shown", true)
    assertEqual(f.__h, open, "open again")
    setLog(inst, "drawer.rows", 12)
    assertEqual(f.__h, open + 7 * NS.LogTable.RowH(), "seven more log rows")
    setLog(inst, "home", "detached")
    assertEqual(f.__h, Hud.FixedHeight(), "detached: the HUD alone")
    assertEqual(NS.HudLog.Height(), 0)
end)

-- ── R4-CT-07: the grip splits the height between the spells and the sequence ─────────────────────

-- A spell row's pitch at the defaults (18 high, 2 apart).
local SP = 20

local function pair(b, l) return b .. "/" .. l end

test("hud static: Hud.SplitFor shrinks the larger side first, the sequence on a tie, never under 3 a side", function()
    local inst, _, Hud = docked(12)
    local NS = inst.NS
    local rowH = NS.LogTable.RowH()
    local h = Hud.HeightFor(5, 5)
    assertEqual(Hud.Frame().__h, h, "the default height holds 5/5")
    local function at(x) return pair(Hud.SplitFor(x, 5, 5)) end
    assertEqual(at(h), "5/5")
    assertEqual(at(h - 1), "5/4", "a pixel short: the sequence gives first on a tie")
    assertEqual(at(h - rowH), "5/4")
    -- The owner's walk: 5/5 -> 5/4 -> 4/4 -> 4/3 -> 3/3.
    assertEqual(at(Hud.HeightFor(4, 4)), "4/4")
    assertEqual(at(Hud.HeightFor(4, 3)), "4/3")
    assertEqual(at(Hud.HeightFor(3, 3)), "3/3")
    assertEqual(at(0), "3/3", "never under 3 a side")
    assertEqual(NS.db.profile.hud.bars, 5, "pure: nothing stored")
    assertEqual(NS.db.profile.sequence.drawer.rows, 5)
end)

test("hud static: Hud.SplitFor grows the smaller side, the spells on a tie, to 15 spells then 20 rows", function()
    local inst, _, Hud = docked(12)
    local rowH = inst.NS.LogTable.RowH()
    local h = Hud.HeightFor(5, 5)
    local function at(x) return pair(Hud.SplitFor(x, 5, 5)) end
    assertEqual(at(h + SP), "6/5", "the spells first on a tie")
    assertEqual(at(h + SP + rowH), "6/6", "then the smaller side")
    assertEqual(at(h + SP - 1), "5/5", "a row that does not fit is not taken")
    assertEqual(at(Hud.HeightFor(15, 15)), "15/15")
    assertEqual(at(Hud.HeightFor(15, 18)), "15/18", "the spells at 15: only the sequence grows")
    assertEqual(at(1e6), "15/20", "and stops at 20")
    -- An unequal pair from an older profile converges: the larger side gives first.
    assertEqual(pair(Hud.SplitFor(Hud.HeightFor(5, 9), 5, 10)), "5/9")
    assertEqual(pair(Hud.SplitFor(Hud.HeightFor(5, 5), 5, 10)), "5/5")
    assertEqual(pair(Hud.SplitFor(Hud.HeightFor(10, 10), 5, 10)), "10/10", "growing evens it too")
end)

test("hud static: docked open, the grip moves both, from 3/3 to 15/20, and its release writes both counts", function()
    local inst, _, Hud = docked(12)
    local NS, M, f = inst.NS, inst.mocks, Hud.Frame()
    local rowH = NS.LogTable.RowH()
    local b = f.__resizeBounds
    assertEqual(b[2], Hud.HeightFor(3, 3), "the least: 3 spell rows and 3 sequence rows")
    assertEqual(b[2], f.__h - 2 * SP - 2 * rowH)
    assertEqual(b[4], Hud.HeightFor(15, 20), "the most")
    gripTo(Hud, M, 300, Hud.HeightFor(5, 4) + 3, true)
    assertEqual(NS.HudLog.Rows(), 4, "held: four sequence rows")
    assertEqual(#H.body(Hud, "live").parts.spells.list:Rows(), 5, "five spell rows")
    M.__now = M.__now + 1 / 60
    f:__fire("OnSizeChanged", 300, Hud.HeightFor(4, 4))
    assertEqual(NS.HudLog.Rows(), 4)
    assertEqual(#H.body(Hud, "live").parts.spells.list:Rows(), 4, "the walk from the grip-down pair: 4/4")
    assertEqual(NS.db.profile.sequence.drawer.rows, 5, "nothing stored while held")
    f:__setGeom(300, Hud.HeightFor(4, 4))
    f.resizeGrip:__fire("OnMouseUp")
    assertEqual(NS.db.profile.hud.bars, 4, "both counts written on release")
    assertEqual(NS.db.profile.sequence.drawer.rows, 4)
    assertEqual(NS.db.profile.hud.width, 300)
    assertEqual(f.__h, Hud.HeightFor(4, 4), "snapped to the pair")
    assertEqual(NS.HudLog.__ui().table.nRows, 4)
    gripTo(Hud, M, 300, Hud.HeightFor(5, 5) + SP + 1)
    assertEqual(pair(NS.db.profile.hud.bars, NS.db.profile.sequence.drawer.rows), "6/5", "grown from 4/4")
    gripTo(Hud, M, 300, 10)
    assertEqual(pair(NS.db.profile.hud.bars, NS.db.profile.sequence.drawer.rows), "3/3", "the least")
end)

test("hud static: closed or detached, the grip moves only the spell rows, never under 3", function()
    local inst, _, Hud = docked(12)
    local NS, M, f = inst.NS, inst.mocks, Hud.Frame()
    setLog(inst, "drawer.shown", false)
    assertEqual(f.__resizeBounds[2], Hud.HeightFor(3, 0), "the least: 3 spell rows")
    assertEqual(f.__resizeBounds[4], Hud.HeightFor(15, 0))
    gripTo(Hud, M, 300, Hud.HeightFor(7, 0) + 3)
    assertEqual(NS.db.profile.hud.bars, 7, "closed: the height goes to the spell rows")
    assertEqual(NS.db.profile.sequence.drawer.rows, 5, "the sequence's rows untouched")
    gripTo(Hud, M, 300, 10)
    assertEqual(NS.db.profile.hud.bars, 3, "never under 3")
    setLog(inst, "drawer.shown", true)
    setLog(inst, "home", "detached")
    gripTo(Hud, M, 300, Hud.HeightFor(6, 0))
    assertEqual(NS.db.profile.hud.bars, 6, "detached: the spell rows")
    assertEqual(NS.db.profile.sequence.drawer.rows, 5)
end)

test("hud static: with Spell breakdown off the grip moves only the sequence's rows", function()
    local inst, _, Hud = docked(12)
    local NS, M, f = inst.NS, inst.mocks, Hud.Frame()
    H.setHud(inst, "layout.spells", false)
    assertEqual(f.__resizeBounds[2], Hud.HeightFor(5, 3), "the least: 3 sequence rows")
    assertEqual(f.__resizeBounds[4], Hud.HeightFor(5, 20))
    gripTo(Hud, M, 300, Hud.HeightFor(5, 8) + 2)
    assertEqual(NS.db.profile.sequence.drawer.rows, 8, "the sequence's rows")
    assertEqual(NS.db.profile.hud.bars, 5, "the spell rows untouched")
end)

test("hud static: a whole fight with the log open, saved, then skipped, never moves the window", function()
    local inst, meter = H.fresh()
    setLog(inst, "drawer.shown", true)
    local heights = {}
    fight(inst, meter, 2, fightOf(8, 40), 100, 40, heights)
    fight(inst, meter, 3, fightOf(3, 6), 200, 6, heights)
    allSame(heights, "the one height")
end)
