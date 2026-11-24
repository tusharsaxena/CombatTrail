-- tests/test_sample_names.lua — one source of sample names (FB2-CTR-01, LibKa0s#104; standard
-- v2.120.0 preview-mode, *Sample characters*, *Every name comes from the library*).
--
-- WHY. Every named sample person a test mode, sim, preview or sample line draws comes from
-- LibKa0s-Sim-1.0: the protagonists through Sim.Sample() and everyone else from the shared crowd,
-- Sim.SampleCrowd() (LibKa0s v1.113.0). The convention's rule 6 ("roster pools do not converge") is
-- retired, so an addon's own Sample*/Mock* list, a library-absent fallback included, is drift
-- (decision D1 of Ka0sAddonsCommonTasks docs/2026-11-24-FEEDBACK_BATCH/R2_SMOKE_FEEDBACK.md).
-- modules/MockFights.lua reads its hunters and its player targets from the library.
--
-- THE GATE. A Sample*/Mock* name (`Sample` or `Mock` then lowercase letters, the convention's name
-- shape, `Samplerealm` and `Mockrealm` among them) may live only under tests/. libs/ is the
-- library's own, and the frozen bundles under docs/ are history. It scans every tracked text file,
-- code and docs alike, and fails rather than passes when it cannot look.

local T = _G.CT_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local SKIPPED = { "tests/", "libs/", "docs/audits/", "docs/reviews/", "docs/automated-tests/",
                  "docs/perf-analysis/", "docs/revendor/", "docs/superpowers/" }
local TEXT = { lua = true, toc = true, xml = true, md = true, txt = true, json = true }

--- Every Sample*/Mock* name in `text`, in order.
local function sampleNames(text)
    local found = {}
    for word in text:gmatch("%f[%w_]%u%l+%f[^%w_]") do
        if word:match("^Sample%l+$") or word:match("^Mock%l+$") then found[#found + 1] = word end
    end
    return found
end

local function skipped(path)
    for _, prefix in ipairs(SKIPPED) do
        if path:sub(1, #prefix) == prefix then return true end
    end
    local ext = path:match("%.(%w+)$")
    return not (ext and TEXT[ext:lower()])
end

--- Every tracked text path outside the skipped trees; raises when git cannot answer.
local function tracked()
    assert(io.popen, "sample names: io.popen is unavailable, so this gate cannot run")
    local pipe = assert(io.popen('git -C "' .. T.root .. '" ls-files'), "sample names: git ls-files gave no handle")
    local out = {}
    for path in pipe:lines() do
        if not skipped(path) then out[#out + 1] = path end
    end
    pipe:close()
    assertTrue(#out > 0, "sample names: git ls-files reported no file, so this gate cannot run")
    return out
end

test("sample names: the matcher sees the convention's names and nothing else", function()
    local found = sampleNames('local a = "Samplewarrior-Samplerealm"; local b = { "Mockpriest" }')
    assertEqual(table.concat(found, ","), "Samplewarrior,Samplerealm,Mockpriest",
        "a planted name, its realm and a Mock name are each seen")
    assertEqual(#sampleNames("Sim.Sample(), Sim.SampleCrowd(c, 13, 1), MockFights, SampleSay, Sample note, SAMPLE"),
        0, "the library's calls, the module names and the bare words are not names")
    assertEqual(#sampleNames("ExampleSamplewarrior unMockpriest"), 0, "a name inside a word is not one")
end)

test("sample names: no Sample*/Mock* name lives outside tests/ (LibKa0s#104)", function()
    local hits = {}
    for _, path in ipairs(tracked()) do
        local fh = assert(io.open(T.root .. "/" .. path, "rb"), "sample names: cannot open " .. path)
        local n = 0
        for line in fh:lines() do
            n = n + 1
            for _, name in ipairs(sampleNames(line)) do hits[#hits + 1] = ("%s:%d %s"):format(path, n, name) end
        end
        fh:close()
    end
    assertEqual(table.concat(hits, "; "), "", "every named sample person is read from LibKa0s-Sim-1.0")
end)
