-- tests/test_race.lua — modules/Race.lua and modules/RaceWatchers.lua on the fight pipeline (Race mode
-- plan Task B1): DPS Race's race-lifecycle cases (its tests/test_race.lua @f8078c7) moved onto Combat
-- Trail's fight, through the REAL Fight, Recorder and meter (tests/race_fixture.lua fires the events).
-- The arm and its refusals, the clock on the fight's first hit, a non-dummy pull, the buzzer, the
-- casts after it, the combat end and the death before it, the timeline's tail and restart, a meter
-- reset, a shared session netted against the arm, *Stop Now* through Fight.Hurry, Cancel, the arm's
-- snapshots, the order on the bus and the event wiring per state. Race mode is Retail's: every case
-- but the WoW Forever refusal runs on the Retail kit profile only.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local F = dofile(T.root .. "/tests/race_fixture.lua")(T)

local function forever() return T.NS.Compat.IsForever() end

local function fresh(opts) return F.fresh(opts) end

-- ── constants and the shape ────────────────────────────────────────────────────────────────────

test("race: the states, the lengths and the timings are the plan's", function()
    local S = fresh()
    local NS = S.NS
    local R = NS.Race
    assertEqual(R.STATE.IDLE, "idle")
    assertEqual(R.STATE.ARMED, "armed")
    assertEqual(R.STATE.RUNNING, "running")
    assertEqual(R.STATE.STOPPING, "stopping")
    assertEqual(R.STATE.RESULT, "result")
    assertEqual(table.concat(R.LENGTHS, ","), "30,60,120,180,300")
    assertEqual(R.MIN_LENGTH, 10)
    assertEqual(R.MAX_LENGTH, 900)
    local d = NS.defaults.profile.race
    assertEqual(d.defaultLength, 60)
    assertEqual(d.grace, 1.0)
    assertEqual(d.restartGap, 6)
    assertEqual(d.hintDelay, 15)
    assertEqual(NS.RaceScoring.QUIET_BEFORE_READ, 2.5)
    assertEqual(R.State(), "idle")
    assertNil(R.Current())
    for _, key in ipairs({ "RACE_STATE_CHANGED", "RACE_ARMED", "RACE_STARTED", "RACE_BUZZER", "RACE_RESULT",
                           "RACE_CANCELED", "FIGHT_FIRST_HIT" }) do
        assertEqual(type(NS.MSG[key]), "string", key .. " is declared")
    end
    assertEqual(NS.MSG.RACE_RESULT, "Ka0s_CombatTrail_RaceResult")
end)

-- ── arming ─────────────────────────────────────────────────────────────────────────────────────

test("race: arming refuses on WoW Forever and registers nothing there", function()
    if not forever() then return end
    local S = fresh()
    local ok, why = F.arm(S, 30)
    assertFalse(ok)
    assertEqual(why, "client")
    assertEqual(S.NS.Race.State(), "idle")
    local target, frame = S.NS.RaceWatchers.Targets()
    assertNil(target, "no race event target on WoW Forever")
    assertNil(frame, "no race cast frame on WoW Forever")
    -- A dummy pull on Forever is a fight: the race receivers are absent.
    S.meter.SetSession(25, F.SESSION)
    F.enter(S, 101)
    assertNil(S.NS.Fight.Current().race, "no race part on WoW Forever")
end)

test("race: arm refuses while armed or racing, out of range, in combat, settling, and with the meter unavailable", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    local ok, why = F.arm(S, 9)
    assertFalse(ok)
    assertEqual(why, "bad_length", "under 10 s")
    ok, why = F.arm(S, 901)
    assertFalse(ok)
    assertEqual(why, "bad_length", "over 15:00")
    S.meter.SetAvailable(false, "Not in this zone")
    local detail
    ok, why, detail = F.arm(S, 30)
    assertFalse(ok)
    assertEqual(why, "meter_unavailable")
    assertEqual(detail, "Not in this zone", "the client's reason, verbatim")
    S.meter.SetAvailable(true)
    S.M.__inCombat = true
    ok, why = F.arm(S, 30)
    assertFalse(ok)
    assertEqual(why, "in_combat")
    S.M.__inCombat = false
    assertTrue(F.arm(S, 30))
    assertEqual(R.State(), "armed")
    ok, why = F.arm(S, 60)
    assertFalse(ok)
    assertEqual(why, "busy", "already armed")
    F.pull(S)
    ok, why = F.arm(S, 60)
    assertFalse(ok, "racing")
    assertTrue(why == "busy" or why == "in_combat")
end)

test("race: arm refuses while a fight is still settling", function()
    if forever() then return end
    local S = fresh()
    S.meter.SetSession(25, F.SESSION)
    F.enter(S, 100)
    F.hit(S, 101, 25)
    F.leave(S, 110)
    assertEqual(S.NS.Fight.State(), "settling")
    local ok, why = F.arm(S, 30, 111)
    assertFalse(ok)
    assertEqual(why, "settling", "a pull inside the grace would carry that fight on")
    F.run(S, 120)
    assertEqual(S.NS.Fight.State(), "idle")
    assertTrue(F.arm(S, 30, 121))
end)

test("race: arm refuses while stood down", function()
    if forever() then return end
    local S = fresh()
    S.NS.SetByPath("general.enabled", false)
    local ok, why = F.arm(S, 30)
    assertFalse(ok)
    assertEqual(why, "disabled")
end)

test("race: an arm remembers its length, and the next arm defaults to it", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertEqual(R.DefaultLength(), 60, "the profile's default before any arm")
    assertTrue(R.Arm(120))
    assertEqual(S.NS.db.profile.race.lastLength, 120)
    R.Cancel()
    assertEqual(R.DefaultLength(), 120)
    assertTrue(R.Arm())
    assertEqual(R.Current().length, 120, "Arm() arms the remembered length")
end)

-- ── the pull and the clock ─────────────────────────────────────────────────────────────────────

test("race: the first hit on a dummy starts the clock, on the fight's firstHitT", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertTrue(F.arm(S, 30))
    assertEqual(F.trail(S), "RACE_ARMED")
    S.meter.SetSession(25, F.SESSION)
    F.enter(S, 101)
    local fight = S.NS.Fight.Current()
    assertEqual(R.State(), "armed", "combat entry alone starts nothing")
    assertEqual(fight.race, R.Current(), "the dummy's fight carries the race part")
    assertEqual(fight.race.kind, "boss", "Raider's Training Dummy is a boss dummy")
    assertNil(R.Elapsed())
    F.hit(S, 102.5, 25)
    assertEqual(R.State(), "running")
    assertEqual(fight.firstHitT, 102.5)
    F.near(R.Elapsed(), 0, "the clock is the first hit")
    F.near(R.TimeLeft(), 30)
    F.at(S, 112.5)
    F.near(R.TimeLeft(), 20)
    -- RACE_STARTED is sent from inside FIGHT_FIRST_HIT's dispatch: the bus gives no receiver order,
    -- so the two may be heard either way round; both follow the pull's FIGHT_STARTED.
    local trail = F.trail(S)
    assertTrue(trail == "RACE_ARMED,FIGHT_STARTED,FIGHT_FIRST_HIT,RACE_STARTED"
        or trail == "RACE_ARMED,FIGHT_STARTED,RACE_STARTED,FIGHT_FIRST_HIT", trail)
    local started = F.last(S, "RACE_STARTED")
    assertEqual(started[2], R.Current())
    assertEqual(started[3], fight)
    assertEqual(F.states(S), "idle>armed,armed>running")
end)

test("race: an armed race cancels when a non-dummy pull starts, and that pull is a normal fight", function()
    if forever() then return end
    local S = fresh({ target = F.BOAR_GUID })
    local R = S.NS.Race
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    assertEqual(R.State(), "idle", "the arm is canceled")
    assertEqual(F.last(S, "RACE_CANCELED")[2], "not_dummy")
    assertNil(S.NS.Fight.Current().race, "no race part on the fight")
    F.damage(S, 25, start + 1, start + 40, 1)
    F.settle(S, start + 41)
    local records = F.records(S)
    assertEqual(#records, 1, "the pull is saved as a fight")
    assertNil(records[1].race)
    assertEqual(F.count(S, "RACE_RESULT"), 0)
end)

test("race: a pull with no target cancels the arm", function()
    if forever() then return end
    local S = fresh({ target = false })
    assertTrue(F.arm(S, 30))
    F.pull(S)
    assertEqual(S.NS.Race.State(), "idle")
    assertEqual(F.last(S, "RACE_CANCELED")[2], "not_dummy")
end)

test("race: an armed pull that never hits keeps the arm for the next pull", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertTrue(F.arm(S, 30))
    F.enter(S, 101)       -- no session, no damage: the fight never binds
    F.settle(S, 103)
    assertEqual(R.State(), "armed", "still armed")
    assertNil(R.Fight(), "the dead pull is let go")
    F.pull(S, 120)
    assertEqual(R.State(), "running", "the next pull races")
end)

-- ── the buzzer ─────────────────────────────────────────────────────────────────────────────────

test("race: buzzer at start+length moves to stopping and emits RACE_BUZZER, never early", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.run(S, start + 29.9)
    assertEqual(R.State(), "running", "a timer serviced early waits for its time")
    F.run(S, start + 30)
    assertEqual(R.State(), "stopping")
    assertEqual(F.count(S, "RACE_BUZZER"), 1)
    assertEqual(F.last(S, "RACE_BUZZER")[2], R.Current())
    assertEqual(R.TimeLeft(), 0)
    F.at(S, start + 32)
    F.near(R.SinceBuzzer(), 2)
    assertEqual(S.NS.Fight.State(), "combat", "the fight stays in combat")
    assertEqual(#F.records(S), 0, "nothing is written mid-race")
end)

-- ── the read and the result ────────────────────────────────────────────────────────────────────

test("race: a complete race is read after the settle and saved once, as a race with its score and DPS", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    F.whole(S, 30, 1)
    assertEqual(R.State(), "result")
    local records = F.records(S)
    assertEqual(#records, 1, "saved once")
    local race = records[1].race
    assertEqual(race.status, "complete")
    assertEqual(race.length, 30)
    assertEqual(race.kind, "boss")
    assertEqual(race.score, 1539711, "the score is the fight's merged total")
    F.near(race.dps, 1539711 / 30, "the DPS is the score over the length")
    assertEqual(race.grace, 1.0)
    assertEqual(race.restartGap, 6)
    assertNil(race.endedAt)
    assertEqual(R.Result(), records[1])
    local result = F.last(S, "RACE_RESULT")
    assertEqual(result[2], records[1], "RACE_RESULT carries the stored record")
    assertEqual(result[3], R.Current())
    assertNil(F.findSecret(records[1]), "nothing secret in the record")
end)

test("race: the race part is on the fight before Recorder builds it, and RACE_RESULT follows FIGHT_SAVED", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local seen, stored, best
    local rx = NS.NewBusTarget()
    rx:RegisterMessage(NS.MSG.FIGHT_SAVED, function(_, record)
        seen = record.race and record.race.status
    end)
    -- RACE_RESULT is sent from inside FIGHT_SAVED's dispatch, after the store and the bests moved.
    rx:RegisterMessage(NS.MSG.RACE_RESULT, function(_, record)
        stored = NS.db.global.fights[record.id] == record
        best = NS.Bests.For(record) == record
    end)
    F.whole(S, 30, 1)
    assertEqual(seen, "complete", "the saved record already carries the finalized part")
    assertTrue(stored, "the record is in the store when RACE_RESULT is heard")
    assertTrue(best, "and the boards already count it")
    local trail = F.trail(S)
    local at = {}
    for i, name in ipairs({ "RACE_BUZZER", "FIGHT_ENDED", "FIGHT_SAVED", "RACE_RESULT" }) do
        at[i] = trail:find(name, 1, true)
        assertTrue(at[i] ~= nil, name .. " in " .. trail)
    end
    -- FIGHT_ENDED, FIGHT_SAVED and RACE_RESULT nest (each is sent inside the one before), so only the
    -- buzzer's place among them is an order a receiver can see.
    assertTrue(at[1] < at[2] and at[1] < at[3] and at[1] < at[4], trail)
    assertEqual(F.states(S), "idle>armed,armed>running,running>stopping,stopping>result")
end)

test("race: a race is saved however short, past the minimum length", function()
    if forever() then return end
    local S = fresh()
    S.NS.db.profile.history.minLength = 30
    F.whole(S, 10, 1)
    assertEqual(#F.records(S), 1)
    assertEqual(F.records(S)[1].race.length, 10)
end)

test("race: combat end before the buzzer -> incomplete with endedAt", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 12, 1)
    F.leave(S, start + 12.5)
    assertEqual(R.State(), "stopping")
    assertEqual(R.Current().endedAt, 12.5)
    F.run(S, start + 31)
    assertEqual(F.count(S, "RACE_BUZZER"), 0, "the buzzer never goes")
    F.run(S, start + 40)
    local race = F.records(S)[1].race
    assertEqual(race.status, "incomplete")
    assertEqual(race.endedAt, 12.5)
    F.near(race.dps, 1539711 / 12.5, "the DPS is over endedAt")
end)

test("race: Feign Death before the buzzer ends the race as incomplete while the fight carries on", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.leave(S, start + 10)
    F.enter(S, start + 11)           -- inside Combat Trail's grace: the same fight
    assertEqual(S.NS.Fight.State(), "combat")
    assertEqual(R.State(), "stopping", "the race ended at the combat end")
    assertEqual(R.Current().endedAt, 10)
    F.damage(S, 25, start + 12, start + 20, 1)
    F.settle(S, start + 21)
    local records = F.records(S)
    assertEqual(#records, 1)
    assertEqual(records[1].race.status, "incomplete")
    assertEqual(records[1].race.endedAt, 10)
    assertTrue(records[1].duration > 10, "the fight's own record runs on")
end)

test("race: death -> incomplete, died flag", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.die(S, start + 8)
    assertEqual(R.State(), "stopping")
    assertTrue(R.Current().flags.died)
    assertEqual(R.Current().endedAt, 8)
    F.settle(S, start + 8.5)
    local race = F.records(S)[1].race
    assertEqual(race.status, "incomplete")
    assertTrue(race.flags.died)
end)

test("race: death after the buzzer flags died and the race stays complete", function()
    if forever() then return end
    local S = fresh()
    assertTrue(F.arm(S, 10))
    local start = F.pull(S)
    F.run(S, start + 10)
    F.die(S, start + 11)
    F.settle(S, start + 11.5)
    local race = F.records(S)[1].race
    assertEqual(race.status, "complete")
    assertTrue(race.flags.died)
end)

test("race: tail and combat end are stored relative to the buzzer", function()
    if forever() then return end
    local S = fresh()
    assertTrue(F.arm(S, 10))
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 10, 1)
    F.hit(S, start + 13.03, 25)
    F.settle(S, start + 14)
    local race = F.records(S)[1].race
    assertEqual(race.tail, 3.03)
    assertEqual(race.combatEnd, 4)
end)

test("race: restart after a 10s gap sets flags.restartedAt", function()
    if forever() then return end
    local S = fresh()
    assertTrue(F.arm(S, 10))
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 10, 1)
    F.hit(S, start + 11, 25)
    F.hit(S, start + 21, 25)
    assertEqual(S.NS.Race.Current().flags.restartedAt, 11, "flagged the moment it is heard")
    F.settle(S, start + 22)
    assertEqual(F.records(S)[1].race.flags.restartedAt, 11)
end)

test("race: updates for another session never move the timeline", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertTrue(F.arm(S, 10))
    local start = F.pull(S)
    F.run(S, start + 10)
    assertEqual(R.LastDamage(), 0)
    S.M.__fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 999)   -- another session, never bound
    assertEqual(R.LastDamage(), 0)
    S.M.__fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 3, 25)    -- another meter type
    assertEqual(R.LastDamage(), 0)
    F.hit(S, start + 11, 25)
    assertEqual(R.LastDamage(), 11)
end)

test("race: a sealed meter type or session ID is taken as the race's own, and nothing secret is kept", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertTrue(F.arm(S, 10))
    local start = F.pull(S)
    F.run(S, start + 10)
    F.at(S, start + 12)
    S.M.__fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", T.secret(0), T.secret(25))
    assertEqual(R.LastDamage(), 12, "a secret session counts as the fight's own (the tail reads longer)")
    assertNil(F.findSecret(R.Current()), "the part holds nothing secret")
end)

-- ── casts after the buzzer ─────────────────────────────────────────────────────────────────────

-- A race of 10 s whose buzzer has gone at start + 10.
local function pastBuzzer()
    local S = fresh()
    assertTrue(F.arm(S, 10))
    local start = F.pull(S)
    F.run(S, start + 10)
    assertEqual(S.NS.Race.State(), "stopping")
    return S, start + 10
end

local function lateCasts(S) return S.NS.Race.Current().flags.lateCasts end

test("race: cast started 0.5s after buzzer is not late at grace 1.0", function()
    if forever() then return end
    local S, buzzer = pastBuzzer()
    F.cast(S, buzzer + 0.5, "start", 29722)
    assertEqual(#lateCasts(S), 0)
end)

test("race: cast started 1.4s after buzzer is recorded as late with spellID", function()
    if forever() then return end
    local S, buzzer = pastBuzzer()
    F.cast(S, buzzer + 1.4, "start", 29722, "Cast-A")
    F.cast(S, buzzer + 3.9, "succeeded", 29722, "Cast-A")
    local list = lateCasts(S)
    assertEqual(#list, 1, "judged at its start, once")
    assertEqual(list[1].t, 1.4)
    assertEqual(list[1].spellID, 29722)
    F.settle(S, buzzer + 4)
    assertEqual(F.records(S)[1].race.flags.lateCasts[1].spellID, 29722, "kept on the record")
end)

test("race: a late cast of an ignored spell is still stored raw; the list is read, never applied, at capture", function()
    if forever() then return end
    local S, buzzer = pastBuzzer()
    F.cast(S, buzzer + 2, "succeeded", 5384)    -- Feign Death, on the default ignore list
    assertEqual(#lateCasts(S), 1)
    assertEqual(lateCasts(S)[1].spellID, 5384)
end)

test("race: cast that started before buzzer and succeeded after is not late", function()
    if forever() then return end
    local S = fresh()
    assertTrue(F.arm(S, 10))
    local start = F.pull(S)
    F.cast(S, start + 9.5, "start", 29722, "Cast-B")
    F.run(S, start + 10)
    F.cast(S, start + 12, "succeeded", 29722, "Cast-B")
    assertEqual(#lateCasts(S), 0)
end)

test("race: an empowered cast held across the buzzer is never late", function()
    if forever() then return end
    local S = fresh()
    assertTrue(F.arm(S, 10))
    local start = F.pull(S)
    F.cast(S, start + 9, "empower", 357208, "Cast-E")
    F.run(S, start + 10)
    F.cast(S, start + 13, "succeeded", 357208, "Cast-E")
    assertEqual(#lateCasts(S), 0)
end)

test("race: a channel begun after the grace is late once; its stop clears it", function()
    if forever() then return end
    local S, buzzer = pastBuzzer()
    F.cast(S, buzzer + 2, "channel", 234153, "Cast-C")
    F.cast(S, buzzer + 4, "channelStop", 234153, "Cast-C")
    F.cast(S, buzzer + 4.5, "succeeded", 234153, "Cast-D")
    assertEqual(#lateCasts(S), 2, "the channel at its start, then a later instant")
end)

test("race: an interrupted cast leaves nothing open; a later instant of the same spell is late", function()
    if forever() then return end
    local S, buzzer = pastBuzzer()
    F.cast(S, buzzer + 0.5, "start", 29722, "Cast-F")
    F.cast(S, buzzer + 1, "interrupted", 29722, "Cast-F")
    F.cast(S, buzzer + 2, "succeeded", 29722, "Cast-G")
    assertEqual(#lateCasts(S), 1)
    assertEqual(lateCasts(S)[1].t, 2)
end)

test("race: a cast matches its own success by castGUID, not by spell", function()
    if forever() then return end
    local S, buzzer = pastBuzzer()
    F.cast(S, buzzer + 0.5, "start", 29722, "Cast-H")
    F.cast(S, buzzer + 2, "succeeded", 29722, "Cast-I")    -- another cast of the same spell
    assertEqual(#lateCasts(S), 1, "the other cast is an instant judged at its success")
end)

test("race: secret spell IDs and castGUIDs are judged without ever being stored", function()
    if forever() then return end
    local S, buzzer = pastBuzzer()
    F.cast(S, buzzer + 2, "succeeded", T.secret(29722), T.secret("Cast-J"))
    local list = lateCasts(S)
    assertEqual(#list, 1, "judged")
    assertNil(list[1].spellID, "a sealed spell is kept as nothing")
    assertEqual(list[1].t, 2)
    assertNil(F.findSecret(S.NS.Race.Current()))
end)

test("race: auto-repeat successes after the buzzer are never late casts", function()
    if forever() then return end
    local S, buzzer = pastBuzzer()
    F.cast(S, buzzer + 2, "succeeded", 75)
    F.cast(S, buzzer + 3, "succeeded", 5019)
    assertEqual(#lateCasts(S), 0)
    S.M.C_Spell.IsAutoRepeatSpell = function(id) return id == 75 end
    F.cast(S, buzzer + 4, "succeeded", T.secret(75))
    assertEqual(#lateCasts(S), 0, "a sealed success while Auto Shot repeats")
end)

test("race: a pet's cast is never judged", function()
    if forever() then return end
    local S, buzzer = pastBuzzer()
    F.at(S, buzzer + 2)
    S.M.__fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "Cast-P", 17253)
    assertEqual(#lateCasts(S), 0)
end)

test("race: the grace in force is the race's own, not the profile's", function()
    if forever() then return end
    local S = fresh()
    assertTrue(F.arm(S, 10))
    S.NS.db.profile.race.grace = 5
    local start = F.pull(S)
    F.run(S, start + 10)
    F.cast(S, start + 12, "succeeded", 29722)
    assertEqual(#lateCasts(S), 1, "the grace frozen at the arm (1.0)")
    assertEqual(S.NS.Race.Current().grace, 1.0)
end)

-- ── the meter ──────────────────────────────────────────────────────────────────────────────────

test("race: a meter reset while running loses the race; nothing is saved and the buzzer never goes", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    S.M.__fire("DAMAGE_METER_RESET")
    assertEqual(R.State(), "result")
    assertEqual(R.Current().status, "lost")
    assertNil(F.last(S, "RACE_RESULT")[2], "no record")
    F.run(S, start + 31)
    assertEqual(F.count(S, "RACE_BUZZER"), 0)
    assertEqual(#F.records(S), 0, "a lost race is not saved")
end)

test("race: a meter reset while stopping -> lost", function()
    if forever() then return end
    local S = fresh()
    assertTrue(F.arm(S, 10))
    local start = F.pull(S)
    F.run(S, start + 10)
    S.M.__fire("DAMAGE_METER_RESET")
    assertEqual(S.NS.Race.Current().status, "lost")
    assertEqual(#F.records(S), 0)
end)

test("race: a meter reset while armed forgets the arm-time sessions and keeps the arm", function()
    if forever() then return end
    local S = fresh()
    S.meter.SetSession(5, F.SESSION)
    assertTrue(F.arm(S, 30))
    S.M.__fire("DAMAGE_METER_RESET")
    assertEqual(S.NS.Race.State(), "armed")
    -- The pull carries on session 5: with the arm's set forgotten it is never bound as shared.
    F.enter(S, 101)
    F.hit(S, 102, 5)
    assertNil(S.NS.Fight.Current().sharedSession)
    assertEqual(S.NS.Race.State(), "armed")
end)

-- ── a shared session (ruling X3, Review focus 5) ───────────────────────────────────────────────

local EARLIER = { damage = 200000, dps = 10000, duration = 20,
                  spells = { { id = 29722, dmg = 150000, dps = 7500 }, { id = 348, dmg = 50000, dps = 2500 } } }
local CARRIED = { damage = 1200000, dps = 20000, duration = 60,
                  spells = { { id = 29722, dmg = 950000, dps = 15800 }, { id = 348, dmg = 250000, dps = 4100 } } }

test("race: a shared session is flagged and netted against the arm baseline, saved once", function()
    if forever() then return end
    local S = fresh()
    S.meter.SetSession(5, EARLIER)     -- the last fight's session, still alive (its DoTs ticking)
    assertTrue(F.arm(S, 10))
    F.enter(S, 101)
    S.meter.SetSession(5, CARRIED)     -- the pull lands in it: no new session
    F.hit(S, 102, 5)
    local fight = S.NS.Fight.Current()
    assertEqual(fight.sessionID, 5, "Fight bound the session alive at the arm, for the race")
    assertTrue(fight.sharedSession)
    assertEqual(S.NS.Race.State(), "running")
    assertTrue(S.NS.Race.Current().flags.sharedSession)
    F.damage(S, 5, 103, 112, 1)
    F.settle(S, 113)
    local records = F.records(S)
    assertEqual(#records, 1, "saved once")
    local r = records[1]
    assertEqual(r.race.score, 1000000, "the race's share only: 1200000 less the 200000 the arm saw")
    assertEqual(r.damage.merged, 1000000, "the record's damage agrees with the score")
    assertTrue(r.race.flags.sharedSession)
    local spells = S.NS.Recorder.Spells(r)
    assertEqual(spells[1].spellID, 29722)
    assertEqual(spells[1].total, 800000, "each spell netted too")
    assertEqual(spells[2].total, 200000)
end)

test("race: a plain fight never binds a session alive before it", function()
    if forever() then return end
    local S = fresh()
    S.meter.SetSession(5, EARLIER)
    S.NS.Meter.Prime()
    F.enter(S, 101)
    F.hit(S, 102, 5)
    assertNil(S.NS.Fight.Current().sessionID, "no race armed: the old session is not this fight's")
end)

test("race: a fresh session heard after a shared start replaces the shared one", function()
    if forever() then return end
    local S = fresh()
    S.meter.SetSession(5, EARLIER)
    assertTrue(F.arm(S, 10))
    F.enter(S, 101)
    S.meter.SetSession(5, CARRIED)
    F.hit(S, 102, 5)
    local shared = S.NS.Fight.Current()
    S.meter.SetSession(6, F.SESSION)   -- the meter splits: a fresh session for the pull
    F.hit(S, 103, 6)
    local fresh6 = S.NS.Fight.Current()
    assertTrue(fresh6 ~= shared, "Fight split the fresh session off")
    assertEqual(S.NS.Race.Fight(), fresh6, "the race follows the fresh session")
    assertNil(shared.race)
    assertNil(S.NS.Race.Current().flags.sharedSession, "no longer shared")
    F.damage(S, 6, 104, 112, 1)
    F.settle(S, 113)
    local race
    for _, r in ipairs(F.records(S)) do
        if r.race then
            assertNil(race, "one race")
            race = r.race
        end
    end
    assertEqual(race.score, 1539711, "the fresh session's total")
end)

test("race: a split mid-race keeps the race on its first fight", function()
    if forever() then return end
    local S = fresh()
    assertTrue(F.arm(S, 10))
    local start = F.pull(S)
    local first = S.NS.Race.Fight()
    S.meter.SetSession(26, EARLIER)
    F.hit(S, start + 3, 26)
    assertTrue(S.NS.Fight.Current() ~= first, "the meter split the fight")
    assertEqual(S.NS.Race.Fight(), first, "the race stays on its own fight")
    F.run(S, start + 10)
    F.settle(S, start + 11)
    local races = 0
    for _, r in ipairs(F.records(S)) do
        if r.race then
            races = races + 1
            assertEqual(r.race.score, 1539711)
        end
    end
    assertEqual(races, 1)
end)

test("race: a session bound only on a tick's look at the list flags sessionFromList", function()
    if forever() then return end
    local S = fresh()
    assertTrue(F.arm(S, 10))
    F.enter(S, 101)
    S.meter.SetSession(25, F.SESSION)    -- made after the entry, no session event: the tick finds it
    F.run(S, 101.25)
    assertEqual(S.NS.Fight.Current().boundBy, "tick")
    F.hit(S, 102, 25)
    F.run(S, 112)
    F.settle(S, 113)
    assertTrue(F.records(S)[1].race.flags.sessionFromList)
end)

-- ── stop now (ruling X5) ───────────────────────────────────────────────────────────────────────

test("race: Stop Now acts only while stopping", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertFalse(R.StopNow(), "idle")
    assertTrue(F.arm(S, 10))
    assertFalse(R.StopNow(), "armed")
    local start = F.pull(S)
    assertFalse(R.StopNow(), "running")
    F.run(S, start + 10)
    assertTrue(R.StopNow(), "stopping")
    assertTrue(R.StopRequested())
end)

test("race: Stop Now after combat ends reads at once", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertTrue(F.arm(S, 10))
    local start = F.pull(S)
    F.run(S, start + 10)
    F.leave(S, start + 11)
    assertEqual(S.NS.Fight.State(), "settling")
    assertTrue(R.StopNow())
    assertEqual(R.State(), "result", "read with no wait, no clock moved")
    assertEqual(#F.records(S), 1)
    assertEqual(F.records(S)[1].race.status, "complete")
end)

test("race: Stop Now in combat waits for combat to end and skips the quiet", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertTrue(F.arm(S, 10))
    local start = F.pull(S)
    F.run(S, start + 10)
    assertTrue(R.StopNow())
    F.run(S, start + 12)
    assertEqual(R.State(), "stopping", "nothing is read in combat")
    F.leave(S, start + 13)
    F.hit(S, start + 13.5, 25)            -- a trailing update: the quiet would wait on it
    F.run(S, start + 13.5)
    assertEqual(R.State(), "result", "read at the combat end, without the grace or the quiet")
    assertEqual(#F.records(S), 1)
end)

test("race: Stop Now on a race that ended before the buzzer reads it as incomplete", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.leave(S, start + 5)
    assertTrue(R.StopNow())
    assertEqual(F.records(S)[1].race.status, "incomplete")
end)

-- ── cancel ─────────────────────────────────────────────────────────────────────────────────────

test("race: Cancel while armed stores nothing and arms again", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertTrue(F.arm(S, 30))
    assertTrue(R.Cancel())
    assertEqual(R.State(), "idle")
    assertEqual(F.last(S, "RACE_CANCELED")[2], "canceled")
    assertFalse(R.Cancel(), "nothing to cancel")
    assertTrue(F.arm(S, 30))
end)

test("race: Cancel after the first hit leaves a plain dummy fight", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    S.NS.db.profile.history.minLength = 30
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    local fight = R.Fight()
    F.damage(S, 25, start + 1, start + 10, 1)
    assertTrue(R.Cancel())
    assertNil(fight.race, "the part comes off the fight")
    F.run(S, start + 30)
    assertEqual(F.count(S, "RACE_BUZZER"), 0, "the buzzer is gone with it")
    F.damage(S, 25, start + 11, start + 40, 1)
    F.settle(S, start + 41)
    local records = F.records(S)
    assertEqual(#records, 1, "the pull is kept, under the normal filters")
    assertNil(records[1].race)
    assertEqual(records[1].identity.content, "dummy")
end)

test("race: Cancel after the first hit of a short pull saves nothing under the minimum length", function()
    if forever() then return end
    local S = fresh()
    S.NS.db.profile.history.minLength = 30
    assertTrue(F.arm(S, 30))
    local start = F.pull(S, 101, 25, { damage = 90000, dps = 9000, duration = 10,
                                        spells = { { id = 29722, dmg = 90000, dps = 9000 } } })
    S.NS.Race.Cancel()
    F.settle(S, start + 10)
    assertEqual(#F.records(S), 0)
    assertEqual(F.last(S, "FIGHT_SKIPPED")[3], "short")
end)

test("race: cancel on a result dismisses it and keeps the record; race again arms", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    F.whole(S, 10, 1)
    assertEqual(R.State(), "result")
    local canceled = F.count(S, "RACE_CANCELED")
    assertTrue(R.Cancel())
    assertEqual(R.State(), "idle")
    assertEqual(F.count(S, "RACE_CANCELED"), canceled, "a dismissed result is not a cancel")
    assertEqual(#F.records(S), 1, "the race stays saved")
    assertTrue(F.arm(S, 10, 200))
end)

test("race: an arm from a result arms a new race", function()
    if forever() then return end
    local S = fresh()
    F.whole(S, 10, 1)
    assertTrue(F.arm(S, 60, 200))
    assertEqual(S.NS.Race.State(), "armed")
    assertEqual(S.NS.Race.Current().length, 60)
end)

-- ── the arm's snapshots (ruling X6) ────────────────────────────────────────────────────────────

test("race: the arm's snapshots replace the fight's combat-entry reads", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local phase = "arm"
    NS.Stats.Read = function() return { phase = phase } end
    NS.Usage.Snapshot = function() return { phase = phase } end
    assertTrue(F.arm(S, 10))
    phase = "combat"
    S.meter.SetSession(25, F.SESSION)
    F.enter(S, 101)
    local fight = NS.Fight.Current()
    assertEqual(fight.stats.phase, "combat", "Combat Trail's read at the pull")
    F.hit(S, 102, 25)
    assertEqual(fight.stats.phase, "arm", "the arm's read, out of combat")
    assertEqual(fight.usageSnap.phase, "arm")
end)

-- ── inputs in the wrong state and the wiring ───────────────────────────────────────────────────

test("race: inputs in the wrong state change nothing", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    R.OnCombatEnd(100)
    R.OnDeath(100)
    R.OnCast("succeeded", 29722, 100, "Cast-X")
    R.OnMeterUpdate(100, 0, 25)
    R.OnMeterReset()
    R.Finalize({ id = "x" }, nil, "lost")
    assertEqual(R.State(), "idle")
    assertEqual(#S.heard, 0, "nothing on the bus")
end)

-- The events the race watchers hold now: the AceEvent ones and the unit ones, each a sorted list.
local function watched(S)
    local target, frame = S.NS.RaceWatchers.Targets()
    local events, units = {}, {}
    for _, r in ipairs(S.M.__registrations()) do
        if target and r.target == target and r.kind == "event" then events[#events + 1] = r.event end
        if frame and r.target == frame and r.kind == "unit" then units[#units + 1] = r.event .. "@" .. tostring(r.unit) end
    end
    table.sort(events)
    table.sort(units)
    return table.concat(events, ","), table.concat(units, ",")
end

test("race: the watchers register only what the race's state needs", function()
    if forever() then return end
    local S = fresh()
    local events, units = watched(S)
    assertEqual(events, "", "idle hears nothing")
    assertEqual(units, "")
    assertTrue(F.arm(S, 10))
    events = watched(S)
    assertEqual(events, "DAMAGE_METER_RESET")
    local start = F.pull(S)
    events, units = watched(S)
    assertEqual(events, "DAMAGE_METER_COMBAT_SESSION_UPDATED,PLAYER_DEAD,PLAYER_REGEN_DISABLED,PLAYER_REGEN_ENABLED")
    assertEqual(units, "UNIT_SPELLCAST_CHANNEL_START@player,UNIT_SPELLCAST_CHANNEL_STOP@player,"
        .. "UNIT_SPELLCAST_EMPOWER_START@player,UNIT_SPELLCAST_INTERRUPTED@player,"
        .. "UNIT_SPELLCAST_START@player,UNIT_SPELLCAST_SUCCEEDED@player")
    F.run(S, start + 10)
    F.settle(S, start + 11)
    assertEqual(S.NS.Race.State(), "result")
    events, units = watched(S)
    assertEqual(events, "", "a result hears nothing")
    assertEqual(units, "")
end)

test("race: a stand-down drops the armed race silently, with its registrations", function()
    if forever() then return end
    local S = fresh()
    local R = S.NS.Race
    assertTrue(F.arm(S, 10))
    local start = F.pull(S)
    local before = #S.heard
    S.NS.SetByPath("general.enabled", false)
    assertEqual(R.State(), "idle")
    assertNil(R.Current())
    local events, units = watched(S)
    assertEqual(events, "")
    assertEqual(units, "")
    F.run(S, start + 10)
    assertEqual(F.count(S, "RACE_BUZZER"), 0, "the buzzer went with the stand-down")
    assertTrue(#S.heard == before, "nothing sent")
    S.NS.SetByPath("general.enabled", true)
    assertEqual(R.State(), "idle", "a stand-up does not bring it back")
end)
