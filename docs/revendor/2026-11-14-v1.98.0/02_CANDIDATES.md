# 02 Candidates

Sources, in order: `git -C ../LibKa0s log --oneline v1.96.0..v1.98.0`, the `CHANGELOG.md` blocks
`## v1.97.0 — 2026-11-13` and `## v1.98.0 — 2026-11-14`, and the API documents of every major whose
minor moved (`docs/api/Callout/version-1.2-docs.md`, `version-2.3-docs.md`,
`docs/api/Media/version-13.1-docs.md`, `docs/api/Skin/version-18.1.27.9.19.19.1.1.17.4.9-docs.md`,
`docs/api/testkit/version-56-docs.md`, all at `v1.98.0`).

This run is unattended (row C5 of `docs/superpowers/plans/2026-11-13-callout-adoption.md`): there is
no interview and no issue is filed. Candidate 1 is the work row C5 itself names, so it is adopted in
this run's later commits; nothing else is implemented.

## Class A: delivered on the re-vendor alone

- **Media 13: two Callout display faces.** `Ka0s Bebas Neue` and `Ka0s Russo One` join `FONTS`
  (`docs/api/Media/version-13.1-docs.md`); a consumer owes nothing, and a new font file needs a full
  client restart.
- **CalloutSettings 2: the font row leads with the call-out's faces** (`version-2.3-docs.md:47-65`,
  `FONT_FACES`): "Skin font", "Game default", Oxanium Bold, Bebas Neue, Russo One, then the rest.
  Combat Trail's Callout reaches it once the settings section is drawn (candidate 1).
- **SkinDefsOthers 9**: `__FACE_SIZES` rows for both faces; no skin draws them.
- **Kit 56**: the glyph face list gains both faces; the safe set is unchanged at 117.

## Class B: host change required

### 1. The Callout's settings on the host's write route (Callout 2, CalloutSettings 3): adopt, as row C5

- **What.** `d.path` / `d.set` / `d.colorEncode` on the descriptor send every instance write through
  `NS.SetByPath`; `SchemaRows("callout.")` registers the settings as schema rows (so
  `/ct get|set|list|reset` and the boot check reach them); `BuildSettings` / `SettingsTabs` draw
  those rows on the host's route. Evidence: `version-2.3-docs.md:20-45` (*What changed at this
  version*), `:199-203` (the descriptor), `:276-310` (*The schema rows*), `:312-331` (the Options
  build on the route), `:394-444` (*Adopting it*).
- **Files it would touch.** `core/CalloutSetup.lua`, `modules/Countdown.lua` (the descriptor),
  `settings/Schema.lua` (the rows and `writeThrough`), the AceDB defaults, `settings/Race.lua` (the
  section), the countdown and settings suites, and the docs.
- **Recommendation: adopt.** It is the conforming route (`architecture-§5`) the v1.96.0 adoption
  was blocked on (plan row C2, *Blocked*).
- **Blast radius: additive.** Nothing the host ships is deleted: the section's "no settings yet"
  text is replaced, and existing `profile.callout` data reads the same (a stored array color is read
  in either shape, `version-2.3-docs.md:37`).

## Class C: whole-module adoption

Nothing new. `Role` (offered in the v1.96.0 bundle, unreached, recommended not now), `Glow`, `Item`
and `IconBrowser` did not move a minor in v1.96.0..v1.98.0, so they are not re-offered.
