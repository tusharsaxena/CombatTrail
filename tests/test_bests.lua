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
