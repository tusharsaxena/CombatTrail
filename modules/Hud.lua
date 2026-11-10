local _, NS = ...
-- modules/Hud.lua — the DPS HUD's shell (spec §6, plan Task 3.1): the window, its title bar and
-- footer, which body shows for the fight on screen, when it opens and when it fades. The two bodies
-- are modules/Hud_States.lua. Adapted from DPS Race @045f479 (modules/Hud.lua) without its race: no
-- arm, buzzer, countdown, auto-arm, race length or dummy auto-show; the fight is modules/Fight.lua's.
--
-- THE STATES. Hud.State() answers "hidden" while the window is not up, else "live" for the fight in
-- progress ("noBest" when there is nothing to pace it against: no stored fight on its board, or
-- `hud.paceAgainst` "none"), or "over" for the fight-over card, whose view carries `newBest` (with
-- its `delta`), `saved` and `skipReason` from the recorder's FIGHT_SAVED / FIGHT_SKIPPED.
--
-- WHEN IT OPENS (`hud.show`). "auto" (default): on the first hit of every fight (FIGHT_TICK after the
-- fight's firstHitT is set; the Master controls' `general.hudInCombat` off turns this off), and
-- `hud.instancesOnly` keeps it shut outside an instance. It fades `hud.fadeAfter` seconds after the
-- fight ends (0 keeps the card up), held while the pointer is over it (`hud.holdOnMouse`) and never
-- while pinned (Hud.Pin). "always": up at login and after a stand-up, and never fades. "toggle":
-- only the player opens it. A HUD the player opened (Show, the toggle, the launcher, `/kct hud`) never
-- fades; one the player closed stays closed for the rest of that fight. `hud.overCard` off closes an
-- auto-opened HUD when its fight ends instead of showing the card.
--
-- WHAT RUNS, AND WHEN. Nothing is registered with the client: the HUD hears the bus (FIGHT_STARTED,
-- FIGHT_TICK, FIGHT_ENDED, FIGHT_SAVED, FIGHT_SKIPPED, SETTINGS_CHANGED) on its own target. While a
-- fight is live and the window is up, each FIGHT_TICK (4 Hz, combat only) reads NS.Meter.ReadLive
-- once and redraws; nothing else polls, and no OnUpdate is ever set. The fade is one AceTimer on the
-- addon object, so the stand-down's CancelAllTimers takes it, and Suspend drops it too.
--
-- NO DECISION FROM A METER VALUE. The live figures are opaque handles copied into labels
-- (modules/Hud_States.lua); every decision here comes from GetTime(), the fight's plain stamps, the
-- plain after-combat read and the stored records.
--
-- THE WINDOW is a plain, non-secure frame (standalone-windows): skinned through NS.ApplySkin, closed
-- through NS.MakeCloseButton, in UISpecialFrames, clamped, toplevel in the MEDIUM tier
-- (LAYERS.STRATA.HUD). Its width is `hud.width` and its height the body's stack, so it has no resize
-- grip; its scale is `hud.scale`; its place is `hud.position`, written by the title bar's drag (not
-- while `general.locked`) and put back by Master controls' Reset position. Built on first show.

local Hud = {}
NS.Hud = Hud

local L = NS.L
local Perf = NS.Perf
local Secrets = NS.Secrets

Hud.STATE = { HIDDEN = "hidden", LIVE = "live", OVER = "over", NO_BEST = "noBest" }
Hud.FRAME_NAME = "CombatTrailHud"
Hud.MIN_WIDTH = 220
-- Seconds the card stays after the pointer leaves it, once the pointer held it past its fade (and
-- how often a held card looks again whether the pointer is still on it).
Hud.LEAVE_DELAY = 2

local STATE = Hud.STATE
local HEADER_H, FOOTER_H, PAD = NS.Style.TITLE_BAR_H, 20, 10
local CONTENT_TOP = HEADER_H + 8
local CONTENT_BOTTOM = FOOTER_H + 6

local ui                         -- the built window
local wanted = false             -- the window should be up
local byPlayer = false           -- the player opened it: it never fades
local pinned = false             -- held open (Hud.Pin)
local locked = false             -- general.locked: no drag
local hiding = false             -- the addon is hiding the frame itself
local hovering = false           -- the pointer is over the frame
local key                        -- the body on screen: nil (no fight yet) | "live" | "over"
local cur                        -- the fight the body shows
local pending                    -- a fight that started and has not hit yet
local view = {}                  -- the facts about `cur` the bodies draw
local live                       -- the last NS.Meter.ReadLive of `cur` (opaque)
local dismissed                  -- the id of the fight the player closed the window on
local fadeAt, fadeTimer, held    -- the fade's deadline, its timer, held by the pointer

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Hud", fmt, ...) end
end

local function isDown()
    return NS.IsStoodDown ~= nil and NS.IsStoodDown()
end

-- ── settings ────────────────────────────────────────────────────────────────────────────────────

-- The shipped default for a profile path: defaults/Profile.lua is the only place a default is
-- written (savedvariables-§2), so no literal fallback lives here.
local function shipped(path)
    local node = NS.defaults and NS.defaults.profile
    for part in path:gmatch("[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

-- A profile value by path, read straight off the profile (the hud.* rows arrive with the DPS HUD
-- page, plan Task 3.3), else its shipped default.
local function setting(path)
    local node = NS.db and NS.db.profile
    for part in path:gmatch("[^.]+") do
        if type(node) ~= "table" then node = nil break end
        node = node[part]
    end
    if node == nil then return shipped(path) end
    return node
end
Hud.Setting = setting

local function position()
    local hud = NS.db and NS.db.profile and NS.db.profile.hud
    if type(hud) ~= "table" then return nil end
    if type(hud.position) ~= "table" then hud.position = {} end
    return hud.position
end

-- ── what the HUD knows about the fight ──────────────────────────────────────────────────────────

local function inInstance()
    if type(IsInInstance) ~= "function" then return false end
    local ok, inside = pcall(IsInInstance)
    return ok and Secrets.PlainTruth(inside) == true
end

--- Whether the HUD may open itself for `fight` now (the show mode, the master row, instancesOnly,
--- and the player's close on this fight).
local function autoAllowed(fight)
    local mode = setting("hud.show")
    if mode == "toggle" then return false end
    if mode ~= "always" and setting("general.hudInCombat") == false then return false end
    if setting("hud.instancesOnly") == true and not inInstance() then return false end
    if fight and dismissed ~= nil and dismissed == fight.id then return false end
    return true
end

local function identityOf(fight)
    local ok, ident = pcall(NS.Identity.Resolve, fight, nil, nil)
    if ok and type(ident) == "table" then return ident end
    return {}
end

-- The board's newest stored fight, for `hud.paceAgainst` "last".
local function lastOnBoard(probe)
    local boardKey = NS.Bests.Key(probe)
    if not boardKey then return nil end
    for _, r in ipairs(NS.Recorder.List()) do
        if r.status == "final" and NS.Bests.Key(r) == boardKey then return r end
    end
    return nil
end

--- The stored fight the live fight is paced against (`hud.paceAgainst`): its board's best, its
--- board's newest fight, or nil (none, an unknown target, a board with nothing on it).
--- @param fight table
--- @param ident table|nil  the fight's identity (Identity.Resolve), read when nil
--- @return table|nil record
function Hud.PaceRecord(fight, ident)
    local against = setting("hud.paceAgainst")
    if against == "none" or type(fight) ~= "table" then return nil end
    ident = ident or identityOf(fight)
    local snap = type(fight.snapshot) == "table" and fight.snapshot or {}
    local probe = { who = snap.who, boardKey = NS.Identity.BoardKey(ident), identity = ident, status = "final" }
    if against == "last" then return lastOnBoard(probe) end
    return NS.Bests.For(probe)
end

-- "<boss or target> · <instance> · <difficulty>", plain strings only.
local function targetLine(ident)
    local parts = {}
    local name = Secrets.PlainString(ident.encounterName) or Secrets.PlainString(ident.targetName)
    for _, s in ipairs({ name, Secrets.PlainString(ident.instanceName), Secrets.PlainString(ident.difficultyName) }) do
        if s and s ~= "" then parts[#parts + 1] = s end
    end
    return table.concat(parts, " \194\183 ")
end

local function newView(fight)
    local ident = identityOf(fight)
    return { fight = fight, ident = ident, targetLine = targetLine(ident), pace = Hud.PaceRecord(fight, ident) }
end

-- The over card's best: is the saved fight its board's best now, and by how much over the one before.
local function judge(record)
    NS.Bests.Invalidate()   -- the bus keeps no order between receivers: the board must hold `record`
    view.newBest = NS.Bests.IsBest(record) and true or false
    view.delta = nil
    if not view.newBest then return end
    local before = NS.Bests.For(record, true)
    local a, b = record.dps, before and before.dps
    if type(a) == "number" and type(b) == "number" and b > 0 then view.delta = (a - b) * 100 / b end
end

-- ── the fade ────────────────────────────────────────────────────────────────────────────────────

local function cancelFade()
    if fadeTimer and NS.addon and NS.addon.CancelTimer then NS.addon:CancelTimer(fadeTimer) end
    fadeTimer, fadeAt, held = nil, nil, false
end

local function canFade()
    return wanted and not byPlayer and not pinned and setting("hud.show") ~= "always"
end

local fadeCheck

local function schedule(delay)
    if not (NS.addon and NS.addon.ScheduleTimer) then return end
    fadeTimer = NS.addon:ScheduleTimer(function() fadeCheck() end, math.max(0.05, delay))
end

-- Start the fade `delay` seconds from now (default `hud.fadeAfter`; 0 or less: no fade).
local function startFade(delay)
    cancelFade()
    if not canFade() then return end
    local after = delay or tonumber(setting("hud.fadeAfter")) or 0
    if after <= 0 then return end
    fadeAt = GetTime() + after
    schedule(after)
end

local function mouseOver()
    if hovering then return true end
    local f = ui and ui.frame
    if not (f and f.IsMouseOver) then return false end
    local ok, over = pcall(f.IsMouseOver, f)
    return ok and over == true
end

-- ── the window ──────────────────────────────────────────────────────────────────────────────────

local function windowShown()
    return ui ~= nil and ui.frame:IsShown() == true
end

local function width()
    return math.max(Hud.MIN_WIDTH, tonumber(setting("hud.width")) or Hud.MIN_WIDTH)
end

local function applyPlacement()
    local f, p = ui.frame, position() or {}
    local d = shipped("hud.position") or {}
    f:ClearAllPoints()
    f:SetPoint(p.point or d.point or "CENTER", UIParent, p.relPoint or d.relPoint or "CENTER",
        tonumber(p.x) or d.x or 0, tonumber(p.y) or d.y or 0)
    f:SetScale(tonumber(setting("hud.scale")) or 1)
end

-- The shell frame never displays a meter value (only its descendants do), so its own anchor is
-- read back here, the one geometry read in the HUD.
local function savePosition()
    local p = position()
    if not (p and ui) then return end
    local point, _, relPoint, x, y = ui.frame:GetPoint(1)
    if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return end
    p.point, p.relPoint = point, type(relPoint) == "string" and relPoint or point
    p.x, p.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

local Act = {}
Hud.Act = Act

-- The title band: the title LEFT, the four controls on the right (close outermost), each the catalog's.
local function buildHeader(f)
    local Style = NS.Style
    f.title = f:CreateFontString(nil, "OVERLAY", Style.FONT.TITLE)
    f.title:SetText(L["Combat Trail"])
    ui.controls = Style.NewStrip()
    ui.close = NS.MakeCloseButton(f, function() Act.close() end)
    ui.lock = Style.ControlButton(f, "unlock", "U", L["Lock or unlock the HUD"], function() Act.lock() end)
    ui.settings = Style.ControlButton(f, "settings", "S", L["Settings"], function() Act.settings() end)
    ui.results = Style.ControlButton(f, "chart", "R", L["Results"], function() Act.results() end)
    for _, b in ipairs({ ui.lock, ui.settings, ui.results }) do Style.AddToStrip(ui.controls, b) end
    local drag = CreateFrame("Frame", nil, f)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() if not locked then f:StartMoving() end end)
    drag:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        savePosition()
    end)
    ui.drag = drag
    Style.Header(f, { title = f.title, align = "LEFT", drag = drag,
        right = { ui.close, ui.lock, ui.settings, ui.results }, n = 4 })
end

local function buildFooter(f)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    NS.Skin.Divider(line)
    line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, FOOTER_H)
    line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, FOOTER_H)
    ui.footLeft = NS.Style.Text(f, NS.Style.FONT.CAPTION)
    ui.footLeft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 5)
    ui.footRight = NS.Style.Text(f, NS.Style.FONT.CAPTION, nil, "RIGHT")
    ui.footRight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 5)
end

local onHide

local function hookPointer(f)
    f:SetScript("OnEnter", function() hovering = true end)
    f:SetScript("OnLeave", function()
        hovering = false
        if held then
            held = false
            startFade(Hud.LEAVE_DELAY)
        end
    end)
end

local function ensureWindow()
    if ui then return ui end
    local f = CreateFrame("Frame", Hud.FRAME_NAME, UIParent, "BackdropTemplate")
    ui = { frame = f, body = {} }
    f:Hide()
    f:SetFrameStrata(NS.Constants.LAYERS.STRATA.HUD)
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    buildHeader(f)
    buildFooter(f)
    ui.content = CreateFrame("Frame", nil, f)
    ui.content:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -CONTENT_TOP)
    ui.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, CONTENT_BOTTOM)
    NS.ApplySkin(f)
    f:SetScript("OnHide", function() onHide() end)
    hookPointer(f)
    -- Escape closes it with the standard close stack (standalone-windows).
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Hud.FRAME_NAME) end
    applyPlacement()
    debug("window built")
    return ui
end

local function applyLock()
    NS.Style.SetControlIcon(ui.lock, locked and "lock" or "unlock", locked and "L" or "U")
end

local function showBody(which)
    local body = ui.body[which]
    if not body then
        body = NS.HudStates.Build(which, ui.content)
        ui.body[which] = body
    end
    if ui.current ~= which then
        local old = ui.current and ui.body[ui.current]
        if old then old.frame:Hide() end
        ui.current = which
    end
    body.frame:Show()
    return body
end

-- ── the view ────────────────────────────────────────────────────────────────────────────────────

-- The clock: from the first hit (plain GetTime()), or the fight's length once it is over.
local function clockOf()
    local fight = cur
    if not fight then return 0 end
    local first = fight.firstHitT or fight.startT
    if key == "over" then
        local final = view.final
        local d = final and Secrets.PlainNumber(final.duration)
        if d then return d end
        local stop = fight.closedT or fight.combatEndT or GetTime()
        return math.max(0, stop - (first or stop))
    end
    if type(first) ~= "number" then return 0 end
    return math.max(0, GetTime() - first)
end

local function hasPet()
    if key == "over" then
        local pet = view.final and view.final.pet
        return type(pet) == "table" and Secrets.PlainNumber(pet.total) ~= nil
    end
    return type(live) == "table" and live.pet ~= nil
end

-- The view the bodies draw: the fight's facts plus this moment's settings and figures.
local function fill()
    local v = view
    v.key = key or "live"
    v.live = live
    v.layout = setting("hud.layout") or {}
    v.clock = clockOf()
    v.hasPet = hasPet()
    v.width = width() - 2 * PAD
    v.showSkipReason = setting("hud.showSkipReason") ~= false
    v.minLength = setting("history.minLength")
    return v
end

local function footer(v)
    local snap = cur and cur.snapshot
    local who = type(snap) == "table" and snap.who or {}
    local parts = {}
    for _, s in ipairs({ Secrets.PlainString(who.specName), Secrets.PlainString(who.name) }) do
        if s then parts[#parts + 1] = s end
    end
    ui.footLeft:SetText(table.concat(parts, " \194\183 "))
    local right = ""
    if v.key == "live" and cur then right = L["live \194\183 4 Hz"] end
    if v.key == "over" then
        if pinned then right = L["Pinned open"]
        elseif fadeAt and not held then right = L["Fades %d s after the fight"]:format(tonumber(setting("hud.fadeAfter")) or 0) end
    end
    ui.footRight:SetText(right)
end

local function render()
    local v = fill()
    local body = showBody(v.key)
    body:Update(v)
    ui.frame:SetSize(width(), CONTENT_TOP + (body.height or 0) + CONTENT_BOTTOM)
    footer(v)
    return v
end

local function hideWindow()
    if windowShown() then
        hiding = true
        ui.frame:Hide()
        hiding = false
    end
end

-- The frame went away by Escape or the close control: the player closed it. A frame still shown in
-- its own right was hidden with its parent (the interface hidden, a cinematic), which is not.
function onHide()
    if hiding or (ui and ui.frame:IsShown()) then return end
    wanted, byPlayer, pinned, hovering = false, false, false, false
    cancelFade()
    if cur then dismissed = cur.id end
end

-- ── the public surface ──────────────────────────────────────────────────────────────────────────

--- Whether the HUD decides to be up: wanted, and the addon standing.
function Hud.IsShown()
    return wanted and not isDown()
end

--- The HUD's state (Hud.STATE): hidden, live, noBest or over.
--- @return string
function Hud.State()
    if not Hud.IsShown() then return STATE.HIDDEN end
    if key == "over" then return STATE.OVER end
    if key == "live" and cur and view.pace == nil then return STATE.NO_BEST end
    return STATE.LIVE
end

--- Re-decide and redraw. The one place the frame follows the decision.
function Hud.Refresh()
    locked = setting("general.locked") == true
    if not Hud.IsShown() then return hideWindow() end
    ensureWindow()
    applyLock()
    applyPlacement()
    render()
    if not windowShown() then ui.frame:Show() end
end

--- Open the window. `reason` "auto" is the addon's own opening, which fades after the fight; any
--- other (the player's: the toggle, the verb, the launcher) never fades.
--- @param reason string|nil
function Hud.Show(reason)
    wanted = true
    byPlayer = reason ~= "auto"
    if byPlayer then cancelFade() end
    Hud.Refresh()
end

--- Close the window (the player's close): it stays closed for the rest of the fight on screen.
function Hud.Hide()
    wanted, byPlayer, pinned = false, false, false
    cancelFade()
    if cur then dismissed = cur.id end
    Hud.Refresh()
end

function Hud.Toggle()
    if Hud.IsShown() then Hud.Hide() else Hud.Show() end
end

--- Pin the window open (it never fades), or let it go (an over card starts its fade again).
--- @param on boolean
function Hud.Pin(on)
    pinned = on == true
    if pinned then
        cancelFade()
        wanted = true
    elseif key == "over" then
        startFade()
    end
    Hud.Refresh()
end

function Hud.IsPinned() return pinned end

--- The Locked row's reaction: no drag while locked.
function Hud.SetLocked(on)
    locked = on == true
    if ui then applyLock() end
end

function Hud.IsLocked() return locked end

--- Back to the default place (the Master controls' Reset position).
function Hud.ResetPosition()
    local p, d = position(), shipped("hud.position")
    if p and type(d) == "table" then
        for k in pairs(p) do p[k] = nil end
        for k, v in pairs(d) do p[k] = v end
    end
    if ui then applyPlacement() end
end

--- The view the bodies draw now, for the suites and the parts that stack under it (plan Task 3.2).
function Hud.View() return view end

--- The over card's chip texts on screen, in order (the suites read these).
function Hud.Chips()
    local body = ui and ui.body.over
    if not body then return {} end
    return body.w.chips:Texts()
end

--- When the fade will close the window (GetTime() seconds), or nil while none runs.
function Hud.FadeAt() return fadeAt end

--- The lifecycle's stand-down: the window hides, the fade goes, the fight on screen is dropped. A
--- window the addon opened is let go; one the player opened comes back at the stand-up.
function Hud.Suspend()
    cancelFade()
    if not byPlayer then wanted, pinned = false, false end
    cur, pending, key, view, live, hovering = nil, nil, nil, {}, nil, false
    hideWindow()
end

--- The login and the stand-up (core/CombatTrail.lua NS.RegisterGameEvents): "always" opens it.
function Hud.Sync()
    if setting("hud.show") == "always" then wanted = true end
    Hud.Refresh()
end

Hud.Resume = Hud.Sync

-- ── the fight, heard on the bus ─────────────────────────────────────────────────────────────────

local function readLive()
    local fight = cur
    local sessions = fight.sessions
    local id = (type(sessions) == "table" and sessions[#sessions]) or fight.sessionID
    live = NS.Meter.ReadLive(id)
end

-- The first hit: the fight goes on screen (opening the window when the mode allows it).
local function goLive(fight)
    pending, cur, key, live, dismissed = nil, fight, "live", nil, nil
    view = newView(fight)
    cancelFade()
    if not (byPlayer or pinned) then wanted = autoAllowed(fight) end
    debug("fight %s live (pace %s)", tostring(fight.id), view.pace and tostring(view.pace.id) or "none")
    if Hud.IsShown() then readLive() end
    Hud.Refresh()
end

function Hud.OnFightStarted(fight)
    if isDown() or type(fight) ~= "table" then return end
    pending = fight
    -- The last fight's card stays until this one's first hit, and stops fading meanwhile.
    cancelFade()
    if fight.firstHitT then goLive(fight) end
end

function Hud.OnFightTick(fight)
    if isDown() or type(fight) ~= "table" then return end
    if fight == pending then
        if fight.firstHitT then goLive(fight) end
        return
    end
    if fight ~= cur or key ~= "live" or not windowShown() then return end
    local t0 = Perf.on and debugprofilestop()
    readLive()
    render()
    if t0 then Perf.Note("hud", debugprofilestop() - t0) end
end

local function closesWithFight()
    return setting("hud.overCard") == false and not (byPlayer or pinned) and setting("hud.show") ~= "always"
end

function Hud.OnFightEnded(fight, final, reason)
    if isDown() then return end
    if fight == pending then
        -- A fight with no hit never reached the screen: the card still up may fade now.
        pending = nil
        if key == "over" then startFade() end
        return
    end
    if fight ~= cur then return end
    key = "over"
    view.final = type(final) == "table" and final or nil
    view.lost = reason ~= "final"
    view.endedAt = GetTime()
    if closesWithFight() then wanted = false end
    startFade()
    Hud.Refresh()
end

function Hud.OnFightSaved(record)
    if isDown() or type(record) ~= "table" or not cur or cur.recordID ~= record.id then return end
    view.saved, view.skipReason, view.record = true, nil, record
    -- The stored identity names the meter's primary target, which the live line could only guess.
    if type(record.identity) == "table" then view.targetLine = targetLine(record.identity) end
    judge(record)
    if key == "over" then Hud.Refresh() end
end

function Hud.OnFightSkipped(fight, reason)
    if isDown() or fight ~= cur then return end
    view.saved, view.skipReason = false, reason
    if key == "over" then Hud.Refresh() end
end

local function onSettings(path, value)
    if type(path) ~= "string" then return end
    if path == "hud.show" and value == "always" then wanted = true end
    if path == "profile" or path:find("^hud%.") then Hud.Refresh() end
end

do
    local bus = NS.NewBusTarget()
    if bus then
        bus:RegisterMessage(NS.MSG.FIGHT_STARTED, function(_, fight) Hud.OnFightStarted(fight) end)
        bus:RegisterMessage(NS.MSG.FIGHT_TICK, function(_, fight) Hud.OnFightTick(fight) end)
        bus:RegisterMessage(NS.MSG.FIGHT_ENDED, function(_, fight, final, reason) Hud.OnFightEnded(fight, final, reason) end)
        bus:RegisterMessage(NS.MSG.FIGHT_SAVED, function(_, record) Hud.OnFightSaved(record) end)
        bus:RegisterMessage(NS.MSG.FIGHT_SKIPPED, function(_, fight, reason) Hud.OnFightSkipped(fight, reason) end)
        bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path, value) onSettings(path, value) end)
    end
end

-- ── the fade's check ────────────────────────────────────────────────────────────────────────────

function fadeCheck()
    fadeTimer = nil
    if not fadeAt or isDown() then return end
    local left = fadeAt - GetTime()
    if left > 0 then return schedule(left) end
    if setting("hud.holdOnMouse") ~= false and mouseOver() then
        -- Held: look again a moment later rather than wait for the frame's OnLeave, which never
        -- comes when the pointer leaves from a child (a chip, a title-bar control) that took it.
        held = true
        fadeAt = GetTime() + Hud.LEAVE_DELAY
        return schedule(Hud.LEAVE_DELAY)
    end
    fadeAt = nil
    wanted = false
    debug("faded")
    Hud.Refresh()
end

-- ── the title bar's acts and the verb ───────────────────────────────────────────────────────────

function Act.close()
    if windowShown() then ui.frame:Hide() end
    if wanted then onHide() end
end

function Act.lock() return NS.ToggleLock() end
function Act.settings() return NS.OpenSettings() end

--- The chart control: the fight on the card in the Results window, else the window itself.
function Act.results()
    local R = NS.Results
    local record = key == "over" and view.record or nil
    if R and record and type(R.ShowFight) == "function" then return R.ShowFight(record.id) end
    if R and type(R.Toggle) == "function" then return R.Toggle() end
    NS.Print(L["That part of Combat Trail is not built yet."])
end

local VERBS = {
    show = function() Hud.Show() end,
    hide = function() Hud.Hide() end,
    toggle = function() Hud.Toggle() end,
    pin = function() Hud.Pin(true) end,
    unpin = function() Hud.Pin(false) end,
}

--- `/kct hud show|hide|toggle|pin|unpin`.
function Hud.OnVerb(rest)
    local word = tostring(rest or ""):match("^%s*(%S*)"):lower()
    local fn = VERBS[word]
    if fn then return fn() end
    NS.Print(L["Usage: /kct hud show, hide, toggle, pin or unpin"])
end

--- What the HUD is doing, for the diagnostics report.
function Hud.Diagnose()
    return { state = Hud.State(), body = ui and ui.current or "none", pinned = pinned, byPlayer = byPlayer,
             locked = locked, fadeAt = fadeAt }
end

--- The HUD's window, or nil before it is first built.
function Hud.Frame() return ui and ui.frame or nil end

--- The built window and its bodies, for the suites (nil until first shown).
function Hud.__ui() return ui end
