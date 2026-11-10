-- tests/test_lane_visibility.lua — the lanes' visibility rules (plan Task 1.3, spec §4 Visibility):
-- ShouldShow and Alpha over a context, one case per `show` mode, per `where` key and per hide rule,
-- the hide-after-combat window, the events registered only while some lane uses their rule, the
-- lane frames following the decision, and the Retail-only keys absent on WoW Forever.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

-- A fresh instance whose frames record their paint (alpha, label text).
local function setup(mutate)
    local inst = T.load({ mutate = function(m)
        installPaint(m)
        if mutate then mutate(m) end
    end })
    return inst, inst.NS.LaneVisibility
end

local function vis(inst, laneKey) return inst.NS.db.profile.lanes[laneKey].visibility end

-- Write one visibility key and announce it, as the settings seam does.
local function setVis(inst, laneKey, key, value)
    vis(inst, laneKey)[key] = value
    inst.NS.AnnounceSettingsChanged("lanes." .. laneKey .. ".visibility." .. key, value)
end

local function setWhere(inst, laneKey, key, value)
    vis(inst, laneKey).where[key] = value
    inst.NS.AnnounceSettingsChanged("lanes." .. laneKey .. ".visibility.where." .. key, value)
end

-- A context: out of combat, no target, the open world, nothing else going on.
local function ctx(over)
    local c = { inCombat = false, hasTarget = false, instanceType = "none", isDelve = false,
                mounted = false, inVehicle = false, petBattle = false, resting = false,
                secondsSinceCombat = math.huge }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

-- The events the visibility frame is registered for: { [event] = true }.
local function regs(inst)
    local frame = inst.NS.LaneVisibility.Frame()
    local out = {}
    for _, r in ipairs(inst.mocks.__registrations()) do
        if frame and r.target == frame then out[r.event] = true end
    end
    return out
end

local function lane(inst, laneKey) return inst.NS.LaneRender.Get(laneKey) end

-- ── the show modes ─────────────────────────────────────────────────────────────────────────────

test("lane visibility: show always shows in and out of combat", function()
    local inst, V = setup()
    assertTrue(V.ShouldShow("player", ctx()))
    assertTrue(V.ShouldShow("player", ctx({ inCombat = true })))
    assertEqual(vis(inst, "player").show, "always", "the default")
end)

test("lane visibility: show never hides everywhere", function()
    local inst, V = setup()
    vis(inst, "player").show = "never"
    assertFalse(V.ShouldShow("player", ctx()))
    assertFalse(V.ShouldShow("player", ctx({ inCombat = true })))
end)

test("lane visibility: show combat shows only in combat", function()
    local inst, V = setup()
    vis(inst, "player").show = "combat"
    assertFalse(V.ShouldShow("player", ctx()))
    assertTrue(V.ShouldShow("player", ctx({ inCombat = true })))
    assertFalse(V.ShouldShow("player", ctx({ hasTarget = true })), "a target is not combat")
end)

test("lane visibility: show combatOrTarget shows in combat or with a target", function()
    local inst, V = setup()
    vis(inst, "player").show = "combatOrTarget"
    assertFalse(V.ShouldShow("player", ctx()))
    assertTrue(V.ShouldShow("player", ctx({ inCombat = true })))
    assertTrue(V.ShouldShow("player", ctx({ hasTarget = true })))
end)

test("lane visibility: an unknown show mode reads as always", function()
    local inst, V = setup()
    vis(inst, "player").show = "sometimes"
    assertTrue(V.ShouldShow("player", ctx()))
end)

test("lane visibility: hideAfter keeps a combat lane up for N seconds after combat", function()
    local inst, V = setup()
    local v = vis(inst, "player")
    v.show, v.hideAfter = "combat", 5
    assertTrue(V.ShouldShow("player", ctx({ secondsSinceCombat = 0 })), "just out of combat")
    assertTrue(V.ShouldShow("player", ctx({ secondsSinceCombat = 4.9 })), "inside the window")
    assertFalse(V.ShouldShow("player", ctx({ secondsSinceCombat = 5 })), "the window is over")
    v.hideAfter = 0
    assertFalse(V.ShouldShow("player", ctx({ secondsSinceCombat = 0 })), "0 hides at once")
    v.show, v.hideAfter = "combatOrTarget", 3
    assertTrue(V.ShouldShow("player", ctx({ secondsSinceCombat = 2 })), "combatOrTarget too")
end)

-- ── where ──────────────────────────────────────────────────────────────────────────────────────

test("lane visibility: each where key maps its instance type", function()
    local inst, V = setup()
    local cases = { { "world", "none" }, { "dungeon", "party" }, { "raid", "raid" }, { "bg", "pvp" } }
    if inst.NS.Compat.IsRetail() then cases[#cases + 1] = { "arena", "arena" } end
    for _, c in ipairs(cases) do
        local key, instanceType = c[1], c[2]
        local w = vis(inst, "player").where
        assertEqual(V.WhereKey(ctx({ instanceType = instanceType })), key, instanceType)
        assertTrue(V.ShouldShow("player", ctx({ instanceType = instanceType })), key .. " on")
        w[key] = false
        assertFalse(V.ShouldShow("player", ctx({ instanceType = instanceType })), key .. " off")
        w[key] = true
    end
end)

test("lane visibility: a scenario outside a delve counts as the open world", function()
    local _, V = setup()
    assertEqual(V.WhereKey(ctx({ instanceType = "scenario" })), "world")
end)

test("lane visibility: a delve is its own where key on Retail", function()
    local inst, V = setup()
    if not inst.NS.Compat.IsRetail() then return end
    assertEqual(V.WhereKey(ctx({ instanceType = "scenario", isDelve = true })), "delve")
    vis(inst, "player").where.delve = false
    assertFalse(V.ShouldShow("player", ctx({ instanceType = "scenario", isDelve = true })))
    assertTrue(V.ShouldShow("player", ctx({ instanceType = "scenario" })), "not a delve")
end)

test("lane visibility: forever: delve/arena keys absent from the defaults the Lanes page reads", function()
    local inst, V = setup()
    local w = vis(inst, "player").where
    if inst.NS.Compat.IsForever() then
        assertEqual(w.delve, nil, "no delve key")
        assertEqual(w.arena, nil, "no arena key")
        assertEqual(inst.NS.db.profile.lanes.pet.visibility.where.arena, nil, "nor on the pet lane")
        -- An absent key never hides: Forever's own arenas show the lane.
        assertTrue(V.ShouldShow("player", ctx({ instanceType = "arena" })))
        assertFalse(V.Context().isDelve, "no delve on Forever")
    else
        assertEqual(w.delve, true)
        assertEqual(w.arena, true)
    end
end)

-- ── the hide rules ─────────────────────────────────────────────────────────────────────────────

test("lane visibility: mounted, vehicle, pet battle and resting each hide while their rule is on", function()
    local inst, V = setup()
    local v = vis(inst, "player")
    local rules = { { "hideMounted", "mounted" }, { "hideVehicle", "inVehicle" },
                    { "hidePetBattle", "petBattle" }, { "hideResting", "resting" } }
    for _, r in ipairs(rules) do
        local key, field = r[1], r[2]
        v[key] = true
        assertFalse(V.ShouldShow("player", ctx({ [field] = true })), key .. " on hides")
        v[key] = false
        assertTrue(V.ShouldShow("player", ctx({ [field] = true })), key .. " off shows")
    end
end)

test("lane visibility: the hide rules' defaults (mounted, vehicle and pet battle on; resting off)", function()
    local inst = setup()
    local v = vis(inst, "pet")
    assertEqual(v.hideMounted, true)
    assertEqual(v.hideResting, false)
    if inst.NS.Compat.IsForever() then
        -- Vehicles and pet battles are Retail-only (clients-§4): the keys are absent, not false.
        assertEqual(v.hideVehicle, nil, "no vehicle key on Forever")
        assertEqual(v.hidePetBattle, nil, "no pet battle key on Forever")
    else
        assertEqual(v.hideVehicle, true)
        assertEqual(v.hidePetBattle, true)
    end
end)

test("lane visibility: Alpha follows alphaCombat and alphaOOC", function()
    local inst, V = setup()
    local v = vis(inst, "player")
    v.alphaCombat, v.alphaOOC = 0.9, 0.4
    assertEqual(V.Alpha("player", ctx({ inCombat = true })), 0.9)
    assertEqual(V.Alpha("player", ctx()), 0.4)
    v.alphaOOC = 7
    assertEqual(V.Alpha("player", ctx()), 1, "clamped to 0..1")
end)

test("lane visibility: Context reads the client", function()
    local inst, V = setup()
    local m = inst.mocks
    m.__mounted, m.__resting, m.__inVehicle, m.__petBattle = true, true, true, true
    m.__unitExists.target = true
    m.__context.instanceType = "raid"
    local c = V.Context()
    assertTrue(c.mounted and c.resting and c.inVehicle and c.petBattle and c.hasTarget, "flags")
    assertEqual(c.instanceType, "raid")
    assertEqual(c.secondsSinceCombat, math.huge, "never in combat yet")
end)

-- ── the frames follow ──────────────────────────────────────────────────────────────────────────

test("lane visibility: a lane set to never hides, and back to always shows", function()
    local inst = setup()
    setVis(inst, "player", "show", "never")
    assertFalse(lane(inst, "player"):IsShown(), "hidden")
    setVis(inst, "player", "show", "always")
    assertTrue(lane(inst, "player"):IsShown(), "shown")
end)

test("lane visibility: a combat lane shows on PLAYER_REGEN_DISABLED and hides hideAfter seconds after", function()
    local inst = setup()
    local m = inst.mocks
    setVis(inst, "player", "show", "combat")
    setVis(inst, "player", "hideAfter", 5)
    assertFalse(lane(inst, "player"):IsShown(), "out of combat: hidden")
    m.__inCombat = true
    m.__fire("PLAYER_REGEN_DISABLED")
    assertTrue(lane(inst, "player"):IsShown(), "in combat: shown")
    m.__inCombat = false
    m.__now = 100
    m.__fire("PLAYER_REGEN_ENABLED")
    assertTrue(lane(inst, "player"):IsShown(), "inside the hide-after window")
    m.__now = 105
    m.__fireTimers()
    assertFalse(lane(inst, "player"):IsShown(), "the window closed")
end)

test("lane visibility: combatOrTarget follows PLAYER_TARGET_CHANGED", function()
    local inst = setup()
    local m = inst.mocks
    setVis(inst, "player", "show", "combatOrTarget")
    assertFalse(lane(inst, "player"):IsShown())
    m.__unitExists.target = true
    m.__fire("PLAYER_TARGET_CHANGED")
    assertTrue(lane(inst, "player"):IsShown(), "a target shows it")
    m.__unitExists.target = false
    m.__fire("PLAYER_TARGET_CHANGED")
    assertFalse(lane(inst, "player"):IsShown(), "no target hides it")
end)

test("lane visibility: mounting hides the lane through PLAYER_MOUNT_DISPLAY_CHANGED", function()
    local inst = setup()
    local m = inst.mocks
    m.__mounted = true
    m.__fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    assertFalse(lane(inst, "player"):IsShown(), "mounted")
    assertFalse(lane(inst, "pet"):IsShown(), "the pet lane too")
    m.__mounted = false
    m.__fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    assertTrue(lane(inst, "player"):IsShown(), "dismounted")
end)

test("lane visibility: a vehicle hides the lane through UNIT_ENTERED_VEHICLE", function()
    local inst = setup()
    if inst.NS.Compat.IsForever() then return end -- no vehicles on Forever: the rule is absent
    local m = inst.mocks
    m.__inVehicle = true
    m.__fire("UNIT_ENTERED_VEHICLE", "player")
    assertFalse(lane(inst, "player"):IsShown())
    m.__inVehicle = false
    m.__fire("UNIT_EXITED_VEHICLE", "player")
    assertTrue(lane(inst, "player"):IsShown())
end)

test("lane visibility: a pet battle hides the lane until it closes", function()
    local inst = setup()
    if inst.NS.Compat.IsForever() then return end -- no pet battles on Forever: the rule is absent
    local m = inst.mocks
    m.__petBattle = true
    m.__fire("PET_BATTLE_OPENING_START")
    assertFalse(lane(inst, "player"):IsShown())
    m.__petBattle = false
    m.__fire("PET_BATTLE_CLOSE")
    assertTrue(lane(inst, "player"):IsShown())
end)

test("lane visibility: resting hides the lane once hideResting is on", function()
    local inst = setup()
    local m = inst.mocks
    m.__resting = true
    m.__fire("PLAYER_UPDATE_RESTING")
    assertTrue(lane(inst, "player"):IsShown(), "hideResting is off by default")
    setVis(inst, "player", "hideResting", true)
    assertFalse(lane(inst, "player"):IsShown(), "on: hidden")
    m.__resting = false
    m.__fire("PLAYER_UPDATE_RESTING")
    assertTrue(lane(inst, "player"):IsShown(), "left the inn")
end)

test("lane visibility: a where key switched off hides the lane on ZONE_CHANGED_NEW_AREA", function()
    local inst = setup()
    local m = inst.mocks
    setWhere(inst, "player", "dungeon", false)
    assertTrue(lane(inst, "player"):IsShown(), "still in the open world")
    m.__context.inInstance, m.__context.instanceType = true, "party"
    m.__fire("ZONE_CHANGED_NEW_AREA")
    assertFalse(lane(inst, "player"):IsShown(), "in a dungeon: hidden")
    assertTrue(lane(inst, "pet"):IsShown(), "the pet lane's own where list still shows it")
end)

test("lane visibility: the lane's alpha follows combat", function()
    local inst = setup()
    local m = inst.mocks
    setVis(inst, "player", "alphaOOC", 0.5)
    assertEqual(lane(inst, "player"):GetAlpha(), 0.5, "out of combat")
    m.__inCombat = true
    m.__fire("PLAYER_REGEN_DISABLED")
    assertEqual(lane(inst, "player"):GetAlpha(), 1, "in combat")
end)

test("lane visibility: a cast on a hidden lane is dropped", function()
    local inst = setup()
    setVis(inst, "player", "show", "never")
    inst.NS.LaneRender.Push("player", { texture = 1, spellID = 133, t = 0, interrupted = false })
    assertEqual(#inst.NS.LaneRender.__icons("player"), 0)
end)

test("lane visibility: hiding a lane clears its icons and its OnUpdate", function()
    local inst = setup()
    local R = inst.NS.LaneRender
    R.Push("player", { texture = 1, spellID = 133, t = 0, interrupted = false })
    assertEqual(#R.__icons("player"), 1)
    setVis(inst, "player", "show", "never")
    assertEqual(#R.__icons("player"), 0)
    assertEqual(lane(inst, "player"):GetScript("OnUpdate"), nil)
end)

test("lane visibility: the first cast of a pull shows a combat lane before PLAYER_REGEN_DISABLED", function()
    local inst = setup()
    setVis(inst, "player", "show", "combat")
    inst.mocks.__inCombat = true
    inst.NS.LaneRender.Push("player", { texture = 1, spellID = 133, t = 0, interrupted = false })
    assertTrue(lane(inst, "player"):IsShown(), "shown")
    assertEqual(#inst.NS.LaneRender.__icons("player"), 1, "and the cast kept")
end)

test("lane visibility: UNIT_PET refreshes the pet lane's label", function()
    local inst = setup()
    local m = inst.mocks
    local label = inst.NS.LaneRender.__label("pet")
    assertEqual(label:GetText(), "Pet")
    m.__unitExists.pet, m.__unitNames.pet = true, "Fluffy"
    m.__fire("UNIT_PET", "player")
    assertEqual(label:GetText(), "Fluffy")
end)

-- ── registration ───────────────────────────────────────────────────────────────────────────────

test("lane visibility: events are registered only while some lane uses their rule", function()
    local inst = setup()
    local r = regs(inst)
    -- The defaults: always shown, hide when mounted, in a vehicle or in a pet battle.
    assertTrue(r.PLAYER_MOUNT_DISPLAY_CHANGED, "mounted")
    if inst.NS.Compat.IsForever() then
        assertFalse(r.UNIT_ENTERED_VEHICLE ~= nil, "no vehicle event on Forever")
        assertFalse(r.PET_BATTLE_OPENING_START ~= nil, "no pet battle event on Forever")
    else
        assertTrue(r.UNIT_ENTERED_VEHICLE and r.UNIT_EXITED_VEHICLE, "vehicle")
        assertTrue(r.PET_BATTLE_OPENING_START and r.PET_BATTLE_CLOSE, "pet battle")
    end
    assertTrue(r.UNIT_PET, "the pet lane's label")
    assertFalse(r.PLAYER_REGEN_DISABLED ~= nil, "no lane needs combat")
    assertFalse(r.PLAYER_TARGET_CHANGED ~= nil, "no lane needs the target")
    assertFalse(r.PLAYER_UPDATE_RESTING ~= nil, "no lane hides resting")
    assertFalse(r.ZONE_CHANGED_NEW_AREA ~= nil, "every where key is on")
    setVis(inst, "pet", "show", "combatOrTarget")
    r = regs(inst)
    assertTrue(r.PLAYER_REGEN_DISABLED and r.PLAYER_REGEN_ENABLED, "combat now")
    assertTrue(r.PLAYER_TARGET_CHANGED, "target now")
    setWhere(inst, "player", "raid", false)
    assertTrue(regs(inst).ZONE_CHANGED_NEW_AREA, "a where key off")
end)

test("lane visibility: a lane set to never or switched off needs no event", function()
    local inst = setup()
    for _, k in ipairs({ "player", "pet" }) do
        local v = vis(inst, k)
        v.show, v.hideResting = "never", true
    end
    inst.NS.AnnounceSettingsChanged("lanes.player.visibility.show", "never")
    local r = regs(inst)
    assertFalse(r.PLAYER_MOUNT_DISPLAY_CHANGED ~= nil, "never needs no mount event")
    assertFalse(r.PLAYER_UPDATE_RESTING ~= nil, "nor resting")
    assertTrue(r.UNIT_PET, "the pet lane's label still follows its pet")
    inst.NS.db.profile.lanes.pet.enabled = false
    inst.NS.AnnounceSettingsChanged("lanes.pet.enabled", false)
    assertFalse(regs(inst).UNIT_PET ~= nil, "no pet lane, no UNIT_PET")
end)

test("lane visibility: stand-down drops every registration and the hide-after timer", function()
    local inst = setup()
    local m, NS = inst.mocks, inst.NS
    setVis(inst, "player", "show", "combat")
    m.__fire("PLAYER_REGEN_ENABLED")
    NS.SetByPath("general.enabled", false)
    assertEqual(next(regs(inst)), nil, "nothing registered while disabled")
    assertEqual(m.__fireUnconditional(NS.LaneVisibility.Frame(), "PLAYER_REGEN_DISABLED"), 1, "reachable")
    assertFalse(lane(inst, "player"):IsShown(), "a stood-down handler shows nothing")
    m.__fireTimers()
    assertFalse(lane(inst, "player"):IsShown(), "no timer brings it back")
    NS.SetByPath("general.enabled", true)
    assertTrue(regs(inst).PLAYER_REGEN_DISABLED, "back from current settings")
end)
