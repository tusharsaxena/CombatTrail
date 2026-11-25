# Performance — Ka0s Combat Trail

How much the addon costs, and how to measure it (documentation-§3; performance). The harness is
wired: `core/PerfSetup.lua` builds `NS.Perf` from LibKa0s-Perf-1.0, the reserved `perf` verb drives
it, and captures land in `CombatTrailPerfDB`. The capture protocol and the record contract are the
library's; this page says what this addon brackets and why.

## The buckets

Declared in report order in `core/PerfSetup.lua`; each is a `Perf.Note(key, ms)` around the hot path,
taken only while `Perf.on` is set, so an idle harness costs one boolean test.

| Bucket | Brackets | Why it is hot |
|---|---|---|
| `laneCast` | every `UNIT_SPELLCAST_*` a lane hears (modules/LaneCasts.lua) | runs on every cast and pet cast, in combat |
| `laneRender` | each lane's `OnUpdate` and push (modules/LaneRender.lua) | runs every frame while icons are visible |
| `probe` | the armed probe's cast and combat events (modules/Probe.lua) | only while `/ct probe` is armed |
| `meter` | the live read of the player's and the pet's sources (modules/Meter.lua) | every HUD tick in combat |
| `fight` | every combat, encounter and meter event (modules/Watchers.lua) | the meter's session events fire often in combat |
| `race` | every race event: both regen edges, `PLAYER_DEAD`, the meter's session updates and the player's casts (modules/RaceWatchers.lua) | only while a race runs or waits for its read (Retail) |
| `autoArm` | auto-show's and auto-arm's target, nameplate and `PLAYER_ENTERING_WORLD` events (modules/AutoArm.lua) | only while either rule is on, Race mode on (Retail); nameplates churn in a city |
| `casts` | each cast the fight record keeps (modules/Casts.lua), inside `laneCast` | every cast, in combat |
| `combatLog` | every aura, hit, heal and death the Combat Log hears (no combat-end line since owner feedback item 10) (modules/CombatLog.lua's frame); its casts come in through `laneCast` and are not bracketed again | every `UNIT_AURA` on the player and the target and every `UNIT_COMBAT` on the player, only while a fight is open |
| `slices` | the damage chart's once-a-step read (modules/Slices.lua), holding `meter` | every 2 s in combat |
| `hud` | the HUD's read and redraw on each beat (modules/Hud.lua: its own beat, or the race beat's call), holding `meter` | `hud.refreshRate` times a second (4, 5, 10 or 20, default 10) while the HUD is up on a live fight; no read in the settle |
| `raceWindow` | the Race window's redraw on each race beat and its idle events (modules/RaceWindow.lua); it reads no meter | `hud.refreshRate` times a second (default 10), only while the window is shown and a race runs or waits for its read (Retail) |
| `raceClock` | each race beat (modules/RaceClock.lua): the HUD's read and redraw, then the one `RACE_CLOCK` send, holding `hud` and the Race window's redraw | `hud.refreshRate` times a second (default 10), only while a race (real or sample) runs or waits for its read (Retail) |

Nested buckets are reported as their own lines; the outer bucket's figure includes the inner one.

## The budget

- The lanes animate in `OnUpdate` only while an icon is visible, and nothing polls while idle (spec
  §2's anti-goal).
- The HUD reads and redraws on ONE beat at a time at `hud.refreshRate` (default 10 a second, owner
  2026-11-13), not per frame; its rows and the Results window's rows come from pools. Outside a race
  that is the HUD's own AceTimer (`Hud.SyncBeat`), running only while the HUD is up on a live fight
  that moves; in a race it is the race beat. Each beat is one `Meter.ReadLive` (the player's source
  and the pet's) and the whole redraw, so the HUD's meter cost scales with the rate: 10 a second is
  2.5 times the old 4 Hz, 20 is 5 times. No read in the settle (Fight out of combat): the beat then
  redraws from the last read. Hidden, nothing reads.
- On WoW Forever, with no pet source, the live read also splits the pet's figure out of the player's rows
  (callout plan row C7): two passes over the rows it already copied, each value proved plain first,
  and one small table for the pet's part. It builds no row array (the pet's rows stay in the player's
  list, marked), keeps its sums in one file-scope table, asks the cast set through
  `Casts.IsPetSpell` (no copy of the set), and stops at the first secret value, so a sealed fight
  costs one pass to its first row.
- `FIGHT_TICK` stays 0.25 s for its other receivers (the chart's slices, the unbound scan): raising it
  to the HUD's rate would multiply their work for nothing, and the slices' 2 s steps need no finer tick.
- The race beat is one AceTimer at 1 / `hud.refreshRate`, running only while a race runs or waits for
  its read, and never outside a race. Each fire has the HUD read and redraw (`Hud.OnRaceClock`), then
  sends one `RACE_CLOCK`, on which the Race window redraws its body from stored records, `GetTime()`
  and that same read, so a race costs no read beyond the HUD's. The Race window has no timer and no
  read of its own; its two mini pace bars (over Best by now and in each Checkpoint) are set from that
  same handed-in figure. The player's
  damage it draws beside the best's is the HUD's last read, taken as a field lookup
  (`Hud.LiveDamage`), not a read. The clock's color costs one blend (`RaceWindowBoard.ClockColor`), two
  `SetTextColor` calls and one `SetColorTexture` per beat.
- The center call-out (LibKa0s-Callout-1.0, Retail) runs an OnUpdate only while it counts or holds a
  call-out: modules/Countdown.lua keeps one AceTimer waiting through the race and hands the call-out
  the countdown a second before its window, so its frame clock runs for at most the window plus that
  second (11 s at the default 10) and STOP's hold, and sleeps the moment neither is up. Its animations
  are AnimationGroups the client runs, with no OnUpdate of their own. Each new number costs one race
  beat off the timer (`RaceClock.Kick`): one per number of `race.finalCountdown`'s window, ten at the
  default and at most twenty.
- The equipment recon walks the gear once per burst of `PLAYER_EQUIPMENT_CHANGED` /
  `UNIT_INVENTORY_CHANGED` (one coalesced 0.5 s timer), never per event and never per fight: the pull
  takes the current set's key.
- The Combat Log (#11) does constant work per event: one line into its ring, whose slots are reused
  once it is full (`NS.Constants.LOG.RING`, 2000 lines), so a busy fight allocates nothing per line
  after the first 2000 of the session (`tests/perf.lua` pins 0 bytes per event). Its events are
  registered only while a fight is open. A loss is a lookup in the unit's aura-instance map; the
  map is walked again only at the fight's start, a target change and a full update. The fight's
  saved lines are built once, out of combat, when the record is.
- The Combat Log's live views (the DPS HUD's drawer, the detached window) repaint on one AceTimer each
  at `NS.Constants.LOG.REPAINT` (0.1 s), only while shown, and a tick with nothing new paints nothing
  (`logPaintIdle`, 0 bytes). The Combat Log page's *Show new rows* throttle (`log.view.throttle`) only
  spaces out what those ticks reveal; the capture and the store never wait on it. The rows' text size
  and height (`log.view.fontSize`, `log.view.rowHeight`) are read at layout, which runs only when the
  width, the rows, the columns or one of those two change, never on a paint: a new text size sets each
  pooled label's face once (a named font object per size, made once and kept).
- The live views' scroll bar (owner feedback item 6, Spell breakdown's indicator) needs the count of
  lines the view accepts, and walking the 2000-line ring on every paint cost 2.2 ms a paint against
  0.16, so the feed keeps the count instead (`LogTable.Count`): it adds the lines that arrive, takes
  off the lines the ring drops (a mark per slot), and counts again only when the floor, the top or the
  filter changes (`LogTable.Refilter`, from each home's seed and chip click). An indicator that did not
  move is not placed again. With the chips shown by default (item 9) the drawer's height reads the
  HUD's width on every beat, so the HUD's `width()` reads through `NS.GetSetting` rather than the
  local path walker, whose iterator cost 88 bytes a call (`logPlaceIdle` back to 0.2 bytes a beat).
  `logPaint` is 6,992 bytes and about 0.2 ms a repaint at the default ten rows (5,696 at eight, CLF-2);
  its ceiling is still 10,240.
- The settle read, the record build and the purge run out of combat. A daily purge that falls due
  in combat or while a fight is open waits (`Retention.RETRY`, 60 s) and is asked again.
- When the HUD's beat and a slices boundary tick land in one frame they share one `Meter.ReadLive` of
  the session: both bracket their read with `Meter.ShareLive`, whichever runs first asks the client
  and the other is served it within that frame (`GetTime()`), so the client is asked once a frame.
- The chart's cooldown icons are laid again only when the casts, the span or the geometry change,
  compared by value, since the HUD builds a fresh list every tick.

## Taking a capture

`/ct perf help` prints the library's grammar. The usual run: `/ct perf start`, fight the pull you
want measured, `/ct perf finish`, then copy the report and the JSON dump from the console. The
in-game captures and their write-ups live in [`perf-analysis/README.md`](perf-analysis/README.md).

## Stored size

A fight's saved Combat Log (the record's `log`, CT_SCHEMA 6) is the one part of a record whose size
grows with the fight. Measured with `Retention.SizeOf` (the client's SavedVariables layout) on
2026-11-25 (CL-REV, after each target line gained its `g` and the record its `logTargets`): a log at
the default cap of 400 lines, a busy fight's mix of casts, auras and hits with an amount, a school
and a mark, takes about 38.4 KB, about 96 bytes a line (36.9 KB before `g`, at CL-11a).
`tests/test_combat_log.lua` holds it under 39,500 bytes. A fight shorter than the cap takes less in
proportion (an in-game figure for a typical pull is still owed), and the lines kept per fight (100 to
1000) and the categories saved are the player's to lower.

**The total is bounded by `log.store.fights`** (100 by default, 0 to 500; modules/Retention.lua). Age
(`history.days`) and the cap (`history.maxFights`, 500) alone did not bound it: a best-holding fight
is kept for ever with its log, so 500 fights at the cap would have been about 19 MB of SavedVariables,
a real cost at load, logout and `/reload`. Each purge run (login, daily, `/ct purge`) now strips the
log from every stored fight but the newest 100 carrying one, so the worst case at the defaults is 100
logs at the cap, about 3.8 MB, plus the fights a session stores before the next run (each up to 38 KB).
A player who wants every log back sets it to 0. The History tab's size (`Retention.EstimateBytes`)
counts the logs.

## Offline

`tests/perf.lua` (performance-§9) is outside the green gate: `lua tests/perf.lua`, and the vendored
runner's `perf` suite. It drives the Combat Log's handlers inside an open fight, as the client calls
them: a hit (`logHit`), an aura gained and lost (`logAura`), a cast from the lanes' listener
(`logCast`) and a busy fight's beat of all of them (`busyFight`), the first two with capture off and
on, then the drawer's repaint after a busy beat (`logPaint`) and with nothing new (`logPaintIdle`),
and the drawer's place at a HUD beat that moved nothing (`logPlaceIdle`: `HudLog.Place`, which the HUD's
render calls on every live beat, compares its last place field by field and allocates nothing; CL-REV,
0.2 bytes per iteration, under an 8-byte ceiling).
Every capture scenario measured 0 bytes per iteration once the ring is full (2026-11-25, Lua 5.1.5),
and its ceilings sit just above that; `logPaint` measured 9,520 bytes per iteration, all of it the kit's
widget mock, under a 10,240 ceiling (re-run 2026-11-25 after CL-11c2's sizes: unchanged). The recorded runs live in
[`automated-tests/README.md`](automated-tests/README.md)'s bundles.
