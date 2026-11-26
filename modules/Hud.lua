local _, NS = ...
-- modules/Hud.lua — the DPS HUD's shell (spec §6, plan Tasks 3.1 and 3.2): the window, its title bar
-- and footer, which body shows for the fight on screen, when it opens and when it fades, and the view
-- the bodies draw (the figures, the pace bar's range, the damage chart's columns, the spell rows).
-- The two bodies are modules/Hud_States.lua; the pace data modules/Hud_Best.lua, the chart and the
-- pace bar modules/Hud_Chart.lua, the rows modules/Hud_Breakdown.lua, the look
-- modules/Hud_Appearance.lua and the tooltips' words modules/Hud_Tips.lua. Adapted from DPS Race @045f479 (modules/Hud.lua) without its race: no
-- arm, buzzer, countdown, auto-arm or race length (the race is modules/Race.lua's, drawn by the Race
-- window); the fight is modules/Fight.lua's.
--
-- THE STATES. Hud.State() answers "hidden" while the window is not up, else "live" for the fight in
-- progress ("noBest" when there is nothing to pace it against: no stored fight on its board, or
-- `hud.paceAgainst` "none"), or "over" for the fight-over card, whose view carries `newBest` (with
-- its `delta`), `saved` and `skipReason` from the recorder's FIGHT_SAVED / FIGHT_SKIPPED.
--
-- A RACE'S FIGHT (race plan ruling X7) opens it on its first hit whatever `hud.show`, `hud.instancesOnly`
-- and `general.hudInCombat` say (RACE_STARTED re-decides a fight already on screen); only the
-- player's close on that fight holds it shut. While the fight carries its `race` part the HUD paces on
-- the race board the race would count on (race plan Task C3, spec §4.2): Hud.PaceRecord probes with
-- the part's kind and length, and the curve is the race best's straight line (HudBest.RaceCurve), the
-- Race window's own. RACE_STARTED reads the pace again (the bus keeps no order between receivers), and
-- RACE_CANCELED, the part gone, paces the fight on its dummy's fight board again. A race resumed after a
-- /reload (RACE_STATE_CHANGED out of idle) brings its adopted fight, which had no FIGHT_STARTED, live.
-- A RACE ARMED (RACE_ARMED, owner 2026-11-13) clears the fight still on screen, the over card or a
-- last view (its clock, its figures, its chips, its spell rows, its chart): the HUD goes back to the
-- look it has before any fight (0:00.0, dashes, no spell rows), the window staying as open as it was.
-- A fight live on it is never dropped (an arm wants Fight idle), and nothing brings the old fight
-- back: a race canceled to idle finds no fight here to pace again.
-- A fight on a SHARED session (ruling X3: its live total holds the damage from before the arm) is not
-- paced and draws no chart, live or on the card, as in DPS Race.
--
-- WHEN IT OPENS (`hud.show`). "auto" (default): on the first hit of every fight (FIGHT_TICK after the
-- fight's firstHitT is set; the Master controls' `general.hudInCombat` off turns this off), and
-- `hud.instancesOnly` keeps it shut outside an instance; both apply to "auto" only. It fades
-- `hud.fadeAfter` seconds after the fight ends (0 keeps the card up), held while the pointer is over
-- it (`hud.holdOnMouse`) and never while pinned (Hud.Pin). "always": up at login and after a
-- stand-up and a profile switch, in or out of an instance, and never fades. "toggle":
-- only the player opens it. A HUD the player opened (Show, the toggle, the launcher, `/ct hud`) never
-- fades; one the player closed stays closed for the rest of that fight. `hud.overCard` off closes an
-- auto-opened HUD when its fight ends instead of showing the card.
--
-- THE RACE WINDOW IS PART OF IT (Retail; owner, 2026-11-13, race window redesign plan W29). The Race
-- window is never up while the HUD is hidden: every Refresh ends by telling it (RaceWindow.FollowHud),
-- so whatever hides the HUD (the fade, the overCard close, its close control, a stand-down) hides it
-- too, still wanted, and the HUD's return brings it back (its header has the whole rule). Its open
-- paths open the HUD first: the player's through Show, a race's (arm, resume, result, sample) through
-- ShowForRace, a dummy session's through ShowNearDummy. ESCAPE closes both, each the player's close
-- (onHide closes a Race window still up, whichever the close list reached first); the close control
-- hides the Race window with the HUD, still wanted. NO FADE WHILE A RACE HOLDS IT (D2): while the
-- race, real or sample, is not idle, neither the fade nor the overCard close runs; the race's idle
-- edge (Hud.OnRaceIdle) starts the fade (the overCard close a LEAVE_DELAY on), and closes a HUD
-- ShowForRace opened when no fight came on it.
--
-- THE TOGGLE (Hud.Toggle: the HUD key, the launcher's Show window entry, `/ct hud toggle`; `/ct hud
-- hide` is its closing half). Closing, it closes the Race window with the HUD when that is open, each
-- a close by the player (Hud.Closes, the Race window's Closes). Opening, it opens the HUD, a still
-- wanted Race window with it, and near a training dummy (Race mode on, AutoArm.InSession, either
-- auto-show row on) the Race window as the player's open (RaceWindow.Show, tied to that session),
-- whatever closed it before in the session: the key is explicit.
--
-- NEAR A TRAINING DUMMY (Tasks W3 and W29). modules/AutoArm.lua's session opens the Race window,
-- which opens this (Hud.ShowNearDummy: an "auto" open whatever `hud.show` says, kept up through the
-- first hit, fading by the rules above, opened again by the session's next ask after a fade), and
-- asks it to close at the session's end (Hud.HideAwayFromDummy) while that open still stands: no
-- fight live on it, not opened or pinned by the player since. A HUD the player closed (Hud.Closes)
-- keeps both windows shut for the session.
--
-- THE TITLE BAR, left to right: Results, Log, Race, Lock, Settings, Close (LibKa0s#86 order). The Race control
-- (Retail only, the flag) shows while Race mode is on, the strip closing up without it;
-- its click is `/ct race toggle` (NS.SetRaceWindowShown). The Combat Sequence control (Phosphor's list-bullets mark, item 13, while
-- `sequence.enabled`) opens and closes the Combat Sequence drawer under the spell rows (modules/Hud_Log.lua,
-- CombatTrail #11), whose height the content's bottom inset reserves. Like every title-bar control it rests in the
-- skin's `icon.tint` and takes `text.link` only under the pointer (smoke round 1, SR-L3), with its
-- tooltip above it: it carries no light for the Race window being open.
--
-- WHAT RUNS, AND WHEN. Nothing is registered with the client: the HUD hears the bus (FIGHT_STARTED,
-- FIGHT_TICK, FIGHT_ENDED, FIGHT_SAVED, FIGHT_SKIPPED, RACE_ARMED, RACE_STARTED, RACE_CANCELED,
-- RACE_STATE_CHANGED, SETTINGS_CHANGED, which also re-decides the Race control for `race.enabled`) on its own target,
-- and the race beat calls it directly (Hud.OnRaceClock). No OnUpdate is ever set. The fade is one
-- AceTimer on the addon object, so the stand-down's CancelAllTimers takes it, and Suspend drops it too.
--
-- THE BEAT (owner, 2026-11-13): `hud.refreshRate` (4, 5, 10 or 20 a second, default 10) drives every
-- live part of both windows. While a fight is live on the window and it is up, ONE beat at a time
-- reads NS.Meter.ReadLive once and redraws the whole body (the clock, Damage and DPS, the pace bar,
-- the chart, the spell rows), timed into the perf harness's `hud` bucket:
--   in a race   (the fight on the window is the race's or the sample's and the race beat runs,
--               modules/RaceClock.lua: running or stopping) the race beat, which calls
--               Hud.OnRaceClock and then sends RACE_CLOCK, so the Race window redraws from this
--               read in the same beat (Task W5, ruling O5);
--   otherwise   the HUD's own beat (Hud.SyncBeat): one repeating AceTimer on the addon object at
--               1 / `hud.refreshRate`, while the window is up on a live fight that moves (not a
--               frozen sample) and no race beat draws it. It is re-decided at every Refresh, by
--               RaceClock.Sync and by a `hud.refreshRate` or profile change; a fire that finds it
--               unwanted stops it.
-- A real fight is read only while Fight holds it in combat (FIGHT_TICK's own window); in its settle a
-- beat redraws from the last read, the clock moving on. A sample's read is its plan's. FIGHT_TICK
-- (4 Hz, modules/Fight.lua) stays the fight's own rhythm for its other receivers (the chart's slices,
-- the unbound scan); for the HUD it only brings a fight live, and redraws it only while no beat runs
-- (no timer API). The footer says the rate ("live · 10 Hz").
--
-- THE RACE WINDOW BESIDE IT (Task W4) takes its height when docked LEFT or RIGHT (`raceWindow.matchHud`):
-- every redraw that leaves the window at a new height (Hud.Height: the one static height, the grip's
-- while it is held) tells it (RaceWindow.OnHudResized).
--
-- NO DECISION FROM A METER VALUE. The live figures are opaque handles copied into labels
-- (modules/Hud_States.lua); every decision here comes from GetTime(), the fight's plain stamps, the
-- plain after-combat read and the stored records. The Race window draws the same last read's player
-- total beside its best's figures (Hud.LiveDamage, owner 2026-11-13): no second meter read.
--
-- THE PACE (spec §6 and §12). The pace record's curve (HudBest.Curve) is read once when the fight goes
-- live; each redraw sets the fight's live total against it at the clock's time (from the first hit),
-- on DPS Race's split bar: red short of the tick, green past it (modules/Hud_Chart.lua; the total and
-- its reference, HudBest.LiveView). The over card draws the same bar from the plain after-combat read
-- at the fight's length.
--
-- THE WINDOW is a plain, non-secure frame (standalone-windows): skinned through NS.ApplySkin, closed
-- through NS.MakeCloseButton, in UISpecialFrames, clamped, toplevel in the MEDIUM tier
-- (LAYERS.STRATA.HUD, or `hud.window.strata`). Its width is `hud.width`; its scale is `hud.scale`, its
-- opacity `hud.window.alpha`; its title bar and footer (the library's W.Footer, NS.FOOTER_HEIGHT
-- tall) follow `hud.window.titleBar` and `footer`; its
-- place is `hud.position`, written by the title bar's drag (not while `general.locked`) and put back
-- by Master controls' Reset position. Built on first show, or by Hud.Dock for an attached Race window
-- (placed and sized where it would stand, still hidden).
--
-- ONE WINDOW, ONE STATIC HEIGHT (owner feedback item 12, 2026-11-25; v0.2 Task B3's fixed mode, the
-- auto-grow `hud.sizeMode` and its `hud.grow` retired by schema step 6). The HUD and the docked log
-- are one frame, top down: the title bar, the clock and target, the boxes, one reserved status line
-- (the over card's chips, kept while empty), Damage profile, Spell breakdown, the Combat Sequence
-- (modules/Hud_Log.lua) and the footer. Hud.FixedHeight() is their sum (HudStates.FixedStack for
-- `hud.bars` rows, HudLog.HeightFor its rows), worked out from the configuration alone, so nothing a
-- fight holds or does moves it: only the log opening or closing, a rows setting, or the grip. The
-- library's grip (modules/Sizing.lua), hidden while locked, sizes it: while it is held the sections
-- lay out at the dragged size, and the release stores `hud.width` (MIN_WIDTH-MAX_WIDTH) and the whole
-- rows the height holds, and the window snaps to them. While the log is docked open the height is split
-- between the spell rows and the log's (Hud.SplitFor, modules/Hud_Split.lua, R4-CT-07) and both
-- `hud.bars` and `sequence.drawer.rows` are stored; with Spell breakdown off only the log's; with the log
-- closed or detached only the spell rows' (MIN_BARS-MAX_BARS). Spells past the rows scroll
-- with the wheel (modules/Hud_States.lua). The top left holds because the stored anchor is on it: a
-- drag of the title bar or the grip, and any Refresh that finds the stored point off the top edge (a
-- profile switch), re-anchor the window (normalizeAnchor) to TOPLEFT on UIParent's BOTTOMLEFT, from
-- the shell frame's own edges, so the log's open and close grow and shrink it downward.
--
-- A SAMPLE FIGHT (test mode and the sim, modules/Preview.lua and modules/Sim.lua) comes to the same
-- receivers, handed over directly rather than on the bus, flagged `sample`. Its live and cast reads
-- come from its plan (modules/MockFights.lua), never the meter or the cast list; it is paced and
-- judged against the sample history (modules/Results_Source.lua); it opens the window whatever the
-- show mode, never fades, and a `frozen` one holds its clock at that many seconds. The window says
-- so with the library's strip under the title bar (the sim's while a sim runs), and EndSample drops
-- it.

local Hud = {}
NS.Hud = Hud

local L = NS.L
local Perf = NS.Perf
local Secrets = NS.Secrets

Hud.STATE = { HIDDEN = "hidden", LIVE = "live", OVER = "over", NO_BEST = "noBest" }
-- Seconds between two reads of the fight's casts for the chart's cooldown icons.
Hud.CAST_READ = 1
Hud.FRAME_NAME = "CombatTrailHud"
Hud.MIN_WIDTH = 260   -- DPS Race's (v0.2 Task B2); `hud.width` defaults to it (R4-CT-06)
Hud.MAX_WIDTH = 600   -- the width row's and the grip's
Hud.MIN_BARS, Hud.MAX_BARS = 3, 15   -- the spell rows `hud.bars` holds (v0.2 Task B3; at least 3, R4-CT-07)
-- Seconds the card stays after the pointer leaves it, once the pointer held it past its fade (and
-- how often a held card looks again whether the pointer is still on it).
Hud.LEAVE_DELAY = 2

local STATE = Hud.STATE
-- DPS Race's insets: PAD at the sides, the content 10 under the title bar and 8 over the footer (the
-- library's W.Footer, NS.FOOTER_HEIGHT tall: standalone-windows, *Window chrome geometry*).
local HEADER_H, PAD = NS.Style.TITLE_BAR_H, 12

local ui                         -- the built window
local wanted = false             -- the window should be up
local byPlayer = false           -- the player opened it: it never fades
local pinned = false             -- held open (Hud.Pin)
local locked = false             -- general.locked: no drag
local hiding = false             -- the addon is hiding the frame itself
local hovering = false           -- the pointer is over the frame
local key                        -- the body on screen: nil (no fight yet) | "live" | "over"
local cur                        -- the fight the body shows
local pending                    -- a fight that started and has not hit yet
local view = {}                  -- the facts about `cur` the bodies draw
local live                       -- the last NS.Meter.ReadLive of `cur` (opaque)
local dismissed                  -- the id of the fight the player closed the window on
local closes = 0                 -- the player's closes, for the dummy session's manual-close rule
local dummyShown = false         -- opened near a training dummy (Hud.ShowNearDummy), still that open
local raceShown = false          -- opened for the Race window by a race (Hud.ShowForRace), still that open
local pullShown = false          -- opened at the pull (`hud.openOnPull`), no hit since: its fight's end lets go
local closing = false            -- the close control is hiding the frame (Act.close), not Escape
local fadeAt, fadeTimer, held    -- the fade's deadline, its timer, held by the pointer
local beatTimer, beatEvery       -- the HUD's own beat (Hud.SyncBeat) and its interval

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Hud", fmt, ...) end
end

local function isDown()
    return NS.IsStoodDown ~= nil and NS.IsStoodDown()
end

-- ── settings ────────────────────────────────────────────────────────────────────────────────────

-- The shipped default for a profile path: defaults/Profile.lua is the only place a default is
-- written (savedvariables-§2), so no literal fallback lives here.
local function shipped(path)
    local node = NS.defaults and NS.defaults.profile
    for part in path:gmatch("[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

-- A profile value by path, read straight off the profile, else its shipped default. Every `hud.*`
-- key has its row on the DPS HUD page (settings/Hud.lua), which writes through the seam; the read
-- stays direct because it runs many times on every beat's draw, where a schema lookup per key would
-- cost a row search each.
local function setting(path)
    local node = NS.db and NS.db.profile
    for part in path:gmatch("[^.]+") do
        if type(node) ~= "table" then node = nil break end
        node = node[part]
    end
    if node == nil then return shipped(path) end
    return node
end
Hud.Setting = setting

local function position()
    local hud = NS.db and NS.db.profile and NS.db.profile.hud
    if type(hud) ~= "table" then return nil end
    if type(hud.position) ~= "table" then hud.position = {} end
    return hud.position
end

-- ── what the HUD knows about the fight ──────────────────────────────────────────────────────────

local function inInstance()
    if type(IsInInstance) ~= "function" then return false end
    local ok, inside = pcall(IsInInstance)
    return ok and Secrets.PlainTruth(inside) == true
end

--- Whether the player closed the HUD on `fight`.
local function closedOn(fight)
    return fight ~= nil and dismissed ~= nil and dismissed == fight.id
end

--- Whether the HUD may open itself for `fight` now (the show mode, the master row, instancesOnly,
--- and the player's close on this fight). "always" answers before the master row and instancesOnly,
--- which govern "auto" only (plan decision D4): only the player's close on this fight holds it. A
--- race's fight opens it whatever the three say (race plan ruling X7): the Race window draws no live
--- damage of its own, so the HUD is where a race's damage shows; only the player's close holds it.
local function autoAllowed(fight)
    if type(fight) == "table" and fight.race ~= nil then return not closedOn(fight) end
    local mode = setting("hud.show")
    if mode == "toggle" then return false end
    if mode == "always" then return not closedOn(fight) end
    if setting("general.hudInCombat") == false then return false end
    if setting("hud.instancesOnly") == true and not inInstance() then return false end
    return not closedOn(fight)
end

-- The pace lookup (which stored fight the live one is paced against, its target line, its curve)
-- lives with the pace data in modules/Hud_Best.lua (peeled under layout-§1's cap, W29).
local identityOf, onSharedSession = NS.HudBest.Identity, NS.HudBest.OnSharedSession
local targetLine, curveOf = NS.HudBest.TargetLine, NS.HudBest.CurveOf
Hud.PaceRecord = NS.HudBest.PaceRecord

local function newView(fight)
    local ident = identityOf(fight)
    local pace = Hud.PaceRecord(fight, ident)
    return { fight = fight, ident = ident, targetLine = targetLine(ident), pace = pace, curve = curveOf(pace),
             raced = fight.race ~= nil }
end

-- The live fight's pace read again (its race part came or went after the first hit).
local function repace(fight)
    local pace = Hud.PaceRecord(fight, view.ident)
    view.pace, view.curve, view.raced = pace, curveOf(pace), fight.race ~= nil
    debug("fight %s paced again (pace %s)", tostring(fight.id), pace and tostring(pace.id) or "none")
end

-- The over card's best: is the saved fight its board's best now, and by how much over the one before.
-- A sample record is judged against the sample history.
local function judge(record)
    NS.Bests.Invalidate()   -- the bus keeps no order between receivers: the board must hold `record`
    local isBest, bestFor = NS.Bests.IsBest, NS.Bests.For
    if record.sample then isBest, bestFor = NS.ResultsSource.IsBest, NS.ResultsSource.BestFor end
    view.newBest = isBest(record) and true or false
    view.delta = nil
    if not view.newBest then return end
    local before = bestFor(record, true)
    local a, b = record.dps, before and before.dps
    if type(a) == "number" and type(b) == "number" and b > 0 then view.delta = (a - b) * 100 / b end
end

-- ── the fade ────────────────────────────────────────────────────────────────────────────────────

local function cancelFade()
    if fadeTimer and NS.addon and NS.addon.CancelTimer then NS.addon:CancelTimer(fadeTimer) end
    fadeTimer, fadeAt, held = nil, nil, false
end

-- Whether a race holds the HUD up (W29 D2): the sample standing in, else the real race, is not idle.
local function raceHolds()
    local RS = NS.RaceSample
    local R = (RS and RS.On and RS.On()) and RS or NS.Race
    return R ~= nil and R.State ~= nil and R.State() ~= "idle"
end

-- A dummy session holds the HUD up as a race does (the owner, 2026-11-13: after New Race at a dummy the
-- fade took both windows down while the player stood there). Its end lets go (Hud.HideAwayFromDummy).
local function dummyHolds()
    local AA, RM = NS.AutoArm, NS.RaceMode
    return AA ~= nil and AA.InSession ~= nil and AA.InSession() and RM ~= nil and RM.On()
end

local closesWithFight   -- below, by the fight's end (Hud.HideAwayFromDummy reads it first)

local function canFade()
    return wanted and not byPlayer and not pinned and setting("hud.show") ~= "always" and not (cur and cur.sample)
        and not raceHolds() and not dummyHolds()
end

local fadeCheck

local function schedule(delay)
    if not (NS.addon and NS.addon.ScheduleTimer) then return end
    fadeTimer = NS.addon:ScheduleTimer(function() fadeCheck() end, math.max(0.05, delay))
end

-- Start the fade `delay` seconds from now (default `hud.fadeAfter`; 0 or less: no fade).
local function startFade(delay)
    cancelFade()
    if not canFade() then return end
    local after = delay or tonumber(setting("hud.fadeAfter")) or 0
    if after <= 0 then return end
    fadeAt = GetTime() + after
    schedule(after)
end

local function mouseOver()
    if hovering then return true end
    local f = ui and ui.frame
    if not (f and f.IsMouseOver) then return false end
    local ok, over = pcall(f.IsMouseOver, f)
    return ok and over == true
end

-- ── the window ──────────────────────────────────────────────────────────────────────────────────

local function windowShown()
    return ui ~= nil and ui.frame:IsShown() == true
end

-- Through the schema's reader, which walks a row's path without allocating: the docked log reads the
-- width on every beat (HudLog.Height's chips wrap at it, CLF-1), where this file's own `setting` makes a
-- gmatch iterator per call.
local function width()
    return math.max(Hud.MIN_WIDTH, tonumber(NS.GetSetting("hud.width")) or Hud.MIN_WIDTH)
end

-- The content's insets from the window's top and bottom: the title bar's and the footer's, each
-- only while shown (`hud.window.titleBar`, `hud.window.footer`), and the docked strip's BodyOffset (its
-- height while it shows, 0 while hidden).
local function stripHeight()
    local strip = ui and ui.stripMode and ui[ui.stripMode .. "Strip"]
    return strip and strip:BodyOffset() or 0
end
local function contentTop() return (setting("hud.window.titleBar") ~= false and HEADER_H + 10 or PAD) + stripHeight() end
local function footInset() return setting("hud.window.footer") ~= false and NS.FOOTER_HEIGHT + 8 or PAD end
local function contentBottom() return footInset() + NS.HudLog.Height() end

-- ── the size (owner feedback item 12) ─────────────────────────────────────────────────────────

local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

--- The spell rows `hud.bars` asks for, whole and in range.
local function bars()
    return clamp(math.floor(tonumber(setting("hud.bars")) or Hud.MIN_BARS), Hud.MIN_BARS, Hud.MAX_BARS)
end

local function chromeHeight() return contentTop() + contentBottom() end

-- The window's height for `n` spell rows and `r` log rows: the title bar's and the footer's insets,
-- the stack the configuration reserves and the docked log's sections (0 while it is not docked open).
local function heightFor(n, r)
    return contentTop() + footInset() + NS.HudLog.HeightFor(r)
        + NS.HudStates.FixedStack(setting("hud.layout"), n, setting("hud.paceAgainst") ~= "none")
end

Hud.HeightFor = heightFor   -- the same, for the suites

--- The window's one height: `hud.bars` spell rows and the docked log's rows (the grip's while held).
--- @return number
function Hud.FixedHeight() return heightFor(bars(), NS.HudLog.Rows()) end

--- The spell rows and log rows a window `h` high holds, walked from (b0, l0) (modules/Hud_Split.lua).
--- @return number, number
function Hud.SplitFor(h, b0, l0)
    local HL = NS.HudLog
    return NS.HudSplit.Walk(h, b0, l0, heightFor,
        { minB = Hud.MIN_BARS, maxB = Hud.MAX_BARS, minL = HL.MIN_ROWS, maxL = HL.MAX_ROWS })
end

-- The whole bars a window `h` high holds, in range, the log's rows kept.
local function barsFor(h)
    return clamp(NS.HudBreakdown.Capacity(h - heightFor(0, NS.HudLog.RowsSetting())), Hud.MIN_BARS, Hud.MAX_BARS)
end

-- The whole log rows a window `h` high holds, in range, the bars kept.
local function logRowsFor(h)
    return NS.HudLog.RowsFit(h - heightFor(bars(), 0))
end

-- Whether the grip's height goes to the log's rows (the log docked open), and whether to the spell rows.
local function logTakes() return NS.HudLog.Wanted() end
local function barsTake() return (setting("hud.layout") or {}).spells ~= false end

-- The grip's least and most heights of the stack configured now: 3/3 to 15/20 while both take it, the
-- log's MIN_ROWS to MAX_ROWS with the spells off, else MIN_BARS to MAX_BARS spell rows.
local function heightBounds()
    local HL = NS.HudLog
    if logTakes() and barsTake() then return heightFor(Hud.MIN_BARS, HL.MIN_ROWS), heightFor(Hud.MAX_BARS, HL.MAX_ROWS) end
    if logTakes() then return heightFor(bars(), HL.MIN_ROWS), heightFor(bars(), HL.MAX_ROWS) end
    return heightFor(Hud.MIN_BARS, 0), heightFor(Hud.MAX_BARS, 0)
end

-- The spell rows and log rows (nil: the log takes none) a height `h` holds, from the grip-down pair.
local function dragPair(h)
    local b0, l0 = ui.down and ui.down[1] or bars(), ui.down and ui.down[2] or NS.HudLog.RowsSetting()
    if not logTakes() then return barsFor(h), nil end
    if not barsTake() then return b0, logRowsFor(h) end
    return Hud.SplitFor(h, b0, l0)
end

-- Whether the grip is being dragged now and has handed on a size.
local function sizing()
    return ui ~= nil and ui.dragH ~= nil and NS.Sizing.IsSizing(ui.frame)
end

local function canResize() return not locked end

-- The grip shown while it may size the window (not locked), and its bounds (heightBounds).
local function applyGrip()
    local f, on = ui.frame, canResize()
    if f.resizeGrip then f.resizeGrip:SetShown(on) end
    -- The footer's right line clears the grip's corner while the grip shows (a relayout: only on a change).
    if ui.footGrip ~= on then
        ui.footGrip = on
        ui.foot:SetGrip(on)
    end
    if type(f.SetResizeBounds) == "function" then
        local lo, hi = heightBounds()
        f:SetResizeBounds(Hud.MIN_WIDTH, lo, Hud.MAX_WIDTH, hi)
    end
end

-- ── the place ──────────────────────────────────────────────────────────────────────────────────

local function applyPlacement()
    local f, p = ui.frame, position() or {}
    local d = shipped("hud.position") or {}
    f:ClearAllPoints()
    f:SetPoint(p.point or d.point or "CENTER", UIParent, p.relPoint or d.relPoint or "CENTER",
        tonumber(p.x) or d.x or 0, tonumber(p.y) or d.y or 0)
    f:SetScale(tonumber(setting("hud.scale")) or 1)
end

-- The shell frame never displays a meter value (only its descendants do), so its own anchor and its
-- edges (GetLeft, GetTop, GetBottom) are read back here, the only geometry reads in the HUD; each
-- answer is still taken only as a plain number.
local function savePosition()
    local p = position()
    if not (p and ui) then return end
    local point, _, relPoint, x, y = ui.frame:GetPoint(1)
    if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return end
    p.point, p.relPoint = point, type(relPoint) == "string" and relPoint or point
    p.x, p.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

local function edgeOf(f, name)
    local fn = f[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, f)
    return ok and Secrets.PlainNumber(v) or nil
end

--- Re-anchor the window on its top edge where it stands: TOPLEFT on UIParent's BOTTOMLEFT at the
--- frame's own left and top edges, stored in `hud.position`. Unless `force` (after a drag, whose
--- anchor is the client's), a stored point already on the top edge (TOP*) is kept. Answers whether it
--- re-anchored (false where the frame cannot say where it is).
local function normalizeAnchor(force)
    local p = position()
    if not (p and ui) then return false end
    if not force and type(p.point) == "string" and p.point:find("^TOP") then return false end
    local f = ui.frame
    local left, y = edgeOf(f, "GetLeft"), edgeOf(f, "GetTop")
    if not (left and y) then return false end
    p.point, p.relPoint = "TOPLEFT", "BOTTOMLEFT"
    p.x, p.y = math.floor(left + 0.5), math.floor(y + 0.5)
    applyPlacement()
    return true
end

-- After a drag (the title bar's or the grip's): the place stored on the top edge, else as the
-- client left it.
local function placeAfterDrag()
    if not normalizeAnchor(true) then savePosition() end
end

local Act = {}
Hud.Act = Act

-- The controls on the band, outermost first: Close, Settings, Lock, the Race control and the Combat Sequence control
-- while each shows, Results (W.HeaderButtons' order, extras . settings . close). Laid again when either
-- comes or goes, so the strip closes up.
local function layoutHeader(withRace, withLog)
    local right = { ui.close, ui.settings, ui.lock }
    if withRace then right[#right + 1] = ui.race end
    if withLog then right[#right + 1] = ui.log end
    right[#right + 1] = ui.results
    ui.header = { right = right, withRace = withRace == true, withLog = withLog == true }
    NS.Style.Header(ui.frame, { title = ui.frame.title, align = "LEFT", drag = ui.drag, right = right, n = #right })
end

-- The title band: the title LEFT, the marks on the right through W.HeaderButtons (NS.MakeHeader; LibKa0s#86),
-- left to right Results, Race (Retail only), Lock, then Settings (the launcher's registered opener) and
-- the Close in the corner. The HUD sits in the MEDIUM tier, under the settings panel, so it stays up.
local function buildHeader(f)
    local Style = NS.Style
    f.title = f:CreateFontString(nil, "OVERLAY", Style.FONT.TITLE)
    f.title:SetText(L["Combat Trail"])
    local extras = { { key = "results", icon = "chart", glyph = "R", tip = L["Results"], onClick = function() Act.results() end },
                     { key = "log", icon = "ph:list-bullets", glyph = "L", tip = L["Combat Sequence"], onClick = function() Act.log() end } }
    if NS.Compat.ForClient({ "retail" }) then
        extras[#extras + 1] = { key = "race", icon = "flag", glyph = "F", tip = L["Race window"], onClick = function() Act.race() end }
    end
    extras[#extras + 1] = { key = "lock", icon = "unlock", glyph = "U", tip = L["Lock or unlock the HUD"], onClick = function() Act.lock() end }
    local hb = NS.MakeHeader(f, { close = function() Act.close() end, settingsTip = L["Settings"], extras = extras })
    ui.close, ui.settings = hb.close, hb.settings
    ui.results, ui.race, ui.lock, ui.log = hb.extras.results, hb.extras.race, hb.extras.lock, hb.extras.log
    local drag = CreateFrame("Frame", nil, f)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() if not locked then f:StartMoving() end end)
    drag:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        placeAfterDrag()
    end)
    ui.drag = drag
    layoutHeader(false, NS.HudLog.ControlShown())
end

-- The footer is the library's (NS.MakeFooter: W.Footer, its hairline and its two muted lines); the
-- host writes the lines (footer, below) and shows or hides it whole.
local function buildFooter(f)
    ui.foot = NS.MakeFooter(f)
    ui.footLeft, ui.footRight = ui.foot.left, ui.foot.right
end

local onHide, render, resized

-- The Race window docked beside it takes its height (Task W4): told each time that height changes.
local function tellHeight()
    local h = Hud.Height()
    if h == ui.toldHeight then return end
    ui.toldHeight = h
    local W = NS.RaceWindow
    if W and W.OnHudResized then W.OnHudResized() end
end

-- The Race control (Retail) while Race mode is on and the Combat Sequence control while the Combat Sequence is, each
-- shown with the title bar, the strip laid again when either changes.
local function applyRace()
    local b, bar = ui.race, setting("hud.window.titleBar") ~= false
    local on, log = b ~= nil and NS.RaceMode.On() == true, NS.HudLog.ControlShown()
    if ui.header.withRace ~= on or ui.header.withLog ~= log then layoutHeader(on, log) end
    if b then b:SetShown(on and bar) end
    ui.log:SetShown(log and bar)
end

-- Every size change: the grip's size, in range, that a drag lays out from (plain numbers only), and
-- the rows it holds (dragPair, from the pair the grip went down on, noted at its first change).
local function trackSize(w, h)
    w, h = Secrets.PlainNumber(w), Secrets.PlainNumber(h)
    if not ui.down and NS.Sizing.IsSizing(ui.frame) then ui.down = { bars(), NS.HudLog.RowsSetting() } end
    if w then ui.dragW = clamp(w, Hud.MIN_WIDTH, Hud.MAX_WIDTH) end
    if h then ui.dragH = clamp(h, heightBounds()) end
    if ui.dragH then ui.dragBars, ui.dragRows = dragPair(ui.dragH) end
    NS.HudLog.SetDragRows(ui.dragH and ui.dragRows or nil)
end

local function hookPointer(f)
    f:SetScript("OnEnter", function() hovering = true end)
    f:SetScript("OnLeave", function()
        hovering = false
        if held then
            held = false
            startFade(Hud.LEAVE_DELAY)
        end
    end)
end

local function ensureWindow()
    if ui then return ui end
    local f = CreateFrame("Frame", Hud.FRAME_NAME, UIParent, "BackdropTemplate")
    ui = { frame = f, body = {} }
    f:Hide()
    f:SetFrameStrata(NS.Constants.LAYERS.STRATA.HUD)
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    buildHeader(f)
    buildFooter(f)
    applyRace()
    ui.content = CreateFrame("Frame", nil, f)
    NS.ApplySkin(f)
    f:SetScript("OnHide", function() onHide() end)
    hookPointer(f)
    -- Escape closes it with the standard close stack (standalone-windows).
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Hud.FRAME_NAME) end
    -- The grip (modules/Sizing.lua): while it is held each size change redraws the body at the
    -- dragged size (the beat's draw, no meter read); the release stores it (resized). A size change the
    -- grip did not start is the HUD's own SetSize, already laid out, so `redraw` has nothing to do.
    NS.Sizing.MakeResizable(f, {
        minWidth = Hud.MIN_WIDTH, minHeight = (heightBounds()),
        canResize = function() return canResize() end,
        size = trackSize, layout = function() render() end, redraw = function() end,
        done = function(w, h) resized(w, h) end,
    })
    applyPlacement()
    debug("window built")
    return ui
end

local function applyLock()
    NS.Style.SetControlIcon(ui.lock, locked and "lock" or "unlock", locked and "L" or "U")
    applyGrip()
end

-- The strip a sample fight wears: the sim's while a sim runs, else test mode's; nil before it is
-- built or with no Widgets library (the title then says it). Born hidden, and docked by the library
-- under the title bar (on the window's top edge while it is hidden): the HUD is a window
-- (preview-mode, *Where the strip sits*), and the content moves down by the strip's BodyOffset.
local STRIP_TEXT = { test = "Test mode: sample data. Nothing here is saved.",
                     sim = "Sim: a made-up fight, not your data. /ct sim ends it." }
local STRIP_MAKER = { test = "MakeTestStrip", sim = "MakeSimStrip" }

local function stripFor(which)
    local field = which .. "Strip"
    if not ui[field .. "Tried"] then
        ui[field .. "Tried"] = true
        ui[field] = NS[STRIP_MAKER[which]](ui.frame, L[STRIP_TEXT[which]],
            { titleBar = NS.Style.Band(ui.frame), window = ui.frame })
    end
    return ui[field]
end

-- The strip for the fight on screen shown (and the other hidden); a change moves the content, so the
-- window's look is laid out again (applyWindow moves the content by the strip's BodyOffset).
local function applyStrip()
    local P = NS.Preview
    local want = cur and cur.sample and P and P.Mode() or nil
    if want == ui.stripMode then return end
    ui.stripMode, ui.stamp = want, nil
    local shown = want and stripFor(want) or nil
    for _, which in ipairs({ "test", "sim" }) do
        local strip = ui[which .. "Strip"]
        if strip then strip:SetShown(strip == shown) end
    end
    ui.frame.title:SetText(want and not shown and L["Combat Trail (sample)"] or L["Combat Trail"])
end

-- The window's configured look (modules/Hud_Appearance.lua), once per Appearance stamp: the title
-- bar and its title, the footer, the content's insets, the background, border, strata and opacity.
local function applyWindow()
    local A, logH = NS.HudAppearance, NS.HudLog.Height()
    if ui.stamp == A.stamp and ui.logH == logH then return end
    ui.stamp, ui.logH = A.stamp, logH
    local f = ui.frame
    local bar, foot = A.On("hud.window.titleBar"), A.On("hud.window.footer")
    for _, part in ipairs({ ui.close, ui.lock, ui.settings, ui.results, ui.drag, NS.Style.Band(f) }) do
        part:SetShown(bar)
    end
    applyRace()
    f.title:SetShown(bar and A.On("hud.window.title"))
    ui.foot:SetShown(foot)
    ui.content:ClearAllPoints()
    ui.content:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -contentTop())
    ui.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, contentBottom())
    A.ApplyWindow(f)
end

local function showBody(which)
    local body = ui.body[which]
    if not body then
        body = NS.HudStates.Build(which, ui.content)
        ui.body[which] = body
    end
    body.onScroll = render
    if ui.current ~= which then
        local old = ui.current and ui.body[ui.current]
        if old then old.frame:Hide() end
        ui.current = which
    end
    body.frame:Show()
    return body
end

-- ── the view ────────────────────────────────────────────────────────────────────────────────────

-- The clock: from the first hit (plain GetTime()), or the fight's length once it is over.
local function clockOf()
    local fight = cur
    if not fight then return 0 end
    local first = fight.firstHitT or fight.startT
    if fight.frozen and key ~= "over" then return fight.frozen end
    if key == "over" then
        local final = view.final
        local d = final and Secrets.PlainNumber(final.duration)
        if d then return d end
        local stop = fight.closedT or fight.combatEndT or GetTime()
        return math.max(0, stop - (first or stop))
    end
    if type(first) ~= "number" then return 0 end
    return math.max(0, GetTime() - first)
end

-- Whether the race beat draws the clock (Task W5): it runs, for the fight live on the window.
local function onBeat()
    local RC = NS.RaceClock
    return cur ~= nil and key == "live" and RC ~= nil and RC.Fight() == cur
end

local function hasPet()
    if key == "over" then
        local pet = view.final and view.final.pet
        return type(pet) == "table" and Secrets.PlainNumber(pet.total) ~= nil
    end
    -- A folding client's dash (Meter.ReadLive's petDash) shows the row too, with no figure.
    return type(live) == "table" and (live.pet ~= nil or live.petDash == true)
end

-- Seconds since the fight's combat entry: the slices' and the casts' zero (the chart's time axis).
local function sinceStart()
    local t = cur and cur.startT
    if type(t) ~= "number" then return 0 end
    if cur.frozen and key ~= "over" then return cur.frozen + ((cur.firstHitT or t) - t) end
    if key == "over" then
        local d = view.final and Secrets.PlainNumber(view.final.duration)
        if d then return d end
    end
    return math.max(0, GetTime() - t)
end

-- The fight's casts and their base cooldowns, read again at most every Hud.CAST_READ seconds while
-- it is live (the chart's icons); the over card keeps the last read, or the record's own.
local function readCasts(v)
    if v.key ~= "live" or not cur or not NS.Casts then return end
    local now = GetTime()
    if v.castsAt and now - v.castsAt < Hud.CAST_READ then return end
    v.castsAt = now
    local casts, spells
    if cur.sample then casts, spells = NS.MockFights.CastsAt(cur.plan, sinceStart())
    else casts, spells = NS.Casts.Live(cur.id) end
    if casts then v.casts, v.castSpells = casts, spells end
end

-- The pace bar's view: the live totals (opaque) or the plain final ones, against the curve.
local function paceView(v)
    local curve = v.curve
    if not curve or v.pace == nil then return nil end
    if v.key == "over" then return NS.HudBest.OverView(curve, v.final, v.clock) end
    return NS.HudBest.LiveView(curve, v.clock, v.live)
end

-- The over card's spell rows: the merged plain read, highest first, and its total.
local function finalSpells(v)
    local merged = v.final and v.final.merged
    if type(merged) ~= "table" then
        v.finalSpells, v.finalTotal = v.record and NS.Recorder.Spells(v.record) or {}, v.record and v.record.damage
            and v.record.damage.merged or 0
        return
    end
    local out = {}
    for _, sp in ipairs(type(merged.spells) == "table" and merged.spells or {}) do
        local id, total = Secrets.PlainNumber(sp.spellID), Secrets.PlainNumber(sp.total)
        if id and total then out[#out + 1] = { spellID = id, total = total, isPet = sp.isPet == true } end
    end
    v.finalSpells, v.finalTotal = out, Secrets.PlainNumber(merged.total) or 0
end

-- The extras' views (plan Task 3.2): the pace bar, the damage chart, the over card's rows.
local function fillExtras(v)
    readCasts(v)
    local cooldowns = NS.HudChart.Cooldowns(v.casts, v.castSpells)
    v.paceView = paceView(v)
    if not cur then
        v.chartView = nil
    elseif v.key == "over" then
        v.chartView = NS.HudChart.OverView(cur, v.curve, v.final, cooldowns)
        finalSpells(v)
    else
        v.chartView = NS.HudChart.LiveView(cur, v.curve, v.live, sinceStart(), cooldowns)
    end
    -- A shared session's columns hold the damage from before the race's arm: no chart (DPS Race's rule).
    if cur and onSharedSession(cur) then v.chartView = nil end
end

-- The view the bodies draw: the fight's facts plus this moment's settings and figures.
local function fill()
    local v = view
    v.key = key or "live"
    v.live = live
    v.layout = setting("hud.layout") or {}
    v.clock = clockOf()
    v.hasPet = hasPet()
    -- The rows' window (modules/Hud_States.lua): the bars and the window's room for the stack; while
    -- the grip is held, the dragged size's (its rows the pair dragPair walked to).
    local drag = sizing()
    v.width = (drag and ui.dragW or width()) - 2 * PAD
    v.bars = drag and ui.dragBars or bars()
    v.fitH = (drag and ui.dragH or Hud.FixedHeight()) - chromeHeight()
    v.showSkipReason = setting("hud.showSkipReason") ~= false
    v.minLength = setting("history.minLength")
    fillExtras(v)
    return v
end

local function footer(v)
    local snap = cur and cur.snapshot
    local who = type(snap) == "table" and snap.who or {}
    local parts = {}
    for _, s in ipairs({ Secrets.PlainString(who.specName), Secrets.PlainString(who.name) }) do
        if s then parts[#parts + 1] = s end
    end
    ui.footLeft:SetText(table.concat(parts, " \194\183 "))
    local right = ""
    if v.key == "live" and cur then right = L["live \194\183 %d Hz"]:format(Hud.RefreshRate()) end
    if v.key == "over" then
        if pinned then right = L["Pinned open"]
        elseif fadeAt and not held then right = L["Fades %d s after the fight"]:format(tonumber(setting("hud.fadeAfter")) or 0) end
    end
    ui.footRight:SetText(right)
end

function render()
    applyStrip()
    applyWindow()
    ui.rendered = true
    local v = fill()
    local body = showBody(v.key)
    body:Update(v)
    -- The grip owns the size while it is held.
    if not sizing() then
        ui.height = Hud.FixedHeight()
        ui.frame:SetSize(width(), ui.height)
    end
    footer(v)
    NS.HudLog.Place(ui.frame, PAD, footInset(), Hud.LogWidth())
    tellHeight()
    return v
end

-- The grip's release (or a hide while it was held): the window re-anchored where the drag left it,
-- the width and the whole rows the height holds (dragPair: both counts while both take the height)
-- stored through the seam, and the window snapped to them by the redraw that follows.
function resized(w, h)
    w = Secrets.PlainNumber(w) or ui.dragW
    h = Secrets.PlainNumber(h) or ui.dragH
    local b, l
    if h then b, l = dragPair(clamp(h, heightBounds())) end
    ui.dragW, ui.dragH, ui.down, ui.dragBars, ui.dragRows = nil, nil, nil, nil, nil
    NS.HudLog.SetDragRows(nil)
    placeAfterDrag()
    if w then NS.SetByPath("hud.width", clamp(math.floor(w + 0.5), Hud.MIN_WIDTH, Hud.MAX_WIDTH)) end
    if b and barsTake() then NS.SetByPath("hud.bars", b) end
    if l then NS.SetByPath("sequence.drawer.rows", l) end
    if Hud.IsShown() then Hud.Refresh() end
end

local function hideWindow()
    if windowShown() then
        hiding = true
        ui.frame:Hide()
        hiding = false
    end
end

-- The Race window follows the HUD (W29): hidden with it (still wanted) or back with it; `playerClose`
-- (Escape) closes one still up as the player's close. It never calls back into Hud.Refresh: no loop.
local function syncRace(playerClose)
    local W = NS.RaceWindow
    if not W then return end
    if playerClose and W.Visible and W.Visible() then return W.Hide() end
    if W.FollowHud then W.FollowHud() end
end

-- The frame went away by Escape or the close control: the player closed it. A frame still shown in
-- its own right was hidden with its parent (the interface hidden, a cinematic), which is not.
function onHide()
    if hiding or (ui and ui.frame:IsShown()) then return end
    if wanted then closes = closes + 1 end
    wanted, byPlayer, pinned, hovering, dummyShown, raceShown, pullShown = false, false, false, false, false, false, false
    cancelFade()
    if cur then dismissed = cur.id end
    syncRace(not closing)
end

-- ── the public surface ──────────────────────────────────────────────────────────────────────────

--- Whether the HUD decides to be up: wanted, and the addon standing.
function Hud.IsShown()
    return wanted and not isDown()
end

--- The HUD's state (Hud.STATE): hidden, live, noBest or over.
--- @return string
function Hud.State()
    if not Hud.IsShown() then return STATE.HIDDEN end
    if key == "over" then return STATE.OVER end
    if key == "live" and cur and view.pace == nil then return STATE.NO_BEST end
    return STATE.LIVE
end

--- Re-decide and redraw. The one place the frame follows the decision.
function Hud.Refresh()
    locked = setting("general.locked") == true
    if not Hud.IsShown() then
        hideWindow()
        Hud.SyncBeat()
        NS.HudLog.Sync()
        return syncRace(false)
    end
    ensureWindow()
    applyLock()
    applyPlacement()
    render()
    applyRace()
    applyGrip()   -- after the strip is placed: its height is in the bounds
    if not windowShown() then ui.frame:Show() end
    -- A stored point off the top edge (arriving with a profile): moved onto it once the window is
    -- placed and sized (a no-op while it already sits on the edge).
    normalizeAnchor(false)
    Hud.SyncBeat()
    NS.HudLog.Sync()
    syncRace(false)
end

--- Open the window. `reason` "auto" is the addon's own opening, which fades after the fight; any
--- other (the player's: the toggle, the verb, the launcher) never fades.
--- @param reason string|nil
function Hud.Show(reason)
    wanted = true
    byPlayer = reason ~= "auto"
    if byPlayer then
        dummyShown, raceShown, pullShown = false, false, false
        cancelFade()
    end
    Hud.Refresh()
end

--- The race's open of the Race window with the HUD closed (W29 D3): an "auto" open, held by the race
--- and let go at its idle edge (Hud.OnRaceIdle). A HUD already wanted is left as it is.
--- @return boolean opened
function Hud.ShowForRace()
    if wanted or isDown() then return false end
    wanted, byPlayer, raceShown = true, false, true
    debug("opened for the Race window")
    Hud.Refresh()
    return true
end

--- Close the window (the player's close): it stays closed for the rest of the fight on screen.
function Hud.Hide()
    if wanted then closes = closes + 1 end
    wanted, byPlayer, pinned, dummyShown, raceShown, pullShown = false, false, false, false, false, false
    cancelFade()
    if cur then dismissed = cur.id end
    Hud.Refresh()
end

--- The toggle's closing half (`/ct hud hide` too): the HUD, and the Race window with it when that is
--- open (read first: the HUD's close hides it still wanted), each the player's close.
function Hud.HideWithRace()
    local W = NS.RaceWindow
    local raceUp = W ~= nil and W.IsShown ~= nil and W.IsShown()
    Hud.Hide()
    if raceUp then W.Hide() end
end

-- Whether the toggle's open takes the Race window too: Race mode on, either auto-show row on (W29 D4)
-- and its dummy session live (modules/AutoArm.lua). WoW Forever has no Race window.
local function raceWithToggle()
    local W, A = NS.RaceWindow, NS.AutoArm
    if not (W and W.Show and W.IsShown and A and A.InSession) then return false end
    local auto = setting("race.autoShow") == true or setting("race.autoShowHud") == true
    return NS.RaceMode.On() and auto and A.InSession() == true
end

--- The player's toggle (the HUD key, the launcher, `/ct hud toggle`): closing takes the Race window
--- with it (Hud.HideWithRace); opening opens the HUD, and near a training dummy with auto-show on
--- the Race window too (the player's open, tied to the dummy session, whatever closed it before).
function Hud.Toggle()
    if Hud.IsShown() then return Hud.HideWithRace() end
    Hud.Show()
    if raceWithToggle() and not NS.RaceWindow.IsShown() then NS.RaceWindow.Show() end
end

--- Pin the window open (it never fades), or let it go (an over card starts its fade again).
--- @param on boolean
function Hud.Pin(on)
    pinned = on == true
    if pinned then
        cancelFade()
        wanted, dummyShown, raceShown = true, false, false
    elseif key == "over" then
        startFade()
    end
    Hud.Refresh()
end

function Hud.IsPinned() return pinned end

--- The Locked row's reaction: no drag while locked.
function Hud.SetLocked(on)
    locked = on == true
    if ui then applyLock() end
end

function Hud.IsLocked() return locked end

--- Back to the default place (the Master controls' Reset position).
function Hud.ResetPosition()
    local p, d = position(), shipped("hud.position")
    if p and type(d) == "table" then
        for k in pairs(p) do p[k] = nil end
        for k, v in pairs(d) do p[k] = v end
    end
    if ui then
        applyPlacement()
        normalizeAnchor(false)
    end
end

--- The view the bodies draw now, for the suites and the parts that stack under it (plan Task 3.2).
function Hud.View() return view end

--- A `hud.*` look or layout changed: every part restyles (HudAppearance.Changed) and the HUD
--- redraws now. The DPS HUD page's rows (plan Task 3.3) and the settings seam call it.
function Hud.Apply()
    NS.HudAppearance.Changed()
end

--- The over card's chip texts on screen, in order (the suites read these).
function Hud.Chips()
    local body = ui and ui.body.over
    if not body then return {} end
    return body.w.chips:Texts()
end

--- When the fade will close the window (GetTime() seconds), or nil while none runs.
function Hud.FadeAt() return fadeAt end

--- The lifecycle's stand-down: the window hides, the fade goes, the fight on screen is dropped. A
--- window the addon opened is let go; one the player opened comes back at the stand-up.
function Hud.Suspend()
    cancelFade()
    beatTimer, beatEvery = nil, nil     -- the stand-down's CancelAllTimers took it
    if not byPlayer then wanted, pinned, dummyShown, raceShown = false, false, false, false end
    cur, pending, key, view, live, hovering = nil, nil, nil, {}, nil, false
    hideWindow()
end

--- Drop the sample fight on screen (test mode or the sim ended, modules/Preview.lua): its body goes,
--- and with `release` a window the preview opened is let go too, unless the player opened it, pinned
--- it or keeps it always up, and a real race that ended the preview by its arm takes it over (W29),
--- let go at its idle edge. A real fight on screen or waiting for its first hit is left alone.
--- @param release boolean|nil
function Hud.EndSample(release)
    if pending and pending.sample then pending = nil end
    if cur and cur.sample then
        cancelFade()
        cur, key, view, live = nil, nil, {}, nil
    end
    if release and not (byPlayer or pinned) and setting("hud.show") ~= "always" then
        if raceHolds() then raceShown = true else wanted = false end
    end
    Hud.Refresh()
end

--- The login and the stand-up (core/CombatTrail.lua NS.RegisterGameEvents): "always" opens it.
function Hud.Sync()
    if setting("hud.show") == "always" then wanted = true end
    Hud.Refresh()
end

Hud.Resume = Hud.Sync

-- ── near a training dummy (Task W3): modules/AutoArm.lua's four hooks ───────────────────────────

--- The dummy session's opening, asked by the Race window (W29): an "auto" open, again after a fade. A
--- HUD already wanted is left as it is; one a race opened (ShowForRace) is taken over by the dummy.
--- @return boolean opened
function Hud.ShowNearDummy()
    if isDown() then return false end
    if wanted then
        if raceShown then dummyShown, raceShown = true, false end
        return false
    end
    wanted, byPlayer, dummyShown, raceShown = true, false, true, false
    debug("opened near a training dummy")
    Hud.Refresh()
    return true
end

--- The dummy session's end: a HUD ShowNearDummy opened closes, unless a fight is live on it or the
--- player opened or pinned it since (either takes the open over). A HUD left up on its over card,
--- which the session held (dummyHolds), starts its fade now (overCard off: its close, LEAVE_DELAY on).
--- @return boolean closed
function Hud.HideAwayFromDummy()
    local mine = dummyShown
    dummyShown = false
    if mine and wanted and not (byPlayer or pinned) and key ~= "live" then
        wanted = false
        cancelFade()
        Hud.Refresh()
        return true
    end
    if wanted and key == "over" then
        if closesWithFight() then startFade(Hud.LEAVE_DELAY) else startFade() end
    end
    return false
end

--- Whether the HUD stands opened by the dummy session (it may have faded since).
function Hud.ShownNearDummy() return dummyShown end

--- How many times the player has closed the HUD.
function Hud.Closes() return closes end

-- ── the fight, heard on the bus ─────────────────────────────────────────────────────────────────

local readLive

-- Whether the beat may read the fight on the window: a sample's plan always, a real fight while Fight
-- holds it in combat (FIGHT_TICK's own window: no read in its settle).
local function reading()
    if cur.sample then return true end
    local Fight = NS.Fight
    return Fight.State() == Fight.STATE.COMBAT and Fight.Current() == cur
end

-- One beat of the live fight: a read (while `reading`) and the whole redraw.
local function liveBeat()
    local t0 = Perf.on and debugprofilestop()
    if reading() then
        -- Shared with FIGHT_TICK's slices read when both land in one frame (Meter.ShareLive).
        NS.Meter.ShareLive(true)
        readLive()
        NS.Meter.ShareLive(false)
    end
    render()
    if t0 then Perf.Note("hud", debugprofilestop() - t0) end
end

function readLive()
    local fight = cur
    if fight.sample then
        live = NS.MockFights.LiveAt(fight.plan, sinceStart())
        return
    end
    local sessions = fight.sessions
    local id = (type(sessions) == "table" and sessions[#sessions]) or fight.sessionID
    live = NS.Meter.ReadLive(id)
end

-- The first hit: the fight goes on screen (opening the window when the mode allows it).
local function goLive(fight)
    pending, cur, key, live, dismissed, pullShown = nil, fight, "live", nil, nil, false
    view = newView(fight)
    -- A new fight's rows start at the top.
    if ui then for _, body in pairs(ui.body) do body.offset = 0 end end
    cancelFade()
    if fight.sample then
        wanted = true
    elseif not (byPlayer or pinned) then
        -- A HUD a training dummy opened (Hud.ShowNearDummy) stays up through the first hit.
        wanted = autoAllowed(fight) or (wanted and dummyShown)
    end
    debug("fight %s live (pace %s)", tostring(fight.id), view.pace and tostring(view.pace.id) or "none")
    if Hud.IsShown() then readLive() end
    Hud.Refresh()
end

function Hud.OnFightStarted(fight)
    if isDown() or type(fight) ~= "table" then return end
    pending = fight
    -- The last fight's card stays until this one's first hit, and stops fading meanwhile.
    cancelFade()
    -- Open when a fight starts (SM-CT-LG22, R4-CT-08): a closed or hidden HUD opens at the pull, an auto
    -- open, where the show mode lets one (autoAllowed: never under "toggle"; the master row, instancesOnly).
    if setting("hud.openOnPull") ~= false and not wanted and autoAllowed(fight) then
        Hud.Show("auto")
        pullShown = true
    end
    if fight.firstHitT then goLive(fight) end
end

function Hud.OnFightTick(fight)
    if isDown() or type(fight) ~= "table" then return end
    if fight == pending then
        if fight.firstHitT then goLive(fight) end
        return
    end
    if fight ~= cur or key ~= "live" or not windowShown() then return end
    -- A beat reads and redraws at `hud.refreshRate`: FIGHT_TICK stands in only while none runs.
    if beatTimer or onBeat() then return end
    liveBeat()
end

--- The player's damage in the HUD's last live read (the beat's NS.Meter.ReadLive, or a sample
--- fight's plan) of `fight`, opaque: a secret in combat, for a label alone (NS.Format.Number). The
--- second answer, plain, says whether there is one: false when `fight` is not the one live on the
--- HUD or nothing was read yet. The third, plain, says whether that read carries the pet on a live
--- source of its own (HudBest.LiveView's playerOnly): the total is then the player's alone. Never a
--- second read.
--- @param fight table|nil
--- @return any total, boolean has, boolean petOwn
function Hud.LiveDamage(fight)
    if fight == nil or fight ~= cur or key ~= "live" or type(live) ~= "table" then return nil, false, false end
    local player = live.player
    if type(player) ~= "table" then return nil, false, false end
    local total = player.total
    return total, Secrets.IsPresent(total), type(live.pet) == "table"
end

--- The race beat (modules/RaceClock.lua, Task W5): while the fight live on the window is the race's,
--- one read and the whole redraw, before the beat's RACE_CLOCK sends the Race window the same read.
function Hud.OnRaceClock()
    if isDown() or not windowShown() or key ~= "live" or not onBeat() then return end
    liveBeat()
end

-- ── the HUD's own beat outside a race (owner, 2026-11-13) ───────────────────────────────────────

Hud.REFRESH_RATE = 10           -- `hud.refreshRate`'s default
Hud.REFRESH_RATES = { [4] = true, [5] = true, [10] = true, [20] = true }

--- The refreshes a second (`hud.refreshRate`, an offered rate, else the default): both windows'.
--- @return number
function Hud.RefreshRate()
    local rate = tonumber(setting("hud.refreshRate"))
    return Hud.REFRESH_RATES[rate] and rate or Hud.REFRESH_RATE
end

--- The beat's interval (s): 1 / Hud.RefreshRate(). The race beat runs at it too.
--- @return number
function Hud.RefreshInterval() return 1 / Hud.RefreshRate() end

-- Whether the HUD's own beat should run: up on a live fight that moves, no race beat on it.
local function beatWanted()
    return not isDown() and windowShown() and key == "live" and cur ~= nil and not cur.frozen and not onBeat()
end

local function ownBeat()
    if not beatWanted() then return Hud.SyncBeat() end
    liveBeat()
end

--- Re-decide the HUD's own beat: on (at Hud.RefreshInterval) while it is wanted, else off.
function Hud.SyncBeat()
    local want, addon = beatWanted(), NS.addon
    local interval = Hud.RefreshInterval()
    if beatTimer and (not want or beatEvery ~= interval) then
        if addon and addon.CancelTimer then addon:CancelTimer(beatTimer) end
        beatTimer, beatEvery = nil, nil
    end
    if want and not beatTimer and addon and addon.ScheduleRepeatingTimer then
        beatTimer, beatEvery = addon:ScheduleRepeatingTimer(ownBeat, interval), interval
    end
end

--- The HUD's own beat's interval while it runs, else nil (the suites).
function Hud.BeatEvery() return beatEvery end

-- `hud.overCard` off: an auto-opened HUD closes with its fight, not while a race holds it (W29 D2).
function closesWithFight()
    return setting("hud.overCard") == false and not (byPlayer or pinned) and setting("hud.show") ~= "always"
        and not (cur and cur.sample) and not raceHolds() and not dummyHolds()
end

function Hud.OnFightEnded(fight, final, reason)
    if isDown() then return end
    if fight == pending then
        -- A fight with no hit never reached the screen: the card still up may fade now, and so may a
        -- HUD the pull opened with no card behind it (key nil: the first fight since login, an arm or
        -- a sample's end), as an over card would (overCard off: its close, LEAVE_DELAY on). R4-REV.
        local mine = pullShown
        pending, pullShown = nil, false
        if key == "over" then startFade()
        elseif mine then startFade(closesWithFight() and Hud.LEAVE_DELAY or nil) end
        return
    end
    if fight ~= cur then return end
    key = "over"
    view.final = type(final) == "table" and final or nil
    view.lost = reason ~= "final"
    view.endedAt = GetTime()
    if closesWithFight() then wanted = false end
    startFade()
    Hud.Refresh()
end

function Hud.OnFightSaved(record)
    if isDown() or type(record) ~= "table" or not cur or cur.recordID ~= record.id then return end
    view.saved, view.skipReason, view.record = true, nil, record
    -- The stored casts are the whole fight's: the chart's icons take them over the last live read.
    local casts = type(record.casts) == "string" and NS.CastCodec.Decode(record.casts) or nil
    if casts then view.casts, view.castSpells = casts, record.cooldowns or {} end
    -- The stored identity names the meter's primary target, which the live line could only guess.
    if type(record.identity) == "table" then view.targetLine = targetLine(record.identity) end
    judge(record)
    if key == "over" then Hud.Refresh() end
end

--- A race's clock started on `fight` (RACE_STARTED): the fight already live paces on its race board
--- now (Task C3), and one the HUD's own rules kept shut opens (ruling X7), whichever of FIGHT_STARTED's
--- receivers ran first.
function Hud.OnRaceStarted(fight)
    if isDown() or type(fight) ~= "table" or fight ~= cur or key ~= "live" then return end
    repace(fight)
    if not wanted then wanted = autoAllowed(fight) end
    if not Hud.IsShown() then return end
    readLive()
    Hud.Refresh()
end

--- A race resumed after a /reload or a stand-up (RACE_STATE_CHANGED from idle to running or stopping,
--- Race.Resume): its fight came back through Fight.Adopt, which sends no FIGHT_STARTED, so the HUD
--- takes it up here, live and paced on its race board, and a race's fight opens it (ruling X7). A
--- stopping race's fight is read at once: its FIGHT_ENDED turns this into the card.
function Hud.OnRaceStateChanged(from, to)
    if isDown() then return end
    if to ~= "idle" then cancelFade() elseif from ~= "idle" then return Hud.OnRaceIdle() end
    if from ~= "idle" or (to ~= "running" and to ~= "stopping") then return end
    local fight = NS.Race and NS.Race.Fight and NS.Race.Fight()
    if type(fight) ~= "table" or not fight.resumed or fight == cur or fight == pending then return end
    Hud.OnFightStarted(fight)
end

--- The race is idle again (W29 D2): an over card starts its fade (overCard off: its close, LEAVE_DELAY
--- on); a HUD ShowForRace opened with no fight since closes. A sample sends no edge (EndSample lets go).
function Hud.OnRaceIdle()
    if isDown() then return end
    local mine = raceShown
    raceShown = false
    if key == "over" then
        if closesWithFight() then startFade(Hud.LEAVE_DELAY) else startFade() end
    elseif mine and key ~= "live" and not (byPlayer or pinned) then
        wanted = false
        debug("the race that opened it is idle")
        Hud.Refresh()
    end
end

--- A race was armed (RACE_ARMED): the fight still on screen goes, and the HUD draws its look before
--- any fight, as at its first open. A live fight stays (an arm wants Fight idle, so none should be).
function Hud.OnRaceArmed()
    if isDown() or not cur or key == "live" then return end
    debug("race armed: fight %s let go", tostring(cur.id))
    cur, key, view, live, dismissed = nil, nil, {}, nil, nil
    if ui then for _, body in pairs(ui.body) do body.offset = 0 end end
    if Hud.IsShown() then Hud.Refresh() end
end

--- A race was canceled (RACE_CANCELED): the live fight it rode, its part gone, paces on its dummy's
--- fight board again.
function Hud.OnRaceCanceled()
    if isDown() or not cur or key ~= "live" or not view.raced or cur.race ~= nil then return end
    repace(cur)
    if Hud.IsShown() then Hud.Refresh() end
end

function Hud.OnFightSkipped(fight, reason)
    if isDown() or fight ~= cur then return end
    view.saved, view.skipReason = false, reason
    if key == "over" then Hud.Refresh() end
end

--- A setting changed (SETTINGS_CHANGED, wired by modules/Hud_Wiring.lua): the window re-decided.
function Hud.OnSettings(path, value)
    if type(path) ~= "string" then return end
    if path == "hud.show" and value == "always" then wanted = true end
    if path == "profile" and setting("hud.show") == "always" and not isDown() then wanted = true end
    if path == "profile" or path:find("^hud%.") then Hud.Apply() end
    if (path == "race.enabled" or path == "profile") and ui then applyRace() end
    if path == "hud.refreshRate" or path == "profile" then Hud.SyncBeat() end
end

-- ── the fade's check ────────────────────────────────────────────────────────────────────────────

function fadeCheck()
    fadeTimer = nil
    if not fadeAt or isDown() then return end
    if not canFade() then fadeAt, held = nil, false return end   -- a race holds it now (W29 D2)
    local left = fadeAt - GetTime()
    if left > 0 then return schedule(left) end
    if setting("hud.holdOnMouse") ~= false and mouseOver() then
        -- Held: look again a moment later rather than wait for the frame's OnLeave, which never
        -- comes when the pointer leaves from a child (a chip, a title-bar control) that took it.
        held = true
        fadeAt = GetTime() + Hud.LEAVE_DELAY
        return schedule(Hud.LEAVE_DELAY)
    end
    fadeAt = nil
    wanted, raceShown, pullShown = false, false, false
    debug("faded")
    Hud.Refresh()
end

-- ── the title bar's acts ───────────────────────────────────────────────────────────────────

-- The close control (not Escape: the Race window hides with the HUD, still wanted, W29).
function Act.close()
    closing = true
    if windowShown() then ui.frame:Hide() end
    if wanted then onHide() end
    closing = false
end

function Act.lock() return NS.ToggleLock() end

--- The Combat Sequence control: the Combat Sequence drawer opened or closed (`/ct sequence`).
function Act.log() return NS.HudLog.SetShown() end

--- The Race control: `/ct race toggle`, the player's open or close of the Race window.
function Act.race() return NS.SetRaceWindowShown("toggle") end

--- The chart control: the fight on the card in the Results window, else the window itself.
function Act.results()
    local R = NS.Results
    local record = key == "over" and view.record or nil
    if R and record and type(R.ShowFight) == "function" then return R.ShowFight(record.id) end
    if R and type(R.Toggle) == "function" then return R.Toggle() end
    NS.Print(L["That part of Combat Trail is not built yet."])
end

--- What the HUD is doing, for the diagnostics report.
function Hud.Diagnose()
    return { state = Hud.State(), body = ui and ui.current or "none", pinned = pinned, byPlayer = byPlayer,
             locked = locked, fadeAt = fadeAt, beatEvery = beatEvery }
end

--- The HUD's window, or nil before it is first built.
function Hud.Frame() return ui and ui.frame or nil end

--- The window's height now: the grip's while it is held, else the height the last draw (or Hud.Dock)
--- gave it; nil before it is first sized. The Race window docked beside it reads it (Task W4).
--- @return number|nil
--- The width the docked log drawer is laid at (its chips wrap at it): the window's, the grip's while
--- it is held, less the content's insets. Worked out from the configuration, never measured.
function Hud.LogWidth() return (sizing() and ui.dragW or width()) - 2 * PAD end

function Hud.Height()
    if not ui then return nil end
    if sizing() then return ui.dragH end
    return ui.height
end

--- The HUD's window for the Race window to stand beside (race plan Task C1, Review focus 4): built
--- and placed where it stands even while hidden, and a window that never drew is given its fixed
--- size, so an attached Race window never falls to 0,0. A hidden window that drew before is placed
--- again and given its width (a profile or a setting may have moved them since). Shows nothing.
--- @return table frame
function Hud.Dock()
    ensureWindow()
    if not windowShown() then
        applyPlacement()
        if ui.rendered then
            ui.frame:SetWidth(width())
        else
            ui.height = Hud.FixedHeight()
            ui.frame:SetSize(width(), ui.height)
        end
        ui.docked = true
    end
    return ui.frame
end

--- The built window and its bodies, for the suites (nil until first shown).
function Hud.__ui() return ui end
