-- tests/test_hud_appearance.lua — every DPS HUD appearance key applies (plan Task 3.2, spec §6 and §8,
-- the mockup's DPS HUD tabs): one case per leaf of `hud.clock`, `hud.figures`, `hud.chart`,
-- `hud.spells` and `hud.window`, each written through the settings seam (Hud.Apply restyles every
-- part) and asserted on the widget it draws. A completeness case holds the case list to the shipped
-- defaults, so a key added to defaults/Profile.lua without a case here fails.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse
local H = dofile(T.root .. "/tests/hud_fixture.lua")(T)
local near = H.near

local MAGE = { r = 0.25, g = 0.78, b = 0.92 }
local RED = { r = 1, g = 0, b = 0, a = 1 }
local WRATH = 31884

local PETFIGHT = { damage = 40000, dps = 1000, duration = 40,
                   spells = { { id = 11366, dmg = 10000, dps = 250 }, { id = 133, dmg = 30000, dps = 750 } },
                   pet = { damage = 8000, dps = 200,
                           spells = { { id = 17253, dmg = 5000, dps = 125 }, { id = 16827, dmg = 3000, dps = 75 } } },
                   enemies = { { name = "Angry Boar", creatureID = 1985, damage = 48000 } } }

-- ── the stage: a stored best, then a live fight with a pet and a long cooldown ──────────────────

local function stage()
    local inst, meter, Hud = H.fresh({ pet = true, mutate = function(m)
        m.RAID_CLASS_COLORS = { MAGE = MAGE }
        m.__baseCooldowns[WRATH] = 120000
    end })
    H.whole(inst, meter, 1, PETFIGHT, 10, 40)
    H.start(inst, meter, 2, PETFIGHT, 100)
    H.cast(inst, 101.5, "player", WRATH)
    H.tick(inst, 101.5, 104)
    return inst, meter, Hud
end

local function media(inst, kind, name)
    local lib = inst.mocks.LibStub("LibKa0s-Media-1.0", true)
    return lib[kind]("CombatTrail", name)
end

local function skinFace(inst)
    return media(inst, "Font", inst.NS.Skin.Resolve("hud.font", nil, true))
end

local function skinBar(inst)
    return media(inst, "Texture", inst.NS.Skin.Resolve("bar.texture", nil, true))
end

local function live(Hud) return H.body(Hud, "live") end
local function rows(Hud) return live(Hud).parts.spells.list:Rows() end
local function chart(Hud) return live(Hud).parts.chart end
local function plainColumn(Hud)
    local view, cols = Hud.View().chartView, chart(Hud):Columns()
    for i = view.count, 1, -1 do
        if not view.burst[i] then return cols[i] end
    end
end
local function burstColumn(Hud) return chart(Hud):Columns()[1] end
local function face(fs) return (fs:GetFont()) end
local function size(fs) return select(2, fs:GetFont()) end
local function flags(fs) return select(3, fs:GetFont()) end
local function rgb(want, r, g, b, msg)
    near(r, want.r, (msg or "") .. " r")
    near(g, want.g, (msg or "") .. " g")
    near(b, want.b, (msg or "") .. " b")
end
local function texture(bar) return bar:GetStatusBarTexture():GetTexture() end

-- A font block's cases (one per key, the shadow's twice) on `fs(Hud)`, in an order that keeps each assertion its own key's.
local function fontCases(block, fs)
    local p = block .. "."
    return {
        { p .. "fontFromSkin", true, function(inst, Hud) assertEqual(face(fs(Hud)), skinFace(inst)) end },
        { p .. "font", "Ka0s Inter", function(inst, Hud)
            assertEqual(face(fs(Hud)), skinFace(inst), "the skin's face while its companion is on")
        end },
        { p .. "fontFromSkin", false, function(inst, Hud)
            assertEqual(face(fs(Hud)), media(inst, "Font", "Ka0s Inter"), "the stored pick")
        end },
        { p .. "fontSize", 17, function(_, Hud) assertEqual(size(fs(Hud)), 17) end },
        { p .. "fontColor", RED, function(inst, Hud)
            local r, g, b = inst.NS.Skin.HudTextColor()
            assertFalse(r == 1 and g == 0 and b == 0, "the skin's HUD text color is not the stored red")
            rgb({ r = r, g = g, b = b }, fs(Hud):GetTextColor())
        end },
        { p .. "fontColorFromSkin", false, function(_, Hud) rgb(RED, fs(Hud):GetTextColor()) end },
        { p .. "useClassColorFont", true, function(_, Hud) rgb(MAGE, fs(Hud):GetTextColor()) end },
        { p .. "fontFlags", "THICKOUTLINE", function(_, Hud) assertEqual(flags(fs(Hud)), "THICKOUTLINE") end },
        { p .. "fontShadow", true, function(inst, Hud)
            -- The skin's answer while the companion is on: none (false, Ka0s Default) or its offset.
            local sx, sy = inst.NS.Skin.HudShadow()
            if sx == false then sx, sy = 0, 0 end
            local x, y = fs(Hud):GetShadowOffset()
            assertTrue(x == sx and y == sy, "the skin's shadow, not the stored one, while its companion is on")
        end },
        { p .. "fontShadowFromSkin", false, function(_, Hud)
            local x, y = fs(Hud):GetShadowOffset()
            assertTrue(x ~= 0 or y ~= 0, "the stored shadow once the companion is off")
        end },
        { p .. "fontShadow", false, function(_, Hud)
            local x, y = fs(Hud):GetShadowOffset()
            assertTrue(x == 0 and y == 0, "and the stored none")
        end },
    }
end

-- A bar block's cases on the StatusBar `bar(Hud)`.
local function barCases(block, bar)
    local p = block .. "."
    return {
        { p .. "barTexture", "Ka0s Matte", function(inst, Hud)
            assertEqual(texture(bar(Hud)), skinBar(inst), "the skin's texture while its companion is on")
        end },
        { p .. "barTextureFromSkin", false, function(inst, Hud)
            assertEqual(texture(bar(Hud)), media(inst, "Texture", "Ka0s Matte"))
        end },
        { p .. "barAlpha", 0.3, function(_, Hud) near(select(4, bar(Hud):GetStatusBarColor()), 0.3) end },
        { p .. "barColor", RED, function(_, Hud) rgb(RED, bar(Hud):GetStatusBarColor()) end },
        { p .. "useClassColorBar", true, function(_, Hud) rgb(MAGE, bar(Hud):GetStatusBarColor()) end },
    }
end

-- A backdrop swatch with its companions on frame `f(Hud)`: `getter` is the frame's color reader.
local function backdropCases(block, key, f, getter)
    local p = block .. "."
    local companion = "useClassColor" .. key:sub(1, 1):upper() .. key:sub(2)
    return {
        { p .. key, RED, function(_, Hud)
            local r, g, b = f(Hud)[getter](f(Hud))
            assertFalse(r == 1 and g == 0 and b == 0, "the skin's paint while " .. key .. "FromSkin is on")
        end },
        { p .. key .. "FromSkin", false, function(_, Hud) rgb(RED, f(Hud)[getter](f(Hud))) end },
        { p .. companion, true, function(_, Hud) rgb(MAGE, f(Hud)[getter](f(Hud))) end },
    }
end

local function join(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, c in ipairs(list) do out[#out + 1] = c end
    end
    return out
end

local function damageText(Hud) return live(Hud).w.damage.value end
local function box(Hud) return live(Hud).w.damage.frame end
local function window(Hud) return Hud.Frame() end
local function rowName(Hud) return rows(Hud)[1].name end
local function playerRowBar(Hud) return rows(Hud)[1].bar end

local LIVE_CASES = join(
    fontCases("clock", function(Hud) return live(Hud).w.clock end),
    fontCases("figures", damageText),
    backdropCases("figures", "boxBg", box, "GetBackdropColor"),
    backdropCases("figures", "boxBorder", box, "GetBackdropBorderColor"),
    {
        { "chart.height", 60, function(inst, Hud)
            assertEqual(chart(Hud).plotH, 60)
            assertEqual(chart(Hud).frameH, 60 + inst.NS.HudChart.RESERVE)
        end },
        { "chart.columns", 8, function(_, Hud)
            local n = Hud.View().chartView.count
            assertTrue(n >= 1 and n <= 8, "at most 8 columns: " .. n)
        end },
    },
    barCases("chart", plainColumn),
    {
        { "chart.burstColor", RED, function(_, Hud) rgb(RED, burstColumn(Hud):GetStatusBarColor()) end },
        { "chart.useClassColorBurstColor", true, function(_, Hud) rgb(MAGE, burstColumn(Hud):GetStatusBarColor()) end },
        { "chart.bestColor", RED, function(_, Hud) rgb(RED, unpack(chart(Hud).line.__color)) end },
        { "chart.useClassColorBestColor", true, function(_, Hud) rgb(MAGE, unpack(chart(Hud).line.__color)) end },
        { "chart.cooldownMin", 200, function(_, Hud) assertEqual(#chart(Hud):Icons(), 0, "Wrath is 120 s") end },
        { "chart.cooldowns", false, function(_, Hud) assertEqual(#chart(Hud):Icons(), 0) end },
        { "chart.zeroLine", false, function(_, Hud) assertFalse(chart(Hud).zero:IsShown()) end },
        { "spells.rows", 1, function(_, Hud) assertEqual(#rows(Hud), 1) end },
        { "spells.rows", 8, function(_, Hud) assertEqual(#rows(Hud), 4) end },
        { "spells.rowHeight", 30, function(_, Hud) assertEqual(rows(Hud)[1].iconSize, 28) end },
        { "spells.icons", false, function(_, Hud) assertFalse(rows(Hud)[1].icon:IsShown()) end },
        { "spells.paw", false, function(_, Hud) assertFalse(rows(Hud)[3].paw:IsShown()) end },
    },
    barCases("spells", playerRowBar),
    {
        { "spells.petColor", RED, function(_, Hud)
            rgb(RED, rows(Hud)[3].bar:GetStatusBarColor())
            rgb(RED, live(Hud).parts.pace.pet:GetStatusBarColor())
        end },
        { "spells.useClassColorPetColor", true, function(_, Hud) rgb(MAGE, rows(Hud)[3].bar:GetStatusBarColor()) end },
    },
    fontCases("spells", rowName),
    {
        { "window.title", false, function(_, Hud)
            assertFalse(Hud.Frame().title:IsShown())
            assertTrue(Hud.__ui().close:IsShown(), "the title bar stays")
        end },
        { "window.titleBar", false, function(_, Hud)
            assertFalse(Hud.__ui().close:IsShown())
            assertFalse(Hud.__ui().drag:IsShown())
        end },
        { "window.footer", false, function(_, Hud) assertFalse(Hud.__ui().footLeft:IsShown()) end },
        { "window.strata", "HIGH", function(_, Hud) assertEqual(Hud.Frame():GetFrameStrata(), "HIGH") end },
        { "window.alpha", 0.5, function(_, Hud) near(Hud.Frame():GetAlpha(), 0.5) end },
    },
    backdropCases("window", "bg", window, "GetBackdropColor"),
    backdropCases("window", "border", window, "GetBackdropBorderColor")
)
-- The over card's own: the DPS figure's color.
local OVER_CASES = {
    { "figures.overColor", RED, function(_, Hud) rgb(RED, H.body(Hud, "over").w.dps.value:GetTextColor()) end },
    { "figures.useClassColorOverColor", true, function(_, Hud)
        rgb(MAGE, H.body(Hud, "over").w.dps.value:GetTextColor())
    end },
}

local function run(inst, Hud, cases)
    for i, c in ipairs(cases) do
        H.setHud(inst, c[1], c[2])
        local ok, err = pcall(c[3], inst, Hud)
        if not ok then error(("case %d (hud.%s = %s): %s"):format(i, c[1], tostring(c[2]), tostring(err)), 0) end
    end
end

test("every hud appearance key applies (one assertion per key via Apply)", function()
    local inst, _, Hud = stage()
    assertEqual(Hud.State(), "live")
    assertTrue(#chart(Hud):Icons() == 1, "Wrath's icon is up before its cases")
    run(inst, Hud, LIVE_CASES)
    H.finish(inst, 100, 40)
    assertEqual(Hud.State(), "over")
    run(inst, Hud, OVER_CASES)
end)

test("appearance: every look key in the defaults has a case", function()
    local inst = H.fresh()
    local covered = {}
    for _, c in ipairs(join(LIVE_CASES, OVER_CASES)) do covered[c[1]] = true end
    local missing = {}
    for _, block in ipairs({ "clock", "figures", "chart", "spells", "window" }) do
        for leaf in pairs(inst.NS.defaults.profile.hud[block]) do
            if not covered[block .. "." .. leaf] then missing[#missing + 1] = block .. "." .. leaf end
        end
    end
    table.sort(missing)
    assertEqual(table.concat(missing, ", "), "", "keys with no case")
end)

test("appearance: Hud.Apply bumps the stamp, so a part restyles once, not on every tick", function()
    local inst, _, Hud = stage()
    local A = inst.NS.HudAppearance
    local before = A.stamp
    Hud.Apply()
    assertEqual(A.stamp, before + 1)
    local row = rows(Hud)[1]
    local calls = 0
    local paint = A.PaintBar
    A.PaintBar = function(...) calls = calls + 1; return paint(...) end
    H.tick(inst, 104.25, 105)
    A.PaintBar = paint
    assertEqual(calls, 0, "no restyle on a tick")
    assertEqual(row.stamp, A.stamp)
end)
