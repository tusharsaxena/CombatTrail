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
-- Race's HUD answered them. Every case runs on tests/race_fixture.lua's instance (the scripted meter,
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
    S.W = fakeWindow(S.NS)
    S.A = S.NS.AutoArm
    if not opts.defaults then
        assertTrue(S.NS.SetByPath("race.autoShow", opts.show == true))
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
