-- tests/test_race_clock.lua — the beats at `hud.refreshRate` (owner, 2026-11-13; default 10 a second).
-- The race beat (race window redesign plan Task W5, ruling O5): one AceTimer on the addon object while
-- a race, the real one or the sample, runs or stops, each fire the DPS HUD's read and redraw then one
-- RACE_CLOCK, the Race window drawing that same read. No race beat outside a race; it stops on idle,
-- on a result and on the stand-down. A fight that is no race has the HUD's own beat: one meter read
-- (none in the settle) and the whole redraw (clock, figures, rows), standing down while the race beat
-- runs; FIGHT_TICK keeps its 4 Hz and leaves the HUD to the beat; each rate takes effect mid-fight and
-- shows in the footer. Through the REAL Fight and Race (tests/race_fixture.lua); the HUD's own beat on
-- both kit profiles, the race beat on Retail only.

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
    return S
end

-- RACE_CLOCK as heard on the bus.
local function beats(NS)
    local heard = { n = 0 }
    NS.NewBusTarget():RegisterMessage(NS.MSG.RACE_CLOCK, function() heard.n = heard.n + 1 end)
    return heard
end

local function hudClock(NS)
    local ui = NS.Hud.__ui()
    return ui and ui.body.live and ui.body.live.w.clock or nil
end

test("race clock: absent on WoW Forever", function()
    if not forever() then return end
    local S = F.fresh()
    assertNil(S.NS.RaceClock, "no race beat on WoW Forever")
end)

test("race clock: no beat outside a race, nor while armed or on a plain fight", function()
    if forever() then return end
    local S = fresh()
    local RC = S.NS.RaceClock
    assertEqual(RC.TICK, 0.1)
    assertFalse(RC.On(), "idle")
    assertTrue(F.arm(S, 30))
    assertFalse(RC.On(), "armed: the clock has not started")
    S.NS.Race.Cancel()
    local start = F.pull(S)
    F.run(S, start + 1)
    assertFalse(RC.On(), "a plain fight: no beat")
    assertNil(RC.Fight())
end)

test("race clock: the beat runs while the race runs and stops, and ends with the result", function()
    if forever() then return end
    local S = fresh()
    local RC = S.NS.RaceClock
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    assertEqual(S.NS.Race.State(), "running")
    assertTrue(RC.On(), "running")
    assertEqual(RC.Fight(), S.NS.Race.Fight(), "the race's fight")
    F.damage(S, 25, start + 1, start + 30, 1)
    assertEqual(S.NS.Race.State(), "stopping")
    assertTrue(RC.On(), "stopping")
    F.settle(S, start + 31)
    assertEqual(S.NS.Race.State(), "result")
    assertFalse(RC.On(), "the result: no beat")
end)

test("race clock: a canceled race and the stand-down stop the beat", function()
    if forever() then return end
    local S = fresh()
    local RC = S.NS.RaceClock
    assertTrue(F.arm(S, 30))
    F.pull(S)
    assertTrue(RC.On())
    S.NS.Race.Cancel()
    assertFalse(RC.On(), "canceled: idle, no beat")
    local S2 = fresh()
    assertTrue(F.arm(S2, 30))
    F.pull(S2)
    assertTrue(S2.NS.RaceClock.On())
    assertTrue(S2.NS.SetByPath("general.enabled", false))
    assertFalse(S2.NS.RaceClock.On(), "stood down: no beat")
    local heard = beats(S2.NS)
    F.run(S2, 110)
    assertEqual(heard.n, 0, "and nothing beats after it")
end)

test("race clock: each fire sends one RACE_CLOCK", function()
    if forever() then return end
    local S = fresh()
    local heard = beats(S.NS)
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    heard.n = 0
    S.NS.RaceClock.__beat()
    assertEqual(heard.n, 1, "one beat, one message")
    -- The kit's queue fires each queued timer once per pass: one pass, one beat.
    F.at(S, start + 0.5)
    local before = heard.n
    S.M.__fireTimers()
    assertEqual(heard.n - before, 1, "one timer: one message per pass")
end)

test("race clock: during a race the HUD's clock moves on the beat, not on FIGHT_TICK", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    NS.Hud.Show()
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.run(S, start + 0.25)
    local fight = NS.Race.Fight()
    assertEqual(NS.Hud.View().fight, fight, "the HUD shows the race's fight")
    local clock = hudClock(NS)
    F.at(S, start + 5)
    clock:SetText("held")
    NS.Hud.OnFightTick(fight)
    assertEqual(clock:GetText(), "held", "FIGHT_TICK leaves the clock to the beat")
    NS.RaceClock.__beat()
    assertEqual(clock:GetText(), NS.Format.Clock(S.M.__now - fight.firstHitT), "the beat draws it from GetTime()")
    F.at(S, start + 5.3)
    NS.RaceClock.__beat()
    assertEqual(clock:GetText(), NS.Format.Clock(S.M.__now - fight.firstHitT))
end)

-- A fresh instance on either client (auto-show off on Retail), the HUD up on a plain fight's first hit.
local function plainFight()
    local S = F.fresh({ mutate = function(m) installPaint(m) end })
    if not forever() then
        assert(S.NS.SetByPath("race.autoShow", false))
        S.NS.RaceWindow.HideAwayFromDummy()
    end
    S.NS.Hud.Show()
    local start = F.pull(S)
    F.run(S, start + 0.25)
    local fight = S.NS.Hud.View().fight
    assertTrue(fight ~= nil and fight.race == nil, "a plain fight on the HUD")
    return S, fight, start
end

-- The HUD's own beat's queued timer (the kit's AceTimer queue entry), or nil.
local function hudBeat(S)
    for _, t in ipairs(S.M.__timers) do
        if t.timer and not t.timer.cancelled and t.delay == S.NS.Hud.BeatEvery() then return t end
    end
    return nil
end

-- NS.Meter.ReadLive counted; answers the counter and the restore.
local function countReads(NS)
    local n, read = { n = 0 }, NS.Meter.ReadLive
    NS.Meter.ReadLive = function(...) n.n = n.n + 1; return read(...) end
    return n, function() NS.Meter.ReadLive = read end
end

local function liveBody(NS) return NS.Hud.__ui().body.live end

test("hud beat: a plain fight reads and redraws 10 times a second by default, FIGHT_TICK leaving it", function()
    local S, fight, start = plainFight()
    local NS = S.NS
    assertEqual(NS.defaults.profile.hud.refreshRate, 10, "the default")
    assertEqual(NS.Hud.BeatEvery(), 0.1, "the beat runs at 0.1 s")
    assertTrue(hudBeat(S) ~= nil, "one repeating AceTimer queued")
    assertEqual(NS.Hud.__ui().footRight:GetText(), "live \194\183 10 Hz", "the footer says the rate")
    local reads, restore = countReads(NS)
    local clock = hudClock(NS)
    clock:SetText("held")
    F.at(S, start + 4.3)
    NS.Hud.OnFightTick(fight)
    assertEqual(clock:GetText(), "held", "FIGHT_TICK leaves the HUD to the beat")
    assertEqual(reads.n, 0, "and reads nothing")
    hudBeat(S).fn()
    assertEqual(reads.n, 1, "one beat, one read")
    assertEqual(clock:GetText(), NS.Format.Clock(S.M.__now - fight.firstHitT), "the beat draws the clock")
    restore()
end)

test("hud beat: Damage, DPS, the pace view and the spell rows move on each beat", function()
    local S, _, start = plainFight()
    local NS = S.NS
    local body = liveBody(NS)
    S.meter.SetSession(25, { damage = 100000, dps = 1000, duration = 10, spells = { { id = 348, dmg = 100000, dps = 1000 } } })
    S.M.__now = start + 2
    hudBeat(S).fn()
    assertEqual(body.w.damage.value:GetText(), NS.Format.Number(100000))
    assertEqual(#body.parts.spells.list:Rows(), 1, "one spell row")
    S.meter.SetSession(25, { damage = 250000, dps = 2500, duration = 10,
        spells = { { id = 348, dmg = 150000, dps = 1500 }, { id = 29722, dmg = 100000, dps = 1000 } } })
    S.M.__now = start + 2.1
    hudBeat(S).fn()
    assertEqual(body.w.damage.value:GetText(), NS.Format.Number(250000), "the next beat's Damage")
    assertEqual(body.w.dps.value:GetText(), NS.Format.Rate(2500), "and DPS")
    assertEqual(#body.parts.spells.list:Rows(), 2, "the breakdown on the same beat")
    local v = NS.Hud.View()
    assertTrue(v.live ~= nil and v.live.player.total == 250000, "the pace bar and the chart take this read")
end)

test("hud beat: each rate, and a switch mid-fight", function()
    local S = plainFight()
    local NS = S.NS
    for _, rate in ipairs({ 4, 5, 20, 10 }) do
        assertTrue(NS.SetByPath("hud.refreshRate", rate))
        assertEqual(NS.Hud.BeatEvery(), 1 / rate, rate .. " a second, mid-fight")
        assertTrue(hudBeat(S) ~= nil, "re-armed at " .. rate)
        assertEqual(NS.Hud.__ui().footRight:GetText(), ("live \194\183 %d Hz"):format(rate))
    end
    assertFalse(NS.SetByPath("hud.refreshRate", 7), "a rate the row does not offer")
    NS.db.profile.hud.refreshRate = nil
    NS.Hud.SyncBeat()
    assertEqual(NS.Hud.BeatEvery(), 0.1, "a profile without the key reads the default")
    assertEqual(NS.Constants.FIGHT.TICK, 0.25, "FIGHT_TICK keeps its own 4 Hz for its other receivers")
    assertEqual(NS.Fight.Timers().tick.delay or 0.25, 0.25)
end)

test("hud beat: no read in the settle, and it stops with the window and the fight", function()
    local S, fight, start = plainFight()
    local NS = S.NS
    NS.Hud.Hide()
    assertNil(NS.Hud.BeatEvery(), "the window closed: no beat")
    NS.Hud.Show()
    assertTrue(NS.Hud.BeatEvery() ~= nil, "open again on the live fight")
    F.leave(S, start + 3)
    assertEqual(NS.Fight.State(), "settling")
    local reads, restore = countReads(NS)
    S.M.__now = start + 3.5
    hudBeat(S).fn()
    assertEqual(reads.n, 0, "out of combat the beat reads nothing (FIGHT_TICK's window)")
    assertEqual(hudClock(NS):GetText(), NS.Format.Clock(S.M.__now - fight.firstHitT), "the clock moves on")
    restore()
    F.run(S, start + 3 + 4.1)
    F.run(S, start + 10)
    assertEqual(NS.Hud.State(), "over")
    assertNil(NS.Hud.BeatEvery(), "the over card: no beat")
end)

test("race clock: the race beat runs at hud.refreshRate, reads once, and the Race window draws that read", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    NS.Hud.Show()
    NS.RaceWindow.Show()
    assertTrue(NS.SetByPath("hud.refreshRate", 20))
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.run(S, start + 0.25)
    assertTrue(NS.RaceClock.On())
    assertEqual(NS.RaceClock.Diagnose().every, 0.05, "20 a second")
    assertNil(NS.Hud.BeatEvery(), "the HUD's own beat stands down: one beat at a time")
    local reads, restore = countReads(NS)
    S.meter.SetSession(25, { damage = 777000, dps = 7770, duration = 10, spells = { { id = 348, dmg = 777000, dps = 7770 } } })
    S.M.__now = start + 3
    local before = NS.RaceWindow.View()
    NS.RaceClock.__beat()
    assertEqual(reads.n, 1, "one read a beat")
    assertTrue(NS.RaceWindow.View() ~= before, "the Race window redrew")
    assertEqual(NS.RaceWindow.View().you, 777000, "on the HUD's read of this beat")
    assertEqual(liveBody(NS).w.damage.value:GetText(), NS.Format.Number(777000), "the HUD's Damage too")
    NS.RaceClock.__beat()
    assertEqual(reads.n, 2)
    restore()
    assertTrue(NS.SetByPath("hud.refreshRate", 4))
    assertEqual(NS.RaceClock.Diagnose().every, 0.25, "a switch mid-race")
    NS.Race.Cancel()
    F.run(S, start + 1)
    assertFalse(NS.RaceClock.On(), "canceled: no race beat")
    assertEqual(NS.Hud.BeatEvery(), 0.25, "the plain fight's own beat takes over")
end)

test("race clock: the held sample race beats while running, and stops with test mode", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local RC = NS.RaceClock
    NS.Slash:OnSlash("test race armed")
    assertFalse(RC.On(), "a sample armed: no beat")
    NS.Slash:OnSlash("test race running")
    assertTrue(NS.RaceSample.On())
    assertTrue(RC.On(), "a sample running: the beat")
    assertEqual(RC.Fight(), NS.RaceSample.Fight(), "the sample race's fight")
    NS.Slash:OnSlash("test race result")
    assertFalse(RC.On(), "a sample result: no beat")
    NS.Slash:OnSlash("test race running")
    assertTrue(RC.On())
    NS.Preview.Stop()
    assertFalse(NS.RaceSample.On())
    assertFalse(RC.On(), "test mode off: no beat")
end)

test("race clock: the sim's race beats from its first hit through Stop!, and stops at its read", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local RC = NS.RaceClock
    S.M.__now = 1000
    assertTrue(NS.Preview.Start({ mode = "sim", scenario = "race-newbest" }))
    assertFalse(RC.On(), "parked, armed: no beat")
    assertTrue(NS.Sim.Unpark())
    local t0 = S.M.__now
    local function playTo(rc)
        local stop = t0 + NS.MockFights.FIRST_HIT + rc
        while S.M.__now < stop - 1e-9 do
            S.M.__now = math.min(stop, S.M.__now + NS.SimRace.TICK)
            S.M.__fireTimers()
        end
    end
    playTo(2)
    assertEqual(NS.RaceSample.State(), "running")
    assertTrue(RC.On(), "the sample race runs: the beat")
    assertEqual(NS.Hud.View().fight, NS.RaceSample.Fight(), "the HUD shows the sample race's fight")
    local clock = hudClock(NS)
    clock:SetText("held")
    NS.Hud.OnFightTick(NS.RaceSample.Fight())
    assertEqual(clock:GetText(), "held", "the sim's tick leaves the clock to the beat")
    NS.RaceClock.__beat()
    assertEqual(clock:GetText(), NS.Format.Clock(S.M.__now - NS.RaceSample.Fight().firstHitT))
    playTo(30.2)
    assertEqual(NS.RaceSample.State(), "stopping")
    assertTrue(RC.On(), "Stop!: the beat")
    local MR = NS.MockRaces
    playTo(MR.LENGTH + 4.2 + NS.RaceScoring.QUIET_BEFORE_READ + 0.2)
    assertEqual(NS.RaceSample.State(), "result")
    assertFalse(RC.On(), "read: no beat")
    NS.Preview.Stop()
    assertFalse(RC.On())
end)
