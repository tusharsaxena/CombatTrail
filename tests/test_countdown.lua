-- tests/test_countdown.lua — modules/Countdown.lua (Race mode plan Task C2): a race's final seconds and
-- its buzzer, ported from DPS Race @f8078c7 (its tests/test_countdown.lua, the buzzer case of its
-- test_hud.lua and the countdown case of its test_layers.lua) onto Combat Trail's race through the REAL
-- Fight and Race (tests/race_fixture.lua fires the events). The center-screen numbers
-- (race.centerCountdown, race.finalCountdown) and the countdown cue (race.countdownCue), one timer per
-- mark, one sound per second at most, the Blizzard BigGold digit art with its font fallback, hidden at
-- the buzzer, on a cancel, on an early combat end and at the stand-down; the /reload cases; the
-- buzzer's raid warning (race.buzzer); and the module's absence on WoW Forever.
--
-- THE CLOCK. The race is armed at 100 and its first hit lands at 102, so a 30 s race's buzzer is at
-- 132 and its numbers run 10 at 122 to 1 at 131. `to(S, t)` walks the clock there in quarter seconds,
-- servicing the timer queue at each step, so every mark fires on its own second as the client would.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local F = dofile(T.root .. "/tests/race_fixture.lua")(T)
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local CUE, BUZZ = 25477, 8959

local function forever() return T.NS.Compat.IsForever() end

-- The client calls the countdown and the buzzer make, recorded: each sound with its time, each raid
-- warning's text.
local function record(m)
    m.__sounds, m.__notices = {}, {}
    m.PlaySound = function(id) m.__sounds[#m.__sounds + 1] = { id = id, t = m.__now } end
    m.SOUNDKIT = { UI_BATTLEGROUND_COUNTDOWN_TIMER = CUE, RAID_WARNING = BUZZ }
    m.RaidWarningFrame = {}
    m.ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.28, b = 0 } }
    m.RaidNotice_AddMessage = function(_, text) m.__notices[#m.__notices + 1] = text end
end

local function fresh(opts)
    opts = opts or {}
    local mutate = opts.mutate
    opts.mutate = function(m)
        installPaint(m)
        record(m)
        if mutate then mutate(m) end
    end
    return F.fresh(opts)
end

local function C(S) return S.NS.Countdown end

--- Walk the clock to `t` in quarter seconds, servicing the timers at each step.
local function to(S, t)
    local now = S.M.__now
    while now < t - 1e-9 do
        now = math.min(t, now + 0.25)
        F.run(S, now)
    end
end

--- Armed for `length` (30) at 100, pulled at 101, the first hit at 102: running.
local function running(S, length)
    assertTrue(F.arm(S, length or 30))
    F.pull(S)
    assertEqual(S.NS.Race.State(), "running")
end

local function shownAt(S, t)
    to(S, t)
    return C(S).Shown()
end

local function frameShown(S)
    local u = C(S).__ui()
    return u ~= nil and u.frame:IsShown() == true
end

--- The times the sound `id` played, as "120,121".
local function soundTimes(S, id)
    local out = {}
    for _, s in ipairs(S.M.__sounds) do
        if s.id == id then out[#out + 1] = ("%g"):format(s.t) end
    end
    return table.concat(out, ",")
end

-- ── the clients ────────────────────────────────────────────────────────────────────────────────

test("countdown: absent on WoW Forever", function()
    if not forever() then return end
    local S = F.fresh()
    assertNil(S.NS.Countdown, "no countdown on WoW Forever")
end)

-- ── the numbers ────────────────────────────────────────────────────────────────────────────────

test("countdown: 10..1 show one per second in the last 10 s, then go at the buzzer", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    assertNil(shownAt(S, 121.75), "a number before the final 10 s")
    assertNil(C(S).__ui(), "the frame is built lazily, at the first number")
    assertEqual(shownAt(S, 122), 10)
    assertTrue(frameShown(S))
    assertEqual(shownAt(S, 122.75), 10, "a number holds for its second")
    assertEqual(shownAt(S, 123), 9)
    assertEqual(shownAt(S, 127.5), 5)
    assertEqual(shownAt(S, 131.5), 1)
    assertNil(shownAt(S, 132), "the buzzer clears it")
    assertFalse(frameShown(S))
    assertEqual(S.NS.Race.State(), "stopping")
end)

test("countdown: its own frame, center of UIParent, FULLSCREEN, over every window and below every menu", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 122)
    local u = assert(C(S).__ui())
    assertEqual(u.frame:GetFrameStrata(), "FULLSCREEN")
    assertEqual(S.NS.Constants.LAYERS.STRATA.SCREEN_ALERT, "FULLSCREEN")
    local hud = S.NS.Hud.Frame and S.NS.Hud.Frame()
    assertTrue(u.frame ~= hud, "not the HUD's frame")
    local rw = S.NS.RaceWindow.__ui()
    assertTrue(rw == nil or u.frame ~= rw.frame, "not the Race window's frame")
end)

test("countdown: the frame never takes the mouse, and each number pops in", function()
    if forever() then return end
    local S = fresh({ mutate = function(m)
        local create = m.CreateFrame
        m.CreateFrame = function(...)
            local f = create(...)
            rawset(f, "EnableMouse", function(self, on) rawset(self, "__mouse", on and true or false) end)
            return f
        end
    end })
    running(S, 30)
    to(S, 122)
    local u = assert(C(S).__ui())
    assertEqual(rawget(u.frame, "__mouse"), false, "mouse-disabled")
    assertTrue(u.pop ~= nil, "the pop animation")
    local plays = 0
    local play = u.pop.Play
    rawset(u.pop, "Play", function(g, ...) plays = plays + 1 return play(g, ...) end)
    to(S, 131)
    assertEqual(plays, 9, "one pop per number after the first: 9 down to 1")
end)

test("countdown: the digits are Blizzard's BigGold set, cut by texcoord", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 122)
    local u = C(S).__ui()
    assertEqual(u.mode, "texture")
    local ones, tens = u.digits[1], u.digits[2]
    assertEqual(ones.__texture, "Interface\\Timer\\BigTimerNumbers")
    assertEqual(u.glows[1].__texture, "Interface\\Timer\\BigTimerNumbersGlow")
    local h = 170 / 512
    -- The cell (left, right, top, bottom), as the four corners the client answers.
    local function cell(l, r, t, b) return table.concat({ l, t, l, b, r, t, r, b }, ",") end
    -- "10": the ones digit 0 (column 0, row 0), the tens digit 1 (column 1, row 0).
    assertEqual(table.concat(ones.__texCoord, ","), cell(0, 0.25, 0, h))
    assertEqual(table.concat(tens.__texCoord, ","), cell(0.25, 0.5, 0, h))
    assertTrue(tens:IsShown())
    to(S, 128)
    -- "4": column 0, row 1; the tens digit hidden.
    assertEqual(table.concat(ones.__texCoord, ","), cell(0, 0.25, h, 2 * h))
    assertFalse(tens:IsShown())
end)

test("countdown: without the digit art it falls back to a large outlined number", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    -- The client answers false for an asset it cannot load: the next frame built takes the font.
    local make = S.M.CreateFrame
    S.M.CreateFrame = function(...)
        local f = make(...)
        local tex = f.CreateTexture
        f.CreateTexture = function(self, ...)
            local t = tex(self, ...)
            local set = t.SetTexture
            t.SetTexture = function(region, path)
                if path == "Interface\\Timer\\BigTimerNumbers" then return false end
                return set(region, path)
            end
            return t
        end
        return f
    end
    to(S, 129)
    S.M.CreateFrame = make
    local u = C(S).__ui()
    assertEqual(u.mode, "font")
    assertEqual(u.text:GetText(), "3")
    assertTrue(u.text:IsShown())
    local _, size, flags = u.text:GetFont()
    assertEqual(size, 110)
    assertTrue(tostring(flags):find("OUTLINE", 1, true) ~= nil)
    assertFalse(u.digits[1]:IsShown())
end)

test("countdown: finalCountdown 3 starts at 3", function()
    if forever() then return end
    local S = fresh()
    assertTrue(S.NS.SetByPath("race.finalCountdown", 3))
    running(S, 30)
    assertNil(shownAt(S, 128.75))
    assertEqual(shownAt(S, 129), 3)
    assertEqual(shownAt(S, 130), 2)
    assertEqual(shownAt(S, 131), 1)
end)

test("countdown: switched off, no frame is ever built and only the cue marks sound", function()
    if forever() then return end
    local S = fresh()
    assertTrue(S.NS.SetByPath("race.centerCountdown", false))
    running(S, 30)
    to(S, 133)
    assertNil(C(S).__ui())
    assertEqual(soundTimes(S, CUE), "122,127,129,130,131")
end)

test("countdown: switching it off mid-countdown hides the number at once", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 124)
    assertTrue(frameShown(S))
    assertTrue(S.NS.SetByPath("race.centerCountdown", false))
    assertFalse(frameShown(S))
    assertNil(shownAt(S, 127))
end)

test("countdown: works with the DPS HUD and the Race window closed", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    S.NS.Hud.Hide()
    S.NS.RaceWindow.Hide()
    assertEqual(shownAt(S, 126), 6)
end)

-- ── the sounds ─────────────────────────────────────────────────────────────────────────────────

test("countdown: one cue per second of the numbers, never two in a second", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 133)
    assertEqual(soundTimes(S, CUE), "122,123,124,125,126,127,128,129,130,131")
    local R = fresh()
    assertTrue(R.NS.SetByPath("race.finalCountdown", 3))
    running(R, 30)
    to(R, 133)
    assertEqual(soundTimes(R, CUE), "122,127,129,130,131", "the cue marks and the numbers' seconds share their sounds")
end)

test("countdown: the cue off keeps the numbers and silences every second", function()
    if forever() then return end
    local S = fresh()
    assertTrue(S.NS.SetByPath("race.countdownCue", false))
    running(S, 30)
    assertEqual(shownAt(S, 127), 5)
    to(S, 133)
    assertEqual(soundTimes(S, CUE), "")
end)

test("countdown: switching the cue off mid-race silences the marks still ahead", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 124.5)
    assertTrue(S.NS.SetByPath("race.countdownCue", false))
    to(S, 133)
    assertEqual(soundTimes(S, CUE), "122,123,124")
end)

-- ── the lifecycle ──────────────────────────────────────────────────────────────────────────────

test("countdown: a cancel at 5 s left hides it and nothing more shows or sounds", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 127.25)
    assertEqual(C(S).Shown(), 5)
    assertTrue(S.NS.Race.Cancel())
    assertNil(C(S).Shown())
    assertFalse(frameShown(S))
    to(S, 133)
    assertNil(C(S).Shown())
    assertEqual(soundTimes(S, CUE), "122,123,124,125,126,127")
    assertEqual(C(S).Diagnose().scheduled, 0)
end)

test("countdown: combat ending before the buzzer hides it", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 125)
    assertTrue(frameShown(S))
    F.leave(S, 125.1)
    assertEqual(S.NS.Race.State(), "stopping")
    assertFalse(frameShown(S))
    assertEqual(C(S).Diagnose().scheduled, 0)
end)

test("countdown: the stand-down takes the number and every mark, and nothing re-arms them", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 124)
    assertTrue(frameShown(S))
    assertTrue(S.NS.SetByPath("general.enabled", false))
    assertFalse(frameShown(S))
    assertEqual(C(S).Diagnose().scheduled, 0)
    to(S, 133)
    assertNil(C(S).Shown())
    assertEqual(soundTimes(S, CUE), "122,123,124")
end)

--- A race run to `at` (30 s, the first hit at 102), then a /reload at `now`, still in combat.
local function reloaded(at, now)
    local S = fresh()
    running(S, 30)
    F.damage(S, 25, 103, at, 1)
    local R = F.reload(S, { now = now, inCombat = true, mutate = function(m)
        installPaint(m)
        record(m)
    end })
    return R
end

test("countdown: a /reload with 4 s left resumes at 4 and counts 3, 2, 1", function()
    if forever() then return end
    local R = reloaded(110, 128)
    assertEqual(R.NS.Race.State(), "running")
    assertEqual(C(R).Shown(), 4, "the number of the moment shows at once")
    assertEqual(#R.M.__sounds, 0, "the resume itself plays no sound")
    assertEqual(shownAt(R, 129), 3)
    assertEqual(shownAt(R, 130), 2)
    assertEqual(shownAt(R, 131), 1)
    assertNil(shownAt(R, 132))
    assertEqual(soundTimes(R, CUE), "129,130,131")
end)

test("countdown: a /reload before the window shows nothing until it opens", function()
    if forever() then return end
    local R = reloaded(110, 112)
    assertEqual(R.NS.Race.State(), "running")
    assertNil(C(R).Shown())
    assertNil(shownAt(R, 121.75))
    assertEqual(shownAt(R, 122), 10)
end)

test("countdown: a /reload past the buzzer shows nothing", function()
    if forever() then return end
    local R = reloaded(110, 133)
    assertEqual(R.NS.Race.State(), "stopping")
    assertNil(C(R).Shown())
    assertNil(C(R).__ui())
end)

-- ── the buzzer ─────────────────────────────────────────────────────────────────────────────────

test("countdown: the buzzer raises the raid warning's STOP with its sound, once, only when enabled", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 131.75)
    assertEqual(#S.M.__notices, 0, "no warning before the buzzer")
    to(S, 132)
    assertEqual(table.concat(S.M.__notices, ","), "STOP")
    assertEqual(soundTimes(S, BUZZ), "132")
    to(S, 134)
    assertEqual(#S.M.__notices, 1, "one warning")
    local Q = fresh()
    assertTrue(Q.NS.SetByPath("race.buzzer", false))
    running(Q, 30)
    to(Q, 133)
    assertEqual(Q.NS.Race.State(), "stopping", "the race still stops")
    assertEqual(#Q.M.__notices, 0, "no warning with the buzzer off")
    assertEqual(soundTimes(Q, BUZZ), "")
end)

test("countdown: a canceled race and a race ending early raise no buzzer", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 120)
    assertTrue(S.NS.Race.Cancel())
    to(S, 134)
    assertEqual(#S.M.__notices, 0)
    local E = fresh()
    running(E, 30)
    F.leave(E, 120)
    to(E, 134)
    assertEqual(#E.M.__notices, 0)
end)

-- ── the fences ─────────────────────────────────────────────────────────────────────────────────

test("countdown: never broadcasts a pull timer nor drives Blizzard's TimerTracker", function()
    local fh = assert(io.open(T.root .. "/modules/Countdown.lua", "rb"))
    local body = fh:read("*a")
    fh:close()
    local code = body:gsub("%-%-[^\n]*", "")
    for _, name in ipairs({ "C_PartyInfo", "DoCountdown", "TimerTracker", "StartTimer_", "OnUpdate" }) do
        assertFalse(code:find(name, 1, true) ~= nil, "modules/Countdown.lua calls " .. name)
    end
end)
