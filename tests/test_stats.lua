-- tests/test_stats.lua — modules/Stats.lua, the character's stats a fight was fought with (plan Task
-- 2.4, ported from DPS Race @045f479): the read (every value, a secret one absent, a client without
-- the APIs), the fight's start read filled in after combat for any field that came back secret, and
-- the pure display (groups, dashes, deltas).

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertNil = T.test, T.assertEqual, T.assertTrue, T.assertNil

-- The client's stat APIs over one settable table; `over` replaces fields (T.secret for a sealed one).
local function statMocks(m, over)
    local v = {
        primaryStat = 4, intellect = 12345.4, stamina = 98765, armor = 4321,
        ratings = { [9] = 1234, [18] = 2345, [26] = 3456, [29] = 456, [17] = 120, [21] = 80, [14] = 60 },
        crit = 25.304, haste = 18.5, mastery = 41.256, versBonus = 3.1, versExtra = 0.5,
        leech = 1.2, avoidance = 0.8, speed = 2.05,
    }
    for k, x in pairs(over or {}) do v[k] = x end
    m.__stats = v
    m.GetSpecialization = function() return 1 end
    m.GetSpecializationInfo = function() return 267, "Destruction", "", 0, "DAMAGER", m.__stats.primaryStat end
    m.UnitStat = function(_, i)
        if i == 4 then return 1000, m.__stats.intellect, 0, 0 end
        if i == 3 then return 1000, m.__stats.stamina, 0, 0 end
        return 1, 2, 0, 0
    end
    m.UnitArmor = function() return 100, m.__stats.armor end
    m.GetCombatRating = function(i) return m.__stats.ratings[i] end
    m.GetCritChance = function() return m.__stats.crit end
    m.GetRangedCritChance = function() return m.__stats.rangedCrit end
    m.GetSpellCritChance = function(school) return m.__stats.spellCrit and m.__stats.spellCrit[school] end
    m.GetHaste = function() return m.__stats.haste end
    m.GetMasteryEffect = function() return m.__stats.mastery, 1.5 end
    m.GetCombatRatingBonus = function() return m.__stats.versBonus end
    m.GetVersatilityBonus = function() return m.__stats.versExtra end
    m.GetLifesteal = function() return m.__stats.leech end
    m.GetAvoidance = function() return m.__stats.avoidance end
    m.GetSpeed = function() return m.__stats.speed end
end

local function fresh(over)
    local inst = T.load{ mutate = function(m) statMocks(m, over) end }
    return inst.NS, inst.mocks
end

-- ── the read ────────────────────────────────────────────────────────────────────────────────────

test("stats: Read reads the primary stat, stamina, armor and every rating with its percent", function()
    local NS = fresh()
    local s = NS.Stats.Read()
    assertEqual(s.v, 1)
    if NS.Compat.IsRetail() then
        assertEqual(s.primaryStat, 4, "the spec's primary stat (Intellect)")
        assertEqual(s.primary, 12345, "whole numbers")
    else
        assertNil(s.primaryStat, "no specialization on WoW Forever: no primary stat to name")
        assertNil(s.primary)
    end
    assertEqual(s.stamina, 98765)
    assertEqual(s.armor, 4321)
    assertEqual(s.critRating, 1234)
    assertEqual(s.crit, 25.3, "percents to two decimals")
    assertEqual(s.haste, 18.5)
    assertEqual(s.mastery, 41.26)
    assertEqual(s.vers, 3.6, "versatility's rating bonus plus its flat bonus")
    assertEqual(s.speedRating, 60)
end)

test("stats: crit is the highest of melee, ranged and each spell school's", function()
    local NS = fresh({ crit = 20.1, rangedCrit = 22.5,
                       spellCrit = { [2] = 24, [3] = T.secret(99), [6] = 31.456, [7] = 30 } })
    assertEqual(NS.Stats.Read().crit, 31.46)
    NS = fresh({ crit = T.secret(40), spellCrit = { [2] = 18 } })
    assertEqual(NS.Stats.Read().crit, 18, "a secret reading is skipped, not compared")
end)

test("stats: a secret value is absent, never compared or kept", function()
    local NS = fresh({ crit = T.secret(25.3), stamina = T.secret(98765), primaryStat = T.secret(4),
                       ratings = { [9] = T.secret(1234), [18] = 2345 } })
    local s = NS.Stats.Read()
    assertNil(s.crit)
    assertNil(s.critRating)
    assertNil(s.stamina)
    assertNil(s.primaryStat)
    assertNil(s.primary)
    assertEqual(s.hasteRating, 2345)
    for k, v in pairs(s) do assertTrue(not T.isSecret(v), "a secret reached the record: " .. tostring(k)) end
end)

test("stats: a client without the APIs, or one that raises, yields absent fields; nothing readable is nil", function()
    local NS, M = fresh()
    M.GetCritChance = function() error("boom") end
    M.UnitArmor = nil
    local s = NS.Stats.Read()
    assertNil(s.crit)
    assertNil(s.armor)
    assertEqual(s.haste, 18.5)
    for _, name in ipairs({ "UnitStat", "UnitArmor", "GetCombatRating", "GetCritChance", "GetRangedCritChance",
                            "GetSpellCritChance", "GetHaste", "GetMasteryEffect", "GetCombatRatingBonus",
                            "GetVersatilityBonus", "GetLifesteal", "GetAvoidance", "GetSpeed",
                            "GetSpecialization", "GetSpecializationInfo" }) do
        M[name] = nil
    end
    assertNil(NS.Stats.Read(), "nothing readable, yet a record")
end)

test("stats: the fight's start read rides the fight; Fill completes it after combat from a fresh read", function()
    local meter
    local inst = T.load{ mutate = function(m)
        statMocks(m, { crit = T.secret(25.3), ratings = { [9] = T.secret(1234), [18] = 2345 } })
        meter = T.mockMeter.install(m)
    end }
    local NS, M = inst.NS, inst.mocks
    meter.SetSession(1, { damage = 10, dps = 1, duration = 10, spells = {} })
    M.__now = 100
    M.__fire("PLAYER_REGEN_DISABLED")
    local fight = NS.Fight.Current()
    assertEqual(type(fight.stats), "table")
    assertNil(fight.stats.crit, "sealed in combat")
    M.__stats.crit, M.__stats.ratings[9], M.__stats.haste = 26, 1300, 99
    local s = NS.Stats.Fill(fight.stats)
    assertEqual(s.crit, 26, "filled from the after-combat read")
    assertEqual(s.critRating, 1300)
    assertEqual(s.haste, 18.5, "a field read at the start keeps its start value")
    assertEqual(NS.Stats.Fill(nil).haste, 99, "no start read: the fresh read")
end)

-- ── the display ─────────────────────────────────────────────────────────────────────────────────

test("stats: Groups lays out Primary, Secondary and Tertiary with each value's text", function()
    local NS = fresh()
    local groups = NS.Stats.Groups(NS.Stats.Read())
    assertEqual(#groups, 3)
    assertEqual(groups[1].title, "Primary")
    if NS.Compat.IsRetail() then
        assertEqual(groups[1].rows[1].label, "Intellect", "the spec's primary stat names the row")
        assertEqual(groups[1].rows[1].text, "12,345")
    else
        assertEqual(groups[1].rows[1].label, "Primary stat")
        assertEqual(groups[1].rows[1].text, "\226\128\148")
    end
    assertEqual(groups[2].rows[1].text, "1,234 \194\183 25.30%", "the rating and the percent")
    assertEqual(groups[3].rows[3].text, "60 \194\183 2.05%")
    assertNil(groups[2].rows[1].delta, "a delta with nothing to compare with")
    for _, g in ipairs(NS.Stats.Groups(nil, NS.Stats.Read())) do
        for _, r in ipairs(g.rows) do assertEqual(r.text, "\226\128\148", r.key) end
    end
    assertEqual(NS.Stats.Groups(nil)[1].rows[1].label, "Primary stat")
end)

test("stats: deltas against the compared fight, signed, the percent deciding a rated row", function()
    local NS = fresh()
    local s = NS.Stats.Read()
    s.primaryStat, s.primary = 4, 12345   -- the Retail read (WoW Forever names no primary stat)
    local o = {}
    for k, v in pairs(s) do o[k] = v end
    o.primary, o.critRating, o.crit, o.hasteRating, o.haste = s.primary + 300, s.critRating - 140, s.crit - 1.17,
        s.hasteRating + 10, s.haste - 0.2
    local text, sign = NS.Stats.Delta(s, o, "primary")
    assertEqual(text, "-300")
    assertEqual(sign, -1)
    text, sign = NS.Stats.Delta(s, o, "crit", true)
    assertEqual(text, "+140 \194\183 +1.17%")
    assertEqual(sign, 1)
    text, sign = NS.Stats.Delta(s, o, "haste", true)
    assertEqual(text, "-10 \194\183 +0.20%")
    assertEqual(sign, 1, "the percent decides")
    o.primaryStat = 2
    assertNil(NS.Stats.Delta(s, o, "primary"), "another primary stat has no delta")
    assertEqual(NS.Stats.Of({ stats = s }), s)
    assertNil(NS.Stats.Of({}))
end)
