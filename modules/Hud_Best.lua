local _, NS = ...
-- modules/Hud_Best.lua — the pace data (spec §6, plan Task 3.2): which stored fight the HUD paces
-- against (Best.PaceRecord, the DPS HUD's Hud.PaceRecord: the board's best, or its newest fight, with
-- the fight's target line and its curve), what it had done by each second of its own clock, and the
-- pace bar's ends around that figure. Adapted from DPS Race @045f479
-- (modules/Hud_Best.lua and modules/Hud_Chart.lua's Pace and PaceBounds) without its race: no race
-- length, no idle "Your best" card; a fight's own duration is the curve's length. A RACE best is paced
-- on its own straight line instead (HudBest.RaceCurve, Race mode plan Task C3): its score over its
-- race length, held at the score past the buzzer, read by the HUD and the Race window alike.
--
-- THE CURVE (HudBest.Curve) comes from the best's SESSION SLICES when this session holds them
-- (modules/Slices.lua, by the record's id) and every step it would read is a plain number, else it
-- is the best's linear average pace: its merged damage over its duration, times t. A slice captured
-- in combat stays secret, and a secret cannot be interpolated, so on a live client the slices serve
-- only a store that was filled with plain values (test mode, the sim, a fight read out of combat);
-- the linear pace is the rule, and the slices are the refinement when they can be read. Past the
-- curve's last step it runs on at the best's average rate, so a fight longer than the best keeps a
-- pace that grows.
--
-- TWO MEASURES. `damageAt(t)` is the best's MERGED damage (player and pet), the pace bar's reference
-- for a merged total (spec §6); `playerAt(t)` is the best's own player damage alone, which the bar
-- paces against when the pet has a live source of its own and which the damage chart
-- draws its best line from (the chart's columns are the player's live total alone: modules/Slices.lua
-- keeps the pet beside it, and the two can never be summed in combat).
--
-- PLAIN ONLY. Every number here is a stored record's (plain since NS.Secrets took it in) or a slice
-- PlainNumber answered; the bounds are plain, so the pace bar's SetMinMaxValues takes plain values and
-- only its SetValue takes the live (secret) total.

local Best = {}
NS.HudBest = Best

local Secrets = NS.Secrets

--- The pace bar range's bounds (`hud.paceRange`, the DPS HUD page's slider).
Best.RANGE_MIN, Best.RANGE_MAX = 1.1, 2.0

local function positive(v)
    return type(v) == "number" and v > 0 and v or nil
end

-- The record's damage figures: merged, and the player's own (the merged total when it has none).
local function damageOf(record)
    local d = type(record.damage) == "table" and record.damage or {}
    local merged = positive(d.merged)
    if not merged then return nil, nil end
    local player = type(d.player) == "number" and d.player >= 0 and d.player or merged
    return merged, player
end

-- The slices' points as plain { t, merged, player }, or nil when there are none or one step it would
-- read is still secret (a hole, nil, is skipped: it holds no total).
local function slicePoints(id)
    local rec = NS.Slices and NS.Slices.Get(id)
    if not rec or (tonumber(rec.filled) or 0) == 0 then return nil end
    local step = positive(rec.step) or NS.Slices.STEP
    local points = {}
    for i = 1, tonumber(rec.count) or 0 do
        local raw = rec.values[i]
        if raw ~= nil then
            local player = Secrets.PlainNumber(raw)
            if player == nil then return nil end
            local petRaw = rec.pet and rec.pet[i]
            local pet = 0
            if petRaw ~= nil then
                pet = Secrets.PlainNumber(petRaw)
                if pet == nil then return nil end
            end
            points[#points + 1] = { t = i * step, merged = player + pet, player = player }
        end
    end
    if #points == 0 then return nil end
    return points
end

-- The value of `field` at `t` along `points` (from 0 at 0:00), straight lines between steps, and on
-- at `rate` per second past the last one.
local function along(points, field, rate, t)
    local t0, v0 = 0, 0
    for _, p in ipairs(points) do
        if t <= p.t then
            local span = p.t - t0
            if span <= 0 then return p[field] end
            return v0 + (p[field] - v0) * (t - t0) / span
        end
        t0, v0 = p.t, p[field]
    end
    return v0 + rate * (t - t0)
end

local Curve = {}
Curve.__index = Curve

--- The best's merged damage by `t` seconds of its clock (0 before the start).
--- @param t number
--- @return number
function Curve:damageAt(t)
    t = tonumber(t) or 0
    if t <= 0 then return 0 end
    if self.points then return along(self.points, "merged", self.rate, t) end
    return self.rate * t
end

--- The best's player damage alone by `t` seconds (the pet left out).
--- @param t number
--- @return number
function Curve:playerAt(t)
    t = tonumber(t) or 0
    if t <= 0 then return 0 end
    if self.points then return along(self.points, "player", self.playerRate, t) end
    return self.playerRate * t
end

--- The pace curve of stored fight `recordID`: { id, duration, merged, player, fromSlices, rate,
--- playerRate, damageAt(t), playerAt(t) }, or nil when it has no plain damage and duration to pace
--- from (no such record, a lost one, an empty one).
--- @param recordID string
--- @param held table|nil  the record itself when the caller holds it (a sample fight's, which the
---   store does not)
--- @return table|nil curve
function Best.Curve(recordID, held)
    local record = type(held) == "table" and held or (recordID ~= nil and NS.Recorder.Get(recordID) or nil)
    if type(record) ~= "table" or record.status ~= "final" then return nil end
    local duration = positive(record.duration)
    local merged, player = damageOf(record)
    if not duration or not merged then return nil end
    local points = slicePoints(record.id)
    return setmetatable({ id = record.id, duration = duration, merged = merged, player = player,
                          rate = merged / duration, playerRate = player / duration,
                          points = points, fromSlices = points ~= nil }, Curve)
end

-- A race best's straight line (Race mode spec §4.4, DPS Race's Chart.Pace): its score by t, held at
-- the score past the race length; the player's own part at the record's share of its merged damage.
local RaceLine = {}
RaceLine.__index = RaceLine

local function clip(line, t)
    return math.max(0, math.min(tonumber(t) or 0, line.duration))
end

function RaceLine:damageAt(t) return self.rate * clip(self, t) end
function RaceLine:playerAt(t) return self.playerRate * clip(self, t) end

--- The pace curve of a stored RACE (a record with a `race` part): its score over its race length,
--- times t, held at the score past the buzzer (the tail is in the score, as in DPS Race), the player's
--- own part at the record's player share. The shape is Best.Curve's (`duration` is the race length),
--- so the HUD's pace bar and chart and the Race window's pace bar read one line. Nil for a record that
--- is no race, or one with no plain score or length to pace from.
--- @param record table
--- @return table|nil curve
function Best.RaceCurve(record)
    local race = type(record) == "table" and record.race or nil
    if type(race) ~= "table" then return nil end
    local score, length = positive(race.score), positive(race.length)
    if not (score and length) then return nil end
    local merged, player = damageOf(record)
    local share = (merged and player) and math.min(1, player / merged) or 1
    return setmetatable({ id = record.id, duration = length, merged = score, player = score * share,
                          rate = score / length, playerRate = score * share / length, fromSlices = false },
                        RaceLine)
end

--- The configured pace bar range (`hud.paceRange`), held to the slider's bounds at read time.
--- @return number
function Best.Range()
    local v = NS.Hud and NS.Hud.Setting and tonumber(NS.Hud.Setting("hud.paceRange"))
    return math.max(Best.RANGE_MIN, math.min(Best.RANGE_MAX, v or 1.5))
end

--- The pace bar's ends around `pace` (the best's damage by now): lo = pace x (2 - m), hi = pace x m,
--- `m` the range (default the setting), so the on-pace tick sits in the middle; hi is at least lo + 1
--- (0:00, where the pace is 0).
--- @param pace number
--- @param range number|nil
--- @return number lo, number hi
function Best.Bounds(pace, range)
    local m = math.max(Best.RANGE_MIN, math.min(Best.RANGE_MAX, tonumber(range) or Best.Range()))
    pace = math.max(0, tonumber(pace) or 0)
    local lo = pace * (2 - m)
    return lo, math.max(pace * m, lo + 1)
end

--- The reference the pace bar sets the fight against at `t`: the best's merged damage, or its player
--- damage alone with `playerOnly` (a live pet source of its own: the totals cannot be summed).
--- @param curve table  Best.Curve's
--- @param t number
--- @param playerOnly boolean|nil
--- @return number
function Best.PaceAt(curve, t, playerOnly)
    if playerOnly then return curve:playerAt(t) end
    return curve:damageAt(t)
end

--- The live pace bar's view: the bounds around the best's pace at `t` (the fight's clock) and the
--- one total the bar is handed (opaque, copied and never tested but for nil): the player's source
--- total. Where the pet folds into it (WoW Forever) or there is no pet, that is the merged figure,
--- against the best's merged pace; where the pet has a live source of its own (`live.pet`), the two
--- secrets cannot be summed, so the player's alone runs against the best's player damage.
--- @param curve table
--- @param t number
--- @param live table|nil  NS.Meter.ReadLive's
--- @return table { lo, hi, ref, total, playerOnly }
function Best.LiveView(curve, t, live)
    local playerOnly = type(live) == "table" and type(live.pet) == "table"
    local ref = Best.PaceAt(curve, t, playerOnly)
    local lo, hi = Best.Bounds(ref)
    local view = { lo = lo, hi = hi, ref = ref, playerOnly = playerOnly }
    if type(live) == "table" and type(live.player) == "table" then view.total = live.player.total end
    return view
end

--- The over card's pace bar: the fight's plain final merged damage (the player's and the pet's,
--- summed: plain after combat) against the best's merged pace at the fight's length
--- (`final.duration`, else `clock`). Nil for a fight the meter lost.
--- @param curve table
--- @param final table|nil  the after-combat read
--- @param clock number
--- @return table|nil { lo, hi, ref, total, playerOnly }
function Best.OverView(curve, final, clock)
    if type(final) ~= "table" or type(final.player) ~= "table" then return nil end
    local player = Secrets.PlainNumber(final.player.total)
    if not player then return nil end
    local t = Secrets.PlainNumber(final.duration) or tonumber(clock) or 0
    local ref = Best.PaceAt(curve, t, false)
    local lo, hi = Best.Bounds(ref)
    local pet = type(final.pet) == "table" and Secrets.PlainNumber(final.pet.total) or 0
    return { lo = lo, hi = hi, ref = ref, total = player + pet, playerOnly = false }
end

-- ── the pace lookup (Hud.PaceRecord's, here since W29) ──────────────────────────────────────────

--- The fight's identity (Identity.Resolve), or an empty one.
function Best.Identity(fight)
    local ok, ident = pcall(NS.Identity.Resolve, fight, nil, nil)
    if ok and type(ident) == "table" then return ident end
    return {}
end

-- The board's newest fight in `list` (newest first), for `hud.paceAgainst` "last".
local function lastOnBoard(probe, list)
    local boardKey = NS.Bests.Key(probe)
    if not boardKey then return nil end
    for _, r in ipairs(list) do
        if r.status == "final" and NS.Bests.Key(r) == boardKey then return r end
    end
    return nil
end

-- A fight on a shared session (race plan ruling X3): its live total holds the damage from before the
-- race's arm, which cannot be netted in combat.
function Best.OnSharedSession(fight)
    if fight.sharedSession == true then return true end
    local race = fight.race
    return type(race) == "table" and type(race.flags) == "table" and race.flags.sharedSession == true
end

-- The record the pace looks up: the fight's board, or while it carries its race part the race board
-- (Bests.Key reads a probe with a `race` part as a race: its kind and length).
local function probeOf(fight, ident)
    local snap = type(fight.snapshot) == "table" and fight.snapshot or {}
    local probe = { who = snap.who, boardKey = NS.Identity.BoardKey(ident), identity = ident, status = "final" }
    local race = fight.race
    if type(race) == "table" then probe.race = { kind = race.kind, length = race.length } end
    return probe
end

--- The stored fight the live fight is paced against (`hud.paceAgainst`): its board's best, its
--- board's newest fight, or nil (none, an unknown target, a board with nothing on it, a shared
--- session). While the fight carries its race part, the board is its race board. A sample fight is
--- paced against the sample history.
--- @param fight table
--- @param ident table|nil  the fight's identity (Identity.Resolve), read when nil
--- @return table|nil record
function Best.PaceRecord(fight, ident)
    local against = NS.Hud and NS.Hud.Setting and NS.Hud.Setting("hud.paceAgainst")
    if against == "none" or type(fight) ~= "table" or Best.OnSharedSession(fight) then return nil end
    local probe = probeOf(fight, ident or Best.Identity(fight))
    if fight.sample then
        local Source = NS.ResultsSource
        if against == "last" then return lastOnBoard(probe, Source.All()) end
        return Source.BestFor(probe)
    end
    if against == "last" then return lastOnBoard(probe, NS.Recorder.List()) end
    return NS.Bests.For(probe)
end

-- "<boss or target> · <instance> · <difficulty>", plain strings only.
function Best.TargetLine(ident)
    local parts = {}
    local name = Secrets.PlainString(ident.encounterName) or Secrets.PlainString(ident.targetName)
    for _, s in ipairs({ name, Secrets.PlainString(ident.instanceName), Secrets.PlainString(ident.difficultyName) }) do
        if s and s ~= "" then parts[#parts + 1] = s end
    end
    return table.concat(parts, " \194\183 ")
end

-- The pace record's curve: a race's straight line (its score over its length), else the fight's.
function Best.CurveOf(pace)
    if not pace then return nil end
    if NS.RaceRecord.IsRace(pace) then return NS.HudBest.RaceCurve(pace) end
    return NS.HudBest.Curve(pace.id, pace)
end
