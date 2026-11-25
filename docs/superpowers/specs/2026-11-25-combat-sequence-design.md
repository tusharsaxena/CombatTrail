# Combat Sequence (owner, 2026-11-25)

- **The change:** the Combat Log becomes the **Combat Sequence**: the order of what you did and what
  happened to your buffs and debuffs, with no amounts. The hit and heal rows go.
- **Branch:** `feat/2026-11-25-combat-sequence`, built in the scratch clone
  `~/ka0s-scratch/cseq/CombatTrail` from master `b679cc5`. The live repo is left alone.
- **Plan:** `docs/superpowers/plans/2026-11-25-combat-sequence.md`.
- **Clients:** both (Retail and WoW Forever, one codebase).
- **Earlier specs:** `2026-11-25-log-level-buffs-design.md` (the Combat Log, #11, and its v2 addendum)
  and `2026-11-25-combat-log-feedback-design.md` (the 20 feedback items). Anything this spec does not
  change stays as those two have it. Where they disagree, this spec wins.
- **Scope:** confirmed by the owner.

## Why

The log's HIT and HEAL rows come from `UNIT_COMBAT` on `player`, which reports damage and healing
**taken**. The owner read the HIT amounts as their own hits. An addon can't capture outgoing per-hit
damage: `COMBAT_LOG_EVENT_UNFILTERED` is forbidden on Forever and sealed on Retail 12.x, and it is
never registered here, on either client. So the rows that looked like outgoing damage are dropped,
and the feature is renamed for what it can honestly show.

## The owner's words (verbatim)

> Lets rebrand it to something else - we can mark cast events and buff gains and buffs lost by the
> player. Is that possible? We can drop the amount part altogether, and HIT/HEAL events can be
> deprecated. We can call this "combat sequence"

The rows the owner picked to keep:

> Your casts, Buffs gained / lost on you, Pet casts, Debuffs on you / your target

The rename scope the owner picked: **"Everywhere"**. The HUD section, the detached window, the Results
section, the settings tab, the chips, the docs and the help text all say Combat Sequence. Saved
settings move over automatically through schema steps. `/ct log` keeps working as an alias of a new
`/ct sequence`.

## 1. What is captured

| Source | Before | After |
|---|---|---|
| Player and pet casts (the lanes' listener, `UNIT_SPELLCAST_*`) | CAST rows | **unchanged** |
| `UNIT_AURA` on `player`, HELPFUL | BUFF+ / BUFF− from `addedAuras` / `removedAuraInstanceIDs` only | BUFF+ / BUFF−, **plus a diff on a full update or with no update info** (§2) |
| `UNIT_AURA` on `player`, HARMFUL | DEBUFF+ / DEBUFF− | same, plus the diff |
| `UNIT_AURA` on `target`, HARMFUL from you or your pet | DEBUFF+ / DEBUFF− | same, plus the diff |
| `UNIT_AURA` on `target`, HELPFUL | BUFF+ / BUFF− on the target | **removed** (not among the owner's picks; a call, §11) |
| `UNIT_COMBAT` on `player` | HIT / HEAL rows with amount, school, crit, glancing, crushing | **removed**: never registered again |
| `PLAYER_DEAD` | DIES | **unchanged** |
| `PLAYER_TARGET_CHANGED` | the target list, a silent target walk | **unchanged** (the walk now reads HARMFUL alone) |

- `COMBAT_LOG_EVENT_UNFILTERED` is still never registered, on either client.
- `CombatLog.OnCombat`, the `UNIT_COMBAT` handler and its `UNIT_EVENTS` entry, and the
  `ACTION` and `MARK` tables are deleted.
- `CombatLog.Diagnose` no longer names `UNIT_COMBAT`. Its line in `/ct diagnostics` reads
  `combat sequence registered=… refused=… lines=…`.
- **The kinds** (`CombatLog.KIND`) keep their numbers, because saved logs carry them:
  `CAST 1, BUFF_ON 2, BUFF_OFF 3, DEBUFF_ON 4, DEBUFF_OFF 5, DIES 8`.
  - `HIT 6`, `HEAL 7`, `START 9` and `END 10` are **retired**. They are never captured, and they are
    kept in `KIND` only so an old saved log can be read past them.
  - `CombatLog.IsBoundary` becomes `CombatLog.IsRetired(e)`. It answers true for a retired kind, and
    for a BUFF± line on the target (`u` 3) from a log saved before this change.
  - Every view drops a retired line at read time: the live views, the Results Combat Sequence
    section and its chip counts.
  - Old saved logs are **never rewritten** on disk.
- **The marks** (`CombatLog.FLAG`): `INTERRUPTED = 8` stays at its bit, because saved data carries it.
  `CRIT`, `GLANCING` and `CRUSHING` had only `UNIT_COMBAT` as their source. They are removed from
  the Info words. Their bits stay reserved and are never reused.
- **`CombatLog.SEALED`** ("s", a sealed amount) goes. No line carries an amount any more, so the
  ring's `a`, `s` and `x` fields go too (the line is `{ n, at, k, u, id?, f?, g? }`), and so does the
  saved line's (`{ t, k, id?, u?, f?, g? }`). An old saved line that still has `a` or `s` is read
  past them, because no view reads them.
- **The categories** (`CombatLog.CATEGORIES`) become
  `{ "casts", "petCasts", "playerBuffs", "playerDebuffs", "targetDebuffs", "deaths" }`.
  `hits`, `heals` and `targetBuffs` go, and `CategoryOf` answers nil for them, which is what makes
  `IsRetired`'s lines unsaved and unshown.

## 2. Buff lost (fade) rows

**Today:** a buff or debuff loss on the player (BUFF− / DEBUFF−) is already logged, but only from
Retail-shaped update info. `removedAuraInstanceIDs` is matched against this file's map of instance to
spell. A full update (`isFullUpdate`), or a `UNIT_AURA` with no update info at all, is walked again
**without a line**. So on a client or a moment that sends no update info, nothing is logged. That
covers WoW Forever if its `UNIT_AURA` has no `updateInfo` (`docs/forever-quirks.md`: assumed, not
probed), and Retail's occasional in-combat full updates.

**After:** BUFF− (and DEBUFF−) is logged on both clients, whatever shape the update has. Two paths
feed it.

1. **Update info (Retail, and Forever if it has it).** This path is unchanged: `addedAuras` gives
   gains and `removedAuraInstanceIDs` gives fades. `updatedAuraInstanceIDs` (a refresh, a stack
   change) is still no line.
2. **The diff (Forever-safe).** This path handles a full update, no update info, or sealed or
   unreadable info. When a capture is open, the unit is walked into a **scratch map**, and the scratch
   map is then compared to the current map:
   - an instance in the scratch map and not in the current map is a **gain** (BUFF+ / DEBUFF+);
   - an instance in the current map and not in the scratch map is a **fade** (BUFF− / DEBUFF−);
   - the two maps are then **swapped**, never reallocated, and the old one is cleared for next time.

   The line order is fixed. Gains come first, in walk order, which is held in a reused array. Fades
   come next, by ascending instance ID, sorted in a reused array. The order is deterministic, so the
   tests can pin it.

**Rules for the diff:**

- **Only plain numbers are compared.** A map key is an instance ID that passed
  `Secrets.PlainNumber`, and a map value is a spell ID that passed it, negated for a debuff. A secret
  value is never compared, counted, stored, or used as a table key. A sealed aura table, a sealed
  instance or a sealed spell ID is skipped, exactly as `mapped()` skips it today.
- **An incomplete walk logs nothing.** A walk can stop early:
  - a sealed or unreadable aura breaks it;
  - `GetAuraDataByIndex` raises (Forever's sealed read, `docs/forever-quirks.md` §3);
  - it reaches `AURA_LIMIT`.

  Then the scratch map is incomplete. Its missing entries would read as false fades, so it replaces
  the current map **silently**, with no line at all. The walk is complete only when the index walk ran
  until `GetAuraDataByIndex` returned nil, for every filter walked.
- **The target walk stays silent across a change of target.** `PLAYER_TARGET_CHANGED` rebuilds the
  target's map with no line, as today, so a new target is not a burst of gains. Only a full update or
  update-less `UNIT_AURA` on the same target diffs.
- **The registration walk stays silent.** The walk at a capture's registration (the pull) is silent,
  as today. A fade of a buff that was up at the pull is still a BUFF− line, because the buff is in the
  map.
- **The target walk reads HARMFUL alone,** because target buffs are gone (§1). The player walk reads
  HELPFUL and HARMFUL.
- **Debuff fades:** DEBUFF− rows show for **debuffs on you and for your debuffs on your target** (a
  call, §11). They sit under the categories `playerDebuffs` and `targetDebuffs`, beside their gains,
  so there is no separate toggle.

**Out of scope, unchanged:** the capture registers only while a fight's capture is open (pre-pull floor
to fight end). A buff that fades after combat ends and before the next pull is not a line. The live view
still shows the casts the lanes hand in after combat.

## 3. The table: rows, columns and colours

**Event tags** (`LogTable.TAG`): `CAST`, `BUFF+`, `BUFF-`, `DEBUFF+`, `DEBUFF-`, `DIES`. `HIT` and `HEAL`
go. The tags keep their text (a call, §11). The settings and the chip tooltips spell out "gained" and
"lost".

| Kind | Tag colour | Wash | Spell cell |
|---|---|---|---|
| CAST (you) | `ct.text` | `ct.log.wash.cd` for a long base cooldown | the spell's icon and name |
| CAST (pet) | `ct.text` | as above | the icon and name (the paw stays where it is drawn today) |
| BUFF+ | `ct.log.buff` | none | icon and name |
| BUFF− | `ct.log.buffOff` (dimmed) | none | icon and name, dimmed |
| DEBUFF+ | `ct.log.debuff` | `ct.log.wash.debuff` | icon and name |
| DEBUFF− | `ct.log.debuffOff` (dimmed) | none | icon and name, dimmed |
| DIES | `ct.log.hit` | none | blank |

**Columns** (`LogTable.ORDER`): **Time · Event · Spell · Info**, every one centered, as feedback item 8
has it.

- **Amount goes:** `WIDTH.amount`, its head, the `amount()` cell builder, the critical's larger face
  (`Cells.big`, `BIG_FONT`) and `log.view.columns.amount` are all removed.
- **The Spell/School head becomes "Spell".** No row carries a school now. `LogTable.School`,
  `LogTable.SCHOOLS`, `LogTable.HealWords` and the HIT and HEAL branches of `spell()` go.
- **Info stays,** in the homes that have it (the detached window and Results). It reads only
  "Interrupted" now. Its toggle `view.columns.info` stays.
- **The docked minimum width shrinks** by Amount's share (its width plus one gap). The builder
  measures it, and the default `hud.width` stays 390.

**What is shown** (`LogTable.Shows`, and the Results section's own filter): the categories, and the
auto attacks (Auto Shot and Shoot, off by default). `show.minAmount` and its amount test go. A retired
line never shows.

**Skin tokens:** they keep their `ct.log.*` names (a call, §11). `ct.log.heal`, `ct.log.wash.hit` and
the seven `ct.school.*` tokens no longer have anything that draws them, so they are removed from
`core/SkinSetup.lua`. Before removing them, the builder checks how LibKa0s treats a stored skin
override for a token that is no longer registered. If it ignores the override, the tokens go. If it
errors, the tokens stay registered, unused, and the builder records this as a deviation from this
spec. `ct.log.hit` stays (DIES).

## 4. The chips

The chips (`LogTable.CHIPS`) appear in the live views (the docked section and the detached window) and
in the Results section, in this order:

| Key | Label | Covers | Tooltip |
|---|---|---|---|
| `casts` | Casts | `casts` | Your casts. |
| `pet` | Pet | `petCasts` | Your pet's casts. |
| `buffs` | Buffs | `playerBuffs` | Buffs gained and lost on you. |
| `debuffs` | Debuffs | `playerDebuffs`, `targetDebuffs` | Debuffs on you, and the debuffs you put on your target, gained and lost. |

- **Taken and Heals go.** Their `log.results.chips.taken` and `.heals` keys go too, through schema
  step 8.
- **No Deaths chip is added** (a call, §11). DIES rows follow the What to show and Storage toggles.

## 5. The rename: "Combat Sequence" everywhere

Every place a player can see the feature's name says **Combat Sequence**:

| Where | Before | After |
|---|---|---|
| The HUD's docked section heading (`Hud_Log.lua`) | Combat Log | **Combat Sequence** |
| The HUD title bar control's tooltip (`Hud.lua`, key `log`, icon `ph:list-bullets` kept) | Combat Log | **Combat Sequence** |
| The heading marks' tips | Show or hide the Combat Log's filter chips / Detach the Combat Log into its own window | …the Combat Sequence's filter chips / Detach the Combat Sequence into its own window |
| The detached window's title (`LogWindow.lua`) | Combat Trail · Log | **Combat Trail · Combat Sequence** |
| The detached window's dock and gear tips | Dock the Combat Log back… / Combat Log settings | Dock the Combat Sequence back in the DPS HUD / Combat Sequence settings |
| The Results detail's foldable section (`Results_Log.lua`) | Log | **Combat Sequence** |
| The Results empty state | No log was saved for this fight | No combat sequence was saved for this fight |
| The settings page title and its first tab | Combat Log | **Combat Sequence** |
| The settings page key, its panel name | `log`, `CombatTrailLogPanel` | **`sequence`**, **`CombatTrailSequencePanel`** |
| The Results tab's subgroup | Log section | Combat Sequence section |
| The Defaults button's tooltip | …every Combat Log setting… | …every Combat Sequence setting… |
| The slash help line | `log`: The Combat Log, in the DPS HUD… | `sequence`: The Combat Sequence, in the DPS HUD or its own window: /ct sequence toggles it, detach and dock move it (/ct log also works) |
| The usage line | Usage: /ct log show, hide, toggle, detach or dock | Usage: /ct sequence show, hide, toggle, detach or dock |
| The "off" notice | The Combat Log is off (log.enabled). | The Combat Sequence is off (sequence.enabled). |
| `/ct diagnostics` | combat log registered=… | combat sequence registered=… |
| README, the docs, `docs/smoke-tests.md` row text and the HUD sizing tooltip in `settings/Hud.lua` | Combat Log | Combat Sequence |

**The setting rows' new labels** come from the owner's picks (What to show, and Storage → Saved):

| Key (under `sequence.show.` and `sequence.store.categories.`) | Label | Tooltip (What to show) |
|---|---|---|
| `casts` | Your casts | Show the spells you cast. |
| `petCasts` | Your pet's casts | Show the spells your pet casts. |
| `playerBuffs` | Buffs gained / lost on you | Show the buffs you gain, and when each one ends. |
| `playerDebuffs` | Debuffs on you | Show the debuffs put on you, and when each one ends. |
| `targetDebuffs` | Your debuffs on your target | Show the debuffs you put on your target, and when each one ends. |
| `deaths` | Deaths | Show your death. |

**Rows removed from the settings page:**

- *Hits taken*, *Heals taken* and *Buffs on your target*, under What to show and under Saved;
- *Least amount shown*;
- *Show the Amount column*;
- *School colors*. The Colors tab's *Color-blind safety* subgroup keeps *Row washes*.

The tooltip of *Enable the Combat Sequence* now reads: "Record your casts, your pet's casts, the buffs
you gain and lose, the debuffs on you and your target, and your death during each fight, in order, and
show them in the DPS HUD's Combat Sequence section or its own window. Off, nothing is recorded and the
HUD's Combat Sequence control is hidden."

The *Row washes* tooltip now reads: "Tint the rows of debuffs going on and of long-cooldown casts. Off,
every row has the plain stripe."

**Locale strings:** each changed string gets a new key. Every key that no longer has a caller is
removed from `locales/enUS.lua`: `HIT`, `HEAL`, `Amount`, `Taken`, `Heals`, `Healing`, `Healing (%s)`,
`sealed`, `Critical`, `Glancing`, `Crushing`, `Hits taken`, `Heals taken`, `Buffs on your target`, the
two chip tips, the *Least amount*, *Amount column* and *School colors* rows and their tooltips. The
school names (`Physical` to `Arcane`) are removed only if nothing else calls them; the builder greps.
The repo's locale tests (unused keys, prose) decide the rest.

**Not renamed (internal; a call, §11):**

- the file names (`modules/CombatLog.lua`, `LogTable*.lua`, `Hud_Log.lua`, `LogWindow.lua`,
  `Results_Log.lua`, `settings/Log.lua`);
- the Lua identifiers (`NS.CombatLog`, `NS.LogTable`, `NS.HudLog`, `NS.LogWindow`, `NS.ResultsLog`,
  `C.LOG`);
- the lanes' listener name `"log"`, the HUD's title bar control key `log`, the perf bracket
  `combatLog` and the skin tokens `ct.log.*`;
- the fight record's `log`, `logDropped` and `logTargets` fields.

## 6. The settings keys and the schema steps

**The keys move** from `log.*` to `sequence.*`. Every key under the profile's `log` table moves, with
the same shape, minus the retired keys below. Every `NS.GetSetting("log.…")`, `NS.SetByPath("log.…")`,
`SETTINGS_CHANGED` path test (the prefix `log.`, `LogTable.Reseeds`), schema row path and test reads
`sequence.…`.

**`results.collapsedSections`:** the Results section key `log` in `Detail.SECTIONS` becomes
`sequence`, and a stored fold moves with it.

| Step | Item | Body | What it does |
|---|---|---|---|
| **7 → 8**, per profile | CSEQ-1 | `NS.DropRetiredSequenceKeys(profile)` | Drops, under the stored `profile.log`: `view.columns.amount`, `view.schoolColors`, `show.hits`, `show.heals`, `show.minAmount`, `show.targetBuffs`, `store.categories.hits`, `store.categories.heals`, `store.categories.targetBuffs`, `results.chips.taken` and `results.chips.heals`. Nothing is carried across, because each key served only what was removed. |
| **8 → 9**, per profile | CSEQ-2 | `NS.MoveLogToSequence(profile)` | Moves `profile.log` to `profile.sequence` (a deep merge: a key already stored under `sequence` wins, and a key only under `log` is copied), then sets `profile.log = nil`. Moves `profile.results.collapsedSections.log` to `.sequence`, the same way. |

- `NS.SCHEMA_VERSION` goes to **9**.
- Both steps are idempotent: a fresh profile stores none of these keys, and a second run finds no
  `log`. A profile with no `log` table is left alone.
- Each step has its own test, which covers a fresh profile, a profile holding every retired key, a
  profile holding both `log` and `sequence`, and a second run.
- The fight record format (`CT_SCHEMA`) does not change, and no record is rewritten. The steps never
  touch `CombatTrailDB`'s fight history.

**Defaults** (`defaults/Profile.lua`): the `log = { … }` block becomes `sequence = { … }`, with these
changes:

- `view.columns = { spell = true, info = true }`;
- `view.schoolColors` removed;
- `show = { casts, petCasts, playerBuffs, playerDebuffs, targetDebuffs, deaths, autoAttacks = false }`;
- `store.categories = { casts, petCasts, playerBuffs, playerDebuffs, targetDebuffs, deaths }`;
- `results.chips = { casts, pet, buffs, debuffs }`.

The block's comment is rewritten to match.

## 7. The slash verb

- **`/ct sequence [show|hide|toggle|detach|dock]`** is the verb: `HudLog.OnVerb` under a new help row
  `sequence`.
- **`/ct log`** is an **alias** of it, through the slash table's `aliases` (`{ options = "config",
  log = "sequence" }`). Every sub-verb works the same under either name, and the help lists only
  `sequence`. If the standard requires an alias to be listed (slash-commands-§), the builder stops and
  flags it rather than deviating.
- The feature hold (`feature()`) covers the verb as it does today.
- `docs/slash-dispatch.md` and the README's slash section show `/ct sequence` and note the alias.

## 8. Performance

The capture's contract is unchanged: constant work for each event, and no allocation beyond a line's
table, which the ring reuses once it is full.

- **Less work:** `UNIT_COMBAT` was the busiest source after casts, and it is no longer registered. The
  target walk reads one filter instead of two.
- **New work:** the diff (§2), on a full update or an update-less `UNIT_AURA`. It is one walk of the
  unit (at most `AURA_LIMIT` reads for each filter) and one pass over each map. The scratch map, the
  walk-order array and the fade array are this file's own reused tables, so a diff allocates nothing
  once warm. Only plain numbers are compared or used as keys. The aura tables that
  `GetAuraDataByIndex` returns are the client's cost, as today.
- **On Forever without update info,** every `UNIT_AURA` on the player is a diff. That is up to 80
  reads, bracketed under `combatLog`. The bracket name is kept, so earlier perf-analysis bundles still
  compare.
- **`tests/perf.lua`:**
  - `logHitCaptureOff` / `logHitCaptureOn` are removed.
  - **`logAuraDiffCaptureOff` / `logAuraDiffCaptureOn`** are added: a `UNIT_AURA` on `player` with no
    update info, where the mock's aura list alternates between holding one buff and not, so each pair
    of events is one gain and one fade. Ceiling **8** bytes per iteration. Notes per iteration: 0 off,
    1 on. They are paired as the old pair was.
  - **`busyFight`** becomes: two casts, a player buff gained and lost (update info), and a target
    debuff gained and lost. Its ceiling stays 16.
  - **`logPaint`** keeps its 10,240 ceiling. With Amount gone, each row paints one fewer label, so its
    measured figure should fall. The builder re-measures and records the new figure in the file's
    header.
  - No ceiling rises. If one has to rise, the builder says so as a call.
- `docs/performance.md`'s `combatLog` row is updated: auras, deaths and the diff; no hits or heals.

## 9. Tests

The headless suites must pass under both kit profiles (`lua tests/run.lua`, and the same with
`KA0S_KIT_CLIENT=forever`). The cases below are new or rewritten.

- **`tests/test_combat_log.lua`:**
  - no `UNIT_COMBAT` registration on either client (the frame's registrations name `UNIT_AURA`,
    `PLAYER_DEAD` and `PLAYER_TARGET_CHANGED` only);
  - `OnCombat` is gone;
  - BUFF− from `removedAuraInstanceIDs` (as today);
  - BUFF+ and BUFF− from a **full update diff**, and from a `UNIT_AURA` with **no update info**;
  - the diff's line order: gains in walk order, then fades by instance ID;
  - an incomplete walk (a sealed aura mid-list; a raising reader; `AURA_LIMIT` reached) writes **no**
    line and leaves no false fade on the next complete diff;
  - a secret instance or spell ID is never a key and is never compared (the kit's secret values, and
    the kit's tripwire if it has one);
  - a target change is silent;
  - the target walk reads HARMFUL only, and no target BUFF line exists;
  - DEBUFF− on you and on the target;
  - DIES unchanged;
  - `CategoryOf` answers nil for HIT, HEAL and a target BUFF;
  - `IsRetired` covers HIT, HEAL, START, END and target BUFF±;
  - `CATEGORIES`' new list;
  - the saved line has no `a` or `s`.
- **`tests/test_log_table.lua`:**
  - the columns are Time, Event, Spell and Info (no Amount, in every home and at every width);
  - the head reads "Spell";
  - the narrow-home rule (Info dropped first) still holds;
  - the tags and their colours for the six kinds;
  - the washes (DEBUFF+ and a long-cooldown CAST only);
  - Info reads "Interrupted" and nothing else;
  - `Shows` has no amount test;
  - an old saved HIT, HEAL or target BUFF line is not shown;
  - the chips: four, in order, with their categories and tips.
- **`tests/test_results_log.lua`:**
  - the section is titled Combat Sequence;
  - the chip counts count only live kinds, so a saved log holding HIT, HEAL, PULL, END and target
    BUFF lines counts none of them;
  - the empty state text;
  - the section key `sequence` folds and unfolds.
- **`tests/test_log_page.lua`:**
  - the page key `sequence`, its title and panel name;
  - the first tab, Combat Sequence;
  - no row for the removed keys;
  - the six category rows' labels in both What to show and Saved;
  - every row's path starts with `sequence.`.
- **`tests/test_log_window.lua`, `tests/test_hud_static.lua` and `tests/test_race_window.lua`:** the
  titles and headings say Combat Sequence, the docked minimum width is re-measured, and the 390-wide
  default height still holds 5 bars and 10 rows.
- **`tests/test_slash.lua`:**
  - `/ct sequence` with each sub-verb;
  - `/ct log` reaches the same handler for each sub-verb;
  - the help lists `sequence` and not `log`;
  - the usage line.
- **`tests/test_settings.lua` (or wherever the steps are tested):**
  - step 8 drops each retired key, and is idempotent;
  - step 9 moves `log` to `sequence`, merges when both exist (the `sequence` value wins), moves the
    fold key, and is idempotent;
  - `SCHEMA_VERSION` is 9;
  - a profile at schema 5 runs 6 to 9 in order and ends with no `log`.
- **`tests/test_load.lua`, `tests/test_retention.lua`, `tests/test_diagnostics.lua` and
  `tests/test_docs.lua`:** every `log.` path they read moves to `sequence.`; Retention trims
  `record.log` by `sequence.store.fights`; the diagnostics line reads `combat sequence`.
- **`tests/run.lua`'s fixture** writes `NS.db.profile.sequence.drawer.*`.
- **The test inventory** (`docs/test-cases.md`, `docs/testing.md`) lists the new and changed cases,
  with counts that match the suite's totals.

## 10. Smoke rows (written unrun)

New rows go in `docs/smoke-tests.md`, under a new header line for the branch
`feat/2026-11-25-combat-sequence`, all `(not run yet)`. The rows they supersede, wholly or in part
(SM-CT-LG3, LG13, LG14, LG15, LG16, LG17 and LG25), are amended to say so, and they lose any pass mark.

| ID | Client | Steps | Expect |
|---|---|---|---|
| SM-CT-SQ1 | Both | After `/reload` on the owner's existing profile, open the HUD, then the settings panel, then a stored fight in Results. | The HUD section, the title bar tip, the settings page and its first tab, and the Results section all read **Combat Sequence**. The earlier choices (docked or detached, the rows, the chips shown, the jump to the Timeline) are as they were. |
| SM-CT-SQ2 | Both | Fight a dummy for 20 s: cast, let the pet cast, gain a buff that ends mid-fight (a trinket or a proc), take a debuff, put a DoT on the dummy and let it fall off. | Rows read CAST, pet CAST, BUFF+ then BUFF- for that buff, DEBUFF+ / DEBUFF- for the debuff on you, DEBUFF+ / DEBUFF- for your DoT on the target. No HIT or HEAL row. No Amount column. |
| SM-CT-SQ3 | Forever | As SQ2, with `/ct debug on`. | BUFF+ and BUFF- rows appear on Forever. Afterwards, `/ct diagnostics` shows `combat sequence registered=… refused=none` and no `UNIT_COMBAT`. |
| SM-CT-SQ4 | Both | Target the dummy, then a friendly player with buffs, then the dummy again, all mid-fight. | No burst of rows at either target change. No row for the friendly player's buffs. |
| SM-CT-SQ5 | Both | Read the chips in the docked section, the detached window and the Results section. Click each. | Four chips, **Casts, Pet, Buffs, Debuffs**, in that order. No Taken or Heals chip. Each chip hides and shows its rows. |
| SM-CT-SQ6 | Both | `/ct sequence`, `/ct sequence detach`, `/ct sequence dock`, then `/ct log`, `/ct log hide`, then `/ct help`. | Each verb works under both names. Help lists `sequence` with the alias note, and no separate `log` row. |
| SM-CT-SQ7 | Both | Open a fight stored before this branch whose saved log had hits, heals and target buffs. | Its Combat Sequence section shows only casts, buffs and debuffs on you, debuffs on the target, and deaths. The chip counts match the rows shown. |
| SM-CT-SQ8 | Both | Settings → Combat Sequence: read every tab. | No Hits taken, Heals taken, Buffs on your target, Least amount shown, Amount column or School colors row. What to show and Saved list the six rows with the owner's labels. |
| SM-CT-SQ9 | Both | Docked at the default 390 width, read the columns; then detach and read them again. | Docked: Time, Event, Spell. Detached: Time, Event, Spell, Info. Every column is centered. An interrupted cast reads Interrupted under Info. |
| SM-CT-SQ10 | Both | Have the debuff fall off you while the section is scrolled away (paused); then Resume. | The DEBUFF- row is there in order. Pausing did not drop it. |

## 11. Calls made without asking

| Area | Call |
|---|---|
| Target buffs | **Removed** (capture, category, chip coverage, rows and keys). The owner's picks named buffs on you and debuffs on you and your target, and did not name buffs on the target. Old saved target BUFF lines are filtered at read. |
| Debuff fades | **Shown**, on you and on your target (DEBUFF−), under the same categories as their gains. "Debuffs on you / your target" reads as both ends. A DoT falling off the target is the moment to reapply it, which is the point of a sequence. |
| Fades on Retail | The diff runs on **both clients** for a full update, not only on Forever, so Retail's in-combat full updates stop hiding gains and fades. |
| Incomplete walk | Logs **nothing**: a missed row is better than a false fade. |
| Tags | `BUFF+` / `BUFF-` / `DEBUFF+` / `DEBUFF-` keep their text. The settings and chip tooltips say "gained" and "lost". |
| Info column | **Kept**, holding Interrupted alone. Critical, Glancing and Crushing had only `UNIT_COMBAT` as a source. |
| Spell column head | "Spell/School" becomes **"Spell"**, because no row carries a school. |
| Deaths | **Kept** as DIES, with no chip of its own, as today. |
| Key move | `log.*` moves to `sequence.*` (step 9), with `results.collapsedSections.log` moved to `.sequence`. The retired keys are dropped first (step 8), so nothing dead is carried across. |
| Not renamed | File names, Lua identifiers, the lanes' listener name, the HUD control key, the `combatLog` perf bracket, the `ct.log.*` skin tokens and the fight record's `log` fields. None of these is visible to a player. Renaming them would churn the module map and older perf bundles, would orphan skin overrides, and would rewrite every stored fight. |
| Skin tokens | The unused `ct.log.heal`, `ct.log.wash.hit` and `ct.school.*` are removed only if LibKa0s ignores a stored override for an unregistered token. Otherwise they stay, and the builder records it. |
| Alias in help | `/ct log` is not listed separately. The `sequence` help line names it. |
| Window title | "Combat Trail · Combat Sequence" (the window was "Combat Trail · Log"). |
| Saved logs | Never rewritten. Retired kinds and target BUFF lines are dropped at read time, as feedback item 10 did for PULL and END. |
| Perf | No ceiling is raised. The new diff scenario is held to the same 8-byte ceiling as the other capture scenarios. |
