local _, NS = ...
-- modules/Watchers.lua — the fight's event wiring (plan Task 2.2): combat, encounters and the meter,
-- turned into modules/Fight.lua's inputs with `t` from GetTime(). Adapted from DPS Race @045f479
-- (modules/Watchers.lua) without its race: nothing is armed, and the casts are not heard here (the
-- lanes hear them in modules/LaneCasts.lua; the fight's cast list arrives with plan Task 2.4).
--
-- WHAT IS REGISTERED, BY FIGHT STATE (only what the state needs):
--   idle              PLAYER_REGEN_DISABLED (a fight starts) and ENCOUNTER_START (an encounter that
--                     opens before the regen edge names the fight, or starts one while in combat),
--                     plus ENCOUNTER_END while an encounter is active (Fight.EncounterActive), so one
--                     that ends with the player out of combat (dead, the raid fighting on) is heard
--                     and does not name the next fight
--   combat, settling  the same, plus PLAYER_REGEN_ENABLED, ENCOUNTER_END and the meter's three events
--                     (DAMAGE_METER_COMBAT_SESSION_UPDATED, _CURRENT_SESSION_UPDATED, _RESET)
--   stood down        nothing
-- Fight calls Watchers.Sync() on every transition, so the set always follows the state. Sync moves
-- only the difference: an event in both sets stays registered, so a regen edge being dispatched is
-- never unregistered under itself (an idle ENCOUNTER_END drops itself after its handler has run,
-- which AceEvent's dispatch allows). Every registration goes through NS.SafeRegisterEvent
-- (events-frames-taint-§1), so an event name a client does not know costs only itself and lands in
-- NS.rejectedEvents. Never COMBAT_LOG_EVENT_UNFILTERED: it is protected for addons on both clients.
--
-- ONE REGISTRANT: this module's own AceEvent target (AceEvent keys a registration by event and target,
-- so no other module's handler for the same edge is clobbered).
--
-- STAND-DOWN (slash-commands-§7). The lifecycle's stand-down calls Watchers.Suspend(), which drops
-- every registration; Sync answers "nothing" while stood down, and the stand-up's
-- NS.RegisterGameEvents rebuilds the set from the fight's CURRENT state (IDLE after a stand-down).
--
-- Event arguments are handed to Fight untouched: a value that may be secret (the meter type, the
-- session ID, an encounter's fields) is only ever converted by it through NS.Secrets.

local Watchers = {}
NS.Watchers = Watchers

local Perf = NS.Perf

local IDLE_EVENTS = { "PLAYER_REGEN_DISABLED", "ENCOUNTER_START" }
local IDLE_ENCOUNTER_EVENTS = { "PLAYER_REGEN_DISABLED", "ENCOUNTER_START", "ENCOUNTER_END" }
local FIGHT_EVENTS = {
    "PLAYER_REGEN_DISABLED",
    "ENCOUNTER_START",
    "PLAYER_REGEN_ENABLED",
    "ENCOUNTER_END",
    "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    "DAMAGE_METER_CURRENT_SESSION_UPDATED",
    "DAMAGE_METER_RESET",
}

local target          -- this module's AceEvent target (nil until a set is first registered)
local registered = {} -- the events registered now, as a set

-- ── dispatch ────────────────────────────────────────────────────────────────────────────────────

local HANDLERS = {
    PLAYER_REGEN_DISABLED = function(t) NS.Fight.OnCombatStart(t) end,
    PLAYER_REGEN_ENABLED  = function(t) NS.Fight.OnCombatEnd(t) end,
    ENCOUNTER_START       = function(t, ...) NS.Fight.OnEncounterStart(t, ...) end,
    ENCOUNTER_END         = function(t, ...) NS.Fight.OnEncounterEnd(t, ...) end,
    DAMAGE_METER_COMBAT_SESSION_UPDATED  = function(t, statType, sessionID)
        NS.Fight.OnMeterUpdate(t, statType, sessionID)
    end,
    DAMAGE_METER_CURRENT_SESSION_UPDATED = function(t) NS.Fight.OnSessionCreated(t) end,
    DAMAGE_METER_RESET    = function() NS.Fight.OnMeterReset() end,
}

-- AceEvent hands a function handler (event, ...).
local function onEvent(event, ...)
    local t0 = Perf.on and debugprofilestop()
    local handler = HANDLERS[event]
    if handler then handler(GetTime(), ...) end
    if t0 then Perf.Note("fight", debugprofilestop() - t0) end
end

-- ── registration ────────────────────────────────────────────────────────────────────────────────

local function ensureTarget()
    if target then return target end
    target = LibStub("AceEvent-3.0"):Embed({})
    return target
end

-- The events the fight's state asks for, as a list.
local function wanted()
    if NS.IsStoodDown() then return {} end
    if NS.Fight.State() == NS.Fight.STATE.IDLE then
        return NS.Fight.EncounterActive() and IDLE_ENCOUNTER_EVENTS or IDLE_EVENTS
    end
    return FIGHT_EVENTS
end

--- Make the registrations match the fight's state (and nothing while stood down). Moves only the
--- difference, so it is cheap when they already match.
function Watchers.Sync()
    local want = {}
    for _, event in ipairs(wanted()) do want[event] = true end
    for event in pairs(registered) do
        if not want[event] then
            target:UnregisterEvent(event)
            registered[event] = nil
        end
    end
    for event in pairs(want) do
        if not registered[event] then
            NS.SafeRegisterEvent(ensureTarget(), event, onEvent, NS.rejectedEvents)
            registered[event] = true
        end
    end
end

--- The lifecycle's stand-down: every registration goes.
function Watchers.Suspend()
    if target then target:UnregisterAllEvents() end
    registered = {}
end

--- The lifecycle's stand-up: rebuilt from the fight's current state.
function Watchers.Resume()
    Watchers.Sync()
end

--- The AceEvent target (nil until a set was first registered), for the suites.
function Watchers.EventTarget()
    return target
end
