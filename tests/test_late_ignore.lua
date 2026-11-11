-- tests/test_late_ignore.lua — the late-cast ignore list (Race mode plan Task B1, modules/LateIgnore.lua),
-- DPS Race's module cases (its tests/test_late_ignore.lua @f8078c7) on Combat Trail's store: the
-- hearthstone table's pins; the setting's parse, normalize and join; the read memo and the 8690
-- expansion; what a typed spell resolves to (a number, a link, a hearthstone's name, a default the
-- character does not know, a degraded load); the known spells over the saved races; the read-time
-- re-score through a profile switch and the clean board it drops; the menu's entries. The writes
-- (Ignore, Unignore, Reset through the seam) wait for the list's schema row, Task B3's. Both kit
-- profiles: a saved race is account-wide, so WoW Forever re-scores it too.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local DEFAULT = "66,1856,5384,8690,58984,110959"
local FEIGN, VANISH, HEARTH, INCINERATE = 5384, 1856, 8690, 29722
local TOY, ASTRAL = 191329, 556   -- a toy hearthstone (also named "Hearthstone"), and a class spell

-- The client's spell names the cases read: three IDs share "Hearthstone", as in the live data.
local NAMES = {
    [FEIGN] = "Feign Death", [VANISH] = "Vanish", [HEARTH] = "Hearthstone", [TOY] = "Hearthstone",
    [401802] = "Hearthstone", [231504] = "Town Portal", [INCINERATE] = "Incinerate", [ASTRAL] = "Astral Recall",
    [66] = "Invisibility", [58984] = "Shadowmeld", [110959] = "Greater Invisibility",
}

local function named(M)
    M.C_Spell = {
        GetSpellName = function(id) return NAMES[id] end,
        GetSpellTexture = function(id) return 1000 + id end,
        -- The library's spell info: by ID any spell; by name none (the character knows none of these).
        GetSpellInfo = function(key)
            if type(key) ~= "number" or not NAMES[key] then return nil end
            return { name = NAMES[key], iconID = 1000 + key }
        end,
    }
end

local function fresh()
    local inst = T.load({ mutate = named })
    return inst.NS, inst.mocks
end

local function joined(list) return table.concat(list, ",") end

local function late(...)
    local out = {}
    for i, c in ipairs({ ... }) do out[i] = { t = c[1], spellID = c[2] } end
    return out
end

-- A saved race (the stored shape) with its late casts; `t` is its start.
local function savedRace(NS, id, t, dps, casts)
    local r = {
        schema = 4, id = id, t = t, duration = 30, status = "final", dps = dps,
        who = { name = "Traxex", realm = "Area 52", client = NS.Compat.ClientKey(), class = "HUNTER", specID = 253 },
        identity = { content = "dummy", targetName = "Training Dummy", targetCreatureID = 31146, targetLevel = 80,
                     difficultyID = 0 },
        damage = { merged = dps * 30 },
        race = { length = 30, kind = "boss", status = "complete", score = dps * 30, dps = dps, grace = 1,
                 flags = { lateCasts = casts or {}, reloaded = false, died = false } },
    }
    r.boardKey = NS.Identity.BoardKey(r.identity)
    NS.db.global.fights[id] = r
    table.insert(NS.db.global.fightOrder, 1, id)
    return r
end

-- ── the hearthstone table ───────────────────────────────────────────────────────────────────────

test("late ignore: the hearthstone table holds 59 positive IDs, once each, with 8690, Dalaran and Garrison, never 556", function()
    local list, seen = T.NS.HEARTHSTONE_SPELLS, {}
    assertEqual(#list, 59, "the count from the build in the file's header")
    for _, id in ipairs(list) do
        assertTrue(type(id) == "number" and id >= 1 and id % 1 == 0, tostring(id))
        assertFalse(seen[id] == true, "listed twice: " .. tostring(id))
        seen[id] = true
    end
    assertEqual(list[1], HEARTH)
    assertTrue(seen[222695] and seen[171253], "the Dalaran and Garrison hearthstones")
    assertNil(seen[ASTRAL], "Astral Recall is a class spell, never a variant")
    assertTrue(T.NS.LateIgnore.IsHearthstone(TOY))
    assertFalse(T.NS.LateIgnore.IsHearthstone(FEIGN))
end)

-- ── the stored text ─────────────────────────────────────────────────────────────────────────────

test("late ignore: the setting parses sorted and once each, refuses anything else, and joins back", function()
    local LI = T.NS.LateIgnore
    assertEqual(joined(LI.Parse(" 5384, 66,5384 ,, 1856 ")), "66,1856,5384")
    assertEqual(#LI.Parse(""), 0)
    assertNil(LI.Parse("66,abc"))
    assertNil(LI.Parse("0"))
    assertNil(LI.Parse("1.5"))
    assertNil(LI.Parse(66))
    assertEqual(LI.Join({ 5384, 66 }), "66,5384")
    assertEqual(LI.Normalize("5384, 66"), "66,5384")
    assertNil(LI.Normalize("x"))
end)

test("late ignore: Normalize drops a variant while 8690 is listed and keeps it alone", function()
    local LI = T.NS.LateIgnore
    assertEqual(LI.Normalize("191329, 8690, 5384"), "5384,8690", "8690 already covers the toy")
    assertEqual(LI.Normalize("191329,5384"), "5384,191329", "on its own the variant stays")
end)

test("late ignore: the default is the profile's, and 8690 stands for every hearthstone in Set only", function()
    local NS = fresh()
    local LI = NS.LateIgnore
    assertEqual(LI.DEFAULT, NS.defaults.profile.race.lateIgnore)
    assertEqual(LI.DEFAULT, DEFAULT)
    assertEqual(NS.GetSetting(LI.PATH), DEFAULT)
    assertEqual(joined(LI.List()), DEFAULT, "one entry for the hearthstones")
    local set = LI.Set()
    for _, id in ipairs(NS.HEARTHSTONE_SPELLS) do assertTrue(set[id], "variant " .. id) end
    assertTrue(set[FEIGN] and set[VANISH])
    assertNil(set[ASTRAL])
    assertTrue(LI.Set() == set, "one parse while the text holds")
    assertTrue(LI.IsIgnored(TOY))
    assertFalse(LI.IsIgnored(nil), "a sealed cast is never ignored")
    assertFalse(LI.IsIgnored(INCINERATE))
    NS.db.profile.race.lateIgnore = "5384"
    assertFalse(LI.Set() == set, "a new text, a new parse")
    assertFalse(LI.IsIgnored(TOY))
    -- The list's entry that ignores a spell: itself, or 8690 for a variant only it covers.
    NS.db.profile.race.lateIgnore = DEFAULT
    assertEqual(LI.Covering(TOY), HEARTH)
    assertEqual(LI.Covering(FEIGN), FEIGN)
    assertNil(LI.Covering(INCINERATE))
end)

-- ── what a typed spell is ───────────────────────────────────────────────────────────────────────

test("late ignore: Resolve takes a number, a link, a hearthstone's name and a default the character does not know", function()
    local NS = fresh()
    local LI = NS.LateIgnore
    local id, name, icon = LI.Resolve("5384")
    assertEqual(id, FEIGN)
    assertEqual(name, "Feign Death")
    assertEqual(icon, 1000 + FEIGN)
    assertEqual((LI.Resolve(FEIGN)), FEIGN, "a number as a number")
    assertEqual((LI.Resolve("|cff71d5ff|Hspell:1856:0|h[Vanish]|h|r")), VANISH)
    assertEqual((LI.Resolve(" hearthstone ")), HEARTH, "the word")
    assertEqual((LI.Resolve("Hearthstone")), HEARTH, "three IDs share the name: never ambiguous")
    assertEqual((LI.Resolve("town portal")), HEARTH, "a variant's own name")
    assertEqual((LI.Resolve(tostring(TOY))), TOY, "a variant by ID stays itself")
    assertEqual((LI.Resolve("Vanish")), VANISH, "a Hunter cannot look it up; the defaults are candidates")
    local none, why = LI.Resolve("Frostbolt")
    assertNil(none)
    assertEqual(why, "notFound")
    none, why = LI.Resolve("  ")
    assertNil(none)
    assertEqual(why, "empty")
    -- A spell a saved race cast late is a candidate too.
    savedRace(NS, "a", 5, 100, late({ 1.4, INCINERATE }))
    assertEqual((LI.Resolve("incinerate")), INCINERATE)
end)

test("late ignore: a variant's name resolves to that variant when it is listed on its own, else to 8690", function()
    local NS = fresh()
    local LI = NS.LateIgnore
    NS.db.profile.race.lateIgnore = "66,231504"
    local id, name = LI.Resolve("Town Portal")
    assertEqual(id, 231504, "the listed variant, so remove finds it")
    assertEqual(name, "Town Portal")
    assertEqual((LI.Resolve("hearthstone")), HEARTH, "no listed variant carries the name")
    NS.db.profile.race.lateIgnore = "66"
    assertEqual((LI.Resolve("town portal")), HEARTH, "nothing listed: every hearthstone")
    NS.db.profile.race.lateIgnore = "8690,231504"
    assertEqual((LI.Resolve("town portal")), HEARTH, "8690 covers it")
end)

test("late ignore: on a degraded load a number, a link and a hearthstone still resolve", function()
    local inst = T.load({ libFiles = {}, mutate = named })
    local LI = inst.NS.LateIgnore
    assertEqual((LI.Resolve("5384")), FEIGN)
    assertEqual((LI.Resolve("spell:1856")), VANISH)
    assertEqual((LI.Resolve("Hearthstone")), HEARTH)
    assertNil((LI.Resolve("Vanish")), "the name lookup is the library's")
end)

test("late ignore: the known spells are every late cast's spell, newest race first, then the defaults", function()
    local NS = fresh()
    savedRace(NS, "a", 10, 100, late({ 1.4, INCINERATE }, { 2, FEIGN }))
    savedRace(NS, "b", 20, 100, late({ 3, 17962 }, { 4 }))
    savedRace(NS, "c", 30, 100)
    NS.db.global.fights.d = { id = "d", t = 40, dps = 5 }      -- a plain fight: no race part
    assertEqual(joined(NS.LateIgnore.KnownSpells()), "17962,29722,5384,66,1856,8690,58984,110959")
end)

-- ── the readers ─────────────────────────────────────────────────────────────────────────────────

test("late ignore: a profile switch re-scores the flags by the other profile's list and drops the clean board", function()
    local NS = fresh()
    local f = savedRace(NS, "f", 1, 900, late({ 1.4, FEIGN }))
    local c = savedRace(NS, "c", 2, 500)
    NS.Bests.Invalidate()
    assertFalse(NS.RaceRecord.Flagged(f), "Feign Death is on the default list")
    assertEqual(NS.Bests.CleanFor(c), f)
    NS.db:SetProfile("Other")
    NS.HideSkinPicker()
    NS.db.profile.race.lateIgnore = ""
    NS.AnnounceSettingsChanged(NS.LateIgnore.PATH, "")
    assertTrue(NS.RaceRecord.Flagged(f), "the other profile ignores nothing")
    assertEqual(NS.Bests.CleanFor(c), c, "the list's change dropped the cached clean board")
    NS.db:SetProfile("Default")
    assertFalse(NS.RaceRecord.Flagged(f))
    assertEqual(NS.Bests.CleanFor(c), f, "the switch dropped it again")
end)

-- ── the menu ────────────────────────────────────────────────────────────────────────────────────

test("late ignore: the menu offers each counted spell once, the undo for each ignored one, nothing for a sealed cast", function()
    local NS = fresh()
    local r = savedRace(NS, "m", 1, 100, late({ 1.4, FEIGN }, { 2.0, INCINERATE }, { 2.5, INCINERATE }, { 3 },
        { 4, TOY }))
    local e = NS.LateIgnore.MenuEntries(r)
    assertEqual(#e, 3)
    assertEqual(e[1].text, "Ignore Incinerate for late casts")
    assertEqual(e[1].id, INCINERATE)
    assertTrue(e[1].ignore)
    assertEqual(e[2].text, "Stop ignoring Feign Death")
    assertFalse(e[2].ignore)
    assertEqual(e[3].text, "Stop ignoring all hearthstones", "a variant only 8690 covers")
    assertEqual(#NS.LateIgnore.MenuEntries(r.race), 3, "the race part answers as its record does")
    assertTrue(NS.LateIgnore.Offers(r))
    local clean = savedRace(NS, "c", 2, 100)
    assertEqual(#NS.LateIgnore.MenuEntries(clean), 0)
    assertFalse(NS.LateIgnore.Menu(clean, {}), "nothing to offer, no menu")
    assertFalse(NS.LateIgnore.Offers({ id = "fight", dps = 5 }), "a fight has no late casts")
end)

test("late ignore: Label names a spell, the hearthstones' entry and an unknown one", function()
    local NS = fresh()
    local LI = NS.LateIgnore
    assertEqual(LI.Label(FEIGN), "Feign Death (5384)")
    assertEqual(LI.Label(HEARTH), "Hearthstone, all variants (8690)")
    assertEqual(LI.Label(424242), "Unknown spell (424242)")
end)
