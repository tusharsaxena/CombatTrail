local _, NS = ...
-- modules/Results.lua — the Results window's shell (spec §7, mockup §5): the window, its title bar,
-- the fight list in its body (modules/Results_Fights.lua over modules/Results_Table.lua), the footer,
-- the row menu, and the window's public surface (Show, Hide, Toggle, Open, ShowFight). Adapted from
-- DPS Race @045f479 (modules/Results.lua) without its race and without its Insights tab (deferred,
-- spec §2): one list, so no tab strip. The fight detail (Task 4.2) places itself beside the list.
--
-- THE WINDOW is a plain, non-secure frame (standalone-windows): skinned through NS.ApplySkin, closed
-- through NS.MakeCloseButton, in UISpecialFrames, clamped, toplevel in the HIGH tier
-- (LAYERS.STRATA.WINDOW: a browser opened to read and closed), movable by its title bar and
-- resizable from the library's grip (modules/Sizing.lua: a cheap layout while the grip is held, the
-- full redraw once on release), its place and size in `results.window` and its scale `results.scale`.
-- General > Lock frame does not lock it (the lock is the lanes' and the HUD's, the displays the player
-- places for combat), and nothing opens it but the player. Built on first show.
--
-- WHAT RUNS. Nothing while hidden but its bus receiver: FIGHT_SAVED and FIGHTS_CHANGED redraw a
-- shown list (a hidden one redraws in full on its next show), SETTINGS_CHANGED redraws the footer or,
-- on a profile change, takes the new profile's view. No game event, no OnUpdate but a hovered row's
-- (modules/Results_Table.lua), no timer.

local Results = { wanted = false }
NS.Results = Results

local L = NS.L
local Style = NS.Style
local Source = NS.ResultsSource

Results.FRAME_NAME = "CombatTrailResults"
Results.MIN_HEIGHT = 360
-- The least width: the filter bar's and the table's, whichever is wider, and the window's border
-- (the suite holds it to both).
Results.MIN_WIDTH = math.max(NS.ResultsFights.BarMinWidth(),
    NS.ResultsTable.MinWidth(NS.ResultsFights.Columns())) + 2

local FOOTER_H = 20
-- The footer's hint; the fight count goes before it.
local HINT = L["Right-click a fight for options"]

local ui                 -- the built window
local selected           -- the fight id the window has selected
local pick               -- the fight a "Compare With This Fight" picked (session only, plan Task 4.4)
local hiding = false     -- true while the addon hides the frame itself

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

local function storedSize()
    local w, d = store() or {}, shippedWindow()
    return math.max(Results.MIN_WIDTH, tonumber(w.width) or d.width),
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
    if type(width) == "number" then w.width = math.floor(math.max(Results.MIN_WIDTH, width) + 0.5) end
    if type(height) == "number" then w.height = math.floor(math.max(Results.MIN_HEIGHT, height) + 0.5) end
end

-- ── the parts ───────────────────────────────────────────────────────────────────────────────────

local layout, resize, render, footer

local function fight(id)
    return id and Source.Get(id) or nil
end

local function selectFight(record)
    selected = record and record.id or nil
    if ui and ui.list then ui.list.list:SetSelected(selected) end
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
    local drag = CreateFrame("Frame", nil, f)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        savePosition()
    end)
    ui.drag = drag
    Style.Header(f, { title = f.title, drag = drag, right = { ui.close, ui.settings }, n = 2 })
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
    if type(width) == "number" then ui.width = math.max(Results.MIN_WIDTH, width) end
    if type(height) == "number" then ui.height = math.max(Results.MIN_HEIGHT, height) end
end

local function applyPlacement()
    local f, w, d = ui.frame, store() or {}, shippedWindow()
    ui.width, ui.height = storedSize()
    f:ClearAllPoints()
    f:SetPoint(w.point or d.point, UIParent, w.relPoint or d.relPoint, tonumber(w.x) or d.x, tonumber(w.y) or d.y)
    f:SetSize(ui.width, ui.height)
    if f.SetResizeBounds then f:SetResizeBounds(Results.MIN_WIDTH, Results.MIN_HEIGHT) end
end

local function buildList()
    ui.list = NS.ResultsFights.Build(ui.body, {
        select = function(record) Results.Select(record and record.id) end,
        selected = function() return selected end,
        menu = function(record, row) Results.RowMenu(record, row) end,
        count = function(text) ui.count = text end,
    })
    if Source.IsMock() then ui.list:SampleView(true) end
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
    ui.body:SetPoint("TOPLEFT", Style.Band(f), "BOTTOMLEFT", 0, -1)
    ui.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, FOOTER_H + 1)
    buildList()
    NS.ApplySkin(f)
    f:SetScript("OnHide", function() onHide() end)
    -- Escape closes it with the standard close stack (standalone-windows).
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Results.FRAME_NAME) end
    -- Smooth resizing (modules/Sizing.lua): while the grip is dragged only `resize` runs, once a frame;
    -- the full `layout` (every row rebound) runs once on release.
    NS.Sizing.MakeResizable(f, {
        minWidth = Results.MIN_WIDTH, minHeight = Results.MIN_HEIGHT,
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
    return ui.width - 1 - inset, ui.height - inset - bandH - FOOTER_H - 2 - (ui.drop or 0)
end

function layout()
    if not ui then return end
    local width, height = bodySize()
    ui.list:Layout(width, height)
end

-- The cheap half of a resize (modules/Sizing.lua): what layout places, at the tracked size, with
-- nothing rebound.
function resize()
    if not ui then return end
    local width, height = bodySize()
    ui.list:Resize(width, height)
end

function footer()
    ui.footLeft:SetText(ui.count and (ui.count .. " \194\183 " .. HINT) or HINT)
    -- GetSetting answers the shipped default itself (settings/Schema.lua); no second literal here.
    local days = tonumber(NS.GetSetting("history.days"))
    ui.footRight:SetText(days and days > 0 and L["Fights are kept for %d days"]:format(days)
        or L["Fights are kept until you delete them"])
end

function render()
    if not ui then return end
    if selected and not fight(selected) then selected = nil end
    if pick and not fight(pick) then pick = nil end
    ui.list:Refresh()
    if selected then ui.list.list:Reveal(selected) end
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
        strip:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, -1)
        strip:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, -1)
    end
    return strip
end

local function ensureStrip(sim)
    local key = sim and "simStrip" or "testStrip"
    if ui[key .. "Tried"] then return ui[key] end
    ui[key .. "Tried"] = true
    if sim then
        ui[key] = anchorStrip(NS.MakeSimStrip(ui.frame, L["Sim: a made-up fight, not your data. /kct sim ends it."]))
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
        ui.body:SetPoint("TOPLEFT", Style.Band(ui.frame), "BOTTOMLEFT", 0, -(1 + drop))
    end
    local marked = mode ~= nil and not strip
    ui.frame.title:SetText(marked and L["Combat Trail \226\128\148 Results \194\183 Test"]
        or L["Combat Trail \226\128\148 Results"])
end

local function hideWindow()
    if windowShown() then
        hiding = true
        ui.frame:Hide()
        hiding = false
    end
    NS.CloseMenu()
end

-- The frame went away by Escape (UISpecialFrames): the player closed it. A frame still shown in its
-- own right was hidden with its parent (Alt-Z), which is not the player closing it.
function onHide()
    NS.CloseMenu()
    if hiding or (ui and ui.frame:IsShown()) then return end
    Results.wanted = false
end

-- ── the public surface ──────────────────────────────────────────────────────────────────────────

--- Whether the window decides to show: wanted, and the addon standing up.
function Results.IsShown()
    return Results.wanted and not NS.IsStoodDown()
end

--- Re-decide and redraw. The one place the frame follows the decision.
function Results.Refresh()
    if not Results.IsShown() then return hideWindow() end
    ensureWindow()
    local scale = tonumber(NS.GetSetting("results.scale"))
    if scale and scale > 0 then ui.frame:SetScale(scale) end
    if not windowShown() then ui.frame:Show() end
    applySampleMarker()
    render()
end

function Results.Show()
    Results.wanted = true
    Results.Refresh()
end

function Results.Hide()
    Results.wanted = false
    Results.Refresh()
end

function Results.Toggle()
    if Results.IsShown() then Results.Hide() else Results.Show() end
end

--- Select fight `id` in the list (nil clears the selection).
function Results.Select(id)
    selectFight(fight(id))
end

--- Open the window on fight `id` (the HUD's chart control): selected and scrolled into view. A fight
--- the filters hide still opens the window; an id no longer stored opens the list alone.
--- @param id string|nil
--- @return boolean shown
function Results.ShowFight(id)
    selected = fight(id) and id or nil
    Results.Show()
    return Results.IsShown()
end

--- `NS.Results.Open(fightID|nil)` (the plan's name): the window on that fight, or on the list.
function Results.Open(id)
    if id ~= nil then return Results.ShowFight(id) end
    Results.Show()
    return Results.IsShown()
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
    if ui then
        applyPlacement()
        layout()
    end
end

local VERBS = {
    [""] = function() Results.Toggle() end,
    toggle = function() Results.Toggle() end,
    show = function() Results.Show() end,
    hide = function() Results.Hide() end,
}

--- `/kct results [show|hide|toggle]`: bare toggles the window; anything else is one usage line.
function Results.OnVerb(rest)
    local word = tostring(rest or ""):match("^%s*(%S*)"):lower()
    local fn = VERBS[word]
    if fn then return fn() end
    NS.Print(L["Usage: /kct results, or /kct results show, hide or toggle"])
end

-- ── the row menu ────────────────────────────────────────────────────────────────────────────────

-- A sample fight is never shared: its numbers are made up.
local function canShare()
    return NS.Share ~= nil and type(NS.Share.FillMenu) == "function" and not Source.IsMock()
end

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
end

--- The picked fight's id, or nil.
function Results.Pick()
    return pick
end

--- A row's right-click menu (LootHistory's): Add Note (Edit Note once it has one), Share with its
--- channels as a submenu (grayed until the share line exists, plan Task 4.2, and on sample fights),
--- Compare With This Fight (grayed on the selected fight itself), and Delete behind its confirmation.
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
    maxLetters   = 200,
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
    if selected == id then selected = nil end
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

--- Store a fight's note (trimmed, at most Recorder.NOTE_MAX characters) and answer what was stored.
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
        selected, pick = nil, nil
        if ui then ui.list:SampleView(Source.IsMock()) end
    end
    if windowShown() then
        applySampleMarker()
        render()
    end
end

--- The lifecycle's stand-down: the window hides (it decides not to show while stood down).
function Results.Suspend()
    hideWindow()
end

--- The stand-up: back on screen if the player had it open.
function Results.Resume()
    Results.Refresh()
end

--- What the window is doing, for the diagnostics report.
function Results.Diagnose()
    return { shown = Results.IsShown(), selected = selected or "none", rows = ui and ui.list:Count() or 0 }
end

--- The built window, for the suites (nil until first shown).
function Results.__ui() return ui end

-- ── the store, heard on the bus ─────────────────────────────────────────────────────────────────

-- A hidden window draws nothing: its next show redraws in full.
local function onStoreChanged()
    if windowShown() then render() end
end

-- A profile change takes the new profile's view whether the window is up or not (a hidden list keeps
-- its filters for its next show).
local function onSettings(path)
    if path == "profile" and ui then
        ui.list:ApplyView(NS.ResultsFights.SavedView())
        if windowShown() then render() end
        return
    end
    if path == "history.days" and windowShown() then footer() end
end

do
    local bus = NS.NewBusTarget()
    if bus then
        bus:RegisterMessage(NS.MSG.FIGHT_SAVED, onStoreChanged)
        bus:RegisterMessage(NS.MSG.FIGHTS_CHANGED, onStoreChanged)
        bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path) onSettings(path) end)
    end
end
