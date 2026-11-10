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

-- The lanes' default labels (modules/LaneCasts.lua, defaults/Profile.lua)
L["You"] = "You"
L["Pet"] = "Pet"

-- The lanes' placement (modules/LaneAnchor.lua): the edit overlay's labels and the one-line notices
L["Player lane"] = "Player lane"
L["Pet lane"] = "Pet lane"
L["%s: drag to move"] = "%s: drag to move"
L["%s: docked, so it moves with the lane it follows"] = "%s: docked, so it moves with the lane it follows"
L["%s: on its unit frame, so it moves with that frame"] = "%s: on its unit frame, so it moves with that frame"
L["The Player and Pet lanes are docked to each other, so neither can dock. Both sit at their own place until one is undocked."] =
    "The Player and Pet lanes are docked to each other, so neither can dock. Both sit at their own place until one is undocked."
L["The %s cannot find its unit frame (%s), so it sits at its own place."] =
    "The %s cannot find its unit frame (%s), so it sits at its own place."
L["The %s cannot use the unit frame %s, so it sits at its own place."] =
    "The %s cannot use the unit frame %s, so it sits at its own place."

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

-- The Lanes page (settings/Lanes.lua): its tabs, rows, acts and the `lane` verb
L["Size and position"] = "Size and position"
L["Icons"] = "Icons"
L["Background and border"] = "Background and border"
L["Ticks and labels"] = "Ticks and labels"
L["Visibility"] = "Visibility"
L["Ignored spells"] = "Ignored spells"
L["Newest at the right, moving left"] = "Newest at the right, moving left"
L["Newest at the left, moving right"] = "Newest at the left, moving right"
L["Newest at the bottom, moving up"] = "Newest at the bottom, moving up"
L["Newest at the top, moving down"] = "Newest at the top, moving down"
L["Free"] = "Free"
L["Docked to the other lane"] = "Docked to the other lane"
L["Unit frame"] = "Unit frame"
L["Top left"] = "Top left"
L["Top"] = "Top"
L["Top right"] = "Top right"
L["Left"] = "Left"
L["Center"] = "Center"
L["Right"] = "Right"
L["Bottom left"] = "Bottom left"
L["Bottom"] = "Bottom"
L["Bottom right"] = "Bottom right"
L["Every 1.5 seconds"] = "Every 1.5 seconds"
L["Your global cooldown, with haste"] = "Your global cooldown, with haste"
L["Every second"] = "Every second"
L["Always"] = "Always"
L["In combat only"] = "In combat only"
L["In combat or with a target"] = "In combat or with a target"
L["Never"] = "Never"
L["Background"] = "Background"
L["Low"] = "Low"
L["Medium"] = "Medium"
L["High"] = "High"
L["Match host"] = "Match host"
L["Open world"] = "Open world"
L["Dungeons"] = "Dungeons"
L["Raids"] = "Raids"
L["Delves"] = "Delves"
L["Battlegrounds"] = "Battlegrounds"
L["Arenas"] = "Arenas"
L["Lane"] = "Lane"
L["Enable this lane"] = "Enable this lane"
L["Show this lane and listen for its casts. Off, it draws nothing and listens for nothing."] =
    "Show this lane and listen for its casts. Off, it draws nothing and listens for nothing."
L["Size"] = "Size"
L["Direction"] = "Direction"
L["Which edge the newest cast appears at, and which way the casts move away from it."] =
    "Which edge the newest cast appears at, and which way the casts move away from it."
L["Scale"] = "Scale"
L["The size of the whole lane, its icons, ticks and label included."] =
    "The size of the whole lane, its icons, ticks and label included."
L["Lane length"] = "Lane length"
L["How long the lane is, in pixels, from the now edge to the far end."] =
    "How long the lane is, in pixels, from the now edge to the far end."
L["Seconds shown"] = "Seconds shown"
L["How many seconds a cast takes to cross the lane."] = "How many seconds a cast takes to cross the lane."
L["Icon size"] = "Icon size"
L["The size of each cast's icon, in pixels. The lane is this tall, or this wide when it runs up or down."] =
    "The size of each cast's icon, in pixels. The lane is this tall, or this wide when it runs up or down."
L["Icon spacing"] = "Icon spacing"
L["The smallest gap between two icons, in pixels. A fast burst of casts pushes older icons along to keep it."] =
    "The smallest gap between two icons, in pixels. A fast burst of casts pushes older icons along to keep it."
L["Position"] = "Position"
L["Anchor"] = "Anchor"
L["Free: the lane sits where you put it. Docked: it follows the other lane. Unit frame: it follows your unit frame (the pet's for the Pet lane), from ElvUI, Shadowed Unit Frames, Cell, PitBull, UnhaltedUnitFrames or the game's own."] =
    "Free: the lane sits where you put it. Docked: it follows the other lane. Unit frame: it follows your unit frame (the pet's for the Pet lane), from ElvUI, Shadowed Unit Frames, Cell, PitBull, UnhaltedUnitFrames or the game's own."
L["Frame by name"] = "Frame by name"
L["The name of any frame to sit on instead of the one found for you. Empty finds it for you."] =
    "The name of any frame to sit on instead of the one found for you. Empty finds it for you."
L["Point"] = "Point"
L["The point of the lane that is placed."] = "The point of the lane that is placed."
L["Relative point"] = "Relative point"
L["The point it is placed at: on the screen, on the other lane or on the unit frame."] =
    "The point it is placed at: on the screen, on the other lane or on the unit frame."
L["Gap"] = "Gap"
L["The space between the lane and what it follows, in pixels."] =
    "The space between the lane and what it follows, in pixels."
L["Horizontal offset of the lane's own place, in pixels. A docked lane, or one on its unit frame, uses it when what it follows is missing."] =
    "Horizontal offset of the lane's own place, in pixels. A docked lane, or one on its unit frame, uses it when what it follows is missing."
L["Vertical offset of the lane's own place, in pixels. A docked lane, or one on its unit frame, uses it when what it follows is missing."] =
    "Vertical offset of the lane's own place, in pixels. A docked lane, or one on its unit frame, uses it when what it follows is missing."
L["Layer"] = "Layer"
L["Frame strata"] = "Frame strata"
L["Match host draws the lane on its unit frame's strata, and is offered while the lane is on one."] =
    "Match host draws the lane on its unit frame's strata, and is offered while the lane is on one."
L["Frame level"] = "Frame level"
L["Added to the lane's level on its strata. Raise it to draw this lane over a frame on the same strata."] =
    "Added to the lane's level on its strata. Raise it to draw this lane over a frame on the same strata."
L["Icon zoom"] = "Icon zoom"
L["How much of each icon's edge is cropped away."] = "How much of each icon's edge is cropped away."
L["Fade portion"] = "Fade portion"
L["How much of the lane, at its far end, icons fade out over. 0 never fades."] =
    "How much of the lane, at its far end, icons fade out over. 0 never fades."
L["Mark interrupted casts"] = "Mark interrupted casts"
L["Draw a red X on a cast that was interrupted or canceled after it started."] =
    "Draw a red X on a cast that was interrupted or canceled after it started."
L["Stack repeated casts"] = "Stack repeated casts"
L["Fold a cast of the same spell as the newest icon into it, with a count, instead of a new icon."] =
    "Fold a cast of the same spell as the newest icon into it, with a count, instead of a new icon."
L["Show spell tooltip"] = "Show spell tooltip"
L["Show the spell's tooltip while the mouse is over its icon. Off, the icons let the mouse through."] =
    "Show the spell's tooltip while the mouse is over its icon. Off, the icons let the mouse through."
L["Show spell name"] = "Show spell name"
L["Write each spell's name under its icon."] = "Write each spell's name under its icon."
L["Border"] = "Border"
L["The texture each icon's border is drawn with. Empty draws it flat."] =
    "The texture each icon's border is drawn with. Empty draws it flat."
L["Glow"] = "Glow"
L["Glow long cooldowns"] = "Glow long cooldowns"
L["Ring the icon of a spell with a long cooldown, read from the spell's base cooldown."] =
    "Ring the icon of a spell with a long cooldown, read from the spell's base cooldown."
L["Long cooldown (seconds)"] = "Long cooldown (seconds)"
L["The shortest base cooldown, in seconds, that glows."] =
    "The shortest base cooldown, in seconds, that glows."
L["Glow color"] = "Glow color"
L["Show background"] = "Show background"
L["Fill the lane behind its icons."] = "Fill the lane behind its icons."
L["Background texture"] = "Background texture"
L["The texture the background is drawn with, tinted by its color. Empty fills it flat."] =
    "The texture the background is drawn with, tinted by its color. Empty fills it flat."
L["Background color"] = "Background color"
L["Padding"] = "Padding"
L["Space between the lane's edge and its icons, in pixels."] =
    "Space between the lane's edge and its icons, in pixels."
L["The texture the lane's border is drawn with. Empty draws it flat."] =
    "The texture the lane's border is drawn with. Empty draws it flat."
L["Ticks"] = "Ticks"
L["Show GCD ticks"] = "Show GCD ticks"
L["Draw a thin line across the lane at each global cooldown back from now."] =
    "Draw a thin line across the lane at each global cooldown back from now."
L["Tick spacing"] = "Tick spacing"
L["How far apart the ticks are. With haste, they follow your global cooldown, read out of combat."] =
    "How far apart the ticks are. With haste, they follow your global cooldown, read out of combat."
L["Tick width"] = "Tick width"
L["How thick each tick is, in pixels."] = "How thick each tick is, in pixels."
L["Tick color"] = "Tick color"
L["Now line"] = "Now line"
L["Show now line"] = "Show now line"
L["Draw a line at the edge where each cast appears."] = "Draw a line at the edge where each cast appears."
L["Now line color"] = "Now line color"
L["Label"] = "Label"
L["Show label"] = "Show label"
L["Name the lane beside it."] = "Name the lane beside it."
L["Label position"] = "Label position"
L["Which side of the lane the label sits on."] = "Which side of the lane the label sits on."
L["Label text"] = "Label text"
L["The label's words. Empty shows your pet's name, or Pet with no pet out."] =
    "The label's words. Empty shows your pet's name, or Pet with no pet out."
L["The label's words. Empty shows You."] = "The label's words. Empty shows You."
L["Label font"] = "Label font"
L["The face the label is drawn in. Empty uses the skin's font."] =
    "The face the label is drawn in. Empty uses the skin's font."
L["When"] = "When"
L["Show the lane"] = "Show the lane"
L["When the lane shows. In combat or with a target also shows it while you have something targeted."] =
    "When the lane shows. In combat or with a target also shows it while you have something targeted."
L["Hide after combat (seconds)"] = "Hide after combat (seconds)"
L["How long the lane stays after combat ends, in seconds, when it shows in combat only."] =
    "How long the lane stays after combat ends, in seconds, when it shows in combat only."
L["Opacity in combat"] = "Opacity in combat"
L["How opaque the whole lane is while you are in combat."] =
    "How opaque the whole lane is while you are in combat."
L["Opacity out of combat"] = "Opacity out of combat"
L["How opaque the whole lane is out of combat."] = "How opaque the whole lane is out of combat."
L["Where"] = "Where"
L["Show the lane here. Off, it hides here whatever the rules above say."] =
    "Show the lane here. Off, it hides here whatever the rules above say."
L["Hide when"] = "Hide when"
L["Mounted"] = "Mounted"
L["Hide the lane while you are mounted."] = "Hide the lane while you are mounted."
L["In a vehicle"] = "In a vehicle"
L["Hide the lane while you are in a vehicle."] = "Hide the lane while you are in a vehicle."
L["In a pet battle"] = "In a pet battle"
L["Hide the lane during a pet battle."] = "Hide the lane during a pet battle."
L["Resting"] = "Resting"
L["Hide the lane while you rest in a city or an inn."] = "Hide the lane while you rest in a city or an inn."
L["The %s now looks like the %s."] = "The %s now looks like the %s."
L["The %s is back to its defaults."] = "The %s is back to its defaults."
L["Reset the %s to its defaults? Every setting on its tabs goes back, and so does its ignore list. The other lane is not affected."] =
    "Reset the %s to its defaults? Every setting on its tabs goes back, and so does its ignore list. The other lane is not affected."
L["The %s is switched off. Enable it to see the preview."] =
    "The %s is switched off. Enable it to see the preview."
L["The %s is hidden by its Visibility tab right now. Unlock the lanes to see it."] =
    "The %s is hidden by its Visibility tab right now. Unlock the lanes to see it."
L["Usage: /kct lane player|pet on|off"] = "Usage: /kct lane player|pet on|off"
L["The %s is on."] = "The %s is on."
L["The %s is off."] = "The %s is off."
L["Unlock the lanes"] = "Unlock the lanes"
L["Show the lanes' move boxes so you can drag them, as /kct unlock does. Both lanes unlock together."] =
    "Show the lanes' move boxes so you can drag them, as /kct unlock does. Both lanes unlock together."
L["Copy from %s"] = "Copy from %s"
L["Give this lane every setting of the other lane, except where it sits, its label text, its switch and its ignore list."] =
    "Give this lane every setting of the other lane, except where it sits, its label text, its switch and its ignore list."
L["Reset lane…"] = "Reset lane…"
L["Put every setting of this lane back to its default, its ignore list included. Asks first."] =
    "Put every setting of this lane back to its default, its ignore list included. Asks first."
L["Preview lane"] = "Preview lane"
L["Fill this lane with a few made-up casts, so you can see its look while you change it."] =
    "Fill this lane with a few made-up casts, so you can see its look while you change it."
L["The spells this lane never shows."] = "The spells this lane never shows."
L["Add a spell"] = "Add a spell"
L["Type a spell's ID or name, or shift-click its link, to stop this lane showing it."] =
    "Type a spell's ID or name, or shift-click its link, to stop this lane showing it."
L["This lane ignores no spells."] = "This lane ignores no spells."
L["Reset to starting spells"] = "Reset to starting spells"
L["Put this lane's list back to the spells it ignores out of the box."] =
    "Put this lane's list back to the spells it ignores out of the box."
L["Restore every setting of both lanes on this profile to its addon default, their ignore lists included."] =
    "Restore every setting of both lanes on this profile to its addon default, their ignore lists included."
L["The lane every tab below edits."] = "The lane every tab below edits."

-- The lanes' ignore lists (modules/LaneIgnore.lua) and the `ignore` verb
L["Usage: /kct ignore add|remove <spell> [player|pet], /kct ignore list [player|pet] or /kct ignore reset [player|pet]"] =
    "Usage: /kct ignore add|remove <spell> [player|pet], /kct ignore list [player|pet] or /kct ignore reset [player|pet]"
L["The %s ignores no spells."] = "The %s ignores no spells."
L["The %s ignores %s."] = "The %s ignores %s."
L["No spell named '%s'."] = "No spell named '%s'."
L["The %s now ignores %s."] = "The %s now ignores %s."
L["The %s already ignores %s."] = "The %s already ignores %s."
L["The %s no longer ignores %s."] = "The %s no longer ignores %s."
L["The %s does not ignore %s."] = "The %s does not ignore %s."
L["The %s ignores its starting spells again."] = "The %s ignores its starting spells again."

-- The meter reader (modules/Meter.lua)
L["Blizzard's damage meter is not available on this client."] =
    "Blizzard's damage meter is not available on this client."

-- A fight's identity (modules/Identity.lua)
L["Unknown target"] = "Unknown target"

-- What a fight used (modules/Usage.lua): the food buff's name, read off the player's auras
L["Well Fed"] = "Well Fed"

-- The stats a fight was fought with (modules/Stats.lua): the gear view's groups and rows
L["Primary"] = "Primary"
L["Secondary"] = "Secondary"
L["Tertiary"] = "Tertiary"
L["Primary stat"] = "Primary stat"
L["Strength"] = "Strength"
L["Agility"] = "Agility"
L["Intellect"] = "Intellect"
L["Stamina"] = "Stamina"
L["Armor"] = "Armor"
L["Critical Strike"] = "Critical Strike"
L["Haste"] = "Haste"
L["Mastery"] = "Mastery"
L["Versatility"] = "Versatility"
L["Leech"] = "Leech"
L["Avoidance"] = "Avoidance"
L["Speed"] = "Speed"

-- `/kct probe` (modules/Probe.lua)
L["The probe report is in the debug console (%d lines). It also watches your next fight: fight for 20 seconds or more, then type %s again."] =
    "The probe report is in the debug console (%d lines). It also watches your next fight: fight for 20 seconds or more, then type %s again."
L["The probe report is in the debug console (%d lines)."] = "The probe report is in the debug console (%d lines)."
L["The probe watches your next fight. Fight for 20 seconds or more, then type %s."] =
    "The probe watches your next fight. Fight for 20 seconds or more, then type %s."
L["The probe stopped watching."] = "The probe stopped watching."
L["The probe sampled your fight. Type %s to see the report."] = "The probe sampled your fight. Type %s to see the report."
L["Usage: /kct probe, /kct probe start or /kct probe stop"] = "Usage: /kct probe, /kct probe start or /kct probe stop"

-- `/kct purge` (modules/Retention.lua)
L["No stored fight was old enough to remove."] = "No stored fight was old enough to remove."
L["Removed 1 stored fight."] = "Removed 1 stored fight."
L["Removed %d stored fights."] = "Removed %d stored fights."

-- The DPS HUD (modules/Hud.lua, modules/Hud_States.lua, modules/Format.lua)
L["Combat Trail"] = "Combat Trail"
L["Lock or unlock the HUD"] = "Lock or unlock the HUD"
L["Settings"] = "Settings"
L["Results"] = "Results"
L["Damage"] = "Damage"
L["DPS"] = "DPS"
L["DPS \194\183 Live"] = "DPS \194\183 Live"
L["live \194\183 4 Hz"] = "live \194\183 4 Hz"
L["Pinned open"] = "Pinned open"
L["Fades %d s after the fight"] = "Fades %d s after the fight"
L["%+.1f%%"] = "%+.1f%%"
L["New best"] = "New best"
L["New best %s"] = "New best %s"
L["Saved"] = "Saved"
L["Not saved"] = "Not saved"
L["Not saved: shorter than %d s"] = "Not saved: shorter than %d s"
L["Not saved: filtered out"] = "Not saved: filtered out"
L["Not saved: the meter lost this fight"] = "Not saved: the meter lost this fight"
L["Not saved: no readable character"] = "Not saved: no readable character"
L["Your best DPS on this boss or target, for this character and spec."] =
    "Your best DPS on this boss or target, for this character and spec."
L["Stored in your fight history."] = "Stored in your fight history."
L["Every fight is tracked live; only the ones that pass History > Recording filters are stored."] =
    "Every fight is tracked live; only the ones that pass History > Recording filters are stored."
L["Usage: /kct hud show, hide, toggle, pin or unpin"] = "Usage: /kct hud show, hide, toggle, pin or unpin"
