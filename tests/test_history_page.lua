-- tests/test_history_page.lua — the History settings page (plan Task 4.5, spec §5, §7 and §8, the
-- mockup's History tabs): the five tabs (the Training dummies tab's body is tests/test_dummies.lua's),
-- a row for every `history.*` key the recorder, the filters, the retention and the bests read, the
-- Results window's settings (its scale reaching every follower, its row height reaching the list), the
-- Usage tab's "never show" list as the library's ID list, the History tab's stored count and size and
-- its Purge history… behind a confirmation, no Retail-only trace on WoW Forever, the words
-- options-ui-§7/§21 fix, and the page's Defaults.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")
local installIds = dofile(T.root .. "/tests/_kit/mock_ids.lua")

local DAY = 86400

-- A fresh instance whose StaticPopup_Show records what it was asked.
local function withPopups(extra)
    return function(m)
        m.__popups = {}
        m.StaticPopup_Show = function(name, _, _, data) m.__popups[#m.__popups + 1] = { name = name, data = data } end
        if extra then extra(m) end
    end
end

--- The History page, built and on screen.
local function shownPage(opts)
    local inst = T.load(opts)
    inst.mocks.__subcategories["History"]:__fire("OnShow")
    local ctx = inst.NS.pageCtx.history
    ctx.panel:Show()
    return inst, ctx
end

local function walk(w, out)
    for _, child in ipairs(w.children or {}) do
        out[#out + 1] = child
        walk(child, out)
    end
    return out
end

local function widget(inst, ctx, label)
    for _, w in ipairs(walk(ctx.scroll, {})) do
        if w.labelText == inst.NS.L[label] or w.text == inst.NS.L[label] then return w end
    end
end

local function anyText(_, ctx, needle)
    for _, w in ipairs(walk(ctx.scroll, {})) do
        for _, s in ipairs({ w.text, w.labelText }) do
            if type(s) == "string" and s:find(needle, 1, true) then return true end
        end
    end
    return false
end

local function leaves(t, prefix, out)
    for k, v in pairs(t) do
        local path = prefix .. "." .. k
        if type(v) == "table" and v.r == nil then leaves(v, path, out) else out[#out + 1] = path end
    end
    return out
end

local n = 0
local function rec(t, o)
    n = n + 1
    o = o or {}
    return {
        schema = 1, id = "h-" .. n, t = t, duration = 60, status = "final",
        who = { name = "Tush", realm = "Area 52", client = "retail", specID = 63 },
        identity = { content = "world", targetName = "Boar" }, boardKey = o.boardKey, dps = o.dps or 100,
    }
end

local function stored(NS)
    local c = 0
    for _ in pairs(NS.db.global.fights) do c = c + 1 end
    return c
end

test("history page: five tabs, Recording filters first and Training dummies last", function()
    local inst, ctx = shownPage()
    local NS = inst.NS
    assertEqual(table.concat(NS.HISTORY_TAB_ORDER, ","), "recording,retention,results,usage,dummies")
    local want = {}
    for i, key in ipairs(NS.HISTORY_TAB_ORDER) do want[i] = NS.HISTORY_TABS[key] end
    assertEqual(table.concat(want, ","), "Recording filters,History,Results window,Usage,Training dummies")
    -- The label is the standard's (plan D6); the internal key stays `retention`.
    assertEqual(NS.HISTORY_TABS.retention, "History")
    local _, keys = NS.Helpers.RenderTabbedSchema(ctx, "history")
    assertEqual(table.concat(keys or {}, ","), table.concat(want, ","))
    assertFalse(anyText(inst, ctx, NS.L["The History settings arrive with the fight history."]),
        "the placeholder notice is gone")
end)

test("history page: every history.* key, the Results window's settings and the hidden list have a row", function()
    local NS = T.load().NS
    local paths = leaves(NS.defaults.profile.history, "history", {})
    for _, p in ipairs({ "results.scale", "results.shareTalents", "results.rowHeight", "results.closeInCombat",
                        "results.timelineMarks", NS.Usage.HIDDEN_PATH }) do
        paths[#paths + 1] = p
    end
    local missing = {}
    for _, path in ipairs(paths) do
        local row = NS.FindSchemaRow(path)
        if not row then missing[#missing + 1] = path
        else
            assertEqual(row.page, "history", path)
            assertTrue(type(row.group) == "string" and row.group ~= "", path .. " has a tab")
        end
    end
    table.sort(missing)
    assertEqual(table.concat(missing, ", "), "", "keys with no row")
    -- The window's place, size and fold, and its saved view, are window state (architecture-§5's
    -- named non-setting state): no control sets them, so no row addresses them.
    for _, p in ipairs({ "results.view", "results.view.group", "results.window", "results.window.width",
                        "results.columns", "results.columns.character", "results.collapsedSections",
                        "results.collapsedSections.spells" }) do
        assertNil(NS.FindSchemaRow(p), p .. " is window state")
    end
    local errors, _, unresolved = NS.ValidateSchema()
    assertEqual(errors, 0)
    assertEqual(unresolved, 0)
end)

test("history page: the rows sit on their tabs, the hidden list on Usage", function()
    local NS = T.load().NS
    local TAB = NS.HISTORY_TABS
    local function tab(p) return NS.FindSchemaRow(p).group end
    assertEqual(tab("history.minLength"), TAB.recording)
    assertEqual(tab("history.bossesOnly"), TAB.recording)
    assertEqual(tab("history.content.raid"), TAB.recording)
    assertEqual(tab("history.days"), TAB.retention)
    assertEqual(tab("history.keepBests"), TAB.retention)
    assertEqual(tab("history.maxFights"), TAB.retention)
    assertEqual(tab("results.scale"), TAB.results)
    assertEqual(tab("results.rowHeight"), TAB.results)
    assertEqual(tab("results.shareTalents"), TAB.results)
    assertEqual(tab("results.closeInCombat"), TAB.results)
    assertEqual(tab("results.timelineMarks"), TAB.results)
    local hidden = NS.FindSchemaRow(NS.Usage.HIDDEN_PATH)
    assertEqual(hidden.group, TAB.usage)
    assertTrue(hidden.skipRender, "drawn as the ID list, not as a text box")
    assertTrue(hidden.tooltip:find("^" .. NS.L["Account-wide: shared by every profile."]:gsub("%p", "%%%0")) ~= nil,
        "an account-wide row says so first (options-ui-§21)")
end)

test("history page: every row's default is the shipped one (defaults/Profile.lua is the only source)", function()
    local NS = T.load().NS
    for _, row in ipairs(NS.SchemaForPage("history")) do
        if row.path then
            local parts, root = {}, NS.defaults.profile
            for part in row.path:gmatch("[^.]+") do parts[#parts + 1] = part end
            if parts[1] == "global" then root = NS.defaults.global; table.remove(parts, 1) end
            for _, part in ipairs(parts) do root = root[part] end
            assertEqual(row.default, root, row.path)
        end
    end
end)

test("history page: forever: no delve/arena/mplus rows", function()
    local NS = T.load().NS
    local mplus = NS.FindSchemaRow("history.content.mplus")
    local delve = NS.FindSchemaRow("history.content.delve")
    local arena = NS.FindSchemaRow("history.content.arena")
    for _, key in ipairs({ "raid", "dungeon", "bg", "world", "dummy", "scenario" }) do
        assertTrue(NS.FindSchemaRow("history.content." .. key) ~= nil, key .. " on every client")
    end
    if NS.Compat.IsForever() then
        assertNil(mplus)
        assertNil(delve)
        assertNil(arena)
        -- No trace on WoW Forever, tooltips and the page's own lines included (clients-§4).
        for _, r in ipairs(NS.SchemaForPage("history")) do
            local words = ((r.label or "") .. " " .. (type(r.tooltip) == "string" and r.tooltip or "")):lower()
            for _, retailOnly in ipairs({ "delve", "mythic+", "arena", "keystone", "spec" }) do
                assertFalse(words:find(retailOnly, 1, true) ~= nil, tostring(r.path) .. " names " .. retailOnly)
            end
        end
        local purge = NS.HistoryPage.PURGE_TOOLTIP():lower()
        assertFalse(purge:find("spec", 1, true) ~= nil, "the purge tooltip names no spec")
    else
        for _, r in ipairs({ mplus, delve, arena }) do
            assertTrue(r ~= nil)
            assertEqual(table.concat(r.clients, ","), "retail")
        end
    end
end)

test("history page: a content row stores its kind and the filter follows", function()
    local NS = T.load().NS
    local world = { content = "world", targetName = "Boar" }
    assertTrue((NS.Filters.Passes(world, 60)))
    assertTrue(NS.SetByPath("history.content.world", false))
    assertFalse((NS.Filters.Passes(world, 60)), "open world is no longer stored")
    assertTrue(NS.SetByPath("history.minLength", 90))
    assertTrue(NS.SetByPath("history.content.world", true))
    local ok, why = NS.Filters.Passes(world, 60)
    assertFalse(ok)
    assertEqual(why, "short")
    assertFalse(NS.SetByPath("history.minLength", -5), "a negative length is refused")
    assertFalse(NS.SetByPath("history.maxFights", 99999), "past the slider's range is refused")
end)

test("history page: the History tab shows the stored count and size", function()
    local inst, ctx = shownPage()
    local NS = inst.NS
    local now = os.time()
    for i = 1, 3 do NS.Recorder.Save(rec(now - i * 60)) end
    local line = NS.HistoryPage.StoredLine()
    assertTrue(line:find("3 fights", 1, true) ~= nil, line)
    assertTrue(line:find(NS.HistoryPage.SizeText(NS.Retention.EstimateBytes()), 1, true) ~= nil, line)
    assertEqual(NS.HistoryPage.SizeText(512), "512 bytes")
    assertEqual(NS.HistoryPage.SizeText(2048), "2.0 KB")
    assertEqual(NS.HistoryPage.SizeText(3 * 1024 * 1024), "3.0 MB")
    NS.Recorder.Delete(NS.db.global.fightOrder[1])
    assertTrue(NS.HistoryPage.StoredLine():find("2 fights", 1, true) ~= nil)
    NS.Recorder.Delete(NS.db.global.fightOrder[1])
    assertTrue(NS.HistoryPage.StoredLine():find("1 fight", 1, true) ~= nil, "one fight, singular")
    NS.Helpers.SelectTab("history", NS.HISTORY_TABS.retention)
    assertTrue(anyText(inst, ctx, NS.HistoryPage.StoredLine()), "the line is drawn on the tab")
    assertTrue(widget(inst, ctx, "Purge history\226\128\166") ~= nil, "Purge history… is drawn")
    assertNil(widget(inst, ctx, "Purge now\226\128\166"), "the old label is gone")
end)

test("history page: purge now confirm", function()
    local inst = T.load({ mutate = withPopups() })
    local NS, M = inst.NS, inst.mocks
    local now = os.time()
    local old = rec(now - 30 * DAY)
    local recent = rec(now - DAY)
    NS.Recorder.Save(old)
    NS.Recorder.Save(recent)
    NS.HistoryPage.ConfirmPurge()
    assertEqual(M.__popups[#M.__popups].name, NS.HistoryPage.POPUP, "it asks first")
    assertEqual(stored(NS), 2, "nothing is removed before the answer")
    local dialog = M.StaticPopupDialogs[NS.HistoryPage.POPUP]
    assertTrue(dialog.text:find("\226\128\148", 1, true) == nil, "no em dash in the question")
    M.__resetPrinted()
    dialog.OnAccept()
    assertNil(NS.db.global.fights[old.id], "the old fight went")
    assertTrue(NS.db.global.fights[recent.id] ~= nil, "a recent one stays")
    assertTrue(#M.__printed() == 1, "one line says what went")
end)

test("history page: the Usage tab draws the hidden items as the ID list", function()
    local inst, ctx = shownPage({ mutate = installIds })
    local NS, M = inst.NS, inst.mocks
    M.addIdRecord("item", 5512, "Healthstone", 538745)
    NS.Helpers.SelectTab("history", NS.HISTORY_TABS.usage)
    assertTrue(widget(inst, ctx, "Hide an item") ~= nil, "the add box is drawn")
    assertTrue(NS.Usage.Hide(5512))
    assertEqual(NS.GetSetting(NS.Usage.HIDDEN_PATH), "5512")
    assertTrue(NS.Usage.Unhide(5512))
    assertEqual(NS.GetSetting(NS.Usage.HIDDEN_PATH), "")
end)

test("history page: Window scale reaches the Results window and every follower", function()
    local inst = T.load({ mutate = installPaint })
    local NS = inst.NS
    local called = {}
    for _, name in ipairs({ "ResultsTimeline", "ResultsGear", "ResultsCompare" }) do
        local mod = NS[name]
        local real = mod.ApplyScale
        mod.ApplyScale = function(...) called[name] = (called[name] or 0) + 1; return real(...) end
    end
    NS.Results.Show()
    local scaled
    rawset(NS.Results.__ui().frame, "SetScale", function(_, s) scaled = s end)
    assertTrue(NS.SetByPath("results.scale", 1.25))
    assertEqual(scaled, 1.25, "the window takes it at once")
    for _, name in ipairs({ "ResultsTimeline", "ResultsGear", "ResultsCompare" }) do
        assertEqual(called[name], 1, name .. " rescales")
    end
    assertFalse(NS.SetByPath("results.scale", 5), "past the range is refused")
end)

test("history page: Row height reaches the Results list", function()
    local inst = T.load({ mutate = installPaint })
    local NS = inst.NS
    assertEqual(NS.ResultsTable.RowHeight(), NS.defaults.profile.results.rowHeight)
    assertEqual(NS.defaults.profile.results.rowHeight, NS.ResultsTable.ROW_H, "the shipped height is unchanged")
    NS.Recorder.Save(rec(os.time() - 60))
    NS.Results.Show()
    NS.Results.__ui().list:ApplyView({ character = "all", days = 0 })
    local list = NS.Results.__ui().list.list
    local row = list.shown[1]
    assertTrue(row ~= nil, "a row is drawn")
    local height
    rawset(row, "SetHeight", function(_, h) height = h end)
    assertTrue(NS.SetByPath("results.rowHeight", 24))
    assertEqual(NS.ResultsTable.RowHeight(), 24)
    assertEqual(list.shown[1], row, "the same pooled row is bound again")
    assertEqual(height, 24, "the drawn row takes the new height")
    assertFalse(NS.SetByPath("results.rowHeight", 4), "too short to draw is refused")
end)

test("history page: the words follow options-ui-§21 and no subsection restates its tab (options-ui-§7)", function()
    local NS = T.load().NS
    for _, r in ipairs(NS.SchemaForPage("history")) do
        local label = r.label or ""
        assertFalse(label:find("(s)", 1, true) ~= nil, label)
        assertFalse(label:find("&", 1, true) ~= nil, label)
        assertFalse(label:find("alpha", 1, true) ~= nil, label)
        local tab, sub = (r.group or ""):lower(), (r.subgroup or ""):lower()
        for stem in sub:gmatch("%a+") do
            assertFalse(#stem > 3 and tab:find(stem, 1, true) ~= nil, "'" .. r.subgroup .. "' restates '" .. r.group .. "'")
        end
    end
    assertTrue(NS.FindSchemaRow("results.rowHeight").label:find("(px)", 1, true) ~= nil, "row height says (px)")
    assertTrue(NS.FindSchemaRow("history.minLength").label:find("(seconds", 1, true) ~= nil, "length says (seconds)")
end)

test("history page: the minimum length tooltip names this client's default", function()
    local NS = T.load().NS
    local want = NS.Compat.IsForever() and 15 or 30
    local tip = NS.FindSchemaRow("history.minLength").tooltip
    assertTrue(type(tip) == "string" and tip:find("default is " .. want .. " seconds", 1, true) ~= nil, tostring(tip))
end)

test("history page: every tab renders without printing", function()
    local inst, ctx = shownPage({ mutate = installIds })
    local NS, M = inst.NS, inst.mocks
    M.__resetPrinted()
    for _, key in ipairs(NS.HISTORY_TAB_ORDER) do
        NS.Helpers.SelectTab("history", NS.HISTORY_TABS[key])
        assertEqual(ctx.activeTab, NS.HISTORY_TABS[key])
    end
    assertEqual(#M.__printed(), 0, "a render printed: " .. tostring(M.__printed()[1]))
end)

test("history page: the page's Defaults puts every row back and leaves the fights", function()
    local inst, ctx = shownPage()
    local NS = inst.NS
    NS.Recorder.Save(rec(os.time() - 60))
    NS.SetByPath("history.days", 30)
    NS.SetByPath("history.content.world", false)
    NS.SetByPath("results.scale", 1.5)
    NS.SetByPath("results.shareTalents", false)
    NS.Usage.Hide(5512)
    NS.SetByPath("hud.width", 400)
    ctx.panel.defaultsOnClick()
    assertEqual(NS.GetSetting("history.days"), NS.defaults.profile.history.days)
    assertEqual(NS.GetSetting("history.content.world"), true)
    assertEqual(NS.GetSetting("results.scale"), 1)
    assertEqual(NS.GetSetting("results.shareTalents"), true)
    assertEqual(NS.GetSetting(NS.Usage.HIDDEN_PATH), "", "the hidden list is the page's too")
    assertEqual(NS.GetSetting("hud.width"), 400, "another page's row is not this page's to reset")
    assertEqual(stored(NS), 1, "stored fights are not touched")
end)

test("history page: /ct set reaches a history path", function()
    local NS = T.load().NS
    NS.Slash:OnSlash("set history.days 14")
    assertEqual(NS.GetSetting("history.days"), 14)
    NS.Slash:OnSlash("set history.keepBests false")
    assertEqual(NS.GetSetting("history.keepBests"), false)
end)

test("history page: the keep-bests tooltip names the board's spec, a talent tree on Forever (D5, D11)", function()
    local NS = T.load().NS
    local tip = NS.FindSchemaRow("history.keepBests").tooltip
    if NS.Compat.IsForever() then
        assertTrue(tip:find("one character and talent tree", 1, true) ~= nil, tip)
    else
        assertTrue(tip:find("one character and spec", 1, true) ~= nil, tip)
    end
end)
