Delta: LibKa0s v1.96.0 -> v1.98.0

# 01 Delta

Combat Trail, branch `feat/2026-11-13-callout`, row C5 of
`docs/superpowers/plans/2026-11-13-callout-adoption.md`. Written before the copy. Every finding
carries the command that produced it; `<scratch>` is the extract of the tag
(`git -C ../LibKa0s archive v1.98.0 LibKa0s testkit tools | tar -x -C <scratch>/`).

## Step 0: pre-flight across the roster

The Step 0 loop over `../WowAddonStandards/standards/ADDONS.md` (*In-scope addons*) prints the same
eighteen rows as the v1.96.0 bundle's (every row `ok`, SkillMaster `no store`). Combat Trail is not
on the roster; its own newest bundle, `2026-11-13-v1.96.0`, states base v1.94.0, and the provenance
line before its re-vendor commit `cfbd85f` named v1.94.0
(`git show cfbd85f^:CLAUDE.md | grep -oE 'Bundles ... v[0-9.]+'`): **ok**, no correction.

## 3a. Claimed version, and the base

```sh
grep -n '[Bb]undles' CLAUDE.md
# 59:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.96.0 (MIT).
c=$(git log -1 --format=%h -- libs/LibKa0s tests/_kit)     # cfbd85f
git show "$c:CLAUDE.md" | grep -oE 'Bundles \[LibKa0s\]\([^)]*\) v[0-9]+\.[0-9]+\.[0-9]+'
# Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.96.0
```

The two agree: **base v1.96.0**. The payload today is the library's payload at v1.96.0 (archive of
v1.96.0 into `<scratch>/claimed`, then `diff -rq`): the library diff prints only the undeclared
icons the v1.96.0 prune removed, and the kit diff is empty.

New tag: `git -C ../LibKa0s tag --sort=-v:refname | head -1` -> `v1.98.0`;
`git -C ../LibKa0s rev-parse 'v1.98.0^{commit}'` -> `9dd6d0954efd27feb6bb27a8f4f72be674587e64`;
pushed (`git -C ../LibKa0s ls-remote --tags origin v1.98.0` -> `5c36354… refs/tags/v1.98.0`, the
tag object). v1.97.0 lies in the range and was never vendored here, so it needs no record of its
own.

Range: `git -C ../LibKa0s log --oneline v1.96.0..v1.98.0` (14 commits: the v1.97.0 fonts release,
plan rows L2 and L10, and the v1.98.0 write-route release, rows L11 and L12).
`git -C ../LibKa0s diff --stat v1.96.0 v1.98.0 -- LibKa0s testkit`: 11 files, +667 / -142.

## 3b. Actual version

`grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua` agrees with
the v1.96.0 version block file by file (Callout 1, CalloutSettings 1, Media 12, SkinDefsOthers 8).
The line and the bytes agree.

## 3c. Per-file minor delta

The loop over the tag's `LibKa0s/LibKa0s.xml` (every file, old minor beside new), filtered to the
rows that differ:

```text
Callout.lua          old: local MAJOR, MINOR = "LibKa0s-Callout-1.0", 1  new: ... 2
CalloutSettings.lua  old: local SETTINGS_MINOR = 1                       new: local SETTINGS_MINOR = 3
Media.lua            old: local MAJOR, MINOR = "LibKa0s-Media-1.0", 12   new: ... 13
SkinDefsOthers.lua   old: local OTHERS_MINOR = 8                         new: local OTHERS_MINOR = 9
```

No file is new in this range, none is behind (no cross-major skew), and no `NEEDS_*` floor rises
(CHANGELOG `## v1.97.0` and `## v1.98.0`, the versions paragraphs). Beside the Lua, the payload
gains `media/fonts/BebasNeue-Regular.ttf`, `RussoOne-Regular.ttf` and their `-OFL.txt` files, and
`FONTS.md` lists them.

## 3d. Both diffs

Before the copy, content and bytes against `<scratch>` differ exactly in the four files above, the
font files and `FONTS.md` (library), and `framework.lua` and `glyphs.lua` (kit). No `Only in
libs/LibKa0s` line: nothing was removed upstream.

## 3e. Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua'` outside `libs/` and
`tests/`: the setup seams under `core/` (Bus, Core, Env, DebugLog, Callout, Compat, Media, Charts,
Skin, Lifecycle, Launcher, Widgets, Sim, Toast, Perf, Pool), `settings/OptionsSetup.lua` (Options),
`settings/Schema.lua` (Schema, Slash), `settings/Slash.lua` (Slash), `modules/Style.lua` (Skin) and
`modules/Hud_Appearance.lua` (Media). The majors that moved and are consumed: **Callout**
(`core/CalloutSetup.lua:25`), **Media** (`core/MediaSetup.lua:4`, `modules/Hud_Appearance.lua:67`)
and **Skin** (`core/SkinSetup.lua:79`, `modules/Style.lua:317`).

## 3f. Kit revision

```sh
grep -n 'Kit.VERSION' <scratch>/testkit/framework.lua tests/_kit/framework.lua
# <scratch>/testkit/framework.lua:20:Kit.VERSION = 56
# tests/_kit/framework.lua:20:Kit.VERSION = 55
```

Kit 55 -> 56 (the generated face list in `glyphs.lua` gains the two faces; the safe set is unchanged
at 117). The pairing rule (a v1.9.0+ library takes kit 11+ in the same commit) holds by
construction: both payloads are copied whole in one commit.

## 3g. Contract delta

Read for the three consumed majors that moved:

- **Callout 1.1 -> 2.3.** `diff` of `docs/api/Callout/version-1.1-docs.md` (v1.96.0) against
  `version-2.3-docs.md` (v1.98.0), walking `Superseded by` through `version-1.2-docs.md`. Every
  change is additive (`version-2.3-docs.md:27-30`: "every change is additive, and a host that passes
  neither new descriptor field sees 1.2's behavior"). The descriptor gains `path`, `set` and
  `colorEncode` (`:34-35`, `:201-203`), the instance `SchemaRows` (`:38`, `:264`), `Get`/`Set` the
  leaf keys (`:36`). The one new MUST-shaped sentence is a statement about the *old* route:
  "not conforming for a Ka0s host" (`:41-45`). That is not a contract break (the host keeps
  working), and it is the finding row C2 blocked on, so it is adopted in this run's later commits
  (row C5 points 2-3), not in the copy. `New` raises only for a `set` with no `path`, which this
  host does not pass today. The degradation stub gains `SchemaRows` (`:463`, `:471`); today's
  `NS.CalloutStub` (`core/CalloutSetup.lua`) lacks it, which only matters once the host calls it,
  so it lands with the adoption, pinned by the surface-parity case.
- **Media 12 -> 13** (`docs/api/Media/version-13.1-docs.md`): `FONTS` gains two faces. Additive;
  "What a consumer owes: nothing".
- **SkinDefsOthers 8 -> 9** (`docs/api/Skin/version-18.1.27.9.19.19.1.1.17.4.9-docs.md`): two
  `__FACE_SIZES` rows; no skin draws either face. Additive.

`grep -rn '__Attach[A-Za-z]*' . --include='*.lua' --exclude-dir=libs --exclude-dir=_kit`: no
output. The addon hands no member to an attach seam.

**Blockers: none.**

## 3h. Tags vendored and never recorded

The audit's walk from the store's horizon (`2026-11-13`), payload commits plus `CLAUDE.md` rolls:
`v1.96.0`. Recorded: `v1.96.0`. Nothing unrecorded, so no span bundle.

## 3i. The icon declaration

`grep -n 'LibKa0s icons:' CLAUDE.md` -> line 60, the next non-blank line after the provenance line
(59), with `LibKa0s sounds:` at 61. Kept unchanged (30 names): no surface this run wires draws a new
catalog name (`version-2.3-docs.md` names no icon; the Callout settings section draws through the
host's Options instance, whose `info` mark is already declared). Sounds kept:
`callout/female-kathleen, callout/male-joe.` A pruned icon still resolves to a path and draws blank,
so the owner's in-client smoke is the backstop for a name the host forgot to declare; hand lists
have drifted before (KickCD `tests/test_mediasetup.lua:28`, WhatGroup `tests/test_mediasetup.lua:19`).

## 3j. Tests that assume the whole icon folder

`grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v '/_kit/'`:
`tests/test_hud_race_button.lua:257` opens `media/icons/<name>.tga` for the race button's declared
names only, and `tests/test_countdown.lua:142` is a message string. Neither assumes the whole
catalog. No blocker.

## Found at the gate: the degradation stub's surface

After the copy, `lua tests/run.lua` failed one case, `countdown: the stub answers every member a live
call-out has, as an idle call-out does`: `Callout instance: the degraded stub diverges from the live
surface in 1 place(s) — SchemaRows is missing (live: function)`. The instance gained `SchemaRows` at
CalloutSettings 3 (`version-2.3-docs.md:463`, `:471`: "a stub written against 1.2 gains it"). It is a
blocker in 3g's sense (the host is wrong the moment the bytes land), fixed in the re-vendor commit:
`core/CalloutSetup.lua`'s `NS.CalloutStub` gains `SchemaRows = function() return {}, {} end`, the
document's stub.
