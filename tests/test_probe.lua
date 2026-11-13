-- tests/test_probe.lua — `/ct probe` (plan Task 1.5, spec §3 and §10): the report's lines with and
-- without C_DamageMeter, the function list, the in-combat meter samples at +5 s and +2 s after combat,
-- the cast secrecy counts, secrets printed as <secret> and never handed to tostring, the pet-source
-- split, the pace bar's pet-fill anchor check, the debug console, the arming words and the stand-down.
-- The combat log event is never registered, on either client.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local EIGHT = {
    "GetAvailableCombatSessions", "GetCombatSessionFromID", "GetCombatSessionFromType",
    "GetCombatSessionSourceFromID", "GetCombatSessionSourceFromType", "GetSessionDurationSeconds",
    "IsDamageMeterAvailable", "ResetAllCombatSessions",
}

-- A fresh instance with the scripted meter: answers inst and the meter's controller.
local function withMeter(extra)
    local meter
    local inst = T.load{ mutate = function(m)
        meter = T.mockMeter.install(m)
        if extra then extra(m) end
    end }
    return inst, meter
end

local function session(meter, data)
    meter.SetSession(1, data or { damage = 1000, dps = 50, duration = 20,
                                  spells = { { id = 133, dmg = 600, dps = 30 }, { id = 116, dmg = 400, dps = 20 } } })
end

-- The first report line that holds `needle` (plain find), or nil.
local function lineWith(lines, needle)
    for _, line in ipairs(lines) do
        if line:find(needle, 1, true) then return line end
    end
    return nil
end

local function text(lines) return table.concat(lines, "\n") end

local function slash(inst, line)
    inst.mocks.__resetPrinted()
    inst.NS.Slash:OnSlash(line)
    return inst.mocks.__printed()
end

-- Enter combat as the client does: the lockdown flag first, then the edge event.
local function enterCombat(inst)
    inst.mocks.InCombatLockdown = function() return true end
    inst.mocks.__inCombat = true
    inst.mocks.__fire("PLAYER_REGEN_DISABLED")
end

local function leaveCombat(inst)
    inst.mocks.InCombatLockdown = function() return false end
    inst.mocks.__inCombat = false
    inst.mocks.__fire("PLAYER_REGEN_ENABLED")
end

-- The delays of the timers still live now (the kit's live set: armed AceTimer handles, canceled
-- ones left out), in order. The fight state machine's tick and settle (modules/Fight.lua) are not the
-- probe's and are left out, both each AceTimer handle and the client queue entry it rides.
local function delays(inst)
    local out, fights = {}, {}
    local others = inst.NS.Fight.Timers()
    -- The purge's daily timer (modules/Retention.lua) is not the probe's either.
    others.retention = inst.NS.Retention.Timer()
    for _, h in pairs(others) do
        fights[h] = true
        fights[h.callback or h] = true
    end
    for _, t in ipairs(inst.mocks.__timers()) do
        if t.delay and not fights[t] and not fights[t.fn] then out[#out + 1] = t.delay end
    end
    return out
end

local function probeRegs(inst)
    local frame = inst.NS.Probe.Frame()
    local out = {}
    if not frame then return out end
    for _, r in ipairs(inst.mocks.__registrations()) do
        if r.target == frame then out[#out + 1] = r end
    end
    return out
end

-- ── the report ─────────────────────────────────────────────────────────────────────────────────

test("probe: report runs with no C_DamageMeter", function()
    local inst = T.load()
    assertEqual(inst.mocks.C_DamageMeter, nil, "the base mock has no meter")
    local lines = inst.NS.Probe.Report()
    assertTrue(#lines > 3, "a report: " .. text(lines))
    assertTrue(lineWith(lines, "C_DamageMeter: missing") ~= nil, text(lines))
    assertTrue(lineWith(lines, "combat log: protected, not used") ~= nil, text(lines))
    assertTrue(lineWith(lines, "client: " .. inst.NS.Compat.ClientKey()) ~= nil, "the client line names the client")
end)

test("probe: the enemy view lists each enemy's every field (issue #6's feasibility)", function()
    local inst, meter = withMeter()
    session(meter, { damage = 1000, dps = 50, duration = 20, spells = { { id = 133, dmg = 1000, dps = 50 } },
                     enemies = { { name = "Angry Boar", creatureID = 1985, damage = 700 },
                                 { name = "Kobold", creatureID = 40, damage = 300 } } })
    local lines = inst.NS.Probe.Report()
    assertTrue(lineWith(lines, "enemy view (EnemyDamageTaken): enemies 2") ~= nil, text(lines))
    local first = lineWith(lines, "   enemy 1: ")
    assertTrue(first ~= nil, text(lines))
    assertTrue(first:find("name=Angry Boar", 1, true) ~= nil, first)
    assertTrue(first:find("totalAmount=700", 1, true) ~= nil, first)
    assertTrue(first:find("sourceCreatureID=1985", 1, true) ~= nil, first)
    assertTrue(lineWith(lines, "      drill-down by GUID: ") ~= nil, "each enemy's drill-down by GUID")
    local byID = lineWith(lines, "      drill-down by creature ID: ")
    assertTrue(byID ~= nil and byID:find("totalAmount=700", 1, true) ~= nil, text(lines))
    assertTrue(lineWith(lines, "   enemy view session: ") ~= nil, "the session table's own fields")
end)

-- A step color curve, scripted (issue #7's probe): points { x, color }, Evaluate answers the last
-- point at or below x, with secret channels when x is secret, as the client's native curve would.
local function installCurve(m)
    local function color(r, g, b, a)
        return { r = r, g = g, b = b, a = a, GetRGBA = function(self) return self.r, self.g, self.b, self.a end }
    end
    m.CreateColor = color
    m.Enum = m.Enum or {}
    m.Enum.LuaCurveType = { Linear = 0, Step = 1 }
    m.C_CurveUtil = { CreateColorCurve = function()
        local c = { points = {} }
        function c:SetType(kind) self.kind = kind end
        function c:AddPoint(x, col) self.points[#self.points + 1] = { x = x, col = col } end
        function c:Evaluate(x)
            local secret = T.isSecret(x)
            local n = T.reveal(x)
            local best
            for _, pt in ipairs(self.points) do
                if pt.x <= n then best = pt.col end
            end
            if not best then return nil end
            if not secret then return best end
            return color(T.secret(best.r), T.secret(best.g), T.secret(best.b), T.secret(best.a))
        end
        return c
    end }
end

test("probe: the spell color curve section says when the client has no curve API", function()
    local inst, meter = withMeter(function(m) m.C_CurveUtil = nil end)
    session(meter)
    local lines = inst.NS.Probe.Report()
    assertTrue(lineWith(lines, "spell color curve: C_CurveUtil no, CreateColorCurve no") ~= nil, text(lines))
    assertTrue(lineWith(lines, "spell color curve: not built (the API is missing)") ~= nil, text(lines))
    assertTrue(lineWith(lines, "C_CurveUtil functions (0): none") ~= nil, text(lines))
    assertTrue(lineWith(lines, "C_StringUtil functions (") ~= nil, text(lines))
end)

test("probe: the spell color curve maps a plain pet ID and a plain other ID to their colors", function()
    local inst, meter = withMeter(installCurve)
    session(meter)
    local lines = inst.NS.Probe.Report()
    assertTrue(lineWith(lines, "spell color curve: C_CurveUtil yes, CreateColorCurve yes, Enum.LuaCurveType.Step 1, CreateColor yes") ~= nil,
        text(lines))
    assertTrue(lineWith(lines, "Evaluate(16829) is the pet color: yes (0.40, 1.00, 0.40); Evaluate(75) is the player color: yes")
        ~= nil, text(lines))
    assertTrue(lineWith(lines, "C_CurveUtil functions (1): CreateColorCurve") ~= nil, text(lines))
end)

test("probe: each sample runs the formatter trial and the color curve on what the HUD draws", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local inst, meter = withMeter(installCurve)
        session(meter)
        slash(inst, "probe")
        meter.SetSecret(true)
        enterCombat(inst)
        inst.mocks.__fireTimers()
        meter.SetSecret(false)
        leaveCombat(inst)
        inst.mocks.__fireTimers()
        local lines = inst.NS.Probe.Report()
        assertTrue(lineWith(lines, "   combat+5s format trial: value secret") ~= nil, text(lines))
        assertTrue(lineWith(lines, "   combat+5s    string.format %d: ") ~= nil, text(lines))
        assertTrue(lineWith(lines, "   combat+5s spell color curve: spell ID secret; Evaluate ok; GetRGBA ok (red secret); SetStatusBarColor took it")
            ~= nil, text(lines))
        assertTrue(lineWith(lines, "   afterCombat+2s format trial: value plain 50") ~= nil, text(lines))
        assertTrue(lineWith(lines, "   afterCombat+2s spell color curve: spell ID plain; Evaluate ok") ~= nil, text(lines))
        for _, line in ipairs(lines) do
            assertEqual(line:find("trials raised", 1, true), nil, line)
        end
    end)
    restore()
    assertTrue(ok, tostring(err))
end)

test("probe: report lists the 8 functions with mock meter", function()
    local inst, meter = withMeter()
    session(meter)
    local lines = inst.NS.Probe.Report()
    local fns = lineWith(lines, "C_DamageMeter functions (8): ")
    assertTrue(fns ~= nil, text(lines))
    for _, name in ipairs(EIGHT) do
        assertTrue(fns:find(name, 1, true) ~= nil, name .. " listed")
    end
    assertEqual(lineWith(lines, "functions not found"), nil, "nothing expected is missing")
    assertTrue(lineWith(lines, "IsDamageMeterAvailable: ok, available true") ~= nil, text(lines))
    assertTrue(lineWith(lines, "Enum.DamageMeterType: ") ~= nil, text(lines))
    assertTrue(lineWith(lines, "DamageDone=0") ~= nil, text(lines))
    assertTrue(lineWith(lines, "Enum.DamageMeterSessionType: ") ~= nil, text(lines))
    assertTrue(lineWith(lines, "sessions: 1") ~= nil, text(lines))
    assertTrue(lineWith(lines, "player source: total 1000, dps 50, spells 2") ~= nil, text(lines))
    assertTrue(lineWith(lines, "spell 133 total 600 creature nil") ~= nil, text(lines))
    assertTrue(lineWith(lines, "current session: sources 1, duration 20") ~= nil, text(lines))
    assertTrue(lineWith(lines, "GetSessionDurationSeconds(current): 20") ~= nil, text(lines))
end)

test("probe: a function the client lacks is named", function()
    local inst, meter = withMeter()
    session(meter)
    inst.mocks.C_DamageMeter.ResetAllCombatSessions = nil
    local lines = inst.NS.Probe.Report()
    assertTrue(lineWith(lines, "C_DamageMeter functions (7): ") ~= nil, text(lines))
    assertTrue(lineWith(lines, "functions not found: ResetAllCombatSessions") ~= nil, text(lines))
end)

test("probe: a meter call that raises is reported, never raised", function()
    local inst, meter = withMeter()
    session(meter)
    meter.SetRaise("GetAvailableCombatSessions", "boom")
    meter.SetRaise("GetCombatSessionSourceFromType", "bang")
    local ok, lines = pcall(inst.NS.Probe.Report)
    assertTrue(ok, tostring(lines))
    assertTrue(lineWith(lines, "sessions: raised") ~= nil, text(lines))
    assertTrue(lineWith(lines, "player source: raised") ~= nil, text(lines))
end)

test("probe: secret values reported as <secret>, never tostring'd", function()
    local handed = 0
    local inst, meter = withMeter(function(m)
        m.tostring = function(v)
            if T.isSecret(v) then handed = handed + 1 end
            return tostring(v)
        end
    end)
    session(meter)
    meter.SetSecret(true)
    local ok, lines = pcall(inst.NS.Probe.Report)
    assertTrue(ok, tostring(lines))
    assertTrue(lineWith(lines, "player source: total <secret>, dps <secret>") ~= nil, text(lines))
    assertTrue(lineWith(lines, "duration <secret>") ~= nil, text(lines))
    assertEqual(handed, 0, "no secret reached tostring")
    for _, line in ipairs(lines) do assertEqual(type(line), "string") end
end)

test("probe: the report is written to the debug console in one chat line", function()
    local inst, meter = withMeter()
    session(meter)
    local printed = slash(inst, "probe")
    assertEqual(#printed, 1, table.concat(printed, "\n"))
    assertTrue(printed[1]:find("debug console", 1, true) ~= nil, printed[1])
    local D = inst.NS.DebugLog
    assertTrue(D:FindLine("combat log: protected, not used") ~= nil, "the console holds the report")
    assertTrue(D:FindLine("C_DamageMeter functions (8)") ~= nil, "the console holds the function list")
    assertTrue(D:IsShown(), "the console is shown")
end)

test("probe never registers COMBAT_LOG_EVENT_UNFILTERED", function()
    local inst, meter = withMeter()
    session(meter)
    slash(inst, "probe start")
    slash(inst, "probe")
    enterCombat(inst)
    inst.mocks.__fireTimers()
    for _, r in ipairs(inst.mocks.__registrations()) do
        assertTrue(r.event ~= "COMBAT_LOG_EVENT_UNFILTERED", "nothing is registered for the combat log")
    end
    for _, event in ipairs(inst.NS.rejectedEvents) do
        assertTrue(event ~= "COMBAT_LOG_EVENT_UNFILTERED", "nothing even tried")
    end
    local f = io.open(T.root .. "/modules/Probe.lua", "rb")
    local src = f:read("*a")
    f:close()
    assertEqual(src:find("Register[%a]*Event%s*%([^)]*COMBAT_LOG"), nil, "no registration call names it")
end)

-- ── arming and the combat samples ──────────────────────────────────────────────────────────────

test("probe: in-combat samples recorded via kit combat toggle", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local inst, meter = withMeter()
        session(meter)
        local Probe = inst.NS.Probe
        slash(inst, "probe")
        assertTrue(Probe.IsArmed(), "the default arms the next combat")
        meter.SetSecret(true)
        enterCombat(inst)
        assertEqual(table.concat(delays(inst), ","), "5", "one sample 5 s into combat")
        inst.mocks.__fireTimers()
        meter.SetSecret(false)
        leaveCombat(inst)
        assertEqual(table.concat(delays(inst), ","), "2", "one sample 2 s after combat")
        inst.mocks.__resetPrinted()
        inst.mocks.__fireTimers()
        local printed = inst.mocks.__printed()
        assertEqual(#printed, 1, "one line says the fight was sampled")
        assertFalse(Probe.IsArmed(), "one combat, then the probe stops watching")
        assertEqual(#probeRegs(inst), 0, "and its registrations are gone")
        local lines = Probe.Report()
        assertTrue(lineWith(lines, "meter sample combat+5s: player total secret, dps secret, spells plain") ~= nil,
            text(lines))
        assertTrue(lineWith(lines, "meter sample afterCombat+2s: player total plain, dps plain, spells plain") ~= nil,
            text(lines))
    end)
    restore()
    assertTrue(ok, tostring(err))
end)

test("probe: a second /ct probe after the fight reports without arming again", function()
    local inst, meter = withMeter()
    session(meter)
    slash(inst, "probe")
    enterCombat(inst)
    inst.mocks.__fireTimers()
    leaveCombat(inst)
    inst.mocks.__fireTimers()
    slash(inst, "probe")
    assertFalse(inst.NS.Probe.IsArmed(), "samples are in: the report is all it does")
end)

test("probe: start in combat takes the +5 s sample now", function()
    local inst, meter = withMeter()
    session(meter)
    inst.mocks.InCombatLockdown = function() return true end
    slash(inst, "probe start")
    assertTrue(inst.NS.Probe.IsArmed())
    assertEqual(table.concat(delays(inst), ","), "5")
end)

test("probe: start resets the counts and samples; stop disarms", function()
    local inst, meter = withMeter()
    session(meter)
    local Probe = inst.NS.Probe
    slash(inst, "probe start")
    inst.mocks.__fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 133)
    assertEqual(Probe.Counts().outCombat.n, 1)
    slash(inst, "probe start")
    assertEqual(Probe.Counts().outCombat.n, 0, "start begins again")
    local printed = slash(inst, "probe stop")
    assertEqual(#printed, 1)
    assertFalse(Probe.IsArmed())
    assertEqual(#probeRegs(inst), 0)
end)

test("probe: an unknown word answers the usage line", function()
    local inst = T.load()
    local printed = slash(inst, "probe wibble")
    assertEqual(#printed, 1)
    assertTrue(printed[1]:find("Usage", 1, true) ~= nil, printed[1])
    assertFalse(inst.NS.Probe.IsArmed())
end)

test("probe: cast secrecy counts, in and out of combat, player and pet", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local inst = T.load()
        local Probe = inst.NS.Probe
        slash(inst, "probe start")
        local regs = probeRegs(inst)
        local units = {}
        for _, r in ipairs(regs) do
            if r.event == "UNIT_SPELLCAST_SUCCEEDED" then units[#units + 1] = r.unit end
        end
        table.sort(units)
        assertEqual(table.concat(units, ","), "pet,player", "casts heard for the player and the pet")
        inst.mocks.__fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 133)
        inst.mocks.__fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "Cast-2", 17253)
        inst.mocks.InCombatLockdown = function() return true end
        inst.mocks.__fire("UNIT_SPELLCAST_SUCCEEDED", "player", T.secret("Cast-3"), T.secret(133))
        local c = Probe.Counts()
        assertEqual(c.outCombat.n, 2)
        assertEqual(c.outCombat.pet, 1)
        assertEqual(c.outCombat.secretID, 0)
        assertEqual(c.inCombat.n, 1)
        assertEqual(c.inCombat.secretID, 1)
        assertEqual(c.inCombat.secretGUID, 1)
        local lines = Probe.Report()
        assertTrue(lineWith(lines, "casts out of combat: 2, secret spell IDs 0, secret castGUIDs 0, pet 1") ~= nil,
            text(lines))
        assertTrue(lineWith(lines, "casts in combat: 1, secret spell IDs 1, secret castGUIDs 1, pet 0") ~= nil,
            text(lines))
    end)
    restore()
    assertTrue(ok, tostring(err))
end)

-- ── the pet split and the pace bar's pet fill ──────────────────────────────────────────────────

local function petSession(meter, petSpells, playerSpells)
    meter.SetPetGUID("Pet-0-1-2")
    meter.SetSession(1, {
        damage = 1000, dps = 50, duration = 20,
        spells = playerSpells or { { id = 133, dmg = 1000, dps = 50 } },
        pet = { damage = 300, dps = 15, spells = petSpells },
    })
end

test("probe: pet is separate source: yes", function()
    local inst, meter = withMeter(function(m) m.__unitExists.pet = true end)
    petSession(meter, { { id = 17253, dmg = 300, dps = 15 } })
    local lines = inst.NS.Probe.Report()
    assertTrue(lineWith(lines, "pet is separate source: yes") ~= nil, text(lines))
    assertTrue(lineWith(lines, "pet source: total 300, dps 15, spells 1") ~= nil, text(lines))
end)

test("probe: pet is separate source: no while the pet's own source is empty", function()
    local inst, meter = withMeter(function(m) m.__unitExists.pet = true end)
    meter.SetPetGUID("Pet-0-1-2")
    session(meter)
    local lines = inst.NS.Probe.Report()
    assertTrue(lineWith(lines, "pet is separate source: no") ~= nil, text(lines))
end)

test("probe: pet is separate source: no while the player's source holds the pet's spells", function()
    local inst, meter = withMeter(function(m) m.__unitExists.pet = true end)
    petSession(meter, { { id = 17253, dmg = 300, dps = 15 } },
        { { id = 133, dmg = 700, dps = 35 }, { id = 17253, dmg = 300, dps = 15 } })
    local lines = inst.NS.Probe.Report()
    local line = lineWith(lines, "pet is separate source: no")
    assertTrue(line ~= nil and line:find("pet's spells", 1, true) ~= nil, text(lines))
end)

test("probe: pet is separate source: unknown with no pet, or while the values are secret", function()
    local inst, meter = withMeter()
    session(meter)
    assertTrue(lineWith(inst.NS.Probe.Report(), "pet is separate source: unknown") ~= nil, "no pet")
    local inst2, meter2 = withMeter(function(m) m.__unitExists.pet = true end)
    petSession(meter2, { { id = 17253, dmg = 300, dps = 15 } })
    meter2.SetSecret(true)
    local lines = inst2.NS.Probe.Report()
    local line = lineWith(lines, "pet is separate source: unknown")
    assertTrue(line ~= nil and line:find("secret", 1, true) ~= nil, text(lines))
end)

-- The folded pet (callout plan row C7): each sample counts the pet's rows in the player's source and
-- their secrecy, and says what the HUD's live Pet figure is, so the owner can see on WoW Forever
-- whether the meter's values and the pet's rows are secret in combat.
local FOLDED = { damage = 1700, dps = 85, duration = 20, pet = false, spells = {
    { id = 133, dmg = 1000, dps = 50, creature = "" }, { id = 6603, dmg = 300, dps = 15, creature = "Wolf" },
    { id = 17253, dmg = 400, dps = 20, creature = "Wolf" },
} }

test("probe: each sample with a pet out counts the pet's rows in the player's source and their secrecy", function()
    local restore = T.installSecretValue()
    local ok, err = pcall(function()
        local inst, meter = withMeter(function(m) m.__unitExists.pet = true end)
        meter.SetPetGUID("Pet-0-1-2")
        meter.SetSession(1, FOLDED)
        local Probe = inst.NS.Probe
        slash(inst, "probe")
        meter.SetSecret(true)
        enterCombat(inst)
        inst.mocks.__fireTimers()
        meter.SetSecret(false)
        leaveCombat(inst)
        inst.mocks.__fireTimers()
        local lines = Probe.Report()
        local folds = inst.NS.Meter.FOLDS_PET
        local secret = lineWith(lines, "combat+5s pet rows in player source: 3 row(s), 3 with a secret name, "
            .. "0 named a creature (0 with a secret amount); player total secret; live Pet figure: "
            .. (folds and "dash" or "none"))
        assertTrue(secret ~= nil, text(lines))
        local plain = lineWith(lines, "afterCombat+2s pet rows in player source: 3 row(s), 0 with a secret name, "
            .. "2 named a creature (0 with a secret amount); player total plain; live Pet figure: "
            .. (folds and "split" or "none"))
        assertTrue(plain ~= nil, text(lines))
    end)
    restore()
    assertTrue(ok, tostring(err))
end)

test("probe: no pet out: the samples carry no pet-rows line", function()
    local inst, meter = withMeter()
    session(meter)
    slash(inst, "probe")
    enterCombat(inst)
    inst.mocks.__fireTimers()
    assertTrue(lineWith(inst.NS.Probe.Report(), "pet rows in player source") == nil)
    assertTrue(meter ~= nil)
end)

test("probe: pace pet-fill anchor check builds hidden bars and reports ok", function()
    local inst, meter = withMeter()
    session(meter)
    local bars = {}
    local create = inst.mocks.CreateFrame
    inst.mocks.CreateFrame = function(kind, ...)
        local f = create(kind, ...)
        if kind == "StatusBar" then bars[#bars + 1] = f end
        return f
    end
    local lines = inst.NS.Probe.Report()
    assertTrue(lineWith(lines, "pace pet-fill anchor: ok") ~= nil, text(lines))
    assertEqual(#bars, 2, "two StatusBars")
    for _, b in ipairs(bars) do assertFalse(b:IsShown(), "built hidden") end
    inst.NS.Probe.Report()
    assertEqual(#bars, 2, "built once, the answer kept")
end)

test("probe: pace pet-fill anchor reports a SetPoint that raised", function()
    local inst = T.load()
    local create = inst.mocks.CreateFrame
    local n = 0
    inst.mocks.CreateFrame = function(kind, ...)
        local f = create(kind, ...)
        if kind == "StatusBar" then
            n = n + 1
            if n == 2 then rawset(f, "SetPoint", function() error("cannot anchor to a texture") end) end
        end
        return f
    end
    local lines = inst.NS.Probe.Report()
    local line = lineWith(lines, "pace pet-fill anchor: SetPoint raised")
    assertTrue(line ~= nil and line:find("cannot anchor", 1, true) ~= nil, text(lines))
end)

-- ── the lifecycle ──────────────────────────────────────────────────────────────────────────────

test("probe: stand-down drops its registrations; stand-up brings them back while armed", function()
    local inst = T.load()
    local NS = inst.NS
    slash(inst, "probe start")
    assertTrue(#probeRegs(inst) > 0, "armed: registered")
    NS.Slash:OnSlash("disable")
    assertEqual(#probeRegs(inst), 0, "stood down: nothing registered")
    NS.Slash:OnSlash("enable")
    assertTrue(#probeRegs(inst) > 0, "stood up while armed: registered again")
    slash(inst, "probe stop")
    NS.Slash:OnSlash("disable")
    NS.Slash:OnSlash("enable")
    assertEqual(#probeRegs(inst), 0, "stood up while off: nothing")
end)

test("probe: nothing is registered until the probe is armed", function()
    local inst = T.load()
    assertEqual(#probeRegs(inst), 0)
    assertFalse(inst.NS.Probe.IsArmed())
end)

-- ── deferred review items (plan Task 5.2b) ──────────────────────────────────────────────────────

test("probe: Disarm and a fresh Arm cancel the samples still pending", function()
    local inst, meter = withMeter()
    session(meter)
    local Probe = inst.NS.Probe
    slash(inst, "probe")
    enterCombat(inst)
    assertEqual(table.concat(delays(inst), ","), "5")
    slash(inst, "probe stop")
    assertEqual(#delays(inst), 0, "stop cancels the +5 s sample")
    slash(inst, "probe start")
    assertEqual(table.concat(delays(inst), ","), "5", "start in combat takes it again")
    Probe.Arm(true)
    assertEqual(table.concat(delays(inst), ","), "5", "a fresh arm cancels the old one: one timer, not two")
end)

test("probe: a plain /ct probe in combat schedules the +5 s sample, one per combat", function()
    local inst, meter = withMeter()
    session(meter)
    inst.mocks.InCombatLockdown = function() return true end
    inst.mocks.__inCombat = true
    slash(inst, "probe")
    assertTrue(inst.NS.Probe.IsArmed())
    assertEqual(table.concat(delays(inst), ","), "5", "armed in combat, the sample is scheduled now")
    inst.mocks.__fire("PLAYER_REGEN_DISABLED")
    assertEqual(table.concat(delays(inst), ","), "5", "a second edge in the same combat adds none")
    slash(inst, "probe")
    assertEqual(table.concat(delays(inst), ","), "5", "nor does a second report")
end)

test("probe: a function the client lacks reads missing, not raised", function()
    local inst, meter = withMeter()
    session(meter)
    inst.mocks.C_DamageMeter.GetAvailableCombatSessions = nil
    inst.mocks.C_DamageMeter.GetSessionDurationSeconds = nil
    local lines = inst.NS.Probe.Report()
    assertTrue(lineWith(lines, "sessions: missing") ~= nil, text(lines))
    assertTrue(lineWith(lines, "GetSessionDurationSeconds(current): missing") ~= nil, text(lines))
    assertTrue(lineWith(lines, "raised: missing") == nil, text(lines))
end)

test("probe: the pet verdict says it cannot see double counting", function()
    local inst, meter = withMeter(function(m) m.__unitExists.pet = true end)
    petSession(meter, { { id = 17253, dmg = 300, dps = 15 } })
    local lines = inst.NS.Probe.Report()
    assertTrue(lineWith(lines, "pet is separate source: yes (it cannot tell whether your own total also counts the pet's damage)") ~= nil, text(lines))
end)

-- ── the talent trees (v0.2 plan Task A4, D11) ──────────────────────────────────────────────────

test("probe: forever: the report dumps every talent API's answer and the tree it picks", function()
    local inst = T.load{ mutate = function(m)
        m.GetNumTalentTabs = function() return 2 end
        m.GetTalentTabInfo = function(i) return ({ "Holy", "Shadow" })[i], 100 + i, ({ 11, 40 })[i], "bg" end
        m.__talents.treeIDs = { 900 }
        m.C_Traits.GetGroupDisplayInfoByTreeID = function()
            return { { groupID = 11, displayName = "Holy", orderIndex = 1 },
                     { groupID = 12, displayName = "Shadow", orderIndex = 2 } }
        end
        m.C_Traits.GetGroupCurrencyInfo = function()
            return { { traitNodeGroupID = 11, currencyInfos = { { spent = 11 } } },
                     { traitNodeGroupID = 12, currencyInfos = { { spent = 40 } } } }
        end
    end }
    T.Loader.MockClient.apply(inst.mocks, "forever")
    local lines = inst.NS.Probe.Report()
    T.Loader.MockClient.apply(T.mocks)
    assertTrue(lineWith(lines, "talent tabs: GetNumTalentTabs function, GetTalentTabInfo function, count 2") ~= nil,
               text(lines))
    assertTrue(lineWith(lines, "talent tab 2: Shadow, 102, 40, bg") ~= nil, text(lines))
    assertTrue(lineWith(lines, "talent config: active 7001") ~= nil, text(lines))
    assertTrue(lineWith(lines, "trait tree 900: 2 groups") ~= nil, text(lines))
    assertTrue(lineWith(lines, "trait group 12: displayName=Shadow, groupID=12, orderIndex=2") ~= nil, text(lines))
    assertTrue(lineWith(lines, "trait group 12 spent: 40") ~= nil, text(lines))
    assertTrue(lineWith(lines, "talent tree pick: Shadow (11/40), icon 102") ~= nil, text(lines))
end)

test("probe: forever: missing or secret talent answers never raise", function()
    local restore = T.installSecretValue()
    local ok, lines = pcall(function()
        local inst = T.load{ mutate = function(m)
            m.GetNumTalentTabs = function() return T.secret(3) end
            m.GetTalentTabInfo = function() error("boom") end
        end }
        T.Loader.MockClient.apply(inst.mocks, "forever")
        return inst.NS.Probe.Report()
    end)
    restore()
    T.Loader.MockClient.apply(T.mocks)
    assertTrue(ok, tostring(lines))
    assertTrue(lineWith(lines, "count <secret>") ~= nil, text(lines))
    assertTrue(lineWith(lines, "talent tree pick: none") ~= nil, text(lines))
end)

test("probe: forever: a talent read that raises prints one line and the rest of the report", function()
    local inst = T.load()
    T.Loader.MockClient.apply(inst.mocks, "forever")
    inst.NS.Compat.TalentApis = function() error("boom") end
    local ok, lines = pcall(inst.NS.Probe.Report)
    T.Loader.MockClient.apply(T.mocks)
    assertTrue(ok, tostring(lines))
    assertTrue(lineWith(lines, "talent apis: raised: ") ~= nil, text(lines))
    assertTrue(lineWith(lines, "pace pet-fill anchor: ") ~= nil, text(lines))
end)

test("probe: retail: no talent-tree section (clients-§4)", function()
    local inst = T.load()
    T.Loader.MockClient.apply(inst.mocks, "retail")
    local lines = inst.NS.Probe.Report()
    T.Loader.MockClient.apply(T.mocks)
    assertTrue(lineWith(lines, "talent tree pick") == nil, text(lines))
    assertTrue(lineWith(lines, "talent tabs") == nil, text(lines))
end)
