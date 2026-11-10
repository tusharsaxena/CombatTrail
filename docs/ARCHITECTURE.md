# Ka0s Combat Trail — architecture

The engineer-context hub (documentation-§3). Each section summarizes and links its topic doc; the
design is [`superpowers/specs/2026-11-10-combat-trail-design.md`](superpowers/specs/2026-11-10-combat-trail-design.md)
(cited below as "spec §N") and the build order is
[`superpowers/plans/2026-11-10-combat-trail-v0.1.0.md`](superpowers/plans/2026-11-10-combat-trail-v0.1.0.md).

## Overview

An Ace3 addon in the Ka0s modular layout (`core/ defaults/ modules/ settings/ locales/`), built on
the vendored LibKa0s (the provenance line is in root `CLAUDE.md`). It does three things:

- **The trail.** Two fixed cast lanes, Player and Pet, fed by `UNIT_SPELLCAST_*` for `player` and
  `pet` (spec §4).
- **The live HUD.** A DPS window on every fight, fed only by `C_DamageMeter` (spec §6).
- **The history.** Every fight that passes the recording filters stored account-wide in
  `CombatTrailDB.global.fights`, read back by the Results window, the timeline, the compare and the
  gear view (spec §5, §7).

Core, meter, HUD and Results code is adapted from DPS Race @045f479 with every race concept removed;
the lanes are new code grown from the owner's CastTrail. One codebase serves **Retail and WoW
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
| Training dummies (Identity's dummy content) | the measured dummies in `defaults/Dummies.lua` | none, empty by decision until one is measured |
| Ignore seeds (`defaults/IgnoreSeeds.lua`) | its own list, picked once | its own list (the same IDs today) |
| Default skin | Ka0s Default | WoW Forever |
| Spec in Results (the column's second icon, the dropdown, the Spec grouping, the bests' board, the Share line) | the specialization | the predominant talent tree (most points, a tie to the first) stands in, worded "talent tree" (v0.2 plan A4, D5 and D11); none with no points or no talent API, so the class icon never shows twice |
| The talent-tree section of `/ct probe` | absent | every talent API's answer and the tree picked |
| Sample history (test mode and the sim) | 40 fights | 21 fights (no Mythic+, delve, arena, dummy or Mythic raid boards) |
| Everything else (lanes, HUD, Results, probe, sim) | present | present |

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
  SimSetup, Secrets, Bus, PoolSetup, WidgetsSetup, LifecycleSetup, PerfSetup, DebugLogSetup,
  LauncherSetup, CombatTrail, Database.
- **Defaults and locale:** IgnoreSeeds, Profile, Dummies; enUS.
- **Lanes:** LaneCasts, LaneLayout, LaneRender, LaneAnchor, LaneVisibility, LaneIgnore.
- **Fights:** Meter, Probe, Identity, Fight, Watchers, CastCodec, Casts, Usage, Stats, Loadouts,
  Filters, Bests, Recorder, Retention, Slices.
- **HUD:** Format, Style, Hud_Appearance, Hud_Tips, Hud_Best, Hud_Breakdown, Hud_Chart, Hud_States, Hud.
- **Results:** Sizing, Results_Source, Results_Table, Results_Tips, Results_Fights, Results_Loadout,
  Results_Usage, Results_Detail, Share, Results_TimelineData, Results_Timeline, Results_TimelineMarks,
  Results_Gear, Results_Compare, Results.
- **Preview and support:** MockRotations, MockFights, Preview, Sim, Diagnostics.
- **Settings:** Schema, Slash, OptionsSetup, General, Lanes, Hud, History, Profiles.

## Settings Schema

The profile tree is `defaults/Profile.lua` (the only place a default is written): `general`,
`lanes.player` / `lanes.pet`, `hud`, `history`, `results` and `skin`. The global tree holds the fight
store (`fights`, `fightOrder`), the interned talent loadouts (`loadouts`) and equipment sets (`gearSets`), the Usage hidden list, the
minimap table and `schemaVersion`, migrated by `core/Database.lua`'s runner to `NS.SCHEMA_VERSION`.
Every row registers into `NS.Schema` through `NS.RegisterSchemaRows`, and every write goes through
`NS.SetByPath`. The storage keys, the registry writer and its load pass, and every piece of named
non-setting state with its owner and writers are in [`schema.md`](schema.md).

## Message Bus

Every name is declared once in `core/Bus.lua` (`NS.MSG`) and sent with `NS.SendBus`; wire names are
`Ka0s_CombatTrail_<Event>`. Nine messages, so `message-bus.md` is not required.

| Message | Sender | Payload | Consumers |
|---|---|---|---|
| `SETTINGS_CHANGED` | settings/Schema.lua | `(path, value)`, or `("profile", key)` | Hud, LaneAnchor, LaneCasts, LaneRender, LaneVisibility, Results, History page |
| `LANE_PUSH` | LaneCasts | `(laneKey, item)` | LaneRender |
| `COMBAT_ENTERED` | Fight, on the `PLAYER_REGEN_DISABLED` edge only (never a split or a mid-combat `ENCOUNTER_START`) | `(t)` | Results (closes while `results.closeInCombat` is on) |
| `FIGHT_STARTED` | Fight | `(fight)` | Casts, Hud, Loadouts, Preview (ends test mode), Slices, Stats, Usage |
| `FIGHT_TICK` | Fight, every 0.25 s in combat | `(fight)` | Hud, Slices |
| `FIGHT_ENDED` | Fight | `(fight, final, reason)` | Casts, Hud, Recorder, Slices, Usage |
| `FIGHT_SAVED` | Recorder | `(record)` | Bests, Hud, Results, Slices, History page |
| `FIGHT_SKIPPED` | Recorder | `(fight, reason)` | Hud, Slices |
| `FIGHTS_CHANGED` | Recorder, Retention | none | Bests, Results, History page |

The sample fight of test mode and the sim is never sent on the bus: Preview and Sim hand it to the
HUD directly, so the recorder, the casts, the slices reader and the bests never hear it.

## Slash Commands

`/ct` and `/combattrail` reach one LibKa0s-Slash-1.0 dispatcher over the ordered `NS.COMMANDS` in
`settings/Slash.lua`: the thirteen reserved verbs plus `skin`, then the feature verbs `results`,
`hud`, `lock`, `unlock`, `test`, `sim`, `purge`, `probe`, `lane` and `ignore`. Feature verbs refuse
while stood down; `lane` and `ignore` stay live. The full table and the dispatch rules are in
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
owner's in-game checks. The full list is [`known-limitations.md`](known-limitations.md); the checks
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
| `message-bus.md` | Not applicable | Nine messages, not more than ten |
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
