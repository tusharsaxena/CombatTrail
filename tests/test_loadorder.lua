-- tests/test_loadorder.lua — the runner's load list IS the TOC's (testing-§9): fed exactly the TOC's
-- files in the TOC's order, every derived path on disk, and no libs/ path leaked in.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

test("load order: the runner loaded exactly the TOC's files, in the TOC's order", function()
    local fresh = T.Loader.tocFiles(T.root .. "/CombatTrail.toc")
    local loaded = T.loadedAddonFiles
    assertTrue(#fresh > 0, "the TOC derivation is empty; nothing below can fail")
    assertEqual(#loaded, #fresh, "the runner's list and the TOC differ in length")
    for i, path in ipairs(fresh) do assertEqual(loaded[i], path, "position " .. i) end
end)

test("load order: the locale and the namespace come first, the AceAddon promotion after the printer", function()
    local at = {}
    for i, path in ipairs(T.loadedAddonFiles) do at[path:gsub("\\", "/")] = i end
    assertEqual(at["locales/enUS.lua"], 1, "NS.L before every file that reads it at file scope")
    assertEqual(at["core/Namespace.lua"], 2, "NS.PREFIX, NS.name and NS.BRAND before everything else")
    assertTrue(at["core/MediaSetup.lua"] < at["core/Constants.lua"], "FONT_MONO resolves from NS.MediaFont")
    assertTrue(at["core/Compat.lua"] < at["core/Secrets.lua"], "Secrets binds Compat's guards at file scope")
    assertTrue(at["core/CoreSetup.lua"] < at["core/CombatTrail.lua"], "the printer before its reclaim")
    assertTrue(at["core/LifecycleSetup.lua"] < at["core/PerfSetup.lua"], "the latch before the Perf instance")
    assertTrue(at["core/CombatTrail.lua"] < at["defaults/Profile.lua"], "NS is the addon before the defaults")
end)

test("load order: every derived path exists on disk", function()
    for _, path in ipairs(T.loadedAddonFiles) do
        local f = io.open(T.root .. "/" .. path, "rb")
        assertTrue(f ~= nil, path .. " is in the TOC but not on disk")
        if f then f:close() end
    end
end)

test("load order: no libs/ path leaked into the addon's own list", function()
    for _, path in ipairs(T.loadedAddonFiles) do
        assertFalse(path:find("^libs[/\\]") ~= nil, path .. " is a library file in the addon's list")
    end
end)
