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
-- frame on `raceWindow.side` (RIGHT by default; LEFT, TOP, BOTTOM), DOCK_GAP apart, its top or left
-- edge level with the HUD's, so it moves with the HUD; it is never the HUD's child, so each window
-- shows and fades on its own rules. A HUD that is hidden, or was never shown, is still built and
-- placed where it would stand (Hud.Dock), so the window never falls to 0,0 (Review focus 4). Detached,
-- it stands at `raceWindow.position`, written by its title bar's drag; Detach keeps it where it stood.
-- The lock is Master controls' Lock frame (`general.locked`): no drag while locked, and none while
-- attached (it follows the HUD). Master controls' Reset position puts the detached place back.
--
-- WHEN IT SHOWS (DPS Race's rules, spec §4.1). Never with Race mode off (NS.RaceMode.On()), stood down
-- or on WoW Forever, where nothing here loads. Opened by the player (`/ct race show|toggle`, through
-- NS.SetRaceWindowShown), by auto-show near a training dummy (modules/AutoArm.lua's five hooks:
-- ShowNearDummy, HideAwayFromDummy, ShownNearDummy, Closes, ArmLength), by an arm, by a resumed race
-- and by a result. A window the addon opened for a race closes when that race goes back to idle,
-- unless a dummy is near; one the player opened stays. The player's close counts (Closes), so
-- auto-show leaves the window shut for the rest of that dummy session; closing a result card
-- dismisses it (Race.Cancel), the saved race staying in the history.
--
-- WHAT RUNS. Bus receivers (RACE_STATE_CHANGED, RACE_RESULT, FIGHT_TICK, FIGHTS_CHANGED,
-- SETTINGS_CHANGED) on its own target; while shown and the race idle or armed, the target, the regen
-- edges and the spec change on its own AceEvent target (the target card, Arm's refusal, the best's
-- board); while shown and the race running or stopping, one repeating AceTimer at TICK (10 Hz) for the
-- race clock and the stop figures, timed into the perf harness's `raceWindow` bucket, and each
-- FIGHT_TICK of the race's fight (4 Hz, combat only) reads NS.Meter.ReadLive once for the pace bar.
-- Nothing else polls and no OnUpdate is set. The stand-down drops every registration and the timer.
--
-- NO DECISION FROM A METER VALUE. The pace bar's total is the only live value, handed opaque to the
-- bar; the clocks are Race's GetTime() figures, the result card's the stored record's.
--
-- A RESULT CARD WHOSE RACE IS DELETED (its Delete, or a delete in the Results window): the window goes
-- back to the Arm Race screen at that race's length, as New Race does. One behavior for both, since the
-- Results window's confirmation takes no callback (R:hud#10).
--
-- RETAIL ONLY (clients-§4): nothing here loads on WoW Forever, so NS.RaceWindow is absent there.

if not NS.Compat.ForClient({ "retail" }) then return end

local RW = {}
NS.RaceWindow = RW

local L = NS.L
local Perf = NS.Perf
local Secrets = NS.Secrets

RW.FRAME_NAME = "CombatTrailRaceWindow"
RW.WIDTH = 260        -- DPS Race's window width, the bodies' layout constants are tuned to it
RW.TICK = 0.1         -- the race clock's redraw while racing (s)
RW.DOCK_GAP = 4       -- the gap to the DPS HUD while attached
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
local live                      -- the race's fight's last NS.Meter.ReadLive (opaque)
local paceBest = {}             -- { race, record } : the race board's best the running race paces on
local ticker                    -- the race clock's repeating AceTimer
local events                    -- this module's AceEvent target
local listening = false         -- the idle events are registered
local anchor                    -- the last place applied: { point, relativeTo, relPoint, x, y }
local view = {}                 -- the view the body on screen drew

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Race", fmt, ...) end
end

local function isDown() return NS.IsStoodDown ~= nil and NS.IsStoodDown() end
local function setting(path) return NS.Hud.Setting(path) end
local function S() return NS.Race.STATE end

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

local onHide

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

--- The window's height: the chrome and the content every body fits in.
--- @return number
function RW.Height()
    return contentTop() + contentBottom() + NS.RaceWindowStates.CONTENT_H
end

-- ── the view ────────────────────────────────────────────────────────────────────────────────────

local function inCombat() return UnitAffectingCombat("player") and true or false end

--- The length an arm takes now: the idle body's pick, else the length the next race arms at.
local function currentLength()
    return pick.length or NS.Race.DefaultLength()
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

local function idleView(v)
    v.target = targetNow()
    v.length = currentLength()
    v.editing = pick.editing
    v.blocker, v.detail = armBlocker()
    v.warning = targetWarning(v.target)
    v.best = NS.RaceWindowBest.View(v.target, v.length)
end

local function fightTarget(fight)
    local snap = type(fight) == "table" and fight.snapshot or nil
    return type(snap) == "table" and snap.target or nil
end

local function armedView(v)
    v.length = v.race and v.race.length
    v.target = fightTarget(NS.Race.Fight()) or targetNow()
end

-- The race board's best the race paces on, read once per race: its fight's character and spec, the
-- dummy's kind, the race length.
local function bestFor(race)
    if paceBest.race == race then return paceBest.record end
    local fight = NS.Race.Fight()
    local snap = type(fight) == "table" and fight.snapshot or {}
    local target = fightTarget(fight) or {}
    local probe = { who = snap.who, identity = { targetCreatureID = target.creatureID },
                    race = { kind = race.kind, length = race.length } }
    paceBest = { race = race, record = NS.Bests.For(probe) }
    return paceBest.record
end

-- The best's straight-line pace (spec §4.4): its score over its length, times t.
local function lineOf(record)
    local score, length = record.race.score, record.race.length
    local rate = (type(score) == "number" and type(length) == "number" and length > 0) and score / length or 0
    local function at(_, t) return rate * math.max(0, math.min(tonumber(t) or 0, length or 0)) end
    return { damageAt = at, playerAt = at }
end

-- The running pace bar: the live total against the race board's best at the race clock. None on a
-- shared session (its live total holds damage from before the arm) or with no best.
local function runningPace(race, elapsed)
    if type(race.flags) == "table" and race.flags.sharedSession then return nil, L["not paced: shared session"] end
    local best = bestFor(race)
    if not best or type(best.race) ~= "table" then return nil, L["no best yet"] end
    return NS.HudBest.LiveView(lineOf(best), elapsed, live), nil
end

local function runningView(v)
    local R, race = NS.Race, v.race
    local elapsed = R.Elapsed()
    if elapsed and race.length then elapsed = math.min(elapsed, race.length) end
    v.elapsed, v.timeLeft = elapsed, R.TimeLeft()
    v.clockMode = setting("race.clock")
    v.pace, v.paceWhy = runningPace(race, elapsed or 0)
    v.chips = NS.RaceWindowStates.RunningChips(race)
end

-- Seconds since the race's last damage update, or since the buzzer when none came.
local function quietFor()
    local R = NS.Race
    local elapsed, last = R.Elapsed(), R.LastDamage()
    if not elapsed then return 0 end
    if type(last) ~= "number" then return R.SinceBuzzer() or 0 end
    return elapsed - last
end

--- STOPPING is shown in two phases: Stop! while damage may still land, waiting once the tail went
--- quiet (for combat to end, or for the read); a race that ended before its buzzer waits for its read.
local function stopPhase()
    if NS.Race.SinceBuzzer() == nil then return "waiting" end
    if quietFor() >= NS.RaceScoring.QUIET_BEFORE_READ then return "waiting" end
    return "stop"
end

local function hintFor(v)
    if v.key ~= "waiting" or not v.inCombat then return nil end
    local delay = tonumber(setting("race.hintDelay")) or 15
    if (v.sinceBuzzer or 0) < delay then return nil end
    return L["Combat is holding. Walk out of range, or use an ability that drops combat (Feign Death, Vanish, Shadowmeld, Invisibility). Your score is safe: it waits for combat to end, however long that takes."]
end

local function stopView(v)
    local R, race = NS.Race, v.race
    v.key = stopPhase()
    local last = R.LastDamage()
    v.tail = (type(last) == "number" and race.length) and math.max(0, last - race.length) or 0
    v.sinceBuzzer = R.SinceBuzzer()
    v.endedEarly = v.sinceBuzzer == nil
    v.endedAt = race.endedAt
    v.lateCasts = type(race.flags) == "table" and race.flags.lateCasts or nil
    v.grace = race.grace
    v.stopNow = R.StopRequested()
    v.hint = hintFor(v)
end

-- The result card's pace bar: the plain score against the race board's best before the race, at the
-- race length. None for an incomplete or lost race, or with no earlier best.
local function resultPace(record, race)
    if not record or race.status ~= "complete" or type(race.score) ~= "number" then return nil end
    local prev = NS.Bests.Before(record)
    local ref = prev and type(prev.race) == "table" and prev.race.score
    if type(ref) ~= "number" then return nil end
    local lo, hi = NS.HudBest.Bounds(ref)
    return { lo = lo, hi = hi, total = race.score }
end

local function resultView(v)
    local record = NS.Race.Result()
    v.record = record
    v.race = record and type(record.race) == "table" and record.race or v.race
    v.dps = record and NS.RaceRecord.Dps(record) or (v.race and v.race.dps)
    if record and v.race.status == "complete" then
        local delta, isNew = NS.Bests.Delta(record)
        v.delta, v.isNew = delta, isNew
    end
    v.canShare = record ~= nil and not record.sample and NS.Share ~= nil and type(NS.Share.Prompt) == "function"
    v.pace = resultPace(record, v.race)
end

local BODY_OF = { idle = "idle", armed = "armed", running = "running", result = "result" }
local FILL = { idle = idleView, armed = armedView, running = runningView, result = resultView }

local function fill()
    local R = NS.Race
    local state = R.State()
    local v = { state = state, race = R.Current(), inCombat = inCombat(), width = RW.WIDTH - 2 * PAD }
    if state == S().STOPPING and v.race then
        stopView(v)
        return v
    end
    v.key = v.race and BODY_OF[state] or "idle"
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
    local fight = NS.Race.Fight()
    local snap = type(fight) == "table" and fight.snapshot or nil
    local who = type(snap) == "table" and snap.who or (not ticker and NS.Identity.Who()) or ui.who or {}
    ui.who = who
    local parts = {}
    for _, s in ipairs({ Secrets.PlainString(who.specName), Secrets.PlainString(who.name) }) do
        if s then parts[#parts + 1] = s end
    end
    ui.footLeft:SetText(table.concat(parts, " \194\183 "))
    ui.footRight:SetText(v.state == S().STOPPING and L["Result pending"] or "")
end

local function render()
    applyWindow()
    applyControls()
    local v = fill()
    local body = showBody(v.key)
    body.width = v.width
    body:Update(v)
    ui.frame:SetSize(RW.WIDTH, RW.Height())
    footer(v)
    view = v
    return v
end

-- ── what runs while shown ───────────────────────────────────────────────────────────────────────

local function racing()
    local st = NS.Race.State()
    return st == S().RUNNING or st == S().STOPPING
end

local function tick()
    if isDown() or not windowShown() then return end
    local t0 = Perf.on and debugprofilestop()
    render()
    if t0 then Perf.Note("raceWindow", debugprofilestop() - t0) end
end

local function syncTicker()
    local want = windowShown() and racing() and not isDown()
    local addon = NS.addon
    if want and not ticker and addon and addon.ScheduleRepeatingTimer then
        ticker = addon:ScheduleRepeatingTimer(tick, RW.TICK)
    elseif not want and ticker then
        if addon and addon.CancelTimer then addon:CancelTimer(ticker) end
        ticker = nil
    end
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
    syncTicker()
    syncEvents()
    if NS.Race.State() == S().RESULT and not isDown() then NS.Race.Cancel() end
end

-- ── the public surface ──────────────────────────────────────────────────────────────────────────

--- Whether the window decides to be up: wanted, Race mode on and the addon standing.
function RW.IsShown()
    return wanted and not isDown() and NS.RaceMode.On()
end

--- Re-decide and redraw. The one place the frame follows the decision.
function RW.Refresh()
    locked = setting("general.locked") == true
    if not RW.IsShown() then
        hideWindow()
    else
        ensureWindow()
        applyPlacement()
        render()
        if not windowShown() then ui.frame:Show() end
    end
    syncTicker()
    syncEvents()
end

--- Draw again now (the body on screen, with the window's place and look).
RW.Render = RW.Refresh

--- Open the window as the player's.
function RW.Show()
    wanted, autoShown, dummyShown = true, false, false
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

local function autoShow()
    if wanted then return end
    wanted, autoShown = true, true
end

--- Auto-show's opening (modules/AutoArm.lua): a training dummy is near. A window already wanted is
--- left as it is; an addon-opened one is taken over by the dummy.
--- @return boolean opened
function RW.ShowNearDummy()
    if wanted then
        if autoShown then dummyShown = true end
        return false
    end
    wanted, autoShown, dummyShown = true, true, true
    RW.Refresh()
    return true
end

--- Auto-show's closing: no dummy near. Only a window ShowNearDummy opened, still the addon's, closes.
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
    if ui then applyControls() end
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

--- The place applied last: { point, relativeTo, relPoint, x, y } (the suites read it), or nil.
function RW.Anchor() return anchor end

--- The view the body on screen drew last.
function RW.View() return view end

--- The lifecycle's stand-down: the window hides, its timer and events go; one the addon opened is
--- let go, one the player opened comes back at the stand-up.
function RW.Suspend()
    if autoShown then wanted, autoShown, dummyShown = false, false, false end
    live, paceBest = nil, {}
    hideWindow()
    syncTicker()
    if events then events:UnregisterAllEvents() end
    listening = false
end

--- The stand-up: re-decide from the current state.
function RW.Resume() RW.Refresh() end

--- What the window is doing, for the diagnostics report.
function RW.Diagnose()
    return { shown = RW.IsShown(), body = ui and ui.current or "none", attached = attached(), side = side(),
             ticking = ticker ~= nil, events = listening, locked = locked }
end

--- The built window and its bodies, for the suites (nil until first shown).
function RW.__ui() return ui end

-- ── the race, heard on the bus ──────────────────────────────────────────────────────────────────

local function onState(_, from, to)
    local St = S()
    if to == St.ARMED then
        pick.editing, live, paceBest = false, nil, {}
        autoShow()
    end
    -- Straight from idle into a live race is a resume: its window comes back as the arm's did.
    if from == St.IDLE and (to == St.RUNNING or to == St.STOPPING) then autoShow() end
    if to == St.IDLE and autoShown and not dummyShown then wanted, autoShown = false, false end
    debug("race window: %s -> %s", tostring(from), tostring(to))
    RW.Refresh()
end

local function readLive(fight)
    local sessions = fight.sessions
    local id = (type(sessions) == "table" and sessions[#sessions]) or fight.sessionID
    live = NS.Meter.ReadLive(id)
end

local function onFightTick(fight)
    if isDown() or NS.Race.State() ~= S().RUNNING or fight ~= NS.Race.Fight() or not windowShown() then return end
    local t0 = Perf.on and debugprofilestop()
    readLive(fight)
    if t0 then Perf.Note("raceWindow", debugprofilestop() - t0) end
end

local backToIdle

-- The store changed: the idle body's best may have moved; a result card whose race left the store
-- goes back to the Arm Race screen.
local function onFightsChanged()
    if isDown() then return end
    local R = NS.Race
    if R.State() == S().RESULT then
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

local function onSettings(path)
    if type(path) ~= "string" or isDown() then return end
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
        bus:RegisterMessage(NS.MSG.FIGHT_TICK, function(_, fight) onFightTick(fight) end)
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

function Act.cancel() return NS.Race.Cancel() end

function Act.stopNow()
    local acted = NS.Race.StopNow()
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
function Act.open() return openRecord(NS.Race.Result()) end

--- New Race: back to the Arm Race screen at the same length, the window the player's; the result card
--- is dismissed and the race stays saved.
function backToIdle()
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
    local record, R = NS.Race.Result(), NS.Results
    if not (record and R and type(R.ConfirmDelete) == "function") then return false end
    R.ConfirmDelete(record.id)
    return true
end

function Act.share()
    local record = NS.Race.Result()
    if record and not record.sample and NS.Share and type(NS.Share.Prompt) == "function" then NS.Share.Prompt(record) end
end
