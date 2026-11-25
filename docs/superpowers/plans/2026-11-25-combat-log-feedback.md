# Plan: Combat Log feedback (2026-11-25)

- **Spec:** `docs/superpowers/specs/2026-11-25-combat-log-feedback-design.md`.
- **Branch:** `feat/2026-11-25-combat-log-feedback`, in `~/ka0s-scratch/ctfb/CombatTrail`.
- **State is git:** an item is done when a commit whose subject starts `<ID>: ` is on the branch.

| ID | Item | Spec items | Depends on |
|---|---|---|---|
| CLF-PLAN | spec and plan | – | – |
| CLF-1 | the table and the capture: columns, centering, the HEAL school, no boundary lines, reset at the pull, chips on, icons and the section look, no fold | 3, 4, 5, 8, 9, 10, 13, 14, 17, 18 | CLF-PLAN |
| CLF-2 | one window with static sizes: defaults (shown, 390, 5 bars, 10 rows), the chart after the fight, the scrollbar, two detach states, the Race window | 1, 2, 6, 7, 11, 12, 16 | CLF-1 |
| CLF-3 | the lanes verb and the Results detail without tabs: the Log section under Targets, no Damage by spell | 15, 19, 20 | CLF-2 |
| CLF-4 | settings and schema steps check, docs, smoke rows, full gate | all | CLF-3 |
| CLF-REV | independent review, then a fix pass | – | CLF-4 |

**Checkpoints:**
- **After CLF-2 and after CLF-4:** the gate is green on both profiles.
- **After CLF-REV:** the lead re-gates the work, then brings the branch into the live repo and pushes
  it.

**Merging** waits for the owner's go-ahead.

**Resume:** run `git log --format=%s master..feat/2026-11-25-combat-log-feedback` in the clone, read
`git status` (continue the uncommitted work or stash it), then relaunch the workflow with
`resumeFromRunId`, or brief a builder from the spec for the missing IDs.
