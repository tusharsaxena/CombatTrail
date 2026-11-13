# Scope — Ka0s Combat Trail

What the addon is for, and what it deliberately leaves out (documentation-§3, Tier 1). The design is
the spec (`superpowers/specs/2026-11-10-combat-trail-design.md`, §1 and §2).

## What it does

- **The trail.** The player's and the pet's casts as icons sliding along two lanes, with GCD ticks,
  a "now" line, interrupt marks and a glow on long cooldowns. Every visual element is configurable per
  lane, on top of the skin.
- **The live HUD.** A DPS window on every fight: the clock, the target line, damage and DPS (the pet's
  beside them), a pace bar against the best fight on the same board, a damage chart and the top spells.
  After the fight, a card with the final figures, the shares, a New best chip and the save status.
- **The history.** Every fight that passes the recording filters, stored account-wide with its
  spells, casts, gear, stats, talents and usage; the Results window lists, filters, groups and
  compares them, with an ability timeline and a gear view. Fights are purged after a number of days,
  except those that hold a best.
- **Both clients.** Retail and WoW Forever from one codebase, with the features a client cannot have
  absent there.

## What it deliberately does not do

| Not done | Why |
|---|---|
| Read the combat log | `COMBAT_LOG_EVENT_UNFILTERED` is protected for addons on both clients; every number comes from `C_DamageMeter` |
| Live percentages, sorting, or a live "ahead by" number on the HUD | In combat the meter's values are secret: an addon may copy them into a widget but not do arithmetic or comparisons on them |
| Keep a stored fight's damage chart past the session | The chart's samples are secret in combat and are never persisted |
| Lanes for target, focus or party members | v0.1.0 has the Player and Pet lanes only; more lanes are issue #1 |
| Create new lanes | The lane picker selects between the two fixed lanes |
| Other players' damage (group or raid meters) | A personal tool; Details and Blizzard's meter already do this |
| Import CastTrail's settings | CastTrail was a throwaway; Combat Trail starts from its own defaults |
| Masque support | The icons use the addon's skins only |
| Race against a timer or arm a run | That is DPS Race; Combat Trail records real fights with no arming |
