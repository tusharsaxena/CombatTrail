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
    -- Auto-show off, and the window it opened at login (the player targets a dummy) let go: each case
    -- opens the window itself. The auto-show hooks have their own case below.
    assert(S.NS.SetByPath("race.autoShow", false))
    S.NS.RaceWindow.HideAwayFromDummy()
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

-- ── idle ───────────────────────────────────────────────────────────────────────────────────────

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
    assertFalse(w.pace.bar:IsShown(), "no earlier best: no pace bar")
    assertFalse(w.paceTitle:IsShown())
end)

test("race window: a slower second race is behind its best, and its pace bar is the score against it", function()
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
    assertTrue(chips[1]:find("vs best", 1, true) ~= nil, chips[1])
    assertEqual(v.pace.total, 1000000)
    local lo, hi = S.NS.HudBest.Bounds(first.race.score)
    F.near(v.pace.lo, lo, "the bar's low end")
    F.near(v.pace.hi, hi, "the bar's high end")
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
    W(S).Show()
    assertTrue(F.arm(S, 30))
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 10, 1)
    W(S).Refresh()
    local w = body(S).w
    assertTrue(w.elapsed:IsShown() and w.left:IsShown(), "both clocks by default")
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

test("race window: the running pace bar paces on the race board's best", function()
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
    assertTrue(v.pace ~= nil, "paced against the race board's best")
    F.near(v.pace.ref, best.race.score / 30 * 10.25, "the best's straight-line pace at the race clock")
    assertTrue(body(S).w.pace.bar:IsShown())
    local chips = body(S).w.chips:Texts()
    assertEqual(chips[1], S.NS.Dummies.Label(best.race.kind) .. " \194\183 0:30")
end)

test("race window: with a pet the meter reads apart, the player's total paces on the best's player share", function()
    if forever() then return end
    local PET = "Pet-0-1-2-3-4"
    local S = fresh({ mutate = function(m)
        m.__unitExists.pet = true
        m.__unitGUIDs.pet = PET
        m.__unitNames.pet = "Wolf"
    end })
    S.meter.SetPetGUID(PET)
    local session = { damage = 30000, dps = 1000, duration = 30, spells = { { id = 133, dmg = 30000, dps = 1000 } },
                      pet = { damage = 30000, dps = 1000, spells = { { id = 17253, dmg = 30000, dps = 1000 } } } }
    W(S).Show()
    assertTrue(F.arm(S, 30))
    local s1 = F.pull(S, 101, 25, session)
    F.damage(S, 25, s1 + 1, s1 + 30, 1)
    F.settle(S, s1 + 31)
    local best = F.records(S)[1]
    assertEqual(best.race.status, "complete")
    local share = best.damage.player / best.damage.merged
    assertTrue(share < 1, "the best's pet did part of its damage")
    W(S).Act.newRace()
    assertTrue(F.arm(S, 30, 200))
    local start = F.pull(S, 201, 26, session)
    F.damage(S, 26, start + 1, start + 10, 1)
    F.run(S, start + 10.25)
    W(S).Refresh()
    local v = W(S).View()
    assertTrue(v.pace ~= nil and v.pace.playerOnly, "the live total is the player's alone")
    F.near(v.pace.ref, best.race.score * share / 30 * 10.25, "against the best's player damage, not its merged score")
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

test("race window: attached, it stands beside the HUD on each side and moves with it", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    RW.Show()
    local hud = S.NS.Hud.Frame()
    local want = {
        RIGHT  = { "TOPLEFT", "TOPRIGHT", 4, 0 },
        LEFT   = { "TOPRIGHT", "TOPLEFT", -4, 0 },
        TOP    = { "BOTTOMLEFT", "TOPLEFT", 0, 4 },
        BOTTOM = { "TOPLEFT", "BOTTOMLEFT", 0, -4 },
    }
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
    W(S).Show()
    local hud = Hud.Frame()
    assertTrue(hud ~= nil, "the HUD's frame is built to stand beside")
    assertFalse(hud:IsShown(), "and stays hidden")
    assertTrue(Hud.__ui().docked, "placed and sized where the HUD would stand")
    assertEqual(W(S).Anchor()[2], hud)
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
    Hud.Show()
    Hud.Hide()
    W(S).Refresh()
    assertEqual(W(S).Anchor()[2], hud, "a HUD closed by hand keeps its place")
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

test("race window: the clock's timer runs only while racing and shown, and the stand-down drops all of it", function()
    if forever() then return end
    local S = fresh()
    local RW = W(S)
    RW.Show()
    assertFalse(RW.Diagnose().ticking)
    assertTrue(RW.Diagnose().events, "idle: the target and regen events")
    assertTrue(F.arm(S, 30))
    F.pull(S)
    assertTrue(RW.Diagnose().ticking, "racing: the clock ticks")
    assertFalse(RW.Diagnose().events, "racing: no idle events")
    RW.Hide()
    assertFalse(RW.Diagnose().ticking, "hidden: no tick")
    RW.Show()
    assertTrue(RW.Diagnose().ticking)
    assertTrue(S.NS.SetByPath("general.enabled", false))
    assertFalse(RW.Diagnose().ticking, "stood down: no tick")
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
