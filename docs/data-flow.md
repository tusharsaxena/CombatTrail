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
  -> modules/Hud.lua reads Meter.ReadLive (opaque player and pet totals and spells) into the bars
  -> modules/Slices.lua copies the opaque total into its step every 2 s
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
  damage at the same second (modules/Hud_Best.lua). After FIGHT_ENDED the card draws the plain read:
  shares, the New best chip from `Bests`, and Saved or the skip reason.
- **The Results window** (modules/Results.lua) reads `Results_Source`, which is the store or, in test
  mode and the sim, the sample history. The list, the detail, the timeline, the compare and the gear
  view all read stored records; the detail's chart reads Slices while this session holds it.

## 5. Test mode and the sim

Neither touches the bus or the store. `modules/Preview.lua` hands a sample fight from
`modules/MockFights.lua` straight to the HUD (`Hud.OnFight*`), feeds its casts to the lanes through
`Preview.FeedLanes` (which applies the ignore list), and points `Results_Source` at the sample
history. `modules/Sim.lua` plays the same shape in real time on an AceTimer beat, judged by the
player's own recording filters. A real FIGHT_STARTED ends both.
