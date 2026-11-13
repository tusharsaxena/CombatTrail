# Module map — Ka0s Combat Trail

Every non-vendored file the addon ships, in TOC load order, with its one job (documentation-§3, Tier
1). Each file's own header says the same in more words, and each LOAD-BEARING note in
`CombatTrail.toc` says what that file resolves at file scope.

## Load order and why

- **Libraries first** (`libs/`, vendored): LibStub, CallbackHandler, Ace3, then `LibKa0s.xml` as one
  line (its own file list), then LibSharedMedia, LibDataBroker and LibDBIcon. Panel Master's copies,
  the set that loads on both clients.
- **The locale** next: `locales/enUS.lua` creates `NS.L`, which several `core/` files read at file
  scope; its topic files `locales/enUS_Race.lua` and `locales/enUS_Insights.lua` fill it directly after
  (localization-§6).
- **`core/`** in dependency order: the namespace and media first, then the skin seam (before any
  frame-building file), the compat root (before the secret guards bind), the latch (before the perf
  harness, which raises without it), and the AceAddon promotion after the printer exists.
- **`defaults/`**: the ignore seeds before the profile tree that reads them.
- **`modules/`** in conventional order. Each reaches the others at call time, except where a module
  registers its bus receiver or captures a neighbor at file scope (the TOC names each one). Two Race
  mode cases: `modules/RaceClock.lua` follows `modules/RaceWatchers.lua` and registers its bus receiver
  at file scope; `modules/RaceWindow_Board.lua` and `modules/RaceWindow_States.lua` follow
  `modules/Hud_States.lua`, whose colors both read at file scope, and the board comes first, as the
  bodies read its layout constants there.
- **`settings/` last**: the schema and the slash table first, the options descriptor, then the pages
  in panel order (General first, Profiles last), because the page order is the registration order.

## Files

| File | Job |
|---|---|
| `CombatTrail.toc` | Both interface numbers, the metadata and the load order |
| `Bindings.xml` | The three shared `CLICK` key bindings in the addon's own category, the file WoW Forever reads |
| `Bindings_Mainline.xml` | Retail's bindings file: the same three plus *Toggle Race window* after Results, held in step with `Bindings.xml` by `tests/test_bindings.lua` (a documented deviation) |
| `locales/enUS.lua` | `NS.L`, the canonical locale with the key-is-the-string fallback |
| `locales/enUS_Race.lua` | Race mode's strings, a topic file filling `NS.L` (ruling X13) |
| `locales/enUS_Insights.lua` | The Insights tab's strings, a topic file filling `NS.L` (Race mode plan D2) |
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
| `core/ToastSetup.lua` | `NS.NewToast`, the alert-toast shell from LibKa0s-Toast, and its degraded stub |
| `core/CalloutSetup.lua` | `NS.NewCallout`, the center-screen call-out from LibKa0s-Callout, its degraded stub, the shipped voice packs and the settings defaults |
| `core/ChartsSetup.lua` | `NS.Charts` (LibKa0s-Charts) and `NS.ChartsHost()`, the Results window's look for the Insights charts |
| `core/LifecycleSetup.lua` | The one stand-down latch and the modules it suspends and resumes |
| `core/PerfSetup.lua` | `NS.Perf`, the performance harness and its buckets |
| `core/DebugLogSetup.lua` | `NS.DebugLog`, the gated `NS.Debug` sink and the diagnostics descriptor |
| `core/LauncherSetup.lua` | The minimap button and broker row, and the three binding buttons |
| `core/CombatTrail.lua` | AceAddon registration, `NS.RegisterGameEvents`, and the host handlers every surface shares |
| `core/Database.lua` | AceDB setup, the profile callbacks and the migration runner |
| `defaults/IgnoreSeeds.lua` | Each lane's ignored spells out of the box, per client |
| `defaults/Profile.lua` | The AceDB defaults tree, the only place a default is written |
| `defaults/Dummies.lua` | The measured training dummies' seed, per client, with each dummy's category |
| `defaults/Hearthstones.lua` | Every hearthstone variant's spell ID, which the late-cast ignore list's 8690 stands for |
| `modules/LaneCasts.lua` | The lanes' cast capture: one `LANE_PUSH` per shown cast, dedupe and interrupt marks |
| `modules/LaneLayout.lua` | The lanes' layout math, pure |
| `modules/LaneRender.lua` | Each lane's frame, ticks, label and pooled icons, and its `OnUpdate` while icons show |
| `modules/LaneAnchor.lua` | Where a lane sits (free, docked, unit frame), its strata and level, and the edit overlay |
| `modules/LaneVisibility.lua` | When a lane shows and how opaque it is |
| `modules/LaneIgnore.lua` | Each lane's ignore list and the `/ct ignore` verb |
| `modules/Meter.lua` | The only reader of `C_DamageMeter`: sessions, the live read (`Meter.ShareLive` lets the HUD's beat and the slices' boundary tick share one read in a frame) and the after-combat read |
| `modules/ProbeCurve.lua` | `/ct probe`'s spell color curve trial (issue #7): can the client map a secret spell ID to a color |
| `modules/Probe.lua` | `/ct probe`, the in-game report of what the client answers |
| `modules/Dummies.lua` | The training dummies: the seed with the player's own list, the captures and `/ct dummy` (both clients) |
| `modules/Identity.lua` | Who fought, where and against what, and the board key |
| `modules/Fight.lua` | The fight state machine, one fight per meter session |
| `modules/Watchers.lua` | The fight's game events, one set per fight state |
| `modules/RaceTimeline.lua` | A race's damage-update stamps: the tail after the buzzer and the restart, pure (Race mode) |
| `modules/LateIgnore.lua` | The late-cast ignore list, read when a race is scored (Race mode, both clients) |
| `modules/RaceScoring.lua` | A race's scoring rules: the late-cast test, the race DPS and its flags (Race mode) |
| `modules/Race.lua` | The race engine on the fight: arm, the first-hit clock, the buzzer, the late casts, the race part, the pending slot and the resume after a `/reload` (Race mode, Retail) |
| `modules/RaceWatchers.lua` | The race's game events, one set per race state (Race mode, Retail) |
| `modules/RaceClock.lua` | The race beat: one timer at `Hud.RefreshInterval()` (1 / `hud.refreshRate`, default 0.1 s) while a race (real or sample) runs or stops, which stands the HUD's own beat down (`Hud.SyncBeat`); each fire calls `Hud.OnRaceClock()` (the HUD's read and redraw), then sends one `RACE_CLOCK` for the Race window (Race mode, Retail) |
| `modules/AutoArm.lua` | Auto-show and auto-arm near a training dummy: the target and nameplate events, the debounced hide, the Race window's five hooks and the DPS HUD's four, and `AutoArm.InSession`, which ties a Race window the player opens in a dummy session to it (Race mode, Retail) |
| `modules/RaceVerb.lua` | `/ct race`'s words: arm with a typed length, cancel, the Race window, the late-cast ignore list; the arm refusals' copy (Race mode, Retail) |
| `modules/CastCodec.lua` | The packed cast-list string a record stores, pure |
| `modules/Casts.lua` | Each fight's cast list, from the lanes' capture |
| `modules/Usage.lua` | What a fight used: on-use gear and consumables |
| `modules/Stats.lua` | The character's stats at the fight's start, completed after combat |
| `modules/Loadouts.lua` | The interned equipment sets (and their recon) and talent loadouts a fight refers to |
| `modules/Filters.lua` | The recording filters a fight must pass to be stored |
| `modules/RaceRecord.lua` | The fight record's `race` part: its plain copy, the race DPS, its flags (Race mode) |
| `modules/Bests.lua` | Personal bests, worked out from the stored fights: fight boards, race boards and their clean view |
| `modules/Recorder.lua` | The fight record and the store |
| `modules/Retention.lua` | The purge, its daily timer and `/ct purge`, and the store's size |
| `modules/Slices.lua` | The damage chart's in-session store |
| `modules/Format.lua` | Every number the UI draws, secret-safe; `Format.RaceClock`, the one count of tenths the race's elapsed time and time left share |
| `modules/Style.lua` | The look the HUD and the Results window share; `Style.FitControlArt`, which crops each header control's mark to its measured box (`Style.ART_BOX`) and sizes its long side to `Style.CONTROL_ART` |
| `modules/Hud_Appearance.lua` | The HUD's configured look |
| `modules/Hud_Tips.lua` | The words of the HUD's tooltips |
| `modules/Hud_Best.lua` | The pace data: which stored fight the live one is paced against (`Best.PaceRecord`, the HUD's `Hud.PaceRecord`), its target line and curve, and what it had done by each second |
| `modules/Hud_Breakdown.lua` | The HUD's spell rows, live and after combat |
| `modules/Hud_Chart.lua` | The HUD's damage chart and pace bar; `Chart.NewPace(parent, opts)` also builds the Race window's thinner mini pace bars |
| `modules/Hud_States.lua` | The HUD's two bodies, the live view and the fight-over card |
| `modules/Hud.lua` | The HUD's shell: the window, when it opens and fades, and the view the bodies draw; `Hud.Dock`, the frame an attached Race window stands beside, and `Hud.Height`, the height it takes; `Hud.HideWithRace`, the toggle's closing half, which closes an open Race window with the HUD; `Hud.ShowForRace`, the race's open of the HUD under the Race window, and `Hud.OnRaceIdle`, the race's idle edge that lets it go or starts its fade (no fade while a race holds it, W29); `Hud.LiveDamage`, the last live read's player total the Race window draws (and whether the pet has its own source); `Hud.Toggle`, whose open takes the Race window too near a dummy; `Hud.SyncBeat`, the HUD's own beat at `hud.refreshRate` outside a race (one read and the whole redraw), `Hud.RefreshInterval`, the rate both beats run at, and `Hud.OnRaceClock`, the race beat's direct call; `Hud.OnRaceArmed`, the reset to the pre-fight look; the title bar's Race button (the flag, gold under the pointer only) (Retail) |
| `modules/RaceWindow_Best.lua` | The Race window's Your best card: the race board's best for the dummy targeted and the length picked, and `Best.Figure`, the labeled Damage and DPS pair on one row that Best to beat and Best by now share (Race mode, Retail) |
| `modules/RaceWindow_Board.lua` | The race board's figures the Race window draws: Best by now and the Checkpoints (the best's straight line, the player's figure as *Current* and their mini pace bars), Against your best and Top races on one column grid, `Board.Spread` (the result card's rows and gaps in a taller window) and `Board.ClockColor` (the countdown's and the time bar's green to amber to red) (Race mode, Retail) |
| `modules/RaceWindow_States.lua` | The Race window's six bodies: idle, armed, running, Stop!, waiting, the result card, and the layouts that stretch them to the window's size: `States.ResultLayout`, `States.IdleLayout`, `States.RunningGap` (Race mode, Retail) |
| `modules/RaceWindow.lua` | The Race window's shell: flush beside the DPS HUD (at its height on the left or right) or on its own, its size and resize grip, when it shows, the view and the acts (Race mode, Retail) |
| `modules/Countdown.lua` | A race's final seconds on the addon's one call-out (`NS.Callout`): the center numbers counted to the race's endsAt, spoken, and STOP at the buzzer (Race mode, Retail) |
| `modules/BestToast.lua` | The new-best toast: a race's (Retail) or a fight's (both clients) new best on its board |
| `modules/Sizing.lua` | The one smooth-resize pattern every resizable window uses |
| `modules/Results_Source.lua` | Where the Results window reads fights: the store, or the sample history |
| `modules/Results_Table.lua` | The sortable pooled list and the small drawing helpers |
| `modules/Results_Tips.lua` | What every cell and header says on hover |
| `modules/Results_Fights.lua` | The filter bar, the grouping and the fight list |
| `modules/Results_Races.lua` | Races in the list: the Fights / Races / All filter and the race filters, the race groupings, a race row's chips, score and time raced, the race cells' tooltips (Retail controls; Race mode plan D1) |
| `modules/Results_Loadout.lua` | The detail's Gear and Talents |
| `modules/Results_Usage.lua` | The detail's Usage list and its edit, and the list's Used icons |
| `modules/Results_Targets.lua` | The detail's Targets list: each enemy your damage reached and how much it took (issue #6) |
| `modules/Results_RaceDetail.lua` | A race's detail: the Timing strip and the Flags box, its score and race DPS, the late-cast right-click (Retail; Race mode plan D1) |
| `modules/Results_Detail.lua` | One fight in full |
| `modules/Share.lua` | The one-line chat summary of a fight or a race, and the race's own lines on the arm and at its result |
| `modules/Results_TimelineData.lua` | The ability timeline's pure half |
| `modules/Results_Timeline.lua` | The ability timeline window |
| `modules/Results_TimelineMarks.lua` | The timeline's cast marks on the same `NS.ResultsTimeline`: By ability's icons or ticks (`results.timelineMarks`), the caster colors and every cast icon's art and edge |
| `modules/Results_Gear.lua` | The gear view window |
| `modules/Results_Compare.lua` | The compare window |
| `modules/Results_InsightsData.lua` | The Insights tab's pure half: its filters, the faceted options with counts, the one stats pass (Race mode plan D2) |
| `modules/Results_Insights.lua` | The Insights tab: its filter bar, the stat cards and the chart sections over every saved fight, races as a filter (Race mode plan D2) |
| `modules/Results.lua` | The Results window's shell, its Fights and Insights tabs, the row menu and its public toggles |
| `modules/MockRotations.lua` | The sample rotation per client, data only |
| `modules/MockFights.lua` | The sample history and the sample fight |
| `modules/MockRaces.lua` | The sample races beside the sample fights, and the sample race test mode and the sim race (Retail only, Race mode plan E1) |
| `modules/RaceSample.lua` | The sample race: the stand-in for `NS.Race` the Race window and the countdown read in test mode and the sim (Retail only, Race mode plan E1) |
| `modules/Preview.lua` | Test mode and the sim's shared shell; `/ct test race` |
| `modules/SimRace.lua` | The sim's eight race scenarios: their script, steps and gate (Retail only, Race mode plan E1) |
| `modules/Sim.lua` | `/ct sim`: a made-up fight in real time, its scenarios and its step session |
| `modules/Diagnostics.lua` | This addon's sections of `/ct diagnostics` |
| `settings/Schema.lua` | The schema array and the one write seam |
| `settings/Slash.lua` | `NS.COMMANDS` and the slash descriptor |
| `settings/OptionsSetup.lua` | The LibKa0s-Options descriptor (`NS.Helpers`) and `NS.RegisterTabbedPage` |
| `settings/General.lua` | The General page: Master controls, Look and skin, Keybindings |
| `settings/Lanes.lua` | The Lanes page and the `/ct lane` verb |
| `settings/Hud.lua` | The DPS HUD page |
| `settings/History.lua` | The History page |
| `settings/Race.lua` | The Race mode page: the switch, the Race tab, the late-cast ignore list, the Race window's place and height, and its size rows the grip writes (Retail only) |
| `settings/Profiles.lua` | The Profiles page |

## Not shipped

| Path | Job |
|---|---|
| `tests/run.lua` | The runner: load list, lifecycle kick, suite list |
| `tests/wow_mock.lua`, `tests/mock_meter.lua`, `tests/mock_formatter.lua`, `tests/hud_fixture.lua` | The client mock, the scripted meter, the scripted number formatters and a HUD fixture |
| `tests/race_fixture.lua`, `tests/insights_fixture.lua` | Race mode's fixtures: a race armed, run and read on the scripted meter, and the saved fights and races the Insights suites read |
| `tests/skin_surfaces.lua` | The painted surfaces the skin-switch gate walks |
| `tests/test_*.lua` | The suites ([`test-cases.md`](test-cases.md) lists every case) |
| `tools/make_logo.py` | Draws the logo files in `media/logos/` |
