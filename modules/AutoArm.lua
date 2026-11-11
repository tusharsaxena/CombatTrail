local _, NS = ...
-- modules/AutoArm.lua — the race near a training dummy (Race mode, plan Task B3; Retail only): Auto-show
-- (`race.autoShow`) asks the Race window to open by itself while a training dummy (NS.Dummies) is the
-- target or has a nameplate up, and Auto-arm (`race.autoArm`) arms a race by itself when the player
-- targets one out of combat. Auto-show is on by default, auto-arm off, and each is independent of the
-- other. Ported from DPS Race @f8078c7 (modules/AutoArm.lua), unchanged in behavior; the window it
-- drives is the Race window (spec §4.1), never the DPS HUD.
--
-- AUTO-SHOW. A DUMMY SESSION runs from the first dummy seen (the target, or a nameplate:
-- NAME_PLATE_UNIT_ADDED) until none has been seen for HIDE_DELAY seconds: the hide is a timer canceled
-- by the next dummy, so nameplates churning at the edge of their range never flicker the window. At
-- its fire the nameplates are scanned again (a plate that came up in combat, its GUID secret, was not
-- counted when it came). The window opens through RaceWindow.ShowNearDummy (only when nothing else
-- wants it) and closes through RaceWindow.HideAwayFromDummy, and only while the race is idle: an armed
-- or running race, or a result card, keeps it; the race's idle edge asks again. THE MANUAL-CLOSE RULE:
-- a close by the player in a session (RaceWindow.Closes() moved since the session began) keeps
-- auto-show from opening the window again until that session ends.
--
-- AUTO-ARM. PLAYER_TARGET_CHANGED to a training dummy, out of combat, the race idle and no test mode or
-- sim on: Race.Arm at RaceWindow.ArmLength() (what Arm Race would arm; the race's own DefaultLength
-- when the window has none), through every refusal Race.Arm has, silently: the Race window's idle body
-- shows why. The way back out: while the race this rule armed is still armed (not started), a target
-- change out of combat to anything that is not a training dummy, or none, cancels it (in combat the
-- pull is under way). A result card is never armed over (Race.Arm wants the race idle), and a race
-- that started is never disarmed.
--
-- THE RACE WINDOW'S SEAM (Task C1). Five hooks on NS.RaceWindow, each reached at CALL time:
-- ShowNearDummy() -> opened, HideAwayFromDummy() -> closed, ShownNearDummy() -> boolean, Closes() ->
-- count, ArmLength() -> seconds|nil. Until the window exists, auto-show has nothing to open and
-- auto-arm arms at the race's default length.
--
-- GATES. Neither rule acts in an instance (GetInstanceInfo's type other than "none"), and nothing is
-- registered while the addon is stood down, with Race mode off (NS.RaceMode.On(), the Race mode page's
-- switch) or on WoW Forever (clients-§4: the bus receivers below register only on Retail). Registered
-- only while a rule is on: the target and PLAYER_ENTERING_WORLD for either, the nameplate events for
-- auto-show, on this module's own AceEvent target through NS.SafeRegisterEvent. A GUID is read only
-- through NS.Identity.UnitCreatureID, which never parses a secret one: a secret GUID is no dummy. The
-- hide is the addon object's AceTimer, so the stand-down's CancelAllTimers takes it; each event is
-- timed into the perf harness's `autoArm` bucket (core/PerfSetup.lua).

local AutoArm = {}
NS.AutoArm = AutoArm

local Secrets = NS.Secrets
local Perf = NS.Perf

--- Seconds with no training dummy seen before the session ends and an auto-shown window closes.
AutoArm.HIDE_DELAY = 3

local RETAIL = { "retail" }
local TARGET_EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD" }
local PLATE_EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }

local events               -- this module's AceEvent target (nil until a rule is first on)
local registered = "none"  -- "none" | "target" | "plates"
local plates = {}          -- nameplate unit token -> true, for each training dummy's plate
local session              -- { closes = RaceWindow.Closes() at its start } while a dummy is near
local hideTimer, hideAt    -- the session's end (the AceTimer and its GetTime()), while no dummy is seen
local armedRace            -- the race part this rule armed, while it is armed and not started

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("AutoArm", fmt, ...) end
end

local function showOn() return NS.GetSetting("race.autoShow") == true end
local function armOn() return NS.GetSetting("race.autoArm") == true end

local function idle() return NS.Race.State() == NS.Race.STATE.IDLE end
local function previewOn() return NS.Preview ~= nil and NS.Preview.IsActive() == true end

-- ── the Race window's hooks (Task C1) ───────────────────────────────────────────────────────────

local function window(hook, ...)
    local W = NS.RaceWindow
    local fn = W and W[hook]
    if type(fn) ~= "function" then return nil end
    return fn(...)
end

local function shownNear() return window("ShownNearDummy") == true end
local function closes() return window("Closes") or 0 end

local function armLength()
    local n = window("ArmLength")
    if type(n) == "number" then return n end
    return NS.Race.DefaultLength()
end

-- ── what is near ────────────────────────────────────────────────────────────────────────────────

-- The open world only: an instance's type is anything but "none" (nil, unread, counts as open).
local function inInstance()
    local ok, _, kind = pcall(GetInstanceInfo)
    kind = ok and Secrets.PlainString(kind) or nil
    return kind ~= nil and kind ~= "none"
end

local function active()
    return not NS.IsStoodDown() and NS.RaceMode.On() and not inInstance()
end

local function isDummy(unit)
    local id = NS.Identity.UnitCreatureID(unit)
    return id ~= nil and NS.Dummies.Lookup(id) ~= nil
end

local function clearPlates()
    for unit in pairs(plates) do plates[unit] = nil end
end

-- Every nameplate up now, read again.
local function rescan()
    clearPlates()
    local api = C_NamePlate
    local ok, list = pcall(api and api.GetNamePlates)
    if not ok or type(list) ~= "table" then return end
    for _, plate in ipairs(list) do
        local unit = type(plate) == "table" and plate.namePlateUnitToken
        if Secrets.IsSafeKey(unit) and isDummy(unit) then plates[unit] = true end
    end
end

local function near()
    return isDummy("target") or next(plates) ~= nil
end

-- ── auto-show ───────────────────────────────────────────────────────────────────────────────────

local function cancelHide()
    local addon = NS.addon
    if hideTimer and addon and addon.CancelTimer then addon:CancelTimer(hideTimer) end
    hideTimer, hideAt = nil, nil
end

-- The session is over: an auto-shown window closes, unless a race holds it (its idle edge asks again).
local function leave()
    cancelHide()
    if session then debug("dummy session ended") end
    session = nil
    if idle() then window("HideAwayFromDummy") end
end

local hideDue   -- the timer callback, below

local function queueHide(delay)
    local addon = NS.addon
    if addon and addon.ScheduleTimer then hideTimer = addon:ScheduleTimer(hideDue, math.max(0, delay)) end
end

-- The timer may be serviced early (a queue that runs every timer at once): it waits out the rest.
function hideDue()
    hideTimer = nil
    local left = (hideAt or 0) - GetTime()
    if left > 0 then return queueHide(left) end
    hideAt = nil
    rescan()
    if active() and showOn() and near() then return end
    leave()
end

local function scheduleHide()
    if hideTimer or not (session or shownNear()) then return end
    hideAt = GetTime() + AutoArm.HIDE_DELAY
    queueHide(AutoArm.HIDE_DELAY)
end

-- Auto-show's decision, after anything that may change it.
local function decideShow()
    if not (active() and showOn()) then
        if session or shownNear() then leave() end
        return
    end
    if not near() then return scheduleHide() end
    cancelHide()
    if not session then
        session = { closes = closes() }
        debug("dummy session began")
    end
    -- The player closed the window in this session: theirs to open again.
    if closes() ~= session.closes then return end
    window("ShowNearDummy")
end

-- ── auto-arm ────────────────────────────────────────────────────────────────────────────────────

local function tryArm()
    if not (armOn() and active()) or previewOn() or not idle() then return end
    if UnitAffectingCombat("player") then return end
    local ok, reason = NS.Race.Arm(armLength())
    if not ok then return debug("auto-arm refused: %s", tostring(reason)) end
    armedRace = NS.Race.Current()
    debug("auto-armed on a training dummy")
end

-- The target moved off the dummies: the race this rule armed goes, if it has not started. Not in
-- combat: the pull is under way.
local function disarm()
    if UnitAffectingCombat("player") then return end
    local race = armedRace
    armedRace = nil
    if race and NS.Race.State() == NS.Race.STATE.ARMED and NS.Race.Current() == race then
        debug("auto-arm canceled: the target is no training dummy")
        NS.Race.Cancel()
    end
end

-- ── events ──────────────────────────────────────────────────────────────────────────────────────

local function onTarget()
    -- Auto-show first, so a window it opens is its own before an arm would claim it.
    decideShow()
    if isDummy("target") then tryArm() else disarm() end
end

local function onPlateAdded(unit)
    if not Secrets.IsSafeKey(unit) or not isDummy(unit) then return end
    plates[unit] = true
    decideShow()
end

local function onPlateRemoved(unit)
    if not Secrets.IsSafeKey(unit) or not plates[unit] then return end
    plates[unit] = nil
    decideShow()
end

local function onEnteringWorld()
    rescan()
    decideShow()
end

local HANDLERS = {
    PLAYER_TARGET_CHANGED   = onTarget,
    PLAYER_ENTERING_WORLD   = onEnteringWorld,
    NAME_PLATE_UNIT_ADDED   = onPlateAdded,
    NAME_PLATE_UNIT_REMOVED = onPlateRemoved,
}

-- An AceEvent function handler: (event, ...).
local function onAceEvent(event, ...)
    if NS.IsStoodDown() then return end
    local t0 = Perf.on and debugprofilestop()
    local handler = HANDLERS[event]
    if handler then handler(...) end
    if t0 then Perf.Note("autoArm", debugprofilestop() - t0) end
end

local function wanted()
    if NS.IsStoodDown() or not NS.RaceMode.On() then return "none" end
    if showOn() then return "plates" end
    if armOn() then return "target" end
    return "none"
end

local function register(set)
    -- Its own AceEvent target (events-frames-taint-§1): no other module's PLAYER_TARGET_CHANGED is clobbered.
    if not events then events = LibStub("AceEvent-3.0"):Embed({}) end
    for _, event in ipairs(TARGET_EVENTS) do NS.SafeRegisterEvent(events, event, onAceEvent, NS.rejectedEvents) end
    if set ~= "plates" then return end
    for _, event in ipairs(PLATE_EVENTS) do NS.SafeRegisterEvent(events, event, onAceEvent, NS.rejectedEvents) end
end

-- The race on the bus: a race leaving ARMED is no longer this rule's to cancel, and an idle race lets an
-- auto-shown window go (or come back) as the dummies say. A profile switch, copy or reset re-reads the
-- rows (their onChange does not run for it), and an edit of the dummy list may make another creature
-- one.
local function onState(race, _, to)
    if type(race) == "table" and race.sample then return end   -- a sample race is no race of this rule's
    local S = NS.Race.STATE
    if to ~= S.ARMED then armedRace = nil end
    if to == S.IDLE then decideShow() end
end

if NS.Compat.ForClient(RETAIL) then
    local bus = NS.NewBusTarget()
    if bus then
        bus:RegisterMessage(NS.MSG.RACE_STATE_CHANGED, function(_, race, from, to) onState(race, from, to) end)
        bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path)
            if path == "profile" or path == NS.Dummies.PATH then AutoArm.Sync() end
        end)
    end
end

-- ── the public surface ──────────────────────────────────────────────────────────────────────────

--- Make the registrations and the window follow the rows (their reaction, a profile change, the dummy
--- list, OnEnable and the stand-up). Turning auto-show off closes a window it opened; turning auto-arm
--- off leaves an armed race armed, as a manual one.
function AutoArm.Sync()
    local want = wanted()
    if want ~= registered then
        if events then events:UnregisterAllEvents() end
        registered = want
        if want ~= "none" then register(want) end
    end
    if not armOn() then armedRace = nil end
    if want == "plates" then rescan() else clearPlates() end
    decideShow()
end

--- The lifecycle's stand-down: every registration, the hide timer and the session go. The Race window
--- drops its own auto-shown state on its own stand-down.
function AutoArm.Suspend()
    if events then events:UnregisterAllEvents() end
    registered = "none"
    cancelHide()
    clearPlates()
    session, armedRace = nil, nil
end

--- The stand-up: rebuilt from the current settings.
function AutoArm.Resume()
    registered = "none"
    AutoArm.Sync()
end

--- What the rules hold now, for the suites and the diagnostics: the event set, the dummies' nameplates
--- up, whether a session runs (and its hide is pending), and whether a race is this rule's.
function AutoArm.Diagnose()
    local n = 0
    for _ in pairs(plates) do n = n + 1 end
    return { events = registered, plates = n, session = session ~= nil, hiding = hideTimer ~= nil,
             armed = armedRace ~= nil }
end

--- The AceEvent target (nil until a rule is first on; never on WoW Forever), for the suites.
function AutoArm.Target()
    return events
end
