-- tests/test_usage_edit.lua — the Usage edit (plan Task 4.4, spec §7): the player's ticks replacing a
-- fight's used list (a detected entry keeping its times, a new tick "manual"), the edit's rows (every
-- candidate, what was used ticked), the ticks carried across a redraw mid-edit, the "never show" list
-- (stored whole through the schema seam, hiding an item everywhere the usage is shown while the record
-- keeps it), and a sample fight changing in memory only.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local NOW = os.time()
local TRINKET, POTION, FLASK = 212264, 212265, 212266

local function fresh()
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        m.StaticPopup_Show = function() end
        m.StaticPopup_Hide = function() end
    end }
    return inst.NS, inst.mocks
end

local n = 0
--- A stored-shape record with a usage record: the trinket used at 0:01, food on at the pull; the
--- potion and the flask candidates nobody used.
local function rec(NS, id)
    n = n + 1
    local me = NS.Identity.Who()
    local who = { name = me.name, realm = me.realm, client = me.client, class = me.class or "HUNTER",
                  specID = me.specID, specName = me.specName, ilvl = 721.4 }
    local ident = { content = "raid", targetName = "Vorasius", encounterID = 3176, encounterName = "Vorasius",
                    instanceName = "The Voidspire", difficultyID = 15, difficultyName = "Heroic", isBoss = true }
    return {
        schema = 1, id = id, t = NOW - n * 60, duration = 60, status = "final",
        who = who, identity = ident, boardKey = NS.Identity.BoardKey(ident),
        damage = { merged = 60000, player = 60000 }, dps = 1000, meterDps = 1000,
        build = "120105", version = "0.1.0",
        spells = NS.CastCodec.EncodeSpells({ { spellID = 34026, total = 60000, isPet = false } }),
        usage = { v = 1, edited = false,
                  candidates = { { itemID = TRINKET, kind = "gear", slot = 13 }, { itemID = POTION, kind = "potion" },
                                 { itemID = FLASK, kind = "flask" } },
                  used = { { itemID = TRINKET, kind = "gear", slot = 13, times = { 1 }, n = 1, src = "cast" },
                           { kind = "food", n = 1, src = "buff" } } },
    }
end

local function detailOn(NS, id)
    assertTrue(NS.Results.ShowFight(id))
    return NS.Results.__ui().detail
end

-- The edit's row for `itemID` (or the food row with nil): its index and its frame.
local function rowFor(pane, itemID)
    for i, data in ipairs(pane.usage.rows) do
        if data.itemID == itemID then return i, pane.usage.items[i] end
    end
    return nil
end

test("usage edit: the pure rows, ticks and saves", function()
    local NS = fresh()
    local U, RU = NS.Usage, NS.ResultsUsage
    local r = rec(NS, "a")
    local rows = RU.Rows(r)
    assertEqual(#rows, 4, "three candidates and the food no candidate stands for")
    assertEqual(rows[1].itemID, TRINKET)
    assertTrue(rows[1].entry ~= nil, "the trinket was used")
    assertNil(rows[2].entry, "the potion was not")
    assertEqual(rows[4].kind, "food")
    local state = RU.Carry(rows)
    assertTrue(state[1] and state[4] and not state[2], "ticked as used")
    assertFalse(RU.Changed(rows, state))
    state[2] = true
    state[4] = nil
    assertTrue(RU.Changed(rows, state))
    assertTrue(U.SetUsed(r, RU.Edits(r, rows, state)))
    assertTrue(r.usage.edited, "marked edited")
    assertEqual(#r.usage.used, 2)
    assertEqual(r.usage.used[1].src, "cast", "the trinket kept its detection")
    assertEqual(r.usage.used[1].times[1], 1, "and its time")
    assertEqual(r.usage.used[2].itemID, POTION)
    assertEqual(r.usage.used[2].src, "manual", "a new tick: manual, once, no time")
    assertEqual(RU.Detail(r.usage.used[2]), "time unknown")
    -- The unticked food keeps its row as a candidate, so it can be ticked again.
    local again = RU.Rows(r)
    local foodRow
    for _, row in ipairs(again) do if row.kind == "food" then foodRow = row end end
    assertTrue(foodRow ~= nil, "the food row stays")
    assertNil(foodRow.entry)
    assertFalse(U.SetUsed({}, {}), "no usage record: nothing stored")
    -- A tick of a kind the record does not know is stored as "other".
    U.SetUsed(r, { { itemID = 7, kind = "rocket" } })
    assertEqual(r.usage.used[1].kind, "other")
end)

test("usage edit: save persists", function()
    local NS = fresh()
    assertTrue(NS.Recorder.Save(rec(NS, "a")))
    local changed = 0
    local bus = NS.NewBusTarget()
    bus:RegisterMessage(NS.MSG.FIGHTS_CHANGED, function() changed = changed + 1 end)
    local pane = detailOn(NS, "a")
    local x = pane.usage
    assertTrue(x.edit:IsEnabled(), "Edit is live for a fight with a usage record")
    assertEqual(#x.rows, 2, "outside the edit: the used entries")
    assertFalse(x.save:IsShown(), "Save only in the edit")
    x.edit:__fire("OnClick")
    assertTrue(x.editing)
    assertEqual(#x.rows, 4, "in the edit: every candidate")
    assertTrue(x.save:IsShown())
    assertFalse(x.save:IsEnabled(), "nothing changed yet")
    local i, row = rowFor(pane, POTION)
    assertTrue(row.check:IsShown(), "a check box per row")
    assertNil(x.state[i], "not ticked: the potion was not used")
    row.check:__fire("OnClick")
    assertTrue(x.state[i], "ticked")
    assertTrue(x.save:IsEnabled(), "Save is live once the ticks differ")
    -- A redraw of the same fight mid-edit (another fight saved) keeps the tick not saved yet.
    assertTrue(NS.Recorder.Save(rec(NS, "b")))
    assertTrue(x.editing, "still editing")
    i = rowFor(pane, POTION)
    assertTrue(x.state[i], "the tick was carried")
    x.save:__fire("OnClick")
    assertFalse(x.editing, "the save left the edit")
    assertTrue(changed >= 1, "FIGHTS_CHANGED")
    local stored = NS.Recorder.Get("a").usage
    assertTrue(stored.edited)
    assertEqual(#stored.used, 3, "the trinket, the potion and the food")
    assertEqual(#x.rows, 3, "the section shows the new list")
    -- Edit then Cancel leaves it unsaved.
    x.edit:__fire("OnClick")
    local _, flask = rowFor(pane, FLASK)
    row = flask
    row.check:__fire("OnClick")
    x.edit:__fire("OnClick")
    assertFalse(x.editing)
    assertEqual(#NS.Recorder.Get("a").usage.used, 3, "nothing saved")
end)

test("usage edit: never-show list hides", function()
    local NS = fresh()
    local U, RU = NS.Usage, NS.ResultsUsage
    assertTrue(NS.Recorder.Save(rec(NS, "a")))
    assertEqual(table.concat(U.ParseHidden(" 5, 3,5 "), ","), "3,5", "ascending, each once")
    assertNil(U.ParseHidden("3,x"), "anything but IDs is refused")
    assertEqual(U.NormalizeHidden("9, 2"), "2,9")
    local pane = detailOn(NS, "a")
    -- In the edit, an item row's right-click offers Never show.
    pane.usage.edit:__fire("OnClick")
    local _, potion = rowFor(pane, POTION)
    potion.check:__fire("OnClick")
    local items
    local saved = NS.OpenMenu
    NS.OpenMenu = function(_, fill)
        items = {}
        fill({ CreateButton = function(_, text, onClick) items[#items + 1] = { label = text, onClick = onClick } end })
    end
    local _, trinketRow = rowFor(pane, TRINKET)
    assertTrue(RU.RowMenu(pane, trinketRow))
    NS.OpenMenu = saved
    assertTrue(items[1].label:find("Never show", 1, true) == 1, items[1].label)
    items[1].onClick()
    assertTrue(U.HiddenSet()[TRINKET], "hidden")
    assertEqual(NS.GetSetting(U.HIDDEN_PATH), tostring(TRINKET), "stored whole through the seam")
    assertEqual(NS.db.global.usage.hidden, tostring(TRINKET), "account-wide")
    -- The redraw kept the edit and its tick, and the trinket's row is gone.
    assertTrue(pane.usage.editing)
    assertNil(rowFor(pane, TRINKET), "the hidden item is not listed")
    local i = rowFor(pane, POTION)
    assertTrue(pane.usage.state[i], "the tick not saved yet was kept")
    -- A save keeps the hidden item the fight used in its record.
    pane.usage.save:__fire("OnClick")
    local stored = NS.Recorder.Get("a").usage
    local kept = false
    for _, e in ipairs(stored.used) do if e.itemID == TRINKET then kept = true end end
    assertTrue(kept, "the record keeps the hidden trinket")
    assertEqual(#RU.Entries(NS.Recorder.Get("a")), 2, "the section lists the potion and the food")
    -- Shown again: it is back.
    assertTrue(U.Unhide(TRINKET))
    assertEqual(#RU.Entries(NS.Recorder.Get("a")), 3)
    assertFalse(U.Unhide(TRINKET), "not hidden any more")
    assertFalse(U.Hide(0), "no such item")
    local known = {}
    for _, id in ipairs(U.KnownItems()) do known[#known + 1] = id end
    table.sort(known)
    assertEqual(table.concat(known, ","), TRINKET .. "," .. POTION .. "," .. FLASK, "each item once")
end)

test("usage edit: a sample fight changes in memory only", function()
    local NS = fresh()
    local changed = 0
    local bus = NS.NewBusTarget()
    bus:RegisterMessage(NS.MSG.FIGHTS_CHANGED, function() changed = changed + 1 end)
    local sample = rec(NS, "sample")
    NS.ResultsSource.Use({ fights = { sample } })
    local pane = detailOn(NS, "sample")
    pane.usage.edit:__fire("OnClick")
    local _, row = rowFor(pane, FLASK)
    row.check:__fire("OnClick")
    pane.usage.save:__fire("OnClick")
    assertFalse(pane.usage.editing, "the sample's redraw left the edit")
    assertEqual(changed, 0, "no FIGHTS_CHANGED: nothing stored")
    assertEqual(#sample.usage.used, 3, "the sample changed in memory")
    assertNil(NS.Recorder.Get("sample"), "never written to the store")
    assertEqual(#pane.usage.rows, 3)
end)
