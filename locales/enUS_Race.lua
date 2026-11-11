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

-- The Race window's words (core/CombatTrail.lua)
L["Race mode is off. Turn it on at the top of the Race mode settings page."] =
    "Race mode is off. Turn it on at the top of the Race mode settings page."

-- `/ct race` (modules/RaceVerb.lua)
L["Blizzard's damage meter is unavailable: %s"] = "Blizzard's damage meter is unavailable: %s"
L["Combat Trail is turned off."] = "Combat Trail is turned off."
L["The race could not be armed."] = "The race could not be armed."
L["Nothing to cancel."] = "Nothing to cancel."
L["Usage: %s race ignore [show|add|remove|defaults] <spell ID, link or name>"] =
    "Usage: %s race ignore [show|add|remove|defaults] <spell ID, link or name>"
L["The late-cast ignore list is empty."] = "The late-cast ignore list is empty."
L["Late-cast ignore list:"] = "Late-cast ignore list:"
L["More than one spell is named '%s'. Use its spell ID or a shift-clicked link."] =
    "More than one spell is named '%s'. Use its spell ID or a shift-clicked link."
L["No spell named '%s' is known. Use its spell ID or a shift-clicked link."] =
    "No spell named '%s' is known. Use its spell ID or a shift-clicked link."
L["%s is already ignored."] = "%s is already ignored."
L["Late casts of %s no longer flag a race."] = "Late casts of %s no longer flag a race."
L["%s is not on the list."] = "%s is not on the list."
L["Late casts of %s flag a race again."] = "Late casts of %s flag a race again."
L["The late-cast ignore list is back to its defaults."] = "The late-cast ignore list is back to its defaults."
L["Usage: %s race arm [length] | cancel | show | hide | toggle | ignore [show|add|remove|defaults]"] =
    "Usage: %s race arm [length] | cancel | show | hide | toggle | ignore [show|add|remove|defaults]"
L["Race mode is not available on this client."] = "Race mode is not available on this client."
L["A race is already armed or running."] = "A race is already armed or running."
L["A race is still waiting for its result: let it finish, or type /ct race cancel."] =
    "A race is still waiting for its result: let it finish, or type /ct race cancel."
L["A race lasts from 0:10 to 15:00."] = "A race lasts from 0:10 to 15:00."
L["Leave combat to arm a race."] = "Leave combat to arm a race."
L["The last fight is still being read. Arm again in a moment."] =
    "The last fight is still being read. Arm again in a moment."
L["Race canceled."] = "Race canceled."
L["Race canceled: the fight goes on as a plain dummy fight."] =
    "Race canceled: the fight goes on as a plain dummy fight."
L["Result closed. The race stays in your history."] = "Result closed. The race stays in your history."

-- The verb's help row (settings/Slash.lua)
L["Race mode: /ct race arm [length], cancel, show, hide, toggle or ignore"] =
    "Race mode: /ct race arm [length], cancel, show, hide, toggle or ignore"

-- The Race mode page (settings/Race.lua)
L["Race"] = "Race"
L["Late-cast ignore list"] = "Late-cast ignore list"
L["Race window"] = "Race window"
L["Elapsed and time left"] = "Elapsed and time left"
L["Time left"] = "Time left"
L["Elapsed"] = "Elapsed"
L["Race mode"] = "Race mode"
L["Time a fight on a training dummy against a set length, and keep your best on each dummy and length. Off, no new race starts: the Race window stays hidden and nothing is shown or armed by itself. Your saved races stay in your history."] =
    "Time a fight on a training dummy against a set length, and keep your best on each dummy and length. Off, no new race starts: the Race window stays hidden and nothing is shown or armed by itself. Your saved races stay in your history."
L["Default race length"] = "Default race length"
L["The race length the Race window offers until you pick another. The last length you arm is remembered until you change this."] =
    "The race length the Race window offers until you pick another. The last length you arm is remembered until you change this."
L["Near a training dummy"] = "Near a training dummy"
L["Show the Race window near a training dummy"] = "Show the Race window near a training dummy"
L["Open the Race window by itself while a training dummy is your target or has its nameplate up, outside instances. It closes a few seconds after the last one is gone, and stays closed once you close it until you next come near one."] =
    "Open the Race window by itself while a training dummy is your target or has its nameplate up, outside instances. It closes a few seconds after the last one is gone, and stays closed once you close it until you next come near one."
L["Arm on a training dummy"] = "Arm on a training dummy"
L["Arm a race by itself when you target a training dummy out of combat, at the length Arm Race would use; your first hit starts it. Targeting anything else (or nothing) before the pull cancels it. Nothing arms in combat, in instances, over a result, or while a race waits for its result."] =
    "Arm a race by itself when you target a training dummy out of combat, at the length Arm Race would use; your first hit starts it. Targeting anything else (or nothing) before the pull cancels it. Nothing arms in combat, in instances, over a result, or while a race waits for its result."
L["Clock"] = "Clock"
L["Race clock"] = "Race clock"
L["What the Race window's clock shows while a race runs: the time elapsed and the time left side by side, or one of them alone, drawn larger."] =
    "What the Race window's clock shows while a race runs: the time elapsed and the time left side by side, or one of them alone, drawn larger."
L["Countdown"] = "Countdown"
L["Countdown cue sound"] = "Countdown cue sound"
L["A sound at 10, 5, 3, 2 and 1 seconds left, and with each number of the center countdown. Takes effect at once, in the race in progress too."] =
    "A sound at 10, 5, 3, 2 and 1 seconds left, and with each number of the center countdown. Takes effect at once, in the race in progress too."
L["Center-screen countdown"] = "Center-screen countdown"
L["Large numbers in the middle of the screen for the last seconds of the race, one a second down to 1, like a pull timer. Only you see them."] =
    "Large numbers in the middle of the screen for the last seconds of the race, one a second down to 1, like a pull timer. Only you see them."
L["Center countdown from (seconds)"] = "Center countdown from (seconds)"
L["How many seconds before the buzzer the center countdown starts. 3 to 10."] =
    "How many seconds before the buzzer the center countdown starts. 3 to 10."
L["At the buzzer"] = "At the buzzer"
L["Buzzer raid warning and sound"] = "Buzzer raid warning and sound"
L["A raid warning that says STOP, with a sound, the moment the race ends."] =
    "A raid warning that says STOP, with a sound, the moment the race ends."
L["Sticky-combat hint after (seconds)"] = "Sticky-combat hint after (seconds)"
L["How long combat may hold after the buzzer before the Race window suggests ways to drop it. 5 to 60 seconds."] =
    "How long combat may hold after the buzzer before the Race window suggests ways to drop it. 5 to 60 seconds."
L["Scoring rules"] = "Scoring rules"
L["Late-cast grace (seconds)"] = "Late-cast grace (seconds)"
L["A cast that starts later than this after the buzzer flags the race. 0 to 5 seconds. Applies to new races. Saved races keep the value they were raced with."] =
    "A cast that starts later than this after the buzzer flags the race. 0 to 5 seconds. Applies to new races. Saved races keep the value they were raced with."
L["Damage-restart gap (seconds)"] = "Damage-restart gap (seconds)"
L["Your damage going quiet for this long after the buzzer, then landing again, flags the race as damage restarted. 3 to 15 seconds. Applies to new races. Saved races keep the value they were raced with."] =
    "Your damage going quiet for this long after the buzzer, then landing again, flags the race as damage restarted. 3 to 15 seconds. Applies to new races. Saved races keep the value they were raced with."
L["Spell IDs, comma-separated, whose casts after the grace never flag a race. Applies to every saved race: a race keeps its casts, so taking a spell off the list flags them again. Unlike the grace, nothing is frozen into a race. 8690 stands for every hearthstone."] =
    "Spell IDs, comma-separated, whose casts after the grace never flag a race. Applies to every saved race: a race keeps its casts, so taking a spell off the list flags them again. Unlike the grace, nothing is frozen into a race. 8690 stands for every hearthstone."
L["Attach to the DPS HUD"] = "Attach to the DPS HUD"
L["Keep the Race window beside the DPS HUD, moving with it. Off, it stands on its own wherever you drag it; Lock frame on the General page holds it in place."] =
    "Keep the Race window beside the DPS HUD, moving with it. Off, it stands on its own wherever you drag it; Lock frame on the General page holds it in place."
L["Side of the DPS HUD"] = "Side of the DPS HUD"
L["Which side of the DPS HUD the attached Race window stands on."] =
    "Which side of the DPS HUD the attached Race window stands on."
L["Race mode is DPS Race, now part of Combat Trail: a race is a fight on a training dummy, timed to a set length and kept in your history."] =
    "Race mode is DPS Race, now part of Combat Trail: a race is a fight on a training dummy, timed to a set length and kept in your history."
L["(all hearthstones, %d)"] = "(all hearthstones, %d)"
L["Put the list back to its six defaults: Invisibility, Vanish, Feign Death, every hearthstone, Shadowmeld and Greater Invisibility. The other Race mode settings are not touched."] =
    "Put the list back to its six defaults: Invisibility, Vanish, Feign Death, every hearthstone, Shadowmeld and Greater Invisibility. The other Race mode settings are not touched."
L["Spells whose casts after the grace never flag a race, on every saved race. Taking one off flags its casts again."] =
    "Spells whose casts after the grace never flag a race, on every saved race. Taking one off flags its casts again."
L["Ignore a spell"] = "Ignore a spell"
L["A spell ID, a shift-clicked spell link, or the name of a spell a race cast late. \"Hearthstone\" adds every hearthstone."] =
    "A spell ID, a shift-clicked spell link, or the name of a spell a race cast late. \"Hearthstone\" adds every hearthstone."
L["No spell is ignored: every late cast flags its race."] = "No spell is ignored: every late cast flags its race."
L["Restore every Race mode setting on this profile to its addon default, the late-cast ignore list among them. Saved races are not touched."] =
    "Restore every Race mode setting on this profile to its addon default, the late-cast ignore list among them. Saved races are not touched."
