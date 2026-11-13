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
-- if the client refuses them. A formatter that renders a check value wrongly is not used at all;
-- the next constructor is tried (core/Compat.lua lists them). A PLAIN number never reaches the
-- client formatter: Lua abbreviates it, truncating, so no fraction is ever drawn raw (plan v0.2 A5).
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
-- The checks a formatter must pass before it is trusted: what the ladder above renders each as. The
-- integer check proves the breakpoints took; the fractional one proves the formatter truncates a
-- fraction too. A client formatter measured passing an unfloored fraction through ("30.1904761904K",
-- docs/midnight-quirks.md) passes the first and fails the second.
local CHECKS = {
    { value = 2763000, text = "2.76M" },
    { value = 30190.4761904, text = "30.1K" },
}

-- The numeric RULE formatter's own shape (C_StringUtil.CreateNumericRuleFormatter, measured by
-- AuraMaster on 12.1): { threshold, format }, a value written through the highest rule it reaches.
-- It cannot divide, so it cannot abbreviate; a whole-number rule at least never draws a fraction
-- ("39", not "39.7142857..."). Tried when the constructor refuses the ladder, and checked the same way.
local RULES = { { threshold = 0, format = "%d" } }
local RULE_CHECKS = {
    { value = 77.142857, text = "77" },
    { value = 30190.4761904, text = "30190" },
}

-- nil = not built yet, false = this client has none that works, else the instance.
local formatter
-- The constructor that built it, for the debug line naming the path.
local formatterName

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Format", fmt, ...) end
end

-- Which path served a number, written when it changes (debug-logging-§8: no line per redraw). A
-- rate keeps its own key: the HUD draws a total and a rate on every redraw, and one shared key
-- logged a line at each alternation (the owner's WoW Forever log, 2026-11-11).
local function servedBy(path, key)
    if NS.DebugChanged then
        NS.DebugChanged(key or "format:path", "Format", "%s served by %s", key and "rates" or "numbers", path)
    end
end

-- An error's text for the log: "<secret>" when the client handed back a secret.
local function errText(e)
    if Secrets.IsSealed(e) then return "<secret>" end
    return tostring(e)
end

-- f:FormatNumber(v), at file scope so the call is pcall'd with no closure made per number (and a
-- userdata instance is indexed inside the pcall).
local function formatWith(f, v)
    return f:FormatNumber(v)
end

-- The first check `f` renders wrongly, as (value, what it drew), or nil when it passes them all.
-- The values are plain constants and the outputs plain strings, so comparing them is legal.
local function failedCheck(f, checks)
    for _, check in ipairs(checks) do
        local ok, out = pcall(formatWith, f, check.value)
        if not ok or out ~= check.text then return check.value, tostring(out) end
    end
    return nil
end

-- Whether `f` answers SetBreakpoints. A client object may be a table or a userdata (AuraMaster tests
-- only that one came back), so its type is not asked: the method is looked up in pcall.
local function setter(f)
    if f == nil or Secrets.IsSealed(f) then return nil end
    local ok, fn = pcall(function() return f.SetBreakpoints end)
    if ok and type(fn) == "function" then return fn end
    return nil
end

-- One constructor built, `list` set as its breakpoints and `checks` passed: the instance, or nil
-- (logged why). `how` names the attempt in the log ("" or " as a whole-number rule").
local function tryCandidate(c, list, checks, how)
    local ok, f = pcall(c.make)
    local set = ok and setter(f) or nil
    if not set then
        debug("%s built no formatter (%s); trying the next", c.name, ok and type(f) or "it raised")
        return nil
    end
    if not pcall(set, f, list) then
        debug("%s refused the breakpoints%s; trying the next", c.name, how)
        return nil
    end
    local value, out = failedCheck(f, checks)
    if value then
        debug("%s%s rendered the check value %s as %s; not used", c.name, how, tostring(value), out)
        return nil
    end
    return f
end

-- The client's constructors are version-variant: core/Compat.lua owns the list (compat). Each is
-- tried with the abbreviating ladder; the numeric rule formatter, refusing that, with RULES.
local function build()
    for _, c in ipairs(NS.Compat.NumberFormatterCandidates()) do
        local f = tryCandidate(c, LADDER, CHECKS, "")
        if not f and c.name == "CreateNumericRuleFormatter" then
            f = tryCandidate(c, RULES, RULE_CHECKS, " as a whole-number rule")
        end
        if f then
            formatterName = c.name
            debug("%s passed its checks; secret numbers go to it first", c.name)
            return f
        end
    end
    debug("no client formatter passed its checks; secret numbers go to AbbreviateNumbers")
    return false
end

local function instance()
    if formatter == nil then formatter = build() end
    return formatter or nil
end

-- ── AbbreviateNumbers with the ladder (Retail) ──────────────────────────────────────────────────
--
-- Retail's AbbreviateNumbers is taken to accept a second argument, a config CreateAbbreviateConfig
-- builds from a breakpoint list in the ladder's shape, and a secret from addon code as the plain call
-- does (the checks below are what decide it, not this assumption).
-- Without it the live figures drew the plain table's "24M" and FloorToNearestString's whole
-- "363477" (the owner's Retail screenshot, 2026-11-13). The config is built once and trusted only
-- when it renders CONFIG_CHECKS exactly: the ladder's two checks, and a fraction under a thousand that
-- must come back whole, since a rate goes here too. A client whose AbbreviateNumbers ignores the
-- config renders "2.8M" for the first check and is never used. Not measured in game: `/ct probe`'s
-- trial and `/ct debug`'s path line say whether it served.

local CONFIG_CHECKS = { CHECKS[1], CHECKS[2], { value = 69.5625, text = "69" } }
-- nil = not built yet, false = this client has none that passes, else the config.
local ladderConfig

local function abbreviateWith(v, config)
    return AbbreviateNumbers(v, config)
end

-- The config, or false (logged why).
local function buildConfig()
    local make = CreateAbbreviateConfig
    if type(make) ~= "function" or type(AbbreviateNumbers) ~= "function" then return false end
    local ok, config = pcall(make, LADDER)
    if not ok or not Secrets.IsPresent(config) then
        debug("CreateAbbreviateConfig built no config (%s)", ok and "it answered nothing" or ("raised: " .. errText(config)))
        return false
    end
    for _, check in ipairs(CONFIG_CHECKS) do
        local okDraw, out = pcall(abbreviateWith, check.value, config)
        if not okDraw or out ~= check.text then
            debug("AbbreviateNumbers with the ladder's config rendered %s as %s; not used", tostring(check.value),
                okDraw and tostring(out) or ("an error: " .. errText(out)))
            return false
        end
    end
    debug("AbbreviateNumbers with the ladder's config passed its checks; secret numbers and rates go to it")
    return config
end

-- A secret through AbbreviateNumbers with the ladder's config: the client's answer, or nil. A config
-- that raises on a secret is dropped for the session, as a formatter is.
local function viaConfig(v)
    if ladderConfig == nil then ladderConfig = buildConfig() end
    if not ladderConfig then return nil end
    local ok, out = pcall(abbreviateWith, v, ladderConfig)
    if ok and Secrets.IsPresent(out) then return out end
    if NS.DebugChanged then
        NS.DebugChanged("format:configfail", "Format", "AbbreviateNumbers with the ladder's config failed on a secret (%s)",
            ok and "it answered nothing" or ("raised: " .. errText(out)))
    end
    if not ok then ladderConfig = false end
    return nil
end

--- Drop the formatter so the next number builds a fresh one (the harness's seam between instances).
function Format.Reset()
    formatter, formatterName, ladderConfig = nil, nil, nil
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

-- A secret through the client: the trusted formatter, then AbbreviateNumbers, both in pcall. Either
-- answer goes to SetText untouched. nil when neither answered. An answer to a secret may itself be
-- secret (a secret string), so its presence is asked of Secrets.IsPresent and never compared to nil.
local function native(v)
    local f = instance()
    if f then
        local ok, out = pcall(formatWith, f, v)
        if ok and Secrets.IsPresent(out) then
            servedBy("the client formatter (" .. tostring(formatterName) .. ")")
            return out
        end
        -- It passed its plain checks but not this secret. Measured on WoW Forever (`/ct probe`,
        -- 2026-11-11): both client formatters raise "Secret values are only allowed during untainted
        -- execution", and an addon's code is never untainted, so it is dropped for the session.
        if NS.DebugChanged then
            NS.DebugChanged("format:fail", "Format", "%s failed on a secret (%s); AbbreviateNumbers next",
                tostring(formatterName), ok and "it answered nothing" or ("raised: " .. errText(out)))
        end
        if not ok then formatter = false end
    end
    local configured = viaConfig(v)
    if Secrets.IsPresent(configured) then
        servedBy("AbbreviateNumbers with the ladder's config")
        return configured
    end
    local client = AbbreviateNumbers
    if type(client) == "function" then
        local ok, out = pcall(client, v)
        if ok and Secrets.IsPresent(out) then
            servedBy("AbbreviateNumbers")
            return out
        end
    end
    return nil
end

--- A meter number as short text ("2.76M"), secret or plain, never a raw decimal. "" for nil.
--- A plain number abbreviates in Lua (legal on a plain value, and it truncates); a secret goes to
--- the client (`native`); the raw secret is the last resort, where the client offers nothing.
--- @param v any  a number, possibly secret
--- @return any  a string, or the secret itself where no formatter exists (SetText takes either)
function Format.Number(v)
    if v == nil then return "" end
    -- PlainNumber tests IsSealed before type(), so a secret never meets a Lua operator here.
    local plain = Secrets.PlainNumber(v)
    if plain then
        servedBy("Lua (plain)")
        return abbreviate(plain)
    end
    local out = native(v)
    if Secrets.IsPresent(out) then return out end
    servedBy("nothing: the raw value")
    return v
end

--- A per-second rate as short text. A plain rate abbreviates in Lua, as Number does ("30.1K",
--- "69"). A secret rate (the live DPS) goes first to AbbreviateNumbers with the ladder's config where
--- that passed its checks ("363.4K"). On Retail it then goes to the plain AbbreviateNumbers, the same
--- path that draws the live Damage beside it ("309K"): the owner's Retail screenshot, 2026-11-13, had
--- the Damage abbreviated and the DPS whole ("309060") while the config served neither. A rate under
--- a thousand may show the client's decimals there, the cost of an abbreviated figure. Elsewhere
--- (WoW Forever) it goes to C_StringUtil.FloorToNearestString,
--- which takes a secret from an addon and answers it whole: `/ct probe` on WoW Forever, 2026-11-11,
--- "ok, a secret" in combat and "69" for 69.5625 after it, where AbbreviateNumbers drew "69.5625"
--- and both client formatters refuse a secret from tainted code. Whole, not abbreviated: a live
--- rate of 30190.47 reads "30190". Without the helper, Number's chain.
--- @param v any  a number, possibly secret
--- @return any  a string, or what Number answers
function Format.Rate(v)
    if v == nil then return "" end
    if Secrets.PlainNumber(v) then return Format.Number(v) end
    local configured = viaConfig(v)
    if Secrets.IsPresent(configured) then
        servedBy("AbbreviateNumbers with the ladder's config", "format:rate")
        return configured
    end
    if NS.Compat.IsRetail() and type(AbbreviateNumbers) == "function" then
        local ok, out = pcall(AbbreviateNumbers, v)
        if ok and Secrets.IsPresent(out) then
            servedBy("AbbreviateNumbers", "format:rate")
            return out
        end
    end
    local floor = NS.Compat.NamespaceFunction("C_StringUtil", "FloorToNearestString")
    if floor then
        local ok, got = pcall(floor, v)
        if ok and Secrets.IsPresent(got) then
            servedBy("FloorToNearestString", "format:rate")
            return got
        end
    end
    return Format.Number(v)
end

-- ── `/ct probe`'s trial: every path a number could take to text ─────────────────────────────────

-- C_StringUtil's whole-number helpers, tried on the value where the client has them: a seam that
-- would end the live DPS's decimal tail without a formatter.
local STRING_UTIL_TRIALS = { "FloorToNearestString", "RoundToNearestString", "TruncateWhenZero" }

-- One pcall's answer, described: never the text of a secret.
local function answerOf(ok, got)
    if not ok then return "raised: " .. errText(got) end
    if Secrets.IsSealed(got) then return "ok, a secret" end
    if got == nil then return "ok, nil" end
    if type(got) == "string" then return ('ok, "%s"'):format(got) end
    return "ok, " .. tostring(got)
end

-- Constructor `c` built afresh, `list` set, then run on `v`: the answer, or where it stopped.
local function trialOf(c, list, v)
    local ok, f = pcall(c.make)
    if not ok then return "the constructor raised: " .. errText(f) end
    local set = setter(f)
    if not set then return "built no formatter (" .. (Secrets.IsSealed(f) and "secret" or type(f)) .. ")" end
    local okSet, err = pcall(set, f, list)
    if not okSet then return "refused the breakpoints: " .. errText(err) end
    return answerOf(pcall(formatWith, f, v))
end

-- AbbreviateNumbers on `v` with a fresh config from the ladder, described: Format.Trial's Retail line.
local function configTrial(v)
    local make = CreateAbbreviateConfig
    if type(make) ~= "function" then return "CreateAbbreviateConfig missing" end
    if type(AbbreviateNumbers) ~= "function" then return "AbbreviateNumbers missing" end
    local ok, config = pcall(make, LADDER)
    if not ok then return "CreateAbbreviateConfig raised: " .. errText(config) end
    return answerOf(pcall(abbreviateWith, v, config))
end

--- `/ct probe`'s trial of value `v` (the live DPS figure, secret in combat): each client formatter
--- built afresh with the ladder (the rule formatter with the whole-number rule too), the one in
--- use, AbbreviateNumbers, C_StringUtil's whole-number helpers and string.format, each answer
--- described ("ok, a secret", or the plain text). Never shows a secret's text.
--- @param v any
--- @return table lines
function Format.Trial(v)
    local value = Secrets.IsSealed(v) and "secret" or (v == nil and "nil" or ("plain " .. tostring(v)))
    local out = { "format trial: value " .. value }
    for _, c in ipairs(NS.Compat.NumberFormatterCandidates()) do
        out[#out + 1] = ("   %s with the ladder: %s"):format(c.name, trialOf(c, LADDER, v))
        if c.name == "CreateNumericRuleFormatter" then
            out[#out + 1] = ("   %s with the whole-number rule: %s"):format(c.name, trialOf(c, RULES, v))
        end
    end
    local inUse = formatter == nil and "not built yet" or (formatter == false and "none") or tostring(formatterName)
    out[#out + 1] = "   formatter in use: " .. inUse
    local abbr = AbbreviateNumbers
    out[#out + 1] = "   AbbreviateNumbers: " .. (type(abbr) == "function" and answerOf(pcall(abbr, v)) or "missing")
    out[#out + 1] = "   AbbreviateNumbers with the ladder's config: " .. configTrial(v)
    for _, name in ipairs(STRING_UTIL_TRIALS) do
        local fn = NS.Compat.NamespaceFunction("C_StringUtil", name)
        out[#out + 1] = ("   C_StringUtil.%s: %s"):format(name, fn and answerOf(pcall(fn, v)) or "missing")
    end
    out[#out + 1] = "   string.format %d: " .. answerOf(pcall(string.format, "%d", v))
    return out
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

--- A race's clock in the tenths every race clock draws (owner, 2026-11-13: the countdown, the time
--- elapsed beside it, the DPS HUD's clock and the center countdown agree): the elapsed time truncated
--- to its tenth, as Format.Clock draws the HUD's, and the time left the rest of the length, so the time
--- left is rounded UP to its tenth. It reads 0:00.0 only at the buzzer, every whole second n is reached
--- on the tenth the center countdown shows n (modules/Countdown.lua: whole seconds left, rounded up),
--- and the two always add up to the length. Plain numbers only; each answer is a multiple of 0.1 that
--- Format.Clock draws exactly.
--- @param elapsed number  seconds since the race's first hit
--- @param length number  the race length (s)
--- @return number elapsed, number left
function Format.RaceClock(elapsed, length)
    local total = math.floor((tonumber(length) or 0) * 10 + 0.5)
    local tenths = math.floor((tonumber(elapsed) or 0) * 10 + 1e-6)
    tenths = math.max(0, math.min(total, tenths))
    return tenths / 10, (total - tenths) / 10
end

--- A length as "m:ss" ("4:12"). Plain numbers only.
--- @param seconds number
--- @return string
function Format.Length(seconds)
    if type(seconds) ~= "number" or seconds < 0 then seconds = 0 end
    local whole = math.floor(seconds + 0.5)
    return ("%d:%02d"):format(math.floor(whole / 60), whole % 60)
end

--- An offset in seconds with its sign and one decimal ("+3.1"): the Race window's tail and time in
--- combat after the buzzer (DPS Race's Format.Seconds). Plain numbers only.
--- @param x number
--- @return string
function Format.Seconds(x)
    if type(x) ~= "number" then x = 0 end
    return L["+%.1f"]:format(x)
end

--- A race's time off its part (DPS Race's Format.RunTime on the race part): the race length and the
--- damage tail after the buzzer ("2:00 +11.1s"), or for an incomplete race its time in combat
--- against the length ("1:04 / 2:00"). Plain numbers only.
--- @param race table  a race part
--- @return string
function Format.RaceTime(race)
    race = type(race) == "table" and race or {}
    local length = Format.Length(race.length)
    if race.status == "incomplete" and type(race.endedAt) == "number" then
        return L["%s / %s"]:format(Format.Length(race.endedAt), length)
    end
    local tail = race.tail
    if type(tail) ~= "number" or tail < 0.05 then return length end
    return length .. " " .. L["+%.1fs"]:format(tail)
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
