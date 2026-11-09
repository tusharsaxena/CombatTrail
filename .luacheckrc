std = "lua51"
max_line_length = false
codes = true

-- libs/ holds vendored code, including libs/LibKa0s/, whose upstream is the LibKa0s repo and which is
-- linted THERE as source. tests/_kit/ is the same fact one level down: a byte copy of the library's
-- testkit/, so linting the copy as well would report every finding twice and let the copy drift green
-- while the original went red (lint). The rest of tests/ is ours, and it is linted. Under docs/ only
-- the FROZEN evidence bundles are excluded: a blanket docs/ exclude would silently drop any Lua a
-- future doc directory carries out of the gate.
exclude_files = { "libs/", "tests/_kit/", "docs/audits/", "docs/reviews/", "docs/revendor/", "_dev/" }

-- NO TOP-LEVEL `ignore`: a blanket reaches every file, including the ones with no business producing
-- the code it silences (lint). A receiver a calling convention forces gets a per-file stanza below.

read_globals = {
    "_G", "LibStub", "CreateFrame", "GetTime", "UIParent", "STANDARD_TEXT_FONT",
    "DEFAULT_CHAT_FRAME", "UISpecialFrames",
    "C_Timer", "C_AddOns", "GetLocale",
    -- the epoch clock (the client's `time`, not os.time): a fight's ID (modules/Fight.lua)
    "time",
    -- combat state: InCombatLockdown() gates secure writes; UnitAffectingCombat() drives display
    "InCombatLockdown", "UnitAffectingCombat",
    -- units: the pet's presence and name (modules/LaneCasts.lua), and the GUIDs `/kct probe` asks the meter by
    "UnitExists", "UnitName", "UnitGUID",
    -- the lanes' visibility context (modules/LaneVisibility.lua)
    "IsMounted", "IsResting", "IsInInstance",
    -- Blizzard's Edit Mode callbacks, which show the lanes' edit overlay (modules/LaneAnchor.lua)
    "EventRegistry",
    -- a lane icon's spell tooltip (modules/LaneRender.lua)
    "GameTooltip",
    -- the perf brackets' CPU clock (LibKa0s-Perf-1.0's Note takes milliseconds)
    "debugprofilestop",
    -- settings panel plumbing (settings/)
    "Settings", "StaticPopup_Show",
}

globals = {
    "CombatTrailDB",        -- the SavedVariables write target (the AceDB tree)
    "CombatTrailPerfDB",    -- the LibKa0s-Perf capture ring, outside the AceDB tree (performance-§5)
    "StaticPopupDialogs",   -- the addon registers its named popup (settings/General.lua) into this table
}

-- The test tree is linted; these are the globals it WRITES. Scoped here so no shipped file can reach
-- for the harness.
files["tests/"] = {
    globals = { "_G.CT_TEST", "_G.CombatTrailDB", "_G.CombatTrailPerfDB" },
}

-- The compat family (compat, clients-§3): the version-variant client calls and the client's project
-- constants, and the only file that may name them. Anywhere else, naming one is a warning.
files["core/Compat.lua"] = {
    read_globals = {
        "WOW_PROJECT_ID", "WOW_PROJECT_MAINLINE", "WOW_PROJECT_CAMELOT",
        "C_ChatInfo", "SendChatMessage", "C_StringUtil",
        "C_SpecializationInfo", "GetSpecialization", "GetSpecializationInfo",
        "C_Spell", "GetSpellTexture", "GetSpellInfo", "GetSpellBaseCooldown", "UnitSpellHaste",
        "C_PetBattles", "UnitInVehicle", "C_PartyInfo",
        "issecretvalue", "canaccessvalue", "issecrettable", "canaccesstable",
        "GetBuildInfo",
    },
}

-- The meter reader is the only file that names C_DamageMeter (tests/test_meter.lua holds it to that).
-- `/kct probe` reaches the meter through NS.Meter and reads the meter enums itself, for the report.
files["modules/Meter.lua"] = { read_globals = { "C_DamageMeter", "Enum" } }
files["modules/Probe.lua"] = { read_globals = { "Enum" } }

-- The context menus: the client's menu without the library.
files["core/WidgetsSetup.lua"] = { read_globals = { "MenuUtil" } }
-- An item quality's client color, the degraded skin facade's fallback.
files["core/SkinSetup.lua"] = { read_globals = { "ITEM_QUALITY_COLORS" } }

-- ---------------------------------------------------------------------------
-- The narrowed 212s: every stanza names ONE file and every entry the code AND the variable.
-- ---------------------------------------------------------------------------

-- The database entry points publish onto `NS` itself and are reached by colon (`NS:InitDB()`,
-- `NS:RunMigrations()` from core/CombatTrail.lua's OnInitialize); the receiver and the file's `NS`
-- upvalue are the same table, so the bodies read the upvalue.
files["core/Database.lua"] = { ignore = { "212/self" } }

-- AceAddon calls the lifecycle entry points by colon on the addon object, which is NS itself:
-- OnEnable reads the file's `NS` upvalue (the same table), and OnInitialize reads `self`, which is
-- why the entry is `212/self` and not a file-wide switch.
files["core/CombatTrail.lua"] = { ignore = { "212/self" } }

-- The dispatcher's methods are reached by colon (`NS.Slash:OnSlash(msg)`, the Ace and kit convention)
-- and forward to the library's instance; `Sl` and `self` are the same table, so the bodies read the
-- file's upvalue.
files["settings/Slash.lua"] = { ignore = { "212/self" } }
