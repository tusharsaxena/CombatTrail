# 02 Candidates

Nothing was adopted at this re-vendor. The run's design (Ka0sAddonsCommonTasks
`docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS/00_DESIGN.md` section 5) puts adoption in phase [3], planned
in that bundle's `03_ADOPTION_PLAN.md`, so every candidate below is **owed in phase [3]**. No issue was
filed, because the open LibKa0s issues are the tracker. Combat Trail is the pilot for #92 and #86
(`03_ADOPTION_PLAN.md`, *Order*).

| Issue | Candidate | Evidence here | Blast radius |
|---|---|---|---|
| #92 | Own tooltips through `LibKa0s-Tooltip-1.0` (`PlaceBeside` / `PlaceAttached`), and the Charts host's `tip` on `ctx:PlaceTip` | 22 `SetOwner(` sites outside `libs/`, `_kit/` and `tests/`, 4 at `ANCHOR_RIGHT` (`modules/Results_Compare.lua:709`, `modules/Results_Loadout.lua:206`, `modules/Results_Gear.lua:444`, `modules/Results_Usage.lua:280`). The Charts host's `cursorTip` is at `core/ChartsSetup.lua:13`. | Replaces host code in 16 files |
| #86 | Window header strip `W.HeaderButtons` with the settings mark | 11 `MakeCloseButton` uses in `modules/` across 6 windows (Hud, RaceWindow, Results, Results_Compare, Results_Timeline, Results_Gear), plus the `Style.ControlButton` header controls (lock, settings, race) | Replaces host code |
| #89 | `W.Footer` (24 px) | The hand-built 20 px footers: Hud `buildFooter` (`modules/Hud.lua:511`) and the race window's footer (`modules/RaceWindow.lua:127`, `FOOTER_H` 20, its rule at :300) | Replaces host code |
| #88 | Docked test and sim strip (`dock="hud"`, `dock="title"`) | The HUD strip is hand-anchored (`modules/Hud.lua:605`, `STRIP_MAKER`). The Results strip is in `anchorStrip` (`modules/Results.lua:557`). | Replaces host code |
| #79 | `D:Report` for the list verbs | `/ct ignore list` (`modules/LaneIgnore.lua:156`, `listVerb`) | Replaces host code |
| #87 | The shared sample characters `Sim.SAMPLE` / `Sim.Sample(client)` | `modules/MockFights.lua:71-73`: `Samplerealm`, `Samplehunter` with the pet `Grimfang`. The shared set names the pet `Mockfang`. | Replaces host data |

Not candidates here:

- **#85 (Callout consumers):** Combat Trail is already the Callout consumer (key 4.5, at v1.102.0).
- **#80 and #81 (`W.Bar`, `extraEntries`):** Skill Master only, by the owner's ruling Q1.
- **WidgetsHeader on library windows, the console footer, plain-text Copy and the library's own
  tooltips:** these arrived with the copy (class A). They are listed in `05_SUMMARY.md`.
