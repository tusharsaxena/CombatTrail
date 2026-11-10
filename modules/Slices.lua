local _, NS = ...
-- modules/Slices.lua — the damage chart's in-session store (spec §6 and §7, plan Task 2.6): the
-- fight's live damage total, copied once per fixed step of the fight clock, held in memory by fight
-- id, so the HUD can draw the fight's damage curve live and the HUD's fight-over card and the Results
-- detail can draw it again after combat. Adapted from DPS Race @045f479 (modules/Slices.lua) without
-- its race: no race length, no buzzer, no shared session. A fight has no length until it ends, so the
-- store grows by step and the chart's columns are worked out from the steps (Slices.Columns).
--
-- THE STEPS are plain: one every Slices.STEP seconds of the fight clock (zero at the fight's combat
-- entry, fight.startT, the same zero as the cast list), up to Slices.MAX_STEPS. On the first live read
-- at or after a step's boundary, that read's player total and pet total are COPIED into the step. The
-- values are never inspected: no arithmetic, no comparison, no truth test, never a key. The one
-- question asked of a value is `== nil`.
--
-- THE COLUMNS. The chart draws at most Slices.MAX columns. A column is Slices.Width(length) seconds
-- wide, the plan's max(1, floor(length / 60) + 1) seconds rounded up to whole steps, so it grows with
-- the fight. Re-bucketing never sums: each value is the fight's running total at its step, so a
-- column that spans several steps takes the total of its latest filled step, a copy. The same rule
-- holds for a secret and a plain value, and nothing is computed from either. Slices.Tail is the other
-- live view: the last Slices.MAX steps, one column a step.
--
-- HONEST HOLES. A boundary that passed more than LATE seconds before the read that noticed it, or one
-- passed while the fight had no session bound, leaves its step empty rather than fill it with a later
-- total. A read with no total keeps a recent boundary open for the next read.
--
-- THE READS. FIGHT_STARTED opens the fight's store and FIGHT_TICK (4 Hz, combat only) reads
-- Meter.ReadLive once per step, never more often: the tick only reads when a boundary is due. A merged
-- fight reads its newest session. FIGHT_ENDED "final" closes the store, which waits for the record
-- (Recorder sets fight.recordID, so Slices.Get answers a record id too); "lost" forgets it. Slices.KEEP
-- closed fights are held, the oldest let go first.
--
-- IN MEMORY ONLY, NEVER STORED. A value captured in combat stays secret, and the client writes a
-- secret to SavedVariables as nil, so a fight recorded before the last /reload or login has no chart
-- (spec §3). Nothing here writes to the record.

local Slices = {}
NS.Slices = Slices

local Perf = NS.Perf

--- Seconds of the fight clock per step.
Slices.STEP = 2
--- The most columns the chart draws.
Slices.MAX = 60
--- The most steps one fight holds (an hour): a longer fight keeps its first hour.
Slices.MAX_STEPS = 1800
--- How late (seconds) a read may notice a boundary and still fill its step.
Slices.LATE = 1.0
--- How many ended fights keep their store.
Slices.KEEP = 50
-- Float slack on a boundary: a read AT the boundary counts as at or after it.
local EPS = 1e-6

local store = {}     -- [fight id] = { step, values, pet, count, filled, next, expected, open, fight }
local closed = {}    -- closed fight ids, oldest first
local alias = {}     -- [record id] = fight id, filled on the first lookup

-- ── the plain math ──────────────────────────────────────────────────────────────────────────────

--- How many steps each column spans for a chart of `length` seconds.
--- @param length number|nil
--- @return number k
local function stepsPerColumn(length)
    local n = math.max(0, tonumber(length) or 0)
    local width = math.max(1, math.floor(n / Slices.MAX) + 1)
    local k = math.ceil(width / Slices.STEP)
    while math.ceil(n / Slices.STEP / k) > Slices.MAX do k = k + 1 end
    return k
end

--- A chart column's width in seconds for a fight of `length` seconds: grows with the fight, so the
--- chart never draws more than MAX columns. Always a whole number of steps.
--- @param length number|nil
--- @return number seconds
function Slices.Width(length)
    return stepsPerColumn(length) * Slices.STEP
end

--- Step `i`'s end boundary, in seconds of the fight clock.
function Slices.Boundary(i)
    return i * Slices.STEP
end

-- ── the store ───────────────────────────────────────────────────────────────────────────────────

local function newRecord(expected)
    return { step = Slices.STEP, values = {}, pet = {}, count = 0, filled = 0, next = 1,
             expected = expected, open = true }
end

local function plainLength(v)
    return type(v) == "number" and v > 0 and v or nil
end

--- Open fight `fightID`'s store. Called again on an open store, it keeps what was captured and only
--- takes the new expected length (the HUD's pace, when the best's length is known).
--- @param fightID any  a plain fight id
--- @param expectedLen number|nil  seconds the chart should span before the fight reaches them
--- @return table|nil rec
function Slices.Begin(fightID, expectedLen)
    if fightID == nil then return nil end
    local rec = store[fightID]
    if rec then
        rec.expected = plainLength(expectedLen) or rec.expected
        rec.view = nil
        return rec
    end
    rec = newRecord(plainLength(expectedLen))
    store[fightID] = rec
    return rec
end

-- Copy one read into step `rec.next` when it came in time; advance past it either way.
local function passBoundary(rec, recent, total, pet)
    if recent then
        local i = rec.next
        rec.values[i] = total
        rec.pet[i] = pet
        rec.filled = rec.filled + 1
    end
    rec.next = rec.next + 1
    rec.count = rec.next - 1
    rec.view, rec.tail = nil, nil
    return recent and 1 or 0
end

--- A live read `t` seconds into fight `fightID` answered `total` (and the pet's `pet`): copy them
--- into every step whose boundary this is the first read at or after. A boundary too far behind
--- (LATE) is passed with its step left empty; a read with no total (nil) fills nothing and leaves a
--- recent boundary for the next read.
--- @param fightID any
--- @param t number  plain seconds from the fight's start
--- @param total any  the player's live total, possibly secret, or nil; only copied
--- @param pet any  the pet's live total, possibly secret, or nil; only copied
--- @return number filled  steps filled by this read
function Slices.Record(fightID, t, total, pet)
    local rec = fightID ~= nil and store[fightID]
    if not rec or not rec.open or type(t) ~= "number" then return 0 end
    local n = 0
    while rec.next <= Slices.MAX_STEPS do
        local boundary = Slices.Boundary(rec.next)
        if t + EPS < boundary then break end
        local recent = t - boundary <= Slices.LATE
        if recent and total == nil then break end
        n = n + passBoundary(rec, recent, total, pet)
    end
    return n
end

--- The fight-clock time of fight `fightID`'s next step boundary, or nil (no open store, or full).
function Slices.NextBoundary(fightID)
    local rec = fightID ~= nil and store[fightID]
    if not rec or not rec.open or rec.next > Slices.MAX_STEPS then return nil end
    return Slices.Boundary(rec.next)
end

local function byRecordID(id)
    local fightID = alias[id]
    if fightID ~= nil and store[fightID] then return store[fightID] end
    for fid, rec in pairs(store) do
        if type(rec.fight) == "table" and rec.fight.recordID == id then
            alias[id] = fid
            return rec
        end
    end
    return nil
end

--- The store of a fight, by its fight id or by the id of the record it became: { step, values, pet,
--- count, filled, expected, open }, or nil when this session holds none.
--- @param id any
--- @return table|nil
function Slices.Get(id)
    if id == nil or not NS.Secrets.IsSafeKey(id) then return nil end
    return store[id] or byRecordID(id)
end

-- The latest filled step in steps from..to, or nil: only `~= nil` is asked of a value.
local function latestFilled(values, from, to)
    for i = to, from, -1 do
        if values[i] ~= nil then return i end
    end
    return nil
end

local function buildColumns(rec, k, length)
    local count = math.min(Slices.MAX, math.max(1, math.ceil(length / (k * Slices.STEP))))
    local view = { step = k * Slices.STEP, count = count, values = {}, pet = {}, filled = 0,
                   k = k, steps = rec.count }
    for j = 1, math.min(count, math.ceil(rec.count / k)) do
        local i = latestFilled(rec.values, (j - 1) * k + 1, math.min(j * k, rec.count))
        if i then
            view.values[j], view.pet[j] = rec.values[i], rec.pet[i]
            view.filled = view.filled + 1
        end
    end
    return view
end

--- The chart's view of a fight: at most MAX columns, each Width(length) seconds of the fight clock,
--- holding the running total at its latest filled step (copied, never summed). `length` defaults to
--- the longer of the expected length and the steps so far. Cached until the next capture.
--- @param id any  a fight id or a record id
--- @param length number|nil  seconds the chart spans
--- @return table|nil view  { step (seconds a column), count, values, pet, filled }
function Slices.Columns(id, length)
    local rec = Slices.Get(id)
    if not rec then return nil end
    local span = plainLength(length) or math.max(rec.expected or 0, rec.count * Slices.STEP)
    local k = stepsPerColumn(span)
    local view = rec.view
    if view and view.k == k and view.steps == rec.count and view.span == span then return view end
    view = buildColumns(rec, k, span)
    view.span = span
    rec.view = view
    return view
end

--- The live chart's other view: the last MAX steps, one column a step. Cached until the next capture.
--- @param id any  a fight id or a record id
--- @return table|nil view  { step, first (the first step's index), count, values, pet }
function Slices.Tail(id)
    local rec = Slices.Get(id)
    if not rec then return nil end
    if rec.tail then return rec.tail end
    local first = math.max(1, rec.count - Slices.MAX + 1)
    local view = { step = Slices.STEP, first = first, count = rec.count - first + 1, values = {}, pet = {} }
    for i = first, rec.count do
        view.values[i - first + 1], view.pet[i - first + 1] = rec.values[i], rec.pet[i]
    end
    rec.tail = view
    return view
end

--- The store the after-combat chart draws for a stored record, or nil when there is none: not a final
--- record, no plain damage to scale to, or no step filled this session.
--- @param record table
--- @return table|nil rec
function Slices.Drawable(record)
    if type(record) ~= "table" or record.status ~= "final" then return nil end
    local damage = type(record.damage) == "table" and record.damage.merged
    if type(damage) ~= "number" or damage <= 0 then return nil end
    local rec = Slices.Get(record.id)
    if not rec or rec.filled == 0 then return nil end
    return rec
end

-- ── the fight's end ─────────────────────────────────────────────────────────────────────────────

local function forgetAlias(fightID)
    for rid, fid in pairs(alias) do
        if fid == fightID then alias[rid] = nil end
    end
end

--- Drop one fight's store (a lost fight, a sample fight going away).
--- @param id any  a fight id
function Slices.Forget(id)
    if id == nil or store[id] == nil then return end
    store[id] = nil
    forgetAlias(id)
    for i = #closed, 1, -1 do
        if closed[i] == id then table.remove(closed, i) end
    end
end

--- Close fight `fightID`'s store: it takes no more reads and waits for its record; the oldest closed
--- stores past KEEP are let go.
function Slices.Close(fightID)
    local rec = fightID ~= nil and store[fightID]
    if not rec or not rec.open then return end
    rec.open = false
    closed[#closed + 1] = fightID
    while #closed > Slices.KEEP do Slices.Forget(closed[1]) end
end

--- Put a ready-made store under `id`: a sample fight's chart (test mode, plan Task 5.1), drawn by the
--- same path as a real one.
--- @param id any
--- @param rec table  { step, values, pet, count, filled }
function Slices.Seed(id, rec)
    if id == nil or type(rec) ~= "table" then return end
    rec.pet = rec.pet or {}
    store[id] = rec
end

--- How many fights this session hold a store (the diagnostics report).
function Slices.Held()
    local n = 0
    for _ in pairs(store) do n = n + 1 end
    return n
end

--- Drop every store (the suites).
function Slices.Reset()
    store, closed, alias = {}, {}, {}
end

--- The stand-down: a fight still open is dropped without a message (modules/Fight.lua's Suspend), so
--- its store goes too; the closed ones keep their charts.
function Slices.Suspend()
    for id, rec in pairs(store) do
        if rec.open then store[id] = nil end
    end
end

-- ── the reads ───────────────────────────────────────────────────────────────────────────────────

-- The session a fight's live read asks for: its newest, or nil while none is bound.
local function liveSession(fight)
    local sessions = fight.sessions
    if type(sessions) == "table" and #sessions > 0 then return sessions[#sessions] end
    return fight.sessionID
end

local function readStep(fight, elapsed)
    local id = liveSession(fight)
    if id == nil then return Slices.Record(fight.id, elapsed, nil, nil) end
    local live = NS.Meter.ReadLive(id)
    local player, pet = live and live.player, live and live.pet
    return Slices.Record(fight.id, elapsed, player and player.total, pet and pet.total)
end

--- FIGHT_TICK's receiver: one live read when a step boundary is due, none otherwise. With no session
--- bound a due boundary is passed with no read, so it becomes a hole once it is LATE behind.
--- @param fight table
--- @param now number|nil  GetTime(), for the suites
--- @return number filled
function Slices.OnTick(fight, now)
    if type(fight) ~= "table" or type(fight.startT) ~= "number" then return 0 end
    local at = Slices.NextBoundary(fight.id)
    if not at then return 0 end
    local elapsed = (now or GetTime()) - fight.startT
    if elapsed + EPS < at then return 0 end
    local t0 = Perf.on and debugprofilestop()
    local n = readStep(fight, elapsed)
    if t0 then Perf.Note("slices", debugprofilestop() - t0) end
    return n
end

local busTarget = NS.NewBusTarget and NS.NewBusTarget()
if busTarget then
    busTarget:RegisterMessage(NS.MSG.FIGHT_STARTED, function(_, fight)
        if type(fight) ~= "table" then return end
        local rec = Slices.Begin(fight.id)
        if rec then rec.fight = fight end
    end)
    busTarget:RegisterMessage(NS.MSG.FIGHT_TICK, function(_, fight) Slices.OnTick(fight) end)
    busTarget:RegisterMessage(NS.MSG.FIGHT_ENDED, function(_, fight, _, reason)
        if type(fight) ~= "table" then return end
        if reason == "final" then Slices.Close(fight.id) else Slices.Forget(fight.id) end
    end)
end
