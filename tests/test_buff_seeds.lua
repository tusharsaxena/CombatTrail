-- tests/test_buff_seeds.lua — defaults/BuffSeeds.lua (issue #13, CL-13a): each client's lists are
-- picked once, at file scope, into NS.BUFF_SEEDS (clients-§5), and carry the issue's anchors. The
-- shipped ids against the recorded rulings are tools/seeds/test_seeds.py's gate (TestBuffGate).

local T = _G.CT_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- The client is the kit profile's (KA0S_KIT_CLIENT): the gate runs this file under both, and a mock
-- stamped after load cannot re-run a file-scope pick, so the per-client lists are read as tables.

local function set(list)
    local out = {}
    for _, v in ipairs(list) do out[v] = true end
    return out
end

test("buff seeds: the kit profile's client list is picked once", function()
    local NS = T.load().NS
    local want = NS.Compat.IsForever() and NS.BuffSeeds.Forever or NS.BuffSeeds.Retail
    assertTrue(NS.BUFF_SEEDS == want, "NS.BUFF_SEEDS is the " .. tostring(NS.Compat.ClientKey()) .. " list")
    local got = NS.BuffSeedSet("buffs")
    for _, id in ipairs(want.buffs) do assertTrue(got[id], "BuffSeedSet holds " .. id) end
end)

test("buff seeds: WoW Forever lists Camp Benefits and Might of Stormwind, Retail neither", function()
    local NS = T.load().NS
    local forever, retail = set(NS.BuffSeeds.Forever.buffs), set(NS.BuffSeeds.Retail.buffs)
    assertTrue(forever[1229741], "Camp Benefits 1229741")
    assertTrue(forever[460940] and forever[1304678], "Might of Stormwind")
    assertTrue(not retail[1229741] and not retail[460940], "neither is in Retail's list")
end)

test("buff seeds: Retail lists its own world buffs", function()
    local retail = set(T.load().NS.BuffSeeds.Retail.buffs)
    assertTrue(retail[15366] and retail[22888], "Songflower Serenade and Rallying Cry of the Dragonslayer")
    assertTrue(not retail[46668], "WHEE! (experience, no stat) is ruled out")
end)

test("buff seeds: each client's Well Fed list holds 19705, and Food & Drink is subclass 5", function()
    local NS = T.load().NS
    for _, client in ipairs({ "Retail", "Forever" }) do
        local seeds = NS.BuffSeeds[client]
        assertTrue(set(seeds.wellFed)[19705], client .. " Well Fed 19705")
        assertEqual(seeds.foodSubclass, 5, client .. " Food & Drink subclass")
    end
end)

test("buff seeds: BuffSeedSet returns a fresh set each call, and no id twice in a list", function()
    local NS = T.load().NS
    local a, b = NS.BuffSeedSet("buffs"), NS.BuffSeedSet("buffs")
    assertTrue(a ~= b, "a fresh table per call")
    for _, client in ipairs({ "Retail", "Forever" }) do
        for _, list in ipairs({ "buffs", "wellFed" }) do
            local seen = {}
            for _, id in ipairs(NS.BuffSeeds[client][list]) do
                assertTrue(not seen[id], client .. "." .. list .. " holds " .. id .. " once")
                seen[id] = true
            end
        end
    end
end)
