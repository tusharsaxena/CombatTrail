# Analysis — Retail seed validation, 2026-11-25 (build 12.1.5.70961)

This is Combat Trail's first run of `tools/seeds/seeds.py` under its contract, `docs/validate-seeds.md`.
That contract supersedes DPS Race's.

- **Build.** The live Retail build on wago.tools (product `wow`, 12.1.5.70961), the newest live,
  non-background-download build that the builds API listed on 2026-11-25. The run pinned it with
  `?build=`.
- **What it re-derives.** `defaults/Hearthstones.lua`, by the four rules in the file's header.
- **What it checks.** `defaults/IgnoreSeeds.lua`'s `Retail` lists.
- **Rulings.** Each one is in `tools/seeds/retail_rulings.json`, and `RULINGS.md` lists it with its
  reason.

The last run was DPS Race's 2026-11-15 run on 12.1.5.70783 (`DpsRace/docs/seed-research/2026-11-15-retail/`).
Combat Trail ported that hearthstone list unchanged from DPS Race @f8078c7.

## What changed in the game between the builds

Nothing that touches the lists:

| Check | 12.1.5.70783 (DPS Race, 2026-11-15) | 12.1.5.70961 |
| --- | --- | --- |
| Rule 1 (ChargeCategory 2309) | 44 spells | 44 spells |
| Rule 2 (Effect 252, ImplicitTarget 9) | 63 spells | 63 spells |
| Derived after rules 3 and 4 | 58 | 58, the same ids |
| Shipped hearthstones the build does not name | 1 (`1310840`) | the same 1 |
| Shipped hearthstones whose name disagrees with the comment | 0 | 0 |
| Shipped hearthstones the rules no longer derive (named) | 0 | 0 |
| Sentinel gate (8690, 222695, 171253) | pass | pass |
| Ignore seeds (6603 Auto Attack, 75 Auto Shot, 5019 Shoot) | not checked | all three named as the header says |

`--replay` on a copy of this bundle reproduces `candidates.json` byte for byte from `raw/`.

## What the run proposed

It proposed no candidates and raised 1 flag.

### The flag: `1310840`, kept

`1310840` ships as *Wood-Cursed Hearthstone*, but live 12.1.5.70961 has no `SpellName` row for it, as
neither 12.1.5.70783 nor 12.1.5.70575 did. The Retail PTR, `wowt` 12.1.7.71087, settles it. A
scratch read of that build's `SpellName` and `SpellCategories`, which this bundle did not freeze,
found:

- `SpellName` names the id *Wood-Cursed Hearthstone*;
- `SpellCategories` gives it `ChargeCategory` 2309, which is rule 1.

So it is a real hearthstone that arrives with 12.1.7. The likeliest history (DPS Race's analysis) is
that the 2026-10-28 run read an unpinned export, which serves the PTR.

The ruling is **keep**. The data decides this one, so it is not a judgment call. Until 12.1.7 ships,
no cast on the live client carries the id, so the entry is inert. Once 12.1.7 is live, the flag
stops being raised.

## The ignore seeds

`NS.IgnoreSeeds.Retail` is `player = { 6603, 75, 5019 }, pet = { 6603 }`. All three ids exist on the
build, under the names the header gives them (Auto Attack, Auto Shot, Shoot). The list is curated
rather than derived, so the run proposed no candidates for it.

## The dummy catalog: not checkable

`defaults/Dummies.lua` is measured, so it takes no candidates. The client's `Creature` export holds
none of the catalog's ids, so an existence or name check would have nothing to read (`## Notes` in
the contract). The tool reads no `Creature` table.

## Changes applied

The run changed no data. `apply` ran and changed nothing. In `defaults/Hearthstones.lua`, two things
changed by hand, comments only:

- its refresh recipe now points at the contract;
- it gains a re-validation line.

The 59 rows, the pin test and the smoke checks are unchanged.

## Judgment calls applied

None.

## What a later run should re-check

- **`1310840` once 12.1.7 is live.** The flag should stop being raised. If it still is, read the
  live `SpellName` again before ruling.
- **New bind-point teleports with no item behind them.** These are the case rule 2's item clause
  was meant to keep out. Read the `no item casts it` note and the spell's name. Reject test, `[DNT]`
  and `[PH]` spells, and class spells.
- **Rule 1's charge category.** If 8690 leaves ChargeCategory 2309, the sentinel gate still passes
  on rule 2, but much of the list would turn `unfit`. Read the flags before ruling.
- **`Creature` coverage.** If a later export carries the training dummies, the Retail catalog could
  gain an existence and name check.
