# 05 Summary

**Combat Trail: LibKa0s v1.94.0 -> v1.96.0**, test kit revision 53 -> 55, on
`feat/2026-11-13-callout`. Base from the `CLAUDE.md` provenance line, confirmed by the last payload
commit (`b0dd9ab`) and by the payload matching v1.94.0 (01_DELTA 3a). Tag `v1.96.0`, commit
`f1b4b155bf184d755ee6afe1b876cbcf85478aeb`, pushed.

## Minors that moved

| File | v1.94.0 | v1.96.0 |
|---|---|---|
| `Role.lua` (`LibKa0s-Role-1.0`) | absent | 1 |
| `Callout.lua` (`LibKa0s-Callout-1.0`) | absent | 1 |
| `CalloutSettings.lua` | absent | 1 |
| `DebugLogDiagnostics.lua` | 7 | 9 |
| `Launcher.lua` | 9 | 10 |

Every other file is at its v1.94.0 minor. No `NEEDS_*` floor rose. No span bundle (first bundle in
the store). No base correction.

## What arrived for free (class A)

Launcher 10 (descriptor checks in a helper, same messages), DebugLogDiagnostics 9 (the report names
Role and Callout), kit 54 (CCN split, no behavior change) and kit 55 (the sound subset gate).

## Contract blockers

None. Launcher's and DebugLog's documents say a host owes nothing; the addon hands no member to an
`__Attach*` seam; `tests/test_vendor_sync.lua` uses the kit's default pairs.

## Declarations, prune and credits

- `LibKa0s icons:` kept unchanged (30 names). The prune: `kept 32 file(s), removed 5808` under
  `media/icons/` (the catalog the whole-folder copy brought back, Open Iconic and Phosphor kept,
  nothing new removed against the previous tree).
- `LibKa0s sounds: callout/female-kathleen, callout/male-joe.` written directly under the icon line
  (decided by the run plan). The prune: `2 voice pack(s) declared; kept 91 file(s), removed 0`.
- No provenance split needed. The `CLAUDE.md` vendor paragraph names the sound prune and the commit
  (the old paragraph named the v1.94.0 tag object `5e71662…`, not its commit).
- README `## Credits` gains the voice packs: Piper, the Nabu Casa Voice Datasets (CC0 1.0), and the
  CC BY 4.0 attribution kathleen's `CREDITS.md` requires for its Hi-Fi TTS base model (reader 92,
  Cori Samuel; Bakhturina, Lavrukhin, Ginsburg and Zhang, NVIDIA, Interspeech 2021, with the
  changes stated); joe credited as a courtesy (CC0). `DEPENDENCIES.md` names the packs as part of
  the vendored media. No icon-set credit changed. No dead stub mirror (`__releaseChrome` absent).

## Adopted, declined, unreached

Nothing adopted or declined in this run, and no issue filed (unattended run). Callout: adopt in row
C2. Role: unreached, recommended not now (02_CANDIDATES).

## Gates

Before the copy the suite was already red on one case, independent of the re-vendor:
`prose: no authored file carries a British spelling` at `tests/test_race_clock.lua:152`
(`t.timer.cancelled`, AceTimer's and the kit mock's field name; from `89438d0`, the Race mode
merge). It is fixed in its own prerequisite commit with `tests/prose_waivers.lua`, per file and per
word, as the gate's own message directs and as DPS Race already does for the same field.

After the copy, the prune and the waiver:

- `lua tests/run.lua`: 1444 passed, 0 failed, 1 skipped (the kit's opt-out diagnostics case), 1445.
- `KA0S_KIT_CLIENT=forever lua tests/run.lua`: 1436 passed, 0 failed, 1 skipped, 1437.
- `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .`: 0 warnings / 0 errors in 191 files.

`libs/LibKa0s/ is the LibKa0s release CLAUDE.md says this addon bundles` passes (the vendored
payload gate, icons and sounds held to their lines).
