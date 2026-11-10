local _, NS = ...
-- modules/CastCodec.lua — a fight's cast list as the one string the record stores (spec §5 record
-- size, plan Task 2.4). Pure: no client call, no state.
--
-- THE FORMAT. One token per cast, in list order, joined by ";":
--     <dt>:<id>[:<flags>]
--   dt     the cast's time minus the previous cast's (the first: minus 0), in whole tenths of a second,
--          base 36, a leading "-" when negative (a pre-pull cast, or a list out of order)
--   id     the spell ID, base 36
--   flags  "p" a pet cast, "x" an interrupted cast; absent when neither
-- Times are rounded to the tenth on the way in, so a decoded list encodes to the same string. A
-- press every 1.2 s with a six-digit spell ID is about eight bytes, so a 250-cast fight stays under
-- 2.5 KB (tests/test_cast_codec.lua holds it to that).
--
-- THE LIST is { { t = seconds from the fight's start, spellID, unit = "player"|"pet", interrupted } }
-- (modules/Casts.lua's shape). Decode skips a token that does not parse, and its delta with it.

local CastCodec = {}
NS.CastCodec = CastCodec

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local floor = math.floor

-- A whole number in base 36, "-" before a negative one.
local function b36(n)
    if n < 0 then return "-" .. b36(-n) end
    local out = ""
    repeat
        local r = n % 36
        out = DIGITS:sub(r + 1, r + 1) .. out
        n = (n - r) / 36
    until n == 0
    return out
end

local function tenths(t)
    return floor((tonumber(t) or 0) * 10 + 0.5)
end

local function flagsOf(c)
    local f = (c.unit == "pet" and "p" or "") .. (c.interrupted and "x" or "")
    return f ~= "" and (":" .. f) or ""
end

--- The stored string for a cast list ("" for none).
--- @param casts table|nil
--- @return string
function CastCodec.Encode(casts)
    local parts, prev = {}, 0
    for i, c in ipairs(type(casts) == "table" and casts or {}) do
        local at = tenths(c.t)
        parts[i] = b36(at - prev) .. ":" .. b36(floor(tonumber(c.spellID) or 0)) .. flagsOf(c)
        prev = at
    end
    return table.concat(parts, ";")
end

local FLAG_OK = { [""] = true, p = true, x = true, px = true, xp = true }

-- One token as (dt, id, flags), or nil when it does not parse.
local function parse(token)
    local dt, id, rest = token:match("^(%-?[0-9a-z]+):([0-9a-z]+)(.*)$")
    if not dt then return nil end
    local flags = rest == "" and "" or rest:match("^:([a-z]+)$")
    if not flags or not FLAG_OK[flags] then return nil end
    local neg = dt:sub(1, 1) == "-"
    local n = tonumber(neg and dt:sub(2) or dt, 36)
    local spellID = tonumber(id, 36)
    if not n or not spellID then return nil end
    return neg and -n or n, spellID, flags
end

--- The cast list a stored string holds, in stored order; a token that does not parse is skipped.
--- @param s string|nil
--- @return table casts
function CastCodec.Decode(s)
    local out = {}
    if type(s) ~= "string" or s == "" then return out end
    local at = 0
    for token in (s .. ";"):gmatch("([^;]*);") do
        local dt, spellID, flags = parse(token)
        if dt then
            at = at + dt
            out[#out + 1] = { t = at / 10, spellID = spellID, unit = flags:find("p", 1, true) and "pet" or "player",
                              interrupted = flags:find("x", 1, true) ~= nil }
        end
    end
    return out
end
