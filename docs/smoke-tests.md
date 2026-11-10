# Smoke tests — Ka0s Combat Trail

The in-game checks no headless run can reach: real rendering, the real damage meter, real cast
events, taint, and the client behaviors the build could not measure ahead of time (spec §10). The
owner runs them; an agent never marks a row passed. Every check names its client: **Retail**,
**Forever** (WoW Forever) or **Both** (run it on each, and record each result).

## Sign-off

| Date | Build | Result |
|---|---|---|
| (not run yet) | 0.1.0, branch `feat/2026-11-10-combat-trail-v0.1.0` | |

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
  in and out of combat, and the meter's secrecy samples. On WoW Forever, also the talent-tree lines
  (SM-CT-P7).
- `/ct probe stop` disarms it early.

Hand the reports back for `midnight-quirks.md`. A "no" on the pet line, or a raise on the pet-fill
line, is a fix on the branch before the merge (spec §12's fallbacks).

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-P1 | Both | `/ct probe` out of combat on a Hunter with a pet | The report prints in the console; every one of the eight functions is present; "combat log: protected, not used" |
| SM-CT-P2 | Both | `/ct probe start`, then ten seconds of combat | One +5 s sample and one sample 2 s after combat, then the probe disarms |
| SM-CT-P3 | Both | `/ct probe` typed while already in combat | It schedules the +5 s sample; a combat takes one in-combat sample however often it is armed |
| SM-CT-P4 | Both | The "pet is separate source" verdict, Hunter and Warlock | "yes" on both classes, with the note that it cannot detect double counting |
| SM-CT-P5 | Both | The "pace pet-fill anchor" line | The SetPoint did not raise |
| SM-CT-P6 | Forever | The cast secrecy counts in combat | Recorded either way: whether cast spell IDs and castGUIDs are secret in combat on WoW Forever |
| SM-CT-P7 | Forever | The talent-tree lines of `/ct probe` (talent tabs, talent spec, talent config, trait tree and groups, talent tree pick), on a character with points spent | Recorded either way: which API answers, each group's fields (which one holds the icon), and a pick that names the tree with the most points |

## 1. Load and identity

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-L1 | Both | Log in with the addon enabled | No Lua error; the first-run skin picker shows once, in test mode |
| SM-CT-L2 | Both | `/ct version` and `/ct help` | The version line; the full command list |
| SM-CT-L3 | Both | Settings → AddOns → Ka0s Combat Trail | The landing page with the logo, then General, Lanes, DPS HUD, History and Profiles |
| SM-CT-L4 | Both | `/ct disable`, then `/ct results` and `/ct enable` | Lanes and HUD hide; the feature verb answers the disabled line; enable brings everything back |
| SM-CT-L5 | Both | Hover and right-click the minimap button | Status tooltip; menu with Enabled, Locked, Test mode, Sim mode, Show window |
| SM-CT-L6 | Both | The three bindings (Toggle DPS HUD, Toggle Results window, Toggle lanes) pressed in game | Each toggles its target; the lanes key brings back exactly the lanes it turned off |
| SM-CT-L7 | Both | The bindings under Options → Keybindings → Ka0s Combat Trail and General → Keybindings | The same keys in both places |
| SM-CT-L8 | Both | The first login on v0.2 over a v0.1 SavedVariables with stored fights | No Lua error; Results is empty, `/ct diag` reads `schema stored=2 code=2 fightFormat=2`; the hidden items and the minimap button are kept |

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
| SM-CT-F2 | Both | A 15 s fight | Not saved, the card says too short |
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

## 4. The DPS HUD

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-H1 | Both | A fight with a pet | Clock, target line, Damage with the Pet figure, DPS, pace bar, chart, spell rows with the paw |
| SM-CT-H2 | Both | The pace bar's pet fill anchored to the player fill (`SetClipsChildren`) | The pet fill starts where the player fill ends; else the fallback to player-only pace |
| SM-CT-H3 | Both | Hover a title-bar control (`Frame:IsMouseOver()`) and a spell row | Tooltips show; `GameTooltip:SetSpellByID` with a secret ID does not error |
| SM-CT-H4 | Both | `SetMinMaxValues` with a secret max on the spell bars | The bars scale; no error |
| SM-CT-H5 | Both | `IsInInstance()` in combat with Only in instances on | The HUD opens only inside |
| SM-CT-H6 | Both | Beat the best on a board | The card shows New best with the delta, and Saved |
| SM-CT-H7 | Both | The HUD's fade 8 s after combat, held by the mouse, and `/ct hud pin` | It fades, waits while hovered, stays pinned |
| SM-CT-H8 | Both | The test and sim strips under the title bar on both skins, and the body at small HUD heights | The strip sits under the title bar; the body is not clipped |
| SM-CT-H9 | Both | Show the HUD Always with Only in instances on, two fights in the open world | The HUD stays up through and after both fights |
| SM-CT-H10 | Both | `/ct debug on`, a 20 s fight on a dummy, then the over card; out of combat, the formatter probe in `midnight-quirks.md` (each `C_StringUtil` constructor's `FormatNumber(30190.4761904)` and `AbbreviateNumbers(30190.4761904)`) | The DPS tile, Damage and spell amounts never show a long decimal tail; the console names the path ("numbers served by ...") and any constructor passed over; the probe's answers are recorded in `midnight-quirks.md` |
| SM-CT-H11 | Both | A fresh profile (or the swatches reset), a fight with a pet, side by side with DPS Race on the same skin | The spell rows, chart columns and the pace fill are DPS Race's blue at the same opacity; the pet rows and pet pace fill are a darker green with legible white text; the pace line is a pale neutral gray, not light blue; switching the skin leaves the fill colors as they are |
| SM-CT-H12 | Both | A fresh profile, the Ka0s Default skin, a fight with a best (live, then the over card), side by side with DPS Race's running body and result card | Same width (260) and about the same height; "Damage profile" and "Spell breakdown" in the same large gold heading with the same space over them; the pace bar directly under "Damage profile" and over the plot; the clock in the same face and size; spell rows 18 px in a 10 pt face; nothing overlaps at 236 px, the heading and its right-hand note included |
| SM-CT-H13 | Both | A fresh profile; a fight with more than 5 spells (a pet class too); drag the HUD's bottom-right grip taller and shorter, then lock it; then Layout > Window size Auto-grow with Grow Down and Up, dragging the title bar between fights | Fixed: 5 rows, the window the same height with 2 spells as with 12 and when the pet arrives; the note reads "live order · 1-5 of 12" and the wheel scrolls to 8-12 and stops, with a thin thumb in the right gutter; the grip's release snaps to whole rows and the Spell bars slider shows the new count; no grip while locked or in Auto-grow. Auto-grow: the window grows with the rows up to Spell bars, then scrolls; Down keeps the top edge in place, Up the bottom, after a /reload too; nothing overlaps the footer, the over card included |

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
| SM-CT-R9 | Retail | View talents | Opens PlayerSpellsFrame; the Results window steps aside and comes back |
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
| SM-CT-T7 | Forever | The gear view's primary stat | A dash, by design |
| SM-CT-T8 | Both | The Never show menu in the Usage edit | The item leaves the list and joins History → Usage |
| SM-CT-T9 | Both | Fight twice in the same gear, swap a full equipment set (the Equipment Manager), fight again, `/reload`, fight again, then `/ct diag` | `gearSets=2`, not one per fight or per slot; the gear view and Compare's *Gear changed* show the swap; nothing new after the reload |

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

## 8. Test mode and the sim

| ID | Client | Check | Expect |
|---|---|---|---|
| SM-CT-M1 | Both | `/ct test` | Sample casts loop on the lanes, the HUD holds a sample fight, the Results window shows the sample history, each under its strip |
| SM-CT-M2 | Both | Enter combat in test mode | Test mode ends; nothing was saved |
| SM-CT-M3 | Both | `/ct sim newbest`, then `short` and `lost` | The fight plays in real time; the card says New best, then Not saved |
| SM-CT-M4 | Both | `/ct sim` step window | Anchored beside the HUD |
| SM-CT-M5 | Forever | The WoW Forever mock spell and item IDs | Every sample icon draws |

## In-game verification list

The items the build assumed and the owner confirms, each answered by a row above:

- `/ct probe` on both clients, in combat with a pet: SM-CT-P1 to SM-CT-P6.
- The pet source split, and that the player's source excludes the pet: SM-CT-P4, SM-CT-F12,
  SM-CT-F13.
- The pace bar's pet fill: SM-CT-P5, SM-CT-H2.
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
