local addonName, NS = ...
-- core/LifecycleSetup.lua — the ONE stand-down latch, from LibKa0s-Lifecycle-1.0: the `disabled` hold
-- (the stored `general.enabled` row) and the `perf` hold (a capture's suspended arm) both take it
-- (slash-commands-§7, performance-§6).

local Lifecycle = LibStub and LibStub("LibKa0s-Lifecycle-1.0", true)
local L = NS.L

-- The feature modules that stand down and back up on their own terms, in that order. Each is reached
-- at CALL time (the modules load after this file), and each module adds its name here in the task
-- that builds it: the lanes, the fight watchers, the HUD and the Results window (plan milestones 1 to
-- 4). A module carries `Suspend` (nothing on screen, no timer, no registration) and `Resume` (rebuilt
-- from CURRENT settings).
local MODULES = { "LaneCasts", "LaneAnchor", "LaneVisibility", "LaneRender", "Probe", "Meter", "Fight",
                  "Watchers" }

--- Disabled means NOT RUNNING. Every registration goes -- not gated -- every timer is canceled, and
--- every frame is hidden at the source of its show decision.
local function standDown()
    local addon = NS.addon
    if addon then
        if addon.UnregisterAllEvents then addon:UnregisterAllEvents() end
        if addon.UnregisterAllMessages then addon:UnregisterAllMessages() end
        if addon.CancelAllTimers then addon:CancelAllTimers() end
    end
    NS.BusStandDown()
    for _, name in ipairs(MODULES) do
        local m = NS[name]
        if m and m.Suspend then m.Suspend() end
    end
    -- The first-run skin picker is a frame this addon shows: it goes down unmarked, so it comes back
    -- on the next login the addon stands up for (core/SkinSetup.lua).
    if NS.HideSkinPicker then NS.HideSkinPicker() end
end

--- Back up FROM CURRENT STATE, never from a snapshot taken at stand-down (performance-§6): a setting
--- changed while down comes back correctly because the registrations are rebuilt from it.
local function standUp()
    NS.BusStandUp()
    if NS.RegisterGameEvents then NS.RegisterGameEvents() end
    for _, name in ipairs(MODULES) do
        local m = NS[name]
        if m and m.Resume then m.Resume() end
    end
end

NS.StandDown, NS.StandUp = standDown, standUp

if Lifecycle then
    NS.lifecycle = Lifecycle:New({
        name      = addonName,
        standDown = standDown,
        standUp   = standUp,
        print     = function(line) NS.Print(line) end,
        -- The library logs every edge with its holds; the callbacks above write no edge line.
        debug     = function(tag, message) if NS.Debug then NS.Debug(tag, "%s", message) end end,
    })
else
    -- Degrade, never error: the same two-hold latch, every member the addon calls.
    local held, down = {}, false
    local function edge()
        local want = next(held) ~= nil
        if want == down then return false end
        down = want
        if down then standDown() else standUp() end
        return true
    end
    local lc = { name = addonName }
    function lc.Hold(_, key) held[key] = true; return edge() end
    function lc.Release(_, key) held[key] = nil; return edge() end
    function lc.Set(self, key, want)
        if want then return self:Hold(key) end
        return self:Release(key)
    end
    function lc.IsHeld(_, key) return held[key] == true end
    function lc.IsDown() return down end
    function lc.Reevaluate() return edge() end
    function lc.Holds()
        local out = {}
        for key in pairs(held) do out[#out + 1] = key end
        table.sort(out)
        return out
    end
    function lc.PrintHolds() return false end
    NS.lifecycle = lc
end

-- The two hold names, read off the major so the arm that takes a hold and the arm that releases it
-- cannot disagree about what it is called.
NS.HOLD_DISABLED = Lifecycle and Lifecycle.HOLD_DISABLED or "disabled"
NS.HOLD_PERF     = Lifecycle and Lifecycle.HOLD_PERF or "perf"

-- The capitalized alias the plan's interface names; the same object.
NS.Lifecycle = NS.lifecycle

--- The `general.enabled` row's reaction: take or release the `disabled` hold. Never a direct stand-up, so
--- re-enabling during a capture does not resurrect an addon the `perf` hold still holds down.
function NS.ApplyEnabled(enabled)
    return NS.lifecycle:Set(NS.HOLD_DISABLED, enabled == false)
end

--- Re-read the stored switch (login, and every profile change/copy/reset, which can flip it).
function NS.SyncEnabledHold()
    local on = NS.GetSetting and NS.GetSetting("general.enabled")
    return NS.ApplyEnabled(on ~= false)
end

function NS.IsStoodDown()
    return NS.lifecycle:IsDown() == true
end

function NS.IsDisabled()
    return NS.lifecycle:IsHeld(NS.HOLD_DISABLED) == true
end

--- THE one refusal helper (slash-commands-§7, "Which refusal, by hold"): the line a stood-down
--- feature prints, or nil while standing up. The `disabled` hold answers the dispatcher's refusal
--- line and wins over `perf`; the `perf` hold alone answers the capture line, never the disabled one.
function NS.StoodDownRefusal()
    if not NS.IsStoodDown() then return nil end
    if NS.IsDisabled() then
        local Sl = NS.Slash
        if Sl and Sl.DisabledLine then return Sl:DisabledLine() end
    end
    return L["Not available during a performance capture."]
end
