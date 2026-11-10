# Analysis — 20261110-130352

- **Addon:** CombatTrail 0.1.0
- **Verdict:** green
- **Commit:** d8ce97c (feat/2026-11-10-combat-trail-v0.1.0)
- **Previous run:** 20261110-130020

## Headline

Green on both kit profiles: lint 0/0 over 131 files, and 726 passed, 1 skipped, 0 failed of 727 on
Retail and on Forever. The one function the previous run warned on (`rec`, CCN 17) is gone, so the
complexity watch list is empty and Max CCN is 15. Perf is still a skip because no `tests/perf.lua`
exists. Nothing here needs action before the tag except the perf gap, which the tag treats as NOT
EVALUATED.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261110-130020 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 131 files | [`lint.txt`](lint.txt) | no change |
| tests | pass | 726 passed, 1 skipped, 0 failed, 727 total (Retail); Forever, run by the runner with `KA0S_KIT_CLIENT=forever --suite tests --no-bundle` at this commit: 726 passed, 0 failed, 1 skipped, 727 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | no change |
| perf | skip | 0 scenarios | none: no `tests/perf.lua` | no change |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | 1 warning to 0 |

| Metric | Value |
|---|---|
| Total NLOC | 29566 |
| Functions | 3736 |
| Avg NLOC / function | 7.1 |
| Avg CCN | 2.7 |
| Max CCN | 15 |
| Avg tokens / function | 65.6 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 2 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |
| Crashed files (lizard raised) | 0 |

**perf (skip).** `manifest.json` records `no tests/perf.lua — this addon ships no offline scenarios`.
This is the first sanctioned reason (nothing to run), not a performance-§12 exemption. The addon has
combat paths and no offline scenario measures them, so the record says nothing about runtime cost.

**tests, the Forever profile.** The Forever figure is from the runner's own `--no-bundle` run at
d8ce97c (stamp 20261110-130419, nothing written), as the playbook's dual-client step asks. It is not
an artifact in this bundle; `tests.txt` is the Retail run.

## What moved

- **lint:** 0/0 over 131 files, unchanged.
- **tests:** 726/1/727, unchanged. The cases are the same set; only a test helper was restructured.
- **perf:** skip, unchanged.
- **complexity:** warnings 1 to 0 and Max CCN 17 to 15, from moving `rec`'s identity defaults into
  `identOf` (functions 3735 to 3736, NLOC 29563 to 29566). The averages did not move.

## Complexity watch list

**Functions `lizard` warned on:**

None.

**Files by `layout-§1` band:**

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `locales/enUS.lua` | 1058 | accepted: a flat string table, one key per line, not tangle |
| 1000–1500 (on notice) | `modules/Results_Timeline.lua` | 1103 | accepted for v0.1.0: split the drawing helpers out if it grows toward the cap |

## Actions

1. `tests/perf.lua`: none exists. Offline scenarios for the lane push and the HUD tick would give the
   whole-branch review's unmeasured hot-path findings (docs/reviews/2026-11-10/, F-002, F-004 and
   F-005) a number, and turn the perf suite from skip into a reading. Carried from 20261110-130020.
