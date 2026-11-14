# Slash dispatch — Ka0s Combat Trail

How `/ct` and `/combattrail` are routed (documentation-§3, Tier 2: `NS.COMMANDS` carries eight or
more commands). The authority is `NS.COMMANDS` in `settings/Slash.lua`; `/ct help` prints it, and
this page must agree with it (`tests/test_docs.lua` checks that every verb is here).

## The dispatcher

- One LibKa0s-Slash-1.0 instance, built at the bottom of `settings/Slash.lua` from a descriptor:
  the slash words (`NS.SLASH_CMD`, `/` .. `NS.SLASH_LONG`), `NS.COMMANDS` passed in, the alias
  `options` → `config`, and the schema CLI's closures (`get`, `set` through `NS.SetByPath`, `findRow`,
  `allRows`, `applyDefault`).
- A bare `/ct` opens the settings panel.
- **The disabled gate.** While the `disabled` hold is taken every verb but the live set answers the one
  refusal line. The live set is the library's thirteen reserved verbs plus this addon's `lane`,
  `ignore` and `dummy` (`HOST_LIVE_VERBS`), which read and write the lanes' own settings and the
  training-dummy list as `get` and `set` do, and on Retail `race`, which answers its `ignore` word (the
  late-cast list's settings) and refuses every other word itself with the hold's one line (race plan
  ruling X10).
- **Per client.** `race` is declared `clients = { "retail" }` on its triple (clients-§4): the library
  leaves it out of the help and the landing page on WoW Forever, where typing it is an unknown verb.
  The degraded stub and `NS.RunVerb` apply the same gate. The schema CLI follows the rows: on Retail
  `list`, `get`, `set` and `reset` reach the Race mode page's rows, the race call-out's `callout.*` rows
  among them (`/ct set callout.size 150`, `/ct reset callout.voice`; the instance's own validation
  refuses what it would refuse, and the row's reaction re-applies the call-out), and on WoW Forever no
  such path exists. `callout.point`, the call-out's drag-written place, has no row: the CLI does not
  list or reset it; Reset position on the call-out's tabs puts it back.
- **The perf hold.** Every feature verb is wrapped in `feature()`, which answers
  `NS.StoodDownRefusal()`'s line while a capture holds the addon down.
- **One handler per act.** A feature verb calls the same handler as the launcher menu and the key
  bindings (`core/CombatTrail.lua`), or hands its words to the owning module's `OnVerb(rest)` through
  `delegate`.
- **Degraded.** Without LibKa0s-Slash the file builds a stub that keeps the host verbs working, routes
  by the same table and applies the same gate; the schema CLI names the missing library.

## The verbs

| Verb | Arguments | Live while disabled | Handler |
|---|---|---|---|
| `help` | none | yes | the dispatcher's `PrintHelp` |
| `config` | none | yes | `NS.OpenOptionsPanel` |
| `skin` | none | no | `NS.RunSkinVerb` (core/SkinSetup.lua): the skin picker |
| `enable` | none | yes | writes `general.enabled` true through the seam |
| `disable` | none | yes | writes `general.enabled` false |
| `list` | none | yes | the schema CLI |
| `get` | `path` | yes | the schema CLI |
| `set` | `path value` | yes | the schema CLI, through `NS.SetByPath` |
| `reset` | `path` | yes | the schema CLI |
| `resetall` | none | yes | `NS.ShowResetAll`, which asks first |
| `debug` | `on`, `off`, `diagnostics`, or nothing (toggles the console) | yes | `NS.DebugLog:DebugVerb` |
| `diagnostics` | none | yes | `NS.DebugLog:RunDiagnostics` (modules/Diagnostics.lua's sections) |
| `perf` | the library's grammar (`/ct perf help`) | yes | `NS.Perf.OnCommand` |
| `version` | none | yes | the dispatcher's `CliVersion` |
| `results` | `show`, `hide`, `toggle`, or nothing; `insights` (the Insights tab, `Results.ShowTab`); `races` on Retail (the list on the Races filter, `Results.ShowRaces`) | no | `Results.OnVerb` |
| `hud` | `show`, `hide`, `toggle`, `pin`, `unpin`. `hide`, and `toggle` when it closes, take an open Race window with the HUD, each counting as the player's close (`Hud.HideWithRace`); `show` and `toggle`'s open open the HUD, and a Race window still wanted with it (one that hid with the HUD, W29); near a dummy `toggle`'s open opens the Race window too | no | `Hud.OnVerb` |
| `lock` | none | no | writes `general.locked` true; `NS.ApplyLocked` |
| `unlock` | none | no | writes `general.locked` false; the lanes' edit overlay and the HUD's drag |
| `test` | none; on Retail `race [armed\|running\|result]` (test mode holding a sample race in that state, running when none; Race mode off refuses it in one line) | no | `NS.ToggleTestMode`; `NS.TestRace` (modules/Preview.lua) |
| `sim` | nothing (the step panel), `start scenario`, a scenario, or `stop` | no | `NS.RunSimVerb` (modules/Sim.lua, the library's sim grammar) |
| `purge` | none | no | `Retention.OnVerb` |
| `probe` | nothing, `start`, `stop` | no | `Probe.OnVerb` |
| `lane` | `player` or `pet`, then `on` or `off` | yes | `NS.Lanes.OnVerb` (settings/Lanes.lua) |
| `ignore` | `add` or `remove` a spell, `list`, `reset`, then an optional `player` or `pet` | yes | `LaneIgnore.OnVerb` |
| `dummy` | nothing or `show`; `add [category]` (the target; `single` when none is typed), `remove [creature ID or name]` (the target when none), `capture` (the target, not marked), `defaults`. Both clients | yes | `Dummies.OnVerb` (modules/Dummies.lua) |
| `race` | Retail only. `arm [length]` (`90`, `1:30`, `3m`, `1m30s`; 0:10 to 15:00; none: the Race window's pick, else the length the next race arms at; a typed length becomes the window's pick, as in DPS Race), `cancel`, `show`, `hide`, `toggle` (the Race window, through `NS.SetRaceWindowShown`), `ignore [show\|add\|remove\|defaults] <spell>` (the late-cast ignore list). Race mode off refuses the arm and the window in one line | `ignore` only | `RaceVerb.OnVerb` (modules/RaceVerb.lua) |

The sim's scenarios are `Sim.SCENARIOS`: `newbest`, `behind`, `first`, `short` and `lost`, then on Retail
Race mode's eight (modules/SimRace.lua): `race-newbest`, `race-behind`, `race-first`, `race-incomplete`,
`race-died`, `race-flagged`, `race-shared` and `race-sticky`, refused in one line with Race mode off.
A fight scenario plays 15 s in real time (`Sim.LENGTH`; its step window reads *Fighting (15 s)*), under
Retail's 30 s minimum length, so `newbest`, `behind`, `first` and `lost` are exempt from the minimum
and judged by the rest of the recording filters; `short` has its own 10 s and is judged by the
player's own minimum, so its card reads *Not saved: shorter than N s* (callout plan row C10).

Both verbs draw one fixed showcase (modules/MockFights.lua, modules/MockRaces.lua), the same on every
character, and the alerts a scenario earns (callout plan row C6). Bare `/ct test` stays the HUD's,
the lanes' and the Results window's alone: no toast, no call-out. `/ct test race result` adds the
new-best toast's preview and the call-out's NEW_BEST; `running` is a still frame (owner, 2026-11-14):
its clock holds at 0:18, so it shows no center countdown and no STOP; only the sim's race scenarios
count down. In `/ct sim`, `newbest` toasts its save (`toast.fights`) and says NEW_BEST on Retail with
Race mode on; a race scenario counts down to the sample's own endsAt (`RaceSample.EndsAt`) and shows
STOP at its buzzer, `race-newbest` then toasts (`toast.races`) and says NEW_BEST, and
`race-incomplete` and `race-died` say FAILED as they end, by the rule a real race's words follow
(callout plan row C9). Every stop and switch of either takes the
toasts and the call-out down (`Countdown.EndSample`, `BestToast.EndSample`), and nothing writes a
record or a best.

The Race window has no launcher entry (race plan ruling X17). On Retail it has a key, *Toggle Race
window* (`Bindings_Mainline.xml`, the owner's decision of 2026-11-13, superseding ruling X18's
deferral; a documented deviation), whose button runs the same handler as `/ct race toggle`
(`NS.ToggleRaceWindow`). `/ct race show`, `toggle` and `arm` work in a macro too. The DPS HUD's
title-bar Race button (race window redesign ruling O6) runs the same `toggle`. Neither the race verb
nor the flag ever touches the DPS HUD.

## Adding a verb

See [`common-tasks.md`](common-tasks.md), *Add a slash verb*.
