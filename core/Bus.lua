local addonName, NS = ...
-- core/Bus.lua — every message name declared ONCE, and the record of the addon's bus receivers.

-- A misspelled literal is a message nobody receives, and nothing goes red. Through a constant the
-- same typo is a nil name at the call site (architecture-§4). The wire name is
-- Ka0s_<Addon>_<Event>, <Event> PascalCase; the SCREAMING_SNAKE key never leaks into it. Each entry
-- names its one sender and its payload, and arrives in the same change as that sender (the settings
-- write seam, the lanes, the fight state machine and the recorder, plan Tasks 0.2 to 2.5).
NS.MSG = {
    -- Sender: settings/Schema.lua (NS.AnnounceSettingsChanged: the write seam, and the profile
    -- callbacks' wholesale change). Payload: (path, value); ("profile", key) on a profile change.
    SETTINGS_CHANGED = "Ka0s_CombatTrail_SettingsChanged",
}

local Bus = LibStub and LibStub("LibKa0s-Bus-1.0", true)
if not Bus then
    -- Degrade, never error. The latch's standDown unregisters only on NS.addon, so the record MUST
    -- track every target it hands out: each target's message registrations are remembered, dropped
    -- at StandDown and replayed at StandUp; one registered while down is remembered and waits.
    local function newRecord(d)
        local targets, down = {}, false        -- array: the replay order is the creation order
        local rec = { name = d and d.name }
        function rec.NewTarget()
            local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
            if not AceEvent then return nil end
            local t, held = {}, {}
            AceEvent:Embed(t)
            local reg, unreg, all = t.RegisterMessage, t.UnregisterMessage, t.UnregisterAllMessages
            t.RegisterMessage = function(self, name, handler)
                held[name] = handler or false
                if not down then return reg(self, name, handler) end
            end
            t.UnregisterMessage = function(self, name)
                held[name] = nil
                return unreg(self, name)
            end
            t.UnregisterAllMessages = function(self)
                for name in pairs(held) do held[name] = nil end
                return all(self)
            end
            targets[#targets + 1] = { t = t, held = held, reg = reg, all = all }
            return t
        end
        function rec.StandDown()
            if down then return 0 end
            down = true
            local n = 0
            for _, e in ipairs(targets) do
                for _ in pairs(e.held) do n = n + 1 end
                e.all(e.t)
            end
            return n
        end
        function rec.StandUp()
            if not down or (d and d.isDown and d.isDown()) then return 0, {} end
            down = false
            local n = 0
            for _, e in ipairs(targets) do
                for name, handler in pairs(e.held) do
                    e.reg(e.t, name, handler or nil)
                    n = n + 1
                end
            end
            return n, {}
        end
        return rec
    end
    Bus = {
        New = function(_, d) return newRecord(d) end,
        Catalog = function(_, messages) return messages end,
    }
end
NS.BusLib = Bus

-- One record per addon, beside its latch: it remembers every receiver it hands out, so the latch can
-- drop their message registrations at stand-down and replay them at stand-up (slash-commands-§7).
NS.busRecord = Bus:New({
    name   = addonName,
    isDown = function() return NS.IsStoodDown ~= nil and NS.IsStoodDown() end,
})

--- A receiver of the module's OWN (CallbackHandler keys callbacks by (message, target), so two
--- modules sharing one target clobber each other -- architecture-§4).
function NS.NewBusTarget()
    return NS.busRecord:NewTarget()
end

function NS.BusStandDown()
    return NS.busRecord:StandDown()
end

function NS.BusStandUp()
    local replayed = NS.busRecord:StandUp()
    return replayed
end

--- The one sender: every message leaves through the addon object so a receiver on any target hears
--- it. Resolved at call time because core/CombatTrail.lua builds NS.addon after this file loads.
function NS.SendBus(name, ...)
    local addon = NS.addon
    if addon and addon.SendMessage then addon:SendMessage(name, ...) end
end
