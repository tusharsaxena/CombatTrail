-- tests/test_bar_textures.lua — every bar of data draws the active skin's statusbar texture unless
-- the player picked one (AF-CT-TEX of Ka0sAddonsCommonTasks docs/2026-11-19-ADOPTION_FEEDBACK/, the
-- owner's images 3, 4 and 5: the Results table's and the compare's bars drew flat while the HUD's
-- drew the skin's). One instance in test mode (modules/Preview.lua) fills every window from the
-- sample history; each surface is read under two skins whose `bar.texture` differ, Ka0s Default
-- ("Ka0s Default") and Obsidian ("Ka0s Matte"). The Race window's time bar is held in
-- tests/test_race_window_board.lua, where its running body is built.

local T = _G.CT_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local OWNER = "CombatTrail"
local OTHER = "obsidian"

local inst
local function live()
    if inst then return inst end
    local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")
    inst = T.load{ mutate = function(m)
        installPaint(m)
        m.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    end }
    inst.mocks.__now = 1000
    assert(inst.NS.Preview.Start({ mode = "test" }), "test mode did not start")
    return inst
end

local function skinLib() return live().mocks.LibStub("LibKa0s-Skin-1.0") end

-- The file the skin now in force names for its bars.
local function skinTexture()
    local S = live().NS.Skin
    local key = S.Token("bar.texture")
    return live().mocks.LibStub("LibKa0s-Media-1.0").Texture(OWNER, key)
end

-- What a bar region or StatusBar draws: its fill's file, nil when it draws a flat color.
local function drawnTexture(obj)
    local p = live().mocks.__paint(obj)
    if p.frameType == "StatusBar" then return p.statusBarTexture end
    return p.texture
end

-- ── the surfaces ────────────────────────────────────────────────────────────────────────────────

local function hudBody()
    local NS = live().NS
    local u = assert(NS.Hud.__ui(), "the HUD window was never built")
    return u.body[u.current]
end

local function results()
    local NS = live().NS
    local first = NS.ResultsSource.All()[1]
    assert(first, "no sample fight")
    if NS.Results.Selected() ~= first.id then assert(NS.Results.ShowFight(first.id), "the detail did not open") end
    return assert(NS.Results.__ui(), "the Results window was never built")
end

local function resultsCell(key)
    for _, row in ipairs(results().list.list:Visible()) do
        local cell = row.record and row.cells and row.cells[key]
        if cell and cell.bar and cell.bar:IsShown() then return cell.bar end
    end
    error("no fight row draws a " .. key .. " bar")
end

local function compareUi()
    local NS = live().NS
    assert(NS.ResultsCompare.Open(results().detail), "the compare did not open")
    return NS.ResultsCompare.__ui()
end

local SURFACES = {
    { "the HUD's spell row", function() return hudBody().parts.spells.list:Rows()[1].bar end },
    { "the HUD's chart column", function() return hudBody().parts.chart:Columns()[1] end },
    { "the HUD's pace bar, ahead", function() return hudBody().parts.pace.ahead end },
    { "the HUD's pace bar, behind", function() return hudBody().parts.pace.behind end },
    { "the HUD's pace bar, the red shortfall", function() return hudBody().parts.pace.shortfall end },
    { "the Results table's Damage bar", function() return resultsCell("damage") end },
    { "the Results table's DPS bar", function() return resultsCell("dps") end },
    { "the detail's spell breakdown row", function() return results().detail.w.list:Rows()[1].bar end },
    { "the detail's damage profile column", function() return results().detail.w.chart:Columns()[1] end },
    { "the detail's Targets bar", function() return results().detail.targets.rows[1].bar end },
    { "the compare's this-fight bar", function() return compareUi().rows[1].barA end },
    { "the compare's other-fight bar", function() return compareUi().rows[1].barB end },
}

-- Every window drawn again, as the player would see it after the switch: on the next frame, when the
-- Results detail's coalesced restyle has run (Results.Restyle).
local function redraw()
    local NS = live().NS
    live().mocks.__fireTimers()
    NS.Hud.Refresh()
    results().list:Refresh()
    if results().detail.Refresh then results().detail:Refresh() end
    compareUi()
end

local function withSkin(key, fn)
    local Skin = skinLib()
    local source, skin = Skin:GetChoice(OWNER)
    Skin:SetChoice(OWNER, "ka0s", key)
    local ok, err = pcall(fn)
    Skin:SetChoice(OWNER, source, skin)
    if not ok then error(err, 0) end
end

test("bar textures: the two skins under test name different bar textures", function()
    local Skin = skinLib()
    local seen = {}
    for _, key in ipairs({ Skin.DEFAULT, OTHER }) do
        withSkin(key, function() seen[#seen + 1] = skinTexture() end)
    end
    assertTrue(seen[1] ~= nil and seen[2] ~= nil, "both skins resolve a texture")
    assertTrue(seen[1] ~= seen[2], "Ka0s Default and Obsidian draw different bars")
end)

for _, s in ipairs(SURFACES) do
    test("bar textures: " .. s[1] .. " draws the skin's texture under Ka0s Default and Obsidian", function()
        local Skin = skinLib()
        for _, key in ipairs({ Skin.DEFAULT, OTHER }) do
            withSkin(key, function()
                redraw()
                assertEqual(drawnTexture(s[2]()), skinTexture(), s[1] .. " under " .. key)
            end)
        end
    end)
end

-- The Insights tab's bars of data (SD-SK-CT.1 of Ka0sAddonsCommonTasks docs/2026-11-20-SKIN_DEFAULTS_AUDIT,
-- LibKa0s#97): By Character's first bar, read on the Insights tab, and the Fights tab back after.
local function insightsBar()
    local NS = live().NS
    assert(NS.Results.ShowTab("insights"), "the Insights tab did not open")
    local rows = NS.Results.__ui().insights.ctx:Pool("chars").active
    return assert(rows[1] and rows[1].fill, "By Character draws no bar")
end

test("bar textures: an Insights bar draws the skin's texture under Ka0s Default and Obsidian", function()
    local Skin = skinLib()
    local ok, err = pcall(function()
        for _, key in ipairs({ Skin.DEFAULT, OTHER }) do
            withSkin(key, function()
                assertEqual(drawnTexture(insightsBar()), skinTexture(), "the Insights bar under " .. key)
            end)
        end
    end)
    live().NS.Results.ShowTab("fights")
    if not ok then error(err, 0) end
end)

test("bar textures: a texture the player picked for the HUD's spell rows wins over the skin's", function()
    local NS = live().NS
    local Media = live().mocks.LibStub("LibKa0s-Media-1.0")
    NS.SetByPath("hud.spells.barTextureFromSkin", false)
    NS.SetByPath("hud.spells.barTexture", "Ka0s Forge")
    local ok, err = pcall(function()
        withSkin(OTHER, function()
            redraw()
            local want = Media.Texture(OWNER, "Ka0s Forge")
            assertEqual(drawnTexture(hudBody().parts.spells.list:Rows()[1].bar), want, "the spell row: the pick")
            assertEqual(drawnTexture(hudBody().parts.pace.shortfall), want, "the pace bar's shortfall: the pick")
            -- A surface with no texture setting keeps following the skin.
            assertEqual(drawnTexture(resultsCell("dps")), skinTexture(), "the Results bar: still the skin's")
        end)
    end)
    NS.SetByPath("hud.spells.barTextureFromSkin", true)
    NS.SetByPath("hud.spells.barTexture", "Ka0s Default")
    if not ok then error(err, 0) end
end)

test("bar textures: the Results bars keep the palette's blue in the skin's texture", function()
    local P = live().NS.Constants.PALETTE
    withSkin(OTHER, function()
        redraw()
        local r, g, b, a = resultsCell("damage"):GetVertexColor()
        assertTrue(math.abs(r - P.BAR[1]) < 1e-6 and math.abs(g - P.BAR[2]) < 1e-6 and math.abs(b - P.BAR[3]) < 1e-6,
            "the palette's blue")
        assertTrue(math.abs(a - P.BAR_A) < 1e-6, "at the bars' opacity")
    end)
end)

-- The detail's restyle is the whole pane: a HUD slider dragged with the window open fires
-- HudAppearance.Changed on every tick, so the redraws coalesce to one a frame, and a skin switch runs
-- Changed once, not twice (the review of 2026-11-19, AF-CT-TEX).
local function countDetailShows(fn)
    local NS, M = live().NS, live().mocks
    local detail = results().detail
    M.__fireTimers()
    local shows, show = 0, detail.Show
    detail.Show = function(self, ...) shows = shows + 1; return show(self, ...) end
    local stamp = NS.HudAppearance.stamp
    local ok, err = pcall(fn, NS)
    M.__fireTimers()
    detail.Show = nil   -- the pane's own method again, from its metatable
    if not ok then error(err, 0) end
    return shows, NS.HudAppearance.stamp - stamp
end

test("bar textures: three HUD look changes in one frame redraw the Results detail once", function()
    local shows, changes = countDetailShows(function(NS)
        for _ = 1, 3 do NS.HudAppearance.Changed() end
    end)
    assertEqual(changes, 3, "every change still stamps the HUD's parts")
    assertEqual(shows, 1, "one detail redraw, on the next frame")
end)

test("bar textures: a skin switch runs HudAppearance.Changed once", function()
    local _, changes = countDetailShows(function() withSkin(OTHER, function() end) end)
    -- withSkin switches twice: to Obsidian and back.
    assertEqual(changes, 2, "one Changed per switch")
end)
