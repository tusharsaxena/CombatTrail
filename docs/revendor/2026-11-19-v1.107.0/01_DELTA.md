Delta: LibKa0s v1.106.0 -> v1.107.0

# 01 Delta

Combat Trail, branch `feat/2026-11-19-adoption-feedback`, item `AF-RV-CT` of the cross-repo run
Ka0sAddonsCommonTasks `docs/2026-11-19-ADOPTION_FEEDBACK/`. The run is unattended: this is the copy
and bundle half of `/dev-copilot:wow-revendor-libka0s` (dev-copilot 2.9.0) only. The run's plan
pre-decides the adoptions, so there was no interview and no issue was filed. The tag was read only
through `git -C ../LibKa0s archive v1.107.0 LibKa0s testkit tools`. The tag is local and not yet on
origin (`git -C ../LibKa0s ls-remote --tags origin v1.107.0` prints nothing), which the run expects.

## Base and tag

- `grep -n '[Bb]undles' CLAUDE.md` before the copy: `Bundles [LibKa0s](...) v1.106.0 (MIT).`
- Last payload commit `git log -1 --format=%H -- libs/LibKa0s tests/_kit` is `7371d3b` (Re-vendor
  LibKa0s v1.106.0), and its `CLAUDE.md` names `v1.106.0`. The two agree.
- Minors before the copy (3b) are the v1.106.0 minors. The line and the bytes agree.
- New tag: `v1.107.0`, `git -C ../LibKa0s rev-parse v1.107.0^{commit}` ->
  `5e96365908bcde5aac2d1010f201c962c2aab399`.
- `git -C ../LibKa0s log --oneline v1.106.0..v1.107.0`: 7 commits.
- `git -C ../LibKa0s diff --stat v1.106.0 v1.107.0 -- LibKa0s testkit`: 2 files, +195 / -197. No file
  added or removed.

Step 0 pre-flight for this addon: v1.106.0 was vendored in `7371d3b` with no bundle of its own. 3h
below records it in the span bundle `2026-11-19-v1.106.0-v1.106.0/`. The newest single-tag bundle,
`2026-11-16-v1.105.0`, states base `v1.102.0`, which matches the history, so no base correction is
owed.

## Per-file minor delta

The loop is 3c's, run over the tag's `LibKa0s.xml`. Only the files that moved are listed:

```text
WidgetsDragHandle.lua     DRAG_MINOR 14 -> 15
WidgetsDragHandleTip.lua  DRAGTIP_MINOR 1 -> 2
```

## Diffs (3d)

Before the copy, `diff -rq --strip-trailing-cr` against the extract showed the two files above and
the `Only in <extract>/LibKa0s/media/...` lines for the icons and sounds this addon does not declare.
After `cp -r`, the content diff and the byte diff were both empty against the whole tag. The prune
then removed the undeclared icons again.

## Consumption (3e)

`LibKa0s-Widgets-1.0` is consumed (24 lookup sites outside `libs/` and `tests/`), but Combat Trail
builds no `DragHandle` of its own (`grep -rn 'DragHandle\|tooltipPlace' --include='*.lua'` outside
`libs/` and `tests/_kit/` finds nothing). The one strip it shows is the library's own, the race
countdown's call-out (`libs/LibKa0s/Callout.lua` `buildHandle`, which this tag did not touch).

## Kit revision (3f)

`Kit.VERSION = 57` in both the tag and the addon. The kit did not move. Both payloads were still
copied whole.

## Contract delta (3g)

The changelog's *What a consumer owes at its re-vendor* names three things. None is a blocker here:

- A host strip `tooltipPlace` hook: Combat Trail has none.
- A strip with no `settings` field gains the settings mark, and every strip passes `onClose`: Combat
  Trail builds no strip. The call-out's strip is the library's, and it now shows the settings mark,
  which opens Combat Trail's settings through `Core.OpenSettings` with the call-out's owner
  (`core/CalloutSetup.lua:60`, `d.skin = addonName`, the launcher's registered name). It passes no
  `onClose`, so it shows no X. That is the library's strip, so the X is a library follow-up, not a
  host item.
- The `settings` icon on the `LibKa0s icons:` line: already declared.

No `__Attach*` member moved.

## Icon declaration (3i)

Kept unchanged:
`arrow-left, chart, chat, chevron-down, chevron-left, chevron-right, chevron-up, clear, close, confirm,
copy, export, eye, flag, info, lock, move, ph:check, ph:flag, ph:ghost, ph:paw-print, ph:skull,
ph:trophy, ph:x, reset, settings, sort-down, sort-up, unlock, volume-high`. The sound declaration is
unchanged as well. Prune: `30 icon(s) declared; kept 32 file(s)` and `8 voice pack(s) declared; kept
362 file(s)`.

## Whole-folder tests (3j)

`grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v /_kit/` finds
`tests/test_hud_race_button.lua:258`, which opens declared names only. Nothing to fix.
