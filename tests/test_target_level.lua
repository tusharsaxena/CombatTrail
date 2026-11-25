-- tests/test_target_level.lua — the target's level beside its name (issue #12): one formatter
-- (modules/Results_Fights.lua: TargetLevel, LevelSuffix, WithLevel, TargetLabel, LevelWords,
-- TargetSort) behind the Encounter or target cell, its sort and tooltip, the board label (the Board
-- grouping and the Insights tabs), the fight detail's meta line and the Targets section's primary
-- row. Each form: a level, a skull (-1, tinted red where colored), none (an older record, an unknown
-- target: the name alone, never "(Lnil)"), a boss (the suffix too, owner 2026-11-25), on both clients.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertNil

local function fresh(client)
    local inst = T.load{ mutate = function(m)
        if client then T.Loader.MockClient.apply(m, client) end
    end }
    return inst.NS
end

local NOW = os.time()

-- A stored-shape record against `name` at `level` (nil: none). `o` overrides: boss (an encounter).
local function rec(name, level, o)
    o = o or {}
    local ident = { content = "world", targetName = name, targetCreatureID = 4000, targetLevel = level,
                    instanceType = "none", zone = "Westfall", difficultyID = 0 }
    if o.boss then
        ident.content, ident.encounterID, ident.encounterName, ident.isBoss = "raid", 3176, name, true
        ident.difficultyID, ident.difficultyName = 15, "Heroic"
    end
    return { id = name .. tostring(level), t = NOW, duration = 30, identity = ident,
             who = { name = "Tester", realm = "Realm", client = "retail", class = "HUNTER" },
             damage = { merged = 30000 } }
end

local function targetColumn(NS)
    for _, col in ipairs(NS.ResultsFights.Columns()) do
        if col.key == "target" then return col end
    end
end

local function hasRed(NS, s)
    return s:find("|c" .. NS.ResultsTable.Hex(NS.ResultsTable.COLORS.red), 1, true) ~= nil
end

for _, client in ipairs({ "retail", "forever" }) do
    test(("target level (%s): a level reads \"<name> (L<level>)\""):format(client), function()
        local NS = fresh(client)
        local F, r = NS.ResultsFights, rec("Bluegill Raider", 29)
        assertEqual(F.TargetLevel(r), 29)
        assertEqual(F.LevelText(r), "29")
        assertEqual(F.LevelSuffix(r), "(L29)")
        assertEqual(F.TargetLabel(r), "Bluegill Raider (L29)")
        assertEqual(F.TargetLabel(r, true), "Bluegill Raider (L29)", "a level is never tinted")
        assertEqual(F.LevelWords(r), NS.L["level %s"]:format("29"))
        assertEqual((targetColumn(NS).text(r)), "Bluegill Raider (L29)")
    end)

    test(("target level (%s): a skull reads \"(L??)\", red where colored"):format(client), function()
        local NS = fresh(client)
        local F, r = NS.ResultsFights, rec("Hogger", -1)
        assertEqual(F.TargetLevel(r), -1)
        assertEqual(F.TargetLabel(r), "Hogger (L??)")
        local colored = F.TargetLabel(r, true)
        assertTrue(colored:find("Hogger ", 1, true) == 1, colored)
        assertTrue(colored:find("(L??)", 1, true) ~= nil and hasRed(NS, colored), "tinted red: " .. colored)
        assertTrue(hasRed(NS, (targetColumn(NS).text(r))), "the cell tints the skull")
        assertEqual(F.LevelWords(r), NS.L["level %s"]:format("??"))
        r.identity.targetLevel = -2
        assertEqual(F.LevelText(r), "??", "any level below 0 is the client's skull")
    end)

    test(("target level (%s): no level shows the name alone, never (Lnil)"):format(client), function()
        local NS = fresh(client)
        local F = NS.ResultsFights
        for _, level in ipairs({ false, 0, "29" }) do
            local r = rec("Angry Boar", level or nil)
            assertNil(F.TargetLevel(r))
            assertNil(F.LevelSuffix(r, true))
            assertNil(F.LevelWords(r))
            assertEqual(F.TargetLabel(r, true), "Angry Boar")
            assertEqual((targetColumn(NS).text(r)), "Angry Boar")
        end
        -- An older record: no level at all, an unknown target.
        local old = { id = "old", t = NOW, identity = { content = "world", unknown = true,
                                                        targetName = NS.L["Unknown target"] } }
        assertEqual(F.TargetLabel(old), NS.L["Unknown target"])
        assertEqual(F.TargetLabel({ id = "bare" }), NS.L["Unknown target"], "a record with no identity")
        assertTrue(not F.TargetLabel(old, true):find("(L", 1, true), "no suffix at all")
    end)

    test(("target level (%s): a boss keeps the suffix (owner, 2026-11-25)"):format(client), function()
        local NS = fresh(client)
        local F, r = NS.ResultsFights, rec("Vorasius", -1, { boss = true })
        assertEqual(F.TargetLabel(r), "Vorasius (L??)")
        assertEqual(F.BoardLabel(r), "Vorasius (L??) \194\183 Heroic")
        r.identity.targetLevel = 92
        assertEqual(F.TargetLabel(r), "Vorasius (L92)")
    end)
end

test("target level: the column sorts by name, then level (none, low to high, a skull last)", function()
    local NS = fresh()
    local col = targetColumn(NS)
    local list = { rec("Boar", -1), rec("Boar", 12), rec("Wolf", 3), rec("Boar", nil), rec("Boar", 9),
                   rec("Boar Raider", 1) }
    local sorted = NS.ResultsTable.Sort({ col }, list, "target", false)
    local got = {}
    for i, r in ipairs(sorted) do got[i] = NS.ResultsFights.TargetLabel(r) end
    assertEqual(table.concat(got, ","), "Boar,Boar (L9),Boar (L12),Boar (L??),Boar Raider (L1),Wolf (L3)")
end)

test("target level: the cell's tooltip, the board label and the Insights tab read the same", function()
    local NS = fresh()
    local r = rec("Bluegill Raider", 29)
    local tip = NS.ResultsTips.Cell(targetColumn(NS), r)
    assertEqual(tip[1], "Bluegill Raider (L29)")
    assertEqual(NS.ResultsFights.BoardLabel(r), "Bluegill Raider (L29)")
    assertEqual(NS.InsightsData.ScopeLabel(r), "Bluegill Raider (L29)")
    local skull = rec("Hogger", -1)
    assertTrue(not NS.ResultsFights.BoardLabel(skull):find("|c", 1, true), "a board label is plain: it is a sort rank")
end)

test("target level: the detail's meta reads \"<name> · level <n>\"", function()
    local NS = fresh()
    local r = rec("Bluegill Raider", 29)
    local what = NS.ResultsDetail.Meta(r)[2]
    assertTrue(what:find("Bluegill Raider \194\183 " .. NS.L["level %s"]:format("29"), 1, true) == 1, what)
    r.identity.targetLevel = -1
    what = NS.ResultsDetail.Meta(r)[2]
    assertTrue(what:find("Bluegill Raider \194\183 " .. NS.L["level %s"]:format("??"), 1, true) == 1, what)
    r.identity.targetLevel = nil
    what = NS.ResultsDetail.Meta(r)[2]
    assertTrue(what:find("level", 1, true) == nil, "no level, no words: " .. what)
end)

test("target level: the Targets section's primary row carries the level, the others their name", function()
    local NS = fresh()
    local r = rec("Bluegill Raider", 29)
    r.targets = { { name = "Bluegill Raider", total = 600 }, { name = "Bluegill Puddlejumper", total = 300 } }
    local rows = NS.ResultsTargets.Rows(r)
    assertEqual(NS.ResultsTargets.Label(r, rows[1]), "Bluegill Raider (L29)")
    assertEqual(NS.ResultsTargets.Label(r, rows[2]), "Bluegill Puddlejumper")
    r.identity.targetLevel = nil
    assertEqual(NS.ResultsTargets.Label(r, rows[1]), "Bluegill Raider", "an older record: the name alone")
end)
