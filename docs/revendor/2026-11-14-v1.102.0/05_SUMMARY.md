# 05 Summary

**Combat Trail: LibKa0s v1.100.0 -> v1.102.0**, test kit revision 56 (unchanged), on
`feat/2026-11-13-callout`, row C12. Tag `v1.102.0`, commit
`2748549521ea9588fbe9a4c97b48828f21d35a84`. v1.101.0 lies in the range, never vendored here.

This bundle has no `03_DECISIONS.md` or `04_EXECUTION_PLAN.md`: the run was unattended, with no
interview. The one decision (take the owner's defaults as shipped, keep the black glow for a migrated
Soft / Strong profile, add no schema step) is recorded in `02_CANDIDATES.md`, and the work landed in
three commits: `6fdc66b` (the re-vendor and the suites' pins), `3bc0440` (the migrated profile's new
look, characterized) and `ed47a14` (the docs).

## Minors that moved

| File | v1.100.0 | v1.102.0 |
|---|---|---|
| `Callout.lua` (`LibKa0s-Callout-1.0`, key 4.5) | 3 | 4 |
| `CalloutSettings.lua` | 4 | 5 |
| `OptionsWidgets.lua` (`LibKa0s-Options-1.0`) | 45 | 46 |
| `WaypointArrow.lua` (`LibKa0s-WaypointArrow-1.0`, key 2.2) | 1 | 2 |
| `WaypointArrowSettings.lua` | 1 | 2 |

## Declarations

Icons kept (30 names), prune `kept 32, removed 5808`. Sounds kept (eight packs), prune
`kept 362, removed 0`. No README credit moves: no icon set, voice pack or font file arrived (Oxanium
SemiBold was already in the vendored Media payload).

## Adopted

The owner's Look defaults and the one tab with no sample line, as the library ships them (the suites'
pins in the re-vendor commit; the migrated profile's new look characterized and documented after).

## Not adopted

See `02_CANDIDATES.md`.
