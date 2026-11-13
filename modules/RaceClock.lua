local _, NS = ...
-- modules/RaceClock.lua — the race beat (race window redesign plan Task W5, ruling O5): ONE repeating
-- AceTimer on the addon object while a race runs or stops, every 1 / `hud.refreshRate` seconds (4, 5,
-- 10 or 20 a second, default 10, owner 2026-11-13: one rate for every live part of both windows;
-- RC.Interval, Hud.RefreshInterval). Each fire first hands the DPS HUD its beat (Hud.OnRaceClock: one
-- meter read and its whole redraw, while the fight on it is the race's), then sends RACE_CLOCK once
-- (core/Bus.lua), on which the Race window (modules/RaceWindow.lua) redraws its body from that same
-- read (Hud.LiveDamage), so both windows move in the same frame on the same figures. A fight that is
-- no race has the HUD's own beat at the same rate (Hud.SyncBeat), which stands down while this one
-- runs: RC.Sync tells the HUD after every change, so exactly one beat drives it.
--
-- WHICH RACE. The sample race while one stands in (NS.RaceSample.On(): test mode's `/ct test race`,
-- the sim's race scenarios), else NS.Race, the same pick as the Race window's. The beat runs while its
-- state is RUNNING or STOPPING, and never while armed, idle, on a result or stood down.
--
-- WHAT STARTS AND STOPS IT. RaceClock.Sync re-decides and moves only the difference: on every
-- RACE_STATE_CHANGED of the real race (its bus receiver here, a resumed race's included), on every
-- change of the sample race (modules/RaceSample.lua calls it, as a sample never reaches the bus), and
-- at the stand-up (Resume). A new `hud.refreshRate` (or profile) restarts a running beat at its rate.
-- The stand-down's CancelAllTimers takes the timer, and Suspend forgets it.
-- The countdown and the buzzer keep their own timers (modules/Countdown.lua, modules/Race.lua).
--
-- THE BEAT ON THE BUS, A SAMPLE'S TOO. RACE_CLOCK carries no payload: it says "draw the clocks now"
-- and nothing about any race, so a sample's beat moves no receiver's state (the sample rule of
-- modules/Preview.lua's header is about the fight and race messages, which a sample never sends).
--
-- PERF. Each fire is timed into the perf harness's `raceClock` bucket (core/PerfSetup.lua), which
-- holds the HUD's read and redraw (also in its `hud` bucket, holding `meter`) and the Race window's
-- redraw (also in its own `raceWindow` bucket).
--
-- NO METER VALUE HERE. The beat reads nothing but the race's state; the HUD's read is the HUD's, its
-- values opaque (modules/Hud.lua), and the Race window copies its player total only into labels and StatusBar:SetValue (the mini pace bars).
--
-- RETAIL ONLY (clients-§4): races are Retail's, so on WoW Forever this file returns at once and
-- NS.RaceClock is absent.

if not NS.Compat.ForClient({ "retail" }) then return end

local RC = {}
NS.RaceClock = RC

local Perf = NS.Perf

RC.TICK = 0.1         -- the default beat (s): `hud.refreshRate` 10

local timer           -- the beat's repeating AceTimer, nil while none runs
local every           -- the interval it runs at

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Race", fmt, ...) end
end

local function isDown() return NS.IsStoodDown ~= nil and NS.IsStoodDown() end

-- The race the beat follows: the sample race while one stands in, else Race.
local function src()
    local RS = NS.RaceSample
    if RS and RS.On() then return RS end
    return NS.Race
end

local function racing()
    local R, ST = src(), NS.Race.STATE
    local st = R and R.State()
    return st == ST.RUNNING or st == ST.STOPPING
end

-- One fire: the HUD's read and redraw, then one RACE_CLOCK for the Race window, on that read.
local function beat()
    if isDown() then return end
    local t0 = Perf.on and debugprofilestop()
    local Hud = NS.Hud
    if Hud and Hud.OnRaceClock then Hud.OnRaceClock() end
    NS.SendBus(NS.MSG.RACE_CLOCK)
    if t0 then Perf.Note("raceClock", debugprofilestop() - t0) end
end

--- The beat's interval (s): the DPS HUD's (1 / `hud.refreshRate`), else the default's.
--- @return number
function RC.Interval()
    local Hud = NS.Hud
    return (Hud and Hud.RefreshInterval) and Hud.RefreshInterval() or RC.TICK
end

local function stop(addon)
    if timer and addon and addon.CancelTimer then addon:CancelTimer(timer) end
    timer, every = nil, nil
end

--- Re-decide the beat from the race's state now: on while it runs or stops (at RC.Interval), else
--- off. The DPS HUD's own beat follows (Hud.SyncBeat).
function RC.Sync()
    local want = racing() and not isDown()
    local addon = NS.addon
    local interval = RC.Interval()
    if timer and (not want or every ~= interval) then
        stop(addon)
        if not want then debug("race beat off") end
    end
    if want and not timer and addon and addon.ScheduleRepeatingTimer then
        timer, every = addon:ScheduleRepeatingTimer(beat, interval), interval
        debug("race beat on, every %.2fs", interval)
    end
    local Hud = NS.Hud
    if Hud and Hud.SyncBeat then Hud.SyncBeat() end
end

--- Whether the beat runs now.
function RC.On() return timer ~= nil end

--- The fight of the race the beat runs for (the HUD redraws its clock on the beat only for it), or nil
--- while no beat runs.
function RC.Fight()
    if not timer then return nil end
    return src().Fight()
end

--- The stand-down: the beat goes (CancelAllTimers took the timer; this forgets it).
function RC.Suspend() stop(NS.addon) end

--- The stand-up: re-decided from the race's current state.
function RC.Resume() RC.Sync() end

--- What the beat is doing, for the diagnostics report.
function RC.Diagnose() return { on = timer ~= nil, every = every } end

--- One fire now, for the suites.
function RC.__beat() beat() end

do
    local bus = NS.NewBusTarget()
    if bus then
        bus:RegisterMessage(NS.MSG.RACE_STATE_CHANGED, function() RC.Sync() end)
        bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path)
            if path == "hud.refreshRate" or path == "profile" then RC.Sync() end
        end)
    end
end
