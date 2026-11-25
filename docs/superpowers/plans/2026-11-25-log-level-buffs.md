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

**Resume:**
1. Run `git log --format=%s master..feat/2026-11-25-log-level-buffs` in the clone to see which IDs are done.
2. Read `git status` and either continue or stash any uncommitted work.
3. Relaunch the workflow with `resumeFromRunId`, or brief a builder from the spec for the missing IDs.
