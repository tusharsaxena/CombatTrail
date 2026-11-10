-- tests/test_hud_breakdown.lua — the DPS HUD's spell rows (plan Task 3.2, spec §6): live, the
-- player's spells then the pet's in the meter's own order, every bar scaled to the player source's
-- maxAmount and handed the spell's total, all of it the meter's secrets, never sorted or computed;
-- the pet's rows carry the paw and `hud.spells.petColor`; the fight-over card's rows are the plain
-- merged read, highest first, each with its share; `hud.spells.rows` caps them, 0 shows every one
-- and the wheel scrolls.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse
local H = dofile(T.root .. "/tests/hud_fixture.lua")(T)
local near = H.near

local PETFIGHT = { damage = 40000, dps = 1000, duration = 40,
                   spells = { { id = 11366, dmg = 10000, dps = 250 }, { id = 133, dmg = 30000, dps = 750 } },
                   pet = { damage = 8000, dps = 200,
                           spells = { { id = 17253, dmg = 5000, dps = 125 }, { id = 16827, dmg = 3000, dps = 75 } } },
                   enemies = { { name = "Angry Boar", creatureID = 1985, damage = 48000 } } }

-- Fight 1 live from 10 with every meter value secret.
local function secretFight()
    local inst, meter, Hud = H.fresh({ pet = true })
    meter.SetSession(1, PETFIGHT)
    H.enter(inst, 10)
    meter.SetSecret(true)
    H.run(inst, 10.25)
    H.hit(inst, 11, 1)
    H.tick(inst, 11.25, 13)
    return inst, meter, Hud
end

local function rows(Hud, key)
    local body = H.body(Hud, key)
    return body.parts.spells.list:Rows(), body
end

test("breakdown never sorts or computes in combat (mock secret values)", function()
    local inst, meter, Hud = secretFight()
    local list = rows(Hud, "live")
    assertEqual(#list, 4, "two player spells, then two pet spells")
    local order = {}
    for i, row in ipairs(list) do
        local value = row.bar:GetValue()
        local _, max = row.bar:GetMinMaxValues()
        assertTrue(T.isSecret(value), "row " .. i .. ": the spell's total, the meter's secret")
        assertTrue(T.isSecret(max), "row " .. i .. ": scaled to a secret maxAmount")
        assertEqual(T.reveal(max), 30000, "row " .. i .. ": the PLAYER source's maxAmount, pet rows too")
        assertTrue(T.isSecret(row.spellID), "the ID kept as the meter's handle")
        order[i] = T.reveal(row.spellID)
        assertTrue(T.isSecret(row.amount:GetText()), "the amount is the formatter's (here the secret itself)")
        assertFalse(row.pct:IsShown(), "no share in combat")
    end
    assertEqual(table.concat(order, ","), "11366,133,17253,16827", "the meter's own order, player then pet")
    assertEqual(T.reveal(list[1].bar:GetValue()), 10000)
    assertEqual(T.reveal(list[4].bar:GetValue()), 3000)
    meter.SetSecret(false)
    assertTrue(inst ~= nil)
end)

test("breakdown: pet rows carry paw and pet color", function()
    local inst, meter, Hud = secretFight()
    local NS = inst.NS
    local list = rows(Hud, "live")
    local paw = NS.Icon("ph:paw-print")
    assertTrue(paw ~= nil, "the paw is a declared catalog icon")
    for i, row in ipairs(list) do
        local pet = i > 2
        assertEqual(row.isPet, pet, "row " .. i)
        assertEqual(row.paw:IsShown(), pet, "row " .. i .. ": the paw only on a pet row")
        local r, g, b, a = row.bar:GetStatusBarColor()
        local want = pet and NS.db.profile.hud.spells.petColor or NS.db.profile.hud.spells.barColor
        near(r, want.r, "row " .. i .. " r")
        near(g, want.g, "row " .. i .. " g")
        near(b, want.b, "row " .. i .. " b")
        near(a, pet and want.a or NS.db.profile.hud.spells.barAlpha, "row " .. i .. " alpha")
    end
    assertEqual(list[3].paw:GetTexture(), paw)
    H.setHud(inst, "spells.paw", false)
    H.tick(inst, 13.25, 13.5)
    list = rows(Hud, "live")
    assertFalse(list[3].paw:IsShown(), "hud.spells.paw off: no paw")
    meter.SetSecret(false)
end)

test("breakdown: the over card's rows are merged, highest first, with their shares", function()
    local inst, meter, Hud = H.fresh({ pet = true })
    H.whole(inst, meter, 1, PETFIGHT, 10, 40)
    assertEqual(Hud.State(), "over")
    local list = rows(Hud, "over")
    local ids, pcts = {}, {}
    for i, row in ipairs(list) do
        ids[i] = row.spellID
        pcts[i] = row.pct:GetText()
        assertTrue(row.pct:IsShown())
    end
    assertEqual(table.concat(ids, ","), "133,11366,17253,16827")
    assertEqual(table.concat(pcts, ","), "62.5%,20.8%,10.4%,6.2%", "each spell's share of 48000")
    assertTrue(list[3].isPet and list[3].paw:IsShown(), "the pet's rows keep the paw")
    local _, max = list[2].bar:GetMinMaxValues()
    assertEqual(max, 30000, "scaled to the top spell")
    assertEqual(list[1].name:GetText(), "Spell 133")
end)

test("breakdown: hud.spells.rows caps the rows; 0 shows every one and the wheel scrolls", function()
    local inst, meter, Hud = H.fresh({ pet = true })
    H.whole(inst, meter, 1, PETFIGHT, 10, 40)
    H.setHud(inst, "spells.rows", 2)
    local list, body = rows(Hud, "over")
    assertEqual(#list, 2)
    local before = body.height
    H.setHud(inst, "spells.rows", 0)
    list = rows(Hud, "over")
    assertEqual(#list, 4, "every spell")
    assertTrue(body.height > before, "the window grows with the rows")
    local States = inst.NS.HudStates
    local all = States.ALL_ROWS
    States.ALL_ROWS = 2
    Hud.Refresh()
    list = rows(Hud, "over")
    assertEqual(#list, 2, "0 shows ALL_ROWS at once")
    assertEqual(list[1].spellID, 133)
    body.parts.spells.frame:__fire("OnMouseWheel", -1)
    list = rows(Hud, "over")
    assertEqual(list[1].spellID, 11366, "the wheel scrolled one row")
    body.parts.spells.frame:__fire("OnMouseWheel", -5)
    list = rows(Hud, "over")
    assertEqual(list[1].spellID, 17253, "held at the last full window")
    States.ALL_ROWS = all
end)

test("breakdown: the layout's spell rows off hides them", function()
    local inst, meter, Hud = H.fresh({ pet = true })
    H.start(inst, meter, 1, PETFIGHT, 10)
    H.setHud(inst, "layout.spells", false)
    local body = H.body(Hud, "live")
    assertFalse(body.parts.spells.frame:IsShown())
    assertTrue(inst ~= nil)
end)
