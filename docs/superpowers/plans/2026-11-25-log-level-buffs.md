# Plan: combat log window, target level, buffs in Used (#11, #12, #13)

- **Spec:** `docs/superpowers/specs/2026-11-25-log-level-buffs-design.md`.
- **Branch:** `feat/2026-11-25-log-level-buffs`.
- **Where it's built:** the scratch clone `~/ka0s-scratch/ctlog/CombatTrail`. The live repo is left alone, because the game
  loads it. The lead brings the branch over with
  `git fetch ~/ka0s-scratch/ctlog/CombatTrail feat/2026-11-25-log-level-buffs:feat/2026-11-25-log-level-buffs`.
- **State is git.** An item is done when a commit whose subject starts `<ID>: ` is on the branch.

| ID | Milestone | Item | Depends on |
|---|---|---|---|
| CL-PLAN | M0 | spec and plan | – |
| CL-12 | M1 | target level formatter in the Encounter column, the detail title, Targets and Insights; tests | CL-PLAN |
| CL-13a | M1 | buff seed research (wago, pinned per client), frozen bundles, `defaults/BuffSeeds.lua`, validate-seeds contract, gate test | CL-PLAN |
| CL-13b | M1 | buffs in Used (spell-keyed entries, schema step, migration), plain food and drink excluded; tests | CL-13a |
| CL-11a | M2 | log capture (casts, auras, UNIT_COMBAT probe), ring buffer, saved `log` on the fight record, schema step, cap, retention; tests and a perf scenario | CL-13b |
| CL-11b | M2 | the Combat Log window: live feed and saved-fight view, chips, damage by spell, Older/Newer, `/ct log`, entry button, Results Log button | CL-11a |
| CL-11c | M2 | settings, docs, locales, smoke rows, full gate on both profiles | CL-11b |
| CL-REV | M3 | independent review, then a fix pass | CL-11c |

**Checkpoints:**
- **M1:** the gate is green on both profiles.
- **M2:** the full gate is green.
- **M3:** the lead re-runs the gate and pushes the feature branch.

**Merging** waits for the owner's go-ahead.

## Execution notes

- **CL-REV: the buff seed research has its own bundles, against the spec.** The spec put the buff
  research in `docs/seed-research/2026-11-25-{retail,forever}/`. Those bundles were frozen and merged
  by the same day's seeds run (SF-CT-01), and clients-§10 says a seed bundle is never edited after
  the fact. CL-13a re-derived into them anyway. CL-REV restored both to master's bytes and derived
  the buff seeds, at the same pinned builds, into `docs/seed-research/2026-11-25-retail-buffs/` and
  `docs/seed-research/2026-11-25-forever-buffs/`. `tools/seeds/seeds.py` now accepts a
  `<date>-<flavor>-<label>` bundle, which sorts after its day's plain one.
- **CL-REV: Well Fed rule 2.** Buff food whose buff is not named Well Fed is now seeded through
  what it gives, for example Dirge's *Increased Stamina* 25661.
- **Owed (owner): the current Retail fight buffs.** The Retail `buffs` list is Classic-era and event
  buffs only, so SM-CT-R35 is event-gated until the owner names the buffs to track.

- **CL-11a: the storage keys have defaults and no rows yet.** `log.enabled`, `log.store.enabled`,
  `log.store.lines` and `log.store.categories.*` are in `defaults/Profile.lua` and read by
  `modules/CombatLog.lua`. Their schema rows, the Combat Log page and their settings-panel.md lines
  arrive with CL-11c, so until then `NS.SetByPath` refuses them. CL-11a also adds `tests/perf.lua`, the
  first offline scenario runner, which CL-11b's repaint can extend.

- **CL-11b split (CL-11b, CL-11b2).** CL-11b builds the shared table component
  (`modules/LogTable.lua`, `modules/LogTable_View.lua`) and the DPS HUD's docked drawer
  (`modules/Hud_Log.lua`): the Log control on the HUD title bar, the drawer under the spell rows
  with its accent seam, the fold to a one-line strip with the newest event, 3 to 20 rows (8),
  the newest-first sort flipped from the Time header, follow, pause and Resume, the display
  throttle, `/ct log`, and the Race window's matched height following the drawer. **CL-11b2**
  builds the detached companion window (dock and detach, HUD-follow unless pinned, its own rows,
  the Info column) and the default layout that keeps it and the Race window apart.
- **CL-11b: three drawer keys are write-through for now.** `log.drawer.shown`,
  `log.drawer.collapsed` and `log.view.sort` are written by the drawer's own controls, so they are
  in `settings/Schema.lua`'s write-through list until CL-11c gives them rows; CL-11c takes them off
  that list when it does. Every other `log.drawer.*`, `log.view.*` and `log.show.*` key has its
  default in `defaults/Profile.lua` and no row yet.
- **CL-11b: the suites start with the drawer's auto-open off.** `tests/run.lua` turns
  `log.drawer.autoOpen` off on each instance, so a fight leaves the HUD at the height its own
  suites pin; `T.load{ logDrawer = true }` keeps the shipped default (`tests/test_log_table.lua`).

- **CL-11b2: the detached window and its keys.** `modules/LogWindow.lua` is home B. `log.home`
  ("docked" | "detached"), `log.window.attached` and `log.window.pinned` are written by its marks
  and `/ct log detach|dock|pin|unpin`, so they join the write-through list until CL-11c gives them
  rows. `log.window.position`, `log.window.width` and `log.window.height` are geometry only the drag
  and the grip determine, written raw as the Race window's `raceWindow.position` is. The other
  `log.window.*` keys (`side` LEFT, `matchHud`, `fill`, `rows` 3-40, `locked`, `scale`, `alpha`) have
  defaults and no rows yet. `log.drawer.shown` stays the log's one open switch in either home.
- **CL-11b2: the Race window.** Its matched height already takes the drawer (CL-11b). Detached, the
  HUD reserves no drawer and the Race window follows it back down. The two companions default to
  opposite sides (log LEFT, Race RIGHT). On one side, the log stands beyond the Race window
  (RaceWindow's redockSim tells it each time the Race window shows, hides or moves), and the sim
  panel docks beside the outermost window on the right.

- **CL-11c split (CL-11c, CL-11c2).** CL-11c builds home C: the Results fight detail's Overview,
  Timeline and Log tabs (`modules/Results_Detail.lua`), the Log tab (`modules/Results_Log.lua`: the
  saved log in the shared table with the Info column, the chips with their counts, Damage by spell in
  the HUD's spell rows, a CAST row's click opening the timeline at that cast through
  `Timeline.FocusAt`), and "No log was saved for this fight" for an older fight. **CL-11c2** builds the
  Combat Log settings page with every row of the addendum, takes the write-through keys off that list,
  and finishes the docs (settings-panel.md, the log's smoke rows beyond the Results tabs) and the full
  gate.
- **CL-11c: the Timeline keeps its window.** The Timeline tab is its way in (the addendum's second
  option): it opens the window as the footer's Timeline button does, and the tab shown stays as it was.
  `log.results.jumpToCast` and `log.results.chips.*` have defaults and no rows until CL-11c2.

- **CL-11c2: the Combat Log page.** `settings/Log.lua`, eight tabs (Combat Log, Docked drawer,
  Detached window, Order and display, What to show, Colors, Storage, Results) with a row for every
  `log.*` key but the detached window's drag-and-grip geometry (`log.window.position`, `width`,
  `height`, written raw as the Race window's place is). Every `log.*` key is off the write-through list.
  New keys: `log.view.fontSize` (8-16 points, 10) and `log.view.rowHeight` (12-28 px, 14), read at
  layout by `modules/LogTable_View.lua` (each text size its own pool of rows, because the skin keeps the
  size a label had at its first paint), and `log.colors.*`: "You" a ColorPair with Use class color on
  (the log shipped "You" in the class color, options-ui-§17's "unless the addon already ships it on"),
  the hostile and friendly target colors a reaction palette with no class companion (§17's exemption),
  each with Use the skin's color on. The detached window's gear opens the page. Hide auto attacks is the
  existing `log.show.autoAttacks`, drawn as *Show auto attacks* (off), and the window's "background
  opacity" is `log.window.alpha`, the whole window's opacity, drawn as *Window opacity*.

- **CL-11b/CL-11c2: five table-design substitutions, for the owner to rule on (recorded by CL-REV).**
  The addendum's *The table* asked for five things the build draws differently; each reason was only in
  `modules/LogTable.lua`'s header. SM-CT-LG19 puts each in front of the owner.
  1. *A critical "bold with ★"*: drawn as `*` after the plain amount, in the row's larger amount face.
     WoW's font objects have no bold weight, and FRIZQT__ (the body font) has no ★ glyph.
  2. *"You" "always bold"*: drawn in the class color (or the player's own `log.colors.you`) only, for
     the same reason: no bold weight.
  3. *"Spell names are in their school's colour"*: only the school word of a HIT or HEAL row is in its
     school's color. A CAST or an aura row's spell has no school the addon can read: the client offers
     no spell-school API for a cast or an aura (only UNIT_COMBAT's school, for a hit or a heal).
  4. *"Friendly units blue or their class colour"*: a friendly target is `ct.log.friendly` (blue) or the
     player's own swatch, never its class color. Each target line now records the target's name and
     reaction when it was captured (`logTargets`, CL-REV); its class is not recorded.
  5. *Batch mode painting "each repaint tick"*: it paints the queued rows together once every
     `log.view.throttleMs` ms. A batch every repaint tick would be the same as Instant, because the tick
     is the only time a view paints.

- **CL-REV: the live views' chips.** The addendum's *What to show* row named "the default filter
  chips", and only the Results Log tab had chips. The detached window now carries the chips under its
  status line and the drawer behind a filter mark (the eye) in its header, which opens a chips row under
  it, the HUD growing by it (the drawer's width at the HUD's default 260 px wraps them to two lines, so
  they are not drawn by default). Each view's chips are its own for the session, seeded from `log.show.*`
  when it is built, when the log is opened or moved, at each FIGHT_STARTED and at a `log.show` write.
  `LogTable.CHIPS` is now the shared list (`ResultsLog.CHIPS` is it). SM-CT-LG17.
- **CL-REV: which target, per line.** Each line on the target records which target it was: an index
  `g` into the session's target list (`CombatLog.Targets`, noted at registration and each
  PLAYER_TARGET_CHANGED, once per name and reaction), saved as the record's `logTargets` (CT_SCHEMA 6,
  still unmerged, so no new step). A swap mid-fight no longer renames the earlier rows. SM-CT-LG18.
- **CL-REV: each capture keeps its own saved lines.** The saved log was rebuilt from the shared
  2000-line ring at the fight's end, so heavy unsaved traffic (auto attacks, categories not saved) could
  push saved lines out before then. Each capture now keeps its own bounded list as lines arrive.
- **CL-REV: the stored logs' total bound, `log.store.fights`** (100; 0 to 500, 0 keeps every log). Each
  purge run strips the log from every stored fight but the newest that many carrying one, best-holding
  fights included (docs/performance.md, *Stored size*: about 3.8 MB at the defaults instead of about
  19 MB). SM-CT-LG20.

**Resume:**
1. Run `git log --format=%s master..feat/2026-11-25-log-level-buffs` in the clone to see which IDs are done.
2. Read `git status` and either continue or stash any uncommitted work.
3. Relaunch the workflow with `resumeFromRunId`, or brief a builder from the spec for the missing IDs.
