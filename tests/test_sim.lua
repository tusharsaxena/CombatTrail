-- tests/test_sim.lua — modules/Sim.lua, `/kct sim [scenario]` (spec §8 "Sim mode", plan Task 5.1): a
-- made-up 45 s fight played in real time through the lanes, the HUD's live view and its fight-over
-- card, then the Results window on the sim's fight beside the sample history. Each scenario reaches
-- its card and its chips; nothing reaches the bus's fight messages or SavedVariables; the step
-- session parks the fight until its first step; the preview's end conditions end it.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local function fresh()
    local inst = T.load{ mutate = function(m) installPaint(m) end }
    inst.mocks.__now = 1000
    return inst.NS, inst.mocks
end

-- Start scenario `key` and release the parked fight (the stepper's first step).
local function sim(NS, key)
    assertTrue(NS.Preview.Start({ mode = "sim", scenario = key }), key .. " started")
    assertEqual(NS.Sim.Diagnose().phase, "parked", "the step session parks the fight")
    assertTrue(NS.Sim.Unpark())
end

-- Let `secs` pass a beat at a time, running the timers due.
local function play(M, secs)
    for _ = 1, math.floor(secs / 0.25 + 0.5) do
        M.__now = M.__now + 0.25
        M.__fireTimers()
    end
end

-- Count the fight messages the bus carries meanwhile: a sim sends none.
local function listen(NS)
    local heard = { n = 0 }
    local bus = NS.NewBusTarget()
    for _, name in ipairs({ "FIGHT_STARTED", "FIGHT_TICK", "FIGHT_ENDED", "FIGHT_SAVED", "FIGHT_SKIPPED" }) do
        bus:RegisterMessage(NS.MSG[name], function() heard.n = heard.n + 1 end)
    end
    return heard
end

local function untouched(NS)
    assertEqual(next(NS.db.global.fights or {}), nil, "a sim fight reached the store")
    assertEqual(next(NS.db.global.loadouts or {}), nil, "a sim loadout was stored")
end

test("sim newbest ends with New best chip", function()
    local NS, M = fresh()
    local heard = listen(NS)
    sim(NS, "newbest")
    assertEqual(NS.Preview.Mode(), "sim")
    play(M, 10)
    assertEqual(NS.Hud.State(), "live", "the live view, paced against the board's best")
    assertTrue(NS.Hud.__ui().simStrip ~= nil and NS.Hud.__ui().simStrip:IsShown(), "the HUD wears the sim strip")
    assertTrue(#NS.LaneRender.__icons("player") > 0, "the casts reach the Player lane")
    assertTrue(#NS.LaneRender.__icons("pet") > 0, "and the Pet lane")
    local rec = NS.Slices.Get("sim-newbest")
    assertTrue(rec ~= nil and rec.filled >= 4, "the chart's store fills, a step every 2 s")
    play(M, 45 - 10 + NS.Sim.SETTLE + 0.5)
    assertEqual(NS.Hud.State(), "over", "the fight-over card")
    local chips = NS.Hud.Chips()
    assertTrue(chips[1]:find("New best +", 1, true) == 1, "the New best chip with its gain: " .. tostring(chips[1]))
    assertEqual(chips[2], "Saved")
    assertFalse(NS.Results.IsShown(), "the card holds first")
    play(M, NS.Sim.RESULT_HOLD + 0.5)
    assertTrue(NS.Results.IsShown(), "then the Results window opens")
    assertEqual(NS.Results.Selected(), "sim-newbest", "on the sim's fight")
    assertEqual(NS.ResultsSource.All()[1].id, "sim-newbest", "the newest fight of the sample history")
    assertTrue(NS.ResultsSource.IsBest(NS.ResultsSource.Get("sim-newbest")), "the board's best now")
    assertEqual(NS.Sim.Diagnose().phase, "results")
    assertEqual(NS.Sim.Diagnose().ticking, false, "the beat stops")
    assertEqual(NS.Hud.State(), "over", "the HUD keeps the card")
    assertEqual(heard.n, 0, "no fight message on the bus")
    untouched(NS)
    NS.Preview.Stop()
    assertFalse(NS.ResultsSource.IsMock())
    assertEqual(NS.Slices.Get("sim-newbest"), nil, "the sim's chart goes with it")
    untouched(NS)
end)

test("sim short ends Not saved", function()
    local NS, M = fresh()
    sim(NS, "short")
    play(M, 22 + NS.Sim.SETTLE + 0.5)
    assertEqual(NS.Hud.State(), "over")
    assertEqual(NS.Hud.Chips()[1], "Not saved: shorter than 30 s")
    play(M, NS.Sim.RESULT_HOLD + 0.5)
    assertTrue(NS.Results.IsShown(), "the Results window opens on the list")
    assertEqual(NS.ResultsSource.Get("sim-short"), nil, "nothing joined the sample history")
    untouched(NS)
end)

test("sim: behind saves under the best; first has no pace; lost is not saved", function()
    local NS, M = fresh()
    sim(NS, "behind")
    play(M, 45 + NS.Sim.SETTLE + 0.5)
    local chips = NS.Hud.Chips()
    assertEqual(chips[1], "Saved", "no New best behind the best")
    assertEqual(#chips, 1)
    NS.Preview.Stop()

    sim(NS, "first")
    play(M, 5)
    assertEqual(NS.Hud.State(), "noBest", "nothing on the board to pace against")
    play(M, 40 + NS.Sim.SETTLE + 0.5)
    assertEqual(NS.Hud.Chips()[1], "New best", "the first fight on a board is its best, no gain")
    NS.Preview.Stop()

    sim(NS, "lost")
    play(M, 45 + NS.Sim.SETTLE + 0.5)
    assertEqual(NS.Hud.Chips()[1], "Not saved: the meter lost this fight")
    untouched(NS)
end)

test("sim: the verb starts it through the step session, and stop ends it", function()
    local NS, M = fresh()
    assertTrue(NS.Sim.session ~= nil, "the library's step session")
    NS.RunSimVerb("newbest")
    assertEqual(NS.Preview.Mode(), "sim")
    assertTrue(NS.IsSimMode(), "Sim mode reads on")
    play(M, 6)
    assertTrue(NS.Sim.Diagnose().phase ~= "parked", "the playing stepper released the fight")
    NS.RunSimVerb("stop")
    assertFalse(NS.Preview.IsActive(), "the stepper's stop ends the preview")
    assertFalse(NS.ResultsSource.IsMock())
    untouched(NS)
end)

test("sim: combat ends it; a refused start leaves nothing on", function()
    local NS, M = fresh()
    sim(NS, "newbest")
    play(M, 5)
    M.__now = M.__now + 1
    M.InCombatLockdown = function() return true end
    M.__inCombat = true
    M.__fire("PLAYER_REGEN_DISABLED")
    assertFalse(NS.Preview.IsActive(), "a real fight ends the sim")
    assertEqual(NS.Sim.Diagnose().phase, "none")
    assertEqual(NS.Sim.Diagnose().ticking, false)
    assertTrue(NS.Hud.View().fight == nil or not NS.Hud.View().fight.sample, "the sample fight left the HUD")
    assertFalse(NS.Preview.Start({ mode = "sim", scenario = "behind" }), "refused in combat")
    assertFalse(NS.Preview.IsActive())
end)
