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

test("load: the settings stamp is 6 and the fight record's format is 6", function()
    assertEqual(T.NS.SCHEMA_VERSION, 6)
    assertEqual(T.NS.Recorder.CT_SCHEMA, 6)
end)

test("load: a schema 1 store loads empty at the current version, keeping the account's other state", function()
    local old = { schema = 1, id = "f-old", t = 1000, duration = 60, status = "final", dps = 100 }
    local NS = boot({ global = {
        schemaVersion = 1,
        fights = { [old.id] = old }, fightOrder = { old.id },
        loadouts = { ["l-1"] = { talents = "x" } }, gearSets = { ["g-1"] = { slots = {} } },
        usage = { hidden = "6948" }, minimap = { hide = true },
    } })
    local g = NS.db.global
    assertEqual(g.schemaVersion, NS.SCHEMA_VERSION, "stamped")
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
    assertEqual(g.schemaVersion, NS.SCHEMA_VERSION)
    assertEqual(type(g.fights), "table")
    assertEqual(type(g.fightOrder), "table")
    assertEqual(count(g.fights), 0)
end)

test("load: step 5 drops the Combat Log's retired keys in every profile, and keeps the rest", function()
    local function stored()
        return { log = { drawer = { shown = true, collapsed = true, strip = false, rows = 12 },
                         view = { columns = { source = false, target = true, info = false } } } }
    end
    local NS = boot({ global = { schemaVersion = 4 }, profiles = { Default = stored(), Other = stored() } })
    local sv = _G.CombatTrailDB.profiles
    for _, name in ipairs({ "Default", "Other" }) do
        local log = sv[name].log
        -- red under: no step, or one over the active profile alone
        assertEqual(rawget(log.drawer, "collapsed"), nil, name .. ": the fold's key")
        assertEqual(rawget(log.drawer, "strip"), nil, name .. ": the folded line's key")
        assertEqual(rawget(log.view.columns, "source"), nil, name .. ": the Source toggle")
        assertEqual(rawget(log.view.columns, "target"), nil, name .. ": the Target toggle")
        assertEqual(log.drawer.shown, true, name .. ": the open kept")
        assertEqual(log.drawer.rows, 12, name .. ": the rows kept")
        assertEqual(log.view.columns.info, false, name .. ": the Info toggle kept")
    end
    assertEqual(NS.db.global.schemaVersion, NS.SCHEMA_VERSION)
    -- Idempotent, and harmless on a profile with no log table.
    NS.DropRetiredLogKeys(sv.Default)
    NS.DropRetiredLogKeys({})
    assertEqual(sv.Default.log.drawer.rows, 12)
end)

test("load: step 6 drops the HUD's auto-grow and the log window's attached state in every profile", function()
    local function stored()
        return { hud = { sizeMode = "auto", grow = "up", bars = 7, width = 390 },
                 log = { window = { attached = true, side = "RIGHT", matchHud = false, pinned = true, rows = 20,
                                    width = 500, position = { point = "TOPLEFT", x = 10, y = 20 } } } }
    end
    local NS = boot({ global = { schemaVersion = 5 }, profiles = { Default = stored(), Other = stored() } })
    local sv = _G.CombatTrailDB.profiles
    for _, name in ipairs({ "Default", "Other" }) do
        local hud, w = sv[name].hud, sv[name].log.window
        -- red under: no step, or one over the active profile alone
        assertEqual(rawget(hud, "sizeMode"), nil, name .. ": the size mode")
        assertEqual(rawget(hud, "grow"), nil, name .. ": the grow edge")
        for _, key in ipairs({ "attached", "side", "matchHud", "pinned" }) do
            assertEqual(rawget(w, key), nil, name .. ": log.window." .. key)
        end
        assertEqual(hud.bars, 7, name .. ": the bars kept")
        assertEqual(hud.width, 390, name .. ": the width kept")
        assertEqual(w.rows, 20, name .. ": the window's rows kept")
        assertEqual(w.width, 500, name .. ": its width kept")
        assertEqual(w.position.x, 10, name .. ": its own place kept")
    end
    assertEqual(NS.db.global.schemaVersion, 6)
    NS.DropRetiredWindowKeys(sv.Default)
    NS.DropRetiredWindowKeys({})
    NS.DropRetiredWindowKeys({ log = {} })
    assertEqual(sv.Default.hud.bars, 7)
end)
