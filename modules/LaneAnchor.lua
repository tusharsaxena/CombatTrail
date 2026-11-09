local _, NS = ...
-- modules/LaneAnchor.lua — where each lane sits (spec §4 Anchoring and Layering): its point, its
-- strata and its level, and the edit overlay a player drags it by. modules/LaneRender.lua calls
-- LaneAnchor.Apply(laneKey) from every Apply of a lane; this file never draws an icon.
--
-- THREE MODES per lane, `anchor.mode`:
--   * "free": anchor.point on UIParent's anchor.relPoint at anchor.x, anchor.y. A lane that cannot
--     reach its host in the other two modes falls back to x, y from the screen's CENTER: its point
--     and relPoint there are the dock's (TOP under BOTTOM), and on UIParent they would put the lane
--     off the bottom of the screen.
--   * "dock": on the other lane (anchor.target), anchor.point to its anchor.relPoint, `gap` pixels
--     apart on the axis the two points face across (TOP under BOTTOM: down; LEFT beside RIGHT:
--     right). A dock to itself, to a lane switched off, or to a lane docked back to this one (the
--     cycle) is refused; the cycle prints one line until it is broken.
--   * "unit": on the lane's unit frame, the first of UNIT_FRAMES[laneKey] that exists and is not
--     forbidden (ElvUI, Shadowed Unit Frames, Cell, PitBull4, UnhaltedUnitFrames, then Blizzard's),
--     or the global frame anchor.frameName names when it is set. Placed by point, relPoint and gap
--     as a dock is. A missing or forbidden frame falls back to free and prints one line, held until
--     PLAYER_ENTERING_WORLD at login because a unit frame addon may build its frames late; that
--     event looks for every unit-mode lane's frame again.
--
-- THE STRATA AND LEVEL (frame-layering-§1 host-matched surfaces, §3). `strata` "HOST" reads the
-- host's strata and level (GetFrameStrata and GetFrameLevel, each in pcall and through NS.Secrets: a
-- secret or unreadable answer is never used) and puts the lane at host level + LEVEL.LANE +
-- levelOffset. Any other strata is the lane's own (an unknown one reads as LAYERS.STRATA.LANE), at
-- its parent's level + LEVEL.LANE + levelOffset. Switching a lane INTO unit-frame mode turns a
-- default "LOW" into "HOST" (spec §4: unit-frame mode matches its host by default), and switching
-- out turns "HOST" back into "LOW"; a strata the player picks afterwards stands. The same edge
-- moves a CENTER-to-CENTER point (the free default) to TOP under BOTTOM, so a lane leaving free mode
-- sits under its host and not over its middle, and the edge back INTO free mode moves a TOP under
-- BOTTOM point (the dock default) back to CENTER-to-CENTER, so the lane lands on the screen.
--
-- THE EDIT OVERLAY (frame-layering-§2): one mouse-live box per lane, shown while Blizzard's Edit
-- Mode is open (EventRegistry "EditMode.Enter"/"EditMode.Exit") and the Locked row is off, or after
-- `/kct unlock` (NS.Lanes.SetLocked, from the Locked row's reaction) until `/kct lock`. It is chrome:
-- floored at LAYERS.STRATA.CHROME over a lower lane, fixed and re-lifted after every strata the lane
-- takes, at lane level + LEVEL.LANE_EDIT over the whole icon band, and blind to the lane's alpha. An
-- unlocked lane shows whatever its visibility rules say (modules/LaneVisibility.lua asks
-- IsUnlocked). Dragging a lane that sits at its free place saves anchor.point/relPoint "CENTER" and
-- the x, y it was dropped at (a lane at its fallback place saves only x, y: its point is the dock's);
-- a docked or unit-frame lane moves with its host and is not dragged.
--
-- WRITES go through the settings seam when a schema row holds the path (settings/Lanes.lua, plan
-- Task 1.4), and otherwise straight to the profile with the same SETTINGS_CHANGED announcement.
--
-- Stand-down (core/LifecycleSetup.lua) calls Suspend: the Edit Mode callbacks and the event frame's
-- registration go, every overlay hides, and the unlock is dropped. Resume rebuilds from the CURRENT
-- settings, locked.

local LaneAnchor = {}
NS.LaneAnchor = LaneAnchor

-- The placed-frame contract core/CombatTrail.lua's NS.ApplyLocked and NS.ResetPositions call
-- (SetLocked, ResetPosition). settings/Lanes.lua (plan Task 1.4) adds OnVerb, the `lane` verb.
NS.Lanes = NS.Lanes or {}
local Lanes = NS.Lanes

local Secrets = NS.Secrets
local LAYERS = NS.Constants.LAYERS
local L = NS.L

--- The unit frames a lane in "unit" mode looks for, in order: ElvUI, Shadowed Unit Frames, Cell,
--- PitBull4, UnhaltedUnitFrames, then Blizzard's own. PitBull4 names a frame after its layout entry,
--- whose default for the pet is "Player's pet".
LaneAnchor.UNIT_FRAMES = {
    player = { "ElvUF_Player", "SUFUnitplayer", "CellSoloFramePlayer", "PitBull4_Frames_Player",
               "UUF_Player", "PlayerFrame" },
    pet    = { "ElvUF_Pet", "SUFUnitpet", "CellSoloFramePet", "PitBull4_Frames_Player's pet",
               "UUF_Pet", "PetFrame" },
}

local LANES = { "player", "pet" }
local IS_LANE = { player = true, pet = true }
local LANE_NAMES = { player = L["Player lane"], pet = L["Pet lane"] }
local STRATA_OK = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true }
local STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
                      FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local LEVEL_OFFSET_MAX = 50
local EDGE = 1
local NONE = { 0, 0, 0, 0 }

local state = { editMode = false, unlocked = false, worldSeen = false, callbacks = false }
local overlays = {}   -- [laneKey] = the edit overlay frame
local notified = {}   -- [laneKey] = the reason last printed; .cycle = the cycle was printed
local dragging = {}   -- [laneKey] = true while the player drags that lane
local eventFrame      -- PLAYER_ENTERING_WORLD, until the world is first entered

local function cfgOf(laneKey)
    local db = NS.db
    local all = db and db.profile and db.profile.lanes
    return all and all[laneKey]
end

local function laneOn(laneKey)
    local cfg = cfgOf(laneKey)
    return cfg ~= nil and cfg.enabled ~= false and not NS.IsStoodDown()
end

local function num(v, default)
    if type(v) == "number" and v == v then return v end
    return default
end

-- ── writes ─────────────────────────────────────────────────────────────────────────────────────

-- One lane setting, `key` relative to the lane ("anchor.x"), through the seam when a row holds it.
local function write(laneKey, key, value)
    local path = "lanes." .. laneKey .. "." .. key
    if NS.FindSchemaRow and NS.FindSchemaRow(path) then return NS.SetByPath(path, value) end
    local t = cfgOf(laneKey)
    if not t then return end
    local parts = {}
    for part in key:gmatch("[^.]+") do parts[#parts + 1] = part end
    for i = 1, #parts - 1 do t = t[parts[i]] end
    t[parts[#parts]] = value
    NS.AnnounceSettingsChanged(path, value)
end

-- ── the host ───────────────────────────────────────────────────────────────────────────────────

-- The global frame `name`, or nil and why: "missing" or "forbidden".
local function lookup(name, own)
    local f = _G[name]
    if type(f) ~= "table" or f == own then return nil, "missing" end
    if type(f.IsForbidden) == "function" then
        local ok, forbidden = pcall(f.IsForbidden, f)
        if not ok or Secrets.PlainEquals(forbidden, true) or Secrets.IsSealed(forbidden) then return nil, "forbidden" end
    end
    return f
end

local function dockHost(laneKey, a)
    local target = a.target
    if target == laneKey or not IS_LANE[target] then return nil, "self" end
    if not laneOn(target) then return nil, "off" end
    local oa = cfgOf(target).anchor
    if type(oa) == "table" and oa.mode == "dock" and oa.target == laneKey then return nil, "cycle" end
    return NS.LaneRender.Get(target), "dock"
end

local function unitHost(laneKey, a)
    local own = NS.LaneRender.Get(laneKey)
    local typed = Secrets.PlainString(a.frameName)
    if typed and typed ~= "" then
        local f, why = lookup(typed, own)
        if f then return f, typed end
        return nil, why, typed
    end
    local why = "missing"
    for _, name in ipairs(LaneAnchor.UNIT_FRAMES[laneKey] or {}) do
        local f, reason = lookup(name, own)
        if f then return f, name end
        if reason == "forbidden" then why = reason end
    end
    local list = LaneAnchor.UNIT_FRAMES[laneKey] or {}
    return nil, why, list[#list]
end

--- The frame a lane sits on, and why: (host, "dock") on the other lane, (host, frameName) on a unit
--- frame, or (nil, reason[, frameName]) at its free place, reason "free", "self", "off", "cycle",
--- "missing" or "forbidden".
--- @param laneKey string
--- @return table|nil host, string reason, string|nil frameName
function LaneAnchor.ResolveHost(laneKey)
    local cfg = cfgOf(laneKey)
    local a = cfg and cfg.anchor
    if type(a) ~= "table" then return nil, "free" end
    if a.mode == "dock" then return dockHost(laneKey, a) end
    if a.mode == "unit" then return unitHost(laneKey, a) end
    return nil, "free"
end

-- ── the one-line notices ───────────────────────────────────────────────────────────────────────

local function cycleNow()
    local p, q = cfgOf("player"), cfgOf("pet")
    local pa, qa = p and p.anchor, q and q.anchor
    return type(pa) == "table" and type(qa) == "table" and pa.mode == "dock" and qa.mode == "dock"
        and pa.target == "pet" and qa.target == "player"
end

local function say(line)
    NS.Print(line)
    if NS.Debug then NS.Debug("Lanes", "%s", line) end
end

local function noticeFor(laneKey, host, reason, frameName)
    if not cycleNow() then notified.cycle = nil end
    if host or reason == "free" or reason == "self" or reason == "off" then
        notified[laneKey] = nil
        return
    end
    if reason == "cycle" then
        if notified.cycle then return end
        notified.cycle = true
        return say(L["The Player and Pet lanes are docked to each other, so neither can dock. Both sit at their own place until one is undocked."])
    end
    -- At login a unit frame addon may not have built its frames yet: PLAYER_ENTERING_WORLD looks again.
    if not state.worldSeen or notified[laneKey] == reason then return end
    notified[laneKey] = reason
    local text = reason == "forbidden" and L["The %s cannot use the unit frame %s, so it sits at its own place."]
        or L["The %s cannot find its unit frame (%s), so it sits at its own place."]
    say(text:format(LANE_NAMES[laneKey], tostring(frameName)))
end

-- ── the layer and the point ────────────────────────────────────────────────────────────────────

-- The host's strata and level, or nil when either is secret, unreadable or not a strata.
local function hostLayer(host)
    local okS, s = pcall(host.GetFrameStrata, host)
    local okL, l = pcall(host.GetFrameLevel, host)
    local strata = okS and Secrets.PlainString(s) or nil
    local level = okL and Secrets.PlainNumber(l) or nil
    if not (strata and STRATA_RANK[strata] and level) then return nil end
    return strata, level
end

local function parentLevel(frame)
    local parent = frame:GetParent() or UIParent
    return parent:GetFrameLevel()
end

-- The overlay over its lane: the lane's strata floored at CHROME, fixed, and over the icon band.
local function liftOverlay(laneKey)
    local ov, lane = overlays[laneKey], NS.LaneRender.Get(laneKey)
    if not ov then return end
    local strata = lane:GetFrameStrata()
    local floor = LAYERS.STRATA.CHROME
    if (STRATA_RANK[strata] or 0) < STRATA_RANK[floor] then strata = floor end
    ov:SetFixedFrameStrata(false)
    ov:SetFrameStrata(strata)
    ov:SetFixedFrameStrata(true)
    ov:SetFrameLevel(lane:GetFrameLevel() + LAYERS.LEVEL.LANE_EDIT)
end

local function applyLayer(laneKey, frame, cfg, host)
    local strata, base
    if cfg.strata == "HOST" and host then strata, base = hostLayer(host) end
    if not strata then
        strata = STRATA_OK[cfg.strata] and cfg.strata or LAYERS.STRATA.LANE
        base = parentLevel(frame)
    end
    frame:SetFrameStrata(strata)
    local offset = math.floor(math.min(LEVEL_OFFSET_MAX, math.max(0, num(cfg.levelOffset, 0))))
    frame:SetFrameLevel(base + LAYERS.LEVEL.LANE + offset)
    liftOverlay(laneKey)
end

-- The gap, on the axis the two points face across: dx, dy.
local function gapOffset(point, relPoint, gap)
    if relPoint:find("BOTTOM") and point:find("TOP") then return 0, -gap end
    if relPoint:find("TOP") and point:find("BOTTOM") then return 0, gap end
    if relPoint:find("RIGHT") and point:find("LEFT") then return gap, 0 end
    if relPoint:find("LEFT") and point:find("RIGHT") then return -gap, 0 end
    return 0, 0
end

-- A lane in dock or unit mode that found no host sits at its fallback place.
local function isFallback(a)
    return a.mode == "dock" or a.mode == "unit"
end

local function place(frame, cfg, host)
    local a = type(cfg.anchor) == "table" and cfg.anchor or {}
    frame:ClearAllPoints()
    if host then
        local point, relPoint = a.point or "TOP", a.relPoint or "BOTTOM"
        local dx, dy = gapOffset(point, relPoint, math.max(0, num(a.gap, 0)))
        frame:SetPoint(point, host, relPoint, dx, dy)
    elseif isFallback(a) then
        frame:SetPoint("CENTER", UIParent, "CENTER", num(a.x, 0), num(a.y, 0))
    else
        frame:SetPoint(a.point or "CENTER", UIParent, a.relPoint or "CENTER", num(a.x, 0), num(a.y, 0))
    end
end

-- ── the edit overlay ───────────────────────────────────────────────────────────────────────────

--- Whether the lanes show their edit overlay now: after `/kct unlock`, or in Edit Mode while the
--- Locked row is off. Never while stood down.
--- @return boolean
function LaneAnchor.IsUnlocked()
    if NS.IsStoodDown() then return false end
    if state.unlocked then return true end
    return state.editMode and NS.GetSetting("general.locked") ~= true
end

local function laneCenter(lane)
    local cx, cy = lane:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and ux) then return nil end
    local ratio = UIParent:GetEffectiveScale() / lane:GetEffectiveScale()
    return math.floor(cx - ux * ratio + 0.5), math.floor(cy - uy * ratio + 0.5)
end

local function dragStart(laneKey)
    if not LaneAnchor.IsUnlocked() or LaneAnchor.ResolveHost(laneKey) then return end
    local lane = NS.LaneRender.Get(laneKey)
    lane:SetMovable(true)
    lane:StartMoving()
    dragging[laneKey] = true
end

local function dragStop(laneKey)
    if not dragging[laneKey] then return end
    dragging[laneKey] = nil
    local lane = NS.LaneRender.Get(laneKey)
    lane:StopMovingOrSizing()
    -- StartMoving marked the named lane user-placed; the client's layout cache must not restore it
    -- over the saved anchor at the next login.
    lane:SetUserPlaced(false)
    local x, y = laneCenter(lane)
    if not x then return end
    local a = cfgOf(laneKey).anchor
    if not (type(a) == "table" and isFallback(a)) then
        write(laneKey, "anchor.point", "CENTER")
        write(laneKey, "anchor.relPoint", "CENTER")
    end
    write(laneKey, "anchor.x", x)
    write(laneKey, "anchor.y", y)
end

local EDGE_POINTS = {
    { "TOPLEFT", "TOPRIGHT", "height" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "height" },
    { "TOPLEFT", "BOTTOMLEFT", "width" }, { "TOPRIGHT", "BOTTOMRIGHT", "width" },
}

local function buildOverlay(laneKey)
    local lane = NS.LaneRender.Get(laneKey)
    local ov = CreateFrame("Frame", nil, lane)
    ov:Hide()
    ov:SetAllPoints(lane)
    ov:EnableMouse(true)
    ov:RegisterForDrag("LeftButton")
    ov:SetIgnoreParentAlpha(true)
    ov.bg = ov:CreateTexture(nil, "BACKGROUND")
    ov.bg:SetAllPoints(ov)
    ov.edges = {}
    for i, p in ipairs(EDGE_POINTS) do
        local t = ov:CreateTexture(nil, "BORDER")
        t:SetPoint(p[1], ov, p[1], 0, 0)
        t:SetPoint(p[2], ov, p[2], 0, 0)
        if p[3] == "height" then t:SetHeight(EDGE) else t:SetWidth(EDGE) end
        ov.edges[i] = t
    end
    ov.text = ov:CreateFontString(nil, "OVERLAY")
    ov.text:SetPoint("CENTER", ov, "CENTER", 0, 0)
    ov:SetScript("OnDragStart", function() dragStart(laneKey) end)
    ov:SetScript("OnDragStop", function() dragStop(laneKey) end)
    overlays[laneKey] = ov
    return ov
end

local function tint(name)
    local r, g, b, a = NS.SkinColor(name)
    if r == nil then return NONE[1], NONE[2], NONE[3], NONE[4] end
    return r, g, b, a or 1
end

local function overlayText(laneKey)
    local host, reason = LaneAnchor.ResolveHost(laneKey)
    local name = LANE_NAMES[laneKey]
    if host and reason == "dock" then return L["%s: docked, so it moves with the lane it follows"]:format(name) end
    if host then return L["%s: on its unit frame, so it moves with that frame"]:format(name) end
    return L["%s: drag to move"]:format(name)
end

local function paintOverlay(laneKey)
    local ov = overlays[laneKey]
    ov.bg:SetColorTexture(tint("ct.lane.edit.bg"))
    for _, t in ipairs(ov.edges) do t:SetColorTexture(tint("ct.lane.edit.border")) end
    local face = NS.Skin and NS.Skin.GetFont and NS.Skin.GetFont()
    if type(face) ~= "string" or face == "" then face = STANDARD_TEXT_FONT end
    ov.text:SetFont(face, 11, "OUTLINE")
    ov.text:SetTextColor(tint("ct.lane.edit.text"))
    ov.text:SetText(overlayText(laneKey))
end

local function refreshOverlay(laneKey)
    local ov = overlays[laneKey]
    if not (LaneAnchor.IsUnlocked() and laneOn(laneKey)) then
        -- A drag the overlay's hide cut short still lands (Edit Mode closed under the cursor).
        if dragging[laneKey] then dragStop(laneKey) end
        if ov then ov:Hide() end
        return
    end
    if not ov then buildOverlay(laneKey) end
    paintOverlay(laneKey)
    liftOverlay(laneKey)
    overlays[laneKey]:Show()
end

-- The lanes re-decide whether they show (an unlocked lane always does), and the overlays follow.
local function refreshAll()
    if NS.LaneVisibility then NS.LaneVisibility.Refresh() end
    for _, laneKey in ipairs(LANES) do refreshOverlay(laneKey) end
end

--- Show or hide the edit overlay outside Edit Mode (`/kct unlock`, `/kct lock`).
--- @param on boolean
function LaneAnchor.SetUnlocked(on)
    state.unlocked = on == true
    refreshAll()
end

--- The Locked row's reaction (core/CombatTrail.lua NS.ApplyLocked).
function Lanes.SetLocked(locked)
    LaneAnchor.SetUnlocked(locked ~= true)
end

--- Master controls' Reset position (core/CombatTrail.lua NS.ResetPositions): each lane's anchor
--- back to its default.
function Lanes.ResetPosition()
    local defaults = NS.defaults.profile.lanes
    for _, laneKey in ipairs(LANES) do
        local d = defaults[laneKey].anchor
        local keys = {}
        for key in pairs(d) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do write(laneKey, "anchor." .. key, d[key]) end
    end
end

-- ── apply ──────────────────────────────────────────────────────────────────────────────────────

--- Place one lane: its host, its strata and level, its point, and its overlay. Called by
--- modules/LaneRender.lua's Apply.
--- @param laneKey string
function LaneAnchor.Apply(laneKey)
    local cfg = cfgOf(laneKey)
    if not cfg then return end
    local frame = NS.LaneRender.Get(laneKey)
    local host, reason, frameName = LaneAnchor.ResolveHost(laneKey)
    noticeFor(laneKey, host, reason, frameName)
    applyLayer(laneKey, frame, cfg, host)
    place(frame, cfg, host)
    refreshOverlay(laneKey)
end

-- ── registration ───────────────────────────────────────────────────────────────────────────────

local function onEditEnter()
    state.editMode = true
    refreshAll()
end

local function onEditExit()
    state.editMode = false
    refreshAll()
end

local function registerCallbacks()
    local reg = EventRegistry
    if state.callbacks or type(reg) ~= "table" or type(reg.RegisterCallback) ~= "function" then return end
    reg:RegisterCallback("EditMode.Enter", onEditEnter, LaneAnchor)
    reg:RegisterCallback("EditMode.Exit", onEditExit, LaneAnchor)
    state.callbacks = true
end

local function unregisterCallbacks()
    local reg = EventRegistry
    if not state.callbacks then return end
    if type(reg) == "table" and type(reg.UnregisterCallback) == "function" then
        reg:UnregisterCallback("EditMode.Enter", LaneAnchor)
        reg:UnregisterCallback("EditMode.Exit", LaneAnchor)
    end
    state.callbacks = false
end

-- The first PLAYER_ENTERING_WORLD: every unit-mode lane looks for its frame again, and from then on a
-- missing one is said.
local function onEvent(_, event)
    if event ~= "PLAYER_ENTERING_WORLD" or NS.IsStoodDown() then return end
    state.worldSeen = true
    eventFrame:UnregisterAllEvents()
    for _, laneKey in ipairs(LANES) do
        local cfg = cfgOf(laneKey)
        if laneOn(laneKey) and type(cfg.anchor) == "table" and cfg.anchor.mode == "unit" then
            NS.LaneRender.Apply(laneKey)
        end
    end
end

local function anyLaneOn()
    for _, laneKey in ipairs(LANES) do
        if laneOn(laneKey) then return true end
    end
    return false
end

--- Make the registrations match the current settings: the Edit Mode callbacks while a lane is on,
--- and PLAYER_ENTERING_WORLD until the world is first entered.
function LaneAnchor.Sync()
    if not NS.db or not anyLaneOn() then
        unregisterCallbacks()
        if eventFrame then eventFrame:UnregisterAllEvents() end
        return
    end
    registerCallbacks()
    if not state.worldSeen then
        if not eventFrame then
            eventFrame = CreateFrame("Frame")
            eventFrame:SetScript("OnEvent", onEvent)
        end
        NS.SafeRegisterEvent(eventFrame, "PLAYER_ENTERING_WORLD", nil, NS.rejectedEvents)
    end
end

--- The lifecycle's stand-down: no callback, no event, no overlay, no unlock.
function LaneAnchor.Suspend()
    unregisterCallbacks()
    if eventFrame then eventFrame:UnregisterAllEvents() end
    state.editMode, state.unlocked = false, false
    for laneKey in pairs(dragging) do NS.LaneRender.Get(laneKey):StopMovingOrSizing() end
    dragging = {}
    for _, ov in pairs(overlays) do ov:Hide() end
end

--- The lifecycle's stand-up: rebuilt from the CURRENT settings.
function LaneAnchor.Resume()
    LaneAnchor.Sync()
end

-- ── the bus ────────────────────────────────────────────────────────────────────────────────────

-- The edge into or out of unit-frame mode: the strata default and the point (see the header).
local function onModeChanged(laneKey)
    local cfg = cfgOf(laneKey)
    local a = cfg and cfg.anchor
    if type(a) ~= "table" then return end
    if a.mode == "unit" and cfg.strata == LAYERS.STRATA.LANE then
        write(laneKey, "strata", "HOST")
    elseif a.mode ~= "unit" and cfg.strata == "HOST" then
        write(laneKey, "strata", LAYERS.STRATA.LANE)
    end
    if a.mode ~= "free" and a.point == "CENTER" and a.relPoint == "CENTER" then
        write(laneKey, "anchor.point", "TOP")
        write(laneKey, "anchor.relPoint", "BOTTOM")
    elseif a.mode == "free" and a.point == "TOP" and a.relPoint == "BOTTOM" then
        write(laneKey, "anchor.point", "CENTER")
        write(laneKey, "anchor.relPoint", "CENTER")
    end
end

local function onSettingsChanged(_, path)
    if type(path) ~= "string" then return end
    if path == "profile" then return LaneAnchor.Sync() end
    local laneKey, rest = path:match("^lanes%.([^.]+)%.(.+)$")
    if not IS_LANE[laneKey] then return end
    if rest == "anchor.mode" or rest == "anchor" then onModeChanged(laneKey) end
    if rest == "enabled" then LaneAnchor.Sync() end
end

local busTarget = NS.NewBusTarget()
if busTarget then busTarget:RegisterMessage(NS.MSG.SETTINGS_CHANGED, onSettingsChanged) end

-- ── for the suites ─────────────────────────────────────────────────────────────────────────────

--- The lane's edit overlay, built hidden on first ask.
function LaneAnchor.__overlay(laneKey)
    return overlays[laneKey] or buildOverlay(laneKey)
end
