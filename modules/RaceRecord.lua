local _, NS = ...
-- modules/RaceRecord.lua — the fight record's `race` part (Race mode spec §6, plan Task A3): a race is
-- one fight record that carries this part, DPS Race's run fields with no fight equivalent. The record's
-- own fields (who, identity, damage, dps, duration, ...) stay a fight's; the part adds:
--
--   race = { length, kind, status, flags = { lateCasts, restartedAt, reloaded, died, sessionFromList,
--            sharedSession, carriedOn }, score, dps, tail, endedAt, combatEnd, grace, restartGap, firstHit }
--
-- `length` is the race length the player picked (seconds); `kind` the dummy's category when the race
-- was saved (modules/Dummies.lua CATEGORIES; the boards read the list as it is now, modules/Bests.lua
-- RaceKind); `status` "complete" or "incomplete" on a stored record (a lost or canceled race is taken
-- off its fight before the save, modules/Recorder.lua); `score` the session's total (player and pet);
-- `dps` the score over the length, or over `endedAt` (seconds from the first hit to combat end) when
-- incomplete, unless `flags.carriedOn` (combat came back inside Combat Trail's grace after the early
-- end, ruling X16): then over the first hit to the fight's end, as the score is the whole fight's; `tail`, `combatEnd`, `grace` and `restartGap` DPS Race's timing. `flags.lateCasts` is
-- `{ { t, spellID }, ... }`, each cast's offset after the buzzer. `firstHit` is the race clock's zero on
-- the fight clock (ruling X9): seconds from combat entry (the fight's startT, the zero of the casts and
-- of the chart's steps) to the first hit. A race saved without it reads as 0: no shift.
--
-- PURE over plain values: no WoW API. Plain copies only plain values: a sealed field, a sealed flag or
-- a late cast's sealed spell is left out, never kept (spec §10, docs/midnight-quirks.md).

local RaceRecord = {}
NS.RaceRecord = RaceRecord

local Secrets = NS.Secrets

-- The part's fields by the type each must have to be kept.
local NUMBERS = { "length", "score", "dps", "tail", "endedAt", "combatEnd", "grace", "restartGap", "firstHit" }
local STRINGS = { "kind", "status" }
local FLAG_TRUTHS = { "reloaded", "died", "sessionFromList", "sharedSession" }
-- The truths a plain copy keeps: the flags, and carriedOn (how an incomplete race's DPS was taken; it
-- flags nothing, as an incomplete race is flagged already).
local KEPT_TRUTHS = { "reloaded", "died", "sessionFromList", "sharedSession", "carriedOn" }

--- Whether `record` is a race: it carries a `race` part.
--- @param record table|nil
--- @return boolean
function RaceRecord.IsRace(record)
    return type(record) == "table" and type(record.race) == "table"
end

--- The race clock's zero on the fight clock (ruling X9): a race's `firstHit`, seconds from combat entry
--- to the first hit. 0, no shift, for a fight, and for a race saved without it or with one not past 0.
--- @param record table|nil
--- @return number seconds
function RaceRecord.FirstHit(record)
    local v = RaceRecord.IsRace(record) and record.race.firstHit or nil
    if type(v) ~= "number" or v <= 0 then return 0 end
    return v
end

--- `casts` ({ { t, ... }, ... }, timed from combat entry) moved onto a clock whose zero is `shift`
--- seconds in: a copy of each cast, `t` less the shift (to the hundredth), every other field kept. A
--- cast before the new zero goes negative. No shift (0 or none) answers the list itself.
--- @param casts table
--- @param shift number|nil
--- @return table casts
function RaceRecord.OnClock(casts, shift)
    if type(shift) ~= "number" or shift == 0 or type(casts) ~= "table" then return casts end
    local out = {}
    for i, c in ipairs(casts) do
        local copy = {}
        for k, v in pairs(c) do copy[k] = v end
        if type(c.t) == "number" then copy.t = math.floor((c.t - shift) * 100 + 0.5) / 100 end
        out[i] = copy
    end
    return out
end

--- The race DPS out of a score (DPS Race's Scoring.Dps on the race part): the score over the race
--- length when complete, else over `endedAt`. 0 with no score or no positive divisor yet. A carried-on
--- incomplete race (`flags.carriedOn`) has its stored `dps`, which RaceRecord.Dps prefers.
--- @param score number|nil
--- @param race table|nil  a race part
--- @return number dps
function RaceRecord.ScoreDps(score, race)
    if type(score) ~= "number" or type(race) ~= "table" then return 0 end
    local secs
    if race.status == "complete" then secs = race.length else secs = race.endedAt end
    if type(secs) ~= "number" or secs <= 0 then return 0 end
    return score / secs
end

--- The one DPS a record is shown, sorted and ranked by (spec §7): the race DPS for a race (its stored
--- `dps`, else worked out from its score), else the fight's DPS. nil when it has none.
--- @param record table|nil
--- @return number|nil dps
function RaceRecord.Dps(record)
    if type(record) ~= "table" then return nil end
    local race = record.race
    if type(race) ~= "table" then
        return type(record.dps) == "number" and record.dps or nil
    end
    if type(race.dps) == "number" then return race.dps end
    if type(race.score) ~= "number" then return nil end
    return RaceRecord.ScoreDps(race.score, race)
end

-- The late casts' list counted against the ignore list (the race engine's, plan Task B1, once it is
-- loaded: NS.LateIgnore.Set()); a cast with no readable spell is always counted.
local function lateCount(list)
    if type(list) ~= "table" then return 0 end
    local LI = NS.LateIgnore
    local set = LI and type(LI.Set) == "function" and LI.Set() or {}
    local n = 0
    for _, cast in ipairs(list) do
        local id = type(cast) == "table" and cast.spellID or nil
        if not (type(id) == "number" and set[id]) then n = n + 1 end
    end
    return n
end

--- Whether a race carries a flag (DPS Race's Scoring.Flags is not empty): a counted late cast, a
--- restart, a reload, a session matched by list, a shared session, a death, or incomplete. Flags inform
--- and never void a race: a flagged complete race still holds its all-races board, and only the clean
--- board leaves it out (modules/Bests.lua). A fight is never flagged.
--- @param record table|nil
--- @return boolean
function RaceRecord.Flagged(record)
    if not RaceRecord.IsRace(record) then return false end
    local race = record.race
    if race.status ~= "complete" then return true end
    local flags = type(race.flags) == "table" and race.flags or {}
    if lateCount(flags.lateCasts) > 0 or type(flags.restartedAt) == "number" then return true end
    for _, key in ipairs(FLAG_TRUTHS) do
        if flags[key] == true then return true end
    end
    return false
end

-- One late cast's plain copy: its offset and its spell, each only when plain.
local function plainCast(cast)
    if Secrets.IsSealed(cast) or type(cast) ~= "table" or not Secrets.CanAccessTable(cast) then return nil end
    return { t = Secrets.PlainNumber(cast.t), spellID = Secrets.PlainNumber(cast.spellID) }
end

local function plainFlags(flags)
    if Secrets.IsSealed(flags) or type(flags) ~= "table" or not Secrets.CanAccessTable(flags) then return {} end
    local out = { restartedAt = Secrets.PlainNumber(flags.restartedAt) }
    for _, key in ipairs(KEPT_TRUTHS) do
        local v = flags[key]
        if not Secrets.IsSealed(v) and type(v) == "boolean" then out[key] = v end
    end
    local list = flags.lateCasts
    if not Secrets.IsSealed(list) and type(list) == "table" and Secrets.CanAccessTable(list) then
        out.lateCasts = {}
        for _, cast in ipairs(list) do out.lateCasts[#out.lateCasts + 1] = plainCast(cast) end
    end
    return out
end

--- A race part's plain copy, for the record (modules/Recorder.lua Build): the spec §6 fields only,
--- each kept only when it is plain and of its type. nil for anything but an accessible table.
--- @param race any
--- @return table|nil part
function RaceRecord.Plain(race)
    if Secrets.IsSealed(race) or type(race) ~= "table" or not Secrets.CanAccessTable(race) then return nil end
    local out = {}
    for _, key in ipairs(NUMBERS) do out[key] = Secrets.PlainNumber(race[key]) end
    for _, key in ipairs(STRINGS) do out[key] = Secrets.PlainString(race[key]) end
    out.flags = plainFlags(race.flags)
    return out
end
