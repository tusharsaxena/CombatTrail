# 05 Summary

**Combat Trail: LibKa0s v1.106.0 -> v1.107.0**, test kit revision 57 (unchanged), on
`feat/2026-11-19-adoption-feedback`, item `AF-RV-CT`. Tag `v1.107.0`, commit
`5e96365908bcde5aac2d1010f201c962c2aab399` (local, not yet pushed). The base is the provenance line's.
The unrecorded v1.106.0 re-vendor (`7371d3b`) is recorded in the span bundle
`2026-11-19-v1.106.0-v1.106.0/`.

This bundle has no `02_CANDIDATES.md`, `03_DECISIONS.md` or `04_EXECUTION_PLAN.md`. The run was
unattended, its plan pre-decides the adoptions, and this tag brings no surface Combat Trail could
adopt: it changes the drag strip only, and Combat Trail builds none.

## Minors that moved

`WidgetsDragHandle.lua` 14 -> 15 and `WidgetsDragHandleTip.lua` 1 -> 2. No file was added.

## Reached the addon with the copy (class A)

- The race call-out's drag strip (the library's) reads `?`, settings in the window header's tints,
  packed tighter. Its settings mark opens Combat Trail's settings. Its tooltip opens above the strip.
  It has no X, because `Callout.lua` passes no `onClose`; that is a library follow-up.

## Contract blockers (3g)

None.

## Icons, credits, stubs

The `LibKa0s icons:` and `LibKa0s sounds:` lines are kept. The prune removed nothing beyond the
undeclared names the copy brought back. No README credit line moved, and there were no dead stub
mirrors.

## Adopted, declined, unreached

Nothing adopted, declined or unreached at this re-vendor.

## Gates

Retail `ka0s-bounded lua tests/run.lua`: 1571 passed, 0 failed, 1 skipped (1572). WoW Forever
`KA0S_KIT_CLIENT=forever ka0s-bounded lua tests/run.lua`: 1563 passed, 0 failed, 1 skipped (1564).
`ka0s-bounded luacheck .`: 0 warnings / 0 errors in 198 files.
