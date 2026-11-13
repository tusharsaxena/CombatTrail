local _, NS = ...
-- modules/Countdown.lua — a race's final seconds and its buzzer on LibKa0s-Callout-1.0 (callout plan
-- row C2; Race mode spec §4.2 before it). The addon's one call-out instance (NS.Callout, through the
-- core/CalloutSetup.lua seam) shows the race's last seconds as big numbers in the middle of the screen,
-- spoken in the player's chosen voice, and STOP at the buzzer. When `race.finalCountdown` seconds remain
-- (3-10, default 10) and `race.centerCountdown` is on, the call-out counts down to 1 and goes at the
-- buzzer; with `race.buzzer` on, it then says STOP. The call-out's own look, voice and words are its
-- settings: the profile's `callout` table when one exists, which no default seeds and nothing writes
-- yet (defaults/Profile.lua, callout plan row C2), so today the library's DEFAULTS.
--
-- ONE endsAt (owner, 2026-11-13: the numbers and the Race window's clock had disagreed). The call-out
-- counts down to RaceClock.EndsAt(), the buzzer's moment on the GetTime() clock, the same value the
-- Race window's time left is read from (Race.EndsAt, modules/RaceClock.lua). Its number is
-- ceil(endsAt - now), read on the frame by the library, so n shows from n seconds left until n - 1,
-- and on each new number the race beat runs once at once (RaceClock.Kick): the Race window reads
-- 0:0n.0 in the frame the call-out shows n, and 1 goes in the frame the buzzer's 0:00.0 is drawn.
--
-- ONE TIMER, THEN THE LIBRARY'S FRAME CLOCK. The call-out's countdown runs an OnUpdate while it is
-- armed, so it is not armed for the whole race: while more than `window + LEAD` seconds remain, one
-- AceTimer on the addon object waits (re-armed for what is left when serviced early, as the client
-- never does and the headless kit does), and then the call-out is handed the race's endsAt. Re-arming
-- with the same endsAt and window leaves a running countdown alone, so a refresh never repeats a
-- number. A new window (or the numbers switched off) takes the number down at once.
--
-- THE SIM'S RACE (plan Task E1): while its sample race's clock runs (modules/RaceSample.lua Live),
-- RaceClock.EndsAt is the sample's, armed by the sim's own Countdown.Refresh at each step; test mode's
-- held sample has none and counts nothing.
--
-- A RESUME mid-window (a /reload, a stand-up, a countdown row changed mid-race) shows the number of
-- the moment at once and counts on from there. The rows carry no onChange: their SETTINGS_CHANGED
-- (and a profile change, which also re-applies the call-out's look) re-arm it here.
--
-- THE BUZZER (RACE_BUZZER, whether or not the Race window is shown): leaving running has already
-- taken the countdown down (RACE_STATE_CHANGED comes first), and with `race.buzzer` on the call-out
-- shows the stock STOP with its voice, held for the call-out's hold. Leaving running any other way (a
-- cancel, combat ending early) takes the number down and says nothing.
--
-- THE STAND-DOWN: the lead-in timer goes and the call-out is suspended (NS.Callout:Suspend: no
-- countdown, nothing shown, no OnUpdate, Show and Countdown refused) until the stand-up resumes it.
--
-- RETAIL ONLY (clients-§4): races are Retail's, so on WoW Forever this file returns at once and
-- NS.Countdown and NS.Callout are absent. Nothing here reads a meter value: the call-out is handed a
-- GetTime() value and a stock key, never a figure.

if not NS.Compat.ForClient({ "retail" }) then return end

local Countdown = {}
NS.Countdown = Countdown

-- The numbers' window bounds (race.finalCountdown's range).
Countdown.MIN, Countdown.MAX = 3, 10
-- The seconds before the first number that the call-out is handed the countdown.
Countdown.LEAD = 1
Countdown.FRAME_NAME = "CombatTrailCallout"
-- A whole second computed from GetTime() differences may land a hair either side of the integer.
local EPS = 1e-6

--- The addon's one call-out (core/CalloutSetup.lua; the stub without the library). Its settings are
--- the profile's `callout` table, read at every call, so a profile switch is followed; with none (the
--- profile ships no such key), the getter answers nil and the call-out reads the library's DEFAULTS.
NS.Callout = NS.NewCallout({
    name = Countdown.FRAME_NAME,
    db = function()
        local db = NS.db
        return db and db.profile and db.profile.callout or nil
    end,
})
local CO = NS.Callout

local lead       -- the lead-in AceTimer, while it waits
local armedAt    -- the endsAt the call-out counts down to, nil while it counts nothing
local armedFrom  -- the window it was armed with

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Countdown", fmt, ...) end
end

-- ── settings ────────────────────────────────────────────────────────────────────────────────────

local function numbersOn() return NS.GetSetting("race.centerCountdown") ~= false end

--- race.finalCountdown, clamped to its range.
local function window()
    local n = math.floor(tonumber(NS.GetSetting("race.finalCountdown")) or Countdown.MAX)
    return math.max(Countdown.MIN, math.min(Countdown.MAX, n))
end

-- ── the race's countdown ────────────────────────────────────────────────────────────────────────

local function cancelLead()
    local addon = NS.addon
    if lead and addon and addon.CancelTimer then addon:CancelTimer(lead) end
    lead = nil
end

--- Take the race's countdown down: the lead-in and the call-out's number. A call-out the countdown did
--- not put up (the buzzer's STOP) keeps its hold.
local function takeDown()
    cancelLead()
    if armedAt then
        armedAt, armedFrom = nil, nil
        CO:Cancel()
    end
end

-- Each new number: the race beat once, so the Race window draws its 0:0n.0 in this frame.
local function onTick()
    local RC = NS.RaceClock
    if RC and RC.Kick then RC.Kick() end
end

local function racing()
    return not NS.IsStoodDown() and NS.RaceClock ~= nil and NS.RaceClock.EndsAt() ~= nil
end

local arm

local function wait(delay)
    local addon = NS.addon
    if addon and addon.ScheduleTimer then lead = addon:ScheduleTimer(arm, math.max(0, delay)) end
end

--- Arm the race's countdown from its endsAt: the call-out at once inside the lead, else the lead-in.
arm = function()
    cancelLead()
    if not (racing() and numbersOn()) then return takeDown() end
    local at, from = NS.RaceClock.EndsAt(), window()
    if at == armedAt and from == armedFrom and CO:Running() then return end
    local left = at - GetTime()
    if left > from + Countdown.LEAD + EPS then
        if armedAt then takeDown() end
        return wait(left - from - Countdown.LEAD)
    end
    -- A new window or a new race: the old number goes first, so a smaller window never leaves it up.
    if armedAt then CO:Cancel() end
    -- Armed only when the call-out took it: the stub, or a suspended instance, answers false, and
    -- Diagnose must not then report a countdown that nothing runs.
    if CO:Countdown({ endsAt = at, from = from, finish = false, onTick = onTick }) then
        armedAt, armedFrom = at, from
        debug("counting down from %d, %.2fs left", from, left)
    else
        armedAt, armedFrom = nil, nil
    end
end

-- ── the buzzer ──────────────────────────────────────────────────────────────────────────────────

--- RACE_BUZZER: the call-out's STOP with its voice, with `race.buzzer` on.
--- @return boolean raised
function Countdown.Buzzer()
    if NS.IsStoodDown() or NS.GetSetting("race.buzzer") == false then return false end
    takeDown()
    local shown = CO:Show("STOP") ~= false
    if shown then debug("buzzer: STOP") end
    return shown
end

-- ── the public surface ──────────────────────────────────────────────────────────────────────────

--- The number the call-out shows for the race now, or nil.
--- @return number|nil
function Countdown.Shown()
    if not armedAt then return nil end
    local running, n = CO:Running()
    return running and n or nil
end

--- The countdown rows' reaction (race.centerCountdown, race.finalCountdown, a profile change), and the
--- sim's sample race moving on (modules/SimRace.lua): re-arm from the new values, or take it down when
--- the race no longer runs.
function Countdown.Refresh()
    if racing() then arm() else takeDown() end
end

--- The lifecycle's stand-down: the lead-in canceled, the call-out suspended.
function Countdown.Suspend()
    cancelLead()
    armedAt, armedFrom = nil, nil
    CO:Suspend()
end

--- The stand-up: the call-out resumed, and re-armed from the race's current state (Race resumes
--- before this module does).
function Countdown.Resume()
    CO:Resume()
    if racing() then arm() end
end

--- What it is doing, for the diagnostics report: the number shown, what is armed (the lead-in or the
--- call-out's countdown), the owner.
function Countdown.Diagnose()
    local n = (lead and 1 or 0) + (armedAt and 1 or 0)
    return { shown = Countdown.Shown() or "none", scheduled = n, owner = armedAt and "race" or "none" }
end

local ROWS = { ["race.centerCountdown"] = true, ["race.finalCountdown"] = true, profile = true }

do
    local bus = NS.NewBusTarget()
    if bus then
        bus:RegisterMessage(NS.MSG.RACE_STATE_CHANGED, function(_, _, _, to)
            if to == NS.Race.STATE.RUNNING then arm() else takeDown() end
        end)
        bus:RegisterMessage(NS.MSG.RACE_BUZZER, function() Countdown.Buzzer() end)
        bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path)
            if path == "profile" then CO:Apply() end
            if ROWS[path] then Countdown.Refresh() end
        end)
    end
end
