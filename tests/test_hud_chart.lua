-- tests/test_hud_chart.lua — the DPS HUD's damage chart (plan Task 3.2, spec §6): one column per
-- time bucket of the fight's in-session slices (modules/Slices.lua), each handed the player's total
-- captured at its step (the meter's secret, untouched), scaled to the paced best's player damage
-- (plain) or, with no best, to the live total itself; the best's line; the cooldown icons for every
-- cast whose base cooldown is at least `hud.chart.cooldownMin` (29 s) and the burst columns after
-- them; and the fight-over card's chart from the same store.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local H = dofile(T.root .. "/tests/hud_fixture.lua")(T)
local near = H.near

local FIGHT = { damage = 40000, dps = 1000, duration = 40,
                spells = { { id = 133, dmg = 30000, dps = 750 }, { id = 11366, dmg = 10000, dps = 250 } },
                enemies = { { name = "Angry Boar", creatureID = 1985, damage = 40000 } } }

local WRATH, BARRIER, NEARLY, FIREBALL = 31884, 12472, 5143, 133

local function chartOf(Hud, key)
    return H.body(Hud, key).parts.chart
end

local function iconIDs(chart)
    local out = {}
    for i, icon in ipairs(chart:Icons()) do out[i] = icon.cast.spellID end
    return table.concat(out, ",")
end

test("chart cooldown icons for base CD >= 29 s", function()
    local inst, meter, Hud = H.fresh({ mutate = function(m)
        m.__baseCooldowns[WRATH] = 120000
        m.__baseCooldowns[BARRIER] = 29000
        m.__baseCooldowns[NEARLY] = 28000
    end })
    H.start(inst, meter, 1, FIGHT, 10)
    H.cast(inst, 11.5, "player", WRATH)
    H.cast(inst, 12, "player", FIREBALL)
    H.cast(inst, 14, "player", NEARLY)
    H.cast(inst, 16, "player", BARRIER)
    H.tick(inst, 16.25, 18)
    local chart = chartOf(Hud, "live")
    assertTrue(chart ~= nil and chart.plot:IsShown(), "the chart is up")
    assertEqual(iconIDs(chart), WRATH .. "," .. BARRIER, "only the long cooldowns, in time order (29 s counts)")
    for _, icon in ipairs(chart:Icons()) do
        assertEqual(icon.frame.tex:GetTexture(), 136000 + icon.cast.spellID, "the spell's own icon")
    end

    -- The burst window: the column Wrath was cast in draws in the burst color.
    local view = Hud.View().chartView
    local col = math.floor(1.5 / view.step) + 1
    assertTrue(view.burst[col] == true, "Wrath's column is a burst column")
    local want = inst.NS.db.profile.hud.chart.burstColor
    local r, g, b = chart:Columns()[col]:GetStatusBarColor()
    near(r, want.r)
    near(g, want.g)
    near(b, want.b)

    H.setHud(inst, "chart.cooldownMin", 100)
    assertEqual(iconIDs(chart), tostring(WRATH), "the threshold is the setting's")
    H.setHud(inst, "chart.cooldowns", false)
    assertEqual(iconIDs(chart), "", "icons off")
end)

test("chart: unchanged cooldown icons are not laid again on the next ticks", function()
    local inst, meter, Hud = H.fresh({ mutate = function(m) m.__baseCooldowns[WRATH] = 120000 end })
    H.start(inst, meter, 1, FIGHT, 10)
    H.cast(inst, 11.5, "player", WRATH)
    H.tick(inst, 16.25, 18)
    local chart = chartOf(Hud, "live")
    local first = chart:Icons()[1]
    assertTrue(first ~= nil, "Wrath's icon is up")
    local moved = 0
    local setPoint = first.frame.SetPoint
    first.frame.SetPoint = function(...) moved = moved + 1; return setPoint(...) end
    H.tick(inst, 16.5, 18)
    H.tick(inst, 17.75, 18)
    assertEqual(moved, 0, "same casts, span and geometry: the icon stays where it is")
    assertTrue(chart:Icons()[1] == first, "the same icon entry")
    H.cast(inst, 18, "player", WRATH)
    H.tick(inst, 19.25, 20)
    assertEqual(iconIDs(chart), WRATH .. "," .. WRATH, "a new cast lays them again")
end)

test("chart: the HUD and the slices share one live read on a boundary tick", function()
    local inst, meter = H.fresh()
    H.start(inst, meter, 1, FIGHT, 10)
    local function reads()
        local n = 0
        for _, c in ipairs(meter.CallsTo("GetCombatSessionSourceFromID")) do
            if c.args[3] == inst.mocks.UnitGUID("player") then n = n + 1 end
        end
        return n
    end
    local most, t = 0, 11.5
    while t <= 16 do
        local before = reads()
        H.run(inst, t)
        most = math.max(most, reads() - before)
        t = t + 0.25
    end
    assertEqual(most, 1, "one player source read per tick, boundary or not")
    assertTrue(#inst.NS.Slices.Columns(inst.NS.Fight.Current().id, 6, 10).values > 0, "the slices still filled")
end)

test("chart: live columns are the slices, scaled to the best's player damage", function()
    local inst, meter, Hud = H.fresh()
    H.whole(inst, meter, 1, FIGHT, 10, 40)
    meter.SetSession(2, FIGHT)
    H.enter(inst, 100)
    meter.SetSecret(true)
    H.run(inst, 100.25)
    H.hit(inst, 101, 2)
    H.tick(inst, 101.25, 105)
    local view = Hud.View().chartView
    assertEqual(view.span, 40, "the chart spans the best's 40 s while the fight is shorter")
    assertEqual(view.count, 20, "one column per 2 s step")
    local chart = chartOf(Hud, "live")
    local cols = chart:Columns()
    local value = cols[1]:GetValue()
    assertTrue(T.isSecret(value), "a column holds the total captured at its step, secret")
    assertEqual(T.reveal(value), 40000)
    local _, max = cols[1]:GetMinMaxValues()
    near(max, 40000 * inst.NS.HudChart.HEADROOM, "the best's player damage at the chart's end, plain")
    assertTrue(chart.line:IsShown(), "the best's line")
    near(view.best, 1 / inst.NS.HudChart.HEADROOM)
    assertEqual(cols[10]:GetValue(), 0, "a step still to come is empty")
    meter.SetSecret(false)

    -- The over card: the same store over the fight's length, scaled to the plain final damage.
    H.finish(inst, 100, 40)
    local over = Hud.View().chartView
    assertTrue(over ~= nil, "the over card draws the fight's chart")
    local ocols = chartOf(Hud, "over"):Columns()
    _, max = ocols[1]:GetMinMaxValues()
    near(max, 40000 * inst.NS.HudChart.HEADROOM)
end)

test("chart: with no best the scale is the live total itself, and no line", function()
    local inst, meter, Hud = H.fresh()
    meter.SetSession(1, FIGHT)
    H.enter(inst, 10)
    meter.SetSecret(true)
    H.run(inst, 10.25)
    H.hit(inst, 11, 1)
    H.tick(inst, 11.25, 15)
    assertEqual(Hud.State(), "noBest")
    local chart = chartOf(Hud, "live")
    local _, max = chart:Columns()[1]:GetMinMaxValues()
    assertTrue(T.isSecret(max), "SetMinMaxValues took the secret live total")
    assertFalse(chart.line:IsShown())
    assertNil(Hud.View().chartView.best)
    meter.SetSecret(false)
end)

test("chart: hud.chart.columns caps the columns; the layout's chart off hides it", function()
    local inst, meter, Hud = H.fresh()
    H.start(inst, meter, 1, FIGHT, 10)
    H.tick(inst, 11.5, 50)
    local view = Hud.View().chartView
    assertTrue(view.count <= 48, "at most the shipped 48")
    H.setHud(inst, "chart.columns", 8)
    view = Hud.View().chartView
    assertTrue(view.count <= 8, "at most 8: " .. view.count)
    H.setHud(inst, "layout.chart", false)
    assertFalse(chartOf(Hud, "live").plot:IsShown())
end)

test("chart: the pure layout helpers", function()
    local inst = H.fresh()
    local Chart = inst.NS.HudChart
    local xs, widths = Chart.ColumnEdges(100, 3)
    assertEqual(table.concat(xs, ","), "0,33,67")
    assertEqual(table.concat(widths, ","), "33,34,33")
    local rows, marks = Chart.IconRows({ 10, 12, 14, 40 }, 2)
    assertEqual(rows[1], 1)
    assertEqual(rows[4], 1)
    assertEqual(#marks, 1, "two crowded casts on the overflow row become one mark")
    assertEqual(#marks[1].members, 2)
    local burst = Chart.BurstColumns({ { t = 3 } }, 2, 20)
    assertTrue(burst[2] and burst[10] and not burst[1] and not burst[11], "from the cast's column to the one starting 15 s after it")
end)
