# Schema — Ka0s Combat Trail

What the addon persists (documentation-§3, Tier 1; savedvariables). Two SavedVariables globals, both
declared in `CombatTrail.toc`: `CombatTrailDB` (AceDB, everything below) and `CombatTrailPerfDB`
(LibKa0s-Perf's capture record, written only by `/ct perf`).

Every default is written once, in `defaults/Profile.lua`. The tables below name each key and its
default; the file's comments say what each value means.

## The settings registry (architecture-§5)

- **Storage:** the profile tree under `CombatTrailDB.profiles[<name>]`, and two global keys
  (`global.usage.hidden`, and the minimap button's `global.minimap.hide`, read through its inverted
  `general.minimap.shown` row).
- **The registry:** `NS.Schema`, the one array of schema rows. **Its one writer** is
  `NS.RegisterSchemaRows` (settings/Schema.lua), called at **file scope** by each page file in
  `settings/` (General, Lanes, Hud, History, and Race on Retail only) as the TOC loads them, so the load pass is the TOC's own
  settings pass. `NS.SchemaForPage` filters it per page.
- **The one write seam:** `NS.SetByPath(path, value)` (settings/Schema.lua). The pages, the CLI
  (`/ct set`), the verbs (`enable`, `lock`, `lane`, `lanes`, `ignore`, `dummy`, `race`) and the launcher all write through it,
  and it sends `SETTINGS_CHANGED`. Reads go through `NS.GetSetting(path)`.

## The profile tree

| Key | Default | Page |
|---|---|---|
| `general.enabled` | `true` | General → Master controls |
| `general.locked` | `false`: the DPS HUD's and the windows' lock (`/ct lock`, `/ct unlock`); never the lanes' since step 7 | General → Master controls |
| `general.lanesLocked` | `false`: the lanes' own lock (owner feedback item 15, `/ct lanes lock\|unlock\|toggle`): on, Edit Mode does not show their move boxes. Step 7 carried each profile's `general.locked` across | General → Master controls |
| `general.hudInCombat` | `true` | General → Master controls |
| `general.fontScale` | `1` | General → Look and skin |
| `lanes.player.*`, `lanes.pet.*` | one block per lane, `lane()` in `defaults/Profile.lua` | Lanes (all seven tabs) |
| `lanes.<k>.anchor` | `{ mode, point, relPoint, x, y, target, gap, frameName }`: the Player lane free at `CENTER` 0, -200, the Pet lane docked under it | Lanes → Size and position |
| `lanes.<k>.visibility` | `{ show = "always", hideAfter = 5, where, hideMounted, hideVehicle, hidePetBattle, hideResting, alphaCombat, alphaOOC }`; `where` has no `delve` or `arena` key, and there is no `hideVehicle` or `hidePetBattle`, on WoW Forever | Lanes → Visibility |
| `lanes.<k>.ignore` | `{ [spellID] = true }` from the client's seed; a removed seed is stored as `false` | Lanes → Ignored spells |
| `lanes.pet.link` | `false`; on, the Pet lane reads every look and visibility key from the Player lane's (`LaneRender.Config`), keeping `enabled`, `anchor`, `strata`, `levelOffset`, `labelText` and `ignore` (`LaneRender.LINK_OWN`); the Player lane has no such key | Lanes → General (Pet lane) |
| `hud.show`, `fadeAfter`, `holdOnMouse`, `instancesOnly`, `paceAgainst`, `paceRange`, `overCard`, `showSkipReason` | `"auto"`, `8`, `true`, `false`, `"best"`, `1.5`, `true`, `true` | DPS HUD → Behavior |
| `hud.openOnPull` | `true`: *Open when a fight starts* (the owner's ruling of 2026-11-26, SM-CT-LG22, R4-CT-08): at the pull (FIGHT_STARTED) a closed or hidden HUD opens, an auto open where the show mode lets one (never under `"toggle"`; `general.hudInCombat` and `hud.instancesOnly` apply), even after the player's close in the last fight. The Combat Sequence no longer opens itself; step 11 carries a stored `sequence.drawer.autoOpen = false` here | DPS HUD → Behavior |
| `hud.width`, `hud.scale`, `hud.layout.*` | `260`, the least, `Hud.MIN_WIDTH` (DPS Race's; `Hud.MAX_WIDTH` 600), so a new profile starts narrow (owner feedback round 4, R4-CT-06; 390, feedback item 2, until then: step 10 pins 390 on every stored profile that keeps no width of its own), `1`, every part `true` | DPS HUD → Layout |
| `hud.refreshRate` | `10` (`4`, `5`, `10` or `20`): how many times a second every live part of both windows redraws, in a fight or a race (owner, 2026-11-13): the HUD's own beat (`Hud.SyncBeat`, modules/Hud.lua) outside a race and the race beat (modules/RaceClock.lua) in one, each one meter read and the whole redraw, the Race window's in the same beat. A value off the list falls back to 10 (`Hud.RefreshRate`). On both clients | DPS HUD → Behavior |
| `hud.bars` | `5` (`Hud.MIN_BARS` 3 to `Hud.MAX_BARS` 15; at least 3 since R4-CT-07, a stored 1 or 2 reading 3). The HUD is one window of one static height (owner feedback item 12): `Hud.FixedHeight()`, the chrome plus `HudStates.FixedStack(layout, bars, paceable)` (the status line reserved) plus the docked Combat Sequence's `HudLog.HeightFor(rows)`. The grip's release writes `hud.width` and the rows its height holds: while the Combat Sequence is docked open, both `hud.bars` and `sequence.drawer.rows`, split by `Hud.SplitFor` (modules/Hud_Split.lua, R4-CT-07: from the pair the grip went down on, shrinking the larger side first, the sequence on a tie, and growing the smaller, the spells on a tie, 3/3 to 15/20); with Spell breakdown off, `sequence.drawer.rows` alone; else `hud.bars`. Spells past `bars` scroll (v0.2 Task B3; `hud.spells.rows` retired, no migration: AceDB stores only differences; `hud.sizeMode` and `hud.grow` retired by step 6) | DPS HUD → Layout |
| `hud.clock.*`, `hud.figures.*` | font blocks and the boxes' colors; the clock follows the skin's HUD face (`fontFromSkin = true`) at `fontSize = 26`, drawn at DPS Race's single-clock 40 (`HudStates.ClockSize`, × 40/26), flags `"@skin"` (the skin's Font outline: the HUD fight clock is no race clock, the owner's U-14 of 2026-11-20; `""` until LibKa0s v1.108.0) | DPS HUD → Clock and figures |
| `hud.chart.*` | `height = 80`, `columns = 48`, bar, colors (`barColor` = `PALETTE.BAR`, `barAlpha` = `PALETTE.BAR_A` 0.9, `bestColor` = `PALETTE.PACE`, the pace line, drawn in the skin's `ct.chart.diag` while `bestColorFromSkin = true`), `cooldowns = true`, `cooldownMin = 29`, `zeroLine = true` | DPS HUD → Damage chart |
| `hud.spells.*` | `rowHeight = 18`, icons, paw, bars (`barColor` = `PALETTE.BAR`, `barAlpha` = `PALETTE.BAR_A` 0.9, `petColor` = `PALETTE.PET` at `BAR_A`), font (`fontSize = 10`, `fontShadow = true`), the bars' border (`borderShow = false`, `borderStyle = "Solid"`, `borderSize = 1`, `borderColor` black, `useClassColorBorder`, `borderStyleFromSkin = true`, `borderColorFromSkin = true` (`false` until LibKa0s v1.108.0, R-2): a skin's real bar border style draws, its None keeps Show border off; drawn round the bar alone, on the HUD and in the fight detail) | DPS HUD → Spell rows |
| `hud.window.*` | title bar, colors, footer, `strata = "MEDIUM"`, `alpha = 1` | DPS HUD → Window |
| `hud.position` | `{ point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -60, y = -160 }` | DPS HUD → Window, and the title bar's drag (named state, below) |
| `history.minLength`, `bossesOnly`, `content.*` | `30` on Retail and `15` on WoW Forever, `false`, every kind on, `scenario` too; no `mplus`, `delve` or `arena` key on WoW Forever | History → Recording filters |
| `history.days`, `keepBests`, `maxFights` | `7`, `true`, `500` | History → History |
| `results.scale`, `rowHeight`, `shareTalents`, `closeInCombat` | `1`, `18`, `true`, `true` | History → Results window |
| `results.timelineMarks` | `"icon"` | History → Results window (*Ability timeline*); also the timeline's *Icons* and *Ticks* words on its *By ability* heading line, through `NS.SetByPath`. How By ability draws a cast: its ability's icon or a thin tick (`"tick"`); an open timeline redraws, its zoom kept |
| `results.view` | the saved filters, grouping and sort (`group = "datechar"`: by date and character, `days = 7`), and the race filters (Race mode plan D1, read on Retail only): `kind = "all"` (`"fights"`, `"races"`), and under `"races"` `length = "all"`, `dummyKind = "all"`, `hideFlagged = false`, `includeIncomplete = true`, `onlyBest = false` | (named state, below) |
| `results.insights` | the Insights tab's saved filters (Race mode plan D2): `character = "all"`, `spec = "all"`, `content = "all"`, `days = 0` (all time), and read on Retail only `kind = "all"` (`"fights"`, `"races"`), under `"races"` `length = "all"`, `dummyKind = "all"`, and `cleanOnly = false`, `includeIncomplete = false` (the race checks, offered unless `kind = "fights"`) | (named state, below) |
| `results.window` | `{ point, relPoint, x, y, height = 520, view = "collapsed" }`; no `width` ships: with none stored the list opens at its least width, `Results.MIN_WIDTH` (the filter bar's or the table's, whichever is wider), and a stored width below it is held to it | (named state, below) |
| `results.columns` | `{}`; a dragged column's width, `{ character = px }` (Character ships at 104, held to 70–240) | (named state, below) |
| `results.collapsedSections` | `{}`; the fight detail's folded sections, `{ [section] = true }` over `chart`, `timing`, `spells`, `loadout`, `usage`, `targets`, `sequence`, `flags` and `note` (`NS.ResultsDetail.SECTIONS`; `timing` and `flags` a race's; `sequence` the Combat Sequence section, `log` until step 9 moved it), open stored as nothing | (named state, below) |
| `dummies.custom` | `""`; the player's own training dummies (modules/Dummies.lua, both clients): `id:category` marks a creature as a dummy (`single`, `cleave`, `dungeoneer`, `boss` or `pvp`; one added without a category is `single`), `-id` switches a built-in off, ascending and comma-separated (`"243300:cleave,-243205"`); written whole through `NS.SetByPath`, so `/ct get`, `set` and `reset` reach it | History → Training dummies (drawn as Add your target, a list with add and remove, and a checkbox per built-in) |
| `race.defaultLength`, `race.grace`, `race.restartGap`, `race.hintDelay` | `60`, `1.0`, `6`, `15` (DPS Race's): the length a race arms at until one is picked (s), the grace after the buzzer before a cast start is late (s), the quiet after the buzzer before damage counts as restarted (s), both frozen into each race as it arms, and the seconds in combat after the buzzer before the Race window's drop-combat hint (modules/Race.lua, Race mode plan Task B1); on both clients, the rows on Retail only | Race mode → Race (Retail) |
| `race.lateIgnore` | `"66,1856,5384,8690,58984,110959"` (Invisibility, Vanish, Feign Death, Hearthstone, Shadowmeld, Greater Invisibility): the late-cast ignore list, spell IDs ascending and comma-separated, 8690 standing for every hearthstone (`defaults/Hearthstones.lua`); read when a race is scored, never frozen, so an edit re-scores every saved race (modules/LateIgnore.lua, both clients; the row on Retail only) | Race mode → Late-cast ignore list (Retail; drawn as a list with add and remove), and `/ct race ignore` |
| `race.enabled`, `autoShow`, `autoShowHud`, `autoArm`, `clock`, `centerCountdown`, `finalCountdown`, `buzzer` | `true`, `true`, `true`, `false`, `"left"` (`"both"`, `"elapsed"`), `true`, `10`, `true` (DPS Race's, but for `autoShowHud` and the clock; Task B3 and the race window redesign plan's rulings O2 and O4): the Race mode switch (`NS.RaceMode.On()`: off stops new races only), auto-show near a training dummy, the DPS HUD opening with it (an auto open the dummy session closes again only while no fight is on the HUD and the player has not opened or pinned it since; drawn disabled while `autoShow` is off) and auto-arm on targeting one (modules/AutoArm.lua), the race clock's mode (`"left"`, one countdown, for a new profile; a profile that saved `"both"` keeps it), the countdown (modules/Countdown.lua: the call-out's center numbers and the second they start at, 3-20), and the call-out's STOP at the buzzer. `race.countdownCue` (the old per-second cue sound) is retired with the call-out (callout plan row C2): no migration, AceDB stores only differences and nothing reads it. Retail only: ABSENT on WoW Forever (clients-§4) | Race mode → Race (Retail) |
| `raceWindow.attached`, `raceWindow.side`, `raceWindow.matchHud` | `true`, `"RIGHT"` (`"LEFT"`, `"TOP"`, `"BOTTOM"`), `true`: the Race window attached beside the DPS HUD, flush against it, on which side, and whether on the left or right it takes the HUD's height and follows each HUD resize, never shorter than its own height (modules/RaceWindow.lua, race window redesign plan Task W4); above, below or detached it keeps its own height. Retail only: ABSENT on WoW Forever | Race mode → Race window (Retail) |
| `raceWindow.width`, `raceWindow.height` | `260` (`RW.WIDTH`, the least, to `RW.MAX_WIDTH` 600), `0` (0 to `RW.MAX_HEIGHT` 1000; 0 is the content height `RW.Height()`, and a height under it is held to it): the Race window's size, written by its resize grip on release (shown only while unlocked; matched left or right it writes the width alone). Both skipRender: no drawn row, the Race window tab's Defaults and `/ct set` reach them. Retail only: ABSENT on WoW Forever | none (the window's grip) |
| `raceWindow.position` | `{ point = "CENTER", relPoint = "CENTER", x = 0, y = 160 }`: the detached Race window's place, written by its title bar's drag (and by Detach or unticking `raceWindow.attached`, where it stood) and put back by Master controls' Reset position. Retail only: ABSENT on WoW Forever | none (the window's drag) |
| `callout.*` | The race call-out's look and voice (LibKa0s-Callout-1.0 at 4.5, LibKa0s v1.102.0, its `SchemaRows("callout.", { texts = false })`, the library's docs/api/Callout, The schema rows): `font = "Skin font"` (from LibKa0s v1.108.0, U-1; `"Ka0s Oxanium SemiBold"`, the library's `FONT_DEFAULT`, before it, and Oxanium Bold before v1.102.0), `size = 96` (32-200), `outline = "@skin"` (From skin, from v1.108.0; `"THICKOUTLINE"` before), `shadow = true`, `shadowX = 1`, `shadowY = 1` (positive y is up), `anim = "slam"`, `hold = 1.5` (s); the glow, as AuraMaster's: `glow = true` (a boolean; it was `"off"`, `"soft"` or `"strong"` before schema 3), `glowIntensity = 1` (0.05-1), `glowThickness = 2` (1-6 px), `glowX = 1`, `glowY = 1` (-20 to 20 px), `glowCustom = true` with `glowColor` black (`{ r = 0, g = 0, b = 0, a = 1 }`, the panel's named shape): a black halo at full intensity, 2 px thick, 1 px right and 1 px up, the owner's look (before v1.102.0 it was 35%, 2 px at 0, 0 in each word's kind color; from v1.102.0 to SD-CT-DEF 1 px at 1, -1), `useClassColorGlow = false`, `glowColorFromSkin = false` (the thickness, the Y offset and the glow color's companion are Combat Trail's own defaults over the library's, `NS.CALLOUT_DEFAULTS` in settings/Race.lua: the owner's settings of 2026-11-20, SD-CT-DEF; the companion off is a documented deviation from skinning-§9, and the one-time step onto the skin leaves it where it is); `voice = "male-arena-john"` (the Arena announcer; the other packs `female` (Kathleen), `female-kristin`, `female-cori`, `female-bella`, `male` (Joe), `male-john`, `male-norman`, then `tts`, `off`; a profile that stored a voice keeps it; AceDB stored none equal to the old default `female`, so a profile on Female (Kathleen), chosen or not, now reads Arena John), `channel = "Master"`, `speakFrom = 5` (higher numbers shown, not said), `ttsVoice = false`, `ttsRate = 0`, `ttsVolume = 100`; `colors.<kind>` per kind (`number`, `info`, `go`, `stop`, `warn`, `error`) in the panel's named shape `{ r, g, b, a }`. **No `texts.<KEY>` or `muted.<KEY>`**: the stock words and their mutes are the addon's (owner, 2026-11-14, callout plan row C11), so they have no row, the seam refuses them, and schema 3 dropped any stored. One schema row each, registered by settings/Race.lua and seeded into `profile.callout` from the rows before AceDB:New (never from the library's `DEFAULTS`, whose array colors are the off-route shape). The instance's `db` getter (modules/Countdown.lua) reads the table at every call, so a profile switch is followed, and every write it makes goes through `NS.SetByPath`; `/ct get|set|list|reset` and the page's Defaults reach each row. Two session rows beside them, `callout.play` (`GO`, or `countdown10`) and `callout.unlocked` (`false`), store nothing. Retail only: ABSENT on WoW Forever | Race mode → Callout (Retail; the library's settings section, Look and Sound side tabs) |
| `callout.point` | `{ "CENTER", "CENTER", 0, 180 }` (the instance's default place, `{ point, relativePoint, x, y }` in UIParent's units): where the call-out stands, written by its drag while *Unlock to move* is on and put back by *Reset position*, both through `NS.SetByPath` (the schema's `writeThrough`, settings/Schema.lua). Retail only | none (the call-out's drag; named state, below) |
| `toast.fights`, `toast.races` | `false`, `true`: the new-best toast for a stored fight's new best on its board (both clients) and for a race's (modules/BestToast.lua, race plan Task C2): a new profile toasts a race's new best and not a fight's. `toast.races` is Retail only: ABSENT on WoW Forever | History → New-best toast |
| `toast.sound`, `toast.soundKey`, `toast.duration`, `toast.scale` | `true`, `"Default"` (the toast shell's alert; any other value a LibSharedMedia sound key, one it does not know plays Default), `10` (s, 3-30), `1.0` (0.5-2.0), DPS Race's | History → New-best toast |
| `toast.point` | none: where *Test toast*'s sample was dragged to, `{ point, relativePoint, x, y }` in UIParent's units; cleared by Master controls' Reset position | none (the sample's drag) |
| `sequence.enabled`, `sequence.drawer.shown`, `sequence.home` | `true`, `true` (owner feedback item 1), `"docked"` (`"detached"`): the Combat Sequence captures (modules/CombatLog.lua, CombatTrail #11; off, it registers nothing, no fight saves a sequence and the HUD's Combat Sequence control hides); it is open in its home (the HUD's Combat Sequence control, `/ct sequence` or its alias `/ct log`, the window's close; it never opens itself at a fight's start: `sequence.drawer.autoOpen` went to `hud.openOnPull`, step 11); and it lives in the DPS HUD's drawer or its own window (the drawer's detach mark, the window's dock mark, `/ct sequence detach|dock`). The controls write through these rows (none is on the write-through list since CL-11c2) | Combat Sequence → Combat Sequence |
| `sequence.drawer.chips`, `sequence.drawer.rows` | `false`, `5` (3-20, `HudLog.MIN_ROWS` to `MAX_ROWS`; 10 from owner feedback item 16 until round 4's R4-CT-07, five each with the spell rows; a profile that never stored its rows follows the new default, no step): the docked drawer's filter chips under its heading (the heading's eye writes it; hidden by default and when absent, owner feedback round 4, R4-CT-04), and its rows (the HUD's grip writes them, with `hud.bars`, while the Combat Sequence is docked open); the drawer's sections are part of the HUD's one height (modules/Hud_Log.lua). The drawer has no fold (owner feedback item 14): step 5 drops `log.drawer.collapsed` and `log.drawer.strip` (before step 9 moved `log` to `sequence`) | Combat Sequence → Docked drawer |
| `sequence.window.chips`, `fill`, `rows`, `locked`, `scale`, `alpha` | `false`, `true`, `12` (3-40), `false`, `1` (0.5-2), `1` (0.1-1): the detached window (modules/LogWindow.lua, CL-11b2), a standalone window (owner feedback item 11): its filter chips under the status line (the title bar's eye writes it; hidden by default and when absent, R4-CT-04), its rows filling its height or `rows`, locked (as with `general.locked`), its scale and its opacity. Step 6 drops the retired attached state's `attached`, `side`, `matchHud` and `pinned` | Combat Sequence → Detached window |
| `sequence.window.position`, `sequence.window.width`, `sequence.window.height` | `{ point = "CENTER", relPoint = "CENTER", x = -360, y = 0 }`, `460` (`LW.MIN_WIDTH` 320 to `MAX_WIDTH` 900), `0` (0: the rows' height): the free-standing window's place and its size, written raw by its drag and its grip's release, the place put back by Master controls' Reset position; no row (named state, below) | none (the window's drag and grip) |
| `sequence.view.sort`, `throttle`, `throttleMs`, `fontSize`, `rowHeight`, `timeFormat` | `"newest"` (`"oldest"`; the Time header's click flips it), `"instant"` (`"every"`, `"batch"`), `250` (50-1000), `10` (8-16 points; `LogTable.FONT_BASE`, GameFontHighlightSmall's), `14` (12-28 px; `LogTable.ROW_H`), `"pull"` (`"clock"`): the table in all three homes (modules/LogTable.lua, modules/LogTable_View.lua): its sort, the live views' display throttle (it delays the display only; the capture and the store never wait), the rows' text size and height (CL-11c2: every home's height follows `LogTable.RowH()`, the fixed columns and the icon widen with the text), and the time from the pull or the clock | Combat Sequence → Order and display |
| `sequence.view.columns.*` | `spell`, `info` both `true`: the optional columns (Time and Event always show; Info, which reads only Interrupted, only where a home has room: the detached window and the Results detail). There is no Source or Target column (owner feedback item 3): step 5 drops `source` and `target`; there is no Amount column (CSEQ-1): step 8 drops `amount` | Combat Sequence → Order and display |
| `sequence.show.*` | one `true` per category of `CombatLog.CATEGORIES` (`casts`, `petCasts`, `playerBuffs`, `playerDebuffs`, `targetDebuffs`, `deaths`), `autoAttacks = false`: what the live views show, the defaults their chips seed from (`LogTable.Reseeds`: a chip's click is the view's own, for the session, never stored) (the Results Combat Sequence section's chips filter by these categories' chips, and read `deaths`). `hits`, `heals`, `targetBuffs` and `minAmount` went with their rows (CSEQ-1): step 8 drops them | Combat Sequence → What to show |
| `sequence.view.washes` | `true`: the rows' washes (a DEBUFF+ row and a long-cooldown CAST); off, every kind still differs by its tag. `schoolColors` went with the schools (CSEQ-1): step 8 drops it | Combat Sequence → Colors |
| `sequence.store.enabled`, `sequence.store.lines`, `sequence.store.categories.*` | `true`; `NS.Constants.LOG.MAX_PER_FIGHT` (400; 100 to 1000, `MIN_PER_FIGHT` to `MAX_LINES`); one `true` per category in `CombatLog.CATEGORIES` (`casts`, `petCasts`, `playerBuffs`, `playerDebuffs`, `targetDebuffs`, `deaths`; step 8 drops `hits`, `heals` and `targetBuffs`): whether a fight's record keeps its sequence, how many lines (the newest), and which kinds of line it keeps, apart from what any view shows. Each fight freezes them at its start | Combat Sequence → Storage |
| `sequence.store.fights` | `NS.Constants.LOG.FIGHTS` (100; 0 to `MAX_FIGHTS` 500, 0 keeps every sequence): how many stored fights keep their saved sequence, the newest carrying one; each purge run (modules/Retention.lua: login, daily, `/ct purge`) strips `log`, `logDropped` and `logTargets` from every older one, best-holding fights included, the fight itself kept | Combat Sequence → Storage |
| `sequence.results.jumpToCast`, `sequence.results.chips.*` | `true`; one `true` per chip of `ResultsLog.CHIPS` (`casts`, `pet`, `buffs`, `debuffs`; step 8 drops `taken` and `heals`): the Results fight detail's Combat Sequence section (modules/Results_Log.lua, CL-11c), whether a click on a CAST row opens the ability timeline at that cast, and the chips each fight opens on (a click on a chip turns it for the fight shown, never stored) | Combat Sequence → Results |
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
| `usage.hiddenSpells` | The buff spell IDs the Usage list never shows, comma-separated (CombatTrail #13), beside the hidden items |
| `pendingRaces` | A race under way, per character, `{ [Bests.CharKey] = slot }` (modules/Race.lua, race plan Task B2): written at its first hit, cleared at its result or a cancel, plain fields only; on both clients, written only where a race runs (Retail). The slot's fields are under *Named non-setting state* |
| `dummies.captures` | What the game said about each creature `/ct dummy` captured, `{ [creatureID] = { name, level, classification, health, creatureType, pvp, faction, reaction, first, last, count, addon, build, places = { [mapID] = { zone, subzone, x, y, date } } } }` (modules/Dummies.lua); a sealed field is absent |
| `minimap` | LibDBIcon's own table, handed to `:Register` |
| `skinNotice` | The account's one-time skin notice, written by LibKa0s-Options |

## Named non-setting state (architecture-§5)

| State | Storage key | Owner | Writers |
|---|---|---|---|
| A lane's dragged place | `lanes.<k>.anchor.x` / `.y` (and `point`) | modules/LaneAnchor.lua | `dragStop` (the edit overlay's drag) through `write`; `NS.Lanes.ResetPosition` (Master controls' Reset position) |
| The HUD's place | `hud.position` | modules/Hud.lua | `normalizeAnchor` (the title bar's drag and the grip's release, and a Refresh that finds the stored point off the top edge: TOPLEFT on UIParent's BOTTOMLEFT), else `savePosition`; `Hud.ResetPosition` |
| The Results window's place, size and fold | `results.window` | modules/Results.lua | `savePosition` (drag, the grip's release, the fold arrow through `Results.SetView`); `Results.ResetPosition` |
| The Results columns' dragged widths | `results.columns` | modules/Results_Fights.lua | `Fights.StoreColumnWidth` (a header edge's release, through the table's `onColumnResize`); `Fights.ClearColumnWidths` (`Results.ResetPosition`) |
| The detail's folded sections | `results.collapsedSections` | modules/Results_Detail.lua | `Detail.SetCollapsed` (a heading's arrow or text, through `Pane:ToggleSection`; Add Note opens the Note); kept by `Results.ResetPosition` |
| The saved Results view | `results.view` | modules/Results_Fights.lua | `writeView` (the Save button; Reset writes nil, so the shipped view applies) |
| The saved Insights view | `results.insights` | modules/Results_Insights.lua | `writeView` (the Insights tab's Save; Reset writes nil, so the shipped view applies); never written over the sample history |
| The fight store | `global.fights`, `global.fightOrder` | modules/Recorder.lua | `Recorder.Save`, `Recorder.Delete`, `Recorder.SetNote`; `Retention.Purge` (modules/Retention.lua) |
| Interned loadouts | `global.loadouts` | modules/Loadouts.lua | `Loadouts.Store`; `Loadouts.Sweep`, called by the purge |
| Equipment sets | `global.gearSets` | modules/Loadouts.lua | `Loadouts.StoreGear`, through `Loadouts.Recon` (PLAYER_ENTERING_WORLD, the debounced PLAYER_EQUIPMENT_CHANGED and UNIT_INVENTORY_CHANGED, the stand-up, and the pull when no set is known); `Loadouts.Sweep`, called by the purge and a delete, keeping the current set and the live fight's |
| The Usage hidden list | `global.usage.hidden` | modules/Usage.lua | `Usage.Hide`, `Usage.Unhide` and the History page's Usage tab, all through `NS.SetByPath` |
| The Usage hidden buffs | `global.usage.hiddenSpells` | modules/Usage.lua | `Usage.HideSpell`, `Usage.UnhideSpell` and the History page's Usage tab, all through `NS.SetByPath` |
| The call-out's place | `callout.point` | modules/Countdown.lua's `NS.Callout` (LibKa0s-Callout-1.0) | the call-out's drag-stop (Unlock to move in the Race mode page's Callout tab (its Preview block)) and its `ResetPosition` (Reset position there), both through `NS.SetByPath`, the path in the schema's `writeThrough` (no control chooses it, so it has no row; Retail only) |
| The Combat Sequence window's place and size | `sequence.window.position`, `sequence.window.width`, `sequence.window.height` | modules/LogWindow.lua | written raw: the title bar's drag-stop, the grip's release (`keepWhereItStands`; the width, and the height with `fill` on); no row, so neither the page's Defaults nor `/ct set` reach them |
| The last race length armed | `race.lastLength` (no default) | modules/Race.lua | `Race.Arm` (a successful arm); `Race.DefaultLength` reads it before `race.defaultLength` |
| A race under way, per character | `global.pendingRaces` (`{ [Bests.CharKey] = slot }`) | modules/Race.lua | written at a race's first hit (and when it follows a split), its `lastDamage` and sessions at each damage update; cleared at its result, a cancel, or a `Race.Resume` that finds it stale. The slot is plain: the race part itself, `startedAt`, `date`, `lastDamage`, `sessions`, `boundBy`, `sharedSession`, `startT`, `snapshot`, `stats`, `talents`, `gearSet`, `baseline` |
| The training-dummy captures | `global.dummies.captures` | modules/Dummies.lua | `Dummies.Capture` (`/ct dummy add` and `capture`, the Training dummies tab's Add your target) |
| The skin picker seen | `skin.pickerSeen`, `global.skinNotice` | core/SkinSetup.lua (LibKa0s-Options writes the notice) | the picker's close |
| The minimap button | `global.minimap` | LibDBIcon-1.0 (vendored) | its own drag; the `general.minimap.shown` row |
| The perf record | `CombatTrailPerfDB` | LibKa0s-Perf-1.0 (vendored) | `/ct perf` |

## The fight record (CT_SCHEMA 6)

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
| `gearSet`, `stats`, `loadout`, `usage` | the key of the equipment set current at combat start (`global.gearSets`; read through `Loadouts.GearOf`, which also takes a sample fight's inline `gear`), the stats (per fight: they move with buffs), the loadout key, what was used (below) |
| `targets` | CT_SCHEMA 3, optional: `{ { name, total }, ... }`, the enemies your damage reached (the meter's EnemyDamageTaken view, read after combat), enemies of one name merged, highest first, at most `Recorder.TARGETS_MAX` (10). Absent on a CT_SCHEMA 2 record or when the meter answered none; the fight detail's Targets section is then not drawn |
| `race` | CT_SCHEMA 4, optional: a race's part (Race mode; `modules/RaceRecord.lua`, `RaceRecord.Plain` keeps these fields only, each only when plain): `length` (the race length picked, s), `kind` (the dummy's category when saved; the boards read the Training dummies list now and fall back to it), `status` (`complete` or `incomplete`: a lost or canceled race is taken off its fight, which is then judged as a plain fight), `flags` (`lateCasts` `{ { t, spellID } }`, `restartedAt`, `reloaded`, `died`, `sessionFromList`: the race's fight bound its session only on a tick's look at the meter's list, ruling X14, `sharedSession`: the pull carried on a meter session alive at the arm, ruling X3, `carriedOn`: combat came back inside the grace after an early end, ruling X16), `score` (the session's merged total; for a shared session, less what it held at the arm, as is the record's own damage), `dps` (score over `length`, over `endedAt` when incomplete, over the first hit to the fight's end when incomplete and `carriedOn`), `tail`, `endedAt`, `combatEnd`, `grace`, `restartGap`, `firstHit` (the race clock's zero on the fight clock, ruling X9: seconds from combat entry, the zero of `casts` and of the chart's steps, to the first hit, to the hundredth; a resumed race keeps its pull's, or 0 when its slot kept no `startT`. The Results detail's chart and the Timeline shift a race by it and draw its buzzer line at `length`, on Retail only: `NS.ResultsRaces.Clock`. Absent on a race saved before it, which reads as 0, no shift; no migration, as the part is new in CT_SCHEMA 4). A race is saved without the recording filters; the record's own `duration` and `dps` stay the fight's, and `RaceRecord.Dps` is the race DPS wherever a race is shown. Absent on a fight and on every older record |
| `log`, `logDropped`, `logTargets` | CT_SCHEMA 6, optional (CombatTrail #11, modules/CombatLog.lua): the fight's Combat Sequence (the field keeps its name), an array oldest first of `{ t, k, id?, u?, f?, g? }`: `t` seconds from the fight's start (to the tenth, a pre-pull cast negative), `k` the kind (`CombatLog.KIND`: 1 CAST, 2 BUFF+, 3 BUFF−, 4 DEBUFF+, 5 DEBUFF−, 8 DIES; 6 HIT, 7 HEAL, 9 START and 10 END are retired, never captured now, and an older log's lines of those kinds, like its BUFF± lines on the target, are dropped at read time by `CombatLog.IsRetired`), `id` the spell ID, `u` the unit (`CombatLog.UNIT`: 1 the player, 2 the pet, 3 the target; none on a boundary), `f` its marks (`CombatLog.FLAG`: 8 an interrupted cast; bits 1, 2 and 4, critical, glancing and crushing, came only from `UNIT_COMBAT` and stay reserved, never reused). A log saved before CSEQ-1 may carry `a` (an amount, or `"s"` for a sealed one) and `s` (a school mask); no view reads them, and no stored log is rewritten. `g` a target line's index into `logTargets`. Names and icons are read at display time from the ID. At most `sequence.store.lines` lines, the newest; `logDropped` counts the lines of saved categories that were not kept, present only when some were. `logTargets` is `{ { name?, friendly? }, ... }`, each target the lines name as it was when the line was captured (its plain name, none when the client sealed it, and `friendly = true` when the player could not attack it), present only when a line names one; a line with no `g` reads as the record's primary target, hostile. Absent on an older record, with saving off, on a sample fight, and on a fight past `sequence.store.fights` (Retention strips it): `CombatLog.Of` answers nil and a view shows none |
| `note`, `client`, `build`, `version`, `status` | the player's note (`Recorder.ClampNote`: a control character to a space, `\|` to `/`, trimmed, at most 200 UTF-8 characters), `retail`/`forever`, the client build, the addon version, `"final"` |

`usage` (modules/Usage.lua) is `{ v, used, candidates, edited }`. Each `used` entry is
`{ itemID?, spellID?, kind, slot?, times?, n, src }`: item-keyed (gear, a potion, a flask, an other
consumable), spell-keyed (`kind = "buff"`, a seeded world, camp, zone, shrine, faire or event buff on at
the pull, `src = "buff"`; usage v 2, CT_SCHEMA 5, CombatTrail #13), or neither (`kind = "food"`, Well Fed).
`src` is `cast`, `bag`, `buff` or `manual`. A candidate is `{ itemID?, spellID?, kind, slot? }`. Plain
food and drink (the client's Food & Drink subclass, or an Eat or Drink use spell) is never recorded from
v 2 on. A v 1 usage (CT_SCHEMA 4 and older) has no spell-keyed entry and reads as it is; a Food & Drink
item entry in it (`kind = "food"` with an `itemID`, the Eat aura or count of a food) is kept in the
record and never shown.

A five-minute raid fight packs under 6 KB without its Combat Sequence (pinned by `tests/test_record.lua`). A
log at the default cap of 400 lines adds about 38 KB (pinned under 39,500 bytes by
`tests/test_combat_log.lua`; [`performance.md`](performance.md), *Stored size*), and only the newest
`sequence.store.fights` (100) stored fights keep one. The History page's
History tab shows the count and an estimate (`Retention.EstimateBytes`), saved sequences included.

## Migrations

`core/Database.lua` runs `STEPS` in order against `global.schemaVersion`, moving the stamp only past
a step that returned; a step marked `perProfile` runs once for every stored profile. The target is
`NS.SCHEMA_VERSION`.

| Step | From → to | Does |
|---|---|---|
| 1 | 0 → 1 | Nothing: the first release's shape |
| 2 | 1 → 2 | Empties the fight store, its order, the loadouts and the gear sets (`global.fights`, `fightOrder`, `loadouts`, `gearSets`): the v0.2 record shape, CT_SCHEMA 2. Every other account-wide key is kept |
| 3 | 2 → 3 | Per profile (`perProfile`, every stored profile, the active one and the rest): the race call-out at LibKa0s-Callout-1.0 3.4 (callout plan row C11). A stored `callout.glow` choice is rewritten by the library's own `Callout:MigrateGlow` (`"off"` → `glow = false`; `"soft"` → on at 35% and 2 px; `"strong"` → on at 70% and 5 px, each intensity or thickness only where no valid one is stored; the old choice named no color, offset or swatch, so none is stored and a migrated profile reads the current defaults for them: since LibKa0s v1.102.0, *Glow color* ticked in the black swatch, now at Combat Trail's 1, 1 (SD-CT-DEF), where v1.100.0 drew each word's kind color at 0, 0; the owner's defaults, so no further step), after an intensity or thickness equal to its default beside the old string is cleared as AceDB's copy (savedvariables-§1: compare to the default, never test for the key; those keys are new with the boolean, so no player set one under the old choice). `callout.texts` and `callout.muted` are dropped: their rows are gone, and the instance would still read a stored own word or mute, so leaving them would keep a preference with no row (architecture-§5). A stored `callout.voice` is kept; an unset one reads the new default, Arena John. AceDB stores no value equal to its default, so a profile on the old default `female` (Kathleen), whether chosen or not, has no stored voice and moves to Arena John (savedvariables-§1: the step cannot tell that choice from no choice). Idempotent: a profile with no `callout` table, or a migrated one, passes unchanged. Without the library the glow string stays and only the two tables are dropped |

Step 12 (11 → 12, per profile, `NS.DropWhoColors`, the owner's ruling of 2026-11-26, SM-CT-LG27,
R4-CT-08) drops the stored `sequence.colors` whole (`you`, `useClassColorYou`, `hostile`,
`hostileFromSkin`, `friendly`, `friendlyFromSkin`): the who colors drew nothing once the Source and
Target columns went, and the owner removed them with their rows, `LogTable.ReadColors` and the skin
tokens `ct.log.hostile` and `ct.log.friendly` (LibKa0s stores no per-token override, so no stored value
names those). Idempotent: a fresh profile stores none. The fight record's `logTargets` stays: it is data.

Step 11 (10 → 11, per profile, `NS.MoveOpenOnPull`, the owner's ruling of 2026-11-26, SM-CT-LG22,
R4-CT-08) moves *Open when a fight starts* from the Combat Sequence to the DPS HUD: it drops
`sequence.drawer.autoOpen`, and a stored `false` becomes `hud.openOnPull = false`; an on or nothing
stored leaves the new key's default, on, which is the old key's default carried. Idempotent: a second
run finds no old key.

Step 10 (9 → 10, per profile, `NS.PinHudWidth`, owner feedback round 4, R4-CT-06) writes
`hud.width = 390`, the default until then, into every stored profile that keeps no width (or only the
default's copy AceDB puts into the active profile), so only a new profile starts at the new default,
260. It skips a fresh install (no stamp when the runner started: every install that ever loaded was
stamped at least 1, so the runner hands each per-profile step `fresh`) and a profile table with nothing
stored. A 260 chosen under the old default reads the same as the copy, and is pinned too. Idempotent: a
width of its own is kept.

Step 9 (8 → 9, per profile, `NS.MoveLogToSequence`, the Combat Sequence, 2026-11-25, CSEQ-2) moves the
stored `log` table to `sequence`, since the Combat Log is the Combat Sequence everywhere, its keys
included. Where a profile stores only `log`, the table moves whole; where it stores both, the two are
deep-merged, a key only under `log` copied across and a key already under `sequence` kept, unless it
equals its default, in which case the `log` value replaces it (AceDB copies the defaults into the active
profile, so without that exception the active profile's own choices would lose to the defaults). Then
`log` is cleared. The Results fold `results.collapsedSections.log` moves to `.sequence` the same way.
Steps 5, 6 and 8 run on `log` before it, so nothing retired is carried across. Idempotent: a second
run finds no `log`, and a profile with neither is left alone. The fight record's `log` fields are not
touched.

Step 8 (7 → 8, per profile, `NS.DropRetiredSequenceKeys`, the Combat Sequence, 2026-11-25, CSEQ-1)
drops, under the stored `log`, the keys whose features went when the hit and heal rows did:
`view.columns.amount` and `view.schoolColors` (no line carries an amount or a school), `show.hits`,
`show.heals`, `show.minAmount` and `show.targetBuffs`, `store.categories.hits`, `.heals` and
`.targetBuffs`, and the Taken and Heals chips' `results.chips.taken` and `.heals`. Nothing is carried
across, since each served only what was removed. Idempotent: a fresh profile stores none of them, and a
profile with no `log` table is left alone.

Step 7 (6 → 7, per profile, `NS.CarryLanesLock`, the owner's Combat Log feedback, 2026-11-25, CLF-3)
gives the lanes their own lock (item 15). Until then `general.locked` also kept Edit Mode from unlocking
the lanes; from here they read `general.lanesLocked`, so a profile that stores `general.locked = true`
gets `general.lanesLocked = true` and its lanes stay locked. `general.locked` is kept: it is still the
DPS HUD's and the windows' lock. Idempotent: a lanes lock already stored is kept, and a profile with no
stored lock stores nothing.

Step 6 (5 → 6, per profile, `NS.DropRetiredWindowKeys`, the owner's Combat Log feedback, 2026-11-25, CLF-2)
drops the keys of two retired states: `hud.sizeMode` and `hud.grow` (the HUD's auto-grow; the HUD is one
window of one static height, item 12) and `log.window.attached`, `.side`, `.matchHud` and `.pinned` (the
log window's attached state; it is a standalone window, item 11). Nothing is carried across: a HUD that
grew keeps its bars, and a log window that stood beside the HUD stands at its own stored place.
Idempotent; a profile with neither table is left alone.

Step 5 (4 → 5, per profile, `NS.DropRetiredLogKeys`, the owner's Combat Log feedback, 2026-11-25) drops
the keys whose features went: `log.view.columns.source` and `log.view.columns.target` (the Source and
Target columns, item 3), and `log.drawer.collapsed` and `log.drawer.strip` (the drawer's fold and its
folded line, item 14). Nothing is carried across, since each served only what was removed. Idempotent; a
profile with no `log` table is left alone.

Step 4 (3 → 4, per profile, `NS.RestoreOwnLooks`, the owner, 2026-11-23) undoes a retired step. From
2026-11-20 until then, never released, a step outside the ladder moved options onto the skin and recorded
`skin.defaultsMoved` on each profile. In a profile carrying that record, a value of `NS.OWN_LOOKS` still
holding what that step left there takes the owner's own back, and the record is cleared. Any other profile
is untouched. AceDB stores no value equal to its default, so a profile that stores none reads the owner's
own from the defaults.

A change to the fight record bumps `Recorder.CT_SCHEMA` and reads the older shape where it is read,
never by rewriting stored fights: CT_SCHEMA 3 → 4 (the optional `race`) has no step, and an older record
loads as it was, a fight. CT_SCHEMA 4 → 5 (usage v 2, the spell-keyed buff entry) has no step either:
a v 1 usage reads as it is, its Food & Drink item entries left unshown (`Usage.Shown`), and
`tests/test_usage_buffs.lua` holds an older record to that. CT_SCHEMA 5 → 6 (the optional `log`,
`logDropped` and `logTargets`) has no step: an older record has no log and reads as it was. The Combat Sequence (CSEQ-1) changed no record either: `CT_SCHEMA` stays 6, a saved log's `a` and `s` are read past, and its retired kinds and target-buff lines are dropped at read time (`tests/test_combat_log.lua`). The one exception is step 2: the addon was unpublished, so the v0.1
store was emptied once instead of migrated (v0.2 plan, decision D1).
