-- tests/test_combat_log.lua — modules/CombatLog.lua, the Combat Sequence's capture and store (CombatTrail
-- #11, plan item CL-11a; the Combat Sequence, CSEQ-1): the casts from the lanes' listener, UNIT_AURA's
-- gains and losses on the player and the debuffs the player put on the target, from the update info and
-- from the DIFF a full update or an update-less UNIT_AURA takes (its line order, an incomplete walk that
-- logs nothing, secrets never a key), the player's death; no UNIT_COMBAT, no HIT or HEAL, no target buff
-- (a saved one is retired at read); the in-memory ring and its bound; the saved `log` on the record
-- (oldest first, at most `log.store.lines`, the newest kept and the rest counted in `logDropped`, only
-- the categories saved, no amount or school); the events registered only while a fight is open; the
-- record schema's step to CT_SCHEMA 6 (an older fight reads with no log); and the stored size of a log
-- at the cap. Runs under both kit profiles: the capture is the same on Retail and WoW Forever.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertNil = T.test, T.assertEqual, T.assertTrue, T.assertNil

local FIGHT = { damage = 40000, dps = 1000, duration = 40,
                spells = { { id = 133, dmg = 30000, dps = 750 }, { id = 11366, dmg = 10000, dps = 250 } },
                enemies = { { name = "Angry Boar", creatureID = 1985, damage = 40000 } } }

local FIREBALL, PYROBLAST, BITE = 133, 11366, 17253
local INTELLECT, POLY, IGNITE, MARK = 1459, 118, 12654, 1126
local HASTE, CURSE = 2825, 980
local TARGET_A, TARGET_B = "Creature-0-1-1-1-100-0000000A", "Creature-0-1-1-1-200-0000000B"

-- A fresh instance on the scripted meter, the auras on each unit scripted by `m.__unitAuras`
-- ([unit][filter] = { aura, ... }; `m.__auraRaise` [unit .. filter] = an index whose read raises), a
-- target (TARGET_A, its GUID in `m.__unitGUIDs.target`), and a receiver for the saved fights.
local function fresh(o)
    o = o or {}
    local meter
    local inst = T.load{ mutate = function(m)
        meter = T.mockMeter.install(m)
        m.__unitAuras = { player = { HELPFUL = {}, HARMFUL = {} }, target = { HELPFUL = {}, HARMFUL = {} } }
        m.__auraReads = {}
        m.__auraRaise = {}
        m.__unitGUIDs.target = TARGET_A
        m.C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
            m.__auraReads[#m.__auraReads + 1] = unit .. ":" .. filter
            if m.__auraRaise[unit .. filter] == i then error("sealed read", 0) end
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

-- A cast of spell `id` handed in as the lanes' listener does (an ID past every auto attack's).
local function spellAt(inst, t, id)
    at(inst, t)
    inst.NS.CombatLog.OnCast("player", id, t, false)
end

-- The auras a walk reads for `unit`'s `filter`, set whole.
local function onUnit(inst, unit, filter, list)
    inst.mocks.__unitAuras[unit][filter] = list
end

local function buff(inst, id) return { auraInstanceID = inst, spellId = id, isHelpful = true } end
local function debuff(inst, id, mine)
    return { auraInstanceID = inst, spellId = id, isHarmful = true, isFromPlayerOrPlayerPet = mine == true }
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

-- Each line as KIND:id, for the order checks.
local function lines(NS, log)
    local name = {}
    for key, code in pairs(NS.CombatLog.KIND) do name[code] = key end
    local out = {}
    for i, e in ipairs(log or {}) do out[i] = name[e.k] .. ":" .. tostring(e.id) end
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

test("combat log: a fight's casts, auras and death are saved with its record: no hit, heal or boundary line", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    local U = NS.CombatLog.UNIT
    local r = fightThrough(inst, meter, saved, 40, function(i)
        cast(i, 12, "player", FIREBALL)
        cast(i, 13.04, "pet", BITE)
        aura(i, 14, "player", { addedAuras = { { auraInstanceID = 7, spellId = INTELLECT, isHelpful = true,
                                                 isHarmful = false } } })
        aura(i, 15, "target", { addedAuras = { { auraInstanceID = 8, spellId = IGNITE, isHarmful = true,
                                                 isFromPlayerOrPlayerPet = true } } })
        -- red under: UNIT_COMBAT still heard (the Combat Sequence drops the hits and heals taken)
        at(i, 16)
        i.mocks.__fire("UNIT_COMBAT", "player", "WOUND", "CRITICAL", 1200, 4)
        i.mocks.__fire("UNIT_COMBAT", "player", "HEAL", "", 800, 2)
        aura(i, 18, "target", { removedAuraInstanceIDs = { 8 } })
        aura(i, 19, "player", { removedAuraInstanceIDs = { 7 } })
        at(i, 20)
        i.mocks.__fire("PLAYER_DEAD")
    end)
    assertTrue(r ~= nil, "the fight was saved")
    assertEqual(r.schema, 6)
    local log, dropped = NS.CombatLog.Of(r)
    assertEqual(kinds(NS, log), "CAST,CAST,BUFF_ON,DEBUFF_ON,DEBUFF_OFF,BUFF_OFF,DIES")
    assertEqual(dropped, 0)
    assertNil(r.logDropped, "nothing dropped: no field")
    assertEqual(log[1].t, 2, "timed from the pull, still 0.0")
    assertEqual(log[1].id, FIREBALL)
    assertEqual(log[1].u, U.player)
    assertEqual(log[2].t, 3, "to the tenth")
    assertEqual(log[2].u, U.pet)
    assertEqual(log[3].id, INTELLECT)
    assertEqual(log[3].u, U.player)
    assertEqual(log[4].id, IGNITE)
    assertEqual(log[4].u, U.target)
    assertEqual(log[5].id, IGNITE, "a loss names the spell its instance was given for")
    assertNil(NS.CombatLog.OnCombat, "the hits-and-heals handler is gone")
    for n = NS.CombatLog.First(), NS.CombatLog.Seq() do
        assertTrue(not NS.CombatLog.IsRetired(NS.CombatLog.Line(n)), "no retired line in the ring either")
    end
    for _, e in ipairs(log) do
        assertNil(e.a, "no amount saved")
        assertNil(e.s, "no school saved")
        for key, v in pairs(e) do assertTrue(type(v) == "number", key .. " is a number") end
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
    assertEqual(kinds(NS, log), "CAST,CAST")
    assertEqual(log[1].t, -5)
    assertEqual(log[1].id, PYROBLAST)
    local autos = 0
    for n = NS.CombatLog.First(), NS.CombatLog.Seq() do
        local e = NS.CombatLog.Line(n)
        if e and e.id == 6603 then autos = autos + 1 end
    end
    assertEqual(autos, 1, "the ring holds the swing for a view")
end)

test("combat log: the target's lines are only the player's debuffs, and a target change logs nothing", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    local r = fightThrough(inst, meter, saved, 40, function(i)
        aura(i, 12, "target", { addedAuras = {
            { auraInstanceID = 21, spellId = 589, isHarmful = true, isFromPlayerOrPlayerPet = false },
            { auraInstanceID = 22, spellId = MARK, isHelpful = true, isHarmful = false },
            { auraInstanceID = 23, spellId = POLY, isHarmful = true, sourceUnit = "pet" } } })
        onUnit(i, "target", "HELPFUL", { buff(30, 21562) })
        onUnit(i, "target", "HARMFUL", { debuff(31, CURSE, true) })
        at(i, 13)
        i.mocks.__fire("PLAYER_TARGET_CHANGED")
        aura(i, 15, "target", { removedAuraInstanceIDs = { 30, 22, 31 } })
        aura(i, 16, "focus", { addedAuras = { { auraInstanceID = 40, spellId = 1, isHelpful = true } } })
    end)
    local log = NS.CombatLog.Of(r)
    -- red under: a target buff (MARK) and its loss as lines (the Combat Sequence keeps no target buff)
    assertEqual(lines(NS, log), "DEBUFF_ON:" .. POLY .. ",DEBUFF_OFF:" .. CURSE,
        "someone else's debuff, a target buff and the focus are no line; the new target's debuff ends with a loss")
end)

test("combat log: the target walk reads HARMFUL alone; the player's both", function()
    local inst, meter, saved = fresh()
    fightThrough(inst, meter, saved, 40, function(i)
        i.mocks.__auraReads = {}
        at(i, 13)
        i.mocks.__fire("PLAYER_TARGET_CHANGED")
        local reads = table.concat(i.mocks.__auraReads, ",")
        -- red under: a target:HELPFUL read
        assertEqual(reads, "target:HARMFUL", "one filter on the target")
        i.mocks.__auraReads = {}
        aura(i, 14, "player", nil)
        assertEqual(table.concat(i.mocks.__auraReads, ","), "player:HELPFUL,player:HARMFUL")
    end)
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
    assertEqual(kinds(NS, log), "BUFF_OFF", "an unknown instance is no line")
    assertEqual(log[1].id, INTELLECT)
end)

test("combat log: debuffs on you and your debuffs on your target are gained and lost", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    local U = NS.CombatLog.UNIT
    local r = fightThrough(inst, meter, saved, 40, function(i)
        aura(i, 12, "player", { addedAuras = { debuff(50, CURSE) } })
        aura(i, 13, "target", { addedAuras = { debuff(51, IGNITE, true) } })
        aura(i, 14, "player", { removedAuraInstanceIDs = { 50 } })
        aura(i, 15, "target", { removedAuraInstanceIDs = { 51 } })
    end)
    local log = NS.CombatLog.Of(r)
    assertEqual(kinds(NS, log), "DEBUFF_ON,DEBUFF_ON,DEBUFF_OFF,DEBUFF_OFF")
    assertEqual(log[3].u, U.player)
    assertEqual(log[3].id, CURSE)
    assertEqual(log[4].u, U.target)
    assertEqual(log[4].id, IGNITE)
end)

-- ── the diff: a full update, or no update info (WoW Forever) ────────────────────────────────────

test("combat log: a UNIT_AURA with no update info diffs the unit into gains and losses", function()
    local inst, meter, saved = fresh{ mutate = function(m)
        m.__unitAuras.player.HELPFUL = { { auraInstanceID = 3, spellId = INTELLECT, isHelpful = true } }
    end }
    local NS = inst.NS
    local r = fightThrough(inst, meter, saved, 40, function(i)
        onUnit(i, "player", "HELPFUL", { buff(3, INTELLECT), buff(4, HASTE) })
        aura(i, 12, "player", nil)
        onUnit(i, "player", "HELPFUL", { buff(4, HASTE) })
        aura(i, 13, "player", nil)
        onUnit(i, "player", "HELPFUL", {})
        aura(i, 14, "player", nil)
        aura(i, 15, "player", nil)
    end)
    -- red under: a walk with no line (the Combat Log's full update was silent)
    assertEqual(lines(NS, NS.CombatLog.Of(r)), "BUFF_ON:" .. HASTE .. ",BUFF_OFF:" .. INTELLECT .. ",BUFF_OFF:" .. HASTE,
        "the gain, then each loss; a walk that finds nothing new is no line")
end)

test("combat log: a full update diffs too, on the player and on the same target", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    local r = fightThrough(inst, meter, saved, 40, function(i)
        onUnit(i, "player", "HARMFUL", { debuff(60, CURSE) })
        aura(i, 12, "player", { isFullUpdate = true })
        onUnit(i, "target", "HARMFUL", { debuff(61, IGNITE, true), debuff(62, 589, false) })
        aura(i, 13, "target", { isFullUpdate = true })
        onUnit(i, "player", "HARMFUL", {})
        onUnit(i, "target", "HARMFUL", {})
        aura(i, 14, "player", { isFullUpdate = true })
        aura(i, 15, "target", { isFullUpdate = true })
    end)
    assertEqual(lines(NS, NS.CombatLog.Of(r)),
        "DEBUFF_ON:" .. CURSE .. ",DEBUFF_ON:" .. IGNITE .. ",DEBUFF_OFF:" .. CURSE .. ",DEBUFF_OFF:" .. IGNITE,
        "someone else's debuff on the target is never a line")
end)

test("combat log: the diff's order is fixed: gains in walk order, then losses by instance", function()
    local inst, meter, saved = fresh{ mutate = function(m)
        m.__unitAuras.player.HELPFUL = { { auraInstanceID = 9, spellId = 9001, isHelpful = true },
                                         { auraInstanceID = 2, spellId = 9002, isHelpful = true },
                                         { auraInstanceID = 5, spellId = 9003, isHelpful = true } }
    end }
    local NS = inst.NS
    local r = fightThrough(inst, meter, saved, 40, function(i)
        onUnit(i, "player", "HELPFUL", { buff(30, 9030), buff(10, 9010) })
        onUnit(i, "player", "HARMFUL", { debuff(20, 9020) })
        aura(i, 12, "player", { isFullUpdate = true })
    end)
    assertEqual(lines(NS, NS.CombatLog.Of(r)),
        "BUFF_ON:9030,BUFF_ON:9010,DEBUFF_ON:9020,BUFF_OFF:9002,BUFF_OFF:9003,BUFF_OFF:9001")
end)

test("combat log: a refresh (updatedAuraInstanceIDs) is no line", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    local r = fightThrough(inst, meter, saved, 40, function(i)
        aura(i, 12, "player", { addedAuras = { buff(7, INTELLECT) } })
        aura(i, 13, "player", { updatedAuraInstanceIDs = { 7 } })
    end)
    assertEqual(kinds(NS, NS.CombatLog.Of(r)), "BUFF_ON")
end)

-- An incomplete walk: what stops it, then (unless `alone`) a complete one with the same auras. Neither
-- draws a line.
local function incomplete(stop, alone)
    local inst, meter, saved = fresh{ mutate = function(m)
        m.__unitAuras.player.HELPFUL = { { auraInstanceID = 1, spellId = INTELLECT, isHelpful = true },
                                         { auraInstanceID = 2, spellId = HASTE, isHelpful = true } }
    end }
    local r = fightThrough(inst, meter, saved, 40, function(i)
        stop(i)
        aura(i, 12, "player", nil)
        if alone then return end
        i.mocks.__auraRaise = {}
        onUnit(i, "player", "HELPFUL", { buff(1, INTELLECT), buff(2, HASTE) })
        aura(i, 13, "player", nil)
    end)
    return inst.NS, r
end

test("combat log: an incomplete walk writes no line and leaves no false loss or gain after it", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        -- A sealed aura mid-list: skipped, HASTE after it still read; the walk is incomplete.
        local NS, r = incomplete(function(i)
            onUnit(i, "player", "HELPFUL", { buff(1, INTELLECT), T.secret({}), buff(2, HASTE) })
        end)
        -- red under: BUFF_OFF HASTE (a false loss), then BUFF_ON HASTE (a false gain)
        assertEqual(kinds(NS, NS.CombatLog.Of(r)), "", "a sealed aura: no line, now or after")
        -- A sealed instance on an accessible aura.
        NS, r = incomplete(function(i)
            onUnit(i, "player", "HELPFUL", { buff(1, INTELLECT), { auraInstanceID = T.secret(2), spellId = HASTE } })
        end)
        assertEqual(kinds(NS, NS.CombatLog.Of(r)), "", "a sealed instance")
        -- A sealed spell ID.
        NS, r = incomplete(function(i)
            onUnit(i, "player", "HELPFUL", { buff(1, INTELLECT), { auraInstanceID = 2, spellId = T.secret(HASTE) } })
        end)
        assertEqual(kinds(NS, NS.CombatLog.Of(r)), "", "a sealed spell ID")
    end)
    restore()
    if not ok then error(err, 0) end
    -- A read that raises (WoW Forever's sealed read).
    local NS, r = incomplete(function(i)
        i.mocks.__auraRaise = { playerHELPFUL = 2 }
    end)
    assertEqual(kinds(NS, NS.CombatLog.Of(r)), "", "a raising read")
    -- AURA_LIMIT reached: the walk never saw the list's end, so the 40 new auras (and the two it no
    -- longer reached) are no line.
    NS, r = incomplete(function(i)
        local many = {}
        for n = 1, i.NS.CombatLog.AURA_LIMIT do many[n] = buff(100 + n, 5000 + n) end
        onUnit(i, "player", "HELPFUL", many)
    end, true)
    assertEqual(kinds(NS, NS.CombatLog.Of(r)), "", "AURA_LIMIT reached: no gain and no loss logged")
end)

test("combat log: a sealed aura at the pull leaves the auras after it mapped (a fade logged, no false gain)", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local function pulled()
            return fresh{ mutate = function(m)
                m.__unitAuras.player.HELPFUL = { T.secret({}), { auraInstanceID = 2, spellId = HASTE, isHelpful = true } }
                m.__unitAuras.target.HARMFUL = {
                    { auraInstanceID = T.secret(80), spellId = 589, isHarmful = true, isFromPlayerOrPlayerPet = false },
                    { auraInstanceID = 81, spellId = IGNITE, isHarmful = true, isFromPlayerOrPlayerPet = true } }
            end }
        end
        -- (a) the buff after the sealed aura fades through removedAuraInstanceIDs: logged.
        local inst, meter, saved = pulled()
        local NS = inst.NS
        local r = fightThrough(inst, meter, saved, 40, function(i)
            aura(i, 12, "player", { removedAuraInstanceIDs = { 2 } })
        end)
        -- red under: "" (the walk stopped at the sealed aura, HASTE unmapped)
        assertEqual(lines(NS, NS.CombatLog.Of(r)), "BUFF_OFF:" .. HASTE, "the fade of a buff after a sealed one")
        -- (b) the sealed aura gone, a complete diff finds nothing new; someone else's sealed debuff on
        -- the target never made the target walk incomplete, so the DoT's fade there is a diff's loss.
        inst, meter, saved = pulled()
        NS = inst.NS
        r = fightThrough(inst, meter, saved, 40, function(i)
            onUnit(i, "player", "HELPFUL", { buff(2, HASTE) })
            aura(i, 12, "player", nil)
            onUnit(i, "target", "HARMFUL", {})
            aura(i, 13, "target", { isFullUpdate = true })
        end)
        -- red under: BUFF_ON HASTE (a false gain mid-fight)
        assertEqual(lines(NS, NS.CombatLog.Of(r)), "DEBUFF_OFF:" .. IGNITE, "no false gain; the DoT's fade logged")
    end)
    restore()
    if not ok then error(err, 0) end
end)

test("combat log: a full update for a new target before PLAYER_TARGET_CHANGED is silent", function()
    local inst, meter, saved = fresh{ mutate = function(m)
        m.__unitAuras.target.HARMFUL = { { auraInstanceID = 70, spellId = IGNITE, isHarmful = true, isFromPlayerOrPlayerPet = true } }
    end }
    local NS = inst.NS
    local r = fightThrough(inst, meter, saved, 40, function(i)
        i.mocks.__unitGUIDs.target = TARGET_B
        onUnit(i, "target", "HARMFUL", { debuff(71, CURSE, true) })
        aura(i, 12, "target", { isFullUpdate = true })
        at(i, 13)
        i.mocks.__fire("PLAYER_TARGET_CHANGED")
        -- The map is the new target's now: its DoT's fade is a diff's loss.
        onUnit(i, "target", "HARMFUL", {})
        aura(i, 14, "target", { isFullUpdate = true })
    end)
    -- red under: DEBUFF_ON CURSE, DEBUFF_OFF IGNITE (a burst across the change), then DEBUFF_OFF CURSE
    assertEqual(lines(NS, NS.CombatLog.Of(r)), "DEBUFF_OFF:" .. CURSE, "no burst across the change")
end)

test("combat log: a target whose GUID cannot be read plain is never diffed", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local inst, meter, saved = fresh{ mutate = function(m)
            m.__unitGUIDs.target = T.secret(TARGET_A)
            m.__unitAuras.target.HARMFUL = { { auraInstanceID = 70, spellId = IGNITE, isHarmful = true, isFromPlayerOrPlayerPet = true } }
        end }
        local NS = inst.NS
        local r = fightThrough(inst, meter, saved, 40, function(i)
            onUnit(i, "target", "HARMFUL", { debuff(71, CURSE, true) })
            aura(i, 12, "target", { isFullUpdate = true })
            aura(i, 13, "target", { removedAuraInstanceIDs = { 71 } })
        end)
        assertEqual(lines(NS, NS.CombatLog.Of(r)), "DEBUFF_OFF:" .. CURSE,
            "the full update walked silently; the update info's loss still logged")
    end)
    restore()
    if not ok then error(err, 0) end
end)

test("combat log: a target change is silent, and a new target is no burst of gains", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    local r = fightThrough(inst, meter, saved, 40, function(i)
        onUnit(i, "target", "HARMFUL", { debuff(70, IGNITE, true), debuff(71, CURSE, true) })
        at(i, 12)
        i.mocks.__fire("PLAYER_TARGET_CHANGED")
        aura(i, 13, "target", { isFullUpdate = true })
    end)
    assertEqual(kinds(NS, NS.CombatLog.Of(r)), "", "walked at the change; the full update after finds nothing new")
end)

-- ── secrets ─────────────────────────────────────────────────────────────────────────────────────

test("combat log: a sealed aura and a sealed cast are no line; a sealed instance is never a key", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local inst, meter, saved = fresh()
        local NS = inst.NS
        local r = fightThrough(inst, meter, saved, 40, function(i)
            aura(i, 12, "player", { addedAuras = { { auraInstanceID = 5, spellId = T.secret(INTELLECT), isHelpful = true },
                                                   { auraInstanceID = T.secret(6), spellId = MARK, isHelpful = true } } })
            aura(i, 13, "player", T.secret({}))
            aura(i, 14, "player", { isFullUpdate = T.secret(true) })
            aura(i, 15, "player", { removedAuraInstanceIDs = { T.secret(5) } })
            cast(i, 16, "player", T.secret(FIREBALL))
            cast(i, 17, "player", FIREBALL)
        end)
        local log = NS.CombatLog.Of(r)
        assertEqual(kinds(NS, log), "CAST", "only the plain cast")
        for n = NS.CombatLog.First(), NS.CombatLog.Seq() do
            local e = NS.CombatLog.Line(n)
            for key, v in pairs(e or {}) do assertTrue(not T.isSecret(v), "no secret in the ring's " .. key) end
        end
    end)
    restore()
    if not ok then error(err, 0) end
end)

-- R5-CT-03 (owner feedback round 5): on WoW Forever the owner's real fights show only CAST rows. The
-- saved fights say UNIT_AURA arrives (a death's fades are logged) and the auras at the pull are read,
-- but no gain or debuff in combat ever lands. Which read drops them cannot be told offline, so the
-- capture counts every aura it hears and why each one drew no line, for `/ct diagnostics` after a fight.
test("combat log: the aura tally counts what UNIT_AURA brought and why each aura drew no line", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local inst = fresh()
        local CL = inst.NS.CombatLog
        onUnit(inst, "player", "HELPFUL", { buff(1, MARK) })
        at(inst, 10)
        CL.Begin("tally", 10)
        assertEqual(CL.Diagnose().auras.walkComplete, 2, "the pull's walks: the player and the target")
        aura(inst, 11, "player", { addedAuras = {
            buff(5, INTELLECT),
            { auraInstanceID = 6, spellId = T.secret(HASTE), isHelpful = true },
            { auraInstanceID = T.secret(7), spellId = HASTE, isHelpful = true },
            T.secret({}),
        } })
        aura(inst, 12, "target", { addedAuras = {
            { auraInstanceID = 20, spellId = IGNITE, isHarmful = true, isFromPlayerOrPlayerPet = T.secret(true) },
            debuff(21, CURSE, false),
            { auraInstanceID = 22, spellId = MARK, isHelpful = true },
        } })
        aura(inst, 13, "player", { removedAuraInstanceIDs = { 5, 99, T.secret(6) } })
        aura(inst, 14, "player", nil)
        aura(inst, 15, "player", { isFullUpdate = true })
        inst.mocks.__auraRaise.playerHELPFUL = 1
        aura(inst, 16, "player", T.secret({}))
        local a = CL.Diagnose().auras
        assertEqual(a.evPlayer, 5, "UNIT_AURA on the player")
        assertEqual(a.evTarget, 1)
        assertEqual(a.info, 3, "with usable update info")
        assertEqual(a.none, 1, "with none")
        assertEqual(a.full, 1, "a full update")
        assertEqual(a.sealedInfo, 1, "sealed info")
        assertEqual(a.gainSeen, 7, "every added aura read")
        assertEqual(a.gainLined, 1, "the one plain buff")
        assertEqual(a.gainSealedSpell, 1)
        assertEqual(a.gainSealedInstance, 1)
        assertEqual(a.gainSealedTable, 1)
        assertEqual(a.gainSealedSource, 1, "a target debuff whose source cannot be read")
        assertEqual(a.gainNotYours, 1, "a target debuff someone else put on")
        assertEqual(a.gainTargetBuff, 1)
        assertEqual(a.lossSeen, 3)
        assertEqual(a.lossLined, 1)
        assertEqual(a.lossUnknown, 1, "an instance never mapped")
        assertEqual(a.lossSealed, 1)
        assertEqual(a.walkComplete, 4, "the two diffs walked whole")
        assertEqual(a.walkIncomplete, 1, "the diff whose read raised")
        assertEqual(a.walkRaised, 1)
        CL.Drop("tally")
        CL.Begin("next", 30)
        assertEqual(CL.Diagnose().auras.gainSeen, 0, "a new capture's registration starts the tally over")
    end)
    restore()
    if not ok then error(err, 0) end
end)

-- ── the retired lines ───────────────────────────────────────────────────────────────────────────

test("combat log: HIT, HEAL, START, END and a target BUFF are retired: no category, never saved or shown", function()
    local NS = T.load().NS
    local CL = NS.CombatLog
    local K, U = CL.KIND, CL.UNIT
    -- The numbers never move: saved logs carry them.
    assertEqual(K.CAST .. K.BUFF_ON .. K.BUFF_OFF .. K.DEBUFF_ON .. K.DEBUFF_OFF .. K.DIES, "123458")
    assertEqual(K.HIT .. "," .. K.HEAL .. "," .. K.START .. "," .. K.END, "6,7,9,10")
    assertNil(CL.IsBoundary, "renamed IsRetired")
    for _, e in ipairs({ { k = K.HIT, u = U.player }, { k = K.HEAL, u = U.player }, { k = K.START }, { k = K.END },
                         { k = K.BUFF_ON, u = U.target }, { k = K.BUFF_OFF, u = U.target } }) do
        assertTrue(CL.IsRetired(e), "kind " .. e.k)
        assertNil(CL.CategoryOf(e.k, e.u, e.id), "no category for kind " .. e.k)
    end
    for _, e in ipairs({ { k = K.CAST, u = U.player, id = FIREBALL }, { k = K.BUFF_ON, u = U.player },
                         { k = K.DEBUFF_OFF, u = U.target }, { k = K.DIES, u = U.player } }) do
        assertTrue(not CL.IsRetired(e), "kind " .. e.k .. " is live")
    end
    assertEqual(table.concat(CL.CATEGORIES, ","), "casts,petCasts,playerBuffs,playerDebuffs,targetDebuffs,deaths")
    assertNil(CL.SEALED, "no sealed amount mark")
    assertNil(CL.FLAG.CRIT, "the hits' marks are gone")
    assertEqual(CL.FLAG.INTERRUPTED, 8, "at its bit")
end)

-- ── the cap and the categories ──────────────────────────────────────────────────────────────────

test("combat log: past `log.store.lines` only the newest are kept and the record counts the rest", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    NS.db.profile.sequence.store.lines = 100
    local r = fightThrough(inst, meter, saved, 40, function(i)
        for n = 1, 250 do spellAt(i, 11 + n * 0.1, 100000 + n) end
    end)
    local log, dropped = NS.CombatLog.Of(r)
    assertEqual(#log, 100)
    assertEqual(log[#log].id, 100250, "the newest kept")
    assertEqual(log[1].id, 100151, "casts 151 to 250")
    assertEqual(dropped, 150)
    assertEqual(r.logDropped, 150)
end)

test("combat log: heavy unsaved traffic never costs the saved log its lines (each capture keeps its own)", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    local C = NS.Constants.LOG
    NS.db.profile.sequence.store.lines = C.MAX_LINES
    for _, key in ipairs(NS.CombatLog.CATEGORIES) do NS.db.profile.sequence.store.categories[key] = key == "casts" end
    local r = fightThrough(inst, meter, saved, 40, function(i)
        for n = 1, 1500 do
            local t = 11 + n * 0.01
            at(i, t)
            NS.CombatLog.OnCast("player", FIREBALL, t, false)
            NS.CombatLog.OnCast("player", 75, t, false)      -- Auto Shot: in the ring, never saved
            NS.CombatLog.OnCast("player", 75, t, false)
            NS.CombatLog.OnCast("pet", BITE, t, false)       -- pet casts: in the ring, not saved here
            NS.CombatLog.OnCast("pet", BITE, t, false)
        end
    end)
    assertTrue(NS.CombatLog.Seq() > 3 * C.RING, "the ring wrapped several times over")
    local log, dropped = NS.CombatLog.Of(r)
    assertEqual(#log, C.MAX_LINES, "the log reaches `lines` however much else the ring held")
    assertEqual(log[#log].k, NS.CombatLog.KIND.CAST, "the newest kept")
    for i = 1, #log do
        if log[i].k ~= NS.CombatLog.KIND.CAST or log[i].id ~= FIREBALL then
            error("line " .. i .. " is not a saved cast", 0)
        end
    end
    assertEqual(dropped, 1500 - C.MAX_LINES, "only the casts the cap left out are counted")
end)

test("combat log: the default keeps C.LOG.MAX_PER_FIGHT lines, and a setting is held to its range", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    local C = NS.Constants.LOG
    assertEqual(C.MAX_PER_FIGHT, 400)
    assertEqual(NS.GetSetting("sequence.store.lines"), 400)
    NS.db.profile.sequence.store.lines = 5
    local r = fightThrough(inst, meter, saved, 40, function(i)
        for n = 1, 150 do spellAt(i, 11 + n * 0.1, 100000 + n) end
    end)
    assertEqual(#NS.CombatLog.Of(r), C.MIN_PER_FIGHT, "a stored 5 reads as the least, 100")
end)

test("combat log: a category not saved is no line and not counted as dropped", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    NS.db.profile.sequence.store.categories.playerBuffs = false
    NS.db.profile.sequence.store.categories.petCasts = false
    local r = fightThrough(inst, meter, saved, 40, function(i)
        aura(i, 12, "player", { addedAuras = { buff(7, INTELLECT) } })
        aura(i, 13, "player", { addedAuras = { debuff(8, CURSE) } })
        cast(i, 14, "pet", BITE)
        cast(i, 15, "player", FIREBALL)
    end)
    local log, dropped = NS.CombatLog.Of(r)
    assertEqual(kinds(NS, log), "DEBUFF_ON,CAST")
    assertEqual(dropped, 0)
end)

test("combat log: saving off keeps no log on the record; the log off registers nothing", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    NS.db.profile.sequence.store.enabled = false
    local r = fightThrough(inst, meter, saved, 40, function(i) cast(i, 12, "player", FIREBALL) end)
    assertNil(r.log)
    assertNil(NS.CombatLog.Of(r))
    NS.db.profile.sequence.enabled = false
    local before = NS.CombatLog.Seq()
    local r2 = fightThrough(inst, meter, saved, 40, function(i)
        assertEqual(next(unitRegs(i)), nil, "no registration in the fight")
        aura(i, 12, "player", { addedAuras = { buff(7, INTELLECT) } })
    end)
    assertTrue(r2 ~= r, "the second fight was saved")
    assertNil(r2.log)
    assertEqual(NS.CombatLog.Seq(), before, "no line was captured")
end)

test("combat log: the settings are frozen at the fight's start", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    local r = fightThrough(inst, meter, saved, 40, function(i)
        NS.db.profile.sequence.store.categories.playerBuffs = false
        aura(i, 12, "player", { addedAuras = { buff(7, INTELLECT) } })
    end)
    assertEqual(kinds(NS, NS.CombatLog.Of(r)), "BUFF_ON")
end)

test("combat log: the storage keys have their shipped defaults", function()
    local NS = T.load().NS
    assertTrue(NS.GetSetting("sequence.enabled"))
    assertTrue(NS.GetSetting("sequence.store.enabled"))
    for _, key in ipairs(NS.CombatLog.CATEGORIES) do
        assertEqual(NS.defaults.profile.sequence.store.categories[key], true, key .. " saved by default")
    end
    local n = 0
    for _ in pairs(NS.defaults.profile.sequence.store.categories) do n = n + 1 end
    assertEqual(n, #NS.CombatLog.CATEGORIES, "one key per category")
end)

-- ── registration ────────────────────────────────────────────────────────────────────────────────

test("combat log: its events are registered only while a fight is open: UNIT_AURA, PLAYER_DEAD, the target change", function()
    local inst, meter, saved = fresh()
    local NS = inst.NS
    assertNil(NS.CombatLog.EventFrame(), "idle: no frame yet")
    local inFight
    fightThrough(inst, meter, saved, 40, function(i) inFight = unitRegs(i) end)
    local names = {}
    for event in pairs(inFight) do if event ~= "units" then names[#names + 1] = event end end
    table.sort(names)
    -- red under: UNIT_COMBAT registered (the hits and heals taken, retired by the Combat Sequence)
    assertEqual(table.concat(names, ","), "PLAYER_DEAD,PLAYER_TARGET_CHANGED,UNIT_AURA")
    assertTrue(inFight.units.UNIT_AURA.player and inFight.units.UNIT_AURA.target, "UNIT_AURA for player and target")
    assertEqual(next(unitRegs(inst)), nil, "the fight ended: nothing registered")
    for _, r in ipairs(inst.mocks.__registrations()) do
        assertTrue(r.event ~= "COMBAT_LOG_EVENT_UNFILTERED", "never the combat log")
        assertTrue(r.target ~= NS.CombatLog.EventFrame() or r.event ~= "UNIT_COMBAT", "never UNIT_COMBAT")
    end
end)

test("combat log: a stand-down mid-fight drops every registration and line", function()
    local inst, meter = fresh()
    local NS = inst.NS
    at(inst, 10)
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    aura(inst, 11, "player", { addedAuras = { buff(7, INTELLECT) } })
    assertTrue(next(unitRegs(inst)) ~= nil)
    NS.SetByPath("general.enabled", false)
    assertEqual(next(unitRegs(inst)), nil)
    assertEqual(NS.CombatLog.Seq(), 0)
    assertEqual(NS.CombatLog.__ringCount(), 0)
    NS.SetByPath("general.enabled", true)
    assertEqual(next(unitRegs(inst)), nil, "the stand-up opens no fight")
end)

test("combat log: a client that refuses PLAYER_DEAD costs only it, and the diagnosis names it", function()
    local inst, meter, saved = fresh{ mutate = function(m) m.__badEvents = { PLAYER_DEAD = true } end }
    local NS = inst.NS
    local regs
    local r = fightThrough(inst, meter, saved, 40, function(i)
        regs = unitRegs(i)
        aura(i, 12, "player", { addedAuras = { { auraInstanceID = 1, spellId = INTELLECT, isHelpful = true } } })
    end)
    assertNil(regs.PLAYER_DEAD)
    assertTrue(regs.UNIT_AURA ~= nil)
    assertEqual(table.concat(NS.CombatLog.Diagnose().refused, ","), "PLAYER_DEAD")
    assertEqual(kinds(NS, NS.CombatLog.Of(r)), "BUFF_ON")
end)

test("combat log: the combatLog perf bucket is reached by its events, the diff too", function()
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
        aura(i, 12, "player", { addedAuras = { buff(7, INTELLECT) } })
        aura(i, 13, "player", nil)
        NS.Perf.on = false
    end)
    NS.Perf.Note = note
    assertEqual(noted, 2)
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
    local r = fightThrough(inst, meter, saved, 40, function(i) cast(i, 12, "player", FIREBALL) end)
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
    fightThrough(inst, meter, saved, 5, function(i) cast(i, 11, "player", PYROBLAST) end, short)
    assertEqual(#saved, 0, "too short to store")
    assertNil(NS.CombatLog.LiveStart(), "no capture left open")
    local r = fightThrough(inst, meter, saved, 40, function(i) cast(i, 102, "player", FIREBALL) end, nil, 100, 2)
    assertEqual(lines(NS, NS.CombatLog.Of(r)), "CAST:" .. FIREBALL, "the short fight's lines are not this one's")
end)

-- ── which target ────────────────────────────────────────────────────────────────────────────────

test("combat log: a target swap mid-fight keeps the earlier rows' target, live and saved", function()
    local inst, meter, saved = fresh{ mutate = function(m)
        m.__unitExists.target = true
        m.__unitNames.target = "Angry Boar"
        m.__hostile = true
        m.UnitCanAttack = function() return m.__hostile end
    end }
    local NS = inst.NS
    local K = NS.CombatLog.KIND
    local LT = NS.LogTable
    local r = fightThrough(inst, meter, saved, 40, function(i)
        aura(i, 12, "target", { addedAuras = { { auraInstanceID = 8, spellId = IGNITE, isHarmful = true,
                                                 isFromPlayerOrPlayerPet = true } } })
        at(i, 14)
        i.mocks.__unitNames.target = "Stormwind Guard"
        i.mocks.__hostile = false
        i.mocks.__fire("PLAYER_TARGET_CHANGED")
        aura(i, 15, "target", { addedAuras = { { auraInstanceID = 9, spellId = CURSE, isHarmful = true,
                                                 isFromPlayerOrPlayerPet = true } } })
        at(i, 16)
        i.mocks.__unitNames.target = "Angry Boar"
        i.mocks.__hostile = true
        i.mocks.__fire("PLAYER_TARGET_CHANGED")
        aura(i, 17, "target", { addedAuras = { { auraInstanceID = 10, spellId = POLY, isHarmful = true,
                                                 isFromPlayerOrPlayerPet = true } } })
    end)
    -- The data keeps each line's own target (its `g`), though no column draws it now (item 3).
    local function who(list, g)
        local t = list[g]
        return t.name .. (t.friendly and "/friendly" or "/hostile")
    end
    local live = {}
    for n = NS.CombatLog.First(), NS.CombatLog.Seq() do
        local e = NS.CombatLog.Line(n)
        if e and e.k == K.DEBUFF_ON and e.u == NS.CombatLog.UNIT.target then
            live[#live + 1] = who(NS.CombatLog.Targets(), e.g)
        end
    end
    assertEqual(table.concat(live, ","), "Angry Boar/hostile,Stormwind Guard/friendly,Angry Boar/hostile")
    -- Saved: the record's own target list, each name once per reaction.
    local log, _, targets = NS.CombatLog.Of(r)
    assertEqual(#targets, 2, "Angry Boar once, Stormwind Guard once")
    assertEqual(r.logTargets, targets)
    local got = {}
    for _, e in ipairs(log) do
        if e.u == NS.CombatLog.UNIT.target then got[#got + 1] = who(targets, e.g) end
    end
    assertEqual(table.concat(got, ","), "Angry Boar/hostile,Stormwind Guard/friendly,Angry Boar/hostile")
    -- And no cell names a source or a target.
    local c = LT.Cells(log[1], NS.ResultsLog.Context(r, {}), {})
    assertNil(c.source)
    assertNil(c.target)
end)

-- ── the stored size ─────────────────────────────────────────────────────────────────────────────

--- How many bytes a log at the cap takes in SavedVariables (docs/performance.md, *Stored size*): 400
--- lines, a busy fight's mix (casts, an interrupted one with its mark, auras with IDs on you and the
--- target). No line carries an amount or a school now (the Combat Sequence).
local LOG_BYTES_CEILING = 39500

test("combat log: a log at the cap stays under its stored-size ceiling", function()
    local NS = T.load().NS
    local K, U = NS.CombatLog.KIND, NS.CombatLog.UNIT
    local log = {}
    for n = 1, NS.Constants.LOG.MAX_PER_FIGHT do
        local t = math.floor(n * 7.5) / 10 + 0.1
        local m = n % 4
        if m == 0 then log[n] = { t = t, k = K.CAST, id = 1234567, u = U.player }
        elseif m == 1 then log[n] = { t = t, k = K.DEBUFF_ON, id = 1234567, u = U.target, g = 1 }
        elseif m == 2 then log[n] = { t = t, k = K.CAST, id = 1234567, u = U.player, f = 8 }
        else log[n] = { t = t, k = K.BUFF_OFF, id = 1234567, u = U.player } end
    end
    local bytes = NS.Retention.SizeOf({ log = log, logDropped = 600, logTargets = { { name = "Training Dummy" } } })
    assertTrue(bytes <= LOG_BYTES_CEILING, "a log at the cap takes " .. bytes .. " bytes")
    assertTrue(bytes > LOG_BYTES_CEILING * 0.8, "the ceiling sits close to the measure (" .. bytes .. ")")
end)
