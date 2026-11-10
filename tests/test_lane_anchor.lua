-- tests/test_lane_anchor.lua — where a lane sits (plan Task 1.3, spec §4 Anchoring and Layering):
-- free, docked to the other lane and on a unit frame, the dock cycle refused, the unit frames found
-- in order with a fallback to free, the strata and level read off the host, the edit overlay of
-- Edit Mode and `/ct unlock` with its chrome layering, the drag that saves a free lane's place, the
-- reset, and the stand-down.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- Every line the addon printed, in order.
local function capturePrints(inst)
    local lines = {}
    local NS = inst.NS
    local print = NS.Print
    NS.Print = function(line, ...)
        lines[#lines + 1] = tostring(line)
        return print(line, ...)
    end
    return lines
end

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

-- A fresh instance whose frames record their paint (so a font string is not the frame it sits on).
local function load(mutate)
    return T.load({ mutate = function(m)
        installPaint(m)
        if mutate then mutate(m) end
    end })
end

local function setup(mutate)
    local inst = load(mutate)
    -- The world is entered, so a diagnostic is not held for the login's late unit frames.
    inst.mocks.__fire("PLAYER_ENTERING_WORLD")
    return inst, inst.NS.LaneAnchor
end

local function cfgOf(inst, laneKey) return inst.NS.db.profile.lanes[laneKey] end

local function setAnchor(inst, laneKey, key, value)
    cfgOf(inst, laneKey).anchor[key] = value
    inst.NS.AnnounceSettingsChanged("lanes." .. laneKey .. ".anchor." .. key, value)
end

local function set(inst, laneKey, key, value)
    cfgOf(inst, laneKey)[key] = value
    inst.NS.AnnounceSettingsChanged("lanes." .. laneKey .. "." .. key, value)
end

-- Record the lane frame's points from now on: answers a function returning the current point list.
local function points(inst, laneKey)
    local frame = inst.NS.LaneRender.Get(laneKey)
    local list = {}
    rawset(frame, "ClearAllPoints", function() list = {} end)
    rawset(frame, "SetPoint", function(_, ...) list[#list + 1] = { ... } end)
    return function() return list end
end

local function layers(inst, f) return inst.mocks.__layers(f) end

-- A named frame the client would hold as a global (a unit frame addon's player frame).
local function unitFrame(inst, name)
    return inst.mocks.CreateFrame("Frame", name, inst.mocks.UIParent)
end

-- ── free and dock ──────────────────────────────────────────────────────────────────────────────

test("lane anchor: free mode uses saved point", function()
    local inst = setup()
    local pts = points(inst, "player")
    local a = cfgOf(inst, "player").anchor
    a.point, a.relPoint, a.x = "TOPLEFT", "BOTTOMLEFT", 12
    setAnchor(inst, "player", "y", -40)
    local p = pts()
    assertEqual(#p, 1)
    assertEqual(p[1][1], "TOPLEFT")
    assertTrue(p[1][2] == inst.mocks.UIParent, "relative to UIParent")
    assertEqual(p[1][3], "BOTTOMLEFT")
    assertEqual(p[1][4], 12)
    assertEqual(p[1][5], -40)
end)

test("lane anchor: dock pet under player follows player", function()
    local inst, A = setup()
    local pts = points(inst, "pet")
    A.Apply("pet")
    local p = pts()
    assertEqual(#p, 1)
    assertEqual(p[1][1], "TOP")
    assertTrue(p[1][2] == inst.NS.LaneRender.Get("player"), "on the player lane")
    assertEqual(p[1][3], "BOTTOM")
    assertEqual(p[1][4], 0)
    assertEqual(p[1][5], -4, "the gap below")
    local host, reason = A.ResolveHost("pet")
    assertTrue(host == inst.NS.LaneRender.Get("player"))
    assertEqual(reason, "dock")
end)

test("lane anchor: a side-by-side dock puts the gap on the x axis", function()
    local inst, A = setup()
    local pts = points(inst, "pet")
    local a = cfgOf(inst, "pet").anchor
    a.point, a.relPoint, a.gap = "LEFT", "RIGHT", 6
    A.Apply("pet")
    assertEqual(pts()[1][4], 6)
    assertEqual(pts()[1][5], 0)
    a.point, a.relPoint = "BOTTOM", "TOP"
    A.Apply("pet")
    assertEqual(pts()[1][5], 6, "above: the gap goes up")
end)

test("lane anchor: a docked lane follows a host docked later in the build order", function()
    local inst, A = setup()
    setAnchor(inst, "pet", "mode", "free")
    local pts = points(inst, "player")
    local a = cfgOf(inst, "player").anchor
    a.target = "pet"
    setAnchor(inst, "player", "mode", "dock")
    assertTrue(pts()[1][2] == inst.NS.LaneRender.Get("pet"), "player docks to the pet lane")
    -- A fresh Sync (login order: player before pet) lands the same.
    inst.NS.LaneRender.Sync()
    assertTrue(pts()[1][2] == inst.NS.LaneRender.Get("pet"), "and after a Sync")
    assertEqual(select(2, A.ResolveHost("player")), "dock")
end)

test("lane anchor: dock cycle (player→pet while pet→player) is refused and prints once", function()
    local inst, A = setup()
    local lines = capturePrints(inst)
    local pts = points(inst, "player")
    local a = cfgOf(inst, "player").anchor
    a.target = "pet"
    setAnchor(inst, "player", "mode", "dock")
    local p = pts()
    assertTrue(p[1][2] == inst.mocks.UIParent, "the player lane falls back to its free point")
    assertEqual(p[1][5], -200)
    local host, reason = A.ResolveHost("player")
    assertEqual(host, nil)
    assertEqual(reason, "cycle")
    A.Apply("player")
    A.Apply("pet")
    inst.NS.LaneRender.Sync()
    assertEqual(#lines, 1, "one line for the cycle, however often it is applied")
    assertTrue(lines[1]:find("dock") ~= nil, "the line says why: " .. lines[1])
    -- Broken and made again: a fresh line.
    setAnchor(inst, "player", "mode", "free")
    setAnchor(inst, "player", "mode", "dock")
    assertEqual(#lines, 2)
end)

test("lane anchor: a dock to itself or to a lane switched off falls back to free", function()
    local inst, A = setup()
    local pts = points(inst, "pet")
    set(inst, "player", "enabled", false)
    assertTrue(pts()[1][2] == inst.mocks.UIParent, "host off: free")
    assertEqual(select(2, A.ResolveHost("pet")), "off")
    set(inst, "player", "enabled", true)
    assertTrue(pts()[1][2] == inst.NS.LaneRender.Get("player"), "host back: docked again")
    setAnchor(inst, "pet", "target", "pet")
    assertEqual(select(2, A.ResolveHost("pet")), "self")
    assertTrue(pts()[1][2] == inst.mocks.UIParent)
end)

test("lane anchor: a lane at its fallback place sits on screen, x and y from the CENTER", function()
    local inst = setup()
    local pts = points(inst, "pet")
    set(inst, "player", "enabled", false)
    local p = pts()[1]
    assertEqual(p[1], "CENTER", "not the dock's TOP on UIParent's BOTTOM, off the screen")
    assertTrue(p[2] == inst.mocks.UIParent)
    assertEqual(p[3], "CENTER")
    assertEqual(p[4], 0)
    assertEqual(p[5], -236)
    assertEqual(cfgOf(inst, "pet").anchor.point, "TOP", "the dock's point is kept for when the host is back")
end)

test("lane anchor: leaving dock mode for free moves a TOP under BOTTOM point to CENTER", function()
    local inst = setup()
    local pts = points(inst, "pet")
    setAnchor(inst, "pet", "mode", "free")
    local a = cfgOf(inst, "pet").anchor
    assertEqual(a.point, "CENTER")
    assertEqual(a.relPoint, "CENTER")
    local p = pts()[1]
    assertEqual(p[1], "CENTER")
    assertEqual(p[3], "CENTER")
    assertEqual(p[5], -236)
end)

test("lane anchor: dragging a lane at its fallback place keeps its dock point", function()
    local inst, A = setup()
    set(inst, "player", "enabled", false)
    A.SetUnlocked(true)
    local lane, ov = inst.NS.LaneRender.Get("pet"), A.__overlay("pet")
    rawset(lane, "StartMoving", function() end)
    rawset(lane, "StopMovingOrSizing", function() end)
    rawset(lane, "GetCenter", function() return 530, 350 end)
    rawset(lane, "GetEffectiveScale", function() return 1 end)
    rawset(inst.mocks.UIParent, "GetCenter", function() return 500, 400 end)
    rawset(inst.mocks.UIParent, "GetEffectiveScale", function() return 1 end)
    ov:__fire("OnDragStart", "LeftButton")
    ov:__fire("OnDragStop")
    local a = cfgOf(inst, "pet").anchor
    assertEqual(a.x, 30)
    assertEqual(a.y, -50)
    assertEqual(a.point, "TOP", "still the dock's point")
    assertEqual(a.relPoint, "BOTTOM")
end)

-- ── unit frames ────────────────────────────────────────────────────────────────────────────────

test("lane anchor: the unit frame list names each supported addon, Blizzard's last", function()
    local _, A = setup()
    local p, q = A.UNIT_FRAMES.player, A.UNIT_FRAMES.pet
    assertEqual(p[1], "ElvUF_Player")
    assertEqual(p[#p], "PlayerFrame")
    assertEqual(q[1], "ElvUF_Pet")
    assertEqual(q[#q], "PetFrame")
    assertEqual(#p, #q, "one per addon on each lane")
end)

test("lane anchor: unit-frame mode picks the first existing frame in order", function()
    local inst, A = setup()
    unitFrame(inst, "PlayerFrame")
    local suf = unitFrame(inst, "SUFUnitplayer")
    local pts = points(inst, "player")
    setAnchor(inst, "player", "mode", "unit")
    local host, name = A.ResolveHost("player")
    assertTrue(host == suf, "Shadowed Unit Frames before Blizzard")
    assertEqual(name, "SUFUnitplayer")
    assertTrue(pts()[1][2] == suf, "the lane sits on it")
    local elv = unitFrame(inst, "ElvUF_Player")
    A.Apply("player")
    assertTrue(pts()[1][2] == elv, "ElvUI first of all")
end)

test("lane anchor: a frame named by the player wins over the list", function()
    local inst, A = setup()
    unitFrame(inst, "PlayerFrame")
    local mine = unitFrame(inst, "MyCustomPlayerFrame")
    cfgOf(inst, "player").anchor.frameName = "MyCustomPlayerFrame"
    setAnchor(inst, "player", "mode", "unit")
    assertTrue(A.ResolveHost("player") == mine)
end)

test("lane anchor: a forbidden frame is skipped", function()
    local inst, A = setup()
    local elv = unitFrame(inst, "ElvUF_Player")
    rawset(elv, "IsForbidden", function() return true end)
    local blizz = unitFrame(inst, "PlayerFrame")
    setAnchor(inst, "player", "mode", "unit")
    assertTrue(A.ResolveHost("player") == blizz)
end)

test("lane anchor: missing frame falls back to free and prints one diagnostic", function()
    local inst, A = setup()
    local lines = capturePrints(inst)
    local pts = points(inst, "player")
    setAnchor(inst, "player", "mode", "unit")
    local host, reason = A.ResolveHost("player")
    assertEqual(host, nil)
    assertEqual(reason, "missing")
    assertTrue(pts()[1][2] == inst.mocks.UIParent, "free")
    A.Apply("player")
    A.Apply("player")
    assertEqual(#lines, 1, "one line")
    -- Found later (a unit frame addon that builds late): placed, and a later loss prints again.
    local blizz = unitFrame(inst, "PlayerFrame")
    A.Apply("player")
    assertTrue(pts()[1][2] == blizz)
    inst.mocks.PlayerFrame = nil
    A.Apply("player")
    assertEqual(#lines, 2)
end)

test("lane anchor: a unit frame missing at login is looked for again on entering the world", function()
    local inst = load()
    local lines = capturePrints(inst)
    local A = inst.NS.LaneAnchor
    cfgOf(inst, "player").anchor.mode = "unit"
    inst.NS.LaneRender.Sync()
    assertEqual(#lines, 0, "held while the unit frame addons may still be building")
    local blizz = unitFrame(inst, "PlayerFrame")
    local pts = points(inst, "player")
    inst.mocks.__fire("PLAYER_ENTERING_WORLD")
    assertTrue(pts()[1][2] == blizz, "placed once the world is entered")
    assertEqual(#lines, 0, "found: nothing to say")
    assertTrue(A.ResolveHost("player") == blizz)
end)

test("lane anchor: switching to unit-frame mode makes the strata Match host", function()
    local inst = setup()
    assertEqual(cfgOf(inst, "player").strata, "LOW")
    setAnchor(inst, "player", "mode", "unit")
    assertEqual(cfgOf(inst, "player").strata, "HOST", "the unit-frame default")
    setAnchor(inst, "player", "mode", "free")
    assertEqual(cfgOf(inst, "player").strata, "LOW", "and back")
end)

test("lane anchor: leaving free mode moves a CENTER-to-CENTER point to TOP under BOTTOM", function()
    local inst = setup()
    setAnchor(inst, "player", "mode", "unit")
    local a = cfgOf(inst, "player").anchor
    assertEqual(a.point, "TOP")
    assertEqual(a.relPoint, "BOTTOM")
end)

test("lane anchor: strata follows host when strata=\"HOST\"", function()
    local inst = setup()
    local host = unitFrame(inst, "PlayerFrame")
    host:SetFrameStrata("HIGH")
    host:SetFrameLevel(20)
    setAnchor(inst, "player", "mode", "unit")
    local lane = inst.NS.LaneRender.Get("player")
    assertEqual(layers(inst, lane).strata, "HIGH")
    local LEVEL = inst.NS.Constants.LAYERS.LEVEL
    assertEqual(layers(inst, lane).level, 20 + LEVEL.LANE, "a named offset over the host")
end)

test("lane anchor: explicit strata (e.g. LOW) overrides the host in unit-frame mode", function()
    local inst = setup()
    local host = unitFrame(inst, "PlayerFrame")
    host:SetFrameStrata("HIGH")
    host:SetFrameLevel(20)
    setAnchor(inst, "player", "mode", "unit")
    set(inst, "player", "strata", "LOW")
    local lane = inst.NS.LaneRender.Get("player")
    assertEqual(layers(inst, lane).strata, "LOW")
    local parent = layers(inst, lane:GetParent()).level
    assertEqual(layers(inst, lane).level, parent + inst.NS.Constants.LAYERS.LEVEL.LANE,
        "its own strata: the level is its parent's again")
end)

test("lane anchor: level offset adds to the relative base", function()
    local inst = setup()
    local host = unitFrame(inst, "PlayerFrame")
    host:SetFrameLevel(20)
    setAnchor(inst, "player", "mode", "unit")
    set(inst, "player", "levelOffset", 5)
    local LEVEL = inst.NS.Constants.LAYERS.LEVEL
    local lane = inst.NS.LaneRender.Get("player")
    assertEqual(layers(inst, lane).level, 20 + LEVEL.LANE + 5)
    set(inst, "player", "levelOffset", 99)
    assertEqual(layers(inst, lane).level, 20 + LEVEL.LANE + 50, "capped at 50")
end)

test("lane anchor: a secret host strata or level is never used", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local inst = setup()
        local host = unitFrame(inst, "PlayerFrame")
        rawset(host, "GetFrameStrata", function() return T.secret("HIGH") end)
        rawset(host, "GetFrameLevel", function() return T.secret(20) end)
        setAnchor(inst, "player", "mode", "unit")
        local lane = inst.NS.LaneRender.Get("player")
        assertEqual(layers(inst, lane).strata, "LOW", "the lane's own default strata")
        assertEqual(layers(inst, lane).level,
            layers(inst, lane:GetParent()).level + inst.NS.Constants.LAYERS.LEVEL.LANE, "its parent's base")
    end)
    restore()
    assertTrue(ok, tostring(err))
end)

-- ── the edit overlay ───────────────────────────────────────────────────────────────────────────

test("lane anchor: Edit Mode shows each lane's overlay and closing it hides them", function()
    local inst, A = setup()
    assertFalse(A.__overlay("player"):IsShown(), "locked in place by default")
    inst.mocks.EventRegistry:TriggerEvent("EditMode.Enter")
    assertTrue(A.IsUnlocked())
    assertTrue(A.__overlay("player"):IsShown(), "player overlay")
    assertTrue(A.__overlay("pet"):IsShown(), "pet overlay")
    inst.mocks.EventRegistry:TriggerEvent("EditMode.Exit")
    assertFalse(A.IsUnlocked())
    assertFalse(A.__overlay("player"):IsShown())
end)

test("lane anchor: the Locked row keeps Edit Mode from showing the overlay", function()
    local inst, A = setup()
    inst.NS.SetByPath("general.locked", true)
    inst.mocks.EventRegistry:TriggerEvent("EditMode.Enter")
    assertFalse(A.IsUnlocked())
    assertFalse(A.__overlay("player"):IsShown())
end)

test("lane anchor: /ct unlock shows the overlay and /ct lock hides it", function()
    local inst, A = setup()
    inst.NS.Slash:OnSlash("lock")
    assertFalse(A.__overlay("player"):IsShown())
    inst.NS.Slash:OnSlash("unlock")
    assertTrue(A.IsUnlocked(), "unlocked")
    assertTrue(A.__overlay("player"):IsShown(), "overlay up")
    inst.NS.Slash:OnSlash("lock")
    assertFalse(A.__overlay("player"):IsShown(), "overlay down")
    A.SetUnlocked(true)
    assertTrue(A.__overlay("pet"):IsShown(), "SetUnlocked is the same switch")
end)

test("lane anchor: an unlocked lane shows even when its visibility says never", function()
    local inst, A = setup()
    cfgOf(inst, "player").visibility.show = "never"
    inst.NS.AnnounceSettingsChanged("lanes.player.visibility.show", "never")
    local lane = inst.NS.LaneRender.Get("player")
    assertFalse(lane:IsShown())
    A.SetUnlocked(true)
    assertTrue(lane:IsShown(), "shown to be moved")
    A.SetUnlocked(false)
    assertFalse(lane:IsShown(), "hidden again")
end)

test("lane anchor: the overlay is chrome over the icon band, mouse-live at MEDIUM or above", function()
    local inst, A = setup()
    A.SetUnlocked(true)
    local lane, ov = inst.NS.LaneRender.Get("player"), A.__overlay("player")
    local LEVEL = inst.NS.Constants.LAYERS.LEVEL
    assertEqual(layers(inst, lane).strata, "LOW")
    assertEqual(layers(inst, ov).strata, "MEDIUM", "floored at MEDIUM")
    assertTrue(layers(inst, ov).fixedStrata, "fixed, so the lane's next SetFrameStrata leaves it")
    assertEqual(layers(inst, ov).level, layers(inst, lane).level + LEVEL.LANE_EDIT)
    assertTrue(LEVEL.LANE_EDIT > LEVEL.ICON_BAND, "above every icon")
    assertTrue(ov:IsIgnoringParentAlpha(), "does not fade with the lane")
    set(inst, "player", "strata", "HIGH")
    assertEqual(layers(inst, ov).strata, "HIGH", "re-lifted with the lane")
end)

test("lane anchor: dragging a free lane saves its place", function()
    local inst, A = setup()
    A.SetUnlocked(true)
    local lane, ov = inst.NS.LaneRender.Get("player"), A.__overlay("player")
    local moved, stopped, userPlaced = 0, 0, nil
    rawset(lane, "StartMoving", function() moved = moved + 1 end)
    rawset(lane, "StopMovingOrSizing", function() stopped = stopped + 1 end)
    rawset(lane, "SetUserPlaced", function(_, v) userPlaced = v end)
    rawset(lane, "GetCenter", function() return 600, 300 end)
    rawset(lane, "GetEffectiveScale", function() return 1 end)
    rawset(inst.mocks.UIParent, "GetCenter", function() return 500, 400 end)
    rawset(inst.mocks.UIParent, "GetEffectiveScale", function() return 1 end)
    ov:__fire("OnDragStart", "LeftButton")
    assertEqual(moved, 1)
    ov:__fire("OnDragStop")
    assertEqual(stopped, 1)
    assertEqual(userPlaced, false, "the client's layout cache does not take it over")
    local a = cfgOf(inst, "player").anchor
    assertEqual(a.point, "CENTER")
    assertEqual(a.relPoint, "CENTER")
    assertEqual(a.x, 100)
    assertEqual(a.y, -100)
end)

test("lane anchor: Edit Mode closing under a drag still saves the place", function()
    local inst, A = setup()
    inst.mocks.EventRegistry:TriggerEvent("EditMode.Enter")
    local lane, ov = inst.NS.LaneRender.Get("player"), A.__overlay("player")
    local stopped = 0
    rawset(lane, "StopMovingOrSizing", function() stopped = stopped + 1 end)
    rawset(lane, "GetCenter", function() return 520, 380 end)
    rawset(lane, "GetEffectiveScale", function() return 1 end)
    rawset(inst.mocks.UIParent, "GetCenter", function() return 500, 400 end)
    rawset(inst.mocks.UIParent, "GetEffectiveScale", function() return 1 end)
    ov:__fire("OnDragStart", "LeftButton")
    inst.mocks.EventRegistry:TriggerEvent("EditMode.Exit")
    assertEqual(stopped, 1, "the move stopped")
    assertEqual(cfgOf(inst, "player").anchor.x, 20)
    assertEqual(cfgOf(inst, "player").anchor.y, -20)
end)

test("lane anchor: a docked lane is not dragged on its own", function()
    local inst, A = setup()
    A.SetUnlocked(true)
    local lane, ov = inst.NS.LaneRender.Get("pet"), A.__overlay("pet")
    local moved = 0
    rawset(lane, "StartMoving", function() moved = moved + 1 end)
    ov:__fire("OnDragStart", "LeftButton")
    assertEqual(moved, 0)
end)

test("lane anchor: ResetPosition puts both lanes back where they started", function()
    local inst = setup()
    local a = cfgOf(inst, "player").anchor
    a.x, a.y, a.point = 300, 40, "TOPLEFT"
    setAnchor(inst, "pet", "mode", "free")
    inst.NS.ResetPositions()
    a = cfgOf(inst, "player").anchor
    assertEqual(a.x, 0)
    assertEqual(a.y, -200)
    assertEqual(a.point, "CENTER")
    assertEqual(cfgOf(inst, "pet").anchor.mode, "dock")
end)

test("lane anchor: stand-down drops the Edit Mode callbacks and hides the overlay", function()
    local inst, A = setup()
    local function callbacks()
        local n = 0
        for _, r in ipairs(inst.mocks.__registrations()) do
            if r.kind == "callback" and r.event:find("^EditMode") then n = n + 1 end
        end
        return n
    end
    assertEqual(callbacks(), 2, "Enter and Exit while running")
    A.SetUnlocked(true)
    inst.NS.SetByPath("general.enabled", false)
    assertEqual(callbacks(), 0, "none while disabled")
    assertFalse(A.__overlay("player"):IsShown())
    inst.mocks.EventRegistry:TriggerEvent("EditMode.Enter")
    assertFalse(A.__overlay("player"):IsShown(), "Edit Mode while disabled shows nothing")
    inst.NS.SetByPath("general.enabled", true)
    assertEqual(callbacks(), 2, "back")
    assertFalse(A.IsUnlocked(), "a stand-up comes back locked")
end)

-- ── deferred review items (plan Task 5.2b) ──────────────────────────────────────────────────────

test("lane anchor: a place saved with no schema row builds the table it writes into", function()
    local inst, A = setup()
    inst.NS.FindSchemaRow = function() return nil end
    cfgOf(inst, "player").anchor = nil
    A.SetUnlocked(true)
    local lane, ov = inst.NS.LaneRender.Get("player"), A.__overlay("player")
    rawset(lane, "StartMoving", function() end)
    rawset(lane, "StopMovingOrSizing", function() end)
    rawset(lane, "SetUserPlaced", function() end)
    rawset(lane, "GetCenter", function() return 600, 300 end)
    rawset(lane, "GetEffectiveScale", function() return 1 end)
    rawset(inst.mocks.UIParent, "GetCenter", function() return 500, 400 end)
    rawset(inst.mocks.UIParent, "GetEffectiveScale", function() return 1 end)
    ov:__fire("OnDragStart", "LeftButton")
    local ok, err = pcall(ov.__fire, ov, "OnDragStop")
    assertTrue(ok, "the drag's save raised: " .. tostring(err))
    local a = cfgOf(inst, "player").anchor
    assertTrue(type(a) == "table", "the anchor table was made")
    assertEqual(a.x, 100)
    assertEqual(a.y, -100)
end)

test("lane anchor: a delve reads as none on WoW Forever, whatever the client says (clients-§4)", function()
    local inst = setup(function(m) m.__inDelve = true end)
    local NS = inst.NS
    assertEqual(NS.Compat.InDelve(), NS.Compat.IsRetail(), "a delve only on Retail")
    inst.mocks.__inDelve = false
    assertFalse(NS.Compat.InDelve())
end)
