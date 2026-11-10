local _, NS = ...
-- modules/Hud_Best.lua — the pace data (spec §6, plan Task 3.2): what the stored fight the HUD paces
-- against (modules/Hud.lua PaceRecord: the board's best, or its newest fight) had done by each second
-- of its own clock, and the pace bar's ends around that figure. Adapted from DPS Race @045f479
-- (modules/Hud_Best.lua and modules/Hud_Chart.lua's Pace and PaceBounds) without its race: no race
-- length, no idle "Your best" card; a fight's own duration is the curve's length.
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
-- while the pet fill is drawn (Hud.PACE_PET_FILL, spec §6 and §12); `playerAt(t)` is the best's own
-- player damage alone, which the bar paces against when that seam is off and which the damage chart
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
--- damage alone with `playerOnly` (Hud.PACE_PET_FILL off).
--- @param curve table  Best.Curve's
--- @param t number
--- @param playerOnly boolean|nil
--- @return number
function Best.PaceAt(curve, t, playerOnly)
    if playerOnly then return curve:playerAt(t) end
    return curve:damageAt(t)
end

--- The live pace bar's view: the bounds around the best's pace at `t` (the fight's clock), the
--- player's live total and, with `withPet`, the pet's (both opaque, copied and never tested but for
--- nil).
--- @param curve table
--- @param t number
--- @param live table|nil  NS.Meter.ReadLive's
--- @param withPet boolean  Hud.PACE_PET_FILL
--- @return table { lo, hi, ref, player, pet, withPet }
function Best.LiveView(curve, t, live, withPet)
    local ref = Best.PaceAt(curve, t, not withPet)
    local lo, hi = Best.Bounds(ref)
    local view = { lo = lo, hi = hi, ref = ref, withPet = withPet }
    if type(live) ~= "table" then return view end
    if type(live.player) == "table" then view.player = live.player.total end
    if withPet and type(live.pet) == "table" then view.pet = live.pet.total end
    return view
end

--- The over card's pace bar: the fight's plain final player (and pet) damage against the best's pace
--- at the fight's length (`final.duration`, else `clock`). Nil for a fight the meter lost.
--- @param curve table
--- @param final table|nil  the after-combat read
--- @param clock number
--- @param withPet boolean
--- @return table|nil { lo, hi, ref, player, pet, withPet }
function Best.OverView(curve, final, clock, withPet)
    if type(final) ~= "table" or type(final.player) ~= "table" then return nil end
    local player = Secrets.PlainNumber(final.player.total)
    if not player then return nil end
    local t = Secrets.PlainNumber(final.duration) or tonumber(clock) or 0
    local ref = Best.PaceAt(curve, t, not withPet)
    local lo, hi = Best.Bounds(ref)
    local pet = withPet and type(final.pet) == "table" and Secrets.PlainNumber(final.pet.total) or nil
    return { lo = lo, hi = hi, ref = ref, player = player, pet = pet, withPet = withPet }
end
