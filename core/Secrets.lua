local _, NS = ...
-- core/Secrets.lua — the ONLY file that inspects a value that may be secret (spec §3): the
-- secret guards (NS.Compat's, which core/Compat.lua routes through LibKa0s-Compat-1.0 with its stub
-- arm), plain-number conversion and the bounded array walk.
--
-- THE CONTRACT (WoW 12.0 secret values), measured by DPS Race's probe on Retail and assumed on WoW
-- Forever until `/ct probe` reports (spec §3): while the Combat addon restriction is active, meter
-- numbers, spell IDs, GUIDs and the isLocalPlayer flag arrive SECRET, and a value captured then STAYS
-- secret after combat. Tainted code may store one, pass it,
-- put it in a table VALUE, hand it to a widget setter or NumericRuleFormatter:FormatNumber, and
-- string.format it. It may NOT do arithmetic on it, compare it, truth-test a secret boolean, key a
-- table with it, apply `#` to it or index it. A NON-boolean secret may be tested for nil-ness, which
-- is the one operation SafeIterate leans on.
--
-- Everywhere else in the addon a meter value is an opaque handle. A module that needs to know
-- something about one asks this file; modules/Meter.lua asks on the read path, and nothing on the
-- live path asks at all.
--
-- DEGRADATION: every member is correct with the secrets system ABSENT (an older client, the headless
-- harness): nothing is secret, everything is accessible, iteration is plain ipairs semantics.
--
-- No perf brackets here: core/PerfSetup.lua loads after this file, and a per-value NS lookup is the
-- cost the perf contract forbids. Callers carry the brackets.
--
-- LOAD ORDER: binds NS.Compat's guards at FILE SCOPE, so core/Compat.lua loads first (the TOC says so).
-- This file names no client global: the detectors and their ladders live in the compat family.

local Secrets = {}
NS.Secrets = Secrets
local Compat = NS.Compat

-- ---------------------------------------------------------------------------
-- The three guards: NS.Compat's (LibKa0s-Compat-1.0's, or core/Compat.lua's stub arm)
-- ---------------------------------------------------------------------------

--- Whether `v` is a secret value. False on a client without the secrets system.
--- @param v any
--- @return boolean
Secrets.IsSecret = Compat.IsSecret

--- Whether this context may look at `v`: the question that decides whether arithmetic or a
--- comparison on it is legal. A plain value always answers true.
--- @param v any
--- @return boolean
Secrets.CanAccess = Compat.CanAccess

--- Whether `v` may be a table KEY right now (not secret, not nil).
--- @param v any
--- @return boolean
Secrets.IsSafeKey = Compat.IsSafeKey

-- ---------------------------------------------------------------------------
-- Value conversion
-- ---------------------------------------------------------------------------

--- Whether `v` is present but may not be looked at: secret, or inaccessible to this context. nil is
--- absent, not sealed. modules/Meter.lua asks this to tell "the session is still sealed" apart from
--- "the field is missing".
--- @param v any
--- @return boolean
function Secrets.IsSealed(v)
    if Secrets.IsSecret(v) then return true end
    return not Secrets.CanAccess(v)
end

--- Whether `v` is there at all, secret or plain, without comparing it: a secret is present (the test
--- runs first, so a secret meets nothing else), and anything else answers type(). What a caller asks
--- of a client answer that may itself be secret, such as a formatter's secret string (modules/Format.lua).
--- @param v any
--- @return boolean
function Secrets.IsPresent(v)
    if Secrets.IsSecret(v) then return true end
    return type(v) ~= "nil"
end

--- `v` as a plain Lua number, or nil when it is nil, secret, inaccessible or not a number. The
--- secret test runs FIRST, so a secret never meets type() on a client where type() answers its
--- underlying type.
--- @param v any
--- @return number|nil
function Secrets.PlainNumber(v)
    if Secrets.IsSealed(v) then return nil end
    if type(v) ~= "number" then return nil end
    return v
end

--- `v` as a plain Lua string, or nil when it is nil, secret, inaccessible or not a string. What a
--- metadata snapshot stores: a unit's name or GUID read in combat may be secret, and a secret must
--- never reach SavedVariables (modules/Recorder.lua).
--- @param v any
--- @return string|nil
function Secrets.PlainString(v)
    if Secrets.IsSealed(v) then return nil end
    if type(v) ~= "string" then return nil end
    return v
end

--- True only when `v` is accessible and truthy. `if src.isLocalPlayer then` raises on a secret
--- boolean; an inaccessible flag reads as "no claim" (false), the safe answer for every caller.
--- @param v any
--- @return boolean
function Secrets.PlainTruth(v)
    if Secrets.IsSealed(v) then return false end
    return v and true or false
end

--- True only when both operands are accessible and equal. One sealed operand answers false without
--- the comparison ever running.
--- @param a any
--- @param b any
--- @return boolean
function Secrets.PlainEquals(a, b)
    if Secrets.IsSealed(a) or Secrets.IsSealed(b) then return false end
    return a == b
end

--- Whether a meter spell row's `creatureName` PLAINLY names a creature: the folded source's mark of a
--- pet's row (WoW Forever puts the pet's spells, its melee too, in its owner's source). The owner's
--- own rows carry "" there, not nil (`/ct probe`, 2026-11-11), so a sealed name says nothing: it
--- may be "" and cannot be compared. Only a plain, non-empty name counts; nil, "" and a secret do not.
--- @param v any
--- @return boolean
function Secrets.NamesCreature(v)
    if Secrets.IsSealed(v) then return false end
    return type(v) == "string" and v ~= ""
end

-- ---------------------------------------------------------------------------
-- Table inspection
-- ---------------------------------------------------------------------------

--- Whether this context may read the CONTENTS of `t`. A non-table answers false. Without the client
--- globals every table is readable.
--- @param t any
--- @return boolean
function Secrets.CanAccessTable(t)
    if type(t) ~= "table" then return false end
    return Compat.CanAccessTable(t)
end

-- Hard ceiling on one walk. `#` is forbidden on a secret and a table dense past any sane length would
-- spin the client; 512 is far beyond any real spell list or session list.
local ITERATION_LIMIT = 512
Secrets.ITERATION_LIMIT = ITERATION_LIMIT

--- Walk a possibly-secret array, calling `fn(i, e)` per entry; `fn` may return false to stop.
---
--- Never applies `#` and never uses ipairs; refuses an inaccessible table (answers 0); stops at the
--- first nil (a nil-ness test, the one operation legal on a non-boolean secret); bounded at 512;
--- never inspects the entry it hands to `fn`.
--- @param arr table|nil
--- @param fn function
--- @return number count  how many entries were visited
function Secrets.SafeIterate(arr, fn)
    if type(fn) ~= "function" or not Secrets.CanAccessTable(arr) then return 0 end
    local count = 0
    for i = 1, ITERATION_LIMIT do
        local e = arr[i]
        if e == nil then break end
        count = i
        if fn(i, e) == false then break end
    end
    return count
end
