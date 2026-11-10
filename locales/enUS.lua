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
L["The lanes are off. Press the key again to bring them back."] =
    "The lanes are off. Press the key again to bring them back."
L["The lanes are on."] = "The lanes are on."

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
L["Restore every Lanes setting on this profile to its addon default."] =
    "Restore every Lanes setting on this profile to its addon default."
L["Restore every DPS HUD setting on this profile to its addon default."] =
    "Restore every DPS HUD setting on this profile to its addon default."

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
L["Lane length (px)"] = "Lane length (px)"
L["How long the lane is, in pixels, from the now edge to the far end."] =
    "How long the lane is, in pixels, from the now edge to the far end."
L["Seconds shown"] = "Seconds shown"
L["How many seconds a cast takes to cross the lane."] = "How many seconds a cast takes to cross the lane."
L["Icon size (px)"] = "Icon size (px)"
L["The size of each cast's icon, in pixels. The lane is this tall, or this wide when it runs up or down."] =
    "The size of each cast's icon, in pixels. The lane is this tall, or this wide when it runs up or down."
L["Icon spacing (px)"] = "Icon spacing (px)"
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
L["Gap (px)"] = "Gap (px)"
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
L["Two lanes at the same level that overlap mix their icons. Give one a higher level to draw it whole over the other."] =
    "Two lanes at the same level that overlap mix their icons. Give one a higher level to draw it whole over the other."
L["Flat"] = "Flat"
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
L["Padding (px)"] = "Padding (px)"
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
L["Tick width (px)"] = "Tick width (px)"
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

-- The DPS HUD page (settings/Hud.lua): its tabs, rows and the skin companions' words
L["Behavior"] = "Behavior"
L["Layout"] = "Layout"
L["Clock and figures"] = "Clock and figures"
L["Damage chart"] = "Damage chart"
L["Spell rows"] = "Spell rows"
L["Window"] = "Window"
L["On each fight's first hit"] = "On each fight's first hit"
L["Only when you open it"] = "Only when you open it"
L["Your best on this boss or target"] = "Your best on this boss or target"
L["Your last fight there"] = "Your last fight there"
L["Nothing"] = "Nothing"
L["Use the skin's color"] = "Use the skin's color"
L["Draw this text in the skin's HUD text color. The Font color swatch is not read while this is on, and Use class color comes first."] =
    "Draw this text in the skin's HUD text color. The Font color swatch is not read while this is on, and Use class color comes first."
L["Use the skin's shadow"] = "Use the skin's shadow"
-- The Lanes page's skin companions (settings/Lanes.lua)
L["Draw this in the skin's own color. The swatch is not read while this is on, and Use class color comes first."] =
    "Draw this in the skin's own color. The swatch is not read while this is on, and Use class color comes first."
L["Draw the label in the skin's HUD label color. The Font color swatch is not read while this is on, and Use class color comes first."] =
    "Draw the label in the skin's HUD label color. The Font color swatch is not read while this is on, and Use class color comes first."
L["Draw the label with the skin's shadow. Font shadow is not read while this is on."] =
    "Draw the label with the skin's shadow. Font shadow is not read while this is on."
L["Draw this text with the skin's shadow. Font shadow is not read while this is on."] =
    "Draw this text with the skin's shadow. Font shadow is not read while this is on."
L["When it shows"] = "When it shows"
L["Show the HUD"] = "Show the HUD"
L["On each fight's first hit: it opens when your damage starts and fades after the fight. Always: it stays up. Only when you open it: from /kct hud, the launcher or its key binding."] =
    "On each fight's first hit: it opens when your damage starts and fades after the fight. Always: it stays up. Only when you open it: from /kct hud, the launcher or its key binding."
L["Only in instances"] = "Only in instances"
L["Open the HUD on a fight's first hit only inside a dungeon, raid or other instance."] =
    "Open the HUD on a fight's first hit only inside a dungeon, raid or other instance."
L["Fade after the fight (seconds, 0 = never)"] = "Fade after the fight (seconds, 0 = never)"
L["How long the fight-over card stays after the fight ends before the HUD closes. 0 keeps it up until you close it."] =
    "How long the fight-over card stays after the fight ends before the HUD closes. 0 keeps it up until you close it."
L["Stay open while the mouse is over it"] = "Stay open while the mouse is over it"
L["Hold the HUD open while the pointer is over it, and fade it a moment after the pointer leaves."] =
    "Hold the HUD open while the pointer is over it, and fade it a moment after the pointer leaves."
L["Pace"] = "Pace"
L["Pace compares against"] = "Pace compares against"
L["The stored fight the pace bar measures you against: your best on the same boss or target, the last fight you had there, or none, which hides the pace bar."] =
    "The stored fight the pace bar measures you against: your best on the same boss or target, the last fight you had there, or none, which hides the pace bar."
L["Pace bar range"] = "Pace bar range"
L["How far either side of the pace the bar reaches: 1.5 runs from half the pace's damage so far to half again. The tick in the middle is the pace."] =
    "How far either side of the pace the bar reaches: 1.5 runs from half the pace's damage so far to half again. The tick in the middle is the pace."
L["Fight-over card"] = "Fight-over card"
L["Show fight-over card"] = "Show fight-over card"
L["Show the final damage, DPS and spell percentages once the fight ends. Off, a HUD that opened by itself closes when the fight ends."] =
    "Show the final damage, DPS and spell percentages once the fight ends. Off, a HUD that opened by itself closes when the fight ends."
L["Show why a fight was not saved"] = "Show why a fight was not saved"
L["Say on the card why a fight was not stored, such as too short or filtered out. Needs Show fight-over card."] =
    "Say on the card why a fight was not stored, such as too short or filtered out. Needs Show fight-over card."
L["Parts"] = "Parts"
L["Show clock"] = "Show clock"
L["Show the fight's clock, counting up from the first hit."] =
    "Show the fight's clock, counting up from the first hit."
L["Show target line"] = "Show target line"
L["Show the encounter or target, the instance and the difficulty under the clock."] =
    "Show the encounter or target, the instance and the difficulty under the clock."
L["Show damage and DPS boxes"] = "Show damage and DPS boxes"
L["Show the Damage and DPS boxes, with your pet's figure beside them."] =
    "Show the Damage and DPS boxes, with your pet's figure beside them."
L["Show pace bar"] = "Show pace bar"
L["Show the bar that measures your damage so far against the pace. Hidden while there is nothing to pace against."] =
    "Show the bar that measures your damage so far against the pace. Hidden while there is nothing to pace against."
L["Show damage chart"] = "Show damage chart"
L["Show your damage over the fight as columns, with the pace as a line and your long cooldowns as icons."] =
    "Show your damage over the fight as columns, with the pace as a line and your long cooldowns as icons."
L["Show spell rows"] = "Show spell rows"
L["Show your spells and your pet's, one row each, in the order the damage meter gives them."] =
    "Show your spells and your pet's, one row each, in the order the damage meter gives them."
L["HUD width (px)"] = "HUD width (px)"
L["How wide the HUD is, in pixels. Its height follows the parts it shows."] =
    "How wide the HUD is, in pixels. Its height follows the parts it shows."
L["HUD scale"] = "HUD scale"
L["The size of the whole HUD, its text included."] = "The size of the whole HUD, its text included."
L["Clock font"] = "Clock font"
L["The face the clock is drawn in. A face with even-width digits keeps the clock from jumping as it counts."] =
    "The face the clock is drawn in. A face with even-width digits keeps the clock from jumping as it counts."
L["Figures font"] = "Figures font"
L["The face the Damage and DPS figures are drawn in."] = "The face the Damage and DPS figures are drawn in."
L["Final DPS color"] = "Final DPS color"
L["The color of the DPS figure on the fight-over card."] =
    "The color of the DPS figure on the fight-over card."
L["Box background"] = "Box background"
L["The fill behind the Damage and DPS boxes."] = "The fill behind the Damage and DPS boxes."
L["Use the skin's background"] = "Use the skin's background"
L["Fill the boxes in the skin's own color. The background swatch is not read while this is on."] =
    "Fill the boxes in the skin's own color. The background swatch is not read while this is on."
L["Box border"] = "Box border"
L["Border color"] = "Border color"
L["The edge around the Damage and DPS boxes."] = "The edge around the Damage and DPS boxes."
L["Draw the boxes' edge in the skin's own color. The border swatch is not read while this is on."] =
    "Draw the boxes' edge in the skin's own color. The border swatch is not read while this is on."
L["Chart height (px)"] = "Chart height (px)"
L["The height of the chart's plot, in pixels."] = "The height of the chart's plot, in pixels."
L["Maximum columns"] = "Maximum columns"
L["The most columns the chart draws. A long fight folds more seconds into each column."] =
    "The most columns the chart draws. A long fight folds more seconds into each column."
L["Columns"] = "Columns"
L["Burst windows"] = "Burst windows"
L["Burst column color"] = "Burst column color"
L["The color of the columns in the seconds after you use a long cooldown."] =
    "The color of the columns in the seconds after you use a long cooldown."
L["Lines"] = "Lines"
L["Pace line color"] = "Pace line color"
L["The color of the line that marks the pace."] = "The color of the line that marks the pace."
L["Show zero line"] = "Show zero line"
L["Draw a thin line along the chart's bottom edge."] = "Draw a thin line along the chart's bottom edge."
L["Cooldowns"] = "Cooldowns"
L["Show cooldown icons"] = "Show cooldown icons"
L["Mark each cast of a spell with a long cooldown with its icon along the top of the chart."] =
    "Mark each cast of a spell with a long cooldown with its icon along the top of the chart."
L["Shortest cooldown (seconds)"] = "Shortest cooldown (seconds)"
L["The shortest base cooldown, in seconds, that earns an icon. Needs Show cooldown icons."] =
    "The shortest base cooldown, in seconds, that earns an icon. Needs Show cooldown icons."
L["Spell rows shown (0 = all)"] = "Spell rows shown (0 = all)"
L["How many spells the HUD lists. 0 lists every one: as many as fit show, and the mouse wheel scrolls through the rest."] =
    "How many spells the HUD lists. 0 lists every one: as many as fit show, and the mouse wheel scrolls through the rest."
L["Row height (px)"] = "Row height (px)"
L["The height of each spell row, in pixels."] = "The height of each spell row, in pixels."
L["Show spell icons"] = "Show spell icons"
L["Draw each spell's icon at the start of its row."] = "Draw each spell's icon at the start of its row."
L["Show pet paw"] = "Show pet paw"
L["Mark your pet's spells with a paw."] = "Mark your pet's spells with a paw."
L["Player bars"] = "Player bars"
L["The texture your spell rows' bars and the pace bar's fills are drawn with."] =
    "The texture your spell rows' bars and the pace bar's fills are drawn with."
L["Pet bars"] = "Pet bars"
L["Pet bar color"] = "Pet bar color"
L["The color of your pet's spell rows and of its part of the pace bar."] =
    "The color of your pet's spell rows and of its part of the pace bar."
L["Row font"] = "Row font"
L["The face the spell names and amounts are drawn in."] = "The face the spell names and amounts are drawn in."
L["Title bar and footer"] = "Title bar and footer"
L["Show title bar"] = "Show title bar"
L["Show the bar along the top with the HUD's buttons, where you drag it from."] =
    "Show the bar along the top with the HUD's buttons, where you drag it from."
L["Show title"] = "Show title"
L["Write Combat Trail in the title bar. Needs Show title bar."] =
    "Write Combat Trail in the title bar. Needs Show title bar."
L["Show footer"] = "Show footer"
L["Show the line along the bottom that says what the HUD is doing."] =
    "Show the line along the bottom that says what the HUD is doing."
L["The fill behind the whole HUD."] = "The fill behind the whole HUD."
L["Fill the HUD in the skin's own color. The background swatch is not read while this is on."] =
    "Fill the HUD in the skin's own color. The background swatch is not read while this is on."
L["The edge around the whole HUD."] = "The edge around the whole HUD."
L["Draw the HUD's edge in the skin's own color. The border swatch is not read while this is on."] =
    "Draw the HUD's edge in the skin's own color. The border swatch is not read while this is on."
L["The point of the HUD that is placed."] = "The point of the HUD that is placed."
L["The point of the screen it is placed at."] = "The point of the screen it is placed at."
L["Horizontal offset of the HUD from its point, in pixels. Dragging the title bar sets it too."] =
    "Horizontal offset of the HUD from its point, in pixels. Dragging the title bar sets it too."
L["Vertical offset of the HUD from its point, in pixels. Dragging the title bar sets it too."] =
    "Vertical offset of the HUD from its point, in pixels. Dragging the title bar sets it too."
L["HUD opacity"] = "HUD opacity"
L["How opaque the whole HUD is."] = "How opaque the whole HUD is."

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

-- The DPS HUD's pace bar, damage chart, spell rows and tooltips (modules/Hud_Chart.lua,
-- modules/Hud_Breakdown.lua, modules/Hud_States.lua, modules/Hud_Tips.lua)
L["% of total"] = "% of total"
L["%d cooldowns"] = "%d cooldowns"
L["+%d"] = "+%d"
L["Cast at %s"] = "Cast at %s"
L["Damage profile"] = "Damage profile"
L["Fight clock"] = "Fight clock"
L["How long this fight has run, from your first hit."] = "How long this fight has run, from your first hit."
L["How your damage built up over the fight, one column per slice of time. The line is your best's average pace, and icons mark your long cooldowns."] =
    "How your damage built up over the fight, one column per slice of time. The line is your best's average pace, and icons mark your long cooldowns."
L["Pace bar"] = "Pace bar"
L["Spell breakdown"] = "Spell breakdown"
L["Target"] = "Target"
L["The boss or target this fight is against, with the instance and difficulty its bests group by."] =
    "The boss or target this fight is against, with the instance and difficulty its bests group by."
L["This fight's damage per second, yours and your pet's."] =
    "This fight's damage per second, yours and your pet's."
L["This fight's final damage against the best it was paced against, at the same length. The tick in the middle is level with that best."] =
    "This fight's final damage against the best it was paced against, at the same length. The tick in the middle is level with that best."
L["This fight's spells, highest damage first, with each one's share."] =
    "This fight's spells, highest damage first, with each one's share."
L["This fight's total damage, yours and your pet's."] = "This fight's total damage, yours and your pet's."
L["Unknown spell"] = "Unknown spell"
L["Your damage against your best's at this point in the fight. The tick in the middle is on pace; your pet's damage carries on from the end of yours."] =
    "Your damage against your best's at this point in the fight. The tick in the middle is on pace; your pet's damage carries on from the end of yours."
L["Your damage per second so far this fight, as the damage meter reports it."] =
    "Your damage per second so far this fight, as the damage meter reports it."
L["Your damage so far this fight, as the damage meter reports it. Your pet's shows beside it."] =
    "Your damage so far this fight, as the damage meter reports it. Your pet's shows beside it."
L["Your spells, then your pet's, in the damage meter's order. Shares appear once the fight is over."] =
    "Your spells, then your pet's, in the damage meter's order. Shares appear once the fight is over."
L["first fight on this board"] = "first fight on this board"
L["live order"] = "live order"
L["vs best pace"] = "vs best pace"

-- The Results window (modules/Results.lua, Results_Fights.lua, Results_Table.lua, Results_Tips.lua)
L["Right-click a fight for options"] = "Right-click a fight for options"
L["Combat Trail \226\128\148 Results"] = "Combat Trail \226\128\148 Results"
L["Fights are kept for %d days"] = "Fights are kept for %d days"
L["Fights are kept until you delete them"] = "Fights are kept until you delete them"
L["Sim: a made-up fight, not your data. /kct sim ends it."] =
    "Sim: a made-up fight, not your data. /kct sim ends it."
L["Test mode: sample fights. Nothing here is saved."] = "Test mode: sample fights. Nothing here is saved."
L["Combat Trail \226\128\148 Results \194\183 Test"] = "Combat Trail \226\128\148 Results \194\183 Test"
L["Usage: /kct results, or /kct results show, hide or toggle"] =
    "Usage: /kct results, or /kct results show, hide or toggle"
L["Edit Note"] = "Edit Note"
L["Add Note"] = "Add Note"
L["Share"] = "Share"
L["Compare With This Fight"] = "Compare With This Fight"
L["Delete"] = "Delete"
L["Delete this fight? This cannot be undone, and a personal best it holds goes with it."] =
    "Delete this fight? This cannot be undone, and a personal best it holds goes with it."
L["Cancel"] = "Cancel"
L["A note for this fight (200 characters at most):"] = "A note for this fight (200 characters at most):"
L["Save"] = "Save"
L["Mythic+ %d"] = "Mythic+ %d"
L["Tier %d"] = "Tier %d"
L["Bracket %s"] = "Bracket %s"
L["No difficulty"] = "No difficulty"
L["Today"] = "Today"
L["Last 7 days"] = "Last 7 days"
L["Last 30 days"] = "Last 30 days"
L["All time"] = "All time"
L["All characters"] = "All characters"
L["Current character"] = "Current character"
L["All specs"] = "All specs"
L["Current spec"] = "Current spec"
L["All content"] = "All content"
L["All encounters and targets"] = "All encounters and targets"
L["All difficulties"] = "All difficulties"
L["Best"] = "Best"
L["%.1f%%"] = "%.1f%%"
L["No fight in this group to compare with."] = "No fight in this group to compare with."
L["No fight in view to compare with."] = "No fight in view to compare with."
L["The best in this group: %s DPS."] = "The best in this group: %s DPS."
L["The best in view: %s DPS."] = "The best in view: %s DPS."
L["%+.1f%% vs the best"] = "%+.1f%% vs the best"
L["The best fight in its group."] = "The best fight in its group."
L["The best fight in view."] = "The best fight in view."
L["Leads the next one by %s."] = "Leads the next one by %s."
L["Your best on this board."] = "Your best on this board."
L["%s +%d"] = "%s +%d"
L["Date"] = "Date"
L["Class"] = "Class"
L["Character"] = "Character"
L["iLvl"] = "iLvl"
L["Encounter or target"] = "Encounter or target"
L["Content"] = "Content"
L["Length"] = "Length"
L["Delta"] = "Delta"
L["Bosses only"] = "Bosses only"
L["Save view"] = "Save view"
L["Save these filters, the grouping and the sort as this profile's view of your fights."] =
    "Save these filters, the grouping and the sort as this profile's view of your fights."
L["Reset view"] = "Reset view"
L["Go back to the view the addon ships with: your character, the last 7 days, grouped by encounter and difficulty, newest first."] =
    "Go back to the view the addon ships with: your character, the last 7 days, grouped by encounter and difficulty, newest first."
L["No fights match these filters."] = "No fights match these filters."
L["Not saved: the Results window is showing sample fights."] =
    "Not saved: the Results window is showing sample fights."
L["The Results view is saved."] = "The Results view is saved."
L["The Results view is back to the one the addon ships with."] =
    "The Results view is back to the one the addon ships with."
L["1 fight"] = "1 fight"
L["%d fights"] = "%d fights"
L["Unknown class"] = "Unknown class"
L["Delve %d"] = "Delve %d"
L["build %s"] = "build %s"
L["Class color"] = "Class color"
L["Pet: %s"] = "Pet: %s"
L["Item level %s"] = "Item level %s"
L["Equipped, read when the fight started."] = "Equipped, read when the fight started."
L["Primary target: %s"] = "Primary target: %s"
L["1 other target took damage"] = "1 other target took damage"
L["%d other targets took damage"] = "%d other targets took damage"
L["A boss fight"] = "A boss fight"
L["No readable target: this fight never counts as a best."] =
    "No readable target: this fight never counts as a best."
L["Length %s"] = "Length %s"
L["The meter's session, from the first hit to the end of combat."] =
    "The meter's session, from the first hit to the end of combat."
L["%s damage"] = "%s damage"
L["You %s, your pet %s"] = "You %s, your pet %s"
L["Read from Blizzard's meter after combat. The bar runs from the smallest fight in its group to the largest."] =
    "Read from Blizzard's meter after combat. The bar runs from the smallest fight in its group to the largest."
L["%s DPS"] = "%s DPS"
L["Damage over the fight's length."] = "Damage over the fight's length."
L["Blizzard's meter said %s."] = "Blizzard's meter said %s."
L["Click to fold or unfold the group."] = "Click to fold or unfold the group."
L["Raid"] = "Raid"
L["Dungeon"] = "Dungeon"
L["Mythic+"] = "Mythic+"
L["Delve"] = "Delve"
L["Battleground"] = "Battleground"
L["Arena"] = "Arena"
L["Dummy"] = "Dummy"
L["Scenario"] = "Scenario"
L["Other"] = "Other"
L["Group: Encounter + difficulty"] = "Group: Encounter + difficulty"
L["Group: Character"] = "Group: Character"
L["Group: Spec"] = "Group: Spec"
L["Group: Content"] = "Group: Content"
L["Group: None"] = "Group: None"
L["When the fight started. Click to sort."] = "When the fight started. Click to sort."
L["The character's class and spec."] = "The character's class and spec."
L["Who fought. Hover a name for the realm and the pet."] =
    "Who fought. Hover a name for the realm and the pet."
L["Equipped item level when the fight started."] = "Equipped item level when the fight started."
L["The encounter, or the enemy that took the most damage."] =
    "The encounter, or the enemy that took the most damage."
L["Where the fight was: a raid, a dungeon, the open world, a training dummy and so on."] =
    "Where the fight was: a raid, a dungeon, the open world, a training dummy and so on."
L["How long the fight lasted."] = "How long the fight lasted."
L["Your damage and your pet's, read from Blizzard's meter after combat. The bar runs from the smallest fight in its group to the largest (with no grouping, the whole list)."] =
    "Your damage and your pet's, read from Blizzard's meter after combat. The bar runs from the smallest fight in its group to the largest (with no grouping, the whole list)."
L["Damage over the fight's length. The bar runs from the smallest fight in its group to the largest (with no grouping, the whole list)."] =
    "Damage over the fight's length. The bar runs from the smallest fight in its group to the largest (with no grouping, the whole list)."
L["How far this fight's DPS is from the best fight in its group (with no grouping, the whole list). The best shows a trophy."] =
    "How far this fight's DPS is from the best fight in its group (with no grouping, the whole list). The best shows a trophy."

-- The fight detail (modules/Results_Detail.lua, Results_Loadout.lua, Results_Usage.lua, Results.lua's
-- fold arrow) and Share (modules/Share.lua)
L["M+ %d"] = "M+ %d"
L["T%d"] = "T%d"
L["top: %s"] = "top: %s"
L["Talents"] = "Talents"
L["You can share a fight once you are out of combat."] = "You can share a fight once you are out of combat."
L["Whisper this fight to:"] = "Whisper this fight to:"
L["Send"] = "Send"
L["Share to"] = "Share to"
L["Not recorded"] = "Not recorded"
L["Unnamed loadout"] = "Unnamed loadout"
L["Talents for %s: %s. Click the link to see the tree."] =
    "Talents for %s: %s. Click the link to see the tree."
L["this fight"] = "this fight"
L["Talent loadout"] = "Talent loadout"
L["Item %d"] = "Item %d"
L["Gear and Talents"] = "Gear and Talents"
L["Gear view"] = "Gear view"
L["Gear not recorded"] = "Gear not recorded"
L["View"] = "View"
L["Copy"] = "Copy"
L["The fight's gear and stats, laid out as the character panel does."] =
    "The fight's gear and stats, laid out as the character panel does."
L["Posts the loadout's link to your chat and opens the talent tree, read-only."] =
    "Posts the loadout's link to your chat and opens the talent tree, read-only."
L["The loadout's import string, to paste into the talent frame."] =
    "The loadout's import string, to paste into the talent frame."
L["ilvl %s"] = "ilvl %s"
L["Talents: %s"] = "Talents: %s"
L["at %s"] = "at %s"
L["x%d %s"] = "x%d %s"
L["active at the start"] = "active at the start"
L["x%d, time unknown"] = "x%d, time unknown"
L["time unknown"] = "time unknown"
L["Usage"] = "Usage"
L["Edit"] = "Edit"
L["Tick what the fight really used: an item the detection missed, or one it got wrong."] =
    "Tick what the fight really used: an item the detection missed, or one it got wrong."
L["Nothing used"] = "Nothing used"
L["pet %s"] = "pet %s"
L["Leads by"] = "Leads by"
L["Personal best"] = "Personal best"
L["Meter DPS"] = "Meter DPS"
L["This fight holds your best DPS on its board."] = "This fight holds your best DPS on its board."
L["Damage chart is only kept for fights recorded this session."] =
    "Damage chart is only kept for fights recorded this session."
L["Note"] = "Note"
L["Back"] = "Back"
L["Back to the list of fights."] = "Back to the list of fights."
L["Select a fight to see its detail."] = "Select a fight to see its detail."
L["Pet %s"] = "Pet %s"
L["this session only"] = "this session only"
L["What Blizzard's damage meter said the fight's DPS was."] =
    "What Blizzard's damage meter said the fight's DPS was."
L["The meter did not say."] = "The meter did not say."
L["Your damage over the fight, one column a stretch of time; long cooldowns sit along its top."] =
    "Your damage over the fight, one column a stretch of time; long cooldowns sit along its top."
L["The chart lives in memory only, so a fight recorded before your last reload or login has none."] =
    "The chart lives in memory only, so a fight recorded before your last reload or login has none."
L["1 spell, highest first, with its share of the fight's damage."] =
    "1 spell, highest first, with its share of the fight's damage."
L["%d spells, highest first, each with its share of the fight's damage."] =
    "%d spells, highest first, each with its share of the fight's damage."
L["Your pet's spells carry the paw."] = "Your pet's spells carry the paw."
L["Click a fight for its detail \194\183 right-click for options"] =
    "Click a fight for its detail \194\183 right-click for options"
L["Fold the detail away: the list alone (a click opens a fight in its place)"] =
    "Fold the detail away: the list alone (a click opens a fight in its place)"
L["Unfold the detail beside the list"] = "Unfold the detail beside the list"
L["Timeline"] = "Timeline"
L["Compare vs best"] = "Compare vs best"
L["Every cast of the fight along its length, beside the fight it is compared with."] =
    "Every cast of the fight along its length, beside the fight it is compared with."
L["A short note of your own on this fight."] = "A short note of your own on this fight."
L["One line about this fight in a chat channel you pick."] =
    "One line about this fight in a chat channel you pick."
L["Delete this fight. It asks first."] = "Delete this fight. It asks first."
L["Say"] = "Say"
L["Party"] = "Party"
L["Guild"] = "Guild"
L["Whisper\226\128\166"] = "Whisper\226\128\166"

-- The ability timeline (modules/Results_Timeline.lua, modules/Results_TimelineData.lua)
L["%s cooldown"] = "%s cooldown"
L["%s (pet)"] = "%s (pet)"
L["This fight"] = "This fight"
L["No fight to compare with"] = "No fight to compare with"
L["No fight to compare with: the blue lanes stay empty."] =
    "No fight to compare with: the blue lanes stay empty."
L["%s has no casts recorded: the blue lanes stay empty."] =
    "%s has no casts recorded: the blue lanes stay empty."
L["Too many casts here for %d rows: this icon overlaps others."] =
    "Too many casts here for %d rows: this icon overlaps others."
L["%s: 1 cast"] = "%s: 1 cast"
L["%s: %d casts"] = "%s: %d casts"
L["Cooldown %s"] = "Cooldown %s"
L["Mouse controls"] = "Mouse controls"
L["Mouse wheel: scroll up and down"] = "Mouse wheel: scroll up and down"
L["Shift+mouse wheel: scroll left and right (zoomed in)"] =
    "Shift+mouse wheel: scroll left and right (zoomed in)"
L["Ctrl+mouse wheel: zoom in and out"] = "Ctrl+mouse wheel: zoom in and out"
L["Ability timeline"] = "Ability timeline"
L["Pet abilities"] = "Pet abilities"
L["Right: casts in each lane"] = "Right: casts in each lane"
L["Scroll right, toward the end (or Shift+mouse wheel down)"] =
    "Scroll right, toward the end (or Shift+mouse wheel down)"
L["Scroll left, toward 0:00 (or Shift+mouse wheel up)"] = "Scroll left, toward 0:00 (or Shift+mouse wheel up)"
L["Reset zoom"] = "Reset zoom"
L["Zoom in (or Ctrl+mouse wheel up)"] = "Zoom in (or Ctrl+mouse wheel up)"
L["Zoom out (or Ctrl+mouse wheel down)"] = "Zoom out (or Ctrl+mouse wheel down)"
L["Casts"] = "Casts"
L["By ability"] = "By ability"
L["No casts recorded"] = "No casts recorded"
L["%sx"] = "%sx"
L["Select a fight in the Results window to see its timeline."] =
    "Select a fight in the Results window to see its timeline."
L["No casts recorded for this fight."] = "No casts recorded for this fight."
L["Only pet abilities were cast: turn on Pet abilities to see them."] =
    "Only pet abilities were cast: turn on Pet abilities to see them."
L["Picked"] = "Picked"
L["Runner-up"] = "Runner-up"

-- The compare (modules/Results_Compare.lua)
L["This fight beside the best on its board, the runner-up when it is the best, or the fight you picked with Compare With This Fight."] =
    "This fight beside the best on its board, the runner-up when it is the best, or the fight you picked with Compare With This Fight."
L["Compare vs runner-up"] = "Compare vs runner-up"
L["Compare vs pick"] = "Compare vs pick"
L["Compare"] = "Compare"
L["Clear pick"] = "Clear pick"
L["Compare with the best on this fight's board again."] = "Compare with the best on this fight's board again."
L["Spell"] = "Spell"
L["Change"] = "Change"
L["Neither fight recorded its spells."] = "Neither fight recorded its spells."
L["Gear changed"] = "Gear changed"
L["Different loadout"] = "Different loadout"
L["%s: not cast"] = "%s: not cast"
L["%s: %s (%s of its damage)"] = "%s: %s (%s of its damage)"
L["Change: %s"] = "Change: %s"
L["Cast by your pet."] = "Cast by your pet."
L["This fight: %s"] = "This fight: %s"
L["The other fight: %s"] = "The other fight: %s"
L["On another board"] = "On another board"
L["%s \194\187 this"] = "%s \194\187 this"
L["%s / This"] = "%s / This"
L["No gear changed."] = "No gear changed."
L["Gear not recorded for both fights."] = "Gear not recorded for both fights."
L["nothing worn"] = "nothing worn"
L["nothing worn before"] = "nothing worn before"
L["another item"] = "another item"
L["enchant differs"] = "enchant differs"
L["gem differs"] = "gem differs"

-- The gear view (modules/Results_Gear.lua)
L["Slot %d"] = "Slot %d"
L["Head"] = "Head"
L["Neck"] = "Neck"
L["Shoulder"] = "Shoulder"
L["Shirt"] = "Shirt"
L["Chest"] = "Chest"
L["Waist"] = "Waist"
L["Legs"] = "Legs"
L["Feet"] = "Feet"
L["Wrist"] = "Wrist"
L["Hands"] = "Hands"
L["Ring 1"] = "Ring 1"
L["Ring 2"] = "Ring 2"
L["Trinket 1"] = "Trinket 1"
L["Trinket 2"] = "Trinket 2"
L["Main hand"] = "Main hand"
L["Off hand"] = "Off hand"
L["Ranged"] = "Ranged"
L["Tabard"] = "Tabard"
L["Changed: %s wore %s."] = "Changed: %s wore %s."
L["Changed: %s had nothing here."] = "Changed: %s had nothing here."
L["The enchant differs from %s's."] = "The enchant differs from %s's."
L["The gems differ from %s's."] = "The gems differ from %s's."
L["Higher item level than %s's."] = "Higher item level than %s's."
L["Lower item level than %s's."] = "Lower item level than %s's."
L["Stats were not recorded for this fight."] = "Stats were not recorded for this fight."
L["Empty"] = "Empty"
L["Nothing was equipped in this slot."] = "Nothing was equipped in this slot."
L["vs %s"] = "vs %s"

-- The Usage edit and its "never show" list (modules/Results_Usage.lua, modules/Usage.lua, settings/History.lua)
L["Right-click: never show this item."] = "Right-click: never show this item."
L["Never show %s"] = "Never show %s"
L["Keep these ticks as what the fight used."] = "Keep these ticks as what the fight used."
L["Nothing to list: no on-use item or consumable was found at the start."] =
    "Nothing to list: no on-use item or consumable was found at the start."
L["Hidden items"] = "Hidden items"
L["Account-wide: shared by every profile. Item IDs, comma-separated, that the Results window's Usage never lists, on any fight. A fight that used one still records it, so taking it off the list brings it back."] =
    "Account-wide: shared by every profile. Item IDs, comma-separated, that the Results window's Usage never lists, on any fight. A fight that used one still records it, so taking it off the list brings it back."

-- The History page (settings/History.lua): its tabs, the Recording filters, Retention (the stored
-- count and size, Purge now… and its question), the Results window's rows and the Usage tab's list
L["Recording filters"] = "Recording filters"
L["Retention"] = "Retention"
L["Results window"] = "Results window"
L["Mythic+ dungeons"] = "Mythic+ dungeons"
L["Training dummies"] = "Training dummies"
L["Scenarios"] = "Scenarios"
L["Which fights"] = "Which fights"
L["Minimum fight length (seconds)"] = "Minimum fight length (seconds)"
L["A fight shorter than this is shown on the DPS HUD but not stored."] =
    "A fight shorter than this is shown on the DPS HUD but not stored."
L["Store only boss encounters. Trash, the open world and training dummies are still shown on the DPS HUD."] =
    "Store only boss encounters. Trash, the open world and training dummies are still shown on the DPS HUD."
L["Content to store"] = "Content to store"
L["Store the fights you have here. Off, they are still shown on the DPS HUD."] =
    "Store the fights you have here. Off, they are still shown on the DPS HUD."
L["Keep history for (days, 0 = forever)"] = "Keep history for (days, 0 = forever)"
L["Stored fights older than this many days are removed, at login and once a day while you play. 0 keeps every fight."] =
    "Stored fights older than this many days are removed, at login and once a day while you play. 0 keeps every fight."
L["Never purge a fight that holds a best"] = "Never purge a fight that holds a best"
L["Keep a fight however old it is while it is your best on its board: your top DPS for one character and spec on one encounter or target at one difficulty."] =
    "Keep a fight however old it is while it is your best on its board: your top DPS for one character and spec on one encounter or target at one difficulty."
L["Keep a fight however old it is while it is your best on its board: your top DPS for one character on one encounter or target at one difficulty."] =
    "Keep a fight however old it is while it is your best on its board: your top DPS for one character on one encounter or target at one difficulty."
L["Maximum stored fights (0 = no limit)"] = "Maximum stored fights (0 = no limit)"
L["The most fights kept. Past it the oldest go first, except a fight that holds a best while Never purge a fight that holds a best is on. 0 keeps any number."] =
    "The most fights kept. Past it the oldest go first, except a fight that holds a best while Never purge a fight that holds a best is on. 0 keeps any number."
L["Window scale"] = "Window scale"
L["The size of the Results window, its text included, and of the ability timeline, the gear view and the compare that open over it."] =
    "The size of the Results window, its text included, and of the ability timeline, the gear view and the compare that open over it."
L["The height of each row in the Results window's list of fights, in pixels."] =
    "The height of each row in the Results window's list of fights, in pixels."
L["Sharing"] = "Sharing"
L["Include talents link when sharing"] = "Include talents link when sharing"
L["Add the fight's talents to the shared line as a link others can click to see the talent tree. When the line and the link would be too long for one chat message, the link follows as a second one."] =
    "Add the fight's talents to the shared line as a link others can click to see the talent tree. When the line and the link would be too long for one chat message, the link follows as a second one."
L["%d bytes"] = "%d bytes"
L["%.1f KB"] = "%.1f KB"
L["%.1f MB"] = "%.1f MB"
L["Stored now: 1 fight, about %s of saved variables."] = "Stored now: 1 fight, about %s of saved variables."
L["Stored now: %d fights, about %s of saved variables."] =
    "Stored now: %d fights, about %s of saved variables."
L["Remove now the stored fights these settings no longer keep, as the purge at login does. Asks for confirmation."] =
    "Remove now the stored fights these settings no longer keep, as the purge at login does. Asks for confirmation."
L["Remove the stored fights that Keep history for and Maximum stored fights no longer keep? This cannot be undone."] =
    "Remove the stored fights that Keep history for and Maximum stored fights no longer keep? This cannot be undone."
L["Remove"] = "Remove"
L["Purge now\226\128\166"] = "Purge now\226\128\166"
L["Every fight is tracked live on the DPS HUD. A fight is stored only when it passes all of these."] =
    "Every fight is tracked live on the DPS HUD. A fight is stored only when it passes all of these."
L["Items the Results window's Usage never lists, on any fight. Right-click an item in a fight's Usage edit to add it here."] =
    "Items the Results window's Usage never lists, on any fight. Right-click an item in a fight's Usage edit to add it here."
L["Hide an item"] = "Hide an item"
L["An item ID, a shift-clicked item link, or the name of an item a fight listed."] =
    "An item ID, a shift-clicked item link, or the name of an item a fight listed."
L["No item is hidden."] = "No item is hidden."
L["Restore every History setting on this profile to its addon default, and empty the account-wide hidden items. Stored fights are not touched."] =
    "Restore every History setting on this profile to its addon default, and empty the account-wide hidden items. Stored fights are not touched."

-- Test mode and the sim (modules/Preview.lua, modules/Sim.lua, modules/MockFights.lua). The sample
-- history's difficulty and spec names stand in for the client's own; its boss, place and character
-- names are made up and stay as they are.
L["Test mode: sample data. Nothing here is saved."] = "Test mode: sample data. Nothing here is saved."
L["Combat Trail (sample)"] = "Combat Trail (sample)"
L["Test mode ended: you entered combat."] = "Test mode ended: you entered combat."
L["Test mode is not available in combat."] = "Test mode is not available in combat."
L["Test mode is not available while a fight is being read."] =
    "Test mode is not available while a fight is being read."
L["Combat Trail - SIM"] = "Combat Trail - SIM"
L["Combat starts"] = "Combat starts"
L["Fighting (%d s)"] = "Fighting (%d s)"
L["Combat ends"] = "Combat ends"
L["The fight is still on."] = "The fight is still on."
L["Waiting for the meter's final read."] = "Waiting for the meter's final read."
L["The fight-over card holds."] = "The fight-over card holds."
L["  %s: %s"] = "  %s: %s"
L["Usage: %s sim [%s]"] = "Usage: %s sim [%s]"
L["Behind the best"] = "Behind the best"
L["First fight"] = "First fight"
L["Too short"] = "Too short"
L["Lost fight"] = "Lost fight"
L["beats your best on the board"] = "beats your best on the board"
L["saved, behind your best"] = "saved, behind your best"
L["the first fight on its board: no best, no pace bar"] = "the first fight on its board: no best, no pace bar"
L["shorter than the recording filters' minimum: not saved"] =
    "shorter than the recording filters' minimum: not saved"
L["the meter loses the fight: not saved"] = "the meter loses the fight: not saved"
L["Normal"] = "Normal"
L["Heroic"] = "Heroic"
L["Mythic"] = "Mythic"
L["Mythic Keystone"] = "Mythic Keystone"
L["40 Player"] = "40 Player"
L["Beast Mastery"] = "Beast Mastery"
L["Sample note: every cooldown in the opener"] = "Sample note: every cooldown in the opener"
L["Sample note: tier 8 with the bountiful key"] = "Sample note: tier 8 with the bountiful key"
L["Sample note: a clean dummy pull"] = "Sample note: a clean dummy pull"
