local _, NS = ...
-- modules/Format.lua — every number the UI draws: the one secret-safe abbreviating formatter (spec
-- §3, §6), the fight clock, percentages and signed offsets. Ported from DPS Race @045f479
-- (modules/Format.lua) without its race: no race length, no run time with a DoT tail, no typed
-- length and no Arm refusal copy.
--
-- THE ONE FORMATTER. Abbreviating 2763000 to "2.76M" is a division, and a division on a secret value
-- raises in tainted code. Every live meter number is secret for the whole fight, so the live path
-- hands its values to the client's own formatter (C_StringUtil's abbreviated-number formatter, which
-- takes a secret and does the arithmetic natively) and to nothing else. This file owns the one
-- instance: built on first use, its breakpoints set and checked once, and given up for the session
-- if the client refuses them. A formatter that renders a check value wrongly is not used at all.
--
-- WHAT A RETURN VALUE IS. Format.Number answers "something FontString:SetText takes": a string, or,
-- on a client with no formatter at all, the secret itself (SetText accepts one). A caller may SetText
-- it and must do nothing else with it: no comparing, no concatenating, no measuring.
--
-- Everything else here (Clock, Pct, Signed) takes PLAIN numbers only: the HUD's own clock, an
-- after-combat read or a stored fight, never a live meter value.

local Format = {}
NS.Format = Format

local L = NS.L
local Secrets = NS.Secrets

-- The ladder, in the client's measured semantics: shown = n / (significandDivisor * fractionDivisor),
-- with log10(fractionDivisor) decimals, truncated. The mockup's figures: 188.4K, 30.36M.
local LADDER = {
    { breakpoint = 1, abbreviation = "", significandDivisor = 1, fractionDivisor = 1,
      abbreviationIsGlobal = false },
    { breakpoint = 1000, abbreviation = "K", significandDivisor = 100, fractionDivisor = 10,
      abbreviationIsGlobal = false },
    { breakpoint = 1000000, abbreviation = "M", significandDivisor = 10000, fractionDivisor = 100,
      abbreviationIsGlobal = false },
    { breakpoint = 1000000000, abbreviation = "B", significandDivisor = 10000000, fractionDivisor = 100,
      abbreviationIsGlobal = false },
}
-- The check a formatter must pass before it is trusted: what the ladder above renders this as.
local CHECK_VALUE, CHECK_TEXT = 2763000, "2.76M"

-- nil = not built yet, false = this client has none that works, else the instance.
local formatter

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Format", fmt, ...) end
end

-- The client's constructor is version-variant: core/Compat.lua owns it (compat).
local function newFormatter()
    local f = NS.Compat.NewNumberFormatter()
    if f == nil or type(f.SetBreakpoints) ~= "function" then return nil end
    return f
end

local function build()
    local f = newFormatter()
    if not f then return false end
    if not pcall(f.SetBreakpoints, f, LADDER) then
        debug("the client refused the breakpoints; numbers fall back")
        return false
    end
    local ok, out = pcall(f.FormatNumber, f, CHECK_VALUE)
    if not ok or out ~= CHECK_TEXT then
        debug("the formatter rendered the check value as %s; numbers fall back", tostring(out))
        return false
    end
    return f
end

local function instance()
    if formatter == nil then formatter = build() end
    return formatter or nil
end

--- Drop the formatter so the next number builds a fresh one (the harness's seam between instances).
function Format.Reset()
    formatter = nil
end

-- A plain number abbreviated in Lua, truncated as the client truncates.
local function abbreviate(n)
    local a = math.abs(n)
    local sign = n < 0 and "-" or ""
    if a >= 1e9 then return ("%s%.2fB"):format(sign, math.floor(a / 1e7) / 100) end
    if a >= 1e6 then return ("%s%.2fM"):format(sign, math.floor(a / 1e4) / 100) end
    if a >= 1e3 then return ("%s%.1fK"):format(sign, math.floor(a / 100) / 10) end
    return ("%s%d"):format(sign, math.floor(a))
end

--- A meter number as short text ("2.76M"), secret or plain. "" for nil.
--- @param v any  a number, possibly secret
--- @return any  a string, or the secret itself where no formatter exists (SetText takes either)
function Format.Number(v)
    if v == nil then return "" end
    local f = instance()
    if f then
        local ok, out = pcall(f.FormatNumber, f, v)
        if ok and out ~= nil then return out end
    end
    local plain = Secrets.PlainNumber(v)
    if plain then return abbreviate(plain) end
    local client = AbbreviateNumbers
    if type(client) == "function" then
        local ok, out = pcall(client, v)
        if ok and out ~= nil then return out end
    end
    return v
end

--- Seconds as the HUD's clock shows them: "m:ss.t", tenths truncated ("2:41.3"). Plain numbers only.
--- @param seconds number
--- @return string
function Format.Clock(seconds)
    if type(seconds) ~= "number" or seconds < 0 then seconds = 0 end
    local tenths = math.floor(seconds * 10 + 1e-6)
    local whole = math.floor(tenths / 10)
    return ("%d:%02d.%d"):format(math.floor(whole / 60), whole % 60, tenths % 10)
end

--- A length as "m:ss" ("4:12"). Plain numbers only.
--- @param seconds number
--- @return string
function Format.Length(seconds)
    if type(seconds) ~= "number" or seconds < 0 then seconds = 0 end
    local whole = math.floor(seconds + 0.5)
    return ("%d:%02d"):format(math.floor(whole / 60), whole % 60)
end

--- A percentage, one decimal ("27.6%"). Plain numbers only.
--- @param x number
--- @return string
function Format.Pct(x)
    if type(x) ~= "number" then return "" end
    return ("%.1f%%"):format(x)
end

--- A signed percentage, one decimal ("+2.1%", "-0.4%"). Plain numbers only.
--- @param x number
--- @return string
function Format.SignedPct(x)
    if type(x) ~= "number" then x = 0 end
    return L["%+.1f%%"]:format(x)
end
