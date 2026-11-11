local _, NS = ...
-- modules/Bests.lua — personal bests (spec §5, plan Task 2.5): the top DPS for a character x spec x
-- board key, worked out from the stored fights and never stored on its own. Adapted from DPS Race
-- @045f479 (modules/Bests.lua); its race boards came back with Race mode (plan Task A3).
--
-- THE BOARD a fight belongs on is "<character>|<specID>|<boardKey>". The character is the name, the
-- realm and the client key (Bests.CharKey), so boards never mix Retail and WoW Forever and their
-- difficulty IDs never need to be comparable (spec §5). A fight counts only when it is "final", has a
-- DPS, a character and a board key: an Unknown target (no board key, or Identity's `unknown` flag)
-- never counts as a best. A DPS tie goes to the earlier fight (it set the mark first), then the id.
--
-- RACE BOARDS (Race mode spec §5). A race (a record with a `race` part, modules/RaceRecord.lua) is on
-- its RACE board only, never its dummy's fight board, so one pull never holds two bests:
-- "<character>|<specID>|race:<kind>:<length>" (Bests.RaceKey). The kind is the dummy's category read
-- from the list as it is NOW (Dummies.CategoryOf on the record's creature), else the kind stored with
-- the race (ruling X8), so editing the Training dummies list moves stored races between boards. Only a
-- "complete" race counts, ranked by its race DPS (RaceRecord.Dps); DPS Race's two views stay: every
-- complete race, and the CLEAN board (Bests.CleanFor), which leaves out a race with a flag
-- (RaceRecord.Flagged). A fight has no flags, so it is on both views of its board.
--
-- PURE over plain stored records (every value went through NS.Secrets on its way into the record,
-- modules/Recorder.lua), apart from THE CACHE: one board over the whole store, built on first ask and
-- dropped on FIGHT_SAVED and FIGHTS_CHANGED, and on a change to the Training dummies list or the
-- profile (SETTINGS_CHANGED: a race's board is its kind read now); the clean view is cached apart.
-- The receiver is this module's own bus target, so the latch drops and replays it with the rest
-- (slash-commands-§7).

local Bests = {}
NS.Bests = Bests

local cache = {}   -- the cached boards over the store: [false] every record, [true] the clean view

--- The character a fight was fought by: "name|realm|client", or nil without a readable name.
--- @param who table|nil  a record's (or Identity.Snapshot's) `who`
--- @return string|nil
function Bests.CharKey(who)
    if type(who) ~= "table" or type(who.name) ~= "string" then return nil end
    return ("%s|%s|%s"):format(who.name, tostring(who.realm), tostring(who.client))
end

local function boardOf(charKey, specID, boardKey)
    return ("%s|%s|%s"):format(charKey, tostring(specID), boardKey)
end

--- A race's dummy kind as the boards read it: the creature's category on the list now, else the kind
--- stored with the race. nil for a fight, or a race with neither.
--- @param record table|nil
--- @return string|nil kind
function Bests.RaceKind(record)
    if not NS.RaceRecord.IsRace(record) then return nil end
    local ident = type(record.identity) == "table" and record.identity or {}
    local Dummies = NS.Dummies
    local now = Dummies and Dummies.CategoryOf and Dummies.CategoryOf(ident.targetCreatureID) or nil
    if type(now) == "string" then return now end
    local kind = record.race.kind
    return type(kind) == "string" and kind or nil
end

--- The race board a race belongs on: "<character>|<specID>|race:<kind>:<length>" (spec §5:
--- character + spec + dummy kind + length). nil for a fight, or without a character, a kind or a length.
--- @param record table|nil
--- @return string|nil key
function Bests.RaceKey(record)
    local kind = Bests.RaceKind(record)
    if not kind then return nil end
    local length = record.race.length
    if type(length) ~= "number" then return nil end
    local who = type(record.who) == "table" and record.who or nil
    local char = Bests.CharKey(who)
    if not char then return nil end
    return boardOf(char, who.specID, ("race:%s:%s"):format(kind, tostring(length)))
end

--- The board a record belongs on, or nil when it can hold no best (no character, no board key, or an
--- unknown target). A race's is its race board (Bests.RaceKey), never its dummy's.
--- @param record table
--- @return string|nil key
function Bests.Key(record)
    if NS.RaceRecord.IsRace(record) then return Bests.RaceKey(record) end
    if type(record) ~= "table" or type(record.boardKey) ~= "string" then return nil end
    local ident = record.identity
    if type(ident) == "table" and ident.unknown then return nil end
    local who = type(record.who) == "table" and record.who or nil
    local char = Bests.CharKey(who)
    if not char then return nil end
    return boardOf(char, who.specID, record.boardKey)
end

local function dpsOf(record) return NS.RaceRecord.Dps(record) end

-- A record can hold a best: final, with a DPS and a board; a race only when complete.
local function counts(record)
    if type(record) ~= "table" or record.status ~= "final" or dpsOf(record) == nil then return false end
    if NS.RaceRecord.IsRace(record) and record.race.status ~= "complete" then return false end
    return Bests.Key(record) ~= nil
end

local function cleanOnlyOf(opts) return type(opts) == "table" and opts.cleanOnly == true end

-- Counts on the view: every record, or (cleanOnly) every record without a flag.
local function countsOn(record, cleanOnly)
    return counts(record) and not (cleanOnly and NS.RaceRecord.Flagged(record))
end

--- `a` ranks above `b`: higher DPS (a race's race DPS); on a tie the earlier fight, then the id.
local function ranksAbove(a, b)
    local da, db = dpsOf(a), dpsOf(b)
    if da ~= db then return da > db end
    local ta, tb = a.t or 0, b.t or 0
    if ta ~= tb then return ta < tb end
    return tostring(a.id) < tostring(b.id)
end

--- The best record per board.
--- @param records table  an array of records (only the ones that count are ranked)
--- @param skip table|nil  a record to leave out
--- @param opts table|nil  { cleanOnly = true } leaves out every flagged race (the clean board)
--- @return table board  { [key] = record }
function Bests.Compute(records, skip, opts)
    local cleanOnly = cleanOnlyOf(opts)
    local out = {}
    for _, r in ipairs(records or {}) do
        if r ~= skip and countsOn(r, cleanOnly) then
            local key = Bests.Key(r)
            local held = out[key]
            if not held or ranksAbove(r, held) then out[key] = r end
        end
    end
    return out
end

--- The cached board over the whole store.
--- @param opts table|nil  as Compute's (the clean view is cached apart)
--- @return table board  { [key] = record }
function Bests.Board(opts)
    local cleanOnly = cleanOnlyOf(opts)
    local board = cache[cleanOnly]
    if not board then
        board = Bests.Compute(NS.Recorder.List(), nil, { cleanOnly = cleanOnly })
        cache[cleanOnly] = board
    end
    return board
end

--- Drop the cached boards; the next ask rebuilds them from the store.
function Bests.Invalidate()
    cache = {}
end

--- The best on `record`'s board, or nil when it is on none. With `exclude`, `record` itself is left out:
--- the runner-up when it is the best (Compare's "the runner-up if this fight is the best", spec §7).
--- @param record table
--- @param exclude boolean|nil
--- @return table|nil best
function Bests.For(record, exclude)
    local key = Bests.Key(record)
    if not key then return nil end
    if not exclude then return Bests.Board()[key] end
    local best
    for _, r in ipairs(NS.Recorder.List()) do
        if r ~= record and r.id ~= record.id and counts(r) and Bests.Key(r) == key
            and (not best or ranksAbove(r, best)) then
            best = r
        end
    end
    return best
end

--- The best on `record`'s CLEAN board (DPS Race's clean-only view: no race with a flag), or nil when it
--- is on none. A fight is on the clean view of its own board.
--- @param record table
--- @return table|nil best
function Bests.CleanFor(record)
    local key = Bests.Key(record)
    if not key then return nil end
    return Bests.Board({ cleanOnly = true })[key]
end

--- Whether `record` holds the best on its board.
--- @return boolean
function Bests.IsBest(record)
    if not counts(record) then return false end
    local best = Bests.Board()[Bests.Key(record)]
    return best ~= nil and (best == record or best.id == record.id)
end

--- The id of the best fight on a board for a character and a spec (the HUD's pace, plan Task 3.2).
--- @param boardKey string
--- @param character string|table  a Bests.CharKey, or a `who` table
--- @param specID number|nil
--- @return string|nil recordID
function Bests.BestCurve(boardKey, character, specID)
    if type(boardKey) ~= "string" then return nil end
    if type(character) == "table" then character = Bests.CharKey(character) end
    if type(character) ~= "string" then return nil end
    local best = Bests.Board()[boardOf(character, specID, boardKey)]
    return best and best.id or nil
end

--- Every record holding a best, on a fight board, a race board or a race board's clean view: what
--- the purge keeps (modules/Retention.lua).
--- @param records table  an array of records
--- @return table ids  { [id] = true }
function Bests.HoldingIDs(records)
    local ids = {}
    for _, cleanOnly in ipairs({ false, true }) do
        for _, r in pairs(Bests.Compute(records, nil, { cleanOnly = cleanOnly })) do ids[r.id] = true end
    end
    return ids
end

-- The records a question with none given is about: the sample history while one is in place
-- (modules/Results_Source.lua), else the store.
local function history(records)
    if records then return records end
    local Source = NS.ResultsSource
    if Source and Source.IsMock and Source.IsMock() then return Source.All() end
    return NS.Recorder.List()
end

-- `a` was fought before `b`: its combat-entry epoch, then the id.
local function before(a, b)
    local ta, tb = a.t or 0, b.t or 0
    if ta ~= tb then return ta < tb end
    return tostring(a.id) < tostring(b.id)
end

local function isEarlierRival(other, record, key)
    if other == record or other.id == record.id or not counts(other) then return false end
    return before(other, record) and Bests.Key(other) == key
end

--- The best on `record`'s board among the records fought BEFORE it (DPS Race's Before): what Delta
--- compares against. `record` itself need not count.
--- @param record table
--- @param records table|nil  defaults to the store (the sample history while one is in place)
--- @return table|nil prev
function Bests.Before(record, records)
    local key = Bests.Key(record)
    if not key then return nil end
    local prev
    for _, other in ipairs(history(records)) do
        if isEarlierRival(other, record, key) and (not prev or ranksAbove(other, prev)) then prev = other end
    end
    return prev
end

--- `record` against the best on its board BEFORE it (DPS Race's Delta), for a race or a fight.
--- @param record table
--- @param records table|nil  as Before's
--- @return number|nil pct  (dps / previous best's - 1) * 100; nil with no previous best, or one at 0
--- @return boolean isNewBest  it beats the previous best, or is the first that counts on its board
--- @return table|nil prev  the previous best (Bests.Before), nil with none
function Bests.Delta(record, records)
    if not counts(record) then return nil, false, nil end
    local prev = Bests.Before(record, records)
    if not prev then return nil, true, nil end
    local mine, theirs = dpsOf(record), dpsOf(prev)
    if theirs <= 0 then return nil, mine > theirs, prev end
    return (mine / theirs - 1) * 100, mine > theirs, prev
end

-- ── bus ─────────────────────────────────────────────────────────────────────────────────────────

local receiver = NS.NewBusTarget and NS.NewBusTarget()
if receiver then
    receiver:RegisterMessage(NS.MSG.FIGHT_SAVED, function() Bests.Invalidate() end)
    receiver:RegisterMessage(NS.MSG.FIGHTS_CHANGED, function() Bests.Invalidate() end)
    -- A race's board is its kind read from the Training dummies list now, the profile's.
    receiver:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path)
        local Dummies = NS.Dummies
        if path == "profile" or (Dummies and path == Dummies.PATH) then Bests.Invalidate() end
    end)
end
