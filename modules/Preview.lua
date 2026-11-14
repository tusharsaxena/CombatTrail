local _, NS = ...
-- modules/Preview.lua — test mode and the sim's shared shell (spec §7 "Test mode", §8 "Sim mode",
-- preview-mode; plan Task 5.1). Two modes, one switch:
--
--   test  `/ct test`, the Master controls' Test mode row and the launcher's entry: sample data in
--         every view. The HUD holds one moment of a sample fight still (its clock, live figures,
--         pace bar, chart and spell rows), the lanes play the sample rotation on a loop, and the
--         Results window opens on a made-up fight history (modules/MockFights.lua).
--   sim   `/ct sim`'s Start: a made-up 45 s fight played in real time through the lanes, the HUD's
--         live view and its fight-over card, then the Results window on the sim's fight beside the
--         same history (modules/Sim.lua holds the scenarios and the clock; with the library its
--         step session starts first, and its prepare comes back here).
--
-- Both run the views' own paths with made-up input: a sample fight (flagged `sample`) is handed to
-- the HUD's fight receivers (modules/Hud.lua's OnFight* functions) directly, never sent on the bus,
-- so the recorder, the cast list, the chart's reader and the bests never hear it. The HUD reads a
-- sample fight's figures from its plan and paces it against the sample history; the Results window
-- reads its source seam (modules/Results_Source.lua), routed to the sample history while either is
-- on and back to the store when it ends; the HUD and the Results window each lay their strip over
-- themselves meanwhile.
--
-- Session-only and on until turned off. It ENDS on combat (a real fight's FIGHT_STARTED, below), on
-- a real race's arm (RACE_ARMED, Retail), on its own switch, on Reset all settings (the row's
-- default), and silently on the stand-down. A start is refused in combat, while a real fight is still
-- being read and while a real race is armed or racing. It never writes a fight, a note, a loadout or a
-- view: the sample lives only in memory.
--
-- RACE MODE (Retail, race plan Task E1). The sample history holds races beside the fights
-- (modules/MockRaces.lua), and `/ct test race [armed|running|result]` holds a sample race in that
-- state (running when none is named; a state word in test mode switches it in place): the Race window
-- draws it through modules/RaceSample.lua, the stand-in for NS.Race; running holds the HUD on the
-- race's fight at RACE_STILL_AT race seconds, paced on its race board; result holds the HUD's over card
-- and the Race window's result card on the sample race, which joins the sample history, and the
-- new-best toast's preview. Armed holds the HUD on test mode's own sample fight. With Race mode off
-- the race word is refused with one line (the switch stops new races; a sample race is one).
--
-- THE ALERTS (callout plan row C6, owner 2026-11-14). Plain `/ct test` stays the HUD's alone. The
-- race word's result, a new best over the sample history, also shows the call-out's NEW_BEST
-- (Countdown.SampleSay of Countdown.ResultWord, a real race's rule). Its running body is a still frame
-- (owner, 2026-11-14): it holds the race clock still, so the sample has no endsAt (RaceSample.EndsAt)
-- and no countdown runs: the countdown and the buzzer's STOP are the sim's, on the sample's running
-- clock (modules/SimRace.lua). Every stop and switch of the
-- preview takes the samples' alerts down (Countdown.EndSample, BestToast.EndSample): no toast and no
-- call-out outlives the sample that earned it, and none of them writes a record or a best.

local Preview = { active = false }
NS.Preview = Preview

local L = NS.L

-- The board the samples fight on (modules/MockFights.lua), and test mode's held moment: this far
-- past the first hit of a 60 s sample fight at 3 percent over the board's best.
Preview.BOARD = "vorasius"
Preview.STILL_AT = 25
Preview.TEST_LENGTH = 60
Preview.TEST_FACTOR = 1.03
-- How often test mode's lanes move on, and how far back their first fill reaches (s).
Preview.LANE_TICK = 0.25
Preview.LANE_BACK = 15
-- Race mode's held sample race (Retail): the state words, the default, and the running body's held
-- moment (race seconds past the first hit, clear of the final countdown) at 3 percent over the best on
-- its race board.
Preview.RACE_STATES = { "armed", "running", "result" }
Preview.RACE_DEFAULT = "running"
Preview.RACE_STILL_AT = 18
Preview.RACE_FACTOR = 1.03

local mode            -- "test" | "sim" while active
local opened          -- the HUD was opened by the preview (let go again at the end)
local resultsOpened   -- the Results window was opened by the preview (closed again at the end)
local dataset         -- the sample history the Results window reads meanwhile
local still           -- test mode's held sample: { fight, plan }
local raceWord        -- the sample race's held state word, while test mode holds one
local queued          -- the next argument-less Start's options (Preview.Queue)
local laneTimer, laneAt, laneZero

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Test", fmt, ...) end
end

function Preview.IsActive() return Preview.active end

--- The mode on: "test", "sim", or nil when off.
function Preview.Mode() return Preview.active and mode or nil end

--- The sample history the Results window reads while the preview is on (nil when off).
function Preview.Dataset() return Preview.active and dataset or nil end

-- The Master controls' Test mode and Sim mode boxes read the preview only when a refresher runs:
-- every start and stop repaints an open panel in place (options-ui-§11, §15), whoever turned it.
local function repaintPanel()
    local H = NS.Helpers
    if H and type(H.RefreshScalars) == "function" then H.RefreshScalars() end
end

--- The Results window on the sample history, opened if it was not (and closed again at the end).
--- `id` opens that fight's detail.
function Preview.OpenResults(id)
    local R = NS.Results
    if not R then return end
    if not resultsOpened then resultsOpened = not R.IsShown() end
    if id then R.ShowFight(id) else R.Show() end
end

--- The Results window was closed (its close, Escape): a later open is the player's own, so the end
--- of the preview no longer closes it.
function Preview.ResultsClosed()
    resultsOpened = false
end

-- ── the lanes ───────────────────────────────────────────────────────────────────────────────────

--- Push `plan`'s casts with from < t <= to onto the lanes, each placed as if cast `to - t` seconds
--- before `now`. A lane's ignore list and its switch apply as to a real cast; nothing is recorded.
--- @return number pushed
function Preview.FeedLanes(plan, from, to, now)
    local R = NS.LaneRender
    if not (R and plan) then return 0 end
    local n = 0
    for _, c in ipairs(plan.casts) do
        local lane = c.unit == "pet" and "pet" or "player"
        if c.t > from and c.t <= to and not NS.LaneCasts.IsIgnored(lane, c.spellID) then
            local ok, texture = pcall(NS.Compat.SpellTexture, c.spellID)
            R.Push(lane, { texture = ok and texture or nil, spellID = c.spellID, t = now - (to - c.t),
                           interrupted = c.interrupted == true })
            n = n + 1
        end
    end
    return n
end

local function clearLanes()
    local R = NS.LaneRender
    if R then
        R.Clear("player")
        R.Clear("pet")
    end
    if NS.LaneVisibility then NS.LaneVisibility.Refresh() end
end

-- Test mode's lanes: the held fight's rotation on a loop, one beat every LANE_TICK.
local function laneBeat()
    if not (Preview.active and still) then return end
    local length, now = still.plan.length, GetTime()
    local at = now - laneZero
    if at >= length then
        Preview.FeedLanes(still.plan, laneAt, length, now - (at - length))
        laneZero = laneZero + length
        at, laneAt = at - length, 0
    end
    Preview.FeedLanes(still.plan, laneAt, at, now)
    laneAt = at
end

local function startLanes(plan, at)
    local now = GetTime()
    laneZero, laneAt = now - at, at
    Preview.FeedLanes(plan, math.max(0, at - Preview.LANE_BACK), at, now)
    if NS.addon and NS.addon.ScheduleRepeatingTimer then
        laneTimer = NS.addon:ScheduleRepeatingTimer(laneBeat, Preview.LANE_TICK)
    end
end

local function stopLanes()
    if laneTimer and NS.addon and NS.addon.CancelTimer then NS.addon:CancelTimer(laneTimer) end
    laneTimer = nil
end

-- ── test mode: the held views ───────────────────────────────────────────────────────────────────

-- The HUD held on `sample`'s live view `at` seconds past its first hit, with its lanes.
local function holdLive(sample, at)
    local MF = NS.MockFights
    still = sample
    local fight, now = still.fight, GetTime()
    fight.frozen = at
    fight.startT = now - at - MF.FIRST_HIT
    fight.firstHitT = fight.startT + MF.FIRST_HIT
    local rec = NS.Slices.Begin(fight.id)
    if rec then rec.fight = fight end
    MF.FillSlices(fight.id, still.plan, at + MF.FIRST_HIT)
    NS.Hud.OnFightStarted(fight)
    startLanes(still.plan, at + MF.FIRST_HIT)
end

-- The held HUD: the sample fight STILL_AT seconds past its first hit, beating the history's best on
-- its board (the most a live body draws: the chart, the pace bar and the spell rows).
local function holdFight()
    holdLive(NS.MockFights.Sample({ id = "test", board = Preview.BOARD, length = Preview.TEST_LENGTH,
                                    factor = Preview.TEST_FACTOR }, dataset), Preview.STILL_AT)
end

local function startTest()
    holdFight()
    Preview.OpenResults()
end

-- The HUD's over card on the sample race, read and saved into the sample history (never the store).
local function holdResult(sample)
    local MF, plan = NS.MockFights, sample.plan
    still = sample
    local fight, now = sample.fight, GetTime()
    fight.startT = now - plan.length
    fight.firstHitT = fight.startT + MF.FIRST_HIT
    fight.combatEndT, fight.closedT = now, now
    local rec = NS.Slices.Begin(fight.id)
    if rec then rec.fight = fight end
    MF.FillSlices(fight.id, plan, plan.length)
    NS.Slices.Close(fight.id)
    NS.Hud.OnFightStarted(fight)
    NS.Hud.OnFightEnded(fight, MF.FinalOf(plan, plan.length), "final")
    NS.ResultsSource.Put(sample.record)
    NS.Hud.OnFightSaved(sample.record)
    startLanes(plan, plan.length)
end

-- Test mode on a sample race held in state `word` (Retail): the Race window, the HUD and the lanes.
local function startRaceTest(word)
    raceWord = word
    local sample = NS.MockRaces.Sample({ id = "test-race", factor = Preview.RACE_FACTOR }, dataset)
    if word == "running" then
        holdLive(sample, Preview.RACE_STILL_AT)
    elseif word == "result" then
        holdResult(sample)
        NS.BestToast.ShowPreview(sample.record)
        NS.Countdown.SampleSay(NS.Countdown.ResultWord(sample.record))
    else
        holdFight()
    end
    NS.RaceSample.Hold(sample, word, Preview.RACE_STILL_AT)
    NS.RaceWindow.ShowSample()
    Preview.OpenResults()
end

local function stopTest()
    stopLanes()
    if still then NS.Slices.Forget(still.fight.id) end
    still = nil
    if raceWord then
        raceWord = nil
        NS.RaceSample.Clear()
        NS.RaceWindow.EndSample()
    end
end

-- The samples' alerts down: the toasts a sample earned, the call-out's countdown and words (Retail).
local function endAlerts()
    if NS.BestToast then NS.BestToast.EndSample() end
    if NS.Countdown then NS.Countdown.EndSample() end
end

-- ── the switch ──────────────────────────────────────────────────────────────────────────────────

-- A real race armed or racing (Retail): the windows are its.
local RACING = { armed = true, running = true, stopping = true }

--- The line refusing a start now, or nil: in combat, while a real fight is still being read (its
--- settle), and while a real race is armed or racing. The sim's step session reads it as its refusal
--- (modules/Sim.lua).
--- @return string|nil
function Preview.Refusal()
    if NS.Secrets.PlainTruth(UnitAffectingCombat("player")) then return L["Test mode is not available in combat."] end
    if NS.Fight and NS.Fight.Current() then return L["Test mode is not available while a fight is being read."] end
    if NS.Race and RACING[NS.Race.State()] then return L["Test mode is not available during a race."] end
    return nil
end

-- Stop whichever run is on. `keepSession`: the sim's step session is the one starting this preview
-- (its prepare), so it stays.
local function stopRun(keepSession)
    if NS.Sim then NS.Sim.Cancel(keepSession) end
    stopTest()
    endAlerts()
    if NS.Hud then NS.Hud.EndSample(false) end
    clearLanes()
end

-- The mode's own start: the sim's scenario, test mode's sample race (Retail), or its held fight.
local function enter(opts)
    if mode == "sim" then return NS.Sim.Enter(opts.scenario) end
    if opts.race and NS.RaceSample then return startRaceTest(opts.race) end
    startTest()
end

--- Turn the preview on, or switch an active one to `opts`' mode in place. Refused (one line) in
--- combat, while a real fight is read and during a real race; silent while stood down, where the caller's own hold-aware
--- refusal has already spoken. A sim start with the library goes through the sim's step session
--- (Sim.Open), whose prepare calls back here with `session` set.
--- @param opts table|nil  { mode = "test" | "sim", scenario?, arm?, session?, race? }; nil is the queued
---   options (Preview.Queue), else test mode
--- @return boolean started
function Preview.Start(opts)
    if type(opts) ~= "table" then opts = queued or { mode = "test" } end
    queued = nil
    if NS.IsStoodDown() then return false end
    if opts.mode == "sim" and not opts.session and NS.Sim and NS.Sim.session then
        return NS.Sim.Open(opts.scenario, opts.arm)
    end
    local line = Preview.Refusal()
    if line then
        NS.Print(line)
        return false
    end
    stopRun(opts.session)
    if not Preview.active then opened = not NS.Hud.IsShown() end
    Preview.active, mode = true, opts.mode == "sim" and "sim" or "test"
    dataset = NS.MockFights.Dataset()
    NS.ResultsSource.Use(dataset)
    clearLanes()
    enter(opts)
    repaintPanel()
    debug("%s on (%s)", mode, tostring(mode == "sim" and NS.Sim.Scenario() or raceWord or "held"))
    return true
end

--- The options the next argument-less Start takes (the Test mode row's write starts with none): a
--- race test through the row, so the box follows.
function Preview.Queue(opts)
    queued = type(opts) == "table" and opts or nil
end

local function isRaceWord(word)
    for _, w in ipairs(Preview.RACE_STATES) do
        if w == word then return true end
    end
    return false
end

--- The sample race's held state word while test mode holds one, else nil.
function Preview.RaceState() return Preview.Mode() == "test" and raceWord or nil end

--- Test mode's sample race switched to `word` in place (test mode only).
--- @return boolean switched
function Preview.SetRace(word)
    if Preview.Mode() ~= "test" or not isRaceWord(word) or not NS.RaceSample then return false end
    stopTest()
    endAlerts()
    if NS.Hud then NS.Hud.EndSample(false) end
    clearLanes()
    dataset = NS.MockFights.Dataset()
    NS.ResultsSource.Use(dataset)
    startRaceTest(word)
    debug("test race %s", word)
    return true
end

--- `/ct test race [armed|running|result]` (Retail): test mode holding a sample race in that state
--- (running when none is named), through the Test mode row so the box follows; in test mode the word
--- switches it in place. Refused with Race mode off, and with an unknown word (the usage line).
--- @param word string|nil
--- @return boolean held
function Preview.TestRace(word)
    if not NS.RaceSample then return false end
    word = (word == nil or word == "") and Preview.RACE_DEFAULT or tostring(word):lower()
    if not isRaceWord(word) then
        NS.Print(L["Usage: %s test race [armed|running|result]"]:format(NS.SLASH_CMD))
        return false
    end
    if not NS.RaceMode.On() then
        NS.Print(L["Race mode is off: turn it on on the Race mode page to race."])
        return false
    end
    if Preview.Mode() == "test" then return Preview.SetRace(word) end
    Preview.Queue({ mode = "test", race = word })
    NS.SetByPath("general.testMode", true)
    queued = nil
    return Preview.RaceState() == word
end

-- Give the windows back: the store to the Results window, each window let go if the preview opened
-- it.
local function release()
    if resultsOpened and NS.Results then NS.Results.Hide() end
    resultsOpened = false
    NS.ResultsSource.Restore()
    NS.Hud.EndSample(opened)
    opened = false
end

--- Turn the preview off. `reason` "combat" says so once; any other stop is the player's own act and
--- stays quiet.
--- @param reason string|nil
--- @return boolean stopped
function Preview.Stop(reason)
    if not Preview.active then return false end
    Preview.active = false
    stopRun()
    if reason == "combat" then NS.Print(L["Test mode ended: you entered combat."]) end
    local was = mode
    mode, dataset = nil, nil
    release()
    repaintPanel()
    debug("%s off (%s)", tostring(was), reason or "switch")
    return true
end

--- The stand-down ends the preview silently: the player turned the addon off, not the preview. A
--- Results window it opened is dropped (the lifecycle hides it next), so the stand-up does not bring
--- it back.
function Preview.Suspend()
    local was = Preview.active
    Preview.active = false
    stopRun()
    if resultsOpened and NS.Results then NS.Results.wanted = false end
    mode, dataset, opened, resultsOpened = nil, nil, false, false
    NS.ResultsSource.Restore()
    if was then repaintPanel() end
end

--- What the preview is doing, for the diagnostics report and the suites.
function Preview.Diagnose()
    local sim = NS.Sim and NS.Sim.Diagnose() or {}
    local phase = "none"
    if Preview.active then phase = mode == "sim" and sim.phase or (raceWord and "race " .. raceWord) or "held" end
    return { active = Preview.active, mode = Preview.Mode() or "none", phase = phase,
             scenario = Preview.active and mode == "sim" and sim.scenario or "none",
             ticking = sim.ticking == true or laneTimer ~= nil }
end

-- A real fight starting (combat entry) ends the preview: the HUD and the lanes then show that fight.
-- So does a real race's arm (Retail): its window is the race's (a sample never arms on the bus).
do
    local bus = NS.NewBusTarget()
    if bus then
        bus:RegisterMessage(NS.MSG.FIGHT_STARTED, function()
            if Preview.active then Preview.Stop("combat") end
        end)
        if NS.Compat.ForClient({ "retail" }) then
            bus:RegisterMessage(NS.MSG.RACE_ARMED, function(_, race)
                if not Preview.active or (type(race) == "table" and race.sample) then return end
                NS.Print(L["Test mode ended: a race was armed."])
                Preview.Stop("race")
            end)
        end
    end
end
