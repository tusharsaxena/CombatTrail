-- tests/test_bests.lua — modules/Bests.lua (plan Task 2.5, spec §5, adapted from DPS Race @045f479):
-- the best is the top DPS per character x spec x board key, worked out from the stored fights rather
-- than stored on its own; a fight with an unknown target (no board key) never counts; a tie goes to
-- the earlier fight; the boards follow the store (FIGHT_SAVED, FIGHTS_CHANGED).

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local function fresh()
    local inst = T.load()
    return inst.NS, inst.mocks, inst
end

local n = 0
-- A stored-shape record: `o` overrides the fields (who, specID, boardKey, dps, t).
local function rec(o)
    n = n + 1
    local who = { name = o.name or "Tush", realm = o.realm or "Area 52", client = o.client or "retail",
                  class = "MAGE", specID = o.specID or 63, specName = "Fire" }
    local key = o.boardKey
    if key == nil and not o.unknown then key = "c:1985:0" end
    return {
        schema = 1, id = o.id or ("rec-" .. n), t = o.t or (1000 + n), duration = 60, status = o.status or "final",
        who = who, identity = { content = "world", targetName = o.unknown and "Unknown target" or "Boar",
                                unknown = o.unknown or nil },
        boardKey = key, dps = o.dps or 1000, damage = { merged = (o.dps or 1000) * 60 },
    }
end

local function save(NS, ...)
    for _, r in ipairs({ ... }) do assertTrue(NS.Recorder.Save(r), "saved " .. tostring(r.id)) end
end

test("bests: best per character×spec×boardKey", function()
    local NS = fresh()
    local a = rec({ dps = 1000 })
    local b = rec({ dps = 1500 })
    local otherSpec = rec({ dps = 900, specID = 64 })
    local otherBoard = rec({ dps = 800, boardKey = "e:3176:15" })
    local otherChar = rec({ dps = 700, name = "Alt" })
    local otherClient = rec({ dps = 600, client = "forever" })
    save(NS, a, b, otherSpec, otherBoard, otherChar, otherClient)
    local B = NS.Bests
    assertEqual(B.For(a), b, "the higher DPS on the same board")
    assertTrue(B.IsBest(b))
    assertFalse(B.IsBest(a))
    for _, r in ipairs({ otherSpec, otherBoard, otherChar, otherClient }) do
        assertEqual(B.For(r), r, r.id .. " is alone on its board")
        assertTrue(B.IsBest(r))
    end
end)

test("bests: For with exclude answers the runner-up", function()
    local NS = fresh()
    local a, b, c = rec({ dps = 1000 }), rec({ dps = 1500 }), rec({ dps = 1200 })
    save(NS, a, b, c)
    assertEqual(NS.Bests.For(b, true), c, "the best, itself left out")
    assertEqual(NS.Bests.For(a, true), b, "a non-best still sees the best")
    local alone = rec({ dps = 10, boardKey = "c:42:0" })
    save(NS, alone)
    assertNil(NS.Bests.For(alone, true), "no rival")
end)

test("bests: unknown target never a best", function()
    local NS = fresh()
    local u = rec({ dps = 99999, unknown = true })
    local known = rec({ dps = 10 })
    save(NS, u, known)
    assertFalse(NS.Bests.IsBest(u))
    assertNil(NS.Bests.For(u), "no board at all")
    assertTrue(NS.Bests.IsBest(known), "the unknown one does not take a board from a known one")
    local holding = NS.Bests.HoldingIDs(NS.Recorder.List())
    assertNil(holding[u.id])
    assertTrue(holding[known.id])
end)

test("bests: a record with a board key but the unknown flag, or no character, never counts", function()
    local NS = fresh()
    local flagged = rec({ dps = 5000 })
    flagged.identity.unknown = true
    local nameless = rec({ dps = 6000 })
    nameless.who.name = nil
    local lostOne = rec({ dps = 7000, status = "lost" })
    local real = rec({ dps = 10 })
    save(NS, flagged, nameless, lostOne, real)
    assertTrue(NS.Bests.IsBest(real))
    for _, r in ipairs({ flagged, nameless, lostOne }) do assertFalse(NS.Bests.IsBest(r), r.id) end
end)

-- A non-boss identity on NPC `npc` at `level` (plan Task A2): its board key is Identity.BoardKey's.
local function onNpc(NS, o, npc, level)
    local r = rec(o)
    r.identity = { content = "world", targetName = "Boar", targetCreatureID = npc, targetLevel = level,
                   difficultyID = 0 }
    r.boardKey = NS.Identity.BoardKey(r.identity)
    return r
end

test("bests: one NPC at two levels is two boards; the same NPC and level share one", function()
    local NS = fresh()
    local low, lowFaster = onNpc(NS, { dps = 1000 }, 1985, 70), onNpc(NS, { dps = 2000 }, 1985, 70)
    local high = onNpc(NS, { dps = 500 }, 1985, 71)
    save(NS, low, lowFaster, high)
    assertTrue(low.boardKey ~= high.boardKey, "the level splits the key")
    assertEqual(NS.Bests.For(low), lowFaster, "the same NPC and level share a board")
    assertTrue(NS.Bests.IsBest(high), "level 71 is a board of its own, so its slower fight is its best")
end)

test("bests: a tie goes to the earlier fight", function()
    local NS = fresh()
    local late = rec({ dps = 1000, t = 5000 })
    local early = rec({ dps = 1000, t = 4000 })
    save(NS, late, early)
    assertTrue(NS.Bests.IsBest(early))
    assertFalse(NS.Bests.IsBest(late))
end)

test("bests: BestCurve names the best fight's id for a board, a character and a spec", function()
    local NS = fresh()
    local a, b = rec({ dps = 1000 }), rec({ dps = 2000 })
    save(NS, a, b)
    local char = NS.Bests.CharKey(a.who)
    assertEqual(type(char), "string")
    assertEqual(NS.Bests.BestCurve("c:1985:0", char, 63), b.id)
    assertEqual(NS.Bests.BestCurve("c:1985:0", a.who, 63), b.id, "a who table works as the character")
    assertNil(NS.Bests.BestCurve("c:1985:0", char, 64), "another spec")
    assertNil(NS.Bests.BestCurve("c:1:0", char, 63), "another board")
    assertNil(NS.Bests.BestCurve(nil, char, 63))
end)

test("bests: the boards follow a save and a delete", function()
    local NS = fresh()
    local a = rec({ dps = 1000 })
    save(NS, a)
    assertTrue(NS.Bests.IsBest(a))
    local b = rec({ dps = 3000 })
    save(NS, b)
    assertFalse(NS.Bests.IsBest(a), "FIGHT_SAVED drops the cached board")
    assertTrue(NS.Recorder.Delete(b.id))
    assertTrue(NS.Bests.IsBest(a), "FIGHTS_CHANGED drops it too")
end)

test("bests: the character key carries the client, so boards never mix Retail and Forever", function()
    local NS = fresh()
    local r = rec({})
    local f = rec({ client = "forever" })
    assertTrue(NS.Bests.CharKey(r.who) ~= NS.Bests.CharKey(f.who))
    assertNil(NS.Bests.CharKey({ realm = "x" }), "no name, no character")
    assertNil(NS.Bests.CharKey(nil))
end)

test("bests: forever: the predominant tree splits the boards as a spec does (D5)", function()
    local NS = fresh()
    local bm = rec({ dps = 1000, client = "forever", specID = "tree:HUNTER:1" })
    local mm = rec({ dps = 900, client = "forever", specID = "tree:HUNTER:2" })
    local none = rec({ dps = 800, client = "forever" })
    none.who.specID = nil
    save(NS, bm, mm, none)
    assertTrue(NS.Bests.IsBest(bm))
    assertTrue(NS.Bests.IsBest(mm), "another tree, another board")
    assertTrue(NS.Bests.IsBest(none), "no tree is a board of its own")
    assertTrue(NS.Bests.Key(bm):find("|tree:HUNTER:1|", 1, true) ~= nil, NS.Bests.Key(bm))
    assertEqual(NS.Bests.BestCurve("c:1985:0", NS.Bests.CharKey(mm.who), "tree:HUNTER:2"), mm.id)
end)

-- ── race boards (Race mode plan Task A3, the Race mode spec §5) ─────────────────────────────────

-- A race record on dummy `npc` (a Retail seed dummy by default): `o` sets the race part (length,
-- kind, status, flags, dps) over rec's fight fields. Its fight board key is the dummy's.
local DUMMY = 31146
local function race(NS, o)
    local r = onNpc(NS, { dps = o.fightDps or 100, name = o.name, specID = o.specID, t = o.t, id = o.id },
        o.npc or DUMMY, 80)
    r.identity.content = "dummy"
    r.race = { length = o.length or 60, kind = o.kind or "single", status = o.status or "complete",
               flags = o.flags or {}, score = (o.dps or 1000) * (o.length or 60), dps = o.dps or 1000 }
    return r
end

test("bests: a race counts only on its race board, never the dummy's fight board", function()
    local NS = fresh()
    local fight = onNpc(NS, { dps = 500 }, DUMMY, 80)
    fight.identity.content = "dummy"
    local r = race(NS, { dps = 9000, fightDps = 9500 })
    save(NS, fight, r)
    local B = NS.Bests
    assertTrue(B.Key(r) ~= B.Key(fight), "two boards")
    assertEqual(B.Key(r), B.RaceKey(r), "a race's key is its race key")
    assertTrue(B.Key(r):find("|race:", 1, true) ~= nil, B.Key(r))
    assertTrue(B.IsBest(fight), "the fight still holds the dummy's board")
    assertTrue(B.IsBest(r), "the race holds its race board")
    assertEqual(B.For(fight), fight)
    assertEqual(B.For(r), r)
    assertNil(B.RaceKey(fight), "a fight has no race key")
end)

test("bests: race boards split by character, spec, dummy kind and length", function()
    local NS = fresh()
    local a = race(NS, { dps = 1000 })
    local b = race(NS, { dps = 2000 })
    local spec = race(NS, { dps = 100, specID = 64 })
    local char = race(NS, { dps = 100, name = "Alt" })
    local len = race(NS, { dps = 100, length = 120 })
    save(NS, a, b, spec, char, len)
    local B = NS.Bests
    assertEqual(B.For(a), b, "the same character, spec, kind and length share one board")
    for _, r in ipairs({ spec, char, len }) do assertTrue(B.IsBest(r), r.id .. " is alone on its board") end
    assertTrue(B.RaceKey(a):find("race:" .. B.RaceKind(a) .. ":60", 1, true) ~= nil, B.RaceKey(a))
    local nameless = race(NS, {})
    nameless.who.name = nil
    assertNil(B.RaceKey(nameless), "no character, no board")
    local noLength = race(NS, {})
    noLength.race.length = nil
    assertNil(B.RaceKey(noLength), "no length, no board")
end)

test("bests: a race's kind is read from the dummy list now, else the stored kind", function()
    local NS = fresh()
    -- A creature on no list: the stored kind holds the board.
    local stored = race(NS, { npc = 999001, kind = "boss" })
    assertEqual(NS.Bests.RaceKind(stored), "boss")
    -- The player adds it as a cleave dummy: its race moves boards, and back when it is removed.
    assertTrue(NS.Dummies.Add(999001, "cleave"))
    assertEqual(NS.Bests.RaceKind(stored), "cleave")
    assertTrue(NS.Dummies.Remove(999001))
    assertEqual(NS.Bests.RaceKind(stored), "boss")
    local none = race(NS, { npc = 999002 })
    none.race.kind = nil
    assertNil(NS.Bests.RaceKey(none), "no kind at all, no board")
end)

test("bests: a dummy list change redraws the race boards", function()
    local NS = fresh()
    local a = race(NS, { npc = 999003, kind = "single", dps = 1000 })
    local b = race(NS, { npc = 999004, kind = "single", dps = 2000 })
    save(NS, a, b)
    assertFalse(NS.Bests.IsBest(a), "one board")
    assertTrue(NS.Dummies.Add(999003, "cleave"))
    assertTrue(NS.Bests.IsBest(a), "moved to the cleave board, where it is alone")
end)

test("bests: incomplete and lost races never count; the highest race DPS holds the board", function()
    local NS = fresh()
    local done = race(NS, { dps = 1000, fightDps = 99999 })
    local incomplete = race(NS, { dps = 5000, status = "incomplete" })
    local lost = race(NS, { dps = 6000, status = "lost" })
    save(NS, done, incomplete, lost)
    assertTrue(NS.Bests.IsBest(done))
    assertFalse(NS.Bests.IsBest(incomplete))
    assertFalse(NS.Bests.IsBest(lost))
    local better = race(NS, { dps = 1001, fightDps = 1 })
    save(NS, better)
    assertTrue(NS.Bests.IsBest(better), "ranked by the race DPS, not the fight's")
end)

test("bests: an incomplete or flagged race never holds the clean board", function()
    local NS = fresh()
    local clean = race(NS, { dps = 1000 })
    local flagged = race(NS, { dps = 3000, flags = { lateCasts = { { t = 1.4, spellID = 133 } } } })
    local died = race(NS, { dps = 2500, flags = { died = true } })
    local incomplete = race(NS, { dps = 4000, status = "incomplete" })
    save(NS, clean, flagged, died, incomplete)
    local B = NS.Bests
    assertEqual(B.For(clean), flagged, "a flag informs and never voids: it holds the all-races board")
    assertEqual(B.CleanFor(clean), clean, "the clean board leaves every flagged race out")
    assertEqual(B.CleanFor(flagged), clean, "the same board, seen from a flagged race")
    local cleanBoard = B.Board({ cleanOnly = true })
    assertEqual(cleanBoard[B.Key(clean)], clean)
    local fight = rec({ dps = 10 })
    save(NS, fight)
    assertEqual(B.CleanFor(fight), fight, "a fight has no flags, so it is its own clean board")
    assertNil(B.CleanFor(rec({ unknown = true })), "no board")
end)

test("bests: Compute's second argument still skips a record; the clean view is its third", function()
    local NS = fresh()
    local a, b = race(NS, { dps = 1000 }), race(NS, { dps = 2000, flags = { reloaded = true } })
    local key = NS.Bests.Key(a)
    assertEqual(NS.Bests.Compute({ a, b })[key], b)
    assertEqual(NS.Bests.Compute({ a, b }, b)[key], a, "skip")
    assertEqual(NS.Bests.Compute({ a, b }, nil, { cleanOnly = true })[key], a, "clean")
end)

test("bests: HoldingIDs names the holders of the all and the clean boards", function()
    local NS = fresh()
    local clean = race(NS, { dps = 1000 })
    local flagged = race(NS, { dps = 3000, flags = { sharedSession = true } })
    local slow = race(NS, { dps = 500 })
    local fight = rec({ dps = 10 })
    local ids = NS.Bests.HoldingIDs({ clean, flagged, slow, fight })
    assertTrue(ids[clean.id], "the clean holder")
    assertTrue(ids[flagged.id], "the all-races holder")
    assertTrue(ids[fight.id], "a fight board's holder")
    assertNil(ids[slow.id])
end)

test("bests: Before is the best on the board fought before; Delta the verdict against it", function()
    local NS = fresh()
    local first = race(NS, { dps = 1000, t = 100 })
    local second = race(NS, { dps = 1200, t = 200 })
    local third = race(NS, { dps = 1100, t = 300 })
    local otherBoard = race(NS, { dps = 5000, t = 150, length = 120 })
    local incomplete = race(NS, { dps = 9000, t = 160, status = "incomplete" })
    local later = race(NS, { dps = 9999, t = 900 })
    local all = { first, second, third, otherBoard, incomplete, later }
    local B = NS.Bests
    assertNil(B.Before(first, all), "nothing before the first")
    assertEqual(B.Before(third, all), second, "ignores later races, other boards and ones that never count")
    local pct, isNew, prev = B.Delta(second, all)
    assertTrue(math.abs(pct - 20) < 1e-9, tostring(pct))
    assertTrue(isNew)
    assertEqual(prev, first)
    pct, isNew, prev = B.Delta(third, all)
    assertTrue(pct < 0)
    assertFalse(isNew)
    assertEqual(prev, second)
    pct, isNew, prev = B.Delta(first, all)
    assertNil(pct)
    assertTrue(isNew, "the first complete race on its board is a new best")
    assertNil(prev)
    pct, isNew, prev = B.Delta(incomplete, all)
    assertNil(pct)
    assertFalse(isNew, "a race that does not count is never a new best")
    assertNil(prev)
end)

test("bests: Delta works for fights too, and defaults its list to the store", function()
    local NS = fresh()
    local a, b = rec({ dps = 1000, t = 100 }), rec({ dps = 1500, t = 200 })
    save(NS, a, b)
    local pct, isNew, prev = NS.Bests.Delta(b)
    assertTrue(math.abs(pct - 50) < 1e-9, tostring(pct))
    assertTrue(isNew)
    assertEqual(prev, a)
    assertEqual(NS.Bests.Before(b), a, "the store by default")
end)
