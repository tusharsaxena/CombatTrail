local addonName, NS = ...
-- core/LauncherSetup.lua — the ONE LibDataBroker launcher, registered twice (minimap button and broker
-- row) through LibKa0s-Launcher-1.0 (launcher-§1).
--
-- Left-click ALWAYS opens the settings panel; right-click the options menu (launcher-§2). The menu's
-- master-controls entries (Enabled, Locked, Test mode, Sim mode, Show window) arrive with the
-- handlers they share with the slash verbs (plan Task 0.2), and the key-binding buttons with
-- Bindings.xml (plan Task 5.2).

local Launcher = LibStub and LibStub("LibKa0s-Launcher-1.0", true)
local L = NS.L

local function minimapTable()
    local db = NS.db
    return db and db.global and db.global.minimap or nil
end

if not Launcher then
    -- Degrade, never error: no button and no broker row, said once, and the Minimap button row still
    -- reads and writes LibDBIcon's own `hide` key so the setting survives the next healthy load.
    local missing = NS.LIBKA0S_MISSING .. ", so there is no minimap button and no broker plugin."
    local announced = false
    NS.Launcher = {
        Register = function()
            if not announced then
                announced = true
                NS.Print(missing)
            end
            return false
        end,
        IsRegistered = function() return false end,
        Object       = function() return nil end,
        IsShown      = function()
            local t = minimapTable()
            return not (t and t.hide)
        end,
        SetShown     = function(_, shown)
            local t = minimapTable()
            if t then t.hide = not shown end
            return false
        end,
    }
    return
end

NS.Launcher = Launcher:New({
    name    = addonName,                   -- the registration name LibDBIcon keys the position by
    icon    = NS.Constants.LOGO_128,
    label   = L["Ka0s Combat Trail"],      -- the brand in plain text, never the TOC Title (launcher-§1)
    minimap = minimapTable,                -- db.global.minimap, shared with the Minimap button row
    -- Resolved at CALL time: the settings panel and the skin verb are built by settings/ files, which
    -- load after this one.
    openSettings   = function() NS.OpenSettings() end,
    openSkinPicker = function() if NS.RunSkinVerb then NS.RunSkinVerb() end end,
    version        = function() return NS.Version() end,
    print          = function(line) NS.Print(line) end,
    debug          = function(tag, message) NS.Debug(tag, "%s", message) end,
    debugAtEnable  = function(tag, message) NS.DebugAtEnable(tag, "%s", message) end,
})
