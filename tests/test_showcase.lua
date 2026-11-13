-- tests/test_showcase.lua — the one showcase sample set and the samples' alerts (callout plan row C6,
-- owner 2026-11-14). The set (modules/MockFights.lua, modules/MockRaces.lua) is fixed, the same for
-- every character, and every view of it agrees: a record's damage is its player plus its pet and its
-- spell rows add up to it, its DPS is that damage over its length, the HUD's live DPS is its damage over
-- the HUD's clock, the pet's live rows carry the pet's name, the chart carries its cooldown marks
-- against a best's pace, and the Race window's checkpoints stand on the best's straight line. The
-- alerts: `/ct test race result` and the sim's scenarios show the new-best toast and the call-out's
-- words they earn (NEW_BEST, FAILED; the sim's countdown and STOP are tests/test_sim_race.lua's), never
-- write a record or a best, and come down when the preview stops. WoW Forever has no call-out and no
-- race: its cases check the fights alone.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local F = dofile(T.root .. "/tests/race_fixture.lua")(T)
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local function forever() return T.NS.Compat.IsForever() end

local function fresh()
    local S = F.fresh({ mutate = function(m) installPaint(m) end })
    local NS = S.NS
    if NS.RaceWindow then
        assert(NS.SetByPath("race.autoShow", false))
        assert(NS.SetByPath("race.autoShowHud", false))
        NS.RaceWindow.HideAwayFromDummy()
        NS.Hud.HideAwayFromDummy()
    end
    S.M.__now = 1000
    return S
end

local function near(got, want, slack, msg)
    assertTrue(type(got) == "number" and math.abs(got - want) <= slack,
        (msg or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got))
end

-- Nothing a sample drew reached SavedVariables, and the store's bests are still empty.
local function untouched(S)
    local NS, g = S.NS, S.NS.db.global
    assertEqual(next(g.fights or {}), nil, "a sample reached the store")
    assertEqual(next(g.pendingRaces or {}), nil, "a sample race reached the pending slots")
    assertEqual(next(NS.Bests.Compute(NS.Recorder.List())), nil, "a sample made a best")
end

local function toastKey(NS)
    local _, key = NS.BestToast.Instance():Current()
    return key
end

local function said(NS)
    local st = NS.Callout:Stats()
    return st.shown and st.key or nil
end

-- One client frame: every armed OnUpdate runs (the call-out's frame clock).
local function frame(S)
    for _, h in ipairs(S.M.__timers()) do
        if type(h) == "table" and h.__scripts and h.__scripts.OnUpdate then h:__fire("OnUpdate", 0) end
    end
end

local function play(S, secs, tick)
    tick = tick or 0.1
    local stop = S.M.__now + secs
    while S.M.__now < stop - 1e-9 do
        S.M.__now = math.min(stop, S.M.__now + tick)
        S.M.__fireTimers()
        frame(S)
    end
end

-- Play a beat at a time until `done()` holds (at most `secs`): the kit services every queued timer at
-- once, whatever its delay, so a toast's own countdown runs out on the beat after it shows.
local function playUntil(S, done, secs, tick)
    tick = tick or 0.1
    local stop = S.M.__now + secs
    while not done() and S.M.__now < stop - 1e-9 do
        S.M.__now = math.min(stop, S.M.__now + tick)
        S.M.__fireTimers()
        frame(S)
    end
    assertTrue(done(), "reached in time")
end

local function sim(S, key)
    assertTrue(S.NS.Preview.Start({ mode = "sim", scenario = key }), key .. " started")
    assertTrue(S.NS.Sim.Unpark())
end

-- ── the data ────────────────────────────────────────────────────────────────────────────────────

test("showcase: every sample record adds up: rows to the damage, player plus pet, DPS over its length", function()
    local NS = fresh().NS
    local data = NS.MockFights.Dataset()
    for _, r in ipairs(data.fights) do
        local sum, pets = 0, 0
        for _, sp in ipairs(NS.Recorder.Spells(r)) do
            sum = sum + sp.total
            if sp.isPet then pets = pets + sp.total end
        end
        assertEqual(sum, r.damage.merged, r.id .. ": the spell rows add up to the damage")
        assertEqual(r.damage.merged, r.damage.player + (r.damage.pet or 0), r.id .. ": player plus pet")
        assertEqual(pets, r.damage.pet or 0, r.id .. ": the pet's rows add up to the pet's damage")
        near(r.dps, r.damage.merged / r.duration, 0.05, r.id .. ": DPS is the damage over the length")
        if NS.RaceRecord.IsRace(r) then
            local secs = r.race.status == "incomplete" and r.race.endedAt or r.race.length
            near(r.race.dps, r.race.score / secs, 0.05, r.id .. ": race DPS is the score over its time")
            assertEqual(r.race.score, r.damage.merged, r.id .. ": the score is the race's damage")
        end
        local chart = data.slices[r.id]
        if chart then
            assertTrue(chart.values[chart.count] <= r.damage.player, r.id .. ": the chart climbs to the damage")
            assertTrue(chart.pet[chart.count] <= (r.damage.pet or 0), r.id .. ": the pet's line too")
        end
    end
end)

test("showcase: one fixed set, the same for every character (the sample realm, not the player's)", function()
    local S = fresh()
    local NS = S.NS
    local a = NS.MockFights.Dataset()
    NS.Identity.Who = function() return { name = "Other", realm = "Elsewhere", class = "MAGE" } end
    local b = NS.MockFights.Dataset()
    assertEqual(#a.fights, #b.fights)
    for i, r in ipairs(a.fights) do
        assertEqual(r.who.realm, NS.MockFights.REALM, r.id .. ": on the sample realm")
        assertEqual(b.fights[i].who.realm, NS.MockFights.REALM)
        assertEqual(b.fights[i].who.name, r.who.name, r.id .. ": the same hunter")
        assertEqual(b.fights[i].damage.merged, r.damage.merged, r.id .. ": the same damage")
        assertEqual(b.fights[i].spells, r.spells, r.id .. ": the same rows")
    end
end)

test("showcase: test mode's HUD agrees with itself: live DPS over the clock, the pet named, cooldown marks, the pace", function()
    local S = fresh()
    local NS = S.NS
    assertTrue(NS.Preview.Start())
    local v = NS.Hud.View()
    assertEqual(v.clock, NS.Preview.STILL_AT, "held at its moment")
    local live = v.live
    near(live.player.dps, live.player.total / v.clock, 1e-6, "the player's DPS is the damage over the clock")
    assertTrue(live.pet ~= nil and live.pet.total > 0, "the pet's own figure under Damage and DPS")
    near(live.pet.dps, live.pet.total / v.clock, 1e-6, "the pet's DPS over the same clock")
    assertTrue(v.hasPet, "the boxes draw the Pet figure")
    local sum = 0
    for _, sp in ipairs(live.player.spells) do sum = sum + sp.total end
    assertEqual(sum, live.player.total, "the player's rows add up to the player's damage")
    assertTrue(live.petOut, "the pet is out")
    local pet = NS.MockFights.Character("me").petName
    for _, sp in ipairs(live.pet.spells) do assertEqual(sp.creatureName, pet, "a pet row names the pet") end
    for _, sp in ipairs(live.player.spells) do assertEqual(sp.creatureName, "", "an owner row names nobody") end
    local rows = NS.Hud.__ui().body.live.parts.spells.list:Rows()
    local petRows = 0
    for _, row in ipairs(rows) do
        if row.isPet then
            petRows = petRows + 1
            assertTrue(row.paw:IsShown(), "a pet row wears the paw")
            assertEqual(row.pct:GetText(), pet, "and the pet's name")
        end
    end
    assertTrue(petRows > 0 or #rows < #live.player.spells + 1, "pet rows drawn where room allows")
    assertTrue(v.pace ~= nil and v.pace.id == "sample-01", "paced against the board's best")
    assertTrue(v.chartView ~= nil and #v.chartView.cooldowns > 0, "the chart carries cooldown marks")
    assertTrue(v.paceView ~= nil and v.paceView.total > v.paceView.ref, "3% ahead of the best's pace")
    NS.Preview.Stop()
    untouched(S)
end)

test("showcase: /ct test stays the HUD's alone: no toast, no call-out", function()
    local S = fresh()
    local NS = S.NS
    assertTrue(NS.Preview.Start())
    assertNil(toastKey(NS), "no toast")
    if NS.Callout then assertNil(said(NS), "no call-out") end
    NS.Preview.Stop()
end)

-- ── the race's showcase (Retail) ────────────────────────────────────────────────────────────────

test("showcase: test race running: two checkpoints passed, the third next, on the best's line", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    assertTrue(NS.Preview.TestRace("running"))
    local v = NS.RaceWindow.View()
    local best = v.bestView.record
    local passed, nextAt = 0, nil
    for i, cp in ipairs(v.checkpoints) do
        if cp.passed then passed = passed + 1 end
        if cp.next then nextAt = i end
        near(cp.damage, best.race.score * cp.t / best.race.length, 1e-6, "checkpoint " .. i .. " on the best's line")
    end
    assertEqual(passed, 2, "0:07.5 and 0:15.0 passed (green)")
    assertEqual(nextAt, 3, "0:22.5 is next (amber)")
    assertEqual(NS.Hud.View().clock, NS.Preview.RACE_STILL_AT, "the HUD at the race's moment")
    assertNil(NS.RaceSample.EndsAt(), "a held race clock has no endsAt")
    assertNil(said(NS), "so no countdown")
    NS.Preview.Stop()
    untouched(S)
end)

test("showcase: test race result: the new-best toast and NEW_BEST; both go when test mode stops", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    assertTrue(NS.Preview.TestRace("result"))
    assertEqual(toastKey(NS), NS.TOAST_PREVIEW, "the toast's preview")
    assertEqual(said(NS), "NEW_BEST", "the call-out says NEW_BEST")
    assertTrue(NS.Preview.SetRace("armed"))
    assertNil(toastKey(NS), "a switch takes the toast down")
    assertNil(said(NS), "and the call-out")
    assertTrue(NS.Preview.SetRace("result"))
    assertEqual(said(NS), "NEW_BEST")
    NS.Preview.Stop()
    assertNil(toastKey(NS), "the stop takes the toast down")
    assertNil(said(NS), "and the call-out")
    untouched(S)
end)

test("showcase: sim race-newbest: countdown to the sample's endsAt, STOP, then NEW_BEST and the toast", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    sim(S, "race-newbest")
    play(S, NS.MockFights.FIRST_HIT + 25.5)
    assertEqual(NS.Callout:Stats().endsAt, NS.RaceSample.EndsAt(), "counted to the sample's endsAt")
    play(S, 4.8)
    assertEqual(said(NS), "STOP", "STOP at the buzzer")
    playUntil(S, function() return NS.RaceWindow.View().key == "result" end, 12)
    assertEqual(toastKey(NS), "sim-race-newbest", "the new-best toast")
    assertEqual(said(NS), "NEW_BEST", "and NEW_BEST")
    untouched(S)
    NS.Preview.Stop()
    assertNil(toastKey(NS), "the stop takes the sim's toast down")
    assertNil(said(NS), "and the call-out")
    untouched(S)
end)

test("showcase: sim race-incomplete and race-died say FAILED as they end; race-behind earns nothing", function()
    if forever() then return end
    for _, key in ipairs({ "race-incomplete", "race-died" }) do
        local S = fresh()
        local NS = S.NS
        sim(S, key)
        play(S, NS.MockFights.FIRST_HIT + (key == "race-died" and 6 or 9) + 0.2)
        assertEqual(said(NS), "FAILED", key .. ": FAILED as it ends")
        play(S, 10)
        assertNil(toastKey(NS), key .. ": no toast")
        NS.Preview.Stop()
        assertNil(said(NS), key .. ": the stop takes it down")
        untouched(S)
    end
    local S = fresh()
    local NS = S.NS
    sim(S, "race-behind")
    play(S, NS.MockFights.FIRST_HIT + 45)
    assertEqual(NS.RaceWindow.View().key, "result")
    assertNil(toastKey(NS), "behind the best: no toast")
    assertTrue(said(NS) ~= "NEW_BEST", "and no NEW_BEST")
    NS.Preview.Stop()
end)

test("showcase: Race mode off keeps the samples' words off", function()
    if forever() then return end
    local NS = fresh().NS
    assertTrue(NS.Countdown.SampleSay("NEW_BEST"))
    NS.Countdown.EndSample()
    assertNil(said(NS))
    assertTrue(NS.SetByPath("race.enabled", false))
    assertFalse(NS.Countdown.SampleSay("NEW_BEST"), "Race mode off")
    assertTrue(NS.SetByPath("race.enabled", true))
    assertFalse(NS.Countdown.SampleSay("STOP"), "only the samples' words")
    assertFalse(NS.Countdown.SampleSay("TIME_UP"))
end)

-- ── the sim's fights (both clients) ─────────────────────────────────────────────────────────────

test("showcase: sim newbest toasts the fight (toast.fights) and says NEW_BEST on Retail; stop clears both", function()
    local S = fresh()
    local NS = S.NS
    assertTrue(NS.SetByPath("toast.fights", true))
    sim(S, "newbest")
    playUntil(S, function() return NS.Hud.State() == "over" end, NS.Sim.LENGTH + NS.Sim.SETTLE + 0.5, 0.25)
    assertEqual(toastKey(NS), "sim-newbest", "the new-best toast")
    if NS.Callout then assertEqual(said(NS), "NEW_BEST", "the call-out says NEW_BEST") end
    untouched(S)
    NS.Preview.Stop()
    assertNil(toastKey(NS), "the stop takes the toast down")
    if NS.Callout then assertNil(said(NS), "and the call-out") end
    untouched(S)
    -- Behind the best: nothing.
    sim(S, "behind")
    play(S, NS.Sim.LENGTH + NS.Sim.SETTLE + 0.5, 0.25)
    assertNil(toastKey(NS), "behind: no toast")
    if NS.Callout then assertNil(said(NS), "behind: no call-out") end
    NS.Preview.Stop()
    untouched(S)
end)

test("showcase: a real toast outlives the samples' cleanup", function()
    local NS = fresh().NS
    assertTrue(NS.BestToast.Test())
    assertEqual(toastKey(NS), NS.BestToast.SAMPLE)
    NS.BestToast.EndSample()
    assertEqual(toastKey(NS), NS.BestToast.SAMPLE, "Test toast's sample is not the preview's")
end)
