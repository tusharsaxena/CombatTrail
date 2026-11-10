-- tests/test_record.lua — modules/Recorder.lua (plan Task 2.5, spec §5, adapted from DPS Race
-- @045f479): FIGHT_ENDED "final" becomes a stored record when the fight passes the recording filters
-- (FIGHT_SAVED), and FIGHT_SKIPPED says why when it does not; the record's shape and size; the store's
-- reads and edits (Get, All, Delete, SetNote); nothing is written before the fight ends, and no secret
-- ever reaches the record.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local FIGHT = { damage = 40000, dps = 1000, duration = 40,
                spells = { { id = 133, dmg = 30000, dps = 750 }, { id = 11366, dmg = 10000, dps = 250 } },
                enemies = { { name = "Angry Boar", creatureID = 1985, damage = 30000 },
                            { name = "Boar Piglet", creatureID = 1986, damage = 10000 } } }

-- A fresh instance on the scripted meter (so secrets are the kit's), with a receiver for the
-- recorder's messages.
local function fresh()
    local meter
    local inst = T.load{ mutate = function(m)
        meter = T.mockMeter.install(m)
        m.GetHaste = function() return 18.5 end      -- one stat the client reads, so Stats has a record
    end }
    local NS = inst.NS
    local heard = { saved = {}, skipped = {}, changed = 0 }
    local rx = NS.NewBusTarget()
    rx:RegisterMessage(NS.MSG.FIGHT_SAVED, function(_, r) heard.saved[#heard.saved + 1] = r end)
    rx:RegisterMessage(NS.MSG.FIGHT_SKIPPED, function(_, f, why)
        heard.skipped[#heard.skipped + 1] = { fight = f, reason = why }
    end)
    rx:RegisterMessage(NS.MSG.FIGHTS_CHANGED, function() heard.changed = heard.changed + 1 end)
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

local function settle(inst, t)
    at(inst, t)
    inst.mocks.__fireTimers()
end

-- A whole fight on the scripted meter: session 1 holds `session`, combat from 10 to 10 + len.
local function fightThrough(inst, meter, session, len)
    at(inst, 10)
    meter.SetSession(1, session)
    enter(inst, 10)
    at(inst, 11)
    inst.mocks.__fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 1)
    leave(inst, 10 + len)
    settle(inst, 10 + len + 5)
    settle(inst, 10 + len + 10)
end

-- A fight table as modules/Fight.lua hands it over, without the state machine.
local function fakeFight(NS, o)
    o = o or {}
    return {
        id = o.id or "fake-1", startT = 100, combatEndT = 100 + (o.len or 60), sessions = { 1 }, sessionID = 1,
        sessionSet = { [1] = true }, encounter = o.encounter,
        snapshot = o.snapshot or {
            who = { name = "Tush", realm = "Area 52", class = "MAGE", specID = 63, specName = "Fire",
                    ilvl = 650.5, client = NS.Compat.ClientKey() },
            target = { name = "Angry Boar", creatureID = 1985 },
            where = { instanceType = "none", difficultyID = 0 },
        },
        stats = o.stats, loadout = o.loadout,
    }
end

local function fakeFinal(o)
    o = o or {}
    local duration = o.duration or 60
    local total = o.total or 60000
    return { duration = duration,
             player = { total = total, dps = total / duration, spells = { { spellID = 133, total = total, dps = 1 } } },
             merged = { total = total, dps = o.meterDps or (total / duration),
                        spells = { { spellID = 133, total = total, isPet = false } } } }
end

local function finish(NS, fight, final, reason)
    NS.SendBus(NS.MSG.FIGHT_ENDED, fight, final, reason or "final")
end

local function count(NS)
    local c = 0
    for _ in pairs(NS.db.global.fights) do c = c + 1 end
    return c
end

-- ── the record ─────────────────────────────────────────────────────────────────────────────────

test("record: a real fight becomes a stored record with the spec §5 fields", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    fightThrough(inst, meter, FIGHT, 40)
    assertEqual(#heard.saved, 1, "FIGHT_SAVED once")
    local r = heard.saved[1]
    assertEqual(NS.Recorder.Get(r.id), r, "stored under its id")
    assertEqual(NS.db.global.fightOrder[1], r.id)
    assertEqual(r.schema, NS.Recorder.CT_SCHEMA)
    assertEqual(NS.Recorder.CT_SCHEMA, 2)
    assertEqual(r.status, "final")
    assertEqual(r.duration, 40)
    assertEqual(r.damage.merged, 40000)
    assertEqual(r.damage.player, 40000)
    assertNil(r.damage.pet, "no pet source")
    assertEqual(r.dps, 1000, "merged total over the duration")
    assertEqual(r.meterDps, 1000)
    assertEqual(type(r.spells), "string", "packed")
    local spells = NS.Recorder.Spells(r)
    assertEqual(#spells, 2)
    assertEqual(spells[1].spellID, 133)
    assertEqual(spells[1].total, 30000)
    assertEqual(spells[1].isPet, false)
    assertEqual(r.identity.targetName, "Angry Boar", "the enemy that took the most")
    assertEqual(r.identity.otherTargets, 1)
    assertEqual(r.boardKey, "t:1985:?:Angry Boar:0")
    assertEqual(r.who.client, NS.Compat.ClientKey())
    assertEqual(type(r.who.name), "string")
    assertEqual(type(r.t), "number")
    assertEqual(type(r.casts), "string", "packed")
    assertEqual(r.version, NS.version)
    assertEqual(r.client, NS.Compat.ClientKey())
    assertNil(r.gear, "no gear inline (v0.2 plan Task A3)")
    assertEqual(type(r.gearSet), "string", "the gear set's key")
    assertEqual(NS.Loadouts.GearOf(r)[1], "212001::::::::80:267::6:2:10390:1540", "the set holds the item strings")
    assertEqual(type(r.loadout), "string", "the talents' hash")
    assertTrue(NS.Loadouts.Get(r.loadout) ~= nil, "the talent string stored once, by hash")
    assertTrue(r.stats ~= nil, "stats")
    assertEqual(#heard.skipped, 0)
end)

test("record: 22 s fight skipped as short", function()
    local inst, meter, heard = fresh()
    local s = {}
    for k, v in pairs(FIGHT) do s[k] = v end
    s.duration = 22
    fightThrough(inst, meter, s, 22)
    assertEqual(#heard.saved, 0)
    assertEqual(count(inst.NS), 0)
    assertEqual(#heard.skipped, 1)
    assertEqual(heard.skipped[1].reason, "short")
end)

test("record: a lost fight is skipped as lost", function()
    local inst, _, heard = fresh()
    local NS = inst.NS
    finish(NS, fakeFight(NS), nil, "lost")
    assertEqual(heard.skipped[1].reason, "lost")
    assertEqual(count(NS), 0)
end)

test("record: a filtered fight is skipped as filtered", function()
    local inst, _, heard = fresh()
    local NS = inst.NS
    NS.db.profile.history.bossesOnly = true
    finish(NS, fakeFight(NS), fakeFinal())
    assertEqual(heard.skipped[1].reason, "filtered")
    assertEqual(count(NS), 0)
end)

test("record: a fight with no readable character is skipped as unknown", function()
    local inst, _, heard = fresh()
    local NS = inst.NS
    local f = fakeFight(NS)
    f.snapshot.who.name = nil
    finish(NS, f, fakeFinal())
    assertEqual(heard.skipped[1].reason, "unknown")
    assertEqual(count(NS), 0)
end)

test("record: a fight with no readable target is stored as Unknown target, with no board key", function()
    local inst, _, heard = fresh()
    local NS = inst.NS
    local f = fakeFight(NS)
    f.snapshot.target = nil
    finish(NS, f, fakeFinal())
    local r = heard.saved[1]
    assertTrue(r ~= nil)
    assertEqual(r.identity.targetName, NS.L["Unknown target"])
    assertNil(r.boardKey)
    assertFalse(NS.Bests.IsBest(r))
end)

test("record: an unreadable meter duration falls back to the fight's own clock", function()
    local inst, _, heard = fresh()
    local NS = inst.NS
    finish(NS, fakeFight(NS, { len = 50 }), fakeFinal({ duration = 0, total = 50000, meterDps = 0 }))
    local r = heard.saved[1]
    assertEqual(r.duration, 50, "combat entry to combat end")
    assertEqual(r.dps, 1000)
end)

test("record: the fight's casts are packed into the record", function()
    local inst, _, heard = fresh()
    local NS = inst.NS
    local f = fakeFight(NS)
    at(inst, 100)
    NS.Casts.Begin(f.id, 100, f)
    at(inst, 101)
    NS.Casts.Record("player", 133, 101, false)
    at(inst, 102.5)
    NS.Casts.Record("pet", 17253, 102.5, false)
    at(inst, 170)
    finish(NS, f, fakeFinal())
    local r = heard.saved[1]
    local casts = NS.CastCodec.Decode(r.casts)
    assertEqual(#casts, 2)
    assertEqual(casts[1].spellID, 133)
    assertEqual(casts[1].t, 1)
    assertEqual(casts[2].unit, "pet")
    assertEqual(casts[2].t, 2.5)
end)

test("record: the enemies are summed across a merged fight's sessions", function()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    meter.SetSession(1, { damage = 100, dps = 1, duration = 30, spells = {},
                          enemies = { { name = "Add", creatureID = 7, damage = 600 },
                                      { name = "Boss", creatureID = 9, damage = 500 } } })
    meter.SetSession(2, { damage = 100, dps = 1, duration = 30, spells = {},
                          enemies = { { name = "Boss", creatureID = 9, damage = 900 } } })
    local f = fakeFight(NS)
    f.sessions, f.sessionSet = { 1, 2 }, { [1] = true, [2] = true }
    finish(NS, f, fakeFinal())
    local r = heard.saved[1]
    assertEqual(r.identity.targetName, "Boss", "1400 across both sessions beats 600")
    assertEqual(r.identity.otherTargets, 1)
end)

test("record: 5-min raid record < 6 KB", function()
    local inst, _, heard = fresh()
    local NS = inst.NS
    local f = fakeFight(NS, { len = 300, encounter = { id = 3176, name = "Chrome King Gallywix", difficultyID = 15,
                                                     groupSize = 20, startT = 100, endT = 400, success = true } })
    f.snapshot.where = { instanceType = "raid", instanceName = "Liberation of Undermine", instanceID = 2769,
                         difficultyID = 15, difficultyName = "Heroic", maxPlayers = 30 }
    f.loadout = { talents = { importString = ("C0PAAAAAAAAAAAAAAAAAAAAAAAAAAA"):rep(6), specID = 63,
                              name = "Raid ST", heroSpecID = 58, heroName = "Sunfury" } }
    local gear = {}
    for slot = 1, 17 do gear[slot] = ("2120%02d::::::::80:267::6:2:10390:1540"):format(slot) end
    f.gearSet = NS.Loadouts.StoreGear(gear)
    f.stats = NS.Stats.Read()
    -- 300 casts: a press every second across 40 spells, a pet cast every third second.
    at(inst, 100)
    NS.Casts.Begin(f.id, 100, f)
    for i = 1, 300 do
        at(inst, 100 + i)
        NS.Casts.Record("player", 400000 + (i % 40), 100 + i, i % 50 == 0)
        if i % 3 == 0 then NS.Casts.Record("pet", 17253, 100 + i + 0.5, false) end
    end
    local spells = {}
    for i = 1, 40 do spells[i] = { spellID = 400000 + i, total = 1234567 * i, isPet = i > 34 } end
    local final = { duration = 300, player = { total = 900000000, dps = 3000000, spells = {} },
                    pet = { total = 90000000, dps = 300000, spells = {} },
                    merged = { total = 990000000, dps = 3300000, spells = spells } }
    finish(NS, f, final)
    local r = heard.saved[1]
    assertTrue(r ~= nil, "stored")
    local bytes = NS.Retention.SizeOf(r)
    assertTrue(bytes < 6144, "the record is " .. bytes .. " bytes")
end)

-- ── the store ──────────────────────────────────────────────────────────────────────────────────

test("record: All walks newest first; Delete and SetNote edit the store and say so", function()
    local inst, _, heard = fresh()
    local NS = inst.NS
    local R = NS.Recorder
    finish(NS, fakeFight(NS, { id = "a" }), fakeFinal())
    finish(NS, fakeFight(NS, { id = "b" }), fakeFinal())
    local first, second = heard.saved[1], heard.saved[2]
    local seen = {}
    for r in R.All() do seen[#seen + 1] = r end
    assertEqual(#seen, 2)
    assertEqual(seen[1], second, "newest first")
    assertEqual(seen[2], first)
    assertEqual(R.Count(), 2)
    local changed = heard.changed
    assertTrue(R.SetNote(first.id, "  first pull  "))
    assertEqual(R.Get(first.id).note, "first pull", "trimmed")
    assertEqual(heard.changed, changed + 1, "FIGHTS_CHANGED")
    assertTrue(R.SetNote(first.id, ""))
    assertNil(R.Get(first.id).note, "an empty note is no note")
    assertTrue(R.SetNote(first.id, ("x"):rep(500)))
    assertEqual(#R.Get(first.id).note, R.NOTE_MAX, "clamped")
    assertFalse(R.SetNote("nope", "x"))
    assertTrue(R.Delete(second.id))
    assertNil(R.Get(second.id))
    assertEqual(#NS.db.global.fightOrder, 1)
    assertFalse(R.Delete(second.id), "already gone")
    assertNil(R.Get(nil))
    assertNil(R.Get(T.secret("a")), "a secret id is never a key")
end)

test("record: two fights saved in the same second get distinct ids", function()
    local inst, _, heard = fresh()
    local NS = inst.NS
    inst.mocks.time = function() return 1800000000 end
    for i = 1, 5 do finish(NS, fakeFight(NS, { id = "same-" .. i }), fakeFinal()) end
    local ids = {}
    for _, r in ipairs(heard.saved) do
        assertNil(ids[r.id], "unique " .. r.id)
        ids[r.id] = true
    end
    assertEqual(count(NS), 5)
end)

test("reload mid-fight leaves store valid", function()
    local inst, meter = fresh()
    local NS = inst.NS
    at(inst, 10)
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    inst.mocks.__fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 1)
    assertEqual(count(NS), 0, "nothing written while the fight runs")
    leave(inst, 50)
    assertEqual(count(NS), 0, "nor while it settles")
    assertEqual(#NS.db.global.fightOrder, 0)
    -- The /reload: the same SavedVariables come back on a new instance.
    local saved = _G.CombatTrailDB
    local again = T.load{ init = false }
    _G.CombatTrailDB = saved
    local AceAddon = again.mocks.LibStub("AceAddon-3.0")
    AceAddon:InitializeAddon(again.NS)
    AceAddon:EnableAddon(again.NS)
    assertEqual(again.NS.Recorder.Count(), 0)
    assertEqual(#again.NS.db.global.fightOrder, 0)
    assertEqual(again.NS.Fight.State(), "idle", "the fight in memory is gone, not resumed")
end)

test("no secret reaches the record", function()
    local inst, _, heard = fresh()
    local NS = inst.NS
    local f = fakeFight(NS)
    f.snapshot.who.specName = T.secret("Fire")
    f.snapshot.who.ilvl = T.secret(650)
    f.snapshot.target.name = T.secret("Angry Boar")
    f.stats = { v = 1, crit = T.secret(25), haste = 12.5 }
    f.gearSet = T.secret("deadbeef")
    local final = fakeFinal()
    final.merged.spells[2] = { spellID = 999, total = T.secret(5), isPet = false }
    finish(NS, f, final)
    local r = heard.saved[1]
    assertTrue(r ~= nil, "stored")
    assertNil(r.who.specName, "a sealed field is absent")
    assertNil(r.who.ilvl)
    assertEqual(r.who.name, "Tush", "the plain fields stay")
    assertEqual(r.identity.targetCreatureID, 1985, "the target is still known by its creature")
    assertNil(r.gearSet, "a sealed gear set key is absent")
    assertNil(r.gear)
    local spells = NS.Recorder.Spells(r)
    assertEqual(#spells, 1, "a spell whose total is sealed is left out")
    assertEqual(spells[1].spellID, 133)
    -- And nothing anywhere in the record is secret.
    local function walk(v, path)
        assertFalse(T.isSecret(v), "secret at " .. path)
        if type(v) == "table" and not T.isSecret(v) then
            for k, x in pairs(v) do
                assertFalse(T.isSecret(k), "secret key at " .. path)
                walk(x, path .. "." .. tostring(k))
            end
        end
    end
    walk(r, "record")
end)

-- ── deferred review items (plan Task 5.2b) ──────────────────────────────────────────────────────

test("record: a short fight with no readable character is skipped as short, the filters first", function()
    local inst, _, heard = fresh()
    local NS = inst.NS
    local f = fakeFight(NS, { len = 5 })
    f.snapshot.who.name = nil
    finish(NS, f, fakeFinal({ duration = 5 }))
    assertEqual(heard.skipped[1].reason, "short")
    NS.db.profile.history.bossesOnly = true
    f = fakeFight(NS, { id = "fake-2" })
    f.snapshot.who.name = nil
    finish(NS, f, fakeFinal())
    assertEqual(heard.skipped[2].reason, "filtered")
end)

test("record: three fights in the same gear share one gear set; a swap between fights is a second", function()
    local inst, meter, heard = fresh()
    local NS, M = inst.NS, inst.mocks
    -- Fight n on meter session n, a minute apart.
    local function nth(n)
        local t0 = n * 1000
        at(inst, t0)
        meter.SetSession(n, FIGHT)
        enter(inst, t0)
        at(inst, t0 + 1)
        M.__fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, n)
        leave(inst, t0 + 40)
        settle(inst, t0 + 45)
        settle(inst, t0 + 50)
    end
    for i = 1, 3 do
        nth(i)
        M.__fire("PLAYER_ENTERING_WORLD", false, true)
        M.__fireTimers()
        assertEqual(#heard.saved, i, "fight " .. i .. " saved")
    end
    local key = heard.saved[1].gearSet
    assertTrue(key ~= nil)
    assertEqual(heard.saved[2].gearSet, key)
    assertEqual(heard.saved[3].gearSet, key)
    assertEqual(NS.Loadouts.GearCount(), 1, "one set for three fights")
    M.__gear[16] = "|cnIQ3:|Hitem:299999::::::::80:267::::::|h[Other Staff]|h|r"
    M.__fire("PLAYER_EQUIPMENT_CHANGED", 16, true)
    M.__fireTimers()
    nth(4)
    assertEqual(#heard.saved, 4)
    assertTrue(heard.saved[4].gearSet ~= key, "the new weapon is another set")
    assertEqual(NS.Loadouts.GearCount(), 2)
    -- Deleting the fights on a set no longer current drops that set too.
    for i = 1, 3 do NS.Recorder.Delete(heard.saved[i].id) end
    assertNil(NS.Loadouts.GetGear(key), "the orphaned set swept with its last fight")
    assertTrue(NS.Loadouts.GetGear(heard.saved[4].gearSet) ~= nil)
end)
