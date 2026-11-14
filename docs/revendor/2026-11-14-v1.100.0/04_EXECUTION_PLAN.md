# 04 Execution plan

Each commit: `lua tests/run.lua`, `KA0S_KIT_CLIENT=forever lua tests/run.lua` and
`~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` green first.

1. **Re-vendor commit.** Both payloads at v1.100.0, the provenance, icon and sounds lines and the
   vendor paragraph in `CLAUDE.md`, the prune, `NS.CALLOUT_PACKS` at eight, `NS.CalloutStub` gaining
   `SettingsTab` and `GetGlowColor`, the three suite pins (eight voices and the default, the shipped
   pack's path, the row count with the glow keys), the README credits for every shipped pack and
   `DEPENDENCIES.md`, this bundle.
2. **The one tab** (candidate 1). Characterization first: `tests/test_callout_settings.lua` asserts
   the page's strip is `Race,callout,Late-cast ignore list,Race window`, the one tab's build is
   `layout = "side"` with Preview and the Look and Sound side tabs, no `callout.texts.*` or
   `callout.muted.*` row, `/ct get|set` refusing them, the glow rows reachable by `/ct set|get|reset`.
   Then `settings/Race.lua` (`SchemaRows(prefix, { page, texts = false })`, every row grouped under
   `callout`, `SettingsTab` as one host tab labeled "Callout"), the locale words dropped, the Helpers
   stub's `SideTabs`. The C9 case pinning a stored own FAILED text moves to the stock word with
   the mute and own text gone.
3. **The migration** (candidate 2). Red first: a stored profile with `glow = "strong"` (and one not
   active) reads `glow = true`, 0.7, 5 after the runner; `"off"` reads false; `"soft"` the defaults;
   stored `texts` and `muted` gone; a stored voice kept; a fresh profile's voice Arena John. Then
   `core/Database.lua` step 3 (`perProfile`).
4. **Docs.** `docs/schema.md`, `docs/profiles.md`, `docs/settings-panel.md`, `docs/ARCHITECTURE.md`,
   `docs/known-limitations.md`, `docs/smoke-tests.md` (RM81 to RM86 and new rows), README,
   `docs/test-cases.md` regenerated, the plan ledger's row C11.
