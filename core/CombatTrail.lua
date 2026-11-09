local addonName, NS = ...
-- core/CombatTrail.lua — AceAddon registration, the lifecycle kick, and the host handlers the
-- launcher, the key bindings and the slash verbs share.

local L = NS.L

local addon = LibStub("AceAddon-3.0"):NewAddon(NS, addonName, "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
NS.addon = addon

-- AceConsole's embed stamped its own :Print over NS.Print; reclaim the tagged printer every settings
-- file captured (architecture-§2: the SAME function object as NS.Util.print).
NS.Print = NS.Util.print

function NS:OnInitialize()
    self:InitDB()
    -- Before anything reads NS.db.profile (savedvariables-§1).
    self:RunMigrations()
    -- The skin the active profile names (core/SkinSetup.lua), right after the store exists: the owner
    -- registered at file load, before AceDB, and has worn the client's default skin since. Before any
    -- page or window is built, so the first paint is already the profile's skin.
    NS.ApplySkinChoice()
    -- The stored switch takes its hold before OnEnable runs, so a disabled login registers nothing.
    NS.SyncEnabledHold()
    NS.Launcher:Register()
end

function NS:OnEnable()
    if NS.IsStoodDown() then return end
    NS.RegisterGameEvents()
end

-- ── Game events ─────────────────────────────────────────────────────────────────────────────────
-- Built from CURRENT settings every time, which is what lets a stand-up after a setting changed while
-- disabled come back with the right set (slash-commands-§7 step 9). The scaffold watches nothing yet:
-- the lanes, the fight watchers and the HUD each register their own events for the state they are in
-- (plan milestones 1 to 3), and add here only what the addon object itself must hear.
function NS.RegisterGameEvents()
end

-- ── Host handlers ───────────────────────────────────────────────────────────────────────────────
-- ONE handler per act, shared by every surface that performs it: the launcher menu, the key binding
-- and the slash verb. Each refuses through the one hold-aware helper while stood down.

--- Left-click on the launcher: the settings panel (launcher-§2), once settings/ has built it.
function NS.OpenSettings()
    if NS.OpenOptionsPanel then return NS.OpenOptionsPanel() end
    NS.Print(L["That part of Combat Trail is not built yet."])
    return false
end
