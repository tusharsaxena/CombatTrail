# Ka0s Combat Trail — architecture

The engineer-context hub (documentation-§3). Each section summarizes and links its topic doc; the
design is [`superpowers/specs/2026-11-10-combat-trail-design.md`](superpowers/specs/2026-11-10-combat-trail-design.md)
(cited below as "spec §N") and the build order is
[`superpowers/plans/2026-11-10-combat-trail-v0.1.0.md`](superpowers/plans/2026-11-10-combat-trail-v0.1.0.md); the first
in-game feedback batch is [`superpowers/plans/2026-11-10-combat-trail-v0.2-feedback.md`](superpowers/plans/2026-11-10-combat-trail-v0.2-feedback.md)
(cited as "v0.2 plan" or "v0.2 Task N").

## Overview

An Ace3 addon in the Ka0s modular layout (`core/ defaults/ modules/ settings/ locales/`), built on
the vendored LibKa0s (the provenance line is in root `CLAUDE.md`). It does three things, and on
Retail a fourth:

- **The trail.** Two fixed cast lanes, Player and Pet, fed by `UNIT_SPELLCAST_*` for `player` and
  `pet` (spec §4).
- **The live HUD.** A DPS window on every fight, fed only by `C_DamageMeter` (spec §6).
- **The history.** Every fight that passes the recording filters stored account-wide in
  `CombatTrailDB.global.fights`, read back by the Results window, the timeline, the compare and the
  gear view (spec §5, §7).
- **Race mode (Retail).** DPS Race, retired as an addon and rebuilt here: a fight on a training dummy
  timed against a set length, with its own Race window, countdown and buzzer, race boards and a
  `race` part on the fight record (the Race mode spec,
  [`superpowers/specs/2026-11-11-race-mode-design.md`](superpowers/specs/2026-11-11-race-mode-design.md),
  and its plan, [`superpowers/plans/2026-11-11-race-mode.md`](superpowers/plans/2026-11-11-race-mode.md),
  whose rulings are cited as "ruling Xn"). A race is a Combat Trail fight that happens to be timed:
  `Race` rides the fight pipeline and `Recorder` saves it.

Core, meter, HUD and Results code is adapted from DPS Race @045f479 with every race concept removed;
Race mode then ports DPS Race @f8078c7's race layer back on top of it. The lanes are new code grown
from the owner's CastTrail. One codebase serves **Retail and WoW
Forever** (`## Interface: 120105, 16001`); every client check goes through `NS.Compat`
(clients-§3).

### Per-client features (clients-§4)

A feature a client cannot have is **absent** there: no row, no menu entry, no filter, no stored key.

| Feature | Retail | WoW Forever |
|---|---|---|
| Delves (lane visibility, the delve tier on the board key, the recording filter) | present | absent |
| Arenas (lane visibility, the recording filter) | present | absent |
| Mythic+ (the keystone level on the board key, the recording filter) | present | absent |
| Vehicles and pet battles (lane visibility's "Hide when" rows and their events) | present | absent |
| Training dummies (Identity's dummy content) | the measured seed in `defaults/Dummies.lua`, plus the player's own list (`modules/Dummies.lua`, History > Training dummies, `/ct dummy`) | no seed, empty by decision until one is measured; the player's own list works as on Retail |
| Ignore seeds (`defaults/IgnoreSeeds.lua`) | its own list, picked once | its own list (the same IDs today) |
| Default skin | Ka0s Default | WoW Forever |
| Recording filters' default minimum length (`history.minLength`) | 30 s | 15 s (Race mode spec §3) |
| Spec in Results (the column's second icon, the dropdown, the Spec grouping, the bests' board, the Share line) | the specialization | the predominant talent tree (most points, a tie to the first) stands in, worded "talent tree" (v0.2 plan A4, D5 and D11); none with no points or no talent API, so the class icon never shows twice |
| The talent-tree section of `/ct probe` | absent | every talent API's answer and the tree picked |
| Race mode's engine (`modules/Race.lua`: its bus receivers and `Race.Arm`; `modules/RaceWatchers.lua`: its events), gated with `NS.Compat.ForClient({ "retail" })` | present | absent: `Race.Arm` refuses (`"client"`), nothing registers; a saved race still lists and re-scores (`modules/LateIgnore.lua`, both clients) |
| The Race mode page (`settings/Race.lua`: the page declared `clients = { "retail" }`, its rows registered on Retail only and each declared retail; the keys `race.enabled`, `autoShow`, `autoArm`, `clock`, the countdown's and the buzzer's, and `raceWindow` built under `ForClient` in `defaults/Profile.lua`) | present | absent: no page, no row, no stored key |
| The `/ct race` verb (`settings/Slash.lua`: the triple declared `clients = { "retail" }`, gated by the library and, degraded, by the stub and `NS.RunVerb`) | present | absent: not in the help, typing it is an unknown verb |
| Auto-show and auto-arm (`modules/AutoArm.lua`: its bus receivers under `ForClient`, its events only while `NS.RaceMode.On()`) | present | absent: nothing registers |
| The Race window (`modules/RaceWindow.lua`, `RaceWindow_States.lua`, `RaceWindow_Best.lua`: each returns at once off Retail, so `NS.RaceWindow` is nil) | present | absent: nothing loads, the toggle refuses |
| The race's countdown and buzzer (`modules/Countdown.lua`, returns at once off Retail) and its chat lines on the arm and at the result (`modules/Share.lua`'s receivers under `ForClient`) | present | absent: nothing loads or registers; a saved race still shares |
| The new-best toast (`modules/BestToast.lua`, History > New-best toast) | a fight's (`toast.fights`) and a race's (`toast.races`) | a fight's only: no `toast.races` key, row or receiver |
| Races in the Results window (`modules/Results_Races.lua`, `Results_RaceDetail.lua`: the Fights / Races / All filter, the race filters, the race groupings, a race row's length and flag chips, the detail's Timing and Flags, the late-cast right-click, `/ct results races`; each asks `NS.ResultsRaces.On()`, `ForClient({ "retail" })`) | present, whether Race mode is on or off (the filter reads the record) | absent: a saved race lists as a fight, with its race DPS, score and time raced, and no race control |
| The Insights tab (`modules/Results_Insights.lua`, `Results_InsightsData.lua`, `/ct results insights`): the cards, DPS Progression, the board tabs with Spec Comparison and Consistency, By Character, By Character x Content, Recent New Bests over every saved fight | present, plus the Fights / Races / All filter, Clean only and Include incomplete, the Clean races card, and under Races the race length and dummy kind filters and the race-only sections (Races By Character x Length, Late Casts, Races Per Day, Damage Tail After The Buzzer; ruling X12) | present with no race control: a saved race counts as a fight, with its race DPS |
| The DPS HUD opening for a race whatever `hud.show`, `hud.instancesOnly` and `general.hudInCombat` say (ruling X7) | present | absent: there is no race |
| Race mode's samples (`modules/MockRaces.lua`, `RaceSample.lua`, `SimRace.lua`: each returns at once off Retail): `/ct test race [armed\|running\|result]`, the sim's eight `race-` scenarios, and the `race` section of `/ct diagnostics` | present | absent: `test race` is plain `test`, the sim lists no race scenario, the report has no race section |
| Sample history (test mode and the sim) | 40 fights and 16 races | 21 fights (no Mythic+, delve, arena, dummy or Mythic raid boards) |
| Everything else (lanes, HUD, Results, probe, sim) | present | present |

Race mode has no launcher entry and no key binding on either client: LibKa0s-Launcher's menu is fixed
(launcher-§2), so the minimap menu stays Enabled, Locked, Test mode, Sim mode and Show window (ruling
X17), and one static `Bindings.xml` would show a Retail-only binding on WoW Forever (clients-§4), so
`Bindings.xml` keeps its three (ruling X18). `/ct race show`, `/ct race toggle` and `/ct race arm`
work in a macro. Neither is a deviation: the spec items are dropped and deferred.

### Secret-value invariants (spec §3)

- `core/Secrets.lua` is the only file that inspects a value that may be secret; everything else asks
  `NS.Secrets` (`IsSecret`, `IsPresent`, `PlainNumber`, `PlainString`, `CanAccessTable`, `SafeIterate`).
  A client answer that may itself be secret, such as a formatter's secret string, is tested for
  presence with `Secrets.IsPresent`, never compared to nil (v0.2 Task F1a).
- `modules/Meter.lua` is the only reader of `C_DamageMeter` (the probe reads it raw through
  `Meter.Api` / `Meter.Call`). In combat its live read is opaque and goes only into C-side widgets:
  `StatusBar:SetMinMaxValues/SetValue`, `SetTexture`, and the secret-safe number formatter.
- No arithmetic, comparison, truth test, `tostring` or table key on a value that may be secret. A
  secret spell ID or castGUID still pushes a lane icon (through the texture) and skips the dedupe.
- Nothing secret is persisted. A record's fields come from the after-combat plain read; a field that
  came back secret is left absent. The in-combat damage curve (`modules/Slices.lua`) lives in memory
  for the session only.
- `COMBAT_LOG_EVENT_UNFILTERED` is never registered: it is protected for addons on both clients.
- No geometry is read back off a frame that has displayed a meter value: every layout is worked out
  from configuration and plain counts. The one exception is the DPS HUD's shell frame, which never
  displays a value itself: its anchor (`GetPoint`) and its edges (`GetLeft`, `GetTop`, `GetBottom`,
  for the grow edge, v0.2 Task B3) are read after a drag, each only as a plain number, and the grip's
  sizes are the ones `OnSizeChanged` hands the shell.

## Module Map

Load order is the TOC's: libraries, the locale, `core/` in dependency order, `defaults/`,
`modules/`, then `settings/` last, every LOAD-BEARING note in the TOC saying what resolves at file
scope. The full file-by-file table is [`module-map.md`](module-map.md). By area:

- **Core:** Namespace, MediaSetup, Constants, State, EnvSetup, CoreSetup, SkinSetup, Compat,
  SimSetup, Secrets, Bus, PoolSetup, WidgetsSetup, ToastSetup, ChartsSetup, LifecycleSetup, PerfSetup, DebugLogSetup,
  LauncherSetup, CombatTrail, Database.
- **Defaults and locale:** IgnoreSeeds, Profile, Dummies, Hearthstones; enUS, enUS_Race, enUS_Insights.
- **Lanes:** LaneCasts, LaneLayout, LaneRender, LaneAnchor, LaneVisibility, LaneIgnore.
- **Fights:** Meter, ProbeCurve, Probe, Dummies, Identity, Fight, Watchers, CastCodec, Casts, Usage, Stats, Loadouts,
  Filters, RaceRecord, Bests, Recorder, Retention, Slices.
- **Race mode (Retail):** RaceTimeline, LateIgnore, RaceScoring, Race, RaceWatchers, AutoArm, RaceVerb.
- **HUD:** Format, Style, Hud_Appearance, Hud_Tips, Hud_Best, Hud_Breakdown, Hud_Chart, Hud_States, Hud.
- **Race window (Retail):** RaceWindow_Best, RaceWindow_States, RaceWindow, Countdown; and BestToast (the
  new-best toast, a fight's on both clients, a race's on Retail).
- **Results:** Sizing, Results_Source, Results_Table, Results_Tips, Results_Fights, Results_Races, Results_Loadout,
  Results_Usage, Results_Targets, Results_RaceDetail, Results_Detail, Share, Results_TimelineData, Results_Timeline, Results_TimelineMarks,
  Results_Gear, Results_Compare, Results_InsightsData, Results_Insights, Results.
- **Preview and support:** MockRotations, MockFights, MockRaces and RaceSample (Retail), Preview, SimRace
  (Retail), Sim, Diagnostics.
- **Settings:** Schema, Slash, OptionsSetup, General, Lanes, Hud, History, Race (the Race mode page, Retail), Profiles.

## Settings Schema

The profile tree is `defaults/Profile.lua` (the only place a default is written): `general`,
`lanes.player` / `lanes.pet`, `hud`, `history`, `results`, `dummies`, `race`, `raceWindow` (Retail) and `skin`. The global tree holds the fight
store (`fights`, `fightOrder`), the interned talent loadouts (`loadouts`) and equipment sets (`gearSets`), the Usage hidden list, the
minimap table and `schemaVersion`, migrated by `core/Database.lua`'s runner to `NS.SCHEMA_VERSION`.
Every row registers into `NS.Schema` through `NS.RegisterSchemaRows`, and every write goes through
`NS.SetByPath`. The storage keys, the registry writer and its load pass, and every piece of named
non-setting state with its owner and writers are in [`schema.md`](schema.md).

## Message Bus

Every name is declared once in `core/Bus.lua` (`NS.MSG`) and sent with `NS.SendBus`; wire names are
`Ka0s_CombatTrail_<Event>`. Sixteen messages, so the table, the payloads, the consumers and the
order rules are in [`message-bus.md`](message-bus.md). By sender:

- **Settings:** `SETTINGS_CHANGED`. **Lanes:** `LANE_PUSH`.
- **Fight:** `COMBAT_ENTERED`, `FIGHT_STARTED`, `FIGHT_FIRST_HIT`, `FIGHT_TICK`, `FIGHT_ENDED`.
- **Recorder and Retention:** `FIGHT_SAVED`, `FIGHT_SKIPPED`, `FIGHTS_CHANGED`.
- **Race (Retail):** `RACE_STATE_CHANGED`, `RACE_ARMED`, `RACE_STARTED`, `RACE_BUZZER`, `RACE_RESULT`,
  `RACE_CANCELED`.

The bus gives no receiver order: Recorder pulls `Race.Finalize` before it judges a fight (ruling X1).
A race under way is the one thing written before its read: `db.global.pendingRaces[charKey]` from its
first hit, so `Race.Resume` (OnEnable and the stand-up) carries it on after a `/reload` through
`Fight.Adopt`, which rebinds the fight to the race's kept sessions.

## Slash Commands

`/ct` and `/combattrail` reach one LibKa0s-Slash-1.0 dispatcher over the ordered `NS.COMMANDS` in
`settings/Slash.lua`: the thirteen reserved verbs plus `skin`, then the feature verbs `results`,
`hud`, `lock`, `unlock`, `test`, `sim`, `purge`, `probe`, `lane`, `ignore` and `dummy`, and `race` on
Retail only (declared `clients = { "retail" }`). Feature verbs refuse while stood down; `lane`,
`ignore` and `dummy` stay live, and `race` stays live for its `ignore` word alone (ruling X10). The full table and the dispatch rules are in
[`slash-dispatch.md`](slash-dispatch.md).

## Event Subscriptions

`NS.RegisterGameEvents` (core/CombatTrail.lua) rebuilds every module's set from current settings at
enable and at each stand-up; the stand-down drops all of them (core/LifecycleSetup.lua's `MODULES`).

- **Lanes:** `UNIT_SPELLCAST_START`, `_SUCCEEDED`, `_INTERRUPTED`, `_FAILED`, `_EMPOWER_START` for
  the lanes switched on (LaneCasts); the visibility rules' events (LaneVisibility) and Edit Mode's
  callbacks (LaneAnchor).
- **Fights, by state (Watchers):** idle hears `PLAYER_REGEN_DISABLED` and `ENCOUNTER_START`
  (plus `ENCOUNTER_END` while an encounter is active); combat and settling add `PLAYER_REGEN_ENABLED`,
  `ENCOUNTER_END` and the meter's `DAMAGE_METER_COMBAT_SESSION_UPDATED`, `_CURRENT_SESSION_UPDATED`
  and `_RESET`; stood down hears nothing.
- **Race, by state (RaceWatchers, Retail only):** idle and result hear nothing; armed hears
  `DAMAGE_METER_RESET`; running and stopping hear both regen edges, `PLAYER_DEAD`,
  `DAMAGE_METER_COMBAT_SESSION_UPDATED` and, on a frame filtered to `player`, `UNIT_SPELLCAST_START`,
  `_EMPOWER_START`, `_CHANNEL_START`, `_SUCCEEDED`, `_INTERRUPTED` and `_CHANNEL_STOP`.
- **Auto-show and auto-arm (AutoArm, Retail only, Race mode on):** with either rule on,
  `PLAYER_TARGET_CHANGED` and `PLAYER_ENTERING_WORLD`; with auto-show on, `NAME_PLATE_UNIT_ADDED` and
  `_REMOVED` too; both off, Race mode off or stood down, nothing.
- **Probe:** nothing until armed; then `UNIT_SPELLCAST_SUCCEEDED` and both regen edges.
- **Equipment recon (Loadouts):** `PLAYER_ENTERING_WORLD`, `PLAYER_EQUIPMENT_CHANGED` and
  `UNIT_INVENTORY_CHANGED` for `player` while standing, each asking for one coalesced recon on an
  AceTimer (`Loadouts.RECON_DELAY`, 0.5 s), so a set swap interns one set; the stand-up asks for one
  too. `PLAYER_REGEN_ENABLED` asks for one only after a recon ran in combat, where a sealed link is
  left out of the set. The stand-down drops the events and the timer.
- **HUD and Results:** no game events; they hear the bus. Results closes on `COMBAT_ENTERED`, the
  Fight's regen edge, never on a game event of its own.

Every registration goes through `NS.SafeRegisterEvent`, so a name a client does not know costs only
itself. The pipeline from event to screen is [`data-flow.md`](data-flow.md).

## Taint Notes

- No secure template, no protected call, no `hooksecurefunc`. The key bindings are `CLICK` bindings
  on plain hidden buttons (core/LauncherSetup.lua).
- A lane anchored to a unit frame anchors **its own** frame to the host; it never touches the host's
  points, so a secure unit button is read, not written.
- The settings panel refuses to open in combat (LibKa0s-Options). Share refuses in combat
  (`modules/Share.lua`), as chat sends are locked there.
- The haste-adjusted tick spacing is read only out of combat and cached (LaneRender).
- `COMBAT_LOG_EVENT_UNFILTERED` is never registered (Secret-value invariants above).

## Known Limitations

The in-combat chart is session-only, the HUD has no live percentage or delta, the pet split rests on
the meter exposing the pet as its own source, and a set of client behaviors still waits for the
owner's in-game checks. Race mode reads on Combat Trail's settle, scores the pet's damage with the
player's, ends a race at the first combat end before the buzzer, and resumes after a `/reload` without
the casts or chart from before it. The full list is [`known-limitations.md`](known-limitations.md); the checks
are in [`smoke-tests.md`](smoke-tests.md).

## Documentation map

Out of scope, named once as directories: `docs/superpowers/`, `docs/audits/`, `docs/reviews/`,
`docs/automated-tests/<run>/`, `docs/perf-analysis/<run>/`, `docs/revendor/<date>-v<tag>/` and
`docs/investigations/`.

### Required (documentation-§3, Tier 1)

| Doc | Covers |
|---|---|
| `scope.md` | What Combat Trail does, and what it deliberately leaves out |
| `module-map.md` | Every non-vendored file, its job, and the load order |
| `schema.md` | The SavedVariables shape, the defaults, the fight record and the migrations |
| `settings-panel.md` | The Page and Covers table, then page, tab and row |
| `data-flow.md` | From the cast and meter events to the lanes, the HUD and the store |
| `common-tasks.md` | Recipes for the changes made most often here |

### Conditional (documentation-§3, Tier 2)

| Doc | Status | Trigger |
|---|---|---|
| `perf-analysis/README.md` | Present | The performance harness is wired (core/PerfSetup.lua) |
| `slash-dispatch.md` | Present | `NS.COMMANDS` carries eight or more commands |
| `midnight-quirks.md` | Present | Always, from v2.102.0 of the standard |
| `compat-layer.md` | Present | `core/Compat.lua` publishes three or more addon-specific shims |
| `message-bus.md` | Present | Sixteen messages, more than ten |
| `profiles.md` | Present | The Profiles page ships in the options UI |
| `known-limitations.md` | Present | The Known Limitations material passes sixty lines |
| `taint.md` | Not applicable | Taint Notes stays under sixty lines |
| `debug.md` | Present | The diagnostics dump ships (every addon) |

### Verification and record (documentation-§3)

| Doc | Covers |
|---|---|
| `testing.md` | How to run the harness and lint; the green commit gate |
| `smoke-tests.md` | The in-game smoke-test suite and the in-game verification list |
| `test-cases.md` | The generated case inventory (authoritative pass count) |
| `performance.md` | The addon performance page |
| `automated-tests/README.md` | What the automated-test record is and how to produce it |
| `automated-tests/RESULTS.md` | One row per run; generated by the runner, never hand-edited apart from the watch list's `Disposition` column |

### Addon-specific (documentation-§3, Tier 3)

| Doc | Covers |
|---|---|
| (none) | |

## Documented deviations

| Rule | What differs | Why | Decided | Re-check trigger |
|---|---|---|---|---|
| slash-commands-§2 | The primary slash is `/ct`, which CTMod has long used (it opens CTMod's settings panel), against the MUST NOT on colliding with a well-known addon's slash. `/combattrail` is the long alias. If both addons load, whichever registers `/ct` last owns it. | Owner's choice: "No one uses ctmod nowadays". | 2026-11-10, owner | CTMod (or another addon using `/ct`) is reported in use alongside Combat Trail |

One ratified deviation, above. The plan's Task 5.3 listed a root `CHANGELOG.md`; documentation-§1 forbids one in an
addon, so the history is the README's `## Version History` alone (a plan correction, not a
deviation).

### Files over the 1500-line cap

`layout-§1` caps every **authored** `.lua` file this repository tracks at 1500 lines, `tests/`
included, with vendored code (`libs/`, `tests/_kit/`) the only carve-out that reaches anything here.
Nothing here is generated non-shipping data, so `tests/run.lua` sets no `Kit.layoutCap`. A file over
the cap has three terminal states and no others: peeled, an open issue naming the seam a peel would
follow, or a ratified row in the register above carrying a re-check trigger. The kit's gate,
`tests/_kit/test_layout_cap.lua`, reads this census from here.

**Nothing is over the cap today.** Measure it with

```
git ls-files '*.lua' | grep -v '^libs/' | grep -v '^tests/_kit/' | xargs wc -l | sort -rn
```
