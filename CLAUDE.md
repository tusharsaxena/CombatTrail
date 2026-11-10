# CLAUDE.md — Ka0s Combat Trail

**Ka0s WoW addon.** Adheres to the **Ka0s WoW Addon Standard** —
https://github.com/tusharsaxena/WowAddonStandards

## Standards compliance (read first)

This repo is built to the **Ka0s WoW Addon Standard** (URL above). All development here — features,
refactors, doc changes — MUST conform to it. The standard is the source of truth for layout, TOC
shape, the Ace substrate, schema-driven settings, slash/prefix conventions, locales, Compat,
tests/lint, and doc structure.

**If a change would deviate from the standard, STOP and flag the deviation explicitly.** Do not
silently deviate and do not silently "fix" to match. Surface it and let the user decide which of
two things it is:

1. **An accepted deviation** — this addon intentionally differs; record it as a row in
   `docs/ARCHITECTURE.md` -> `## Documented deviations`, shaped
   `| Rule | What differs | Why | Decided | Re-check trigger |`, where Rule is the `filename-§N`
   reference. That register is the single home: the reasoning may live in the issue-audit GitHub
   issue or an audit bundle and the row cites it, but a deviation not in the register is not ratified.
2. **A change to the standard itself** — the standard's definition should evolve; the update
   belongs upstream in the WowAddonStandards repo, after which this addon conforms to the new rule.

When in doubt, treat standard conformance as a hard requirement and ask.

Start here, then read the docs:

- **`docs/ARCHITECTURE.md`** — the hub: the module map, the per-client feature table, the bus
  messages, the event wiring per state, the secret-value invariants, the Documentation map and the
  deviation register. **`docs/module-map.md`** lists every file and the load order.
- **`docs/testing.md`** — how to verify: both kit profiles, lint, complexity, the commit gate.
- **`docs/smoke-tests.md`** — the in-game suite and the `/kct probe` steps the owner runs.
- Then the topic docs the hub's Documentation map lists: `docs/scope.md`, `docs/schema.md`,
  `docs/settings-panel.md`, `docs/data-flow.md`, `docs/common-tasks.md`, `docs/slash-dispatch.md`,
  `docs/compat-layer.md`, `docs/profiles.md`, `docs/debug.md`, `docs/known-limitations.md`,
  `docs/midnight-quirks.md` and `docs/performance.md`.
- **`docs/superpowers/specs/2026-11-10-combat-trail-design.md`** — the v0.1.0 design: Player and Pet
  cast lanes, the live DPS HUD and the fight history. Damage comes only from `C_DamageMeter`, and a
  secret value is only ever copied into a C-side widget, never inspected (spec §3).
- **`docs/superpowers/plans/2026-11-10-combat-trail-v0.1.0.md`** — the build plan and its status
  ledger. A resumed session continues from the first row that is not `done`.

Green gate before every commit: `lua tests/run.lua`, `KA0S_KIT_CLIENT=forever lua tests/run.lua` (the
addon serves Retail and WoW Forever, so the suite runs under both kit profiles, clients-§6) and
`~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` (0/0; the kit bounds the suite on load, and
`luacheck` loads no kit, so it runs through the bounded runner, testing-§15). Never
auto-stage/commit/push and never bump the version without an explicit instruction.

This addon vendors **[LibKa0s](https://github.com/tusharsaxena/LibKa0s)** into `libs/LibKa0s/` and
its test kit into `tests/_kit/`, both copied whole from the tag below (`git -C ../LibKa0s archive
v1.94.0`, commit 5e71662d117feb7a5c572a3b3e7c7e780e06c0d7), with `libs/LibKa0s/media/icons/` pruned
to the declaration by the tag's own `tools/prune-icons.lua`. **Never edit anything under `libs/` or
`tests/_kit/`**: a library problem is filed on LibKa0s and re-vendored back, because the next
re-vendor silently reverts a local edit. The Ace3, LibSharedMedia, LibDataBroker and LibDBIcon copies
are Panel Master's (the set that loads on both clients).

Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.94.0 (MIT).
LibKa0s icons: arrow-left, chart, chat, chevron-down, chevron-left, chevron-right, chevron-up, clear, close, confirm, copy, export, eye, flag, info, lock, move, ph:check, ph:flag, ph:ghost, ph:paw-print, ph:skull, ph:trophy, ph:x, reset, settings, sort-down, sort-up, unlock, volume-high.

The first of those two lines is the **provenance line**: `tests/test_vendor_sync.lua` reads it and
compares both vendored payloads against that tag in the sibling checkout, so it moves in the same
commit as the vendored bytes. The second is the **icon declaration** (`library-stack-§7`): the same
gate holds `libs/LibKa0s/media/icons/` to exactly those names. They are the marks the library draws
for this addon (the debug console's copy, clear and close, the skin picker's settings gear and eye,
and the small marks beside skinned controls) plus the ones the HUD and the Results window draw as
they arrive from DPS Race, and the paw on pet spell rows.
