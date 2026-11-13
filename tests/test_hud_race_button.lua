-- tests/test_hud_race_button.lua — the DPS HUD's Race control (Race window redesign plan Task W2,
-- rulings O6): built on Retail only, shown while Race mode is on and hidden (the strip closed up) with
-- it off, between Results and Settings (Results, Race, Settings, Lock, Close left to right), its icon
-- the plain flag (owner, 2026-11-13); a click toggles the Race window as `/ct race toggle` does, and the
-- control turns gold only under the pointer, like every title-bar control, never for the Race window
-- being open. Every title-bar mark of both windows, the close among them, at one art size
-- (Style.FitControlArt), its measured box held to the vendored art. Then the toggles between the two
-- windows: the HUD's toggle (the key, the launcher's Show window entry, `/ct hud toggle` and `/ct hud
-- hide`) closing the Race window with it, each a player's close, and opening the HUD alone, except in
-- a training dummy session with auto-show on, where it opens the Race window too, tied to the session
-- (owner, 2026-11-13); the Race window's toggle closing it alone, and opening the HUD first when the
-- HUD is shut (W29 decision D3). Then the W29 rule itself: the Race window is never up while the HUD
-- is hidden (the fade, the close control, the end-of-fight close), comes back with the HUD while
-- still wanted, and the HUD never fades while a race holds it. Last, a race armed clears the HUD back
-- to its look before any fight. On the race fixture's instance with no target, so auto-show opens
-- nothing by itself, with the kit's paint recorder installed.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local F = dofile(T.root .. "/tests/race_fixture.lua")(T)
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local function forever() return T.NS.Compat.IsForever() end

local function fresh()
    local S = F.fresh{ target = false, mutate = installPaint }
    S.NS.Hud.Show()
    return S, S.NS.Hud.__ui()
end

local function click(b) b:GetScript("OnClick")(b) end

test("hud race button: absent on WoW Forever", function()
    if not forever() then return end
    local _, ui = fresh()
    assertNil(ui.race, "no Race control on WoW Forever")
    assertTrue(ui.results:IsShown() and ui.settings:IsShown(), "the other controls stand")
end)

test("hud race button: built and shown on Retail with Race mode on, the plain flag", function()
    if forever() then return end
    local _, ui = fresh()
    assertTrue(ui.race ~= nil, "the Race control is built")
    assertTrue(ui.race:IsShown(), "shown with Race mode on")
    assertEqual(ui.race.iconName, "flag", "Open Iconic's flag, the other controls' family")
    assertEqual(ui.race.tip, "Race window")
end)

test("hud race button: Results, Race, Settings, Lock, Close left to right; off, the strip closes up", function()
    if forever() then return end
    local S, ui = fresh()
    local right = ui.header.right
    assertEqual(#right, 5)
    local want = { ui.close, ui.lock, ui.settings, ui.race, ui.results }
    for i, b in ipairs(want) do assertTrue(right[i] == b, "slot " .. i .. " outermost first") end
    assertTrue(S.NS.SetByPath("race.enabled", false))
    assertFalse(ui.race:IsShown(), "hidden with Race mode off")
    right = ui.header.right
    assertEqual(#right, 4, "the strip closed up")
    assertTrue(right[4] == ui.results, "Results takes the Race control's place")
    assertTrue(S.NS.SetByPath("race.enabled", true))
    assertTrue(ui.race:IsShown(), "back with Race mode on")
    assertEqual(#ui.header.right, 5)
end)

test("hud race button: hidden with the title bar", function()
    if forever() then return end
    local S, ui = fresh()
    assertTrue(S.NS.SetByPath("hud.window.titleBar", false))
    assertFalse(ui.race:IsShown())
    assertTrue(S.NS.SetByPath("hud.window.titleBar", true))
    assertTrue(ui.race:IsShown())
end)

local function painted(S, b, which)
    local r, g, bl = b.icon:GetVertexColor()
    local c = S.NS.Style[which]
    return r == c[1] and g == c[2] and bl == c[3]
end

test("hud race button: a click toggles the Race window as /ct race toggle does", function()
    if forever() then return end
    local S, ui = fresh()
    local RW = S.NS.RaceWindow
    assertFalse(RW.IsShown())
    click(ui.race)
    assertTrue(RW.IsShown(), "the click opened the Race window")
    click(ui.race)
    assertFalse(RW.IsShown(), "the second click closed it")
    assertEqual(RW.Closes(), 1, "the click's close is the player's, as /ct race toggle")
end)

test("hud race button: gold only under the pointer, never for the Race window being open", function()
    if forever() then return end
    local S, ui = fresh()
    assertTrue(painted(S, ui.race, "REST"), "at rest with the Race window shut")
    S.NS.SetRaceWindowShown("show")
    assertTrue(S.NS.RaceWindow.IsShown())
    assertTrue(painted(S, ui.race, "REST"), "still at rest with the Race window open")
    assertNil(S.NS.Style.SetControlLit, "no lit state left in the Style API")
    assertNil(S.NS.Hud.OnRaceWindowShown, "the Race window tells the HUD nothing")
    ui.race:__fire("OnEnter")
    assertTrue(painted(S, ui.race, "GOLD"), "gold under the pointer")
    ui.race:__fire("OnLeave")
    assertTrue(painted(S, ui.race, "REST"), "at rest again once the pointer leaves, the window still open")
    -- A HUD built after the Race window opened (a /reload with the window up) starts at rest too.
    local S2 = F.fresh{ target = false, mutate = installPaint }
    S2.NS.SetRaceWindowShown("show")
    S2.NS.Hud.Show()
    assertTrue(painted(S2, S2.NS.Hud.__ui().race, "REST"), "a HUD built with the Race window up is at rest")
end)

-- ── the toggles between the DPS HUD and the Race window ─────────────────────────────────────────

local function both(S)
    S.NS.SetRaceWindowShown("show")
    assertTrue(S.NS.Hud.IsShown() and S.NS.RaceWindow.IsShown(), "both windows up")
end

test("hud toggle: closing the HUD closes an open Race window with it, each a player's close", function()
    if forever() then return end
    local S = fresh()
    local Hud, RW = S.NS.Hud, S.NS.RaceWindow
    both(S)
    local hc, rc = Hud.Closes(), RW.Closes()
    assertTrue(S.NS.ToggleHud())
    assertFalse(Hud.IsShown(), "the HUD closed")
    assertFalse(RW.IsShown(), "the Race window closed with it")
    assertEqual(Hud.Closes(), hc + 1, "the HUD's close is the player's")
    assertEqual(RW.Closes(), rc + 1, "the Race window's close is the player's")
end)

test("hud toggle: opening the HUD opens the HUD alone, never the Race window", function()
    if forever() then return end
    local S = fresh()
    local Hud, RW = S.NS.Hud, S.NS.RaceWindow
    both(S)
    assertTrue(S.NS.ToggleHud())
    assertTrue(S.NS.ToggleHud())
    assertTrue(Hud.IsShown(), "the HUD opened")
    assertFalse(RW.IsShown(), "the Race window stays shut")
end)

test("hud toggle: closing the HUD with the Race window shut counts no Race window close", function()
    if forever() then return end
    local S = fresh()
    local rc = S.NS.RaceWindow.Closes()
    assertTrue(S.NS.ToggleHud())
    assertFalse(S.NS.Hud.IsShown())
    assertEqual(S.NS.RaceWindow.Closes(), rc, "nothing to close")
end)

test("hud toggle: the key and the launcher's Show window run the same rule", function()
    if forever() then return end
    local S = fresh()
    both(S)
    S.M.__frameByName[S.NS.TOGGLE_HUD_BUTTON]:__fire("OnClick", "LeftButton")
    assertFalse(S.NS.Hud.IsShown() or S.NS.RaceWindow.IsShown(), "the key closed both")
    S.M.__frameByName[S.NS.TOGGLE_HUD_BUTTON]:__fire("OnClick", "LeftButton")
    assertTrue(S.NS.Hud.IsShown(), "the key opened the HUD")
    assertFalse(S.NS.RaceWindow.IsShown(), "and only the HUD")
    S.NS.SetRaceWindowShown("show")
    S.NS.LAUNCHER_DESCRIPTOR.toggleWindow()
    assertFalse(S.NS.Hud.IsShown() or S.NS.RaceWindow.IsShown(), "the launcher's entry closed both")
end)

test("hud toggle: /ct hud toggle and /ct hud hide close both; /ct hud show opens the HUD alone", function()
    if forever() then return end
    local S = fresh()
    both(S)
    S.NS.Slash:OnSlash("hud toggle")
    assertFalse(S.NS.Hud.IsShown() or S.NS.RaceWindow.IsShown(), "/ct hud toggle closed both")
    S.NS.Slash:OnSlash("hud toggle")
    assertTrue(S.NS.Hud.IsShown())
    assertFalse(S.NS.RaceWindow.IsShown(), "/ct hud toggle opened the HUD alone")
    S.NS.SetRaceWindowShown("show")
    S.NS.Slash:OnSlash("hud hide")
    assertFalse(S.NS.Hud.IsShown() or S.NS.RaceWindow.IsShown(), "/ct hud hide closed both")
    S.NS.Slash:OnSlash("hud show")
    assertTrue(S.NS.Hud.IsShown())
    assertFalse(S.NS.RaceWindow.IsShown(), "/ct hud show opened the HUD alone")
end)

test("hud toggle: the Race window's toggle closes it alone; opened with the HUD shut it opens both (W29 #3)", function()
    if forever() then return end
    local S = fresh()
    local Hud, RW = S.NS.Hud, S.NS.RaceWindow
    local hc = Hud.Closes()
    assertTrue(S.NS.ToggleRaceWindow())
    assertTrue(S.NS.ToggleRaceWindow())
    assertTrue(Hud.IsShown(), "the HUD stays up through the Race window's open and close")
    assertEqual(Hud.Closes(), hc)
    assertTrue(S.NS.ToggleHud())
    assertFalse(Hud.IsShown())
    assertTrue(S.NS.ToggleRaceWindow())
    assertTrue(RW.IsShown() and RW.Visible(), "the Race window opened")
    assertTrue(Hud.IsShown(), "the HUD opened first")
    assertTrue(Hud.Diagnose().byPlayer, "as the player's open, which never fades")
    -- `/ct race show` and the HUD's own toggle the same way.
    assertTrue(S.NS.ToggleHud())
    assertFalse(Hud.IsShown() or RW.Visible())
    assertTrue(S.NS.SetRaceWindowShown("show"))
    assertTrue(Hud.IsShown() and RW.Visible(), "/ct race show opened both")
end)

test("hud toggle: on WoW Forever, with no Race window, it closes and opens the HUD", function()
    if not forever() then return end
    local S = fresh()
    assertNil(S.NS.RaceWindow)
    assertTrue(S.NS.ToggleHud())
    assertFalse(S.NS.Hud.IsShown())
    S.NS.Slash:OnSlash("hud hide")
    assertTrue(S.NS.ToggleHud())
    assertTrue(S.NS.Hud.IsShown())
end)

-- ── one art size on the title bar (owner, 2026-11-13) ───────────────────────────────────────────

-- The visible box of a vendored 64 px TGA (32-bit, RLE or raw), top-down and end-exclusive:
-- { left, top, right, bottom } of the pixels with alpha above 0.
local function artBox(path)
    local fh = assert(io.open(path, "rb"))
    local d = fh:read("*a")
    fh:close()
    local w, h = d:byte(13) + d:byte(14) * 256, d:byte(15) + d:byte(16) * 256
    local rle, bottomUp = d:byte(3) == 10, math.floor(d:byte(18) / 32) % 2 == 0
    local i, n, alpha = 19 + d:byte(1), 0, {}
    while n < w * h do
        local count, packet = 1, false
        if rle then
            local c = d:byte(i)
            i = i + 1
            count = c % 128 + 1
            packet = c >= 128
        end
        for k = 1, count do
            alpha[n] = d:byte(i + 3)
            n = n + 1
            if not packet or k == count then i = i + 4 end
        end
    end
    local l, t, r, b = w, h, -1, -1
    for p = 0, w * h - 1 do
        if alpha[p] > 0 then
            local x, y = p % w, math.floor(p / w)
            if bottomUp then y = h - 1 - y end
            l, t, r, b = math.min(l, x), math.min(t, y), math.max(r, x), math.max(b, y)
        end
    end
    return { l, t, r + 1, b + 1 }
end

test("header art: every measured box is the vendored art's", function()
    local Style = T.NS.Style
    for name, box in pairs(Style.ART_BOX) do
        local got = artBox(T.root .. "/libs/LibKa0s/media/icons/" .. name .. ".tga")
        assertEqual(table.concat(got, ","), table.concat(box, ","), name .. "'s box")
    end
end)

-- A mark's texture size: its longest side, its width, its height.
local function fitted(tex)
    local w, h = tex:GetSize()
    return math.max(w, h), w, h
end

test("header art: every title-bar mark of the DPS HUD and the Race window is one size, the close too", function()
    local S, ui = fresh()
    local Style = S.NS.Style
    local marks = { ui.results, ui.settings, ui.lock, ui.close }
    if not forever() then
        marks[#marks + 1] = ui.race
        S.NS.SetRaceWindowShown("show")
        local rw = S.NS.RaceWindow.__ui()
        for _, b in ipairs({ rw.attach, rw.lock, rw.settings, rw.close }) do marks[#marks + 1] = b end
    end
    for i, b in ipairs(marks) do
        assertTrue(b.icon ~= nil, "mark " .. i .. " draws its art")
        local side = fitted(b.icon)
        assertTrue(math.abs(side - Style.CONTROL_ART) < 1e-6, "mark " .. i .. " (" .. tostring(b.iconName) .. "): " .. side)
    end
    -- The lock's art is narrower than its cell: cropped to its box, and taller than a whole-cell draw.
    S.NS.SetByPath("general.locked", true)
    local _, w, h = fitted(ui.lock.icon)
    assertEqual(h, Style.CONTROL_ART, "the lock's height is the longest side")
    assertTrue(math.abs(w - Style.CONTROL_ART * 48 / 56) < 1e-6, "its width in proportion")
    local l, t = ui.lock.icon:GetTexCoord()
    assertEqual(l, 8 / 64, "cropped to its box")
    assertEqual(t, 0)
end)

-- ── the toggle in a dummy session (owner, 2026-11-13) ───────────────────────────────────────────

local function dummyIn(S)
    S.M.__unitExists.target = true
    S.M.__unitGUIDs.target = F.DUMMY_GUID
    S.M.__fire("PLAYER_TARGET_CHANGED")
    assertTrue(S.NS.AutoArm.InSession(), "a dummy session")
end

local function dummyAway(S)
    S.M.__unitExists.target = false
    S.M.__unitGUIDs.target = nil
    S.M.__fire("PLAYER_TARGET_CHANGED")
    F.run(S, S.M.__now + S.NS.AutoArm.HIDE_DELAY)
    assertFalse(S.NS.AutoArm.InSession(), "the session ended")
end

local function bothShut(S)
    S.NS.Hud.Hide()
    S.NS.RaceWindow.Hide()
    assertFalse(S.NS.Hud.IsShown() or S.NS.RaceWindow.IsShown())
end

test("hud toggle: in a dummy session the opening toggle opens the Race window too, tied to the session", function()
    if forever() then return end
    local S = fresh()
    local Hud, RW = S.NS.Hud, S.NS.RaceWindow
    dummyIn(S)
    bothShut(S)
    assertTrue(S.NS.ToggleHud())
    assertTrue(Hud.IsShown(), "the HUD opened")
    assertTrue(RW.IsShown(), "and the Race window with it")
    assertTrue(RW.ShownNearDummy(), "tied to the dummy session, as RW.Show() ties it")
    dummyAway(S)
    assertFalse(RW.IsShown(), "walking away closes it")
    assertTrue(Hud.IsShown(), "the HUD the player opened stays")
end)

test("hud toggle: it opens the Race window even when the player closed it in the session", function()
    if forever() then return end
    local S = fresh()
    local Hud, RW = S.NS.Hud, S.NS.RaceWindow
    dummyIn(S)
    assertTrue(Hud.IsShown() and RW.IsShown(), "auto-show opened both")
    RW.Hide()
    assertFalse(RW.IsShown(), "the player's close of the Race window")
    assertTrue(S.NS.ToggleHud())
    assertFalse(Hud.IsShown(), "the closing toggle")
    assertTrue(S.NS.ToggleHud())
    assertTrue(Hud.IsShown() and RW.IsShown(), "the key is explicit: both open")
    -- The key and the launcher's entry, and /ct hud toggle, take the same rule.
    S.M.__frameByName[S.NS.TOGGLE_HUD_BUTTON]:__fire("OnClick", "LeftButton")
    assertFalse(Hud.IsShown() or RW.IsShown(), "the key closed both")
    S.M.__frameByName[S.NS.TOGGLE_HUD_BUTTON]:__fire("OnClick", "LeftButton")
    assertTrue(Hud.IsShown() and RW.IsShown(), "the key opened both")
    S.NS.LAUNCHER_DESCRIPTOR.toggleWindow()
    S.NS.LAUNCHER_DESCRIPTOR.toggleWindow()
    assertTrue(Hud.IsShown() and RW.IsShown(), "the launcher's entry opened both")
    S.NS.Slash:OnSlash("hud toggle")
    S.NS.Slash:OnSlash("hud toggle")
    assertTrue(Hud.IsShown() and RW.IsShown(), "/ct hud toggle opened both")
    S.NS.Slash:OnSlash("hud hide")
    S.NS.Slash:OnSlash("hud show")
    assertFalse(RW.IsShown(), "/ct hud show opens the HUD alone")
end)

test("hud toggle: with auto-show off, or Race mode off, the opening toggle opens the HUD alone", function()
    if forever() then return end
    local S = fresh()
    local Hud, RW = S.NS.Hud, S.NS.RaceWindow
    dummyIn(S)
    bothShut(S)
    assertTrue(S.NS.SetByPath("race.enabled", false))
    assertTrue(S.NS.ToggleHud())
    assertTrue(Hud.IsShown())
    assertFalse(RW.IsShown(), "Race mode off: no Race window")
    assertTrue(S.NS.SetByPath("race.enabled", true))
    bothShut(S)
    assertTrue(S.NS.SetByPath("race.autoShow", false))
    assertTrue(S.NS.SetByPath("race.autoShowHud", false))   -- either row is auto-show (W29 decision D4)
    assertTrue(S.NS.ToggleHud())
    assertTrue(Hud.IsShown())
    assertFalse(RW.IsShown(), "auto-show off: the HUD alone")
end)

test("hud toggle: away from a dummy the opening toggle opens the HUD alone", function()
    if forever() then return end
    local S = fresh()
    dummyIn(S)
    dummyAway(S)
    bothShut(S)
    assertTrue(S.NS.ToggleHud())
    assertTrue(S.NS.Hud.IsShown())
    assertFalse(S.NS.RaceWindow.IsShown(), "no session: the HUD alone")
end)

-- ── a race armed clears the HUD (owner, 2026-11-13) ─────────────────────────────────────────────

-- The texts the HUD's top draws now: the clock, Damage, DPS and the target line.
local function hudTexts(S)
    local ui = S.NS.Hud.__ui()
    local w = ui.body[ui.current].w
    return table.concat({ ui.current, w.clock:GetText() or "", w.damage.value:GetText() or "",
                          w.dps.value:GetText() or "", w.target:GetText() or "" }, "|")
end

local function spellRows(S)
    local ui = S.NS.Hud.__ui()
    return #ui.body[ui.current].parts.spells.list:Rows()
end

-- A fight of 7 s on the dummy, too short to save: the over card with its chips and spell rows.
local function shortFight(S)
    S.NS.Hud.Show()
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 7, 1)
    F.settle(S, start + 7)
    assertEqual(S.NS.Hud.State(), "over", "the over card")
    assertTrue(#S.NS.Hud.Chips() > 0, "with its chips")
    return start
end

test("hud race armed: the HUD drops the last fight and goes back to its look before any fight", function()
    if forever() then return end
    local pre = F.fresh{ target = false, mutate = installPaint }
    pre.NS.Hud.Show()
    local before = hudTexts(pre)
    local S = F.fresh{ mutate = installPaint }
    shortFight(S)
    assertTrue(spellRows(S) > 0, "the card's spell rows")
    assertTrue(hudTexts(S) ~= before, "the card differs from the look before any fight")
    assertTrue(F.arm(S, 30, 200))
    assertTrue(S.NS.Hud.IsShown(), "the window stays up")
    assertEqual(S.NS.Hud.State(), "live", "the body before any fight")
    assertEqual(hudTexts(S), before, "0:00.0, dashes, no target line")
    assertEqual(spellRows(S), 0, "an empty Spell breakdown")
    assertFalse(S.NS.Hud.__ui().body.over.frame:IsShown(), "no over card, so no chips")
    assertNil(S.NS.Hud.View().fight, "no fight held")
    -- Canceled back to idle: nothing brings the old fight back.
    assertTrue(S.NS.Race.Cancel())
    assertEqual(S.NS.Race.State(), "idle")
    assertEqual(hudTexts(S), before, "still the look before any fight")
    assertNil(S.NS.Hud.View().fight)
    -- Armed again, then the race's own fight goes live as any first hit does.
    assertTrue(F.arm(S, 30, 210))
    local start = F.pull(S, 211, 26)
    F.run(S, start + 0.25)
    assertEqual(S.NS.Hud.State() ~= "over" and S.NS.Hud.View().fight ~= nil, true, "the race's fight is live")
end)

test("hud race armed: an arm with the HUD closed opens both windows, the HUD showing no old fight", function()
    if forever() then return end
    local S = F.fresh{ mutate = installPaint }
    shortFight(S)
    S.NS.Hud.Hide()
    assertTrue(F.arm(S, 30, 200))
    assertTrue(S.NS.RaceWindow.IsShown(), "the arm opens the Race window")
    assertTrue(S.NS.Hud.IsShown(), "and the HUD first (W29 decision D3)")
    assertFalse(S.NS.Hud.Diagnose().byPlayer, "the race's open, not the player's")
    assertNil(S.NS.Hud.View().fight, "showing no old fight")
end)

-- ── the Race window is an extension of the HUD (owner, 2026-11-13, race window redesign plan W29) ──
-- T1: the Race window is never on screen while the HUD is hidden. T2: auto open and close stay in
-- step across both. Each case is one of the audit's violations (#1 to #7), reproduced and held to the
-- owner's decisions D1 to D4.

-- Both windows' decisions and the Race window's frame, together: the frame must never be up alone.
local function pair(S)
    local Hud, RW = S.NS.Hud, S.NS.RaceWindow
    if RW.Visible() then assertTrue(Hud.IsShown(), "T1: the Race window on screen with the HUD hidden") end
    return Hud.IsShown(), RW.IsShown()
end

-- A fresh instance on the dummy target with auto-show off (both its rows) and nothing open.
local function quiet()
    local S = F.fresh{ mutate = installPaint }
    assert(S.NS.SetByPath("race.autoShow", false))
    assert(S.NS.SetByPath("race.autoShowHud", false))
    S.NS.RaceWindow.HideAwayFromDummy()
    S.NS.Hud.HideAwayFromDummy()
    assertFalse(S.NS.Hud.IsShown() or S.NS.RaceWindow.IsShown())
    return S
end

-- An auto-opened HUD (a fight's first hit, `hud.show` "auto") with the player's Race window beside it.
local function autoPair()
    local S = quiet()
    local start = F.pull(S)
    F.run(S, start + 0.25)
    assertTrue(S.NS.Hud.IsShown(), "the first hit opened the HUD")
    assertFalse(S.NS.Hud.Diagnose().byPlayer, "the addon's open, which fades")
    S.NS.RaceWindow.Show()
    assertFalse(S.NS.Hud.Diagnose().byPlayer, "the HUD up already stays the addon's")
    return S, start
end

-- Let the fade's deadline pass and service it.
local function fadeOut(S)
    local at = S.NS.Hud.FadeAt()
    assertTrue(at ~= nil, "a fade runs")
    F.run(S, at + 0.1)
end

test("w29 #1: the HUD's fade takes the Race window with it; the next fight's HUD brings it back", function()
    if forever() then return end
    local S, start = autoPair()
    local RW = S.NS.RaceWindow
    F.damage(S, 25, start + 1, start + 7, 1)
    F.settle(S, start + 7)
    assertEqual(S.NS.Hud.State(), "over")
    fadeOut(S)
    local hud, race = pair(S)
    assertFalse(hud, "the HUD faded")
    assertFalse(race or RW.Visible(), "the Race window went with it")
    assertEqual(RW.Closes(), 0, "hiding with the HUD is not the player's close")
    local s2 = F.pull(S, start + 40, 26)
    F.run(S, s2 + 0.25)
    hud, race = pair(S)
    assertTrue(hud and race and RW.Visible(), "the HUD came back, and the still wanted Race window with it")
end)

test("w29 #1: hud.overCard off closes the HUD at the fight's end, the Race window with it", function()
    if forever() then return end
    local S, start = autoPair()
    assertTrue(S.NS.SetByPath("hud.overCard", false))
    F.damage(S, 25, start + 1, start + 7, 1)
    F.settle(S, start + 7)
    local hud, race = pair(S)
    assertFalse(hud, "the end-of-fight close")
    assertFalse(race or S.NS.RaceWindow.Visible(), "the Race window closed with it")
end)

test("w29 #2: the HUD's close control hides the Race window, still wanted, back with the HUD", function()
    if forever() then return end
    local S, ui = fresh()
    local RW = S.NS.RaceWindow
    both(S)
    click(ui.close)
    local hud, race = pair(S)
    assertFalse(hud or race or RW.Visible(), "both down")
    assertEqual(RW.Closes(), 0, "the HUD's close is not the Race window's")
    S.NS.Hud.Show()
    hud, race = pair(S)
    assertTrue(hud and race and RW.Visible(), "the HUD's open brings the Race window back")
end)

test("w29 #2: Escape closes both, each as the player's close, whichever the close list reaches first", function()
    if forever() then return end
    for _, raceFirst in ipairs({ false, true }) do
        local S = fresh()
        local Hud, RW = S.NS.Hud, S.NS.RaceWindow
        both(S)
        local hc, rc = Hud.Closes(), RW.Closes()
        local frames = { Hud.Frame(), RW.__ui().frame }
        if raceFirst then frames = { frames[2], frames[1] } end
        for _, f in ipairs(frames) do
            if f:IsShown() then
                f:Hide()
                f:__fire("OnHide")
            end
        end
        assertFalse(Hud.IsShown() or RW.IsShown() or RW.Visible(), "both closed")
        assertEqual(Hud.Closes(), hc + 1, "the HUD's close counted")
        assertEqual(RW.Closes(), rc + 1, "the Race window's close counted, once")
        Hud.Show()
        assertFalse(RW.IsShown(), "the Race window closed by Escape stays closed")
    end
end)

test("w29 #4: a result with the HUD closed by the player opens both windows", function()
    if forever() then return end
    local S = quiet()
    local Hud, RW = S.NS.Hud, S.NS.RaceWindow
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 10, 1)
    click(Hud.__ui().close)
    local hud, race = pair(S)
    assertFalse(hud or race, "the player closed the HUD mid-race: both down")
    F.damage(S, 25, start + 11, start + 30, 1)
    F.settle(S, start + 31)
    assertEqual(S.NS.Race.State(), "result")
    hud, race = pair(S)
    assertTrue(hud and race and RW.Visible(), "the result opened both")
    assertEqual(RW.View().key, "result")
end)

test("w29 #5: the stand-up brings the player's Race window back with the HUD first", function()
    if forever() then return end
    local S = autoPair()
    local RW = S.NS.RaceWindow
    assertTrue(S.NS.SetByPath("general.enabled", false))
    assertFalse(RW.Visible() or S.NS.Hud.IsShown(), "stood down: both down")
    assertTrue(S.NS.SetByPath("general.enabled", true))
    local hud, race = pair(S)
    assertTrue(hud and race and RW.Visible(), "stood up: the player's Race window and the HUD under it")
end)

test("w29 #5: Race mode back on brings a wanted Race window back with the HUD first", function()
    if forever() then return end
    local S = fresh()
    local RW = S.NS.RaceWindow
    both(S)
    S.NS.Hud.Hide()
    assertFalse(RW.Visible(), "down with the HUD, still wanted")
    assertTrue(S.NS.SetByPath("race.enabled", false))
    assertTrue(S.NS.SetByPath("race.enabled", true))
    local hud, race = pair(S)
    assertTrue(hud and race and RW.Visible(), "Race mode on opened both")
end)

test("w29 D2: no fade while the race holds the HUD; the race's idle edge starts it, and both go", function()
    if forever() then return end
    local S = quiet()
    local Hud, RW = S.NS.Hud, S.NS.RaceWindow
    assertTrue(F.arm(S, 30))
    assertTrue(Hud.IsShown() and RW.IsShown(), "the arm opened both")
    assertNil(Hud.FadeAt(), "armed: no fade")
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 30, 1)
    F.settle(S, start + 31)
    assertEqual(S.NS.Race.State(), "result")
    assertEqual(Hud.State(), "over")
    assertNil(Hud.FadeAt(), "the result card: no fade")
    F.run(S, start + 31 + 60)
    assertTrue(Hud.IsShown() and RW.Visible(), "still up a minute on")
    RW.Act.newRace()
    assertEqual(S.NS.Race.State(), "idle")
    assertTrue(Hud.FadeAt() ~= nil, "idle again: the over card fades")
    fadeOut(S)
    local hud, race = pair(S)
    assertFalse(hud or race, "both gone")
end)

test("w29 D2: a fade running when a race is armed is dropped; a HUD the race opened closes with it", function()
    if forever() then return end
    local S, start = autoPair()
    local Hud, RW = S.NS.Hud, S.NS.RaceWindow
    F.damage(S, 25, start + 1, start + 7, 1)
    F.settle(S, start + 7)
    assertTrue(Hud.FadeAt() ~= nil)
    assertTrue(F.arm(S, 30, start + 9))
    assertNil(Hud.FadeAt(), "the arm dropped the fade")
    F.run(S, start + 60)
    assertTrue(Hud.IsShown() and RW.Visible(), "the armed race holds both")
    -- A HUD the arm itself opened (Hud.ShowForRace) goes back down with the race.
    local S2 = quiet()
    assertTrue(F.arm(S2, 30))
    assertTrue(S2.NS.Hud.IsShown() and S2.NS.RaceWindow.IsShown())
    S2.NS.Race.Cancel()
    local hud, race = pair(S2)
    assertFalse(hud or race, "canceled: both the race opened close together")
end)

test("w29 #7: a profile switch to one whose HUD is always up opens it", function()
    if forever() then return end
    local S = quiet()
    S.NS.db:SetProfile("Always")
    assertTrue(S.NS.SetByPath("hud.show", "always"))
    S.NS.db:SetProfile("Default")
    S.NS.Hud.Hide()
    assertFalse(S.NS.Hud.IsShown())
    S.NS.db:SetProfile("Always")
    assertTrue(S.NS.Hud.IsShown(), "the always-up profile's HUD")
end)
