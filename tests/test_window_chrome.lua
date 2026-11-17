-- tests/test_window_chrome.lua — the window chrome the library builds and places (LibKa0s#88 and #89,
-- Ka0sAddonsCommonTasks docs/2026-11-17-LIBKA0S_V1_105_ADOPTION, items AD-88-CT and AD-89-CT;
-- WowAddonStandards v2.113.0, standalone-windows' *Window chrome geometry* and *The footer*,
-- preview-mode's *Where the strip sits*). The DPS HUD, the Results window and the Race window (Retail)
-- each draw their footer with LibKa0s-Widgets-1.0's Footer, FOOTER.HEIGHT (24) tall, and their bodies
-- end that far above the window's bottom edge, plus the host's own gap. The HUD's and the Results
-- window's test and sim strips are docked by the library under the title bar (dock = "title"), never
-- anchored by hand: everything below the title bar (the Results window's tabs, its tab rule and its
-- body; the HUD's content) moves down by the strip's BodyOffset while it shows. The DPS HUD has a
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
    assertEqual(ui.foot.__grip, true, "fixed and unlocked: the grip shows, the right line clears it")
    H.setHud(inst, "sizeMode", "auto")
    Hud.Refresh()
    assertEqual(ui.foot.__grip, nil, "auto-grow: no grip, the right line on the footer's padding")
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
