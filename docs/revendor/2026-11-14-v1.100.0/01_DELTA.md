Delta: LibKa0s v1.98.0 -> v1.100.0

# 01 Delta

Combat Trail, branch `feat/2026-11-13-callout`, row C11 of
`docs/superpowers/plans/2026-11-13-callout-adoption.md`. Written before the copy. Every finding
carries the command that produced it; `<scratch>` is the extract of the tag
(`git -C ../LibKa0s archive v1.100.0 LibKa0s testkit tools | tar -x -C <scratch>/`). The run is
unattended (the orchestrator's row C11): no interview, nothing adopted beyond the owner's decisions
for this row, no issue filed.

## Step 0: pre-flight across the roster

The Step 0 loop over `../WowAddonStandards/standards/ADDONS.md` (*In-scope addons*) prints eighteen
rows, every one `ok` (SkillMaster `no store`; AuraMaster's newest bundle is now
`2026-11-14-v1.98.0`, base v1.93.0, `ok`). Combat Trail is not on the roster; its own newest bundle,
`2026-11-14-v1.98.0`, states base v1.96.0, and the provenance line before its re-vendor commit
`6279466` named v1.96.0 (`git show 6279466^:CLAUDE.md | grep -oE 'Bundles ... v[0-9.]+'`): **ok**,
no correction.

## 3a. Claimed version, and the base

```sh
grep -n '[Bb]undles' CLAUDE.md
# 59:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.98.0 (MIT).
c=$(git log -1 --format=%h -- libs/LibKa0s tests/_kit)     # 6279466
git show "$c:CLAUDE.md" | grep -oE 'Bundles \[LibKa0s\]\([^)]*\) v[0-9]+\.[0-9]+\.[0-9]+'
# Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.98.0
```

The two agree: **base v1.98.0**.

New tag: `git -C ../LibKa0s tag --sort=-v:refname | head -1` -> `v1.100.0`;
`git -C ../LibKa0s rev-parse 'v1.100.0^{commit}'` -> `3de352cc9b3f9a3dcc492e3167f2c7eaf860da2e`;
pushed (`git -C ../LibKa0s ls-remote --tags origin v1.100.0` -> `ef38fce… refs/tags/v1.100.0`, the
tag object). v1.99.0 lies in the range and was never vendored here, so it needs no record of its
own.

Range: `git -C ../LibKa0s log --oneline v1.98.0..v1.100.0` (22 commits: the v1.99.0 WaypointArrow
release, plan rows L1; the v1.100.0 Callout release, rows L13 to L16).
`git -C ../LibKa0s diff --stat v1.98.0 v1.100.0 -- LibKa0s testkit`: 286 files, +2347 / -94 (most
of them the six new voice packs' clips and the waypoint TGAs).

## 3b. Actual version

`grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua` agrees with
the v1.98.0 version block file by file (Callout 2, CalloutSettings 3, DebugLogDiagnostics 9,
OptionsNav 6). The line and the bytes agree.

## 3c. Per-file minor delta

The loop over the tag's `LibKa0s/LibKa0s.xml`, filtered to the rows that differ:

```text
Callout.lua                old: local MAJOR, MINOR = "LibKa0s-Callout-1.0", 2   new: ... 3
CalloutSettings.lua        old: local SETTINGS_MINOR = 3                        new: local SETTINGS_MINOR = 4
WaypointArrow.lua          old: (none)                                          new: local MAJOR, MINOR = "LibKa0s-WaypointArrow-1.0", 1
WaypointArrowSettings.lua  old: (none)                                          new: local SETTINGS_MINOR = 1
DebugLogDiagnostics.lua    old: local DIAG_MINOR = 9                            new: local DIAG_MINOR = 10
OptionsNav.lua             old: local NAV_MINOR = 6                             new: local NAV_MINOR = 7
```

Two files are new in this range (the WaypointArrow major, v1.99.0), none is behind (no cross-major
skew), and no `NEEDS_*` floor rises (CHANGELOG `## v1.99.0` and `## v1.100.0`, the versions
paragraphs). Beside the Lua, the payload gains `media/waypoint/` (eight TGAs, ships whole: no
declaration governs it) and six voice-pack folders under `media/sounds/callout/`.

## 3d. Both diffs

Before the copy, `diff -rq --strip-trailing-cr <scratch>/LibKa0s libs/LibKa0s` (the undeclared icons
aside) differs in `Callout.lua`, `CalloutSettings.lua`, `DebugLogDiagnostics.lua`, `OptionsNav.lua`
and `LibKa0s.xml`, and is `Only in <scratch>` for the two WaypointArrow files, `media/waypoint` and
the six new packs. `female-kathleen` and `male-joe` are unchanged. The kit diff is empty. No `Only
in libs/LibKa0s` line: nothing was removed upstream.

## 3e. Consumption map

Unchanged from the v1.98.0 bundle: the setup seams under `core/`, `settings/OptionsSetup.lua`
(Options), `settings/Schema.lua` and `settings/Slash.lua` (Schema, Slash), `modules/Style.lua`
(Skin), `modules/Hud_Appearance.lua` (Media). The majors that moved and are consumed: **Callout**
(`core/CalloutSetup.lua:25`), **Options** (OptionsNav, `settings/OptionsSetup.lua:13`) and
**DebugLog** (DebugLogDiagnostics, `core/DebugLogSetup.lua`). **WaypointArrow** has no lookup: an
unadopted module (Step 5, class C).

## 3f. Kit revision

```sh
grep -n 'Kit.VERSION' <scratch>/testkit/framework.lua tests/_kit/framework.lua
# <scratch>/testkit/framework.lua:20:Kit.VERSION = 56
# tests/_kit/framework.lua:20:Kit.VERSION = 56
```

Kit 56 on both sides. The pairing rule (a v1.9.0+ library takes kit 11+ in the same commit) holds by
construction: both payloads are copied whole in one commit.

## 3g. Contract delta

Read for the three consumed majors that moved:

- **Callout 2.3 -> 3.4.** `docs/api/Callout/version-3.4-docs.md` (v1.100.0) against
  `version-2.3-docs.md` (v1.98.0). Additive: `SettingsTab` (`:142`), `layout = "side"` (`:143`),
  `SchemaRows(prefix, { texts = false })` (`:144`), the Play list's countdown (`:146`), the glow's
  eight new keys (`:69-78`, `:107-112`), `MigrateGlow` and `GLOW_LEGACY` (`:108-109`), the six packs
  (`:28-37`). **Two behavior changes** reach a host that changes nothing (`:52-60`, `:39-46`):
  - `Get("glow")` and `Look().glow` answer a boolean (`:52-55`). `grep -rn '"glow"\|\.glow\b'` over
    `core modules settings` finds no host read of the call-out's glow (the lane icons' `f.glow` is
    their own). Host code: no blocker. The suite pins it in `tests/test_callout_settings.lua`'s
    scalar count (15 -> 23 with the eight glow keys), fixed with the copy.
  - `DEFAULTS.voice` is `"male-arena-john"` (`:39-46`). This host passes `d.packs`
    (`core/CalloutSetup.lua`, `NS.NewCallout`), so with the old line it would keep Kathleen; the
    owner's decision for this row ships all eight packs, so the default becomes Arena John and
    `NS.CALLOUT_PACKS` lists the eight (`tests/test_countdown.lua` holds it to the sounds line, so it
    moves in the copy's commit). `tests/test_countdown.lua:119-120` (two packs, default `female`)
    move with it.
  - The degradation stub gains `SettingsTab` and `GetGlowColor` (`:651-669`): the surface-parity case
    in `tests/test_countdown.lua` fails without them, so `NS.CalloutStub` gains both in the copy's
    commit (the v1.98.0 precedent).
- **Options, OptionsNav 6 -> 7** (`docs/api/Options/version-38.5.45.3.7.2.9.17.3.1.4.19.13.7.5.8.7.11.1.1.4-docs.md`):
  the instance gains `O.SideTabs`. Additive. The library-absent `NS.Helpers` stub
  (`settings/OptionsSetup.lua`, the no-op list) gains `SideTabs` with the one-tab adoption, as the
  library's releasing note asks of an Options stub.
- **DebugLog, DebugLogDiagnostics 9 -> 10**: the report's `LibKa0s running:` line names
  WaypointArrow; no member change. `grep -rn 'DebugLogDiagnostics' tests` outside the kit: no pin.

`grep -rn '__Attach[A-Za-z]*' . --include='*.lua' --exclude-dir=libs --exclude-dir=_kit`: no
output. The addon hands no member to an attach seam.

**Blockers:** the stub's two members, the pack list and the three suite pins above, all fixed in the
copy's commit. None needs a decision.

## 3h. Tags vendored and never recorded

The audit's walk from the store's horizon (`2026-11-13`), payload commits plus `CLAUDE.md` rolls:
`v1.96.0`, `v1.98.0`. Recorded: `v1.96.0`, `v1.98.0`. Nothing unrecorded, so no span bundle.

## 3i. The declarations

`grep -n 'LibKa0s icons:' CLAUDE.md` -> line 60, the next non-blank line after the provenance line
(59). Kept unchanged (30 names): `O.SideTabs`, `SettingsTab` and the glow rows draw no catalog name
(`git -C ../LibKa0s diff v1.98.0 v1.100.0 -- LibKa0s/OptionsNav.lua LibKa0s/CalloutSettings.lua
LibKa0s/Callout.lua | grep -i icon`: no output). A pruned icon still resolves to a path and draws
blank, so the owner's in-client smoke is the backstop for a name the host forgot to declare; hand
lists have drifted before (KickCD `tests/test_mediasetup.lua:28`, WhatGroup
`tests/test_mediasetup.lua:19`).

`LibKa0s sounds:` (line 61), **decided by the owner for this row**: all eight packs ship, in the
tag's `PACKS` order: `callout/male-arena-john, callout/female-kathleen, callout/female-kristin,
callout/female-cori, callout/female-bella, callout/male-joe, callout/male-john,
callout/male-norman.` (the names `version-3.4-docs.md:575-577` lists; the grammar is
`testkit/vendor_sync.lua`'s `parseSoundLine`: comma-separated folder names, one period). Listed
rather than `all.` so `NS.CALLOUT_PACKS` keeps a line to be held to and a later library pack does not
arrive unannounced.

## 3j. Tests that assume the whole icon folder

`grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v '/_kit/'`: unchanged
from v1.98.0 (`tests/test_hud_race_button.lua:257`, declared names only). No blocker.
