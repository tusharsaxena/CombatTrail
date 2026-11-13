-- tests/test_hud_pace.lua — the DPS HUD's pace (plan Task 3.2, spec §6 and §12): the paced best's
-- curve (its session slices when this session holds them plain, else its linear average pace), the
-- bar's range around it, and the bar itself, DPS Race's: two halves split at the on-pace tick, the
-- behind half in the bar look with a red shortfall anchored to its fill's end, the ahead half green,
-- both handed the same total. A total with no live pet source of its own runs against the best's
-- merged pace; a separate pet source, player-only against the best's player damage; after the fight
-- the plain merged total. Every live value reaches the bar as the meter's secret, untouched. While
-- the fight is a race (Race mode plan Task C3), the race board's best is the reference, and a race on
-- a shared session is not paced and draws no chart.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
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

-- ── a race's pace (Race mode plan Task C3, spec §4.2 and §4.4) ─────────────────────────────────
-- On a training dummy through the REAL Fight, Race and Recorder (tests/race_fixture.lua fires the
-- events). While the fight carries a `race` part the HUD paces on the race board the race would count
-- on: its best's score over its length (DPS Race's straight line, the Race window's too), never the
-- dummy's fight board. Retail only: WoW Forever has no race.

local F = dofile(T.root .. "/tests/race_fixture.lua")(T)
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local function forever() return T.NS.Compat.IsForever() end

-- A plain dummy fight: 600000 over 40 s. A race's session: 900000 by its 30 s buzzer.
local PLAIN = { damage = 600000, dps = 15000, duration = 40,
                spells = { { id = 29722, dmg = 400000, dps = 10000 }, { id = 348, dmg = 200000, dps = 5000 } } }
local RACED = { damage = 900000, dps = 29032, duration = 31,
                spells = { { id = 29722, dmg = 700000, dps = 22580 }, { id = 348, dmg = 200000, dps = 6452 } } }

local function racer()
    local S = F.fresh({ mutate = installPaint })
    assert(S.NS.SetByPath("race.autoShow", false))
    S.NS.db.profile.hud.show = "always"
    return S
end

-- The dummy's fight board and the 30 s race board, one record each: a plain fight on session 20,
-- then a race on session 21. Answers the fight's record and the race's.
local function boards(S)
    local start = F.pull(S, 101, 20, PLAIN)
    F.damage(S, 20, start + 1, start + 39, 1)
    F.settle(S, start + 40)
    assertTrue(F.arm(S, 30, 160))
    start = F.pull(S, 161, 21, RACED)
    F.damage(S, 21, start + 1, start + 30, 1)
    F.settle(S, start + 31)
    local fightRec, raceRec
    for _, r in ipairs(F.records(S)) do
        if r.race then raceRec = r else fightRec = r end
    end
    assertTrue(fightRec ~= nil and raceRec ~= nil, "one fight and one race stored")
    assertEqual(raceRec.race.score, 900000)
    return fightRec, raceRec
end

test("hud pace: during a race the HUD paces against the race board's best, not the dummy's fight board", function()
    if forever() then return end
    local S = racer()
    local Hud = S.NS.Hud
    local _, raceRec = boards(S)
    assertTrue(F.arm(S, 30, 210))
    local start = F.pull(S, 211, 22, PLAIN)
    F.damage(S, 22, start + 1, start + 8, 1)
    local v = Hud.View()
    assertEqual(v.pace and v.pace.id, raceRec.id, "the race board's best")
    near(v.curve:damageAt(15), 450000, "its score over its length, times t")
    near(v.curve:damageAt(45), 900000, "held at the score past the buzzer")
    near(v.curve.duration, 30, "the race length is the curve's")
    local pace = H.body(Hud, "live").parts.pace
    assertTrue(pace ~= nil and pace.bar:IsShown(), "the bar is up")
    local ref = 900000 * v.clock / 30
    local lo = pace.behind:GetMinMaxValues()
    local _, hi = pace.ahead:GetMinMaxValues()
    near(lo, ref * 0.5, "lo around the race best's pace")
    near(hi, ref * 1.5)
end)

test("hud pace: with pace against the last fight, a race paces on its race board's newest race", function()
    if forever() then return end
    local S = racer()
    local Hud = S.NS.Hud
    assert(S.NS.SetByPath("hud.paceAgainst", "last"))
    local _, raceRec = boards(S)
    assertTrue(F.arm(S, 30, 210))
    local start = F.pull(S, 211, 22, PLAIN)
    F.damage(S, 22, start + 1, start + 8, 1)
    local v = Hud.View()
    assertEqual(v.pace and v.pace.id, raceRec.id, "the race board's newest, not the dummy's last fight")
    near(v.curve.duration, 30, "on the race's straight line")
    near(v.curve:damageAt(15), 450000)
end)

test("hud pace: after the race the next plain dummy fight paces on the fight board again", function()
    if forever() then return end
    local S = racer()
    local Hud = S.NS.Hud
    local fightRec = boards(S)
    assertTrue(F.arm(S, 30, 210))
    local start = F.pull(S, 211, 22, PLAIN)
    F.damage(S, 22, start + 1, start + 30, 1)
    F.settle(S, start + 31)
    assertEqual(#F.records(S), 3, "the second race saved")
    start = F.pull(S, 260, 23, PLAIN)
    F.damage(S, 23, start + 1, start + 5, 1)
    local v = Hud.View()
    assertNil(v.fight.race, "a plain fight")
    assertEqual(v.pace and v.pace.id, fightRec.id, "the dummy's fight board again")
    assertEqual(v.curve.id, fightRec.id, "the fight's own curve")
    near(v.curve.duration, fightRec.duration, "over the fight's duration, not a race length")
end)

test("hud pace: a race canceled mid-pull paces its fight on the dummy's fight board again", function()
    if forever() then return end
    local S = racer()
    local Hud = S.NS.Hud
    local fightRec, raceRec = boards(S)
    assertTrue(F.arm(S, 30, 210))
    local start = F.pull(S, 211, 22, PLAIN)
    F.damage(S, 22, start + 1, start + 3, 1)
    assertEqual(Hud.View().pace.id, raceRec.id)
    assertTrue(S.NS.Race.Cancel())
    assertEqual(Hud.View().pace and Hud.View().pace.id, fightRec.id, "a plain dummy fight now")
    assertEqual(Hud.View().curve.id, fightRec.id, "the fight's own curve")
end)

test("hud pace: a race part that lands after the HUD went live re-paces on RACE_STARTED", function()
    if forever() then return end
    local S = racer()
    local NS, Hud = S.NS, S.NS.Hud
    local fightRec, raceRec = boards(S)
    local start = F.pull(S, 211, 22, PLAIN)
    F.damage(S, 22, start + 1, start + 2, 1)
    local fight = Hud.View().fight
    assertEqual(Hud.View().pace.id, fightRec.id, "live before the race part: the fight board")
    -- The bus keeps no order between receivers: the part arrives once the HUD already paced.
    fight.race = { kind = "boss", length = 30, status = "running", flags = {} }
    NS.SendBus(NS.MSG.RACE_STARTED, fight.race, fight)
    assertEqual(Hud.View().pace and Hud.View().pace.id, raceRec.id, "re-paced on the race board")
    near(Hud.View().curve:damageAt(15), 450000)
    fight.race = nil
end)

test("hud pace: a race resumed after a /reload goes live on the HUD and paces on its race board", function()
    if forever() then return end
    local S = racer()
    local _, raceRec = boards(S)
    S.NS.db.profile.hud.show = "toggle"     -- only the race's own rule (ruling X7) may open it
    assertTrue(F.arm(S, 30, 210))
    local start = F.pull(S, 211, 22, PLAIN)
    F.damage(S, 22, start + 1, start + 8, 1)
    -- The /reload: Fight.Adopt sends no FIGHT_STARTED; the resume's state change is all there is.
    local G = F.reload(S, { now = start + 10, inCombat = true, sessions = { [22] = PLAIN },
                            mutate = installPaint })
    local NS, Hud = G.NS, G.NS.Hud
    assertEqual(NS.Race.State(), "running", "the race resumed")
    assertEqual(Hud.State(), "live", "the HUD is live for the resumed race")
    assertTrue(Hud.IsShown(), "and up, though hud.show is toggle")
    local v = Hud.View()
    assertTrue(v.fight == NS.Race.Fight(), "on the race's adopted fight")
    assertEqual(v.pace and v.pace.id, raceRec.id, "paced on the race board")
    near(v.curve.duration, 30, "on the race's straight line")
    F.damage(G, 22, start + 11, start + 13, 1)
    local pace = H.body(Hud, "live").parts.pace
    assertTrue(pace ~= nil and pace.bar:IsShown(), "the pace bar is up")
end)

local EARLIER = { damage = 200000, dps = 10000, duration = 20,
                  spells = { { id = 29722, dmg = 150000, dps = 7500 }, { id = 348, dmg = 50000, dps = 2500 } } }
local CARRIED = { damage = 1200000, dps = 20000, duration = 60,
                  spells = { { id = 29722, dmg = 950000, dps = 15800 }, { id = 348, dmg = 250000, dps = 4100 } } }

test("hud pace: a race on a shared session draws no pace bar and no chart, live or on the card", function()
    if forever() then return end
    local S = racer()
    local Hud = S.NS.Hud
    F.whole(S, 10)                      -- a best on the 10 s race board
    S.meter.SetSession(5, EARLIER)      -- the last fight's session, still alive at the arm
    assertTrue(F.arm(S, 10, 130))
    F.enter(S, 131)
    S.meter.SetSession(5, CARRIED)      -- the pull lands in it: its live total holds the arm's damage
    F.hit(S, 132, 5)
    F.damage(S, 5, 133, 137, 1)
    assertTrue(S.NS.Fight.Current().sharedSession)
    assertEqual(Hud.State(), "noBest", "not paced: the live total cannot be netted")
    local live = H.body(Hud, "live")
    assertFalse(live.paceShown == true, "no pace bar")
    assertFalse(live.chartShown == true, "no chart")
    F.damage(S, 5, 138, 142, 1)
    F.settle(S, 143)
    assertEqual(Hud.State(), "over")
    local over = H.body(Hud, "over")
    assertFalse(over.paceShown == true, "no pace bar on the card")
    assertFalse(over.chartShown == true, "no chart on the card")
end)
