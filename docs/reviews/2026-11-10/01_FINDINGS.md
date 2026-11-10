# 01 — Findings: Combat Trail v0.1.0 branch review

**Verdict: minor issues.** I found no secret-value violation on any combat path and no registration of `COMBAT_LOG_EVENT_UNFILTERED`. Retail-only features are absent on Forever wherever I looked. There is one High functional bug (F-001, a cast-list cooldown cache poisoned by a secret read) and a set of Medium hot-path cost and robustness items. **Nothing below was measured today** (see the Measurement run): every finding is a static read and says so.

**Resolved scope:** `branch` mode. The review covers `feat/2026-11-10-combat-trail-v0.1.0` against `main`, merge base `08b650b62bd3598ee6d1f2ff9740ddc0a5e45409`, 49 commits. Authored diff excluding `libs/` and `tests/_kit/`: 165 files, +43,751 lines (`git diff --stat 08b650b...HEAD -- . ':(exclude)libs' ':(exclude)tests/_kit'`). The diff is essentially the whole addon, so I prioritized the focus areas: secret values, taint, clients-§4 on Forever, the hot paths (UNIT_SPELLCAST, OnUpdate, FIGHT_TICK, HUD render) and in-game Lua errors. I read these files whole or in their hot sections: `core/Secrets.lua`, `core/Compat.lua`, `core/CoreSetup.lua`, `core/Constants.lua`, `core/PerfSetup.lua`, `core/LauncherSetup.lua`, `Bindings.xml`, `modules/{Casts,LaneCasts,LaneRender,LaneAnchor,LaneVisibility,Meter,Fight,Watchers,Slices,Hud,Hud_Chart,Hud_Best,Hud_Breakdown,Hud_States,Format,Usage,Loadouts,Stats,Identity,Recorder,Bests,Retention,Probe,Share,Sim}.lua`. I did **not** read in depth: the `Results_*` window family, `settings/*` pages, `core/SkinSetup.lua`, `modules/Style.lua`, `modules/MockFights.lua`, `modules/Preview.lua` beyond its combat guard, or the docs set beyond `docs/ARCHITECTURE.md`, `docs/performance.md` and `docs/perf-analysis/README.md`.

**Profile:** the detector (`dev-copilot-profile`, including its plugin-cache path) needed an approval this session did not have. Per the review spec this run is therefore treated as **`profile=generic`**, and no WoW overlay was read. The caller passed `profile=wow kind=addon`. That hint is not contradicted by anything observed, but it was not confirmed by my own run.

**Standard:** `git -C ../WowAddonStandards show 4e94ad1:<path>` also needed approval, so I did **not** read the pinned standard text. Where a finding touches clients-§4 or another rule, the reference is this repo's own reading of it (`docs/ARCHITECTURE.md` › *Per-client features (clients-§4)*), and the check against the standard's wording is **unverified**.

## Measurement run

| Suite | Command | Result |
|---|---|---|
| Tests, Retail kit profile | `~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua` | **skipped (the tool call needed approval; not granted in this session)** |
| Tests, Forever kit profile | `KA0S_KIT_CLIENT=forever ~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua` | **skipped (same)** |
| Lint | `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` | **skipped (same; `luacheck --version` and `lua -v` also needed approval)** |
| Complexity | `lizard` (via `ka0s-bounded`) | **skipped (same)** |
| Perf offline | `tests/perf.lua` | **not present** (`docs/performance.md:42`: "There is no `tests/perf.lua` yet") |

- I also had nowhere to write scratch output: `/tmp` is outside the session's writable roots. No result was inferred from a previous run.
- **Committed artifacts read but not re-measured:** the plan ledger's per-task counts (for example `docs/superpowers/plans/2026-11-10-combat-trail-v0.1.0.md:27`: "272 pass / 2 declared skips on retail and on forever, luacheck 0/0") and `docs/test-cases.md`, which `docs/ARCHITECTURE.md:186` calls the "authoritative pass count". **These are unverified today.** There is no disagreement to report, only no fresh evidence.
- **No committed perf numbers exist.** `docs/performance.md` holds no capture, and `docs/perf-analysis/README.md:32`'s index reads `| (none yet) | | | |`. Every `[perf]` finding below is therefore **unmeasured**.

### Census (all from `git ls-files` scope via `git grep`, vendored paths excluded)

- `git grep -n "COMBAT_LOG_EVENT" -- . ':(exclude)libs' ':(exclude)tests/_kit'` finds **0 registrations**. The code hits are all comments (`modules/Casts.lua:11`, `modules/LaneCasts.lua:39`, `modules/Probe.lua:25`, `modules/Watchers.lua:21`); the rest are docs and two tests.
- `git grep -n -E "RegisterEvent|RegisterUnitEvent|SafeRegister" -- modules core settings` finds **6 files that register game events**: `core/SkinSetup.lua:492`, `modules/LaneAnchor.lua:508`, `modules/LaneCasts.lua:279`, `modules/LaneVisibility.lua:302,304`, `modules/Probe.lua:481-483` and `modules/Watchers.lua:105`. `core/CoreSetup.lua:62-78` holds the definitions. This number is used by F-008.

## What was checked and is clean (no finding)

- **Secret values.** `core/Secrets.lua` is the only inspector. Every live meter value in `modules/Meter.lua` `ReadLive`/`livePart` (lines 546-587) is copied untouched. The HUD hands values only to `StatusBar:SetMinMaxValues/SetValue` (`Hud_Chart.lua:384-390`, `Hud_Breakdown.lua:243-244`, `Hud_Chart.lua:591-596`) and to `Format.Number`. `Format.Number` itself only nil-tests the formatter's output (`Format.lua:99`, `if ok and out ~= nil then return out end`). `Slices.Record` asks only `total == nil` (`Slices.lua:147`). The lanes push a secret spell ID only through `pcall(NS.Compat.SpellTexture, spellID)` (`LaneCasts.lua:142`). A secret castGUID is only nil-tested (`LaneCasts.lua:221`, `local secretGUID = guid == nil and castGUID ~= nil`). I found no `tostring`, comparison, truth test, `#` or table key on a possibly secret value on the live paths I read.
- **Taint.** No secure template, no `hooksecurefunc`. Key bindings are `CLICK` bindings on plain, hidden, non-secure buttons (`core/LauncherSetup.lua:23-29`). A lane anchors **itself** to a unit frame and never writes the host (`LaneAnchor.lua:272`, `frame:SetPoint(point, host, relPoint, dx, dy)`), with `IsForbidden` checked in `pcall` (`LaneAnchor.lua:128-131`).
- **clients-§4 (as this repo reads it).** Delve, Mythic+ and arena are gated through `Compat.ForClient({ "retail" })`: `Compat.lua:260`, `:315` and `:355`, `Identity.lua:178` and `:254`, `defaults/Profile.lua:16,27`, `settings/Lanes.lua:103` and `settings/History.lua:80-83`. Unverified against the standard text (see header).
- **`COMBAT_LOG_EVENT_UNFILTERED`** is never registered (census above).

---

## High

### F-001 `[correctness]` The cast list caches a secret base-cooldown read as "no cooldown" for the rest of the session
- **Where:** `modules/Casts.lua:136-145`, specifically `:139-141`:
  `local ok, v = pcall(NS.Compat.SpellBaseCooldown, id)` / `ms = ok and Secrets.PlainNumber(v) or nil` / `if not ms then ms = false end`.
  It is reached in combat from `Casts.Live` (`Casts.lua:168-173`). That runs `listOf` → `local ms = cooldown(e.id)` (`Casts.lua:157`), called by the HUD every second (`Hud.lua:504`, `else casts, spells = NS.Casts.Live(cur.id) end`; `Hud.lua:70`, `Hud.CAST_READ = 1`).
- **Problem:** a base cooldown read in combat that comes back secret becomes `PlainNumber(v) == nil`, so the cache stores `false`. `cooldown()` never asks again (`if ms == nil then`). The lanes' own cache does the opposite on purpose: `LaneRender.lua:248`, `if not ok or Secrets.IsSealed(v) then return nil end`, with the header at `LaneRender.lua:25-26`: "a secret is neither used nor cached".
- **Impact:** every spell first heard while the HUD is open in combat loses its cooldown for the whole session. Concretely:
  - the stored record's `cooldowns` omits it (`Recorder.lua:255`, `local casts, cooldowns = NS.Casts.Finish(fight.id)`);
  - the HUD chart's long-cooldown icons and burst columns miss it (`Hud_Chart.lua:162`, `local ms = spells[c.spellID]`);
  - the ability timeline's long-cooldown-first ordering falls back to "by count" (`Casts.lua:246-253`).
- **Failure scenario:** a Hunter has `hud.show` on "auto" (the default). They pull and cast Bestial Wrath (2 min) for the first time this session. While the HUD's 1 Hz `Casts.Live` runs, `GetSpellBaseCooldown` answers secret, so `cooldowns[19574] = false`. Combat ends and the record is written with no entry for 19574. The over card's chart shows no Bestial Wrath icon and no burst columns. This repeats for every later fight in the session, including out-of-combat recomputation, because the cache holds `false`.
- **Reachability:** any player with the HUD on screen during a fight on the default config, **if** the client answers `GetSpellBaseCooldown` secret in combat. This project already models that client behavior for the same call (`tests/test_lane_render.lua:204`, "a secret base cooldown is never compared or cached, and nothing raises"). It has not been verified in game.
- **Test gap:** `tests/test_casts.lua:271-282` covers only plain cooldowns. No Casts test feeds a secret one. The lane's twin of this rule is tested and the cast list's is not.
- **Confidence:** high that the code caches `false` on a secret read. Medium that the client actually returns a secret here. **Unverified** (no suite run, no in-game probe of this call).

## Medium

### F-002 `[perf]` Each lane push restyles the whole icon, re-resolves the label face and restacks every icon
- **Where:** `modules/LaneRender.lua:661-670`:
  - `styleIcon(f, st.cfg, labelFace(st.cfg))` (`:663`)
  - `setItem(f, item, st.cfg)` (`:664`)
  - `restack(st)` (`:667`)
  - `labelText(st, st.cfg)` (`:670`)
- **Problem:** on every cast, `styleIcon` (`:313-330`) re-runs the same work regardless of whether the settings changed:
  - two `pcall(S.Resolve, …)` and an LSM fetch (`iconEdge`, `:161-174`);
  - eight edge textures re-anchored (`placeEdges` ×2) and repainted, each through `tint`'s class-color and skin `pcall` (`:116-125`);
  - `paintMark`, two `SetFont`, `setTooltip`, `refreshName`.
  Then `setItem` repeats `wantsGlow` and `refreshName` (`:341-342`). `labelFace` does another `pcall` and LSM fetch. `restack` calls `SetFrameLevel` on up to 64 icons (`:370-376`). `labelText` calls `UnitExists` and `UnitName` (`LaneCasts.lua:351-352`).
- **Impact:** roughly a hundred widget and API calls per cast on the busiest event of the addon. That is per player cast **and** per pet cast. It works against the spec's "an idle lane costs nothing" budget for the active lane too.
- **Failure scenario:** a BM Hunter in a raid casts 2-3 spells a second, and the pet casts as well. Each one triggers a full restyle of a pooled icon that already carries the current style.
- **Reachability:** every cast with a lane enabled (both lanes on by default).
- **Confidence:** high on the call count by reading. **Unmeasured:** the `laneRender` perf bucket exists, but no capture is committed and none could be taken here.

### F-003 `[perf]` The HUD's 1 Hz cast read walks and copies the whole fight's cast buffer, and the chart re-lays every icon each time
- **Where:**
  - `modules/Casts.lua:148-163`: `listOf` builds a fresh `{ t, spellID, unit, interrupted }` per kept cast on every call.
  - `modules/Hud.lua:497-506` calls it every `Hud.CAST_READ` (1 s).
  - `modules/Hud_Chart.lua:454-462`: `if self.iconList == casts and self.iconN == n …` never matches a freshly built list, so `NS.Pool.ReleaseAll` (`:460-461`) re-acquires and re-anchors every cooldown icon each second.
- **Problem:** O(casts so far) allocation every second, growing with fight length, plus a full icon relayout that the identity-based cache was meant to avoid.
- **Impact:** GC churn and frame-time cost that scale with fight length. Long encounters (5-10 min, 1,000+ casts) pay the most.
- **Reachability:** any fight with the HUD open (default auto-show).
- **Confidence:** high by reading. **Unmeasured.**

### F-004 `[perf]` Combat entry runs four full client snapshots synchronously inside the `PLAYER_REGEN_DISABLED` dispatch
- **Where:** `FIGHT_STARTED` is sent from `Fight.begin` (`Fight.lua:337`) inside the Watchers event handler. The fight table itself takes `snapshot = snapshot()` (`Fight.lua:116`, which runs `Identity.Snapshot`). Then the receivers run:
  - `Usage.lua:366`, `lastFight.usageAfter = Usage.BagCounts() or false`
  - `Usage.lua:369`, `fight.usageSnap = Usage.Snapshot()`: all 6 bags' slots through `pcall(C_Container.GetContainerItemInfo)`, all 19 equipment slots, up to 255 auras (`Usage.lua:62`, `local AURA_LIMIT = 255`)
  - `Loadouts.lua:214`, `fight.loadout = Loadouts.Snapshot()`, including `C_Traits.GenerateImportString`
  - `Stats.lua:169`, `fight.stats = Stats.Read()` (about 25 calls)
- **Problem:** several hundred pcall'd client reads happen in the one frame where the pull starts. The bag walk runs twice when a previous fight was parked. A meter split mid-combat (`Fight.lua:299`) runs all of it again in combat.
- **Impact:** a one-frame spike at the pull, the moment players are most sensitive to stutter. The cost can't be attributed separately, because it sits inside the `fight` perf bucket (`PerfSetup.lua:36`) and no capture exists.
- **Reachability:** every combat entry on the default config.
- **Confidence:** medium (call count by reading; the actual milliseconds are **unmeasured**).

### F-007 `[error-handling]` Watchers records a rejected event as registered, then unregisters it unguarded
- **Where:** `modules/Watchers.lua:103-108`: `NS.SafeRegisterEvent(ensureTarget(), event, onEvent, NS.rejectedEvents)` followed by an unconditional `registered[event] = true`, and `:97-101`, `target:UnregisterEvent(event)` with no `pcall`.
- **Problem:** with an AceEvent target, CallbackHandler stores the callback **before** `OnUsed` calls `frame:RegisterEvent`. A name the client does not know therefore leaves a stored callback, while the pcall reports a rejection. On the next state change, `Sync` calls `UnregisterEvent`, CallbackHandler's `OnUnused` calls `AceEvent.frame:UnregisterEvent(name)` for a name the client does not know. The header promises the opposite (`Watchers.lua:19-21`: "an event name a client does not know costs only itself").
- **Impact:** a Lua error on the fight state machine's idle↔combat edge, every fight, on such a client. `Watchers.Suspend` → `UnregisterAllEvents` (`:113`) takes the same path.
- **Failure scenario:** a client build ships without `DAMAGE_METER_RESET`. The first combat registers it, gets rejected, and marks it registered. At settle → IDLE, `Sync` unregisters it and raises.
- **Reachability:** nobody on today's clients. All seven events exist on Retail and, per the owner's probe, on Forever. Only a client lacking one of `FIGHT_EVENTS` (`Watchers.lua:40-48`) hits it. Severity is capped at Medium.
- **Confidence:** low-medium. Whether `Frame:UnregisterEvent` raises on an unknown name is **unverified** here.

### F-008 `[tests]` The never-register-the-combat-log invariant is scanned in 3 of the 6 files that register events, and its registry check can pass vacuously
- **Where:**
  - `tests/test_fight.lua:494`, `for _, path in ipairs({ "/modules/Fight.lua", "/modules/Watchers.lua" }) do`
  - `tests/test_probe.lua:184`, `local f = io.open(T.root .. "/modules/Probe.lua", "rb")`
  - The registry loops (`test_fight.lua:491-493`, `test_probe.lua:178-180`) assert only that no recorded registration names the event, which also passes when nothing registered at all.
- **Problem:** per the census, `core/SkinSetup.lua`, `modules/LaneAnchor.lua`, `modules/LaneCasts.lua` and `modules/LaneVisibility.lua` also register events and no test scans them. `modules/Fight.lua` is scanned but registers nothing.
- **Impact:** a future `COMBAT_LOG_EVENT_UNFILTERED` registration in a lane or skin file stays green. On Forever that registration is `ADDON_ACTION_FORBIDDEN`, which `pcall` does not catch (plan, Task 1.5 notes).
- **Reachability:** test suite only. The shipped code is correct today (census: 0 registrations).
- **Confidence:** high.

### F-010 `[design]` The HUD paces against the combat-entry target's board, but the record is filed on the meter's top enemy
- **Where:**
  - `modules/Hud.lua:158`, `local ok, ident = pcall(NS.Identity.Resolve, fight, nil, nil)`: no enemies, so `resolveTarget` falls back to the snapshot target (`Identity.lua:261-264`).
  - `modules/Recorder.lua:316`, `local identity = NS.Identity.Resolve(fight, final, enemiesOf(fight))`: the meter's most-damaged enemy wins.
- **Problem:** when no encounter is active, the two board keys can differ (`Identity.BoardKey` keys on `targetCreatureID`, `Identity.lua:324-325`).
- **Impact:** the live pace bar, the chart's best line and the "noBest" state reflect one board. The over card's "new best" is judged on another (`Hud.lua:213-223`). The live and over views can contradict each other.
- **Failure scenario:** in open-world or dungeon trash, the player targets an add at the pull while most damage goes to the pack leader. The HUD paces against the add's best, and the fight is saved and judged on the leader's board.
- **Reachability:** any non-encounter fight whose pull target is not the top-damage enemy. Encounters are unaffected, because `encounterID` keys both.
- **Confidence:** medium (by reading; the live smoke has not run).

## Low

### F-009 `[correctness]` A few raw truth tests and `tostring`s sit outside the `NS.Secrets` contract
- **Where:**
  - `modules/Meter.lua:221`, `if not UnitExists("pet") then return nil end`
  - `modules/LaneCasts.lua:351`, `if not UnitExists("pet") then return nil end`
  - `modules/Probe.lua:234,284,369` (`UnitExists("pet")`)
  - `modules/Identity.lua:80`, `debug("client call raised: %s", tostring((...)))`
  - `modules/Share.lua:204`, `tostring(err)`
  - Contrast `Identity.lua:124`, `if not Secrets.PlainTruth(ask(UnitExists, "pet")) then return end`, and `Meter.lua:71-74` `errorText`.
- **Problem:** the same client answer is guarded in one file and raw in another.
- **Impact:** none today. If `UnitExists` ever answered secret in combat, `Meter.ResolvePet` would raise on every HUD tick.
- **Reachability:** nobody on today's clients. Consistency only.
- **Confidence:** medium.

### F-005 `[perf]` The HUD releases and rebuilds every live spell row on each 4 Hz tick
- **Where:** `modules/Hud_Breakdown.lua:233-252`. `List:ShowLive` starts with `self:Clear()` (`:234`), then per row runs `acquire` (two `SetPoint`, `SetStatusBarColor`, `Show`), `pcall` `SpellName`, `pcall` `SpellTexture` and `Format.Number`. `liveEntries` allocates a new list per tick (`:207-216`).
- **Impact:** about 8 rows × 15 calls × 4 Hz, plus garbage, for rows whose identity rarely changes.
- **Reachability:** any fight with the HUD open.
- **Confidence:** high by reading. **Unmeasured.**

### F-006 `[perf]` Two `Meter.ReadLive` calls for the same session on boundary ticks
- **Where:** `modules/Slices.lua:356`, `local live = NS.Meter.ReadLive(id)`, and `modules/Hud.lua:750`, `live = NS.Meter.ReadLive(id)`. Both run off the same `FIGHT_TICK` (`Slices.lua:385`, `Hud.lua:840`).
- **Impact:** a duplicate C_DamageMeter read and spell-table copy every 2 s in combat.
- **Reachability:** any fight with the HUD open.
- **Confidence:** high. **Unmeasured.**

### F-011 `[dead-code]` `acc.err` is never set
- **Where:** `modules/Meter.lua:407`, `if acc.err then return nil, acc.err end`. `acc` is built as `{ sealed = false }` (`:401`), and no reader writes `err`.
- **Impact:** a misleading branch on the record path.
- **Reachability:** a comment-level hazard; no runtime effect.
- **Confidence:** high.

### F-012 `[naming]` The performance doc says the purge runs out of combat, but its daily timer has no combat check
- **Where:** `docs/performance.md:32`, "- The settle read, the record build and the purge run out of combat.", versus `modules/Retention.lua:138-143`. `Retention.OnTimer` checks only `NS.IsStoodDown()` and then runs `Retention.Purge(time())`, which can send `FIGHTS_CHANGED` (`:123`).
- **Impact:** the doc overstates the guarantee. A long session can run a purge, a board rebuild and a Results refresh mid-pull.
- **Reachability:** a player in combat at the moment the daily timer elapses.
- **Confidence:** high (doc versus code).

---

## Upstream findings

None. Nothing in this review traces to `libs/` or `tests/_kit/`.
