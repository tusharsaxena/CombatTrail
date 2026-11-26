# Plan: Combat Sequence (2026-11-25)

- **Spec:** `docs/superpowers/specs/2026-11-25-combat-sequence-design.md`. Section numbers below
  (§N) are the spec's.
- **Branch:** `feat/2026-11-25-combat-sequence`, in the scratch clone `~/ka0s-scratch/cseq/CombatTrail`,
  from master `b679cc5`. The live repo under `GIT/` is never written, because the game loads it.
- **State is git:** an item is done when the branch has a commit whose subject starts `<ID>: `. A
  commit stages named files only, and never uses `--amend` or `--no-verify`.
- **Scope:** confirmed by the owner. The work never registers `COMBAT_LOG_EVENT_UNFILTERED`, and it
  never compares, counts or stores a secret value.

| ID | Item | Spec | Depends on |
|---|---|---|---|
| CSEQ-PLAN | the spec and this plan | – | – |
| CSEQ-1 | capture and table: drop `UNIT_COMBAT`, HIT/HEAL, Amount, school, target buffs, the Taken and Heals chips and `minAmount`; add the full-update / no-update-info diff for gains and fades; filter retired lines at read; schema step 8 | §1–§4, §6 (step 8), §8 | CSEQ-PLAN |
| CSEQ-2 | the rename everywhere: labels, locale strings, settings page key and tab, Results section key, window title, diagnostics line; `log.*` → `sequence.*` (defaults and every reader); `/ct sequence` with the `/ct log` alias; schema step 9 | §5, §6 (step 9), §7 | CSEQ-1 |
| CSEQ-3 | docs, smoke rows (unrun), the test inventory, the perf header's measured figures, the quirk entries | §8–§10 | CSEQ-2 |
| CSEQ-REV | independent review of the branch, then one fix pass | all | CSEQ-3 |

## CSEQ-1: capture and table

**Files:** `modules/CombatLog.lua`, `modules/LogTable.lua`, `modules/LogTable_View.lua`,
`modules/Results_Log.lua`, `modules/Hud_Log.lua`, `modules/LogWindow.lua` (the chip text in comments
only), `settings/Log.lua` (the removed rows only, still under `log.`), `defaults/Profile.lua` (the
`log` block's removed keys), `core/Database.lua` (step 8, `SCHEMA_VERSION` 8), `core/SkinSetup.lua`
(tokens, §3), `core/PerfSetup.lua` (the bracket comment), `locales/enUS.lua` (the keys left with no
caller), `tests/perf.lua`, and the tests named in §9 for these modules.

1. **Write the failing tests first:**
   - the diff cases in `test_combat_log.lua`: no-update-info gain and fade, full-update gain and fade,
     the line order, incomplete walks, secrets, a silent target change, the HARMFUL-only target walk;
   - the column and chip cases in `test_log_table.lua`;
   - the retired-line count cases in `test_results_log.lua`;
   - step 8's test.
2. **`CombatLog.lua`:**
   - delete `OnCombat`, `ACTION`, `MARK`, the `UNIT_COMBAT` handler and its `UNIT_EVENTS` entry, and
     `SEALED`;
   - retire `HIT` and `HEAL` in `KIND`'s comment;
   - change `CATEGORIES` and `CategoryOf` (no hits, heals or targetBuffs);
   - rename `IsBoundary` to `IsRetired`, and update every caller;
   - drop `a`, `s` and `x` from `append`, `keep` and `saved`;
   - make the target walk HARMFUL-only, and drop target HELPFUL from `mapped` (a target HELPFUL aura
     in `addedAuras` is no line);
   - add the diff: a scratch map, swapped with the current map, plus reused walk-order and fade
     arrays. `walk` reports whether it completed. `OnAura` diffs on a full update or with no usable
     info, while the capture is registered. `PLAYER_TARGET_CHANGED` and `register()` stay silent;
   - rewrite the header comment (SOURCES, SECRETS, THE RING, THE SAVED LOG) to match.
   - Every new or changed function stays at CCN ≤ 15. Split the diff into `walkInto`, `diffGains` and
     `diffFades` if needed.
3. **`LogTable.lua` / `LogTable_View.lua`:**
   - remove `amount()`, the `big` face, `School`, `SCHOOLS`, `HealWords`, the HIT and HEAL `TAG`,
     `TAG_COLOR` and `WASH` entries, `minAmount`, the Taken and Heals chips, and the crit, glancing
     and crushing Info words;
   - `ORDER` becomes `{ time, event, spell, info }`, the head reads "Spell", and the docked minimum
     width is re-measured;
   - rewrite both headers.
4. **`Results_Log.lua`:** drop its amount filter, and make the counts skip retired lines.
5. **Settings and defaults:**
   - remove the rows and the default keys for `view.columns.amount`, `view.schoolColors`,
     `show.hits`, `.heals`, `.minAmount` and `.targetBuffs`, the same three categories under
     `store.categories`, and `results.chips.taken` and `.heals`;
   - give the six remaining category rows the owner's labels (§5) now, under their `log.` paths.
6. **Step 8:** add `NS.DropRetiredSequenceKeys` (it runs on `profile.log`), and set `SCHEMA_VERSION`
   to 8.
7. **Skin tokens:** check how LibKa0s treats an override stored for a token that is no longer
   registered (read the vendored `libs/LibKa0s` skin code; never edit it). Remove the tokens or keep
   them, as §3 says, and record the outcome in the commit body.
8. **`tests/perf.lua`:**
   - remove the `logHit` pair, add the `logAuraDiff` pair and rewrite `busyFight` (§8);
   - run it on both clients;
   - no ceiling is raised.
9. **Gate** (below), then commit `CSEQ-1: …`.

## CSEQ-2: the rename everywhere and the key move

**Files:** `defaults/Profile.lua` (`log` → `sequence`), `core/Database.lua` (step 9,
`SCHEMA_VERSION` 9), `settings/Log.lua` (`PAGE = "sequence"`, the panel name, the title, the tab, every
label and tooltip in §5), `settings/Slash.lua` (the `sequence` row and `aliases.log`),
`settings/Hud.lua` (the rows tooltip), `modules/Hud.lua` (the control's tip and every `log.` read),
`modules/Hud_Log.lua`, `modules/LogWindow.lua`, `modules/LogTable.lua` and `modules/LogTable_View.lua`
(every `log.` path, the `Reseeds` prefix), `modules/Results_Log.lua`, `modules/Results_Detail.lua`
(`SECTIONS` `log` → `sequence`), `modules/Retention.lua`, `modules/Style.lua`, `modules/Diagnostics.lua`,
`core/Constants.lua` and `core/CombatTrail.lua` (comments or paths, where they name `log.`),
`locales/enUS.lua`, `tests/run.lua`, and every test that reads a `log.` path.

1. **Write the failing tests first:**
   - step 9's test (move, merge, fold key, idempotent, the 5 → 9 chain);
   - `test_slash.lua`'s alias and help cases;
   - `test_log_page.lua`'s page key, title and paths;
   - the Combat Sequence titles in the HUD, window and Results tests.
2. **The settings keys:**
   - `grep -rn '"log\.' modules settings core defaults tests --include='*.lua'` (excluding `libs/` and
     `tests/_kit/`) lists every reader;
   - move each one to `sequence.`;
   - also check `'log.'` written with single quotes, and prefix tests such as `path:find("^log%.")`.
3. **The locale strings:** add each new string; remove each old string that no longer has a caller.
   The repo's unused-key and prose tests settle the list.
4. **Step 9:** add `NS.MoveLogToSequence`, and set `SCHEMA_VERSION` to 9.
5. **`/ct sequence`:** the help row and `aliases.log = "sequence"`. If the standard's slash section
   requires an alias to be listed, stop and flag it (CLAUDE.md, *Standards compliance*).
6. **Gate,** then commit `CSEQ-2: …`.

## CSEQ-3: docs, smoke and the test inventory

**Files:** `README.md`, `docs/ARCHITECTURE.md` (the feature table, the event wiring per state: no
`UNIT_COMBAT`), `docs/module-map.md`, `docs/data-flow.md`, `docs/schema.md` (steps 8 and 9, the
`sequence.*` keys), `docs/settings-panel.md`, `docs/slash-dispatch.md`, `docs/common-tasks.md`,
`docs/known-limitations.md` (no outgoing damage; fades only while a capture is open), `docs/performance.md`,
`docs/forever-quirks.md` and `docs/midnight-quirks.md` (rewrite the `UNIT_COMBAT` / `UNIT_AURA` entries:
no `UNIT_COMBAT`; the diff covers missing update info; still not probed), `docs/smoke-tests.md`,
`docs/test-cases.md` and `docs/testing.md`. Every doc that describes HIT, HEAL, Amount, Taken, Heals or
target buffs, or names the feature Combat Log, is corrected. The frozen bundles (`docs/audits/`,
`docs/reviews/`, `docs/automated-tests/`, `docs/perf-analysis/`) and the earlier specs and plans are not
touched.

1. **Smoke rows:** add SM-CT-SQ1 to SQ10 under a new `(not run yet)` header line for this branch.
   Amend SM-CT-LG3, LG13, LG14, LG15, LG16, LG17 and LG25 to say which part is superseded. No row is
   marked passed.
2. **The test inventory:** list each new and changed case, with totals that match the suite's output
   under both profiles.
3. **The perf header:** record the re-measured `logPaint` figure and the new scenario's figure, with
   the date and the item.
4. **Gate,** then commit `CSEQ-3: …`.

## CSEQ-REV: review and fix pass

1. An independent reviewer (a fresh agent, not the builder) reads the whole branch diff
   (`master..feat/2026-11-25-combat-sequence`) against the spec. It checks for:
   - a `UNIT_COMBAT` or `COMBAT_LOG_EVENT_UNFILTERED` registration;
   - any comparison, count, key or store of a value that did not pass `Secrets.Plain*`;
   - a false fade from an incomplete walk;
   - a `log.` path left behind;
   - a stale "Combat Log" string a player can see;
   - a step that is not idempotent;
   - a raised perf ceiling;
   - CCN above 15;
   - a file over 1500 lines;
   - a doc that still describes the old rows.
2. Its findings are recorded as a `refs/notes/ka0s-review` note on the CSEQ-3 commit.
3. One fix pass, then the gate, then commit `CSEQ-REV: …`.

## The gate (before every commit)

```
~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua
KA0S_KIT_CLIENT=forever ~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua
~/.claude/dev-copilot/bin/ka0s-bounded luacheck .                # 0 warnings / 0 errors
python3 -m pytest -q -p no:cacheprovider tools/seeds
~/.claude/dev-copilot/bin/ka0s-bounded lua tests/perf.lua        # and with KA0S_KIT_CLIENT=forever
```

Every file stays at 1500 lines or fewer. A new or changed function stays at CCN ≤ 15, measured with
bounded lizard through the kit's sighted shadow, never raw `lizard`. If the complexity suite writes a
`docs/automated-tests/` bundle or changes `RESULTS.md` as a side effect, restore both before
committing.

## Checkpoints

- **After CSEQ-1 and after CSEQ-2:**
  - the gate is green on both profiles;
  - `git grep -n UNIT_COMBAT -- modules settings core` is empty apart from comments that say it is
    not registered;
  - after CSEQ-2, `git grep -n '"log\.' -- modules settings core defaults tests` is empty.
- **After CSEQ-REV:** the lead re-gates the branch, brings it into the live repo and pushes it.

**Merging, a version bump and a tag** all wait for the owner's go-ahead. The smoke rows are the
owner's to run.

## Resume

1. In the clone, run `git log --format=%s master..feat/2026-11-25-combat-sequence` to see which IDs are
   done.
2. Read `git status`. Continue the uncommitted work or stash it, and never `reset --hard` work you
   have not read.
3. Then either relaunch the workflow with `resumeFromRunId`, or brief a builder from the spec for the
   first missing ID.
