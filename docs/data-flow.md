# Data flow — Ka0s Combat Trail

The core mechanic as a pipeline, from the client's events to what the player sees (documentation-§3,
Tier 1). The README's *How the trail and the HUD work* is the same pipeline told for players; the two
must agree.

## 1. The trail

```
UNIT_SPELLCAST_START / _SUCCEEDED / _INTERRUPTED / _FAILED / _EMPOWER_START (player, pet)
  -> modules/LaneCasts.lua   one registration per lane switched on (Sync), each handler perf-bracketed
       dedupe by castGUID (skipped when the GUID is secret), the ignore list (spell IDs, skipped when
       the ID is secret), interrupt marks for a cast that showed a START
  -> LANE_PUSH(laneKey, item { texture, spellID|nil, t, interrupted })
       and every LaneCasts.Listen listener (modules/Casts.lua, in pcall)
  -> modules/LaneRender.lua  an icon from the lane's pool, placed by modules/LaneLayout.lua
       (position = speed x age), faded over the last `fade` of the window, glowing for a base
       cooldown >= glowMinCD; the lane's OnUpdate runs only while an icon is visible
```

`modules/LaneAnchor.lua` places each lane (free, docked, or on a unit frame found in
`LaneAnchor.UNIT_FRAMES`' order) at its strata and level, icons in a bounded band above it.
`modules/LaneVisibility.lua` decides whether a lane shows and at what alpha from its rules and the
events listed in ARCHITECTURE's *Event Subscriptions*.

## 2. A fight

```
PLAYER_REGEN_DISABLED / ENCOUNTER_START (idle set, modules/Watchers.lua)
  -> modules/Fight.lua  IDLE -> COMBAT; snapshots who and the target (modules/Identity.lua),
       sends FIGHT_STARTED(fight): Stats, Loadouts and Usage take their snapshots, Casts opens the
       fight's cast list, Slices opens the chart store, the HUD opens
  DAMAGE_METER_COMBAT_SESSION_UPDATED / _CURRENT_SESSION_UPDATED (combat set)
  -> Fight binds the fight to the meter session that appeared after combat entry
       (Meter.SessionAfter), and merges a second session of the same encounter
  every Constants.FIGHT.TICK (0.25 s): FIGHT_TICK(fight)
  -> modules/Slices.lua copies the opaque total into its step every 2 s
  -> modules/Hud.lua brings a fight live on it; it reads and redraws here only while no beat runs
  the HUD's beat, every 1 / hud.refreshRate (0.1 s by default; Hud.SyncBeat outside a race)
  -> modules/Hud.lua reads Meter.ReadLive (opaque player and pet totals and spells) and redraws
     every live part, only while Fight holds the fight in combat (in the settle it redraws from the
     last read); Meter.ShareLive brackets let the beat and the slices' boundary tick share one read
     in a frame
     (WoW Forever, Meter.FOLDS_PET: with no pet source, the read splits the pet's figure out of
     the player's rows when every value it reads is plain and every row was readable, the main
     figures then the player's part, pet out or not, so a pet that dies mid-fight keeps the split;
     else the merged figure and, with a pet out, petDash, the Pet row's dash; callout plan rows C7
     and C9)
  PLAYER_REGEN_ENABLED
  -> COMBAT -> SETTLING; a re-entry within GRACE (4 s) carries the same fight on
  quiet for SETTLE (2 s) after GRACE
  -> Meter.ReadFinal(sessions): the plain after-combat read, player and pet merged; nil while
       anything is still secret, so the settle retries
  -> FIGHT_ENDED(fight, final, "final")  (or "lost" on DAMAGE_METER_RESET)
```

### A race on the fight (Race mode, Retail)

```
Race.Arm(length)  out of combat, Fight idle: the meter's sessions now (Meter.SessionIDs) are the arm's
     set, the newest one's plain read its baseline; stats, talents, gear set and usage snapshot taken
  FIGHT_STARTED(fight) on a training dummy -> the fight carries the race part; else RACE_CANCELED
  FIGHT_FIRST_HIT(fight)  (Fight, the first update of a bound session; a session of the arm's set may
     be bound as shared, Fight.ShareSessions) -> RUNNING, the buzzer at firstHitT + length, the arm's
     snapshots replace the fight's
  modules/RaceWatchers.lua: the regen edges and PLAYER_DEAD (an early end: incomplete), the meter's
     updates (the timeline's tail and restart), the player's casts (the late-cast judge)
  RUNNING and STOPPING -> modules/RaceClock.lua: one AceTimer at Hud.RefreshInterval() (0.1 s by
     default), the HUD's own beat stood down meanwhile (Hud.SyncBeat); each fire calls
     Hud.OnRaceClock() (the read and the HUD's whole redraw), then sends RACE_CLOCK, on which the
     Race window redraws from that same read in the same frame
  the buzzer -> STOPPING, RACE_BUZZER; Stop Now -> Fight.Hurry (no settle wait)
  FIGHT_ENDED -> Recorder pulls Race.Finalize: a shared read netted against the baseline, then the
     score, DPS, timing and status on the part -> the record (below), RACE_RESULT inside FIGHT_SAVED
  the slot: db.global.pendingRaces[charKey] written at the first hit, cleared at the result or a cancel
  /reload or stand-up -> Race.Resume (after Meter.Prime): a session gone -> lost; else Fight.Adopt
     rebuilds the fight on the kept sessions: in combat with time left RUNNING (the buzzer re-armed),
     else STOPPING (reloaded past the buzzer; out of combat read on the next timer, incomplete before
     the buzzer) -> FIGHT_ENDED as above
```

## 3. The record

```
FIGHT_ENDED
  -> modules/Recorder.lua   Filters.Passes(identity, duration): short or filtered -> FIGHT_SKIPPED
       no readable character -> FIGHT_SKIPPED "unknown"; lost -> FIGHT_SKIPPED "lost"
       else Recorder.Build: identity and board key (Identity), casts packed (CastCodec), the gear set
       taken at the pull and the loadout interned (Loadouts), stats completed (Stats.Fill), usage
       (Usage), every value copied through plainCopy so nothing sealed survives
  -> db.global.fights[id], fightOrder; FIGHT_SAVED(record)
  -> Bests recomputes the board; Slices adopts the record id for the chart; the HUD's card shows
       Saved and New best; the Results window redraws
```

`modules/Retention.lua` purges at login, every stand-up, once a day and on `/ct purge`: older than
`history.days`, except a fight holding a best while `history.keepBests` is on, then the cap
`history.maxFights`. It sends FIGHTS_CHANGED when it removed anything.

## 4. What the player sees

- **The HUD** (modules/Hud.lua and its parts): in combat the live body copies opaque values into
  StatusBars and secret-safe text (spec §3); the pace bar's fill is set against the paced fight's
  damage at the same second (modules/Hud_Best.lua); while the fight carries its `race` part that is
  the race board's best, on its score over its length, and a race on a shared session is not paced
  and draws no chart (Race mode plan Task C3). Every live part (the clock, Damage and DPS, the pace
  bar, the chart, the spell rows) reads and redraws on one beat at `hud.refreshRate` (default 10 a
  second): the race beat's direct call during a race, the HUD's own `Hud.SyncBeat` otherwise. The
  footer names the rate ("live · 10 Hz").
  RACE_ARMED lets go a fight still on screen (never a live one) and draws the HUD's pre-fight look. After
  FIGHT_ENDED the card draws the plain read: shares, the New best chip from `Bests`, and Saved or the
  skip reason.
- **The Race window** (modules/RaceWindow.lua, Retail) never reads the meter. It draws the race's
  GetTime() figures (the clock, and the time bar, which empties to the buzzer, both colored green to
  amber to red by `RaceWindowBoard.ClockColor`), the race board's best and its straight line
  (`NS.HudBest.RaceCurve`: Best to beat, Best by now, the Checkpoints) and stored records (the result
  card, Against your best and Top races, `NS.Bests.Before` and `NS.Bests.Ranked`). Its one live
  figure is the player's damage (*Current*) beside Best by now and in each Checkpoint, the HUD's read of
  the race's fight on the same beat, handed over on the RACE_CLOCK that follows it (`Hud.LiveDamage`),
  so Current and the checkpoints move at `hud.refreshRate` in step with the HUD. It reaches
  two C-side sinks: a label through `NS.Format.Number`, and the two mini pace bars'
  `StatusBar:SetValue` (the HUD's pace bar built thinner, `Chart.NewPace` with opts), whose plain range
  is `NS.HudBest.Bounds` around the best's figure there at the HUD's Pace range. Where the pet has a
  live part of its own (Retail's pet source, or WoW Forever's folded split of plain rows; `Hud.LiveDamage`'s third answer `petOwn`), the figure
  is the player's alone, so the bars range on the best's player-only line (`paceRef`). Each
  Checkpoint keeps the reading of the beat the clock passed it, in memory for that race alone (a dash
  for one passed unseen before a `/reload`); the last one is taken at the buzzer, in the stopping
  view, so all four show on the Stop! and waiting screens (when the board has a best and they fit). The full pace bar is the HUD's alone.
  It is an extension of the HUD (race window redesign plan W29): it is up only while the HUD is
  (`RaceWindow.IsShown` asks `Hud.IsShown`), every `Hud.Refresh` ends in `RaceWindow.FollowHud`, so a
  fade, the overCard close, the HUD's close mark or a stand-down hides it with the HUD (still wanted,
  back when the HUD is), and each of its opens opens the HUD first (`Hud.Show` for the player's,
  `Hud.ShowForRace` for an arm, a resume, a result or a sample, `Hud.ShowNearDummy` for a dummy
  session). While the race, real or sample, is not idle the HUD neither fades nor takes the overCard
  close; `Hud.OnRaceIdle`, at the race's idle edge, starts that fade. A dummy session holds it the
  same way (owner, 2026-11-13): no fade and no overCard close while it lasts, and its end
  (`Hud.HideAwayFromDummy`) closes a HUD the session opened, or starts the fade of one it held.
- **The center call-out** (modules/Countdown.lua on `NS.Callout`, Retail) reads no meter value. While
  a race (real or sample) runs, it is handed `RaceClock.EndsAt()` (Race.EndsAt, or the live sample's)
  a second before the `race.finalCountdown` window and shows `ceil(endsAt - GetTime())`, read on its own
  frame clock, so a number flips in the frame the true time left crosses it; each new number calls
  `RaceClock.Kick()`, one race beat at once, so the Race window draws 0:0n.0 in that frame. The last
  `speakFrom` (5) numbers are spoken from the chosen pack. RACE_BUZZER cancels the count and shows STOP
  (`race.buzzer`). Leaving running with no buzzer (combat dropped or the player died: the race's
  plain `endedAt`) takes the number down and says FAILED; a cancel or a lost read says nothing.
  RACE_RESULT of a complete race that is a new best (`BestToast.Earns`, whether or not the toast is
  on) says NEW_BEST. Both are `Countdown.EndWord` and `Countdown.ResultWord`, the rule the samples
  ask too (callout plan row C9), with Race mode on; each is the library's stock word in the call-out's voice (no own text or mute,
  callout plan row C11). Its settings flow the other way only through the seam: the Race mode page's
  Callout tab, `/ct set` and the drag all
  write `callout.*` through `NS.SetByPath`, whose row reaction (`onChange`, the instance's `Apply`)
  repaints the call-out.
- **The Results window** (modules/Results.lua) reads `Results_Source`, which is the store or, in test
  mode and the sim, the sample history. The list, the detail, the timeline, the compare and the gear
  view all read stored records; the detail's chart reads Slices while this session holds it.

## 5. Test mode and the sim

Neither touches the bus or the store. `modules/Preview.lua` hands a sample fight from
`modules/MockFights.lua` straight to the HUD (`Hud.OnFight*`), feeds its casts to the lanes through
`Preview.FeedLanes` (which applies the ignore list), and points `Results_Source` at the sample
history. `modules/Sim.lua` plays the same shape in real time on an AceTimer beat, judged by the
player's own recording filters. A real FIGHT_STARTED ends both. The one message a sample sends is
the race beat's: a sample race running or stopping calls `RaceClock.Sync`, and its `RACE_CLOCK`
carries no payload, so it only moves the two windows' clocks.

The samples' alerts are calls too, never messages (callout plan row C6): a sim fight's save calls
`BestToast.OnFight`, a sim race's read `BestToast.OnRace`, and `/ct test race result`
`BestToast.ShowPreview`, each judged on the sample history (`Bests` reads it while the preview is
on); the call-out's words are a real race's rule (`Countdown.EndWord`, `Countdown.ResultWord`)
said through `Countdown.SampleSay`. `/ct test race running` is a still frame: its clock holds, so it
counts nothing; only the sim's race scenarios run the countdown. The preview's stop and switch call
`BestToast.EndSample` and `Countdown.EndSample`, so no toast or call-out outlives its sample.
