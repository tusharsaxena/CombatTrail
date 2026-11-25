-- tests/perf.lua — the offline scenario runner (performance-§9).
--
--   lua tests/perf.lua [--out <path>] [--label <text>]
--
-- OUTSIDE THE GREEN GATE: `lua tests/run.lua` never runs it, and no commit depends on it. It asserts
-- only deterministic quantities, bytes allocated per iteration and bracket notes per iteration, each
-- measured loop isolated by a full collect on either side with the collector stopped inside it.
-- Timings are printed for orientation only: compare scenarios within a run, never across machines.
--
-- WHY THESE SCENARIOS. The Combat Log (CombatTrail #11, modules/CombatLog.lua) is the path that runs on
-- the most events in a busy fight: every aura gained or lost on the player and the target, every hit
-- and heal on the player and every cast. Its contract (spec #11, *Performance*) is constant work per
-- event, one ring line each and no allocation beyond the line's table, which the ring reuses once it
-- is full. Each scenario runs inside an open fight, the frame's handler called as the client calls it
-- (its OnEvent script, with the event's own arguments):
--   logHit     one UNIT_COMBAT WOUND on the player, with an amount, a school and a critical mark
--   logAura    one UNIT_AURA gain and the matching loss on the target (two lines)
--   logCast    one cast handed in by the lanes' listener (inside laneCast, so no bracket of its own)
--   busyFight  a busy fight's beat: two casts, two hits, a heal and an aura gained and lost
--   logPaint      (CL-11b) the DPS HUD's docked Combat Log drawer open: a busy beat, then one repaint
--                 tick (modules/Hud_Log.lua's HudLog.Paint), ten rows painted (the default since
--                 owner feedback item 16) and the scroll indicator's count moved on by the new lines
--   logPaintIdle  one repaint tick with nothing new: no paint at all
--   logPlaceIdle  (CL-REV) the drawer's place at a HUD beat that moved nothing (HudLog.Place, which
--                 the HUD's render calls on every live beat): compared field by field, no allocation
-- logHit and logAura are each measured with capture OFF and ON: the pair is the zero-overhead
-- evidence performance-§2 asks for (capture off may allocate nothing over capture on, and capture on
-- no more than one note's PAIR_SLACK over off).
--
-- CEILINGS. Measured 2026-11-25 on Lua 5.1.5 (CL-11a): every scenario 0 bytes per iteration once the
-- ring is full, its lines' tables reused. A ceiling sits a little above the measured figure; raise
-- one only by re-measuring and saying why: a rise is the finding.
-- logPaint, measured 2026-11-25 (CL-11b): 9,520 bytes per iteration, all of it the kit's widget
-- recorder (48 bytes for each SetText and SetVertexColor a row's paint makes, measured on its own);
-- the cells, the time and amount strings and the labels' paint allocate 0 once warm. logPaintIdle: 0.
-- Re-measured 2026-11-25 (CLF-2): 6,992 bytes with ten rows (5,696 with eight, at adbef0d): the two
-- rows' recorder bytes; the scroll indicator's count (LogTable.Count) allocates nothing once its slots
-- are reused, and an indicator that did not move places nothing. The ceiling holds.

local root = (arg and arg[0] and arg[0]:match("^(.*)/tests/perf%.lua$")) or "."
package.path = root .. "/tests/?.lua;" .. package.path

local Kit     = dofile(root .. "/tests/_kit/framework.lua")
local Loader  = dofile(root .. "/tests/_kit/loader.lua")
local mockmod = assert(loadfile(root .. "/tests/wow_mock.lua"))(root)
local MockMeter = dofile(root .. "/tests/mock_meter.lua")(Kit)
Loader.addonName = "CombatTrail"

local N = 4000
local USAGE = "usage: lua tests/perf.lua [--out <path>] [--label <text>]\n"

local BYTE_CEILING = {
    logHitCaptureOff = 8, logHitCaptureOn = 8,
    logAuraCaptureOff = 8, logAuraCaptureOn = 8,
    logCast = 8,
    busyFight = 16,
    logPaint = 10240, logPaintIdle = 8, logPlaceIdle = 8,
}
local NOTES_PER_ITER = {
    logHitCaptureOff = 0, logHitCaptureOn = 1,
    logAuraCaptureOff = 0, logAuraCaptureOn = 2,
    logCast = 0,
    busyFight = 0,
    logPaint = 0, logPaintIdle = 0, logPlaceIdle = 0,
}
local PAIRS = { logHitCaptureOff = "logHitCaptureOn", logAuraCaptureOff = "logAuraCaptureOn" }
local PAIR_SLACK = 64
local PAIR_NOISE = 1

local opts = { out = nil, label = "offline" }
do
    local i = 1
    while arg and arg[i] do
        local a = arg[i]
        if a == "--out" and arg[i + 1] then opts.out = arg[i + 1]; i = i + 2
        elseif a == "--label" and arg[i + 1] then opts.label = arg[i + 1]; i = i + 2
        else
            io.stderr:write("unknown argument: " .. tostring(a) .. "\n")
            io.stderr:write(USAGE)
            os.exit(2)
        end
    end
end

-- ── environment ─────────────────────────────────────────────────────────────────────────────────
-- Both load lists are DERIVED (testing-§9): the library's from LibKa0s.xml, the addon's from the TOC,
-- so this runner measures what the client loads and never a hand-kept list.

local LIB_FILES = Loader.xmlFiles(root .. "/libs/LibKa0s/LibKa0s.xml")
local ADDON_FILES = {}
for i, rel in ipairs(Loader.tocFiles(root .. "/CombatTrail.toc")) do ADDON_FILES[i] = root .. "/" .. rel end

local meter
local mocks = mockmod.build()
meter = MockMeter.install(mocks)
mocks._G = Loader.makeEnv(mocks)
local NS = {}
Loader.loadAll(LIB_FILES, NS, mocks)
Loader.loadAll(ADDON_FILES, NS, mocks)
do
    local AceAddon = mocks.LibStub("AceAddon-3.0")
    AceAddon:InitializeAddon(NS)
    AceAddon:EnableAddon(NS)
    if mocks.__fireTimers then mocks.__fireTimers() end
end
local M = mocks

local failures = {}
local function check(ok, msg) if not ok then failures[#failures + 1] = msg end end

check(NS.Perf.BuildRecord ~= nil, "NS.Perf is the degradation stub: every scenario would measure a stub")

-- Count the bracket's notes without allocating: a counter, not a list.
local notes = 0
local realNote = NS.Perf.Note
NS.Perf.Note = function(key, ms, parent)
    notes = notes + 1
    return realNote(key, ms, parent)
end

local results = {}

-- The warm-up and the measured loop run through this one function, at the same stack depth.
local function loop(n, fn)
    for _ = 1, n do fn() end
end

local REHASH_KB = 64

--- Run `fn` n times after a warm-up of the same length, the collector stopped inside the loop. The
--- warm-up fills the ring (N lines or more), so the measured loop reuses its lines' tables as the
--- client's steady state does; `prime` runs the same stopped-collector loop once first, so neither
--- half of a pair is billed for a rehash the other escaped.
local function measure(name, n, fn)
    loop(n, fn)
    collectgarbage("collect"); collectgarbage("stop")
    loop(n, fn)
    collectgarbage("restart")
    notes = 0
    collectgarbage("collect"); collectgarbage("collect")
    collectgarbage("stop")
    local grown, last = 0, collectgarbage("count")
    local t0 = os.clock()
    for _ = 1, n do
        fn()
        local now = collectgarbage("count")
        local step = now - last
        if step > 0 and step < REHASH_KB then grown = grown + step end
        last = now
    end
    local t1 = os.clock()
    collectgarbage("restart")
    results[#results + 1] = {
        name = name, iterations = n, totalMs = (t1 - t0) * 1000, msPerIter = (t1 - t0) * 1000 / n,
        notesPerIter = notes / n, bytesPerIter = grown * 1024 / n,
    }
end

local function pair(base, fn)
    for _, on in ipairs({ false, true }) do
        NS.Perf.on = on
        collectgarbage("collect"); collectgarbage("stop")
        loop(N, fn)
        collectgarbage("restart")
    end
    NS.Perf.on = false
    measure(base .. "CaptureOff", N, fn)
    NS.Perf.on = true
    measure(base .. "CaptureOn", N, fn)
    NS.Perf.on = false
end

-- ── the scene: a fight open on session 1, the Combat Log capturing ──────────────────────────────

M.__now = 100
meter.SetSession(1, { damage = 1000, dps = 100, duration = 10, spells = { { id = 133, dmg = 1000, dps = 100 } } })
M.InCombatLockdown = function() return true end
M.__inCombat = true
M.__fire("PLAYER_REGEN_DISABLED")
local CL = NS.CombatLog
local frame = CL.EventFrame()
check(CL.LiveStart() ~= nil, "no fight is open: every scenario would measure nothing")
check(frame ~= nil and frame.__scripts and frame.__scripts.OnEvent ~= nil,
    "the Combat Log holds no event frame in the fight: every scenario would measure nothing")
local onEvent = frame and frame.__scripts and frame.__scripts.OnEvent or function() end

-- The events' arguments, built once: the client hands fresh tables, which are the client's to pay for.
local GAIN = { addedAuras = { { auraInstanceID = 501, spellId = 12654, isHarmful = true,
                                isFromPlayerOrPlayerPet = true } } }
local LOSS = { removedAuraInstanceIDs = { 501 } }

local function logHit() onEvent(frame, "UNIT_COMBAT", "player", "WOUND", "CRITICAL", 1234, 4) end
local function logAura()
    onEvent(frame, "UNIT_AURA", "target", GAIN)
    onEvent(frame, "UNIT_AURA", "target", LOSS)
end
local function logCast() CL.OnCast("player", 133, M.__now, false) end
local function busyFight()
    CL.OnCast("player", 133, M.__now, false)
    CL.OnCast("pet", 17253, M.__now, false)
    onEvent(frame, "UNIT_COMBAT", "player", "WOUND", "", 900, 1)
    onEvent(frame, "UNIT_COMBAT", "player", "WOUND", "GLANCING", 400, 1)
    onEvent(frame, "UNIT_COMBAT", "player", "HEAL", "", 700, 2)
    onEvent(frame, "UNIT_AURA", "target", GAIN)
    onEvent(frame, "UNIT_AURA", "target", LOSS)
end

local before = CL.Seq()
pair("logHit", logHit)
pair("logAura", logAura)
NS.Perf.on = false
measure("logCast", N, logCast)
measure("busyFight", N, busyFight)
-- The DPS HUD's docked drawer open (CL-11b, modules/Hud_Log.lua): one repaint tick after a busy beat
-- (seven new lines, ten rows painted), and one with nothing new, which repaints nothing at all.
NS.Hud.Show()
NS.HudLog.SetShown(true)
local drawer = NS.HudLog.__ui()
check(drawer ~= nil and drawer.frame:IsShown(), "the drawer is not up: the paint scenarios would measure nothing")
measure("logPaint", N, function()
    busyFight()
    NS.HudLog.Paint()
end)
measure("logPaintIdle", N, function() NS.HudLog.Paint() end)
-- The HUD's every live beat places the drawer (Hud.lua's render): a place that moved nothing.
local hudFrame, logW = NS.Hud.Frame(), NS.Hud.LogWidth()
NS.HudLog.Place(hudFrame, 12, 0, logW)
measure("logPlaceIdle", N, function() NS.HudLog.Place(hudFrame, 12, 0, logW) end)
check(CL.Seq() > before, "no line was appended: the scenarios measured nothing")
check(CL.__ringCount() == NS.Constants.LOG.RING, "the ring is not full: the steady state was never reached")
NS.Perf.Note = realNote

for _, r in ipairs(results) do
    local ceiling = BYTE_CEILING[r.name]
    check(ceiling ~= nil and r.bytesPerIter <= ceiling,
        ("%s allocated %.1f bytes/iter, over its %s-byte ceiling"):format(r.name, r.bytesPerIter, tostring(ceiling)))
    local want = NOTES_PER_ITER[r.name]
    check(want ~= nil and math.abs(r.notesPerIter - want) < 1e-9,
        ("%s noted %.2f times/iter, pinned at %s"):format(r.name, r.notesPerIter, tostring(want)))
end

local byName = {}
for _, r in ipairs(results) do byName[r.name] = r end
for offName, onName in pairs(PAIRS) do
    local off, on = byName[offName], byName[onName]
    check(off ~= nil and on ~= nil, ("the pair %s / %s was not measured"):format(offName, onName))
    if off and on then
        check(off.bytesPerIter <= on.bytesPerIter + PAIR_NOISE,
            ("%s allocated %.1f bytes/iter, more than %s's %.1f: the off bracket is not free"):format(
                offName, off.bytesPerIter, onName, on.bytesPerIter))
        check(on.bytesPerIter <= off.bytesPerIter + PAIR_SLACK,
            ("%s allocated %.1f bytes/iter, over %s's %.1f by more than %d"):format(
                onName, on.bytesPerIter, offName, off.bytesPerIter, PAIR_SLACK))
    end
end

-- ── report ──────────────────────────────────────────────────────────────────────────────────────

print(("Ka0s Combat Trail \226\128\148 offline perf  (v%s, label '%s')"):format(tostring(NS.Version()), opts.label))
print()
-- Five columns, exactly: tests/_kit/run-automated-tests.sh counts scenarios structurally as the
-- five-field rows under this header.
print(("%-24s %8s %11s %10s %11s"):format("scenario", "iters", "ms/iter", "notes/iter", "bytes/iter"))
for _, r in ipairs(results) do
    print(("%-24s %8d %11.5f %10.2f %11.1f"):format(r.name, r.iterations, r.msPerIter, r.notesPerIter, r.bytesPerIter))
end
print()
print("timings are for orientation only \226\128\148 compare scenarios within a run, never across machines")
if #failures > 0 then
    print()
    print(("%d assertion%s FAILED:"):format(#failures, #failures == 1 and "" or "s"))
    for _, msg in ipairs(failures) do print("  - " .. msg) end
end

-- ── the record ──────────────────────────────────────────────────────────────────────────────────

local function writeRecord(path)
    local buckets = {}
    for _, r in ipairs(results) do
        buckets[r.name] = { calls = r.iterations, totalMs = r.totalMs, maxMs = r.msPerIter,
                            notesPerIter = r.notesPerIter, bytesPerIter = r.bytesPerIter }
    end
    local fh, err = io.open(path, "w")
    if not fh then
        io.stderr:write("cannot write " .. path .. ": " .. tostring(err) .. "\n")
        os.exit(2)
    end
    fh:write(NS.Perf.EncodeJSON({
        schema = 1, addon = "CombatTrail", source = "offline",
        version = tostring(NS.Version()), interface = 0, timestamp = os.time(),
        label = opts.label, buckets = buckets, failures = failures,
    }), "\n")
    fh:close()
    print("wrote " .. path)
end

if opts.out then writeRecord(opts.out) end

os.exit(#failures == 0 and 0 or 1)
