-- tests/test_window_chrome.lua — the window chrome the library builds and places (LibKa0s#88 and #89,
-- Ka0sAddonsCommonTasks docs/2026-11-17-LIBKA0S_V1_105_ADOPTION, items AD-88-CT and AD-89-CT;
-- WowAddonStandards v2.113.0, standalone-windows' *Window chrome geometry* and *The footer*,
-- preview-mode's *Where the strip sits*). The DPS HUD, the Results window and the Race window (Retail)
-- each draw their footer with LibKa0s-Widgets-1.0's Footer, FOOTER.HEIGHT (24) tall, and their bodies
-- end that far above the window's bottom edge, plus the host's own gap. The HUD's, the Results
-- window's and the Race window's test and sim strips are docked by the library under the title bar
-- (dock = "title"), never anchored by hand: everything below the title bar (the Results window's tabs,
-- its tab rule and its body; the HUD's content; the Race window's body) moves down by the strip's
-- BodyOffset while it shows. With no library there is no strip and the title says the mode word. The DPS HUD has a
-- title bar, a background and a footer, so preview-mode counts it a window ("a race or tracker
-- window the addon names its HUD is a window"); with its title bar hidden its strip sits on the
-- window's top edge.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse
local H = dofile(T.root .. "/tests/hud_fixture.lua")(T)

local PAD = 12

local function widgets(inst) return inst.mocks.LibStub("LibKa0s-Widgets-1.0") end

-- Record a frame's points from here on (the kit's frames record none unless asked).
local function track(f)
    rawset(f, "__points", {})
    rawset(f, "ClearAllPoints", function(self) rawset(self, "__points", {}) end)
    rawset(f, "SetPoint", function(self, ...)
        local list = rawget(self, "__points")
        list[#list + 1] = { ... }
    end)
end

local function point(f, name)
    for _, p in ipairs(rawget(f, "__points") or {}) do
        if p[1] == name then return p end
    end
    return nil
end

-- Built by W.Footer: its hairline, its two lines and its setters, the host's lines are its own.
local function isLibraryFooter(ui, what)
    local foot = ui.foot
    assertTrue(foot ~= nil, what .. ": a footer")
    assertTrue(foot.line ~= nil and foot.left ~= nil and foot.right ~= nil, what .. ": W.Footer's hairline and lines")
    assertTrue(type(rawget(foot, "SetLeft")) == "function" and type(rawget(foot, "SetGrip")) == "function",
        what .. ": W.Footer's setters")
    assertTrue(ui.footLeft == foot.left and ui.footRight == foot.right, what .. ": the host writes the library's lines")
end

-- A docked strip: placed by the library (its own Place and BodyOffset, not the kit's no-op stubs), under `band` (TOPLEFT on its BOTTOMLEFT).
local function dockedUnder(strip, band, what)
    assertTrue(strip ~= nil, what .. ": a strip")
    assertTrue(type(rawget(strip, "Place")) == "function" and type(rawget(strip, "BodyOffset")) == "function",
        what .. ": docked by the library")
    track(strip)
    strip:Place()
    local tl, tr = point(strip, "TOPLEFT"), point(strip, "TOPRIGHT")
    assertTrue(tl ~= nil and tr ~= nil, what .. ": anchored on both top corners")
    assertTrue(tl[2] == band and tl[3] == "BOTTOMLEFT" and tl[5] == 0, what .. ": directly under the title bar")
    assertTrue(tr[2] == band and tr[3] == "BOTTOMRIGHT", what .. ": the title bar's full width")
end

-- ── the footers (AD-89-CT) ──────────────────────────────────────────────────────────────────────

test("window chrome: the footer height is the library's FOOTER.HEIGHT, 24", function()
    local inst = H.fresh()
    assertEqual(widgets(inst).FOOTER.HEIGHT, 24)
    assertEqual(inst.NS.FOOTER_HEIGHT, widgets(inst).FOOTER.HEIGHT, "read where the library publishes it")
end)

test("window chrome: the DPS HUD's footer is W.Footer, the content FOOTER.HEIGHT + 8 above the bottom", function()
    local inst, _, Hud = H.fresh()
    local NS = inst.NS
    Hud.Show()
    local ui = Hud.__ui()
    isLibraryFooter(ui, "the HUD")
    track(ui.content)
    H.setHud(inst, "window.alpha", 0.9)   -- a new Appearance stamp lays the window out again
    Hud.Refresh()
    local br = point(ui.content, "BOTTOMRIGHT")
    assertEqual(br[5], NS.FOOTER_HEIGHT + 8, "the content's bottom: the footer + 8")
    H.setHud(inst, "window.footer", false)
    Hud.Refresh()
    assertFalse(ui.foot:IsShown(), "the footer hides whole")
    assertEqual(point(ui.content, "BOTTOMRIGHT")[5], PAD, "and gives its height back to the content")
end)

test("window chrome: the HUD footer's right line clears the grip while the grip shows", function()
    local inst, _, Hud = H.fresh()
    Hud.Show()
    local ui = Hud.__ui()
    assertEqual(ui.foot.__grip, true, "unlocked: the grip shows, the right line clears it")
    inst.NS.SetByPath("general.locked", true)
    Hud.Refresh()
    assertTrue(ui.foot.__grip ~= true, "locked: no grip, the right line on the footer's padding")
end)

test("window chrome: the Results footer is W.Footer with the grip's corner, the body over it", function()
    local inst = H.fresh()
    local NS = inst.NS
    NS.Results.Show()
    local ui = NS.Results.__ui()
    isLibraryFooter(ui, "the Results window")
    assertEqual(ui.foot.__grip, true, "the window resizes from the footer's corner")
    assertTrue(ui.footLeft:GetText():find(NS.L["Click a fight for its detail \194\183 right-click for options"], 1, true) ~= nil,
        "the hint, as before")
end)

test("window chrome: the Race window's footer is W.Footer, the content FOOTER.HEIGHT + 8 above the bottom", function()
    if T.NS.Compat.IsForever() then return end   -- no Race window on WoW Forever
    local inst = H.fresh()
    local NS = inst.NS
    local RW = NS.RaceWindow
    RW.Show()
    local ui = RW.__ui()
    isLibraryFooter(ui, "the Race window")
    local top = NS.Style.TITLE_BAR_H + 10
    assertEqual(RW.Height(), top + NS.FOOTER_HEIGHT + 8 + NS.RaceWindowStates.CONTENT_H, "the chrome in its height")
end)

-- ── the strips (AD-88-CT) ───────────────────────────────────────────────────────────────────────

test("window chrome: the HUD's strip is docked under the title bar, the content below it", function()
    local inst, _, Hud = H.fresh()
    local NS = inst.NS
    NS.ToggleTestMode()
    local ui = Hud.__ui()
    local band = NS.Style.Band(ui.frame)
    dockedUnder(ui.testStrip, band, "the HUD's test strip")
    assertTrue(ui.testStrip:IsShown(), "shown for the sample fight")
    -- The content moves down by the strip's own height (its BodyOffset), not by a host constant.
    ui.testStrip:__setGeom(260, 18)
    track(ui.content)
    H.setHud(inst, "window.alpha", 0.9)
    Hud.Refresh()
    assertEqual(point(ui.content, "TOPLEFT")[5], -(NS.Style.TITLE_BAR_H + 10 + 18), "the content under the strip")
    -- With the title bar hidden the strip sits on the window's top edge.
    H.setHud(inst, "window.titleBar", false)
    Hud.Refresh()
    ui.testStrip:Place()
    local tl = point(ui.testStrip, "TOPLEFT")
    assertTrue(tl[2] == ui.frame and tl[3] == "TOPLEFT", "headerless: on the window's top edge")
    assertEqual(point(ui.content, "TOPLEFT")[5], -(PAD + 18), "the content under it")
    NS.ToggleTestMode()
end)

test("window chrome: the HUD's sim strip is docked under the title bar too", function()
    local inst, _, Hud = H.fresh()
    local NS, M = inst.NS, inst.mocks
    M.__now = 1000
    assertTrue(NS.Preview.Start({ mode = "sim", scenario = "newbest" }), "the sim started")
    assertTrue(NS.Sim.Unpark())
    for _ = 1, 40 do
        M.__now = M.__now + 0.25
        M.__fireTimers()
    end
    local ui = Hud.__ui()
    assertTrue(ui.simStrip ~= nil and ui.simStrip:IsShown(), "the HUD wears the sim strip")
    dockedUnder(ui.simStrip, NS.Style.Band(ui.frame), "the HUD's sim strip")
    NS.Preview.Stop()
end)

test("window chrome: the Results strip sits under the title bar, above the tabs, which move down", function()
    local inst = H.fresh()
    local NS = inst.NS
    NS.Results.Show()
    local ui = NS.Results.__ui()
    local band = NS.Style.Band(ui.frame)
    local first = ui.tabs[NS.Results.TABS[1]]
    NS.ToggleTestMode()
    dockedUnder(ui.testStrip, band, "the Results test strip")
    assertTrue(ui.testStrip:IsShown())
    -- Off and on again with the strip measured: the tabs, their rule and the body move down by it.
    NS.ToggleTestMode()
    ui.testStrip:__setGeom(600, 18)
    for _, f in ipairs({ first, ui.tabRule, ui.body }) do track(f) end
    NS.ToggleTestMode()
    if not NS.Results.IsShown() then NS.Results.Show() end
    local TAB_H = NS.Style.TAB_STRIP_H
    local tab = point(first, "TOPLEFT")
    assertTrue(tab ~= nil and tab[2] == band, "the tab on the title bar's foot")
    assertEqual(tab[5], -18, "the tab under the strip")
    assertEqual(point(ui.tabRule, "TOPLEFT")[5], -(TAB_H + 18), "the tab rule under it")
    assertEqual(point(ui.body, "TOPLEFT")[5], -(1 + TAB_H + 18), "the body under the tabs")
    NS.ToggleTestMode()
    assertFalse(ui.testStrip:IsShown(), "the strip goes with test mode")
    assertEqual(point(first, "TOPLEFT")[5], 0, "the tabs back on the title bar's foot")
end)

-- ── the Race window's strips (Retail; AD-88-CT review fix) ──────────────────────────────────────
-- The Race window is a standalone window that draws the sample race (`/ct test race`, the sim's
-- race-* scenarios: RW.ShowSample), so while it does it wears its own strip, docked by the library
-- under its own title band (dock = "title"), and its body moves down by the strip's BodyOffset.

local F = dofile(T.root .. "/tests/race_fixture.lua")(T)
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local function forever() return T.NS.Compat.IsForever() end

-- A fresh instance with the Race window opened by the case alone (auto-show off).
local function raceFresh()
    local S = F.fresh({ mutate = function(m) installPaint(m) end })
    assert(S.NS.SetByPath("race.autoShow", false))
    assert(S.NS.SetByPath("race.autoShowHud", false))
    S.NS.RaceWindow.HideAwayFromDummy()
    S.NS.Hud.HideAwayFromDummy()
    S.M.__now = 1000
    return S
end

test("window chrome: the Race window's test strip docks under its title bar for the sample race, the body below it", function()
    if forever() then return end
    local S = raceFresh()
    local NS = S.NS
    local RW = NS.RaceWindow
    RW.Show()
    local ui = RW.__ui()
    assertEqual(ui.testStrip, nil, "the real race wears no strip")
    local top, plain = NS.Style.TITLE_BAR_H + 10, RW.Height()
    NS.Slash:OnSlash("test race")
    dockedUnder(ui.testStrip, NS.Style.Band(ui.frame), "the Race window's test strip")
    assertTrue(ui.testStrip:IsShown(), "shown for the sample race")
    assertEqual(ui.frame.title:GetText(), NS.L["Race"], "the strip says it, so the title keeps its name")
    -- Measured, the body moves down by the strip's own height (its BodyOffset), and the window's least
    -- height grows by it, so the body keeps its room.
    ui.testStrip:__setGeom(260, 18)
    track(ui.content)
    H.setHud(S.inst, "window.alpha", 0.9)   -- a new Appearance stamp lays the window out again
    RW.Refresh()
    assertEqual(point(ui.content, "TOPLEFT")[5], -(top + 18), "the body under the strip")
    assertEqual(RW.Height(), plain + 18, "the least height takes the strip")
    -- With the title bar hidden the strip sits on the window's top edge, the body under it.
    H.setHud(S.inst, "window.titleBar", false)
    RW.Refresh()
    ui.testStrip:Place()
    local tl = point(ui.testStrip, "TOPLEFT")
    assertTrue(tl[2] == ui.frame and tl[3] == "TOPLEFT", "headerless: on the window's top edge")
    assertEqual(point(ui.content, "TOPLEFT")[5], -(PAD + 18), "the body under it")
    H.setHud(S.inst, "window.titleBar", true)
    NS.Preview.Stop()
    assertTrue(RW.IsShown(), "the player's window stays up")
    assertFalse(ui.testStrip:IsShown(), "the strip goes with the sample race")
    assertEqual(point(ui.content, "TOPLEFT")[5], -top, "the body back under the title bar")
    assertEqual(RW.Height(), plain, "and the height given back")
end)

test("window chrome: a sim race-* scenario docks the Race window's sim strip, never the test strip", function()
    if forever() then return end
    local S = raceFresh()
    local NS = S.NS
    local RW = NS.RaceWindow
    assertTrue(NS.Preview.Start({ mode = "sim", scenario = "race-newbest" }), "the sim race started")
    assertTrue(RW.IsShown(), "the sample race opens the window")
    local ui = RW.__ui()
    assertTrue(ui.simStrip ~= nil and ui.simStrip:IsShown(), "the Race window wears the sim strip")
    dockedUnder(ui.simStrip, NS.Style.Band(ui.frame), "the Race window's sim strip")
    assertTrue(ui.testStrip == nil or not ui.testStrip:IsShown(), "and not the test strip")
    NS.Preview.Stop()
    assertFalse(RW.IsShown(), "the window the sim opened is let go")
    RW.Show()
    assertFalse(ui.simStrip:IsShown(), "opened again on the real race: the strip went with the sim")
    assertEqual(ui.frame.title:GetText(), NS.L["Race"])
end)

-- ── the degraded load (no LibKa0s) ──────────────────────────────────────────────────────────────
-- With no Widgets library there is no strip, so the title carries the sample word instead (never
-- both), and the footer is the bare stand-in of the same height, so the layout does not move. The
-- settings library is absent too, so the cases start and stop the preview directly (NS.Preview).

local function bareFresh()
    local inst = T.load{ libFiles = {}, mutate = function(m)
        installPaint(m)
        T.mockMeter.install(m)
        m.__unitExists.target = true
        m.__unitGUIDs.target = F.DUMMY_GUID
        m.__unitNames.target = "Raider's Training Dummy"
    end }
    local NS = inst.NS
    if NS.RaceWindow then
        assert(NS.SetByPath("race.autoShow", false))
        assert(NS.SetByPath("race.autoShowHud", false))
        NS.RaceWindow.HideAwayFromDummy()
        NS.Hud.HideAwayFromDummy()
    end
    inst.mocks.__now = 1000
    return inst, NS
end

test("window chrome: with no library the footers are the bare stand-in, FOOTER_HEIGHT (24) tall", function()
    local inst, NS = bareFresh()
    assertEqual(NS.FOOTER_HEIGHT, 24, "the library's figure with no library")
    NS.Hud.Show()
    local hud = NS.Hud.__ui()
    assertTrue(hud.foot ~= nil and hud.foot.line == nil, "the HUD: no hairline, the bare footer")
    assertTrue(hud.footLeft == hud.foot.left, "the host writes the stand-in's lines")
    hud.foot:SetRight("x")
    assertEqual(hud.foot.right:GetText(), "x", "its setters run unchanged")
    track(hud.content)
    H.setHud(inst, "window.alpha", 0.9)
    NS.Hud.Refresh()
    assertEqual(point(hud.content, "BOTTOMRIGHT")[5], NS.FOOTER_HEIGHT + 8, "the content as far above the bottom")
    NS.Results.Show()
    local res = NS.Results.__ui()
    assertTrue(res.foot ~= nil and res.foot.line == nil, "the Results window: the bare footer")
    assertEqual(res.foot.__grip, true, "clear of the grip's corner")
end)

test("window chrome: with no library the HUD and Results titles carry the test word, no strip", function()
    local _, NS = bareFresh()
    NS.Results.Show()
    assertTrue(NS.Preview.Start({ mode = "test" }), "test mode started")
    local hud, res = NS.Hud.__ui(), NS.Results.__ui()
    assertEqual(hud.testStrip, nil, "the HUD: no strip")
    assertEqual(hud.frame.title:GetText(), NS.L["Combat Trail (sample)"], "the HUD's title says it")
    assertEqual(res.testStrip, nil, "the Results window: no strip")
    assertEqual(res.frame.title:GetText(), NS.L["Combat Trail \226\128\148 Results \194\183 Test"],
        "the Results title says it")
    NS.Preview.Stop()
    assertEqual(hud.frame.title:GetText(), NS.L["Combat Trail"], "the HUD's title back")
    assertEqual(res.frame.title:GetText(), NS.L["Combat Trail \226\128\148 Results"], "the Results title back")
end)

test("window chrome: with no library the Race window's title carries the sample word, no strip", function()
    if forever() then return end
    local _, NS = bareFresh()
    local RW = NS.RaceWindow
    RW.Show()
    local ui = RW.__ui()
    assertTrue(ui.foot ~= nil and ui.foot.line == nil, "the bare footer")
    assertTrue(NS.Preview.Start({ mode = "test", race = "running" }), "the sample race started")
    assertTrue(NS.RaceSample.On(), "the sample race stands in")
    assertEqual(ui.testStrip, nil, "no strip")
    assertEqual(ui.frame.title:GetText(), NS.L["Race (sample)"], "the title says it")
    NS.Preview.Stop()
    assertEqual(ui.frame.title:GetText(), NS.L["Race"], "the title back")
end)
