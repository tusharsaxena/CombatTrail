-- tests/test_meter.lua — modules/Meter.lua against the scripted C_DamageMeter (tests/mock_meter.lua),
-- plan Task 2.1: availability, the session list and SessionAfter, the live read of the player's and
-- the pet's sources (opaque, Blizzard's order, the live-DPS rungs), the after-combat read that merges
-- player and pet in plain Lua and refuses while anything is secret, the PET_SEPARATE seam, the enemy
-- view, and the adapter being the only file that names C_DamageMeter.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local PLAYER, PET = "Player-1-00000001", "Pet-0-1-2-3-4"

local function fresh(extra)
    local meter
    local inst = T.load{ mutate = function(m)
        meter = T.mockMeter.install(m)
        if extra then extra(m) end
    end }
    return inst.NS, meter, inst
end

-- A fresh instance with a summoned pet whose GUID the meter answers for.
local function withPet()
    local NS, meter, inst = fresh(function(m) m.__unitExists.pet = true end)
    meter.SetPetGUID(PET)
    return NS, meter, inst
end

-- The player's spells deliberately NOT in damage order; the pet's own source beside them.
local FIGHT = {
    damage = 9000, dps = 300, duration = 30,
    spells = {
        { id = 133, dmg = 3000, dps = 100 },
        { id = 11366, dmg = 6000, dps = 200 },
    },
    pet = { damage = 3000, dps = 100, spells = {
        { id = 17253, dmg = 1000, dps = 33 },
        { id = 16827, dmg = 2000, dps = 67 },
    } },
    others = { { guid = "Player-1-00000002", damage = 50000, dps = 1666 } },
    enemies = {
        { name = "Patchwerk", creatureID = 16028, damage = 8000 },
        { name = "Hateful Strike Dummy", creatureID = 31146, damage = 12000 },
        { name = "Grobbulus", creatureID = 15931, damage = 2000 },
    },
}

local function copy(t, over)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    for k, v in pairs(over or {}) do out[k] = v end
    return out
end

-- ── constants and availability ─────────────────────────────────────────────────────────────────

test("meter: the stat and session constants come from the client enum", function()
    local NS = fresh()
    assertEqual(NS.Meter.STAT_DAMAGE_DONE, 0)
    assertEqual(NS.Meter.STAT_DPS, 1)
    assertEqual(NS.Meter.STAT_ENEMY_DAMAGE_TAKEN, 10)
    assertEqual(NS.Meter.SESSION_CURRENT, 1)
end)

test("meter: without the enum, the documented values stand and the enemy view is unread", function()
    local inst = T.load{ mutate = function(m) m.Enum = nil end }
    assertEqual(inst.NS.Meter.STAT_DAMAGE_DONE, 0)
    assertEqual(inst.NS.Meter.SESSION_CURRENT, 1)
    assertNil(inst.NS.Meter.STAT_ENEMY_DAMAGE_TAKEN, "no guessed literal for an enum the client did not ship")
end)

test("meter: PET_SEPARATE is the spec §12 seam, true out of the box", function()
    local NS = fresh()
    assertTrue(NS.Meter.PET_SEPARATE == true)
end)

test("meter: IsAvailable passes Blizzard's reason through, and answers on a client without the API", function()
    local NS, meter = fresh()
    local ok, reason = NS.Meter.IsAvailable()
    assertTrue(ok)
    assertNil(reason)
    meter.SetAvailable(false, "The damage meter is disabled.")
    ok, reason = NS.Meter.IsAvailable()
    assertFalse(ok)
    assertEqual(reason, "The damage meter is disabled.", "verbatim, untranslated")
    meter.SetRaise("IsDamageMeterAvailable", "boom")
    ok, reason = NS.Meter.IsAvailable()
    assertFalse(ok)
    assertTrue(tostring(reason):find("boom", 1, true) ~= nil)
    meter.Remove()
    ok, reason = NS.Meter.IsAvailable()
    assertFalse(ok)
    assertEqual(type(reason), "string")
end)

-- ── the session list ───────────────────────────────────────────────────────────────────────────

test("meter: SessionIDs and HasSession track the client's list by plain ID, in combat too", function()
    local NS, meter = fresh()
    meter.SetSession(17, FIGHT)
    meter.SetSession(18, FIGHT)
    meter.SetSecret(true)
    local ids = NS.Meter.SessionIDs()
    assertTrue(ids[17])
    assertTrue(ids[18])
    assertTrue(NS.Meter.HasSession(17))
    assertFalse(NS.Meter.HasSession(19))
    assertFalse(NS.Meter.HasSession(nil))
    meter.RemoveSession(17)
    assertFalse(NS.Meter.HasSession(17))
    meter.Remove()
    assertEqual(next(NS.Meter.SessionIDs()), nil, "no API is an empty set")
end)

test("meter: SessionAfter answers the first session that appeared at or after t", function()
    local NS, meter, inst = fresh()
    meter.SetSession(5, FIGHT)                       -- held before the addon looked: never "after"
    inst.mocks.__now = 100
    NS.Meter.Prime()
    assertNil(NS.Meter.SessionAfter(100), "the old session is the baseline")
    inst.mocks.__now = 110
    assertNil(NS.Meter.SessionAfter(110), "nothing new yet")
    inst.mocks.__now = 111
    meter.SetSession(6, FIGHT)
    meter.SetSession(7, FIGHT)                       -- two in one look: the older one is first
    assertEqual(NS.Meter.SessionAfter(110), 6)
    inst.mocks.__now = 130
    meter.SetSession(8, FIGHT)
    assertEqual(NS.Meter.SessionAfter(110), 6, "still the first one after combat entry")
    assertEqual(NS.Meter.SessionAfter(125), 8)
    assertNil(NS.Meter.SessionAfter(131))
end)

test("meter: SessionAfter reads IDs mid-combat and forgets a session the client dropped", function()
    local NS, meter, inst = fresh()
    inst.mocks.__now = 10
    NS.Meter.Prime()
    meter.SetSecret(true)
    inst.mocks.__now = 12
    meter.SetSession(3, FIGHT)
    assertEqual(NS.Meter.SessionAfter(10), 3)
    meter.RemoveSession(3)
    assertNil(NS.Meter.SessionAfter(10), "a reset drops it")
end)

test("meter: a stand-down forgets the baseline; the stand-up primes it again", function()
    local NS, meter, inst = fresh()
    inst.mocks.__now = 10
    meter.SetSession(3, FIGHT)
    NS.Meter.Prime()
    NS.SetByPath("general.enabled", false)
    inst.mocks.__now = 20
    meter.SetSession(4, FIGHT)                       -- appeared while disabled
    NS.SetByPath("general.enabled", true)
    assertNil(NS.Meter.SessionAfter(15), "a session from the disabled stretch is the new baseline")
end)

-- ── the pet ────────────────────────────────────────────────────────────────────────────────────

test("meter: ResolvePet answers the pet's GUID, nil with no pet, and remembers the last plain one", function()
    local NS, meter, inst = withPet()
    assertEqual(NS.Meter.ResolvePet(), PET)
    assertEqual(NS.Meter.LastPet(), PET)
    inst.mocks.__unitExists.pet = false
    assertNil(NS.Meter.ResolvePet(), "no pet now")
    assertEqual(NS.Meter.LastPet(), PET, "the pet that fought is still known")
    local NS2 = fresh()
    assertNil(NS2.Meter.ResolvePet())
    assertNil(NS2.Meter.LastPet())
    assertTrue(meter ~= nil)
end)

-- ── the live read ──────────────────────────────────────────────────────────────────────────────

test("meter: ReadLive returns opaque player and pet tables", function()
    local NS, meter = withPet()
    meter.SetSession(17, FIGHT)
    meter.SetSecret(true)
    local ok, live = pcall(NS.Meter.ReadLive)
    assertTrue(ok, "ReadLive raised: " .. tostring(live))
    local p, q = live.player, live.pet
    assertTrue(p ~= nil and q ~= nil)
    for _, k in ipairs({ "total", "dps", "maxAmount" }) do
        assertTrue(T.isSecret(p[k]), "player " .. k)
        assertTrue(T.isSecret(q[k]), "pet " .. k)
    end
    assertEqual(#p.spells, 2)
    assertEqual(#q.spells, 2)
    for i, sp in ipairs(q.spells) do
        assertTrue(T.isSecret(sp.spellID), "pet spell " .. i .. " spellID")
        assertTrue(T.isSecret(sp.total), "pet spell " .. i .. " total")
    end
    assertEqual(T.reveal(p.total), 9000)
    assertEqual(T.reveal(q.total), 3000)
    assertEqual(T.reveal(p.spells[1].spellID), 133, "Blizzard's order, never re-sorted")
    assertEqual(T.reveal(q.spells[1].spellID), 17253)
end)

test("meter: ReadLive with no pet GUID returns pet=nil", function()
    local NS, meter = fresh()
    meter.SetSession(17, FIGHT)
    meter.SetSecret(true)
    local live = NS.Meter.ReadLive()
    assertTrue(live.player ~= nil)
    assertNil(live.pet, "no pet unit")
    for _, c in ipairs(meter.CallsTo("GetCombatSessionSourceFromType")) do
        assertTrue(c.args[3] ~= nil, "the meter is never asked for a nil GUID")
    end
end)

test("meter: ReadLive with a pet the meter has no source for returns pet=nil", function()
    local NS, meter = withPet()
    meter.SetSession(17, copy(FIGHT, { pet = false }))
    local live = NS.Meter.ReadLive()
    assertTrue(live.player ~= nil)
    assertNil(live.pet)
end)

test("meter: ReadLive reads the Current session, or one session by ID", function()
    local NS, meter = withPet()
    meter.SetSession(17, FIGHT)
    meter.SetSession(18, { damage = 5, dps = 1, duration = 5, spells = {} })   -- 18 is Current
    assertEqual(T.reveal(NS.Meter.ReadLive().player.total), 5)
    local live = NS.Meter.ReadLive(17)
    assertEqual(T.reveal(live.player.total), 9000)
    assertEqual(T.reveal(live.pet.total), 3000)
    local calls = meter.CallsTo("GetCombatSessionSourceFromID")
    assertEqual(calls[#calls].args[1], 17)
    assertEqual(calls[#calls].args[2], NS.Meter.STAT_DAMAGE_DONE)
end)

test("meter: ReadLive answers no sources with no session, and nil with no API or a raising client", function()
    local NS, meter = fresh()
    local live = NS.Meter.ReadLive()
    assertNil(live.player, "no Current session yet")
    assertNil(live.pet)
    meter.SetSession(17, FIGHT)
    meter.SetRaise("GetCombatSessionSourceFromType", "nope")
    assertNil(NS.Meter.ReadLive().player)
    meter.Remove()
    assertNil(NS.Meter.ReadLive().player)
end)

-- The live client (DPS Race's smoke test, 2026-10-23): the source table may carry no amountPerSecond.
-- The player's figure then comes from its own row, else from the Dps meter type; each stays opaque.
test("meter: the player's live DPS rungs: the source, the local row, the Dps type, else nil", function()
    local NS, meter = fresh()
    meter.SetSecret(true)
    meter.SetSession(17, FIGHT)
    NS.Meter.NewLiveFight()
    local live = NS.Meter.ReadLive().player
    assertEqual(live.rung, "source")
    assertEqual(T.reveal(live.dps), 300)

    meter.SetSession(17, copy(FIGHT, { sourceDps = false, localFlagPlain = true }))
    live = NS.Meter.ReadLive().player
    assertEqual(live.rung, "localRow")
    assertTrue(T.isSecret(live.dps))
    assertEqual(T.reveal(live.dps), 300, "the local row's, never the other source's")

    meter.SetSession(17, copy(FIGHT, { sourceDps = false, rowDps = false, dpsType = true }))
    live = NS.Meter.ReadLive().player
    assertEqual(live.rung, "dpsType")
    assertEqual(T.reveal(live.dps), 300)

    meter.SetSession(17, copy(FIGHT, { sourceDps = false, rowDps = false, dpsType = true, dpsTypeRate = false }))
    live = NS.Meter.ReadLive().player
    assertNil(live.dps, "a dash, never a total under the DPS box")
    assertNil(live.rung)
    assertTrue(T.isSecret(live.total), "damage still shows")
end)

test("meter: the rung that served is logged once per fight, under the Meter tag", function()
    local NS, meter = fresh()
    meter.SetSession(17, copy(FIGHT, { sourceDps = false, localFlagPlain = true }))
    meter.SetSecret(true)
    local lines = {}
    NS.Debug = function(tag, fmt, ...) if tag == "Meter" then lines[#lines + 1] = fmt:format(...) end end
    NS.Meter.NewLiveFight()
    for _ = 1, 5 do NS.Meter.ReadLive() end
    local served = 0
    for _, l in ipairs(lines) do if l:find("live DPS from rung localRow", 1, true) then served = served + 1 end end
    assertEqual(served, 1, table.concat(lines, " | "))
    NS.Meter.NewLiveFight()
    NS.Meter.ReadLive()
    served = 0
    for _, l in ipairs(lines) do if l:find("live DPS from rung", 1, true) then served = served + 1 end end
    assertEqual(served, 2, "a new fight logs its rung again")
end)

-- ── the after-combat read ──────────────────────────────────────────────────────────────────────

test("meter: ReadFinal merges player+pet totals and marks isPet", function()
    local NS, meter = withPet()
    meter.SetSession(17, FIGHT)
    local r, err = NS.Meter.ReadFinal(17)
    assertNil(err)
    assertEqual(r.duration, 30)
    assertEqual(r.player.total, 9000, "the player's own row, not the session total")
    assertEqual(r.pet.total, 3000)
    assertEqual(r.merged.total, 12000)
    assertEqual(r.merged.dps, 400, "the player's 300 and the pet's 100")
    assertEqual(r.player.spells[1].spellID, 11366, "each source's spells by damage")
    assertEqual(r.pet.spells[1].spellID, 16827)
    local m = r.merged.spells
    assertEqual(#m, 4)
    local want = { { 11366, 6000, false }, { 133, 3000, false }, { 16827, 2000, true }, { 17253, 1000, true } }
    for i, w in ipairs(want) do
        assertEqual(m[i].spellID, w[1], "merged " .. i)
        assertEqual(m[i].total, w[2], "merged " .. i)
        assertEqual(m[i].isPet, w[3], "merged " .. i)
    end
    for _, sp in ipairs(m) do
        assertEqual(type(sp.spellID), "number")
        assertEqual(type(sp.total), "number")
    end
end)

test("meter: ReadFinal with no pet is the player alone", function()
    local NS, meter = fresh()
    meter.SetSession(17, FIGHT)
    local r = NS.Meter.ReadFinal(17)
    assertNil(r.pet)
    assertEqual(r.merged.total, 9000)
    assertEqual(#r.merged.spells, 2)
    assertFalse(r.merged.spells[1].isPet)
end)

test("meter: ReadFinal reads the pet that fought after it was dismissed", function()
    local NS, meter, inst = withPet()
    meter.SetSession(17, FIGHT)
    assertEqual(NS.Meter.ResolvePet(), PET)          -- seen in the fight
    inst.mocks.__unitExists.pet = false              -- dismissed before the read
    local r = NS.Meter.ReadFinal(17)
    assertEqual(r.pet.total, 3000)
    assertEqual(NS.Meter.ReadFinal(17, false).pet, nil, "false reads no pet at all")
end)

-- In combat UnitGUID("pet") may come back opaque. It is only ever handed back to the client: never
-- truth-tested, compared with false or remembered as the last pet (the kit cannot trap a boolean test,
-- so this pins the pass-through; modules/Meter.lua's petFor uses nil tests alone).
test("meter: an opaque pet GUID reaches the client untouched and is never remembered", function()
    local NS, meter = withPet()
    meter.SetSession(17, FIGHT)
    assertEqual(NS.Meter.ResolvePet(), PET)              -- the plain one, seen before combat
    local opaque = T.secret(PET)
    meter.SetPetGUID(opaque)
    assertTrue(NS.Meter.ResolvePet() == opaque)
    assertEqual(NS.Meter.LastPet(), PET, "a secret never replaces the last plain GUID")
    local ok, live = pcall(NS.Meter.ReadLive)
    assertTrue(ok, "ReadLive raised: " .. tostring(live))
    assertTrue(live.pet ~= nil, "the client answered the opaque GUID")
    local r, err
    ok, r, err = pcall(NS.Meter.ReadFinal, 17)
    assertTrue(ok, "ReadFinal raised: " .. tostring(r))
    assertNil(err)
    assertEqual(r.pet.total, 3000)
    ok, r = pcall(NS.Meter.ReadFinal, 17, opaque)
    assertTrue(ok, "ReadFinal raised on a caller's opaque GUID: " .. tostring(r))
    assertEqual(r.pet.total, 3000)
    local calls = meter.CallsTo("GetCombatSessionSourceFromID")
    assertTrue(calls[#calls].args[3] == opaque, "passed as it came")
end)

test("meter: ReadFinal returns nil while values are secret", function()
    local NS, meter = withPet()
    meter.SetSession(17, FIGHT)
    meter.SetSecret(true)
    local ok, r, err = pcall(NS.Meter.ReadFinal, 17)
    assertTrue(ok, "ReadFinal raised on a secret: " .. tostring(r))
    assertNil(r)
    assertEqual(err, "sealed", "in combat")
    meter.SetSecret(false)
    meter.SetSealed(17, true)
    r, err = NS.Meter.ReadFinal(17)
    assertNil(r)
    assertEqual(err, "sealed", "captured in combat, still secret after it")
    meter.SetSealed(17, false)
    assertEqual(NS.Meter.ReadFinal(17).merged.total, 12000, "readable once unsealed")
end)

test("meter: ReadFinal of a missing session, a raising client or no API answers nil and a reason", function()
    local NS, meter = fresh()
    local r, err = NS.Meter.ReadFinal(99)
    assertNil(r)
    assertEqual(err, "missing")
    r, err = NS.Meter.ReadFinal(nil)
    assertNil(r)
    assertEqual(err, "missing")
    meter.SetSession(17, FIGHT)
    meter.SetRaise("GetCombatSessionFromID", "client says no")
    r, err = NS.Meter.ReadFinal(17)
    assertNil(r)
    assertTrue(tostring(err):find("client says no", 1, true) ~= nil)
    meter.Remove()
    r, err = NS.Meter.ReadFinal(17)
    assertNil(r)
    assertEqual(err, "unavailable")
end)

test("meter: ReadFinal with no damage of the player's is a zero result, not an error", function()
    local NS, meter = fresh()
    meter.SetSession(17, { player = false, duration = 39, others = FIGHT.others })
    local r, err = NS.Meter.ReadFinal(17)
    assertNil(err)
    assertEqual(r.player.total, 0)
    assertEqual(r.merged.total, 0)
    assertEqual(r.merged.dps, 0)
    assertEqual(#r.merged.spells, 0)
end)

test("meter: amountPerSecond nil → dps computed as total/duration in ReadFinal", function()
    local NS, meter = withPet()
    local pet = { damage = 3000, spells = FIGHT.pet.spells }        -- no dps of its own
    meter.SetSession(17, copy(FIGHT, { sourceDps = false, rowDps = false, pet = pet }))
    local r = NS.Meter.ReadFinal(17)
    assertEqual(r.player.dps, 300, "9000 over 30 s")
    assertEqual(r.pet.dps, 100, "3000 over 30 s")
    assertEqual(r.merged.dps, 400)
    meter.SetSession(18, { damage = 100, duration = 0, sourceDps = false, rowDps = false, spells = {} })
    assertEqual(NS.Meter.ReadFinal(18).merged.dps, 0, "a zero-length session divides by nothing")
end)

test("meter: PET_SEPARATE=false path tags by cast set", function()
    local NS, meter = withPet()
    NS.Meter.PET_SEPARATE = false
    NS.Casts = { PetSpellSet = function() return { [17253] = true } end }
    -- The pet folded into its owner: the player's source holds the pet's spell, and no pet source.
    local folded = copy(FIGHT, { damage = 10000, pet = false, spells = {
        { id = 133, dmg = 3000, dps = 100 }, { id = 17253, dmg = 1000, dps = 33 }, { id = 11366, dmg = 6000, dps = 200 },
    } })
    meter.SetSession(17, folded)
    local r = NS.Meter.ReadFinal(17)
    assertEqual(#meter.CallsTo("GetCombatSessionSourceFromID") > 0, true)
    for _, c in ipairs(meter.CallsTo("GetCombatSessionSourceFromID")) do
        assertEqual(c.args[3], PLAYER, "no pet source is read")
    end
    assertEqual(r.merged.total, 10000, "the folded total, counted once")
    assertEqual(r.pet.total, 1000)
    assertEqual(r.player.total, 9000)
    assertEqual(r.pet.spells[1].spellID, 17253)
    local pets = 0
    for _, sp in ipairs(r.merged.spells) do
        if sp.isPet then pets = pets + 1; assertEqual(sp.spellID, 17253) end
    end
    assertEqual(pets, 1)
    NS.Casts = nil
    r = NS.Meter.ReadFinal(17)
    assertNil(r.pet, "no cast set yet: nothing is tagged")
    assertEqual(r.merged.total, 10000)
end)

-- ── the enemies ────────────────────────────────────────────────────────────────────────────────

test("meter: ReadEnemies sorts by damage taken", function()
    local NS, meter = fresh()
    meter.SetSession(17, FIGHT)
    local list, err = NS.Meter.ReadEnemies(17)
    assertNil(err)
    assertEqual(#list, 3)
    assertEqual(list[1].name, "Hateful Strike Dummy")
    assertEqual(list[1].creatureID, 31146)
    assertEqual(list[1].total, 12000)
    assertEqual(list[2].name, "Patchwerk")
    assertEqual(list[3].creatureID, 15931)
    local calls = meter.CallsTo("GetCombatSessionFromID")
    assertEqual(calls[#calls].args[2], NS.Meter.STAT_ENEMY_DAMAGE_TAKEN)
end)

test("meter: ReadEnemies is empty with a reason while sealed, missing or without the enum", function()
    local NS, meter = fresh()
    meter.SetSession(17, FIGHT)
    meter.SetSecret(true)
    local list, err = NS.Meter.ReadEnemies(17)
    assertEqual(#list, 0)
    assertEqual(err, "sealed")
    meter.SetSecret(false)
    list, err = NS.Meter.ReadEnemies(99)
    assertEqual(#list, 0)
    assertEqual(err, "missing")
    local inst = T.load{ mutate = function(m) T.mockMeter.install(m).SetSession(1, FIGHT); m.Enum = nil end }
    list, err = inst.NS.Meter.ReadEnemies(1)
    assertEqual(#list, 0)
    assertEqual(err, "unavailable")
end)

-- ── one reader ─────────────────────────────────────────────────────────────────────────────────

-- A file's code with its comments and its one-line string literals blanked: a report line that
-- mentions the meter by name (modules/Probe.lua's) is text, not a read of the client global.
local function codeOf(body)
    body = body:gsub("%-%-[^\n]*", "")
    body = body:gsub('"[^"\n]*"', '""')
    return body
end

local function filesNaming(pattern)
    local out = {}
    for _, path in ipairs(T.loadedAddonFiles) do
        local f = assert(io.open(T.root .. "/" .. path, "rb"))
        local body = codeOf(f:read("*a"))
        f:close()
        if body:find(pattern) then out[#out + 1] = (path:gsub("\\", "/")) end
    end
    return out
end

test("meter: modules/Meter.lua is the only file that reads C_DamageMeter", function()
    local hits = filesNaming("C_DamageMeter")
    assertEqual(#hits, 1, table.concat(hits, ", "))
    assertEqual(hits[1], "modules/Meter.lua")
end)

test("meter: Call reports a missing function and a raising one without throwing", function()
    local NS, meter = fresh()
    local ok, code = NS.Meter.Call("NoSuchFunction")
    assertFalse(ok)
    assertEqual(code, "unavailable")
    meter.SetRaise("GetAvailableCombatSessions", "kaboom")
    local detail
    ok, code, detail = NS.Meter.Call("GetAvailableCombatSessions")
    assertFalse(ok)
    assertEqual(code, "error")
    assertTrue(tostring(detail):find("kaboom", 1, true) ~= nil)
    assertTrue(NS.Meter.Api() ~= nil)
    meter.Remove()
    assertNil(NS.Meter.Api())
end)
