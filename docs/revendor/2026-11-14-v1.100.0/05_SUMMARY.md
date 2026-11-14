# 05 Summary

**Combat Trail: LibKa0s v1.98.0 -> v1.100.0**, test kit revision 56 (unchanged), on
`feat/2026-11-13-callout`. Base from the `CLAUDE.md` provenance line, confirmed by the last payload
commit (`6279466`). Tag `v1.100.0`, commit `3de352cc9b3f9a3dcc492e3167f2c7eaf860da2e`, pushed.
v1.99.0 lies in the range, never vendored here.

## Minors that moved

| File | v1.98.0 | v1.100.0 |
|---|---|---|
| `Callout.lua` (`LibKa0s-Callout-1.0`) | 2 | 3 |
| `CalloutSettings.lua` | 3 | 4 |
| `OptionsNav.lua` (`LibKa0s-Options-1.0`) | 6 | 7 |
| `DebugLogDiagnostics.lua` (`LibKa0s-DebugLog-1.0`) | 9 | 10 |
| `WaypointArrow.lua` (`LibKa0s-WaypointArrow-1.0`, new) | none | 1 |
| `WaypointArrowSettings.lua` (new) | none | 1 |

Every other file is at its v1.98.0 minor. No `NEEDS_*` floor rose; no file removed. No span bundle.
No base correction.

## What arrived for free (class A)

The glow reading a stored Off / Soft / Strong as the same halo, the aligned text-to-speech words
("Pause", "Ten seconds"), "Countdown 10 to 1" in Text to play, DebugLogDiagnostics 10's report line,
and `media/waypoint/` (ships whole, unused).

## Contract blockers

Two behavior changes (01_DELTA 3g): `glow` reads as a boolean (no host read; one suite count moved)
and the default voice is `male-arena-john` (this host passes `d.packs`, and the owner's eight-pack
line makes Arena John the default). The stub's `SettingsTab` and `GetGlowColor` and the suites'
pins were fixed in the re-vendor commit.

## Declarations

Icons kept (30 names), prune `kept 32, removed 5808`. Sounds rolled to all eight packs, prune
`kept 362, removed 0`. README credits added for every new pack (Bella's SIWIS and Koniwa CC BY with
the training-data caveat; the public-domain LibriVox voices and CC0 Joe as a courtesy); Kathleen's
CC BY base kept. No dead stub mirror (`__releaseChrome`: none).

## Adopted

| Candidate | Commit |
|---|---|
| Eight packs, Arena John the default | `2dbb772` (the re-vendor commit) |
| The one Callout tab, `texts = false` | `87e990d` |
| The glow rows and `Callout:MigrateGlow` (settings schema 2 -> 3) | `87e990d` |

## Not adopted

`LibKa0s-WaypointArrow-1.0`: unreached by an interview (the run is unattended); no issue filed, on
the orchestrator's instruction.

## Gates

At each commit: `lua tests/run.lua` and `KA0S_KIT_CLIENT=forever lua tests/run.lua` green (Retail
1504 then 1509 passed, 0 failed, 1 skipped; Forever 1496 then 1501), `ka0s-bounded luacheck .`
0 warnings / 0 errors in 194 files (`libs/` and `tests/_kit/` excluded by `.luacheckrc`; the seams
`core/CalloutSetup.lua`, `core/Database.lua` and `settings/Race.lua` are inside the checked set).
