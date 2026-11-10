-- tests/test_preview.lua — modules/Preview.lua, test mode (spec §7 "Test mode", preview-mode, plan
-- Task 5.1): sample data in every view. The lanes play the sample rotation, the HUD holds a sample
-- fight's live view still through its own render path, the Results window reads the sample history
-- (modules/MockFights.lua) through its source seam, each window says so with its strip, nothing
-- reaches SavedVariables, and the store comes back when it ends: combat, its own switch, Reset all
-- settings and the stand-down. The sample history's content kinds follow the client (clients-§4).
-- The sim is tests/test_sim.lua.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local function fresh(mutate)
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        if mutate then mutate(m) end
    end }
    inst.mocks.__now = 1000
    return inst.NS, inst.mocks
end

local function snapshot(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = type(v) == "table" and snapshot(v) or v end
    return out
end

local function same(a, b, path)
    for k, v in pairs(a) do
        if type(v) == "table" then same(v, b[k] or {}, path .. "." .. tostring(k))
        else assertEqual(b[k], v, path .. "." .. tostring(k)) end
    end
end

-- Nothing the preview drew reached SavedVariables: no fight, no loadout, no saved view.
local function untouched(NS, view)
    local g = NS.db.global
    assertEqual(next(g.fights or {}), nil, "a sample fight reached the store")
    assertEqual(#(g.fightOrder or {}), 0, "a sample fight reached the store's order")
    assertEqual(next(g.loadouts or {}), nil, "a sample loadout was stored")
    if view then same(view, NS.db.profile.results.view, "results.view") end
end

local function printed(M, line)
    for _, l in ipairs(M.__printed()) do
        if l:find(line, 1, true) then return true end
    end
    return false
end

local function enterCombat(M)
    M.__now = M.__now + 1
    M.InCombatLockdown = function() return true end
    M.__inCombat = true
    M.__fire("PLAYER_REGEN_DISABLED")
end

-- ── the views ───────────────────────────────────────────────────────────────────────────────────

test("preview: test mode fills lanes, HUD and Results with sample strip, nothing written to db", function()
    local NS, M = fresh()
    local view = snapshot(NS.db.profile.results.view)
    NS.ToggleTestMode()
    assertEqual(NS.Preview.Mode(), "test")
    assertTrue(NS.IsTestMode(), "the Master controls' row reads it")
    -- The lanes: the rotation's casts, the player's and the pet's.
    assertTrue(#NS.LaneRender.__icons("player") > 0, "the Player lane plays the sample casts")
    assertTrue(#NS.LaneRender.__icons("pet") > 0, "the Pet lane plays the pet's")
    -- The HUD: the held live view, paced against the sample history's best, with its strip.
    assertTrue(NS.Hud.IsShown(), "test mode shows the HUD")
    assertEqual(NS.Hud.State(), "live", "the held live view, paced")
    local hui = NS.Hud.__ui()
    assertTrue(hui.testStrip ~= nil and hui.testStrip:IsShown(), "the HUD wears the test strip")
    local v = NS.Hud.View()
    assertEqual(v.clock, NS.Preview.STILL_AT, "the clock holds still")
    assertTrue(v.pace ~= nil and v.pace.sample == true, "paced against a sample fight")
    assertTrue(v.chartView ~= nil, "the chart draws")
    assertTrue(v.live and v.live.player and v.live.pet, "the live read has the player and the pet")
    -- The Results window: the sample history, behind its strip.
    assertTrue(NS.Results.IsShown(), "test mode opens the Results window")
    assertTrue(NS.ResultsSource.IsMock())
    local all = NS.ResultsSource.All()
    assertTrue(#all >= (NS.Compat.IsForever() and 15 or 35), "about forty sample fights: " .. #all)
    for _, r in ipairs(all) do assertTrue(r.sample == true, "a sample record") end
    local rui = NS.Results.__ui()
    assertTrue(rui.testStrip ~= nil and rui.testStrip:IsShown(), "the Results window wears the test strip")
    -- Time passes: the lanes keep playing, the HUD stays still and up.
    for _ = 1, 40 do
        M.__now = M.__now + 0.25
        M.__fireTimers()
    end
    assertEqual(NS.Hud.View().clock, NS.Preview.STILL_AT)
    assertTrue(NS.Hud.IsShown(), "a held sample never fades")
    assertTrue(#NS.LaneRender.__icons("player") > 0)
    untouched(NS, view)
    -- Off: every window gives its sample back.
    NS.ToggleTestMode()
    assertEqual(NS.Preview.Mode(), nil)
    assertFalse(NS.ResultsSource.IsMock(), "the store is back")
    assertFalse(NS.Results.IsShown(), "the window test mode opened closes")
    assertFalse(NS.Hud.IsShown(), "the HUD test mode opened closes")
    assertEqual(#NS.LaneRender.__icons("player"), 0, "the sample casts leave the lanes")
    assertEqual(NS.Preview.Diagnose().ticking, false, "no beat left running")
    untouched(NS, view)
end)

test("preview: entering combat ends test mode", function()
    local NS, M = fresh()
    assertTrue(NS.Preview.Start())
    assertTrue(NS.Preview.IsActive())
    M.__resetPrinted()
    enterCombat(M)
    assertFalse(NS.Preview.IsActive(), "combat ends test mode")
    assertTrue(printed(M, "Test mode ended: you entered combat."), "said once")
    assertFalse(NS.ResultsSource.IsMock())
    assertTrue(NS.Hud.View().fight == nil or not NS.Hud.View().fight.sample, "no sample fight on the HUD")
    untouched(NS)
end)

test("preview: refused in combat; a window the player opened stays", function()
    local NS, M = fresh()
    M.__inCombat = true
    M.__resetPrinted()
    assertFalse(NS.Preview.Start())
    assertTrue(printed(M, "Test mode is not available in combat."))
    assertFalse(NS.IsTestMode())
    M.__inCombat = false
    NS.Hud.Show()
    NS.Results.Show()
    assertTrue(NS.Preview.Start())
    NS.Preview.Stop()
    assertTrue(NS.Hud.IsShown(), "the player's HUD stays")
    assertTrue(NS.Results.IsShown(), "the player's Results window stays")
end)

test("preview: Reset all settings and the stand-down end test mode", function()
    local NS = fresh()
    assertTrue(NS.Preview.Start())
    NS.Helpers.RestoreAllDefaults()
    -- The reset profile shows the first-run skin picker again, whose own preview is test mode: the
    -- player's test mode ended (the row's default) before it, so the picker's close ends the picker's.
    NS.HideSkinPicker()
    assertFalse(NS.Preview.IsActive(), "Reset all settings ends it (the row's default)")
    assertTrue(NS.Preview.Start())
    NS.SetByPath("general.enabled", false)
    assertFalse(NS.Preview.IsActive(), "the stand-down ends it")
    assertFalse(NS.ResultsSource.IsMock())
    assertFalse(NS.Hud.IsShown())
    NS.SetByPath("general.enabled", true)
    assertFalse(NS.Preview.IsActive(), "the stand-up does not bring it back")
    assertFalse(NS.Results.IsShown(), "nor the Results window it opened")
end)

-- ── the sample data ─────────────────────────────────────────────────────────────────────────────

test("preview: the sample history spans the client's content kinds (clients-§4)", function()
    local NS = fresh()
    local data = NS.MockFights.Dataset()
    local kinds = {}
    for _, r in ipairs(data.fights) do
        kinds[r.identity.content] = true
        assertTrue(type(r.boardKey) == "string", r.id .. " has a board")
        assertTrue(NS.Recorder.Known(r), r.id .. " is a record this version reads")
    end
    for _, k in ipairs({ "raid", "dungeon", "bg", "world" }) do assertTrue(kinds[k], "content " .. k) end
    for _, k in ipairs({ "mplus", "delve", "arena", "dummy" }) do
        if NS.Compat.IsForever() then
            assertFalse(kinds[k] == true, k .. " is absent on WoW Forever")
        else
            assertTrue(kinds[k], k .. " is present on Retail")
        end
    end
    local chars = {}
    for _, r in ipairs(data.fights) do chars[r.who.name] = true end
    assertTrue(chars.Samplehunter and chars.Mockarrow, "two characters")
    assertTrue(next(data.slices) ~= nil, "some fights carry a chart")
end)

test("preview: a sample fight is the same each time, and its parts agree", function()
    local NS = fresh()
    local a, b = NS.MockFights.Dataset(), NS.MockFights.Dataset()
    assertEqual(a.fights[1].spells, b.fights[1].spells, "seeded: the same spells")
    assertEqual(a.fights[1].casts, b.fights[1].casts, "seeded: the same casts")
    local r = a.fights[1]
    assertEqual(r.damage.merged, r.damage.player + (r.damage.pet or 0), "player plus pet")
    local sum = 0
    for _, sp in ipairs(NS.Recorder.Spells(r)) do sum = sum + sp.total end
    assertEqual(sum, r.damage.merged, "the spells add up to the damage")
    local pets = 0
    for _, c in ipairs(NS.CastCodec.Decode(r.casts)) do if c.unit == "pet" then pets = pets + 1 end end
    assertTrue(pets > 0, "the pet casts too")
    assertTrue(#r.usage.used >= 2, "the trinket or the potion, and the food")
end)

test("preview: the first-run skin picker shows the HUD's sample in the skin, and its close puts it back", function()
    local inst = T.load{ loginPicker = true, mutate = function(m) installPaint(m) end }
    local NS = inst.NS
    assertEqual(NS.Preview.Mode(), "test", "the picker shown with the HUD hidden turns test mode on")
    assertTrue(NS.Hud.IsShown())
    NS.HideSkinPicker()
    assertFalse(NS.Preview.IsActive(), "the picker's close ends what it turned on")
    assertFalse(NS.ResultsSource.IsMock())
end)
