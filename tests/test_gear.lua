-- tests/test_gear.lua — the gear view (plan Task 4.4, spec §7, mockup §8): the stored item strings
-- parsed for their enchant and gems, the slots that changed against the compared fight, the marks
-- and the notes; and the window: opened from the detail's View gear button over the Results window
-- under its cover, the character panel's layout, the stats against the compared fight, and closing
-- with the Results window.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local NOW = os.time()

local function fresh()
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        m.StaticPopup_Show = function() end
        m.StaticPopup_Hide = function() end
    end }
    return inst.NS, inst.mocks
end

--- The record's gear set key: `o.gear` stored as a set, unless the record carries it inline.
local function gearSetOf(NS, o)
    if o.inline or type(o.gear) ~= "table" then return nil end
    return NS.Loadouts.StoreGear(o.gear)
end

local n = 0
--- A stored-shape record on the logged-in character, on one boss board. `o`: id, dps, gear, stats.
local function rec(NS, o)
    n = n + 1
    local me = NS.Identity.Who()
    local who = { name = me.name, realm = me.realm, client = me.client, class = me.class or "HUNTER",
                  specID = me.specID, specName = me.specName, ilvl = 721.4 }
    local ident = { content = "raid", targetName = "Vorasius", encounterID = 3176, encounterName = "Vorasius",
                    instanceName = "The Voidspire", difficultyID = 15, difficultyName = "Heroic", isBoss = true }
    local dps = o.dps or 1000
    return {
        schema = 1, id = o.id, t = NOW - n * 60, duration = 60, status = "final",
        who = who, identity = ident, boardKey = NS.Identity.BoardKey(ident),
        damage = { merged = dps * 60, player = dps * 60 }, dps = dps, meterDps = dps,
        build = "120105", version = "0.1.0", stats = o.stats,
        -- The gear as the recorder stores it, a set by key (v0.2 plan Task A3); `inline` = a sample's.
        gear = o.inline and o.gear or nil, gearSet = gearSetOf(NS, o),
        spells = NS.CastCodec.EncodeSpells({ { spellID = 34026, total = dps * 60, isPet = false } }),
    }
end

local function save(NS, ...)
    for _, r in ipairs({ ... }) do assertTrue(NS.Recorder.Save(r), "saved " .. tostring(r.id)) end
end

-- This fight's gear and the best's: the head's enchant moved, ring 2's gem, trinket 1 is another
-- item, the off hand was empty before, the rest alike.
local GEAR = { [1] = "212002:7000", [2] = "212010", [12] = "212020::213001", [13] = "212030", [16] = "212040",
               [17] = "212050" }
local BEST = { [1] = "212002:7001", [2] = "212010", [12] = "212020::213002", [13] = "212031", [16] = "212040" }

-- ── pure ────────────────────────────────────────────────────────────────────────────────────────

test("gear: the stored item strings parsed for their enchant and gems", function()
    local G = fresh().ResultsGear
    local p = G.ParseItem("212020:7000:213001:213002")
    assertEqual(p.itemID, 212020)
    assertEqual(p.enchantID, 7000)
    assertEqual(table.concat(p.gems, ","), "213001,213002")
    p = G.ParseItem("item:212020::213001")
    assertEqual(p.itemID, 212020)
    assertNil(p.enchantID, "no enchant")
    assertEqual(#p.gems, 1)
    assertEqual(G.ParseItem("|cffa335ee|Hitem:212030::::::::80|h[Trinket]|h|r").itemID, 212030, "a full link")
    assertNil(G.ParseItem(nil))
    assertNil(G.ParseItem("not an item"))
end)

test("gear: gear changed slots detected", function()
    local NS = fresh()
    local G = NS.ResultsGear
    local a, b = rec(NS, { id = "a", gear = GEAR }), rec(NS, { id = "b", gear = BEST })
    local changed = G.ChangedSlots(a, b)
    local slots = {}
    for i, c in ipairs(changed) do slots[i] = c.slot end
    -- The character frame's order: head, then the ring, the trinket, then the off hand.
    assertEqual(table.concat(slots, ","), "1,12,13,17")
    assertTrue(changed[1].diff.enchant, "the head's enchant")
    assertFalse(changed[1].diff.item)
    assertTrue(changed[2].diff.gems, "ring 2's gem")
    assertTrue(changed[3].diff.item, "trinket 1 is another item")
    assertTrue(changed[4].diff.item, "the off hand was empty before")
    assertNil(changed[4].otherItem)
    -- The item levels, when given, mark up or down.
    local levels = { ["212030"] = 727, ["212031"] = 714 }
    changed = G.ChangedSlots(a, b, function(item) return levels[item] end)
    assertEqual(changed[3].diff.ilvl, 1, "higher than the best's")
    -- The words of the compare's gear line.
    local Cmp = NS.ResultsCompare
    assertEqual(Cmp.GearText(changed[3], 727, 714), "Trinket 1 \194\183 714 \194\187 727")
    assertEqual(Cmp.GearText(changed[2]), "Ring 2 \194\183 gem differs")
    assertEqual(Cmp.GearText(changed[4]), "Off hand \194\183 nothing worn before")
    -- An upgraded item (the same item ID, another item level) is changed gear once the levels are
    -- known, and the gear line says the levels.
    local up = rec(NS, { id = "up", gear = { [14] = "212060:::::::::::1:200" } })
    local before = rec(NS, { id = "before", gear = { [14] = "212060:::::::::::1:100" } })
    local upLevels = { ["212060:::::::::::1:200"] = 727, ["212060:::::::::::1:100"] = 714 }
    assertEqual(#G.ChangedSlots(up, before), 0, "no levels: the same item, nothing marked")
    local upgraded = G.ChangedSlots(up, before, function(item) return upLevels[item] end)
    assertEqual(#upgraded, 1, "the upgrade is a change")
    assertEqual(upgraded[1].slot, 14)
    assertFalse(upgraded[1].diff.item)
    assertEqual(upgraded[1].diff.ilvl, 1)
    assertEqual(Cmp.GearText(upgraded[1], 727, 714), "Trinket 2 \194\183 714 \194\187 727")
    -- Either fight without gear: nothing to mark.
    assertEqual(#G.ChangedSlots(a, rec(NS, { id = "c" })), 0)
    -- The marks and the notes.
    local marks = G.Marks(G.ParseItem("212002"), { enchant = true, gems = false })
    assertEqual(#marks, 1)
    assertTrue(marks[1].missing, "the enchant the best had, missing here")
    local notes = G.NoteLines({ item = true, ilvl = -1 }, "Best", "Old Trinket")
    assertEqual(notes[1], "Changed: Best wore Old Trinket.")
    assertEqual(notes[2], "Lower item level than Best's.")
end)

test("gear: a stored gear set and a sample's inline gear read alike through Loadouts.GearOf", function()
    local NS = fresh()
    local G = NS.ResultsGear
    local a, b = rec(NS, { id = "a", gear = GEAR }), rec(NS, { id = "b", gear = BEST })
    assertNil(a.gear, "the set, not the items, rides the record")
    assertTrue(a.gearSet ~= nil and a.gearSet ~= b.gearSet)
    local inlineA, inlineB = rec(NS, { id = "ia", gear = GEAR, inline = true }), rec(NS, { id = "ib", gear = BEST, inline = true })
    assertNil(inlineA.gearSet)
    local function slots(list)
        local out = {}
        for i, c in ipairs(list) do out[i] = c.slot end
        return table.concat(out, ",")
    end
    assertEqual(slots(G.ChangedSlots(a, b)), "1,12,13,17")
    assertEqual(slots(G.ChangedSlots(inlineA, inlineB)), "1,12,13,17", "the inline fallback")
    assertEqual(slots(G.ChangedSlots(a, inlineB)), "1,12,13,17", "one of each")
    -- The same set on both fights: nothing changed, and no slot walked.
    local same = rec(NS, { id = "same", gear = GEAR })
    assertEqual(same.gearSet, a.gearSet, "the same gear interns once")
    assertEqual(#G.ChangedSlots(a, same, function() error("not asked") end), 0)
    -- The row's gear (the character frame's order) through the set.
    local order = NS.ResultsLoadout.Order(a)
    assertEqual(order[1].slot, 1)
    assertEqual(order[1].item, "212002:7000")
    assertEqual(#NS.ResultsLoadout.Order(inlineA), #order)
    assertNil(NS.ResultsLoadout.Order(rec(NS, { id = "bare" })))
end)

test("gear: the character panel's layout and its size", function()
    local G = fresh().ResultsGear
    local cells = G.Cells(GEAR)
    local by = {}
    for _, c in ipairs(cells) do by[c.slot] = c end
    assertEqual(by[1].side, "left")
    assertEqual(by[10].side, "right")
    assertNil(by[4], "no shirt: the optional slot is left out")
    assertNil(by[18], "no ranged item")
    assertEqual(by[16].y, by[17].y, "the weapons side by side")
    local w, h, rows = G.Size(GEAR)
    assertEqual(rows, 8, "the right column's eight slots")
    assertEqual(w, 2 * G.PAD + 2 * G.SLOT_W + G.MID_W + 2 * G.COL_GAP)
    assertTrue(h > rows * G.PITCH)
    local x, y = G.CenterOver("CENTER", 10, 20, 900, 500, 700, 400)
    assertEqual(x, 10)
    assertEqual(y, 20)
    x, y = G.CenterOver("TOPLEFT", 0, 0, 900, 500, 700, 400)
    assertEqual(x, 100)
    assertEqual(y, -50)
end)

-- ── the window ──────────────────────────────────────────────────────────────────────────────────

test("gear: the window opens from the detail, marks the changes and closes with the Results window", function()
    local NS, M = fresh()
    save(NS, rec(NS, { id = "best", dps = 3000, gear = BEST,
                       stats = { v = 1, primaryStat = 2, primary = 60000, crit = 21, critRating = 6000 } }),
        rec(NS, { id = "this", dps = 2000, gear = GEAR,
                  stats = { v = 1, primaryStat = 2, primary = 61000, crit = 21.6, critRating = 6120 } }),
        rec(NS, { id = "bare", dps = 100 }))
    assertTrue(NS.Results.ShowFight("this"))
    local pane = NS.Results.__ui().detail
    assertTrue(pane.lo.gearView:IsEnabled(), "View gear for a fight with gear")
    pane.lo.gearView:__fire("OnClick")
    local ui = NS.ResultsGear.__ui()
    assertTrue(NS.ResultsGear.IsShown())
    assertEqual(ui.frame:GetFrameStrata(), NS.Constants.LAYERS.STRATA.MODAL)
    assertTrue(NS.Results.IsCovered())
    local special = false
    for _, name in ipairs(M.UISpecialFrames) do if name == "CombatTrailGear" then special = true end end
    assertTrue(special, "Escape closes it")
    local cells = NS.ResultsGear.SlotCells()
    assertTrue(cells[13].changed, "trinket 1 washed: another item")
    assertTrue(cells[17].changed, "the off hand: empty before")
    assertFalse(cells[1].changed, "the head: the same item")
    assertTrue(cells[1].marks[1].mark.changed, "its enchant mark edged: the enchant differs")
    assertFalse(cells[2].changed)
    assertEqual(cells[3].name:GetText(), "Empty", "the shoulders: nothing worn")
    assertTrue(ui.legendB:GetText():find("Best", 1, true) ~= nil, "against the best")
    -- The stats against the best's: Agility up, crit up.
    local primary, crit
    for _, row in ipairs(ui.statRows) do
        if row.key == "primary" then primary = row end
        if row.key == "crit" then crit = row end
    end
    assertEqual(primary.label:GetText(), "Agility")
    assertEqual(primary.delta:GetText(), "+1,000")
    assertTrue(crit.delta:GetText():find("+0.60%", 1, true) ~= nil, crit.delta:GetText())
    assertFalse(ui.statsNote:IsShown())
    -- Closes with the Results window, and the cover goes.
    NS.Results.Hide()
    assertFalse(NS.ResultsGear.IsShown())
    assertFalse(NS.Results.IsCovered())
    -- A fight with no gear has the button off.
    NS.Results.ShowFight("bare")
    assertFalse(NS.Results.__ui().detail.lo.gearView:IsEnabled())
end)

test("gear: a stand-down refuses the open, a deleted fight closes it", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "best", dps = 3000, gear = BEST }), rec(NS, { id = "this", dps = 2000, gear = GEAR }))
    NS.Results.ShowFight("this")
    local pane = NS.Results.__ui().detail
    assertTrue(NS.ResultsGear.Open(pane))
    NS.Results.DeleteFight("this")
    assertFalse(NS.ResultsGear.IsShown(), "its fight went: the view closes")
    local saved = NS.IsStoodDown
    NS.IsStoodDown = function() return true end
    assertFalse(NS.ResultsGear.Open(pane))
    NS.IsStoodDown = saved
end)
