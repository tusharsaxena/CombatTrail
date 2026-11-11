# Schema — Ka0s Combat Trail

What the addon persists (documentation-§3, Tier 1; savedvariables). Two SavedVariables globals, both
declared in `CombatTrail.toc`: `CombatTrailDB` (AceDB, everything below) and `CombatTrailPerfDB`
(LibKa0s-Perf's capture record, written only by `/ct perf`).

Every default is written once, in `defaults/Profile.lua`. The tables below name each key and its
default; the file's comments say what each value means.

## The settings registry (architecture-§5)

- **Storage:** the profile tree under `CombatTrailDB.profiles[<name>]`, and three global rows
  (`global.usage.hidden`, the minimap button's `global.minimap.hide`, read through its inverted
  `general.minimap.shown` row).
- **The registry:** `NS.Schema`, the one array of schema rows. **Its one writer** is
  `NS.RegisterSchemaRows` (settings/Schema.lua), called at **file scope** by each page file in
  `settings/` (General, Lanes, Hud, History) as the TOC loads them, so the load pass is the TOC's own
  settings pass. `NS.SchemaForPage` filters it per page.
- **The one write seam:** `NS.SetByPath(path, value)` (settings/Schema.lua). The pages, the CLI
  (`/ct set`), the verbs (`enable`, `lock`, `lane`, `ignore`) and the launcher all write through it,
  and it sends `SETTINGS_CHANGED`. Reads go through `NS.GetSetting(path)`.

## The profile tree

| Key | Default | Page |
|---|---|---|
| `general.enabled` | `true` | General → Master controls |
| `general.locked` | `false` | General → Master controls |
| `general.hudInCombat` | `true` | General → Master controls |
| `general.fontScale` | `1` | General → Look and skin |
| `lanes.player.*`, `lanes.pet.*` | one block per lane, `lane()` in `defaults/Profile.lua` | Lanes (all seven tabs) |
| `lanes.<k>.anchor` | `{ mode, point, relPoint, x, y, target, gap, frameName }`: the Player lane free at `CENTER` 0, -200, the Pet lane docked under it | Lanes → Size and position |
| `lanes.<k>.visibility` | `{ show = "always", hideAfter = 5, where, hideMounted, hideVehicle, hidePetBattle, hideResting, alphaCombat, alphaOOC }`; `where` has no `delve` or `arena` key, and there is no `hideVehicle` or `hidePetBattle`, on WoW Forever | Lanes → Visibility |
| `lanes.<k>.ignore` | `{ [spellID] = true }` from the client's seed; a removed seed is stored as `false` | Lanes → Ignored spells |
| `lanes.pet.link` | `false`; on, the Pet lane reads every look and visibility key from the Player lane's (`LaneRender.Config`), keeping `enabled`, `anchor`, `strata`, `levelOffset`, `labelText` and `ignore` (`LaneRender.LINK_OWN`); the Player lane has no such key | Lanes → General (Pet lane) |
| `hud.show`, `fadeAfter`, `holdOnMouse`, `instancesOnly`, `paceAgainst`, `paceRange`, `overCard`, `showSkipReason` | `"auto"`, `8`, `true`, `false`, `"best"`, `1.5`, `true`, `true` | DPS HUD → Behavior |
| `hud.width`, `hud.scale`, `hud.layout.*` | `260` (DPS Race's, also the slider's floor, `Hud.MIN_WIDTH`; `Hud.MAX_WIDTH` 600), `1`, every part `true` | DPS HUD → Layout |
| `hud.sizeMode`, `bars`, `grow` | `"fixed"` (or `"auto"`), `5` (`Hud.MIN_BARS` 1 to `Hud.MAX_BARS` 15), `"down"` (or `"up"`, read in auto only). Fixed: the height is `Hud.FixedHeight()`, the chrome plus `HudStates.FixedStack(layout, bars, paceable)`, and the grip's release writes `hud.width` and `hud.bars`. Auto: the stack's height with up to `bars` rows. Both scroll past `bars` (v0.2 Task B3; `hud.spells.rows` retired, no migration: AceDB stores only differences) | DPS HUD → Layout |
| `hud.clock.*`, `hud.figures.*` | font blocks and the boxes' colors; the clock follows the skin's HUD face (`fontFromSkin = true`) at `fontSize = 26`, drawn at DPS Race's single-clock 40 (`HudStates.ClockSize`, × 40/26), flags `""` | DPS HUD → Clock and figures |
| `hud.chart.*` | `height = 80`, `columns = 48`, bar, colors (`barColor` = `PALETTE.BAR`, `barAlpha` = `PALETTE.BAR_A` 0.9, `bestColor` = `PALETTE.PACE`, the pace line), `cooldowns = true`, `cooldownMin = 29`, `zeroLine = true` | DPS HUD → Damage chart |
| `hud.spells.*` | `rowHeight = 18`, icons, paw, bars (`barColor` = `PALETTE.BAR`, `barAlpha` = `PALETTE.BAR_A` 0.9, `petColor` = `PALETTE.PET` at `BAR_A`), font (`fontSize = 10`, `fontShadow = true`), the bars' border (`borderShow = false`, `borderStyle = "Solid"`, `borderSize = 1`, `borderColor` black, `useClassColorBorder`, `borderStyleFromSkin = false`, `borderColorFromSkin = false`; drawn round the bar alone, on the HUD and in the fight detail) | DPS HUD → Spell rows |
| `hud.window.*` | title bar, colors, footer, `strata = "MEDIUM"`, `alpha = 1` | DPS HUD → Window |
| `hud.position` | `{ point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -60, y = -160 }` | DPS HUD → Window, and the title bar's drag (named state, below) |
| `history.minLength`, `bossesOnly`, `content.*` | `30` on Retail and `15` on WoW Forever, `false`, every kind on, `scenario` too; no `mplus`, `delve` or `arena` key on WoW Forever | History → Recording filters |
| `history.days`, `keepBests`, `maxFights` | `7`, `true`, `500` | History → History |
| `results.scale`, `rowHeight`, `shareTalents`, `closeInCombat` | `1`, `18`, `true`, `true` | History → Results window |
| `results.timelineMarks` | `"icon"` | History → Results window (*Ability timeline*); also the timeline's *Icons* and *Ticks* words on its *By ability* heading line, through `NS.SetByPath`. How By ability draws a cast: its ability's icon or a thin tick (`"tick"`); an open timeline redraws, its zoom kept |
| `results.view` | the saved filters, grouping and sort (`group = "datechar"`: by date and character, `days = 7`), and the race filters (Race mode plan D1, read on Retail only): `kind = "all"` (`"fights"`, `"races"`), and under `"races"` `length = "all"`, `dummyKind = "all"`, `hideFlagged = false`, `includeIncomplete = true`, `onlyBest = false` | (named state, below) |
| `results.window` | `{ point, relPoint, x, y, height = 520, view = "collapsed" }`; no `width` ships: with none stored the list opens at its least width, `Results.MIN_WIDTH` (the filter bar's or the table's, whichever is wider), and a stored width below it is held to it | (named state, below) |
| `results.columns` | `{}`; a dragged column's width, `{ character = px }` (Character ships at 104, held to 70–240) | (named state, below) |
| `results.collapsedSections` | `{}`; the fight detail's folded sections, `{ [section] = true }` over `chart`, `timing`, `spells`, `loadout`, `usage`, `targets`, `flags` and `note` (`NS.ResultsDetail.SECTIONS`; `timing` and `flags` a race's), open stored as nothing | (named state, below) |
| `dummies.custom` | `""`; the player's own training dummies (modules/Dummies.lua, both clients): `id:category` marks a creature as a dummy (`single`, `cleave`, `dungeoneer`, `boss` or `pvp`; one added without a category is `single`), `-id` switches a built-in off, ascending and comma-separated (`"243300:cleave,-243205"`); written whole through `NS.SetByPath`, so `/ct get`, `set` and `reset` reach it | History → Training dummies (drawn as Add your target, a list with add and remove, and a checkbox per built-in) |
| `race.defaultLength`, `race.grace`, `race.restartGap`, `race.hintDelay` | `60`, `1.0`, `6`, `15` (DPS Race's): the length a race arms at until one is picked (s), the grace after the buzzer before a cast start is late (s), the quiet after the buzzer before damage counts as restarted (s), both frozen into each race as it arms, and the seconds in combat after the buzzer before the Race window's drop-combat hint (modules/Race.lua, Race mode plan Task B1); on both clients, the rows on Retail only | Race mode → Race (Retail) |
| `race.lateIgnore` | `"66,1856,5384,8690,58984,110959"` (Invisibility, Vanish, Feign Death, Hearthstone, Shadowmeld, Greater Invisibility): the late-cast ignore list, spell IDs ascending and comma-separated, 8690 standing for every hearthstone (`defaults/Hearthstones.lua`); read when a race is scored, never frozen, so an edit re-scores every saved race (modules/LateIgnore.lua, both clients; the row on Retail only) | Race mode → Late-cast ignore list (Retail; drawn as a list with add and remove), and `/ct race ignore` |
| `race.enabled`, `autoShow`, `autoArm`, `clock`, `countdownCue`, `centerCountdown`, `finalCountdown`, `buzzer` | `true`, `true`, `false`, `"both"` (`"left"`, `"elapsed"`), `true`, `true`, `10`, `true` (DPS Race's; Task B3): the Race mode switch (`NS.RaceMode.On()`: off stops new races only), auto-show and auto-arm near a training dummy (modules/AutoArm.lua), the race clock's mode, the countdown (modules/Countdown.lua: its cue, its center numbers and the second they start at, 3-10) and the buzzer's raid warning. Retail only: ABSENT on WoW Forever (clients-§4) | Race mode → Race (Retail) |
| `raceWindow.attached`, `raceWindow.side` | `true`, `"RIGHT"` (`"LEFT"`, `"TOP"`, `"BOTTOM"`): the Race window attached beside the DPS HUD, and on which side (modules/RaceWindow.lua). Retail only: ABSENT on WoW Forever | Race mode → Race window (Retail) |
| `raceWindow.position` | `{ point = "CENTER", relPoint = "CENTER", x = 0, y = 160 }`: the detached Race window's place, written by its title bar's drag (and by Detach, where it stood) and put back by Master controls' Reset position. Retail only: ABSENT on WoW Forever | none (the window's drag) |
| `toast.fights`, `toast.races` | `true`, `true`: the new-best toast for a stored fight's new best on its board (both clients) and for a race's (modules/BestToast.lua, race plan Task C2). `toast.races` is Retail only: ABSENT on WoW Forever | History → New-best toast |
| `toast.sound`, `toast.soundKey`, `toast.duration`, `toast.scale` | `true`, `"Default"` (the toast shell's alert; any other value a LibSharedMedia sound key, one it does not know plays Default), `10` (s, 3-30), `1.0` (0.5-2.0), DPS Race's | History → New-best toast |
| `toast.point` | none: where *Test toast*'s sample was dragged to, `{ point, relativePoint, x, y }` in UIParent's units; cleared by Master controls' Reset position | none (the sample's drag) |
| `skin.*` | `source = "ka0s"`, `skin = NS.DEFAULT_SKIN` (per client), scope, font, texture, `outline = "hud"`, `pickerSeen = false` | General → Look and skin |

The debug flag, test mode and the sim are session-only (`NS.State`), never stored.

The bar colors come from one place, `NS.Constants.PALETTE` in `core/Constants.lua`. It is DPS Race's
`BAR_BLUE` family: `BAR` {0.36, 0.37, 0.84} and `BAR_A` 0.9 for the player's bars and chart columns,
`PET` {0.24, 0.60, 0.30} for the pet's, `PLAYER_LINE` and `PET_LINE` for thin lines, `THIS_BAR` /
`BEST_BAR` and `THIS_TEXT` / `BEST_TEXT` for the compare's two sides, and `PACE` {0.9, 0.9, 0.92, 0.4}
for the pace line. `defaults/Profile.lua` copies each entry into its block as a table of its own. AceDB
stores only what differs from the defaults, so a profile that never set a swatch draws the palette
and one that did keeps its own. No migration step is needed. No skin overrides a fill color. The
Results table's Damage and DPS bars read the palette directly (`Tbl.BAR_COLOR` = `BAR` at
`Tbl.BAR_ALPHA` = `BAR_A`, v0.2 Task C2); they have no setting, and the class color stays on the
name and the icons. The ability timeline reads it too (v0.2 Task D1): its fights' colors
`Timeline.THIS` / `OTHER` are copies of `THIS_TEXT` / `BEST_TEXT` (no longer the skin's gold read at
load), a tick is its caster's `PLAYER_LINE` or `PET_LINE` at 0.95, and every cast icon sits on a 1 px
edge in that color in place of the skin's icon outline (a meaning color, skinning-§9).

## The global tree

| Key | Holds |
|---|---|
| `schemaVersion` | The settings migration stamp; `0` in the defaults so AceDB never strips it |
| `fights` | The fight store, `{ [id] = record }` |
| `fightOrder` | The store's ids, newest first |
| `loadouts` | Talent loadouts interned once, keyed by hash; a record holds the key |
| `gearSets` | Equipment sets interned once, `{ [key] = { [slot] = trimmed item string } }`, keyed by the hash of the canonical gear (`slot=item` in slot order); a record holds the key (`gearSet`). Created on first use |
| `usage.hidden` | The item IDs the Usage list never shows, comma-separated |
| `dummies.captures` | What the game said about each creature `/ct dummy` captured, `{ [creatureID] = { name, level, classification, health, creatureType, pvp, faction, reaction, first, last, count, addon, build, places = { [mapID] = { zone, subzone, x, y, date } } } }` (modules/Dummies.lua); a sealed field is absent |
| `minimap` | LibDBIcon's own table, handed to `:Register` |
| `skinNotice` | The account's one-time skin notice, written by LibKa0s-Options |

## Named non-setting state (architecture-§5)

| State | Storage key | Owner | Writers |
|---|---|---|---|
| A lane's dragged place | `lanes.<k>.anchor.x` / `.y` (and `point`) | modules/LaneAnchor.lua | `dragStop` (the edit overlay's drag) through `write`; `NS.Lanes.ResetPosition` (Master controls' Reset position) |
| The HUD's place | `hud.position` | modules/Hud.lua | `normalizeAnchor` (the title bar's drag and the grip's release, a change of `hud.sizeMode` or `hud.grow`, and a Refresh that finds the stored point off that edge: TOPLEFT, or BOTTOMLEFT for an auto window growing up, on UIParent's BOTTOMLEFT), else `savePosition`; `Hud.ResetPosition` |
| The Results window's place, size and fold | `results.window` | modules/Results.lua | `savePosition` (drag, the grip's release, the fold arrow through `Results.SetView`); `Results.ResetPosition` |
| The Results columns' dragged widths | `results.columns` | modules/Results_Fights.lua | `Fights.StoreColumnWidth` (a header edge's release, through the table's `onColumnResize`); `Fights.ClearColumnWidths` (`Results.ResetPosition`) |
| The detail's folded sections | `results.collapsedSections` | modules/Results_Detail.lua | `Detail.SetCollapsed` (a heading's arrow or text, through `Pane:ToggleSection`; Add Note opens the Note); kept by `Results.ResetPosition` |
| The saved Results view | `results.view` | modules/Results_Fights.lua | `writeView` (the Save button; Reset writes nil, so the shipped view applies) |
| The fight store | `global.fights`, `global.fightOrder` | modules/Recorder.lua | `Recorder.Save`, `Recorder.Delete`, `Recorder.SetNote`; `Retention.Purge` (modules/Retention.lua) |
| Interned loadouts | `global.loadouts` | modules/Loadouts.lua | `Loadouts.Store`; `Loadouts.Sweep`, called by the purge |
| Equipment sets | `global.gearSets` | modules/Loadouts.lua | `Loadouts.StoreGear`, through `Loadouts.Recon` (PLAYER_ENTERING_WORLD, the debounced PLAYER_EQUIPMENT_CHANGED and UNIT_INVENTORY_CHANGED, the stand-up, and the pull when no set is known); `Loadouts.Sweep`, called by the purge and a delete, keeping the current set and the live fight's |
| The Usage hidden list | `global.usage.hidden` | modules/Usage.lua | `Usage.Hide`, `Usage.Unhide` and the History page's Usage tab, all through `NS.SetByPath` |
| The last race length armed | `race.lastLength` (no default) | modules/Race.lua | `Race.Arm` (a successful arm); `Race.DefaultLength` reads it before `race.defaultLength` |
| A race under way, per character | `global.pendingRaces` (`{ [Bests.CharKey] = slot }`) | modules/Race.lua | written at a race's first hit (and when it follows a split), its `lastDamage` and sessions at each damage update; cleared at its result, a cancel, or a `Race.Resume` that finds it stale. The slot is plain: the race part itself, `startedAt`, `date`, `lastDamage`, `sessions`, `boundBy`, `sharedSession`, `startT`, `snapshot`, `stats`, `talents`, `gearSet`, `baseline` |
| The training-dummy captures | `global.dummies.captures` | modules/Dummies.lua | `Dummies.Capture` (`/ct dummy add` and `capture`, the Training dummies tab's Add your target) |
| The skin picker seen | `skin.pickerSeen`, `global.skinNotice` | core/SkinSetup.lua (LibKa0s-Options writes the notice) | the picker's close |
| The minimap button | `global.minimap` | LibDBIcon-1.0 (vendored) | its own drag; the `general.minimap.shown` row |
| The perf record | `CombatTrailPerfDB` | LibKa0s-Perf-1.0 (vendored) | `/ct perf` |

## The fight record (CT_SCHEMA 4)

Built by `Recorder.Build` after combat from plain values only; anything that came back secret is left
absent. `Recorder.CT_SCHEMA` is the record's own format version, separate from the settings stamp; a
record with a higher `schema` than this build knows is never listed.

| Field | Holds |
|---|---|
| `schema`, `id`, `t`, `duration` | format version, `time()-NNNN` id, combat entry (epoch), seconds |
| `who` | name, realm, class, specID, specName, ilvl, petName, petFamily, client. On WoW Forever also `trees` (each talent tree's points, plain) and `specIcon`; there `specID` is `"tree:<class>:<index>"`, the predominant tree (v0.2 plan A4), with its name and icon, and absent when no tree has points |
| `identity`, `boardKey` | the encounter or primary target (`targetName`, `targetCreatureID`, `targetLevel`: plain or absent, -1 a skull), where (instance, difficulty, tiers, `zone`, `subzone`), the content kind, and the key bests group by: `e:<encounter>:<difficulty>` for an encounter, `c:<creature>:<difficulty>` for a world boss, `t:<npcID>:<level or ?>:<name>:<difficulty>` for any other target (the level is the combat-entry snapshot's, so the HUD's live pace key matches), `i:<instance>:<difficulty>` for PvP against players, `n:<name>:<difficulty>` for a named target with no NPC ID; then `:k`/`:d`/`:p` for the keystone, delve tier or PvP bracket. An unknown target has none. |
| `damage`, `dps`, `meterDps` | `{ merged, player, pet }`, merged divided by duration, the meter's own figure |
| `spells` | one packed string (CastCodec); `Recorder.Spells` unpacks it to `{ spellID, total, isPet }` |
| `casts`, `cooldowns` | the packed cast list, and `{ [spellID] = ms }` for the timeline |
| `gearSet`, `stats`, `loadout`, `usage` | the key of the equipment set current at combat start (`global.gearSets`; read through `Loadouts.GearOf`, which also takes a sample fight's inline `gear`), the stats (per fight: they move with buffs), the loadout key, what was used |
| `targets` | CT_SCHEMA 3, optional: `{ { name, total }, ... }`, the enemies your damage reached (the meter's EnemyDamageTaken view, read after combat), enemies of one name merged, highest first, at most `Recorder.TARGETS_MAX` (10). Absent on a CT_SCHEMA 2 record or when the meter answered none; the fight detail's Targets section is then not drawn |
| `race` | CT_SCHEMA 4, optional: a race's part (Race mode; `modules/RaceRecord.lua`, `RaceRecord.Plain` keeps these fields only, each only when plain): `length` (the race length picked, s), `kind` (the dummy's category when saved; the boards read the Training dummies list now and fall back to it), `status` (`complete` or `incomplete`: a lost or canceled race is taken off its fight, which is then judged as a plain fight), `flags` (`lateCasts` `{ { t, spellID } }`, `restartedAt`, `reloaded`, `died`, `sessionFromList`: the race's fight bound its session only on a tick's look at the meter's list, ruling X14, `sharedSession`: the pull carried on a meter session alive at the arm, ruling X3), `score` (the session's merged total; for a shared session, less what it held at the arm, as is the record's own damage), `dps` (score over `length`, over `endedAt` when incomplete), `tail`, `endedAt`, `combatEnd`, `grace`, `restartGap`. A race is saved without the recording filters; the record's own `duration` and `dps` stay the fight's, and `RaceRecord.Dps` is the race DPS wherever a race is shown. Absent on a fight and on every older record |
| `note`, `client`, `build`, `version`, `status` | the player's note (`Recorder.ClampNote`: a control character to a space, `\|` to `/`, trimmed, at most 200 UTF-8 characters), `retail`/`forever`, the client build, the addon version, `"final"` |

A five-minute raid fight packs under 6 KB (pinned by `tests/test_record.lua`), so 500 fights stay
near 3 MB. The History page's History tab shows the count and an estimate (`Retention.EstimateBytes`).

## Migrations

`core/Database.lua` runs `STEPS` in order against `global.schemaVersion`, moving the stamp only past
a step that returned; a step marked `perProfile` runs once for every stored profile. The target is
`NS.SCHEMA_VERSION`.

| Step | From → to | Does |
|---|---|---|
| 1 | 0 → 1 | Nothing: the first release's shape |
| 2 | 1 → 2 | Empties the fight store, its order, the loadouts and the gear sets (`global.fights`, `fightOrder`, `loadouts`, `gearSets`): the v0.2 record shape, CT_SCHEMA 2. Every other account-wide key is kept |

A change to the fight record bumps `Recorder.CT_SCHEMA` and reads the older shape where it is read,
never by rewriting stored fights: CT_SCHEMA 3 → 4 (the optional `race`) has no step, and an older record
loads as it was, a fight. The one exception is step 2: the addon was unpublished, so the v0.1
store was emptied once instead of migrated (v0.2 plan, decision D1).
