-- tests/test_log_page.lua — the Combat Log settings page (CombatTrail #11, plan item CL-11c2; the spec's
-- addendum, *Settings*): the eight tabs, a row for every `log.*` default a player chooses (the detached
-- window's drag-and-grip geometry the only keys without one), every row's default the profile's, the
-- drawer's and the window's own controls writing through rows now (no `log.*` key left on the
-- write-through list), the value checks, the rows' height and text size reaching all three homes, the
-- who colors' overrides, the detached window's gear opening this page, and the page's Defaults. Runs
-- under both kit profiles.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil = T.test, T.assertEqual, T.assertTrue, T.assertFalse,
    T.assertNil
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

-- The detached window's geometry: chosen by its drag and its grip alone, written raw (settings/Log.lua).
local GEOMETRY = { ["log.window.position"] = true, ["log.window.width"] = true, ["log.window.height"] = true }

local function shownPage(opts)
    local inst = T.load(opts)
    inst.mocks.__subcategories["Combat Log"]:__fire("OnShow")
    local ctx = inst.NS.pageCtx.log
    ctx.panel:Show()
    return inst, ctx
end

-- Every leaf under `t`, a color table counted as one leaf.
local function leaves(t, prefix, out)
    for k, v in pairs(t) do
        local path = prefix .. "." .. k
        if type(v) == "table" and v.r == nil and not GEOMETRY[path] then leaves(v, path, out)
        elseif not GEOMETRY[path] then out[#out + 1] = path end
    end
    return out
end

test("log page: eight tabs, Combat Log first and Results last", function()
    local inst, ctx = shownPage()
    local NS = inst.NS
    assertEqual(table.concat(NS.LOG_TAB_ORDER, ","), "log,drawer,window,display,show,colors,store,results")
    local want = {}
    for i, key in ipairs(NS.LOG_TAB_ORDER) do want[i] = NS.LOG_TABS[key] end
    local _, keys = NS.Helpers.RenderTabbedSchema(ctx, "log")
    assertEqual(table.concat(keys or {}, ","), table.concat(want, ","))
    assertEqual(table.concat(want, ","),
        "Combat Log,Docked drawer,Detached window,Order and display,What to show,Colors,Storage,Results")
end)

test("log page: every log.* default but the window's geometry has a control", function()
    local NS = T.load().NS
    local paths = leaves(NS.defaults.profile.log, "log", {})
    assertTrue(#paths > 45, "the log's leaves (47 since the Combat Sequence dropped eleven): " .. #paths)
    local missing = {}
    for _, path in ipairs(paths) do
        local row = NS.FindSchemaRow(path)
        if not row then missing[#missing + 1] = path
        else
            assertEqual(row.page, "log", path)
            assertTrue(type(row.group) == "string" and row.group ~= "", path .. " has a tab")
        end
    end
    table.sort(missing)
    assertEqual(table.concat(missing, ", "), "", "log keys with no row")
    for path in pairs(GEOMETRY) do assertNil(NS.FindSchemaRow(path), path .. " is the drag's and the grip's") end
    local errors, _, unresolved = NS.ValidateSchema()
    assertEqual(errors, 0)
    assertEqual(unresolved, 0)
end)

test("log page: every row's default is the profile's (defaults/Profile.lua is the only source)", function()
    local NS = T.load().NS
    for _, row in ipairs(NS.SchemaForPage("log")) do
        local want = NS.defaults.profile
        for part in row.path:gmatch("[^.]+") do want = want[part] end
        if type(want) == "table" then
            for k, v in pairs(want) do assertEqual(row.default[k], v, row.path .. "." .. k) end
        else
            assertEqual(row.default, want, row.path)
        end
    end
end)

test("log page: no log.* key is left on the write-through list; the log's own controls write rows", function()
    local NS = T.load().NS
    for _, p in ipairs(NS.SCHEMA_WRITE_THROUGH) do
        assertFalse(p:find("^log%.") ~= nil, p .. " has a row now")
    end
    for _, p in ipairs({ "log.drawer.shown", "log.drawer.chips", "log.view.sort", "log.home" }) do
        assertTrue(NS.FindSchemaRow(p) ~= nil, p .. " has a row")
    end
    -- red under: the rows of the retired keys (owner feedback items 3, 11 and 14)
    for _, p in ipairs({ "log.drawer.collapsed", "log.drawer.strip", "log.view.columns.source",
                         "log.view.columns.target", "log.window.attached", "log.window.pinned",
                         "log.window.side", "log.window.matchHud" }) do
        assertTrue(NS.FindSchemaRow(p) == nil, p .. " has no row")
    end
    NS.HudLog.SetHome("detached")
    assertEqual(NS.GetSetting("log.home"), "detached", "the detach mark writes through its row")
    NS.HudLog.ToggleChipsRow()
    assertFalse(NS.GetSetting("log.drawer.chips"), "the eye writes through its row")
end)

test("log page: the value checks refuse what the log cannot draw", function()
    local NS = T.load().NS
    assertFalse(NS.SetByPath("log.home", "floating"))
    assertTrue(NS.SetByPath("log.home", "detached"))
    assertFalse(NS.SetByPath("log.view.sort", "random"))
    assertTrue(NS.SetByPath("log.view.sort", "oldest"))
    assertFalse(NS.SetByPath("log.view.throttle", "sometimes"))
    assertTrue(NS.SetByPath("log.view.throttle", "batch"))
    assertFalse(NS.SetByPath("log.view.timeFormat", "server"))
    assertTrue(NS.SetByPath("log.view.timeFormat", "clock"))
    local function range(p) local r = NS.FindSchemaRow(p); return r.min .. "-" .. r.max end
    assertEqual(range("log.drawer.rows"), "3-20")
    assertEqual(range("log.window.rows"), "3-40")
    assertEqual(range("log.view.throttleMs"), "50-1000")
    assertEqual(range("log.store.lines"), "100-1000")
    assertEqual(range("log.view.fontSize"), "8-16")
    assertEqual(range("log.view.rowHeight"), "12-28")
end)

test("log page: the dependent rows gray out on what they need, and no color row ever does", function()
    local NS = T.load().NS
    local function off(p) return NS.FindSchemaRow(p).disabledIf() end
    assertTrue(off("log.window.rows"), "fill on: the rows are the height's")
    NS.SetByPath("log.window.fill", false)
    assertFalse(off("log.window.rows"))
    assertTrue(off("log.view.throttleMs"), "instant: no N")
    NS.SetByPath("log.view.throttle", "every")
    assertFalse(off("log.view.throttleMs"))
    for _, r in ipairs(NS.SchemaForPage("log")) do
        if r.type == "color" then assertNil(r.disabledIf, r.path .. " is never disabled (options-ui-§17)") end
    end
end)

test("log page: every tab renders without printing", function()
    local inst, ctx = shownPage()
    local NS, M = inst.NS, inst.mocks
    M.__resetPrinted()
    for _, key in ipairs(NS.LOG_TAB_ORDER) do
        NS.Helpers.SelectTab("log", NS.LOG_TABS[key])
        assertEqual(ctx.activeTab, NS.LOG_TABS[key])
    end
    assertEqual(#M.__printed(), 0, "a render printed: " .. tostring(M.__printed()[1]))
end)

-- ── the sizes reach the homes ───────────────────────────────────────────────────────────────────

local function hudUp(NS)
    NS.Hud.Show()
    NS.HudLog.SetShown(true)
    return NS.HudLog.__ui()
end

test("log page: the row height sizes the drawer, the HUD grows with it, and each row takes it", function()
    local inst = T.load{ mutate = installPaint }
    local NS = inst.NS
    local d = hudUp(NS)
    local before, hud = NS.HudLog.Height(), NS.Hud.Height()
    assertEqual(NS.LogTable.RowH(), 14, "14 px by default")
    assertTrue(NS.SetByPath("log.view.rowHeight", 20))
    assertEqual(NS.LogTable.RowH(), 20)
    assertEqual(NS.HudLog.Height(), before + 6 * NS.HudLog.Rows(), "six more pixels a row")
    assertEqual(NS.Hud.Height(), hud + 6 * NS.HudLog.Rows(), "the HUD grew by them")
    assertEqual(NS.LogTable.Height(8), NS.LogTable.HEAD_H + 8 * 20)
    assertEqual(d.table.rowH, 20, "the rows are laid at the height")
    local second = d.table:Rows()[2]
    local sized
    for _, r in ipairs(d.table:Rows()) do rawset(r, "SetHeight", function(_, h) sized = h end) end
    NS.SetByPath("log.view.rowHeight", 22)
    assertEqual(sized, 22, "each row is drawn at the height")
    assertTrue(second ~= nil, "a second row")
    NS.db.profile.log.view.rowHeight = 99
    assertEqual(NS.LogTable.RowH(), 28, "held to 28")
    NS.db.profile.log.view.rowHeight = 2
    assertEqual(NS.LogTable.RowH(), 12, "and to 12")
end)

test("log page: the text size sets the rows' face, widens the fixed columns and the icon", function()
    local inst = T.load{ mutate = installPaint }
    local NS = inst.NS
    local LT = NS.LogTable
    local d = hudUp(NS)
    local first = d.table:Rows()[1]
    assertEqual(LT.FontScale(), 1, "10 points: the body text's own")
    local _, size = first.text.time:GetFont()
    assertTrue(size ~= 14, "not yet 14")
    assertTrue(NS.SetByPath("log.view.fontSize", 14))
    assertEqual(LT.FontScale(), 1.4)
    local row = d.table:Rows()[1]
    assertTrue(row ~= first, "a new size is a new pool of rows")
    assertFalse(first:IsShown(), "the old size's rows hidden")
    _, size = row.text.time:GetFont()
    assertTrue(size ~= nil and math.abs(size - 14) < 1e-6, "14 points: " .. tostring(size))
    local narrow, wide = LT.Columns(600, {}, true, 1), LT.Columns(600, {}, true, 1.4)
    assertEqual(narrow[1].w, LT.WIDTH.time)
    assertEqual(wide[1].w, math.floor(LT.WIDTH.time * 1.4 + 0.5), "the Time column widens with the text")
    assertEqual(LT.IconSize(14, 1), 12, "the icon at its own size")
    assertEqual(LT.IconSize(14, 1.4), 12, "never taller than the row")
    assertEqual(LT.IconSize(24, 1.4), 17)
    assertTrue(NS.SetByPath("log.view.fontSize", 10))
    assertTrue(d.table:Rows()[1] == first, "back on the first pool, its labels at their own size")
    assertFalse(row:IsShown(), "the 14-point rows hidden")
end)

test("log page: the detached window's rows follow the row height", function()
    local inst = T.load{ mutate = installPaint }
    local NS = inst.NS
    NS.SetByPath("log.window.fill", false)
    local short = NS.LogWindow.WindowHeight()
    NS.SetByPath("log.view.rowHeight", 20)
    assertEqual(NS.LogWindow.WindowHeight(), short + 6 * NS.LogWindow.RowsSetting(), "its height is its rows'")
end)

-- ── the who colors ──────────────────────────────────────────────────────────────────────────────

test("log page: the who colors are still read into a view's context, and no cell draws them now", function()
    local NS = T.load().NS
    local LT, U, K = NS.LogTable, NS.CombatLog.UNIT, NS.CombatLog.KIND
    local onTarget = { k = K.DEBUFF_ON, u = U.target, id = 118, at = 105 }
    local ctx = LT.ReadColors({ startT = 100 })
    assertNil(ctx.youColor, "the class color by default")
    assertNil(ctx.hostileColor, "the skin's hostile color by default")
    NS.SetByPath("log.colors.you", { r = 0.1, g = 0.2, b = 0.3, a = 1 })
    NS.SetByPath("log.colors.useClassColorYou", false)
    NS.SetByPath("log.colors.hostile", { r = 0.4, g = 0.5, b = 0.6, a = 1 })
    NS.SetByPath("log.colors.hostileFromSkin", false)
    LT.ReadColors(ctx)
    assertEqual(table.concat({ ctx.youColor[1], ctx.youColor[2], ctx.youColor[3] }, ","), "0.1,0.2,0.3")
    assertEqual(table.concat({ ctx.hostileColor[1], ctx.hostileColor[2], ctx.hostileColor[3] }, ","), "0.4,0.5,0.6")
    local c = LT.Cells(onTarget, ctx)
    assertNil(c.targetColor, "no Target column draws them (owner feedback item 3)")
    assertNil(c.sourceColor)
end)

test("log page: You is a ColorPair with its class companion on; the targets are a palette, no class", function()
    local NS = T.load().NS
    local you = NS.FindSchemaRow("log.colors.you")
    assertEqual(you.type, "color")
    assertEqual(you.classColorSource, "player")
    assertEqual(NS.FindSchemaRow("log.colors.useClassColorYou").default, true, "the class color, as it shipped")
    assertNil(NS.FindSchemaRow("log.colors.youFromSkin"), "a class color takes no skin companion")
    assertNil(NS.FindSchemaRow("log.colors.useClassColorHostile"), "a reaction's color has no class")
    assertEqual(NS.FindSchemaRow("log.colors.hostileFromSkin").default, true, "it starts on the skin")
end)

-- ── the ways in and the reset ───────────────────────────────────────────────────────────────────

test("log page: the detached window's gear opens the settings on this page", function()
    local inst = T.load{ mutate = installPaint }
    local NS = inst.NS
    local opened
    NS.Helpers.OpenOptionsPanel = function(key) opened = key end
    NS.Hud.Show()
    NS.HudLog.SetHome("detached")
    NS.HudLog.SetShown(true)
    local ui = NS.LogWindow.__ui()
    assertTrue(ui ~= nil and ui.settings ~= nil, "the window's gear")
    ui.settings:GetScript("OnClick")(ui.settings, "LeftButton")
    assertEqual(opened, "log")
end)

test("log page: /ct set reaches a log path", function()
    local NS = T.load().NS
    NS.Slash:OnSlash("set log.drawer.rows 12")
    assertEqual(NS.GetSetting("log.drawer.rows"), 12)
    NS.Slash:OnSlash("set log.view.throttle every")
    assertEqual(NS.GetSetting("log.view.throttle"), "every")
end)

test("log page: the page's Defaults puts every log row back and leaves the geometry", function()
    local inst, ctx = shownPage()
    local NS = inst.NS
    NS.SetByPath("log.drawer.rows", 15)
    NS.SetByPath("log.view.sort", "oldest")
    NS.SetByPath("log.store.categories.playerBuffs", false)
    NS.SetByPath("log.colors.hostile", { r = 0, g = 1, b = 0, a = 1 })
    NS.db.profile.log.window.width = 600
    NS.SetByPath("general.locked", true)
    ctx.panel.defaultsOnClick()
    local log, D = NS.db.profile.log, NS.defaults.profile.log
    assertEqual(log.drawer.rows, D.drawer.rows)
    assertEqual(log.view.sort, "newest")
    assertEqual(log.store.categories.playerBuffs, true)
    assertEqual(log.colors.hostile.g, D.colors.hostile.g)
    assertEqual(log.window.width, 600, "the grip's width is no row's")
    assertEqual(NS.GetSetting("general.locked"), true, "another page's row is not this page's to reset")
end)
