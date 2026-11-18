-- tests/test_report_verbs.lua — the report verbs on LibKa0s-DebugLog-1.0's D:Report (LibKa0s#79, the
-- owner's report-routing ruling of 2026-11-08): `/ct ignore list [lane]`, `/ct dummy [show]` and
-- `/ct race ignore [show]` (Retail) write their lists, and `/ct probe` its report, to the debug console, ungated, open it, and
-- print exactly one pointer line in chat. An empty list is a short answer: one chat line, nothing
-- written. A usage line inside a report verb stays in chat. With the library absent the report is
-- streamed to chat with no pointer.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local GOLEM = 243205
local BOAR = 99999

local function printed(M) return M.__printed() end
local function said(M) return table.concat(M.__printed(), "\n") end

-- Load, with logging off and the console hidden, and the chat cleared.
local function fresh(opts)
    local inst = T.load(opts)
    local NS, M = inst.NS, inst.mocks
    assertFalse(NS.DebugLog:IsEnabled() == true, "logging starts off")
    if NS.DebugLog:IsShown() then NS.DebugLog:Hide() end
    M.__resetPrinted()
    return NS, M
end

-- What one verb wrote to the console, and the chat it printed.
local function run(NS, M, words)
    local D = NS.DebugLog
    local from = #D.buffer
    M.__resetPrinted()
    NS.Slash:OnSlash(words)
    local wrote = {}
    for i = from + 1, #D.buffer do wrote[#wrote + 1] = D.buffer[i] end
    return wrote, printed(M)
end

local function holds(lines, needle)
    for _, l in ipairs(lines) do
        if tostring(l):find(needle, 1, true) then return true end
    end
    return false
end

-- A report: the console holds the header and `needle`, it is shown, and chat is the one pointer.
local function assertReport(NS, wrote, chat, header, needle)
    assertTrue(holds(wrote, header), "the header " .. header .. " is written: " .. table.concat(wrote, " | "))
    assertTrue(holds(wrote, needle), needle .. " is in the console: " .. table.concat(wrote, " | "))
    assertTrue(NS.DebugLog:IsShown(), "the report opens the console")
    assertEqual(#chat, 1, "exactly one chat line: " .. table.concat(chat, " | "))
    assertTrue(chat[1]:find("lines written to the debug console", 1, true) ~= nil, "the pointer: " .. chat[1])
    assertFalse(NS.DebugLog:IsEnabled() == true, "a report leaves logging off")
end

local function assertChatOnly(NS, wrote, chat, needle)
    assertEqual(#wrote, 0, "nothing is written: " .. table.concat(wrote, " | "))
    assertEqual(#chat, 1, "one chat line: " .. table.concat(chat, " | "))
    assertTrue(chat[1]:find(needle, 1, true) ~= nil, chat[1])
    assertFalse(NS.DebugLog:IsShown(), "the console stays hidden")
end

-- ── /ct ignore list ─────────────────────────────────────────────────────────────────────────────

test("report verbs: /ct ignore list writes the lane's list to the console, one spell a line", function()
    local NS, M = fresh()
    NS.LaneIgnore.Add("player", 2649)
    NS.LaneIgnore.Add("player", 34026)
    local wrote, chat = run(NS, M, "ignore list player")
    assertReport(NS, wrote, chat, "/ct ignore list player", "2649")
    assertTrue(holds(wrote, "34026"), "every spell is a line")
    assertTrue(chat[1]:find("ignore list player", 1, true) ~= nil, "the pointer names the report")
end)

test("report verbs: /ct ignore list with an empty lane is one chat line and writes nothing", function()
    local NS, M = fresh()
    NS.LaneIgnore.ResetToSeed("pet")
    for _, id in ipairs(NS.LaneIgnore.Entries("pet")) do NS.LaneIgnore.Remove("pet", id) end
    local wrote, chat = run(NS, M, "ignore list pet")
    assertChatOnly(NS, wrote, chat, "The Pet lane ignores no spells.")
end)

test("report verbs: a usage line inside /ct ignore stays in chat and writes nothing", function()
    local NS, M = fresh()
    local wrote, chat = run(NS, M, "ignore frob")
    assertChatOnly(NS, wrote, chat, "Usage: /ct ignore")
end)

-- ── /ct dummy show ──────────────────────────────────────────────────────────────────────────────

test("report verbs: /ct dummy (show) writes the training-dummy list to the console", function()
    local NS, M = fresh()
    if NS.DUMMY_SEED[GOLEM] == nil then
        NS.DUMMY_SEED[GOLEM] = { name = "Reinforced Golem", category = "boss" }
    end
    NS.Dummies.Add(BOAR, "single")
    NS.Dummies.Remove(GOLEM)
    local wrote, chat = run(NS, M, "dummy")
    assertReport(NS, wrote, chat, "/ct dummy show", "Your training dummies:")
    assertTrue(holds(wrote, "Creature 99999 \194\183 Single target"), table.concat(wrote, " | "))
    assertTrue(holds(wrote, "(off)"), "the switched-off built-in is listed")
    wrote, chat = run(NS, M, "dummy show")
    assertReport(NS, wrote, chat, "/ct dummy show", "Built-in training dummies:")
end)

test("report verbs: /ct dummy defaults acknowledges in chat, then writes the list as a report", function()
    local NS, M = fresh()
    NS.Dummies.Add(BOAR, "single")
    local wrote, chat = run(NS, M, "dummy defaults")
    assertTrue(holds(wrote, "No training dummies of your own."), table.concat(wrote, " | "))
    assertEqual(#chat, 2, "the confirmation and the pointer: " .. table.concat(chat, " | "))
    assertTrue(chat[1]:find("Your training dummies are cleared", 1, true) ~= nil, chat[1])
    assertTrue(chat[2]:find("lines written to the debug console", 1, true) ~= nil, chat[2])
end)

test("report verbs: a refusal inside /ct dummy stays in chat and writes nothing", function()
    local NS, M = fresh()
    local wrote, chat = run(NS, M, "dummy frobnicate")
    assertChatOnly(NS, wrote, chat, "Usage: /ct dummy")
end)

-- ── /ct race ignore show (Retail) ───────────────────────────────────────────────────────────────

test("report verbs: /ct race ignore writes the late-cast list to the console (Retail)", function()
    local NS, M = fresh()
    if NS.Compat.IsForever() then return end
    local wrote, chat = run(NS, M, "race ignore")
    assertReport(NS, wrote, chat, "/ct race ignore show", "Late-cast ignore list:")
end)

test("report verbs: an empty late-cast list is one chat line and writes nothing (Retail)", function()
    local NS, M = fresh()
    if NS.Compat.IsForever() then return end
    for _, id in ipairs(NS.LateIgnore.List()) do NS.LateIgnore.Unignore(id) end
    local wrote, chat = run(NS, M, "race ignore show")
    assertChatOnly(NS, wrote, chat, "The late-cast ignore list is empty.")
end)

-- ── /ct probe ───────────────────────────────────────────────────────────────────────────────────

test("report verbs: /ct probe writes its report through D:Report, the armed hint inside it", function()
    local NS, M = fresh()
    local wrote, chat = run(NS, M, "probe")
    assertReport(NS, wrote, chat, "/ct probe", "combat log: protected, not used")
    assertTrue(chat[1]:find("probe: %d+ lines written") ~= nil, "the pointer names the report: " .. chat[1])
    assertTrue(NS.Probe.IsArmed(), "the first report arms the next fight")
    assertTrue(tostring(wrote[#wrote]):find("It also watches your next fight", 1, true) ~= nil,
        "the armed hint is the report's last line: " .. tostring(wrote[#wrote]))
end)

test("report verbs: /ct probe after the sampled fight carries no armed hint", function()
    local NS, M = fresh()
    NS.Slash:OnSlash("probe")
    M.InCombatLockdown = function() return true end
    M.__inCombat = true
    M.__fire("PLAYER_REGEN_DISABLED")
    M.__fireTimers()
    M.InCombatLockdown = function() return false end
    M.__inCombat = false
    M.__fire("PLAYER_REGEN_ENABLED")
    M.__fireTimers()
    assertFalse(NS.Probe.IsArmed(), "the fight was sampled and the probe disarmed")
    local wrote, chat = run(NS, M, "probe")
    assertEqual(#chat, 1, table.concat(chat, " | "))
    assertTrue(holds(wrote, "/ct probe"), table.concat(wrote, " | "))
    assertFalse(holds(wrote, "It also watches your next fight"), table.concat(wrote, " | "))
end)

test("report verbs: /ct probe start and stop are acknowledgments: chat only, nothing written", function()
    local NS, M = fresh()
    local wrote, chat = run(NS, M, "probe start")
    assertChatOnly(NS, wrote, chat, "The probe watches your next fight.")
    wrote, chat = run(NS, M, "probe stop")
    assertChatOnly(NS, wrote, chat, "The probe stopped watching.")
end)

-- ── the library absent ──────────────────────────────────────────────────────────────────────────

test("report verbs: library absent, the report streams to chat with no pointer", function()
    local NS, M = fresh({ libFiles = {} })
    NS.LaneIgnore.Add("player", 2649)
    M.__resetPrinted()
    NS.LaneIgnore.OnVerb("list player")
    local chat = said(M)
    assertTrue(chat:find("2649", 1, true) ~= nil, chat)
    assertNil(chat:find("lines written to the debug console", 1, true), "no pointer without the console")
    assertEqual(type(NS.DebugLog.Serialize), "function", "the stub answers Serialize")
    assertEqual(#NS.DebugLog:Serialize({}), 1, "a serialize is one line on the stub")
end)
