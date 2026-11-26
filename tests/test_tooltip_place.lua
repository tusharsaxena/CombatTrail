-- tests/test_tooltip_place.lua — where every tooltip this addon places itself opens (LibKa0s#92, item
-- AD-92-CT; WowAddonStandards standalone-windows, *Tooltip placement*). modules/Style.lua's seam onto
-- LibKa0s-Tooltip-1.0 (Style.OwnTip, Style.PlaceBody, Style.PlaceChrome, Style.TipGroup) on the kit's
-- fake screen (tests/_kit/mock_screen.lua), then every hover the addon's windows carry:
--
--   * the body rule: beside the window group, right when it fits and else left, its top level with
--     the hovered element's top, TIP_GAP (2 px) off the group's outer edge;
--   * the chrome rule: centered on the control, TIP_GAP above it, below only without room above;
--   * the window group: the DPS HUD and the attached Race window are one group, the HUD its main
--     frame, so a Race window row's tooltip opens on the Race window's side away from the HUD;
--   * the fallback, with no placer or unreadable geometry: attached above the element, never the cursor;
--   * the sweep: test mode fills the HUD, the lanes and the Results window, the Race window, the fight
--     detail, the compare, the gear view, the ability timeline and the Insights tab are opened, and
--     every frame's OnEnter is fired. Each tooltip it shows is owned at ANCHOR_NONE (never a cursor
--     or corner anchor) and placed by a placer or the fallback, and each named surface by its rule.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")
local installScreen = dofile(T.root .. "/tests/_kit/mock_screen.lua")

local GAP = 2

local function fresh(mutate)
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        m.StaticPopup_Show = function() end
        m.StaticPopup_Hide = function() end
        if mutate then mutate(m) end
    end }
    inst.mocks.__now = 1000
    return inst.NS, inst.mocks
end

local function retail(NS) return not NS.Compat.IsForever() end

local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

-- ── the seam on the fake screen ─────────────────────────────────────────────────────────────────

test("tooltip seam: a body tooltip opens right of its window, level with the row, 2 px off", function()
    local NS, M = fresh()
    local scr = installScreen(M, { width = 1920, height = 1080 })
    local win = scr.frame{ left = 300, bottom = 300, width = 400, height = 500 }
    local row = scr.frame{ left = 310, bottom = 600, width = 380, height = 20, parent = win }
    local tip = scr.tooltip{ width = 250, height = 90 }
    NS.Style.OwnTip(tip, row)
    assertEqual(tip.__anchor, "ANCHOR_NONE", "owned at ANCHOR_NONE")
    assertEqual(NS.Style.PlaceBody(tip, row), "right")
    local l, _, _, t = scr.rectOf(tip)
    assertTrue(near(l, 700 + GAP), "its left 2 px right of the window's right edge: " .. tostring(l))
    assertTrue(near(t, 620), "its top level with the row's top: " .. tostring(t))
    scr.restore()
end)

test("tooltip seam: a body tooltip with no room on the right opens left of the window", function()
    local NS, M = fresh()
    local scr = installScreen(M, { width = 1920, height = 1080 })
    local win = scr.frame{ left = 1500, bottom = 300, width = 400, height = 500 }
    local row = scr.frame{ left = 1510, bottom = 580, width = 380, height = 20, parent = win }
    local tip = scr.tooltip{ width = 250, height = 90 }
    NS.Style.OwnTip(tip, row)
    assertEqual(NS.Style.PlaceBody(tip, row), "left")
    local _, _, r, t = scr.rectOf(tip)
    assertTrue(near(r, 1500 - GAP), "its right 2 px left of the window's left edge: " .. tostring(r))
    assertTrue(near(t, 600), "its top level with the row's top: " .. tostring(t))
    scr.restore()
end)

test("tooltip seam: a chrome tooltip is centered 2 px above its control, below only at the top", function()
    local NS, M = fresh()
    local scr = installScreen(M, { width = 1920, height = 1080 })
    local win = scr.frame{ left = 300, bottom = 300, width = 400, height = 500 }
    local btn = scr.frame{ left = 400, bottom = 760, width = 60, height = 20, parent = win }
    local tip = scr.tooltip{ width = 200, height = 60 }
    NS.Style.OwnTip(tip, btn)
    assertEqual(NS.Style.PlaceChrome(tip, btn), "above")
    local l, b, r = scr.rectOf(tip)
    assertTrue(near(b, 780 + GAP), "its bottom 2 px above the control: " .. tostring(b))
    assertTrue(near((l + r) / 2, 430), "centered on the control")
    btn:__place(400, 1040, 60, 20)   -- no room above: below
    assertEqual(NS.Style.PlaceChrome(tip, btn), "below")
    local _, _, _, t = scr.rectOf(tip)
    assertTrue(near(t, 1040 - GAP), "its top 2 px under the control: " .. tostring(t))
    scr.restore()
end)

test("tooltip seam: unreadable geometry attaches the tooltip above the element, never the cursor", function()
    local NS, M = fresh()
    local el = M.CreateFrame("Frame", nil, M.UIParent)   -- the base answers no geometry: unreadable
    local points, owner = {}, {}
    local tip = M.GameTooltip
    rawset(tip, "SetOwner", function(_, o, a) owner = { o, a } end)
    rawset(tip, "SetPoint", function(_, ...) points[#points + 1] = { ... } end)
    NS.Style.OwnTip(tip, el)
    assertEqual(owner[2], "ANCHOR_NONE")
    assertEqual(NS.Style.PlaceBody(tip, el), "attached", "the body placer's fallback")
    assertEqual(NS.Style.PlaceChrome(tip, el), "attached", "the chrome placer's fallback")
    for _, p in ipairs(points) do
        assertTrue(p[1] == "BOTTOM" and p[2] == el and p[3] == "TOP" and p[4] == 0 and p[5] == GAP,
            "attached centered 2 px above the element: " .. table.concat({ tostring(p[1]), tostring(p[3]) }, " "))
    end
    assertEqual(#points, 2)
    rawset(tip, "SetOwner", nil)
    rawset(tip, "SetPoint", nil)
end)

-- The DPS HUD and the Race window attached on its right, each a fake-screen frame (Retail: WoW
-- Forever has no Race window, so its HUD is a group of one, the last case below).
local function attachedPair(NS, scr)
    local hud = scr.frame{ left = 400, bottom = 400, width = 300, height = 300 }
    local rw = scr.frame{ left = 700, bottom = 400, width = 300, height = 300 }
    local hudFrame, rwFrame, attached = NS.Hud.Frame, NS.RaceWindow.Frame, NS.RaceWindow.IsAttached
    NS.Hud.Frame = function() return hud end
    NS.RaceWindow.Frame = function() return rw end
    NS.RaceWindow.IsAttached = function() return true end
    return hud, rw, function()
        NS.Hud.Frame, NS.RaceWindow.Frame, NS.RaceWindow.IsAttached = hudFrame, rwFrame, attached
        scr.restore()
    end
end

test("tooltip seam: the HUD and the attached Race window are one group, the HUD its main frame", function()
    local NS, M = fresh()
    if not retail(NS) then return end
    local scr = installScreen(M, { width = 1920, height = 1080 })
    local hud, rw, restore = attachedPair(NS, scr)
    local hudRow = scr.frame{ left = 410, bottom = 600, width = 280, height = 20, parent = hud }
    local rwRow = scr.frame{ left = 710, bottom = 500, width = 280, height = 20, parent = rw }
    local g = NS.Style.TipGroup(rwRow)
    assertTrue(type(g) == "table" and g.main == hud and g.panels[1] == rw, "{ main = HUD, panels = { Race window } }")
    assertTrue(NS.Style.TipGroup(hudRow).main == hud, "the HUD's own rows read the same group")
    local tip = scr.tooltip{ width = 250, height = 90 }
    NS.Style.OwnTip(tip, hudRow)
    assertEqual(NS.Style.PlaceBody(tip, hudRow), "right")
    local l = scr.rectOf(tip)
    assertTrue(near(l, 1000 + GAP), "a HUD row's tooltip opens past the Race window, outside the group: " .. tostring(l))
    -- Detached, the Race window is its own window again.
    NS.RaceWindow.IsAttached = function() return false end
    assertTrue(NS.Style.TipGroup(rwRow) == rw, "detached: the Race window alone")
    assertTrue(NS.Style.TipGroup(hudRow) == hud, "detached: the HUD alone")
    restore()
end)

test("tooltip seam: an attached Race window on the HUD's left opens its row tooltips on its left", function()
    local NS, M = fresh()
    if not retail(NS) then return end
    local scr = installScreen(M, { width = 1920, height = 1080 })
    local hud, rw, restore = attachedPair(NS, scr)
    hud:__place(1000, 400, 300, 300)
    rw:__place(700, 400, 300, 300)
    local rwRow = scr.frame{ left = 710, bottom = 500, width = 280, height = 20, parent = rw }
    local tip = scr.tooltip{ width = 250, height = 90 }
    NS.Style.OwnTip(tip, rwRow)
    assertEqual(NS.Style.PlaceBody(tip, rwRow), "left", "the companion's side away from the HUD")
    local _, _, r, t = scr.rectOf(tip)
    assertTrue(near(r, 700 - GAP), "2 px left of the Race window: " .. tostring(r))
    assertTrue(near(t, 520), "level with the row")
    restore()
end)

test("tooltip seam: with no Race window (WoW Forever), the HUD is a group of one", function()
    local NS, M = fresh()
    local scr = installScreen(M, { width = 1920, height = 1080 })
    local hud = scr.frame{ left = 400, bottom = 400, width = 300, height = 300 }
    local row = scr.frame{ left = 410, bottom = 600, width = 280, height = 20, parent = hud }
    local hudFrame, RW = NS.Hud.Frame, NS.RaceWindow
    NS.Hud.Frame = function() return hud end
    NS.RaceWindow = nil
    assertTrue(NS.Style.TipGroup(row) == hud, "the HUD alone")
    NS.Hud.Frame, NS.RaceWindow = hudFrame, RW
    scr.restore()
end)

-- The cast lanes, docked one on the other (LaneAnchor mode "dock"): the docked lane moves with its
-- host, so the two are one window group, the host lane its main frame (standalone-windows, *Window
-- group*: a HUD display's group is the whole display). Each lane a fake-screen frame.
local function dockedLanes(NS, scr, hostLeft, dockedLeft)
    local player = scr.frame{ left = hostLeft, bottom = 400, width = 300, height = 40 }
    local pet = scr.frame{ left = dockedLeft, bottom = 400, width = 300, height = 40 }
    local LR, LA = NS.LaneRender, NS.LaneAnchor
    local get, find, resolve = LR.Get, LR.Find, LA.ResolveHost
    local frames = { player = player, pet = pet }
    LR.Get = function(key) return frames[key] end
    LR.Find = function(key) return frames[key] end
    LA.ResolveHost = function(key)
        if key == "pet" then return player, "dock" end
        return nil, "free"
    end
    return player, pet, function()
        LR.Get, LR.Find, LA.ResolveHost = get, find, resolve
        scr.restore()
    end
end

test("tooltip seam: a lane docked beside the other lane joins its group, so a lane icon's tooltip covers neither", function()
    local NS, M = fresh()
    local scr = installScreen(M, { width = 1920, height = 1080 })
    -- The Pet lane docked LEFT on the Player lane's RIGHT, side by side.
    local player, pet, restore = dockedLanes(NS, scr, 400, 700)
    local icon = scr.frame{ left = 410, bottom = 405, width = 30, height = 30, parent = player }
    local petIcon = scr.frame{ left = 710, bottom = 405, width = 24, height = 24, parent = pet }
    local g = NS.Style.TipGroup(icon)
    assertTrue(type(g) == "table" and g.main == player and g.panels[1] == pet,
        "{ main = the host lane, panels = { the docked lane } }")
    local gp = NS.Style.TipGroup(petIcon)
    assertTrue(type(gp) == "table" and gp.main == player and gp.panels[1] == pet, "the docked lane's icons read the same group")
    local tip = scr.tooltip{ width = 250, height = 90 }
    NS.Style.OwnTip(tip, icon)
    assertEqual(NS.Style.PlaceBody(tip, icon), "right")
    local l, _, _, t = scr.rectOf(tip)
    assertTrue(near(l, 1000 + GAP), "a Player lane icon's tooltip opens past the docked Pet lane: " .. tostring(l))
    assertTrue(near(t, 435), "level with the icon: " .. tostring(t))
    -- The docked lane hidden (its visibility off): the host lane is a group of one again.
    pet:Hide()
    assertTrue(NS.Style.TipGroup(icon) == player, "a hidden docked lane is not in the group")
    restore()
end)

test("tooltip seam: the default dock (Pet under Player) is one group; a free Pet lane is its own", function()
    local NS, M = fresh()
    local scr = installScreen(M, { width = 1920, height = 1080 })
    local player, pet, restore = dockedLanes(NS, scr, 400, 400)
    pet:__place(400, 356, 360, 40)   -- under the Player lane and wider than it
    local icon = scr.frame{ left = 410, bottom = 405, width = 30, height = 30, parent = player }
    local tip = scr.tooltip{ width = 250, height = 90 }
    NS.Style.OwnTip(tip, icon)
    assertEqual(NS.Style.PlaceBody(tip, icon), "right")
    local l = scr.rectOf(tip)
    assertTrue(near(l, 760 + GAP), "outside the wider docked Pet lane too: " .. tostring(l))
    NS.LaneAnchor.ResolveHost = function() return nil, "free" end
    assertTrue(NS.Style.TipGroup(icon) == player, "undocked: the Player lane alone")
    restore()
end)

-- ── the sweep ───────────────────────────────────────────────────────────────────────────────────

-- Record every frame the build makes, in creation order.
local function recorder()
    local made = {}
    return made, function(m)
        local create = m.CreateFrame
        m.CreateFrame = function(...)
            local f = create(...)
            made[#made + 1] = f
            return f
        end
    end
end

-- Spy the game tooltip's owner calls and points, and the placers (read at call time by the seam and
-- the library's own sites alike).
local function spy(M)
    local Tip = M.LibStub("LibKa0s-Tooltip-1.0")
    local log = { owners = {}, points = {}, placed = {} }
    local tip = M.GameTooltip
    rawset(tip, "SetOwner", function(self, owner, anchor)
        log.owners[#log.owners + 1] = { owner, anchor }
        self.__shown = false
    end)
    rawset(tip, "SetPoint", function(_, ...) log.points[#log.points + 1] = { ... } end)
    local beside, attached = Tip.PlaceBeside, Tip.PlaceAttached
    Tip.PlaceBeside = function(t, el, group, ...)
        log.placed[#log.placed + 1] = { "beside", el, group }
        return beside(t, el, group, ...)
    end
    Tip.PlaceAttached = function(t, el, ...)
        log.placed[#log.placed + 1] = { "attached", el }
        return attached(t, el, ...)
    end
    function log.reset()
        log.owners, log.points, log.placed = {}, {}, {}
    end
    function log.restore()
        Tip.PlaceBeside, Tip.PlaceAttached = beside, attached
        rawset(tip, "SetOwner", nil)
        rawset(tip, "SetPoint", nil)
    end
    return log
end

-- Open every window this addon draws on test mode's sample data (the Race window on Retail).
local function openAll(NS)
    NS.ToggleTestMode()
    assertTrue(NS.Hud.IsShown() and NS.Results.IsShown(), "test mode shows the HUD and the Results window")
    if retail(NS) then NS.SetRaceWindowShown("show") end
    local first = NS.ResultsSource.All()[1]
    assertTrue(first ~= nil and NS.Results.ShowFight(first.id), "the fight detail opens on a sample fight")
    local pane = NS.Results.__ui().detail
    if pane.w.compare:IsEnabled() then pane.w.compare:__fire("OnClick") end
    NS.ResultsGear.Open(pane)
    NS.ResultsTimeline.Open(pane)
    return pane
end

-- Fire `f`'s OnEnter (and OnLeave after); answers what the hover did: nil when it showed nothing.
local function hover(M, log, f)
    log.reset()
    M.GameTooltip.__shown = false
    local ok = pcall(f.__fire, f, "OnEnter")
    local out = ok and M.GameTooltip.__shown and #log.owners > 0 and {
        owners = log.owners, points = log.points, placed = log.placed,
    } or nil
    pcall(f.__fire, f, "OnLeave")
    return out
end

local CORNER_OR_CURSOR = {
    ANCHOR_CURSOR = true, ANCHOR_CURSOR_RIGHT = true, ANCHOR_CURSOR_LEFT = true, ANCHOR_RIGHT = true,
    ANCHOR_LEFT = true, ANCHOR_TOP = true, ANCHOR_BOTTOM = true, ANCHOR_TOPLEFT = true,
    ANCHOR_TOPRIGHT = true, ANCHOR_BOTTOMLEFT = true, ANCHOR_BOTTOMRIGHT = true,
    ANCHOR_PRESERVE = true,
}

test("tooltip sweep: every hover on every window is owned at ANCHOR_NONE and placed, never by the cursor", function()
    local made, mutate = recorder()
    local NS, M = fresh(mutate)
    openAll(NS)
    NS.Results.ToggleView()   -- the Insights tab: its charts' marks and boards
    local log = spy(M)
    local shown = 0
    for _, f in ipairs(made) do
        if type(f.GetScript) == "function" and f:GetScript("OnEnter") then
            local h = hover(M, log, f)
            if h then
                shown = shown + 1
                for _, o in ipairs(h.owners) do
                    assertTrue(not CORNER_OR_CURSOR[o[2]], "a hover owned its tooltip at " .. tostring(o[2]))
                    assertEqual(o[2], "ANCHOR_NONE", "a hover's tooltip is owned at ANCHOR_NONE")
                end
                assertTrue(#h.placed > 0 or #h.points > 0, "a shown tooltip is placed")
                for _, p in ipairs(h.points) do
                    -- Placed on UIParent by the library, or the fallback: BOTTOM on an element's TOP.
                    local onScreen = p[2] == M.UIParent and p[3] == "BOTTOMLEFT"
                    local above = p[1] == "BOTTOM" and p[3] == "TOP"
                    assertTrue(onScreen or above, "a tooltip anchored " .. tostring(p[1]) .. " on " .. tostring(p[3]))
                end
            end
        end
    end
    log.restore()
    assertTrue(shown >= 40, "the sweep reached the windows' hovers: " .. shown .. " tooltips shown")
end)

-- The placer one hover called first: "beside" or "attached", and its element and group.
local function placedBy(M, log, f)
    local h = hover(M, log, f)
    assertTrue(h ~= nil, "the hover shows a tooltip")
    return h.placed[1] or {}
end

test("tooltip surfaces: body elements open beside their window, chrome controls above themselves", function()
    local NS, M = fresh()
    local pane = openAll(NS)
    local log = spy(M)
    local R = NS.Results.__ui()
    -- Chrome: the fight list's filter bar and the detail's Back, its toolbar between the title bar
    -- and the scrolled detail.
    NS.Results.Show()
    local list = R.list
    local pb = placedBy(M, log, pane.w.back)
    assertEqual(pb[1], "attached", "the detail's Back, on its top toolbar, is chrome")
    assertTrue(pb[2] == pane.w.back, "attached to the button")
    -- Body: the detail's action row at the pane's bottom (Timeline, Compare, Share, Add Note, Delete)
    -- is neither a toolbar between the title bar and the body nor the window's footer (the library's
    -- W.Footer, under it), so it is a body element: beside the Results window, level with the button.
    for _, key in ipairs({ "timeline", "compare", "share", "addNote", "delete" }) do
        local b = pane.w[key]
        assertTrue(b ~= nil, "the action row's " .. key)
        local p = placedBy(M, log, b)
        assertEqual(p[1], "beside", "the action row's " .. key .. " is a body element")
        assertTrue(p[2] == b and p[3] == R.frame, "beside the Results window, level with " .. key)
    end
    assertTrue(list ~= nil and list.save ~= nil, "the fight list's Save")
    assertEqual(placedBy(M, log, list.save)[1], "attached", "the filter bar's Save is chrome")
    -- Body: a section heading's fold arrow, beside the Results window.
    local arrow
    for _, a in pairs(pane.heads) do arrow = arrow or (a:IsShown() and a) end
    assertTrue(arrow ~= nil, "a shown section arrow")
    local pa = placedBy(M, log, arrow)
    assertEqual(pa[1], "beside", "a section's fold arrow is a body element")
    assertTrue(pa[2] == arrow and pa[3] == R.frame, "beside the Results window, level with the arrow")
    -- Body: the HUD's clock, beside the HUD's group.
    local hui = NS.Hud.__ui()
    local zone
    for _, body in pairs(hui.body or {}) do zone = zone or (body.w and body.w.clockZone) end
    assertTrue(zone ~= nil, "the HUD's clock zone")
    local pz = placedBy(M, log, zone)
    assertEqual(pz[1], "beside", "the HUD's clock is a body element")
    local g = pz[3]
    assertTrue(g == hui.frame or (type(g) == "table" and g.main == hui.frame), "beside the HUD's group")
    log.restore()
end)

test("tooltip surfaces: a Race window body button opens beside the HUD and the attached Race window", function()
    local NS, M = fresh()
    if not retail(NS) then return end
    NS.Hud.Show()
    NS.SetRaceWindowShown("show")
    assertTrue(NS.RaceWindow.IsAttached(), "attached by default")
    local log = spy(M)
    local rw = NS.RaceWindow.__ui()
    local preset
    for _, body in pairs(rw.body or {}) do
        local w = body.w or {}
        preset = preset or (w.presets and w.presets[1])
    end
    assertTrue(preset ~= nil, "the idle body's first length")
    local p = placedBy(M, log, preset)
    assertEqual(p[1], "beside", "a length is a body element")
    local g = p[3]
    assertTrue(type(g) == "table" and g.main == NS.Hud.Frame() and g.panels[1] == NS.RaceWindow.Frame(),
        "the group is the HUD with the Race window docked to it")
    log.restore()
end)

test("tooltip surfaces: the Insights charts place through the context's PlaceTip, beside the window", function()
    local NS, M = fresh()
    local host = NS.ChartsHost()
    local placedTip
    local ctx = { PlaceTip = function(_, tip, owner) placedTip = { tip, owner } return "right" end }
    local owner = M.CreateFrame("Frame", nil, M.UIParent)
    local anchors = {}
    rawset(M.GameTooltip, "SetOwner", function(_, o, a) anchors[#anchors + 1] = { o, a } end)
    host.tip(owner, { "Title", "a line" }, "ANCHOR_CURSOR_RIGHT", ctx)
    assertEqual(#anchors, 1)
    assertEqual(anchors[1][2], "ANCHOR_NONE", "the legacy cursor anchor is not read")
    assertTrue(placedTip ~= nil and placedTip[1] == M.GameTooltip and placedTip[2] == owner, "ctx:PlaceTip places it")
    rawset(M.GameTooltip, "SetOwner", nil)
end)

-- ── the Combat Sequence (CSEQ-4, the tooltip anchor audit) ────────────────────────────────────
-- Every tooltip the Combat Sequence shows, by its home: the HUD drawer (a section of the HUD's body:
-- its heading marks, Resume, chips and rows are body elements, beside the HUD's group), the detached
-- window (its title-bar marks, and Resume and the chips on the band between the title bar and the
-- table, its filter bar, are chrome, attached above; its rows are body, beside the window) and the
-- Results fight detail's section (its chips and rows are body, beside the Results window). Each is
-- owned at ANCHOR_NONE first, never at the client's default anchor.

local FIREBALL = 133

local function click(b) b:GetScript("OnClick")(b, "LeftButton") end

-- Hover `f` and check its owner and its placer: answers the placement record.
local function placedAs(M, log, f, want, what)
    local h = hover(M, log, f)
    assertTrue(h ~= nil, what .. " shows a tooltip")
    assertEqual(h.owners[1][1], f, what .. ": owned by the hovered element")
    assertEqual(h.owners[1][2], "ANCHOR_NONE", what .. ": owned at ANCHOR_NONE, never the default anchor")
    local p = h.placed[1] or {}
    assertEqual(p[1], want, what .. " placed " .. want)
    assertTrue(p[2] == f, what .. ": placed on the hovered element")
    return p
end

-- A fight's casts in the live feed, so the rows carry a spell (its tooltip is the client's spell's).
local function liveCasts(NS, M)
    rawset(M.GameTooltip, "SetSpellByID", function() end)
    NS.CombatLog.Begin("f1", 100)
    for i = 1, 3 do NS.CombatLog.OnCast("player", FIREBALL, 100 + i * 0.1) end
    M.__now = 103
end

test("tooltip surfaces: the Combat Sequence drawer's marks, Resume, chips and rows open beside the HUD", function()
    local NS, M = fresh()
    NS.Hud.Show()
    NS.HudLog.SetShown(true)
    local d = NS.HudLog.__ui()
    liveCasts(NS, M)
    NS.HudLog.Paint()
    local log = spy(M)
    local hud = NS.Hud.Frame()
    local function inHud(p, what)
        local g = p[3]
        assertTrue(g == hud or (type(g) == "table" and g.main == hud), what .. " beside the HUD's group")
    end
    -- red under: a heading mark placed by the chrome rule, or a chip or Resume made chrome in the drawer
    inHud(placedAs(M, log, d.filter, "beside", "the drawer's filter mark"), "the filter mark")
    inHud(placedAs(M, log, d.detach, "beside", "the drawer's detach mark"), "the detach mark")
    inHud(placedAs(M, log, d.resume, "beside", "the drawer's Resume"), "Resume")
    for key, b in pairs(d.chips.buttons) do inHud(placedAs(M, log, b, "beside", "the drawer's " .. key .. " chip"), key) end
    local row = d.table:Rows()[1]
    assertEqual(row.spellID, FIREBALL, "the newest row carries its spell")
    inHud(placedAs(M, log, row, "beside", "a drawer row"), "a drawer row")
    log.restore()
end)

test("tooltip surfaces: the Combat Sequence window's filter bar is chrome, above; its rows open beside it", function()
    local NS, M = fresh()
    NS.Hud.Show()
    NS.HudLog.SetShown(true)
    click(NS.HudLog.__ui().detach)
    local ui = NS.LogWindow.__ui()
    liveCasts(NS, M)
    NS.LogWindow.Paint()
    ui.resume:Show()
    local log = spy(M)
    -- red under: the window's chips or Resume placed beside the window, as the drawer's are
    placedAs(M, log, ui.resume, "attached", "the window's Resume")
    for key, b in pairs(ui.chips.buttons) do placedAs(M, log, b, "attached", "the window's " .. key .. " chip") end
    placedAs(M, log, ui.dock, "attached", "the title bar's dock mark")
    placedAs(M, log, ui.settings, "attached", "the title bar's settings mark")
    local row = ui.table:Rows()[1]
    assertEqual(row.spellID, FIREBALL, "the newest row carries its spell")
    local p = placedAs(M, log, row, "beside", "a window row")
    assertTrue(p[3] == ui.frame, "a window row's tooltip beside the Combat Sequence window, its own group")
    log.restore()
end)

test("tooltip surfaces: a chrome chip's tooltip is centered 2 px above it on the fake screen", function()
    local NS, M = fresh()
    NS.Hud.Show()
    NS.HudLog.SetShown(true)
    click(NS.HudLog.__ui().detach)
    local chip = NS.LogWindow.__ui().chips.buttons.casts
    local scr = installScreen(M, { width = 1920, height = 1080 })
    local win = scr.frame{ left = 300, bottom = 300, width = 460, height = 400 }
    local at = scr.frame{ left = 310, bottom = 640, width = 60, height = 18, parent = win }
    local tip = scr.tooltip{ width = 200, height = 60 }
    rawset(M, "GameTooltip", tip)
    -- The chip's own hover, on a stand-in with the chip's tip and the fake screen's geometry.
    rawset(at, "tip", chip.tip)
    rawset(at, "tipBody", chip.tipBody)
    assertFalse(chip.tipBody, "a window chip is chrome")
    chip:GetScript("OnEnter")(at)
    assertEqual(tip.__anchor, "ANCHOR_NONE", "owned at ANCHOR_NONE")
    local l, b, r = scr.rectOf(tip)
    assertTrue(near(b, 658 + GAP), "its bottom 2 px above the chip: " .. tostring(b))
    assertTrue(near((l + r) / 2, 340), "centered on the chip")
    scr.restore()
end)

test("tooltip surfaces: the Results Combat Sequence section's chips and rows open beside the Results window", function()
    local NS, M = fresh()
    openAll(NS)
    local pane = NS.Results.__ui().detail
    local g = pane.log
    assertTrue(g ~= nil, "the detail's Combat Sequence section")
    rawset(M.GameTooltip, "SetSpellByID", function() end)
    local log = spy(M)
    local R = NS.Results.__ui()
    for key, b in pairs(g.chips) do
        local p = placedAs(M, log, b, "beside", "the section's " .. key .. " chip")
        assertTrue(p[3] == R.frame, "beside the Results window")
    end
    -- A sample fight keeps no saved sequence, so the section's table is laid and its first row handed a spell.
    g.table:Layout(400, 3, NS.GetSetting("sequence.view.columns"))
    local row = g.table:Rows()[1]
    assertTrue(row ~= nil, "the section's table has its rows")
    row.spellID = FIREBALL
    local p = placedAs(M, log, row, "beside", "a section row")
    assertTrue(p[3] == R.frame, "a section row beside the Results window")
    log.restore()
end)

-- ── the guard ───────────────────────────────────────────────────────────────────────────────────

-- The addon's own Lua, comments stripped: no tooltip is owned at any anchor but ANCHOR_NONE, and no
-- client anchor names the cursor or a corner (standalone-windows, *Tooltip placement*).
test("tooltip guard: the addon's own code names no cursor or corner anchor", function()
    local offenders = {}
    for _, rel in ipairs(T.loadedAddonFiles) do
        if rel:match("%.lua$") then
            local fh = io.open(T.root .. "/" .. rel:gsub("\\", "/"), "rb")
            local src = fh and fh:read("*a") or ""
            if fh then fh:close() end
            local n = 0
            for line in (src .. "\n"):gmatch("([^\n]*)\n") do
                n = n + 1
                local code = line:gsub("%-%-.*$", "")
                for anchor in code:gmatch("\"(ANCHOR_[%u_]+)\"") do
                    if anchor ~= "ANCHOR_NONE" then offenders[#offenders + 1] = rel .. ":" .. n .. " " .. anchor end
                end
            end
        end
    end
    assertEqual(#offenders, 0, "anchors other than ANCHOR_NONE: " .. table.concat(offenders, ", "))
end)
