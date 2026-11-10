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
        -- who and where a fight was (modules/Identity.lua)
        "RegionalUniqueNamesEnabled", "GetRealmName", "C_ChallengeMode", "C_UIWidgetManager", "Enum", "C_PvP",
    },
}

-- The meter reader is the only file that names C_DamageMeter (tests/test_meter.lua holds it to that).
-- `/kct probe` reaches the meter through NS.Meter and reads the meter enums itself, for the report.
files["modules/Meter.lua"] = { read_globals = { "C_DamageMeter", "Enum" } }
files["modules/Probe.lua"] = { read_globals = { "Enum" } }
-- A fight's identity: the player, the target and the instance (the version-variant reads are Compat's).
files["modules/Identity.lua"] = {
    read_globals = { "UnitClass", "UnitClassification", "UnitCreatureFamily", "GetAverageItemLevel",
                     "GetInstanceInfo", "GetDifficultyInfo" },
}

-- What a fight used, and the gear, talents and stats it was fought with (each read pcall'd at CALL
-- time, so a client without one leaves the field absent).
files["modules/Usage.lua"] = {
    read_globals = { "C_Item", "C_Container", "C_UnitAuras", "GetInventoryItemID" },
}
files["modules/Loadouts.lua"] = { read_globals = { "GetInventoryItemLink", "C_ClassTalents", "C_Traits" } }
files["modules/Stats.lua"] = {
    read_globals = { "UnitStat", "UnitArmor", "GetCombatRating", "GetCritChance", "GetRangedCritChance",
                     "GetSpellCritChance", "GetHaste", "GetMasteryEffect", "GetCombatRatingBonus",
                     "GetVersatilityBonus", "GetLifesteal", "GetAvoidance", "GetSpeed" },
}

-- The context menus: the client's menu without the library.
files["core/WidgetsSetup.lua"] = { read_globals = { "MenuUtil" } }
-- An item quality's client color, the degraded skin facade's fallback.
files["core/SkinSetup.lua"] = { read_globals = { "ITEM_QUALITY_COLORS" } }
-- The secret-safe number: the client's abbreviated-number formatter is Compat's; with none, the plain
-- fallback is the client's AbbreviateNumbers, type-checked at CALL time (modules/Format.lua).
files["modules/Format.lua"] = { read_globals = { "AbbreviateNumbers" } }
-- The Results window's table: the class colors, names and icons, a spec's name and icon (read bare
-- and type-checked, WoW Forever has no specializations), the cursor a hovered row follows, and the
-- client's date formatter.
files["modules/Results_Table.lua"] = {
    read_globals = { "RAID_CLASS_COLORS", "LOCALIZED_CLASS_NAMES_MALE", "CLASS_ICON_TCOORDS",
                     "GetSpecializationInfoByID", "GetCursorPosition", "date" },
}
-- The fight list's date range: today from local midnight (the client's date formatter).
files["modules/Results_Fights.lua"] = { read_globals = { "date" } }
-- The Results window: the popups it closes with it, and the talent tree it steps aside for (read
-- bare at CALL time, type-checked).
files["modules/Results.lua"] = { read_globals = { "StaticPopup_Hide", "PlayerSpellsFrame" } }
-- The fight detail's gear, talents and usage: the item data, the talent tree's link and an item's
-- Shift-click (each read bare at CALL time and pcall'd).
files["modules/Results_Loadout.lua"] = { read_globals = { "C_Item", "SetItemRef", "HandleModifiedItemClick" } }
files["modules/Results_Usage.lua"] = { read_globals = { "C_Item" } }
-- Share's whisper offers the targeted player's name.
files["modules/Share.lua"] = { read_globals = { "UnitIsPlayer" } }

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
