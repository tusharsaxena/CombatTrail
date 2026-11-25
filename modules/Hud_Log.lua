local _, NS = ...
-- modules/Hud_Log.lua — the Combat Log docked in the DPS HUD (CombatTrail #11, plan item CL-11b; the
-- spec's addendum, home A): a drawer under the spell rows, at the HUD's width, in its skin, over the
-- shared table (modules/LogTable.lua and LogTable_View.lua) and the capture's ring (modules/CombatLog.lua).
--
-- PART OF THE HUD. The drawer is a child of the HUD's window: it hides and fades with it and never
-- shows while the HUD is hidden. The HUD reserves its height under the content (Hud.lua's
-- contentBottom adds HudLog.Height()), so the window grows by it in either size mode and the Race
-- window docked beside it takes the whole height (Hud.Height, RaceWindow.OnHudResized). Its top is an
-- accent seam (`ct.log.seam`) across the window.
--
-- ITS STATE, each saved in the profile:
--   log.drawer.shown      the title bar's log control (the chat mark) and `/ct log` toggle it; with
--                         log.drawer.autoOpen on (the default) each fight's start opens it. Off while
--                         `log.enabled` is off, whatever it says, and the control is then hidden.
--   log.drawer.collapsed  the header's chevron folds it to one line, the newest event
--                         (log.drawer.strip on, the default) or the header alone, and unfolds it.
--   log.drawer.rows       the rows shown expanded, 3 to 20 (default 8).
--   log.view.sort         newest first (default) or oldest first: the Time header's click flips it.
-- `log.drawer.shown`, `log.drawer.collapsed` and `log.view.sort` are written by the drawer's own
-- controls through NS.SetByPath, as named non-setting state (settings/Schema.lua's write-through list)
-- until the Combat Log page (CL-11c) gives them their rows. Every write's SETTINGS_CHANGED on a `log.`
-- path redraws a shown HUD (Hud.Refresh), which re-insets its content and re-places the drawer.
--
-- THE PAINT. Nothing here runs on a client event. While the drawer is shown on a shown HUD, one
-- repeating AceTimer at NS.Constants.LOG.REPAINT (0.1 s) moves the feed (LogTable.Advance, by the
-- throttle) and repaints only when the feed, the pause or a setting moved; it stops the moment the
-- drawer or the HUD is hidden (HudLog.Sync, which the HUD's Refresh calls on both paths). The capture
-- never waits on it. The lines are the newest fight's (CombatLog.Window: from its pre-pull floor on,
-- timed from its start), shown until the next fight starts.

local HudLog = {}
NS.HudLog = HudLog

local L = NS.L
local Style = NS.Style
local Secrets = NS.Secrets
local LogTable = NS.LogTable
local CL = NS.CombatLog

HudLog.HEAD_H = 18        -- the drawer's own header line (its title, the chevron, Resume)
HudLog.GAP = 4            -- above the seam, and the content's gap to it is twice this
HudLog.MIN_ROWS, HudLog.MAX_ROWS = 3, 20
HudLog.SEAM = 1

local d                   -- the built drawer
local feed                -- the live feed (LogTable.NewFeed)
local stripFeed = { offset = 0, shown = 0 }
local timer
local dirty = true
local ctx = {}

local function setting(path)
    return NS.GetSetting and NS.GetSetting(path)
end

local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

--- Whether the Combat Log is on at all (`log.enabled`).
function HudLog.Enabled()
    return setting("log.enabled") ~= false
end

--- Whether the drawer is wanted open (the Combat Log on, `log.drawer.shown`).
function HudLog.Wanted()
    return HudLog.Enabled() and setting("log.drawer.shown") == true
end

--- Whether it is folded to its one line.
function HudLog.Collapsed()
    return setting("log.drawer.collapsed") == true
end

local function stripOn()
    return setting("log.drawer.strip") ~= false
end

--- The rows shown expanded, whole and in range.
function HudLog.Rows()
    local v = Secrets.PlainNumber(setting("log.drawer.rows")) or 8
    return clamp(math.floor(v), HudLog.MIN_ROWS, HudLog.MAX_ROWS)
end

-- The table's height under the header: expanded, its column header and its rows; folded, the one
-- strip row (or nothing).
local function tableHeight()
    if HudLog.Collapsed() then return stripOn() and LogTable.Height(1, true) or 0 end
    return LogTable.Height(HudLog.Rows())
end

--- The height the HUD reserves for the drawer, its gap above the seam included; 0 while it is not
--- wanted. Worked out from the configuration alone (never a measured size).
--- @return number
function HudLog.Height()
    if not HudLog.Wanted() then return 0 end
    return HudLog.GAP + HudLog.SEAM + HudLog.HEAD_H + tableHeight()
end

-- ── the drawer ──────────────────────────────────────────────────────────────────────────────────

local function write(path, value)
    if NS.SetByPath then NS.SetByPath(path, value) end
end

local function sortOf()
    local s = setting("log.view.sort")
    return LogTable.SORTS[s] and s or "newest"
end

local function onSort()
    write("log.view.sort", sortOf() == "newest" and "oldest" or "newest")
end

local function onScroll(away)
    if not feed then return end
    LogTable.Scroll(feed, away)
    dirty = true
    HudLog.Paint()
end

local function build(parent)
    local f = CreateFrame("Frame", nil, parent)
    d = { frame = f, hud = parent }
    d.seam = f:CreateTexture(nil, "ARTWORK")
    d.seam:SetTexture(Style.WHITE)
    Style.Vertex(d.seam, "ct.log.seam")
    d.title = Style.Text(f, Style.FONT.HEADER, "list.header.text", "LEFT")
    d.title:SetText(L["Combat Log"])
    d.fold = Style.ControlButton(f, "chevron-up", "^", L["Fold the Combat Log to one line"], function()
        write("log.drawer.collapsed", not HudLog.Collapsed())
    end, "body")
    d.resume = Style.Button(f, L["Resume"], function()
        if feed then LogTable.Resume(feed) end
        dirty = true
        HudLog.Paint()
    end)
    d.resume:SetSize(56, HudLog.HEAD_H - 2)
    d.resume.tipBody = true
    d.resume.tip = { L["Resume"], L["Follow the newest line again."] }
    d.resume:Hide()
    d.count = Style.Text(f, Style.FONT.CAPTION, nil, "RIGHT")
    d.table = LogTable.New(f, { onSort = onSort, onScroll = onScroll })
    d.strip = LogTable.New(f, { noHeader = true })
    return d
end

-- The header's controls laid: the chevron left of the title, Resume and the count on the right.
local function layHeader(w)
    local f = d.frame
    d.seam:ClearAllPoints()
    d.seam:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    d.seam:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    d.seam:SetHeight(HudLog.SEAM)
    local y = -(HudLog.SEAM + HudLog.HEAD_H / 2)
    d.fold:ClearAllPoints()
    d.fold:SetPoint("LEFT", f, "TOPLEFT", -3, y)
    d.title:ClearAllPoints()
    d.title:SetPoint("LEFT", f, "TOPLEFT", Style.CONTROL - 2, y)
    d.resume:ClearAllPoints()
    d.resume:SetPoint("RIGHT", f, "TOPRIGHT", 0, y)
    d.count:ClearAllPoints()
    d.count:SetPoint("RIGHT", f, "TOPRIGHT", 0, y)
    d.count:SetWidth(math.max(1, w / 2))
end

local function layTables(w)
    local top = -(HudLog.SEAM + HudLog.HEAD_H)
    local cols = setting("log.view.columns")
    local collapsed = HudLog.Collapsed()
    d.table.frame:ClearAllPoints()
    d.table.frame:SetPoint("TOPLEFT", d.frame, "TOPLEFT", 0, top)
    d.table.frame:SetPoint("TOPRIGHT", d.frame, "TOPRIGHT", 0, top)
    d.table:Layout(w, HudLog.Rows(), cols)
    d.table.frame:SetShown(not collapsed)
    d.strip.frame:ClearAllPoints()
    d.strip.frame:SetPoint("TOPLEFT", d.frame, "TOPLEFT", 0, top)
    d.strip.frame:SetPoint("TOPRIGHT", d.frame, "TOPRIGHT", 0, top)
    d.strip:Layout(w, 1, cols)
    d.strip.frame:SetShown(collapsed and stripOn())
    Style.SetControlIcon(d.fold, collapsed and "chevron-down" or "chevron-up", collapsed and "v" or "^")
    Style.SetControlTip(d.fold, collapsed and L["Unfold the Combat Log"] or L["Fold the Combat Log to one line"])
end

--- Place the drawer on the HUD's window `hud` (the HUD's draw calls it): `pad` in from each side, its
--- bottom `bottom` up from the window's, `w` wide, shown while wanted. Builds it on its first want.
function HudLog.Place(hud, pad, bottom, w)
    if not HudLog.Wanted() then
        if d then d.frame:Hide() end
        return HudLog.Sync()
    end
    if not d then build(hud) end
    local f = d.frame
    -- The HUD draws at its beat: a place that moved nothing is no relayout and no repaint.
    local key = table.concat({ pad, bottom, w, HudLog.Height(), tostring(HudLog.Collapsed()), tostring(stripOn()),
                               d.stamp or 0 }, ":")
    if d.placed == key and f:IsShown() then return HudLog.Sync() end
    d.placed = key
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", hud, "BOTTOMLEFT", pad, bottom)
    f:SetPoint("BOTTOMRIGHT", hud, "BOTTOMRIGHT", -pad, bottom)
    f:SetHeight(HudLog.Height() - HudLog.GAP)
    layHeader(w)
    layTables(w)
    f:Show()
    dirty = true
    HudLog.Sync()
    HudLog.Paint()
end

-- ── the paint ───────────────────────────────────────────────────────────────────────────────────

local show = {}
local function accept(e)
    return LogTable.Shows(e, show)
end

local function readShow()
    local s = setting("log.show")
    for k in pairs(show) do show[k] = nil end
    if type(s) == "table" then for k, v in pairs(s) do show[k] = v end end
end

local function unitName(unit)
    if type(UnitExists) == "function" and not Secrets.PlainTruth(UnitExists(unit)) then return nil end
    local ok, name = pcall(UnitName, unit)
    return ok and Secrets.PlainString(name) or nil
end

-- The context the cells read: the window's start, the time format, the names and the color switches.
local function fillContext(startT)
    ctx.startT = startT
    ctx.timeFormat = setting("log.view.timeFormat")
    ctx.startClock = nil
    if startT and type(time) == "function" then ctx.startClock = time() - (GetTime() - startT) end
    ctx.targetName, ctx.petName = unitName("target"), unitName("pet")
    local ok, hostile = pcall(UnitCanAttack, "player", "target")
    ctx.targetFriendly = type(UnitCanAttack) == "function" and ok and Secrets.PlainEquals(hostile, false) or false
    ctx.schoolColors = setting("log.view.schoolColors") ~= false
    ctx.washes = setting("log.view.washes") ~= false
end

-- The paused view's Resume and the header's count.
local function paintHeader(n, collapsed)
    local paused = feed ~= nil and LogTable.Paused(feed) and not collapsed
    d.resume:SetShown(paused)
    d.count:SetShown(not paused and not collapsed)
    d.count:SetText(n > 0 and L["%d shown"]:format(n) or "")
end

local function drawExpanded(from)
    local rows = HudLog.Rows()
    local n = LogTable.Collect(feed, rows, from, accept, d.table.seqs)
    -- Scrolled past the oldest: back up to a full page (still paused).
    if n < rows and feed.offset > 0 then
        feed.offset = math.max(0, feed.offset - (rows - n))
        n = LogTable.Collect(feed, rows, from, accept, d.table.seqs)
    end
    d.table:SetSort(sortOf())
    d.table:Draw(d.table.seqs, n, CL.Line, ctx, L["No events yet."])
    return n
end

local function drawStrip(from)
    stripFeed.shown, stripFeed.offset, stripFeed.anchor = feed.shown, 0, nil
    local n = LogTable.Collect(stripFeed, 1, from, accept, d.strip.seqs)
    d.strip:SetSort("newest")
    d.strip:Draw(d.strip.seqs, n, CL.Line, ctx, L["No events yet."])
    return n
end

--- Repaint the drawer now when anything moved (the repaint tick and the drawer's own controls).
function HudLog.Paint()
    if not (d and d.frame:IsShown()) then return end
    if not feed then feed = LogTable.NewFeed() end
    readShow()
    local moved = LogTable.Advance(feed, GetTime(), setting("log.view.throttle"), setting("log.view.throttleMs"), accept)
    if not (moved or dirty) then return end
    dirty = false
    local startT, from = CL.Window()
    fillContext(startT)
    local collapsed = HudLog.Collapsed()
    local n = 0
    if from then n = collapsed and drawStrip(from) or drawExpanded(from)
    else
        d.table:SetSort(sortOf())
        d.table:Draw(d.table.seqs, 0, CL.Line, ctx, L["No events yet."])
        d.strip:Draw(d.strip.seqs, 0, CL.Line, ctx, L["No events yet."])
    end
    paintHeader(n, collapsed)
end

-- Whether the drawer is on screen: shown itself, on the HUD's window while that is shown.
local function onScreen()
    return d ~= nil and d.frame:IsShown() and d.hud:IsShown() and d.frame:IsVisible()
        and not (NS.IsStoodDown and NS.IsStoodDown())
end

local function tick()
    if not onScreen() then return HudLog.Sync() end
    HudLog.Paint()
end

--- The repaint timer on while the drawer shows on a shown HUD, else off.
function HudLog.Sync()
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
function HudLog.Ticking() return timer ~= nil end

-- ── the ways in ─────────────────────────────────────────────────────────────────────────────────

--- Open or close the drawer (`on` nil: toggle). Opening it opens the HUD too, as the player's open.
function HudLog.SetShown(on)
    if on == nil then on = not HudLog.Wanted() end
    if on and not HudLog.Enabled() then return NS.Print(L["The Combat Log is off (log.enabled)."]) end
    write("log.drawer.shown", on == true)
    if on and NS.Hud and not NS.Hud.IsShown() then NS.Hud.Show() end
end

--- Fold or unfold it (`on` nil: toggle).
function HudLog.SetCollapsed(on)
    if on == nil then on = not HudLog.Collapsed() end
    write("log.drawer.collapsed", on == true)
end

local VERBS = {
    [""] = function() HudLog.SetShown() end,
    toggle = function() HudLog.SetShown() end,
    show = function() HudLog.SetShown(true) end,
    hide = function() HudLog.SetShown(false) end,
    fold = function() HudLog.SetCollapsed(true) end,
    unfold = function() HudLog.SetCollapsed(false) end,
}

--- `/ct log [show|hide|toggle|fold|unfold]`.
function HudLog.OnVerb(rest)
    local word = tostring(rest or ""):match("^%s*(%S*)"):lower()
    local fn = VERBS[word]
    if fn then return fn() end
    NS.Print(L["Usage: /ct log show, hide, toggle, fold or unfold"])
end

--- The title bar's log control: shown while the Combat Log is on (the HUD lays its strip by it).
function HudLog.ControlShown()
    return HudLog.Enabled()
end

--- The built drawer (the suites; nil until first shown).
function HudLog.__ui() return d end

--- The live feed (the suites; nil until first painted).
function HudLog.__feed() return feed end

--- The stand-down: the timer goes (CancelAllTimers took it), the feed starts over.
function HudLog.Suspend()
    timer, feed, dirty = nil, nil, true
    if d then d.frame:Hide() end
end

-- ── wiring ──────────────────────────────────────────────────────────────────────────────────────

local bus = NS.NewBusTarget()
if bus then
    bus:RegisterMessage(NS.MSG.FIGHT_STARTED, function()
        -- A new fight: the feed follows again from its first line, and the drawer opens when asked.
        if feed then LogTable.Resume(feed) end
        dirty = true
        if HudLog.Enabled() and setting("log.drawer.autoOpen") ~= false and setting("log.drawer.shown") ~= true then
            write("log.drawer.shown", true)
        end
    end)
    bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path)
        if type(path) ~= "string" or not path:find("^log%.") then return end
        dirty = true
        if d then d.stamp = (d.stamp or 0) + 1 end
        if NS.Hud and NS.Hud.IsShown and NS.Hud.IsShown() then NS.Hud.Refresh() end
    end)
end
