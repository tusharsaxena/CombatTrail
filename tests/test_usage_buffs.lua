-- tests/test_usage_buffs.lua — buffs in Used and no plain food (CombatTrail #13, CL-13b): a seeded buff
-- on at the start is a spell-keyed entry (usage v 2, CT_SCHEMA 5) with the spell's icon and name; the
-- Usage edit and "never show" apply to it, hidden spells stored beside hidden items; a sealed aura
-- ends the walk and lists nothing; plain food and drink (the client's Food & Drink subclass, or an Eat
-- or Drink use spell) are never listed, whatever the signal, and buff food is listed once, through Well
-- Fed; a potion is unchanged; and a v 1 record from before the change still renders.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local POTION, POTION_SPELL = 211001, 431932
local BREAD, BREAD_SPELL = 4540, 7737        -- a plain food (Food & Drink), its Eat aura
-- An invented Other-subclass (8) drink whose use spell is Drink 430: the holiday treats filed under
-- Other. Not Sweet Nectar 19299, which both clients file under Food & Drink (5).
local NECTAR = 900001

local function kinds(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.kind .. ":" .. e.src end
    return table.concat(out, ",")
end

local function c(t, id) return { t = t, spellID = id, unit = "player", interrupted = false } end

-- The active client's seeded buffs the cases use: on WoW Forever, the issue's anchors.
local function seeded(NS)
    if NS.Compat.IsForever() then return 1229741, 460940 end   -- Camp Benefits, Might of Stormwind
    return 15366, 22888                                       -- Songflower Serenade, Rallying Cry
end

local function snapWith(NS, auras)
    return {
        gear = {},
        bags = { [POTION] = { count = 3, subclass = 1, spellID = POTION_SPELL },
                 [BREAD] = { count = 5, subclass = NS.Usage.FOOD_SUBCLASS, spellID = BREAD_SPELL } },
        auras = auras,
    }
end

-- ── detection ───────────────────────────────────────────────────────────────────────────────────

test("usage buffs: the active client's seeded buffs at the start are listed under their spell IDs", function()
    local NS = T.load().NS
    local a, b = seeded(NS)
    assertTrue(NS.Usage.BUFF_SPELLS[a] and NS.Usage.BUFF_SPELLS[b], "both are in the client's seed")
    local used = NS.Usage.Detect(snapWith(NS, {
        { spellID = a, name = "A" }, { spellID = 1459, name = "Arcane Intellect" }, { spellID = b, name = "B" },
        { spellID = a, name = "A" } }), {}, nil)
    assertEqual(kinds(used), "buff:buff,buff:buff", "each seeded buff once; an unseeded aura never")
    assertEqual(used[1].spellID, a)
    assertNil(used[1].itemID, "spell-keyed, no item")
    assertEqual(used[2].spellID, b)
    assertEqual(NS.ResultsUsage.Detail(used[1]), "active at the start")
    assertEqual(NS.Usage.Build(snapWith(NS, {}), {}, nil).v, 2, "the record's format is 2")
end)

test("usage buffs: the other client's buffs are not listed", function()
    local NS = T.load().NS
    local other = NS.Compat.IsForever() and NS.BuffSeeds.Retail or NS.BuffSeeds.Forever
    local mine = NS.Usage.BUFF_SPELLS
    for _, id in ipairs(other.buffs) do
        if not mine[id] then
            assertEqual(#NS.Usage.Detect(snapWith(NS, { { spellID = id } }), {}, nil), 0, "not this client's: " .. id)
            return
        end
    end
end)

test("usage buffs: a sealed aura ends the walk, and a buff after it never produces an entry", function()
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    local id = seeded(NS)
    local sealed = { spellId = id, name = "x" }
    M.__auras = { { 1459, "Arcane Intellect" }, { id, "Seeded" } }
    local real = M.C_UnitAuras.GetAuraDataByIndex
    M.issecrettable = function(t) return t == sealed end
    M.C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
        if i == 1 then return sealed end
        return real(unit, i, filter)
    end
    local snap = NS.Usage.Snapshot()
    assertEqual(#snap.auras, 0, "the walk ended at the sealed aura")
    assertEqual(#NS.Usage.Detect(snap, {}, nil), 0, "nothing listed")
end)

test("usage buffs: plain food eaten at the pull lists nothing (aura up, a pre-pull cast, count dropped)", function()
    local NS = T.load().NS
    local snap = snapWith(NS, { { spellID = BREAD_SPELL, name = "Food" } })
    local used = NS.Usage.Detect(snap, { c(-3, BREAD_SPELL) }, { [POTION] = 3, [BREAD] = 4 })
    assertEqual(#used, 0, "no entry for the bread")
    for _, cand in ipairs(NS.Usage.Candidates(snap)) do
        assertTrue(cand.itemID ~= BREAD, "plain food is not a candidate either")
    end
    assertTrue(NS.Usage.IsPlainFood(snap.bags[BREAD]))
    assertFalse(NS.Usage.IsPlainFood(snap.bags[POTION]))
end)

test("usage buffs: Well Fed lists the food once, never its Eat aura", function()
    local NS = T.load().NS
    local fed = NS.BUFF_SEEDS.wellFed
    assertTrue(#fed >= 2, "the client's Well Fed list")
    local snap = snapWith(NS, { { spellID = BREAD_SPELL, name = "Food" }, { spellID = fed[1] }, { spellID = fed[2] } })
    local used = NS.Usage.Detect(snap, {}, { [POTION] = 3, [BREAD] = 4 })
    assertEqual(kinds(used), "food:buff", "food once, through Well Fed")
    assertNil(used[1].itemID)
    for _, id in ipairs(fed) do assertTrue(NS.Usage.WELL_FED_SPELLS[id], "Well Fed seed " .. id) end
end)

test("usage buffs: a potion is still listed as before", function()
    local NS = T.load().NS
    local snap = snapWith(NS, { { spellID = BREAD_SPELL, name = "Food" } })
    local used = NS.Usage.Detect(snap, { c(4, POTION_SPELL) }, { [POTION] = 2, [BREAD] = 4 })
    assertEqual(kinds(used), "potion:cast")
    assertEqual(used[1].itemID, POTION)
    used = NS.Usage.Detect(snap, {}, { [POTION] = 2, [BREAD] = 5 })
    assertEqual(kinds(used), "potion:bag")
end)

test("usage buffs: an Other consumable whose use spell is an Eat or Drink aura is plain food too", function()
    local inst = T.load({ mutate = function(m)
        m.__itemSpells[NECTAR], m.__itemSpells[POTION] = 430, POTION_SPELL   -- Drink
        m.__itemInfo[NECTAR], m.__itemInfo[POTION] = { 0, 8 }, { 0, 1 }
        m.__bags[0] = { size = 2, [1] = { NECTAR, 4 }, [2] = { POTION, 2 } }
        m.__auras = { { 430, "Drink" } }
    end })
    local NS = inst.NS
    local snap = NS.Usage.Snapshot()
    assertTrue(snap.bags[NECTAR].eats, "its use spell is the client's Drink")
    assertNil(snap.bags[POTION].eats)
    inst.mocks.__bags[0][1] = { NECTAR, 3 }
    assertEqual(#NS.Usage.Detect(snap, {}, NS.Usage.BagCounts()), 0, "the nectar is never listed")
    assertEqual(#NS.Usage.Candidates(snap), 1, "only the potion is a candidate")
end)

test("usage buffs: buff food under another name lists the food once (Dirge's Increased Stamina)", function()
    local NS = T.load().NS
    -- The active client's Well Fed seed holds what a food gives under another name (Well Fed rule 2):
    -- Increased Stamina 25661, the aura Dirge's Kickin' Chimaerok Chops 21023 triggers, on both clients.
    assertTrue(NS.Usage.WELL_FED_SPELLS[25661], "Increased Stamina is in the client's Well Fed seed")
    local snap = snapWith(NS, { { spellID = BREAD_SPELL, name = "Food" }, { spellID = 25661, name = "Increased Stamina" },
                                { spellID = NS.BUFF_SEEDS.wellFed[1] } })
    local used = NS.Usage.Detect(snap, { c(-8, BREAD_SPELL) }, { [POTION] = 3, [BREAD] = 4 })
    assertEqual(kinds(used), "food:buff", "food once, through the buff it gives; never its Eat aura or count")
    assertNil(used[1].itemID)
end)

test("usage buffs: an item first read under sealing is asked again, so plain food stays unlisted", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local sealed = true
        local inst = T.load({ mutate = function(m)
            m.__itemSpells[BREAD], m.__itemSpells[NECTAR] = BREAD_SPELL, 430      -- Drink
            m.__itemInfo[BREAD], m.__itemInfo[NECTAR] = { 0, 5 }, { 0, 8 }
            m.__bags[0] = { size = 2, [1] = { BREAD, 5 }, [2] = { NECTAR, 4 } }
            m.__auras = { { BREAD_SPELL, "Food" }, { 430, "Drink" } }
            local info, name = m.C_Item.GetItemInfoInstant, m.C_Spell.GetSpellName
            m.C_Item.GetItemInfoInstant = function(itemID)
                local a, b, c2, d, e, class, sub = info(itemID)
                if sealed and sub ~= nil then sub = T.secret(sub) end
                return a, b, c2, d, e, class, sub
            end
            m.C_Spell.GetSpellName = function(id)
                if sealed and id == 430 then return T.secret("Drink") end
                return name(id)
            end
        end })
        local NS = inst.NS
        local first = NS.Usage.Snapshot()
        assertEqual(first.bags[BREAD].subclass, 0, "a sealed subclass reads as none this time")
        assertNil(first.bags[NECTAR].eats, "a sealed Drink name is not known as eating this time")
        sealed = false
        local snap = NS.Usage.Snapshot()
        assertEqual(snap.bags[BREAD].subclass, NS.Usage.FOOD_SUBCLASS, "asked again: Food & Drink")
        assertTrue(snap.bags[NECTAR].eats, "asked again: its use spell is the client's Drink")
        inst.mocks.__bags[0] = { size = 2, [1] = { BREAD, 4 }, [2] = { NECTAR, 3 } }
        assertEqual(#NS.Usage.Detect(snap, {}, NS.Usage.BagCounts()), 0, "neither is listed")
        assertEqual(#NS.Usage.Candidates(snap), 0, "nor a candidate")
    end)
    restore()
    assertTrue(ok, tostring(err))
end)

-- ── the section, the edit and never show ────────────────────────────────────────────────────────

local NOW = os.time()

local function fresh()
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        m.StaticPopup_Show = function() end
        m.StaticPopup_Hide = function() end
    end }
    return inst.NS, inst.mocks
end

local n = 0
local function rec(NS, id, usage, schema)
    n = n + 1
    local me = NS.Identity.Who()
    local who = { name = me.name, realm = me.realm, client = me.client, class = me.class or "HUNTER",
                  specID = me.specID, specName = me.specName, ilvl = 721.4 }
    local ident = { content = "world", targetName = "Boar", targetLevel = 10 }
    return {
        schema = schema or NS.Recorder.CT_SCHEMA, id = id, t = NOW - n * 60, duration = 60, status = "final",
        who = who, identity = ident, boardKey = NS.Identity.BoardKey(ident),
        damage = { merged = 60000, player = 60000 }, dps = 1000, meterDps = 1000,
        build = "120105", version = "0.1.0",
        spells = NS.CastCodec.EncodeSpells({ { spellID = 34026, total = 60000, isPet = false } }),
        usage = usage,
    }
end

local function buffUsage(NS)
    local a = seeded(NS)
    return { v = 2, edited = false,
             candidates = { { itemID = POTION, kind = "potion" } },
             used = { { itemID = POTION, kind = "potion", times = { 4 }, n = 1, src = "cast" },
                      { spellID = a, kind = "buff", n = 1, src = "buff" } } }, a
end

local function rowFor(pane, spellID)
    for i, data in ipairs(pane.usage.rows) do
        if data.spellID == spellID then return i, pane.usage.items[i] end
    end
    return nil
end

test("usage buffs: the section and the Used column show a buff with its spell's icon and name", function()
    local NS = fresh()
    local usage, a = buffUsage(NS)
    local r = rec(NS, "a", usage)
    local RU = NS.ResultsUsage
    assertEqual(RU.Count(r), 2)
    local icons = RU.Icons(r)
    assertEqual(icons[2], 136000 + a, "the spell's icon")
    assertEqual(RU.Name(usage.used[2]), "Spell " .. a, "the spell's name")
    assertEqual(RU.Name({ spellID = a, kind = "buff" }), "Spell " .. a)
    assertTrue(NS.Recorder.Save(r))
    assertTrue(NS.Results.ShowFight("a"))
    local pane = NS.Results.__ui().detail
    local _, row = rowFor(pane, a)
    assertTrue(row ~= nil, "a row for the buff")
    assertEqual(row.icon:GetTexture(), 136000 + a)
end)

test("usage buffs: the edit unticks a buff, keeps its row, and ticks it back as detected", function()
    local NS = fresh()
    local U, RU = NS.Usage, NS.ResultsUsage
    local usage, a = buffUsage(NS)
    local r = rec(NS, "a", usage)
    local rows = RU.Rows(r)
    assertEqual(#rows, 2, "the potion candidate and the buff no candidate stands for")
    assertEqual(rows[2].spellID, a)
    local state = RU.Carry(rows)
    state[2] = nil
    assertTrue(U.SetUsed(r, RU.Edits(r, rows, state)))
    assertEqual(#r.usage.used, 1, "the buff is off the list")
    rows = RU.Rows(r)
    assertEqual(rows[2].spellID, a, "its row stays, as a candidate")
    assertNil(rows[2].entry)
    state = RU.Carry(rows)
    state[2] = true
    assertTrue(U.SetUsed(r, RU.Edits(r, rows, state)))
    assertEqual(r.usage.used[2].spellID, a)
    assertEqual(r.usage.used[2].src, "buff", "ticked again: what it was detected as")
    assertEqual(#RU.Rows(r), 2, "no second row for it")
end)

test("usage buffs: never show hides a buff by its spell ID, stored beside the hidden items", function()
    local NS = fresh()
    local U, RU = NS.Usage, NS.ResultsUsage
    local usage, a = buffUsage(NS)
    assertTrue(NS.Recorder.Save(rec(NS, "a", usage)))
    assertTrue(NS.Results.ShowFight("a"))
    local pane = NS.Results.__ui().detail
    pane.usage.edit:__fire("OnClick")
    local _, row = rowFor(pane, a)
    local items
    local saved = NS.OpenMenu
    NS.OpenMenu = function(_, fill)
        items = {}
        fill({ CreateButton = function(_, text, onClick) items[#items + 1] = { label = text, onClick = onClick } end })
    end
    assertTrue(RU.RowMenu(pane, row))
    NS.OpenMenu = saved
    assertEqual(items[1].label, "Never show Spell " .. a)
    items[1].onClick()
    assertTrue(U.HiddenSpellSet()[a], "hidden")
    assertEqual(NS.db.global.usage.hiddenSpells, tostring(a), "account-wide, beside usage.hidden")
    assertEqual(NS.db.global.usage.hidden, "", "the hidden items untouched")
    assertNil(rowFor(pane, a), "the redraw dropped its row")
    assertEqual(#RU.Entries(NS.Recorder.Get("a")), 1, "the potion alone")
    -- A save keeps the hidden buff in the record.
    local i = 1
    pane.usage.state[i] = nil
    pane.usage.save:__fire("OnClick")
    local kept = false
    for _, e in ipairs(NS.Recorder.Get("a").usage.used) do if e.spellID == a then kept = true end end
    assertTrue(kept, "the record keeps the hidden buff")
    assertEqual(table.concat(U.KnownSpells(), ","), tostring(a))
    assertTrue(U.UnhideSpell(a))
    assertFalse(U.UnhideSpell(a), "not hidden any more")
    assertFalse(U.HideSpell(-1), "no such spell")
    assertFalse(U.HiddenSet()[a], "a spell ID never hides an item")
end)

test("usage buffs: the hidden buffs row validates and normalizes like the hidden items", function()
    local NS = fresh()
    local U = NS.Usage
    assertEqual(NS.GetSetting(U.HIDDEN_SPELLS_PATH), "", "empty by default")
    assertTrue(NS.SetByPath(U.HIDDEN_SPELLS_PATH, "9, 2"))
    assertEqual(NS.GetSetting(U.HIDDEN_SPELLS_PATH), "2,9")
    assertEqual(table.concat(U.HiddenSpellList(), ","), "2,9")
    assertFalse(NS.SetByPath(U.HIDDEN_SPELLS_PATH, "2,x") and true or false, "refused")
end)

test("usage buffs: Compare matches a buff across two fights by its spell", function()
    local NS = fresh()
    local ua, a = buffUsage(NS)
    local ub = buffUsage(NS)
    local rows = NS.ResultsCompare.UsageRows(rec(NS, "a", ua), rec(NS, "b", ub))
    assertEqual(#rows, 2)
    assertEqual(rows[2].spellID, a)
    assertTrue(rows[2].a ~= nil and rows[2].b ~= nil, "one row, both sides")
end)

-- ── the older record (migration) ────────────────────────────────────────────────────────────────

test("usage buffs: a CT_SCHEMA 4 record's v 1 usage still renders, its plain food left out", function()
    local NS = fresh()
    assertTrue(NS.Recorder.CT_SCHEMA >= 5, "usage v 2 arrived with CT_SCHEMA 5")
    local old = rec(NS, "old", { v = 1, edited = false,
        candidates = { { itemID = POTION, kind = "potion" }, { itemID = BREAD, kind = "food" } },
        used = { { itemID = POTION, kind = "potion", times = { 4 }, n = 1, src = "cast" },
                 { itemID = BREAD, kind = "food", times = { -6 }, n = 1, src = "cast" },
                 { kind = "food", n = 1, src = "buff" } } }, 4)
    assertTrue(NS.Recorder.Save(old))
    local r = NS.Recorder.Get("old")
    assertTrue(r ~= nil, "listed")
    assertEqual(r.schema, 4, "not rewritten")
    assertEqual(r.usage.v, 1)
    local RU = NS.ResultsUsage
    local entries = RU.Entries(r)
    assertEqual(#entries, 2, "the potion and Well Fed; the eaten bread never")
    assertEqual(entries[1].itemID, POTION)
    assertEqual(RU.Name(entries[2]), "Well Fed")
    local rows = RU.Rows(r)
    assertEqual(#rows, 2, "the edit lists the potion and Well Fed, not the bread")
    assertTrue(NS.Results.ShowFight("old"))
    assertEqual(#NS.Results.__ui().detail.usage.rows, 2)
    -- A save keeps the bread in the record, unlisted.
    assertTrue(NS.Usage.SetUsed(r, RU.Edits(r, rows, RU.Carry(rows))))
    local kept = false
    for _, e in ipairs(r.usage.used) do if e.itemID == BREAD then kept = true end end
    assertTrue(kept)
end)
