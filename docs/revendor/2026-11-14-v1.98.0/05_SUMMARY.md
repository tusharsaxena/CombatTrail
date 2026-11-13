# 05 Summary

**Combat Trail: LibKa0s v1.96.0 -> v1.98.0**, test kit revision 55 -> 56, on
`feat/2026-11-13-callout`. Base from the `CLAUDE.md` provenance line, confirmed by the last payload
commit (`cfbd85f`) and by the payload matching v1.96.0 (01_DELTA 3a). Tag `v1.98.0`, commit
`9dd6d0954efd27feb6bb27a8f4f72be674587e64`, pushed. v1.97.0 lies in the range, never vendored here.

## Minors that moved

| File | v1.96.0 | v1.98.0 |
|---|---|---|
| `Callout.lua` (`LibKa0s-Callout-1.0`) | 1 | 2 |
| `CalloutSettings.lua` | 1 | 3 |
| `Media.lua` (`LibKa0s-Media-1.0`) | 12 | 13 |
| `SkinDefsOthers.lua` | 8 | 9 |

Every other file is at its v1.96.0 minor. No `NEEDS_*` floor rose, no file added or removed. No span
bundle. No base correction.

## What arrived for free (class A)

Media 13's two Callout faces (`Ka0s Bebas Neue`, `Ka0s Russo One`, SIL OFL 1.1, with their license
files under `media/fonts/`), CalloutSettings 2's font order (`FONT_FACES` first), SkinDefsOthers 9's
face sizes, and kit 56's glyph face list.

## Contract blockers

None in the library's documents (01_DELTA 3g). One at the gate: the degradation stub lacked the
instance's new `SchemaRows`, which the suite's surface-parity case caught. Fixed in the re-vendor
commit (`core/CalloutSetup.lua`), with the document's `function() return {}, {} end`.

## Declarations, prune and credits

- `LibKa0s icons:` kept (30 names). The prune: `kept 32 file(s), removed 5808` (Open Iconic and
  Phosphor kept; the whole catalog the copy brought back removed again, nothing new removed).
- `LibKa0s sounds:` kept (`callout/female-kathleen, callout/male-joe.`). The prune:
  `2 voice pack(s) declared; kept 91 file(s), removed 0`.
- No provenance split. The vendor paragraph's tag and commit rolled with the line.
- README `## Credits`: no change (no icon set added or removed; the README credits no font today).
  No dead stub mirror.

## Adopted, declined, unreached

Adopted: the Callout's settings on the host's write route (02_CANDIDATES 1), in this run's commits
after the re-vendor, recorded in row C5 of `docs/superpowers/plans/2026-11-13-callout-adoption.md`.
Nothing declined, no issue filed (unattended run). Role stays unreached from the v1.96.0 bundle.

## Gates (the re-vendor commit)

- `lua tests/run.lua`: 1455 passed, 0 failed, 1 skipped, 1456.
- `KA0S_KIT_CLIENT=forever lua tests/run.lua`: 1447 passed, 0 failed, 1 skipped, 1448.
- `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .`: 0 warnings / 0 errors in 192 files.
