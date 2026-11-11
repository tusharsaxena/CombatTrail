# Module map — Ka0s Combat Trail

Every non-vendored file the addon ships, in TOC load order, with its one job (documentation-§3, Tier
1). Each file's own header says the same in more words, and each LOAD-BEARING note in
`CombatTrail.toc` says what that file resolves at file scope.

## Load order and why

- **Libraries first** (`libs/`, vendored): LibStub, CallbackHandler, Ace3, then `LibKa0s.xml` as one
  line (its own file list), then LibSharedMedia, LibDataBroker and LibDBIcon. Panel Master's copies,
  the set that loads on both clients.
- **The locale** next: `locales/enUS.lua` creates `NS.L`, which several `core/` files read at file
  scope.
- **`core/`** in dependency order: the namespace and media first, then the skin seam (before any
  frame-building file), the compat root (before the secret guards bind), the latch (before the perf
  harness, which raises without it), and the AceAddon promotion after the printer exists.
- **`defaults/`**: the ignore seeds before the profile tree that reads them.
- **`modules/`** in conventional order. Each reaches the others at call time, except where a module
  registers its bus receiver or captures a neighbor at file scope (the TOC names each one).
- **`settings/` last**: the schema and the slash table first, the options descriptor, then the pages
  in panel order (General first, Profiles last), because the page order is the registration order.

## Files

| File | Job |
|---|---|
| `CombatTrail.toc` | Both interface numbers, the metadata and the load order |
| `Bindings.xml` | The three `CLICK` key bindings in the addon's own category |
| `locales/enUS.lua` | `NS.L`, the canonical locale with the key-is-the-string fallback |
| `core/Namespace.lua` | The chat tag, folder name, brand, slash words and version fallback |
| `core/MediaSetup.lua` | `NS.Icon` and `NS.MediaFont` from LibKa0s-Media, and the one LibSharedMedia registration |
| `core/Constants.lua` | Fixed values: the mono face, the logo path, the frame-layering table, the fight timing, the shared bar palette (`PALETTE`, every bar default's source) |
| `core/State.lua` | Session-only state, never stored |
| `core/EnvSetup.lua` | TOC metadata and the addon version, from LibKa0s-Env |
| `core/CoreSetup.lua` | `NS.Print`, the secret-safe stringifier, the safe-register family and the window chrome |
| `core/SkinSetup.lua` | The LibKa0s-Skin seam: which skin this addon wears, its owner tokens and the first-run picker |
| `core/Compat.lua` | The compat family's only file: every version-variant client call behind `NS.Compat` |
| `core/SimSetup.lua` | The LibKa0s-Sim seam the `/ct sim` step session is built on |
| `core/Secrets.lua` | The only file that inspects a value that may be secret |
| `core/Bus.lua` | Every message name, declared once, and the record of the bus receivers |
| `core/PoolSetup.lua` | `NS.Pool`, the widget pool the lanes, the HUD and the Results window use |
| `core/WidgetsSetup.lua` | Dropdowns, menus, the test and sim strips and the copy box, from LibKa0s-Widgets |
| `core/LifecycleSetup.lua` | The one stand-down latch and the modules it suspends and resumes |
| `core/PerfSetup.lua` | `NS.Perf`, the performance harness and its buckets |
| `core/DebugLogSetup.lua` | `NS.DebugLog`, the gated `NS.Debug` sink and the diagnostics descriptor |
| `core/LauncherSetup.lua` | The minimap button and broker row, and the three binding buttons |
| `core/CombatTrail.lua` | AceAddon registration, `NS.RegisterGameEvents`, and the host handlers every surface shares |
| `core/Database.lua` | AceDB setup, the profile callbacks and the migration runner |
| `defaults/IgnoreSeeds.lua` | Each lane's ignored spells out of the box, per client |
| `defaults/Profile.lua` | The AceDB defaults tree, the only place a default is written |
| `defaults/Dummies.lua` | The measured training dummies' seed, per client, with each dummy's category |
| `modules/LaneCasts.lua` | The lanes' cast capture: one `LANE_PUSH` per shown cast, dedupe and interrupt marks |
| `modules/LaneLayout.lua` | The lanes' layout math, pure |
| `modules/LaneRender.lua` | Each lane's frame, ticks, label and pooled icons, and its `OnUpdate` while icons show |
| `modules/LaneAnchor.lua` | Where a lane sits (free, docked, unit frame), its strata and level, and the edit overlay |
| `modules/LaneVisibility.lua` | When a lane shows and how opaque it is |
| `modules/LaneIgnore.lua` | Each lane's ignore list and the `/ct ignore` verb |
| `modules/Meter.lua` | The only reader of `C_DamageMeter`: sessions, the live read and the after-combat read |
| `modules/ProbeCurve.lua` | `/ct probe`'s spell color curve trial (issue #7): can the client map a secret spell ID to a color |
| `modules/Probe.lua` | `/ct probe`, the in-game report of what the client answers |
| `modules/Dummies.lua` | The training dummies: the seed with the player's own list, the captures and `/ct dummy` (both clients) |
| `modules/Identity.lua` | Who fought, where and against what, and the board key |
| `modules/Fight.lua` | The fight state machine, one fight per meter session |
| `modules/Watchers.lua` | The fight's game events, one set per fight state |
| `modules/CastCodec.lua` | The packed cast-list string a record stores, pure |
| `modules/Casts.lua` | Each fight's cast list, from the lanes' capture |
| `modules/Usage.lua` | What a fight used: on-use gear and consumables |
| `modules/Stats.lua` | The character's stats at the fight's start, completed after combat |
| `modules/Loadouts.lua` | The interned equipment sets (and their recon) and talent loadouts a fight refers to |
| `modules/Filters.lua` | The recording filters a fight must pass to be stored |
| `modules/Bests.lua` | Personal bests, worked out from the stored fights |
| `modules/Recorder.lua` | The fight record and the store |
| `modules/Retention.lua` | The purge, its daily timer and `/ct purge`, and the store's size |
| `modules/Slices.lua` | The damage chart's in-session store |
| `modules/Format.lua` | Every number the UI draws, secret-safe |
| `modules/Style.lua` | The look the HUD and the Results window share |
| `modules/Hud_Appearance.lua` | The HUD's configured look |
| `modules/Hud_Tips.lua` | The words of the HUD's tooltips |
| `modules/Hud_Best.lua` | The pace data: what the paced fight had done by each second |
| `modules/Hud_Breakdown.lua` | The HUD's spell rows, live and after combat |
| `modules/Hud_Chart.lua` | The HUD's damage chart and pace bar |
| `modules/Hud_States.lua` | The HUD's two bodies, the live view and the fight-over card |
| `modules/Hud.lua` | The HUD's shell: the window, when it opens and fades, and the view the bodies draw |
| `modules/Sizing.lua` | The one smooth-resize pattern every resizable window uses |
| `modules/Results_Source.lua` | Where the Results window reads fights: the store, or the sample history |
| `modules/Results_Table.lua` | The sortable pooled list and the small drawing helpers |
| `modules/Results_Tips.lua` | What every cell and header says on hover |
| `modules/Results_Fights.lua` | The filter bar, the grouping and the fight list |
| `modules/Results_Loadout.lua` | The detail's Gear and Talents |
| `modules/Results_Usage.lua` | The detail's Usage list and its edit, and the list's Used icons |
| `modules/Results_Targets.lua` | The detail's Targets list: each enemy your damage reached and how much it took (issue #6) |
| `modules/Results_Detail.lua` | One fight in full |
| `modules/Share.lua` | The one-line chat summary of a fight |
| `modules/Results_TimelineData.lua` | The ability timeline's pure half |
| `modules/Results_Timeline.lua` | The ability timeline window |
| `modules/Results_TimelineMarks.lua` | The timeline's cast marks on the same `NS.ResultsTimeline`: By ability's icons or ticks (`results.timelineMarks`), the caster colors and every cast icon's art and edge |
| `modules/Results_Gear.lua` | The gear view window |
| `modules/Results_Compare.lua` | The compare window |
| `modules/Results.lua` | The Results window's shell, the row menu and its public toggles |
| `modules/MockRotations.lua` | The sample rotation per client, data only |
| `modules/MockFights.lua` | The sample history and the sample fight |
| `modules/Preview.lua` | Test mode and the sim's shared shell |
| `modules/Sim.lua` | `/ct sim`: a made-up fight in real time, its scenarios and its step session |
| `modules/Diagnostics.lua` | This addon's sections of `/ct diagnostics` |
| `settings/Schema.lua` | The schema array and the one write seam |
| `settings/Slash.lua` | `NS.COMMANDS` and the slash descriptor |
| `settings/OptionsSetup.lua` | The LibKa0s-Options descriptor (`NS.Helpers`) and `NS.RegisterTabbedPage` |
| `settings/General.lua` | The General page: Master controls, Look and skin, Keybindings |
| `settings/Lanes.lua` | The Lanes page and the `/ct lane` verb |
| `settings/Hud.lua` | The DPS HUD page |
| `settings/History.lua` | The History page |
| `settings/Profiles.lua` | The Profiles page |

## Not shipped

| Path | Job |
|---|---|
| `tests/run.lua` | The runner: load list, lifecycle kick, suite list |
| `tests/wow_mock.lua`, `tests/mock_meter.lua`, `tests/mock_formatter.lua`, `tests/hud_fixture.lua` | The client mock, the scripted meter, the scripted number formatters and a HUD fixture |
| `tests/skin_surfaces.lua` | The painted surfaces the skin-switch gate walks |
| `tests/test_*.lua` | The suites ([`test-cases.md`](test-cases.md) lists every case) |
| `tools/make_logo.py` | Draws the logo files in `media/logos/` |
