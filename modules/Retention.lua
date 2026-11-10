local _, NS = ...
-- modules/Retention.lua — how long stored fights are kept (spec §5, plan Task 2.5). The purge removes
-- every fight older than `history.days` days (0 keeps them for ever), except a fight holding a best
-- while `history.keepBests` is on (modules/Bests.lua), then caps the store at `history.maxFights`
-- (0 is no cap): the oldest non-best fights go first. It runs at login (and every stand-up), once a
-- day while logged in (out of combat), and from `/kct purge`. Each run also puts db.global.fightOrder back in step
-- with the store (newest first, no id without its record), and sweeps the talent loadouts no fight
-- refers to any more (modules/Loadouts.lua). FIGHTS_CHANGED fires once when anything was removed.
--
-- A record written by a later version (modules/Recorder.lua's Recorder.Known) is never removed and
-- never listed.
--
-- THE DAILY RUN is an AceTimer on the addon object: the stand-down's CancelAllTimers takes it, and
-- Retention.Sync (from NS.RegisterGameEvents) arms it again at the stand-up. It registers no event.
--
-- THE SIZE. Retention.EstimateBytes answers about how many bytes the store takes in SavedVariables,
-- for the History page's count and size (plan Task 4.5). Retention.SizeOf measures one value the way
-- the client writes it: `["key"] = value,` lines, one tab per level, `-- [n]` after an array entry.

local Retention = {}
NS.Retention = Retention

local Secrets = NS.Secrets
local L = NS.L

Retention.DAY = 86400
--- How often the purge runs while logged in (seconds).
Retention.PERIOD = 86400

--- How soon a daily run that landed in a fight is asked again (seconds).
Retention.RETRY = 60

local timer

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Retention", fmt, ...) end
end

local function setting(key)
    return NS.GetSetting and NS.GetSetting("history." .. key)
end

local function wholeOr0(v)
    v = Secrets.PlainNumber(v)
    if not v or v < 1 then return 0 end
    return math.floor(v)
end

-- ── the purge ───────────────────────────────────────────────────────────────────────────────────

local function newerFirst(a, b)
    local ta, tb = a.t or 0, b.t or 0
    if ta ~= tb then return ta > tb end
    return tostring(a.id) > tostring(b.id)
end

-- The records this version reads, newest first, straight from the store (not the order, which this
-- run repairs).
local function known(fights)
    local out = {}
    for id, r in pairs(fights) do
        if NS.Recorder.Known(r) and r.id == id then out[#out + 1] = r end
    end
    table.sort(out, newerFirst)
    return out
end

-- Remove the records older than the cutoff that hold no best; answers the survivors, newest first.
local function byAge(records, holding, now, fights)
    local days = wholeOr0(setting("days"))
    if days == 0 then return records, 0 end
    local cutoff, kept, removed = now - days * Retention.DAY, {}, 0
    for _, r in ipairs(records) do
        if type(r.t) == "number" and r.t < cutoff and not holding[r.id] then
            fights[r.id] = nil
            removed = removed + 1
        else
            kept[#kept + 1] = r
        end
    end
    return kept, removed
end

-- Remove the oldest non-best records until no more than the cap remain.
local function byCap(records, holding, fights)
    local cap = wholeOr0(setting("maxFights"))
    local excess = cap > 0 and #records - cap or 0
    if excess <= 0 then return records, 0 end
    local gone = {}
    for i = #records, 1, -1 do
        if excess == 0 then break end
        local r = records[i]
        if not holding[r.id] then
            gone[r.id], fights[r.id] = true, nil
            excess = excess - 1
        end
    end
    local kept, removed = {}, 0
    for _, r in ipairs(records) do
        if gone[r.id] then removed = removed + 1 else kept[#kept + 1] = r end
    end
    return kept, removed
end

--- Purge the store to the History settings, measured from `now`.
--- @param now number|nil  the epoch ages are measured from (time())
--- @return number removed
function Retention.Purge(now)
    local g = NS.db and NS.db.global
    if type(g) ~= "table" or type(g.fights) ~= "table" then return 0 end
    now = Secrets.PlainNumber(now) or time()
    local fights = g.fights
    local records = known(fights)
    local holding = setting("keepBests") == true and NS.Bests.HoldingIDs(records) or {}
    local aged, cut
    records, aged = byAge(records, holding, now, fights)
    records, cut = byCap(records, holding, fights)
    local order = {}
    for i, r in ipairs(records) do order[i] = r.id end
    g.fightOrder = order
    local removed = aged + cut
    if removed > 0 then
        debug("purged %d fight(s): %d by age, %d over the cap", removed, aged, cut)
        if NS.Loadouts and NS.Loadouts.Sweep then NS.Loadouts.Sweep(fights) end
        if NS.Bests then NS.Bests.Invalidate() end
        NS.SendBus(NS.MSG.FIGHTS_CHANGED)
    end
    return removed
end

-- ── when it runs ────────────────────────────────────────────────────────────────────────────────

local function arm(delay)
    local addon = NS.addon
    if addon and addon.CancelTimer and timer then addon:CancelTimer(timer) end
    timer = nil
    if addon and addon.ScheduleTimer then
        timer = addon:ScheduleTimer(Retention.OnTimer, delay or Retention.PERIOD)
    end
end

-- In combat, or while a fight is open or settling, the purge waits (docs/performance.md).
local function busy()
    if InCombatLockdown and InCombatLockdown() then return true end
    return NS.Fight ~= nil and NS.Fight.Current() ~= nil
end

--- The daily run: purge, then arm the next one. A run that lands in a fight is asked again shortly.
function Retention.OnTimer()
    timer = nil
    if NS.IsStoodDown and NS.IsStoodDown() then return end
    if busy() then return arm(Retention.RETRY) end
    Retention.Purge(time())
    arm()
end

--- The login (and stand-up) run, from NS.RegisterGameEvents: purge now and arm the daily timer.
function Retention.Sync()
    Retention.Purge(time())
    arm()
end

--- The stand-down: the timer went with CancelAllTimers; forget its handle.
function Retention.Suspend()
    timer = nil
end

--- The daily timer's handle, or nil while none is armed (the suites).
function Retention.Timer()
    return timer
end

--- `/kct purge`: purge now and say how many fights went, in one line.
function Retention.OnVerb()
    local removed = Retention.Purge(time())
    if removed == 0 then
        NS.Print(L["No stored fight was old enough to remove."])
    elseif removed == 1 then
        NS.Print(L["Removed 1 stored fight."])
    else
        NS.Print(L["Removed %d stored fights."]:format(removed))
    end
    return removed
end

-- ── the size ────────────────────────────────────────────────────────────────────────────────────

local sizeOf

local function keySize(k)
    if type(k) == "number" then return #tostring(k) + 2 end      -- [1]
    return #tostring(k) + 4                                        -- ["k"]
end

local function scalarSize(v)
    local kind = type(v)
    if kind == "string" then return #("%q"):format(v) end
    if kind == "number" then return #("%.14g"):format(v) end
    if kind == "boolean" then return v and 4 or 5 end
    return 3                                                       -- nil
end

local function tableSize(t, depth)
    local bytes, n = 2, #t                    -- "{" and "}" (the newline after "{" is counted below)
    for i = 1, n do
        -- tabs, the value, ", -- [i]" and the newline
        bytes = bytes + depth + sizeOf(t[i], depth + 1) + 8 + #tostring(i) + 1
    end
    for k, v in pairs(t) do
        if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
            -- tabs, the key, " = ", the value, "," and the newline
            bytes = bytes + depth + keySize(k) + 3 + sizeOf(v, depth + 1) + 2
        end
    end
    return bytes + 1 + depth - 1
end

sizeOf = function(v, depth)
    if type(v) == "table" then return tableSize(v, depth) end
    return scalarSize(v)
end

--- About how many bytes `v` takes in a SavedVariables file.
--- @return number bytes
function Retention.SizeOf(v)
    return sizeOf(v, 1)
end

--- About how many bytes the fight store takes in SavedVariables: the fights, their order and the
--- talent loadouts they refer to.
--- @return number bytes
function Retention.EstimateBytes()
    local g = NS.db and NS.db.global
    if type(g) ~= "table" then return 0 end
    return Retention.SizeOf(g.fights or {}) + Retention.SizeOf(g.fightOrder or {})
        + Retention.SizeOf(g.loadouts or {})
end
