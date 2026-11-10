local _, NS = ...
-- modules/Bests.lua — personal bests (spec §5, plan Task 2.5): the top DPS for a character x spec x
-- board key, worked out from the stored fights and never stored on its own. Adapted from DPS Race
-- @045f479 (modules/Bests.lua) without its race: no race length, no dummy-type category, no
-- clean-only board (late-cast flags are gone with the race).
--
-- THE BOARD a fight belongs on is "<character>|<specID>|<boardKey>". The character is the name, the
-- realm and the client key (Bests.CharKey), so boards never mix Retail and WoW Forever and their
-- difficulty IDs never need to be comparable (spec §5). A fight counts only when it is "final", has a
-- DPS, a character and a board key: an Unknown target (no board key, or Identity's `unknown` flag)
-- never counts as a best. A DPS tie goes to the earlier fight (it set the mark first), then the id.
--
-- PURE over plain stored records (every value went through NS.Secrets on its way into the record,
-- modules/Recorder.lua), apart from THE CACHE: one board over the whole store, built on first ask and
-- dropped on FIGHT_SAVED and FIGHTS_CHANGED. The receiver is this module's own bus target, so the
-- latch drops and replays it with the rest (slash-commands-§7).

local Bests = {}
NS.Bests = Bests

local board        -- the cached board over the store, or nil

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

--- The board a record belongs on, or nil when it can hold no best (no character, no board key, or an
--- unknown target).
--- @param record table
--- @return string|nil key
function Bests.Key(record)
    if type(record) ~= "table" or type(record.boardKey) ~= "string" then return nil end
    local ident = record.identity
    if type(ident) == "table" and ident.unknown then return nil end
    local who = type(record.who) == "table" and record.who or nil
    local char = Bests.CharKey(who)
    if not char then return nil end
    return boardOf(char, who.specID, record.boardKey)
end

local function counts(record)
    return type(record) == "table" and record.status == "final" and type(record.dps) == "number"
        and Bests.Key(record) ~= nil
end

--- `a` ranks above `b`: higher DPS; on a tie the earlier fight, then the id.
local function ranksAbove(a, b)
    if a.dps ~= b.dps then return a.dps > b.dps end
    local ta, tb = a.t or 0, b.t or 0
    if ta ~= tb then return ta < tb end
    return tostring(a.id) < tostring(b.id)
end

--- The best record per board.
--- @param records table  an array of records (only the ones that count are ranked)
--- @param skip table|nil  a record to leave out
--- @return table board  { [key] = record }
function Bests.Compute(records, skip)
    local out = {}
    for _, r in ipairs(records or {}) do
        if r ~= skip and counts(r) then
            local key = Bests.Key(r)
            local held = out[key]
            if not held or ranksAbove(r, held) then out[key] = r end
        end
    end
    return out
end

--- The cached board over the whole store.
--- @return table board  { [key] = record }
function Bests.Board()
    if not board then board = Bests.Compute(NS.Recorder.List()) end
    return board
end

--- Drop the cached board; the next ask rebuilds it from the store.
function Bests.Invalidate()
    board = nil
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

--- Every record holding a best: what the purge keeps (modules/Retention.lua).
--- @param records table  an array of records
--- @return table ids  { [id] = true }
function Bests.HoldingIDs(records)
    local ids = {}
    for _, r in pairs(Bests.Compute(records)) do ids[r.id] = true end
    return ids
end

-- ── bus ─────────────────────────────────────────────────────────────────────────────────────────

local receiver = NS.NewBusTarget and NS.NewBusTarget()
if receiver then
    receiver:RegisterMessage(NS.MSG.FIGHT_SAVED, function() Bests.Invalidate() end)
    receiver:RegisterMessage(NS.MSG.FIGHTS_CHANGED, function() Bests.Invalidate() end)
end
