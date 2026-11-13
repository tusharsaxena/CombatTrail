# Smoke tests — Ka0s Combat Trail

The in-game checks no headless run can reach: real rendering, the real damage meter, real cast
events, taint, and the client behaviors the build could not measure ahead of time (spec §10). The
owner runs them; an agent never marks a row passed. Every check names its client: **Retail**,
**Forever** (WoW Forever) or **Both** (run it on each, and record each result).

## Sign-off

| Date | Build | Result |
|---|---|---|
| (not run yet) | 0.1.0, branch `feat/2026-11-10-combat-trail-v0.1.0` | |
| (not run yet) | 0.1.0, branch `feat/2026-11-11-race-mode` (Race mode, sections 9 and 10) | |
| (not run yet) | 0.1.0, branch `feat/2026-11-13-callout` (the center call-out: SM-CT-RM12, RM14, RM31, RM77 to RM88; the showcase and the samples' alerts: SM-CT-M6, M7; WoW Forever's live Pet figure: SM-CT-P8, SM-CT-H15) | |

## How to run it

- Set `/console scriptErrors 1` first, and keep `/ct debug on` for the whole pass. Most failures
  leave their evidence in the debug console (`/ct debug`).
- Run **The probe** first on each client: its answers decide what several later rows expect.
- Work down the page. Mark each row passed or failed, with the date, the client and its build
  (`/ct version`, and the build from the login screen).
- A failure report carries the row ID, what happened instead, and `/ct diagnostics` copied from the
  console right after the failure (the report follows the trace, so one **Copy** carries both).
- A class is named where a check needs one: a Hunter (pet, Feign Death), a Warlock (a second pet
  family), any caster with a channel and a cast-time spell, and an Evoker for empowered casts
  (Retail).

## The probe

`/ct probe` writes a plain-text report to the debug console; **Copy** lifts it out. Run these steps
on **each** client, on a Hunter with a pet out, then again on a Warlock with a demon out:

- Out of combat, type `/ct probe`. Copy the report. It names the client, version, build and
  interface; says "combat log: protected, not used"; lists `C_DamageMeter`'s functions against the
  eight expected, `IsDamageMeterAvailable`, both enums and the session count; and reads the player's
  and the pet's sources in the Current session.
- Type `/ct probe start`, then pull a training dummy (or any target) and fight for at least ten
  seconds. The probe takes one sample 5 s into combat and one 2 s after it ends, then disarms itself.
- Type `/ct probe` again and copy the whole report. Check its lines: **pet is separate source** (yes
  or no), **pace pet-fill anchor** (whether the anchored SetPoint raised), the cast secrecy counts
  in and out of combat, and the meter's secrecy samples (with a pet out, each sample's *pet rows in
  player source* line: SM-CT-P8). On WoW Forever, also the talent-tree lines (SM-CT-P7).
- `/ct probe stop` disarms it early.

Hand the reports back for `midnight-quirks.md`. A "no" on the pet line, or a raise on the pet-fill
line, is a fix on the branch before the merge (spec §12's fallbacks).

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-P1 | Both | `/ct probe` out of combat on a Hunter with a pet | The report prints in the console; every one of the eight functions is present; "combat log: protected, not used" |
| SM-CT-P2 | Both | `/ct probe start`, then ten seconds of combat | One +5 s sample and one sample 2 s after combat, then the probe disarms |
| SM-CT-P3 | Both | `/ct probe` typed while already in combat | It schedules the +5 s sample; a combat takes one in-combat sample however often it is armed |
| SM-CT-P4 | Both | The "pet is separate source" verdict, Hunter and Warlock | "yes" on both classes, with the note that it cannot detect double counting. On WoW Forever the out-of-combat probe (2026-11-10) found the pet's source empty (midnight-quirks.md): record the in-combat verdict there |
| SM-CT-P5 | Both | The "pace pet-fill anchor" line | The SetPoint did not raise |
| SM-CT-P6 | Forever | The cast secrecy counts in combat | Recorded either way: whether cast spell IDs and castGUIDs are secret in combat on WoW Forever |
| SM-CT-P7 | Forever | The talent-tree lines of `/ct probe` (talent tabs, talent spec, talent config, trait tree and groups, talent tree pick), on a character with points spent | Recorded either way: which API answers, each group's fields (which one holds the icon), and a pick that names the tree with the most points. First run 2026-11-10 (build 70862, out of combat): the talent tabs absent, C_Traits' three groups answered, the pick read Beast Mastery (10/3/0) (midnight-quirks.md). Still owed: the same lines read right after a pull, while combat is fresh |
| SM-CT-P8 | Forever | `/ct probe start` with the pet out, ten seconds of combat with the pet attacking, then `/ct probe` | Each sample has a line "pet rows in player source: N row(s), A with a secret name, B named a creature (C with a secret amount); player total plain|secret; live Pet figure: split|dash|own source|none". Record the combat+5s line: "split" with no secret name, amount or total means the meter's values are plain in combat on WoW Forever and the HUD shows the live Pet figure (SM-CT-H15); "dash" means they are secret there. The afterCombat+2s line should read "split" |

## 1. Load and identity

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-L1 | Both | Log in with the addon enabled | No Lua error; the first-run skin picker shows once, in test mode |
| SM-CT-L2 | Both | `/ct version` and `/ct help` | The version line; the full command list |
| SM-CT-L3 | Both | Settings → AddOns → Ka0s Combat Trail | The landing page with the logo, then General, Lanes, DPS HUD, History, Race mode (Retail only) and Profiles |
| SM-CT-L4 | Both | `/ct disable`, then `/ct results` and `/ct enable` | Lanes and HUD hide; the feature verb answers the disabled line; enable brings everything back |
| SM-CT-L5 | Both | Hover and right-click the minimap button | Status tooltip; menu with Enabled, Locked, Test mode, Sim mode, Show window |
| SM-CT-L6 | Both | The three bindings (Toggle DPS HUD, Toggle Results window, Toggle lanes) pressed in game | Each toggles its target; the lanes key brings back exactly the lanes it turned off |
| SM-CT-L7 | Both | The bindings under Options → Keybindings → Ka0s Combat Trail and General → Keybindings | The same keys in both places |
| SM-CT-L8 | Both | The first login on v0.2 over a v0.1 SavedVariables with stored fights | No Lua error; Results is empty, `/ct diag` reads `schema stored=2 code=2 fightFormat=4`; the hidden items and the minimap button are kept |
| SM-CT-L9 | Both | Lanes → pick Pet lane → tick Link to Player lane; change the Player lane's icon size, border color and Visibility; then Copy from Player lane | The Pet lane takes each change at once and keeps its place and label; its tabs show only Size and position's place rows and the label text, with the note on General; Copy from unticks the link and the two drift apart from there |

## 2. Lanes

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-N1 | Both | Cast a rotation with a pet out | Player and Pet icons slide from the now edge; auto attacks never show |
| SM-CT-N2 | Both | Interrupt yourself mid-cast (move during a cast-time spell) | The icon shows with the red cross |
| SM-CT-N3 | Both | A channel: does it fire `UNIT_SPELLCAST_SUCCEEDED` per tick? | Recorded either way; the lane shows one icon per press |
| SM-CT-N4 | Retail | An Evoker's empowered cast | One icon per cast |
| SM-CT-N5 | Both | A cooldown of 29 s or more | The icon glows |
| SM-CT-N6 | Both | `/ct unlock`, drag both lanes, `/ct lock`, `/reload` | The places hold; the docked Pet lane follows the Player lane |
| SM-CT-N7 | Retail | Edit Mode open | The lanes show their edit overlay while the Locked row is off |
| SM-CT-N8 | Both | Anchor the Player lane to the unit frame with ElvUI, then Shadowed Unit Frames, then Blizzard's frames | The lane sits on the frame each time; strata and level follow the host |
| SM-CT-N9 | Both | The unit-frame names in `LaneAnchor.UNIT_FRAMES` (ElvUI, SUF, Cell, PitBull4, UnhaltedUnitFrames, Blizzard) | Each name exists on the client that ships the frame addon; a missing one falls back to free with one line |
| SM-CT-N10 | Both | Two lanes overlapping at the same Frame level | Their icons mix, as the Frame level tooltip says; a different level separates them |
| SM-CT-N11 | Both | A lane icon over another addon's window on MEDIUM strata | The icon never draws over it (the bounded icon band) |
| SM-CT-N12 | Both | The lane label and looks under Ka0s Default with the From skin companions on | Owner rules on: the gold label (stored default white), the black icon border, the skin's glow and background |
| SM-CT-N13 | Both | A skin whose border style is flat, on the lane edges | The edges draw as flat strips; "None" hides the icon border |
| SM-CT-N14 | Both | The *Flat* entry in the background and border texture pickers' pull-out | It draws and can be picked |
| SM-CT-N15 | Both | Visibility: In combat only, hide after combat 5 s, hidden while mounted | The lane follows each rule |
| SM-CT-N16 | Retail | The Visibility tab's where rows | Delves and Arenas are present |
| SM-CT-N17 | Forever | The Visibility tab's where rows | Delves and Arenas are absent on WoW Forever |
| SM-CT-N18 | Both | `/ct ignore add` a spell by name, by shift-clicked link, then `/ct ignore reset` | The spell stops showing; reset brings the seed back |
| SM-CT-N19 | Both | Dismiss the pet mid-fight, then summon another | The Pet lane label dims, then reads the new pet's name; no error |

## 3. Fights and the meter

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-F1 | Both | A 40 s fight on a target dummy, then leave combat | The HUD's card appears 2 s after damage stops; the fight is saved |
| SM-CT-F2 | Both | A 10 s fight | Not saved, the card says too short |
| SM-CT-F3 | Both | Feign Death (Hunter) mid-boss and back in within 4 s | One fight, not two, and not lost |
| SM-CT-F4 | Both | Does the meter open a new session at `ENCOUNTER_START` mid-combat? | Recorded; if it splits, the boss part is the encounter fight |
| SM-CT-F5 | Both | Does the meter keep or replace the session across Feign Death? | Recorded; either way the fight carries on |
| SM-CT-F6 | Both | Are `DAMAGE_METER_COMBAT_SESSION_UPDATED`'s arguments secret in combat? | Recorded; the fight still binds to its session |
| SM-CT-F7 | Both | Back-to-back trash pulls in one combat | One fight; the identity line says "+N others" |
| SM-CT-F8 | Both | Reset the meter mid-fight | The fight is lost, not stored, no error |
| SM-CT-F9 | Both | `/reload` mid-fight and while settling | Nothing errors on the next load; nothing secret was stored |
| SM-CT-F10 | Both | The EnemyDamageTaken row field names (`sourceCreatureID`, `name`) | The primary target is named from them |
| SM-CT-F11 | Forever | A two-word character name from the meter's EnemyDamageTaken rows | Read whole |
| SM-CT-F12 | Both | Is `UnitGUID("pet")` secret in combat? | Recorded; the pet source still reads (or is nil-safe) |
| SM-CT-F13 | Both | With `PET_SEPARATE = true`, compare the player source's total to the meter's own window | The player's source does not already include the pet |
| SM-CT-F14 | Both | Target GUID, name and classification at `PLAYER_REGEN_DISABLED` | Recorded whether secret; the snapshot falls back cleanly |
| SM-CT-F15 | Retail | A delve fight: the delve tier read (`Compat.DelveTierText`) | The board key carries the tier |
| SM-CT-F16 | Retail | A Mythic+ fight and a Battleground Blitz (`C_PvP.IsRatedSoloRBG`) | The keystone level and the PvP bracket on the board key |
| SM-CT-F17 | Both | The FIGHT_STARTED snapshots at `PLAYER_REGEN_DISABLED` | No hitch on the pull (a perf capture if one is felt) |
| SM-CT-F18 | Both | Spell 19705 is named Well Fed | Usage marks food on both clients; a current Retail food buff matches it by name |
| SM-CT-F19 | Both | A merged fight when the meter split a session into it | The chart drops back cleanly |
| SM-CT-F20 | Retail | Race mode: arm a 60 s race, `/reload` before the first hit; arm again, hit the dummy, `/reload` at about 0:20 still in combat; then a third race, `/reload` past the buzzer in combat; then a fourth, leave combat at 0:20 and `/reload` | No race after the first reload; the second carries on with the time it had left and its buzzer sounds on time; the third is read after combat and saved flagged reloaded; the fourth is saved incomplete at about 0:20, read right after the load; no Lua error |

## 4. The DPS HUD

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-H1 | Both | A fight with a pet | Clock, target line, Damage with the Pet figure, DPS, pace bar, chart, spell rows with the paw |
| SM-CT-H2 | Both | The pace bar live and on the over card, once behind the best and once ahead of it (a pet class too) | Behind: your bar color up to where you are, then red to the middle tick; ahead: the left half full and green past the tick; on the over card the same against the final damage (the pet's included); no pet-colored segment |
| SM-CT-H3 | Both | Hover a title-bar control (`Frame:IsMouseOver()`) and a spell row | Tooltips show; `GameTooltip:SetSpellByID` with a secret ID does not error |
| SM-CT-H4 | Both | `SetMinMaxValues` with a secret max on the spell bars | The bars scale; no error |
| SM-CT-H5 | Both | `IsInInstance()` in combat with Only in instances on | The HUD opens only inside |
| SM-CT-H6 | Both | Beat the best on a board | The card shows New best (in the best blue) with the delta, and Saved; the chart's columns keep the bar color through a long cooldown |
| SM-CT-H7 | Both | The HUD's fade 8 s after combat, held by the mouse, and `/ct hud pin` | It fades, waits while hovered, stays pinned |
| SM-CT-H8 | Both | The test and sim strips under the title bar on both skins, and the body at small HUD heights | The strip sits under the title bar; the body is not clipped |
| SM-CT-H9 | Both | Show the HUD Always with Only in instances on, two fights in the open world | The HUD stays up through and after both fights |
| SM-CT-H10 | Both | `/ct debug on`, a 20 s fight on a dummy, then the over card; out of combat, the formatter probe in `midnight-quirks.md` (each `C_StringUtil` constructor's `FormatNumber(30190.4761904)` and `AbbreviateNumbers(30190.4761904)`) | The DPS tile, Damage and spell amounts never show a long decimal tail; the console names the paths ("numbers served by ..." and, live, "rates served by FloorToNearestString"), one line each per change and any constructor passed over; the probe's answers are recorded in `midnight-quirks.md` |
| SM-CT-H11 | Both | A fresh profile (or the swatches reset), a fight with a pet, side by side with DPS Race on the same skin | The spell rows, chart columns and the pace fill are DPS Race's blue at the same opacity; the pet rows and pet pace fill are a darker green with legible white text; the pace line is a pale neutral gray, not light blue; switching the skin leaves the fill colors as they are |
| SM-CT-H12 | Both | A fresh profile, the Ka0s Default skin, a fight with a best (live, then the over card), side by side with DPS Race's running body and result card | Same width (260) and about the same height; "Damage profile" and "Spell breakdown" in the same large gold heading with the same space over them; the pace bar directly under "Damage profile" and over the plot; the clock in the same face and size; spell rows 18 px in a 10 pt face; nothing overlaps at 236 px, the heading and its right-hand note included |
| SM-CT-H13 | Both | A fresh profile; a fight with more than 5 spells (a pet class too); drag the HUD's bottom-right grip taller and shorter, then lock it; then Layout > Window size Auto-grow with Grow Down and Up, dragging the title bar between fights | Fixed: 5 rows, the window the same height with 2 spells as with 12 and when the pet arrives; the note reads "live order · 1-5 of 12" and the wheel scrolls to 8-12 and stops, with a thin thumb in the right gutter; the grip's release snaps to whole rows and the Spell bars slider shows the new count; no grip while locked or in Auto-grow. Auto-grow: the window grows with the rows up to Spell bars, then scrolls; Down keeps the top edge in place, Up the bottom, after a /reload too; nothing overlaps the footer, the over card included |
| SM-CT-H14 | Forever | A Hunter fight where the pet melees and casts, then one where only the pet fights; `/ct debug on`; then `/ct probe` in and out of combat | Live, every row is blue and the pet's rows show its name at the right (the owner's none); on the card the pet's Attack, Claw and Bite carry the paw in the pet's color and the owner's Attack and shots stay blue; the pet-only fight's Attack is the pet's; the live Pet figure as SM-CT-H15 says; the console logs "folded split: … by creature name"; the probe's spell lines show `creature ""` on the owner's rows and the pet's name on the pet's (`<secret>` on all in combat) |
| SM-CT-H15 | Forever | A Hunter with the pet out: a 20 s fight on a dummy, the pet attacking; then `/ct probe` (SM-CT-P8); then a fight with the pet dismissed | Live, the boxes show a Pet row the whole fight while the pet is out. If SM-CT-P8 read "live Pet figure: split": the Pet figures move with the pet's damage, your Damage and DPS are your own part (lower than the merged figure the card shows after, by about the Pet figure), and the pace bar runs against the best's player line. If it read "dash": the Pet figures are a dash and Damage and DPS are the merged figure, as before. With no pet out there is no Pet row. Record which one this client gives in `known-limitations.md` |

## 5. Results

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-R1 | Both | `/ct results` after a few saved fights | The list, filters, grouping by board; a click opens the detail |
| SM-CT-R2 | Both | The standalone-windows resize check: drag the grip | The list follows without lag; the size survives `/reload` |
| SM-CT-R3 | Both | Add a note (the StaticPopup edit box) | The note saves |
| SM-CT-R4 | Both | The dropdowns with 500 fights | They open without a hitch |
| SM-CT-R5 | Both | The window under EllesmereUI's band | Draws correctly |
| SM-CT-R6 | Both | The Usage icon file ids (134062, 134400) | Both icons draw |
| SM-CT-R7 | Both | Share to party and say | One line; the difficulty short names read right; refused in combat |
| SM-CT-R8 | Both | A talentbuild link in chat | It opens the talents |
| SM-CT-R9 | Retail | View Talents | Opens PlayerSpellsFrame; the Results window steps aside and comes back |
| SM-CT-R10 | Both | Item tooltips from a trimmed item string, and Shift-click links | Full tooltips; the link posts |
| SM-CT-R11 | Both | The detail's four boxes at 440 px | Damage, DPS, Meter DPS and Delta fit |
| SM-CT-R12 | Retail | The Spec dropdown, column and grouping | Present |
| SM-CT-R13 | Forever | The Mythic+, delve and arena content filters | Absent on WoW Forever |
| SM-CT-R15 | Forever | A fight with points spent, then `/ct results` | The row's second icon is the predominant tree's (never the class icon twice); the dropdown reads "All talent trees" / "Current talent tree"; "Group: Talent tree" groups by it; Share names the tree |
| SM-CT-R16 | Both | `/ct results` open, then pull a mob; reopen it mid-fight; then turn History → Results window → Close when combat starts off and pull again | The window and its timeline, gear view and compare close on the pull; reopened mid-fight it stays open; with the option off it stays open |
| SM-CT-R17 | Both | `/ct results`: the title bar's fold arrow, then the Character column's header edge | Collapsed shows a right chevron, expanded a left one; Character opens at 104 px and the target column takes the slack; dragging the header edge resizes it, the width survives `/reload`, and Reset position puts it back |
| SM-CT-R14 | Both | An open-world fight, then the same mob at another level (or a Retail mob after a level-up), then `/ct results` | The detail's three meta lines name the realm, ilvl and the zone (never the continent), the target with its level, and the stamp; the two levels group as two boards, and a second fight at one level paces against the first on the HUD |
| SM-CT-R18 | Both | `/ct results` with a few fights on one board, one with a trinket and a potion used, one with a note | Delta reads a green 0.0% on each group's best (no trophy, no "Best"); Status shows a blue "Best" with the trophy on the board's best only; Used shows the trinket and potion icons, with their names and times on hover, and a dash for a fight with nothing; Note shows the first ten characters, the whole note on hover; the Damage and DPS bars are one blue for every class, the same shade as DPS Race's |
| SM-CT-R19 | Both | Right-click a fight → Add Note, type `\|cffff0000red\|r`, press Enter; then Edit Note, clear it, Save; `/reload` between | Enter saves and closes the box, as Save does, and Escape closes it unsaved; the note reads `/cffff0000red/r` in plain text, never red; a cleared note leaves the Note cell empty and the menu reads Add Note again; the note survives `/reload` |
| SM-CT-R22 | Both | `/ct results` on a fresh profile with fights on two days; then each Group option; then Save, change a filter, Clear, then Reset; then Compare on a fight | The list opens grouped by date and character, the newest day first, its header "11 Nov 2026 · <name>"; Group: Date lists one header per day; under both, Delta still reads each fight against the best on its own encounter; every other list row is faintly tinted, as DPS Race's; Clear brings the saved view back and keeps it, Reset goes back to the shipped one; the HUD's and the fight detail's spell rows alternate the same tint, which stays with its spell on the wheel; the compare's boxes center their label, figures and change, the change on the bottom line, and its spell rows alternate the tint |
| SM-CT-R23 | Both | `/ct results` on a profile that never resized the window; then Compare on a fight; then DPS HUD → Spell rows → Bar border: Show border, then a thickness of 2, a color, Use the skin's border | The window opens at its least width, the filter bar and the columns just fitting; the compare's boxes read Damage, DPS, Length, as the HUD's Damage then DPS; out of the box the spell bars have no border, and with Show border every bar on the HUD and in the fight detail gets the same edge, round the bar and not the icon, in the picked thickness and color |
| SM-CT-R24 | Both | At a UI scale that is not round (Options → Graphics → UI Scale, say 0.71), a fight with eight or more spells; look at the HUD's spell rows and the fight detail's Spell breakdown, then DPS HUD → Spell rows → Bar border: Show border | Every spell bar is the same height and every gap between bars the same, top to bottom; with the border on, every bar's edge is one pixel on all four sides, none thicker than another |
| SM-CT-R25 | Retail | A 30 s race on a training dummy (pull, then the first hit a moment later), then its detail in `/ct results` and its Timeline; then a plain fight's | The Damage profile and the Timeline start at the first hit, not at combat entry: an opener sits on 0:00 and a cast before the first hit at the very left; a thin blue-violet buzzer line (the Timing strip's race color) crosses the chart, the Casts strips and the lanes at 0:30; the plain fight has no such line and starts at combat entry |
| SM-CT-R21 | Both | A fight on two mobs of one name and a third of another (Forever: two Redridge Brutes and a Mystic), then its detail in `/ct results`; then a fight stored before this version; then `/ct test` | Below Usage, a Targets section lists Redridge Brute (both Brutes, one row) and Redridge Mystic, highest first, each over a blue bar as long as its amount against the top target's, then three right-aligned white columns a little apart: its amount, its DPS over the fight (EllesmereUI's figure: amount over the fight's length) and its share; the amounts sum to your damage when solo; it folds like the others; the older fight has no Targets heading; a sample fight shows its target and one "Sample add" row. In a group: note whether a row's amount is yours or the group's |
| SM-CT-R20 | Both | Open a fight's detail; click each section heading's arrow, then each heading's text; `/reload`; Master controls → Reset position; read the footer and Gear and Talents | Each section folds to its heading (chevron-right) and the sections below move up, and opens again (chevron-down); the folds survive `/reload` and Reset position; the footer reads Add Note, Share, Timeline, Compare (plain buttons) with Delete at the right, 10 px clear; the buttons read View gear and View Talents, no Copy; on Forever the talents line reads "Talents: <Class> (a/b/c)" |

## 6. Timeline, compare and gear view

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-T1 | Both | Open the timeline, press Escape | The modal closes first; the Results window stays |
| SM-CT-T2 | Both | The dim cover | It takes the mouse |
| SM-CT-T3 | Both | Ctrl+wheel zoom, Shift+wheel pan, the scrollbar thumb drag | Zoom about the cursor; the axis moves |
| SM-CT-T4 | Both | The pet toggle rows (UICheckButtonTemplate) under each skin, and the opaque modal shell | Drawn by the skin |
| SM-CT-T5 | Both | The compare at 14 rows and its wheel scroll | Scrolls; the Different loadout mark when talents differ |
| SM-CT-T6 | Both | The gear view: file id 136244 for the enchant mark, Shift-click links | The mark draws; links post |
| SM-CT-T7 | Forever | A new fight's gear view | Primary lists Strength, Agility, Stamina, Intellect, Spirit and Armor; Secondary lists Attack Power, Ranged Attack Power, Spell Power, Critical Strike, Hit and Haste (a stat the client cannot read is left out); no Mastery, Versatility or Tertiary; the bottom row reads Main hand, Off hand, Ranged and Ammo, filled or Empty |
| SM-CT-T8 | Both | The Never show menu in the Usage edit | The item leaves the list and joins History → Usage |
| SM-CT-T9 | Both | Fight twice in the same gear, swap a full equipment set (the Equipment Manager), fight again, `/reload`, fight again, then `/ct diag` | `gearSets=2`, not one per fight or per slot; the gear view and Compare's *Gear changed* show the swap; nothing new after the reload |
| SM-CT-T10 | Both | Open Compare on a fight that is not its board's best, then on the best, then after *Compare With This Fight* on another; hover the button each time; use a trinket and a potion in one fight and not the other | The button reads Compare and its tooltip names the best, the runner-up or the pick; this fight's bars, legend, figures and item levels are yellow and the other's blue in every case; *Trinkets and consumables* lists each item once, gear first, the other's uses then this one's, "not used" on the side without it, the item tooltip on hover; "None used" with nothing on either side |
| SM-CT-T11 | Both | On a fight with a pet and a best on its board, press *Timeline*; hover a lane icon of yours, one of your pet's, and the *Casts* icon of the first cast; zoom in two steps and pan right; click *Ticks*, then *Icons*; set History → Results window → *Casts in By ability* to *Tick lines* with the timeline open; `/reload` and open it again | Every By ability cast is its ability's icon inside its lane, a cast at 0:00 whole; your icons and your pet's sit on a thin blue-violet and green edge (the *Casts* icons too) and the corridors stay gold and blue; each lane icon's tooltip is the *Casts* icon's (spell, *Cast at m:ss*, *(pet)* on a pet's, the fight); *Ticks* turns them into thin ticks in the same caster colors and keeps the zoom and the pan, *Icons* back; the setting redraws the open window; the mode survives `/reload` |

## 7. Settings pages

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-S1 | Both | Each page's Defaults button | Resets that page only, after asking |
| SM-CT-S2 | Both | History → Usage: the ID list's lookup by name and Shift-click | Both add the item |
| SM-CT-S3 | Both | The History tab's stored-size readout with 500 fights, and Purge history… | Draws without a hitch |
| SM-CT-S4 | Both | Row height changed while the Results window is open | The list redraws |
| SM-CT-S5 | Retail | History → Recording filters | Mythic+, Delves and Arenas rows present |
| SM-CT-S6 | Forever | History → Recording filters | Mythic+, Delves and Arenas rows absent on WoW Forever |
| SM-CT-S7 | Both | Switch, copy and reset a profile | Every window redraws from the new profile; fights stay |
| SM-CT-S8 | Both | `/ct skin`, preview a skin, Apply; then close the picker without Apply | Apply keeps it; closing puts everything back |
| SM-CT-S9 | Retail | The Race mode page: its three tabs; `/ct race arm 1:30`, then `/ct race cancel`; `/ct race ignore add` a spell, then `/ct race ignore defaults`; Race mode off, then `/ct race arm` | The tabs are Race, Late-cast ignore list and Race window; the race arms at 1:30 and the cancel says so; the list follows each verb and the page redraws; off, the arm says Race mode is off |
| SM-CT-S10 | Retail | Auto-arm on, target a training dummy out of combat, then a boar; target the dummy and pull | Armed on the dummy, canceled on the boar; the pull starts the race |
| SM-CT-S11 | Forever | The settings panel, `/ct help` and `/ct race` | No Race mode page, `race` is not in the help, and `/ct race` is an unknown command |

## 8. Test mode and the sim

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-M1 | Both | `/ct test` | Sample casts loop on the lanes, the HUD holds a sample fight, the Results window shows the sample history, each under its strip |
| SM-CT-M2 | Both | Enter combat in test mode | Test mode ends; nothing was saved |
| SM-CT-M3 | Both | `/ct sim newbest`, then `short` and `lost` | The fight plays in real time; the card says New best, then Not saved. The `race-` scenarios are Retail's (SM-CT-RM42) |
| SM-CT-M4 | Both | `/ct sim` step window | Anchored beside the HUD |
| SM-CT-M5 | Forever | The WoW Forever mock spell and item IDs | Every sample icon draws |
| SM-CT-M6 | Both | `/ct test` on two different characters (another class, another realm); read the HUD and the Results window | The same showcase on both: Samplehunter and Mockarrow on Samplerealm, the same fights and figures. The HUD at 0:25: Damage and DPS each with the Pet figure under it, DPS the damage over 0:25 (2.71M at 108.4K on Retail), the spell rows adding up to the damage, the pet's rows marked with the paw and named Grimfang in the right column, cooldown marks on the chart against the best's pace, the pace bar ahead of the best. `/ct test` shows no toast and no call-out |
| SM-CT-M7 | Both | History → *Toast a fight's new best* on; `/ct sim newbest`, then `behind`; then `/ct sim newbest` and stop the sim while its toast is up | The new best's card is joined by the new-best toast and, on Retail with Race mode on, the call-out's NEW BEST; behind shows neither; stopping the sim takes the toast and the call-out down at once. Nothing is saved, and the History list and the HUD's real bests are unchanged |

## 9. Training dummies and the recording rules

Both clients (race plan Tasks A1 and A2). On Retail use the Reinforced Golem (243205, Boss-level) or
any built-in dummy. On WoW Forever no dummy is built in, so add one first (SM-CT-D2).

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-D1 | Retail | Target a built-in dummy (the Reinforced Golem), fight it for 35 s, then `/ct results` | The fight is saved with Training dummies as its content and the dummy's name as its target |
| SM-CT-D2 | Both | Target a creature that is not a built-in dummy, `/ct dummy add`, then `/ct dummy` (WoW Forever: any target dummy in a capital) | One line says it is a training dummy now, as Single target; `/ct dummy` lists it under *Your training dummies* and counts the built-ins (0 on WoW Forever) |
| SM-CT-D3 | Both | `/ct dummy add cleave` on the same target, then a 35 s fight on it | The line names Cleave; the fight is saved as a Training dummies fight |
| SM-CT-D4 | Both | History → Training dummies: *Add your target*, the list's X, a built-in's checkbox cleared (Retail), *Reset list*; then `/ct dummy remove` on a built-in and `/ct dummy defaults` | Each change shows at once on the tab and in `/ct dummy`; a built-in switched off is listed as off and `/ct dummy add` on it brings it back; Reset list and `defaults` leave only the built-ins |
| SM-CT-D5 | Both | `/ct dummy capture` on a target, then `/ct dummy` | One *Saved:* line with its level, health, zone and place; the target is not marked a dummy and `/ct dummy` does not list it |
| SM-CT-D6 | Both | A fight on a dummy saved before it was added, then add it and fight again | The older fight keeps its content (open world); the new one is Training dummies |
| SM-CT-D7 | Both | `/ct dummy add` on a player, or with no target | One refusal line each; the list does not change |
| SM-CT-D8 | Retail | History → Recording filters on a fresh profile | Minimum fight length reads 30, every content kind ticked, Scenarios too |
| SM-CT-D9 | Forever | History → Recording filters on a fresh profile; then a 20 s fight and a 12 s fight | Minimum fight length reads 15, every content kind ticked, Scenarios too; the 20 s fight is saved, the 12 s one is not (the card says too short) |
| SM-CT-D10 | Retail | A 20 s fight on a fresh profile | Not saved, the card says too short (the minimum is 30 s here) |
| SM-CT-D11 | Both | A fight inside a scenario (Retail: a Delve's lead-in or a world scenario; WoW Forever: any scenario the client has) on a fresh profile | Saved, its content Scenarios; untick Scenarios and the next one is not saved |
| SM-CT-D12 | Both | A profile made before this version that never changed Scenarios or the minimum length, then a scenario fight (WoW Forever: and a 20 s fight) | The new defaults apply to it: Scenarios ticked, the minimum 30 s on Retail and 15 s on WoW Forever; a value the profile set itself is kept |

## 10. Race mode

Retail only (race plan Tasks B1 to E1), ported from DPS Race's smoke suite (its sections 4, 5 and
20-24) onto Combat Trail's verbs and windows: `/ct race` for DPS Race's `/dr arm` and `/dr cancel`,
the Race window for DPS Race's race HUD, and the DPS HUD for its live damage. Use a 0:30 race on the
Reinforced Golem (243205) unless a row says otherwise, and a Dungeoneer's Training Dummy where a row
needs combat to hold. There is no launcher entry for the Race window (ruling X17); on Retail it has a
key, *Toggle Race window* (SM-CT-RM57), and `/ct race show` and `/ct race toggle` open it, and work in a
macro.

### The Race window and arming

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-RM1 | Retail | `/ct race show` with no target, then target the Golem | The Race window opens beside the DPS HUD, on its right: the presets 0:30, 1:00, 2:00, 3:00, 5:00 and *Custom*, the target card (*No target*, then the Golem's name with its Boss-level chip), *Your best* (none yet), *Arm Race*; nothing overlaps |
| SM-CT-RM2 | Retail | Target a creature that is no training dummy | The target card warns that a race armed now is canceled when that pull starts |
| SM-CT-RM3 | Retail | *Custom*: type `90`, `1:30`, `3m`, then `5` | The first three are taken (1:30, 1:30, 3:00); `5` is refused with *A race lasts from 0:10 to 15:00.* |
| SM-CT-RM4 | Retail | Enter combat on anything, then look at *Arm Race* and click it; `/ct race arm` | Grayed with *Leave combat to arm a race.*; the click and the verb say the same |
| SM-CT-RM5 | Retail | `/ct race arm 30` out of combat | The armed body: 0:30, still, and that the first hit starts the clock; chat prints *Armed: 0:30 on Reinforced Golem. First hit starts the clock.* |
| SM-CT-RM6 | Retail | Pull with a cast-time spell, then on a second race with an instant | Both times the race clock starts on the first hit, not on the cast's start or the combat entry; the DPS HUD opens on the same hit |
| SM-CT-RM7 | Retail | On a fresh profile, a race; then Race mode → Race → *Race clock*: *Elapsed*, then *Elapsed and time left*, then *Time left*, during a race | A fresh profile shows *Time left*: one large countdown, green at the start (SM-CT-RM60 has its colors), with *Left of 0:30* under it; *Elapsed* one large green clock with *Elapsed of 0:30*; the pair side by side with no caption; the change shows at once |
| SM-CT-RM8 | Retail | Race mode → Race window: untick *Attach to the DPS HUD*, drag the window, `/reload`; then each *Side of the DPS HUD*; then the title bar's attach control; then Master controls → Lock frame and Reset position | Detached it drags and holds its place; attached it stands flush against the HUD on the side picked, with no gap, and moves with it; the control attaches and detaches; locked, no drag; Reset position puts the detached place back |
| SM-CT-RM9 | Retail | Attached, close the DPS HUD by hand (or with DPS HUD → Behavior's Show on toggle, the HUD hidden), then `/ct race show` | The Race window stands where the HUD would be, never at the screen's corner or off screen (Review focus 4) |
| SM-CT-RM10 | Retail | `/ct race toggle` twice; then Race mode off and `/ct race show` | It opens, then closes; off, one line says Race mode is off and nothing opens |

### The race

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-RM11 | Retail | Keep attacking through a 0:30 race | The running body: the race clock counting (SM-CT-RM52 has its parts), and no pace bar; the DPS HUD beside it shows the live damage, DPS, chart and spells, its pace on the race board (whatever DPS HUD → Behavior's Show, Only in instances and Show DPS HUD in combat say, ruling X7) |
| SM-CT-RM12 | Retail | Hear and watch the last 10 s with the defaults; then *Center countdown from* 3; then *Center-screen countdown* off mid-countdown | Big white numbers 10 to 1 slam in above the middle of the screen with a soft glow, one a second, and go at the buzzer; the voice (the female pack) says five, four, three, two, one, each once and never twice, and nothing for 10 to 6; the Race mode page has no cue sound row; from 3 the numbers start at 3, spoken; switched off, the number on screen goes at once and nothing more is said |
| SM-CT-RM13 | Retail | With about 8 s left, open a Results filter dropdown over the numbers | The menu draws over them; the mouse passes through the numbers |
| SM-CT-RM14 | Retail | Stop on the buzzer; then a race with *STOP at the buzzer* off | The center call-out's *STOP* in red, spoken once, fading after about a second and a half, with no raid warning and no other sound; with the row off no STOP shows or is said and the race still stops; the Stop! body: the damage tail climbing while DoTs tick, the late casts so far, the time in combat, *Stop Now* and *Cancel* |
| SM-CT-RM15 | Retail | On the Dungeoneer's dummy, stay idle in combat 20 s after the buzzer | The waiting body with the time in combat; after 15 s (*Sticky-combat hint after*) the hint names the drop-combat abilities this character has |
| SM-CT-RM16 | Retail | *Stop Now* on the Stop! body out of combat, then on another race while waiting in combat | Out of combat the race is read at once, without waiting out the tail; in combat it is read the moment combat ends, with no settle wait; the result card shows |
| SM-CT-RM17 | Retail | Read the result card, then the chat | Score, race DPS (the score over 0:30 exactly; check it in the detail), the verdict against the best (*New best* on the board's first race), the flag chips, no pace bar (SM-CT-RM53 has the tables under them), *New Race*, *Open*, *Share*, *Delete*; chat prints the score line once |
| SM-CT-RM18 | Retail | *New Race*; then *Open* on another card | New Race goes back to *Arm Race* with 0:30 picked and the same target, nothing armed; Open shows the race in the Results window |
| SM-CT-RM19 | Retail | Stop attacking at about 0:12 left and drop combat | Incomplete: the card says combat ended before the buzzer, its DPS is the score over the time raced, and it never takes a best (no toast) |
| SM-CT-RM20 | Retail | Feign Death (Hunter) at about 0:15 and back in within 4 s | The race is incomplete at the Feign Death (ruling X4); the fight carries on and is saved whole; the race's DPS divides by the fight's race-clock length (ruling X16) |
| SM-CT-RM21 | Retail | Let the Dungeoneer's dummy kill you mid-race | The card says incomplete, died |
| SM-CT-RM22 | Retail | Cast a spell 2 s after the buzzer; then put it on Race mode → Late-cast ignore list and look at the race again | The card and the detail flag the late cast; on the list, the flag goes from that race and every other saved one (the list is read at score time) |
| SM-CT-RM23 | Retail | Stop at the buzzer, stay in combat on the Dungeoneer's dummy 10 s without attacking, then attack again | The result carries the damage-restarted flag at about +10 s |
| SM-CT-RM24 | Retail | `/ct race cancel` while armed, then while running; then *Cancel* while waiting | Armed: *Race canceled.*; running and waiting: the race is off and the fight goes on as a plain dummy fight, saved by the recording filters as any other; nothing is saved as a race |
| SM-CT-RM25 | Retail | Arm, then pull a mob that is no dummy (or walk into an instance) | The arm cancels with the pull; the fight is a normal fight with no race part; no error (Review focus 1) |
| SM-CT-RM26 | Retail | Fight the Golem, let combat drop, then arm and pull it again within a few seconds, while the meter still holds that session | The race is flagged shared session, its score is the session's total less what it held at the arm, and it is saved once (Review focus 5); the HUD draws no pace and no chart for it |
| SM-CT-RM27 | Retail | Reset Blizzard's damage meter while armed, then while running | Armed: still armed. Running: the race is lost, the card says its result could not be read, and nothing is saved as a race |
| SM-CT-RM28 | Retail | Close the result card (its close mark, then Escape on a fresh one); *Delete* on another, then delete a race in the Results window while its card shows | The card is dismissed and the race stays in the history; Delete asks first, and the window goes back to *Arm Race* at that race's length |
| SM-CT-RM29 | Retail | The toast: a race that beats its board's best; then the board's first race; then History → New-best toast → *Toast a race's new best* off | A toast near the top says New best and by how much, with the dummy kind and length chips; the first race shows none; off, no race toasts while a fight's still does (with *Toast a fight's new best* on, which a new profile leaves off) |
| SM-CT-RM30 | Retail | Race mode off (the switch at the top of the page) with a race armed, then with one running | The armed race is canceled; the running one runs on to its result; afterwards no race arms, auto-arm does nothing, the Race window stays shut and the saved races stay in Results |

### Reload and resume

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-RM31 | Retail | `/reload` at 0:15 left, still attacking (SM-CT-F20 covers the four reload cases in one pass) | The Race window and the HUD come back on the same race clock; the center numbers start at 0:10 left as usual (SM-CT-RM79 reloads inside them); at the buzzer the race resolves as usual |
| SM-CT-RM32 | Retail | On the Dungeoneer's dummy, `/reload` 2 s after the buzzer still in combat | After the reload the window is waiting; once combat drops the result reads with the reloaded flag |
| SM-CT-RM33 | Retail | Race, and while waiting for the read log out to the character screen and into another character | The other character is idle and can arm; back on the first the race resumes, or reads lost if its session is gone |

### Near a training dummy

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-RM34 | Retail | Auto-show on (the default): walk up to the Golem with enemy nameplates on, then away; then close the window by hand near it; then near it open the window yourself (`/ct race show`) and walk away | It opens while the dummy's nameplate is up or it is targeted, with the DPS HUD beside it (SM-CT-RM48), and closes a few seconds after the last one is gone; closed by hand, it stays closed until the next time you come near one; opened by you near the dummy, it closes when you walk away, as auto-show's own does (SM-CT-RM55 has the long form) |
| SM-CT-RM35 | Retail | Auto-arm on: target the Golem out of combat, then a boar, then the Golem in combat; then in an instance | Armed at the window's length on the Golem, canceled on the boar; nothing arms in combat or in an instance (SM-CT-S10 is the short form) |

### Results and Insights

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-RM36 | Retail | `/ct results races` after the races above | The list on the Races filter: each race with its race DPS, a length chip and a flag chip (Flagged, Incomplete, Died); the second filter row shows the race length, the dummy kind, Hide flagged, Include incomplete and Only best; the groupings by race length and by dummy kind and length list them under headers |
| SM-CT-RM37 | Retail | Each race filter in turn; then *Fights only* and *Fights and races* | Each narrows the list as it says; Fights only hides every race; both kinds list together under the third |
| SM-CT-RM38 | Retail | A race's detail | The Timing strip (race length, the tail after the buzzer, the combat end) and the Flags box; Damage, race DPS and Delta; right-click a late cast in Flags and *Ignore for late casts* takes it off the flags (SM-CT-R25 covers the race clock on the chart and the Timeline) |
| SM-CT-RM39 | Retail | `/ct results insights`, then the Fights / Races / All filter, then Races with Clean only and Include incomplete | The cards, DPS Progression, the board tabs with Spec Comparison and Consistency, By Character, By Character x Content and Recent New Bests over every saved fight; under Races the race-only sections show (Races By Character x Length, Late Casts, Races Per Day, Damage Tail After The Buzzer) and the Clean races card; under Fights both are gone |
| SM-CT-RM40 | Both | Log in on WoW Forever (or turn Race mode off on Retail) on an account that holds saved races, then `/ct results` and its Insights tab | No Lua error. Forever: the races list as fights with their race DPS, with no Fights / Races / All filter, no race chip, no Timing or Flags section and no race section in Insights. Retail with Race mode off: the race controls are still there (Review focus 3) |

### Test mode, the sim, share and diagnostics

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-RM41 | Retail | `/ct test race armed`, `running`, `result`, then bare `/ct test race` | The Race window holds a sample race in each body (running when none is named), under the sample strip, beside the HUD's sample fight; Results shows 40 sample fights and 16 sample races |
| SM-CT-RM42 | Retail | `/ct sim race-newbest`, then `race-incomplete`, `race-flagged`, `race-shared` and `race-sticky` | Each plays in real time: armed, running with the countdown and the STOP warning, then its ending (the new best with its toast; incomplete; the late-cast flag; the shared-session flag; the sticky-combat hint), the chat lines, then the Results window on the sample race. Nothing is saved |
| SM-CT-RM43 | Retail | Race mode off, then `/ct test race` and `/ct sim race-newbest`; then a real `/ct race arm 30` while test mode is on | Both refuse in one line; the arm ends test mode with *Test mode ended: a race was armed.* |
| SM-CT-RM87 | Retail | `/ct test race running`, then `result`, then `armed`, then `result` again and `/ct test` off | Running: 0:18 on the clock, 0:08 and 0:15 passed (green), 0:23 next (amber), each checkpoint's best figure on the best's straight line, no center number (the held clock stands still). Result: the new-best toast and the call-out's NEW BEST, said in the chosen voice. Each switch and the stop take both down at once; nothing is saved |
| SM-CT-RM88 | Retail | `/ct sim race-newbest`, then `race-incomplete`, `race-died` and `race-behind` | race-newbest: the center numbers count to the Race window's 0:00.0 and STOP shows at the buzzer, then at the result the toast and NEW BEST. race-incomplete and race-died: FAILED as combat ends before the buzzer, no STOP, no toast. race-behind: STOP at the buzzer, no toast, no NEW BEST. `/ct sim stop` (or the step panel's Stop) mid-countdown or with a word or toast up takes them down at once |
| SM-CT-RM44 | Retail | *Share* on the result card to Say, then a race from the Results row menu | One line with the race's length, target, damage and DPS; refused in combat |
| SM-CT-RM45 | Retail | `/ct diagnostics` while idle, then while a race runs | A race section: the race state, its fight and session, the pending races, the race boards, the Race window (with `matched=`), `race beat on=false` idle and `on=true` while the race runs, the countdown and the sample race; the windows section has the toast line |
| SM-CT-RM46 | Forever | `/ct test race`, `/ct sim` and `/ct diagnostics` | `test race` is plain test mode; the sim's list has no `race-` scenario; the report has no race section but keeps the toast line |
| SM-CT-RM47 | Both | `/ct perf start`, a 0:30 race (Retail) or a fight (WoW Forever), `/ct perf finish` | No hitch felt; on Retail the `race`, `raceWindow`, `raceClock` and `autoArm` buckets show figures |

### The Race window beside the DPS HUD

Race window redesign plan, rulings O1 to O6 (O5's two rhythms and O6's checkered flag superseded
on 2026-11-13: SM-CT-RM68, SM-CT-RM69 and SM-CT-RM49): near a dummy the DPS HUD and the Race window work as one
panel. Run these on a fresh profile with a best on the 0:30 Golem board (race it once first) unless a
row says otherwise.

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-RM48 | Retail | Both windows shut, walk up to the Golem; walk away; then Race mode → Race → *Show the DPS HUD near a training dummy* off and walk up again, then that row on and *Show the Race window near a training dummy* off, then both off; both on again, near the dummy close the DPS HUD by hand, step away briefly and come back within the few seconds; then fight the dummy and walk away before the HUD fades | Both open together; both close a few seconds after the dummy is gone; with either row on both open (neither row is grayed), with both off neither does; closed by hand, the HUD takes the Race window down with it and both stay shut for the rest of that dummy session, opening again on the next one; a HUD with a fight on it never closes with the session and fades by its own rules (SM-CT-RM72) |
| SM-CT-RM49 | Retail | Read the DPS HUD's title bar with Race mode on; click its flag, twice; open the Race window with `/ct race show` and close it with its close mark; turn Race mode off; then hide the title bar (DPS HUD → Layout) | Left to right: Results, Race (a plain flag), Settings, Lock, Close, evenly spaced and the same size (SM-CT-RM67), with the tooltip *Race window*; the click opens and closes the Race window as `/ct race toggle` does, and never opens or closes the DPS HUD; the flag turns gold only under the pointer, like the other controls, and carries no light for the Race window being open, after a `/reload` too; with Race mode off the flag is gone and the strip closes up; with no title bar no control shows |
| SM-CT-RM50 | Retail | Attached on the right, then the left: drag the HUD's grip taller and shorter, switch Layout > Window size to Auto-grow and fight until a spell row arrives, hide and show the HUD's title bar and footer; then *Side of the DPS HUD* Top and Bottom; then detached; then *Match the DPS HUD's height* off | Right and left: no gap between the windows, the Race window's top and bottom level with the HUD's through each resize, and never shorter than its own screens need (a HUD shrunk below that leaves the Race window the taller); its buttons stay at its bottom and the space above them grows; Top, Bottom, detached and the row off: its own height, flush against the HUD where attached |
| SM-CT-RM51 | Retail | Watch both clocks through a 0:30 race; then `/ct test race running`; then an ordinary fight on a boar with the Race window shut | During the race the HUD's clock (elapsed) and the Race window's countdown change in the same frame, tenths moving smoothly about ten times a second (the default *HUD refresh rate*), and the two always add up to the race length; the sample race's two clocks do the same; the boar fight's HUD also moves about ten times a second, its clock and its Damage and DPS figures alike (SM-CT-RM68) |
| SM-CT-RM52 | Retail | The running screen of a 0:30 race with a best on the board; then a race on a fresh board; then a race flagged shared session (SM-CT-RM26); then a long race on a strong character, so the figures run to six or seven digits | Top to bottom: one large countdown in its color over the race (SM-CT-RM60), *Left of 0:30*, a time bar drawn like the DPS HUD's pace bar (no border, the pace bar's dark track, an 8px bar) that starts full and empties to the buzzer, in the countdown's color, with a pace-bar tick at each quarter, the race's chips, *Best to beat* (one row, *Damage* and the score, then *DPS* and the race DPS, labels in dim gold and both values in the plain text face in the dim color, no big DPS figure; the date and item level under it), *Best by now* (*at 0:12* and so on beside its caption, a thin pace bar, then *Best*, the best's score times the time raced over 0:30, beside *Current*, your damage so far, each value a fixed step after its label and never running into the other half, even at six or seven digits), *Checkpoints* (*best · current* beside its heading; four cells, each top to bottom the time in a larger dim-gold face, the best's damage at that quarter, yours, and a short bar nine tenths of the cell wide, nothing touching or clipped, labeled 0:08, 0:15, 0:23 and 0:30, the passed ones' best figure dimmed and the next one outlined; SM-CT-RM59 has your figures, SM-CT-RM70 the bars, SM-CT-RM71 the colors), then space, then *Cancel* at the bottom; no full pace bar, and no word, mark or difference says ahead or behind. On a fresh board *Best to beat* says *No race yet: this one sets the mark.*, and Best by now and Checkpoints are gone. The shared-session race keeps its chip and still shows the best's figures |
| SM-CT-RM53 | Retail | The result card of a race that beats the best; then one that does not, ranked outside the top three; then the board's first race; then a lost race (SM-CT-RM27) | Score and Race DPS, the chips, then *Against your best*: rows Score, DPS, Item level and Date (no time raced row), columns This race, Best and Diff, the Diff green where this race is higher and red where lower (DPS as a percentage), no diff for the date; then *Top races* with its kind, length and spec: the top three races, this race's row highlighted, and when it is not in the top three its own row under them with its rank; then the four buttons at the bottom; no pace bar. The first race shows no Against your best. The lost race shows *Couldn't read the result* and neither table |
| SM-CT-RM54 | Retail | The idle screen on the Golem with 0:30 picked, the board holding races; then a length with no race on it | *Your best* shows one row, *Damage* and *DPS* in dim gold labels with their values in the plain text face, the date and item level under it (no big DPS figure); *Top races* (the top three) sits between Your best and *Arm Race*; on the empty board it is gone and the rest of the screen is as before |
| SM-CT-RM55 | Retail | Near the Golem with auto-show's window up: detach the Race window, attach it again, close it with its close mark, open it with the HUD's flag, then walk away; come back; then open it with `/ct race show` far from any dummy, walk up to the Golem and away again | Detach and attach move it only; closed by hand it stays shut until you open it; opened by you in the dummy session, it closes a few seconds after you walk away, and opens again by itself when you come back; opened before the session began, it stays up when you walk away (it is yours) |
| SM-CT-RM56 | Retail | Both windows up: press the *Toggle DPS HUD* key; press it again; then the launcher's *Show window* entry twice and `/ct hud toggle` twice; then `/ct hud hide`; `/ct hud show`; then the HUD's close mark and Escape with both up; then `/ct race toggle` and the flag, twice each; then near the Golem close both with the key, and press it again | Each closing toggle and `/ct hud hide` close the HUD and the Race window together; away from a dummy each opening toggle and `/ct hud show` open the HUD alone; the close mark closes the HUD and hides the Race window with it, which comes back with the next `/ct hud show` (SM-CT-RM73); Escape closes both as your closes; `/ct race toggle` and the flag close only the Race window, and open it with the HUD when the HUD is shut; near the dummy, the closing key leaves auto-show shut for the rest of that session (each close counted as yours), and the opening key opens both again (SM-CT-RM62) |
| SM-CT-RM57 | Retail | Options → Keybindings → Ka0s Combat Trail, then General → Keybindings; bind *Toggle Race window* and press it twice, then with Race mode off | Four keys in order: *Toggle DPS HUD*, *Toggle Results window*, *Toggle Race window*, *Toggle lanes*, the same in both places; the key opens and closes the Race window as `/ct race toggle` does; with Race mode off it prints that Race mode is off and nothing opens |
| SM-CT-RM58 | Forever | Options → Keybindings → Ka0s Combat Trail, then General → Keybindings | Mandatory: three keys, *Toggle DPS HUD*, *Toggle Results window*, *Toggle lanes*, and no *Toggle Race window* in either place. If WoW Forever lists the Race key, it read `Bindings_Mainline.xml`: report it, as the fallback is a Forever-specific bindings file name (the deviation's re-check trigger) |
| SM-CT-RM59 | Retail | A 0:30 race with a best on the board, keeping an eye on *Best by now* and the Checkpoints; then another, `/reload` at about 0:18 and read the cells after the resume | *Current* reads a dash before the first hit, then your damage beside *Best*, moving with the DPS HUD's Damage figure; each checkpoint's *Current* line is a dash until the clock passes it, then holds your damage at that moment and does not change, its short bar appearing with it; no word or difference says ahead or behind; after the reload the checkpoints passed before it (0:08 and 0:15) show a dash for yours while the best's figures stay, and the later ones take yours as the clock passes them |
| SM-CT-RM60 | Retail | Watch the countdown and the time bar through a 1:00 race; then a 0:20 race | The bar starts full and empties to the buzzer; both stay green to 0:30 left, turn from green through yellow to red, and are red from 0:10 left, on the same beat the countdown's tenths reach 10.0; the countdown reads 0:00.0 only at the buzzer, never a tenth before (SM-CT-RM64); the 0:20 race is green, then red from 0:10 left, with no yellow between; *Elapsed* and the pair's elapsed clock stay green |
| SM-CT-RM61 | Retail | The result card attached on the right with the HUD's grip dragged tall; then with *Match the DPS HUD's height* off; then an incomplete race (SM-CT-RM19) | Every heading (*Against your best*, *Top races*, and on the other screens *Best to beat*, *Best by now*, *Checkpoints*) is in the DPS HUD's gold section font; the two tables' columns line up on one grid; in the tall window the rows and the gaps over the headings grow, up to a cap, the buttons staying at the bottom; with the table shown no *vs best* chip repeats it (a *New best* chip still shows); the incomplete race's time in combat shows on its *Time* chip |
| SM-CT-RM62 | Retail | Near the Golem with both windows up: close the Race window with its close mark; press *Toggle DPS HUD* twice (or `/ct hud toggle` twice); walk away, wait for both to close, press the key again; then `/ct hud show` near the dummy with the HUD shut | Near the dummy the second press opens the HUD and the Race window together, even though you closed the Race window earlier in the session; the Race window then closes with the session when you walk away. Away from a dummy the key opens the HUD alone; `/ct hud show` opens the HUD alone even near the dummy. With both auto-show rows off (*Show the Race window near a training dummy* and *Show the DPS HUD near a training dummy*), or Race mode off, the key opens the HUD alone |
| SM-CT-RM63 | Retail | Fight the Golem without a race and let the HUD show its fight-over card; then press *Arm Race*; then arm in the middle of a fight (it refuses in combat) | On the arm the card goes and the HUD shows its look before any fight (the clock at zero, no figures), ready for the race; a fight still live on the HUD is never dropped |
| SM-CT-RM64 | Retail | A 0:30 race with *Center-screen countdown* on, eyes on the Race window's countdown, the DPS HUD's clock and the center numbers at 0:01.0 left and at the buzzer; then with *Race clock* Elapsed and time left | At 0:01.0 left the Race window reads 0:01.0, the HUD's clock 0:29.0 and the center number 1 pops on that tenth; the countdown reads 0:00.0 only at the buzzer, with the HUD at 0:30.0 and the center 1 gone; with the pair the two clocks always add up to 0:30.0 |
| SM-CT-RM65 | Retail | A 0:30 race with a best on the board: keep casting past the buzzer so Stop! shows, then hold combat for the waiting screen; then the same on a fresh board; then shrink the window with the grip (SM-CT-RM66) | Stop! and waiting show the *Checkpoints* under their own figures, all four filled: 0:30's taken at the buzzer, with its *Current* and bar; on a fresh board there are none; in a window too short for them they are left out and the rest is unclipped |
| SM-CT-RM66 | Retail | Unlock the frames (`/ct unlock`): attached right with *Match the DPS HUD's height* on, drag the Race window's grip; then detached, then attached Top; drag it as small as it goes, then large, on each screen (idle, running, Stop!, waiting, result card); `/reload`; then lock | Matched it drags the width only (the height stays the HUD's); detached or on Top it drags width and height; it stops at 260 wide and at the height the content needs, and at 600 by 1000; every body stretches to the size, the buttons pinned to the bottom, the running screen's gaps growing and shrinking, with nothing clipped, two lines of chips included; the size holds after the reload; locked, the grip is gone; Race mode → Race window → Defaults puts the size back |
| SM-CT-RM67 | Both | Read the header controls of the DPS HUD (with the Race flag on Retail), the Race window (Retail) and the Results window | Every mark is the same size, its long side about 12 pixels, and centered in its button: the flag, the chart, the gear, the lock, the attach mark and the close no larger or smaller than each other |
| SM-CT-RM68 | Both | An ordinary fight on a dummy at each DPS HUD → Behavior → Refresh → *HUD refresh rate* (4, 5, 10, 20 a second); change it mid-fight; then `/ct perf` through a fight at 20; then leave combat and watch the HUD in the settle | Every live part steps together at the rate picked: the clock, Damage and DPS, the pace bar, the damage chart and the spell rows; the footer reads *live · 4 Hz*, *live · 5 Hz*, *live · 10 Hz* or *live · 20 Hz* to match; a change mid-fight takes effect at once, without a reload; the perf report has its `hud` line and no `hudClock` line; in the settle the figures hold while the clock runs on until the card |
| SM-CT-RM69 | Retail | A 0:30 race with a best on the board at *HUD refresh rate* 4, then 20, eyes on the Race window's *Current*, its checkpoints and the DPS HUD's Damage figure; change the rate mid-race; look for a *Race clock refresh rate* row on the Race mode page | The Race window's countdown, time bar, *Current* and its mini bar move at the rate picked, on the same beat as the HUD's clock and Damage figure, *Current* equal to the HUD's Damage (on a class with no pet); each checkpoint takes the figure the HUD showed on the beat the clock passed it; a change mid-race takes effect at once on both windows; the Race mode page has no refresh row of its own |
| SM-CT-RM70 | Retail | A 0:30 race with a best on the board, first as a class with no pet, then as a Retail pet class (a Hunter or a Warlock) with a best raced on that class; then Pace bar range on the DPS HUD's Behavior tab at its least and most | *Best by now* has a thin bar over its box with a middle tick, filling green past the tick or red short of it in step with the DPS HUD's pace bar; each checkpoint's short bar (no track) appears as the clock passes it and holds; with the pet class the bars follow your own damage against the best's own figure (the pet left out of both), and agree with the HUD's pace; the range row narrows or widens their swing as it does the HUD's |
| SM-CT-RM71 | Retail | Read the running screen and the Stop! screen of a race with a best | *Best* figures in blue, *Current* figures in white, the labels *Best*, *Current* and each checkpoint's time in dim gold (the time a size larger than the figures); a passed checkpoint's best figure dims and stays blue; the Checkpoints note reads *best · current*; *Best to beat*'s *Damage* and *DPS* labels in the same dim gold |
| SM-CT-RM72 | Retail | Near the Golem with both windows open by auto-show and *Fade after the fight* at its default 8: fight the dummy a few seconds without a race and wait half a minute beside it; then walk away | Neither window fades or closes while you stand near the dummy (the dummy holds the HUD up, owner 2026-11-13); walking away closes both together a few seconds later, the Race window never left alone on screen. With *Show fight-over card* off (DPS HUD → Behavior) the fight's end closes neither while near the dummy, and walking away closes both together |
| SM-CT-RM73 | Retail | Far from any dummy with the DPS HUD shut: press *Toggle Race window* (or `/ct race show`, or `/ct race toggle`); then close the HUD with its close mark; then `/ct hud show`; then press Escape with both up; then `/ct hud show` again | The key opens the DPS HUD and the Race window beside it together (the HUD as your open, so it never fades); the HUD's close mark takes both down; `/ct hud show` brings both back; Escape closes both, and the next `/ct hud show` opens the HUD alone |
| SM-CT-RM74 | Retail | DPS HUD shut, far from any dummy: `/ct race arm`, then `/ct race cancel`; then arm, pull the dummy, close the HUD with its close mark at about 0:10 and let the race run to its result | The arm opens the DPS HUD and the Race window together, and the cancel closes both; closing the HUD mid-race takes the Race window down too, and the result card opens both again with the HUD's fight-over card beside it |
| SM-CT-RM75 | Retail | A 0:30 race on the Golem with *Fade after the fight* 8: race to the result card and wait half a minute; then press *New Race* and wait | Neither window fades while the race is armed, running, waiting or on its result card; after *New Race* neither fades while you stay near the Golem; walking away closes both together |
| SM-CT-RM76 | Retail | Open the Race window by hand (`/ct race show`) beside an auto-opened HUD (a fight's first hit), let the card fade, then `/ct disable` and `/ct enable`; then with the HUD shut by its close mark and the Race window still wanted, turn Race mode off and on | The stand-up brings the Race window back with the DPS HUD opened under it; Race mode back on does the same; the Race window never shows without the HUD |

### The center call-out

Callout plan rows C2, C3 and C5: the race's last seconds and its buzzer on LibKa0s-Callout-1.0, counted
to the race's one endsAt, which the Race window's countdown reads too. Use a 0:30 race on the Golem with
the defaults. SM-CT-RM81 to SM-CT-RM86 check the call-out's own settings: the Race mode page's *Call-out
look*, *Call-out sound* and *Call-out texts* tabs (the library's settings section, every write through
`NS.SetByPath`), the `/ct` reach of their rows, and the longer countdown.

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-RM77 | Retail | Listen to the last ten seconds of a race with the game's sound on and music playing; then race again on the Dialog volume slider at its lowest | The voice is the female pack, clear and unclipped, each word starting with its number and done before the next; it is loud enough over the game at the default Master channel, and none of it is cut off at the buzzer, where STOP follows; the voice ignores the Dialog slider (it plays on Master) |
| SM-CT-RM78 | Retail | Watch the Race window's countdown and the center number through the last ten seconds, first at DPS HUD → Behavior → *HUD refresh rate* 20, then at 4 | At both rates each center number pops in the same frame the countdown's whole second changes (0:05.0 beside 5), even at 4 a second, where the countdown otherwise steps a quarter second at a time; the last tenth reads 0:00.1 beside 1, and 1 goes as 0:00.0 is drawn |
| SM-CT-RM79 | Retail | `/reload` at about 0:04 left, still attacking; then a race where you `/reload` at about 0:15 left | After the first reload the center shows the number of the moment at once and says it, then counts on, each number said once, and STOP at the buzzer; after the second nothing shows until 0:10 left, then the countdown runs as usual |
| SM-CT-RM80 | Retail | `/ct disable` at about 0:05 left; `/ct enable` at about 0:03 left; then a race where you `/ct race cancel` at 0:05 left, and one where you leave combat at 0:05 left | Disabled, the number goes at once and nothing more is said; enabled with time left, the number of the moment shows and is said, and the count runs on to STOP; the cancel and the early combat end take the number down with no STOP |
| SM-CT-RM81 | Retail | `/ct config` → Race mode → *Call-out sound*: *Voice* female, then male, then *Game TTS*, then off, pressing *Test countdown* after each | Female and male each say five to one and GO in their own voice; Game TTS speaks the same words in the client's installed voice (none installed: silence, and the debug console says so once); off is silent, the numbers still shown |
| SM-CT-RM82 | Retail | Race mode → each of *Call-out look*, *Call-out sound* and *Call-out texts*: watch the preview line while changing a row; press *Test countdown*; pick a text in *Text to play* and press *Play* | The preview (5, GO!, STOP in their colors) repaints on every change; *Test countdown* runs 5 to GO! on the real call-out with its voice; *Play* shows and says the text picked; nothing here starts, arms or touches a race |
| SM-CT-RM83 | Retail | Race mode → *Call-out look* → *Unlock to move*: drag the call-out to the top left; lock; `/reload`; then *Reset position* | Unlocked, a READY sample shows with a drag strip, and it drags; locked, the strip goes and the mouse passes through the call-out again; the place holds after the reload and the next race counts there; Reset position puts it back above the center |
| SM-CT-RM84 | Retail | Race mode → *Call-out look*: each *Font* (Oxanium, Bebas Neue, Russo One, the skin's font, the game's default, a LibSharedMedia face; after a full client restart if the faces are new), *Size* at 32 and 200, each *Outline*, *Shadow* off and on with its offsets, each *Glow*, each *Animation* (Slam, Pulse, Glow, Blink, Shake, None) and *Hold*, with *Test countdown* after each | Each choice shows on the next call-out and in the preview; at 200 the numbers stay on screen and are never clipped; the shadow offsets move the shadow and are grayed with it off; each animation plays as named and None just shows the number; a longer hold keeps STOP up longer |
| SM-CT-RM85 | Retail | `/ct set callout.size 150`, `/ct get callout.size`, `/ct set callout.texts.STOP HALT`, then press *Test countdown*, then pick STOP in *Text to play* and press *Play*; `/ct reset callout.size`; then on *Call-out texts* change a color and press the page's *Defaults*; then `/ct list` | Each `/ct set` prints its `[Set]` line and the tab on screen repaints; the next call-out draws at 150 and *Play* (or a race's buzzer) shows HALT; `reset` puts 96 back; *Defaults* restores every Race mode row, the call-out's size, colors and texts with them; `/ct list` names the `callout.` rows; none of it arms or touches a race |
| SM-CT-RM86 | Retail | Race mode → Race → *Center countdown from* 20 (the slider stops at 20); a 0:30 race on the Golem | The numbers start at 20 left, one a second, shown silently down to 6, then five to one are said (the call-out's *Speak numbers from* 5) and STOP at the buzzer; the Race window's countdown agrees with each number |

## In-game verification list

The items the build assumed and the owner confirms, each answered by a row above:

- `/ct probe` on both clients, in combat with a pet: SM-CT-P1 to SM-CT-P6; on WoW Forever, whether the
  meter's values and the pet's rows are secret in combat (the live Pet figure): SM-CT-P8, SM-CT-H15.
- The pet source split, and that the player's source excludes the pet: SM-CT-P4, SM-CT-F12,
  SM-CT-F13.
- The pace bar's red shortfall anchored to its fill: SM-CT-P5, SM-CT-H2.
- Feign Death mid-boss: SM-CT-F3, SM-CT-F5.
- Unit-frame anchors with ElvUI, Shadowed Unit Frames and Blizzard's frames: SM-CT-N8, SM-CT-N9.
- WoW Forever in-combat secrecy (meter values, spell IDs, castGUIDs, the pet's GUID): SM-CT-P6,
  SM-CT-F6, SM-CT-F12.
- The meter's session order at `ENCOUNTER_START`: SM-CT-F4.
- Channel ticks: SM-CT-N3. The delve tier read: SM-CT-F15.
- The standalone-windows resize check: SM-CT-R2.
- Whether the client's number formatters truncate a fraction, on each client: SM-CT-H10.
- The HUD's look against DPS Race's, live and after the fight: SM-CT-H12.
- The HUD's fixed size, grip, scroll and grow edge: SM-CT-H13.
- The timeline's icons or ticks and the caster colors: SM-CT-T11.
- Training dummies on both clients, the player's own list and the captures: SM-CT-D1 to SM-CT-D7.
- The recording rules (30 s on Retail, 15 s on WoW Forever, scenarios recorded): SM-CT-F2, SM-CT-D8 to
  SM-CT-D12.
- The center call-out (Retail): its voice packs, its numbers against the Race window's countdown, the
  resume and the stand-down: SM-CT-RM77 to SM-CT-RM80; its settings section, the `/ct` reach of its
  rows and the 20 s countdown: SM-CT-RM81 to SM-CT-RM86; the samples' toasts and words in `/ct test race`
  and `/ct sim`: SM-CT-RM87, SM-CT-RM88, SM-CT-M7.
- The one showcase sample set, the same on every character: SM-CT-M6.
- Race mode (Retail): SM-CT-RM1 to SM-CT-RM88, with SM-CT-F20 (the reload cases), SM-CT-R25 (the race
  clock on the chart and the Timeline) and SM-CT-S9 to SM-CT-S11 (the page, the verb, its absence on
  WoW Forever).
- The race's first-hit clock, the shared session and the Feign Death split: SM-CT-RM6, SM-CT-RM20,
  SM-CT-RM26.
- That WoW Forever reads `Bindings.xml` and never lists the Retail-only *Toggle Race window* key (the
  per-flavor bindings deviation's re-check): SM-CT-RM58.
