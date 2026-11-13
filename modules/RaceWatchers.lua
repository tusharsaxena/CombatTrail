local _, NS = ...
-- modules/RaceWatchers.lua — the race's own event wiring (Race mode, plan Task B1): the regen edges,
-- the player's death, the race fight's damage updates and the player's casts, turned into
-- modules/Race.lua's inputs with `t` from GetTime(). Ported from DPS Race @f8078c7 (modules/Watchers.lua,
-- its race half). The fight's own wiring stays modules/Watchers.lua's: this module never feeds Fight.
--
-- WHAT IS REGISTERED, BY RACE STATE (only what the state needs):
--   idle, result        nothing
--   armed               DAMAGE_METER_RESET (the arm-time sessions are forgotten; the pull itself
--                       arrives on the bus, FIGHT_STARTED and FIGHT_FIRST_HIT)
--   running, stopping   PLAYER_REGEN_DISABLED and _ENABLED (the race's combat end), PLAYER_DEAD,
--                       DAMAGE_METER_COMBAT_SESSION_UPDATED (the timeline's stamps: the tail and the
--                       restart), and on a unit-filter frame for `player` the casts the late-cast judge
--                       reads: UNIT_SPELLCAST_START, _EMPOWER_START, _CHANNEL_START, _SUCCEEDED,
--                       _INTERRUPTED and _CHANNEL_STOP
--   stood down, Forever nothing (Race mode is Retail's, clients-§4: every registration is gated here)
-- Race calls RaceWatchers.Sync() on every transition, so the set always follows the state, and Sync
-- moves only the difference. Every registration goes through NS.SafeRegisterEvent or
-- NS.SafeRegisterUnitEvent (events-frames-taint-§1); never COMBAT_LOG_EVENT_UNFILTERED.
--
-- TWO REGISTRANTS of this module's own: an AceEvent target (AceEvent keys a registration by event and
-- target, so Fight's handler for the same regen edge is never clobbered) and a frame for the unit
-- events. Each event is timed into the perf harness's `race` bucket (core/PerfSetup.lua).
--
-- Event arguments are handed to Race untouched: a value that may be secret (the meter type, a session
-- ID, a spell ID, a castGUID) is only ever converted by it through NS.Secrets.

local RaceWatchers = {}
NS.RaceWatchers = RaceWatchers

local Perf = NS.Perf

local RETAIL = { "retail" }
local ARMED_EVENTS = { "DAMAGE_METER_RESET" }
local RACE_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD",
                      "DAMAGE_METER_COMBAT_SESSION_UPDATED" }
local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP",
}
local CAST_KIND = {
    UNIT_SPELLCAST_START         = "start",
    UNIT_SPELLCAST_EMPOWER_START = "start",
    UNIT_SPELLCAST_CHANNEL_START = "channel",
    UNIT_SPELLCAST_SUCCEEDED     = "succeeded",
    UNIT_SPELLCAST_INTERRUPTED   = "interrupted",
    UNIT_SPELLCAST_CHANNEL_STOP  = "channelStop",
}

local target            -- the AceEvent target (nil until a set is first registered)
local frame             -- the unit-filter frame (nil until the casts are first registered)
local registered = {}   -- the AceEvent events registered now, as a set
local refused = {}      -- the events the client rejected, as a set
local castsOn = false   -- whether the unit events are registered now

-- ── dispatch ────────────────────────────────────────────────────────────────────────────────────

local HANDLERS = {
    PLAYER_REGEN_DISABLED = function(t) NS.Race.OnCombatStart(t) end,
    PLAYER_REGEN_ENABLED  = function(t) NS.Race.OnCombatEnd(t) end,
    PLAYER_DEAD           = function(t) NS.Race.OnDeath(t) end,
    DAMAGE_METER_COMBAT_SESSION_UPDATED = function(t, statType, sessionID)
        NS.Race.OnMeterUpdate(t, statType, sessionID)
    end,
    DAMAGE_METER_RESET    = function() NS.Race.OnMeterReset() end,
}

local function onEvent(event, ...)
    local t0 = Perf.on and debugprofilestop()
    local handler = HANDLERS[event]
    if handler then handler(GetTime(), ...) end
    if t0 then Perf.Note("race", debugprofilestop() - t0) end
end

-- A frame's OnEvent: (self, event, unit, castGUID, spellID). The filter is `player`; the unit is still
-- checked, as the client's filter is the only one that holds it.
local function onCastEvent(_, event, unit, castGUID, spellID)
    local t0 = Perf.on and debugprofilestop()
    local kind = CAST_KIND[event]
    if kind and unit == "player" then NS.Race.OnCast(kind, spellID, GetTime(), castGUID) end
    if t0 then Perf.Note("race", debugprofilestop() - t0) end
end

-- ── registration ────────────────────────────────────────────────────────────────────────────────

local function ensureTarget()
    if target then return target end
    target = LibStub("AceEvent-3.0"):Embed({})
    return target
end

local function ensureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", onCastEvent)
    return frame
end

local function racing(st)
    local S = NS.Race.STATE
    return st == S.RUNNING or st == S.STOPPING
end

-- The AceEvent events the race's state asks for, and whether it wants the casts.
local function wanted()
    if NS.IsStoodDown() or not NS.Compat.ForClient(RETAIL) or not NS.Race then return {}, false end
    local st = NS.Race.State()
    if st == NS.Race.STATE.ARMED then return ARMED_EVENTS, false end
    if racing(st) then return RACE_EVENTS, true end
    return {}, false
end

local function syncEvents(list)
    local want = {}
    for _, event in ipairs(list) do want[event] = true end
    for event in pairs(registered) do
        if not want[event] then
            pcall(target.UnregisterEvent, target, event)
            registered[event] = nil
        end
    end
    for event in pairs(want) do
        if not registered[event] and not refused[event] then
            if NS.SafeRegisterEvent(ensureTarget(), event, onEvent, NS.rejectedEvents) then
                registered[event] = true
            else
                refused[event] = true
            end
        end
    end
end

local function syncCasts(on)
    if on == castsOn then return end
    castsOn = on
    if not on then
        if frame then frame:UnregisterAllEvents() end
        return
    end
    local f = ensureFrame()
    for _, event in ipairs(CAST_EVENTS) do NS.SafeRegisterUnitEvent(f, event, NS.rejectedEvents, "player") end
end

--- Make the registrations match the race's state (nothing stood down or on WoW Forever).
function RaceWatchers.Sync()
    local list, casts = wanted()
    syncEvents(list)
    syncCasts(casts)
end

--- The lifecycle's stand-down: every registration goes.
function RaceWatchers.Suspend()
    if target then
        for event in pairs(registered) do pcall(target.UnregisterEvent, target, event) end
    end
    registered = {}
    if frame then frame:UnregisterAllEvents() end
    castsOn = false
end

--- The lifecycle's stand-up: rebuilt from the race's current state.
function RaceWatchers.Resume()
    RaceWatchers.Sync()
end

--- The AceEvent target and the cast frame (each nil until first registered), for the suites.
function RaceWatchers.Targets()
    return target, frame
end
