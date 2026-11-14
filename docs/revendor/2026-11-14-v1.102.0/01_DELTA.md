Delta: LibKa0s v1.100.0 -> v1.102.0

# 01 Delta

Combat Trail, branch `feat/2026-11-13-callout`, row C12 of
`docs/superpowers/plans/2026-11-13-callout-adoption.md`. The run is unattended (the orchestrator's
row C12): no interview, nothing adopted beyond the owner's request for this row, no issue filed.
The tag was read only through `git -C ../LibKa0s archive v1.102.0 LibKa0s testkit tools`; the
sibling checkout's working tree was not touched.

## Base and tag

- Base: the `CLAUDE.md` provenance line before the re-vendor commit, `v1.100.0`
  (`3de352cc9b3f9a3dcc492e3167f2c7eaf860da2e`), the tag of the last payload commit `2dbb772`.
- New tag: `v1.102.0`, `git -C ../LibKa0s rev-list -n1 v1.102.0` ->
  `2748549521ea9588fbe9a4c97b48828f21d35a84`. v1.101.0 lies in the range and was never vendored
  here, so it needs no record of its own.
- `git -C ../LibKa0s diff --stat v1.100.0 v1.102.0 -- LibKa0s testkit`: 5 files, +942 / -102. No
  payload file added or removed, no media change, test kit revision 56 unchanged.

## Per-file minor delta

```text
Callout.lua                MINOR 3  -> 4   (LibKa0s-Callout-1.0, key 3.4 -> 4.5)
CalloutSettings.lua        SETTINGS_MINOR 4 -> 5
OptionsWidgets.lua         WIDGETS_MINOR 45 -> 46 (LibKa0s-Options-1.0)
WaypointArrow.lua          MINOR 1  -> 2   (LibKa0s-WaypointArrow-1.0, key 1.1 -> 2.2)
WaypointArrowSettings.lua  SETTINGS_MINOR 1 -> 2
```

No `NEEDS_*` floor rose.

## Majors this addon consumes

`LibKa0s-Callout-1.0` (`core/CalloutSetup.lua`, `core/Database.lua`, `settings/Race.lua`) and
`LibKa0s-Options-1.0` (`settings/OptionsSetup.lua`). `LibKa0s-WaypointArrow-1.0` is vendored and
unused.

## Contract changes under surfaces whose signature did not move

1. **Callout minor 4, the Look defaults** (the owner's): `FONT_DEFAULT` `"Ka0s Oxanium SemiBold"`
   (was Bold; `FONT_FACES` leads with it, then Bold), shadow `1, 1` (was `2, -2`), glow
   `glowCustom = true`, `glowColor = { 0, 0, 0 }`, `glowIntensity = 1`, `glowThickness = 1`,
   `glowX = 1`, `glowY = -1` (was 0.35, 2 px at 0, 0 in each word's kind color). Every schema row
   `SchemaRows` answers takes the new default, so this addon's `profile.callout` seed and a reset
   move with it. `GLOW_LEGACY` and `MigrateGlow` are unchanged, so a stored `"soft"` or `"strong"`
   still reads its intensity and thickness, and now draws in the black swatch at 1, -1.
   Pins re-pinned in the re-vendor commit: `tests/test_callout_settings.lua` (the seeded glow
   defaults, `/ct reset callout.glowThickness` back to 1).
2. **CalloutSettings minor 5, no sample line in the one tab**: `layout = "side"` (what
   `SettingsTab` draws) builds no `5  GO!  STOP` line; `view.preview` and `view.repaint` are nil.
   The Preview heading, Test countdown and Play, Text to play, Unlock to move and Reset position
   stay. Re-pinned: `tests/test_callout_settings.lua`'s one-tab case reads both as nil.
3. **OptionsWidgets minor 46**: a slider's edit box puts junk text back to the widget's value on
   Enter and on focus loss. Arrives for free on every number row of the panel; nothing to pin.
4. **WaypointArrow 2.2**: not consumed here.
