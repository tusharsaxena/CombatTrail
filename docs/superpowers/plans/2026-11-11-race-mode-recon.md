# Race mode recon: DPS Race (f8078c7) -> Combat Trail seams

Written by the M0 workflow (wf_bc36d941-0a2), 2026-11-11: nine readers and a completeness critic, read-only.
Cite items as `R:<area>#<n>`. Line numbers were true on 2026-11-11; re-check before editing.

## race

Scope: DR `modules/Race.lua`, `Scoring.lua`, `Timeline.lua`, `Slices.lua`, `Watchers.lua`, `Meter.lua` (race reads) and the race parts of `Recorder.lua` and `Hud.lua`, at f8078c7. CT `modules/Fight.lua`, `Recorder.lua`, `Meter.lua`, `Watchers.lua`, `core/Bus.lua` and `core/Constants.lua`, at the branch tip. DR paths are `../DpsRace/...`.

**Summary of the mapping.** DR's race is a state machine of its own. It keys on one meter session ID, reads that session by ID after combat and stores the run at every transition. CT's `Fight` already owns the session, the settle and the read, so B1's Race becomes a layer that only annotates. It arms, starts its clock on the fight's first hit, runs the buzzer, judges late casts, stamps a timeline and writes `fight.race`. Fight still decides when the read happens and what it returns. Four places conflict and need a seam or a decision:
1. A shared session is never bound by CT, so that fight ends `lost` (#6).
2. Feign Death inside the grace carries the CT fight on, while DR ends the race (#9).
3. DR's quiet is 2.5 s and CT's settle is 4 s / 2 s (#13).
4. CallbackHandler gives no dispatch order, so "the race receiver registered first" is not a guarantee. Recorder must pull `Race.Finalize` itself (#21).

---

### #1 States, constants and the two state machines

- **DR:** `Race.lua:28-36`.
  - `STATE = { IDLE="idle", ARMED="armed", RUNNING="running", STOPPING="stopping", RESULT="result" }`.
  - `POLL_INTERVAL = 0.5`, `SEALED_RETRIES = 20` (10 s), `MIN_LENGTH, MAX_LENGTH = 10, 900`.
  - Queries:
    - `Race.State()`;
    - `Race.Current()` (nil when IDLE);
    - `Race.Elapsed()` (live only: RUNNING/STOPPING with `startedAt`);
    - `Race.TimeLeft()` (0 once STOPPING);
    - `Race.SinceBuzzer()` (STOPPING with `buzzerAt` only);
    - `Race.StopRequested()` (`Race.lua:84-116`, `:669-671`).
  - `setState` calls `Watchers.Sync()` and then sends `RACE_STATE_CHANGED(run, from, to)` (`:64-69`).
- **CT seam:** `Fight.lua:43` `STATE = { IDLE, COMBAT, SETTLING }`. Timings are in `core/Constants.lua:55`: `C.FIGHT = { GRACE = 4, SETTLE = 2, TICK = 0.25 }`, plus `Fight.RETRY = 0.5` and `Fight.SEALED_RETRIES = 10` (`Fight.lua:47-48`). The fight table comes from `newFight` (`:113-117`): `{ id, startT, scanFrom, sessions, sessionSet, encounter, snapshot }`, later `sessionID`, `firstHitT`, `lastUpdateT`, `combatEndT`, `closedT`.
- **Owner:** B1 (`modules/Race.lua`).
- **How the states line up:**
  - ARMED runs while Fight is IDLE.
  - RUNNING runs while Fight is COMBAT.
  - STOPPING spans COMBAT (sticky combat) and SETTLING.
  - RESULT and IDLE come after `FIGHT_ENDED`.
- **What differs:**
  - CT's sealed retries cover 5 s (10 × 0.5); DR's covered 10 s (20 × 0.5). The race inherits CT's, since Fight does the read.
  - Plan B1's `Race.LENGTHS = {30,60,120,180,300}` is DR's `HudStates.PRESETS` (`Hud_States.lua:142`). Custom lengths are 10..900.
- **DR tests:** `test_race.lua` ("the state names are the interface's", "inputs in the wrong state change nothing").

### #2 Arm: refusals, snapshot, baseline sessions

- **DR:** `Race.lua:339-406`.
  - Refusals, in this order (`armRefusal`): `"disabled"` (stood down), `"busy"` (ARMED or RUNNING), `"pending"` (STOPPING, or `#Recorder.Pending() > 0`), `"bad_length"`, `"in_combat"`, `"meter_unavailable"` plus Blizzard's reason verbatim.
  - `Race.Arm(length) -> ok, reason, detail` then does the following:
    - `Recorder.NewRun(length)` (DR `Recorder.lua:278-298`) snapshots char, target, where and stats. It freezes `race = { length, grace, restartGap, startSource="meterSession" }` from `profile.race`, with defaults `grace = 1.0` and `restartGap = 6` (`defaults/Profile.lua:83-84`), and sets `flags = { lateCasts = {}, reloaded = false, died = false }`.
    - It holds `armTarget`, `armLoadout = Recorder.SnapshotLoadout()`, `Casts.Begin()` and `usageSnap = Usage.Snapshot()`.
    - `armSet = Meter.SessionIDs()`.
    - `run.race.armMaxSession` = the highest ID in that set.
    - `cur.baseline = baselineOf(mark)`: an out-of-combat `ReadSession(mark)`, giving `{ session, damage, spells = {[id] = dmg summed} }`.
- **CT seam:** most of this already happens at `FIGHT_STARTED`:
  - `Identity.Snapshot()` in `newFight` (`Fight.lua:116`, `Identity.lua:279-281`);
  - Loadouts, Stats and Usage receivers (`Loadouts.lua:432`, `Stats.lua:231`, `Usage.lua:577`);
  - `Casts.Begin` with the PREPULL window (`Casts.lua:125-130`, receiver `:287-289`).
  - Race's Arm keeps only: length, frozen grace/restartGap, `armSet`/`armMaxSession`, baseline, arm target.
  - The CT baseline read is `Meter.ReadFinal(mark)` (`Meter.lua:417-438`). Net against `merged` (player plus pet, spells keyed by spellID and isPet) so it matches what Fight's final returns.
- **Owner:** B1 for Arm. B3 adds the `NS.RaceMode.On()` / Forever refusals.
- **What differs:**
  - Add a refusal while `Fight.State() ~= IDLE`, for example `"settling"`. Arming during SETTLING and pulling within GRACE (4 s) is a carry-on (`Fight.lua:385-391`): no `FIGHT_STARTED` is sent, so the race would never start.
  - DR's `"pending"` refusal reads stored running/stopping runs. In CT that becomes `db.global.pendingRaces` (B2).
  - CT's `Meter.SessionIDs()` returns `(set, ok)` and also stamps IDs (`Meter.lua:149-170`). DR's returns only the set.
  - Plan B3's settings list leaves out DR's `race.grace` and `race.restartGap` rows (DR `settings/Race.lua:74-80`, "Scoring" subgroup) and the countdown/buzzer rows (`countdownCue`, `centerCountdown`, `finalCountdown` 3-10, `buzzer`; DR `defaults/Profile.lua:99-105`).
- **DR tests:** `test_race.lua` ("arm refuses in combat and while a run is pending", "arm refuses while a stored run is pending, even when idle", "arm refuses when meter unavailable", "arm refuses a length outside 10s-15:00 and arms a valid one", "the grace in force is the run's own, not the profile's"), `test_disabled.lua` ("Disabled (race): an armed race is dropped by the stand-down and not resumed").

### #3 First hit: `OnSessionCreated`, regen pairing, stash, `startOnUpdate`

- **DR:** `Race.lua:442-565`.
  - `begin(t)` sets `status="running"`, `date=time()`, `race.startedAt=t`, calls `Casts.Start(t)`, adopts the stash if it is held, `armBuzzer(length)`, then RUNNING.
  - The clock starts on any of three paths:
    - (a) `Race.OnSessionCreated(t)` (`DAMAGE_METER_CURRENT_SESSION_UPDATED`) in combat, or on the same frame as the regen edge (`combatAt == t`);
    - (b) `OnCombatStart(t)` when `sessionAt == t` or `stashAt == t`;
    - (c) `startOnUpdate`: the first in-combat DamageDone update while ARMED (`OnMeterUpdate:551-558`). This is the path for a session made out of combat.
  - Out-of-combat session events and updates are held only for their own frame (`stashUpdate:527-534`). Updates for sessions from before the arm are held back.
- **CT seam:**
  - `FIGHT_STARTED(fight)` fires at the regen edge (`Fight.lua:328-339`), before any hit, with `firstHitT == nil`.
  - `firstHitT` is set in `heard()` (`:407-410`), only once `sessionID` is bound. No message marks it; CT's HUD notices it on `FIGHT_TICK` (`Hud.lua:931-935`).
- **Owner:** B1.
- **Recommendation:**
  - Race clock = `fight.firstHitT`. The buzzer delay is `length - (GetTime() - firstHitT)`, so a ≤0.25 s tick lag does not skew it.
  - Either poll `FIGHT_TICK` while ARMED with a `FIGHT_STARTED` fight in hand, or add a one-shot bus message in `heard()` (e.g. `FIGHT_FIRST_HIT (fight)`, declared in `core/Bus.lua`). The second is cheaper and exact.
- **What differs:**
  - DR's clock usually starts on the regen-edge frame. CT's `firstHitT` is the first damage update, a little later.
  - A fight with no bound session (see #6) never gets `firstHitT`.
- **DR tests:** `test_race.lua` ("session created starts the clock and persists the run as running", "a DamageDone update heard just before the session event is adopted at the start", "a session event heard out of combat does not start the clock", "a DamageDone update for a stray session heard out of combat is never adopted at the start", "a session event with the regen edge on an earlier frame does not start the clock", "a session made out of combat starts the clock on its first update in combat", "an update on the regen edge's frame, heard before the edge, starts the clock", "an update in combat for another session never starts a stray combat's clock out of combat"). Fixture: `tests/race_clock.lua`.

### #4 Target re-read, and a non-dummy pull

- **DR:** `rereadTarget` / `OnCombatStart` (`Race.lua:471-492`): `run.target = Recorder.SnapshotTarget("target", prior)`, once per combat that starts the clock. DR itself never cancels on a non-dummy; `AutoArm.lua` cancels on a target change before the pull.
- **CT seam:**
  - `fight.snapshot.target = { name, creatureID, level, classification, isDummy }`, read at combat entry (`Identity.lua:206-218`, `isDummy` at `:215`, via `NS.DummyName`, which becomes `NS.Dummies` in A2).
  - The final content is `Identity.Resolve` → `contentOf` (`:317-324`): `"dummy"` when `targetCreatureID` is a dummy, after `resolveTarget` merges in the meter's enemies.
- **Owner:** B1 (Review focus 1). A2 for the dummy lookup.
- **What differs:**
  - Decide at `FIGHT_STARTED` while ARMED: `snapshot.target.isDummy` → keep waiting for the first hit; otherwise `Race.Cancel` (`RACE_CANCELLED("not_dummy")`), and the pull stays a normal fight.
  - `snapshot.target == nil` (no target at the pull) is undecided by the spec. DR's idle body says "the one you fight is read when combat starts". Recommendation: treat it as not a dummy and cancel.
  - Re-check `identity.content == "dummy"` in `Finalize` (#21). If it is not, drop the race part.
  - The race kind is `NS.Dummies.CategoryOf(snapshot.target.creatureID)`.
- **DR tests:** `test_race.lua` ("the target is re-read at combat start", "the target is re-read at the combat that starts the clock, not an earlier one"). New: plan B1's "an armed race cancels when a non-dummy pull starts".

### #5 Session capture: `adopt`, `sessionToRead`, `sessionFromList`

- **DR:**
  - `adopt(id)` (`Race.lua:409-417`) refuses a `beforeArm(id)` session (`:165-169`: in `armSet`, or `id <= armMaxSession`).
  - `sessionToRead` (`:173-185`): the captured `race.sessionID`, otherwise the newest session after the arm, with `flags.sessionFromList = true`.
- **CT seam:** every CT bind comes from the list:
  - `begin` uses `Meter.SessionAfter(t)` (`Fight.lua:331`).
  - `scan` uses `Meter.SessionsAfter(cur.scanFrom, all)` (`:315-324`, `Meter.lua:195-205`), with sessions stamped on first sight.
  - `Meter.Prime()` (`Meter.lua:178-181`) sets the baseline, which plays the part of DR's `armSet`.
  - Race reads `fight.sessionID` / `fight.sessions`.
- **Owner:** B1 for the race. A3 for the flag field.
- **What differs:**
  - DR's event-vs-list split has no CT equivalent, so `sessionFromList` loses its meaning. Options: keep the field and leave it nil, or set it when the race's fight bound only on a tick scan (`onTick`, `:343`). This is a builder decision; record it in `docs/schema.md`.
  - `armSet` is still needed for the shared-session test (#6).
- **DR tests:** `test_race.lua` ("sessionID captured from first DamageDone update with non-zero id", "a session ID never captured falls back to the newest session after arming", "no new session at all is lost"), `test_race_resume.lua` ("a run with no session ID never adopts a session from before its arm").

### #6 `sharedSession`: share, net, unshare (main conflict)

- **DR:**
  - `share(id)` (`Race.lua:423-431`): a pull whose first in-combat update names a session from before the arm. It adopts that session, sets `flags.sharedSession = true`, and sets `race.baseline` only when `baseline.session == id`.
  - `net(data, base)` (`:213-236`): drops `meterDps`; `damage = max(0, damage - base.damage)`; per-spell sums minus `held[id]`.
  - `unshare(id)` (`:433-440`): a fresh session after the arm replaces the shared one and clears the flag.
  - Flag text: `Scoring.lua:118-123`.
- **CT seam:** `SessionsAfter(scanFrom)` leaves out any session stamped before the combat entry, and `owned()` (`Fight.lua:126-132`) blocks a parked fight's session.
  - Previous fight idle: the new fight stays unbound and `readFight` returns `"unbound"`, so `FIGHT_ENDED(fight, nil, "lost")` (`:221`, `:258`).
  - Previous fight still SETTLING because DoT updates keep moving `settleDue`: re-entry after GRACE parks it (`:392-394`). The parked fight's merged read then includes the race damage, and the new fight is lost.
  - Either way, CT today saves the pre-arm fight with the race damage folded in, or loses the pull.
- **Owner:** B1. Needs a Fight seam (Review focus 5).
- **Recommendation:** a narrow `Fight` hook, e.g. `Fight.BindShared(id)` or a rule inside `OnMeterUpdate`. When the fight is in COMBAT, unbound, and an in-combat update names a plain id that is neither owned nor after `scanFrom`, bind it as `fight.sharedSession = true`. Allow this only while a race asks for it (Race passes its `armSet`), so plain fights keep today's rule.
  - Netting happens in `Race.Finalize` against `final.merged` (total and spells, keyed by spellID and isPet).
  - Recorder builds the record from the netted final, so the record's damage and the race score agree, saved once.
  - A later fresh session (DR's `unshare`) is a CT `split` (`:290-300`, see #7). The race should follow it only when its fight is shared.
  - Arming during SETTLING is refused (#2), which removes the parked-fight case.
- **DR tests:** `test_race.lua` ("a pull that continues a session from before the arm is adopted, flagged and netted", "a fresh session heard after a shared start replaces the shared one"), `test_scoring.lua` ("Flags order and text"). DR Slices also leaves holes for a shared run (#23).

### #7 Meter split and encounter merge during a race

- **DR:** the run reads one session. Updates for other sessions are ignored (`OnMeterUpdate:560-564`).
- **CT seam:**
  - `adopt` → `mergesInto` (`Fight.lua:282-286`, same active encounter, never inside GRACE of a mid-fight encounter start).
  - Otherwise `split` (`:290-300`): the race's fight is parked (`closedT = t`), a new fight starts and `FIGHT_STARTED` fires again.
  - `finishAll` ends parked fights first, then the current one (`:247-260`).
- **Owner:** B1.
- **What differs:**
  - Race must hold its fight by reference or `fight.id`. A `FIGHT_STARTED` while RUNNING or STOPPING must not re-attach, except the unshare case in #6.
  - `Finalize` must match on its own fight id, because one settle can end several fights.
  - Dummies have no encounters, so a merge is practically unreachable. Pin "a split mid-race keeps the race on its first fight".
- **DR tests:** `test_race.lua` ("updates for another session never move the timeline"). New CT case in B1.

### #8 The buzzer

- **DR:**
  - `armBuzzer(delay)` = `C_Timer.NewTimer(max(0, delay), buzz)` (`Race.lua:324-326`).
  - `buzz` (`:314-322`) sets `buzzerAt = startedAt + length` (the buzzer's own time, not when the timer ran), calls `stop()` (`status="stopping"`, `Recorder.Save`, STOPPING, start polling), then sends `RACE_BUZZER(run)`.
- **CT seam:** no Fight change; the fight stays in COMBAT. Timers: CT Fight uses the addon's AceTimers (`NS.addon:ScheduleTimer`, `Fight.lua:91-101`), so the stand-down's `CancelAllTimers` takes them. Race should do the same rather than use `C_Timer` (Disabled 4).
- **Owner:** B1. C2 consumes `RACE_BUZZER` (raid warning, `SOUND_BUZZER = 8959`, DR `Hud.lua:83`).
- **What differs:** CT must not save at STOPPING (#25).
- **DR tests:** `test_race.lua` ("buzzer at start+length moves to stopping and emits RACE_BUZZER", "a buzzer heard out of combat with the regen edge missed is still read"), `test_disabled.lua` ("Disabled 4").

### #9 `endEarly`: combat ends before the buzzer, and the Fight grace

- **DR:**
  - `OnCombatEnd` while RUNNING → `endEarly(t)` (`Race.lua:329-335`, `:495-510`): cancels the buzzer, sets `run.result = { endedAt = round2(t - startedAt) }`, then STOPPING. The read becomes `"incomplete"` (`complete:244`).
  - At a STOPPING combat end it attaches a fresh loadout and sets `combatEndedAt = quietFrom = t`.
  - A re-entry while STOPPING clears both (`OnCombatStart:488-490`).
- **CT seam:**
  - `Fight.OnCombatEnd` (`Fight.lua:398-404`) sets `combatEndT` and SETTLING, with no bus message.
  - A re-entry within GRACE = 4 s carries the same fight on and clears `combatEndT` (`:385-391`, Feign Death or Vanish).
  - CT sends `COMBAT_ENTERED(t)` (`core/Bus.lua:25`) but has no "combat left" message.
- **Owner:** B1.
- **Conflict:**
  - Under DR's rule, Feign Death before the buzzer ends the race as incomplete, while the CT fight carries on and keeps recording. The race part then says incomplete at `endedAt` while the record runs longer.
  - DR's score has the same quirk: the session total at the later read, divided by `endedAt`, includes the damage after the re-entry. Incomplete races never rank, so it is harmless. Keep DR's rule.
  - Race needs the regen edges itself: its own `PLAYER_REGEN_ENABLED`/`DISABLED` (#20), or a new `COMBAT_LEFT(t)` from `Fight.OnCombatEnd`.
  - `endedAt` lives on `race.endedAt` (spec §6), not on DR's `run.result.endedAt`.
- **DR tests:** `test_race.lua` ("combat end before buzzer -> incomplete with endedAt", "stop now on a run that ended before the buzzer reads it as incomplete").

### #10 Death

- **DR:** `Race.OnDeath(t)` (`Race.lua:513-518`), on `PLAYER_DEAD`. While RUNNING or STOPPING it sets `flags.died = true`; while RUNNING it also calls `endEarly(t)`.
- **CT seam:** none. CT `Watchers.lua:38-48` never registers `PLAYER_DEAD`.
- **Owner:** B1 (Race's own watcher, #20).
- **DR tests:** `test_race.lua` ("death -> incomplete, died flag", "death after the buzzer flags died and the run stays complete").

### #11 Late casts after the buzzer

- **DR:**
  - `judge(spellID, t)` (`Race.lua:569-577`) runs only while STOPPING with `buzzerAt`: `offset = t - buzzerAt`. If `Scoring.IsLateCast(offset, run.race.grace)` (strictly `offset > grace`, `Scoring.lua:24-27`), it appends `{ t = round2(offset), spellID }` to `flags.lateCasts`. A secret spell ID is stored as nil.
  - `Race.OnCast(kind, spellID, t, castGUID)` (`:620-631`): kinds `start | channel | succeeded | interrupted | channelStop`.
    - `start` and `channel` open `inFlight` and are judged at their start.
    - The in-flight cast's own `succeeded` is not judged again.
    - An instant is judged at its success.
    - `AUTO_REPEAT = { [75]=true, [5019]=true }`. A sealed-ID success is skipped while `C_Spell.IsAutoRepeatSpell` holds (`:580-591`).
    - Matching uses castGUID, then spell ID, then "assume yes" (`isInFlight:595-601`).
- **CT seam:** `LaneCasts.Listen(key, fn)` (`LaneCasts.lua:309`) hands `(unit, spellID, t, interrupted)` only for deduped successes and interrupts (`tell:204-211`). `start` is never handed on (`onStart` returns nil). No channel events are registered (`:64-68`). `Casts.AUTO = {6603, 75, 5019}` (`Casts.lua:~38`).
- **Owner:** B1 for the capture. A3 for `NS.LateIgnore` / `Scoring.SplitLate` (`Scoring.lua:68-83`), which re-scores on edit.
- **What differs:**
  - The listener seam cannot judge "counts at its start". A cast begun before the buzzer and finished after it would read as late.
  - Race needs DR's own unit-filter frame: `UNIT_SPELLCAST_START`, `_EMPOWER_START`, `_INTERRUPTED`, `_SUCCEEDED`, `_CHANNEL_START`, `_CHANNEL_STOP` for `player`, from RUNNING on (#20). The alternative is extending LaneCasts to pass a `start`/`channel` kind; LaneCasts is not near the cap.
  - Do not port DR's cast-list capture (`CAPTURE_EVENTS` → `Casts.Hear`). CT Casts already records casts.
- **DR tests:** `test_race.lua` ("an empowered cast held across the buzzer is never late", "cast started 0.5s after buzzer is not late at grace 1.0", "cast started 1.4s after buzzer is recorded as late with spellID", "a late cast of an ignored spell is still stored raw…", "cast that started before buzzer and succeeded after is not late", "an interrupted cast leaves nothing open; a later instant of the same spell is late", "a cast matches its own success by castGUID, not by spell", "secret spell IDs and castGUIDs are judged without ever being stored", "auto-repeat successes after the buzzer are never late casts", "Watchers hands Race the castGUID and the interrupt"), `test_scoring.lua` ("late cast boundaries", "SplitLate …", "Flags flags only the counted late casts…").

### #12 Timeline: tail, restart gap, `lastDamage`

- **DR:**
  - `Timeline.New()`; `:AddDamage(t)` keeps stamps sorted (`Timeline.lua:175-185`); `:LastDamage()`.
  - `:Tail(buzzer)` = last stamp − buzzer, else 0 (`:193-197`).
  - `:RestartAt(buzzer, gap, resumedAt)` (`:204-217`): the first stamp after the buzzer that follows a quiet stretch ≥ `gap`. The stretch starts at the later of the previous stamp and the buzzer, and never spans `resumedAt`.
  - `stamp(t)` (`Race.lua:199-207`) runs on every DamageDone update for the race session. It keeps `race.lastDamage = round2(t - startedAt)` and sets `flags.restartedAt` the moment it is heard (`round2`).
  - `timing(result)` (`:189-194`): `tail = round2(Tail(buzzerAt))`, `combatEnd = round2(combatEndedAt - buzzerAt)`, both only when a buzzer happened.
- **CT seam:**
  - `Fight.OnMeterUpdate` → `heard(t)` keeps only `cur.lastUpdateT` (`Fight.lua:407-423`), only for `cur`'s sessions; a parked fight's updates are not heard.
  - Note that a secret session ID counts as the fight's own (`:422`), so stamps can come from another session.
  - `combatEndT` is cleared on a carry-on; `closedT` is set when the fight is parked.
- **Owner:** B1 (`modules/RaceTimeline.lua`, a port of `Timeline.lua` unchanged).
- **What differs:**
  - The tail alone could come from `fight.lastUpdateT` at Finalize.
  - The restart needs every stamp. Feed the Timeline from Race's own `DAMAGE_METER_COMBAT_SESSION_UPDATED` registration while RUNNING or STOPPING (#20). Sampling `lastUpdateT` on `FIGHT_TICK` misses SETTLING, which has no ticks.
  - `combatEnd` should come from Race's own regen edge.
  - Defaults: `restartGap = 6`, frozen per race.
- **DR tests:** `test_timeline.lua` (all 10: "tail from probe run 4 = 3.03", "tail from probe run 6 = 8.49", "restart detected after 10s quiet at gap 6", "DoT ticks every 2s are not a restart", "a gap of exactly the setting counts as a restart", "a gap that spans a resume is measured from the resume", …), `test_race.lua` ("tail and combat end are stored relative to the buzzer", "restart after a 10s gap sets flags.restartedAt", "updates for another session never move the timeline").

### #13 STOPPING and the quiet before the read

- **DR:**
  - `Scoring.QUIET_BEFORE_READ = 2.5` (`Scoring.lua:19`).
  - `checkReady(t)` (`Race.lua:272-283`) reads once combat has ended and `t - max(quietFrom, LastDamage) >= 2.5`.
  - `poll()` runs on a 0.5 s ticker while STOPPING (`:288-301`). It also starts the quiet when out of combat with no regen edge heard.
  - `read()` (`:255-266`): `Meter.ReadSession(sessionToRead())`. `"sealed"` retries up to `SEALED_RETRIES`; anything else fails into `lose(err)`.
- **CT seam:** `settleDue()` = `max(combatEndT + GRACE(4), lastUpdateT + SETTLE(2))` (`Fight.lua:262-268`). Then `onSettle` → `finishAll` → `readAll` (sealed retries `RETRY` 0.5 × 10) → `FIGHT_ENDED` (`:232-276`).
- **Owner:** B1.
- **Conflict:**
  - Plan B1 says "quiet 2.5 s", but Fight owns the read and the race cannot have its own quiet without a second read. Recommendation: the race reads when the fight reads, on CT's settle. A race read lands at about combat end + 4 s instead of DR's about + 2.5 to 3.8 s.
  - `QUIET_BEFORE_READ` survives only as the Race window's Stop!→Waiting threshold (`stopPhase`, DR `Hud.lua:213-229`).
  - CT has no missed-edge poll; Fight comes back IDLE after a stand-down.
- **DR tests:** `test_race.lua` ("result read only after combat end AND 2.5s quiet", "no read while combat holds, however quiet the meter is", "read uses ReadSession(sessionID), never Current", "a read that stays sealed is retried, then lost", "a read that raises is lost, not a Lua error"), `test_scoring.lua` ("QUIET_BEFORE_READ is 2.5s").

### #14 Stop Now and the `Fight.Hurry` seam

- **DR:** `Race.StopNow() -> acted` (`Race.lua:653-665`) acts only in STOPPING. It sets `cur.stopNow`.
  - Out of combat: `quietFrom = quietFrom or t` and it reads at once.
  - In combat: it reads on the regen edge with no quiet.
  - A sealed read still retries on the poll.
- **CT seam:** new `Fight.Hurry()` in `Fight.lua`, the plan's one Fight seam:
  - `state == SETTLING`: `stopSettle(); finishAll()`. This keeps the `scheduleSettle(RETRY)` retry path inside `finishAll` (`:251-254`).
  - `state == COMBAT`: set `cur.hurry = true`. `OnCombatEnd` (`:398-404`) then calls `scheduleSettle(0)` instead of `C.GRACE`, and `onSettle` skips `settleDue` while `cur.hurry` is set.
  - IDLE: no-op, returns false.
  - Hurry also reads any parked fights.
  - Hurry removes the GRACE carry-on for that fight. A Feign Death after Stop Now ends it, which is acceptable because the player asked.
  - Hurry must not reach a fight other than the race's. Guard with `Race`'s fight id, or `Fight.Hurry(fightID)`.
- **Owner:** B1.
- **DR tests:** `test_race.lua` ("stop now acts only while stopping", "stop now out of combat reads at once through the normal path, the quiet waived", "stop now in combat reads nothing until the regen edge, then reads without the quiet", "stop now on a still-sealed read retries on the poll, as any read does"). New CT `test_fight.lua` cases for Hurry: COMBAT, SETTLING, IDLE.

### #15 Cancel

- **DR:** `Race.Cancel() -> acted` (`Race.lua:678-687`).
  - ARMED: nothing is stored.
  - RUNNING or STOPPING: `Recorder.Delete(run.id)`, so nothing is kept.
  - RESULT: dismisses the card and keeps the run.
  - Then `Casts.Reset()` and IDLE.
- **CT seam:** Race only. Cancel removes Race's hold on the fight; the fight runs on and `Recorder` takes the normal path.
- **Owner:** B1. A3 for Recorder's rule.
- **What differs:**
  - Spec §4.1 inverts DR: a cancel after the first hit leaves a plain dummy fight under Filters (minimum length and the dummy toggle). Nothing is deleted.
  - Race must not call `Casts.Reset`; CT Casts belongs to the fight.
  - Cancel after Stop Now: if `Fight.Hurry` already ran, the fight is read early. Acceptable; pin it.
  - New message: `RACE_CANCELLED(reason)`.
- **DR tests:** `test_race.lua` ("cancel in armed/running stores nothing; cancel in stopping discards", "cancel on a result dismisses it and keeps the run; race again arms"). New: "Cancel after the first hit leaves a plain dummy fight".

### #16 Meter reset, lost, session gone

- **DR:**
  - `Race.OnMeterReset()` (`Race.lua:634-642`): ARMED clears `armSet`, stash and `armMaxSession` and keeps the arm; RUNNING or STOPPING calls `lose("meter reset")`.
  - `lose(why)` (`:151-160`) sets `status = "lost"` and **saves** the run, then `finish()` sends `RACE_RESULT`.
- **CT seam:** `Fight.OnMeterReset` → `loseAll` (`Fight.lua:152-158`, `:433-435`), and `scan`'s `goneFrom` (`:320`): `FIGHT_ENDED(f, nil, "lost")` for every fight, at once. Recorder skips it as `"lost"` (`Recorder.lua:369`).
- **Owner:** B1 / A3.
- **What differs:**
  - Spec §3.4 says a lost race is not saved, unlike DR (which stores `lost` runs, `PRUNABLE` in DR `Recorder.lua:405`). `Finalize` sets `race.status = "lost"`, and the record never exists because the fight is lost too.
  - While ARMED, CT needs nothing: Meter stamps forget dropped IDs (`Meter.lua:165-167`). Race must still clear its `armSet` and baseline.
  - `RACE_RESULT` for a lost race has no record (plan signature `RACE_RESULT (record)`). Send `(nil, race)`, or `RACE_CANCELLED("lost")`. Decide before C1/C2.
- **DR tests:** `test_race.lua` ("meter reset while stopping -> lost", "meter reset while running -> lost, and the buzzer never goes", "meter reset while armed forgets the arm-time sessions and keeps the arm", "a session the client no longer holds is lost at the read").

### #17 Scoring: score, DPS, flags

- **DR:**
  - `complete(data)` (`Race.lua:238-253`) nets a shared session, sets `result.damage`, `meterDps` and `sessionDuration`, calls `timing`, sets `status = endedAt and "incomplete" or "complete"`, takes `run.spells = data.spells`, and sets `result.dps = Scoring.Dps(damage, run)`.
  - `Scoring.Dps(damage, run)` (`Scoring.lua:31-41`): divides by `race.length` when complete, otherwise by `result.endedAt`; 0 for no divisor.
  - `Scoring.Flags(run, nameOf, set)` (`:134-151`) returns flags in this order: lateCasts, restarted, reloaded, sessionFromList, sharedSession, died, incomplete, lost.
  - The score is the player's own row total (DR `Meter.lua:153-170`, `playerRow`). It reads the player alone (CT `Meter.lua:5-6`).
- **CT seam:**
  - `final.merged.total` (player plus pet, `Fight.lua:205-217`).
  - Recorder's fight `dps = total / duration`, where duration is the meter session's (`Recorder.lua:271-277`, `:338`).
- **Owner:** A3 (`RaceRecord.Dps`), B1 (`RaceScoring.lua` = DR `Scoring.lua`).
- **What differs:**
  - Spec §6 says "score = the session total". Use `merged.total` so race and fight agree. For a pet class that is higher than DR's figure; note it in the docs.
  - `Scoring.Dps` reads `run.status` and `run.result.endedAt`. Re-point it to `race.status` and `race.endedAt`.
  - The fight's own `duration` and `dps` stay in the record.
- **DR tests:** `test_scoring.lua` ("Dps complete = damage / length", "Dps incomplete = damage / endedAt", "Flags order and text", "Flags names late-cast spells through an optional resolver", "a clean complete run has no flags; lost stands alone at the end").

### #18 DR run fields onto the race part (spec §6)

| DR | CT `fight.race` / record `race` |
|---|---|
| `run.race.length` | `length` |
| target category (DR `Dummies.CategoryOf`) | `kind` |
| `run.status` (`armed/running/stopping/complete/incomplete/lost`) | `status` (`running/stopping/complete/incomplete/lost`; `armed` never reaches a fight) |
| `run.flags.{lateCasts, restartedAt, reloaded, died, sessionFromList, sharedSession}` | `flags.{…}` same names |
| `run.result.damage` | `score` |
| `run.result.dps` | `dps` |
| `run.result.tail` | `tail` |
| `run.result.endedAt` | `endedAt` |
| `run.result.combatEnd` | `combatEnd` |
| `run.race.grace`, `run.race.restartGap` | `grace`, `restartGap` |
| `run.race.startedAt`, `sessionID`, `armMaxSession`, `lastDamage`, `baseline`, `startSource` | not in spec §6. `startedAt`, `sessionID`, `armMaxSession` and `lastDamage` belong in `pendingRaces` (B2) only. `baseline` (spell table) is dropped after netting. |
| `run.result.meterDps`, `sessionDuration` | covered by record `meterDps` / `duration` |

- **Owner:** A3 (`RaceRecord.Plain`). Everything goes through `Recorder.PlainCopy` (`Recorder.lua:199-211`).

### #19 Sticky-combat hint delay and the Stop!/Waiting phase

- **DR:**
  - `hintDelay = 15` (`defaults/Profile.lua:106`). It reads `race.hintDelay`.
  - `stopView` (`Hud.lua:260-271`) shows the hint when the phase is `"waiting"`, the player is in combat, and `SinceBuzzer() >= delay`.
  - `stopPhase` (`:225-229`): `"waiting"` when there was no buzzer or `quietFor >= QUIET_BEFORE_READ`, otherwise `"stop"`.
  - `quietFor` = `Elapsed() - race.lastDamage` (`:213-220`).
  - Hint text: `hintText` (`:252-258`), naming `Hud.DROP_COMBAT = {5384 Feign Death, 1856 Vanish, 58984 Shadowmeld, 66 Invisibility}` (`:76-80`, filtered by `IsPlayerSpell`).
- **CT seam:** Race window states (C1). They need `Race.SinceBuzzer()`, `Race.Elapsed()`, `race.lastDamage` (in memory), `Race.StopRequested()`.
- **Owner:** C1. The setting row is B3's.
- **DR tests:** `test_hud.lua`, `test_hud_hint.lua` (hud area).

### #20 Event wiring per state

- **DR:** `Watchers.lua:253-279`.
  - `RACE_EVENTS`: `DAMAGE_METER_CURRENT_SESSION_UPDATED`, `_COMBAT_SESSION_UPDATED`, `_RESET`, `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`, `PLAYER_DEAD`.
  - `CAPTURE_EVENTS` (from ARMED): `UNIT_SPELLCAST_SUCCEEDED` (player, pet), `_CHANNEL_START`, `_CHANNEL_STOP` (player).
  - `JUDGE_EVENTS` (from RUNNING): `_START`, `_EMPOWER_START`, `_INTERRUPTED` (player).
  - `wanted()` (`:353-359`): none when idle or result.
  - Two registrants: an AceEvent target for the non-unit events and a unit-filter frame for the casts, both through `NS.SafeRegister*`. Perf tag `"raceEvent"`.
- **CT seam:** `Watchers.lua:38-48`, `:85-91`, keyed on Fight state only. Its events are regen, encounter and the three meter events; it has no casts and no `PLAYER_DEAD`.
- **Owner:** B1.
- **Recommendation:**
  - Keep a separate race watcher, e.g. `modules/RaceWatchers.lua` or a section of `Race.lua`, synced from Race's `setState`.
  - ARMED: nothing beyond the bus. The first hit comes from Fight (#3), and the arm's reset handling from `DAMAGE_METER_RESET`, which is optional; Fight's loss covers RUNNING.
  - RUNNING and STOPPING: `DAMAGE_METER_COMBAT_SESSION_UPDATED` (timeline stamps), `PLAYER_REGEN_ENABLED`/`DISABLED` (`endedAt`, `combatEnd`), `PLAYER_DEAD`, and the player's judge and channel events.
  - A second AceEvent target and its own frame do not clobber CT's.
  - Drop DR's `CAPTURE_EVENTS` → `Casts.Hear`.
  - Add `Race` (and the watcher) to `core/LifecycleSetup.lua:14-16` `MODULES` for `Suspend`/`Resume`.
- **DR tests:** `test_disabled.lua` ("Disabled (race): Watchers holds no registrations and Race does nothing while disabled", "a disabled login resumes nothing until the addon is enabled"), `test_race.lua` ("a sealed meter type or session ID moves nothing and stores nothing"). CT `test_fight.lua` ("idle registers only the idle events", "COMBAT_LOG_EVENT_UNFILTERED is never registered", "an event the client rejects costs only itself…") should get race twins.

### #21 Bus messages and finalizing before Recorder saves

- **DR:** `core/Bus.lua:9-17`: `RACE_STATE_CHANGED(run, from, to)`, `RACE_BUZZER(run)`, `RACE_RESULT(run)`, `RUN_SAVED(run)`, `RUNS_CHANGED`. Consumers of `RACE_STATE_CHANGED`: `Hud.lua:1149`, `Countdown.lua:347`, `AutoArm.lua:229`, `Preview.lua:252`, `Share.lua:286`. Consumers of `RACE_RESULT`: `BestToast.lua:351`, `Share.lua:289`, `Hud.lua:1151`.
- **CT seam:** `core/Bus.lua:9-41`, `NS.SendBus` (`:127-130`).
  - `FIGHT_ENDED` receivers: `Recorder.lua:382-387`, `Casts.lua:290-298`, `Hud.lua:998`, `Slices.lua:389`, `Usage.lua:578`.
  - CallbackHandler dispatches with `next()` over a table keyed by target (`libs/CallbackHandler-1.0/CallbackHandler-1.0.lua:15-21`, `:129`), so receiver order is undefined.
- **Owner:** B1 (messages, `Race.Finalize`), A3 (Recorder hook).
- **Recommendation:**
  - Do not rely on registration order. `Recorder.OnFightEnded` (`Recorder.lua:367-380`) calls `NS.Race.Finalize(fight, final, reason)` first, synchronously.
  - Finalize nets the final for a shared session, sets `fight.race` (score, dps, status, flags, tail, endedAt, combatEnd), or sets `fight.race = nil` when cancelled or not a dummy.
  - Then Recorder applies:
    - `lost` reason → skip `"lost"`, and Race goes to RESULT/lost;
    - `fight.race` with `complete` or `incomplete` status → bypass `Filters.Passes` (`:373`);
    - otherwise the normal path.
  - `Build` (`:327-350`) copies `race` through `RaceRecord.Plain`, then `Save` (`:103-112`), which calls `Bests.Invalidate()` and then `FIGHT_SAVED(record)`.
  - Only after Save returns, Race sends `RACE_RESULT(record)`. Recorder calls `NS.Race.OnSaved(record)`, or Race hears `FIGHT_SAVED` and matches `fight.recordID` (`:378`). `BestToast`'s `Bests.Before`/`Delta` then see the new record.
  - The order on the bus for one race: `RACE_ARMED` → `FIGHT_STARTED` → (first hit) `RACE_STARTED(race, fight)` → `FIGHT_TICK`… → `RACE_BUZZER` → `FIGHT_ENDED` → [`Race.Finalize`, pulled] → `FIGHT_SAVED` → `RACE_RESULT`.
  - `Casts.Finish` already copes with either order against Casts' own receiver (unpark or close, `Casts.lua:211-215`).
- **Gap:** the plan's list (`RACE_ARMED`, `RACE_STARTED`, `RACE_BUZZER`, `RACE_RESULT`, `RACE_CANCELLED`) drops `RACE_STATE_CHANGED`, which five DR modules consume. Either keep it (one message, `(race, from, to)`) or map each consumer to the new set in C1, C2, B3 and E1.
- **DR tests:** `test_race.lua` (RACE_BUZZER). New B1 test pins the order: "the race part is on the fight before Recorder builds the record" and "RACE_RESULT follows FIGHT_SAVED".

### #22 Stand-down, `/reload` and Fight's silent drop

- **DR:**
  - `Race.Suspend()` (`Race.lua:693-698`) drops memory and timers; the stored run stays.
  - `Race.Resume()` (`:755-766`) rebuilds from `Recorder.Pending()`.
  - Every input and verb returns early `if isDown()`.
- **CT seam:**
  - `Fight.Suspend` (`Fight.lua:467-472`) drops the fight with no `FIGHT_ENDED`.
  - `Fight.Resume` (`:475-477`) comes back IDLE, and "a combat already under way is not picked up". `Meter.Prime` at stand-up marks the running session as baseline (`Meter.lua:30-36`).
- **Owner:** B1 for Suspend. B2 for Resume.
- **Conflict for B2:**
  - After a `/reload` mid-race, CT has no fight to re-attach to, and its baseline stamp excludes the race session. The plan's "re-attach to the fight the meter session belongs to" needs a Fight seam: adopt a known session ID as a resumed fight.
  - Alternatively the resumed race reads its stored `sessionID` itself through `Meter.ReadFinal` and builds the record through `Recorder.Build` with a synthetic fight.
  - Pin "Disabled (race): an armed race is dropped by the stand-down and not resumed".
- **DR tests:** `test_race_resume.lua` (resume area), `test_disabled.lua` (race cases).

### #23 Slices (race parts)

- **DR:**
  - `Slices.lua:25-27`: `MAX = 60`, `LATE = 1.0`. Buckets = `min(60, floor(length))` over the race clock (`Count`, `Boundary`).
  - `Capture(run, elapsed, total)` (`:76-93`) leaves a bucket empty while `flags.sharedSession` is set.
  - `Drawable(run)` (`:117-125`) is nil for a lost run, a shared run, or one with no plain damage.
  - Captured from DR's HUD only (`Hud.lua:804-817`, plus a timer at each boundary and at the buzzer).
- **CT seam:** `Slices.lua`: `STEP = 2`, `MAX = 60`, `MAX_STEPS = 1800`, `LATE = 1.0`, `KEEP = 50`, keyed by fight id with record-id aliasing (`:380-398`). It has no shared-session rule.
- **Owner:** C1 (no chart in the Race window, spec §4.2), C3 / B1 for the shared hole.
- **What differs:**
  - The race needs no buckets of its own; the CT HUD draws the fight's curve.
  - A shared-session race's live totals include the pre-arm damage, which cannot be netted live. CT draws it anyway. Add a hole rule such as DR's (`fight.sharedSession` → no capture) or accept the gap.
  - Pace curve: spec §4.4 keeps CT's.
- **DR tests:** `test_chart.lua` (hud area).

### #24 Meter race reads

- **DR:** `Meter.IsAvailable() -> ok, reason` (`Meter.lua:59-67`), `SessionIDs() -> set` (`:72-82`), `HasSession(id)` (`:87-90`), `ReadSession(id) -> {damage, meterDps, duration, spells{id,dmg,dps}} | nil, "missing"|"sealed"|"unavailable"|"error: …"` (`:153-170`), `NewLiveRace()` (`:245-247`), `ReadLive()` (`:253-270`).
- **CT seam:** `Meter.IsAvailable` (`Meter.lua:116`), `SessionIDs() -> set, ok` (`:149-170`, stamps as it reads), `HasSession` (`:172`), `ReadFinal(id, petGUID)` (`:417-438`, `{duration, player, pet, merged{total, dps, spells{spellID,total,isPet}}}` with the same error strings), `NewLiveFight` (`:566`, called by Fight).
- **Owner:** B1. Race calls `Meter.*` only; `Meter.lua` stays the only file naming `C_DamageMeter`.
- **What differs:**
  - Field names: `dmg`/`id` become `total`/`spellID`, and pet rows are separate.
  - Race never calls `ReadLive` (the HUD's job).
  - Calling `SessionIDs()` at the arm also stamps IDs, which is harmless and is in fact what makes them "before".
- **DR tests:** `test_meter.lua` (DR), `test_secrets.lua`. CT `test_meter.lua` already covers ReadFinal.

### #25 Persistence during a race

- **DR:** `Recorder.Save(run)` runs at adopt, share, unshare, begin, stop, lose and complete (`Race.lua:158, 251, 309, 416, 430, 439, 456`). The run table is the stored table, so every field is in SavedVariables at once (`:13-17`).
- **CT seam:** `Recorder.lua:17-18`: "NOTHING IS WRITTEN BEFORE FIGHT_ENDED final".
- **Owner:** B1 (writes nothing mid-race), B2 (`db.global.pendingRaces[charKey]`, plain fields: `length`, `kind`, `grace`, `restartGap`, `startedAt`, `date`, `sessionID`, `armMaxSession`, `lastDamage`, `status`, `flags`, `endedAt`; written at the first hit and cleared at result or cancel).
- **What differs:** DR's "pending" arm refusal and Resume read this store instead of the history.
- **DR tests:** `test_race_resume.lua`, `test_race.lua` ("the diagnostics state section names the race state, run, session and pending count").

## resume

### #1 Race.Resume: entry points, guard, and choosing the pending run
- **DR:** `modules/Race.lua:751-766` (`Race.Resume()`), called from `core/DpsRace.lua:38` (`NS:OnEnable`, right after `NS.Bests.PruneToSetting()` at :36 and before `NS.Hud.Resume()` :40, `NS.AutoArm.Resume()` :42 and `NS.Countdown.Resume()` :44). Also called from the stand-up loop at `core/LifecycleSetup.lua:38-43`, order `{ "Race", "Watchers", "Hud", "AutoArm", "Countdown", "Results" }`, so the watchers register for whatever state the resume ends in.
- **What it does:** it returns early if `isDown()` or `state ~= STATE.IDLE`. It reads `NS.Recorder.Pending()`, which holds this character's runs with status `running` or `stopping`, oldest first. If none, it returns and touches nothing. Every pending run except the newest is settled as lost (`status = "lost"`, `result = nil`, `Recorder.Save`). The newest goes to `resumeRun(run, GetTime())`. The comment says two runs cannot both be pending.
- **CT seam:** `core/CombatTrail.lua:30-37` (`NS:OnEnable`: `RegisterGameEvents()` then the skin-picker timer; no resume call today) and `core/LifecycleSetup.lua:14-16` (`MODULES` = Preview, LaneCasts, LaneAnchor, LaneVisibility, LaneRender, Probe, Meter, Fight, Watchers, Casts, Usage, Loadouts, Retention, Slices, Hud, Results), with the stand-up at `:41-46`. **Owner: B2**, which produces `Race.Resume()` "from OnEnable and stand-up".
- **Differs:** `Race.Resume` must run after `NS.RegisterGameEvents()`, because that calls `Meter.Prime()` (`core/CombatTrail.lua`, `modules/Meter.lua:178`) and `resumeRun` calls `Meter.HasSession`. In `MODULES`, "Race" goes after "Meter" and "Fight" and before "Watchers", matching DR. DR's "older run settled as lost" case mostly goes away because CT keys pending races by character (one slot per character, #3). The port keeps the test as "a stale slot is overwritten or settled".
- **DR tests:** `test_race_resume.lua` "resume: an older unresolved run is settled as lost; the newest is carried on", "resume: nothing stored leaves the race idle and touches nothing"; `test_disabled.lua` "Disabled (race): a disabled login resumes nothing until the addon is enabled", "Disabled (race): Watchers holds no registrations and Race does nothing while disabled" (it asserts `run.flags.reloaded` after the stand-up).

### #2 Where DR saves a running run (and what is not saved)
- **DR:** `modules/Recorder.lua:15` (store `db.global.runs`, keyed by run id, account-wide), `:274-299` `Recorder.NewRun(length)`, `:302-309` `Recorder.Save(run)`, `:357-365` `Recorder.Pending()`, `:348-355` `Recorder.IsMine(run)`, `:404-405` `PRUNABLE = { complete, incomplete, lost }`. `Race.lua:13-17` notes that the stored run is the same table as the one in memory, so any field set on it is in SavedVariables at once.
- **When it is written:** `Race.Arm` (`:379-407`) does not save. The run has `status = "armed"`, and `Recorder.All` excludes armed runs. The first save is in `begin(t)` (`:443-461`): `status = "running"`, `date = time()`, `race.startedAt = t` (GetTime). It is saved again at `adopt` :409-421 (`race.sessionID`), `share`/`unshare` :423-441 (`flags.sharedSession`, `race.baseline`), `stop()` :305-312 (`status = "stopping"`), `lose()` :151-162 and `complete()` :238-253. `stamp(t)` (:199-208) writes `race.lastDamage` (round2 of the offset from the start) and `flags.restartedAt` straight onto the stored table, with no Save call.
- **Fields saved that the resume reads:** `status`, `date`, `char.{name,realm}` (for IsMine), `race.{length, grace, restartGap, startSource="meterSession", armMaxSession, sessionID, startedAt, lastDamage, baseline={session,damage,spells}}`, `flags.{lateCasts, reloaded=false, died, sharedSession, sessionFromList, restartedAt}`, `result.endedAt` (set by `endEarly` :329-336). The snapshots `char`, `target`, `where` and `stats` are taken at NewRun.
- **Memory only, lost on /reload (the `cur` fields, :38-49):** `armSet` (stood in for by `race.armMaxSession`; see `beforeArm` :165-169, which relies on session IDs only growing), `armTarget`, `armLoadout`, `usageSnap`, the Casts list, every timeline stamp except `lastDamage`, `combatEndedAt` (so `result.combatEnd` is not measured), `stash*`, `combatAt`/`sessionAt`, `stopNow`, `inFlight`, `sealedTries`, `buzzer`/`ticker`, `baseline` (kept only on the run when shared).
- **Other gates:** `stateRefusal()` (:344-348) refuses an arm with `"pending"` while `#Recorder.Pending() > 0`. Prune never removes a running or stopping run (`PRUNABLE`, `protectedIDs` :408-416), so the login prune cannot take what Resume picks up.
- **CT seam:** `modules/Recorder.lua:17-18` says "NOTHING IS WRITTEN BEFORE FIGHT_ENDED 'final'", and the store is `db.global.fights` / `db.global.fightOrder` (`defaults/Profile.lua:230-246`). `defaults/Profile.lua` has no `pendingRaces` key. **Owner: B2**, which adds `db.global.pendingRaces[charKey]` (plain fields only), written at the first hit and cleared at the result or a cancel.
- **Conflicts:** (a) DR's model, a partial run kept in the main store, is forbidden in CT. `tests/test_record.lua:342` "reload mid-fight leaves store valid" asserts `Recorder.Count() == 0` and `#fightOrder == 0` during the fight, during settling and after a reload. B2's separate `pendingRaces` keeps that test true, so it must not be relaxed. (b) DR has no character key. It filters a list by `IsMine` (name, plus realm when both are known). CT's natural key is `NS.Bests.CharKey(who)` = `"name|realm|client"` (`modules/Bests.lua:23-29`), which returns nil with no readable name, so B2 needs a fallback or must skip persisting in that case. (c) In CT, `Recorder.OnFightEnded` drops a fight as `"unknown"` without `fight.snapshot.who` (`modules/Recorder.lua:359-376`), and `Recorder.Build` reads `fight.snapshot`, `fight.stats`, casts and loadout. So the pending entry must hold the plain `snapshot` (`who` and identity seed) and `stats` taken at the start, or a resumed race cannot become a record. (d) The arm refusal must also say `"pending"` while this character's slot is filled (B1's `Race.Arm` reasons list "while pending").
- **DR tests:** `test_recorder.lua` "recorder: Pending returns running and stopping only", "recorder: Pending holds only the logged-in character's runs" (:274 asserts `#Pending() == 0` once resumed); `test_race_resume.lua` "resume: a run another character left pending is not resumed here".

### #3 An armed race with no first hit is dropped
- **DR:** `Race.Arm` never saves (#2). `Race.Suspend()` (`:693-699`) runs `cancelTimers()`, `NS.Casts.Reset()`, `cur = {}` and `state = IDLE`, with no message and no store write. `Race.Cancel()` (`:678-689`) deletes the stored run only when it is running or stopping: `Recorder.Delete(run.id)` unless the state is ARMED or RESULT.
- **CT seam:** B2's rule "An armed race with no first hit is dropped", Review focus 2 in the plan (`plans/2026-11-11-race-mode.md:93-94`), and the new test `resume: an armed race with no first hit is dropped and the window is idle`. **Owner: B2**. The write to `pendingRaces` happens at the first hit (FIGHT_STARTED on a dummy, B1), never at the arm.
- **Differs:** nothing in behavior. In CT a cancel after the first hit must also clear `pendingRaces[charKey]`, which DR does with `Recorder.Delete`.
- **DR tests:** `test_disabled.lua` "Disabled (race): an armed race is dropped by the stand-down and not resumed".

### #4 resumeRun: rebuilding the clock and the timeline
- **DR:** `modules/Race.lua:702-708` `startOf(run, now)`, `:726-749` `resumeRun(run, now)`.
- **What it does:** `newRace(run)` creates a fresh `cur` with a new `NS.Timeline.New()`, an empty `armSet` and `sealedTries = 0`. `cur.startedAt = startOf(run, now)`. That is `run.race.startedAt` when it is a number `<= now`, because GetTime survives a /reload. Otherwise, after a machine restart, it is `now - max(0, time() - run.date)`. It sets `cur.reread = true` (no target re-read at combat start) and `cur.resumedAt = now`. It reads `Secrets.PlainNumber(run.race.lastDamage)` and, when present, `timeline:AddDamage(startedAt + last)`, so the tail and restart gap measure from the last update before the reload. `Timeline:RestartAt(buzzer, gap, resumedAt)` (`modules/Timeline.lua:50-60`) moves the gap's start up to `resumedAt` when the gap spans the reload, because the damage landed during the loading screen is unknown. If `run.race.sessionID ~= nil and not NS.Meter.HasSession(id)`, it calls `lose("session gone")`.
- **CT seam:** CT has a `Meter.HasSession(id)` (`modules/Meter.lua:172-175`), same name and meaning. B1 creates `modules/RaceTimeline.lua` (port of DR Timeline, `RestartAt` with `resumedAt`). **Owner: B2**, using B1's RaceTimeline.
- **Differs:** in CT, `Meter.Prime()` (`modules/Meter.lua:178-181`, called in `RegisterGameEvents` at OnEnable and at the stand-up) stamps every session already held with `t = BASELINE (-math.huge)` (`:125-139`). The race's live session is one of them, so `Meter.SessionsAfter(t)` / `SessionAfter(t)` never return it again (#5). DR's `armMaxSession` high-water mark (`beforeArm`) is needed for a run with no `sessionID`. B2 must persist an equivalent (CT's fight binds by time stamps, not by IDs).
- **DR tests:** `test_race_resume.lua` "resume: session gone becomes lost", "resume: a reload that outlasts the restart gap while DoTs tick is not a restart", "resume: the tail and a restart heard before a /reload survive it", "resume: the stamps before a /reload keep a DoT tail across it from looking like a restart", "resume: a run with no session ID never adopts a session from before its arm"; `test_timeline.lua` "timeline: a gap that spans a resume is measured from the resume".

### #5 Running at reload: still in combat with time left re-arms the buzzer
- **DR:** `modules/Race.lua:711-724` `resumeRunning(run, now)`, `:324-327` `armBuzzer(delay)` (`C_Timer.NewTimer(max(0, delay), buzz)`), `:314-322` `buzz()` (`buzzerAt = startedAt + length`, `stop()`, `RACE_BUZZER`).
- **What it does:** it computes `elapsed = now - cur.startedAt` and `left = run.race.length - elapsed`. If `left > 0` and `UnitAffectingCombat("player")`, it calls `setState(RUNNING)` and `armBuzzer(left)`, and the race carries on. Live updates then stamp through `OnMeterUpdate` (:551-567), since `cur.run.race.sessionID` is still known. If `left > 0` and the player is out of combat, it sets `run.result = { endedAt = round2(elapsed) }`: the run is incomplete, and the real time of the combat-end edge is unknowable. Then, when the run is not still running, it sets `run.status = "stopping"`, calls `Recorder.Save` and returns false (#6). `Countdown.Resume()` (`modules/Countdown.lua:330-332`) calls `schedule()` if a race is running, so the final-seconds marks come back. `Hud.Resume()` (`modules/Hud.lua:1036-1039`) shows the HUD under `"always"` and refreshes.
- **CT seam:** `modules/Fight.lua:466-477`. `Fight.Suspend()` clears `cur`, `parked`, `encounter` and `sealedTries` and sets IDLE. `Fight.Resume()` only sets `state = STATE.IDLE`, with the comment "a combat already under way is not picked up (Review Focus 4)". `modules/Watchers.lua:38,87-88`: in IDLE, Watchers registers only `PLAYER_REGEN_DISABLED` and `ENCOUNTER_START` (plus `ENCOUNTER_END` while an encounter is active). **Owner: B2**.
- **Conflict (load-bearing):** the plan says B2 "re-attaches to the fight the meter session belongs to", but after a reload in combat CT has no such fight. Fight is IDLE. No regen edge arrives until combat ends and restarts. `ENCOUNTER_START` only begins a fight if it fires in combat (`Fight.lua:446`). The race's session is primed as BASELINE (#4). B2's Files list `Race.lua` and `defaults/Profile.lua` only, and B1's one listed Fight seam is `Fight.Hurry()`. So B2 needs a new Fight seam, for example `Fight.Adopt(sessionID, startT, snapshot)`: it enters COMBAT bound to that session, or SETTLING when out of combat, and ends in the normal `FIGHT_ENDED` → `Recorder.OnFightEnded` path. The other route is for Race to read the session itself with `Meter.ReadFinal(id, petGUID)` (`modules/Meter.lua:417`) and build the record, which duplicates the Fight and Recorder pipeline. The spec (§ risks, line 256) lists "reload" as a Fight/Race handoff with its own test. This must be flagged, and the plan's B2 Files/Interfaces updated to include `modules/Fight.lua`.
- **DR tests:** `test_race_resume.lua` "resume: running before buzzer keeps running with remaining time", "resume: running before the buzzer with combat already over is incomplete and read at once"; `test_countdown.lua` "countdown: a /reload with 4s left resumes at 4 and counts 3, 2, 1", "countdown: a /reload before the window shows nothing until it opens", "countdown: a /reload past the buzzer shows nothing"; `test_hud_window.lua` "hud: a race resumed after a /reload shows the HUD under onArm".

### #6 Past the buzzer or stopping: STOPPING, `reloaded` flag, the read
- **DR:** `modules/Race.lua:736-749` (the rest of `resumeRun`), `:288-303` `poll()` / `startPolling()`, `:272-286` `checkReady(t)`, `:255-270` `read()`.
- **What it does:** when the run is not already incomplete (no `run.result.endedAt`), it sets `cur.buzzerAt = cur.startedAt + run.race.length` and `run.flags.reloaded = true`, because casts made during the reload were unseen. An incomplete run (it ended before its buzzer) is not flagged `reloaded`. Then `setState(STOPPING)` and `startPolling()` (`Race.POLL_INTERVAL = 0.5` s ticker). Out of combat it sets `cur.quietFrom = now - NS.Scoring.QUIET_BEFORE_READ` (2.5 s, `modules/Scoring.lua:19`), so the quiet counts as spent during the reload, and `checkReady(now)` reads straight away. In combat it waits for `OnCombatEnd` (the regen edge), which sets `quietFrom` and attaches a fresh `Loadouts` snapshot. If the edge is never heard, `poll()` notices `not UnitAffectingCombat` with no `quietFrom` and counts the quiet from then. The read: `sessionToRead()` takes `race.sessionID`, else the newest session with ID `> armMaxSession` (flag `sessionFromList`). Then `Meter.ReadSession(id)`. A `"sealed"` result is retried up to `Race.SEALED_RETRIES = 20` times (10 s at 0.5 s), then `lose`. Otherwise `complete(data)`: status is `incomplete` if `result.endedAt`, else `complete`; it calls `Scoring.Dps`, `keepLoadout`, `keepUsage`, `Save`, then `finish()` → RESULT + `RACE_RESULT`.
- **CT seam:** CT Fight's own settle (`modules/Fight.lua` `settleDue` :263, `finishAll` :247-261, `Fight.RETRY = 0.5`, `Fight.SEALED_RETRIES = 10`, `C.FIGHT = { GRACE = 4, SETTLE = 2, TICK = 0.25 }` at `core/Constants.lua:55`) does the read with `Meter.ReadFinal` and emits `FIGHT_ENDED(fight, final, reason)`. **Owner: B2**, for the settle rules: "incomplete before the buzzer, `reloaded` past it, read when out of combat". B1 owns the race's scoring on `FIGHT_ENDED`.
- **Differs:** DR's read is Race's own (quiet 2.5 s, 20 sealed retries). CT's is Fight's (SETTLE 2 s after GRACE 4 s, 10 retries). With a re-attach seam (#5), a resumed race inherits CT's settle timings and DR's resume-time "quiet already spent" shortcut has no equivalent unless the new Fight seam takes a "settle now" (compare B1's `Fight.Hurry()`). `flags.reloaded` lives in `fight.race.flags` (spec §6). The read must also respect a `sharedSession` baseline (`race.baseline`) persisted in the pending slot.
- **DR tests:** `test_race_resume.lua` "resume: running past buzzer becomes stopping+reloaded", "resume: stopping out of combat reads immediately", "resume: stopping in combat waits for the regen edge", "resume: an incomplete run waiting for its read stays incomplete", "resume: a stopping run that ended before its buzzer is not flagged reloaded", "resume: a stand-down mid-run whose combat ends unseen never hangs in stopping"; `test_loadout.lua` "loadout: a run resumed after a /reload whose combat ended unheard still takes a loadout".

### #7 What a resumed run cannot recover
- **DR:** `modules/Race.lua:136-149` `keepUsage` (returns when `Casts.Collecting()` is false, so a resumed run keeps no `casts` and no `usage`), `:130-134` `keepLoadout` (arm loadout gone; out of combat it takes a fresh `Recorder.SnapshotLoadout()`), `:49` (`usageSnap` nil for a resumed run), `:189-195` `timing` (`combatEnd` only when the edge was heard after the resume). Chart slices were in memory, so a run from before the reload has no chart.
- **CT seam:** `docs/known-limitations.md:12-14` already says "A stored fight's damage chart lasts one session" (`modules/Slices.lua`). It has no line for "a /reload mid-fight drops the fight", although `Fight.Resume` (`modules/Fight.lua:474`) and `Recorder.lua:17-18` say so in comments. **Owner: B2**, which writes "casts, usage and chart slices are not recovered" to `docs/known-limitations.md`.
- **Differs:** CT's record also carries `cooldowns`, `gearSet`, `targets` (`Recorder.Build`, `modules/Recorder.lua:327-351`). `cooldowns` come from Casts and are lost the same way. `targets` (`Meter.ReadEnemies`, after combat) and gear (taken at the read) can still be filled. Per spec line 219, the plain-fight reload gap stays a known limitation unless it comes cheap. If B2 adds the Fight re-attach seam (#5), most of the plain-fight fix comes with it, which the owner should decide. Either way, the known-limitations doc should get both the race line and the plain-fight line.
- **DR tests:** `test_usage.lua` "usage: a run resumed after a /reload keeps no casts and no usage"; `test_chart.lua` (around :419 and :510, "a run from before the reload has no chart"); `test_loadout.lua` "loadout: a run resumed after a /reload whose combat ended unheard still takes a loadout".

### #8 CT today: nothing is persisted mid-fight, and a reload in combat loses the fight
- **CT:** `modules/Fight.lua:466-477` (Suspend/Resume, quoted in #5). `modules/Recorder.lua:17-18` (no write before `FIGHT_ENDED "final"`). `modules/Meter.lua:178-186` (`Prime` and `Suspend` reset `seen`, `primed`, `seq`). `core/CombatTrail.lua:30-37` (OnEnable: `RegisterGameEvents` → `Meter.Prime`, `Identity.Prime`, `Watchers.Sync`). Fight ids are `("%d-%d"):format(time(), seq)` in memory (`Fight.lua:113-117`). The v0.1.0 plan's Review Focus 4 (`plans/2026-11-10-combat-trail-v0.1.0.md:153`) says: "the in-progress fight is discarded cleanly ... nothing errors on the next load".
- **Behavior on /reload in combat:** Fight comes back IDLE with no fight. The live session is primed as BASELINE and is never bound. The rest of that combat is not tracked until the next `PLAYER_REGEN_DISABLED`, or an `ENCOUNTER_START` while in combat. Nothing about the fight was saved, so nothing is lost from the store and nothing is half-written. Slices and casts for it are gone.
- **Owner:** B2 for the race path. The plain-fight path stays as it is unless the owner widens B2 (#7).
- **CT tests that pin this and must stay green:** `tests/test_record.lua` "reload mid-fight leaves store valid"; `tests/test_fight.lua` "fight: a stand-down mid-fight drops the fight, its timers and every registration", "fight: meter reset mid-fight → lost".

## hud

Scope: DR `modules/Hud.lua` (1308 lines), `Hud_States.lua` (1486), `Hud_Best.lua` (200), `Hud_Tips.lua` (62), `Hud_Chart.lua` (pace parts only), `Countdown.lua` (351), `BestToast.lua` (421), and Sizing usage, read against CT `modules/Hud.lua` (1070), `Hud_States.lua` (643), `Hud_Best.lua`, `Hud_Tips.lua` (48), `Hud_Chart.lua`, `Hud_Appearance.lua` (318) and `Style.lua` (697) on `feat/2026-11-11-race-mode`.

Classification key, used in every body table:
- **KEEP**: goes into the Race window (C1).
- **ALREADY**: the CT HUD already draws it during any fight, so a race gets it too (chart, spell rows, Damage and DPS boxes).
- **DROP**: not ported.

---

### #1 Name collisions: the Race window needs its own namespaces
- **DR:** `Hud.lua:55` `NS.Hud`, `Hud_States.lua:27` `NS.HudStates`, `Hud_Best.lua:20` `NS.HudBest`, `Hud_Tips.lua:62` `NS.HudTips`, `Hud.lua:81` `FRAME_NAME = "DpsRaceHud"`.
- **CT:** every one of these names is already taken by the CT HUD. `NS.HudBest` (CT `Hud_Best.lua:27`) is CT's **pace-curve** module, not a best card. `Hud.FRAME_NAME = "CombatTrailHud"` (CT `Hud.lua:84`).
- **Owner:** C1. Use new names, for example `NS.RaceWindow`, `NS.RaceWindowStates`, `NS.RaceWindowBest`, race tip keys, and a frame name such as `"CombatTrailRaceWindow"`, which must be added to `UISpecialFrames`. Never shadow the CT globals.

### #2 Window shell (DR `Hud.lua:582-614` `ensureWindow`)
- **DR behavior:**
  - `CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")`, then `SetFrameStrata(LAYERS.STRATA.HUD)` ("MEDIUM"), `SetToplevel(true)`, `SetClampedToScreen(true)`, `SetMovable(true)`, `EnableMouse(true)`.
  - Builds the header and footer, then `ui.content` inset `PAD=12` at the sides, `CONTENT_TOP = TITLE_BAR_H(30)+10`, `CONTENT_BOTTOM = FOOTER_H(20)+8`, with `SetClipsChildren(true)`.
  - Then `NS.ApplySkin(f)`, `OnHide → onHide`, an insert into `UISpecialFrames`, `NS.Sizing.MakeResizable`, and `applyPlacement`.
  - Stores its position and width in `db.profile.windows.hud` (`{point, relativePoint, x, y, width}`), default `width = 260`. `MIN_WIDTH 260`, `MAX_WIDTH 600` (`Hud.lua:68-70`). Scale is the General `scale` (`Hud.lua:452`).
- **CT seam to copy line for line:** CT `Hud.lua:467-497` `ensureWindow` (same calls, with `hookPointer`), CT `Hud.lua:547-563` `applyWindow`, and `NS.HudAppearance.ApplyWindow(f)` (CT `Hud_Appearance.lua:302`). `ApplyWindow` sets the background and border from `hud.window.*`, the strata from `hud.window.strata`, and the alpha from `hud.window.alpha`. CT position is `hud.position` with `{point, relPoint, x, y}`; note CT says `relPoint` where DR says `relativePoint`. CT scale is `hud.scale`.
- **What differs:** CT content insets depend on `hud.window.titleBar` and `footer` (`contentTop`/`contentBottom`, CT `Hud.lua:295-297`), and the test-strip height is folded in. For the Race window to look identical it must:
  - run `A.ApplyWindow`;
  - honor `hud.window.titleBar`, `title` and `footer`;
  - use `hud.scale` (it must be the HUD's scale while attached, or docking misaligns);
  - store its detached position in its own key (plan `raceWindow.*`), never in `hud.position`.
- **Lock:** DR reads the General `locked`. CT reads `general.locked` (CT `Hud.lua:772`). The plan adds a `raceWindow` lock, so the builder must decide whether it follows `general.locked` or is separate. Spec §4.3 says "detached ... can be locked".
- **Owner:** C1. **DR tests:** `test_hud_window.lua` (skinned, Escape, clamped, Lock and scale, Reset position), `test_layers.lua` ("the Race HUD is MEDIUM, toplevel and clamped").

### #3 Title strip and controls (DR `Hud.lua:537-562` `buildHeader`)
- **DR:**
  - Title `FONT.TITLE` with `L["DPS Race"]`, left-aligned.
  - `ui.controls = Style.NewStrip()`.
  - Close is `NS.MakeCloseButton(f, Act.close)` with tip `HudTips.close`.
  - Three controls: `Style.ControlButton(f, "unlock", "L", L["Lock or unlock the HUD"], Act.lock)`, `("settings", "S", L["Settings"], Act.settings)`, `("chart", "R", L["Results"], Act.results)`, each passed to `Style.AddToStrip`.
  - A drag frame on the band. `Style.Header(f, { title, align = "LEFT", drag, right = { close, lock, settings, results }, n = 4 })`.
  - `applyLock` swaps the icon `lock`/`unlock` (`Hud.lua:616-619`).
- **CT seam:** CT `Hud.lua:411-432` is identical in shape (title `L["Combat Trail"]`). Helpers: `Style.Header` (CT `Style.lua:551`), `Style.ControlButton(parent, name, glyph, tip, onClick)` (`:597`), `Style.SetControlIcon(b, name, glyph)` (`:619`), `Style.NewStrip`/`AddToStrip` (`:413`/`:427`), `Style.Band(f)` (`:540`), `NS.MakeCloseButton` (CT `core/CoreSetup.lua`). CT `applyWindow` hides the band, its controls and the drag frame when `hud.window.titleBar` is off.
- **Classification:**

| Control | Class | Note |
|---|---|---|
| Close | KEEP | Closing a result card dismisses it: DR `onHide` calls `Race.Cancel()` in RESULT (`Hud.lua:943`). |
| Lock | KEEP | Detached lock (spec §4.3). |
| Settings | KEEP | Opens the Race mode page (B3), not `NS.OpenSettings()` generically, unless a page argument exists. |
| Results | DROP | The CT HUD's chart control covers it. |
| Attach/detach | NEW | Plan C1: `ControlButton` with `chevron-left/right/up/down` or `move`, all declared in CLAUDE.md. `n` grows to 4 or 5. |

- **Title:** a Race-mode word, such as `L["Race"]` or `L["Race window"]`. Never "DPS Race".
- **Owner:** C1. **DR tests:** `test_header_band.lua`, `test_header_rule.lua`, `test_hud_window.lua` ("a title-bar control turns gold under the pointer…").

### #4 Footer (DR `Hud.lua:564-578` `buildFooter`, `Hud.lua:706-716` `footer`)
- **DR:**
  - A 1 px divider (`NS.Skin.Divider`) at `FOOTER_H=20`.
  - Left `FONT.CAPTION` at (8, 5) holding "spec · name".
  - Right at (-20, 5) holding `L["ilvl %d"]`, or `L["live · %d Hz"]` while running, or `L["result pending"]` while waiting.
  - Tip zones `HudTips.footLeft`/`footRight`.
- **CT:** CT `Hud.lua:434-446` is the same, except the right label sits at -8 and the text differs (`live · 4 Hz`, `Pinned open`, `Fades %d s…`).
- **Classification:**
  - Left "spec · name": ALREADY (the CT HUD footer shows it).
  - Right "result pending": KEEP as optional. The waiting body's title already says it (#16).
  - "live · N Hz": DROP. The Race window does no meter reads of its own at a configured rate (#7).
- Builder's call: show the footer per `hud.window.footer` for parity, or omit it.
- **Owner:** C1.

### #5 Test and sim strip (DR `Hud.lua:627-688`)
- **DR:** `NS.MakeTestStrip(frame, L["Test mode: sample numbers. Combat or Arm ends it"])` and `NS.MakeSimStrip(frame, L["SIM: a scripted race, not your data. /dr sim stop ends it."])` sit under `Style.Band`. The content drops `NS.TEST_STRIP_HEIGHT`. Without the Widgets library the title says `"DPS Race · Test"`.
- **CT:** CT `Hud.lua:503-545` (`STRIP_TEXT`, `stripFor`, `placeStrip`, `applyStrip`). `NS.MakeTestStrip`/`MakeSimStrip`/`TEST_STRIP_HEIGHT` are in CT `core/WidgetsSetup.lua:106-127`.
- **Classification:** KEEP the mechanism, with CT's wording ("/ct sim ends it"; no "/dr").
- **Owner:** C1 (strip). E1 wires the sample race.
- **DR tests:** `test_hud_window.lua` ("test mode's sample race draws through the race's own view…"), `test_preview.lua`, `test_sample_parity.lua`.

### #6 Sizing model (DR `Hud.lua:357-418`, `:513-531`, `:605-610`, `:752-771`; `Hud_States.lua:536-576`, `:1447-1476`)
- **DR:**
  - `hud.sizeMode` "fixed"/"auto", `hud.bars` 1-15, `hud.grow` down/up.
  - `Hud.FixedHeight() = chrome + HudStates.FixedContentHeight(bars, {mode, chart, pace})`.
  - The grip is `NS.Sizing.MakeResizable(f, { minWidth, minHeight, canResize, size = trackSize, layout = layoutCurrent, redraw = layoutBodies, done = resized })`; `normalizeAnchor` holds the grow edge.
  - `States.BaseContentHeight() = IDLE_ARM_Y(220) + ARM_HEIGHT(24) + 4 + REASON_HEIGHT(14) + 4 + LINK_HEIGHT(20) = 286` is the floor of every window, so the idle window is 286 + 40 + 28 = 354 px.
- **CT:** CT `modules/Sizing.lua:88` `MakeResizable` and `:114` `IsSizing`, unchanged in behavior from DR's. CT HUD uses it at CT `Hud.lua:489-494`.
- **Classification:** DROP the grip, `bars`, `sizeMode` and `grow` from the Race window, because every one of them exists only to size spell rows, which the Race window no longer draws.
  - Size the window from config: the tallest body's stack. That is the idle floor of 286 content px, less the dropped Results button (`LINK_HEIGHT` 20 + 4) if C1 drops it.
  - Or, attached LEFT/RIGHT, match `Hud.FixedHeight()`, per spec §4.3 "the HUD's height or its own".
  - Width: 260 (content 236), the value DR's layout constants are tuned to (CLOCK_PAIR fits 236; `layoutRow(…, 236)`).
- **Owner:** C1. **DR tests (DROP or adapt):** `test_hud_sizing.lua` (30 cases, all row and grip driven: DROP), `test_sizing.lua` (CT has its own), `test_hud_layout.lua` "the idle body's whole stack is every window's floor" (adapt).

### #7 What runs: live reads, ticker, events (DR `Hud.lua:774-916`)
- **DR:**
  - **Events while shown:** `PLAYER_TARGET_CHANGED`, `PLAYER_REGEN_DISABLED`/`ENABLED`, `PLAYER_SPECIALIZATION_CHANGED` (`BASE_EVENTS`, `:85`).
  - **While RUNNING:** also `DAMAGE_METER_COMBAT_SESSION_UPDATED`, coalesced to `1/live.hz` (default 4) through `C_Timer.NewTimer` (`requestLive`, `:848-855`). There is also a slice timer at the next chart bucket (`scheduleSlice`, `LIVE_RETRY 0.1`, `:798-812`).
  - **While RUNNING or STOPPING:** one `OnUpdate` (`syncTicker`, `:904-916`), redrawing at `TICK = 0.05` (20 Hz) RUNNING and `STOP_TICK = 0.25` (4 Hz) STOPPING.
  - Events use their own AceEvent target `LibStub("AceEvent-3.0"):Embed({})` via `NS.SafeRegisterEvent`.
  - `captureBuzzer` (`:840-845`) fills the last chart bucket at the buzzer.
- **CT:** the CT HUD registers nothing with the client and sets no OnUpdate ever (CT `Hud.lua:24-28`). It redraws on `FIGHT_TICK` (4 Hz, combat only) with `NS.Meter.ReadLive(sessions[#sessions] or sessionID)` (`readLive`, CT `Hud.lua:895-905`).
- **What differs and conflicts:**
  - The Race window needs no meter-event registration. The only live value it shows is the pace bar's total, which can come from `FIGHT_TICK` plus `NS.Meter.ReadLive` exactly as CT does, or from `NS.Hud.View().live`. DROP the meter event, the `live.hz` coalescer and the slice timer (the chart is CT's).
  - The race clock (tenths, `Format.Clock` "m:ss.t", identical in both repos) still needs a ticker. In combat `FIGHT_TICK` is 4 Hz. STOPPING continues out of combat, where `FIGHT_TICK` stops (`onTick` guards `state == COMBAT`, CT `Fight.lua:340-347`), so the waiting body's "since the buzzer" figure needs its own driver.
  - Keeping DR's 20 Hz OnUpdate is a per-frame cost CT's HUD avoids. **Flag for C1:** pick either a 20 Hz OnUpdate only while RUNNING/STOPPING and shown (DR's) or a C_Timer ticker. Record a `perf` entry in `docs/performance.md` either way.
  - `PLAYER_TARGET_CHANGED` (the idle target card), the regen edges (Arm's combat refusal) and `PLAYER_SPECIALIZATION_CHANGED` (the Your best board) are KEEP, registered only while the window is shown and idle. They are client events, so they need CT's `SafeRegisterEvent` path and a stand-down drop.
- **Owner:** C1. **DR tests:** `test_hud.lua` ("live reads stop when hud hidden or state leaves running", "STOPPING redraws at a few Hz, and a steady stop body rebuilds nothing"), `test_disabled.lua` ("Disabled 4: no timer, ticker or OnUpdate…"), `test_perf_harness.lua`.

### #8 The view and the Race queries it needs (DR `Hud.lua:203-353`)
- **DR builders:**
  - `raceView()` builds `{ state, run, inCombat, preview, bars, fitH, icons, showDps, hz, clockMode }`, then per body:
    - `idleView` (`:290`): `target = Recorder.SnapshotTarget("target")`, `length = currentLength()`, `editing`, `blocker`, `detail = armBlocker()`, `warning = targetWarning(target)`, `best = HudBest.View(target, length)`;
    - `runningView` (`:313`): `timeLeft`, `elapsed` clamped to length, `live`, chart and pace views;
    - `stopView` (`:260`): `key = stopPhase(run)` "stop" or "waiting", `tail`, `sinceBuzzer`, `endedEarly`, `endedAt`, `lateCasts`, `grace`, `stopNow`, `hint`;
    - `resultView` (`:301`): `delta, isNew = Bests.Delta(run)`, `canShare`, chart, pace.
  - `stopPhase` (`:225`): "waiting" when `SinceBuzzer() == nil` (ended before the buzzer) or `quietFor(run) >= Scoring.QUIET_BEFORE_READ`, else "stop". `quietFor` = `Elapsed() - run.race.lastDamage` (or `SinceBuzzer()` with no stamp).
  - The hint (`:252`, `:270-271`): shown when waiting, in combat, and `sinceBuzzer >= race.hintDelay` (15).
  - `Hud.OwnedDropSpells()` (`:238-250`): `DROP_COMBAT` = {5384 Feign Death, 1856 Vanish, 58984 Shadowmeld, 66 Invisibility}, filtered by `IsPlayerSpell`, named via `HudBreakdown.SpellName`. CT has `NS.HudBreakdown.SpellName` (CT `Hud_Breakdown.lua:77`).
  - `armBlocker` (`:275`): "pending" (from `Recorder.Pending()`), "in_combat", "meter_unavailable" (from `Meter.IsAvailable()`).
  - `targetWarning` (`:283`): `L["Unknown target: recorded as Other: %s"]` or `L["No target: the one you fight is read when combat starts."]`.
  - Length memory: `currentLength()` = pick, else `race.lastLength`, else `race.defaultLength` (60) (`:148`); `rememberLength` (`:156`); `Hud.ForgetLength()` (`:163`); `Hud.ArmLength()` (`:1091`).
- **CT seam:** a new `RaceWindow` view, C1.
- **Conflict: B1 must also produce what the view consumes.** Plan B1 lists `State`, `Arm`, `Cancel`, `StopNow`, `TimeLeft`, `Current`. The view also needs:
  - `Race.Elapsed()`, `Race.SinceBuzzer()`, `Race.StopRequested()`;
  - the plain `race.lastDamage` stamp and `race.grace`;
  - the counted late-cast list (`run.flags.lateCasts`);
  - `RaceScoring.QUIET_BEFORE_READ` (2.5);
  - `Race.MIN_LENGTH`/`MAX_LENGTH` (10/900);
  - on the sample race: `Held()` and `InCombat()`.
- **Other mapping:**
  - `Recorder.Pending()` becomes B2's `db.global.pendingRaces[charKey]`.
  - `Recorder.SnapshotTarget`/`CurrentSpec`/`SnapshotPlayer` have no CT equivalents of those names. Use `NS.Identity.Snapshot().target` and `Identity.Who()` (CT `Identity.lua:279`, `:287`).
  - `Format.ParseLength`, `Format.ArmRefusal(reason, detail)`, `Format.Seconds` and `Format.RunTime` do not exist in CT `Format.lua`, so B1, B3 or C1 must add them. `Format.Clock` and `Format.Length` exist in both and are identical.
- **Owner:** C1, consuming B1, B2 and B3. **DR tests:** `test_hud.lua` (six-state switch, pre-buzzer waiting, arm refusal, custom length, unknown target, default length 1:00, ForgetLength, target-cache cases), `test_hud_hint.lua`.

### #9 Show and hide rules (DR `Hud.lua:928-1091`, `:1093-1110`)
- **DR:**
  - **Flags:** `Hud.wanted`, `autoShown` (the addon opened it), `dummyShown` (opened near a dummy), `closes` (count of player closes, AutoArm's manual-close rule).
  - **Openers and closers:** `Hud.ShowNearDummy() -> opened`, `Hud.HideAwayFromDummy() -> closed`, `Hud.ShownNearDummy()`, `Hud.Closes()`, `Hud.AutoShow()`, `Hud.Show()`, `Hud.Hide(own)` (`own` = the addon's own close, not counted), `Hud.Toggle()`.
  - **`onState`:** ARMED calls `autoShow()` and resets the live caches. IDLE to RUNNING/STOPPING (a resume) auto-shows. A return to IDLE closes an `autoShown`, non-dummy, non-preview window when `hud.showMode == "onArm"`.
  - `RACE_RESULT` auto-shows. `hud.showMode` "always" opens at Resume.
  - `IsShown = wanted and NS.MasterVisibilityAllows()`.
  - `Suspend` drops an `autoShown` window; `Resume` re-opens on "always".
- **CT:** CT has no `MasterVisibilityAllows`. The CT HUD uses `wanted and not isDown()` (CT `Hud.lua:757-760`). AutoArm (B3) calls these entry points.
- **Classification:** KEEP the whole show/hide contract under spec §4.1: auto-show near a dummy, the debounced hide, respect for a manual close, and `/ct race show|hide|toggle`. DR `hud.showMode` ("onArm"/"always") and `hud.autoShow` move under the plan's `race.*` or `raceWindow.*` keys. They must not use `hud.show`, which is the CT HUD's own key ("auto"/"always"/"toggle").
- **Review focus 4** is unchanged: the window stays where the HUD stands. See #24.
- **Owner:** C1 (API), B3 (AutoArm callers, `NS.RaceMode.On()` gate: off means `IsShown` false).
- **DR tests:** `test_hud_window.lua` (onArm and always cases, resume shows under onArm, a result opens a closed window, stand-down drops onArm's window), `test_autoarm.lua`, `test_disabled.lua`.

### #10 Acts and the result card's delete flow (DR `Hud.lua:1112-1295`)
- **DR `Hud.Act`:** `arm`, `pickLength(n)`, `openCustom`, `closeCustom`, `customLength(text)` (parses; refuses outside `MIN_LENGTH..MAX_LENGTH` with `ArmRefusal("bad_length")`), `cancel` (= `discard`; in preview `Preview.Stop()`), `stopNow`, `close`, `lock`, `settings`, `results`, `details`, `openBest(run)`, `newRace` (`backToIdle`: cancels RESULT, keeps the length, makes the window the player's), `delete`, `share`.
- **Delete flow:** `Act.delete` calls `Results.ConfirmDelete(run.id, markDeleting)`. `runsChanged` (`:1120-1137`) on `RUNS_CHANGED` then goes back to idle after the card's own delete, cancels on an outside delete, and redraws otherwise. In IDLE it also does `Bests.Invalidate()` and a refresh.
- **CT:** `Results.ConfirmDelete(id)` takes **no callback** (CT `Results.lua:874-878`, popup `COMBATTRAIL_DELETE_FIGHT`). `Results.ShowFight(id)` (CT `:720`) is DR's `ShowRun`. `Share.Prompt(record, owner)` (CT `Share.lua:281`). DR's `RUNS_CHANGED` is CT's `FIGHTS_CHANGED`.
- **Conflict:** DR's "own delete goes back to Arm Race, outside delete just dismisses" depends on the `markDeleting` callback, which CT lacks. C1 needs a seam on `Results.ConfirmDelete` (an optional `onAccept`; Results.lua is near the cap, so seams only) or must accept one behavior for both cases.
- **Labels:** the button DR calls "Details" is **"Open"** in spec §4.2 (*New Race / Open / Delete / Share*). Its act is `Results.ShowFight(record.id)`.
- **Owner:** C1. **DR tests:** `test_hud_layout.lua` (Delete asks first…, a card whose run is deleted in Results is dismissed, a cancelled popup…, New Race…, Share live or grayed, closing a card keeps the run), `test_late_ignore_ui.lua`.

### #11 Shared body widgets (DR `Hud_States.lua:34-479`) and their CT counterparts

| DR helper | DR lines | What it is | CT counterpart | Verdict |
|---|---|---|---|---|
| `C` palette | 37-45 | `dr.text/dim/caution/ahead/info`, `sem.statusBad`, GOLD | CT `Hud_States.lua:49-60` `ct.*` same roles, plus `best`, `pet` | Reuse `NS.HudStates.COLORS` (exported). |
| `BOX` | 50 | `{bg="list.boxDim", border="dr.box.border"}` | CT `:63` `ct.box.border` | Same. |
| `BUTTON_STYLES` normal/primary/danger | 55-63 | `NS.Skin.Button` token remaps | CT `Style.Button(parent, label, onClick, style)` `Style.lua:673`, `Style.SetEnabled` `:694` | Reuse `Style.Button`. |
| `SELECTED` preset look | 64-67 | `dr.sel.border`, `btnPrimary.text` | **missing**: CT `Style.lua:637-642` says "minus the selected-preset look"; no `ct.sel.border` token in CT `core/SkinSetup.lua` | C1 adds a `ct.sel.border` owner token plus a selected paint (a seam on `Style.Button`, or local). |
| `button(…, font)` | 270-292 | the font argument (Arm uses `FONT.TITLE`) | `Style.Button` has no font argument | C1 adds it, or sets the Arm label font after. |
| `bigText` mono | 167-197 | unstyled: `font.mono` face via `NS.Skin.Token`, re-fonted on `Style.OnLooks`; styled: from a font object, face by `A.ApplyFont` | CT clock is `Style.PlainText(f, FONT.FIGURE)` plus `A.ApplyFont(clock block)` (CT `Hud_States.lua:282`, `:300-321`) | Race clocks use the `hud.clock` block (#22). |
| `panel(kind)` | 201-207 | `NS.Skin.Card`/`Inset`/`Panel` | CT `States.Card(parent, tokens)` `:101-106` (Card only) | Card covers the KPIs, target card and best card. The callout box (hint) needs `NS.Skin.Panel` with `ct.callout.*` (tokens exist in CT). |
| `States.AddTip`/`TipZone` | 243-264 | a hover on any frame with a `{title, lines…}` table | CT `HudTips.Attach(frame, key)` `Hud_Tips.lua:33`, looks the key up in `NS.HudTips` only | Merge the race tips into `NS.HudTips` as new keys, or give `Attach` a table form. Zones over labels: a plain `CreateFrame` + `Attach`, as CT does for `clockZone` (`:283-285`). |
| `kpi`/`kpiPair` (captioned) | 309-350 | a Card with caption, figure (`FONT.FIGURE`) and an optional caption row (`KPI_HEIGHT 46`, `KPI_CAPTION_H 14`, `KPI_CAPTIONED_HEIGHT 60`, `KPI_PAD 5`) | CT `kpi` local `:120-136` (a pet row in the same 14 px slot), `placePair` `:151`; both **not exported** | Export them from CT Hud_States (643 lines, room) or rebuild with `States.Card` + `A.ApplyBox` + `A.ApplyFont(figures)`. |
| `chips` | 370-446 | `CHIP_HEIGHT 18`, `CHIP_GAP 5`, wraps at width; items `{text, color, tip, tipLines, menu}`; right-click calls `menu(chip)` | CT `Chips` local `:183-224`: `{text, color, tip}` only, no `tipLines`/`menu`, `Set(list, y)`, `Height()` | Race needs `tipLines` and `menu` (the late-cast right-click). Extend and export CT's, or own copy. |
| `targetCard` | 450-479 | Card 46 high: name (`FONT.HEADING`), category badge (`dr.callout.badge`/`borderStrong`, amber), `#npcID` caption | none in CT (the CT HUD has a one-line `target` label) | KEEP. Tokens `ct.callout.badge` and `ct.callout.borderStrong` are **missing** in CT SkinSetup. |
| `RowWidths`/`layoutRow`/`footerButtons` | 496-525 | equal buttons, `ROW_GAP 4`, `LINK_HEIGHT 20`, default width 236 | none | KEEP. |
| `caption`, `text` (wrapping) | 158, 353 | `FONT.HEADER` gold caption; wrapping `Style.Text` | `Style.Text` `Style.lua:322` | KEEP. |

- Dummy labels: `NS.Dummies.Label(NS.Dummies.CategoryOf(target))` takes a **target table** and returns `"other"` for unknown targets (`targetCard` `:475`, `targetWarning`, toast). Plan A2's `Dummies.CategoryOf(creatureID) -> …|nil` has no `"other"` and no `Label`. **Flag for A2/C1:** add `Dummies.Label(category)` and an "other" path.
- **Owner:** C1. **DR tests:** `test_hud_tiles.lua`, `test_hud_element_tips.lua`, `test_hud_tips.lua`, `test_bar_style.lua`, `test_skin_hud.lua`, `test_glyphs.lua`.

### #12 Body 1: idle (DR `Hud_States.lua:581-670`; layout constants `:105-124`)
- **Layout constants:** `PRESET_TOP 14`, `PRESET_H 20`, `PRESET_GAP 6`, `BLOCK_GAP 8`, `ARM_GAP 14`. Derived: `IDLE_TARGET_Y 68`, `IDLE_CARD_Y 82`, `IDLE_WARN_Y 132`, `IDLE_BEST_Y_PLAIN 136`, `IDLE_BEST_Y_WARNED 160`, `IDLE_ARM_Y_PLAIN 202`, `IDLE_ARM_Y 220` (warned cap), `ARM_HEIGHT 24`, `REASON_HEIGHT 14`. Presets: a 3-column grid, `cell = floor((width-12)/3)`.

| Widget | DR field | Class | Note |
|---|---|---|---|
| "Race Length" caption + tip zone | `w.lengthCap`, `lengthTip` | KEEP | |
| 5 preset buttons `{30,60,120,180,300}` | `w.presets` (`States.PRESETS` `:142`) | KEEP | Matches plan `Race.LENGTHS`. Selected look per #11. |
| Custom button | `w.custom` | KEEP | Shows `Format.Length(v.length)` when not a preset. |
| Custom EditBox | `w.customBox` | KEEP | `NS.Skin.EditBox(…, {padInput=false})`, centered, `SetMaxLetters(6)`; Enter calls `customLength`, Escape calls `closeCustom`. |
| "Target" caption + target card | `w.targetCap`, `w.card` | KEEP | Spec §4.1 "the target line". |
| Amber warning line | `w.warn` | KEEP | Moves the best card and Arm down (`warned`). |
| Your best section | `w.best` (#18) | KEEP | |
| Arm Race (primary, `FONT.TITLE`, 24 high) | `w.arm` | KEEP | Disabled while `v.blocker`. |
| Refusal line | `w.reason` | KEEP | `Format.ArmRefusal`, missing in CT. |
| Results button across the foot | `w.results` | DROP | Not in spec §4.1's list; the HUD's chart control covers it. Removing it frees `LINK_HEIGHT + 4`. |

- **DR tests:** `test_hud.lua` (idle cases), `test_hud_best.lua` ("every launcher block sits the same gap apart…"), `test_hud_element_tips.lua` ("the idle body names every length, the target, Arm and Results").

### #13 Body 2: armed (DR `Hud_States.lua:673-698`)

| Widget | DR field | Class | Note |
|---|---|---|---|
| Big length clock (mono, `BIG=40`) | `w.clock` + `clockTip` | KEEP | `Format.Clock(run.race.length)`. |
| "First hit starts the clock" caption | `w.sub` + `subTip` | KEEP | y -52. |
| Target card | `w.card` at -74 | KEEP | `run.target` becomes the CT fight's target or snapshot. |
| Pre-cast note (dim, wraps) | `w.note` at -128 | KEEP | |
| Cancel (wide, foot) | `w.cancel` | KEEP | |

- **DR tests:** `test_hud_element_tips.lua` ("the armed body names its clock, target and Cancel").

### #14 Body 3: running (DR `Hud_States.lua:951-1048`; clocks `:720-805`)
- **Clock logic:** `setClocks` (`:724`) uses `hud.clock` "both" (default), "left" or "elapsed". "both" is a pair of `CLOCK_PAIR=26` (elapsed green left, time-left red right, captions "Elapsed"/"Left"). A single clock draws at `SINGLE_SCALE = 40/26`.
- **KPI top:** `kpiTop` = `26 + max(sizes)` (pair) or `12 + round(size*40/26)` (single), which gives 52 at the defaults (`:751-762`).
- **Fonts:** `styleRunning` applies the `elapsed`/`left`/`figures` blocks (`:787-805`).

| Widget | DR field | Class | Note |
|---|---|---|---|
| Single clock / elapsed + left pair + captions + tip zones | `w.clock`, `w.elapsed`, `w.left`, `w.elapsedCap`, `w.leftCap`, `clockTip`, `elapsedTip`, `leftTip` | KEEP | Spec §4.2 "elapsed and/or time left per the clock setting". See #22 for fonts; the clock-mode setting **cannot** be `hud.clock` (#22). |
| Damage KPI, "DPS · Live" KPI | `w.damage`, `w.dps` (`kpiPair` at -52) | ALREADY | The CT HUD's live boxes. `live.showDps` DROP. |
| Pace bar | `w.pace` (`HudChart.NewPace`) | KEEP | Spec §4.2. See #20 for the API differences. |
| "Damage profile" heading + note | `w.chart.title/note` | KEEP (heading only) | With no plot the note reads `L["vs best pace"]` (`placeStack` `:842`). |
| Damage chart plot, cooldown icons | `w.chart` (`HudChart.New`) | ALREADY | The CT HUD chart. Spec §4.2 "No duplicated widgets". |
| "Spell breakdown" heading, rows, wheel, "Live order · % after the race", count | `w.spellsTitle`, `w.rows`, `w.list` (`HudBreakdown.New`), `w.order`, `w.count` | ALREADY | The CT HUD rows. |
| Cancel (wide, foot) | `w.cancel` | KEEP | |
| Chips | none in DR's running body | NEW? | Spec §4.2 lists "chips" for running. DR draws none; it can only mean live flags such as `sharedSession`/`sessionFromList`. **Builder's call**, flag to owner if unclear. |

- **DR tests:** `test_hud.lua` ("running render raises nothing with secret values", "running body shows no percentage text", the two clock-mode cases, "the clock pair fits the minimum width"), `test_hud_element_tips.lua` (running body), `test_pace.lua` ("the running body stacks Damage profile, the pace bar…": adapt).
- **Drop with the rows and chart:** `test_hud_layout.lua` live-row cases, `test_chart.lua`, `test_chart_icons.lua`, `test_hud_icon_edge.lua` (CT owns these in `test_hud_chart.lua`, `test_hud_breakdown.lua`).

### #15 Body 4: Stop! (DR `Hud_States.lua:1100-1141`; figures `:1054-1071`; buttons `:1076-1084`)
- **Positions:** `STOP_KPI_Y 56`, `STOP_CHIPS_Y 124`, `STOP_NOTE_Y 152`.

| Widget | DR field | Class | Note |
|---|---|---|---|
| "STOP" big (mono, 48, red) + tip | `w.big` | KEEP | |
| Captioned pair: "Damage Stopped"/"Combat Ended" and "In Combat"/"Out of Combat" | `w.tail`, `w.combat` | KEEP | Plain `GetTime()` figures: `Format.Seconds(tail).."s"`/`Format.Length(endedAt)`, captions "after buzzer"/"into the race", "since the buzzer"/"combat ended". |
| Chips: "N late cast(s) · +x.xs" (amber), "Grace x.xs" (info) | `w.chips` | KEEP | Counted through `LateIgnore.Set()`/`IsIgnored` (`countedLate` `:1088`). Rebuilt only when `"%d|%.1f|%.1f"` changes. |
| Note (dim) | `w.note` | KEEP | |
| Stop Now (primary) + Cancel (danger), equal widths | `w.stopNow`, `w.cancel` | KEEP | Stop Now disabled once requested. |

- **DR tests:** `test_hud.lua` (stop body, ignore-list count), `test_hud_tiles.lua` (all 10), `test_hud_layout.lua` (Stop Now and Cancel cases).

### #16 Body 5: waiting (DR `Hud_States.lua:1181-1226`; hint sizing `:1148-1178`)
- **Positions and hint metrics:** `WAITING_KPI_Y 40`, `WAITING_HINT_Y 108`, `HINT_PADX 8`, `HINT_PADY 6`, `HINT_ADVANCE 5.4`, `HINT_LINE_H 12`. `States.HintLines(s, width)` and `States.HintHeight(s, width)` estimate the size and never measure it.

| Widget | DR field | Class | Note |
|---|---|---|---|
| Title: "Waiting for combat to end" / "Reading the result" / "Reading when combat ends" + `pending` tip | `w.title` | KEEP | Carries the old footer's "result pending" (#4). |
| Captioned tail and combat pair | `w.tail`, `w.combat` | KEEP | Same as Stop!. |
| Hint callout box (`dr.callout.bg/border/text`) | `w.hint`, `w.hintText` | KEEP | `ct.callout.*` exist in CT SkinSetup. |
| Stop Now + Cancel | as Stop! | KEEP | |

- **DR tests:** `test_hud_hint.lua` (6), `test_hud_tiles.lua` ("the waiting screen's tiles…"), `test_hud.lua` ("waiting hint appears after hintDelay…", "asks for the player's spells once per race").

### #17 Body 6: result card (DR `Hud_States.lua:1331-1445`; chips `:1228-1318`)
- **Chips** (`States.ResultChips(v)`), in order:
  1. The verdict (`verdictChip`): "New best +x.x%" or "New best" (green), "+x.x% vs best" (red, or dim on a tie).
  2. "N ignored" (dim; it keeps the menu and tip lines).
  3. The flags (amber, from `States.FlagChips(run)` over `Scoring.Flags(run, SpellName)`; `FLAG_CHIP` keys `lateCasts`, `restarted`, `reloaded`, `sessionFromList`, `sharedSession`, `incomplete`, `lost`, `died`).
  4. "Time %s" (`Format.RunTime`).
- **Exports:** `States.FlagChips` and `States.FLAG_COLOR` are also read by BestToast (#27).

| Widget | DR field | Class | Note |
|---|---|---|---|
| Damage / DPS KPI pair (DPS green) | `w.damage`, `w.dps` | KEEP | Spec: the race's figures, **score** = `race.score` and DPS = `race.dps` (spec §6). Label "Score" is a builder's call. Dashes for a lost race. |
| Chips strip | `w.chips` | KEEP | Late-cast right-click via `LateIgnore.Offers/Menu` (none in preview). |
| "Couldn't read the result" | `w.lost` | KEEP | Spec §3: a lost race is not saved, so this shows only until it is dismissed. |
| Pace bar (plain final vs best-before) | `w.pace` + `resultExtras` | KEEP | Spec §4.2. |
| Chart, spell rows, wheel, count, "Spell breakdown" heading | `w.chart`, `w.rows`, `w.list`, `w.count`, `w.spellsTitle` | DROP | *Open* opens the detail, which has them (spec §4.2). |
| New Race (primary) / Details / Share / Delete (danger) | `w.newRace`, `w.details`, `w.share`, `w.delete` | KEEP | Rename Details to **Open**. Share disabled for samples. |

- **Wording:** "Remove this run from history…" and the other "run" strings must become "race" or "fight" (plan's words rule).
- **DR tests:** `test_hud_layout.lua` (result card cases: % and delta chip, first and slower, late-cast right-click, lost, incomplete chip, New Race, Share, close), `test_hud_element_tips.lua` (verdict chip words, result card names), `test_results_badges.lua` (flag words shared), `test_late_ignore_ui.lua`, `test_pace.lua` (result card cases).

### #18 Your best card (DR `Hud_Best.lua:38-200`)
- **DR:**
  - `Best.View(target, length)` returns `{state="noTarget"|"empty"|"best", run, spec, category, length}`. The board comes from `Bests.Key({char={specID}, target, race={length}})` and `Bests.Board()[key]`.
  - `Best.Build(parent, y)`: a `FONT.HEADER` caption "Your best" and a Card `BEST_CARD_H=38` holding the DPS (`Style.PlainText FONT.FIGURE`, styled by `A.Font("figures")` × `FIGURE_SCALE 0.8`), damage (dim, right), and a line "date · ilvl · consumable icons" (`ResultsTable.Date(date,"%d %b")`, `Ilvl`, `ResultsUsage.Entries/Icon/InlineIcon/Name`, icon markup `|T…:12:12:0:0:64:64:5:59:5:59|t`).
  - Empty texts: "Target a dummy to see your best." / "No race yet: this one sets the mark."
  - The hover lists the board, date, length, damage, DPS, consumables and "Click to open this run in Results.". A click calls `Act.openBest(run)`.
  - `Best.Place(b, parent, y)`, `Best.Update(b, v)`.
- **CT:** CT's `ResultsTable.Date` and `Ilvl` and `ResultsUsage.Entries/Icon/InlineIcon/Name` all exist.
- **Field mapping:** `run.char` → `record.who`; `run.result.dps/damage` → `race.dps`/`race.score`; `run.race.length` → `race.length`.
- **Board:** plan A3's `Bests.RaceKey(record)` over character + spec + kind + length. The probe needs `who` (from `Identity.Who()`) and `race = {kind, length}`. A board change redraws on `FIGHTS_CHANGED` and `PLAYER_SPECIALIZATION_CHANGED`.
- **Classification:** KEEP, as `modules/RaceWindow_Best.lua` (plan C1). Never `NS.HudBest`.
- **Owner:** C1, consuming A3. **DR tests:** `test_hud_best.lua` (9).

### #19 Tooltip words (DR `Hud_Tips.lua:12-60`)
- **DR keys, each `{title, line}` or a string:**
  - idle: `lengthCap`, `preset`, `custom`, `customBox`, `target`, `arm`, `results`;
  - armed: `armedClock`, `armedSub`, `cancel`;
  - running: `clock`, `elapsed`, `left`, `liveDamage`, `liveDps`, `profile`, `pace`, `resultPace`, `liveSpells`, `resultSpells`, `order`, `count`;
  - stop and waiting: `stop`, `damageStopped`, `combatEnded`, `inCombat`, `outOfCombat`, `pending`, `lateChip`, `graceChip`;
  - result: `resultDamage`, `resultDps`, `newBestChip`, `firstBestChip`, `behindChip`, `tiedChip`, `newRace`, `details`, `share`;
  - title bar and footer: `close`, `footLeft`, `footRight`.
- **CT:** `NS.HudTips` holds `clock`, `target`, `liveDamage`, `liveDps`, `overDamage`, `overDps`, `pace`, `overPace`, `chart`, `liveSpells`, `overSpells` and `Attach` (CT `Hud_Tips.lua:13-48`). The keys `clock`, `target`, `pace`, `liveDamage` and `liveDps` **collide** with different words, so the race keys need a prefix (for example `race.clock`).
- **Classification:** KEEP the tips of every KEEP widget. DROP `liveDamage`, `liveDps`, `profile`, `liveSpells`, `resultSpells`, `order`, `count`, `results`, `footLeft`/`footRight`.
- **Rewording needed:** every "run", plus "HUD > Race clock" and "HUD > Race HUD > Spell rows shown" (wrong menu paths in CT), and "Race settings page" (should be "Race mode page").
- **Owner:** C1. **DR tests:** `test_hud_element_tips.lua`, `test_hud_tips.lua`, `test_tooltips.lua`.

### #20 Pace bar (DR `Hud_Chart.lua:80-100`, `:157-236`, `:338-423`, `:790-913`)
- **DR:**
  - `Chart.PACE_H 12`. The bar is 8 px tall, 2 px under the line. `PACE_A 0.85`.
  - `Chart.Pace(best, elapsed) = best.result.damage * clamp(elapsed,0,length)/best.race.length`, i.e. linear over the **race length**.
  - `Chart.PaceRange()` reads `live.paceRange` (default 1.5), clamped 1.1..2.0.
  - `Chart.PaceBounds(best, elapsed, range)`: `lo = pace*(2-m)`, `hi = max(pace*m, lo+1)`.
  - `Chart.TickX(barW) = floor(barW/2+0.5)`.
  - `NewPace(parent)` / `:Place(anchor, y, width)` / `:SetRange(lo, hi)` / `:SetValue(total)`. The look comes from the `appearance.pace` block (`A.Pace()`, `A.PaintTrack`, `A.PaintEdge`). Ahead is `dr.ahead`, behind is `sem.statusBad`, the tick is `dr.pace.tick`.
  - `Chart.LiveViews(run, …)` returns no pace for `sharedSession` or with no best.
  - `Chart.ResultPace(run, showPace)` gives `{lo, hi, value=run.result.damage}` against `Bests.Before(run)` at the run's length. None when lost, shared or with no earlier best.
- **CT:**
  - `HudChart.NewPace(parent)` (CT `Hud_Chart.lua:573`), `Pace:Place(anchor, y, width) -> PACE_H` (`:601`), **`Pace:Set(lo, hi, total)`** (`:627`, one call; no SetRange/SetValue).
  - The look is the **spell rows' bar block** (`A.Bar("spells")`) plus `ct.ahead`/`ct.pace.behind`/`ct.pace.track`/`ct.pace.tick`. There is no `pace` appearance block.
  - `NewPace` attaches the tip key `"pace"` itself.
  - Bounds: `HudBest.Bounds(pace, range)` (CT `Hud_Best.lua:143`), range `hud.paceRange` 1.5, clamped 1.1..2.0 (`Best.Range` `:132`).
  - Live view: `HudBest.LiveView(curve, t, live)` / `OverView(curve, final, clock)` (`:170`/`:186`).
- **What differs:** spec §4.4 says one pace model, CT's. The Race window's bar therefore uses CT's `NewPace`/`Set` and `HudBest.Bounds`. DR's per-race formula (score over `race.length`) differs from CT's curve (`record.damage.merged / record.duration`, `Best.Curve` `:118-128`).
- **Classification:** KEEP the widget (CT's), DROP DR's `Hud_Chart` copy.
- **Owner:** C1 (window bar), C3 (HUD bar). **DR tests:** `test_pace.lua` (14: the range/tick/split cases port to CT's `test_hud_pace.lua` or are already there; the Before and result-card cases go to C1).

### #21 CT construction helpers the Race window must reuse to look identical

| Part | CT source | Use |
|---|---|---|
| Skin shell | `NS.ApplySkin(f)` (`core/CoreSetup.lua:94`), `A.ApplyWindow(f)` (`Hud_Appearance.lua:302`) | Background, border, strata `hud.window.strata`, alpha `hud.window.alpha`. |
| Title band | `Style.Header(f, spec)` `Style.lua:551`, `Style.Band(f)` `:540`, `Style.TITLE_BAR_H` (skin `title.height` or 30) | Same title-left layout. |
| Controls | `Style.ControlButton` `:597`, `Style.SetControlIcon` `:619`, `Style.NewStrip`/`AddToStrip` `:413`/`:427`, `NS.MakeCloseButton` | Close, lock, settings, attach/detach. |
| Footer | the `buildFooter` pattern CT `Hud.lua:434-446` (`NS.Skin.Divider`, `FONT.CAPTION`) | Optional (#4). |
| Insets | `PAD 12`, `HEADER_H+10`, `FOOTER_H+8`, `hud.window.titleBar`/`footer` (CT `Hud.lua:93`, `:295-297`) | Same content rect. |
| Boxes | `NS.HudStates.Card` (`Hud_States.lua:101`), `A.ApplyBox(f)` (`hud.figures.boxBg/boxBorder`) | KPIs, target card, best card. |
| Figures | `A.Font("figures")` + `A.ApplyFont(fs, font, color)` | KPI figures, best DPS (×0.8). |
| Clock face | `A.Font("clock")` + `States.ClockSize(size)` (×40/26) | Race clocks (#22). |
| Buttons | `Style.Button`/`Style.SetEnabled` (`Style.lua:673`/`:694`) | Every body button; add the selected style (#11). |
| Chips | `Style.FlatBox`, `Style.TintBox(chip, c, Style.CHIP_EDGE_A)`, `Style.Paint` | Same as CT's over card. |
| Pace bar | `NS.HudChart.NewPace`, `HudBest.Bounds` | #20. |
| Section heading | `FONT.SECTION` on `Style.SECTION_H` (22) with `HEAD_GAP = SECTION_GAP(14) - GAP(8)` (CT `Hud_States.lua:74-75`) | "Damage profile"-style heading over the pace bar. |
| Restyle stamp | `NS.HudAppearance.stamp`; `Style.OnLooks` | **Conflict:** `Appearance.Changed()` (`:311-314`) calls only `NS.Hud.Refresh()`. The Race window must compare the stamp on its own draw **and** be refreshed on a change (a seam: `Changed` also calls `NS.RaceWindow.Refresh`, or the window hooks `Style.OnLooks` and `SETTINGS_CHANGED` `hud.*`). |
| Skin-surface test | `tests/skin_surfaces.lua` (HUD rows at `:118-122`) | Register the Race window's surfaces (plan C1). |

### #22 HUD Appearance blocks: DR vs CT
- **DR blocks** (`defaults/Profile.lua:163-215`): `appearance.elapsed` (JetBrains Mono 26, green 0.36/0.86/0.46), `appearance.left` (26, red 1.0/0.32/0.32), `appearance.figures` (Ka0s Prototype 20), `bars`, `spellText`, `chart`, `pace`. The rows are under HUD > HUD Appearance.
- **CT blocks** (`defaults/Profile.lua:149-187`): `hud.clock` (JetBrains Mono 26, neutral 0.92/0.91/0.88), `hud.figures` (Ka0s Prototype 20, `overColor`, `boxBg`, `boxBorder`), `hud.chart`, `hud.spells`, `hud.window`. No elapsed/left split and no pace block.
- **Conflicts:**
  - **`hud.clock` is a CT font block.** DR's `hud.clock` is the clock *mode* ("both"/"left"/"elapsed", default "both"). The race clock mode must live elsewhere; plan B3 puts it in the Race section, for example `race.clock`.
  - The Race window's clocks draw in the `hud.clock` font block. Spec §8 forbids a styling tree of the Race window's own. The elapsed/left meaning colors come from `C.green`/`C.red` passed as `A.ApplyFont(fs, font, color)`'s override. The single clock is red (time left) or green (elapsed).
  - DR `live.paceBar` maps to CT `hud.layout.pace`; DR `live.paceRange` maps to CT `hud.paceRange`.
  - DROP `live.icons`, `live.showDps`, `live.hz`, `live.chart`, `live.castDots`.
- **Owner:** C1 (use), B3 (the clock-mode key). **DR tests:** `test_hud_window.lua` ("the running clocks, figures and spell rows take their HUD Appearance blocks", "…every skin's HUD face…", "a clock shown alone draws half again as large…"), `test_skin_fonts.lua`.

### #23 CT `Hud.lua` PaceRecord seam (plan C3)
- **CT now:**
  - `Hud.PaceRecord(fight, ident)` (CT `Hud.lua:201-215`): `against = hud.paceAgainst` ("best" | "last" | "none"). The probe is `{ who = fight.snapshot.who, boardKey = Identity.BoardKey(ident), identity = ident, status = "final" }`.
  - It returns `NS.Bests.For(probe)`, or `lastOnBoard(probe, Recorder.List())` (`:186-196`, matching on `Bests.Key`). Samples go to `ResultsSource`.
  - It is read **once** in `newView` (`:226-232`) from `goLive` (`:907-921`), which also builds `curve = NS.HudBest.Curve(pace.id, pace)`.
  - `judge(record)` (`:235-247`) for the over card's New best uses `Bests.IsBest` and `Bests.For(record, true)`.
- **C3 change:** while `fight.race` exists, the probe carries `race = {kind, length}` and the board is `Bests.RaceKey` through `Bests.For` (A3). The "last" mode must also match on the race key.
- **Hazards for C3:**
  1. **Ordering.** `goLive` runs on the first `FIGHT_TICK` with `firstHitT` set (`:923-941`; `firstHitT` set in CT `Fight.lua:407-410`). The bus keeps no order between receivers, and B1 creates `fight.race` "on FIGHT_STARTED … the clock from that first hit". If the race part appears on the same tick, the HUD may already have paced on the dummy's fight board. Re-run `newView`/PaceRecord on `RACE_STARTED`, or have B1 guarantee `fight.race` exists before the first `FIGHT_TICK` that carries `firstHitT`.
  2. **The curve's measure.** `HudBest.Curve` paces `damage.merged / duration`. A race best's fight `duration` includes the tail after the buzzer, and `damage.merged` includes the tail damage. DR and spec §6 pace on `race.score / race.length`. C3 should build the race curve from `race.score` and `race.length` (for example by passing a `held` table to `Best.Curve`, or a `RaceRecord` helper). Otherwise the HUD and the Race window disagree on "on pace".
  3. **`sharedSession`.** DR hides the pace bar and chart on a shared session (`Hud_Chart.lua:157-159`, `:391`, `:414`), because the live total includes pre-arm damage. CT `LiveView` would pace the un-netted total. Hide or flag it.
  4. **The over card.** The HUD's over card "New best" (`judge`) then also answers the race board, because A3 makes `IsBest`/`For` race-aware. That is consistent with spec §5 ("a race counts only on its race board").
- **Test:** CT `tests/test_hud_pace.lua` exists. Extend it per plan C3 and add a case for the ordering hazard. **DR tests:** none (DR had a single board).

### #24 Docking seam and attach/detach (plan C1, Review focus 4)
- **CT:** `Hud.Frame()` already exists (CT `Hud.lua:1067`), so no new seam is needed for the getter. It returns **nil until the HUD is first shown** (`ensureWindow` runs only from `Refresh` when `IsShown`, `:771-786`). The frame's size is set only in `render()` (`:709-725`), so a built HUD that never rendered is 0×0.
- **Gap for Review focus 4** ("attached with the HUD hidden it stands where the HUD would"): the Race window cannot anchor to a nil frame. C1 needs one of:
  - a Hud seam that builds and places the HUD frame hidden (ensureWindow + applyPlacement + SetSize(`width()`, `Hud.FixedHeight()`)) without showing it; or
  - a computed anchor from `hud.position`, `hud.width`, `Hud.FixedHeight()` and `hud.scale`.
- A hidden built frame keeps its last points and size, so anchoring to it is valid in WoW. A frame that was never rendered is the edge case.
- The HUD fades (`hud.fadeAfter` 8 s) and `Hud.Hide` hides it. The attached window must not hide with it (spec §4.3: each window follows its own rules), so do not parent it to the HUD frame. Anchor it only.
- Grow "up" re-anchors the HUD's BOTTOMLEFT (`normalizeAnchor`, `:387-400`). Attach TOP/BOTTOM by side to the frame, not to the stored point.
- DR's stepper docking precedent is DR `Hud.lua:1304-1305` ("the stepper docks beside it, SF-DR-8").
- **Tests:** plan C1's four attach cases. DR has no equivalent.

### #25 The buzzer's raid warning (DR `Hud.lua:83`, `:188-201`, `:1150`)
- **DR:** on `RACE_BUZZER`, whether or not the window is shown, when `race.buzzer ~= false`:
  - `PlaySound(SOUNDKIT.RAID_WARNING or 8959, "Master")` (pcall);
  - `RaidNotice_AddMessage(RaidWarningFrame, L["STOP"], ChatTypeInfo.RAID_WARNING)` (pcall, guarded on type).
- **CT seam:** none yet. Plan C2 owns "buzzer warning". It belongs in C2's Countdown module or the Race window, registered on a bus target so the stand-down drops it.
- **Owner:** C2, consuming B1's `RACE_BUZZER (race)`. **DR tests:** `test_hud.lua` ("countdown cue plays at 10,5,3,2,1 and buzzer raises the raid warning only when enabled").

### #26 Countdown (DR `Countdown.lua`)
- **DR constants:** `CUES = {10,5,3,2,1}`; `MIN, MAX = 3, 10`; `TEXTURE = "Interface\\Timer\\BigTimerNumbers"`; `GLOW = "…BigTimerNumbersGlow"`; `OFFSET_Y = 150`; `FONT_SIZE = 110`; `GOLD {1,0.82,0}`; digits 256×170 on a 1024×512 sheet with `HALF_WIDTHS`; `SOUND_CUE = 25477` (`SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_TIMER`); `EPS 1e-6`.
- **DR settings:** `race.centerCountdown` (true), `race.countdownCue` (true), `race.finalCountdown` (10, clamped 3-10).
- **DR behavior:**
  - **On entering RUNNING:** `schedule()` (`:292-308`) arms one `C_Timer.NewTimer(left - m)` per mark m=10..1 still ahead (`left` from `Race.TimeLeft()`), and shows the current number silently (resume).
  - **Each mark** (`mark`, `:275-281`): plays the cue once when `cueOn` and (m is a cue mark or numbers are on), then `display(m)`.
  - **Leaving RUNNING:** `stopRace` cancels every timer and hides the number.
  - **Frame:** its own, on UIParent, `LAYERS.STRATA.SCREEN_ALERT` ("FULLSCREEN"), mouse-disabled, built at the first number. Pop animation: scale 0.25 to 1 over 0.3 s plus alpha 0 to 1 over 0.15 s; glow flash 1 to 0 over 0.3 s. A font fallback (`THICKOUTLINE`) is used when the texture fails.
  - **Public:** `Countdown.Shown()`, `Refresh()` (the settings rows' reaction), `Suspend()`, `Resume()`, `Diagnose() -> {shown, scheduled, owner}`, `__ui()`.
  - The sim's race is read through `NS.SampleRace` when it is running and not `Held()`.
- **CT seam:** a new `modules/Countdown.lua` (C2). Needs `LAYERS.STRATA.SCREEN_ALERT = "FULLSCREEN"` added to CT `core/Constants.lua:58`, which today has `{ LANE, CHROME, HUD, WINDOW, MODAL }` only. Add `"Countdown"` to CT `core/LifecycleSetup.lua:14-16` `MODULES` and a Resume call at stand-up (`core/CombatTrail.lua:~68`).
- **Conflict, bus input:** DR drives everything from `RACE_STATE_CHANGED (run, from, to)` (sent at DR `Race.lua:68`). Plan B1 declares `RACE_ARMED`, `RACE_STARTED`, `RACE_BUZZER`, `RACE_RESULT` and `RACE_CANCELLED`, with **no state-change message**. Map them as:
  - `RACE_STARTED` → `schedule()`;
  - `RACE_BUZZER`, `RACE_CANCELLED`, `RACE_RESULT` → `stopRace()`;
  - B2's `Race.Resume()` must call `Countdown.Resume()`, or send `RACE_STARTED` on a resume.
  - "Combat ended before the buzzer" also leaves RUNNING; B1 must signal it (RACE_RESULT incomplete or a state message).
  - **Recommendation:** B1 also sends `RACE_STATE_CHANGED (race, from, to)`, which the Race window (#9 `onState`) and Countdown both port unchanged.
- **Owner:** C2 (+ B1 for the message). **DR tests:** `test_countdown.lua` (20), `test_disabled.lua` ("Disabled 5 (countdown)"), `test_layers.lua` ("the countdown is FULLSCREEN, below every menu").

### #27 New-best toast (DR `BestToast.lua`)
- **DR shell:** `NS.NewToast({ name = "DpsRaceBestToast", build, width, height, duration = toast.duration, scale = toast.scale, sound = toast.sound, soundFile = BestToast.SoundFile, draggable, getPosition, setPosition, debug })` (`:319-332`). It lives in DR `core/ToastSetup.lua` (the LibKa0s-Toast-1.0 seam, `NS.TOAST_PREVIEW`, `NS.ToastStub`).
- **DR geometry:** `SCALE 1.25`, `PAD 13`, `GAP 10`, `ROW_GAP 6`, `TITLE_H 17`, `CHIP_H 20`, `TEXT_H 15`, `CLASS_ICON 16`, `CONTENT_W 355`, `CLOSE_ROOM 32`, `ROWS_H 64`, `WIDTH 445`, `HEIGHT 90`, `FLAGS_HEIGHT 21`.
- **DR content:**
  - Trophy `NS.Icon("ph:trophy")` (declared in CT), tinted `ResultsTable.COLORS.blue`.
  - "New best:" plus class and spec icons plus "Spec Class" in the class color.
  - Two chips: the target category and the length (`Tbl.Badge`, `Tbl.LengthChip`, `Tbl.Chip`, `Tbl.SetChip`, `Tbl.CHIP_GAP`).
  - A detail line "%s DPS, %s better than previous best (%s)".
  - A flags line from `HudStates.FlagChips`.
- **DR trigger** (`OnResult`, `:339-346`): `RACE_RESULT`, `toast.enabled`, `run.status == "complete"`, `pct, isNew, prev = Bests.Delta(run)`, and `isNew and pct ~= nil`, so a board's first race does not toast.
- **DR settings:** `toast = { enabled = true, duration = 10, sound = true, soundKey = "Default", scale = 1.0 }`, plus `point`, written by a drag. The toast drags only for a preview or sample.
- **DR extras:** `SoundValues()` (Default first, then sorted LSM sounds), `ShowPreview(sample)`, `EndPreview()`, `Test()` (needs `MockRuns.Player`/`LENGTH`/`DPS`), `Sync()`, `Refresh()`, `ResetPosition()`, `Suspend()`, `Instance()`, `Diagnose()`. A profile change (`SETTINGS_CHANGED "profile"`) re-syncs.
- **CT seams and gaps:**
  - CT vendors `libs/LibKa0s/Toast.lua` (loaded in `LibKa0s.xml:12`) but has **no `core/ToastSetup.lua`**. C2 adds the seam, honoring library-stack-§7 (one file leases the major; `test_surface_parity` holds the stub).
  - CT `ResultsTable` lacks `Badge`, `LengthChip`, `Chip`, `SetChip` and `CHIP_GAP`. It has `SpecInfo`, `ClassName`, `ClassColor`, `Hex`, `SetClassIcon`, `COLORS` and `ContentChip` (`Results_Table.lua:163`), so the chip helpers must come with C2 or D1.
  - **`Bests.Before`/`Bests.Delta` do not exist in CT** (`modules/Bests.lua` has `Key`, `Compute`, `Board`, `Invalidate`, `For`, `IsBest`, `BestCurve`, `HoldingIDs`). Plan C2 consumes them, but A3's interface list does not produce them. Add them to A3, or have C2 use CT's `judge` pattern (`IsBest(record)` + `For(record, true)`, CT `Hud.lua:235-247`). That is equivalent at result time: every other record is earlier.
  - Toast settings: plan B3 sets `toast = { races = true, fights = true, … }`, which replaces DR's single `enabled`.
  - The fights toast (spec §8): on `FIGHT_SAVED`, `IsBest`, and a previous best exists. It must **skip records with a `race` part**, because the race toasts on `RACE_RESULT`, so the same pull would toast twice. Fights' toast on both clients; races' Retail only.
  - Payload for a fight: content and duration chips instead of category and length.
  - Wording: "Click to open this run" and similar must use race or fight.
  - Rename the frame to `"CombatTrailBestToast"` and the stash `frame.dpsRace`.
  - Add `"BestToast"` to Lifecycle `MODULES`.
- **Owner:** C2 (+ A3 for Before/Delta). **DR tests:** `test_toast.lua` (27), `test_surface_parity.lua` (toast stub), `test_skin_menus.lua` (sound picker).

### #28 Bus inputs summary (C1, C2)

| DR message (payload) | DR consumer | CT plan equivalent | Gap |
|---|---|---|---|
| `RACE_STATE_CHANGED (run, from, to)` | Hud `onState`, Countdown | none | Add it to B1, or map from the started/buzzer/result/cancelled messages (#26). |
| `RACE_BUZZER (run)` | Hud `buzzer()` | `RACE_BUZZER (race)` | Payload is the race part, not a run. |
| `RACE_RESULT (run)` | Hud auto-show, BestToast | `RACE_RESULT (record)` | The record carries `race`; the toast reads `record.race.status`. |
| `RUNS_CHANGED` | Hud `runsChanged` | `FIGHTS_CHANGED` (CT `core/Bus.lua:40`) | Delete-flow callback (#10). |
| `SETTINGS_CHANGED (path)` | Hud: `LateIgnore.PATH`, `DummyList.PATH`, `"profile"`; BestToast: `"profile"` | `SETTINGS_CHANGED (path, value)` | Paths become plan B3/A2 keys; the Race window also needs `hud.*` (restyle, #21). |
| `FIGHT_SAVED (record)` | none | CT | Fights toast (#27). |
| `FIGHT_TICK (fight)` | none | CT, 4 Hz in combat | The Race window's pace total (#7). |

### #29 Lifecycle and gating
- **DR:** `Hud.Suspend()` (`:1027-1033`) cancels live reads, hides, unregisters everything and drops an addon-opened window. `Hud.Resume()` (`:1036`). `Countdown.Suspend/Resume`. `BestToast.Suspend`.
- **CT:** the module list is CT `core/LifecycleSetup.lua:14-16`; stand-up resumes are at `core/CombatTrail.lua:~50-68`. Add `RaceWindow`, `Countdown` and `BestToast` to both.
- **Gating:** every race surface asks B3's `NS.RaceMode.On()`. On Forever the Race window, countdown and race toast are **absent** (clients-§4). The fights toast is not.
- **DR tests:** `test_disabled.lua` (15, including "Disabled 5 (countdown)" and "Disabled (race)…"), `test_hud_window.lua` ("the stand-down drops every registration, timer and the OnUpdate", "General visibility and the stand-down hide it at the source").

### #30 DR tests by fate
- **Port to C1 (adapt to CT fixtures, `tests/hud_fixture.lua`):** `test_hud.lua` (minus the live rows and DPS cases), `test_hud_best.lua`, `test_hud_hint.lua`, `test_hud_tiles.lua` (minus the running and result KPI height cases), `test_hud_layout.lua` (the button, Stop Now, Cancel, Delete, result chip and New Race cases; drop the row cases), `test_hud_element_tips.lua`, `test_hud_tips.lua`, `test_hud_window.lua` (shell, show rules, stand-down, tests strip, title, clock font cases), `test_pace.lua` (the result card and Before cases), `test_late_ignore_ui.lua`, `test_layers.lua` (the Race window case).
- **Port to C2:** `test_countdown.lua`, `test_toast.lua`, the buzzer case of `test_hud.lua`, `test_layers.lua` (the countdown case), the toast-stub part of `test_surface_parity.lua`.
- **DROP (CT owns or retires):** `test_hud_sizing.lua`, `test_sizing.lua`, `test_chart.lua`, `test_chart_icons.lua`, `test_hud_icon_edge.lua`, `test_bar_style.lua` (CT has `test_hud_appearance.lua`, `test_hud_chart.lua`, `test_hud_breakdown.lua`, `test_hud_sizing.lua`, `test_hud_layout.lua`, `test_hud_states.lua`), and the running-body row and chart cases.
- **Fixtures DR's suites lean on, which CT lacks:** `tests/race_clock.lua` (the race clock driver), `tests/mock_widgets.lua`, `tests/mock_meter.lua`. C1 and C2 need race-clock equivalents on CT's `hud_fixture.lua`.

## dummies

DR paths are relative to `/mnt/d/Profile/Users/Tushar/Documents/GIT/DpsRace` (master f8078c7). CT paths are relative to `/mnt/d/Profile/Users/Tushar/Documents/GIT/CombatTrail` (feat/2026-11-11-race-mode).

### #1 The seed catalog: shape, categories, labels

- **DR:** `defaults/Dummies.lua:15-71`.
- **What it does:**
  - `NS.Dummies.CATEGORIES = { "single", "cleave", "dungeoneer", "boss", "pvp", "other" }` (`:15`) is the display order, with `"other"` meaning any target that is not in the catalog.
  - `Dummies.LABELS` (`:17-24`) holds the enUS labels: `L["Single target"]`, `L["Cleave"]`, `L["Dungeoneer"]`, `L["Boss-level"]`, `L["PvP"]`, `L["Other"]`.
  - `Dummies.BY_ID[creatureID] = { name = "...", category = "<kind>" }` (`:28-71`) has 42 rows: 15 single, 3 cleave, 8 dungeoneer, 12 boss, 4 pvp. Each row carries a `-- date, places` measurement comment.
  - The catalog is Retail only, and one table serves every client.
- **API:**
  - `Dummies.BuiltIn(npcID) -> {name, category}|nil` (`:76-82`) returns a fresh copy and refuses a key that fails `Secrets.IsSafeKey`.
  - `Dummies.Lookup(npcID)` (`:89-97`) answers the profile list first. A hidden entry answers nil. A custom entry answers `{ name = DummyList.NameOf(id), category }`, and the name is nil when the creature was never captured. Anything else falls through to `BuiltIn`.
  - `Dummies.CategoryOf(target)` (`:104-111`) takes a run's **target table**, not an ID. It returns the read-time category for `target.npcID`, or `target.category` when there is no ID, or `"other"`.
  - `Dummies.Label(cat)` (`:116-118`) labels an unknown key as Other.
- **CT seam:** `defaults/Dummies.lua:22-72`, which is already `NS.Dummies = { Retail = { [id] = "name" }, Forever = {} }` (the same 42 IDs, names only, categories stripped; the header at `:6-9` says the DR DummyList was not ported). `NS.DUMMIES` is picked once at file scope (`:72`). The TOC loads it after `defaults\Profile.lua` (`CombatTrail.toc:96-98`). Owner: **A2**.
- **Differs / conflicts:**
  - The CT global `NS.Dummies` is already taken by the per-client data table, so the A2 module `NS.Dummies` must replace it. `tests/test_identity.lua:303-311` pins `NS.Dummies.Forever`, `NS.Dummies.Retail[31146]` and `NS.DUMMIES == want`, so that test is rewritten in A2.
  - The categories must be added back to the CT Retail rows from DR `BY_ID`.
  - Forever stays empty by decision (CT `defaults/Dummies.lua:16-18`). The plan allows this.
  - The plan says `NS.Dummies.CATEGORIES` is an ordered list of the 5 kinds, but DR has two lists: `CATEGORIES` (6, with `other`) and `DummyList.KINDS` (5). The builder has to pick one, and race-board and filter code needs `other`.
  - The 6 labels are not in CT `locales/enUS.lua` yet.
- **DR tests:** `tests/test_dummies.lua` ("dummies: Lookup known and unknown npcID", "the catalog holds exactly the measured rows", "Lookup answers a copy…", "six categories in order, each with an enUS label", "every cataloged category is one of the six").

### #2 The player's own list: storage, row, parse/normalize

- **DR:** `modules/DummyList.lua:1-114`, `defaults/Profile.lua:91-98`, `settings/Race.lua:139-146`.
- **What it does:**
  - **Storage is one plain string** at the profile path `race.dummies` (`DummyList.PATH`, `:23`), default `""` (`Profile.lua:95`), for example `"243300:cleave,-243205"`.
    - `id:category` marks a creature that is not built in.
    - `-id` switches off a built-in.
    - A built-in is never recategorized.
  - The string is written whole through `NS.SetByPath`, so `/dr get|set|reset race.dummies` reach it.
  - Constants:
    - `DummyList.KINDS = { "single","cleave","dungeoneer","boss","pvp" }` (`:28`).
    - `DummyList.MAX_ID = 2^31-1` (`:33`).
    - `DummyList.CATEGORY_PATH = "race.dummyCategory"` (`:24`), default `"auto"` (`Profile.lua:98`).
    - `DummyList.DEFAULT` is the profile default.
  - Functions:
    - `Parse(text) -> entries|nil` (`:43-60`) returns entries sorted by ID, last one wins, shaped `{id, category}` or `{id, hidden=true}`. One bad token makes the whole result nil.
    - `Join(entries)` (`:72-79`).
    - `Normalize(text)` (`:83-86`) drops a custom entry for a built-in and a hide for a non-built-in.
    - `Entry(id)` (`:102-106`) and `Entries()` (`:109-114`) return copies and cache the parse by text (`:89-98`).
  - Schema row: `type="string"`, `skipRender=true`, `validate = Parse(v) ~= nil`, `normalize = Normalize` (`settings/Race.lua:142-146`).
  - **Read time:** a list change or a profile switch recategorizes every stored run. Consumers listen for `SETTINGS_CHANGED` on `PATH` and on `"profile"`.
- **CT seam:** `defaults/Profile.lua:101-228` (the profile block; `history` at `:191-194`). The new module is `modules/Dummies.lua`. Owner: **A2**.
- **Differs / conflicts:**
  - **The plan's storage (`dummies = { custom = {} }` per profile) contradicts DR's one-string row.** DR's whole-row seam is what makes `/ct get|set|reset` and the page's Defaults work, the same way the CT Usage list `usage.hidden` already works (`defaults/Profile.lua:240`, `modules/Usage.lua`). Keep the string and pick a CT path, for example `history.dummies` plus `history.dummyCategory`, because the section sits on the History page. Flag this to the owner.
  - A table-shaped value would need a custom CLI and a custom reset.
  - The plan's "a custom entry without one is `single`" drops DR's `dummyCategory = "auto"` inference (#4). Decide which one wins.
  - A switched-off built-in (`-id`) has no counterpart in the plan's `Add/Remove`. DR's `Remove(builtin)` hides it.
- **DR tests:** `tests/test_dummy_list.lua` ("Parse reads entries and hides, ascending, the last of an ID winning", "Normalize drops a custom entry for a built-in and a hide of a non-built-in", "the row refuses what does not parse and stores what it normalizes", "Reset clears the list; a profile switch reads the other profile's"). `tests/test_settings.lua` also touches the row.

### #3 List writes: Add / Remove / Reset

- **DR:** `modules/DummyList.lua:118-174`.
- **What it does:**
  - `Add(id, category) -> "added"|"restored"|"changed"|nil` (`:139-153`):
    - On a built-in it only un-hides one (`"restored"`) and ignores the category.
    - On a custom creature it needs a valid `KIND`.
    - When the category is unchanged it returns nil.
  - `Remove(id) -> "removed"|"hidden"|nil` (`:157-169`).
  - `Reset() -> boolean` writes `DEFAULT` (`:172-174`).
  - IDs go through `plainId` (`Secrets.PlainNumber`, whole, `1..MAX_ID`) at `:130-133`.
  - Every write is `NS.SetByPath(PATH, Join(...))`.
- **CT seam:** `NS.SetByPath` exists in CT (`settings/Schema.lua`, used by `modules/Usage.lua`). Owner: **A2**.
- **Differs / conflicts:**
  - The plan names `Add(id, category)`, `Remove(id)` and `Defaults()`, but DR's is `Reset()` and returns outcome strings that the slash lines depend on (#7). Keep the outcomes.
- **DR tests:** `tests/test_dummy_list.lua` ("Add marks a creature, Lookup answers it, Remove takes it off", "a built-in is switched off and back on, never recategorized").

### #4 Category for a new dummy: Infer / CategoryWord / CategoryFor

- **DR:** `modules/DummyList.lua:178-212`.
- **What it does:**
  - `Infer({name, classification, level})` (`:184-192`, pure) checks name words in order: "cleave" gives cleave, "dungeoneer" gives dungeoneer, "pvp" gives pvp. Otherwise `classification == "worldboss"` or `level == -1` gives boss, and anything else gives single.
  - `CategoryWord(word)` (`:195-202`) accepts a key or a localized label and returns nil for "auto".
  - `CategoryFor(t, word)` (`:206-212`) uses the typed word, then the `race.dummyCategory` row, then `Infer(t)`.
  - The settings dropdown `categoryValues()` (`settings/Race.lua:23-28`) puts `{ "auto", L["Automatic"] }` first, followed by the KINDS.
- **CT seam:** `modules/Dummies.lua` (new). Owner: **A2**.
- **Differs / conflicts:**
  - The plan defaults an uncategorized custom entry to `"single"` with no inference (see #2).
  - A category only matters to races (spec §9), but a dummy added on Forever still needs one.
- **DR tests:** `tests/test_dummy_list.lua` ("Infer reads a name word, then a boss classification or skull level, else single", "CategoryFor takes a typed word, else the row, and auto infers").

### #5 Captures: storage and read

- **DR:** `modules/DummyList.lua:214-310`, `defaults/Profile.lua:282-284`.
- **What it does:**
  - **Storage:** `db.global.dummies.captures[npcID]` (default `global.dummies = { captures = {} }`) is data, not a setting. It is global because a creature is the same on every profile. `store()` repairs a missing table (`:223-229`).
  - `DummyList.Read(unit="target")` (`:250-270`) returns `{ npcID, name, level, classification, health (UnitHealthMax), creatureType, pvp (bool), faction, reaction, mapID, zone, subzone, x, y }`.
    - Every field passes `Secrets`, and a sealed field is left out.
    - `x` and `y` are map percent rounded to 2 places (`:243-245`).
    - It returns nil when the unit is not a creature.
    - It depends on `NS.Recorder.NpcIDOf`, `NS.Recorder.SnapshotTarget` and `NS.Recorder.SnapshotWhere` (DR `modules/Recorder.lua:118-120, 145-159, 163-173`).
  - `DummyList.Capture(r)` (`:277-295`) builds the record:
    - `DETAIL_FIELDS = { name, level, classification, health, creatureType, pvp, faction, reaction }`, latest value wins.
    - `first`, `last` (`time()`), `count++`, `addon = NS.Version()`, `build = GetBuildInfo` (4th return).
    - `places[mapID] = { zone, subzone, x, y, date }`.
  - Lookups:
    - `Captured(id)` (`:298-302`).
    - `NameOf(id)` (`:305-310`) uses the capture name, then the catalog name, then nil.
    - `Resolve(text) -> id | nil, "empty"|"notFound"` (`:335-345`) accepts digits or a captured or cataloged name, case-insensitive, lowest ID first (`:313-323`).
  - Only the slash verbs and the page's Add-your-target write captures. A race never writes one.
- **CT seam:** plan `db.global.dummies.captures` in `defaults/Profile.lua:230-246` (the global block). The CT equivalents of DR Recorder's readers are **local to `modules/Identity.lua`**: `creatureOf(guid)` at `:113-119`, `readTarget()` at `:206-218` (fields `creatureID`, not `npcID`), and `readWhere()`. Owner: **A2**.
- **Differs / conflicts:**
  - CT has no exported `NpcIDOf`, `SnapshotTarget` or `SnapshotWhere`. A2 must export a unit-to-creature-ID helper from Identity (it is also needed by AutoArm, #9) or carry its own.
  - CT spells the field `creatureID` and DR spells it `npcID`. Pick one key for the capture record. Keeping `npcID` keeps DR captures recognizable, but nothing migrates DR SavedVariables anyway.
  - The plan's `Capture()` has no arguments, while DR splits it into `Read(unit)` and `Capture(r)`.
  - `NS.Version` exists in CT (`core/EnvSetup.lua`).
- **DR tests:** `tests/test_dummy_list.lua` ("Read and Capture keep what the game says, by map, and count the captures", "a sealed field is left out of the read, and a player is no creature", "Resolve takes an ID or a captured or cataloged name", "a captured custom dummy answers its captured name").

### #6 Read-time recategorization of stored runs

- **DR:** `defaults/Dummies.lua:99-111`, `modules/Recorder.lua:140-159` (`SnapshotTarget` freezes `t.category`, but `CategoryOf` prefers the live lookup by `npcID`).
- **What it does:** a stored run moves boards when its creature is added or removed. A run with no creature ID (its GUID was secret) keeps the category it recorded. Bests and Results caches drop on `SETTINGS_CHANGED` for `race.dummies` and `"profile"`.
- **CT seam:**
  - `modules/Identity.lua:317-323` `contentOf` (`NS.DummyName(ident.targetCreatureID)` gives `"dummy"`) and `:357-363` `isBoss` (a dummy is never a boss).
  - CT content is **frozen** into `fight.identity.content` at `Identity.Resolve` (`:375-394`). Board keys `t:<npc>:<level>:<name>:<diff>` (`:397-420`) carry no category.
  - Owners: **A2** (content), A3 and the bests area (race boards by `kind`).
- **Differs / conflicts:**
  - In CT, a fight saved before a creature became a custom dummy stays `world`. DR re-reads at display time. Decide whether CT Filters and Results re-derive `content` from `targetCreatureID` at read time or keep it frozen. The plan does not say.
  - `race.kind` on the record (spec §5) should be read through `Dummies.CategoryOf` by creature ID at read time, as in DR, or race boards will not follow list edits.
- **DR tests:** `tests/test_dummy_list.lua` ("CategoryOf reads a stored target by its creature as the list is now", "a stored run moves boards when its creature is added, and back when removed", "switching a built-in off sends its runs to Other; a run with no creature ID keeps its own", "a new snapshot of a listed creature is categorized and auto-arm sees it", "the idle HUD's unknown-target warning follows the list without a target change"). `tests/test_results_badges.lua` and `tests/test_refactor_pins.lua` also read `Dummies`.

### #7 Slash verb `/dr targetdummy`

- **DR:** `settings/Slash.lua:74-77` (registration), `:97-100` (`HOST_LIVE_VERBS = { "ignore", "targetdummy" }`, so it answers while disabled), `:372-502` (`doTargetDummy`).
- **What it does:** `targetdummy [show|add|remove|capture|defaults] [category or creature ID]`. A bare verb or `""` means show. An unknown word prints the usage.
  - `show` lists your own dummies as `"  %s · %s"`, then `"Built-in training dummies: %d, %d switched off."`, then the switched-off ones as `"  %s (off)"`.
  - `capture` runs `Read` and `Capture` and prints `"Saved: <captureLine>"` (level, health, type, PvP flag, place).
  - `add [category|auto]`:
    - It refuses a word that is not a category: `"'%s' is no category. Use single, cleave, dungeoneer, boss or pvp."`.
    - It captures, then calls `Add(npcID, CategoryFor(r, word))`.
    - The line depends on the outcome: "is a training dummy now", "again", "already a built-in", "already".
  - `remove [id|name]` resolves the text, or uses the target when there is no text, and prints "no longer", "switched off… add brings it back" or "is not".
  - `defaults` runs `Reset()` and then `show`.
  - `dummyName(id)` formats as `"Name (id)"` or `"Creature %d"`.
  - A related verb is `/dr target` (`:304-312`), which prints the target's name, creature and category.
- **CT seam:**
  - `settings/Slash.lua:31-69`: the verb table. A new `{ "dummy", ... }` goes there.
  - `settings/Slash.lua:93`: `HOST_LIVE_VERBS = { "lane", "ignore" }`. Add `"dummy"` there so it is live while disabled on both clients, as the plan says.
  - `settings/Slash.lua:162-165`: the live set.
  - Owner: **A2**.
- **Differs / conflicts:**
  - The verb is renamed `targetdummy` to `dummy`, and every user string changes `%s targetdummy add` to `/ct dummy add`.
  - The DR verb test pins the live-verb list. The CT equivalent test (the live set equals the library's LIVE_VERBS plus host verbs) must add `dummy`.
  - There is no CT `/ct target` verb. Decide whether to drop it or fold it into `/ct dummy show`.
- **DR tests:** `tests/test_dummy_list.lua` ("targetdummy: add marks the target, captures it and says what it saved", "add refuses a word that is no category, no target, and a player", "on a built-in, add says so and captures; remove switches it off, add brings it back", "remove takes a typed creature ID or name; show lists yours and the switched-off", "capture saves without marking; an unknown word prints the usage", "answers while the addon is disabled, as ignore does"). `tests/test_slash.lua:573` ("the live dispatcher's live set is the library's LIVE_VERBS plus ignore and targetdummy").

### #8 The Training dummies settings section

- **DR:** `settings/Race.lua:135-146` (rows), `:188-258` (`afterDummies`), `:268-274` (page), `:276-291` (repaint).
- **What it does:**
  - Rows:
    - `race.dummyCategory`, a dropdown labelled "Category for new dummies" (Automatic plus 5 kinds).
    - `race.dummies`, a skipRender string row.
  - The body:
    - A blurb.
    - An **Add your target** button (`addTarget`: Read, Capture, `Add(id, CategoryFor(r))`).
    - `H.IdList` over your own dummies (`DUMMY_KIND = { noun="creature", plural="creatures", resolve=DummyList.Resolve, info=DummyList.NameOf }`, entry suffix `"· <label>"`, `onAdd = Add(id, CategoryFor({name=NameOf(id)}))`, `onRemove = Remove`, `removeStyle="icon"`).
    - One `H.SessionCheckbox` per built-in, ascending by ID, labelled `"%s (%d) · %s"`, `get = Lookup(id) ~= nil`, `set = Add/Remove`.
    - A **Reset list** button that leaves the category row alone.
  - The page repaints on `SETTINGS_CHANGED` for `DummyList.PATH` or `"profile"`.
  - It sits on the Race page, as its own tab.
- **CT seam:**
  - `settings/History.lua:35-39`: `NS.HISTORY_TAB_ORDER = { "recording","retention","results","usage" }`.
  - `settings/History.lua:245-252`: `RegisterTabbedPage` with `afterGroup`.
  - `settings/History.lua:262-270`: repaint on `NS.Usage.HIDDEN_PATH`. Add the dummy path there.
  - The CT Usage IdList at `:222-243` is the pattern to follow.
  - `H.SessionCheckbox` exists (`settings/OptionsSetup.lua:137` lists it).
  - Owner: **A2** (both clients).
- **Differs / conflicts:**
  - The plan says "a Training dummies section" on History. Either it becomes a 5th tab, which breaks `tests/test_history_page.lua:86`'s pinned order `"recording,retention,results,usage"` (update it), or it becomes a subgroup of an existing tab. Decide which.
  - On Forever the built-in checkbox list is empty, because the seed list is empty. Only Add your target and the IdList show, and the blurb must not promise built-ins there.
  - DR's blurb text mentions races, auto-arm and `/dr targetdummy`. CT needs fight wording ("a fight on one is stored as a Training dummies fight").
  - The CT row `history.content.dummy` already carries the label `L["Training dummies"]` (`settings/History.lua:89`), so the tab or section name collides with that label in the Recording filters.
- **DR tests:** `tests/test_settings.lua` (rows and page). The body behavior is covered through `tests/test_dummy_list.lua`.

### #9 Every CT call site of `NS.DummyName` (and `NS.DUMMIES`)

- **Definition:** CT `defaults/Dummies.lua:78-81`, `function NS.DummyName(creatureID)`. It calls `IsSafeKey`, then returns `NS.DUMMIES[creatureID]`, which is `string|nil`.
- **Call sites:**
  1. `modules/Identity.lua:214-216` (`readTarget`): `t.isDummy = NS.DummyName(t.creatureID) ~= nil`, and the name falls back to the dummy name.
  2. `modules/Identity.lua:318` (`contentOf`): returns `"dummy"`.
  3. `modules/Identity.lua:352` (`resolveTarget`): `targetName = first.name or NS.DummyName(first.creatureID) or encounterName`.
  4. `modules/MockFights.lua:113-114`: sample `target = { name = NS.DummyName(31146), creatureID = 31146 }`.
  5. Tests: `tests/test_identity.lua:305-310` (`NS.Dummies.Forever/Retail`, `NS.DUMMIES`, `NS.DummyName(nil|1985)`), and `:318` and `:329`, which **write** `NS.DUMMIES[id] = ...` to make a fixture dummy.
  6. Docs and TOC: `CombatTrail.toc:96-98` and `:127-129` (the Identity comment says it reaches `NS.DummyName`), and `docs/test-cases.md:425`.
- **CT seam:** owner **A2**. There are four source call sites, so the plan's rule applies: replace them with `NS.Dummies.Name` and drop the alias.
- **Differs / conflicts:**
  - The `isDummy` and `contentOf` tests must become `Dummies.Lookup(id) ~= nil`, so that a hidden built-in stops counting and a custom one counts.
  - The test fixtures that write `NS.DUMMIES` must use `Dummies.Add` or a stubbed setting instead.
  - On Forever, `MockFights` site 4 gives `name = nil` (an empty catalog). The header at `modules/MockFights.lua:22` documents this already.
  - The TOC must load `modules/Dummies.lua` before `modules/Identity.lua`, or Dummies must be reached at call time only. Its `DEFAULT` read of `NS.defaults` needs `defaults\Profile.lua` first.

### #10 AutoArm: auto-show and auto-arm near a dummy

- **DR:** `modules/AutoArm.lua:1-277`, `defaults/Profile.lua:107-110` (`race.autoArm = false`) and `:142` (`hud.autoShow = true`), `settings/Race.lua:44-47`, `settings/Hud.lua:48-51` (`onChange = AutoArm.Sync`), `core/DpsRace.lua:42` (`AutoArm.Resume()` on enable), `core/LifecycleSetup.lua:23,40` (stand-down and stand-up lists).
- **What it does:**
  - **Constant:** `AutoArm.HIDE_DELAY = 3` seconds.
  - **Events:** `TARGET_EVENTS = { PLAYER_TARGET_CHANGED, PLAYER_ENTERING_WORLD }` and `PLATE_EVENTS = { NAME_PLATE_UNIT_ADDED, NAME_PLATE_UNIT_REMOVED }`. They are registered on the module's own AceEvent target through `NS.SafeRegisterEvent(events, ev, fn, NS.rejectedEvents)`.
  - **Registration set** (`wanted()`, `:201-206`): `"plates"` when autoShow is on, `"target"` when only autoArm is on, otherwise `"none"`. It is `"none"` while stood down.
  - **`isDummy(unit)`** is `Recorder.DummyOf(unit) ~= nil`, which reads the catalog and the list, and a secret GUID counts as no dummy.
  - **Auto-show:**
    - A dummy session runs from the first dummy seen (the target or a plate) until none has been seen for 3 s. A `C_Timer.NewTimer` that the next dummy cancels debounces the hide.
    - At the timer's fire the plates are rescanned (`C_NamePlate.GetNamePlates`, `namePlateUnitToken`).
    - It opens through `Hud.ShowNearDummy()` and closes through `Hud.HideAwayFromDummy()`, and only while the race is IDLE.
    - **Manual-close rule:** when `Hud.Closes()` changes within a session, the window is not reopened until that session ends.
  - **Auto-arm** (`tryArm`, `:141-148`):
    - It fires on a target change to a dummy when autoArm is on, the client is active, no Preview is on, the race is IDLE and the player is not `UnitAffectingCombat`.
    - It calls `Race.Arm(Hud.ArmLength())` silently and remembers `armedRun = Race.Current()`.
  - **Disarm** (`:152-160`): out of combat only, and only when the run is still ARMED and is the rule's own. A started race, or one the player armed, is never disarmed.
  - **Stand-down** (`inInstance`): any `GetInstanceInfo` type other than `"none"` stands it down.
  - **Bus:** `RACE_STATE_CHANGED (run, from, to)` clears `armedRun` when the state leaves ARMED and calls `decideShow()` on IDLE, ignoring `run.sample`. `SETTINGS_CHANGED` on `"profile"` or `DummyList.PATH` calls `Sync()`.
  - **API:** `AutoArm.Sync()`, `Suspend()`, `Resume()`, `Diagnose() -> { events, plates, session, hiding, armed }`.
  - The DR HUD seam lives in `modules/Hud.lua:1061-1091` (`ShowNearDummy`, `HideAwayFromDummy`, `ShownNearDummy`, `Closes`, `ArmLength`).
- **CT seam:**
  - New `modules/AutoArm.lua`, Retail only. Owner: **B3**, with the Race window seams owned by **C1**.
  - CT `modules/Hud.lua:8` states the CT HUD has no auto-show. The CT `Hud.Show(reason)` and `Hud.Hide()` are at `:788` and `:796`, and `Hud.lua` (1070 lines) takes seams only.
  - `NS.SafeRegisterEvent` is at `core/CoreSetup.lua:62,85` and `NS.IsStoodDown` is used in `core/Bus.lua:107`.
  - No `C_NamePlate` or `NAME_PLATE` use exists in CT yet. The new event set needs Compat or the Watchers doc (`docs/ARCHITECTURE.md`, event wiring per state).
- **Differs / conflicts:**
  - Auto-show drives the **Race window**, not the CT HUD (spec §4.1). The five `Hud.*` hooks must exist on the Race window (C1): `ShowNearDummy`, `HideAwayFromDummy`, `ShownNearDummy`, `Closes`, `ArmLength`. Because B3 comes before C1 in the plan, B3 needs stubs or must reorder.
  - `hud.autoShow` moves to the `race.*` table (the Race section, B3). Defaults stay autoShow true and autoArm false.
  - Both rules must also gate on `NS.RaceMode.On()`. When off, nothing is registered.
  - **The plan's B1 bus list has no `RACE_STATE_CHANGED`.** AutoArm needs the leave-ARMED and enter-IDLE edges, so either add it in B1 or derive the edges from `RACE_ARMED`, `RACE_STARTED`, `RACE_RESULT` and `RACE_CANCELLED` plus the result-card dismissal.
  - `previewOn()` should cover CT Sim as well as Preview.
  - `isDummy(unit)` needs a CT unit-to-creature-ID helper (see #5).
  - On Forever the module is absent, and the absent test lives in B3.
  - Plan Review focus 1 (a non-dummy pull cancels the arm) belongs to B1. AutoArm's own disarm on a target change covers only the case before the pull.
- **DR tests:** `tests/test_autoarm.lua` has 32 cases, including:
  - "a new profile shows the HUD near a dummy and never arms by itself", "both rules off register nothing", "each rule registers only what it needs…".
  - autoshow cases: target, nameplate, churn inside the debounce, the rescan at the fire, a secret GUID, the player's close, a window the player opened, a race or result holding the window, the idle edge, test mode, General visibility, turning the rule off.
  - autoarm cases: arms at the HUD's length, a non-dummy target arms nothing, Race.Arm's refusals hold silently, no arm over a result or in test mode, a target change before the pull disarms, a started race is never disarmed, no disarm in combat, a player-armed race is not the rule's, Cancel then re-arm, alongside auto-show, a profile switch re-reads both rows, not in an instance or battleground, entering an instance closes the window, stood down then stand-up.
  - `tests/test_sample_parity.lua` and `tests/test_settings.lua` also touch it.

### #11 LateIgnore: the late-cast ignore list

- **DR:** `modules/LateIgnore.lua:1-329`, `defaults/Profile.lua:85-90`, `defaults/Hearthstones.lua:26` (`NS.HEARTHSTONE_SPELLS`, 59 IDs), `settings/Race.lua:83-90, 148-186`, `settings/Slash.lua:70-73, 314-370`.
- **What it does:**
  - **Storage:** one string at the profile path `race.lateIgnore`, default `"66,1856,5384,8690,58984,110959"` (Invisibility, Vanish, Feign Death, Hearthstone, Shadowmeld, Greater Invisibility). It is read at score time and never frozen into a run.
  - `LateIgnore.HEARTHSTONE = 8690` stands for every hearthstone variant. It is expanded only in `Set()`, and `compact()` drops any variant it already covers.
  - List functions: `Parse`, `Join`, `Normalize` (validate and normalize the row), `List()`, `Set()` (a cached table), `IsIgnored(id, set)` (a sealed nil ID is never ignored), `Covering(id)`.
  - Writes: `Ignore(id)`, `Unignore(id)` (a variant ignored only through 8690 removes 8690), `Reset()`.
  - Names and lookup:
    - `Label(id)` formats as `"%s (%d)"`, `"%s, all variants (%d)"` or "Unknown spell".
    - `Resolve(text, candidates) -> id,name,icon | nil,"empty"|"notFound"|"ambiguous"` accepts digits, a `spell:` link, a hearthstone name (`hearthByName`), then `NS.Helpers.ResolveId("spell", ...)`.
    - `KnownSpells()` reads `db.global.runs[*].flags.lateCasts[*].spellID` newest first by `run.date`, then the defaults.
  - Menu:
    - `MenuEntries(run)` uses `NS.Scoring.SplitLate(run)` and returns "Ignore %s for late casts" for a counted cast, and "Stop ignoring %s" or "Stop ignoring all hearthstones" for an ignored one.
    - `Offers`, `FillMenu(root, run)`, `Menu(run, owner)` (`NS.CanOpenMenu`/`NS.OpenMenu`, titled "Late casts").
  - Page body: a blurb, `H.IdList` (`kind = { base="spell", resolve=LateIgnore.Resolve }`, entry suffix "(all hearthstones, %d)" for 8690, `columns=2`), and a **Reset list** button.
  - Slash: `/dr ignore [show|add|remove|defaults] <spell ID, link or name>`, a HOST_LIVE verb that answers while disabled.
- **CT seam:**
  - New `modules/LateIgnore.lua`, owner **B1**.
  - The page section and the `/ct race ignore` sub-verb belong to **B3**.
  - The right-click on rows and in the detail belongs to **D1**.
  - `NS.CanOpenMenu` and `NS.OpenMenu` exist (`core/WidgetsSetup.lua`), and `H.IdList` too (`settings/History.lua:227`). CT `modules/LaneIgnore.lua` is the lanes' unrelated list.
- **Differs / conflicts:**
  - CT has **no `NS.HEARTHSTONE_SPELLS`**, so `defaults/Hearthstones.lua` must be ported with it. B1 does not list it.
  - `KnownSpells` must read `db.global.fights[*].race.flags.lateCasts` (the CT store at `defaults/Profile.lua:236-237`) and sort by the CT fight date field.
  - `MenuEntries` depends on `RaceScoring.SplitLate` (B1).
  - The verb moves from `/dr ignore` to `/ct race ignore`, because `/ct ignore` is the lanes' list (`settings/Slash.lua:69`, already a HOST_LIVE verb). DR made `ignore` live while disabled. Under CT, `race` is a Retail feature verb, so decide whether `race ignore` answers while disabled. Accepting either answer needs a ruling, because DR declined the slash-commands-§2 feature-verb refusal for it.
  - The path becomes `race.lateIgnore` inside CT's new `race` table (B3's defaults).
  - The section and the verb are absent on Forever. Saved races' flags still re-score at read time on Forever, with the default list.
- **DR tests:** `tests/test_late_ignore.lua` (20 cases: the hearthstone table holds 59 IDs; parse, normalize, default, writes through the seam, Resolve including the degraded load, KnownSpells, the result chips, read-time re-score, the detail ticks, the list change redraws and cache drops, a profile switch re-scores, the menu entries, IgnoredText, the tooltips), `tests/test_late_ignore_ui.lua` (the detail's Flags box right-click, the row-menu submenu only with a late cast, the sample history offers no menu), and `tests/test_slash.lua:479-571` (the six `slash: ignore …` cases).

## bests

### #1 The race board key: `specID|category|length`, no character
- **DR:** `modules/Bests.lua:30-36`, `Bests.Key(run) -> string`, returns `("%s|%s|%s"):format(tostring(char.specID), tostring(NS.Dummies.CategoryOf(target)), tostring(race.length))`. The key has no character, so DR boards span every character on the account (header :2-3). The category is **read at read time**. `defaults/Dummies.lua:104` `Dummies.CategoryOf(target)` re-looks up `target.npcID` through `Dummies.Lookup`, which checks the player's own list (`race.dummies`) before the built-ins. It answers `"other"` when the creature is no dummy now. It keeps the stored `target.category` only when the run has no `npcID`. Editing the dummy list, or switching profile, therefore moves stored runs between boards.
- **CT seam:** `modules/Bests.lua:39-47` `Bests.Key(record)` = `boardOf(Bests.CharKey(who), who.specID, record.boardKey)`, with `CharKey` = `"name|realm|client"` (:26-29). `record.boardKey` is `Identity.BoardKey(identity)` (`modules/Identity.lua:411`). For a dummy that is a `t:<npc>:<level>:<name>:<diff>` key. **Owner: A3.** The plan's `NS.Bests.RaceKey(record) = "race:" .. kind .. ":" .. length` goes in the boardKey slot, so a race's full key is `<char>|<specID>|race:<kind>:<length>` (spec §5: character + spec + dummy kind + length).
- **Differs / conflicts:**
  - CT adds the character and client to the key. DR's cross-character boards go away (owner, spec §5). Retail and Forever never mix.
  - The stored `record.boardKey` is the dummy's fight key. `Bests.Key` must answer `RaceKey` whenever `RaceRecord.IsRace(record)`, never `record.boardKey`. That is spec §5's "a race counts only on its race board". The cleanest seam is a branch at the top of `Bests.Key`, which keeps every existing caller race-aware with no change: `Hud.lua:187,190,213`, `Results_Detail.lua:134-138`, `Results_Compare.lua:107-112,137-138`, `Results_Source.lua:119-143`, `MockFights.lua:516-517`.
  - **Frozen vs read-time kind.** The spec puts `race.kind` in the record. DR never trusts the stored category when it has a creature ID (#9). To keep DR's behavior, `RaceKey` should use `NS.Dummies.CategoryOf(identity.targetCreatureID)` (A2's API takes a creatureID) and fall back to the stored `race.kind` only when the ID is absent or no dummy now. Otherwise a dummy-list edit no longer recategorizes races, and DR tests `test_dummy_list.lua:228` and `:242` cannot port. **Decision for A3; it needs A2's `CategoryOf` signature.** DR's `"other"` category (no dummy now) has no CT equivalent. A race whose creature stops being a dummy needs a defined answer: keep `race.kind`, or `"other"`.
  - `RaceKey` must answer nil without `who.name` or `length`, as `Bests.Key` does.
- **DR tests:** `test_bests.lua:50` "Key is specID|category|length", `:91` "two Dungeoneer npcIDs share one board", `:102` "spec, category and length each split the board"; `test_dummy_list.lua:100,228,242`.

### #2 What counts, the ranking and the tie
- **DR:** `Bests.lua:38-60`. `counts(run)` = `run.status == "complete"` and `run.result.dps` is a number, so incomplete and lost runs never count (spec §5.4). `ranksAbove`: higher `result.dps`, then the earlier `date`, then `tostring(id)` ascending. `Bests.Compute(runs, opts)` (:66-77) builds `{ [key] = run }`, where `opts.cleanOnly == true` leaves out every flagged run.
- **CT seam:** `Bests.lua:49-60` `counts(record)` = `status == "final"`, numeric `record.dps`, and `Bests.Key ~= nil`. `ranksAbove`: `dps`, then `t`, then id. **`Bests.Compute(records, skip)` (:66) takes a *record to skip* as its second argument**, not an opts table. `Results_Compare.lua:112` calls `Compute(all, best)` for the runner-up. **Owner: A3.**
- **Differs:**
  - For a race, `counts` must also require `race.status == "complete"` and read `race.dps` (through `NS.RaceRecord.Dps`), not the fight's `dps`. The record's own `status` stays `"final"`.
  - `ranksAbove` on a race board compares `RaceRecord.Dps`.
  - A3 must not repurpose `Compute`'s second argument: `Results_Compare` depends on it. Add the clean view as a third argument, `Compute(records, skip, opts)`, or as a separate function.
  - Ties break on `t` (CT's combat-entry epoch) where DR used `date` (the arm time, restamped at the start). The two are close, but not the same instant.
- **DR tests:** `test_bests.lua:55` "incomplete and lost never count", `:70` "the highest result.dps holds the board; a tie keeps the earlier run", `:111` "deleting a best promotes the next run". CT tests to extend: `tests/test_bests.lua:35,54,110,132`.

### #3 The clean-only board
- **DR:** `Bests.lua:49-51`. `flagged(run)` = `#NS.Scoring.Flags(run) > 0`. `Scoring.Flags` (`Scoring.lua:131-158`) lists, in order: `lateCasts` (counted only after `LateIgnore.Set()` is applied, `SplitLate` :65-82), `restarted` (`flags.restartedAt` a number), `reloaded`, `sessionFromList`, `sharedSession`, `died`, then status `incomplete` / `lost`. Flags inform and never void a run: a flagged complete run still holds the all-runs board. The clean board is `Compute(runs, { cleanOnly = true })`. The late-cast list is applied at read time and is per profile, so an edit or a profile switch re-scores every run.
- **CT seam:** CT has no clean-only board (header :4-5: "no clean-only board"). The plan's `NS.Bests.CleanFor(record)` answers this. **Owner: A3**, with the flag judge in B1's `modules/RaceScoring.lua`.
- **Differs:**
  - DR's `Scoring.Flags` reads `run.flags`, `run.status` and `run.race.baseline`. In CT these are `record.race.flags`, `record.race.status` and (see #8) the baseline or a netted marker. RaceScoring must take the race part or the record.
  - Until B1 lands, A3 either needs a minimal flag test (any `race.flags` set, or a `lateCasts` entry not on the ignore list) or must order itself after B1. **The plan puts A3 (M1) before B1 (M2) and LateIgnore arrives in B1.** CleanFor needs a placeholder or a guarded `NS.RaceScoring and ...` call, and the late-ignore part of the clean test lands in B1.
- **DR tests:** `test_bests.lua:76` "cleanOnly excludes flagged", `:133` "a run flagged only by an ignored spell joins the clean board, and leaves it on Unignore"; `test_scoring.lua:57,93,115,131`; `test_late_ignore.lua:249,266`.

### #4 The cache and its invalidation
- **DR:** `Bests.lua:19` `cache = {}`, keyed `[true|false]` by cleanOnly. `Bests.Board(opts)` (:82-92) builds lazily and routes to `ResultsSource.Board(opts)` while the sample history is on (`Source.IsMock()`). `Bests.Invalidate()` (:95-97) clears both. The bus receiver (:164-176) invalidates on `RUN_SAVED` (and prunes, see #7), on `RUNS_CHANGED`, and on `SETTINGS_CHANGED` when `path == NS.LateIgnore.PATH`, `NS.DummyList.PATH` or `"profile"`.
- **CT seam:** `Bests.lua:21` holds a single `board`. `Board()` (:80-83) has no mock routing; `Results_Source.IsBest` / `BestFor` (:119-143) do that. The receiver (:141-145) handles `FIGHT_SAVED` and `FIGHTS_CHANGED` only. `Recorder.Save` and `Delete` also call `Bests.Invalidate` directly (`Recorder.lua:96-98`), as does `Hud.lua:236`. **Owner: A3** for the clean cache. The `SETTINGS_CHANGED` paths depend on A2 (the dummy list's path) and B1 (`LateIgnore.PATH`).
- **Differs:** CT needs a second cached board (clean), or a cache keyed like DR's. It also needs the `SETTINGS_CHANGED` receiver for the dummy-list path, the late-ignore path and `"profile"`. Without it, a dummy-list edit leaves stale race boards (see #1). The mock routing stays in CT's `Results_Source`, so `Source.IsBest` / `BestFor` get race-aware keys through `Bests.Key` and need a clean variant only if D1 shows clean bests on samples.
- **DR tests:** `test_bests.lua:124` "the cache is invalidated by RUN_SAVED and keeps cleanOnly apart"; `test_late_ignore.lua:249,266`.

### #5 `Before` and `Delta` (the previous best and the verdict)
- **DR:** `Bests.lua:99-141`.
  - `before(a, b)` compares `date`, then id.
  - `Bests.Before(run, runs?) -> prev|nil`: the best on `run`'s board among runs that count and were raced *before* it. `run` itself need not count. `runs` defaults to `history()`: `ResultsSource.All()` while mock, else `Recorder.All()`.
  - `Bests.Delta(run, runs?) -> pct|nil, isNewBest, prev|nil`. If `run` does not count, it answers `nil, false, nil`. With no `prev`, it answers `nil, true, nil` (the first complete run on its board is a new best). With `prev.dps <= 0`, it answers `nil, mine > theirs, prev`. Otherwise it answers `(mine / theirs - 1) * 100, mine > theirs, prev`.
  - Callers: `Hud.lua:303` (result card), `BestToast.lua:341`, `Share.lua:279`, `MockRuns.lua:599-601`, `Hud_Chart.lua:418,453` (Before as the result chart's best line).
- **CT seam:** CT has no `Before` or `Delta`. CT's over card uses `IsBest` + `For(record, true)` (`Hud.lua:235-240`, `judge`). **Owner: A3** adds `Bests.Before` and `Bests.Delta` over CT records. C2 consumes them (`NS.Bests.Before/Delta`, plan :314). C1 (the result card) and E1 (Share, mock samples) also consume them.
- **Differs:**
  - Order by CT `t`, not `date`.
  - Read DPS through `RaceRecord.Dps`.
  - The default list is `Recorder.List()` (CT's array; CT's `Recorder.All()` is an *iterator*, `Recorder.lua:137-143`), or `ResultsSource.All()` while `Source.IsMock()`.
  - Spec §8's fight toast fires "never [on] a board's first fight", so C2 must test `prev ~= nil` and not rely on `isNewBest` alone. A3 should make `Delta` work for fight records too, since C2 uses it for fight bests.
- **DR tests:** `test_bests.lua:145` "Delta reports new best and percentage vs previous best", `:163` "Delta ignores later runs, other boards and runs that never count", `:178` "Delta defaults its run list to the store".

### #6 `HoldingIDs`: what the purge keeps
- **DR:** `Bests.lua:145-151`, `Bests.HoldingIDs(runs) -> { [id] = true }`: the union of the holders on the all-runs board and the clean-only board.
- **CT seam:** `Bests.lua:133-137` `HoldingIDs(records)` = holders of `Compute(records)`. It is consumed by `Retention.lua:114`, gated by `history.keepBests` (default `true`, `defaults/Profile.lua:193`). **Owner: A3.**
- **Differs:** CT must union fight-board holders, race all-runs holders and race clean holders. Because `Compute` is keyed through `Bests.Key`, race boards arrive with the race-aware key. Only the clean union needs adding.
- **DR tests:** `test_bests.lua:187` "HoldingIDs names the holders of the all-runs and the clean-only boards". CT: `tests/test_retention.lua:55,81,98`. Add the plan's `retention: a race holding a best survives the purge`.

### #7 Pruning vs CT's purge
- **DR:** pruning runs on every `RUN_SAVED` (`Bests.lua:166-169`, `Bests.PruneToSetting(protect)` reads `global.history.keepDays`, default **90**, 0 = never) and at OnEnable. `Recorder.lua:404-451` `Recorder.Prune(days, protect, now)` removes only `PRUNABLE = { complete, incomplete, lost }` runs older than `days * 86400`. It never removes a holder, `protect` (the run just saved) or `NS.Race.Current()`'s run (`protectedIDs`, :409-415). It never removes a running or stopping run. It has no count cap.
- **CT seam:** `Retention.lua:108-129` `Retention.Purge(now)` runs at login and stand-up (`Sync`), on a daily AceTimer that waits out combat and a fight (`busy()` :143-146, `RETRY` 60 s), and on `/ct purge`. It applies `history.days` (default **7**), then `history.maxFights` (default **500**), protecting holders only while `keepBests` is on. **Owner: A3** (holders only; spec §3.5 adopts CT's rule for races).
- **Differs:**
  - CT never prunes on save, so DR's `protect` and current-run guards have no CT trigger. A just-saved race is the newest record, so neither the age rule nor the cap reaches it.
  - Races count toward the 500 cap.
  - DR's never-prune-running/stopping guard matters only if B2 stores a pending race in `db.global.fights`. If B2 does, `Retention.known` / `byAge` must skip a record whose `race.status` is `running` or `stopping`. **Flag for B2.**
- **DR tests:** `test_bests.lua:199,210,228,240,256,270,290,302`. These are mostly DR-specific; only `:210` "prune keeps best-holding runs" has a CT analogue, as a race case in `test_retention.lua`.

### #8 DR's run record (schema 4) and its statuses
- **DR:** `Recorder.lua:31` `Recorder.RUN_SCHEMA = 4`. `Recorder.NewRun(length)` (:278-298) builds:
  - top level: `id` (`time() .. "-" .. random(1000,9999)`, `ID_ATTEMPTS` 32), `schema`, `status = "armed"`, `addon`, `build`, `date` (arm time, restamped at the start);
  - `race = { length, grace, restartGap, startSource = "meterSession" }`, with the grace and gap frozen from `profile.race` (defaults **1.0** and **6**);
  - `char` (SnapshotPlayer), `target` (SnapshotTarget: `npcID`, `name`, `category`, `level`, `classification`), `where` (`mapID`, `zone`, `subzone`, `instanceType`), `stats`;
  - `flags = { lateCasts = {}, reloaded = false, died = false }`, `spells = {}`, `note = ""`.

  Race adds the following (`Race.lua`):
  - `race.startedAt` (GetTime at the start), `race.sessionID`, `race.armMaxSession`, `race.lastDamage` (s after the start), `race.baseline` (the arm-time read `{ session, damage, spells }`, for a shared session);
  - `result = { damage, dps, meterDps, sessionDuration, tail, combatEnd, endedAt }`;
  - `flags.restartedAt`, `flags.sessionFromList`, `flags.sharedSession`.

  Optional parts: `loadout` (format 2), `casts` and `usage` (format 3), `stats` (format 4). Statuses: `armed` (never stored), `running`, `stopping`, `complete`, `incomplete`, `lost`. `complete` vs `incomplete` is decided by `result.endedAt` (`Race.lua:244`). A lost run is **stored** with `result = nil` (:151-160). Cancel **deletes** the run (:682); there is no `cancelled` status. The score is `Scoring.Dps(damage, run)` (`Scoring.lua:30-41`): `damage / race.length` when complete, else `damage / result.endedAt`, and 0 with no positive divisor.
- **CT seam:** `modules/Recorder.lua:30-36` lists the record. `Build` (:327-350) assembles `raw` and passes it through `plainCopy` (:199-210, `MAX_DEPTH` 8). **Owner: A3** (`race` in `Build` through `NS.RaceRecord.Plain`); B1 owns the writers.
- **Field map, DR run → CT record:**

| DR field | CT field | Notes |
|---|---|---|
| `id` | `id` | same format and same `ID_ATTEMPTS` |
| `schema` | `schema` | `CT_SCHEMA` |
| `status` | **`race.status`** | the record's own `status` stays `"final"` |
| `addon` | `version` | |
| `build` | `build` | |
| `date` | `t` | CT `t` = combat-entry epoch (`startEpoch`); DR's is arm time, restamped at the first hit |
| `race.length` | **`race.length`** | |
| `race.grace`, `race.restartGap` | **`race.grace`, `race.restartGap`** | frozen at arm |
| `target.category` | **`race.kind`** | read time vs frozen: see #1 |
| `result.damage` (netted on a shared session) | **`race.score`** | CT `damage.merged` stays the meter's un-netted total |
| `result.dps` | **`race.dps`** | |
| `result.tail` | **`race.tail`** | |
| `result.combatEnd` | **`race.combatEnd`** | |
| `result.endedAt` | **`race.endedAt`** | |
| `flags.{lateCasts, restartedAt, reloaded, died, sessionFromList, sharedSession}` | **`race.flags.*`** | |
| `result.meterDps` | `meterDps` | DR drops it on a shared session (`net`, Race.lua:221); CT should too for a shared race |
| `result.sessionDuration` | `duration` | CT: the meter's session duration, else its own clock |
| `char` | `who` | CT has `name`, `realm`, `client`, `class`, `level`, `ilvl`, `specID`, `specName`, pet fields; it has no `ilvlOverall` or player `race`, and `char.spec` corresponds to `who.specName` |
| `target.npcID`, `name`, `level` | `identity.targetCreatureID`, `targetName`, `targetLevel` | `classification` is only in the combat-entry snapshot, not stored |
| `where` | `identity` (`instanceType`, `zone`, `subzone`, ...) | no `mapID` in CT |
| `stats` | `stats` | |
| `spells` (`{ id, dmg, dps }`) | `spells` (CastCodec packed) | shared session: DR's spells are netted, CT's come from `final.merged.spells` un-netted (flag for B1) |
| `loadout` | `gearSet` + `loadout` | |
| `casts` | `casts` + `cooldowns` | |
| `usage` | `usage` | |
| `note` | `note` | |
| `race.startSource`, `startedAt`, `sessionID`, `armMaxSession`, `lastDamage`, `baseline` | *(not stored)* | in-memory race state; B2 may need `sessionID`, `armMaxSession`, `startedAt` and `lastDamage` if it persists a pending race |

- **Conflicts:**
  1. `Scoring.Flags`' `sharedText` (Scoring.lua:122-127) words the flag by whether `race.baseline` is a table ("taken off" vs "may include"). Spec §6 does not list `baseline`. Store a boolean, e.g. `race.flags.sharedNetted`, or a `race.netted`, rather than the baseline's spell table. **Flag to the owner or decide in A3/B1.**
  2. The spec lists statuses `running` and `stopping`, but A3's rule only stores `complete` and `incomplete`. CT writes nothing before `FIGHT_ENDED` (`Recorder.lua:17-18`).
  3. The plan's `cancelled` status does not exist in DR; it is a B1 in-memory marker.
  4. DR stores `lost`; spec §3.4 and §4.1 drop the race part and keep a plain fight instead.
- **DR tests:** `test_recorder.lua:144` "NewRun copies grace and restartGap from the profile", `:174` "NewRun uses the shipped defaults (grace 1.0, restart gap 6)", `:182`, `:196`, `:241` "Pending returns running and stopping only", `:255`, `:267` "a run written by a later schema is left alone"; `test_scoring.lua:39` "Dps complete = damage / length", `:48` "Dps incomplete = damage / endedAt".

### #9 CT's save rule: `OnFightEnded` and `Filters.Passes`
- **DR:** every race that resolves is stored (`Recorder.Save` at the start, the capture, the buzzer and the result), whatever its length (as short as 0:10).
- **CT seam:** `Recorder.lua:367-380` `OnFightEnded(fight, final, reason)`:
  1. reason ≠ `"final"` → `skip "lost"`;
  2. `enemiesOf` → `Identity.Resolve` → `durationOf`;
  3. `Filters.Passes(identity, duration)` (`Filters.lua:25-33`: `"short"` under `history.minLength` default 30, or `duration <= 0`; `"filtered"` for bosses-only or a content toggle off);
  4. `hasWho` → `skip "unknown"`;
  5. `Build` → `Save` (fires `FIGHT_SAVED`).

  **Owner: A3.** A1 changes the `minLength` default per client.
- **Differs:**
  - Plan rule: a fight whose `fight.race.status` is `complete` or `incomplete` bypasses `Filters.Passes` but should still pass `hasWho`: a record needs a `who`, and `Bests.CharKey` needs `who.name`.
  - For `lost` or `cancelled`, set `fight.race = nil` before the filters, so the pull takes the plain-dummy path.
  - A race whose `FIGHT_ENDED` reason is not `"final"` (no plain final read) is still skipped `"lost"`. That matches spec §3.4.
  - Ordering: `fight.race` must be final before this receiver runs. CT's bus has no receiver order (`Hud.lua:236` comment), so B1 must use a direct `Race.Finalize(fight)` call from here, or a receiver guaranteed to run first (plan :230-231).
  - `Build`'s `raw` needs `race = NS.RaceRecord.Plain(fight.race)`. `plainCopy` would already drop secrets, but `Plain` also whitelists the spec §6 fields.
- **CT tests:** `tests/test_record.lua:106,147,159,167,365`, plus the plan's `race record:` cases in the new `tests/test_race_record.lua`; `tests/test_filters.lua:65,113`.

### #10 Schema 4 and the migration runner
- **DR:** `global.schema` = 4. Each format step (1→2, 2→3, 4→5) only raises `global.schema`; no stored run is rewritten (DR `docs/schema.md:121-124,165-168`). A reader skips a run with a higher `schema` (`Recorder.lua:326-328`, `known`).
- **CT seam:** `Recorder.lua:46` `Recorder.CT_SCHEMA = 3`, with `Recorder.Known` at :74-77. `core/Database.lua:6` `NS.SCHEMA_VERSION = 2` is the **settings** stamp, distinct from `CT_SCHEMA` (:4-5). `STEPS` has `to = 1` (no-op) and `to = 2` (wipes `fights`, `fightOrder`, `loadouts`, `gearSets`). No step accompanied `CT_SCHEMA` 2→3. **Owner: A3.**
- **Differs / conflict:**
  - The plan says "`core/Database.lua` (3 → 4: no wipe...)". The runner stamp is at **2**, not 3, and CT_SCHEMA bumps have never needed a step: `Known` accepts every `schema <= CT_SCHEMA`, and an older record simply has no `race`. A3 either leaves `Database.lua` alone, or adds a no-op `{ to = 3 }` step that bumps `SCHEMA_VERSION` to 3. The no-op only buys a stamp.
  - Bump `CT_SCHEMA` to 4 and update the comment at :44-45 and the THE RECORD block at :30-36.
  - Two existing tests pin the current values and must change in the same commit: `tests/test_load.lua:103-106` ("the settings stamp is 2 and the fight record's format is 2" asserts `SCHEMA_VERSION == 2` and `CT_SCHEMA == 3`) and `tests/test_record.lua:115` (`CT_SCHEMA == 3`).
  - The plan's test `database: schema 3 records load unchanged under 4` belongs beside `test_load.lua:108`, which pins the 1→2 wipe being a one-time step.
  - `Diagnostics.lua:33` prints `fightFormat`; it needs no change.
- **DR tests:** `test_recorder.lua:267`; `test_schema.lua:152` "a migration runs once and stamps the stored version".

## results

Scope: DR `modules/Results.lua`, `Results_Runs.lua`, `Results_Table.lua`, `Results_Detail.lua` (race parts only), `Results_Source.lua`, `Results_Insights.lua`, `Results_InsightsData.lua` at f8078c7, compared with CT `modules/Results*.lua` and `modules/Filters.lua` on `feat/2026-11-11-race-mode`. Owners: **D1** (Races filter, race rows, race detail) and **D2** (Insights over all fights). Unless an item says otherwise, "DR x:n" means `../DpsRace/modules/x:n` and "CT x:n" means `modules/x:n`.

### #1 The record-shape remap (read this first: every item below depends on it)
- **DR:** every Results file reads a *run*: `run.status` (`complete|incomplete|lost`), `run.result.{damage,dps,meterDps,tail,endedAt,combatEnd}`, `run.flags.{lateCasts,restartedAt,reloaded,died,sessionFromList,sharedSession}`, `run.race.{length,grace}`, `run.char.{name,realm,class,specID,spec,ilvl}`, `run.target` (`Dummies.CategoryOf(run.target)`), `run.date`, `run.where`, `run.addon`.
- **CT (spec §6, plan A3):** a race is one fight record with `status = "final"`, `t`, `who.{name,realm,class,specID,specName,ilvl}`, `identity.{targetCreatureID,content="dummy",...}`, `damage.merged`, `dps`, `duration`, `version`. The race-only data lives in `record.race = { length, kind, status, flags{...}, score, dps, tail, endedAt, combatEnd, grace, restartGap }`.
- **The mapping every port applies:**

  | DR | CT |
  |---|---|
  | `run.status` | `record.race.status` |
  | `run.flags` | `record.race.flags` |
  | `run.result.dps` | `RaceRecord.Dps(record)` |
  | `run.result.damage` | `record.race.score` |
  | `run.result.tail/endedAt/combatEnd` | `record.race.*` |
  | `run.race.grace` | `record.race.grace` |
  | `Dummies.CategoryOf(run.target)` | `record.race.kind` |
  | `run.date` | `record.t` |
  | `run.char` | `record.who` |
  | `run.char.spec` | `who.specName` |
  | `Runs.CharKey` ("Name-Realm") | `ResultsFights.CharKey` (`Bests.CharKey`: "name\|realm\|client") |
- **Conflict:** DR `Scoring.Flags(run, nameOf, set)` (DR `Scoring.lua:134`) reads `run.flags` and `run.status`. The CT port (`RaceScoring`, B1) must read `record.race.flags` and `record.race.status`, otherwise every Results/Insights flag helper below silently reads nothing.
- **`lost`:** a lost race is never saved in CT (spec §3.4, §4.1). DR's `lost` branches (Status tag `lost`/`ph:ghost`, `Runs.RESOLVED.lost`, "A lost run has no DPS") are dead code in CT. `ph:ghost` stays declared in CLAUDE.md.

### #2 The tab strip (Runs / Insights)
- **DR Results.lua:48** `Results.TABS = { "runs", "insights" }`. Line 57: `tab` is session-only, never saved. buildTab:137-165 builds lazily; the Insights hooks are `{ open(r) -> Results.ShowRun(r.id), menu(r,row), count(text) }`.
- **tabButton 167-185:** button `Style.TAB_W` x `TAB_H` (`Style.TAB_STRIP_H` = 26), at `6 + (i-1)*Style.TAB_PITCH` under `Style.Band`, label `Style.FONT.TAB`, a 2 px `tab.onLine` underline. It is placed in buildChrome 213-220, with a divider rule `TAB_H` under the band.
- **Layout:** bodySize:355 subtracts `TAB_H`. `layout`:385 and `resize` branch on `tab == "runs"` (Insights: `ui.detail.frame:Hide(); pane:Layout(w,h)`). paintTabs:423, footer:433 (`runsCount`/`insightsCount`), renderTab:448.
- **Public calls:** `ShowTab(name)`:705 (`NS.CloseMenu()` on a switch), `ShowRun(id)`:715 (forces "runs"), `Results.Tab()`:733. `Diagnose` returns `{tab, selected, rows, mode}`.
- **CT seam:** `Results.lua` has **no tab strip** (header comment CT Results.lua:6: "one list, so no tab strip").
  - buildChrome:156 has the `Style.Header` controls `{close, viewToggle, settings}`.
  - `ui.body` is anchored at ensureWindow:254 directly under `Style.Band(f)` (offset -1).
  - bodySize:290, layout:303, resize:331, render:428, `ShowFight(id)`:720, `OnSourceChanged`:910 (`ui.list:SampleView`).
  - `Style.TAB_W, TAB_PITCH = 90, 94` and `TAB_STRIP_H = 26` exist (CT Style.lua:215-216), as do the `tab.onText`/`tab.onLine` tokens (core/SkinSetup.lua:117-118). **`Style.FONT.TAB` does not exist in CT** (DR Style.lua:51 `TAB = "GameFontNormal"`).
- **Owner D2.** The plan says "through the existing tab strip", but none exists. D2 builds the strip in Results.lua (984 lines; about 70 lines of seam fits under the cap), adds `FONT.TAB`, and moves `ui.body` down by `TAB_H`.
- **Tests that pin the body:** `tests/test_results_body.lua`-style body checks, CT test_results_table.lua:429-432 and test_results_detail.lua:388-390 (min widths). DR suites: test_results_window.lua ("the Insights tab is built on first show..."), test_results_body.lua, test_header_band.lua.

### #3 Slash verbs `/ct results races` and `/ct results insights`
- **DR:** `ShowTab("insights")` (Results.lua:705). DR has no "races" verb, because every DR row is a race.
- **CT seam:** CT Results.lua:765 `VERBS` (`""`, `toggle`, `show`, `hide`) and `OnVerb`:773, whose usage line is `L["Usage: /ct results, or /ct results show, hide or toggle"]`. settings/Slash.lua:51 only routes `results` to `NS.Results.OnVerb` (Slash.lua:237-241).
- **Conflict:** the plan puts `/ct results races` in `settings/Slash.lua`. The verb table actually lives in Results.lua `VERBS`. Add `races` (D1: open the list with the kind filter set to `"races"`, Retail only via `Compat.ForClient({"retail"})`) and `insights` (D2: both clients). Update the usage line.

### #4 Filters: DR's set and CT's seams
- **DR Results_Runs.lua:24-31** `Runs.DEFAULTS = { char="current", spec="all", category="all", length="all", date="all", hideFlagged=false, includeIncomplete=true, onlyBest=false, group="full" }`.
  - `DROPDOWNS`:36-39: char 110, spec 96, category 96, length 88, date 100, group 164.
  - `CHECKS`:40-44: "Hide flagged" 100, "Include incomplete" 128, "Only best" 84.
  - `PASS`:113-123, run in order:
    1. char
    2. spec
    3. category (`Dummies.CategoryOf(run.target) == f.category`)
    4. length (`run.race.length == f.length`)
    5. date (`run.date >= Since`)
    6. `includeIncomplete or status=="complete"`
    7. `not (hideFlagged and Runs.IsFlagged(run))`
    8. `not onlyBest or Runs.HoldsBest(run)`
  - `Runs.Filter`:130 first gates on `Runs.RESOLVED[run.status]` (23).
  - `Runs.IsFlagged`:67 is any `Scoring.Flags` key other than `incomplete`/`lost`.
  - `Since`:75 takes `"today"|"7d"|"30d"|"all"`.
- **CT seam:** CT Results_Fights.lua.
  - `Fights.FILTERS`:46 `{character, spec, content, board, difficulty, days, bossesOnly}`; `VIEW_KEYS`:48.
  - `DROPDOWN_SPECS`:54-58 already accept a `clients` field (filtered by `Fights.Dropdowns()`:69).
  - `PASS`:174 is a **local** keyed table. `passes`:192 hard-gates `record.status ~= "final"`. `OPTION_LISTS`:311 is local. `SetFilter`:999 refuses any key absent from `Fights.StockView()`.
  - The bar has one checkbox, `view.bossesOnly`, at buildBar:736. `BarPlan`:901 places only that box on row 2.
  - The defaults live at `defaults/Profile.lua:210-212` `results.view` (`character="current", spec, content, board, difficulty, days=7, bossesOnly=false, group="datechar", sort="date", desc=true`).
- **What D1 adds:**
  - `kind` (`"all"|"fights"|"races"`), Retail-only. A Forever record with a `race` part passes as a fight (Review focus 3).
  - Under `kind=="races"`: `length`, `dummyKind`, `hideFlagged`, `includeIncomplete` (DR default true), `onlyBest`.
  - Map DR `date` onto CT's `days` (0/1/7/30). Do not port DR's date keys.
- **Conflicts:**
  1. The plan names the default `views.fights.kind = "all"`, but CT's view is `results.view` (Profile.lua:211). Add `kind`, `length`, `dummyKind`, `hideFlagged`, `includeIncomplete`, `onlyBest` there and to `VIEW_KEYS`/`FILTERS`.
  2. `PASS`, `OPTION_LISTS`, `GROUP_SPECS` and the bar's checkbox list are local to Results_Fights.lua (1009 lines). Results_Races.lua needs a registration seam, for example `Fights.Extend({ filters, options, groups, checks })`, rather than growing the file.
  3. `bossesOnly` plus Races empties the list, because dummy records are never `isBoss`. Decide whether it is ignored for race rows or hidden under Races.
  4. "Appear when Races is on" means a dynamic bar. `Results.MIN_WIDTH` (CT Results.lua:44-45) is computed **at file scope** from `Fights.BarMinWidth()` and `Tbl.MinWidth(Fights.Columns())`. Today's minimum is 872 px of dropdowns. Adding DR's length (88) and category (96) plus a kind dropdown (about 90) adds about 290 px, so the minimum must cover the widest bar. The suites hold it: CT test_results_table.lua:429-432.
- **DR pins:** test_results.lua ("filters: character, spec, category, length, date range, hide flagged, include incomplete"; "Only best keeps the runs holding their board's best"), test_results_fit.lua.

### #5 Faceted option lists for the race filters
- **DR Results_Runs.lua:**
  - `categoryOptions`:181 lists the categories present, in `NS.Dummies.CATEGORIES` order, labeled `Dummies.Label`.
  - `lengthOptions`:190 lists the distinct `run.race.length` values, ascending, labeled `Format.Length`.
  - `OptionLists(runs, key)`:212 and `WithAll(list, label, current)`:222.
  - `Options`:361 heads: "All targets", "Any length", "All characters"/"Current character", "All specs"/"Current spec".
  - DR's Runs options are **not** faceted (they read all resolved runs). Only Insights facets (#21).
- **CT seam:** `Fights.Options`:352 is faceted (`Filter(..., skip=key)`). Race lists must use the same `facet(key)`.
- **Owner D1.** Label "All dummy kinds" or similar, in CT's vocabulary. Never "run".

### #6 Group-by modes
- **DR Results_Runs.lua:**
  - `GROUPS`:341-350 and `GROUP_ORDER`:351: `none, full, char, classSpec, target, length, targetLength, specTargetLength`.
  - Labels:352-356: "Group: Full / Character / Class & spec / Target / Time / Target + time / Spec + target + time".
  - Keys and ranks:
    - `timeGroup`:291 keys `"length:"..len`, label `"Time: <chip>"`, rank = length or `NO_LENGTH_RANK` (1e6, line 279).
    - `targetLengthGroup`:297 keys `category.."|"..len`, rank `CATEGORY_RANK*(1e6+1)+len`.
    - `specTargetLengthGroup`:308 keys `class|specID|category|len`, rank `"%s|%s|%03d|%07d"`.
    - `fullGroup`:324.
  - Header values are inline-colored (`Runs.Colored`:245): class color, `Tbl.CATEGORY_COLORS`, `Tbl.LengthColor`.
- **CT seam:** CT Results_Fights.lua.
  - `GROUP_SPECS`:331 `{datechar, date, board, character, spec, content, none}`, each with an optional `clients`.
  - `GROUP_LABELS`:342, `Fights.GROUPS`:433 (`{ of, delta? }`), `GroupSpec(mode)`:443.
  - CT ranks sort ascending with strings. `Tbl.GroupKey`:830 uses only the key; the `delta` override lives at CT Results_Table.lua:861-863.
- **Owner D1.** Add `length`, `targetLength` and `specTargetLength` (spec §7 names these three) as Retail-only `GROUP_SPECS` entries. DR's `full`, `classSpec` and `target` are not asked for. For a non-race row: `lengthOf` returns nil, so it gets a dash and sorts last (DR:279-288), and `category` falls to `"other"` (`CATEGORY_RANK` 99).
- **Conflict:** under CT's date groupings the Delta measures by `boardGroup` (`r.boardKey`). A race record needs its race board (`Bests.RaceKey`, A3) there, otherwise races and the dummy's plain fights share a delta group.
- **DR pins:** test_results_group.lua ("Group by time, and by target type and time, shortest first"; "Group by spec + target + time, one group per board"; "Group by Full").

### #7 Columns: what a race row draws
- **DR Results_Runs.lua `Columns(view)`:716-788**, column by column:
  - `date` 80.
  - `icons` 40.
  - `char`: flex, min 60.
  - `ilvl` 40.
  - `target`: badge, `TARGET_W` 92, `Tbl.Badge`.
  - `time`: badge with `trail=true`, `TIME_W` 84, sort `Format.RunSeconds`, text `Runs.TimeCell`:704 (`Tbl.LengthChip`, then `Tbl.TimeTail`).
  - `damage` 60.
  - `dps` 62: `sortDps`:400 ranks only complete runs; `dpsText`:387 shows an incomplete run's DPS too.
  - `delta` 56.
  - `status`: badge, `STATUS_W` 92.
  - `used`: `USED_W` 70.
  - `note`: `NOTE_W` 80, `NOTE_CHARS` 10.
- **CT seam:** CT Results_Fights.lua `Columns`:668-722 (`date, clsSpec, character, ilvl, target (flex, min 150), content (badge 90), len (44, record.duration), damage (damage.merged), dps (record.dps), delta 64, used, note`). Cell tips are CT Results_Tips.lua `CELL.len`:101 and `CELL.dps`:116.
- **What D1 does without a new column** (the column set is fixed at `Tbl.New`, and `Results.MIN_WIDTH` is computed once at file scope):
  - `len`: for a race, the length chip in `LENGTH_COLORS` plus the tail trail (#13).
  - `damage`: `race.score`.
  - `dps` (`dpsOf`:455): `RaceRecord.Dps`.
  - `content`: "Dummy" stays, or the chip becomes the dummy kind.
  - The flags/Status tag: see #8.
- **Conflict:** CT deliberately dropped the Status column ("no Status column: the best is only what a fight is compared against", owner 2026-11-10; CT Results_Fights.lua:6-8). Spec §7 asks for "its flags (DPS Race's Status badge)" on race rows. D1 must pick one of three: a Status column shown on every row (widens `MIN_WIDTH`, conflicts with the v0.2 owner call), a badge inside an existing cell, or a column only in the Races view (needs the table rebuilt per kind). **Raise it with the owner.**
- **DR pins:** test_results.lua ("runs list columns: ..."; "the Status column tags each run; the DPS column shows every run's DPS"; "race lengths take muted ROYGBIV colors"; "the Time column takes the length color; the tail stays gray"), test_results_badges.lua ("the Time cell boxes the length in its color; the tail or the end of combat follows"; "a chip never runs past its column").

### #8 Status tags, Only best and the board a best holds
- **DR Results_Runs.lua `STATUS`:414-421**, each with an icon from the declared set:

  | Tag | Color | Icon |
  |---|---|---|
  | best "Spec best" | `C.blue` | `ph:trophy` |
  | complete "Complete" | `C.green` | `ph:check` |
  | flagged "Flagged" | `C.red` | `ph:flag` |
  | incomplete "Incomplete" | `C.orange` | `ph:x` |
  | died "Died" | `C.pink` | `ph:skull` |
  | lost "Lost" | `C.slate` | `ph:ghost` |

  - `STATUS_ORDER`:422 runs best=1 through lost=6.
  - `Runs.Status(run)`:442 picks: lost, else incomplete (`died` when `flags.died`), else best when `HoldsBest`, else flagged when `IsFlagged`, else complete. Best wins over Flagged.
  - `HoldsBest`:425 is `ResultsSource.Board()[Bests.Key(run)].id == run.id`. That is the **all-runs** board, where flagged runs count.
  - `StatusBoard`:465 and `STATUS_ABOUT`:625-632. `StatusTip`:637 appends `Tbl.FlagTexts` in red and `Scoring.IgnoredText` dimmed.
- **CT seam:** `Source.IsBest(record)` (CT Results_Source.lua:119) and `Bests.IsBest`. A3 makes it answer race boards. The CT detail already has a "Personal best" trophy chip (CT Results_Detail.lua:315-327, `w.best`).
- **Conflict:** DR's boards are `specID|category|length` **across characters** (DR Bests.lua:32). CT race boards are character + spec + kind + length (spec §5), so "Spec best" becomes "Personal best", as CT's own wording has it.
- **Only best (D1):** `RaceRecord.IsRace(r) and Source.IsBest(r)`. For fight rows: either all pass or the filter shows only under Races (it lives in the race-only group of spec §7).
- **DR pins:** test_results.lua ("Status is Spec best, Flagged or Complete for a complete run, each with its icon; there is no Max tag"; "Only best keeps ..."), test_results_badges.lua ("Spec best and Max are the box alone; their board is in the tooltip").

### #9 Delta column and leaders (the race-DPS seam)
- **DR Results_Runs.lua:**
  - `runDps`:433 is nil when lost.
  - `MaxDps`:487 and `Leaders`:539 count **complete runs only**. `leads`:528 compares DPS, then the earlier date, then the id.
  - `Delta(run, top)`:501 compares an incomplete run as well, shown muted (`deltaText`:511: `C.dim` when not complete).
  - `DeltaTip`:609 adds "An incomplete run is compared, but never sets the max."
- **CT seam:** CT Results_Fights.lua.
  - `dpsOf`:455 reads `record.dps`. It feeds `leads`:462, `Leaders`:472, `Context`:487, `Delta`:512, `DeltaText`:524, `DeltaTip`:535 and the `dps`/`damage` columns.
  - CT Results_Detail.lua `DeltaBox`:147 reads `tonumber(ctx.second.dps)` directly.
- **Owner D1.** Every one of these must go through `RaceRecord.Dps` (spec §7: a race contributes its race DPS). Also decide whether an incomplete race may lead a group; DR: never.
- **Mixed boards:** spec §7 says mixed boards compare by percent of each board's best. That is an Insights rule (#22); the table's Delta stays raw DPS within a group.
- **DR pins:** test_results_delta.lua ("Runs.Leaders breaks a DPS tie on the earlier run, then the id"; "the detail's Delta box follows the Runs view's grouping and filters").

### #10 Saved views and sample views
- **DR Runs** (Results_Runs.lua:866-959) saves at `profile.views.runs` as `{filters, sortKey, sortDesc}`.
  - `STOCK_SORT {date, desc}` and `RENAMED_SORT {vsMax="delta"}`.
  - `SAMPLE_VIEW { filters = { char="all", spec="all" } }`:922.
  - Save and Reset refuse with "Not saved: the Results window is showing sample runs."
- **CT** already has all of this (CT Results_Fights.lua:791-871 at `results.view`, `SAMPLE_VIEW` 827). D1 adds only the new keys to the defaults, so `ApplyView`'s `full()` fills them.
- **Insights:** DR keeps its view at `profile.views.insights` (#20). D2 needs a new CT home, for example `results.insightsView` in defaults/Profile.lua (a named non-setting state: docs/schema.md).

### #11 Late-cast ignore on rows
- **DR Results.lua `RowMenu`:786-806** adds `NS.LateIgnore.FillMenu(root:CreateButton(L["Ignore for late casts"]), r)` when `not Source.IsMock() and NS.LateIgnore.Offers(r)`.
- **LateIgnore API** (DR LateIgnore.lua): `Offers(run)`:300, `FillMenu(root, run)`:307, `Menu(run, owner)`:321, `MenuEntries`:283, `Set()`:110, `IsIgnored(id, set)`:118, `PATH`.
- **CT seam:** CT Results.lua `RowMenu`:809-830 (Add/Edit Note, Share, Compare With This Fight, Delete). Owner D1, through Results_RaceDetail.lua. Guard it with `RaceRecord.IsRace` and Retail.
- **DR pin:** test_late_ignore_ui.lua (the row menu offers Ignore for late casts only when the run has one; none on the sample history).

### #12 Redraw on ignore-list and dummy-list edits
- **DR Results.lua:900-914:** a `SETTINGS_CHANGED` on `NS.LateIgnore.PATH`, `NS.DummyList.PATH` or `"profile"` calls `NS.ResultsSource.Invalidate()` and then `onStoreChanged()`. It re-scores flags, Hide flagged, the clean board and the badges.
- **CT seam:** CT Results.lua `onSettings`:955-967, plus the bus at the file's foot. Add the two paths: `LateIgnore.PATH` (B1) and the A2 dummy-list path (`NS.Dummies` custom list). Owner D1.

### #13 Results_Table race helpers
- **DR Results_Table.lua:**
  - `LENGTH_COLORS`:67-73: 30 `{0.86,0.52,0.52}`, 60 `{0.88,0.67,0.46}`, 120 `{0.86,0.81,0.52}`, 180 `{0.56,0.80,0.58}`, 300 `{0.58,0.66,0.92}`. `LENGTH_NEUTRAL`:74 `{0.76,0.76,0.80}`.
  - `CATEGORY_COLORS`:77-84: single `{0.56,0.72,1}`, cleave `{1,0.72,0.29}`, dungeoneer `{1,0.45,0.45}`, boss `{0.75,0.55,1}`, pvp `{0.36,0.86,0.46}`, other `{0.62,0.62,0.68}`.
  - `LengthColor(s)`:145, `Badge(target)`:159.
  - `FlagTexts(run)`:170 drops `incomplete` and `lost`.
  - `Chip(parent, scale)`:376 and `SetChip(chip, s, color, maxW)`:390, with `CHIP_GAP` 4.
  - `LengthChip(len)`:408.
  - `TimeTail(run)`:416: `"at %s"` when incomplete; `"+%.1fs"` when tail >= 0.05.
  - `Bind.badge`:578 takes `col.text -> s, color, icon, trail, chips`, drawn by `bindChips`:563 and `cell.trail`.
- **CT seam:** CT Results_Table.lua (1197 lines, near the cap). `Cells.badge`:316 has only `box`, `fs` and `icon`. `Bind.badge`:442 reads `s, color, icon`: **no trail, no chips**. `CONTENT_COLORS`:71.
- **Owner D1.** Put the tables and helpers in Results_Races.lua. A trail needs a small seam in `Cells.badge`/`Bind.badge`, or render the tail as the cell's plain text after the chip. The `Tbl.Chip`/`SetChip` box is needed by the detail header (#17).

### #14 Detail: the Timing section (race only)
- **DR Results_Detail.lua constants (68-73):** `STRIP_GAP` 3, `STRIP_RATIO` 1.2, `SPAN_STEP` 6. The section key is `"timing"` in `SECTIONS`:74. `STRIP_H` 34, `LINE_H` 14, `LINE_W` 2, `LINE_INSET` 4.
- **Colors:** `RACE {0.53,0.53,0.93}`, `CYAN {0.3,0.85,1}` (combat end), `VIOLET {0.78,0.5,1}` (restart), `IGNORED {0.55,0.55,0.55}`, late = `C.red`, tail = `C.amber` at 0.45, grace = `C.green` at 0.8.
- **Pure functions:**
  - `Detail.Timing(run)`:189 returns `{length, raceFill, endInRace, span, grace, tail, combatEnd, restart, late[], lateAt[], lateIgnored[]}`.
    - An incomplete run gets `raceFill = endedAt/length` and `span = 12`.
    - Otherwise `afterBuzzer`:165 marks `{grace, tail, combatEnd, restartedAt, each lateCast.t}`, and `spanFor`:153 sets span = `max(12, 6*ceil(max/6))`.
    - `lateIgnored` comes from `LateIgnore.IsIgnored(cast.spellID, LateIgnore.Set())`.
  - `Detail.Place(model, width)`:209 sets `raceW = floor((w-3)*1.2/2.2)` and `postX = raceW+3`.
- **Drawing:** buildTiming:514 makes two segments (`Tbl.Panel(strip, {bg="dr.strip.seg", border="dr.strip.segEdge"}, "inset")`) and a marks frame at level +2. layoutStripMarks:1026, tailText:1049 ("Damage stopped %ss after the buzzer · combat ended %ss" / "Combat ended at %s, before the buzzer."), layoutLegend:1063, layoutTiming:1082 (axis "0:00 — race %s — buzzer", "+%ds" at 0, span/2 and span).
- **Legend:** `Detail.LEGEND`:358 is Race, Tail (damage still landing), Grace, Late cast, Combat ended, Restart. `LEGEND_ROWS`:361 is `{{1,2},{3,4,5,6}}`. The tips are DR Results_Tips.lua `LEGEND`:393 and `DETAIL.strip`:310.
- **CT seam:** CT Results_Detail.lua.
  - `SECTIONS`:67 `{chart, spells, loadout, usage, targets, note}`.
  - `Layout`:681-704 runs header, chart, spells, Loadout, Usage, `NS.ResultsTargets.Layout`, note.
  - `Show`:542 calls `ResultsTargets.Fill`.
  - The model to copy is `Results_Targets.lua` (`Build(p,c)`:83, `Fill(p)`:104, `Layout(p, y, cw)`:130, wired at Detail.Build:459).
- **Owner D1.** Create `Results_RaceDetail.lua` with the same three-function shape. Add `"timing"` and `"flags"` to `Detail.SECTIONS`; folds are kept in `results.collapsedSections`. Insert the Layout calls (DR order: timing after the chart, flags just before the note). For a non-race, Fill must give no heading and no arrow, as Targets does.
- **Missing tokens:** CT lacks `ct.strip.seg`/`ct.strip.segEdge` (core/SkinSetup.lua; DR SkinSetup.lua:258-259 `{0.07,0.07,0.1,1}` follows `input.bg`, `{1,1,1,0.08}` follows `input.border`). CT also has no `Tbl.Panel`/`HudStates.Panel`; use `NS.Skin.Card` with tokens, as CT Detail.Build:441 does.
- **DR pins:** test_results_detail.lua ("timing strip positions buzzer, grace, tail, late casts, combat end"; "the timing strip's marks draw above its two segments"; "the timing legend is two rows ..."), test_results_sections.lua.

### #15 Detail: the Flags section (race only)
- **`Detail.FlagLines(run)`:277** returns `{key, main, sub, text, full}` in Scoring order: lateCasts, restarted, reloaded, sessionFromList, sharedSession, died, incomplete, lost.
  - `EXPLAIN`:245-258 says what each flag means; each line ends with "The run still counts toward bests."
  - `lateLine`:231 reads "%s started +%.1fs after the buzzer" and "(grace %.1fs)".
  - `ignoredLine`:260 adds the dim key `lateIgnored` ("%d ignored late casts", "On the late-cast ignore list, so no flag. Right-click to count a spell again."). It goes 2nd after lateCasts, else 1st.
- **Look:** a callout `Tbl.Panel(c, {bg="dr.callout.bg", border="dr.callout.border"})`, built at buildFlags:557. `FLAG_MAIN` is `dr.callout.text` (FONT.SECTION), sub is `C.amber` (FONT.CAPTION), body is FONT.TEXT. `FLAG_PADX/Y` 9/7, `FLAG_GAP` 6, `FLAG_MAIN_H` 18, `FLAG_SUB_H` 12. fillFlags:757, layoutFlags:1159.
- **Right-click:** anywhere on the box, `NS.LateIgnore.Menu(p.run, self)` (wireTips:636-639), never on mock data.
- **CT:** `ct.callout.bg/border/text` already exist (core/SkinSetup.lua:205-207). Owner D1, in Results_RaceDetail.lua.
- **Words:** "run" becomes "race" ("The race still counts toward bests").
- **DR pins:** test_results_detail.lua ("detail flags name late-cast spells and the session matched by list"), test_late_ignore_ui.lua ("the detail's Flags box dims the ignored line and its right-click ignores ...").

### #16 Detail: the Delta box and the New best badge
- **DR:**
  - `Pane:deltaContext`:702 uses `hooks.deltaContext`, falling back to `Runs.BoardContext(run, Source.All())` (Runs:562).
  - `fillDelta`:708 calls `Runs.DeltaBox`:581. The top shows its lead over the runner-up in green, or a dash with no runner-up. A non-top shows its Delta cell.
  - The `w.badge` "New best" (trophy, `BADGE_ICON` 20, `C.blue`, FONT.SECTION, no box: buildHeader:480-493) shows only when `top`.
  - `placeDeltaRow`:943 centers the Delta box and the badge under the three figures.
- **CT:** CT Results_Detail.lua `DeltaBox`:147 uses the label "Leads by" for the leader in place of a badge. `fillDelta`:483, `BoardContext`:133, and 4 KPI boxes in one row (layoutHeader:603). CT also has the "Personal best" chip beside the name (`w.best`, 315).
- **Conflict:** the plan wants "the race delta box with the new-best badge". CT already says the same thing with "Leads by" plus "Personal best". D1 should either reuse CT's (one look, as spec §1 asks) or add the badge for races only. Recommend CT's look, with `ctx.second` read through `RaceRecord.Dps` (#9).
- **DR pin:** test_results_delta.lua (Delta box cases; "Delta + New best sit as a centered pair").

### #17 Detail: header chips and the figure labels
- **DR `Detail.Meta(run)`:306** returns the target line's two chips: `{Tbl.Badge(target)}` (dummy kind) and `{Tbl.LengthChip(length)}`. They are drawn as `w.metaChips` (`Tbl.Chip` x2) before the text `TimeTail · target name`.
- **DR `fillScore`:743:** the DPS label reads "DPS · Incomplete" for an incomplete run. Damage and DPS come from `result`.
- **CT `Detail.Meta`:118** returns 3 plain lines (target, level, difficulty, tier, `Format.Length(record.duration)`, pet). `fillFigures`:498 reads `damage.merged` and `record.dps`.
- **Owner D1.** For a race, show `race.score` and `RaceRecord.Dps`, the Incomplete label, and the length and kind chips (or text). Plain fields stay plain.

### #18 Tooltips (race keys)
- **DR Results_Tips.lua:**
  - `CELL.target`:96, `CELL.time`:107, `CELL.dps`:134.
  - `DETAIL.delta`:289, `DETAIL.badge`:305, `DETAIL.strip`:310.
  - `legendTip`:411 with `LEGEND`:393-400; `LATE_LEGEND` 4 adds `ignoreHint`:403.
  - `DETAIL.flags`:422.
- **CT** Results_Tips.lua (255 lines): `CELL.*` at 42-126, `Tips.Cell`:158, `DETAIL.*` at 201-236, `Tips.Detail(key, record, ctx)`:249. Owner D1: race tips beside or in the new files, wording "race".

### #19 Results_Source: clean board and invalidation
- **DR Results_Source.lua:**
  - `Board(opts)`:125 keeps one cache per `cleanOnly` (`boards[cleanOnly]`), over `Bests.Compute(mock.runs, {cleanOnly})`.
  - `Invalidate()`:119.
  - `ChartView`:153, `LoadoutOf`:137.
- **CT Results_Source.lua:** `IsBest`:119, `BestFor(record, exclude)`:131, and one sample `board` cache. There is **no** `Invalidate`, **no** `cleanOnly` board and **no** `Board()`.
- **Owner D1.** Add `Source.Invalidate()` (called from #12), and give the sample path race boards plus a clean board through `Bests.CleanFor` (A3), so test-mode races judge against the sample history.

### #20 Insights: the shell and the view contract
- **DR Results_Insights.lua:**
  - The view contract matches the Runs tab: `frame, Layout(w,h), Resize(w,h), Refresh, Redraw, Count, SetFilter, SampleView, SaveView/ResetView/ClearView, SelectBoard(key)`.
  - `Build(parent, {open, menu, count})`:714.
  - `DROPDOWNS`:38-41: char 110, spec 96, category 96, length 88, date 100. `CHECKS`:42-45: "Clean only" 84, "Include incomplete" 128. `VIEW_BUTTONS` are 52 px.
  - `BarPlan(width)`:110 uses one row when it fits, else two.
  - Layout constants: `PAD` 8, `CARD_COLS` 4, `CARD_GAP` 8, `WHEEL_STEP` 40, `PROGRESS_DAYS_FROM` 60, `LIST_VALUE_W {late=48, bests=120}`, `BOARD_TAB_W/H` 120/22.
  - Saved at `profile.views.insights` (731-810). `SampleView(true)` applies the stock view.
  - `Insights.lastBoard` is the session-only board tab.
  - Refresh:943 runs `Normalize`, `Filter`, then `Compute`. The count text is "%d runs".
- **CT:** none of this exists. Owner D2: create `Results_Insights.lua`, wire `buildTab` hooks `open -> Results.ShowFight(r.id)` and `menu -> Results.RowMenu`, and give it a home for the saved view (#10).
- **Words:** "Races run" becomes "Fights" (or "Fights and races") under All.
- **DR pins:** test_insights.lua (61 tests: "Save, Clear and Reset keep the view at profile.views.insights"; "test mode fills the tab from the sample history; Save refuses"; "the bar takes two rows in the collapsed window and one in the expanded"; "Resize re-plans the bar ..."; "the wheel scrolls the content"; "a load with no library draws no dropdown").

### #21 Insights data: filters, faceted options, Normalize
- **DR Results_InsightsData.lua:**
  - `DEFAULTS`:30 `{char="all", spec="all", category="all", length="all", date="all", cleanOnly=false, includeIncomplete=false}`. `ORDER`:35.
  - `FACETS`:38-44 read char (`Runs.CharKey`), spec (`run.char.specID`), category, length.
  - `Filter(runs, f, now)`:84 drops lost runs, then calls `Runs.Filter` with `hideFlagged = cleanOnly` and `onlyBest = false`.
  - `Options`:182 makes one pass: each run counts toward the one dropdown it alone fails (`missedSlot`:107). Labels read "Name (n)". The All head carries `choices`. Date options always list all four.
  - `ClosedLabel(options, value)`:206 shows "All characters (4)" for the All head, else the bare name.
  - `Normalize(runs, f, now, keep)`:224 resets a 0-count pick to "all" in bar order, never the one just changed (`keep`).
- **CT seam:** reuse `ResultsFights.CharKey` (CT:93), `Fights.Since(days)`:142 and the option builders. CT's `Fights.Options` is faceted by `Filter(..., skip)`, not by a one-pass count.
- **Owner D2.** The plan wants Insights filters to mirror Results': character, spec, **content**, date (CT days) and Fights/Races/All on Retail. Category (dummy kind), length, Clean only and Include incomplete apply under Races only. Under All, `cleanOnly` drops flagged races only.
- **DR pins:** test_insights_data.lua (13 tests: "Filter defaults wide, keeps lost runs out and maps Clean only to Hide flagged"; "Options lists each facet's values ..., with counts"; "a closed dropdown names its choices ..."; "Normalize sets a 0-run selection to All, never the one just changed, in bar order").

### #22 Insights data: the stats pass
- **DR `Compute(runs)`:591.** `newAcc`:552, `REDUCERS`:300-347 (one call per run), `FINALIZERS`:502-550.
- **Per-run facts** (`factsOf`:279): `complete = status=="complete" and dps`, `dps`, `key = Bests.Key(run)`, `flagged`.
- **Reducers:**
  1. Counts: n, secs (`runSeconds`:256 = length when complete, else `endedAt`), clean, first/last, `days[midnight]`.
  2. Characters (`charEntry`:285 with `byCategory`), categories, specs.
  3. Lengths per character.
  4. Late casts by spell (`Scoring.SplitLate(run, set)`; a cast with no spellID becomes `UNKNOWN`).
  5. Tail buckets (`TAIL_EDGES {5,10,15,20}`).
  6. Complete runs `{run, dps, key}`.
- **Finalizers:**
  - Date order (`earlier`:353), then `onBoard`:368 builds the boards and `newBests {run, dps, key, prev, prevDps, gain%}`. A board's first run is never a new best.
  - `boardFigures`:386: each run's `pct` of its board best, `avg`, `cv`, `avgPct`.
  - `boardTabs`:438: one tab per `category|length` with `specs` (byBest) and `consistency` (n >= `CONSISTENT_MIN` 3, `moreConsistent`). `boardTop` is the most-raced tab.
  - `boardCards`:464: `avgPct`, plus `oneBoard`/`avgDps` when exactly one board.
  - Totals, byChar/byCharTarget, byCharLength, `lateBySpell {counted, ignored}`, `byDay` (gap days included, `MAX_DAYS` 3660), `tail`.
- **Also:** `ScopeKey(run)`:563 (`category|length`), `Scope(runs, key)`:569, `OVERALL = "all"`:589.
- **CT seam (D2):**
  - `key` becomes `Bests.Key(record)` for a fight, or `Bests.RaceKey(record)` for a race (A3). Both include the character, where DR's boards did not.
  - `dps` becomes `RaceRecord.Dps`; `complete` becomes "a fight, or a race with status complete".
  - `runSeconds` becomes `record.duration` for a fight.
  - Mixed boards compare by `pct` (already DR's rule, spec §7).
- **Conflict:** DR's board tabs group by `category|length` and compare **specs** (Spec Comparison) across characters. CT boards are per character, so a "spec × board" row would be one character's spec. D2 must define the tab key over CT records: races `kind|length`; fights `boardKey` (encounter + difficulty + tier).
- **DR pins:** test_insights_data.lua ("Compute on no runs returns zero cards and empty sections"; "Compute's cards over the owner-shaped fixture"; "boards and progression are board-relative"; "board tabs, one per target x length pair, in the catalog's order"; "new bests beat an earlier best on their board, in date order"; "counts by character, target, length and day, gap days included"; "buckets the damage tail, the 155 s outlier in 20+"; "lists late casts by spell, ignored apart, a sealed one as Unknown").

### #23 Insights: the ten cards (DR Results_Insights.lua `CARDS`:176-187, `CARD_FILL`:205-254, `CardGrid(defs, cols)`:273)
Colors: `GOOD_SHARE` 0.9 is green, `POOR_SHARE` 0.7 is red (`shareColor`:193). Four cards a row; a wide card spans 2; a short last row is shared out (`stretchLastRow`:256).

| key | caption | reads | class |
|---|---|---|---|
| runs | Races run | `totals.runs` | GENERAL (needs a new caption under All/Fights) |
| time | Time raced | `totals.timeRaced` (length or endedAt) | GENERAL (fights: `duration`; caption "Time in combat") |
| avg | Avg % of board best (Avg DPS on one board) | `totals.avgPct` / `avgDps`, `oneBoard` | GENERAL |
| clean | Clean runs | `totals.clean / runs` (Scoring flags) | **RACE-ONLY in meaning**: a fight has no flags, so it would read 100%. The plan's "ten cards run on all fights" needs a ruling: hide it under Fights, or count races only |
| newBests | New bests set | `totals.newBests` | GENERAL |
| chars | Characters | `totals.chars` | GENERAL |
| specs | Specs | `totals.specs` | GENERAL |
| activeDays | Active days | `totals.activeDays` | GENERAL |
| best (wide) | Best DPS | `totals.best {run, dps, key}`, its board text (`runBoard`:135 = spec · category · length) | GENERAL (fights need `Fights.BoardLabel`) |
| span (wide) | Date range | `totals.first/last` | GENERAL |

DR pins: test_insights.lua ("the cards state the ten figures, each hover naming its value"; "a card's figure is gold, and colored where it means something"; "CardGrid packs four a row ..."; "the cards fill even rows ...").

### #24 Insights: chart sections (DR `SECTIONS`:609 in draw order, `HEADERS`:613-623)
| Section | Layout fn | Renderer | Reads | Class |
|---|---|---|---|---|
| A DPS Progression ("(% of board best)" when mixed) | `layoutProgression`:344; `progressionPerRun`:290 / `PerDay`:306 (> 60 runs); legend `progressionLegend`:328 | `ctx:renderStrip`, `renderLegend` | `stats.progression {run, dps, key, pct}`, `totals.oneBoard` | GENERAL |
| B/C By Target × Length (board tabs, Overall first) | `layoutBoards`:441, `placeBoardTabs`:412, `makeBoardTab`:388 | tabs + `Scope` + a rerun of `Compute` (`self.scoped`) | `stats.boardTabs`, `Insights.lastBoard` | **RACE-ONLY** as built (category × length). The plan lists "By Target × Length tabs" as race-only |
| Spec Comparison (on a picked tab only) | `layoutSpecs`:357 | `renderBarSection` | `tab.specs {best, avg, n}` | GENERAL per spec §7 ("by spec"), but DR draws it only under a board tab. D2 needs a fight-side tab key (#22), else it never shows under Fights |
| Consistency (on a picked tab, n >= 3) | `layoutConsistency`:371 | `renderRangeSection` (worst to best, mark at avg) | `tab.consistency {worst, best, avg, avgPct, cv}` | GENERAL per spec; same tab dependency as Spec Comparison |
| D Races By Character | `layoutCharacters`:457 | `renderBarSection` | `stats.byChar {name, class, n}` | GENERAL ("by character") |
| E Races By Character × Target | `layoutCharTarget`:497 via `layoutSplit`:477, `SPLITS.charTarget`:468 | `renderStackedBarSection` + legend | `byCharTarget {rows, categories}` (dummy kinds, `CATEGORY_COLORS`) | **RACE-ONLY** as is. It would be general only if rebased on CT content kinds (`CONTENT_COLORS`); the spec is silent, so D2 decides |
| F Races By Character × Length | `layoutCharLength`:503 | `renderStackedBarSection` + legend (`LengthColor`) | `byCharLength {rows, lengths}` | **RACE-ONLY** |
| I Races Per Day | `layoutPerDay`:555 | `renderStrip` | `stats.byDay {day, n}` | **RACE-ONLY** per spec §7. The data is general; a "Fights per day" would be a new section |
| J Damage Tail After The Buzzer | `layoutTail`:564 | `renderBarSection` (`C.blue`) | `stats.tail {lo, hi, n}` | **RACE-ONLY** |

DR pins: test_insights.lua ("above 60 runs the progression is one column a day ..."; "DPS Progression carries a legend ..."; "a section with nothing to show hides; Top Spells and Races By Length are gone"; "a tab per target x length board, Overall first, the pick kept while present"; "a new tab in the same session opens on the last board picked, nothing saved"; "the sections under the tabs read the tab picked, Overall reads every board"; "Consistency on a board tab ..."; "Races By Character x Length stacks ..."; "one date format everywhere"; "with no run the empty state shows ...").

### #25 Insights: list panels (DR `PANELS`:624)
| Panel | Fn | Reads | Interaction | Class |
|---|---|---|---|---|
| G Late Casts | `layoutLateCasts`:544, `lateRow`:526, `lateMenu`:519 | `stats.lateBySpell {counted, ignored}`, `K.LIST_MAX` (10); the ignored keep up to half the rows | a right-click calls `LateIgnore.Menu({flags={lateCasts={{spellID=id}}}}, row)`, never on mock data or an unknown spell. In CT the synthetic shape must match the race-part flags (#1) | **RACE-ONLY** |
| K Recent New Bests | `layoutNewBests`:590, `bestClick`:578 | `stats.newBests` newest first; right text "%s  %+.1f%%" | a left click `hooks.open(run)` (CT: `Results.ShowFight`); a right click `hooks.menu` | GENERAL |

DR pins: test_insights.lua ("Late Casts keeps room for the ignored spells when the counted ones pass ten"; "Late Casts lists the counted spells, then the ignored ones dimmed and tagged"; "a right-click on a Late Casts row opens the ignore list's menu, which redraws the tab"; "a Recent New Bests row opens its run on the Runs tab; a right-click its row menu").

### #26 Insights prerequisites missing from CT (D2)
- **DR core/ChartsSetup.lua** (TOC:75-77) gives `NS.Charts = LibStub("LibKa0s-Charts-1.0", true)` and `NS.ChartsHost()`, which returns `{pool=NS.Pool, panel=Tbl.Panel, tip=cursorTip, hideTip=Tbl.HideTip, text=Style.PlainText, paint, fill=Style.Fill, palette=Skin.Token("chart.series"), colors{body, value, muted, heading=C.gold, caption, rule="section.rule", bar="dr.chart.bar", track="chart.track", axis="chart.axis"}, fonts{label=TEXT, axis=CAPTION, heading=CHART, divider=SECTION, panelTitle=CHART, caption=CAPTION, figure=FIGURE}}`.
- **What CT already has:** LibKa0s Charts is vendored and loaded (`libs/LibKa0s/LibKa0s.xml:13-14` Charts.lua, ChartsRender.lua). `Tbl.HideTip` (CT Results_Table.lua:272), `FONT.CHART`, `FONT.FIGURE`, and the tokens `section.rule`, `chart.track` and `chart.axis` (core/SkinSetup.lua:121-124).
- **What CT lacks:** `core/ChartsSetup.lua` (not in D2's file list: add it, plus its TOC line before Results), the `ct.chart.bar` token (DR `{0.40,0.66,1.0,1}` follows `chart.bar`), the `chart.series` check, and a `Tbl.Panel`.
- **No-library path:** `NS.LIBKA0S_MISSING` keeps the filters and the count with an empty-state message (anti-pattern #73).
- **DR pins:** test_insights.lua ("insights charts: ..." host-table cases; "with no library the empty state says why there are no charts").

### #27 CT files near the cap and the seams they offer
| CT file | Lines | Seam for D1/D2 |
|---|---|---|
| `modules/Results_Table.lua` | 1197 | `Cells.badge`:316 / `Bind.badge`:442 (needs a trail for the tail text); `GroupKey`:830; the measure `delta` key 861-863. Nothing else |
| `modules/Results_Fights.lua` | 1009 | `DROPDOWN_SPECS`:54 and `GROUP_SPECS`:331 (both take `clients`); local `PASS`:174 and `OPTION_LISTS`:311 need an extension hook; `dpsOf`:455 becomes `RaceRecord.Dps`; `Columns`:668 cell fns; `buildBar`:736 / `BarPlan`:901 for the race checkboxes; `SetFilter`:999 is gated on `StockView` keys |
| `modules/Results.lua` | 984 | the tab strip (#2); `VERBS`:765; `RowMenu`:809; `onSettings`:955; `MIN_WIDTH`:44 is file-scope |
| `modules/Results_Detail.lua` | 723 | `SECTIONS`:67; `Build`:438 (`ResultsTargets.Build` model); `Show`:542; `Layout`:681; `DeltaBox`:147 (`ctx.second.dps`) |
| `modules/Results_Source.lua` | 181 | add `Invalidate`, a clean board and race boards (#19) |
| `modules/Filters.lua` | 33 | recording filter only (`Filters.Passes(identity, duration)`); a saved race bypasses it in Recorder (A3), so nothing Results-side here |

New files per the plan: `Results_Races.lua`, `Results_RaceDetail.lua` (D1) and `Results_Insights.lua`, `Results_InsightsData.lua` (D2). DR's are 982 and 607 lines; rebased they fit. The TOC goes after `Results_Detail.lua` and before `Results.lua` (CT TOC:191-205), and its LOAD-BEARING comment must be updated, since Results.lua reads `NS.ResultsFights` at file scope.

### #28 DR suites to port (D1 / D2)
- **D1:**
  - test_results.lua: filters, Only best, Status, length colors, the Time column.
  - test_results_badges.lua: the Time chip and trail; Spec best tooltip board.
  - test_results_group.lua: the race groupings.
  - test_results_delta.lua: the race Delta box.
  - test_results_detail.lua: timing strip, legend, flags.
  - test_results_sections.lua: the timing and flags folds.
  - test_late_ignore_ui.lua.
  - test_results_fit.lua: bar and columns fit `MIN_WIDTH`.
- **D2:**
  - test_insights_data.lua (13).
  - test_insights.lua (61; the "insights charts:" cases test the library host, port them with ChartsSetup).
  - test_results_window.lua (the Insights tab built on first show; tab label gold).
- **Plan's new cases:** all Forever-absence tests (Races filter, race-only sections, race controls) run under `KA0S_KIT_CLIENT=forever`, with saved race records present in the fixture (Review focus 3).

## settings

Scope: DR `settings/*.lua`, `Bindings.xml`, `core/LauncherSetup.lua`, `core/DpsRace.lua` handlers, `modules/AutoArm.lua`, compared with CT's `settings/*.lua`, `Bindings.xml`, `core/LauncherSetup.lua`, `core/CombatTrail.lua`, and how CT gates per-client features. Plan task: **B3**, unless an item names another. Paths: DR = `../DpsRace` at f8078c7, CT = this repo. Three items are **STOP-and-flag** under CLAUDE.md: #11 (launcher), #12 (Bindings.xml on Forever) and #4 (toast section on a Retail-only page). Each needs the owner's call before B3 can finish.

### #1 DR Race page: the page shell and its tabs
- **DR:** `settings/Race.lua:269-275` `NS.RegisterTabbedPage{ key="race", title=L["Race"], panelName="DpsRaceRacePanel", afterGroup={[LATE]=afterRace,[TOAST]=afterToast,[DUMMIES]=afterDummies} }`. The tabs come from group first-appearance: **Race | Late-cast ignore list | New-best toast | Training dummies**. `settings/Race.lua:280-292` repaints the page on `SETTINGS_CHANGED` for `race.lateIgnore`, `race.dummies` or `"profile"`, through `NS.pageCtx.race` and `H.RefreshPanel(ctx, true)`. DR page order is `general, race, hud, history, profiles` (`settings/Schema.lua:195`).
- **CT seam:** create `settings/Race.lua`, loaded after `settings/Hud.lua` and `History.lua` and before `Profiles.lua` (`CombatTrail.toc:228-232`). Add `race = true` to `VALID_PAGES` (`settings/Schema.lua:203`). `NS.RegisterTabbedPage` (`settings/OptionsSetup.lua:81-107`) is reused.
- **Differs:**
  - CT's page wrapper drops the library's 4th `opts` argument: `NS.RegisterOptionsPage = function(key, name, builder) Helpers.RegisterOptionsPage(key, name, builder) end` (`settings/OptionsSetup.lua:174`).
  - The library gates a page by `opts.clients` (`libs/LibKa0s/OptionsRegistry.lua:166-184`). So B3 must thread `spec.clients` through `RegisterTabbedPage` and pass `{ clients = { "retail" } }`. The stub at `OptionsSetup.lua:163` is a no-op and stays one.
  - The page order pinned in `tests/test_settings.lua:14-18` (`"general,lanes,hud,history,profiles"`) and the page-name lists at `:21-35` become per client. Where the page sits in the order is the builder's call.
  - Training dummies is not on this page in CT: it moves to History (A2, spec §9).
  - The title is "Race mode" (spec §8), not "Race".
- **DR tests:** `test_settings.lua` "Race is four tabs…" (477), "Race repaints when the ignore list changes…" (780), "the pages register in the panel's order…" (418).

### #2 Race tab rows (paths, defaults, ranges)
- **DR:** `settings/Race.lua:36-93`, defaults at `defaults/Profile.lua:82-113`. Subgroups in order:
  - **Length:** `race.defaultLength`, number, default **60**, values from `NS.HudStates.PRESETS` = `{30,60,120,180,300}` (`modules/Hud_States.lua:142`) shown as `Format.Length`. `onChange = NS.Hud.ForgetLength` clears `race.lastLength` (`modules/Hud.lua:163-167`).
  - **Auto-arm:** `race.autoArm`, bool, default **false**, `onChange = AutoArm.Sync`.
  - **Countdown:**
    - `race.countdownCue`: bool, default **true**, startsLine.
    - `race.centerCountdown`: bool, default **true**, startsLine.
    - `race.finalCountdown`: number 3..10 step 1, default **10**.
    - All three use `onChange = NS.Countdown.Refresh`.
  - **At the buzzer:** `race.buzzer`, bool, default **true**. `race.hintDelay`, number 5..60 step 1, default **15**.
  - **Scoring rules:** `race.grace`, number 0..5 step 0.1, default **1.0**. `race.restartGap`, number 3..15 step 1, default **6**. Both are frozen into each new run.
  - **Simulator:** `sim.stepDelay`, `Sim.STEP_DELAY_MIN..MAX`, default 1 (`defaults/Profile.lua:227`).
  - Non-row state: `race.lastLength`, written by the HUD (`modules/Hud.lua:149-159`). Range constants: `Race.MIN_LENGTH, Race.MAX_LENGTH = 10, 900` (`modules/Race.lua:36`).
- **CT seam:** `settings/Race.lua` (new). Add a `race` table to `defaults/Profile.lua:101-` that is **absent on Forever**, following the `content()`/`where()` pattern (`defaults/Profile.lua:19-47`, clients-§4 "no stored key").
- **Differs:**
  - Plan B3 lists only "default length, clock, hint delay, auto-show, auto-arm". It does not name `countdownCue`, `centerCountdown`, `finalCountdown`, `buzzer`, `grace` or `restartGap`. Spec §8 says DR's whole Race section ports, so these rows belong on the page too. B1 reads grace/restartGap and C2 reads countdown/buzzer; B3 should own every row.
  - Do **not** port `sim.stepDelay`. CT's sim has a fixed `Sim.STEP_DELAY = 1.5` (`modules/Sim.lua:53`) and no row.
  - The race clock and auto-show rows move here from DR's HUD page (#3).
  - The new **Race mode** master switch `race.enabled = true` goes first (spec §8). `NS.RaceMode.On()` = `Compat.ForClient({"retail"}) and race.enabled`.
  - Tooltips must swap "run" for "race" or "fight" (plan's Words rule).
- **DR tests:** `test_settings.lua` "the Race page's rows, ranges and defaults" (294), "grace slider 0..5 step 0.1, restartGap 3..15…" (264), "the scoring sliders say they apply to new runs" (286), "changing grace does not alter saved runs" (338), "the sticky-combat hint's tooltip states its range" (514), "the stored paths, types, defaults and ranges are exactly the pinned set" (202).

### #3 DR HUD-page rows that become Race-window rows
- **DR:** `settings/Hud.lua:23-52`, defaults `hud = { showMode="onArm", clock="both", autoShow=true, … }` (`defaults/Profile.lua:142`).
  - `hud.showMode`: string, "onArm" | "always". `onChange` with "always" calls `Hud.Show()`.
  - `hud.clock`: "both" | "left" | "elapsed", `onChange = Hud.Refresh`.
  - `hud.autoShow`: bool, default **true**, startsLine, `onChange = AutoArm.Sync`.
  - Appearance blocks `appearance.elapsed` (green 0.36/0.86/0.46) and `appearance.left` (red 1.0/0.32/0.32), JetBrains Mono 26 (`defaults/Profile.lua:166-171`). They show only while `hud.clock` selects them (`settings/Hud.lua:171-177`, `shownWhen`).
  - The rest of DR's HUD page (`hud.sizeMode/bars/grow`, `live.*`, the chart and pace blocks) is CT HUD territory and does not port. CT already has `hud.paceRange` and the chart and spells blocks (`defaults/Profile.lua:102-150`).
- **CT seam:** in `settings/Race.lua`, `race.clock` and `race.autoShow` (plan) and something for showMode. In `settings/Hud.lua`, "Clock and figures" holds CT's single `hud.clock` font block.
- **Differs:**
  - Paths move from `hud.*` to `race.*`. The `hud.*` namespace is CT's HUD.
  - `showMode` has no slot in the plan. The Race window is shown by the dummy rule, the arm, the result, `/ct race show`, the key and the launcher (spec §4.1). Recommendation: drop `showMode` and state why, or keep it as `raceWindow.show`.
  - Spec §8 says the Race window's look comes from the DPS HUD page's blocks with no styling tree of its own. CT has one clock block. DR's two colored clocks carry meaning (green elapsed, red time left).
  - C1 or B3 must choose: reuse `hud.clock` for both clocks (meaning lost), or add two Retail-only blocks to the DPS HUD page's Clock and figures tab. Those blocks need `clients={"retail"}` and defaults absent on Forever, and `tests/test_hud_page.lua:216` ("no row names a Retail-only feature") must keep passing on Forever.
- **DR tests:** `test_settings.lua` "the HUD's show mode is on the HUD page's Race HUD tab…" (369), "the race clock is a Race HUD row…" (383), "the show mode's tooltip points at General visibility" (519). `test_autoarm.lua` (55, 259, 400).

### #4 New-best toast section (STOP-and-flag)
- **DR:** `settings/Race.lua:95-122` plus `afterToast` (`:261-267`, the *Test toast* button calling `BestToast.Test()`). Defaults `toast = { enabled=true, duration=10, sound=true, soundKey="Default", scale=1.0 }`, plus `toast.point`, written by the test-mode drag (`defaults/Profile.lua:224`). Rows:
  - `toast.enabled`: bool, `onChange = BestToast.Sync`.
  - `toast.sound`: bool, startsLine.
  - `toast.soundKey`: string, `dialogControl="Ka0sMedia_Sound"`, `values = BestToast.SoundValues()`, no validate.
  - `toast.duration`: number 3..30 step 1, startsLine.
  - `toast.scale`: number 0.5..2.0 step 0.05, `onChange = BestToast.Refresh`.
- **CT seam:** `settings/Race.lua` per the plan. Defaults `toast = { races=true, fights=true, ... }`. Modules in C2.
- **Conflict:** plan C2 says "fights' toast is on both clients, races' Retail only" (spec §8). Under plan B3 the whole toast section sits on the Retail-only Race mode page, which leaves Forever with a fight toast and no controls. Options for the owner:
  - (a) Put the toast section on a both-client page (DPS HUD or History), with only `toast.races` declared `clients={"retail"}` and its default key absent on Forever.
  - (b) Make the fight toast Retail-only too.
  - `toast.enabled` is replaced by `toast.races` and `toast.fights`. Every other key ports as is.
- **DR tests:** `test_toast.lua` (all, esp. 227 "Play a sound stays the switch", 264 "a page's Defaults brings it back", 291 "Test toast…", 330 "a drag stores the place…; Reset position clears it"), `test_settings.lua` 770 "Race's Defaults brings the toast back…".

### #5 Late-cast ignore list tab
- **DR:** `settings/Race.lua:87-92` is the row:
  - `path = NS.LateIgnore.PATH` = `"race.lateIgnore"` (`modules/LateIgnore.lua:20`), string, `skipRender`.
  - Default `"66,1856,5384,8690,58984,110959"` (`defaults/Profile.lua:90`).
  - `validate = LateIgnore.Parse(v) ~= nil`, `normalize = LateIgnore.Normalize`.

  `afterRace` (`:164-186`) draws `H.TextRow`, then `H.IdList{ kind={base="spell", resolve=LateIgnore.Resolve}, candidates=LateIgnore.KnownSpells, onAdd=LateIgnore.Ignore, onRemove=LateIgnore.Unignore, removeStyle="icon", columns=2 }`. Entry 8690 gets the suffix "(all hearthstones, %d)" with `#NS.HEARTHSTONE_SPELLS`. A *Reset list* button runs `LateIgnore.Reset()`.
- **CT seam:** `settings/Race.lua` (tab), `modules/LateIgnore.lua` (B1). `NS.HEARTHSTONE_SPELLS` comes from DR `defaults/Hearthstones.lua`, which CT does not have (`defaults/` holds only Dummies, IgnoreSeeds and Profile). B1 must bring it, or B3 must.
- **Differs:** the path `race.lateIgnore` can stay. The page's Defaults tooltip must name it (`settings/Race.lua:273`). The words "run" become "race".
- **DR tests:** `test_settings.lua` 712 "Race draws the late-cast ignore list as the library's spell ID list…", 743 "Race's Reset list puts the six defaults back…", 759 "Race's Defaults resets the ignore list too…". All of `test_late_ignore.lua` (51-387). `test_late_ignore_ui.lua` (53, 82, 98).

### #6 Training dummies tab (A2, not B3)
- **DR:** `settings/Race.lua:134-147` holds two rows:
  - `race.dummyCategory`: string, default `"auto"`, values Automatic plus `DummyList.KINDS={"single","cleave","dungeoneer","boss","pvp"}` (`modules/DummyList.lua:24,28`).
  - `race.dummies`: string, default `""`, skipRender, `Parse`/`Normalize`.

  `afterDummies` (`:225-258`) draws a blurb, then *Add your target* (`DL.Read("target")`, `Capture`, `Add(npcID, CategoryFor(r))`). Next comes an IdList of your own dummies (suffix `· <category>`). Then one `H.SessionCheckbox` per built-in sorted by ID, which adds or removes it. Last, *Reset list*. Captures live in `db.global.dummies.captures` (`defaults/Profile.lua:284`).
- **CT seam:** the History page's Training dummies section (A2). Do not add it to the Race page.
- **Differs:** the plan's A2 shape is `dummies = { custom = {} }`, not DR's string row. The categories stay because races read them (spec §9). The DR blurb mentions "/dr targetdummy add" and becomes "/ct dummy add".
- **DR tests:** `test_settings.lua` 827, 870. `test_dummy_list.lua`, `test_dummies.lua`.

### #7 Race window rows (new in CT)
- **DR:** none. DR's HUD is the race window. Its lock is Master `locked` (`settings/General.lua:105`) and its reset is Master *Reset position* (`settings/General.lua:66-72`, which also calls `BestToast.ResetPosition`).
- **CT seam:** plan B3 has `raceWindow = { attached=true, side="RIGHT", ... }` with the rows attached, side (RIGHT/LEFT/TOP/BOTTOM), lock and reset position. C1 consumes them.
- **Differs:**
  - CT has one lock switch for every placed frame: `general.locked`, through `NS.ApplyLocked`, which calls `eachPlaced("SetLocked")` over `PLACED = {"Lanes","Hud","Results"}` (`core/CombatTrail.lua:88-118`).
  - CT's HUD deliberately has no lock row (`settings/Hud.lua:20-21` header). A `raceWindow.locked` row would be the only per-frame lock, which conflicts with CT's convention.
  - Recommendation: add `"RaceWindow"` (and C2's `"BestToast"` for `ResetPosition`) to `PLACED`. Keep "Reset position" only as a page act if wanted. The spec's "detached … can be locked" is then met by Lock frame.

### #8 The slash verbs
- **DR:** `settings/Slash.lua:49-77` registers the feature verbs in this order: `arm`, `cancel`, `hud`, `results`, `target`, `test`, `sim`, `lock`, `unlock`, `ignore`, `targetdummy`. Handlers:
  - `doArm` (`:249-260`): `Format.ParseLength(text)` takes "90", "1:30" or "3m". Outside `Race.MIN_LENGTH..MAX_LENGTH` (10..900) it prints `Format.ArmRefusal("bad_length")`. Otherwise it calls `Hud.Act.pickLength(n)`, then `Hud.Act.arm()`.
  - `doCancel` (`:262-276`): the `CANCELED` lines by state (armed / running / stopping / result) or "Nothing to cancel.".
  - `doHud` (`:279-285`): show | hide | toggle, bare = toggle, calls `NS.SetHudShown`.
  - `doTest` (`:288-291`): `ToggleTestMode(word)` with armed | running | result.
  - `doResults` (`:299-303`): `NS.ShowResults(word)`. "insights" and the silent alias "bests" open the Insights tab (`core/DpsRace.lua:133-139`).
  - `doTarget` (`:306-314`).
  - `IGNORE_VERBS` show | add | remove | defaults (`:318-372`).
  - `DUMMY_VERBS` (`:375-502`).
  - `HOST_LIVE_VERBS = { "ignore", "targetdummy" }` (`:93`).
- **CT seam:** `settings/Slash.lua:30-71` (`NS.COMMANDS`), `:93` (`HOST_LIVE_VERBS = {"lane","ignore"}`), and `delegate(owner)` (`:238-246`). One new triple: `{ "race", L[...], fn, clients = { "retail" } }`.
  - The library honors `clients` on triples (Slash minor 22, `libs/LibKa0s/Slash.lua:239-249,405`) and on schema rows in the CLI (`:601-606`).
  - Spec §8 grammar: `race arm [len] | cancel | show | hide | toggle | ignore [show|add|remove|defaults]`.
  - `/ct dummy …` is A2. `results races`/`results insights` are D1/D2 through `Results.OnVerb` (`modules/Results.lua:773-779`). `test race [armed|running|result]` is E1; CT's `doTest` takes no args today (`settings/Slash.lua:254-256`).
- **Differs and conflicts:**
  - **The degraded stub ignores `clients`.** The library-absent stub's `OnSlash`, `LandingRows` and `HelpRows` (`settings/Slash.lua:122-155`) and `NS.RunVerb` (`:75-79`) loop every triple. B3 must add the same `ForClient` gate there, or `race` leaks into Forever's reduced help.
  - **Liveness is per verb.** DR's `ignore` was live while disabled. In CT it becomes the `race ignore` sub-word, but liveness is per top-level verb.
    - Choice (a): put `race` in `HOST_LIVE_VERBS`. The handler then refuses arm | cancel | show | hide | toggle itself while disabled, printing `cli:DisabledLine()` when `NS.IsDisabled()` and `NS.StoodDownRefusal()` under the perf hold. That is what `feature()` (`:18-24`) does, minus the disabled line, which only the dispatcher prints.
    - Choice (b): keep `race` feature-gated and leave `race ignore` refused while disabled. That deviates from DR's behavior but not from the standard.
  - **`/dr target` has no home.** It prints the target's name, creature ID and category (`:306-314`). The spec and plan do not mention it. Fold it into `/ct dummy` (A2) or drop it explicitly.
  - **Sub-words on Forever.** `results races` and the Races help text must answer the usage line and never name races, because the Slash library gates whole verbs, not sub-words.
  - **Owner logic.** DR's `Hud.Act.*` belongs to `NS.RaceWindow` and `NS.Race` in CT.
  - **CT verbs that already cover DR's.** CT's `hud` verb already does show | hide | toggle | pin | unpin (`modules/Hud.lua:1044-1058`), so DR's `/dr hud` maps to `/ct race show|hide|toggle`. `lock`/`unlock` exist (`:54-56`).
- **DR tests:** `test_slash.lua` 182 "the feature verbs follow `version`…", 189 "arm parses 90, 1:30, 3m and rejects 0 and 901", 205, 216, 226, 244, 257, 266, 282, 302, 312, 407 "feature verbs answer the enable line while disabled", 425 "the Arm or cancel key…", 479-560 (ignore), 573 "the live dispatcher's live set is…".

### #9 The shared handlers behind verb, key and menu
- **DR:** `core/DpsRace.lua`:
  - `refused()` (103-107).
  - `NS.ToggleHud` (109).
  - `NS.ToggleResults` (115).
  - `NS.SetHudShown(how)` (123).
  - `NS.ShowResults(tab)` (133).
  - `NS.ToggleArm()` (143-152): ARMED or RUNNING → `Race.Cancel()`. STOPPING prints "A run is waiting for its result: /dr cancel discards it." and returns false. Otherwise it runs `Hud.Act.arm()`.
- **CT seam:** `core/CombatTrail.lua:70-215`, which has the same `refused()` (75-79) and `notBuilt()` (81-84). Add `NS.ToggleArm()` and `NS.ToggleRaceWindow()`, each refusing first, then `if not NS.RaceMode.On() then return false end` (spec §8: "the arm keybinding and the launcher entry do nothing" when the switch is off). What "do nothing" means (silent, or one line) is the builder's call; test it.
- **Differs:** the STOPPING line becomes "/ct race cancel".
- **DR tests:** `test_slash.lua` 425, `test_disabled.lua` 330 (the press while stood down).

### #10 Key bindings
- **DR:** `Bindings.xml:11-15` holds three `CLICK` bindings, all `category="BINDING_HEADER_DPSRACE"`: `DpsRaceToggleHud`, `DpsRaceToggleResults` and `DpsRaceArmToggle`. In `core/LauncherSetup.lua`:
  - Buttons are created at `18-38`, registered for "AnyDown", hidden.
  - `NS.BINDINGS` (43-50) carries tooltips. The arm tooltip reads "Arms a race at the HUD's length, or cancels an armed or running race. A finished race's result is kept."
  - Labels are set at `54-57`, including `L["Arm or cancel race"]`.
- **CT seam:**
  - `Bindings.xml:11-13` holds three `CLICK` bindings.
  - `core/LauncherSetup.lua:19-53` has the `button(name, handler)` helper, `NS.BINDINGS` and labels via `rawset`.
  - General's Keybindings tab: `H.KeybindingsTab({ bindings = NS.BINDINGS })` (`settings/General.lua:219`).
  - Add two Retail entries (plan: *Arm / cancel race*, *Toggle Race window*) carrying `clients = {"retail"}`. OptionsKeybinds minor 8 drops such a row on another client (`libs/LibKa0s/OptionsKeybinds.lua:70-71`).
  - Create their buttons and `BINDING_NAME_` globals only under `Compat.ForClient({"retail"})`.
  - Button names are permanent once shipped. Suggested: `CombatTrailArmToggle` (DR's shape) and `CombatTrailToggleRace` (launcher-§6's `<Folder>Toggle<Window>`). The new entries append after the three existing ones: the Show window binding stays first.
- **Differs:** `tests/test_bindings.lua:54-74` pins `#NS.BINDINGS == 3` and the `LABELS` map. `Kit.assertBindingsXml` (`tests/_kit/bindings_xml.lua:160-170`) requires the XML names to equal `opts.commands` in order. A `clients`-filtered list would therefore fail against the static XML on Forever. See #12.
- **DR tests:** `test_keybinds.lua` 53, 63, 84. `test_launcher.lua` 105, 119, 128. `test_slash.lua` 425-429 (label "Arm or cancel race").

### #11 Launcher menu "Show Race window" (STOP-and-flag)
- **DR:** `core/LauncherSetup.lua:87-113` passes only the standard pairs: Enabled, Locked, Test mode, Sim mode, and Show window = the race HUD (`toggleWindow = NS.ToggleHud`). DR has no race-specific entry.
- **CT seam:** `NS.LAUNCHER_DESCRIPTOR` (`core/LauncherSetup.lua:89-116`). Its Show window is the DPS HUD (`toggleWindow = NS.ToggleHud`).
- **Conflict:**
  - `LibKa0s-Launcher-1.0` minor 9 builds a **fixed** entry list: `ENTRIES` = Enabled, Locked, Test mode, Sim mode, Show window (`libs/LibKa0s/Launcher.lua:149-155`). There is no descriptor field for an extra entry.
  - `entryClients` (`:158-168`, `:262-266`) only gates the fixed toggles and `openSkinPicker`.
  - launcher-§2 fixes the menu order "and no other", and anti-pattern #81 forbids a host-built menu. Show window must stay the primary display, the DPS HUD.
  - So plan B3's "the launcher's master-controls menu (*Show Race window*)" and spec §8's "Launcher: a 'Show race window' entry on Retail" **cannot be built** on the vendored library without deviating.
  - The owner chooses:
    - (a) Drop the entry. The window is still reachable through the key, `/ct race show` and auto-show.
    - (b) File a LibKa0s issue and a standard change (launcher-§2 gaining an optional secondary-window entry), then re-vendor.
    - (c) Ratify a deviation row. That is not workable: the library offers no seam, and building one by hand is #81.
  - Until decided, the test `race mode: every … launcher entry is absent on WoW Forever` has nothing to assert on.
- **CT tests that pin the menu:** `tests/test_slash.lua:227-252` ("launcher: the menu carries Enabled, Locked, Test mode, Sim mode and Show window"; "the menu's toggles are the slash verbs' handlers"). DR: `test_launcher.lua` 38 "right-click lists Enabled, Locked, Test mode, Show window and Open skin selector, in that order", 47.

### #12 Bindings.xml is static, so a Retail-only binding leaves a trace on Forever (STOP-and-flag)
- **DR:** n/a, Retail only.
- **CT seam:** `Bindings.xml`. The client reads it by name from the addon root (launcher-§6). CT ships one TOC with `## Interface: 120105, 16001` (`CombatTrail.toc:1`).
- **Conflict:**
  - clients-§4 says "A Forever player's … key bindings list show[s] no trace of a Retail-only feature". clients-§4 bullet 2 also names "bindings" as a library-gated registration, but only the settings tab is library-drawn.
  - The two new `<Binding>` lines would still appear in Forever's own Options → Keybindings. With no `BINDING_NAME_` global set they show as raw `CLICK …` text.
  - Paths I could not verify here:
    - A flavor-suffixed bindings file (e.g. `Bindings_Mainline.xml`). Client support and Forever's suffix are both unverified: it needs an in-game probe.
    - That route also breaks `Kit.assertBindingsXml`'s single-file read.
  - Otherwise the owner decides between a documented deviation (`clients-§4` row: "Race bindings listed in Forever's client Keybindings UI") and a standard change.
  - Either way, `tests/test_bindings.lua` must pass the **unfiltered** command list to `assertBindingsXml` on both profiles and assert the General tab's rows are filtered on Forever.

### #13 AutoArm (auto-show and auto-arm)
- **DR:** `modules/AutoArm.lua:1-277`.
  - Settings `hud.autoShow` (default true) and `race.autoArm` (default false).
  - `AutoArm.HIDE_DELAY = 3` s debounce, through `C_Timer.NewTimer`. `hideDue` rescans the nameplates before closing.
  - Events: `TARGET_EVENTS = {"PLAYER_TARGET_CHANGED","PLAYER_ENTERING_WORLD"}`, plus `PLATE_EVENTS = {"NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED"}` only while auto-show is on. They register through `NS.SafeRegisterEvent` on the module's own AceEvent target. `wanted()` answers "none" | "target" | "plates".
  - No action in an instance: `GetInstanceInfo` kind other than "none", read through `Secrets.PlainString`.
  - No action while stood down.
  - Manual-close rule: a session records `closes = Hud.Closes()` and does not reopen once that count moves.
  - `tryArm` needs auto-arm on, the addon active, no preview, Race IDLE and not in combat. It then calls `Race.Arm(Hud.ArmLength())` and remembers `armedRun`. `disarm()` (out of combat only) cancels only that same run while it is still ARMED.
  - `onState` listens on `RACE_STATE_CHANGED` (ignoring `run.sample`). Bus reactions on `"profile"` and `DummyList.PATH` call `Sync`.
  - Public surface: `Sync`, `Suspend`, `Resume`, and `Diagnose() -> {events, plates, session, hiding, armed}`.
  - HUD hooks used: `Hud.ShowNearDummy` / `HideAwayFromDummy` / `ShownNearDummy` / `Closes` (`modules/Hud.lua:1061-1087`).
- **CT seam:** `modules/AutoArm.lua` (new, B3). CT already has `NS.SafeRegisterEvent` (`core/CoreSetup.lua:62,85`), `NS.rejectedEvents` (`:9`), `Secrets.IsSafeKey`/`PlainString` (`core/Secrets.lua:50,92`), `NS.IsStoodDown` (`core/LifecycleSetup.lua:109`) and `NS.NewBusTarget` (`core/Bus.lua:112`).
- **Differs:**
  - Dummy detection: DR's `NS.Recorder.DummyOf(unit)` becomes A2's `NS.Dummies` plus CT `Identity` (CT today: `NS.DummyName(creatureID)`, `modules/Identity.lua:214,318`).
  - The four HUD hooks move to `NS.RaceWindow` (C1). B3 lands before C1, so it needs a stub or an agreed interface.
  - Plan B1's bus list (`RACE_ARMED/STARTED/BUZZER/RESULT/CANCELLED`) has **no `RACE_STATE_CHANGED`**. AutoArm needs a state-edge message (`to == IDLE`, leaving ARMED). B1 must add one, or AutoArm subscribes to all five.
  - Gate every action on `NS.RaceMode.On()`. Off means no registrations (`wanted()` returns "none").
  - Register only under `Compat.ForClient({"retail"})`, which matches clients-§4's "event registration".
  - Settings paths: `race.autoShow` and `race.autoArm`.
- **DR tests:** `test_autoarm.lua`, 31 cases (55-447): "a new profile shows the HUD near a dummy and never arms by itself", "each rule registers only what it needs…", "nameplates churning inside the debounce…", "a secret GUID is no dummy", "the player's close keeps it closed…", "targeting anything else before the pull disarms…", "a target change in combat … never disarms", "neither rule acts in an instance or a battleground", "stood down, nothing is registered…". The fixture is `tests/race_clock.lua` (scripted meter and fake clock, `M.__setTarget`, `M.__setPlate`), which CT lacks.

### #14 History page: refuse a purge while racing
- **DR:** `settings/History.lua:32-57`. `raceBusy()` is true for ARMED, RUNNING or STOPPING. `History.DeleteAll` and `ConfirmDeleteAll` then print "Finish or cancel the race first.".
- **CT seam:** `settings/History.lua:188-215` (`HistoryPage.ConfirmPurge`, popup `COMBATTRAIL_PURGE_FIGHTS` → `Retention.OnVerb`) and `/ct purge` (`settings/Slash.lua:61`).
- **Differs:** CT's purge removes only old or over-cap fights, not all of them. An unsaved race fight is not in the store until `FIGHT_SAVED`. The DR guard is therefore likely unnecessary. Decide and record it, or port the guard for safety.
- **DR tests:** `test_settings.lua` 575 "Purge history… is refused while a race is armed".

### #15 How CT declares Retail-only features and tests them absent on Forever
- **Pattern in CT:**
  1. The default key is **absent** on Forever, built under `NS.Compat.ForClient({"retail"})` (`defaults/Profile.lua:19-47`).
  2. A row is built only where its default key exists, and also carries `clients = { "retail" }`: `settings/History.lua:81-107` (`CONTENT`, `if D.history.content[c[1]] ~= nil`) and `settings/Lanes.lua:352-359` (`retailHides`).
  3. Wording is per client: `settings/History.lua:115-117`.
  4. `NS.Compat.ForClient` is the library's function or a stub that raises on an unknown token (`core/Compat.lua:79-108`).
  5. Each feature has a row in `docs/ARCHITECTURE.md:27-43` ("Per-client features").
- **Tests:** one test per feature, branching on `NS.Compat.IsForever()`. On Forever it asserts `NS.FindSchemaRow(path) == nil`, and that no label or tooltip on the page names the feature. On Retail it asserts `table.concat(row.clients, ",") == "retail"`. Examples: `tests/test_history_page.lua:163-190`, `tests/test_lanes_page.lua:172-184`, `tests/test_load.lua:63-68`. The suite runs under both `KA0S_KIT_CLIENT` profiles.
- **B3 must add:**
  - Per-client rows for the page, `/ct race`, both bindings, the launcher entry (if #11 allows one), AutoArm's event registration, the toast races toggle and the Race window.
  - `tests/test_race_settings.lua`: on Forever, no `race` page in `Helpers.__pages()`; no `race.*`/`raceWindow.*` rows; `race` not in help or landing rows (live **and** stub dispatcher); no race rows on the Keybindings tab; no `CombatTrailArmToggle`/`CombatTrailToggleRace` button or `BINDING_NAME_`; `NS.defaults.profile.race == nil`. On Retail, the inverse plus `clients == "retail"`.
  - Also `race mode off: arming refuses and the Race window stays hidden` (plan B3).

## test-sim

Scope: DR `modules/Preview.lua`, `SampleRace.lua`, `MockRuns.lua`, `MockRotations.lua`, `Sim.lua`, `Share.lua` and `Diagnostics.lua` (race parts), compared with CT `modules/Preview.lua`, `MockFights.lua`, `MockRotations.lua`, `Sim.lua`, `Share.lua`, `Diagnostics.lua` and `Results_Source.lua`. Owners: **E1** (test mode, sim, samples, diagnostics) and **C2** (the arm and result chat lines). Paths are `modules/` unless named otherwise.

### #1 Preview shell: test mode's race states and how a preview ends
- **DR:** `Preview.lua:37-40` (constants), `:52-58` (`IsState`), `:61-64` (`raceOn`), `:98-121` (`drawStill`, `startTest`, `SetState`), `:128-130` (`Queue`), `:147-151` (`Refusal`), `:160-190` (`Start`), `:194-205` (`release(reason)`), `:211-223` (`Stop(reason)`), `:228-237` (`Suspend`), `:240-246` (`Diagnose`), `:248-259` (ends on arm).
- **What it does:**
  - Constants: `Preview.STATES = { "armed", "running", "result" }`, `Preview.DEFAULT_STATE = "running"`, `Preview.STILL_AT = 18`, which is race-clock seconds and clear of the final countdown.
  - Test mode builds `sample = NS.Sim.Sample("newbest", dataset)`. It then calls `NS.SampleRace.Hold(sample, state, state=="running" and STILL_AT or 0)`, `NS.Hud.Render()` and `Preview.OpenResults()`, and holds the new-best toast with `NS.BestToast.ShowPreview(sample)`.
  - `SetState(word)` only works while `mode=="test"`.
  - `Refusal()` returns one of two lines:
    - `"Test mode is not available in combat."`
    - `"Test mode is not available during a race."` (Race state ARMED, RUNNING or STOPPING)
  - `Start(opts)`: `opts = opts or queued or {mode="test"}`. The dataset is `NS.Sim.Dataset()` for the sim, else `NS.MockRuns.Dataset()`, and goes to `NS.ResultsSource.Use(dataset)`. The HUD is opened through `Hud.AutoShow()`, so it counts as the addon's own open (AutoArm's manual-close rule).
  - `Stop("race")` keeps the HUD open for the real race. `Stop("combat")` prints once through `NS.SayTestModeEnded()`.
  - A `RACE_STATE_CHANGED(run, from, to)` handler fires when `to == ARMED`, the preview is active and `not run.sample`. It prints `"Test mode ended: a race was armed."` and calls `Preview.Stop("race")`.
  - `Diagnose()` returns `{ active, mode, phase (the held state word, or the sim's phase), scenario, ticking }`.
- **CT seam:** `Preview.lua:34-37` (`BOARD = "vorasius"`, `STILL_AT = 25`, `TEST_LENGTH = 60`, `TEST_FACTOR = 1.03`), `:145-159` (`startTest`), `:172-176` (`Refusal`), `:193-214` (`Start`), `:218-224` (`release`), `:230-241` (`Stop`), `:257-264` (`Diagnose`, phase `"held"`), `:266-274` (ends on `FIGHT_STARTED`). Owner: **E1**.
- **What differs:**
  - CT has a single held moment: no state words, no `Queue`, no `SetState`.
  - CT's `Refusal` checks `NS.Fight.Current()`, not a race. An ARMED real race has no `Fight.Current()`, so E1 must add a race check: `Race.State()` is ARMED, RUNNING or STOPPING. Use the DR line, worded in CT's vocabulary.
  - CT ends the preview on `FIGHT_STARTED`; DR ends it on arm. E1 needs a `RACE_ARMED` handler with the `race.sample` guard. Without it, a real arm during test mode leaves the Race window on the sample.
  - CT's `Start` ignores `opts.state`, and `Preview.Diagnose().phase` is `"held"`. A race test needs a phase such as the held race state.
  - CT's `release` calls `Hud.EndSample(opened)`, which has no `"race"` reason. The Race window (C1) needs its own `EndSample`, or a release that is aware of the race.
  - The toast hooks come from **C2** (see #11).
- **DR tests:** `tests/test_preview.lua` (25 cases):
  - `"preview: a queued state opens on that body; SetState switches armed, running and result"`
  - `"preview: arming a real race ends test mode and gives the Results window the store"`
  - `"preview: a start during a real race is refused"`
  - `"preview: over a real result card its controls never touch the real race"`
  - `"preview: a HUD test mode opened is handed to the race that ended it, and closes with it"`
  - `"preview: the still running clock follows the Race clock setting"`

### #2 The `test` verb: `/dr test [armed|running|result]` becomes `/ct test race [armed|running|result]`
- **DR:** `settings/Slash.lua:61` (help row), `:286-290` (`doTest(rest)` → `NS.ToggleTestMode(word)`); `core/DpsRace.lua:171-181` (`NS.ToggleTestMode(word)`):
  - A bare word toggles `state.testMode`.
  - An unknown word prints `"Usage: %s test [armed|running|result]"`.
  - In test mode, a state word calls `P.SetState(word)`; otherwise it calls `startQueued({mode="test", state=word})`.
- **CT seam:** `settings/Slash.lua:57-58` (`feature(function() doTest() end)` drops `rest`), `:253-256` (`doTest()`); `core/CombatTrail.lua:189` (the `general.testMode` row's write calls `Preview.Start({mode="test"})`), `:193-196` (`NS.ToggleTestMode()` takes no word). Owner: **E1**. The verb row also touches B3's Slash file.
- **What differs:**
  - CT keeps the setting at `general.testMode`, where DR used `state.testMode`.
  - The `race` sub-word and its three states must be declared through `NS.Compat.ForClient({ "retail" })`. On Forever they must be absent, not refused (clients-§4), with a present test and an absent test.
  - CT's `Preview.Start` must carry `{ mode="test", race=state }` through the `general.testMode` write. DR used a queued start (`Preview.Queue`) for this, because the row's write calls `Start()` with no arguments.
  - Race mode off (`NS.RaceMode.On()` false, B3): the spec says the switch stops new races only. Leaving `/ct test race` usable with Race mode off is the builder's call; record it in E1.
- **DR tests:** `tests/test_slash.lua` (the test-verb cases); `tests/test_skin_picker_preview.lua` `"skin picker preview: the hook goes through NS.ToggleTestMode, the verb's and the launcher's seam"`.

### #3 SampleRace: the stand-in for `NS.Race`
- **DR:** `SampleRace.lua`, 353 lines in total:
  - `:30-40` state
  - `:56-111` queries: `On`, `Held`, `State`, `Current`, `Elapsed`, `TimeLeft`, `SinceBuzzer`, `StopRequested`, `InCombat`, `ReadLive`
  - `:119-215` the script: `hear`, `land`, `begin`, `stop`, `buzz`, `endEarly`, `read`, `checkReady`, `stopping`, `running`, `advance`
  - `:218-237` `shell` and `load`
  - `:240-317` `Start(s, lead, park)`, `Unpark(lead)`, `Advance() -> updated`, `Skip(t)`, `SkipToResult()` (at most 400 half-second steps), `StopAt()`, `Hold(s, key, t)`
  - `:323-353` `StopNow`, `Cancel`, `Clear`
- **What it does:**
  - It answers Race's query surface, so every view is built by one path. DR's HUD chooses between the two at `Hud.lua:174-184`: `raceNow()` returns `NS.SampleRace` while `previewOn() and sample.On()`, and `sampleOn()`.
  - It sends the real messages (`RACE_STATE_CHANGED(run, from, to)`, `RACE_BUZZER(run)`, `RACE_RESULT(run)`) unless `silent`, so the countdown, the buzzer, the chat lines and the toast are the real receivers.
  - It never fires `RUN_SAVED`, never calls `Recorder.Save` and never moves `NS.Race`.
  - The clock runs at real speed (`anchor + GetTime() - wallAt`). Casts are stamped from `zero` (fixed at `begin()`), and a parked arm does not move the clock (SG-DR-1).
  - The read follows Race's rule: out of combat, then `Scoring.QUIET_BEFORE_READ = 2.5` seconds after the later of the last hit and the combat end. *Stop Now* waives the quiet but still waits for the combat end.
  - Late casts are judged as they are heard (`offset > 0 and not pet and Scoring.IsLateCast(offset, run.race.grace)`) into `run.flags.lateCasts` as `{ t = round2(offset), spellID }`.
  - The run joins the sample history at `begin()` through `ResultsSource.Put(run)`.
  - `Hold(...)` replays silently:
    - `"running"` freezes at `t` and captures `Slices.Capture(run, rec, TotalAt(plan, rec))` for each whole second.
    - `"result"` uses `held = math.huge` and captures every second up to `run.race.length`.
    - `"armed"` uses `held = 0` and deletes the run from the history again.
    - Running and result call `Touched()` once at the end.
  - `Clear()` keeps `NS.Casts` when a real race is ARMED, so the real race keeps its cast list.
- **CT seam:** nothing exists yet. Add a new file such as `modules/RaceSample.lua`, loaded after `Race.lua`. It needs:
  - a `raceNow()` chooser inside the Race window (C1 `RaceWindow*.lua`);
  - the CT HUD fed the sample fight directly, as `Preview.lua:14-20` documents: `Hud.OnFightStarted/OnFightTick/OnFightEnded/OnFightSaved` (`Hud.lua:66-69, 895-925`), with `fight.sample = true` and `fight.plan`, plus a `fight.race` so that C3's pacing reads the race board.
  
  Owner: **E1**. C1 must leave the `raceNow()` seam in place.
- **Conflicts:**
  - **Bus:** the plan's B1 messages are `RACE_ARMED`, `RACE_STARTED`, `RACE_BUZZER`, `RACE_RESULT` and `RACE_CANCELLED`, with no `RACE_STATE_CHANGED`. SampleRace, DR's Countdown, DR's Share arm line and DR's Preview end-on-arm all key off `RACE_STATE_CHANGED`. Either B1 adds it, or E1 maps each state change to the matching B1 message. Decide this in B1.
  - **Casts:** DR feeds sample casts into `NS.Casts.Hear/Begin/Start/Stop/Reset`. CT never lets the cast list hear a sample (`Preview.lua:14-16`); it reads `MockFights.CastsAt(plan, t)` (`Hud.lua:628`). E1 keeps CT's rule, so the sample's late casts come from the plan (see #4).
  - **Slices:** DR's `Slices.Capture(run, sec, total)` becomes CT's `Slices.Begin(id)`, `Slices.Record(id, t, player, pet)`, `Slices.Close(id)` and `MockFights.FillSlices` (`MockFights.lua:396-403`).
  - **Sim timing:** CT's sim waits `Sim.SETTLE = 2` seconds after combat; a race waits for the 2.5 s quiet.
- **DR tests:** `tests/test_sample_parity.lua` (32 cases):
  - `"...the race's messages reach the buzzer, the chat lines and the toast, and no RUN_SAVED"` (in CT: no `FIGHT_SAVED`)
  - `"...test mode's replay is silent: no race message, no chat line, no toast of its own"`
  - `"...the run joins the sample history at its start and resolves in place"`
  - `"...a held state's history is the same moment's: the board, the row and the card agree"`
  - `"...a held race reads nothing and holds no timer; the sim's timers end with it"`
  - `"...arming a real race from under a sim keeps that race's cast list"`
  - `"...a run that ended early shows Combat Ended, with no tail and no buzzer"`
  - `"...complete runs go out of combat before the read, and the hint waits for its delay"`

### #4 MockRuns: DR's 17 sample runs and the race plan
- **DR:** `MockRuns.lua`:
  - `:26-30` constants
  - `:35-40` plan variation
  - `:47-50` gear and potion
  - `:58-84` `ALTS`
  - `:91-94` `TARGETS`
  - `:106-131` `HISTORY`
  - `:145-165` `Player`, `Target`
  - `:170-300` `Plan`
  - `:304-350` `TotalAt`, `Spells`, `LiveAt`
  - `:408-418` `Usage`
  - `:424-438` `resultOf`
  - `:456-483` `Run(spec)`
  - `:489-500` `Slices`
  - `:556-577` `Dataset(opts)`
  - `:588-603` `Race(spec, runs, sets)`
  - `:608-612` `BoardBest(runs, category, length)`
- **Constants:**
  - `LENGTH = 30`, `TAIL = 3.1`, `COMBAT_END = 4.2`, `DPS = 147600`.
  - `LUCK, DRIFT_FROM, DRIFT_EVERY, SKIP, CRIT, TRAVEL = 0.16, 0.25, 0.06, 0.05, 0.25, 0.3`.
  - `FIRST_HIT = 0.05`, because the first hit starts the clock.
  - `TAIL_HITS, TAIL_GAP, TAIL_SIZE = 8, 1.5, 0.4`.
  - `GEAR_AT = 0.4`, `GEAR_EVERY = 120`, `POTION_AT = 1.2`, Healthstone `{ itemID = 5512, spellID = 6262 }`, `GEAR_CD = 120000`, `POTION_CD = 300000`.
- **Targets by category:** single is generic, with no npcID. Cleave is `243208`, dungeoneer `243167`, boss `243205`, pvp `243211`.
- **The 17 HISTORY rows**, with fields `who, cat, len, dps, ago (hours), tail, combatEnd, status, endAt, died, late, restartedAt, shared, old, loadout "b", noMajor, dry, chart, note`:
  - **Lengths:** all five preset lengths (30, 60, 120, 180, 300).
  - **Statuses:** complete, three `incomplete` (endAt 95, 41 with `died`, 212), one `lost` (`me`, single, 30), and one `old` format-2 run (pvp, 120, `restartedAt = 47.5`).
  - **Shared session:** one row (`ret`, boss, 180).
  - **Late casts:** one flagged row with `late = {{t=1.6},{t=2.3}}`, and one Warlock cleave row with `late = {{t=2.1, spellID=8690}}`, a Hearthstone the LateIgnore defaults leave uncounted.
  - **Characters:**
    - `me` is the player's own `Recorder.SnapshotPlayer()`.
    - `ret` is Sampleblade, a Retribution PALADIN, specID 70, ilvl 312.4.
    - `fire` is Mockflame, a Fire MAGE, specID 63, ilvl 309.8.
- **The plan:**
  - Hits run up to `secs + tail`. `tailHits` lands up to 8 ticks of the rotation's first damage-over-time row past the buzzer, plus a second wave for a restart.
  - `lateCasts` adds a cast at `length + t`. A late row with no spellID takes the rotation's second spell.
  - `settle` scales the hits so they add up to the damage exactly.
- **The run (`Run`):**
  - It is built on `Recorder.NewRun(length)`, which carries the race's `grace`, `restartGap` and `startSource = "meterSession"`.
  - Lost damage is 1. A shared session sets `run.race.baseline = { session = 1, damage = floor(damage * 0.14), spells = {} }` and spells DPS 0.
  - `result` is `{ damage, dps = Scoring.Dps, endedAt | tail + combatEnd, sessionDuration, meterDps }`.
- **The dataset:** `Dataset(opts)` returns `{ runs, loadouts, slices, length }`. `opts.length` re-boards the 30 s rows onto the sim's board.
- **The HUD's sample race:** `Race()` returns `{ run, plan, best = Bests.Before(run, runs) (nil when shared), delta, isNew = Bests.Delta(run, runs), dps, stopAt, early, combatAt, shared }`.
- **CT seam:** `MockFights.lua`:
  - `:31` `FIRST_HIT = 1.0`, measured from combat entry
  - `:113-114` the dummy board, `creatureID = 31146`
  - `:127-168` HISTORY, 40 rows of `{who, board, ago, len, dps}`
  - `:177-183` `Character`, the made-up hunters Samplehunter and Mockarrow
  - `:219-223` `addHit`, which drops every hit past `plan.length`
  - `:287-299` `Plan`, which takes no `secs`, `tail`, `late` or `restartedAt`
  - `:454-472` `Record`, with `status = "final"` and `sample = true`
  - `:476-491` `Dataset()`, which takes no `opts`, and `Preview.lua:207` calls it the same way for both modes
  - `:512-523` `Sample`, whose probe has no race part
  
  Owner: **E1**: the 17 race samples sit beside the fight samples, in memory only.
- **What differs:**
  - **Record shape mapping:**

    | DR run field | CT record field |
    |---|---|
    | `char` | `who` |
    | `target` | `identity` (Identity.Resolve of a dummy snapshot) |
    | `date` | `t` |
    | `result.damage` | `race.score` |
    | `result.dps` | `race.dps` |
    | `result.sessionDuration` | `duration` |
    | `result.meterDps` | `meterDps` |
    | `run.status` | `race.status` (the record's own `status` stays `"final"`) |
    | `run.flags` | `race.flags` |
    | `run.race.{grace, restartGap}` | `race.{grace, restartGap}` |
    | `result.tail / combatEnd / endedAt` | `race.tail / combatEnd / endedAt` |

  - **Lost row:** a lost race is not a race (spec §3.4), so the `lost` row has no CT counterpart. Drop it, or keep it as a plain dummy fight.
  - **`old` row:** CT has no format-2 record. Drop it, or keep it as a race with no casts, usage or stats.
  - **`race.baseline`:** not in spec §6's race part. A sample may still carry it for the shared scenario, but A3's `RaceRecord.Plain` decides whether it survives.
  - **Characters:** CT samples are the two hunters and never the player. DR's `me` is the player, and `ret`/`fire` are other classes and specs. Races are boarded by character × spec (A3), and Insights' "by character" and "by spec" sections (D2) need more than one of each. CT's rotation is hunter-only (#5), so mapping `ret`/`fire` onto hunters or giving them a second spec is the builder's call.
  - **Board kind:** CT's sample dummy is `31146`, which DR's catalog files under `"boss"` (`DpsRace/defaults/Dummies.lua:29`), so a race on CT's dummy board is boarded boss. A single-target sample needs a generic dummy with no npcID, as DR does. Also, DR's `Dummies.CategoryOf(target)` can answer `"other"`, while A2 lists five categories with none for other.
  - **Timing:** CT's `FIRST_HIT` is 1.0 s after combat entry; DR's is 0.05 s on the race clock.
  - **Plan extensions:** CT's `Plan` must grow DR's tail, late-cast and restart extensions, or E1 adds a sibling such as `MockRaces.lua`. MockFights is 523 lines.
  - **Toast and delta:** `Bests.Before/Delta` do not exist in CT (#8).
- **DR tests:** `tests/test_sample_parity.lua`:
  - `"...every sample record has the shape a race leaves"`
  - `"...the plan is deterministic: the same id, the same fight"`
  - `"...a flagged run's late cast is in its own cast list, past the buzzer"`
  - `"...a raised grace judges the sample's late casts as it would a race's"`
  - `"...the running chart and the card's are the same buckets, short of the final at the buzzer"`
  - `"...no two sample runs scale uniformly"`
  - `"...a sim's new best is not a flat factor of its history"`

### #5 MockRotations: 13 classes in DR, one hunter per client in CT
- **DR:** `MockRotations.lua:1-128` defines `NS.MockRotations[CLASS]` for WARRIOR, PALADIN, HUNTER, ROGUE, PRIEST, DEATHKNIGHT, SHAMAN, MAGE, WARLOCK, MONK, DRUID, DEMONHUNTER and EVOKER.
  - Row fields: `id, hit, from` (negative means a pre-pull cast heard while armed), `every, cd` (ms), `ticks + gap, pet, passive, major, alt, main, none`.
  - `Plan` picks `ROTATIONS[o.class] or ROTATIONS.WARLOCK`.
- **CT seam:** `MockRotations.lua:1-58` defines one table, `NS.MOCK_ROTATION`, picked at file scope per client: a Beast Mastery hunter and its pet. Its rows carry `echo`, `use + item + slot` and `passive`. Owner: **E1**.
- **What differs:**
  - CT has no `alt`/`main`, which is DR's loadout b swap. CT's sample gear is inline and it interns no talents.
  - CT has no negative `from` (pre-pull casts).
  - Race samples on CT's one rotation work without porting the 13 classes. The "player draws their own class's rotation" behavior goes away; that is the builder's call (spec §11).
- **DR tests:** `tests/test_sample_parity.lua` `"sample parity: the player draws their own class's rotation; every class has one"`. Drop it or rewrite it.

### #6 Sim: DR's eight race scenarios and their stepper
- **DR:** `Sim.lua`:
  - `:26-42` `SCENARIOS`
  - `:43-58` constants
  - `:63-74` `ValidStepDelay`, `StepDelay`
  - `:97` `Dataset()` = `MockRuns.Dataset({ length = Sim.LENGTH })`
  - `:99-119` `combatEnd(s)`, `Sample(key, dataset)`
  - `:127-158` `finish`, `beat`, `launch`
  - `:170-202` `STEP_MOMENTS`, `timeline`
  - `:209-222` `Gate`
  - `:239-276` `prepare`, `newSession`
  - `:279-333` session hooks
  - `:348-387` `Open`, `Enter(key, data)`, `Finish`, `Cancel`, `Diagnose`
  - `:390-392` `Usage`
- **The eight scenarios**, as key, label, then the fields:
  - `newbest` "New best": factor 1.04, tail 3.1, combatEnd 4.2.
  - `behind` "Behind the best": factor 0.93, tail 2.4, combatEnd 5.2.
  - `first` "First race": category `"boss"`, tail 1.8, combatEnd 3.6. No factor; it uses `MockRuns.DPS`.
  - `incomplete` "Incomplete": factor 0.96, status incomplete, endAt 9.
  - `died` "You die": factor 0.90, status incomplete, endAt 6, died.
  - `flagged` "Late cast": factor 0.98, tail 2.8, combatEnd 4.6, `late = {{t=1.4}}`.
  - `shared` "Shared session": factor 0.99, tail 3.4, combatEnd 4.8, shared.
  - `sticky` "Combat holds on": factor 0.97, tail 2.6, sticky. Its combatEnd is `race.hintDelay` (default 15) + `STICKY_EXTRA` (3), so 18.
- **Constants:**
  - `DEFAULT = "newbest"`, `LENGTH = 15` (an imaginary 0:15 board, not a preset), `ARM_HOLD = 3`, `RESULT_HOLD = 4`, `STICKY_EXTRA = 3`.
  - `TICK = 0.05`, on a `C_Timer.NewTicker`.
  - `STEP_DELAY` is the setting `sim.stepDelay` (default 1, range 0.5..10, step 0.5; `DpsRace/settings/Race.lua:127`).
- **Steps:** Armed (`Unpark(StepDelay())`), Race starts (`Skip(0)`), "Racing (%d s)", "Buzzer" (or "Combat ends" for an early end), "Result card" (`SkipToResult`), "Results window".
- **Gate lines:**
  - `"The race is still running."`
  - `"Waiting for the result."`
  - `"Waiting for the result (combat holds on)."`
  - `"The result card holds."`
- **Session:** the panel title is `"DPS Race - SIM"`, anchored to `Hud.Frame()`, with `PANEL_NAME = "DpsRaceSimPanel"`.
- **CT seam:** `Sim.lua`:
  - `:34-42` five scenarios: `newbest`, `behind`, `first` (board salhadaar), `short` (22 s), `lost`
  - `:43-53` `BOARD = "vorasius"`, `LENGTH = 45`, `SETTLE = 2`, `RESULT_HOLD = 4`, `TICK = 0.25` on an AceTimer, `STEP_DELAY = 1.5` (a constant; there is no setting)
  - `:108-129` `endFight` → `Filters.Passes`
  - `:168-177` `launch`
  - `:186-221` steps and `Gate`
  - `:245-272` one `lib:New` session named `"CombatTrail"`
  - `:301` `PANEL_NAME = "CombatTrailSimPanel"`
  - `:358` `Enter(key)`, which takes no dataset
  - `:374-376` `Diagnose`
  
  Owner: **E1**.
- **Conflicts:**
  - **Key collision:** `newbest`, `behind` and `first` exist in both. The race eight need distinct keys (a `race-` prefix, for example) or a sub-grammar. Spec §8 says only "the sim gains DPS Race's eight race scenarios"; flag the choice in E1.
  - **One session:** CT has one library session whose `scenarios.names/defs` are fixed at `newSession()`. The race defs must be added at file scope only on Retail (`ForClient({"retail"})`), each with its own `timeline` function. The library allows one timeline per def, and the race's steps differ from the fight's. `Gate` and `STEP_MOMENTS` must branch on the scenario's kind.
  - **Saving:** race samples skip `Filters.Passes`, following A3's rule. A 15 s race is saved even though `minLength` is 30, which is CT's `short` scenario in reverse.
  - **Timer:** port the clock to AceTimer (the stand-down's `CancelAllTimers`). CT's 0.25 s beat can land the buzzer up to 0.25 s late. DR pins one countdown number a second, and the Countdown runs its own timers, so either keep 0.25 or use a faster race beat.
  - **Step delay:** `sim.stepDelay` is not in CT. Keep CT's constant 1.5, or add the setting, which needs a schema row.
  - **Panel anchor:** DR anchors the panel to the HUD, which was DR's race window. CT may anchor it to `RaceWindow` for race scenarios.
  - **Diagnose phase:** DR reads `Hud.Diagnose().body`; CT's phase is its own variable.
- **DR tests:** `tests/test_sim.lua` (31 cases):
  - `"sim race: an imaginary 15 s race on a 0:15 board, its history beside it (R5-DR2)"`
  - `"sim race: the gate holds the buzzer, then the read, then the card's hold (R5-DR2)"`
  - `"sim race: sticky's wait says combat holds on (R5-DR2)"`
  - `"sim: shared draws no chart and no pace bar, live or on the card"`
  - `"sim: flagged shows the late cast after the buzzer and on the card"`
  - `"sim: incomplete and died end before the buzzer and read out of combat"`
  - `"sim stepper: an early end has no buzzer step, and switching scenarios restarts the session"`
  - `"sim stepper: the race holds armed until a step is played, then counts down (SG-DR-1)"`
  - `"sim stepper: the Armed countdown is the step delay, so Race starts lights as it ends (SG-SIM)"`
  - `"sim: the sample card's Delete asks, leaves the sample history and goes to the Arm screen"`
  
  Also `tests/test_sim_checkbox.lua` (10 cases; CT already has its own Sim mode box).

### #7 Results_Source: the sample seam's surface
- **DR:** `Results_Source.lua:39-45` (`changed` also calls `NS.Hud.SampleChanged()` when not swapped), `:58-69` (`Use`: `{runs, loadouts, slices}`), `:84-96` (`Put`), `:119-121` (`Invalidate`), `:125-134` (`Board(opts{cleanOnly})`, cached per cleanOnly), `:137-150` (`LoadoutOf`, `GearChanged`), `:153-155` (`ChartView`).
- **CT seam:** `Results_Source.lua:57-68` (`Use`: `{fights, slices}`), `:83-95` (`Put`), `:119-126` (`IsBest`), `:131-144` (`BestFor(record, exclude)`), `:161-165` (`Touched`). Owner: **E1**. D1 also reads it.
- **What differs:**
  - CT has no clean-only board on the mock. A3's `Bests.CleanFor(record)` and D1's "only bests" and "hide flagged" filters need a mock-aware `Source.CleanFor`, or a `records` argument.
  - `Source.IsBest/BestFor` compute `NS.Bests.Key(record)` and `Bests.Compute(mock.fights)`. If A3 keeps race boards in a separate `Bests.RaceKey` rather than making `Key` pick the race key, a sample race lands on the dummy's fight board. Both must use one chooser.
  - CT has no `Hud.SampleChanged`. A sample result card over a deleted sample needs a `RaceWindow` hook in `changed(false)`.
  - CT has no `Invalidate` for a late-cast ignore edit while the mock is on.
- **DR tests:** `tests/test_preview.lua` `"preview: a note or a delete changes the sample in memory; Save view and Share refuse"`; `tests/test_sample_parity.lua` `"...a change to the sample history reaches the card, as RUNS_CHANGED does a real one"`.

### #8 Bests in the sample context: `Before`/`Delta` and where the history comes from
- **DR:** `Bests.lua:22-27`: `history(runs)` returns `ResultsSource.All()` while `IsMock()`. `:82-93`: `Board(opts)` defers to `Source.Board`. `:118-126`: `Bests.Before(run, runs)` is the best before it, by date then id. `:134-142`: `Bests.Delta(run, runs) -> pct, isNewBest, prev`, where a first run is `nil, true, nil`.
- **CT seam:**
  - `Bests.lua:95-108`: `For(record, exclude)` returns the runner-up excluding the record, not the best before it in time.
  - `Hud.lua:234-244`: `judge` swaps in `ResultsSource.IsBest/BestFor` for a sample.
  - CT has no `Before`/`Delta`, but C2's interface consumes `NS.Bests.Before/Delta`.
  
  Owners: **A3/C2** define them, **E1** makes them mock-aware.
- **What differs:**
  - CT's rule is that callers pick the source; Bests itself never reads ResultsSource. Keep that: `Before/Delta` take a `records` argument, and the sample paths pass `Source.All()`, as DR's `MockRuns.Race` does.
  - `Hud.PaceRecord`'s sample probe (`Hud.lua:207-211`) carries no `race`. C3/E1 must add it, or a sample race paces on the fight board.
- **DR tests:** `tests/test_preview.lua` `"preview: the detail's Delta box and New best badge read the sample history's Runs view"`.

### #9 Share: one line shape for a fight and a race
- **DR:** `Share.lua:59-71`: `Share.Line(run)` is nil unless the status is complete or incomplete. The format is `"DPS Race %s · <targetText> · <spec ilvl> · <damage> · %s DPS[ · incomplete] (Ka0s DPS Race)"`, with `targetText` from `Dummies.Label(category)` or an uncataloged target's own name. `:96-108`: `Messages`, gated by `share.talentsLink`.
- **CT seam:** `Share.lua:108-118`: `lineWith` builds `"Combat Trail · <Against> · <Format.Length(record.duration)> · <%s DPS of record.dps> · <spec ilvl> · top: …"`. `:150-156`: `Line` requires `record.status == "final"`. `:141-143`: `results.shareTalents`. Owner: **C2** (spec §9).
- **What differs:**
  - For a race, the length shown must be `race.length` and the DPS `RaceRecord.Dps(record)`. An incomplete race needs the `incomplete` word.
  - The `"DPS Race"` and `"(Ka0s DPS Race)"` words go, under the Words rule.
  - `Against(record)` already names the dummy through `ResultsFights.TargetName`. The race kind could replace the difficulty slot.
  - DR's user-facing strings say "run": `"This run has no score to share."`, `"Whisper this run to:"`, `"You can share a run once you are out of combat."`. CT's words are "fight". Do not port DR's strings.
- **DR tests:** `tests/test_share.lua`:
  - `"share: Share.Line matches the mockup format"`
  - `"share: the target type is named; an uncataloged target by its own name; incomplete is said"`
  - `"share: a lost run has no line, and the prompt says so"`
  - `"share: no chat escape survives into the line"`
  - `"share: the chat sender and the number formatter are reached only through NS.Compat"`

### #10 The race's chat lines: armed, result, lost
- **DR:** `Share.lua`:
  - `:235-238` `ArmedLine(run)`: `"Armed: %s on %s. First hit starts the clock."`, with the length from `Format.Length(run.race.length)` and `targetName(target)` (`:43-46`).
  - `:240-247` `deltaText(delta, isNew)`: `"new best (+%.1f%%)"`, `"new best"` or `"%+.1f%% vs best"`.
  - `:255-270` `ResultLine(run, delta, isNew)`: `"%s damage · %s DPS in %s on %s"`, then `" — "` and a `" · "`-joined tail made of the delta text, the late casts (`"1 late cast"` or `"%d late casts"`, counting only `#Scoring.SplitLate(run)`, so ignored spells never count), `"incomplete"`, and `"tail +%.1fs"` when `result.tail` is a number.
  - `:272-281` `onResult`: on a lost run, prints `"Couldn't read the result: the run is kept as lost."`. The delta is taken only when the status is `complete`, through `Bests.Delta(run)`.
  - `:283-291` bus: `RACE_STATE_CHANGED` to ARMED prints `ArmedLine`; `RACE_RESULT` calls `onResult`.
- **CT seam:** CT has nothing; `Share.lua:5-6` says "no armed line, no score line". Add the lines in `Share.lua` (294 lines). Owner: **C2**. E1's sim must reach them through the real receivers.
- **What differs:**
  - **Armed line timing:** the plan has `RACE_ARMED(race)` where DR used the ARMED state change. At arm there is no fight record yet, so the target name must come from the race's own target snapshot at arm.
  - **Lost:** `RACE_RESULT(record)` never fires for a lost race, because a lost race is not saved. The lost line moves to `RACE_CANCELLED(reason)`, and its wording must drop "run".
  - **Inputs:** the result line reads `record.race.score` and `record.race.dps` (or `RaceRecord.Dps`), `race.tail`, `race.status`, the target from `identity`, and `RaceScoring.SplitLate`.
  - **Scope:** the lines stay race-only (spec §8) and Retail-only.
  - **Samples:** a held sample is silent (#3). A sim sample must print, because DR's parity test pins it.
- **DR tests:** `tests/test_share.lua`:
  - `"share: arming prints the armed line with the length and the target"`
  - `"share: a result prints the score line with the delta, the flags and the tail"`
  - `"share: the score line counts only the late casts the ignore list leaves (#8)"`
  - `"share: the race's own result is printed once, when it resolves"`
  
  Also `tests/test_sample_parity.lua` `"...the race's messages reach the buzzer, the chat lines and the toast, and no RUN_SAVED"`.

### #11 Toast and countdown hooks for test mode and the sim
- **DR:** `BestToast.lua:344` (`if run.sample then sampleKey = run.id end`), `:366` (`BestToast.ShowPreview(sample)`), `:373` (`BestToast.EndPreview()`). `Preview.lua:111, 182, 218, 235` call them. `Countdown.lua:28-29, 265`: the countdown reads `NS.SampleRace` while it runs, and a frozen test race counts nothing. `Preview.lua:141`: `stopSim` calls `NS.Countdown.Refresh()`.
- **CT seam:** CT has nothing; C2 creates `modules/Countdown.lua` and `modules/BestToast.lua`. E1 wires `ShowPreview` into the race test start, `EndPreview` into stop and suspend, and `Countdown.Refresh` into the sample's clear.
- **What differs:**
  - C2's fight toast (`toast.fights`, both clients) has no sample path. A CT test-mode toast preview for a fight is optional.
  - On Forever, race previews are absent.
- **DR tests:**
  - `tests/test_toast.lua:273` `"toast: test mode holds the sample race's toast, and its end takes it down"`
  - `:291` `"toast: Test toast queues a sample that runs its course, and a second click replaces it"`
  - `:311` `"toast: a real toast never moves; in test mode or as a sample it drags"`
  - `tests/test_countdown.lua:251` `"countdown: the sim runs the real marks in its running phase, cue included, and they stop with it"`
  - `:269` `"countdown: the sim race's buzzer clears it, the setting holds in the sim, and still test mode shows none"`

### #12 AutoArm and the sample guard
- **DR:** `AutoArm.lua:220`: `if type(run)=="table" and run.sample then return end`.
- **CT seam:** B3's `modules/AutoArm.lua`. E1's sample `race` part (or its run) must carry `sample = true` so that AutoArm and Preview's end-on-arm skip it.
- **DR tests:**
  - `tests/test_autoarm.lua:236` `"autoshow: test mode's window stays test mode's, and its end is no close by the player"`
  - `:309` `"autoarm: no arm over a result card, nor in test mode"`
  - `tests/test_sample_parity.lua` `"...a sim neither ends itself on its own arm nor arms AutoArm's rule"`

### #13 Diagnostics: the race section
- **DR:** `Diagnostics.lua:31-59`, in one `"state"` section:
  - `race state=%s run=%s session=%s pending=%s meter=%s`, from `Race.State()`, `run.id`, `run.race.sessionID`, `#Recorder.Pending()` and `Meter.IsAvailable()`
  - `countdown shown=%s scheduled=%s owner=%s`
  - `test active=%s mode=%s phase=%s scenario=%s ticking=%s`
  - `toast shown=%s waiting=%s key=%s preview=%s`
  - `results tab=%s mode=%s rows=%s selected=%s`
  
  `:21-22` identity: `schema stored=%s code=%s runFormat=%s`.
- **CT seam:** `Diagnostics.lua`:
  - `:66-72` `fight` (`fight state=%s id=%s session=%s meter=%s chart fights=%s`)
  - `:74-84` `windows`
  - `:86-91` `preview`
  - `:99-110` `Sections()` order: identity, settings, store, lanes, fight, windows, preview, rejected
  - `:22-26` `down(out)` for a stood-down addon
  
  Owner: **E1** (plan: "a race section: state, pending races, board count").
- **What differs:**
  - Insert a new section, such as `"race"`, after `fight`. It carries:
    - the race state, the race's fight id and session;
    - the count of `db.global.pendingRaces` (B2), replacing DR's `Recorder.Pending()`;
    - the race board count;
    - the countdown and toast lines (C2's `Diagnose`);
    - the Race window's shown/attached state (C1).
  - On Forever the section is absent or prints one line; follow clients-§4 and pin both profiles.
  - Stood down, it calls `down(out)`.
  - The preview line's phase must name the race state when a race sample is held.
  - CT's `tests/test_diagnostics.lua:35` `"diagnostics: the report carries every section of this addon's own"` pins the section list, so it changes with the new section.
- **DR tests:**
  - `tests/test_race.lua:915` `"race: the diagnostics state section names the race state, run, session and pending count"`, which expects `race state=running run=<id> session=25 pending=1 meter=true`
  - `tests/test_countdown.lua:310` `"countdown: the diagnostics state section names what it shows and holds"`, which expects `countdown shown=6 scheduled=5 owner=race`
  - CT's own: `tests/test_diagnostics.lua:56` `"diagnostics: test mode shows in the preview line"`, `:75` `"diagnostics: the report arms no timer and registers no event"`

### #14 Which DR suites port where
- **E1, adapted onto CT's fixtures:**
  - `tests/test_preview.lua`: the race-state cases only. The Results and Insights cases already have CT equivalents, or belong to D1/D2.
  - `tests/test_sim.lua`: the `sim race:` and `sim stepper:` cases, and the eight scenario behaviors. The CT `tests/test_sim.lua` fight cases stay.
  - `tests/test_sample_parity.lua`: the race-shape, late-cast, silence and message cases. Drop the class-rotation and loadout-b cases, which assume DR's samples (#4, #5).
  - CT's `tests/test_diagnostics.lua` is extended for the race section.
- **C2:** `tests/test_share.lua` (the armed, result, ignore-list and printed-once cases), the `tests/test_toast.lua` preview cases and the `tests/test_countdown.lua` sim cases.
- **Every Retail-only surface** (the `race` sub-verb, the race scenarios, the race section) needs a present test under the default profile and an absent test under `KA0S_KIT_CLIENT=forever`.
- **Kit fixtures DR's suites lean on:**
  - `tests/race_clock.lua`, which drives `GetTime`;
  - `tests/mock_meter.lua`, which CT also has;
  - the sim library's session through `NS.SimLib` / `NS.SimSeam`, which both use.
  
  CT has a `tests/hud_fixture.lua`; DR has none. CT has no `race_clock.lua`, so E1 needs one, or uses CT's `now` parameter on `Sim.Beat(now)` (`Sim.lua:133`).

## tests

Source: DR `docs/test-cases.md` at f8078c7. It lists 102 suites and 1509 cases (plus 1 skipped). 94 of those suites are DR's own files in `tests/` (1412 cases). The other 8 are kit suites in `tests/_kit/` (97 cases): `test_skin_values` 3, `test_skin_switch` 45, `test_client_globals` 3, `test_eol` 2, `test_prose` 15, `test_layout_cap` 13, `test_diagnostics_contract` 8, `test_lizard_sighted` 8. CT already runs the same 8 from its vendored kit (CT `tests/run.lua:159-168`), so none of them is ported. New CT suites are added to the `SUITES` list at CT `tests/run.lua:107-158`, and each needs a `docs/test-cases.md` regeneration.

"(tc:N)" below is the line of the suite's heading in DR `docs/test-cases.md`. "Port" names the cases that move. The rest of a suite is DROP because CT already covers that code. Case names are quoted exactly so they can be grepped in DR `tests/test_*.lua`.

### #1 Fixture: `tests/race_clock.lua` (the race suites' clock and drivers)
- **DR:** `tests/race_clock.lua` (226 lines).
  - `installClock(M)` (:20-84) replaces the instance's `C_Timer.NewTimer`/`NewTicker` with handles that are due at `GetTime()+delay`. `advance(dt)` and `to(t)` fire due callbacks in time order, and push each handle onto `M.__timers` marked `cancelled` once it has fired or been canceled.
  - `listen(NS)` (:87-104) records `RACE_STATE_CHANGED (run, from, to)`, `RACE_BUZZER`, `RACE_RESULT`. `F.trail` (:107-113) gives `"from>to,..."`.
  - `F.SESSION` (:116-123) is probe run 8: damage 1539711, dps 39479.8, duration 39, spells 29722/116858/348.
  - Methods (:127-164): `now`, `to`, `advance`, `arm(length=30, count)`, `start(sessionID=25)`, `update(sessionID)`, `combatEnd()`, `stored(id)`, `reads()` (counts `GetCombatSessionFromID`), `trail()`. `start` calls `Race.OnCombatStart/OnSessionCreated/OnMeterUpdate` directly; `combatEnd` calls `Race.OnCombatEnd`.
  - `F.new{enable, mutate}` (:170-189) sets the clock to 100 and `NS.db.global.history.keepDays = 0`.
  - `F.findSecret(v)` (:197-209) gives the path of the first secret key or value.
  - `F.storedRun(fields)` (:211-224) builds a DR-shaped pending run: `race = {length=30, grace=1.0, restartGap=6, startSource="meterSession", sessionID=25, startedAt=100}`.
- **Used by** 30 suites: autoarm, bests, chart, chart_icons, countdown, disabled, hud, hud_best, hud_hint, hud_layout, hud_sizing, hud_tiles, hud_tips, hud_window, layers, loadout, pace, perf_harness, preview, race, race_resume, sample_parity, settings, share, sim, sizing, skin_flip, slash, toast, usage.
- **CT seam:** `tests/hud_fixture.lua`.
  - `H.fresh{pet, mutate}` (:16-34) uses a boar target `H.BOAR_GUID` (:12).
  - It drives the real Fight state machine through events: `H.enter` (:51), `H.leave` (:58), `H.hit` (:65, fires `DAMAGE_METER_COMBAT_SESSION_UPDATED`), `H.run` (:71), `H.start/tick/finish/whole` (:77-106), `H.cast` (:108).
  - Its timers fire through the kit's `M.__fireTimers()` (`tests/_kit/mock_record.lua:118`). That fires everything queued at once and has no due time.
- **Differs:** CT has no timed clock, so a buzzer at `length`, the quiet of 2.5 s or the poll cannot be pinned.
  - B1 should create **`tests/race_fixture.lua`**: DR's `installClock` and `listen` on top of `hud_fixture`'s event steps, with a dummy target (creature 31146) instead of the boar.
  - The drivers must fire events (`PLAYER_REGEN_*`, the meter session events) rather than call `Race.On*`, because CT's Race consumes `FIGHT_STARTED/TICK/ENDED` (plan B1).
  - `F.storedRun` becomes a CT fight record with a `race` part (A3's shape). `keepDays` becomes CT `profile.history.days`/`keepBests` (`defaults/Profile.lua:193`, `days = 7, keepBests = true, maxFights = 500`).
  - `F.findSecret` ports as is (A3, B1, B2).
- **Owner:** B1 creates it. B2, B3, C1, C2 and E1 reuse it.

### #2 Fixture: `tests/mock_widgets.lua` (the HUD widget recorder)
- **DR:** `tests/mock_widgets.lua` (264 lines). Every font string and texture is its own recorded object (`__text/__value/__min/__max/__texture/__scale`), with a geometry spy (`W.SecretGeometryReads` :251) and `W.NewAnimationGroup` (:191).
  - Client seams: `C_Spell.GetSpellName/GetSpellTexture` (secret-aware), `IsPlayerSpell` over `W.known`, `SOUNDKIT = {RAID_WARNING=8959, UI_BATTLEGROUND_COUNTDOWN_TIMER=25477}`, `PlaySound` into `W.sounds` (:238), `RaidWarningFrame`, `ChatTypeInfo.RAID_WARNING`, `RaidNotice_AddMessage` into `W.notices` (:241), `W.SoundTimes(id)` (:244).
  - Used by 53 suites (every HUD, Results and toast suite).
- **CT seam:** the kit's opt-in `tests/_kit/mock_paint.lua`, installed by `hud_fixture.lua:10,20`. It records paint (textures, font strings, backdrops, StatusBars) but has no sound log, raid-warning log, animation group or geometry spy. CT's `tests/_kit/mock_base.lua:378` `PlaySound` is a no-op.
- **Differs:** C2's countdown and toast ports need sounds, notices and animation groups. C1's "reads no geometry" cases need the geometry spy. Port the sound, notice and animation parts as a small CT fixture (for example `tests/race_widgets.lua`, installed from `mutate` after `mock_paint`). Do not port the region layer `mock_paint` already gives.
- **Owner:** C2 (sounds, notices, animation). C1 (geometry spy, if its tiles and hint cases are kept).

### #3 Fixture: `tests/wow_mock.lua` fakes DR has and CT lacks
- **DR:** `tests/wow_mock.lua`:
  - `MenuUtil` and `__menus`/`__lastMenu` (:107-~190): records context-menu entries for late-ignore and row menus.
  - `C_Map.GetBestMapForUnit` (:205) and `C_Map.GetPlayerMapPosition` over `__context.mapX/mapY` (:400-404).
  - `C_Timer.NewTicker` (:336-354): the race's read poll.
  - `__target` and `__setTarget{guid, name, level, classification}` (:357-361).
  - `__plates`, `__plateOrder`, `__setPlate(unit, t)` and `C_NamePlate.GetNamePlates` (:363-381).
  - `unitField` (:382-387) behind `UnitGUID`, `UnitName`, `UnitLevel`, `UnitClassification`, `UnitHealthMax`, `UnitCreatureType`, `UnitIsPVP`, `UnitFactionGroup`, `UnitReaction` (:388-399).
  - Also `UnitRace`, `GetSpecializationInfo(ByID)`, `__specs`, `GetBuildInfo`, `RAID_CLASS_COLORS`, `CLASS_ICON_TCOORDS`, `LOCALIZED_CLASS_NAMES_MALE`, `GetWeaponEnchantInfo`, `__baseCooldowns`.
- **CT seam:** CT `tests/wow_mock.lua` (311 lines) addresses units through `__unitExists/__unitGUIDs/__unitNames/__unitLevels`, as `hud_fixture.lua:21-23` does. It has no `C_NamePlate`, `MenuUtil`, `NewTicker`, `UnitHealthMax`, `UnitCreatureType`, `UnitReaction` or `UnitIsPVP`.
- **Differs:** each porting task adds its fakes to CT `tests/wow_mock.lua`, keyed on CT's `__unit*` tables, not DR's `__target`:
  - A2: `UnitHealthMax`, `UnitCreatureType`, `UnitIsPVP`, `UnitFactionGroup`, `UnitReaction`, `C_Map.GetPlayerMapPosition` (dummy capture).
  - B3: `C_NamePlate` and `__setPlate` (auto-show).
  - B1: `C_Timer.NewTicker`, if Race polls.
  - D1: `MenuUtil` only if the late-cast menu goes through the client menu rather than LibKa0s `W.ContextMenu`.
- **Owner:** A2, B1, B3, D1 (as listed).

### #4 Fixtures: `tests/mock_meter.lua`, `tests/mock_formatter.lua`
- **DR:** `tests/mock_meter.lua` (222 lines). API: `CallsTo`, `GetAvailableCombatSessions`, `GetCombatSessionFromID`, `GetCombatSessionFromType`, `GetCombatSessionSourceFromID`, `GetCombatSessionSourceFromType`, `IsAddOnRestrictionActive`, `IsDamageMeterAvailable`, `Remove`, `RemoveSession`, `SetAvailable`, `SetCurrent`, `SetPlayerGUID`, `SetRaise`, `SetSealed`, `SetSecret`, `SetSession`. `tests/mock_formatter.lua` (86 lines) has the "floor" and "raw" modes; `test_format` and `test_hud` use it.
- **CT seam:** CT `tests/mock_meter.lua` (292 lines) is a strict superset (adds `GetSessionDurationSeconds`, `ResetAllCombatSessions`, `SetPetGUID`, `SetRaiseFor`). It is exposed as `T.mockMeter` (CT `tests/run.lua:183`). CT `tests/mock_formatter.lua` (118 lines) adds "rule", `userdata` and `secretRaises`.
- **Differs:** none blocking. Port the race suites onto CT's copies unchanged. A meter reset that should make a race lost (`test_race` "meter reset while running -> lost") uses CT's `ResetAllCombatSessions` or `RemoveSession`.
- **Owner:** B1, B2 (meter). C1 (formatter, for live figures in the Race window if any).

### #5 Fixtures: `tests/skin_surfaces.lua` and `Kit.skinValues` rows
- **DR:** `tests/skin_surfaces.lua` (184 lines). Its race-specific surfaces (:132-160) are the HUD body's Cancel button (`b.w.cancel`), the pace bar's track, behind half and tick (`pace().track/behind/tick`), the run detail's flags box (`detail.w.flags`) and the timing strip's segment (`detail.w.segA`). Its fixture run (:50-53) is a `cleave` dummy run.
  - DR `tests/run.lua:268-276` `Kit.skinValues` waives `modules/Countdown.lua` `"Countdown.TEXTURE ="` and `"Countdown.GLOW ="` (cause `A6`, Blizzard's BigGold digit art).
- **CT seam:** CT `tests/skin_surfaces.lua` (153 lines) builds one test-mode instance, and `tests/test_skin_surfaces.lua` (5 cases) holds it to every window. CT `tests/run.lua:202-207` `Kit.skinValues` has only the `Results_Timeline.lua` `local DISC =` row.
- **Differs:**
  - C1 adds Race window surfaces (shell, Cancel or Stop Now, pace bar parts) to CT `tests/skin_surfaces.lua` and to `test_skin_surfaces`'s coverage.
  - D1 adds the race detail's flags box and timing segment.
  - C2 **must** add DR's two Countdown rows to CT `Kit.skinValues`, or `test_skin_values` fails once `modules/Countdown.lua` lands.
- **Owner:** C1, C2, D1.

### #6 Helpers outside the gate: `tests/prose_waivers.lua`, `tests/perf.lua`
- **DR:** `tests/prose_waivers.lua` (18 lines) waives the word `cancelled` per file for `wow_mock.lua` and `race_clock.lua`, because the kit's timer survey reads AceTimer's `cancelled` field. `tests/perf.lua` (320 lines) is the offline scenario runner (performance-§9), outside the green gate. Its `raceEvent` bucket is DR `Watchers.lua`'s DamageDone handler while RUNNING.
- **CT seam:** CT has neither file. CT's `test_prose` runs from the kit (`tests/run.lua:160`).
- **Differs:** if B1's `race_fixture.lua` (#1) spells `cancelled`, B1 also creates CT `tests/prose_waivers.lua`, waiving that one word per file. A race perf scenario is optional (E1, diagnostics). Never put it in the gate.
- **Owner:** B1 (waiver). E1 (perf, optional).

### #7 A2: training dummies in the core (target `tests/test_dummies.lua`)
| DR suite (tc) | Cases | Port |
|---|---|---|
| `test_dummies.lua` (tc:65) | 5 | all. DR has **six** categories, `{ "single","cleave","dungeoneer","boss","pvp","other" }` (DR `defaults/Dummies.lua:16`). The plan's `CategoryOf` lists five, so decide where `other` lives. |
| `test_dummy_list.lua` (tc:73) | 23 | Parse/Normalize/row/Add/Remove/built-in off-on/Reset-profile/CategoryOf/Infer/CategoryFor/Read+Capture/sealed field/Resolve/captured name (14 cases). The 6 `targetdummy:` cases go to `/ct dummy` here, renamed from `/dr targetdummy`, including "answers while the addon is disabled". "auto-arm sees it" goes to B3; "the idle HUD's unknown-target warning follows the list" to C1; "a stored run moves boards when its creature is added" and "switching a built-in off sends its runs to Other" to A3. |
| `test_recorder.lua` (tc:99) | 22 | only "SnapshotTarget parses npcID ... categorizes known dummies", "... unknown targets as other", "on a player or with no target is other", "tolerates a secret GUID", "fills a sealed field from the prior snapshot". These go to CT `tests/test_identity.lua`. The rest is DROP (CT `test_record` 18, `test_identity` 47). "NewRun copies grace and restartGap" and "NewRun uses the shipped defaults (grace 1.0, restart gap 6)" go to B1; "Pending returns running and stopping only" and "Pending holds only the logged-in character's runs" to B2. |
| `test_refactor_pins.lua` (tc:1412) | 4 | "Resolve answers the lowest ID a name is captured under, and refuses an ID past MAX_ID" and "the capture line names each part it has". The two skin pins are DROP. |
| `test_settings.lua` (tc:1158) | 38 | "Race's Training dummies tab: the blurb, Add your target, your list, the built-ins, Reset list" and "Race repaints when your training dummies change". Both are retargeted to CT's **History** page and asserted on both kit profiles. The rest goes to B3 or DROP (#10). |

CT seam: CT `defaults/Dummies.lua:22` already defines **`NS.Dummies = { Retail = {...}, Forever = {} }`** (7 Retail IDs: 31146, 65310, 67127, 114832, 126781, 131983, 131989), plus `NS.DUMMIES` (:72) and `NS.DummyName(creatureID)` (:78). CT `tests/test_identity.lua:303-338` pins them ("identity: the dummy list is picked once, per client; Forever's is empty by decision" asserts `next(NS.Dummies.Forever) == nil` and `NS.Dummies.Retail[31146]`). **Conflict:** A2's module `NS.Dummies.Lookup/Name/CategoryOf/...` takes the same name. A2 must rename the seed tables (for example `NS.Dummies.SEED.Retail`) and update `test_identity.lua:303-338` in the same commit. Fakes: #3.

### #8 A3: the race part, schema 4, race boards (target `tests/test_race_record.lua`, extend `tests/test_bests.lua`, `tests/test_retention.lua`)
| DR suite (tc) | Cases | Port |
|---|---|---|
| `test_bests.lua` (tc:149) | 21 | "Key is specID\|category\|length" (becomes CT's `"race:"..kind..":"..length` with character and spec), "incomplete and lost never count", "the highest result.dps holds the board; a tie keeps the earlier run", "cleanOnly excludes flagged", "two Dungeoneer npcIDs share one board", "spec, category and length each split the board", "deleting a best promotes the next run", "the cache is invalidated by RUN_SAVED and keeps cleanOnly apart" (on `FIGHT_SAVED`), "a run flagged only by an ignored spell joins the clean board, and leaves it on Unignore" (needs B1's LateIgnore, so it may land in B1), "Delta reports new best and percentage vs previous best", "Delta ignores later runs, other boards and runs that never count", "Delta defaults its run list to the store", "HoldingIDs names the holders of the all-runs and the clean-only boards" (13). The 8 prune cases ("prune days=0 ...", "prune keeps best-holding runs", "prune never removes a running or stopping run", "prune runs on RUN_SAVED with ... keepDays", "never removes the run just saved, nor the race's own run", "a raced run that lands below the best survives the prune its own save fires", "prune runs at OnEnable", "no prune and no cache work while disabled") go to CT `tests/test_retention.lua` as race-record cases. CT `Retention` already owns the purge; DR's `keepDays` default of 90 is DROP in favor of CT's `days = 7`. |
| `test_dummy_list.lua` (tc:73) | (2 of 23) | "a stored run moves boards when its creature is added, and back when removed" and "switching a built-in off sends its runs to Other". **Conflict:** DR resolves a run's board category from the *live* list at read time (`CategoryOf reads a stored target by its creature as the list is now`), but A3 stores `race.kind` at save. Choose either (a) derive the kind at read from `target.creatureID` through `NS.Dummies.CategoryOf`, which keeps DR's behavior, or (b) freeze it, and then drop these two cases explicitly. |
| `test_loadorder.lua` (tc:1692) | 4 | DROP (CT `test_loadorder` 4). The one race case, "the hearthstones load before the ignore list, and the ignore list before its readers", goes to B1. |

CT seam: CT `tests/test_bests.lua` (10 cases; `bests: best per character×spec×boardKey` :35, `For with exclude answers the runner-up` :54, `the character key carries the client` :144). CT `tests/test_retention.lua` (13; `retention: purge removes >7 days except bests` :55). Plan cases: "race record: a complete race is saved however short", "a cancelled race saves the pull as a plain dummy fight under the normal filters", "a lost race is not a race", "no secret reaches the race part" (uses `F.findSecret`, #1), "database: schema 3 records load unchanged under 4".

### #9 B1: race engine, scoring, timeline, late ignore (target `tests/test_race.lua`, `tests/test_race_scoring.lua`, plus `tests/test_late_ignore.lua`)
| DR suite (tc) | Cases | Port |
|---|---|---|
| `test_race.lua` (tc:201) | 58 | Port the lifecycle on `race_fixture` (#1): the arm refusals (in combat, pending, a stored run pending, meter unavailable, length outside 10 s-15:00), clock start and first-hit adoption, "a pull that continues a session from before the arm is adopted, flagged and netted" (`sharedSession`), "a fresh session heard after a shared start replaces the shared one", the buzzer at start+length to stopping plus `RACE_BUZZER`, the late-cast boundaries at grace 1.0 (0.5 s not late, 1.4 s late), empowered and channel casts, castGUID matching, interrupts, auto-repeat, "secret spell IDs and castGUIDs are judged without ever being stored", combat end before the buzzer (incomplete with `endedAt`), death (incomplete plus `died`; after the buzzer it is complete plus `died`), "result read only after combat end AND 2.5s quiet", "read uses ReadSession(sessionID), never Current", tail and combat end relative to the buzzer, restart after a 10 s gap (`flags.restartedAt`), meter reset (lost in running or stopping; kept when armed), sealed reads retried then lost, raise is lost, "a session ID never captured falls back to the newest session after arming", cancel and stop-now semantics (6 cases), "inputs in the wrong state change nothing". Rewrite on CT: the session-event-ordering cases (`OnSessionCreated`/`OnMeterUpdate` edges, about 10 cases at "a DamageDone update heard just before the session event ..." through "an update on the regen edge's frame ...") because CT `Fight` owns the session and Race reads `FIGHT_STARTED`. "Watchers hands Race the castGUID and the interrupt" is retargeted to CT's cast watcher. "the diagnostics state section names the race state ..." goes to E1. Add plan Review-focus 1 (non-dummy pull cancels the arm) and 5 (`sharedSession`, the restart gap). |
| `test_scoring.lua` (tc:137) | 9 | all: the late boundaries, "QUIET_BEFORE_READ is 2.5s", "Dps complete = damage / length", "Dps incomplete = damage / endedAt", Flags order and text, the resolver, SplitLate, "a clean complete run has no flags; lost stands alone at the end". |
| `test_timeline.lua` (tc:124) | 10 | all (DR `Timeline.lua`, the tail and restart): "tail from probe run 4 = 3.03", "tail from probe run 6 = 8.49", "restart detected after 10s quiet at gap 6", "DoT ticks every 2s are not a restart", "a gap of exactly the setting counts as a restart", and so on. **Name clash:** CT `tests/test_timeline.lua` (12) is the *ability timeline* window, so this goes to `tests/test_race_timeline.lua` or into `test_race_scoring.lua`. |
| `test_late_ignore.lua` (tc:173) | 19 | the module cases: "the hearthstone table holds 59 positive IDs, once each, with 8690, Dalaran and Garrison, never 556", parse and join, Normalize, the profile default with 8690 standing for every hearthstone, Ignore/Unignore/Reset through the seam, Resolve (number, link, name, degraded load), the known spells, IgnoredText, "a profile switch re-scores the flags ... and drops the clean board" (10). The UI cases (result card chips, the menu, the detail flags box, "every flags tooltip shows the dimmed ignored line") go to C1 and D1. |
| `test_disabled.lua` (tc:1644) | 17 | "Disabled (race): Watchers holds no registrations and Race does nothing while disabled" and "Disabled (race): an armed race is dropped by the stand-down and not resumed". "Disabled 5 (countdown) ..." goes to C2; "a disabled login resumes nothing until the addon is enabled" to B2. The other 13 are DROP (CT covers stand-down in `test_load`, `test_settings` :90 and `test_slash` :86-126). |
| `test_skeleton.lua` (tc:11) | 8 | only "NS.MSG declares the six bus names", retargeted to CT's race messages (`RACE_ARMED`, `RACE_STARTED`, `RACE_BUZZER`, `RACE_RESULT`, `RACE_CANCELLED`, plus any state message). The rest is DROP (CT `test_load` 13). |
| `test_usage.lua` (tc:188) | 25 | "a canceled race keeps nothing; the next arm starts a fresh list" and "a lost race stores its casts and usage too, and nothing secret", reread against spec §4.1: a cancel now leaves a plain dummy fight that keeps its casts, so invert the first. The rest is DROP (CT `test_usage` 11, `test_usage_edit` 4). |
| `test_loadout.lua` (tc:712) | 27 | DROP (CT `test_loadouts` 22). Optional: "a race keeps the combat-end loadout, not the arm-time one" as a check that the race part does not alter CT's snapshot timing. |
| `test_casts.lua` (tc:754) | 10 | DROP (CT `test_casts` 17, `test_cast_codec` 7). "times are on the race clock; a cast heard while armed is negative" holds on CT's fight clock, because the race clock is the fight's first hit. |

CT seam: CT `tests/test_fight.lua` (30) and `tests/test_record.lua` (18) drive Fight with `__fireTimers` (`test_fight.lua:61`, `test_record.lua:53`). Constants to pin: grace 1.0, restartGap 6, quiet 2.5, `race.hintDelay` 15, `Race.LENGTHS = {30,60,120,180,300}`, custom 10..900.

### #10 B2: resume after /reload (target `tests/test_race_resume.lua`)
| DR suite (tc) | Cases | Port |
|---|---|---|
| `test_race_resume.lua` (tc:262) | 16 | all, with `F.storedRun` rebuilt as a CT pending race in `db.global.pendingRaces[charKey]` (#1): "running past buzzer becomes stopping+reloaded", "running before buzzer keeps running with remaining time", "stopping out of combat reads immediately", "stopping in combat waits for the regen edge", "an incomplete run waiting for its read stays incomplete", "session gone becomes lost", "an older unresolved run is settled as lost; the newest is carried on", "nothing stored leaves the race idle", "running before the buzzer with combat already over is incomplete and read at once", "a stand-down mid-run whose combat ends unseen never hangs in stopping", "a stopping run that ended before its buzzer is not flagged reloaded", "a run another character left pending is not resumed here", the three DoT and restart-gap cases, "a run with no session ID never adopts a session from before its arm". Add plan Review-focus 2 (an armed race with no first hit is dropped). |
| `test_recorder.lua` (tc:99) | (2 of 22) | "Pending returns running and stopping only" and "Pending holds only the logged-in character's runs". |
| `test_disabled.lua` (tc:1644) | (1 of 17) | "Disabled (race): a disabled login resumes nothing until the addon is enabled". |
| `test_usage.lua` (tc:188) | (1 of 25) | "a run resumed after a /reload keeps no casts and no usage" (DR's limit; goes to `docs/known-limitations.md`). |

### #11 B3: Race mode switch, page, slash, bindings, launcher, auto-arm (target `tests/test_race_settings.lua`, `tests/test_autoarm.lua`)
| DR suite (tc) | Cases | Port |
|---|---|---|
| `test_autoarm.lua` (tc:531) | 31 | all, on `race_fixture` plus `C_NamePlate` (#3), with the HUD replaced by the Race window: "a new profile shows the HUD near a dummy and never arms by itself" (defaults: auto-show on, auto-arm off), registration per rule, auto-show on target and on nameplate, the debounced hide (with a rescan before closing), "a secret GUID is no dummy", the player's close held for the dummy session, holds from race and result, auto-arm on a cataloged dummy out of combat, the silent refusals, disarm on target change before the pull, "a target change in combat before the clock starts never disarms", a race the player armed is never disarmed, profile switch, "neither rule acts in an instance or a battleground", "entering an instance closes the dummy's window", stand-down. Plus the A2 case "a new snapshot of a listed creature is categorized and auto-arm sees it". |
| `test_settings.lua` (tc:1158) | 38 | the race rows: "grace slider 0..5 step 0.1, restartGap 3..15" (:264; the `history.keepDays` half is DROP), "the scoring sliders say they apply to new runs" (:286), "the Race page's rows, ranges and defaults" (:294), "changing grace does not alter saved runs", "the race clock is a Race HUD row: both, left or elapsed, default both", "the sticky-combat hint's tooltip states its range", "Purge history… is refused while a race is armed", "Race draws the late-cast ignore list as the library's spell ID list, writing through LateIgnore", "Race's Reset list puts the six defaults back", "Race's Defaults resets the ignore list too", "Race's Defaults brings the toast back" (toast part to C2), "Race repaints when the ignore list changes". "Race is four tabs ..." is rewritten for CT's page sections. The rest is DROP (CT `test_settings` 19, `test_hud_page` 14, `test_history_page` 16). Every control needs a present test on Retail and an absent one on Forever. |
| `test_slash.lua` (tc:1419) | 38 | "arm parses 90, 1:30, 3m and rejects 0 and 901", "a bare arm uses the last length, and an armed length becomes the last one", "arm prints the refusal line Race.Arm's reason maps to", "arm then cancel goes armed and back to idle", "the Arm or cancel key arms the last length, then cancels; a pending result is kept", the 6 `ignore` cases (become `/ct race ignore`), "the live dispatcher's live set is the library's LIVE_VERBS plus ignore and targetdummy" (`race ignore` and `dummy` become live verbs). "target prints name, npcID and category" and "an uncataloged target reads as Other" go to A2 (`/ct dummy`). "results opens ...; results insights opens Insights" goes to D2, and the `test` and `sim` verbs to E1. The rest is DROP (CT `test_slash` 19). |
| `test_keybinds.lua` (tc:1634) | 7 | DROP (CT `test_bindings` 11), except a new row-order check: CT's `NS.BINDINGS` gains *Arm / cancel race* and *Toggle Race window* (Retail only, absent on Forever). |
| `test_launcher.lua` (tc:1604) | 10 | DROP (CT `test_slash.lua:227-238` launcher cases, `test_bindings`), except a new *Show Race window* entry case on Retail and its absence on Forever. "Bindings.xml names exactly the three buttons" becomes CT's count plus the two race buttons. |
| `test_schema.lua` (tc:1137) | 18 | only "the late-cast ignore list is one Race string row of spell IDs; junk is refused and stores nothing". The rest is DROP. |
| `test_surface_parity.lua` (tc:1664) | 17 | only "the degraded load keeps the late-cast ignore list: the Race page draws quietly and /dr ignore adds by ID" (becomes `/ct race ignore`). The rest is DROP. |
| `test_format.lua` (tc:281) | 16 | "ParseLength accepts 90, 90s, 1:30, 3m and 1m30s, and rejects anything else" (:201) and "ArmRefusal maps every Race.Arm reason to its line" (:215). The other 14 are DROP (CT `test_format` 19), apart from the two C1 cases below. |

### #12 C1: Race window (target `tests/test_race_window.lua`)
| DR suite (tc) | Cases | Port |
|---|---|---|
| `test_hud.lua` (tc:300) | 31 | the body switch on state for all six states, waiting-for-read, idle Arm disabled in combat, idle Arm uses the picked length, custom length parse and range, "an unknown target is allowed and said so", "a new profile's idle body races 1:00", "a changed Default race length takes effect over the remembered pick", "falls back to defaults/Profile.lua, never a literal", the target-of-the-moment pair, the stop body (live tail, time in combat, late casts, grace; ignore-aware), the waiting hint after `hintDelay`, "STOPPING redraws at a few Hz", "the sticky-combat hint asks for the player's spells once per race", "a stand-down drops a window onArm opened", the clock-mode trio (elapsed green and time left red by default; single clock; fits min width). DROP (CT HUD owns these, spec §4.2): "running render raises nothing with secret values", the fractional secret DPS case, "running body shows no percentage text", "live rows keep Blizzard's order", the dash, the live DPS KPI, "layout never calls GetWidth/GetPoint on breakdown rows", "live reads stop when hud hidden". The 3 countdown-cue cases go to C2. |
| `test_hud_layout.lua` (tc:334) | 24 | the buttons and the card: "the equal buttons' width is whole pixels", "the result card's four buttons sit in one row", "Cancel on the waiting body throws the attempt away", "the Stop! and waiting bodies carry Stop Now and Cancel", Stop Now in and out of combat, the 4 Delete cases, "result body shows % and the best delta chip", "a first run is a new best; a slower one shows its deficit and its flags", "a late-cast chip's right-click ignores its spell", "a lost result says it could not be read", "an incomplete run's chip names when combat ended, or that the player died", "New Race opens ... Details and Share reach their modules" (*Open* in the spec), "Share is live on a result card", "closing a result card dismisses it and keeps the run", "the idle body's whole stack is every window's floor" (19). DROP: the 5 spell-row and wheel cases (no spell rows in the Race window, spec §4.2). |
| `test_hud_window.lua` (tc:361) | 21 | "the window is skinned ... and clamped", "Lock frame, Master scale and Reset position act on the window", "dragging is refused while locked and the position is stored" (detached), "onArm shows it on arm and hides it when the race it opened for is canceled", "a race resumed after a /reload shows the HUD under onArm" (the Race window), "a result arriving while the window is closed opens it", "the stand-down drops every registration, timer and the OnUpdate", "hidden with its parent is not closed by the player", "the diagnostics state section ..." (to E1), "no body shouts in capitals", "a title-bar control turns gold under the pointer", "the smallest window still holds every body", "a clock shown alone draws half again as large". DROP: General visibility, showMode, library-absent grip, and the HUD Appearance face and class-color cases (CT `test_hud_appearance`). Add plan Review-focus 4 (attached with the HUD hidden) and the attach, detach and side cases. |
| `test_hud_best.lua` (tc:418) | 9 | all, on race boards: "the board's best sits between Target and Arm Race", "with no race on the board, the card says this one sets the mark", "with no target, it asks for a dummy", the consumables line (×2), "it swaps at once on a length, Custom, a new target, a spec change and a board change", "the hover names the whole run, the click opens it in Results", the block gaps, "nothing above it moves, it fits the width". |
| `test_hud_hint.lua` (tc:430) | 6 | all (the waiting hint box: wrap, three lines at min width, text inset, resizes only on text change). |
| `test_hud_tiles.lua` (tc:445) | 10 | all (the Stop! and waiting tiles: tail `+x.xs`, centered boxes, the 46 px heights, captions fit at the **260 px** minimum by a 6 px-per-character estimate, "the Stop! and waiting redraws read no geometry" (needs #2's geometry spy)). |
| `test_hud_element_tips.lua` (tc:1394) | 11 | all except the running-body chart, heading and spell parts. "hud tips: the running body names its clocks, figures, chart, pace bar, headings and captions" is cut to what the Race window draws. |
| `test_pace.lua` (tc:491) | 14 | "Pace bar range defaults to 1.5 ... clamped to 1.1-2.0", tick in the middle in whole pixels, the bar split, "Bests.Before is the best on the run's board raced before it" (could be A3), "the result card sets the plain final damage against the best's pace at the buzzer", "a run that just became the best is set against the previous best", "no pace bar on the result card with no earlier best", "Show pace bar off, a shared session and a lost run hide the result card's bar" (8). DROP the running-body and card stacking with plot and spells (3), "at the fewest rows ..." and the sim's card (to E1). Overlaps CT `tests/test_hud_pace.lua` (5, `pace: the bounds sit the best's pace in the middle; the range is held to the slider` :70), so reuse CT `Hud_Best`'s pace helpers. |
| `test_switched_sections.lua` (tc:1108) | 3 | all, if the Race window's clock blocks live on CT's HUD Appearance page ("Race clock draws only the clock blocks it picks ..."). Otherwise DROP. |
| `test_format.lua` (tc:281) | (2) | "Clock is m:ss.t with tenths truncated; Length is m:ss" (:183) and "RunTime is the length and the tail, or the time in combat against the length" (:227). |
| `test_layers.lua` (tc:565) | 7 | "the Race HUD is MEDIUM, toplevel and clamped" (the Race window). "the countdown is FULLSCREEN, below every menu" goes to C2. The rest is DROP. |
| `test_header_band.lua` (tc:988) | 5 | "the HUD's title is LEFT in every skin" for the Race window if it has a title band. The rest is DROP. |
| `test_header_rule.lua` (tc:975) | 3 | "the race HUD draws no line under its title band, and keeps its footer rule" (the Race window). The rest is DROP. |
| `test_icon_crop.lua` (tc:1012) | 4 | "the HUD's Your best card crops each consumable icon in its markup". The rest is DROP. |
| `test_dummy_list.lua` (tc:73) | (1) | "the idle HUD's unknown-target warning follows the list without a target change". |
| `test_late_ignore.lua` (tc:173) | (3) | "the result card's chips count only the counted casts; all ignored, no chip", "the result card's late chip carries the menu and the dimmed lines", "a list change redraws the HUD and drops the cached boards". |

Also DROP for C1, because the CT HUD owns them (spec §4.2 "no duplicated widgets"): `test_hud_sizing.lua` (tc:385, 30; CT `test_hud_sizing` 19), `test_hud_tips.lua` (tc:439, 3; spell-row tooltips), `test_chart.lua` (tc:458, 30; CT `test_hud_chart` 7 and `test_slices` 18), `test_chart_icons.lua` (tc:834, 29; CT `test_hud_chart`/`test_timeline`), `test_hud_icon_edge.lua` (tc:1019, 6). Keep one chart case in C3: "chart: hidden, with the pace bar, while the run is on a shared session", because the CT HUD's race-board pace must also hide on `sharedSession`.

### #13 C2: countdown, buzzer warning, new-best toast, chat lines (targets `tests/test_countdown.lua`, `tests/test_toast.lua`, extend `tests/test_share.lua`)
| DR suite (tc) | Cases | Port |
|---|---|---|
| `test_countdown.lua` (tc:508) | 20 | all, on #1 and #2: "10..1 show one per second in the last 10s, then go at the buzzer", "its own frame, center of UIParent, above everything, never taking the mouse", pop-in animation, "the digits are Blizzard's BigGold set, cut by texcoord" (needs the `Kit.skinValues` rows, #5), the large outlined fallback, "finalCountdown 3 starts at 3", off and mid-countdown off, "works with the HUD window closed", one cue per second, cue off, "a cancel at 5s left hides it", "combat ending before the buzzer hides it", the 3 `/reload` cases (4 s left resumes at 4, before the window, past the buzzer), "never broadcasts a pull timer nor drives Blizzard's TimerTracker", diagnostics (to E1). The 2 sim cases go to E1. |
| `test_toast.lua` (tc:1477) | 27 | all, keyed on races (`toast.races`): "a complete run that beats the board's best toasts once", "none for an incomplete or lost run, a run that is no best, a board's first run, or turned off", the payload, the flagged and ignored cases, duration and sound, the 8 `toast sound:` cases (LibSharedMedia key, Default fallback), the test-mode and Test-toast cases (×2), drag and position, profile switch, stand-down, size and icon layout (6). Add the plan's "toast: a new fight best raises the toast; a board's first fight does not" and "toast: each toggle silences its kind" (`toast.fights` on both clients). |
| `test_share.lua` (tc:1460) | 14 | "arming prints the armed line with the length and the target", "a result prints the score line with the delta, the flags and the tail", "the score line counts only the late casts the ignore list leaves (#8)", "the race's own result is printed once, when it resolves", "the target type is named; an uncataloged target by its own name; incomplete is said", "a lost run has no line". DROP: line format, escapes, combat refusal, channels, whisper, compat routing (CT `test_share` 6: `share: line format and length <= 255` :45, `send goes out of combat only` :93). |
| `test_hud.lua` (tc:300) | (3) | "countdown cue plays at 10,5,3,2,1 and buzzer raises the raid warning only when enabled", "the cue stops when the race is canceled", "switching the cue off mid-race silences the marks still ahead". |
| `test_icon_rule.lua` (tc:1001) | 8 | only "the new-best toast's class and spec icons are cropped and edged in the HUD's border". The rest is DROP. |
| `test_layers.lua`, `test_disabled.lua` | (1 each) | "the countdown is FULLSCREEN, below every menu"; "Disabled 5 (countdown): the center numbers go at the stand-down and nothing re-arms them". |

### #14 C3: HUD paces on the race board (extend CT `tests/test_hud_pace.lua`)
No DR suite ports whole, because DR has no fight HUD apart from its race HUD. Keep "chart: hidden, with the pace bar, while the run is on a shared session" (DR `test_chart.lua`, tc:458) as a C3 case. The plan adds two cases ("during a race the HUD paces against the race board's best ..." and "after the race the next plain dummy fight paces on the fight board again") on `hud_fixture` plus `race_fixture`. CT seam: `tests/test_hud_pace.lua:39` ("pace: uses the best's slices when present, else its linear pace").

### #15 D1: Results races, rows, detail (target `tests/test_results_races.lua`)
| DR suite (tc) | Cases | Port |
|---|---|---|
| `test_results.lua` (tc:575) | 18 | "the Status column tags each run", "Status is Spec best, Flagged or Complete for a complete run, each with its icon; there is no Max tag", "race lengths take muted ROYGBIV colors for the presets and a neutral one otherwise", "the Time column takes the length color; the tail stays gray", "Status tags are boxed in their hue with the icon inside", "the HUD never draws a race length in the Results length colors", "Only best keeps the runs holding their board's best", "filters: character, spec, category, length, date range, hide flagged, include incomplete" (only the race facets are new) (8). DROP: the column list, Note column, tooltips, bars, the Delta column, sort, pool (CT `test_results_table` 42). |
| `test_results_detail.lua` (tc:596) | 18 | "timing strip positions buzzer, grace, tail, late casts, combat end", "detail flags name late-cast spells and the session matched by list", "the timing strip's marks draw above its two segments", "the timing legend is two rows ... Restart among the lines" (4). The rest is DROP (CT `test_results_detail` 20). |
| `test_results_delta.lua` (tc:651) | 5 | all (the race delta box: lead, lone run, incomplete muted, lost; centered with New best; `Runs.Leaders` tie on the earlier run then the id; follows grouping and filters; falls back to its board). |
| `test_results_group.lua` (tc:642) | 6 | "Group by time, and by target type and time, shortest first" (length, target × length) and "Group by spec + target + time, one group per board". The rest is DROP (CT groups and saved views). |
| `test_results_badges.lua` (tc:667) | 10 | "the Target cell is a boxed chip in its category color", "the Time cell boxes the length in its color; the tail ... in gray", "Spec best and Max are the box alone; their board is in the tooltip", "a chip never runs past its column", "Target, Time and Status fit their widest chips (Tbl.BadgeWidth)", "the detail's target line leads with the type and length chips", "drawing the chips reads no frame's size or position back", "group headers color ... length", "the HUD draws none of the Results chips" (9). DROP: "the window minimums hold the wider columns ..." (CT's own minimums). |
| `test_results_fit.lua` (tc:634) | 5 | "the Runs filter bar fits inside both views' minimum width" and "... ends on the window's right edge", re-asserted with the Races filter's extra facets on. The rest is DROP. |
| `test_results_sections.lua` (tc:822) | 9 | "a lost run after a drawn one hides Timing's heading hover, so it takes no click" and "Flags is a section heading over the yellow box; each flag's main line, detail and meaning read apart". The rest is DROP (CT `test_results_sections` 5). |
| `test_late_ignore_ui.lua` (tc:195) | 3 | all: "the detail's Flags box dims the ignored line and its right-click ignores a spell", "the row menu holds an Ignore for late casts submenu only when the run has a late cast", "the sample history offers no ignore menu". |
| `test_late_ignore.lua` (tc:173) | (6) | the menu and detail cases: "the Results detail draws an ignored cast's tick gray", "the menu offers each counted spell once ...", "the menu's entries ignore and count again", "the detail's flags box keeps a dimmed ignored line", "every flags tooltip shows the dimmed ignored line (D-6a)". |

Add plan Review-focus 3, run under both kit profiles: "results: saved races list on WoW Forever with no race control" and "results: Race mode off still lists saved races". DROP for D1: `test_results_tree.lua` (tc:659, 5; CT `Results.lua` already handles the talent tree), `test_column_header_rule.lua` (tc:981, 4; except the Insights bar case, which goes to D2), `test_results_body.lua` (tc:996, 2), `test_results_window.lua` (tc:617; apart from the D2 cases), `test_compare.lua` (tc:680, 29; CT `test_compare` 12), `test_results_gear.lua` (tc:959, 13; CT `test_gear` 6), `test_results_usage.lua` (tc:795, 24; CT `test_usage_edit` 4), `test_results_timeline*.lua` (tc:866-946; 20+7+8+6+8+13+10 = 72; CT `test_timeline` 12 and `test_timeline_marks` 11).

### #16 D2: Insights over all fights (targets `tests/test_insights.lua`, `tests/test_insights_data.lua`)
| DR suite (tc) | Cases | Port |
|---|---|---|
| `test_insights_data.lua` (tc:1028) | 13 | all, rebased on CT records through `RaceRecord.Dps` and CT boards: OptionLists/WithAll, "Filter defaults wide, keeps lost runs out and maps Clean only to Hide flagged", faceted Options with counts, closed-dropdown naming, "Normalize sets a 0-run selection to All, never the one just changed", "Compute on no runs returns zero cards", "Compute's cards over the owner-shaped fixture", "boards and progression are board-relative", "board tabs, one per target x length pair, in the catalog's order", "new bests beat an earlier best on their board", "counts by character, target, length and day, gap days included", "Compute buckets the damage tail, the 155 s outlier in 20+", "Compute lists late casts by spell, ignored apart, a sealed one as Unknown". |
| `test_insights.lua` (tc:1044) | 61 | all. The 30 `insights charts:` cases are the chart primitives (truncate, `fitFontSize`, palettes, bar, range, stacked, strip, `StripLabels`/`StripSlots`, the 10-row list panel, pools, divider, the LootHistory stat card, host, tooltip; "the DpsRace host pools through NS.Pool" becomes the CT host). The 31 `insights tab:` and `insights data:` cases cover the ten cards, `CardGrid` four to a row, progression one column a day above 60 runs, the specs legend, the Target × Length tabs (Overall first, the pick kept per session), Consistency ranges, Races By Character × Length, Late Casts with ignored rows dimmed and right-click, Recent New Bests opening its run, empty state, Save/Clear/Reset at `profile.views.insights`, test-mode fill, library-absent, Resize, the bar's rows, the wheel. The race-only sections (Target × Length tabs, Races By Character × Length, Late Casts, the damage tail) assert under the Races filter only. Add the plan's five `insights:` cases. |
| `test_results_window.lua` (tc:617) | 14 | "the Insights tab is built on first show, counts the runs and shows the empty state with none". The rest is DROP. "a profile saved before the rename loads clean and opens Insights" is DR-only. |
| `test_column_header_rule.lua` (tc:981) | (1) | "the Insights filter bar keeps its rule (cards sit under it, not headers)". |
| `test_sizing.lua` (tc:1114) | 13 | "results sizing: the Insights tab and the collapsed view's open detail resize without a redraw". The rest is DROP (CT `test_sizing` 7). |
| `test_slash.lua` (tc:1419) | (1) | "results opens the Results window; results insights opens Insights, and bests still does" (`/ct results insights`, `/ct results races`). |

### #17 E1: test mode, sim, share, diagnostics (extend `tests/test_preview.lua`, `tests/test_sim.lua`, `tests/test_diagnostics.lua`)
| DR suite (tc) | Cases | Port |
|---|---|---|
| `test_preview.lua` (tc:1507) | 25 | "a queued state opens on that body; SetState switches armed, running and result" (`/ct test race [armed\|running\|result]`), "the still running clock follows the Race clock setting", "the sample history covers every status, target type, preset length, notes, loadouts and charts" (race samples), "the detail's Delta box and New best badge read the sample history's Runs view", "arming a real race ends test mode and gives the Results window the store", "a start during a real race is refused", "over a real result card its controls never touch the real race", "a HUD test mode opened is handed to the race that ended it" (8). The rest is DROP (CT `test_preview` 7). |
| `test_sim.lua` (tc:1535) | 31 | the race scenarios newbest, behind, first, shared, flagged, incomplete and died, "the end conditions: ... arming a real race ...", "Stop Now reads as a real race's ...; Cancel ends the sim", the sample card's Delete and Details, "the result card draws the best's diagonal" (DROP: no chart in the Race window), the `sim race:` cases (15 s race on a 0:15 board, real-speed countdown, the cast plan, the buzzer, read and hold gates, sticky). The `sim stepper:` and `sim panel:` cases are DROP where CT's step session already covers them (CT `test_sim` 5: "sim: the verb starts it through the step session" :116), except "the race holds armed until a step is played, then counts down" and "the Armed countdown is the step delay". Scenario names: newbest, behind, first, incomplete, died, flagged, shared, sticky. |
| `test_sample_parity.lua` (tc:1569) | 32 | the race-specific cases: "every sample record has the shape a race leaves", "a flagged run's late cast is in its own cast list, past the buzzer", "a raised grace judges the sample's late casts as it would a race's", "a run that ended early shows Combat Ended", "complete runs go out of combat before the read, and the hint waits for its delay", "the race's messages reach the buzzer, the chat lines and the toast, and no RUN_SAVED", "a sim neither ends itself on its own arm nor arms AutoArm's rule", "New Race on a sample's card leaves the player's length alone", "test mode's replay is silent", "the sim's buzzer makes the race's one last read", "Share on a sample's card reaches nothing", "a held state's history is the same moment's", "a state switch redraws an open Results window", "a held race reads nothing and holds no timer", "arming a real race from under a sim keeps that race's cast list". DROP the rotation, gear and compare-variance cases that CT `MockFights` already pins (CT `test_preview` "a sample fight is the same each time, and its parts agree" :180). |
| `test_countdown.lua` (tc:508) | (3) | "the sim runs the real marks in its running phase", "the sim race's buzzer clears it ... still test mode shows none", "the diagnostics state section names what it shows and holds". |
| `test_race.lua`, `test_hud_window.lua` | (1 each) | "race: the diagnostics state section names the race state, run, session and pending count"; "hud: the diagnostics state section names the body, the event set and the countdown driver" (the Race window). CT seam: `tests/test_diagnostics.lua:35` ("the report carries every section of this addon's own"). |
| `test_slash.lua` (tc:1419) | (5) | "test armed\|running\|result holds that HUD body still ...", "a bare sim opens the idle panel and starts nothing", "sim <scenario> and sim start <scenario> start at once", "the sim help line lists every scenario Sim.Names() has", "test turns test mode on and off" (DROP, CT has it). |
| `test_perf_harness.lua` (tc:1684) | 5 | DROP unless E1 adds a race perf bucket. Then port "every declared bucket is reached by a real bracket" for it. |

### #18 DROP whole (covered by CT, DR-only, or kit)
- **DR-only:** `test_skeleton` 8 (apart from the bus-name case in B1), `test_secrets` 11, `test_meter` 26, `test_launcher_skin_entry` 1, `test_vendor_sync` 3, `test_glyphs` 1 (CT does not run the kit's glyph gate, so no new obligation).
- **CT has its own suites:** `test_compare` 29, `test_loadout` 27, `test_stats` 9, `test_casts` 10, `test_results_usage` 24, `test_results_gear` 13, the seven `test_results_timeline*` (72), `test_results_tree` 5, `test_results_body` 2, `test_hud_sizing` 30, `test_hud_tips` 3, `test_chart` 30 (apart from C3's one case), `test_chart_icons` 29, `test_hud_icon_edge` 6, `test_tooltips` 4, `test_sizing` 13 (apart from D2's one case).
- **Skin suites,** where CT's skin seam and `test_hud_appearance`/`test_skin_surfaces` apply: `test_skinsetup` 25 (DR's `dr.` token namespace), `test_skin` 12, `test_skin_hud` 10, `test_skin_flip` 25, `test_skin_menus` 13, `test_bar_style` 22, `test_skin_fonts` 13, `test_skin_picker` 11, `test_skin_picker_preview` 15, `test_skin_outline` 10, `test_skin_verb` 6. If C1 skins the custom-length input box, port DR `test_skin.lua` "the custom-length box draws the skin's input box under every skin" and "the Arm Race label is opaque once enabled, in every skin".
- **Mostly DROP,** apart from the cases named above: `test_schema` 18, `test_settings` 38, `test_slash` 38, `test_keybinds` 7, `test_launcher` 10, `test_sim_checkbox` 10, `test_disabled` 17, `test_surface_parity` 17, `test_perf_harness` 5, `test_loadorder` 4, `test_results_window` 14, `test_layers` 7, `test_header_rule` 3, `test_column_header_rule` 4, `test_header_band` 5, `test_icon_rule` 8, `test_icon_crop` 4, `test_refactor_pins` 4, `test_format` 16, `test_recorder` 22, `test_usage` 25.
- **Cross-character boards** (spec §5) have no DR suite of their own. Nothing to drop beyond the board-key changes in #8.
- **Kit suites** (8, 97 cases): already run by CT. Their obligations move with the ports: `test_skin_switch` needs the new surfaces (#5), `test_skin_values` needs the Countdown rows (#5), `test_prose` may need the waiver (#6), and `test_layout_cap` holds every new file under 1500 lines.

**Rough port size:** about 470-520 DR cases move (largest: `test_race` 58, `test_insights` 61, `test_autoarm` 31, `test_sim`/`test_sample_parity` race parts, `test_toast` 27, `test_countdown` 20, `test_dummy_list` 23, `test_late_ignore` 19, `test_bests` 21, `test_race_resume` 16). The remaining roughly 900 are DROP.

## gaps

Checked against DR `docs/ARCHITECTURE.md`, `docs/module-map.md` and `docs/scope.md` at f8078c7, and against the plan. Items #1-#4 are claims I could show to be wrong or in conflict. Items #5-#15 are modules, features, settings or saved fields that no section maps, or maps only in part.

### #1 Wrong claim: CT's Retail seed list has 42 IDs, not 7 (R:tests#7)
- **DR:** `defaults/Dummies.lua:28-71` has 42 rows.
- **CT seam:** `defaults/Dummies.lua:24-...` holds 42 `[id] = "name"` rows in `NS.Dummies.Retail` (`grep -c '^\s*\[[0-9]'` gives 42). R:dummies#1 ("the same 42 IDs") is right. R:tests#7 ("7 Retail IDs: 31146, 65310, ...") is wrong.
- **Owner:** A2. When A2 adds the categories back from DR `BY_ID`, it covers all 42 rows. The rewrite of `tests/test_identity.lua:303-338` should pin the count against DR's `test_dummies` "the catalog holds exactly the measured rows".
- **DR tests:** `test_dummies.lua`.

### #2 Wrong claim: `Style.FONT.TAB` already exists in CT (R:results#2)
- **DR:** `modules/Style.lua:51`, `TAB = "GameFontNormal"`.
- **CT seam:** `modules/Style.lua:52` already has `TAB = "GameFontNormal"` inside `Style.FONT` (`:50-`). `Style.TAB_STRIP_H = 26` is at `:215` and `Style.TAB_W, Style.TAB_PITCH = 90, 94` at `:216`.
- **Owner:** D2. Drop "adds `FONT.TAB`" from D2's work. The rest of results#2 stands: CT has no tab strip, and `ui.body` must move down by `TAB_H`.

### #3 Wrong counts and lists in the sections
- **`test_autoarm.lua` has 31 cases, not 32.** DR `docs/test-cases.md:531` says `### test_autoarm.lua (31)`, and R:settings#13 and R:tests#11 agree. R:dummies#10 is wrong.
- **`test_late_ignore.lua` has 19 cases, not 20.** DR `docs/test-cases.md:173` says `(19)`, and `grep -c 'test("'` also gives 19. R:dummies#11 is wrong. R:tests#9 is right.
- **R:hud#27's list of CT `Bests` functions leaves out `Bests.CharKey`.** It is at CT `modules/Bests.lua:26`, and R:bests#1 and R:results#1 depend on it. The other functions match: `Key :39`, `Compute :66`, `Board :80`, `Invalidate :86`, `For :95`, `IsBest :111`, `BestCurve :122`, `HoldingIDs :133`.
- **Owners:** A2 and B1 (test counts), A3 (Bests).

### #4 Conflict between sections: `race ignore` cannot be "a live verb" by itself
- **DR:** `settings/Slash.lua:93` has `HOST_LIVE_VERBS = { "ignore", "targetdummy" }`.
- **CT seam:** `settings/Slash.lua:93` has `HOST_LIVE_VERBS = { "lane", "ignore" }`, and liveness is decided per top-level verb (R:settings#8).
- **Conflict:** R:tests#11 says "`race ignore` and `dummy` become live verbs". R:settings#8 shows that only `race` as a whole can be live: either the handler refuses the other sub-words while disabled (choice a), or `race ignore` is refused while disabled (choice b). `dummy` alone is fine.
- **Owner:** B3 (ruling). A2 (`dummy`).
- **DR tests:** `test_slash.lua:573`. CT's own live-set test must change either way.

### #5 Unmapped: Results_Compare and the DPS cell tip read the fight DPS
- **DR:** the compare sets two runs' `result.dps` side by side (scope.md, "Compare two runs").
- **CT seam:** `modules/Results_Compare.lua:99` (`type(record.dps) == "number"`) and `:173` (`{ key = "dps", va = num(a and a.dps), vb = num(b and b.dps) }`) read `record.dps`. `modules/Results_Tips.lua:116-117` (`CELL.dps`, also `DETAIL.dps :212`) says "Damage over the fight's length." No section maps either.
- **Owner:** D1. Spec §7 says "a race contributes its race DPS wherever a DPS is shown". Route both through `RaceRecord.Dps`, and give a race its own tip line ("Score over the race length", or "over the time raced" when incomplete). Compare's runner-up already becomes race-aware through `Bests.Compute`/`Bests.Key` (R:bests#1).
- **DR tests:** `test_compare.lua` (DPS row). CT `test_compare` needs a race case.

### #6 Unmapped: locale strings and the 1500-line cap
- **DR:** `locales/enUS.lua` is 1232 lines. DR ARCHITECTURE.md:739 already lists it in the on-notice band ("crossed 1000 with the Training dummies tab and `/dr targetdummy`'s lines").
- **CT seam:** `locales/enUS.lua` is 1136 lines today and is the only locale file.
- **Gap:** the Race window, Countdown, BestToast, the AutoArm settings, LateIgnore, dummies, the Race mode page, `/ct race`, `/ct dummy`, the race Results and Insights, and the sim's race steps all bring new keys. That will very likely push the file past the 1500 cap. No section and no plan task lists `locales/enUS.lua` in its Files.
- **Owner:** every task (strings) and F1 (record). Decide the split before B3 and C1 grow it, for example a second canonical locale file loaded after `enUS.lua`. Check the split against the standard's locale rules, and if it deviates, **STOP and flag** (CLAUDE.md).
- **CT tests:** the kit's `test_layout_cap` holds the cap.

### #7 Unmapped: perf buckets for the race paths
- **DR:** `core/PerfSetup.lua:31-36` declares the buckets `combatEvent`, `raceEvent` (every race event in `Watchers.lua`), `hudLive` and `hudTick` (the HUD's 20 Hz redraw).
- **CT seam:** `core/PerfSetup.lua:31-39` declares `laneCast`, `laneRender`, `probe`, `meter`, `fight`, `casts`, `slices` and `hud`, with no race bucket.
- **Gap:** R:hud#7 asks for a `docs/performance.md` entry only, and R:test-sim#6 calls a race perf bucket optional. These paths need a declared bucket and a real bracket:
  - Race's own event watcher (R:race#20: the meter session updates, regen, `PLAYER_DEAD`, the cast judge events);
  - the Race window's clock driver (R:hud#7);
  - AutoArm's nameplate events.
  - DR pins "every declared bucket is reached by a real bracket" (`test_perf_harness.lua`); port it if CT runs the same check.
- **Owner:** B1 (race events), C1 (window tick), B3 (AutoArm), E1 (performance doc).

### #8 Unmapped: debug channels
- **DR:** the `NS.Debug` channels in `modules/` include `Race`, `AutoArm`, `Countdown` and `Toast` (one call site each). CT has none of the four.
- **CT seam:** `core/DebugLogSetup.lua` (the gated sink) and `docs/debug.md`.
- **Owner:** B1, B3, C2 (the calls), F1 (`docs/debug.md`).

### #9 Unmapped: the CT HUD may stay shut during a race, and the Race window has no live damage
- **DR:** the running body always drew the Damage and DPS boxes, the chart and the spell rows (DR `Hud_States.lua:951-1048`). Its visibility followed `hud.showMode` ("onArm" by default) and the master `general.visibility` (always | inCombat | outOfCombat | never, DR `defaults/Profile.lua:76`, `MasterVisibilityAllows`).
- **CT seam:** `modules/Hud.lua:167-175`. `hud.show` ("auto" by default, `defaults/Profile.lua:150`), `general.hudInCombat` (`settings/General.lua:76`) and `hud.instancesOnly` (`settings/Hud.lua:137`) can each keep the HUD shut. `hud.instancesOnly` always does at an open-world dummy.
- **Gap:** spec §4.2 and R:hud#14/#17 move the live Damage and DPS, the chart and the spells out of the Race window because "the CT HUD draws them". Under any of those three settings a race then has no live damage display at all. R:hud#24 (Review focus 4) covers only where the window stands.
- **Owner:** C1/C3, an owner call. Options: the HUD opens for a race whatever `instancesOnly`/`hudInCombat` say, or the Race window keeps DR's Damage and DPS boxes as a fallback while the HUD is hidden. Pin the decision with a test.

### #10 Unmapped behavior change: the snapshots move from the arm to combat entry
- **DR:** `Race.Arm` (`Race.lua:339-406`) takes the loadout (`Recorder.SnapshotLoadout`), `Usage.Snapshot()` and `Stats` at the arm, out of combat. DR ARCHITECTURE.md Known Limitations: "The gear view's stats are the arm's ... buffs then included".
- **CT seam:** CT takes them at `FIGHT_STARTED`, which is combat entry (`modules/Usage.lua:8-24`, `:369`, `:577`; `modules/Stats.lua:3`, `:231`; `modules/Loadouts.lua:432`). Usage says so itself: "a value may come back secret (an aura in combat)".
- **Gap:** R:race#2 says this "already happens at FIGHT_STARTED" and keeps none of it at the arm, without saying the behavior changes.
  - A race now reads stats and auras in combat, where a value may be sealed.
  - DR's "a consumable that leaves the bags while armed reads as used" is gone.
  - The cast window is not a gap: CT `Casts.PREPULL = 10` (`modules/Casts.lua:41`) matches DR's "only the last 10 s before the pull are kept".
- **Owner:** B1. Either accept CT's timing and write it to `docs/known-limitations.md`, or have Race hand an arm-time Stats/Usage snapshot to the fight at `FIGHT_STARTED`.
- **DR tests:** `test_usage.lua`, `test_stats` (DR), `test_loadout.lua` ("a race keeps the combat-end loadout, not the arm-time one").

### #11 Unmapped: `Format.RunSeconds` is missing from CT
- **DR:** `modules/Format.lua:193` `Format.RunTime(run, tailColor)`, `:210` `Format.RunSeconds(run)`, `:229` `Format.Seconds(x)`, `:247` `Format.ParseLength(text)` and `:269` `Format.ArmRefusal(reason, detail)`.
- **CT seam:** CT `modules/Format.lua` has `Reset`, `Number`, `Rate`, `Trial`, `Clock`, `Length`, `Pct` and `SignedPct` only.
- **Gap:** R:hud#8 lists the four missing helpers, but not `RunSeconds`. R:results#7's Time column sorts by it, and R:results#22 uses it as `runSeconds`.
- **Owner:** B3 (`ParseLength`, `ArmRefusal`), C1 (`Seconds`, `RunTime`), D1 (`RunSeconds`). Put them in one place, and remap them to the race part (`race.length` / `race.endedAt` / `race.tail`).
- **DR tests:** `test_format.lua:183, 201, 215, 227`.

### #12 Unmapped: the lifecycle list, the resume order and the TOC positions for every new module
- **DR:** `core/LifecycleSetup.lua:23,40` stand down and stand up `{ "Race", "Watchers", "Hud", "AutoArm", "Countdown", "Results" }` (plus BestToast's Suspend). DR `test_loadorder.lua`: "the hearthstones load before the ignore list, and the ignore list before its readers".
- **CT seam:** `core/LifecycleSetup.lua:14-16` `MODULES`, and the stand-up resumes in `core/CombatTrail.lua`. Each section names only part of the list (R:race#20 Race, R:hud#29 RaceWindow/Countdown/BestToast, R:resume#1 the order).
- **The complete set:**
  - `MODULES`: `Race` (and its watcher if separate), `AutoArm`, `RaceWindow`, `Countdown` and `BestToast`. Race comes after `Meter`/`Fight` and before `Watchers`. Race's Resume runs before Countdown's and RaceWindow's resumes.
  - TOC load-bearing order:
    - `defaults/Hearthstones.lua` before `modules/LateIgnore.lua`;
    - `modules/Dummies.lua` before `Identity.lua` (R:dummies#9);
    - `RaceRecord` before `Recorder` and `Bests`;
    - `core/ToastSetup.lua` and `core/ChartsSetup.lua` in `core/` (R:hud#27, R:results#26);
    - the race Results files before `Results.lua` (R:results#27);
    - `settings/Race.lua` before `Profiles.lua` (R:settings#1).
  - Each new suite goes in CT `tests/run.lua` `SUITES` (`:107-158`).
- **Owner:** each creating task. F1 owns `docs/module-map.md`. CT `test_loadorder` gains the hearthstone case (B1).

### #13 Unmapped: DR's Known Limitations beyond the resume line
- **DR:** ARCHITECTURE.md:638-670 and `docs/known-limitations.md`:
  - auto-show and auto-arm see only known dummies, and with nameplates off only the target counts;
  - your own dummies recategorize every stored run, and a built-in cannot be recategorized;
  - the late-cast list is a static per-patch table that judges by spell ID: a sealed late spell ID is always counted, and a typed name resolves only to a known or late-cast spell;
  - the list is per profile while pruning is account-wide;
  - the chart lasts one session.
- **CT seam:** `docs/known-limitations.md`. The plan writes only B2's line ("casts, usage and chart slices are not recovered").
- **Owner:** B3 (auto-show), A2 (custom dummies; the lines hold on both clients), B1 (late ignore), F1 (consolidation). The recategorization line depends on the frozen-vs-read-time ruling (R:bests#1, R:dummies#6).

### #14 Unmapped: DR's open client assumptions in the smoke tests
- **DR:** ARCHITECTURE.md Known Limitations: "Unmeasured client behavior is the spec's open items O1 to O7 and the client assumptions C1 to C26, closed in the owner's smoke-test pass". Examples: the new session lands on the first hit's frame, the buzzer, the sealed read after combat, the nameplate signals.
- **CT seam:** `docs/smoke-tests.md` (F1 "a Race mode section ported from DR's"). The `/ct probe` steps are in CLAUDE.md.
- **Gap:** CT's first hit is the first meter update, not the session-created event (R:race#3), so DR's frame-accurate-start assumption needs its own CT smoke row. So does every race handoff that spec §12 lists (arm, first hit, buzzer, combat end, cancel, reload).
- **Owner:** F1, with rows added by B1 and B2.

### #15 DR modules no section maps, because CT already owns them (spec §9 "not ported twice")
- **DR, no section:** `Casts.lua`, `Usage.lua`, `Stats.lua`, `Loadouts.lua`, `Hud_Breakdown.lua`, `Results_Compare.lua`, `Results_Loadout.lua`, `Results_Usage.lua`, `Results_Gear.lua`, `Results_Timeline.lua` with `_TimelineData` and `_TimelineMarks`, and in `core/` `State`, `MediaSetup`, `Compat`, `Secrets`, `PoolSetup`, `WidgetsSetup`, `EnvSetup`, `SimSetup`.
- **DR, mapped only in part:** `Slices.lua` (R:race#23), `Hud_Appearance.lua` (R:hud#22), `Sizing.lua` (R:hud#6), `Style.lua` (R:hud#21).
- **CT seam:** the same-named CT modules. CT `core/Secrets.lua` is a superset of DR's: it adds `NamesCreature`, and every `Secrets.*` the DR race files call exists (`IsSafeKey`, `IsSealed`, `PlainNumber`, `PlainString`, `PlainTruth`).
- **What is left for the race:**
  - (a) CT's cast times and the chart's x axis start at combat entry, where DR's start on the race clock (the first hit). The race detail and Timeline cast marks therefore sit offset by `firstHitT - startT`. D1 decides whether race rows shift them or say so.
  - (b) DR's `CAPTURE_EVENTS` cast capture is dropped (R:race#20).
  - (c) the loadout and snapshot timing in #10.
- **Owner:** D1 for (a). Otherwise none, and F1 records "not ported, CT's own" in `docs/module-map.md`.
- **DR tests:** dropped per R:tests#18.
