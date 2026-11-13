local _, NS = ...
-- modules/SimRace.lua — the sim's race scenarios (Race mode spec §8 "the sim gains DPS Race's eight race
-- scenarios", race plan Task E1): a made-up race played in real time through the Race window, the DPS
-- HUD, the lanes, the countdown, the buzzer, the chat lines and the new-best toast, then the Results
-- window on the race beside the sample history. Ported from DPS Race @f8078c7 (modules/Sim.lua and
-- modules/SampleRace.lua's script) onto Combat Trail's sim (modules/Sim.lua, which hands a race
-- scenario's start, beat, steps and gate to this file).
--
-- THE EIGHT, under a `race-` prefix (the sim's own newbest, behind and first are fights'): newbest,
-- behind, first, incomplete, died, flagged, shared and sticky, DPS Race's figures. Each races
-- MockRaces.LENGTH seconds on a dummy of its kind (single, but first's boss board, which has no
-- history), against the main sample hunter's best on that race board in the sample history.
--
-- THE CLOCK. Launch arms the sample race (modules/RaceSample.lua Start: the Race window's armed body)
-- and parks it; Unpark (the stepper's Race starts, or at once with no library) stamps combat entry and
-- starts one AceTimer beat every TICK. The first hit lands MockFights.FIRST_HIT in and starts the race
-- clock; each beat feeds the lanes, the chart's store and the HUD's tick from the plan, as Sim's fight
-- beat does. At the race length the buzzer goes (Countdown.Buzzer, the real call-out's STOP); an
-- incomplete scenario's combat ends before it instead. Combat ends `combatEnd` seconds after the
-- buzzer (sticky: past the hint's delay, `race.hintDelay` + STICKY_EXTRA), and the read lands
-- RaceScoring.QUIET_BEFORE_READ seconds after the later of the last hit and the combat end (Stop Now:
-- at the combat end). The record joins the sample history (Results_Source.Put), the HUD and the Race
-- window show their cards, the result line prints and the toast offers itself through their real
-- functions (Share.OnRaceResult, BestToast.OnRace), and RESULT_HOLD seconds later the Results window
-- opens on it.
--
-- NOTHING REACHES THE BUS OR THE STORE, as every sample (modules/Preview.lua's header): the windows are
-- called directly, the record lives in the sample history only, and NS.Race never moves. The one
-- message is the race beat's RACE_CLOCK (modules/RaceClock.lua), which carries nothing: while the
-- sample race runs or stops it moves both race clocks, as for a real race.
--
-- RETAIL ONLY (clients-§4): on WoW Forever this file returns at once and the sim has no race scenario.
-- With Race mode off a race scenario is refused (Sim's raceRefusal), as an arm is.

if not NS.Compat.ForClient({ "retail" }) then return end

local SR = {}
NS.SimRace = SR

local L = NS.L

--- The eight, in the order help lists them (Sim appends them to its own scenarios).
SR.SCENARIOS = {
    { key = "race-newbest", label = "Race: new best", factor = 1.04, tail = 3.1, combatEnd = 4.2,
      desc = "a race that beats your best on its board" },
    { key = "race-behind", label = "Race: behind the best", factor = 0.93, tail = 2.4, combatEnd = 5.2,
      desc = "a race behind your best on its board" },
    { key = "race-first", label = "Race: first race", kind = "boss", tail = 1.8, combatEnd = 3.6,
      desc = "the first race on its board: nothing to beat" },
    { key = "race-incomplete", label = "Race: incomplete", factor = 0.96, status = "incomplete", endAt = 9,
      desc = "combat ends before the buzzer" },
    { key = "race-died", label = "Race: you die", factor = 0.90, status = "incomplete", endAt = 6, died = true,
      desc = "you die before the buzzer" },
    { key = "race-flagged", label = "Race: late cast", factor = 0.98, tail = 2.8, combatEnd = 4.6,
      late = { { t = 1.4 } }, desc = "a cast after the buzzer flags the race" },
    { key = "race-shared", label = "Race: shared session", factor = 0.99, tail = 3.4, combatEnd = 4.8,
      shared = true, desc = "the pull carries on a meter session: no pace" },
    { key = "race-sticky", label = "Race: combat holds on", factor = 0.97, tail = 2.6, sticky = true,
      desc = "combat holds on after the buzzer: the hint shows" },
}
for _, s in ipairs(SR.SCENARIOS) do s.race = true end

-- The beat (the Race window's own clock is 10 Hz), how long the card holds before the Results window,
-- and how far past the hint's delay a sticky combat holds on.
SR.TICK = 0.1
SR.RESULT_HOLD = 4
SR.STICKY_EXTRA = 3

local timer, scen, sample, phase, lastAt, overAt, combatAt, readAt
local racingStep, endedStep, cardStep = false, false, false

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Race", fmt, ...) end
end

local function ST() return NS.Race.STATE end

local function cancelTimer()
    if timer and NS.addon and NS.addon.CancelTimer then NS.addon:CancelTimer(timer) end
    timer = nil
end

local function hintDelay() return tonumber(NS.GetSetting("race.hintDelay")) or 15 end

-- Seconds after the buzzer combat ends (the race clock's combat end, for a complete race).
local function combatEndOf(s)
    if s.sticky then return hintDelay() + SR.STICKY_EXTRA end
    return s.combatEnd or NS.MockRaces.COMBAT_END
end

--- Whether `key` names a race scenario.
function SR.Is(key)
    for _, s in ipairs(SR.SCENARIOS) do
        if s.key == key then return true end
    end
    return false
end

--- The line refusing race scenario `key` now, or nil: Race mode off.
function SR.Refusal(key)
    if not SR.Is(key) or NS.RaceMode.On() then return nil end
    return L["Race mode is off: turn it on on the Race mode page to race."]
end

-- ── the script ──────────────────────────────────────────────────────────────────────────────────

local function refreshWindows()
    if NS.Countdown then NS.Countdown.Refresh() end
    if NS.RaceWindow then NS.RaceWindow.Refresh() end
end

-- The plan's last hit by `at` (the fight's clock), on the race clock.
local function lastHitBy(at)
    local last
    for _, h in ipairs(sample.plan.hits) do
        if h.t > at then break end
        last = h.t
    end
    return last and last - NS.MockFights.FIRST_HIT or nil
end

-- One beat of the fight: the lanes, the chart's store, the HUD's live view, the race's last damage.
local function feed(fight, at, now)
    local MF = NS.MockFights
    at = math.min(at, sample.plan.length)
    NS.Preview.FeedLanes(sample.plan, lastAt, at, now)
    lastAt = at
    local player, pet = MF.TotalAt(sample.plan, at)
    NS.Slices.Record(fight.id, at, player, pet)
    NS.RaceSample.Set({ lastDamage = lastHitBy(at) })
    NS.Hud.OnFightTick(fight)
end

-- The first hit: the race clock starts.
local function firstHit(fight)
    fight.firstHitT = fight.startT + NS.MockFights.FIRST_HIT
    phase = "racing"
    NS.RaceSample.Set({ state = ST().RUNNING, startedAt = fight.firstHitT })
    debug("sim race %s: the clock starts", scen.key)
    refreshWindows()
end

local function endCombat(fight, rc)
    fight.combatEndT = fight.firstHitT + rc
    NS.RaceSample.Set({ inCombat = false })
end

-- The buzzer at the race length, or combat ending before it (an incomplete scenario).
local function stopRace(fight, early)
    local RS, length = NS.RaceSample, sample.length
    phase = "stopping"
    if early then
        sample.race.endedAt = scen.endAt
        combatAt = scen.endAt
        RS.Set({ state = ST().STOPPING })
        endCombat(fight, scen.endAt)
        readAt = scen.endAt + NS.RaceScoring.QUIET_BEFORE_READ
    else
        combatAt = length + combatEndOf(scen)
        RS.Set({ state = ST().STOPPING, buzzerAt = fight.firstHitT + length })
        readAt = math.max(length + (scen.tail or 0), combatAt) + NS.RaceScoring.QUIET_BEFORE_READ
    end
    refreshWindows()
    if not early and NS.Countdown then NS.Countdown.Buzzer() end
end

-- The read: the record joins the sample history, every card shows it, the result line and the toast.
local function read(fight)
    local MF, record = NS.MockFights, sample.record
    phase, overAt = "over", GetTime()
    record.t = time()
    fight.closedT = fight.combatEndT
    NS.Slices.Close(fight.id)
    NS.Hud.OnFightEnded(fight, MF.FinalOf(sample.plan, sample.plan.length), "final")
    NS.ResultsSource.Put(record)
    NS.Hud.OnFightSaved(record)
    NS.RaceSample.Set({ state = ST().RESULT, record = record, race = record.race })
    refreshWindows()
    if NS.Share then NS.Share.OnRaceResult(record, record.race) end
    if NS.BestToast then NS.BestToast.OnRace(record) end
    debug("sim race %s: read, %s", scen.key, tostring(record.race.status))
end

-- The script's end: the Results window on the race; the cards stay.
local function finish()
    cancelTimer()
    phase = "results"
    NS.Preview.OpenResults(sample.record.id)
end

local function stopping(fight, rc)
    local RS = NS.RaceSample
    if RS.InCombat() and rc >= combatAt then endCombat(fight, combatAt) end
    if RS.InCombat() then return end
    if rc >= readAt or RS.StopRequested() then read(fight) end
end

--- One beat (`now` is for the suites, GetTime() otherwise): the first hit, the race, the buzzer or the
--- early end, the combat end, the read after the quiet, and the card's hold.
function SR.Beat(now)
    if not (NS.Preview.IsActive() and sample) then return cancelTimer() end
    now = now or GetTime()
    local fight = sample.fight
    local at = now - fight.startT
    local rc = at - NS.MockFights.FIRST_HIT
    if phase == "fight" and rc >= 0 then firstHit(fight) end
    if phase == "racing" or phase == "stopping" then feed(fight, at, now) end
    if phase == "racing" then
        if scen.status == "incomplete" and rc >= scen.endAt then stopRace(fight, true)
        elseif rc >= sample.length then stopRace(fight, false) end
    end
    if phase == "stopping" then stopping(fight, rc) end
    if phase == "over" and now - overAt >= SR.RESULT_HOLD then finish() end
end

--- Start the parked race's fight: combat entry now, the first hit FIRST_HIT later.
--- @return boolean started
function SR.Unpark()
    if phase ~= "parked" or not sample then return false end
    local fight = sample.fight
    fight.startT = GetTime()
    local rec = NS.Slices.Begin(fight.id)
    if rec then rec.fight = fight end
    phase, lastAt = "fight", 0
    NS.RaceSample.Set({ inCombat = true })
    NS.Hud.OnFightStarted(fight)
    if NS.addon and NS.addon.ScheduleRepeatingTimer then
        timer = NS.addon:ScheduleRepeatingTimer(function() SR.Beat() end, SR.TICK)
    end
    return true
end

--- Arm scenario `s` (one of SR.SCENARIOS) against the preview's history and park it; with no step
--- session it plays at once.
function SR.Launch(s)
    cancelTimer()
    scen = s
    sample = NS.MockRaces.Sample({ id = "sim-" .. s.key, kind = s.kind, factor = s.factor, status = s.status,
                                   endAt = s.endAt, died = s.died, late = s.late, shared = s.shared,
                                   tail = s.tail, combatEnd = s.sticky and combatEndOf(s) or s.combatEnd },
                                 NS.Preview.Dataset())
    phase, lastAt, overAt, combatAt, readAt = "parked", 0, nil, nil, nil
    racingStep, endedStep, cardStep = false, false, false
    NS.RaceSample.Start(sample)
    if NS.RaceWindow then NS.RaceWindow.ShowSample() end
    if NS.Share then NS.Print(NS.Share.ArmedLine(sample.race, sample.fight.snapshot.target.name)) end
    debug("sim race %s armed", s.key)
    if not NS.Sim.session then SR.Unpark() end
end

--- Stop the script where it is (the preview's stop and switch): the sample race goes with it.
function SR.Cancel()
    cancelTimer()
    if not sample then return end
    NS.Slices.Forget(sample.fight.id)
    sample, scen, phase = nil, nil, nil
    racingStep, endedStep, cardStep = false, false, false
    NS.RaceSample.Clear()
    if NS.RaceWindow then NS.RaceWindow.EndSample() end
    if NS.Countdown then NS.Countdown.Refresh() end
end

--- The sim's sample race ({ fight, plan, race, record, ... }), or nil.
function SR.Sample() return sample end

--- What the race script is doing, for Sim.Diagnose.
--- @return table  { phase ("none" | "parked" | "fight" | "racing" | "stopping" | "over" | "results"), ticking }
function SR.Diagnose()
    return { phase = phase or "none", ticking = timer ~= nil }
end

-- ── the stepper ─────────────────────────────────────────────────────────────────────────────────
-- Armed holds the parked race; Race starts releases it; Racing does not jump, and the gate holds every
-- later step until the race got there; after the Buzzer (or Combat ends) step it holds until the read,
-- and after Result card until the card has shown for RESULT_HOLD.

--- The steps of race scenario `s`.
function SR.Timeline(s)
    return {
        { kind = "raceArmed", label = L["Armed"] },
        { kind = "raceStart", label = L["Race starts"] },
        { kind = "raceRun", label = L["Racing (%d s)"]:format(NS.MockRaces.LENGTH) },
        { kind = "raceEnd", label = s.status == "incomplete" and L["Combat ends"] or L["Buzzer"] },
        { kind = "raceCard", label = L["Result card"] },
        { kind = "raceResults", label = L["Results window"] },
    }
end

local PLAY = {
    raceArmed = function() end,
    raceStart = function() SR.Unpark() end,
    raceRun = function()
        SR.Unpark()
        racingStep = true
    end,
    raceEnd = function() endedStep = true end,
    raceCard = function() cardStep = true end,
    raceResults = function() if phase ~= "results" and sample then finish() end end,
}

--- Play step `kind` (one of SR.Timeline's).
function SR.Play(kind)
    local fn = PLAY[kind]
    if fn then fn() end
end

--- The stepper's gate for a race scenario: closed, with its line, while the race runs, while it waits
--- for its read (sticky's says combat holds on while it does), and while the card has shown for less
--- than RESULT_HOLD.
--- @return boolean open
--- @return string|nil line
function SR.Gate()
    if not sample then return true end
    if racingStep and (phase == "fight" or phase == "racing") then return false, L["The race is still running."] end
    if endedStep and phase == "stopping" then
        if scen.sticky and NS.RaceSample.InCombat() then return false, L["Waiting for the result (combat holds on)."] end
        return false, L["Waiting for the result."]
    end
    if cardStep and phase == "over" and overAt and GetTime() - overAt < SR.RESULT_HOLD then
        return false, L["The result card holds."]
    end
    return true
end
