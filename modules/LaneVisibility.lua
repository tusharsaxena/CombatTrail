local _, NS = ...
-- modules/LaneVisibility.lua — when each lane shows, and how opaque it is (spec §4 Visibility):
-- `visibility.show` (always, combat, combatOrTarget, never), the hide-after-combat window, where
-- (open world, dungeons, raids, delves, battlegrounds, arenas), the mounted, vehicle, pet battle and
-- resting hides, and the in- and out-of-combat opacity. modules/LaneRender.lua asks Decide(laneKey)
-- on every Apply and shows or hides the lane frame; this file never draws.
--
-- PURE AT THE CORE. ShouldShow(laneKey, ctx) and Alpha(laneKey, ctx) read only the lane's settings
-- and the context table ctx = { inCombat, hasTarget, instanceType, isDelve, mounted, inVehicle,
-- petBattle, resting, secondsSinceCombat }, which Context() reads off the client (each answer read
-- through NS.Secrets, so a secret never meets a test). A `where` key that is absent (delve and
-- arena on WoW Forever, clients-§4) never hides; only false does.
--
-- AN UNLOCKED LANE ALWAYS SHOWS, at full opacity (modules/LaneAnchor.lua IsUnlocked): the player
-- has to see a lane to move it.
-- So does every lane while test mode or the sim is on (modules/Preview.lua): they play their sample
-- casts there.
--
-- EVENTS ONLY WHILE A RULE IS USED (performance). Each rule names the events that can change its
-- answer, and the frame is registered for a rule's events only while some lane switched on, and not
-- set to "never", uses it: PLAYER_REGEN_* for a combat show mode or a combat opacity that differs,
-- PLAYER_TARGET_CHANGED for combatOrTarget, ZONE_CHANGED_NEW_AREA and PLAYER_ENTERING_WORLD for a
-- where key switched off, PLAYER_MOUNT_DISPLAY_CHANGED, UNIT_ENTERED/EXITED_VEHICLE (the player),
-- PET_BATTLE_OPENING_START/CLOSE and PLAYER_UPDATE_RESTING for their hides. UNIT_PET (the player's)
-- is registered while the Pet lane is on: a new, changed or dismissed pet re-applies that lane, so
-- its label names the pet (modules/LaneRender.lua). Sync() rebuilds the set on login, on every
-- SETTINGS_CHANGED for a lane's switch or visibility and on a profile change, and at stand-up.
--
-- THE HIDE-AFTER WINDOW. PLAYER_REGEN_ENABLED notes the time and schedules one AceTimer per lane
-- that uses a combat show mode with hideAfter > 0, a beat after the window closes, to re-decide.
-- PLAYER_REGEN_DISABLED cancels them. A cast that pulls combat before PLAYER_REGEN_DISABLED still
-- shows a combat lane, because Context() also asks UnitAffectingCombat.
--
-- Stand-down (core/LifecycleSetup.lua) calls Suspend: every registration and timer goes. Resume
-- rebuilds from the CURRENT settings.

local LaneVisibility = {}
NS.LaneVisibility = LaneVisibility

local Secrets = NS.Secrets

local LANES = { "player", "pet" }
local IS_LANE = { player = true, pet = true }
local SHOW_MODES = { always = true, combat = true, combatOrTarget = true, never = true }
-- IsInInstance's type -> the `where` key. A scenario outside a delve is the open world.
local WHERE = { none = "world", party = "dungeon", raid = "raid", pvp = "bg", arena = "arena",
                scenario = "world" }
-- The hides: the setting, and the context field that triggers it.
local HIDES = { { "hideMounted", "mounted" }, { "hideVehicle", "inVehicle" },
                { "hidePetBattle", "petBattle" }, { "hideResting", "resting" } }
-- A beat after the hide-after window closes, so the re-decision lands outside it.
local HIDE_SLACK = 0.1

local frame             -- the event frame (nil until something registers)
local registered        -- the registered set as a string key ("" = nothing), nil = unknown
local combat = false    -- between PLAYER_REGEN_DISABLED and PLAYER_REGEN_ENABLED
local lastCombatEnd     -- GetTime() at the last PLAYER_REGEN_ENABLED
local timers = {}       -- the hide-after AceTimer handles

-- Through modules/LaneRender.lua's resolver: a linked Pet lane shows when the Player lane's
-- Visibility says (LaneRender.Config, LINK_OWN).
local function cfgOf(laneKey)
    local R = NS.LaneRender
    if R and R.Config then return R.Config(laneKey) end
    local db = NS.db
    local all = db and db.profile and db.profile.lanes
    return all and all[laneKey]
end

local function visOf(laneKey)
    local cfg = cfgOf(laneKey)
    local v = cfg and cfg.visibility
    return type(v) == "table" and v or nil
end

local function laneOn(laneKey)
    local cfg = cfgOf(laneKey)
    return cfg ~= nil and cfg.enabled ~= false and not NS.IsStoodDown()
end

local function num(v, default)
    if type(v) == "number" and v == v then return v end
    return default
end

local function showMode(v)
    return SHOW_MODES[v.show] and v.show or "always"
end

-- ── the decision ───────────────────────────────────────────────────────────────────────────────

--- The `where` key a context is in.
--- @param ctx table
--- @return string
function LaneVisibility.WhereKey(ctx)
    if ctx.isDelve then return "delve" end
    return WHERE[ctx.instanceType] or "world"
end

local function modeAllows(v, ctx)
    local mode = showMode(v)
    if mode == "never" then return false end
    if mode == "always" or ctx.inCombat then return true end
    if mode == "combatOrTarget" and ctx.hasTarget then return true end
    return num(ctx.secondsSinceCombat, math.huge) < math.max(0, num(v.hideAfter, 0))
end

--- Whether a lane's rules show it in context `ctx` (the lane's own switch aside).
--- @param laneKey string
--- @param ctx table
--- @return boolean
function LaneVisibility.ShouldShow(laneKey, ctx)
    local v = visOf(laneKey)
    if not v then return true end
    ctx = ctx or {}
    if not modeAllows(v, ctx) then return false end
    if type(v.where) == "table" and v.where[LaneVisibility.WhereKey(ctx)] == false then return false end
    for _, h in ipairs(HIDES) do
        if v[h[1]] == true and ctx[h[2]] then return false end
    end
    return true
end

--- A lane's opacity in context `ctx`, 0..1.
--- @param laneKey string
--- @param ctx table
--- @return number
function LaneVisibility.Alpha(laneKey, ctx)
    local v = visOf(laneKey)
    if not v then return 1 end
    local a = (ctx and ctx.inCombat) and v.alphaCombat or v.alphaOOC
    return math.min(1, math.max(0, num(a, 1)))
end

local function truth(fn, ...)
    if type(fn) ~= "function" then return false end
    return Secrets.PlainTruth(fn(...))
end

--- The client's answers ShouldShow and Alpha read.
--- @return table ctx
function LaneVisibility.Context()
    local _, instanceType = IsInInstance()
    return {
        inCombat           = combat or truth(UnitAffectingCombat, "player"),
        hasTarget          = truth(UnitExists, "target"),
        instanceType       = Secrets.PlainString(instanceType) or "none",
        isDelve            = NS.Compat.InDelve(),
        mounted            = truth(IsMounted),
        inVehicle          = NS.Compat.InVehicle(),
        petBattle          = NS.Compat.InPetBattle(),
        resting            = truth(IsResting),
        secondsSinceCombat = lastCombatEnd and (GetTime() - lastCombatEnd) or math.huge,
    }
end

--- Whether a lane shows now, and its opacity: what modules/LaneRender.lua applies.
--- @param laneKey string
--- @return boolean shown, number alpha
function LaneVisibility.Decide(laneKey)
    local anchor = NS.LaneAnchor
    if anchor and anchor.IsUnlocked() then return true, 1 end
    -- Test mode and the sim play their sample casts on the lanes, so a lane shows while either is on.
    local preview = NS.Preview
    if preview and preview.IsActive() then return true, 1 end
    local v = visOf(laneKey)
    if v and showMode(v) == "never" then return false, 1 end
    local ctx = LaneVisibility.Context()
    return LaneVisibility.ShouldShow(laneKey, ctx), LaneVisibility.Alpha(laneKey, ctx)
end

--- Every lane re-decides and its frame follows.
function LaneVisibility.Refresh()
    local R = NS.LaneRender
    if not R then return end
    for _, laneKey in ipairs(LANES) do R.ApplyVisibility(laneKey) end
end

-- ── the hide-after timers ──────────────────────────────────────────────────────────────────────

local function cancelTimers()
    local addon = NS.addon
    for _, h in ipairs(timers) do
        if addon and addon.CancelTimer then addon:CancelTimer(h) end
    end
    timers = {}
end

local function onWindowClosed()
    if not NS.IsStoodDown() then LaneVisibility.Refresh() end
end

local function scheduleHides()
    cancelTimers()
    local addon = NS.addon
    if not (addon and addon.ScheduleTimer) then return end
    for _, laneKey in ipairs(LANES) do
        local v = visOf(laneKey)
        local after = v and num(v.hideAfter, 0) or 0
        local mode = v and showMode(v)
        if laneOn(laneKey) and after > 0 and (mode == "combat" or mode == "combatOrTarget") then
            timers[#timers + 1] = addon:ScheduleTimer(onWindowClosed, after + HIDE_SLACK)
        end
    end
end

-- ── registration ───────────────────────────────────────────────────────────────────────────────

local function anyWhereOff(v)
    if type(v.where) ~= "table" then return false end
    for _, on in pairs(v.where) do
        if on == false then return true end
    end
    return false
end

local function usesCombat(v)
    local mode = showMode(v)
    return mode == "combat" or mode == "combatOrTarget" or num(v.alphaCombat, 1) ~= num(v.alphaOOC, 1)
end

-- Each rule: the events it needs (`unit` = registered for the player only) and whether a lane uses it.
local RULES = {
    { events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }, uses = usesCombat },
    { events = { "PLAYER_TARGET_CHANGED" }, uses = function(v) return showMode(v) == "combatOrTarget" end },
    { events = { "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }, uses = anyWhereOff },
    { events = { "PLAYER_MOUNT_DISPLAY_CHANGED" }, uses = function(v) return v.hideMounted == true end },
    { events = { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }, unit = true,
      uses = function(v) return v.hideVehicle == true end },
    { events = { "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE" },
      uses = function(v) return v.hidePetBattle == true end },
    { events = { "PLAYER_UPDATE_RESTING" }, uses = function(v) return v.hideResting == true end },
}

-- The rules one lane uses, into `want` ([event] = "unit" | "frame").
local function addLane(want, v)
    if showMode(v) == "never" then return end
    for _, rule in ipairs(RULES) do
        if rule.uses(v) then
            for _, event in ipairs(rule.events) do want[event] = rule.unit and "unit" or "frame" end
        end
    end
end

local function wanted()
    local want = {}
    if not NS.db or NS.IsStoodDown() then return want end
    for _, laneKey in ipairs(LANES) do
        local v = visOf(laneKey)
        if v and laneOn(laneKey) then addLane(want, v) end
    end
    if laneOn("pet") then want.UNIT_PET = "unit" end
    return want
end

local function keyOf(want)
    local names = {}
    for event in pairs(want) do names[#names + 1] = event end
    table.sort(names)
    return table.concat(names, ","), names
end

local HANDLERS = {
    PLAYER_REGEN_DISABLED = function()
        combat = true
        cancelTimers()
    end,
    PLAYER_REGEN_ENABLED = function()
        combat = false
        lastCombatEnd = GetTime()
        scheduleHides()
    end,
}

local function onEvent(_, event)
    if NS.IsStoodDown() then return end
    if event == "UNIT_PET" then
        if NS.LaneRender then NS.LaneRender.Apply("pet") end
        return
    end
    local h = HANDLERS[event]
    if h then h() end
    LaneVisibility.Refresh()
end

local function ensureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", onEvent)
    return frame
end

--- Make the registrations match the current settings. Cheap when they already do.
function LaneVisibility.Sync()
    local want = wanted()
    local key, names = keyOf(want)
    if key == registered then return end
    -- Whatever the combat flag held while its events were not heard is stale: read it fresh.
    combat = truth(UnitAffectingCombat, "player")
    if frame then frame:UnregisterAllEvents() end
    registered = key
    if #names == 0 then return end
    local f = ensureFrame()
    for _, event in ipairs(names) do
        if want[event] == "unit" then
            NS.SafeRegisterUnitEvent(f, event, NS.rejectedEvents, "player")
        else
            NS.SafeRegisterEvent(f, event, nil, NS.rejectedEvents)
        end
    end
end

--- The lifecycle's stand-down: no registration, no timer.
function LaneVisibility.Suspend()
    if frame then frame:UnregisterAllEvents() end
    registered = ""
    cancelTimers()
    combat, lastCombatEnd = false, nil
end

--- The lifecycle's stand-up: rebuilt from the CURRENT settings.
function LaneVisibility.Resume()
    registered = nil
    LaneVisibility.Sync()
    LaneVisibility.Refresh()
end

--- The event frame (nil until something registered), for the suites.
function LaneVisibility.Frame()
    return frame
end

-- ── the bus ────────────────────────────────────────────────────────────────────────────────────

local function onSettingsChanged(_, path)
    if type(path) ~= "string" then return end
    local laneKey, rest = path:match("^lanes%.([^.]+)%.(.+)$")
    local relevant = path == "profile"
        or (IS_LANE[laneKey] and (rest == "enabled" or rest == "link" or rest == "visibility"
            or rest:match("^visibility%.") ~= nil))
    if not relevant then return end
    LaneVisibility.Sync()
    LaneVisibility.Refresh()
end

local busTarget = NS.NewBusTarget()
if busTarget then busTarget:RegisterMessage(NS.MSG.SETTINGS_CHANGED, onSettingsChanged) end
