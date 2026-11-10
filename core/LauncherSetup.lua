local addonName, NS = ...
-- core/LauncherSetup.lua — the ONE LibDataBroker launcher, registered twice (minimap button and broker
-- row) through LibKa0s-Launcher-1.0 (launcher-§1).
--
-- Left-click ALWAYS opens the settings panel; right-click the options menu (launcher-§2), whose
-- master-controls entries are Enabled, Locked, Test mode, Sim mode and Show window (the DPS HUD), each
-- on the handler its slash verb runs (core/CombatTrail.lua). Also the three key-binding buttons
-- (launcher-§6, plan Task 5.2) and NS.BINDINGS, the table Bindings.xml and the General page's
-- Keybindings tab are both held to.

local Launcher = LibStub and LibStub("LibKa0s-Launcher-1.0", true)
local L = NS.L

-- The key bindings (launcher-§6). Each button is plain, named, hidden and NOT secure, registered for
-- the down edge only, and its click runs the SAME handler the launcher menu and the slash verb run
-- (core/CombatTrail.lua), which refuses through the one hold-aware helper while stood down. The NAMES
-- ARE PERMANENT: the client stores the player's key against them, so a rename unbinds every key. The
-- handlers are reached at CALL time: core/CombatTrail.lua loads after this file.
NS.TOGGLE_HUD_BUTTON     = "CombatTrailToggleHud"
NS.TOGGLE_RESULTS_BUTTON = "CombatTrailToggleResults"
NS.TOGGLE_LANES_BUTTON   = "CombatTrailToggleLanes"
do
    local function button(name, handler)
        local b = CreateFrame("Button", name, UIParent)
        b:RegisterForClicks("AnyDown")
        b:SetScript("OnClick", function() NS[handler]() end)
        b:Hide()
        return b
    end
    button(NS.TOGGLE_HUD_BUTTON, "ToggleHud")
    button(NS.TOGGLE_RESULTS_BUTTON, "ToggleResults")
    button(NS.TOGGLE_LANES_BUTTON, "ToggleLanes")
end

-- The ONE bindings table (launcher-§6), in Bindings.xml's order with the Show window key first: the
-- General page's Keybindings tab draws its rows from it (options-ui-§20) and the suite checks
-- Bindings.xml against it. Each command is the CLICK binding on the button above.
local function clickCommand(button) return "CLICK " .. button .. ":LeftButton" end
NS.BINDINGS = {
    { command = clickCommand(NS.TOGGLE_HUD_BUTTON),
      tooltip = L["Shows or hides the DPS HUD, as the launcher's Show window entry and /kct hud do."] },
    { command = clickCommand(NS.TOGGLE_RESULTS_BUTTON),
      tooltip = L["Shows or hides the Results window, with your fight history."] },
    { command = clickCommand(NS.TOGGLE_LANES_BUTTON),
      tooltip = L["Shows or hides the Player and Pet cast lanes."] },
}
-- The category's title is the brand, assigned at file scope because the client reads it when it
-- registers the bindings (launcher-§6). The labels' global names hold a space and a colon, so no
-- identifier can spell them: rawset.
rawset(_G, "BINDING_HEADER_COMBATTRAIL", L["Ka0s Combat Trail"])
rawset(_G, "BINDING_NAME_" .. NS.BINDINGS[1].command, L["Toggle DPS HUD"])
rawset(_G, "BINDING_NAME_" .. NS.BINDINGS[2].command, L["Toggle Results window"])
rawset(_G, "BINDING_NAME_" .. NS.BINDINGS[3].command, L["Toggle lanes"])

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

-- The descriptor, published for the suite (tests/test_slash.lua) so it can pin the menu's pairs.
NS.LAUNCHER_DESCRIPTOR = {
    name    = addonName,                   -- the registration name LibDBIcon keys the position by
    icon    = NS.Constants.LOGO_128,
    label   = L["Ka0s Combat Trail"],      -- the brand in plain text, never the TOC Title (launcher-§1)
    minimap = minimapTable,                -- db.global.minimap, shared with the Minimap button row
    -- Resolved at CALL time: the handlers live in core/CombatTrail.lua and the settings panel and the
    -- skin verb in settings/ files, all of which load after this one. Each toggle calls the same
    -- handler its verb calls -- never a copy -- and the library grays every entry but Enabled while
    -- the addon is disabled.
    openSettings   = function() NS.OpenSettings() end,
    openSkinPicker = function() if NS.RunSkinVerb then NS.RunSkinVerb() end end,
    isEnabled      = function() return not NS.IsDisabled() end,
    setEnabled     = function(on) NS.RunVerb(on and "enable" or "disable") end,
    isLocked       = function() return NS.GetSetting("general.locked") == true end,
    toggleLock     = function() NS.ToggleLock() end,
    isTestMode     = function() return NS.IsTestMode() end,
    toggleTestMode = function() NS.ToggleTestMode() end,
    isWindowShown  = function() return NS.IsHudShown() end,
    toggleWindow   = function() NS.ToggleHud() end,
    -- The ONE pair General > Master controls' Sim mode box carries too.
    isSimMode      = function() return NS.IsSimMode() end,
    toggleSim      = function() return NS.ToggleSim() end,
    version        = function() return NS.Version() end,
    print          = function(line) NS.Print(line) end,
    debug          = function(tag, message) NS.Debug(tag, "%s", message) end,
    debugAtEnable  = function(tag, message) NS.DebugAtEnable(tag, "%s", message) end,
}
NS.Launcher = Launcher:New(NS.LAUNCHER_DESCRIPTOR)
