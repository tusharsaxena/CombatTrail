local _, NS = ...
-- locales/enUS_Insights.lua — the Results window's Insights tab's strings (Race mode plan Task D2,
-- localization-§6): a topic file of the canonical locale. It fills locales/enUS.lua's NS.L and
-- nothing else: no table of its own, no metatable. Grouped by first reader, in TOC load order.

local L = NS.L

-- The Results window's tabs (modules/Results.lua)
L["Fights"] = "Fights"
L["Insights"] = "Insights"

-- The cards (modules/Results_Insights.lua)
L["Races"] = "Races"
L["Time in combat"] = "Time in combat"
L["Time raced"] = "Time raced"
L["Avg % of board best"] = "Avg % of board best"
L["Avg DPS"] = "Avg DPS"
L["Clean races"] = "Clean races"
L["New bests set"] = "New bests set"
L["Characters"] = "Characters"
L["Specs"] = "Specs"
L["Active days"] = "Active days"
L["Best DPS"] = "Best DPS"
L["Date range"] = "Date range"
L["%dh %02dm"] = "%dh %02dm"
L["%dm %02ds"] = "%dm %02ds"
L["%s to %s"] = "%s to %s"
L["1 race"] = "1 race"
L["%d races"] = "%d races"
L["%d days with a fight."] = "%d days with a fight."
L["%d of %d races carry no flag."] = "%d of %d races carry no flag."
L["The fights these filters pass; a race is a fight."] = "The fights these filters pass; a race is a fight."
L["The race lengths added up; an incomplete race counts its time in combat."] =
    "The race lengths added up; an incomplete race counts its time in combat."
L["The fights' lengths added up; a race counts its time raced."] =
    "The fights' lengths added up; a race counts its time raced."
L["No fight with a DPS in these filters."] = "No fight with a DPS in these filters."
L["The fights' average, all on one board."] = "The fights' average, all on one board."
L["Each fight against the best on its own board (character, spec and what it was against), averaged."] =
    "Each fight against the best on its own board (character, spec and what it was against), averaged."
L["No race in these filters."] = "No race in these filters."
L["Late casts on the ignore list do not flag a race."] = "Late casts on the ignore list do not flag a race."
L["Fights that beat an earlier best on their board, within these filters. A board's first fight does not count."] =
    "Fights that beat an earlier best on their board, within these filters. A board's first fight does not count."
L["The characters with a fight in these filters."] = "The characters with a fight in these filters."
L["The specs with a fight in these filters."] = "The specs with a fight in these filters."

-- The sections (modules/Results_Insights.lua)
L["DPS Progression"] = "DPS Progression"
L["DPS Progression (% of board best)"] = "DPS Progression (% of board best)"
L["By Board"] = "By Board"
L["By Target \195\151 Length"] = "By Target \195\151 Length"
L["Spec Comparison"] = "Spec Comparison"
L["Consistency"] = "Consistency"
L["By Character"] = "By Character"
L["Races By Character"] = "Races By Character"
L["By Character \195\151 Content"] = "By Character \195\151 Content"
L["Races By Character \195\151 Target"] = "Races By Character \195\151 Target"
L["Races By Character \195\151 Length"] = "Races By Character \195\151 Length"
L["Races Per Day"] = "Races Per Day"
L["Damage Tail After The Buzzer"] = "Damage Tail After The Buzzer"
L["Late Casts"] = "Late Casts"
L["Recent New Bests"] = "Recent New Bests"
L["Overall"] = "Overall"
L["Unknown spec"] = "Unknown spec"
L["%s of board best"] = "%s of board best"
L["Avg %s DPS"] = "Avg %s DPS"
L["Avg %s of board best"] = "Avg %s of board best"
L["Best %s DPS"] = "Best %s DPS"
L["Worst %s DPS"] = "Worst %s DPS"
L["Spread (CV) %s"] = "Spread (CV) %s"
L["%s: %d"] = "%s: %d"
L["%d-%d s"] = "%d-%d s"
L["%d+ s"] = "%d+ s"
L["Damage still landing after the buzzer, and counted."] = "Damage still landing after the buzzer, and counted."
L["%s (ignored)"] = "%s (ignored)"
L["On the ignore list: no flag. Right-click to stop ignoring it."] =
    "On the ignore list: no flag. Right-click to stop ignoring it."
L["No spell ID was recorded, so it cannot be ignored."] = "No spell ID was recorded, so it cannot be ignored."
L["Each one flags its race. Right-click to ignore it."] = "Each one flags its race. Right-click to ignore it."
L["%s  %s"] = "%s  %s"
L["%s DPS, up from %s"] = "%s DPS, up from %s"
L["Click to open the fight \194\183 right-click for options"] =
    "Click to open the fight \194\183 right-click for options"

-- The filter bar (modules/Results_Insights.lua)
L["Clean only"] = "Clean only"
L["Save these filters as this profile's default view of Insights."] =
    "Save these filters as this profile's default view of Insights."
L["Delete the saved view and go back to the stock one: every character, spec, content and date, fights and races."] =
    "Delete the saved view and go back to the stock one: every character, spec, content and date, fights and races."
L["Go back to the saved view (the stock one when none is saved). The saved view is kept."] =
    "Go back to the saved view (the stock one when none is saved). The saved view is kept."
L["The Insights view is saved."] = "The Insights view is saved."
L["The Insights view is back to the one the addon ships with."] =
    "The Insights view is back to the one the addon ships with."
