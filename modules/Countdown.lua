local _, NS = ...
-- modules/Countdown.lua — a race's final seconds and its buzzer (Race mode spec §4.2, plan Task C2),
-- ported from DPS Race @f8078c7 (modules/Countdown.lua, and the buzzer's raid warning from its
-- modules/Hud.lua) onto Combat Trail's race: the countdown cue's sounds, the center-screen numbers
-- (like Blizzard's /pull 10), and at the buzzer a raid warning that says STOP, with its sound. When
-- `race.finalCountdown` seconds remain (3-10, default 10) and `race.centerCountdown` is on, a large
-- number pops in at the middle of the screen each second down to 1, and goes at the buzzer.
--
-- ONE TIMER PER MARK, ONE SOUND PER SECOND. When the race starts running (RACE_STATE_CHANGED to
-- running), one C_Timer is armed per whole second still ahead (10 down to 1), from Race.TimeLeft(),
-- never an OnUpdate. A mark serviced before its own second (the client never fires one early; the
-- headless kit fires its queue at once) waits again for what is left, as the race's buzzer does. Each
-- mark reads the settings as it fires: it plays the cue sound once (`race.countdownCue` on, and the
-- mark is a cue mark, 10, 5, 3, 2, 1, or a second of the numbers), then shows its number. So a cue
-- mark inside the numbers' window sounds once, never twice. Leaving running (the buzzer, a cancel,
-- combat ending early) cancels every timer and hides the number; so does the stand-down.
--
-- THE NUMBER AND THE OTHER CLOCKS (owner, 2026-11-13). A number is the whole seconds left rounded up:
-- n shows from n seconds left until n - 1. The Race window's countdown takes the same rounding
-- (NS.Format.RaceClock: the time left rounded up to its tenth, the elapsed time and the DPS HUD's
-- clock truncated), so n pops on the tenth the countdown reads 0:0n.0, and 1 goes at the buzzer, the
-- moment the countdown reads 0:00.0 and the HUD's clock the race length.
--
-- THE SIM'S RACE (plan Task E1): while its sample race's clock runs (modules/RaceSample.lua Live), the
-- marks count it instead, armed by the sim's own Countdown.Refresh at each step; test mode's held sample
-- counts nothing.
--
-- A RESUME mid-window (a /reload, a stand-up, a countdown row changed mid-race) shows the number of
-- the moment at once, silently, and counts on from the next mark. The rows carry no onChange: their
-- SETTINGS_CHANGED (and a profile change) re-arm the marks here.
--
-- THE BUZZER (RACE_BUZZER, whether or not the Race window is shown): with `race.buzzer` on, the raid
-- warning frame says STOP and the raid warning sound plays. Each client call is presence-checked
-- and pcall'd: a client without either still has its race.
--
-- THE FRAME is its own, parented to UIParent, FULLSCREEN strata (LAYERS.STRATA.SCREEN_ALERT in
-- core/Constants.lua: over every window, below every menu, which sits at FULLSCREEN_DIALOG, so a
-- dropdown opened in the last ten seconds is never covered), mouse-disabled, built at the first
-- number it shows. The digits are Blizzard's own art, the BigGold set the client's TimerTracker draws
-- from (256x170 cells on a 1024x512 sheet, four to a row, with a matching Glow sheet), cut by
-- texcoord on this file's own textures and placed by its half-width table as Blizzard places them.
-- Nothing of Blizzard's is called: no pull timer is broadcast to the group and no Blizzard handler
-- runs (taint). A client that cannot load the sheet gets a large outlined number instead. The
-- countdown is the client's start-timer art and stays Blizzard's under every skin.
--
-- RETAIL ONLY (clients-§4): on WoW Forever this file returns at once and NS.Countdown is nil. Nothing
-- here reads a meter value: the marks are GetTime() arithmetic on the race's own clock.

if not NS.Compat.ForClient({ "retail" }) then return end

local L = NS.L

local Countdown = {}
NS.Countdown = Countdown

-- The countdown cue's marks, in seconds left.
Countdown.CUES = { 10, 5, 3, 2, 1 }
-- The numbers' window bounds (race.finalCountdown's range); also the highest mark scheduled.
Countdown.MIN, Countdown.MAX = 3, 10
Countdown.TEXTURE = "Interface\\Timer\\BigTimerNumbers"
Countdown.GLOW = "Interface\\Timer\\BigTimerNumbersGlow"
-- Where the numbers sit: the middle of the screen, a little above the character.
Countdown.OFFSET_Y = 150
-- The fallback number's size, and its color (the BigGold digits' gold, Blizzard's art's own hue).
Countdown.FONT_SIZE = 110
local GOLD = { 1, 0.82, 0 }

-- BigGold's layout (Blizzard_FrameXML/Timer.lua), drawn at its large size.
local DIGIT_W, DIGIT_H, SHEET_W, SHEET_H = 256, 170, 1024, 512
local COLUMNS = math.floor(SHEET_W / DIGIT_W)
local CELL_U, CELL_V = DIGIT_W / SHEET_W, DIGIT_H / SHEET_H
-- Each digit's visible half-width, as a fraction of the cell width: digits 0 to 9.
local HALF_WIDTHS = { 35 / 128, 14 / 128, 33 / 128, 32 / 128, 36 / 128, 32 / 128, 33 / 128, 29 / 128, 31 / 128, 31 / 128 }

Countdown.SOUND_CUE = 25477      -- SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_TIMER, if the table is absent
Countdown.SOUND_BUZZER = 8959    -- SOUNDKIT.RAID_WARNING, if the table is absent
-- A whole second computed from GetTime() differences may land a hair either side of the integer.
local EPS = 1e-6

local IS_CUE = {}
for _, m in ipairs(Countdown.CUES) do IS_CUE[m] = true end

local ui           -- the built frame (nil until the first number)
local timers = {}  -- mark -> C_Timer handle, while the race runs
local shown        -- the number on screen, or nil
local owner        -- "race" | nil: whether the race put it there

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Countdown", fmt, ...) end
end

-- ── settings ────────────────────────────────────────────────────────────────────────────────────

local function numbersOn() return NS.GetSetting("race.centerCountdown") ~= false end
local function cueOn() return NS.GetSetting("race.countdownCue") ~= false end

--- race.finalCountdown, clamped to its range.
local function window()
    local n = math.floor(tonumber(NS.GetSetting("race.finalCountdown")) or Countdown.MAX)
    return math.max(Countdown.MIN, math.min(Countdown.MAX, n))
end

-- ── the frame ───────────────────────────────────────────────────────────────────────────────────

local function scaleRange(anim, from, to)
    if anim.SetScaleFrom then
        anim:SetScaleFrom(from, from)
        anim:SetScaleTo(to, to)
    elseif anim.SetFromScale then
        anim:SetFromScale(from, from)
        anim:SetToScale(to, to)
    end
end

-- The pop: from a quarter size to full in 0.3 s, fading in (Blizzard's startNumbers, held at full size
-- rather than faded out, so the number stays up for its second).
local function buildPop(frame)
    local g = frame:CreateAnimationGroup()
    local grow = g:CreateAnimation("Scale")
    scaleRange(grow, 0.25, 1)
    grow:SetDuration(0.3)
    grow:SetSmoothing("OUT")
    grow:SetOrder(1)
    local fade = g:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.15)
    fade:SetOrder(1)
    return g
end

-- A glow's flash: full, then gone over the pop's 0.3 s. It plays on the glow's own holder frame (an
-- animation group on a frame fades every region on it), one holder per digit.
local function buildFlash(holder)
    local g = holder:CreateAnimationGroup()
    local fade = g:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.3)
    fade:SetSmoothing("IN")
    if g.SetToFinalAlpha then g:SetToFinalAlpha(true) end
    return g
end

-- The animations are decoration: a client that refuses one still shows the numbers.
local function animate(build, target)
    if type(target.CreateAnimationGroup) ~= "function" then return nil end
    local ok, g = pcall(build, target)
    if ok then return g end
    debug("no animation: %s", tostring(g))
    return nil
end

local function buildDigits(u)
    u.digits, u.glows, u.flashes = {}, {}, {}
    u.holders = {}
    for i = 1, 2 do
        local tex = u.frame:CreateTexture(nil, "OVERLAY")
        tex:SetSize(DIGIT_W, DIGIT_H)
        local holder = CreateFrame("Frame", nil, u.frame)
        holder:SetAllPoints(u.frame)
        holder:EnableMouse(false)
        u.holders[i] = holder
        local glow = holder:CreateTexture(nil, "OVERLAY", nil, 2)
        glow:SetPoint("TOPLEFT", tex, "TOPLEFT", 0, 0)
        glow:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 0, 0)
        glow:SetBlendMode("ADD")
        u.digits[i], u.glows[i] = tex, glow
        tex:Hide()
        glow:Hide()
    end
    -- SetTexture answers false for an asset the client cannot load.
    local ok = u.digits[1]:SetTexture(Countdown.TEXTURE) ~= false
    u.digits[2]:SetTexture(Countdown.TEXTURE)
    local glowOk = u.glows[1]:SetTexture(Countdown.GLOW) ~= false
    u.glows[2]:SetTexture(Countdown.GLOW)
    u.glowOk = glowOk
    if glowOk then
        for i = 1, 2 do u.flashes[i] = animate(buildFlash, u.holders[i]) end
    end
    return ok
end

local function buildFallback(u)
    local fs = u.frame:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", Countdown.FONT_SIZE, "THICKOUTLINE")
    fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    fs:SetPoint("CENTER", u.frame, "CENTER", 0, 0)
    fs:Hide()
    u.text = fs
end

local function ensure()
    if ui then return ui end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata(NS.Constants.LAYERS.STRATA.SCREEN_ALERT)
    f:EnableMouse(false)
    f:SetSize(DIGIT_W * 2, DIGIT_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, Countdown.OFFSET_Y)
    f:Hide()
    ui = { frame = f }
    buildFallback(ui)
    ui.mode = buildDigits(ui) and "texture" or "font"
    ui.pop = animate(buildPop, f)
    debug("frame built (%s)", ui.mode)
    return ui
end

-- ── drawing a number ────────────────────────────────────────────────────────────────────────────

local function texCoord(d)
    local l = (d % COLUMNS) * CELL_U
    local t = math.floor(d / COLUMNS) * CELL_V
    return l, l + CELL_U, t, t + CELL_V
end

-- Blizzard's placement: the ones digit's center sits right of the frame's by the summed half-widths
-- less its own, and the tens digit sits left of it by the two half-widths, so the pair is centered.
local function placeDigits(n)
    local x, offset, count = n, 0, 0
    for i = 1, 2 do
        local tex, glow = ui.digits[i], ui.glows[i]
        if x > 0 then
            local d = x % 10
            tex.hw = HALF_WIDTHS[d + 1] * DIGIT_W
            offset = offset + tex.hw
            tex:SetTexCoord(texCoord(d))
            glow:SetTexCoord(texCoord(d))
            tex:Show()
            glow:SetShown(ui.glowOk)
            x, count = math.floor(x / 10), i
        else
            tex:Hide()
            glow:Hide()
        end
    end
    local ones, tens = ui.digits[1], ui.digits[2]
    ones:ClearAllPoints()
    ones:SetPoint("CENTER", ui.frame, "CENTER", offset - ones.hw, 0)
    if count == 2 then
        tens:ClearAllPoints()
        tens:SetPoint("CENTER", ones, "CENTER", -(tens.hw + ones.hw), 0)
    end
end

local function replay(g)
    if not g then return end
    g:Stop()
    g:Play()
end

local function display(n)
    if n == shown then return end
    ensure()
    shown = n
    if ui.mode == "texture" then
        placeDigits(n)
    else
        ui.text:SetText(tostring(n))
        ui.text:Show()
    end
    ui.frame:Show()
    replay(ui.pop)
    for _, g in pairs(ui.flashes or {}) do replay(g) end
end

local function hide()
    shown = nil
    if not ui then return end
    if ui.pop then ui.pop:Stop() end
    ui.frame:Hide()
end

-- ── the race's marks ────────────────────────────────────────────────────────────────────────────

local function play(id)
    if type(PlaySound) ~= "function" then return end
    pcall(PlaySound, id, "Master")
end

local function cueSound()
    return (SOUNDKIT and SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_TIMER) or Countdown.SOUND_CUE
end

local function cancel()
    for m, handle in pairs(timers) do
        handle:Cancel()
        timers[m] = nil
    end
end

-- The race the marks count: the sim's sample race while its clock runs (modules/RaceSample.lua; a
-- held test-mode sample counts nothing), else Race.
local function src()
    local RS = NS.RaceSample
    if RS and RS.Live() then return RS end
    return NS.Race
end

local function racing()
    return not NS.IsStoodDown() and src().State() == NS.Race.STATE.RUNNING
end

local mark

local function arm(m, delay)
    timers[m] = C_Timer.NewTimer(delay, function() mark(m) end)
end

--- One mark, `m` seconds left: the cue once, then the number. The settings are read as it fires. A
--- mark serviced before its second waits again for what is left.
mark = function(m)
    timers[m] = nil
    if not racing() then return end
    local left = src().TimeLeft()
    if not left then return end
    if left > m + EPS then return arm(m, left - m) end
    local numbers = numbersOn() and m <= window()
    if cueOn() and (IS_CUE[m] or numbers) then play(cueSound()) end
    if numbers then display(m) end
end

local function stopRace()
    cancel()
    if owner == "race" then
        owner = nil
        hide()
    end
end

--- Arm the marks still ahead from the race's own clock, showing the number of the moment silently.
local function schedule()
    cancel()
    if not racing() then return stopRace() end
    local left = src().TimeLeft()
    if not left then return stopRace() end
    owner = "race"
    local numbers = numbersOn()
    local now = math.ceil(left - EPS)
    if numbers and now >= 1 and now <= window() then display(now) else hide() end
    if not (numbers or cueOn()) then return end
    for m = Countdown.MAX, 1, -1 do
        if left > m + EPS then arm(m, left - m) end
    end
end

-- ── the buzzer ──────────────────────────────────────────────────────────────────────────────────

--- RACE_BUZZER: the raid warning's STOP and its sound, with `race.buzzer` on.
--- @return boolean raised
function Countdown.Buzzer()
    if NS.IsStoodDown() or NS.GetSetting("race.buzzer") == false then return false end
    play((SOUNDKIT and SOUNDKIT.RAID_WARNING) or Countdown.SOUND_BUZZER)
    if type(RaidNotice_AddMessage) == "function" and RaidWarningFrame then
        local info = type(ChatTypeInfo) == "table" and ChatTypeInfo.RAID_WARNING or nil
        pcall(RaidNotice_AddMessage, RaidWarningFrame, L["STOP"], info)
    end
    debug("buzzer: STOP")
    return true
end

-- ── the public surface ──────────────────────────────────────────────────────────────────────────

--- The number on screen now, or nil.
--- @return number|nil
function Countdown.Shown() return shown end

--- The countdown rows' reaction (race.centerCountdown, race.finalCountdown, race.countdownCue, a
--- profile change), and the sim's sample race moving on (modules/SimRace.lua): re-arm the race's
--- marks from the new values, or take them down when it no longer runs.
function Countdown.Refresh()
    if racing() then schedule() else stopRace() end
end

--- The lifecycle's stand-down: every timer canceled, the number hidden.
function Countdown.Suspend()
    cancel()
    owner = nil
    hide()
end

--- The stand-up: re-arm from the race's current state (Race resumes before this module does).
function Countdown.Resume()
    if racing() then schedule() end
end

--- What it is doing, for the diagnostics report: the number shown, the marks armed, the owner.
function Countdown.Diagnose()
    local n = 0
    for _ in pairs(timers) do n = n + 1 end
    return { shown = shown or "none", scheduled = n, owner = owner or "none" }
end

--- The built frame and its parts, for the suites (nil until the first number).
function Countdown.__ui() return ui end

local ROWS = { ["race.centerCountdown"] = true, ["race.finalCountdown"] = true, ["race.countdownCue"] = true,
               profile = true }

do
    local bus = NS.NewBusTarget()
    if bus then
        bus:RegisterMessage(NS.MSG.RACE_STATE_CHANGED, function(_, _, _, to)
            if to == NS.Race.STATE.RUNNING then schedule() else stopRace() end
        end)
        bus:RegisterMessage(NS.MSG.RACE_BUZZER, function() Countdown.Buzzer() end)
        bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path)
            if ROWS[path] then Countdown.Refresh() end
        end)
    end
end
