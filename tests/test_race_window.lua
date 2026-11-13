-- tests/test_race_window.lua — the Race window (Race mode plan Task C1): DPS Race's HUD-state cases
-- that survive the merge (its tests/test_hud.lua, test_hud_best.lua, test_hud_hint.lua,
-- test_hud_tiles.lua, test_hud_layout.lua and test_hud_window.lua @f8078c7, the chart and spell-row
-- cases dropped: the DPS HUD owns them), on Combat Trail's race through the REAL Fight, Race and
-- Recorder (tests/race_fixture.lua fires the events), with the kit's paint recorder installed. The six
-- bodies, the idle pick and its refusals, the target card and Your best, the Stop! and waiting
-- figures, the result card and its acts, the shell's skin and look, attached and detached, the show
-- rules, the clock's timer, the DPS HUD opening for a race (ruling X7), and the window's absence on
-- WoW Forever. Every case but that one runs on the Retail kit profile only.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local F = dofile(T.root .. "/tests/race_fixture.lua")(T)
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local function forever() return T.NS.Compat.IsForever() end

local function fresh(opts)
    opts = opts or {}
    local mutate = opts.mutate
    opts.mutate = function(m)
        installPaint(m)
        if mutate then mutate(m) end
    end
    local S = F.fresh(opts)
    -- Auto-show off (both its rows, W29 decision D4), and the windows it opened at login (the player
    -- targets a dummy) let go: each case opens the window itself. The auto-show hooks have their own
    -- case below.
    assert(S.NS.SetByPath("race.autoShow", false))
    assert(S.NS.SetByPath("race.autoShowHud", false))
    S.NS.RaceWindow.HideAwayFromDummy()
    S.NS.Hud.HideAwayFromDummy()
    return S
end

local function W(S) return S.NS.RaceWindow end
local function body(S)
    local ui = W(S).__ui()
    return ui and ui.body[ui.current] or nil
end
local function current(S)
    local ui = W(S).__ui()
    return ui and ui.current or nil
end

local function prints(S)
    local lines = {}
    S.NS.Print = function(line) lines[#lines + 1] = line end
    return lines
end

local function has(list, want)
    for _, s in ipairs(list) do
        if s == want then return true end
    end
    return false
end

local function hasPrefix(list, want)
    for _, s in ipairs(list) do
        if type(s) == "string" and s:sub(1, #want) == want then return true end
    end
    return false
end

-- A race of `length` run whole (armed at 100, the first hit at 102), the window shown first.
local function raced(S, length, after)
    W(S).Show()
    return F.whole(S, length or 30, after)
end

-- ── the clients ────────────────────────────────────────────────────────────────────────────────

test("race window: absent on WoW Forever, with nothing of it loaded", function()
    if not forever() then return end
    local S = F.fresh()
    assertNil(S.NS.RaceWindow, "no Race window on WoW Forever")
    assertNil(S.NS.RaceWindowStates, "no Race window bodies on WoW Forever")
    assertNil(S.NS.RaceWindowBest, "no Your best card on WoW Forever")
    prints(S)
    assertFalse(S.NS.ToggleRaceWindow(), "the toggle does nothing")
end)

test("race window: present on Retail, with its frame name and its hooks", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    assertEqual(RW.FRAME_NAME, "CombatTrailRaceWindow")
    for _, name in ipairs({ "Show", "Hide", "Toggle", "IsShown", "Attach", "Detach", "IsAttached", "Render",
                            "ResetPosition", "ShowNearDummy", "HideAwayFromDummy", "ShownNearDummy", "Closes",
                            "ArmLength", "Suspend", "Resume" }) do
        assertEqual(type(RW[name]), "function", name)
    end
    assertFalse(RW.IsShown(), "closed until something opens it")
    RW.Show()
    assertTrue(RW.IsShown())
    assertTrue(RW.__ui().frame:IsShown())
end)

-- ── the six bodies ─────────────────────────────────────────────────────────────────────────────

test("race window: the six bodies follow the race, idle to the result card", function()
    if forever() then return end
    local S = fresh()
    W(S).Show()
    assertEqual(current(S), "idle")
    assertTrue(F.arm(S, 30))
    assertEqual(current(S), "armed")
    local start = F.pull(S)
    assertEqual(current(S), "running")
    F.damage(S, 25, start + 1, start + 30, 1)
    assertEqual(S.NS.Race.State(), "stopping")
    assertEqual(current(S), "stop", "damage may still land: Stop!")
    F.run(S, start + 33)
    assertEqual(current(S), "waiting", "the tail went quiet: waiting for combat to end")
    F.settle(S, start + 34)
    assertEqual(S.NS.Race.State(), "result")
    assertEqual(current(S), "result")
end)

test("race window: combat ending before the buzzer waits for the read", function()
    if forever() then return end
    local S = fresh()
    W(S).Show()
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 10, 1)
    F.leave(S, start + 10)
    W(S).Refresh()
    assertEqual(current(S), "waiting")
    local v = W(S).View()
    assertTrue(v.endedEarly, "ended before the buzzer")
    local w = body(S).w
    assertEqual(w.tail.label:GetText(), "Combat ended")
    assertEqual(w.tail.value:GetText(), "0:10")
    assertEqual(w.title:GetText(), "Reading the result", "out of combat the read is next")
end)

test("race window: an early end back in combat counts the time since the race ended, and the hint comes", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    RW.Show()
    assertTrue(F.arm(S, 60))
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 10, 1)
    F.leave(S, start + 10)
    F.enter(S, start + 11)              -- Feign Death inside the grace: combat carries on
    F.run(S, start + 15)
    assertEqual(current(S), "waiting")
    local w = body(S).w
    assertEqual(w.combat.label:GetText(), "In combat")
    assertEqual(w.combat.value:GetText(), "+5.0s", "the time since the race ended, never a frozen 0")
    assertFalse(w.hint:IsShown(), "no hint before the delay")
    F.run(S, start + 26)
    assertTrue(w.hint:IsShown(), "combat holding the read brings the hint")
end)

-- ── idle ───────────────────────────────────────────────────────────────────────────────────────

test("race window: idle after a plain fight's settle offers Arm Race again", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    RW.Show()
    S.meter.SetSession(25, F.SESSION)
    F.enter(S, 101)
    F.hit(S, 102, 25)
    F.leave(S, 110)
    assertEqual(RW.View().blocker, "settling", "the last fight is still being read")
    F.run(S, 114.1)
    F.run(S, 117)
    assertEqual(S.NS.Fight.State(), "idle")
    assertNil(RW.View().blocker, "the window drew again once the fight was read")
    assertTrue(body(S).w.arm:IsEnabled(), "Arm Race is offered")
end)

test("race window: idle offers the five lengths and Custom, and Arm Race arms the pick", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    RW.Show()
    local w = body(S).w
    assertEqual(#w.presets, 5)
    local labels = {}
    for i, b in ipairs(w.presets) do labels[i] = b.label:GetText() end
    assertEqual(table.concat(labels, ","), "0:30,1:00,2:00,3:00,5:00")
    assertEqual(RW.View().length, 60, "the default length, 1:00")
    assertEqual(w.presets[2].styleName, "primary", "the length offered is the picked one")
    RW.Act.pickLength(120)
    assertEqual(RW.ArmLength(), 120)
    assertEqual(w.presets[3].styleName, "primary")
    assertEqual(w.presets[2].styleName, "normal")
    assertEqual(w.custom.label:GetText(), "Custom")
    assertTrue(RW.Act.arm())
    assertEqual(S.NS.Race.Current().length, 120, "Arm Race arms the pick")
end)

test("race window: a typed length is taken, and one out of range is refused with the length line", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    local lines = prints(S)
    RW.Show()
    RW.Act.openCustom()
    local w = body(S).w
    assertTrue(w.customBox:IsShown(), "the box replaces Custom")
    assertFalse(w.custom:IsShown())
    assertTrue(RW.Act.customLength("1:30"))
    assertEqual(RW.View().length, 90)
    assertFalse(w.customBox:IsShown(), "the box closes on a length")
    assertEqual(w.custom.label:GetText(), "1:30", "Custom names a length that is no preset")
    assertEqual(w.custom.styleName, "primary")
    assertFalse(RW.Act.customLength("5"))
    assertFalse(RW.Act.customLength("abc"))
    assertEqual(lines[1], "A race lasts from 0:10 to 15:00.")
    assertEqual(RW.View().length, 90, "a refused length changes nothing")
end)

test("race window: a changed Default race length takes effect over the pick", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    RW.Show()
    RW.Act.pickLength(120)
    assertEqual(RW.View().length, 120)
    assertTrue(S.NS.SetByPath("race.defaultLength", 300))
    assertEqual(RW.View().length, 300, "the idle body offers the new default")
    assertEqual(RW.ArmLength(), 300, "and auto-arm arms it")
    assertEqual(body(S).w.presets[5].styleName, "primary", "the 5:00 preset is the picked one")
end)

test("race window: in combat Arm Race is disabled and the line under it says why", function()
    if forever() then return end
    local S = fresh()
    W(S).Show()
    F.enter(S, 100)
    W(S).Refresh()
    local w = body(S).w
    assertFalse(w.arm:IsEnabled())
    assertEqual(w.reason:GetText(), "Leave combat to arm a race.")
end)

test("race window: the target card names the dummy, its kind and its creature ID", function()
    if forever() then return end
    local S = fresh()
    W(S).Show()
    local w = body(S).w
    assertEqual(w.card.name:GetText(), "Raider's Training Dummy")
    assertEqual(w.card.badgeText:GetText(), S.NS.Dummies.Label(S.NS.Dummies.CategoryOf(F.DUMMY)))
    assertEqual(w.card.id:GetText(), "#31146")
    assertEqual(w.warn:GetText(), "", "a dummy draws no warning")
end)

test("race window: a target that is no training dummy, or none, is warned about", function()
    if forever() then return end
    local S = fresh({ target = F.BOAR_GUID })
    W(S).Show()
    local w = body(S).w
    assertTrue(w.warn:GetText():find("is no training dummy", 1, true) ~= nil, w.warn:GetText())
    assertEqual(w.best.empty:GetText(), "Target a training dummy to see your best.")
    local N = fresh({ target = false })
    W(N).Show()
    assertEqual(body(N).w.warn:GetText(), "No target: target a training dummy, then arm.")
end)

test("race window: Your best is empty before the first race, then the race board's best", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    RW.Show()
    RW.Act.pickLength(30)
    assertEqual(body(S).w.best.empty:GetText(), "No race yet: this one sets the mark.")
    raced(S, 30)
    local record = F.records(S)[1]
    RW.Act.newRace()
    assertEqual(current(S), "idle")
    local best = body(S).w.best
    assertTrue(best.dps:IsShown())
    assertEqual(best.card.record.id, record.id, "the card holds the race board's best")
    assertEqual(best.dps:GetText(), S.NS.Format.Number(S.NS.RaceRecord.Dps(record)))
    assertEqual(best.damage:GetText(), S.NS.Format.Number(record.race.score))
    local opened
    S.NS.Results.ShowFight = function(id) opened = id return true end
    best.card:__fire("OnMouseUp", "LeftButton")
    assertEqual(opened, record.id, "a click opens it in Results")
    RW.Act.pickLength(60)
    assertEqual(body(S).w.best.empty:GetText(), "No race yet: this one sets the mark.", "another length, another board")
end)

-- ── Stop! and waiting ──────────────────────────────────────────────────────────────────────────

test("race window: Stop! counts the late casts the ignore list leaves, beside the grace", function()
    if forever() then return end
    local S = fresh()
    W(S).Show()
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 30, 1)
    local buzzer = start + 30
    F.cast(S, buzzer + 2, "start", 133)
    F.cast(S, buzzer + 2.2, "succeeded", 5384)   -- Feign Death: on the default ignore list
    W(S).Refresh()
    assertEqual(current(S), "stop")
    local chips = body(S).w.chips:Texts()
    assertEqual(chips[1], "1 late cast \194\183 +2.0s")
    assertEqual(chips[2], "Grace 1.0s")
    local w = body(S).w
    assertEqual(w.big:GetText(), "STOP")
    assertEqual(w.tail.label:GetText(), "Damage stopped")
    assertEqual(w.tail.value:GetText(), "+0.0s")
    assertEqual(w.combat.label:GetText(), "In combat")
    assertEqual(w.combat.value:GetText(), "+2.2s")
    assertTrue(w.stopNow:IsEnabled())
end)

test("race window: the waiting body's hint comes after the hint delay in combat, and Stop Now is taken once", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    RW.Show()
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 30, 1)
    local buzzer = start + 30
    F.run(S, buzzer + 5)
    assertEqual(current(S), "waiting")
    local w = body(S).w
    assertEqual(w.title:GetText(), "Waiting for combat to end")
    assertFalse(w.hint:IsShown(), "no hint before the delay")
    F.run(S, buzzer + 16)
    assertTrue(w.hint:IsShown(), "the hint after race.hintDelay (15 s)")
    assertTrue(w.hintText:GetText():find("Combat is holding", 1, true) ~= nil)
    assertTrue(RW.Act.stopNow())
    assertEqual(w.title:GetText(), "Reading when combat ends")
    assertFalse(w.stopNow:IsEnabled(), "Stop Now is taken once")
    assertEqual(RW.__ui().footRight:GetText(), "Result pending")
end)

-- The owner, 2026-11-13: a DoT ticking after the buzzer flipped Stop! and waiting at each tick, the
-- hint box blinking in and out. Combat holding past the hint delay goes to waiting and stays.
test("race window: a damage tail in combat past the hint delay waits, and never goes back to Stop!", function()
    if forever() then return end
    local S = fresh()
    W(S).Show()
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    local buzzer = start + 30
    F.damage(S, 25, start + 1, buzzer + 5, 1)    -- a DoT still landing a tick a second
    assertEqual(current(S), "stop", "damage still landing under the delay: Stop!")
    F.damage(S, 25, buzzer + 6, buzzer + 16, 1)
    assertEqual(current(S), "waiting", "combat held past race.hintDelay: waiting")
    local w = body(S).w
    assertTrue(w.hint:IsShown(), "with the hint")
    for t = buzzer + 17, buzzer + 25 do
        F.damage(S, 25, t, t, 1)
        assertEqual(current(S), "waiting", "a later tick keeps waiting at " .. (t - buzzer))
        assertTrue(w.hint:IsShown())
    end
end)

test("race window: the waiting body keeps the hint's room before the hint shows", function()
    if forever() then return end
    local S = fresh()
    W(S).Show()
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 30, 1)
    F.run(S, start + 35)
    assertEqual(current(S), "waiting")
    local b = body(S)
    assertFalse(b.w.hint:IsShown(), "no hint yet")
    local room = b.hintH
    assertTrue(type(room) == "number" and room > 0, "the room is kept")
    F.run(S, start + 47)
    assertTrue(b.w.hint:IsShown())
    assertEqual(b.hintH, room, "the hint's arrival moves nothing")
end)

test("race window: the hint box is sized to its words, never measured", function()
    if forever() then return end
    local S = fresh()
    local St = S.NS.RaceWindowStates
    assertEqual(St.HintLines("one two three", 236), 1)
    assertTrue(St.HintLines(string.rep("word ", 60), 236) > 3)
    assertEqual(St.HintHeight("one", 236), 12 + 12)
end)

-- ── the result card ────────────────────────────────────────────────────────────────────────────

test("race window: the result card shows the score, the race DPS and its chips", function()
    if forever() then return end
    local S = fresh()
    raced(S, 30)
    assertEqual(current(S), "result")
    local record = F.records(S)[1]
    local w = body(S).w
    assertEqual(w.score.label:GetText(), "Score")
    assertEqual(w.score.value:GetText(), S.NS.Format.Number(record.race.score))
    assertEqual(w.dps.label:GetText(), "Race DPS")
    assertEqual(w.dps.value:GetText(), S.NS.Format.Number(S.NS.RaceRecord.Dps(record)))
    local chips = w.chips:Texts()
    assertEqual(chips[1], "New best", "the board's first race sets the mark")
    assertTrue(hasPrefix(chips, "Time 0:30"), table.concat(chips, " | "))
    assertTrue(w.open:IsEnabled())
    assertTrue(w.share:IsEnabled())
    assertTrue(w.delete:IsEnabled())
    assertNil(w.pace, "no pace bar: the DPS HUD's over card draws it (Task W7)")
    assertFalse(w.againstCap.title:IsShown(), "no earlier best: no Against your best")
    assertEqual(#w.against:Texts(), 0)
    assertTrue(w.boardCap.title:IsShown(), "Top races: the race is on it")
    assertEqual(w.boardCap.title:GetText(), "Top races")
    assertEqual(#w.board:Texts(), 1)
    assertEqual(w.board:Highlighted(), 1, "this race, first on its board")
end)

test("race window: a slower second race is behind its best, set against it in Against your best", function()
    if forever() then return end
    local S = fresh()
    raced(S, 30)
    local first = F.records(S)[1]
    W(S).Act.newRace()
    local slower = { damage = 1000000, dps = 25000, duration = 40, spells = { { id = 348, dmg = 1000000, dps = 25000 } } }
    -- The second race a hundred seconds later on the epoch clock too, so it is the later of the two.
    local later = os.time() + 100
    S.M.time = function() return later end
    assertTrue(F.arm(S, 30, 200))
    local start = F.pull(S, 201, 26, slower)
    F.damage(S, 26, start + 1, start + 30, 1)
    F.settle(S, start + 31)
    assertEqual(current(S), "result")
    local v = W(S).View()
    assertEqual(S.NS.Race.Result().race.score, 1000000, "the card is the second race's")
    assertTrue(type(v.delta) == "number" and v.delta < 0, "behind the best")
    local chips = body(S).w.chips:Texts()
    for _, s in ipairs(chips) do
        assertTrue(s:find("vs best", 1, true) == nil, "no chip repeats Against your best's DPS Diff: " .. s)
    end
    assertTrue(hasPrefix(chips, "Time 0:30"), "the Time chip stays: " .. table.concat(chips, " | "))
    assertNil(v.pace, "no pace bar")
    assertEqual(v.prev.id, first.id, "set against the best before it, Bests.Delta's")
    local w = body(S).w
    assertTrue(w.againstCap.title:IsShown())
    local rows = w.against:Texts()
    assertEqual(#rows, 4, "Score, DPS, Item level, Date: no time raced row")
    local F2 = S.NS.Format
    assertEqual(rows[1], "Score|" .. F2.Number(1000000) .. "|" .. F2.Number(first.race.score) .. "|"
        .. F2.Number(1000000 - first.race.score))
    assertEqual(v.compare[2].cells[4], F2.SignedPct(v.delta), "the DPS diff is Bests.Delta's")
    assertTrue(v.compare[1].colors[4] == S.NS.HudStates.COLORS.red, "behind: red")
    assertEqual(v.compare[4].cells[1], "Date")
    assertEqual(v.compare[4].cells[4], "", "the date has no diff")
    local board = w.board:Texts()
    assertEqual(#board, 2)
    assertEqual(board[1]:sub(1, 2), "1|", "the first race leads the board")
    assertEqual(w.board:Highlighted(), 2, "this race, second")
end)

test("race window: New Race goes back to Arm Race at the race's length, the window kept", function()
    if forever() then return end
    local S = fresh()
    raced(S, 30)
    local RW = W(S)
    assertTrue(RW.Act.newRace())
    assertEqual(S.NS.Race.State(), "idle")
    assertEqual(current(S), "idle")
    assertEqual(RW.View().length, 30)
    assertTrue(RW.IsShown())
    assertEqual(#F.records(S), 1, "the race stays saved")
end)

test("race window: Open opens the race in Results, Share prompts, Delete asks first", function()
    if forever() then return end
    local S = fresh()
    raced(S, 30)
    local record = F.records(S)[1]
    local RW, NS = W(S), S.NS
    local opened, shared, asked
    NS.Results.ShowFight = function(id) opened = id return true end
    NS.Share.Prompt = function(r) shared = r.id end
    NS.Results.ConfirmDelete = function(id) asked = id end
    RW.Act.open()
    assertEqual(opened, record.id)
    RW.Act.share()
    assertEqual(shared, record.id)
    assertTrue(RW.Act.delete())
    assertEqual(asked, record.id, "Delete asks through the Results window's confirmation")
    assertEqual(current(S), "result", "nothing goes before the confirmation")
end)

test("race window: a result card whose race is deleted goes back to Arm Race", function()
    if forever() then return end
    local S = fresh()
    raced(S, 30)
    local record = F.records(S)[1]
    S.NS.Recorder.Delete(record.id)
    assertEqual(S.NS.Race.State(), "idle")
    assertEqual(current(S), "idle")
    assertEqual(W(S).View().length, 30)
    assertTrue(W(S).IsShown())
end)

test("race window: closing a result card dismisses it and keeps the race", function()
    if forever() then return end
    local S = fresh()
    raced(S, 30)
    local RW = W(S)
    RW.Act.close()
    assertFalse(RW.IsShown())
    assertEqual(S.NS.Race.State(), "idle", "the card is dismissed")
    assertEqual(#F.records(S), 1, "the race stays in the history")
    assertEqual(RW.Closes(), 1, "the player's close is counted")
end)

test("race window: a lost race shows dashes and says it could not be read", function()
    if forever() then return end
    local S = fresh()
    W(S).Show()
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 5, 1)
    S.M.__fire("DAMAGE_METER_RESET")
    F.settle(S, start + 6)
    if S.NS.Race.State() ~= "result" then return end
    local w = body(S).w
    assertEqual(w.score.value:GetText(), "\226\128\148")
    assertEqual(w.lost:GetText(), "Couldn't read the result")
    assertFalse(w.open:IsEnabled(), "nothing saved to open")
    assertFalse(w.againstCap.title:IsShown(), "a lost race: no Against your best")
    assertFalse(w.boardCap.title:IsShown(), "and no Top races")
    assertEqual(#w.board:Texts(), 0)
end)

test("race window: the result chips name each flag in a short word, its full text the tip", function()
    if forever() then return end
    local S = fresh()
    local St = S.NS.RaceWindowStates
    local race = { status = "incomplete", length = 30, endedAt = 12.5, score = 1000,
                   flags = { lateCasts = {}, sharedSession = true, died = false } }
    local list = St.FlagChips(race)
    local texts = {}
    for i, c in ipairs(list) do texts[i] = c.text end
    assertTrue(has(texts, "Shared session"), table.concat(texts, ","))
    assertTrue(has(texts, "Incomplete (combat ended at 0:13)"), table.concat(texts, ","))
    assertEqual(S.NS.Format.RaceTime(race), "0:13 / 0:30")
end)

-- ── running ────────────────────────────────────────────────────────────────────────────────────

test("race window: the running clocks follow the race clock setting", function()
    if forever() then return end
    local S = fresh()
    assertEqual(S.NS.GetSetting("race.clock"), "left", "one countdown by default (ruling O2)")
    assertTrue(S.NS.SetByPath("race.clock", "both"))
    W(S).Show()
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 10, 1)
    W(S).Refresh()
    local w = body(S).w
    assertTrue(w.elapsed:IsShown() and w.left:IsShown(), "both clocks with the row on both")
    assertEqual(w.elapsed:GetText(), "0:10.0")
    assertEqual(w.left:GetText(), "0:20.0")
    assertTrue(S.NS.SetByPath("race.clock", "left"))
    assertFalse(w.elapsed:IsShown())
    assertTrue(w.single:IsShown())
    assertEqual(w.single:GetText(), "0:20.0")
    assertTrue(S.NS.SetByPath("race.clock", "elapsed"))
    assertTrue(w.singleElapsed:IsShown())
    assertFalse(w.single:IsShown())
end)

test("race window: the running body sets the race against the race board's best, with no pace bar", function()
    if forever() then return end
    local S = fresh()
    raced(S, 30)
    local best = F.records(S)[1]
    W(S).Act.newRace()
    assertTrue(F.arm(S, 30, 200))
    local start = F.pull(S, 201, 26)
    F.damage(S, 26, start + 1, start + 10, 1)
    F.run(S, start + 10.25)
    W(S).Refresh()
    local v = W(S).View()
    assertNil(v.pace, "no pace bar: the DPS HUD's alone (Task W6)")
    local w = body(S).w
    assertNil(w.pace, "no pace region")
    assertNil(w.paceTitle)
    assertEqual(v.bestView.record.id, best.id, "Best to beat: the race board's best")
    assertEqual(w.best.caption:GetText(), "Best to beat")
    assertEqual(w.best.damage:GetText(), S.NS.Format.Number(best.race.score))
    assertEqual(v.elapsed, S.NS.Format.RaceClock(10.25, 30), "the race clock, in tenths (0:10.2)")
    F.near(v.byNow, best.race.score / 30 * v.elapsed, "Best by now: the best's straight line at the race clock")
    assertEqual(w.now.value:GetText(), S.NS.Format.Number(v.byNow))
    assertEqual(w.now.cap.note:GetText(), "at 0:10")
    assertEqual(#v.checkpoints, 4)
    F.near(v.checkpoints[1].damage, best.race.score / 4, "the first quarter")
    assertTrue(v.checkpoints[1].passed, "0:07.5 is behind the clock")
    assertTrue(v.checkpoints[2].next, "0:15 is next")
    assertTrue(w.cps.cells[2].next and not w.cps.cells[1].next)
    assertEqual(w.cps.cells[4].time:GetText(), "0:30")
    assertEqual(w.ofCap:GetText(), "Left of 0:30", "the countdown's caption against the length")
    F.near(w.bar.share, v.elapsed / 30, "the time bar: elapsed over the length")
    assertEqual(w.bar.fillW, math.floor(body(S).width * (1 - w.bar.share)), "the bar: what is left, emptying")
    local r, g, b = S.NS.RaceWindowBoard.ClockColor(v.timeLeft, 30)
    local cr, cg, cb = w.single:GetTextColor()
    assertTrue(cr == r and cg == g and cb == b, "the countdown in the race's color")
    local tc = w.bar.fill.__color
    assertTrue(tc[1] == r and tc[2] == g and tc[3] == b, "the bar in the countdown's color")
    local G = S.NS.HudStates.COLORS.green
    assertTrue(r == G[1] and g == G[2] and b == G[3], "0:19.8 left of 0:30: green, in the first half")
    local SECTION = S.NS.Style.FONT.SECTION
    assertEqual(w.best.caption.__template, SECTION, "Best to beat: the DPS HUD's heading")
    assertEqual(w.now.cap.title.__template, SECTION, "Best by now too")
    assertEqual(w.cps.cap.title.__template, SECTION, "and the Checkpoints")
    local chips = w.chips:Texts()
    assertEqual(chips[1], S.NS.Dummies.Label(best.race.kind) .. " \194\183 0:30")
end)

-- A session of `damage`, for the live read to answer.
local function session(damage)
    return { damage = damage, dps = damage / 30, duration = 31, spells = { { id = 348, dmg = damage, dps = damage / 30 } } }
end

test("race window: Best by now and each Checkpoint show your damage, kept as the clock passes it", function()
    if forever() then return end
    local S = fresh()
    raced(S, 30)
    W(S).Act.newRace()
    assertTrue(F.arm(S, 30, 200))
    local start = F.pull(S, 201, 26, session(1000000))
    F.damage(S, 26, start + 1, start + 5, 1)
    W(S).Refresh()
    local w, v = body(S).w, W(S).View()
    local Fmt = S.NS.Format
    assertTrue(v.hasYou, "the DPS HUD's last read of the race's fight")
    assertEqual(w.now.you:GetText(), Fmt.Number(1000000), "Current beside Best")
    for i = 1, 4 do assertEqual(w.cps.cells[i].you:GetText(), "\226\128\148", "checkpoint " .. i .. ": a dash before it") end
    -- 0:07.5 goes by: the first checkpoint keeps the reading of that beat.
    F.damage(S, 26, start + 6, start + 8, 1)
    W(S).Refresh()
    assertEqual(w.cps.cells[1].you:GetText(), Fmt.Number(1000000), "captured at its crossing")
    assertEqual(w.cps.cells[2].you:GetText(), "\226\128\148")
    -- More damage after it: Best by now's Current moves on, the first checkpoint holds.
    S.meter.SetSession(26, session(2500000))
    F.damage(S, 26, start + 9, start + 11, 1)
    W(S).Refresh()
    assertEqual(w.now.you:GetText(), Fmt.Number(2500000))
    assertEqual(w.cps.cells[1].you:GetText(), Fmt.Number(1000000), "the crossing's reading kept")
    -- In combat the read is secret: it reaches the labels as it is, and the second crossing keeps it.
    S.meter.SetSecret(true)
    F.damage(S, 26, start + 12, start + 16, 1)
    W(S).Refresh()
    assertTrue(T.isSecret(w.now.you:GetText()), "the secret itself in Current (no formatter in the harness)")
    assertTrue(T.isSecret(w.cps.cells[2].you:GetText()), "and in the checkpoint it passed")
    assertEqual(w.cps.cells[1].you:GetText(), Fmt.Number(1000000))
    assertEqual(w.cps.cells[3].you:GetText(), "\226\128\148")
    S.meter.SetSecret(false)
    -- The result: the readings let go.
    F.damage(S, 26, start + 17, start + 30, 1)
    F.settle(S, start + 31)
    assertEqual(current(S), "result")
end)

test("race window: with no best on the board the running body says so and hides the best's line", function()
    if forever() then return end
    local S = fresh()
    W(S).Show()
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 10, 1)
    F.run(S, start + 10)
    W(S).Refresh()
    local v, w = W(S).View(), body(S).w
    assertEqual(v.bestView.state, "empty")
    assertNil(v.checkpoints)
    assertTrue(w.best.empty:IsShown())
    assertEqual(w.best.empty:GetText(), "No race yet: this one sets the mark.", "the idle card's empty words")
    assertFalse(w.now.card:IsShown(), "no Best by now")
    assertFalse(w.now.cap.title:IsShown())
    assertFalse(w.cps.cells[1]:IsShown(), "no Checkpoints")
    assertFalse(w.cps.cap.title:IsShown())
end)

test("race window: no live boxes, no chart and no spell rows in any body", function()
    if forever() then return end
    local S = fresh()
    W(S).Show()
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 30, 1)
    F.run(S, start + 33)
    F.settle(S, start + 34)
    local ui = W(S).__ui()
    local n = 0
    for key, b in pairs(ui.body) do
        n = n + 1
        for _, part in ipairs({ "chart", "rows", "list", "spellsTitle", "damage" }) do
            assertNil(b.w[part], key .. " draws " .. part)
        end
    end
    assertEqual(n, 6, "all six bodies were drawn")
end)

-- ── the shell ──────────────────────────────────────────────────────────────────────────────────

test("race window: it wears the HUD's skin and appearance", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local skinned = {}
    local apply = NS.ApplySkin
    NS.ApplySkin = function(f, ...)
        skinned[f] = true
        return apply(f, ...)
    end
    local ui = W(S).__ui()
    if ui then skinned[ui.frame] = true end   -- built at login by auto-show, before the spy
    W(S).Show()
    ui = W(S).__ui()
    assertTrue(skinned[ui.frame], "the window takes the skin's shell")
    local strata
    rawset(ui.frame, "SetFrameStrata", function(_, s) strata = s end)
    NS.db.profile.hud.window.strata = "HIGH"
    NS.db.profile.hud.window.alpha = 0.6
    NS.HudAppearance.Changed()
    assertEqual(strata, "HIGH", "the HUD's strata")
    F.near(ui.frame:GetAlpha(), 0.6, "the HUD's opacity")
    NS.db.profile.hud.window.titleBar = false
    NS.HudAppearance.Changed()
    assertFalse(ui.lock:IsShown(), "the HUD's title bar switch")
    assertFalse(ui.frame.title:IsShown())
end)

test("race window: attached, it stands flush beside the HUD on each side and moves with it", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    RW.Show()
    local hud = S.NS.Hud.Frame()
    local want = {
        RIGHT  = { "TOPLEFT", "TOPRIGHT", 0, 0 },
        LEFT   = { "TOPRIGHT", "TOPLEFT", 0, 0 },
        TOP    = { "BOTTOMLEFT", "TOPLEFT", 0, 0 },
        BOTTOM = { "TOPLEFT", "BOTTOMLEFT", 0, 0 },
    }
    -- Flush on every side (race window redesign plan Task W4): no gap between the two windows.
    assertEqual(RW.DOCK_GAP, 0)
    assertTrue(RW.IsAttached(), "attached by default")
    local a = RW.Anchor()
    assertEqual(a[2], hud, "anchored to the DPS HUD's frame, so it moves with it")
    assertEqual(a[1], "TOPLEFT")
    for _, side in ipairs({ "LEFT", "TOP", "BOTTOM", "RIGHT" }) do
        RW.Attach(side)
        a = RW.Anchor()
        assertEqual(a[2], hud, side)
        assertEqual(a[1], want[side][1], side .. " point")
        assertEqual(a[3], want[side][2], side .. " the HUD's point")
        assertEqual(a[4], want[side][3], side .. " x")
        assertEqual(a[5], want[side][4], side .. " y")
    end
    assertEqual(S.NS.GetSetting("raceWindow.side"), "RIGHT", "Attach writes the side through the seam")
    S.NS.Hud.ResetPosition()
    assertEqual(RW.Anchor()[2], S.NS.Hud.Frame(), "the HUD moved: still beside it")
end)

test("race window: attached with the HUD hidden it stands where the HUD would", function()
    if forever() then return end
    -- The kit's frames keep no anchors or size: each named frame records its own here.
    local geom = {}
    local S = fresh({ mutate = function(m)
        local create = m.CreateFrame
        m.CreateFrame = function(kind, name, ...)
            local f = create(kind, name, ...)
            if type(name) ~= "string" then return f end
            local g = { points = {} }
            geom[name] = g
            rawset(f, "SetPoint", function(_, ...) g.points[#g.points + 1] = { ... } end)
            rawset(f, "ClearAllPoints", function() g.points = {} end)
            rawset(f, "SetSize", function(_, w, h) g.w, g.h = w, h end)
            return f
        end
    end })
    local Hud = S.NS.Hud
    assertFalse(Hud.IsShown(), "the HUD is shut")
    -- The Race window never stands without the HUD (W29), but Hud.Dock still builds and places a
    -- hidden HUD, so nothing that reads it can fall to 0,0.
    local hud = Hud.Dock()
    assertTrue(hud ~= nil and hud == Hud.Frame(), "the HUD's frame is built to stand beside")
    assertFalse(hud:IsShown(), "and stays hidden")
    assertTrue(Hud.__ui().docked, "placed and sized where the HUD would stand")
    -- A frame with no anchor and no size has no rect, and a window anchored to it has none either.
    local g = geom[Hud.FRAME_NAME]
    assertTrue(#g.points >= 1, "the hidden HUD is anchored")
    local point, rel, relPoint, x, y = unpack(g.points[#g.points])
    assertEqual(point, "TOPRIGHT", "at the HUD's own place")
    assertEqual(rel, S.M.UIParent)
    assertEqual(relPoint, "TOPRIGHT")
    assertEqual(x, -60)
    assertEqual(y, -160)
    assertTrue((g.w or 0) > 0 and (g.h or 0) > 0, "and sized")
    W(S).Show()
    assertTrue(Hud.IsShown(), "the Race window's open opened the HUD first (W29 decision D3)")
    assertEqual(W(S).Anchor()[2], hud, "beside it")
    Hud.Hide()
    W(S).Refresh()
    assertEqual(W(S).Anchor()[2], hud, "a HUD closed by hand keeps its place")
end)

test("race window: a HUD that drew once, hidden, is placed again for the window beside it", function()
    if forever() then return end
    local geom = {}
    local S = fresh({ mutate = function(m)
        local create = m.CreateFrame
        m.CreateFrame = function(kind, name, ...)
            local f = create(kind, name, ...)
            if type(name) ~= "string" then return f end
            local g = { points = {} }
            geom[name] = g
            rawset(f, "SetPoint", function(_, ...) g.points[#g.points + 1] = { ... } end)
            rawset(f, "ClearAllPoints", function() g.points = {} end)
            rawset(f, "SetSize", function(_, w, h) g.w, g.h = w, h end)
            rawset(f, "SetWidth", function(_, w) g.w = w end)
            return f
        end
    end })
    local Hud = S.NS.Hud
    Hud.Show()
    Hud.Hide()
    assertTrue(Hud.__ui().rendered, "the HUD drew once")
    local p = S.NS.db.profile.hud.position
    p.point, p.relPoint, p.x, p.y = "TOPLEFT", "TOPLEFT", 40, -80   -- a profile with its own HUD place
    assertTrue(S.NS.SetByPath("hud.width", 420))
    W(S).Show()
    local g = geom[Hud.FRAME_NAME]
    local point, _, relPoint, x, y = unpack(g.points[#g.points])
    assertEqual(point, "TOPLEFT", "at this profile's HUD place")
    assertEqual(relPoint, "TOPLEFT")
    assertEqual(x, 40)
    assertEqual(y, -80)
    assertEqual(g.w, 420, "at this profile's HUD width")
end)

-- ── the HUD's height, docked beside it (race window redesign plan Task W4) ──────────────────────

-- A fresh instance whose named frames (the HUD's and the Race window's) record the size and scale
-- the code sets: the kit's frames answer no geometry unless armed.
local function sized()
    local geom = {}
    local S = fresh({ mutate = function(m)
        local create = m.CreateFrame
        m.CreateFrame = function(kind, name, ...)
            local f = create(kind, name, ...)
            if type(name) ~= "string" then return f end
            local g = {}
            geom[name] = g
            rawset(f, "SetSize", function(_, w, h) g.w, g.h = w, h end)
            rawset(f, "SetWidth", function(_, w) g.w = w end)
            rawset(f, "SetHeight", function(_, h) g.h = h end)
            rawset(f, "SetScale", function(_, v) g.scale = v end)
            return f
        end
    end })
    S.NS.Hud.Show()
    W(S).Show()
    return S, geom[S.NS.Hud.FRAME_NAME], geom[W(S).FRAME_NAME]
end

local function chromeOf(S)
    return S.NS.Style.TITLE_BAR_H + 10 + 20 + 8
end

test("race window: docked LEFT or RIGHT it takes the DPS HUD's height", function()
    if forever() then return end
    local S, hud, win = sized()
    local RW = W(S)
    assertTrue(S.NS.GetSetting("raceWindow.matchHud"), "on by default")
    assertTrue(hud.h > RW.Height(), "the default HUD is taller than the window's own minimum")
    for _, side in ipairs({ "RIGHT", "LEFT" }) do
        RW.Attach(side)
        assertEqual(win.h, hud.h, side .. ": the HUD's height")
        assertEqual(win.h, S.NS.Hud.Height(), side)
    end
    -- The bodies lay out against the height the window has: the content is the window less its chrome.
    assertEqual(RW.View().height, win.h - chromeOf(S), "the body's room is the matched height's")
end)

test("race window: the matched height follows the HUD's resizes, its parts, the grip and the scale", function()
    if forever() then return end
    local S, hud, win = sized()
    local NS, Hud = S.NS, S.NS.Hud
    local before = hud.h
    assertTrue(NS.SetByPath("hud.bars", 12))
    assertTrue(hud.h > before, "more spell bars: a taller HUD")
    assertEqual(win.h, hud.h, "the window follows the bars")
    NS.db.profile.hud.window.footer = false
    NS.HudAppearance.Changed()
    assertEqual(win.h, hud.h, "the footer off on both: still level")
    NS.db.profile.hud.window.titleBar = false
    NS.HudAppearance.Changed()
    assertEqual(win.h, hud.h, "the title bar off on both: still level")
    -- The grip, held: the window follows the dragged height; released, the snapped one.
    local f = Hud.Frame()
    f.resizeGrip:__fire("OnMouseDown", "LeftButton")
    S.M.__now = S.M.__now + 1 / 60
    local dragged = Hud.FixedHeight() - 47
    f:__fire("OnSizeChanged", 300, dragged)
    assertEqual(Hud.Height(), dragged, "the HUD's height while the grip is held")
    assertEqual(win.h, dragged, "the window follows the drag")
    f:__setGeom(300, dragged)
    f.resizeGrip:__fire("OnMouseUp")
    assertEqual(win.h, hud.h, "released: the snapped height")
    assertTrue(NS.SetByPath("hud.scale", 1.2))
    assertEqual(win.scale, hud.scale, "one scale for both, so equal heights line up")
    assertEqual(win.h, hud.h, "rescaled: still level")
end)

test("race window: a HUD shorter than the window's minimum leaves the minimum", function()
    if forever() then return end
    local S, hud, win = sized()
    local layout = S.NS.db.profile.hud.layout
    layout.pace, layout.chart, layout.spells = false, false, false
    S.NS.Hud.Apply()
    assertTrue(hud.h < W(S).Height(), "a short HUD: " .. tostring(hud.h))
    assertEqual(win.h, W(S).Height(), "never shorter than the tallest body needs")
end)

test("race window: TOP, BOTTOM, detached or the row off keep the window's own height", function()
    if forever() then return end
    local S, hud, win = sized()
    local RW = W(S)
    for _, side in ipairs({ "TOP", "BOTTOM" }) do
        RW.Attach(side)
        assertEqual(win.h, RW.Height(), side)
    end
    RW.Attach("RIGHT")
    assertEqual(win.h, hud.h)
    RW.Detach()
    assertEqual(win.h, RW.Height(), "detached")
    RW.Attach("LEFT")
    assertTrue(S.NS.SetByPath("raceWindow.matchHud", false))
    assertEqual(win.h, RW.Height(), "Match the DPS HUD's height off")
    assertTrue(S.NS.SetByPath("hud.bars", 14))
    assertEqual(win.h, RW.Height(), "and a HUD resize leaves it")
    assertEqual(RW.View().height, RW.Height() - chromeOf(S))
end)

test("race window: unticking Attach in the settings keeps it where it stands, as Detach does", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    RW.Show()
    assertTrue(RW.IsAttached())
    local ui = RW.__ui()
    rawset(ui.frame, "GetLeft", function() return 700.4 end)
    rawset(ui.frame, "GetTop", function() return 500.6 end)
    assertTrue(S.NS.SetByPath("raceWindow.attached", false))
    local a = RW.Anchor()
    assertEqual(a[1], "TOPLEFT", "where it stood, not the default place")
    assertEqual(a[2], S.M.UIParent)
    assertEqual(a[3], "BOTTOMLEFT")
    assertEqual(a[4], 700)
    assertEqual(a[5], 501)
end)

test("race window: detached, it keeps its own place across a reload", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    RW.Show()
    RW.Detach()
    assertFalse(RW.IsAttached())
    local a = RW.Anchor()
    assertEqual(a[1], "CENTER")
    assertEqual(a[2], S.M.UIParent)
    assertEqual(a[5], 160, "the default detached place")
    local ui = RW.__ui()
    rawset(ui.frame, "GetPoint", function() return "TOPLEFT", S.M.UIParent, "BOTTOMLEFT", 400.4, 600.6 end)
    ui.drag:__fire("OnDragStop")
    local R = F.reload(S)
    R.NS.RaceWindow.Show()
    a = R.NS.RaceWindow.Anchor()
    assertFalse(R.NS.RaceWindow.IsAttached())
    assertEqual(a[1], "TOPLEFT")
    assertEqual(a[3], "BOTTOMLEFT")
    assertEqual(a[4], 400)
    assertEqual(a[5], 601)
    R.NS.RaceWindow.ResetPosition()
    assertEqual(R.NS.RaceWindow.Anchor()[1], "CENTER", "Reset position puts the default back")
end)

test("race window: locked, or attached, its title bar drags nothing", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    RW.Show()
    local ui = RW.__ui()
    local moved = 0
    rawset(ui.frame, "StartMoving", function() moved = moved + 1 end)
    ui.drag:__fire("OnDragStart")
    assertEqual(moved, 0, "attached: it moves with the HUD")
    RW.Detach()
    ui.drag:__fire("OnDragStart")
    assertEqual(moved, 1, "detached and unlocked")
    assertTrue(S.NS.SetByPath("general.locked", true))
    assertTrue(RW.IsLocked())
    ui.drag:__fire("OnDragStart")
    assertEqual(moved, 1, "locked")
end)

-- ── when it shows ──────────────────────────────────────────────────────────────────────────────

test("race window: auto-show near a dummy, the debounced close, and the player's close counted", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    assertTrue(RW.ShowNearDummy())
    assertTrue(RW.IsShown())
    assertTrue(RW.ShownNearDummy())
    assertFalse(RW.ShowNearDummy(), "already up")
    assertTrue(RW.HideAwayFromDummy())
    assertFalse(RW.IsShown())
    RW.Show()
    assertFalse(RW.HideAwayFromDummy(), "the player's window is not auto-show's to close")
    RW.Act.close()
    assertEqual(RW.Closes(), 1)
end)

test("race window: an arm opens it, and it closes when that race goes back to idle; the player's stays", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    assertTrue(F.arm(S, 30))
    assertTrue(RW.IsShown(), "the arm opens it")
    S.NS.Race.Cancel()
    assertFalse(RW.IsShown(), "the addon's window closes with the race")
    RW.Show()
    assertTrue(F.arm(S, 30))
    S.NS.Race.Cancel()
    assertTrue(RW.IsShown(), "the player's window stays")
end)

test("race window: with Race mode off it stays hidden", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    assertTrue(S.NS.SetByPath("race.enabled", false))
    RW.Show()
    assertFalse(RW.IsShown())
    local ui = RW.__ui()
    assertFalse(ui ~= nil and ui.frame:IsShown(), "not on screen")
end)

test("race window: it has no timer of its own; the race beat redraws it while racing and shown", function()
    if forever() then return end
    local S = fresh()
    local RW, RC = W(S), S.NS.RaceClock
    RW.Show()
    assertTrue(RW.Diagnose().events, "idle: the target and regen events")
    assertNil(RW.TICK, "no clock rate of its own (race window redesign plan Task W5)")
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    assertTrue(RC.On(), "racing: the race beat runs")
    assertFalse(RW.Diagnose().events, "racing: no idle events")
    -- One repeating 0.1 s timer while the window is up: the beat's, never one of the window's.
    local n = 0
    for _, t in ipairs(S.M.__timers) do
        if t.timer and t.timer.looping and t.timer.delay == RC.TICK then n = n + 1 end
    end
    assertEqual(n, 1, "the race beat is the only 0.1 s timer")
    F.at(S, start + 3)
    RC.__beat()
    assertTrue(math.abs(RW.View().elapsed - 3) < 1e-6, "the beat redrew the race clock")
    RW.Hide()
    F.at(S, start + 4)
    RC.__beat()
    assertTrue(math.abs(RW.View().elapsed - 3) < 1e-6, "hidden: the beat draws nothing")
    RW.Show()
    assertTrue(S.NS.SetByPath("general.enabled", false))
    assertFalse(RC.On(), "stood down: no beat")
    assertFalse(RW.Diagnose().events, "stood down: no events")
    assertFalse(RW.__ui().frame:IsShown(), "stood down: hidden")
end)

-- ── the DPS HUD during a race (ruling X7) ──────────────────────────────────────────────────────

test("race window: a race opens the DPS HUD whatever its own rules say; a plain fight does not", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    NS.db.profile.hud.instancesOnly = true
    local start = F.pull(S)
    F.run(S, start + 0.25)
    assertFalse(NS.Hud.IsShown(), "a plain dummy fight in the open world: the HUD stays shut")
    F.settle(S, start + 5)
    NS.db.profile.hud.show = "toggle"
    assertTrue(F.arm(S, 30, 120))
    local s2 = F.pull(S, 121, 26)
    F.run(S, s2 + 0.25)
    assertTrue(NS.Hud.IsShown(), "a race opens it")
end)

-- ── the last checkpoint, taken at the buzzer (owner, 2026-11-13) ───────────────────────────────

test("race window: the buzzer takes the last checkpoint with the DPS HUD's last read, so all four show", function()
    if forever() then return end
    local S = fresh()
    raced(S, 30)
    W(S).Act.newRace()
    assertTrue(F.arm(S, 30, 200))
    local start = F.pull(S, 201, 26, session(1000000))
    F.damage(S, 26, start + 1, start + 28, 1)
    S.meter.SetSession(26, session(3000000))
    F.hit(S, start + 29.5, 26)
    F.run(S, start + 29.5)
    W(S).Refresh()
    local v = W(S).View()
    assertEqual(v.key, "running")
    assertTrue(v.checkpoints[3].hasYou, "the third quarter taken on its beat")
    assertFalse(v.checkpoints[4].passed, "the last one is the buzzer's")
    assertFalse(v.checkpoints[4].hasYou, "no reading before it")
    F.run(S, start + 30)
    assertEqual(S.NS.Race.State(), "stopping")
    v = W(S).View()
    assertTrue(v.key == "stop" or v.key == "waiting", "the stopping body")
    assertEqual(#v.checkpoints, 4)
    for i = 1, 4 do
        assertTrue(v.checkpoints[i].passed, "checkpoint " .. i .. " passed")
        assertTrue(v.checkpoints[i].hasYou, "checkpoint " .. i .. " has your reading")
    end
    assertEqual(v.checkpoints[4].you, 3000000, "the last one is the HUD's last read")
    assertEqual(v.checkpoints[1].you, 1000000, "the first quarter's own reading kept")
    -- The stopping beats move nothing: the readings are held.
    S.meter.SetSession(26, session(9000000))
    F.hit(S, start + 30.5, 26)
    F.run(S, start + 31)
    assertEqual(W(S).View().checkpoints[4].you, 3000000, "held through the stop")
end)

test("race window: a race ending early takes no checkpoint past its end", function()
    if forever() then return end
    local S = fresh()
    raced(S, 30)
    W(S).Act.newRace()
    assertTrue(F.arm(S, 30, 200))
    local start = F.pull(S, 201, 26, session(1000000))
    F.damage(S, 26, start + 1, start + 18, 1)
    F.leave(S, start + 18)
    F.run(S, start + 18.1)
    assertEqual(S.NS.Race.State(), "stopping")
    local v = W(S).View()
    assertTrue(v.checkpoints[2].hasYou, "0:15 was passed")
    assertFalse(v.checkpoints[3].passed or v.checkpoints[3].hasYou, "0:22.5 never came")
    assertFalse(v.checkpoints[4].passed or v.checkpoints[4].hasYou, "nor the buzzer")
end)

-- ── the pet's own source: the pace bars' player-only reference (owner, 2026-11-13) ─────────────

-- A second race, 30 s, with the best's record split half player, half pet; the DPS HUD's read
-- answered as `petOwn` says (the pet on a live source of its own, or not).
local function petRace(petOwn, player)
    local S = fresh()
    raced(S, 30)
    local best = F.records(S)[1]
    best.damage.player = player and best.damage.merged * player or nil
    W(S).Act.newRace()
    assertTrue(F.arm(S, 30, 200))
    local start = F.pull(S, 201, 26, session(1000000))
    F.damage(S, 26, start + 1, start + 5, 1)
    local live = S.NS.Hud.LiveDamage
    S.NS.Hud.LiveDamage = function(fight)
        local total, present = live(fight)
        return total, present, petOwn
    end
    F.damage(S, 26, start + 6, start + 10, 1)
    W(S).Refresh()
    return S, best, W(S).View()
end

test("race window pet: with the pet on its own source the pace bars take the best's player-only line", function()
    if forever() then return end
    local S, best, v = petRace(true, 0.5)
    local score = best.race.score
    F.near(v.paceRef, score * 0.5 * v.elapsed / 30, "Best by now's player-only figure at the race clock")
    F.near(v.byNow, score * v.elapsed / 30, "Best by now itself stays the best's whole figure")
    F.near(v.checkpoints[1].paceRef, score * 0.5 * 7.5 / 30, "the checkpoint the clock passed")
    assertNil(v.checkpoints[2].paceRef, "a checkpoint not reached has none")
    assertTrue(type(v.paceRef) == "number" and not T.isSecret(v.paceRef), "plain")
    assertNil(S.NS.Hud.Diagnose().clockEvery, "the race beat draws the HUD's clock, not its own")
end)

test("race window pet: no pet source, or a best with no player-only figure, gives no paceRef", function()
    if forever() then return end
    local _, _, v = petRace(false, 0.5)
    assertNil(v.paceRef, "the player's total is the merged one: the best's whole figure")
    assertNil(v.checkpoints[1].paceRef)
    _, _, v = petRace(true, nil)
    assertNil(v.paceRef, "no player-only figure stored: none made up")
    assertNil(v.checkpoints[1].paceRef)
end)
