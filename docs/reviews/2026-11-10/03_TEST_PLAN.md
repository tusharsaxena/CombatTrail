# 03 — Test plan

This plan is derived from `02_PROPOSED_CHANGES.md`. None of it was run during the review: every interpreter call needed an approval this session did not have (see `01_FINDINGS.md`, Measurement run).

## Pre-flight

These three commands are the repo's commit gate (root `CLAUDE.md`, `docs/testing.md`). Run them from the repo root on the unmodified branch first, to get the baseline, and again after each change.

```sh
~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua
KA0S_KIT_CLIENT=forever ~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua
~/.claude/dev-copilot/bin/ka0s-bounded luacheck .
```

- **Baseline:** record the pass and skip counts of both profiles. The plan ledger last claimed 272 pass / 2 skips at Task 1.5; the current authoritative count is `docs/test-cases.md`.
- **Pass:** both profiles show 0 failures, and luacheck shows `0 warnings / 0 errors`.
- **Exit codes:** an exit of 124 (time limit) or 137 (killed) is reported as exactly that, never as a pass or a failure.

## Per-change tests

### C-01: Casts never caches a sealed base cooldown (F-001)
- **Setup:** the harness's `inst.mocks.__baseCooldowns` with the secret marker the lane test uses (`tests/test_lane_render.lua:204` shows the pattern).
- **Steps:**
  1. Add the test `casts: a secret base cooldown is never cached; the read after combat fills it` to `tests/test_casts.lua`.
  2. In combat, mark 12472's cooldown secret, cast 12472 and call `Casts.Live(id)`.
  3. Leave combat, unmark the cooldown (plain 120000), settle, then call `Casts.Finish`.
  4. Run both profiles.
- **Expected:** `spells[12472] == 120000` from `Finish`, no Lua error, and the new case passes on Retail and Forever.
- **Pass / Fail:** pass if the new case is green and was **red on the unfixed code**. Run it first against the current `Casts.lua`, before changing it, to prove it can fail.

### C-02: lane icons restyle only on a style change (F-002)
- **Steps:**
  1. Add `lane render: a second push with unchanged settings restyles nothing` (count `SetFont` calls on the reused icon through the mock).
  2. Run the whole `tests/test_lane_render.lua`, `tests/test_lane_casts.lua` and `tests/test_skin_surfaces.lua`.
- **Expected:** the new case is green, every existing look and skin case is green, and the case counts `0` `SetFont` calls after the first push.
- **Pass / Fail:** pass if all three files are green on both profiles.

### C-03: incremental `Casts.Live` (F-003)
- **Steps:**
  1. Add `casts: Live answers the same table between reads with no new cast`.
  2. Add `casts: Live after a trim still answers only the window's casts`.
  3. Run `tests/test_casts.lua`, `tests/test_hud_chart.lua` and `tests/test_timeline.lua`.
- **Expected:** `rawequal(Live(id), Live(id))` with no cast between the reads, the window bounds unchanged, and all three files green.

### C-04: HUD rows reused; one live read per tick (F-005, F-006)
- **Steps:**
  1. Add `hud breakdown: ShowLive reuses rows by index`.
  2. Add `slices: a tick the HUD read reuses its live read`, counting `GetCombatSessionSourceFromID` calls in `tests/mock_meter.lua`.
  3. Run `tests/test_hud_breakdown.lua`, `tests/test_hud_states.lua` and `tests/test_slices.lua`.
- **Expected:** at a step boundary with the HUD shown, there is one meter source read per source per tick, not two. With the HUD hidden, Slices still reads.

### C-05: combat-entry snapshots deferred one frame (F-004)
- **Steps:**
  1. Update the `tests/test_usage.lua` and `tests/test_loadouts.lua` cases that read `fight.usageSnap` or `fight.loadout` right after `enter()` to `inst.mocks.__fireTimers()` first.
  2. Add `usage: a fight that ends before the deferred snapshot has none and is still recorded`.
  3. Run `tests/test_usage.lua`, `tests/test_usage_edit.lua`, `tests/test_loadouts.lua` and `tests/test_record.lua`.
- **Expected:** the same detected usage and loadout as before after the timers fire, and no Lua error when a stand-down cancels the timer.

### C-06: guarded unregister; consistent guards (F-007, F-009)
- **Steps:**
  1. Add `fight: an event the client rejects is never unregistered and costs nothing`. Make the mock's `RegisterEvent` raise for `DAMAGE_METER_RESET`, enter, leave, settle to IDLE, and assert no error and that `NS.rejectedEvents` holds it.
  2. Run `tests/test_fight.lua`, `tests/test_meter.lua` and `tests/test_lane_casts.lua`.
- **Expected:** green; the rejected event is listed once.

### C-07: the combat-log test can fail (F-008)
- **Steps:**
  1. Change `tests/test_fight.lua:487` and `tests/test_probe.lua:171` as in C-07.
  2. **Prove it can fail:** in a scratch copy only (never committed), add `frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` to `modules/LaneVisibility.lua` and run the suite.
- **Expected:** red with the scratch edit, green without it.

### C-08: live pace board rule documented (F-010)
- **Steps:** run `tests/test_docs.lua` (the prose and doc-shape gate) and `tests/test_hud_page.lua`.
- **Expected:** green; the new locale key is present in `locales/enUS.lua`.

### C-09: dead branch removed; purge outside combat (F-011, F-012)
- **Steps:**
  1. Run `tests/test_meter.lua` and `tests/test_retention.lua`.
  2. Add `retention: the daily run in combat re-arms instead of purging`.
- **Expected:** green; `Retention.Timer()` is non-nil after the in-combat run and nothing was removed.

## Manual / live-environment checks (owner, in game; not runnable headless)

1. **The F-001 premise.** On Retail and Forever, out of combat, run `/run print(issecretvalue(GetSpellBaseCooldown(19574)))`. Then pull a dummy and run the same line in combat (it can be bound to a macro).
   - **Expected:** `false` out of combat. Record the in-combat answer in `docs/midnight-quirks.md`. If it is `true`, F-001 is confirmed live.
2. **After C-01.** With the HUD on "auto", fight about 60 s using a 2-minute cooldown. Open the Results timeline for that fight.
   - **Expected:** the cooldown's row sorts first, and the over card's chart shows its icon.
3. **Perf, before and after C-02, C-03 and C-05.** Run `/kct perf start`, do a 5-minute dummy pull with the pet out and the HUD open, then `/kct perf finish`. Copy the report.
   - **Expected:** the `laneRender`, `hud` and `fightStart` medians drop. Compare within one session on one machine. Commit the write-up under `docs/perf-analysis/<run>/`.
4. **F-010 sanity.** On open-world trash, target an add at the pull and kill the pack.
   - **Expected:** the tooltip text from C-08 explains why the over card's best differs from the live pace.
5. **The Forever smoke from `docs/smoke-tests.md`** (secret samples via `/kct probe start`). Confirm no `ADDON_ACTION_FORBIDDEN` in BugGrabber after a full fight.

## Regression suite

- Both kit profiles are green and `luacheck .` reports 0/0 (Pre-flight).
- `tests/test_vendor_sync.lua` is green: no vendored byte moved.
- `tests/test_loadorder.lua` and `tests/test_load.lua` are green: the TOC order is unchanged.
- In game: `/reload` shows no Lua error; `/kct hud show`, `/kct results` and `/kct test` each open; a dummy fight is saved and appears in Results.

## Performance spot-checks

These come from items 3-4 above. The measurement is the LibKa0s-Perf capture, by bucket median and p95 in ms, taken before and after within one session.

## Concurrency spot-checks

Not applicable: single-threaded Lua. Bus receiver order is unordered (CallbackHandler `pairs`), so C-04's fallback is tested with the HUD hidden and with it shown.

## Sign-off

| ID | Tested? | Pass/Fail | Notes |
|---|---|---|---|
| C-01 | | | must be red on unfixed code first |
| C-02 | | | |
| C-03 | | | |
| C-04 | | | |
| C-05 | | | |
| C-06 | | | |
| C-07 | | | scratch-edit red run required |
| C-08 | | | |
| C-09 | | | |
