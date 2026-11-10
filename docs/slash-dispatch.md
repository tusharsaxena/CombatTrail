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
  refusal line. The live set is the library's thirteen reserved verbs plus this addon's `lane` and
  `ignore` (`HOST_LIVE_VERBS`), which read and write the lanes' own settings as `get` and `set` do.
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
| `results` | `show`, `hide`, `toggle`, or nothing | no | `Results.OnVerb` |
| `hud` | `show`, `hide`, `toggle`, `pin`, `unpin` | no | `Hud.OnVerb` |
| `lock` | none | no | writes `general.locked` true; `NS.ApplyLocked` |
| `unlock` | none | no | writes `general.locked` false; the lanes' edit overlay and the HUD's drag |
| `test` | none | no | `NS.ToggleTestMode` (modules/Preview.lua) |
| `sim` | nothing (the step panel), `start scenario`, a scenario, or `stop` | no | `NS.RunSimVerb` (modules/Sim.lua, the library's sim grammar) |
| `purge` | none | no | `Retention.OnVerb` |
| `probe` | nothing, `start`, `stop` | no | `Probe.OnVerb` |
| `lane` | `player` or `pet`, then `on` or `off` | yes | `NS.Lanes.OnVerb` (settings/Lanes.lua) |
| `ignore` | `add` or `remove` a spell, `list`, `reset`, then an optional `player` or `pet` | yes | `LaneIgnore.OnVerb` |

The sim's scenarios are `Sim.SCENARIOS`: `newbest`, `behind`, `first`, `short` and `lost`.

## Adding a verb

See [`common-tasks.md`](common-tasks.md), *Add a slash verb*.
