-- tests/test_insights_data.lua — the Insights tab's pure half (modules/Results_InsightsData.lua, Race
-- mode plan Task D2, spec §7), ported from DPS Race @f8078c7 (tests/test_insights_data.lua) onto Combat
-- Trail's fight records: the filters (character, spec, content, date, and on Retail Fights / Races /
-- All, Clean only, Include incomplete, and under Races the race length and the dummy kind), the
-- faceted options with their counts, the fallback of an emptied selection, and the one stats pass:
-- the cards, the boards (a fight's or a race's, each board-relative), the board tabs, the new bests,
-- the counts by character and day, the damage tail and the late casts. Runs under both kit profiles:
-- on WoW Forever there is no race control, and a saved race counts as a fight with its race DPS.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local F = dofile(T.root .. "/tests/insights_fixture.lua")(T)

local function forever() return T.NS.Compat.IsForever() end

local function fresh()
    local inst = T.load()
    return inst.NS, inst.mocks
end

local function values(options)
    local out = {}
    for _, o in ipairs(options or {}) do out[#out + 1] = tostring(o.value) end
    return table.concat(out, ",")
end

local function near(a, b) return math.abs(a - b) < 1e-6 end

-- ── the filters ─────────────────────────────────────────────────────────────────────────────────

test("insights: Filter opens wide; on Retail Include incomplete and Clean only judge the races", function()
    local NS = fresh()
    local D = NS.InsightsData
    local all = F.history(NS)
    local stock = NS.defaults.profile.results.insights
    assertEqual(stock.character, "all", "the cross-character view")
    assertEqual(stock.days, 0, "all time")
    assertFalse(stock.includeIncomplete)
    if forever() then
        -- No race control on WoW Forever: every saved fight passes, the incomplete race too.
        assertEqual(F.ids(D.Filter(all, nil, F.NOW)), "f1,f2,f3,r1,r2,r3,r4")
        assertEqual(F.ids(D.Filter(all, { kind = "races", cleanOnly = true }, F.NOW)), "f1,f2,f3,r1,r2,r3,r4",
            "a stored race view is no filter there")
        return
    end
    assertEqual(F.ids(D.Filter(all, nil, F.NOW)), "f1,f2,f3,r1,r2,r3", "the incomplete race left out")
    assertEqual(F.ids(D.Filter(all, { includeIncomplete = true }, F.NOW)), "f1,f2,f3,r1,r2,r3,r4")
    assertEqual(F.ids(D.Filter(all, { cleanOnly = true }, F.NOW)), "f1,f2,f3,r1,r2",
        "the late Incinerate flags r3; the ignored Feign Death never would")
    assertEqual(F.ids(D.Filter(all, { kind = "races" }, F.NOW)), "r1,r2,r3")
    assertEqual(F.ids(D.Filter(all, { kind = "fights" }, F.NOW)), "f1,f2,f3")
    assertEqual(F.ids(D.Filter(all, { kind = "races", length = 60 }, F.NOW)), "r3")
    assertEqual(F.ids(D.Filter(all, { kind = "races", dummyKind = "cleave" }, F.NOW)), "r1,r2")
    -- The race length and the dummy kind apply under Races only.
    assertEqual(F.ids(D.Filter(all, { length = 60 }, F.NOW)), "f1,f2,f3,r1,r2,r3")
    assertEqual(F.ids(D.Filter(all, { character = F.charKey(NS, "lan") }, F.NOW)), "f3,r3")
    assertEqual(F.ids(D.Filter(all, { spec = 63, content = "raid" }, F.NOW)), "f1,f2")
    assertEqual(F.ids(D.Filter(all, { days = 1 }, F.NOW)), "", "today: only the incomplete race")
end)

test("insights: Options lists each facet's values among the fights every other filter passes, with counts", function()
    local NS = fresh()
    local D = NS.InsightsData
    local all = F.history(NS)
    local o = D.Options(all, nil, F.NOW)
    local n = forever() and 7 or 6
    assertEqual(o.character[1].label, ("All characters (%d)"):format(n), "led by All, no Current head")
    assertEqual(values(o.character), "all," .. F.charKey(NS, "lan") .. "," .. F.charKey(NS, "tush"))
    assertEqual(o.character[3].label, ("Tush (%d)"):format(forever() and 5 or 4))
    assertEqual(values(o.spec), "all,267,63")
    assertEqual(values(o.days), "1,7,30,0", "the date ranges always number four")
    assertEqual(o.days[4].label, ("All time (%d)"):format(n))
    if forever() then
        assertNil(o.kind, "no Fights / Races / All on WoW Forever")
        assertNil(o.length)
        assertNil(o.dummyKind)
        return
    end
    assertEqual(F.labels(o.kind), "Fights and races (6)|Fights only (3)|Races only (3)")
    assertNil(o.length, "the race length is offered under Races only")
    -- Faceted: a dropdown lists what the OTHER filters leave.
    o = D.Options(all, { kind = "races" }, F.NOW)
    assertEqual(F.labels(o.length), "Any race length (3)|1:00 (1)|3:00 (2)")
    assertEqual(F.labels(o.dummyKind), "All dummy kinds (3)|Cleave (2)|Boss-level (1)", "in the catalog's order")
    assertEqual(F.labels(o.kind), "Fights and races (6)|Fights only (3)|Races only (3)", "the kind's own list ignores itself")
    o = D.Options(all, { kind = "races", length = 60 }, F.NOW)
    assertEqual(F.labels(o.dummyKind), "All dummy kinds (1)|Boss-level (1)")
    assertEqual(F.labels(o.length), "Any race length (3)|1:00 (1)|3:00 (2)")
end)

test("insights: a closed dropdown names its choices on the All head, and a pick by its name alone", function()
    local NS = fresh()
    local D = NS.InsightsData
    local o = D.Options(F.history(NS), nil, F.NOW)
    assertEqual(D.ClosedLabel(o.character, "all"), "All characters (2)")
    assertEqual(D.ClosedLabel(o.character, F.charKey(NS, "lan")), "Lanfear")
    assertEqual(D.ClosedLabel(o.days, 0), "All time", "the date head is its name alone")
    assertNil(D.ClosedLabel(o.character, "nobody"))
end)

test("insights: Normalize sets a selection with no fights back, never the one just changed, in bar order", function()
    local NS = fresh()
    local D = NS.InsightsData
    local all = F.history(NS)
    local view = { character = F.charKey(NS, "lan"), spec = 63 }
    local f = D.Normalize(all, view, F.NOW, "spec")
    assertEqual(f.spec, 63, "kept: the dropdown just changed")
    assertEqual(f.character, "all", "Lanfear fought no Fire")
    assertEqual(view.character, F.charKey(NS, "lan"), "the view handed in is never written")
    f = D.Normalize(all, view, F.NOW, "character")
    assertEqual(f.character, F.charKey(NS, "lan"))
    assertEqual(f.spec, "all")
    if forever() then return end
    f = D.Normalize(all, { kind = "races", length = 300 }, F.NOW)
    assertEqual(f.length, "all", "no 5:00 race")
    assertEqual(f.kind, "races")
end)

-- ── the stats pass ──────────────────────────────────────────────────────────────────────────────

test("insights: Compute on no fights returns zero cards and empty sections", function()
    local NS = fresh()
    local s = NS.InsightsData.Compute({})
    local t = s.totals
    assertEqual(t.count, 0)
    assertEqual(t.time, 0)
    assertEqual(t.newBests, 0)
    assertNil(t.best)
    assertNil(t.avgPct)
    assertEqual(#s.progression, 0)
    assertEqual(#s.boardTabs, 0)
    assertEqual(#s.byChar, 0)
    assertEqual(#s.byDay, 0)
    assertEqual(#s.tail, 0, "no tail with no race")
    assertEqual(#s.lateBySpell.counted, 0)
end)

test("insights: the general sections run on all fights", function()
    local NS = fresh()
    local D = NS.InsightsData
    local all = F.history(NS)
    local s = D.Compute(D.Filter(all, nil, F.NOW))
    local t = s.totals
    local n = forever() and 7 or 6
    assertEqual(t.count, n, "fights and races alike")
    assertEqual(t.races, forever() and 4 or 3)
    assertEqual(t.time, 360 + 420 + (forever() and 41 or 0), "three fights' lengths and the races' time raced")
    assertEqual(t.chars, 2)
    assertEqual(t.specs, 2)
    assertEqual(t.activeDays, forever() and 4 or 3)
    assertEqual(t.newBests, 2, "one on the raid boss board, one on the Cleave 3:00 race board")
    assertEqual(#s.progression, 6, "every fight with a DPS figure; an incomplete race holds none")
    assertEqual(s.progression[1].record.id, "f1", "in date order")
    assertEqual(#s.byChar, 2)
    assertEqual(s.byChar[1].name, "Tush", "most fights first")
    assertEqual(s.byChar[1].n, forever() and 5 or 4)
    assertEqual(s.byCharContent.keys[1], "raid", "Identity's content order")
    assertEqual(table.concat(s.byCharContent.keys, ","), "raid,dungeon,dummy")
end)

test("insights: a race contributes its race DPS, never its fight's", function()
    local NS = fresh()
    local D = NS.InsightsData
    local r2 = F.history(NS)[4]
    assertEqual(r2.id, "r2")
    assertTrue(r2.dps ~= 1600, "the fight around it has its own DPS")
    local s = D.Compute({ r2 })
    assertEqual(s.totals.best.dps, 1600, "score over the race length")
    assertEqual(s.progression[1].dps, 1600)
    assertEqual(s.totals.avgDps, 1600, "one board: the raw average")
    assertEqual(s.totals.oneBoard, NS.Bests.Key(r2), "its race board")
end)

test("insights: mixed boards compare by percent of each board's best", function()
    local NS = fresh()
    local D = NS.InsightsData
    local s = D.Compute(D.Filter(F.history(NS), { includeIncomplete = false }, F.NOW))
    local t = s.totals
    assertNil(t.oneBoard, "four boards")
    local pct = {}
    for _, e in ipairs(s.progression) do pct[e.record.id] = e.pct end
    assertTrue(near(pct.f1, 1000 / 1200), "f1 against its board's 1200")
    assertTrue(near(pct.r1, 1500 / 1600), "r1 against its race board's 1600")
    assertTrue(near(pct.f2, 1) and near(pct.r2, 1) and near(pct.f3, 1) and near(pct.r3, 1), "each board's best at 100%")
    assertTrue(near(t.avgPct, (1000 / 1200 + 1500 / 1600 + 4) / 6), "the average share")
    assertEqual(t.best.record.id, "r2", "the peak DPS")
end)

test("insights: board tabs, the races' kind x length first in the catalog's order, then the fight boards", function()
    local NS = fresh()
    local D = NS.InsightsData
    local s = D.Compute(D.Filter(F.history(NS), nil, F.NOW))
    local keys = {}
    for i, tab in ipairs(s.boardTabs) do keys[i] = tab.key end
    assertEqual(table.concat(keys, " "), "race:cleave|180 race:boss|60 fight:e:1111:15 fight:e:2222:8")
    local cleave = s.boardTabs[1]
    assertEqual(cleave.label, "Cleave \194\183 3:00")
    assertEqual(cleave.n, 2)
    assertEqual(#cleave.specs, 1)
    assertEqual(cleave.specs[1].best, 1600)
    assertEqual(cleave.specs[1].name, "Tush")
    assertEqual(#cleave.consistency, 0, "two fights: under the three Consistency needs")
    assertEqual(s.boardTabs[3].label, "Grobbulus \194\183 Heroic")
    -- Scope keeps a tab's fights, or all of them.
    local filtered = D.Filter(F.history(NS), nil, F.NOW)
    assertEqual(#D.Scope(filtered, D.OVERALL), #filtered)
    assertEqual(F.ids(D.Scope(filtered, "race:cleave|180")), "r1,r2")
    assertEqual(F.ids(D.Scope(filtered, "fight:e:1111:15")), "f1,f2")
end)

test("insights: new bests beat an earlier best on their board, in date order; a board's first never counts", function()
    local NS = fresh()
    local D = NS.InsightsData
    local s = D.Compute(D.Filter(F.history(NS), nil, F.NOW))
    assertEqual(#s.newBests, 2)
    local a, b = s.newBests[1], s.newBests[2]
    assertEqual(a.record.id, "f2")
    assertEqual(a.prev.id, "f1")
    assertTrue(near(a.gain, 20), "+20%")
    assertEqual(b.record.id, "r2")
    assertEqual(b.prevDps, 1500)
    assertTrue(near(b.gain, (1600 / 1500 - 1) * 100))
end)

test("insights: counts by character, dummy kind, race length and day, gap days included", function()
    local NS = fresh()
    local D = NS.InsightsData
    local all = F.history(NS)
    all[#all + 1] = F.fight(NS, { id = "old", t = F.NOW - 6 * F.DAY })
    local s = D.Compute(D.Filter(all, { includeIncomplete = true }, F.NOW))
    assertEqual(#s.byDay, 7, "six days ago to today")
    assertEqual(s.byDay[1].n, 1)
    assertEqual(s.byDay[2].n, 0, "a gap day")
    assertEqual(s.byDay[7].n, 1, "today: the incomplete race")
    local tush = s.byChar[1]
    assertEqual(tush.name, "Tush")
    assertEqual(tush.byCategory.cleave, 3)
    assertEqual(tush.byLength[180], 2)
    assertEqual(tush.byLength[60], 1)
    assertEqual(table.concat(s.byCharTarget.keys, ","), "cleave,boss", "the catalog's order")
    assertEqual(table.concat(s.byCharLength.keys, ","), "60,180", "shortest first")
end)

test("insights: Compute buckets the damage tail, the 25 s outlier in 20+", function()
    local NS = fresh()
    local D = NS.InsightsData
    local s = D.Compute(D.Filter(F.history(NS), nil, F.NOW))
    assertEqual(#s.tail, 5)
    assertEqual(s.tail[1].n, 1, "r2's 4 s")
    assertEqual(s.tail[2].n, 1, "r1's 9.2 s")
    assertEqual(s.tail[5].n, 1, "r3's 25 s")
    assertEqual(s.tail[5].lo, 20)
    assertNil(s.tail[5].hi, "open-ended")
end)

test("insights: Compute lists late casts by spell, ignored apart, a sealed one as Unknown", function()
    local NS = fresh()
    local D = NS.InsightsData
    local all = F.history(NS)
    all[#all + 1] = F.race(NS, { id = "sealed", flags = { lateCasts = { { t = 2.0 }, { t = 2.5, spellID = 29722 } } } })
    local s = D.Compute(D.Filter(all, nil, F.NOW))
    local counted, ignored = s.lateBySpell.counted, s.lateBySpell.ignored
    assertEqual(counted[1].id, 29722, "most casts first")
    assertEqual(counted[1].count, 2)
    local unknown = counted[#counted]
    assertTrue(unknown.unknown, "a cast with no spell ID, after the named ones of its count")
    assertNil(unknown.id)
    assertEqual(#ignored, 1)
    assertEqual(ignored[1].id, 5384, "the stock list's Feign Death")
end)

test("insights: on WoW Forever there is no Races filter and no race-only section", function()
    local NS = fresh()
    local D = NS.InsightsData
    local onRetail = not forever()
    assertEqual(D.UnderRaces({ kind = "races" }), onRetail, "the race-only sections' gate")
    assertEqual(D.RaceChecks({ kind = "all" }), onRetail, "Clean only and Include incomplete")
    assertFalse(D.RaceChecks({ kind = "fights" }), "no race check over fights only")
    assertEqual(D.Options(F.history(NS), { kind = "races" }, F.NOW).length ~= nil, onRetail)
end)
