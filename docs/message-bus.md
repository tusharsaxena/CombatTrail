# Message bus — Ka0s Combat Trail

Every message the addon sends on its bus (documentation-§3, Tier 2: more than ten distinct messages).
Each name is declared once in `core/Bus.lua` (`NS.MSG`) and sent with `NS.SendBus`; wire names are
`Ka0s_CombatTrail_<Event>`. Every receiver is a target of its module's own (`NS.NewBusTarget`), so the
stand-down drops it and the stand-up replays it (slash-commands-§7).

## Messages

| Message | Sender | Payload | Consumers |
|---|---|---|---|
| `SETTINGS_CHANGED` | settings/Schema.lua | `(path, value)`, or `("profile", key)` | AutoArm, Bests, BestToast, Countdown, Hud, RaceWindow, LaneAnchor, LaneCasts, LaneRender, LaneVisibility, Results, History page, Race mode page |
| `LANE_PUSH` | LaneCasts | `(laneKey, item)` | LaneRender |
| `COMBAT_ENTERED` | Fight, on the `PLAYER_REGEN_DISABLED` edge only (never a split or a mid-combat `ENCOUNTER_START`) | `(t)` | Results (closes while `results.closeInCombat` is on) |
| `FIGHT_STARTED` | Fight | `(fight)` | Casts, Hud, Loadouts, Preview (ends test mode), Race, Slices, Stats, Usage |
| `FIGHT_FIRST_HIT` | Fight, once per fight, on its first damage update for a bound session | `(fight)`, `fight.firstHitT` set | Race (the race clock, ruling X2) |
| `FIGHT_TICK` | Fight, every 0.25 s in combat | `(fight)` | Hud, RaceWindow (the race's live total for its pace bar), Slices |
| `FIGHT_ENDED` | Fight | `(fight, final, reason)` | Casts, Hud, Recorder (which pulls `Race.Finalize` first, ruling X1), Slices, Usage |
| `FIGHT_SAVED` | Recorder | `(record)` | Bests, BestToast (a fight's new best; never a race), Hud, Race, Results, Slices, History page |
| `FIGHT_SKIPPED` | Recorder | `(fight, reason)` | Hud, Race, Slices |
| `FIGHTS_CHANGED` | Recorder, Retention | none | Bests, RaceWindow (a deleted result card goes back to Arm Race), Results, History page |
| `RACE_STATE_CHANGED` | Race, on every transition | `(race, from, to)` | AutoArm, Countdown (the marks armed on `running`, gone on any other state), Hud (the resume's `idle` to `running` or `stopping`: the adopted fight goes live, paced on its race board, ruling X7), RaceWindow (the body on screen, the arm's and the resume's opening, the idle edge's close) |
| `RACE_ARMED` | Race.Arm | `(race)` | Share (the armed line); the Race window reacts to the state change |
| `RACE_STARTED` | Race, on the race fight's `FIGHT_FIRST_HIT` | `(race, fight)` | Hud (a race's fight opens the HUD whatever its own rules say, ruling X7; the live fight paces on its race board, Task C3) |
| `RACE_BUZZER` | Race, at the race length | `(race)` | Countdown (the raid warning's STOP and its sound) |
| `RACE_RESULT` | Race, inside the race fight's `FIGHT_SAVED` or `FIGHT_SKIPPED`; or from `Race.Resume` itself for a resumed race whose session is gone | `(record, race)`; `record` nil when nothing was stored (a lost race) | RaceWindow (opens on the result card), BestToast (a race's new best), Share (the score line, or the lost line) |
| `RACE_CANCELED` | Race.Cancel, or a pull not on a training dummy | `(reason)`: `"canceled"` or `"not_dummy"` | Hud (the live fight, its race part gone, paces on its dummy's fight board again, Task C3); the Race window reacts to the state change |

The race messages are Retail's (Race mode is absent on WoW Forever, clients-§4): nothing sends them
there. A consumer in parentheses arrives with the task named.

## Order and nesting

CallbackHandler dispatches a message to its receivers in no fixed order, so nothing here relies on
one receiver running before another:

- **Recorder pulls the race in.** `FIGHT_ENDED`'s Recorder receiver calls `NS.Race.Finalize` itself
  before it judges the fight (ruling X1), so the race part is final when the record is built.
- **Nested sends.** `RACE_STARTED` is sent from inside `FIGHT_FIRST_HIT`'s dispatch, and `RACE_RESULT`
  from inside `FIGHT_SAVED`'s (or `FIGHT_SKIPPED`'s), itself inside `FIGHT_ENDED`'s. A receiver of
  `RACE_RESULT` therefore finds the record already stored and the bests already counting it.
- **One race on the bus:** `RACE_ARMED` → `FIGHT_STARTED` → `FIGHT_FIRST_HIT` / `RACE_STARTED` →
  `FIGHT_TICK`… → `RACE_BUZZER` → `FIGHT_ENDED` → `FIGHT_SAVED` / `RACE_RESULT`, with a
  `RACE_STATE_CHANGED` at each transition.
- **A resumed race** (`Race.Resume` after a `/reload` or the stand-up, Task B2) sends no `RACE_ARMED`
  or `RACE_STARTED`, and its fight (`Fight.Adopt`) no `FIGHT_STARTED` or `FIGHT_FIRST_HIT`: the first
  message is `RACE_STATE_CHANGED` from `idle` to `running` or `stopping` (or to `result`, with
  `RACE_RESULT` and a nil record, when its session is gone), then `FIGHT_TICK`… → `FIGHT_ENDED` →
  `FIGHT_SAVED` / `RACE_RESULT` as above. A receiver that shows a race reacts to the state change, not
  to `RACE_STARTED` alone; one that keys on `FIGHT_STARTED` (Casts, Slices, Usage) hears an ended
  fight it never saw begin. The HUD takes the adopted fight up on that state change (`Race.Fight()`,
  marked `resumed`): live and paced on its race board, and on screen whatever its own rules say.

The sample fight of test mode and the sim is never sent on the bus: Preview and Sim hand it to the
HUD directly, so the recorder, the casts, the slices reader and the bests never hear it.
