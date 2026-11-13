# Known limitations — Ka0s Combat Trail

What v0.1.0 (Race mode included) cannot do, or does not yet know (documentation-§3, Tier 2). Each line says why. Items
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
  double counting. *Unverified* in combat. On WoW Forever, out of combat, the pet's source came back
  empty and the player's list held no pet spells (midnight-quirks.md): the pet's damage is most likely
  folded into the player's, and fights since show it is: the pet's rows sit in the player's source,
  each named by `creatureName` (midnight-quirks.md), and are split out by that name. While in combat
  the Pet figure reads a dash there, because summing the pet's secret rows is not allowed.
- **Targets are read after combat, by name.** The fight detail's Targets section (issue #6) comes
  from the meter's EnemyDamageTaken view, which is secret in combat, so the HUD never shows it.
  Enemies of one name are one row (the meter keys them by creature ID), at most ten are kept, and
  a fight stored before this version has none. Solo, the rows sum to your own damage; whether a
  group fight's row counts only yours is not measured.
- **A meter reset mid-fight loses the fight.** It is marked lost and not stored, and the rest of that
  combat is not tracked. A plain fight is never netted against a session the meter already held;
  only a race is (ruling X3: flagged `sharedSession`, its score less what the session held at the
  arm), and its HUD then draws no pace and no chart.
- **Nothing after the settle is read.** Damage that lands more than the settle window after combat
  ends (a long DoT tail on a dummy) is not in the record.

## WoW Forever

- **In-combat behavior is unverified.** The 2026-11-10 probe (build 70862) ran out of combat only:
  whether the meter's values, cast spell IDs and the pet's GUID are secret in combat there is assumed
  to match Retail until the probe reports.
- **No built-in training dummies.** No dummy creature ID has been measured, so a dummy fight reads as
  open world until the player adds the dummy to their own list (History > Training dummies, or
  `/ct dummy add` on the target).
- **The talent tree stands in for a spec.** WoW Forever answers one class-wide spec, so the tree
  with the most points is the fight's spec (v0.2 plan A4). The probe (build 70862, out of combat)
  found the trees in C_Traits' trait groups, with the talent-tab API absent (midnight-quirks.md);
  whether the config, tree or group IDs or a group's points read secret in combat is not measured.
  A tree read sealed in combat (any of those) keeps the session's last plain read, primed at login
  and every stand-up and refreshed by every out-of-combat read, so a respec followed by a pull
  before any out-of-combat read could file that fight under the old tree.
- **The sample history is 21 fights**, because the Retail-only boards are absent.
- **Spell and item IDs in the sample rotation are unverified** in game.

## Design limits of v0.1.0

- **Two lanes only**, Player and Pet (target, focus and party lanes are issue #1). The Insights tab
  (issue #2) came with Race mode.
- **The retention settings are per profile while the store is global**, and the 500-fight cap is
  enforced when the purge runs, not on each save.
- **Your own training dummies are per profile, and a fight's content is decided when it is saved.**
  Adding a creature to the list (or switching a built-in off) changes what the next fight on it is;
  a fight stored before keeps the content it was saved with. A built-in cannot be given another
  category, only switched off. A creature whose GUID arrives secret has no creature ID, so it is never
  a dummy (both clients).
- **The HUD has no Pin control in its title bar** (the icon catalog has none); `/ct hud pin` pins
  it. The fade hides at once, the pace bar has no ahead or behind color, and the best line is solid.
- **Results:** the detail ships collapsed, there are no `results.*` look keys for the table (its bars
  are the palette's blue, with no class-color option), and the Delta column measures against the
  group's best, while the board's best (whatever the filters) shows only in that cell's tooltip,
  the detail and the compare: the list has no Status column (owner, 2026-11-10).
- **The Results window is wider since v0.2.** The Used and Note columns raise the list's
  least width to 972 px (1412 expanded, with the 440 px detail beside it). The window opens at that
  least (owner, 2026-11-11); drag its corner wider to give the Character column's header drag room. On a small screen
  or a large UI scale, lower History → Results window → Scale. A width a profile stored before is
  held to the new least.
- **The compare's "Trinkets and consumables" list has no cap.** Each item used by either fight adds
  a 22 px line (`Compare.USAGE_ROW_H`), so a fight with many consumables makes a tall window that
  relies on being clamped to the screen and can run past it on a small one.
- **By ability icons do not stack.** A lane is 16 px, so casts closer than an icon overlap there and
  only the one on top takes the pointer. At 1x a filler cast every global cooldown reads as a run of
  icons; zoom in to part them, or switch the lanes to *Ticks*.
- **The sim's "short" scenario is 10 s**, judged by the player's own minimum length: with a minimum of
  10 s or less it is saved and its label no longer holds.
- **Outside an encounter, the live pace can use a different board than the saved fight.** The HUD
  paces against the board of the target held at the pull, while the record is filed on the enemy
  that took the most damage. Pull an add and kill the pack leader, and the live view and the over
  card can disagree about a best. Encounters key both on the encounter, so they agree.
- **Two lanes overlapping at the same frame level mix their icons**; the Frame level tooltip says how
  to separate them.
- **The lanes' skin-following defaults** change their look under Ka0s Default (a gold label, a black
  icon border, the skin's glow and background); the owner rules on these at the smoke test.

## Race mode (Retail)

- **A race is read on Combat Trail's settle, not DPS Race's quiet.** The fight owns the read, so a race
  is read 4 s after combat ends at the earliest (the grace), against DPS Race's 2.5 s of quiet (ruling
  X5); *Stop Now* reads at once.
- **A race's score is the session's merged total, the pet's damage included,** so the record's damage
  and the race agree; DPS Race scored the player's own row, so a pet class races higher here.
- **A race ends at the first combat end before the buzzer,** even when Combat Trail's grace carries
  the fight on (Feign Death): the race is incomplete at that moment while the fight's own record runs
  longer (ruling X4).
- **The late-cast judge works by spell ID.** A late cast whose spell ID is sealed always counts, and a
  sealed success is taken as no press only while Auto Shot or Shoot is repeating.
- **A race resumed after a `/reload` keeps no casts, usage or chart from before it.** The race's own
  fields are in `db.global.pendingRaces` from its first hit, so `Race.Resume` carries it on, but the
  casts (and so the cooldowns and the late-cast judge while the loading screen was up), the usage
  snapshot and the chart's samples were in memory. A race read after the reload is flagged
  `reloaded` past its buzzer; one whose combat ended unseen is incomplete at the resume, its real
  combat end unknowable. A resume after a restart of the machine takes its clock from the stored date.
  The HUD goes live on the resumed fight, paced on its race board, from the resume on.
- **A `/reload` mid-fight still drops a plain fight.** Only a race is written before its read; a
  fight in memory is gone with the reload and the rest of that combat is not tracked (the race's
  `Fight.Adopt` seam could carry plain fights too; not done).
- **The late-cast ignore list is per profile while the store is account-wide,** as the Training
  dummies list is: a profile switch re-scores every saved race by the other profile's list.
- **Auto-show and auto-arm see only the training dummies Combat Trail knows** (the built-ins and your
  own list), and with enemy nameplates off only your target counts: a dummy across the room opens
  nothing until you target it. A nameplate that came up in combat with a sealed GUID is counted at the
  next rescan (the debounced hide's), not when it came.
- **Race mode is Retail only.** WoW Forever has no Race mode page, `/ct race` verb, Race window,
  countdown, race toast or race filter (clients-§4); a race saved on Retail lists there as a fight
  with its race DPS.
- **No launcher entry for the Race window** (ruling X17). The minimap menu is LibKa0s-Launcher's
  fixed set. Its key, *Toggle Race window*, is Retail's alone, in `Bindings_Mainline.xml` (a
  documented deviation); that WoW Forever reads `Bindings.xml` and never lists it waits for the
  owner's in-game check (SM-CT-RM58). `/ct race show`, `toggle` and `arm` work in a macro, and the DPS
  HUD's title bar has a Race button.
- **An incomplete race whose fight carries on keeps the whole fight's total as its score** (ruling
  X16): no meter read is taken at the early combat end, where secrecy is unproven, so its DPS divides
  that total by the fight's race-clock length (first hit to fight end). Incomplete races never count
  on a board, so this only sets the figure shown.
- **A race on a shared session that the meter splits mid-race scores the fresh session only.** The
  race keeps its clock (its record runs from the pull's combat entry, its first hit the race's), but the
  damage and the casts before the split stay with the shared session's fight, and the chart's steps
  before the split are empty.
- **A race whose fight is parked by a new pull waits for that pull's read.** A pull past Combat Trail's
  grace while the race's fight still settles parks it (modules/Fight.lua), and Fight reads parked fights
  with the next settle. The new pull's combat end, death and casts are never the race's.
- **A race's chart, like a fight's, lasts one session.** The race clock shift on the chart and the
  Timeline (ruling X9) reads the part's `firstHit`; a race saved before that field reads as 0, with no
  shift.
- **Race mode off stops new races only.** An armed race is canceled with the switch (or a profile
  that has it off), but one already running when it goes off runs on to its result; the switch never
  touches a saved race.
- **The Race window never says ahead or behind in words during a race.** The race's live damage is a
  secret value: the Race window shows it beside the best's figures (Best by now's *Current*, and your
  reading in each Checkpoint, the DPS HUD's last read) as text and on a thin mini pace bar, which the
  client fills against the best's figure there, so the green or red is where the fill ends. Nothing
  in Lua compares it, so there is no mark, chip or difference figure (the owner's choice, 2026-11-13).
  Best by now and the Checkpoints are the best's straight line at the clock, and a checkpoint shows as
  passed because the clock reached it, not because the damage did. The full live pace is the DPS HUD's
  pace bar.
- **A best saved without a player-only figure paces a pet class on the whole total.** On Retail, where
  the pet has a meter source of its own, the live figure is the player's alone, so the mini pace bars
  set it against the best's player-only line. A best whose record has no player figure has no such
  line, and the bars fall back to its whole figure.
- **A checkpoint passed before a `/reload` shows a dash for your figure.** Its reading was held in
  memory for that race alone, so a resumed race keeps the best's figure there but not yours.
- **The Race window matches the DPS HUD's height only on the left or right.** Above or below the HUD
  it keeps its own height, and it is never shorter than its tallest screen needs, so a HUD shrunk below
  that leaves the Race window taller than the HUD.
