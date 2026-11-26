local _, NS = ...
-- modules/Hud_Log.lua — the Combat Sequence docked in the DPS HUD (CombatTrail #11, plan item CL-11b; the
-- spec's addendum, home A): a drawer under the spell rows, at the HUD's width, in its skin, over the
-- shared table (modules/LogTable.lua and LogTable_View.lua) and the capture's ring (modules/CombatLog.lua).
--
-- PART OF THE HUD. The drawer is a child of the HUD's window: it hides and fades with it and never
-- shows while the HUD is hidden. The HUD and the drawer are one window of one static height (owner
-- feedback item 12): the HUD reserves the drawer's sections under the content (Hud.lua's
-- contentBottom adds HudLog.Height(), worked out from the configuration alone), so the height moves
-- only when the log opens or closes, a rows setting changes or the HUD's grip is dragged (whose extra
-- height goes to the drawer's rows while it is open: HudLog.SetDragRows while held, `sequence.drawer.rows`
-- on release), and the Race window docked beside it takes the whole height (Hud.Height,
-- RaceWindow.OnHudResized).
--
-- A SECTION LIKE SPELL BREAKDOWN (owner feedback items 17 and 18, 2026-11-25): HudLog.GAP (the HUD's
-- HEAD_GAP) of clear space, then its heading on the HUD's section line (Hud_States' SECTION_H): the
-- gold "Combat Sequence" in FONT.SECTION at the left, the dim count ("8 shown") right-aligned on the
-- heading's bottom edge, then its two marks (the filter eye and the detach arrow) at the right edge,
-- tinted and lit as the window's title-bar marks are (Style.NewStrip, Style.AddToStrip: the skin's
-- `icon.tint` at rest, `text.link` under the pointer, the same 18 px slot and 12 px art). No separator
-- or seam above it, and no fold: the title bar's Log mark alone opens and closes the log (item 14).
--
-- ITS STATE, each saved in the profile:
--   sequence.drawer.shown      the title bar's log control (the list mark) and `/ct sequence` toggle it (on by
--                         default, owner feedback item 1); with
--                         sequence.drawer.autoOpen on (the default) each fight's start opens it. Off while
--                         `sequence.enabled` is off, whatever it says, and the control is then hidden.
--   sequence.drawer.chips      the header's filter mark (the eye) shows or hides the drawer's chips, a row
--                         under its heading (LogTable.NewChips: Casts, Pet, Buffs, Debuffs), the
--                         HUD growing by it; hidden by default, an absent value hidden too (owner
--                         feedback round 4, R4-CT-04, reversing item 9's default). The chips themselves
--                         are the drawer's own, seeded from `sequence.show.*` (LogTable.Reseeds) and turned
--                         for this session alone.
--   sequence.drawer.rows       the rows shown, 3 to 20 (default 10, owner feedback item 16); the rows past
--                         them scroll with the wheel, the Spell breakdown's indicator in the gutter
--                         (item 6, LogTable's View:SetScroll).
--   sequence.view.sort         newest first (default) or oldest first: the Time header's click flips it.
--   sequence.home              "docked" (the default) or "detached": the header's detach control (the export
--                         mark) moves the log into its own window (modules/LogWindow.lua, CL-11b2), whose
--                         dock control sends it back. `sequence.drawer.shown` is the log's one open, in either
--                         home: detached, the HUD reserves nothing and this drawer stays hidden.
-- `sequence.drawer.shown`, `sequence.drawer.chips`, `sequence.view.sort` and `sequence.home` are written by the controls
-- through NS.SetByPath, onto their Combat Sequence page rows (settings/Log.lua, CL-11c2). Every write's
-- SETTINGS_CHANGED on a `sequence.` path redraws a shown HUD (Hud.Refresh), which re-insets its content and
-- re-places the drawer.
--
-- THE PAINT. Nothing here runs on a client event. While the drawer is shown on a shown HUD, one
-- repeating AceTimer at NS.Constants.LOG.REPAINT (0.1 s) moves the feed (LogTable.Advance, by the
-- throttle) and repaints only when the feed, the pause or a setting moved; it stops the moment the
-- drawer or the HUD is hidden (HudLog.Sync, which the HUD's Refresh calls on both paths). The capture
-- never waits on it. The lines are the newest fight's (CombatLog.Window: from its pre-pull floor on,
-- timed from its start), shown until the next fight starts: each pull clears the view (item 5).

local HudLog = {}
NS.HudLog = HudLog

local L = NS.L
local Style = NS.Style
local Secrets = NS.Secrets
local LogTable = NS.LogTable
local CL = NS.CombatLog

local States = NS.HudStates
HudLog.HEAD_H = States.SECTION_H   -- the heading's line: the HUD's sections' (Damage profile, Spell breakdown)
HudLog.GAP = States.HEAD_GAP       -- the clear space over the heading: the HUD's sections' HEAD_GAP
HudLog.MIN_ROWS, HudLog.MAX_ROWS = 3, 20

local d                   -- the built drawer
local dragRows            -- the rows the HUD's grip holds while it is dragged (HudLog.SetDragRows)
local feed                -- the live feed (LogTable.NewFeed)
local show = {}           -- the drawer's own What to show, seeded from `sequence.show`
local seeded = false
local timer
local dirty = true
local ctx = {}

local function setting(path)
    return NS.GetSetting and NS.GetSetting(path)
end

local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

--- Whether the Combat Sequence is on at all (`sequence.enabled`).
function HudLog.Enabled()
    return setting("sequence.enabled") ~= false
end

--- Where the log lives: "docked" in the HUD (the default) or "detached" in its own window.
--- @return string
function HudLog.Home()
    return setting("sequence.home") == "detached" and "detached" or "docked"
end

--- Whether the log is wanted open in either home (the Combat Sequence on, `sequence.drawer.shown`).
function HudLog.Open()
    return HudLog.Enabled() and setting("sequence.drawer.shown") == true
end

--- Whether the drawer is wanted open: the log open and docked.
function HudLog.Wanted()
    return HudLog.Open() and HudLog.Home() == "docked"
end

--- The rows `sequence.drawer.rows` asks for, whole and in range.
function HudLog.RowsSetting()
    local v = Secrets.PlainNumber(setting("sequence.drawer.rows")) or HudLog.MIN_ROWS
    return clamp(math.floor(v), HudLog.MIN_ROWS, HudLog.MAX_ROWS)
end

--- The rows shown: the HUD grip's while it is dragged, else the rows setting's.
function HudLog.Rows()
    return dragRows or HudLog.RowsSetting()
end

--- The HUD's grip, dragged with the drawer open, hands the rows its height holds (nil: the drag ended).
--- @param n number|nil
function HudLog.SetDragRows(n)
    dragRows = n and clamp(math.floor(n), HudLog.MIN_ROWS, HudLog.MAX_ROWS) or nil
end

--- The whole rows `h` pixels of table rows hold, in range.
--- @param h number
--- @return number
function HudLog.RowsFit(h)
    return clamp(math.floor((tonumber(h) or 0) / LogTable.RowH()), HudLog.MIN_ROWS, HudLog.MAX_ROWS)
end

-- The drawer's width (the HUD's, less its insets): its chips wrap at it.
local function drawerWidth()
    local H = NS.Hud
    return H and H.LogWidth and Secrets.PlainNumber(H.LogWidth()) or 366
end

--- Whether the chips row shows (`sequence.drawer.chips`, the header's filter mark): only while it is
--- on, so a new profile and an absent value both hide it (R4-CT-04).
function HudLog.ChipsShown()
    return setting("sequence.drawer.chips") == true
end

-- The chips row's height, its gap under it included; 0 while it is not shown.
local function chipsHeight()
    if not HudLog.ChipsShown() then return 0 end
    return LogTable.ChipsHeight(drawerWidth()) + LogTable.CHIP_GAP
end

--- The height the HUD reserves for a drawer of `rows` rows, the clear space over its heading, the
--- heading, the chips row (when shown), the column header and the rows; 0 while it is not wanted.
--- Worked out from the configuration alone, never measured.
--- @param rows number
--- @return number
function HudLog.HeightFor(rows)
    if not HudLog.Wanted() then return 0 end
    return HudLog.GAP + HudLog.HEAD_H + chipsHeight() + LogTable.Height(rows)
end

--- The height the HUD reserves for the drawer at HudLog.Rows().
--- @return number
function HudLog.Height() return HudLog.HeightFor(HudLog.Rows()) end

-- ── the drawer ──────────────────────────────────────────────────────────────────────────────────

local function write(path, value)
    if NS.SetByPath then NS.SetByPath(path, value) end
end

local function onSort()
    write("sequence.view.sort", LogTable.SortOf() == "newest" and "oldest" or "newest")
end

local function onScroll(away)
    if not feed then return end
    LogTable.Scroll(feed, away)
    dirty = true
    HudLog.Paint()
end

local function build(parent)
    local f = CreateFrame("Frame", nil, parent)
    d = { frame = f, hud = parent, marks = Style.NewStrip() }
    d.title = Style.Text(f, Style.FONT.SECTION)
    d.title:SetText(L["Combat Sequence"])
    d.resume = Style.Button(f, L["Resume"], function()
        if feed then LogTable.Resume(feed) end
        dirty = true
        HudLog.Paint()
    end)
    d.resume:SetSize(56, HudLog.HEAD_H - 2)
    d.resume.tipBody = true
    d.resume.tip = { L["Resume"], L["Follow the newest line again."] }
    d.resume:Hide()
    d.filter = Style.AddToStrip(d.marks, Style.ControlButton(f, "eye", "F",
        L["Show or hide the Combat Sequence's filter chips"], function() HudLog.ToggleChipsRow() end, "body"))
    d.detach = Style.AddToStrip(d.marks, Style.ControlButton(f, "export", ">",
        L["Detach the Combat Sequence into its own window"], function() HudLog.SetHome("detached") end, "body"))
    d.count = Style.Text(f, Style.FONT.CAPTION, nil, "RIGHT")
    d.chips = LogTable.NewChips(f, function(key) HudLog.ToggleChip(key) end)
    d.table = LogTable.New(f, { onSort = onSort, onScroll = onScroll })
    return d
end

-- The heading laid as Spell breakdown's: the title at the left, the detach mark at the right edge, the
-- filter mark left of it, and the count (or Resume) left of the marks on the heading's bottom edge.
local MARK_STEP = Style.CONTROL - 2   -- one mark's pitch, the art 3 px past the edge as the title bar's
local function layHeader(w)
    local f = d.frame
    d.title:ClearAllPoints()
    d.title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    local y = -(Style.FONT_SIZE[Style.FONT.SECTION] or 16) / 2
    d.detach:ClearAllPoints()
    d.detach:SetPoint("RIGHT", f, "TOPRIGHT", 3, y)
    d.filter:ClearAllPoints()
    d.filter:SetPoint("RIGHT", f, "TOPRIGHT", 3 - MARK_STEP, y)
    local x = -2 * MARK_STEP
    d.resume:ClearAllPoints()
    d.resume:SetPoint("RIGHT", f, "TOPRIGHT", x, y)
    d.count:ClearAllPoints()
    d.count:SetPoint("BOTTOMRIGHT", d.title, "BOTTOMLEFT", w + x, 0)
    d.count:SetWidth(math.max(1, w / 2))
end

local function layTables(w)
    local top = -HudLog.HEAD_H
    local chips = HudLog.ChipsShown()
    LogTable.ShowChips(d.chips, chips)
    if chips then LogTable.LayChips(d.chips, d.frame, 0, top, w) end
    local tableTop = top - chipsHeight()
    d.table.frame:ClearAllPoints()
    d.table.frame:SetPoint("TOPLEFT", d.frame, "TOPLEFT", 0, tableTop)
    d.table.frame:SetPoint("TOPRIGHT", d.frame, "TOPRIGHT", 0, tableTop)
    d.table:Layout(w, HudLog.Rows(), setting("sequence.view.columns"))
end

--- Place the drawer on the HUD's window `hud` (the HUD's draw calls it): `pad` in from each side, its
--- bottom `bottom` up from the window's (the footer's inset; the content's is that plus HudLog.Height()), `w` wide,
--- shown while wanted; its top is HudLog.GAP under the content. Builds it on its first want.
function HudLog.Place(hud, pad, bottom, w)
    if not HudLog.Wanted() then
        if d then d.frame:Hide() end
        return HudLog.Sync()
    end
    if not d then build(hud) end
    local f = d.frame
    -- The HUD draws at its beat: a place that moved nothing is no relayout and no repaint. The last
    -- place is kept as plain fields on `d` and compared field by field, so a beat allocates nothing.
    local h, stamp = HudLog.Height(), d.stamp or 0
    if f:IsShown() and d.pPad == pad and d.pBottom == bottom and d.pW == w and d.pH == h and d.pStamp == stamp then
        return HudLog.Sync()
    end
    d.pPad, d.pBottom, d.pW, d.pH, d.pStamp = pad, bottom, w, h, stamp
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

local function accept(e)
    return LogTable.Shows(e, show)
end

-- The drawer's chips from `sequence.show` again (built, opened, a fight's start, a What to show write).
local function seed()
    LogTable.ReadShow(show)
    seeded = true
    LogTable.Refilter(feed)
    if d then LogTable.PaintChips(d.chips, show) end
end

-- The paused view's Resume and the heading's count.
local function paintHeader(n)
    local paused = feed ~= nil and LogTable.Paused(feed)
    d.resume:SetShown(paused)
    d.count:SetShown(not paused)
    d.count:SetText(n > 0 and L["%d shown"]:format(n) or "")
end

--- Repaint the drawer now when anything moved (the repaint tick and the drawer's own controls).
function HudLog.Paint()
    if not (d and d.frame:IsShown()) then return end
    if not feed then feed = LogTable.NewFeed() end
    if not seeded then seed() end
    local moved = LogTable.Advance(feed, GetTime(), setting("sequence.view.throttle"), setting("sequence.view.throttleMs"), accept)
    if not (moved or dirty) then return end
    dirty = false
    local startT, from = CL.Window()
    LogTable.LiveContext(ctx, startT)
    paintHeader(d.table:DrawFeed(feed, from, accept, ctx, LogTable.SortOf(), L["No events yet."]))
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

--- The repaint timer on while the drawer shows on a shown HUD, else off. The HUD's every Refresh
--- calls this on both its paths, so it also lets the detached window settle (LogWindow.Settle: the
--- login and a stand-up bring it up; it never follows the HUD, owner feedback item 11).
function HudLog.Sync()
    local want = onScreen()
    local addon = NS.addon
    if timer and not want then
        if addon and addon.CancelTimer then addon:CancelTimer(timer) end
        timer = nil
    elseif want and not timer and addon and addon.ScheduleRepeatingTimer then
        timer = addon:ScheduleRepeatingTimer(tick, NS.Constants.LOG.REPAINT)
    end
    local W = NS.LogWindow
    if W and W.Settle then W.Settle() end
end

--- Whether the repaint timer runs (the suites).
function HudLog.Ticking() return timer ~= nil end

-- ── the ways in ─────────────────────────────────────────────────────────────────────────────────

--- Open or close the log in its home (`on` nil: toggle). Opening it docked opens the HUD too, as the
--- player's open; the detached window is a standalone window and opens alone.
function HudLog.SetShown(on)
    if on == nil then on = not HudLog.Open() end
    if on and not HudLog.Enabled() then return NS.Print(L["The Combat Sequence is off (sequence.enabled)."]) end
    write("sequence.drawer.shown", on == true)
    if on and HudLog.Home() == "docked" and NS.Hud and not NS.Hud.IsShown() then NS.Hud.Show() end
end

--- Show or hide the drawer's chips row (the header's filter mark, `sequence.drawer.chips`): its write
--- redraws the HUD to its new height.
function HudLog.ToggleChipsRow()
    write("sequence.drawer.chips", not HudLog.ChipsShown())
end

--- Turn chip `key` on or off in the drawer alone (never in the settings), and repaint.
function HudLog.ToggleChip(key)
    if not seeded then seed() end
    LogTable.ToggleChip(show, key)
    LogTable.Refilter(feed)
    if d then LogTable.PaintChips(d.chips, show) end
    dirty = true
    HudLog.Paint()
end

--- The drawer's own What to show (the suites): the table its chips turn.
function HudLog.__show() return show end

--- Move the log to `home`, "docked" or "detached" (the drawer's detach mark, the window's dock mark,
--- `/ct sequence detach|dock`). The log stays open across the move.
function HudLog.SetHome(home)
    home = home == "detached" and "detached" or "docked"
    if home == HudLog.Home() then return end
    write("sequence.home", home)
end

local VERBS = {
    [""] = function() HudLog.SetShown() end,
    toggle = function() HudLog.SetShown() end,
    show = function() HudLog.SetShown(true) end,
    hide = function() HudLog.SetShown(false) end,
    detach = function() HudLog.SetHome("detached") end,
    dock = function() HudLog.SetHome("docked") end,
}

--- `/ct sequence [show|hide|toggle|detach|dock]` (no pin: the detached window is standalone, item 11).
function HudLog.OnVerb(rest)
    local word = tostring(rest or ""):match("^%s*(%S*)"):lower()
    local fn = VERBS[word]
    if fn then return fn() end
    NS.Print(L["Usage: /ct sequence show, hide, toggle, detach or dock"])
end

--- The title bar's log control: shown while the Combat Sequence is on (the HUD lays its strip by it).
function HudLog.ControlShown()
    return HudLog.Enabled()
end

--- The built drawer (the suites; nil until first shown).
function HudLog.__ui() return d end

--- The live feed (the suites; nil until first painted).
function HudLog.__feed() return feed end

--- The stand-down: the timer goes (CancelAllTimers took it), the feed starts over.
function HudLog.Suspend()
    timer, feed, dirty, seeded = nil, nil, true, false
    if d then d.frame:Hide() end
end

-- ── wiring ──────────────────────────────────────────────────────────────────────────────────────

-- The sample seam swapped what the ring reads (test mode, the sim: CombatLog.UseSample and EndSample):
-- the feed starts over on the ring it reads now, as at a fight's start.
CL.Watch("drawer", function()
    feed, dirty, seeded = nil, true, false
    HudLog.Paint()
end)

local bus = NS.NewBusTarget()
if bus then
    bus:RegisterMessage(NS.MSG.FIGHT_STARTED, function()
        -- A new fight: the feed follows again from its first line, and the drawer opens when asked.
        if feed then LogTable.Resume(feed) end
        dirty, seeded = true, false
        if HudLog.Enabled() and setting("sequence.drawer.autoOpen") ~= false and setting("sequence.drawer.shown") ~= true then
            write("sequence.drawer.shown", true)
        end
    end)
    bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path)
        if type(path) ~= "string" or not (path:find("^sequence%.") or path == "profile") then return end
        if LogTable.Reseeds(path) then seeded = false end
        if not path:find("^sequence%.") then return end
        dirty = true
        if d then d.stamp = (d.stamp or 0) + 1 end
        if NS.Hud and NS.Hud.IsShown and NS.Hud.IsShown() then NS.Hud.Refresh() end
    end)
end
