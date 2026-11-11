-- tests/test_filters.lua — modules/Filters.lua and the `history` defaults (plan Task 2.5, spec §5):
-- a fight is stored only if it passes the recording filters: the minimum length (30 s on Retail, 15 s
-- on WoW Forever; Race mode plan Task A1), bosses only (off) and the content toggles (all on,
-- scenarios too). The Retail-only kinds (Mythic+, delves, arenas) are declared for Retail and their
-- toggles are absent on WoW Forever (clients-§4).

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local function fresh()
    local inst = T.load()
    return inst.NS, inst.mocks, inst
end

local function world(extra)
    local ident = { content = "world", isBoss = false, targetName = "Angry Boar", targetCreatureID = 1985,
                    difficultyID = 0, otherTargets = 0 }
    for k, v in pairs(extra or {}) do ident[k] = v end
    return ident
end

test("filters: the history defaults are the plan's", function()
    local NS = fresh()
    local h = NS.defaults.profile.history
    assertEqual(h.bossesOnly, false)
    assertEqual(h.days, 7)
    assertEqual(h.keepBests, true)
    assertEqual(h.maxFights, 500)
end)

test("filters: the minimum length defaults to 30 s on Retail and 15 s on WoW Forever", function()
    local NS = fresh()
    assertEqual(NS.defaults.profile.history.minLength, NS.Compat.IsForever() and 15 or 30)
end)

test("filters: every content kind is saved by default, scenarios too", function()
    local NS = fresh()
    local c = NS.defaults.profile.history.content
    for _, key in ipairs(NS.Identity.ContentKeys()) do
        assertEqual(c[key], true, key)
    end
    assertEqual(c.scenario, true, "scenarios are on")
end)

test("filters: the content toggles are exactly this client's content kinds", function()
    local NS = fresh()
    local want = NS.Identity.ContentKeys()
    local got = {}
    for key in pairs(NS.defaults.profile.history.content) do got[#got + 1] = key end
    table.sort(want)
    table.sort(got)
    assertEqual(table.concat(got, ","), table.concat(want, ","))
end)

test("filters: retail: the mplus, delve and arena toggles are present and on", function()
    local NS = fresh()
    if not NS.Compat.IsRetail() then return end
    local c = NS.defaults.profile.history.content
    assertEqual(c.mplus, true)
    assertEqual(c.delve, true)
    assertEqual(c.arena, true)
end)

test("forever: mplus/delve/arena filter keys absent", function()
    local NS = fresh()
    if not NS.Compat.IsForever() then return end
    local c = NS.defaults.profile.history.content
    assertNil(c.mplus)
    assertNil(c.delve)
    assertNil(c.arena)
    assertEqual(c.bg, true, "an arena counts as a battleground there")
end)

test("filters: a fight under the minimum length is skipped as short", function()
    local NS = fresh()
    local min = NS.defaults.profile.history.minLength
    local ok, why = NS.Filters.Passes(world(), min - 1)
    assertFalse(ok)
    assertEqual(why, "short")
    assertTrue((NS.Filters.Passes(world(), min)), "the minimum length itself passes")
    ok, why = NS.Filters.Passes(world(), nil)
    assertFalse(ok)
    assertEqual(why, "short", "no length at all is short")
end)

test("filters: the minimum length follows the setting", function()
    local NS = fresh()
    NS.db.profile.history.minLength = 10
    assertTrue((NS.Filters.Passes(world(), 22)))
    NS.db.profile.history.minLength = 0
    assertTrue((NS.Filters.Passes(world(), 1)))
end)

test("filters: bossesOnly drops non-encounter", function()
    local NS = fresh()
    assertTrue((NS.Filters.Passes(world(), 60)), "off by default")
    NS.db.profile.history.bossesOnly = true
    local ok, why = NS.Filters.Passes(world(), 60)
    assertFalse(ok)
    assertEqual(why, "filtered")
    local boss = world({ content = "raid", isBoss = true, encounterID = 3176, difficultyID = 15 })
    assertTrue((NS.Filters.Passes(boss, 60)), "an encounter passes")
end)

test("filters: content toggle drops world", function()
    local NS = fresh()
    NS.db.profile.history.content.world = false
    local ok, why = NS.Filters.Passes(world(), 60)
    assertFalse(ok)
    assertEqual(why, "filtered")
    assertTrue((NS.Filters.Passes(world({ content = "raid" }), 60)), "another kind still passes")
end)

test("filters: scenarios are stored by default, a kind without a toggle is dropped", function()
    local NS = fresh()
    assertTrue((NS.Filters.Passes(world({ content = "scenario" }), 60)), "a scenario passes")
    local ok, why = NS.Filters.Passes(world({ content = "nonsense" }), 60)
    assertFalse(ok)
    assertEqual(why, "filtered")
    assertFalse((NS.Filters.Passes(nil, 60)), "no identity at all")
end)

test("filters: the short check comes before the content check", function()
    local NS = fresh()
    NS.db.profile.history.content.world = false
    local _, why = NS.Filters.Passes(world(), 5)
    assertEqual(why, "short")
end)
