# Ka0s Combat Trail v0.1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **This run executes milestone by milestone through Workflow scripts (owner: "use ultracode"), one workflow per milestone, each task = implement agent → review agent.**

**Goal:** Build Ka0s Combat Trail v0.1.0: Player and Pet cast lanes, a live DPS HUD, and a DpsRace-style fight history. It runs on Retail and WoW Forever and is born compliant with the Ka0s standard.

**Architecture:** An Ace3 addon in the Ka0s modular layout (`core/ defaults/ modules/ settings/ locales/ tests/`). LibKa0s v1.94.0 is vendored. Core, meter, HUD and Results code is copied and adapted from DpsRace @045f479. The lanes are new code grown from CastTrail. Damage comes only from `C_DamageMeter`, and secret values are only ever copied into C-side widgets. Fights are stored account-wide as plain values after combat.

**Tech Stack:** Lua 5.1 (WoW), Ace3 (the Forever-safe copy in PanelMaster/libs), LibKa0s v1.94.0 (+ its `testkit` → `tests/_kit/`), LibSharedMedia, LibDataBroker, LibDBIcon; headless tests via `lua tests/run.lua`; luacheck; lizard.

**Spec:** `docs/superpowers/specs/2026-11-10-combat-trail-design.md` (read it first; section refs below are `§N` of the spec). Mockup: `docs/superpowers/specs/2026-11-10-combat-trail-mockup/index.html`.

---

## Status ledger (resume here)

Update the row and commit with each task. Each task row gets the commit SHA that completed it. A resumed session reads this table, runs `git log --oneline`, and continues from the first row that isn't `done`.

| Task | Title | Status | Commit |
|---|---|---|---|
| 0.1 | Scaffold, libs, core, load test | done | this commit, `feat: scaffold Combat Trail on Ace3 and LibKa0s v1.94.0` (2026-11-10: TOC for 120105 + 16001, Panel Master's Ace3/LSM/LDB/LibDBIcon, LibKa0s v1.94.0 + kit, icons pruned to 30, core ported from DpsRace minus ChartsSetup and ToastSetup (Insights and the toast are out of scope), Compat client checks, per-client default skin, defaults skeleton, logo via tools/make_logo.py, stub docs/ARCHITECTURE.md for the layout-cap census, CRLF working tree per line-endings-§2; 60 pass / 2 declared skips on retail and on forever, luacheck 0/0) |
| 0.2 | Settings framework, General, Profiles, Slash, Launcher | todo | |
| 1.1 | Lane defaults, ignore seeds, LaneCasts | todo | |
| 1.2 | LaneLayout + LaneRender | todo | |
| 1.3 | LaneAnchor + LaneVisibility | todo | |
| 1.4 | Lanes settings page | todo | |
| 1.5 | /kct probe | todo | |
| M1 | Checkpoint push | todo | |
| 2.1 | Meter (player + pet sources) | todo | |
| 2.2 | Fight state machine + Watchers | todo | |
| 2.3 | Identity, dummies, board key | todo | |
| 2.4 | CastCodec, Casts, Usage, Stats, Loadouts | todo | |
| 2.5 | Recorder, Filters, Bests, Retention | todo | |
| 2.6 | Slices | todo | |
| M2 | Checkpoint push | todo | |
| 3.1 | HUD shell + states | todo | |
| 3.2 | Chart, pace, breakdown, appearance | todo | |
| 3.3 | DPS HUD settings page | todo | |
| M3 | Checkpoint push | todo | |
| 4.1 | Results shell, Source, Table, Tips | todo | |
| 4.2 | Detail, Share | todo | |
| 4.3 | Timeline + TimelineData | todo | |
| 4.4 | Compare, Gear view, Loadout, Usage edit | todo | |
| 4.5 | History settings page | todo | |
| M4 | Checkpoint push | todo | |
| 5.1 | Test mode, Sim, MockFights | todo | |
| 5.2 | Bindings, Diagnostics, skin surfaces | todo | |
| 5.3 | Docs set | todo | |
| 5.4 | Automated-test bundle, complexity, whole-branch review | todo | |
| 5.5 | Roster issue, smoke hand-off, final push | todo | |

---

## Global Constraints

- **Pins (spec §3):** LibKa0s **v1.94.0** (copy from `git -C ../LibKa0s archive v1.94.0`, never the working tree), WowAddonStandards **4e94ad1** (`git -C ../WowAddonStandards show 4e94ad1:<path>`), DpsRace **045f479**. **Never write to LibKa0s, WowAddonStandards, dev-copilot, DpsRace or PanelMaster.** If you need something from them, file a GitHub issue on that repo (`gh issue create -R tusharsaxena/<repo>`) and work around it locally.
- **Clients:** TOC `## Interface: 120105, 16001`. Client checks only through `NS.Compat.IsRetail()/IsForever()/ClientKey()/ForClient()` (clients-§3). A Retail-only feature (Delves, Arenas, Mythic+, Challenge Mode) is **declared** with `clients = { "retail" }` and **absent** on Forever (clients-§4). Per-client seed lists are picked once (clients-§5).
- **Identity:** folder and AceAddon `CombatTrail`, title `Ka0s Combat Trail`, SavedVariables `CombatTrailDB` (+ `CombatTrailPerfDB` if the Perf seam needs it, as in DpsRace), slash `/kct` and `/combattrail`, chat prefix `Combat Trail`, author `add1kted2ka0s`, MIT, `## Category-enUS: Combat`, version `0.1.0` (no tag in this run).
- **Secrets (spec §3, anti-goals):** never do arithmetic, compare, truth-test, `tostring`, or use as a table key on a value that may be secret. Route every inspection through `NS.Secrets` (DpsRace `core/Secrets.lua` API: `PlainNumber`, `PlainString`, `PlainTruth`, `CanAccessTable`, `SafeIterate`). Never persist a secret. In-combat meter numbers only go to `StatusBar:SetMinMaxValues/SetValue` and secret-safe text setters.
- **Green gate before every commit:** `lua tests/run.lua` **and** `KA0S_KIT_CLIENT=forever lua tests/run.lua` both all-pass, and `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` reports 0 warnings / 0 errors.
- **Complexity:** no function above CCN 15 (`lizard -C 15 -x "./libs/*" -x "./tests/_kit/*" .`). This is enforced from Task 5.4, but write for it from the start.
- **Commits:** one per task minimum, conventional-commit subject, ending with the attribution trailer:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01JV4dmNsR2fNZSmHBxysaEL`. Update the status ledger row in the same commit. Work only on branch `feat/2026-11-10-combat-trail-v0.1.0`. Push only at the M-checkpoints. **Never merge to main** (owner gate).
- **Copy rule:** when porting a DpsRace file, keep its header-comment convention (file job, LOAD-BEARING notes) and rewrite it for Combat Trail. Remove race-only concepts (arm, buzzer, countdown, late cast, auto-arm, race length, dummy-type boards) entirely, and don't leave them dead.
- **Player-facing copy:** plain language, no em-dash asides. Locale strings live in `locales/enUS.lua` (`NS.L`).

## Review Focus

These inputs and conditions aren't exercised by any single task's happy-path tests and are the most likely to break for a player. Each line names the task that owns its test:

1. **A spell ID or castGUID that arrives secret in combat** (Forever/Retail): the lane still shows the icon via the texture (pcall'd), dedupe is skipped, no error is raised. *Test in 1.1: `test_lane_casts: secret spellID still pushes, no raise`.*
2. **No pet, a pet dismissed mid-fight, or a pet that changes** (hunter swaps or a warlock resummons): the Pet lane label dims and the meter's pet source is nil-safe. Fight records carry the pet that dealt damage, or none. *Tests in 1.1 (`pet lane with no pet`), 2.1 (`ReadLive with no pet GUID returns pet=nil`).*
3. **Feign Death or Vanish mid-boss, and back-to-back trash:** one fight, not two, and not lost. *Test in 2.2: `FD within grace keeps one fight`, `encounter split sessions merge after combat`.*
4. **`/reload` or logout during combat or settling:** no secret is persisted, the in-progress fight is discarded cleanly (marked lost only if a record was opened), and nothing errors on the next load. *Test in 2.5: `reload mid-fight leaves store valid`.*
5. **A huge history** (500 fights, long raid fights, many casts): login purge and the Results table stay responsive, and the record size target holds. *Tests in 2.4 (`250 casts packs under 2.5 KB`), 2.5 (`5-min raid record < 6 KB`, `purge of 600 fights keeps bests and caps at 500`), 4.1 (`table builds 500 rows via pooled rows`).*

---

## Milestone 0 — Foundation

### Task 0.1: Scaffold, libs, core, load test

**Files:**
- Create: `CombatTrail.toc`, `LICENSE` (MIT, add1kted2ka0s), `CLAUDE.md` (the standard's stub shape, copied from DpsRace's and rewritten: name, green gate, provenance lines `Bundles LibKa0s v1.94.0 (MIT).` and `LibKa0s icons: …`), `.luacheckrc` (from PanelMaster's, with globals for this addon), `.gitignore`, `DEPENDENCIES.md`, `README.md` (placeholder until 5.3)
- Create: `libs/` = LibStub, CallbackHandler-1.0, AceAddon/Event/Timer/DB/DBOptions/Console/GUI/Config (copied from `../PanelMaster/libs/`, the Forever-safe Ace3), LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0 (from PanelMaster), `libs/LibKa0s/` (from `git -C ../LibKa0s archive v1.94.0 LibKa0s`)
- Create: `tests/_kit/` (from `git -C ../LibKa0s archive v1.94.0 testkit`, laid out as DpsRace's `tests/_kit/`), `tests/run.lua`, `tests/test_load.lua`
- Create: `locales/enUS.lua`, and `core/{Namespace,MediaSetup,Constants,State,EnvSetup,CoreSetup,SkinSetup,Compat,SimSetup,Secrets,Bus,PoolSetup,WidgetsSetup,ToastSetup,ChartsSetup,LifecycleSetup,PerfSetup,DebugLogSetup,LauncherSetup,CombatTrail,Database}.lua`, ported from DpsRace `core/` (rename `DpsRace.lua` to `CombatTrail.lua`)
- Create: `defaults/Profile.lua` (skeleton: `general`, `lanes`, `hud`, `history`, `results` sub-tables, filled by later tasks)
- Create: `media/logos/combattrail.logo.128.tga` and `.png` (generate with a small script in `tools/make_logo.py`: a dark square, a gold trail of three icon tiles fading left)

**Interfaces:**
- Produces: `NS` (the AceAddon object `CombatTrail`), `NS.L`, `NS.name="CombatTrail"`, `NS.BRAND="Ka0s Combat Trail"`, `NS.SLASH="kct"`, `NS.SLASH_LONG="combattrail"`, `NS.Print`, `NS.Compat`, `NS.Secrets`, `NS.Bus`, `NS.Pool`, `NS.Skin`, `NS.Debug`, `NS.db` (AceDB on `CombatTrailDB`, defaults from `NS.defaults`), `NS.Constants.LAYERS`

- [ ] **Step 1: Copy the libs and the kit** from the pinned sources above. `git -C ../LibKa0s rev-parse v1.94.0` must resolve, and record the SHA in CLAUDE.md's provenance line.
- [ ] **Step 2: Write `tests/test_load.lua`.** It loads every TOC file in order via the kit and asserts: `NS` is an AceAddon named `CombatTrail`, `NS.db.profile` exists after `OnInitialize`, and `NS.Compat.ClientKey()` equals `"retail"` by default and `"forever"` under `KA0S_KIT_CLIENT=forever`. `tests/run.lua` is copied from DpsRace and pointed at this TOC.
- [ ] **Step 3: Run** `lua tests/run.lua`. Expected: FAIL (core files missing).
- [ ] **Step 4: Port the core files and write the TOC** (`## Interface: 120105, 16001`, `## IconTexture: Interface\AddOns\CombatTrail\media\logos\combattrail.logo.128.tga`, OptionalDeps as DpsRace, `## X-Standard`, `## X-License: MIT`, load-order comments in DpsRace's style).
- [ ] **Step 5: Green gate** on both profiles, plus luacheck 0/0.
- [ ] **Step 6: Commit** `feat: scaffold Combat Trail on Ace3 and LibKa0s v1.94.0`, ledger 0.1 done.

### Task 0.2: Settings framework, General, Profiles, Slash, Launcher

**Files:**
- Create: `settings/{Schema,Slash,OptionsSetup,General,Profiles}.lua` (port DpsRace's; General has three tabs **Master controls** (Enabled, Locked, Test mode, Sim mode, Show DPS HUD in combat, Minimap button, Debug logging, Open debug console), **Look and skin** (skin dropdown + selector, global font, global font scale), **Keybindings** (filled in 5.2))
- Modify: `core/LauncherSetup.lua` (master-controls menu: Enabled, Locked, Test mode, Sim mode, Show window (HUD); `test` verb)
- Test: `tests/test_settings.lua`, `tests/test_slash.lua`

**Interfaces:**
- Produces: `NS.RegisterSchemaRows(page, rows)`, `NS.RegisterTabbedPage(def)`, `NS.Helpers` (DpsRace names), `NS.Slash.Register(verb, def)`, the setting paths `general.enabled`, `general.locked`, `general.testMode`, `general.simMode`, `general.hudInCombat`, `general.minimap.hide`, `general.debug`, the bus message `SETTINGS_CHANGED(path)`

- [ ] **Step 1: Write tests.** `test_settings`: the page order is General, Lanes, DPS HUD, History, Profiles (stubs for the middle three registered here, filled later). Every `general.*` path round-trips through `/kct set` and `/kct get`. `test_slash`: `/kct help` lists the verbs from spec §8, and an unknown verb prints the help hint.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement** by porting, renaming paths and removing race pages.
- [ ] **Step 4: Green gate. Step 5: Commit** `feat: settings framework, General and Profiles pages, slash and launcher`.

---

## Milestone 1 — Lanes and the probe

### Task 1.1: Lane defaults, ignore seeds, LaneCasts

**Files:**
- Modify: `defaults/Profile.lua` (`lanes.player`, `lanes.pet`: every key in spec §4's table; defaults: enabled true, width 480, seconds 12, iconSize 28 (pet 24), direction `"left"` (newest at the right edge), scale 1, spacing 0, anchor `{mode="free", point="CENTER", relPoint="CENTER", x=0, y=-200 (pet -236)}`, border on, color `{1,0.82,0,0.9}` (pet `{0.4,1,0.4,0.9}`), zoom 0.08, markInterrupted true, glowLongCD true, glowMinCD 29, tooltip true, showName false, fade 0.2, stack false, background on `{0,0,0,0.35}`, laneBorder off, ticks on, tickSpacing `"gcd15"`, now on, label on (`"You"`, pet: `""` = the pet's name), visibility `{show="always", hideAfter=5, where={world,dungeon,raid,delve,bg,arena all true}, hideMounted=true, hideVehicle=true, hidePetBattle=true, hideResting=false, alphaCombat=1, alphaOOC=1}`; the pet lane defaults to anchor mode `"dock"` under player with gap 4, per the mockup; `strata="LOW"`, `levelOffset=0` (spec §4 Layering; `strata` also accepts `"HOST"` = match host, used as the default when `anchor.mode="unit"`))
- Create: `defaults/IgnoreSeeds.lua` (`NS.IgnoreSeeds = {Retail={player={6603,75,5019}, pet={…pet melee IDs}}, Forever={player={6603,75,5019}, pet={…}}}` picked once into `NS.IGNORE_SEEDS`)
- Create: `modules/LaneCasts.lua`
- Test: `tests/test_lane_casts.lua`

**Interfaces:**
- Produces: `NS.LaneCasts.OnSucceeded(unit, castGUID, spellID)`, `NS.LaneCasts.OnInterrupted(unit, castGUID, spellID)`, `NS.LaneCasts.OnStart(unit, castGUID, spellID)`. Each pushes through `NS.Bus` message `LANE_PUSH(laneKey, {texture, spellID|nil, t, interrupted=bool})`. Also `NS.LaneCasts.IsIgnored(laneKey, spellID) -> bool` and `NS.LaneCasts.PetName() -> string|nil`.

- [ ] **Step 1: Write `test_lane_casts`.** Cases: `player cast pushes to player lane`; `pet cast pushes to pet lane`; `same castGUID twice pushes once`; `ignored spellID (6603) does not push`; `secret spellID still pushes with texture, no raise` (kit secret helper); `secret castGUID skips dedupe`; `interrupted cast that had a start pushes with interrupted=true`; `instant cast failure does not push`; `per-lane ignore list is independent`; `pet lane with no pet: PetName() is nil and label falls back`; `forever profile uses Forever seed list`.
- [ ] **Step 2: Run.** Expected: FAIL. **Step 3: Implement.** Event registration is gated on `general.enabled` and on each lane's `enabled`. **Step 4: Green gate. Step 5: Commit** `feat(lanes): cast capture with dedupe, ignore lists and interrupt marks`.

### Task 1.2: LaneLayout + LaneRender

**Files:** Create `modules/LaneLayout.lua` (pure) and `modules/LaneRender.lua`. Test: `tests/test_lane_layout.lua`, `tests/test_lane_render.lua`.

**Interfaces:**
- Produces: `NS.LaneLayout.Position(age, cfg) -> x, y` (offset of the icon's TOPLEFT inside the lane for `cfg.direction ∈ {left,right,up,down}`, `cfg.width`, `cfg.seconds`, `cfg.iconSize`), `NS.LaneLayout.Alpha(age, cfg) -> 0..1` (fade over the last `cfg.fade` portion), `NS.LaneLayout.TickOffsets(cfg, gcd) -> {px…}`, `NS.LaneLayout.LaneSize(cfg) -> w, h`. Also `NS.LaneRender.Get(laneKey) -> frame`, `NS.LaneRender.Apply(laneKey)` (re-reads settings, restyles live icons), `NS.LaneRender.Push(laneKey, item)`, `NS.LaneRender.Clear(laneKey)`.

- [ ] **Step 1: Write the tests.** `test_lane_layout`: for width 480, seconds 12, icon 28: `left` age 0 → x = 452, age 6 → x = 212; `right` age 6 → x = 240; `up` and `down` mirror on y. Alpha is 1 at age 9.5 and 0.5 at age 10.8 with fade 0.2. TickOffsets with gcd 1.5 gives 8 offsets of 60 px steps. `test_lane_render`: the pool reuses frames after expiry; OnUpdate is nil once the lane is empty; Apply restyles the border color on live icons; an interrupted item shows the ✕ overlay; a spell with base cooldown ≥ glowMinCD gets the glow (stub `GetSpellBaseCooldown`) and the result is cached per spellID; **`icon levels stay within laneLevel+1..laneLevel+8 after 500 pushes`** (the regression for CastTrail's climbing `level % 200` bug), **`newest icon has the highest level in the band`**, **`lane uses its configured strata (default LOW) and Apply moves live icons with it`**, **`no absolute SetFrameLevel call`** (assert every level equals lane level + a `NS.Constants.LAYERS` offset).
- [ ] **Step 2: Run** (FAIL). **Step 3: Implement.** Use `NS.Pool`, skin border via `NS.Skin`, a tooltip on hover only when `tooltip` is true (`EnableMouse` follows it), and the label text from `PetName()` for the pet. The haste-adjusted GCD tick option reads `UnitSpellHaste` out of combat and caches it. **Step 4: Green gate. Step 5: Commit** `feat(lanes): layout math and pooled renderer in four directions`.

### Task 1.3: LaneAnchor + LaneVisibility

**Files:** Create `modules/LaneAnchor.lua` and `modules/LaneVisibility.lua`. Test: `tests/test_lane_anchor.lua`, `tests/test_lane_visibility.lua`.

**Interfaces:**
- Produces: `NS.LaneAnchor.Apply(laneKey)`, `NS.LaneAnchor.UNIT_FRAMES = { player = {"ElvUF_Player","SUFUnitplayer","CellSoloFramePlayer","PitBull4_Frames_Player","UUF_Player","PlayerFrame"}, pet = {"ElvUF_Pet","SUFUnitpet","CellSoloFramePet","PitBull4_Frames_Pet","UUF_Pet","PetFrame"} }` (verify names against each addon at execution time and adjust), `NS.LaneAnchor.ResolveHost(laneKey) -> frame|nil, reason`, `NS.LaneAnchor.SetUnlocked(bool)` (Edit Mode `EventRegistry` "EditMode.Enter/Exit" + `/kct unlock` overlay, as CastTrail), and `NS.LaneVisibility.ShouldShow(laneKey, ctx) -> bool`, where `ctx = {inCombat, hasTarget, instanceType, isDelve, mounted, inVehicle, petBattle, resting, secondsSinceCombat}`. Also `NS.LaneVisibility.Alpha(laneKey, ctx)`.

- [ ] **Step 1: Write the tests.** Anchor: `free mode uses saved point`; `dock pet under player follows player`; `dock cycle (player→pet while pet→player) is refused and prints once`; `unit-frame mode picks the first existing frame in order`; `missing frame falls back to free and prints one diagnostic`; `strata follows host when strata="HOST"`; `explicit strata (e.g. LOW) overrides the host in unit-frame mode`; `level offset adds to the relative base`. Visibility: one case per `show` mode, one per `where` key, mounted, vehicle, pet battle and resting hides; `hideAfter` window; `forever: delve/arena keys absent from the defaults the Lanes page reads` (asserted again in 1.4).
- [ ] **Step 2–4: FAIL → implement → green.** Visibility re-evaluates on `PLAYER_REGEN_*`, `ZONE_CHANGED_NEW_AREA`, `PLAYER_MOUNT_DISPLAY_CHANGED`, `UNIT_ENTERED/EXITED_VEHICLE`, `PET_BATTLE_OPENING_START/CLOSE`, `PLAYER_UPDATE_RESTING`, `PLAYER_TARGET_CHANGED`. Register only while some lane uses the rule. **Step 5: Commit** `feat(lanes): free, docked and unit-frame anchoring with visibility rules`.

### Task 1.4: Lanes settings page

**Files:** Create `settings/Lanes.lua` (pattern: `../PanelMaster/settings/PanelEditor.lua` and `PanelEditorTabs.lua`, the entity dropdown on top and tabs below). Test: `tests/test_lanes_page.lua`.

**Interfaces:**
- Consumes: `NS.RegisterTabbedPage`, the `lanes.<key>.*` paths from 1.1, `NS.LaneRender.Apply`, `NS.LaneAnchor.Apply`.
- Produces: the page `Lanes` with dropdown values `{"player","pet"}` (labels Player and Pet) and tabs `general, size, icons, bg, ticks, vis, ignore` (labels as in spec §4). Every control binds to `lanes.<selected>.<key>`. A live preview (a LaneRender instance in the General and Size tabs). "Copy settings from lane" and "Reset lane…" with confirmation.

- [ ] **Step 1: Write the tests.** `switching dropdown rebinds every control to lanes.pet.*`; `all seven tabs exist`; `copy from player copies everything but anchor and label`; `reset lane restores defaults for that lane only`; `forever profile: no delve or arena rows on the Visibility tab`; `Size and position tab has Frame strata (BACKGROUND/LOW/MEDIUM/HIGH/DIALOG, + Match host in unit-frame mode) and Frame level offset 0–50`; `ignore tab add by ID, by name, remove, reset to seed`; `slash: /kct lane pet off disables the pet lane`, `/kct ignore add 2649 pet`.
- [ ] **Step 2–4. Step 5: Commit** `feat(settings): Lanes page with lane dropdown and seven tabs`.

### Task 1.5: /kct probe

**Files:** Create `modules/Probe.lua`. Test: `tests/test_probe.lua`.

**Interfaces:**
- Produces: `NS.Probe.Report() -> {lines…}`, shown in the debug console (copyable), and `/kct probe` (with `start` arming in-combat sampling, the default arming it automatically for the next combat). **Never register `COMBAT_LOG_EVENT_UNFILTERED`**: it is protected for addons on Forever (ADDON_ACTION_FORBIDDEN, owner's BugGrabber report 2026-11-10; `pcall` does not catch a forbidden action) and on Retail. The report states "combat log: protected, not used". Add a test `probe never registers COMBAT_LOG_EVENT_UNFILTERED`. The report covers everything KCTProbe did, except the combat log (the client line, the `C_DamageMeter` function list, availability, enums, sessions, player and pet sources, the combat log, cast secrecy counts, in-combat meter secrecy samples at +5 s and +2 s after combat) **plus**: `pet is separate source: yes/no` (pet GUID source non-empty while the player source excludes pet spells), and a `pace pet-fill anchor` check (it builds two hidden StatusBars, anchors bar B's left to bar A's fill texture right, and reports whether `SetPoint` raised).

- [ ] **Step 1: Write the tests.** `report runs with no C_DamageMeter`; `report lists the 8 functions with mock meter`; `in-combat samples recorded via kit combat toggle`; `secret values reported as <secret>, never tostring'd`.
- [ ] **Step 2–4. Step 5: Commit** `feat: /kct probe for in-game API and secrecy checks`.

### M1 checkpoint
- [ ] Green gate on both profiles, then `git push`. Ledger row M1 done. Tell the owner `/kct probe` is ready (via the final run report, without blocking).

---

## Milestone 2 — Fights

### Task 2.1: Meter

**Files:** Port `modules/Meter.lua` from DpsRace (and `tests/mock_meter.lua`). Test: `tests/test_meter.lua`.

**Interfaces:**
- Produces: `NS.Meter.IsAvailable() -> bool, reason`, `NS.Meter.SessionAfter(t) -> sessionID|nil`, `NS.Meter.ReadLive(sessionID|nil) -> { player = {total, dps, maxAmount, spells={{spellID,total,dps}…}} | nil, pet = {…}|nil }` (all values **opaque**), `NS.Meter.ReadFinal(sessionID) -> { duration, player={total, spells}, pet={total, spells}|nil, merged={total, dps, spells={{spellID,total,isPet}…}} } | nil` (plain, out of combat only; `nil` while any value is secret), `NS.Meter.ReadEnemies(sessionID) -> {{name, creatureID, total}…}` (plain, sorted desc, out of combat), and `NS.Meter.ResolvePet() -> guid|nil`. **Seam (spec §12):** `NS.Meter.PET_SEPARATE = true`. When it's false, `ReadFinal` tags pet spells with `NS.Casts.PetSpellSet()` instead of reading a pet source.

- [ ] **Step 1: Tests.** `ReadLive returns opaque player and pet tables`; `ReadLive with no pet GUID returns pet=nil`; `ReadFinal merges player+pet totals and marks isPet`; `ReadFinal returns nil while values are secret`; `ReadEnemies sorts by damage taken`; `PET_SEPARATE=false path tags by cast set`; `amountPerSecond nil → dps computed as total/duration in ReadFinal`.
- [ ] **Step 2–5.** Commit `feat(fights): meter reader with player and pet sources`.

### Task 2.2: Fight state machine + Watchers

**Files:** Create `modules/Fight.lua` and `modules/Watchers.lua` (adapted from DpsRace `Race.lua` and `Watchers.lua`, without arming). Test: `tests/test_fight.lua`.

**Interfaces:**
- Produces: `NS.Fight.STATE = {IDLE="idle", COMBAT="combat", SETTLING="settling"}`, `NS.Fight.Current() -> fight|nil` (`{id, sessionID, startT, firstHitT, encounter, snapshot}`), and these bus messages: `FIGHT_STARTED(fight)`, `FIGHT_TICK(fight)` (4 Hz while in combat, for the HUD), `FIGHT_ENDED(fight, final|nil, reason)` with reason ∈ `"final"|"lost"`. Constants `NS.Constants.FIGHT = { GRACE = 4, SETTLE = 2, TICK = 0.25 }`.
- Rules (spec §5): a fight binds to the meter session that appears at or after combat entry. FD/Vanish re-entry within GRACE with the same session continues the fight. A new session with the same active `encounterID` is merged after combat. A meter reset (sessions list shrinks or the bound session disappears) makes the fight `lost`. Settling ends after SETTLE s with no `DAMAGE_METER_COMBAT_SESSION_UPDATED`. Watchers register events only for the current state (idle: `PLAYER_REGEN_DISABLED`, `ENCOUNTER_START`).

- [ ] **Step 1: Tests.** `normal combat → started, ticks, ended final`; `FD within grace keeps one fight`; `FD beyond grace ends the first fight`; `encounter split sessions merge after combat`; `meter reset mid-fight → lost`; `settle waits for quiet`; `idle registers only the idle events`; `disabled addon registers nothing`.
- [ ] **Step 2–5.** Commit `feat(fights): fight state machine bound to meter sessions`.

### Task 2.3: Identity, dummies, board key

**Files:** Create `modules/Identity.lua` and `defaults/Dummies.lua` (from DpsRace `defaults/Dummies.lua` plus `DummyList.lua`, split into `Retail` and `Forever` lists, where Forever is empty-by-decision with a comment if no IDs are known). Test: `tests/test_identity.lua`.

**Interfaces:**
- Produces: `NS.Identity.Snapshot() -> snap` (combat start, secret-safe; who + target), `NS.Identity.Resolve(fight, final, enemies) -> identity`. The identity is `{ encounterID?, encounterName?, difficultyID, difficultyName, instanceType ("none"|"party"|"raid"|"pvp"|"arena"|"scenario"), instanceName, isDelve, delveTier?, keystoneLevel?, pvpBracket?, content ("raid"|"dungeon"|"mplus"|"delve"|"bg"|"arena"|"world"|"dummy"|"scenario"), targetName, targetCreatureID?, otherTargets (int), isBoss }`, plus `NS.Identity.BoardKey(identity) -> string|nil` in the format `"e:<encounterID>:<difficultyID>"` or `"c:<creatureID>:<difficultyID>"`, with `":k<level>"`, `":d<tier>"` or `":p<bracket>"` appended. It returns `nil` when the target is unknown.

- [ ] **Step 1: Tests.** `boss fight key e:3176:15`; `M+ trash key carries :k12`; `delve key carries :d8 (retail)`; `bg key carries bracket`; `open world key has no qualifier`; `dummy creature → content dummy`; `no enemies and no snapshot → Unknown target, key nil`; `forever: delve/mplus fields never set`; `two-word Forever names handled` (client-quirks §5).
- [ ] **Step 2–5.** Commit `feat(fights): fight identity, content and board keys`.

### Task 2.4: CastCodec, Casts, Usage, Stats, Loadouts

**Files:** Create `modules/CastCodec.lua`, and port `modules/Casts.lua`, `Usage.lua`, `Stats.lua` and `Loadouts.lua` from DpsRace. Test: `tests/test_cast_codec.lua`, `tests/test_casts.lua`, `tests/test_usage.lua`.

**Interfaces:**
- Produces: `NS.CastCodec.Encode(casts) -> string` and `Decode(string) -> casts`, where `casts = {{t=number (s from fight start, 0.1 s resolution), spellID=int, unit="player"|"pet", interrupted=bool}…}`. The format is delta-encoded base-36 tokens separated by `;`, and the encoder must keep a 250-cast fight under 2.5 KB. Also `NS.Casts.Begin(fightID)`, `NS.Casts.Record(unit, spellID, t, flags)`, `NS.Casts.Finish(fightID) -> casts`, `NS.Casts.PetSpellSet() -> {[spellID]=true}`, `NS.Usage.Snapshot()`, `NS.Usage.Detect(fight, casts) -> {{itemID|spellID, kind, times={…}}…}`, `NS.Stats.Read() -> stats`, and `NS.Loadouts.Store(importString) -> hash` and `Get(hash)`.

- [ ] **Step 1: Tests.** `codec round-trips 0.1 s times and flags`; `250 casts packs under 2.5 KB`; `secret spellID cast is dropped from the record, not stored as nil-key`; `pet casts tagged unit=pet`; `usage detects potion from cast + bag delta`; `loadout dedupes by hash`.
- [ ] **Step 2–5.** Commit `feat(fights): packed cast lists, usage, stats and loadouts`.

### Task 2.5: Recorder, Filters, Bests, Retention

**Files:** Create `modules/Recorder.lua` (adapted from DpsRace), `modules/Filters.lua`, `modules/Bests.lua` (adapted) and `modules/Retention.lua`. Modify `defaults/Profile.lua` (`history.minLength=30`, `history.bossesOnly=false`, `history.content={raid=true,dungeon=true,mplus=true,delve=true,bg=true,arena=true,world=true,dummy=true,scenario=false}`, `history.days=7`, `history.keepBests=true`, `history.maxFights=500`). Test: `tests/test_filters.lua`, `tests/test_bests.lua`, `tests/test_retention.lua`, `tests/test_record.lua`.

**Interfaces:**
- Consumes: `FIGHT_ENDED`, `NS.Meter.ReadFinal`, `NS.Identity.*`, `NS.Casts.Finish`, `NS.CastCodec.Encode`, `NS.Usage`, `NS.Stats`, `NS.Loadouts`.
- Produces: `db.global.fights = { [id] = record }` and `db.global.fightOrder = {id…}` (newest first). The record has schema version `CT_SCHEMA = 1` and these fields (spec §5): `id, t (time()), duration, who={name, realm, class, specID, specName, ilvl, petName?, petFamily?, client}, identity, boardKey, damage={merged, player, pet}, dps, meterDps?, spells={{spellID,total,isPet}…}, casts (packed string), gear={slot=itemString}, stats, loadout (hash), usage, note?, build, version, status ("final")`. Also `NS.Recorder.Get(id)`, `NS.Recorder.All() -> iterator newest-first`, `NS.Recorder.Delete(id)`, `NS.Recorder.SetNote(id, text)`, bus messages `FIGHT_SAVED(record)`, `FIGHT_SKIPPED(fight, reason)` (reason ∈ `"short"|"filtered"|"lost"|"unknown"`), `FIGHTS_CHANGED`, `NS.Filters.Passes(identity, duration) -> bool, reason`, `NS.Bests.For(record) -> bestRecord|nil` (same character × spec × boardKey, excluding the record itself when `exclude=true`), `NS.Bests.IsBest(record) -> bool`, `NS.Bests.BestCurve(boardKey, character, specID) -> recordID|nil`, `NS.Retention.Purge(now) -> removedCount`, and `NS.Retention.EstimateBytes() -> int`.

- [ ] **Step 1: Tests.** `22 s fight skipped as short`; `bossesOnly drops non-encounter`; `content toggle drops world`; `forever: mplus/delve/arena filter keys absent`; `best per character×spec×boardKey`; `unknown target never a best`; `purge removes >7 days except bests`; `purge of 600 fights keeps bests and caps at 500`; `days=0 keeps forever`; `5-min raid record < 6 KB` (sample record serialized with the kit's SV serializer); `reload mid-fight leaves store valid` (no partial record written before FIGHT_ENDED final); `no secret reaches the record` (feed secret fields, assert absent).
- [ ] **Step 2–4.** The purge runs on `PLAYER_LOGIN`, on a 24 h `C_Timer`, and from `/kct purge`. **Step 5: Commit** `feat(fights): recording filters, store, bests and retention`.

### Task 2.6: Slices

**Files:** Port `modules/Slices.lua`. Test: `tests/test_slices.lua` (port).

**Interfaces:** `NS.Slices.Begin(fightID, expectedLen|nil)`. Since fight length is unknown, buckets grow: one per `max(1, floor(elapsed/60)+1)` s up to 60 buckets, with re-bucketing by merging adjacent buckets, which is done **only** on plain values, never secrets. Because in-combat values are secret, Slices stores the opaque totals per fixed 2 s step during combat and the chart draws the last ≤ 60 steps live. After combat, the chart for the stored fight uses the opaque list as-is (drawn by C-side bars) in this session only. Also `NS.Slices.Record(fightID, t, opaqueTotal)` and `NS.Slices.Get(fightID) -> {step, values}`.
- [ ] **Steps:** port the DpsRace tests and adapt them to open-ended length. Commit `feat(fights): in-session damage slices`.

### M2 checkpoint
- [ ] Green gate, then `git push`. Ledger M2 done.

---

## Milestone 3 — HUD

### Task 3.1: HUD shell + states

**Files:** Port `modules/Format.lua`, `Style.lua`, `Sizing.lua`, `Hud.lua` and `Hud_States.lua`, keeping only these states: `hidden`, `live`, `over` (with sub-flags `newBest`, `saved`, `skipReason`) and `noBest` (live with no pace). Modify `defaults/Profile.lua` (`hud.show="auto"` (`"auto"|"always"|"toggle"`), `hud.fadeAfter=8`, `hud.holdOnMouse=true`, `hud.instancesOnly=false`, `hud.paceAgainst="best"` (`"best"|"last"|"none"`), `hud.paceRange=1.5`, `hud.overCard=true`, `hud.showSkipReason=true`, `hud.width=300`, `hud.scale=1`, and layout toggles). Test: `tests/test_hud_states.lua`.

**Interfaces:**
- Consumes: `FIGHT_STARTED/TICK/ENDED`, `FIGHT_SAVED/SKIPPED`, `NS.Meter.ReadLive`, `NS.Bests.For`.
- Produces: `NS.Hud.Show(reason)`, `NS.Hud.Hide()`, `NS.Hud.Toggle()`, `NS.Hud.State() -> string`, `NS.Hud.Pin(bool)`.
- [ ] **Step 1: Tests.** `auto: hidden → live on FIGHT_STARTED's first hit`; `over card after FIGHT_ENDED final with saved chip`; `skip reason chip on FIGHT_SKIPPED short`; `fades after hud.fadeAfter unless mouse over or pinned`; `toggle mode never auto-shows`; `instancesOnly hides in world`; `noBest when Bests.For is nil hides pace`.
- [ ] **Step 2–5.** Commit `feat(hud): HUD shell and states`.

### Task 3.2: Chart, pace, breakdown, appearance

**Files:** Port `modules/Hud_Chart.lua`, `Hud_Best.lua` (pace data), `Hud_Breakdown.lua`, `Hud_Appearance.lua` and `Hud_Tips.lua`. Test: `tests/test_hud_chart.lua`, `tests/test_hud_pace.lua`, `tests/test_hud_breakdown.lua`.

**Interfaces:**
- Produces: the breakdown lists player rows then pet rows (the meter's order). Each bar uses `SetMinMaxValues(0, player.maxAmount)` and `SetValue(spell.total)`. Pet rows get the paw (LibKa0s icon or a bundled `media/icons/paw.tga`) and use `hud.spells.petColor`. Pace: `NS.HudBest.Curve(bestRecordID) -> {damageAt(t)}` comes from the best's **session Slices if present**, otherwise linear average pace (merged dps × t). The bar has the player fill as a StatusBar plus the pet fill as a StatusBar anchored to the player fill texture's right edge. **Seam:** `NS.Hud.PACE_PET_FILL = true`; when it's false, the bar shows player-only damage against the best's player damage. Appearance covers every key in the mockup's DPS HUD tabs (Layout, Clock and figures, Damage chart, Spell rows, Window) under `hud.*`.
- [ ] **Step 1: Tests.** `breakdown never sorts or computes in combat (mock secret values)`; `pet rows carry paw and pet color`; `pace uses best slices when present else linear`; `pace pet fill anchored to player fill texture`; `PACE_PET_FILL=false shows player-only`; `chart cooldown icons for base CD ≥ 29 s`; `every hud appearance key applies (one assertion per key via Apply)`.
- [ ] **Step 2–5.** Commit `feat(hud): damage chart, pace bar and spell breakdown`.

### Task 3.3: DPS HUD settings page

**Files:** Create `settings/Hud.lua` with tabs `behavior, layout, clock, chart, spells, window` (mockup §4). Test: `tests/test_hud_page.lua` (`six tabs`, `every hud.* default has a control`, `changes apply live via Hud.Apply`).
- [ ] **Steps**, then commit `feat(settings): DPS HUD page`.

### M3 checkpoint
- [ ] Green gate, then `git push`. Ledger M3 done.

---

## Milestone 4 — Results

### Task 4.1: Results shell, Source, Table, Tips

**Files:** Port `modules/Results.lua`, `Results_Source.lua`, `Results_Table.lua`, `Results_Tips.lua`, and `Results_Runs.lua` renamed to **`Results_Fights.lua`**. Modify defaults (`results.view = {character="current", spec="all", content="all", board="all", difficulty="all", days=7, bossesOnly=false, group="board"}`). Test: `tests/test_results_table.lua`.

**Interfaces:** columns `date, clsSpec, character, ilvl, target, content, len, damage, dps, delta`. Groups are `board` (encounter or target + difficulty + qualifier, the default), `character`, `spec`, `content` and `none`. Delta is against the best in the group (with no grouping, the best in the list), with a trophy on the best. Filters are faceted (options computed from the fights that pass the other filters), and Save view persists `results.view`. Produces `NS.Results.Open(fightID|nil)`, `NS.Results.Toggle()`, `NS.ResultsSource.Use(sample|nil)`, and `NS.ResultsFights.Rows(view) -> rows`.
- [ ] **Step 1: Tests.** `default view: current character, last 7 days, grouped by board`; `delta vs group best`; `bossesOnly filter`; `forever: content facet lacks mplus/delve/arena`; `table builds 500 rows via pooled rows`; `right-click menu has Note, Share, Compare With This Fight, Delete`.
- [ ] **Step 2–5.** Commit `feat(results): Results window, fight table and filters`.

### Task 4.2: Detail, Share

**Files:** Port `modules/Results_Detail.lua`, `Share.lua`, `Results_Loadout.lua` and `Results_Usage.lua` (detail part). Test: `tests/test_results_detail.lua`, `tests/test_share.lua`.

**Interfaces:** the detail shows the header line (spec §7), boxes (Damage, DPS, Meter DPS, Delta or "Leads by" + New best trophy), the chart (from `NS.Slices.Get(id)`, or "Damage chart is only kept for fights recorded this session" when it's missing), the breakdown (merged, percentages, pet paw), Gear and Talents (View / Copy), Usage (Edit), and the buttons Timeline / Compare vs best / Add note / Share / Delete (with confirm). `NS.Share.Line(record, withTalents) -> string`, matching mockup §9's party line.
- [ ] **Step 1: Tests.** `detail shows Leads by on best`; `missing slices shows the session-only note`; `pet spells tagged`; `delete asks to confirm, then FIGHTS_CHANGED`; `share line format and length ≤ 255`; `talents link appended when enabled`.
- [ ] **Step 2–5.** Commit `feat(results): fight detail and share`.

### Task 4.3: Timeline + TimelineData

**Files:** Port `modules/Results_Timeline.lua` and `Results_TimelineData.lua`. Test: `tests/test_timeline.lua`.
**Interfaces:** `NS.ResultsTimelineData.Build(record, compareRecord|nil, opts={showPet}) -> {rows={{spellID, cd?, a={t…}, b={t…}}…}, stripA, stripB, len}`, with rows ordered so long cooldowns (base CD ≥ 29 s) come first, then by cast count. The pet-ability toggle, the zoom/pan controls (buttons, Ctrl+wheel, Shift+wheel) and the "?" tooltip are as in DpsRace.
- [ ] **Tests:** `rows order long CDs first`; `pet toggle hides pet rows`; `decodes packed casts`; `compare lanes align to their own fight start`. Commit `feat(results): ability timeline`.

### Task 4.4: Compare, Gear view, Loadout, Usage edit

**Files:** Port `modules/Results_Compare.lua`, `Results_Gear.lua` and the edit flow in `Results_Usage.lua`. Test: `tests/test_compare.lua`, `tests/test_gear.lua`, `tests/test_usage_edit.lua`.
**Interfaces:** `NS.ResultsCompare.Pick(record) -> other` (the best, or the runner-up if this is the best, or the session pick from "Compare With This Fight"), and `NS.ResultsCompare.Spells(a, b) -> rows {spellID, aTotal, bTotal, deltaPct}`.
- [ ] **Tests:** `compare vs best, runner-up when best`; `session pick overrides until cleared`; `gear changed slots detected`; `different loadout mark`; `usage edit save persists; never-show list hides`. Commit `feat(results): compare, gear view and usage edit`.

### Task 4.5: History settings page

**Files:** Create `settings/History.lua` with tabs `recording, retention, results, usage` (mockup §4). The Retention tab shows the fight count and `NS.Retention.EstimateBytes()`, plus "Purge now…" with confirm. Test: `tests/test_history_page.lua` (`four tabs`, `forever: no delve/arena/mplus rows`, `purge now confirm`).
- [ ] **Steps**, then commit `feat(settings): History page`.

### M4 checkpoint
- [ ] Green gate, then `git push`. Ledger M4 done.

---

## Milestone 5 — Polish, docs, verification

### Task 5.1: Test mode, Sim, MockFights

**Files:** Port `modules/MockRotations.lua` (BM hunter + pet rotation for Retail, and a Forever hunter rotation using Forever spell IDs, picked per client), and `MockRuns.lua` renamed to **`MockFights.lua`** (a sample history of about 40 fights across content types, as in mockup §5). Port `Preview.lua` and `Sim.lua` (one 45 s made-up fight that drives LaneCasts, the HUD and then Results; scenarios `newbest`, `behind`, `first`, `short`, `lost`). Test: `tests/test_preview.lua`, `tests/test_sim.lua`.
- [ ] **Tests:** `test mode fills lanes, HUD and Results with sample strip, nothing written to db`; `entering combat ends test mode`; `sim newbest ends with New best chip`; `sim short ends Not saved`. Commit `feat: test mode and sim`.

### Task 5.2: Bindings, Diagnostics, skin surfaces

**Files:** Create `Bindings.xml` (Toggle DPS HUD, Toggle Results window, Toggle lanes) and fill the General ▸ Keybindings tab. Port `modules/Diagnostics.lua`, and port `tests/skin_surfaces.lua` and the skin tests so that every window (HUD, Results, Timeline, Compare, Gear, Lanes) is covered. Test: `tests/test_bindings.lua`, `tests/test_diagnostics.lua`, `tests/test_skin_surfaces.lua`.
- [ ] Commit `feat: key bindings, diagnostics and skin coverage`.

### Task 5.3: Docs set

**Files:** `README.md` (canonical player-facing structure per documentation-§ at the pin, like DpsRace's: usage, settings, FAQ including the secret-value limits, troubleshooting, reporting a bug, version history row `0.1.0 | Unreleased`, credits), `docs/ARCHITECTURE.md` (module map, **per-client feature table**, bus messages, event wiring per state, secret-value invariants, documented deviations — expected: none, or roster registration pending), `docs/testing.md`, `docs/smoke-tests.md` (every check names its client, absent-feature checks on Forever, plus the **in-game verification list**: `/kct probe` on both clients in combat with pet; pet source split; pace pet fill; FD mid-boss; unit-frame anchors with ElvUI/SUF/Blizzard), `docs/schema.md`, `docs/data-flow.md`, `docs/known-limitations.md`, `docs/midnight-quirks.md` (start with the probe findings), `CHANGELOG.md` (Unreleased), `DEPENDENCIES.md`, and `CLAUDE.md` (final).
- [ ] Run `dev-copilot:sync-docs`-style checks by hand: every module in the TOC is in ARCHITECTURE, and every slash verb is in the README. Commit `docs: v0.1.0 documentation set`.

### Task 5.4: Automated-test bundle, complexity, whole-branch review

- [ ] Run `lizard -C 15 -x "./libs/*" -x "./tests/_kit/*" .` and refactor any function above 15.
- [ ] Produce the automated-test bundle under `docs/automated-tests/<YYYYMMDD-HHMMSS>/` per the playbook `AUTOMATED_TESTS.md` read at the pinned standard (`git -C ../WowAddonStandards show 4e94ad1:AUTOMATED_TESTS.md`), and roll up `RESULTS.md`.
- [ ] Whole-branch review by a fresh reviewer (spec compliance, secrets, taint, clients-§4 absence, perf). Fix confirmed findings, then run the green gate.
- [ ] Commit `test: first automated-test bundle and review fixes`.

### Task 5.5: Roster issue, smoke hand-off, final push

- [ ] File `gh issue create -R tusharsaxena/WowAddonStandards --title "Register Ka0s Combat Trail in the roster" --body "<row: name, path ../../CombatTrail/, repo URL, Clients: Retail · Forever, launcher entries (Enabled · Locked · Test mode · Sim mode · Show window), test verb test, placement next to Test mode>"`. Deferred because other agents are editing that repo during this run.
- [ ] `git push`. Ledger 5.5 done. Report to the owner: the branch is ready, the smoke-test checklist and the `/kct probe` steps are written down, and the merge waits for their go-ahead.
- [ ] After the owner approves the merge (a separate step): merge to `main`, push, then delete the feature branch (local + remote), any worktrees and stashes from this run, and the throwaway `_forever_/Interface/AddOns/KCTProbe`.
