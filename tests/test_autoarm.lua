-- tests/test_autoarm.lua — auto-show and auto-arm near a training dummy (Race mode plan Task B3,
-- modules/AutoArm.lua): DPS Race's auto-arm cases (its tests/test_autoarm.lua @f8078c7) on Combat
-- Trail's race engine, the dummies read through NS.Dummies. Auto-show on by default, auto-arm off; the
-- Race window asked to open by a dummy target or nameplate and to close again only after the debounce,
-- never over a race or a result, never against the player's close in the same dummy session; the race
-- armed on targeting a dummy through Race.Arm's refusals, canceled by a target change before the pull
-- and never after it; nothing in an instance, while stood down, with Race mode off, or on WoW Forever.
--
-- The Race window is Task C1's. Its five hooks (ShowNearDummy, HideAwayFromDummy, ShownNearDummy, Closes
-- and ArmLength) are the seam this module calls; the cases stand a fake window on that seam, as DPS
-- Race's HUD answered them, except the last section's, which run the real Race window (`real`) for the
-- player's own open and close in a dummy session (AutoArm.InSession, the owner's in-game report). Every case runs on tests/race_fixture.lua's instance (the scripted meter,
-- the clock, the timer queue serviced at its own GetTime()).

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local F = dofile(T.root .. "/tests/race_fixture.lua")(T)

local function forever() return T.NS.Compat.IsForever() end

local CLEAVE = "Creature-0-1-2-3-131983-0001"    -- Raider's Training Dummy (Tiragarde Sound), a boss dummy
local GOLEM = "Creature-0-1-2-3-67127-0001"      -- Training Dummy (Shrine of Seven Stars), single target
local BOAR = "Creature-0-1-2-3-1985-0001"        -- no dummy

-- The Race window as DPS Race's HUD answered auto-show: a window wanted by someone, the dummy's own
-- opening, and the player's closes counted.
local function fakeWindow(NS)
    local W = { wanted = false, dummy = false, closes = 0 }
    function W.ShowNearDummy()
        if W.wanted then return false end
        W.wanted, W.dummy = true, true
        return true
    end
    function W.HideAwayFromDummy()
        if not W.dummy then return false end
        W.wanted, W.dummy = false, false
        return true
    end
    function W.ShownNearDummy() return W.dummy end
    function W.Closes() return W.closes end
    function W.ArmLength() return W.length end
    function W.IsShown() return W.wanted end
    -- The player's own open and close.
    function W.Open() W.wanted, W.dummy = true, false end
    function W.Close()
        W.wanted, W.dummy = false, false
        W.closes = W.closes + 1
    end
    NS.RaceWindow = W
    return W
end

--- A fresh instance with no target, nameplates readable from `S.plates`, the fake window, and the two
--- rules set as asked (both off when not named; `defaults` leaves the profile's own defaults alone).
local function fixture(opts)
    opts = opts or {}
    local plates = {}
    local S = F.fresh{ target = false, mutate = function(m)
        m.C_NamePlate = { GetNamePlates = function()
            local out = {}
            for unit in pairs(plates) do out[#out + 1] = { namePlateUnitToken = unit } end
            return out
        end }
        if opts.mutate then opts.mutate(m) end
    end }
    S.plates = plates
    if not opts.real then S.W = fakeWindow(S.NS) end
    S.A = S.NS.AutoArm
    if not opts.defaults then
        assertTrue(S.NS.SetByPath("race.autoShow", opts.show == true))
        -- Either auto-show row opens the Race window (W29 decision D4): the HUD's row as asked too.
        assertTrue(S.NS.SetByPath("race.autoShowHud", opts.hud == true))
        assertTrue(S.NS.SetByPath("race.autoArm", opts.arm == true))
    else
        S.A.Sync()
    end
    return S
end

local function target(S, guid)
    S.M.__unitExists.target = guid ~= nil
    S.M.__unitGUIDs.target = guid
    S.M.__fire("PLAYER_TARGET_CHANGED")
end

local function plateUp(S, unit, guid, silent)
    S.plates[unit] = true
    S.M.__unitExists[unit] = true
    S.M.__unitGUIDs[unit] = guid
    if not silent then S.M.__fire("NAME_PLATE_UNIT_ADDED", unit) end
end

local function plateDown(S, unit)
    S.plates[unit] = nil
    S.M.__unitExists[unit] = false
    S.M.__unitGUIDs[unit] = nil
    S.M.__fire("NAME_PLATE_UNIT_REMOVED", unit)
end

--- Move the clock on by `dt` and service the timers.
local function advance(S, dt)
    F.run(S, S.M.__now + dt)
end

-- ── WoW Forever ─────────────────────────────────────────────────────────────────────────────────

test("autoarm: on WoW Forever nothing registers and a dummy target arms and shows nothing", function()
    if not forever() then return end
    local S = F.fresh{ target = false }
    local W = fakeWindow(S.NS)
    S.NS.AutoArm.Sync()
    assertEqual(S.NS.AutoArm.Diagnose().events, "none")
    assertNil(S.NS.AutoArm.Target(), "no AutoArm event target on WoW Forever")
    assertNil(S.NS.defaults.profile.race.autoShow, "no auto-show key on WoW Forever")
    assertNil(S.NS.defaults.profile.race.autoArm, "no auto-arm key on WoW Forever")
    target(S, CLEAVE)
    assertFalse(W.wanted)
    assertFalse(S.NS.Hud.IsShown(), "the DPS HUD opened by a dummy on WoW Forever")
    assertEqual(S.NS.Race.State(), "idle")
end)

-- ── off by default ──────────────────────────────────────────────────────────────────────────────

test("autoarm: a new profile shows the Race window near a dummy and never arms by itself", function()
    if forever() then return end
    local S = fixture{ defaults = true }
    assertTrue(S.NS.GetSetting("race.autoShow"))
    assertFalse(S.NS.GetSetting("race.autoArm"))
    assertEqual(S.NS.defaults.profile.race.autoShow, true)
    assertEqual(S.NS.defaults.profile.race.autoArm, false)
    assertEqual(S.A.Diagnose().events, "plates")
    target(S, CLEAVE)
    assertTrue(S.W.wanted, "the Race window opens on a dummy target")
    assertEqual(S.NS.Race.State(), "idle", "nothing armed")
end)

test("autoarm: both rules off register nothing", function()
    if forever() then return end
    local S = fixture()
    assertEqual(S.A.Diagnose().events, "none")
    target(S, CLEAVE)
    plateUp(S, "nameplate1", GOLEM)
    assertEqual(S.NS.Race.State(), "idle", "nothing armed with the rule off")
    assertFalse(S.W.wanted, "nothing shown with the rule off")
end)

test("autoarm: each rule registers only what it needs, and turning both off drops it all", function()
    if forever() then return end
    local S = fixture{ arm = true }
    assertEqual(S.A.Diagnose().events, "target")
    local ev = S.A.Target()
    assertTrue(ev ~= nil, "the rule's own AceEvent target")
    assertTrue(S.NS.SetByPath("race.autoShow", true))
    assertEqual(S.A.Diagnose().events, "plates")
    assertTrue(S.NS.SetByPath("race.autoShow", false))
    assertTrue(S.NS.SetByPath("race.autoArm", false))
    assertEqual(S.A.Diagnose().events, "none")
    target(S, CLEAVE)
    assertEqual(S.NS.Race.State(), "idle", "an event heard after the unregistration")
end)

-- ── auto-show ───────────────────────────────────────────────────────────────────────────────────

test("autoshow: a dummy target opens the Race window, and leaving it closes it after the debounce", function()
    if forever() then return end
    local S = fixture{ show = true }
    target(S, CLEAVE)
    assertTrue(S.W.wanted, "the dummy target opened it")
    assertTrue(S.W.ShownNearDummy())
    target(S, BOAR)
    assertTrue(S.W.wanted, "still open inside the debounce")
    assertTrue(S.A.Diagnose().hiding)
    advance(S, S.A.HIDE_DELAY - 1)
    assertTrue(S.W.wanted, "closed before the debounce ran out")
    advance(S, 1)
    assertFalse(S.W.wanted, "closed once no dummy was seen for the debounce")
    assertFalse(S.A.Diagnose().session)
end)

test("autoshow: a dummy's nameplate opens the Race window, with no target at all", function()
    if forever() then return end
    local S = fixture{ show = true }
    plateUp(S, "nameplate3", GOLEM)
    assertTrue(S.W.wanted)
    assertEqual(S.A.Diagnose().plates, 1)
    plateUp(S, "nameplate4", BOAR)
    assertEqual(S.A.Diagnose().plates, 1, "a creature that is no training dummy")
end)

test("autoshow: nameplates churning inside the debounce never close the window", function()
    if forever() then return end
    local S = fixture{ show = true }
    plateUp(S, "nameplate1", CLEAVE)
    for _ = 1, 4 do
        plateDown(S, "nameplate1")
        advance(S, S.A.HIDE_DELAY - 1)
        assertTrue(S.W.wanted, "closed while the plate was only blinking")
        plateUp(S, "nameplate1", CLEAVE)
        assertFalse(S.A.Diagnose().hiding, "the plate's return cancels the hide")
    end
    plateDown(S, "nameplate1")
    advance(S, S.A.HIDE_DELAY)
    assertFalse(S.W.wanted)
end)

test("autoshow: the hide's fire scans the nameplates again before it closes", function()
    if forever() then return end
    local S = fixture{ show = true }
    plateUp(S, "nameplate1", CLEAVE)
    plateUp(S, "nameplate2", CLEAVE, true)    -- up without its event reaching the rule
    plateDown(S, "nameplate1")
    advance(S, S.A.HIDE_DELAY)
    assertTrue(S.W.wanted, "the rescan found the dummy still up")
    assertEqual(S.A.Diagnose().plates, 1)
end)

test("autoshow: a secret GUID is no dummy", function()
    if forever() then return end
    local S = fixture{ show = true }
    plateUp(S, "nameplate1", T.secret(CLEAVE))
    assertFalse(S.W.wanted)
    assertEqual(S.A.Diagnose().plates, 0)
end)

test("autoshow: the player's close keeps it closed for the rest of the dummy session", function()
    if forever() then return end
    local S = fixture{ show = true }
    plateUp(S, "nameplate1", CLEAVE)
    assertTrue(S.W.wanted)
    S.W.Close()
    plateUp(S, "nameplate2", GOLEM)
    target(S, CLEAVE)
    assertFalse(S.W.wanted, "auto-show fought the player's close")
    -- Away from the dummies for the debounce: the session ends, and the next one opens it again.
    target(S, nil)
    plateDown(S, "nameplate1")
    plateDown(S, "nameplate2")
    advance(S, S.A.HIDE_DELAY)
    assertFalse(S.A.Diagnose().session)
    plateUp(S, "nameplate1", CLEAVE)
    assertTrue(S.W.wanted, "a new session opens it")
end)

test("autoshow: a window the player opened is theirs, and never closed by leaving", function()
    if forever() then return end
    local S = fixture{ show = true }
    S.W.Open()
    plateUp(S, "nameplate1", CLEAVE)
    assertFalse(S.W.ShownNearDummy())
    plateDown(S, "nameplate1")
    advance(S, S.A.HIDE_DELAY)
    assertTrue(S.W.wanted, "the player's window closed by itself")
end)

test("autoshow: a race holds the window; its idle edge starts the debounce", function()
    if forever() then return end
    local S = fixture{ show = true }
    target(S, CLEAVE)
    assertTrue(F.arm(S, 30, S.M.__now))
    target(S, BOAR)
    advance(S, S.A.HIDE_DELAY * 2)
    assertTrue(S.W.wanted, "closed over an armed race")
    assertTrue(S.NS.Race.Cancel())
    assertTrue(S.W.wanted, "the idle edge starts the debounce, not a close")
    advance(S, S.A.HIDE_DELAY)
    assertFalse(S.W.wanted)
end)

test("autoshow: turning the rule off closes the window it opened", function()
    if forever() then return end
    local S = fixture{ show = true }
    target(S, CLEAVE)
    assertTrue(S.W.wanted)
    assertTrue(S.NS.SetByPath("race.autoShow", false))
    assertFalse(S.W.wanted)
end)

-- ── the DPS HUD near a dummy (Race window redesign plan Task W3, ruling O4) ─────────────────────

local function hud(S) return S.NS.Hud end

--- Leave every dummy and let the debounce run out: the session ends.
local function away(S)
    target(S, nil)
    for unit in pairs(S.plates) do plateDown(S, unit) end
    advance(S, S.A.HIDE_DELAY)
    assertFalse(S.A.Diagnose().session, "the session ended")
end

-- From here on the cases run the real Race window (W29): it opens the DPS HUD itself, so the HUD's
-- part of auto-show is the Race window's own open.
local function hudFixture(opts)
    opts = opts or {}
    opts.real = true
    if opts.show == nil then opts.show = true end
    local S = fixture(opts)
    return S, S.NS.RaceWindow
end

test("autoshow hud: a new profile opens the DPS HUD with the Race window, as an auto open", function()
    if forever() then return end
    local S, RW = hudFixture()
    assertEqual(S.NS.defaults.profile.race.autoShowHud, true, "on by default")
    assertFalse(hud(S).IsShown())
    target(S, CLEAVE)
    assertTrue(RW.IsShown(), "the Race window opened")
    assertTrue(hud(S).IsShown(), "the DPS HUD opened with it")
    assertTrue(hud(S).ShownNearDummy())
    assertFalse(hud(S).Diagnose().byPlayer, "the addon's open, which fades by the HUD's rules")
    away(S)
    assertFalse(RW.IsShown())
    assertFalse(hud(S).IsShown(), "the HUD this rule opened closed at the session's end")
    assertFalse(hud(S).ShownNearDummy())
end)

test("autoshow hud: either row opens both windows near a dummy; both off, neither (W29 D4)", function()
    if forever() then return end
    for _, rows in ipairs({ { show = true, hud = false }, { show = false, hud = true }, { show = true, hud = true } }) do
        local S, RW = hudFixture(rows)
        local tag = ("autoShow %s, autoShowHud %s"):format(tostring(rows.show), tostring(rows.hud))
        assertEqual(S.A.Diagnose().events, "plates", tag .. ": the nameplates are heard")
        target(S, CLEAVE)
        assertTrue(RW.IsShown(), tag .. ": the Race window opened")
        assertTrue(hud(S).IsShown() and hud(S).ShownNearDummy(), tag .. ": the HUD opened with it, the session's")
    end
    local S, RW = hudFixture{ show = false, hud = false }
    assertEqual(S.A.Diagnose().events, "none")
    target(S, CLEAVE)
    assertFalse(RW.IsShown() or hud(S).IsShown(), "both rows off: nothing opens")
end)

test("autoshow hud: turning one row off keeps both windows; turning both off closes both", function()
    if forever() then return end
    local S, RW = hudFixture{ hud = true }
    target(S, CLEAVE)
    assertTrue(hud(S).IsShown() and RW.IsShown())
    assertTrue(S.NS.SetByPath("race.autoShowHud", false))
    assertTrue(hud(S).IsShown() and RW.IsShown(), "auto-show is still on by its other row")
    assertTrue(S.NS.SetByPath("race.autoShow", false))
    assertFalse(hud(S).IsShown(), "the HUD it opened closed")
    assertFalse(RW.IsShown(), "the Race window it opened closed")
end)

test("autoshow hud: the player's close of the HUD holds both windows shut for the rest of the session", function()
    if forever() then return end
    local S, RW = hudFixture()
    plateUp(S, "nameplate1", CLEAVE)
    assertTrue(hud(S).IsShown() and RW.IsShown())
    local closes, rwCloses = hud(S).Closes(), RW.Closes()
    hud(S).Hide()
    assertEqual(hud(S).Closes(), closes + 1, "the player's close counted")
    assertFalse(RW.IsShown(), "the Race window hid with the HUD (T1)")
    assertEqual(RW.Closes(), rwCloses, "hiding with the HUD is not the player closing the Race window")
    plateUp(S, "nameplate2", GOLEM)
    target(S, CLEAVE)
    assertFalse(hud(S).IsShown(), "auto-show fought the player's close")
    assertFalse(RW.IsShown(), "and the Race window stays down with it")
    away(S)
    plateUp(S, "nameplate1", CLEAVE)
    assertTrue(hud(S).IsShown() and RW.IsShown(), "a new session opens both again")
end)

test("autoshow hud: the close control hides the Race window still wanted; Escape closes both as the player's", function()
    if forever() then return end
    local S, RW = hudFixture()
    target(S, CLEAVE)
    local closes, rwCloses = hud(S).Closes(), RW.Closes()
    hud(S).__ui().close:GetScript("OnClick")(hud(S).__ui().close)
    assertFalse(hud(S).IsShown())
    assertEqual(hud(S).Closes(), closes + 1)
    assertFalse(RW.IsShown() or RW.Visible(), "the Race window hid with the HUD")
    assertEqual(RW.Closes(), rwCloses, "the HUD's close control is not the Race window's close")
    assertTrue(RW.ShownNearDummy(), "still wanted, the session's")
    target(S, GOLEM)
    assertFalse(hud(S).IsShown() or RW.IsShown(), "the session leaves both shut")
    -- Escape: the HUD's frame hidden by the close list, its OnHide heard.
    S = hudFixture()
    RW = S.NS.RaceWindow
    target(S, CLEAVE)
    closes, rwCloses = hud(S).Closes(), RW.Closes()
    hud(S).Frame():Hide()
    hud(S).Frame():__fire("OnHide")
    assertFalse(hud(S).IsShown())
    assertEqual(hud(S).Closes(), closes + 1)
    assertFalse(RW.Visible(), "Escape took the Race window too")
    assertEqual(RW.Closes(), rwCloses + 1, "as the player's close of it")
    assertFalse(RW.ShownNearDummy(), "no longer wanted")
    target(S, GOLEM)
    assertFalse(hud(S).IsShown() or RW.IsShown())
end)

test("autoshow hud: a HUD the player opened or pinned is never closed by leaving", function()
    if forever() then return end
    local S = hudFixture()
    hud(S).Show()
    target(S, CLEAVE)
    assertFalse(hud(S).ShownNearDummy(), "the player's HUD is not the rule's")
    away(S)
    assertTrue(hud(S).IsShown(), "the player's HUD closed by itself")
    hud(S).Hide()
    away(S)
    -- A new session opens it, and the player pins it; then one the player opens as theirs.
    target(S, CLEAVE)
    assertTrue(hud(S).ShownNearDummy())
    hud(S).Pin(true)
    away(S)
    assertTrue(hud(S).IsShown(), "a pinned HUD closed by leaving")
    hud(S).Pin(false)
    hud(S).Hide()
    away(S)
    target(S, CLEAVE)
    assertTrue(hud(S).ShownNearDummy(), "the rule opened it again")
    hud(S).Show()
    away(S)
    assertTrue(hud(S).IsShown(), "a HUD the player opened since closed by leaving")
end)

test("autoshow hud: the session's end never closes a live fight's HUD", function()
    if forever() then return end
    local S = hudFixture()
    target(S, CLEAVE)
    assertTrue(hud(S).IsShown())
    F.pull(S, S.M.__now + 1)
    assertTrue(hud(S).IsShown(), "the first hit kept it up")
    target(S, nil)
    advance(S, S.A.HIDE_DELAY)
    assertFalse(S.A.Diagnose().session)
    assertTrue(hud(S).IsShown(), "the live fight's HUD closed")
    assertTrue(hud(S).State() == "live" or hud(S).State() == "noBest", hud(S).State())
end)

test("autoshow hud: a HUD the dummy opened stays up through the first hit whatever the show mode", function()
    if forever() then return end
    local S = hudFixture()
    assertTrue(S.NS.SetByPath("hud.show", "toggle"))
    target(S, CLEAVE)
    assertTrue(hud(S).IsShown())
    F.pull(S, S.M.__now + 1)
    assertTrue(hud(S).IsShown(), "the first hit shut the HUD the dummy opened")
end)

test("autoshow hud: the same gates as auto-show: an instance and Race mode off", function()
    if forever() then return end
    local S = hudFixture()
    S.M.__instance.type = "party"
    target(S, CLEAVE)
    assertFalse(hud(S).IsShown(), "opened in an instance")
    S = hudFixture()
    assertTrue(S.NS.SetByPath("race.enabled", false))
    target(S, CLEAVE)
    assertFalse(hud(S).IsShown(), "opened with Race mode off")
    S = hudFixture()
    target(S, CLEAVE)
    assertTrue(hud(S).IsShown())
    assertTrue(S.NS.SetByPath("race.enabled", false))
    assertFalse(hud(S).IsShown(), "Race mode off closes a HUD the rule opened")
end)

-- The owner, 2026-11-13: near a dummy the HUD is held up (no fade), so both windows stay while the
-- player stands there; the session's end closes both.
test("autoshow hud: a dummy session holds the HUD up through its fade, and its end closes both", function()
    if forever() then return end
    local S, RW = hudFixture()
    target(S, CLEAVE)
    local start = F.pull(S, S.M.__now + 1)
    F.damage(S, 25, start + 1, start + 3, 1)
    F.settle(S, start + 4)
    assertEqual(hud(S).State(), "over")
    assertEqual(hud(S).FadeAt(), nil, "no fade while the session holds it")
    advance(S, 60)
    assertTrue(hud(S).IsShown(), "still up a minute on")
    assertTrue(RW.IsShown() and RW.Visible(), "and the Race window with it")
    target(S, GOLEM)
    assertTrue(hud(S).IsShown() and RW.IsShown())
    away(S)
    assertFalse(hud(S).IsShown() or RW.IsShown(), "the session's end closes both")
end)

-- ── auto-arm ────────────────────────────────────────────────────────────────────────────────────

test("autoarm: targeting a dummy out of combat arms at the Race window's length", function()
    if forever() then return end
    local S = fixture{ arm = true }
    S.W.length = 120
    target(S, CLEAVE)
    assertEqual(S.NS.Race.State(), "armed")
    assertEqual(S.NS.Race.Current().length, 120, "the length Arm Race would arm")
    assertTrue(S.A.Diagnose().armed)
    assertFalse(S.W.ShownNearDummy(), "auto-show is off")
end)

test("autoarm: with no length from the Race window, the race's own default", function()
    if forever() then return end
    local S = fixture{ arm = true }
    S.NS.db.profile.race.lastLength = 180
    target(S, GOLEM)
    assertEqual(S.NS.Race.Current().length, 180)
end)

test("autoarm: a target that is no dummy arms nothing", function()
    if forever() then return end
    local S = fixture{ arm = true }
    target(S, BOAR)
    assertEqual(S.NS.Race.State(), "idle")
    target(S, nil)
    assertEqual(S.NS.Race.State(), "idle")
end)

test("autoarm: Race.Arm's refusals hold, silently: in combat, meter unavailable", function()
    if forever() then return end
    local S = fixture{ arm = true }
    S.M.__inCombat = true
    S.M.__resetPrinted()
    target(S, CLEAVE)
    assertEqual(S.NS.Race.State(), "idle", "armed in combat")
    S.M.__inCombat = false
    S.meter.SetAvailable(false, "Unavailable here")
    target(S, nil)
    target(S, CLEAVE)
    assertEqual(S.NS.Race.State(), "idle", "armed with the meter unavailable")
    assertEqual(#S.M.__printed(), 0, "a refusal printed")
end)

test("autoarm: no arm in test mode", function()
    if forever() then return end
    local S = fixture{ arm = true }
    assertTrue(S.NS.Preview.Start({ mode = "test" }))
    target(S, CLEAVE)
    assertEqual(S.NS.Race.State(), "idle", "armed in test mode")
end)

test("autoarm: targeting anything else before the pull disarms; another dummy keeps it", function()
    if forever() then return end
    local S = fixture{ arm = true }
    target(S, CLEAVE)
    assertEqual(S.NS.Race.State(), "armed")
    target(S, GOLEM)
    assertEqual(S.NS.Race.State(), "armed", "a second dummy is still a dummy")
    target(S, BOAR)
    assertEqual(S.NS.Race.State(), "idle", "a boar disarmed it")
    assertFalse(S.A.Diagnose().armed)
    target(S, CLEAVE)
    target(S, nil)
    assertEqual(S.NS.Race.State(), "idle", "clearing the target disarmed it")
end)

test("autoarm: a target change in combat never disarms, and a started race is no longer the rule's", function()
    if forever() then return end
    local S = F.fresh()
    fakeWindow(S.NS)
    assertTrue(S.NS.SetByPath("race.autoArm", true))
    target(S, F.DUMMY_GUID)
    assertEqual(S.NS.Race.State(), "armed")
    S.meter.SetSession(25, F.SESSION)
    F.enter(S, 101)
    target(S, nil)
    assertEqual(S.NS.Race.State(), "armed", "the pull under way was canceled")
    target(S, F.DUMMY_GUID)
    F.run(S, 101.25)
    F.hit(S, 102, 25)
    assertEqual(S.NS.Race.State(), "running")
    assertFalse(S.NS.AutoArm.Diagnose().armed, "a started race is no longer the rule's")
    target(S, BOAR)
    assertEqual(S.NS.Race.State(), "running")
end)

test("autoarm: a race the player armed is never the rule's to disarm", function()
    if forever() then return end
    local S = fixture{ arm = true }
    assertTrue(F.arm(S, 30, S.M.__now))
    target(S, BOAR)
    assertEqual(S.NS.Race.State(), "armed")
end)

test("autoarm: Cancel works as ever, and the next target change to a dummy arms again", function()
    if forever() then return end
    local S = fixture{ arm = true }
    target(S, CLEAVE)
    assertTrue(S.NS.Race.Cancel())
    assertEqual(S.NS.Race.State(), "idle")
    target(S, GOLEM)
    assertEqual(S.NS.Race.State(), "armed")
end)

-- ── profiles, Race mode, the instances and the stand-down ───────────────────────────────────────

test("autoarm: a profile switch re-reads both rows, with no /reload", function()
    if forever() then return end
    local S = fixture()
    S.NS.db:SetProfile("Other")
    assertTrue(S.NS.SetByPath("race.autoShow", false))
    assertTrue(S.NS.SetByPath("race.autoShowHud", false))
    assertTrue(S.NS.SetByPath("race.autoArm", true))
    S.NS.db:SetProfile("Default")
    assertEqual(S.A.Diagnose().events, "none", "the other profile's rules held on")
    S.NS.db:SetProfile("Other")
    assertEqual(S.A.Diagnose().events, "target", "the other profile's rules not registered")
end)

test("autoarm: Race mode off, neither rule registers or acts; on again, both come back", function()
    if forever() then return end
    local S = fixture{ arm = true, show = true }
    assertTrue(S.NS.SetByPath("race.enabled", false))
    assertEqual(S.A.Diagnose().events, "none")
    target(S, CLEAVE)
    assertFalse(S.W.wanted, "shown with Race mode off")
    assertEqual(S.NS.Race.State(), "idle", "armed with Race mode off")
    assertTrue(S.NS.SetByPath("race.enabled", true))
    assertEqual(S.A.Diagnose().events, "plates")
    target(S, nil)
    target(S, CLEAVE)
    assertEqual(S.NS.Race.State(), "armed")
end)

test("autoarm: neither rule acts in an instance or a battleground", function()
    if forever() then return end
    for _, kind in ipairs({ "party", "raid", "pvp", "arena", "scenario" }) do
        local S = fixture{ arm = true, show = true }
        S.M.__instance.type = kind
        target(S, CLEAVE)
        plateUp(S, "nameplate1", CLEAVE)
        assertEqual(S.NS.Race.State(), "idle", kind .. ": armed")
        assertFalse(S.W.wanted, kind .. ": shown")
    end
end)

test("autoarm: entering an instance closes the dummy's window", function()
    if forever() then return end
    local S = fixture{ show = true }
    target(S, CLEAVE)
    assertTrue(S.W.wanted)
    S.M.__instance.type = "party"
    S.M.__fire("PLAYER_ENTERING_WORLD")
    assertFalse(S.W.wanted)
end)

test("autoarm: stood down, nothing is registered and nothing acts; the stand-up rebuilds", function()
    if forever() then return end
    local S = fixture{ arm = true, show = true }
    target(S, CLEAVE)
    assertTrue(S.NS.SetByPath("general.enabled", false))
    assertEqual(S.A.Diagnose().events, "none")
    assertFalse(S.A.Diagnose().session)
    assertTrue(S.NS.SetByPath("general.enabled", true))
    assertEqual(S.A.Diagnose().events, "plates")
    target(S, nil)
    target(S, GOLEM)
    assertEqual(S.NS.Race.State(), "armed")
end)

-- ── the player's own open and close in a dummy session, on the real Race window ────────────────

--- The real Race window and DPS HUD, auto-show on (the HUD with it by default).
local function real()
    local S = fixture{ show = true, real = true }
    return S, S.NS.RaceWindow, S.NS.Hud
end

local function raceToggle(S) assertTrue(S.NS.SetRaceWindowShown("toggle")) end

test("autoshow window: InSession is live from the first dummy seen to the session's end", function()
    if forever() then return end
    local S = real()
    assertFalse(S.A.InSession())
    target(S, CLEAVE)
    assertTrue(S.A.InSession())
    away(S)
    assertFalse(S.A.InSession())
end)

test("autoshow window: detach, reattach, open and close by hand, walk away, come back", function()
    if forever() then return end
    local S, RW, Hud = real()
    target(S, CLEAVE)
    assertTrue(RW.IsShown() and RW.ShownNearDummy(), "auto-show opened the Race window")
    assertTrue(Hud.IsShown(), "and the DPS HUD")
    local closes = RW.Closes()
    RW.Detach()
    RW.Attach()
    assertTrue(RW.IsShown() and RW.ShownNearDummy(), "Detach and Attach change nothing of who opened it")
    assertEqual(RW.Closes(), closes, "and count no close")
    raceToggle(S)
    assertFalse(RW.IsShown(), "the player's close")
    assertEqual(RW.Closes(), closes + 1)
    raceToggle(S)
    assertTrue(RW.IsShown(), "the player's open")
    assertTrue(RW.ShownNearDummy(), "opened in the session, it is the session's")
    raceToggle(S)
    assertFalse(RW.IsShown(), "the player's second close")
    away(S)
    assertFalse(RW.IsShown(), "still shut after walking away")
    assertFalse(Hud.IsShown(), "the DPS HUD closed by its own rule")
    target(S, CLEAVE)
    assertTrue(RW.IsShown() and RW.ShownNearDummy(), "a new session opens the Race window again")
    assertTrue(Hud.IsShown(), "and the DPS HUD")
    away(S)
    assertFalse(RW.IsShown(), "and walking away closes it")
end)

test("autoshow window: the player's open in a session closes on walking away and opens on coming back", function()
    if forever() then return end
    local S, RW = real()
    target(S, CLEAVE)
    raceToggle(S)
    assertFalse(RW.IsShown())
    plateUp(S, "nameplate1", GOLEM)
    assertFalse(RW.IsShown(), "the player's close still holds it shut in the session")
    RW.Detach()
    raceToggle(S)
    RW.Attach()
    assertTrue(RW.IsShown(), "opened by hand, detached and reattached")
    local closes = RW.Closes()
    away(S)
    assertFalse(RW.IsShown(), "walking away closes a window the player opened in the session")
    assertEqual(RW.Closes(), closes, "the session's close is not the player's")
    plateUp(S, "nameplate1", CLEAVE)
    assertTrue(RW.IsShown(), "coming back opens it again")
end)

test("autoshow window: a window the player opened before the session stays theirs", function()
    if forever() then return end
    local S, RW = real()
    raceToggle(S)
    assertTrue(RW.IsShown())
    target(S, CLEAVE)
    assertFalse(RW.ShownNearDummy(), "the player's window is not the session's")
    RW.Detach()
    RW.Attach()
    assertFalse(RW.ShownNearDummy())
    away(S)
    assertTrue(RW.IsShown(), "walking away leaves the player's window open")
    raceToggle(S)
    assertFalse(RW.IsShown())
    raceToggle(S)
    assertFalse(RW.ShownNearDummy(), "opened with no session live, it is the player's")
    target(S, CLEAVE)
    away(S)
    assertTrue(RW.IsShown())
end)
