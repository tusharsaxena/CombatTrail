-- tests/test_hud_pace.lua — the DPS HUD's pace (plan Task 3.2, spec §6 and §12): the paced best's
-- curve (its session slices when this session holds them plain, else its linear average pace), the
-- bar's range around it, and the bar itself: the player's live total on the player fill, the pet's
-- on a fill anchored to the end of the player fill's texture, against the best's merged pace, and
-- with the seam (Hud.PACE_PET_FILL) off, player-only against the best's player damage. Every live
-- value reaches the bar as the meter's secret, untouched.

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
local function pacedFight(opts)
    local inst, meter, Hud = H.fresh({ pet = true })
    if opts and opts.noPetFill then Hud.PACE_PET_FILL = false end
    H.whole(inst, meter, 1, PETFIGHT, 10, 40)
    meter.SetSession(2, PETFIGHT)
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

test("pace: pet fill anchored to player fill texture, against the best's merged pace", function()
    local inst, meter, Hud = pacedFight()
    assertEqual(Hud.State(), "live")
    local body = H.body(Hud, "live")
    assertTrue(body.paceShown == true)
    local pace = body.parts.pace
    assertTrue(pace ~= nil and pace.bar:IsShown(), "the bar is up")
    assertTrue(pace.petAnchor ~= nil and pace.petAnchor == pace.player:GetStatusBarTexture(),
        "the pet fill hangs off the player fill's texture")
    assertTrue(pace.pet:IsShown(), "the pet fill shows")
    -- And the anchor itself, as the client is told it, on the next restyle.
    local points = {}
    rawset(pace.pet, "SetPoint", function(_, ...) points[#points + 1] = { ... } end)
    Hud.Apply()
    assertTrue(#points >= 1, "the pet fill was anchored again")
    for _, pt in ipairs(points) do
        assertEqual(pt[2], pace.player:GetStatusBarTexture(), "relative to the player fill's texture")
    end
    assertEqual(points[1][1] .. ">" .. points[1][3], "TOPLEFT>TOPRIGHT", "its left edge on the fill's right edge")
    local player, pet = pace.player:GetValue(), pace.pet:GetValue()
    assertTrue(T.isSecret(player), "the player's live total, handed over as the meter's secret")
    assertTrue(T.isSecret(pet), "and the pet's")
    assertEqual(T.reveal(player), 40000)
    assertEqual(T.reveal(pet), 8000)
    local ref = 48000 * Hud.View().clock / 40
    local lo, hi = pace.player:GetMinMaxValues()
    near(lo, ref * 0.5, "lo: the merged pace x (2 - 1.5)")
    near(hi, ref * 1.5, "hi: the merged pace x 1.5")
    local plo, phi = pace.pet:GetMinMaxValues()
    near(plo, 0)
    near(phi, hi - lo, "the pet fill runs at the player fill's scale")
    meter.SetSecret(false)

    -- The over card: the plain final read against the best at the fight's length.
    H.finish(inst, 100, 40)
    assertEqual(Hud.State(), "over")
    local over = H.body(Hud, "over").parts.pace
    assertTrue(over ~= nil and over.bar:IsShown())
    assertEqual(over.player:GetValue(), 40000)
    assertEqual(over.pet:GetValue(), 8000)
    lo, hi = over.player:GetMinMaxValues()
    near(lo, 24000, "the best's 48000 at 40 s, x 0.5")
    near(hi, 72000)
end)

test("pace: PACE_PET_FILL=false shows player-only against the best's player damage", function()
    local inst, meter, Hud = pacedFight({ noPetFill = true })
    local pace = H.body(Hud, "live").parts.pace
    assertFalse(pace.pet:IsShown(), "no pet fill")
    assertEqual(T.reveal(pace.player:GetValue()), 40000, "the player's own total")
    local ref = 40000 * Hud.View().clock / 40
    local lo, hi = pace.player:GetMinMaxValues()
    near(lo, ref * 0.5, "against the best's player damage alone")
    near(hi, ref * 1.5)
    meter.SetSecret(false)
    assertTrue(inst ~= nil)
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
