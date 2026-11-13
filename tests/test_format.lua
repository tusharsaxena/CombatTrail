-- tests/test_format.lua — modules/Format.lua (plan v0.2 Task A5, spec §3): the one secret-safe number
-- formatter never draws a raw decimal. A plain number abbreviates in Lua; a secret goes to the first
-- client formatter that passes both the integer and the fractional check; with none trusted, it goes
-- to AbbreviateNumbers, and the raw secret is the last resort. Also the plain helpers (Clock, Length,
-- Pct, SignedPct).

local T = _G.CT_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local Formatter = dofile(T.root .. "/tests/mock_formatter.lua")(T)

local FRACTION = 30190.4761904

local function fresh(spec)
    local inst = T.load{ mutate = function(m) if spec then Formatter.install(m, spec) end end }
    return inst.NS, inst.mocks, inst
end

local function logged(inst, needle)
    local n = 0
    for _, line in ipairs(inst.NS.DebugLog.buffer) do
        if line:find(needle, 1, true) then n = n + 1 end
    end
    return n
end

-- The values a formatter was handed after its two checks.
local function handedAfterChecks(f)
    return #f.seen - 2
end

test("format: a plain fractional DPS abbreviates in Lua, never through the client formatter", function()
    local NS, m = fresh{ abbreviated = "raw" }
    assertEqual(NS.Format.Number(77.142857), "77", "no raw decimals")
    assertEqual(NS.Format.Number(FRACTION), "30.1K")
    assertEqual(NS.Format.Number(2763000), "2.76M")
    assertEqual(NS.Format.Number(812), "812")
    assertEqual(NS.Format.Number(nil), "")
    for _, f in ipairs(m.__formatters) do
        assertEqual(handedAfterChecks(f), 0, "a plain number never reaches " .. f.name)
    end
end)

test("format: a secret goes to a formatter that passes both checks", function()
    local NS, m = fresh{ abbreviated = "floor" }
    assertEqual(NS.Format.Number(T.secret(FRACTION)), "30.1K")
    assertEqual(NS.Format.Number(T.secret(130600)), "130.6K")
    local f = m.__formatters[1]
    assertTrue(T.isSecret(f.seen[#f.seen]), "the secret itself was handed over")
    NS.Format.Number(77.142857)
    assertEqual(handedAfterChecks(f), 2, "a plain number skips even a trusted formatter")
end)

test("format: a formatter that renders a fraction raw fails the check, and the next constructor answers", function()
    local NS, m = fresh{ abbreviated = "raw", numeric = "floor" }
    assertEqual(NS.Format.Number(T.secret(FRACTION)), "30.1K")
    assertEqual(#m.__formatters, 2, "both constructors were tried")
    assertEqual(m.__formatters[1].name, "abbreviated", "in order")
    assertEqual(handedAfterChecks(m.__formatters[1]), 0, "the raw formatter is never used")
    assertEqual(handedAfterChecks(m.__formatters[2]), 1, "the numeric-rule formatter served the secret")
end)

test("format: a client formatter that is a userdata, not a table, is still used (WoW Forever, 2026-11-11)", function()
    local NS, m = fresh{ abbreviated = "floor", userdata = true }
    assertEqual(NS.Format.Number(T.secret(FRACTION)), "30.1K")
    assertEqual(#m.__formatters, 1, "the abbreviated formatter served")
end)

test("format: a rule formatter refusing the ladder serves whole numbers, never a raw fraction", function()
    local NS, m, inst = fresh{ abbreviated = "raw", numeric = "rule" }
    NS.State.debug = true
    assertEqual(NS.Format.Number(T.secret(39.7142857)), "39", "the live DPS without its tail")
    assertEqual(NS.Format.Number(T.secret(FRACTION)), "30190", "whole, if not abbreviated")
    assertTrue(#m.__formatters >= 2, "the abbreviated one was tried first")
    assertEqual(logged(inst, "CreateNumericRuleFormatter refused the breakpoints; trying the next"), 1)
end)

test("format: a secret with no trusted formatter goes to AbbreviateNumbers", function()
    local NS, m = fresh{ abbreviated = "raw", numeric = "raw", abbreviate = true }
    local s = T.secret(FRACTION)
    assertEqual(NS.Format.Number(s), "abbr")
    assertEqual(#m.__abbreviated, 1)
    assertTrue(m.__abbreviated[1] == s, "the secret itself, untouched")
end)

test("format: a secret with no client formatter at all is handed back untouched", function()
    local NS = fresh()
    local s = T.secret(1539711)
    assertTrue(NS.Format.Number(s) == s, "the secret itself goes to SetText")
    assertEqual(NS.Format.Number(1539711), "1.53M")
    assertEqual(NS.Format.Number(1234), "1.2K")
    assertEqual(NS.Format.Number(3e9), "3.00B")
    assertEqual(NS.Format.Number(-1234), "-1.2K")
end)

-- The client's formatters answer a secret with a secret string. Lua 5.1 cannot trap `out ~= nil`
-- against a wrapper (the kit's secrets.lua: `==` against a non-table never consults __eq), so the
-- case asserts it explicitly: Format's presence test on a client answer is Secrets.IsPresent, which
-- never compares the value, and no `~= nil` / `== nil` on a client answer is left in the file.
test("format: a secret the client formatter answers with a secret string goes to SetText untouched", function()
    local inst = T.load{ mutate = function(m)
        Formatter.install(m, { abbreviated = "floor", abbreviate = true })
        local util = m.C_StringUtil
        local make = util.CreateAbbreviatedNumberFormatter
        util.CreateAbbreviatedNumberFormatter = function()
            local f = make()
            local plain = f.FormatNumber
            function f:FormatNumber(v)
                local out = plain(self, v)
                if T.isSecret(v) then return T.secret(out) end
                return out
            end
            return f
        end
    end }
    local NS = inst.NS
    local asked = 0
    local present = NS.Secrets.IsPresent
    NS.Secrets.IsPresent = function(v) asked = asked + 1; return present(v) end
    local out = NS.Format.Number(T.secret(FRACTION))
    NS.Secrets.IsPresent = present
    assertTrue(T.isSecret(out), "the formatter's secret string itself")
    assertEqual(T.reveal(out), "30.1K")
    assertTrue(asked >= 1, "the answer's presence asked of Secrets.IsPresent")
    local fh = assert(io.open(T.root .. "/modules/Format.lua", "rb"))
    local src = fh:read("*a")
    fh:close()
    assertTrue(not src:find("out%s*[~=]=%s*nil"), "no comparison of a client answer against nil")
end)

test("format: Secrets.IsPresent answers a secret and a plain value without comparing either", function()
    local NS = fresh()
    local restore = T.installSecretValue()
    local S = NS.Secrets
    local ok, err = pcall(function()
        assertTrue(S.IsPresent(T.secret("30.1K")), "a secret string is present")
        assertTrue(S.IsPresent(T.secret(false)), "a secret false is present")
        assertTrue(S.IsPresent("x") and S.IsPresent(0) and S.IsPresent(false), "plain values are present")
        assertTrue(not S.IsPresent(nil), "nil is absent")
    end)
    restore()
    assert(ok, err)
end)

test("format: the debug log names the path that served a number, once per change", function()
    local NS, _, inst = fresh{ abbreviated = "raw", numeric = "floor" }
    NS.State.debug = true
    NS.Format.Number(T.secret(FRACTION))
    NS.Format.Number(T.secret(FRACTION))
    assertEqual(logged(inst, "[Format] numbers served by the client formatter (CreateNumericRuleFormatter)"), 1)
    assertEqual(logged(inst, "[Format] CreateAbbreviatedNumberFormatter rendered "), 1,
        "the build names the constructor it passed over")
    NS.Format.Number(12.5)
    assertEqual(logged(inst, "[Format] numbers served by Lua (plain)"), 1)
end)

test("format: a refused or failing constructor is skipped", function()
    local inst = T.load{ mutate = function(m)
        m.C_StringUtil = {
            CreateAbbreviatedNumberFormatter = function() error("refused") end,
            CreateNumericRuleFormatter = function()
                return { SetBreakpoints = function() end, FormatNumber = function() return "nonsense" end }
            end,
        }
    end }
    local s = T.secret(5)
    assertTrue(inst.NS.Format.Number(s) == s, "neither was trusted")
    assertEqual(inst.NS.Format.Number(2763000), "2.76M")
end)

test("format: a formatter that passes its checks but raises on a secret says so, once (WoW Forever, 2026-11-11)", function()
    local NS, _, inst = fresh{ abbreviated = "floor", secretRaises = true, abbreviate = true }
    NS.State.debug = true
    assertEqual(NS.Format.Number(T.secret(FRACTION)), "abbr", "AbbreviateNumbers next")
    NS.Format.Number(T.secret(FRACTION))
    assertEqual(logged(inst, "CreateAbbreviatedNumberFormatter passed its checks; secret numbers go to it first"), 1)
    assertEqual(logged(inst, "CreateAbbreviatedNumberFormatter failed on a secret (raised: "), 1, "once, not per number")
end)

test("format: the probe's trial runs every path on a value and describes each answer", function()
    local NS = fresh{ abbreviated = "floor", numeric = "rule", abbreviate = true }
    local lines = NS.Format.Trial(FRACTION)
    local all = table.concat(lines, "\n")
    assertEqual(lines[1], "format trial: value plain " .. tostring(FRACTION))
    assertTrue(all:find('CreateAbbreviatedNumberFormatter with the ladder: ok, "30.1K"', 1, true) ~= nil, all)
    assertTrue(all:find('CreateNumericRuleFormatter with the whole-number rule: ok, "30190"', 1, true) ~= nil, all)
    assertTrue(all:find("formatter in use: not built yet", 1, true) ~= nil, all)
    assertTrue(all:find('AbbreviateNumbers: ok, "abbr"', 1, true) ~= nil, all)
    assertTrue(all:find("C_StringUtil.FloorToNearestString: missing", 1, true) ~= nil, all)
    assertTrue(all:find('string.format %d: ok, "30190"', 1, true) ~= nil, all)
end)

test("format: the trial on a secret never shows its text", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        -- The client answers a secret with a secret string, as AbbreviateNumbers does here.
        local inst = T.load{ mutate = function(m)
            m.AbbreviateNumbers = function(v) return T.isSecret(v) and T.secret("30.1K") or "30.1K" end
        end }
        local lines = inst.NS.Format.Trial(T.secret(FRACTION))
        local all = table.concat(lines, "\n")
        assertEqual(lines[1], "format trial: value secret")
        assertTrue(all:find("AbbreviateNumbers: ok, a secret", 1, true) ~= nil, all)
        assertEqual(all:find("30.1K", 1, true), nil, "a secret answer's text is not printed")
    end)
    restore()
    assertTrue(ok, tostring(err))
end)

test("format: a client formatter that raises on a secret is dropped after the first", function()
    local NS, m = fresh{ abbreviated = "floor", secretRaises = true, abbreviate = true }
    NS.Format.Number(T.secret(FRACTION))
    NS.Format.Number(T.secret(FRACTION))
    assertEqual(handedAfterChecks(m.__formatters[1]), 1, "tried on one secret, then not again")
end)

-- C_StringUtil.FloorToNearestString as measured (WoW Forever, 2026-11-11): a secret in, a secret
-- string out; a plain value floored to its whole digits.
local function withFloor(spec)
    local inst = T.load{ mutate = function(m)
        Formatter.install(m, spec)
        m.C_StringUtil.FloorToNearestString = function(v)
            local s = tostring(math.floor(T.reveal(v)))
            return T.isSecret(v) and T.secret(s) or s
        end
    end }
    return inst.NS, inst.mocks
end

test("format: a secret rate is written whole by FloorToNearestString, never with its decimal tail", function()
    local NS = withFloor{ abbreviated = "floor", secretRaises = true, abbreviate = true }
    if NS.Compat.IsRetail() then
        -- Retail: the plain AbbreviateNumbers, as the live Damage beside it.
        assertEqual(T.reveal(NS.Format.Rate(T.secret(FRACTION))), T.reveal(NS.Format.Number(T.secret(FRACTION))))
        return
    end
    local out = NS.Format.Rate(T.secret(69.5625))
    assertTrue(T.isSecret(out), "the helper's secret string, untouched")
    assertEqual(T.reveal(out), "69")
    assertEqual(T.reveal(NS.Format.Rate(T.secret(FRACTION))), "30190", "whole, not abbreviated")
end)

test("format: a total and a rate drawn in turn log each path once, not a line per redraw", function()
    local inst = T.load{ mutate = function(m)
        Formatter.install(m, { abbreviated = "floor", secretRaises = true, abbreviate = true })
        m.C_StringUtil.FloorToNearestString = function(v) return T.secret(tostring(math.floor(T.reveal(v)))) end
    end }
    local NS = inst.NS
    NS.State.debug = true
    for _ = 1, 5 do
        NS.Format.Number(T.secret(1243))
        NS.Format.Rate(T.secret(59.047619))
    end
    assertEqual(logged(inst, "numbers served by AbbreviateNumbers"), 1)
    local ratePath = NS.Compat.IsRetail() and "rates served by AbbreviateNumbers" or "rates served by FloorToNearestString"
    assertEqual(logged(inst, ratePath), 1)
end)

test("format: a plain rate abbreviates in Lua; with no helper a secret rate takes Number's chain", function()
    local NS = withFloor{ abbreviated = "floor" }
    assertEqual(NS.Format.Rate(FRACTION), "30.1K")
    assertEqual(NS.Format.Rate(69.5625), "69")
    assertEqual(NS.Format.Rate(nil), "")
    local bare = fresh{ abbreviated = "floor" }
    assertEqual(bare.Format.Rate(T.secret(FRACTION)), "30.1K", "the client formatter, as Number")
end)

-- Retail's AbbreviateNumbers takes a config (CreateAbbreviateConfig) and a secret: the live figures
-- drew "24M" and a whole "363477" there (the owner, 2026-11-13), the plain global's table and
-- FloorToNearestString, while the config carries the ladder.
test("format: a secret goes to AbbreviateNumbers with the ladder's config once it passes the checks", function()
    local NS, m = fresh{ abbreviated = "floor", secretRaises = true, config = "floor" }
    assertEqual(T.reveal(NS.Format.Number(T.secret(24390000))), "24.39M")
    assertEqual(T.reveal(NS.Format.Number(T.secret(FRACTION))), "30.1K")
    assertTrue(T.isSecret(m.__abbreviated[#m.__abbreviated]), "the secret itself was handed over")
end)

test("format: a secret rate takes the ladder's config before FloorToNearestString", function()
    local NS = withFloor{ abbreviated = "floor", secretRaises = true, config = "floor" }
    local out = NS.Format.Rate(T.secret(363477.4))
    assertTrue(T.isSecret(out), "the client's secret string, untouched")
    assertEqual(T.reveal(out), "363.4K")
    assertEqual(T.reveal(NS.Format.Rate(T.secret(69.5625))), "69", "no decimal tail under a thousand")
end)

test("format: a config that draws a fraction raw is never used; the rate takes the client's next path", function()
    local NS = withFloor{ abbreviated = "floor", secretRaises = true, config = "raw" }
    local whole = NS.Compat.IsRetail() and "abbr" or "30190"
    assertEqual(T.reveal(NS.Format.Rate(T.secret(FRACTION))), whole, "Retail: AbbreviateNumbers; else FloorToNearestString")
    assertEqual(NS.Format.Number(T.secret(FRACTION)), "abbr", "the plain AbbreviateNumbers")
end)

test("format: the probe's trial runs AbbreviateNumbers with the ladder's config", function()
    local NS = fresh{ abbreviated = "floor", config = "floor" }
    local all = table.concat(NS.Format.Trial(FRACTION), "\n")
    assertTrue(all:find('AbbreviateNumbers with the ladder\'s config: ok, "30.1K"', 1, true) ~= nil, all)
end)

test("format: Clock, Length, Pct and SignedPct take plain numbers", function()
    local F = T.NS.Format
    assertEqual(F.Clock(161.34), "2:41.3")
    assertEqual(F.Clock(-1), "0:00.0")
    assertEqual(F.Length(90), "1:30")
    assertEqual(F.Pct(27.63), "27.6%")
    assertEqual(F.Pct(nil), "")
    assertEqual(F.SignedPct(2.14), "+2.1%")
end)

-- The race clock (owner, 2026-11-13): one count of tenths, the elapsed truncated, the time left the
-- rest of the length (rounded up), so the two add up and 0:00.0 is the buzzer's alone.
test("format: RaceClock splits a race into the elapsed and the time left at the same tenth", function()
    local F = T.NS.Format
    local function at(elapsed, length)
        local e, l = F.RaceClock(elapsed, length or 60)
        return F.Clock(e) .. " " .. F.Clock(l)
    end
    assertEqual(at(0), "0:00.0 1:00.0", "the first hit")
    assertEqual(at(0.05), "0:00.0 1:00.0", "inside the first tenth")
    assertEqual(at(0.1), "0:00.1 0:59.9", "on a tenth's edge")
    assertEqual(at(58.95), "0:58.9 0:01.1")
    assertEqual(at(59), "0:59.0 0:01.0", "one second left: the center countdown's 1 pops here")
    assertEqual(at(59.05), "0:59.0 0:01.0")
    assertEqual(at(59.9), "0:59.9 0:00.1")
    assertEqual(at(59.95), "0:59.9 0:00.1", "the last tenth reads 0:00.1, never 0:00.0 before the buzzer")
    assertEqual(at(60), "1:00.0 0:00.0", "the buzzer")
    assertEqual(at(61.3), "1:00.0 0:00.0", "held at the length")
    assertEqual(at(-1), "0:00.0 1:00.0")
    for _, e in ipairs({ 0.3, 7.7, 29.95, 44.44, 59.99 }) do
        local a, b = F.RaceClock(e, 60)
        assertTrue(math.abs(a + b - 60) < 1e-9, "they add up to the length at " .. e)
    end
end)

test("format: Seconds signs an offset, and RaceTime reads a race part's length, tail or early end", function()
    local F = T.NS.Format
    assertEqual(F.Seconds(3.14), "+3.1")
    assertEqual(F.Seconds(nil), "+0.0")
    assertEqual(F.RaceTime({ length = 120, status = "complete", tail = 11.12 }), "2:00 +11.1s")
    assertEqual(F.RaceTime({ length = 120, status = "complete", tail = 0.01 }), "2:00", "no tail worth a figure")
    assertEqual(F.RaceTime({ length = 120, status = "incomplete", endedAt = 64 }), "1:04 / 2:00")
    assertEqual(F.RaceTime(nil), "0:00")
end)
