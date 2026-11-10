-- tests/test_hud_sizing.lua — the DPS HUD's size model (v0.2 Task B3, plan decisions D2 and D9,
-- R:hud-sizing#2-#3, Review focus 3): `hud.sizeMode` "fixed" (the default) derives the window's height
-- from `hud.bars` and the configured parts, never from the spell count; the grip (fixed mode only,
-- hidden while locked) sets the width and rounds the height to a whole number of bars, then stores
-- `hud.bars` (1-15); "auto" grows the window with the rows up to `hud.bars` and then scrolls, keeping
-- the top (`hud.grow` "down", the default) or the bottom ("up") in place. The breakdown scrolls with
-- the wheel whenever there are more spells than visible rows, in both modes. Every size read here is
-- one the code set (a recorder over the setter), never a measurement of a value-bearing region.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse
local H = dofile(T.root .. "/tests/hud_fixture.lua")(T)

local ENEMIES = { { name = "Angry Boar", creatureID = 1985, damage = 40000 } }

-- A fight with `n` player spells (ids 1001...), and optionally the pet's two.
local function fightOf(n, pet)
    local spells = {}
    for i = 1, n do spells[i] = { id = 1000 + i, dmg = 1000 * (n - i + 1), dps = 25 * (n - i + 1) } end
    local f = { damage = 40000, dps = 1000, duration = 40, spells = spells, enemies = ENEMIES }
    if pet then
        f.pet = { damage = 8000, dps = 200,
                  spells = { { id = 17253, dmg = 5000, dps = 125 }, { id = 16827, dmg = 3000, dps = 75 } } }
    end
    return f
end

-- The chrome over and under the content (DPS Race's insets) and the stack's pitches (v0.2 Task B2).
local function chrome(inst) return inst.NS.Style.TITLE_BAR_H + 10 + 20 + 8 end
local TOP = 52 + 18 + (46 + 14) + 8          -- clock, target, the boxes with the pet's row, GAP
local PROFILE = 6 + 22 + 16 + 80 + 13 + 2 + 12 + 8   -- HEAD_GAP, heading, pace line, plot, labels, GAP
local function spellsBlock(n) return 6 + 22 + (n > 0 and n * 20 - 2 or 0) + 8 end

-- Record what the code sets on `f` (the kit's frames answer no geometry unless armed).
local function track(f)
    rawset(f, "__points", {})
    rawset(f, "ClearAllPoints", function(self) rawset(self, "__points", {}) end)
    rawset(f, "SetPoint", function(self, ...)
        local list = rawget(self, "__points")
        list[#list + 1] = { ... }
    end)
    rawset(f, "SetSize", function(self, w, h) rawset(self, "__w", w); rawset(self, "__h", h) end)
    rawset(f, "SetWidth", function(self, w) rawset(self, "__w", w) end)
    rawset(f, "SetHeight", function(self, h) rawset(self, "__h", h) end)
    return f
end

-- Fight `id` live from `t0` on `session`, the window tracked and redrawn.
local function liveOn(session, opts)
    opts = opts or {}
    local inst, meter, Hud = H.fresh({ pet = opts.pet })
    for k, v in pairs(opts.hud or {}) do H.setHud(inst, k, v) end
    if opts.best then H.whole(inst, meter, 1, opts.best, 10, 40) end
    H.start(inst, meter, 2, session, 100)
    H.tick(inst, 101.25, 102)
    track(Hud.Frame())
    Hud.Refresh()
    return inst, meter, Hud
end

local function rows(Hud, key) return H.body(Hud, key).parts.spells.list:Rows() end
local function firstID(Hud, key) return rows(Hud, key)[1].spellID end
local function wheel(Hud, delta, key) H.body(Hud, key).parts.spells.frame:__fire("OnMouseWheel", delta) end

-- The grip dragged to `w` x `h` and released (the library reads the released size off the frame).
local function gripTo(Hud, M, w, h)
    local f = Hud.Frame()
    local grip = f.resizeGrip
    grip:__fire("OnMouseDown", "LeftButton")
    M.__now = M.__now + 1 / 60
    f:__fire("OnSizeChanged", w, h)
    f:__setGeom(w, h)
    grip:__fire("OnMouseUp")
end

-- ── the defaults and the rows ───────────────────────────────────────────────────────────────────

test("hud sizing: the defaults are fixed, 5 bars, grow down; spells.rows is retired", function()
    local inst = H.fresh()
    local NS = inst.NS
    local d = NS.defaults.profile.hud
    assertEqual(d.sizeMode, "fixed")
    assertEqual(d.bars, 5)
    assertEqual(d.grow, "down")
    assertEqual(d.spells.rows, nil, "hud.spells.rows retired into hud.bars")
    assertEqual(NS.FindSchemaRow("hud.spells.rows"), nil)
    local bars = NS.FindSchemaRow("hud.bars")
    assertTrue(bars ~= nil, "the Spell bars row")
    assertEqual(bars.min, 1)
    assertEqual(bars.max, 15)
    assertEqual(NS.Hud.MIN_BARS, 1)
    assertEqual(NS.Hud.MAX_BARS, 15)
    local mode, grow = NS.FindSchemaRow("hud.sizeMode"), NS.FindSchemaRow("hud.grow")
    assertTrue(mode ~= nil and grow ~= nil, "the Window size and Grow rows")
    assertTrue(mode.validate("fixed") and mode.validate("auto") and not mode.validate("big"))
    assertTrue(grow.validate("down") and grow.validate("up") and not grow.validate("left"))
    assertEqual(type(grow.disabledIf), "function")
    assertTrue(grow.disabledIf(grow), "Grow is greyed out in fixed mode")
    NS.SetByPath("hud.sizeMode", "auto")
    assertFalse(grow.disabledIf(grow), "and live in auto mode")
    assertEqual(NS.FindSchemaRow("hud.width").max, NS.Hud.MAX_WIDTH)
end)

-- ── fixed mode ──────────────────────────────────────────────────────────────────────────────────

test("hud sizing: the fixed height is derived from the bars, the same with 0, 3 or 20 spells", function()
    local heights = {}
    for _, n in ipairs({ 0, 3, 20 }) do
        local inst, _, Hud = liveOn(fightOf(n))
        local f = Hud.Frame()
        assertEqual(f.__h, chrome(inst) + TOP + PROFILE + spellsBlock(5), n .. " spells: the stack for 5 bars")
        assertEqual(f.__h, Hud.FixedHeight())
        assertEqual(f.__w, 260)
        assertEqual(#rows(Hud), math.min(n, 5), n .. " spells: at most 5 rows")
        heights[#heights + 1] = f.__h
    end
    assertEqual(heights[1], heights[2])
    assertEqual(heights[2], heights[3])
end)

test("hud sizing: every part shown with a pet fills the fixed window exactly", function()
    local inst, _, Hud = liveOn(fightOf(6, true), { pet = true, best = fightOf(6, true) })
    local body = H.body(Hud, "live")
    assertTrue(body.paceShown == true and body.chartShown == true)
    assertEqual(#rows(Hud), 5)
    assertEqual(Hud.Frame().__h, chrome(inst) + body.height, "no blank space and no overflow")
    H.setHud(inst, "bars", 3)
    assertEqual(#rows(Hud), 3)
    assertEqual(Hud.Frame().__h, chrome(inst) + TOP + PROFILE + spellsBlock(3))
    assertEqual(Hud.Frame().__h, chrome(inst) + body.height)
end)

test("hud sizing: a layout part switched off shrinks the fixed height, the bars stay", function()
    local inst, _, Hud = liveOn(fightOf(8))
    H.setHud(inst, "layout.chart", false)
    H.setHud(inst, "layout.pace", false)
    assertEqual(Hud.Frame().__h, chrome(inst) + TOP + spellsBlock(5))
    assertEqual(#rows(Hud), 5)
    H.setHud(inst, "layout.spells", false)
    assertEqual(Hud.Frame().__h, chrome(inst) + TOP, "no rows, no room for them")
    H.setHud(inst, "paceAgainst", "none")
    H.setHud(inst, "layout.spells", true)
    H.setHud(inst, "layout.chart", true)
    H.setHud(inst, "layout.pace", true)
    assertEqual(Hud.Frame().__h, chrome(inst) + TOP + PROFILE - 16 + spellsBlock(5), "no pace line to reserve")
end)

test("hud sizing: a pet appearing mid-fight keeps the fixed height and the bars", function()
    local inst, meter, Hud = liveOn(fightOf(8), { pet = true })
    local f = Hud.Frame()
    local h = f.__h
    assertFalse(Hud.View().hasPet)
    meter.SetSession(2, fightOf(8, true))
    H.tick(inst, 102.25, 103)
    assertTrue(Hud.View().hasPet, "the pet's damage arrived")
    assertEqual(f.__h, h, "the window held its height")
    assertEqual(#rows(Hud), 5, "the pet's row in the boxes was reserved")
end)

test("hud sizing: the fight-over card fits the fixed window, fewer rows and the wheel past them", function()
    local inst, _, Hud = liveOn(fightOf(9), { best = fightOf(9) })
    H.finish(inst, 100, 40)
    assertEqual(Hud.State(), "over")
    local body = H.body(Hud, "over")
    local f = Hud.Frame()
    assertEqual(f.__h, Hud.FixedHeight(), "the same window after the fight")
    assertTrue(body.height <= f.__h - chrome(inst), "the card's stack overflows the window")
    local n = #rows(Hud, "over")
    assertTrue(n >= 1 and n <= 5, "at most the bars: " .. n)
    assertEqual(body.visible, n)
    wheel(Hud, -50, "over")
    assertEqual(body.offset, 9 - n, "held at the last full window")
end)

-- ── the grip ────────────────────────────────────────────────────────────────────────────────────

test("hud sizing: a grip release stores the width and the rounded bars, and the height snaps", function()
    local inst, _, Hud = liveOn(fightOf(20))
    local NS, M = inst.NS, inst.mocks
    local f = Hud.Frame()
    assertTrue(f.resizeGrip ~= nil, "the HUD has the library's grip")
    assertTrue(f.resizeGrip:IsShown())
    local base = chrome(inst) + TOP + PROFILE + spellsBlock(0)
    gripTo(Hud, M, 333.4, base + 7 * 20 + 9)   -- seven and a half bars
    assertEqual(NS.db.profile.hud.bars, 7, "the height rounded down to whole bars")
    assertEqual(NS.db.profile.hud.width, 333)
    assertEqual(f.__h, base + 7 * 20 - 2, "snapped to the seven bars")
    assertEqual(f.__w, 333)
    assertEqual(#rows(Hud), 7)
    gripTo(Hud, M, 100, 40)
    assertEqual(NS.db.profile.hud.bars, 1, "a drag shorter than one bar keeps one")
    assertEqual(NS.db.profile.hud.width, NS.Hud.MIN_WIDTH, "never under the minimum width")
    assertEqual(#rows(Hud), 1)
    gripTo(Hud, M, 2000, 5000)
    assertEqual(NS.db.profile.hud.bars, 15, "a window taller than 15 bars stores 15")
    assertEqual(NS.db.profile.hud.width, NS.Hud.MAX_WIDTH)
    assertEqual(#rows(Hud), 15)
    assertEqual(f.__h, base + 15 * 20 - 2)
end)

test("hud sizing: while the grip is held the rows follow the drag and nothing is stored", function()
    local inst, _, Hud = liveOn(fightOf(20))
    local NS, M = inst.NS, inst.mocks
    local f = Hud.Frame()
    local base = chrome(inst) + TOP + PROFILE + spellsBlock(0)
    local writes = {}
    local set = NS.SetByPath
    NS.SetByPath = function(path, ...) writes[#writes + 1] = path; return set(path, ...) end
    f.resizeGrip:__fire("OnMouseDown", "LeftButton")
    M.__now = M.__now + 1 / 60
    f:__fire("OnSizeChanged", 300, base + 9 * 20)
    assertEqual(#rows(Hud), 9, "nine bars fit the dragged height")
    assertEqual(Hud.View().width, 300 - 24, "the bodies lay out at the dragged width")
    assertEqual(table.concat(writes, ","), "", "stored only on release")
    assertEqual(f.__h, Hud.FixedHeight(), "the drag owns the size: no SetSize while it is held")
    f:__setGeom(300, base + 9 * 20)
    f.resizeGrip:__fire("OnMouseUp")
    NS.SetByPath = set
    assertEqual(table.concat(writes, ","), "hud.width,hud.bars", "the release stores the width and the bars")
    assertEqual(NS.db.profile.hud.bars, 9)
end)

test("hud sizing: the grip's bounds follow the parts shown", function()
    local inst, _, Hud = liveOn(fightOf(3))
    local f = Hud.Frame()
    local b = f.__resizeBounds
    assertEqual(b[1], 260)
    assertEqual(b[2], chrome(inst) + TOP + PROFILE + spellsBlock(1), "one bar at the least")
    assertEqual(b[4], chrome(inst) + TOP + PROFILE + spellsBlock(15), "fifteen at the most")
    H.setHud(inst, "layout.chart", false)
    H.setHud(inst, "layout.pace", false)
    assertEqual(f.__resizeBounds[2], chrome(inst) + TOP + spellsBlock(1))
end)

test("hud sizing: the grip is hidden while locked and in auto mode, and refuses a drag", function()
    local inst, _, Hud = liveOn(fightOf(8))
    local NS = inst.NS
    local f = Hud.Frame()
    local grip = f.resizeGrip
    NS.SetByPath("general.locked", true)
    assertFalse(grip:IsShown(), "hidden while locked")
    grip:__fire("OnMouseDown", "LeftButton")
    assertFalse(NS.Sizing.IsSizing(f), "a locked HUD refuses the drag")
    grip:__fire("OnMouseUp")
    NS.SetByPath("general.locked", false)
    assertTrue(grip:IsShown())
    H.setHud(inst, "sizeMode", "auto")
    assertFalse(grip:IsShown(), "auto mode sizes itself")
    grip:__fire("OnMouseDown", "LeftButton")
    assertFalse(NS.Sizing.IsSizing(f))
    grip:__fire("OnMouseUp")
    H.setHud(inst, "sizeMode", "fixed")
    assertTrue(grip:IsShown())
end)

-- ── the scroll ──────────────────────────────────────────────────────────────────────────────────

test("hud sizing: the wheel scrolls the live rows, clamped, and the note counts them", function()
    local _, _, Hud = liveOn(fightOf(12))
    local body = H.body(Hud, "live")
    local s = body.parts.spells
    assertEqual(#rows(Hud), 5)
    assertEqual(firstID(Hud), 1001)
    assertEqual(s.note:GetText(), "live order \194\183 1-5 of 12")
    assertTrue(s.thumb:IsShown(), "the scroll indicator shows")
    wheel(Hud, -1)
    assertEqual(body.offset, 1)
    assertEqual(firstID(Hud), 1002)
    assertEqual(s.note:GetText(), "live order \194\183 2-6 of 12")
    wheel(Hud, -20)
    assertEqual(body.offset, 7, "held at the last full window")
    assertEqual(firstID(Hud), 1008)
    assertEqual(#rows(Hud), 5)
    assertEqual(s.note:GetText(), "live order \194\183 8-12 of 12")
    wheel(Hud, 50)
    assertEqual(body.offset, 0, "never above the first")
    assertEqual(firstID(Hud), 1001)
end)

test("hud sizing: with every spell in view there is no scroll and no count", function()
    local _, _, Hud = liveOn(fightOf(4))
    local body = H.body(Hud, "live")
    local s = body.parts.spells
    assertEqual(#rows(Hud), 4)
    assertEqual(s.note:GetText(), "live order")
    assertFalse(s.thumb:IsShown())
    wheel(Hud, -3)
    assertEqual(body.offset, 0)
end)

test("hud sizing: zero spells draws no row and keeps the HUD drawable", function()
    local inst, _, Hud = liveOn(fightOf(0))
    assertEqual(#rows(Hud), 0)
    wheel(Hud, -1)
    assertEqual(H.body(Hud, "live").offset, 0)
    H.setHud(inst, "sizeMode", "auto")
    assertEqual(Hud.Frame().__h, chrome(inst) + H.body(Hud, "live").height)
end)

test("hud sizing: a new fight starts its rows at the top", function()
    local inst, meter, Hud = liveOn(fightOf(12))
    wheel(Hud, -4)
    assertEqual(H.body(Hud, "live").offset, 4)
    H.finish(inst, 100, 40)
    H.start(inst, meter, 3, fightOf(12), 300)
    assertEqual(Hud.State() == "live" or Hud.State() == "noBest", true)
    assertEqual(H.body(Hud, "live").offset, 0)
    assertEqual(firstID(Hud), 1001)
end)

-- ── auto mode ───────────────────────────────────────────────────────────────────────────────────

test("hud sizing: auto mode grows with the rows up to the bars, then scrolls", function()
    local heights = {}
    for _, n in ipairs({ 3, 5, 12 }) do
        local inst, _, Hud = liveOn(fightOf(n), { hud = { sizeMode = "auto" } })
        local body = H.body(Hud, "live")
        assertEqual(#rows(Hud), math.min(n, 5))
        assertEqual(Hud.Frame().__h, chrome(inst) + body.height, "the window is the stack")
        heights[n] = body.height
    end
    assertEqual(heights[5] - heights[3], 2 * 20, "two more rows, two more pitches")
    assertEqual(heights[12], heights[5], "past the bars it scrolls instead of growing")
end)

-- The anchor the frame was last placed by.
local function anchor(f) return f.__points[1] end

-- The shell frame's own edges, armed for the anchor read (the only geometry the HUD reads back).
local function edges(f, left, top, bottom)
    rawset(f, "GetLeft", function() return left end)
    rawset(f, "GetTop", function() return top end)
    rawset(f, "GetBottom", function() return bottom end)
end

test("hud sizing: grow down keeps the top in place, grow up the bottom", function()
    local inst, _, Hud = liveOn(fightOf(2), { hud = { sizeMode = "auto" } })
    local NS = inst.NS
    local f, ui = Hud.Frame(), Hud.__ui()
    edges(f, 400.4, 700.6, 300.2)
    ui.drag:__fire("OnDragStop")
    local p = NS.db.profile.hud.position
    assertEqual(p.point, "TOPLEFT", "grow down: the top edge is the anchor")
    assertEqual(p.relPoint, "BOTTOMLEFT")
    assertEqual(p.x, 400)
    assertEqual(p.y, 701)
    assertEqual(anchor(f)[1], "TOPLEFT")
    H.setHud(inst, "grow", "up")
    assertEqual(p.point, "BOTTOMLEFT", "grow up: the bottom edge is the anchor")
    assertEqual(p.relPoint, "BOTTOMLEFT")
    assertEqual(p.y, 300)
    assertEqual(anchor(f)[1], "BOTTOMLEFT")
    assertEqual(anchor(f)[5], 300)
    local before = f.__h
    H.setHud(inst, "layout.target", false)
    assertTrue(f.__h ~= before, "the window changed height")
    assertEqual(anchor(f)[1], "BOTTOMLEFT", "and kept its bottom")
    assertEqual(anchor(f)[5], 300)
end)

test("hud sizing: a stored point that already suits the grow edge is kept", function()
    local inst, _, Hud = liveOn(fightOf(2), { hud = { sizeMode = "auto" } })
    local NS = inst.NS
    local f = Hud.Frame()
    edges(f, 10, 20, 5)
    H.setHud(inst, "grow", "down")
    local p = NS.db.profile.hud.position
    assertEqual(p.point or NS.defaults.profile.hud.position.point, "TOPRIGHT", "the default already grows down")
    Hud.ResetPosition()
    assertEqual(p.point, "TOPRIGHT")
end)

test("hud sizing: switching the mode mid-fight redraws without error", function()
    local inst, _, Hud = liveOn(fightOf(12))
    local f = Hud.Frame()
    local fixed = f.__h
    H.setHud(inst, "sizeMode", "auto")
    assertEqual(f.__h, chrome(inst) + H.body(Hud, "live").height)
    assertEqual(#rows(Hud), 5)
    H.tick(inst, 102.25, 103)
    H.setHud(inst, "sizeMode", "fixed")
    assertEqual(f.__h, fixed)
    H.finish(inst, 100, 40)
    H.setHud(inst, "sizeMode", "auto")
    assertEqual(Hud.State(), "over")
    assertEqual(f.__h, chrome(inst) + H.body(Hud, "over").height)
end)
