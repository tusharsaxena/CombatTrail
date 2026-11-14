# 02 Candidates

Sources, in order: `git -C ../LibKa0s log --oneline v1.98.0..v1.100.0`, the `CHANGELOG.md` blocks
`## v1.99.0 — 2026-11-14` and `## v1.100.0 — 2026-11-14`, and the API documents of every major whose
minor moved (`docs/api/Callout/version-3.4-docs.md`,
`docs/api/Options/version-38.5.45.3.7.2.9.17.3.1.4.19.13.7.5.8.7.11.1.1.4-docs.md`,
`docs/api/DebugLog/version-22.10.1.4-docs.md`, `docs/api/WaypointArrow/version-1.1-docs.md`, all at
`v1.100.0`).

This run is unattended (row C11 of `docs/superpowers/plans/2026-11-13-callout-adoption.md`): there is
no interview and no issue is filed. Candidates 1 to 3 are the work row C11 names, decided by the
owner for this row; everything else is listed and left.

## Class A: delivered on the re-vendor alone

- **The glow as AuraMaster's draws** (Callout 3, `version-3.4-docs.md:62-103`): a stored `"soft"`,
  `"strong"` or `"off"` reads through `GLOW_LEGACY` as the same halo, with no host change.
- **Text to speech words aligned** (`:48-50`): `PAUSE` says "Pause", `LAST_TEN` "Ten seconds".
- **"Countdown 10 to 1" in Text to play** (`:146`, CalloutSettings 4): reaches the section wherever
  it is drawn.
- **DebugLogDiagnostics 10**: the report's `LibKa0s running:` line names WaypointArrow.
- **The six new packs' bytes** arrive with the copy; the declaration (decided) keeps them.

## Class B: host change required

### 1. The one tab (`SettingsTab`, `SchemaRows(prefix, { texts = false })`, CalloutSettings 4; OptionsNav 7's `SideTabs`): adopt, row C11

- **Evidence.** `version-3.4-docs.md:124-152` (*the section as one tab*), `:419-447` (*The one tab*),
  `:631-636` (the settings page's call), `:651-669` (the stub).
- **Files.** `settings/Race.lua`, `locales/enUS_Race.lua`, `settings/OptionsSetup.lua` (the stub's
  `SideTabs`), `tests/test_callout_settings.lua`, `tests/test_countdown.lua`, the docs.
- **Recommendation: adopt** (the owner's decision: one "Callout" tab replacing the three; the stock
  texts and mutes are the addon's to control).
- **Blast radius: replaces.** The three host tabs and their 46 text and mute rows go; a test pinning a
  stored own text (C9's FAILED case) moves.

### 2. The glow rows and `Callout:MigrateGlow` (Callout 3): adopt, row C11

- **Evidence.** `:69-78` (the keys), `:95-103` and `:109` (`MigrateGlow`, "A host on the route calls
  it on its stored call-out table before its Schema's boot check"), `:120-122` (what a host owes).
- **Files.** `core/Database.lua` (a per-profile migration step), `tests/test_migrations.lua` or the
  callout suites, `docs/schema.md`, `docs/profiles.md`.
- **Recommendation: adopt.** The glow row is now a `bool`; a stored string fails the boot check.
- **Blast radius: additive** (a new step; the rows arrive with `SchemaRows`).

### 3. Eight packs, Arena John the default (Callout 3): adopt, row C11

- **Evidence.** `:20-46`, `:575-577`. Decided: the sounds line lists all eight, `NS.CALLOUT_PACKS`
  matches; landed in the re-vendor commit (the suite holds the list to the line).
- **Blast radius: additive.** A profile that stored a voice keeps it; an unset one reads Arena John.

## Class C: whole-module adoption

### 4. `LibKa0s-WaypointArrow-1.0` (v1.99.0): not adopted, listed

- A waypoint arrow toward a map point or world position (`docs/api/WaypointArrow/version-1.1-docs.md`).
  Combat Trail has no navigation target: it times fights and races on a dummy the player already
  stands at. No candidate premise; the orchestrator's instruction is to adopt nothing else and file
  nothing. Its files ship whole with the payload (no declaration governs them).

## Not candidates

- **`Set("glow", "off" | "soft" | "strong")`** (`:55-60`): a v1.98.0 caller's write; this host never
  writes the glow itself.
- **The three-tab `SettingsTabs`** stays in the library as before; the host leaves it (candidate 1).
