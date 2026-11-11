local addonName, NS = ...
-- core/PerfSetup.lua — NS.Perf, the one performance-harness instance from LibKa0s-Perf-1.0
-- (performance-§1); the reserved `perf` verb in settings/Slash.lua drives it.

local lib = LibStub and LibStub("LibKa0s-Perf-1.0", true)

if not lib then
    -- Degrade, never error: the gate, the sink and what the slash layer touches.
    NS.Perf = {
        on        = false,
        suspended = false,
        Note      = function() end,
        Open      = function() end,
        Close     = function() end,
        OnCommand = function()
            return { NS.LIBKA0S_MISSING .. ", so performance measurement is unavailable." }
        end,
    }
    return
end

NS.Perf = lib:New({
    name      = addonName,
    addonName = addonName,
    title     = NS.BRAND,
    slash     = NS.SLASH_CMD,
    sv        = "CombatTrailPerfDB",  -- declared in the TOC (toc-file-§2)
    version   = NS.Version(),
    -- Declared in report order, each in the task that adds its real bracket: the lanes' cast event
    -- and OnUpdate, the fight watchers and the HUD's live read (plan milestones 1 to 3).
    buckets = {
        { key = "laneCast" },        -- every UNIT_SPELLCAST_* a lane hears, in modules/LaneCasts.lua
        { key = "laneRender" },      -- each lane's OnUpdate frame and push, in modules/LaneRender.lua
        { key = "probe" },           -- the armed probe's cast and combat events, in modules/Probe.lua
        { key = "meter" },           -- the live read of the player's and the pet's sources, in modules/Meter.lua
        { key = "fight" },           -- every combat, encounter and meter event, in modules/Watchers.lua
        { key = "race" },            -- every race event (regen, death, meter update, cast), in modules/RaceWatchers.lua
        { key = "autoArm" },         -- auto-show's and auto-arm's target and nameplate events, in modules/AutoArm.lua
        { key = "casts" },           -- each cast the fight record keeps, in modules/Casts.lua (inside laneCast)
        { key = "slices" },          -- the damage chart's once-a-step live read, in modules/Slices.lua (holds meter)
        { key = "hud" },             -- the HUD's live read and redraw on each FIGHT_TICK, in modules/Hud.lua (holds meter)
        { key = "raceWindow" },      -- the Race window's clock tick, its events and its pace read, in modules/RaceWindow.lua (holds meter)
    },
    -- The latch the capture's suspended arm takes its `perf` hold on. suspend/resume are NOT passed:
    -- the latch's standDown/standUp (core/LifecycleSetup.lua) are the one teardown.
    lifecycle = NS.lifecycle,
    log = function(line)
        if NS.DebugLog and NS.DebugLog.Add then NS.DebugLog:Add("Perf", line) else NS.Print(line) end
    end,
    print   = function(line) NS.Print(line) end,
    showLog = function()
        if NS.DebugLog and NS.DebugLog.Show and not NS.DebugLog:IsShown() then NS.DebugLog:Show() end
    end,
    -- No `decorate`: the library draws the step panel's close control from addonName itself
    -- (performance-§4, anti-pattern #65).
})
