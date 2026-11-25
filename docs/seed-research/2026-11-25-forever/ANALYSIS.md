# Analysis — WoW Forever seed validation, 2026-11-25 (build 1.60.1.71091 + ForeverDB v2026.11.24.46)

This is Combat Trail's first `forever` run of `tools/seeds/seeds.py` under its contract,
`docs/validate-seeds.md`.

- **Build.** The live WoW Forever build on wago.tools (product `wowf`, 1.60.1.71091), the newest live,
  non-background-download build that the builds API listed on 2026-11-25. The run pinned it with
  `?build=`.
- **What it checks.**
  - `defaults/IgnoreSeeds.lua`'s `Forever` lists, against that build's `SpellName`.
  - The ForeverDB evidence for `defaults/Dummies.lua`'s `Forever` seed, which is EMPTY BY DECISION.
- **ForeverDB.** The run read tag `v2026.11.24.46` (commit `6e0a34b4…`) through dev-copilot's
  `scripts/foreverdb.py`. The cache matched both GitHub and the owner's install, version
  2026.11.24.46. `SOURCES.md` records each file's sha256. No ForeverDB row is kept here.
- **Rulings.** Each one is in `tools/seeds/forever_rulings.json`, and `RULINGS.md` lists it with its
  reason.

`--replay` on a copy of this bundle reproduces `candidates.json` byte for byte.

## What the run proposed

It proposed 84 dummy candidates (information only) and raised 1 ignore-seed flag.

### The flag: `6603` is "Attack" on WoW Forever, kept

`NS.IgnoreSeeds.Forever` is `player = { 6603, 75, 5019 }, pet = { 6603 }`. All three ids exist on the
build. Spell 6603 is named *Attack* there, its 1.x name, while the header calls it *Auto Attack*,
Retail's name for it. It is the same auto-attack swing, so the id is right on both clients.

The ruling is **keep**. Following the contract's rule for a renamed spell, the comment was fixed by
hand: the header of `defaults/IgnoreSeeds.lua` now notes Forever's name. The shipped ids are
unchanged. 75 (*Auto Shot*) and 5019 (*Shoot*) carry the header's names.

### The dummy candidates: 84, all rejected

ForeverDB's `npc` table holds 84 creatures whose name contains the word "dummy". Each is a candidate
`dummies:<id>`, and every one is ruled **reject**. The reason is the repo's own recorded ruling:
`defaults/Dummies.lua` says Forever is EMPTY BY DECISION, and a Forever dummy row comes only from a
measurement in game. `seeds.py` takes no other ruling for a dummy, and `apply` never writes the
file.

For information:

- **81 of the 84 have no spawn in ForeverDB's `spm`.** Most of them are test, placeholder or
  summoned creatures. Their names, which are in `RULINGS.md`, run to *Unkillable Test Dummy*,
  *Outlands Test Dummy Warrior*, *SoD Test Dummy* and the engineering *Target Dummy*.
- **3 have a recorded spawn:** `218019`, `218020` and `218021`, each named *Combat Dummy* and each on
  one map. These are the ones worth a look in game. If the owner meets one, `/ct dummy capture`
  records its id, and only a capture adds it to the seed.

ForeverDB is evidence, not truth. Its sources are classic-era dumps merged with Forever data, so a
spawn recorded there does not prove that the creature stands on today's realm under that id.

## Changes applied

The run changed no data. `apply` ran and changed nothing. One comment was added by hand to the
header of `defaults/IgnoreSeeds.lua`, to record Forever's name for 6603.

## Judgment calls applied

None. The one fix is a comment, ruled under the contract's renamed-spell rule. The dummy rejections
follow an owner ruling already recorded in the repo.

## What a later run should re-check

- **Whether a new ForeverDB tag adds dummy spawns.** Diff the `spawn recorded` notes against this
  bundle's three.
- **The ignore seeds' names** on a new `wowf` build. A rename that is not 6603's *Attack* would be
  new.
- **Whether a measured Forever dummy reaches the seed.** Once one does, it is no longer a candidate,
  and later runs should compare its id against ForeverDB's record.

## Addendum: the buff seeds (CombatTrail #13, CL-13a, the same day)

Later on 2026-11-25, `derive` ran again into this bundle, at the same `wowf` build (1.60.1.71091)
and the same ForeverDB tag, with the tool extended for `defaults/BuffSeeds.lua`. The new file's
three rules are in its header and in the contract's `## Rules`.

- **New tables.** The run froze `SpellEffect`, `Item`, `ItemEffect` and `ItemXItemEffect` beside
  `SpellName` in `raw/`, all pinned with `?build=`.
- **New findings.** It added the buff, Well Fed and food findings to `candidates.json`, `DIFF.md`,
  `SOURCES.md` and `RULINGS.md`.
- **Unchanged.** The ignore-seed and dummy findings above are unchanged, key for key.
- **The helper.** `SOURCES.md` now names the helper's dev-copilot commit as
  `f475b8732e7de0b76bd64d79dad4a0869dd9c27a`. That is the read-only checkout's HEAD, and its
  `scripts/foreverdb.py` is byte-identical to the one at `ab560b3`, the commit the first pass
  recorded. ForeverDB itself is not read by the buff rules.

The file started with empty lists and `foodSubclass = 0`. That way every id, and the subclass, was
a candidate that got a ruling.

### What it proposed and what was ruled

| List | Derived | Accepted | Rejected |
| --- | --- | --- | --- |
| `buffs` | 69 | 55 | 14 |
| `wellfed` | 30 | 30 | 0 |
| `food` | subclass 5 | 5 (the placeholder 0 removed) | – |

- **The issue's anchors.**
  - Camp Benefits 1229741: its client aura is a dummy, and the server applies the benefit.
  - Might of Stormwind 460939, 460940 and 1304678.

  Both are sentinels: a build that stops deriving either one stops the run.
- **Buffs accepted (55):**
  - the 1.x world buffs and their later ids: Songflower Serenade, Warchief's Blessing, Rallying Cry
    of the Dragonslayer, Spirit of Zandalar, the Dire Maul tribute and Sayge's fortunes;
  - the Season of Discovery buffs: Boon of Blackfathom, Ashenvale Rallying Cry, Spark of
    Inspiration, Fervor of the Temple Explorer, Songflower Lullaby, Dreams of Zandalar, Dark
    Fortune of Damage and Might of Blackrock;
  - Blessing of Blackfathom and Traces of Silithyst;
  - the Midsummer and Lunar Festival buffs;
  - Camp Benefits.

  On this client, the 1.x ids carry a dummy aura (4) in the DB2 where the server applies the stats.
  They are kept, because the server may send them.
- **Buffs rejected (14):**
  - Sayge's Dark Fortune 353694: a dummy aura only, a later id whose source the data does not show;
  - Boon of Water, Air, Fire and Earth (8 ids), Brood Boon (5 ids) and Blessing of Neptulon: stat
    auras named like world buffs, whose source the data does not show.

  Every one is ruled *needs owner review*.
- **Well Fed:** all 30 aura spells named *Well Fed* are accepted.
- **Food.** Consumable subclass 5 holds 176 of the 198 Consumable eating items. Dwarven Mild 422,
  Sweet Nectar 1708 and Longjaw Mud Snapper 4592, the issue's examples, are among them. The other 22
  are subclass 8 (*Other*): Harvest Nectar 19997, the Hallow's End treats 20388 to 20390, the
  Winter Veil foods 21238 and 21241, and others.

### Judgment calls applied

- **Dummy-aura ids are accepted by name.** The 1.x world buffs' client data shows only a dummy
  aura, so the stat test cannot read them. They are known world buffs, and an id that never
  appears costs nothing.
- **Unknown-source stat auras are rejected for review**, not accepted. The Boons, Brood Boons and
  Blessing of Neptulon are on the build, but nothing in the data says what grants them.

### For CL-13b

- Food & Drink is subclass 5 on WoW Forever too, so the issue's examples are excluded by subclass.
- The 22 subclass-8 eating items still need the use-spell check.
- `wellFed` holds 30 ids. Usage's 19705 name match stays as the fallback.

### What a later run should re-check (buffs)

- **The *needs owner review* rejections**, once the owner can say where those auras come from (an
  in-game sighting would settle one).
- **New Season-style world buffs** on a new `wowf` build: add their names to `BUFF_CATALOG`.
