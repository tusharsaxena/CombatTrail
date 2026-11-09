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
