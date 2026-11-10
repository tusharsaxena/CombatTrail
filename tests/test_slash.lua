-- tests/test_slash.lua — the slash dispatcher (plan Task 0.2): the spec §8 verb list in help, bare
-- /kct, unknown verbs, enable/disable and lock/unlock through the seam, the debug verb, both chat
-- commands, and the library-absent dispatcher.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local function anyLine(M, needle)
    for _, l in ipairs(M.__printed()) do
        if l:find(needle, 1, true) then return true end
    end
    return false
end

local function text(M) return table.concat(M.__printed(), "\n") end

-- Spec §8's verbs, plus the reserved ones the standard owes every addon (slash-commands-§2).
local SPEC_VERBS = {
    "help", "results", "hud", "unlock", "lock", "test", "sim", "lane", "ignore", "set", "get", "reset",
    "purge", "debug", "diagnostics", "probe",
}
local RESERVED = { "config", "skin", "enable", "disable", "list", "resetall", "perf", "version" }

test("slash: help lists every verb spec §8 names", function()
    local inst = T.load()
    inst.mocks.__resetPrinted()
    inst.NS.Slash:OnSlash("help")
    local out = text(inst.mocks)
    for _, verb in ipairs(SPEC_VERBS) do
        assertTrue(out:find("/kct " .. verb, 1, true) ~= nil, "help names " .. verb)
    end
    for _, verb in ipairs(RESERVED) do
        assertTrue(out:find("/kct " .. verb, 1, true) ~= nil, "help names the reserved " .. verb)
    end
end)

test("slash: help lists every COMMANDS verb, in order", function()
    local inst = T.load()
    inst.mocks.__resetPrinted()
    inst.NS.Slash:OnSlash("help")
    local out, last = text(inst.mocks), 0
    for _, row in ipairs(inst.NS.COMMANDS) do
        local at = out:find("/kct " .. row[1], 1, true)
        assertTrue(at ~= nil and at > last, row[1] .. " is in COMMANDS order")
        last = at
    end
end)

test("slash: an unknown verb says so and prints the help", function()
    local inst = T.load()
    local M = inst.mocks
    M.__resetPrinted()
    inst.NS.Slash:OnSlash("frobnicate")
    assertTrue(anyLine(M, "unknown command 'frobnicate'"), text(M))
    assertTrue(anyLine(M, "/kct help"), "the help follows")
end)

test("slash: bare /kct opens the settings panel", function()
    local inst = T.load()
    local opened = 0
    inst.NS.OpenOptionsPanel = function() opened = opened + 1 end
    inst.NS.Slash:OnSlash("")
    assertEqual(opened, 1)
end)

test("slash: /kct and /combattrail are both registered on the one dispatcher", function()
    local inst = T.load()
    local known = inst.mocks.LibStub("AceConsole-3.0").commands
    assertTrue(known.kct ~= nil, "kct is registered")
    assertTrue(known.combattrail ~= nil, "combattrail is registered")
end)

test("slash: disable and enable write general.enabled through the seam", function()
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    M.__resetPrinted()
    NS.Slash:OnSlash("disable")
    assertEqual(NS.db.profile.general.enabled, false)
    assertTrue(NS.IsDisabled())
    assertTrue(anyLine(M, "general.enabled"), "the stored value is echoed")
    NS.Slash:OnSlash("enable")
    assertEqual(NS.db.profile.general.enabled, true)
    assertFalse(NS.IsStoodDown())
end)

test("slash: a feature verb refuses with the one line while disabled; settings verbs still answer", function()
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    NS.Slash:OnSlash("disable")
    M.__resetPrinted()
    NS.Slash:OnSlash("lock")
    assertTrue(anyLine(M, "is disabled"), text(M))
    assertEqual(NS.GetSetting("general.locked"), false, "the refused verb wrote nothing")
    M.__resetPrinted()
    NS.Slash:OnSlash("get general.locked")
    assertTrue(anyLine(M, "general.locked"), "get answers while disabled")
end)

-- slash-commands-§7 step 7: the suite pins the addon's choice per verb. Every feature verb refuses
-- with exactly one line while disabled and writes nothing; `lane` and `ignore` decline the
-- feature-verb SHOULD (HOST_LIVE_VERBS) and act normally. Under the `perf` hold alone a feature verb
-- answers the capture line, never the disabled one.
local FEATURE_VERBS = { "skin", "results", "hud", "lock", "unlock", "test", "sim", "purge", "probe" }

test("slash: disabled, each feature verb answers one refusal line; lane and ignore still act", function()
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    NS.Slash:OnSlash("disable")
    local refusal = NS.Slash:DisabledLine()
    for _, verb in ipairs(FEATURE_VERBS) do
        M.__resetPrinted()
        NS.Slash:OnSlash(verb)
        assertEqual(#M.__printed(), 1, verb .. ": " .. text(M))
        assertTrue(M.__printed()[1]:find(refusal, 1, true) ~= nil, verb .. " answers the refusal line")
    end
    assertEqual(NS.GetSetting("general.locked"), false, "lock wrote nothing")
    assertFalse(NS.IsTestMode(), "test wrote nothing")
    for _, verb in ipairs({ "lane", "ignore" }) do
        M.__resetPrinted()
        NS.Slash:OnSlash(verb)
        assertEqual(#M.__printed(), 1, verb .. ": " .. text(M))
        assertTrue(M.__printed()[1]:find(refusal, 1, true) == nil, verb .. " is live while disabled")
    end
end)

test("slash: under the perf hold alone a feature verb answers the capture line", function()
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    NS.Slash:OnSlash("disable")
    NS.Slash:OnSlash("enable")
    NS.lifecycle:Hold(NS.HOLD_PERF)
    for _, verb in ipairs({ "lock", "test", "hud" }) do
        M.__resetPrinted()
        NS.Slash:OnSlash(verb)
        assertEqual(#M.__printed(), 1, verb .. ": " .. text(M))
        assertTrue(M.__printed()[1]:find("Not available during a performance capture.", 1, true) ~= nil, text(M))
        assertTrue(M.__printed()[1]:find("is disabled", 1, true) == nil, "never the disabled line")
    end
    assertEqual(NS.GetSetting("general.locked"), false, "lock wrote nothing")
    NS.lifecycle:Release(NS.HOLD_PERF)
end)

test("slash: lock and unlock write general.locked", function()
    local inst = T.load()
    local NS = inst.NS
    NS.Slash:OnSlash("lock")
    assertEqual(NS.GetSetting("general.locked"), true)
    NS.Slash:OnSlash("unlock")
    assertEqual(NS.GetSetting("general.locked"), false)
end)

test("slash: test turns test mode on and off", function()
    local inst = T.load()
    local NS = inst.NS
    NS.Slash:OnSlash("test")
    assertTrue(NS.IsTestMode())
    NS.Slash:OnSlash("test")
    assertFalse(NS.IsTestMode())
end)

test("slash: `debug on`/`off` flip the session flag; bare `debug` toggles only the window", function()
    local inst = T.load()
    local NS = inst.NS
    NS.Slash:OnSlash("debug on")
    assertTrue(NS.State.debug)
    NS.Slash:OnSlash("debug off")
    assertFalse(NS.State.debug)
    local shown = NS.DebugLog:IsShown()
    NS.Slash:OnSlash("debug")
    assertEqual(NS.DebugLog:IsShown(), not shown)
    assertFalse(NS.State.debug, "the window toggle leaves the flag alone")
end)

test("slash: `resetall` asks first, through the one popup", function()
    local inst = T.load()
    local shown = {}
    inst.mocks.StaticPopup_Show = function(name) shown[#shown + 1] = name end
    inst.NS.Slash:OnSlash("resetall")
    assertEqual(shown[1], "COMBATTRAIL_RESET_ALL")
end)

test("slash: a verb whose feature is not built yet says so in one line", function()
    local inst = T.load()
    local M = inst.mocks
    for _, verb in ipairs({ "hud", "lane", "ignore", "purge", "probe" }) do
        M.__resetPrinted()
        inst.NS.Slash:OnSlash(verb)
        assertEqual(#M.__printed(), 1, verb .. ": " .. text(M))
    end
end)

test("slash: the stub's live-verb set is the library's LIVE_VERBS", function()
    local lib = T.mocks.LibStub("LibKa0s-Slash-1.0")
    local want, got = {}, {}
    for _, v in ipairs(lib.LIVE_VERBS) do want[#want + 1] = v end
    for v in pairs(T.NS.SLASH_LIVE_VERBS) do got[#got + 1] = v end
    table.sort(want)
    table.sort(got)
    assertEqual(table.concat(got, ","), table.concat(want, ","))
end)

test("slash: the stub's refusal format is byte-equal to the live library's", function()
    local degraded = T.load{ libFiles = {} }
    local live = T.mocks.LibStub("LibKa0s-Slash-1.0")
    assertEqual(degraded.NS.Slash.__stubFormat, live.DISABLED_LINE_FORMAT)
end)

test("slash: library absent, /kct still answers, and enable/disable still land", function()
    local inst = T.load{ libFiles = {} }
    local NS, M = inst.NS, inst.mocks
    M.__resetPrinted()
    NS.Slash:OnSlash("version")
    assertTrue(anyLine(M, "0.1.0"))
    NS.Slash:OnSlash("disable")
    assertEqual(NS.db.profile.general.enabled, false)
    assertTrue(NS.IsDisabled(), "the written-through switch still took the hold")
    NS.Slash:OnSlash("enable")
    assertEqual(NS.db.profile.general.enabled, true)
    assertFalse(NS.IsStoodDown())
    M.__resetPrinted()
    NS.Slash:OnSlash("list")
    assertTrue(anyLine(M, "LibKa0s library did not load"), "the schema CLI names the missing library")
end)

-- ── the launcher's master-controls menu (spec §8, launcher-§2) ───────────────────────────────────

test("launcher: the menu carries Enabled, Locked, Test mode, Sim mode and Show window", function()
    local d = T.NS.LAUNCHER_DESCRIPTOR
    assertTrue(type(d) == "table", "NS.LAUNCHER_DESCRIPTOR")
    for _, pair in ipairs({ { "isEnabled", "setEnabled" }, { "isLocked", "toggleLock" },
                            { "isTestMode", "toggleTestMode" }, { "isSimMode", "toggleSim" },
                            { "isWindowShown", "toggleWindow" } }) do
        assertEqual(type(d[pair[1]]), "function", pair[1])
        assertEqual(type(d[pair[2]]), "function", pair[2])
    end
end)

test("launcher: the menu's toggles are the slash verbs' handlers", function()
    local inst = T.load()
    local NS = inst.NS
    local d = NS.LAUNCHER_DESCRIPTOR
    d.toggleLock()
    assertTrue(d.isLocked())
    assertEqual(NS.GetSetting("general.locked"), true)
    d.toggleTestMode()
    assertTrue(d.isTestMode())
    d.setEnabled(false)
    assertFalse(d.isEnabled())
    d.setEnabled(true)
    assertTrue(d.isEnabled())
end)
