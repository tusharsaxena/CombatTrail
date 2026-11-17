Delta: LibKa0s v1.102.0 -> v1.105.0

# 01 Delta

Combat Trail, branch `feat/2026-11-16-libka0s-75-plus`, item `RV-CT` of the cross-repo run
Ka0sAddonsCommonTasks `docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS/` (design section 5). The run is
unattended: this is the copy and bundle half of `/dev-copilot:wow-revendor-libka0s` (dev-copilot
2.10.0) only. There was no adoption interview and no issue was filed. The adoption candidates are
listed in `02_CANDIDATES.md` as owed in phase [3] of that run. The tag was read only through
`git -C ../LibKa0s archive v1.105.0 LibKa0s testkit tools`. The tag is local and not yet on origin,
which the run expects. The sibling checkout's working tree was not touched.

## Base and tag

- `grep -n '[Bb]undles' CLAUDE.md` before the copy: `Bundles [LibKa0s](...) v1.102.0 (MIT).`
- Last payload commit `git log -1 --format=%H -- libs/LibKa0s tests/_kit` is `6fdc66b`, and its
  `CLAUDE.md` names `v1.102.0`. The two agree.
- `git -C ../LibKa0s archive v1.102.0 LibKa0s testkit` compared with `diff -rq` against
  `libs/LibKa0s` and `tests/_kit` before the copy gave no difference outside the pruned
  `media/icons` and `media/sounds`. The payload matched the claimed tag.
- Minors before the copy (3b) are the v1.102.0 minors in the table below. The line and the bytes
  agree.
- New tag: `v1.105.0`, `git -C ../LibKa0s rev-parse v1.105.0^{commit}` ->
  `79b1d9c40d3729e75a8c1ece519f445f6a20b1c9`. v1.103.0 and v1.104.0 lie in the range and were
  never vendored here, so they need no record of their own.
- `git -C ../LibKa0s log --oneline v1.102.0..v1.105.0`: 27 commits.
- `git -C ../LibKa0s diff --stat v1.102.0 v1.105.0 -- LibKa0s testkit`: 32 files, +3442 / -580.
  New files (`--name-status`, `A`): `LibKa0s/Tooltip.lua`, `LibKa0s/WidgetsDragHandleTip.lua`,
  `LibKa0s/WidgetsHeader.lua`, `LibKa0s/WidgetsBar.lua`, `LibKa0s/OptionsSkinPickerQueue.lua`,
  `testkit/mock_screen.lua`. Nothing was removed upstream.

Step 0 pre-flight for this addon: the newest single-tag bundle, `2026-11-14-v1.102.0`, states base
`v1.100.0`, and the provenance line before `6fdc66b` was `v1.100.0`. That is ok, so no base
correction is owed.

## Per-file minor delta

The loop is 3c's, run over the tag's `LibKa0s.xml`. Only the files that moved are listed:

```text
Core.lua                    MINOR 17 -> 18      (LibKa0s-Core-1.0)
Tooltip.lua                 new, MINOR 1        (LibKa0s-Tooltip-1.0, new major)
Charts.lua                  MINOR 1 -> 2        (LibKa0s-Charts-1.0)
SkinDefs.lua                DEFS_MINOR 27 -> 28
SkinDefsOthers.lua          OTHERS_MINOR 9 -> 10
Widgets.lua                 MINOR 26 -> 27      (LibKa0s-Widgets-1.0)
WidgetsDropdown.lua         DROPDOWN_MINOR 1 -> 2
WidgetsReorder.lua          REORDER_MINOR 6 -> 7
WidgetsDragHandle.lua       DRAG_MINOR 13 -> 14
WidgetsDragHandleTip.lua    new, DRAGTIP_MINOR 1
WidgetsCopyWindow.lua       COPY_MINOR 5 -> 6
WidgetsHeader.lua           new, HEADER_MINOR 1
WidgetsBar.lua              new, BAR_MINOR 1
DebugLog.lua                MINOR 22 -> 23      (LibKa0s-DebugLog-1.0)
DebugLogDiagnostics.lua     DIAG_MINOR 10 -> 11
DebugLogWindow.lua          WINDOW_MINOR 4 -> 5
Launcher.lua                MINOR 10 -> 11      (LibKa0s-Launcher-1.0)
OptionsSkinPicker.lua       PICKER_MINOR 11 -> 12
OptionsSkinPickerQueue.lua  new, QUEUE_MINOR 1
IconBrowserWindow.lua       WINDOW_MINOR 1 -> 2
IconBrowser.lua             BROWSER_MINOR 1 -> 2
PerfPanel.lua               PANEL_MINOR 13 -> 14
Sim.lua                     MINOR 2 -> 3        (LibKa0s-Sim-1.0)
SimPanel.lua                SIM_PANEL_MINOR 10 -> 11
SimPanelRender.lua          RENDER_MINOR 3 -> 4
```

The consumer was behind on no file, so there is no cross-major skew.

## Both diffs

After the whole copy and before the prune, `diff -r --strip-trailing-cr` and plain `diff -r` of the
extract against `libs/LibKa0s` and against `tests/_kit` were all four empty. After the prune, the only
difference is the `Only in <extract>/LibKa0s/media/icons` lines for undeclared icons.

## Majors this addon consumes (3e)

From `grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)'` outside `libs/` and `tests/`: Bus,
Callout, Charts, Compat, Core, DebugLog, Env, IconBrowser, Item, Launcher, Lifecycle, Media, Options,
Perf, Pool, Schema, Sim, Skin, Slash, Toast, WaypointArrow and Widgets. Of the majors that moved, this
addon consumes Core, Charts, Skin, Widgets, DebugLog, Launcher, Options (the skin picker), IconBrowser,
Perf and Sim. `LibKa0s-Tooltip-1.0` is new and has no lookup here yet, so it is an adoption candidate
(#92).

## Kit revision (3f)

`Kit.VERSION` goes from 56 to 57 (`testkit/framework.lua:20`). Both payloads were copied whole in one
commit, which satisfies the pairing rule by construction. Revision 57 holds a frame strongly while it
has a raw event registration (#75 half 2). No Combat Trail suite relied on a garbage collection
dropping such a frame: both profiles stay green.

## Contract changes under surfaces whose signature did not move (3g)

No blocker. `grep -rn '__Attach[A-Za-z]*'` outside `libs/` and `_kit/` finds no site. Each consumed
major that moved was checked against what this host hands over:

- **Charts 2.** `host.tip` gains a fourth argument `ctx`, and the default tooltip moves from the
  cursor to beside the window group. Combat Trail supplies its own `tip` (`core/ChartsSetup.lua:13`,
  `cursorTip`, which honors the `anchor` it is given). The library calls it as before, with
  `ANCHOR_CURSOR_RIGHT` as the default anchor, so it is additive for this host. Moving to
  `ctx:PlaceTip` is a #92 adoption candidate.
- **Skin (SkinDefs 28, #84).** Ka0s Default's `list.stripe` moved from white .03 to .08,
  `list.hover` from gold .10 to .16 and `list.sel` from gold .18 to .26. Combat Trail's own owner
  tokens `ct.list.stripe`, `ct.list.hover` and `ct.list.sel` carry their own Ka0s Default `default`
  (`core/SkinSetup.lua:248-250` before this commit), so the library fix did not reach the Results
  list, where #84 was reported (research note R5 section 2). Design section 3.4 assigns that fix to
  this re-vendor. The decision is recorded in `05_SUMMARY.md`.
- **Launcher 11 and Core 18.** The launcher now registers a settings opener for every host. It
  takes nothing new from this host (`core/LauncherSetup.lua`).
- **DebugLog 23, Widgets 27, Perf, IconBrowser and Sim 3.** These are additive surfaces (`D:Report`,
  `D:Serialize`, the header strip, `W.Bar`, `Sim.SAMPLE`) and library-drawn changes (console footer,
  header marks, the library's own tooltips). The host owes none of them at the re-vendor.

## Span (3h)

Vendored tags since the store's horizon (2026-11-13): v1.96.0, v1.98.0, v1.100.0 and v1.102.0. All
four are recorded. `grep -vxF -f recorded.txt vendored.txt` printed nothing, so no span bundle is
owed.

## Icon and sound declarations (3i)

The icon line was kept as it stood: 30 names, including `settings`, which the kit-57 vendor gate's
`LIBRARY_MARKS` now requires. It is decided by the run's design (copy half, keep the declaration).
The sound line was kept: eight voice packs. The `LibKa0s icons:` line is the next non-blank line
under the provenance line, and no split was needed. Hand lists have drifted before (KickCD
`tests/test_mediasetup.lua:28`, WhatGroup `tests/test_mediasetup.lua:19`). The owner's in-client
smoke is the backstop for a name the host forgot to declare.

Prune with `lua <extract>/tools/prune-icons.lua .`: icons `30 icon(s) declared; kept 32 file(s),
removed 5808`, sounds `8 voice pack(s) declared; kept 362 file(s), removed 0`.

## Tests that assume the whole icon folder (3j)

`grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v '/_kit/'` finds
`tests/test_hud_race_button.lua:257`, which opens one declared icon (`flag`) by name. That is not a
whole-catalog loop, so it is not a blocker.

## Dead stub mirrors

`grep -rn '__releaseChrome'` outside `libs/` and `_kit/` finds nothing.
