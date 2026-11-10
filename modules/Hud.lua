local _, NS = ...
-- modules/Hud.lua — the DPS HUD's shell (spec §6, plan Tasks 3.1 and 3.2): the window, its title bar
-- and footer, which body shows for the fight on screen, when it opens and when it fades, and the view
-- the bodies draw (the figures, the pace bar's range, the damage chart's columns, the spell rows).
-- The two bodies are modules/Hud_States.lua; the pace data modules/Hud_Best.lua, the chart and the
-- pace bar modules/Hud_Chart.lua, the rows modules/Hud_Breakdown.lua, the look
-- modules/Hud_Appearance.lua and the tooltips' words modules/Hud_Tips.lua. Adapted from DPS Race @045f479 (modules/Hud.lua) without its race: no
-- arm, buzzer, countdown, auto-arm, race length or dummy auto-show; the fight is modules/Fight.lua's.
--
-- THE STATES. Hud.State() answers "hidden" while the window is not up, else "live" for the fight in
-- progress ("noBest" when there is nothing to pace it against: no stored fight on its board, or
-- `hud.paceAgainst` "none"), or "over" for the fight-over card, whose view carries `newBest` (with
-- its `delta`), `saved` and `skipReason` from the recorder's FIGHT_SAVED / FIGHT_SKIPPED.
--
-- WHEN IT OPENS (`hud.show`). "auto" (default): on the first hit of every fight (FIGHT_TICK after the
-- fight's firstHitT is set; the Master controls' `general.hudInCombat` off turns this off), and
-- `hud.instancesOnly` keeps it shut outside an instance; both apply to "auto" only. It fades
-- `hud.fadeAfter` seconds after the fight ends (0 keeps the card up), held while the pointer is over
-- it (`hud.holdOnMouse`) and never while pinned (Hud.Pin). "always": up at login and after a
-- stand-up, in or out of an instance, and never fades. "toggle":
-- only the player opens it. A HUD the player opened (Show, the toggle, the launcher, `/ct hud`) never
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
-- THE PACE (spec §6 and §12). The pace record's curve (HudBest.Curve) is read once when the fight goes
-- live; each redraw sets the fight's live totals against it at the clock's time (from the first hit):
-- the player's total on the bar's player fill, the pet's on the pet fill anchored to it, against the
-- best's merged pace. Hud.PACE_PET_FILL is the seam (one place, spec §10): false, and the pet fill
-- hides and the player's total is set against the best's player damage alone. The over card draws
-- the same bar from the plain after-combat read at the fight's length.
--
-- THE WINDOW is a plain, non-secure frame (standalone-windows): skinned through NS.ApplySkin, closed
-- through NS.MakeCloseButton, in UISpecialFrames, clamped, toplevel in the MEDIUM tier
-- (LAYERS.STRATA.HUD, or `hud.window.strata`). Its width is `hud.width`; its scale is `hud.scale`, its
-- opacity `hud.window.alpha`; its title bar and footer follow `hud.window.titleBar` and `footer`; its
-- place is `hud.position`, written by the title bar's drag (not while `general.locked`) and put back
-- by Master controls' Reset position. Built on first show.
--
-- ITS SIZE (v0.2 Task B3, plan decisions D2 and D9) is `hud.sizeMode`'s:
--   "fixed" (default)  the height is Hud.FixedHeight(): the chrome plus HudStates.FixedStack, the stack
--                      every configured part takes with `hud.bars` spell rows, worked out from the
--                      configuration alone, so the window is the same whatever the fight holds. The
--                      library's grip (modules/Sizing.lua) sizes it, shown only in this mode and not
--                      while locked: while it is held the bodies lay out at the dragged size with as
--                      many rows as fit, and the release stores `hud.width` (MIN_WIDTH-MAX_WIDTH) and
--                      `hud.bars`, the whole rows the height holds (MIN_BARS-MAX_BARS), and the window
--                      snaps to them.
--   "auto"             the height is the body's stack, growing with the rows up to `hud.bars`;
--                      `hud.grow` picks the edge that stays put ("down": the top, "up": the bottom).
-- In both, spells past the rows scroll with the wheel (modules/Hud_States.lua). The edge holds because
-- the stored anchor is on it: a drag of the title bar or the grip, a change of the mode or the edge,
-- and any Refresh that finds the stored point off the edge (an edge chosen before the window was
-- built, a profile switch) re-anchor the window (normalizeAnchor) to TOPLEFT ("down", and fixed mode,
-- whose grip keeps the top left) or BOTTOMLEFT ("up") on UIParent's BOTTOMLEFT, from the shell
-- frame's own edges.
--
-- A SAMPLE FIGHT (test mode and the sim, modules/Preview.lua and modules/Sim.lua) comes to the same
-- receivers, handed over directly rather than on the bus, flagged `sample`. Its live and cast reads
-- come from its plan (modules/MockFights.lua), never the meter or the cast list; it is paced and
-- judged against the sample history (modules/Results_Source.lua); it opens the window whatever the
-- show mode, never fades, and a `frozen` one holds its clock at that many seconds. The window says
-- so with the library's strip under the title bar (the sim's while a sim runs), and EndSample drops
-- it.

local Hud = {}
NS.Hud = Hud

local L = NS.L
local Perf = NS.Perf
local Secrets = NS.Secrets

Hud.STATE = { HIDDEN = "hidden", LIVE = "live", OVER = "over", NO_BEST = "noBest" }
--- The pace bar's pet-fill seam (spec §12): true draws the pet's live total on from the end of the
--- player's fill against the best's merged pace; false is the fallback, player-only against the
--- best's player damage, if the anchoring does not hold up in game.
Hud.PACE_PET_FILL = true
-- Seconds between two reads of the fight's casts for the chart's cooldown icons.
Hud.CAST_READ = 1
Hud.FRAME_NAME = "CombatTrailHud"
Hud.MIN_WIDTH = 260   -- DPS Race's, and the default `hud.width` (v0.2 Task B2)
Hud.MAX_WIDTH = 600   -- the width row's and the grip's
Hud.MIN_BARS, Hud.MAX_BARS = 1, 15   -- the spell rows `hud.bars` holds (v0.2 Task B3)
-- Seconds the card stays after the pointer leaves it, once the pointer held it past its fade (and
-- how often a held card looks again whether the pointer is still on it).
Hud.LEAVE_DELAY = 2

local STATE = Hud.STATE
-- DPS Race's insets: PAD at the sides, the content 10 under the title bar and 8 over the footer.
local HEADER_H, FOOTER_H, PAD = NS.Style.TITLE_BAR_H, 20, 12

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

-- A profile value by path, read straight off the profile, else its shipped default. Every `hud.*`
-- key has its row on the DPS HUD page (settings/Hud.lua), which writes through the seam; the read
-- stays direct because it runs many times on every 4 Hz draw, where a schema lookup per key would
-- cost a row search each.
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

--- Whether the player closed the HUD on `fight`.
local function closedOn(fight)
    return fight ~= nil and dismissed ~= nil and dismissed == fight.id
end

--- Whether the HUD may open itself for `fight` now (the show mode, the master row, instancesOnly,
--- and the player's close on this fight). "always" answers before the master row and instancesOnly,
--- which govern "auto" only (plan decision D4): only the player's close on this fight holds it.
local function autoAllowed(fight)
    local mode = setting("hud.show")
    if mode == "toggle" then return false end
    if mode == "always" then return not closedOn(fight) end
    if setting("general.hudInCombat") == false then return false end
    if setting("hud.instancesOnly") == true and not inInstance() then return false end
    return not closedOn(fight)
end

local function identityOf(fight)
    local ok, ident = pcall(NS.Identity.Resolve, fight, nil, nil)
    if ok and type(ident) == "table" then return ident end
    return {}
end

-- The board's newest fight in `list` (newest first), for `hud.paceAgainst` "last".
local function lastOnBoard(probe, list)
    local boardKey = NS.Bests.Key(probe)
    if not boardKey then return nil end
    for _, r in ipairs(list) do
        if r.status == "final" and NS.Bests.Key(r) == boardKey then return r end
    end
    return nil
end

--- The stored fight the live fight is paced against (`hud.paceAgainst`): its board's best, its
--- board's newest fight, or nil (none, an unknown target, a board with nothing on it). A sample
--- fight is paced against the sample history.
--- @param fight table
--- @param ident table|nil  the fight's identity (Identity.Resolve), read when nil
--- @return table|nil record
function Hud.PaceRecord(fight, ident)
    local against = setting("hud.paceAgainst")
    if against == "none" or type(fight) ~= "table" then return nil end
    ident = ident or identityOf(fight)
    local snap = type(fight.snapshot) == "table" and fight.snapshot or {}
    local probe = { who = snap.who, boardKey = NS.Identity.BoardKey(ident), identity = ident, status = "final" }
    if fight.sample then
        local Source = NS.ResultsSource
        if against == "last" then return lastOnBoard(probe, Source.All()) end
        return Source.BestFor(probe)
    end
    if against == "last" then return lastOnBoard(probe, NS.Recorder.List()) end
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
    local pace = Hud.PaceRecord(fight, ident)
    return { fight = fight, ident = ident, targetLine = targetLine(ident), pace = pace,
             curve = pace and NS.HudBest.Curve(pace.id, pace) or nil }
end

-- The over card's best: is the saved fight its board's best now, and by how much over the one before.
-- A sample record is judged against the sample history.
local function judge(record)
    NS.Bests.Invalidate()   -- the bus keeps no order between receivers: the board must hold `record`
    local isBest, bestFor = NS.Bests.IsBest, NS.Bests.For
    if record.sample then isBest, bestFor = NS.ResultsSource.IsBest, NS.ResultsSource.BestFor end
    view.newBest = isBest(record) and true or false
    view.delta = nil
    if not view.newBest then return end
    local before = bestFor(record, true)
    local a, b = record.dps, before and before.dps
    if type(a) == "number" and type(b) == "number" and b > 0 then view.delta = (a - b) * 100 / b end
end

-- ── the fade ────────────────────────────────────────────────────────────────────────────────────

local function cancelFade()
    if fadeTimer and NS.addon and NS.addon.CancelTimer then NS.addon:CancelTimer(fadeTimer) end
    fadeTimer, fadeAt, held = nil, nil, false
end

local function canFade()
    return wanted and not byPlayer and not pinned and setting("hud.show") ~= "always" and not (cur and cur.sample)
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

-- The content's insets from the window's top and bottom: the title bar's and the footer's, each
-- only while shown (`hud.window.titleBar`, `hud.window.footer`).
local function stripHeight() return ui and ui.stripMode and ui.stripShown and NS.TEST_STRIP_HEIGHT or 0 end
local function contentTop() return (setting("hud.window.titleBar") ~= false and HEADER_H + 10 or PAD) + stripHeight() end
local function contentBottom() return setting("hud.window.footer") ~= false and FOOTER_H + 8 or PAD end

-- ── the size (v0.2 Task B3) ──────────────────────────────────────────────────────────────────

local function fixedMode() return setting("hud.sizeMode") ~= "auto" end

local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

--- The spell rows `hud.bars` asks for, whole and in range.
local function bars()
    return clamp(math.floor(tonumber(setting("hud.bars")) or Hud.MIN_BARS), Hud.MIN_BARS, Hud.MAX_BARS)
end

-- The edge that stays put: "up" (the bottom) only for an auto-grow window told to grow up.
local function growEdge()
    return (not fixedMode() and setting("hud.grow") == "up") and "up" or "down"
end

local function chromeHeight() return contentTop() + contentBottom() end

-- A fixed window's height for `n` spell rows: the chrome and the stack the configuration reserves.
local function fixedHeightFor(n)
    return chromeHeight() + NS.HudStates.FixedStack(setting("hud.layout"), n, setting("hud.paceAgainst") ~= "none")
end

--- The fixed window's height for `hud.bars` rows (the window's height in fixed mode).
--- @return number
function Hud.FixedHeight() return fixedHeightFor(bars()) end

-- The whole bars a fixed window `h` high holds, in range.
local function barsFor(h)
    return clamp(NS.HudBreakdown.Capacity(h - fixedHeightFor(0)), Hud.MIN_BARS, Hud.MAX_BARS)
end

-- Whether the grip is being dragged now and has handed on a size.
local function sizing()
    return ui ~= nil and ui.dragH ~= nil and NS.Sizing.IsSizing(ui.frame)
end

local function canResize() return not locked and fixedMode() end

-- The grip shown while it may size the window (fixed mode, not locked), and its bounds: MIN_BARS to
-- MAX_BARS rows of the stack configured now.
local function applyGrip()
    local f = ui.frame
    if f.resizeGrip then f.resizeGrip:SetShown(canResize()) end
    if type(f.SetResizeBounds) == "function" then
        f:SetResizeBounds(Hud.MIN_WIDTH, fixedHeightFor(Hud.MIN_BARS), Hud.MAX_WIDTH, fixedHeightFor(Hud.MAX_BARS))
    end
end

-- ── the place ──────────────────────────────────────────────────────────────────────────────────

local function applyPlacement()
    local f, p = ui.frame, position() or {}
    local d = shipped("hud.position") or {}
    f:ClearAllPoints()
    f:SetPoint(p.point or d.point or "CENTER", UIParent, p.relPoint or d.relPoint or "CENTER",
        tonumber(p.x) or d.x or 0, tonumber(p.y) or d.y or 0)
    f:SetScale(tonumber(setting("hud.scale")) or 1)
end

-- The shell frame never displays a meter value (only its descendants do), so its own anchor and its
-- edges (GetLeft, GetTop, GetBottom) are read back here, the only geometry reads in the HUD; each
-- answer is still taken only as a plain number.
local function savePosition()
    local p = position()
    if not (p and ui) then return end
    local point, _, relPoint, x, y = ui.frame:GetPoint(1)
    if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return end
    p.point, p.relPoint = point, type(relPoint) == "string" and relPoint or point
    p.x, p.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

local function edgeOf(f, name)
    local fn = f[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, f)
    return ok and Secrets.PlainNumber(v) or nil
end

-- Whether an anchor `point` sits on the grow edge: TOP* for "down", BOTTOM* for "up".
local function onEdge(point, edge)
    return type(point) == "string" and point:find(edge == "up" and "^BOTTOM" or "^TOP") ~= nil
end

--- Re-anchor the window on its grow edge where it stands: TOPLEFT (or BOTTOMLEFT for "up") on
--- UIParent's BOTTOMLEFT at the frame's own left and top (bottom) edge, stored in `hud.position`.
--- Unless `force` (after a drag, whose anchor is the client's), a stored point already on the edge
--- is kept. Answers whether it re-anchored (false where the frame cannot say where it is).
local function normalizeAnchor(force)
    local p = position()
    if not (p and ui) then return false end
    local edge = growEdge()
    if not force and onEdge(p.point, edge) then return false end
    local f = ui.frame
    local left, y = edgeOf(f, "GetLeft"), edgeOf(f, edge == "up" and "GetBottom" or "GetTop")
    if not (left and y) then return false end
    p.point, p.relPoint = edge == "up" and "BOTTOMLEFT" or "TOPLEFT", "BOTTOMLEFT"
    p.x, p.y = math.floor(left + 0.5), math.floor(y + 0.5)
    applyPlacement()
    return true
end

-- After a drag (the title bar's or the grip's): the place stored on the grow edge, else as the
-- client left it.
local function placeAfterDrag()
    if not normalizeAnchor(true) then savePosition() end
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
        placeAfterDrag()
    end)
    ui.drag = drag
    Style.Header(f, { title = f.title, align = "LEFT", drag = drag,
        right = { ui.close, ui.lock, ui.settings, ui.results }, n = 4 })
end

local function buildFooter(f)
    local line = f:CreateTexture(nil, "ARTWORK")
    ui.footLine = line
    line:SetHeight(1)
    NS.Skin.Divider(line)
    line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, FOOTER_H)
    line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, FOOTER_H)
    ui.footLeft = NS.Style.Text(f, NS.Style.FONT.CAPTION)
    ui.footLeft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 5)
    ui.footRight = NS.Style.Text(f, NS.Style.FONT.CAPTION, nil, "RIGHT")
    ui.footRight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 5)
end

local onHide, render, resized

-- Every size change: the grip's size, in range, that a drag lays out from (plain numbers only).
local function trackSize(w, h)
    w, h = Secrets.PlainNumber(w), Secrets.PlainNumber(h)
    if w then ui.dragW = clamp(w, Hud.MIN_WIDTH, Hud.MAX_WIDTH) end
    if h then ui.dragH = clamp(h, fixedHeightFor(Hud.MIN_BARS), fixedHeightFor(Hud.MAX_BARS)) end
end

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
    NS.ApplySkin(f)
    f:SetScript("OnHide", function() onHide() end)
    hookPointer(f)
    -- Escape closes it with the standard close stack (standalone-windows).
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Hud.FRAME_NAME) end
    -- The grip (modules/Sizing.lua): while it is held each size change redraws the body at the
    -- dragged size (the 4 Hz draw, no meter read); the release stores it (resized). A size change the
    -- grip did not start is the HUD's own SetSize, already laid out, so `redraw` has nothing to do.
    NS.Sizing.MakeResizable(f, {
        minWidth = Hud.MIN_WIDTH, minHeight = fixedHeightFor(Hud.MIN_BARS),
        canResize = function() return canResize() end,
        size = trackSize, layout = function() render() end, redraw = function() end,
        done = function(w, h) resized(w, h) end,
    })
    applyPlacement()
    debug("window built")
    return ui
end

local function applyLock()
    NS.Style.SetControlIcon(ui.lock, locked and "lock" or "unlock", locked and "L" or "U")
    applyGrip()
end

-- The strip a sample fight wears: the sim's while a sim runs, else test mode's; nil before it is
-- built or with no Widgets library (the title then says it). Born hidden.
local STRIP_TEXT = { test = "Test mode: sample data. Nothing here is saved.",
                     sim = "Sim: a made-up fight, not your data. /ct sim ends it." }
local STRIP_MAKER = { test = "MakeTestStrip", sim = "MakeSimStrip" }

local function stripFor(which)
    local field = which .. "Strip"
    if not ui[field .. "Tried"] then
        ui[field .. "Tried"] = true
        ui[field] = NS[STRIP_MAKER[which]](ui.frame, L[STRIP_TEXT[which]])
    end
    return ui[field]
end

-- The strip on screen, under the title bar (at the window's top with the title bar hidden).
local function placeStrip()
    local strip = ui.stripMode and ui[ui.stripMode .. "Strip"]
    if not strip then return end
    local top = setting("hud.window.titleBar") ~= false and HEADER_H or 0
    strip:ClearAllPoints()
    strip:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", 1, -top)
    strip:SetPoint("TOPRIGHT", ui.frame, "TOPRIGHT", -1, -top)
end

-- The strip for the fight on screen shown (and the other hidden); a change moves the content, so the
-- window's look is laid out again (applyWindow places the strip).
local function applyStrip()
    local P = NS.Preview
    local want = cur and cur.sample and P and P.Mode() or nil
    if want == ui.stripMode then return end
    ui.stripMode, ui.stamp = want, nil
    local shown = want and stripFor(want) or nil
    for _, which in ipairs({ "test", "sim" }) do
        local strip = ui[which .. "Strip"]
        if strip then strip:SetShown(strip == shown) end
    end
    ui.stripShown = shown ~= nil
    ui.frame.title:SetText(want and not shown and L["Combat Trail (sample)"] or L["Combat Trail"])
end

-- The window's configured look (modules/Hud_Appearance.lua), once per Appearance stamp: the title
-- bar and its title, the footer, the content's insets, the background, border, strata and opacity.
local function applyWindow()
    local A = NS.HudAppearance
    if ui.stamp == A.stamp then return end
    ui.stamp = A.stamp
    local f = ui.frame
    local bar, foot = A.On("hud.window.titleBar"), A.On("hud.window.footer")
    for _, part in ipairs({ ui.close, ui.lock, ui.settings, ui.results, ui.drag, NS.Style.Band(f) }) do
        part:SetShown(bar)
    end
    f.title:SetShown(bar and A.On("hud.window.title"))
    for _, part in ipairs({ ui.footLine, ui.footLeft, ui.footRight }) do part:SetShown(foot) end
    ui.content:ClearAllPoints()
    ui.content:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -contentTop())
    ui.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, contentBottom())
    placeStrip()
    A.ApplyWindow(f)
end

local function showBody(which)
    local body = ui.body[which]
    if not body then
        body = NS.HudStates.Build(which, ui.content)
        ui.body[which] = body
    end
    body.onScroll = render
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
    if fight.frozen and key ~= "over" then return fight.frozen end
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

-- Seconds since the fight's combat entry: the slices' and the casts' zero (the chart's time axis).
local function sinceStart()
    local t = cur and cur.startT
    if type(t) ~= "number" then return 0 end
    if cur.frozen and key ~= "over" then return cur.frozen + ((cur.firstHitT or t) - t) end
    if key == "over" then
        local d = view.final and Secrets.PlainNumber(view.final.duration)
        if d then return d end
    end
    return math.max(0, GetTime() - t)
end

-- The fight's casts and their base cooldowns, read again at most every Hud.CAST_READ seconds while
-- it is live (the chart's icons); the over card keeps the last read, or the record's own.
local function readCasts(v)
    if v.key ~= "live" or not cur or not NS.Casts then return end
    local now = GetTime()
    if v.castsAt and now - v.castsAt < Hud.CAST_READ then return end
    v.castsAt = now
    local casts, spells
    if cur.sample then casts, spells = NS.MockFights.CastsAt(cur.plan, sinceStart())
    else casts, spells = NS.Casts.Live(cur.id) end
    if casts then v.casts, v.castSpells = casts, spells end
end

-- The pace bar's view: the live totals (opaque) or the plain final ones, against the curve.
local function paceView(v)
    local curve = v.curve
    if not curve or v.pace == nil then return nil end
    local withPet = Hud.PACE_PET_FILL == true
    if v.key == "over" then return NS.HudBest.OverView(curve, v.final, v.clock, withPet) end
    return NS.HudBest.LiveView(curve, v.clock, v.live, withPet)
end

-- The over card's spell rows: the merged plain read, highest first, and its total.
local function finalSpells(v)
    local merged = v.final and v.final.merged
    if type(merged) ~= "table" then
        v.finalSpells, v.finalTotal = v.record and NS.Recorder.Spells(v.record) or {}, v.record and v.record.damage
            and v.record.damage.merged or 0
        return
    end
    local out = {}
    for _, sp in ipairs(type(merged.spells) == "table" and merged.spells or {}) do
        local id, total = Secrets.PlainNumber(sp.spellID), Secrets.PlainNumber(sp.total)
        if id and total then out[#out + 1] = { spellID = id, total = total, isPet = sp.isPet == true } end
    end
    v.finalSpells, v.finalTotal = out, Secrets.PlainNumber(merged.total) or 0
end

-- The extras' views (plan Task 3.2): the pace bar, the damage chart, the over card's rows.
local function fillExtras(v)
    readCasts(v)
    local cooldowns = NS.HudChart.Cooldowns(v.casts, v.castSpells)
    v.paceView = paceView(v)
    if not cur then
        v.chartView = nil
    elseif v.key == "over" then
        v.chartView = NS.HudChart.OverView(cur, v.curve, v.final, cooldowns)
        finalSpells(v)
    else
        v.chartView = NS.HudChart.LiveView(cur, v.curve, v.live, sinceStart(), cooldowns)
    end
end

-- The view the bodies draw: the fight's facts plus this moment's settings and figures.
local function fill()
    local v = view
    v.key = key or "live"
    v.live = live
    v.layout = setting("hud.layout") or {}
    v.clock = clockOf()
    v.hasPet = hasPet()
    -- The rows' window (modules/Hud_States.lua): the bars, and a fixed window's room for the stack;
    -- while the grip is held, the dragged size's.
    local drag = sizing()
    v.width = (drag and ui.dragW or width()) - 2 * PAD
    v.bars = drag and barsFor(ui.dragH) or bars()
    v.fitH = fixedMode() and ((drag and ui.dragH or Hud.FixedHeight()) - chromeHeight()) or nil
    v.showSkipReason = setting("hud.showSkipReason") ~= false
    v.minLength = setting("history.minLength")
    fillExtras(v)
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

function render()
    applyStrip()
    applyWindow()
    local v = fill()
    local body = showBody(v.key)
    body:Update(v)
    -- The grip owns the size while it is held.
    if not sizing() then
        local h = fixedMode() and Hud.FixedHeight() or chromeHeight() + (body.height or 0)
        ui.frame:SetSize(width(), h)
    end
    footer(v)
    return v
end

-- The grip's release (or a hide while it was held): the window re-anchored where the drag left it,
-- the width and the whole bars the height holds stored through the seam, and the window snapped to
-- them by the redraw that follows.
function resized(w, h)
    w = Secrets.PlainNumber(w) or ui.dragW
    h = Secrets.PlainNumber(h) or ui.dragH
    ui.dragW, ui.dragH = nil, nil
    placeAfterDrag()
    if w then NS.SetByPath("hud.width", clamp(math.floor(w + 0.5), Hud.MIN_WIDTH, Hud.MAX_WIDTH)) end
    if h and (setting("hud.layout") or {}).spells ~= false then NS.SetByPath("hud.bars", barsFor(h)) end
    if Hud.IsShown() then Hud.Refresh() end
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
    applyGrip()   -- after the strip is placed: its height is in the bounds
    if not windowShown() then ui.frame:Show() end
    -- A grow edge set while the window was unbuilt, or arriving with a profile: the stored point moved
    -- onto it once the window is placed and sized (a no-op while it already sits on the edge).
    normalizeAnchor(false)
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
    if ui then
        applyPlacement()
        normalizeAnchor(false)
    end
end

--- The view the bodies draw now, for the suites and the parts that stack under it (plan Task 3.2).
function Hud.View() return view end

--- A `hud.*` look or layout changed: every part restyles (HudAppearance.Changed) and the HUD
--- redraws now. The DPS HUD page's rows (plan Task 3.3) and the settings seam call it.
function Hud.Apply()
    NS.HudAppearance.Changed()
end

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

--- Drop the sample fight on screen (test mode or the sim ended, modules/Preview.lua): its body goes,
--- and with `release` a window the preview opened is let go too, unless the player opened it, pinned
--- it or keeps it always up. A real fight on screen or waiting for its first hit is left alone.
--- @param release boolean|nil
function Hud.EndSample(release)
    if pending and pending.sample then pending = nil end
    if cur and cur.sample then
        cancelFade()
        cur, key, view, live = nil, nil, {}, nil
    end
    if release and not (byPlayer or pinned) and setting("hud.show") ~= "always" then wanted = false end
    Hud.Refresh()
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
    if fight.sample then
        live = NS.MockFights.LiveAt(fight.plan, sinceStart())
        return
    end
    local sessions = fight.sessions
    local id = (type(sessions) == "table" and sessions[#sessions]) or fight.sessionID
    live = NS.Meter.ReadLive(id)
end

-- The first hit: the fight goes on screen (opening the window when the mode allows it).
local function goLive(fight)
    pending, cur, key, live, dismissed = nil, fight, "live", nil, nil
    view = newView(fight)
    -- A new fight's rows start at the top.
    if ui then for _, body in pairs(ui.body) do body.offset = 0 end end
    cancelFade()
    if fight.sample then
        wanted = true
    elseif not (byPlayer or pinned) then
        wanted = autoAllowed(fight)
    end
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
        and not (cur and cur.sample)
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
    -- The stored casts are the whole fight's: the chart's icons take them over the last live read.
    local casts = type(record.casts) == "string" and NS.CastCodec.Decode(record.casts) or nil
    if casts then view.casts, view.castSpells = casts, record.cooldowns or {} end
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
    -- A new mode or edge: the window re-anchored on the edge that now stays put, where it stands.
    if (path == "hud.sizeMode" or path == "hud.grow") and ui then normalizeAnchor(false) end
    if path == "profile" or path:find("^hud%.") then Hud.Apply() end
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

--- `/ct hud show|hide|toggle|pin|unpin`.
function Hud.OnVerb(rest)
    local word = tostring(rest or ""):match("^%s*(%S*)"):lower()
    local fn = VERBS[word]
    if fn then return fn() end
    NS.Print(L["Usage: /ct hud show, hide, toggle, pin or unpin"])
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
