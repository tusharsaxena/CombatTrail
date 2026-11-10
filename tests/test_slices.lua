-- tests/test_slices.lua — modules/Slices.lua, the damage chart's in-session store (plan Task 2.6,
-- spec §6 and §7). Ported from DPS Race @045f479 (tests/test_chart.lua's store cases) and adapted to a
-- fight of open-ended length: the store copies the live totals once per fixed 2 s step, the chart's
-- columns grow with the fight (never more than 60, re-bucketed by picking, never by summing), and the
-- store never inspects a value. The meter is secret in combat, every read answering fresh opaque
-- handles, so a step is checked by IDENTITY: it must hold the very handle the read answered.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local FIGHT = { damage = 40000, dps = 1000, duration = 40,
                spells = { { id = 133, dmg = 30000, dps = 750 }, { id = 11366, dmg = 10000, dps = 250 } },
                pet = { damage = 5000, dps = 125, spells = { { id = 3110, dmg = 5000, dps = 125 } } },
                enemies = { { name = "Angry Boar", creatureID = 1985, damage = 45000 } } }

local function slices()
    local S = T.NS.Slices
    S.Reset()
    return S
end

-- n fresh secret handles.
local function handles(n)
    local h = {}
    for i = 1, n do h[i] = T.secret(i * 100) end
    return h
end

-- ── the plain math ──────────────────────────────────────────────────────────────────────────────

test("slices: a 2 s step, at most 60 columns, a column that grows with the fight", function()
    local S = slices()
    assertEqual(S.STEP, 2)
    assertEqual(S.MAX, 60)
    assertEqual(S.Boundary(1), 2)
    assertEqual(S.Boundary(30), 60)
    assertEqual(S.Width(0), 2, "never narrower than a step")
    assertEqual(S.Width(30), 2, "a short fight: one column a step")
    assertEqual(S.Width(119), 2, "max(1, floor(119/60)+1) = 2 s")
    assertEqual(S.Width(120), 4, "3 s, rounded up to whole steps")
    assertEqual(S.Width(300), 6)
    assertEqual(S.Width(359), 6)
    for len = 1, 3600, 7 do
        local w = S.Width(len)
        assertTrue(w % S.STEP == 0, "a whole number of steps at " .. len)
        assertTrue(math.ceil(len / w) <= S.MAX, "at most 60 columns at " .. len)
        assertTrue(w >= math.max(1, math.floor(len / 60) + 1), "never narrower than the plan's width at " .. len)
    end
end)

-- ── the capture, pure ───────────────────────────────────────────────────────────────────────────

test("slices: a read copies the handles into each step it is the first read at or after", function()
    local S = slices()
    local h, p = handles(6), handles(6)
    S.Begin("f1")
    assertEqual(S.Record("f1", 1.0, h[1], p[1]), 0, "before the first boundary: nothing")
    assertEqual(S.Record("f1", 2.0, h[2], p[2]), 1, "exactly on it")
    assertEqual(S.Record("f1", 2.6, h[3], p[3]), 0, "a later read in the same step changes nothing")
    local rec = S.Get("f1")
    assertTrue(rawequal(rec.values[1], h[2]), "step 1 holds the read at its boundary")
    assertTrue(rawequal(rec.pet[1], p[2]), "and the pet's total beside it")
    -- 6.2 s: boundary 4 is 2.2 s behind (too late, left empty), boundary 6 is 0.2 s behind.
    assertEqual(S.Record("f1", 6.2, h[4], p[4]), 1)
    assertNil(rec.values[2], "a boundary noticed too late stays empty")
    assertTrue(rawequal(rec.values[3], h[4]))
    assertEqual(S.NextBoundary("f1"), 8)
    -- A read with no total keeps a recent boundary open for the next read.
    assertEqual(S.Record("f1", 8.1, nil, nil), 0)
    assertEqual(S.NextBoundary("f1"), 8)
    assertEqual(S.Record("f1", 8.4, h[5], nil), 1)
    assertTrue(rawequal(rec.values[4], h[5]))
    assertNil(rec.pet[4], "no pet: the pet's step is empty, the player's is not")
    assertEqual(rec.filled, 3)
    assertEqual(rec.count, 4, "four boundaries passed, one a hole")
end)

test("slices: a store without Begin takes nothing, and a secret id is never a key", function()
    local S = slices()
    assertEqual(S.Record("nope", 10, T.secret(1)), 0)
    assertNil(S.Get("nope"))
    assertNil(S.NextBoundary("nope"))
    assertNil(S.Get(T.secret("f1")))
    assertNil(S.Begin(nil))
end)

test("slices: the store never inspects a value, a secret or a plain one", function()
    local S = slices()
    S.Begin("f2")
    local h = handles(40)
    -- Every operation the kit's secret refuses (arithmetic, comparison, truth, concat) would raise.
    local ok, err = pcall(function()
        for i = 1, 40 do S.Record("f2", i * 2, h[i], h[41 - i]) end
        S.Columns("f2", 200)
        S.Tail("f2")
    end)
    assertTrue(ok, tostring(err))
    local rec = S.Get("f2")
    for i = 1, 40 do assertTrue(rawequal(rec.values[i], h[i]), "step " .. i .. " is the handle itself") end
end)

test("slices: the store grows with an open-ended fight and stops at MAX_STEPS", function()
    local S = slices()
    S.Begin("long")
    local last
    for i = 1, S.MAX_STEPS + 20 do
        last = T.secret(i)
        S.Record("long", i * 2, last)
    end
    local rec = S.Get("long")
    assertEqual(rec.count, S.MAX_STEPS, "an hour of steps")
    assertNil(S.NextBoundary("long"), "a full store wants no more reads")
    assertEqual(S.Record("long", (S.MAX_STEPS + 30) * 2, last), 0)
end)

-- ── the columns ─────────────────────────────────────────────────────────────────────────────────

test("slices: a 5 minute fight re-buckets into 50 columns of 6 s, each its last step's total", function()
    local S = slices()
    S.Begin("f5")
    local h = handles(150)
    for i = 1, 150 do S.Record("f5", i * 2, h[i], h[i]) end
    local view = S.Columns("f5")
    assertEqual(view.step, 6)
    assertEqual(view.count, 50)
    for j = 1, 50 do
        assertTrue(rawequal(view.values[j], h[j * 3]), "column " .. j .. " is step " .. (j * 3) .. "'s total")
        assertTrue(rawequal(view.pet[j], h[j * 3]))
    end
    assertEqual(view.filled, 50)
end)

test("slices: a column whose last step is a hole takes its latest filled step, and an empty one stays empty", function()
    local S = slices()
    S.Begin("holes")
    local h = handles(10)
    S.Record("holes", 2, h[1])
    S.Record("holes", 4, h[2])
    S.Record("holes", 10.5, h[3])   -- 6 and 8 are too late: holes; 10 is filled
    S.Record("holes", 30, h[4])     -- 12..28 holes, 30 filled
    local view = S.Columns("holes", 120)   -- 4 s a column: steps {1,2} {3,4} {5,6} ...
    assertEqual(view.step, 4)
    assertEqual(view.count, 30, "the chart spans the length it was given")
    assertTrue(rawequal(view.values[1], h[2]), "steps 1 and 2: the later one")
    assertNil(view.values[2], "steps 3 and 4 are both holes")
    assertTrue(rawequal(view.values[3], h[3]), "steps 5 and 6: step 5")
    assertNil(view.values[4])
    assertTrue(rawequal(view.values[8], h[4]), "step 15 is in column 8")
    assertEqual(view.filled, 3)
end)

test("slices: an expected length sizes the columns before the fight reaches it", function()
    local S = slices()
    S.Begin("pace")
    for i = 1, 10 do S.Record("pace", i * 2, T.secret(i)) end
    assertEqual(S.Columns("pace").step, 2, "20 s in, no expected length: one column a step")
    S.Begin("pace", 300)
    assertEqual(S.Get("pace").count, 10, "a second Begin keeps what was captured")
    local view = S.Columns("pace")
    assertEqual(view.step, 6, "sized for the 5 minutes expected")
    assertEqual(view.count, 50)
    assertEqual(view.filled, 4, "20 s of steps fill four 6 s columns (the fourth with step 10)")
end)

test("slices: the views are cached until the next capture", function()
    local S = slices()
    S.Begin("c")
    S.Record("c", 2, T.secret(1))
    local a, ta = S.Columns("c"), S.Tail("c")
    assertTrue(rawequal(a, S.Columns("c")), "the same view while nothing changed")
    assertTrue(rawequal(ta, S.Tail("c")))
    S.Record("c", 4, T.secret(2))
    assertFalse(rawequal(a, S.Columns("c")), "a new step builds a new view")
    assertFalse(rawequal(ta, S.Tail("c")))
end)

test("slices: Tail is the last 60 steps, one column a step", function()
    local S = slices()
    S.Begin("t")
    local h = handles(100)
    for i = 1, 100 do S.Record("t", i * 2, h[i]) end
    local view = S.Tail("t")
    assertEqual(view.step, 2)
    assertEqual(view.first, 41)
    assertEqual(view.count, 60)
    assertTrue(rawequal(view.values[1], h[41]))
    assertTrue(rawequal(view.values[60], h[100]))
    S.Begin("empty")
    assertEqual(S.Tail("empty").count, 0)
end)

-- ── the fight's end ─────────────────────────────────────────────────────────────────────────────

test("slices: a closed store takes no more reads, and only KEEP closed stores are held", function()
    local S = slices()
    S.Begin("x")
    S.Record("x", 2, T.secret(1))
    S.Close("x")
    assertEqual(S.Record("x", 4, T.secret(2)), 0, "closed: no more reads")
    assertEqual(S.Get("x").count, 1)
    for i = 1, S.KEEP do
        S.Begin("k" .. i)
        S.Close("k" .. i)
    end
    assertNil(S.Get("x"), "the oldest closed store is let go past KEEP")
    assertTrue(S.Get("k1") ~= nil)
    assertEqual(S.Held(), S.KEEP)
    S.Begin("open")
    assertEqual(S.Held(), S.KEEP + 1, "an open store is never let go for room")
end)

test("slices: Drawable answers only a final record with plain damage and steps this session", function()
    local S = slices()
    local record = { id = "r1", status = "final", damage = { merged = 500 } }
    assertNil(S.Drawable(record), "an earlier session's record: no store")
    S.Seed("r1", { step = 2, values = { T.secret(1) }, count = 1, filled = 1 })
    assertTrue(S.Drawable(record) ~= nil)
    record.damage.merged = 0
    assertNil(S.Drawable(record), "no damage to scale to")
    record.damage.merged = T.secret(500)
    assertNil(S.Drawable(record), "a sealed total is no scale")
    record.damage.merged = 500
    record.status = "lost"
    assertNil(S.Drawable(record))
    S.Seed("r2", { step = 2, values = {}, count = 3, filled = 0 })
    assertNil(S.Drawable({ id = "r2", status = "final", damage = { merged = 9 } }), "nothing filled")
    S.Forget("r1")
    assertNil(S.Get("r1"))
end)

-- ── end to end, on the scripted meter ───────────────────────────────────────────────────────────

local function fresh()
    local meter
    local inst = T.load{ mutate = function(m)
        meter = T.mockMeter.install(m)
        m.__unitExists.pet = true
    end }
    local NS = inst.NS
    local heard = { saved = {} }
    local rx = NS.NewBusTarget()
    rx:RegisterMessage(NS.MSG.FIGHT_SAVED, function(_, r) heard.saved[#heard.saved + 1] = r end)
    return inst, meter, heard
end

local function at(inst, t) inst.mocks.__now = t end

local function enter(inst, t)
    at(inst, t)
    inst.mocks.InCombatLockdown = function() return true end
    inst.mocks.__inCombat = true
    inst.mocks.__fire("PLAYER_REGEN_DISABLED")
end

local function leave(inst, t)
    at(inst, t)
    inst.mocks.InCombatLockdown = function() return false end
    inst.mocks.__inCombat = false
    inst.mocks.__fire("PLAYER_REGEN_ENABLED")
end

local function settle(inst, t)
    at(inst, t)
    inst.mocks.__fireTimers()
end

-- The fight's 4 Hz tick from `from` to `to`, as modules/Fight.lua sends it.
local function ticks(inst, fight, from, to)
    for t = from, to, 0.25 do
        at(inst, t)
        inst.NS.SendBus(inst.NS.MSG.FIGHT_TICK, fight)
    end
end

-- Count the live reads.
local function countReads(NS)
    local n, real = { reads = 0 }, NS.Meter.ReadLive
    NS.Meter.ReadLive = function(...)
        n.reads = n.reads + 1
        return real(...)
    end
    return n
end

-- A whole secret fight on session 1, combat from 10 to 50, with the tick running throughout.
local function secretFight()
    local inst, meter, heard = fresh()
    local NS = inst.NS
    at(inst, 10)
    meter.SetSession(1, FIGHT)
    meter.SetPetGUID("Pet-0-1")
    enter(inst, 10)
    local fight = NS.Fight.Current()
    meter.SetSecret(true)
    at(inst, 11)
    inst.mocks.__fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 1)
    local n = countReads(NS)
    ticks(inst, fight, 11, 49.75)
    meter.SetSecret(false)
    leave(inst, 50)
    settle(inst, 55)
    settle(inst, 60)
    return inst, fight, heard, n
end

test("slices: a secret fight is captured once a step, opaque, and its record finds the chart", function()
    local inst, fight, heard, n = secretFight()
    local S = inst.NS.Slices
    local rec = S.Get(fight.id)
    assertTrue(rec ~= nil, "FIGHT_STARTED opened the fight's store")
    assertFalse(rec.open, "FIGHT_ENDED final closed it")
    assertEqual(rec.count, 19, "steps at 2 .. 38 s of the fight clock (11 .. 49.75)")
    assertEqual(n.reads, 19, "one live read a step, not one a tick")
    for i = 1, rec.count do
        assertTrue(T.isSecret(rec.values[i]), "step " .. i .. " holds the opaque player total")
        assertTrue(T.isSecret(rec.pet[i]), "and the opaque pet total")
    end
    assertEqual(#heard.saved, 1, "the fight was stored")
    local record = heard.saved[1]
    assertTrue(rawequal(S.Get(record.id), rec), "the record's id finds the fight's store")
    assertTrue(S.Drawable(record) ~= nil)
    assertEqual(S.Columns(record.id).count, 19)
    for k, v in pairs(record) do
        assertFalse(T.isSecret(v), "the record holds no slice: " .. tostring(k))
    end
    assertNil(record.slices, "nothing of the chart is persisted")
end)

test("slices: a fight the recording filters skip lets its store go, so it never holds a KEEP slot", function()
    local inst, meter = fresh()
    local NS = inst.NS
    local s = {}
    for k, v in pairs(FIGHT) do s[k] = v end
    s.duration = 12
    at(inst, 10)
    meter.SetSession(1, s)
    enter(inst, 10)
    local fight = NS.Fight.Current()
    at(inst, 11)
    inst.mocks.__fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 1)
    ticks(inst, fight, 11, 21.75)
    assertTrue(NS.Slices.Get(fight.id).filled > 0, "the short fight was captured while it ran")
    leave(inst, 22)
    settle(inst, 27)
    settle(inst, 32)
    assertNil(NS.Slices.Get(fight.id), "a skipped fight has no record to draw, so no chart is kept")
    assertEqual(NS.Slices.Held(), 0)
end)

test("slices: no read before a session is bound, and those boundaries become holes", function()
    local inst = fresh()
    local NS = inst.NS
    enter(inst, 10)   -- no session on the meter: nothing to bind
    local fight = NS.Fight.Current()
    assertNil(fight.sessionID)
    local n = countReads(NS)
    ticks(inst, fight, 10, 16)
    assertEqual(n.reads, 0, "no session: no live read")
    assertTrue(NS.Slices.Get(fight.id).count >= 2, "the boundaries passed")
    assertEqual(NS.Slices.Get(fight.id).filled, 0)
end)

test("slices: a lost fight forgets its store, and the stand-down drops an open one", function()
    local inst, meter = fresh()
    local NS = inst.NS
    at(inst, 10)
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    local fight = NS.Fight.Current()
    ticks(inst, fight, 10, 14)
    assertTrue(NS.Slices.Get(fight.id).filled > 0)
    inst.mocks.__fire("DAMAGE_METER_RESET")
    assertNil(NS.Slices.Get(fight.id), "a lost fight has no chart")
    NS.Slices.Begin("open-one")
    NS.Slices.Begin("closed-one")
    NS.Slices.Close("closed-one")
    NS.Slices.Suspend()
    assertNil(NS.Slices.Get("open-one"), "an open store goes with the fight it belonged to")
    assertTrue(NS.Slices.Get("closed-one") ~= nil, "a closed one keeps its chart")
end)
