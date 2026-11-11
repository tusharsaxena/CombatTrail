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
| `Race` | Race mode's engine (Retail): an arm and its refusals, the clock, the buzzer, an early combat end, a late cast, a restart, a cancel and the read |
| `AutoArm` | Auto-show and auto-arm (Retail): a dummy session beginning and ending, an auto-arm and its refusal, an auto-arm canceled by a target change |
| `Countdown` | The race's final seconds (Retail): the frame built (digits or the font fallback), an animation the client refused, the buzzer's STOP |
| `Toast` | The new-best toast: a new best queued with its gain, and the toast shell's own lines |
| `Recorder`, `Retention`, `Loadouts` | A save or skip with its reason, a purge, a loadout interned |
| `Hud`, `Format` | The HUD's open and fade decisions; a formatter constructor passed over and why, and which path served a number (written when it changes) |
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
| `windows` | The HUD's state, body, pin and lock; the Results window, the timeline, the compare and the gear view |
| `preview` | Test mode and the sim: active, mode, phase, scenario (`Preview.Diagnose`, `Sim.Diagnose`) |
| `rejected` | Event names the client refused (`NS.rejectedEvents`) |

While stood down, the runtime sections print "stood down: runtime state released"; the settings and
store still print. The README's *Reporting a bug* tells players how to send it.

## The probe

`/ct probe` is a debug surface too: it writes its report to the console. Its steps are in
[`smoke-tests.md`](smoke-tests.md), *The probe*.
