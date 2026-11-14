-- tests/test_countdown.lua — modules/Countdown.lua on LibKa0s-Callout-1.0 (callout plan row C2; Race
-- mode plan Task C2 before it): a race's final seconds and its buzzer, through the REAL Fight and Race
-- (tests/race_fixture.lua fires the events) and the REAL vendored call-out. The center numbers
-- (race.centerCountdown, race.finalCountdown) counted to the race's one endsAt, which the Race window's
-- clock reads too; the call-out's voice (the bundled packs, numbers from its `speakFrom`); hidden at
-- the buzzer, on a cancel, on an early combat end and at the stand-down; the /reload cases; the
-- buzzer's STOP (race.buzzer); the seam's stub; and the module's absence on WoW Forever.
--
-- THE CLOCK. The race is armed at 100 and its first hit lands at 102, so a 30 s race's buzzer is at
-- 132 and its numbers run 10 at 122 to 1 at 131. `to(S, t)` walks the clock there in quarter seconds,
-- servicing the timer queue and then running one client frame (every armed OnUpdate, which is the
-- call-out's clock) at each step, as the client would.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local F = dofile(T.root .. "/tests/race_fixture.lua")(T)
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local function forever() return T.NS.Compat.IsForever() end

-- The client calls the call-out makes, recorded: each sound file with its time.
local function record(m)
    m.__files = {}
    m.PlaySoundFile = function(file, channel)
        m.__files[#m.__files + 1] = { file = file, channel = channel, t = m.__now }
        return true, #m.__files
    end
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
local function CO(S) return S.NS.Callout end

--- The frames with an OnUpdate armed now (the kit's live set, M.__timers()).
local function onUpdates(S)
    local out = {}
    for _, h in ipairs(S.M.__timers()) do
        if type(h) == "table" and h.__scripts and h.__scripts.OnUpdate then out[#out + 1] = h end
    end
    return out
end

--- One client frame: every armed OnUpdate runs.
local function frame(S)
    for _, f in ipairs(onUpdates(S)) do f:__fire("OnUpdate", 0) end
end

--- Set the clock to `t`, service the timers, then run one frame.
local function step(S, t)
    F.run(S, t)
    frame(S)
end

--- Walk the clock to `t` in quarter seconds, one step each.
local function to(S, t)
    local now = S.M.__now
    while now < t - 1e-9 do
        now = math.min(t, now + 0.25)
        step(S, now)
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
    local st = CO(S):Stats()
    return st.built == true and st.shown == true
end

--- The voice lines played, as "5@127,4@128": each file's name without its folder and extension.
local function spoken(S)
    local out = {}
    for _, f in ipairs(S.M.__files) do
        out[#out + 1] = ("%s@%g"):format(tostring(f.file):match("([^\\/]+)%.ogg$") or f.file, f.t)
    end
    return table.concat(out, ",")
end

-- ── the clients ────────────────────────────────────────────────────────────────────────────────

test("countdown: absent on WoW Forever, the call-out with it", function()
    if not forever() then return end
    local S = F.fresh()
    assertNil(S.NS.Countdown, "no countdown on WoW Forever")
    assertNil(S.NS.Callout, "no call-out on WoW Forever")
    assertNil(S.NS.defaults.profile.callout, "no call-out settings on WoW Forever")
end)

-- ── the seam ───────────────────────────────────────────────────────────────────────────────────

test("countdown: one call-out, on the addon's folder, skin and eight shipped voices, Arena John the default", function()
    if forever() then return end
    local S = fresh()
    local inst = CO(S)
    assertTrue(inst ~= S.NS.CalloutStub, "the live call-out")
    local keys = {}
    for i, v in ipairs(inst:Voices()) do keys[i] = v.key end
    assertEqual(table.concat(keys, ","),
        "male-arena-john,female,female-kristin,female-cori,female-bella,male,male-john,male-norman,tts,off",
        "the eight packs CLAUDE.md declares, in the library's order, then tts and off")
    assertEqual(inst:Get("voice"), "male-arena-john", "the library's default voice: the arena announcer")
end)

--- The root CLAUDE.md's `LibKa0s sounds:` line, split into its pack names (as the kit's vendor gate
--- reads it: comma-separated, the trailing period off).
local function declaredSounds()
    local fh = assert(io.open(T.root .. "/CLAUDE.md", "rb"))
    local text = fh:read("*a")
    fh:close()
    local line = assert(text:match("\nLibKa0s sounds:%s*([^\r\n]*)"), "CLAUDE.md has a LibKa0s sounds: line")
    line = line:gsub("%s+$", ""):gsub("%.$", "")
    local out = {}
    for name in line:gmatch("[^,]+") do out[#out + 1] = (name:gsub("^%s+", ""):gsub("%s+$", "")) end
    return out
end

test("countdown: the packs the seam offers are the CLAUDE.md sounds line, in order", function()
    if forever() then return end
    local S = fresh()
    local want = declaredSounds()
    assertTrue(#want > 0, "the line names a pack")
    assertEqual(table.concat(S.NS.CALLOUT_PACKS, ","), table.concat(want, ","),
        "NS.CALLOUT_PACKS is the declaration the vendor gate prunes media/sounds/ to")
end)

test("countdown: the profile's call-out table is seeded from its rows, at the library's DEFAULTS", function()
    if forever() then return end
    local S = fresh()
    local inst = CO(S)
    local lib = S.M.LibStub("LibKa0s-Callout-1.0")
    assertEqual(S.NS.defaults.profile.callout.size, lib.DEFAULTS.size, "seeded from the rows (architecture-§5)")
    assertTrue(S.NS.db.profile.callout ~= nil, "the call-out reads the profile's table")
    assertEqual(inst:Get("size"), lib.DEFAULTS.size, "the library's default size")
    assertEqual(inst:Get("font"), lib.DEFAULTS.font, "the library's default font")
end)

test("countdown: the stub answers every member a live call-out has, as an idle call-out does", function()
    if forever() then return end
    local S = fresh()
    T.assertSurfaceParity(CO(S), S.NS.CalloutStub, "Callout instance")
    local stub = S.NS.CalloutStub
    assertFalse(stub.Countdown())
    assertFalse(stub.Show("STOP"))
    assertFalse((stub.Running()))
    assertFalse(stub.Stats().running)
end)

test("countdown: the library absent, the seam answers the stub and the countdown counts nothing", function()
    if forever() then return end
    local inst = T.load({ libFiles = {} })
    assertTrue(inst.NS.Callout == inst.NS.CalloutStub, "the stub stands in")
    assertNil(inst.NS.Countdown.Shown())
    assertFalse(inst.NS.Countdown.Buzzer(), "the buzzer raises nothing")
end)

test("countdown: a countdown the call-out refuses is not reported armed", function()
    if forever() then return end
    local S = fresh()
    local inst, asked = CO(S), 0
    inst.Countdown = function() asked = asked + 1; return false end   -- as the stub, or a suspended one
    running(S, 30)
    to(S, 123)
    assertTrue(asked >= 1, "the call-out was asked inside the window")
    local d = C(S).Diagnose()
    assertEqual(d.owner, "none", "nothing counts down, so the race owns nothing")
    assertEqual(d.scheduled, 0, "and nothing is scheduled")
    assertNil(C(S).Shown())
end)

-- ── the numbers ────────────────────────────────────────────────────────────────────────────────

test("countdown: 10..1 show one per second in the last 10 s, then go at the buzzer", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    assertNil(shownAt(S, 121.75), "a number before the final 10 s")
    assertEqual(shownAt(S, 122), 10)
    assertTrue(frameShown(S))
    assertEqual(CO(S):Stats().endsAt, 132, "counted to the race's one endsAt")
    assertEqual(CO(S):Stats().endsAt, S.NS.RaceClock.EndsAt())
    assertEqual(shownAt(S, 122.75), 10, "a number holds for its second")
    assertEqual(shownAt(S, 123), 9)
    assertEqual(shownAt(S, 127.5), 5)
    assertEqual(shownAt(S, 131.5), 1)
    assertNil(shownAt(S, 132), "the buzzer clears it")
    assertEqual(S.NS.Race.State(), "stopping")
end)

test("countdown: the call-out is not handed the race until the lead before its window", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 120.75)
    assertEqual(#onUpdates(S), 0, "no frame clock for the whole race: one lead-in timer instead")
    assertFalse(CO(S):Stats().built, "the frame is built lazily")
    assertEqual(C(S).Diagnose().scheduled, 1, "the lead-in waits")
    to(S, 121)
    assertTrue(CO(S):Running(), "handed the countdown one second before its first number")
    assertNil(C(S).Shown())
end)

-- The three clocks at the race's end (owner, 2026-11-13: the center read 1 while the Race window read
-- 0:00.0 and the HUD 0:59.9): the Race window's countdown, the DPS HUD's clock and the center number,
-- each read from the same GetTime() and the same endsAt, agree on every tenth.
local function clocks(S, t)
    step(S, t)
    local hud = S.NS.Hud.__ui()
    local v = S.NS.RaceWindow.View()
    local left = v.key == "running" and S.NS.Format.Clock(v.timeLeft) or v.key
    return ("%s %s %s"):format(left, hud.body.live.w.clock:GetText(), tostring(C(S).Shown()))
end

test("countdown: the center number, the Race window's countdown and the HUD's clock agree at the boundaries", function()
    if forever() then return end
    local S = fresh()
    S.NS.Hud.Show()
    S.NS.RaceWindow.Show()
    running(S, 30)
    to(S, 120.5)
    assertEqual(clocks(S, 121.95), "0:10.1 0:19.9 nil", "no number before ten seconds left")
    assertEqual(clocks(S, 122), "0:10.0 0:20.0 10", "10 pops as the countdown reads 0:10.0")
    assertEqual(clocks(S, 122.95), "0:09.1 0:20.9 10")
    assertEqual(clocks(S, 123), "0:09.0 0:21.0 9")
    to(S, 130.75)
    assertEqual(clocks(S, 130.95), "0:01.1 0:28.9 2")
    assertEqual(clocks(S, 131), "0:01.0 0:29.0 1", "1 pops as the countdown reads 0:01.0")
    assertEqual(clocks(S, 131.5), "0:00.5 0:29.5 1")
    assertEqual(clocks(S, 131.95), "0:00.1 0:29.9 1", "the last tenth: 0:00.1, never 0:00.0 beside a 1")
    local at = clocks(S, 132)
    assertTrue(at:match("^(%S+)") ~= "running", "the buzzer: the Race window's stopping body")
    assertEqual(at:match("%S+ (%S+) "), "0:30.0", "the HUD at the race length")
    assertEqual(at:match("(%S+)$"), "nil", "and the number gone")
end)

test("countdown: a new number redraws the Race window in its own frame, off the beat", function()
    if forever() then return end
    local S = fresh()
    S.NS.Hud.Show()
    S.NS.RaceWindow.Show()
    running(S, 30)
    to(S, 126.75)
    assertEqual(S.NS.Format.Clock(S.NS.RaceWindow.View().timeLeft), "0:05.3")
    -- The clock moves to 127 with no timer serviced: only the call-out's frame runs.
    F.at(S, 127)
    frame(S)
    assertEqual(C(S).Shown(), 5)
    assertEqual(S.NS.Format.Clock(S.NS.RaceWindow.View().timeLeft), "0:05.0",
        "the window read 0:05.0 in the frame the call-out showed 5")
end)

test("countdown: the call-out's frame is FULLSCREEN, never the HUD's or the Race window's, and mouse-free while locked", function()
    if forever() then return end
    local S = fresh({ mutate = function(m)
        local create = m.CreateFrame
        m.CreateFrame = function(...)
            local f = create(...)
            rawset(f, "EnableMouse", function(self, on) rawset(self, "__mouse", on and true or false) end)
            rawset(f, "SetFrameStrata", function(self, s) rawset(self, "__strata", s) end)
            return f
        end
    end })
    running(S, 30)
    to(S, 122)
    local f = assert(CO(S):Frame())
    assertEqual(rawget(f, "__strata"), "FULLSCREEN")
    assertEqual(S.NS.Constants.LAYERS.STRATA.SCREEN_ALERT, "FULLSCREEN", "the T5 alert tier the call-out sits on")
    assertEqual(rawget(f, "__mouse"), false, "mouse-transparent")
    assertTrue(CO(S):Locked())
    local hud = S.NS.Hud.Frame and S.NS.Hud.Frame()
    assertTrue(f ~= hud, "not the HUD's frame")
    local rw = S.NS.RaceWindow.__ui()
    assertTrue(rw == nil or f ~= rw.frame, "not the Race window's frame")
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

test("countdown: finalCountdown 20 starts at 20, said from the call-out's speakFrom", function()
    if forever() then return end
    local S = fresh()
    assertTrue(S.NS.SetByPath("race.finalCountdown", 20))
    running(S, 30)
    assertNil(shownAt(S, 111.75), "nothing before the last 20 s")
    assertEqual(shownAt(S, 112), 20, "20 at 20 s left")
    assertEqual(shownAt(S, 122), 10)
    to(S, 133)
    assertEqual(spoken(S), "5@127,4@128,3@129,2@130,1@131,stop@132", "numbers above speakFrom are shown, not said")
end)

test("countdown: finalCountdown takes 3 to 20 and refuses the rest", function()
    if forever() then return end
    local S = fresh()
    assertEqual(S.NS.Countdown.MIN, 3)
    assertEqual(S.NS.Countdown.MAX, 20, "the call-out's longest countdown")
    assertEqual(S.NS.Countdown.MAX, S.M.LibStub("LibKa0s-Callout-1.0").MAX_FROM)
    assertFalse(S.NS.SetByPath("race.finalCountdown", 21))
    assertFalse(S.NS.SetByPath("race.finalCountdown", 2))
    assertTrue(S.NS.SetByPath("race.finalCountdown", 15))
    S.NS.db.profile.race.finalCountdown = 99   -- a stored value past the range (an edited file)
    running(S, 30)
    assertEqual(shownAt(S, 112), 20, "clamped to 20")
end)

test("countdown: a smaller window mid-countdown takes the number down until it is reached", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    assertEqual(shownAt(S, 124), 8)
    assertTrue(S.NS.SetByPath("race.finalCountdown", 3))
    assertNil(C(S).Shown())
    assertFalse(frameShown(S), "8 is not left on screen")
    assertNil(shownAt(S, 128.75))
    assertEqual(shownAt(S, 129), 3)
end)

test("countdown: switched off, nothing is counted, shown or said", function()
    if forever() then return end
    local S = fresh()
    assertTrue(S.NS.SetByPath("race.centerCountdown", false))
    assertTrue(S.NS.SetByPath("race.buzzer", false))
    running(S, 30)
    to(S, 133)
    assertFalse(CO(S):Stats().built, "no frame is ever built")
    assertEqual(spoken(S), "")
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
    assertEqual(#onUpdates(S), 0)
end)

test("countdown: works with the DPS HUD and the Race window closed", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    S.NS.Hud.Hide()
    S.NS.RaceWindow.Hide()
    assertEqual(shownAt(S, 126), 6)
end)

-- ── the voice ──────────────────────────────────────────────────────────────────────────────────

test("countdown: the voice says 5 down to 1 and STOP, each once, from the shipped pack", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 134)
    assertEqual(spoken(S), "5@127,4@128,3@129,2@130,1@131,stop@132",
        "numbers above the call-out's speakFrom (5) are shown, not spoken")
    local file = S.M.__files[1].file
    assertTrue(file:find("AddOns\\CombatTrail\\libs\\LibKa0s\\media\\sounds\\callout\\male-arena-john\\", 1, true) ~= nil,
        "the addon's own copy of the pack: " .. file)
    assertEqual(S.M.__files[1].channel, "Master")
end)

test("countdown: a refresh mid-countdown never repeats a number", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 127.5)
    C(S).Refresh()
    C(S).Refresh()
    assertEqual(C(S).Shown(), 5)
    assertEqual(spoken(S), "5@127")
end)

test("countdown: the call-out's voice off keeps the numbers and silences them", function()
    if forever() then return end
    local S = fresh()
    assertTrue(CO(S):Set("voice", "off"))
    assertEqual(S.NS.GetSetting("callout.voice"), "off", "written through the seam")
    running(S, 30)
    assertEqual(shownAt(S, 127), 5)
    to(S, 134)
    assertEqual(spoken(S), "")
end)

-- ── the lifecycle ──────────────────────────────────────────────────────────────────────────────

test("countdown: a cancel at 5 s left hides it and nothing more shows or is said", function()
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
    assertEqual(spoken(S), "5@127")
    assertEqual(C(S).Diagnose().scheduled, 0)
    assertEqual(#onUpdates(S), 0)
end)

test("countdown: combat ending before the buzzer takes the number down and says FAILED", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 125)
    assertTrue(frameShown(S))
    F.leave(S, 125.1)
    assertEqual(S.NS.Race.State(), "stopping")
    assertNil(C(S).Shown(), "the number is down")
    assertEqual(CO(S):Stats().key, "FAILED", "the call-out says FAILED (callout plan row C9)")
    assertEqual(C(S).Diagnose().scheduled, 0)
end)

test("countdown: the stand-down suspends the call-out, and nothing re-arms it until the stand-up", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 124)
    assertTrue(frameShown(S))
    assertTrue(S.NS.SetByPath("general.enabled", false))
    assertFalse(frameShown(S))
    assertTrue(CO(S):Suspended())
    assertEqual(C(S).Diagnose().scheduled, 0)
    assertEqual(#onUpdates(S), 0, "no OnUpdate left armed while stood down")
    to(S, 127)
    assertNil(C(S).Shown())
    assertEqual(spoken(S), "")
    assertTrue(S.NS.SetByPath("general.enabled", true))
    assertFalse(CO(S):Suspended())
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
    assertEqual(shownAt(R, 129), 3)
    assertEqual(shownAt(R, 130), 2)
    assertEqual(shownAt(R, 131), 1)
    assertNil(shownAt(R, 132))
    assertEqual(spoken(R), "4@128,3@129,2@130,1@131,stop@132")
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
    assertFalse(CO(R):Stats().built)
end)

-- ── the buzzer ─────────────────────────────────────────────────────────────────────────────────

test("countdown: the buzzer shows the call-out's STOP, once, only when enabled", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 131.75)
    assertTrue(CO(S):Stats().key ~= "STOP", "no STOP before the buzzer")
    to(S, 132)
    local st = CO(S):Stats()
    assertEqual(st.key, "STOP")
    assertEqual(st.kind, "stop")
    assertTrue(st.shown)
    to(S, 136)
    assertEqual(#onUpdates(S), 0, "its hold over, it fades and the frame clock sleeps")
    local Q = fresh()
    assertTrue(Q.NS.SetByPath("race.buzzer", false))
    running(Q, 30)
    to(Q, 133)
    assertEqual(Q.NS.Race.State(), "stopping", "the race still stops")
    assertTrue(CO(Q):Stats().key ~= "STOP", "no STOP with the buzzer off")
    assertEqual(spoken(Q), "5@127,4@128,3@129,2@130,1@131")
end)

test("countdown: a canceled race and a race ending early raise no buzzer", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 120)
    assertTrue(S.NS.Race.Cancel())
    to(S, 134)
    assertTrue(CO(S):Stats().key ~= "STOP")
    assertEqual(spoken(S), "", "a cancel says nothing, not even FAILED")
    local E = fresh()
    running(E, 30)
    F.leave(E, 120)
    to(E, 134)
    assertTrue(CO(E):Stats().key ~= "STOP")
    assertEqual(spoken(E), "failed@120", "the early end says FAILED, once, and no STOP")
end)

-- ── a real race's words (callout plan row C9, owner 2026-11-14): the samples' rule ──────────────

test("countdown: the player dying before the buzzer says FAILED; after it, nothing more", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 110)
    F.die(S, 110.5)
    assertEqual(S.NS.Race.State(), "stopping")
    assertEqual(CO(S):Stats().key, "FAILED")
    local D = fresh()
    running(D, 30)
    to(D, 133)
    F.die(D, 133.5)
    to(D, 134)
    assertEqual(spoken(D), "5@127,4@128,3@129,2@130,1@131,stop@132", "a death past the buzzer: STOP alone")
end)

-- A second race on the same board with more damage: a new best over the first.
local BETTER = { damage = 1693682, dps = 43428, duration = 39,
                 spells = { { id = 29722, dmg = 1100000, dps = 28205 }, { id = 116858, dmg = 593682, dps = 15223 } } }

-- The epoch on the race clock, so the second race is fought after the first (Bests ranks the earlier
-- by its epoch, and two races in one real second would tie).
local function clocked()
    return fresh({ mutate = function(m) m.time = function() return 1700000000 + math.floor(m.__now or 0) end end })
end

local function secondRace(S, session)
    assertTrue(F.arm(S, 30, 200))
    local start = F.pull(S, 201, 26, session)
    F.damage(S, 26, start + 1, start + 30, 1)
    F.settle(S, start + 31)
    return start
end

test("countdown: a real race that is a new best says NEW_BEST at its result; a first or slower one does not", function()
    if forever() then return end
    local S = clocked()
    F.whole(S, 30)
    assertEqual(S.NS.Race.State(), "result")
    assertTrue(CO(S):Stats().key ~= "NEW_BEST", "a board's first race beats nothing")
    secondRace(S, BETTER)
    assertEqual(S.NS.Race.State(), "result")
    local rec = F.last(S, "RACE_RESULT")[2]
    assertEqual(rec.race.status, "complete")
    assertTrue(S.NS.BestToast.Earns(rec), "the toast's rule says a new best")
    assertEqual(C(S).ResultWord(rec), "NEW_BEST")
    assertEqual(CO(S):Stats().key, "NEW_BEST", "the call-out says it")
    local W = clocked()
    F.whole(W, 30)
    secondRace(W, F.SESSION)
    assertTrue(CO(W):Stats().key ~= "NEW_BEST", "no faster than the best: no NEW_BEST")
end)

test("countdown: NEW_BEST does not ask the toast's switch; Race mode off keeps every word off", function()
    if forever() then return end
    local S = clocked()
    assertTrue(S.NS.SetByPath("toast.races", false))
    F.whole(S, 30)
    secondRace(S, BETTER)
    assertEqual(CO(S):Stats().key, "NEW_BEST", "the word is the call-out's, not the toast's")
    local E = fresh()
    running(E, 30)
    assertTrue(E.NS.SetByPath("race.enabled", false))   -- off stops new races; this one runs on
    F.leave(E, 120)
    assertEqual(spoken(E), "", "Race mode off: no FAILED")
end)

test("countdown: a real race's FAILED keeps the call-out's per-word mute and own text", function()
    if forever() then return end
    local S = fresh()
    assertTrue(S.NS.SetByPath("callout.muted.FAILED", true))
    assertTrue(S.NS.SetByPath("callout.texts.FAILED", "TOO SOON"))
    running(S, 30)
    F.leave(S, 120)
    assertEqual(CO(S):Stats().key, "FAILED")
    assertEqual(spoken(S), "", "muted: shown, never said")
    assertEqual(CO(S):Stats().text, "TOO SOON", "the player's own text")
end)

test("countdown: one rule for a real race and a sample: EndWord and ResultWord", function()
    if forever() then return end
    local C_ = fresh().NS.Countdown
    assertEqual(C_.EndWord({ status = "stopping", endedAt = 9 }), "FAILED")
    assertNil(C_.EndWord({ status = "stopping" }), "the buzzer came: no word")
    assertNil(C_.EndWord({ status = "lost", endedAt = 9 }))
    assertNil(C_.EndWord(nil))
    assertNil(C_.ResultWord({ race = { status = "incomplete" } }), "incomplete never NEW_BEST")
    assertNil(C_.ResultWord({}))
    assertFalse(C_.RaceSay(nil))
    assertFalse(C_.RaceSay("STOP"), "only the race's words")
end)

-- ── the one endsAt, the stand-up, a profile change, the retired cue (callout plan row C3) ──────────

--- Record every countdown the call-out is handed: the spec tables, in order.
local function handed(S)
    local specs, inst = {}, CO(S)
    local real = inst.Countdown
    inst.Countdown = function(self, spec)
        specs[#specs + 1] = spec
        return real(self, spec)
    end
    return specs
end

test("countdown: the call-out is handed the race's one endsAt, the value RaceClock and Race read", function()
    if forever() then return end
    local S = fresh()
    local specs = handed(S)
    running(S, 30)
    assertEqual(S.NS.Race.EndsAt(), 132, "the buzzer's moment: the first hit at 102 plus 30")
    assertEqual(S.NS.RaceClock.EndsAt(), S.NS.Race.EndsAt(), "the race beat follows Race.EndsAt")
    to(S, 122)
    assertEqual(#specs, 1, "handed once, at the lead")
    assertEqual(specs[1].endsAt, S.NS.RaceClock.EndsAt(), "the call-out counts to the same endsAt")
    assertEqual(specs[1].from, 10)
    assertEqual(specs[1].finish, false, "no GO: the countdown runs to the race's end")
    to(S, 125.5)
    assertTrue(math.abs(S.NS.Race.TimeLeft() - (specs[1].endsAt - S.M.__now)) < 1e-9,
        "the time left is that endsAt less now")
    to(S, 132)
    assertNil(S.NS.RaceClock.EndsAt(), "no endsAt once the race stops")
    assertEqual(#specs, 1, "never handed a second time in one race")
end)

test("countdown: the stand-up re-arms from the race's endsAt and shows the number of the moment", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 124)
    assertTrue(S.NS.SetByPath("general.enabled", false))
    to(S, 127.5)
    assertTrue(S.NS.SetByPath("general.enabled", true))
    step(S, 127.5)
    assertEqual(C(S).Shown(), 5, "5 s left at the stand-up: 5 at once")
    assertEqual(shownAt(S, 128), 4)
    assertNil(shownAt(S, 132))
end)

test("countdown: a stand-down during the lead-in drops the timer; the stand-up waits again", function()
    if forever() then return end
    local S = fresh()
    running(S, 30)
    to(S, 110)
    assertEqual(C(S).Diagnose().scheduled, 1, "the lead-in waits")
    assertTrue(S.NS.SetByPath("general.enabled", false))
    assertEqual(C(S).Diagnose().scheduled, 0, "the stand-down drops it")
    assertTrue(S.NS.SetByPath("general.enabled", true))
    assertEqual(C(S).Diagnose().scheduled, 1, "the stand-up waits again")
    assertNil(shownAt(S, 121.75))
    assertEqual(shownAt(S, 122), 10)
end)

test("countdown: a profile change re-applies the call-out's look and reads the new profile's table", function()
    if forever() then return end
    local S = fresh()
    local inst, applied = CO(S), 0
    local real = inst.Apply
    inst.Apply = function(self, ...)
        applied = applied + 1
        return real(self, ...)
    end
    assertTrue(S.NS.SetByPath("callout.size", 120))
    assertEqual(inst:Get("size"), 120, "the getter reads the profile's table")
    S.NS.db:SetProfile("Other")
    assertTrue(applied >= 1, "the profile change re-applied the call-out")
    assertEqual(S.NS.db.profile.callout.size, 96, "the new profile holds the seeded default")
    assertEqual(inst:Get("size"), S.M.LibStub("LibKa0s-Callout-1.0").DEFAULTS.size, "so it reads the defaults")
end)

test("countdown: a profile that still stores the retired race.countdownCue counts as any other", function()
    if forever() then return end
    local played = 0
    local S = fresh({ mutate = function(m) m.PlaySound = function() played = played + 1 end end })
    -- An old profile's stored cue (AceDB keeps only differences; nothing migrates or reads it).
    S.NS.db.profile.race.countdownCue = 8960
    running(S, 30)
    to(S, 133)
    assertEqual(spoken(S), "5@127,4@128,3@129,2@130,1@131,stop@132", "the call-out's voice alone")
    assertEqual(played, 0, "no sound kit cue played")
    assertNil(S.NS.FindSchemaRow("race.countdownCue"), "and no row reaches it")
end)

-- ── the fences ─────────────────────────────────────────────────────────────────────────────────

test("countdown: never broadcasts a pull timer, drives Blizzard's TimerTracker or keeps a clock of its own", function()
    local fh = assert(io.open(T.root .. "/modules/Countdown.lua", "rb"))
    local body = fh:read("*a")
    fh:close()
    local code = body:gsub("%-%-[^\n]*", "")
    for _, name in ipairs({ "C_PartyInfo", "DoCountdown", "TimerTracker", "StartTimer_", "OnUpdate", "PlaySound",
                            "RaidNotice_AddMessage", "C_Timer" }) do
        assertFalse(code:find(name, 1, true) ~= nil, "modules/Countdown.lua calls " .. name)
    end
end)
