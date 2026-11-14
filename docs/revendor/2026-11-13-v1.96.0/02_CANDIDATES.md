# 02 Candidates

Sources, in order: `git -C ../LibKa0s log --oneline v1.94.0..v1.96.0`, the `CHANGELOG.md` blocks
`## v1.95.0 — 2026-11-10` and `## v1.96.0 — 2026-11-13` (lines 13-108 of the tag's file), and the
API documents of every major whose minor moved (`docs/api/Callout/version-1.1-docs.md`,
`docs/api/Role/version-1-docs.md`, `docs/api/Launcher/version-10-docs.md`,
`docs/api/DebugLog/version-22.9.1.4-docs.md`, `docs/api/testkit/version-55-docs.md`, all at
`v1.96.0`).

This run is unattended (run plan row C1): there is no interview, nothing is implemented and no issue
is filed. The candidates are listed for the orchestrator; adopting the Callout is row C2.

## Class A: delivered on the re-vendor alone

- **Launcher 10.** `lib.New`'s descriptor checks move to `checkDescriptor`, same messages at the
  host's line (`docs/api/Launcher/version-10-docs.md:19-27`). `core/LauncherSetup.lua` owes nothing.
- **DebugLogDiagnostics 9.** The `/ct debug` report's `LibKa0s running:` line names Role and
  Callout where the client has them (`docs/api/DebugLog/version-22.9.1.4-docs.md`, *What changed at
  this version*). Today Combat Trail's winning copy carries both majors, so the line lists them.
- **Kit 55.** The vendored-payload gate now holds `media/sounds/` to the `LibKa0s sounds:` line
  (`docs/api/testkit/version-55-docs.md`, *What changed*); kit 54's `client_globals.lua` CCN split is
  behavior-neutral. `tests/test_vendor_sync.lua` uses the default pairs, so nothing is owed.

## Class C: whole-module adoption

### 1. `LibKa0s-Callout-1.0` (Callout 1, CalloutSettings 1): adopt, as row C2

- **What.** A center-screen call-out with a countdown read from a shared `endsAt`
  (`math.ceil(endsAt - GetTime())`, read on the frame), stock texts, voice packs or in-game TTS, and
  a settings section (`BuildSettings` / `SettingsTabs`). Evidence: `version-1.1-docs.md:37-63`
  (*What this major is*, *Timing*, *Sound*), `:140-153` (*The descriptor*, `addon`, `skin`,
  `packs`, `db`, `debug`), `:256-283` (the packs and the sound declaration), `:284-312`
  (*Adopting it*, whose sketch is Combat Trail's race countdown), `:313-340` (the degradation stub).
  CHANGELOG `## v1.96.0`, *The Callout major (L3)* and *The settings section (L4)*.
- **Files it would touch.** `modules/Countdown.lua` (411 lines, ported from DPS Race: the cue's
  sounds, the centered number and the buzzer's raid warning), the race clock that owns `endsAt`, the
  settings schema and page for the Countdown section, `core/` for a `CalloutSetup.lua` seam and its
  stub, the TOC (no change: `LibKa0s.xml` already loads the files), AceDB defaults
  (`profile.callout`), locales for host strings, and the suites that pin the countdown today
  (`tests/test_countdown.lua` and the race suites).
- **Recommendation: adopt.** The owner's design for this run (plan *Design*, *The module*) built
  the major for this addon's race countdown; the shared `endsAt` removes the timer-chain drift the
  current port carries. Pass `packs = { "callout/female-kathleen", "callout/male-joe" }` to match
  the `LibKa0s sounds:` line this commit writes, `addon = "CombatTrail"`, and call `Suspend` /
  `Resume` on the addon's stand-down. Do not depend on the Orbitron, Bebas Neue or Russo One faces:
  they are not in v1.96.0 (CHANGELOG `## v1.96.0`, the versions paragraph, plan row L2 blocked).
- **Blast radius: replaces.** It deletes the host-owned centered number and its sound sequencing in
  `modules/Countdown.lua` and rewires the race onto a library seam, so the existing countdown suites
  must be characterized first (the shown number per second, what sounds when, the buzzer once, the
  cancel path) and rewritten to the same assertions against the instance.

### 2. `LibKa0s-Role-1.0` (Role 1, new in v1.95.0): not recommended now

- **What.** The player's spec and role on Retail and WoW Forever: `Spec()`, `SpecsForClass`,
  `Groups()` (Forever's talent groups), `Resolve(store)` with a player override
  (`docs/api/Role/version-1-docs.md:41-48`, `:54-62`, `:138-146`).
- **Files it would touch.** `core/Compat.lua` (its own `Compat.TalentTrees()` / `TalentApis()`
  reads Forever's talent tabs and C_Traits groups as the stand-in for a spec, `core/Compat.lua:195-405`
  onward), `modules/Identity.lua` and `modules/Probe.lua`, which consume them.
- **Recommendation: not now.** Combat Trail records the player's spec on a fight; it does not decide
  anything by role, and it has no role override to offer. Its talent reader also routes every value
  through `NS.Secrets` (the file's *SECRETS* note) and dumps the raw answers for `/ct probe`, which
  `Role.Groups()` does not expose. Re-check if the addon ever needs a role (a per-role best, or a
  role filter on the History page).
- **Blast radius: replaces** `Compat.TalentTrees` and the probe's talent dump.

### Not new in this range

`Glow`, `Item` and `IconBrowser` have no lookup either (01_DELTA 3e), but none moved a minor in
v1.94.0..v1.96.0, so they are not re-offered here.
