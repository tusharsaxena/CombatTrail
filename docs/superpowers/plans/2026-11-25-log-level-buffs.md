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

**Resume:**
1. Run `git log --format=%s master..feat/2026-11-25-log-level-buffs` in the clone to see which IDs are done.
2. Read `git status` and either continue or stash any uncommitted work.
3. Relaunch the workflow with `resumeFromRunId`, or brief a builder from the spec for the missing IDs.
