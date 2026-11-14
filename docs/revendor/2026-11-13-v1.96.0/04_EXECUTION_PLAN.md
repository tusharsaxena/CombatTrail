# 04 Execution plan

Nothing is implemented in this run. The re-vendor itself is one commit (Step 4), preceded by one
prerequisite commit for a pre-existing gate failure (see 05_SUMMARY).

The Callout adoption is row C2 of `LibKa0s/docs/superpowers/plans/2026-11-13-callout.md`, and its
plan belongs there. The points this bundle hands it:

1. Characterize first: the current countdown's shown number per second, what sounds when, the
   buzzer's STOP once and only when enabled, the cancel at 5 s left, and "switched off, no frame is
   ever built" (today's `countdown:` cases).
2. The descriptor carries `addon = "CombatTrail"`, `skin = "CombatTrail"` and
   `packs = { "callout/female-kathleen", "callout/male-joe" }`, the `LibKa0s sounds:` line.
3. The race clock and the call-out read one `endsAt`.
4. A degradation stub defined before the instance, per `version-1.1-docs.md:313-340`.
5. Fonts: Oxanium (default), the skin font, the game default and LibSharedMedia faces only.
