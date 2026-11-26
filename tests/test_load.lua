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

test("load: the settings stamp is 12 and the fight record's format is 6", function()
    assertEqual(T.NS.SCHEMA_VERSION, 12)
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
        -- Steps 5 to 8 ran on `log`; step 9 then moved it to `sequence`.
        local log = sv[name].sequence
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
    NS.DropRetiredLogKeys({ log = sv.Default.sequence })
    NS.DropRetiredLogKeys({})
    assertEqual(sv.Default.sequence.drawer.rows, 12)
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
        local hud, w = sv[name].hud, sv[name].sequence.window
        -- red under: no step, or one over the active profile alone
        assertEqual(rawget(hud, "sizeMode"), nil, name .. ": the size mode")
        assertEqual(rawget(hud, "grow"), nil, name .. ": the grow edge")
        for _, key in ipairs({ "attached", "side", "matchHud", "pinned" }) do
            assertEqual(rawget(w, key), nil, name .. ": sequence.window." .. key)
        end
        assertEqual(hud.bars, 7, name .. ": the bars kept")
        assertEqual(hud.width, 390, name .. ": the width kept")
        assertEqual(w.rows, 20, name .. ": the window's rows kept")
        assertEqual(w.width, 500, name .. ": its width kept")
        assertEqual(w.position.x, 10, name .. ": its own place kept")
    end
    assertEqual(NS.db.global.schemaVersion, NS.SCHEMA_VERSION)
    NS.DropRetiredWindowKeys(sv.Default)
    NS.DropRetiredWindowKeys({})
    NS.DropRetiredWindowKeys({ log = {} })
    assertEqual(sv.Default.hud.bars, 7)
end)

test("load: step 7 carries each profile's lock to the lanes' own, so no lanes unlock by surprise", function()
    local NS = boot({ global = { schemaVersion = 6 }, profiles = {
        Locked = { general = { locked = true } },
        Open = { general = { locked = false } },
        Bare = { hud = { bars = 6 } },
        Own = { general = { locked = true, lanesLocked = false } },
    } })
    local sv = _G.CombatTrailDB.profiles
    -- red under: no step, or one over the active profile alone
    assertEqual(sv.Locked.general.lanesLocked, true, "a locked profile keeps its lanes locked")
    assertEqual(sv.Locked.general.locked, true, "and keeps its HUD lock")
    assertEqual(rawget(sv.Open.general, "lanesLocked"), nil, "an unlocked one stores nothing")
    assertEqual(rawget(sv.Bare, "general"), nil, "a profile with no lock is left alone")
    assertEqual(sv.Own.general.lanesLocked, false, "a lanes lock already stored is kept")
    assertEqual(NS.db.global.schemaVersion, NS.SCHEMA_VERSION)
    NS.CarryLanesLock(sv.Locked)
    NS.CarryLanesLock({})
    NS.CarryLanesLock(nil)
    assertEqual(sv.Locked.general.lanesLocked, true, "idempotent")
end)

-- The keys the Combat Sequence retired (CSEQ-1), as a profile stored them.
local RETIRED_SEQUENCE = {
    "view.columns.amount", "view.schoolColors", "show.hits", "show.heals", "show.minAmount", "show.targetBuffs",
    "store.categories.hits", "store.categories.heals", "store.categories.targetBuffs",
    "results.chips.taken", "results.chips.heals",
}

local function at(t, path)
    for part in path:gmatch("[^.]+") do
        if type(t) ~= "table" then return nil end
        t = rawget(t, part)
    end
    return t
end

test("load: step 8 drops the Combat Sequence's retired keys in every profile, and keeps the rest", function()
    local function stored()
        return { log = {
            view = { columns = { amount = false, info = false, spell = true }, schoolColors = false, washes = false },
            show = { hits = false, heals = true, minAmount = 500, targetBuffs = false, casts = false, deaths = false },
            store = { categories = { hits = false, heals = false, targetBuffs = true, playerBuffs = false }, lines = 300 },
            results = { chips = { taken = false, heals = false, buffs = false } },
        } }
    end
    local NS = boot({ global = { schemaVersion = 7 }, profiles = { Default = stored(), Other = stored(), Bare = {} } })
    local sv = _G.CombatTrailDB.profiles
    for _, name in ipairs({ "Default", "Other" }) do
        local log = sv[name].sequence
        -- red under: no step 8, or one over the active profile alone
        for _, path in ipairs(RETIRED_SEQUENCE) do
            assertEqual(at(log, path), nil, name .. ": sequence." .. path)
        end
        assertEqual(log.view.columns.info, false, name .. ": the Info toggle kept")
        assertEqual(log.view.washes, false, name .. ": the washes kept")
        assertEqual(log.show.casts, false, name .. ": a live category kept")
        assertEqual(log.show.deaths, false, name .. ": the deaths kept")
        assertEqual(log.store.categories.playerBuffs, false, name .. ": a saved category kept")
        assertEqual(log.store.lines, 300, name .. ": the lines kept")
        assertEqual(log.results.chips.buffs, false, name .. ": a chip kept")
    end
    assertEqual(rawget(sv.Bare, "log"), nil, "a profile with no log is left alone")
    assertEqual(NS.db.global.schemaVersion, NS.SCHEMA_VERSION)
    -- Idempotent, harmless on a fresh profile or one with no log table.
    NS.DropRetiredSequenceKeys({ log = sv.Default.sequence })
    NS.DropRetiredSequenceKeys({})
    NS.DropRetiredSequenceKeys({ log = {} })
    NS.DropRetiredSequenceKeys({ log = { view = {}, show = {}, store = {}, results = {} } })
    NS.DropRetiredSequenceKeys(nil)
    assertEqual(sv.Default.sequence.store.lines, 300, "a second run changes nothing")
    local fresh = boot(nil)
    for _, path in ipairs(RETIRED_SEQUENCE) do
        assertEqual(fresh.GetSetting("sequence." .. path), nil, "a fresh profile has no sequence." .. path)
    end
end)

test("load: step 9 moves each profile's log to sequence, and its Results fold with it", function()
    local NS = boot({ global = { schemaVersion = 8 }, profiles = {
        Default = { log = { enabled = false, home = "detached", drawer = { rows = 14, chips = true },
                            store = { lines = 300 } },
                    results = { collapsedSections = { log = true, spells = true } } },
        Both = { log = { home = "docked", drawer = { rows = 14, shown = false, chips = true } },
                 sequence = { home = "detached", drawer = { rows = 6, chips = false } },
                 results = { collapsedSections = { log = true, sequence = false } } },
        Bare = { hud = { bars = 6 } },
    } })
    local sv = _G.CombatTrailDB.profiles
    -- red under: no step 9, or one over the active profile alone
    for _, name in ipairs({ "Default", "Both", "Bare" }) do
        assertEqual(rawget(sv[name], "log"), nil, name .. ": no log left")
    end
    local d = sv.Default.sequence
    assertEqual(d.enabled, false, "the switch moved")
    assertEqual(d.home, "detached", "the home moved")
    assertEqual(d.drawer.rows, 14, "the rows moved")
    assertEqual(d.drawer.chips, true, "the chips moved")
    assertEqual(d.store.lines, 300, "the lines kept moved")
    assertEqual(NS.GetSetting("sequence.home"), "detached", "the active profile reads them")
    local folds = sv.Default.results.collapsedSections
    assertEqual(rawget(folds, "sequence"), true, "the fold moved")
    assertEqual(rawget(folds, "log"), nil, "the old fold key gone")
    assertEqual(folds.spells, true, "another fold kept")
    -- Both stored: a key already under sequence wins, a key only under log is copied, and a sequence
    -- value equal to its default (AceDB's copy into the active profile, as Default's is here) yields.
    local b = sv.Both.sequence
    assertEqual(b.home, "detached", "sequence's home wins")
    assertEqual(b.drawer.rows, 6, "sequence's rows win")
    assertEqual(b.drawer.shown, false, "log's own key copied in")
    assertEqual(b.drawer.chips, true, "a default's copy under sequence yields to log's choice")
    assertEqual(sv.Both.results.collapsedSections.sequence, false, "sequence's fold wins")
    assertEqual(rawget(sv.Both.results.collapsedSections, "log"), nil)
    assertEqual(rawget(sv.Bare, "sequence"), nil, "a profile with no log is left alone")
    assertEqual(NS.db.global.schemaVersion, NS.SCHEMA_VERSION)
    -- Idempotent: a second run finds no log; harmless on a fresh or empty profile.
    NS.MoveLogToSequence(sv.Default)
    NS.MoveLogToSequence({})
    NS.MoveLogToSequence({ results = {} })
    NS.MoveLogToSequence(nil)
    assertEqual(sv.Default.sequence.drawer.rows, 14, "a second run changes nothing")
    assertEqual(sv.Default.results.collapsedSections.sequence, true)
end)

test("load: a profile at schema 5 runs steps 6 to 10 in order and ends with no log", function()
    local NS = boot({ global = { schemaVersion = 5 }, profiles = { Other = {
        general = { locked = true },
        log = { window = { attached = true, rows = 20 }, view = { columns = { amount = false, info = false } },
                show = { hits = false, casts = false } },
    } } })
    local p = _G.CombatTrailDB.profiles.Other
    assertEqual(rawget(p, "log"), nil, "step 9 moved it")
    assertEqual(rawget(p.sequence.window, "attached"), nil, "step 6 ran on it first")
    assertEqual(p.sequence.window.rows, 20)
    assertEqual(p.general.lanesLocked, true, "step 7 ran")
    assertEqual(rawget(p.sequence.view.columns, "amount"), nil, "step 8 ran on it first")
    assertEqual(rawget(p.sequence.show, "hits"), nil)
    assertEqual(p.sequence.view.columns.info, false, "a kept key moved")
    assertEqual(p.sequence.show.casts, false)
    assertEqual(NS.db.global.schemaVersion, NS.SCHEMA_VERSION)
end)

test("load: step 10 pins 390 wide on each stored profile that keeps no width, so only new profiles start at 260", function()
    local NS = boot({ global = { schemaVersion = 9 }, profiles = {
        Default = { hud = { bars = 6 } },
        Wide = { hud = { width = 480 } },
        NoHud = { general = { locked = true } },
        Empty = {},
    } })
    local sv = _G.CombatTrailDB.profiles
    -- red under: no step 10, or one over the active profile alone
    assertEqual(sv.Default.hud.width, 390, "a stored profile with no width keeps today's 390")
    assertEqual(sv.NoHud.hud.width, 390, "a profile with no hud table gets one")
    assertEqual(sv.Wide.hud.width, 480, "a stored width is kept")
    assertEqual(rawget(sv.Empty, "hud"), nil, "an empty profile stores nothing yet: it is a new one")
    assertEqual(NS.GetSetting("hud.width"), 390, "the active profile reads the pin")
    assertEqual(NS.db.global.schemaVersion, NS.SCHEMA_VERSION)
    -- Idempotent and harmless.
    NS.PinHudWidth(sv.Default)
    NS.PinHudWidth({})
    NS.PinHudWidth(nil)
    assertEqual(sv.Default.hud.width, 390, "a second run changes nothing")
    local fresh = boot(nil)
    assertEqual(fresh.GetSetting("hud.width"), 260, "a fresh install starts at the least width")
    assertEqual(fresh.GetSetting("hud.width"), fresh.Hud.MIN_WIDTH)
end)

test("load: step 11 carries the Combat Sequence's Open when a fight starts to the DPS HUD's (LG22)", function()
    local NS = boot({ global = { schemaVersion = 10 }, profiles = {
        Default = { sequence = { drawer = { autoOpen = false, rows = 7 } } },
        On = { sequence = { drawer = { autoOpen = true } } },
        Never = { hud = { bars = 6 } },
    } })
    local sv = _G.CombatTrailDB.profiles
    -- red under: no step 11, or one over the active profile alone
    assertEqual(sv.Default.hud.openOnPull, false, "a stored off carried across")
    assertEqual(rawget(sv.Default.sequence.drawer, "autoOpen"), nil, "the old key gone")
    assertEqual(sv.Default.sequence.drawer.rows, 7, "the drawer's other keys kept")
    assertEqual(NS.GetSetting("hud.openOnPull"), false, "the active profile reads it")
    assertTrue(rawget(sv.On.hud or {}, "openOnPull") ~= false, "a stored on stays on")
    assertEqual(rawget(sv.On.sequence.drawer, "autoOpen"), nil)
    assertEqual(rawget(sv.Never.hud, "openOnPull"), nil, "nothing stored: the default, on (the old default)")
    NS.MoveOpenOnPull(sv.Default)
    NS.MoveOpenOnPull({})
    NS.MoveOpenOnPull(nil)
    assertEqual(sv.Default.hud.openOnPull, false, "a second run changes nothing")
    assertEqual(boot(nil).GetSetting("hud.openOnPull"), true, "a fresh profile: on")
end)

test("load: step 12 drops the Combat Sequence's who colors (LG27)", function()
    local function stored()
        return { sequence = { colors = { you = { r = 1, g = 0, b = 0, a = 1 }, useClassColorYou = false,
                                         hostile = { r = 0, g = 1, b = 0, a = 1 }, hostileFromSkin = false,
                                         friendly = { r = 0, g = 0, b = 1, a = 1 }, friendlyFromSkin = false },
                              view = { washes = false } } }
    end
    local NS = boot({ global = { schemaVersion = 11 }, profiles = { Default = stored(), Other = stored(), Bare = {} } })
    local sv = _G.CombatTrailDB.profiles
    -- red under: no step 12, or one over the active profile alone
    for _, name in ipairs({ "Default", "Other" }) do
        assertEqual(rawget(sv[name].sequence, "colors"), nil, name .. ": sequence.colors gone")
        assertEqual(sv[name].sequence.view.washes, false, name .. ": the washes kept")
    end
    assertEqual(rawget(sv.Bare, "sequence"), nil, "a profile with no sequence is left alone")
    assertEqual(NS.db.global.schemaVersion, NS.SCHEMA_VERSION)
    NS.DropWhoColors(sv.Default)
    NS.DropWhoColors({})
    NS.DropWhoColors(nil)
end)
