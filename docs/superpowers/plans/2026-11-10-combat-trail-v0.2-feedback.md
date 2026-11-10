# Ka0s Combat Trail v0.2 feedback batch: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax. **This run executes milestone by milestone through Workflow scripts (owner: "use ultracode"), one workflow per milestone. Each task is an implement agent followed by a fresh review agent.**

**Goal:** Apply the owner's first in-game feedback batch to Combat Trail. Bring its HUD, Results and Timeline in line with DPS Race, which is the visual reference, and build the shared pieces (HUD sizing, timeline icons) in DPS Race too.

**Architecture:** The changes stay inside the existing module layout; no new subsystems. Combat Trail's data model changes in three ways:
- the target identity gains level and NPC ID;
- gear becomes deduplicated equipment sets;
- the schema goes to 2 with a one-time wipe.

The DPS Race half runs in its own git worktree and branch.

**Tech stack:** unchanged. Lua 5.1 (WoW), Ace3, LibKa0s v1.94.0 vendored. Headless suites run under both kit profiles, plus luacheck and lizard.

**Inputs (read before any task):**
- **The owner's feedback:** below, verbatim. It is the spec for this run.
- **Recon:** `docs/superpowers/plans/2026-11-10-v0.2-recon.md`. Seven readers mapped both repos item by item; tasks cite it as `R:<area>#<item>`. Its line numbers were true on 2026-11-10, so re-check before editing. Where this plan's **Decisions** disagree with a recon proposal, the plan wins.
- **v0.1.0 design:** `docs/superpowers/specs/2026-11-10-combat-trail-design.md`. Sections this run changes (§5 identity, §7 Results) are updated in the same task that changes the behaviour.

---

## Status ledger (resume here)

Update your row, with the commit SHA, in your task's final commit. A resumed session runs `git log --oneline`, reads this table, and continues from the first row that is not `done`.

| Task | Title | Status | Commit |
|---|---|---|---|
| A1 | Schema 2 wipe, History rename, HUD "always" wins | done | c5a6a8f: SCHEMA_VERSION 2 wipe step, CT_SCHEMA 2, always returns early in autoAllowed, tab "History" / "Purge history…" (key `retention` kept) |
| A2 | Target identity: name + level + NPC ID, board key, detail meta | done | 32481c2: key `t:<npcID>:<level\|?>:<name>:<diff>` (+tier), `n:<name>:<diff>` fallback, world boss stays `c:`; fields `targetLevel` (existing `targetCreatureID` is the NPC ID), `zone`, `subzone`; level from the entry snapshot only; Detail.Meta returns 3 lines |
| A3 | Equipment sets with recon | done | 6751328: `db.global.gearSets`, `Loadouts.StoreGear/GetGear/GearOf/CurrentGearSet/Recon/GearCount/Sync/Suspend`; recon on PEW, PLAYER_EQUIPMENT_CHANGED, UNIT_INVENTORY_CHANGED(player), stand-up and post-combat if owed, one coalesced 0.5 s AceTimer; record `gearSet` (no `gear`); Sweep keeps current + live fight's set |
| A4 | Forever: predominant talent tree stands in for spec | done | e14eb75: `Compat.TalentTrees()` (talent tabs, then C_Traits groups; nil on Retail) and `Compat.TalentApis()` (probe); Forever `who.trees` + `who.specID = "tree:<class>:<index>"`, `specName`, `specIcon`; `Tbl.SpecInfo(id, name, icon)`; Spec filter/grouping on both clients, "talent tree" wording on Forever; `Fights.HasSpecs` removed |
| A5 | Live DPS formatter: no raw decimals | done | c45002f: plain numbers abbreviate in Lua first; `Compat.NumberFormatterCandidates()` (replaces `NewNumberFormatter`) tried in order against an integer and a fractional check (30190.4761904 -> "30.1K"); then `AbbreviateNumbers`, raw secret last; `tests/mock_formatter.lua` |
| B1 | Shared bar palette (HUD) | done | 987b291: `NS.Constants.PALETTE` (arrays {r,g,b[,a]}: BAR, BAR_A, PET, PLAYER_LINE, PET_LINE, THIS_BAR, BEST_BAR, THIS_TEXT, BEST_TEXT, PACE); hud.chart.barColor/barAlpha/bestColor and hud.spells.barColor/barAlpha/petColor (PET at BAR_A) copied per block; PetColor() unchanged; Timeline.THIS left to C4/D1 |
| B2 | HUD look parity with DPS Race | done | 3e40acb: headings FONT.SECTION on SECTION_H, HEAD_GAP 6; `placeProfile` (pace under the heading, over the plot; `Strip:Place(anchor, y, width, midH)`, `SetParts`, `SetNote`; PACE_H 12); clock fontFromSkin, stored `fontSize = 26` drawn at 40 via `HudStates.ClockSize` (composed slider max 32, so not a stored 40), CLOCK_PAD 12; width/MIN_WIDTH 260, PAD 12, insets +10/+8; rows 18 / 10 pt / shadow; chart 80; `body.stackTop` |
| B3 | HUD sizing: fixed N bars (default), auto-grow up/down, grip, scroll | done | 7efbca7: `hud.sizeMode` "fixed"/"auto", `hud.bars` 5 (`Hud.MIN_BARS` 1..`MAX_BARS` 15), `hud.grow` "down"/"up"; `hud.spells.rows` retired; fixed height `Hud.FixedHeight()` = chrome + `HudStates.FixedStack(layout, bars, paceable)` (pet row and pace line reserved); grip (fixed, unlocked) stores `hud.width` (260..`Hud.MAX_WIDTH` 600) and `barsFor(h)` via SetByPath; `normalizeAnchor` TOPLEFT/BOTTOMLEFT on UIParent BOTTOMLEFT; wheel scroll both modes, note "1-5 of 12", gutter thumb; `Breakdown.Capacity` |
| C1 | Results frame: close on combat, chevron, Character width, tree icon | done | cfb64c0: `NS.MSG.COMBAT_ENTERED` (Fight.OnCombatStart, regen edge only) -> Results.Hide while `results.closeInCombat` (default true); fold arrow collapsed chevron-right / expanded chevron-left; Character fixed `Fights.CHARACTER_W` 104, target flex (min 150); header-edge grip drags it 70..240, stored in `results.columns.character` (named state, cleared by Reset position); `Tbl.Columns(columns, width, widths)`; no-spec row draws no second icon (A4 tree icon kept) |
| C2 | Results table: Delta 0.0%, Status, Used, Note columns, notes | done | 30fbb62: Delta 0.0% (green) for the top; Status badge `Fights.StatusText` "Best" + ph:trophy in `Tbl.COLORS.blue` (= PALETTE.BEST_TEXT) via ResultsSource.IsBest, else empty; Used items kind (`Tbl.IconSlots/IconsFit/ICON_GAP`, `ResultsUsage.Icons/Count/InlineIcon`); Note `Fights.NoteCell/NoteSort/NoteTip` (10 chars); `Recorder.ClampNote` (\|->/, controls->space, 200 UTF-8 chars), popup Enter saves / Escape closes; bars `Tbl.BAR_COLOR` PALETTE.BAR @ BAR_A; MIN_WIDTH 1038, `results.window.width` 1100 |
| C3 | Results detail: section folds, footer, Gear and Talents | done | cb59702: `Detail.SECTIONS` chart/spells/loadout/usage/note, `ARROW` 14, `INDENT` 16, `Detail.IsCollapsed/SetCollapsed` over `results.collapsedSections` (named state, Reset position keeps it), `Pane:AddHeading(key, title, click)/Heading/ToggleSection`; Add Note unfolds Note; footer Add Note 84 · Share 84 · Timeline 72 · Compare 70 (`BUTTON_GAP` 6, all normal), Delete 78 danger; Compare label fixed "Compare" (COMPARE_LABELS gone, tooltip per target left to C4); "View gear", "View Talents" (`TALENT_W` 84), Copy + `Loadout.Copy` removed; `Loadout.Points(who)`, `TalentsText(t, who)` -> "Hunter (31/20/0)" from who.trees |
| C4 | Compare popup: label, colours, trinkets/consumables | done | 66f86b6: bars `PALETTE.THIS_BAR`/`BEST_BAR` at `BAR_A`, text `THIS_TEXT`/`BEST_TEXT` by fixed side via `Compare.SideText` (PairText plain), gear ilvls tinted (`GearText(..., tinted)`); button tip by kind (`COMPARE_TIPS` in Results_Detail); "Trinkets and consumables" after Gear changed: `Compare.UsageRows(a,b)` -> rows,aRec,bRec, `Compare.UsageLines()`, `USAGE_TITLE_H`/`USAGE_ROW_H` 22, `Size(n, gear, usage)`, "not used"/"not recorded"/"None used"; LoadoutLines passes `who`; Timeline.THIS left to D1 |
| D1 | Timeline: icons or ticks, player/pet colours | done | 0393d86: `results.timelineMarks` "icon" (default) / "tick" (History > Results window > Ability timeline, plus Icons/Ticks words on the By ability heading line via SetByPath; Results.lua onSettings -> `ResultsTimeline.Redraw()` keeps zoom/pan); new `modules/Results_TimelineMarks.lua` on NS.ResultsTimeline, DR's names (`MARKS_PATH`, `MARK_MODES`, `LANE_ICON` 14, `MARK_A` 0.95, `PLAYER_LINE`/`PET_LINE` = PALETTE refs, `CASTER`, `CasterColor`, `MarkMode`, `SetMarkMode`, `NewCastIcon`, `PaintCast`, `PutMark`, `ReleaseMarks`, `LaneMarks`, `BuildMarks`, `PlaceMarks`); every cast icon on a 1 px BORDER edge in caster colour (S.IconBorder dropped); lanes clip padded CLIP_PAD; Marks() entries carry `kind`; `Timeline.THIS`/`OTHER` = copies of PALETTE.THIS_TEXT/BEST_TEXT (B1 leftover, pinned on forever) |
| E1 | DPS Race: HUD sizing model (same as B3) | done | DpsRace e697b8c + review fix 4003868: `hud.sizeMode`/`bars`/`grow`; `live.rows` and `windows.hud.height` retired (migration 12); `Hud.FixedHeight` = chrome + `HudStates.FixedContentHeight(bars)` = max(`BaseContentHeight` 286, `RowsChrome` + `RowsHeight(bars)`); grip stores `windows.hud.width` (260..`MAX_WIDTH` 600) and `hud.bars`; `normalizeAnchor` for auto; wheel scroll on both bodies, count "1-5 of 12"; 4003868 snaps the window after a height-only release that keeps the row count |
| E2 | DPS Race: timeline icons or ticks, player/pet colours (DpsRace#21) | done | DpsRace 4a1e82c: `results.timelineMarks` "icon" (default) / "tick" (History > Run detail > Ability timeline, plus Icons/Ticks words on the By ability heading line via SetByPath; onChange `ResultsTimeline.Redraw()` keeps zoom/pan); `Timeline.PLAYER_LINE`/`PET_LINE`/`CASTER`/`CasterColor(pet)`, ticks at `MARK_A` 0.95, every cast icon (lanes and Casts strips) on a 1 px BORDER edge in caster colour instead of S.IconBorder; lane from side, not colour; lanes clip padded CLIP_PAD both modes; new `modules/Results_TimelineMarks.lua` (`NewCastIcon`, `PaintCast`, `LaneMarks`, `ReleaseMarks`, `PutMark`, `MarkMode`, `SetMarkMode`; `MarkLines` moved there); Marks() entries carry `kind`; no caster legend swatch |
| E3 | DPS Race: formatter fix and palette check | done | DpsRace 98bb075: A5 ported (plain numbers in Lua first, `CHECKS` integer + fractional 30190.4761904 -> "30.1K", `Compat.NumberFormatterCandidates` replaces `NewNumberFormatter`, `AbbreviateNumbers` then raw secret; `tests/mock_formatter.lua`); DR showed the bug (5 red before). Palette: BAR/BAR_A, chart, pace fill, table, compare bars, `dr.chart.diag` = PACE, PLAYER_LINE/PET_LINE all equal CT PALETTE (new test_bar_style pin); no DR change. Not fixed (DR reference, outside the plan's list): DR `Timeline.THIS` still snapshots Style.GOLD at load; DR draws no pet bars, so no PET |
| F1 | Extraction issue, docs sync, branch review, push | in progress | F1a (Combat Trail cleanup, docs sync, extraction issue) below; branch review and push follow |
| F1a | Combat Trail: left-open review minors, Format secret-safety, docs sync, extraction issue | in progress | |

Milestones and pushes: A → push, B → push, C + D → push, E → push (DPS Race branch), F → push both. Never merge without the owner's go-ahead.

---

## Owner feedback (verbatim, 2026-11-10)

```
- HUD window
  - make it smaller by about 10% (same effect as setting master scale to 90% - this becomes the new 100% master scale after the change)
  - Give options for the window to grow up (current behavior) or down - make down the default
  - Give an option to keep the window fixed size (Show x spell breakdown bars by default, X=5 but configurable). Resizing the window should change the number of bars show
    - Add a scroll for spell breakdown if number of items is less than
    - Add a resize option for the HUD
    - Build this resizing stuff for both Combat Trail and DPS Race for consistency
  - Sometimes the DPS shows some weird lonmg number after decimal point
- Results Window
  - Autoclose results window if you enter combat (configurable via optiosn, enabled by default)
  - The expand/collapse button is inverted - swap it please
  - Replace "Talents: Hunter" with "Talents: Hunter (XX/XX/XX)" which shows spec points allocation
  - Rename Gear view to "View gear"
  - Rename Talents "View" to "View Talents"
  - Remove the Talents "Copy" button altogether
  - Character column is far too wide, optimize it a bit for new profiles) - dragging should still change
  - Remove the double icon - or at least the second icon should be that of the predominant spec (spec with max points) if the game doesnt return a spec
- Timeline window
  - In the By Ability view, give an option to show either the tick lines or the actual ability icon
    - ability icon is the default, should show similar tooltip tp Casts section
    - File this as a github issue in DpsRace as well, and build this there as well
  - Different color for player and pet ability (icon border, tick line color) - use the same colors as spell breakdown but in a relevant shade according to the palette
- Comparison with DPS Race
  - Change the color schemes to be consistent across both addons - especially bars, charts, Column bars
    - i like the brighter look of dps race so use that as the reference
  - In the HUD, make the following consistent (DPS Race is reference point)
    - Section header size
    - font used for timer
    - pace bar below Damage profile header
    - Default size of HUD (height and width)
    - do this for both mid pull and post pull views
  - In the Results view, make the following consistent (DPS Race is reference point)
    - Color of the damage and dps bars
    - Status column shoukd not have BEST flag, it should be 0.0%
    - Add Status, Used, Note column (add note functionality) in CombatTrail
  - In the Results Details view, make the following consistent (DPS Race is reference point)
    - All collpase arrows for every section header (e.g. Spell breakdown)
    - Make the footers consistent (Add note, share, timeline, delete) with same colors and layouts
    - Change the comparse v/s best feature to look and behave like in COMBAT TRAIL (not dps race)
      - button in footer
      - popup window
      - includes gear changed
      - also show trinkets/consumables used in the popup
      - But make the color scheme the same as DPS Race for current v/s best
      - color the text appropriately as well (all THIS text should be yellow, all best/runner up text should be blue) with approriate text shades
      - Call the comapre vs best button just "Compare"
- General Feedback
  - For Encounter or target, save the mob name and if possible the mob level and mob unit ID. Best pace should be acptured against the combination of all of these
  - Do not capture equipment for EVERY combat. Instead, detect equipment changes and save those as equipment sets; tie every saved encounter to an equipment set ID
    - do a equipment recon every /reload, PEW and other similar states to account for changes not detected by the addon (different PC, addon disabled, etc)
  - There is a LOT of commanility between DPSRace and CombatTrail - file a github issue in CombatTrail to extract common parts out as much as possible
```

## Decisions (owner answers and the run's own calls)

Owner answers (2026-11-10):
- **D1. Saved fights:** wipe once on the schema upgrade. No migration (the addon is unpublished).
- **D2. HUD default:** fixed size showing 5 spell bars. The resize grip changes the bar count and the breakdown scrolls. Auto-grow is the alternative mode, growing down by default and up optionally.
- **D3. Board key:** non-boss targets are keyed by name + level + NPC ID. Bosses stay encounter + difficulty (+ keystone), with mob info stored for display.
- **D4. HUD visibility:** "always" beats "Only in instances".
- **D5. Forever specs:** the predominant talent tree (most points) stands in for spec everywhere: the row's second icon, the Spec filter (now present on Forever), grouping and the share line.
- **D6. History page:** renamed to the standard: tab "History", button "Purge history…".
- **D7. DPS Race:** stack on the other agent's branch `feat/2026-11-10-quickcomms-forever-emotes`, which the owner was merging to master. Build in a separate worktree so that agent's checkout is never touched.

The run's own calls:
- **D8. HUD size:** the "10% smaller" is delivered by matching DPS Race's geometry (width 300 → 260, rows 22 → 18, row font 12 → 10, DPS Race's heading and inset values). That shrinks the window about 13%, which is what the owner saw side by side. No extra 0.9 scale on top, which would make Combat Trail smaller than the reference. `hud.scale` stays at default 1.
- **D9. Same sizing model in both addons:** keys `hud.sizeMode` ("fixed" | "auto", default "fixed"), `hud.bars` (1–15, default 5) and `hud.grow` ("down" | "up", default "down", used only in auto mode). In fixed mode the window height is derived from `bars`. Dragging the grip sets the width and rounds the height to a whole number of bars, then stores `bars`. Auto mode grows up to `bars` and then scrolls. The breakdown scrolls with the mouse wheel whenever spells exceed the visible rows.
- **D10. Gear set:** a fight's gear set is the one current at combat start. Stats stay per fight (they vary with buffs).
- **D11. Forever wording:** labels name a "talent tree" on Forever and a "specialization" on Retail. The predominant-tree icon is the tree's own icon. Where the Forever talent API is uncertain, the code is defensive (several APIs, in order) and `/ct probe` dumps what the client answers, for the owner's smoke test.
- **D12. Results table bars:** a single palette colour (DPS Race's BAR_BLUE) at 0.9, not the class colour. Class colour stays on names and icons.
- **D13. Pace line:** DPS Race's neutral {0.9,0.9,0.92,0.4} (the declared, unused `ct.chart.diag` token).
- **D14. Lanes:** live cast-lane borders keep following the skin. The owner asked for player/pet colours on the timeline only.
- **D15. Compare colours:** sides are fixed: this fight is always yellow, and the other (best, runner-up or picked) is always blue. DPS Race instead paints whichever side is best in blue; the owner asked for fixed sides.

## Global constraints

- **Repos the run never writes:** `../LibKa0s`, `../WowAddonStandards`, `../dev-copilot`, `../PanelMaster`. File issues instead.
- **DPS Race:** written only in its worktree `../#Worktrees/DpsRace-ct-parity`, on branch `feat/2026-11-10-ct-parity`. Never in `../DpsRace` itself.
- **Secret values:** never register `COMBAT_LOG_EVENT_UNFILTERED`. Never compare, do arithmetic on, use as a key or `tostring` a value that may be secret. Pass it through `NS.Secrets` first, or hand it to a C-side widget untouched.
- **Clients (clients-§4):** a feature one client cannot have is absent there, not hidden. Both kit profiles must pass.
- **Line endings:** files are CRLF. The Write tool writes LF, so convert before running the suite.
- **Green gate before every commit:**
  - `lua tests/run.lua`
  - `KA0S_KIT_CLIENT=forever lua tests/run.lua`
  - `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .`, 0 warnings / 0 errors
  - `~/.claude/dev-copilot/bin/ka0s-bounded lizard -C 15 -x "./libs/*" -x "./tests/_kit/*" . -w`, no output

  DPS Race uses its own documented gate (its CLAUDE.md).
- **Standard deviations:** any new deviation from the Ka0s standard gets a row in `docs/ARCHITECTURE.md` → Documented deviations, and is called out in the task's report.
- **Docs in the same commit:** a task that adds or renames a setting updates `docs/schema.md` and `docs/settings-panel.md` (the docs gate checks them), plus `locales/enUS.lua`.
- **Commits:** focused commits, ending with the attribution lines given in the workflow prompt. No pushes from task agents.

## Review focus (failure modes no single task's tests own)

1. **Secret identity reads in combat.** `UnitLevel`, `UnitGUID` and `UnitName` may answer secret mid-pull on Retail. The NPC ID is parsed from a GUID only after `Secrets.PlainString`. A sealed level leaves the field nil; it never errors and never splits the board key by itself. Owned by A2: a test with a sealed level and GUID.
2. **The live pace key and the stored key must agree.** If the HUD's pace lookup builds its key from a different level source than the recorder, a new best never shows its pace. Owned by A2: a test that the HUD's pace key equals the saved record's `boardKey` for the same fight.
3. **Grip and scroll at the extremes.** A drag shorter than one bar, a window taller than 15 bars, zero spells, a pet appearing mid-fight, and switching mode while a fight is live. Each keeps the HUD drawable with no overlap. Owned by B3 and E1.
4. **Gear recon churn.** PLAYER_EQUIPMENT_CHANGED fires per slot during a set swap. Recon must intern one set at the end, not one per slot, and an unchanged login must not create a new set. Owned by A3: a burst test and an idempotent-login test.
5. **Forever without the expected talent API.** If neither `GetTalentTabInfo` nor C_Traits answers, the spec stand-in is nil: the second icon is dropped (no double class icon) and the Spec filter shows no rows rather than erroring. Owned by A4.

---

## Milestone A: data and fixes (Combat Trail)

### Task A1: Schema 2 wipe, History rename, HUD "always" wins

**Recon:** R:data-model#3, #4, #5.

**Files:** `core/Database.lua`, `modules/Recorder.lua` (CT_SCHEMA), `modules/Hud.lua` (autoAllowed or goLive), `settings/History.lua`, `settings/Hud.lua` (tooltip), `locales/enUS.lua`, `docs/schema.md`, `docs/settings-panel.md`, `docs/smoke-tests.md`.

**Interfaces.** This task produces:
- `NS.SCHEMA_VERSION = 2`.
- Migration step 2, which empties `db.global.fights`, `fightOrder`, `loadouts` and `gearSets`.
- `Recorder.CT_SCHEMA = 2`.

**Steps:**
- [ ] Write the failing tests.
  - A profile at schema 1 holding fights loads with an empty store at version 2.
  - A fresh install runs step 2 harmlessly.
  - With `hud.show = "always"` and `hud.instancesOnly = true`, the HUD stays shown after an open-world fight and through the next one.
  - The History page's tab reads "History" and its button "Purge history…". The internal key `retention` and the `history.*` paths are unchanged.
- [ ] Implement: STEPS[2] on `NS.db.global`; `always` returns early in autoAllowed, with the header comment and the tooltip updated; the label renames with old locale keys removed (grep first).
- [ ] Run the green gate, update the docs rows, and commit.

### Task A2: Target identity (name + level + NPC ID), board key, detail meta

**Recon:** R:data-model#1 and R:results-detail#5.

**Files:**
- Code: `modules/Identity.lua`, `modules/Fight.lua` (only if the target pick needs the level), `modules/Bests.lua`, `modules/Hud*.lua` (the pace lookup), `modules/Results_Detail.lua` (Meta).
- Tests: `tests/test_identity.lua`, `tests/test_bests.lua`, `tests/test_detail*.lua`.
- Docs: `docs/schema.md` and spec §5.

**Interfaces.** The identity gains `level` (number or nil; -1 means a skull level), `npcID` (number or nil), `zone` and `subzone` (string or nil). `Identity.BoardKey(ident)`:
- for a boss/encounter: unchanged (encounter + difficulty + keystone);
- otherwise: `"t:" .. npcID .. ":" .. (level or "?") .. ":" .. name`, falling back to the name-only key when `npcID` is nil.

`Detail.Meta(record)` returns three lines, (where/who, what, stamp), as in recon item 5.

**Steps:**
- [ ] Write the failing tests:
  - two fights on the same NPC at different levels land on different boards;
  - the same NPC and level share a board;
  - a boss fight's key ignores level and NPC ID;
  - a sealed level or GUID gives nil fields and no error (Review focus 1);
  - the HUD's pace key equals the stored `boardKey` (Review focus 2);
  - Meta returns three lines with zone and pet.
- [ ] Implement:
  - read the level and parse the NPC ID from the GUID, only after `Secrets.PlainString` / `PlainNumber`;
  - fill the level after combat when the primary creature matches the current target.
- [ ] Run the green gate, update the docs, and commit.

### Task A3: Equipment sets with recon

**Recon:** R:data-model#2.

**Files:**
- Code: `modules/Loadouts.lua`, `modules/Recorder.lua`, the gear consumers (`modules/Results_Gear.lua`, `Results_Compare.lua`, `Results_Loadout.lua`) and `modules/MockFights.lua`.
- Event wiring: through the addon's lifecycle / event-state model (see `docs/ARCHITECTURE.md` event wiring). Do not register events from Results.
- Tests: `tests/test_loadouts.lua` and `tests/test_recorder.lua`.
- Docs: `docs/schema.md`.

**Interfaces.** This task produces:
- `db.global.gearSets = { [key] = { [slot] = item } }`, where `key = Hash(canonical gear)`;
- `Loadouts.StoreGear(gear) -> key`;
- `Loadouts.GearOf(record) -> gear` (the record's `gearSet`, falling back to an inline `record.gear` for mock records);
- `Loadouts.CurrentGearSet() -> key|nil`;
- `Loadouts.Recon()`.

Records store `gearSet` (a key) and no longer `gear`. Sweep (retention) keeps every set still referenced by a stored fight and drops the rest.

**Steps:**
- [ ] Write the failing tests:
  - identical gear across 3 fights gives one set;
  - one changed slot gives a second set;
  - a burst of 6 PLAYER_EQUIPMENT_CHANGED events in one frame interns one set (Review focus 4);
  - a login with unchanged gear makes no new set;
  - recon runs on PLAYER_ENTERING_WORLD (login and reload) and on the debounced equipment change;
  - the fight takes the set current at combat start (D10);
  - the sweep drops orphaned sets;
  - the gear view and the compare "Gear changed" still read correctly through `GearOf`.
- [ ] Implement, with the debounce on a timer (C_Timer.After, coalesced).
- [ ] Run the green gate, update the docs, and commit.

### Task A4: Forever's predominant talent tree stands in for spec

**Recon:** R:results-table#4 and R:results-detail#4 (the talent points).

**Files:**
- Code: `core/Compat*.lua` (new `Compat.TalentTrees()`), `modules/Identity.lua` or `Recorder.lua` (where who/spec is captured), `modules/Loadouts.lua`, `modules/Filters.lua`, `modules/Results_Fights.lua` / `Results_Table.lua` (the icon cell), `modules/Share.lua`, `modules/Probe.lua`.
- Settings: `settings/History.lua` (the Spec filter wording).
- Tests: per module.
- Docs: `docs/ARCHITECTURE.md` per-client table and `docs/compat-layer.md`.

**Interfaces.** `Compat.TalentTrees()` returns `{ { name, icon, points }, ... }` in tree order, or nil. On Forever it tries `GetNumTalentTabs`/`GetTalentTabInfo`, then C_Traits, each guarded; on Retail it is nil. Records gain `who.trees = { points, ... }` (plain numbers). On Forever only, `who.specID`/`specName`/`specIcon` are filled from the tree with the most points (ties go to the first tree). The Spec filter and grouping are present on Forever, labelled "Talent tree" (D11).

**Steps:**
- [ ] Write the failing tests (Forever profile):
  - trees 31/20/0 make the first tree the spec, and the row's second icon is that tree's icon;
  - trees 0/0/0, or no API, give no second icon and an empty filter with no error (Review focus 5);
  - the Spec filter is present on Forever with tree wording;
  - the share line names the tree.

  Retail tests are unchanged.
- [ ] Implement. Add a `/ct probe` section that dumps every talent API's answer on Forever.
- [ ] Run the green gate, update the docs, and commit.

### Task A5: Live DPS formatter, no raw decimals

**Recon:** R:hud-sizing#4.

**Files:** `modules/Format.lua`, `core/Compat*.lua` (formatter candidates), `tests/test_format.lua`, `docs/midnight-quirks.md`.

**Interfaces.** `Format.Number(v)` never returns the raw value for a number:
- a plain number goes through Lua `abbreviate` first;
- a secret goes through a client formatter that passed both the integer check and a new fractional check (`30190.4761904` → `"30.1K"`), trying each constructor candidate in order;
- with no trusted formatter, a secret goes to `AbbreviateNumbers` in a pcall, and the raw secret is the last resort only.

Log at debug level which path served the value.

**Steps:**
- [ ] Write the failing tests:
  - a plain fractional DPS (77.142857) renders "77";
  - a mock formatter that renders fractions raw fails the check, and the next candidate is used;
  - a secret with no formatter goes through `AbbreviateNumbers`.
- [ ] Implement; record the quirk.
- [ ] Run the green gate and commit.

**Milestone A checkpoint:** all rows A1–A5 done, then push the branch.

---

## Milestone B: HUD (Combat Trail)

### Task B1: Shared bar palette (HUD)

**Recon:** R:palette#1, #2, #3, #9.

**Files:** `core/Constants.lua`, `defaults/Profile.lua` (`hud.spells.barColor`, `barAlpha`, `petColor`, `hud.chart.barColor`, `barAlpha`, `bestColor` per D13), `tests/test_hud_*`, `docs/schema.md`.

**Interfaces.** `NS.Constants.PALETTE`:

| Key | Value |
|---|---|
| BAR | {0.36,0.37,0.84,1} |
| BAR_A | 0.9 |
| PET | {0.24,0.60,0.30,1} |
| PLAYER_LINE | {0.50,0.52,1.0,1} |
| PET_LINE | {0.40,0.85,0.45,1} |
| THIS_BAR | {0.682,0.569,0,1} |
| BEST_BAR | {0.329,0.549,0.839,1} |
| THIS_TEXT | {1,0.82,0} |
| BEST_TEXT | {0.35,0.66,1} |
| PACE | {0.9,0.9,0.92,0.4} |

C2, C4 and D1 consume it.

**Steps:**
- [ ] Write a failing test that the defaults equal the palette entries.
- [ ] Implement.
- [ ] Run the green gate and commit.

### Task B2: HUD look parity with DPS Race (live and post-pull)

**Recon:** R:hud-look#1–#8.

**Files:** `modules/Hud.lua`, `Hud_States.lua`, `Hud_Chart.lua`, `Hud_Breakdown.lua`, `defaults/Profile.lua`, `settings/Hud.lua`, tests.

**Values:**
- Section headings in `Style.FONT.SECTION` on `Style.SECTION_H` (22), with HEAD_GAP 6.
- The pace bar sits under the "Damage profile" heading, above the chart (`placeProfile`).
- Clock: `fontFromSkin = true`, `fontSize = 40`, CLOCK_PAD 12.
- `hud.width = 260`, `Hud.MIN_WIDTH = 260`; PAD 12; content top `HEADER_H + 10`, bottom `FOOTER_H + 8`.
- Spell rows: `rowHeight = 18`, `fontSize = 10`.
- `hud.chart.height = 80`.

Both the live and the over (post-pull) views follow these.

**Steps:**
- [ ] Write failing tests: the layout order is heading → pace → chart in the live view, and the defaults equal the values above.
- [ ] Implement.
- [ ] Run the green gate and commit.

### Task B3: HUD sizing (fixed N bars by default, auto-grow up/down, grip, scroll)

**Recon:** R:hud-sizing#1–#3, and D8 and D9.

**Files:** `modules/Hud.lua`, `Hud_States.lua`, `Hud_Breakdown.lua`, `Sizing.lua`, `defaults/Profile.lua`, `settings/Hud.lua`, `locales/enUS.lua`, `tests/test_hud_*.lua`, docs.

**Interfaces.** New keys: `hud.sizeMode`, `hud.bars` and `hud.grow` (D9). `hud.spells.rows` is retired into `bars` (remove its row and default).
- `Breakdown` gains an `offset`-driven scroll (mouse wheel on the breakdown; a thin scroll indicator when spells exceed rows).
- The resize grip (`Sizing.MakeResizable`) shows in fixed mode only, and hides when the HUD is locked.
- In auto mode, `normalizeAnchor` re-anchors after a drag: TOPLEFT for "down", BOTTOMLEFT for "up". Update the shell-frame geometry-read comment and the ARCHITECTURE secret-value invariants.

**Settings (Layout → Size):**
- "Window size": Fixed / Auto-grow.
- "Spell bars": 1–15.
- "Grow": Down / Up, greyed out unless the mode is auto.

**Steps:**
- [ ] Write the failing tests (Review focus 3):
  - the fixed height is derived from bars and is identical with 0, 3 or 20 spells;
  - a grip release at an arbitrary height stores the rounded bars (minimum 1, maximum 15);
  - the wheel scroll offset is clamped;
  - auto mode grows up to bars, then scrolls;
  - grow down keeps the top fixed and grow up keeps the bottom fixed;
  - a pet appearing mid-fight keeps the fixed height;
  - a mode switch mid-fight redraws without error;
  - the grip is hidden while locked.
- [ ] Implement.
- [ ] Run the green gate, update the docs, and commit.

**Milestone B checkpoint:** push.

---

## Milestone C: Results (Combat Trail)

### Task C1: Results frame (close on combat, chevron, Character width, tree icon)

**Recon:** R:results-table#1–#4.

**Interfaces:**
- `NS.MSG.COMBAT_ENTERED`, sent by Fight on the regen-disabled edge only.
- Results listens on the bus, never to game events, and hides when `results.closeInCombat` (default true) is on.
- The chevron: expanded shows "chevron-left", collapsed shows "chevron-right".
- Character column: fixed `width = 104` (still drag-resizable). The target column takes the flex.
- The row's second icon is the spec icon, or the tree icon on Forever (from A4). It is omitted when there is none, so a row never shows two class icons.

**Tests:**
- entering combat closes the open window when the option is on and leaves it open when off;
- a window reopened mid-combat stays open;
- the chevron icon matches each state;
- the default Character width is 104, and a stored drag width wins;
- there is no second icon when the spec is nil.

Update docs and settings. Commit.

### Task C2: Results table (Delta 0.0%, Status, Used, Note columns, notes)

**Recon:** R:results-table#5 and R:palette#5.

**Interfaces:**
- **Delta:** reads "0.0%" (green) for the board's top. The trophy branch is removed.
- **Status:** a badge column showing "Best" with the trophy icon for the board's top, otherwise empty.
- **Used:** an icon cells column listing the trinkets and consumables the Usage module detected, with tooltips.
- **Note:** shows `record.note`, truncated, with the full text in a tooltip.
- **Note editing:** "Add Note" / "Edit Note" in the detail footer and the row menu opens an edit popup (StaticPopup with an editbox, at most 200 characters, escape codes stripped). It stores `record.note` and sends FIGHTS_CHANGED.
- **Damage and DPS bars:** `PALETTE.BAR` at `BAR_A` (D12).
- Port DR's badge and items cell kinds into `Results_Table.lua`.

**Tests:**
- the top row's delta is "0.0%";
- the Status badge is on the top only;
- the Used icons list the fight's usage;
- a note can be added, edited and cleared, and survives reload (the db);
- escape codes are stripped from notes;
- the bar colour is the palette's.

Update docs. Commit.

### Task C3: Results detail (section folds, footer, Gear and Talents)

**Recon:** R:results-detail#1, #2, #4.

**Interfaces:**
- **Section folds:** every section heading has a fold chevron. The state lives in `results.collapsedSections`, keyed by the sections `chart`, `spells`, `loadout`, `usage` and `note`.
- **Footer:** DR order and styles, Add Note · Share · Timeline · Compare, with Delete on the right. No primary-styled Timeline.
- **Gear and Talents:**
  - the gear button reads "View gear";
  - the talents button reads "View Talents";
  - the Copy button and its code are removed;
  - the talents line reads "Talents: <Class> (a/b/c)" on Forever, from `who.trees`, and keeps the spec/loadout name on Retail.
- Update spec §7 and README in the same commit.

**Tests:**
- folding a section hides its body, persists the state and moves the sections below it up;
- the footer order and labels;
- no Copy button;
- the talents line formats on Forever.

Commit.

### Task C4: Compare popup (label, colours, trinkets/consumables)

**Recon:** R:results-detail#3 and R:palette#6.

**Interfaces:**
- **Button:** the label is "Compare". Its tooltip names the target: the best, the runner-up, or the picked fight.
- **Bars:** this fight is drawn in `PALETTE.THIS_BAR`, the other side in `BEST_BAR`, both at `BAR_A`.
- **Text:** every figure and label on this fight's side is tinted `THIS_TEXT`, and the other side `BEST_TEXT`. Sides are fixed (D15).
- **Usage:** a new "Trinkets and consumables" section after "Gear changed" lists each side's used items (icon, name, uses), from the Usage data.

**Tests:**
- the label;
- the colours by side in both the best and the runner-up cases;
- the usage section lists both sides' items, and says "None used" when empty.

Commit.

---

## Milestone D: Timeline (Combat Trail)

### Task D1: Timeline icons or ticks, player/pet colours

**Recon:** R:timeline#1, #2.

**Interfaces:**
- **Setting:** `results.timelineMarks` = "icon" (default) | "tick", on the Results window settings tab. A toggle in the timeline header redraws it live.
- **Icon mode:** the By ability lanes draw the spell icon at each cast, with the same tooltip as the Casts strip icons. Overlapping icons are stacked or offset as the Casts strip does.
- **Caster colours:** ticks are coloured `PALETTE.PLAYER_LINE` / `PET_LINE` at 0.95. In icon mode, each icon gets a host-drawn 1px edge in the same colour. The Casts strip icons get the same edge.
- Fix the Timeline.THIS bug noted in R:palette#9 if it is still present.

**Tests:**
- the default mode is icon;
- an icon carries the cast's tooltip data;
- tick mode draws ticks;
- a pet cast's mark is in the pet colour and a player cast's in the player colour;
- the setting redraws an open timeline.

Update docs. Commit.

**Milestones C and D checkpoint:** push.

---

## Milestone E: DPS Race (worktree `../#Worktrees/DpsRace-ct-parity`, branch `feat/2026-11-10-ct-parity`)

**Setup (the orchestrator does this before E1):**
1. Fetch.
2. Choose the base: `origin/master` if the owner's merge of `feat/2026-11-10-quickcomms-forever-emotes` has landed there, otherwise that branch.
3. `git -C ../DpsRace worktree add ../#Worktrees/DpsRace-ct-parity -b feat/2026-11-10-ct-parity <base>`.

DPS Race uses its own CLAUDE.md gate. It is Retail-only after the base commit, so follow whatever profiles its CLAUDE.md lists.

### Task E1: DPS Race HUD sizing model (same as B3)

Port B3's model (D9 keys and semantics, the grip that sets bars, scroll, auto-grow with grow up/down) into DR's HUD. DR's existing grip and window size become the fixed mode, with 5 bars by default. Tests mirror B3's. Update DR's docs and its settings-panel rows. Commit.

### Task E2: DPS Race timeline icons or ticks, player/pet colours (DpsRace#21)

Port D1 into DR's `Results_Timeline.lua` / `Results_TimelineData.lua`, with the same setting key and default and the same caster colours. The commit message references `#21`. Tests mirror D1's.

### Task E3: DPS Race formatter fix and palette check

Port A5's `Format.Number` fix, since the code is shared. Then check that DR's bar, pet and compare colours equal Combat Trail's PALETTE. DR is the reference, so change DR only where it has no equivalent: the timeline caster colours and the pet bar colour, when DR has none. Commit.

**Milestone E checkpoint:** push the DPS Race branch.

---

## Milestone F: wrap-up

### Task F1: Extraction issue, docs sync, branch review, push

1. File a GitHub issue on CombatTrail: "Extract the code DPS Race and Combat Trail share". List the file pairs and their overlap from R:data-model#6, the candidate shared modules, and a suggested order.
2. Docs sync in both repos:
   - README;
   - ARCHITECTURE: per-client table, deviations and invariants;
   - schema;
   - settings-panel;
   - smoke-tests: new steps for sizing, notes, compare, timeline icons, recon, the Forever tree probe;
   - known-limitations;
   - spec §5 and §7.
3. A fresh multi-lens branch review (secrets, clients, runtime, UI/layout) with adversarial verification. Fix what is confirmed.
4. Run the green gate on both repos and push both branches. Report to the owner. The merge waits for their go-ahead. After the merge: delete both branches, the worktree and any stashes.
