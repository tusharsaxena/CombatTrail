local _, NS = ...
-- modules/Results.lua — the Results window's shell (spec §7, mockup §5): the window, its title bar,
-- the fight list in its body (modules/Results_Fights.lua over modules/Results_Table.lua), where the
-- fight detail sits (modules/Results_Detail.lua), the footer, the row menu, and the window's public
-- surface (Show, Hide, Toggle, Open, ShowFight, ShowTab). Adapted from DPS Race @045f479
-- (modules/Results.lua). TWO TABS under the title band (Race mode plan Task D2): Fights, the fight
-- list with its detail, and Insights (modules/Results_Insights.lua), built on its first show. The tab
-- shown is session-only, never saved: the window opens on Fights.
--
-- THE WINDOW is a plain, non-secure frame (standalone-windows): skinned through NS.ApplySkin, closed
-- through NS.MakeCloseButton, in UISpecialFrames, clamped, toplevel in the HIGH tier
-- (LAYERS.STRATA.WINDOW: a browser opened to read and closed), movable by its title bar and
-- resizable from the library's grip (modules/Sizing.lua: a cheap layout while the grip is held, the
-- full redraw once on release), its place, size and view in `results.window` and its scale
-- `results.scale`.
-- General > Lock frame does not lock it (the lock is the lanes' and the HUD's, the displays the player
-- places for combat), and nothing opens it but the player. Built on first show.
--
-- EXPANDED OR COLLAPSED (DPS Race's owner's calls, 2026-10-25 and 2026-10-27, kept). Collapsed, the
-- default, shows the list alone, and a click puts the fight's detail in its place with a Back control;
-- expanded sets the detail beside the list, Results.DETAIL_WIDTH wide. Only the title bar's fold
-- arrow switches them (spec §7: "a fold arrow hides the detail"), never the width. `results.window`'s
-- width is the LIST's in both: expanded adds the detail's width beside it, so each view keeps its own
-- minimum (Results.MinWidth) and neither view's size is lost to the other.
--
-- WHAT RUNS. Nothing while hidden but its bus receiver: FIGHT_SAVED and FIGHTS_CHANGED redraw a
-- shown list and detail (a hidden one redraws in full on its next show), SETTINGS_CHANGED redraws
-- the footer or, on a profile change, takes the new profile's view, and COMBAT_ENTERED (the regen
-- edge, modules/Fight.lua) closes a shown window while `results.closeInCombat` is on; one reopened
-- mid-fight stays open, since a split or an encounter start sends no COMBAT_ENTERED. No game event, no
-- OnUpdate but a hovered row's and a dragged column edge's (modules/Results_Table.lua); the one timer
-- is the talent tree's (below), the ticker that waits for the tree to close while the window has
-- stepped aside for it.

local Results = { wanted = false }
NS.Results = Results

local L = NS.L
local Style = NS.Style
local Source = NS.ResultsSource

Results.FRAME_NAME = "CombatTrailResults"
Results.MIN_HEIGHT = 360
-- The detail's width beside the list in the expanded view.
Results.DETAIL_WIDTH = 440
-- The least width: the filter bar's and the table's, whichever is wider, and the window's border
-- (the suite holds it to both).
Results.MIN_WIDTH = math.max(NS.ResultsFights.BarMinWidth(),
    NS.ResultsTable.MinWidth(NS.ResultsFights.Columns())) + 2

local FOOTER_H = 20
-- The footer's hint; the fight count goes before it.
local HINT = L["Click a fight for its detail \194\183 right-click for options"]

-- The popups the window opens: each closes with it (frame-layering-§4, standalone-windows).
Results.POPUPS = { "COMBATTRAIL_DELETE_FIGHT", "COMBATTRAIL_FIGHT_NOTE", "COMBATTRAIL_SHARE_WHISPER" }

local ui                 -- the built window
local selected           -- the fight id the window has selected
local detailOpen = false -- the collapsed view: the detail stands in the list's place
local pick               -- the fight a "Compare With This Fight" picked (session only, plan Task 4.4)
local hiding = false     -- true while the addon hides the frame itself
local tab = "fights"     -- the tab shown (session only)

--- The window's tabs, left to right.
Results.TABS = { "fights", "insights" }
local TAB_LABELS = { fights = "Fights", insights = "Insights" }
local TAB_H = Style.TAB_STRIP_H

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Results", fmt, ...) end
end

-- ── stored geometry ─────────────────────────────────────────────────────────────────────────────

local function shippedWindow()
    return NS.defaults.profile.results.window
end

local function store()
    local p = NS.db and NS.db.profile
    if not p then return nil end
    if type(p.results) ~= "table" then p.results = {} end
    if type(p.results.window) ~= "table" then p.results.window = {} end
    return p.results.window
end

--- The view shown: "collapsed" (the default, the list alone) or "expanded" (the detail beside it).
function Results.View()
    local w = store() or {}
    return w.view == "expanded" and "expanded" or "collapsed"
end

--- The least frame width of `view` (the view shown by default): the list's, and the detail's beside
--- it when expanded.
function Results.MinWidth(view)
    view = view or Results.View()
    return Results.MIN_WIDTH + (view == "expanded" and Results.DETAIL_WIDTH or 0)
end

-- The frame's width for a stored LIST width: the detail's added when expanded.
local function frameWidth(listWidth)
    return listWidth + (Results.View() == "expanded" and Results.DETAIL_WIDTH or 0)
end

-- The list's width: the stored one held to its least, else the least itself, which is the shipped
-- width (no number ships: the filter bar and the columns set it; owner, 2026-11-11).
local function storedSize()
    local w, d = store() or {}, shippedWindow()
    return frameWidth(math.max(Results.MIN_WIDTH, tonumber(w.width) or Results.MIN_WIDTH)),
        math.max(Results.MIN_HEIGHT, tonumber(w.height) or d.height)
end

-- The shell frame never displays a meter value, so its own anchor is read back here, after a drag.
local function savePosition()
    local w = store()
    if not (w and ui) then return end
    local point, _, relPoint, x, y = ui.frame:GetPoint(1)
    if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return end
    w.point, w.relPoint = point, type(relPoint) == "string" and relPoint or point
    w.x, w.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

-- The grip's release: the size it reached (sizing-time writes are never made, standalone-windows).
local function saveSize(width, height)
    local w = store()
    if not w then return end
    if type(width) == "number" then
        local list = width - frameWidth(0)
        w.width = math.floor(math.max(Results.MIN_WIDTH, list) + 0.5)
    end
    if type(height) == "number" then w.height = math.floor(math.max(Results.MIN_HEIGHT, height) + 0.5) end
end

-- ── the parts ───────────────────────────────────────────────────────────────────────────────────

local layout, resize, render, renderDetail, footer, applyScale, buildTabs

local function fight(id)
    return id and Source.Get(id) or nil
end

local function selectFight(record)
    selected = record and record.id or nil
    detailOpen = selected ~= nil
    if not ui then return end
    ui.list.list:SetSelected(selected)
    renderDetail()
    layout()
end

-- The fold arrow's icon and tooltip for the view shown (DPS Race's): expanded shows chevron-left (fold
-- the detail away), collapsed chevron-right (open it beside the list, to the right).
local function paintToggle()
    local b = ui and ui.viewToggle
    if not b then return end
    local expanded = Results.View() == "expanded"
    Style.SetControlIcon(b, expanded and "chevron-left" or "chevron-right", expanded and "<" or ">")
    b.tip = expanded and L["Fold the detail away: the list alone (a click opens a fight in its place)"]
        or L["Unfold the detail beside the list"]
    Style.PaintStrip(ui.controls)
end

-- LootHistory's tab (its Browser tabs, not the skin's Tab primitive, which would lay a backing under
-- it): Style.FONT.TAB, the skin's `tab.onText` and its `tab.onLine` underline when active, `tab.text`
-- when not; flush under the title band, a rule under the strip.
local function tabButton(f, name, i)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(Style.TAB_W, TAB_H)
    b:SetPoint("TOPLEFT", Style.Band(f), "BOTTOMLEFT", 6 + (i - 1) * Style.TAB_PITCH, 0)
    b.label = Style.Text(b, Style.FONT.TAB, nil, "CENTER")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.label:SetText(L[TAB_LABELS[name]])
    b.underline = b:CreateTexture(nil, "OVERLAY")
    Style.Fill(b.underline, "tab.onLine")
    b.underline:SetHeight(2)
    b.underline:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 8, 0)
    b.underline:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 0)
    b:SetScript("OnClick", function() Results.ShowTab(name) end)
    ui.tabs[name] = b
end

function buildTabs(f)
    ui.tabs = {}
    for i, name in ipairs(Results.TABS) do tabButton(f, name, i) end
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    NS.Skin.Divider(line)
    local band = Style.Band(f)
    line:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, -TAB_H)
    line:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, -TAB_H)
    ui.tabRule = line
end

local function buildChrome(f)
    -- The title on the title band by the skin's `title.align`: the skin's Shell paints it, Style.Header
    -- places it and the controls on the band's middle.
    f.title = Style.PlainText(f, Style.FONT.TITLE, "CENTER")
    f.title:SetText(L["Combat Trail \226\128\148 Results"])
    ui.controls = Style.NewStrip()
    ui.close = NS.MakeCloseButton(f, function() Results.Hide() end)
    ui.settings = Style.AddToStrip(ui.controls, Style.ControlButton(f, "settings", "S", L["Settings"],
        function() NS.OpenSettings() end))
    ui.viewToggle = Style.AddToStrip(ui.controls, Style.ControlButton(f, "chevron-right", ">", "",
        function() Results.ToggleView() end))
    local drag = CreateFrame("Frame", nil, f)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        savePosition()
    end)
    ui.drag = drag
    Style.Header(f, { title = f.title, drag = drag, right = { ui.close, ui.viewToggle, ui.settings }, n = 3 })
    buildTabs(f)
end

local function buildFooter(f)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    NS.Skin.Divider(line)
    line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, FOOTER_H)
    line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, FOOTER_H)
    ui.footLeft = Style.Text(f, Style.FONT.CAPTION)
    ui.footLeft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 5)
    ui.footLeft:SetText(HINT)
    ui.footRight = Style.Text(f, Style.FONT.CAPTION, nil, "RIGHT")
    ui.footRight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 5)
end

local onHide

-- Every size change, the grip's or not: the tracked size the layouts read, never under the minimums.
local function trackSize(width, height)
    if type(width) == "number" then ui.width = math.max(Results.MinWidth(), width) end
    if type(height) == "number" then ui.height = math.max(Results.MIN_HEIGHT, height) end
end

-- The grip's minimum for the view shown.
local function applyBounds()
    local f = ui.frame
    if f.SetResizeBounds then f:SetResizeBounds(Results.MinWidth(), Results.MIN_HEIGHT) end
end

local function applyPlacement()
    local f, w, d = ui.frame, store() or {}, shippedWindow()
    ui.width, ui.height = storedSize()
    f:ClearAllPoints()
    f:SetPoint(w.point or d.point, UIParent, w.relPoint or d.relPoint, tonumber(w.x) or d.x, tonumber(w.y) or d.y)
    f:SetSize(ui.width, ui.height)
    applyBounds()
    paintToggle()
end

local function buildList()
    ui.list = NS.ResultsFights.Build(ui.body, {
        select = function(record) Results.Select(record and record.id) end,
        selected = function() return selected end,
        menu = function(record, row) Results.RowMenu(record, row) end,
        count = function(text) ui.count = text end,
        -- The detail's Delta box reads the list's groups: a new filter or grouping redraws it.
        changed = function() if ui.detail then ui.detail:RefreshDelta() end end,
    })
    if Source.IsMock() then ui.list:SampleView(true) end
end

-- A sample fight is never shared: its numbers are made up.
local function canShare()
    return NS.Share ~= nil and type(NS.Share.FillMenu) == "function" and not Source.IsMock()
end

local function buildDetail()
    ui.detail = NS.ResultsDetail.Build(ui.body, {
        back = function() Results.Back() end,
        note = function(record) Results.EditNote(record.id) end,
        share = function(record, owner) if canShare() then NS.Share.Prompt(record, owner) end end,
        delete = function(record) Results.ConfirmDelete(record.id) end,
        canShare = canShare,
        timeline = function(p)
            local TL = NS.ResultsTimeline
            if TL and type(TL.Open) == "function" then TL.Open(p) end
        end,
        compare = function(p)
            local CMP = NS.ResultsCompare
            if CMP and type(CMP.Open) == "function" then CMP.Open(p) end
        end,
        -- The list's Delta for the fight (its group, or the view), nil when its filters leave the
        -- fight out (the detail falls back to the fight's board).
        deltaContext = function(record) return ui.list:DeltaContext(record) end,
    })
end

local function ensureWindow()
    if ui then return ui end
    local f = CreateFrame("Frame", Results.FRAME_NAME, UIParent, "BackdropTemplate")
    ui = { frame = f }
    f:Hide()
    f:SetFrameStrata(NS.Constants.LAYERS.STRATA.WINDOW)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetToplevel(true)
    buildChrome(f)
    buildFooter(f)
    ui.body = CreateFrame("Frame", nil, f)
    ui.body:SetPoint("TOPLEFT", Style.Band(f), "BOTTOMLEFT", 0, -(1 + TAB_H))
    ui.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, FOOTER_H + 1)
    buildList()
    buildDetail()
    NS.ApplySkin(f)
    f:SetScript("OnHide", function() onHide() end)
    -- Escape closes it with the standard close stack (standalone-windows).
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Results.FRAME_NAME) end
    -- Smooth resizing (modules/Sizing.lua): while the grip is dragged only `resize` runs, once a frame;
    -- the full `layout` (every row rebound) runs once on release.
    NS.Sizing.MakeResizable(f, {
        minWidth = Results.MinWidth(), minHeight = Results.MIN_HEIGHT,
        size = trackSize, layout = function() resize() end, redraw = function() layout() end, done = saveSize,
    })
    applyPlacement()
    debug("window built")
    return ui
end

-- ── layout and drawing ──────────────────────────────────────────────────────────────────────────

-- The body stands under the title band and over the footer rule: its size is the band's own
-- geometry (the skin's inset and `title.height`), worked out, never read back off a frame.
local function bodySize()
    local inset, bandH = Style.BandGeometry()
    return ui.width - 1 - inset, ui.height - inset - bandH - TAB_H - FOOTER_H - 2 - (ui.drop or 0)
end

--- "wide" (the detail beside the list: the expanded view) or "narrow" (the detail in its place: the
--- collapsed view). The view decides, never the width.
function Results.Mode()
    return Results.View() == "expanded" and "wide" or "narrow"
end

-- The list's frame and the detail's, placed for the view: beside each other when wide; in the narrow
-- view one of the two, the detail while a fight is open in it.
-- The Insights tab, built on its first show (it reads the source then).
local function buildInsights()
    if ui.insights then return ui.insights end
    ui.insights = NS.ResultsInsights.Build(ui.body, {
        open = function(record) Results.ShowFight(record.id) end,
        menu = function(record, row) Results.RowMenu(record, row) end,
        -- A filter change redraws the footer's count at once.
        count = function(text)
            ui.insightsCount = text
            if tab == "insights" then footer() end
        end,
    })
    -- Built while the sample history is shown: it opens on the sample's view.
    if Source.IsMock() then ui.insights:SampleView(true) end
    debug("insights built")
    return ui.insights
end

-- Each tab's label and underline for the tab shown, and the panes it hides.
local function paintTabs()
    for _, name in ipairs(Results.TABS) do
        local b, on = ui.tabs[name], name == tab
        Style.Paint(b.label, on and "tab.onText" or "tab.text", Style.FONT.TAB)
        b.underline:SetShown(on)
    end
    if ui.insights then ui.insights.frame:SetShown(tab == "insights") end
end

-- The Insights tab across the body: the list and the detail hidden.
local function layoutInsights(width, height)
    ui.list.frame:Hide()
    ui.detail.frame:Hide()
    local pane = buildInsights()
    pane.frame:Show()
    pane:Layout(width, height)
end

function layout()
    if not ui then return end
    local width, height = bodySize()
    if tab == "insights" then return layoutInsights(width, height) end
    local detail = ui.detail
    detail.frame:ClearAllPoints()
    if Results.Mode() == "wide" then
        local dw = Results.DETAIL_WIDTH
        ui.list.frame:Show()
        ui.list:Layout(width - dw, height)
        detail.frame:SetPoint("TOPRIGHT", ui.body, "TOPRIGHT", 0, 0)
        detail.frame:SetSize(dw, height)
        detail.frame:Show()
        detail:Layout(dw, height, false)
        return
    end
    ui.list.frame:SetShown(not detailOpen)
    detail.frame:SetShown(detailOpen)
    if detailOpen then
        detail.frame:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 0, 0)
        detail.frame:SetSize(width, height)
        detail:Layout(width, height, true)
    else
        ui.list:Layout(width, height)
    end
end

-- The cheap half of a resize (modules/Sizing.lua): what layout places, at the tracked size, with
-- nothing rebound or redrawn.
function resize()
    if not ui then return end
    local width, height = bodySize()
    if tab == "insights" then
        if ui.insights then ui.insights:Resize(width, height) end
        return
    end
    local detail = ui.detail
    if Results.Mode() == "wide" then
        local dw = Results.DETAIL_WIDTH
        ui.list:Resize(width - dw, height)
        detail.frame:SetSize(dw, height)
        detail:Resize(dw, height)
    elseif detailOpen then
        detail.frame:SetSize(width, height)
        detail:Resize(width, height)
    else
        ui.list:Resize(width, height)
    end
end

--- Switch to `view` ("expanded" | "collapsed"): its own size and minimum, the window's top-left
--- corner kept where it is, and the detail closed in a collapsed view (it opens on the list).
--- @return boolean switched
function Results.SetView(view)
    if view ~= "expanded" and view ~= "collapsed" then return false end
    local w = store()
    if not w or Results.View() == view then return false end
    w.view = view
    detailOpen = false
    if not ui then return true end
    local f = ui.frame
    local left, top = NS.Secrets.PlainNumber(f:GetLeft()), NS.Secrets.PlainNumber(f:GetTop())
    ui.width, ui.height = storedSize()
    applyBounds()
    f:SetSize(ui.width, ui.height)
    if left and top then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        savePosition()
    end
    paintToggle()
    renderDetail()
    layout()
    return true
end

--- The title bar's fold arrow.
function Results.ToggleView()
    return Results.SetView(Results.View() == "expanded" and "collapsed" or "expanded")
end

--- The detail's Back (the collapsed view): the list again, the fight still selected.
function Results.Back()
    detailOpen = false
    layout()
end

--- Whether the collapsed view shows the detail in the list's place now.
function Results.DetailOpen()
    return detailOpen
end

function footer()
    -- The tab's count before the hint.
    local count = tab == "insights" and ui.insightsCount or ui.count
    ui.footLeft:SetText(count and (count .. " \194\183 " .. HINT) or HINT)
    -- GetSetting answers the shipped default itself (settings/Schema.lua); no second literal here.
    local days = tonumber(NS.GetSetting("history.days"))
    ui.footRight:SetText(days and days > 0 and L["Fights are kept for %d days"]:format(days)
        or L["Fights are kept until you delete them"])
end

-- The modal windows that follow the detail (its fight and its compare target), each by its NS name.
Results.FOLLOWERS = { "ResultsTimeline", "ResultsGear", "ResultsCompare" }

-- Each follower that has `method`, called with `...`.
local function eachFollower(method, ...)
    for _, name in ipairs(Results.FOLLOWERS) do
        local m = NS[name]
        if m and type(m[method]) == "function" then m[method](...) end
    end
end

function renderDetail()
    if not ui then return end
    if selected and not fight(selected) then selected, detailOpen = nil, false end
    ui.detail:Show(fight(selected))
    -- The timeline, the gear view and the compare follow the detail's fight and its compare target.
    eachFollower("DetailChanged", ui.detail)
end

--- Close every modal window over this one but `keep` (an NS name, nil for none): one opens at a time,
--- under the one dim cover.
function Results.CloseModals(keep)
    for _, name in ipairs(Results.FOLLOWERS) do
        local m = NS[name]
        if name ~= keep and m and type(m.Hide) == "function" then m.Hide() end
    end
end

-- `reveal` scrolls the list to the selected fight (the window opened on it): a store change alone
-- leaves the list where the player scrolled it.
function render(reveal)
    if not ui then return end
    if selected and not fight(selected) then selected, detailOpen = nil, false end
    if pick and not fight(pick) then pick = nil end
    paintTabs()
    if tab == "insights" then
        buildInsights():Refresh()
        layout()
        footer()
        return
    end
    ui.list:Refresh()
    if selected and reveal then ui.list.list:Reveal(selected) end
    renderDetail()
    layout()
    footer()
end

local function windowShown()
    return ui ~= nil and ui.frame:IsShown() == true
end

-- ── the sample marker (test mode, the sim) ──────────────────────────────────────────────────────
-- While the window shows the sample history it says so, as the HUD does: the library's strip under
-- the title band, the body moved down by its height (standalone-windows). A running sim wears the
-- library's cyan sim strip, test mode the amber test strip. With no Widgets library there is no
-- strip, and the title carries the word instead; never both.

local function anchorStrip(strip)
    if strip then
        local band = Style.Band(ui.frame)
        strip:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, -(1 + TAB_H))
        strip:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, -(1 + TAB_H))
    end
    return strip
end

local function ensureStrip(sim)
    local key = sim and "simStrip" or "testStrip"
    if ui[key .. "Tried"] then return ui[key] end
    ui[key .. "Tried"] = true
    if sim then
        ui[key] = anchorStrip(NS.MakeSimStrip(ui.frame, L["Sim: a made-up fight, not your data. /ct sim ends it."]))
    else
        ui[key] = anchorStrip(NS.MakeTestStrip(ui.frame, L["Test mode: sample fights. Nothing here is saved."]))
    end
    return ui[key]
end

-- What the window shows now: nil (the player's fights), "test" or "sim".
local function sampleMode()
    if not Source.IsMock() then return nil end
    local P = NS.Preview
    local sim = P ~= nil and type(P.Mode) == "function" and P.Mode() == "sim"
    return sim and "sim" or "test"
end

-- The strip for `mode` shown and the other hidden; answers the one shown, or nil.
local function showStrip(mode)
    local test = mode == "test" and ensureStrip(false) or ui.testStrip
    local sim = mode == "sim" and ensureStrip(true) or ui.simStrip
    if test then test:SetShown(mode == "test") end
    if sim then sim:SetShown(mode == "sim") end
    if mode == "sim" then return sim end
    return mode == "test" and test or nil
end

local function applySampleMarker()
    local mode = sampleMode()
    local strip = showStrip(mode)
    local drop = strip and NS.TEST_STRIP_HEIGHT or 0
    if ui.drop ~= drop then
        ui.drop = drop
        ui.body:SetPoint("TOPLEFT", Style.Band(ui.frame), "BOTTOMLEFT", 0, -(1 + TAB_H + drop))
    end
    local marked = mode ~= nil and not strip
    ui.frame.title:SetText(marked and L["Combat Trail \226\128\148 Results \194\183 Test"]
        or L["Combat Trail \226\128\148 Results"])
end

-- The popups the window opened close with it (frame-layering-§4).
local function closePopups()
    if type(StaticPopup_Hide) ~= "function" then return end
    for _, name in ipairs(Results.POPUPS) do StaticPopup_Hide(name) end
end

-- The windows that follow the detail (the ability timeline, the gear view, the compare: plan Tasks
-- 4.3, 4.4) close with it.
local function hideFollowers()
    Results.CloseModals(nil)
end

local function hideWindow()
    hideFollowers()
    if windowShown() then
        hiding = true
        ui.frame:Hide()
        hiding = false
    end
    closePopups()
    NS.CloseMenu()
end

-- THE WINDOW STEPS ASIDE FOR THE TALENT TREE AND COMES BACK WHEN IT CLOSES (DPS Race's owner's call,
-- 2026-10-25, kept). Blizzard shows its talent frame (`PlayerSpellsFrame`: the detail's View, the
-- talentbuild link it posts to chat, or the N key) as a "center" UI panel, and showing one runs the
-- close stack, which hides every UISpecialFrames entry: this window among them, just before the tree
-- shows. The frame stays in UISpecialFrames (standalone-windows: Escape and the close stack), so the
-- close is answered rather than prevented: a close-stack close looks again on the next frame, and a
-- tree up by then is what closed it, so the window waits, polling IsShown every Results.TREE_POLL
-- seconds, and comes back once the tree is down. It does not come back OVER the tree: this window
-- sits at HIGH strata and the tree is a MEDIUM panel, and a runtime strata switch is forbidden
-- (frame-layering-§4). The player opening or closing the window while it waits ends the wait. The
-- one read of a Blizzard frame is IsShown; nothing is hooked, shown or hidden on Blizzard's side. A
-- client with no such frame (WoW Forever's tree is another frame) never waits.
Results.TREE_POLL = 0.25
local treeWait

local function talentTreeShown()
    local f = PlayerSpellsFrame
    return type(f) == "table" and type(f.IsShown) == "function" and f:IsShown() == true
end

local function stopTreeWait()
    if treeWait then treeWait:Cancel() end
    treeWait = nil
end

local function backAfterTree()
    if talentTreeShown() then return end
    stopTreeWait()
    if Results.wanted then return end
    debug("the talent tree closed; back")
    Results.Show()
end

local function awaitTree()
    if treeWait or not (C_Timer and C_Timer.NewTicker) then return end
    debug("stepped aside for the talent tree")
    treeWait = C_Timer.NewTicker(Results.TREE_POLL, backAfterTree)
end

local function reopenUnderTree()
    if Results.wanted or not talentTreeShown() then return end
    awaitTree()
end

--- The detail's View just opened the talent tree: when the window is still up (another panel was
--- already open, so the close stack did not run), it steps aside and comes back when the tree closes.
function Results.StepAsideForTree()
    if not (Results.wanted and talentTreeShown()) then return end
    Results.wanted = false
    Results.Refresh()
    awaitTree()
end

--- Whether the window is waiting for the talent tree to close (the suites).
function Results.AwaitingTree()
    return treeWait ~= nil
end

-- The frame went away by Escape (UISpecialFrames): the player closed it. A frame still shown in its
-- own right was hidden with its parent (Alt-Z), which is not the player closing it.
-- With the ability timeline open over it (the cover up), the close stack's hide was the timeline's:
-- the timeline is the modal, so Escape closes it first and the window shows again at once (the cover
-- goes once the timeline's own hide settles, modules/Results_Timeline.lua).
function onHide()
    NS.CloseMenu()
    if hiding or (ui and ui.frame:IsShown()) then return end
    if Results.wanted and Results.IsCovered() then
        ui.frame:Show()
        debug("Escape went to the timeline first")
        return
    end
    Results.wanted = false
    if NS.Preview then NS.Preview.ResultsClosed() end
    hideFollowers()
    closePopups()
    if not talentTreeShown() and C_Timer and C_Timer.After then C_Timer.After(0, reopenUnderTree) end
end

-- THE MODAL COVER. While the ability timeline is open over the window (one strata above it,
-- core/Constants.lua LAYERS), the skin's `ct.cover.dim` dims the whole window and its frame takes the
-- mouse and the wheel at W + LEVEL.COVER, over the grip and every content level: no hover, click or
-- scroll reaches the window behind, so no Results tooltip shows through. A click on it does nothing
-- (the timeline's close control and Escape close the timeline). A child of the window, so it hides
-- with it; the timeline shows and hides it. Built on the first cover; its level set again on each show
-- (a click raises the toplevel window's level).
local function ensureCover()
    if ui.cover then return ui.cover end
    local c = CreateFrame("Frame", nil, ui.frame)
    c:Hide()
    c:SetAllPoints(ui.frame)
    c:EnableMouse(true)
    c:EnableMouseWheel(true)
    c:SetScript("OnMouseWheel", function() end)
    c.dim = c:CreateTexture(nil, "BACKGROUND")
    c.dim:SetAllPoints(c)
    Style.Fill(c.dim, "ct.cover.dim")
    ui.cover = c
    return c
end

--- The ability timeline opened (`on`) or closed over the window: the dim cover up or down. An open
--- closes a filter menu and the window's tooltip, which would act on or speak for the window behind.
function Results.SetCovered(on)
    if not ui then return end
    if not on then
        if ui.cover then ui.cover:Hide() end
        return
    end
    local c = ensureCover()
    c:SetFrameLevel(ui.frame:GetFrameLevel() + NS.Constants.LAYERS.LEVEL.COVER)
    c:Show()
    NS.CloseMenu()
    NS.ResultsTable.HideTip()
end

--- Whether the dim cover is up (the ability timeline open over the window).
function Results.IsCovered()
    return ui ~= nil and ui.cover ~= nil and ui.cover:IsShown() == true
end

--- Where the window is and its size in the view shown, for the ability timeline to open exactly over
--- it: its anchor (read back off the shell frame, which shows no meter value, so a move not yet stored
--- still counts; the stored one before the window is built) and the size it tracks.
--- @return string point, string relativePoint, number x, number y, number width, number height
function Results.Placement()
    local w, d = store() or {}, shippedWindow()
    local point, relativePoint = w.point or d.point, w.relPoint or d.relPoint
    local x, y = tonumber(w.x) or d.x, tonumber(w.y) or d.y
    local width, height = storedSize()
    if ui then
        local p, _, rp, px, py = ui.frame:GetPoint(1)
        if type(p) == "string" and type(px) == "number" and type(py) == "number" then
            point, relativePoint, x, y = p, type(rp) == "string" and rp or p, px, py
        end
        width, height = ui.width or width, ui.height or height
    end
    return point, relativePoint, x, y, width, height
end

-- `results.scale` (History > Results window) on the window, read at each show.
function applyScale()
    local scale = tonumber(NS.GetSetting("results.scale"))
    if ui and scale and scale > 0 then ui.frame:SetScale(scale) end
end

--- A change to Window scale: the window and every follower open over it take it at once.
function Results.ApplyScale()
    applyScale()
    eachFollower("ApplyScale")
end

-- ── the public surface ──────────────────────────────────────────────────────────────────────────

--- Whether the window decides to show: wanted, and the addon standing up.
function Results.IsShown()
    return Results.wanted and not NS.IsStoodDown()
end

--- Re-decide and redraw. The one place the frame follows the decision.
function Results.Refresh(reveal)
    if not Results.IsShown() then return hideWindow() end
    ensureWindow()
    applyScale()
    local opening = not windowShown()
    if opening then ui.frame:Show() end
    applySampleMarker()
    render(reveal or opening)
end

function Results.Show()
    stopTreeWait()
    Results.wanted = true
    Results.Refresh()
end

function Results.Hide()
    stopTreeWait()
    Results.wanted = false
    if NS.Preview then NS.Preview.ResultsClosed() end
    Results.Refresh()
end

function Results.Toggle()
    if Results.IsShown() then Results.Hide() else Results.Show() end
end

--- Select fight `id` in the list (nil clears the selection).
function Results.Select(id)
    selectFight(fight(id))
end

--- Open the window on fight `id` (the HUD's chart control): selected, scrolled into view and its
--- detail shown (in the list's place when collapsed), a fight the filters hide included; an id no
--- longer stored opens the list alone.
--- @param id string|nil
--- @return boolean shown
function Results.ShowFight(id)
    selected = fight(id) and id or nil
    detailOpen = selected ~= nil
    tab = "fights"
    stopTreeWait()
    Results.wanted = true
    Results.Refresh(true)
    return Results.IsShown()
end

--- `NS.Results.Open(fightID|nil)` (the plan's name): the window on that fight, or on the list.
function Results.Open(id)
    if id ~= nil then return Results.ShowFight(id) end
    Results.Show()
    return Results.IsShown()
end

--- Open the window on tab `name` ("fights" | "insights"); a switch closes an open filter menu.
--- @return boolean shown
function Results.ShowTab(name)
    if not TAB_LABELS[name] then return false end
    if name ~= tab then NS.CloseMenu() end
    tab = name
    if tab == "insights" then Results.CloseModals(nil) end
    Results.Show()
    return Results.IsShown()
end

--- The tab shown ("fights" | "insights").
function Results.Tab()
    return tab
end

--- The fight the window has selected, or nil.
function Results.Selected()
    return selected
end

--- The Locked row's reaction (core/CombatTrail.lua's PLACED): the Results window is a browser the
--- player moves freely, so General > Lock frame leaves it alone.
function Results.SetLocked(_)
end

--- Back to the shipped place and size (Master controls' Reset position).
function Results.ResetPosition()
    local w = store()
    if w then
        for k in pairs(w) do w[k] = nil end
        for k, v in pairs(shippedWindow()) do w[k] = v end
    end
    -- The columns' dragged widths go back to the shipped ones with the window's size.
    NS.ResultsFights.ClearColumnWidths()
    detailOpen = false
    if ui then
        applyPlacement()
        renderDetail()
        layout()
    end
    -- An open timeline, gear view or compare goes back over the window, at its new place.
    eachFollower("ResetPosition")
end

--- Open the window on the list under the Races filter (`/ct results races`, Race mode plan Task D1;
--- Retail only: the filter is absent on WoW Forever).
--- @return boolean shown
function Results.ShowRaces()
    if not NS.ResultsRaces.On() then return false end
    tab = "fights"
    Results.Show()
    if not ui then return false end
    detailOpen = false
    ui.list:SetFilter("kind", "races")
    return true
end

local VERBS = {
    [""] = function() Results.Toggle() end,
    toggle = function() Results.Toggle() end,
    show = function() Results.Show() end,
    hide = function() Results.Hide() end,
    insights = function() Results.ShowTab("insights") end,
}
-- The Races verb is Retail's, as the filter it opens (clients-§4).
local RACE_VERBS = { races = function() Results.ShowRaces() end }

--- `/ct results [show|hide|toggle|insights|races]`: bare toggles the window, `insights` opens the
--- Insights tab (both clients), `races` the list under the Races filter (Retail); anything else is one
--- usage line.
function Results.OnVerb(rest)
    local word = tostring(rest or ""):match("^%s*(%S*)"):lower()
    local fn = VERBS[word] or (NS.ResultsRaces.On() and RACE_VERBS[word])
    if fn then return fn() end
    if NS.ResultsRaces.On() then
        return NS.Print(L["Usage: /ct results, or /ct results show, hide, toggle, insights or races"])
    end
    NS.Print(L["Usage: /ct results, or /ct results show, hide, toggle or insights"])
end

-- ── the row menu ────────────────────────────────────────────────────────────────────────────────

--- Compare the selected fight with fight `id` (the row menu's Compare With This Fight): a session-only
--- pick, never stored, that holds until it is cleared or the fight is deleted (plan Task 4.4 draws it).
--- @return boolean picked
function Results.CompareWith(id)
    if not fight(id) then return false end
    pick = id
    if windowShown() then render() end
    return true
end

--- Clear the pick: the compare goes back to the best on the fight's board.
function Results.ClearPick()
    pick = nil
    if windowShown() then render() end
end

--- The picked fight's id, or nil.
function Results.Pick()
    return pick
end

--- A row's right-click menu (LootHistory's): Add Note (Edit Note once it has one), Share with its
--- channels as a submenu (grayed on sample fights, whose numbers are made up),
--- Compare With This Fight (grayed on the selected fight itself), a race's Ignore for late casts
--- submenu (Retail, a stored race with a late cast: modules/Results_RaceDetail.lua), and Delete
--- behind its confirmation.
--- @param record table  the fight
--- @param owner table  the row
--- @return boolean opened
function Results.RowMenu(record, owner)
    if not (record and NS.CanOpenMenu()) then return false end
    NS.OpenMenu(owner or UIParent, function(root)
        root:CreateTitle(NS.ResultsTable.Date(record.t, "%d %b %H:%M"))
        local hasNote = type(record.note) == "string" and record.note ~= ""
        root:CreateButton(hasNote and L["Edit Note"] or L["Add Note"], function() Results.EditNote(record.id) end)
        local shareMenu = root:CreateButton(L["Share"])
        if canShare() then NS.Share.FillMenu(shareMenu, record) else shareMenu:SetEnabled(false) end
        local cmp = root:CreateButton(L["Compare With This Fight"], function() Results.CompareWith(record.id) end)
        if record.id == selected or selected == nil then cmp:SetEnabled(false) end
        NS.ResultsRaceDetail.FillRowMenu(root, record)
        -- A destructive item in the skin's `sem.danger`.
        root:CreateButton((NS.SkinEscape("sem.danger") or "") .. L["Delete"] .. "|r",
            function() Results.ConfirmDelete(record.id) end)
    end)
    return true
end

-- ── the acts the menu runs ──────────────────────────────────────────────────────────────────────

StaticPopupDialogs["COMBATTRAIL_DELETE_FIGHT"] = {
    text         = L["Delete this fight? This cannot be undone, and a personal best it holds goes with it."],
    button1      = L["Delete"],
    button2      = L["Cancel"],
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept     = function(_, data) Results.DeleteFight(data.id) end,
}

-- The note box: the client's own popup with an edit box, filled with the fight's note. The box is
-- the popup's GetEditBox() on a current client, its `editBox` field on an older one.
local function noteBox(popup)
    if type(popup.GetEditBox) == "function" then return popup:GetEditBox() end
    return popup.editBox or popup.EditBox
end

StaticPopupDialogs["COMBATTRAIL_FIGHT_NOTE"] = {
    text         = L["A note for this fight (200 characters at most):"],
    button1      = L["Save"],
    button2      = L["Cancel"],
    hasEditBox   = true,
    maxLetters   = NS.Recorder.NOTE_MAX,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnShow       = function(self, data)
        local box = noteBox(self)
        if box and data then box:SetText(data.note or "") end
    end,
    OnAccept     = function(self, data)
        local box = noteBox(self)
        if box and data then Results.SetNote(data.id, box:GetText()) end
    end,
    -- Enter in the box saves and closes, as Save does; Escape closes and saves nothing.
    EditBoxOnEnterPressed = function(box, data)
        if data then Results.SetNote(data.id, box:GetText()) end
        box:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(box)
        box:GetParent():Hide()
    end,
}

--- Ask before deleting a fight (spec §7); the popup's Accept deletes it.
--- @return boolean asked
function Results.ConfirmDelete(id)
    if not fight(id) then return false end
    StaticPopup_Show("COMBATTRAIL_DELETE_FIGHT", nil, nil, { id = id })
    return true
end

--- Delete a fight from the store (Recorder.Delete fires FIGHTS_CHANGED, which redraws the window), or
--- a sample fight from the sample history (the source redraws it).
function Results.DeleteFight(id)
    if selected == id then selected, detailOpen = nil, false end
    if pick == id then pick = nil end
    return Source.Delete(id)
end

--- Write fight `id`'s note (the row menu's Add Note): the note box, filled with its note.
--- @return boolean asked
function Results.EditNote(id)
    local record = fight(id)
    if not record then return false end
    StaticPopup_Show("COMBATTRAIL_FIGHT_NOTE", nil, nil, { id = id, note = record.note })
    return true
end

--- Store a fight's note (Recorder.ClampNote's: escapes neutralized, trimmed, at most NOTE_MAX
--- characters) and answer what was stored.
function Results.SetNote(id, text)
    local record = fight(id)
    if not record then return nil end
    Source.SetNote(id, text)
    return record.note
end

--- The source changed (modules/Results_Source.lua): `swapped` between the store and the sample
--- history, which drops the selection and the pick (neither is in the other) and moves the list's
--- view to the sample's or back to the player's; else the sample changed (a note, a delete). A
--- hidden window redraws in full on its next show.
function Results.OnSourceChanged(swapped)
    if swapped then
        -- The timeline followed a fight the other source does not hold: it closes, and the cover goes.
        hideFollowers()
        selected, pick, detailOpen = nil, nil, false
        if ui then ui.list:SampleView(Source.IsMock()) end
        if ui and ui.insights then ui.insights:SampleView(Source.IsMock()) end
    end
    if windowShown() then
        applySampleMarker()
        render()
    end
end

--- The lifecycle's stand-down: the window hides (it decides not to show while stood down).
function Results.Suspend()
    stopTreeWait()
    hideWindow()
end

--- The stand-up: back on screen if the player had it open.
function Results.Resume()
    Results.Refresh()
end

--- What the window is doing, for the diagnostics report.
function Results.Diagnose()
    return { shown = Results.IsShown(), tab = tab, selected = selected or "none",
             rows = ui and ui.list:Count() or 0, view = Results.View(), detailOpen = detailOpen }
end

--- The built window, for the suites (nil until first shown).
function Results.__ui() return ui end

-- ── the store, heard on the bus ─────────────────────────────────────────────────────────────────

-- A hidden window draws nothing: its next show redraws in full.
local function onStoreChanged()
    if windowShown() then render() end
end

-- A profile change takes the new profile's view, place, size and fold whether the window is up or not
-- (a hidden list keeps its filters for its next show). The render lays the columns out at the new
-- profile's dragged widths (Fights.ColumnWidths reads the live profile) and, through renderDetail's
-- DetailChanged, redraws an open timeline in the new profile's mark mode; a hidden window does both on
-- its next show (tests/test_results_table.lua, tests/test_timeline_marks.lua).
local function onProfile()
    ui.list:ApplyView(NS.ResultsFights.SavedView())
    if ui.insights then ui.insights:ApplyView(NS.ResultsInsights.SavedView()) end
    detailOpen = false
    applyPlacement()
    if windowShown() then render() end
end

local function onSettings(path)
    if path == "profile" and ui then return onProfile() end
    if path == "history.days" and windowShown() then footer() end
    -- History > Results window: the scale on the window and its followers, the row height on the list.
    if path == "results.scale" then Results.ApplyScale() end
    if path == "results.rowHeight" and windowShown() then render() end
    -- How the ability timeline's By ability draws a cast (v0.2 Task D1): an open one redraws, its zoom kept.
    if path == "results.timelineMarks" then NS.ResultsTimeline.Redraw() end
    -- The Usage "never show" list: the detail redraws (an edit under way keeps its ticks).
    if path == NS.Usage.HIDDEN_PATH and windowShown() then renderDetail() end
    -- The late-cast ignore list re-scores every race's flags, and the Training dummies list moves races
    -- between kinds: the sample's boards are dropped and the window redraws (Race mode plan Task D1).
    if path == NS.LateIgnore.PATH or path == NS.Dummies.PATH then
        NS.Bests.Invalidate()
        Source.Invalidate()
        if windowShown() then render() end
    end
end

do
    local bus = NS.NewBusTarget()
    if bus then
        bus:RegisterMessage(NS.MSG.FIGHT_SAVED, onStoreChanged)
        bus:RegisterMessage(NS.MSG.FIGHTS_CHANGED, onStoreChanged)
        bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path) onSettings(path) end)
        -- Hide is legal in combat: the frame is non-secure (the header's note).
        bus:RegisterMessage(NS.MSG.COMBAT_ENTERED, function()
            if Results.wanted and NS.GetSetting("results.closeInCombat") then Results.Hide() end
        end)
    end
end
