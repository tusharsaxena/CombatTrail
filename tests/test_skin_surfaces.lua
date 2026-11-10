-- tests/test_skin_surfaces.lua — the skin-switch declaration's coverage (skinning-§1 and §9, plan
-- Task 5.2): tests/skin_surfaces.lua, which tests/run.lua hands the kit as Kit.skinSwitch, declares
-- surfaces in every window this addon paints (the DPS HUD, the Results window, the ability timeline,
-- the compare, the gear view and the lanes), each companion it names is a schema row that defaults on
-- (options-ui-§16), and the Lanes page carries the composed skin companions and the From skin flags
-- value. The switch itself is the kit's suite (tests/_kit/test_skin_switch.lua).

local T = _G.CT_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local WINDOWS = { "hud", "results", "timeline", "compare", "gear", "lanes" }

local function facts()
    return dofile(T.root .. "/tests/skin_surfaces.lua")(T)
end

test("skin surfaces: every window has a declared surface", function()
    local seen = {}
    for _, s in ipairs(facts().surfaces) do
        assertTrue(type(s.window) == "string", s.name .. " names no window")
        seen[s.window] = (seen[s.window] or 0) + 1
    end
    for _, w in ipairs(WINDOWS) do
        assertTrue((seen[w] or 0) > 0, "no surface declared for the " .. w .. " window")
    end
end)

test("skin surfaces: the runner hands the kit this declaration", function()
    local src = assert(io.open(T.root .. "/tests/run.lua", "rb")):read("*a")
    assertTrue(src:find("Kit.skinSwitch = dofile(root .. \"/tests/skin_surfaces.lua\")", 1, true) ~= nil,
        "tests/run.lua does not set Kit.skinSwitch from tests/skin_surfaces.lua")
end)

-- Each lane's skin companions: the composer's (the label's face, the two border styles) and this
-- addon's own (every color a skin describes, the label's shadow), each a row defaulting on.
local LANE_COMPANIONS = {
    "labelFontFromSkin", "labelColorFromSkin", "labelShadowFromSkin", "borderTextureFromSkin",
    "borderColorFromSkin", "glowColorFromSkin", "bgColorFromSkin", "laneBorderTextureFromSkin",
    "laneBorderColorFromSkin",
}

test("skin surfaces: every lane companion is a row on the Lanes page, on by default", function()
    local NS = T.NS
    for _, lane in ipairs({ "player", "pet" }) do
        for _, key in ipairs(LANE_COMPANIONS) do
            local path = "lanes." .. lane .. "." .. key
            local row = NS.FindSchemaRow(path)
            assertTrue(row ~= nil, path .. " has no row")
            assertEqual(row.default, true, path .. "'s row default")
            assertEqual(NS.defaults.profile.lanes[lane][key], true, path .. "'s stored default")
            assertEqual(row.page, "lanes", path .. " is not on the Lanes page")
        end
    end
end)

test("skin surfaces: the lane label's Font flags lead with From skin, its default", function()
    local NS = T.NS
    local row = assert(NS.FindSchemaRow("lanes.player.labelOutline"), "no Font flags row")
    assertEqual(row.default, "@skin")
    local values = type(row.values) == "function" and row.values() or row.values
    assertEqual(values["@skin"], "From skin")
    assertEqual(row.sorting and row.sorting[1], "@skin", "From skin is offered first")
end)

test("skin surfaces: each declared companion is a schema row that defaults on", function()
    local NS = T.NS
    local src = assert(io.open(T.root .. "/tests/skin_surfaces.lua", "rb")):read("*a")
    local n = 0
    for path in src:gmatch('writeSetting%("([^"]+)"%)') do
        n = n + 1
        local row = NS.FindSchemaRow(path)
        assertTrue(row ~= nil, path .. " has no row")
        assertEqual(row.default, true, path)
    end
    assertTrue(n > 0, "no companion declared")
end)
