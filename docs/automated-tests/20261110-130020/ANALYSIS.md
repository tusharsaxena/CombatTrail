# Analysis — 20261110-130020

- **Addon:** CombatTrail 0.1.0
- **Verdict:** green
- **Commit:** 6e81fa8 (feat/2026-11-10-combat-trail-v0.1.0)
- **Previous run:** none — this is the first

## Headline

The first recorded run is green: lint 0/0 over 131 files and 726 of 727 cases passing with one declared
skip. Complexity measured one function above CCN 15, the test helper `rec` in
`tests/test_results_table.lua` at 17, which plain `lizard` had not seen and the kit's sighted shadow
did. It is peeled in the commit that records this run. Perf is a skip: the addon ships no
`tests/perf.lua`.

## Suites

| Suite | Status | Result | Artifact | Moved since none |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 131 files | [`lint.txt`](lint.txt) | first run |
| tests | pass | 726 passed, 1 skipped, 0 failed, 727 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | first run |
| perf | skip | 0 scenarios | none: no `tests/perf.lua` | first run |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | first run |

| Metric | Value |
|---|---|
| Total NLOC | 29563 |
| Functions | 3735 |
| Avg NLOC / function | 7.1 |
| Avg CCN | 2.7 |
| Max CCN | 17 |
| Avg tokens / function | 65.6 |
| Warnings (CCN > 15) | 1 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 2 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |
| Crashed files (lizard raised) | 0 |

**perf (skip).** `manifest.json` records `no tests/perf.lua — this addon ships no offline scenarios`.
This is the first sanctioned reason (nothing to run), not a performance-§12 exemption: the addon has
combat paths (the lanes, the HUD tick, the slices) and no offline scenario brackets them. Nothing in
this run says anything about runtime cost.

**complexity (pass, one warning).** `complexity.txt` lists `rec@32-49@./tests/test_results_table.lua`
at CCN 17, a fixture builder whose score comes from its `o.x or default` lines (performance-§10), not
from branching. It is newly measured rather than a regression: this is the first sighted run.
`blindFiles` and `crashedFiles` are 0, so the figures are complete.

**tests, the Forever profile.** This bundle is the default (Retail) profile only. The Forever headless
run through the runner was not taken for this bundle; it is in the next run's analysis.

## What moved

First run — nothing to diff against; every figure above is a baseline reading.

## Complexity watch list

**Functions `lizard` warned on:**

| Function | CCN | Location | Disposition |
|---|---|---|---|
| `rec` | 17 | `tests/test_results_table.lua` | **Peel next**: its identity defaults move to a helper in the commit that records this run |

**Files by `layout-§1` band:**

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `locales/enUS.lua` | 1058 | accepted: a flat string table, one key per line, not tangle |
| 1000–1500 (on notice) | `modules/Results_Timeline.lua` | 1103 | accepted for v0.1.0: split the drawing helpers out if it grows toward the cap |

## Actions

1. `tests/test_results_table.lua`: move `rec`'s identity defaults into their own helper so it drops
   below CCN 16. New here (no deviation ID or prior finding).
2. `tests/perf.lua`: none exists. Offline scenarios for the lane push and the HUD tick would give the
   whole-branch review's unmeasured hot-path findings (docs/reviews/2026-11-10/, F-002, F-004 and
   F-005) a number. New here.
