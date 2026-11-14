# Debug — Ka0s Combat Trail

The debug surfaces (documentation-§3, Tier 2; debug-logging). The console is LibKa0s-DebugLog-1.0's,
set up in `core/DebugLogSetup.lua`; the library documents the console itself.

## The console and the flag

- `/ct debug` opens and closes the console; `/ct debug on` and `/ct debug off` set the logging
  flag, which is session-only (`NS.State.debug`) and off after every reload. General → Master
  controls carries the same two as *Debug console* and *Debug logging*.
- Every line goes through the gated sink `NS.Debug(tag, fmt, ...)`, which costs nothing while the flag
  is off. The console's **Copy** lifts the whole buffer out.

## Tags

| Tag | Written by |
|---|---|
| `Lanes` | LaneCasts, LaneRender, LaneAnchor, LaneVisibility: registration rebuilds, refused events, the stand-down's dropped casts, the guards that keep a cast off a lane, a listener that raised |
| `Casts`, `Identity`, `Fight`, `Meter` | The fight pipeline: a cast list, an identity read, the state machine's edges, a meter read that failed |
| `Race` | Race mode's engine (Retail): an arm and its refusals, the clock, the buzzer, an early combat end, a late cast, a restart, a cancel and the read; the race beat on and off (RaceClock) |
| `AutoArm` | Auto-show and auto-arm (Retail): a dummy session beginning and ending, an auto-arm and its refusal, an auto-arm canceled by a target change |
| `Countdown` | The race's final seconds (Retail): the call-out handed the race's countdown, the buzzer's STOP |
| `Callout` | LibKa0s-Callout-1.0's own lines (Retail): a voice file the copy does not carry, text to speech unavailable, a host callback that raised |
| `Toast` | The new-best toast: a new best queued with its gain, and the toast shell's own lines |
| `Recorder`, `Retention`, `Loadouts` | A save or skip with its reason, a purge, a loadout interned |
| `Hud`, `Format` | The HUD's open and fade decisions (an open near a training dummy among them); a formatter constructor passed over and why, and which path served a number (written when it changes) |
| `Results`, `Timeline`, `Compare`, `Gear`, `Share` | The Results window and its modals, a share refused |
| `Probe` | The probe's arm, samples and disarm |
| `Test` | Test mode and the sim starting and stopping |
| `Skin`, `Set` | A skin applied, a profile act or a setting written |
| `Cmd`, `Perf` | The dispatcher's refusals, the perf harness |

## The diagnostics report

`/ct diagnostics` writes a plain-text report into the console after the trace (debug-logging-§14),
so one **Copy** carries both; it turns logging on first. The library writes the markers and the
identity header (brand, version, client build, locale, the running LibKa0s minors, the state);
`modules/Diagnostics.lua` adds this addon's sections:

| Section | Says |
|---|---|
| `identity` | The stored and code schema versions and the fight format, the profile, enabled, stood down, the holds |
| `settings` | Every row that differs from its default |
| `store` | The stored fights, the loadouts, the gear sets, the estimated size |
| `lanes` | Each lane on or off, the cast registrations and listeners, and per lane: shown, the visibility decision, the icons showing, the anchor mode, unlocked |
| `fight` | The fight state machine's state, the current fight's id and session, the meter, the fights the chart holds, the probe armed |
| `race` | Retail only, after `fight`: the race state, Race mode on or off, the race's fight and session, the pending races (`db.global.pendingRaces`), the race boards the bests hold; the Race window (shown, body, attached, side, matched: whether it takes the DPS HUD's height); the race beat (`race beat on=`, RaceClock.Diagnose, whose answer also carries `every`, the beat's interval at `hud.refreshRate`, for the suites; the report prints `on` alone); the countdown (the number the call-out shows, what is scheduled: the lead-in timer and the call-out's countdown, the owner); the sample race (`RaceSample.Diagnose`) |
| `windows` | The HUD's state, body, pin and lock (Hud.Diagnose; its answer also carries `beatEvery`, the HUD's own beat's interval at `hud.refreshRate` while it runs, which the report does not print); the Results window, the timeline, the compare and the gear view; the new-best toast (shown, waiting, key) |
| `preview` | Test mode and the sim: active, mode, phase (`race <state>` while test mode holds a sample race), scenario (`Preview.Diagnose`, `Sim.Diagnose`) |
| `rejected` | Event names the client refused (`NS.rejectedEvents`) |

While stood down, the runtime sections print "stood down: runtime state released"; the settings and
store still print. The README's *Reporting a bug* tells players how to send it.

## The probe

`/ct probe` is a debug surface too: it writes its report to the console. Its steps are in
[`smoke-tests.md`](smoke-tests.md), *The probe*.

With a pet out, each meter sample (5 s into combat and 2 s after it) adds one line on the pet's rows
in the player's source, the folding client's shape (WoW Forever): how many rows, how many carry a
secret creature name, how many plainly name a creature and how many of those have a secret amount,
whether the player's total is secret, and what the HUD's live read made of it: `split` (every value
plain, so the HUD shows the pet's live figure and your own part), `dash` (something secret: the
merged figure and a dashed Pet row), `own source` (the pet answers a meter source of its own, as on
Retail) or `none` (SM-CT-P8). It only counts: no value is printed or compared.
