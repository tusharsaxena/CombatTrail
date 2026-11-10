-- tests/test_lane_casts.lua — the lanes' cast capture (plan Task 1.1, spec §4): what reaches each
-- lane's LANE_PUSH, the castGUID dedupe, the per-lane ignore lists and their per-client seeds, the
-- interrupt marks, secret spell IDs and castGUIDs, the pet's name, and the registrations following
-- general.enabled and each lane's own switch.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- A fresh instance with a recorder on LANE_PUSH: answers inst and the list of { lane, item } heard.
local function setup()
    local inst = T.load()
    local NS = inst.NS
    local heard = {}
    local target = NS.NewBusTarget()
    target:RegisterMessage(NS.MSG.LANE_PUSH, function(_, laneKey, item)
        heard[#heard + 1] = { lane = laneKey, item = item }
    end)
    return inst, heard
end

local function fire(inst, event, unit, guid, spellID)
    return inst.mocks.__fire(event, unit, guid, spellID)
end

-- The unit tokens LaneCasts' frame is registered for, per event: { [event] = { [unit] = true } }.
local function unitRegs(inst)
    local frame = inst.NS.LaneCasts.Frame()
    local out = {}
    for _, r in ipairs(inst.mocks.__registrations()) do
        if r.kind == "unit" and r.target == frame then
            out[r.event] = out[r.event] or {}
            out[r.event][r.unit] = true
        end
    end
    return out
end

local function setLane(inst, laneKey, key, value)
    inst.NS.db.profile.lanes[laneKey][key] = value
    inst.NS.AnnounceSettingsChanged("lanes." .. laneKey .. "." .. key, value)
end

-- ── defaults ────────────────────────────────────────────────────────────────────────────────────

test("lane casts: both lanes carry spec §4's defaults", function()
    local NS = T.load().NS
    local p, q = NS.db.profile.lanes.player, NS.db.profile.lanes.pet
    assertEqual(p.enabled, true)
    assertEqual(p.width, 480)
    assertEqual(p.seconds, 12)
    assertEqual(p.iconSize, 28)
    assertEqual(q.iconSize, 24)
    assertEqual(p.direction, "left")
    assertEqual(p.anchor.mode, "free")
    assertEqual(p.anchor.y, -200)
    assertEqual(q.anchor.mode, "dock")
    assertEqual(q.anchor.target, "player")
    assertEqual(q.anchor.gap, 4)
    assertEqual(p.strata, "LOW")
    assertEqual(p.levelOffset, 0)
    assertEqual(p.glowMinCD, 29)
    assertEqual(p.fade, 0.2)
    assertEqual(p.tickSpacing, "gcd15")
    assertEqual(p.labelText, "You")
    assertEqual(q.labelText, "")
    assertEqual(p.visibility.show, "always")
    assertEqual(p.visibility.hideAfter, 5)
    assertEqual(p.visibility.hideMounted, true)
    assertEqual(p.visibility.hideResting, false)
    assertEqual(p.visibility.where.world, true)
    assertEqual(p.visibility.where.raid, true)
end)

test("lane casts: delve and arena exist only on Retail (clients-§4)", function()
    local NS = T.load().NS
    local where = NS.db.profile.lanes.player.visibility.where
    local retail = NS.Compat.IsRetail()
    assertEqual(where.delve ~= nil, retail, "delve key present only on Retail")
    assertEqual(where.arena ~= nil, retail, "arena key present only on Retail")
end)

test("lane casts: the client's seed list is picked once (forever profile uses Forever seed list)", function()
    local NS = T.load().NS
    local want = NS.Compat.IsForever() and NS.IgnoreSeeds.Forever or NS.IgnoreSeeds.Retail
    assertTrue(NS.IGNORE_SEEDS == want, "NS.IGNORE_SEEDS is the " .. tostring(NS.Compat.ClientKey()) .. " list")
    for _, id in ipairs(want.player) do
        assertTrue(NS.LaneCasts.IsIgnored("player", id), "player seed " .. id .. " ignored")
    end
    for _, id in ipairs(want.pet) do
        assertTrue(NS.LaneCasts.IsIgnored("pet", id), "pet seed " .. id .. " ignored")
    end
end)

-- ── capture ─────────────────────────────────────────────────────────────────────────────────────

test("lane casts: player cast pushes to player lane", function()
    local inst, heard = setup()
    inst.mocks.__now = 42
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 133)
    assertEqual(#heard, 1)
    assertEqual(heard[1].lane, "player")
    assertEqual(heard[1].item.spellID, 133)
    assertEqual(heard[1].item.t, 42)
    assertEqual(heard[1].item.interrupted, false)
    assertTrue(heard[1].item.texture ~= nil, "a texture")
end)

test("lane casts: pet cast pushes to pet lane", function()
    local inst, heard = setup()
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "pet", "Cast-P1", 17253)
    assertEqual(#heard, 1)
    assertEqual(heard[1].lane, "pet")
    assertEqual(heard[1].item.spellID, 17253)
end)

test("lane casts: same castGUID twice pushes once", function()
    local inst, heard = setup()
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 133)
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 133)
    assertEqual(#heard, 1)
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 133)
    assertEqual(#heard, 2, "a new castGUID pushes again")
end)

test("lane casts: the dedupe memory stays bounded", function()
    local inst, heard = setup()
    for i = 1, 500 do fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. i, 133) end
    assertEqual(#heard, 500)
    assertTrue(inst.NS.LaneCasts.__seenCount("player") <= inst.NS.LaneCasts.SEEN_MAX, "bounded")
end)

test("lane casts: ignored spellID (6603) does not push", function()
    local inst, heard = setup()
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-A", 6603)
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-B", 75)
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "pet", "Cast-C", 6603)
    assertEqual(#heard, 0)
end)

test("lane casts: an unignored seed (stored false) pushes again", function()
    local inst, heard = setup()
    inst.NS.db.profile.lanes.player.ignore[6603] = false
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-A", 6603)
    assertEqual(#heard, 1)
end)

test("lane casts: per-lane ignore list is independent", function()
    local inst, heard = setup()
    inst.NS.db.profile.lanes.pet.ignore[2649] = true
    assertTrue(inst.NS.LaneCasts.IsIgnored("pet", 2649))
    assertFalse(inst.NS.LaneCasts.IsIgnored("player", 2649))
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "pet", "Cast-P", 2649)
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Q", 2649)
    assertEqual(#heard, 1)
    assertEqual(heard[1].lane, "player")
end)

test("lane casts: secret spellID still pushes with texture, no raise", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local inst, heard = setup()
        local asked
        inst.mocks.C_Spell.GetSpellTexture = function(id)
            asked = id
            return 136000 + T.reveal(id)
        end
        local s = T.secret(133)
        fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-S", s)
        assertEqual(#heard, 1, "the secret cast pushed")
        assertTrue(asked == s, "the texture was asked with the secret ID itself")
        assertEqual(heard[1].item.texture, 136133)
        assertEqual(heard[1].item.spellID, nil, "a secret spell ID never rides the payload")
        assertFalse(inst.NS.LaneCasts.IsIgnored("player", s), "a secret is never a key")
    end)
    restore()
    assertTrue(ok, tostring(err))
end)

test("lane casts: a texture lookup that raises still pushes, with no texture", function()
    local inst, heard = setup()
    inst.mocks.C_Spell.GetSpellTexture = function() error("boom") end
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-R", 133)
    assertEqual(#heard, 1)
    assertEqual(heard[1].item.texture, nil)
end)

test("lane casts: secret castGUID skips dedupe", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local inst, heard = setup()
        fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", T.secret("Cast-X"), 133)
        fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", T.secret("Cast-X"), 133)
        assertEqual(#heard, 2, "both pushed: a secret castGUID is never compared or keyed")
        assertEqual(inst.NS.LaneCasts.__seenCount("player"), 0, "nothing remembered")
    end)
    restore()
    assertTrue(ok, tostring(err))
end)

-- ── interrupts ──────────────────────────────────────────────────────────────────────────────────

test("lane casts: interrupted cast that had a start pushes with interrupted=true", function()
    local inst, heard = setup()
    fire(inst, "UNIT_SPELLCAST_START", "player", "Cast-F", 133)
    assertEqual(#heard, 0, "a start pushes nothing")
    fire(inst, "UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-F", 133)
    assertEqual(#heard, 1)
    assertEqual(heard[1].item.interrupted, true)
    fire(inst, "UNIT_SPELLCAST_FAILED", "player", "Cast-F", 133)
    assertEqual(#heard, 1, "the FAILED that follows the INTERRUPTED pushes nothing more")
end)

test("lane casts: a failed cast that had a start pushes with interrupted=true", function()
    local inst, heard = setup()
    fire(inst, "UNIT_SPELLCAST_START", "player", "Cast-G", 133)
    fire(inst, "UNIT_SPELLCAST_FAILED", "player", "Cast-G", 133)
    assertEqual(#heard, 1)
    assertEqual(heard[1].item.interrupted, true)
end)

test("lane casts: instant cast failure does not push", function()
    local inst, heard = setup()
    fire(inst, "UNIT_SPELLCAST_FAILED", "player", "Cast-I", 133)
    fire(inst, "UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-J", 133)
    assertEqual(#heard, 0)
end)

test("lane casts: a cast that started and succeeded pushes once, not interrupted", function()
    local inst, heard = setup()
    fire(inst, "UNIT_SPELLCAST_START", "player", "Cast-K", 133)
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-K", 133)
    fire(inst, "UNIT_SPELLCAST_FAILED", "player", "Cast-K", 133)
    assertEqual(#heard, 1)
    assertEqual(heard[1].item.interrupted, false)
end)

test("lane casts: a failed press during another cast does not mark the cast in flight", function()
    local inst, heard = setup()
    fire(inst, "UNIT_SPELLCAST_START", "player", "Cast-L", 133)
    fire(inst, "UNIT_SPELLCAST_FAILED", "player", "Cast-M", 116)
    assertEqual(#heard, 0)
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-L", 133)
    assertEqual(#heard, 1)
    assertEqual(heard[1].item.interrupted, false)
end)

test("lane casts: the interrupt mark can be turned off per lane", function()
    local inst, heard = setup()
    inst.NS.db.profile.lanes.player.markInterrupted = false
    fire(inst, "UNIT_SPELLCAST_START", "player", "Cast-N", 133)
    fire(inst, "UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-N", 133)
    assertEqual(#heard, 0)
end)

test("lane casts: a secret castGUID's interrupt pushes when a cast was in flight", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local inst, heard = setup()
        fire(inst, "UNIT_SPELLCAST_START", "player", T.secret("Cast-O"), 133)
        fire(inst, "UNIT_SPELLCAST_INTERRUPTED", "player", T.secret("Cast-O"), 133)
        assertEqual(#heard, 1)
        assertEqual(heard[1].item.interrupted, true)
        fire(inst, "UNIT_SPELLCAST_FAILED", "player", T.secret("Cast-P"), 116)
        assertEqual(#heard, 1, "a secret FAILED with nothing in flight pushes nothing")
    end)
    restore()
    assertTrue(ok, tostring(err))
end)

-- ── the pet ─────────────────────────────────────────────────────────────────────────────────────

test("lane casts: pet lane with no pet: PetName() is nil and label falls back", function()
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    M.__unitExists.pet = false
    assertEqual(NS.LaneCasts.PetName(), nil)
    assertEqual(NS.LaneCasts.LabelText("pet"), NS.L["Pet"])
    M.__unitExists.pet = true
    M.__unitNames.pet = "Grumble"
    assertEqual(NS.LaneCasts.PetName(), "Grumble")
    assertEqual(NS.LaneCasts.LabelText("pet"), "Grumble")
    NS.db.profile.lanes.pet.labelText = "Doggo"
    assertEqual(NS.LaneCasts.LabelText("pet"), "Doggo", "a typed label wins")
    assertEqual(NS.LaneCasts.LabelText("player"), "You")
end)

test("lane casts: a secret pet name reads as no name", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local inst = T.load()
        inst.mocks.__unitExists.pet = true
        inst.mocks.__unitNames.pet = T.secret("Grumble")
        assertEqual(inst.NS.LaneCasts.PetName(), nil)
        assertEqual(inst.NS.LaneCasts.LabelText("pet"), inst.NS.L["Pet"])
    end)
    restore()
    assertTrue(ok, tostring(err))
end)

-- ── registration ────────────────────────────────────────────────────────────────────────────────

test("lane casts: both lanes on registers the cast events for player and pet only", function()
    local inst = setup()
    local regs = unitRegs(inst)
    for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START",
                             "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
        assertTrue(regs[event] ~= nil, event .. " registered")
        assertTrue(regs[event].player and regs[event].pet, event .. " for player and pet")
        local n = 0
        for _ in pairs(regs[event]) do n = n + 1 end
        assertEqual(n, 2, event .. " for no other unit")
    end
end)

-- The fight record's listener (modules/Casts.lua) keeps both units registered whatever the lanes
-- show; these cases measure the lanes' own share with it taken off.
local function lanesOnly(inst)
    inst.NS.LaneCasts.Unlisten("casts")
    return inst
end

test("lane casts: a lane turned off drops its unit, both off registers nothing", function()
    local inst, heard = setup()
    lanesOnly(inst)
    setLane(inst, "pet", "enabled", false)
    local regs = unitRegs(inst)
    assertTrue(regs.UNIT_SPELLCAST_SUCCEEDED.player, "player stays")
    assertFalse(regs.UNIT_SPELLCAST_SUCCEEDED.pet ~= nil, "pet dropped")
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "pet", "Cast-P", 17253)
    assertEqual(#heard, 0, "a disabled lane hears nothing")
    setLane(inst, "player", "enabled", false)
    assertEqual(next(unitRegs(inst)), nil, "nothing registered")
    setLane(inst, "pet", "enabled", true)
    assertTrue(unitRegs(inst).UNIT_SPELLCAST_SUCCEEDED.pet, "pet back")
end)

test("lane casts: general.enabled off drops every registration, on rebuilds them", function()
    local inst, heard = setup()
    lanesOnly(inst)
    local NS = inst.NS
    NS.SetByPath("general.enabled", false)
    assertEqual(next(unitRegs(inst)), nil, "nothing registered while disabled")
    assertEqual(inst.mocks.__fireUnconditional(NS.LaneCasts.Frame(), "UNIT_SPELLCAST_SUCCEEDED",
        "player", "Cast-Z", 133), 1, "the handler is reachable")
    assertEqual(#heard, 0, "a stood-down handler pushes nothing")
    -- A setting changed while down comes back from CURRENT state (slash-commands-§7).
    NS.db.profile.lanes.pet.enabled = false
    NS.SetByPath("general.enabled", true)
    local regs = unitRegs(inst)
    assertTrue(regs.UNIT_SPELLCAST_SUCCEEDED.player, "player back")
    assertFalse(regs.UNIT_SPELLCAST_SUCCEEDED.pet ~= nil, "pet stays off")
end)

test("lane casts: a disabled login registers nothing", function()
    local inst = T.load({ enable = false })
    inst.NS.db.profile.general.enabled = false
    inst.NS.SyncEnabledHold()
    inst.mocks.LibStub("AceAddon-3.0"):EnableAddon(inst.NS)
    local frame = inst.NS.LaneCasts.Frame()
    local n = 0
    for _, r in ipairs(inst.mocks.__registrations()) do
        if frame and r.target == frame then n = n + 1 end
    end
    assertEqual(n, 0)
end)

test("lane casts: a listener hears every cast the lanes' rules keep, whatever each lane shows", function()
    local inst, heard = setup()
    local NS = inst.NS
    local got = {}
    NS.LaneCasts.Listen("probe-test", function(unit, spellID, t, interrupted)
        got[#got + 1] = { unit = unit, id = spellID, t = t, x = interrupted }
    end)
    setLane(inst, "pet", "enabled", false)
    NS.db.profile.lanes.player.ignore[2948] = true
    NS.db.profile.lanes.player.markInterrupted = false
    inst.mocks.__now = 7
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "pet", "Cast-P", 17253)
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-I", 2948)
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-I", 2948)
    fire(inst, "UNIT_SPELLCAST_START", "player", "Cast-X", 133)
    fire(inst, "UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-X", 133)
    fire(inst, "UNIT_SPELLCAST_FAILED", "player", "Cast-F", 116)
    assertEqual(#heard, 0, "no lane showed any of them")
    assertEqual(#got, 3, "the pet's, the ignored spell once, the interrupted cast; not the failed instant")
    assertEqual(got[1].unit, "pet")
    assertEqual(got[2].id, 2948)
    assertEqual(got[3].id, 133)
    assertTrue(got[3].x, "interrupted")
    assertEqual(got[1].t, 7)
    NS.LaneCasts.Unlisten("probe-test")
    fire(inst, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Q", 133)
    assertEqual(#got, 3, "off again")
end)
