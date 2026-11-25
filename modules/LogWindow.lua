local _, NS = ...
-- modules/LogWindow.lua — the Combat Log's detached companion window, "Combat Trail · Log" (CombatTrail
-- #11, plan item CL-11b2; the spec's addendum, home B): the same table as the HUD's docked drawer
-- (modules/LogTable.lua, LogTable_View.lua) over the capture's ring (modules/CombatLog.lua), in a
-- window of its own, wider, with the Info column.
--
-- WHERE THE LOG LIVES. `log.home` "docked" (the default) puts it in the DPS HUD's drawer
-- (modules/Hud_Log.lua); "detached" puts it here. The drawer's detach mark (export) and `/ct log
-- detach` send it here; this window's dock mark (arrow-left) and `/ct log dock` send it back. The log's
-- open is one switch in either home, `log.drawer.shown` (the HUD's Log control, `/ct log`, the
-- auto-open at a fight's start), so a move keeps it open. Detached, the HUD reserves no drawer height.
--
-- TWO STATES, NO THIRD (owner feedback item 11, 2026-11-25). Docked, the log is the HUD's drawer;
-- detached, it is this STANDALONE window: up while the log is open and detached, whether or not the
-- HUD is up, at its own saved place and size. The attached state (beside the HUD, following it, its
-- pin, side and HUD-height match) is retired with its keys (schema step 6), its attach mark and
-- `/ct log pin|unpin`, so nothing here stands beside the HUD or the Race window, and neither of them
-- moves it. The HUD's Refresh ends in HudLog.Sync, which calls LW.Settle: a comparison that brings
-- the frame in line with the decision (the login, a stand-up), never a follow. The player's close
-- (its close mark, Escape) closes the log (`log.drawer.shown` off), as the drawer's Log control does.
--
-- WHERE IT STANDS: at `log.window.position`, dragged by its title bar (never while locked), at its
-- own `log.window.scale`.
--
-- ITS SIZE. Its width is `log.window.width` (MIN_WIDTH to MAX_WIDTH; 460 by default, room for every
-- column with Info); its height `log.window.height`, set by the grip (0: the height of
-- `log.window.rows` rows). With `log.window.fill` on (the default) the rows fill the height the window
-- has; off, the rows are `log.window.rows` (3-40) and the window is as tall as they are. The rows past
-- them scroll with the wheel, the Spell breakdown's indicator in the gutter (owner feedback item 6,
-- LogTable's View:SetScroll). THE GRIP (modules/Sizing.lua, standalone-windows *Resizing*): while it is
-- held only the cheap layout runs (the size, the columns, the visible rows); the release stores the
-- width and the height and repaints once.
--
-- THE CHIPS (Casts, Pet, Buffs, Debuffs, Taken, Heals; LogTable.NewChips) stand under the status
-- line, wrapped at the window's width: the window's own What to show, seeded from `log.show.*` when it
-- is built, when the log is opened or moved here, at each FIGHT_STARTED and at a What to show write
-- (LogTable.Reseeds); a click turns one on or off here alone, for the session, never in the settings.
--
-- THE LOOK is the DPS HUD's, as the Race window's is: the same shell (NS.ApplySkin, the title band,
-- NS.MakeHeader's marks: Dock, Settings, Close; the library footer) and the HUD's `hud.window.*`
-- blocks, restyled once per Appearance stamp; its own opacity, `log.window.alpha`, over the HUD's.
-- It keeps a saved position, so it is not a companion in the standard's sense (standalone-windows,
-- *A companion window carries no settings mark*): it carries the settings mark.
--
-- WHAT RUNS. Nothing on a client event. While it is on screen one repeating AceTimer at
-- NS.Constants.LOG.REPAINT (0.1 s) moves its own feed (LogTable.Advance, by the display throttle) and
-- repaints only when the feed, the pause or a setting moved; it stops the moment the window hides. Its
-- bus receivers: FIGHT_STARTED (the feed follows again) and SETTINGS_CHANGED on `log.`, `hud.` and
-- `general.` paths. The stand-down hides it and drops the timer and the feed.
--
-- SECRETS. Nothing here reads a frame's geometry back but the drag's own anchor (stored plain), and
-- every amount goes to a label through the table's cells (NS.Format.Number), never compared.

local LW = {}
NS.LogWindow = LW

local L = NS.L
local Style = NS.Style
local Secrets = NS.Secrets
local LogTable = NS.LogTable
local CL = NS.CombatLog

LW.FRAME_NAME = "CombatTrailLogWindow"
LW.MIN_WIDTH, LW.MAX_WIDTH = 320, 900
LW.MAX_HEIGHT = 1000
LW.MIN_ROWS, LW.MAX_ROWS = 3, 40
LW.LINE_H = 18          -- the status line over the table: Following or Paused, and Resume

local HEADER_H, PAD = Style.TITLE_BAR_H, 12

local ui                -- the built window
local feed              -- its live feed (LogTable.NewFeed)
local timer
local dirty = true
local hiding = false    -- this file is hiding the frame (not the player's close)
local locked = false
local anchor            -- the last place applied: { point, relativeTo, relPoint, x, y }
local ctx, show = {}, {}
local seeded = false    -- `show` holds the window's own chips (seeded from `log.show`)

local function setting(path) return NS.GetSetting and NS.GetSetting(path) end
local function write(path, value) if NS.SetByPath then NS.SetByPath(path, value) end end
local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end
local function isDown() return NS.IsStoodDown ~= nil and NS.IsStoodDown() end
local function windowShown() return ui ~= nil and ui.frame:IsShown() == true end
local function accept(e) return LogTable.Shows(e, show) end

-- The stored geometry the drag and the grip write (geometry only they determine, architecture-§5),
-- in the profile's own table.
local function store()
    local p = NS.db and NS.db.profile
    local log = p and p.log
    if type(log) ~= "table" then return nil end
    if type(log.window) ~= "table" then log.window = {} end
    if type(log.window.position) ~= "table" then log.window.position = {} end
    return log.window
end

-- Whether the grip is held now (the size it tracked is the one to lay out from).
local function sizing()
    return ui ~= nil and ui.dragW ~= nil and NS.Sizing.IsSizing(ui.frame)
end

local function fill() return setting("log.window.fill") ~= false end

-- ── the decision ────────────────────────────────────────────────────────────────────────────────

--- Whether the log is wanted here: open (`log.drawer.shown`, the Combat Log on) and detached.
function LW.Wanted()
    local H = NS.HudLog
    return H ~= nil and H.Open() and H.Home() == "detached"
end

--- Whether the window decides to be up: wanted and the addon standing (the HUD's state is not asked).
function LW.IsShown()
    return LW.Wanted() and not isDown()
end

--- Whether the frame is on screen now.
function LW.Visible() return windowShown() end

--- The window's frame, or nil before its first show builds it.
function LW.Frame() return ui and ui.frame or nil end

-- ── the size ────────────────────────────────────────────────────────────────────────────────────

local function contentTop() return setting("hud.window.titleBar") ~= false and HEADER_H + 10 or PAD end
local function contentBottom() return setting("hud.window.footer") ~= false and NS.FOOTER_HEIGHT + 8 or PAD end

-- The chips' room under the status line at the window's width, the gap under them included.
local function chipsRoom()
    return LogTable.ChipsHeight(LW.Width() - 2 * PAD) + LogTable.CHIP_GAP
end

-- The window's height less the rows: the chrome, the status line, the chips and the table's column
-- header.
local function chrome()
    return contentTop() + contentBottom() + LW.LINE_H + chipsRoom() + LogTable.HEAD_H
end

--- The rows `log.window.rows` asks for, whole and in range.
function LW.RowsSetting()
    local v = Secrets.PlainNumber(setting("log.window.rows")) or 12
    return clamp(math.floor(v), LW.MIN_ROWS, LW.MAX_ROWS)
end

--- The window's least height: its chrome and MIN_ROWS rows.
--- @return number
function LW.MinHeight()
    return chrome() + LW.MIN_ROWS * LogTable.RowH()
end

-- The height of `rows` rows with the chrome.
local function heightFor(rows) return chrome() + rows * LogTable.RowH() end

--- The height the window has now: the grip's while it is held, else `log.window.height` with `fill`
--- on (0: the rows setting's), else the rows setting's; never less than its least.
--- @return number
function LW.WindowHeight()
    local least = LW.MinHeight()
    if sizing() and ui.dragH and fill() then return ui.dragH end
    local stored = Secrets.PlainNumber(setting("log.window.height")) or 0
    if not fill() or stored <= 0 then return heightFor(LW.RowsSetting()) end
    return clamp(stored, least, LW.MAX_HEIGHT)
end

--- The width the window has now: the grip's while it is held, else `log.window.width`, in range.
--- @return number
function LW.Width()
    local w = sizing() and ui.dragW or Secrets.PlainNumber(setting("log.window.width"))
    return clamp(w or 460, LW.MIN_WIDTH, LW.MAX_WIDTH)
end

--- The rows shown in a window `h` tall: as many as fit (fill), else the rows setting, never more than
--- fit and never fewer than MIN_ROWS.
--- @return number
function LW.Rows(h)
    local fit = math.max(LW.MIN_ROWS, math.floor(((h or LW.WindowHeight()) - chrome()) / LogTable.RowH()))
    if fill() then return fit end
    return math.min(LW.RowsSetting(), fit)
end

-- ── the window ──────────────────────────────────────────────────────────────────────────────────

local Act = {}
LW.Act = Act

local function canDrag() return not locked end

-- The place the drag left the frame (the client's anchor), stored plain.
local function savePosition()
    local w = store()
    if not (w and ui) then return end
    local point, _, relPoint, x, y = ui.frame:GetPoint(1)
    if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return end
    local p = w.position
    p.point, p.relPoint = point, type(relPoint) == "string" and relPoint or point
    p.x, p.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

local function edgeOf(f, name)
    local fn = f[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, f)
    return ok and Secrets.PlainNumber(v) or nil
end

-- The window's place where it stands now, as its own place (the grip's release keeps its top left).
local function keepWhereItStands()
    local w = store()
    if not (w and ui) then return end
    local left, top = edgeOf(ui.frame, "GetLeft"), edgeOf(ui.frame, "GetTop")
    if not (left and top) then return end
    local p = w.position
    p.point, p.relPoint = "TOPLEFT", "BOTTOMLEFT"
    p.x, p.y = math.floor(left + 0.5), math.floor(top + 0.5)
end

local function buildHeader(f)
    f.title = f:CreateFontString(nil, "OVERLAY", Style.FONT.TITLE)
    f.title:SetText(L["Combat Trail \194\183 Log"])
    local hb = NS.MakeHeader(f, {
        close = function() Act.close() end, settings = function() Act.settings() end,
        settingsTip = L["Combat Log settings"],
        extras = {
            { key = "dock", icon = "arrow-left", glyph = "D", tip = L["Dock the Combat Log back in the DPS HUD"],
              onClick = function() Act.dock() end },
        },
    })
    ui.close, ui.settings, ui.dock = hb.close, hb.settings, hb.extras.dock
    local drag = CreateFrame("Frame", nil, f)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() if canDrag() then f:StartMoving() end end)
    drag:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        savePosition()
    end)
    ui.drag = drag
    Style.Header(f, { title = f.title, align = "LEFT", drag = drag,
        right = { ui.close, ui.settings, ui.dock }, n = 3 })
end

local function onSort()
    write("log.view.sort", LogTable.SortOf() == "newest" and "oldest" or "newest")
end

local function onScroll(away)
    if not feed then return end
    LogTable.Scroll(feed, away)
    dirty = true
    LW.Paint()
end

local function buildBody(f)
    local c = CreateFrame("Frame", nil, f)
    ui.content = c
    ui.status = Style.Text(c, Style.FONT.CAPTION, nil, "LEFT")
    ui.status:SetPoint("LEFT", c, "TOPLEFT", 0, -LW.LINE_H / 2)
    ui.resume = Style.Button(c, L["Resume"], function()
        if feed then LogTable.Resume(feed) end
        dirty = true
        LW.Paint()
    end)
    ui.resume:SetSize(56, LW.LINE_H - 2)
    ui.resume:SetPoint("RIGHT", c, "TOPRIGHT", 0, -LW.LINE_H / 2)
    ui.resume.tipBody = true
    ui.resume.tip = { L["Resume"], L["Follow the newest line again."] }
    ui.resume:Hide()
    ui.chips = LogTable.NewChips(c, function(key) LW.ToggleChip(key) end)
    ui.table = LogTable.New(c, { info = true, onSort = onSort, onScroll = onScroll })
end

local onHide, layout, redraw, trackSize, resized

local function ensureWindow()
    if ui then return ui end
    local f = CreateFrame("Frame", LW.FRAME_NAME, UIParent, "BackdropTemplate")
    ui = { frame = f }
    f:Hide()
    f:SetFrameStrata(NS.Constants.LAYERS.STRATA.HUD)
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    buildHeader(f)
    ui.foot = NS.MakeFooter(f)
    ui.footLeft, ui.footRight = ui.foot.left, ui.foot.right
    buildBody(f)
    NS.ApplySkin(f)
    f:SetScript("OnHide", function() onHide() end)
    -- Escape closes it with the standard close stack (standalone-windows).
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, LW.FRAME_NAME) end
    NS.Sizing.MakeResizable(f, {
        minWidth = LW.MIN_WIDTH, minHeight = LW.MinHeight(),
        canResize = function() return not locked end,
        size = function(w, h) trackSize(w, h) end, layout = function() layout() end,
        redraw = function() redraw() end, done = function(w, h) resized(w, h) end,
    })
    return ui
end

-- The window's configured look, once per Appearance stamp: the title bar, the footer, the content's
-- insets, the HUD's background, border and strata (HudAppearance.ApplyWindow).
local function applyWindow()
    local A = NS.HudAppearance
    if ui.stamp == A.stamp then return end
    ui.stamp = A.stamp
    local f = ui.frame
    local bar, foot = A.On("hud.window.titleBar"), A.On("hud.window.footer")
    for _, part in ipairs({ ui.close, ui.settings, ui.dock, ui.drag, Style.Band(f) }) do
        if part then part:SetShown(bar) end
    end
    f.title:SetShown(bar and A.On("hud.window.title"))
    ui.foot:SetShown(foot)
    ui.content:ClearAllPoints()
    ui.content:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -contentTop())
    ui.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, contentBottom())
    A.ApplyWindow(f)
end

-- Its own place and scale (it stands beside nothing: owner feedback item 11).
local function applyPlacement()
    local f = ui.frame
    local p = (store() or {}).position or {}
    anchor = { p.point or "CENTER", UIParent, p.relPoint or p.point or "CENTER",
               Secrets.PlainNumber(p.x) or 0, Secrets.PlainNumber(p.y) or 0 }
    f:SetScale(clamp(Secrets.PlainNumber(setting("log.window.scale")) or 1, 0.5, 2))
    f:ClearAllPoints()
    f:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
    f:SetAlpha(clamp(Secrets.PlainNumber(setting("log.window.alpha")) or 1, 0.1, 1))
end

-- The grip shown while unlocked, and its bounds: with `fill` off, the width alone (the height is the
-- rows'); else both, from the least size.
local function applyGrip()
    local f = ui.frame
    if f.resizeGrip then f.resizeGrip:SetShown(not locked) end
    if ui.footGrip ~= not locked then
        ui.footGrip = not locked
        if ui.foot.SetGrip then ui.foot:SetGrip(not locked) end
    end
    if type(f.SetResizeBounds) ~= "function" then return end
    if not fill() then
        local h = LW.WindowHeight()
        f:SetResizeBounds(LW.MIN_WIDTH, h, LW.MAX_WIDTH, h)
    else
        f:SetResizeBounds(LW.MIN_WIDTH, LW.MinHeight(), LW.MAX_WIDTH, LW.MAX_HEIGHT)
    end
end

-- The cheap layout (every size tick while the grip is held, and every draw): the size, the table's
-- columns and its visible rows, all from the configured or tracked size. Nothing is painted here.
function layout()
    local w, h = LW.Width(), LW.WindowHeight()
    if not sizing() then ui.frame:SetSize(w, h) end
    LogTable.LayChips(ui.chips, ui.content, 0, -LW.LINE_H, w - 2 * PAD)
    local top = -(LW.LINE_H + chipsRoom())
    ui.table.frame:ClearAllPoints()
    ui.table.frame:SetPoint("TOPLEFT", ui.content, "TOPLEFT", 0, top)
    ui.table.frame:SetPoint("TOPRIGHT", ui.content, "TOPRIGHT", 0, top)
    ui.table:Layout(w - 2 * PAD, LW.Rows(h), setting("log.view.columns"))
end

-- The full draw: the layout, then a repaint.
function redraw()
    if not ui then return end
    layout()
    dirty = true
    LW.Paint()
end

-- Every size change: the size, in range, that a drag lays out from (plain numbers only).
function trackSize(w, h)
    w, h = Secrets.PlainNumber(w), Secrets.PlainNumber(h)
    if w then ui.dragW = clamp(w, LW.MIN_WIDTH, LW.MAX_WIDTH) end
    if h then ui.dragH = clamp(h, LW.MinHeight(), LW.MAX_HEIGHT) end
end

-- The grip's release (or a hide while it was held): the width stored, and the height unless it is
-- the rows'; the window keeps its top left where the drag left it; then the redraw.
function resized(w, h)
    w = Secrets.PlainNumber(w) or ui.dragW
    h = Secrets.PlainNumber(h) or ui.dragH
    ui.dragW, ui.dragH = nil, nil
    local s = store()
    keepWhereItStands()
    if s and w then s.width = clamp(math.floor(w + 0.5), LW.MIN_WIDTH, LW.MAX_WIDTH) end
    if s and h and fill() then s.height = clamp(math.floor(h + 0.5), 0, LW.MAX_HEIGHT) end
    if LW.IsShown() then LW.Refresh() end
end

-- ── the paint ───────────────────────────────────────────────────────────────────────────────────

-- The window's chips from `log.show` again (built, opened, a fight's start, a What to show write).
local function seed()
    LogTable.ReadShow(show)
    seeded = true
    LogTable.Refilter(feed)
    if ui then LogTable.PaintChips(ui.chips, show) end
end

--- Turn chip `key` on or off in this window alone (never in the settings), and repaint.
function LW.ToggleChip(key)
    if not seeded then seed() end
    LogTable.ToggleChip(show, key)
    LogTable.Refilter(feed)
    if ui then LogTable.PaintChips(ui.chips, show) end
    dirty = true
    LW.Paint()
end

--- The window's own What to show (the suites): the table its chips turn.
function LW.__show() return show end

--- Repaint now when anything moved (the repaint tick, the controls, a draw).
function LW.Paint()
    if not windowShown() then return end
    if not feed then feed = LogTable.NewFeed() end
    if not seeded then seed() end
    local moved = LogTable.Advance(feed, GetTime(), setting("log.view.throttle"), setting("log.view.throttleMs"), accept)
    if not (moved or dirty) then return end
    dirty = false
    local startT, from = CL.Window()
    LogTable.LiveContext(ctx, startT)
    local n = ui.table:DrawFeed(feed, from, accept, ctx, LogTable.SortOf(), L["No events yet."])
    local paused = LogTable.Paused(feed)
    ui.resume:SetShown(paused)
    ui.status:SetText(paused and L["Paused"] or L["Following the newest line"])
    ui.footLeft:SetText(n > 0 and L["%d shown"]:format(n) or "")
end

local function onScreen()
    return windowShown() and ui.frame:IsVisible() and not isDown()
end

local function tick()
    if not onScreen() then return LW.Sync() end
    LW.Paint()
end

--- The repaint timer on while the window is on screen, else off.
function LW.Sync()
    local want = onScreen()
    local addon = NS.addon
    if timer and not want then
        if addon and addon.CancelTimer then addon:CancelTimer(timer) end
        timer = nil
    elseif want and not timer and addon and addon.ScheduleRepeatingTimer then
        timer = addon:ScheduleRepeatingTimer(tick, NS.Constants.LOG.REPAINT)
    end
end

--- Whether the repaint timer runs (the suites).
function LW.Ticking() return timer ~= nil end

-- ── showing and hiding ──────────────────────────────────────────────────────────────────────────

local function hideWindow()
    if windowShown() then
        hiding = true
        ui.frame:Hide()
        hiding = false
    end
end

-- The frame went away by Escape (or the close mark): the player closed the log. A frame still shown in
-- its own right was hidden with its parent (the interface hidden), which is not.
function onHide()
    if hiding or (ui and ui.frame:IsShown()) then return end
    LW.Sync()
    if LW.Wanted() and not isDown() then write("log.drawer.shown", false) end
end

--- Re-decide and redraw. The one place the frame follows the decision. Never calls the HUD's Refresh.
function LW.Refresh()
    locked = setting("general.locked") == true or setting("log.window.locked") == true
    if not LW.IsShown() then
        hideWindow()
    else
        ensureWindow()
        applyWindow()
        applyPlacement()
        layout()
        applyGrip()
        if not windowShown() then ui.frame:Show() end
        dirty = true
        LW.Paint()
    end
    LW.Sync()
end

--- HudLog.Sync, at the end of each of the HUD's Refreshes and draws (the login, a stand-up): the frame
--- re-decides when it disagrees with the decision. A comparison otherwise; it never follows the HUD.
function LW.Settle()
    if LW.IsShown() ~= windowShown() then return LW.Refresh() end
end

--- The place applied last: { point, relativeTo, relPoint, x, y } (the suites read it), or nil.
function LW.Anchor() return anchor end

-- ── the acts ────────────────────────────────────────────────────────────────────────────────────

function Act.close()
    write("log.drawer.shown", false)
    LW.Refresh()
end

function Act.dock() NS.HudLog.SetHome("docked") end

--- The gear: the settings panel on its Combat Log page (settings/Log.lua).
function Act.settings()
    local H = NS.Helpers
    if H and type(H.OpenOptionsPanel) == "function" then return H.OpenOptionsPanel("log") end
    return NS.OpenSettings()
end

--- The stand-down: the timer goes (CancelAllTimers took it), the feed starts over, the frame hides.
function LW.Suspend()
    timer, feed, dirty, seeded = nil, nil, true, false
    hideWindow()
end

--- The stand-up: re-decide from the current state.
function LW.Resume() LW.Refresh() end

--- What the window is doing, for the diagnostics report.
function LW.Diagnose()
    return { shown = LW.IsShown(), width = LW.Width(), height = LW.WindowHeight(), ticking = timer ~= nil }
end

--- The built window (the suites; nil until first shown).
function LW.__ui() return ui end

--- The live feed (the suites; nil until first painted).
function LW.__feed() return feed end

-- ── wiring ──────────────────────────────────────────────────────────────────────────────────────

local bus = NS.NewBusTarget()
if bus then
    bus:RegisterMessage(NS.MSG.FIGHT_STARTED, function()
        if feed then LogTable.Resume(feed) end
        dirty, seeded = true, false
    end)
    bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path)
        if type(path) ~= "string" then return end
        if LogTable.Reseeds(path) then seeded = false end
        if path:find("^log%.") or path:find("^hud%.") or path:find("^general%.") or path == "profile" then
            dirty = true
            if ui then ui.table.laid = nil end
            return LW.Refresh()
        end
    end)
end
