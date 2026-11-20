Delta: LibKa0s v1.107.0 -> v1.108.0

# 01 Delta

Combat Trail, branch `feat/2026-11-20-libka0s-94-97-99-100`, item `SD-RV-CT` of the cross-repo run
Ka0sAddonsCommonTasks `docs/2026-11-20-LIBKA0S_94_97_99_100/` (LibKa0s #94, #97, #99, #100). The run
is unattended: this is the copy and bundle half of `/dev-copilot:wow-revendor-libka0s` (dev-copilot
2.10.1) only. The run's plan pre-decides the adoptions (its `SD-SK-CT` and `SD-CT-100` items), so
there was no interview and no issue was filed. The tag was read only through
`git -C ../LibKa0s archive v1.108.0 LibKa0s testkit tools`. The tag is local and not yet on origin
(`git -C ../LibKa0s ls-remote --tags origin v1.108.0` prints nothing), which the run expects.

## Base and tag

- `grep -n '[Bb]undles' CLAUDE.md` before the copy: `Bundles [LibKa0s](...) v1.107.0 (MIT).`
- Last payload commit `git log -1 --format=%H -- libs/LibKa0s tests/_kit` is `fc45cdf` (AF-RV-CT,
  the re-cut v1.107.0), and its `CLAUDE.md` names `v1.107.0`. The two agree.
- Before the copy, `diff -rq --strip-trailing-cr` of the v1.107.0 extract against `libs/LibKa0s`
  showed only the `Only in <extract>/LibKa0s/media/...` lines for the undeclared icons and sounds,
  and against `tests/_kit` nothing: the line and the bytes agree.
- New tag: `v1.108.0`, `git -C ../LibKa0s rev-parse v1.108.0^{commit}` ->
  `56c20b7686c9dbb858552f23c61003aff02fe601`.
- `git -C ../LibKa0s log --oneline v1.107.0..v1.108.0`: 15 commits.
- `git -C ../LibKa0s diff --stat v1.107.0 v1.108.0 -- LibKa0s testkit`: 23 files, +1363 / -306. No
  file added or removed.

Step 0 pre-flight for this addon: the newest single-tag bundle, `2026-11-19-v1.107.0`, states base
`v1.106.0`, which matches the provenance line at its re-vendor's parent. No base correction is owed.
3h: every tag this addon vendored since its store's horizon has a bundle (v1.106.0 in the span
bundle `2026-11-19-v1.106.0-v1.106.0/`), so no span bundle is written.

## Per-file minor delta

The loop is 3c's, run over the tag's `LibKa0s.xml`. Only the files that moved are listed:

```text
Core.lua                   MINOR 18 -> 19
Callout.lua                MINOR 4 -> 5
CalloutSettings.lua        SETTINGS_MINOR 5 -> 6
WaypointArrow.lua          MINOR 2 -> 3
WaypointArrowSettings.lua  SETTINGS_MINOR 2 -> 3
Charts.lua                 MINOR 2 -> 3
ChartsRender.lua           RENDER_MINOR 1 -> 2
SkinPaint.lua              PAINT_MINOR 19 -> 20
SkinPaintHud.lua           HUD_MINOR 1 -> 2
SkinPaintControls.lua      CONTROLS_MINOR 18 -> 19
Widgets.lua                MINOR 29 -> 30
WidgetsDropdown.lua        DROPDOWN_MINOR 2 -> 3
WidgetsDragHandle.lua      DRAG_MINOR 15 -> 16
WidgetsDragHandleTip.lua   DRAGTIP_MINOR 2 -> 3
WidgetsLineChart.lua       CHART_MINOR 7 -> 8
WidgetsBar.lua             BAR_MINOR 1 -> 2
OptionsCompose.lua         COMPOSE_MINOR 19 -> 20
```

## Diffs (3d)

After `cp -r`, the content diff and the byte diff were both empty against the whole tag, for both
payloads. The prune then removed the undeclared icons again.

## Consumption (3e)

Majors whose minor moved and that Combat Trail looks up outside `libs/` and `tests/`: Core, Callout
(`core/CalloutSetup.lua`, `core/Database.lua`), Charts (`core/ChartsSetup.lua`), Skin, Widgets and
Options (the composers in `settings/Hud.lua` and `settings/Lanes.lua`). WaypointArrow has one lookup
and draws nothing for this addon.

## Kit revision (3f)

`Kit.VERSION` 57 -> 58. Both payloads were copied whole in one commit.

## Contract delta (3g)

The changelog's *What a consumer owes at its re-vendor* names these for Combat Trail. Each was fixed in
the re-vendor commit, beside the payload:

- **The composers start on the skin (OptionsCompose minor 20).** Every `O.ColorPair` and the two
  `O.BarGroup` blocks now emit a `<key>FromSkin` companion. Five HUD swatches and the lanes' tick and
  now colors had none, so the schema's boot check found nine rows without a default. The blocks whose
  swatch already has a hand-written companion in `extra` (the boxes, the window, the glow, the
  background, the borders, the label) emit nothing new. The rest pass the part's opt-out,
  `colorFromSkin = false`, in this commit: the chart's and spell rows' bar colors and the pet color
  are skinning-§9's Leave "Combat Trail's bar colors" (the audit's OVERRIDE row); the over card's DPS
  color follows the skin already through `overColorMatchDamage`; and the Pace line color and the lane
  tick and now colors keep their opt-out only until `SD-SK-CT` gives them a companion and a reader
  (`SD-SK-CT.4`, `SD-SK-CT.6`).
- **The call-out's look follows the skin (Callout minor 5, U-1, U-2).** Two new rows,
  `callout.fontShadowFromSkin` and `callout.numberColorFromSkin`, join the schema through
  `SchemaRows` with no code. `tests/test_callout_settings.lua` re-pins the row count, the Skin font,
  the "@skin" outline, GO's `sem.good` default and the glow's skin color.
- **The skin guards (kit revision 58).** The family check found two classes:
  - The Results window's shell holds the detail's chart columns and spell bars, which a switch
    redraws on the next frame (`Results.Restyle`); the surface now passes `paint`, which runs that
    frame, so each bar's fill is read under both skins.
  - The timeline's legend, the compare's and the gear view's strings painted in a data hue kept the
    client's color when the library's replay put the skin's face back: `modules/Style.lua` now sets
    a hue again on every looks change (`hued`). The gear view's legend surface holds its color
    (`hold = "color"`): the compared fight's side color is a meaning color.
  - The typed-value scanner now reads three- and four-number tables. Combat Trail's data hues live in
    such tables; each gets a row in `tests/run.lua` (cause `MC`, `A9` for the bar fills, a kit row
    category for the stub's white, the unreachable swatch fallback and the chip alphas).

No `__Attach*` member moved.

## Icon declaration (3i)

Kept unchanged: `arrow-left, chart, chat, chevron-down, chevron-left, chevron-right, chevron-up, clear,
close, confirm, copy, export, eye, flag, info, lock, move, ph:check, ph:flag, ph:ghost, ph:paw-print,
ph:skull, ph:trophy, ph:x, reset, settings, sort-down, sort-up, unlock, volume-high`. The sound
declaration is unchanged as well. Prune: `30 icon(s) declared; kept 32 file(s), removed 5808` and
`8 voice pack(s) declared; kept 362 file(s), removed 0`.

## Whole-folder tests (3j)

`grep -rn "media/icons\|lib.ICONS\|\.ICONS)" tests --include='*.lua' | grep -v /_kit/` finds only
`tests/test_hud_race_button.lua`, which opens declared names. Nothing to fix.
