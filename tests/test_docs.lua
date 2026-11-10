-- tests/test_docs.lua — the doc set's shape against the code it describes (documentation-§1 to §3,
-- plan Task 5.3): the README's canonical section order, badge row and fixed Reporting a bug body,
-- every slash verb named in the README, every TOC file in the module map, every bus message in the
-- hub, the hub's ten mandated sections and its Documentation map in both directions, the smoke suite
-- naming a client on every check and carrying the in-game verification list, and no forbidden root
-- doc. A drift between the docs and the code reddens the suite instead of waiting for an audit.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

--- The file's text with CR stripped, or nil when it is missing.
local function read(rel)
    local f = io.open(T.root .. "/" .. rel, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return (s:gsub("\r", ""))
end

local function mustRead(rel)
    local s = read(rel)
    assertTrue(s ~= nil, rel .. " is missing")
    return s
end

local function lines(s)
    local out = {}
    for line in (s .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line end
    return out
end

local function exists(rel)
    local f = io.open(T.root .. "/" .. rel, "rb")
    if f then f:close() return true end
    return false
end

local function contains(s, needle) return s:find(needle, 1, true) ~= nil end

--- The `## ` headings of a Markdown text, in order, fenced code left out.
local function h2s(s)
    local out, fenced = {}, false
    for _, line in ipairs(lines(s)) do
        if line:match("^```") then fenced = not fenced end
        if not fenced and line:match("^## ") then out[#out + 1] = line end
    end
    return out
end

-- ── README.md (documentation-§1) ─────────────────────────────────────────────────────────────────

test("docs: README opens on its H1 and keeps the canonical section order", function()
    local s = mustRead("README.md")
    assertEqual(lines(s)[1], "# Ka0s Combat Trail")
    local want = { "## Usage", "## How ", "## FAQ", "## Troubleshooting", "## Reporting a bug",
                   "## Issues and feature requests", "## Version History", "## Credits" }
    local got = h2s(s)
    assertEqual(#got, #want, "README sections: " .. table.concat(got, ", "))
    for i, prefix in ipairs(want) do
        assertEqual(got[i]:sub(1, #prefix), prefix, "section " .. i)
    end
end)

test("docs: README badge row tracks the TOC and the case inventory", function()
    local s = mustRead("README.md")
    assertTrue(contains(s, "![WoW](https://img.shields.io/badge/WoW-Midnight_12.1.5_and_Forever_1.60.1-purple)"),
        "the dual-client WoW badge must match ## Interface: 120105, 16001")
    assertTrue(contains(mustRead("CombatTrail.toc"), "## Interface: 120105, 16001"))
    assertTrue(contains(s, "![License](https://img.shields.io/badge/License-MIT-orange)"))
    assertTrue(contains(s, "\n![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)\n"),
        "the standard badge is a bare image, never a link")
    local cases = mustRead("docs/test-cases.md")
    local total = cases:match("| %*%*Total%*%* | %*%*(%d+)%*%* |")
    assertTrue(total ~= nil, "docs/test-cases.md has no Total row")
    local x, y = s:match("Tests%-(%d+)%%2F(%d+)_passing%-green")
    assertEqual(x, total, "the Tests badge's passing count")
    assertEqual(y, total, "the Tests badge's total")
    -- The supported-clients sentence opens the description.
    local desc, want = s:match("\n\n([^\n!#][^\n]*)"), "Supports Retail and WoW Forever."
    assertTrue(desc and desc:sub(1, #want) == want, "description: " .. tostring(desc))
end)

test("docs: README names every slash verb", function()
    local s = mustRead("README.md")
    local missing = {}
    for _, entry in ipairs(T.NS.COMMANDS) do
        if not contains(s, "/kct " .. entry[1]) then missing[#missing + 1] = entry[1] end
    end
    assertEqual(table.concat(missing, ", "), "", "verbs the README never names")
    assertTrue(contains(s, "/combattrail"), "the long slash form")
end)

test("docs: README carries the fixed bug-report body and the first version row", function()
    local s = mustRead("README.md")
    local body = table.concat({
        "## Reporting a bug",
        "",
        "- Type `/kct debug on` and reproduce the bug.",
        "- Type `/kct diagnostics`.",
        "- If the debug window isn't open, open it with `/kct debug`. Press **Copy**, copy the entire output, and include it with your bug report.",
        "",
        "The report is added after the debug trace in the same window, so one copy carries both.",
    }, "\n")
    assertTrue(contains(s, body), "the Reporting a bug section is not the fixed body")
    assertTrue(contains(s, "| Something looks wrong and I want to report it | Follow [Reporting a bug](#reporting-a-bug) below. |"))
    assertTrue(contains(s, "| 0.1.0 | Unreleased | - "), "the version history's first row")
    assertTrue(contains(s, "https://github.com/tusharsaxena/CombatTrail/issues"))
end)

test("docs: README has no numbered list, no placeholder, no logo and no library list", function()
    local s = mustRead("README.md")
    local fenced = false
    for i, line in ipairs(lines(s)) do
        if line:match("^```") then fenced = not fenced end
        if not fenced then
            assertFalse(line:match("^%s*%d+%.%s") ~= nil, "numbered list at README line " .. i)
            assertFalse(line:match("<%a[%w%-]*>") ~= nil and not line:match("<br>"),
                "angle-bracket placeholder at README line " .. i .. ": " .. line)
        end
    end
    assertFalse(contains(s, "media/logos"), "the README carries no logo")
    assertFalse(contains(s, "Ace3") or contains(s, "LibKa0s") or contains(s, "LibSharedMedia"),
        "the README carries no library inventory")
    assertTrue(contains(s, "/kct skin"), "Usage names the skin verb")
end)

-- ── the root doc set (documentation-§1, §2, §4, §7) ──────────────────────────────────────────────

test("docs: the root holds README, CLAUDE and DEPENDENCIES, and no CHANGELOG or TODO", function()
    for _, rel in ipairs({ "README.md", "CLAUDE.md", "DEPENDENCIES.md", "LICENSE" }) do
        assertTrue(exists(rel), rel)
    end
    for _, rel in ipairs({ "CHANGELOG.md", "TODO.md", "docs/CHANGELOG.md", "docs/TODO.md", "docs/agent-context.md" }) do
        assertFalse(exists(rel), rel .. " is forbidden in an addon repo")
    end
end)

test("docs: every doc CLAUDE.md and DEPENDENCIES.md point at exists", function()
    for _, host in ipairs({ "CLAUDE.md", "DEPENDENCIES.md" }) do
        local s = mustRead(host)
        for path in s:gmatch("`(docs/[%w%-_/%.]+%.md)`") do
            assertTrue(exists(path), host .. " points at " .. path)
        end
        assertFalse(contains(s, "arrive with the docs task") or contains(s, "(plan Task 5.3)"),
            host .. " still says the docs are coming")
    end
end)

-- ── docs/ARCHITECTURE.md (documentation-§3) ──────────────────────────────────────────────────────

local TEN = { "## Overview", "## Module Map", "## Settings Schema", "## Message Bus", "## Slash Commands",
              "## Event Subscriptions", "## Taint Notes", "## Known Limitations", "## Documentation map",
              "## Documented deviations" }

test("docs: ARCHITECTURE carries the ten mandated sections and the over-cap census under the register", function()
    local s = mustRead("docs/ARCHITECTURE.md")
    local have = {}
    for _, h in ipairs(h2s(s)) do have[h] = true end
    for _, h in ipairs(TEN) do assertTrue(have[h], "ARCHITECTURE.md lacks " .. h) end
    local reg = s:find("\n## Documented deviations\n", 1, true)
    local census = s:find("\n### Files over the 1500-line cap\n", 1, true)
    assertTrue(reg and census and census > reg, "the census sits under ## Documented deviations")
    assertTrue(contains(s, "| Rule | What differs | Why | Decided | Re-check trigger |"))
    assertTrue(#lines(s) < 400, "the hub stays under 400 lines")
end)

test("docs: ARCHITECTURE carries the per-client feature table", function()
    local s = mustRead("docs/ARCHITECTURE.md")
    assertTrue(contains(s, "| Feature | Retail | WoW Forever |"), "the per-client feature table")
    for _, feature in ipairs({ "Delves", "Arenas", "Mythic+" }) do
        assertTrue(contains(s, "| " .. feature), "the feature table names " .. feature)
    end
end)

--- The addon's own files, as the TOC lists them (libs left out), slash-separated.
local function tocFiles()
    local out = {}
    for _, line in ipairs(lines(mustRead("CombatTrail.toc"))) do
        if line ~= "" and not line:match("^#") and not line:match("^libs\\") then
            out[#out + 1] = (line:gsub("\\", "/"))
        end
    end
    return out
end

test("docs: every TOC file is in the module map and the hub", function()
    local map, hub = mustRead("docs/module-map.md"), mustRead("docs/ARCHITECTURE.md")
    local files = tocFiles()
    assertTrue(#files > 60, "the TOC lists the addon's files")
    for _, path in ipairs(files) do
        assertTrue(contains(map, "`" .. path .. "`"), "docs/module-map.md lacks " .. path)
        local base = path:match("([^/]+)%.lua$")
        assertTrue(contains(hub, base), "docs/ARCHITECTURE.md lacks " .. base)
    end
end)

test("docs: every bus message and slash verb is documented", function()
    local hub, bus = mustRead("docs/ARCHITECTURE.md"), mustRead("docs/slash-dispatch.md")
    for key in pairs(T.NS.MSG) do
        assertTrue(contains(hub, key), "docs/ARCHITECTURE.md lacks the message " .. key)
    end
    for _, entry in ipairs(T.NS.COMMANDS) do
        assertTrue(contains(bus, "`" .. entry[1] .. "`"), "docs/slash-dispatch.md lacks " .. entry[1])
    end
end)

-- The frozen and generated stores the register names once, as directories (documentation-§3).
local FROZEN = { "^docs/superpowers/", "^docs/audits/", "^docs/reviews/", "^docs/revendor/",
                 "^docs/investigations/", "^docs/automated%-tests/[^/]+/", "^docs/perf%-analysis/[^/]+/" }

--- Docs the register names that a LATER task writes: `path -> the task`. The test refuses a row
--- here once its file exists, so the allowance cannot outlive its reason.
local PENDING = { ["automated-tests/RESULTS.md"] = "plan Task 5.4, the first automated-test bundle" }

test("docs: the Documentation map registers every doc under docs/, each once, each on disk", function()
    local hub = mustRead("docs/ARCHITECTURE.md")
    local mapText = hub:match("\n## Documentation map\n(.-)\n## ") or ""
    assertTrue(mapText ~= "", "no ## Documentation map body")
    for _, sub in ipairs({ "### Required (documentation-§3, Tier 1)", "### Conditional (documentation-§3, Tier 2)",
                           "### Verification and record (documentation-§3)", "### Addon-specific (documentation-§3, Tier 3)" }) do
        assertTrue(contains(mapText, sub), "the map lacks " .. sub)
    end
    local rows = {}
    for doc, rest in mapText:gmatch("\n| `([%w%-_/%.]+%.md)` |([^\n]*)") do
        rows[doc] = (rows[doc] or 0) + 1
        local present = not rest:find("Not applicable", 1, true)
        if present then
            if PENDING[doc] then
                assertFalse(exists("docs/" .. doc), doc .. " exists now: drop it from PENDING")
            else
                assertTrue(exists("docs/" .. doc), "the map registers docs/" .. doc .. ", which is not on disk")
            end
        else
            assertFalse(exists("docs/" .. doc), doc .. " is on disk but registered Not applicable")
        end
    end
    for doc, n in pairs(rows) do assertEqual(n, 1, doc .. " is registered more than once") end
    local p = io.popen('cd "' .. T.root .. '" && find docs -name "*.md"')
    for path in p:lines() do
        local frozen = false
        for _, pat in ipairs(FROZEN) do if path:match(pat) then frozen = true end end
        local rel = path:sub(#"docs/" + 1)
        if not frozen and rel ~= "ARCHITECTURE.md" then
            assertTrue(rows[rel] ~= nil, "docs/" .. rel .. " is not in the Documentation map")
        end
    end
    p:close()
end)

-- ── docs/smoke-tests.md (documentation-§3, audit-review-history) ─────────────────────────────────

local CLIENTS = { Retail = true, Forever = true, Both = true }

test("docs: every smoke check names its client", function()
    local s = mustRead("docs/smoke-tests.md")
    local clientCol, checks = nil, 0
    for _, line in ipairs(lines(s)) do
        if line:match("^| ID |") then
            clientCol = nil
            local i = 0
            for cell in line:gmatch("|%s*([^|]-)%s*%f[|]") do
                i = i + 1
                if cell == "Client" then clientCol = i end
            end
            assertTrue(clientCol ~= nil, "a check table without a Client column: " .. line)
        elseif clientCol and line:match("^|") and not line:match("^|%-") then
            local i, client = 0, nil
            for cell in line:gmatch("|%s*([^|]-)%s*%f[|]") do
                i = i + 1
                if i == clientCol then client = cell end
            end
            assertTrue(CLIENTS[client] == true, "a check names no client: " .. line)
            checks = checks + 1
        elseif not line:match("^|") then
            clientCol = nil
        end
    end
    assertTrue(checks >= 60, "the smoke suite holds " .. checks .. " checks")
end)

test("docs: the smoke suite carries the in-game verification list and the probe steps", function()
    local s = mustRead("docs/smoke-tests.md")
    for _, needle in ipairs({
        "/kct probe", "/kct probe start", "pet is separate source", "pace pet-fill anchor",
        "Feign Death", "ElvUI", "Shadowed Unit Frames", "unit-frame names", "sourceCreatureID",
        'UnitGUID("pet")', "PET_SEPARATE", "UNIT_SPELLCAST_SUCCEEDED", "delve tier", "ENCOUNTER_START",
        "DAMAGE_METER_COMBAT_SESSION_UPDATED", "resize", "19705", "absent on WoW Forever",
    }) do
        assertTrue(contains(s, needle), "docs/smoke-tests.md lacks " .. needle)
    end
end)
