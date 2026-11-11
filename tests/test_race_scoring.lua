-- tests/test_race_scoring.lua — modules/RaceScoring.lua and modules/RaceTimeline.lua (Race mode plan Task
-- B1): DPS Race's scoring and timeline suites (its tests/test_scoring.lua and tests/test_timeline.lua
-- @f8078c7) on the race part. The late-cast rule, the race DPS from the race clock, the Stop! quiet,
-- a race's flags in display order with their words, the late casts split by the ignore list; and the
-- timeline's tail after the buzzer, the damage-restarted check and a gap that spans a /reload's
-- resume. Pure: both kit profiles (a saved race re-scores on WoW Forever too).

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil, assertNear =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil, T.assertNear

-- A race part as a saved race carries it.
local function race(status, fields)
    local r = { status = status, length = 180, grace = 1.0, restartGap = 6,
                flags = { lateCasts = {}, reloaded = false, died = false } }
    for k, v in pairs(fields or {}) do r[k] = v end
    return r
end

-- ── scoring ────────────────────────────────────────────────────────────────────────────────────

test("race scoring: late cast boundaries", function()
    local S = T.NS.RaceScoring
    assertFalse(S.IsLateCast(1.0, 1.0), "exactly buzzer + grace is not late")
    assertTrue(S.IsLateCast(1.01, 1.0), "past buzzer + grace is late")
    assertFalse(S.IsLateCast(-0.2, 1.0), "started before the buzzer, finished after: never late")
    assertFalse(S.IsLateCast(0.5, 1.0))
    assertTrue(S.IsLateCast(1.4, 1.0))
    -- An instant has no START event: it is scored by its SUCCEEDED offset, through the same rule.
    assertTrue(S.IsLateCast(1.3, 1.0))
    assertFalse(S.IsLateCast(0.9, 1.0))
    -- Grace 0: anything after the buzzer is late; the buzzer itself is not.
    assertFalse(S.IsLateCast(0, 0))
    assertTrue(S.IsLateCast(0.01, 0))
    assertFalse(S.IsLateCast(nil, 1.0), "no offset is never late")
end)

test("race scoring: QUIET_BEFORE_READ is 2.5s", function()
    assertEqual(T.NS.RaceScoring.QUIET_BEFORE_READ, 2.5)
end)

test("race scoring: Dps complete = score / length", function()
    local S = T.NS.RaceScoring
    -- DPS Race's probe run 8: 1539711 over a 30 s race.
    local r = race("complete", { length = 30 })
    assertNear(S.Dps(1539711, r), 51323.7, 0.05)
    r.endedAt = 7
    assertNear(S.Dps(1539711, r), 51323.7, 0.05, "a complete race ignores endedAt")
end)

test("race scoring: Dps incomplete = score / endedAt", function()
    local S = T.NS.RaceScoring
    assertNear(S.Dps(1000000, race("incomplete", { endedAt = 40 })), 25000, 1e-6)
    assertEqual(S.Dps(1000000, race("incomplete")), 0, "no endedAt yet: 0, not a divide by zero")
    assertEqual(S.Dps(1000000, race("incomplete", { endedAt = 0 })), 0)
    assertEqual(S.Dps(nil, race("complete")), 0, "no score: 0")
end)

test("race scoring: Flags order and text", function()
    local S, L = T.NS.RaceScoring, T.NS.L
    local r = race("incomplete", {
        endedAt = 12.5,
        flags = {
            lateCasts = { { t = 1.4, spellID = 29722 }, { t = 2.0, spellID = 17962 } },
            restartedAt = 14.2, reloaded = true, sessionFromList = true, sharedSession = true, died = true,
        },
    })
    local f = S.Flags(r)
    local want = { "lateCasts", "restarted", "reloaded", "sessionFromList", "sharedSession", "died", "incomplete" }
    assertEqual(#f, #want)
    for i, key in ipairs(want) do assertEqual(f[i].key, key) end
    assertEqual(f[1].text, "2 late casts (+1.4s, +2.0s)")
    assertEqual(f[1].main, "2 late casts")
    assertEqual(f[1].sub, "+1.4s, +2.0s")
    assertEqual(f[2].text, "Damage restarted at +14.2s")
    assertEqual(f[3].text, "Reloaded mid-race: casts after the buzzer not tracked")
    assertEqual(f[4].text, "Session matched by list")
    assertEqual(f[5].text, "Shared session: the pull carried on a meter session from before the arm")
    assertEqual(f[6].text, "Died during the race")
    assertEqual(f[7].text, "Incomplete: combat ended before the buzzer")
    for _, flag in ipairs(f) do assertTrue(type(flag.text) == "string" and flag.text ~= "") end
    assertEqual(L["Damage restarted at +%.1fs"], "Damage restarted at +%.1fs", "the text is a locale key")
end)

test("race scoring: Flags names late-cast spells through an optional resolver", function()
    local S = T.NS.RaceScoring
    local names = { [29722] = "Incinerate", [17962] = "Conflagrate" }
    local r = race("complete", { flags = {
        lateCasts = { { t = 1.4, spellID = 29722 }, { t = 2.0, spellID = 17962 }, { t = 2.6 } },
    } })
    local f = S.Flags(r, function(id) return names[id] end)
    assertEqual(f[1].text, "3 late casts (+1.4s Incinerate, +2.0s Conflagrate, +2.6s)")
    r.flags.lateCasts = { { t = 1.4, spellID = 29722 } }
    assertEqual(S.Flags(r, function() error("resolver raised") end)[1].text, "1 late cast (+1.4s)",
        "a raising resolver costs the name, never the flag")
end)

test("race scoring: SplitLate keeps the recorded order and splits by the ignore set; a sealed cast always counts", function()
    local S = T.NS.RaceScoring
    local r = race("complete", { flags = {
        lateCasts = { { t = 1.2, spellID = 5384 }, { t = 1.4, spellID = 29722 }, { t = 2.0 }, { t = 2.5, spellID = 1856 } },
    } })
    local function ids(list)
        local out = {}
        for i, c in ipairs(list) do out[i] = tostring(c.spellID) .. "@" .. c.t end
        return table.concat(out, ",")
    end
    local counted, ignored = S.SplitLate(r, { [5384] = true, [1856] = true })
    assertEqual(ids(counted), "29722@1.4,nil@2")
    assertEqual(ids(ignored), "5384@1.2,1856@2.5")
    counted, ignored = S.SplitLate(r, {})
    assertEqual(#counted, 4, "none ignored")
    assertEqual(#ignored, 0)
    counted, ignored = S.SplitLate(r)
    assertEqual(ids(counted), "29722@1.4,nil@2", "no set: the stored list (Feign Death and Vanish by default)")
    assertEqual(#ignored, 2)
    assertEqual(#S.SplitLate({}), 0, "no flags table")
    assertEqual(#S.SplitLate(nil), 0, "no race")
end)

test("race scoring: Flags flags only the counted late casts and carries the count, the casts and the ignored", function()
    local S = T.NS.RaceScoring
    local r = race("complete", { flags = {
        lateCasts = { { t = 1.2, spellID = 5384 }, { t = 1.4, spellID = 29722 }, { t = 2.0, spellID = 17962 } },
    } })
    local f = S.Flags(r, nil, { [5384] = true })
    assertEqual(f[1].key, "lateCasts")
    assertEqual(f[1].count, 2)
    assertEqual(f[1].text, "2 late casts (+1.4s, +2.0s)")
    assertEqual(f[1].casts[1].spellID, 29722)
    assertEqual(f[1].ignored[1].spellID, 5384)
    assertEqual(#S.Flags(r, nil, { [5384] = true, [29722] = true, [17962] = true }), 0, "all ignored: clean")
    assertEqual(S.Flags(r, nil, {})[1].count, 3, "none ignored")
    assertEqual(S.Flags(r)[1].count, 2, "no set: Feign Death is on the default list")
end)

test("race scoring: IgnoredText names the ignored casts in one line, nil with none", function()
    local S = T.NS.RaceScoring
    local r = race("complete", { flags = { lateCasts = { { t = 20.6, spellID = 5384 }, { t = 3.0, spellID = 1856 } } } })
    local names = { [5384] = "Feign Death", [1856] = "Vanish" }
    assertEqual(S.IgnoredText(r, function(id) return names[id] end), "Ignored: +20.6s Feign Death, +3.0s Vanish")
    assertNil(S.IgnoredText(r, nil, {}), "nothing ignored")
    assertNil(S.IgnoredText(race("complete")))
end)

test("race scoring: a clean complete race has no flags; lost stands alone at the end", function()
    local S = T.NS.RaceScoring
    assertEqual(#S.Flags(race("complete")), 0)
    local lost = race("lost", { flags = { lateCasts = {}, reloaded = true } })
    local f = S.Flags(lost)
    assertEqual(#f, 2)
    assertEqual(f[1].key, "reloaded")
    assertEqual(f[2].key, "lost")
    assertEqual(f[2].text, "Lost: the fight could not be read")
    assertEqual(#S.Flags({}), 0, "a race with no flags table at all is clean")
end)

-- ── the timeline ───────────────────────────────────────────────────────────────────────────────

-- An arbitrary GetTime() for the buzzer; every fixture is written as offsets from it.
local BUZZER = 1000.0

local function timeline(offsets)
    local tl = T.NS.RaceTimeline.New()
    for _, o in ipairs(offsets) do tl:AddDamage(BUZZER + o) end
    return tl
end

-- DPS Race's probe run 4 (2026-10-23): no DoTs, damage stopped about 3s after the buzzer.
local RUN4 = { -2.09, 0.45, 1.04, 1.35, 2.47, 3.03 }
-- Probe run 6: DoT ticks about every 2s, the last at +8.49.
local RUN6 = { -5.51, -3.50, -1.52, 0.49, 2.50, 4.51, 6.49, 8.49 }

test("race timeline: tail from probe run 4 = 3.03", function()
    local tl = timeline(RUN4)
    assertNear(tl:Tail(BUZZER), 3.03, 1e-6)
    assertNil(tl:RestartAt(BUZZER, 6), "no restart in run 4")
    assertNear(tl:LastDamage(), BUZZER + 3.03, 1e-6)
end)

test("race timeline: tail from probe run 6 = 8.49", function()
    local tl = timeline(RUN6)
    assertNear(tl:Tail(BUZZER), 8.49, 1e-6)
    assertNil(tl:RestartAt(BUZZER, 6), "no restart at gap 6")
end)

test("race timeline: restart detected after 10s quiet at gap 6", function()
    local tl = timeline({ -1.0, 0.5, 2.0, 12.0, 13.1 })
    assertNear(tl:RestartAt(BUZZER, 6), 12.0, 1e-6, "the first update after the quiet stretch")
    assertNear(tl:Tail(BUZZER), 13.1, 1e-6)
end)

test("race timeline: DoT ticks every 2s are not a restart", function()
    local offsets = {}
    for i = 0, 15 do offsets[#offsets + 1] = -4 + i * 2 end   -- -4 .. +26, every 2s
    local tl = timeline(offsets)
    assertNil(tl:RestartAt(BUZZER, 3), "2s spacing never reaches the 3s minimum gap")
    assertNear(tl:Tail(BUZZER), 26, 1e-6)
end)

test("race timeline: the quiet stretch starts at the buzzer when the last damage was before it", function()
    local tl = timeline({ -3.0, 7.0 })
    assertNear(tl:RestartAt(BUZZER, 6), 7.0, 1e-6, "7s from the buzzer is quiet enough")
    tl = timeline({ -3.0, 5.0 })
    assertNil(tl:RestartAt(BUZZER, 6), "5s from the buzzer is not, however long before it")
end)

test("race timeline: a gap of exactly the setting counts as a restart", function()
    local tl = timeline({ 1.0, 7.0 })
    assertNear(tl:RestartAt(BUZZER, 6), 7.0, 1e-6)
end)

test("race timeline: no damage after the buzzer gives tail 0 and no restart", function()
    local tl = timeline({ -9.0, -4.0, -0.5 })
    assertEqual(tl:Tail(BUZZER), 0)
    assertNil(tl:RestartAt(BUZZER, 6))
    local empty = T.NS.RaceTimeline.New()
    assertEqual(empty:Tail(BUZZER), 0)
    assertNil(empty:RestartAt(BUZZER, 6))
    assertNil(empty:LastDamage())
end)

test("race timeline: a gap that spans a resume is measured from the resume", function()
    local tl = timeline({ 1.0, 8.2, 9.0 })     -- a /reload from 1.0 to a resume at 8.0
    assertNil(tl:RestartAt(BUZZER, 6, BUZZER + 8), "the loading screen is not a stop in the damage")
    assertNear(tl:RestartAt(BUZZER, 6), 8.2, 1e-6, "without the resume it is a restart")
    local real = timeline({ 1.0, 9.5 })        -- resumed at 2.0, quiet 7.5s after it: a restart
    assertNear(real:RestartAt(BUZZER, 6, BUZZER + 2), 9.5, 1e-6)
end)

test("race timeline: an out-of-order or non-number update is handled", function()
    local tl = T.NS.RaceTimeline.New()
    tl:AddDamage(BUZZER + 2)
    tl:AddDamage(BUZZER + 1)        -- arrives late: the last damage stays +2
    tl:AddDamage(nil)
    tl:AddDamage("soon")
    assertNear(tl:LastDamage(), BUZZER + 2, 1e-6)
    assertNear(tl:Tail(BUZZER), 2, 1e-6)
end)

test("race timeline: two timelines are independent", function()
    local a, b = T.NS.RaceTimeline.New(), T.NS.RaceTimeline.New()
    a:AddDamage(BUZZER)
    assertNil(b:LastDamage())
    assertTrue(a:LastDamage() ~= nil)
end)
