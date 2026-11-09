local _, NS = ...
-- locales/enUS.lua — the canonical locale: NS.L with the key-is-the-string fallback (localization).

-- Keys ARE the English source string. A missing key answers itself, so a string can ship before this
-- file lists it; listing it here is still owed, because it is what a translator copies.
--
-- Never pass this table as a LibKa0s descriptor's `L`: the fallback answers EVERY key, which shadows
-- the library's own strings (the "L trap" the library documents).
local L = setmetatable({}, { __index = function(_, k) return k end })
NS.L = L

-- Identity and chrome
L["Ka0s Combat Trail"] = "Ka0s Combat Trail"

-- Key bindings (launcher-§6)
L["Toggle DPS HUD"] = "Toggle DPS HUD"
L["Toggle Results window"] = "Toggle Results window"
L["Toggle lanes"] = "Toggle lanes"
L["Shows or hides the DPS HUD, as the launcher's Show window entry and /kct hud do."] =
    "Shows or hides the DPS HUD, as the launcher's Show window entry and /kct hud do."
L["Shows or hides the Results window, with your fight history."] =
    "Shows or hides the Results window, with your fight history."
L["Shows or hides the Player and Pet cast lanes."] = "Shows or hides the Player and Pet cast lanes."

-- Shared refusals (slash-commands-§1, slash-commands-§7)
L["%s is unavailable: the LibKa0s library did not load."] = "%s is unavailable: the LibKa0s library did not load."
L["Not available during a performance capture."] = "Not available during a performance capture."
L["That part of Combat Trail is not built yet."] = "That part of Combat Trail is not built yet."

-- The skin seam (core/SkinSetup.lua)
L["Reload your interface (/reload) to finish changing the skin."] =
    "Reload your interface (/reload) to finish changing the skin."

-- Settings pages (settings/)
L["General"] = "General"
L["Lanes"] = "Lanes"
L["DPS HUD"] = "DPS HUD"
L["History"] = "History"
L["Profiles"] = "Profiles"
L["Slash Commands"] = "Slash Commands"
L["The lane settings arrive with the lanes."] = "The lane settings arrive with the lanes."
L["The DPS HUD settings arrive with the HUD."] = "The DPS HUD settings arrive with the HUD."
L["The History settings arrive with the fight history."] =
    "The History settings arrive with the fight history."
L["Restore every Lanes setting on this profile to its addon default."] =
    "Restore every Lanes setting on this profile to its addon default."
L["Restore every DPS HUD setting on this profile to its addon default."] =
    "Restore every DPS HUD setting on this profile to its addon default."
L["Restore every History setting on this profile to its addon default. Stored fights are not touched."] =
    "Restore every History setting on this profile to its addon default. Stored fights are not touched."

-- Master controls tab (settings/General.lua)
L["Reset this profile to the addon's defaults? Everything you have configured or added in it is discarded — your other profiles are not affected."] =
    "Reset this profile to the addon's defaults? Everything you have configured or added in it is discarded — your other profiles are not affected."
L["Yes"] = "Yes"
L["No"] = "No"
L["All settings reset to defaults."] = "All settings reset to defaults."
L["Restore every General setting on this profile to its addon default: Master controls and the look and skin."] =
    "Restore every General setting on this profile to its addon default: Master controls and the look and skin."
L["It fills the lanes, the HUD and the Results window with sample data."] =
    "It fills the lanes, the HUD and the Results window with sample data."
L["Move the lanes, the DPS HUD and the Results window back to where they started."] =
    "Move the lanes, the DPS HUD and the Results window back to where they started."
L["Show DPS HUD in combat"] = "Show DPS HUD in combat"
L["Open the DPS HUD whenever you enter combat. Off, it opens only when you show it."] =
    "Open the DPS HUD whenever you enter combat. Off, it opens only when you show it."
L["Debug logging"] = "Debug logging"
L["Write this session's developer log to the debug console. A reload turns it off."] =
    "Write this session's developer log to the debug console. A reload turns it off."

-- Look and skin tab (settings/General.lua; the tab's own words are the library's)
L["Look and skin"] = "Look and skin"
L["Skin source"] = "Skin source"
L["Where this addon's look comes from: the Ka0s skin chosen below, or EllesmereUI."] =
    "Where this addon's look comes from: the Ka0s skin chosen below, or EllesmereUI."
L["Skin"] = "Skin"
L["The Ka0s skin this addon wears. Changes every window and panel right away."] =
    "The Ka0s skin this addon wears. Changes every window and panel right away."
L["Ignore settings panel"] = "Ignore settings panel"
L["Keep this addon's settings panel in the game's own look. Its windows still wear the skin."] =
    "Keep this addon's settings panel in the game's own look. Its windows still wear the skin."
L["Ignore fonts"] = "Ignore fonts"
L["Keep every font in this addon as the game draws it. The skin still colors the text."] =
    "Keep every font in this addon as the game draws it. The skin still colors the text."
L["Font"] = "Font"
L["The font this addon's text uses, over the skin's own. Empty keeps the skin's."] =
    "The font this addon's text uses, over the skin's own. Empty keeps the skin's."
L["Texture"] = "Texture"
L["The texture this addon's bars use, over the skin's own. Empty keeps the skin's."] =
    "The texture this addon's bars use, over the skin's own. Empty keeps the skin's."
L["Font outline"] = "Font outline"
L["Where the skin outlines this addon's text: all of it, its HUD text only, or nowhere."] =
    "Where the skin outlines this addon's text: all of it, its HUD text only, or nowhere."
L["Skin picker seen"] = "Skin picker seen"
L["Whether the first-run skin picker was closed on this profile."] =
    "Whether the first-run skin picker was closed on this profile."
L["Global font scale"] = "Global font scale"
L["Scales every text in the lanes, the DPS HUD and the Results window, on top of each element's own size."] =
    "Scales every text in the lanes, the DPS HUD and the Results window, on top of each element's own size."

-- Slash verbs (settings/Slash.lua, spec §8)
L["Show this help"] = "Show this help"
L["Open the settings panel"] = "Open the settings panel"
L["Choose a skin: open the skin picker"] = "Choose a skin: open the skin picker"
L["Turn the addon on"] = "Turn the addon on"
L["Turn the addon off without unloading it"] = "Turn the addon off without unloading it"
L["List every setting"] = "List every setting"
L["Read one setting: /kct get path"] = "Read one setting: /kct get path"
L["Write one setting: /kct set path value"] = "Write one setting: /kct set path value"
L["Reset one setting: /kct reset path"] = "Reset one setting: /kct reset path"
L["Reset every setting (asks first)"] = "Reset every setting (asks first)"
L["Debug console; on/off set logging, diagnostics writes the report"] =
    "Debug console; on/off set logging, diagnostics writes the report"
L["Write the diagnostics report to the debug console"] = "Write the diagnostics report to the debug console"
L["Performance capture; try /kct perf help"] = "Performance capture; try /kct perf help"
L["Print the addon version"] = "Print the addon version"
L["Open the Results window, with your fight history"] = "Open the Results window, with your fight history"
L["The DPS HUD: /kct hud show or hide"] = "The DPS HUD: /kct hud show or hide"
L["Lock the lanes and the DPS HUD in place"] = "Lock the lanes and the DPS HUD in place"
L["Unlock the lanes and the DPS HUD to move them"] = "Unlock the lanes and the DPS HUD to move them"
L["Test mode: sample data in the lanes, the HUD and the Results window"] =
    "Test mode: sample data in the lanes, the HUD and the Results window"
L["Sim mode: a made-up fight played in real time"] = "Sim mode: a made-up fight played in real time"
L["Delete stored fights older than the History page's limit"] =
    "Delete stored fights older than the History page's limit"
L["Check what this client reports for the meter, casts and your pet"] =
    "Check what this client reports for the meter, casts and your pet"
L["Turn a lane on or off: /kct lane player|pet on|off"] = "Turn a lane on or off: /kct lane player|pet on|off"
L["A lane's ignore list: /kct ignore add|remove <spell> [player|pet]"] =
    "A lane's ignore list: /kct ignore add|remove <spell> [player|pet]"
L["%s version %s"] = "%s version %s"
L["%s commands (reduced: the LibKa0s library is missing)"] =
    "%s commands (reduced: the LibKa0s library is missing)"
L["%s = %s"] = "%s = %s"
