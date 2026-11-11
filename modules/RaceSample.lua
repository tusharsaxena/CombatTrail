local _, NS = ...
-- modules/RaceSample.lua — the sample race (race plan Task E1, R:test-sim#3): the stand-in for NS.Race
-- the Race window (modules/RaceWindow.lua) and the countdown (modules/Countdown.lua) read while test
-- mode holds a sample race (`/ct test race [armed|running|result]`, modules/Preview.lua) or the sim
-- plays a race scenario (modules/SimRace.lua). Ported from DPS Race @f8078c7 (modules/SampleRace.lua):
-- it answers Race's query surface (State, Current, Fight, Result, Elapsed, TimeLeft, SinceBuzzer,
-- LastDamage, StopRequested, DefaultLength) so every body is drawn by one path.
--
-- IT NEVER MOVES NS.Race, AND NOTHING OF IT REACHES THE BUS. Combat Trail's rule for a sample (modules/
-- Preview.lua's header) is a hand-over, never a message: the owner (Preview or SimRace) sets the state
-- here and calls the windows itself. The Race window's Cancel and Stop Now act on the sample, never on a
-- real race: a Cancel (the result card's close, Cancel on the armed body) ends the preview; Stop Now
-- marks it for the sim to read at once.
--
-- TWO CLOCKS. Held (test mode): the race clock stands at the held moment (`at`), and the countdown is
-- the real race's (none). Live (the sim): the clock runs from the first hit's GetTime() (SimRace's
-- beat sets it), and the countdown reads the sample (RaceSample.Live).
--
-- RETAIL ONLY (clients-§4): races are Retail's, so on WoW Forever this file returns at once.

if not NS.Compat.ForClient({ "retail" }) then return end

local RS = {}
NS.RaceSample = RS

-- The sample race: { state, race, fight, record, live (the sim's clock runs), at (the held clock),
-- startedAt, buzzerAt, lastDamage, inCombat, stopNow }; nil when none.
local held

local function STATE() return NS.Race.STATE end

--- Whether a sample race stands in for the real one now.
function RS.On() return held ~= nil end

--- Whether the sample's clock runs (the sim), so the countdown reads it.
function RS.Live() return held ~= nil and held.live == true end

local function moving()
    local st = held and held.state
    return st == STATE().RUNNING or st == STATE().STOPPING
end

--- Hold `sample` (MockRaces.Sample's) in `state` ("armed" | "running" | "result"), its clock still at
--- `at` seconds past the first hit (test mode).
function RS.Hold(sample, state, at)
    held = { state = state, race = sample.race, fight = sample.fight, record = sample.record, at = at or 0,
             inCombat = state == "running" }
    if state == "result" then held.race = sample.record.race end
    if state == "running" then held.lastDamage = at end
end

--- Start `sample` armed, on a live clock (the sim). SimRace.Set moves it on.
function RS.Start(sample)
    held = { state = STATE().ARMED, race = sample.race, fight = sample.fight, live = true, inCombat = false }
end

--- Move the live sample on: any of { state, startedAt, buzzerAt, lastDamage, inCombat, record, race }.
function RS.Set(fields)
    if not held then return end
    for k, v in pairs(fields) do held[k] = v end
end

--- The sample goes; the windows read the real race again.
function RS.Clear() held = nil end

-- ── Race's query surface ────────────────────────────────────────────────────────────────────────

function RS.State() return held and held.state or STATE().IDLE end
function RS.Current() return held and held.race or nil end
function RS.Fight() return held and held.fight or nil end

function RS.Result()
    if not held or held.state ~= STATE().RESULT then return nil end
    return held.record
end

function RS.Elapsed()
    if not moving() then return nil end
    if not held.live then return held.at end
    if not held.startedAt then return nil end
    return GetTime() - held.startedAt
end

function RS.TimeLeft()
    if not moving() then return nil end
    if held.state == STATE().STOPPING then return 0 end
    local elapsed = RS.Elapsed()
    if not elapsed then return nil end
    return math.max(0, held.race.length - elapsed)
end

function RS.SinceBuzzer()
    if not held or held.state ~= STATE().STOPPING or not held.buzzerAt then return nil end
    return GetTime() - held.buzzerAt
end

function RS.LastDamage()
    if not moving() then return nil end
    return held.lastDamage
end

function RS.StopRequested()
    return held ~= nil and held.state == STATE().STOPPING and held.stopNow == true
end

--- Whether the sample's player is in combat (the waiting body's hint reads it).
function RS.InCombat() return held ~= nil and held.inCombat == true end

function RS.DefaultLength() return NS.Race.DefaultLength() end

-- ── the acts the Race window runs on it ─────────────────────────────────────────────────────────

--- The sample's Cancel (Cancel on the armed body, the result card's close): the preview ends. A real
--- race is never touched.
--- @return boolean acted
function RS.Cancel()
    if not held then return false end
    held = nil
    if NS.Preview and NS.Preview.IsActive() then NS.Preview.Stop() end
    return true
end

--- The sample's Stop Now: the sim reads it at once once combat is over.
--- @return boolean acted
function RS.StopNow()
    if not (held and held.state == STATE().STOPPING) or held.stopNow then return false end
    held.stopNow = true
    return true
end

--- What the sample is doing, for the diagnostics report.
function RS.Diagnose()
    return { on = held ~= nil, state = held and held.state or "none", live = RS.Live() }
end
