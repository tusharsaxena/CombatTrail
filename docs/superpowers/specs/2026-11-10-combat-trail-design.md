# Ka0s Combat Trail — v0.1.0 design

- **Date:** 2026-11-10
- **Status:** approved for planning by the owner, 2026-11-10 ("mockup looks good, go ahead")
- **Mockup:** [`2026-11-10-combat-trail-mockup/index.html`](2026-11-10-combat-trail-mockup/index.html)
  (published: https://claude.ai/artifact/CJPSoo9s4m6HaWt3sgzRg7)
- **Repo:** https://github.com/tusharsaxena/CombatTrail, branch `feat/2026-11-10-combat-trail-v0.1.0`
- **Pins** (other agents are editing these repos during this run; read them at these revisions only and
  never write to them): LibKa0s **v1.94.0**, WowAddonStandards **4e94ad1**, DpsRace **045f479**.

Where this document says **(owner)**, the owner decided it. Where it says **(Claude)**, Claude decided it
and the owner has not confirmed it. Unmarked statements follow from one of those or from the Ka0s standard.

---

## 1. Intent

The owner had a throwaway addon, **CastTrail** (`_forever_/Interface/AddOns/CastTrail`, about 450 lines,
v1.2.1). It scrolls the player's and the pet's casts as icons along two lanes with 1.5 s GCD ticks. Combat
Trail replaces it with a full Ka0s addon that does three things:

1. **The trail.** A TrufiGCD-style cast trail, with a Player lane and a Pet lane where every visual element can be configured.
2. **The live HUD.** A DPS climb shown on every combat: damage, DPS, a damage chart, top spells, and pace against
   your best fight on the same boss or target.
3. **The history.** DPS Race's Results window applied to real combat: a fight table, fight detail, ability
   timeline, compare, gear view and usage, for every fight that passes the recording filters. Fights are
   purged after N days.

The difference from DPS Race **(owner)**: DPS Race runs timed races against training dummies. Combat Trail
records real fights (raids, dungeons, delves, PvP, the open world and dummies) with no arming and no clock to
race.

Success means the owner deletes CastTrail, plays with Combat Trail on both clients, and uses the Results
window to check rotations and gear changes after real pulls.

## 2. Goals, non-goals, anti-goals

**Goals (v0.1.0)**
- Everything in §4 to §9, on **Retail and WoW Forever** from one codebase **(owner)**.
- Born compliant with the Ka0s WoW Addon Standard at the pinned revision. That covers the Ace3 skeleton, the modular layout,
  LibKa0s, skins, launcher, profiles, debug console, test and sim modes, the slash framework, the headless test
  suite on both kit profiles, the automated-test bundle, README, ARCHITECTURE, smoke-tests and DEPENDENCIES.
- **Every visual element can be customized** **(owner)**: colors, fonts, sizes, textures, visibility and position, per lane
  and per window, on top of the selected skin.

**Non-goals (v0.1.0)**
- Lanes other than Player and Pet. Target, Focus and Party 1-5 come later (issue #1) **(owner)**.
- The Insights tab, deferred to v2 (issue #2) **(owner)**.
- Creating new lanes. The dropdown only selects between the fixed lanes **(owner)**.
- Parsing the combat log for damage. Every number comes from `C_DamageMeter`, as in DPS Race and Multi Meters.
- Importing CastTrail's settings **(Claude)**.
- Masque support **(Claude)**. The owner didn't answer this question, so the icons use LibKa0s skins only.
- Group or raid meters (other players' damage). This is a personal tool.

**Anti-goals** (failure even if the addon works otherwise)
- Taint or Lua errors in combat, or any arithmetic, comparison, truth test or table key on a secret
  value.
- A secret value written to SavedVariables.
- A Retail-only feature that appears on Forever, even greyed out (clients-§4).
- A memory or CPU cost the player notices. The lanes animate in `OnUpdate` only while icons are visible, and
  nothing polls while idle.
- Touching LibKa0s, WowAddonStandards or dev-copilot during this run. Anything they need is filed as an
  issue.

## 3. Constraints

- **Clients.** Retail (Midnight 12.x) and Forever (1.60.1, interface 16001). The TOC ships
  `## Interface: <retail>, 16001`. Client detection goes only through `NS.Compat` (clients-§3).
- **Data on Forever.** The probe (owner, 2026-11-10, Forever build 70862) confirmed that `C_DamageMeter` exists with all
  eight Retail functions and identical `Enum.DamageMeterType` and `Enum.DamageMeterSessionType`, and that
  `IsDamageMeterAvailable()` returns true. The player source returns `totalAmount` and `combatSpells`, while
  `amountPerSecond` was nil out of combat. The probe did **not** exercise combat, so in-combat behavior
  on Forever (secret values, cast events, the pet source) is **unverified**. Plan milestone M1 includes an
  in-game probe step. Until it reports, assume Forever behaves like Retail.
- **Secret values (Retail, and assumed on Forever).** Meter numbers are secret in combat. The live HUD may only
  copy them into C-side widgets (`StatusBar:SetMinMaxValues/SetValue`, `FontString:SetText` through the
  library's secret-safe formatters). It must not compute percentages, sort, sum player and pet, or compare
  against a best in Lua. A value captured as secret stays secret, so the in-combat damage curve
  can't be persisted: **the damage chart of a stored fight is available only in the session that recorded
  it**, as in DPS Race. Everything else about a fight (totals, per-spell totals, duration, casts, gear,
  usage) is read or finalized **after combat** as plain values and persisted.
- **Concurrency.** Other agents are editing LibKa0s, WowAddonStandards and dev-copilot. This run vendors
  LibKa0s **v1.94.0** and its `tests/_kit/` from that tag, reads the standard at **4e94ad1**, and copies code
  from DpsRace at **045f479**. Registering in the roster (`WowAddonStandards/standards/ADDONS.md`, NEW_ADDON
  step 10) is **deferred**: it is filed as an issue on WowAddonStandards and done after the other agents finish,
  with the owner's go-ahead.
- **Code reuse (Claude).** Copy and adapt DpsRace's modules, not shared code. Issue #3 tracks extracting
  them into LibKa0s later.

## 4. Lanes (the trail)

Two fixed lanes, **Player** and **Pet** **(owner)**. CastTrail is the behavioral baseline: casts come from
`UNIT_SPELLCAST_SUCCEEDED` for `player` and `pet`, castGUID-deduped, with icons scrolling from the "now"
edge, fading over the last part of the window, and GCD reference ticks.

Per-lane settings. Each tab maps to a settings tab on the Lanes page (mockup §4):

| Tab | Settings |
|---|---|
| General | enable, unlock, copy settings from the other lane, reset lane, live preview |
| Size and position | direction (newest at right / left / bottom / top, scrolling away from it), scale, lane length px, seconds shown, icon size, icon spacing; **anchoring** (below) with point, relative point, X and Y offsets; **frame strata** (BACKGROUND, LOW, MEDIUM, HIGH; default **LOW**; DIALOG left out per frame-layering-§1 (Claude, 2026-11-10); unit-frame mode offers "Match host" as an extra choice and uses it by default) and **frame level offset** (0–50, default 0) **(owner, 2026-11-10)** |
| Icons | border on/off, color and size; icon zoom (crop); **mark interrupted or cancelled casts** (red ✕); **glow long cooldowns** (≥ N s, default 29) with glow color; spell tooltip on hover; spell name under icon; fade portion (default the last 20%); stack repeated casts |
| Background and border | lane background on/off, texture, color and opacity; lane border on/off, texture, color and size; padding |
| Ticks and labels | GCD ticks on/off, spacing (1.5 s fixed, haste-adjusted GCD, 1 s), color and width; "now" line on/off and color; label on/off, text (default "You" and the pet's name), font, size, outline, color and position |
| Visibility | show (always, in combat only, in combat or with a target, never); hide N s after combat; where (open world, dungeons, raids, delves*, battlegrounds, arenas*); hide when mounted, in a vehicle, in a pet battle, or resting; opacity in and out of combat |
| Ignored spells | a per-lane list, seeded per client (Auto Attack 6603, Auto Shot 75, Shoot 5019 on the player lane; Auto Attack on the pet lane, plus each client's pet auto-attack IDs); add by ID, name or link; remove; reset |

\* Options a client can't have are **absent** there (clients-§4). This is Claude's reading of which ones apply:
Delves and Arenas are Retail-only, and so are Mythic+ in History.

**Anchoring (owner).** There are three modes per lane, and the default is **Free** (not anchored):
1. **Free:** the lane is positioned by Edit Mode (one Edit Mode system per lane, like CastTrail's blue box) or by the
   offsets on the tab. When Blizzard's Edit Mode isn't available, `/ct unlock` shows the drag overlay instead.
2. **Dock to the other lane:** set a point, relative point and gap. Moving the host moves the docked lane, and a lane
   can't dock to a lane that is docked to it.
3. **Unit frame:** the Player lane anchors to the player frame and the Pet lane to the pet frame. The frame is auto-detected
   in order: ElvUI, Shadowed Unit Frames, Cell, Pitbull, UnhaltedUnitFrames, then Blizzard. A "Frame by name…" option
   accepts any global frame name. If the frame is missing or forbidden, the lane falls back to Free and
   prints one diagnostic line. Strata and level follow the host (frame-layering, host-matched surfaces).

**Layering (owner, 2026-11-10).** CastTrail's icons climbed up to 200 frame levels above their lane (`level % 200 + 1`).
That let a cast icon draw over unrelated windows on the same strata (the owner saw a fishing icon float over a
fishing-helper window). Combat Trail must not do this:
- each lane sits on its configured **strata** (default LOW, below most addon windows, which use MEDIUM and up).
  Its level is relative to that strata's base plus the lane's level offset (frame-layering: every level relative,
  through `NS.Constants.LAYERS`).
- icons stay inside a **bounded band** just above their lane: `laneLevel + 1 … laneLevel + ICON_BAND` with
  `ICON_BAND = 8`. "Newest on top" comes from re-ordering the visible icons within that band on each push, never from
  a counter that climbs.
- the edit overlay, the ✕ marker and the glow use named offsets in the same band. Nothing in a lane ever calls
  `SetFrameLevel` with an absolute number.

**Interrupted and cancelled casts (Claude).** On `UNIT_SPELLCAST_INTERRUPTED` or `_FAILED` for a cast that
showed a start (cast-time spells), the lane pushes the icon with the red ✕ marker. Instant casts that
fail aren't shown. Secret castGUIDs and spellIDs are handled like CastTrail: never tested or keyed before `issecretvalue`.

**Long-cooldown glow (Claude).** The cooldown length comes from the spell's base cooldown (`GetSpellBaseCooldown`, pcall'd,
plain out of combat and cached per spellID). DpsRace's ≥ 29 s rule is the default.

## 5. Fights: tracking, identity, storage, retention

**A fight is one Blizzard meter session (Claude).** The addon follows the meter's own segmentation, the same
segments the built-in meter shows, rather than inventing its own. A new session appearing while the player
enters combat (or inside combat, for example when `ENCOUNTER_START` opens one) starts a new tracked fight. The
fight ends when the player has left combat and the session has stopped updating for the settle window (DpsRace's
quiet-wait pattern in `Race.lua` and `Meter.lua`). Edge cases:
- **Feign Death, Vanish, Shadowmeld:** if the player re-enters combat within a **grace period (default 4 s)** and the
  meter keeps the same session, it is still the same fight. If the meter opened a new session but the same
  `encounterID` is still active, the two sessions are **merged after combat** (plain sums) into one fight.
- **Chained trash** (one long combat, many targets): one session gives one fight. The primary target is the enemy that took
  the most damage, and the identity line says "+N others".
- **An encounter starting mid-combat:** if the meter splits there, the pre-encounter part is its own fight (usually
  under 30 s, so not stored) and the boss part is the encounter fight. If the meter doesn't split, the whole session is
  one fight carrying the encounter identity.
- **A meter reset mid-fight:** the fight is marked *lost* (as in DpsRace) and isn't stored.
- **The live HUD** follows the same session: the clock starts on the session's first damage update.

Every fight is **tracked** live for the HUD **(owner)**. A fight is **stored** only if
it passes the recording filters:

| Filter | Default |
|---|---|
| Minimum length | **30 s** **(owner)** |
| Bosses only | off |
| Content types | raids, dungeons (Retail: incl. Mythic+), delves*, battlegrounds, arenas*, open world, training dummies: all on; scenarios off **(Claude)** |

**Identity (Claude).** The identity is read after combat, as plain values:
- **Encounter:** `ENCOUNTER_START` and `ENCOUNTER_END` (`encounterID`, name, difficultyID, group size) inside the fight.
  These make it a boss fight.
- **Primary target:** the enemy that took the most damage, from the session's `EnemyDamageTaken` sources
  (name, `sourceCreatureID`). The fallback is the target snapshot taken at combat start (DpsRace `Recorder`'s
  secret-safe snapshot).
- **Content:** `GetInstanceInfo()` (instance type, difficultyID, instance name and map) and, since v0.2, the zone and
  subzone (`GetZoneText`, `GetSubZoneText`: the open world's instance name is the continent); delve (Retail);
  Mythic+ keystone level (Retail, `C_ChallengeMode`); training dummy from a **per-client** dummy creature-ID
  seed list (start from DpsRace `DummyList.lua`; Forever gets its own list, possibly empty by decision).
- **Who:** character, realm (Forever's two-word names and long realm labels, client-quirks §5), class, spec,
  item level, pet name and family. On Forever (v0.2 owner decision D5) the client answers one class-wide spec,
  so the talent tree with the most points stands in for the spec everywhere (the row's second icon, the Spec
  filter and grouping, the bests' board, the Share line), worded "talent tree" (D11); each tree's points are
  stored too.

**Board key (Claude; v0.2 owner decision D3)** (used for grouping, bests and pace): `encounterID + difficultyID` for boss fights
(a world boss without an encounter: `creatureID + difficultyID`), otherwise the primary target's **NPC ID + level + name**
`+ difficultyID` (the level is the combat-entry target read, taken when that target is the primary; a sealed level
is "?"; a named target with no NPC ID keys by its name alone), plus a **tier qualifier** where difficulty alone
doesn't separate content: the Mythic+ keystone level, the delve tier, and the PvP bracket. Bosses store the target's
level and NPC ID for display only. The open world uses no
group-size qualifier. Bests also add character and spec. The client key is part of the character, so boards
never mix Retail and Forever, and their difficulty IDs never need to be comparable. A fight with no
readable identity is stored under "Unknown target" and never counts as a best.

**Best (Claude, following DpsRace):** the top DPS for a character × spec × board key. DPS is the merged total (player + pet)
÷ fight duration (the meter's session duration, or the addon's own regen-to-regen clock when the meter's is
unreadable). Bests are recomputed from the stored fights, not stored separately.

**Retention (owner):** purge fights older than **7 days** (setting: 0 = keep forever), and keep any fight that
holds a best (toggle, default on). There's also a **500-fight cap (Claude)**: the oldest non-best fights go first. The purge
runs at login, once a day while logged in, and from `/ct purge`.

**Fight record** (account-wide, `db.global.fights`; versioned with migrations like DpsRace's run record):
id, time, duration, who, identity, content, board key, damage (merged, player, pet), DPS, meter DPS,
spells[] {spellID, total, isPet} with percentages computed at read, casts[] {t, spellID, unit, interrupted},
gear, stats, talent loadout string, usage[], note, client key, build and addon version. **No secret ever enters
the record.** Fields that came back secret are left absent.

**Record size (Claude).** Casts are stored packed: one string per fight, delta-encoded `t:spellID[:flags]`
tokens, with the spell list kept separately. Gear is stored as trimmed item strings, not full links, and
(v0.2) once per distinct equipment set in `db.global.gearSets`: a recon at every world entry and after each
equipment change interns the set the player wears, and a record holds the key of the set current at combat
start (`gearSet`). The
talent string is stored once per distinct loadout and referenced by hash. The target is **under 6 KB for a
5-minute raid fight**, so 500 fights stays around 3 MB or less. The cap is one global cap (bests exempt); the
Retention page shows the current count and an estimated size. A per-content cap can come later if the owner
finds open-world fights crowding out raid history.

## 6. Live DPS HUD

**When (owner):** on every combat, it fades in on the first damage and fades out N s after combat (default 8 s). It stays while
the mouse is over it, and can be pinned open. Other modes: always shown, or only when toggled.

**Contents** (mockup §2): a clock counting up from the first hit; a target line (encounter or target, instance,
difficulty); Damage and DPS boxes (live from the meter, copied, never computed); a **pace bar** against your
best on the same board key **(owner)**; the damage chart (one column per time bucket, a dashed line for the best's average pace,
icons for cooldowns ≥ 29 s); and spell rows (icon, name, bar, amount, with pet spells marked by a paw and a green bar).

**Fight-over card:** final damage and DPS, percentages per spell, a New best chip with the delta, and a Saved or "Not saved:
<reason>" chip. The chart button opens the fight in Results.

**Pet in combat (Claude).** The meter exposes the pet as **its own source** (Multi Meters scope.md, pet
folding). In combat the HUD can't sum player and pet, so:
- the Damage box shows the player source's total, and a smaller "Pet" figure sits beside it (copied).
- the spell rows list player spells, then pet spells, in the meter's own order. Each bar is scaled to the
  player source's `maxAmount` (C-side clamp).
- the pace bar draws the player fill, then a pet fill anchored to the end of the player fill's texture (C-side
  geometry, never read back) against the best's merged damage so far. If that turns out not to work in
  game, fall back to player-only pace against the best's player damage.
- after combat everything merges in plain Lua.

**Not available on the HUD:** live percentages, sorting, and a live delta number, because of secret values. The same
FAQ wording as DpsRace applies.

## 7. Results window

The same structure as DpsRace's Results window (owner: "results table, results details and results timeline,
all from DPS Race"), with real-combat columns and filters (mockup §5):

- **Filters:** character, spec, content type, encounter or target, difficulty, date range (default last 7
  days), bosses only, group by (encounter + difficulty (default), character, spec, content, none), and Save view.
- **Table:** date, class and spec icons, character, ilvl, encounter or target, content chip, length, damage,
  DPS, delta against the best in the group, a trophy on the best. Clicking a row shows its detail. The right-click menu has note,
  share, compare with this fight, and delete (with confirmation).
- **Detail:** header (who and spec, then three meta lines since v0.2: realm, ilvl and the place; the target and its
  level, difficulty, tier, length and pet; the date, build and version), stat boxes (damage,
  DPS, meter DPS, a Delta or "Leads by" box), the damage chart (this session only), the spell breakdown with pet
  spells tagged, Gear and Talents (Gear view, View talents, Copy import string), Usage (Edit), and buttons for Timeline,
  Compare vs best, Add note, Share and Delete. A fold arrow hides the detail.
- **Ability timeline (owner: same as DpsRace):** opens over the Results window. It shows two icon strips (this fight in gold,
  the compared fight in blue), per-ability rows with two tick lanes, cooldown length under the name, cast counts, long
  cooldowns first, pet abilities (toggle), zoom and pan (buttons, Ctrl+wheel, Shift+wheel), and a help "?".
- **Compare (owner):** against the best on the board key, or the runner-up if this fight is the best, or any fight picked from the
  right-click menu. Damage, DPS, length and every spell side by side with deltas and dual bars, gear slots changed, and a
  Different loadout mark.
- **Gear view and stats (owner):** DpsRace `Results_Gear.lua` and `Stats.lua`. Snapshots are taken at combat start, and
  re-read out of combat for any field that came back secret.
- **Usage (owner):** DpsRace `Usage.lua` and `Results_Usage.lua`: on-use gear and consumables found from casts, bag counts
  and buffs. A "never show" list lives on History ▸ Usage.
- **Share:** a one-line chat summary, with an optional talents link (mockup §9).
- **Test mode:** a sample history (DpsRace `MockRuns.lua` pattern) behind a "sample data" strip, never written.

## 8. Settings, slash, launcher, skins

- **Settings ▸ AddOns ▸ Ka0s Combat Trail**, built with `LibKa0s-Options-1.0` (options-ui). The pages are General
  (Master controls, Look and skin, Keybindings), **Lanes** (lane dropdown and seven tabs), DPS HUD (Behavior,
  Layout, Clock and figures, Damage chart, Spell rows, Window), History (Recording filters, Retention, Results
  window, Usage) and Profiles. Headers, Defaults and Reset follow the Panel Master pattern **(owner)**.
- **Slash (Claude):** `/ct` and `/combattrail` through `LibKa0s-Slash-1.0`. The verbs are help, results, hud
  show|hide, unlock, lock, test, sim, lane player|pet on|off, ignore add|remove <spell> [lane], set, get, reset,
  purge, debug, diagnostics, and **probe** (a built-in version of KCTProbe for the in-game checks). Every setting is reachable
  by `set <path>`.
- **Launcher:** the minimap button (LibDBIcon) and the master-controls menu in the standard's shape (launcher).
  Following DpsRace's roster row **(Claude)**: Enabled, Locked, Test mode, Sim mode, Show window (the HUD); the test
  verb is `test`.
- **Skins:** LibKa0s skins. The default is per client (WoW Forever on Forever, Ka0s Default on Retail), answered by the
  library. Every element has its own overrides on top of the skin.
- **Keybindings:** Toggle DPS HUD, Toggle Results window, Toggle lanes.
- **Debug and diagnostics:** the standard debug console and `/ct diagnostics` report, as in DpsRace.
- **Sim mode:** a made-up 45 s fight played in real time through the lanes, the HUD and into Results **(Claude)**.

## 9. Architecture outline (Claude)

The standard's modular layout (`core/ modules/ defaults/ settings/ locales/ tests/`). Module names are
indicative, and the plan settles them:

| Area | Modules | Source |
|---|---|---|
| Core | Namespace, Compat, Secrets, Constants, State, Env, Core, Media, Skin, Widgets, Charts, Pool, Bus, Toast, Lifecycle, Launcher, Perf, Sim, DebugLog, Database | DpsRace `core/` |
| Lanes | Lanes (model), LaneRender (frames, pooling, OnUpdate), LaneAnchor (free/dock/unit frame, Edit Mode), LaneCasts (events) | CastTrail plus new code |
| Fights | Watchers (events per state), Fight (state machine: idle → combat → settling → final), Meter, Slices, Casts, Identity (encounter, target, content, dummy), Recorder (store), Scoring (DPS, flags), Bests, Retention, Filters | DpsRace `Meter`, `Slices`, `Casts`, `Recorder`, `Bests`, `Scoring`, `Watchers`, `DummyList`, adapted |
| HUD | Hud, Hud_States, Hud_Chart, Hud_Breakdown, Hud_Best (pace), Hud_Appearance, Hud_Tips | DpsRace `Hud*` |
| Results | Results, Results_Source, Results_Table, Results_Detail, Results_Timeline(+Data), Results_Compare, Results_Gear, Results_Loadout, Results_Usage, Results_Tips, Share, Stats, Loadouts, Usage, MockFights | DpsRace `Results*` |
| Settings | Schema, OptionsSetup, General, Lanes, Hud, History, Profiles, Slash | DpsRace `settings/`, Panel Master's per-entity dropdown pattern for Lanes |

The per-client feature table goes in `docs/ARCHITECTURE.md` (clients-§4).

## 10. Testing and done

- A headless suite on the vendored `tests/_kit/` (LibKa0s v1.94.0), run under **both** `KA0S_KIT_CLIENT=retail` and
  `forever`. Each per-client feature has a present test and an absent test.
- Lint clean (luacheck), lizard complexity with no function above CCN 15, and the first automated-test bundle under
  `docs/automated-tests/`.
- `docs/smoke-tests.md` covers both clients, with checks named per client. In-client smoke tests are the owner's,
  and an agent never marks them passed.
- An in-game check list for the unverified items: Forever in-combat secrecy, pet source in combat, cast
  events, pet-fill anchoring on the pace bar, and the unit-frame anchors.
- **The run does not stop for in-game input (Claude).** It builds to the "assume Retail" design, with the §12
  fallbacks behind small seams (one place each for the pet-source split and the pace-bar pet fill). `/ct probe`
  ships in M1. The owner runs it and the smoke tests when they can, and the merge to `main` already waits on the
  owner's go-ahead. Any "no" from the probe becomes a fix commit on the branch before the merge. **No release tag is cut
  in this run.** v0.1.0 is tagged after the owner's smoke tests pass.
- Definition of Done from the NEW_ADDON context pack at the pinned standard.

## 11. Left to the builder

Module boundaries and names; the exact defaults table; the order of unit-frame detection; how
DpsRace modules are trimmed of race-only logic (arming, buzzer, late-cast flags, countdown); test case
lists; locale strings; Edit Mode integration details; the sample data for test and sim modes.

## 12. Risks

| Risk | Mitigation |
|---|---|
| Forever behaves differently in combat | M1 in-game probe (`/ct probe`); design for secrets regardless |
| The pet isn't a separate meter source on one client | the probe confirms it; if the pet is folded into the player, drop the pet split and tag pet spells by the IDs seen from `UNIT_SPELLCAST_SUCCEEDED` unit=pet |
| The pace bar's pet-fill anchoring fails | fall back to player-only pace |
| Scope is large (DpsRace is about 24k lines) | milestones with a pushed checkpoint each; the plan's status ledger makes the run resumable |
| LibKa0s v1.94.0 lacks something needed | work around it locally, file a LibKa0s issue, and don't edit LibKa0s |
