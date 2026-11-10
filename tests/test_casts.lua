-- tests/test_casts.lua — modules/Casts.lua, a fight's cast list (plan Task 2.4, spec §5): the casts
-- come from the lanes' own capture (modules/LaneCasts.lua's listener, no second UNIT_SPELLCAST_*
-- registration), are timed from the fight's combat entry, keep a short pre-pull, never reach into
-- the fight before, end at the fight's own end, drop a sealed spell ID (counted, never a key), tag
-- the pet's, and leave the auto-repeat swings out. The lanes' display switches do not touch it.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local FIGHT = { damage = 9000, dps = 300, duration = 30, spells = { { id = 133, dmg = 9000, dps = 300 } } }
local SECOND = { damage = 4000, dps = 200, duration = 20, spells = { { id = 133, dmg = 4000, dps = 200 } } }

local function near(got, want, msg)
    assertTrue(type(got) == "number" and math.abs(got - want) < 1e-6,
        (msg or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got))
end

local function fresh()
    local meter
    local inst = T.load{ mutate = function(m) meter = T.mockMeter.install(m) end }
    -- The recorder (modules/Recorder.lua) takes each ended fight's list with Casts.Finish, which
    -- answers once: here the suite is the one that asks, so the recorder stands aside.
    inst.NS.Recorder.OnFightEnded = function() end
    local ended = {}
    local rx = inst.NS.NewBusTarget()
    rx:RegisterMessage(inst.NS.MSG.FIGHT_ENDED, function(_, fight, final, reason)
        ended[#ended + 1] = { fight = fight, final = final, reason = reason }
    end)
    return inst, meter, ended
end

local function at(inst, t) inst.mocks.__now = t end

local guid = 0
local function cast(inst, t, unit, id, event)
    at(inst, t)
    guid = guid + 1
    inst.mocks.__fire(event or "UNIT_SPELLCAST_SUCCEEDED", unit, "Cast-" .. guid, id)
end

local function enter(inst, t)
    at(inst, t)
    inst.mocks.InCombatLockdown = function() return true end
    inst.mocks.__fire("PLAYER_REGEN_DISABLED")
end

local function leave(inst, t)
    at(inst, t)
    inst.mocks.InCombatLockdown = function() return false end
    inst.mocks.__fire("PLAYER_REGEN_ENABLED")
end

local function settle(inst, t)
    at(inst, t)
    inst.mocks.__fireTimers()
end

local function ids(list)
    local out = {}
    for i, c in ipairs(list or {}) do out[i] = (c.unit == "pet" and "p" or "") .. tostring(c.spellID) end
    return table.concat(out, ",")
end

-- One whole fight from 100 to 130 on session 1, with what `during(inst)` casts in it.
local function oneFight(during)
    local inst, meter, ended = fresh()
    at(inst, 100)
    meter.SetSession(1, FIGHT)
    enter(inst, 100)
    if during then during(inst) end
    leave(inst, 130)
    settle(inst, 140)
    return inst, ended
end

-- ── the capture, end to end ─────────────────────────────────────────────────────────────────────

test("casts: a fight's casts come from the lanes' capture, timed from its combat entry", function()
    local inst, ended = oneFight(function(i)
        cast(i, 101.04, "player", 133)
        cast(i, 102.5, "player", 11366)
        cast(i, 120, "player", 133)
    end)
    assertEqual(#ended, 1)
    local casts, _, dropped = inst.NS.Casts.Finish(ended[1].fight.id)
    assertEqual(ids(casts), "133,11366,133")
    near(casts[1].t, 1.0, "seconds from the combat entry, to the tenth")
    near(casts[2].t, 2.5)
    near(casts[3].t, 20)
    assertEqual(casts[1].unit, "player")
    assertFalse(casts[1].interrupted)
    assertEqual(dropped, 0)
end)

test("casts: pet casts tagged unit=pet, and the pet's spells make PetSpellSet", function()
    local inst, ended = oneFight(function(i)
        cast(i, 101, "player", 133)
        cast(i, 102, "pet", 17253)
        cast(i, 103, "pet", 16827)
    end)
    local casts = inst.NS.Casts.Finish(ended[1].fight.id)
    assertEqual(ids(casts), "133,p17253,p16827")
    assertEqual(casts[2].unit, "pet")
    local set = inst.NS.Casts.PetSpellSet()
    assertTrue(set[17253] and set[16827], "the pet's spells")
    assertNil(set[133], "never the player's")
    set[999] = true
    assertNil(inst.NS.Casts.PetSpellSet()[999], "a copy: the caller cannot write the set")
end)

test("casts: secret spellID cast is dropped from the record, not stored as nil-key", function()
    local inst, ended = oneFight(function(i)
        cast(i, 101, "player", 133)
        cast(i, 102, "player", T.secret(11366))
        cast(i, 103, "pet", T.secret(17253))
        cast(i, 104, "player", 2948)
    end)
    local casts, _, dropped = inst.NS.Casts.Finish(ended[1].fight.id)
    assertEqual(ids(casts), "133,2948", "only the plain IDs")
    assertEqual(dropped, 2, "the sealed ones are counted")
    for _, c in ipairs(casts) do assertEqual(type(c.spellID), "number") end
    assertEqual(next(inst.NS.Casts.PetSpellSet()), nil, "a sealed pet spell is no key")
end)

test("casts: an interrupted cast is kept with interrupted=true; an instant that fails is not", function()
    local inst, ended = oneFight(function(i)
        at(i, 101)
        i.mocks.__fire("UNIT_SPELLCAST_START", "player", "Cast-A", 133)
        at(i, 102)
        i.mocks.__fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-A", 133)
        at(i, 103)
        i.mocks.__fire("UNIT_SPELLCAST_FAILED", "player", "Cast-B", 2948)
    end)
    local casts = inst.NS.Casts.Finish(ended[1].fight.id)
    assertEqual(ids(casts), "133")
    assertTrue(casts[1].interrupted)
    near(casts[1].t, 2)
end)

test("casts: the auto-repeat swings and shots are never kept", function()
    local inst, ended = oneFight(function(i)
        cast(i, 101, "player", 6603)
        cast(i, 102, "player", 75)
        cast(i, 103, "pet", 6603)
        cast(i, 104, "player", 133)
    end)
    assertEqual(ids(inst.NS.Casts.Finish(ended[1].fight.id)), "133")
end)

test("casts: the record hears a lane that is off and a spell a lane ignores", function()
    local inst, meter, ended = fresh()
    local NS = inst.NS
    NS.db.profile.lanes.pet.enabled = false
    NS.AnnounceSettingsChanged("lanes.pet.enabled", false)
    NS.db.profile.lanes.player.ignore[2948] = true
    meter.SetSession(1, FIGHT)
    enter(inst, 100)
    cast(inst, 101, "pet", 17253)
    cast(inst, 102, "player", 2948)
    leave(inst, 130)
    settle(inst, 140)
    assertEqual(ids(NS.Casts.Finish(ended[1].fight.id)), "p17253,2948")
end)

test("casts: no second UNIT_SPELLCAST_* registration; lanes off still hear both units for the record", function()
    local inst = fresh()
    local NS = inst.NS
    NS.db.profile.lanes.player.enabled = false
    NS.db.profile.lanes.pet.enabled = false
    NS.AnnounceSettingsChanged("profile")
    local frames, units = {}, {}
    for _, r in ipairs(inst.mocks.__registrations()) do
        if type(r.event) == "string" and r.event:find("^UNIT_SPELLCAST_") then
            frames[r.target] = true
            if r.event == "UNIT_SPELLCAST_SUCCEEDED" and r.unit then units[r.unit] = true end
        end
    end
    local n = 0
    for f in pairs(frames) do
        n = n + 1
        assertEqual(f, NS.LaneCasts.Frame(), "only the lanes' frame")
    end
    assertEqual(n, 1)
    assertTrue(units.player and units.pet, "both units, for the record")
end)

-- ── the window ──────────────────────────────────────────────────────────────────────────────────

test("casts: a pre-pull cast within PREPULL is kept at a negative time; an older one is not", function()
    local inst, meter, ended = fresh()
    meter.SetSession(1, FIGHT)
    assertEqual(inst.NS.Casts.PREPULL, 10)
    cast(inst, 80, "player", 1)
    cast(inst, 95, "player", 2)
    enter(inst, 100)
    cast(inst, 101, "player", 3)
    leave(inst, 130)
    settle(inst, 140)
    local casts = inst.NS.Casts.Finish(ended[1].fight.id)
    assertEqual(ids(casts), "2,3")
    near(casts[1].t, -5)
end)

test("casts: the next fight's pre-pull never reaches into the fight before it", function()
    local inst, meter, ended = fresh()
    meter.SetSession(1, FIGHT)
    enter(inst, 100)
    cast(inst, 101, "player", 1)
    cast(inst, 129, "player", 2)
    leave(inst, 130)
    cast(inst, 131, "player", 3)   -- after the first fight's combat: no fight's, until the next pre-pull
    settle(inst, 140)
    at(inst, 141)
    meter.SetSession(2, SECOND)
    enter(inst, 141)
    cast(inst, 142, "player", 4)
    leave(inst, 160)
    settle(inst, 170)
    assertEqual(#ended, 2)
    assertEqual(ids(inst.NS.Casts.Finish(ended[1].fight.id)), "1,2", "ends at its own combat end")
    local second = inst.NS.Casts.Finish(ended[2].fight.id)
    assertEqual(ids(second), "3,4", "the pre-pull starts at the first fight's end")
    near(second[1].t, -10)
end)

test("casts: a fight parked at a late re-entry ends at its combat end", function()
    local inst, meter, ended = fresh()
    meter.SetSession(1, FIGHT)
    enter(inst, 100)
    cast(inst, 101, "player", 1)
    cast(inst, 108, "player", 3)       -- within the next fight's PREPULL, but before this one's end
    leave(inst, 110)
    at(inst, 116)
    meter.SetSession(2, SECOND)
    enter(inst, 116)                   -- past GRACE: the first fight is parked
    cast(inst, 117, "player", 2)
    leave(inst, 130)
    settle(inst, 140)
    assertEqual(#ended, 2)
    assertEqual(ids(inst.NS.Casts.Finish(ended[1].fight.id)), "1,3")
    assertEqual(ids(inst.NS.Casts.Finish(ended[2].fight.id)), "2", "nothing of the parked fight's")
end)

test("casts: a lost fight's capture is dropped", function()
    local inst, meter, ended = fresh()
    meter.SetSession(1, FIGHT)
    enter(inst, 100)
    cast(inst, 101, "player", 1)
    inst.mocks.__fire("DAMAGE_METER_RESET")
    assertEqual(ended[1].reason, "lost")
    assertNil(inst.NS.Casts.Finish(ended[1].fight.id))
end)

test("casts: Live reads the fight in progress without ending it; Finish answers once", function()
    local inst, meter, ended = fresh()
    local Casts = inst.NS.Casts
    meter.SetSession(1, FIGHT)
    enter(inst, 100)
    cast(inst, 101, "player", 1)
    local id = inst.NS.Fight.Current().id
    assertEqual(ids(Casts.Live(id)), "1")
    cast(inst, 102, "player", 2)
    assertEqual(ids(Casts.Live(id)), "1,2")
    leave(inst, 130)
    settle(inst, 140)
    assertEqual(ids(Casts.Finish(ended[1].fight.id)), "1,2")
    assertNil(Casts.Finish(ended[1].fight.id), "taken")
end)

test("casts: Finish answers each spell's base cooldown, known ones only, asked once per spell", function()
    local inst, ended = oneFight(function(i)
        i.mocks.__baseCooldowns[12472] = 120000
        cast(i, 101, "player", 12472)
        cast(i, 102, "player", 133)
        cast(i, 103, "player", 133)
    end)
    local _, spells = inst.NS.Casts.Finish(ended[1].fight.id)
    assertEqual(spells[12472], 120000)
    assertNil(spells[133], "no cooldown, not stored")
    assertEqual(inst.mocks.__baseCooldownCalls[133] <= 2, true, "cached (the lane's glow may ask too)")
end)

test("casts: a secret base cooldown is not cached, so the spell's cooldown arrives once readable", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local secret = true
        local inst, meter = fresh()
        inst.mocks.GetSpellBaseCooldown = function()
            if secret then return T.secret(120000), 0 end
            return 120000, 0
        end
        meter.SetSession(1, FIGHT)
        enter(inst, 100)
        cast(inst, 101, "player", 19574)
        local id = inst.NS.Fight.Current().id
        local _, live = inst.NS.Casts.Live(id)
        assertNil(live[19574], "a secret answer is not a cooldown")
        secret = false
        local _, after = inst.NS.Casts.Live(id)
        assertEqual(after[19574], 120000, "the next read asks again and keeps the plain answer")
    end)
    restore()
    assertTrue(ok, tostring(err))
end)

test("casts: while idle the buffer holds only the pre-pull's worth", function()
    local inst = fresh()
    for i = 1, 200 do cast(inst, i, "player", 133) end
    assertTrue(inst.NS.Casts.__rawCount() <= 11, "held " .. inst.NS.Casts.__rawCount())
end)

test("casts: a stand-down drops every capture and the buffer", function()
    local inst, meter = fresh()
    local NS = inst.NS
    meter.SetSession(1, FIGHT)
    enter(inst, 100)
    cast(inst, 101, "player", 1)
    local id = NS.Fight.Current().id
    NS.SetByPath("general.enabled", false)
    assertEqual(NS.Casts.__rawCount(), 0)
    assertNil(NS.Casts.Finish(id))
    NS.SetByPath("general.enabled", true)
end)

-- ── the pure helpers ────────────────────────────────────────────────────────────────────────────

test("casts: IsLong is 29 s or more; Group orders long cooldowns first, then by count", function()
    local Casts = T.NS.Casts
    assertTrue(Casts.IsLong(29000))
    assertFalse(Casts.IsLong(28999))
    assertFalse(Casts.IsLong(nil))
    local list = {
        { t = 1, spellID = 133, unit = "player" }, { t = 2, spellID = 133, unit = "player" },
        { t = 3, spellID = 12472, unit = "player" }, { t = 4, spellID = 17253, unit = "pet" },
        { t = 0.5, spellID = 133, unit = "player" }, { t = 5, spellID = 190319, unit = "player" },
    }
    local groups = Casts.Group(list, { [12472] = 120000, [190319] = 60000 })
    assertEqual(groups[1].spellID, 12472, "the longest cooldown first")
    assertEqual(groups[2].spellID, 190319)
    assertEqual(groups[3].spellID, 133, "then by count")
    assertEqual(groups[3].count, 3)
    near(groups[3].times[1], 0.5, "times in order")
    assertEqual(groups[4].unit, "pet")
end)
