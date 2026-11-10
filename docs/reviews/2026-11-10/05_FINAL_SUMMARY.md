# 05 — Final summary (projected)

> This is written as if `02` and `04` were implemented and every check in `03` passed. **None of it has been applied yet.** The review was report-only, and no suite could be run when it was written. Replace each projected figure with the measured one when the work lands.

## Headline

This cycle fixes one real defect and makes the busy paths cheaper:
- **The defect.** The fight's cast list no longer forgets a spell's cooldown after reading it once in combat, so the saved fight, its timeline and the HUD chart keep their long-cooldown marks.
- **Hot paths.** The lane icons, the HUD's per-second cast read, its per-tick spell rows and the pull's snapshots each stop redoing work whose inputs did not change.
- **Latent errors.** Two latent error paths are closed: unregistering an event the client rejected, and a few unguarded client answers.
- **Test hardening.** The most important hard rule, "never register the combat log", gets a test that can actually fail.

## Counts

Critical fixed: 0, High fixed: 1, Medium fixed: 6, Low fixed: 5.

Deferred: F-010's behavioral option (re-judging the best on the live view's board) waits for an owner decision. Only its documentation part (C-08) is counted as fixed.

## Changes by theme

### T1. One rule for secret client answers
- **What changed:** `Casts`' base-cooldown cache leaves a secret answer uncached, as the lanes' cache already did.
- **Why it mattered:** a single in-combat read could blank a cooldown for the whole session.
- **Findings / changes:** F-001 / C-01.
- **Files:** `modules/Casts.lua`, `tests/test_casts.lua`.

### T2. Hot paths do work only on change
- **What changed:**
  - Lane icons carry a style stamp.
  - The live cast list grows incrementally and keeps its identity.
  - The HUD reuses its spell rows.
  - Slices reuses the HUD's live read on the same tick.
- **Why it mattered:** per-cast and per-tick costs had been growing with the cast count and with fight length.
- **Findings / changes:** F-002, F-003, F-005, F-006 / C-02, C-03, C-04.
- **Files:** `modules/LaneRender.lua`, `modules/Casts.lua`, `modules/Hud.lua`, `modules/Hud_Breakdown.lua`, `modules/Slices.lua`, and the tests.

### T3. A lighter pull
- **What changed:** the bag walk and the talent import string are taken one frame after combat entry. A new `fightStart` perf bucket measures the receivers.
- **Findings / changes:** F-004 / C-05.
- **Files:** `modules/Usage.lua`, `modules/Loadouts.lua`, `core/PerfSetup.lua`, `docs/performance.md`, and the tests.

### T4. Rejections really cost only themselves
- **What changed:**
  - Watchers marks only accepted events and unregisters under `pcall`.
  - The last raw `UnitExists("pet")` tests and error `tostring`s go through `NS.Secrets` / `NS.SafeToString`.
  - The dead `acc.err` branch is removed.
- **Findings / changes:** F-007, F-009, F-011 / C-06, C-09.
- **Files:** `modules/Watchers.lua`, `modules/Meter.lua`, `modules/LaneCasts.lua`, `modules/Probe.lua`, `modules/Identity.lua`, `modules/Share.lua`.

### T5. A test that can fail
- **What changed:** the combat-log test scans every authored file and requires a non-empty registry.
- **Findings / changes:** F-008 / C-07.
- **Files:** `tests/test_fight.lua`, `tests/test_probe.lua`.

### T6/T7. Docs that match the code
- **What changed:**
  - The live pace's board rule is stated in the HUD tooltip and in the known limitations.
  - The daily purge waits out combat, matching `docs/performance.md`.
- **Findings / changes:** F-010 (documentation part), F-012 / C-08, C-09.
- **Files:** `docs/known-limitations.md`, `modules/Hud_Tips.lua`, `locales/enUS.lua`, `modules/Retention.lua`.

## API / behavior changes

- **Perf bucket:** new bucket `fightStart`, visible in `/kct perf` reports.
- **Bags and talents at the pull:** snapshotted one frame later. The record shape is unchanged.
- **Daily purge:** may run up to 60 s after combat instead of during it.
- **Unchanged:** no slash verb, setting, saved key or schema changes.

## Migration notes

None. The record format (`Recorder.CT_SCHEMA = 1`) and the settings schema are unchanged.

## Dependency changes

None. No vendored library moved, and `tests/test_vendor_sync.lua` still passes against LibKa0s v1.94.0.

## Performance impact

**Not yet measured.** Fill this from the before and after `/kct perf` captures (`03`, manual item 3): the `laneRender`, `hud`, `slices` and `fightStart` medians and p95s, from one session on one machine. Do not fill it with estimates.

## Test movement

- **Before:** unknown today (no run was possible). Take it from M0.
- **After:** expected to be the M0 count plus about 9 new cases (C-01, C-02, C-03 ×2, C-04 ×2, C-05, C-06, C-09), on both profiles. `docs/test-cases.md` is regenerated in the same changes.

## Known follow-ups

- **F-010, behavioral option:** re-judge the over card on the live view's board, or name both boards. Needs an owner decision on spec §6.
- **One shared base-cooldown cache** for Casts and LaneRender, if a third consumer appears.
- **`SafeUnregisterEvent` in LibKa0s:** an upstream idea only, to be filed on LibKa0s if wanted, never a local edit to `libs/`.
- **Areas this review did not cover in depth:** the `Results_*` window family, the `settings/*` pages, `core/SkinSetup.lua` and `modules/Style.lua`.

## Verification evidence

- `docs/reviews/2026-11-10/03_TEST_PLAN.md`, with the sign-off table filled in.
- The commit range on `feat/2026-11-10-combat-trail-v0.1.0`, recorded once the work is done.

## Suggested commit message / PR description

```
fix: review 2026-11-10 — secret cooldown cache, hot-path cost, latent unregister error

- casts: never cache a secret base cooldown, so the record, timeline and HUD chart keep
  long-cooldown marks (F-001)
- watchers: a rejected event is never marked registered or unregistered (F-007)
- route the last raw pet-exists tests and error strings through NS.Secrets; drop a dead
  branch (F-009, F-011)
- tests: the combat-log invariant scans every authored file and cannot pass empty (F-008)
- perf: lane icons restyle only on a style change; incremental live cast list; HUD rows
  reused; one live read per tick; bag and talent snapshots deferred one frame (F-002..F-006)
- docs: the live pace follows the pull target; the daily purge waits out combat (F-010, F-012)

Gate: lua tests/run.lua (retail + forever) and luacheck . — counts in the PR body.
```
