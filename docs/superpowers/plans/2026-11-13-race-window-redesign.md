# Race window redesign: implementation plan

> **For agentic workers:** steps use checkbox (`- [ ]`) syntax. One implementer per task, in ledger order (the
> tasks share files, so none run in parallel). The orchestrator reviews each diff and runs the gate between tasks.

**Goal:** On Retail in Race mode, the DPS HUD and the Race window work as one panel. Both open near a
training dummy, the HUD's header opens the Race window, the docked Race window sits flush at the HUD's
height, both clocks move on one beat during a race, and the Race window's running and result screens drop
the duplicated pace bar and fill the space with race-only facts.

**Design source:** the owner-approved mockup, revision 2 (2026-11-13),
https://claude.ai/artifact/Fq8QF27NPurVto3rmsGAs2 . The owner's rulings:

| # | Ruling |
|---|---|
| O1 | Sizing: the Race window keeps ONE fixed size and fills it (mockup option B). No Fixed / Dynamic setting. |
| O2 | Clock: one countdown (Left only) is the default: `race.clock` defaults to `"left"` (the row stays; a profile that saved `"both"` keeps it). |
| O3 | Docked LEFT or RIGHT, the Race window takes the HUD's height (`raceWindow.matchHud`, on). TOP or BOTTOM: its own height. |
| O4 | The HUD's auto-show near a dummy is its own setting, `race.autoShowHud`, on by default. |
| O5 | Two rhythms: a fight that is not a race keeps the HUD's clock on FIGHT_TICK (4 Hz), unchanged. During a race (running or stopping, real or sample), ONE 0.1 s timer drives the HUD's clock AND the Race window's clocks, in the same frame. Meter reads (damage, DPS, chart, spells, pace) stay on FIGHT_TICK. This supersedes the earlier "never change the HUD" tenet, by the owner's word. **Superseded in part (owner, 2026-11-13, W21):** a fight that is not a race now draws its clock on the HUD's own beat at `hud.clockRate`, not on FIGHT_TICK, and the race beat runs at `race.clockRate`; the meter reads stay on FIGHT_TICK. **Superseded again (W24):** one rate, `hud.refreshRate`, drives every live part of both windows; each beat is one meter read and the whole redraw, and FIGHT_TICK keeps the slices and Fight's scan. |
| O6 | HUD header order, left to right: Results, Race, Settings, Lock, Close. The Race button's icon is `gi:checkered-flag`. **Superseded in part (owner, 2026-11-13, W15):** the icon is Open Iconic's plain `flag`, and `gi:checkered-flag` is gone from the declaration, `libs/` and the README credit. The order stands. |

**Global constraints (every task):**
- The Ka0s WoW Addon Standard, `CLAUDE.md`. A deviation is STOPPED and flagged, never made silently.
- Never edit `libs/` or `tests/_kit/`, except Task W1's declared-icon copy, which is the prune contract run in reverse
  (the files come byte-for-byte from LibKa0s tag v1.94.0, and `tests/test_vendor_sync.lua` judges it).
- Secret values (spec §3): no Lua operator, comparison or concatenation on a live meter value. Every figure the new
  Race window bodies draw comes from a stored record, the race best's straight line (`NS.HudBest.RaceCurve`) or
  `GetTime()`. The window never says "ahead" or "behind".
- Line endings: every file is CRLF (`.gitattributes`); the `eol` test fails a bare LF. Write through a tool that
  keeps CRLF.
- Strings through `NS.L`, defined in `locales/enUS_Race.lua` (Race window) or `locales/enUS.lua` (HUD).
- Retail only for anything race: gated by `NS.Compat.ForClient({ "retail" })` and `NS.RaceMode.On()`; nothing new
  shows or registers on WoW Forever.
- Test first: a failing case, then the code. Gate before reporting a task done: `lua tests/run.lua`,
  `KA0S_KIT_CLIENT=forever lua tests/run.lua`, `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` (0/0),
  `~/.claude/dev-copilot/bin/ka0s-bounded lizard -C 15 -x "./libs/*" -x "./tests/_kit/*" .` (no warning).
- No commits, no staging, no version bump (the owner commits).
- Keep each module's header comment true: a behavior change updates the header's prose in the same task.

---

## Status ledger (resume here)

| Task | Title | Status | Notes |
|---|---|---|---|
| W1 | Checkered-flag icon declared and vendored | done | gate green (vendor sync passes); README and CLAUDE.md credit. **Superseded by W15:** the checkered flag is gone, the Race button draws Open Iconic's `flag` |
| W2 | HUD header Race button | done | gate green; the lit state it shipped with (`Style.SetControlLit`, the RaceWindow-to-HUD tell) was removed in W11: the flag is gold only under the pointer |
| W3 | The HUD's auto-show near a dummy | done | gate green; asked once per dummy session; a dummy-opened HUD stays up through the first hit whatever `hud.show`; `docs/settings-panel.md` gained the one Key row `test_docs` requires (rest of docs is W8; `docs/schema.md` still says `"both"`) |
| W4 | Flush dock at the HUD's height | done | gate green; the HUD tells the window on each height change (`Hud.Height`, `RaceWindow.OnHudResized`); the view carries the content `height`; the bodies already fill the content, so W6/W7 lay out against it; `settings-panel.md` gained only the Key row |
| W5 | One race beat for both clocks | done | gate green; `modules/RaceClock.lua` after RaceWatchers in the TOC and the lifecycle list; RaceSample's mutators call `RaceClock.Sync` (a sample's beat is the one payload-free bus message it causes); `raceClock` perf bucket; Diagnostics prints `matched` and `race beat on`; test_docs forced one module-map row and the hub's RaceClock / RACE_CLOCK mentions (rest of the docs is W8) |
| W6 | Running body: one countdown, time bar, best to beat, best by now, checkpoints | done | gate green; new `modules/RaceWindow_Board.lua` (Best by now, Checkpoints, the tables; TOC before RaceWindow_States, module-map row, hub list); the window no longer reads the meter at all (its FIGHT_TICK ReadLive went with the pace bar); CONTENT_H is now the tallest stack's (314, was 262; 354 since W12, 360 since W28) |
| W7 | Result and idle bodies: no pace bar; Against your best; This board | done | gate green; new `Bests.Ranked` (the all-races board, flagged complete races in, as Your best and the vs best chip rank); Against your best is set against `Bests.Before`; idle This board reads the store, the result's the sample history for a sample; tests in `tests/test_race_window_board.lua` |
| W8 | Docs, smoke tests, test inventory, README | done | gate green; hub (17 messages, feature rows for the Race button and the race beat), module map, message bus (RACE_CLOCK, RaceWindow off FIGHT_TICK, the sample-beat exception), schema, settings panel, data flow, performance (`raceClock`), debug, known limitations, slash dispatch, smoke SM-CT-RM48 to RM54 (RM7, RM8, RM11, RM17, RM34, RM45, RM47 brought in line), README, test-cases regenerated; a dated amendment note in the Race mode spec §4.2 |
| W9 | Auto-show: the player's open in a dummy session | done | no commit; new `AutoArm.InSession()`; `RW.Show()` ties a window the player opens in a live dummy session to it (walking away closes it, the next session reopens it); one open before the session stays the player's; a close in the session still holds it shut; Attach and Detach change none of it; smoke SM-CT-RM34, RM55 |
| W10 | The HUD toggle takes the Race window; a Retail Race window key | done | no commit; new `Hud.HideWithRace()`: the HUD's toggle (key, launcher *Show window*, `/ct hud toggle`) and `/ct hud hide` close both, each a player's close; opening opens the HUD alone; the HUD's close mark and Escape, `/ct race toggle` and the flag touch one window. New root `Bindings_Mainline.xml` (four keys, Retail), `Bindings.xml` keeps three for WoW Forever; button `CombatTrailToggleRace` and its `NS.BINDINGS` row under `ForClient` (core/LauncherSetup.lua); a documented deviation (toc-file-§3, layout-§1, launcher-§6) in `docs/ARCHITECTURE.md`, superseding ruling X18; smoke SM-CT-RM56 to RM58 (RM58, WoW Forever's key list, is mandatory) |
| W11 | The Race button's lit state removed | done | no commit; gone: `Style.SetControlLit`, `Hud.OnRaceWindowShown`, `RaceWindow.WindowShown` and the tell; the flag is gold only under the pointer, after a `/reload` too; smoke SM-CT-RM49 |
| W12 | Result screen declutter | done | no commit; no time raced row (an incomplete race's time is on the Time chip); the vs best chip dropped beside the table; *This board* renamed *Top races*; both tables on one column grid (`Board.LEAD_W`); `States.ResultLayout` and `Board.Spread` grow the rows and heading gaps in a taller window, up to `ROW_MAX` and `GAP_MAX`; every heading FONT.SECTION on `Style.SECTION_H` (22); `CONTENT_H` 314 to 354 (360 since W28); smoke SM-CT-RM53, RM54, RM61 |
| W13 | Running screen: a depleting colored bar, your figures beside the best's | done | no commit; the time bar empties to the buzzer; it and the countdown blend green to amber to red (`Board.ClockColor`: green until half the race, red from 10 s left on the countdown's tenths, a race of 20 s or less green straight to red; tokens `ct.ahead`, `ct.caution`, `sem.statusBad`); *Best by now* shows Best and You, and each Checkpoint the best's figure, yours as the clock passed it and the time (`best · you`, `CP_H` 40); You is the HUD's last read (`Hud.LiveDamage`, text only, no second meter read); the readings are held in memory for the race alone; text only by the owner's choice (no pace bar, no difference); the running worst case is 323 of 354 (it sets `CONTENT_H` at 360 since W28); smoke SM-CT-RM52, RM59, RM60. **Superseded in part by W23:** *You* is *Current*, the note `best · current`, `CP_H` 48, and the running screen gains mini pace bars |
| W14 | The toggle opens both near a dummy | done | no commit; `Hud.Toggle`'s open takes the Race window (`RW.Show`, tied to the session) when Race mode, `race.autoShow` and `AutoArm.InSession()` are on, even after a close earlier in the session; away from a dummy and for `/ct hud show`, the HUD alone; closing still closes both; smoke SM-CT-RM56, RM62 |
| W15 | The plain flag; header icons one size | done | no commit; the Race button draws Open Iconic's `flag`; `gi:checkered-flag` gone from CLAUDE.md, `libs/` and the README credit (supersedes O6's icon and W1); `Style.FitControlArt` crops each mark to `Style.ART_BOX` and scales its long side to `Style.CONTROL_ART` 12, on every window's header controls (the library's close through `NS.MakeCloseButton` too); smoke SM-CT-RM49, RM67 |
| W16 | The HUD resets on an arm | done | no commit; `Hud.OnRaceArmed` (RACE_ARMED) lets go the fight on screen and draws the pre-fight look; a live fight is never dropped; smoke SM-CT-RM63 |
| W17 | One count of tenths for the race clocks | done | no commit; `NS.Format.RaceClock`: the elapsed truncates, the time left rounds up, the two sum to the length, 0:00.0 only at the buzzer; the center countdown keeps "1 from 1 s left until the buzzer"; smoke SM-CT-RM60, RM64 |
| W18 | The last checkpoint at the buzzer | done | no commit; `endBoard` in `stopView` takes the fourth checkpoint with the HUD's last read; smoke SM-CT-RM65 |
| W19 | The Race window's resize grip; the bodies stretch | done | no commit; the grip shows only while unlocked: width alone when matched left or right, else width and height; least 260 by the content height; new skipRender rows `raceWindow.width` (260, 260 to 600) and `raceWindow.height` (0, 0 to 1000; 0 is the content height); `States.IdleLayout`, `States.RunningGap` (gaps 2 to 24), `States.RunningFloor`, a `lines` argument on `RunningNeed`; `Board.PlaceCaption` takes a width; running worst case, two chip lines at the largest clock, 344 of 354 at the gaps' floor (since W28 that worst case, plus 4 slack, is `CONTENT_H` itself: 360); smoke SM-CT-RM66 |
| W20 | Checkpoints on the Stop! and waiting screens | done | no commit; shown under their own figures when there is a best and they fit, all four after the buzzer; smoke SM-CT-RM65 |
| W21 | Clock refresh rate settings | done | **Superseded by W24** (both settings retired). no commit; `hud.clockRate` (DPS HUD → Clock and figures → Clock refresh) and `race.clockRate` (Race mode → Race → Clock), 4, 5, 10 or 20 a second, default 10, shared as `NS.CLOCK_RATE_CHOICES`; outside a race the HUD's own beat (`Hud.SyncClock`) redraws the clock label alone, no meter read; RACE_CLOCK at `race.clockRate`; `RaceClock.Sync` calls `Hud.SyncClock`; perf bucket `hudClock`; `Hud.Diagnose` answers `clockEvery`, `RaceClock.Diagnose` `every`; the footer's "live · 4 Hz" (the meter's read rate) unchanged; supersedes O5's plain-fight clock; smoke SM-CT-RM51, RM68, RM69 |
| W22 | The pet's pace reference | done | no commit; `Hud.LiveDamage` answers a third value, `petOwn`; the views carry `v.paceRef` and `cp.paceRef` (the best's player-only line) when the pet has its own source and the best has a player figure, else the bars range on the best's whole figure; smoke SM-CT-RM70 |
| W23 | Running screen: colors, labels and mini pace bars | done | no commit; *You* is *Current*; labels dim gold (`text.headingAlt`), Best blue (`ct.info`), Current white (`ct.text`); Best by now gains a 4px HUD-style pace bar (track and tick) over its box, ranged by `HudBest.Bounds(byNow)` at the HUD's Pace range; Checkpoint cells (`CP_H` 48): the time, the best, Current, then a bare 3px bar at 75% width, centered, hidden until captured; passed best figures dim to alpha 0.55; the note reads `best · current`; `Chart.NewPace(parent, opts)` (`barH`, `bare`, `tip`) with `SetRange`, `SetTotal` and `Blank` split out; supersedes W13's text-only screen by the owner's later request; smoke SM-CT-RM52, RM59, RM70, RM71. **Superseded in part by W27 and W28:** the Best by now layout and the cell sizes |
| W24 | One refresh rate for both windows | done | no commit; `hud.refreshRate` (*HUD refresh rate*, DPS HUD → Behavior → Refresh, 4, 5, 10 or 20 a second, default 10, both clients) replaces `hud.clockRate`; `race.clockRate` removed; every beat one `Meter.ReadLive` and the whole HUD redraw: `Hud.SyncBeat` (was `SyncClock`) outside a race, RaceClock at `Hud.RefreshInterval()` in one, calling `Hud.OnRaceClock()` before its `RACE_CLOCK` (the HUD no longer hears it; the Race window redraws on that read); FIGHT_TICK 4 Hz for the slices and Fight's scan, the HUD's only to go live or as a fallback; the real fight read only while Fight holds it in combat; `Meter.ShareLive` lets the beat and the slices' boundary tick share a read in a frame; the footer reads the rate (`live · %d Hz`); `hudClock` bucket and `Hud_States`' `clockOnBeat` gone; `Hud.Diagnose` answers `beatEvery`; supersedes O5 again and W21; smoke SM-CT-RM51, RM68, RM69 |
| W25 | The time bar looks like the pace bar | done | no commit; no border, a `ct.pace.track` background, an 8px bar on a 12px line, quarter ticks in `ct.pace.tick`; it still empties and blends green to amber to red; smoke SM-CT-RM52, RM60 |
| W26 | Best card labels | done | no commit; Best to beat and the idle Your best card show labeled Damage and DPS on one row, labels `text.headingAlt`, both values in the text face and the dim color; the big DPS figure gone; `NS.RaceWindowBest.Figure`; smoke SM-CT-RM52, RM54, RM71 |
| W27 | Best by now: no overlap | done | no commit; Best by now uses `Best.Figure`: each value `NS.RaceWindowBest.LABEL_W` (44px) after its label, two anchors holding it inside its half; `NOW_FIG_X` gone; smoke SM-CT-RM52 |
| W28 | Checkpoint cell sizing | done | no commit; the time `FONT.HEADING` (12px, dim gold), the figures `FONT.TEXT` (10px), rows at 4, 19 and 31, the bar's line at 43, the bar 90% wide, `CP_H` 54; `CONTENT_H` 354 to 360, set by the running worst case (the largest clock, two chip lines, gaps at the 2px floor, plus 4 slack); smoke SM-CT-RM52, RM71 |
| W29 | The Race window never without the DPS HUD | done | no commit; owner tenets T1 (never up while the HUD is hidden) and T2 (auto open and close in step). D1: `RaceWindow.IsShown` asks `Hud.IsShown`; every `Hud.Refresh` ends in `RaceWindow.FollowHud`, so the fade, the overCard close, the HUD's close mark and the stand-down hide it still wanted and the HUD's return brings it back; only its own close (its mark, `/ct race hide|toggle`, Escape on it) or an auto-close rule clears `wanted`; Escape closes both, each counted, whichever the close list reaches first (the HUD's onHide closes a Race window still up). D2: no fade or overCard close while the race, real or sample, is not idle (`raceHolds`); `Hud.OnRaceIdle` starts it at the idle edge. D3: each Race window open opens the HUD first: `Hud.Show` (the player's: key, slash, flag, stand-up, Race mode back on), new `Hud.ShowForRace` (arm, resume, result, sample; let go at the idle edge), `Hud.ShowNearDummy` (a dummy session). D4: auto-show is on while `race.autoShow` or `race.autoShowHud` is on (*Show the DPS HUD near a training dummy*, no longer grayed); `Hud.ShowNearDummy` opens again after a fade, and a HUD the player closed holds both shut for the session. Also a profile switch re-decides `hud.show` "always". The pace lookup moved from `Hud.lua` to `Hud_Best.lua` (`Best.PaceRecord`) to keep `Hud.lua` under layout-§1's cap; smoke SM-CT-RM48, RM56, RM62, RM72 to RM76 |
| W30 | Held up near a dummy | done | no commit; owner 2026-11-13: the HUD neither fades nor closes with its fight while a dummy session lasts (Hud.lua `dummyHolds`), so both windows stay while the player stands near the dummy; the session's end closes a HUD it opened or starts the fade of one it held (`Hud.HideAwayFromDummy`); test_autoarm's W29 #6 test rewritten; smoke RM72, RM75 revised |

---

### Task W1: Checkered-flag icon declared and vendored

**Files:** `CLAUDE.md` (the `LibKa0s icons:` line gains `gi:checkered-flag`, kept in the line's order), copy from
`git -C ../LibKa0s archive v1.94.0`: `LibKa0s/media/icons/game-icons/checkered-flag.tga`, `AUTHORS.txt`,
`LICENSE-game-icons.txt` into `libs/LibKa0s/media/icons/game-icons/`; `README.md` (the icon credits paragraph:
game-icons.net, CC BY 3.0, the checkered flag by Delapouite).

- [ ] `tests/test_vendor_sync.lua` passes with the new declaration (it fails first with the line changed and the file absent).

### Task W2: HUD header Race button

**Files:** `modules/Hud.lua` (buildHeader, applyLock or a new apply step, Act), `modules/RaceWindow.lua` (a
shown-state hook the HUD reads), `locales/enUS.lua`, a test file (`tests/test_hud_race_button.lua` or the HUD's own suite).

- Built only on Retail; shown only while Race mode is on (`NS.RaceMode.On()`), re-decided on SETTINGS_CHANGED
  for the Race mode switch. Header right list, outermost first: Close, Lock, Settings, Race, Results, so it reads
  Results, Race, Settings, Lock, Close left to right (O6). With the button hidden, the strip closes up.
- Click: `NS.SetRaceWindowShown` toggle (the player's open, as `/ct race toggle`). Tooltip `L["Race window"]`.
- Lit (`Style` control button's active look, or the gold tint the lock uses) while the Race window is shown; it
  follows the window's show and hide, whoever caused them. *Superseded 2026-11-13 (owner, W11):* no lit state;
  the flag is gold only under the pointer.
- [ ] Tests: built and shown on Retail with Race mode on; hidden with it off; absent on Forever; click toggles; lit follows.

### Task W3: The HUD's auto-show near a dummy

**Files:** `modules/AutoArm.lua` (the session start and end), `modules/Hud.lua` (two hooks, ShowNearDummy and
HideAwayFromDummy, mirroring RaceWindow's), `defaults/Profile.lua` (`race.autoShowHud = true`, Retail only),
`settings/Race.lua` (the row under "Near a training dummy": `L["Show the DPS HUD with it"]`, disabled while
`race.autoShow` is off), `locales/enUS_Race.lua`, tests.

- When auto-show opens the Race window for a dummy session and `race.autoShowHud` is on, the HUD opens as an
  "auto" open (it fades by its own rules) unless the player closed it during this session (count its closes the
  way RaceWindow.Closes does). At the session's end, the HUD closes only if this rule opened it, no fight is live
  on it, and the player has not opened or pinned it since.
- Same gates as auto-show: never in an instance, stood down, Race mode off or on Forever.
- `race.clock` default changes to `"left"` in this task too (O2; `defaults/Profile.lua` raceMode()).
- [ ] Tests: opens with the Race window; stays shut with the row off; a player close holds it shut for the session;
  closes at session end only when this rule opened it; never closes a live fight's HUD.

### Task W4: Flush dock at the HUD's height

**Files:** `modules/RaceWindow.lua` (`DOCK_GAP` 0; RW.Height; placement), `modules/Hud.lua` (a size-changed
signal, or RW reads `Hud.Dock()`'s frame height on each HUD resize), `defaults/Profile.lua`
(`raceWindow.matchHud = true`), `settings/Race.lua` (its row on the Race window tab), locale, tests.

- Docked LEFT or RIGHT with `matchHud` on: the Race window's height is the HUD frame's height, kept in step when
  the HUD resizes (grip, auto-grow, scale, title bar or footer toggled). Never shorter than the Race window's
  own minimum (the tallest body's needs, as RW.Height computes today); if the HUD is shorter, use the minimum.
- TOP, BOTTOM, detached, or `matchHud` off: today's height.
- The bodies lay out against the window's actual height: bottom buttons stay pinned to the bottom, filler grows.
- Both windows use the same scale (`hud.scale`) today; keep that, so equal heights line up.
- [ ] Tests: gap is 0 on every side; matched height on LEFT and RIGHT follows a HUD resize; floor at the minimum;
  TOP/BOTTOM/detached keep their own height.

### Task W5: One race beat for both clocks

**Files:** a new `modules/RaceClock.lua` (TOC: after `Race.lua` and `RaceSample.lua`, before `Hud.lua`? place it
where its dependencies load; update `docs/module-map.md` in W8), `core/Constants.lua` or wherever `NS.MSG` lives
(`RACE_CLOCK`), `modules/RaceWindow.lua` (drop its own ticker; redraw on RACE_CLOCK), `modules/Hud.lua` (on
RACE_CLOCK, redraw the clock label only, while its fight is the race's fight or the sample race's; on FIGHT_TICK,
skip the clock label while the beat is on), `core/PerfSetup.lua` (a `raceClock` bucket, replacing or beside
`raceWindow`'s timer use), `docs/message-bus.md` (in W8), tests.

- The beat runs one AceTimer at 0.1 s on the addon object while the race's state (real `NS.Race` or the sample
  `NS.RaceSample` while it is on) is RUNNING or STOPPING, started on RACE_STATE_CHANGED into those states and on a
  resumed race, stopped on the way out, and by the stand-down's CancelAllTimers. Each fire sends
  `NS.MSG.RACE_CLOCK` once; both windows redraw from `GetTime()` inside the same callback.
- A fight that is not a race: nothing changes, the HUD's clock stays on FIGHT_TICK.
- The countdown (`modules/Countdown.lua`) and the buzzer keep their own timers.
- [ ] Tests: no beat outside a race; beat during running and stopping (real and sample); stops on idle and on the
  stand-down; the HUD clock redraws on the beat and not on FIGHT_TICK during a race, and on FIGHT_TICK otherwise;
  the Race window has no timer of its own; one RACE_CLOCK per fire.

### Task W6: Running body

**Files:** `modules/RaceWindow_States.lua` (Builders.running, its layout constants), `modules/RaceWindow.lua`
(the running view: the best record, its straight line, the checkpoints), `modules/RaceWindow_Best.lua` if the best
card is shared from there, `locales/enUS_Race.lua`, tests.

*Amended 2026-11-13 (owner, W13):* the time bar empties to the buzzer, it and the countdown turn green to yellow to
red, and Best by now and the Checkpoints show the player's damage beside the best's (the HUD's last read).

Top to bottom (mockup §3): the clock per `race.clock` (default one large Left, red); caption "Left of 1:00"; a time
bar for the race length with quarter marks (plain: elapsed / length); the race's chips (as today); **Best to beat**
(the idle screen's best card: DPS, score, date, item level); **Best by now** (the best's straight line at the
current elapsed: score × elapsed / length, with "at 0:40"); **Checkpoints** (four cells at 25/50/75/100% of the
length, the best's damage at each, the passed ones dimmed, the next one outlined); filler; Cancel at the bottom.
No pace bar. With no best on the board: Best to beat says so (the idle card's empty text), Best by now and
Checkpoints hide. A shared-session race keeps its chip; the best figures still show (they never touch the meter).
The stop and waiting bodies keep their content and drop nothing.
- [ ] Tests: no pace bar region; every figure plain and right for a sample best (score 22.02M over 60 s at 40 s =
  14.68M; checkpoints 5.51M/11.01M/16.52M/22.02M); no best hides the two sections; layout fits the window's
  minimum height and stretches to a taller one.

### Task W7: Result and idle bodies

**Files:** `modules/RaceWindow_States.lua` (Builders.result, Builders.idle), `modules/RaceWindow.lua` (the views:
the best before this race via `NS.Bests.Before`, the board's races), `locales/enUS_Race.lua`, tests.

- Result (mockup §4): Score and Race DPS boxes, the chips (as today); **Against your best**: a table with rows
  Score, DPS, Raced, Item level, Date; columns This race, Best, Diff (Diff colored green or red; date has no
  diff); hidden when there was no earlier best; **This board** (its kind · length · spec): the top 3 races on the
  board for this character and spec (clean races, as the board ranks them), plus this race's row with its rank
  when it is not in the top 3, highlighted; filler; the four buttons at the bottom. No pace bar. A lost race keeps
  today's "Couldn't read the result" and shows neither table.
- Idle (mockup §1): add **This board** (top 3) between Your best and Arm Race when the board has races; the rest
  unchanged.
- *Amended 2026-11-13 (owner, W12):* no Raced row (Score, DPS, Item level, Date), *This board* is *Top races*,
  and no vs best chip beside the table.
- All figures from stored records (`NS.Bests`, the Results source the Race window already uses for its best).
- [ ] Tests: the comparison rows and diffs for a sample; ranks, including a race outside the top 3; first race
  (no best) hides Against your best; lost race; idle table appears only with races on the board.

### Task W8: Docs, smoke tests, test inventory, README

**Files:** `docs/ARCHITECTURE.md` (module map, bus table: RACE_CLOCK), `docs/module-map.md` (RaceClock, load
order), `docs/message-bus.md`, `docs/schema.md` (`race.autoShowHud`, `raceWindow.matchHud`, `race.clock`
default), `docs/settings-panel.md` (the two rows), `docs/smoke-tests.md` (new SM-CT-RM rows: both windows near
a dummy, the header button, flush and matched height, one beat during a race, the running and result screens),
`docs/performance.md` (the beat's cost), `README.md` (Race mode paragraph, the HUD header button, the test badge),
`docs/test-cases.md` (regenerate: `lua tests/run.lua --list > docs/test-cases.md`), this ledger.
