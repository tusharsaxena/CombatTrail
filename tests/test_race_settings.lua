-- tests/test_race_settings.lua — Race mode's switch and its surfaces (Race mode plan Task B3): the Race
-- mode page (Retail only: the switch, the Race tab's rows, the late-cast ignore list, the Race window's
-- attach rows), NS.RaceMode.On(), the `/ct race` verb (arm with a typed length, cancel, show, hide,
-- toggle, the late-cast ignore list's words) on the live and the library-absent dispatcher, its
-- liveness (ruling X10), the late-cast list's writes through its row, and Race mode off. Every surface
-- has a present case on the Retail kit profile and an absent case on WoW Forever (clients-§4, §6).

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local F = dofile(T.root .. "/tests/race_fixture.lua")(T)

local function forever() return T.NS.Compat.IsForever() end

local function text(M) return table.concat(M.__printed(), "\n") end

local function said(M, needle)
    return text(M):find(needle, 1, true) ~= nil
end

-- The Race mode page's stored rows: path, type, default, and (numbers) min, max, step.
local ROWS = {
    { "race.enabled",         "bool",   true },
    { "race.defaultLength",   "number", 60 },
    { "race.autoShow",        "bool",   true },
    { "race.autoArm",         "bool",   false },
    { "race.clock",           "string", "both" },
    { "race.countdownCue",    "bool",   true },
    { "race.centerCountdown", "bool",   true },
    { "race.finalCountdown",  "number", 10, 3, 10, 1 },
    { "race.buzzer",          "bool",   true },
    { "race.hintDelay",       "number", 15, 5, 60, 1 },
    { "race.grace",           "number", 1.0, 0, 5, 0.1 },
    { "race.restartGap",      "number", 6, 3, 15, 1 },
    { "race.lateIgnore",      "string", "66,1856,5384,8690,58984,110959" },
    { "raceWindow.attached",  "bool",   true },
    { "raceWindow.side",      "string", "RIGHT" },
}

local function pageKeys(NS)
    local out = {}
    for _, ctx in ipairs(NS.Helpers.__pages()) do out[#out + 1] = ctx.pageKey or ctx.key end
    return table.concat(out, ",")
end

-- ── per client ──────────────────────────────────────────────────────────────────────────────────

test("race mode: the page, its rows and the verb are present on Retail, each declared retail", function()
    if forever() then return end
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    assertEqual(pageKeys(NS), "general,lanes,hud,history,race,profiles")
    assertTrue(M.__subcategories["Race mode"] ~= nil, "the Race mode page is registered")
    for _, r in ipairs(ROWS) do
        local row = NS.FindSchemaRow(r[1])
        assertTrue(row ~= nil, r[1] .. " has a row")
        assertEqual(row.page, "race", r[1])
        assertEqual(table.concat(row.clients or {}, ","), "retail", r[1] .. " is declared retail")
    end
    local entry
    for _, e in ipairs(NS.COMMANDS) do if e[1] == "race" then entry = e end end
    assertTrue(entry ~= nil, "the race verb")
    assertEqual(table.concat(entry.clients or {}, ","), "retail")
    M.__resetPrinted()
    NS.Slash:OnSlash("help")
    assertTrue(said(M, "/ct race"), "help names the race verb")
    assertTrue(NS.RaceMode.On(), "Race mode is on by default")
end)

test("race mode: every control and verb is absent on WoW Forever", function()
    if not forever() then return end
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    assertEqual(pageKeys(NS), "general,lanes,hud,history,profiles")
    assertNil(M.__subcategories["Race mode"], "no Race mode page")
    for _, r in ipairs(ROWS) do assertNil(NS.FindSchemaRow(r[1]), r[1] .. " on WoW Forever") end
    for _, row in ipairs(NS.Schema) do
        assertFalse(tostring(row.path):find("^race") ~= nil, tostring(row.path) .. " on WoW Forever")
    end
    local D = NS.defaults.profile
    for _, key in ipairs({ "enabled", "autoShow", "autoArm", "clock", "countdownCue", "centerCountdown",
                           "finalCountdown", "buzzer" }) do
        assertNil(D.race[key], "race." .. key .. " is stored on WoW Forever")
    end
    assertNil(D.raceWindow, "raceWindow is stored on WoW Forever")
    M.__resetPrinted()
    NS.Slash:OnSlash("help")
    assertFalse(said(M, "/ct race"), "help names the race verb")
    M.__resetPrinted()
    NS.Slash:OnSlash("race arm")
    assertTrue(said(M, "unknown command 'race'"), text(M))
    assertFalse(NS.RaceMode.On())
end)

test("race mode: the library-absent dispatcher lists and runs the verb on its own client only", function()
    local inst = T.load{ libFiles = {} }
    local NS, M = inst.NS, inst.mocks
    M.__resetPrinted()
    NS.Slash:OnSlash("help")
    assertEqual(said(M, "/ct race"), not forever(), "the reduced help and the race verb")
    local landing = table.concat(NS.Slash:LandingRows(), "\n")
    assertEqual(landing:find("/ct race", 1, true) ~= nil, not forever(), "the landing rows")
    M.__resetPrinted()
    NS.RunVerb("race", "frob")
    if forever() then
        assertEqual(#M.__printed(), 0, "RunVerb ran the race verb on WoW Forever")
    else
        assertTrue(said(M, "Usage: /ct race"), text(M))
    end
end)

-- ── the page ────────────────────────────────────────────────────────────────────────────────────

test("race mode: the stored paths, types, defaults and ranges are the pinned set", function()
    if forever() then return end
    local NS = T.load().NS
    assertEqual(#NS.SchemaForPage("race"), #ROWS, "the page's row count")
    for _, r in ipairs(ROWS) do
        local row = NS.FindSchemaRow(r[1])
        assertEqual(row.type, r[2], r[1] .. " type")
        assertEqual(row.default, r[3], r[1] .. " default")
        assertEqual(NS.GetSetting(r[1]), r[3], r[1] .. " reads its default")
        if r[4] then
            assertEqual(row.min, r[4], r[1] .. " min")
            assertEqual(row.max, r[5], r[1] .. " max")
            assertEqual(row.step, r[6], r[1] .. " step")
        end
    end
    local values = {}
    for _, v in ipairs(NS.FindSchemaRow("race.defaultLength").values) do values[#values + 1] = v.value end
    assertEqual(table.concat(values, ","), "30,60,120,180,300")
    assertTrue(NS.FindSchemaRow("race.lateIgnore").skipRender, "the list is the tab's body")
    assertFalse(NS.SetByPath("race.clock", "never"), "a clock mode that is none")
    assertFalse(NS.SetByPath("raceWindow.side", "MIDDLE"), "a side that is none")
    assertFalse(NS.SetByPath("race.grace", 6), "grace past 5")
    assertTrue(NS.SetByPath("raceWindow.side", "LEFT"))
end)

test("race mode: the page's tabs are Race, Late-cast ignore list and Race window, and it renders quietly", function()
    if forever() then return end
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    M.__resetPrinted()
    M.__subcategories["Race mode"]:__fire("OnShow")
    assertEqual(#M.__printed(), 0, "the render printed: " .. text(M))
    local ctx = NS.pageCtx.race
    assertTrue(ctx ~= nil, "the page's ctx")
    local _, keys = NS.Helpers.RenderTabbedSchema(ctx, "race", nil, nil, {})
    assertEqual(table.concat(keys or {}, ","), "Race,Late-cast ignore list,Race window")
    -- The switch is the Race tab's first row.
    assertEqual(NS.SchemaForPage("race")[1].path, "race.enabled")
end)

test("race mode: a new default length forgets the last one armed", function()
    if forever() then return end
    local NS = T.load().NS
    NS.db.profile.race.lastLength = 300
    assertEqual(NS.Race.DefaultLength(), 300)
    assertTrue(NS.SetByPath("race.defaultLength", 120))
    assertNil(NS.db.profile.race.lastLength)
    assertEqual(NS.Race.DefaultLength(), 120)
end)

test("race mode: the page's Defaults brings every race row back, the ignore list too", function()
    if forever() then return end
    local inst = T.load()
    local NS = inst.NS
    assertTrue(NS.SetByPath("race.enabled", false))
    assertTrue(NS.SetByPath("race.grace", 2.5))
    assertTrue(NS.SetByPath("race.lateIgnore", "5384"))
    assertTrue(NS.SetByPath("raceWindow.attached", false))
    inst.mocks.__subcategories["Race mode"]:__fire("OnShow")
    NS.Helpers.RestoreDefaults("race", NS.pageCtx.race)
    assertTrue(NS.GetSetting("race.enabled"))
    assertEqual(NS.GetSetting("race.grace"), 1.0)
    assertEqual(NS.GetSetting("race.lateIgnore"), "66,1856,5384,8690,58984,110959")
    assertTrue(NS.GetSetting("raceWindow.attached"))
end)

-- ── the late-cast ignore list's writes (modules/LateIgnore.lua, through its row) ────────────────

test("race mode: Ignore, Unignore and Reset write the late-cast list through its row", function()
    if forever() then return end
    local NS = T.load().NS
    local LI = NS.LateIgnore
    assertTrue(LI.Ignore(29722))
    assertEqual(NS.GetSetting("race.lateIgnore"), "66,1856,5384,8690,29722,58984,110959")
    assertFalse(LI.Ignore(29722), "already ignored")
    assertTrue(LI.Unignore(5384))
    assertEqual(NS.GetSetting("race.lateIgnore"), "66,1856,8690,29722,58984,110959")
    assertTrue(LI.Unignore(401802), "a variant ignored through 8690 takes 8690 off")
    assertEqual(NS.GetSetting("race.lateIgnore"), "66,1856,29722,58984,110959")
    assertTrue(LI.Reset())
    assertEqual(NS.GetSetting("race.lateIgnore"), "66,1856,5384,8690,58984,110959")
    assertFalse(NS.SetByPath("race.lateIgnore", "abc"), "a list that does not parse")
    assertTrue(NS.SetByPath("race.lateIgnore", " 8690, 66 ,66"))
    assertEqual(NS.GetSetting("race.lateIgnore"), "66,8690", "normalized as it is stored")
end)

-- ── `/ct race` ──────────────────────────────────────────────────────────────────────────────────

test("race verb: arm takes 90, 1:30 and 3m, and refuses 0 and 901 with one line", function()
    if forever() then return end
    for _, case in ipairs({ { "90", 90 }, { "1:30", 90 }, { "3m", 180 }, { "1m30s", 90 }, { "45s", 45 } }) do
        local S = F.fresh()
        S.NS.Slash:OnSlash("race arm " .. case[1])
        assertEqual(S.NS.Race.State(), "armed", case[1])
        assertEqual(S.NS.Race.Current().length, case[2], case[1])
    end
    for _, typed in ipairs({ "0", "901", "9", "soon", "1:75" }) do
        local S = F.fresh()
        S.M.__resetPrinted()
        S.NS.Slash:OnSlash("race arm " .. typed)
        assertEqual(S.NS.Race.State(), "idle", typed)
        assertEqual(#S.M.__printed(), 1, typed .. ": " .. text(S.M))
        assertTrue(said(S.M, "A race lasts from 0:10 to 15:00."), typed .. ": " .. text(S.M))
    end
end)

test("race verb: a bare arm takes the remembered length, and a refusal says why", function()
    if forever() then return end
    local S = F.fresh()
    S.NS.db.profile.race.lastLength = 120
    S.NS.Slash:OnSlash("race arm")
    assertEqual(S.NS.Race.Current().length, 120)
    S.M.__resetPrinted()
    S.NS.Slash:OnSlash("race arm")
    assertTrue(said(S.M, "A race is already armed or running."), text(S.M))
    local G = F.fresh()
    G.M.__inCombat = true
    G.M.__resetPrinted()
    G.NS.Slash:OnSlash("race arm 60")
    assertTrue(said(G.M, "Leave combat to arm a race."), text(G.M))
    local H = F.fresh()
    H.meter.SetAvailable(false, "Not in this zone")
    H.M.__resetPrinted()
    H.NS.Slash:OnSlash("race arm 60")
    assertTrue(said(H.M, "Not in this zone"), text(H.M))
end)

test("race verb: cancel says what it did in the state it found", function()
    if forever() then return end
    local S = F.fresh()
    S.M.__resetPrinted()
    S.NS.Slash:OnSlash("race cancel")
    assertTrue(said(S.M, "Nothing to cancel."), text(S.M))
    assert(F.arm(S, 30))
    S.M.__resetPrinted()
    S.NS.Slash:OnSlash("race cancel")
    assertTrue(said(S.M, "Race canceled."), text(S.M))
    assertEqual(S.NS.Race.State(), "idle")
    assert(F.arm(S, 30))
    F.pull(S)
    S.M.__resetPrinted()
    S.NS.Slash:OnSlash("race cancel")
    assertTrue(said(S.M, "Race canceled: the fight goes on as a plain dummy fight."), text(S.M))
    assertNil(S.NS.Fight.Current().race, "the part came off the fight")
end)

test("race verb: show, hide and toggle reach the Race window, and say so before it is built", function()
    if forever() then return end
    local S = F.fresh()
    S.M.__resetPrinted()
    S.NS.Slash:OnSlash("race show")
    assertTrue(said(S.M, "That part of Combat Trail is not built yet."), text(S.M))
    local calls = {}
    S.NS.RaceWindow = {
        Show = function() calls[#calls + 1] = "show" end,
        Hide = function() calls[#calls + 1] = "hide" end,
        Toggle = function() calls[#calls + 1] = "toggle" end,
    }
    for _, word in ipairs({ "show", "hide", "toggle" }) do S.NS.Slash:OnSlash("race " .. word) end
    assertEqual(table.concat(calls, ","), "show,hide,toggle")
    assertTrue(S.NS.ToggleRaceWindow())
    assertEqual(calls[#calls], "toggle", "the shared handler")
    S.M.__resetPrinted()
    S.NS.Slash:OnSlash("race")
    assertTrue(said(S.M, "Usage: /ct race"), "a bare race prints its usage")
end)

test("race verb: ignore shows, adds, removes and resets the late-cast list", function()
    if forever() then return end
    local S = F.fresh()
    local NS, M = S.NS, S.M
    M.__resetPrinted()
    NS.Slash:OnSlash("race ignore")
    assertTrue(said(M, "Late-cast ignore list:"), text(M))
    M.__resetPrinted()
    NS.Slash:OnSlash("race ignore add 29722")
    assertTrue(said(M, "no longer flag a race"), text(M))
    assertTrue(NS.LateIgnore.IsIgnored(29722))
    M.__resetPrinted()
    NS.Slash:OnSlash("race ignore add 29722")
    assertTrue(said(M, "is already ignored"), text(M))
    M.__resetPrinted()
    NS.Slash:OnSlash("race ignore remove 29722")
    assertTrue(said(M, "flag a race again"), text(M))
    M.__resetPrinted()
    NS.Slash:OnSlash("race ignore remove 29722")
    assertTrue(said(M, "is not on the list"), text(M))
    M.__resetPrinted()
    NS.Slash:OnSlash("race ignore frob")
    assertTrue(said(M, "Usage: /ct race ignore"), text(M))
    NS.Slash:OnSlash("race ignore add 29722")
    M.__resetPrinted()
    NS.Slash:OnSlash("race ignore defaults")
    assertTrue(said(M, "The late-cast ignore list is back to its defaults."), text(M))
    assertFalse(NS.LateIgnore.IsIgnored(29722))
end)

test("race verb: disabled, only race ignore answers; every other word is the refusal line", function()
    if forever() then return end
    local S = F.fresh()
    local NS, M = S.NS, S.M
    NS.Slash:OnSlash("disable")
    local refusal = NS.Slash:DisabledLine()
    for _, words in ipairs({ "race", "race arm 60", "race cancel", "race show", "race toggle" }) do
        M.__resetPrinted()
        NS.Slash:OnSlash(words)
        assertEqual(#M.__printed(), 1, words .. ": " .. text(M))
        assertTrue(said(M, refusal), words .. " answers the refusal line")
    end
    assertEqual(NS.Race.State(), "idle", "an arm while disabled")
    M.__resetPrinted()
    NS.Slash:OnSlash("race ignore add 29722")
    assertFalse(said(M, refusal), "race ignore is live while disabled")
    assertTrue(NS.LateIgnore.IsIgnored(29722))
end)

test("race verb: under the perf hold alone, race arm answers the capture line", function()
    if forever() then return end
    local S = F.fresh()
    local NS, M = S.NS, S.M
    NS.lifecycle:Hold(NS.HOLD_PERF)
    M.__resetPrinted()
    NS.Slash:OnSlash("race arm 60")
    assertEqual(#M.__printed(), 1, text(M))
    assertTrue(said(M, "Not available during a performance capture."), text(M))
    assertFalse(said(M, "is disabled"), "never the disabled line")
    M.__resetPrinted()
    NS.Slash:OnSlash("race ignore")
    assertTrue(said(M, "Late-cast ignore list:"), "race ignore answers under the perf hold")
    NS.lifecycle:Release(NS.HOLD_PERF)
end)

-- ── Race mode off ───────────────────────────────────────────────────────────────────────────────

test("race mode off: arming refuses and the Race window stays hidden", function()
    if forever() then return end
    local S = F.fresh()
    local NS, M = S.NS, S.M
    local shown = 0
    NS.RaceWindow = { Show = function() shown = shown + 1 end, Hide = function() end,
                      Toggle = function() shown = shown + 1 end }
    assertTrue(NS.SetByPath("race.enabled", false))
    assertFalse(NS.RaceMode.On())
    local ok, why = F.arm(S, 30)
    assertFalse(ok)
    assertEqual(why, "off")
    for _, words in ipairs({ "race arm 60", "race show", "race toggle" }) do
        M.__resetPrinted()
        NS.Slash:OnSlash(words)
        assertEqual(#M.__printed(), 1, words .. ": " .. text(M))
        assertTrue(said(M, "Race mode is off."), words .. ": " .. text(M))
    end
    M.__resetPrinted()
    assertFalse(NS.ToggleRaceWindow())
    assertTrue(said(M, "Race mode is off."), "the shared handler says why")
    assertEqual(shown, 0, "the Race window was shown with Race mode off")
    assertEqual(NS.Race.State(), "idle")
    -- A pull on the dummy is a plain fight, and the late-cast list still answers.
    S.meter.SetSession(25, F.SESSION)
    F.enter(S, 101)
    F.run(S, 101.25)
    assertNil(NS.Fight.Current().race)
    M.__resetPrinted()
    NS.Slash:OnSlash("race ignore")
    assertTrue(said(M, "Late-cast ignore list:"), text(M))
    assertTrue(NS.SetByPath("race.enabled", true))
    assertTrue(NS.RaceMode.On())
end)

test("race mode off: an armed race is canceled with the switch; a running race runs on", function()
    if forever() then return end
    local S = F.fresh()
    assert(F.arm(S, 30))
    assertTrue(S.NS.SetByPath("race.enabled", false))
    assertEqual(S.NS.Race.State(), "idle", "the arm outlived the switch")
    assertEqual(F.last(S, "RACE_CANCELED")[2], "canceled")
    assertTrue(S.NS.SetByPath("race.enabled", true))
    assert(F.arm(S, 30))
    F.pull(S)
    assertTrue(S.NS.SetByPath("race.enabled", false))
    assertEqual(S.NS.Race.State(), "running", "a race under way was stopped by the switch")
end)
