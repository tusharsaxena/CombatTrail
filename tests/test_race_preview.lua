-- tests/test_race_preview.lua — Race mode's test mode (race plan Task E1, R:test-sim#1-#4, #8, #12):
-- DPS Race's preview cases (@f8078c7 tests/test_preview.lua, test_sample_parity.lua) on Combat Trail's
-- test mode. `/ct test race [armed|running|result]` holds a sample race (modules/RaceSample.lua) on the
-- Race window, the HUD and the lanes; the sample history holds races beside the fights
-- (modules/MockRaces.lua); a real race's arm ends it, a real race refuses it, and nothing of it reaches
-- the store or NS.Race. On WoW Forever every race part is absent (clients-§4): its last case.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local F = dofile(T.root .. "/tests/race_fixture.lua")(T)
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local function forever() return T.NS.Compat.IsForever() end

local function fresh()
    local S = F.fresh({ mutate = function(m) installPaint(m) end })
    if S.NS.RaceWindow then
        assert(S.NS.SetByPath("race.autoShow", false))
        assert(S.NS.SetByPath("race.autoShowHud", false))   -- either row is auto-show (W29 decision D4)
        S.NS.RaceWindow.HideAwayFromDummy()
        S.NS.Hud.HideAwayFromDummy()
    end
    S.M.__now = 1000
    return S
end

local function slash(S, line) S.NS.Slash:OnSlash(line) end

local function prints(S)
    local lines = {}
    S.NS.Print = function(line) lines[#lines + 1] = line end
    return lines
end

local function has(list, want)
    for _, s in ipairs(list) do
        if type(s) == "string" and s:find(want, 1, true) then return true end
    end
    return false
end

local function current(S)
    local ui = S.NS.RaceWindow.__ui()
    return S.NS.RaceWindow.IsShown() and ui and ui.current or nil
end

local function beats(S, n)
    for _ = 1, n do
        S.M.__now = S.M.__now + 0.25
        S.M.__fireTimers()
    end
end

-- Nothing the sample race drew reached SavedVariables, and the real race never moved.
local function untouched(S)
    local g = S.NS.db.global
    assertEqual(next(g.fights or {}), nil, "a sample reached the store")
    assertEqual(next(g.pendingRaces or {}), nil, "a sample race reached the pending slots")
    assertEqual(S.NS.Race.State(), "idle", "the real race moved")
end

test("race preview: /ct test race holds the sample race running on the Race window and the HUD", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    slash(S, "test race")
    assertEqual(NS.Preview.Mode(), "test")
    assertTrue(NS.IsTestMode(), "through the Test mode row, so the box follows")
    assertEqual(NS.Preview.RaceState(), "running", "running when no state is named")
    assertEqual(current(S), "running", "the Race window opens on the running body")
    local v = NS.RaceWindow.View()
    assertEqual(v.elapsed, NS.Preview.RACE_STILL_AT, "the race clock holds still")
    assertEqual(v.timeLeft, NS.MockRaces.LENGTH - NS.Preview.RACE_STILL_AT)
    local best = v.bestView.record
    assertTrue(best ~= nil and best.race.sample, "Best to beat: its race board's best in the sample history")
    F.near(v.byNow, best.race.score * v.elapsed / best.race.length, "Best by now: the sample best's straight line")
    assertEqual(#v.checkpoints, 4, "the Checkpoints draw by the same path")
    -- The DPS HUD: the race's fight, live, paced on the race board (a race record).
    assertEqual(NS.Hud.State(), "live")
    local hv = NS.Hud.View()
    assertTrue(hv.fight ~= nil and hv.fight.race ~= nil and hv.fight.sample, "the HUD holds the sample race's fight")
    assertTrue(NS.RaceRecord.IsRace(hv.pace), "the HUD paces on the race board, against a sample race")
    assertTrue(#NS.LaneRender.__icons("player") > 0, "the lanes play its rotation")
    beats(S, 40)
    assertEqual(NS.RaceWindow.View().elapsed, NS.Preview.RACE_STILL_AT, "time passes; the clock stands")
    assertNil(NS.Countdown.Shown(), "a held race counts nothing down")
    assertEqual(NS.Countdown.Diagnose().scheduled, 0)
    untouched(S)
    slash(S, "test")
    assertFalse(NS.Preview.IsActive())
    assertFalse(NS.RaceSample.On(), "the sample race goes")
    assertFalse(NS.RaceWindow.IsShown(), "the window the sample opened closes")
    untouched(S)
end)

test("race preview: each state word holds its body, and in test mode switches it in place", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    slash(S, "test race armed")
    assertEqual(current(S), "armed")
    assertEqual(NS.RaceWindow.View().length, NS.MockRaces.LENGTH)
    assertEqual(NS.Preview.Diagnose().phase, "race armed")
    slash(S, "test race result")
    assertEqual(NS.Preview.Mode(), "test", "still test mode")
    assertEqual(current(S), "result")
    local v = NS.RaceWindow.View()
    assertTrue(v.record ~= nil and v.record.sample == true, "the sample race's record")
    assertTrue(v.isNew == true and type(v.delta) == "number" and v.delta > 0, "a new best over the sample history's")
    assertTrue(NS.ResultsSource.Get("test-race") ~= nil, "the race joins the sample history")
    assertEqual(NS.Hud.State(), "over", "the HUD holds its over card")
    local _, key = NS.BestToast.Instance():Current()
    assertEqual(key, NS.TOAST_PREVIEW, "the new-best toast shows as the preview")
    slash(S, "test race running")
    assertEqual(current(S), "running")
    assertNil(NS.ResultsSource.Get("test-race"), "a held state's history is that moment's")
    local _, after = NS.BestToast.Instance():Current()
    assertTrue(after ~= NS.TOAST_PREVIEW, "the preview's toast went with the result")
    untouched(S)
    NS.Preview.Stop()
end)

test("race preview: an unknown word prints the usage; Race mode off refuses the race word", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local lines = prints(S)
    slash(S, "test race banana")
    assertTrue(has(lines, "test race [armed|running|result]"), "the usage line")
    assertFalse(NS.Preview.IsActive())
    assert(NS.SetByPath("race.enabled", false))
    slash(S, "test race")
    assertTrue(has(lines, "Race mode is off"), "one line")
    assertFalse(NS.Preview.IsActive(), "no sample race with Race mode off")
    slash(S, "test")
    assertTrue(NS.Preview.IsActive(), "plain test mode still works")
    NS.Preview.Stop()
end)

test("race preview: arming a real race ends test mode and hands it the Race window", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local lines = prints(S)
    slash(S, "test race running")
    assertTrue(NS.RaceWindow.IsShown())
    assertTrue(F.arm(S, 30, S.M.__now))
    assertFalse(NS.Preview.IsActive(), "the arm ends test mode")
    assertTrue(has(lines, "Test mode ended: a race was armed."))
    assertFalse(NS.RaceSample.On())
    assertFalse(NS.ResultsSource.IsMock(), "the Results window has the store back")
    assertEqual(current(S), "armed", "the window is the real race's now")
    NS.Race.Cancel()
    assertFalse(NS.RaceWindow.IsShown(), "and closes with it")
end)

test("race preview: a start during a real race is refused", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local lines = prints(S)
    assertTrue(F.arm(S, 30, S.M.__now))
    slash(S, "test race")
    assertTrue(has(lines, "Test mode is not available during a race."))
    assertFalse(NS.Preview.IsActive())
    slash(S, "test")
    assertFalse(NS.Preview.IsActive(), "plain test mode too")
    assertEqual(NS.Race.State(), "armed", "the real race is untouched")
end)

test("race preview: the sample card's acts never touch the real race", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    slash(S, "test race result")
    NS.RaceWindow.Act.newRace()
    assertFalse(NS.RaceSample.On(), "New Race lets the sample card go")
    assertEqual(current(S), "idle", "the Arm Race screen")
    assertTrue(NS.Preview.IsActive(), "test mode stays")
    assertEqual(NS.RaceWindow.ArmLength(), NS.Race.DefaultLength(), "the player's length is left alone")
    slash(S, "test race result")
    -- A delete of the sample race (the Results window's own) takes its card away.
    assertTrue(NS.ResultsSource.Delete("test-race"))
    assertFalse(NS.RaceSample.On(), "a deleted sample race's card goes")
    slash(S, "test race result")
    NS.RaceWindow.Act.close()
    assertFalse(NS.Preview.IsActive(), "closing the sample's result card ends test mode")
    untouched(S)
end)

-- A sample race is a sample record in the shape a race leaves.
local function sampleShape(NS, r)
    local race = r.race
    assertTrue(r.sample == true and NS.Recorder.Known(r), r.id .. " is a sample record")
    assertEqual(r.identity.content, "dummy", r.id .. " is fought on a dummy")
    assertEqual(race.score, r.damage.merged, r.id .. ": the score is the whole damage")
    assertEqual(race.dps, NS.RaceRecord.ScoreDps(race.score, race), r.id .. ": the race DPS")
    assertNil(F.findSecret(r), r.id .. " holds no secret")
end

-- The races with a late cast: one counted (flagged) and one Hearthstone (ignored).
local function lateRaces(races)
    local flagged, hearth
    for _, r in ipairs(races) do
        local late = r.race.flags.lateCasts
        if late and late[1].spellID == 8690 then hearth = r elseif late then flagged = r end
    end
    return flagged, hearth
end

test("race preview: the sample history holds races beside the fights, every status, kind and length", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local data = NS.MockFights.Dataset()
    local races, kinds, lengths, statuses, flags = {}, {}, {}, {}, {}
    for _, r in ipairs(data.fights) do
        if NS.RaceRecord.IsRace(r) then
            races[#races + 1] = r
            local race = r.race
            kinds[race.kind], lengths[race.length], statuses[race.status] = true, true, true
            for k in pairs(race.flags) do flags[k] = true end
            sampleShape(NS, r)
        end
    end
    assertEqual(#races, #NS.MockRaces.HISTORY, "every sample race")
    for _, k in ipairs(NS.Dummies.CATEGORIES) do assertTrue(kinds[k], "kind " .. k) end
    for _, n in ipairs(NS.Race.LENGTHS) do assertTrue(lengths[n], "length " .. n) end
    assertTrue(statuses.complete and statuses.incomplete, "both statuses")
    for _, k in ipairs({ "lateCasts", "died", "sharedSession", "restartedAt" }) do assertTrue(flags[k], "flag " .. k) end
    -- A late cast sits in the race's own casts, past the buzzer; a late Hearthstone flags nothing.
    local flagged, hearth = lateRaces(races)
    assertTrue(NS.RaceRecord.Flagged(flagged), "a counted late cast flags the race")
    assertFalse(NS.RaceRecord.Flagged(hearth), "the ignore list's Hearthstone leaves it clean")
    local want = NS.MockFights.FIRST_HIT + flagged.race.length + flagged.race.flags.lateCasts[1].t
    local found = false
    for _, c in ipairs(NS.CastCodec.Decode(flagged.casts)) do
        if math.abs(c.t - want) < 0.01 then found = true end
    end
    assertTrue(found, "the late cast is in its cast list past the buzzer")
    -- The same id plans the same race.
    local again = NS.MockFights.Dataset()
    for i, r in ipairs(data.fights) do assertEqual(again.fights[i].race and again.fights[i].race.score, r.race and r.race.score) end
end)

test("race preview: on WoW Forever there is no sample race, no race word and no race in the history", function()
    if not forever() then return end
    local S = fresh()
    local NS = S.NS
    assertNil(NS.MockRaces, "no sample races")
    assertNil(NS.RaceSample, "no sample race")
    for _, r in ipairs(NS.MockFights.Dataset().fights) do assertFalse(NS.RaceRecord.IsRace(r), r.id .. " is a fight") end
    slash(S, "test race running")
    assertEqual(NS.Preview.Mode(), "test", "the word is absent: `test` is plain test mode")
    assertNil(NS.Preview.RaceState())
    assertEqual(NS.Preview.Diagnose().phase, "held")
    NS.Preview.Stop()
end)
