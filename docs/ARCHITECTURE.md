# Ka0s Combat Trail — architecture

This page is the engineer-context hub. It is a stub until the docs task of the v0.1.0 plan (Task 5.3)
writes the module map, the per-client feature table, the bus messages, the event wiring per state and
the secret-value invariants. Until then the design is
[`superpowers/specs/2026-11-10-combat-trail-design.md`](superpowers/specs/2026-11-10-combat-trail-design.md)
and the build order is
[`superpowers/plans/2026-11-10-combat-trail-v0.1.0.md`](superpowers/plans/2026-11-10-combat-trail-v0.1.0.md).

## Documented deviations

| Rule | What differs | Why | Decided | Re-check trigger |
|---|---|---|---|---|

None. This addon follows the Ka0s WoW Addon Standard at the pinned revision with no ratified
deviation.

### Files over the 1500-line cap

`layout-§1` caps every **authored** `.lua` file this repository tracks at 1500 lines, `tests/`
included, with vendored code (`libs/`, `tests/_kit/`) the only carve-out that reaches anything here.
Nothing here is generated non-shipping data, so `tests/run.lua` sets no `Kit.layoutCap`. A file over
the cap has three terminal states and no others: peeled, an open issue naming the seam a peel would
follow, or a ratified row in the register above carrying a re-check trigger. The kit's gate,
`tests/_kit/test_layout_cap.lua`, reads this census from here.

**Nothing is over the cap today.** Measure it with

```
git ls-files '*.lua' | grep -v '^libs/' | grep -v '^tests/_kit/' | xargs wc -l | sort -rn
```
