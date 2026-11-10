local _, NS = ...
-- modules/Recorder.lua — the fight record and its store (spec §5, plan Task 2.5). Adapted from DPS
-- Race @045f479 (modules/Recorder.lua) without its race: no arming, no pending run a /reload resumes,
-- no race settings frozen in. Its snapshots moved out: who, the target and where are
-- modules/Identity.lua's (taken at combat entry), the loadout modules/Loadouts.lua's and the stats
-- modules/Stats.lua's.
--
-- THE FLOW. FIGHT_ENDED (modules/Fight.lua) is the one input. "lost" is skipped as "lost". "final"
-- is resolved (Identity.Resolve over the meter's enemies, summed across a merged fight's sessions),
-- timed (the meter's session duration, else the fight's own combat-entry-to-end clock), and put
-- through the recording filters (modules/Filters.lua): FIGHT_SKIPPED(fight, "short" | "filtered"),
-- or, once it passes them, "unknown" when no character can be read (a record must say whose fight it
-- was), so a short fight reads "short" whoever fought it. A fight that
-- passes becomes a record, stored, and FIGHT_SAVED(record). An Unknown TARGET is still stored (spec
-- §5): it has no board key and never counts as a best (modules/Bests.lua).
--
-- NOTHING IS WRITTEN BEFORE FIGHT_ENDED "final": a fight in memory is never a partial record, so a
-- /reload or a logout mid-fight leaves the store as it was (Review Focus 4).
--
-- SECRETS. No secret ever enters the record (spec §5). The parts it is built from are plain by their
-- own contracts (Meter.ReadFinal answers nil while anything is secret; Identity, Stats, Loadouts and
-- Usage pass every client value through NS.Secrets), and the whole record is still copied through
-- plainCopy below before it is stored: a value or key that is sealed is left absent, never kept.
--
-- THE STORE is db.global.fights ({ [id] = record }) and db.global.fightOrder ({ id, ... }, newest
-- first): account-wide, so a profile switch never hides a character's history and bests span alts.
-- Save fires FIGHT_SAVED; Delete and SetNote fire FIGHTS_CHANGED; the purge is modules/Retention.lua's.
-- A record written by a later version (a higher `schema` than this one knows) is never listed.
--
-- THE RECORD (CT_SCHEMA 1): { schema, id, t (time() at combat entry), duration, who, identity,
-- boardKey, damage = { merged, player, pet? }, dps, meterDps?, spells (CastCodec.EncodeSpells'
-- packed string; Recorder.Spells unpacks it to { { spellID, total, isPet } }), casts (CastCodec's
-- packed string), cooldowns ({ [spellID] = ms }, the timeline's),
-- gear ({ [slot] = item string }), stats, loadout (Loadouts' key), usage, note?, client, build,
-- version, status = "final" }.

local Recorder = {}
NS.Recorder = Recorder

local Secrets = NS.Secrets
local L = NS.L

--- The fight record's format version (spec §5). Distinct from NS.SCHEMA_VERSION, the settings'.
Recorder.CT_SCHEMA = 2
--- The longest note a record keeps.
Recorder.NOTE_MAX = 200

-- An id is time() .. "-" .. a four-digit random; a clash with a stored fight is redrawn this often.
local ID_ATTEMPTS = 32
-- How deep plainCopy walks (a record is four levels deep at most; this is a guard, not a shape).
local MAX_DEPTH = 8

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Recorder", fmt, ...) end
end

-- ── the store ───────────────────────────────────────────────────────────────────────────────────

local function store()
    local db = NS.db
    local g = db and db.global
    if type(g) ~= "table" then return nil end
    if type(g.fights) ~= "table" then g.fights = {} end
    if type(g.fightOrder) ~= "table" then g.fightOrder = {} end
    return g.fights, g.fightOrder
end

--- Whether `record` is one this version reads: a table not written by a later format.
--- @return boolean
function Recorder.Known(record)
    return type(record) == "table"
        and not (type(record.schema) == "number" and record.schema > Recorder.CT_SCHEMA)
end

local function newID()
    local fights = store() or {}
    local stamp = tostring(time())
    local id
    for _ = 1, ID_ATTEMPTS do
        id = stamp .. "-" .. math.random(1000, 9999)
        if fights[id] == nil then return id end
    end
    return id .. math.random(1000, 9999)
end

local function dropFromOrder(order, id)
    for i = #order, 1, -1 do
        if order[i] == id then table.remove(order, i) end
    end
end

local function invalidate()
    if NS.Bests and NS.Bests.Invalidate then NS.Bests.Invalidate() end
end

--- Store `record` under its id (replacing any earlier copy, which moves to the front) and fire
--- FIGHT_SAVED(record).
--- @return boolean saved  false for a record without a usable id, or before the DB exists
function Recorder.Save(record)
    local fights, order = store()
    if not fights or type(record) ~= "table" or not Secrets.IsSafeKey(record.id) then return false end
    if fights[record.id] ~= nil then dropFromOrder(order, record.id) end
    fights[record.id] = record
    table.insert(order, 1, record.id)
    invalidate()
    NS.SendBus(NS.MSG.FIGHT_SAVED, record)
    return true
end

--- The stored record with this id, or nil (none, or one from a later version).
function Recorder.Get(id)
    local fights = store()
    if not fights or not Secrets.IsSafeKey(id) then return nil end
    local r = fights[id]
    if not Recorder.Known(r) then return nil end
    return r
end

--- Every stored record this version reads, newest first, as a fresh array.
--- @return table records
function Recorder.List()
    local fights, order = store()
    local out = {}
    if not fights then return out end
    for _, id in ipairs(order) do
        local r = Secrets.IsSafeKey(id) and fights[id] or nil
        if Recorder.Known(r) then out[#out + 1] = r end
    end
    return out
end

--- An iterator over the stored records, newest first: `for record in Recorder.All() do`.
function Recorder.All()
    local list, i = Recorder.List(), 0
    return function()
        i = i + 1
        return list[i]
    end
end

--- How many records the store lists.
function Recorder.Count()
    return #Recorder.List()
end

--- Remove one record. Fires FIGHTS_CHANGED only when something was removed.
--- @return boolean removed
function Recorder.Delete(id)
    local fights, order = store()
    if not fights or not Secrets.IsSafeKey(id) or fights[id] == nil then return false end
    fights[id] = nil
    dropFromOrder(order, id)
    if NS.Loadouts and NS.Loadouts.Sweep then NS.Loadouts.Sweep(fights) end
    invalidate()
    NS.SendBus(NS.MSG.FIGHTS_CHANGED)
    return true
end

--- Store a record's note: trimmed, clamped to NOTE_MAX, and an empty one removes it. Fires
--- FIGHTS_CHANGED.
--- @return boolean stored
function Recorder.SetNote(id, text)
    local r = Recorder.Get(id)
    if not r then return false end
    local note = Secrets.PlainString(text) or ""
    note = note:gsub("^%s+", ""):gsub("%s+$", "")
    if #note > Recorder.NOTE_MAX then note = note:sub(1, Recorder.NOTE_MAX) end
    r.note = note ~= "" and note or nil
    NS.SendBus(NS.MSG.FIGHTS_CHANGED)
    return true
end

-- ── building the record ─────────────────────────────────────────────────────────────────────────

--- `v` with every sealed value and key left out, as a fresh plain copy (strings, numbers, booleans
--- and tables of them). nil for a sealed value, a function or anything else.
local function plainCopy(v, depth)
    if v == nil or Secrets.IsSealed(v) then return nil end
    local kind = type(v)
    if kind == "string" or kind == "number" or kind == "boolean" then return v end
    if kind ~= "table" or depth > MAX_DEPTH or not Secrets.CanAccessTable(v) then return nil end
    local out = {}
    for k, x in pairs(v) do
        local kk = type(k)
        if Secrets.IsSafeKey(k) and (kk == "string" or kk == "number") then out[k] = plainCopy(x, depth + 1) end
    end
    return out
end
Recorder.PlainCopy = function(v) return plainCopy(v, 0) end

local function round1(v)
    v = Secrets.PlainNumber(v)
    if not v then return nil end
    return math.floor(v * 10 + 0.5) / 10
end

-- The enemies of every session of the fight, summed by creature (else name), highest first.
local function enemiesOf(fight)
    local sessions = type(fight.sessions) == "table" and fight.sessions or {}
    if #sessions <= 1 then return (NS.Meter.ReadEnemies(sessions[1] or fight.sessionID)) end
    local rows, index = {}, {}
    for _, id in ipairs(sessions) do
        for _, e in ipairs((NS.Meter.ReadEnemies(id))) do
            local key = e.creatureID or e.name
            local row = key ~= nil and index[key] or nil
            if row then
                row.total = row.total + e.total
            else
                row = { name = e.name, creatureID = e.creatureID, total = e.total }
                if key ~= nil then index[key] = row end
                rows[#rows + 1] = row
            end
        end
    end
    table.sort(rows, function(a, b) return a.total > b.total end)
    return rows
end

-- The fight's length: the meter's session duration, else its own combat-entry-to-end clock.
local function durationOf(fight, final)
    local d = Secrets.PlainNumber(final.duration)
    if d and d > 0 then return round1(d) end
    local from, to = Secrets.PlainNumber(fight.startT), Secrets.PlainNumber(fight.closedT or fight.combatEndT)
    if from and to and to > from then return round1(to - from) end
    return 0
end

-- The epoch the fight started at: now, less how long ago (GetTime) its combat entry was.
local function startEpoch(fight)
    local now, startT = time(), Secrets.PlainNumber(fight.startT)
    if not startT then return now end
    return math.floor(now - math.max(0, GetTime() - startT))
end

-- The damage by spell, packed (CastCodec.EncodeSpells); a row whose ID or total is unreadable is left
-- out.
local function spellsOf(merged)
    local out = {}
    for _, sp in ipairs(type(merged.spells) == "table" and merged.spells or {}) do
        local id, total = Secrets.PlainNumber(sp.spellID), Secrets.PlainNumber(sp.total)
        if id and total then out[#out + 1] = { spellID = id, total = total, isPet = Secrets.PlainTruth(sp.isPet) } end
    end
    return NS.CastCodec.EncodeSpells(out)
end

--- A record's damage by spell, unpacked: { { spellID, total, isPet } }, highest first.
--- @param record table|nil
--- @return table spells
function Recorder.Spells(record)
    return NS.CastCodec.DecodeSpells(type(record) == "table" and record.spells or nil)
end

-- The casts, packed, and what they were cast with (base cooldowns, the usage).
local function castsOf(fight)
    local casts, cooldowns = NS.Casts.Finish(fight.id)
    local usage = NS.Usage and NS.Usage.ForFight(fight, casts) or nil
    return NS.CastCodec.Encode(casts), cooldowns, usage
end

local function loadoutOf(fight)
    local lo = type(fight.loadout) == "table" and fight.loadout or {}
    local key = lo.talents and NS.Loadouts.Store(plainCopy(lo.talents, 0)) or nil
    return lo.gear, key
end

local function buildOf()
    local _, build = NS.Compat.BuildInfo()
    return Secrets.PlainString(build)
end

--- The record for a fight that ended "final" and passed the filters (`identity` and `duration`
--- already resolved). Takes the fight's casts (Casts.Finish) and stores its talents (Loadouts.Store).
--- @return table record  plain throughout
function Recorder.Build(fight, final, identity, duration)
    local merged = final.merged or {}
    local total = Secrets.PlainNumber(merged.total) or 0
    local casts, cooldowns, usage = castsOf(fight)
    local gear, loadout = loadoutOf(fight)
    local raw = {
        schema = Recorder.CT_SCHEMA, t = startEpoch(fight), duration = duration,
        who = type(fight.snapshot) == "table" and fight.snapshot.who or nil,
        identity = identity, boardKey = NS.Identity.BoardKey(identity),
        damage = { merged = total, player = final.player and final.player.total,
                   pet = final.pet and final.pet.total },
        dps = duration > 0 and round1(total / duration) or 0, meterDps = round1(merged.dps),
        spells = spellsOf(merged), casts = casts, cooldowns = cooldowns, gear = gear,
        stats = NS.Stats.Fill(plainCopy(fight.stats, 0)), loadout = loadout, usage = usage,
        client = NS.Compat.ClientKey(), build = buildOf(), version = NS.version, status = "final",
    }
    local record = plainCopy(raw, 0)
    record.id = newID()
    if type(record.identity) == "table" and record.identity.targetName == nil then
        record.identity.targetName = L["Unknown target"]
    end
    return record
end

-- ── the flow ────────────────────────────────────────────────────────────────────────────────────

local function skip(fight, reason)
    debug("fight %s not stored: %s", tostring(type(fight) == "table" and fight.id), reason)
    if type(fight) == "table" and NS.Casts and NS.Casts.Drop then NS.Casts.Drop(fight.id) end
    NS.SendBus(NS.MSG.FIGHT_SKIPPED, fight, reason)
end

local function hasWho(fight)
    local snap = fight.snapshot
    local who = type(snap) == "table" and snap.who or nil
    return type(who) == "table" and Secrets.PlainString(who.name) ~= nil
end

--- FIGHT_ENDED's receiver: store the fight, or say why not.
function Recorder.OnFightEnded(fight, final, reason)
    if type(fight) ~= "table" then return end
    if reason ~= "final" or type(final) ~= "table" then return skip(fight, "lost") end
    local identity = NS.Identity.Resolve(fight, final, enemiesOf(fight))
    local duration = durationOf(fight, final)
    local ok, why = NS.Filters.Passes(identity, duration)
    if not ok then return skip(fight, why) end
    if not hasWho(fight) then return skip(fight, "unknown") end
    local record = Recorder.Build(fight, final, identity, duration)
    -- The fight remembers its record, so the chart's in-session store (modules/Slices.lua) answers it.
    fight.recordID = record.id
    if Recorder.Save(record) then debug("fight %s stored as %s (%.1f s)", fight.id, record.id, duration) end
end

local receiver = NS.NewBusTarget and NS.NewBusTarget()
if receiver then
    receiver:RegisterMessage(NS.MSG.FIGHT_ENDED, function(_, fight, final, reason)
        Recorder.OnFightEnded(fight, final, reason)
    end)
end
