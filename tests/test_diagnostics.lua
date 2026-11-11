-- tests/test_diagnostics.lua — this addon's sections of `/ct diagnostics` (debug-logging-§14, plan
-- Task 5.2; modules/Diagnostics.lua). The dispatcher half (the two forms, the markers, the append,
-- the logging edge) is the kit's contract suite; this file holds what only Combat Trail writes: the
-- schema and store line, the settings that differ from their defaults, the lanes, the fight, the
-- HUD, the Results window and the preview, and the stood-down answer. The report reads, never acts.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local BEGIN = "[Diag] ==== Ka0s Combat Trail diagnostics begin ===="

--- Run the report on `inst` and answer its lines (from the begin marker on).
local function report(inst)
    local D = inst.NS.DebugLog
    local from = #D.buffer + 1
    inst.NS.Slash:OnSlash("diagnostics")
    local out, on = {}, false
    for i = from, #D.buffer do
        local line = D.buffer[i]
        if line:find(BEGIN, 1, true) then on = true end
        if on then out[#out + 1] = line end
    end
    return out
end

local function has(lines, needle)
    for _, l in ipairs(lines) do
        if l:find(needle, 1, true) then return true end
    end
    return false
end

local function dump(lines) return table.concat(lines, "\n") end

test("diagnostics: the report carries every section of this addon's own", function()
    local inst = T.load()
    local lines = report(inst)
    assertTrue(#lines > 0, "no report landed")
    for _, needle in ipairs({
        "schema stored=2 code=2 fightFormat=3", "profile=", "fights stored=0",
        "lanes player=on pet=on", "cast events=", "fight state=idle",
        "hud state=", "results shown=false", "test active=false mode=none",
    }) do
        assertTrue(has(lines, needle), "missing '" .. needle .. "' in:\n" .. dump(lines))
    end
    assertFalse(has(lines, "section "), "a section raised:\n" .. dump(lines))
end)

test("diagnostics: a setting off its default is listed with its default", function()
    local inst = T.load()
    inst.NS.SetByPath("hud.width", 360)
    local lines = report(inst)
    assertTrue(has(lines, "hud.width = 360 (260)"), dump(lines))
end)

test("diagnostics: test mode shows in the preview line", function()
    local inst = T.load()
    inst.NS.Preview.Start({ mode = "test" })
    local lines = report(inst)
    assertTrue(has(lines, "test active=true mode=test"), dump(lines))
    inst.NS.Preview.Stop()
end)

test("diagnostics: stood down, the runtime sections say so and the stored ones still print", function()
    local inst = T.load()
    inst.NS.SetByPath("hud.width", 360)
    inst.NS.Slash:OnSlash("disable")
    local lines = report(inst)
    assertTrue(has(lines, "stood down: runtime state released"), dump(lines))
    assertTrue(has(lines, "hud.width = 360 (260)"), "the settings still print:\n" .. dump(lines))
    assertTrue(has(lines, "fights stored=0"), "the store still prints:\n" .. dump(lines))
    assertFalse(has(lines, "fight state="), "no runtime fight line while stood down:\n" .. dump(lines))
end)

test("diagnostics: the report arms no timer and registers no event", function()
    local inst = T.load()
    local M = inst.mocks
    local timers = #M.__timers
    local regs = #M.__registrations()
    report(inst)
    assertEqual(#M.__timers, timers, "the report armed a timer")
    assertEqual(#M.__registrations(), regs, "the report registered an event")
end)

test("diagnostics: a rejected event is listed", function()
    local inst = T.load()
    inst.NS.rejectedEvents[#inst.NS.rejectedEvents + 1] = "NOT_A_REAL_EVENT"
    local lines = report(inst)
    assertTrue(has(lines, "NOT_A_REAL_EVENT"), dump(lines))
end)
