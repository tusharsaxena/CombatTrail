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
        "schema stored=3 code=3 fightFormat=4", "profile=", "fights stored=0",
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

test("diagnostics: Retail's race section names the race, the pending races, the boards and its windows", function()
    local inst = T.load()
    local lines = report(inst)
    assertTrue(has(lines, "toast shown=false waiting=0"), "the toast's line, on both clients:\n" .. dump(lines))
    if inst.NS.Compat.IsForever() then
        assertFalse(has(lines, "race state="), "no race section on WoW Forever:\n" .. dump(lines))
        assertFalse(has(lines, "race window "), dump(lines))
        return
    end
    for _, needle in ipairs({ "race state=idle mode=on", "pending=0 boards=0", "race window shown=false",
                              "countdown shown=none scheduled=0 owner=none", "race sample=false" }) do
        assertTrue(has(lines, needle), "missing '" .. needle .. "' in:\n" .. dump(lines))
    end
    -- After the fight's section, before the windows'.
    local fightAt, raceAt, windowsAt
    for i, l in ipairs(lines) do
        if l:find("fight state=", 1, true) then fightAt = i end
        if l:find("race state=", 1, true) then raceAt = i end
        if l:find("hud state=", 1, true) then windowsAt = i end
    end
    assertTrue(fightAt < raceAt and raceAt < windowsAt, dump(lines))
end)

test("diagnostics: the race line counts a real race's pending slot while it runs, then its race board", function()
    if T.NS.Compat.IsForever() then return end
    local F = dofile(T.root .. "/tests/race_fixture.lua")(T)
    local S = F.fresh()
    F.arm(S, 30)
    local start = F.pull(S)
    F.damage(S, 25, start + 1, start + 5, 1)
    local f = S.NS.Race.Fight()
    local lines = report(S.inst)
    local want = ("race state=running mode=on fight=%s session=25 pending=1 boards=0"):format(tostring(f.id))
    assertTrue(has(lines, want), "missing '" .. want .. "' in:\n" .. dump(lines))
    F.damage(S, 25, start + 6, start + 30, 1)
    F.settle(S, start + 31)
    assertEqual(S.NS.Race.State(), "result", "the race was read")
    lines = report(S.inst)
    assertTrue(has(lines, "pending=0 boards=1"), "the race's board, its slot cleared:\n" .. dump(lines))
    -- A fight's board is no race board.
    assertEqual(#S.NS.Recorder.List(), 1)
end)

test("diagnostics: test mode's held sample race shows in the preview and race lines", function()
    local inst = T.load()
    if inst.NS.Compat.IsForever() then return end
    assertTrue(inst.NS.Preview.TestRace("result"))
    local lines = report(inst)
    assertTrue(has(lines, "phase=race result"), dump(lines))
    assertTrue(has(lines, "race sample=true state=result live=false"), dump(lines))
    assertTrue(has(lines, "race state=idle"), "the real race stays idle:\n" .. dump(lines))
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
