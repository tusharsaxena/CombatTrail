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

local function target(m, guid, name, classification, level)
    m.__unitExists.target = true
    m.__unitGUIDs.target = guid
    m.__unitNames.target = name
    m.__classifications.target = classification
    m.__unitLevels.target = level
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
    assertEqual(NS.Identity.BoardKey(id), "t:218671:?:Venture Co. Patron:8:k12")
    restoreProfile()
end)

test("identity: a dungeon without a keystone is dungeon content with no qualifier", function()
    local _, NS, m = fresh()
    place(m, { name = "The Rookery", type = "party", difficultyID = 1, maxPlayers = 5, instanceID = 2648 })
    local id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil,
                                   { { name = "Cursed Rooktender", creatureID = 212793, total = 3000 } })
    assertEqual(id.content, "dungeon")
    assertNil(id.keystoneLevel)
    assertEqual(NS.Identity.BoardKey(id), "t:212793:?:Cursed Rooktender:1")
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
    assertEqual(NS.Identity.BoardKey(id), "t:207454:?:Spinshroom:208:d8")
    restoreProfile()
end)

test("identity: a scenario that is no delve is scenario content", function()
    local _, NS, m = fresh("retail")
    place(m, { name = "Some Scenario", type = "scenario", difficultyID = 12, instanceID = 1000 })
    local id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil,
                                   { { name = "Scenario Mob", creatureID = 5000, total = 10 } })
    assertEqual(id.content, "scenario")
    assertEqual(id.isDelve, false)
    assertEqual(NS.Identity.BoardKey(id), "t:5000:?:Scenario Mob:12")
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
    assertEqual(NS.Identity.BoardKey(id), "t:11946:?:Drek'Thar:0:p40")
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
    assertEqual(NS.Identity.BoardKey(id), "t:1985:?:Ravenous Boar:0")
    restoreProfile()
end)

test("identity: a named target with no NPC ID falls back to the name-only key", function()
    local _, NS = fresh()
    local id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil, { { name = "Gankster", total = 400 } })
    assertEqual(id.targetName, "Gankster")
    assertNil(id.targetCreatureID)
    assertEqual(NS.Identity.BoardKey(id), "n:Gankster:0", "plan A2: name-only when there is no NPC ID")
    restoreProfile()
end)

-- ── the target's level and NPC ID (plan Task A2) ───────────────────────────────────────────────

-- One open-world fight on `npc` targeted at `level` (nil: no level), resolved over the meter's row.
local function boarFight(NS, m, npc, level, name)
    target(m, creatureGUID(npc), name or "Ravenous Boar", "normal", level)
    local fight = { snapshot = NS.Identity.Snapshot() }
    return NS.Identity.Resolve(fight, nil, { { name = name or "Ravenous Boar", creatureID = npc, total = 400 } }), fight
end

test("identity: the snapshot reads the target's level", function()
    local _, NS, m = fresh()
    target(m, creatureGUID(1985), "Ravenous Boar", "normal", 72)
    local snap = NS.Identity.Snapshot()
    assertEqual(snap.target.level, 72)
    assertEqual(snap.target.creatureID, 1985)
    restoreProfile()
end)

test("identity: the key is t:<npcID>:<level>:<name>:<difficulty>", function()
    local _, NS, m = fresh()
    local id = boarFight(NS, m, 1985, 72)
    assertEqual(id.targetLevel, 72)
    assertEqual(id.targetCreatureID, 1985)
    assertEqual(NS.Identity.BoardKey(id), "t:1985:72:Ravenous Boar:0")
    restoreProfile()
end)

test("identity: one NPC at two levels is two boards; the same NPC and level share one", function()
    local _, NS, m = fresh()
    local low, high, again = boarFight(NS, m, 1985, 70), boarFight(NS, m, 1985, 71), boarFight(NS, m, 1985, 70)
    local B = NS.Identity.BoardKey
    assertTrue(B(low) ~= B(high), "levels 70 and 71 split the board")
    assertEqual(B(low), B(again), "the same NPC and level share it")
    restoreProfile()
end)

test("identity: a skull level keys as -1", function()
    local _, NS, m = fresh()
    local id = boarFight(NS, m, 1985, -1)
    assertEqual(id.targetLevel, -1)
    assertEqual(NS.Identity.BoardKey(id), "t:1985:-1:Ravenous Boar:0")
    restoreProfile()
end)

test("identity: the level is taken only when the primary is the snapshot's target", function()
    local _, NS, m = fresh()
    target(m, creatureGUID(1985), "Ravenous Boar", "normal", 72)
    local id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil,
                                   { { name = "Angry Wolf", creatureID = 2000, total = 900 } })
    assertEqual(id.targetCreatureID, 2000)
    assertNil(id.targetLevel, "the boar's level is not the wolf's")
    assertEqual(NS.Identity.BoardKey(id), "t:2000:?:Angry Wolf:0")
    restoreProfile()
end)

test("identity: a boss fight's key ignores the level and the NPC ID, which stay for display", function()
    local _, NS, m = fresh()
    place(m, { name = "Liberation of Undermine", type = "raid", difficultyID = 15, maxPlayers = 30,
               instanceID = 2769 })
    target(m, creatureGUID(229953), "Chrome King Gallywix", "worldboss", -1)
    local fight = { encounter = { id = 3176, name = "Gallywix", difficultyID = 15 }, snapshot = NS.Identity.Snapshot() }
    local id = NS.Identity.Resolve(fight, nil, { { name = "Chrome King Gallywix", creatureID = 229953, total = 9 } })
    assertEqual(id.targetLevel, -1, "stored for display")
    assertEqual(id.targetCreatureID, 229953)
    assertEqual(NS.Identity.BoardKey(id), "e:3176:15")
    target(m, creatureGUID(229953), "Chrome King Gallywix", "worldboss", 83)
    fight.snapshot = NS.Identity.Snapshot()
    assertEqual(NS.Identity.BoardKey(NS.Identity.Resolve(fight, nil, {})), "e:3176:15", "another level, same board")
    restoreProfile()
end)

test("identity: a world boss keeps its creature key, level aside", function()
    local _, NS, m = fresh()
    target(m, creatureGUID(221224), "Aggregation of Horrors", "worldboss", -1)
    local id = NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil,
                                   { { name = "Aggregation of Horrors", creatureID = 221224, total = 9 } })
    assertEqual(id.isBoss, true)
    assertEqual(id.targetLevel, -1)
    assertEqual(NS.Identity.BoardKey(id), "c:221224:0")
    restoreProfile()
end)

test("identity: a sealed level or GUID leaves the fields nil and never raises", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local _, NS, m = fresh()
        target(m, creatureGUID(1985), "Ravenous Boar", "normal", T.secret(72))
        local snap = NS.Identity.Snapshot()
        assertNil(snap.target.level, "a sealed level is absent")
        assertEqual(snap.target.creatureID, 1985)
        local id = NS.Identity.Resolve({ snapshot = snap }, nil,
                                       { { name = "Ravenous Boar", creatureID = 1985, total = 400 } })
        assertNil(id.targetLevel)
        assertEqual(NS.Identity.BoardKey(id), "t:1985:?:Ravenous Boar:0", "a sealed level keys as ?")
        m.__unitGUIDs.target = T.secret(creatureGUID(1985))
        snap = NS.Identity.Snapshot()
        assertNil(snap.target.creatureID, "a sealed GUID is never parsed")
        assertNil(snap.target.level)
        id = NS.Identity.Resolve({ snapshot = snap }, nil, {})
        assertNil(id.targetCreatureID)
        assertNil(id.targetLevel)
        assertEqual(NS.Identity.BoardKey(id), "n:Ravenous Boar:0")
    end)
    restore()
    restoreProfile()
    assertTrue(ok, tostring(err))
end)

test("identity: where carries the zone and subzone; sealed or raising ones are absent", function()
    local _, NS, m = fresh()
    m.__context.zone, m.__context.subZone = "Burning Steppes", "Flame Crest"
    local snap = NS.Identity.Snapshot()
    assertEqual(snap.where.zone, "Burning Steppes")
    assertEqual(snap.where.subzone, "Flame Crest")
    local id = NS.Identity.Resolve({ snapshot = snap }, nil, {})
    assertEqual(id.zone, "Burning Steppes")
    assertEqual(id.subzone, "Flame Crest")
    m.__context.subZone = ""
    assertNil(NS.Identity.Snapshot().where.subzone, "an empty subzone is none")
    m.GetZoneText = function() error("no zone") end
    m.GetSubZoneText = nil
    snap = NS.Identity.Snapshot()
    assertNil(snap.where.zone)
    assertNil(snap.where.subzone)
    local restore = T.installSecretValue()
    m.GetZoneText = function() return T.secret("Burning Steppes") end
    local okSealed, sealed = pcall(NS.Identity.Snapshot)
    restore()
    restoreProfile()
    assertTrue(okSealed, tostring(sealed))
    assertNil(sealed.where.zone, "a secret zone is dropped")
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
    assertEqual(NS.Identity.BoardKey(ident), "t:31146:?:Raider's Training Dummy:0")
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
    assertEqual(NS.Identity.BoardKey(id), "t:5000:?:Mob:208")
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

-- ── WoW Forever: the predominant talent tree stands in for spec (v0.2 plan Task A4, D5) ────────

-- The talent-tab arm: GetNumTalentTabs / GetTalentTabInfo answering (name, icon, points, bg).
local function tabs(m, list)
    m.GetNumTalentTabs = function() return #list end
    m.GetTalentTabInfo = function(i)
        local t = list[i]
        if not t then return nil end
        return t[1], t[2], t[3], "bg"
    end
end

-- The C_Traits arm: the active config's tree, its groups out of display order, the points per group.
local function groups(m, list)
    m.__talents.treeIDs = { 900 }
    m.C_Traits.GetGroupDisplayInfoByTreeID = function(treeID)
        if treeID ~= 900 then return nil end
        local out = {}
        for i = #list, 1, -1 do
            out[#out + 1] = { groupID = 10 + i, displayName = list[i][1], orderIndex = i, iconFileID = list[i][2] }
        end
        return out
    end
    m.C_Traits.GetGroupCurrencyInfo = function(configID, ids)
        if configID ~= m.__talents.configID then return nil end
        local out = {}
        for _, id in ipairs(ids) do
            out[#out + 1] = { traitNodeGroupID = id, currencyInfos = { { spent = list[id - 10][3] } } }
        end
        return out
    end
end

local HUNTER = { { "Beast Mastery", 132164, 31 }, { "Marksmanship", 132222, 20 }, { "Survival", 132215, 0 } }

test("identity: forever: trees 31/20/0 make the first tree the spec (talent tabs)", function()
    local _, NS, m = fresh("forever")
    tabs(m, HUNTER)
    local trees = NS.Compat.TalentTrees()
    assertEqual(#trees, 3)
    assertEqual(trees[2].name, "Marksmanship")
    assertEqual(trees[2].icon, 132222)
    assertEqual(trees[2].points, 20)
    local who = NS.Identity.Snapshot().who
    assertEqual(table.concat(who.trees, "/"), "31/20/0")
    assertEqual(who.specID, "tree:MAGE:1", "the class and the tree's index, never a Retail spec ID")
    assertEqual(who.specName, "Beast Mastery")
    assertEqual(who.specIcon, 132164)
    restoreProfile()
end)

test("identity: forever: the C_Traits groups stand in when there are no talent tabs", function()
    local _, NS, m = fresh("forever")
    groups(m, { { "Beast Mastery", 132164, 5 }, { "Marksmanship", 132222, 41 }, { "Survival", 132215, 5 } })
    local who = NS.Identity.Who()
    assertEqual(table.concat(who.trees, "/"), "5/41/5", "in display order")
    assertEqual(who.specID, "tree:MAGE:2")
    assertEqual(who.specName, "Marksmanship")
    assertEqual(who.specIcon, 132222)
    restoreProfile()
end)

test("identity: forever: a tie goes to the first tree", function()
    local _, NS, m = fresh("forever")
    tabs(m, { { "Arcane", 1, 20 }, { "Fire", 2, 31 }, { "Frost", 3, 31 } })
    assertEqual(NS.Identity.Who().specName, "Fire")
    restoreProfile()
end)

test("identity: forever: 0/0/0 or no talent API gives no spec and never raises (Review focus 5)", function()
    local _, NS, m = fresh("forever")
    -- The client answers a class-wide spec on Forever; it is never read there.
    m.C_SpecializationInfo = { GetSpecialization = function() return 1 end,
                               GetSpecializationInfo = function() return 1491, "Hunter" end }
    tabs(m, { { "Arcane", 1, 0 }, { "Fire", 2, 0 }, { "Frost", 3, 0 } })
    local who = NS.Identity.Who()
    assertEqual(table.concat(who.trees, "/"), "0/0/0")
    assertNil(who.specID)
    assertNil(who.specName)
    assertNil(who.specIcon)
    m.GetNumTalentTabs, m.GetTalentTabInfo = nil, nil
    assertNil(NS.Compat.TalentTrees(), "no API: no trees")
    who = NS.Identity.Who()
    assertNil(who.trees)
    assertNil(who.specID)
    assertNil(who.specName)
    m.GetNumTalentTabs = function() error("boom") end
    m.GetTalentTabInfo = function() error("boom") end
    m.C_Traits.GetGroupDisplayInfoByTreeID = function() error("boom") end
    m.C_Traits.GetGroupCurrencyInfo = function() error("boom") end
    m.__talents.treeIDs = { 900 }
    assertNil(NS.Compat.TalentTrees(), "a raising API: no trees")
    assertNil(NS.Identity.Who().specID)
    restoreProfile()
end)

test("identity: forever: the second talent-tab shape (id, name, desc, icon, points) reads too", function()
    local _, NS, m = fresh("forever")
    m.GetNumTalentTabs = function() return 2 end
    m.GetTalentTabInfo = function(i) return 280 + i, ({ "Holy", "Shadow" })[i], "desc", 100 + i, ({ 11, 40 })[i] end
    local who = NS.Identity.Who()
    assertEqual(table.concat(who.trees, "/"), "11/40")
    assertEqual(who.specName, "Shadow")
    assertEqual(who.specIcon, 102)
    restoreProfile()
end)

test("identity: forever: sealed points give no trees; the last plain read stands in", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local _, NS, m = fresh("forever")
        tabs(m, HUNTER)
        assertEqual(NS.Identity.Who().specName, "Beast Mastery", "a plain read out of combat")
        m.GetTalentTabInfo = function(i) return HUNTER[i][1], HUNTER[i][2], T.secret(HUNTER[i][3]) end
        assertNil(NS.Compat.TalentTrees(), "a sealed point count is never compared")
        local who = NS.Identity.Snapshot().who
        assertEqual(who.specName, "Beast Mastery", "the snapshot keeps the last plain read")
        assertEqual(table.concat(who.trees, "/"), "31/20/0")
    end)
    restore()
    restoreProfile()
    assertTrue(ok, tostring(err))
end)

-- A sealed config ID, tree, group list or group answer is a sealed read too (not "no trees"): each
-- keeps the last plain read, and an inaccessible nested table is never indexed.
local MARKS = { { "Beast Mastery", 132164, 5 }, { "Marksmanship", 132222, 41 }, { "Survival", 132215, 5 } }

local SEALINGS = {
    { "config ID", function(m) m.C_ClassTalents.GetActiveConfigID = function() return T.secret(7001) end end },
    { "config info", function(m)
        local real = m.C_Traits.GetConfigInfo
        m.C_Traits.GetConfigInfo = function(id) return T.secret(real(id)) end
    end },
    { "tree list", function(m) m.__talents.treeIDs = T.secret({ 900 }) end },
    { "tree ID", function(m) m.__talents.treeIDs = { T.secret(900) } end },
    { "group list", function(m)
        local real = m.C_Traits.GetGroupDisplayInfoByTreeID
        m.C_Traits.GetGroupDisplayInfoByTreeID = function(id) return T.secret(real(id)) end
    end },
    { "currency row", function(m)
        local real = m.C_Traits.GetGroupCurrencyInfo
        m.C_Traits.GetGroupCurrencyInfo = function(c, ids)
            local out = real(c, ids)
            out[2].currencyInfos[1] = T.secret(out[2].currencyInfos[1])
            return out
        end
    end },
}

for _, case in ipairs(SEALINGS) do
    test("identity: forever: a sealed " .. case[1] .. " keeps the last plain read and never raises", function()
        local restore = T.installSecretValue()
        local ok, err = pcall(function()
            local _, NS, m = fresh("forever")
            m.issecrettable = function(t) return T.isSecret(t) end
            groups(m, MARKS)
            assertEqual(NS.Identity.Who().specName, "Marksmanship", "a plain read out of combat")
            case[2](m)
            local okRead, trees, why = pcall(NS.Compat.TalentTrees)
            assertTrue(okRead, tostring(trees))
            assertNil(trees, "a sealed read is no trees")
            assertEqual(why, "sealed", "and says it was sealed")
            local who = NS.Identity.Snapshot().who
            assertEqual(who.specName, "Marksmanship", "the snapshot keeps the last plain read")
            assertEqual(table.concat(who.trees, "/"), "5/41/5")
            local okApis, apis = pcall(NS.Compat.TalentApis)
            assertTrue(okApis, tostring(apis))
        end)
        restore()
        restoreProfile()
        assertTrue(ok, tostring(err))
    end)
end

test("identity: forever: Prime reads the trees out of combat, so the session's first sealed read has one", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local _, NS, m = fresh("forever")
        groups(m, MARKS)
        NS.Identity.Prime()
        m.C_ClassTalents.GetActiveConfigID = function() return T.secret(7001) end
        local who = NS.Identity.Snapshot().who
        assertEqual(who.specName, "Marksmanship", "the primed read stands in")
    end)
    restore()
    restoreProfile()
    assertTrue(ok, tostring(err))
end)

test("identity: the stand-up primes the trees (core/CombatTrail.lua RegisterGameEvents)", function()
    local _, NS = fresh()
    local primed = 0
    NS.Identity.Prime = function() primed = primed + 1 end
    NS.RegisterGameEvents()
    assertEqual(primed, 1)
    restoreProfile()
end)

test("identity: retail: the talent trees are absent and the spec is the client's", function()
    local _, NS, m = fresh("retail")
    tabs(m, HUNTER)
    assertNil(NS.Compat.TalentTrees(), "Retail has specializations, not trees (clients-§4)")
    local who = NS.Identity.Who()
    assertNil(who.trees)
    assertNil(who.specIcon)
    if m.GetSpecializationInfo then
        assertEqual(who.specID, 250)
        assertEqual(who.specName, "Blood")
    else
        -- Under the Forever run the instance was built without the spec globals: no spec, never a tree.
        assertNil(who.specID)
    end
    restoreProfile()
end)
