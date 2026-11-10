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
    assertEqual(cell("fast"), "0.0%", "the board's best reads 0.0% (v0.2 Task C2: no trophy, no word)")
    assertEqual(cell("slow"), "-33.3%", "against its own board's best")
    assertEqual(cell("other"), "0.0%", "alone on its board, it is its best")
    view:SetFilter("group", "none")
    rows = drawn(view)
    assertEqual(cell("other"), "-46.7%", "flat: against the best in the list")
    assertEqual(cell("slow"), "-33.3%")
    assertEqual(cell("fast"), "0.0%")
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
    assertEqual(F.DeltaText(early, ctx), "0.0%", "the leader reads 0.0% too")
    assertEqual(F.Delta(late, ctx.top), 0)
    assertNil(F.Delta({ id = "x" }, ctx.top), "no DPS, no delta")
end)

-- ── the table ───────────────────────────────────────────────────────────────────────────────────

test("results: the table's columns are the plan's", function()
    local NS = fresh()
    local keys = {}
    for i, col in ipairs(NS.ResultsFights.Columns()) do keys[i] = col.key end
    assertEqual(table.concat(keys, ","), "date,clsSpec,character,ilvl,target,content,len,damage,dps,delta,status,used,note")
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

-- ── v0.2 Task C1: close on combat, the fold arrow, the Character width, the second icon ─────────

-- A fresh instance on the scripted meter, so the regen edge runs the real fight state machine.
local function freshFight()
    return fresh(function(m) T.mockMeter.install(m) end)
end

local function enterCombat(M, t)
    M.__now = t
    M.InCombatLockdown = function() return true end
    M.__inCombat = true
    M.__fire("PLAYER_REGEN_DISABLED")
end

test("results: entering combat closes the window when Close when combat starts is on, and not when off", function()
    local NS, M = freshFight()
    assertEqual(NS.defaults.profile.results.closeInCombat, true, "on by default")
    local ui = open(NS)
    enterCombat(M, 10)
    assertFalse(NS.Results.IsShown(), "closed on the regen edge")
    assertFalse(ui.frame:IsShown(), "the frame follows")
    local NS2, M2 = freshFight()
    assertTrue(NS2.SetByPath("results.closeInCombat", false))
    local ui2 = open(NS2)
    enterCombat(M2, 10)
    assertTrue(NS2.Results.IsShown(), "the option off keeps it open")
    assertTrue(ui2.frame:IsShown())
end)

test("results: a window reopened mid-combat stays open through a split or an encounter start", function()
    local NS, M = freshFight()
    open(NS)
    enterCombat(M, 10)
    assertFalse(NS.Results.IsShown())
    NS.Results.Show()
    M.__now = 15
    M.__fire("ENCOUNTER_START", 2002, "Grobbulus", 15, 20)
    M.__fireTimers()
    assertTrue(NS.Results.IsShown(), "only the regen edge closes it")
end)

test("results: the fold arrow shows chevron-right collapsed and chevron-left expanded", function()
    local NS = fresh()
    local ui = open(NS)
    assertEqual(NS.Results.View(), "collapsed")
    assertEqual(ui.viewToggle.iconName, "chevron-right", "collapsed: open the detail to the right")
    NS.Results.ToggleView()
    assertEqual(NS.Results.View(), "expanded")
    assertEqual(ui.viewToggle.iconName, "chevron-left", "expanded: fold the detail away")
    NS.Results.ToggleView()
    assertEqual(ui.viewToggle.iconName, "chevron-right")
end)

local function indexOf(columns, key)
    for i, col in ipairs(columns) do if col.key == key then return i end end
end

test("results: Character is a fixed 104 px column and the target column takes the rest", function()
    local NS = fresh()
    local F, Tbl = NS.ResultsFights, NS.ResultsTable
    local cols = F.Columns()
    local ci, ti = indexOf(cols, "character"), indexOf(cols, "target")
    assertEqual(F.CHARACTER_W, 104)
    local shipped = NS.defaults.profile.results.window.width
    for _, width in ipairs({ NS.Results.MIN_WIDTH, shipped, 1400 }) do
        local place = Tbl.Columns(cols, width)
        assertEqual(place[ci].w, 104, "Character at " .. width)
        assertTrue(place[ti].w >= F.TARGET_W, "the target column keeps its minimum at " .. width)
        local last = place[#place]
        assertTrue(last.x + last.w <= width - Tbl.SCROLLBAR_W - Tbl.PAD, "the columns fit at " .. width)
    end
    assertTrue(Tbl.Columns(cols, 1400)[ti].w > Tbl.Columns(cols, shipped)[ti].w, "a wider window widens the target")
    assertTrue(NS.defaults.profile.results.window.width >= NS.Results.MIN_WIDTH, "the shipped width fits")
end)

test("results: a stored Character width wins, within the room the target column leaves", function()
    local NS = fresh()
    local F, Tbl = NS.ResultsFights, NS.ResultsTable
    local cols = F.Columns()
    local ci, ti = indexOf(cols, "character"), indexOf(cols, "target")
    assertEqual(Tbl.Columns(cols, 1400, { character = 160 })[ci].w, 160, "the stored width")
    assertEqual(Tbl.Columns(cols, 1400, { character = 9999 })[ci].w, F.CHARACTER_MAX, "held to the most")
    assertEqual(Tbl.Columns(cols, 1400, { character = 1 })[ci].w, F.CHARACTER_MIN, "held to the least")
    local tight = Tbl.Columns(cols, NS.Results.MIN_WIDTH, { character = 200 })
    assertTrue(tight[ti].w >= F.TARGET_W, "the target keeps its minimum")
    assertTrue(tight[ci].w >= F.CHARACTER_W, "the character gives back only what it took")
    local least = Tbl.MinWidth(cols)
    local full = Tbl.Columns(cols, least, { character = 200 })
    assertEqual(full[ci].w, F.CHARACTER_W, "at the least width the drag gives back all it took")
    assertEqual(full[ti].w, F.TARGET_W, "and the target sits at its minimum")
    assertTrue(full[#full].x + full[#full].w <= least - Tbl.SCROLLBAR_W - Tbl.PAD, "the columns still fit")
    NS.db.profile.results.columns.character = 150
    local _, view = open(NS)
    assertEqual(view.list.place[ci].w, 150, "the window lays out the stored width")
end)

test("results: dragging the Character header's edge resizes it and stores the width on release", function()
    local cursor = 0
    local NS = fresh(function(m) m.GetCursorPosition = function() return cursor, 0 end end)
    local cols = NS.ResultsFights.Columns()
    local ci = indexOf(cols, "character")
    local _, view = open(NS)
    local grip = view.list.heads[ci].grip
    assertTrue(grip ~= nil, "the Character header has a grip")
    assertNil(view.list.heads[indexOf(cols, "date")].grip, "a fixed column has none")
    cursor = 500
    grip:__fire("OnMouseDown", "LeftButton")
    cursor = 530
    grip:__fire("OnUpdate", 0.01)
    assertEqual(view.list.place[ci].w, 134, "live while dragged")
    assertNil(NS.db.profile.results.columns.character, "nothing stored mid-drag")
    grip:__fire("OnMouseUp", "LeftButton")
    assertEqual(NS.db.profile.results.columns.character, 134, "stored on release")
    NS.ResetPositions()
    assertNil(NS.db.profile.results.columns.character, "Reset position puts the shipped width back")
    assertEqual(view.list.place[ci].w, 104)
end)

test("results: a window hidden while the Character edge is held ends the drag and stores the width", function()
    local cursor = 0
    local NS = fresh(function(m) m.GetCursorPosition = function() return cursor, 0 end end)
    local ci = indexOf(NS.ResultsFights.Columns(), "character")
    local _, view = open(NS)
    local grip = view.list.heads[ci].grip
    cursor = 500
    grip:__fire("OnMouseDown", "LeftButton")
    cursor = 520
    grip:__fire("OnUpdate", 0.01)
    grip:__fire("OnHide")                 -- no mouse-up reaches a hidden grip
    assertEqual(NS.db.profile.results.columns.character, 124, "stored as a release would")
    assertNil(view.list.dragging, "the drag is over")
    assertNil(grip:GetScript("OnUpdate"), "the cursor no longer drives the column")
    cursor = 700
    view.list:Layout(view.list.width, view.list.height)
    assertEqual(view.list.place[ci].w, 124, "a later layout keeps the stored width")
end)

test("results: no spec: the row draws its class icon and no second icon", function()
    local NS = fresh(function(m) m.CLASS_ICON_TCOORDS = { MAGE = { 0, 0.25, 0, 0.25 } } end)
    local r = rec(NS, { id = "nospec" })
    r.who.specID, r.who.specName, r.who.specIcon = nil, nil, nil
    save(NS, r)
    local _, view = open(NS)
    local cell = drawn(view).nospec.cells.clsSpec
    assertTrue(cell.class:IsShown(), "the class icon")
    assertFalse(cell.spec:IsShown(), "no second icon, never the class icon twice")
end)

-- ── v0.2 Task C2: Delta 0.0%, the Status, Used and Note columns, notes, the palette's bars ──────

-- A fresh instance whose item API answers an icon per item (5000 + its id) and a name.
local function freshItems()
    return fresh(function(m)
        m.C_Item.GetItemIconByID = function(id) return 5000 + id end
        m.C_Item.GetItemNameByID = function(id) return "Item " .. id end
    end)
end

-- A usage record of `count` used entries: on-use gear first, then food.
local function usageOf(count)
    local used = {}
    for i = 1, count do
        used[i] = i == count and { kind = "food", src = "buff" } or { kind = "gear", itemID = 100 + i, slot = 13, n = 1, times = { 9 } }
    end
    return { v = 1, edited = false, used = used, candidates = {} }
end

test("results: the Status badge reads Best with the trophy on the board's top only", function()
    local NS = fresh()
    local slow, fast = rec(NS, { id = "slow", dps = 1000 }), rec(NS, { id = "fast", dps = 1500 })
    save(NS, slow, fast)
    local _, view = open(NS)
    local rows = drawn(view)
    local top, other = rows.fast.cells.status, rows.slow.cells.status
    assertEqual(top.fs:GetText(), "Best")
    assertTrue(top.box:IsShown(), "the badge's box")
    assertTrue(top.icon:IsShown(), "the trophy inside it")
    assertEqual(top.icon:GetTexture(), NS.Icon("ph:trophy"))
    assertEqual(other.fs:GetText(), "", "no tag below the top")
    assertFalse(other.box:IsShown(), "no box below the top")
    local cols = NS.ResultsFights.Columns()
    local status = cols[indexOf(cols, "status")]
    assertEqual(status.kind, "badge")
    assertTrue(status.sort(fast) < 99 and status.sort(slow) == nil, "the best sorts first, the rest after it")
    assertTrue(NS.ResultsTips.Cell(status, fast)[1] ~= nil, "the best's tooltip")
    assertTrue(NS.ResultsTips.Cell(status, slow)[1] ~= nil, "every fight's tooltip")
end)

test("results: the Used column lists the fight's usage as icons, +n past what fits, a dash for none", function()
    local NS = freshItems()
    local Tbl, U = NS.ResultsTable, NS.ResultsUsage
    local two, many, none, unrec = rec(NS, { id = "two" }), rec(NS, { id = "many" }), rec(NS, { id = "none" }),
        rec(NS, { id = "unrec" })
    two.usage, many.usage, none.usage = usageOf(2), usageOf(6), usageOf(0)
    save(NS, two, many, none, unrec)
    assertEqual(U.Count(two), 2)
    assertEqual(U.Count(none), 0)
    assertNil(U.Count(unrec), "not recorded sorts last")
    local icons = U.Icons(two)
    assertEqual(icons[1], 5101, "the gear's own icon first")
    assertEqual(icons[2], U.FOOD_ICON, "then the food")
    assertNil(U.Icons(unrec))
    local cols = NS.ResultsFights.Columns()
    local used = cols[indexOf(cols, "used")]
    assertEqual(used.kind, "items")
    assertEqual(Tbl.IconSlots(used.width), 4)
    local shown, more = Tbl.IconsFit(6, used.width)
    assertEqual(shown, 3)
    assertEqual(more, 3)
    local _, view = open(NS)
    view:SetFilter("group", "none")
    local rows = drawn(view)
    local c2 = rows.two.cells.used
    assertTrue(c2.icon1:IsShown() and c2.icon2:IsShown(), "two icons")
    assertFalse(c2.icon3:IsShown(), "no third")
    assertEqual(c2.icon1:GetTexture(), 5101)
    assertFalse(c2.dash:IsShown())
    assertFalse(c2.more:IsShown())
    local c6 = rows.many.cells.used
    assertTrue(c6.icon3:IsShown() and not c6.icon4:IsShown(), "three icons, then the count")
    assertEqual(c6.more:GetText(), "+3")
    assertTrue(rows.none.cells.used.dash:IsShown(), "a dash for nothing used")
    assertTrue(rows.unrec.cells.used.dash:IsShown(), "a dash for not recorded")
    -- The tooltip names each entry.
    local tip = NS.ResultsTips.Cell(used, two)
    assertEqual(tip[1], "2 items used")
    assertTrue(tostring(tip[2]):find("Item 101", 1, true) ~= nil, "the gear by name: " .. tostring(tip[2]))
    assertEqual(NS.ResultsTips.Cell(used, unrec)[1], "Not recorded")
    assertEqual(NS.ResultsTips.Cell(used, none)[1], "Nothing used")
end)

test("results: the Note column shows the note cut to ten characters, the whole of it on hover", function()
    local NS = fresh()
    local F = NS.ResultsFights
    local long, short, bare = rec(NS, { id = "long" }), rec(NS, { id = "short" }), rec(NS, { id = "bare" })
    long.note, short.note = "pulled with \195\169clat early", "ok"
    save(NS, long, short, bare)
    assertEqual(F.NoteCell(long), "pulled wit\226\128\166", "ten characters, then an ellipsis")
    assertEqual(F.NoteCell(short), "ok")
    assertEqual(F.NoteCell(bare), "")
    local accented = { note = "\195\169\195\169\195\169\195\169\195\169\195\169\195\169\195\169\195\169\195\169\195\169" }
    assertEqual(F.NoteCell(accented), ("\195\169"):rep(10) .. "\226\128\166", "never a byte cut through a character")
    assertEqual(F.NoteSort(long), "pulled with \195\169clat early")
    assertNil(F.NoteSort(bare), "no note sorts last")
    local cols = F.Columns()
    local note = cols[indexOf(cols, "note")]
    assertEqual(NS.ResultsTips.Cell(note, long)[2], long.note, "the whole note on hover")
    assertTrue(NS.ResultsTips.Cell(note, bare)[1] ~= nil, "a fight with no note says so")
    local _, view = open(NS)
    view:SetFilter("group", "none")
    assertEqual(drawn(view).long.cells.note.fs:GetText(), "pulled wit\226\128\166")
end)

test("results: a note is added, edited and cleared from the note box, and a reload keeps it", function()
    local NS, M = fresh()
    save(NS, rec(NS, { id = "a" }))
    local _, view = open(NS)
    view:SetFilter("group", "none")
    local dialog = M.StaticPopupDialogs.COMBATTRAIL_FIGHT_NOTE
    assertEqual(dialog.maxLetters, NS.Recorder.NOTE_MAX)
    assertTrue(NS.Results.EditNote("a"))
    local data = M.__popups[#M.__popups].data
    -- Enter in the box saves and closes, as Save does; Escape closes.
    local hidden = 0
    local popup = { Hide = function() hidden = hidden + 1 end }
    local function box(text) return { GetText = function() return text end, GetParent = function() return popup end } end
    dialog.EditBoxOnEnterPressed(box("  first pull  "), data)
    assertEqual(NS.Recorder.Get("a").note, "first pull", "added")
    assertEqual(hidden, 1, "Enter closed the box")
    assertEqual(drawn(view).a.cells.note.fs:GetText(), "first pull", "FIGHTS_CHANGED redrew the list")
    dialog.EditBoxOnEnterPressed(box("second pull"), data)
    assertEqual(NS.Recorder.Get("a").note, "second pull", "edited")
    dialog.EditBoxOnEscapePressed(box("ignored"), data)
    assertEqual(hidden, 3, "Escape closed it")
    assertEqual(NS.Recorder.Get("a").note, "second pull", "Escape saved nothing")
    -- The /reload: the same SavedVariables come back on a new instance, the note with them.
    local saved = _G.CombatTrailDB
    local again = T.load{ init = false }
    _G.CombatTrailDB = saved
    local AceAddon = again.mocks.LibStub("AceAddon-3.0")
    AceAddon:InitializeAddon(again.NS)
    AceAddon:EnableAddon(again.NS)
    assertEqual(again.NS.Recorder.Get("a").note, "second pull", "the note survived the reload")
    assertTrue(again.NS.Results.SetNote("a", "   ") == nil, "an empty note clears it")
    assertNil(again.NS.Recorder.Get("a").note)
end)

test("results: a note's escape codes and control characters are neutralized", function()
    local NS = fresh()
    local R = NS.Recorder
    assertEqual(R.ClampNote("|cffff0000red|r and |Hitem:1|h[x]|h"), "/cffff0000red/r and /Hitem:1/h[x]/h")
    assertEqual(R.ClampNote("two\nlines\tand\001more"), "two lines and more")
    assertEqual(R.ClampNote(("\195\169"):rep(250)), ("\195\169"):rep(R.NOTE_MAX), "200 characters, not bytes")
    assertEqual(R.ClampNote(nil), "")
    save(NS, rec(NS, { id = "a" }))
    NS.Results.SetNote("a", "|TInterface\\Icons\\x:0|t boom")
    assertEqual(R.Get("a").note, "/TInterface\\Icons\\x:0/t boom", "stored with its escapes neutralized")
    -- The sample's notes (test mode) go through the same clamp.
    assertTrue(NS.Preview.Start({ mode = "test" }), "test mode")
    local sample = NS.ResultsSource.All()[1]
    assertTrue(NS.ResultsSource.SetNote(sample.id, "a|cffffffffb"))
    assertEqual(sample.note, "a/cffffffffb")
end)

test("results: the Damage and DPS bars are the palette's blue, not the class color, under every skin", function()
    local NS, M = fresh()
    local P = NS.Constants.PALETTE
    save(NS, rec(NS, { id = "slow", dps = 1000 }), rec(NS, { id = "fast", dps = 1500 }))
    local _, view = open(NS)
    local function barColor(id, key)
        local c = M.__paint(drawn(view)[id].cells[key].bar).color
        return c
    end
    local function isPalette(c, what)
        for i = 1, 3 do assertTrue(math.abs(c[i] - P.BAR[i]) < 1e-6, what .. " channel " .. i) end
        assertTrue(math.abs(c[4] - P.BAR_A) < 1e-6, what .. " alpha")
    end
    assertEqual(NS.ResultsTable.BAR_ALPHA, P.BAR_A)
    for _, key in ipairs({ "damage", "dps" }) do
        for _, id in ipairs({ "slow", "fast" }) do isPalette(barColor(id, key), key .. " " .. id) end
    end
    -- A skin switch repaints the window; the fills stay the palette's (skinning rung 4: a data hue).
    local W = dofile(T.root .. "/tests/_kit/skin_switch.lua")
    local Skin = M.LibStub("LibKa0s-Skin-1.0")
    Skin:RegisterSkin({ key = W.PROBE_KEY, label = "Probe", tokens = W.probeTokens(Skin) })
    Skin:SetChoice("CombatTrail", "ka0s", W.PROBE_KEY)
    view:Refresh()
    for _, key in ipairs({ "damage", "dps" }) do isPalette(barColor("fast", key), key .. " under the probe skin") end
end)
