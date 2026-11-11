local _, NS = ...
-- locales/enUS_Race.lua — Race mode's strings (ruling X13, localization-§6): a topic file of the
-- canonical locale. It fills locales/enUS.lua's NS.L and nothing else: no table of its own, no
-- metatable. Grouped by first reader, in TOC load order.

local L = NS.L

-- The late-cast ignore list (modules/LateIgnore.lua)
L["%s, all variants (%d)"] = "%s, all variants (%d)"
L["Ignore %s for late casts"] = "Ignore %s for late casts"
L["Stop ignoring all hearthstones"] = "Stop ignoring all hearthstones"
L["Stop ignoring %s"] = "Stop ignoring %s"
L["Late casts"] = "Late casts"

-- A race's flags (modules/RaceScoring.lua)
L["+%.1fs %s"] = "+%.1fs %s"
L["+%.1fs"] = "+%.1fs"
L["Ignored: %s"] = "Ignored: %s"
L["1 late cast (%s)"] = "1 late cast (%s)"
L["1 late cast"] = "1 late cast"
L["%d late casts (%s)"] = "%d late casts (%s)"
L["%d late casts"] = "%d late casts"
L["Damage restarted at +%.1fs"] = "Damage restarted at +%.1fs"
L["Reloaded mid-race: casts after the buzzer not tracked"] = "Reloaded mid-race: casts after the buzzer not tracked"
L["Session matched by list"] = "Session matched by list"
L["Shared session: the pull carried on a meter session from before the arm"] =
    "Shared session: the pull carried on a meter session from before the arm"
L["Died during the race"] = "Died during the race"
L["Incomplete: combat ended before the buzzer"] = "Incomplete: combat ended before the buzzer"
L["Lost: the fight could not be read"] = "Lost: the fight could not be read"
