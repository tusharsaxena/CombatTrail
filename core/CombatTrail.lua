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
    -- EAGER category registration; the page bodies stay lazy (options-ui-§1/§5).
    NS.CreateOptionsPanel()
    NS.Slash:Register()
end

function NS:OnEnable()
    if NS.IsStoodDown() then return end
    NS.RegisterGameEvents()
    -- The first-run skin picker (core/SkinSetup.lua), once per session on a profile that has not
    -- closed it: two seconds in, off the login spike, on an AceTimer the stand-down cancels. The
    -- stored skin was applied in OnInitialize; in combat the show holds for PLAYER_REGEN_ENABLED.
    addon:ScheduleTimer(function() NS.MaybeShowSkinPicker() end, 2)
end

-- ── Game events ─────────────────────────────────────────────────────────────────────────────────
-- Built from CURRENT settings every time, which is what lets a stand-up after a setting changed while
-- disabled come back with the right set (slash-commands-§7 step 9). The scaffold watches nothing yet:
-- the lanes, the fight watchers and the HUD each register their own events for the state they are in
-- (plan milestones 1 to 3), and add here only what the addon object itself must hear.
function NS.RegisterGameEvents()
    -- The lanes' cast events, for the lanes switched on (modules/LaneCasts.lua).
    if NS.LaneCasts then NS.LaneCasts.Sync() end
    -- The lanes' frames, built and styled from the current settings (modules/LaneRender.lua).
    if NS.LaneRender then NS.LaneRender.Sync() end
end

-- ── Host handlers ───────────────────────────────────────────────────────────────────────────────
-- ONE handler per act, shared by every surface that performs it: the launcher menu, the key binding
-- and the slash verb. Each refuses through the one hold-aware helper while stood down.

local function refused()
    local line = NS.StoodDownRefusal()
    if line then NS.Print(line) return true end
    return false
end

local function notBuilt()
    NS.Print(L["That part of Combat Trail is not built yet."])
    return false
end

-- The modules with a frame the player places: each is reached at CALL time and joins in the task
-- that builds it (the lanes, the DPS HUD and the Results window, plan milestones 1, 3 and 4). A module
-- carries `SetLocked(locked)` and `ResetPosition()`.
local PLACED = { "Lanes", "Hud", "Results" }

local function eachPlaced(method, ...)
    for _, name in ipairs(PLACED) do
        local m = NS[name]
        if m and m[method] then m[method](...) end
    end
end

--- Left-click on the launcher and the `config` verb: the settings panel (launcher-§2).
function NS.OpenSettings()
    return NS.OpenOptionsPanel()
end

--- The `general.locked` row's reaction: every placed frame locks or unlocks with it.
function NS.ApplyLocked(locked)
    eachPlaced("SetLocked", locked == true)
end

--- The launcher's Locked entry: flip the row through the seam, so its reaction runs.
function NS.ToggleLock()
    if refused() then return false end
    return NS.SetByPath("general.locked", NS.GetSetting("general.locked") ~= true)
end

--- Master controls' Reset position: every placed frame back to where it started.
function NS.ResetPositions()
    eachPlaced("ResetPosition")
end

--- The `general.hudInCombat` row's reaction: the HUD re-decides whether combat opens it.
function NS.OnHudInCombatChanged()
    if NS.Hud and NS.Hud.Refresh then NS.Hud.Refresh() end
end

--- The launcher's Show window entry and the HUD key: show or hide the DPS HUD.
function NS.ToggleHud()
    if refused() then return false end
    if not (NS.Hud and NS.Hud.Toggle) then return notBuilt() end
    NS.Hud.Toggle()
    return true
end

function NS.IsHudShown()
    return NS.Hud ~= nil and NS.Hud.IsShown ~= nil and NS.Hud.IsShown() == true
end

-- ── Test mode and Sim mode ──────────────────────────────────────────────────────────────────────
-- Session state, never stored (preview-mode). Until test mode's sample data and the sim's made-up
-- fight arrive (plan Task 5.1, modules/Preview.lua and modules/Sim.lua), each is a session flag the
-- Master controls' box, the launcher's entry and the verb all read and write, so the three already
-- agree; that task moves each read and write onto its module and keeps these names.

function NS.IsTestMode()
    local P = NS.Preview
    if P and P.Mode then return P.Mode() == "test" end
    return NS.State.testMode == true
end

--- The Test mode row's own set: start or stop test mode.
function NS.SetTestMode(on)
    local P = NS.Preview
    if P and P.Start then
        if on then P.Start() else P.Stop() end
        return
    end
    NS.State.testMode = on and true or false
end

--- `/kct test` and the launcher's Test mode entry: through the row's write seam, so the box follows.
function NS.ToggleTestMode()
    if refused() then return false end
    return NS.SetByPath("general.testMode", not NS.IsTestMode())
end

function NS.IsSimMode()
    local session = NS.Sim and NS.Sim.session
    if session then return session:IsPanelShown() == true or session:IsActive() == true end
    return NS.State.simMode == true
end

--- The launcher's Sim mode entry and the Master controls' Sim mode box: the one act.
function NS.ToggleSim()
    if refused() then return false end
    local Sim = NS.Sim
    if Sim and Sim.Toggle then return Sim.Toggle() end
    NS.State.simMode = not NS.IsSimMode()
    return true
end

--- `/kct sim [line]`: the sim's own grammar once it exists; until then a bare `sim` is the toggle.
function NS.RunSimVerb(line)
    if refused() then return false end
    local Sim = NS.Sim
    if Sim and Sim.RunVerb then return Sim.RunVerb(line) end
    if tostring(line or ""):match("^%s*$") then return NS.ToggleSim() end
    return notBuilt()
end
