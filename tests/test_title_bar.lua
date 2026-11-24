-- tests/test_title_bar.lua — every title-bar control this addon draws on its own windows (smoke round 1,
-- rulings 3 and 4: Ka0sAddonsCommonTasks docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS/SR1_SMOKE_ROUND1.md,
-- item SR-CT; the settings marks from LibKa0s#86, item AD-86-CT). One case per window: the DPS HUD, the Race window (Retail), the Results window, the
-- compare, the gear view and the ability timeline. Each control, the close among them:
--   * shows a non-empty one-line tooltip on hover, through LibKa0s-Tooltip-1.0's attached placement
--     (owned at ANCHOR_NONE, never below the control), in the owner's `gtip.title`, hidden on leave;
--   * rests in the skin's `icon.tint`; under the pointer a mark takes `text.link` and the close X
--     `close.hot`; and back at rest once the pointer leaves,
-- under Ka0s Default and under the first other skin whose every one of those tokens (and `gtip.title`)
-- differs from Ka0s Default's, so the second pass proves the colors are read, not assumed. The lock is a mark like any other: its state is its art (lock / unlock), not a color.

local T = _G.CT_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local F = dofile(T.root .. "/tests/race_fixture.lua")(T)
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local OWNER = "CombatTrail"
local TOKENS = { "icon.tint", "text.link", "close.hot", "gtip.title" }
local SKINS   -- Ka0s Default and one other skin (skinsUnderTest, below)

local function retail() return not T.NS.Compat.IsForever() end

-- ── the records the Results windows open on ─────────────────────────────────────────────────────

local NOW = os.time()
local KC = 34026
local GEAR = { [1] = "212002:7000", [13] = "212030", [16] = "212040" }
local BEST = { [1] = "212002:7001", [13] = "212031", [16] = "212040" }

local n = 0
local function rec(NS, o)
    n = n + 1
    local me = NS.Identity.Who()
    local who = { name = me.name, realm = me.realm, client = me.client, class = me.class or "HUNTER",
                  specID = me.specID, specName = me.specName, ilvl = 721.4 }
    local ident = { content = "raid", targetName = "Vorasius", encounterID = 3176,
                    encounterName = "Vorasius", instanceName = "The Voidspire", difficultyID = 15,
                    difficultyName = "Heroic", isBoss = true }
    local merged = o.dps * 60
    return {
        schema = 1, id = o.id, t = NOW - n * 60, duration = 60, status = "final",
        who = who, identity = ident, boardKey = NS.Identity.BoardKey(ident),
        damage = { merged = merged, player = merged }, dps = o.dps, meterDps = o.dps,
        build = "120105", version = "0.1.0", gearSet = NS.Loadouts.StoreGear(o.gear),
        spells = NS.CastCodec.EncodeSpells({ { spellID = KC, total = merged, isPet = false } }),
    }
end

local function fresh()
    local S = F.fresh{ target = false, mutate = function(m)
        installPaint(m)
        m.StaticPopup_Show = function() end
        m.StaticPopup_Hide = function() end
    end }
    return S, S.NS
end

-- The Results window on a fight with a best on its board, so compare, gear and timeline can open.
local function results(NS)
    for _, r in ipairs({ rec(NS, { id = "best", dps = 3000, gear = BEST }),
                         rec(NS, { id = "this", dps = 2000, gear = GEAR }) }) do
        assertTrue(NS.Recorder.Save(r), "saved " .. r.id)
    end
    assertTrue(NS.Results.ShowFight("this"))
    return NS.Results.__ui().detail
end

-- ── the tooltip spy ─────────────────────────────────────────────────────────────────────────────

-- Record what the game tooltip is told: its owner and anchor, its text and color, every point set.
local function spy(M)
    local tip = M.GameTooltip
    local log = {}
    rawset(tip, "SetOwner", function(self, owner, anchor)
        log.owner, log.anchor, log.text, log.color, log.points = owner, anchor, nil, nil, {}
        return self
    end)
    rawset(tip, "SetText", function(self, text, r, g, b)
        log.text, log.color = text, { r, g, b }
        return self
    end)
    rawset(tip, "IsOwned", function(_, f) return log.owner == f end)
    rawset(tip, "SetPoint", function(self, ...)
        log.points = log.points or {}
        log.points[#log.points + 1] = { ... }
        return self
    end)
    return log
end

local function near(a, b) return math.abs((a or -1) - (b or -2)) < 1e-6 end

local function sameRgb(got, want, what)
    assertTrue(got ~= nil and near(got[1], want[1]) and near(got[2], want[2]) and near(got[3], want[3]),
        what .. ": got " .. (got and string.format("%.3f %.3f %.3f", got[1] or -1, got[2] or -1, got[3] or -1) or "nil")
        .. ", want " .. string.format("%.3f %.3f %.3f", want[1], want[2], want[3]))
end

-- The color a control's art (or its glyph) wears now.
local function colorOf(b)
    if b.icon and b.icon:IsShown() ~= false then
        local r, g, bl = b.icon:GetVertexColor()
        return { r, g, bl }
    end
    local fs = b.glyph
    if fs then
        local r, g, bl = fs:GetTextColor()
        return { r, g, bl }
    end
    return nil
end

local function token(NS, name)
    local r, g, b = NS.Skin.Color(name)
    return { r, g, b }
end

-- One control: hover shows its words above it in gtip.title and lights it; leave hides and rests it.
local function checkControl(S, log, b, what, isClose)
    local NS, M = S.NS, S.M
    assertTrue(b ~= nil, what .. " is built")
    sameRgb(colorOf(b), token(NS, "icon.tint"), what .. " at rest is icon.tint")
    b:__fire("OnEnter")
    assertTrue(type(log.text) == "string" and log.text ~= "", what .. " shows a tooltip")
    assertTrue(log.owner == b, what .. "'s tooltip is owned by it")
    assertEqual(log.anchor, "ANCHOR_NONE", what .. "'s tooltip is placed by the library, not the client's anchor")
    for _, p in ipairs(log.points or {}) do
        assertTrue(not (p[1] == "TOP" and p[2] == b and p[3] == "BOTTOM"), what .. "'s tooltip hangs below it")
    end
    sameRgb(log.color, token(NS, "gtip.title"), what .. "'s tooltip is in gtip.title")
    assertTrue(M.GameTooltip:IsShown(), what .. "'s tooltip is shown")
    sameRgb(colorOf(b), token(NS, isClose and "close.hot" or "text.link"),
        what .. " under the pointer is " .. (isClose and "close.hot" or "text.link"))
    b:__fire("OnLeave")
    assertTrue(not M.GameTooltip:IsShown(), what .. "'s tooltip hides on leave")
    sameRgb(colorOf(b), token(NS, "icon.tint"), what .. " back at rest is icon.tint")
    if isClose then assertEqual(log.text, "Close", what .. " says Close") end
end

-- Every control of a window, in every skin of SKINS.
local function checkWindow(S, name, controls)
    local Skin = S.M.LibStub("LibKa0s-Skin-1.0")
    local source, skin = Skin:GetChoice(OWNER)
    local log = spy(S.M)
    for _, key in ipairs(SKINS) do
        Skin:SetChoice(OWNER, "ka0s", key)
        for _, c in ipairs(controls()) do
            checkControl(S, log, c[1], name .. " " .. c[2] .. " (" .. key .. ")", c[3])
        end
    end
    Skin:SetChoice(OWNER, source, skin)
end

-- Ka0s Default and the first registered skin whose title-bar tokens all differ from it.
local function sameTok(a, b) return a and b and near(a[1], b[1]) and near(a[2], b[2]) and near(a[3], b[3]) end
local function skinsUnderTest()
    local Skin = T.mocks.LibStub("LibKa0s-Skin-1.0")
    local function tok(key, name)
        local S = Skin:For(OWNER)
        local source, skin = Skin:GetChoice(OWNER)
        Skin:SetChoice(OWNER, "ka0s", key)
        local r, g, b = S.Color(name)
        Skin:SetChoice(OWNER, source, skin)
        return { r, g, b }
    end
    for _, s in ipairs(Skin:Skins()) do
        if s.key ~= "ka0s" then
            local all = true
            for _, name in ipairs(TOKENS) do
                if sameTok(tok("ka0s", name), tok(s.key, name)) then all = false end
            end
            if all then return { "ka0s", s.key } end
        end
    end
    return { "ka0s" }
end
SKINS = skinsUnderTest()

test("title bar: a second skin differs from Ka0s Default in every title-bar token", function()
    assertEqual(#SKINS, 2, "no registered skin differs from Ka0s Default in all of " .. table.concat(TOKENS, ", "))
end)

test("title bar: the DPS HUD's controls, the close among them", function()
    local S, NS = fresh()
    NS.Hud.Show()
    checkWindow(S, "HUD", function()
        local ui = NS.Hud.__ui()
        local list = { { ui.close, "close", true }, { ui.lock, "lock" }, { ui.settings, "settings" },
                       { ui.results, "results" } }
        if ui.race then list[#list + 1] = { ui.race, "race" } end
        return list
    end)
    -- Locked, the lock is still a mark at rest in icon.tint (its state is its art).
    assertTrue(NS.SetByPath("general.locked", true))
    checkWindow(S, "HUD locked", function() return { { NS.Hud.__ui().lock, "lock" } } end)
end)

test("title bar: the Race window's controls (Retail)", function()
    if not retail() then return end
    local S, NS = fresh()
    NS.Hud.Show()
    NS.SetRaceWindowShown("show")
    checkWindow(S, "Race window", function()
        local ui = NS.RaceWindow.__ui()
        return { { ui.close, "close", true }, { ui.attach, "attach" }, { ui.lock, "lock" },
                 { ui.settings, "settings" } }
    end)
end)

test("title bar: the Results window's controls, the view toggle in both views", function()
    local S, NS = fresh()
    results(NS)
    local function controls()
        local ui = NS.Results.__ui()
        return { { ui.close, "close", true }, { ui.settings, "settings" }, { ui.viewToggle, "view toggle" } }
    end
    checkWindow(S, "Results", controls)
    NS.Results.ToggleView()
    checkWindow(S, "Results (toggled)", controls)
end)

-- The compare, the gear view and the timeline are companions of the Results window (FB-CTR-02;
-- standalone-windows, *Settings is on every window but a companion*, v2.119.0): the close alone.
test("title bar: the compare's close, its one control", function()
    local S, NS = fresh()
    local pane = results(NS)
    pane.w.compare:__fire("OnClick")
    assertTrue(NS.ResultsCompare.IsShown())
    checkWindow(S, "compare", function() local ui = NS.ResultsCompare.__ui()
        return { { ui.close, "close", true } } end)
end)

test("title bar: the gear view's close, its one control", function()
    local S, NS = fresh()
    local pane = results(NS)
    assertTrue(NS.ResultsGear.Open(pane))
    checkWindow(S, "gear", function() local ui = NS.ResultsGear.__ui()
        return { { ui.close, "close", true } } end)
end)

test("title bar: the ability timeline's close, its one control", function()
    local S, NS = fresh()
    local pane = results(NS)
    NS.ResultsTimeline.Open(pane)
    assertTrue(NS.ResultsTimeline.IsShown())
    checkWindow(S, "timeline", function() local ui = NS.ResultsTimeline.__ui()
        return { { ui.close, "close", true } } end)
end)

-- ── the strip (LibKa0s#86, item AD-86-CT; standalone-windows, *Title-bar controls*) ────────────────
-- Every window's marks are W.HeaderButtons': `frame.headerButtons` is the library's answer, its order
-- left to right the window's extras, then settings, then the close; each mark laid on the band's right
-- through the skin's S.Header, HEADER.PAD (6) in and HEADER.SIZE + HEADER.GAP (24) apart, outermost first. The settings mark opens
-- this addon's settings (the launcher-registered opener, NS.OpenSettings; the Race window its own Race
-- mode page), and the three DIALOG-tier windows over the Results window hide first (hideOnSettings),
-- since they would cover the settings panel.

local function W(S) return S.M.LibStub("LibKa0s-Widgets-1.0") end

-- What Style.Header hands the skin's S.Header for each window: its `right` entries, outermost first.
-- Installed before a window is built (each builds on its first show), so its first layout is seen.
local function watchHeaders(NS)
    local seen, header = {}, NS.Skin.Header
    NS.Skin.Header = function(f, spec, ...)
        seen[f] = spec and spec.right
        return header(f, spec, ...)
    end
    return seen
end

-- The marks a window shows, outermost first, each RIGHT on the band at HEADER.PAD + (i - 1) * pitch.
local function checkStrip(S, seen, f, want, what)
    local H = W(S).HEADER
    local hb = f.headerButtons
    assertTrue(type(hb) == "table", what .. ": the marks are W.HeaderButtons'")
    assertEqual(table.concat(hb.order, ","), table.concat(want.order, ","), what .. ": extras, settings, close")
    assertTrue(hb.settings ~= nil and hb.optOut == nil, what .. ": a settings mark, not opted out")
    local right = seen[f]
    assertTrue(type(right) == "table", what .. ": laid on the title band by S.Header")
    assertEqual(#right, #want.right, what .. ": the marks shown")
    for i, b in ipairs(want.right) do
        local at = H.PAD + (i - 1) * (H.SIZE + H.GAP)
        assertTrue(right[i].frame == b, what .. " slot " .. i .. " outermost first")
        assertEqual(right[i].x, at, what .. " slot " .. i .. ": " .. at .. " in from the band's right")
    end
end

-- Count NS.OpenSettings' panel opens (and the Race page's) while `fn` runs; answers the calls.
local function opens(S, fn)
    local NS, calls = S.NS, {}
    local panel, helper = NS.OpenOptionsPanel, NS.Helpers.OpenOptionsPanel
    NS.OpenOptionsPanel = function(...) calls[#calls + 1] = { "panel", ... } end
    NS.Helpers.OpenOptionsPanel = function(page) calls[#calls + 1] = { "page", page } end
    fn()
    NS.OpenOptionsPanel, NS.Helpers.OpenOptionsPanel = panel, helper
    return calls
end

local function click(b) b:GetScript("OnClick")(b, "LeftButton") end

test("header strip: the DPS HUD reads Results, Race, Lock, Settings, Close; Race off, it closes up", function()
    local S, NS = fresh()
    local seen = watchHeaders(NS)
    NS.Hud.Show()
    local ui = NS.Hud.__ui()
    if retail() then
        checkStrip(S, seen, ui.frame, { order = { "results", "race", "lock", "settings", "close" },
            right = { ui.close, ui.settings, ui.lock, ui.race, ui.results } }, "HUD")
        assertTrue(NS.SetByPath("race.enabled", false))
    else
        assertTrue(ui.race == nil, "no Race mark on WoW Forever")
    end
    checkStrip(S, seen, ui.frame, { order = retail() and { "results", "race", "lock", "settings", "close" }
            or { "results", "lock", "settings", "close" },
        right = { ui.close, ui.settings, ui.lock, ui.results } }, "HUD without Race")
end)

test("header strip: the HUD's settings mark opens the settings panel and leaves the HUD up", function()
    local S, NS = fresh()
    NS.Hud.Show()
    local calls = opens(S, function() click(NS.Hud.__ui().settings) end)
    assertEqual(#calls, 1, "one open")
    assertEqual(calls[1][1], "panel", "the settings panel (NS.OpenSettings)")
    assertTrue(NS.Hud.IsShown(), "the HUD stays: it does not cover the panel")
end)

test("header strip: the Race window reads Lock, Attach, Settings, Close; settings opens Race mode (Retail)", function()
    if not retail() then return end
    local S, NS = fresh()
    local seen = watchHeaders(NS)
    NS.Hud.Show()
    NS.SetRaceWindowShown("show")
    local ui = NS.RaceWindow.__ui()
    checkStrip(S, seen, ui.frame, { order = { "lock", "attach", "settings", "close" },
        right = { ui.close, ui.settings, ui.attach, ui.lock } }, "Race window")
    local calls = opens(S, function() click(ui.settings) end)
    assertEqual(#calls, 1, "one open")
    assertEqual(calls[1][1] .. ":" .. tostring(calls[1][2]), "page:race", "the Race mode page")
    assertTrue(NS.RaceWindow.IsShown(), "the Race window stays")
end)

test("header strip: the Results window reads the view toggle, Settings, Close; settings opens the panel", function()
    local S, NS = fresh()
    local seen = watchHeaders(NS)
    results(NS)
    local ui = NS.Results.__ui()
    checkStrip(S, seen, ui.frame, { order = { "view", "settings", "close" },
        right = { ui.close, ui.settings, ui.viewToggle } }, "Results")
    local calls = opens(S, function() click(ui.settings) end)
    assertEqual(#calls, 1, "one open")
    assertEqual(calls[1][1], "panel", "the settings panel")
    assertTrue(NS.Results.IsShown(), "the Results window stays (HIGH, beside the panel)")
end)

-- The three DIALOG-tier windows over the Results window are its companions (FB-CTR-02; standalone-
-- windows, *Settings is on every window but a companion*, v2.119.0): each opens only from a button in
-- the Results detail, shows that detail's fight and keeps no position. The close alone, built with
-- `companion = true` (WidgetsHeader minor 2): no settings mark and no waiver.
local OVER = {
    { "compare", "ResultsCompare", function(_, pane) pane.w.compare:__fire("OnClick") end },
    { "gear view", "ResultsGear", function(NS, pane) assertTrue(NS.ResultsGear.Open(pane)) end },
    { "ability timeline", "ResultsTimeline", function(NS, pane) NS.ResultsTimeline.Open(pane) end },
}

for _, w in ipairs(OVER) do
    test("header strip: the " .. w[1] .. " is a companion: the close alone, no settings mark", function()
        local S, NS = fresh()
        local seen = watchHeaders(NS)
        local pane = results(NS)
        w[3](NS, pane)
        local mod = NS[w[2]]
        assertTrue(mod.IsShown(), w[1] .. " open")
        local ui = mod.__ui()
        local hb = ui.frame.headerButtons
        assertTrue(type(hb) == "table", w[1] .. ": the marks are W.HeaderButtons'")
        assertEqual(table.concat(hb.order, ","), "close", w[1] .. ": the close alone")
        assertTrue(hb.companion == true, w[1] .. ": recorded as a companion")
        assertTrue(hb.settings == nil and ui.settings == nil, w[1] .. ": a companion drew the settings mark")
        assertTrue(hb.optOut == nil, w[1] .. ": a companion needs no settingsOptOut waiver")
        local right = seen[ui.frame]
        assertTrue(type(right) == "table" and #right == 1, w[1] .. ": one mark laid on the band")
        assertTrue(right[1].frame == ui.close, w[1] .. ": the one mark is the close")
        assertEqual(right[1].x, W(S).HEADER.PAD, w[1] .. ": the close HEADER.PAD in from the band's right")
    end)
end
