local _, NS = ...
-- modules/Results_Source.lua — where the Results window reads its fights (spec §7): the store, or,
-- while test mode or the sim is on (plan Task 5.1), an in-memory sample history that is never written
-- anywhere. Adapted from DPS Race @045f479 (modules/Results_Source.lua); the sample's boards hold its
-- races on their race boards (modules/Bests.lua Key), all races and the clean view apart, and are
-- dropped on a late-cast ignore list or Training dummies edit (Source.Invalidate, Race mode plan D1).
--
-- ONE SEAM. Every Results file asks this module, never NS.Recorder or NS.Bests, for the fights it
-- lists, a fight by id, whether a fight holds its best, and to store a note or delete a fight. With
-- no sample history in place each answer is the store's own (the same function, called at call
-- time, so a suite's stub on NS.Recorder still reaches the window). With one in place (Source.Use)
-- the answers come from it, and a note or a delete changes it in memory only. A sample fight's chart
-- is a record in NS.Slices like a recorded one's (seeded here, in memory), so the chart draws by one
-- path (plan Task 4.2).
--
-- THE SAMPLE HISTORY is a plain table: `fights` (an array of records in the store's shape, any
-- order) and `slices` ({ [fight id] = Slices.Seed's record }: plain numbers). It never reaches
-- SavedVariables: nothing here writes NS.db, and the window's own writers (Save view) refuse while
-- it is shown (modules/Results_Fights.lua).

local Source = {}
NS.ResultsSource = Source

local mock        -- the sample history in place, or nil
local board       -- the sample's bests board, dropped on a change
local clean       -- the sample's clean view of it (no flagged race)

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Results", fmt, ...) end
end

-- Newest first; a time tie breaks on the id, as the store's order does.
local function newerFirst(a, b)
    local ta, tb = a.t or 0, b.t or 0
    if ta ~= tb then return ta > tb end
    return tostring(a.id) > tostring(b.id)
end

-- The shell redraws on every change of source or sample (modules/Results.lua); a change to the sample
-- history in place reaches the Race window's sample card too (a deleted sample race's card goes).
local function changed(swapped)
    board, clean = nil, nil
    local R = NS.Results
    if R and type(R.OnSourceChanged) == "function" then R.OnSourceChanged(swapped) end
    local RW = NS.RaceWindow
    if not swapped and RW and RW.SampleChanged then RW.SampleChanged() end
end

local function forgetCharts(dataset)
    for id in pairs(dataset.slices) do NS.Slices.Forget(id) end
end

--- Whether the window reads the sample history now.
function Source.IsMock()
    return mock ~= nil
end

--- Read `dataset` instead of the store until Restore; nil restores the store. A second Use replaces
--- the first.
--- @param dataset table|nil  { fights, slices }
--- @return boolean changed
function Source.Use(dataset)
    if dataset == nil then return Source.Restore() end
    if type(dataset) ~= "table" then return false end
    dataset.fights = type(dataset.fights) == "table" and dataset.fights or {}
    dataset.slices = type(dataset.slices) == "table" and dataset.slices or {}
    if mock then forgetCharts(mock) end
    mock = dataset
    for id, rec in pairs(dataset.slices) do NS.Slices.Seed(id, rec) end
    debug("source: sample history (%d fights)", #dataset.fights)
    changed(true)
    return true
end

--- Back to the store. Answers whether a sample history was in place.
function Source.Restore()
    if not mock then return false end
    forgetCharts(mock)
    mock = nil
    debug("source: the store")
    changed(true)
    return true
end

--- Put `record` in the sample history in place, replacing a fight of its id (the sim's fight joins
--- it as a real one joins the store, plan Task 5.1).
--- @return boolean added
function Source.Put(record)
    if not mock or type(record) ~= "table" then return false end
    for i, other in ipairs(mock.fights) do
        if other.id == record.id then
            mock.fights[i] = record
            changed(false)
            return true
        end
    end
    mock.fights[#mock.fights + 1] = record
    changed(false)
    return true
end

--- Every fight the window lists, newest first (a fresh array).
function Source.All()
    if not mock then return NS.Recorder.List() end
    local out = {}
    for i, record in ipairs(mock.fights) do out[i] = record end
    table.sort(out, newerFirst)
    return out
end

--- The fight with this id, or nil.
function Source.Get(id)
    if not mock then return NS.Recorder.Get(id) end
    if id == nil then return nil end
    for _, record in ipairs(mock.fights) do
        if record.id == id then return record end
    end
    return nil
end

--- Whether `record` holds the best on its board (character x spec x board key, modules/Bests.lua),
--- among the store's fights or the sample's.
--- @return boolean
function Source.IsBest(record)
    if not mock then return NS.Bests.IsBest(record) end
    local key = NS.Bests.Key(record)
    if not key then return false end
    board = board or NS.Bests.Compute(mock.fights)
    local held = board[key]
    return held ~= nil and held.id == record.id
end

--- The best on `record`'s board (modules/Bests.lua For), among the store's fights or the sample's.
--- With `exclude`, `record` itself is left out: the best before it, or the runner-up.
--- @return table|nil best
function Source.BestFor(record, exclude)
    if not mock then return NS.Bests.For(record, exclude) end
    local key = NS.Bests.Key(record)
    if not key then return nil end
    if not exclude then
        board = board or NS.Bests.Compute(mock.fights)
        return board[key]
    end
    local others = {}
    for _, r in ipairs(mock.fights) do
        if r ~= record and r.id ~= record.id then others[#others + 1] = r end
    end
    return NS.Bests.Compute(others)[key]
end

--- The best on `record`'s CLEAN board (no race with a flag: modules/Bests.lua CleanFor), among the
--- store's fights or the sample's.
--- @return table|nil best
function Source.CleanFor(record)
    if not mock then return NS.Bests.CleanFor(record) end
    local key = NS.Bests.Key(record)
    if not key then return nil end
    clean = clean or NS.Bests.Compute(mock.fights, nil, { cleanOnly = true })
    return clean[key]
end

--- Drop the sample's boards (a race's flags and kind are read now: the late-cast ignore list or the
--- Training dummies list changed); the store's are Bests' own, dropped on the same edit.
function Source.Invalidate()
    board, clean = nil, nil
end

--- Store a note. The sample's note lives in memory.
--- @return boolean stored
function Source.SetNote(id, note)
    if not mock then return NS.Recorder.SetNote(id, note) end
    local record = Source.Get(id)
    if not record then return false end
    note = NS.Recorder.ClampNote(note)
    record.note = note ~= "" and note or nil
    changed(false)
    return true
end

--- A sample fight changed in place (its usage edit, modules/Usage.lua): the window redraws, nothing is
--- written. Nothing with no sample history in place.
--- @return boolean announced
function Source.Touched()
    if not mock then return false end
    changed(false)
    return true
end

--- Delete a fight. A sample fight leaves the sample history only.
--- @return boolean removed
function Source.Delete(id)
    if not mock then return NS.Recorder.Delete(id) end
    for i, record in ipairs(mock.fights) do
        if record.id == id then
            table.remove(mock.fights, i)
            mock.slices[id] = nil
            NS.Slices.Forget(id)
            changed(false)
            return true
        end
    end
    return false
end
