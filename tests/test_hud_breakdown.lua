-- tests/test_hud_breakdown.lua — the DPS HUD's spell rows (plan Task 3.2, spec §6): live, the
-- player's spells then the pet's in the meter's own order, every bar scaled to the player source's
-- maxAmount and handed the spell's total, all of it the meter's secrets, never sorted or computed;
-- the pet's rows carry the paw and `hud.spells.petColor`; the fight-over card's rows are the plain
-- merged read, highest first, each with its share; `hud.bars` caps them and the wheel scrolls past
-- the cap (v0.2 Task B3; the size model itself is tests/test_hud_sizing.lua's).

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
        -- No share in combat: with a pet out the column draws the meter's creature name instead,
        -- blank here (a separate pet source names none).
        assertEqual(row.pct:GetText(), "", "no share in combat")
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

test("breakdown: a folded pet row the meter names a creature on draws as the pet's, live", function()
    local inst, meter, Hud = H.fresh({ pet = true })
    meter.SetSession(1, { damage = 2000, dps = 100, duration = 20, pet = false,
        spells = { { id = 6603, dmg = 900, dps = 45 }, { id = 6603, dmg = 700, dps = 35, creature = "Wolf" },
                   { id = 17253, dmg = 400, dps = 20, creature = "Wolf" } },
        enemies = { { name = "Angry Boar", creatureID = 1985, damage = 2000 } } })
    H.enter(inst, 10)
    H.run(inst, 10.25)
    H.hit(inst, 11, 1)
    H.tick(inst, 11.25, 13)
    -- Plain (the meter answering out of combat): the named rows are the pet's.
    local list = rows(Hud, "live")
    local marks = {}
    for i, row in ipairs(list) do marks[i] = row.isPet and "p" or "-" end
    assertEqual(table.concat(marks), "-pp", "the owner's melee, then the pet's melee and Bite")
    assertTrue(list[2].paw:IsShown(), "the paw on the pet's melee")
    -- In combat the name is secret: no row can be colored by it, but the share column draws it.
    meter.SetSecret(true)
    H.tick(inst, 13.25, 14)
    list = rows(Hud, "live")
    marks = {}
    for i, row in ipairs(list) do marks[i] = row.isPet and "p" or "-" end
    assertEqual(table.concat(marks), "---", "a secret name colors nothing")
    assertTrue(list[2].pct:IsShown(), "the name column is up while a pet is out")
    assertTrue(T.isSecret(list[2].pct:GetText()), "the pet's name, handed on untouched")
    assertEqual(T.reveal(list[2].pct:GetText()), "Wolf")
    assertEqual(list[1].pct:GetText(), "", "the owner's row draws no name")
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
    -- The share wears the amount's color, face and flags, a little smaller (owner, 2026-11-11).
    H.setHud(inst, "spells.fontFlags", "OUTLINE")
    list = rows(Hud, "over")
    local pct, amount = list[1].pct, list[1].amount
    local pf, ps, pfl = pct:GetFont()
    local af, as, afl = amount:GetFont()
    assertEqual(pf, af, "the amount's face")
    assertEqual(pfl, afl, "the amount's flags")
    assertEqual(pfl, "OUTLINE")
    assertEqual(ps, as - inst.NS.HudBreakdown.PCT_SMALLER, "a little smaller")
    local pr, pg, pb = pct:GetTextColor()
    local ar, ag, ab = amount:GetTextColor()
    assertEqual(pr, ar)
    assertEqual(pg, ag)
    assertEqual(pb, ab)
end)

test("breakdown: hud.bars caps the rows and the wheel scrolls past them", function()
    local inst, meter, Hud = H.fresh({ pet = true })
    H.whole(inst, meter, 1, PETFIGHT, 10, 40)
    H.setHud(inst, "sizeMode", "auto")
    H.setHud(inst, "bars", 2)
    local list, body = rows(Hud, "over")
    assertEqual(#list, 2)
    assertEqual(list[1].spellID, 133)
    local before = body.height
    H.setHud(inst, "bars", 4)
    list = rows(Hud, "over")
    assertEqual(#list, 4, "every spell")
    assertTrue(body.height > before, "an auto-grow window grows with the rows")
    H.setHud(inst, "bars", 2)
    body.parts.spells.frame:__fire("OnMouseWheel", -1)
    list = rows(Hud, "over")
    assertEqual(list[1].spellID, 11366, "the wheel scrolled one row")
    body.parts.spells.frame:__fire("OnMouseWheel", -5)
    list = rows(Hud, "over")
    assertEqual(list[1].spellID, 17253, "held at the last full window")
end)

test("breakdown: the layout's spell rows off hides them", function()
    local inst, meter, Hud = H.fresh({ pet = true })
    H.start(inst, meter, 1, PETFIGHT, 10)
    H.setHud(inst, "layout.spells", false)
    local body = H.body(Hud, "live")
    assertFalse(body.parts.spells.frame:IsShown())
    assertTrue(inst ~= nil)
end)

test("hud: the live DPS figures are written whole through the rate path; Damage is not", function()
    local inst = secretFight()
    local NS = inst.NS
    local seen = {}
    local rate, number = NS.Format.Rate, NS.Format.Number
    NS.Format.Rate = function(v) seen[#seen + 1] = "rate"; return rate(v) end
    NS.Format.Number = function(v) seen[#seen + 1] = "number"; return number(v) end
    H.tick(inst, 13.25, 14)
    NS.Format.Rate, NS.Format.Number = rate, number
    local rates = 0
    for _, k in ipairs(seen) do if k == "rate" then rates = rates + 1 end end
    assertTrue(rates >= 2, "your DPS and the pet's: " .. table.concat(seen, ","))
end)

test("hud: the DPS box shows your pet's DPS too; your figures share a color, the pet's another", function()
    local inst, meter, Hud = secretFight()
    local NS = inst.NS
    local C = NS.HudStates.COLORS
    local live = H.body(Hud, "live").w.dps
    assertTrue(live.petValue:IsShown(), "the Pet row is up live")
    assertTrue(T.isSecret(live.petValue:GetText()), "the pet's rate, the meter's secret")
    assertEqual(T.reveal(live.petValue:GetText()), 200)
    local dmg = H.body(Hud, "live").w.damage
    local r, g, b = live.value:GetTextColor()
    local dr, dg, db = dmg.value:GetTextColor()
    assertEqual(r, dr, "your DPS in your Damage's color")
    assertEqual(g, dg)
    assertEqual(b, db)
    local pr, pg, pb = live.petValue:GetTextColor()
    assertEqual(pr, C.pet[1], "the pet's DPS in the softer skin hue")
    assertEqual(pg, C.pet[2])
    assertEqual(pb, C.pet[3])
    local qr, qg, qb = dmg.petValue:GetTextColor()
    assertEqual(qr, pr, "the pet's damage in the same hue")
    assertEqual(qg, pg)
    assertEqual(qb, pb)
    assertTrue(pr ~= r or pg ~= g or pb ~= b, "yours and the pet's differ")
    meter.SetSecret(false)
    H.finish(inst, 10, 40)
    assertEqual(Hud.State(), "over")
    local over = H.body(Hud, "over").w.dps
    assertTrue(over.petValue:IsShown(), "the Pet row on the card")
    assertEqual(over.petValue:GetText(), NS.Format.Number(200))
end)

test("breakdown: every other spell row is faintly tinted, on the HUD and in the fight detail (2026-11-11)", function()
    local inst, meter, Hud = secretFight()
    local list = rows(Hud, "live")
    local NS = inst.NS
    assertEqual(list[1].stripe:GetTexture(), NS.Style.WHITE, "a white texture the tint shows on")
    local _, _, _, a1 = list[1].stripe:GetVertexColor()
    local _, _, _, a2 = list[2].stripe:GetVertexColor()
    assertEqual(a1, 0, "the first row untinted")
    assertEqual(a2, NS.Style.Tok("ct.list.stripe")[4], "the second tinted")
    meter.SetSecret(false)
end)

-- A client whose PixelUtil makes one physical pixel `px` UI units (a UI scale that is not round);
-- the mock client has none, so every other case draws at 1. The kit's frames keep no anchors, so
-- each frame made here records its own (`GetPoint`). Fight 1 live from 10, as secretFight's.
local function pixelFight(px)
    local inst, meter, Hud = H.fresh({ pet = true, mutate = function(m)
        m.PixelUtil = { GetPixelToUIUnitFactor = function() return px end }
        local create = m.CreateFrame
        m.CreateFrame = function(...)
            local f = create(...)
            local points = {}
            rawset(f, "SetPoint", function(_, ...) points[#points + 1] = { ... } end)
            rawset(f, "ClearAllPoints", function() for k in pairs(points) do points[k] = nil end end)
            rawset(f, "GetPoint", function(_, n) return unpack(points[n or 1] or {}) end)
            return f
        end
    end })
    meter.SetSession(1, PETFIGHT)
    H.enter(inst, 10)
    meter.SetSecret(true)
    H.run(inst, 10.25)
    H.hit(inst, 11, 1)
    H.tick(inst, 11.25, 13)
    return inst, meter, Hud
end

local function whole(v, px, what)
    local n = v / px
    assertTrue(math.abs(n - math.floor(n + 0.5)) < 1e-6, what .. ": " .. v .. " is not whole pixels at " .. px)
end

test("breakdown: the snapped rows are whole pixels, never taller than the layout's room (2026-11-11)", function()
    local inst = H.fresh({ pet = true })
    local B = inst.NS.HudBreakdown
    for _, px in ipairs({ 1, 0.7, 0.533, 1.25 }) do
        local h, pitch, gap = B.Snapped(px)
        whole(h, px, "height")
        whole(pitch, px, "pitch")
        whole(gap, px, "gap")
        assertTrue(gap >= px - 1e-6, "a gap of a pixel at least at " .. px)
        assertTrue(pitch <= B.Pitch() + 1e-6, "never past the configured pitch at " .. px)
        assertTrue(math.abs(h + gap - pitch) < 1e-6, "height and gap make the pitch")
    end
    local h, pitch, gap = B.Snapped(1)
    assertEqual(h, B.RowHeight(), "at one unit a pixel, the configured height")
    assertEqual(pitch, B.Pitch())
    assertEqual(gap, B.ROW_GAP)
end)

test("breakdown: at a UI scale that is not round, every row and its border sit on whole pixels (2026-11-11)", function()
    do
        local inst, meter, Hud = pixelFight(0.7)
        H.setHud(inst, "spells.borderShow", true)
        H.tick(inst, 13.25, 14)
        local list = rows(Hud, "live")
        assertTrue(#list >= 3, "rows to measure")
        local B = inst.NS.HudBreakdown
        local h, pitch, gap = B.Snapped(0.7)
        for i, row in ipairs(list) do
            -- (The kit's mock answers no height unarmed; the icon is sized off the snapped one.)
            assertTrue(math.abs(row.iconSize - (h - 2 * 0.7)) < 1e-6, "row " .. i .. ": the icon off the snapped height")
            whole(row.iconSize, 0.7, "row " .. i .. " icon")
            local _, _, _, _, y = row:GetPoint(1)
            assertTrue(math.abs(y + (i - 1) * pitch) < 1e-6, "row " .. i .. ": a whole-pixel pitch down")
            whole(y, 0.7, "row " .. i .. " top")
            local _, _, _, _, sy = row.stripe:GetPoint(2)
            assertTrue(math.abs(sy + gap) < 1e-6, "row " .. i .. ": the stripe down through the snapped gap")
            local _, _, _, bx = row.bar:GetPoint(1)
            whole(bx, 0.7, "row " .. i .. " bar's left")
            assertTrue(math.abs(row.edge:GetBackdrop().edgeSize - 0.7) < 1e-6, "row " .. i .. ": a 1 px edge is one pixel")
        end
        meter.SetSecret(false)
    end
end)
