# Ka0s Combat Trail

![WoW](https://img.shields.io/badge/WoW-Midnight_12.1.5_and_Forever_1.60.1-purple)
![License](https://img.shields.io/badge/License-MIT-orange)
![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)
![Tests](https://img.shields.io/badge/Tests-764%2F764_passing-green)

Supports Retail and WoW Forever. Combat Trail shows what you and your pet just cast as a row of icons sliding along two lanes, with tick marks for the global cooldown, so you can see your rotation as you play it. Every time you fight, a small DPS window climbs with your damage, draws it as a chart and sets it against your best fight on the same boss or target. When the fight is over it is saved, with its spells, casts, gear, talents and the consumables you used, so you can look back at a pull and see what changed.

All the numbers come from Blizzard's built-in damage meter, so you don't need another meter running. Everything can be set up on the addon's page under Settings → AddOns, or from chat with `/ct` (or `/combattrail`).

## Usage

The two lanes are there as soon as you log in: the Player lane, and the Pet lane docked just under it. Each cast slides in at one end and drifts across until it fades out, a red cross marks a cast that was interrupted or canceled, and big cooldowns glow. To move them, type `/ct unlock` (or open Edit Mode) and drag the lanes where you want them, then `/ct lock`. A lane can also sit on your player or pet unit frame, found by itself for ElvUI, Shadowed Unit Frames, Cell, PitBull, Unhalted Unit Frames and Blizzard's own frames, or on any frame you name. The Lanes settings page has a lane picker at the top and seven tabs under it for everything about the lane it names: size and direction, icons, background and border, ticks and the label, when it shows, and its ignored spells. `/ct lane pet off` turns a lane off from chat (`/ct lane player on` brings one back). Auto attacks are ignored out of the box. `/ct ignore add Hunter's Mark` hides another spell from the Player lane (add `pet` at the end for the Pet lane), and `/ct ignore remove`, `/ct ignore list` and `/ct ignore reset` manage the list.

The DPS HUD opens on your first hit and fades a few seconds after the fight. It shows the fight clock, who you are fighting, your damage and DPS (your pet's damage beside it), a pace bar against your best fight on that boss or target, a damage chart with icons for your big cooldowns, and your top spells, with pet spells marked by a paw. While you fight, the game hides the real numbers from addons, so the HUD can show them and fill bars with them but can't do math on them: no live percentages or "ahead by" figure. Once the fight is over, the card shows your final damage and DPS, each spell's share, a *New best* chip when you beat your best, and whether the fight was saved. `/ct hud show` and `/ct hud hide` open and close it, `/ct hud pin` keeps it from fading, and the DPS HUD settings page sets when it opens, what it paces against and how every part of it looks.

Fights are saved if they pass the recording filters on the History page: 30 seconds or longer by default, and only the kinds of content you keep ticked. Open the Results window with `/ct results`, or with the chart button on the HUD's title bar, which opens it on the fight the card is showing. It lists your fights with filters for character, spec, content, boss or target, difficulty and date, grouped by boss and difficulty unless you pick another grouping. Click a fight for its detail: damage, DPS, how far it sits from the best in its group, its spells, gear, talents and what it used. From there, *Timeline* shows when you cast each ability next to another fight, *Compare vs best* sets two fights side by side spell by spell, and *Gear view* lays out the gear and stats you pulled with. Right-click a fight to add a note, share it to chat, compare with it or delete it. Fights are kept for 7 days, except a fight that holds a best, and `/ct purge` clears old ones right away. The damage chart of a fight is only there until you reload or log out, because the game won't let addons save the in-combat numbers.

To set things up without a fight, turn on test mode with `/ct test`: the lanes loop sample casts, the HUD holds still on a made-up fight and the Results window opens on a made-up history, each with a strip saying the numbers are samples. `/ct sim` plays a whole made-up fight in real time instead, from the first hit to the card and then into the Results window, and `/ct sim newbest`, `behind`, `first`, `short` or `lost` picks the ending. Both stop when you enter combat, and nothing from either is saved. The addon's look follows a skin. `/ct skin` opens the skin picker, and while it is up the addon shows in test mode (the eye beside the list turns that off and on) so you can see each skin on the lanes and the HUD. Press *Apply* to keep the skin you picked, or close the picker to put everything back. The minimap button opens the settings on a left-click, and a right-click menu turns the addon on or off, locks it, toggles test mode or the sim and shows the HUD. You can bind keys to toggle the HUD, the Results window and the lanes in Options → Keybindings → Ka0s Combat Trail, or on General → Keybindings in this addon's settings.

From chat, `/ct enable` and `/ct disable` turn the addon on and off without reloading, `/ct config` opens its settings, `/ct list` shows every setting and `/ct get`, `/ct set` and `/ct reset` read, change or reset one by name (`/ct set history.days 14`). `/ct resetall` puts every setting back after asking first. `/ct version` prints the version, `/ct perf` measures what the addon costs you during a fight, and `/ct probe` writes a report of what your client tells addons about the meter, your casts and your pet, which helps when something looks off on one client. `/ct debug` and `/ct diagnostics` are for bug reports (see below).

Everything else is on the addon's page under Settings → AddOns, and `/ct help` (or `/combattrail help`) prints the full command list.

## How the trail and the HUD work

- Each lane hears the game's own cast events for you or your pet. A finished cast adds its icon at the "now" edge, and every icon slides away at a steady speed, so its distance from the edge is how long ago you cast it.
- A fight starts when you enter combat and follows Blizzard's damage meter: one meter session is one fight. Feign Death, Vanish and Shadowmeld don't split a fight if you are back in combat within a few seconds, and a boss whose meter split in two is joined back into one fight.
- During the fight the HUD copies the meter's numbers straight into its bars and text, so it always shows what the meter shows.
- A couple of seconds after you leave combat and your damage stops, the addon reads the fight's totals from the meter. Your DPS is your damage plus your pet's, divided by the length of the fight.
- The fight is saved if it passes the recording filters. Your best on a boss or target is the saved fight with the highest DPS for that character and spec, and it is worked out from the saved fights each time.

## FAQ

| Question | Answer |
|---|---|
| Why doesn't the HUD show percentages or how far ahead I am while I fight? | In combat the game hides the meter's numbers from addons. An addon can put them in a bar or print them, but it can't divide, add or compare them. The fight-over card has the percentages and the difference once combat ends. |
| Why can't I see the damage chart of an older fight? | The chart is built from the meter's in-combat numbers, which the game won't let addons save. A fight keeps its chart until you reload or log out. Everything else about it is saved. |
| Why wasn't my fight saved? | It was shorter than the minimum length, its content is unticked on the History page's recording filters, or the meter lost it (a reset or a logout before it was read). The fight-over card says which. |
| Why is my DPS a little different from Blizzard's meter? | Combat Trail adds your pet's damage to yours and divides by the fight's length as the meter reports it. The meter's own DPS figure is saved with the fight too, in the *Meter DPS* box. |
| Does it read the combat log? | No. Everything comes from the built-in damage meter and the game's cast events. |
| Does it work on WoW Forever? | Yes, from the same download. Delves, arenas and Mythic+ don't exist there, so their settings and filters don't appear. |
| Are my fights shared with anyone? | No. They stay in your own saved variables unless you share one to chat yourself. |

## Troubleshooting

| Symptom | Fix |
|---|---|
| The HUD stays empty in a fight | Make sure Blizzard's damage meter is on. The HUD reads its numbers from it. |
| A lane doesn't show | Check `/ct lane player on`, then the lane's Visibility tab: it may be set to show only in combat, or hidden while mounted or resting. |
| A lane anchored to a unit frame moved to the middle of the screen | That frame wasn't found, so the lane went back to a free position. Pick another frame on the Size and position tab, or name the frame yourself. |
| A spell I don't care about fills the lane | `/ct ignore add` with the spell's name, or add it on the lane's Ignored spells tab. |
| I can't find the HUD or the Results window | `/ct hud show` or `/ct results`. Reset position on General → Master controls puts every window back in its starting place. |
| The settings panel won't open | It doesn't open in combat. Try again once combat ends. |
| Something looks wrong and I want to report it | Follow [Reporting a bug](#reporting-a-bug) below. |

## Reporting a bug

- Type `/ct debug on` and reproduce the bug.
- Type `/ct diagnostics`.
- If the debug window isn't open, open it with `/ct debug`. Press **Copy**, copy the entire output, and include it with your bug report.

The report is added after the debug trace in the same window, so one copy carries both.

## Issues and feature requests

Please raise bugs and ideas on GitHub rather than in comments, so they are all in one place:
<https://github.com/tusharsaxena/CombatTrail/issues>

## Version History

| Version | Date | Highlights |
|---|---|---|
| 0.1.0 | Unreleased | - First release: Player and Pet cast lanes, a live DPS HUD on every fight, and a saved history of your fights with detail, timeline, compare and gear view, on Retail and WoW Forever |

## Credits

The window controls, the debug console, the skin picker and the Results window's buttons draw icons from [Open Iconic](https://github.com/iconic/open-iconic) by Waybury (MIT), and the status marks, the trophy and the pet's paw come from [Phosphor](https://github.com/phosphor-icons/core) by Phosphor Icons (MIT). Only the icons this addon draws are included, each set with its license file beside it.
