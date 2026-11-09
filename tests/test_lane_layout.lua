-- tests/test_lane_layout.lua — the lanes' pure layout math (plan Task 1.2, spec §4): where an icon of a
-- given age sits in each of the four directions, the fade over the last part of the window, the GCD
-- reference ticks, the lane's own size and the push-apart that keeps two close casts from overlapping.

local T = _G.CT_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local function near(a, b, msg)
    assertTrue(math.abs(a - b) < 1e-6, (msg or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- Spec §4's defaults: a 480 px lane showing 12 s, so 40 px per second, with 28 px icons.
local function cfg(over)
    local c = { direction = "left", width = 480, seconds = 12, iconSize = 28, spacing = 0, fade = 0.2,
                padding = 0 }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

local function Layout() return T.NS.LaneLayout end

-- ── position ────────────────────────────────────────────────────────────────────────────────────

test("lane layout: left puts the newest icon at the right edge (age 0 -> x 452)", function()
    local x, y = Layout().Position(0, cfg())
    assertEqual(x, 452)
    assertEqual(y, 0)
end)

test("lane layout: left scrolls 40 px a second (age 6 -> x 212)", function()
    local x, y = Layout().Position(6, cfg())
    assertEqual(x, 212)
    assertEqual(y, 0)
end)

test("lane layout: right puts the newest at the left edge and scrolls right (age 6 -> x 240)", function()
    assertEqual((Layout().Position(0, cfg({ direction = "right" }))), 0)
    local x, y = Layout().Position(6, cfg({ direction = "right" }))
    assertEqual(x, 240)
    assertEqual(y, 0)
end)

test("lane layout: up and down mirror left and right on y (TOPLEFT offsets, down is negative)", function()
    local x, y = Layout().Position(0, cfg({ direction = "up" }))
    assertEqual(x, 0)
    assertEqual(y, -452, "up: the newest at the bottom edge")
    x, y = Layout().Position(6, cfg({ direction = "up" }))
    assertEqual(x, 0)
    assertEqual(y, -212)
    x, y = Layout().Position(0, cfg({ direction = "down" }))
    assertEqual(x, 0)
    assertEqual(y, 0, "down: the newest at the top edge")
    x, y = Layout().Position(6, cfg({ direction = "down" }))
    assertEqual(x, 0)
    assertEqual(y, -240)
end)

test("lane layout: an unknown direction reads as left", function()
    assertEqual((Layout().Position(6, cfg({ direction = "sideways" }))), 212)
end)

test("lane layout: an icon is expired once it has scrolled the whole lane", function()
    assertTrue(not Layout().Expired(479, cfg()), "still on the lane")
    assertTrue(Layout().Expired(480, cfg()), "fully past the far edge")
end)

-- ── the push-apart ──────────────────────────────────────────────────────────────────────────────

test("lane layout: a cast close behind the newer one is pushed one icon plus spacing away", function()
    local c = cfg({ spacing = 2 })
    local d1 = Layout().Distance(0, nil, c)
    local d2 = Layout().Distance(0.1, d1, c)
    assertEqual(d1, 0)
    assertEqual(d2, 30, "28 px icon + 2 px spacing, not 4 px")
    local d3 = Layout().Distance(6, d2, c)
    assertEqual(d3, 240, "far enough behind: its own age decides")
end)

-- ── fade ────────────────────────────────────────────────────────────────────────────────────────

test("lane layout: alpha is 1 before the fade and 0.5 halfway through it (fade 0.2)", function()
    near(Layout().Alpha(0, cfg()), 1, "age 0")
    near(Layout().Alpha(9.5, cfg()), 1, "age 9.5, before the last 20%")
    near(Layout().Alpha(10.8, cfg()), 0.5, "age 10.8")
    near(Layout().Alpha(12, cfg()), 0, "age 12")
    near(Layout().Alpha(20, cfg()), 0, "past the window, clamped")
end)

test("lane layout: fade 0 keeps every icon opaque until it leaves", function()
    near(Layout().Alpha(11.9, cfg({ fade = 0 })), 1, "age 11.9")
end)

-- ── ticks ───────────────────────────────────────────────────────────────────────────────────────

test("lane layout: TickOffsets with a 1.5 s GCD gives 8 offsets in 60 px steps", function()
    local t = Layout().TickOffsets(cfg(), 1.5)
    assertEqual(#t, 8)
    for i, px in ipairs(t) do assertEqual(px, 60 * i, "tick " .. i) end
end)

test("lane layout: TickOffsets with a 1 s step gives 12, and nothing for a step of 0 or nil", function()
    assertEqual(#Layout().TickOffsets(cfg(), 1), 12)
    assertEqual(#Layout().TickOffsets(cfg(), 0), 0)
    assertEqual(#Layout().TickOffsets(cfg(), nil), 0)
end)

test("lane layout: TickStep reads the spacing setting and the haste", function()
    assertEqual(Layout().TickStep(cfg({ tickSpacing = "gcd15" }), 50), 1.5)
    assertEqual(Layout().TickStep(cfg({ tickSpacing = "1s" }), 50), 1)
    near(Layout().TickStep(cfg({ tickSpacing = "haste" }), 50), 1.0, "1.5 / 1.5")
    near(Layout().TickStep(cfg({ tickSpacing = "haste" }), 0), 1.5, "no haste")
    near(Layout().TickStep(cfg({ tickSpacing = "haste" }), 300), 0.75, "the GCD floor")
    near(Layout().TickStep(cfg({ tickSpacing = "haste" }), nil), 1.5, "unknown haste")
end)

-- ── size ────────────────────────────────────────────────────────────────────────────────────────

test("lane layout: LaneSize is length by icon, plus the padding, turned for up and down", function()
    local w, h = Layout().LaneSize(cfg())
    assertEqual(w, 480)
    assertEqual(h, 28)
    w, h = Layout().LaneSize(cfg({ padding = 3 }))
    assertEqual(w, 486)
    assertEqual(h, 34)
    w, h = Layout().LaneSize(cfg({ direction = "up", padding = 3 }))
    assertEqual(w, 34)
    assertEqual(h, 486)
end)
