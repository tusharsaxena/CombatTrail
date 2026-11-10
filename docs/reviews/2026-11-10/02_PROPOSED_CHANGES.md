# 02 — Proposed changes (HLD + LLD)

This is a design for the findings in `01_FINDINGS.md`. **Nothing here has been applied**: the review was report-only and no source was edited. Every change targets this repo's own `modules/`, `tests/` or `docs/` files. No entry touches `libs/` or `tests/_kit/` (root `CLAUDE.md`: "Never edit anything under `libs/` or `tests/_kit/`").

## HLD — themes

### T1. One rule for secret client answers: never cache a secret (F-001)
- **What:** the cast list's base-cooldown cache adopts the lanes' rule. A sealed answer is not cached, and the next read (out of combat at the latest, at `Casts.Finish`) asks again.
- **Why:** the record and both cooldown views depend on this value. A secret read in combat currently poisons it for the session.
- **Alternatives considered:**
  - Share one cooldown cache between `Casts` and `LaneRender`. Rejected for now: the two have different consumers (the record vs the glow), and a shared module is a new seam for two callers whose semantics already match only after this fix. Revisit if a third caller appears.
  - Read cooldowns only at `Finish`. Rejected: the HUD's live chart icons need them in combat whenever the read is plain.
- **Trade-off:** a spell whose cooldown stays secret is re-asked on each 1 Hz live read. That is one pcall per distinct spell, bounded by the spell count.

### T2. Do the per-cast and per-tick work only when its inputs changed (F-002, F-003, F-005, F-006)
- **What:**
  - Stamp each lane icon with the lane's style generation, and restyle only on a stamp change. Keep `setItem` for the per-cast fields.
  - Make `Casts.Live` incremental: keep the list built so far per capture and append only casts newer than the last read.
  - Keep a cooldown-filtered list on the HUD view whose identity changes only when it grows, so the chart's `drawIcons` cache works.
  - In the HUD breakdown, reuse rows by index instead of `Clear()` plus re-acquire.
  - Let Slices reuse the HUD's live read on the same tick.
- **Why:** these are the four hottest paths the focus list names (UNIT_SPELLCAST push, FIGHT_TICK, HUD render). Each one repeats work whose inputs have not changed.
- **Alternatives considered:** lowering `Hud.CAST_READ` or `TICK`. Rejected: it changes the user-visible cadence (`L["live \194\183 4 Hz"]`, `Hud.lua:572`) and hides the cost rather than removing it.
- **Measure first.** Take a `/kct perf` capture of a long pull (the `laneRender`, `hud`, `slices` and `fight` buckets) **before** each change, then repeat it after. Compare within one session on one machine.

### T3. Spread the combat-entry snapshots (F-004)
- **What:**
  - Keep the cheap, time-critical reads (Identity, Stats, gear item links) at `FIGHT_STARTED`.
  - Defer the bag walk and the talent import string to the next frame (`C_Timer.After(0, …)` or an AceTimer of 0).
  - Skip `Usage.BagCounts()` for the parked fight when its `usageAfter` can be filled at its own settle.
- **Why:** this moves several hundred pcall'd reads out of the pull's frame.
- **Alternatives considered:** reading bags out of combat only (at the previous fight's end). Rejected: a consumable swapped between fights would be missed. A one-frame deferral keeps the "at the start" semantics within about 16 ms.
- **Risk:** the deferred snapshot races the first casts by one frame. `Usage.Detect` keys on spell IDs and counts, not on cast order, so the result is unchanged.
- **Measure:** add a perf bucket around the `FIGHT_STARTED` receivers (performance.md's bucket table moves in the same change), and capture before and after.

### T4. Make the "costs only itself" promise true on unregister too (F-007, F-009)
- **What:**
  - `Watchers.Sync` records an event as registered only when `SafeRegisterEvent` answered true.
  - Unregister through a guarded call.
  - Route the remaining raw `UnitExists("pet")` tests and error `tostring`s through `NS.Secrets` / `NS.SafeToString`.
- **Why:** this matches the module headers and the project's one-inspector rule (`docs/ARCHITECTURE.md`, *Secret-value invariants*).
- **Alternative considered:** a `SafeUnregisterEvent` in LibKa0s. Rejected for this repo: it would be an upstream library change. If wanted, it is a LibKa0s issue and a later re-vendor, not a local edit.

### T5. Make the hard invariant's test able to fail (F-008)
- **What:** scan every tracked authored `.lua` file (`git ls-files` scope, minus `libs/` and `tests/_kit/`) for a registration naming `COMBAT_LOG_EVENT`. Assert the registry is **non-empty** before asserting it lacks the event.

### T6. One board for the live view and the record (F-010)
- **What:**
  - When no encounter is active, the HUD re-resolves its pace board once the meter names a primary enemy. This can only happen after combat (the enemy read is plain then), so the practical form is: the over card judges "new best" against the same board the live view used, and states the board when the two differ.
  - Or, simpler: say in the HUD's tooltip and `docs/known-limitations.md` that the live pace follows the pull target.
- **Trade-off:** this is an owner decision on spec §6 semantics. Both options are listed. The minimal one (document it) is the default in the LLD.

### T7. Small cleanups (F-011, F-012)
- Remove the dead `acc.err` branch.
- Either guard the daily purge with "not in combat, else re-arm for after combat", or correct `docs/performance.md:32`.

## Upstream change-set

None.

## LLD — change set

### C-01 → F-001: do not cache a sealed base cooldown in Casts
- **File:** `modules/Casts.lua`, `cooldown(id)` (`:136-145`).
- **Before:**
  ```lua
  local ok, v = pcall(NS.Compat.SpellBaseCooldown, id)
  ms = ok and Secrets.PlainNumber(v) or nil
  if not ms then ms = false end
  cooldowns[id] = ms
  ```
- **After:**
  ```lua
  local ok, v = pcall(NS.Compat.SpellBaseCooldown, id)
  if ok and Secrets.IsSealed(v) then return nil end   -- secret: not cached, asked again
  ms = ok and Secrets.PlainNumber(v) or false
  cooldowns[id] = ms
  ```
- **Test:** add `tests/test_casts.lua`, "casts: a secret base cooldown is never cached; the read after combat fills it". Mark the mock's cooldown secret, call `Casts.Live` in combat, then unmark it and call `Finish`. Expect `spells[id] == ms`.
- **Risk:** low.
- **Count movement:** `docs/test-cases.md` (generated) gains one case in the same change.

### C-02 → F-002: restyle lane icons only on a style change
- **File:** `modules/LaneRender.lua`.
- **Changes:**
  - `LaneRender.Apply` bumps `st.styleGen` (one integer), and the skin hook (`NS.Skin.OnLooksChanged`) does the same.
  - `Push` calls `styleIcon` only when `f.styleGen ~= st.styleGen`.
  - `labelFace(cfg)` is cached on `st` per `styleGen`.
  - `restack` only touches the first `ICON_BAND + 1` icons (all older ones are already at `+1`).
  - `labelText` runs on `UNIT_PET` and Apply only, not per push.
- **Tests:** the existing `tests/test_lane_render.lua` look tests must stay green. Add a case asserting a second push with unchanged settings makes no `SetFont` call on the reused icon (mock call counter).
- **Risk:** medium. A missed bump leaves a stale look, so every `SETTINGS_CHANGED` path that reaches `Apply` must bump.

### C-03 → F-003: incremental live cast list and a stable icon list
- **Files:** `modules/Casts.lua` (`listOf`, `Casts.Live`), `modules/Hud.lua` (`readCasts`, `fillExtras`).
- **Changes:**
  - The capture holds `cap.live = { casts = {}, spells = {}, upto = index into raw }`. `Live` appends `raw[cap.live.upto+1 .. #raw]` within the window and returns the same tables.
  - `trim` adjusts `upto` when it drops entries.
  - `close()` still builds the final list fresh.
  - Hud keeps `v.cooldowns` and rebuilds it only when `#casts` changed, so `Strip:drawIcons`' `self.iconList == casts` check hits.
- **Tests:** `tests/test_casts.lua` "Live ... without ending it" must stay green. Add "Live answers the same table between reads with no new cast".
- **Risk:** medium. The window `from` and `to` must still filter, and `trim` rebuilding `raw` must reset `upto`.

### C-04 → F-005, F-006: reuse HUD rows; one live read per tick
- **Files:**
  - `modules/Hud_Breakdown.lua` `List:ShowLive`: keep `self.rows[i]` and release only the rows past `n`.
  - `modules/Hud.lua` `OnFightTick` / `modules/Slices.lua` `OnTick`: Hud publishes `Hud.LastLive(fightID, t)`, and Slices uses it when its tick time matches. Otherwise it reads itself (the HUD may be closed).
- **Risk:** low and medium respectively. Ordering between bus receivers is not guaranteed (`Hud.lua:214` already notes this), so Slices must fall back to its own read.

### C-05 → F-004: defer the heavy snapshots one frame
- **Files:** `modules/Usage.lua` `onStarted`, `modules/Loadouts.lua` `FIGHT_STARTED` receiver.
- **Change:** wrap each snapshot in `NS.addon:ScheduleTimer(fn, 0)`, with an `if fight still current` guard. The AceTimer goes with the stand-down's `CancelAllTimers`, as the rest do.
- **Perf:** add the bucket `{ key = "fightStart" }` to `core/PerfSetup.lua` and bracket the receivers. `docs/performance.md`'s bucket table moves in the same change.
- **Tests:** the `tests/test_usage.lua` and `tests/test_loadouts.lua` cases that read `fight.usageSnap` or `fight.loadout` immediately after `enter()` must fire timers first (`inst.mocks.__fireTimers()`, already used in `tests/test_probe.lua:177`).
- **Risk:** medium (test-order coupling).

### C-06 → F-007, F-009: guarded unregister and consistent guards
- **File:** `modules/Watchers.lua` `Sync`:
  ```lua
  if NS.SafeRegisterEvent(ensureTarget(), event, onEvent, NS.rejectedEvents) then
      registered[event] = true
  end
  ```
  For the unregister, use `pcall(target.UnregisterEvent, target, event)`.
- **Files:** `modules/Meter.lua:221`, `modules/LaneCasts.lua:351` and `modules/Probe.lua:234,284,369`, using `Secrets.PlainTruth(UnitExists("pet"))`. Also `modules/Identity.lua:80` and `modules/Share.lua:204`, using `NS.SafeToString` (`core/CoreSetup.lua:82`).
- **Test:** `tests/test_fight.lua`, "an event the client rejects is never unregistered and costs nothing". Make the mock reject `DAMAGE_METER_RESET`, then run a fight to IDLE.
- **Risk:** low.

### C-07 → F-008: a combat-log test that can fail
- **File:** `tests/test_fight.lua` (the case at `:487`).
- **Changes:**
  - Replace the two-file list with every tracked authored `.lua` file under `core/`, `modules/` and `settings/`. The suite already reads `T.root`; a static file list from `CombatTrail.toc` is the headless equivalent of `git ls-files`.
  - Assert `#inst.mocks.__registrations() > 0` before the loop.
  - Do the same in `tests/test_probe.lua:171`.
- **Count movement:** none (same case names).

### C-08 → F-010: state the live pace's board rule
- **Files:** `docs/known-limitations.md` (one bullet), and `modules/Hud_Tips.lua` (the pace tooltip text) plus `locales/enUS.lua` (the new string).
- **Behavior:** unchanged. The behavioral alternative (re-judging on the same board) waits for an owner decision.

### C-09 → F-011, F-012
- `modules/Meter.lua:407`: delete the line.
- `modules/Retention.lua` `OnTimer`: if `InCombatLockdown()`, re-arm for 60 s instead of purging. Otherwise purge as today. Alternatively, reword `docs/performance.md:32`.

## Standards conformance

**I could not read the pinned standard** (cross-repo `git show` needed approval), so conformance is checked against this repo's own statements of it:
- **Vendored code.** No change touches `libs/` or `tests/_kit/` (root `CLAUDE.md`).
- **Event registration.** C-06 keeps every registration on `NS.SafeRegisterEvent` (`docs/ARCHITECTURE.md`, *Event Subscriptions*: "Every registration goes through `NS.SafeRegisterEvent`").
- **Secret-value inspection.** C-01 and C-06 keep `core/Secrets.lua` the only inspector (*Secret-value invariants*).
- **Layering.** C-02 keeps every `SetFrameLevel` a parent level plus a `LAYERS` offset (`LaneRender.lua:21`).
- **Perf buckets.** C-05 adds a bucket the same way the existing ones are declared (`core/PerfSetup.lua:31-40`, `docs/performance.md` table).
- **New strings.** C-08's string goes through `locales/enUS.lua`.

If the owner reads any of these as a deviation from the pinned standard, it is to be flagged per root `CLAUDE.md` (an accepted deviation row, or a change upstream), not silently applied.
