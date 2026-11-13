-- tests/test_race_resume.lua — a race carried on after a /reload (Race mode plan Task B2): DPS Race's
-- resume cases (its tests/test_race_resume.lua @f8078c7) on Combat Trail's fight. A race is written to
-- db.global.pendingRaces[charKey] at its first hit and cleared at its result or cancel; Race.Resume
-- (OnEnable and the stand-up) rebuilds it, and Fight.Adopt gives it back the fight its meter session
-- belongs to. Still in combat with time left it keeps running; past the buzzer it is stopping and
-- flagged reloaded; out of combat it is read at once (incomplete before its buzzer); a session gone is
-- lost; an armed race with no first hit is dropped (Review focus 2). Every case runs through the REAL
-- Fight, Recorder and meter (tests/race_fixture.lua's F.reload is the /reload: a new instance on the
-- same SavedVariables). Race mode is Retail's: every case but the WoW Forever one runs on Retail only.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local F = dofile(T.root .. "/tests/race_fixture.lua")(T)

local function forever() return T.NS.Compat.IsForever() end

local DAMAGE = F.SESSION.damage

-- A 30 s race (armed at 100, the first hit at 102, the buzzer due at 132) with damage each second from
-- 103 to `to`, the timers serviced as it goes. Answers the state table and the first hit.
local function raceTo(to, length)
    local S = F.fresh()
    assert(F.arm(S, length or 30))
    local start = F.pull(S)
    F.damage(S, 25, start + 1, to, 1)
    return S, start
end

-- ── the slot ───────────────────────────────────────────────────────────────────────────────────

test("resume: the slot is written at the first hit, plain, and nothing reaches the fight store", function()
    if forever() then return end
    local S = F.fresh()
    assertTrue(F.arm(S, 30))
    assertNil(F.slot(S), "nothing is written at the arm")
    local start = F.pull(S)
    local slot = F.slot(S)
    assertTrue(slot ~= nil, "written at the first hit")
    assertEqual(slot.race.status, "running")
    assertEqual(slot.race.length, 30)
    assertEqual(slot.startedAt, start)
    assertEqual(slot.sessions[1], 25)
    assertEqual(slot.snapshot.target.creatureID, F.DUMMY, "the pull's target, for the record")
    assertEqual(type(slot.date), "number")
    assertNil(F.findSecret(slot), "plain fields only")
    F.damage(S, 25, start + 1, start + 8, 1)
    assertEqual(slot.lastDamage, 8, "the last update's offset follows the race")
    assertEqual(S.NS.Recorder.Count(), 0, "the fight store is untouched mid-race")
end)

test("resume: the slot is cleared at the result and at a cancel", function()
    if forever() then return end
    local S = F.fresh()
    F.whole(S, 30)
    assertEqual(S.NS.Race.State(), "result")
    assertNil(F.slot(S), "cleared at the result")
    local T2 = F.fresh()
    assertTrue(F.arm(T2, 30))
    F.pull(T2)
    assertTrue(F.slot(T2) ~= nil)
    assertTrue(T2.NS.Race.Cancel())
    assertNil(F.slot(T2), "cleared at a cancel")
end)

test("resume: arming refuses while this character's slot waits to be resumed", function()
    if forever() then return end
    local S = F.fresh()
    local key = S.NS.Bests.CharKey(S.NS.Identity.Who())
    S.NS.db.global.pendingRaces[key] = { race = { length = 30, status = "stopping" }, sessions = { 25 } }
    local ok, why = F.arm(S, 30)
    assertFalse(ok)
    assertEqual(why, "pending")
end)

-- ── the resume ─────────────────────────────────────────────────────────────────────────────────

test("resume: running past buzzer becomes stopping+reloaded", function()
    if forever() then return end
    local S = raceTo(125)
    local G = F.reload(S, { now = 147, inCombat = true })
    local R = G.NS.Race
    assertEqual(R.State(), "stopping", "never left hanging in running")
    assertTrue(R.Current().flags.reloaded)
    F.near(R.SinceBuzzer(), 15)
    assertEqual(F.states(G), "idle>stopping")
    assertEqual(G.NS.Fight.State(), "combat", "the fight its session belongs to is back")
    assertEqual(R.Fight(), G.NS.Fight.Current())
    assertEqual(#F.records(G), 0, "still in combat: wait for the combat end")
    F.damage(G, 25, 147, 150, 1)
    F.settle(G, 151)
    assertEqual(R.State(), "result")
    local records = F.records(G)
    assertEqual(#records, 1, "saved once")
    local r = records[1]
    assertEqual(r.race.status, "complete")
    assertEqual(r.race.score, DAMAGE)
    F.near(r.race.dps, DAMAGE / 30, "race DPS")
    assertTrue(r.race.flags.reloaded)
    assertEqual(r.identity.targetCreatureID, F.DUMMY, "the pull's target, kept in the slot")
    assertEqual(r.who.name, S.NS.Identity.Who().name)
    assertTrue(r.casts == nil or r.casts == "", "the casts before the reload are not recovered")
    assertNil(r.usage, "nor the usage")
    assertNil(F.slot(G), "the slot is cleared")
end)

test("resume: a resumed race keeps its first hit's offset; a slot without the combat entry has none", function()
    if forever() then return end
    local S = raceTo(125)   -- combat entry at 101, the first hit at 102
    local G = F.reload(S, { now = 147, inCombat = true })
    F.settle(G, 148)
    assertEqual(F.records(G)[1].race.firstHit, 1.0, "the adopted fight keeps the pull's combat entry")
    S = raceTo(125)
    F.slot(S).startT = nil
    G = F.reload(S, { now = 147, inCombat = true })
    F.settle(G, 148)
    assertEqual(F.records(G)[1].race.firstHit, 0, "the adopted fight starts on the first hit: no shift")
end)

test("resume: running before buzzer keeps running with remaining time", function()
    if forever() then return end
    local S = raceTo(110)
    local G = F.reload(S, { now = 112, inCombat = true })
    local R = G.NS.Race
    assertEqual(R.State(), "running")
    F.near(R.TimeLeft(), 20)
    F.near(R.Elapsed(), 10)
    assertFalse(R.Current().flags.reloaded, "nothing after the buzzer was missed")
    F.run(G, 131.9)
    assertEqual(F.count(G, "RACE_BUZZER"), 0)
    F.run(G, 132)
    assertEqual(R.State(), "stopping")
    assertEqual(F.count(G, "RACE_BUZZER"), 1)
    F.cast(G, 133.4, "start", 29722)
    assertEqual(#R.Current().flags.lateCasts, 1, "cast tracking is back on")
end)

test("resume: stopping out of combat reads immediately", function()
    if forever() then return end
    local S = raceTo(131)
    F.run(S, 132)
    assertEqual(S.NS.Race.State(), "stopping")
    F.leave(S, 133)
    local G = F.reload(S, { now = 134 })
    assertEqual(G.NS.Fight.State(), "settling", "the fight is read without the settle's wait")
    F.run(G, 134)
    local R = G.NS.Race
    assertEqual(R.State(), "result")
    local r = F.records(G)[1]
    assertEqual(r.race.status, "complete")
    assertEqual(r.race.score, DAMAGE)
    assertEqual(F.count(G, "RACE_RESULT"), 1)
    assertTrue(r.race.flags.reloaded, "a reload between the buzzer and the read missed what was cast")
    local timers = G.NS.Fight.Timers()
    assertNil(timers.tick, "nothing left ticking")
    assertNil(timers.settle, "nothing left settling")
end)

test("resume: stopping in combat waits for the combat end", function()
    if forever() then return end
    local S = raceTo(131)
    F.run(S, 132)
    local G = F.reload(S, { now = 140, inCombat = true })
    F.run(G, 150)
    assertEqual(G.NS.Race.State(), "stopping")
    assertEqual(#F.records(G), 0)
    F.settle(G, 151)
    assertEqual(F.records(G)[1].race.status, "complete")
end)

test("resume: an incomplete race waiting for its read stays incomplete", function()
    if forever() then return end
    local S = raceTo(113)
    F.leave(S, 114)
    assertEqual(S.NS.Race.Current().endedAt, 12)
    local G = F.reload(S, { now = 116 })
    F.run(G, 116)
    assertEqual(G.NS.Race.State(), "result")
    local r = F.records(G)[1]
    assertEqual(r.race.status, "incomplete")
    F.near(r.race.dps, DAMAGE / 12)
    assertFalse(r.race.flags.reloaded == true, "it never reached its buzzer")
end)

test("resume: an incomplete race whose fight carried on keeps its own race clock after a reload", function()
    if forever() then return end
    local S, start = raceTo(110, 60)
    F.leave(S, start + 9)
    F.enter(S, start + 10)            -- Feign Death inside Combat Trail's grace: the fight carries on
    F.damage(S, 25, start + 11, start + 30, 1)
    local G = F.reload(S, { now = start + 31, inCombat = true })
    F.damage(G, 25, start + 32, start + 40, 1)
    F.settle(G, start + 41)
    local r = F.records(G)[1]
    assertEqual(r.race.status, "incomplete")
    assertEqual(r.race.endedAt, 9)
    assertTrue(r.race.flags.carriedOn, "the record says how its DPS was taken")
    F.near(r.race.dps, DAMAGE / 41, "over the first hit to the fight's end (ruling X16), not endedAt")
end)

test("resume: a carried-on incomplete race read at the resume divides by its last damage, not the reload", function()
    if forever() then return end
    local S, start = raceTo(110, 60)
    F.leave(S, start + 9)
    F.enter(S, start + 10)
    F.damage(S, 25, start + 11, start + 30, 1)
    F.leave(S, start + 31)
    local G = F.reload(S, { now = start + 50 })
    F.run(G, start + 50)
    local r = F.records(G)[1]
    assertEqual(r.race.status, "incomplete")
    F.near(r.race.dps, DAMAGE / 30, "over the first hit to its last damage update")
end)

test("resume: running before the buzzer with combat already over is incomplete and read at once", function()
    if forever() then return end
    local S = raceTo(110)
    local G = F.reload(S, { now = 112 })
    F.run(G, 112)
    local R = G.NS.Race
    assertEqual(R.State(), "result", "combat ended unseen: never left waiting for an edge")
    local r = F.records(G)[1]
    assertEqual(r.race.status, "incomplete")
    assertEqual(r.race.endedAt, 10, "ended no later than the resume")
    F.near(r.race.dps, DAMAGE / 10)
    assertEqual(F.count(G, "RACE_BUZZER"), 0, "no buzzer left armed")
    assertTrue(F.arm(G, 30, 113), "a new race can be armed")
end)

test("resume: session gone becomes lost", function()
    if forever() then return end
    for _, past in ipairs({ false, true }) do
        local S = raceTo(110)
        if past then F.run(S, 132) end
        local label = past and "stopping" or "running"
        local G = F.reload(S, { now = 135, inCombat = true, sessions = {} })
        assertEqual(G.NS.Race.State(), "result", label)
        assertEqual(F.count(G, "RACE_RESULT"), 1, label .. ": the result is heard")
        local heard = F.last(G, "RACE_RESULT")
        assertNil(heard[2], label .. ": nothing stored")
        assertEqual(heard[3].status, "lost", label)
        assertEqual(#F.records(G), 0, label)
        assertNil(F.slot(G), label .. ": the slot is cleared")
        assertEqual(G.NS.Fight.State(), "idle", label .. ": no fight adopted")
    end
end)

test("resume: a slot that cannot be raced is cleared, and a new race can be armed", function()
    if forever() then return end
    for _, bad in ipairs({ "x", { race = { status = "running" }, sessions = { 25 } },
                           { race = { length = 30, status = "running" }, sessions = {} },
                           { race = { length = 30, status = "result" }, sessions = { 25 }, startedAt = 90 } }) do
        local S = F.fresh()
        local key = S.NS.Bests.CharKey(S.NS.Identity.Who())
        S.NS.db.global.pendingRaces[key] = bad
        local G = F.reload(S, { now = 100 })
        assertEqual(G.NS.Race.State(), "idle")
        assertNil(F.slot(G), "a stale slot is cleared")
        assertEqual(F.states(G), "")
        assertTrue(F.arm(G, 30, 101))
    end
end)

test("resume: nothing stored leaves the race idle and touches nothing", function()
    if forever() then return end
    local S = F.fresh()
    local G = F.reload(S)
    assertEqual(G.NS.Race.State(), "idle")
    assertEqual(F.states(G), "")
    assertEqual(G.NS.Fight.State(), "idle")
end)

test("resume: an armed race with no first hit is dropped and the window is idle", function()
    if forever() then return end
    local S = F.fresh()
    assertTrue(F.arm(S, 30))
    local G = F.reload(S, { now = 105 })
    local R = G.NS.Race
    assertEqual(R.State(), "idle", "no ghost race")
    assertNil(R.Current())
    assertNil(F.slot(G))
    assertEqual(F.trail(G, true), "", "nothing sent")
    assertTrue(F.arm(G, 30, 106), "armed again")
end)

test("resume: a slot another character left is not resumed here and does not block the arm", function()
    if forever() then return end
    local S = raceTo(110)
    local slots = S.NS.db.global.pendingRaces
    local key = S.NS.Bests.CharKey(S.NS.Identity.Who())
    local other = "Otherchar|Testrealm|retail"
    slots[other], slots[key] = slots[key], nil
    local G = F.reload(S, { now = 112, inCombat = false })
    assertEqual(G.NS.Race.State(), "idle", "another character's race was resumed")
    assertTrue(G.NS.db.global.pendingRaces[other] ~= nil, "left pending for its own character")
    assertEqual(G.NS.db.global.pendingRaces[other].race.status, "running")
    assertTrue(F.arm(G, 30, 113), "another character's slot never blocks the arm")
end)

test("resume: after a restart of the machine the clock comes from the stored date", function()
    if forever() then return end
    local S = raceTo(105)
    local wall = os.time()
    F.slot(S).date = wall - 5                   -- the first hit was 5 s ago, on a clock that started over
    -- The wall clock frozen at this read: a second ticking over before the resume reads time() again
    -- would put the elapsed a second out.
    local G = F.reload(S, { now = 50, inCombat = true, mutate = function(m)
        m.time = function() return wall end
    end })
    local R = G.NS.Race
    assertEqual(R.State(), "running")
    F.near(R.Elapsed(), 5)
    F.near(R.TimeLeft(), 25)
end)

-- ── the timeline across the reload ─────────────────────────────────────────────────────────────

test("resume: a reload that outlasts the restart gap while DoTs tick is not a restart", function()
    if forever() then return end
    local S = raceTo(131)
    F.run(S, 132)
    F.hit(S, 133, 25)                         -- the last update heard before the reload, +1s
    local G = F.reload(S, { now = 140, inCombat = true })   -- the loading screen took 7s
    F.hit(G, 140.2, 25)                       -- the first update heard after it: 7.2s after the last
    F.hit(G, 142, 25)
    F.settle(G, 143)
    local r = F.records(G)[1]
    assertEqual(r.race.status, "complete")
    assertNil(r.race.flags.restartedAt, "the gap spans the reload, not a stop in the damage")
end)

test("resume: the tail and a restart heard before a /reload survive it", function()
    if forever() then return end
    local S = raceTo(131)
    F.run(S, 132)
    F.hit(S, 133, 25)
    F.hit(S, 143, 25)                         -- 10s quiet, then damage again: a restart at +11
    F.leave(S, 144)
    local G = F.reload(S, { now = 147 })
    F.run(G, 147)
    assertEqual(G.NS.Race.State(), "result")
    local r = F.records(G)[1]
    assertEqual(r.race.status, "complete")
    F.near(r.race.tail, 11, "not +0.0s: the stamps before the reload count")
    F.near(r.race.flags.restartedAt, 11)
end)

test("resume: the stamps before a /reload keep a DoT tail across it from looking like a restart", function()
    if forever() then return end
    local S = raceTo(131)
    F.run(S, 132)
    F.hit(S, 133, 25)
    F.hit(S, 137, 25)
    local G = F.reload(S, { now = 138, inCombat = true })
    assertEqual(G.NS.Race.State(), "stopping")
    F.hit(G, 140, 25)                         -- 3s after the last stamp before the reload: a tail tick
    F.settle(G, 141)
    local r = F.records(G)[1]
    assertEqual(r.race.status, "complete")
    assertNil(r.race.flags.restartedAt, "8s after the buzzer, but only 3s after the last update")
    F.near(r.race.tail, 8)
end)

-- ── a shared session across the reload (Review focus 5) ────────────────────────────────────────

local EARLIER = { damage = 200000, dps = 10000, duration = 20,
                  spells = { { id = 29722, dmg = 150000, dps = 7500 }, { id = 348, dmg = 50000, dps = 2500 } } }
local CARRIED = { damage = 1200000, dps = 20000, duration = 60,
                  spells = { { id = 29722, dmg = 950000, dps = 15800 }, { id = 348, dmg = 250000, dps = 4100 } } }

test("resume: a shared session resumed is still netted against the arm's baseline, saved once", function()
    if forever() then return end
    local S = F.fresh()
    S.meter.SetSession(5, EARLIER)
    assertTrue(F.arm(S, 10))
    F.enter(S, 101)
    S.meter.SetSession(5, CARRIED)
    F.hit(S, 102, 5)
    assertTrue(S.NS.Race.Current().flags.sharedSession)
    F.damage(S, 5, 103, 110, 1)
    local G = F.reload(S, { now = 113, inCombat = true, sessions = { [5] = CARRIED } })
    assertEqual(G.NS.Race.State(), "stopping")
    F.settle(G, 114)
    local records = F.records(G)
    assertEqual(#records, 1, "saved once")
    assertEqual(records[1].race.score, 1000000, "the arm's 200000 still comes off")
    assertTrue(records[1].race.flags.sharedSession)
    assertTrue(records[1].race.flags.reloaded)
end)

-- ── the stand-down and stand-up ────────────────────────────────────────────────────────────────

test("resume: a stand-down mid-race whose combat ends unseen never hangs in stopping", function()
    if forever() then return end
    local S = raceTo(110)
    S.NS.SetByPath("general.enabled", false)
    S.M.__inCombat = false                    -- combat drops while nothing is listening
    S.M.InCombatLockdown = function() return false end
    F.at(S, 115)
    S.NS.SetByPath("general.enabled", true)
    F.run(S, 115)
    F.run(S, 700)
    local R = S.NS.Race
    assertEqual(R.State(), "result")
    local r = F.records(S)[1]
    assertEqual(r.race.status, "incomplete")
    assertEqual(r.race.endedAt, 13)
end)

test("resume: an armed race is dropped by the stand-down and not resumed", function()
    if forever() then return end
    local S = F.fresh()
    assertTrue(F.arm(S, 30))
    S.NS.SetByPath("general.enabled", false)
    S.NS.SetByPath("general.enabled", true)
    assertEqual(S.NS.Race.State(), "idle")
    assertNil(F.slot(S))
end)

test("resume: a stood-down login resumes nothing until the addon is enabled", function()
    if forever() then return end
    local S = raceTo(110)
    S.NS.db.profile.general.enabled = false
    local G = F.reload(S, { now = 112, inCombat = true })
    assertEqual(G.NS.Race.State(), "idle")
    assertTrue(F.slot(G) ~= nil, "kept for the stand-up")
    G.NS.SetByPath("general.enabled", true)
    assertEqual(G.NS.Race.State(), "running", "the stand-up resumes it")
    F.near(G.NS.Race.TimeLeft(), 20)
end)

test("resume: nothing is resumed on WoW Forever", function()
    if not forever() then return end
    local S = F.fresh()
    local key = S.NS.Bests.CharKey(S.NS.Identity.Who())
    local slot = { race = { length = 30, status = "running" }, sessions = { 25 }, startedAt = 90, date = os.time() }
    S.NS.db.global.pendingRaces[key] = slot
    local G = F.reload(S, { now = 100, inCombat = true })
    assertEqual(G.NS.Race.State(), "idle")
    assertEqual(G.NS.Fight.State(), "idle")
    assertTrue(G.NS.db.global.pendingRaces[key] ~= nil, "left as it is")
end)
