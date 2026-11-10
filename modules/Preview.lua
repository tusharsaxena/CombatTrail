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
-- its own switch, on Reset all settings (the row's default), and silently on the stand-down. A start
-- is refused in combat and while a real fight is still being read. It never writes a fight, a note,
-- a loadout or a view: the sample lives only in memory.

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

local mode            -- "test" | "sim" while active
local opened          -- the HUD was opened by the preview (let go again at the end)
local resultsOpened   -- the Results window was opened by the preview (closed again at the end)
local dataset         -- the sample history the Results window reads meanwhile
local still           -- test mode's held sample: { fight, plan }
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

-- The held HUD: the sample fight STILL_AT seconds past its first hit, beating the history's best on
-- its board (the most a live body draws: the chart, the pace bar and the spell rows).
local function startTest()
    local MF = NS.MockFights
    still = MF.Sample({ id = "test", board = Preview.BOARD, length = Preview.TEST_LENGTH,
                        factor = Preview.TEST_FACTOR }, dataset)
    local fight, now = still.fight, GetTime()
    fight.frozen = Preview.STILL_AT
    fight.startT = now - Preview.STILL_AT - MF.FIRST_HIT
    fight.firstHitT = fight.startT + MF.FIRST_HIT
    local rec = NS.Slices.Begin(fight.id)
    if rec then rec.fight = fight end
    MF.FillSlices(fight.id, still.plan, Preview.STILL_AT + MF.FIRST_HIT)
    NS.Hud.OnFightStarted(fight)
    startLanes(still.plan, Preview.STILL_AT + MF.FIRST_HIT)
    Preview.OpenResults()
end

local function stopTest()
    stopLanes()
    if still then NS.Slices.Forget(still.fight.id) end
    still = nil
end

-- ── the switch ──────────────────────────────────────────────────────────────────────────────────

--- The line refusing a start now, or nil: in combat, and while a real fight is still being read
--- (its settle). The sim's step session reads it as its refusal (modules/Sim.lua).
--- @return string|nil
function Preview.Refusal()
    if NS.Secrets.PlainTruth(UnitAffectingCombat("player")) then return L["Test mode is not available in combat."] end
    if NS.Fight and NS.Fight.Current() then return L["Test mode is not available while a fight is being read."] end
    return nil
end

-- Stop whichever run is on. `keepSession`: the sim's step session is the one starting this preview
-- (its prepare), so it stays.
local function stopRun(keepSession)
    if NS.Sim then NS.Sim.Cancel(keepSession) end
    stopTest()
    if NS.Hud then NS.Hud.EndSample(false) end
    clearLanes()
end

--- Turn the preview on, or switch an active one to `opts`' mode in place. Refused (one line) in
--- combat and while a real fight is read; silent while stood down, where the caller's own hold-aware
--- refusal has already spoken. A sim start with the library goes through the sim's step session
--- (Sim.Open), whose prepare calls back here with `session` set.
--- @param opts table|nil  { mode = "test" | "sim", scenario?, arm?, session? }; nil is test mode
--- @return boolean started
function Preview.Start(opts)
    opts = type(opts) == "table" and opts or { mode = "test" }
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
    if mode == "sim" then NS.Sim.Enter(opts.scenario) else startTest() end
    repaintPanel()
    debug("%s on (%s)", mode, tostring(mode == "sim" and NS.Sim.Scenario() or "held"))
    return true
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
    if Preview.active then phase = mode == "sim" and sim.phase or "held" end
    return { active = Preview.active, mode = Preview.Mode() or "none", phase = phase,
             scenario = Preview.active and mode == "sim" and sim.scenario or "none",
             ticking = sim.ticking == true or laneTimer ~= nil }
end

-- A real fight starting (combat entry) ends the preview: the HUD and the lanes then show that fight.
do
    local bus = NS.NewBusTarget()
    if bus then
        bus:RegisterMessage(NS.MSG.FIGHT_STARTED, function()
            if Preview.active then Preview.Stop("combat") end
        end)
    end
end
