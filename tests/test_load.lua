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
    assertEqual(T.NS.SLASH, "ct")
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

-- ── the schema 2 wipe (plan Task A1, decision D1) ────────────────────────────────────────────────

-- An instance that logs in over `seeded` SavedVariables (the client's login reads the store first).
local function boot(seeded)
    local inst = T.load{ init = false }
    _G.CombatTrailDB = seeded
    local AceAddon = inst.mocks.LibStub("AceAddon-3.0")
    AceAddon:InitializeAddon(inst.NS)
    AceAddon:EnableAddon(inst.NS)
    return inst.NS
end

local function count(t)
    local c = 0
    for _ in pairs(t or {}) do c = c + 1 end
    return c
end

test("load: the settings stamp is 2 and the fight record's format is 2", function()
    assertEqual(T.NS.SCHEMA_VERSION, 2)
    assertEqual(T.NS.Recorder.CT_SCHEMA, 3)
end)

test("load: a schema 1 store loads empty at version 2, keeping the account's other state", function()
    local old = { schema = 1, id = "f-old", t = 1000, duration = 60, status = "final", dps = 100 }
    local NS = boot({ global = {
        schemaVersion = 1,
        fights = { [old.id] = old }, fightOrder = { old.id },
        loadouts = { ["l-1"] = { talents = "x" } }, gearSets = { ["g-1"] = { slots = {} } },
        usage = { hidden = "6948" }, minimap = { hide = true },
    } })
    local g = NS.db.global
    assertEqual(g.schemaVersion, 2, "stamped")
    assertEqual(count(g.fights), 0, "fights emptied")
    assertEqual(#g.fightOrder, 0, "fightOrder emptied")
    assertEqual(count(g.loadouts), 0, "loadouts emptied")
    assertEqual(count(g.gearSets), 0, "gearSets emptied")
    assertEqual(g.usage.hidden, "6948", "usage.hidden kept")
    assertEqual(g.minimap.hide, true, "minimap kept")
    -- A second run is a no-op: a fight saved since survives it.
    g.fights["f-new"] = { schema = 2, id = "f-new" }
    g.fightOrder[1] = "f-new"
    NS:RunMigrations()
    assertTrue(g.fights["f-new"] ~= nil, "the stamped store is not wiped again")
end)

test("load: a store already at version 2 keeps its fights", function()
    local kept = { schema = 2, id = "f-kept", t = os.time(), duration = 60, status = "final", dps = 100 }
    local NS = boot({ global = { schemaVersion = 2, fights = { [kept.id] = kept }, fightOrder = { kept.id } } })
    assertTrue(NS.db.global.fights[kept.id] ~= nil, "not wiped")
end)

test("load: a fresh install runs step 2 harmlessly", function()
    local NS = boot(nil)
    local g = NS.db.global
    assertEqual(g.schemaVersion, 2)
    assertEqual(type(g.fights), "table")
    assertEqual(type(g.fightOrder), "table")
    assertEqual(count(g.fights), 0)
end)
