# Ka0s Combat Trail — Race mode (DPS Race merged in) design

- **Date:** 2026-11-11
- **Status:** draft for the owner's review
- **Repo:** https://github.com/tusharsaxena/CombatTrail, branch `feat/2026-11-11-race-mode`
- **Source of the ported code:** DpsRace `master` at **f8078c7** (v0.1.0 plus the Combat Trail v0.2 parity
  round). Combat Trail `main` at **306b2c0**.

Where this document says **(owner)**, the owner decided it in the 2026-11-11 conversation. Where it says
**(Claude)**, Claude decided it and the owner has not confirmed it. Unmarked statements follow from one of
those, from the Combat Trail v0.1.0 design (`2026-11-10-combat-trail-design.md`, "the CT spec") or from the
Ka0s standard.

---

## 1. Intent

Two Ka0s addons overlap by about two thirds. DPS Race times a fixed-length race against a training dummy;
Combat Trail records every real fight. With both installed, a dummy pull draws two HUDs and is saved twice
with two different DPS figures (CT issue #4), and every shared fix is written twice.

The owner never wants to run both **(owner)**. So DPS Race is retired as an addon and becomes **Race mode**
inside Combat Trail **(owner)**:

- **Combat Trail covers every encounter** and saves the segments worth keeping: boss fights, Mythic+ trash
  packs, trash pulls in a Forever dungeon or raid, raid bosses, instanced PvP, dummy fights, and (by choice)
  the open world **(owner)**.
- **Race mode is a specialized case of a Combat Trail fight**: Retail only, against training dummies only,
  with a fixed length you pick, and a game on top (bests per length, pace, a buzzer, a new-best moment)
  **(owner)**. It exists to optimize a rotation.

**Success:** the owner uninstalls DPS Race, races on dummies inside Combat Trail, and finds nothing missing
**(owner: "I don't want to lose anything")**.

**The one anti-goal that matters most (owner):** Race mode must feel **native, not bolted on**. One look,
one HUD style, one Results window, one settings tree, one set of words. A race is a fight that happens to be
timed.

## 2. Goals, non-goals, anti-goals

**Goals**
- Every DPS Race feature works inside Combat Trail on Retail (inventory in §9) **(owner)**.
- One fight history and one Insights tab for fights and races, with filters **(owner)**.
- The recording rules in §3 **(owner)**.
- Combat Trail stays fully working on WoW Forever, where Race mode is **absent**, not greyed (clients-§4).

**Non-goals**
- Carrying DPS Race's saved runs, settings or cross-character bests over **(Claude)**. Neither addon is
  released; the formats differ. The owner accepted "saved fights wouldn't carry over" in the earlier
  assessment, and the v0.2 run already wiped saved fights once without migration (owner, 2026-11-10).
- Race mode on WoW Forever. Forever has no training dummies (DPS Race's ARCHITECTURE records why).
- Racing anything but a training dummy **(owner)**.
- A shared LibKa0s extraction of the HUD, recorder or bests (the earlier assessment: never shared).
- Keeping `/dr` as a command **(owner: retire DPS Race)**.

**Anti-goals** (failure even if it technically works)
- Race mode that looks or reads like a second addon: a different window style, different words for the
  same thing, its own settings tree, its own history **(owner)**.
- A dummy pull saved twice (once as a fight, once as a race).
- Any CT spec §2 anti-goal: taint, Lua errors in combat, arithmetic or comparison on a secret, a secret in
  SavedVariables, a Retail-only control on Forever, a cost the player notices.
- Changing the Combat Trail HUD's look or behavior for a normal fight **(owner: "keep the CombatTrail hud
  the same as it is today")**.

## 3. Recording rules (owner)

Every encounter is tracked live (the HUD, as today). Whether it is **saved**:

1. **Length is the primary rule.** A fight shorter than the minimum length is never saved. The minimum is
   configurable, default **30 s on Retail and 15 s on WoW Forever** (today it is 30 on both).
2. **Location is the secondary rule.** The per-content toggles stay **(owner: keep per-type toggles)**: raid,
   dungeon, Mythic+ (Retail), delve (Retail), scenario, battleground, arena (Retail), training dummy, open
   world. **All on by default (owner)**, which turns scenarios on (today off) and keeps the open world on.
3. **Dummy fights** are saved like any other fight **(owner)**, under the training-dummy toggle.
4. **A race is always saved** when it completes, is incomplete or is flagged, as DPS Race does today; a lost
   race (meter reset, session gone) is not **(Claude, following DPS Race)**. The minimum length does not
   apply to a race: its length is the one the player picked (as short as 0:10).
5. **Retention:** one rule for everything **(owner)**: the CT purge (days, default 7; the 500-fight cap)
   applies to races too, and any record holding a best, a fight best or a race best, survives it.

## 4. Race mode: the experience

### 4.1 At a dummy (owner)

The Combat Trail HUD shows exactly as it does for any fight. Beside it, a **small secondary window, the Race
window**, holds everything race-specific: the length presets and custom length, your best on this board, the
target line, and **Arm Race**.

- **Shown** near a known dummy (target or nameplate), on Retail, outside instances: DPS Race's auto-show,
  with its debounced hide and its respect for a manual close (`AutoArm.lua`). Also by `/ct race show`, the
  keybinding and the launcher **(Claude)**.
- **Auto-arm** on targeting a dummy out of combat, cancelled when the target changes before the pull, as in
  DPS Race (a setting, as today).
- **Not armed:** the pull is a normal dummy fight, saved under the dummy toggle **(owner)**.
- **Armed:** the first hit starts the race clock (DPS Race's first-new-session rule).
- **Cancelled or lost (Claude).** A race cancelled after the first hit (including *Stop Now* then *Cancel*) or
  lost (a meter reset, a sealed session) drops its `race` part, and the pull falls back to a plain dummy fight
  under the normal rules of §3 (the minimum length and the dummy toggle). Nothing the player did is silently
  thrown away, and nothing is saved twice.

### 4.2 During and after the race (owner)

The Combat Trail HUD stays as it is. **Every race-specific screen goes in the Race window** **(owner)**: armed,
running (the race clock, elapsed and/or time left per the clock setting; the pace bar against the race board's
best; chips), Stop! (figure tiles, *Stop Now* and *Cancel*), waiting (the hint box), and the result card (score,
delta to best, the pace bar, flag chips, *New Race / Open / Delete / Share*). The center-screen countdown, the
buzzer's raid warning and sound, and the new-best toast are as in DPS Race.

**What the CT HUD shows during a race (Claude).** The HUD keeps its own fight view (clock counting up, Damage,
DPS, chart, spells). Its best reference (the pace bar and the chart's best line) is the board the fight
would count on. For a race that is the **race board's best**, so both windows pace against the same run.
This is a change in data, not in look, and it is the natural reading of "a race is a fight that happens to be
timed". The owner can veto it.

**No duplicated widgets (Claude).** DPS Race's running body draws its own chart and spell rows. In the merged
addon those are the CT HUD's job, so the Race window does not repeat them. The result card keeps the score,
the delta and the flags, and *Open* opens the fight detail, which has the chart and the spells.

> **Amendment, 2026-11-13 (owner).** The Race window redesign,
> [`../plans/2026-11-13-race-window-redesign.md`](../plans/2026-11-13-race-window-redesign.md), supersedes
> parts of §4.1 to §4.3. The Race window's running and result screens no longer draw a pace bar (the HUD's
> is the race's); the running screen shows one countdown by default (`race.clock` is `"left"`), a time
> bar, *Best to beat*, *Best by now* and *Checkpoints*, and the result card *Against your best* and *This
> board*. The HUD now changes during a race: its title bar carries a Race button (ruling O6), it opens with
> the Race window near a dummy (`race.autoShowHud`, ruling O4), and its clock moves on the race beat,
> `RACE_CLOCK` at 10 Hz, with the Race window's (ruling O5). Attached, the Race window sits flush and, on
> the left or right, takes the HUD's height (`raceWindow.matchHud`, ruling O3). The text above is kept as
> it was decided.

> **Amendment, 2026-11-13 (owner, second batch; redesign plan W9 to W13).** A Race window the player
> opens while a dummy session is live is tied to that session (`AutoArm.InSession`), so walking away
> closes it; one open before the session stays the player's. The HUD's toggle (its key, the launcher's
> *Show window*, `/ct hud toggle`) and `/ct hud hide` close an open Race window with the HUD, each a
> player's close; opening opens the HUD alone, and `/ct race toggle` and the Race button never touch
> the HUD. The Race button carries no lit state. On Retail the Race window has a key, *Toggle Race
> window*, in a Retail-only `Bindings_Mainline.xml` (a documented deviation). The result card drops the
> time raced row and the vs best chip beside its table, and *This board* is renamed *Top races*. The
> running screen's time bar empties to the buzzer, it and the countdown turn green to yellow to red,
> and *Best by now* and each *Checkpoint* show the player's damage (the HUD's last read, text only, no
> pace bar or difference) beside the best's.

> **Amendment, 2026-11-13 (owner, third batch; redesign plan W14 to W23).** Near a dummy with auto-show
> on, the HUD's toggle opening the HUD opens the Race window too (tied to the session), even after a
> close earlier in the session; away from a dummy, and for `/ct hud show`, it opens the HUD alone. The
> Race button's icon is Open Iconic's plain `flag` (ruling O6's checkered flag is withdrawn), and every
> header mark is cropped and scaled to one size (`Style.FitControlArt`). An arm resets the HUD to its
> pre-fight look and never drops a live fight. The race's elapsed time and time left share one count of
> tenths (`NS.Format.RaceClock`), so the countdown reads 0:00.0 only at the buzzer and the center
> countdown agrees; the last checkpoint is taken at the buzzer, and the Stop! and waiting screens show
> all four Checkpoints when there is a best and they fit. The Race window has a resize grip while
> unlocked (`raceWindow.width`, `raceWindow.height`; width alone when matched to the HUD), and its
> bodies stretch to it. The clocks' redraw rate is a setting, `hud.clockRate` outside a race and
> `race.clockRate` in one (4, 5, 10 or 20 a second, default 10): a fight that is not a race now draws
> its clock on the HUD's own beat, not on FIGHT_TICK (superseding that part of ruling O5), and the meter
> is still read four times a second. *Best by now*'s *You* is *Current*, and the running screen gains
> two thin mini pace bars (over Best by now and in each Checkpoint), the HUD's bar driven by the same
> handed-in figure; this supersedes the second batch's "text only, no pace bar". With a pet on its own
> meter source, the bars range on the best's player-only figure.

> **Amendment, 2026-11-13 (owner, fourth batch; redesign plan W24 to W28).** One setting replaces the
> third batch's two: `hud.refreshRate` (*HUD refresh rate*, DPS HUD → Behavior → Refresh, 4, 5, 10 or 20
> a second, default 10, both clients) drives every live part of both windows, in a fight and in a race;
> `hud.clockRate` is replaced and `race.clockRate` is gone. Each beat is one meter read and the HUD's
> whole redraw: the HUD's own beat (`Hud.SyncBeat`) outside a race, the race beat in one, which calls
> `Hud.OnRaceClock()` and then sends `RACE_CLOCK`, so the Race window redraws on that same read (the
> HUD no longer hears `RACE_CLOCK`). FIGHT_TICK stays at 4 Hz for the slices and Fight's scan; the
> footer names the actual rate. This supersedes ruling O5 again. On the Race window, the time bar is
> drawn like the HUD's pace bar; Best to beat and the idle Your best card show a labeled Damage and DPS
> pair on one row (no big DPS figure); Best by now uses the same labeled layout, so its values never
> overlap; and the checkpoint cells are larger (`CP_H` 54, the time in the heading face, the bar 90%
> wide). The window's content height is 360.

### 4.3 Attach and detach (owner)

The Race window can be **attached** to the HUD or **detached**, by a setting and by attach/detach buttons on
the window itself, and it **keeps the HUD's styling** either way (same skin, same HUD Appearance blocks).
**(Claude):** attached, it docks to one side of the HUD (setting: right by default, or left, top, bottom), is the
HUD's height or its own (whichever is taller is left to the builder), and moves with it; detached, it
remembers its own position and can be locked. The race window and the HUD fade and show on their own rules:
the HUD by its own visibility mode, the Race window by the dummy rule above.

### 4.4 Pace (Claude)

One pace model for fights and races: Combat Trail's as it is today (`modules/Hud_Best.lua`). On a live client
that is the best's **straight-line average** (its damage over its length, times t), which is also what DPS Race
does; the best's session slices refine it into a curve only when they hold plain values (test mode, the sim).
No damage curve is added to saved records: it would need a schema and storage workstream for a refinement.

## 5. Bests and boards

- **Fight boards** are unchanged (CT spec §5, v0.2 D3): character × spec × board key.
- **Race boards (owner):** **character + spec + dummy kind + length**. Dummy kinds are DPS Race's categories:
  single target, cleave, dungeoneer, boss, PvP (`DummyList.lua`, the player's own list in the Training dummies
  settings). DPS Race's cross-character boards go away **(owner)**.
- DPS Race's two views of a board stay: all complete runs, and **clean only** (no flags). Incomplete and lost
  races never count. The late-cast ignore list still re-scores stored races on edit.
- **A race counts only on its race board (Claude).** It is not also a candidate for the dummy's fight board, so
  a dummy pull never holds two bests. An unarmed dummy fight counts on the dummy's fight board, as today.

## 6. The record

A race is **one fight record** with an optional `race` part **(Claude, from the earlier assessment)**:

- the usual CT fight fields (who, identity, content `dummy`, damage, spells, casts, gear, stats, loadout,
  usage, note);
- `race = { length, kind (dummy category), status (running/stopping/complete/incomplete/lost), flags
  {lateCasts, restartedAt, reloaded, died, sessionFromList, sharedSession}, score, dps, tail, endedAt,
  combatEnd, grace, restartGap }`, DPS Race's run fields that have no fight equivalent.
- **The race's figures are DPS Race's (Claude):** score = the session total, DPS = score ÷ race length (or ÷
  `endedAt` when incomplete). The fight's own duration and DPS stay in the record, and the race's are the ones
  shown wherever the row is a race.
- The CT schema version bumps, with a migration that leaves existing fight records as they are (they simply
  have no `race`).

## 7. Results window and Insights

- **One history (owner).** A **Fights / Races / All** filter **(owner: "a filter to show races only")**, absent on
  Forever. With Races on, the race-only filters appear: race length, dummy kind, hide flagged, include
  incomplete, **only bests** (DPS Race's). Group-by gains DPS Race's race groupings (length, target × length,
  spec × target × length) **(Claude)**.
- **A race row** shows the race's DPS and score, a length chip and its flags (DPS Race's Status badge), in the
  same table. **The detail** is Combat Trail's fight detail plus the race's sections (Timing, Flags) and the race
  delta box. Compare, Timeline and the Gear view are Combat Trail's and work on races unchanged.
- **Insights (owner):** a new Results tab, **across all saved fights, with races as a filter**. This closes CT
  issue #2. DPS Race's Insights sections port over. The race-only ones (Damage Tail After The Buzzer, Late
  Casts, Races Per Day, the Target × Length board tabs) show under the Races filter. The general ones (DPS
  progression, by character, by spec, consistency, recent new bests) run on all fights **(Claude)**. **A race
  contributes its race DPS** (score over length) wherever a DPS is shown or sorted, in Insights and in the All
  view of the table, since that is the figure its board ranks; mixed boards compare by percent of each board's
  best, as DPS Race's Insights do **(Claude)**.
- Also ported from DPS Race: the Insights cards and panels, the right-click late-cast ignore on rows and in the
  detail.

## 8. Settings, slash, launcher, names

- **One settings tree (owner: native).** A new **Race mode** page on Retail only, holding DPS Race's Race,
  Late-cast ignore list and New-best toast sections, plus the Race window's attach settings. Training dummies
  go to the History page (§9).
  The Race window's look comes from the DPS HUD page's appearance blocks, so it never has a styling tree of its
  own **(Claude)**. A **Race mode on/off** master switch sits at the top of the page **(Claude)**. Off, it stops **new** races:
  no Race window, no auto-show or auto-arm, the arm keybinding and the launcher entry do nothing, and the CT
  HUD paces on fight boards only. Saved races are fights and stay in the history, the Races filter and Insights,
  which gate on "the record has a `race` part", never on the switch. Forever has neither the switch nor any of it.
- **Slash (Claude):** `/ct race` with `arm [len]`, `cancel`, `show`, `hide`, `toggle`, `ignore
  [show|add|remove|defaults]`; `/ct dummy [show|add|remove|capture|defaults]` on both clients, since the
  dummy list is core (§9); `/ct results races` and
  `/ct results insights`; `/ct test race [armed|running|result]`; the sim gains DPS Race's eight race scenarios.
  `/ct ignore` stays the lanes' spell ignore, so the late-cast list lives under `race`.
- **Keybindings (Claude):** Arm / cancel race and Toggle Race window, both Retail. DPS Race's other two (toggle
  HUD, toggle Results) already exist in Combat Trail.
  *Amended 2026-11-13 (owner):* Toggle Race window ships, Retail only, in `Bindings_Mainline.xml`; Arm /
  cancel race does not (`/ct race arm` and `cancel` work in a macro).
- **New-best toast and chat lines (Claude).** The toast fires for a new race best, as in DPS Race, and also for a
  new **fight** best on its board (never a board's first fight), since a boss best is the moment Combat Trail
  exists for and "one behavior" is the owner's bar. Two toggles on the toast section, races and fights, both on.
  *Amended 2026-11-13 (owner):* a new profile toasts a race's new best and not a fight's (`toast.fights`
  defaults off); both toggles stay.
  The chat lines on arm and on a race result stay race-only. The CT HUD itself is unchanged.
- **Launcher:** a "Show race window" entry on Retail.
- **Words (owner):** the mode is "Race mode", a timed fight is a "race", the window is the "Race window".
  The rest of the vocabulary is Combat Trail's (fight, history, Results).
- **Retiring DPS Race (owner):** at the end of the run, with the owner's go-ahead, the DpsRace GitHub repo is
  archived and a final README note points to Combat Trail **(Claude)**. Its entry in the standard's roster
  (`WowAddonStandards/standards/ADDONS.md`) is a change to the standard and is filed as an issue there, not
  edited from this run.

## 9. What ports from DPS Race (owner: nothing is lost)

| DPS Race piece | Where it lands |
|---|---|
| `Race.lua` lifecycle (arm, first-hit clock, buzzer, Stop Now, Cancel, grace, restart gap, sticky-combat hint, combat-end quiet read) | a Race module beside `Fight.lua`, driving the fight record's `race` part |
| `Scoring.lua` (DPS, flags, late split) | Race scoring; reused by bests and Insights |
| Six HUD bodies (`Hud_States`), `Hud_Best` (your best card), `Hud_Tips` | the Race window's bodies, drawn with CT's HUD style helpers |
| `Countdown.lua`, `BestToast.lua` | as they are, on CT's bus and skin |
| `AutoArm.lua`, `DummyList.lua` (categories, captures, the player's list) | `DummyList` merges into CT's core dummy detection (Identity), on both clients: one list, one place. Its settings (the player's list, captures, categories) live on the **History** page's Training dummies section, so a custom dummy classifies a fight as `dummy` with Race mode off and on Forever too; the categories only matter to races. `AutoArm` is race layer, Retail only **(Claude)** |
| `LateIgnore.lua` | as it is, under `/ct race ignore` and the Race mode page |
| Resume after `/reload` mid-race (`Race.Resume`) | ported; this also closes CT's "a reload mid-combat drops the fight" gap for races (for plain fights it stays a known limitation unless cheap) **(Claude)** |
| Bests' race boards, clean-only boards | `Bests` gains race boards (§5) |
| Results: Runs list's race columns and filters, only bests, race groupings | Combat Trail's Results with the Races filter (§7) |
| Insights tab | a Combat Trail Results tab over all fights (§7) |
| Test mode samples (17 mock runs, three race previews), the sim's eight race scenarios | CT test mode and sim, race samples beside fight samples |
| Share's race line, the chat lines on arm and result | CT's Share, one line shape for fights and races |
| Diagnostics and perf for the race | CT's diagnostics report gains a race section |

Already in Combat Trail and **not** ported twice: Meter, Slices, Casts, Recorder's snapshots, Loadouts, Stats,
Usage, the Results table, detail, compare, timeline and gear view, Sizing, Style, skins, launcher, debug.

## 10. Constraints

- The Ka0s standard at the revision CT already follows. Anything that cannot conform is flagged, not
  silently done (CLAUDE.md).
- Race mode is a Retail-only feature in a dual-client addon: declared through `NS.Compat.ForClient`, with a
  present test on Retail and an absent test on Forever for each control (clients-§4, clients-§6).
- The layout cap (1500 lines per file) and CCN 15. Several CT files are near 1000-1200 lines, so new race
  code goes into new files rather than growing them.
- Secret values: DPS Race's rules already match CT's (copy into C-side widgets only). Race scoring reads plain
  values after combat, as DPS Race does.
- `libs/` and `tests/_kit/` are never edited. LibKa0s needs are filed as issues.
- Owner run rules: a resumable, checkpointed plan; a branch with incremental commits; pushes at milestones;
  no merge without the owner's go-ahead; no version bump; at the end, every branch, stash and worktree of the
  run deleted.

## 11. Left to the builder

Module names and boundaries; how DPS Race's HUD bodies are split between the Race window and what the CT HUD
already draws; the Race window's exact size and the attached layout; locale strings; which DPS Race tests are
adapted and which are re-written against CT's fixtures; the sample data; the order of the Insights sections.

## 12. Risks

| Risk | Mitigation |
|---|---|
| Scope: about 24k lines of DPS Race, 1,509 tests; perhaps 6-9k lines actually move | milestones with a pushed checkpoint each; the plan's ledger makes the run resumable |
| Two state machines (Fight and Race) fight over one pull | Race drives the record's `race` part and Fight owns the session; one test per handoff (arm, first hit, buzzer, combat end, cancel, reload) |
| The CT HUD's best reference switching to the race board surprises the owner | flagged as Claude's call in §4.2; one setting-free seam, easy to revert |
| Insights over all fights is new code, not a port | DPS Race's sections that are race-specific port as they are; the general ones are rebuilt on CT's fight records with the same visuals |
| Files hit the 1500-line cap | new files per area from the start (Race, RaceWindow, RaceScoring, Results_Insights, ...) |
