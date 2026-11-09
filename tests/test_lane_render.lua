-- tests/test_lane_render.lua — the lanes' pooled renderer (plan Task 1.2, spec §4): icons from
-- LANE_PUSH, the pool's reuse, OnUpdate armed only while a lane holds icons, the restyle on Apply, the
-- ✕ mark, the long-cooldown glow and its cache, the ticks, the label, and THE LAYERING: every level
-- relative to the lane, icons in a bounded band (CastTrail's climbing `level % 200` is the regression
-- these pin), the lane on its configured strata.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

-- A fresh instance whose frames record their paint (distinct textures and font strings).
local function setup(mutate)
    local inst = T.load({ mutate = function(m)
        installPaint(m)
        if mutate then mutate(m) end
    end })
    return inst, inst.NS.LaneRender
end

local function item(spellID, t, over)
    local it = { texture = 136000 + (spellID or 0), spellID = spellID, t = t or 0, interrupted = false }
    for k, v in pairs(over or {}) do it[k] = v end
    return it
end

-- Advance the clock to `now` and run one OnUpdate frame on the lane.
local function tick(inst, laneKey, now)
    inst.mocks.__now = now
    local lane = inst.NS.LaneRender.Get(laneKey)
    local fn = lane:GetScript("OnUpdate")
    if fn then fn(lane, 0.016) end
end

local function cfgOf(inst, laneKey) return inst.NS.db.profile.lanes[laneKey] end

local function set(inst, laneKey, key, value)
    cfgOf(inst, laneKey)[key] = value
    inst.NS.AnnounceSettingsChanged("lanes." .. laneKey .. "." .. key, value)
end

local function lvl(inst, f) return inst.mocks.__layers(f).level end

-- ── the pool and OnUpdate ──────────────────────────────────────────────────────────────────────

test("lane render: a push shows one icon with the cast's texture", function()
    local _, R = setup()
    R.Push("player", item(133, 0))
    local icons = R.__icons("player")
    assertEqual(#icons, 1)
    assertEqual(icons[1].tex:GetTexture(), 136133)
    assertTrue(icons[1]:IsShown(), "shown")
end)

test("lane render: the pool reuses frames after expiry", function()
    local inst, R = setup()
    for i = 1, 3 do R.Push("player", item(100 + i, 0)) end
    local first = {}
    for _, f in ipairs(R.__icons("player")) do first[f] = true end
    tick(inst, "player", 13)
    assertEqual(#R.__icons("player"), 0, "all three expired")
    local free, active = inst.NS.Pool.Counts(R.__pool("player"))
    assertEqual(free, 3)
    assertEqual(active, 0)
    for i = 1, 3 do R.Push("player", item(200 + i, 13)) end
    for _, f in ipairs(R.__icons("player")) do assertTrue(first[f], "a reused frame") end
    free = inst.NS.Pool.Counts(R.__pool("player"))
    assertEqual(free, 0)
end)

test("lane render: OnUpdate is armed while icons show and nil once the lane is empty", function()
    local inst, R = setup()
    local lane = R.Get("player")
    assertEqual(lane:GetScript("OnUpdate"), nil, "idle: nothing polls")
    R.Push("player", item(133, 0))
    assertTrue(lane:GetScript("OnUpdate") ~= nil, "armed")
    tick(inst, "player", 6)
    assertTrue(lane:GetScript("OnUpdate") ~= nil, "still one icon")
    tick(inst, "player", 12.5)
    assertEqual(lane:GetScript("OnUpdate"), nil, "empty again")
end)

test("lane render: OnUpdate moves the icon and fades it", function()
    local inst, R = setup()
    R.Push("player", item(133, 0))
    local icon = R.__icons("player")[1]
    local at
    rawset(icon, "SetPoint", function(_, ...) at = { ... } end)
    tick(inst, "player", 6)
    assertEqual(at[1], "TOPLEFT")
    assertTrue(at[2] == R.Get("player"), "inside its lane")
    assertEqual(at[4], 212)
    assertEqual(at[5], 0)
    tick(inst, "player", 10.8)
    assertTrue(math.abs(icon:GetAlpha() - 0.5) < 1e-6, "halfway through the fade")
end)

test("lane render: Clear empties the lane and disarms OnUpdate", function()
    local _, R = setup()
    R.Push("player", item(133, 0))
    R.Push("player", item(134, 0))
    R.Clear("player")
    assertEqual(#R.__icons("player"), 0)
    assertEqual(R.Get("player"):GetScript("OnUpdate"), nil)
end)

test("lane render: the icons a lane holds stay bounded however fast casts arrive", function()
    local _, R = setup()
    for i = 1, 300 do R.Push("player", item(i, 0)) end
    assertTrue(#R.__icons("player") <= R.MAX_ICONS, "capped at MAX_ICONS")
end)

-- ── the bus and the switches ───────────────────────────────────────────────────────────────────

test("lane render: a cast LaneCasts hears reaches the lane over the bus", function()
    local inst, R = setup()
    inst.mocks.__fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 133)
    assertEqual(#R.__icons("player"), 1)
    inst.mocks.__unitExists.pet = true
    inst.mocks.__fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "Cast-2", 17253)
    assertEqual(#R.__icons("pet"), 1)
end)

test("lane render: a lane switched off hides and takes no push", function()
    local inst, R = setup()
    R.Push("pet", item(17253, 0))
    set(inst, "pet", "enabled", false)
    assertFalse(R.Get("pet"):IsShown(), "hidden")
    assertEqual(#R.__icons("pet"), 0, "cleared")
    R.Push("pet", item(17253, 0))
    assertEqual(#R.__icons("pet"), 0, "no push while off")
    set(inst, "pet", "enabled", true)
    assertTrue(R.Get("pet"):IsShown(), "back")
end)

test("lane render: stand-down clears and hides every lane; stand-up shows them again", function()
    local inst, R = setup()
    R.Push("player", item(133, 0))
    inst.NS.SetByPath("general.enabled", false)
    assertEqual(#R.__icons("player"), 0)
    assertFalse(R.Get("player"):IsShown(), "player lane hidden")
    assertFalse(R.Get("pet"):IsShown(), "pet lane hidden")
    assertEqual(R.Get("player"):GetScript("OnUpdate"), nil)
    R.Push("player", item(133, 0))
    assertEqual(#R.__icons("player"), 0, "nothing while stood down")
    inst.NS.SetByPath("general.enabled", true)
    assertTrue(R.Get("player"):IsShown(), "player lane back")
end)

-- ── style ──────────────────────────────────────────────────────────────────────────────────────

test("lane render: Apply restyles the border color on live icons", function()
    local inst, R = setup()
    R.Push("player", item(133, 0))
    local icon = R.__icons("player")[1]
    local c = inst.mocks.__paint(icon.border[1]).color
    assertEqual(c[1], 1)
    assertEqual(c[2], 0.82)
    set(inst, "player", "borderColor", { r = 0.2, g = 0.4, b = 0.6, a = 1 })
    c = inst.mocks.__paint(icon.border[1]).color
    assertEqual(c[1], 0.2)
    assertEqual(c[2], 0.4)
    assertEqual(c[3], 0.6)
    set(inst, "player", "border", false)
    assertFalse(icon.border[1]:IsShown(), "border off hides it")
end)

test("lane render: icon size and zoom follow Apply", function()
    local inst, R = setup()
    R.Push("player", item(133, 0))
    local icon = R.__icons("player")[1]
    local size
    rawset(icon, "SetSize", function(_, w, h) size = { w, h } end)
    set(inst, "player", "iconSize", 40)
    assertEqual(size[1], 40)
    assertEqual(size[2], 40)
    local p = inst.mocks.__paint(icon.tex)
    assertEqual(p.texCoord[1], 0.08, "zoom 0.08")
end)

test("lane render: an interrupted item shows the ✕ mark, a clean one does not", function()
    local _, R = setup()
    R.Push("player", item(116, 0, { interrupted = true }))
    local icon = R.__icons("player")[1]
    assertTrue(icon.mark:IsShown(), "✕ on the interrupted cast")
    R.Push("player", item(133, 0))
    assertFalse(R.__icons("player")[1].mark:IsShown(), "no ✕ on a clean cast")
end)

test("lane render: a long base cooldown glows, cached per spellID", function()
    local inst, R = setup(function(m) m.__baseCooldowns[12472] = 120000 end)
    R.Push("player", item(12472, 0))
    assertTrue(R.__icons("player")[1].glow[1]:IsShown(), "≥ 29 s glows")
    R.Push("player", item(133, 0))
    assertFalse(R.__icons("player")[1].glow[1]:IsShown(), "a short cooldown does not")
    R.Push("player", item(12472, 0))
    R.Push("player", item(133, 0))
    assertEqual(inst.mocks.__baseCooldownCalls[12472], 1, "asked once for 12472")
    assertEqual(inst.mocks.__baseCooldownCalls[133], 1, "asked once for 133")
end)

test("lane render: glowMinCD sets the bar and glowLongCD off never glows", function()
    local inst, R = setup(function(m) m.__baseCooldowns[1] = 20000 end)
    set(inst, "player", "glowMinCD", 15)
    R.Push("player", item(1, 0))
    assertTrue(R.__icons("player")[1].glow[1]:IsShown(), "20 s ≥ 15 s")
    set(inst, "player", "glowLongCD", false)
    assertFalse(R.__icons("player")[1].glow[1]:IsShown(), "Apply turns the live glow off")
end)

test("lane render: a secret texture goes to SetTexture untouched, and nothing raises", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local _, R = setup()
        local s = T.secret(136133)
        R.Push("player", { texture = s, spellID = nil, t = 0, interrupted = false })
        local icon = R.__icons("player")[1]
        assertTrue(icon.tex:GetTexture() == s, "the secret itself reached SetTexture")
        assertFalse(icon.glow[1]:IsShown(), "no spell ID, no glow")
    end)
    restore()
    assertTrue(ok, tostring(err))
end)

test("lane render: the tooltip is wired only while `tooltip` is on", function()
    local inst, R = setup()
    R.Push("player", item(133, 0))
    local icon = R.__icons("player")[1]
    assertTrue(icon:GetScript("OnEnter") ~= nil, "on by default")
    icon:GetScript("OnEnter")(icon)
    assertTrue(inst.mocks.GameTooltip:IsShown(), "the tooltip opened")
    icon:GetScript("OnLeave")(icon)
    assertFalse(inst.mocks.GameTooltip:IsShown(), "and closed")
    set(inst, "player", "tooltip", false)
    assertEqual(icon:GetScript("OnEnter"), nil, "off: no hover")
end)

test("lane render: stack folds a repeat of the newest cast into one icon with a count", function()
    local inst, R = setup()
    set(inst, "player", "stack", true)
    R.Push("player", item(133, 0))
    R.Push("player", item(133, 1))
    local icons = R.__icons("player")
    assertEqual(#icons, 1)
    assertEqual(icons[1].count:GetText(), "2")
    R.Push("player", item(134, 2))
    assertEqual(#R.__icons("player"), 2, "a different spell is its own icon")
end)

test("lane render: showName writes the spell's name under the icon", function()
    local inst, R = setup()
    set(inst, "player", "showName", true)
    R.Push("player", item(133, 0))
    local icon = R.__icons("player")[1]
    assertTrue(icon.name:IsShown(), "shown")
    assertEqual(icon.name:GetText(), "Spell 133")
end)

-- ── the lane's own surfaces ────────────────────────────────────────────────────────────────────

test("lane render: ticks follow the spacing setting and switch off", function()
    local inst, R = setup()
    assertEqual(#R.__ticks("player"), 8, "1.5 s over 12 s")
    set(inst, "player", "tickSpacing", "1s")
    assertEqual(#R.__ticks("player"), 12)
    set(inst, "player", "ticks", false)
    assertEqual(#R.__ticks("player"), 0)
end)

test("lane render: haste-adjusted ticks read UnitSpellHaste out of combat", function()
    local inst, R = setup(function(m) m.__haste = 50 end)
    set(inst, "player", "tickSpacing", "haste")
    assertEqual(#R.__ticks("player"), 12, "1.0 s GCD over 12 s")
end)

test("lane render: the size follows width, icon size, padding and direction", function()
    local inst, R = setup()
    local lane = R.Get("player")
    local size
    rawset(lane, "SetSize", function(_, w, h) size = { w, h } end)
    R.Apply("player")
    assertEqual(size[1], 480)
    assertEqual(size[2], 28)
    set(inst, "player", "direction", "up")
    assertEqual(size[1], 28)
    assertEqual(size[2], 480)
end)

test("lane render: the label reads You, and the pet's name or a dimmed Pet", function()
    local inst, R = setup()
    assertEqual(R.__label("player"):GetText(), "You")
    assertEqual(R.__label("pet"):GetText(), "Pet")
    assertTrue(R.__label("pet"):GetAlpha() < 1, "dimmed with no pet")
    inst.mocks.__unitExists.pet = true
    inst.mocks.__unitNames.pet = "Wolfie"
    R.Apply("pet")
    assertEqual(R.__label("pet"):GetText(), "Wolfie")
    assertEqual(R.__label("pet"):GetAlpha(), 1)
    set(inst, "player", "label", false)
    assertFalse(R.__label("player"):IsShown(), "label off")
end)

test("lane render: background and now line follow their switches", function()
    local inst, R = setup()
    local bg = R.__bg("player")
    assertTrue(bg:IsShown())
    assertEqual(inst.mocks.__paint(bg).color[4], 0.35)
    set(inst, "player", "background", false)
    assertFalse(bg:IsShown())
    assertTrue(R.__now("player"):IsShown())
    set(inst, "player", "now", false)
    assertFalse(R.__now("player"):IsShown())
end)

-- ── the layering (spec §4, Layering) ───────────────────────────────────────────────────────────

test("lane render: icon levels stay within laneLevel+1..laneLevel+8 after 500 pushes", function()
    local inst, R = setup()
    local band = inst.NS.Constants.LAYERS.LEVEL.ICON_BAND
    assertEqual(band, 8)
    for i = 1, 500 do
        inst.mocks.__now = i * 0.4
        R.Push("player", item(1000 + i, i * 0.4))
        tick(inst, "player", i * 0.4)
    end
    local laneLevel = lvl(inst, R.Get("player"))
    local icons = R.__icons("player")
    assertTrue(#icons > band, "more icons alive than the band is tall (" .. #icons .. ")")
    for _, icon in ipairs(icons) do
        local d = lvl(inst, icon) - laneLevel
        assertTrue(d >= 1 and d <= band, "icon level offset " .. d .. " inside the band")
    end
end)

test("lane render: the newest icon has the highest level in the band", function()
    local inst, R = setup()
    local band = inst.NS.Constants.LAYERS.LEVEL.ICON_BAND
    for i = 1, 5 do R.Push("player", item(i, 0)) end
    local laneLevel = lvl(inst, R.Get("player"))
    local icons = R.__icons("player")
    assertEqual(lvl(inst, icons[1]), laneLevel + band, "newest on top")
    for i = 2, #icons do
        assertTrue(lvl(inst, icons[i]) < lvl(inst, icons[i - 1]), "older sits lower")
    end
end)

test("lane render: lane uses its configured strata (default LOW) and Apply moves live icons with it", function()
    local inst, R = setup()
    local lane = R.Get("player")
    assertEqual(inst.mocks.__layers(lane).strata, "LOW")
    R.Push("player", item(133, 0))
    local icon = R.__icons("player")[1]
    assertEqual(inst.mocks.__layers(icon).strata, "LOW")
    set(inst, "player", "strata", "HIGH")
    assertEqual(inst.mocks.__layers(lane).strata, "HIGH")
    assertEqual(inst.mocks.__layers(icon).strata, "HIGH", "the icon follows its lane")
    set(inst, "player", "strata", "nonsense")
    assertEqual(inst.mocks.__layers(lane).strata, "LOW", "an unknown strata reads as the default")
end)

test("lane render: no absolute SetFrameLevel call (every level is the lane's plus a LAYERS offset)", function()
    local inst, R = setup()
    local LEVEL = inst.NS.Constants.LAYERS.LEVEL
    local lane = R.Get("player")
    local parentLevel = lvl(inst, lane:GetParent())
    assertEqual(lvl(inst, lane), parentLevel + LEVEL.LANE, "the lane: parent + LANE")
    set(inst, "player", "levelOffset", 10)
    assertEqual(lvl(inst, lane), parentLevel + LEVEL.LANE + 10, "plus the level offset")
    for i = 1, 3 do R.Push("player", item(i, 0)) end
    local laneLevel = lvl(inst, lane)
    for i, icon in ipairs(R.__icons("player")) do
        assertEqual(lvl(inst, icon), laneLevel + LEVEL.ICON_BAND - (i - 1), "icon " .. i)
    end
    set(inst, "player", "levelOffset", 0)
    assertEqual(lvl(inst, R.__icons("player")[1]), lvl(inst, lane) + LEVEL.ICON_BAND,
        "a level change carries the live icons with the lane")
end)
