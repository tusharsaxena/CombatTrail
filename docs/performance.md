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
| `probe` | the armed probe's cast and combat events (modules/Probe.lua) | only while `/kct probe` is armed |
| `meter` | the live read of the player's and the pet's sources (modules/Meter.lua) | every HUD tick in combat |
| `fight` | every combat, encounter and meter event (modules/Watchers.lua) | the meter's session events fire often in combat |
| `casts` | each cast the fight record keeps (modules/Casts.lua), inside `laneCast` | every cast, in combat |
| `slices` | the damage chart's once-a-step read (modules/Slices.lua), holding `meter` | every 2 s in combat |
| `hud` | the HUD's read and redraw on each `FIGHT_TICK` (modules/Hud.lua), holding `meter` | four times a second in combat |

Nested buckets are reported as their own lines; the outer bucket's figure includes the inner one.

## The budget

- The lanes animate in `OnUpdate` only while an icon is visible, and nothing polls while idle (spec
  §2's anti-goal).
- The HUD redraws on `FIGHT_TICK` (0.25 s), not per frame; its rows and the Results window's rows
  come from pools.
- The settle read, the record build and the purge run out of combat.

## Taking a capture

`/kct perf help` prints the library's grammar. The usual run: `/kct perf start`, fight the pull you
want measured, `/kct perf finish`, then copy the report and the JSON dump from the console. The
in-game captures and their write-ups live in [`perf-analysis/README.md`](perf-analysis/README.md).

## Offline

There is no `tests/perf.lua` yet, so the automated-test runner records the `perf` suite as a skip
(automated-tests-§3); a skip is not evaluated at the tag. The offline runs, when they exist, live in
[`automated-tests/README.md`](automated-tests/README.md)'s bundles.
