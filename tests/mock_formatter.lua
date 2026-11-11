-- tests/mock_formatter.lua — the client's number formatters, scripted (plan v0.2 Task A5): the
-- C_StringUtil constructors modules/Format.lua tries in order, each building an instance that
-- applies the breakpoints it was given, and the global AbbreviateNumbers. A formatter reads the
-- plain value behind a secret wrapper (T.reveal), as the client does natively, and counts its calls.
--
-- Three behaviors, per constructor:
--   "floor"  truncates to the breakpoint's decimals, as the ladder's semantics promise
--   "raw"    the measured defect: an integer input truncates, a fractional one passes through
--            unfloored ("30.1904761904K"), which the fractional check must catch
--   "rule"   the numeric RULE formatter AuraMaster measured (12.1): breakpoints are
--            { threshold, format } and a value is written through the highest one's format; a
--            ladder (no format) is refused
-- `spec.userdata` = true hands each instance out as a userdata proxy, as a client object may be.
-- `spec.secretRaises` = true makes every instance raise on a secret, while it passes its plain checks.
--
-- Loaded as `local Formatter = dofile(T.root .. "/tests/mock_formatter.lua")(T)`.

return function(T)
    local F = {}

    local function decimalsFor(fractionDivisor)
        local d, n = 0, fractionDivisor or 1
        while n >= 10 do n, d = n / 10, d + 1 end
        return d
    end

    local function pick(list, n)
        local best
        for _, bp in ipairs(list or {}) do
            if n >= (bp.breakpoint or 0) and (best == nil or bp.breakpoint >= best.breakpoint) then best = bp end
        end
        return best
    end

    local function render(mode, bp, n)
        local scaled = n / ((bp.significandDivisor or 1) * (bp.fractionDivisor or 1))
        local d = decimalsFor(bp.fractionDivisor)
        if mode == "raw" and n ~= math.floor(n) then
            return ("%.10g"):format(scaled) .. (bp.abbreviation or "")
        end
        local factor = 10 ^ d
        return ("%." .. d .. "f"):format(math.floor(scaled * factor + 1e-9) / factor) .. (bp.abbreviation or "")
    end

    --- One formatter instance in `mode` ("floor" or "raw"); `seen` collects every value it was handed.
    local function pickRule(list, n)
        local best
        for _, bp in ipairs(list or {}) do
            if n >= (bp.threshold or 0) and (best == nil or bp.threshold >= best.threshold) then best = bp end
        end
        return best
    end

    function F.new(mode, name)
        local f = { mode = mode, name = name, calls = 0, seen = {} }
        function f:SetBreakpoints(list)
            if type(list) ~= "table" then error("SetBreakpoints wants an array", 2) end
            if self.mode == "rule" then
                for _, bp in ipairs(list) do
                    if type(bp.format) ~= "string" then error("a rule wants a format", 2) end
                end
            end
            self.breakpoints = list
        end
        function f:FormatNumber(v)
            self.calls = self.calls + 1
            self.seen[#self.seen + 1] = v
            if self.secretRaises and T.isSecret(v) then error("bad argument #1 to 'FormatNumber'", 2) end
            local n = T.reveal(v)
            if type(n) ~= "number" then return tostring(n) end
            if self.mode == "rule" then
                local rule = pickRule(self.breakpoints, n)
                return rule and rule.format:format(n) or tostring(n)
            end
            local bp = pick(self.breakpoints, n)
            if bp == nil then return tostring(n) end
            return render(self.mode, bp, n)
        end
        return f
    end

    --- Install the constructors on one mock build. `spec.abbreviated` / `spec.numeric` name each
    --- constructor's mode (absent = the client lacks it); `spec.abbreviate` = true also installs a
    --- global AbbreviateNumbers that records what it was handed and answers "abbr". The instances
    --- built land in m.__formatters, in build order; AbbreviateNumbers' arguments in m.__abbreviated.
    function F.install(m, spec)
        m.__formatters, m.__abbreviated = {}, {}
        local util = {}
        local function ctor(mode, name)
            return function()
                local f = F.new(mode, name)
                f.secretRaises = spec.secretRaises
                m.__formatters[#m.__formatters + 1] = f
                if spec.userdata then
                    local u = newproxy(true)
                    getmetatable(u).__index = function(_, k)
                        local v = f[k]
                        if type(v) ~= "function" then return v end
                        return function(_, ...) return v(f, ...) end
                    end
                    return u
                end
                return f
            end
        end
        if spec.abbreviated then util.CreateAbbreviatedNumberFormatter = ctor(spec.abbreviated, "abbreviated") end
        if spec.numeric then util.CreateNumericRuleFormatter = ctor(spec.numeric, "numeric") end
        m.C_StringUtil = util
        if spec.abbreviate then
            m.AbbreviateNumbers = function(v)
                m.__abbreviated[#m.__abbreviated + 1] = v
                return "abbr"
            end
        end
    end

    return F
end
