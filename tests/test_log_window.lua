-- tests/test_log_window.lua — the Combat Log's detached window, "Combat Trail · Log" (CombatTrail #11,
-- plan item CL-11b2; the spec's addendum, home B): the drawer's detach mark and the window's dock mark
-- moving the log between its homes with the log kept open, the HUD giving the drawer's height back;
-- the window wider, with the Info column; following the HUD, hidden and back with it, unless pinned;
-- the player's close (Escape, the close mark) closing the log, the HUD's hide not; attached LEFT
-- beside the HUD by default, at the HUD's height with its rows filling it; standing free at its own
-- place, scale and stored size; the grip's drag repainting nothing until its release; the rows setting
-- with fill off; the live feed with its pause and Resume; `/ct log detach|dock|pin|unpin`. The Race
-- window's side of it (Retail) is in tests/test_race_window.lua. Runs under both kit profiles.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local FIREBALL = 133

-- A fresh instance whose named frames (the HUD's, the log window's, the Race window's) record the size
-- and scale the code sets: the kit's frames answer no geometry unless armed.
local function fresh()
    local geom = {}
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        m.__unitExists.target = true
        m.__unitNames.target = "Angry Boar"
        m.UnitCanAttack = function() return true end
        local create = m.CreateFrame
        m.CreateFrame = function(kind, name, ...)
            local f = create(kind, name, ...)
            if type(name) ~= "string" then return f end
            local g = {}
            geom[name] = g
            rawset(f, "SetSize", function(_, w, h) g.w, g.h = w, h end)
            rawset(f, "SetWidth", function(_, w) g.w = w end)
            rawset(f, "SetHeight", function(_, h) g.h = h end)
            rawset(f, "SetScale", function(_, v) g.scale = v end)
            return f
        end
    end }
    inst.mocks.__now = 100
    inst.geom = geom
    return inst, inst.NS
end

local function click(b) b:GetScript("OnClick")(b, "LeftButton") end

-- The HUD up and the log open, then detached by the drawer's own mark.
local function detached(NS)
    NS.Hud.Show()
    NS.HudLog.SetShown(true)
    click(NS.HudLog.__ui().detach)
    return NS.LogWindow.__ui()
end

local function columns(view)
    local keys = {}
    for _, c in ipairs(view.cols) do keys[c.key] = true end
    return keys
end

test("log window: the drawer's detach mark moves the log into its own window, and the HUD gives the drawer's height back", function()
    local _, NS = fresh()
    NS.Hud.Show()
    local bare = NS.Hud.Height()
    NS.HudLog.SetShown(true)
    assertTrue(NS.Hud.Height() > bare, "docked: the HUD grew by the drawer")
    local d = NS.HudLog.__ui()
    assertEqual(d.detach.iconName, "export", "the drawer's header carries the detach mark")
    click(d.detach)
    assertEqual(NS.GetSetting("log.home"), "detached", "saved detached")
    assertTrue(NS.GetSetting("log.drawer.shown"), "still open")
    assertTrue(NS.LogWindow.Visible(), "the window is up")
    assertFalse(d.frame:IsShown(), "the drawer is gone from the HUD")
    assertEqual(NS.HudLog.Height(), 0)
    assertEqual(NS.Hud.Height(), bare, "the HUD back to its height")
    assertFalse(NS.HudLog.Ticking(), "the drawer's timer stopped")
    assertTrue(NS.LogWindow.Ticking(), "the window's own runs")
    local ui = NS.LogWindow.__ui()
    assertEqual(ui.frame.title:GetText(), "Combat Trail \194\183 Log")
end)

test("log window: the dock mark sends it back to the HUD, still open", function()
    local _, NS = fresh()
    local ui = detached(NS)
    assertEqual(ui.dock.iconName, "arrow-left")
    assertTrue(ui.settings ~= nil, "it keeps a saved place, so it is no companion: it carries the settings mark")
    click(ui.dock)
    assertEqual(NS.GetSetting("log.home"), "docked")
    assertFalse(NS.LogWindow.Visible(), "the window went")
    assertFalse(NS.LogWindow.Ticking())
    assertTrue(NS.HudLog.__ui().frame:IsShown(), "the drawer is back under the spell rows")
    assertTrue(NS.GetSetting("log.drawer.shown"))
end)

test("log window: wider than the drawer, with the Info column", function()
    local inst, NS = fresh()
    local ui = detached(NS)
    assertEqual(inst.geom[NS.LogWindow.FRAME_NAME].w, 460, "460 wide by default")
    assertTrue(columns(ui.table).info, "the window shows Info")
    assertTrue(columns(ui.table).spell and columns(ui.table).amount, "and every other column")
    assertTrue(not columns(ui.table).source and not columns(ui.table).target, "no Source or Target (item 3)")
    click(ui.dock)
    assertTrue(not columns(NS.HudLog.__ui().table).info, "the drawer never does")
end)

test("log window: it follows the HUD, hidden and back with it, unless pinned", function()
    local _, NS = fresh()
    detached(NS)
    local LW = NS.LogWindow
    NS.Hud.Hide()
    assertFalse(LW.Visible(), "hidden with the HUD")
    assertFalse(LW.Ticking(), "and its timer stopped")
    assertTrue(LW.Wanted(), "still wanted: hiding with the HUD is not the player's close")
    NS.Hud.Show()
    assertTrue(LW.Visible(), "back with the HUD")
    NS.Slash:OnSlash("log pin")
    assertTrue(NS.GetSetting("log.window.pinned"))
    NS.Hud.Hide()
    assertTrue(LW.Visible(), "pinned: it stays up while the HUD is hidden")
    assertTrue(LW.Ticking())
    NS.Slash:OnSlash("log unpin")
    assertFalse(LW.Visible(), "unpinned with the HUD hidden: it goes")
end)

test("log window: Escape and its close mark close the log; the HUD's hide does not", function()
    local _, NS = fresh()
    local ui = detached(NS)
    -- The client runs OnHide inside Hide: so does this frame here.
    local hide = ui.frame.Hide
    rawset(ui.frame, "Hide", function(self)
        local was = self:IsShown()
        hide(self)
        if was then self:__fire("OnHide") end
        return self
    end)
    ui.frame:Hide()
    assertFalse(NS.GetSetting("log.drawer.shown"), "Escape: the player closed the log")
    assertFalse(NS.LogWindow.Visible())
    NS.HudLog.SetShown(true)
    assertTrue(NS.LogWindow.Visible(), "the Log control opens it again, still detached")
    click(ui.close)
    assertFalse(NS.GetSetting("log.drawer.shown"), "its close mark closes the log")
    NS.HudLog.SetShown(true)
    NS.Hud.Hide()
    assertFalse(NS.LogWindow.Visible(), "hidden with the HUD")
    assertTrue(NS.GetSetting("log.drawer.shown"), "a hide with the HUD leaves the log open")
end)

test("log window: attached LEFT beside the HUD by default, at the HUD's scale and height", function()
    local inst, NS = fresh()
    detached(NS)
    local a = NS.LogWindow.Anchor()
    assertEqual(NS.LogWindow.DockSide(), "LEFT", "left by default: the Race window's default is right")
    assertEqual(a[1], "TOPRIGHT")
    assertTrue(a[2] == NS.Hud.Frame(), "beside the HUD's window")
    assertEqual(a[3], "TOPLEFT")
    local g, hud = inst.geom[NS.LogWindow.FRAME_NAME], inst.geom[NS.Hud.FRAME_NAME]
    assertEqual(g.h, NS.Hud.Height(), "the HUD's height")
    assertEqual(g.h, hud.h)
    assertEqual(g.scale, NS.GetSetting("hud.scale") or 1, "the HUD's scale")
    -- The HUD grows: the window follows the next time the HUD draws.
    assertTrue(NS.SetByPath("hud.bars", 12))
    assertEqual(g.h, hud.h, "it follows the HUD's height")
end)

test("log window: its rows fill the height it has", function()
    local _, NS = fresh()
    local ui = detached(NS)
    local LW, LT = NS.LogWindow, NS.LogTable
    local h = LW.WindowHeight()
    local chrome = LW.MinHeight() - LW.MIN_ROWS * LT.ROW_H
    assertEqual(ui.table.nRows, math.floor((h - chrome) / LT.ROW_H), "as many rows as fit")
    assertTrue(ui.table.nRows > LW.MIN_ROWS, "the HUD's height holds more than the least")
end)

test("log window: with fill off its rows are the rows setting, and the window is as tall as they are", function()
    local inst, NS = fresh()
    detached(NS)
    local LW = NS.LogWindow
    NS.db.profile.log.window.attached = false
    NS.db.profile.log.window.fill = false
    NS.db.profile.log.window.rows = 6
    NS.AnnounceSettingsChanged("log.window.rows", 6)
    local ui = LW.__ui()
    assertEqual(ui.table.nRows, 6)
    assertEqual(LW.Rows(), 6)
    local g = inst.geom[LW.FRAME_NAME]
    assertEqual(g.h, LW.MinHeight() + 3 * NS.LogTable.ROW_H, "the chrome and six rows")
    NS.db.profile.log.window.rows = 99
    assertEqual(LW.RowsSetting(), LW.MAX_ROWS, "held to the most")
end)

test("log window: standing on its own it takes its saved place and scale; the attach mark lets it go", function()
    local inst, NS = fresh()
    local ui = detached(NS)
    local LW = NS.LogWindow
    NS.db.profile.log.window.scale = 1.25
    click(ui.attach)
    assertFalse(NS.GetSetting("log.window.attached"), "standing on its own")
    local a = LW.Anchor()
    assertTrue(a[2] == inst.mocks.UIParent, "at its own place")
    assertEqual(inst.geom[LW.FRAME_NAME].scale, 1.25, "at its own scale")
    assertTrue(ui.attach.iconName ~= "move", "the mark now points back toward the HUD")
    click(ui.attach)
    assertTrue(NS.GetSetting("log.window.attached"))
    assertTrue(LW.Anchor()[2] == NS.Hud.Frame(), "beside the HUD again")
end)

test("log window: a grip drag lays out cheaply and repaints nothing until its release, then stores the size", function()
    local inst, NS = fresh()
    local ui = detached(NS)
    local LW, M = NS.LogWindow, inst.mocks
    NS.db.profile.log.window.attached = false
    NS.AnnounceSettingsChanged("log.window.attached", false)
    local draws = { n = 0 }
    local orig = ui.table.Draw
    rawset(ui.table, "Draw", function(...) draws.n = draws.n + 1; return orig(...) end)
    local f, grip = ui.frame, ui.frame.resizeGrip
    assertTrue(grip ~= nil, "the window has the library's grip")
    grip:__fire("OnMouseDown", "LeftButton")
    for k = 1, 20 do
        M.__now = M.__now + 1 / 60
        f:__fire("OnSizeChanged", 460 + 10 * k, 300 + 8 * k)
    end
    assertEqual(draws.n, 0, "nothing repainted while the grip is held")
    assertEqual(ui.table.nRows, LW.Rows(460), "the visible rows follow the drag")
    assertTrue(NS.db.profile.log.window.width == 460, "nothing stored while the grip is held")
    rawset(f, "GetWidth", function() return 660 end)
    rawset(f, "GetHeight", function() return 460 end)
    grip:__fire("OnMouseUp")
    assertTrue(draws.n >= 1, "repainted at the release")
    assertEqual(NS.db.profile.log.window.width, 660, "the width stored on release")
    assertEqual(NS.db.profile.log.window.height, 460, "and the height")
    assertEqual(inst.geom[LW.FRAME_NAME].w, 660)
    assertEqual(inst.geom[LW.FRAME_NAME].h, 460)
end)

test("log window: it paints the newest fight's lines with their Info; the wheel pauses it, Resume follows", function()
    local inst, NS = fresh()
    local ui = detached(NS)
    NS.CombatLog.Begin("f1", 100)
    for i = 1, 20 do NS.CombatLog.OnCast("player", FIREBALL, 100 + i * 0.1) end
    NS.CombatLog.OnCombat("player", "WOUND", "CRITICAL", 2000, 4, 102.5)
    inst.mocks.__now = 103
    NS.LogWindow.Paint()
    local rows = ui.table:Rows()
    assertEqual(rows[1].text.event:GetText(), "HIT", "the newest at the top")
    assertEqual(rows[1].text.info:GetText(), "Critical", "the Info column says what the client gave")
    assertTrue(ui.footLeft:GetText():find("shown") ~= nil, "the footer counts the lines")
    ui.table.frame:GetScript("OnMouseWheel")(ui.table.frame, -1)
    assertTrue(NS.LogTable.Paused(NS.LogWindow.__feed()), "scrolled away: paused")
    assertTrue(ui.resume:IsShown())
    assertEqual(ui.status:GetText(), "Paused")
    click(ui.resume)
    assertFalse(NS.LogTable.Paused(NS.LogWindow.__feed()))
    assertFalse(ui.resume:IsShown())
end)

test("log window: its chips filter what it shows, for the session, seeded from What to show", function()
    local inst, NS = fresh()
    local ui = detached(NS)
    local b = ui.chips.buttons
    for _, chip in ipairs(NS.LogTable.CHIPS) do
        assertTrue(b[chip.key]:IsShown(), chip.key .. " under the status line")
        assertEqual(b[chip.key].styleName, "primary", chip.key .. " lit: log.show is all on")
    end
    NS.CombatLog.Begin("f1", 100)
    NS.CombatLog.OnCast("player", FIREBALL, 100.5)
    NS.CombatLog.OnCombat("player", "WOUND", "", 2000, 4, 101)
    inst.mocks.__now = 101.5
    NS.LogWindow.Paint()
    local rows = ui.table:Rows()
    assertEqual(rows[1].text.event:GetText(), "HIT")
    click(b.taken)
    assertEqual(b.taken.styleName, "normal", "off")
    assertEqual(rows[1].text.event:GetText(), "CAST", "the hit is hidden at once")
    assertTrue(NS.GetSetting("log.show.hits"), "never written to the settings")
    assertTrue(NS.HudLog.__show().hits ~= false, "the drawer's own chips untouched")
    NS.SendBus(NS.MSG.FIGHT_STARTED, { id = "f2", startT = 102 })
    NS.LogWindow.Paint()
    assertEqual(b.taken.styleName, "primary", "a new fight seeds the chips from log.show again")
    NS.SetByPath("log.show.casts", false)
    NS.LogWindow.Paint()
    assertEqual(b.casts.styleName, "normal", "a What to show write seeds them too")
    click(b.casts)
    assertTrue(NS.LogWindow.__show().casts, "a click turns the chip back on for this window")
    assertEqual(NS.GetSetting("log.show.casts"), false, "the default stays as written")
end)

test("log window: the chips take their room above the table, wrapping when narrow", function()
    local _, NS = fresh()
    local ui = detached(NS)
    local lt = NS.LogTable
    assertEqual(lt.ChipLines(NS.LogWindow.Width() - 24), 1, "one line at 460")
    local f, y = ui.table.frame, nil
    local setPoint = f.SetPoint
    rawset(f, "SetPoint", function(self, p, rel, rp, x, yy)
        if p == "TOPLEFT" then y = yy end
        return setPoint(self, p, rel, rp, x, yy)
    end)
    NS.LogWindow.Refresh()
    assertEqual(y, -(NS.LogWindow.LINE_H + lt.ChipsHeight(436) + lt.CHIP_GAP), "the table under the chips")
    assertTrue(lt.ChipLines(150) > 1, "a narrow width wraps them")
end)

test("log window: /ct log detach and dock move it; the HUD's Log control opens and closes it", function()
    local _, NS = fresh()
    NS.Slash:OnSlash("log")
    NS.Slash:OnSlash("log detach")
    assertTrue(NS.LogWindow.Visible())
    local hud = NS.Hud.__ui()
    click(hud.log)
    assertFalse(NS.LogWindow.Visible(), "the Log control closes it")
    click(hud.log)
    assertTrue(NS.LogWindow.Visible(), "and opens it")
    NS.Slash:OnSlash("log dock")
    assertFalse(NS.LogWindow.Visible())
    assertTrue(NS.HudLog.__ui().frame:IsShown())
end)

test("log window: with the Combat Log off it never shows", function()
    local _, NS = fresh()
    detached(NS)
    NS.db.profile.log.enabled = false
    NS.AnnounceSettingsChanged("log.enabled", false)
    assertFalse(NS.LogWindow.Visible())
    assertFalse(NS.LogWindow.Ticking())
end)

test("log window: on WoW Forever there is no Race window, and it stands beside the HUD the same way", function()
    if not T.NS.Compat.IsForever() then return end
    local _, NS = fresh()
    detached(NS)
    assertTrue(NS.RaceWindow == nil)
    NS.db.profile.log.window.side = "RIGHT"
    NS.AnnounceSettingsChanged("log.window.side", "RIGHT")
    assertTrue(NS.LogWindow.Anchor()[2] == NS.Hud.Frame())
    assertEqual(NS.LogWindow.Anchor()[1], "TOPLEFT")
end)
