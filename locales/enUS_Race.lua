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
L["Open the Race window by itself, with the DPS HUD beside it, while a training dummy is your target or has its nameplate up, outside instances. It closes a few seconds after the last one is gone, and stays closed once you close it until you next come near one."] =
    "Open the Race window by itself, with the DPS HUD beside it, while a training dummy is your target or has its nameplate up, outside instances. It closes a few seconds after the last one is gone, and stays closed once you close it until you next come near one."
L["Show the DPS HUD near a training dummy"] = "Show the DPS HUD near a training dummy"
L["Open the DPS HUD by itself near a training dummy, with the Race window beside it: the Race window never shows without the DPS HUD, so this or Show the Race window near a training dummy opens both. The DPS HUD fades after a fight by its own rules and takes the Race window with it; both come back the next time a dummy is targeted or comes into view. Both close a few seconds after the last dummy is gone, unless a fight is on the DPS HUD or you opened or pinned it yourself. Once you close either, they stay closed until you next come near a dummy."] =
    "Open the DPS HUD by itself near a training dummy, with the Race window beside it: the Race window never shows without the DPS HUD, so this or Show the Race window near a training dummy opens both. The DPS HUD fades after a fight by its own rules and takes the Race window with it; both come back the next time a dummy is targeted or comes into view. Both close a few seconds after the last dummy is gone, unless a fight is on the DPS HUD or you opened or pinned it yourself. Once you close either, they stay closed until you next come near a dummy."
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
L["Match the DPS HUD's height"] = "Match the DPS HUD's height"
L["Race window width (px)"] = "Race window width (px)"
L["How many times a second everything live on the DPS HUD and the Race window redraws, in a fight or a race: the clock, Damage and DPS, the pace bar, the damage chart and the spell rows, and the Race window's clock, Best by now and checkpoints. Faster reads the damage meter more often."] =
    "How many times a second everything live on the DPS HUD and the Race window redraws, in a fight or a race: the clock, Damage and DPS, the pace bar, the damage chart and the spell rows, and the Race window's clock, Best by now and checkpoints. Faster reads the damage meter more often."
L["Race window height (px)"] = "Race window height (px)"
L["Attached on the left or right of the DPS HUD, the Race window takes the HUD's height and keeps it as the HUD resizes, never shorter than it needs. Above or below the HUD, or on its own, it keeps its own height."] =
    "Attached on the left or right of the DPS HUD, the Race window takes the HUD's height and keeps it as the HUD resizes, never shorter than it needs. Above or below the HUD, or on its own, it keeps its own height."
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

-- A race's time (modules/Format.lua)
L["+%.1f"] = "+%.1f"
L["%s / %s"] = "%s / %s"

-- The Race window's bodies (modules/RaceWindow_States.lua)
L["Race length"] = "Race length"
L["How long the next race runs. Pick a preset or Custom; the choice stays for your next race."] =
    "How long the next race runs. Pick a preset or Custom; the choice stays for your next race."
L["Race for this long. Your bests are kept per race length, so each length has its own."] =
    "Race for this long. Your bests are kept per race length, so each length has its own."
L["Custom"] = "Custom"
L["Set a race length of your own. Click, then type it in."] =
    "Set a race length of your own. Click, then type it in."
L["Custom length"] = "Custom length"
L["Type a length from 10 seconds to 15 minutes, such as 90, 1:30 or 3m, then press Enter. Escape backs out."] =
    "Type a length from 10 seconds to 15 minutes, such as 90, 1:30 or 3m, then press Enter. Escape backs out."
L["The training dummy you have targeted, its dummy kind and its creature ID. The kind decides which board the race counts on."] =
    "The training dummy you have targeted, its dummy kind and its creature ID. The kind decides which board the race counts on."
L["Arm Race"] = "Arm Race"
L["Get this race ready. The clock starts on your first hit. When you can't arm, the line under this button says why."] =
    "Get this race ready. The clock starts on your first hit. When you can't arm, the line under this button says why."
L["The length of this race. It starts counting down when your first hit lands."] =
    "The length of this race. It starts counting down when your first hit lands."
L["First hit"] = "First hit"
L["Nothing counts until your damage lands, so pre-cast and pre-pot as you would on a pull."] =
    "Nothing counts until your damage lands, so pre-cast and pre-pot as you would on a pull."
L["Drop the race. The pull goes on as a plain dummy fight, saved under your recording filters."] =
    "Drop the race. The pull goes on as a plain dummy fight, saved under your recording filters."
L["The race's clock. Race mode > Race clock picks what shows here."] =
    "The race's clock. Race mode > Race clock picks what shows here."
L["How long this race has run."] = "How long this race has run."
L["How long until the buzzer."] = "How long until the buzzer."
L["How much of the race is left: the bar empties to the buzzer, a mark at each quarter. It and the countdown turn from green to yellow after half the race, and red for the last 10 seconds."] =
    "How much of the race is left: the bar empties to the buzzer, a mark at each quarter. It and the countdown turn from green to yellow after half the race, and red for the last 10 seconds."
L["Best to beat"] = "Best to beat"
L["Your best on this race board: the mark this race is after."] =
    "Your best on this race board: the mark this race is after."
L["Against your best"] = "Against your best"
L["This race beside the best you had on this race board before it, with the difference."] =
    "This race beside the best you had on this race board before it, with the difference."
L["Top races"] = "Top races"
L["Your top races on this race board (character, spec, dummy kind and length), ranked by race DPS."] =
    "Your top races on this race board (character, spec, dummy kind and length), ranked by race DPS."
L["Left of %s"] = "Left of %s"
L["Elapsed of %s"] = "Elapsed of %s"
L["STOP"] = "STOP"
L["The buzzer has gone: stop casting. Damage still landing counts, but a cast that starts after the grace flags the race."] =
    "The buzzer has gone: stop casting. Damage still landing counts, but a cast that starts after the grace flags the race."
L["Damage stopped"] = "Damage stopped"
L["How long after the buzzer your last damage landed, as far as the race has seen."] =
    "How long after the buzzer your last damage landed, as far as the race has seen."
L["Combat ended"] = "Combat ended"
L["Combat ended before the buzzer, this far into the race, so the race is incomplete."] =
    "Combat ended before the buzzer, this far into the race, so the race is incomplete."
L["In combat"] = "In combat"
L["How long you have stayed in combat since the buzzer. The result is read when combat ends."] =
    "How long you have stayed in combat since the buzzer. The result is read when combat ends."
L["How long you have been in combat since the race ended. The result is read when combat ends."] =
    "How long you have been in combat since the race ended. The result is read when combat ends."
L["Out of combat"] = "Out of combat"
L["Combat is over, so the result can be read."] = "Combat is over, so the result can be read."
L["Result pending"] = "Result pending"
L["The damage meter can only be read once combat ends, so the result waits for that. Stop Now takes it as soon as it can."] =
    "The damage meter can only be read once combat ends, so the result waits for that. Stop Now takes it as soon as it can."
L["Stop Now"] = "Stop Now"
L["Take the result now instead of waiting out the damage tail. Out of combat it is read at once; in combat it is read the moment combat ends, and damage up to then counts."] =
    "Take the result now instead of waiting out the damage tail. Out of combat it is read at once; in combat it is read the moment combat ends, and damage up to then counts."
L["Casts that started after the grace. The result flags them unless the spell is on the late-cast ignore list."] =
    "Casts that started after the grace. The result flags them unless the spell is on the late-cast ignore list."
L["How long after the buzzer a cast may start before it is flagged. Set it on the Race mode page."] =
    "How long after the buzzer a cast may start before it is flagged. Set it on the Race mode page."
L["Score"] = "Score"
L["This race's damage: the whole fight's, as the damage meter read it after combat."] =
    "This race's damage: the whole fight's, as the damage meter read it after combat."
L["Race DPS"] = "Race DPS"
L["The score over the race length, or over the time raced when the race is incomplete. It is the figure the race board ranks."] =
    "The score over the race length, or over the time raced when the race is incomplete. It is the figure the race board ranks."
L["This race beat your best on this race board, by this much."] =
    "This race beat your best on this race board, by this much."
L["This race sets the best on this race board: there was no earlier race to beat."] =
    "This race sets the best on this race board: there was no earlier race to beat."
L["How far this race fell short of your best on this race board."] =
    "How far this race fell short of your best on this race board."
L["This race matched your best on this race board."] = "This race matched your best on this race board."
L["New Race"] = "New Race"
L["Back to the Arm Race screen at this length. This race stays saved."] =
    "Back to the Arm Race screen at this length. This race stays saved."
L["Open"] = "Open"
L["Open this race in the Results window, with its chart and its spells."] =
    "Open this race in the Results window, with its chart and its spells."
L["Pick a chat channel and post this race's result there."] =
    "Pick a chat channel and post this race's result there."
L["Remove this race from your history, after a confirmation. A best it holds goes with it."] =
    "Remove this race from your history, after a confirmation. A best it holds goes with it."
L["No target"] = "No target"
L["First hit starts the clock"] = "First hit starts the clock"
L["Pre-cast and pre-pot as you would on a pull. The clock starts when damage lands, not when you press the button."] =
    "Pre-cast and pre-pot as you would on a pull. The clock starts when damage lands, not when you press the button."
L["into the race"] = "into the race"
L["s"] = "s"
L["after the buzzer"] = "after the buzzer"
L["since the buzzer"] = "since the buzzer"
L["since the race ended"] = "since the race ended"
L["combat ended"] = "combat ended"
L["1 late cast \194\183 +%.1fs"] = "1 late cast \194\183 +%.1fs"
L["%d late casts \194\183 +%.1fs"] = "%d late casts \194\183 +%.1fs"
L["Grace %.1fs"] = "Grace %.1fs"
L["Damage still landing (DoTs, travel time) counts. Casts that start more than %.1fs after the buzzer are flagged on the result."] =
    "Damage still landing (DoTs, travel time) counts. Casts that start more than %.1fs after the buzzer are flagged on the result."
L["Reading the result"] = "Reading the result"
L["Reading when combat ends"] = "Reading when combat ends"
L["Waiting for combat to end"] = "Waiting for combat to end"
L["Restarted +%.1fs"] = "Restarted +%.1fs"
L["Reloaded"] = "Reloaded"
L["Session by list"] = "Session by list"
L["Shared session"] = "Shared session"
L["Incomplete: died"] = "Incomplete: died"
L["Incomplete (combat ended at %s)"] = "Incomplete (combat ended at %s)"
L["Lost"] = "Lost"
L["Died"] = "Died"
L["Right-click to ignore a spell for late casts, or count it again."] =
    "Right-click to ignore a spell for late casts, or count it again."
L["%d ignored"] = "%d ignored"
L["Late casts on the ignore list: they flag nothing."] = "Late casts on the ignore list: they flag nothing."
L["New best +%.1f%%"] = "New best +%.1f%%"
L["%+.1f%% vs best"] = "%+.1f%% vs best"
L["Time %s"] = "Time %s"
L["The race length, then how long your damage kept landing after the buzzer (DoTs, travel time). An incomplete race shows its time in combat against the length."] =
    "The race length, then how long your damage kept landing after the buzzer (DoTs, travel time). An incomplete race shows its time in combat against the length."
L["Couldn't read the result"] = "Couldn't read the result"
L["The race board this race counts on: the dummy's kind and the race length, for this character and spec."] =
    "The race board this race counts on: the dummy's kind and the race length, for this character and spec."

-- The race board's figures (modules/RaceWindow_Board.lua)
L["%+.1f"] = "%+.1f"
L["Item level"] = "Item level"
L["This race"] = "This race"
L["Diff"] = "Diff"
L["#"] = "#"
L["Best by now"] = "Best by now"
L["Current"] = "Current"
L["Where your best on this race board stood at this second of its race, read off its straight line: its score over the race length, times the time raced. Beside it, Current: your own damage so far, as the DPS HUD last read it. The bar over it is the DPS HUD's pace bar, thinner: green past the middle tick, red short of it."] =
    "Where your best on this race board stood at this second of its race, read off its straight line: its score over the race length, times the time raced. Beside it, Current: your own damage so far, as the DPS HUD last read it. The bar over it is the DPS HUD's pace bar, thinner: green past the middle tick, red short of it."
L["Checkpoints"] = "Checkpoints"
L["best \194\183 current"] = "best \194\183 current"
L["Your best's damage at each quarter of the race, off its straight line, and under it yours as the clock passed that quarter (the DPS HUD's reading then). A quarter not reached yet shows a dash. Once it is passed, the bar under them grows from its middle tick: green as far as you were ahead of your best there, red as far behind. The passed ones dim and are outlined green; the one the clock is in is outlined amber."] =
    "Your best's damage at each quarter of the race, off its straight line, and under it yours as the clock passed that quarter (the DPS HUD's reading then). A quarter not reached yet shows a dash. Once it is passed, the bar under them grows from its middle tick: green as far as you were ahead of your best there, red as far behind. The passed ones dim and are outlined green; the one the clock is in is outlined amber."

-- The Race window's Your best card (modules/RaceWindow_Best.lua)
L["Your best"] = "Your best"
L["Length: %s"] = "Length: %s"
L["Score: %s"] = "Score: %s"
L["Race DPS: %s"] = "Race DPS: %s"
L["Click to open this race in Results."] = "Click to open this race in Results."
L["Target a training dummy to see your best."] = "Target a training dummy to see your best."
L["No race yet: this one sets the mark."] = "No race yet: this one sets the mark."

-- The Race window's shell (modules/RaceWindow.lua)
L["Attach to or detach from the DPS HUD"] = "Attach to or detach from the DPS HUD"
L["Lock or unlock the Race window"] = "Lock or unlock the Race window"
L["Race mode settings"] = "Race mode settings"
L["No target: target a training dummy, then arm."] = "No target: target a training dummy, then arm."
L["%s is no training dummy: a race armed now is canceled when that pull starts."] =
    "%s is no training dummy: a race armed now is canceled when that pull starts."
L["Your target"] = "Your target"
L["Combat is holding. Walk out of range, or use an ability that drops combat (Feign Death, Vanish, Shadowmeld, Invisibility). Your score is safe: it waits for combat to end, however long that takes."] =
    "Combat is holding. Walk out of range, or use an ability that drops combat (Feign Death, Vanish, Shadowmeld, Invisibility). Your score is safe: it waits for combat to end, however long that takes."

-- The center countdown and the buzzer (modules/Countdown.lua) use STOP above; the race toast's row
-- (settings/History.lua) and the race's own chat lines (modules/Share.lua), race plan Task C2
L["Toast a race's new best"] = "Toast a race's new best"
L["When a race sets a new best on its board (character, spec, dummy kind and length), a toast near the top of the screen says by how much. A board's first race has nothing to beat and shows none."] =
    "When a race sets a new best on its board (character, spec, dummy kind and length), a toast near the top of the screen says by how much. A board's first race has nothing to beat and shows none."
L["Armed: %s on %s. First hit starts the clock."] = "Armed: %s on %s. First hit starts the clock."
L["your target"] = "your target"
L["new best (+%.1f%%)"] = "new best (+%.1f%%)"
L["new best"] = "new best"
L["%+.1f%% vs best"] = "%+.1f%% vs best"
L["tail +%.1fs"] = "tail +%.1fs"
L["%s damage · %s DPS in %s on %s"] = "%s damage · %s DPS in %s on %s"
L["Couldn't read the race's result, so it is not saved as a race."] =
    "Couldn't read the race's result, so it is not saved as a race."

-- Races in the Results window (modules/Results_Races.lua, Results_RaceDetail.lua, Results.lua; Task D1)
L["Fights and races"] = "Fights and races"
L["Fights only"] = "Fights only"
L["Races only"] = "Races only"
L["Any race length"] = "Any race length"
L["All dummy kinds"] = "All dummy kinds"
L["Hide flagged"] = "Hide flagged"
L["Include incomplete"] = "Include incomplete"
L["Only best"] = "Only best"
L["Flagged"] = "Flagged"
L["Incomplete"] = "Incomplete"
L["Race length: %s"] = "Race length: %s"
L["Group: Race length"] = "Group: Race length"
L["Group: Dummy kind + length"] = "Group: Dummy kind + length"
L["Group: Spec + dummy kind + length"] = "Group: Spec + dummy kind + length"
L["The race's score over its race length."] = "The race's score over its race length."
L["The race's score over the time raced: combat ended before the buzzer."] =
    "The race's score over the time raced: combat ended before the buzzer."
L["The race's score over %s, its first hit to the fight's end: combat came back inside the grace after it ended before the buzzer."] =
    "The race's score over %s, its first hit to the fight's end: combat came back inside the grace after it ended before the buzzer."
L["The fight around it: %s DPS over its own length."] = "The fight around it: %s DPS over its own length."
L["%s score"] = "%s score"
L["The race's score: the meter session's total, you and your pet, read after combat."] =
    "The race's score: the meter session's total, you and your pet, read after combat."
L["%s of a %s race"] = "%s of a %s race"
L["Combat ended before the buzzer."] = "Combat ended before the buzzer."
L["Race %s"] = "Race %s"
L["The race length you picked."] = "The race length you picked."
L["Damage stopped %ss after the buzzer."] = "Damage stopped %ss after the buzzer."
L["Usage: /ct results, or /ct results show, hide, toggle, insights or races"] =
    "Usage: /ct results, or /ct results show, hide, toggle, insights or races"

-- A race's detail: the Timing and Flags sections, its figures, the late-cast menu
L["Timing"] = "Timing"
L["Flags"] = "Flags"
L["Tail (damage still landing)"] = "Tail (damage still landing)"
L["Grace"] = "Grace"
L["Late cast"] = "Late cast"
L["Restart"] = "Restart"
L["0:00 \226\128\148 race %s \226\128\148 buzzer"] = "0:00 \226\128\148 race %s \226\128\148 buzzer"
L["+%ds"] = "+%ds"
L["Combat ended at %s, before the buzzer."] = "Combat ended at %s, before the buzzer."
L["Damage stopped %ss after the buzzer"] = "Damage stopped %ss after the buzzer"
L["combat ended %ss"] = "combat ended %ss"
L["The race still counts toward bests."] = "The race still counts toward bests."
L["%s started +%.1fs after the buzzer"] = "%s started +%.1fs after the buzzer"
L["%s (grace %.1fs)."] = "%s (grace %.1fs)."
L["After the quiet gap past the buzzer: a new pull."] = "After the quiet gap past the buzzer: a new pull."
L["The meter session was found by its place in Blizzard's list, not by its ID."] =
    "The meter session was found by its place in Blizzard's list, not by its ID."
L["The pull carried on the meter session that was open before the race was armed, so its score is the session's total less what it held then."] =
    "The pull carried on the meter session that was open before the race was armed, so its score is the session's total less what it held then."
L["It does not count toward bests."] = "It does not count toward bests."
L["1 ignored late cast"] = "1 ignored late cast"
L["%d ignored late casts"] = "%d ignored late casts"
L["On the late-cast ignore list, so no flag. Right-click to count a spell again."] =
    "On the late-cast ignore list, so no flag. Right-click to count a spell again."
L["DPS \194\183 Incomplete"] = "DPS \194\183 Incomplete"
L["An incomplete race is compared, but never sets the best."] =
    "An incomplete race is compared, but never sets the best."
L["Ignore for late casts"] = "Ignore for late casts"

-- Test mode's sample race, the sim's race scenarios and the sample races (modules/Preview.lua,
-- modules/SimRace.lua, modules/MockRaces.lua; race plan Task E1)
L["Test mode: sample data in the lanes, the HUD and the Results window; /ct test race [armed|running|result] holds a sample race"] =
    "Test mode: sample data in the lanes, the HUD and the Results window; /ct test race [armed|running|result] holds a sample race"
L["Usage: %s test race [armed|running|result]"] = "Usage: %s test race [armed|running|result]"
L["Race mode is off: turn it on on the Race mode page to race."] =
    "Race mode is off: turn it on on the Race mode page to race."
L["Test mode is not available during a race."] = "Test mode is not available during a race."
L["Test mode ended: a race was armed."] = "Test mode ended: a race was armed."
L["Race: new best"] = "Race: new best"
L["a race that beats your best on its board"] = "a race that beats your best on its board"
L["Race: behind the best"] = "Race: behind the best"
L["a race behind your best on its board"] = "a race behind your best on its board"
L["Race: first race"] = "Race: first race"
L["the first race on its board: nothing to beat"] = "the first race on its board: nothing to beat"
L["Race: incomplete"] = "Race: incomplete"
L["combat ends before the buzzer"] = "combat ends before the buzzer"
L["Race: you die"] = "Race: you die"
L["you die before the buzzer"] = "you die before the buzzer"
L["Race: late cast"] = "Race: late cast"
L["a cast after the buzzer flags the race"] = "a cast after the buzzer flags the race"
L["Race: shared session"] = "Race: shared session"
L["the pull carries on a meter session: no pace"] = "the pull carries on a meter session: no pace"
L["Race: combat holds on"] = "Race: combat holds on"
L["combat holds on after the buzzer: the hint shows"] = "combat holds on after the buzzer: the hint shows"
L["Armed"] = "Armed"
L["Race starts"] = "Race starts"
L["Racing (%d s)"] = "Racing (%d s)"
L["Buzzer"] = "Buzzer"
L["Result card"] = "Result card"
L["The race is still running."] = "The race is still running."
L["Waiting for the result."] = "Waiting for the result."
L["Waiting for the result (combat holds on)."] = "Waiting for the result (combat holds on)."
L["The result card holds."] = "The result card holds."
L["Sample note: opener with every cooldown"] = "Sample note: opener with every cooldown"
L["Sample note: five dummies in reach"] = "Sample note: five dummies in reach"
L["Sample note: another character's best"] = "Sample note: another character's best"
L["Move the lanes, the DPS HUD, the Race window, the Results window and the new-best toast back to where they started."] =
    "Move the lanes, the DPS HUD, the Race window, the Results window and the new-best toast back to where they started."
