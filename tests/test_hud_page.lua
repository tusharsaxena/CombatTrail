-- tests/test_hud_page.lua — the DPS HUD settings page (plan Task 3.3, spec §6 and §8, the mockup's
-- DPS HUD tabs): the six tabs, a row for every `hud.*` default, the composed blocks over the
-- profile's own defaults and skin companions, the words options-ui-§16/§21 and frame-layering-§1
-- fix, the value checks, the page's Defaults, and a change reaching the HUD live through Hud.Apply.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

--- The DPS HUD page, built and on screen.
local function shownPage(opts)
    local inst = T.load(opts)
    inst.mocks.__subcategories["DPS HUD"]:__fire("OnShow")
    local ctx = inst.NS.pageCtx.hud
    ctx.panel:Show()
    return inst, ctx
end

--- Every widget under `w`, depth first.
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

-- Every leaf under the HUD's defaults, a color table counted as one leaf.
local function leaves(t, prefix, out)
    for k, v in pairs(t) do
        local path = prefix .. "." .. k
        if type(v) == "table" and v.r == nil then leaves(v, path, out) else out[#out + 1] = path end
    end
    return out
end

test("hud page: six tabs, Behavior first and Window last", function()
    local inst, ctx = shownPage()
    local NS = inst.NS
    local want = {}
    for i, key in ipairs(NS.HUD_TAB_ORDER) do want[i] = NS.HUD_TABS[key] end
    assertEqual(table.concat(NS.HUD_TAB_ORDER, ","), "behavior,layout,clock,chart,spells,window")
    assertEqual(table.concat(want, ","), "Behavior,Layout,Clock and figures,Damage chart,Spell rows,Window")
    local _, keys = NS.Helpers.RenderTabbedSchema(ctx, "hud")
    assertEqual(table.concat(keys or {}, ","), table.concat(want, ","))
end)

test("hud page: every hud.* default has a control", function()
    local NS = T.load().NS
    local paths = leaves(NS.defaults.profile.hud, "hud", {})
    assertTrue(#paths > 80, "the HUD's leaves: " .. #paths)
    local missing = {}
    for _, path in ipairs(paths) do
        local row = NS.FindSchemaRow(path)
        if not row then missing[#missing + 1] = path
        else
            assertEqual(row.page, "hud", path)
            assertTrue(type(row.group) == "string" and row.group ~= "", path .. " has a tab")
        end
    end
    table.sort(missing)
    assertEqual(table.concat(missing, ", "), "", "hud keys with no row")
    local errors, _, unresolved = NS.ValidateSchema()
    assertEqual(errors, 0)
    assertEqual(unresolved, 0)
end)

test("hud page: every row's default is the profile's (defaults/Profile.lua is the only source)", function()
    local NS = T.load().NS
    for _, row in ipairs(NS.SchemaForPage("hud")) do
        if row.path then
            local want = NS.defaults.profile
            for part in row.path:gmatch("[^.]+") do want = want[part] end
            if type(want) == "table" then
                for k, v in pairs(want) do assertEqual(row.default[k], v, row.path .. "." .. k) end
            else
                assertEqual(row.default, want, row.path)
            end
        end
    end
end)

test("hud page: changes apply live via Hud.Apply", function()
    local inst = T.load({ mutate = installPaint })
    local NS = inst.NS
    local Hud = NS.Hud
    Hud.Show()
    local applied, apply = 0, Hud.Apply
    Hud.Apply = function(...) applied = applied + 1; return apply(...) end
    local stamp = NS.HudAppearance.stamp
    assertTrue(NS.SetByPath("hud.window.alpha", 0.5))
    assertEqual(applied, 1, "one write, one Apply")
    assertTrue(NS.HudAppearance.stamp > stamp, "the look's stamp moved")
    assertTrue(math.abs(Hud.Frame():GetAlpha() - 0.5) < 1e-6, "the window's opacity follows at once")
    assertTrue(NS.SetByPath("hud.window.strata", "HIGH"))
    assertEqual(Hud.Frame():GetFrameStrata(), "HIGH")
    local sized
    rawset(Hud.Frame(), "SetSize", function(_, w) sized = w end)
    assertTrue(NS.SetByPath("hud.width", 360))
    assertEqual(sized, 360, "the window takes the new width")
    assertTrue(NS.SetByPath("hud.window.footer", false))
    assertFalse(Hud.__ui().footLeft:IsShown(), "the footer hides")
    Hud.Apply = apply
end)

test("hud page: a drawn control writes through the seam and the HUD follows", function()
    local inst, ctx = shownPage({ mutate = installPaint })
    local NS = inst.NS
    NS.Hud.Show()
    NS.Helpers.SelectTab("hud", NS.HUD_TABS.window)
    local box = widget(inst, ctx, "Show footer")
    assertTrue(box ~= nil, "the Show footer box is drawn")
    box:__fire("OnValueChanged", false)
    assertEqual(NS.db.profile.hud.window.footer, false)
    assertFalse(NS.Hud.__ui().footLeft:IsShown())
end)

test("hud page: every tab renders without printing", function()
    local inst, ctx = shownPage()
    local NS, M = inst.NS, inst.mocks
    M.__resetPrinted()
    for _, key in ipairs(NS.HUD_TAB_ORDER) do
        NS.Helpers.SelectTab("hud", NS.HUD_TABS[key])
        assertEqual(ctx.activeTab, NS.HUD_TABS[key])
    end
    assertEqual(#M.__printed(), 0, "a render printed: " .. tostring(M.__printed()[1]))
end)

test("hud page: the composed blocks follow the skin with the profile's defaults", function()
    local NS = T.load().NS
    local function row(p) return assert(NS.FindSchemaRow(p), "no row " .. p) end
    -- The clock is the mono role: no outline, and its flags never follow the skin's outline.
    assertEqual(row("hud.clock.fontFlags").default, "")
    assertTrue(row("hud.clock.fontFlags").values["@skin"] == nil, "no From skin on the clock's flags")
    assertEqual(row("hud.clock.fontFromSkin").default, true, "the skin's HUD face, as DPS Race's clock (v0.2 B2)")
    -- The figures and the rows draw the skin's outline by default.
    assertEqual(row("hud.figures.fontFlags").default, "@skin")
    assertEqual(row("hud.spells.fontFlags").default, "@skin")
    assertEqual(row("hud.figures.fontFromSkin").default, true)
    -- Every font block has its text color and shadow companions, every bar its texture's.
    for _, block in ipairs({ "clock", "figures", "spells" }) do
        assertEqual(row("hud." .. block .. ".fontColorFromSkin").type, "bool")
        assertEqual(row("hud." .. block .. ".fontShadowFromSkin").type, "bool")
    end
    for _, block in ipairs({ "chart", "spells" }) do
        assertEqual(row("hud." .. block .. ".barTextureFromSkin").default, true)
        assertEqual(row("hud." .. block .. ".barTexture").dialogControl, "Ka0sMedia_Statusbar")
    end
    -- The backdrop swatches' skin companions are the host's own rows, beside their pair.
    for _, p in ipairs({ "hud.figures.boxBgFromSkin", "hud.figures.boxBorderFromSkin",
                         "hud.window.bgFromSkin", "hud.window.borderFromSkin" }) do
        assertEqual(row(p).type, "bool")
        assertEqual(row(p).default, true)
    end
end)

test("hud page: every color is a ColorPair with its Use class color companion", function()
    local NS = T.load().NS
    local colors = 0
    for _, r in ipairs(NS.SchemaForPage("hud")) do
        if r.type == "color" then
            colors = colors + 1
            local prefix, key = r.path:match("^(.*%.)([^.]+)$")
            local leaf = key == "fontColor" and "Font" or key == "barColor" and "Bar"
                or (key:sub(1, 1):upper() .. key:sub(2))
            local companion = NS.FindSchemaRow(prefix .. "useClassColor" .. leaf)
            assertTrue(companion ~= nil, "no class-color companion beside " .. r.path)
            assertEqual(companion.type, "bool")
            assertEqual(r.classColorSource, "player", r.path .. " describes the player")
            assertTrue(r.disabledIf == nil, r.path .. " is never disabled (anti-pattern #74)")
        end
    end
    assertEqual(colors, 12)
end)

test("hud page: Frame strata offers BACKGROUND to HIGH and never DIALOG (frame-layering-§1)", function()
    local NS = T.load().NS
    local strata = NS.FindSchemaRow("hud.window.strata")
    assertEqual(strata.label, NS.L["Frame strata"])
    assertEqual(strata.subgroup, NS.L["Layer"])
    local offered = {}
    for _, v in ipairs(strata.values) do offered[#offered + 1] = v.value end
    assertEqual(table.concat(offered, ","), "BACKGROUND,LOW,MEDIUM,HIGH")
    assertEqual(strata.tooltip, NS.Helpers.StrataTooltip({ "BACKGROUND", "LOW", "MEDIUM", "HIGH" }))
    assertFalse(NS.SetByPath("hud.window.strata", "DIALOG"), "DIALOG is not a player strata")
    assertTrue(NS.SetByPath("hud.window.strata", "LOW"))
end)

test("hud page: the words follow options-ui-§21: (px), (seconds), never (s)", function()
    local NS = T.load().NS
    local L = NS.L
    for _, r in ipairs(NS.SchemaForPage("hud")) do
        local label = r.label or ""
        assertFalse(label:find("(s)", 1, true) ~= nil, label)
        assertFalse(label:find("alpha", 1, true) ~= nil, label .. " says opacity")
        assertFalse(label:find("&", 1, true) ~= nil, label)
    end
    for _, p in ipairs({ "hud.width", "hud.chart.height", "hud.spells.rowHeight" }) do
        assertTrue(NS.FindSchemaRow(p).label:find("(px)", 1, true) ~= nil, p .. " says (px)")
    end
    for _, p in ipairs({ "hud.fadeAfter", "hud.chart.cooldownMin" }) do
        assertTrue(NS.FindSchemaRow(p).label:find("(seconds", 1, true) ~= nil, p .. " says (seconds)")
    end
    assertTrue(NS.FindSchemaRow("hud.window.title").tooltip:find(L["Needs Show title bar."], 1, true) ~= nil,
        "a dependent row names the row it needs")
end)

test("hud page: no subsection restates its tab (options-ui-§7) and no row names a Retail-only feature (clients-§4)", function()
    local NS = T.load().NS
    for _, r in ipairs(NS.SchemaForPage("hud")) do
        local tab, sub = (r.group or ""):lower(), (r.subgroup or ""):lower()
        assertFalse(sub ~= "" and tab:find(sub, 1, true) ~= nil, "'" .. r.subgroup .. "' restates '" .. r.group .. "'")
        local words = ((r.label or "") .. " " .. (type(r.tooltip) == "string" and r.tooltip or "")):lower()
        for _, retailOnly in ipairs({ "delve", "mythic+", "arena", "keystone" }) do
            assertFalse(words:find(retailOnly, 1, true) ~= nil, r.path .. " names " .. retailOnly)
        end
    end
end)

test("hud page: the value checks refuse what the HUD cannot draw", function()
    local NS = T.load().NS
    assertFalse(NS.SetByPath("hud.show", "sometimes"))
    assertTrue(NS.SetByPath("hud.show", "toggle"))
    assertFalse(NS.SetByPath("hud.paceAgainst", "worst"))
    assertTrue(NS.SetByPath("hud.paceAgainst", "last"))
    assertFalse(NS.SetByPath("hud.position.point", "MIDDLE"))
    assertTrue(NS.SetByPath("hud.position.point", "CENTER"))
    local range = NS.FindSchemaRow("hud.paceRange")
    assertEqual(range.min, 1.1)
    assertEqual(range.max, 2.0)
end)

test("hud page: /ct set reaches a hud path, and hud.show always opens the HUD", function()
    local inst = T.load({ mutate = installPaint })
    local NS = inst.NS
    NS.Slash:OnSlash("set hud.chart.height 120")
    assertEqual(NS.GetSetting("hud.chart.height"), 120)
    assertFalse(NS.Hud.IsShown())
    NS.Slash:OnSlash("set hud.show always")
    assertTrue(NS.Hud.IsShown(), "always opens it now")
end)

test("hud page: the page's Defaults puts every hud row back", function()
    local inst, ctx = shownPage()
    local NS = inst.NS
    NS.SetByPath("hud.fadeAfter", 20)
    NS.SetByPath("hud.layout.chart", false)
    NS.SetByPath("hud.spells.petColor", { r = 1, g = 0, b = 0, a = 1 })
    NS.SetByPath("hud.position.x", 12)
    NS.SetByPath("general.locked", true)
    ctx.panel.defaultsOnClick()
    local hud, D = NS.db.profile.hud, NS.defaults.profile.hud
    assertEqual(hud.fadeAfter, D.fadeAfter)
    assertEqual(hud.layout.chart, true)
    assertEqual(hud.spells.petColor.r, D.spells.petColor.r)
    assertEqual(hud.position.x, D.position.x)
    assertEqual(NS.GetSetting("general.locked"), true, "another page's row is not this page's to reset")
end)
