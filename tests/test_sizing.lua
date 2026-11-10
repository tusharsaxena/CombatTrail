-- tests/test_sizing.lua — smooth resizing (modules/Sizing.lua, standalone-windows Resizing), the one
-- pattern every resizable window this addon owns sizes by: while the grip is held each size change
-- runs the window's cheap layout, at most once a frame (a second change in one frame waits for one
-- C_Timer.After(0)), and the release runs the full redraw once, then stores the size. A size change
-- the grip did not start redraws at once. The Results window's case drives a 30-frame drag and counts
-- its expensive path, the fight list's rebind (ported from DPS Race @045f479, tests/test_sizing.lua).
-- Each case can fail: under a handler that redraws on every size change, the "no redraw while the
-- grip is held" and the "no rebind" counts go red.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local FRAME = 1 / 60

--- Count the calls to `obj[name]`, still calling through.
local function spy(obj, name)
    local s = { n = 0 }
    local orig = obj[name]
    rawset(obj, name, function(...)
        s.n = s.n + 1
        return orig(...)
    end)
    return s
end

--- `n` size changes, one a frame: the clock moves on a frame before each.
local function drag(M, frame, n, size)
    for k = 1, n do
        M.__now = M.__now + FRAME
        frame:__fire("OnSizeChanged", size(k))
    end
end

-- ── the pattern ─────────────────────────────────────────────────────────────────────────────────

local function bare()
    local i = T.load{}
    local f = i.mocks.CreateFrame("Frame", nil, i.mocks.UIParent)
    f:SetSize(400, 300)
    local c = { size = 0, layout = 0, redraw = 0, done = 0, gate = true }
    i.NS.Sizing.MakeResizable(f, {
        minWidth = 200, minHeight = 100,
        canResize = function() return c.gate end,
        size = function() c.size = c.size + 1 end,
        layout = function() c.layout = c.layout + 1 end,
        redraw = function() c.redraw = c.redraw + 1 end,
        done = function(w, h) c.done, c.w, c.h = c.done + 1, w, h end,
    })
    return i, f, c
end

test("sizing: a size change the grip did not start redraws at once", function()
    local i, f, c = bare()
    assertTrue(f.resizeGrip ~= nil, "no grip")
    f:__fire("OnSizeChanged", 500, 300)
    assertEqual(c.size, 1)
    assertEqual(c.redraw, 1)
    assertEqual(c.layout, 0)
    assertFalse(i.NS.Sizing.IsSizing(f))
end)

test("sizing: while the grip is held, one cheap layout a frame; one redraw on release", function()
    local i, f, c = bare()
    local M = i.mocks
    f.resizeGrip:__fire("OnMouseDown", "LeftButton")
    assertTrue(i.NS.Sizing.IsSizing(f))
    drag(M, f, 30, function(k) return 400 + k, 300 end)
    assertEqual(c.layout, 30, "one cheap layout a frame")
    assertEqual(c.redraw, 0, "no redraw while the grip is held")
    assertEqual(c.size, 30)
    f:__setGeom(430, 300)
    f.resizeGrip:__fire("OnMouseUp")
    assertEqual(c.redraw, 1, "one redraw on release")
    assertEqual(c.done, 1)
    assertEqual(c.w, 430, "the released size is handed on to be stored")
    assertFalse(i.NS.Sizing.IsSizing(f))
end)

test("sizing: changes inside one frame coalesce into one layout now and one next frame", function()
    local i, f, c = bare()
    local M = i.mocks
    M.__now = 10
    f.resizeGrip:__fire("OnMouseDown", "LeftButton")
    for k = 1, 30 do f:__fire("OnSizeChanged", 400 + k, 300) end
    assertEqual(c.layout, 1, "the first change of the frame lays out at once")
    M.__fireTimers()
    assertEqual(c.layout, 2, "the rest, once, on the next frame")
    M.__fireTimers()
    assertEqual(c.layout, 2, "nothing left queued")
    -- A deferred layout the release overtakes does not run after it.
    f:__fire("OnSizeChanged", 450, 300)
    f.resizeGrip:__fire("OnMouseUp")
    local after = c.layout
    M.__fireTimers()
    assertEqual(c.layout, after, "the release's redraw is the last word")
    assertEqual(c.redraw, 1)
end)

test("sizing: a right press or a refused gate starts no drag", function()
    local i, f, c = bare()
    f.resizeGrip:__fire("OnMouseDown", "RightButton")
    assertFalse(i.NS.Sizing.IsSizing(f))
    c.gate = false
    f.resizeGrip:__fire("OnMouseDown", "LeftButton")
    assertFalse(i.NS.Sizing.IsSizing(f), "the gate refused")
    f:__fire("OnSizeChanged", 450, 300)
    assertEqual(c.redraw, 1, "a change outside a drag redraws")
    f.resizeGrip:__fire("OnMouseUp")
    assertEqual(c.done, 0, "a release that ends no drag stores nothing")
end)

test("sizing: a hide while the grip is held ends the drag as a release would", function()
    local i, f, c = bare()
    local M = i.mocks
    f.resizeGrip:__fire("OnMouseDown", "LeftButton")
    drag(M, f, 5, function(k) return 400 + k, 300 + k end)
    assertEqual(c.redraw, 0)
    f:Hide()
    f:__fire("OnHide")
    assertFalse(i.NS.Sizing.IsSizing(f), "the drag outlived the hide")
    assertEqual(c.redraw, 1, "the hide redraws in full")
    assertEqual(c.done, 1)
    assertEqual(c.w, 405, "the last size the drag reached is stored")
    assertEqual(c.h, 305)
    assertEqual(f.__stopCount, 1, "sizing stopped")
    -- A plain hide, with no drag under way, does nothing.
    f:__fire("OnHide")
    assertEqual(c.redraw, 1)
    assertEqual(c.done, 1)
end)

-- ── the Results window ──────────────────────────────────────────────────────────────────────────

local NOW = os.time()

local function seeded()
    local i = T.load{}
    local NS = i.NS
    local me = NS.Identity.Who()
    for k = 1, 40 do
        local ident = { content = "world", targetName = "Angry Boar", targetCreatureID = 1985, difficultyID = 0 }
        NS.Recorder.Save({
            schema = 1, id = "f" .. k, t = NOW - k * 60, duration = 60, status = "final",
            who = { name = me.name, realm = me.realm, client = me.client, class = "MAGE", specID = me.specID },
            identity = ident, boardKey = NS.Identity.BoardKey(ident),
            damage = { merged = 60000 + k }, dps = 1000 + k,
        })
    end
    NS.Results.ShowFight("f1")
    local u = NS.Results.__ui()
    u.list:SetFilter("group", "none")
    return i, u
end

test("results sizing: a 30-frame drag rebinds no row until the release, then stores the size", function()
    local i, u = seeded()
    local NS = i.NS
    local list = u.list.list
    local binds, refreshes = spy(list, "Bind"), spy(u.list, "Refresh")
    local shown = #list:Visible()
    local w0, h0 = u.width, u.height
    local grip = u.frame.resizeGrip
    assertTrue(grip ~= nil, "the Results window has the library's grip")
    grip:__fire("OnMouseDown", "LeftButton")
    drag(i.mocks, u.frame, 30, function(k) return w0 + 4 * k, h0 + 6 * k end)
    assertEqual(binds.n, 0, "a row rebound while the grip is held")
    assertEqual(refreshes.n, 0, "the store re-read while the grip is held")
    assertEqual(u.width, w0 + 120)
    assertEqual(u.height, h0 + 180)
    assertEqual(list.width, w0 + 120 - 1 - (NS.Style.BandGeometry()), "the columns follow the width")
    assertTrue(#list:Visible() > shown, "the taller list shows more rows")
    assertEqual(#list:Visible(), list:visibleCount(), "as many as fit")
    for k, row in ipairs(list:Visible()) do assertTrue(row.record ~= nil, "row " .. k .. " drawn") end
    rawset(u.frame, "GetWidth", function() return w0 + 120 end)
    rawset(u.frame, "GetHeight", function() return h0 + 180 end)
    grip:__fire("OnMouseUp")
    assertEqual(binds.n, 1, "one rebind on release")
    local w = NS.db.profile.results.window
    assertEqual(w.width, w0 + 120, "the size is stored on release")
    assertEqual(w.height, h0 + 180)
end)

test("results sizing: a drag keeps the minimum and shrinks the list without a rebind", function()
    local i, u = seeded()
    local R = i.NS.Results
    local list = u.list.list
    local binds = spy(list, "Bind")
    local shown = #list:Visible()
    u.frame.resizeGrip:__fire("OnMouseDown", "LeftButton")
    drag(i.mocks, u.frame, 30, function() return 300, 200 end)
    assertEqual(u.width, R.MIN_WIDTH, "never under the minimum width")
    assertEqual(u.height, R.MIN_HEIGHT)
    assertTrue(#list:Visible() < shown, "the shorter list shows fewer rows")
    assertEqual(#list:Visible(), list:visibleCount())
    assertEqual(binds.n, 0)
end)
