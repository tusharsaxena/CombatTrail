local _, NS = ...
-- modules/LaneLayout.lua — the lanes' layout math (spec §4, Size and position): PURE, no frame, no
-- global, no state, so every number modules/LaneRender.lua draws is a number a headless test can
-- pin. A lane is `width` pixels long and shows the last `seconds` of casts, so a cast moves
-- width / seconds pixels a second away from the "now" edge.
--
-- DIRECTION is the way the icons scroll, away from the edge the newest sits at:
--   left   newest at the right edge, scrolling left (the default, as CastTrail)
--   right  newest at the left edge, scrolling right
--   up     newest at the bottom edge, scrolling up
--   down   newest at the top edge, scrolling down
-- An unknown direction reads as left. The lane's length runs along x for left and right and along y
-- for up and down; its thickness is one icon either way.
--
-- DISTANCE is how far an icon's leading edge sits from the now edge, in pixels. It is the cast's age
-- times the speed, except that a cast close behind a newer one is pushed one icon plus `spacing`
-- further, so two casts a moment apart never draw on top of each other (TrufiGCD's push-apart). An
-- icon whose distance reaches the lane's length has scrolled fully past the far edge and expires.
-- POSITION is an icon's TOPLEFT offset inside the lane's inner area (down is negative, as SetPoint).

local LaneLayout = {}
NS.LaneLayout = LaneLayout

local VERTICAL = { up = true, down = true }

-- The haste-adjusted GCD's floor (the client's 0.75 s minimum) and the base GCD.
local GCD_BASE, GCD_FLOOR = 1.5, 0.75
-- Ticks a lane draws at most: a 1 s step over a long lane stays readable, a runaway setting does not
-- build a thousand textures.
LaneLayout.MAX_TICKS = 120

local function num(v, default)
    if type(v) == "number" and v == v then return v end
    return default
end

local function dims(cfg)
    local width = math.max(1, num(cfg.width, 480))
    local seconds = math.max(0.1, num(cfg.seconds, 12))
    local icon = math.max(1, num(cfg.iconSize, 28))
    return width, seconds, icon
end

--- Pixels per second.
--- @param cfg table a lane's settings
--- @return number
function LaneLayout.Speed(cfg)
    local width, seconds = dims(cfg)
    return width / seconds
end

--- How far an icon of `age` seconds sits from the now edge, given the distance of the next newer
--- icon (nil for the newest). Never closer to that one than an icon plus `spacing`.
--- @param age number
--- @param prevDist number|nil
--- @param cfg table
--- @return number
function LaneLayout.Distance(age, prevDist, cfg)
    local _, _, icon = dims(cfg)
    local d = math.max(0, num(age, 0)) * LaneLayout.Speed(cfg)
    if prevDist then
        local floor = prevDist + icon + math.max(0, num(cfg.spacing, 0))
        if d < floor then d = floor end
    end
    return d
end

--- Whether an icon this far from the now edge has scrolled fully off the lane.
function LaneLayout.Expired(dist, cfg)
    local width = dims(cfg)
    return dist >= width
end

--- The TOPLEFT offset of an icon `dist` pixels from the now edge.
--- @return number x, number y
function LaneLayout.Offset(dist, cfg)
    local width, _, icon = dims(cfg)
    local span = width - icon
    local dir = cfg.direction
    if dir == "right" then return dist, 0 end
    if dir == "down" then return 0, -dist end
    if dir == "up" then return 0, -(span - dist) end
    return span - dist, 0
end

--- The TOPLEFT offset of a lone icon of `age` seconds (no newer neighbor pushing it).
--- @return number x, number y
function LaneLayout.Position(age, cfg)
    return LaneLayout.Offset(LaneLayout.Distance(age, nil, cfg), cfg)
end

--- An icon's opacity at `age` seconds: 1 until the last `fade` portion of the window, then down to 0
--- at the far edge.
--- @return number 0..1
function LaneLayout.Alpha(age, cfg)
    local _, seconds = dims(cfg)
    local fade = math.min(1, math.max(0, num(cfg.fade, 0)))
    age = num(age, 0)
    if age >= seconds then return fade > 0 and 0 or 1 end
    if fade <= 0 then return 1 end
    local start = seconds * (1 - fade)
    if age <= start then return 1 end
    return 1 - (age - start) / (seconds - start)
end

--- The seconds between two reference ticks: "gcd15" 1.5 s, "1s" 1 s, "haste" the GCD at `haste`
--- percent spell haste (floored at 0.75 s; unknown haste reads as none).
--- @param cfg table
--- @param haste number|nil
--- @return number
function LaneLayout.TickStep(cfg, haste)
    local mode = cfg.tickSpacing
    if mode == "1s" then return 1 end
    if mode == "haste" then
        local h = math.max(0, num(haste, 0))
        return math.max(GCD_FLOOR, GCD_BASE / (1 + h / 100))
    end
    return GCD_BASE
end

--- The ticks' distances from the now edge, one every `step` seconds up to the far edge.
--- @param cfg table
--- @param step number|nil seconds
--- @return table { px... }
function LaneLayout.TickOffsets(cfg, step)
    local out = {}
    step = num(step, 0)
    if step <= 0 then return out end
    local width = dims(cfg)
    local px = step * LaneLayout.Speed(cfg)
    local n = math.min(LaneLayout.MAX_TICKS, math.floor(width / px + 1e-9))
    for i = 1, n do out[i] = i * px end
    return out
end

--- The lane's outer size: length by one icon, plus the padding on every side, turned for up and down.
--- @return number w, number h
function LaneLayout.LaneSize(cfg)
    local width, _, icon = dims(cfg)
    local pad = 2 * math.max(0, num(cfg.padding, 0))
    if VERTICAL[cfg.direction] then return icon + pad, width + pad end
    return width + pad, icon + pad
end

--- Whether the lane runs along y.
function LaneLayout.IsVertical(cfg)
    return VERTICAL[cfg.direction] == true
end
