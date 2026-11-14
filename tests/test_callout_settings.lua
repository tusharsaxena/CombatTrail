-- tests/test_callout_settings.lua — the race call-out's settings on the host's write route (callout
-- plan row C5; LibKa0s-Callout-1.0 at 2.3): the instance's SchemaRows("callout.") registered as Race
-- mode page rows, each declared retail and skipRender; the AceDB defaults seeded from the rows;
-- `callout.point` in the schema's writeThrough; every instance write (a setting, a color, the drag's
-- point, Reset position) through NS.SetByPath; `/ct get|set|reset` and the page's Defaults reaching
-- the rows; the library's settings section drawn as the page's three call-out tabs on the route; and
-- all of it absent on WoW Forever (clients-§4, §6).

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local function forever() return T.NS.Compat.IsForever() end


local function text(M) return table.concat(M.__printed(), "\n") end

--- The call-out's registered rows, by path.
local function calloutRows(NS)
    local out, n = {}, 0
    for _, row in ipairs(NS.Schema) do
        if type(row.path) == "string" and row.path:find("^callout%.") then
            out[row.path], n = row, n + 1
        end
    end
    return out, n
end

--- Record every path NS.SetByPath is handed, then call the real seam.
local function recordWrites(NS)
    local real, writes = NS.SetByPath, {}
    NS.SetByPath = function(path, ...)
        writes[#writes + 1] = path
        return real(path, ...)
    end
    return writes
end

-- ── per client ──────────────────────────────────────────────────────────────────────────────────

test("callout settings: every SchemaRows row is a Race mode row, declared retail, drawn by the section", function()
    if forever() then return end
    local inst = T.load()
    local NS = inst.NS
    local Callout = inst.mocks.LibStub("LibKa0s-Callout-1.0")
    local want, named = NS.Callout:SchemaRows("callout.")
    local got, n = calloutRows(NS)
    assertEqual(n, #want, "one registered row per SchemaRows row")
    assertEqual(#want, 23 + #Callout.KINDS + 2 * #Callout.STOCK_ORDER + 2, "the scalars, colors, texts, mutes and the two session rows")
    for _, w in ipairs(want) do
        local row = got[w.path]
        assertTrue(row ~= nil, w.path .. " is registered")
        assertTrue(NS.FindSchemaRow(w.path) == row, w.path .. " is found by path")
        assertEqual(row.page, "race", w.path)
        assertEqual(table.concat(row.clients or {}, ","), "retail", w.path .. " is declared retail")
        assertTrue(row.skipRender, w.path .. ": the library's section draws it")
        assertEqual(row.group, "callout." .. (w.tab or "look"), w.path .. ": its group is its host tab's key")
    end
    assertEqual(named[1], "callout.point", "the drag's place is the named state")
    assertEqual(named[1], NS.CALLOUT_POINT)
    local listed = false
    for _, p in ipairs(NS.SCHEMA_WRITE_THROUGH) do if p == named[1] then listed = true end end
    assertTrue(listed, "callout.point is the schema's writeThrough")
    assertNil(got["callout.point"], "and has no row: no control chooses it")
end)

test("callout settings: absent on WoW Forever, no row, default or writeThrough path", function()
    if not forever() then return end
    local NS = T.load().NS
    local _, n = calloutRows(NS)
    assertEqual(n, 0, "no call-out row on WoW Forever")
    assertNil(NS.defaults.profile.callout, "no call-out default")
    for _, p in ipairs(NS.SCHEMA_WRITE_THROUGH) do
        assertFalse(p == "callout.point", "callout.point is not written through on WoW Forever")
    end
    assertFalse(NS.SetByPath("callout.point", { "CENTER", "CENTER", 0, 0 }), "nothing stores it")
end)

-- ── the defaults ────────────────────────────────────────────────────────────────────────────────

test("callout settings: the defaults are seeded from the rows, and the schema validates against them", function()
    if forever() then return end
    local NS = T.load().NS
    local SchemaLib = NS.__schemaLib
    local D = NS.defaults.profile
    assertTrue(type(D.callout) == "table", "profile.callout is seeded")
    for path, row in pairs((calloutRows(NS))) do
        if row.sessionOnly then
            assertNil(SchemaLib.Read(D, path), path .. ": a session row stores nothing")
        else
            assertTrue(SchemaLib.SameValue(SchemaLib.Read(D, path), row.default), path .. " is seeded with its row's default")
            assertTrue(SchemaLib.SameValue(NS.GetSetting(path), row.default), path .. " reads its default")
        end
    end
    assertEqual(table.concat(D.callout.point, ","), "CENTER,CENTER,0,180", "the default place")
    assertEqual(D.callout.colors.go.r, 0.3, "a color in the panel's named shape")
    assertEqual(D.callout.texts.READY, "", "a stock key's own text, none")
    assertEqual(D.callout.muted.STOP, false, "and its mute, off")
    local errors, _, missing = NS.ValidateSchema()
    assertEqual(errors, 0)
    assertEqual(missing, 0)
    assertEqual(NS.Callout:Get("size"), 96, "the instance reads the seeded profile")
end)

-- ── the write route ─────────────────────────────────────────────────────────────────────────────

test("callout settings: every instance write goes through NS.SetByPath, under callout.", function()
    if forever() then return end
    local NS = T.load().NS
    local writes = recordWrites(NS)
    local co = NS.Callout
    assertTrue(co:Set("size", 120))
    assertEqual(writes[#writes], "callout.size")
    assertEqual(NS.db.profile.callout.size, 120, "stored by the seam")
    assertTrue(co:Set("texts.GO", "Now!"))
    assertEqual(writes[#writes], "callout.texts.GO")
    assertEqual(NS.db.profile.callout.texts.GO, "Now!")
    assertTrue(co:SetColor("stop", 0.5, 0.25, 1))
    assertEqual(writes[#writes], "callout.colors.stop")
    local c = NS.db.profile.callout.colors.stop
    assertEqual(table.concat({ NS.ColorDecode(c) }, ","), "0.5,0.25,1,1", "in the panel's codec")
    assertFalse(co:Set("size", 999), "a size the row refuses")
    assertEqual(NS.db.profile.callout.size, 120, "and nothing stored")
end)

test("callout settings: a drag's point and Reset position are written through NS.SetByPath", function()
    if forever() then return end
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    local writes = recordWrites(NS)
    local co = NS.Callout
    co:SetLocked(false)
    local f = assert(co:Frame())
    f:__fire("OnDragStart")
    -- Where the client answers the frame stands once the player has moved it.
    rawset(f, "GetPoint", function() return "TOPLEFT", M.UIParent, "TOPLEFT", 40, -60 end)
    f:__fire("OnDragStop")
    assertEqual(writes[#writes], "callout.point", "the drag wrote through the seam")
    assertEqual(NS.db.profile.callout.point[1], "TOPLEFT")
    assertEqual(NS.db.profile.callout.point[4], -60)
    co:SetLocked(true)
    co:ResetPosition()
    assertEqual(writes[#writes], "callout.point")
    assertEqual(table.concat(NS.db.profile.callout.point, ","), "CENTER,CENTER,0,180", "back on the default place")
end)

-- ── the slash command and the resets ────────────────────────────────────────────────────────────

test("callout settings: /ct set, get and reset reach a call-out row", function()
    if forever() then return end
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    NS.Slash:OnSlash("set callout.size 150")
    assertEqual(NS.db.profile.callout.size, 150, "set: " .. text(M))
    assertEqual(NS.Callout:Get("size"), 150, "the call-out reads it")
    NS.Slash:OnSlash("set callout.voice male")
    assertEqual(NS.Callout:Get("voice"), "male", "a list row")
    NS.Slash:OnSlash("set callout.muted.STOP true")
    assertTrue(NS.Callout:Get("muted.STOP"), "a stock key's mute")
    M.__resetPrinted()
    NS.Slash:OnSlash("get callout.size")
    assertTrue(text(M):find("150", 1, true) ~= nil, "get: " .. text(M))
    NS.Slash:OnSlash("reset callout.size")
    assertEqual(NS.GetSetting("callout.size"), 96, "reset: back to the row's default")
    M.__resetPrinted()
    NS.Slash:OnSlash("set callout.voice nobody")
    assertEqual(NS.GetSetting("callout.voice"), "male", "a voice that is none stores nothing: " .. text(M))
    M.__resetPrinted()
    NS.Slash:OnSlash("list")
    assertTrue(text(M):find("callout.texts.READY", 1, true) ~= nil, "list names the call-out's rows")
end)

test("callout settings: the Race mode page's Defaults and a profile reset put the call-out back", function()
    if forever() then return end
    local inst = T.load()
    local NS = inst.NS
    assertTrue(NS.SetByPath("callout.size", 140))
    assertTrue(NS.SetByPath("callout.colors.go", { r = 0, g = 0, b = 1, a = 1 }))
    assertTrue(NS.SetByPath("callout.texts.STOP", "HALT"))
    inst.mocks.__subcategories["Race mode"]:__fire("OnShow")
    NS.Helpers.RestoreDefaults("race", NS.pageCtx.race)
    assertEqual(NS.GetSetting("callout.size"), 96)
    assertEqual(NS.GetSetting("callout.colors.go").r, 0.3)
    assertEqual(NS.GetSetting("callout.texts.STOP"), "")
    assertTrue(NS.SetByPath("callout.size", 140))
    NS.db:ResetProfile()
    assertEqual(NS.Callout:Get("size"), 96, "a profile reset restores the seeded default")
end)

-- ── the section ─────────────────────────────────────────────────────────────────────────────────

test("callout settings: the Race mode page draws the call-out's three tabs after Race", function()
    if forever() then return end
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    M.__resetPrinted()
    M.__subcategories["Race mode"]:__fire("OnShow")
    assertEqual(#M.__printed(), 0, "the render printed: " .. text(M))
    local ctx = NS.pageCtx.race
    local _, keys = NS.Helpers.RenderTabbedSchema(ctx, "race", nil, nil, { tabs = NS.Callout:SettingsTabs({ options = NS.Helpers }) })
    assertEqual(table.concat(keys or {}, ","),
        "Race,callout.look,callout.sound,callout.texts,Late-cast ignore list,Race window")
end)

test("callout settings: each call-out tab is built by the library's section on the host's route", function()
    if forever() then return end
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    local co, views = NS.Callout, {}
    local real = co.BuildSettings
    co.BuildSettings = function(self, parent, opts)
        local view = real(self, parent, opts)
        views[#views + 1] = { view = view, opts = opts }
        return view
    end
    M.__subcategories["Race mode"]:__fire("OnShow")
    assertTrue(NS.pageCtx.race ~= nil, "the page is built")
    for _, tab in ipairs({ "look", "sound", "texts" }) do
        assertTrue(NS.Helpers.SelectTab("race", "callout." .. tab), tab .. ": the tab is selected")
        M.__subcategories["Race mode"]:__fire("OnShow")   -- a hidden page repaints on its next show
        local last = views[#views]
        assertTrue(last ~= nil, tab .. ": the section built")
        assertEqual(last.opts.tab, tab)
        assertTrue(last.opts.options == NS.Helpers, tab .. ": with the addon's Options instance")
        assertEqual(last.view.kind, "options", tab)
        assertEqual(last.view.prefix, "callout.", tab .. ": on the host's route")
        assertTrue(#last.view.rows > 0, tab .. " draws rows")
        for _, r in ipairs(last.view.rows) do
            assertTrue(NS.FindSchemaRow(r.path) ~= nil, tostring(r.path) .. " is a registered row")
        end
    end
    -- A path the section draws is written by the Options descriptor's set, which is the seam.
    local writes = recordWrites(NS)
    assertTrue(NS.SetByPath("callout.hold", 3))
    assertEqual(writes[#writes], "callout.hold")
    assertEqual(co:Get("hold"), 3)
end)
