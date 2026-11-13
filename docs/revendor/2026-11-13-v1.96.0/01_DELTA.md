Delta: LibKa0s v1.94.0 -> v1.96.0

# 01 Delta

Combat Trail, branch `feat/2026-11-13-callout`, run plan row C1 of LibKa0s
`docs/superpowers/plans/2026-11-13-callout.md`. Written before the copy. Every finding carries the
command that produced it; `<scratch>` is the extract of the tag
(`git -C ../LibKa0s archive v1.96.0 LibKa0s testkit tools | tar -x -C <scratch>/`).

## Step 0: pre-flight across the roster

The Step 0 loop over `../WowAddonStandards/standards/ADDONS.md` (*In-scope addons*):

```text
AbsorbTracker  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@f9153a8  ok
AuraMaster  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@ad6482d  ok
BankLedger  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@e3102c3  ok
ConsumableMaster  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@ba8f2ec  ok
DpsRace  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@d450e20  ok
DropWatcher  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@7608536  ok
KickCD  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@1f40c2f  ok
LibKa0sSkinTester  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@e5acf9f  ok
LootHistory  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@b6e2ad6  ok
MultiMeters  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@87a0620  ok
OutfitterReborn  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@0e45a48  ok
PanelMaster  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@ea45e3b  ok
PartyFrameEnhanced  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@cc8a683  ok
PremadeGroupsFilterExtension  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@738eec1  ok
PrettyChat  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@5278466  ok
QuickComms  2026-11-10-v1.95.0  base v1.93.0  vendored-before v1.93.0@1e7d913  ok
SkillMaster: no store
WhatGroup  2026-11-07-v1.93.0  base v1.92.0  vendored-before v1.92.0@1ce43c7  ok
```

No `MISMATCH`. Combat Trail is not on the roster of the standards checkout (`master`), and has no
`docs/revendor/` store before this bundle, so there is no earlier bundle to correct.

## 3a. Claimed version, and the base

```sh
grep -n '[Bb]undles' CLAUDE.md
# 58:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.94.0 (MIT).
c=$(git log -1 --format=%H -- libs/LibKa0s tests/_kit)     # b0dd9ab
git show "$c:CLAUDE.md" | grep -oE 'Bundles \[LibKa0s\]\([^)]*\) v[0-9]+\.[0-9]+\.[0-9]+'
# Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.94.0
```

The two agree: **base v1.94.0**. The payload today is the library's payload at v1.94.0 (archive of
v1.94.0 into `<scratch>/claimed`, then `diff -rq` against both vendored folders): the library diff
prints only `Only in <scratch>/claimed/LibKa0s/media/icons…` lines (the undeclared icons the v1.94.0
prune removed), and the kit diff is empty.

One stale detail in the line's paragraph, not in the line: `CLAUDE.md` named "commit
5e71662d117feb7a5c572a3b3e7c7e780e06c0d7" for v1.94.0, which is the annotated **tag object**
(`git -C ../LibKa0s rev-parse v1.94.0` -> `5e71662…`; `rev-parse v1.94.0^{commit}` -> `2d2be05…`).
The new paragraph names the commit: `git -C ../LibKa0s rev-parse 'v1.96.0^{commit}'` ->
`f1b4b155bf184d755ee6afe1b876cbcf85478aeb`. The tag is pushed
(`git -C ../LibKa0s ls-remote --tags origin v1.96.0` -> `fd08890… refs/tags/v1.96.0`).

Range: `git -C ../LibKa0s log --oneline v1.94.0..v1.96.0` (27 commits: the v1.95.0 Role release
`QFE-*`, and the v1.96.0 Callout run `L1`..`L9`). `git -C ../LibKa0s diff --stat v1.94.0 v1.96.0 --
LibKa0s testkit tools`: 102 files, 3248 insertions, 179 deletions; outside the 86 `.ogg` clips and
the pack license and credit files, the changed files are `Callout.lua` (new), `CalloutSettings.lua`
(new), `Role.lua` (new), `DebugLogDiagnostics.lua`, `Launcher.lua`, `LibKa0s.xml`, and in the kit
`README.md`, `client_globals.lua`, `framework.lua`, `vendor_sync.lua`, plus `tools/prune-icons.lua`.

## 3b. Actual version

```sh
grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua
```

72 constants, every one equal to v1.94.0's (the 3a payload check). Line and bytes agree.

## 3c. Per-file minor delta (v1.94.0 vendored -> v1.96.0)

The loop over the tag's `LibKa0s/LibKa0s.xml`. Only the rows that moved; the other 72 files are at
the same minor.

| File | Old | New |
|---|---|---|
| `Role.lua` | (absent) | `LibKa0s-Role-1.0` 1 (new major, v1.95.0) |
| `Callout.lua` | (absent) | `LibKa0s-Callout-1.0` 1 (new major, v1.96.0) |
| `CalloutSettings.lua` | (absent) | `SETTINGS_MINOR` 1 (paired on Callout) |
| `DebugLogDiagnostics.lua` | `DIAG_MINOR` 7 | `DIAG_MINOR` 9 |
| `Launcher.lua` | `LibKa0s-Launcher-1.0` 9 | 10 |

No file is behind the tag after the copy, so no cross-major skew. No `NEEDS_*` floor rises (both
CHANGELOG blocks say so).

## 3d. Both diffs, before the copy

```sh
diff -rq --strip-trailing-cr <scratch>/LibKa0s libs/LibKa0s | grep -v 'media/icons'
```

```text
Only in <scratch>/LibKa0s: Callout.lua
Only in <scratch>/LibKa0s: CalloutSettings.lua
Files <scratch>/LibKa0s/DebugLogDiagnostics.lua and libs/LibKa0s/DebugLogDiagnostics.lua differ
Files <scratch>/LibKa0s/Launcher.lua and libs/LibKa0s/Launcher.lua differ
Files <scratch>/LibKa0s/LibKa0s.xml and libs/LibKa0s/LibKa0s.xml differ
Only in <scratch>/LibKa0s: Role.lua
Only in <scratch>/LibKa0s/media: sounds
```

The byte diff (`diff -rq` without `--strip-trailing-cr`) prints the same set: no line-ending drift.
The kit diff, content and bytes alike, is `README.md`, `client_globals.lua`, `framework.lua` and
`vendor_sync.lua`. No `Only in libs/LibKa0s` and no `Only in tests/_kit` line: nothing was removed
upstream, so the copy deletes nothing. The remaining `Only in <scratch>/LibKa0s/media/icons…` lines
are the undeclared icons (the declaration working).

## 3e. Consumption map

```sh
grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v '/libs/' | grep -v '/tests/'
```

Consumed (host lookups): Bus (`core/Bus.lua`), Charts (`core/ChartsSetup.lua`), Compat
(`core/Compat.lua`), Core (`core/CoreSetup.lua`), DebugLog (`core/DebugLogSetup.lua`), Env
(`core/EnvSetup.lua`), Launcher (`core/LauncherSetup.lua`), Lifecycle (`core/LifecycleSetup.lua`),
Media (`core/MediaSetup.lua`, `modules/Hud_Appearance.lua`), Perf (`core/PerfSetup.lua`), Pool
(`core/PoolSetup.lua`), Sim (`core/SimSetup.lua`), Skin (`core/SkinSetup.lua`, `modules/Style.lua`),
Toast (`core/ToastSetup.lua`), Widgets (`core/WidgetsSetup.lua`), Options
(`settings/OptionsSetup.lua`), Schema (`settings/Schema.lua`), Slash (`settings/Schema.lua`,
`settings/Slash.lua`).

In the payload with no lookup: **Callout** (new), **Role** (new), Glow, Item, IconBrowser.

## 3f. Kit revision

```sh
grep -n 'Kit.VERSION' <scratch>/testkit/framework.lua tests/_kit/framework.lua
# <scratch>/testkit/framework.lua:20:Kit.VERSION = 55
# tests/_kit/framework.lua:20:Kit.VERSION = 53
```

Kit 53 -> **55** in the same commit as the library (the pairing rule, satisfied by copying both
payloads whole). 54: `client_globals.lua`'s `strip`, `scan` and `judge` split under CCN 15, no
behavior change. 55: `vendor_sync.lua` holds `media/sounds/` to the `LibKa0s sounds:` line.

## 3g. Contract delta

Majors both moved (3c) and consumed (3e): **DebugLog** and **Launcher**.

```sh
git -C ../LibKa0s show v1.96.0:docs/api/Launcher/version-10-docs.md | head -20
diff <(git -C ../LibKa0s show v1.94.0:docs/api/Launcher/version-9-docs.md) \
     <(git -C ../LibKa0s show v1.96.0:docs/api/Launcher/version-10-docs.md)
diff <(git -C ../LibKa0s show v1.94.0:docs/api/DebugLog/version-22.7.1.4-docs.md) \
     <(git -C ../LibKa0s show v1.96.0:docs/api/DebugLog/version-22.9.1.4-docs.md)
```

- Launcher 9 -> 10 (`docs/api/Launcher/version-10-docs.md`, *What changed at this version*): the
  descriptor checks move from `lib.New` to a file-local `checkDescriptor`, the same messages at the
  host's line. "What a host owes. Nothing." The only other prose change is the `New` paragraph
  naming the `entryClients` refusal version 9 already added.
- DebugLog 22.7.1.4 -> 22.9.1.4 (`version-22.9.1.4-docs.md`, *What changed at this version* and
  *at version 22.8.1.4*): the report's `LibKa0s running:` line names Role and Callout. "No member
  change."
- Kit 55 (`docs/api/testkit/version-55-docs.md`, *What a consumer owes*): run the tag's prune; a
  consumer passing its own `pairs` to `register` adds `sounds`. `tests/test_vendor_sync.lua` calls
  `VendorSync.register(T, { root = T.root })` with the default pairs, so nothing is owed.

```sh
grep -rn '__Attach[A-Za-z]*' . --include='*.lua' --exclude-dir=libs --exclude-dir=Libs --exclude-dir=_kit
# (no output)
```

The addon hands no member to an `__Attach*` seam. **Blockers: none.**

## 3h. Tags vendored and never recorded

No `docs/revendor/` store before this bundle, so there is no horizon and nothing to back-fill. The
store is measured from this run on. No span bundle.

## 3i. The icon and sound declarations

```sh
grep -n 'LibKa0s icons:' CLAUDE.md
# 59:LibKa0s icons: arrow-left, chart, chat, ... unlock, volume-high.
```

The icon line sits directly under the provenance line and is **kept unchanged**: no surface this
re-vendor wires draws a new catalog name (the Callout is not adopted in this row; it is C2). The
provenance line ends its own line (no run-on prose), so no split is needed.

Sounds, decided by the run plan (row C1, the owner's design: Combat Trail is the Callout's first
consumer and ships both packs). The grammar, from the tag's `testkit/vendor_sync.lua`
(`parseSoundLine`, its header example `LibKa0s sounds: callout/female-kathleen, callout/male-joe.`)
and testing-§11 / library-stack-§7 *The sound subset* (standard v2.108.0), is a comma-separated
list of pack folders ending in a period, on the first non-blank line after the icons line:

```text
LibKa0s sounds: callout/female-kathleen, callout/male-joe.
```

Recorded as decided, not asked. The in-client smoke is still the backstop for the icon list: hand
lists have drifted before (KickCD `tests/test_mediasetup.lua:28`, WhatGroup
`tests/test_mediasetup.lua:19`), and a pruned icon draws blank without raising.

## 3j. Tests that assume the whole icon folder

```sh
grep -rn "media/icons\|media/sounds\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v '/_kit/'
# tests/test_hud_race_button.lua:257:        local got = artBox(T.root .. "/libs/LibKa0s/media/icons/" .. name .. ".tga")
```

It reads only the names in `Style.ART_BOX`, which are declared names, not the catalog. Not a
blocker. Dead stub mirrors: `grep -rn '__releaseChrome' . --include='*.lua' --exclude-dir=libs
--exclude-dir=_kit` prints nothing.
