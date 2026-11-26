local _, NS = ...
-- modules/Hud_Split.lua — how the DPS HUD's grip shares a height between the spell rows and the
-- docked Combat Sequence's rows (owner feedback round 4, R4-CT-07). Pure: plain numbers in, plain
-- numbers out, no frame, no setting; modules/Hud.lua hands it the height function and the limits.
--
-- THE WALK. From the pair the grip went down on, one row at a time toward the dragged height, the
-- last pair whose height fits. Shrinking takes a row from the larger side, the sequence on a tie
-- (5/5 -> 5/4 -> 4/4 -> 4/3 -> 3/3), never under each side's least. Growing adds a row to the smaller
-- side, the spells on a tie (5/5 -> 6/5 -> 6/6), until the spells reach their most, then only the
-- sequence grows. The walk is monotonic, so it ends within (maxB - minB) + (maxL - minL) steps.

local Split = {}
NS.HudSplit = Split

local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

--- How far short of a pair's height a height the client hands back may fall and still hold it: the
--- client snaps a frame's size to its pixels, so the HUD's own height can come back a hair short and
--- a grip's release lands a hair off (owner feedback round 5, R5-CT-01: the default 5/5 was read as 5/4).
Split.SLACK = 0.5

--- A height the client handed back, with Split.SLACK forgiven (nil passes through).
--- @param h number|nil
--- @return number|nil
function Split.Forgive(h)
    return h and h + Split.SLACK
end

-- The next pair up, or nil at the most.
local function grow(b, l, lim)
    if b <= l and b < lim.maxB then return b + 1, l end
    if l < lim.maxL then return b, l + 1 end
    if b < lim.maxB then return b + 1, l end
    return nil
end

-- The next pair down, or nil at the least.
local function shrink(b, l, lim)
    if l >= b and l > lim.minL then return b, l - 1 end
    if b > lim.minB then return b - 1, l end
    if l > lim.minL then return b, l - 1 end
    return nil
end

--- The spell rows and sequence rows a height `h` holds, walked from the pair (b0, l0).
--- @param h number        the dragged height
--- @param b0 number       the spell rows the grip went down on
--- @param l0 number       the sequence rows the grip went down on
--- @param heightOf function(b, l) -> number, the window's height for that pair
--- @param lim table       { minB, maxB, minL, maxL }
--- @return number, number the spell rows, the sequence rows
function Split.Walk(h, b0, l0, heightOf, lim)
    local b = clamp(math.floor(tonumber(b0) or lim.minB), lim.minB, lim.maxB)
    local l = clamp(math.floor(tonumber(l0) or lim.minL), lim.minL, lim.maxL)
    h = tonumber(h) or 0
    if heightOf(b, l) <= h then
        local nb, nl = grow(b, l, lim)
        while nb and heightOf(nb, nl) <= h do
            b, l = nb, nl
            nb, nl = grow(b, l, lim)
        end
        return b, l
    end
    while heightOf(b, l) > h do
        local nb, nl = shrink(b, l, lim)
        if not nb then break end
        b, l = nb, nl
    end
    return b, l
end
