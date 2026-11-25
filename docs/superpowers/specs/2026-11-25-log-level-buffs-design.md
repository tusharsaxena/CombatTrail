# Combat log window, target level and buffs in Used (CombatTrail #11, #12, #13)

On 2026-11-25 the owner asked for these three issues to be built in one run. Their answers to the questions asked before the
build:
- **#11:** a live feed in combat, then the fight log after it. Each fight's log is saved with the fight.
- **#12:** the level is always shown, on bosses too.

The owner's mockup is https://claude.ai/artifact/8ZYCiAp9t3MGQ8jgo6G6wg. Placeholders in it are written in brackets.

## #12 — the target level in the Encounter column

- **The Encounter column.** It renders `<name> (L<level>)` from `ident.targetLevel`, which `modules/Identity.lua` already
  stores. A skull level (`-1`, or the client's skull convention) reads `(L??)`, tinted the way the client tints a skull
  (red). A boss also shows the suffix (owner). A fight with no stored level, such as an older record or an unknown target,
  shows the name alone, never `(Lnil)` or a blank suffix.
- **Sorting.** The column sorts by name, then by level.
- **Width, tooltip and detail title.** These follow the column: the detail title reads `<name> · level <n>`, or
  `level ??` for a skull. The Targets tab and the Insights tab use the same name rendering where they show a target.
  Use one formatter for all of them.
- **Clients.** Retail and Forever. Add headless cases for each form.

## #13 — buffs in the Used column, and no plain food

This is the issue as written, including its owner comment of 2026-11-17. Read issue #13 in full on GitHub with
`gh issue view 13 -R tusharsaxena/CombatTrail`.

- **Seed research first.** Build per-client candidate lists from wago.tools DB2, pinned with `?build=` to the builds the
  2026-11-25 seeds run used: wow 12.1.5.70961 and wowf 1.60.1.71091.
  - The lists cover world buffs, camp and zone benefits, shrines, Darkmoon-style buffs, and seasonal or event buffs that
    change stats.
  - Camp Benefits (spell 1229741) and Might of Stormwind are Forever anchors.
  - Every spell is ruled in or out as data.
  - The research is frozen in `docs/seed-research/2026-11-25-{retail,forever}/` bundles.
  - The seeds go in a new `defaults/BuffSeeds.lua`, modelled on `defaults/IgnoreSeeds.lua` and `defaults/Hearthstones.lua`,
    with one list per client picked once (clients-§5).
- **The validate-seeds contract.** CombatTrail's `docs/validate-seeds.md` gains this seed with a Flavor section per client,
  and a gate test checks the shipped data against the recorded rulings. CombatTrail adopted the contract in the
  2026-11-25 run (SF-CT-01); extend it, don't recreate it.
- **The behaviour.** The fight-start aura walk also matches the active client's list.
  - A match is recorded as `src = "buff"` under its spell id. That is a spell-keyed Used entry kind, so the record schema
    changes: the schema version goes up, with a migration test, and older records still render.
  - The Used column and the detail list show these with the spell's icon and name.
  - Usage Edit and "never show" apply to them. Hidden spells are stored beside hidden items.
  - It stays secret-safe: a sealed aura ends the walk and never produces an entry.
- **Plain food and drink are excluded.** Food & Drink that only restores health or mana (`C_Item.GetItemInfoInstant`
  class Consumable, the per-client subclass) is never listed, whether the signal is the start aura, a pre-pull cast or a
  bag-count drop.
  - Buff food is listed only through Well Fed (`Usage.WELL_FED_SPELLS`), and stat drinks only through their buff, never
    through the Eat or Drink aura.
  - The per-client subclass ids and Well Fed spells are folded into the seed research.
  - Tests: plain food eaten at the pull lists nothing; Well Fed lists the food once; a potion is unchanged.

## #11 — the Combat Log window

**What it can read.** Neither client lets an addon read the real combat log:
- Forever forbids registering `COMBAT_LOG_EVENT_UNFILTERED` (docs/forever-quirks.md; never register it, on either
  client).
- Retail 12.x seals combat data.

So the log is built only from sources the addon may read:
- **Casts:** your casts and your pet's, from the cast tracking the lanes already use (`modules/Casts.lua` and related).
  This is not a new event source.
- **Auras:** gained and lost on you (`player`) and on your target (`target`), through `UNIT_AURA` with its update info,
  using the addon's existing aura-reading helpers. They are secret-safe: a sealed aura's name or id is never guessed. It
  is either skipped or shown as the client gives it, which is a display-only path.
- **Hits and heals on you:** `UNIT_COMBAT` for `player`, if the client provides it. Probe it through the existing
  `SafeRegisterEvent` path and record the result in the quirks docs. Amounts that are secret in combat are shown as given
  (FontString display) and are never compared, counted or stored as numbers. A sealed amount is stored as "sealed".
- **Fight boundaries:** the start, combat end, and the target's death if the addon already knows it.
- **After combat:** damage by spell from `Meter.ReadFinal`. It is read plain, player and pet, the same read the record
  uses; reuse the record's own spell breakdown and don't read the meter twice.

**The live window** (mockup board 1):
- A Combat Trail standalone window, separate from the HUD and Results, following standalone-windows: skin, lock, saved
  position and size, close on Escape where the others do.
- The title shows the current target and the fight clock.
- Filter chips: Casts, Buffs, Debuffs, Hits on you, Heals on you, Pet. They filter what is shown, never what is saved.
- The view follows the newest line. Scrolling up pauses following; the pause button resumes it.
- The footer shows the line count.
- **Ways in:** `/ct log` (in help and the slash docs), a button on the HUD or the Results window following the existing
  header-button pattern (one place, your call, recorded), and a settings toggle to open it automatically when combat
  starts (default off).

**The saved fight log** (owner: saved with each fight; mockup board 2):
- The fight record gains `log`, a compact array of entries:
  `{ t = <seconds from start, 0.1 s>, k = <kind code>, id = <spell id or nil>, u = <unit code>, a = <plain amount or nil or "s" for sealed> }`.
  Names and icons are resolved at display time from the spell id. Store no strings when an id serves.
- **Capping.** It is capped at `C.LOG.MAX_PER_FIGHT` (default 400; a setting from 100 to 1000). When the cap is reached,
  only the newest lines are kept, and the fight records how many were dropped.
- **Retention.** It is trimmed with the fight by the existing retention, and older fights without `log` render without
  it. This counts as a record-shape change, so the schema moves (together with #13's change, as one bump or two
  successive steps, your call) and gets a migration test.
- **SavedVariables budget.** Measure the bytes per fight at the cap. If the addon has a stored-size budget or perf
  ceiling (docs/performance.md), update it with the measurement and justify it.
- **The view.** After combat, the live window becomes the fight view:
  - the header shows the fight's target and level (#12's formatter), date, duration and DPS;
  - Older and Newer step through saved fights;
  - the same chips, plus Search (lead's call);
  - a Damage by spell side panel, with bars, from the record.
- The Results fight detail gains a **Log** button beside Timeline that opens the window on that fight. It is disabled,
  with a tooltip, for a fight with no log.

**Settings** (a Combat Log group on the right existing settings page, or its own page if the schema conventions call for
one):
- open automatically in combat (off);
- the categories saved (all on);
- lines kept per fight (400);
- font size;
- background opacity;
- lock.

Every row has a schema entry, a default and a settings-panel.md entry.

**Performance.** Event handlers in combat do constant work per event: append to a ring buffer and mark the window dirty.
The window repaints at most every `C.LOG.REPAINT` (0.1 s), and only while it is shown. Nothing allocates per event
beyond the entry table. Add a perf scenario that drives a busy fight through the kit and checks the ceilings.

## Docs, locales, tests and gate

- **Docs:**
  - README: the features, `/ct log` and the Used buffs.
  - `docs/schema.md`, `docs/settings-panel.md`, `docs/slash-dispatch.md` (or the repo's equivalent),
    `docs/ARCHITECTURE.md` and the module map.
  - `docs/test-cases.md` and `docs/smoke-tests.md`: new rows for each issue.
  - `docs/performance.md`.
  - The quirks docs: the `UNIT_COMBAT` probe result, marked assumed until the owner probes it.
- **Locales:** every new string in enUS.
- **Gate:** the CLAUDE.md gate on both kit profiles, plus the seed tests.

## Non-goals

- Any use of `COMBAT_LOG_EVENT_UNFILTERED`.
- Logging other players' events.
- Exporting a log as text, unless it falls out of the existing Share feature cheaply (your call, recorded).

## Addendum: v2 design, approved (owner, 2026-11-25)

The owner approved the v2 mockup, the "v2 · Part of Combat Trail" page of https://claude.ai/artifact/8ZYCiAp9t3MGQ8jgo6G6wg
("Mock ups look good"), and added requirements. **This addendum replaces the window design in "#11" above.** Capture,
storage, cap and retention stay as above.

### One log component, three homes, all feeling like Combat Trail
- **A: docked in the DPS HUD (the default).**
  - A log button in the HUD title bar toggles a Log drawer under the spell rows, at the HUD's width, in its skin, with an
    accent seam.
  - The drawer is part of the HUD: it hides and fades with it, and it never shows while the HUD is hidden.
  - **Collapsible (owner):** the drawer header collapses it to a one-line strip that shows the newest event, and expands it
    again. The state is saved.
  - Its **row count** is a setting (owner: "configure how many log events to show at a time"), 3–20, default 8. The HUD
    grows by the drawer's height.
- **B: detached companion window.**
  - The drawer's detach button moves the log into a standalone companion window, titled "Combat Trail · Log", wider, with
    an Info column.
  - It still follows the HUD, shown and hidden with it the way the Race window follows it (`RaceWindow.FollowHud`), unless
    pinned.
  - A dock button sends it back. Docked or detached is saved, and so is the window's position and size.
  - Its row count is its own setting (or fills the window's height: your call, recorded).
- **C: the Results fight detail.**
  - The detail gets tabs: Overview (what it shows today), Timeline (today's Timeline content moves into a tab, or keeps
    its window with the tab as an entry point: your call, recorded) and **Log**.
  - The Log tab shows the fight's saved log in the same table, with counts on the chips, a Damage by spell panel using
    the HUD's own bar colours and order, and a click on a cast row that jumps the Timeline to that cast.
  - A fight saved before this change shows "No log was saved for this fight".

### The table (the same component in all three homes)
- **Columns:** Time · Event · Source · Target · Spell/School · Amount, plus Info when there's room (wide companion
  window, Results). Columns can be shown or hidden in settings; Time and Event always show.
- **Events:** CAST, BUFF+, BUFF−, DEBUFF+, DEBUFF−, HIT, HEAL, DIES.
  - For HIT and HEAL on you, the client gives no source or spell: Source reads "—", and Spell/School shows the school.
    Critical and glancing go in Info, and a critical is also bold with ★.
- **Colours** (mockup board D), each a skin token with a Ka0s Default value; reuse the HUD's class and pet colours, don't
  copy them.
  - **Who:** "You" is always bold in the player's class colour. The pet uses the HUD pet colour, hostile units red, and
    friendly units blue or their class colour.
  - **Events:** a CAST row is plain, with a faint gold wash for a long-cooldown cast. BUFF± is green (− dimmed).
    DEBUFF+ has an orange tag and row wash (DEBUFF− dimmed, no wash). HIT has a red wash and a red amount. HEAL is green
    with "+".
  - **Spell names** are in their school's colour.
  - **Colour-blind safety:** events also differ by tag text and wash, never by hue alone. There's a setting to turn off
    school colouring and row washes.
- **Sort (owner):** the default is **newest at the top**. The sort can be switched (newest first or oldest first, saved),
  in settings and from a click on the Time header. Following means "keep the newest in view" in either order.
  Scrolling away from the newest pauses following, and a "Resume" control brings it back.
- **Throttle (owner):** a setting for how fast new rows are shown in the live views: Instant, or at most 1 row every N ms
  (50–1000, default 0 = instant), plus a batch mode that paints queued rows together each repaint tick. Throttling only
  affects display. Capture and storage are never throttled or dropped by it.

### The Race window on Retail (owner)
The Race window is the HUD's companion on Retail (RaceWindow follows the HUD). The docked drawer makes the HUD taller,
and a detached log adds a second companion.
- **Re-anchoring.** Re-anchor and, where the Race window sizes from the HUD, resize it so nothing overlaps: wherever the
  Race window anchors relative to the HUD, it uses the HUD's full height including the drawer, and it follows
  collapse and expand.
- **Two companions.** The detached log and the Race window must not overlap. Give them a default layout (for example,
  the Race window on one side and the log on the other, or stacked) and make it adjustable.
- **Testing.** Cover race-armed and racing states, with the drawer expanded, collapsed and detached, on the Retail kit
  profile. On Forever there is no Race window (the race is Retail-only), so nothing changes there.

### Settings (owner: "plenty of config options")
A **Combat Log** settings page, following the addon's schema conventions; every row has a default and a
settings-panel.md entry.
- **Enable:** enable the Combat Log; open the HUD's log drawer automatically in combat (on); where it lives (docked,
  detached).
- **Docked drawer:** collapsed or expanded; rows shown (8); collapsed strip shows the newest event (on).
- **Detached window:** rows shown, or fill the window; pinned (stays up when the HUD hides); lock; scale; background
  opacity.
- **Order and display:** sort order (newest first); throttle (instant / every N ms / batch); font size; row height or
  density; time format (from pull, or clock time); show the Info column; column visibility.
- **What to show** (the default filter chips; all on): casts (yours, and your pet's as its own switch), buffs on you,
  debuffs on you, debuffs you apply on your target, buffs on your target, hits taken, heals taken, deaths. Also: hide
  auto attacks (Auto Shot, Shoot); a minimum amount to show for hits and heals.
- **Colours:** school colours on or off; row washes on or off; the "You" colour (class colour, or a custom one); hostile
  and friendly colours (skin tokens, with overrides).
- **Storage:** save a log with each fight (on); lines kept per fight (400, 100–1000); which categories are saved
  (separate from the display filter).
- **Results:** the Log tab's default chips; jump to the Timeline on clicking a cast (on).

### Plan impact
- **CL-11b** builds the shared table component, the docked drawer (collapse and rows), the detached companion
  (dock/detach and HUD-follow) and the Race window re-anchoring.
- **CL-11c** builds the Results Overview/Timeline/Log tabs, the Combat Log settings page with every row above, then the
  docs, smoke rows and the full gate.
- Work too big for one item can be split into CL-11b2 and CL-11c2 commits; record the split in the plan file.
