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
    -- A race a /reload cut off, carried on once the meter is primed (modules/Race.lua, Task B2).
    if NS.Race then NS.Race.Resume() end
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
    -- The lanes' Edit Mode callbacks and their visibility rules' events (modules/LaneAnchor.lua,
    -- modules/LaneVisibility.lua), before the frames that read both.
    if NS.LaneAnchor then NS.LaneAnchor.Sync() end
    if NS.LaneVisibility then NS.LaneVisibility.Sync() end
    -- The lanes' frames, built and styled from the current settings (modules/LaneRender.lua).
    if NS.LaneRender then NS.LaneRender.Sync() end
    -- The meter's session list, read once as the baseline a new fight's session is told apart from
    -- (modules/Meter.lua). It registers nothing.
    if NS.Meter then NS.Meter.Prime() end
    -- WoW Forever's talent trees, read once out of combat as the last plain read a sealed in-combat
    -- snapshot keeps (modules/Identity.lua). It registers nothing.
    if NS.Identity then NS.Identity.Prime() end
    -- The fight watchers' events for the fight state machine's current state (modules/Watchers.lua).
    if NS.Watchers then NS.Watchers.Sync() end
    -- The race's events for the race's current state, Retail only (modules/RaceWatchers.lua).
    if NS.RaceWatchers then NS.RaceWatchers.Sync() end
    -- Auto-show and auto-arm near a training dummy: their target and nameplate events, for the rules
    -- on, with Race mode on, on Retail (modules/AutoArm.lua).
    if NS.AutoArm then NS.AutoArm.Sync() end
    -- The equipment recon's events, and one recon now: at login and every stand-up, whatever the gear
    -- became while the addon was not watching is interned as the current set (modules/Loadouts.lua).
    if NS.Loadouts then NS.Loadouts.Sync() end
    -- The stored fights' purge, at login and every stand-up, and its daily timer (modules/Retention.lua).
    if NS.Retention then NS.Retention.Sync() end
    -- The DPS HUD registers nothing with the client; "always" opens it at login and every stand-up
    -- (modules/Hud.lua).
    if NS.Hud then NS.Hud.Sync() end
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

--- The Results window key and `/ct results`: show or hide the Results window.
--- The Race window's words, by the act each one asks of it.
local RACE_WINDOW_ACT = { show = "Show", hide = "Hide", toggle = "Toggle" }

--- `/ct race show|hide|toggle` (Race mode, Retail): show, hide or toggle the Race window (Task C1's
--- NS.RaceWindow). With Race mode off it does nothing and says why in one line (spec §8).
--- @param how string  "show" | "hide" | "toggle"
function NS.SetRaceWindowShown(how)
    if refused() then return false end
    if not NS.RaceMode.On() then
        NS.Print(L["Race mode is off. Turn it on at the top of the Race mode settings page."])
        return false
    end
    local W = NS.RaceWindow
    local act = W and W[RACE_WINDOW_ACT[how] or "Toggle"]
    if not act then return notBuilt() end
    act()
    return true
end

--- `/ct race toggle`: show or hide the Race window.
function NS.ToggleRaceWindow()
    return NS.SetRaceWindowShown("toggle")
end

function NS.ToggleResults()
    if refused() then return false end
    if not (NS.Results and NS.Results.Toggle) then return notBuilt() end
    NS.Results.Toggle()
    return true
end

-- ── the lanes key ───────────────────────────────────────────────────────────────────────────────
-- The Toggle lanes key writes each lane's Enable row through the seam, so the Lanes page, `/ct lane`
-- and the CLI read what the key did. Off remembers which lanes were on, for this session only, so the
-- key brings back exactly those; with no memory (both were off), it turns both on.

local LANE_KEYS = { "player", "pet" }
local lanesWereOn   -- { [laneKey] = true } while the key holds the lanes off, else nil

local function laneOn(key)
    return NS.GetSetting("lanes." .. key .. ".enabled") ~= false
end

--- The Toggle lanes key: every lane that is on goes off, or the lanes the key turned off come back.
function NS.ToggleLanes()
    if refused() then return false end
    local on = {}
    for _, key in ipairs(LANE_KEYS) do
        if laneOn(key) then on[key] = true end
    end
    if next(on) then
        lanesWereOn = on
        for key in pairs(on) do NS.SetByPath("lanes." .. key .. ".enabled", false) end
        NS.Print(L["The lanes are off. Press the key again to bring them back."])
    else
        local back = lanesWereOn or { player = true, pet = true }
        lanesWereOn = nil
        for _, key in ipairs(LANE_KEYS) do
            if back[key] then NS.SetByPath("lanes." .. key .. ".enabled", true) end
        end
        NS.Print(L["The lanes are on."])
    end
    return true
end

-- ── Test mode and Sim mode ──────────────────────────────────────────────────────────────────────
-- Session state, never stored (preview-mode): modules/Preview.lua owns the switch and its end
-- conditions, modules/Sim.lua the sim's grammar and its step window. The Master controls' boxes, the
-- launcher's entries and the verbs all read and write through these names, so the three agree.

function NS.IsTestMode()
    return NS.Preview.Mode() == "test"
end

--- The Test mode row's own set: start or stop test mode.
function NS.SetTestMode(on)
    if on then NS.Preview.Start({ mode = "test" }) else NS.Preview.Stop() end
end

--- `/ct test` and the launcher's Test mode entry: through the row's write seam, so the box follows.
function NS.ToggleTestMode()
    if refused() then return false end
    return NS.SetByPath("general.testMode", not NS.IsTestMode())
end

--- Whether Sim mode reads on: the sim's step window shown or a sim running (modules/Sim.lua).
function NS.IsSimMode()
    return NS.Sim.IsOn()
end

--- The launcher's Sim mode entry and the Master controls' Sim mode box: the one act.
function NS.ToggleSim()
    if refused() then return false end
    return NS.Sim.Toggle()
end

--- `/ct sim [line]`: the library's sim grammar (modules/Sim.lua Sim.RunVerb).
function NS.RunSimVerb(line)
    if refused() then return false end
    return NS.Sim.RunVerb(line)
end
