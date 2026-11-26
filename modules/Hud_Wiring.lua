local _, NS = ...
-- modules/Hud_Wiring.lua — the DPS HUD's wiring, peeled from modules/Hud.lua at the 1500-line cap
-- (layout-§1, R4-CT-07): its bus receiver and its slash verb. Nothing registered with the client: the
-- HUD hears the bus on its own target (modules/Hud.lua's header, *What runs, and when*), each message
-- handed straight to the shell's public receiver.

local Hud = NS.Hud
local L = NS.L

do
    local bus = NS.NewBusTarget()
    if bus then
        bus:RegisterMessage(NS.MSG.FIGHT_STARTED, function(_, fight) Hud.OnFightStarted(fight) end)
        bus:RegisterMessage(NS.MSG.FIGHT_TICK, function(_, fight) Hud.OnFightTick(fight) end)
        bus:RegisterMessage(NS.MSG.FIGHT_ENDED, function(_, fight, final, reason) Hud.OnFightEnded(fight, final, reason) end)
        bus:RegisterMessage(NS.MSG.FIGHT_SAVED, function(_, record) Hud.OnFightSaved(record) end)
        bus:RegisterMessage(NS.MSG.FIGHT_SKIPPED, function(_, fight, reason) Hud.OnFightSkipped(fight, reason) end)
        bus:RegisterMessage(NS.MSG.RACE_ARMED, function() Hud.OnRaceArmed() end)
        bus:RegisterMessage(NS.MSG.RACE_STARTED, function(_, _, fight) Hud.OnRaceStarted(fight) end)
        bus:RegisterMessage(NS.MSG.RACE_CANCELED, function() Hud.OnRaceCanceled() end)
        bus:RegisterMessage(NS.MSG.RACE_STATE_CHANGED, function(_, _, from, to) Hud.OnRaceStateChanged(from, to) end)
        bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path, value) Hud.OnSettings(path, value) end)
    end
end

local VERBS = {
    show = function() Hud.Show() end,
    hide = function() Hud.HideWithRace() end,
    toggle = function() Hud.Toggle() end,
    pin = function() Hud.Pin(true) end,
    unpin = function() Hud.Pin(false) end,
}

--- `/ct hud show|hide|toggle|pin|unpin`.
function Hud.OnVerb(rest)
    local word = tostring(rest or ""):match("^%s*(%S*)"):lower()
    local fn = VERBS[word]
    if fn then return fn() end
    NS.Print(L["Usage: /ct hud show, hide, toggle, pin or unpin"])
end
