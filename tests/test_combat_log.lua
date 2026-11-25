-- tests/test_combat_log.lua — modules/CombatLog.lua, the Combat Log's capture and store (CombatTrail #11,
-- plan item CL-11a): the casts from the lanes' listener, UNIT_AURA's gains and losses on the player and
-- the target, UNIT_COMBAT's hits and heals on the player (school, critical, glancing, a sealed amount
-- saved as "s"), the player's death and the fight's boundaries; the in-memory ring and its bound; the
-- saved `log` on the record (oldest first, at most `log.store.lines`, the newest kept and the rest
-- counted in `logDropped`, only the categories saved); the events registered only while a fight is
-- open; the record schema's step to CT_SCHEMA 6 (an older fight reads with no log); and the stored size
-- of a log at the cap. Runs under both kit profiles: the capture is the same on Retail and WoW Forever.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertNil = T.test, T.assertEqual, T.assertTrue, T.assertNil

local FIGHT = { damage = 40000, dps = 1000, duration = 40,
                spells = { { id = 133, dmg = 30000, dps = 750 }, { id = 11366, dmg = 10000, dps = 250 } },
                enemies = { { name = "Angry Boar", creatureID = 1985, damage = 40000 } } }

local FIREBALL, PYROBLAST, BITE = 133, 11366, 17253
local INTELLECT, POLY, IGNITE, MARK = 1459, 118, 12654, 1126

-- A fresh instance on the scripted meter, the auras on each unit scripted by `m.__unitAuras`
-- ([unit][filter] = { aura, ... }), and a receiver for the saved fights.
local function fresh(o)
    o = o or {}
    local meter
    local inst = T.load{ mutate = function(m)
        meter = T.mockMeter.install(m)
        m.__unitAuras = { player = { HELPFUL = {}, HARMFUL = {} }, target = { HELPFUL = {}, HARMFUL = {} } }
        m.C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
            local byUnit = m.__unitAuras[unit]
            local list = byUnit and byUnit[filter]
            return list and list[i] or nil
        end
        if o.mutate then o.mutate(m) end
    end }
    local saved = {}
    local rx = inst.NS.NewBusTarget()
    rx:RegisterMessage(inst.NS.MSG.FIGHT_SAVED, function(_, r) saved[#saved + 1] = r end)
    return inst, meter, saved
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

local guid = 0
local function cast(inst, t, unit, id)
    at(inst, t)
    guid = guid + 1
    inst.mocks.__fire("UNIT_SPELLCAST_SUCCEEDED", unit, "Cast-" .. guid, id)
end

local function aura(inst, t, unit, info)
    at(inst, t)
    inst.mocks.__fire("UNIT_AURA", unit, info)
end

local function hit(inst, t, action, amount, school, descriptor)
    at(inst, t)
    inst.mocks.__fire("UNIT_COMBAT", "player", action, descriptor or "", amount, school or 1)
end

-- One whole fight from 10 to 10 + len on session 1, with what `during(inst)` does in it. Answers the
-- stored record (nil when none was saved).
-- `session` is the meter's (FIGHT by default), `base` the start (10 by default) and `sid` the meter
-- session's ID (1 by default: a later fight needs a new one).
local function fightThrough(inst, meter, saved, len, during, session, base, sid)
    base, sid = base or 10, sid or 1
    at(inst, base)
    meter.SetSession(sid, session or FIGHT)
    enter(inst, base)
    at(inst, base + 1)
    inst.mocks.__fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, sid)
    if during then during(inst) end
    leave(inst, base + len)
    settle(inst, base + len + 5)
    settle(inst, base + len + 10)
    return saved[#saved]
end

local function kinds(NS, log)
    local name = {}
    for key, code in pairs(NS.CombatLog.KIND) do name[code] = key end
    local out = {}
    for i, e in ipairs(log or {}) do out[i] = name[e.k] end
    return table.concat(out, ",")
end

-- The Combat Log frame's registrations: [event] = a row, and `units` [event] = { [unit] = true }.
local function unitRegs(inst)
    local out, units = {}, {}
    for _, r in ipairs(inst.mocks.__registrations()) do
        if r.target == inst.NS.CombatLog.EventFrame() then
            out[r.event] = r
            units[r.event] = units[r.event] or {}
            if r.unit then units[r.event][r.unit] = true end
        end
    end
    if next(out) == nil then return out end
    out.units = units
    return out
end

-- ── the capture, end to end ─────────────────────────────────────────────────────────────────────

test("combat log: a fight's casts, auras, hits, heals and boundaries are saved with its record", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    local K, U, F = NS.CombatLog.KIND, NS.CombatLog.UNIT, NS.CombatLog.FLAG
    local r = fightThrough(inst, meter, saved, 40, function(i)
        cast(i, 12, "player", FIREBALL)
        cast(i, 13.04, "pet", BITE)
        aura(i, 14, "player", { addedAuras = { { auraInstanceID = 7, spellId = INTELLECT, isHelpful = true,
                                                 isHarmful = false } } })
        aura(i, 15, "target", { addedAuras = { { auraInstanceID = 8, spellId = IGNITE, isHarmful = true,
                                                 isFromPlayerOrPlayerPet = true } } })
        hit(i, 16, "WOUND", 1200, 4, "CRITICAL")
        hit(i, 17, "HEAL", 800, 2)
        aura(i, 18, "target", { removedAuraInstanceIDs = { 8 } })
        aura(i, 19, "player", { removedAuraInstanceIDs = { 7 } })
        at(i, 20)
        i.mocks.__fire("PLAYER_DEAD")
    end)
    assertTrue(r ~= nil, "the fight was saved")
    assertEqual(r.schema, 6)
    local log, dropped = NS.CombatLog.Of(r)
    assertEqual(kinds(NS, log), "START,CAST,CAST,BUFF_ON,DEBUFF_ON,HIT,HEAL,DEBUFF_OFF,BUFF_OFF,DIES,END")
    assertEqual(dropped, 0)
    assertNil(r.logDropped, "nothing dropped: no field")
    assertEqual(log[1].t, 0)
    assertEqual(log[2].t, 2)
    assertEqual(log[2].id, FIREBALL)
    assertEqual(log[2].u, U.player)
    assertEqual(log[3].t, 3, "to the tenth")
    assertEqual(log[3].u, U.pet)
    assertEqual(log[4].id, INTELLECT)
    assertEqual(log[4].u, U.player)
    assertEqual(log[5].id, IGNITE)
    assertEqual(log[5].u, U.target)
    assertEqual(log[6].a, 1200)
    assertEqual(log[6].s, 4, "the school")
    assertEqual(log[6].f, F.CRIT)
    assertEqual(log[7].k, K.HEAL)
    assertEqual(log[7].a, 800)
    assertNil(log[7].f)
    assertEqual(log[8].id, IGNITE, "a loss names the spell its instance was given for")
    assertEqual(log[11].t, 40, "the combat end")
    for _, e in ipairs(log) do
        for key, v in pairs(e) do
            assertTrue(type(v) == "number" or v == NS.CombatLog.SEALED, key .. " is a number (or the sealed mark)")
        end
    end
end)

test("combat log: a pre-pull cast is kept at a negative time; an auto attack reaches the ring, never the log", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    cast(inst, 5, "player", PYROBLAST)
    local r = fightThrough(inst, meter, saved, 40, function(i)
        cast(i, 12, "player", 6603)    -- Auto Attack
        cast(i, 13, "player", FIREBALL)
    end)
    local log = NS.CombatLog.Of(r)
    assertEqual(kinds(NS, log), "CAST,START,CAST,END")
    assertEqual(log[1].t, -5)
    assertEqual(log[1].id, PYROBLAST)
    local autos = 0
    for n = NS.CombatLog.First(), NS.CombatLog.Seq() do
        local e = NS.CombatLog.Line(n)
        if e and e.id == 6603 then autos = autos + 1 end
    end
    assertEqual(autos, 1, "the ring holds the swing for a view")
end)

test("combat log: the target's debuffs are only the player's, and a target change logs nothing", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    local r = fightThrough(inst, meter, saved, 40, function(i)
        aura(i, 12, "target", { addedAuras = {
            { auraInstanceID = 21, spellId = 589, isHarmful = true, isFromPlayerOrPlayerPet = false },
            { auraInstanceID = 22, spellId = MARK, isHelpful = true, isHarmful = false },
            { auraInstanceID = 23, spellId = POLY, isHarmful = true, sourceUnit = "pet" } } })
        i.mocks.__unitAuras.target.HELPFUL = { { auraInstanceID = 30, spellId = 21562, isHelpful = true } }
        at(i, 13)
        i.mocks.__fire("PLAYER_TARGET_CHANGED")
        aura(i, 14, "target", { isFullUpdate = true })
        aura(i, 15, "target", { removedAuraInstanceIDs = { 30, 22 } })
        aura(i, 16, "focus", { addedAuras = { { auraInstanceID = 40, spellId = 1, isHelpful = true } } })
    end)
    local log = NS.CombatLog.Of(r)
    assertEqual(kinds(NS, log), "START,BUFF_ON,DEBUFF_ON,BUFF_OFF,END",
        "someone else's debuff and the focus are no line; the new target's buff ends with a loss")
    assertEqual(log[2].id, MARK)
    assertEqual(log[3].id, POLY, "the pet's debuff counts as the player's")
    assertEqual(log[4].id, 21562, "the new target's aura, walked at the change, is known when it goes")
end)

test("combat log: an aura on at the start is known when it falls off", function()
    local inst, meter, saved = fresh{ mutate = function(m)
        m.__unitAuras.player.HELPFUL = { { auraInstanceID = 3, spellId = INTELLECT, isHelpful = true } }
    end }
    local NS = inst.NS
    local r = fightThrough(inst, meter, saved, 40, function(i)
        aura(i, 20, "player", { removedAuraInstanceIDs = { 3, 99 } })
    end)
    local log = NS.CombatLog.Of(r)
    assertEqual(kinds(NS, log), "START,BUFF_OFF,END", "an unknown instance is no line")
    assertEqual(log[2].id, INTELLECT)
end)

-- ── secrets ─────────────────────────────────────────────────────────────────────────────────────

test("combat log: a sealed aura and a sealed cast are no line; a sealed amount is saved as \"s\"", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local inst, meter, saved = fresh()
        local NS = inst.NS
        local r = fightThrough(inst, meter, saved, 40, function(i)
            aura(i, 12, "player", { addedAuras = { { auraInstanceID = 5, spellId = T.secret(INTELLECT), isHelpful = true },
                                                   { auraInstanceID = T.secret(6), spellId = MARK, isHelpful = true } } })
            aura(i, 13, "player", T.secret({}))
            cast(i, 14, "player", T.secret(FIREBALL))
            hit(i, 15, "WOUND", T.secret(900), 1, "GLANCING")
            hit(i, 16, T.secret("WOUND"), 900)
        end)
        local log = NS.CombatLog.Of(r)
        assertEqual(kinds(NS, log), "START,HIT,END", "only the hit, its amount sealed")
        assertEqual(log[2].a, NS.CombatLog.SEALED)
        assertEqual(log[2].f, NS.CombatLog.FLAG.GLANCING)
        local live
        for n = NS.CombatLog.First(), NS.CombatLog.Seq() do
            local e = NS.CombatLog.Line(n)
            if e and e.k == NS.CombatLog.KIND.HIT then live = e end
        end
        assertTrue(T.isSecret(live.x), "the ring keeps the client's value for display")
        assertNil(log[2].x, "never saved")
    end)
    restore()
    if not ok then error(err, 0) end
end)

-- ── the cap and the categories ──────────────────────────────────────────────────────────────────

test("combat log: past `log.store.lines` only the newest are kept and the record counts the rest", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    NS.db.profile.log.store.lines = 100
    local r = fightThrough(inst, meter, saved, 40, function(i)
        for n = 1, 250 do hit(i, 11 + n * 0.1, "WOUND", n) end
    end)
    local log, dropped = NS.CombatLog.Of(r)
    assertEqual(#log, 100)
    assertEqual(log[#log].k, NS.CombatLog.KIND.END, "the newest kept")
    assertEqual(log[1].a, 152, "hits 152 to 250, then the end")
    assertEqual(dropped, 151)
    assertEqual(r.logDropped, 151)
end)

test("combat log: the default keeps C.LOG.MAX_PER_FIGHT lines, and a setting is held to its range", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    local C = NS.Constants.LOG
    assertEqual(C.MAX_PER_FIGHT, 400)
    assertEqual(NS.GetSetting("log.store.lines"), 400)
    NS.db.profile.log.store.lines = 5
    local r = fightThrough(inst, meter, saved, 40, function(i)
        for n = 1, 150 do hit(i, 11 + n * 0.1, "WOUND", n) end
    end)
    assertEqual(#NS.CombatLog.Of(r), C.MIN_PER_FIGHT, "a stored 5 reads as the least, 100")
end)

test("combat log: a category not saved is no line and not counted as dropped", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    NS.db.profile.log.store.categories.hits = false
    NS.db.profile.log.store.categories.petCasts = false
    local r = fightThrough(inst, meter, saved, 40, function(i)
        hit(i, 12, "WOUND", 10)
        hit(i, 13, "HEAL", 10)
        cast(i, 14, "pet", BITE)
        cast(i, 15, "player", FIREBALL)
    end)
    local log, dropped = NS.CombatLog.Of(r)
    assertEqual(kinds(NS, log), "START,HEAL,CAST,END")
    assertEqual(dropped, 0)
end)

test("combat log: saving off keeps no log on the record; the log off registers nothing", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    NS.db.profile.log.store.enabled = false
    local r = fightThrough(inst, meter, saved, 40, function(i) hit(i, 12, "WOUND", 10) end)
    assertNil(r.log)
    assertNil(NS.CombatLog.Of(r))
    NS.db.profile.log.enabled = false
    local seq = NS.CombatLog.Seq()
    local r2 = fightThrough(inst, meter, saved, 40, function(i)
        assertEqual(next(unitRegs(i)), nil, "no registration in the fight")
        hit(i, 12, "WOUND", 10)
    end)
    assertTrue(r2 ~= r, "the second fight was saved")
    assertNil(r2.log)
    assertEqual(NS.CombatLog.Seq(), seq, "no line was captured")
end)

test("combat log: the settings are frozen at the fight's start", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    local r = fightThrough(inst, meter, saved, 40, function(i)
        NS.db.profile.log.store.categories.hits = false
        hit(i, 12, "WOUND", 10)
    end)
    assertEqual(kinds(NS, NS.CombatLog.Of(r)), "START,HIT,END")
end)

test("combat log: the storage keys have their shipped defaults", function()
    local NS = T.load().NS
    assertTrue(NS.GetSetting("log.enabled"))
    assertTrue(NS.GetSetting("log.store.enabled"))
    for _, key in ipairs(NS.CombatLog.CATEGORIES) do
        assertEqual(NS.defaults.profile.log.store.categories[key], true, key .. " saved by default")
    end
    local n = 0
    for _ in pairs(NS.defaults.profile.log.store.categories) do n = n + 1 end
    assertEqual(n, #NS.CombatLog.CATEGORIES, "one key per category")
end)

-- ── registration ────────────────────────────────────────────────────────────────────────────────

test("combat log: its events are registered only while a fight is open, for player and target", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    assertNil(NS.CombatLog.EventFrame(), "idle: no frame yet")
    local inFight
    fightThrough(inst, meter, saved, 40, function(i) inFight = unitRegs(i) end)
    assertTrue(inFight.UNIT_AURA ~= nil and inFight.UNIT_COMBAT ~= nil and inFight.PLAYER_DEAD ~= nil)
    assertTrue(inFight.units.UNIT_AURA.player and inFight.units.UNIT_AURA.target, "UNIT_AURA for player and target")
    assertTrue(inFight.units.UNIT_COMBAT.player and not inFight.units.UNIT_COMBAT.target, "UNIT_COMBAT for player only")
    assertEqual(next(unitRegs(inst)), nil, "the fight ended: nothing registered")
    for _, r in ipairs(inst.mocks.__registrations()) do
        assertTrue(r.event ~= "COMBAT_LOG_EVENT_UNFILTERED", "never the combat log")
    end
end)

test("combat log: a stand-down mid-fight drops every registration and line", function()
    local inst, meter = fresh()
    local NS = inst.NS
    at(inst, 10)
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    hit(inst, 11, "WOUND", 5)
    assertTrue(next(unitRegs(inst)) ~= nil)
    NS.SetByPath("general.enabled", false)
    assertEqual(next(unitRegs(inst)), nil)
    assertEqual(NS.CombatLog.Seq(), 0)
    assertEqual(NS.CombatLog.__ringCount(), 0)
    NS.SetByPath("general.enabled", true)
    assertEqual(next(unitRegs(inst)), nil, "the stand-up opens no fight")
end)

test("combat log: a client that refuses UNIT_COMBAT costs only it, and the diagnosis names it", function()
    local inst, meter, saved = fresh{ mutate = function(m) m.__badEvents = { UNIT_COMBAT = true } end }
    local NS = inst.NS
    local regs
    local r = fightThrough(inst, meter, saved, 40, function(i)
        regs = unitRegs(i)
        aura(i, 12, "player", { addedAuras = { { auraInstanceID = 1, spellId = INTELLECT, isHelpful = true } } })
    end)
    assertNil(regs.UNIT_COMBAT)
    assertTrue(regs.UNIT_AURA ~= nil)
    assertEqual(table.concat(NS.CombatLog.Diagnose().refused, ","), "UNIT_COMBAT")
    assertEqual(kinds(NS, NS.CombatLog.Of(r)), "START,BUFF_ON,END")
end)

test("combat log: the combatLog perf bucket is reached by its events", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    local noted = 0
    local note = NS.Perf.Note
    NS.Perf.Note = function(key, ...)
        if key == "combatLog" then noted = noted + 1 end
        return note(key, ...)
    end
    fightThrough(inst, meter, saved, 40, function(i)
        NS.Perf.on = true
        hit(i, 12, "WOUND", 5)
        NS.Perf.on = false
    end)
    NS.Perf.Note = note
    assertEqual(noted, 1)
end)

-- ── the ring ────────────────────────────────────────────────────────────────────────────────────

test("combat log: the ring holds at most C.LOG.RING lines and reuses its slots", function()
    local NS = fresh().NS
    local C = NS.Constants.LOG
    local CL = NS.CombatLog
    for n = 1, C.RING + 500 do CL.OnCast("player", FIREBALL, n, false) end
    assertEqual(CL.Seq(), C.RING + 500)
    assertEqual(CL.__ringCount(), C.RING)
    assertNil(CL.Line(500), "an overwritten line is gone")
    assertEqual(CL.Line(501).at, 501, "the oldest kept")
    assertEqual(CL.First(), 501)
    assertNil(CL.Line(CL.Seq() + 1))
end)

-- ── the record (CT_SCHEMA 6) ────────────────────────────────────────────────────────────────────

local function oldRecord(NS, id, schema)
    local me = NS.Identity.Who()
    local ident = { content = "world", targetName = "Boar", targetLevel = 10 }
    return {
        schema = schema, id = id, t = os.time() - 60, duration = 60, status = "final",
        who = { name = me.name, realm = me.realm, client = me.client, class = "MAGE" },
        identity = ident, boardKey = NS.Identity.BoardKey(ident),
        damage = { merged = 60000, player = 60000 }, dps = 1000, meterDps = 1000,
        spells = NS.CastCodec.EncodeSpells({ { spellID = FIREBALL, total = 60000, isPet = false } }),
    }
end

test("combat log: a CT_SCHEMA 5 record reads with no log and still opens in the Results", function()
    local inst = fresh{ mutate = function(m)
        m.StaticPopup_Show = function() end
        m.StaticPopup_Hide = function() end
    end }
    local NS = inst.NS
    assertEqual(NS.Recorder.CT_SCHEMA, 6)
    local old = oldRecord(NS, "old", 5)
    NS.db.global.fights.old = old
    table.insert(NS.db.global.fightOrder, 1, "old")
    assertEqual(NS.Recorder.Get("old"), old, "read as it is: no step, no rewrite")
    local log, dropped = NS.CombatLog.Of(old)
    assertNil(log)
    assertEqual(dropped, 0)
    assertNil(old.log, "nothing written onto it")
    assertTrue(NS.Results.ShowFight("old"))
    local later = oldRecord(NS, "later", NS.Recorder.CT_SCHEMA + 1)
    later.log = { { t = 0, k = 9 } }
    NS.db.global.fights.later = later
    assertNil(NS.Recorder.Get("later"), "a later format is still left alone")
end)

test("combat log: a fight's log goes with it when retention purges the fight", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    local r = fightThrough(inst, meter, saved, 40, function(i) hit(i, 12, "WOUND", 10) end)
    assertTrue(NS.CombatLog.Of(r) ~= nil)
    r.t = os.time() - 30 * 86400
    NS.SetByPath("history.keepBests", false)
    NS.Retention.Purge()
    assertNil(NS.Recorder.Get(r.id))
    assertNil(NS.db.global.fights[r.id], "the record and its log are gone together")
end)

test("combat log: a fight lost or skipped keeps no log waiting", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    NS.SetByPath("history.minLength", 30)
    local short = { damage = 500, dps = 100, duration = 5, spells = FIGHT.spells, enemies = FIGHT.enemies }
    fightThrough(inst, meter, saved, 5, function(i) hit(i, 11, "WOUND", 10) end, short)
    assertEqual(#saved, 0, "too short to store")
    assertNil(NS.CombatLog.LiveStart(), "no capture left open")
    local r = fightThrough(inst, meter, saved, 40, function(i) hit(i, 102, "WOUND", 10) end, nil, 100, 2)
    assertEqual(kinds(NS, NS.CombatLog.Of(r)), "START,HIT,END", "the short fight's lines are not this one's")
end)

-- ── the stored size ─────────────────────────────────────────────────────────────────────────────

--- How many bytes a log at the cap takes in SavedVariables (docs/performance.md, *Stored size*): 400
--- lines, a busy fight's mix (casts, auras with IDs, hits with an amount, school and a mark).
local LOG_BYTES_CEILING = 38000

test("combat log: a log at the cap stays under its stored-size ceiling", function()
    local NS = T.load().NS
    local K, U = NS.CombatLog.KIND, NS.CombatLog.UNIT
    local log = {}
    for n = 1, NS.Constants.LOG.MAX_PER_FIGHT do
        local t = math.floor(n * 7.5) / 10 + 0.1
        local m = n % 4
        if m == 0 then log[n] = { t = t, k = K.CAST, id = 1234567, u = U.player }
        elseif m == 1 then log[n] = { t = t, k = K.DEBUFF_ON, id = 1234567, u = U.target }
        elseif m == 2 then log[n] = { t = t, k = K.HIT, u = U.player, a = 123456, s = 32, f = 1 }
        else log[n] = { t = t, k = K.BUFF_OFF, id = 1234567, u = U.player } end
    end
    local bytes = NS.Retention.SizeOf({ log = log, logDropped = 600 })
    assertTrue(bytes <= LOG_BYTES_CEILING, "a log at the cap takes " .. bytes .. " bytes")
    assertTrue(bytes > LOG_BYTES_CEILING * 0.8, "the ceiling sits close to the measure (" .. bytes .. ")")
end)
