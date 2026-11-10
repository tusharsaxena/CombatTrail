-- tests/test_cast_codec.lua — modules/CastCodec.lua, the stored cast list (plan Task 2.4, spec §5
-- record size): delta-encoded base-36 tokens at 0.1 s resolution, the pet and interrupt flags, a
-- pre-pull cast's negative time, what Decode skips, and the 250-cast size budget.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local function near(got, want, msg)
    assertTrue(type(got) == "number" and math.abs(got - want) < 1e-6,
        (msg or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got))
end

local function cast(t, id, unit, interrupted)
    return { t = t, spellID = id, unit = unit or "player", interrupted = interrupted == true }
end

test("cast codec: the format is delta deciseconds and the spell ID in base 36, flags after a colon", function()
    local Codec = T.NS.CastCodec
    -- 133 = "3p" in base 36, 11366 = "8rq", 17253 = "db9".
    local s = Codec.Encode({ cast(-1.5, 133), cast(0, 11366), cast(1.5, 17253, "pet"), cast(4.2, 133, "player", true) })
    assertEqual(s, "-f:3p;f:8rq;f:db9:p;r:3p:x")
    assertEqual(Codec.Encode({}), "")
    assertEqual(Codec.Encode(nil), "")
end)

test("cast codec: codec round-trips 0.1 s times and flags", function()
    local Codec = T.NS.CastCodec
    local list = { cast(-3.04, 2948), cast(0.06, 133), cast(0.1, 6353, "pet"), cast(12.36, 11366, "pet", true),
                   cast(12.36, 190319), cast(600.0, 1449) }
    local back = Codec.Decode(Codec.Encode(list))
    assertEqual(#back, 6)
    near(back[1].t, -3.0, "rounded to the tenth")
    near(back[2].t, 0.1)
    near(back[3].t, 0.1)
    near(back[4].t, 12.4, "12.36 rounds up")
    near(back[5].t, 12.4, "two casts on one tenth keep a zero delta")
    near(back[6].t, 600)
    assertEqual(back[3].unit, "pet")
    assertEqual(back[1].unit, "player")
    assertTrue(back[4].interrupted)
    assertEqual(back[4].unit, "pet", "both flags on one cast")
    assertFalse(back[5].interrupted)
    assertEqual(back[5].spellID, 190319)
    assertEqual(Codec.Encode(back), Codec.Encode(list), "a decoded list encodes to the same string")
end)

test("cast codec: an out-of-order list still round-trips (a negative delta)", function()
    local Codec = T.NS.CastCodec
    local back = Codec.Decode(Codec.Encode({ cast(5, 1), cast(2, 2), cast(9, 3) }))
    near(back[1].t, 5)
    near(back[2].t, 2)
    near(back[3].t, 9)
end)

test("cast codec: Decode skips what does not parse and answers an empty list for nothing", function()
    local Codec = T.NS.CastCodec
    assertEqual(#Codec.Decode(nil), 0)
    assertEqual(#Codec.Decode(""), 0)
    assertEqual(#Codec.Decode(42), 0)
    local list = Codec.Decode("a:3p;junk;;:9;b:8rq:q;c:db9:p")
    assertEqual(#list, 2, "the junk, the empty token, a missing delta and an unknown flag are skipped")
    near(list[1].t, 1.0)
    assertEqual(list[1].spellID, 133)
    near(list[2].t, 2.2, "a skipped token's delta is not counted")
    assertEqual(list[2].unit, "pet")
end)

test("cast codec: 250 casts packs under 2.5 KB", function()
    local Codec = T.NS.CastCodec
    -- A 5-minute fight's worth: a press every 1.2 s, spell IDs in the six-digit range, every fifth a
    -- pet cast and an occasional interrupt.
    local list, t = {}, -2
    for i = 1, 250 do
        list[i] = cast(t, 400000 + (i * 7919) % 900000, i % 5 == 0 and "pet" or "player", i % 37 == 0)
        t = t + 1.2
    end
    local s = Codec.Encode(list)
    assertTrue(#s < 2560, "250 casts took " .. #s .. " bytes")
    assertEqual(#Codec.Decode(s), 250)
end)

-- ── the spells (plan Task 2.5) ─────────────────────────────────────────────────────────────────

test("codec: the spell list round-trips with the pet flag and a raid-sized total", function()
    local Codec = T.NS.CastCodec
    local spells = {
        { spellID = 133, total = 9876543210, isPet = false },     -- past 2^32
        { spellID = 17253, total = 1200, isPet = true },
        { spellID = 400001, total = 0, isPet = false },
    }
    local s = Codec.EncodeSpells(spells)
    assertEqual(s, "3p:9876543210;db9:1200:p;8kn5:0")
    local back = Codec.DecodeSpells(s)
    assertEqual(#back, 3)
    for i, sp in ipairs(spells) do
        assertEqual(back[i].spellID, sp.spellID)
        assertEqual(back[i].total, sp.total)
        assertEqual(back[i].isPet, sp.isPet)
    end
    assertEqual(Codec.EncodeSpells(Codec.DecodeSpells(s)), s)
end)

test("codec: the spell list skips a row without an ID or a total, and a token that does not parse", function()
    local Codec = T.NS.CastCodec
    assertEqual(Codec.EncodeSpells({ { spellID = 133 }, { total = 5 }, { spellID = 2948, total = 7 } }), "29w:7")
    assertEqual(Codec.EncodeSpells(nil), "")
    local back = Codec.DecodeSpells("3p:10;junk;dbx:5:q;29w:7:p")
    assertEqual(#back, 2)
    assertEqual(back[2].spellID, 2948)
    assertTrue(back[2].isPet)
    assertEqual(#Codec.DecodeSpells(nil), 0)
    assertFalse(#Codec.DecodeSpells("") > 0)
end)
