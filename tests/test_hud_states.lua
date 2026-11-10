-- tests/test_hud_states.lua — the DPS HUD's shell and states (plan Task 3.1, spec §6): hidden, live
-- (and noBest, live with nothing to pace against) and over, with the over card's chips (a new best,
-- saved, or not saved and why). Every fight is driven through the real state machine on the scripted
-- meter (tests/mock_meter.lua), so the HUD hears FIGHT_STARTED, FIGHT_TICK, FIGHT_ENDED and the
-- recorder's FIGHT_SAVED / FIGHT_SKIPPED in the order the client would deliver them. The show modes
-- (auto, always, toggle), the fade after the fight (held by the pointer, or pinned), instancesOnly,
-- the live figures copied without inspection, and the stand-down.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local BOAR_GUID = "Creature-0-1-2-3-1985-0000AAAA"

local FIGHT = { damage = 40000, dps = 1000, duration = 40,
                spells = { { id = 133, dmg = 30000, dps = 750 }, { id = 11366, dmg = 10000, dps = 250 } },
                enemies = { { name = "Angry Boar", creatureID = 1985, damage = 40000 } } }
local FASTER = { damage = 48000, dps = 1200, duration = 40,
                 spells = { { id = 133, dmg = 48000, dps = 1200 } },
                 enemies = { { name = "Angry Boar", creatureID = 1985, damage = 48000 } } }
local SHORT = { damage = 9000, dps = 450, duration = 20,
                spells = { { id = 133, dmg = 9000, dps = 450 } },
                enemies = { { name = "Angry Boar", creatureID = 1985, damage = 9000 } } }

-- A fresh instance on the scripted meter, the player targeting a boar (so a fight has a board key).
local function fresh(mutate)
    local meter
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        meter = T.mockMeter.install(m)
        m.__unitExists.target = true
        m.__unitGUIDs.target = BOAR_GUID
        m.__unitNames.target = "Angry Boar"
        if mutate then mutate(m) end
    end }
    return inst, meter, inst.NS.Hud
end

local function at(inst, t) inst.mocks.__now = t end

-- One hud.* key written and announced, as the settings seam does (the page arrives in Task 3.3).
local function setHud(inst, key, value)
    inst.NS.db.profile.hud[key] = value
    inst.NS.AnnounceSettingsChanged("hud." .. key, value)
end

local function enter(inst, t)
    at(inst, t)
    inst.mocks.InCombatLockdown = function() return true end
    inst.mocks.__inCombat = true
    inst.mocks.__fire("PLAYER_REGEN_DISABLED")
end

local function leave(inst, t)
    at(inst, t)
    inst.mocks.InCombatLockdown = function() return false end
    inst.mocks.__inCombat = false
    inst.mocks.__fire("PLAYER_REGEN_ENABLED")
end

local function hit(inst, t, id)
    at(inst, t)
    inst.mocks.__fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, id)
end

-- Let the clock reach t and run whatever timers are due by then (the fight's tick, its settle).
local function run(inst, t)
    at(inst, t)
    inst.mocks.__fireTimers()
end

-- A fight on session `id` from `t0`: combat entry, the first damage a second in, ticks.
local function start(inst, meter, id, session, t0)
    meter.SetSession(id, session)
    enter(inst, t0)
    run(inst, t0 + 0.25)
    hit(inst, t0 + 1, id)
    run(inst, t0 + 1.25)
end

-- The rest of it: combat ends at t0 + len, the settle runs, the fight ends "final".
local function finish(inst, t0, len)
    leave(inst, t0 + len)
    run(inst, t0 + len + 5)
    run(inst, t0 + len + 7)
end

local function whole(inst, meter, id, session, t0, len)
    start(inst, meter, id, session, t0)
    finish(inst, t0, len)
end

local function shown(Hud)
    local f = Hud.Frame()
    return f ~= nil and f:IsShown() == true
end

-- ── the shape ───────────────────────────────────────────────────────────────────────────────────

test("hud: the states and the defaults are the plan's", function()
    local inst, _, Hud = fresh()
    assertEqual(Hud.STATE.HIDDEN, "hidden")
    assertEqual(Hud.STATE.LIVE, "live")
    assertEqual(Hud.STATE.OVER, "over")
    assertEqual(Hud.STATE.NO_BEST, "noBest")
    assertEqual(Hud.State(), "hidden", "nothing on screen at login")
    local d = inst.NS.defaults.profile.hud
    assertEqual(d.show, "auto")
    assertEqual(d.fadeAfter, 8)
    assertEqual(d.holdOnMouse, true)
    assertEqual(d.instancesOnly, false)
    assertEqual(d.paceAgainst, "best")
    assertEqual(d.paceRange, 1.5)
    assertEqual(d.overCard, true)
    assertEqual(d.showSkipReason, true)
    assertEqual(d.width, 300)
    assertEqual(d.scale, 1)
    for _, key in ipairs({ "clock", "target", "figures", "pace", "chart", "spells" }) do
        assertEqual(d.layout[key], true, "layout." .. key)
    end
    for _, fn in ipairs({ "Show", "Hide", "Toggle", "State", "Pin", "SetLocked", "ResetPosition", "OnVerb",
                          "Suspend", "Resume", "IsShown", "Refresh" }) do
        assertEqual(type(Hud[fn]), "function", "NS.Hud." .. fn)
    end
end)

-- ── auto: the first hit opens it ────────────────────────────────────────────────────────────────

test("hud: auto: hidden -> live on FIGHT_STARTED's first hit", function()
    local inst, meter, Hud = fresh()
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    assertEqual(inst.NS.Fight.State(), "combat")
    run(inst, 10.25)
    assertEqual(Hud.State(), "hidden", "combat alone, no damage yet: still hidden")
    assertFalse(shown(Hud))
    hit(inst, 11, 1)
    run(inst, 11.25)
    assertTrue(Hud.State() == "live" or Hud.State() == "noBest", "live from the first hit: " .. Hud.State())
    assertTrue(shown(Hud), "the window follows the state")
    assertTrue(Hud.IsShown())
    assertTrue(inst.NS.IsHudShown(), "the launcher's Show window entry reads it")
end)

test("hud: the live figures are the meter's handles, copied and never inspected", function()
    local inst, meter, Hud = fresh()
    meter.SetSession(1, FIGHT)
    enter(inst, 10)
    meter.SetSecret(true)
    hit(inst, 11, 1)
    run(inst, 11.25)
    run(inst, 11.5)
    local body = Hud.__ui().body.live
    assertTrue(T.isSecret(body.w.damage.value:GetText()), "the damage figure is the secret itself (no formatter in the harness)")
    assertTrue(T.isSecret(body.w.dps.value:GetText()), "and the DPS figure")
    -- The clock is the HUD's own plain clock from the first hit: 11.5 - 11.
    assertEqual(body.w.clock:GetText(), "0:00.5")
    meter.SetSecret(false)
end)

-- ── noBest and live ─────────────────────────────────────────────────────────────────────────────

test("hud: noBest when Bests.For is nil hides pace; a stored best makes it live with pace", function()
    local inst, meter, Hud = fresh()
    start(inst, meter, 1, FIGHT, 10)
    assertEqual(Hud.State(), "noBest", "no stored fight on this board")
    assertNil(Hud.View().pace, "nothing to pace against")
    assertFalse(Hud.__ui().body.live.paceShown == true, "the pace is hidden")
    finish(inst, 10, 40)
    assertEqual(inst.NS.Recorder.Count(), 1, "the first fight was stored")
    start(inst, meter, 2, FASTER, 100)
    assertEqual(Hud.State(), "live", "the boar's board now holds a best")
    local best = Hud.View().pace
    assertTrue(best ~= nil and best.boardKey == "t:1985:?:Angry Boar:0", "paced against the stored best")
    assertTrue(Hud.__ui().body.live.paceShown == true)
end)

test("hud: the live pace key is the stored boardKey, level and NPC ID included (plan A2)", function()
    local inst, meter, Hud = fresh(function(m) m.__unitLevels.target = 72 end)
    whole(inst, meter, 1, FIGHT, 10, 40)
    local stored = inst.NS.Recorder.List()[1]
    assertEqual(stored.boardKey, "t:1985:72:Angry Boar:0", "the record keys the target's level")
    start(inst, meter, 2, FASTER, 100)
    local view = Hud.View()
    assertEqual(inst.NS.Identity.BoardKey(view.ident), stored.boardKey, "the HUD builds the same key in combat")
    assertTrue(view.pace == stored, "so it paces against the stored fight")
    finish(inst, 100, 40)
    -- Another level of the same boar is another board: nothing to pace against.
    inst.mocks.__unitLevels.target = 73
    start(inst, meter, 3, FIGHT, 200)
    assertEqual(Hud.State(), "noBest", "level 73 has no stored fight")
end)

test("hud: paceAgainst none is always noBest; last paces against the newest fight on the board", function()
    local inst, meter, Hud = fresh()
    whole(inst, meter, 1, FASTER, 10, 40)
    whole(inst, meter, 2, FIGHT, 100, 40)
    local newest = inst.NS.Recorder.List()[1]
    setHud(inst, "paceAgainst", "none")
    start(inst, meter, 3, FIGHT, 200)
    assertEqual(Hud.State(), "noBest")
    finish(inst, 200, 40)
    setHud(inst, "paceAgainst", "last")
    local before = inst.NS.Recorder.List()[1]
    start(inst, meter, 4, FIGHT, 300)
    assertEqual(Hud.State(), "live")
    assertEqual(Hud.View().pace.id, before.id, "the newest stored fight on the board, not the best")
    assertTrue(newest ~= nil)
end)

-- ── over ────────────────────────────────────────────────────────────────────────────────────────

test("hud: over card after FIGHT_ENDED final with saved chip", function()
    local inst, meter, Hud = fresh()
    whole(inst, meter, 1, FIGHT, 10, 40)
    assertEqual(Hud.State(), "over")
    local v = Hud.View()
    assertTrue(v.saved == true, "the recorder stored it")
    assertTrue(v.newBest == true, "the first fight on a board is its best")
    local chips = table.concat(Hud.Chips(), "|")
    assertTrue(chips:find(inst.NS.L["Saved"], 1, true) ~= nil, "a Saved chip: " .. chips)
    assertTrue(chips:find(inst.NS.L["New best"], 1, true) ~= nil, "a New best chip: " .. chips)
    local body = Hud.__ui().body.over
    assertEqual(body.w.damage.value:GetText(), "40.0K", "the plain final damage")
    assertEqual(body.w.dps.value:GetText(), "1.0K")
end)

test("hud: a faster fight on the board says New best with its gain", function()
    local inst, meter, Hud = fresh()
    whole(inst, meter, 1, FIGHT, 10, 40)
    whole(inst, meter, 2, FASTER, 100, 40)
    assertEqual(Hud.State(), "over")
    assertTrue(Hud.View().newBest == true)
    assertEqual(Hud.View().delta, 20, "(1200 - 1000) / 1000")
    local chips = table.concat(Hud.Chips(), "|")
    assertTrue(chips:find("+20.0%", 1, true) ~= nil, chips)
end)

test("hud: skip reason chip on FIGHT_SKIPPED short", function()
    local inst, meter, Hud = fresh()
    whole(inst, meter, 1, SHORT, 10, 20)
    assertEqual(inst.NS.Recorder.Count(), 0, "under the 30 s minimum: not stored")
    assertEqual(Hud.State(), "over")
    local v = Hud.View()
    assertTrue(v.saved == false)
    assertEqual(v.skipReason, "short")
    local chips = table.concat(Hud.Chips(), "|")
    assertTrue(chips:find(inst.NS.L["Not saved: shorter than %d s"]:format(30), 1, true) ~= nil, chips)
    setHud(inst, "showSkipReason", false)
    chips = table.concat(Hud.Chips(), "|")
    assertTrue(chips:find(inst.NS.L["Not saved"], 1, true) ~= nil, chips)
    assertTrue(chips:find("30", 1, true) == nil, "no reason when showSkipReason is off: " .. chips)
end)

test("hud: overCard off: an auto-opened HUD closes with the fight", function()
    local inst, meter, Hud = fresh()
    setHud(inst, "overCard", false)
    start(inst, meter, 1, FIGHT, 10)
    assertTrue(shown(Hud))
    finish(inst, 10, 40)
    assertEqual(Hud.State(), "hidden")
    assertFalse(shown(Hud))
end)

-- ── the fade ────────────────────────────────────────────────────────────────────────────────────

test("hud: fades after hud.fadeAfter unless mouse over or pinned", function()
    local inst, meter, Hud = fresh()
    whole(inst, meter, 1, FIGHT, 10, 40)
    assertEqual(Hud.State(), "over")
    local ended = Hud.View().endedAt
    assertEqual(Hud.FadeAt() - ended, 8, "the fade is hud.fadeAfter after the fight's end")
    run(inst, ended + 7.9)
    assertEqual(Hud.State(), "over", "still up inside the 8 s")
    run(inst, ended + 8.1)
    assertEqual(Hud.State(), "hidden", "faded after hud.fadeAfter")
    assertFalse(shown(Hud))

    -- The pointer on it holds it open; leaving lets it go a moment later.
    whole(inst, meter, 2, FIGHT, 100, 40)
    ended = inst.mocks.__now
    Hud.Frame():__fire("OnEnter")
    run(inst, ended + 20)
    assertEqual(Hud.State(), "over", "held while the mouse is over it")
    Hud.Frame():__fire("OnLeave")
    run(inst, ended + 20 + Hud.LEAVE_DELAY + 0.1)
    assertEqual(Hud.State(), "hidden", "let go after the pointer left")

    -- holdOnMouse off: the pointer does not hold it.
    setHud(inst, "holdOnMouse", false)
    whole(inst, meter, 3, FIGHT, 200, 40)
    ended = Hud.View().endedAt
    Hud.Frame():__fire("OnEnter")
    run(inst, ended + 8.1)
    assertEqual(Hud.State(), "hidden")
    Hud.Frame():__fire("OnLeave")

    -- Pinned: never fades; unpinned, the fade starts again.
    whole(inst, meter, 4, FIGHT, 300, 40)
    Hud.Pin(true)
    assertTrue(Hud.IsPinned())
    ended = inst.mocks.__now
    run(inst, ended + 60)
    assertEqual(Hud.State(), "over", "pinned open")
    Hud.Pin(false)
    run(inst, inst.mocks.__now + 8.1)
    assertEqual(Hud.State(), "hidden", "unpinned, it fades")
end)

test("hud: a pointer that leaves from a chip still lets the card fade", function()
    local inst, meter, Hud = fresh()
    whole(inst, meter, 1, FIGHT, 10, 40)
    local ended = Hud.View().endedAt
    local f = Hud.Frame()
    -- On a chip (a child that takes the pointer): the frame's own OnLeave has fired, IsMouseOver holds.
    local over = true
    f.IsMouseOver = function() return over end
    f:__fire("OnEnter")
    f:__fire("OnLeave")
    run(inst, ended + 8.1)
    assertEqual(Hud.State(), "over", "held while the pointer is on the chip")
    -- The pointer leaves the chip straight off the HUD: no OnLeave reaches the frame.
    over = false
    run(inst, ended + 8.1 + Hud.LEAVE_DELAY + 0.1)
    assertEqual(Hud.State(), "hidden", "let go once the pointer is gone, with no OnLeave")
end)

test("hud: fadeAfter 0 keeps the card up until the next fight or a close", function()
    local inst, meter, Hud = fresh()
    setHud(inst, "fadeAfter", 0)
    whole(inst, meter, 1, FIGHT, 10, 40)
    run(inst, 500)
    assertEqual(Hud.State(), "over")
    start(inst, meter, 2, FIGHT, 600)
    assertEqual(Hud.State(), "live", "the next fight takes it over")
end)

test("hud: a HUD the player opened never fades", function()
    local inst, meter, Hud = fresh()
    Hud.Show()
    assertTrue(shown(Hud), "shown with no fight yet")
    whole(inst, meter, 1, FIGHT, 10, 40)
    run(inst, inst.mocks.__now + 60)
    assertEqual(Hud.State(), "over")
    Hud.Hide()
    assertEqual(Hud.State(), "hidden")
    assertFalse(shown(Hud))
end)

-- ── the show modes ──────────────────────────────────────────────────────────────────────────────

test("hud: toggle mode never auto-shows", function()
    local inst, meter, Hud = fresh()
    setHud(inst, "show", "toggle")
    whole(inst, meter, 1, FIGHT, 10, 40)
    assertEqual(Hud.State(), "hidden")
    assertFalse(shown(Hud))
    Hud.Toggle()
    assertTrue(shown(Hud), "the toggle opens it")
    assertEqual(Hud.State(), "over", "on the fight that just ended")
    start(inst, meter, 2, FIGHT, 100)
    assertEqual(Hud.State(), "live", "open, it follows the next fight (paced against the first)")
    finish(inst, 100, 40)
    run(inst, inst.mocks.__now + 60)
    assertEqual(Hud.State(), "over", "and never fades")
    Hud.Toggle()
    assertEqual(Hud.State(), "hidden")
end)

test("hud: Show DPS HUD in combat off: auto opens nothing", function()
    local inst, meter, Hud = fresh()
    inst.NS.SetByPath("general.hudInCombat", false)
    whole(inst, meter, 1, FIGHT, 10, 40)
    assertEqual(Hud.State(), "hidden")
end)

test("hud: always mode is up at login and after a stand-up, and never fades", function()
    local inst, meter, Hud = fresh()
    setHud(inst, "show", "always")
    Hud.Resume()
    assertTrue(shown(Hud), "always: up with no fight")
    whole(inst, meter, 1, FIGHT, 10, 40)
    run(inst, inst.mocks.__now + 60)
    assertEqual(Hud.State(), "over")
    inst.NS.SetByPath("general.enabled", false)
    assertFalse(shown(Hud), "stood down: hidden")
    inst.NS.SetByPath("general.enabled", true)
    assertTrue(shown(Hud), "stood up: back")
end)

test("hud: instancesOnly hides in world", function()
    local inst, meter, Hud = fresh()
    setHud(inst, "instancesOnly", true)
    inst.mocks.__context.inInstance, inst.mocks.__context.instanceType = false, "none"
    whole(inst, meter, 1, FIGHT, 10, 40)
    assertEqual(Hud.State(), "hidden", "the open world: never opened")
    inst.mocks.__context.inInstance, inst.mocks.__context.instanceType = true, "party"
    start(inst, meter, 2, FIGHT, 100)
    assertTrue(shown(Hud), "in a dungeon it opens")
end)

test("hud: always beats instancesOnly: in the open world it stays up through two fights", function()
    local inst, meter, Hud = fresh()
    setHud(inst, "show", "always")
    setHud(inst, "instancesOnly", true)
    inst.mocks.__context.inInstance, inst.mocks.__context.instanceType = false, "none"
    Hud.Resume()
    assertTrue(shown(Hud), "always: up with no fight")
    start(inst, meter, 1, FIGHT, 10)
    assertTrue(shown(Hud), "up through the first open-world fight")
    finish(inst, 10, 40)
    run(inst, inst.mocks.__now + 60)
    assertTrue(shown(Hud), "up after it")
    assertEqual(Hud.State(), "over")
    start(inst, meter, 2, FIGHT, 200)
    assertTrue(shown(Hud), "up through the next one")
    finish(inst, 200, 40)
    assertTrue(shown(Hud), "and after it")
end)

test("hud: always plus instancesOnly: a player close holds for that fight only", function()
    local inst, meter, Hud = fresh()
    setHud(inst, "show", "always")
    setHud(inst, "instancesOnly", true)
    inst.mocks.__context.inInstance, inst.mocks.__context.instanceType = false, "none"
    Hud.Resume()
    start(inst, meter, 1, FIGHT, 10)
    Hud.Frame():Hide()
    Hud.Frame():__fire("OnHide")
    run(inst, 12)
    run(inst, 12.25)
    assertEqual(Hud.State(), "hidden", "closed for this fight")
    finish(inst, 10, 40)
    start(inst, meter, 2, FIGHT, 100)
    assertTrue(shown(Hud), "the next fight opens it again")
end)

test("hud: a HUD the player closed mid-fight stays closed for that fight", function()
    local inst, meter, Hud = fresh()
    start(inst, meter, 1, FIGHT, 10)
    assertTrue(shown(Hud))
    Hud.Frame():Hide()
    Hud.Frame():__fire("OnHide")
    assertEqual(Hud.State(), "hidden")
    run(inst, 12)
    run(inst, 12.25)
    assertEqual(Hud.State(), "hidden", "the ticks do not bring it back")
    finish(inst, 10, 40)
    assertEqual(Hud.State(), "hidden", "nor does the fight's end")
    start(inst, meter, 2, FIGHT, 100)
    assertTrue(shown(Hud), "the next fight opens it again")
end)

-- ── the verb, the lock, the stand-down ──────────────────────────────────────────────────────────

test("hud: /ct hud show, hide, pin and unpin", function()
    local inst, _, Hud = fresh()
    local NS, M = inst.NS, inst.mocks
    NS.Slash:OnSlash("hud show")
    assertTrue(shown(Hud))
    NS.Slash:OnSlash("hud pin")
    assertTrue(Hud.IsPinned())
    NS.Slash:OnSlash("hud unpin")
    assertFalse(Hud.IsPinned())
    NS.Slash:OnSlash("hud hide")
    assertFalse(shown(Hud))
    NS.Slash:OnSlash("hud toggle")
    assertTrue(shown(Hud))
    M.__resetPrinted()
    NS.Slash:OnSlash("hud sideways")
    assertEqual(#M.__printed(), 1, "one usage line")
end)

test("hud: Locked stops the drag; Reset position puts it back", function()
    local inst, _, Hud = fresh()
    local NS = inst.NS
    Hud.Show()
    NS.SetByPath("general.locked", true)
    assertTrue(Hud.IsLocked())
    NS.SetByPath("general.locked", false)
    assertFalse(Hud.IsLocked())
    NS.db.profile.hud.position.x = 123
    NS.ResetPositions()
    assertEqual(NS.db.profile.hud.position.x, NS.defaults.profile.hud.position.x)
end)

test("hud: disabled addon: hidden, no timer, and no fight opens it", function()
    local inst, meter, Hud = fresh()
    whole(inst, meter, 1, FIGHT, 10, 40)
    assertEqual(Hud.State(), "over")
    inst.NS.SetByPath("general.enabled", false)
    assertEqual(Hud.State(), "hidden")
    assertFalse(shown(Hud))
    assertNil(Hud.FadeAt(), "the fade was dropped")
    for _, t in ipairs(inst.mocks.__timers()) do
        assertFalse(t == Hud.Frame(), "no OnUpdate on the HUD")
    end
end)
