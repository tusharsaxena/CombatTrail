-- tests/test_results_table.lua — the Results window's shell, fight list and table (plan Task 4.1,
-- spec §7): the shipped view (the logged-in character, the last 7 days, grouped by encounter and
-- difficulty), the faceted filters, Bosses only, the Delta column against each group's best, the
-- content facet per client (clients-§4), 500 fights on pooled rows (Review Focus 5), the row menu,
-- Save view, the sample source, and the window's surface (ShowFight, Toggle, the verb, the
-- placeholder contracts core/CombatTrail.lua calls).

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local DAY = 86400
local NOW = os.time()

-- A fresh instance with the kit's paint recorder (a cell's text reads back), whose StaticPopup_Show
-- records what it was asked to show.
local function fresh(mutate)
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        m.__popups = {}
        m.StaticPopup_Show = function(name, _, _, data) m.__popups[#m.__popups + 1] = { name = name, data = data } end
        if mutate then mutate(m) end
    end }
    return inst.NS, inst.mocks, inst
end

local n = 0
--- A stored-shape record. `o` overrides: mine (default true), name, specID, dps, days (ago), boss,
--- content, creatureID, encounterID, difficultyID, difficultyName, keystone.
-- The record's identity from the overrides (rec's half that defaults the board fields).
local function identOf(o)
    return { content = o.content or "world", targetName = o.target or "Angry Boar",
             targetCreatureID = o.creatureID or 1985, difficultyID = o.difficultyID or 0,
             difficultyName = o.difficultyName, isBoss = o.boss or false, keystoneLevel = o.keystone,
             encounterID = o.encounterID, encounterName = o.encounterID and (o.target or "Boss") or nil }
end

local function rec(NS, o)
    o = o or {}
    n = n + 1
    local me = NS.Identity.Who()
    local who = { name = me.name, realm = me.realm, client = me.client, class = me.class or "MAGE",
                  specID = o.specID or me.specID, specName = me.specName, ilvl = 640.5 }
    if o.mine == false then who.name, who.class = o.name or "Altchar", "WARLOCK" end
    local ident = identOf(o)
    local dps = o.dps or 1000
    return {
        schema = 1, id = o.id or ("f-" .. n), t = NOW - (o.days or 0) * DAY - n, duration = 60, status = "final",
        who = who, identity = ident, boardKey = NS.Identity.BoardKey(ident),
        damage = { merged = dps * 60, player = dps * 60 }, dps = dps,
    }
end

local function save(NS, ...)
    for _, r in ipairs({ ... }) do assertTrue(NS.Recorder.Save(r), "saved " .. tostring(r.id)) end
end

local function ids(list)
    local out = {}
    for i, r in ipairs(list) do out[i] = r.id end
    table.sort(out)
    return table.concat(out, ",")
end

local function sorted(options)
    local out = {}
    for _, o in ipairs(options) do out[#out + 1] = tostring(o.value) end
    table.sort(out)
    return table.concat(out, ",")
end

local function values(options)
    local out = {}
    for _, o in ipairs(options) do out[#out + 1] = tostring(o.value) end
    return table.concat(out, ",")
end

-- The window open on the list, laid out at its shipped size.
local function open(NS)
    NS.Results.Show()
    local ui = NS.Results.__ui()
    assertTrue(ui ~= nil, "the window was built")
    return ui, ui.list
end

-- The fight rows drawn now (group headers left out), by id.
local function drawn(view)
    local out = {}
    for _, row in ipairs(view.list:Visible()) do
        if row.record then out[row.record.id] = row end
    end
    return out
end

-- ── the shipped view ────────────────────────────────────────────────────────────────────────────

test("results: default view: current character, last 7 days, grouped by board", function()
    local NS = fresh()
    local v = NS.db.profile.results.view
    assertEqual(v.character, "current")
    assertEqual(v.spec, "all")
    assertEqual(v.content, "all")
    assertEqual(v.board, "all")
    assertEqual(v.difficulty, "all")
    assertEqual(v.days, 7)
    assertEqual(v.bossesOnly, false)
    assertEqual(v.group, "board")
    local recent, older = rec(NS, { id = "recent", days = 1 }), rec(NS, { id = "old", days = 10 })
    local alt = rec(NS, { id = "alt", mine = false, days = 1 })
    local week = rec(NS, { id = "week", days = 6 })
    save(NS, recent, older, alt, week)
    assertEqual(ids(NS.ResultsFights.Rows(nil, NOW)), "recent,week", "mine, in the last 7 days")
    local _, view = open(NS)
    assertEqual(view.filters.group, "board")
    assertEqual(view:Count(), 2)
    local first = view.list:Visible()[1]
    assertTrue(first.group ~= nil, "the first row is a board's group header")
    assertTrue(first.group.label:find("Angry Boar", 1, true) ~= nil, "the header names the board: " .. first.group.label)
end)

test("results: the date range and the character filter", function()
    local NS = fresh()
    local F = NS.ResultsFights
    local a, b, c = rec(NS, { id = "a", days = 0 }), rec(NS, { id = "b", days = 20 }), rec(NS, { id = "c", days = 40 })
    local alt = rec(NS, { id = "alt", mine = false })
    local all = { a, b, c, alt }
    assertEqual(ids(F.Filter(all, { days = 30 }, NOW)), "a,b")
    assertEqual(ids(F.Filter(all, { days = 0 }, NOW)), "a,b,c", "0 is all time")
    assertEqual(ids(F.Filter(all, { days = 0, character = "all" }, NOW)), "a,alt,b,c")
    assertEqual(ids(F.Filter(all, { days = 0, character = F.CharKey(alt) }, NOW)), "alt")
end)

test("results: bossesOnly filter", function()
    local NS = fresh()
    local boss = rec(NS, { id = "boss", boss = true, encounterID = 3176, target = "Plexus Sentinel", difficultyID = 15 })
    local trash = rec(NS, { id = "trash" })
    save(NS, boss, trash)
    assertEqual(ids(NS.ResultsFights.Rows({ bossesOnly = true }, NOW)), "boss")
    assertEqual(ids(NS.ResultsFights.Rows({ bossesOnly = false }, NOW)), "boss,trash")
    local _, view = open(NS)
    rawset(view.bossesOnly, "SetChecked", function(self, on) self.__checked = on end)
    view:SetFilter("bossesOnly", true)
    assertEqual(view:Count(), 1)
    assertTrue(view.bossesOnly.__checked == true, "the box follows the filter")
end)

test("results: the filters are faceted: each list reads the fights the other filters pass", function()
    local NS = fresh()
    local F = NS.ResultsFights
    local fire = rec(NS, { id = "fire", specID = 63 })
    local frost = rec(NS, { id = "frost", specID = 64, content = "dungeon", creatureID = 2000, target = "Ogre" })
    local alt = rec(NS, { id = "alt", mine = false, specID = 265, content = "raid", creatureID = 3000, target = "Drake" })
    local all = { fire, frost, alt }
    local o = F.Options(all, { days = 0 }, NOW)
    assertEqual(values(o.board), "all,c:1985,c:2000", "the current character's targets only")
    assertEqual(sorted(o.spec), "63,64,all,current", "and their specs")
    o = F.Options(all, { days = 0, character = "all" }, NOW)
    assertEqual(sorted(o.spec), "265,63,64,all,current")
    o = F.Options(all, { days = 0, character = "all", content = "raid" }, NOW)
    assertEqual(values(o.board), "all,c:3000", "a content pick narrows the targets")
    assertTrue(values(o.content):find("dungeon", 1, true) ~= nil, "the content list ignores its own pick")
    assertEqual(values(o.days), "1,7,30,0")
    assertEqual(values(o.group), "board,character,spec,content,none")
end)

test("results: the Spec dropdown and grouping are on both clients; Forever names a talent tree (D5, D11)", function()
    local NS = fresh()
    local _, view = open(NS)
    assertTrue(view.dropdowns.spec ~= nil, "the Spec dropdown")
    assertTrue(NS.ResultsFights.GroupSpec("spec") ~= nil, "the Spec grouping")
    view:SetFilter("group", "spec")
    assertTrue(view.list.grouping ~= nil)
    local o = NS.ResultsFights.Options({ rec(NS) }, { days = 0 }, NOW)
    local groupLabel
    for _, g in ipairs(o.group) do if g.value == "spec" then groupLabel = g.label end end
    if NS.Compat.IsForever() then
        assertEqual(o.spec[2].label, "All talent trees")
        assertEqual(o.spec[1].label, "Current talent tree")
        assertEqual(groupLabel, "Group: Talent tree")
    else
        assertEqual(o.spec[2].label, "All specs")
        assertEqual(o.spec[1].label, "Current spec")
        assertEqual(groupLabel, "Group: Spec")
    end
end)

test("results: forever: the predominant tree is the row's second icon, the Spec filter and the grouping", function()
    local NS, m = fresh()
    T.Loader.MockClient.apply(m, "forever")
    local function tree(r, index, name, icon)
        r.who.specID, r.who.specName, r.who.specIcon = ("tree:MAGE:%d"):format(index), name, icon
        r.who.trees = index == 1 and { 31, 20, 0 } or { 0, 20, 31 }
        return r
    end
    local arcane = tree(rec(NS, { id = "arcane" }), 1, "Arcane", 135932)
    local frost = tree(rec(NS, { id = "frost", creatureID = 2000, target = "Ogre" }), 3, "Frost", 135846)
    local bare = rec(NS, { id = "bare", creatureID = 3000, target = "Drake" })
    bare.who.specID, bare.who.specName = nil, nil
    local F = NS.ResultsFights
    local o = F.Options({ arcane, frost, bare }, { days = 0 }, NOW)
    assertEqual(sorted(o.spec), "all,current,tree:MAGE:1,tree:MAGE:3", "a tree is a Spec option")
    local labels = {}
    for _, opt in ipairs(o.spec) do labels[#labels + 1] = opt.label end
    assertTrue(table.concat(labels, ","):find("Arcane", 1, true) ~= nil, "named by the tree")
    assertEqual(ids(F.Filter({ arcane, frost, bare }, { days = 0, spec = "tree:MAGE:3" }, NOW)), "frost")
    local key, label = F.GROUPS.spec.of(frost)
    assertTrue(label:find("Frost", 1, true) ~= nil, "the group header names the tree")
    assertTrue(key ~= F.GROUPS.spec.of(arcane), "two trees, two groups")
    save(NS, arcane, bare)
    local _, view = open(NS)
    local rows = drawn(view)
    local icon = rows.arcane.cells.clsSpec.spec
    assertTrue(icon:IsShown(), "the tree's icon is the second icon")
    assertEqual(icon:GetTexture(), 135932)
    assertFalse(rows.bare.cells.clsSpec.spec:IsShown(), "no tree: no second icon, never the class icon twice")
    assertEqual(rows.arcane.cells.clsSpec.specName, "Arcane")
    T.Loader.MockClient.apply(m)
end)

test("results: forever: content facet lacks mplus/delve/arena", function()
    local NS = fresh()
    local all = {}
    for _, key in ipairs({ "raid", "dungeon", "mplus", "delve", "bg", "arena", "world", "dummy", "scenario" }) do
        all[#all + 1] = rec(NS, { content = key, creatureID = 100 + #all })
    end
    local got = values(NS.ResultsFights.Options(all, { days = 0 }, NOW).content)
    if NS.Compat.IsForever() then
        assertEqual(got, "all,raid,dungeon,bg,world,dummy,scenario")
        for _, key in ipairs({ "mplus", "delve", "arena" }) do
            assertTrue(got:find(key, 1, true) == nil, key .. " is absent on WoW Forever")
        end
    else
        assertEqual(got, "all,raid,dungeon,mplus,delve,bg,arena,world,dummy,scenario")
    end
end)

-- ── the Delta column ────────────────────────────────────────────────────────────────────────────

test("results: delta vs group best", function()
    local NS = fresh()
    local slow = rec(NS, { id = "slow", dps = 1000 })
    local fast = rec(NS, { id = "fast", dps = 1500 })
    local other = rec(NS, { id = "other", dps = 800, creatureID = 2000, target = "Ogre" })
    save(NS, slow, fast, other)
    local _, view = open(NS)
    local rows = drawn(view)
    local function cell(id) return rows[id].cells.delta.fs:GetText() end
    assertTrue(cell("fast"):find("Best", 1, true) ~= nil, "the board's best: " .. cell("fast"))
    assertEqual(cell("slow"), "-33.3%", "against its own board's best")
    assertTrue(cell("other"):find("Best", 1, true) ~= nil, "alone on its board, it is its best")
    view:SetFilter("group", "none")
    rows = drawn(view)
    assertEqual(cell("other"), "-46.7%", "flat: against the best in the list")
    assertEqual(cell("slow"), "-33.3%")
    assertTrue(cell("fast"):find("Best", 1, true) ~= nil)
    -- The Delta context the fight detail reads (plan Task 4.2).
    local ctx = view:DeltaContext(slow)
    assertEqual(ctx.first.id, "fast")
    assertEqual(ctx.second.id, "slow")
end)

test("results: the leader of a group is the earlier fight on a DPS tie", function()
    local NS = fresh()
    local F = NS.ResultsFights
    local early = rec(NS, { id = "early", dps = 1000, days = 2 })
    local late = rec(NS, { id = "late", dps = 1000, days = 1 })
    local ctx = F.Context({ late, early })
    assertEqual(ctx.first.id, "early")
    assertEqual(F.DeltaText(late, ctx), "0.0%")
    assertEqual(F.Delta(late, ctx.top), 0)
    assertNil(F.Delta({ id = "x" }, ctx.top), "no DPS, no delta")
end)

-- ── the table ───────────────────────────────────────────────────────────────────────────────────

test("results: the table's columns are the plan's", function()
    local NS = fresh()
    local keys = {}
    for i, col in ipairs(NS.ResultsFights.Columns()) do keys[i] = col.key end
    assertEqual(table.concat(keys, ","), "date,clsSpec,character,ilvl,target,content,len,damage,dps,delta")
end)

test("results: table builds 500 rows via pooled rows", function()
    local NS = fresh()
    for i = 1, 500 do
        NS.Recorder.Save(rec(NS, { id = ("f%03d"):format(i), dps = 1000 + i, creatureID = 1000 + (i % 7) }))
    end
    assertEqual(NS.Recorder.Count(), 500)
    local _, view = open(NS)
    view:SetFilter("group", "none")
    local list = view.list
    assertEqual(view:Count(), 500, "every fight passes")
    local fit = list:visibleCount()
    assertTrue(fit < 500, "the window shows a slice")
    assertEqual(#list:Visible(), fit, "only the rows that fit are drawn")
    local made = list:Made()
    assertTrue(made <= fit, "no row frame beyond the visible count: " .. made)
    list:ScrollTo(10000)
    assertEqual(list.offset, 500 - fit, "scrolled to the end")
    local last = list:Visible()[#list:Visible()]
    assertTrue(last.record ~= nil, "the last row is bound")
    list:ScrollTo(0)
    view:SetFilter("group", "board")
    assertEqual(list:Made(), made, "scrolling and regrouping re-bind the same frames")
    local free, active = NS.Pool.Counts(list.pool)
    assertEqual(free + active, made, "every frame is the pool's")
end)

test("results: a header click sorts, a second flips it, and a saved view keeps the sort", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "lo", dps = 500 }), rec(NS, { id = "hi", dps = 900 }))
    local _, view = open(NS)
    view:SetFilter("group", "none")
    view.list:SetSort("dps")
    assertEqual(view.list:Visible()[1].record.id, "hi", "DPS sorts high first")
    view.list:SetSort("dps")
    assertEqual(view.list:Visible()[1].record.id, "lo", "a second click flips it")
    assertTrue(view:SaveView(), "saved")
    local v = NS.db.profile.results.view
    assertEqual(v.sort, "dps")
    assertEqual(v.desc, false)
    assertEqual(v.group, "none")
end)

test("results: Save view persists results.view; Reset view puts the shipped one back", function()
    local NS = fresh()
    local _, view = open(NS)
    view:SetFilter("days", 30)
    view:SetFilter("bossesOnly", true)
    assertEqual(NS.db.profile.results.view.days, 7, "nothing is stored before Save")
    assertTrue(view:SaveView())
    assertEqual(NS.db.profile.results.view.days, 30)
    assertEqual(NS.db.profile.results.view.bossesOnly, true)
    -- A new window (the next login) opens on the saved view.
    local again = NS.ResultsFights.Build(NS.Results.__ui().body, {})
    assertEqual(again.filters.days, 30)
    assertTrue(view:ResetView())
    assertEqual(NS.db.profile.results.view.days, 7)
    assertEqual(view.filters.bossesOnly, false)
end)

-- ── the row menu ────────────────────────────────────────────────────────────────────────────────

-- Run the row menu's fill against a recorder and answer its items: { label, enabled, onClick }.
local function menuOf(NS, record)
    local items
    local saved = NS.OpenMenu
    NS.OpenMenu = function(_, fill)
        items = {}
        local root = {}
        function root.CreateTitle(_, text) items[#items + 1] = { label = text, title = true } end
        function root.CreateButton(_, text, onClick)
            local item = { label = text, onClick = onClick, enabled = true }
            function item.SetEnabled(_, on) item.enabled = on and true or false end
            function item.CreateButton() return { SetEnabled = function() end } end
            items[#items + 1] = item
            return item
        end
        fill(root)
    end
    NS.Results.RowMenu(record)
    NS.OpenMenu = saved
    return items
end

test("results: right-click menu has Note, Share, Compare With This Fight, Delete", function()
    local NS, M = fresh()
    local a, b = rec(NS, { id = "a" }), rec(NS, { id = "b" })
    save(NS, a, b)
    NS.Results.ShowFight("a")
    local items = menuOf(NS, NS.Recorder.Get("b"))
    local labels = {}
    for i, item in ipairs(items) do labels[i] = item.label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    assertTrue(items[1].title, "a title first")
    assertEqual(labels[2], "Add Note")
    assertEqual(labels[3], "Share")
    assertEqual(labels[4], "Compare With This Fight")
    assertEqual(labels[5], "Delete")
    assertTrue(items[3].enabled, "Share is live for a stored fight (plan Task 4.2)")
    assertTrue(items[4].enabled, "b can be compared with the selected a")
    assertFalse(menuOf(NS, NS.Recorder.Get("a"))[4].enabled, "not the selected fight with itself")
    -- Compare: a session pick.
    items[4].onClick()
    assertEqual(NS.Results.Pick(), "b")
    -- Add Note: the note box, then a saved note reads Edit Note.
    items[2].onClick()
    assertEqual(M.__popups[#M.__popups].name, "COMBATTRAIL_FIGHT_NOTE")
    NS.Results.SetNote("b", "  pulled early  ")
    assertEqual(NS.Recorder.Get("b").note, "pulled early")
    assertEqual(menuOf(NS, NS.Recorder.Get("b"))[2].label, "Edit Note")
    -- Delete: asks first, then the popup's Accept deletes, and the pick goes with the fight.
    items[5].onClick()
    local popup = M.__popups[#M.__popups]
    assertEqual(popup.name, "COMBATTRAIL_DELETE_FIGHT")
    assertTrue(NS.Recorder.Get("b") ~= nil, "nothing deleted before the Accept")
    M.StaticPopupDialogs.COMBATTRAIL_DELETE_FIGHT.OnAccept(nil, popup.data)
    assertNil(NS.Recorder.Get("b"), "deleted")
    assertNil(NS.Results.Pick(), "the pick went with it")
    assertEqual(NS.Results.__ui().list:Count(), 1, "FIGHTS_CHANGED redrew the list")
end)

-- ── the window ──────────────────────────────────────────────────────────────────────────────────

test("results: the window is a toplevel HIGH browser in the close stack", function()
    local NS, M = fresh()
    local ui = open(NS)
    local f = ui.frame
    assertEqual(f:GetFrameStrata(), "HIGH")
    assertTrue(f.__toplevel == true or (f.IsToplevel and f:IsToplevel()) == true, "toplevel")
    local listed = false
    for _, name in ipairs(M.UISpecialFrames) do listed = listed or name == "CombatTrailResults" end
    assertTrue(listed, "Escape closes it")
    assertTrue(f:IsResizable() == true, "the grip makes it resizable")
    local minW, minH = f:GetResizeBounds()
    assertEqual(minW, NS.Results.MIN_WIDTH)
    assertEqual(minH, NS.Results.MIN_HEIGHT)
    assertTrue(NS.Results.MIN_WIDTH >= NS.ResultsTable.MinWidth(NS.ResultsFights.Columns()), "the columns fit")
    assertTrue(NS.Results.MIN_WIDTH >= NS.ResultsFights.BarMinWidth(), "the filter bar fits")
end)

test("results: ShowFight opens the window on the fight; Toggle closes and opens it", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "a" }), rec(NS, { id = "b" }))
    assertTrue(NS.Results.ShowFight("b"))
    assertTrue(NS.Results.IsShown())
    assertEqual(NS.Results.Selected(), "b")
    assertTrue(drawn(NS.Results.__ui().list).b.sel:IsShown(), "the fight's row is marked")
    NS.Results.Toggle()
    assertFalse(NS.Results.IsShown())
    assertFalse(NS.Results.__ui().frame:IsShown(), "the frame follows")
    NS.Results.Toggle()
    assertTrue(NS.Results.IsShown())
    assertTrue(NS.Results.ShowFight("gone"), "an id no longer stored opens the list")
    assertNil(NS.Results.Selected())
    assertTrue(NS.Results.Open(nil))
end)

test("results: the HUD's Results control reaches the window", function()
    local NS = fresh()
    NS.Hud.Act.results()
    assertTrue(NS.Results.IsShown(), "the HUD's chart control toggles the window open")
end)

test("results: the verb, Reset position and the Locked row", function()
    local NS, M = fresh()
    NS.Slash:OnSlash("results")
    assertTrue(NS.Results.IsShown(), "/ct results toggles it open")
    NS.Slash:OnSlash("results hide")
    assertFalse(NS.Results.IsShown())
    NS.Slash:OnSlash("results show")
    assertTrue(NS.Results.IsShown())
    M.__resetPrinted()
    NS.Results.OnVerb("sideways")
    assertEqual(#M.__printed(), 1, "an unknown word is one usage line")
    local w = NS.db.profile.results.window
    w.x, w.y, w.width = 120, -40, 1200
    NS.ResetPositions()
    assertEqual(w.x, 0)
    assertEqual(w.y, 0)
    assertEqual(w.width, NS.defaults.profile.results.window.width)
    NS.ApplyLocked(true)
    assertTrue(NS.Results.IsShown(), "the lock leaves the browser alone")
end)

test("results: the drag stores the window's place", function()
    local NS = fresh()
    local ui = open(NS)
    ui.frame:ClearAllPoints()
    ui.frame:SetPoint("TOPLEFT", T.mocks.UIParent, "TOPLEFT", 40.4, -60.6)
    rawset(ui.frame, "GetPoint", function() return "TOPLEFT", nil, "TOPLEFT", 40.4, -60.6 end)
    ui.drag:__fire("OnDragStop")
    local w = NS.db.profile.results.window
    assertEqual(w.point, "TOPLEFT")
    assertEqual(w.x, 40)
    assertEqual(w.y, -61)
end)

test("results: the sample source lists its fights, refuses Save view, and gives the store back", function()
    local NS, M = fresh()
    save(NS, rec(NS, { id = "real" }))
    local _, view = open(NS)
    assertEqual(view:Count(), 1)
    local sample = rec(NS, { id = "sample", mine = false })
    assertTrue(NS.ResultsSource.Use({ fights = { sample } }))
    assertTrue(NS.ResultsSource.IsMock())
    assertEqual(view:Count(), 1)
    assertTrue(drawn(view).sample ~= nil, "the sample's fight, on every character")
    M.__resetPrinted()
    assertFalse(view:SaveView(), "Save view refuses")
    assertEqual(#M.__printed(), 1)
    assertTrue(NS.ResultsSource.Delete("sample"))
    assertNil(NS.Recorder.Get("sample"), "never in the store")
    NS.ResultsSource.Use(nil)
    assertFalse(NS.ResultsSource.IsMock())
    assertEqual(view.filters.character, "current", "the player's view is back")
    assertTrue(drawn(view).real ~= nil)
end)

test("results: the stand-down hides the window and the stand-up brings it back", function()
    local NS = fresh()
    local ui = open(NS)
    NS.StandDown()
    assertFalse(ui.frame:IsShown(), "hidden while stood down")
    NS.StandUp()
    assertTrue(ui.frame:IsShown(), "back for the player who had it open")
end)

test("results: a saved fight redraws a shown list", function()
    local NS = fresh()
    local _, view = open(NS)
    assertEqual(view:Count(), 0)
    save(NS, rec(NS, { id = "new" }))
    assertEqual(view:Count(), 1, "FIGHT_SAVED redrew it")
end)

test("results: every cell and header has a tooltip", function()
    local NS = fresh()
    local r = rec(NS, { id = "a", boss = true, encounterID = 3176, target = "Plexus Sentinel" })
    save(NS, r)
    local Tips = NS.ResultsTips
    for _, col in ipairs(NS.ResultsFights.Columns()) do
        local lines = Tips.Cell(col, r)
        assertTrue(type(lines) == "table" and lines[1] ~= nil, col.key .. " cell tooltip")
        assertTrue(Tips.About(col) ~= nil, col.key .. " header tooltip")
    end
end)
