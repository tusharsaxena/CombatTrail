-- tests/test_settings.lua — the settings framework (plan Task 0.2): the page order, the General page's
-- tabs, the general.* paths through the slash CLI, and the pages rendering quietly.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local function anyLine(M, needle)
    for _, l in ipairs(M.__printed()) do
        if l:find(needle, 1, true) then return true end
    end
    return false
end

test("settings: the pages register in the panel's order, General first and Profiles last", function()
    local inst = T.load()
    local order = {}
    for _, ctx in ipairs(inst.NS.Helpers.__pages()) do order[#order + 1] = ctx.pageKey or ctx.key end
    assertEqual(table.concat(order, ","), "general,lanes,hud,history,profiles")
end)

test("settings: every page is a subcategory under its player-facing name", function()
    local M = T.load().mocks
    for _, name in ipairs({ "General", "Lanes", "DPS HUD", "History", "Profiles" }) do
        assertTrue(M.__subcategories[name] ~= nil, name .. " is not registered")
    end
end)

test("settings: every page renders without printing", function()
    local inst = T.load()
    local M = inst.mocks
    M.__resetPrinted()
    for _, name in ipairs({ "General", "Lanes", "DPS HUD", "History", "Profiles" }) do
        M.__subcategories[name]:__fire("OnShow")
    end
    assertEqual(#M.__printed(), 0, "a render printed: " .. tostring(M.__printed()[1]))
end)

test("settings: the General page's tabs are Master controls, Look and skin and Keybindings", function()
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    M.__subcategories["General"]:__fire("OnShow")
    local ctx
    for _, c in ipairs(NS.Helpers.__pages()) do
        if (c.pageKey or c.key) == "general" then ctx = c end
    end
    assertTrue(ctx ~= nil, "the General page's ctx")
    local _, keys = NS.Helpers.RenderTabbedSchema(ctx, "general", nil, nil, { tabs = NS.GENERAL_TABS })
    assertEqual(table.concat(keys or {}, ","), "Master controls,Look and skin,Keybindings")
end)

-- Each general.* path with a value that is not its default. The session rows (test mode, sim mode,
-- debug logging) store nothing in the profile; their round trip is their own get and set.
local GENERAL = {
    { "general.enabled",       "false", false },
    { "general.locked",        "true",  true  },
    { "general.testMode",      "true",  true  },
    { "general.simMode",       "true",  true  },
    { "general.hudInCombat",   "false", false },
    { "general.minimap.shown", "false", false },
    { "general.debug",         "true",  true  },
    { "general.fontScale",     "1.25",  1.25  },
}

for _, case in ipairs(GENERAL) do
    local path, typed, want = case[1], case[2], case[3]
    test("settings: " .. path .. " round-trips through /kct set and /kct get", function()
        local inst = T.load()
        local NS, M = inst.NS, inst.mocks
        assertTrue(NS.FindSchemaRow(path) ~= nil, "no schema row " .. path)
        NS.Slash:OnSlash("set " .. path .. " " .. typed)
        assertEqual(NS.GetSetting(path), want, path .. " after set")
        M.__resetPrinted()
        NS.Slash:OnSlash("get " .. path)
        assertTrue(anyLine(M, path), "get names the path")
        assertTrue(anyLine(M, typed) or anyLine(M, tostring(want)) or anyLine(M, "125%"),
            "get prints the value: " .. tostring(M.__printed()[1]))
    end)
end

test("settings: the minimap row stores LibDBIcon's own hide key in the global store", function()
    local inst = T.load()
    local NS = inst.NS
    NS.SetByPath("general.minimap.shown", false)
    assertEqual(NS.db.global.minimap.hide, true)
    assertEqual(NS.db.profile.general.minimap, nil, "nothing is written to the profile")
    NS.SetByPath("general.minimap.shown", true)
    assertEqual(NS.db.global.minimap.hide, false)
end)

test("settings: general.enabled false stands the addon down, true stands it up", function()
    local inst = T.load()
    local NS = inst.NS
    NS.SetByPath("general.enabled", false)
    assertTrue(NS.IsDisabled())
    assertEqual(NS.db.profile.general.enabled, false)
    NS.SetByPath("general.enabled", true)
    assertFalse(NS.IsStoodDown())
end)

test("settings: the session rows never reach the profile", function()
    local inst = T.load()
    local NS = inst.NS
    NS.SetByPath("general.testMode", true)
    NS.SetByPath("general.debug", true)
    assertEqual(NS.db.profile.general.testMode, nil)
    assertEqual(NS.db.profile.general.debug, nil)
    assertTrue(NS.State.debug, "the debug flag is the session's")
end)

test("settings: a stored write announces SETTINGS_CHANGED with its path", function()
    local inst = T.load()
    local NS = inst.NS
    local heard = {}
    local target = NS.NewBusTarget()
    target:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path) heard[#heard + 1] = path end)
    NS.SetByPath("general.hudInCombat", false)
    assertEqual(heard[#heard], "general.hudInCombat")
end)

test("settings: the schema validates against the defaults", function()
    local errors = T.load().NS.ValidateSchema()
    assertEqual(errors, 0)
end)

test("settings: Reset all settings puts every general row back", function()
    local inst = T.load()
    local NS = inst.NS
    NS.SetByPath("general.locked", true)
    NS.SetByPath("general.fontScale", 1.5)
    NS.SetByPath("general.minimap.shown", false)
    NS.Helpers.RestoreAllDefaults()
    assertEqual(NS.GetSetting("general.locked"), false)
    assertEqual(NS.GetSetting("general.fontScale"), 1)
    assertEqual(NS.GetSetting("general.minimap.shown"), false, "the minimap button is never reset")
end)

test("settings: library absent, the pages register nothing and the switch still writes", function()
    local inst = T.load({ libFiles = {} })
    local NS = inst.NS
    assertEqual(next(inst.mocks.__subcategories), nil, "a page registered without the library")
    assertTrue(NS.SetByPath("general.enabled", false))
    assertEqual(NS.db.profile.general.enabled, false)
    -- A written-through value runs no onChange (options-ui-§1); the next sync reads the stored switch.
    NS.SyncEnabledHold()
    assertTrue(NS.IsDisabled())
end)
