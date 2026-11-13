local _, NS = ...
-- modules/RaceScoring.lua — a race's scoring rules (Race mode, plan Task B1): the late-cast test with its
-- grace, the race DPS, the quiet the Race window waits before it says "waiting", and a race's flags in
-- display order. Ported from DPS Race @f8078c7 (modules/Scoring.lua) onto the race part
-- (modules/RaceRecord.lua's shape): DPS Race read `run.status`, `run.result.endedAt` and `run.flags`;
-- here every function reads the part, `race.status`, `race.endedAt` and `race.flags`.
--
-- PURE but for one seam. No WoW API and no meter value: every input is a plain number already on the
-- part (the score comes from the fight's read after combat, modules/Race.lua Finalize). NS.L is read at
-- CALL time for the flag text, and so is the late-cast ignore list (modules/LateIgnore.lua Set) when a
-- caller hands no `set`: a race keeps every late cast it recorded, and which of them count is decided
-- here, each time, so a change to the list re-scores every saved race.
-- Flags inform, never void: only `incomplete` keeps a race off its board (modules/Bests.lua reads the
-- status for that, not this list).

local RaceScoring = {}
NS.RaceScoring = RaceScoring

--- Seconds of no damage update after the buzzer before the Race window's Stop! screen becomes the
--- waiting one (DPS Race's quiet before its read; the read itself is the fight's, on Combat Trail's
--- settle, ruling X5).
RaceScoring.QUIET_BEFORE_READ = 2.5

--- True when a cast that started `startOffset` seconds after the buzzer is late under `grace`.
--- Strictly later than the grace: a cast at exactly buzzer + grace is on time, and a cast that started
--- before the buzzer (a negative offset) is never late. An instant is scored by its success offset.
function RaceScoring.IsLateCast(startOffset, grace)
    if type(startOffset) ~= "number" or type(grace) ~= "number" then return false end
    return startOffset > grace
end

--- The race DPS: `score` over the race length when complete, else over `endedAt` (seconds from the
--- first hit until combat ended). 0 with no score or no positive divisor yet. RaceRecord.ScoreDps.
--- @param score number|nil
--- @param race table|nil  a race part
--- @return number
function RaceScoring.Dps(score, race)
    return NS.RaceRecord.ScoreDps(score, race)
end

-- One late cast as "+1.4s" or, when the resolver names its spell, "+1.4s Incinerate".
local function lateEntry(cast, nameOf)
    local L = NS.L
    local name
    if nameOf and cast.spellID then
        local ok, got = pcall(nameOf, cast.spellID)
        if ok and type(got) == "string" and got ~= "" then name = got end
    end
    if name then return L["+%.1fs %s"]:format(cast.t or 0, name) end
    return L["+%.1fs"]:format(cast.t or 0)
end

-- The ignore list in force: the caller's, else the stored one (an empty set before LateIgnore loads).
local function ignoreSet(set)
    if type(set) == "table" then return set end
    local LI = NS.LateIgnore
    return LI and LI.Set() or {}
end

--- A race's late casts split by the ignore list: the counted ones (they flag the race) and the
--- ignored ones, each in the recorded order. A cast with no spell ID (sealed) is always counted.
--- @param race table|nil  a race part
--- @param set table|nil  { [spellID] = true }; NS.LateIgnore.Set() when nil
--- @return table counted
--- @return table ignored
function RaceScoring.SplitLate(race, set)
    local counted, ignored = {}, {}
    local flags = type(race) == "table" and race.flags
    local list = type(flags) == "table" and flags.lateCasts
    if type(list) ~= "table" then return counted, ignored end
    set = ignoreSet(set)
    for _, cast in ipairs(list) do
        local id = type(cast) == "table" and cast.spellID
        if type(id) == "number" and set[id] then
            ignored[#ignored + 1] = cast
        else
            counted[#counted + 1] = cast
        end
    end
    return counted, ignored
end

--- The ignored late casts as one line, "Ignored: +20.6s Feign Death, +3.0s Vanish", or nil when the
--- ignore list leaves none. Every flags tooltip draws it dimmed, so they word it the same way.
--- @param set table|nil  as SplitLate's
--- @return string|nil
function RaceScoring.IgnoredText(race, nameOf, set)
    local _, ignored = RaceScoring.SplitLate(race, set)
    if #ignored == 0 then return nil end
    local parts = {}
    for i, cast in ipairs(ignored) do parts[i] = lateEntry(cast, nameOf) end
    return NS.L["Ignored: %s"]:format(table.concat(parts, ", "))
end

-- The late casts' flag: its text, then its count line and its offsets apart (the Results detail's
-- flags box draws those two as separate lines). `list` is the counted casts.
local function lateCastsText(list, nameOf)
    local L, parts = NS.L, {}
    for i, cast in ipairs(list) do parts[i] = lateEntry(cast, nameOf) end
    local joined = table.concat(parts, ", ")
    if #list == 1 then return L["1 late cast (%s)"]:format(joined), L["1 late cast"], joined end
    return L["%d late casts (%s)"]:format(#list, joined), L["%d late casts"]:format(#list), joined
end

-- The lateCasts flag over the counted casts, or nil when none counts (the ignore list's never do).
local function lateFlag(race, nameOf, set)
    local counted, ignored = RaceScoring.SplitLate(race, set)
    if #counted == 0 then return nil end
    local text, main, sub = lateCastsText(counted, nameOf)
    return { key = "lateCasts", text = text, main = main, sub = sub,
             count = #counted, casts = counted, ignored = ignored }
end

-- The flags after the late casts, in display order: { key, the flag's field, its text }.
local FLAG_ORDER = {
    { "reloaded", "Reloaded mid-race: casts after the buzzer not tracked" },
    { "sessionFromList", "Session matched by list" },
    { "sharedSession", "Shared session: the pull carried on a meter session from before the arm" },
    { "died", "Died during the race" },
}

--- The race's flags as an array of { key, text, main?, sub? } (main and sub: the late casts' count
--- line and their offsets, the text split in two), in the order: lateCasts, restarted, reloaded,
--- sessionFromList (the fight bound its session only on a tick's look at the meter's list, ruling
--- X14), sharedSession (the pull carried on a session from before the arm, ruling X3), died,
--- incomplete, lost. `nameOf(spellID) -> name|nil` is optional: the caller (the UI) resolves spell names
--- through C_Spell, so this file stays pure; without it a late cast shows its offset only. The
--- lateCasts flag is there only when a late cast is counted (SplitLate under `set`), and also carries
--- `count`, `casts` (the counted ones) and `ignored` (the rest). This is the one judge of flagged and
--- clean the race window and the Results draw from.
--- @param race table|nil  a race part
--- @param set table|nil  the ignore list as a set; NS.LateIgnore.Set() when nil
function RaceScoring.Flags(race, nameOf, set)
    local L, out = NS.L, {}
    local flags = (type(race) == "table" and type(race.flags) == "table") and race.flags or {}
    local late = lateFlag(race, nameOf, set)
    if late then out[#out + 1] = late end
    if type(flags.restartedAt) == "number" then
        out[#out + 1] = { key = "restarted", text = L["Damage restarted at +%.1fs"]:format(flags.restartedAt) }
    end
    for _, entry in ipairs(FLAG_ORDER) do
        if flags[entry[1]] then out[#out + 1] = { key = entry[1], text = L[entry[2]] } end
    end
    local status = type(race) == "table" and race.status or nil
    if status == "incomplete" then
        out[#out + 1] = { key = "incomplete", text = L["Incomplete: combat ended before the buzzer"] }
    elseif status == "lost" then
        out[#out + 1] = { key = "lost", text = L["Lost: the fight could not be read"] }
    end
    return out
end
