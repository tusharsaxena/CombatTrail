-- tests/test_hud_pace.lua — the DPS HUD's pace (plan Task 3.2, spec §6 and §12): the paced best's
-- curve (its session slices when this session holds them plain, else its linear average pace), the
-- bar's range around it, and the bar itself, DPS Race's: two halves split at the on-pace tick, the
-- behind half in the bar look with a red shortfall anchored to its fill's end, the ahead half green,
-- both handed the same total. A total with no live pet source of its own runs against the best's
-- merged pace; a separate pet source, player-only against the best's player damage; after the fight
-- the plain merged total. Every live value reaches the bar as the meter's secret, untouched.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse
local H = dofile(T.root .. "/tests/hud_fixture.lua")(T)
local near = H.near

local ENEMIES = { { name = "Angry Boar", creatureID = 1985, damage = 48000 } }
-- The player's spells NOT in damage order; the pet's own source beside them.
local PETFIGHT = { damage = 40000, dps = 1000, duration = 40,
                   spells = { { id = 11366, dmg = 10000, dps = 250 }, { id = 133, dmg = 30000, dps = 750 } },
                   pet = { damage = 8000, dps = 200,
                           spells = { { id = 17253, dmg = 5000, dps = 125 }, { id = 16827, dmg = 3000, dps = 75 } } },
                   enemies = ENEMIES }

-- A stored best (fight 1, 10 s to 50 s), then fight 2 live from 100 with the meter's figures secret.
-- `live`: the live fight's session (default PETFIGHT, its pet a source of its own).
local function pacedFight(live)
    local inst, meter, Hud = H.fresh({ pet = true })
    H.whole(inst, meter, 1, PETFIGHT, 10, 40)
    meter.SetSession(2, live or PETFIGHT)
    H.enter(inst, 100)
    meter.SetSecret(true)
    H.run(inst, 100.25)
    H.hit(inst, 101, 2)
    H.tick(inst, 101.25, 105)
    return inst, meter, Hud
end

-- ── the curve ───────────────────────────────────────────────────────────────────────────────────

test("pace: uses the best's slices when present, else its linear pace", function()
    local inst, meter = H.fresh({ pet = true })
    local NS = inst.NS
    H.whole(inst, meter, 1, PETFIGHT, 10, 40)
    local record = NS.Recorder.List()[1]
    assertEqual(record.damage.merged, 48000)
    NS.Slices.Reset()
    local linear = NS.HudBest.Curve(record.id)
    assertFalse(linear.fromSlices, "no slices held: linear")
    near(linear:damageAt(10), 12000, "merged dps x t")
    near(linear:playerAt(10), 10000, "the player's own dps x t")
    near(linear:damageAt(0), 0)

    NS.Slices.Seed(record.id, { step = 2, values = { 1000, 3000, 6000 }, pet = { 500, 1000, 1500 },
                                count = 3, filled = 3 })
    local sliced = NS.HudBest.Curve(record.id)
    assertTrue(sliced.fromSlices, "the session's slices")
    near(sliced:damageAt(1), 750, "half way to the first step")
    near(sliced:damageAt(2), 1500, "player and pet at the first step")
    near(sliced:damageAt(3), 2750, "between two steps")
    near(sliced:damageAt(6), 7500, "the last step")
    near(sliced:damageAt(8), 7500 + 1200 * 2, "on at the best's average rate past the last step")
    near(sliced:playerAt(3), 2000, "the player's own curve")

    NS.Slices.Seed(record.id, { step = 2, values = { T.secret(1000), T.secret(3000) }, pet = {},
                                count = 2, filled = 2 })
    local sealed = NS.HudBest.Curve(record.id)
    assertFalse(sealed.fromSlices, "a secret slice cannot be read: linear")
    near(sealed:damageAt(20), 24000)
end)

test("pace: the bounds sit the best's pace in the middle; the range is held to the slider", function()
    local inst = H.fresh()
    local Best = inst.NS.HudBest
    local lo, hi = Best.Bounds(1000, 1.5)
    near(lo, 500)
    near(hi, 1500)
    lo, hi = Best.Bounds(0, 1.5)
    near(lo, 0)
    near(hi, 1, "0:00 still has a span")
    assertEqual(Best.Range(), 1.5, "the shipped hud.paceRange")
    H.setHud(inst, "paceRange", 3)
    assertEqual(Best.Range(), 2.0)
    H.setHud(inst, "paceRange", 1)
    assertEqual(Best.Range(), 1.1)
end)

-- ── the bar ─────────────────────────────────────────────────────────────────────────────────────

test("pace: split at the tick, red short of it, green past it; a separate pet paces player-only", function()
    local inst, meter, Hud = pacedFight()
    assertEqual(Hud.State(), "live")
    local body = H.body(Hud, "live")
    assertTrue(body.paceShown == true)
    local pace = body.parts.pace
    assertTrue(pace ~= nil and pace.bar:IsShown(), "the bar is up")
    assertTrue(pace.fillAnchor ~= nil and pace.fillAnchor == pace.behind:GetStatusBarTexture(),
        "the red shortfall hangs off the behind half's fill texture")
    local Style = inst.NS.Style
    local sr, sg, sb = unpack(pace.shortfall.__color or {})   -- its SetColorTexture, as recorded
    local red = Style.Tok("ct.pace.behind")
    near(sr, red[1], "the shortfall red")
    near(sg, red[2])
    near(sb, red[3])
    local ar, ag, ab = pace.ahead:GetStatusBarColor()
    local green = Style.Tok("ct.ahead")
    near(ar, green[1], "the ahead half green")
    near(ag, green[2])
    near(ab, green[3])
    local behind, ahead = pace.behind:GetValue(), pace.ahead:GetValue()
    assertTrue(T.isSecret(behind) and T.isSecret(ahead), "both halves handed the meter's secret")
    assertEqual(T.reveal(behind), 40000, "the player's own total: the pet has a source of its own")
    assertEqual(T.reveal(ahead), 40000, "the same total to both")
    local ref = 40000 * Hud.View().clock / 40
    local lo, mid = pace.behind:GetMinMaxValues()
    local mid2, hi = pace.ahead:GetMinMaxValues()
    near(lo, ref * 0.5, "lo: the best's player pace x (2 - 1.5)")
    near(mid, ref, "the behind half ends at the pace, the tick")
    near(mid2, ref, "the ahead half starts there")
    near(hi, ref * 1.5, "hi: the pace x 1.5")
    meter.SetSecret(false)

    -- The over card: the plain final merged total against the best's merged pace at its length.
    H.finish(inst, 100, 40)
    assertEqual(Hud.State(), "over")
    local over = H.body(Hud, "over").parts.pace
    assertTrue(over ~= nil and over.bar:IsShown())
    assertEqual(over.behind:GetValue(), 48000, "the player's and the pet's, summed after combat")
    assertEqual(over.ahead:GetValue(), 48000)
    lo = over.behind:GetMinMaxValues()
    hi = select(2, over.ahead:GetMinMaxValues())
    near(lo, 24000, "the best's 48000 at 40 s, x 0.5")
    near(hi, 72000)
end)

test("pace: a total with no pet source of its own runs against the best's merged pace", function()
    -- WoW Forever folds the pet into the player's source: one total, the pet's damage in it.
    local folded = { damage = 48000, dps = 1200, duration = 40,
                     spells = { { id = 133, dmg = 48000, dps = 1200 } }, enemies = ENEMIES }
    local _, meter, Hud = pacedFight(folded)
    local pace = H.body(Hud, "live").parts.pace
    assertEqual(T.reveal(pace.behind:GetValue()), 48000, "the folded total")
    local ref = 48000 * Hud.View().clock / 40
    local lo = pace.behind:GetMinMaxValues()
    local _, hi = pace.ahead:GetMinMaxValues()
    near(lo, ref * 0.5, "against the best's merged pace")
    near(hi, ref * 1.5)
    meter.SetSecret(false)
end)

test("pace: no best, or the layout's pace off, hides the bar", function()
    local inst, meter, Hud = H.fresh({ pet = true })
    H.start(inst, meter, 1, PETFIGHT, 10)
    local body = H.body(Hud, "live")
    assertFalse(body.paceShown == true, "noBest: nothing to pace against")
    assertTrue(body.parts.pace == nil or not body.parts.pace.bar:IsShown())
    H.finish(inst, 10, 40)
    H.setHud(inst, "layout.pace", false)
    H.start(inst, meter, 2, PETFIGHT, 100)
    assertEqual(Hud.State(), "live", "a best to pace against")
    body = H.body(Hud, "live")
    assertFalse(body.paceShown == true, "the layout's switch hides it")
end)
