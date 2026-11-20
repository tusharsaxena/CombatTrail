# 05 Summary

**Combat Trail: LibKa0s v1.107.0 -> v1.108.0**, test kit revision 57 -> 58, on
`feat/2026-11-20-libka0s-94-97-99-100`, item `SD-RV-CT`. Tag `v1.108.0`, commit
`56c20b7686c9dbb858552f23c61003aff02fe601` (local, not yet pushed). The base is the provenance line's.
No span bundle and no base correction were owed.

This bundle has no `02_CANDIDATES.md`, `03_DECISIONS.md` or `04_EXECUTION_PLAN.md`. The run was
unattended and its plan pre-decides the adoptions: `SD-SK-CT` (the audit's GAP rows, U-1, U-14 and the
skin guards) and `SD-CT-100` (the call-out strip's close and settings marks), each its own commit.

## Minors that moved

Core 19, Callout 5, CalloutSettings 6, WaypointArrow 3, WaypointArrowSettings 3, Charts 3,
ChartsRender 2, SkinPaint 20, SkinPaintHud 2, SkinPaintControls 19, Widgets 30, WidgetsDropdown 3,
WidgetsDragHandle 16, WidgetsDragHandleTip 3, WidgetsLineChart 8, WidgetsBar 2 and OptionsCompose 20.
No file was added.

## Reached the addon with the copy (class A)

- The call-out follows the skin by default: the Skin font, the skin's outline, glow color and shadow,
  the HUD text color for its numbers, and `sem.*` for its meaning kinds until a color is picked.
- Charts with no `barFill` paint bars of data through the skin's bar texture (owner-less, Ka0s
  Default's), so the Insights bars stop drawing flat before `SD-SK-CT.1` gives them an owner.
- The shared context menu tints a submenu arrow from the menu palette and measures no secret label.
- The window footer lays out only its shown marks (LibKa0s#94).

## Contract blockers (3g)

Fixed in the re-vendor commit (01_DELTA.md has the detail): the composers' new companions (nine rows
without a default; opted out where the swatch is a Leave or already follows, and held off until
`SD-SK-CT` for the Pace line and the lane tick and now colors), the call-out suite's re-pins, and the
revision-58 guard findings (the Results shell's next-frame bars, the data-hue strings' color on a
switch, the gear legend's held color, and the typed-value rows for the data-hue tables).

## Other new surfaces

- `Callout.onClose` / `onSettings` (minor 5): adopted under `SD-CT-100`.
- `Callout:FollowKeys` / `MoveToSkin` (minor 5): called from Combat Trail's one-time step under
  `SD-SK-CT` (U-1).
- `W.OwnerWarnings(owner, sink)` (Widgets minor 30): not adopted in this run; the owner-less widget
  it would report, the Insights charts, gets its owner under `SD-SK-CT.1`.
- `Core.ApplySkin` with `skinBands`, `S.BarGloss` on a Texture fill and `W.BarStyle`'s border default:
  Combat Trail draws no `W.Bar`, has no host-skinned window and glosses its HUD bars through
  `S.BarGloss` on StatusBars already, so nothing here applies.

## Icons, credits, stubs

The `LibKa0s icons:` and `LibKa0s sounds:` lines are kept. The prune removed nothing beyond the
undeclared names the copy brought back. No README credit line moved, and there were no dead stub
mirrors.

## The standard

The reference moves to v2.116.0 (WowAddonStandards `feat/2026-11-20-libka0s-94-97-99-100`, read
from the local checkout): the vendored quirks block in `docs/midnight-quirks.md` is restamped
v2.116.0, its text unchanged since v2.115.0. No retired notation, file name or unresolvable section
reference was found.

## Gates

Retail `ka0s-bounded lua tests/run.lua`: 1590 passed, 0 failed, 1 skipped (1591). WoW Forever
`KA0S_KIT_CLIENT=forever ka0s-bounded lua tests/run.lua`: 1582 passed, 0 failed, 1 skipped (1583).
`ka0s-bounded luacheck .`: 0 warnings / 0 errors in 199 files.
