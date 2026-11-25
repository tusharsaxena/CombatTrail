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
