# Perf analysis — Ka0s Combat Trail

The standing store of **in-game** performance captures (documentation-§3, Tier 2: the harness is
wired; performance-§8). Cumulative across versions, so captures compare from one release to the
next. Offline runs live in [`../automated-tests/README.md`](../automated-tests/README.md), not here.

## Bundles

One frozen, dated bundle per capture at `docs/perf-analysis/<YYYYMMDD-HHMMSS>/`, stamped in local
time from the record's own timestamp. Each carries three files:

- `report.md`, the report the console printed after `/kct perf finish`;
- `dump.json`, the verbatim one-line JSON dump;
- `ANALYSIS.md`, the write-up.

The record's field-by-field contract is LibKa0s-Perf-1.0's, documented with the library; this file
does not copy it. In short, a record names the addon, version and client build, the window it
covered (in and out of combat), and per bucket the call count, total and peak milliseconds.

## Taking one

- `/kct perf start`, then play the fight to measure.
- `/kct perf finish`, then press **Copy** in the debug console for the report and the dump.
- Hand both to `/dev-copilot:wow-perf-analysis`, which writes the bundle and its analysis.

The buckets and what each brackets are in [`../performance.md`](../performance.md).

## Index

| Bundle | Version | Client | What was measured |
|---|---|---|---|
| (none yet) | | | |

This file is the one in the store that is rewritten; the bundles are frozen.
