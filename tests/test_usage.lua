-- tests/test_usage.lua — modules/Usage.lua, what a fight used (plan Task 2.4, spec §7, ported from
-- DPS Race @045f479): the snapshot at the fight's start over the client's item, bag and aura reads;
-- detection from the snapshot, the fight's casts and the bag counts after it (pure); the fight's own
-- snapshot and its end counts (a parked fight's are taken when the next fight starts, so the next
-- fight's potion is never the parked one's); and nothing secret in what is answered.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local function near(got, want, msg)
    assertTrue(type(got) == "number" and math.abs(got - want) < 1e-6,
        (msg or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got))
end

-- The items the cases use: a trinket in slot 13, a potion, a flask and a Healthstone in the bags.
local TRINKET, TRINKET_SPELL = 190001, 400001
local POTION, POTION_SPELL = 211001, 431932
local FLASK, FLASK_SPELL = 211002, 432021
local STONE, STONE_SPELL = 5512, 6262

--- The client as the cases see it: the trinket worn, the three consumables in the backpack (the
--- potion over two stacks), a sword in the bags (not a consumable), the flask's buff and Well Fed on.
local function stock(M)
    M.__gear[13] = "|cnIQ4:|Hitem:" .. TRINKET .. "::::::::80:267::::::::|h[Test Trinket]|h|r"
    M.__itemSpells[TRINKET] = TRINKET_SPELL
    M.__itemSpells[POTION], M.__itemSpells[FLASK], M.__itemSpells[STONE] = POTION_SPELL, FLASK_SPELL, STONE_SPELL
    M.__itemSpells[777] = 7777
    M.__itemInfo[POTION], M.__itemInfo[FLASK], M.__itemInfo[STONE] = { 0, 1 }, { 0, 3 }, { 0, 0 }
    M.__itemInfo[777] = { 2, 7 }
    M.__bags[0] = { size = 6, [1] = { POTION, 2 }, [2] = { FLASK, 2 }, [4] = { STONE, 1 }, [5] = { POTION, 1 },
                    [6] = { 777, 1 } }
    M.__auras = { { FLASK_SPELL, "Flask of Testing" }, { 1459, "Arcane Intellect" }, { 999, "Well Fed" } }
end

-- A snapshot by hand: the shape Usage.Snapshot answers.
local function snapOf()
    return {
        gear = { { slot = 13, itemID = TRINKET, spellID = TRINKET_SPELL } },
        bags = { [POTION] = { count = 3, subclass = 1, spellID = POTION_SPELL },
                 [FLASK] = { count = 2, subclass = 3, spellID = FLASK_SPELL },
                 [STONE] = { count = 1, subclass = 0, spellID = STONE_SPELL } },
        auras = { { spellID = FLASK_SPELL, name = "Flask of Testing" }, { spellID = 999, name = "Well Fed" } },
    }
end

local function c(t, id, unit) return { t = t, spellID = id, unit = unit or "player", interrupted = false } end

local function hasSecret(v, depth)
    if T.isSecret(v) then return true end
    if type(v) ~= "table" or (depth or 0) > 6 then return false end
    for k, x in pairs(v) do
        if hasSecret(k, (depth or 0) + 1) or hasSecret(x, (depth or 0) + 1) then return true end
    end
    return false
end

local function kinds(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.kind .. ":" .. e.src end
    return table.concat(out, ",")
end

-- ── the snapshot ────────────────────────────────────────────────────────────────────────────────

test("usage: the snapshot reads the on-use slots, the bag consumables and the auras", function()
    local inst = T.load({ mutate = stock })
    local snap = inst.NS.Usage.Snapshot()
    assertEqual(#snap.gear, 1, "only a slot whose item has a use")
    assertEqual(snap.gear[1].slot, 13)
    assertEqual(snap.gear[1].spellID, TRINKET_SPELL)
    assertEqual(snap.bags[POTION].count, 3, "the potion's two stacks summed")
    assertEqual(snap.bags[POTION].subclass, 1)
    assertEqual(snap.bags[FLASK].spellID, FLASK_SPELL)
    assertNil(snap.bags[777], "not a consumable")
    assertEqual(#snap.auras, 3)
    assertEqual(snap.auras[3].name, "Well Fed")
    local counts = inst.NS.Usage.BagCounts()
    assertEqual(counts[POTION], 3)
    assertEqual(counts[777], 1)
end)

test("usage: an item's class is asked once per session, not on every snapshot", function()
    local inst = T.load({ mutate = stock })
    inst.NS.Usage.Snapshot()
    local first = inst.mocks.__itemCalls
    inst.NS.Usage.Snapshot()
    assertEqual(inst.mocks.__itemCalls, first, "the item data is cached")
end)

test("usage: an unreadable bag stack makes the after counts unknown, never a false drop", function()
    local inst = T.load({ mutate = stock })
    inst.mocks.__bags[0][4] = { STONE, T.secret(1) }
    assertNil(inst.NS.Usage.BagCounts())
    inst.mocks.C_Container = nil
    assertNil(inst.NS.Usage.BagCounts())
    local snap = inst.NS.Usage.Snapshot()
    assertEqual(next(snap.bags), nil)
end)

test("usage: a sealed aura ends the aura walk; a client without the APIs snapshots nothing", function()
    local inst = T.load({ mutate = stock })
    local real = inst.mocks.C_UnitAuras.GetAuraDataByIndex
    local sealed = { spellId = 1, name = "x" }
    inst.mocks.issecrettable = function(t) return t == sealed end
    inst.mocks.C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
        if i == 2 then return sealed end
        return real(unit, i, filter)
    end
    assertEqual(#inst.NS.Usage.Snapshot().auras, 1)
    inst.mocks.C_UnitAuras, inst.mocks.C_Container, inst.mocks.C_Item = nil, nil, nil
    local snap = inst.NS.Usage.Snapshot()
    assertEqual(#snap.gear, 0)
    assertEqual(#snap.auras, 0)
    assertEqual(next(snap.bags), nil)
end)

-- ── detection (pure) ────────────────────────────────────────────────────────────────────────────

test("usage: detection stacks casts, the bag drop and the start's auras, in that order", function()
    local Usage = T.NS.Usage
    local casts = { c(-5, 29722), c(3, TRINKET_SPELL), c(4, POTION_SPELL), c(90, TRINKET_SPELL), c(5, TRINKET_SPELL, "pet") }
    local after = { [POTION] = 2, [FLASK] = 2 }   -- the Healthstone is gone with no cast
    local used = Usage.Detect(snapOf(), casts, after)
    assertEqual(kinds(used), "gear:cast,potion:cast,other:bag,flask:buff,food:buff")
    assertEqual(used[1].itemID, TRINKET)
    assertEqual(used[1].slot, 13)
    assertEqual(used[1].n, 2, "a pet's cast of the same spell is not the player's use")
    near(used[1].times[1], 3)
    near(used[1].times[2], 90)
    assertEqual(used[2].itemID, POTION)
    near(used[2].times[1], 4)
    assertEqual(used[3].itemID, STONE)
    assertNil(used[3].times, "a bag drop has no time")
    assertEqual(used[4].itemID, FLASK)
    assertNil(used[5].itemID, "food is the buff, no item")
end)

test("usage: usage detects potion from cast + bag delta", function()
    local Usage = T.NS.Usage
    local snap = snapOf()
    snap.auras = {}
    local used = Usage.Detect(snap, { c(4, POTION_SPELL) }, { [POTION] = 2, [FLASK] = 2, [STONE] = 1 })
    assertEqual(kinds(used), "potion:cast", "the cast's drop is not counted again")
    assertEqual(#Usage.Detect(snap, {}, nil), 0, "unknown after counts detect no drop")
    used = Usage.Detect(snap, {}, { [POTION] = 1, [FLASK] = 2, [STONE] = 1 })
    assertEqual(kinds(used), "potion:bag", "two gone with no cast")
    assertEqual(used[1].n, 2)
end)

test("usage: of two items with one use spell, a cast is the one whose count dropped", function()
    local Usage = T.NS.Usage
    local snap = { gear = {}, auras = {},
                   bags = { [100] = { count = 4, subclass = 1, spellID = 55 }, [200] = { count = 4, subclass = 1, spellID = 55 } } }
    local used = Usage.Detect(snap, { c(10, 55) }, { [100] = 4, [200] = 3 })
    assertEqual(#used, 1)
    assertEqual(used[1].itemID, 200)
    used = Usage.Detect(snap, { c(10, 55) }, nil)
    assertEqual(used[1].itemID, 100, "unknown counts: the first")
end)

test("usage: the candidates are the on-use gear, then every bag consumable by item", function()
    local Usage = T.NS.Usage
    local list = Usage.Candidates(snapOf())
    assertEqual(#list, 4)
    assertEqual(list[1].kind, "gear")
    assertEqual(list[1].slot, 13)
    assertEqual(list[2].itemID, STONE)
    assertEqual(list[2].kind, "other")
    assertEqual(list[3].kind, "potion")
    assertEqual(list[4].kind, "flask")
    assertNil(Usage.Build(nil, {}, {}))
    local rec = Usage.Build(snapOf(), {}, nil)
    assertEqual(rec.v, 1)
    assertFalse(rec.edited)
    assertEqual(#rec.candidates, 4)
end)

-- ── a fight's own ───────────────────────────────────────────────────────────────────────────────

local FIGHT = { damage = 9000, dps = 300, duration = 30, spells = { { id = 133, dmg = 9000, dps = 300 } } }

local function fighting(inst, meter, id, t)
    inst.mocks.__now = t
    meter.SetSession(id, FIGHT)
    inst.mocks.InCombatLockdown = function() return true end
    inst.mocks.__fire("PLAYER_REGEN_DISABLED")
    return inst.NS.Fight.Current()
end

local function leaving(inst, t)
    inst.mocks.__now = t
    inst.mocks.InCombatLockdown = function() return false end
    inst.mocks.__fire("PLAYER_REGEN_ENABLED")
end

test("usage: each fight snapshots at its start, and ForFight detects with the counts after it", function()
    local meter
    local inst = T.load{ mutate = function(m) stock(m) meter = T.mockMeter.install(m) end }
    local NS = inst.NS
    local fight = fighting(inst, meter, 1, 100)
    assertEqual(type(fight.usageSnap), "table", "the snapshot rides the fight")
    inst.mocks.__bags[0][5] = nil                   -- one potion drunk
    local rec = NS.Usage.ForFight(fight, { c(4, POTION_SPELL) })
    assertEqual(rec.used[1].itemID, POTION)
    assertEqual(rec.used[1].src, "cast")
    assertFalse(hasSecret(rec), "nothing secret in the record")
    assertNil(NS.Usage.ForFight({ id = "x" }, {}), "a fight with no snapshot has no usage")
end)

test("usage: a parked fight's end counts are taken as the next fight starts", function()
    local meter
    local inst = T.load{ mutate = function(m) stock(m) meter = T.mockMeter.install(m) end }
    local NS = inst.NS
    local first = fighting(inst, meter, 1, 100)
    leaving(inst, 110)
    local second = fighting(inst, meter, 2, 116)   -- past the grace: the first is parked
    assertTrue(first ~= second)
    assertEqual(first.usageAfter[POTION], 3, "the counts at the second fight's start")
    inst.mocks.__bags[0][5] = nil                   -- a potion drunk in the second fight
    assertEqual(#NS.Usage.ForFight(first, {}).used, 2, "only the flask and food buffs, no potion")
    assertEqual(kinds(NS.Usage.ForFight(second, {}).used), "potion:bag,flask:buff,food:buff")
end)

-- ── deferred review items (plan Task 5.2b) ──────────────────────────────────────────────────────

test("usage: food is found by the Well Fed spell ID, or by the client's own name for it", function()
    local Usage = T.NS.Usage
    local snap = snapOf()
    local fedID = next(Usage.WELL_FED_SPELLS)
    assertTrue(fedID ~= nil, "a Well Fed spell ID is listed")
    snap.auras = { { spellID = fedID, name = nil } }
    assertEqual(kinds(Usage.Detect(snap, {}, nil)), "food:buff", "an aura with no readable name, by its ID")
    snap.auras = { { spellID = 123456, name = "Wohlgenaehrt" } }
    assertEqual(#Usage.Detect(snap, {}, nil), 0, "a name that is not the client's word for it")
    local inst = T.load({ mutate = function(m)
        local name = m.C_Spell.GetSpellName
        m.C_Spell.GetSpellName = function(id)
            if id == Usage.WELL_FED_SPELL then return "Wohlgenaehrt" end
            return name(id)
        end
    end })
    local U = inst.NS.Usage
    assertEqual(kinds(U.Detect(snap, {}, nil)), "food:buff", "another client language's Well Fed, by its name")
end)
