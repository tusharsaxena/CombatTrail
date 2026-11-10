-- tests/test_loadouts.lua — modules/Loadouts.lua (plan Task 2.4, spec §5 record size, ported from
-- DPS Race @045f479): the snapshot at a fight's start (the gear as trimmed item strings, never full
-- links, without the shirt and the tabard; the talent loadout), the talents stored once per distinct
-- loadout and referenced by hash (a collision told apart), and the sweep of loadouts no fight holds.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertNil = T.test, T.assertEqual, T.assertTrue, T.assertNil

local function fresh(mutate)
    local inst = T.load{ mutate = mutate }
    return inst.NS, inst.mocks, inst
end

-- ── the snapshot ────────────────────────────────────────────────────────────────────────────────

test("loadouts: an item link trims to its item string, and back", function()
    local NS = fresh()
    local L = NS.Loadouts
    local link = "|cnIQ4:|Hitem:212001::::::::80:267::6:2:10390:1540::::::|h[Hood of the Test]|h|r"
    assertEqual(L.TrimItem(link), "212001::::::::80:267::6:2:10390:1540")
    assertEqual(L.ItemString(L.TrimItem(link)), "item:212001::::::::80:267::6:2:10390:1540")
    assertEqual(L.TrimItem("|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"), "19019::::::::60")
    assertNil(L.TrimItem("not a link"))
    assertNil(L.TrimItem(nil))
end)

test("loadouts: Snapshot reads the gear as item strings without the shirt or the tabard, and the talents", function()
    local NS, M = fresh()
    M.__gear[19] = "|cnIQ1:|Hitem:5976::::::::80:267::::::::|h[Guild Tabard]|h|r"
    local lo = NS.Loadouts.Snapshot()
    assertEqual(lo.gear[1], "212001::::::::80:267::6:2:10390:1540")
    assertEqual(lo.gear[16], "212016::::::::80:267::6:1:10390")
    assertNil(lo.gear[4], "the shirt")
    assertNil(lo.gear[19], "the tabard")
    assertNil(lo.gear[2], "an empty slot is absent")
    local t = lo.talents
    assertEqual(t.importString, "C0PAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    -- The saved loadout is looked up by spec; WoW Forever has none, so the active config names it.
    assertEqual(t.name, NS.Compat.IsRetail() and "Raid ST" or "Active", "the player's saved loadout names it")
    assertEqual(t.heroSpecID, 58)
    assertEqual(t.heroName, "Diabolist")
    if NS.Compat.IsRetail() then assertEqual(t.specID, 250) else assertNil(t.specID) end
    M.__talents.savedConfigID = nil
    assertEqual(NS.Loadouts.Snapshot().talents.name, "Active")
end)

test("loadouts: a client without the APIs, or one that raises, or a secret, yields absent fields", function()
    local NS, M = fresh()
    M.__gear[5] = T.secret(M.__gear[5])
    M.C_Traits.GenerateImportString = function() error("boom") end
    local lo = NS.Loadouts.Snapshot()
    assertNil(lo.gear[5], "a sealed link")
    assertTrue(lo.gear[1] ~= nil)
    assertNil(lo.talents.importString)
    M.C_ClassTalents, M.GetInventoryItemLink = nil, nil
    assertNil(NS.Loadouts.Snapshot(), "nothing readable")
end)

test("loadouts: the snapshot rides the fight from its start", function()
    local meter
    local NS, M = fresh(function(m) meter = T.mockMeter.install(m) end)
    meter.SetSession(1, { damage = 10, dps = 1, duration = 10, spells = {} })
    M.__now = 100
    M.__fire("PLAYER_REGEN_DISABLED")
    local cur = NS.Fight.Current()
    assertNil(cur.loadout.gear, "the gear is the set's, not walked again at the pull")
    assertEqual(cur.gearSet, NS.Loadouts.CurrentGearSet(), "the set current at the pull")
    assertEqual(NS.Loadouts.GetGear(cur.gearSet)[1], "212001::::::::80:267::6:2:10390:1540")
    assertEqual(cur.loadout.talents.importString, "C0PAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
end)

-- ── the store ───────────────────────────────────────────────────────────────────────────────────

test("loadouts: the hash is djb2 as eight hex digits, and pure", function()
    local H = T.NS.Loadouts.Hash
    assertEqual(H(""), "00001505", "djb2's seed, 5381")
    assertEqual(H("a"), "0002b606", "5381 * 33 + 97")
    assertEqual(H("abcdef"), "f148cb7a", "a hash of 2^31 or more formats as itself")
    assertTrue(H("abc") ~= H("acb"))
    assertEqual(#H(("x"):rep(5000)), 8)
end)

test("loadouts: loadout dedupes by hash", function()
    local NS = fresh()
    local t = NS.Loadouts.Snapshot().talents
    local a = NS.Loadouts.Store(t)
    local b = NS.Loadouts.Store(NS.Loadouts.Snapshot().talents)
    assertEqual(a, b, "the same loadout stored twice")
    assertEqual(NS.Loadouts.Count(), 1)
    assertEqual(NS.Loadouts.Get(a).importString, t.importString)
    assertEqual(NS.Loadouts.Get(a).name, t.name)
    local s = NS.Loadouts.Store("C0PBBBB")
    assertTrue(s ~= a, "a bare import string is its own loadout")
    assertEqual(NS.Loadouts.Get(s).importString, "C0PBBBB")
    assertEqual(NS.Loadouts.Count(), 2)
    assertNil(NS.Loadouts.Store(nil))
    assertNil(NS.Loadouts.Store({}), "no import string, nothing stored")
    assertNil(NS.Loadouts.Store(""))
    assertNil(NS.Loadouts.Get("missing"))
end)

test("loadouts: two loadouts with one hash are told apart; the same one finds its own key", function()
    local NS = fresh()
    NS.Loadouts.Hash = function() return "deadbeef" end
    assertEqual(NS.Loadouts.Store("one"), "deadbeef")
    assertEqual(NS.Loadouts.Store("two"), "deadbeef-2")
    assertEqual(NS.Loadouts.Store("three"), "deadbeef-3")
    assertEqual(NS.Loadouts.Store("two"), "deadbeef-2", "a collided loadout stored again")
    assertEqual(NS.Loadouts.Get("deadbeef-2").importString, "two")
end)

test("loadouts: Sweep drops the loadouts no stored fight refers to", function()
    local NS = fresh()
    local kept = NS.Loadouts.Store("KEPT")
    NS.Loadouts.Store("ORPHAN")
    local fights = { a = { id = "a", loadout = kept }, b = { id = "b" }, c = "junk" }
    assertEqual(NS.Loadouts.Sweep(fights), 1)
    assertEqual(NS.Loadouts.Count(), 1)
    assertEqual(NS.Loadouts.Get(kept).importString, "KEPT")
    NS.db.global.fights = { a = { id = "a", loadout = kept } }
    assertEqual(NS.Loadouts.Sweep(), 0, "the stored fights by default")
    NS.db.global.fights = nil
    NS.Loadouts.Store("ORPHAN")
    assertEqual(NS.Loadouts.Sweep(), 0, "no fight store to read, nothing dropped")
end)

-- ── the gear sets (v0.2 plan Task A3) ──────────────────────────────────────────────────────────

local function link(id, extra)
    return ("|cnIQ4:|Hitem:%d::::::::80:267%s::::::|h[Item %d]|h|r"):format(id, extra or "", id)
end

-- Count the interns: every StoreGear call, from here on.
local function countStores(NS)
    local n, real = { v = 0 }, NS.Loadouts.StoreGear
    NS.Loadouts.StoreGear = function(...) n.v = n.v + 1 return real(...) end
    return n
end

test("gear sets: one changed slot (an enchant) is a second set; the stored set is a plain copy", function()
    local NS, M = fresh()
    local a = NS.Loadouts.CurrentGearSet()
    assertTrue(a ~= nil, "the login recon interned the gear")
    M.__gear[1] = "|cnIQ4:|Hitem:212001:7000:::::::80:267::6:2:10390:1540::::::|h[Hood of the Test]|h|r"
    local b = NS.Loadouts.Recon()
    assertTrue(b ~= a, "another set")
    assertEqual(NS.Loadouts.CurrentGearSet(), b)
    assertEqual(NS.Loadouts.GearCount(), 2)
    assertEqual(NS.Loadouts.GetGear(a)[1], "212001::::::::80:267::6:2:10390:1540", "the old set kept")
    assertEqual(NS.Loadouts.GetGear(b)[1], "212001:7000:::::::80:267::6:2:10390:1540")
    assertEqual(NS.db.global.gearSets[b][1], "212001:7000:::::::80:267::6:2:10390:1540", "db.global.gearSets")
    assertNil(NS.Loadouts.StoreGear(nil))
    assertNil(NS.Loadouts.StoreGear({}), "no item, no set")
    assertNil(NS.Loadouts.StoreGear({ [1] = T.secret("212001") }), "a secret is never hashed")
    assertNil(NS.Loadouts.GetGear("missing"))
end)

test("gear sets: two sets with one hash are told apart by their canonical form", function()
    local NS = fresh()
    NS.Loadouts.Hash = function() return "deadbeef" end
    assertEqual(NS.Loadouts.StoreGear({ [1] = "1" }), "deadbeef")
    assertEqual(NS.Loadouts.StoreGear({ [1] = "2" }), "deadbeef-2")
    assertEqual(NS.Loadouts.StoreGear({ [1] = "2" }), "deadbeef-2", "a collided set stored again")
    assertEqual(NS.Loadouts.StoreGear({ [1] = "1", [5] = "2" }), "deadbeef-3")
    assertEqual(NS.Loadouts.GetGear("deadbeef-2")[1], "2")
end)

test("gear sets: a burst of six PLAYER_EQUIPMENT_CHANGED in one frame interns one set", function()
    local NS, M = fresh()
    local before, stores = NS.Loadouts.GearCount(), countStores(NS)
    local first = NS.Loadouts.CurrentGearSet()
    for i, slot in ipairs({ 1, 3, 5, 7, 9, 16 }) do
        M.__gear[slot] = link(300000 + i)
        M.__fire("PLAYER_EQUIPMENT_CHANGED", slot, false)
    end
    assertEqual(stores.v, 0, "nothing interned until the debounce runs")
    assertEqual(NS.Loadouts.CurrentGearSet(), first)
    M.__fireTimers()
    assertEqual(stores.v, 1, "one intern for the whole swap")
    assertEqual(NS.Loadouts.GearCount(), before + 1, "one new set, not one per slot")
    assertEqual(NS.Loadouts.GetGear(NS.Loadouts.CurrentGearSet())[16], "300006::::::::80:267")
    M.__fireTimers()
    assertEqual(stores.v, 1, "the debounce does not re-arm itself")
end)

test("gear sets: a login with unchanged gear makes no new set", function()
    local first = fresh()
    local key, sets = first.Loadouts.CurrentGearSet(), first.db.global.gearSets
    local copy = {}
    for k, v in pairs(sets) do
        copy[k] = {}
        for slot, item in pairs(v) do copy[k][slot] = item end
    end
    -- A second session over the saved store: the same gear, the same set.
    local inst = T.load{ init = false }
    _G.CombatTrailDB = { global = { schemaVersion = inst.NS.SCHEMA_VERSION, gearSets = copy } }
    local AceAddon = inst.mocks.LibStub("AceAddon-3.0")
    AceAddon:InitializeAddon(inst.NS)
    AceAddon:EnableAddon(inst.NS)
    inst.mocks.__fire("PLAYER_ENTERING_WORLD", true, false)
    inst.mocks.__fireTimers()
    assertEqual(inst.NS.Loadouts.CurrentGearSet(), key)
    assertEqual(inst.NS.Loadouts.GearCount(), 1, "no new set")
    -- And a /reload (PLAYER_ENTERING_WORLD again) changes nothing either.
    inst.mocks.__fire("PLAYER_ENTERING_WORLD", false, true)
    inst.mocks.__fireTimers()
    assertEqual(inst.NS.Loadouts.GearCount(), 1)
end)

test("gear sets: recon runs on PLAYER_ENTERING_WORLD, on the equipment change and on UNIT_INVENTORY_CHANGED", function()
    local NS, M = fresh()
    local key = NS.Loadouts.CurrentGearSet()
    -- Changed while the addon was not watching (another PC, the addon off): the next world entry finds it.
    M.__gear[2] = link(400002)
    M.__fire("PLAYER_ENTERING_WORLD", false, true)
    M.__fireTimers()
    local afterPEW = NS.Loadouts.CurrentGearSet()
    assertTrue(afterPEW ~= key, "PLAYER_ENTERING_WORLD reconciles")
    assertEqual(NS.Loadouts.GetGear(afterPEW)[2], "400002::::::::80:267")
    M.__gear[3] = link(400003)
    M.__fire("PLAYER_EQUIPMENT_CHANGED", 3, false)
    M.__fireTimers()
    local afterEquip = NS.Loadouts.CurrentGearSet()
    assertTrue(afterEquip ~= afterPEW, "PLAYER_EQUIPMENT_CHANGED reconciles")
    -- An upgrade or a gem changes the item string without a slot swap.
    M.__gear[3] = link(400003, "::6:1:99999")
    M.__fire("UNIT_INVENTORY_CHANGED", "player")
    M.__fireTimers()
    assertTrue(NS.Loadouts.CurrentGearSet() ~= afterEquip, "UNIT_INVENTORY_CHANGED reconciles")
end)

test("gear sets: a stand-down drops the events and the pending recon; the stand-up reconciles", function()
    local NS, M = fresh()
    local key = NS.Loadouts.CurrentGearSet()
    M.__gear[2] = link(500002)
    M.__fire("PLAYER_EQUIPMENT_CHANGED", 2, false)
    NS.StandDown()
    assertEqual(M.__fireTimers(), 0, "the pending recon went with the stand-down")
    assertEqual(M.__fire("PLAYER_EQUIPMENT_CHANGED", 2, false), 0, "no equipment event heard")
    assertEqual(M.__fire("UNIT_INVENTORY_CHANGED", "player"), 0)
    assertEqual(M.__fire("PLAYER_ENTERING_WORLD", false, true), 0)
    assertEqual(NS.Loadouts.CurrentGearSet(), key, "nothing read while down")
    NS.StandUp()
    M.__fireTimers()
    assertTrue(NS.Loadouts.CurrentGearSet() ~= key, "the stand-up's recon finds the change")
end)

test("gear sets: the fight takes the set current at combat start, even with a swap pending or in combat", function()
    local meter
    local NS, M = fresh(function(m) meter = T.mockMeter.install(m) end)
    meter.SetSession(1, { damage = 10, dps = 1, duration = 10, spells = {} })
    -- A swap just before the pull: its debounce has not run yet, the pull reads it at once.
    M.__gear[2] = link(600002)
    M.__fire("PLAYER_EQUIPMENT_CHANGED", 2, false)
    M.__now = 100
    M.__fire("PLAYER_REGEN_DISABLED")
    local cur = NS.Fight.Current()
    local start = cur.gearSet
    assertEqual(NS.Loadouts.GetGear(start)[2], "600002::::::::80:267", "the pending swap counted")
    -- A weapon swap in combat moves the current set, not the fight's.
    M.__gear[16] = link(600016)
    M.__fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
    M.__fireTimers()
    assertTrue(NS.Loadouts.CurrentGearSet() ~= start)
    assertEqual(cur.gearSet, start, "D10: the set at combat start")
end)

test("gear sets: a recon in combat over sealed links is read again once combat ends", function()
    local NS, M = fresh()
    M.InCombatLockdown = function() return true end
    local plain = M.__gear[16]
    M.__gear[16] = T.secret(link(700016))
    M.__fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
    M.__fireTimers()
    local inCombat = NS.Loadouts.CurrentGearSet()
    assertNil(NS.Loadouts.GetGear(inCombat)[16], "the sealed weapon is absent, never hashed")
    M.__gear[16] = link(700016)
    M.InCombatLockdown = function() return false end
    M.__fire("PLAYER_REGEN_ENABLED")
    M.__fireTimers()
    assertEqual(NS.Loadouts.GetGear(NS.Loadouts.CurrentGearSet())[16], "700016::::::::80:267", "read again out of combat")
    -- Out of combat with nothing read in combat, the regen edge reads nothing.
    local stores = countStores(NS)
    M.__gear[16] = plain
    M.__fire("PLAYER_REGEN_ENABLED")
    M.__fireTimers()
    assertEqual(stores.v, 0, "no recon owed")
end)

test("gear sets: a recon the pull runs in combat over a sealed link is read again once combat ends", function()
    local meter
    local NS, M = fresh(function(m) meter = T.mockMeter.install(m) end)
    meter.SetSession(1, { damage = 10, dps = 1, duration = 10, spells = {} })
    -- A swap just before the pull, its debounce still pending: the pull reads it in combat.
    M.InCombatLockdown = function() return true end
    M.__gear[16] = T.secret(link(800016))
    M.__fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
    M.__now = 100
    M.__fire("PLAYER_REGEN_DISABLED")
    assertNil(NS.Loadouts.GetGear(NS.Loadouts.CurrentGearSet())[16], "the sealed weapon is absent")
    M.__gear[16] = link(800016)
    M.InCombatLockdown = function() return false end
    M.__fire("PLAYER_REGEN_ENABLED")
    M.__fireTimers()
    assertEqual(NS.Loadouts.GetGear(NS.Loadouts.CurrentGearSet())[16], "800016::::::::80:267",
        "the pull's in-combat recon is owed a re-read too")
end)

test("gear sets: with no set known yet, the pull reconciles once", function()
    local meter
    local NS, M = fresh(function(m) meter = T.mockMeter.install(m) end)
    meter.SetSession(1, { damage = 10, dps = 1, duration = 10, spells = {} })
    NS.Loadouts.__setCurrent(nil)
    M.__now = 100
    M.__fire("PLAYER_REGEN_DISABLED")
    local key = NS.Fight.Current().gearSet
    assertTrue(key ~= nil, "read at the pull")
    assertEqual(NS.Loadouts.CurrentGearSet(), key)
end)

test("gear sets: GearOf reads the record's set, else an inline gear (sample fights)", function()
    local NS = fresh()
    local key = NS.Loadouts.StoreGear({ [1] = "111", [13] = "113" })
    assertEqual(NS.Loadouts.GearOf({ gearSet = key })[13], "113")
    assertEqual(NS.Loadouts.GearOf({ gear = { [1] = "999" } })[1], "999", "the inline fallback")
    assertEqual(NS.Loadouts.GearOf({ gearSet = key, gear = { [1] = "999" } })[1], "111", "the set first")
    assertNil(NS.Loadouts.GearOf({ gearSet = "gone" }))
    assertNil(NS.Loadouts.GearOf({}))
    assertNil(NS.Loadouts.GearOf(nil))
end)

test("gear sets: Sweep drops the orphaned sets, keeping the referenced and the current one", function()
    local NS = fresh()
    local current = NS.Loadouts.CurrentGearSet()
    local used = NS.Loadouts.StoreGear({ [1] = "101" })
    NS.Loadouts.StoreGear({ [1] = "102" })
    NS.Loadouts.StoreGear({ [1] = "103" })
    assertEqual(NS.Loadouts.GearCount(), 4)
    local fights = { a = { id = "a", gearSet = used }, b = { id = "b" } }
    assertEqual(NS.Loadouts.Sweep(fights), 2, "two orphaned sets")
    assertEqual(NS.Loadouts.GearCount(), 2)
    assertTrue(NS.Loadouts.GetGear(used) ~= nil, "a stored fight's set kept")
    assertTrue(NS.Loadouts.GetGear(current) ~= nil, "the current set kept with no fight on it yet")
end)

test("gear sets: Sweep mid-fight keeps the live fight's set after a swap in combat", function()
    local meter
    local NS, M = fresh(function(m) meter = T.mockMeter.install(m) end)
    meter.SetSession(1, { damage = 10, dps = 1, duration = 10, spells = {} })
    M.__now = 100
    M.__fire("PLAYER_REGEN_DISABLED")
    local start = NS.Fight.Current().gearSet
    M.__gear[16] = link(900016)
    M.__fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
    M.__fireTimers()
    assertTrue(NS.Loadouts.CurrentGearSet() ~= start, "the swap moved the current set")
    NS.Loadouts.Sweep({})
    assertTrue(NS.Loadouts.GetGear(start) ~= nil, "the live fight's set survives a delete in combat")
end)

test("gear sets: the stored size estimate counts the sets", function()
    local NS = fresh()
    local before = NS.Retention.EstimateBytes()
    NS.Loadouts.StoreGear({ [1] = ("7"):rep(200) })
    assertTrue(NS.Retention.EstimateBytes() > before + 200, "the gear sets are in the estimate")
end)
