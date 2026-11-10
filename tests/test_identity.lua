-- tests/test_identity.lua — modules/Identity.lua and defaults/Dummies.lua, plan Task 2.3: the combat-
-- start snapshot (who and target, secret-safe), the after-combat identity (encounter, primary target,
-- content, tier qualifiers) and the board key. Each case stands up its own instance and stamps the
-- client profile it is about, so the suite says the same under both kit profiles; Retail-only content
-- (delves, Mythic+, arenas) is absent on Forever (clients-§4).

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertNil

-- A fresh instance, stamped `client` ("retail" | "forever"; nil keeps the run's profile).
local function fresh(client)
    local inst = T.load()
    if client then T.Loader.MockClient.apply(inst.mocks, client) end
    return inst, inst.NS, inst.mocks
end

-- Put the run's own profile back as the kit's active one (MockClient remembers the last stamp).
local function restoreProfile()
    T.Loader.MockClient.apply(T.mocks)
end

local function place(m, fields)
    for k, v in pairs(fields) do m.__instance[k] = v end
end

local function target(m, guid, name, classification)
    m.__unitExists.target = true
    m.__unitGUIDs.target = guid
    m.__unitNames.target = name
    m.__classifications.target = classification
end

local function creatureGUID(id) return ("Creature-0-1465-2552-17-%d-00006E5A1B"):format(id) end

-- ── the board key ──────────────────────────────────────────────────────────────────────────────

test("identity: boss fight key e:3176:15", function()
    local _, NS, m = fresh()
    place(m, { name = "Liberation of Undermine", type = "raid", difficultyID = 15, maxPlayers = 30,
               instanceID = 2769 })
    local fight = { encounter = { id = 3176, name = "Gallywix", difficultyID = 15, groupSize = 20 },
                    snapshot = NS.Identity.Snapshot() }
    local id = NS.Identity.Resolve(fight, nil, { { name = "Chrome King Gallywix", creatureID = 229953, total = 9000 },
                                                 { name = "Darkfuse Technician", creatureID = 230100, total = 500 } })
    assertEqual(id.encounterID, 3176)
    assertEqual(id.encounterName, "Gallywix")
    assertEqual(id.difficultyID, 15)
    assertEqual(id.difficultyName, "Heroic")
    assertEqual(id.instanceType, "raid")
    assertEqual(id.instanceName, "Liberation of Undermine")
    assertEqual(id.content, "raid")
    assertEqual(id.isBoss, true)
    assertEqual(id.targetName, "Chrome King Gallywix")
    assertEqual(id.targetCreatureID, 229953)
    assertEqual(id.otherTargets, 1)
    assertEqual(NS.Identity.BoardKey(id), "e:3176:15")
    restoreProfile()
end)

test("identity: M+ trash key carries :k12", function()
    local _, NS, m = fresh("retail")
    place(m, { name = "Cinderbrew Meadery", type = "party", difficultyID = 8, maxPlayers = 5, instanceID = 2661 })
    m.__keystone = 12
    local fight = { snapshot = NS.Identity.Snapshot() }
    m.__keystone = nil      -- the run ended before the read: the combat-start snapshot holds the level
    local id = NS.Identity.Resolve(fight, nil, { { name = "Venture Co. Patron", creatureID = 218671, total = 3000 } })
    assertEqual(id.content, "mplus")
    assertEqual(id.keystoneLevel, 12)
    assertEqual(id.isBoss, false)
    assertEqual(NS.Identity.BoardKey(id), "c:218671:8:k12")
    restoreProfile()
end)

test("identity: a dungeon without a keystone is dungeon content with no qualifier", function()
    local _, NS, m = fresh()
    place(m, { name = "The Rookery", type = "party", difficultyID = 1, maxPlayers = 5, instanceID = 2648 })
    local id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil,
                                   { { name = "Cursed Rooktender", creatureID = 212793, total = 3000 } })
    assertEqual(id.content, "dungeon")
    assertNil(id.keystoneLevel)
    assertEqual(NS.Identity.BoardKey(id), "c:212793:1")
    restoreProfile()
end)

test("identity: delve key carries :d8 (retail)", function()
    local _, NS, m = fresh("retail")
    place(m, { name = "Fungal Folly", type = "scenario", difficultyID = 208, maxPlayers = 5, instanceID = 2664 })
    m.__inDelve, m.__delveTier = true, "8"
    local id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil,
                                   { { name = "Spinshroom", creatureID = 207454, total = 3000 } })
    assertEqual(id.content, "delve")
    assertEqual(id.isDelve, true)
    assertEqual(id.delveTier, 8)
    assertEqual(id.difficultyName, "Delves")
    assertEqual(NS.Identity.BoardKey(id), "c:207454:208:d8")
    restoreProfile()
end)

test("identity: a scenario that is no delve is scenario content", function()
    local _, NS, m = fresh("retail")
    place(m, { name = "Some Scenario", type = "scenario", difficultyID = 12, instanceID = 1000 })
    local id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil,
                                   { { name = "Scenario Mob", creatureID = 5000, total = 10 } })
    assertEqual(id.content, "scenario")
    assertEqual(id.isDelve, false)
    assertEqual(NS.Identity.BoardKey(id), "c:5000:12")
    restoreProfile()
end)

test("identity: bg key carries bracket", function()
    local _, NS, m = fresh()
    place(m, { name = "Alterac Valley", type = "pvp", difficultyID = 0, maxPlayers = 40, instanceID = 30 })
    -- A general: a creature, keyed by it, with the bracket.
    local id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil,
                                   { { name = "Drek'Thar", creatureID = 11946, total = 9000 } })
    assertEqual(id.content, "bg")
    assertEqual(id.pvpBracket, "40")
    assertEqual(NS.Identity.BoardKey(id), "c:11946:0:p40")
    -- Players: no creature, so the board is the battleground's own, still with the bracket.
    m.__pvp.ratedBG = true
    place(m, { name = "Warsong Gulch", maxPlayers = 10, instanceID = 489 })
    id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil,
                             { { name = "Somebody", total = 9000 }, { name = "Someone Else", total = 10 } })
    assertEqual(id.pvpBracket, "r10")
    assertEqual(id.targetName, "Somebody")
    assertNil(id.targetCreatureID)
    assertEqual(NS.Identity.BoardKey(id), "i:489:0:pr10")
    restoreProfile()
end)

test("identity: an arena is arena content on retail, keyed by bracket", function()
    local _, NS, m = fresh("retail")
    place(m, { name = "Nagrand Arena", type = "arena", difficultyID = 0, maxPlayers = 6, instanceID = 1505 })
    m.__pvp.soloShuffle = true
    local id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil, { { name = "Rogue", total = 10 } })
    assertEqual(id.content, "arena")
    assertEqual(id.pvpBracket, "ss")
    assertEqual(NS.Identity.BoardKey(id), "i:1505:0:pss")
    restoreProfile()
end)

test("identity: open world key has no qualifier", function()
    local _, NS, m = fresh()
    m.__keystone, m.__delveTier = 12, "8"      -- stale client answers the open world must not take
    local id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil,
                                   { { name = "Ravenous Boar", creatureID = 1985, total = 400 } })
    assertEqual(id.content, "world")
    assertEqual(id.instanceType, "none")
    assertEqual(id.difficultyID, 0)
    assertNil(id.keystoneLevel)
    assertNil(id.delveTier)
    assertNil(id.pvpBracket)
    assertEqual(NS.Identity.BoardKey(id), "c:1985:0")
    restoreProfile()
end)

test("identity: a player target in the open world has a name and no board", function()
    local _, NS = fresh()
    local id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil, { { name = "Gankster", total = 400 } })
    assertEqual(id.targetName, "Gankster")
    assertNil(NS.Identity.BoardKey(id), "a player is no board outside PvP instances")
    restoreProfile()
end)

-- ── training dummies ───────────────────────────────────────────────────────────────────────────

test("identity: the dummy list is picked once, per client; Forever's is empty by decision", function()
    local _, NS = fresh()
    local want = NS.Compat.IsForever() and NS.Dummies.Forever or NS.Dummies.Retail
    assertTrue(NS.DUMMIES == want, "the client's list")
    assertTrue(next(NS.Dummies.Forever) == nil, "no Forever dummy creature ID is known yet")
    assertEqual(NS.Dummies.Retail[31146], "Raider's Training Dummy")
    assertNil(NS.DummyName(nil))
    assertNil(NS.DummyName(1985))
    restoreProfile()
end)

test("identity: dummy creature -> content dummy", function()
    local _, NS = fresh()
    -- Forever's list is empty, so the case lends it one entry to exercise the same path.
    local id = 31146
    if NS.DUMMIES[id] == nil then NS.DUMMIES[id] = "Raider's Training Dummy" end
    local ident = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil,
                                      { { name = "Raider's Training Dummy", creatureID = id, total = 9000 } })
    assertEqual(ident.content, "dummy")
    assertEqual(ident.isBoss, false)
    assertEqual(NS.Identity.BoardKey(ident), "c:31146:0")
    restoreProfile()
end)

test("identity: a dummy found only by the snapshot's target is still a dummy", function()
    local _, NS, m = fresh()
    if NS.DUMMIES[31146] == nil then NS.DUMMIES[31146] = "Raider's Training Dummy" end
    target(m, creatureGUID(31146), "Raider's Training Dummy", "worldboss")
    local snap = NS.Identity.Snapshot()
    assertEqual(snap.target.creatureID, 31146)
    assertEqual(snap.target.isDummy, true)
    local id = NS.Identity.Resolve({ snapshot = snap }, nil, {})
    assertEqual(id.content, "dummy")
    assertEqual(id.targetName, "Raider's Training Dummy")
    assertEqual(id.otherTargets, 0)
    assertEqual(id.isBoss, false, "a boss-level dummy is no boss")
    restoreProfile()
end)

-- ── unknown, secrets, the snapshot ─────────────────────────────────────────────────────────────

test("identity: no enemies and no snapshot -> Unknown target, key nil", function()
    local _, NS = fresh()
    local id = NS.Identity.Resolve({}, nil, {})
    assertEqual(id.targetName, NS.L["Unknown target"])
    assertNil(id.targetCreatureID)
    assertEqual(id.otherTargets, 0)
    assertEqual(id.isBoss, false)
    assertNil(NS.Identity.BoardKey(id))
    assertNil(NS.Identity.BoardKey(nil))
    -- enemies nil (the read failed) is the same as none
    assertNil(NS.Identity.BoardKey(NS.Identity.Resolve({}, nil, nil)))
    restoreProfile()
end)

test("identity: an encounter with no readable enemy is named by the encounter and keeps its board", function()
    local _, NS, m = fresh()
    place(m, { name = "Liberation of Undermine", type = "raid", difficultyID = 15, maxPlayers = 30,
               instanceID = 2769 })
    local fight = { encounter = { id = 3176, name = "Gallywix", difficultyID = 15 },
                    snapshot = NS.Identity.Snapshot() }
    local id = NS.Identity.Resolve(fight, nil, {})
    assertEqual(id.targetName, "Gallywix")
    assertNil(id.unknown, "an encounter is a readable identity")
    assertEqual(id.isBoss, true)
    assertEqual(NS.Identity.BoardKey(id), "e:3176:15")
    restoreProfile()
end)

test("identity: a battleground fight with no readable target has no board", function()
    local _, NS, m = fresh()
    place(m, { name = "Warsong Gulch", type = "pvp", difficultyID = 0, maxPlayers = 10, instanceID = 489 })
    local id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil, {})
    assertEqual(id.pvpBracket, "10")
    assertEqual(id.unknown, true)
    assertNil(NS.Identity.BoardKey(id), "an unknown target is never keyed by its instance")
    restoreProfile()
end)

test("identity: a world boss target snapshot makes a boss", function()
    local _, NS, m = fresh()
    target(m, creatureGUID(221224), "Aggregation of Horrors", "worldboss")
    local id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil,
                                   { { name = "Aggregation of Horrors", creatureID = 221224, total = 9 } })
    assertEqual(id.isBoss, true)
    assertEqual(NS.Identity.BoardKey(id), "c:221224:0")
    restoreProfile()
end)

test("identity: the snapshot reads who and target", function()
    local _, NS, m = fresh()
    target(m, creatureGUID(1985), "Ravenous Boar", "normal")
    m.__unitExists.pet, m.__unitNames.pet, m.__families.pet = true, "Fang", "Wolf"
    local snap = NS.Identity.Snapshot()
    assertEqual(snap.who.name, "Testchar")
    assertEqual(snap.who.class, "MAGE")
    assertEqual(snap.who.ilvl, 639.0)
    assertEqual(snap.who.petName, "Fang")
    assertEqual(snap.who.petFamily, "Wolf")
    assertEqual(snap.who.client, NS.Compat.ClientKey())
    if NS.Compat.IsRetail() then
        assertEqual(snap.who.specID, 250)
        assertEqual(snap.who.specName, "Blood")
    end
    assertEqual(snap.target.name, "Ravenous Boar")
    assertEqual(snap.target.creatureID, 1985)
    assertEqual(snap.target.classification, "normal")
    assertEqual(snap.where.instanceType, "none")
    restoreProfile()
end)

test("identity: a player target's GUID is no creature", function()
    local _, NS, m = fresh()
    target(m, "Player-1-00000002", "Someone", nil)
    local snap = NS.Identity.Snapshot()
    assertEqual(snap.target.name, "Someone")
    assertNil(snap.target.creatureID)
    restoreProfile()
end)

test("identity: a secret target in combat leaves its fields absent, never raises", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local _, NS, m = fresh()
        m.__unitExists.target = true
        m.__unitGUIDs.target = T.secret(creatureGUID(1985))
        m.__unitNames.target = T.secret("Ravenous Boar")
        m.__classifications.target = T.secret("elite")
        m.UnitExists = function(unit) if unit == "target" then return T.secret(true) end return unit == "player" end
        local snap = NS.Identity.Snapshot()
        assertTrue(snap.target == nil or (snap.target.creatureID == nil and snap.target.name == nil),
                   "a sealed target reads as absent")
        local id = NS.Identity.Resolve({ snapshot = snap }, nil,
                                       { { name = T.secret("x"), creatureID = T.secret(5), total = T.secret(1) } })
        assertEqual(id.targetName, NS.L["Unknown target"], "a secret enemy row is no target")
        assertNil(NS.Identity.BoardKey(id))
    end)
    restore()
    restoreProfile()
    assertTrue(ok, tostring(err))
end)

test("identity: the fight's snapshot is taken at combat entry", function()
    local meter
    local inst = T.load{ mutate = function(m) meter = T.mockMeter.install(m) end }
    assertTrue(meter ~= nil)
    target(inst.mocks, creatureGUID(1985), "Ravenous Boar", "normal")
    inst.mocks.__inCombat = true
    inst.mocks.__fire("PLAYER_REGEN_DISABLED")
    local fight = inst.NS.Fight.Current()
    assertTrue(fight ~= nil and fight.snapshot ~= nil, "Fight takes NS.Identity.Snapshot()")
    assertEqual(fight.snapshot.target.creatureID, 1985)
end)

-- ── WoW Forever ────────────────────────────────────────────────────────────────────────────────

test("identity: forever: delve/mplus fields never set", function()
    local _, NS, m = fresh("forever")
    m.__inDelve, m.__delveTier, m.__keystone = true, "8", 12
    place(m, { type = "scenario", difficultyID = 208, name = "A Scenario" })
    local id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil,
                                   { { name = "Mob", creatureID = 5000, total = 10 } })
    assertNil(id.isDelve)
    assertNil(id.delveTier)
    assertNil(id.keystoneLevel)
    assertEqual(id.content, "scenario")
    assertEqual(NS.Identity.BoardKey(id), "c:5000:208")
    place(m, { type = "party", difficultyID = 8, name = "A Dungeon" })
    id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil, { { name = "Mob", creatureID = 5000, total = 10 } })
    assertEqual(id.content, "dungeon")
    assertNil(id.keystoneLevel)
    place(m, { type = "arena", difficultyID = 0, name = "An Arena", maxPlayers = 4, instanceID = 559 })
    id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil, { { name = "Foe", total = 10 } })
    assertEqual(id.content, "bg", "arenas are Retail-only content; Forever files its arena under PvP")
    restoreProfile()
end)

test("identity: the content keys follow the client", function()
    local _, NS = fresh("forever")
    local keys = table.concat(NS.Identity.ContentKeys(), ",")
    assertEqual(keys, "raid,dungeon,bg,world,dummy,scenario")
    local _, NS2 = fresh("retail")
    assertEqual(table.concat(NS2.Identity.ContentKeys(), ","), "raid,dungeon,mplus,delve,bg,arena,world,dummy,scenario")
    restoreProfile()
end)

test("identity: two-word Forever names handled", function()
    local _, NS, m = fresh("forever")
    m.RegionalUniqueNamesEnabled = function() return true end
    local names = { player = { "Traxex", "Silentshot" }, target = { "Doom", "Dock" } }
    m.UnitName = function(unit)
        local n = names[unit or "player"]
        if n then return n[1], n[2] end
        return m.__unitNames[unit]
    end
    m.UnitNameUnmodified = m.UnitName
    m.GetRealmName = function() return "CAMWOW AU1 Realm 2 PvP" end
    m.Enum = m.Enum or {}
    m.Enum.GameRule = { HardcoreRuleset = 1, RPRuleset = 2, PvPRuleset = 3 }
    m.C_GameRules = { IsGameRuleActive = function(rule) return rule == 3 end }
    m.__unitExists.target = true
    m.__unitGUIDs.target = "Player-1-00000002"
    local snap = NS.Identity.Snapshot()
    assertEqual(snap.who.name, "Traxex Silentshot", "the whole name, never the first word")
    assertEqual(snap.who.realm, "PvP", "the realm is the ruleset, never the surname or the long label")
    assertEqual(snap.target.name, "Doom Dock")
    local id = NS.Identity.Resolve({ snapshot = snap }, nil, {})
    assertEqual(id.targetName, "Doom Dock", "the snapshot's whole name when the meter has no enemy")
    id = NS.Identity.Resolve({ snapshot = snap }, nil, { { name = "Doom Dock", total = 5 } })
    assertEqual(id.targetName, "Doom Dock", "the meter's two-word name is kept whole")
    restoreProfile()
end)
