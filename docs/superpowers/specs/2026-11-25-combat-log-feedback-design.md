# Combat Log feedback (owner, 2026-11-25)

- **The feedback:** the owner's first in-game pass over the merged Combat Log (#11, spec
  `2026-11-25-log-level-buffs-design.md`, the v2 addendum), with screenshots 72 to 84. The 20 items are
  restated below in the owner's numbering, and their words are quoted where the wording matters.
- **Branch:** `feat/2026-11-25-combat-log-feedback`, built in the scratch clone
  `~/ka0s-scratch/ctfb/CombatTrail`. The live repo is left alone.
- **Plan:** `docs/superpowers/plans/2026-11-25-combat-log-feedback.md`.
- **Clients:** both.
- **Precedence:** anything this spec doesn't change stays as the v2 addendum has it. Where they
  disagree, this spec wins.

## The owner's answers (asked before the build)

| Question | Answer |
|---|---|
| Item 3: Source and Target removed where? | **Everywhere:** the live log (docked and detached) and the Results fight log. |
| Item 5: the reset | **Pull to next pull.** The log clears at the pull and keeps the pre-pull floor (lines a few seconds before the pull, with negative times, such as buffs that are up at the pull). It keeps adding lines after combat until the next pull clears it. |
| Item 12: sizing | **Static, one window.** The DPS HUD and the docked log are one window. Its height never moves during or after a fight. It changes only when the log opens or closes, or when the player resizes it. |
| Item 19: the Timeline | **Footer button only.** The Results detail has no tabs. Log is a foldable section under Targets, open by default. |

## The items

1. **The log is shown by default.** In a new profile, `log.drawer.shown` defaults to `true`. Existing
   profiles keep what they stored.
2. **The default size is the owner's Forever profile.** `hud.width` defaults to **390** (it was 260).
   The default height follows item 16. A stored width is kept.
3. **No Source or Target columns.** They are removed from the table component, from every home, from
   the settings (any column toggle for them goes, along with its schema row, through a schema step),
   from the docs and from the tests.
   - The remaining columns are Time, Event, Spell / School and Amount, plus Info where that home has
     it.
   - The docked minimum width drops by the two columns' share. The builder measures it, and the
     default stays 390.
   - A saved line's `u` field stays in the data, because Results' chips (Pet) and the colours still
     use it. It is just not a column any more.
4. **A HEAL row is not Physical.** UNIT_COMBAT's HEAL reports school 1 (or nil), which the table
   draws as Physical. A HEAL row's Spell / School cell reads **Healing**, in the heal colour, and
   names a school only when the client reports one other than Physical. The builder confirms against
   the code why it reads Physical today, and fixes it at the capture or the view, whichever is the real
   cause. A test covers it.
5. **The log resets at every pull.** At FIGHT_STARTED, the live view (docked and detached) clears and
   shows only the new fight, from its pre-pull floor onward. The pre-pull floor is lines a few seconds
   before the pull, and its length is today's setting. Lines keep arriving after combat ends, until the
   next pull clears them. No line from an earlier fight is ever shown in the live view. The saved log
   on the fight record is unchanged.
6. **A scrollbar**, the same one Spell breakdown uses (look and behaviour), on the live log in both
   homes and on the Results log section. The scrollbar replaces any other way to see older rows; the
   mouse wheel scrolls as it does in Spell breakdown.
7. **The graph disappears after the fight.** Mid-fight, Damage profile shows the pace bar and the
   chart. After the fight, only the bar is left. Find the cause first (bisect or trace, no guessing).
   The likely cause is that the HUD's height budget squeezes the chart to nothing once the "Not saved"
   line appears with the log drawer open, but confirm it. Then fix it so the chart stays after the fight
   in every state:
   - saved or not;
   - log open or closed;
   - docked or detached.

   Item 12's static layout should make the problem impossible. Add a test that pins the chart's height
   after the fight ends.
8. **Every column is centered**, in the header and the cells, in every home.
9. **The filter chips are shown by default** in the live log (`log.show.chips`, or whatever key holds
   them, defaults to on).
10. **No fight-started or fight-ended rows.** The PULL and END boundary lines are gone from every view,
    live and Results. They are not captured as lines and not saved. Old saved logs that still contain
    them are filtered out at read time. The pull is still time 0.0. The line cap no longer counts
    boundaries.
11. **Detach has two states.** **Docked**: inside the Combat Trail window, at the bottom. **Detached**:
    a standalone window with its own saved position and size.
    - The third state (attached to the HUD, following it, with pin and unpin, side and match-HUD) is
      removed. That includes its keys (`log.window.attached`, `pinned`, `side`, `matchHud` and any
      that serve only it, through a schema step), its controls, its slash verbs, its docs and its
      tests.
    - The Race window layout code that kept the attached log apart from the Race window is simplified
      to match.
    - `/ct log detach` and `/ct log dock` remain.
12. **One window, static sizes.** The DPS HUD and the docked log are one frame, laid out top to bottom:
    - the title bar;
    - the timer and target;
    - the KPI cards;
    - one reserved status line (the "Not saved…" line, kept even when empty);
    - Damage profile (the pace bar and the chart, at a fixed height);
    - Spell breakdown (fixed rows, scrolling);
    - Combat Log (fixed rows, scrolling; item 18);
    - the footer.

    The height is the sum of those sections, so nothing inside a fight changes it. It changes only when:
    - the log opens or closes (from the header button);
    - the player changes the rows settings;
    - the player drag-resizes the window, if the HUD has a resize grip today. The extra height goes to
      the log's rows and the width to every section.

    The Race window's matched height follows the one height. The old `sizeMode` and auto-grow paths
    that made the HUD jump around are removed or pinned to this rule, and the builder records which.
13. **A better icon for the Combat Log header button.** The current one reads as chat. Use a
    list or log glyph from LibKa0s's icon sets, such as Phosphor `list-bullets`, `scroll` or `article`,
    declared on the `LibKa0s icons:` line and pruned as the repo does it.
14. **No fold chevron** on the log's section header. The title-bar button alone opens and closes the
    log. The fold-to-one-line strip and its key (`log.drawer.collapsed`) are removed, through a
    schema step.
15. **`/ct lock` and `/ct unlock` no longer move the lanes.** A new verb, `/ct lanes lock|unlock`
    (with `toggle`), locks and unlocks the lanes alone. `/ct lock|unlock` covers the HUD and the
    windows. The help text, the slash docs and the tests follow. If the lanes have a settings row for
    their lock, it uses its own key. A schema step carries the current value across, so nobody's lanes
    unlock by surprise.
16. **The default height shows 5 Spell breakdown bars and 10 log rows.** `hud.bars` defaults to 5 (it
    already does, so check it), and the docked log's rows default to **10**. With item 12, the default
    window is 390 wide and exactly tall enough for those.
17. **The log header's icons** (the eye and the download arrow) take the same colour, size and hover
    as the window title bar's icons.
18. **Combat Log is a section like Damage profile and Spell breakdown:**
    - the same gold title font and size ("Combat Log");
    - the same right-aligned dim meta text ("8 shown"), followed by the item 17 icons;
    - the same spacing;
    - no separator line or accent seam above it.
19. **The Results detail has no tabs.**
    - The Overview, Timeline and Log tab strip is removed.
    - The detail is one scrolling page: today's Overview sections, then **Log** as a foldable section
      header under **Targets**, with the same chevron and gold look as Spell breakdown and the others,
      **open by default**.
    - Inside the Log section is today's Log tab content: the chips with counts, and the table with
      Time, Event, Spell / School, Amount and Info.
    - The Timeline is reached through the footer's Timeline button only, as today. A CAST row's click
      still opens it at that cast.
20. **No duplicate spell list.** "Damage by spell" in the Results log is a copy of Overview's Spell
    breakdown. It is removed, and its code goes too if nothing else uses it. Only Overview's Spell
    breakdown remains.

## Tests, docs, smoke

- **A headless case for every item:**
  - the defaults (1, 2, 9, 16);
  - the columns (3, 8);
  - the HEAL school (4);
  - the reset (5);
  - the scroll (6);
  - the chart after the fight (7);
  - no boundary lines (10);
  - two detach states (11);
  - the static height across a whole fight (12);
  - the icon declaration (13);
  - no fold (14);
  - the lanes verb (15);
  - the section look (18);
  - the tabless detail and the Log section (19);
  - no Damage by spell (20).
- **Schema steps** for every removed or moved key, each with a test.
- **Docs:** README, ARCHITECTURE, settings-panel.md, the slash docs, module map, data-flow and the test
  inventory. Every doc that describes the old behaviour is corrected.
- **Smoke:** new rows in `docs/smoke-tests.md` for each owner-visible item, unrun. The rows they
  supersede are amended and lose their pass marks.

## Calls made without asking

| Item | Call |
|---|---|
| 2 | Only the default width changes. The owner's own stored 390 stays as it is. |
| 3 | The `u` field stays in saved lines, because the Pet chip and the colours need it. |
| 10 | Old saved logs keep their boundary lines on disk. They are filtered out at read time, not rewritten. |
| 12 | The status line's space is always reserved, so the "Not saved" line can't push the chart. |
| 14 | The fold strip goes with the chevron, because the title-bar button already hides the whole log. |
| 15 | `/ct lanes toggle` is added beside lock and unlock, matching other verbs. |
