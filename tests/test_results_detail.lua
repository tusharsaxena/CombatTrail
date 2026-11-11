-- tests/test_results_detail.lua — the fight detail (plan Task 4.2, spec §7): the header line, the
-- Delta or "Leads by" box, the chart this session only (and the note when the session holds none),
-- the breakdown with the pet's spells tagged, Gear and Talents, Usage, the buttons and their seams,
-- the delete's confirmation, the collapsed and expanded views, the popups closing with the window,
-- and the step aside for the talent tree.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local NOW = os.time()

-- A fresh instance with the kit's paint recorder (a label's text reads back), whose StaticPopup_Show
-- and StaticPopup_Hide record what they were asked.
local function fresh(mutate)
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        m.__popups, m.__hidden = {}, {}
        m.StaticPopup_Show = function(name, _, _, data) m.__popups[#m.__popups + 1] = { name = name, data = data } end
        m.StaticPopup_Hide = function(name) m.__hidden[#m.__hidden + 1] = name end
        if mutate then mutate(m) end
    end }
    return inst.NS, inst.mocks
end

local n = 0
--- A stored-shape record on the logged-in character. `o` overrides: id, dps, pet (damage), spells
--- ({ { spellID, total, isPet } }), creatureID, note.
local function rec(NS, o)
    o = o or {}
    n = n + 1
    local me = NS.Identity.Who()
    local who = { name = me.name, realm = me.realm, client = me.client, class = me.class or "HUNTER",
                  specID = me.specID, specName = me.specName, ilvl = 721.4, petName = o.petName }
    local ident = { content = "raid", targetName = "Vorasius", encounterID = 3176, encounterName = "Vorasius",
                    instanceName = "The Voidspire", difficultyID = 15, difficultyName = "Heroic", isBoss = true,
                    targetCreatureID = o.creatureID }
    local dps = o.dps or 1000
    local merged = dps * 60
    local pet = o.pet or 0
    return {
        schema = 1, id = o.id or ("d-" .. n), t = NOW - n, duration = 60, status = "final",
        who = who, identity = ident, boardKey = NS.Identity.BoardKey(ident),
        damage = { merged = merged, player = merged - pet, pet = pet > 0 and pet or nil }, dps = dps,
        meterDps = dps - 10, build = "120105", version = "0.1.0", note = o.note,
        spells = NS.CastCodec.EncodeSpells(o.spells or { { spellID = 34026, total = merged, isPet = false } }),
    }
end

local function save(NS, ...)
    for _, r in ipairs({ ... }) do assertTrue(NS.Recorder.Save(r), "saved " .. tostring(r.id)) end
end

-- The window open on fight `id`, its detail pane.
local function detailOn(NS, id)
    assertTrue(NS.Results.ShowFight(id))
    local ui = NS.Results.__ui()
    assertTrue(ui ~= nil and ui.detail ~= nil, "the detail was built")
    return ui.detail, ui
end

-- ── the header and the figures ──────────────────────────────────────────────────────────────────

test("detail: the header meta is three lines: where and who, what, the stamp (plan A2)", function()
    local NS = fresh()
    local r = rec(NS, { id = "a", petName = "Grimfang" })
    r.who.realm = "Area 52"
    local lines = NS.ResultsDetail.Meta(r)
    assertEqual(#lines, 3, "where/who, what, stamp")
    local want = { { "Area 52", "ilvl 721.4", "The Voidspire" },
                   { "Vorasius", "Heroic", "1:00", "pet Grimfang" },
                   { NS.ResultsTable.Date(r.t, "%d %b %Y %H:%M"), "build 120105", "v0.1.0" } }
    for k, parts in ipairs(want) do
        for _, part in ipairs(parts) do
            assertTrue(lines[k]:find(part, 1, true) ~= nil, ("line %d has %s: %s"):format(k, part, lines[k]))
        end
    end
    assertTrue(lines[2]:find("Area 52", 1, true) == nil, "the realm is line 1's alone")
    save(NS, r)
    local pane = detailOn(NS, "a")
    for k = 1, 3 do assertEqual(pane.w.meta[k]:GetText(), lines[k], "meta line " .. k) end
    assertEqual(pane.w.name:GetText(), r.who.name)
    assertEqual(pane.w.damage.value:GetText(), NS.Format.Number(60000))
    assertEqual(pane.w.dps.value:GetText(), NS.Format.Number(1000))
    assertEqual(pane.w.meterDps.value:GetText(), NS.Format.Number(990))
end)

test("detail: an open-world fight names its zone, not the continent, and the target's level", function()
    local NS = fresh()
    local r = rec(NS, { id = "w" })
    r.identity = { content = "world", targetName = "Ravenous Boar", targetCreatureID = 1985, targetLevel = 72,
                   instanceType = "none", instanceName = "Eastern Kingdoms", zone = "Burning Steppes",
                   subzone = "Flame Crest", difficultyID = 0 }
    r.boardKey = NS.Identity.BoardKey(r.identity)
    local lines = NS.ResultsDetail.Meta(r)
    assertTrue(lines[1]:find("Burning Steppes, Flame Crest", 1, true) ~= nil, "the zone and subzone: " .. lines[1])
    for k = 1, 3 do
        assertTrue(lines[k]:find("Eastern Kingdoms", 1, true) == nil, "never the continent: " .. lines[k])
    end
    assertTrue(lines[2]:find("Ravenous Boar", 1, true) ~= nil, lines[2])
    assertTrue(lines[2]:find(NS.L["level %s"]:format("72"), 1, true) ~= nil, "the target's level: " .. lines[2])
    r.identity.targetLevel = -1
    assertTrue(NS.ResultsDetail.Meta(r)[2]:find(NS.L["level %s"]:format("??"), 1, true) ~= nil, "a skull level")
    r.identity.zone, r.identity.subzone = nil, nil
    assertTrue(NS.ResultsDetail.Meta(r)[1]:find("Eastern Kingdoms", 1, true) == nil,
               "an old record with no zone omits the place rather than name the continent")
end)

test("detail: shows Leads by on best", function()
    local NS = fresh()
    local best, other = rec(NS, { id = "best", dps = 2000 }), rec(NS, { id = "other", dps = 1000 })
    save(NS, best, other)
    local pane = detailOn(NS, "best")
    assertEqual(pane.w.deltaBox.label:GetText(), "Leads by")
    assertEqual(pane.w.deltaBox.value:GetText(), "+100.0%")
    assertTrue(pane.w.best:IsShown(), "the personal best's trophy chip")
    pane = detailOn(NS, "other")
    assertEqual(pane.w.deltaBox.label:GetText(), "Delta")
    assertEqual(pane.w.deltaBox.value:GetText(), "-50.0%")
    assertFalse(pane.w.best:IsShown(), "no chip on a fight that holds no best")
    -- Alone in its group: the leader with no runner-up reads a dash.
    local label, text, _, leads = NS.ResultsDetail.DeltaBox(best, NS.ResultsFights.Context({ best }))
    assertEqual(label, "Leads by")
    assertEqual(text, "\226\128\148")
    assertTrue(leads)
end)

test("detail: a fight the filters leave out falls back to its board", function()
    local NS = fresh()
    local a, b = rec(NS, { id = "a", dps = 1500 }), rec(NS, { id = "b", dps = 1000 })
    a.t, b.t = NOW - 40 * 86400, NOW - 41 * 86400
    save(NS, a, b)
    local pane, ui = detailOn(NS, "b")
    assertNil(ui.list:DeltaContext(b), "older than the 7 days on screen")
    assertEqual(pane.w.deltaBox.value:GetText(), NS.Format.SignedPct((1000 / 1500 - 1) * 100))
    assertTrue(pane:Record() == b, "the detail shows the fight the view filters out")
end)

-- ── the chart ───────────────────────────────────────────────────────────────────────────────────

test("detail: a fight with no chart this session has no Damage profile section", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "old" }), rec(NS, { id = "now" }))
    local pane = detailOn(NS, "old")
    assertFalse(pane.w.chartTitle:IsShown(), "no heading")
    assertFalse(pane.heads.chart:IsShown(), "no fold arrow")
    assertFalse(pane.w.chartHover:IsShown(), "no hover")
    assertFalse(pane.w.chart.plot:IsShown(), "no chart")
    assertEqual(pane.w.chartNote, nil, "no session-only note")
    NS.Slices.Seed("now", { step = 2, values = { 2000, 4000, 6000 }, pet = {}, count = 3, filled = 3 })
    pane = detailOn(NS, "now")
    assertTrue(pane.w.chartTitle:IsShown(), "the heading with the session's slices")
    assertTrue(pane.w.chart.plot:IsShown(), "the chart")
    assertEqual(pane.w.chartCaption:GetText(), "this session only")
    assertTrue(#pane.w.chart:Columns() > 0, "its columns drawn")
end)

-- ── the breakdown ───────────────────────────────────────────────────────────────────────────────

test("detail: pet spells tagged", function()
    local NS = fresh()
    local r = rec(NS, { id = "a", pet = 24000, spells = {
        { spellID = 34026, total = 36000, isPet = false }, { spellID = 17253, total = 24000, isPet = true } } })
    save(NS, r)
    local pane = detailOn(NS, "a")
    local rows = pane.w.list:Rows()
    assertEqual(#rows, 2)
    assertFalse(rows[1].isPet)
    assertFalse(rows[1].paw:IsShown(), "no paw on the player's spell")
    assertTrue(rows[2].isPet, "the pet's spell")
    assertTrue(rows[2].paw:IsShown(), "the paw on the pet's spell")
    assertEqual(rows[1].pct:GetText(), "60.0%")
    assertEqual(rows[2].pct:GetText(), "40.0%")
    assertEqual(pane.w.petShare:GetText(), "Pet 40.0%")
    assertEqual(NS.ResultsDetail.PetShare(rec(NS, {})), nil, "no pet damage, no share")
end)

-- ── gear, talents and usage ─────────────────────────────────────────────────────────────────────

test("detail: gear in the character frame's order, talents with View Talents and no Copy (C3)", function()
    local NS, M = fresh()
    local r = rec(NS, { id = "a" })
    r.gear = { [13] = "212001", [1] = "212002::::::::80", [16] = "212003" }
    r.loadout = NS.Loadouts.Store({ importString = "CQQAAAAAA", specID = 253, name = "Raid", heroName = "Pack Leader" })
    save(NS, r)
    local order = NS.ResultsLoadout.Order(r)
    assertEqual(order[1].slot, 1)
    assertEqual(order[2].slot, 13)
    assertEqual(order[3].slot, 16)
    local pane = detailOn(NS, "a")
    assertEqual(pane.lo.talents:GetText(), "Talents: Raid \194\183 Pack Leader", "Retail keeps the loadout's name")
    assertEqual(pane.lo.gearView.label:GetText(), "View gear")
    assertEqual(pane.lo.gearView.tip[1], "View gear")
    assertEqual(pane.lo.view.label:GetText(), "View Talents")
    assertEqual(pane.lo.view.tip[1], "View Talents")
    assertNil(pane.lo.copy, "no Copy button")
    assertNil(NS.ResultsLoadout.Copy, "and no Copy code")
    assertTrue(pane.lo.view:IsEnabled(), "View Talents with an import string")
    -- View opens the tree at the fight's level (the record's, here the mock character's 80).
    assertEqual(NS.Identity.Who().level, 80, "who records the character's level")
    local ref
    M.SetItemRef = function(data) ref = data end
    pane.lo.view:__fire("OnClick")
    M.SetItemRef = nil
    assertEqual(ref, "talentbuild:253:80:CQQAAAAAA", "View's link carries the level")
    assertTrue(pane.lo.gearView:IsEnabled(), "View gear for a fight with gear (plan Task 4.4)")
    local link = NS.ResultsLoadout.Hyperlink(NS.Loadouts.Get(r.loadout), 80, "Raid")
    assertTrue(link:find("|Htalentbuild:253:80:CQQAAAAAA|h[Raid]|h|r", 1, true) ~= nil, link)
    -- Nothing recorded.
    local bare = rec(NS, { id = "bare" })
    save(NS, bare)
    pane = detailOn(NS, "bare")
    assertTrue(pane.lo.none:IsShown(), "Gear not recorded")
    assertEqual(pane.lo.talents:GetText(), "Talents: Not recorded")
    assertFalse(pane.lo.view:IsEnabled())
end)

test("detail: forever: the talents line names the class and its points per tree (C3)", function()
    local NS, m = fresh(function(m) m.LOCALIZED_CLASS_NAMES_MALE = { HUNTER = "Hunter" } end)
    T.Loader.MockClient.apply(m, "forever")
    local Lo = NS.ResultsLoadout
    local t = { importString = "CQQAAAAAA", name = "Hunter" }
    assertEqual(Lo.TalentsText(t, { class = "HUNTER", trees = { 31, 20, 0 } }), "Hunter (31/20/0)")
    assertEqual(Lo.TalentsText(nil, { class = "HUNTER", trees = { 0, 41, 10 } }), "Hunter (0/41/10)",
        "the points with no loadout stored")
    assertEqual(Lo.TalentsText(t, { class = "HUNTER" }), "Hunter", "no trees: the loadout's name alone")
    assertEqual(Lo.TalentsText(nil, {}), "Not recorded")
    local r = rec(NS, { id = "tree" })
    r.who.class, r.who.trees = "HUNTER", { 31, 20, 0 }
    r.loadout = NS.Loadouts.Store(t)
    save(NS, r)
    local pane = detailOn(NS, "tree")
    assertEqual(pane.lo.talents:GetText(), "Talents: Hunter (31/20/0)")
    T.Loader.MockClient.apply(m)
end)

test("detail: usage rows, and Edit for a fight with a usage record", function()
    local NS = fresh()
    local U = NS.ResultsUsage
    assertEqual(U.Detail({ times = { 2, 65 }, n = 2 }), "x2 at 0:02, 1:05")
    assertEqual(U.Detail({ times = { -3 }, n = 1 }), "at -0:03")
    assertEqual(U.Detail({ src = "buff", n = 1 }), "active at the start")
    assertEqual(U.Detail({ src = "bag", n = 2 }), "x2, time unknown")
    local r = rec(NS, { id = "a" })
    r.usage = { v = 1, edited = false, candidates = {}, used = {
        { kind = "food", n = 1, src = "buff" },
        { itemID = 212264, kind = "gear", slot = 13, times = { 1 }, n = 1, src = "cast" } } }
    local empty = rec(NS, { id = "empty" })
    empty.usage = { v = 1, used = {}, candidates = {} }
    save(NS, r, empty, rec(NS, { id = "none" }))
    local entries = U.Entries(r)
    assertEqual(entries[1].kind, "gear", "the gear first")
    assertEqual(entries[2].kind, "food")
    local pane = detailOn(NS, "a")
    assertEqual(#pane.usage.rows, 2)
    assertTrue(pane.usage.items[2].check.label:GetText():find("Well Fed", 1, true) ~= nil)
    assertTrue(pane.usage.edit:IsEnabled(), "Edit is live (plan Task 4.4)")
    pane = detailOn(NS, "empty")
    assertEqual(pane.usage.none:GetText(), "Nothing used")
    pane = detailOn(NS, "none")
    assertEqual(pane.usage.none:GetText(), "Not recorded")
end)

-- ── the buttons ─────────────────────────────────────────────────────────────────────────────────

test("detail: the buttons and their seams", function()
    local NS, M = fresh()
    local r = rec(NS, { id = "a" })
    r.casts = "0:34026"
    save(NS, r)
    local pane = detailOn(NS, "a")
    assertTrue(pane.w.timeline:IsEnabled(), "Timeline is live for a fight with casts (plan Task 4.3)")
    assertFalse(pane.w.compare:IsEnabled(), "Compare is off with no other fight on the board (plan Task 4.4)")
    assertTrue(pane.w.share:IsEnabled(), "Share for a stored fight")
    assertEqual(pane.w.addNote.label:GetText(), "Add Note")
    pane.w.addNote:__fire("OnClick")
    assertEqual(M.__popups[#M.__popups].name, "COMBATTRAIL_FIGHT_NOTE")
    NS.Results.SetNote("a", "pulled early")
    assertEqual(pane.w.addNote.label:GetText(), "Edit Note", "FIGHTS_CHANGED redrew the detail")
    assertEqual(pane.w.note:GetText(), "pulled early")
    assertEqual(pane.w.noteTitle:IsShown(), true, "the note under its heading")
    -- A fight with no casts has it off.
    save(NS, rec(NS, { id = "bare" }))
    assertFalse(detailOn(NS, "bare").w.timeline:IsEnabled(), "no Timeline without casts")
    -- The button hands the timeline its pane.
    local opened
    NS.ResultsTimeline = { Open = function(p) opened = p end }
    pane = detailOn(NS, "a")
    assertTrue(pane.w.timeline:IsEnabled())
    pane.w.timeline:__fire("OnClick")
    assertTrue(opened == pane, "the timeline opens on the pane")
    -- A sample fight is never shared.
    NS.ResultsSource.Use({ fights = { rec(NS, { id = "sample" }) } })
    pane = detailOn(NS, "sample")
    assertFalse(pane.w.share:IsEnabled(), "no Share on a sample fight")
end)

test("detail: the footer in DPS Race's order: Add Note, Share, Timeline, Compare, Delete at the right (C3)", function()
    local placed = {}
    local NS = fresh(function(m)
        local create = m.CreateFrame
        m.CreateFrame = function(kind, ...)
            local f = create(kind, ...)
            if kind == "Button" then
                rawset(f, "SetPoint", function(self, ...) placed[self] = { ... } end)
                rawset(f, "SetSize", function(self, w, h) rawset(self, "__w", w); rawset(self, "__h", h) end)
            end
            return f
        end
    end)
    local D = NS.ResultsDetail
    local keys = {}
    for i, spec in ipairs(D.BUTTONS) do keys[i] = spec.key end
    assertEqual(table.concat(keys, ","), "addNote,share,timeline,compare")
    save(NS, rec(NS, { id = "a" }))
    local pane = detailOn(NS, "a")
    local w = pane.w
    local want = { { "addNote", "Add Note", 12, 84 }, { "share", "Share", 102, 84 },
                   { "timeline", "Timeline", 192, 72 }, { "compare", "Compare", 270, 70 } }
    for _, e in ipairs(want) do
        local b = w[e[1]]
        assertEqual(b.label:GetText(), e[2], e[1])
        assertEqual(b.styleName, "normal", e[1] .. " is a plain button (no primary Timeline)")
        local pt = placed[b]
        assertEqual(pt[1], "BOTTOMLEFT", e[1])
        assertEqual(pt[4], e[3], e[1] .. "'s x")
        assertEqual(pt[5], 8, e[1] .. "'s y")
        assertEqual(rawget(b, "__w"), e[4], e[1] .. "'s width")
        assertEqual(rawget(b, "__h"), D.BUTTON_H, e[1])
    end
    assertEqual(w.delete.label:GetText(), "Delete")
    assertEqual(w.delete.styleName, "danger")
    assertEqual(placed[w.delete][1], "BOTTOMRIGHT")
    assertEqual(placed[w.delete][4], -D.PADX)
    assertEqual(rawget(w.delete, "__w"), 78)
    -- Compare's right edge clears Delete's left on the 440 px pane.
    assertTrue(270 + 70 < NS.Results.DETAIL_WIDTH - D.PADX - 78, "Compare clears Delete")
end)

test("detail: delete asks to confirm, then FIGHTS_CHANGED", function()
    local NS, M = fresh()
    save(NS, rec(NS, { id = "a" }), rec(NS, { id = "b" }))
    local changed = 0
    local bus = NS.NewBusTarget()
    bus:RegisterMessage(NS.MSG.FIGHTS_CHANGED, function() changed = changed + 1 end)
    local pane = detailOn(NS, "a")
    pane.w.delete:__fire("OnClick")
    local popup = M.__popups[#M.__popups]
    assertEqual(popup.name, "COMBATTRAIL_DELETE_FIGHT")
    assertEqual(changed, 0, "nothing changes before the Accept")
    assertTrue(NS.Recorder.Get("a") ~= nil)
    M.StaticPopupDialogs.COMBATTRAIL_DELETE_FIGHT.OnAccept(nil, popup.data)
    assertEqual(changed, 1, "FIGHTS_CHANGED")
    assertNil(NS.Recorder.Get("a"), "deleted")
    assertNil(pane:Record(), "the detail clears to its prompt")
    assertTrue(pane.w.empty:IsShown())
    assertNil(NS.Results.Selected())
end)

-- ── the views ───────────────────────────────────────────────────────────────────────────────────

test("detail: collapsed puts the detail in the list's place; the fold arrow sets it beside", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "a" }))
    local R = NS.Results
    R.Show()
    local ui = R.__ui()
    assertEqual(R.View(), "collapsed", "the shipped view")
    assertFalse(ui.detail.frame:IsShown(), "the list alone")
    R.Select("a")
    assertTrue(R.DetailOpen())
    assertTrue(ui.detail.frame:IsShown(), "the detail in the list's place")
    assertFalse(ui.list.frame:IsShown())
    assertTrue(ui.detail.w.back:IsShown(), "with Back")
    ui.detail.w.back:__fire("OnClick")
    assertFalse(R.DetailOpen())
    assertTrue(ui.list.frame:IsShown(), "Back to the list")
    assertEqual(R.Selected(), "a", "still selected")
    local listWidth = NS.db.profile.results.window.width
    assertTrue(R.ToggleView())
    assertEqual(R.View(), "expanded")
    assertEqual(NS.db.profile.results.window.view, "expanded", "stored")
    assertTrue(ui.list.frame:IsShown() and ui.detail.frame:IsShown(), "side by side")
    assertFalse(ui.detail.w.back:IsShown(), "no Back beside the list")
    local minW = ui.frame:GetResizeBounds()
    assertEqual(minW, R.MIN_WIDTH + R.DETAIL_WIDTH, "the expanded view's minimum")
    assertEqual(NS.db.profile.results.window.width, listWidth, "the stored width is the list's")
    assertEqual(R.MinWidth("collapsed"), R.MIN_WIDTH)
    R.ToggleView()
    assertEqual(R.View(), "collapsed")
end)

test("detail: ShowFight on a fight the view filters out shows its detail", function()
    local NS = fresh()
    local old = rec(NS, { id = "old" })
    old.t = NOW - 30 * 86400
    save(NS, old)
    local pane, ui = detailOn(NS, "old")
    assertEqual(ui.list:Count(), 0, "the list filters it out")
    assertTrue(ui.detail.frame:IsShown(), "the detail is up")
    assertTrue(pane:Record() == old)
end)

test("detail: the popups the window opened close with it", function()
    local NS, M = fresh()
    save(NS, rec(NS, { id = "a" }))
    detailOn(NS, "a")
    NS.Results.Hide()
    local hidden = {}
    for _, name in ipairs(M.__hidden) do hidden[name] = true end
    for _, name in ipairs(NS.Results.POPUPS) do assertTrue(hidden[name], name .. " closed") end
end)

test("detail: the window steps aside for the talent tree and comes back", function()
    local tickers = {}
    local NS, M = fresh(function(m)
        m.PlayerSpellsFrame = { __shown = false, IsShown = function(self) return self.__shown end }
        m.C_Timer.NewTicker = function(_, fn)
            local t = { fn = fn }
            t.Cancel = function() t.stopped = true end
            tickers[#tickers + 1] = t
            return t
        end
    end)
    save(NS, rec(NS, { id = "a" }))
    detailOn(NS, "a")
    M.PlayerSpellsFrame.__shown = true
    NS.Results.StepAsideForTree()
    assertFalse(NS.Results.IsShown(), "out of the tree's way")
    assertTrue(NS.Results.AwaitingTree())
    tickers[1].fn()
    assertFalse(NS.Results.IsShown(), "still waiting while the tree is up")
    M.PlayerSpellsFrame.__shown = false
    tickers[1].fn()
    assertTrue(NS.Results.IsShown(), "back once the tree closed")
    assertFalse(NS.Results.AwaitingTree())
    assertTrue(tickers[1].stopped, "the ticker stopped")
end)

test("detail: forever: the header's second icon is the predominant tree's, hidden with none (D5)", function()
    local NS, m = fresh()
    T.Loader.MockClient.apply(m, "forever")
    local r = rec(NS, { id = "tree" })
    r.who.specID, r.who.specName, r.who.specIcon, r.who.trees = "tree:HUNTER:2", "Marksmanship", 132222, { 5, 41, 5 }
    local bare = rec(NS, { id = "bare" })
    bare.who.specID, bare.who.specName, bare.who.specIcon = nil, nil, nil
    save(NS, r, bare)
    local pane = detailOn(NS, "tree")
    assertTrue(pane.w.spec:IsShown(), "the tree's icon")
    assertEqual(pane.w.spec:GetTexture(), 132222)
    assertTrue(pane.w.specName:GetText():find("Marksmanship", 1, true) ~= nil, pane.w.specName:GetText())
    pane = detailOn(NS, "bare")
    assertFalse(pane.w.spec:IsShown(), "no tree: no second icon")
    assertEqual(pane.w.specName:GetText(), "")
    T.Loader.MockClient.apply(m)
end)

-- ── the Targets section (issue #6) ──────────────────────────────────────────────────────────────

test("detail: the Targets section lists each enemy with its amount and share", function()
    local NS = fresh()
    local r = rec(NS, { id = "t" })
    r.targets = { { name = "Redridge Brute", total = 1063 }, { name = "Redridge Mystic", total = 602 } }
    save(NS, r)
    local pane = detailOn(NS, "t")
    local x = pane.targets
    assertTrue(x.title:IsShown(), "the heading")
    assertEqual(x.title:GetText(), "Targets")
    assertTrue(pane.heads.targets:IsShown(), "its fold arrow")
    assertEqual(x.rows[1].name:GetText(), "Redridge Brute")
    assertTrue(x.rows[1].amount:GetText():find("1.0K", 1, true) ~= nil, x.rows[1].amount:GetText())
    assertTrue(x.rows[1].amount:GetText():find("63.8%", 1, true) ~= nil, "its share of the targets")
    assertTrue(x.rows[1].amount:GetText():find("17 DPS", 1, true) ~= nil, "its DPS over the 60 s fight")
    assertTrue(x.rows[1].bar:IsShown(), "a bar under each row")
    assertTrue(x.rows[2].bar:GetWidth() < x.rows[1].bar:GetWidth(), "the bar's length is the amount's")
    assertEqual(x.rows[2].name:GetText(), "Redridge Mystic")
    assertTrue(x.rows[2].name:IsShown())
    -- Its place, below Usage and above the Note: tests/test_results_sections.lua's NEXT chain.
end)

test("detail: a fight with no targets (an older record) has no Targets section", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "old" }))
    local pane = detailOn(NS, "old")
    assertFalse(pane.targets.title:IsShown(), "no heading")
    assertFalse(pane.heads.targets:IsShown(), "no fold arrow")
    assertEqual(#pane.targets.list, 0)
end)

test("detail: Targets rows skip a malformed entry and share out of what is listed", function()
    local NS = fresh()
    local rows = NS.ResultsTargets.Rows({ targets = { { name = "A", total = 300 }, { name = "B" },
                                                      "junk", { name = "C", total = 100 }, { total = 5 } } })
    assertEqual(#rows, 2)
    assertEqual(rows[1].share, 75)
    assertEqual(rows[2].share, 25)
    assertEqual(rows[1].fill, 1, "the top target's bar is full")
    assertTrue(math.abs(rows[2].fill - 1 / 3) < 1e-9, "the next one's against it")
    assertEqual(rows[1].dps, nil, "no fight length, no DPS")
    local timed = NS.ResultsTargets.Rows({ duration = 25, targets = { { name = "Redridge Brute", total = 1063 } } })
    assertEqual(timed[1].dps, 1063 / 25)
    assertEqual(NS.ResultsTargets.Amount(timed[1]):match("|c%x%x%x%x%x%x%x%x(%d+) DPS"), "42", "whole, as EllesmereUI shows it")
    assertEqual(#NS.ResultsTargets.Rows({}), 0)
    assertEqual(#NS.ResultsTargets.Rows(nil), 0)
end)
