local _, NS = ...
-- modules/Casts.lua — each fight's cast list (spec §5, plan Task 2.4): every spell the player and the
-- pet cast in the fight, timed from its combat entry, for the stored record (packed by
-- modules/CastCodec.lua), the HUD's cooldown icons, the ability timeline and the usage detection
-- (modules/Usage.lua). Adapted from DPS Race @045f479 (modules/Casts.lua) without its race: no arm, no
-- race clock; a fight's own start is the zero.
--
-- THE SOURCE is the lanes' own capture: modules/LaneCasts.lua hands this file every cast its rules
-- keep (a SUCCEEDED once per castGUID, an interrupt of the cast in flight) through LaneCasts.Listen,
-- whatever each lane shows (a lane switched off, a spell on a lane's ignore list). No second
-- UNIT_SPELLCAST_* registration, and never COMBAT_LOG_EVENT_UNFILTERED. The auto-repeat swings and
-- shots (Casts.AUTO) are never a press and are left out.
--
-- SECRETS. A spell ID may arrive secret in combat: it passes through NS.Secrets before anything keys
-- or compares it, and a sealed one is dropped and counted (`dropped`), never stored as a nil key.
--
-- THE WINDOW. Casts are held raw ({ at = GetTime(), id, pet, x }) in one buffer. While no fight is
-- open the buffer keeps only the last Casts.PREPULL seconds; a fight's capture (FIGHT_STARTED) holds
-- from Casts.PREPULL seconds before its start, but never from before the end of the fight before it,
-- to its own end: the time it was parked (closedT), else its last combat end (combatEndT). So a
-- pre-pull cast is kept at a negative time, and a split or parked fight's casts are never the next
-- one's.
--
-- THE END. FIGHT_ENDED "final" turns the capture into its list at once (the buffer is let go); the
-- recorder (plan Task 2.5) takes it with Casts.Finish(fightID). Casts.KEEP_FINISHED lists wait for it,
-- the oldest dropped first. FIGHT_ENDED "lost" drops the capture. The stand-down drops everything.
--
-- THE LIST is { { t = seconds from the fight's start (to the tenth), spellID, unit = "player"|"pet",
-- interrupted } }, in heard order, with the spells' base cooldowns beside it ({ [id] = ms }, known
-- ones only) and the dropped count. Every value is plain.

local Casts = {}
NS.Casts = Casts

local Secrets = NS.Secrets
local Perf = NS.Perf

-- Auto-repeat attacks: Auto Attack, Auto Shot, Shoot (a wand). Every swing fires SUCCEEDED.
Casts.AUTO = { [6603] = true, [75] = true, [5019] = true }
-- How many seconds before a fight's start a cast still counts as its pre-pull.
Casts.PREPULL = 10
-- An important ability's base cooldown is at least this (ms): what the chart marks with an icon.
Casts.IMPORTANT_MS = 29000
-- How many ended fights' lists wait for the recorder.
Casts.KEEP_FINISHED = 4

local raw = {}          -- { { at, id|nil (sealed), pet, x } }, oldest first
local captures = {}     -- [fightID] = { fight, from }
local finished = {}     -- [fightID] = { casts, spells, dropped }
local finishedOrder = {}
local lastEnd = -math.huge   -- the latest end of a capture this session
local petSpells = {}    -- { [spellID] = true }: every pet spell heard this session
local cooldowns = {}    -- { [spellID] = ms | false }: base cooldowns asked so far

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Casts", fmt, ...) end
end

-- ── the buffer ──────────────────────────────────────────────────────────────────────────────────

-- The oldest time any open capture holds from, or `now` minus the pre-pull with none open.
local function horizon(now)
    local h
    for _, cap in pairs(captures) do
        if h == nil or cap.from < h then h = cap.from end
    end
    return h or (now - Casts.PREPULL)
end

local function trim(now)
    local h = horizon(now)
    if raw[1] == nil or raw[1].at >= h then return end
    local kept = {}
    for _, e in ipairs(raw) do
        if e.at >= h then kept[#kept + 1] = e end
    end
    raw = kept
end

--- One cast (the lanes' listener): `unit` "player" or "pet", `spellID` as the event gave it (may be
--- secret), `t` GetTime(), `interrupted` whether the cast in flight was interrupted.
function Casts.Record(unit, spellID, t, interrupted)
    if unit ~= "player" and unit ~= "pet" then return end
    local id = Secrets.PlainNumber(spellID)
    if id and Casts.AUTO[id] then return end
    local pet = unit == "pet"
    if id and pet then petSpells[id] = true end
    raw[#raw + 1] = { at = t, id = id, pet = pet, x = interrupted == true }
    trim(t)
end

local function onCast(unit, spellID, t, interrupted)
    local t0 = Perf.on and debugprofilestop()
    Casts.Record(unit, spellID, t, interrupted)
    if t0 then Perf.Note("casts", debugprofilestop() - t0) end
end

--- How many casts the buffer holds now (the suites' bound check).
function Casts.__rawCount()
    return #raw
end

-- ── a fight's capture ───────────────────────────────────────────────────────────────────────────

-- When a fight's casts stop counting: its parking, else its last combat end; nil while it fights on.
local function endOf(fight)
    return type(fight) == "table" and (fight.closedT or fight.combatEndT) or nil
end

-- The latest end among the captures still open (a fight parked or split before this one started).
local function floorAt()
    local f = lastEnd
    for _, cap in pairs(captures) do
        local e = endOf(cap.fight)
        if e and e > f then f = e end
    end
    return f
end

--- A fight started at `startT` (GetTime()): its casts are held from the pre-pull on. `fight` is the
--- fight table (FIGHT_STARTED's), read again at the end for when the fight stopped.
--- @param fightID string
--- @param startT number
--- @param fight table|nil
function Casts.Begin(fightID, startT, fight)
    if type(fightID) ~= "string" or type(startT) ~= "number" then return end
    captures[fightID] = { fight = fight or { startT = startT }, startT = startT,
                          from = math.max(startT - Casts.PREPULL, floorAt()) }
    trim(startT)
end

local function tenth(x)
    return math.floor(x * 10 + 0.5) / 10
end

local function cooldown(id)
    local ms = cooldowns[id]
    if ms == nil then
        local ok, v = pcall(NS.Compat.SpellBaseCooldown, id)
        ms = ok and Secrets.PlainNumber(v) or nil
        if not ms then ms = false end
        cooldowns[id] = ms
    end
    return ms or nil
end

-- The capture's list, its known base cooldowns and the dropped count, up to `to`.
local function listOf(cap, to)
    local casts, spells, dropped = {}, {}, 0
    for _, e in ipairs(raw) do
        if e.at >= cap.from and e.at <= to then
            if e.id == nil then
                dropped = dropped + 1
            else
                casts[#casts + 1] = { t = tenth(e.at - cap.startT), spellID = e.id, unit = e.pet and "pet" or "player",
                                      interrupted = e.x }
                local ms = cooldown(e.id)
                if ms and ms > 0 then spells[e.id] = ms end
            end
        end
    end
    return casts, spells, dropped
end

--- The fight's casts so far and their known base cooldowns (the HUD's cooldown icons), without
--- ending its capture; nil when it has none open.
--- @return table|nil casts, table|nil spells  { [id] = ms }
function Casts.Live(fightID)
    local cap = captures[fightID]
    if not cap then return nil end
    local casts, spells = listOf(cap, endOf(cap.fight) or GetTime())
    return casts, spells
end

-- The capture closes into its list; the buffer lets it go.
local function close(fightID)
    local cap = captures[fightID]
    if not cap then return nil end
    local to = endOf(cap.fight) or GetTime()
    local casts, spells, dropped = listOf(cap, to)
    captures[fightID] = nil
    if to > lastEnd then lastEnd = to end
    trim(GetTime())
    debug("fight %s: %d cast(s) kept, %d dropped", fightID, #casts, dropped)
    return { casts = casts, spells = spells, dropped = dropped }
end

local function park(fightID, done)
    finished[fightID] = done
    finishedOrder[#finishedOrder + 1] = fightID
    while #finishedOrder > Casts.KEEP_FINISHED do
        finished[table.remove(finishedOrder, 1)] = nil
    end
end

local function unpark(fightID)
    local done = finished[fightID]
    finished[fightID] = nil
    for i = #finishedOrder, 1, -1 do
        if finishedOrder[i] == fightID then table.remove(finishedOrder, i) end
    end
    return done
end

--- The fight's cast list, its spells' base cooldowns ({ [id] = ms }, known ones only) and how many
--- casts were dropped as sealed; nil when the fight has none (lost, never begun, or taken already).
--- Answers once: the capture is let go.
--- @return table|nil casts, table|nil spells, number|nil dropped
function Casts.Finish(fightID)
    local done = unpark(fightID) or close(fightID)
    if not done then return nil end
    return done.casts, done.spells, done.dropped
end

--- Let a fight's capture go without a list (a lost fight).
function Casts.Drop(fightID)
    unpark(fightID)
    if captures[fightID] then
        captures[fightID] = nil
        trim(GetTime())
    end
end

--- Every spell the pet cast this session, { [spellID] = true } (modules/Meter.lua's PET_SEPARATE =
--- false seam tags the meter's spells with it). A copy.
--- @return table
function Casts.PetSpellSet()
    local out = {}
    for id in pairs(petSpells) do out[id] = true end
    return out
end

--- The lifecycle's stand-down: every capture, list and buffered cast goes.
function Casts.Suspend()
    raw, captures, finished, finishedOrder = {}, {}, {}, {}
    lastEnd = -math.huge
end

-- ── the pure helpers (the chart's icons, the ability timeline) ──────────────────────────────────

--- Whether a base cooldown (ms) is a long one: at least IMPORTANT_MS (29 s).
function Casts.IsLong(ms)
    return type(ms) == "number" and ms >= Casts.IMPORTANT_MS
end

local function byImportance(a, b)
    local ia, ib = Casts.IsLong(a.cd), Casts.IsLong(b.cd)
    if ia ~= ib then return ia end
    if ia and a.cd ~= b.cd then return a.cd > b.cd end
    if a.count ~= b.count then return a.count > b.count end
    if a.unit ~= b.unit then return a.unit == "player" end
    return a.spellID < b.spellID
end

--- The casts grouped by ability and caster (the timeline's rows), each group's times in order:
--- long cooldowns first, longest first; then the rest by count.
--- @param casts table|nil
--- @param spells table|nil  { [id] = ms }
--- @return table groups  { { spellID, unit, cd (ms, 0 when unknown), count, times = { t, ... } }, ... }
function Casts.Group(casts, spells)
    local groups, index = {}, {}
    for _, c in ipairs(casts or {}) do
        local key = c.unit .. ":" .. c.spellID
        local g = index[key]
        if not g then
            local ms = type(spells) == "table" and spells[c.spellID]
            g = { spellID = c.spellID, unit = c.unit, cd = type(ms) == "number" and ms or 0, count = 0, times = {} }
            index[key] = g
            groups[#groups + 1] = g
        end
        g.count = g.count + 1
        g.times[g.count] = c.t
    end
    for _, g in ipairs(groups) do table.sort(g.times) end
    table.sort(groups, byImportance)
    return groups
end

-- ── wiring ──────────────────────────────────────────────────────────────────────────────────────

NS.LaneCasts.Listen("casts", onCast)

local busTarget = NS.NewBusTarget()
if busTarget then
    busTarget:RegisterMessage(NS.MSG.FIGHT_STARTED, function(_, fight)
        if type(fight) == "table" then Casts.Begin(fight.id, fight.startT, fight) end
    end)
    busTarget:RegisterMessage(NS.MSG.FIGHT_ENDED, function(_, fight, _, reason)
        if type(fight) ~= "table" then return end
        if reason == "final" then
            local done = close(fight.id)
            if done then park(fight.id, done) end
        else
            Casts.Drop(fight.id)
        end
    end)
end
