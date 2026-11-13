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
  beat off the timer (`RaceClock.Kick`), at most ten in a race.
- The equipment recon walks the gear once per burst of `PLAYER_EQUIPMENT_CHANGED` /
  `UNIT_INVENTORY_CHANGED` (one coalesced 0.5 s timer), never per event and never per fight: the pull
  takes the current set's key.
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

## Offline

There is no `tests/perf.lua` yet, so the automated-test runner records the `perf` suite as a skip
(automated-tests-§3); a skip is not evaluated at the tag. The offline runs, when they exist, live in
[`automated-tests/README.md`](automated-tests/README.md)'s bundles.
