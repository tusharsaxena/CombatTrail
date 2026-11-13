-- tests/test_fight.lua — modules/Fight.lua and modules/Watchers.lua against the scripted meter
-- (tests/mock_meter.lua), plan Task 2.2: a fight binds to the meter session that appears at or after
-- combat entry, ticks at 4 Hz in combat, settles after the grace and the quiet, and ends final with
-- the plain read or lost. Feign Death within the grace keeps one fight; a new session with the same
-- active encounter merges; a meter reset loses the fight. Watchers registers only the current
-- state's events, and nothing while the addon is stood down.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local FIGHT = { damage = 9000, dps = 300, duration = 30,
                spells = { { id = 133, dmg = 3000, dps = 100 }, { id = 11366, dmg = 6000, dps = 200 } } }
local SECOND = { damage = 4000, dps = 200, duration = 20,
                 spells = { { id = 133, dmg = 1000, dps = 50 }, { id = 2948, dmg = 3000, dps = 150 } } }

local DAMAGE_DONE = 0

-- A fresh instance on the scripted meter, with a bus receiver that hears the three fight messages.
local function fresh()
    local meter
    local inst = T.load{ mutate = function(m) meter = T.mockMeter.install(m) end }
    local NS = inst.NS
    local heard = { started = {}, ticks = 0, ended = {}, entered = {} }
    local rx = NS.NewBusTarget()
    if NS.MSG.COMBAT_ENTERED then
        rx:RegisterMessage(NS.MSG.COMBAT_ENTERED, function(_, t) heard.entered[#heard.entered + 1] = t end)
    end
    rx:RegisterMessage(NS.MSG.FIGHT_STARTED, function(_, fight) heard.started[#heard.started + 1] = fight end)
    rx:RegisterMessage(NS.MSG.FIGHT_TICK, function() heard.ticks = heard.ticks + 1 end)
    rx:RegisterMessage(NS.MSG.FIGHT_ENDED, function(_, fight, final, reason)
        heard.ended[#heard.ended + 1] = { fight = fight, final = final, reason = reason }
    end)
    return inst, meter, heard
end

local function at(inst, t) inst.mocks.__now = t end

local function enter(inst, t)
    at(inst, t)
    inst.mocks.InCombatLockdown = function() return true end
    inst.mocks.__inCombat = true
    inst.mocks.__fire("PLAYER_REGEN_DISABLED")
end

local function leave(inst, t)
    at(inst, t)
    inst.mocks.InCombatLockdown = function() return false end
    inst.mocks.__inCombat = false
    inst.mocks.__fire("PLAYER_REGEN_ENABLED")
end

local function update(inst, t, id, stat)
    at(inst, t)
    inst.mocks.__fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", stat or DAMAGE_DONE, id)
end

-- Let the clock reach t and run whatever timers are due by then.
local function settle(inst, t)
    at(inst, t)
    inst.mocks.__fireTimers()
end

-- The events the watchers' own AceEvent target holds now, as a sorted comma list.
local function watched(inst)
    local target = inst.NS.Watchers.EventTarget()
    local out = {}
    for _, r in ipairs(inst.mocks.__registrations()) do
        if target and r.target == target and r.kind == "event" then out[#out + 1] = r.event end
    end
    table.sort(out)
    return table.concat(out, ",")
end

local FIGHT_SET = "DAMAGE_METER_COMBAT_SESSION_UPDATED,DAMAGE_METER_CURRENT_SESSION_UPDATED,"
    .. "DAMAGE_METER_RESET,ENCOUNTER_END,ENCOUNTER_START,PLAYER_REGEN_DISABLED,PLAYER_REGEN_ENABLED"

-- ── constants and the shape ────────────────────────────────────────────────────────────────────

test("fight: the states and the timing constants are the plan's", function()
    local inst = fresh()
    local NS = inst.NS
    assertEqual(NS.Fight.STATE.IDLE, "idle")
    assertEqual(NS.Fight.STATE.COMBAT, "combat")
    assertEqual(NS.Fight.STATE.SETTLING, "settling")
    assertEqual(NS.Constants.FIGHT.GRACE, 4)
    assertEqual(NS.Constants.FIGHT.SETTLE, 2)
    assertEqual(NS.Constants.FIGHT.TICK, 0.25)
    assertEqual(NS.Fight.State(), "idle")
    assertNil(NS.Fight.Current())
    assertEqual(type(NS.MSG.FIGHT_STARTED), "string")
    assertEqual(NS.MSG.FIGHT_ENDED, "Ka0s_CombatTrail_FightEnded")
end)

-- ── the normal fight ───────────────────────────────────────────────────────────────────────────

test("fight: normal combat → started, ticks, ended final", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    at(inst, 10)
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    assertEqual(NS.Fight.State(), "combat")
    assertEqual(#heard.started, 1)
    local fight = NS.Fight.Current()
    assertEqual(fight, heard.started[1], "Current is the fight that started")
    assertEqual(fight.sessionID, 1, "bound to the session that appeared at combat entry")
    assertEqual(fight.startT, 10)
    assertEqual(type(fight.id), "string")
    assertNil(fight.firstHitT, "no damage update yet")
    update(inst, 11, 1)
    assertEqual(fight.firstHitT, 11, "the clock starts on the session's first damage update")
    settle(inst, 11.25)
    assertTrue(heard.ticks >= 1, "FIGHT_TICK while in combat")
    leave(inst, 40)
    assertEqual(NS.Fight.State(), "settling")
    local ticks = heard.ticks
    settle(inst, 42.5)
    assertEqual(heard.ticks, ticks, "no tick once combat is over")
    assertEqual(#heard.ended, 0, "the grace has not run out")
    settle(inst, 44.1)
    assertEqual(#heard.ended, 1)
    local e = heard.ended[1]
    assertEqual(e.fight, fight)
    assertEqual(e.reason, "final")
    assertEqual(e.final.merged.total, 9000)
    assertEqual(e.final.duration, 30)
    assertEqual(NS.Fight.State(), "idle")
    assertNil(NS.Fight.Current())
end)

test("fight: the tick runs at 4 Hz in combat only", function()
    local inst, meter = fresh()
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    local live = 0
    for _, t in ipairs(inst.mocks.__timers()) do
        if t.delay == 0.25 and t.looping then live = live + 1 end
    end
    assertEqual(live, 1, "one repeating 0.25 s timer")
    leave(inst, 20)
    for _, t in ipairs(inst.mocks.__timers()) do
        assertFalse(t.delay == 0.25 and t.looping, "the tick is canceled when combat ends")
    end
end)

test("fight: a session that appears after combat entry binds on its first update", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    enter(inst, 10)
    assertNil(NS.Fight.Current().sessionID, "no session yet")
    at(inst, 10.5)
    meter.SetSession(4, FIGHT)
    update(inst, 10.5, 4)
    assertEqual(NS.Fight.Current().sessionID, 4)
    assertEqual(NS.Fight.Current().firstHitT, 10.5)
    assertEqual(#heard.started, 1)
end)

test("fight: an older session is never bound, and a fight with no session ends lost", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    at(inst, 5)
    meter.SetSession(3, FIGHT)           -- seen at 5, before the combat entry
    NS.Meter.SessionIDs()
    enter(inst, 10)
    update(inst, 11, 3)
    assertNil(NS.Fight.Current().sessionID, "the baseline session belongs to an earlier fight")
    leave(inst, 20)
    settle(inst, 24.5)
    assertEqual(#heard.ended, 1)
    assertNil(heard.ended[1].final)
    assertEqual(heard.ended[1].reason, "lost")
end)

test("fight: secret update arguments bind through the session list, never compared", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local inst, meter = fresh()
        enter(inst, 10)
        at(inst, 11)
        meter.SetSecret(true)
        meter.SetSession(6, FIGHT)
        update(inst, 11, T.secret(6), T.secret(DAMAGE_DONE))
        local fight = inst.NS.Fight.Current()
        assertEqual(fight.sessionID, 6, "the list's IDs are plain in combat")
        assertEqual(fight.firstHitT, 11)
    end)
    restore()
    assertTrue(ok, tostring(err))
end)

test("fight: a DPS-type update is not damage and starts no clock", function()
    local inst, meter = fresh()
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    update(inst, 11, 1, 1)
    assertNil(inst.NS.Fight.Current().firstHitT)
end)

-- ── Feign Death, Vanish and the grace ──────────────────────────────────────────────────────────

test("fight: FD within grace keeps one fight", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    local fight = NS.Fight.Current()
    leave(inst, 20)
    settle(inst, 21)
    enter(inst, 22)                       -- 2 s later, the meter keeps session 1
    assertEqual(NS.Fight.State(), "combat")
    assertEqual(NS.Fight.Current(), fight, "the same fight carries on")
    update(inst, 23, 1)
    leave(inst, 40)
    settle(inst, 44.5)
    assertEqual(#heard.started, 1, "one fight, not two")
    assertEqual(#heard.ended, 1)
    assertEqual(heard.ended[1].reason, "final")
    assertEqual(#fight.sessions, 1)
end)

test("fight: FD beyond grace ends the first fight", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    leave(inst, 20)
    settle(inst, 24.5)                    -- grace over, quiet since 20
    assertEqual(#heard.ended, 1, "the first fight is over")
    assertEqual(heard.ended[1].reason, "final")
    at(inst, 26)
    meter.SetSession(2, SECOND)
    enter(inst, 26)
    assertEqual(#heard.started, 2, "a new fight")
    assertEqual(NS.Fight.Current().sessionID, 2)
end)

test("fight: re-entry past the grace while updates still land parks the first fight until the settle", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    local first = NS.Fight.Current()
    leave(inst, 20)
    update(inst, 23, 1)                   -- the tail keeps the first fight unsettled
    at(inst, 25)
    meter.SetSession(2, SECOND)
    enter(inst, 25)                       -- 5 s after the combat end: past the grace
    assertEqual(#heard.started, 2)
    assertTrue(NS.Fight.Current() ~= first, "a second fight")
    assertEqual(NS.Fight.Current().sessionID, 2)
    assertEqual(#heard.ended, 0, "the first is read out of combat, not now")
    leave(inst, 50)
    settle(inst, 54.5)
    assertEqual(#heard.ended, 2)
    assertEqual(heard.ended[1].fight, first, "the older fight ends first")
    assertEqual(heard.ended[1].final.merged.total, 9000)
    assertEqual(heard.ended[2].final.merged.total, 4000)
end)

test("fight: a new session within grace without an encounter is a new fight", function()
    local inst, meter, heard = fresh()
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    leave(inst, 20)
    at(inst, 22)
    meter.SetSession(2, SECOND)
    enter(inst, 22)
    update(inst, 22.5, 2)
    assertEqual(#heard.started, 2, "the meter split it, so does the addon")
    assertEqual(inst.NS.Fight.Current().sessionID, 2)
    leave(inst, 40)
    settle(inst, 44.5)
    assertEqual(#heard.ended, 2)
end)

-- ── encounters ─────────────────────────────────────────────────────────────────────────────────

test("fight: encounter split sessions merge after combat", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    at(inst, 9)
    inst.mocks.__fire("ENCOUNTER_START", 2001, "Patchwerk", 15, 20)
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    local fight = NS.Fight.Current()
    assertEqual(fight.encounter.id, 2001)
    assertEqual(fight.encounter.name, "Patchwerk")
    assertEqual(fight.encounter.difficultyID, 15)
    leave(inst, 20)                       -- Feign Death
    at(inst, 22)
    meter.SetSession(2, SECOND)           -- the meter opened a new session
    enter(inst, 22)
    update(inst, 22.5, 2)
    assertEqual(#heard.started, 1, "the same encounter: one fight")
    assertEqual(#fight.sessions, 2)
    at(inst, 50)
    inst.mocks.__fire("ENCOUNTER_END", 2001, "Patchwerk", 15, 20, 1)
    leave(inst, 50)
    settle(inst, 54.5)
    assertEqual(#heard.ended, 1)
    local final = heard.ended[1].final
    assertEqual(heard.ended[1].reason, "final")
    assertEqual(final.merged.total, 13000, "plain sums of both sessions")
    assertEqual(final.duration, 50)
    assertEqual(final.merged.spells[1].spellID, 11366)
    local fireball
    for _, sp in ipairs(final.merged.spells) do
        if sp.spellID == 133 then fireball = sp end
    end
    assertEqual(fireball.total, 4000, "a spell in both sessions is summed")
    assertEqual(#final.merged.spells, 3)
    assertEqual(fight.encounter.success, true)
end)

test("fight: an encounter that starts mid-combat with a meter split is its own fight", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    local trash = NS.Fight.Current()
    at(inst, 15)
    inst.mocks.__fire("ENCOUNTER_START", 2002, "Grobbulus", 15, 20)
    meter.SetSession(2, SECOND)
    update(inst, 15.2, 2)
    assertEqual(#heard.started, 2)
    local boss = NS.Fight.Current()
    assertEqual(boss.encounter.id, 2002, "the boss part carries the encounter")
    assertNil(trash.encounter, "the pre-encounter part does not")
    leave(inst, 40)
    settle(inst, 44.5)
    assertEqual(#heard.ended, 2)
end)

test("fight: an encounter that starts mid-combat without a split names the whole fight", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    at(inst, 15)
    inst.mocks.__fire("ENCOUNTER_START", 2002, "Grobbulus", 15, 20)
    update(inst, 15.2, 1)
    assertEqual(#heard.started, 1)
    assertEqual(NS.Fight.Current().encounter.id, 2002)
end)

test("fight: a wipe and a new pull of the same boss are two fights", function()
    local inst, meter, heard = fresh()
    at(inst, 9)
    inst.mocks.__fire("ENCOUNTER_START", 2001, "Patchwerk", 15, 20)
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    at(inst, 20)
    inst.mocks.__fire("ENCOUNTER_END", 2001, "Patchwerk", 15, 20, 0)
    leave(inst, 20)
    at(inst, 22)
    inst.mocks.__fire("ENCOUNTER_START", 2001, "Patchwerk", 15, 20)
    meter.SetSession(2, SECOND)
    enter(inst, 22)
    update(inst, 22.5, 2)
    assertEqual(#heard.started, 2, "a new encounter, a new fight")
end)

test("fight: an encounter that ends while idle (the player died out of it) names no later fight", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    at(inst, 9)
    inst.mocks.__fire("ENCOUNTER_START", 2001, "Patchwerk", 15, 20)
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    leave(inst, 20)                       -- the player died; the raid fights on
    settle(inst, 24.5)
    assertEqual(NS.Fight.State(), "idle")
    assertTrue(watched(inst):find("ENCOUNTER_END", 1, true) ~= nil, "idle hears the active encounter's end")
    at(inst, 60)
    inst.mocks.__fire("ENCOUNTER_END", 2001, "Patchwerk", 15, 20, 0)
    assertEqual(watched(inst), "ENCOUNTER_START,PLAYER_REGEN_DISABLED", "the plain idle set again")
    at(inst, 100)
    meter.SetSession(2, SECOND)
    enter(inst, 100)                      -- trash after the wipe
    assertEqual(#heard.started, 2)
    assertNil(NS.Fight.Current().encounter, "the ended encounter does not ride on")
    assertEqual(heard.started[1].encounter.success, false)
end)

-- ── the meter going away ───────────────────────────────────────────────────────────────────────

test("fight: meter reset mid-fight → lost", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    local fight = NS.Fight.Current()
    at(inst, 15)
    inst.mocks.__fire("DAMAGE_METER_RESET")
    assertEqual(#heard.ended, 1)
    assertEqual(heard.ended[1].fight, fight)
    assertEqual(heard.ended[1].reason, "lost")
    assertNil(heard.ended[1].final)
    assertEqual(NS.Fight.State(), "idle")
    assertEqual(watched(inst), "ENCOUNTER_START,PLAYER_REGEN_DISABLED")
end)

test("fight: the bound session disappearing → lost; a failed list read is no evidence", function()
    local inst, meter, heard = fresh()
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    meter.SetRaise("GetAvailableCombatSessions", "boom")
    update(inst, 11, 99)
    assertEqual(#heard.ended, 0, "a raising list read does not lose the fight")
    meter.SetRaise("GetAvailableCombatSessions", nil)
    meter.RemoveSession(1)
    update(inst, 12, 99)
    assertEqual(#heard.ended, 1)
    assertEqual(heard.ended[1].reason, "lost")
end)

test("fight: a session gone by the settle read ends lost", function()
    local inst, meter, heard = fresh()
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    leave(inst, 20)
    meter.RemoveSession(1)
    settle(inst, 24.5)
    assertEqual(#heard.ended, 1)
    assertEqual(heard.ended[1].reason, "lost")
end)

-- ── the settle ─────────────────────────────────────────────────────────────────────────────────

test("fight: settle waits for quiet", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    leave(inst, 20)
    update(inst, 23.5, 1)                 -- a DoT tick after the combat end
    settle(inst, 24.1)
    assertEqual(#heard.ended, 0, "2 s of quiet since 23.5 have not passed")
    assertEqual(NS.Fight.State(), "settling")
    settle(inst, 25.6)
    assertEqual(#heard.ended, 1)
    assertEqual(heard.ended[1].reason, "final")
end)

test("fight: a still-sealed read retries, then reads", function()
    local inst, meter, heard = fresh()
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    leave(inst, 20)
    meter.SetSealed(1, true)
    settle(inst, 24.5)
    assertEqual(#heard.ended, 0, "sealed: try again")
    meter.SetSealed(1, false)
    settle(inst, 25)
    assertEqual(#heard.ended, 1)
    assertEqual(heard.ended[1].reason, "final")
end)

test("fight: a read sealed past the retries ends lost", function()
    local inst, meter, heard = fresh()
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    leave(inst, 20)
    meter.SetSealed(1, true)
    local t = 24.5
    for _ = 1, inst.NS.Fight.SEALED_RETRIES + 1 do
        settle(inst, t)
        t = t + 0.5
    end
    assertEqual(#heard.ended, 1)
    assertEqual(heard.ended[1].reason, "lost")
end)

-- ── the watchers ───────────────────────────────────────────────────────────────────────────────

test("fight: idle registers only the idle events", function()
    local inst, meter = fresh()
    assertEqual(watched(inst), "ENCOUNTER_START,PLAYER_REGEN_DISABLED")
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    assertEqual(watched(inst), FIGHT_SET, "the fight set while in combat")
    leave(inst, 20)
    assertEqual(watched(inst), FIGHT_SET, "and while settling")
    settle(inst, 24.5)
    assertEqual(watched(inst), "ENCOUNTER_START,PLAYER_REGEN_DISABLED", "back to idle")
end)

test("fight: COMBAT_LOG_EVENT_UNFILTERED is never registered", function()
    local inst, meter = fresh()
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    local events = 0
    for _, r in ipairs(inst.mocks.__registrations()) do
        if r.kind == "event" then events = events + 1 end
        assertTrue(r.event ~= "COMBAT_LOG_EVENT_UNFILTERED")
    end
    assertTrue(events > 0, "the registry holds the fight set, so the check above is not vacuous")
    -- Every authored source file, not only the ones that register today (libs/ and tests/ aside).
    local paths = {}
    local p = io.popen('cd "' .. T.root .. '" && git ls-files "*.lua" "*.xml" | grep -v "^libs/" | grep -v "^tests/"')
    for line in p:lines() do paths[#paths + 1] = "/" .. line end
    p:close()
    assertTrue(#paths > 40, "scanned " .. #paths .. " files")
    for _, path in ipairs(paths) do
        local f = io.open(T.root .. path, "rb")
        local src = f:read("*a")
        f:close()
        assertNil(src:find("Register[%a]*Event%s*%([^)]*COMBAT_LOG"), path .. ": no registration call names it")
        assertNil(src:find('"COMBAT_LOG_EVENT', 1, true), path .. ": no event list names it")
    end
end)

test("fight: an event the client rejects costs only itself, and is never unregistered", function()
    local meter
    local inst = T.load{ mutate = function(m)
        meter = T.mockMeter.install(m)
        m.__badEvents = { DAMAGE_METER_RESET = true }
    end }
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    local named = false
    for _, e in ipairs(inst.NS.rejectedEvents) do if e == "DAMAGE_METER_RESET" then named = true end end
    assertTrue(named, "the rejection is recorded")
    local target = inst.NS.Watchers.EventTarget()
    local unregister = target.UnregisterEvent
    target.UnregisterEvent = function(self, event, ...)
        if event == "DAMAGE_METER_RESET" then error("Attempt to unregister unknown event", 2) end
        return unregister(self, event, ...)
    end
    leave(inst, 20)
    local ok, err = pcall(settle, inst, 24.5)
    assertTrue(ok, "back to idle without unregistering the rejected name: " .. tostring(err))
    assertEqual(watched(inst), "ENCOUNTER_START,PLAYER_REGEN_DISABLED", "the idle set")
end)

test("fight: disabled addon registers nothing", function()
    local inst = T.load({ enable = false })
    inst.NS.db.profile.general.enabled = false
    inst.NS.SyncEnabledHold()
    inst.mocks.LibStub("AceAddon-3.0"):EnableAddon(inst.NS)
    assertEqual(watched(inst), "")
end)

test("fight: a stand-down mid-fight drops the fight, its timers and every registration", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    NS.SetByPath("general.enabled", false)
    assertEqual(watched(inst), "")
    assertEqual(NS.Fight.State(), "idle")
    assertNil(NS.Fight.Current())
    local ticks = heard.ticks
    settle(inst, 11)
    assertEqual(heard.ticks, ticks, "no tick while stood down")
    assertEqual(#heard.ended, 0, "discarded silently: no record was opened")
    NS.SetByPath("general.enabled", true)
    assertEqual(watched(inst), "ENCOUNTER_START,PLAYER_REGEN_DISABLED", "rebuilt from the current state")
end)

test("fight: an encounter that starts in combat while idle starts a fight", function()
    local inst, meter, heard = fresh()
    inst.mocks.__inCombat = true
    at(inst, 10)
    meter.SetSession(1, FIGHT)
    inst.mocks.__fire("ENCOUNTER_START", 2001, "Patchwerk", 15, 20)
    assertEqual(#heard.started, 1)
    assertEqual(inst.NS.Fight.Current().encounter.id, 2001)
end)

-- ── COMBAT_ENTERED (v0.2 Task C1): the regen edge alone ───────────────────────────────────────────

test("fight: COMBAT_ENTERED is sent on the regen edge from idle, on the grace carry-on and on park+begin", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    assertTrue(NS.MSG.COMBAT_ENTERED ~= nil, "declared in the bus catalog")
    meter.SetSession(1, FIGHT)
    enter(inst, 10)                       -- from idle
    assertEqual(#heard.entered, 1)
    assertEqual(heard.entered[1], 10, "the payload is the entry time")
    leave(inst, 20)
    enter(inst, 22)                       -- within the grace: the fight carries on
    assertEqual(#heard.started, 1, "no new fight")
    assertEqual(#heard.entered, 2, "but combat was entered again")
    leave(inst, 30)
    update(inst, 33, 1)                   -- the tail keeps it unsettled
    at(inst, 35)
    meter.SetSession(2, SECOND)
    enter(inst, 35)                       -- past the grace: parked, a new fight begins
    assertEqual(#heard.started, 2)
    assertEqual(#heard.entered, 3)
end)

test("fight: COMBAT_ENTERED is not sent on a meter split, ENCOUNTER_START in combat, or while stood down", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    at(inst, 15)
    inst.mocks.__fire("ENCOUNTER_START", 2002, "Grobbulus", 15, 20)
    meter.SetSession(2, SECOND)
    update(inst, 15.2, 2)
    assertEqual(#heard.started, 2, "a split and an encounter start a fight")
    assertEqual(#heard.entered, 1, "only the regen edge entered combat")
    leave(inst, 40)
    settle(inst, 44.5)
    NS.SetByPath("general.enabled", false)
    enter(inst, 50)
    assertEqual(#heard.entered, 1, "nothing while stood down")
end)

-- ── the race's seams (Race mode plan Task B1, rulings X2, X3 and X5) ───────────────────────────

test("fight: FIGHT_FIRST_HIT is sent once, on the first damage update of a bound session", function()
    local inst, meter = fresh()
    local NS = inst.NS
    local hits = {}
    NS.NewBusTarget():RegisterMessage(NS.MSG.FIGHT_FIRST_HIT, function(_, f) hits[#hits + 1] = f end)
    enter(inst, 10)
    update(inst, 10.5, 1)                 -- no session yet: not a hit on this fight
    assertEqual(#hits, 0)
    meter.SetSession(1, FIGHT)
    update(inst, 11, 1)
    update(inst, 12, 1)
    assertEqual(#hits, 1, "once")
    assertEqual(hits[1], NS.Fight.Current())
    assertEqual(hits[1].firstHitT, 11)
end)

test("fight: Hurry reads a settling fight at once; idle or another fight's id does nothing", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    assertFalse(NS.Fight.Hurry("none"), "idle")
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    update(inst, 11, 1)
    leave(inst, 40)
    assertFalse(NS.Fight.Hurry("another"), "not this fight")
    assertEqual(#heard.ended, 0)
    assertTrue(NS.Fight.Hurry(NS.Fight.Current().id))
    assertEqual(#heard.ended, 1, "read now, no grace, no quiet")
    assertEqual(heard.ended[1].reason, "final")
    assertEqual(NS.Fight.State(), "idle")
end)

test("fight: Hurry in combat settles at the combat end with no wait", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    update(inst, 11, 1)
    assertTrue(NS.Fight.Hurry(NS.Fight.Current().id))
    settle(inst, 20)
    assertEqual(#heard.ended, 0, "nothing is read in combat")
    leave(inst, 40)
    local queued = inst.mocks.__timers[#inst.mocks.__timers]
    assertTrue(queued ~= nil and queued.delay <= 0.01, "the settle is queued with no grace")
    update(inst, 40.2, 1)                 -- a trailing update would hold the quiet
    settle(inst, 40.2)
    assertEqual(#heard.ended, 1, "read at the combat end")
end)

test("fight: Adopt rebuilds a resumed race's fight in combat, with no FIGHT_STARTED; refused while busy", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    meter.SetSession(1, FIGHT)
    NS.Meter.Prime()                      -- the stand-up's priming: session 1 is the baseline
    assertNil(NS.Fight.Adopt({ sessions = {} }), "no session, no fight")
    at(inst, 50)
    inst.mocks.__inCombat = true
    local f = NS.Fight.Adopt({ sessions = { 1 }, startT = 10, firstHitT = 11, snapshot = { who = { name = "Tush" } },
                               stats = { crit = 20 }, talents = { "t" }, gearSet = "g1", boundBy = "entry",
                               inCombat = true })
    assertTrue(f ~= nil)
    assertEqual(NS.Fight.State(), "combat")
    assertEqual(NS.Fight.Current(), f)
    assertEqual(f.sessionID, 1, "bound to the kept session, though primed as older")
    assertEqual(f.startT, 10)
    assertEqual(f.firstHitT, 11)
    assertEqual(f.snapshot.who.name, "Tush")
    assertEqual(f.loadout.talents[1], "t")
    assertEqual(f.gearSet, "g1")
    assertEqual(f.boundBy, "entry")
    assertTrue(NS.Fight.Timers().tick ~= nil, "it ticks")
    assertEqual(#heard.started, 0, "not a new fight")
    assertNil(NS.Fight.Adopt({ sessions = { 1 }, inCombat = true }), "refused while a fight is in progress")
    update(inst, 52, 1)
    assertEqual(f.lastUpdateT, 52)
    leave(inst, 60)
    settle(inst, 70)
    assertEqual(#heard.ended, 1)
    assertEqual(heard.ended[1].fight, f)
    assertEqual(heard.ended[1].reason, "final")
end)

test("fight: Adopt out of combat reads the fight on the next timer, without the settle's wait", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    meter.SetSession(1, FIGHT)
    at(inst, 50)
    local f = NS.Fight.Adopt({ sessions = { 1 }, startT = 10, firstHitT = 11, inCombat = false })
    assertEqual(NS.Fight.State(), "settling")
    assertEqual(f.combatEndT, 50)
    assertEqual(#heard.ended, 0, "never read inside the call")
    settle(inst, 50)
    assertEqual(#heard.ended, 1, "read with no grace and no quiet")
    assertEqual(heard.ended[1].reason, "final")
    assertEqual(NS.Fight.State(), "idle")
end)

test("fight: ShareSessions lets an unbound fight bind a listed session, marked shared; none by default", function()
    local inst, meter = fresh()
    local NS = inst.NS
    meter.SetSession(5, SECOND)
    NS.Meter.Prime()                      -- session 5 is older than any fight to come
    enter(inst, 10)
    update(inst, 11, 5)
    assertNil(NS.Fight.Current().sessionID, "a plain fight never binds a session from before it")
    leave(inst, 12)
    settle(inst, 20)
    NS.Fight.ShareSessions({ [5] = true })
    enter(inst, 30)
    update(inst, 31, 5)
    local f = NS.Fight.Current()
    assertEqual(f.sessionID, 5)
    assertTrue(f.sharedSession)
    assertEqual(f.boundBy, "shared")
    NS.Fight.ShareSessions(nil)
end)
