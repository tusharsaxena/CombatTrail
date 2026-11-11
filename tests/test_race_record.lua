-- tests/test_race_record.lua — modules/RaceRecord.lua and Recorder's race rule (Race mode plan Task A3,
-- the Race mode spec §3.4, §4.1 and §6): a fight that carries a complete or incomplete race is saved
-- whatever its length and content, with its plain race part; a canceled or lost race drops the part
-- and the pull takes the normal filters as a plain dummy fight; no secret reaches the part; the race
-- DPS is the score over the race length (over endedAt when incomplete); and a CT_SCHEMA 3 store loads
-- unchanged under 4. Runs under both kit profiles: races are Retail's, but the records are
-- account-wide, so WoW Forever reads them too.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local DUMMY = 31146   -- a Retail seed dummy; on WoW Forever it is a plain NPC, which these cases allow

local function fresh()
    local inst = T.load{ mutate = function(m) T.mockMeter.install(m) end }
    local NS = inst.NS
    local heard = { saved = {}, skipped = {} }
    local rx = NS.NewBusTarget()
    rx:RegisterMessage(NS.MSG.FIGHT_SAVED, function(_, r) heard.saved[#heard.saved + 1] = r end)
    rx:RegisterMessage(NS.MSG.FIGHT_SKIPPED, function(_, f, why)
        heard.skipped[#heard.skipped + 1] = { fight = f, reason = why }
    end)
    return inst, heard
end

-- A race part as the race engine (Task B1) leaves it on the fight.
local function racePart(o)
    o = o or {}
    return {
        length = o.length or 10, kind = o.kind or "single", status = o.status or "complete",
        flags = o.flags or { lateCasts = {}, reloaded = false, died = false },
        score = o.score or 50000, dps = o.dps or 5000, tail = 1.2, endedAt = o.endedAt, combatEnd = 0.8,
        grace = 1.0, restartGap = 6,
    }
end

-- A fight table as modules/Fight.lua hands it over, `len` seconds long, on a training dummy.
local function fakeFight(NS, o)
    o = o or {}
    return {
        id = o.id or "race-fight-1", startT = 100, combatEndT = 100 + (o.len or 10), sessions = { 1 },
        sessionID = 1, sessionSet = { [1] = true }, race = o.race,
        snapshot = {
            who = { name = "Tush", realm = "Area 52", class = "MAGE", specID = 63, specName = "Fire",
                    ilvl = 650.5, client = NS.Compat.ClientKey() },
            target = { name = "Training Dummy", creatureID = DUMMY },
            where = { instanceType = "none", difficultyID = 0 },
        },
    }
end

local function fakeFinal(len, total)
    total = total or 50000
    return { duration = len,
             player = { total = total, dps = total / len, spells = { { spellID = 133, total = total, dps = 1 } } },
             merged = { total = total, dps = total / len, spells = { { spellID = 133, total = total, isPet = false } } } }
end

local function finish(NS, fight, final, reason)
    NS.SendBus(NS.MSG.FIGHT_ENDED, fight, final, reason or "final")
end

-- ── Recorder's race rule ────────────────────────────────────────────────────────────────────────

test("race record: a complete race is saved however short", function()
    local inst, heard = fresh()
    local NS = inst.NS
    NS.db.profile.history.minLength = 30
    NS.db.profile.history.content.dummy = false
    NS.db.profile.history.content.world = false
    finish(NS, fakeFight(NS, { len = 10, race = racePart({ length = 10 }) }), fakeFinal(10))
    assertEqual(#heard.saved, 1, "saved past the minimum length and the content toggles")
    assertEqual(#heard.skipped, 0)
    local r = heard.saved[1]
    assertTrue(NS.RaceRecord.IsRace(r))
    assertEqual(r.race.length, 10)
    assertEqual(r.race.kind, "single")
    assertEqual(r.race.status, "complete")
    assertEqual(r.race.score, 50000)
    assertEqual(r.race.dps, 5000)
    assertEqual(r.race.grace, 1.0)
    assertEqual(r.race.restartGap, 6)
    assertEqual(r.status, "final", "the record's own status stays final")
    assertEqual(r.duration, 10, "the fight's own duration stays in the record")
    assertEqual(NS.Recorder.CT_SCHEMA, 4)
    assertEqual(r.schema, 4)
end)

test("race record: an incomplete race is saved too, with its endedAt", function()
    local inst, heard = fresh()
    local NS = inst.NS
    local part = racePart({ length = 60, status = "incomplete", endedAt = 8, score = 40000, dps = 5000 })
    finish(NS, fakeFight(NS, { len = 8, race = part }), fakeFinal(8, 40000))
    assertEqual(#heard.saved, 1)
    assertEqual(heard.saved[1].race.status, "incomplete")
    assertEqual(heard.saved[1].race.endedAt, 8)
end)

test("race record: a canceled race saves the pull as a plain dummy fight under the normal filters", function()
    local inst, heard = fresh()
    local NS = inst.NS
    NS.db.profile.history.minLength = 30
    local long = fakeFight(NS, { id = "long", len = 40, race = racePart({ status = "canceled" }) })
    finish(NS, long, fakeFinal(40))
    assertEqual(#heard.saved, 1, "a 40 s pull passes the filters")
    assertNil(heard.saved[1].race, "no race part")
    assertFalse(NS.RaceRecord.IsRace(heard.saved[1]))
    assertNil(long.race, "the part is taken off the fight")
    local short = fakeFight(NS, { id = "short", len = 10, race = racePart({ status = "canceled" }) })
    finish(NS, short, fakeFinal(10))
    assertEqual(#heard.saved, 1, "a 10 s canceled pull is not saved")
    assertEqual(heard.skipped[1].reason, "short", "the normal filters judged it")
end)

test("race record: a lost race is not a race", function()
    local inst, heard = fresh()
    local NS = inst.NS
    NS.db.profile.history.minLength = 30
    finish(NS, fakeFight(NS, { id = "a", len = 40, race = racePart({ status = "lost" }) }), fakeFinal(40))
    assertEqual(#heard.saved, 1, "the pull is kept as a plain fight")
    assertNil(heard.saved[1].race)
    finish(NS, fakeFight(NS, { id = "b", len = 10, race = racePart({ status = "lost" }) }), fakeFinal(10))
    assertEqual(heard.skipped[1].reason, "short")
    finish(NS, fakeFight(NS, { id = "c", len = 10, race = racePart() }), nil, "lost")
    assertEqual(heard.skipped[2].reason, "lost", "a fight that ended lost saves nothing, race or not")
    assertEqual(#heard.saved, 1)
end)

test("race record: a race still needs a character", function()
    local inst, heard = fresh()
    local NS = inst.NS
    local f = fakeFight(NS, { race = racePart() })
    f.snapshot.who.name = nil
    finish(NS, f, fakeFinal(10))
    assertEqual(#heard.saved, 0)
    assertEqual(heard.skipped[1].reason, "unknown")
end)

test("race record: Recorder asks the race to finalize before it judges the fight", function()
    local inst, heard = fresh()
    local NS = inst.NS
    local seen
    NS.Race = { Finalize = function(fight, final, reason)
        seen = { fight = fight, final = final, reason = reason }
        fight.race = racePart({ length = 10 })
    end }
    local f = fakeFight(NS, { len = 10 })
    local final = fakeFinal(10)
    finish(NS, f, final)
    NS.Race = nil
    assertEqual(seen.fight, f)
    assertEqual(seen.final, final)
    assertEqual(seen.reason, "final")
    assertEqual(#heard.saved, 1, "the part Finalize set is what Recorder saved")
    assertTrue(NS.RaceRecord.IsRace(heard.saved[1]))
end)

test("race record: no secret reaches the race part", function()
    local inst, heard = fresh()
    local NS = inst.NS
    local part = racePart()
    part.score = T.secret(50000)
    part.tail = T.secret(1.5)
    part.kind = T.secret("single")
    part.flags = { lateCasts = { { t = 1.4, spellID = T.secret(133) }, { t = 2.0, spellID = 11366 } },
                   died = T.secret(true), reloaded = false, sharedSession = true }
    part.stray = "not a race field"
    part[T.secret("k")] = 1
    finish(NS, fakeFight(NS, { race = part }), fakeFinal(10))
    local r = heard.saved[1]
    assertTrue(r ~= nil, "saved")
    local function walk(v, path)
        assertFalse(T.isSecret(v), "secret at " .. path)
        if type(v) == "table" and not T.isSecret(v) then
            for k, x in pairs(v) do
                assertFalse(T.isSecret(k), "secret key at " .. path)
                walk(x, path .. "." .. tostring(k))
            end
        end
    end
    walk(r.race, "race")
    assertNil(r.race.score, "a sealed score is left out")
    assertNil(r.race.tail)
    assertNil(r.race.kind)
    assertNil(r.race.stray, "only the race part's own fields")
    assertNil(r.race.flags.died, "a sealed flag is left out")
    assertEqual(r.race.flags.sharedSession, true)
    assertEqual(#r.race.flags.lateCasts, 2, "each late cast kept")
    assertNil(r.race.flags.lateCasts[1].spellID, "its sealed spell left out")
    assertEqual(r.race.flags.lateCasts[1].t, 1.4)
    assertEqual(r.race.flags.lateCasts[2].spellID, 11366)
end)

-- ── RaceRecord ──────────────────────────────────────────────────────────────────────────────────

test("race record: Plain answers nil for anything but a table, and copies the spec §6 fields", function()
    local RR = T.NS.RaceRecord
    assertNil(RR.Plain(nil))
    assertNil(RR.Plain("race"))
    local p = RR.Plain(racePart({ status = "incomplete", endedAt = 7.5 }))
    assertEqual(p.length, 10)
    assertEqual(p.endedAt, 7.5)
    assertEqual(p.combatEnd, 0.8)
    assertEqual(p.flags.reloaded, false)
    assertEqual(type(p.flags.lateCasts), "table")
end)

test("race record: Plain keeps the first hit's offset only when it is a plain number (ruling X9)", function()
    local RR = T.NS.RaceRecord
    local part = racePart()
    part.firstHit = 1.25
    assertEqual(RR.Plain(part).firstHit, 1.25, "seconds from combat entry to the first hit")
    part.firstHit = T.secret(1.25)
    assertNil(RR.Plain(part).firstHit, "a sealed offset is left out")
    part.firstHit = "1.25"
    assertNil(RR.Plain(part).firstHit, "so is one of the wrong type")
end)

test("race record: FirstHit is the race clock's zero on the fight clock, 0 for no shift", function()
    local RR = T.NS.RaceRecord
    assertEqual(RR.FirstHit({ race = { firstHit = 1.5 } }), 1.5)
    assertEqual(RR.FirstHit({ race = {} }), 0, "a race saved without it: no shift")
    assertEqual(RR.FirstHit({ race = { firstHit = -2 } }), 0, "never a shift back")
    assertEqual(RR.FirstHit({ race = { firstHit = "1" } }), 0)
    assertEqual(RR.FirstHit({ dps = 100 }), 0, "a fight runs on its own clock")
    assertEqual(RR.FirstHit(nil), 0)
end)

test("race record: OnClock answers casts moved onto a later zero, a copy, the list untouched", function()
    local RR = T.NS.RaceRecord
    local casts = { { t = 0.5, spellID = 1 }, { t = 4, spellID = 2, unit = "pet" } }
    local moved = RR.OnClock(casts, 1.5)
    assertEqual(moved[1].t, -1, "a cast before the first hit is before the race clock's zero")
    assertEqual(moved[2].t, 2.5)
    assertEqual(moved[2].unit, "pet", "every other field copied")
    assertEqual(casts[2].t, 4, "the list handed in is not changed")
    assertTrue(RR.OnClock(casts, 0) == casts, "no shift: the same list")
end)

test("race record: IsRace is a record with a race part", function()
    local RR = T.NS.RaceRecord
    assertTrue(RR.IsRace({ race = {} }))
    assertFalse(RR.IsRace({}))
    assertFalse(RR.IsRace(nil))
    assertFalse(RR.IsRace({ race = "x" }))
end)

test("race record: Dps is the race DPS for a race, the fight DPS otherwise", function()
    local RR = T.NS.RaceRecord
    assertEqual(RR.Dps({ dps = 900, race = { status = "complete", length = 10, score = 50000, dps = 5000 } }), 5000)
    assertEqual(RR.Dps({ dps = 900, race = { status = "complete", length = 10, score = 50000 } }), 5000,
        "worked out from the score when no dps is stored")
    assertEqual(RR.Dps({ dps = 900 }), 900)
    assertNil(RR.Dps({}))
    assertNil(RR.Dps(nil))
end)

test("race record: ScoreDps is the score over the length, over endedAt when incomplete", function()
    local RR = T.NS.RaceRecord
    assertEqual(RR.ScoreDps(60000, { status = "complete", length = 60, endedAt = 30 }), 1000)
    assertEqual(RR.ScoreDps(60000, { status = "incomplete", length = 60, endedAt = 30 }), 2000)
    assertEqual(RR.ScoreDps(60000, { status = "incomplete", length = 60 }), 0, "no divisor yet")
    assertEqual(RR.ScoreDps(nil, { status = "complete", length = 60 }), 0)
    assertEqual(RR.ScoreDps(100, { status = "complete", length = 0 }), 0)
end)

test("race record: Flagged reads the race part's flags and its status", function()
    local RR = T.NS.RaceRecord
    local function rec(flags, status) return { race = { status = status or "complete", flags = flags } } end
    assertFalse(RR.Flagged(rec({ lateCasts = {}, reloaded = false, died = false })), "clean")
    assertFalse(RR.Flagged(rec(nil)), "no flags at all")
    assertTrue(RR.Flagged(rec({ lateCasts = { { t = 1.4, spellID = 133 } } })))
    assertTrue(RR.Flagged(rec({ restartedAt = 12.5 })))
    for _, key in ipairs({ "reloaded", "died", "sessionFromList", "sharedSession" }) do
        assertTrue(RR.Flagged(rec({ [key] = true })), key)
    end
    assertTrue(RR.Flagged(rec({}, "incomplete")), "incomplete")
    assertFalse(RR.Flagged({ dps = 1 }), "a fight is never flagged")
end)

-- ── the store's format ──────────────────────────────────────────────────────────────────────────

test("database: schema 3 records load unchanged under 4", function()
    local inst = T.load{ init = false }
    local old = { schema = 3, id = "f-3", t = os.time(), duration = 60, status = "final", dps = 100,
                  boardKey = "c:1:0", targets = { { name = "Boar", total = 6000 } } }
    _G.CombatTrailDB = { global = { schemaVersion = 2, fights = { [old.id] = old }, fightOrder = { old.id } } }
    local AceAddon = inst.mocks.LibStub("AceAddon-3.0")
    AceAddon:InitializeAddon(inst.NS)
    AceAddon:EnableAddon(inst.NS)
    local NS = inst.NS
    local r = NS.Recorder.Get("f-3")
    assertTrue(r ~= nil, "listed")
    assertEqual(r.schema, 3, "not rewritten")
    assertEqual(r.targets[1].total, 6000, "its shape kept")
    assertNil(r.race, "no race part")
    assertFalse(NS.RaceRecord.IsRace(r))
    assertEqual(NS.RaceRecord.Dps(r), 100)
    assertEqual(#NS.Recorder.List(), 1)
    local later = { schema = 5, id = "f-5", t = os.time(), status = "final" }
    NS.db.global.fights[later.id] = later
    assertNil(NS.Recorder.Get("f-5"), "a record from a later format is still left alone")
end)
