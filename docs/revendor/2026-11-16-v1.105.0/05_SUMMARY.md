# 05 Summary

**Combat Trail: LibKa0s v1.102.0 -> v1.105.0**, test kit revision 56 -> 57, on
`feat/2026-11-16-libka0s-75-plus`, item `RV-CT`. Tag `v1.105.0`, commit
`79b1d9c40d3729e75a8c1ece519f445f6a20b1c9` (local, not yet pushed). v1.103.0 and v1.104.0 lie in the
range and were never vendored here. No span bundle is owed and no base correction is owed.

This bundle has no `03_DECISIONS.md` or `04_EXECUTION_PLAN.md`. The run was unattended and had no
interview, and adoption is phase [3] of the cross-repo run (`02_CANDIDATES.md`). Everything landed in
one commit.

## Minors that moved

25 files, listed in `01_DELTA.md`. Five payload files are new (`Tooltip.lua`,
`WidgetsDragHandleTip.lua`, `WidgetsHeader.lua`, `WidgetsBar.lua`, `OptionsSkinPickerQueue.lua`), and
so is the kit's opt-in `mock_screen.lua`. Combat Trail loads the payload through `LibKa0s.xml`, so no
loader list needed a line.

## Reached the addon with the copy (class A)

- The library's own windows (debug console, copy window, perf panel, sim panel, skin picker) carry
  the header strip **extras, settings, close**, and the settings mark opens Combat Trail's settings
  through its launcher.
- The debug console's status line is a 24 px Widgets footer, and Copy hands out plain text.
- The library's own tooltips (dropdown and menu entries, reorder handles, icon-browser cells, sim
  panel controls, drag strips, the minimap button) are placed by `LibKa0s-Tooltip-1.0` and never at
  the cursor. Combat Trail's chart tooltips are its own `tip` and still follow the cursor until #92
  is adopted.
- Skin contrast (#82, #84): seven skins' `icon.hot` and Glass's and High Contrast's `icon.tint`.
  Under every skin other than Ka0s Default, the Results rows follow the library's `list.*`.

## Contract blocker and fix (3g)

There was no blocker. The fix design section 5 expects for this addon is the **stripe default
(#84)**, made in this commit:

- `core/SkinSetup.lua`: the Ka0s Default `default` of `ct.list.stripe` moves from white .025 to white
  .08, and `ct.list.hover` moves from white .04 to gold .16. These are Ka0s Default's new
  `list.stripe` and `list.hover` (SkinDefs minor 28). Without the change, the owner token keeps the
  Results list's stripe at 2.5% under Ka0s Default, where #84 was reported.
- `ct.list.sel` moves from gold .10 to gold .26 with them. This is Ka0s Default's new `list.sel`.
  Without it, the selected row (.10) would read fainter than the hovered one (.16). The three row
  washes move together as the library moved them.
- No test changed. `tests/test_hud_breakdown.lua:332` and `tests/test_results_table.lua:916` read the
  token through `NS.Style.Tok`, so they follow the value.
- This is a visible change: smoke **SM-84**, Combat Trail's Fights tab under Ka0s Default.

## Declarations

Icons kept (30 names, `settings` already among them). Prune: `kept 32, removed 5808`. Sounds kept
(eight packs). Prune: `kept 362, removed 0`. No README credit moves, because no icon set or voice pack
was added or removed. No provenance split was needed. No README provenance line existed. No dead stub
mirrors were found.

## Adopted / declined

Nothing was adopted and nothing was declined. Owed in phase [3]: #92, #86, #89, #88, #79 and #87
(`02_CANDIDATES.md`).

## Gate

- `ka0s-bounded lua tests/run.lua`: 1515 passed, 0 failed, 1 skipped (1516).
- `KA0S_KIT_CLIENT=forever ka0s-bounded lua tests/run.lua`: 1507 passed, 0 failed, 1 skipped (1508).
- `ka0s-bounded luacheck .`: 0 warnings / 0 errors in 194 files.
- Largest own Lua file: `modules/Hud.lua`, 1470 lines (cap 1500).
