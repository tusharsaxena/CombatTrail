local _, NS = ...
-- modules/MockRaces.lua — Race mode's sample races (race plan Task E1): DPS Race's sample run history
-- (@f8078c7 modules/MockRuns.lua HISTORY) as Combat Trail race records beside the sample fights
-- (modules/MockFights.lua Dataset), and the sample race test mode holds and the sim plays. Each is a
-- sample fight on a training dummy (MockFights.Record, the same seeded plan) that carries the race part
-- (modules/RaceRecord.lua's shape): its length, its dummy kind, its status and flags, its score and DPS,
-- its tail, its combat end and the race clock's zero (`firstHit`).
--
-- MADE FRESH, KEPT IN MEMORY, NEVER STORED, as every sample (MockFights' header): nothing here writes
-- NS.db; the Results window reads the races through modules/Results_Source.lua's sample seam.
--
-- WHAT DIFFERS FROM DPS RACE'S. The characters are Combat Trail's two sample hunters (DPS Race's other
-- classes' rows go to the second hunter: the rotation is the client's one hunter, modules/MockRotations.lua);
-- the lost run has no row (a lost race is not a race, spec §3.4); the format-2 run is a race like the
-- others. The plan is timed from combat entry, the first hit MockFights.FIRST_HIT in, so a race's
-- `firstHit` is that offset and its late casts sit at FIRST_HIT + length + t on the fight's clock.
--
-- RETAIL ONLY (clients-§4): races are Retail's, so on WoW Forever this file returns at once, NS.MockRaces
-- is nil and the sample history holds no race.

if not NS.Compat.ForClient({ "retail" }) then return end

local MockRaces = {}
NS.MockRaces = MockRaces

local L = NS.L
local HOUR = 3600

-- The sample race test mode holds, and the sim's: its length, and the tail and combat end (seconds
-- after the buzzer) a scenario that names none takes.
MockRaces.LENGTH = 30
MockRaces.TAIL = 3.1
MockRaces.COMBAT_END = 4.2
-- The DPS a race races at on a board with no history (the first race on its board).
MockRaces.DPS = 147600
-- A late cast with no spell of its own is the rotation's Cobra Shot.
MockRaces.LATE_SPELL = 193455

-- The catalog's dummy per kind (defaults/Dummies.lua, all in Silvermoon City).
MockRaces.TARGETS = { single = 243207, cleave = 243208, dungeoneer = 243167, boss = 243205, pvp = 243211 }

-- The history (DPS Race's, lost run left out): { who, kind, len, dps, ago (hours), tail, combatEnd
-- (seconds after the buzzer), status? ("incomplete", with endAt), died?, late? ({ { t, spellID? } },
-- seconds after the buzzer), restartedAt?, shared?, chart?, note?, noMajor?, dry? }. Every kind, all
-- five preset lengths, both statuses and every flag; a Hearthstone cast late (8690), which the
-- late-cast ignore list's defaults leave uncounted.
local HISTORY = {
    { who = "me", kind = "single", len = 30, dps = 151200, ago = 26, tail = 3.1, combatEnd = 4.2, chart = true,
      note = "Sample note: opener with every cooldown" },
    { who = "me", kind = "single", len = 30, dps = 144900, ago = 5, tail = 2.4, combatEnd = 5.8 },
    { who = "me", kind = "single", len = 30, dps = 149800, ago = 8, tail = 6.3, combatEnd = 7.1, noMajor = true,
      late = { { t = 1.6 }, { t = 2.3 } } },
    { who = "me", kind = "single", len = 60, dps = 139400, ago = 30, tail = 1.2, combatEnd = 3.4, chart = true },
    { who = "me", kind = "cleave", len = 120, dps = 212300, ago = 50, tail = 11.6, combatEnd = 12.9, dry = true,
      note = "Sample note: five dummies in reach" },
    { who = "me", kind = "boss", len = 180, dps = 128700, ago = 72, status = "incomplete", endAt = 95 },
    { who = "me", kind = "dungeoneer", len = 300, dps = 135100, ago = 96, tail = 7.4, combatEnd = 8.2, chart = true },
    { who = "me", kind = "single", len = 60, dps = 120500, ago = 3, status = "incomplete", endAt = 41, died = true },
    { who = "me", kind = "pvp", len = 120, dps = 118200, ago = 120, restartedAt = 47.5, tail = 49.2, combatEnd = 51.0 },
    { who = "alt", kind = "single", len = 30, dps = 163400, ago = 12, tail = 4.6, combatEnd = 6.2,
      note = "Sample note: another character's best" },
    { who = "alt", kind = "cleave", len = 120, dps = 198600, ago = 60, tail = 16.8, combatEnd = 18.1 },
    { who = "alt", kind = "boss", len = 180, dps = 141000, ago = 84, tail = 2.9, combatEnd = 4.4, shared = true, dry = true },
    { who = "alt", kind = "single", len = 60, dps = 146100, ago = 20, tail = 8.7, combatEnd = 9.6, chart = true },
    { who = "alt", kind = "dungeoneer", len = 300, dps = 127300, ago = 110, status = "incomplete", endAt = 212 },
    { who = "alt", kind = "single", len = 30, dps = 155800, ago = 40, tail = 5.2, combatEnd = 5.9, noMajor = true },
    { who = "me", kind = "cleave", len = 120, dps = 205100, ago = 74, tail = 3.8, combatEnd = 6.5,
      late = { { t = 2.1, spellID = 8690 } } },
}
MockRaces.HISTORY = HISTORY

local function round2(v) return math.floor(v * 100 + 0.5) / 100 end

--- The dummy a race of `kind` is fought on, as a fight carries it ({ where, target }).
--- @param kind string
--- @return table board
function MockRaces.Board(kind)
    local id = MockRaces.TARGETS[kind] or MockRaces.TARGETS.single
    local seed = NS.Dummies.BuiltIn(id) or {}
    return { where = { instanceType = "none", instanceName = "Silvermoon City", difficultyID = 0 },
             target = { name = seed.name or L["Training Dummy"], creatureID = id } }
end

-- The race's span on its own clock: to combat end before the buzzer, else to the end of its tail.
local function spanOf(o)
    if o.status == "incomplete" then return o.endAt end
    return o.len + (o.tail or MockRaces.TAIL)
end

-- The race's late casts, on the fight's clock, added to the plan (their offsets after the buzzer).
local function addLate(plan, o)
    local out = {}
    for i, c in ipairs(o.late or {}) do
        local spellID = c.spellID or MockRaces.LATE_SPELL
        plan.casts[#plan.casts + 1] = { t = round2(NS.MockFights.FIRST_HIT + o.len + c.t), spellID = spellID,
                                        unit = "player", interrupted = false }
        out[i] = { t = c.t, spellID = spellID }
    end
    table.sort(plan.casts, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.spellID < b.spellID
    end)
    return #out > 0 and out or nil
end

--- A sample race's plan: what was cast and every hit, `dps` on the race clock over its length (or to
--- its early end), the tail past the buzzer, the late casts after it.
--- @param o table  { id, kind, len, dps, status?, endAt?, tail?, late?, noMajor?, dry? }
--- @return table plan, table|nil lateCasts
function MockRaces.Plan(o)
    local secs = o.status == "incomplete" and o.endAt or o.len
    local plan = NS.MockFights.Plan({ id = o.id, length = NS.MockFights.FIRST_HIT + spanOf(o),
                                      damage = o.dps * secs, noMajor = o.noMajor, dry = o.dry })
    return plan, addLate(plan, o)
end

-- The race part a sample race leaves (RaceRecord's shape), its score the plan's whole damage.
local function partOf(o, score, lateCasts)
    local defaults = NS.defaults.profile.race
    local incomplete = o.status == "incomplete"
    local race = {
        length = o.len, kind = o.kind, status = incomplete and "incomplete" or "complete", score = score,
        endedAt = incomplete and o.endAt or nil, grace = defaults.grace, restartGap = defaults.restartGap,
        firstHit = NS.MockFights.FIRST_HIT, sample = true,
        flags = { lateCasts = lateCasts, restartedAt = o.restartedAt, died = o.died or nil,
                  sharedSession = o.shared or nil },
    }
    if not incomplete then
        race.tail = o.tail or MockRaces.TAIL
        race.combatEnd = o.combatEnd or MockRaces.COMBAT_END
    end
    race.dps = NS.RaceRecord.ScoreDps(score, race)
    return race
end

--- A sample race's record in the stored shape (never stored), and its plan.
--- @param o table  { id, t, who (a record's who), kind, len, dps, ... } (HISTORY's fields)
--- @param plan table|nil  MockRaces.Plan's; made here when nil
--- @return table record, table plan
function MockRaces.Record(o, plan)
    local lateCasts
    if not plan then plan, lateCasts = MockRaces.Plan(o) end
    if lateCasts == nil and o.late then
        lateCasts = {}
        for i, c in ipairs(o.late) do lateCasts[i] = { t = c.t, spellID = c.spellID or MockRaces.LATE_SPELL } end
    end
    local record = NS.MockFights.Record({ id = o.id, t = o.t, who = o.who, board = MockRaces.Board(o.kind),
                                          length = plan.length, note = o.note }, plan)
    record.race = partOf(o, record.damage.merged, lateCasts)
    return record, plan
end

--- Add the sample races to `data` (MockFights.Dataset's { fights, slices }), `now` the epoch they are
--- dated back from.
function MockRaces.AddTo(data, now)
    now = now or time()
    for i, h in ipairs(HISTORY) do
        local o = {}
        for k, v in pairs(h) do o[k] = v end
        o.id = ("sample-race-%02d"):format(i)
        o.t = math.floor(now - h.ago * HOUR)
        o.who = NS.MockFights.Character(h.who)
        o.note = h.note and L[h.note] or nil
        local record, plan = MockRaces.Record(o)
        data.fights[#data.fights + 1] = record
        if h.chart then data.slices[record.id] = NS.MockFights.Slices(plan) end
    end
end

--- The best the main hunter holds on the race board of `kind` and `length` in `data`, or nil.
--- @return table|nil best
function MockRaces.BoardBest(kind, length, data)
    local probe = { who = NS.MockFights.Character("me"), status = "final",
                    identity = { targetCreatureID = MockRaces.TARGETS[kind] }, race = { kind = kind, length = length } }
    local key = NS.Bests.Key(probe)
    return key and NS.Bests.Compute(data and data.fights or {})[key] or nil
end

--- The sample race test mode holds and the sim plays: a sample fight on the dummy of `o.kind` carrying
--- its race part (status "running" until its read), its DPS set `o.factor` against the main hunter's
--- best on that race board in `data` (MockRaces.DPS on a board with none), and the record its read
--- leaves.
--- @param o table  { id, kind?, length?, factor?, status?, endAt?, died?, late?, shared?, tail?, combatEnd? }
--- @param data table|nil  MockFights.Dataset's
--- @return table sample  { fight, plan, who, race, record, best|nil, dps, length }
function MockRaces.Sample(o, data)
    local kind, length = o.kind or "single", o.length or MockRaces.LENGTH
    local best = MockRaces.BoardBest(kind, length, data)
    local dps = MockRaces.DPS
    if best and o.factor then dps = NS.RaceRecord.Dps(best) * o.factor end
    local spec = { id = o.id, t = time(), who = NS.MockFights.Character("me"), kind = kind, len = length, dps = dps,
                   status = o.status, endAt = o.endAt, died = o.died, late = o.late, shared = o.shared,
                   tail = o.tail, combatEnd = o.combatEnd }
    local record, plan = MockRaces.Record(spec)
    local fight = NS.MockFights.Fight({ id = o.id, board = MockRaces.Board(kind), who = spec.who, plan = plan })
    local race = { length = length, kind = kind, status = "running", grace = record.race.grace,
                   restartGap = record.race.restartGap, sample = true,
                   flags = { sharedSession = o.shared or nil } }
    fight.race, fight.recordID = race, record.id
    return { fight = fight, plan = plan, who = spec.who, race = race, record = record, best = best, dps = dps,
             length = length, spec = spec }
end
