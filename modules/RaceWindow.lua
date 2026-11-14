local _, NS = ...
-- modules/RaceWindow.lua — the Race window's shell (Race mode spec §4, plan Task C1): the window, its
-- title bar and footer, where it stands (attached beside the DPS HUD or on its own), when it shows,
-- which body it draws for the race (modules/RaceWindow_States.lua) and the view that body draws, and
-- the acts its buttons run. Ported from DPS Race @f8078c7 (modules/Hud.lua) onto Combat Trail's race
-- (modules/Race.lua) and without what the DPS HUD draws for every fight (no meter events, no live
-- Damage or DPS, no chart, no spell rows: spec §4.2). Its name is never NS.Hud's: the frame is
-- CombatTrailRaceWindow.
--
-- THE LOOK IS THE DPS HUD'S (spec §4.3 and §8): the same shell (NS.ApplySkin, NS.MakeCloseButton, the
-- title band, the footer), the same HUD Appearance blocks (`hud.window.*`: the title bar, the title,
-- the footer, the background, the border, the strata, the opacity; `hud.scale`), restyled once per
-- Appearance stamp (HudAppearance.Changed refreshes this window too). It has no styling rows of its own.
--
-- WHERE IT STANDS. Attached (`raceWindow.attached`, on by default) it is anchored beside the DPS HUD's
-- frame on `raceWindow.side` (RIGHT by default; LEFT, TOP, BOTTOM), flush against it (DOCK_GAP 0,
-- race window redesign plan Task W4), its top or left edge level with the HUD's, so it moves with the
-- HUD; it is never the HUD's child, so each window shows and fades on its own rules. Both take
-- `hud.scale`, so equal heights line up. A HUD that is hidden, or was never shown, is still built and
-- placed where it would stand (Hud.Dock), so the window never falls to 0,0 (Review focus 4). Detached,
-- it stands at `raceWindow.position`, written by its title bar's drag; Detach keeps it where it stood.
-- The lock is Master controls' Lock frame (`general.locked`): no drag while locked, and none while
-- attached (it follows the HUD). Master controls' Reset position puts the detached place back.
--
-- ITS HEIGHT (Task W4, ruling O3). Its least, RW.Height(): the chrome and the content the tallest body
-- needs. Attached LEFT or RIGHT with `raceWindow.matchHud` on (the default), it takes the DPS HUD's
-- height instead (Hud.Height(): its fixed or grown height, or the grip's while held), never less than
-- its least; the HUD tells it each time that height changes (RW.OnHudResized: the bars, auto-grow, the
-- grip, the title bar or footer, a layout part), so the two stay level. TOP, BOTTOM, detached or the
-- row off: `raceWindow.height`, never less than its least (the default 0 is its least). The bodies
-- fill the content frame, so their bottom buttons stay pinned to the window's bottom whatever its
-- height, and the view carries the content's height (`height`) and width (`width`).
--
-- ITS WIDTH AND THE GRIP (owner, 2026-11-13). Its width is `raceWindow.width` (WIDTH, the least, to
-- MAX_WIDTH). The library's grip (modules/Sizing.lua, as the DPS HUD's) shows only while unlocked
-- (`general.locked` off). Matched to the HUD's height it drags the width alone (its bounds hold the
-- height); TOP, BOTTOM, detached or `raceWindow.matchHud` off it drags both, down to the least height.
-- While it is held the body lays out at the dragged size; the release stores the width, and the
-- height when it is not matched (both rows skipRender: the grip is their control, the Race window
-- tab's Defaults puts them back), keeps a detached window's top left where it stood, and redraws.
--
-- WHEN IT SHOWS (DPS Race's rules, spec §4.1). Never with Race mode off (NS.RaceMode.On()), stood down
-- or on WoW Forever, where nothing here loads. Opened by the player (`/ct race show|toggle`, through
-- NS.SetRaceWindowShown), by auto-show near a training dummy (modules/AutoArm.lua's five hooks:
-- ShowNearDummy, HideAwayFromDummy, ShownNearDummy, Closes, ArmLength), by an arm, by a resumed race
-- and by a result. A window the addon opened for a race closes when that race goes back to idle,
-- unless a dummy is near; one the player opened stays. THE PLAYER'S OPEN IN A DUMMY SESSION: a window
-- the player opens while auto-show's dummy session is live (AutoArm.InSession) is tied to that
-- session as auto-show's own opening is, so walking away closes it and the next session opens it
-- again; one that was already up before the session began stays the player's. The player's close
-- counts (Closes), so auto-show leaves the window shut for the rest of that dummy session; closing a
-- result card dismisses it (Race.Cancel), the saved race staying in the history. Attach and Detach
-- move the window only: neither changes who opened it. The DPS HUD's Race control (Task W2) toggles
-- it as `/ct race toggle` does, and the HUD's own toggle closes it with the HUD (Hud.HideWithRace).
--
-- AN EXTENSION OF THE DPS HUD (owner, 2026-11-13; race window redesign plan W29, decisions D1 and
-- D3). The window is up only while the HUD is up: RW.IsShown asks Hud.IsShown, and the HUD's every
-- Refresh ends by calling RW.FollowHud, so a HUD that hides for any reason (its fade, `hud.overCard`'s
-- close, its close control, the toggle, a stand-down) takes this window down with it. Hiding with the
-- HUD is not the player closing this window: `wanted` stands, and the window comes back when the HUD
-- does. Only the player's close of this window (its close control, `/ct race hide|toggle`, Escape on
-- it) and the auto-close rules (a race's idle edge, a dummy session's end) let `wanted` go. The other
-- way round, every open path here opens the HUD first when it is closed (openHud): the player's opens
-- (Show, the toggle, the stand-up and Race mode back on for a window the player opened) through
-- Hud.Show, the race's (an arm, a resume, a result, a sample) through Hud.ShowForRace, and a dummy
-- session's through Hud.ShowNearDummy, so each can close by its own rule later. Escape closes both
-- windows, each as the player's close (modules/Hud.lua's header).
--
-- WHAT RUNS. Bus receivers (RACE_STATE_CHANGED, RACE_RESULT, RACE_CLOCK, FIGHT_ENDED, FIGHTS_CHANGED,
-- SETTINGS_CHANGED) on its own target; while shown and the race idle or armed, the target, the regen
-- edges and the spec change on its own AceEvent target (the target card, Arm's refusal, the best's
-- board); while shown and the race running or stopping, each RACE_CLOCK (the race beat,
-- modules/RaceClock.lua: `hud.refreshRate`, 10 a second by default, Task W5; the beat has the DPS HUD
-- read the meter and redraw just before it sends RACE_CLOCK) redraws the race clock, the time bar,
-- Best by now with Current, the mini pace bars, the Checkpoints and the stop figures, timed into the
-- perf harness's `raceWindow` bucket. It has no timer of its own and reads no meter: the player's
-- damage it draws, as text and on the mini pace bars, is the DPS HUD's read of that same beat
-- (Hud.LiveDamage);
-- nothing else polls and no OnUpdate is set. The stand-down drops every
-- registration (and the beat with RaceClock's Suspend).
--
-- NO DECISION FROM A METER VALUE. The clocks and the time bar are Race's GetTime() figures; Best to
-- beat, Best by now and the Checkpoints are the race board's best and its straight line
-- (NS.HudBest.RaceCurve); the result card, Against your best and Top races are stored records' (Tasks
-- W6 and W7). The one live figure, the player's damage beside Best by now and in each Checkpoint
-- (owner, 2026-11-13), is the DPS HUD's last read of the race's fight (Hud.LiveDamage: a sample's is
-- its plan's), opaque: a secret in combat, handed to a label through NS.Format.Number and never
-- compared, computed on, keyed or tested. A checkpoint keeps the reading of the beat the race clock
-- passed it, held in this file's memory for that race alone (never saved), with a plain flag beside
-- it saying whether there is one. The last checkpoint, at the race length, is passed only at the
-- buzzer, when the race has left running: the stopping view takes it there (the board at the race's
-- end: the length, or an early end's time), with the HUD's last read, so all four show.
--
-- ONE RACE CLOCK (owner, 2026-11-13). The running view's elapsed time and time left are
-- NS.Format.RaceClock's: one count of tenths, the elapsed truncated as the DPS HUD's clock is and the
-- time left the rest of the length (rounded up), so the countdown, the time elapsed, the HUD's clock
-- and the center countdown (modules/Countdown.lua: whole seconds left, rounded up) agree: 0:00.0 only
-- at the buzzer, and the two clocks always add up to the length.
--
-- A RESULT CARD WHOSE RACE IS DELETED (its Delete, or a delete in the Results window): the window goes
-- back to the Arm Race screen at that race's length, as New Race does. One behavior for both, since the
-- Results window's confirmation takes no callback (R:hud#10).
--
-- A SAMPLE RACE (test mode's `/ct test race`, the sim's race scenarios, plan Task E1): while one is on
-- (NS.RaceSample.On()), every read and act below goes to it instead of NS.Race (src()), so its bodies
-- are drawn by the same path; its best, its Against your best and its Top races come from the sample
-- history (Results_Source, and Bests' sample-aware Before and Ranked). ShowSample and EndSample open and let go a window the preview opened.
--
-- RETAIL ONLY (clients-§4): nothing here loads on WoW Forever, so NS.RaceWindow is absent there.

if not NS.Compat.ForClient({ "retail" }) then return end

local RW = {}
NS.RaceWindow = RW

local L = NS.L
local Perf = NS.Perf
local Secrets = NS.Secrets

RW.FRAME_NAME = "CombatTrailRaceWindow"
RW.WIDTH = 260        -- DPS Race's window width, the least (the bodies' layout constants are tuned to it)
RW.MAX_WIDTH = 600    -- the grip's and `raceWindow.width`'s, the DPS HUD's own MAX_WIDTH
RW.MAX_HEIGHT = 1000  -- the grip's and `raceWindow.height`'s
RW.DOCK_GAP = 0       -- flush against the DPS HUD while attached (Task W4)
RW.SIDES = { "RIGHT", "LEFT", "TOP", "BOTTOM" }

local HEADER_H, FOOTER_H, PAD = NS.Style.TITLE_BAR_H, 20, 12

-- Each side: this window's point, the HUD's point, and the gap's direction.
local DOCK = {
    RIGHT  = { "TOPLEFT", "TOPRIGHT", 1, 0 },
    LEFT   = { "TOPRIGHT", "TOPLEFT", -1, 0 },
    TOP    = { "BOTTOMLEFT", "TOPLEFT", 0, 1 },
    BOTTOM = { "TOPLEFT", "BOTTOMLEFT", 0, -1 },
}
-- The control that docks a detached window shows the arrow toward the HUD from where it would stand.
local ATTACH_ICON = { RIGHT = "chevron-left", LEFT = "chevron-right", TOP = "chevron-down", BOTTOM = "chevron-up" }

local ui                        -- the built window
local wanted = false            -- the window should be up
local autoShown = false         -- the addon opened it (an arm, a result, a resume, a dummy)
local dummyShown = false        -- opened by auto-show near a dummy
local closes = 0                -- the player's closes, for auto-show's manual-close rule
local locked = false            -- general.locked
local hiding = false            -- the addon is hiding the frame itself
local pick = {}                 -- the idle body's pick: { length, editing }
local raceBest = {}             -- { race, record } : the race board's best the running race is after
local held = {}                 -- the running race's checkpoint readings (runningYou), memory only
local events                    -- this module's AceEvent target
local listening = false         -- the idle events are registered
local anchor                    -- the last place applied: { point, relativeTo, relPoint, x, y }
local view = {}                 -- the view the body on screen drew

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Race", fmt, ...) end
end

local function isDown() return NS.IsStoodDown ~= nil and NS.IsStoodDown() end
local function hudShown()
    local H = NS.Hud
    return H ~= nil and H.IsShown ~= nil and H.IsShown() == true
end
local function setting(path) return NS.Hud.Setting(path) end
local function S() return NS.Race.STATE end

-- The race the window draws: the sample race while one stands in (modules/RaceSample.lua), else Race.
local function src()
    local RS = NS.RaceSample
    if RS and RS.On() then return RS end
    return NS.Race
end
local function sampled() return src() ~= NS.Race end

local function racing()
    local st = src().State()
    return st == S().RUNNING or st == S().STOPPING
end

local function shipped(path)
    local node = NS.defaults and NS.defaults.profile
    for part in path:gmatch("[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

-- ── where it stands ─────────────────────────────────────────────────────────────────────────────

local function attached() return setting("raceWindow.attached") ~= false end

local function side()
    local s = setting("raceWindow.side")
    return DOCK[s] and s or "RIGHT"
end

local function position()
    local p = NS.db and NS.db.profile
    local rw = p and p.raceWindow
    if type(rw) ~= "table" then return nil end
    if type(rw.position) ~= "table" then rw.position = {} end
    return rw.position
end

local function windowShown() return ui ~= nil and ui.frame:IsShown() == true end

local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

-- Whether the grip is held now (the size it tracked is the one to lay out from).
local function sizing()
    return ui ~= nil and ui.dragW ~= nil and NS.Sizing.IsSizing(ui.frame)
end

-- Whether the height is the DPS HUD's: attached LEFT or RIGHT with `raceWindow.matchHud` on (Task W4).
local function matched()
    if not attached() or setting("raceWindow.matchHud") == false then return false end
    local s = side()
    return s == "LEFT" or s == "RIGHT"
end

local function applyPlacement()
    local f = ui.frame
    local hud = attached() and NS.Hud.Dock() or nil
    if hud then
        local d = DOCK[side()]
        anchor = { d[1], hud, d[2], d[3] * RW.DOCK_GAP, d[4] * RW.DOCK_GAP }
    else
        local p, d = position() or {}, shipped("raceWindow.position") or {}
        anchor = { p.point or d.point or "CENTER", UIParent, p.relPoint or d.relPoint or "CENTER",
                   tonumber(p.x) or d.x or 0, tonumber(p.y) or d.y or 0 }
    end
    f:ClearAllPoints()
    f:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
    -- The HUD's scale either way: docked offsets line up only at the same scale.
    f:SetScale(tonumber(setting("hud.scale")) or 1)
end

local function edgeOf(f, name)
    local fn = f[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, f)
    return ok and Secrets.PlainNumber(v) or nil
end

-- The place the drag left the frame (the client's anchor), stored plain.
local function savePosition()
    local p = position()
    if not (p and ui) then return end
    local point, _, relPoint, x, y = ui.frame:GetPoint(1)
    if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return end
    p.point, p.relPoint = point, type(relPoint) == "string" and relPoint or point
    p.x, p.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

-- The window's place where it stands now, as its detached place (the frame's own edges).
local function keepWhereItStands()
    local p = position()
    if not (p and ui) then return end
    local left, top = edgeOf(ui.frame, "GetLeft"), edgeOf(ui.frame, "GetTop")
    if not (left and top) then return end
    p.point, p.relPoint = "TOPLEFT", "BOTTOMLEFT"
    p.x, p.y = math.floor(left + 0.5), math.floor(top + 0.5)
end

-- ── the window ──────────────────────────────────────────────────────────────────────────────────

local Act = {}
RW.Act = Act

local function canDrag() return not locked and not attached() end

local function buildHeader(f)
    local Style = NS.Style
    f.title = f:CreateFontString(nil, "OVERLAY", Style.FONT.TITLE)
    f.title:SetText(L["Race"])
    ui.close = NS.MakeCloseButton(f, function() Act.close() end)
    ui.attach = Style.ControlButton(f, "move", "A", L["Attach to or detach from the DPS HUD"], function() Act.attach() end)
    ui.lock = Style.ControlButton(f, "unlock", "U", L["Lock or unlock the Race window"], function() Act.lock() end)
    ui.settings = Style.ControlButton(f, "settings", "S", L["Race mode settings"], function() Act.settings() end)
    ui.controls = Style.NewStrip()
    for _, b in ipairs({ ui.attach, ui.lock, ui.settings }) do Style.AddToStrip(ui.controls, b) end
    local drag = CreateFrame("Frame", nil, f)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() if canDrag() then f:StartMoving() end end)
    drag:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if not attached() then savePosition() end
    end)
    ui.drag = drag
    Style.Header(f, { title = f.title, align = "LEFT", drag = drag,
        right = { ui.close, ui.attach, ui.lock, ui.settings }, n = 4 })
end

local function buildFooter(f)
    local line = f:CreateTexture(nil, "ARTWORK")
    ui.footLine = line
    line:SetHeight(1)
    NS.Skin.Divider(line)
    line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, FOOTER_H)
    line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, FOOTER_H)
    ui.footLeft = NS.Style.Text(f, NS.Style.FONT.CAPTION)
    ui.footLeft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 5)
    ui.footRight = NS.Style.Text(f, NS.Style.FONT.CAPTION, nil, "RIGHT")
    ui.footRight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 5)
end

local onHide, render, resized, trackSize

local function canResize() return not locked end

local function ensureWindow()
    if ui then return ui end
    local f = CreateFrame("Frame", RW.FRAME_NAME, UIParent, "BackdropTemplate")
    ui = { frame = f, body = {} }
    f:Hide()
    f:SetFrameStrata(NS.Constants.LAYERS.STRATA.HUD)
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    buildHeader(f)
    buildFooter(f)
    ui.content = CreateFrame("Frame", nil, f)
    NS.ApplySkin(f)
    f:SetScript("OnHide", function() onHide() end)
    -- Escape closes it with the standard close stack (standalone-windows).
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, RW.FRAME_NAME) end
    -- The grip (modules/Sizing.lua): while it is held each size change lays the body out at the
    -- dragged size; the release stores it (resized). A size change the grip did not start is this
    -- window's own SetSize, already laid out, so `redraw` has nothing to do.
    NS.Sizing.MakeResizable(f, {
        minWidth = RW.WIDTH, minHeight = RW.Height(),
        canResize = function() return canResize() end,
        size = function(w, h) trackSize(w, h) end, layout = function() render() end, redraw = function() end,
        done = function(w, h) resized(w, h) end,
    })
    debug("race window built")
    return ui
end

local function contentTop() return setting("hud.window.titleBar") ~= false and HEADER_H + 10 or PAD end
local function contentBottom() return setting("hud.window.footer") ~= false and FOOTER_H + 8 or PAD end

-- The window's configured look, once per Appearance stamp: the title bar, the footer, the content's
-- insets, the background, border, strata and opacity (the DPS HUD's `hud.window.*`).
local function applyWindow()
    local A = NS.HudAppearance
    if ui.stamp == A.stamp then return end
    ui.stamp = A.stamp
    local f = ui.frame
    local bar, foot = A.On("hud.window.titleBar"), A.On("hud.window.footer")
    for _, part in ipairs({ ui.close, ui.attach, ui.lock, ui.settings, ui.drag, NS.Style.Band(f) }) do
        if part then part:SetShown(bar) end
    end
    f.title:SetShown(bar and A.On("hud.window.title"))
    for _, part in ipairs({ ui.footLine, ui.footLeft, ui.footRight }) do part:SetShown(foot) end
    ui.content:ClearAllPoints()
    ui.content:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -contentTop())
    ui.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, contentBottom())
    A.ApplyWindow(f)
end

-- The lock's and the attach control's icons, each set only when it changes.
local function applyControls()
    local Style = NS.Style
    local lockKey = locked and "lock" or "unlock"
    if ui.lockIcon ~= lockKey then
        ui.lockIcon = lockKey
        Style.SetControlIcon(ui.lock, lockKey, locked and "L" or "U")
    end
    local attachKey = attached() and "move" or ATTACH_ICON[side()]
    if ui.attachIcon ~= attachKey then
        ui.attachIcon = attachKey
        Style.SetControlIcon(ui.attach, attachKey, "A")
    end
end

--- The window's least height: the chrome and the content every body fits in.
--- @return number
function RW.Height()
    return contentTop() + contentBottom() + NS.RaceWindowStates.CONTENT_H
end

--- The height the window has now: matched to the DPS HUD's (attached LEFT or RIGHT,
--- `raceWindow.matchHud` on), else the grip's while it is held, else `raceWindow.height`; never less
--- than its least (RW.Height).
--- @return number
function RW.WindowHeight()
    local own = RW.Height()
    if matched() then
        local h = NS.Hud.Height and Secrets.PlainNumber(NS.Hud.Height())
        return h and math.max(own, h) or own
    end
    local h = sizing() and ui.dragH or tonumber(setting("raceWindow.height"))
    return clamp(h or own, own, math.max(own, RW.MAX_HEIGHT))
end

--- The width the window has now: the grip's while it is held, else `raceWindow.width`, in range.
--- @return number
function RW.Width()
    local w = sizing() and ui.dragW or tonumber(setting("raceWindow.width"))
    return clamp(w or RW.WIDTH, RW.WIDTH, RW.MAX_WIDTH)
end

-- Every size change: the size, in range, that a drag lays out from (plain numbers only). Matched,
-- the height is the HUD's and the grip's bounds hold it.
function trackSize(w, h)
    w, h = Secrets.PlainNumber(w), Secrets.PlainNumber(h)
    if w then ui.dragW = clamp(w, RW.WIDTH, RW.MAX_WIDTH) end
    if h then ui.dragH = clamp(h, RW.Height(), math.max(RW.Height(), RW.MAX_HEIGHT)) end
end

-- The grip shown while it may size the window (unlocked), and its bounds: matched to the HUD's
-- height, the width alone; else both, from the least size.
local function applyGrip()
    local f = ui.frame
    if f.resizeGrip then f.resizeGrip:SetShown(canResize()) end
    if type(f.SetResizeBounds) ~= "function" then return end
    local own = RW.Height()
    if matched() then
        local h = RW.WindowHeight()
        f:SetResizeBounds(RW.WIDTH, h, RW.MAX_WIDTH, h)
    else
        f:SetResizeBounds(RW.WIDTH, own, RW.MAX_WIDTH, math.max(own, RW.MAX_HEIGHT))
    end
end

-- ── the view ────────────────────────────────────────────────────────────────────────────────────

local function inCombat()
    if sampled() then return src().InCombat() end
    return UnitAffectingCombat("player") and true or false
end

--- The length an arm takes now: the idle body's pick, else the length the next race arms at.
local function currentLength()
    return pick.length or src().DefaultLength()
end

-- Why Arm would refuse right now, for the idle body: what Race.Arm checks of the world.
local function armBlocker()
    if inCombat() then return "in_combat" end
    if NS.Fight.State() ~= NS.Fight.STATE.IDLE then return "settling" end
    local ok, why = NS.Meter.IsAvailable()
    if not ok then return "meter_unavailable", why end
    return nil
end

local function targetWarning(target)
    if type(target) ~= "table" then return L["No target: target a training dummy, then arm."] end
    if NS.Dummies.CategoryOf(target.creatureID) then return nil end
    return L["%s is no training dummy: a race armed now is canceled when that pull starts."]:format(target.name or L["Your target"])
end

local function targetNow()
    local snap = NS.Identity.Snapshot()
    return type(snap) == "table" and snap.target or nil
end

-- Top races under Your best (Task W7): the top races on the board Your best is read from, the store's.
local function idleBoard(v)
    local bv = v.best
    if bv.state ~= "best" then return end
    local probe = { who = bv.who, race = { kind = bv.kind, length = bv.length } }
    v.board = NS.RaceWindowBoard.Rows(nil, NS.Bests.Ranked(probe, NS.Recorder.List()))
    v.boardNote = NS.RaceWindowBoard.Note(bv.kind, bv.length)
end

local function idleView(v)
    v.target = targetNow()
    v.length = currentLength()
    v.editing = pick.editing
    v.blocker, v.detail = armBlocker()
    v.warning = targetWarning(v.target)
    v.best = NS.RaceWindowBest.View(v.target, v.length)
    idleBoard(v)
end

local function fightTarget(fight)
    local snap = type(fight) == "table" and fight.snapshot or nil
    return type(snap) == "table" and snap.target or nil
end

local function armedView(v)
    v.length = v.race and v.race.length
    v.target = fightTarget(src().Fight()) or targetNow()
end

-- The race board's best the race is after, read once per race: its fight's character and spec, the
-- dummy's kind, the race length (a sample race's from the sample history).
local function bestFor(race)
    if raceBest.race == race then return raceBest.record end
    local fight = src().Fight()
    local snap = type(fight) == "table" and fight.snapshot or {}
    local target = fightTarget(fight) or {}
    local probe = { who = snap.who, identity = { targetCreatureID = target.creatureID },
                    race = { kind = race.kind, length = race.length } }
    local best = race.sample and NS.ResultsSource.BestFor or NS.Bests.For
    raceBest = { race = race, record = best(probe), who = snap.who }
    return raceBest.record
end

-- Best to beat, Best by now and the Checkpoints (Task W6): the best's card, then its straight line
-- (spec §4.4, the one the DPS HUD paces this race on) at the race clock. Stored numbers and the clock
-- only, so a shared session's race shows them too.
local function runningBest(v, race, elapsed)
    local record = bestFor(race)
    v.bestView = { state = record and "best" or "empty", record = record, who = raceBest.who,
                   kind = race.kind, length = race.length }
    local line = NS.HudBest.RaceCurve(record)
    if not line then return nil end
    v.byNow = NS.RaceWindowBoard.ByNow(line, elapsed)
    v.checkpoints = NS.RaceWindowBoard.Checkpoints(line, elapsed)
    return line
end

-- The best's line for a player-only reading: its player share, when the record stored the player's
-- own damage apart from the pet's; nil when it did not (a share made up from the merged total would
-- pace the player's alone against the pet's damage too, so the bars keep the best's merged figure).
local function playerLine(line)
    local record = raceBest.record
    local d = type(record) == "table" and record.damage or nil
    if not (line and type(d) == "table" and type(d.player) == "number") then return nil end
    return line
end

-- The player's damage beside the best's: the DPS HUD's last read of the race's fight (opaque), and
-- per checkpoint the reading of the beat the clock passed it. `has` and `taken` are plain flags; the
-- readings are never looked at. A checkpoint already behind the clock when this race is first drawn
-- (a resumed race) keeps a dash: its moment went by unseen. THE PET (owner, 2026-11-13): where the
-- pet has a live source of its own (the HUD's read carries one, Retail's pet classes), the reading is
-- the player's alone, so the pace bars take the best's player-only figure (`paceRef`, plain: the
-- line's playerAt, as the DPS HUD's HudBest.PaceAt does with playerOnly); a checkpoint keeps the
-- flag of the read it took. No player-only figure on the best's record: no `paceRef`.
-- The HUD's last read of the race's fight: its player total (opaque), and two plain flags.
local function lastRead()
    local Hud = NS.Hud
    if not (Hud and Hud.LiveDamage) then return nil, false, false end
    local total, has, petOwn = Hud.LiveDamage(src().Fight())
    return total, has == true, petOwn == true
end

-- Checkpoint `i` as the clock passes it: the reading of this beat kept, or a dash for a moment that
-- went by unseen.
local function take(i, total, has, petOwn)
    held.taken[i], held.has[i] = true, has and held.seen
    if has and held.seen then held.value[i], held.pet[i] = total, petOwn end
end

local function runningYou(v, race, line, elapsed)
    if held.race ~= race then held = { race = race, taken = {}, has = {}, value = {}, pet = {}, seen = false } end
    local total, has, petOwn = lastRead()
    v.you, v.hasYou = total, has
    local split = playerLine(line)
    v.paceRef = (split and petOwn) and split:playerAt(elapsed or 0) or nil
    for i, cp in ipairs(v.checkpoints or {}) do
        if cp.passed and not held.taken[i] and (has or not held.seen) then take(i, total, has, petOwn) end
        cp.you, cp.hasYou = held.value[i], held.has[i] == true
        cp.paceRef = (split and held.pet[i]) and split:playerAt(cp.t) or nil
    end
    held.seen = true
end

local function runningView(v)
    local R, race = src(), v.race
    local elapsed, left = R.Elapsed(), R.TimeLeft()
    if elapsed and race.length then elapsed, left = NS.Format.RaceClock(elapsed, race.length) end
    v.elapsed, v.timeLeft, v.length = elapsed, left, race.length
    v.clockMode = setting("race.clock")
    local line = runningBest(v, race, elapsed or 0)
    runningYou(v, race, line, elapsed)
    v.chips = NS.RaceWindowStates.RunningChips(race)
end

-- Seconds since the race's last damage update, or since the buzzer when none came.
local function quietFor()
    local R = src()
    local elapsed, last = R.Elapsed(), R.LastDamage()
    if not elapsed then return 0 end
    if type(last) ~= "number" then return R.SinceBuzzer() or 0 end
    return elapsed - last
end

-- The race the waiting phase was reached for: once there it stays (the owner, 2026-11-13: a DoT
-- still ticking after the buzzer flipped Stop! and waiting, the hint box blinking in and out, at each
-- tick that reset the quiet time).
local heldRace

--- STOPPING is shown in two phases: Stop! while damage may still land, waiting once the tail went
--- quiet (for combat to end, or for the read), or once combat has held past `race.hintDelay` after the
--- buzzer with damage still landing; a race that ended before its buzzer waits for its read. Waiting
--- is never left for Stop! within one race.
local function stopPhase(race, fighting)
    if race ~= nil and race == heldRace then return "waiting" end
    local R = src()
    local since = R.SinceBuzzer()
    local delay = tonumber(setting("race.hintDelay")) or 15
    local waiting = since == nil or quietFor() >= NS.RaceScoring.QUIET_BEFORE_READ
        or (fighting and since >= delay)
    if not waiting then return "stop" end
    heldRace = race
    return "waiting"
end

local function hintFor(v)
    if v.key ~= "waiting" or not v.inCombat then return nil end
    local delay = tonumber(setting("race.hintDelay")) or 15
    if (v.sinceBuzzer or v.sinceEnd or 0) < delay then return nil end
    return NS.RaceWindowStates.HintText()
end

-- The board at the race's end: the buzzer's (the length) or an early end's time. The checkpoint the
-- race clock passes there, the last one at the buzzer, is taken now with the HUD's last read, as each
-- before it was taken on its beat (runningYou).
local function endBoard(v, race)
    local at = src().SinceBuzzer() ~= nil and race.length or race.endedAt
    if type(at) ~= "number" then return end
    if type(race.length) == "number" then at = math.min(at, race.length) end
    runningYou(v, race, runningBest(v, race, at), at)
end

local function stopView(v)
    local R, race = src(), v.race
    v.key = stopPhase(race, v.inCombat)
    local last = R.LastDamage()
    v.tail = (type(last) == "number" and race.length) and math.max(0, last - race.length) or 0
    v.sinceBuzzer = R.SinceBuzzer()
    v.endedEarly = v.sinceBuzzer == nil
    v.endedAt = race.endedAt
    -- An early end has no buzzer: combat back after it (ruling X16) is counted from the race's end.
    local elapsed = R.Elapsed()
    if v.endedEarly and elapsed and type(race.endedAt) == "number" then v.sinceEnd = math.max(0, elapsed - race.endedAt) end
    v.lateCasts = type(race.flags) == "table" and race.flags.lateCasts or nil
    v.grace = race.grace
    v.stopNow = R.StopRequested()
    v.hint = hintFor(v)
    endBoard(v, race)
end

-- Against your best and Top races (Task W7): the best before this race (Bests.Before, the one
-- Bests.Delta is set against) and the board's top races with this one's rank, from the store (the
-- sample history for a sample race). Neither for a lost race, which left no record.
local function resultTables(v, record)
    local race = v.race
    if not record or race.status == "lost" or type(race.score) ~= "number" then return end
    local Board = NS.RaceWindowBoard
    v.prev = v.prev or NS.Bests.Before(record)
    v.compare = v.prev and Board.Compare(record, v.prev) or nil
    v.board = Board.Rows(record, NS.Bests.Ranked(record))
    local who = type(record.who) == "table" and record.who or {}
    v.boardNote = Board.Note(NS.Bests.RaceKind(record) or race.kind, race.length, Secrets.PlainString(who.specName))
end

local function resultView(v)
    local record = src().Result()
    v.record = record
    v.race = record and type(record.race) == "table" and record.race or v.race
    v.dps = record and NS.RaceRecord.Dps(record) or (v.race and v.race.dps)
    if record and v.race.status == "complete" then
        local delta, isNew, prev = NS.Bests.Delta(record)
        v.delta, v.isNew, v.prev = delta, isNew, prev
    end
    v.canShare = record ~= nil and not record.sample and NS.Share ~= nil and type(NS.Share.Prompt) == "function"
    resultTables(v, record)
end

local BODY_OF = { idle = "idle", armed = "armed", running = "running", result = "result" }
local FILL = { idle = idleView, armed = armedView, running = runningView, result = resultView }

local function fill()
    local R = src()
    local state = R.State()
    local v = { state = state, race = R.Current(), inCombat = inCombat(), width = RW.Width() - 2 * PAD }
    if state == S().STOPPING and v.race then
        stopView(v)
        return v
    end
    v.key = v.race and BODY_OF[state] or "idle"
    -- The checkpoint readings live as long as the race does (running, then stopping): let go at its
    -- result, or at idle or armed.
    if v.key ~= "running" then held = {} end
    FILL[v.key](v)
    return v
end

local function showBody(which)
    local body = ui.body[which]
    if not body then
        body = NS.RaceWindowStates.Build(which, ui.content)
        ui.body[which] = body
    end
    if ui.current ~= which then
        local old = ui.current and ui.body[ui.current]
        if old then old.frame:Hide() end
        ui.current = which
    end
    body.frame:Show()
    return body
end

local function footer(v)
    local fight = src().Fight()
    local snap = type(fight) == "table" and fight.snapshot or nil
    local who = type(snap) == "table" and snap.who or (not racing() and NS.Identity.Who()) or ui.who or {}
    ui.who = who
    local parts = {}
    for _, s in ipairs({ Secrets.PlainString(who.specName), Secrets.PlainString(who.name) }) do
        if s then parts[#parts + 1] = s end
    end
    ui.footLeft:SetText(table.concat(parts, " \194\183 "))
    ui.footRight:SetText(v.state == S().STOPPING and L["Result pending"] or "")
end

function render()
    applyWindow()
    applyControls()
    local w, h = RW.Width(), RW.WindowHeight()
    local v = fill()
    -- The content's size the body lays out against (the window less its chrome, Task W4).
    v.height = h - contentTop() - contentBottom()
    local body = showBody(v.key)
    body.width = v.width
    body:Update(v)
    -- The grip owns the size while it is held.
    if not sizing() then ui.frame:SetSize(w, h) end
    applyGrip()
    footer(v)
    view = v
    return v
end

-- The grip's release (or a hide while it was held): the width stored, and the height unless it is
-- the HUD's; a detached window keeps its top left where the drag left it; then the redraw.
function resized(w, h)
    w = Secrets.PlainNumber(w) or ui.dragW
    h = Secrets.PlainNumber(h) or ui.dragH
    ui.dragW, ui.dragH = nil, nil
    if not attached() then keepWhereItStands() end
    if w then NS.SetByPath("raceWindow.width", clamp(math.floor(w + 0.5), RW.WIDTH, RW.MAX_WIDTH)) end
    if h and not matched() then
        NS.SetByPath("raceWindow.height", clamp(math.floor(h + 0.5), 0, RW.MAX_HEIGHT))
    end
    if RW.IsShown() then RW.Refresh() end
end

-- ── what runs while shown ───────────────────────────────────────────────────────────────────────

-- The race beat (RACE_CLOCK, modules/RaceClock.lua): the race clock and the stop figures, while racing.
local function onBeat()
    if isDown() or not windowShown() or not racing() then return end
    local t0 = Perf.on and debugprofilestop()
    render()
    if t0 then Perf.Note("raceWindow", debugprofilestop() - t0) end
end

local IDLE_EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                      "PLAYER_SPECIALIZATION_CHANGED" }

local function onEvent()
    if isDown() or not windowShown() then return end
    local t0 = Perf.on and debugprofilestop()
    render()
    if t0 then Perf.Note("raceWindow", debugprofilestop() - t0) end
end

-- The idle and armed bodies' events, registered only while shown there.
local function syncEvents()
    local want = windowShown() and not racing() and not isDown()
    if want == listening then return end
    listening = want
    if not events then events = LibStub("AceEvent-3.0"):Embed({}) end
    if not want then return events:UnregisterAllEvents() end
    for _, event in ipairs(IDLE_EVENTS) do NS.SafeRegisterEvent(events, event, onEvent, NS.rejectedEvents) end
end

-- The sim window (`/ct sim`'s step panel, modules/Sim.lua) docks beside this window while it is up
-- and beside the DPS HUD otherwise, so each show and hide of the frame docks a shown one again.
-- modules/Sim.lua loads after this file, so it is reached at call time.
local function redockSim()
    local Sim = NS.Sim
    if Sim and Sim.Redock then Sim.Redock() end
end

local function hideWindow()
    if windowShown() then
        hiding = true
        ui.frame:Hide()
        hiding = false
    end
end

-- The frame went away by Escape or the close control: the player closed it. A result card closed is
-- a result dismissed (the race stays in the history). A frame still shown in its own right was hidden
-- with its parent, which is not the player closing it.
function onHide()
    if hiding or (ui and ui.frame:IsShown()) then return end
    wanted, autoShown, dummyShown = false, false, false
    closes = closes + 1
    syncEvents()
    redockSim()
    if src().State() == S().RESULT and not isDown() then src().Cancel() end
end

-- ── the public surface ──────────────────────────────────────────────────────────────────────────

--- Whether the window decides to be up: wanted, Race mode on, the addon standing and the DPS HUD up
--- (W29 decision D1: never without the HUD).
function RW.IsShown()
    return wanted and not isDown() and NS.RaceMode.On() and hudShown()
end

--- Whether the frame is on screen now (the HUD's Escape reads it).
function RW.Visible() return windowShown() end

--- The window's frame, or nil before its first show builds it (the sim window docks beside it).
function RW.Frame() return ui and ui.frame or nil end

--- The side of the DPS HUD this window is attached on (RIGHT, LEFT, TOP or BOTTOM), or nil while it
--- stands on its own (the sim window picks which of the two to dock beside from it).
function RW.DockSide() return attached() and side() or nil end

--- The DPS HUD's Refresh tells this window it may have hidden or come back (modules/Hud.lua): the
--- frame re-decides only when it disagrees with the decision, so the HUD's frequent refreshes cost a
--- comparison. Never calls back into the HUD's Refresh.
function RW.FollowHud()
    if RW.IsShown() ~= windowShown() then RW.Refresh() end
end

-- An open of this window while the DPS HUD is closed opens the HUD first (W29 decision D3), by the
-- path that can close it later: "player" (Hud.Show, the player's, never fading), "auto" (Hud.ShowForRace,
-- let go at the race's idle edge or faded) or "dummy" (Hud.ShowNearDummy, closed at the session's end).
-- Nothing while the window is not wanted, Race mode is off or the addon is stood down.
local function openHud(how)
    local H = NS.Hud
    if not wanted or isDown() or not NS.RaceMode.On() or not H or hudShown() then return end
    if how == "dummy" then H.ShowNearDummy() elseif how == "auto" then H.ShowForRace() else H.Show() end
end

--- Re-decide and redraw. The one place the frame follows the decision.
function RW.Refresh()
    locked = setting("general.locked") == true
    local was = windowShown()
    if not RW.IsShown() then
        hideWindow()
    else
        ensureWindow()
        applyPlacement()
        render()
        if not windowShown() then ui.frame:Show() end
    end
    syncEvents()
    if windowShown() ~= was then redockSim() end
end

--- Draw again now (the body on screen, with the window's place and look).
RW.Render = RW.Refresh

-- Whether auto-show's dummy session is live now (modules/AutoArm.lua, reached at call time).
local function inSession()
    local A = NS.AutoArm
    return A ~= nil and A.InSession ~= nil and A.InSession() == true
end

--- Open the window as the player's. Opened while a dummy session is live, it is tied to that session
--- (walking away closes it); a window already up keeps what it was tied to.
function RW.Show()
    if not wanted then dummyShown = inSession() end
    wanted, autoShown = true, false
    openHud("player")
    RW.Refresh()
end

--- Close the window. `own` true is the addon's own close, which does not count as the player's.
--- @param own boolean|nil
function RW.Hide(own)
    if wanted and own ~= true then closes = closes + 1 end
    wanted, autoShown, dummyShown = false, false, false
    RW.Refresh()
end

function RW.Toggle()
    if RW.IsShown() then RW.Hide() else RW.Show() end
end

-- The race's open (an arm, a resume, a result): the window the addon's unless the player's already
-- wants it, and the HUD opened for it when it is closed (W29 decision D3), even under a window that
-- was wanted already but hid with the HUD.
local function autoShow()
    if not wanted then wanted, autoShown = true, true end
    openHud("auto")
end

local sampleOpened = false      -- the sample race opened the window (let go at its end)
local backToIdle                 -- the result card's New Race (below)

--- A sample race stands in now (modules/RaceSample.lua: test mode, the sim): the window shows it,
--- opened for it when it was not up.
function RW.ShowSample()
    if not wanted then sampleOpened, wanted = true, true end
    raceBest = {}
    openHud("auto")
    RW.Refresh()
end

--- The sample race went (test mode or the sim ended): the window reads the real race again, and one the
--- sample opened is let go, unless a real race now holds it (its arm ended the preview): then it is
--- that race's, and closes with it.
function RW.EndSample()
    raceBest = {}
    if sampleOpened and not autoShown then
        if NS.Race.State() == S().IDLE then wanted = false else autoShown = true end
    end
    sampleOpened = false
    RW.Refresh()
end

--- The sample history changed (modules/Results_Source.lua): a sample result card whose race left it
--- goes, as a deleted race's card goes back to the Arm Race screen.
function RW.SampleChanged()
    local RS = NS.RaceSample
    if isDown() or not (RS and RS.On()) or RS.State() ~= S().RESULT then return end
    local record = RS.Result()
    if record and NS.ResultsSource.Get(record.id) == nil then
        debug("the sample result card's race %s was deleted", tostring(record.id))
        backToIdle()
    end
end

--- Auto-show's opening (modules/AutoArm.lua): a training dummy is near. A window already wanted is
--- left as it is (an addon-opened one is taken over by the dummy), but one that hid with the DPS HUD
--- comes back with it: the HUD is opened as the session's (W29 decisions D3 and D4, and the re-ask
--- after a fade). True when the window came up.
--- @return boolean opened
function RW.ShowNearDummy()
    local was = RW.IsShown()
    if not wanted then
        wanted, autoShown, dummyShown = true, true, true
    elseif autoShown then
        dummyShown = true
    end
    if was then return false end
    openHud("dummy")
    RW.Refresh()
    return RW.IsShown()
end

--- Auto-show's closing: no dummy near. Only a window tied to the session closes: one ShowNearDummy
--- opened or took over, or one the player opened in the session (RW.Show).
--- @return boolean closed
function RW.HideAwayFromDummy()
    if not dummyShown then return false end
    wanted, autoShown, dummyShown = false, false, false
    RW.Refresh()
    return true
end

--- Whether the window is open because a training dummy is near.
function RW.ShownNearDummy() return dummyShown end

--- How many times the player has closed the window.
function RW.Closes() return closes end

--- The length an arm takes now (what Arm Race would arm).
function RW.ArmLength() return currentLength() end

--- Attach the window beside the DPS HUD, on `which` side (the stored side when nil).
--- @param which string|nil  "RIGHT" | "LEFT" | "TOP" | "BOTTOM"
function RW.Attach(which)
    if which ~= nil and DOCK[which] then NS.SetByPath("raceWindow.side", which) end
    NS.SetByPath("raceWindow.attached", true)
    RW.Refresh()
end

--- Detach the window: it stays where it stands, now at its own place.
function RW.Detach()
    if attached() and windowShown() then keepWhereItStands() end
    NS.SetByPath("raceWindow.attached", false)
    RW.Refresh()
end

function RW.IsAttached() return attached() end

--- The Lock frame row's reaction: no drag while locked.
function RW.SetLocked(on)
    locked = on == true
    if ui then
        applyControls()
        applyGrip()
    end
end

function RW.IsLocked() return locked end

--- Back to the default detached place (Master controls' Reset position).
function RW.ResetPosition()
    local p, d = position(), shipped("raceWindow.position")
    if p and type(d) == "table" then
        for k in pairs(p) do p[k] = nil end
        for k, v in pairs(d) do p[k] = v end
    end
    if ui then applyPlacement() end
end

--- The DPS HUD's height changed (modules/Hud.lua, Task W4): a window matched to it follows.
function RW.OnHudResized()
    if isDown() or not windowShown() or not matched() then return end
    render()
end

--- The place applied last: { point, relativeTo, relPoint, x, y } (the suites read it), or nil.
function RW.Anchor() return anchor end

--- The view the body on screen drew last.
function RW.View() return view end

--- The lifecycle's stand-down: the window hides, its events go; one the addon opened is let go, one
--- the player opened comes back at the stand-up.
function RW.Suspend()
    if autoShown then wanted, autoShown, dummyShown = false, false, false end
    raceBest = {}
    hideWindow()
    if events then events:UnregisterAllEvents() end
    listening = false
end

--- The stand-up: re-decide from the current state. A window still wanted (the player's: the
--- stand-down let the addon's go) opens the HUD first when the HUD did not come back by its own rules
--- (W29 decision D3).
function RW.Resume()
    openHud(autoShown and "auto" or "player")
    RW.Refresh()
end

--- What the window is doing, for the diagnostics report.
function RW.Diagnose()
    return { shown = RW.IsShown(), body = ui and ui.current or "none", attached = attached(), side = side(),
             matched = matched(), events = listening, locked = locked, width = RW.Width(), height = RW.WindowHeight() }
end

--- The built window and its bodies, for the suites (nil until first shown).
function RW.__ui() return ui end

-- ── the race, heard on the bus ──────────────────────────────────────────────────────────────────

local function onState(_, from, to)
    local St = S()
    if to == St.ARMED then
        pick.editing, raceBest = false, {}
        autoShow()
    end
    -- Straight from idle into a live race is a resume: its window comes back as the arm's did.
    if from == St.IDLE and (to == St.RUNNING or to == St.STOPPING) then autoShow() end
    if to == St.IDLE and autoShown and not dummyShown then wanted, autoShown = false, false end
    debug("race window: %s -> %s", tostring(from), tostring(to))
    RW.Refresh()
end

local function onFightEnded()
    if isDown() or not windowShown() or racing() then return end
    RW.Refresh()
end

-- The store changed: the idle body's best may have moved; a result card whose race left the store
-- goes back to the Arm Race screen.
local function onFightsChanged()
    if isDown() then return end
    local R = src()
    if R.State() == S().RESULT and not sampled() then
        local record = R.Result()
        if record and NS.Recorder.Get(record.id) == nil then
            debug("the result card's race %s was deleted", tostring(record.id))
            return backToIdle()
        end
    end
    if windowShown() then
        NS.Bests.Invalidate()
        RW.Refresh()
    end
end

-- Attach unticked on the Race mode page (or the CLI): it stays where it stands, as the title bar's
-- Detach does; the frame is still beside the HUD until the settings' Refresh.
local function detachedBySetting(path)
    if path ~= "raceWindow.attached" or attached() or not windowShown() then return end
    if anchor and anchor[2] ~= UIParent then keepWhereItStands() end
end

local function onSettings(path)
    if type(path) ~= "string" or isDown() then return end
    detachedBySetting(path)
    -- A new Default race length takes effect over the pick (DPS Race's ForgetLength): the idle body
    -- and auto-arm's ArmLength offer it.
    if path == "race.defaultLength" or path == "profile" then pick.length = nil end
    -- Race mode back on with the window still wanted: the HUD opens first (W29 decision D3).
    if path == "race.enabled" then openHud(autoShown and "auto" or "player") end
    local LI, Dummies = NS.LateIgnore, NS.Dummies
    local mine = path == "profile" or path:find("^raceWindow%.") or path:find("^race%.") or path == "general.locked"
        or (LI and path == LI.PATH) or (Dummies and path == Dummies.PATH)
    if mine and (windowShown() or wanted) then RW.Refresh() end
end

do
    local bus = NS.NewBusTarget()
    if bus then
        bus:RegisterMessage(NS.MSG.RACE_STATE_CHANGED, function(_, race, from, to) onState(race, from, to) end)
        bus:RegisterMessage(NS.MSG.RACE_RESULT, function()
            if isDown() then return end
            autoShow()
            RW.Refresh()
        end)
        bus:RegisterMessage(NS.MSG.RACE_CLOCK, function() onBeat() end)
        -- A fight read (Fight idle again): the idle body's "still being read" refusal is lifted.
        bus:RegisterMessage(NS.MSG.FIGHT_ENDED, function() onFightEnded() end)
        bus:RegisterMessage(NS.MSG.FIGHTS_CHANGED, function() onFightsChanged() end)
        bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path) onSettings(path) end)
    end
end

-- ── the acts the buttons run ────────────────────────────────────────────────────────────────────

function Act.arm()
    local ok, reason, detail = NS.Race.Arm(currentLength())
    if not ok then NS.Print(NS.RaceVerb.ArmRefusal(reason, detail)) end
    RW.Refresh()
    return ok, reason
end

function Act.pickLength(n)
    pick.length, pick.editing = n, false
    RW.Refresh()
end

function Act.openCustom()
    pick.editing = true
    RW.Refresh()
end

function Act.closeCustom()
    pick.editing = false
    RW.Refresh()
end

--- A typed race length ("90", "1:30", "3m"); refused with the length line when out of range.
function Act.customLength(text)
    local n = NS.RaceVerb.ParseLength(text)
    if not n or n < NS.Race.MIN_LENGTH or n > NS.Race.MAX_LENGTH then
        NS.Print(NS.RaceVerb.ArmRefusal("bad_length"))
        return false
    end
    Act.pickLength(n)
    return true
end

function Act.cancel() return src().Cancel() end

function Act.stopNow()
    local acted = src().StopNow()
    RW.Refresh()
    return acted
end

function Act.close()
    if windowShown() then ui.frame:Hide() end
    if wanted then
        if ui then onHide() else wanted = false end
    end
end

function Act.lock() return NS.ToggleLock() end

function Act.settings()
    local H = NS.Helpers
    if H and type(H.OpenOptionsPanel) == "function" then return H.OpenOptionsPanel("race") end
    return NS.OpenSettings()
end

function Act.attach()
    if attached() then return RW.Detach() end
    return RW.Attach()
end

local function openRecord(record)
    local R = NS.Results
    if not (record and R and type(R.ShowFight) == "function") then return false end
    return R.ShowFight(record.id)
end

--- The idle body's Your best card: its race in the Results window.
function Act.openBest(record) return openRecord(record) end

--- Open: the race's fight detail in the Results window (its chart and its spells, spec §4.2).
function Act.open() return openRecord(src().Result()) end

--- New Race: back to the Arm Race screen at the same length, the window the player's; the result card
--- is dismissed and the race stays saved.
function backToIdle()
    -- A sample's card goes, and the window reads the real race again; the player's length is left alone.
    if sampled() then
        NS.RaceSample.Clear()
        RW.Refresh()
        return true
    end
    local race = NS.Race.Current()
    local length = race and race.length
    autoShown, dummyShown = false, false
    if NS.Race.State() == S().RESULT then NS.Race.Cancel() end
    if type(length) == "number" then pick.length = length end
    pick.editing = false
    RW.Refresh()
    return true
end

function Act.newRace() return backToIdle() end

--- Delete: the Results window's own confirmation; the store's FIGHTS_CHANGED then takes the card back
--- to the Arm Race screen.
function Act.delete()
    local record, R = src().Result(), NS.Results
    if not (record and R and type(R.ConfirmDelete) == "function") then return false end
    R.ConfirmDelete(record.id)
    return true
end

function Act.share()
    local record = src().Result()
    if record and not record.sample and NS.Share and type(NS.Share.Prompt) == "function" then NS.Share.Prompt(record) end
end
