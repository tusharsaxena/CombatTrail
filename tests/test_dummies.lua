-- tests/test_dummies.lua — modules/Dummies.lua and defaults/Dummies.lua (race plan Task A2): the
-- seed per client with its categories, the player's own list (one string row, its parse and
-- normalize, add, remove, a built-in switched off and back on, Defaults), what Lookup, Name and
-- CategoryOf answer from the two together, the captures, the History page's Training dummies tab and
-- the `/ct dummy` verb. Ported from DPS Race's test_dummies.lua and test_dummy_list.lua (f8078c7).
-- The seed is Retail's; WoW Forever's is empty by decision, so a case about a built-in lends that
-- client one entry, and every case says the same under both kit profiles.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local GOLEM = 243205                 -- a Retail built-in (boss)
local BOAR = 99999                   -- not a dummy
local function creatureGUID(id) return ("Creature-0-3770-2552-1234-%d-0000ABCDEF"):format(id) end

local function fresh(opts)
    local inst = T.load(opts)
    return inst.NS, inst.mocks
end

-- WoW Forever's seed is empty: lend it the Golem, so a built-in case runs on both clients.
local function lendGolem(NS)
    if NS.DUMMY_SEED[GOLEM] == nil then
        NS.DUMMY_SEED[GOLEM] = { name = "Reinforced Golem", category = "boss" }
    end
end

local function target(m, fields)
    if not fields then
        m.__unitExists.target, m.__unitGUIDs.target, m.__unitNames.target = false, nil, nil
        return
    end
    m.__unitExists.target = true
    m.__unitGUIDs.target = fields.guid
    m.__unitNames.target = fields.name
    m.__classifications.target = fields.classification
    m.__unitLevels.target = fields.level
    m.UnitHealthMax = function() return fields.healthMax end
    m.UnitCreatureType = function() return fields.creatureType end
    m.UnitIsPVP = function() return fields.pvp end
    m.UnitFactionGroup = function() return fields.faction end
    m.UnitReaction = function() return fields.reaction end
end

local function said(M) return table.concat(M.__printed(), "\n") end
local function has(M, want) return said(M):find(want, 1, true) ~= nil end

-- ── the seed ────────────────────────────────────────────────────────────────────────────────────

-- DPS Race's catalog (f8078c7), verbatim. A row is added from a measurement, never guessed.
local CATALOG = {
    { 31146, "Raider's Training Dummy", "boss" }, { 65310, "Turnip Punching Bag", "boss" },
    { 67127, "Training Dummy", "single" }, { 114832, "PvP Training Dummy", "pvp" },
    { 126781, "Training Dummy", "single" }, { 131983, "Raider's Training Dummy", "boss" },
    { 131989, "Training Dummy", "single" }, { 131992, "Dungeoneer's Training Dummy", "dungeoneer" },
    { 144078, "Dungeoneer's Training Dummy", "dungeoneer" }, { 144081, "Training Dummy", "single" },
    { 144082, "Training Dummy", "single" }, { 144085, "Training Dummy", "single" },
    { 144086, "Raider's Training Dummy", "boss" }, { 153285, "Training Dummy", "single" },
    { 153292, "Training Dummy", "single" }, { 189617, "Boulderfist", "boss" },
    { 189632, "Animated Duelist", "boss" }, { 194643, "Dungeoneer's Training Dummy", "dungeoneer" },
    { 194644, "Dungeoneer's Training Dummy", "dungeoneer" }, { 194648, "Training Dummy", "single" },
    { 194649, "Normal Tank Dummy", "single" }, { 196394, "Tuskarr Training Dummy", "boss" },
    { 197833, "PvP Training Dummy", "pvp" }, { 198594, "Cleave Training Dummy", "cleave" },
    { 199057, "Black Dragon's Challenge Dummy", "boss" }, { 216458, "Sparring Dummy", "single" },
    { 219250, "PvP Training Dummy", "pvp" }, { 225976, "Normal Tank Dummy", "single" },
    { 225977, "Dungeoneer's Training Dummy", "dungeoneer" }, { 225978, "Crystalmaw", "boss" },
    { 225982, "Cleave Training Dummy", "cleave" }, { 225983, "Dungeoneer's Training Dummy", "dungeoneer" },
    { 225984, "Training Dummy", "single" }, { 225985, "Kelpfist", "boss" },
    { 243166, "Normal Tank Dummy", "single" }, { 243167, "Dungeoneer's Training Dummy", "dungeoneer" },
    { 243168, "Dungeoneer's Training Dummy", "dungeoneer" }, { 243205, "Reinforced Golem", "boss" },
    { 243206, "Heavyweight Golem", "boss" }, { 243207, "Training Dummy", "single" },
    { 243208, "Cleave Training Dummy", "cleave" }, { 243211, "PvP Training Dummy", "pvp" },
}

test("dummies: the seed is picked once per client; Forever's is empty by decision", function()
    local NS = fresh()
    local want = NS.Compat.IsForever() and NS.DummySeeds.Forever or NS.DummySeeds.Retail
    assertTrue(NS.DUMMY_SEED == want, "the client's seed")
    assertTrue(next(NS.DummySeeds.Forever) == nil, "no Forever dummy creature ID is measured yet")
    local n = 0
    for _ in pairs(NS.DummySeeds.Retail) do n = n + 1 end
    assertEqual(n, #CATALOG, "Retail holds exactly the measured rows")
end)

test("dummies: Lookup answers the seed by creature ID, with its name and category", function()
    local NS = fresh()
    local D, retail = NS.Dummies, not NS.Compat.IsForever()
    for _, row in ipairs(CATALOG) do
        local d = D.Lookup(row[1])
        if retail then
            assertTrue(d ~= nil, "seeded: " .. row[1])
            assertEqual(d.name, row[2])
            assertEqual(d.category, row[3])
            assertEqual(D.Name(row[1]), row[2])
            assertEqual(D.CategoryOf(row[1]), row[3])
        else
            assertNil(d, "a Retail ID is no dummy on WoW Forever: " .. row[1])
        end
    end
    assertNil(D.Lookup(1))
    assertNil(D.Lookup(nil))
    assertNil(D.Lookup("243205"), "the key is a number; the caller converts")
    assertNil(D.Name(1985))
    assertNil(D.CategoryOf(1985), "no dummy, no category")
end)

test("dummies: Lookup answers a copy, so a caller cannot edit the seed", function()
    local NS = fresh()
    lendGolem(NS)
    local d = NS.Dummies.Lookup(GOLEM)
    d.name = "Edited"
    assertEqual(NS.Dummies.Lookup(GOLEM).name, "Reinforced Golem")
end)

test("dummies: five categories in order, each with an enUS label, and Other for no dummy", function()
    local NS = fresh()
    local D = NS.Dummies
    local want = { "single", "cleave", "dungeoneer", "boss", "pvp" }
    assertEqual(table.concat(D.CATEGORIES, ","), table.concat(want, ","))
    local labels = {
        single = "Single target", cleave = "Cleave", dungeoneer = "Dungeoneer",
        boss = "Boss-level", pvp = "PvP", other = "Other",
    }
    for key, label in pairs(labels) do
        assertEqual(D.Label(key), label)
        assertEqual(NS.L[label], label, "the label is a locale key")
    end
    assertEqual(D.Label("nonsense"), "Other", "an unknown category labels as Other")
    for id, d in pairs(NS.DummySeeds.Retail) do
        local known = false
        for _, k in ipairs(D.CATEGORIES) do known = known or k == d.category end
        assertTrue(known, "category of " .. id)
    end
end)

-- ── the stored text ─────────────────────────────────────────────────────────────────────────────

test("dummies: Parse reads entries and hides, ascending, the last of an ID winning", function()
    local D = fresh().Dummies
    local e = D.Parse(" 300:Cleave , -243205, 12:single, 300:boss ")
    assertEqual(#e, 3)
    assertEqual(e[1].id, 12); assertEqual(e[1].category, "single")
    assertEqual(e[2].id, 300); assertEqual(e[2].category, "boss")
    assertEqual(e[3].id, 243205); assertTrue(e[3].hidden)
    assertEqual(#D.Parse(""), 0)
    assertNil(D.Parse("300"), "an entry needs a category")
    assertNil(D.Parse("300:other"), "other is no category a dummy can have")
    assertNil(D.Parse("abc:single"))
    assertNil(D.Parse("0:single"))
    assertNil(D.Parse(42))
    assertNil(D.Parse("99999999999999999999:single"), "past MAX_ID: no integer form to write back")
    assertNil(D.Add(1e20, "single"))
    assertEqual(select(2, D.Resolve("99999999999999999999")), "notFound")
end)

test("dummies: Normalize drops a custom entry for a built-in and a hide of a non-built-in", function()
    local NS = fresh()
    lendGolem(NS)
    local D = NS.Dummies
    assertEqual(D.Normalize("300:cleave,243205:single,-12,-243205"), "300:cleave,-243205")
    assertNil(D.Normalize("300"))
    assertEqual(D.Normalize(""), "")
end)

test("dummies: the row refuses what does not parse and stores what it normalizes", function()
    local NS = fresh()
    lendGolem(NS)
    assertEqual(NS.Dummies.PATH, "dummies.custom")
    assertFalse(NS.SetByPath("dummies.custom", "300") and true or false)
    assertTrue(NS.SetByPath("dummies.custom", "300:Cleave, 243205:boss"))
    assertEqual(NS.db.profile.dummies.custom, "300:cleave")
    local row = NS.FindSchemaRow("dummies.custom")
    assertTrue(row ~= nil and row.skipRender == true, "a row the tab draws as its own list")
    assertEqual(row.default, "")
end)

-- ── the player's own list ───────────────────────────────────────────────────────────────────────

test("dummies: Add marks a creature, Lookup answers it, Remove takes it off", function()
    local NS = fresh()
    local D = NS.Dummies
    assertNil(D.Lookup(BOAR))
    assertEqual(D.Add(BOAR, "cleave"), "added")
    assertEqual(NS.db.profile.dummies.custom, "99999:cleave")
    assertEqual(D.Lookup(BOAR).category, "cleave")
    assertEqual(D.CategoryOf(BOAR), "cleave")
    assertNil(D.Lookup(BOAR).name, "never captured: no name")
    assertNil(D.Add(BOAR, "cleave"), "the same again changes nothing")
    assertEqual(D.Add(BOAR, "single"), "changed")
    assertEqual(D.Lookup(BOAR).category, "single")
    assertNil(D.Add(BOAR, "other"), "no such category")
    assertEqual(D.Remove(BOAR), "removed")
    assertNil(D.Lookup(BOAR))
    assertNil(D.Remove(BOAR), "nothing left to remove")
    assertEqual(NS.db.profile.dummies.custom, "")
end)

test("dummies: a custom dummy added with no category is single target", function()
    local NS = fresh()
    assertEqual(NS.Dummies.Add(BOAR), "added")
    assertEqual(NS.Dummies.CategoryOf(BOAR), "single")
    assertEqual(NS.db.profile.dummies.custom, "99999:single")
end)

test("dummies: a built-in is switched off and back on, never recategorized", function()
    local NS = fresh()
    lendGolem(NS)
    local D = NS.Dummies
    assertNil(D.Add(GOLEM, "single"), "a built-in that is on changes nothing")
    assertEqual(D.CategoryOf(GOLEM), "boss")
    assertEqual(D.Remove(GOLEM), "hidden")
    assertNil(D.Lookup(GOLEM))
    assertEqual(D.BuiltIn(GOLEM).category, "boss", "the seed is untouched")
    assertNil(D.Remove(GOLEM), "already off")
    assertEqual(D.Add(GOLEM, "single"), "restored")
    assertEqual(D.CategoryOf(GOLEM), "boss", "the seed's category comes back")
    assertEqual(NS.db.profile.dummies.custom, "")
end)

test("dummies: Defaults clears the list; a profile switch reads the other profile's", function()
    local NS = fresh()
    lendGolem(NS)
    NS.Dummies.Add(BOAR, "pvp")
    NS.Dummies.Remove(GOLEM)
    assertTrue(NS.Dummies.Defaults())
    assertEqual(NS.db.profile.dummies.custom, "")
    assertEqual(NS.Dummies.CategoryOf(GOLEM), "boss")
    NS.Dummies.Add(BOAR, "pvp")
    NS.db:SetProfile("Other")
    assertNil(NS.Dummies.Lookup(BOAR), "the other profile has no list")
end)

test("dummies: a typed category word is a key or its label; auto and nonsense are none", function()
    local D = fresh().Dummies
    assertEqual(D.CategoryWord("Boss"), "boss")
    assertEqual(D.CategoryWord(" Boss-level "), "boss", "the label works too")
    assertEqual(D.CategoryWord("single target"), "single")
    assertNil(D.CategoryWord("auto"))
    assertNil(D.CategoryWord("sideways"))
    assertNil(D.CategoryWord(nil))
end)

-- ── the fight's content ─────────────────────────────────────────────────────────────────────────

test("dummies: a custom dummy makes a fight's content \"dummy\" on WoW Forever too", function()
    local NS = fresh()
    local function contentOf()
        return NS.Identity.Resolve({ snapshot = NS.Identity.Snapshot() }, nil,
            { { name = "Angry Boar", creatureID = BOAR, total = 9000 } }).content
    end
    assertEqual(contentOf(), "world", "not on any list: open world")
    NS.Dummies.Add(BOAR, "single")
    assertEqual(contentOf(), "dummy", "the player's list counts on " .. (NS.Compat.IsForever() and "Forever" or "Retail"))
    NS.Dummies.Remove(BOAR)
    assertEqual(contentOf(), "world")
end)

test("dummies: a built-in switched off is open-world content again", function()
    local NS, m = fresh()
    lendGolem(NS)
    target(m, { guid = creatureGUID(GOLEM), name = "Reinforced Golem", level = -1 })
    assertEqual(NS.Identity.Snapshot().target.isDummy, true)
    NS.Dummies.Remove(GOLEM)
    local snap = NS.Identity.Snapshot()
    assertEqual(snap.target.isDummy, false)
    assertEqual(NS.Identity.Resolve({ snapshot = snap }, nil, {}).content, "world")
end)

-- ── the captures ────────────────────────────────────────────────────────────────────────────────

test("dummies: Read and Capture keep what the game says, by map, and count the captures", function()
    local NS, m = fresh()
    m.GetZoneText = function() return "Silvermoon City" end
    m.GetSubZoneText = function() return "Training Grounds" end
    m.C_Map = { GetBestMapForUnit = function() return 2393 end,
                GetPlayerMapPosition = function()
                    return { GetXY = function() return 0.41237, 0.6 end }
                end }
    target(m, { guid = creatureGUID(BOAR), name = "Angry Boar", level = 82, classification = "elite",
                healthMax = 5000000, creatureType = "Mechanical", pvp = false, faction = "Neutral",
                reaction = 4 })
    local r = NS.Dummies.Read("target")
    assertEqual(r.creatureID, BOAR)
    assertEqual(r.health, 5000000)
    assertEqual(r.creatureType, "Mechanical")
    assertFalse(r.pvp)
    assertEqual(r.x, 41.24); assertEqual(r.y, 60)
    local c = NS.Dummies.Capture(r)
    assertEqual(c.count, 1)
    assertEqual(c.name, "Angry Boar")
    assertEqual(c.places[2393].zone, "Silvermoon City")
    assertEqual(c.places[2393].subzone, "Training Grounds")
    assertTrue(NS.db.global.dummies.captures[BOAR] == c, "global, by creature ID")
    m.C_Map.GetBestMapForUnit = function() return 84 end
    m.GetZoneText = function() return "Stormwind City" end
    NS.Dummies.Capture()
    assertEqual(c.count, 2, "no argument captures the target")
    assertTrue(c.places[84] ~= nil and c.places[2393] ~= nil, "one line per map")
    assertEqual(NS.Dummies.NameOf(BOAR), "Angry Boar")
    assertNil(NS.Dummies.Lookup(BOAR), "a capture marks nothing")
end)

test("dummies: a sealed field is left out of the read, and a player is no creature", function()
    local NS, m = fresh()
    local restore = T.installSecretValue()
    target(m, { guid = creatureGUID(BOAR), name = "Angry Boar", healthMax = T.secret(5), pvp = T.secret(true) })
    local ok, r = pcall(NS.Dummies.Read, "target")
    restore()
    assertTrue(ok, tostring(r))
    assertNil(r.health)
    assertNil(r.pvp)
    target(m, { guid = "Player-1-00000002", name = "Someone" })
    assertNil(NS.Dummies.Read("target"))
    target(m, nil)
    assertNil(NS.Dummies.Read("target"))
    assertNil(NS.Dummies.Capture(), "nothing to capture")
end)

test("dummies: Resolve takes an ID or a captured or seeded name", function()
    local NS, m = fresh()
    lendGolem(NS)
    local R = NS.Dummies.Resolve
    assertEqual(R("99999"), BOAR)
    assertEqual(R(" reinforced golem "), GOLEM)
    local id, why = R("Angry Boar")
    assertNil(id); assertEqual(why, "notFound")
    target(m, { guid = creatureGUID(BOAR), name = "Angry Boar" })
    NS.Dummies.Capture()
    assertEqual(R("angry boar"), BOAR)
    assertEqual(select(2, R("  ")), "empty")
    assertEqual(select(2, R("0")), "notFound")
end)

test("dummies: a captured custom dummy answers its captured name", function()
    local NS, m = fresh()
    target(m, { guid = creatureGUID(BOAR), name = "Angry Boar" })
    NS.Dummies.Capture()
    NS.Dummies.Add(BOAR, "single")
    assertEqual(NS.Dummies.Lookup(BOAR).name, "Angry Boar")
    assertEqual(NS.Dummies.Name(BOAR), "Angry Boar")
end)

-- ── the History page's Training dummies tab ─────────────────────────────────────────────────────

test("dummies: the Training dummies section is on both clients", function()
    local NS = fresh()
    assertEqual(NS.HISTORY_TABS.dummies, "Training dummies")
    local found = false
    for _, key in ipairs(NS.HISTORY_TAB_ORDER) do found = found or key == "dummies" end
    assertTrue(found, "a History tab on " .. (NS.Compat.IsForever() and "Forever" or "Retail"))
    assertEqual(NS.FindSchemaRow(NS.Dummies.PATH).group, NS.HISTORY_TABS.dummies)
    assertEqual(NS.FindSchemaRow(NS.Dummies.PATH).page, "history")
end)

test("dummies: the row's default empties the list", function()
    local NS = fresh()
    NS.Dummies.Add(BOAR, "pvp")
    assertTrue(NS.ApplyDefault(NS.FindSchemaRow(NS.Dummies.PATH)) ~= false)
    assertEqual(NS.GetSetting(NS.Dummies.PATH), "")
end)

local installIds = dofile(T.root .. "/tests/_kit/mock_ids.lua")

local function walk(w, out)
    for _, child in ipairs(w.children or {}) do
        out[#out + 1] = child
        walk(child, out)
    end
    return out
end

local function drawn(ctx, needle)
    for _, w in ipairs(walk(ctx.scroll, {})) do
        for _, key in ipairs({ "text", "labelText" }) do
            local s = w[key]
            if type(s) == "string" and s:find(needle, 1, true) then return true end
        end
    end
    return false
end

test("dummies: the tab draws Add your target, the list, a box per built-in and Reset list", function()
    local inst = T.load({ mutate = installIds })
    local NS, M = inst.NS, inst.mocks
    M.__subcategories["History"]:__fire("OnShow")
    local ctx = NS.pageCtx.history
    ctx.panel:Show()
    NS.Dummies.Add(BOAR, "cleave")
    M.__resetPrinted()
    NS.Helpers.SelectTab("history", NS.HISTORY_TABS.dummies)
    assertEqual(ctx.activeTab, NS.HISTORY_TABS.dummies)
    for _, label in ipairs({ "Add your target", "Add a creature", "Reset list" }) do
        assertTrue(drawn(ctx, NS.L[label]), label .. " is drawn")
    end
    local forever = NS.Compat.IsForever()
    assertEqual(drawn(ctx, "Reinforced Golem (243205)"), not forever,
        "a checkbox per built-in on Retail, none on WoW Forever")
    assertEqual(drawn(ctx, NS.L["Built-in training dummies. Clear one to stop counting it as a dummy."]), not forever)
    assertEqual(#M.__printed(), 0, "drawn without a line in chat")
end)

test("dummies: Add your target counts the target as single target, and says so with none", function()
    local NS, M = fresh()
    target(M, { guid = creatureGUID(BOAR), name = "Angry Boar" })
    NS.HistoryPage.AddTargetDummy()
    assertEqual(NS.Dummies.CategoryOf(BOAR), "single")
    assertEqual(NS.db.global.dummies.captures[BOAR].count, 1)
    target(M, nil)
    M.__resetPrinted()
    NS.HistoryPage.AddTargetDummy()
    assertTrue(has(M, "Target a creature first."), said(M))
end)

-- ── `/ct dummy` ──────────────────────────────────────────────────────────────────────────────────

test("dummy verb: add marks the target, captures it and says what it saved", function()
    local NS, M = fresh()
    M.GetZoneText = function() return "Silvermoon City" end
    M.GetSubZoneText = function() return "Training Grounds" end
    target(M, { guid = creatureGUID(BOAR), name = "Practice Boar", level = 82, classification = "elite",
                healthMax = 5000000 })
    M.__resetPrinted()
    NS.Slash:OnSlash("dummy add")
    assertEqual(NS.db.profile.dummies.custom, "99999:single", "no word: single target")
    assertTrue(has(M, "Practice Boar (99999) is a training dummy now: Single target."), said(M))
    assertTrue(has(M, "level 82 elite"), said(M))
    assertTrue(has(M, "Silvermoon City, Training Grounds"), said(M))
    assertEqual(NS.db.global.dummies.captures[BOAR].count, 1)
    NS.Slash:OnSlash("dummy add boss")
    assertEqual(NS.db.profile.dummies.custom, "99999:boss", "a typed category wins")
    assertEqual(NS.db.global.dummies.captures[BOAR].count, 2)
    NS.Slash:OnSlash("dummy add boss")
    assertTrue(has(M, "is already a training dummy: Boss-level."), said(M))
end)

test("dummy verb: add refuses a word that is no category, no target, and a player", function()
    local NS, M = fresh()
    target(M, { guid = creatureGUID(BOAR), name = "Angry Boar" })
    M.__resetPrinted()
    NS.Slash:OnSlash("dummy add sideways")
    assertTrue(has(M, "'sideways' is no category."), said(M))
    assertEqual(NS.db.profile.dummies.custom, "")
    target(M, nil)
    NS.Slash:OnSlash("dummy add")
    assertTrue(has(M, "Target a creature first."), said(M))
    target(M, { guid = "Player-1-00000002", name = "Someone" })
    NS.Slash:OnSlash("dummy add")
    assertTrue(has(M, "Your target is not a creature"), said(M))
end)

test("dummy verb: on a built-in, add says so and captures; remove switches it off, add brings it back", function()
    local NS, M = fresh()
    lendGolem(NS)
    target(M, { guid = creatureGUID(GOLEM), name = "Reinforced Golem", level = -1 })
    M.__resetPrinted()
    NS.Slash:OnSlash("dummy add")
    assertTrue(has(M, "Reinforced Golem (243205) is already a built-in training dummy: Boss-level."), said(M))
    assertTrue(NS.db.global.dummies.captures[GOLEM] ~= nil, "a built-in is captured too")
    NS.Slash:OnSlash("dummy remove")
    assertEqual(NS.db.profile.dummies.custom, "-243205")
    assertTrue(has(M, "a built-in training dummy, is switched off."), said(M))
    NS.Slash:OnSlash("dummy add")
    assertEqual(NS.db.profile.dummies.custom, "")
    assertTrue(has(M, "is a training dummy again: Boss-level."), said(M))
end)

test("dummy verb: remove takes a typed creature ID or name; show lists yours and the switched-off", function()
    local NS, M = fresh()
    lendGolem(NS)
    local builtIns = 0
    for _ in pairs(NS.DUMMY_SEED) do builtIns = builtIns + 1 end
    NS.Dummies.Add(BOAR, "single")
    NS.Dummies.Remove(GOLEM)
    M.__resetPrinted()
    NS.Slash:OnSlash("dummy")
    assertTrue(has(M, "Your training dummies:"), said(M))
    assertTrue(has(M, "Creature 99999 \194\183 Single target"), said(M))
    assertTrue(has(M, ("Built-in training dummies: %d, 1 switched off."):format(builtIns)), said(M))
    assertTrue(has(M, "Reinforced Golem (243205) (off)"), said(M))
    NS.Slash:OnSlash("dummy remove 99999")
    assertTrue(has(M, "Creature 99999 is no longer a training dummy."), said(M))
    NS.Slash:OnSlash("dummy remove reinforced golem")
    assertTrue(has(M, "Reinforced Golem (243205) is not a training dummy."), said(M))
    NS.Slash:OnSlash("dummy defaults")
    assertEqual(NS.db.profile.dummies.custom, "")
    assertTrue(has(M, "No training dummies of your own."), said(M))
end)

test("dummy verb: capture saves without marking; an unknown word prints the usage", function()
    local NS, M = fresh()
    target(M, { guid = creatureGUID(BOAR), name = "Angry Boar" })
    M.__resetPrinted()
    NS.Slash:OnSlash("dummy capture")
    assertTrue(has(M, "Saved: Angry Boar (99999)"), said(M))
    assertEqual(NS.db.profile.dummies.custom, "")
    NS.Slash:OnSlash("dummy frobnicate")
    assertTrue(has(M, "Usage: /ct dummy"), said(M))
end)

test("dummy verb: answers while the addon is disabled, on both clients", function()
    local NS, M = fresh()
    NS.Slash:OnSlash("disable")
    NS.Dummies.Add(BOAR, "pvp")
    M.__resetPrinted()
    NS.Slash:OnSlash("dummy show")
    assertTrue(has(M, "Creature 99999 \194\183 PvP"), said(M))
    assertFalse(has(M, NS.Slash:DisabledLine()), "never the refusal line")
end)
