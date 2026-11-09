-- tests/test_load.lua — the scaffold loads (plan Task 0.1): every TOC file in order, on the vendored
-- library, through the client's lifecycle, under whichever kit profile the run was started with.

local T = _G.CT_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

test("load: NS is the AceAddon object named CombatTrail", function()
    local AceAddon = T.mocks.LibStub("AceAddon-3.0")
    assertEqual(T.NS.name, "CombatTrail")
    assertTrue(AceAddon:GetAddon("CombatTrail", true) == T.NS, "AceAddon knows the addon as NS")
    assertTrue(T.NS.addon == T.NS, "NS.addon is the same object")
end)

test("load: the identity constants", function()
    assertEqual(T.NS.BRAND, "Ka0s Combat Trail")
    assertEqual(T.NS.SLASH, "kct")
    assertEqual(T.NS.SLASH_LONG, "combattrail")
    assertEqual(T.NS.version, "0.1.0")
end)

test("load: NS.db.profile exists after OnInitialize, with the defaults' sub-tables", function()
    local db = T.NS.db
    assertTrue(db ~= nil and type(db.profile) == "table", "NS.db.profile")
    for _, key in ipairs({ "general", "lanes", "hud", "history", "results" }) do
        assertEqual(type(db.profile[key]), "table", "profile." .. key)
    end
    assertEqual(type(db.global.fights), "table", "global.fights")
    assertEqual(db.global.schemaVersion, T.NS.SCHEMA_VERSION, "migrations stamped")
end)

test("load: the core seams are published", function()
    local NS = T.NS
    for _, key in ipairs({ "L", "Compat", "Secrets", "Pool", "Skin", "DebugLog", "Launcher", "Perf" }) do
        assertEqual(type(NS[key]), "table", "NS." .. key)
    end
    for _, key in ipairs({ "Print", "Debug", "SendBus", "NewBusTarget", "Icon" }) do
        assertEqual(type(NS[key]), "function", "NS." .. key)
    end
    assertEqual(type(NS.MSG), "table", "NS.MSG, the bus catalog")
    assertEqual(type(NS.Constants.LAYERS), "table", "NS.Constants.LAYERS")
end)

test("load: NS.Compat.ClientKey() follows the kit profile", function()
    -- Read off the environment the run was started with, not off the mock it stamped, so a kit
    -- profile that failed to stamp Forever's constants goes red here instead of agreeing with itself.
    local want = (os.getenv("KA0S_KIT_CLIENT") == "forever") and "forever" or "retail"
    assertEqual(T.NS.Compat.ClientKey(), want)
    assertEqual(T.NS.Compat.IsForever(), want == "forever")
    assertEqual(T.NS.Compat.IsRetail(), want == "retail")
end)

test("load: NS.Compat.ClientKey() is retail on a retail mock and forever on a forever mock", function()
    -- The client is read at CALL time, so re-stamping a loaded instance's mock moves the answer.
    local inst = T.load()
    for _, name in ipairs({ "retail", "forever" }) do
        T.Loader.MockClient.apply(inst.mocks, name)
        assertEqual(inst.NS.Compat.ClientKey(), name, name)
    end
    -- Put the run's own profile back for the cases after this one.
    T.Loader.MockClient.apply(T.mocks)
end)

test("load: NS.Compat.ForClient keeps a declared feature on its clients only", function()
    local key = T.NS.Compat.ClientKey()
    assertTrue(T.NS.Compat.ForClient({ key }), "a feature declared for this client")
    assertTrue(T.NS.Compat.ForClient(nil), "a feature declared for every client")
    local other = key == "retail" and "forever" or "retail"
    assertEqual(T.NS.Compat.ForClient({ other }), false, "a feature declared for the other client")
end)

test("load: NS.Print tags its line with the chat prefix", function()
    T.mocks.__resetPrinted()
    T.NS.Print("hello")
    local line = T.mocks.__printed()[1]
    assertTrue(line ~= nil and line:find("[Combat Trail]", 1, true) ~= nil, tostring(line))
    assertTrue(line:find("hello", 1, true) ~= nil, tostring(line))
end)

test("load: the library-absent load still loads and initializes", function()
    local inst = T.load({ libFiles = {} })
    assertTrue(inst.NS.db ~= nil and type(inst.NS.db.profile) == "table", "NS.db.profile without LibKa0s")
    assertEqual(type(inst.NS.Compat.ClientKey()), "string")
end)
