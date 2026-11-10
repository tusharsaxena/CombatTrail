# Known limitations — Ka0s Combat Trail

What v0.1.0 cannot do, or does not yet know (documentation-§3, Tier 2). Each line says why. Items
marked *unverified* wait for the owner's in-game checks in [`smoke-tests.md`](smoke-tests.md), and the
owner's open decisions are listed in the plan's *Owner decisions*.

## Imposed by the client

- **No live percentages, sorting or delta on the HUD.** The meter's numbers are secret in combat. The
  HUD copies them into StatusBars and secret-safe text, and the pace bar sets the live fill against
  the paced fight's damage at the same second; it never reads back which is larger.
- **A stored fight's damage chart lasts one session.** The chart's samples are the meter's in-combat
  totals, secret when taken, so they live in memory (`modules/Slices.lua`) and are gone after a reload
  or logout. The rest of the record is the after-combat plain read and is kept.
- **No combat log.** `COMBAT_LOG_EVENT_UNFILTERED` is protected for addons on both clients, so nothing
  a combat log would give (damage taken, per-target damage in combat, absorbs) is read.
- **A secret castGUID costs the dedupe and some interrupt marks.** While castGUIDs are secret, the lane
  cannot match a cast's START to its end, so an off-GCD instant cast closes the cast in flight and a
  later interrupt of that cast is not marked.
- **A secret spell ID skips the ignore list.** The icon still shows (the texture is copied), but an
  ignored spell whose ID arrives secret is not filtered.

## Rests on the meter

- **One fight is one meter session.** If the meter does not split at `ENCOUNTER_START` mid-combat,
  the trash before the boss is part of the boss fight. *Unverified* on both clients.
- **The pet is its own source.** `Meter.PET_SEPARATE = true` assumes the meter reports the pet beside
  the player and that the player's total does not already hold the pet's damage. The probe cannot see
  double counting. *Unverified* in combat, and on WoW Forever entirely.
- **A meter reset mid-fight loses the fight.** It is marked lost and not stored, and the rest of that
  combat is not tracked. DPS Race's shared-session netting is not ported.
- **Nothing after the settle is read.** Damage that lands more than the settle window after combat
  ends (a long DoT tail on a dummy) is not in the record.

## WoW Forever

- **In-combat behavior is unverified.** The 2026-11-10 probe (build 70862) ran out of combat only:
  whether the meter's values, cast spell IDs and the pet's GUID are secret in combat there is assumed
  to match Retail until the probe reports.
- **No training dummies.** No dummy creature ID has been measured, so a dummy fight reads as open
  world.
- **No specs.** The Spec column, dropdown and grouping are absent; bests group by character and
  board only.
- **The sample history is 21 fights**, because the Retail-only boards are absent.
- **Spell and item IDs in the sample rotation are unverified** in game.

## Design limits of v0.1.0

- **Two lanes only**, Player and Pet (target, focus and party lanes are issue #1), and no Insights
  tab (issue #2).
- **The retention settings are per profile while the store is global**, and the 500-fight cap is
  enforced when the purge runs, not on each save.
- **The HUD has no Pin control in its title bar** (the icon catalog has none); `/ct hud pin` pins
  it. The fade hides at once, the pace bar has no ahead or behind color, and the best line is solid.
- **Results:** the detail ships collapsed, there are no `results.*` look keys for the table, and the
  Delta column measures against the group's best.
- **The sim's "short" scenario is 22 s**, judged by the player's own minimum length: with a minimum of
  22 s or less it is saved and its label no longer holds.
- **Outside an encounter, the live pace can use a different board than the saved fight.** The HUD
  paces against the board of the target held at the pull, while the record is filed on the enemy
  that took the most damage. Pull an add and kill the pack leader, and the live view and the over
  card can disagree about a best. Encounters key both on the encounter, so they agree.
- **Two lanes overlapping at the same frame level mix their icons**; the Frame level tooltip says how
  to separate them.
- **The lanes' skin-following defaults** change their look under Ka0s Default (a gold label, a black
  icon border, the skin's glow and background); the owner rules on these at the smoke test.
