# Seed validation — Combat Trail

This is the seed-validation contract that `/dev-copilot:validate-seeds CombatTrail <flavor>` runs. The
command supplies the loop: a clean tree, one date, then status, derive, rule, apply, gate and hand-back,
along with its standing rules. This file supplies Combat Trail's side: the tool, the files it writes, the
precedent a ruling follows and each client's nuances. The command reads the headings below by name, so
keep them as they are.

**This contract supersedes DPS Race's** (`DpsRace/docs/validate-seeds.md`, last run 2026-11-15).
DPS Race is retired and its repository is archived. Its hearthstone list and its dummy catalog now
live here, so its contract is left where it is and never run again.

Each run ends in a frozen bundle under `docs/seed-research/<date>-<flavor>/`. The tool is
`tools/seeds/seeds.py`, and its docstring is its manual. The first runs are
`docs/seed-research/2026-11-25-retail/` and `docs/seed-research/2026-11-25-forever/`.

**What is validated, and what is not.**

- **`defaults/Hearthstones.lua` (`NS.HEARTHSTONE_SPELLS`) is derived** (Retail). Its header states
  the four rules it was built by on 2026-10-28, and `derive` runs exactly those rules. A re-run
  therefore reproduces the shipped list, and its candidates are whatever a new build adds under the
  same rules. Race mode is Retail only, so the `forever` flavor does not read this list.
- **`defaults/IgnoreSeeds.lua` (`NS.IgnoreSeeds.<Client>`) is curated, not derived.** It holds the
  auto-repeat attacks each lane hides. It takes no candidates. Every id the flavor's client ships
  is checked on that client's own build, both that it exists and that its name matches the one the
  file's header gives it.
- **`defaults/Dummies.lua` (`NS.DummySeeds`) is measured, not derived.** Its header says a row is
  added from a capture in game and never guessed, so it never takes an accepted candidate.
  - **Retail is not checkable.** No DB2 names a training dummy, so the tool reads no `Creature`
    table (see `## Notes`).
  - **WoW Forever is EMPTY BY DECISION.** The `forever` flavor's ForeverDB step lists every ForeverDB
    creature whose name holds the word "dummy" as a `dummies:<id>` candidate, for information only.
    `reject` is the only ruling such a candidate takes.
- **`defaults/BuffSeeds.lua` (`NS.BuffSeeds.<Client>`) is derived, per client** (CombatTrail #13).
  It holds three things for each client, and both flavors derive their own client's:
  - `buffs`, the world, zone, camp, shrine, faire and event buffs the Used column lists;
  - `wellFed`, the Well Fed auras through which buff food is counted;
  - `foodSubclass`, the Consumable subclass of Food & Drink, which is never listed by its own Eat or
    Drink aura.

  Its header states the three rules, and `derive` runs exactly those rules (`derive_buffs`,
  `derive_wellfed`, `derive_food`) on the flavor's own build. Every derived id is ruled, so the
  shipped lists are the accepted rulings and nothing else. `test_seeds.py`'s gate,
  `test_shipped_buffs_match_the_rulings`, holds each client's file to that.

## Flavors

| Flavor | Source | Seed files | Tools |
| --- | --- | --- | --- |
| `retail` | wago.tools product `wow` (Retail live) | `defaults/Hearthstones.lua` (derived), `defaults/IgnoreSeeds.lua` `Retail` (checked), `defaults/BuffSeeds.lua` `Retail` (derived) | `tools/seeds/seeds.py` |
| `forever` | wago.tools product `wowf` (WoW Forever live). Evidence: ForeverDB | `defaults/IgnoreSeeds.lua` `Forever` (checked), `defaults/Dummies.lua` `Forever` (ForeverDB evidence, information only), `defaults/BuffSeeds.lua` `Forever` (derived) | `tools/seeds/seeds.py`, dev-copilot's `scripts/foreverdb.py` |

Combat Trail is `Retail · Forever` in the roster, so both flavors run. Each flavor reads only its own
client's data (clients-§5, clients-§10). The Retail flavor never reads ForeverDB.

## Rules

- **Only the tool writes the lists' rows.**
  - `seeds.py apply` inserts and removes rows of `NS.HEARTHSTONE_SPELLS`, and removes ids from the
    flavor's own client in `NS.IgnoreSeeds`.
  - It inserts and removes the rows of the flavor's own client's `buffs` and `wellFed` lists in
    `NS.BuffSeeds`, in ascending order, and writes that client's `foodSubclass`. It never touches the
    other client's block.
  - It never writes `defaults/Dummies.lua`.
  - Each file's header comment is hand-written, and is rolled by hand under `### After`.
- **Rulings are data.**
  - They live in `tools/seeds/retail_rulings.json` and `tools/seeds/forever_rulings.json`, one file per
    flavor, and only `seeds.py rule` writes them.
  - Candidates have keys `hearthstones:<id>` (ruled `accept` or `reject`) and `dummies:<id>` (ruled
    `reject` only), and `buffs:<id>`, `wellfed:<id>` and `food:<subclass>` (ruled `accept` or
    `reject`).
  - Flags have keys `shipped:<kind>:<list>:<id>`, ruled `keep` or `remove`.
  - A ruling is never keyed by build. It holds until the thing it ruled on stops being proposed.
- **The four hearthstone rules** come from the header of `defaults/Hearthstones.lua`, as
  `derive_hearthstones` reads them:
  1. every spell with a `SpellCategories` row of `ChargeCategory` 2309, the shared hearthstone
     cooldown, at any `DifficultyID`;
  2. plus every spell with a `SpellEffect` row of `Effect` 252 (teleport) and `ImplicitTarget` 9
     (the bind point), in either target slot;
  3. plus 222695 (Dalaran) and 171253 (Garrison), by id;
  4. minus `EXCLUDED`, by id: Astral Recall 556, and the test and placeholder teleports 1, 3, 70195,
     307896, 1223998, 49493 and 188816.

  Rule 2's header adds "that a toy or an item casts", but the tool does not filter on that clause.
  Rule 4 already removes "the teleports home no item casts" by id, and three shipped ids (191329,
  431644, 1286909) have no `ItemEffect` row of their own. Only this reading reproduces the
  2026-10-28 list, so it is the one coded. Instead, every candidate carries a note of who casts it:
  a toy, an item, a spell an item casts, or nobody. A candidate that no item casts is the case the
  clause was meant to keep out, and it is ruled as one.
- **The three buff rules** come from the header of `defaults/BuffSeeds.lua`:
  1. `buffs`: every spell whose enUS name matches one of `BUFF_CATALOG`'s patterns in full (case
     ignored) and that has a `SpellEffect` row putting an aura on a unit (`Effect` 6, 35, 65 or 128),
     at any `DifficultyID`. Each candidate's notes name its catalog entry and its `EffectAura` types.
  2. `wellfed`: every aura spell named "Well Fed", or one word and "Well Fed" (*Hearty Well Fed*), or
     *Well Fed & Inspired*.
  3. `food`: the Consumable (`Item.ClassID` 0) subclass holding the most items whose use spell
     (`ItemEffect` through `ItemXItemEffect`) is named *Food*, *Drink*, *Refreshment* or *Food &
     Drink*. The counts for every class and subclass are kept in `candidates.json` and `DIFF.md`.

  The sentinel gate needs 15366 (*Songflower Serenade*) and 22888 (*Rallying Cry of the
  Dragonslayer*) on Retail, 1229741 (*Camp Benefits*) and 460940 (*Might of Stormwind*) on WoW
  Forever, and 19705 (*Well Fed*) on both. A build with no eating Consumable also stops the run.
  **A new buff joins through the catalog.** Add its name to `BUFF_CATALOG`, re-derive, then rule
  every id it brings. An id is never written into the file by hand.
- **What "accept" means for a buff.** Accept an aura that changes the player's stats, damage or
  healing, and that comes from outside the player's own kit and gear: a world, zone, camp, shrine,
  faire or event buff. An id whose client data carries only a dummy aura (4) is accepted when its
  name is a known buff. WoW Forever's 1.x world buffs are like this, because the server applies
  their stats. Whether a buff can still be had on today's realm is not in the DB2, and it does not
  decide the ruling: matching an id that never appears costs nothing. Reject an aura that changes
  no stat (*WHEE!*'s experience and reputation), a size aura named like Well Fed, and a trigger.
  When the source is not clear, reject with `needs owner review: <why>`.
- **What "accept" means for Well Fed and food.** Accept a buff food's aura. Accept the derived
  Food & Drink subclass. Its replacement removes the old value as an `unfit` flag, and `apply`
  refuses a removal that has no accepted replacement.
- **Precedent, in this order, never re-litigated:**
  1. a ruling already in the flavor's rulings file;
  2. the seed file's own header:
     - Scrolls of Recall and the other consumables and items that send a player home on the
       hearthstone's cooldown are **kept** (DPS Race's owner call, 2026-10-28);
     - the class spell Astral Recall 556 is **left out** (a player can add it);
     - the Forever dummy seed is **EMPTY BY DECISION** (spec §5);
     - an ignore seed is an auto-repeat attack, whose every swing fires `UNIT_SPELLCAST_SUCCEEDED`;
  3. DPS Race's 2026-11-15 run (`DpsRace/docs/seed-research/2026-11-15-retail/`, read-only), and
     `modules/LateIgnore.lua` (8690 stands for every hearthstone).
- **What "accept" means for a hearthstone.** Accept a spell that a player casts from a toy or an item
  and that sends them to their bind point or to a fixed home, on the hearthstone's cooldown. The
  late-cast ignore list's 8690 entry stands for every id in the list, so a wrong accept stops a late
  cast of that spell from flagging a race.
- **What to reject.** Test, placeholder and `[DNT]` spells; a teleport no item casts, unless it is
  on the hearthstone's cooldown (rule 1); a class spell; every `dummies:<id>`. When the data is not
  clear, reject with `needs owner review: <why>`.
- **The fix policy (owner, 2026-11-25).** Apply every mismatch the evidence supports, judgment calls
  included. Each one cites its evidence in its ruling, gets a smoke row, and is listed in the
  bundle's `ANALYSIS.md` under *Judgment calls applied*. Two things stay as they are: an owner
  ruling already recorded here, and a candidate that the data cannot decide.
- **Flags.**
  - `unnamed`: the build's `SpellName` has no row for the id.
  - `renamed`: the build's name disagrees with the file's name for the id (the comment beside a
    hearthstone, or the header's name for an ignore seed). If it is the same spell, fix the comment
    by hand and rule `keep`. If the id was reused, rule `remove`.
  - `unfit`: the id is named, but the list's rules no longer derive it (hearthstones, buffs and Well
    Fed). For food, the shipped `foodSubclass` is not the derived one.
- **Evidence.**
  - The bundle's `raw/*.csv.gz`, the wago.tools exports, pinned by `?build=`.
  - `candidates.json`, whose notes name the rule or rules that derived each id and who casts it.
  - For `forever`, `SOURCES.md`'s ForeverDB section.
- **ForeverDB is GPL-3.0.** Its rows never enter this repository, test fixtures included (the tests
  use an invented database in its shape, with ids from 900000 up). A bundle keeps the following and
  nothing else:
  - the tag, its commit, each file's sha256, the URLs, the version of the owner's install and the
    dev-copilot commit of the helper;
  - per-id verdicts, each an id plus the one field compared (a creature's name).

  A replay re-fetches the pinned tag, which is immutable, through the helper.
- **Privacy.** No player name, realm or GUID goes into a bundle, a ruling or a commit.

## Flavor: retail

### Status

```sh
python3 tools/seeds/seeds.py status --flavor retail
```

Prints `CURRENT <build> (<bundle>)`, or `NEW <build> (last ruled <build>, <bundle>)`. It compares the
newest live, non-background-download `wow` build with the newest `*-retail` bundle.

### Freeze and derive

```sh
python3 tools/seeds/seeds.py derive --flavor retail --bundle docs/seed-research/<date>-retail --date <date> --build <build>
```

- It pins `<build>` (without `--build`, the newest live `wow` build) and fetches seven tables (about
  85 MB) into the git-ignored `tools/seeds/.cache/`.
- It freezes them gzipped (about 13 MB) into the bundle's `raw/`, and writes `SOURCES.md`, `DIFF.md`
  and `candidates.json`.
- `--replay` re-derives from the bundle's own `raw/` with no network, byte for byte. A replay
  rewrites `SOURCES.md` to say so, so run it on a copy of the bundle.
- **If a sentinel gate fails** (8690, 222695 or 171253 for the hearthstones, or one of `## Rules`'
  buff, Well Fed or food sentinels), **stop**. The rules or the tables have moved, and the fix
  belongs in the tool.

Report the shipped and derived counts, the candidate count, the flag count and the unruled count.

### Rule

```sh
python3 tools/seeds/seeds.py check --bundle docs/seed-research/<date>-retail
python3 tools/seeds/seeds.py rule --tsv <scratchpad>/rulings.tsv --bundle docs/seed-research/<date>-retail
```

`check` lists every unruled key and exits 1 while any remains. After `rule`, it must print `OK`. The
TSV holds one `key<TAB>ruling<TAB>reason` line per key.

### Apply

```sh
python3 tools/seeds/seeds.py report --bundle docs/seed-research/<date>-retail --date <date>
python3 tools/seeds/seeds.py apply  --bundle docs/seed-research/<date>-retail --date <date>
```

Run `report` before `apply`, because once an id has been applied a re-derive no longer proposes it.
`apply` refuses while anything is unruled. It does the following:

- inserts accepted hearthstones in ascending order after rule 3's two fixed rows;
- removes hearthstones whose flag was ruled `remove`;
- removes `remove`-ruled ignore seeds from `NS.IgnoreSeeds.Retail` alone;
- inserts accepted buffs and Well Fed auras in ascending order, removes `remove`-ruled ones, and
  writes an accepted Food & Drink subclass, all in `NS.BuffSeeds.Retail` alone;
- keeps the files' CRLF and every other byte.

A second `apply` changes nothing.

### After

- **When the hearthstone list's length changed**, roll the count in the pin test in
  `tests/test_late_ignore.lua`. The settings row's *(all hearthstones, N)* suffix reads the list's
  length at run time, so it needs no edit.
- **When an ignore seed changed**, roll the header of `defaults/IgnoreSeeds.lua` and the ignore-seed
  cases in `tests/test_lane_casts.lua`.
- **Roll the re-validation line** in `defaults/Hearthstones.lua`'s header: the build, the date and
  the bundle.
- **Write the bundle's `ANALYSIS.md` by hand**, in the 2026-11-25 bundle's shape. It covers:
  - what changed between the builds;
  - what was proposed, accepted and rejected, and why;
  - *Judgment calls applied*;
  - what a later run should re-check.
- **Roll the derived line** in `defaults/BuffSeeds.lua`'s header: the build, the date and the bundle.
  When a buff that a test names changes, roll `tests/test_buff_seeds.lua`.
- **Add one smoke check per shipped-data change** to `docs/smoke-tests.md`. A new hearthstone goes
  in the late-cast ignore list section, and a new buff in the Used column's section. A run that
  ships nothing new adds none.

### Stage

`defaults/Hearthstones.lua`, `defaults/IgnoreSeeds.lua`, `defaults/BuffSeeds.lua`, `tools/seeds/retail_rulings.json`,
`docs/seed-research/<date>-retail`, plus any test, smoke, doc or citation edits. Commit message:
`Seeds (retail): re-validated against <build> (<date>)`.

## Flavor: forever

### Status

```sh
python3 "<root>/scripts/foreverdb.py" status
python3 tools/seeds/seeds.py status --flavor forever --foreverdb <foreverdb>
```

The first command prints the newest ForeverDB tag, which fills `<foreverdb>`. The second prints
`CURRENT <build> + ForeverDB <tag> (<bundle>)` or `NEW ...`. The newest `*-forever` bundle is
current only when both its `wowf` build and its ForeverDB tag are the newest, so either one moving
means a run.

### Freeze and derive

```sh
python3 tools/seeds/seeds.py derive --flavor forever --bundle docs/seed-research/<date>-forever --date <date> --build <build> --foreverdb <foreverdb> --foreverdb-script "<root>/scripts/foreverdb.py"
```

- It pins `<build>` (without `--build`, the newest live `wowf` build), fetches `SpellName`,
  `SpellEffect`, `Item`, `ItemEffect` and `ItemXItemEffect` into the cache and freezes them into
  `raw/`.
- It runs `foreverdb.py fetch --tag <foreverdb> --date <date>` and reads the cache folder it prints.
- `--foreverdb-install "<AddOns>/ForeverDB"` passes the helper's `--from-install` and reads the
  owner's installed copy, read-only, under the same checks.
- It writes `SOURCES.md` (with the ForeverDB section), `DIFF.md` and `candidates.json`.
- If a buff, Well Fed or food sentinel gate fails, stop, as for Retail.
- `--replay` reads those tables from `raw/` and the tag recorded in `candidates.json`. It still goes
  through the helper, whose cache answers a pinned tag offline.

### Rule

```sh
python3 tools/seeds/seeds.py check --bundle docs/seed-research/<date>-forever
python3 tools/seeds/seeds.py rule --tsv <scratchpad>/rulings.tsv --bundle docs/seed-research/<date>-forever
```

Every `dummies:<id>` is ruled `reject`, citing EMPTY BY DECISION. Where ForeverDB records a spawn for
the creature, the reason says so: that makes it a candidate for an in-game capture (`/ct dummy
capture`), never for this file. An ignore-seed flag is ruled as under `## Rules`.

### Apply

```sh
python3 tools/seeds/seeds.py report --bundle docs/seed-research/<date>-forever --date <date>
python3 tools/seeds/seeds.py apply  --bundle docs/seed-research/<date>-forever --date <date>
```

`apply` removes `remove`-ruled ignore seeds from `NS.IgnoreSeeds.Forever` alone, and writes the
accepted buffs, Well Fed auras and Food & Drink subclass into `NS.BuffSeeds.Forever` alone. It
refuses any accepted dummy.

### After

- When an ignore seed changed, roll the header of `defaults/IgnoreSeeds.lua` and its pins, as for
  Retail.
- Roll the derived line in `defaults/BuffSeeds.lua`'s header, and `tests/test_buff_seeds.lua` when
  a buff it names changes (Camp Benefits, Might of Stormwind).
- Write `ANALYSIS.md` by hand in the 2026-11-25 shape. It lists the dummy candidates as information
  only: the count, and the ones ForeverDB records a spawn for.
- Add one smoke check per shipped-data change.

### Stage

`defaults/IgnoreSeeds.lua`, `defaults/BuffSeeds.lua`, `tools/seeds/forever_rulings.json`, `docs/seed-research/<date>-forever`,
plus any test, smoke, doc or citation edits. Commit message:
`Seeds (forever): re-validated against <build> + ForeverDB <foreverdb> (<date>)`.

## Gate

```sh
~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua
KA0S_KIT_CLIENT=forever ~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua
~/.claude/dev-copilot/bin/ka0s-bounded luacheck .
python3 -m pytest -q -p no:cacheprovider tools/seeds
```

luacheck must report 0 warnings and 0 errors, and every suite must report 0 failed. Combat Trail is
`Retail · Forever`, so the headless suite runs under both kit profiles (clients-§6), whichever flavor
the run validated. Without pytest, `python3 -m unittest discover -s tools/seeds` runs the same cases.

## Notes

- **The Retail dummy catalog has no DB2 to check against.** The client's `Creature` table holds only
  the creatures the client needs data for, and none of the catalog's ids is among them (DPS Race's
  2026-11-15 run counted 23167 rows on 12.1.5.70783, ids 3 to 276385). A training dummy's name
  reaches the client from the server. The catalog therefore stays measured: a row is added from `/ct
  dummy capture`, never from a DB2. Re-check if a later build's `Creature` export starts carrying
  the dummies.
- **ForeverDB is evidence, not truth.** Its sources are classic-era server dumps merged with Forever
  data. A creature named "dummy" there may not stand in the world on WoW Forever, or may stand under
  another id. That is why the Forever dummy seed stays measured.
- **Bundle size.** A Retail bundle's `raw/` is about 13 MB, most of it `SpellEffect` (7 MB gzipped).
  A Forever bundle's `raw/` is about 1.1 MB: `SpellName`, `SpellEffect`, `Item`, `ItemEffect` and
  `ItemXItemEffect`.
- **Not every eating item is Food & Drink.** Some holiday and quest foods use an Eat or Drink aura
  but are filed as Consumable subclass 8 (*Other*). The 2026-11-25 runs counted 22 such items on WoW
  Forever and 42 on Retail (and 2 of subclass 0), among them Harvest Nectar and the Hallow's End and Winter Veil treats.
  A check by subclass alone lists them, so the Used column's exclusion also asks whether the item's
  use spell is an Eat or Drink aura.
- **A ruling outlives its candidate.** After `apply`, an accepted id stops being proposed. Its
  ruling stays in the file as provenance, which is not an error.
- **The shared helper.** LibKa0s#91 decides whether the build pin, the cache, the bundle and the
  rulings move into a shared helper. Until it does, the tool copies DPS Race's patterns, and through
  them Aura Master's, and imports nothing across repos. The ForeverDB helper is dev-copilot's,
  because the standard makes it the one way to read ForeverDB.
