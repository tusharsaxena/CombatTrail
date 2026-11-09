local addonName, NS = ...
-- core/DebugLogSetup.lua — NS.DebugLog from LibKa0s-DebugLog-1.0; publishes the gated sink NS.Debug
-- and the console's change gates.

local L = NS.L
local lib = LibStub and LibStub("LibKa0s-DebugLog-1.0", true)

if not lib then
    -- Degrade, never error. Every member the addon calls, and SetEnabled still flips OUR flag and
    -- still acknowledges, because a player who types `/kct debug on` must not be told nothing. What
    -- is lost is the window, said once.
    local missing = NS.LIBKA0S_MISSING .. ", so the debug console window is unavailable."
    local announced = false
    local function sayOnce()
        if announced then return end
        announced = true
        NS.Print(missing)
    end
    local D = {
        buffer          = {},
        Add             = function() end,
        Debug           = function() end,
        Clear           = function() end,
        Show            = function() sayOnce() end,
        Hide            = function() end,
        Toggle          = function() sayOnce() end,
        IsShown         = function() return false end,
        IsEnabled       = function() return NS.State.debug or false end,
        SetEnabled      = function(_, on)
            NS.State.debug = on and true or false
            NS.Print("debug logging " .. (on and "ON" or "OFF"))
            if on then sayOnce() end
        end,
        ConsoleCheckbox = function()
            return {
                label   = "Debug console",
                tooltip = missing,
                get     = function() return false end,
                set     = function() sayOnce() end,
            }
        end,
        RunDiagnostics  = function()
            NS.Print(L["%s is unavailable: the LibKa0s library did not load."]:format(NS.SLASH_CMD .. " diagnostics"))
            return 0
        end,
        DebugVerb       = function() return false end,
        DebugOnce       = function() return false end,
        DebugChanged    = function() return false end,
        DebugForget     = function() end,
        DebugAtEnable   = function() return false end,
    }
    NS.DebugLog = D
    NS.Debug = D.Debug
    NS.DebugOnce, NS.DebugChanged, NS.DebugAtEnable = D.DebugOnce, D.DebugChanged, D.DebugAtEnable
    return
end

NS.DebugLog = lib:New({
    name      = addonName,                    -- seeds the frame globals and UISpecialFrames entries
    addonName = addonName,                    -- the FOLDER: the console's close/copy/clear marks
    title     = NS.BRAND,
    font      = NS.Constants.FONT_MONO,
    slash     = NS.SLASH_CMD,

    -- The flag stays the ADDON's (debug-logging-§5): session-only, never in SavedVariables.
    isEnabled  = function() return NS.State.debug or false end,
    setEnabled = function(on) NS.State.debug = on and true or false end,

    -- Call-time forwarders: NS.Print is reclaimed from AceConsole's embed in a later file.
    print        = function(line) NS.Print(line) end,
    safeToString = function(v) return NS.SafeToString(v) end,

    initSummary = function()
        local db = NS.db
        local schema = db and db.global and db.global.schemaVersion or "?"
        local profile = db and db.GetCurrentProfile and db:GetCurrentProfile() or "?"
        local fights = 0
        if db and db.global and type(db.global.fights) == "table" then
            for _ in pairs(db.global.fights) do fights = fights + 1 end
        end
        return ("CombatTrail v%s, schema v%s, profile '%s', fights %s"):format(NS.SafeToString(NS.version),
            NS.SafeToString(schema), NS.SafeToString(profile), NS.SafeToString(fights))
    end,

    -- So a console opened by `/kct debug` moves the checkbox on an already-open options panel.
    onVisibilityChanged = function()
        local H = NS.Helpers
        if H and H.RefreshAllPanels then H.RefreshAllPanels() end
    end,

    -- The diagnostics dump (debug-logging-§14): the full brand in both markers, the sections read at
    -- RUN time because modules/Diagnostics.lua loads after this file. A run turns logging on for the
    -- session; this addon takes no opt-out and never calls SetEnabled around a run.
    brandName   = NS.BRAND,
    diagnostics = function()
        local Diag = NS.Diagnostics
        return Diag and Diag.Sections and Diag.Sections() or {}
    end,
})

-- The gated sink, bare: call sites stay `NS.Debug("Fight", "%s -> %s", from, to)`.
NS.Debug = NS.DebugLog.Debug

-- The console's gates (DebugLog minor 18): a repeating path logs on change, a one-time line once, and
-- a state line written at OnEnable is held until logging is turned on (debug-logging-§8, §9).
NS.DebugOnce     = NS.DebugLog.DebugOnce
NS.DebugChanged  = NS.DebugLog.DebugChanged
NS.DebugAtEnable = NS.DebugLog.DebugAtEnable
