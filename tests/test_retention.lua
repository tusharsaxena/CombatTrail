-- tests/test_retention.lua — modules/Retention.lua (plan Task 2.5, spec §5): the purge drops fights
-- older than `history.days` (0 keeps them for ever) except those holding a best (`history.keepBests`),
-- then caps the store at `history.maxFights`, the oldest non-best first; it runs at login, on a daily
-- timer while logged in and from `/kct purge`, and fires FIGHTS_CHANGED once. EstimateBytes sizes the
-- store as SavedVariables writes it.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local DAY = 86400
local NOW = 2000000000

local function fresh(mutate)
    local inst = T.load{ mutate = mutate }
    return inst.NS, inst.mocks, inst
end

-- An instance that logs in over `seeded` SavedVariables (the client's login: the store is read, then
-- OnInitialize and OnEnable run).
local function boot(seeded)
    local inst = T.load{ init = false }
    _G.CombatTrailDB = seeded
    local AceAddon = inst.mocks.LibStub("AceAddon-3.0")
    AceAddon:InitializeAddon(inst.NS)
    AceAddon:EnableAddon(inst.NS)
    return inst.NS, inst.mocks, inst
end

local n = 0
local function rec(o)
    n = n + 1
    return {
        schema = 1, id = o.id or ("f-" .. n), t = o.t, duration = 60, status = "final",
        who = { name = "Tush", realm = "Area 52", client = "retail", specID = 63 },
        identity = { content = "world", targetName = "Boar" },
        boardKey = o.boardKey, dps = o.dps or 100, loadout = o.loadout,
    }
end

local function store(NS) return NS.db.global.fights, NS.db.global.fightOrder end

local function count(NS)
    local c = 0
    for _ in pairs(NS.db.global.fights) do c = c + 1 end
    return c
end

local function heardChanged(NS)
    local heard = { n = 0 }
    NS.NewBusTarget():RegisterMessage(NS.MSG.FIGHTS_CHANGED, function() heard.n = heard.n + 1 end)
    return heard
end

test("retention: purge removes >7 days except bests", function()
    local NS = fresh()
    local R = NS.Recorder
    -- Each on its own board, so each is its board's best; then a second, weaker one on a shared board.
    local oldBest = rec({ t = NOW - 10 * DAY, boardKey = "c:1:0", dps = 900 })
    local oldPlain = rec({ t = NOW - 9 * DAY, boardKey = "c:1:0", dps = 100 })
    local oldUnknown = rec({ t = NOW - 8 * DAY })
    local fresh1 = rec({ t = NOW - 1 * DAY, boardKey = "c:2:0" })
    local edge = rec({ t = NOW - 7 * DAY, boardKey = "c:3:0", dps = 1 })
    for _, r in ipairs({ oldBest, oldPlain, oldUnknown, fresh1, edge }) do R.Save(r) end
    local heard = heardChanged(NS)
    local removed = NS.Retention.Purge(NOW)
    assertEqual(removed, 2)
    local fights, order = store(NS)
    assertTrue(fights[oldBest.id] ~= nil, "a best is kept however old")
    assertNil(fights[oldPlain.id], "older than 7 days and no best")
    assertNil(fights[oldUnknown.id], "an unknown target holds no best")
    assertTrue(fights[fresh1.id] ~= nil)
    assertTrue(fights[edge.id] ~= nil, "exactly 7 days old is not older")
    assertEqual(#order, 3, "the order follows the store")
    assertEqual(order[1], fresh1.id, "newest first")
    assertEqual(heard.n, 1, "FIGHTS_CHANGED once")
    assertEqual(NS.Retention.Purge(NOW), 0, "nothing left to remove")
    assertEqual(heard.n, 1, "no message when nothing was removed")
end)

test("retention: keepBests off lets an old best go", function()
    local NS = fresh()
    NS.db.profile.history.keepBests = false
    local old = rec({ t = NOW - 30 * DAY, boardKey = "c:1:0" })
    NS.Recorder.Save(old)
    assertEqual(NS.Retention.Purge(NOW), 1)
    assertNil(NS.db.global.fights[old.id])
end)

test("retention: days=0 keeps forever", function()
    local NS = fresh()
    NS.db.profile.history.days = 0
    for i = 1, 5 do NS.Recorder.Save(rec({ t = NOW - (100 + i) * DAY })) end
    assertEqual(NS.Retention.Purge(NOW), 0)
    assertEqual(count(NS), 5)
end)

test("retention: purge of 600 fights keeps bests and caps at 500", function()
    local NS = fresh()
    NS.db.profile.history.days = 0     -- the cap alone
    local bests = {}
    for i = 1, 600 do
        -- The 20 oldest each hold a board of their own; the rest share one board, where the newest
        -- of them (the highest DPS) is the best.
        local r
        if i <= 20 then
            r = rec({ t = NOW - (1000 - i) * 60, boardKey = "c:" .. (5000 + i) .. ":0" })
            bests[#bests + 1] = r.id
        else
            r = rec({ t = NOW - (1000 - i) * 60, boardKey = "c:1:0", dps = i })
        end
        NS.Recorder.Save(r)
    end
    local sharedBest = NS.db.global.fightOrder[1]
    local removed = NS.Retention.Purge(NOW)
    assertEqual(removed, 100)
    assertEqual(count(NS), 500)
    assertEqual(#NS.db.global.fightOrder, 500)
    for _, id in ipairs(bests) do assertTrue(NS.db.global.fights[id] ~= nil, "best " .. id .. " kept") end
    assertTrue(NS.db.global.fights[sharedBest] ~= nil)
    -- The oldest non-bests went: the 100 after the 20 bests.
    local fights = NS.db.global.fights
    local oldestLeft = math.huge
    for _, r in pairs(fights) do
        if r.boardKey == "c:1:0" and r.t < oldestLeft then oldestLeft = r.t end
    end
    assertEqual(oldestLeft, NOW - (1000 - 121) * 60)
end)

test("retention: maxFights 0 is no cap", function()
    local NS = fresh()
    NS.db.profile.history.days, NS.db.profile.history.maxFights = 0, 0
    for i = 1, 30 do NS.Recorder.Save(rec({ t = NOW - i })) end
    assertEqual(NS.Retention.Purge(NOW), 0)
    assertEqual(count(NS), 30)
end)

test("retention: a purge sweeps the loadouts no fight holds any more", function()
    local NS = fresh()
    local keyOld = NS.Loadouts.Store("OLDSTRING")
    local keyNew = NS.Loadouts.Store("NEWSTRING")
    NS.Recorder.Save(rec({ t = NOW - 30 * DAY, loadout = keyOld }))
    NS.Recorder.Save(rec({ t = NOW, loadout = keyNew }))
    assertEqual(NS.Loadouts.Count(), 2)
    NS.Retention.Purge(NOW)
    assertEqual(NS.Loadouts.Count(), 1)
    assertNil(NS.Loadouts.Get(keyOld))
    assertTrue(NS.Loadouts.Get(keyNew) ~= nil)
end)

test("retention: the purge repairs an order that lost step with the store", function()
    local NS = fresh()
    local a, b = rec({ t = NOW - 10 }), rec({ t = NOW - 5 })
    NS.db.global.fights[a.id], NS.db.global.fights[b.id] = a, b
    NS.db.global.fightOrder = { "ghost", a.id }
    assertEqual(NS.Retention.Purge(NOW), 0, "a dangling id is not a removed fight")
    local order = NS.db.global.fightOrder
    assertEqual(#order, 2)
    assertEqual(order[1], b.id)
    assertEqual(order[2], a.id)
end)

test("retention: a record from a later version is left alone", function()
    local NS = fresh()
    local future = rec({ t = NOW - 400 * DAY })
    future.schema = 99
    NS.db.global.fights[future.id] = future
    assertEqual(NS.Retention.Purge(NOW), 0)
    assertTrue(NS.db.global.fights[future.id] ~= nil)
    assertNil(NS.Recorder.Get(future.id), "never listed")
end)

test("retention: the purge runs at login and on a daily timer", function()
    local seeded = {
        global = { fights = {}, fightOrder = {} },
    }
    local old = rec({ t = 1000 })          -- 1970: far older than 7 days
    seeded.global.fights[old.id] = old
    seeded.global.fightOrder = { old.id }
    local NS, M = boot(seeded)
    assertNil(NS.db.global.fights[old.id], "purged at login")
    local timer = NS.Retention.Timer()
    assertTrue(timer ~= nil, "a timer is armed")
    assertEqual(timer.delay, DAY)
    -- The timer purges again and arms the next day's.
    local again = rec({ t = 1000 })
    NS.Recorder.Save(again)
    M.__fireTimers()
    assertNil(NS.db.global.fights[again.id], "the daily run purged it")
    assertTrue(NS.Retention.Timer() ~= nil)
    assertTrue(NS.Retention.Timer() ~= timer, "re-armed")
end)

test("retention: the daily run waits out combat and a fight in progress", function()
    local seeded = { global = { fights = {}, fightOrder = {} } }
    local NS, M = boot(seeded)
    local again = rec({ t = 1000 })
    NS.Recorder.Save(again)
    M.InCombatLockdown = function() return true end
    M.__fireTimers()
    assertTrue(NS.db.global.fights[again.id] ~= nil, "no purge in combat")
    assertEqual(NS.Retention.Timer().delay, NS.Retention.RETRY, "asked again shortly")
    M.InCombatLockdown = function() return false end
    M.__fireTimers()
    assertNil(NS.db.global.fights[again.id], "purged once combat is over")
    assertEqual(NS.Retention.Timer().delay, DAY, "and the daily timer is armed again")
end)

test("retention: the stand-down cancels the daily timer, the stand-up arms it again", function()
    local NS = fresh()
    assertTrue(NS.Retention.Timer() ~= nil)
    NS.SetByPath("general.enabled", false)
    assertNil(NS.Retention.Timer())
    NS.SetByPath("general.enabled", true)
    assertTrue(NS.Retention.Timer() ~= nil)
end)

test("retention: /kct purge purges now and says how many went", function()
    local NS, M = fresh()
    NS.Recorder.Save(rec({ t = 1000 }))
    NS.Recorder.Save(rec({ t = 1001 }))
    M.__resetPrinted()
    NS.Slash:OnSlash("purge")
    assertEqual(count(NS), 0)
    local lines = M.__printed()
    assertEqual(#lines, 1)
    assertTrue(tostring(lines[1]):find("2", 1, true) ~= nil, tostring(lines[1]))
    M.__resetPrinted()
    NS.Slash:OnSlash("purge")
    assertEqual(#M.__printed(), 1, "one line when nothing went")
end)

test("retention: EstimateBytes sizes the store as SavedVariables writes it", function()
    local NS = fresh()
    local R = NS.Retention
    assertEqual(R.SizeOf(nil), 3, "nil")
    assertEqual(R.SizeOf(5), 1)
    assertEqual(R.SizeOf("ab"), 4, "quoted")
    assertTrue(R.SizeOf({ a = 1 }) > R.SizeOf({}), "an entry costs its key, value and punctuation")
    local before = R.EstimateBytes()
    NS.Recorder.Save(rec({ t = NOW }))
    local after = R.EstimateBytes()
    assertTrue(after > before)
    assertFalse(after - before > 2048, "a bare record is small: " .. (after - before))
end)
