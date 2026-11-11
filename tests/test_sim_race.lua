-- tests/test_sim_race.lua — the sim's race scenarios (race plan Task E1, R:test-sim#3, #6, #14):
-- DPS Race's sim race cases (@f8078c7 tests/test_sim.lua, test_sample_parity.lua, test_countdown.lua)
-- on Combat Trail's sim (modules/SimRace.lua through modules/Sim.lua). A made-up race arms on the Race
-- window, starts its clock on the first hit, counts down with the real marks, buzzes, reads after the
-- quiet and holds its card, the HUD's over card and the result line, then opens the Results window on
-- it; nothing reaches the bus or the store and NS.Race never moves. The gate holds each step; Race mode
-- off refuses the eight; WoW Forever has none of them (its last case).

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local F = dofile(T.root .. "/tests/race_fixture.lua")(T)
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local function forever() return T.NS.Compat.IsForever() end

local function fresh()
    local S = F.fresh({ mutate = function(m) installPaint(m) end })
    assert(S.NS.SetByPath("race.autoShow", false))
    S.NS.RaceWindow.HideAwayFromDummy()
    S.M.__now = 1000
    return S
end

local function prints(S)
    local lines = {}
    S.NS.Print = function(line) lines[#lines + 1] = line end
    return lines
end

local function has(list, want)
    for _, s in ipairs(list) do
        if type(s) == "string" and s:find(want, 1, true) then return true end
    end
    return false
end

local function current(S)
    local ui = S.NS.RaceWindow.__ui()
    return S.NS.RaceWindow.IsShown() and ui and ui.current or nil
end

-- Every fight and race message the bus carries meanwhile: a sim sends none.
local function listen(NS)
    local heard = { n = 0 }
    local bus = NS.NewBusTarget()
    for _, name in ipairs({ "FIGHT_STARTED", "FIGHT_TICK", "FIGHT_ENDED", "FIGHT_SAVED", "FIGHT_SKIPPED",
                            "RACE_STATE_CHANGED", "RACE_ARMED", "RACE_STARTED", "RACE_BUZZER", "RACE_RESULT",
                            "RACE_CANCELED" }) do
        bus:RegisterMessage(NS.MSG[name], function() heard.n = heard.n + 1 end)
    end
    return heard
end

-- Start race scenario `key`, parked armed, and release it (the stepper's Race starts). Answers the
-- combat entry's GetTime().
local function sim(S, key)
    assertTrue(S.NS.Preview.Start({ mode = "sim", scenario = key }), key .. " started")
    assertEqual(S.NS.Sim.Diagnose().phase, "parked", "parked until a step plays")
    assertEqual(current(S), "armed", "the Race window's armed body")
    assertTrue(S.NS.Sim.Unpark())
    return S.M.__now
end

-- Play the race clock (seconds past the first hit) to `rc`, a beat at a time.
local function playTo(S, t0, rc)
    local stop = t0 + S.NS.MockFights.FIRST_HIT + rc
    while S.M.__now < stop - 1e-9 do
        S.M.__now = math.min(stop, S.M.__now + S.NS.SimRace.TICK)
        S.M.__fireTimers()
    end
end

local function untouched(S)
    assertEqual(next(S.NS.db.global.fights or {}), nil, "a sim race reached the store")
    assertEqual(next(S.NS.db.global.pendingRaces or {}), nil, "a sim race reached the pending slots")
    assertEqual(S.NS.Race.State(), "idle", "the real race moved")
end

test("sim race: race-newbest arms, races on its clock, buzzes, reads after the quiet; nothing on the bus", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local heard = listen(NS)
    local lines = prints(S)
    local t0 = sim(S, "race-newbest")
    assertTrue(has(lines, "Armed: 0:30 on "), "the armed line, through the real Share")
    playTo(S, t0, 5)
    assertEqual(current(S), "running", "the first hit starts the race clock")
    local v = NS.RaceWindow.View()
    assertTrue(math.abs(v.elapsed - 5) < 0.11, "the race clock: " .. tostring(v.elapsed))
    assertTrue(v.pace ~= nil, "paced on its race board")
    assertEqual(NS.Hud.State(), "live", "the HUD's live view")
    assertTrue(NS.Hud.View().fight.race ~= nil)
    assertTrue(#NS.LaneRender.__icons("player") > 0, "the lanes play")
    playTo(S, t0, 25.5)
    assertEqual(NS.Countdown.Shown(), 5, "the real marks count the sim's race down")
    playTo(S, t0, 30.2)
    assertEqual(NS.RaceWindow.View().key, "stop", "the buzzer: Stop!")
    assertNil(NS.Countdown.Shown(), "the buzzer clears the countdown")
    local MR, SR = NS.MockRaces, NS.SimRace
    local readAt = MR.LENGTH + math.max(3.1, 4.2) + NS.RaceScoring.QUIET_BEFORE_READ
    playTo(S, t0, readAt - 0.3)
    assertTrue(NS.RaceWindow.View().key ~= "result", "no read before the quiet")
    playTo(S, t0, readAt + 0.1)
    assertEqual(current(S), "result", "the result card")
    v = NS.RaceWindow.View()
    assertTrue(v.isNew == true and v.delta > 0, "a new best over the sample history's")
    local record = NS.ResultsSource.Get("sim-race-newbest")
    assertTrue(record ~= nil and record.race.status == "complete", "the race joins the sample history")
    assertEqual(NS.Hud.State(), "over", "the HUD's over card")
    assertTrue(has(lines, "new best"), "the result line, through the real Share")
    assertEqual(NS.BestToast.Diagnose().key, "sim-race-newbest", "the new-best toast")
    assertFalse(NS.Results.IsShown(), "the card holds first")
    playTo(S, t0, readAt + SR.RESULT_HOLD + 0.3)
    assertTrue(NS.Results.IsShown(), "then the Results window opens")
    assertEqual(NS.Results.Selected(), "sim-race-newbest", "on the race")
    assertEqual(NS.Sim.Diagnose().phase, "results")
    assertEqual(NS.Sim.Diagnose().ticking, false, "the beat stops")
    assertEqual(heard.n, 0, "no fight or race message on the bus")
    untouched(S)
    NS.Preview.Stop()
    assertFalse(NS.RaceSample.On())
    assertFalse(NS.RaceWindow.IsShown(), "the window the sim opened closes")
end)

test("sim race: incomplete and died end before the buzzer, with no buzzer, and read out of combat", function()
    if forever() then return end
    for _, key in ipairs({ "race-incomplete", "race-died" }) do
        local S = fresh()
        local NS = S.NS
        local buzzed = 0
        local real = NS.Countdown.Buzzer
        NS.Countdown.Buzzer = function(...) buzzed = buzzed + 1 return real(...) end
        local t0 = sim(S, key)
        local endAt = key == "race-died" and 6 or 9
        playTo(S, t0, endAt + 0.2)
        local v = NS.RaceWindow.View()
        assertEqual(v.key, "waiting", key .. ": combat ended, waiting for the read")
        assertTrue(v.endedEarly, key .. ": before the buzzer")
        playTo(S, t0, endAt + NS.RaceScoring.QUIET_BEFORE_READ + 0.2)
        assertEqual(current(S), "result", key .. ": the card")
        local record = NS.ResultsSource.Get("sim-" .. key)
        assertEqual(record.race.status, "incomplete", key)
        assertEqual(record.race.endedAt, endAt, key)
        assertEqual(record.race.flags.died == true, key == "race-died", key .. ": died")
        assertNil(NS.RaceWindow.View().isNew, key .. ": no delta for an incomplete race")
        assertEqual(buzzed, 0, key .. ": no buzzer")
        untouched(S)
        NS.Preview.Stop()
    end
end)

test("sim race: race-flagged's late cast flags the card; race-shared has no pace", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local t0 = sim(S, "race-flagged")
    playTo(S, t0, 40)
    local record = NS.ResultsSource.Get("sim-race-flagged")
    assertEqual(record.race.flags.lateCasts[1].t, 1.4, "the late cast, past the buzzer")
    assertTrue(NS.RaceRecord.Flagged(record), "flagged")
    local want = NS.MockFights.FIRST_HIT + NS.MockRaces.LENGTH + 1.4
    local found = false
    for _, c in ipairs(NS.CastCodec.Decode(record.casts)) do
        if math.abs(c.t - want) < 0.01 then found = true end
    end
    assertTrue(found, "in the race's own cast list")
    NS.Preview.Stop()
    t0 = sim(S, "race-shared")
    playTo(S, t0, 5)
    local v = NS.RaceWindow.View()
    assertNil(v.pace, "no pace bar on a shared session")
    assertEqual(v.paceWhy, "not paced: shared session")
    assertNil(NS.Hud.View().pace, "nor on the HUD")
    NS.Preview.Stop()
end)

test("sim race: race-sticky's wait says combat holds on, the hint shows after its delay", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local t0 = sim(S, "race-sticky")
    local delay = NS.GetSetting("race.hintDelay")
    NS.SimRace.Play("raceEnd")
    playTo(S, t0, 30 + delay + 0.5)
    local v = NS.RaceWindow.View()
    assertEqual(v.key, "waiting", "the tail went quiet; combat holds on")
    assertTrue(v.hint ~= nil, "the hint shows past its delay")
    local open, line = NS.Sim.Gate()
    assertFalse(open)
    assertEqual(line, "Waiting for the result (combat holds on).")
    playTo(S, t0, 30 + delay + NS.SimRace.STICKY_EXTRA + 0.2)
    open, line = NS.Sim.Gate()
    assertFalse(open)
    assertEqual(line, "Waiting for the result.", "combat ended; the quiet runs")
    playTo(S, t0, 30 + delay + NS.SimRace.STICKY_EXTRA + NS.RaceScoring.QUIET_BEFORE_READ + 0.2)
    assertEqual(current(S), "result")
    NS.Preview.Stop()
end)

test("sim race: the gate holds the race, the read, then the card; Stop Now reads at the combat end", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local t0 = sim(S, "race-newbest")
    NS.SimRace.Play("raceRun")
    playTo(S, t0, 5)
    local open, line = NS.Sim.Gate()
    assertFalse(open)
    assertEqual(line, "The race is still running.")
    NS.SimRace.Play("raceEnd")
    playTo(S, t0, 31)
    open, line = NS.Sim.Gate()
    assertFalse(open)
    assertEqual(line, "Waiting for the result.")
    assertTrue(NS.RaceWindow.Act.stopNow(), "Stop Now acts on the sample")
    assertEqual(NS.Race.State(), "idle", "never on a real race")
    playTo(S, t0, 30 + 4.2 + 0.2)
    assertEqual(current(S), "result", "Stop Now skips the quiet once combat is over")
    NS.SimRace.Play("raceCard")
    open, line = NS.Sim.Gate()
    assertFalse(open)
    assertEqual(line, "The result card holds.")
    playTo(S, t0, 30 + 4.2 + NS.SimRace.RESULT_HOLD + 0.4)
    assertTrue((NS.Sim.Gate()), "the hold is over")
    NS.Preview.Stop()
end)

test("sim race: the eight follow the fight scenarios; Race mode off refuses them", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local names = table.concat(NS.Sim.Names(), ",")
    for _, key in ipairs({ "race-newbest", "race-behind", "race-first", "race-incomplete", "race-died",
                           "race-flagged", "race-shared", "race-sticky" }) do
        assertTrue(NS.Sim.IsScenario(key), key)
    end
    assertTrue(names:find("lost,race-newbest", 1, true) ~= nil, "after the fight scenarios: " .. names)
    -- race-first fights a board with no history: nothing to beat.
    local t0 = sim(S, "race-first")
    playTo(S, t0, 40)
    assertEqual(current(S), "result")
    local v = NS.RaceWindow.View()
    assertTrue(v.isNew == true and v.delta == nil, "a first race is a best with nothing to beat")
    NS.Preview.Stop()
    local lines = prints(S)
    assert(NS.SetByPath("race.enabled", false))
    assertFalse(NS.Sim.Start("race-newbest"))
    assertTrue(has(lines, "Race mode is off"), "one line")
    assertFalse(NS.Preview.IsActive())
    assertTrue(NS.Sim.Start("newbest"), "the fight scenarios still play")
    NS.Preview.Stop()
end)

test("sim race: WoW Forever has no race scenario", function()
    if not forever() then return end
    local NS = T.load().NS
    assertNil(NS.SimRace)
    for _, key in ipairs(NS.Sim.Names()) do assertFalse(key:find("^race%-") ~= nil, key) end
    assertFalse(NS.Sim.IsScenario("race-newbest"))
end)
