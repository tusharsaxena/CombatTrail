local _, NS = ...
-- modules/Sim.lua — `/ct sim` (spec §8 "Sim mode", plan Task 5.1): a made-up fight played in real
-- time through the lanes, the HUD's live view and its fight-over card, then the Results window on
-- the sim's fight beside the sample history, so the best, the pace and the compare have something
-- to stand on. Adapted from DPS Race @045f479 (modules/Sim.lua) without its race: no arm, no
-- buzzer, no countdown, no late cast; the fight is 45 s against the main sample hunter's board.
--
-- `/ct sim` is the library's sim grammar (LibKa0s-Sim-1.0 RunVerb): a bare line opens the step
-- panel idle (the scenario dropdown and Start, the steps previewed, nothing run); Start (or `/ct
-- sim start <scenario>`, or the bare `/ct sim <scenario>`) starts the session, whose prepare turns
-- the preview on (Preview.Start) and parks the fight until the first step. With no library the sim
-- plays at once.
--
-- THE CLOCK. Unpark stamps the sample fight's combat entry and starts one AceTimer beat every
-- Sim.TICK (the HUD's own 4 Hz): each beat pushes the casts now due onto the lanes, copies the
-- plan's totals into the chart's store (modules/Slices.lua, plain numbers) and hands the fight to
-- the HUD's tick, as Fight's FIGHT_TICK does. At the fight's length combat ends; SETTLE seconds
-- later the "final" read lands (the plan's, in Meter.ReadFinal's shape), the recording filters judge
-- it (modules/Filters.lua, the player's own settings) and the record joins the sample history in
-- memory (Results_Source.Put); RESULT_HOLD seconds after the card the Results window opens on it.
-- The stand-down's CancelAllTimers takes the beat.
--
-- NOTHING REACHES THE BUS OR THE STORE. The sample fight goes to the HUD's receivers directly, so
-- the recorder, the casts, the usage and the bests never hear it, and the record is never saved.
--
-- RACE MODE'S EIGHT (Retail, race plan Task E1): the race scenarios (`race-newbest` ... `race-sticky`,
-- modules/SimRace.lua) follow the fight scenarios in help and in the step window; this file hands a
-- race scenario's start, unpark, steps, gate, cancel and phase to NS.SimRace. With Race mode off a race
-- scenario is refused with one line.

local Sim = {}
NS.Sim = Sim

local L = NS.L

-- The scenarios, in the order help lists them. `factor` sets the sample's DPS against the main
-- hunter's best on its board; `board` names another board ("first" fights one with no history);
-- `length` replaces the 45 s; `lost` has the meter lose the fight.
Sim.SCENARIOS = {
    { key = "newbest", label = "New best", factor = 1.04, desc = "beats your best on the board" },
    { key = "behind", label = "Behind the best", factor = 0.93, desc = "saved, behind your best" },
    { key = "first", label = "First fight", board = "salhadaar",
      desc = "the first fight on its board: no best, no pace bar" },
    { key = "short", label = "Too short", factor = 0.98, length = 10,
      desc = "shorter than the recording filters' minimum: not saved" },
    { key = "lost", label = "Lost fight", factor = 0.97, lost = true, desc = "the meter loses the fight: not saved" },
}
-- Race mode's race scenarios (Retail only: modules/SimRace.lua loads nowhere else).
for _, s in ipairs(NS.SimRace and NS.SimRace.SCENARIOS or {}) do Sim.SCENARIOS[#Sim.SCENARIOS + 1] = s end
Sim.DEFAULT = "newbest"
Sim.BOARD = "vorasius"
--- The fight's length (spec §8): 45 s in real time.
Sim.LENGTH = 45
-- Seconds from the combat end to the final read (modules/Fight.lua's settle), and how long the card
-- holds before the Results window opens.
Sim.SETTLE = 2
Sim.RESULT_HOLD = 4
-- The beat, and the seconds between two steps of a playing stepper.
Sim.TICK = 0.25
Sim.STEP_DELAY = 1.5

local timer, sample, scenario, phase, overAt, lastAt, record, quiet, keepPanel
local fighting, ended, carded

local function find(key)
    for _, s in ipairs(Sim.SCENARIOS) do
        if s.key == key then return s end
    end
    return nil
end

--- Whether `word` names a scenario.
function Sim.IsScenario(word) return find(word) ~= nil end

--- The scenario keys, in help order.
function Sim.Names()
    local out = {}
    for i, s in ipairs(Sim.SCENARIOS) do out[i] = s.key end
    return out
end

--- The scenario playing, or nil.
function Sim.Scenario() return scenario end

--- The sim's sample fight ({ fight, plan, … }, modules/MockFights.lua Sample), or nil.
function Sim.Sample() return sample end

local function cancelTimer()
    if timer and NS.addon and NS.addon.CancelTimer then NS.addon:CancelTimer(timer) end
    timer = nil
end

-- ── the script ──────────────────────────────────────────────────────────────────────────────────

-- The script's end: the Results window on the sim's fight (the list when it was not saved); the HUD
-- keeps the card.
local function finish()
    cancelTimer()
    phase = "results"
    NS.Preview.OpenResults(record and record.id or nil)
end

-- One beat of the fight: the lanes, the chart's store and the HUD's live view, `at` seconds in.
local function fightBeat(fight, at, now)
    local MF = NS.MockFights
    if not fight.firstHitT and at >= MF.FIRST_HIT then fight.firstHitT = fight.startT + MF.FIRST_HIT end
    NS.Preview.FeedLanes(sample.plan, lastAt, at, now)
    lastAt = at
    local player, pet = MF.TotalAt(sample.plan, at)
    NS.Slices.Record(fight.id, at, player, pet)
    NS.Hud.OnFightTick(fight)
end

-- The settle is over: the final read, the filters, the record (or the reason it was not saved).
local function endFight(fight, now)
    phase, overAt = "over", now
    fight.closedT = fight.combatEndT
    local s, length = find(scenario), sample.plan.length
    if s.lost then
        NS.Slices.Forget(fight.id)
        NS.Hud.OnFightEnded(fight, nil, "lost")
        return NS.Hud.OnFightSkipped(fight, "lost")
    end
    NS.Slices.Close(fight.id)
    NS.Hud.OnFightEnded(fight, NS.MockFights.FinalOf(sample.plan, length), "final")
    local ok, why = NS.Filters.Passes(sample.ident, length)
    if not ok then
        NS.Slices.Forget(fight.id)
        return NS.Hud.OnFightSkipped(fight, why)
    end
    record = NS.MockFights.Record({ id = fight.id, t = time() - math.floor(length + Sim.SETTLE), who = sample.who,
                                    board = sample.board, length = length }, sample.plan)
    fight.recordID = record.id
    NS.ResultsSource.Put(record)
    NS.Hud.OnFightSaved(record)
end

--- One beat: the fight moves on, combat ends at its length, the read lands after the settle, and the
--- card's hold runs out. `now` is for the suites (GetTime() otherwise).
function Sim.Beat(now)
    if not (NS.Preview.IsActive() and sample) then return cancelTimer() end
    now = now or GetTime()
    local fight, length = sample.fight, sample.plan.length
    local at = now - fight.startT
    if phase == "fight" then
        fightBeat(fight, math.min(at, length), now)
        if at >= length then
            fight.combatEndT = fight.startT + length
            phase = "settle"
        end
    end
    if phase == "settle" and at >= length + Sim.SETTLE then endFight(fight, now) end
    if phase == "over" and now - overAt >= Sim.RESULT_HOLD then finish() end
end

--- Start the parked fight's clock: combat entry now, the first hit FIRST_HIT later. The stepper's
--- first step, or Enter's own with no stepper.
--- @return boolean started
function Sim.Unpark()
    if phase == "race" then return NS.SimRace.Unpark() end
    if phase ~= "parked" or not sample then return false end
    local fight = sample.fight
    fight.startT = GetTime()
    local rec = NS.Slices.Begin(fight.id)
    if rec then rec.fight = fight end
    phase, lastAt = "fight", 0
    NS.Hud.OnFightStarted(fight)
    if NS.addon and NS.addon.ScheduleRepeatingTimer then
        timer = NS.addon:ScheduleRepeatingTimer(function() Sim.Beat() end, Sim.TICK)
    end
    return true
end

-- Build scenario `key`'s fight against the preview's history and park it (Enter's job, for every
-- start: the session's prepare, its Restart's included, and the start with no library).
local function launch(key)
    cancelTimer()
    local s = find(key) or find(Sim.DEFAULT)
    scenario = s.key
    if s.race then
        sample, record, overAt, lastAt, phase = nil, nil, nil, 0, "race"
        fighting, ended, carded = false, false, false
        return NS.SimRace.Launch(s)
    end
    sample = NS.MockFights.Sample({ id = "sim-" .. s.key, board = s.board or Sim.BOARD,
                                    length = s.length or Sim.LENGTH, factor = s.factor }, NS.Preview.Dataset())
    record, overAt, lastAt, phase = nil, nil, 0, "parked"
    fighting, ended, carded = false, false, false
    if not Sim.session then Sim.Unpark() end
end

-- ── the stepper ─────────────────────────────────────────────────────────────────────────────────
-- LibKa0s-Sim-1.0's step window beside the HUD. The fight plays on its own clock, in real time:
-- Combat starts releases the parked fight; Fighting does not jump, and the gate (Sim.Gate) holds every
-- later step until the fight has got there; after Combat ends it holds until the final read, and
-- after Fight-over card until the card has shown for RESULT_HOLD. The session fakes no client answer
-- (core/SimSetup.lua).

local STEP_MOMENTS = {
    combat = function() Sim.Unpark() end,
    fight = function()
        Sim.Unpark()
        fighting = true
    end,
    ending = function() ended = true end,
    card = function() carded = true end,
    results = function() if phase ~= "results" then finish() end end,
}

local function timeline(_, opts)
    local s = find(opts.scenario) or find(Sim.DEFAULT)
    if s.race then return NS.SimRace.Timeline(s) end
    return {
        { kind = "combat", label = L["Combat starts"] },
        { kind = "fight", label = L["Fighting (%d s)"]:format(s.length or Sim.LENGTH) },
        { kind = "ending", label = L["Combat ends"] },
        { kind = "card", label = L["Fight-over card"] },
        { kind = "results", label = L["Results window"] },
    }
end

--- The stepper's gate: closed, with its line, while the Fighting step's fight is still on, while the
--- fight after the Combat ends step has yet to be read, and while the card after its step has shown
--- for less than RESULT_HOLD; open otherwise.
--- @return boolean open
--- @return string|nil line
function Sim.Gate()
    if phase == "race" then return NS.SimRace.Gate() end
    if not sample then return true end
    if fighting and phase == "fight" then return false, L["The fight is still on."] end
    if ended and phase == "settle" then return false, L["Waiting for the meter's final read."] end
    if carded and phase == "over" and overAt and GetTime() - overAt < Sim.RESULT_HOLD then
        return false, L["The fight-over card holds."]
    end
    return true
end

local function playStep(step)
    local moment = STEP_MOMENTS[step.kind]
    if moment then moment() elseif NS.SimRace then NS.SimRace.Play(step.kind) end
    return step.label
end

-- The line refusing scenario `key` now (a race scenario with Race mode off), or nil.
local function raceRefusal(key)
    return NS.SimRace and NS.SimRace.Refusal(key) or nil
end

-- The scenario lines the library's usage ends with (an unknown word).
local function usageLines()
    local out = {}
    for i, s in ipairs(Sim.SCENARIOS) do out[i] = L["  %s: %s"]:format(s.key, L[s.desc]) end
    return out
end

-- The session's prepare (Start, the panel's Start, Restart): the preview on in sim mode, the fight
-- parked, the panel shown. Preview.Start's `session` start leaves the session it is building alone.
local function prepare(_, _, opts, ready)
    local line = raceRefusal(opts.scenario)
    if line then
        NS.Print(line)
        return Sim.session:Stop("refused")
    end
    if not NS.Preview.Start({ mode = "sim", scenario = opts.scenario, session = true }) then
        return Sim.session:Stop("refused")
    end
    Sim.session:ShowPanel()
    ready()
end

local function newSession()
    local lib = NS.SimLib
    if not (lib and lib.New) then return nil end
    local names, defs = {}, {}
    for i, s in ipairs(Sim.SCENARIOS) do
        names[i] = s.key
        defs[s.key] = { label = L[s.label], timeline = timeline }
    end
    return lib:New({
        name = "CombatTrail",
        seam = NS.SimSeam,
        slash = NS.SLASH_CMD .. " sim",
        deliver = function() return 0 end,
        isStoodDown = function() return NS.IsStoodDown() end,
        scenarios = { names = names, defs = defs },
        prepare = prepare,
        play = playStep,
        gate = function() return Sim.Gate() end,
        refusal = function() return NS.Preview.Refusal() end,
        usage = usageLines(),
        stepDelay = Sim.STEP_DELAY,
        print = function(line) if not quiet then NS.Print(line) end end,
        panel = {
            title = function() return L["Combat Trail - SIM"] end,
            anchorTo = function() return NS.Hud.Frame() end,
        },
    })
end

--- The stepper's session, or nil with no LibKa0s-Sim-1.0.
Sim.session = newSession()

-- Every start and stop (the verb, the panel, the launcher, its own end) repaints an open settings
-- page, so Master controls' Sim mode box shows the live sim.
local function repaintSettings()
    local H = NS.Helpers
    if H and type(H.RefreshScalars) == "function" then H.RefreshScalars() end
end

-- The stepper's own Stop (reason "stop") ends the preview as well: the beat and the fight are Sim's,
-- not the session's. Sim.Cancel's stopSession runs quiet and a Restart's reason is "restart", so
-- neither re-enters. The panel stays open on its idle picker; every other end hides it.
if Sim.session then
    Sim.session:OnStop(function(_, reason)
        if quiet or reason ~= "stop" or not NS.Preview.IsActive() then return end
        keepPanel = true
        NS.Preview.Stop()
        keepPanel = false
    end)
    Sim.session:AddListener(repaintSettings)
end

-- The sim window's show and hide repaint the settings too: the box reads "window shown or running",
-- and the window also closes by its own close control and by Escape, neither of which goes through
-- HidePanel. The library builds the window on its first show and publishes no handle, so the frame
-- is found by its global name (the library's `<name>SimPanel`) after that show and hooked once.
local PANEL_NAME = "CombatTrailSimPanel"
local panelHooked = false
local function hookPanel()
    if panelHooked then return end
    local frame = _G[PANEL_NAME]
    if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return end
    panelHooked = true
    frame:HookScript("OnShow", repaintSettings)
    frame:HookScript("OnHide", repaintSettings)
end
if Sim.session then
    -- The members are the instance's own fields (the library installs them per session), so the wrap
    -- is this session's alone; it repaints only when the window's state moved.
    local session = Sim.session
    local show, hide = session.ShowPanel, session.HidePanel
    function session.ShowPanel(...)
        local was = session:IsPanelShown()
        local shown = show(...)
        hookPanel()
        if not was and session:IsPanelShown() then repaintSettings() end
        return shown
    end
    function session.HidePanel(...)
        local was = session:IsPanelShown()
        hide(...)
        if was and not session:IsPanelShown() then repaintSettings() end
    end
end

local function stopSession(reason)
    local session = Sim.session
    if not session then return end
    quiet = true
    if session:IsActive() then session:Stop(reason) end
    if not keepPanel then session:HidePanel() end
    quiet = false
end

--- Start scenario `key` (the default when it names none) through the session: a live one ends quietly
--- first, so the sim switches in place. `arm` plays it as the typed `start` does (the panel's Start);
--- without it the session waits for its first step, as the member's Start does.
--- @return boolean started
function Sim.Open(key, arm)
    local session = Sim.session
    local s = find(key) or find(Sim.DEFAULT)
    local line = raceRefusal(s.key) or NS.Preview.Refusal()
    if line then
        NS.Print(line)
        return false
    end
    stopSession("switch")
    if arm then return (session:RunVerb("start " .. s.key)) == true end
    return (session:Start({ scenario = s.key })) == true
end

--- Play scenario `key` against the preview's history: the preview shell's sim start, which has
--- already checked it may start (and, with a session, is that session's prepare).
function Sim.Enter(key)
    launch(key)
end

--- Stop the script where it is (the preview's stop and switch). `keepSession` (the session's own
--- prepare switching the preview to it) leaves the session alone.
function Sim.Cancel(keepSession)
    cancelTimer()
    if NS.SimRace then NS.SimRace.Cancel() end
    if not keepSession then stopSession("stop") end
    if sample then NS.Slices.Forget(sample.fight.id) end
    sample, scenario, phase, overAt, record = nil, nil, nil, nil, nil
    fighting, ended, carded = false, false, false
end

--- What the sim is doing, for the diagnostics report and the suites.
--- @return table  { scenario, phase ("none" | "parked" | "fight" | "settle" | "over" | "results"), ticking }
function Sim.Diagnose()
    if phase == "race" then
        local r = NS.SimRace.Diagnose()
        return { scenario = scenario, phase = r.phase, ticking = r.ticking }
    end
    return { scenario = scenario or "none", phase = phase or "none", ticking = timer ~= nil }
end

-- ── the switch the surfaces share ───────────────────────────────────────────────────────────────

--- The usage line with no library session: every scenario, the default first.
function Sim.Usage()
    return L["Usage: %s sim [%s]"]:format(NS.SLASH_CMD, table.concat(Sim.Names(), "|"))
end

--- Play a whole made-up fight at once (the default scenario with none); an active preview switches
--- to it in place. With the step session it starts there and plays (the panel's Start).
--- @param word string|nil
--- @return boolean started
function Sim.Start(word)
    if word == nil or word == "" then word = Sim.DEFAULT end
    if not Sim.IsScenario(word) then
        NS.Print(Sim.Usage())
        for _, line in ipairs(usageLines()) do NS.Print(line) end
        return false
    end
    if Sim.session then return Sim.Open(word, true) end
    local line = raceRefusal(word)
    if line then
        NS.Print(line)
        return false
    end
    return NS.Preview.Start({ mode = "sim", scenario = word })
end

--- `/ct sim [line]`: the library's sim grammar. A bare line prints the status and the usage and
--- opens the step panel idle; `start <scenario>`, `step`, `run`, `pause`, `resume`, `restart`,
--- `stop`, `status` and `panel` are the panel's own verbs. A bare scenario word starts it at once,
--- switching a live sim in place. With no library session: Sim.Start.
--- @param line string|nil
--- @return boolean ok
function Sim.RunVerb(line)
    line = tostring(line or "")
    local word = line:match("^%s*(%S*)"):lower()
    if not Sim.session then return Sim.Start(word) end
    if Sim.IsScenario(word) then return Sim.Start(word) end
    return (Sim.session:RunVerb(line)) == true
end

--- Whether Sim mode reads on (the launcher's entry and Master controls' box): the step window is
--- shown or a sim runs. With no library session, the preview's mode.
function Sim.IsOn()
    local session = Sim.session
    if session then return session:IsPanelShown() == true or session:IsActive() == true end
    return NS.Preview.Mode() == "sim"
end

--- The Sim mode toggle. Off, it is the bare `/ct sim` (the idle sim window), so it picks no
--- scenario. On, it stops a running sim and closes the window, so one untick or one launcher click
--- leaves it off. With no library session: the preview off, or Sim.Start.
--- @return boolean ok
function Sim.Toggle()
    local session = Sim.session
    if not session then
        if Sim.IsOn() then return NS.Preview.Stop() end
        return Sim.Start()
    end
    if not Sim.IsOn() then return Sim.RunVerb("") end
    if session:IsActive() and not Sim.RunVerb("stop") then return false end
    session:HidePanel()
    return true
end
