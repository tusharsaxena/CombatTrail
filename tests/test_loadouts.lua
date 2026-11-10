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
    local lo = NS.Fight.Current().loadout
    assertEqual(lo.gear[1], "212001::::::::80:267::6:2:10390:1540")
    assertEqual(lo.talents.importString, "C0PAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
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
