local _, NS = ...
-- modules/Probe.lua — `/kct probe` (spec §3 and §10, plan Task 1.5): the built-in version of the
-- owner's throwaway KCTProbe, for the in-game checks the run could not make headless. It writes a
-- plain-text report to the debug console, where the console's Copy button lifts it out:
--   * the client line (client, version, build, interface) and which version-variant APIs exist
--   * "combat log: protected, not used"
--   * C_DamageMeter: present or missing, its function list against the eight the client ships,
--     IsDamageMeterAvailable, both enums, the session count, the player's and the pet's sources in
--     the Current session (top five spells each), the Current session's sources and its duration
--   * "pet is separate source": yes when the pet's GUID answers a source of its own that is not
--     empty while the player's source holds none of the pet's spells (spec §12's pet-split seam).
--     It cannot see double counting: whether the player's own total also holds the pet's damage
--     is a sum the meter alone could answer, so a "yes" says so beside it.
--   * "pace pet-fill anchor": two hidden StatusBars, bar B's LEFT anchored to bar A's fill texture's
--     RIGHT, and whether that SetPoint raised (the pace bar's pet fill, plan Task 3.2)
--   * the cast secrecy counts and the meter's secrecy samples 5 s into combat and 2 s after it.
--
-- ARMING. Nothing is registered until the probe is armed. `/kct probe` writes the report and, while
-- no fight has been sampled, arms the probe for the next combat; `/kct probe start` arms it now with
-- fresh counts; `/kct probe stop` disarms it. Armed in combat, either way, the +5 s sample is
-- scheduled from then, and a combat schedules one in-combat sample however many edges it sees.
-- An armed probe hears UNIT_SPELLCAST_SUCCEEDED for the player and the pet and the two
-- PLAYER_REGEN_* edges, and disarms itself after the sample 2 s past the end of one combat.
--
-- NEVER COMBAT_LOG_EVENT_UNFILTERED. Registering it is protected for addons on WoW Forever (the client
-- raises ADDON_ACTION_FORBIDDEN, which pcall does not catch; the owner's BugGrabber report,
-- 2026-11-10) and on Retail. The report says so instead of probing it.
--
-- SECRETS (spec §3). In combat the meter's numbers, spell IDs and castGUIDs may be secret. Every value
-- the report prints goes through show(), which asks NS.Secrets FIRST and prints a secret as
-- "<secret>": a secret never meets tostring, string.format, a comparison or a table key. Counting a
-- secret only asks NS.Secrets.IsSecret of it. Tables are read only after NS.Secrets.CanAccessTable,
-- and arrays only through NS.Secrets.SafeIterate.
--
-- LIFECYCLE. The probe is in core/LifecycleSetup.lua's MODULES list: Suspend drops its registrations
-- and timers, Resume registers again from the CURRENT armed flag. The verb is a feature verb, so the
-- dispatcher refuses it while the addon is disabled.
--
-- THROUGH THE METER ADAPTER, RAW. modules/Meter.lua is the only file that names the client's meter;
-- this file reaches it through NS.Meter.Api (the namespace, for the function list) and NS.Meter.Call
-- (each function, pcall'd), and nothing else of the adapter's: the probe exists to check the client
-- the adapter is built on, so it reads the raw shapes (each field's secrecy, the error a call
-- raised, the pet's source beside the player's) that the adapter's reads deliberately fold away.

local Probe = {}
NS.Probe = Probe

local Secrets = NS.Secrets
local Perf = NS.Perf
local L = NS.L

--- The eight functions the client's C_DamageMeter carries (the kit's live client list; the owner's
--- Forever probe, build 70862, listed the same eight).
Probe.EXPECTED_FUNCTIONS = {
    "GetAvailableCombatSessions", "GetCombatSessionFromID", "GetCombatSessionFromType",
    "GetCombatSessionSourceFromID", "GetCombatSessionSourceFromType", "GetSessionDurationSeconds",
    "IsDamageMeterAvailable", "ResetAllCombatSessions",
}

--- Seconds into combat for the in-combat sample, and seconds after combat for the last one.
Probe.SAMPLE_IN_COMBAT = 5
Probe.SAMPLE_AFTER_COMBAT = 2

-- How many spells and sources of each list the report prints.
local TOP = 5

-- The documented enum values, for a client that ships the namespace without the enum.
local SESSION_CURRENT_DEFAULT, DAMAGE_DONE_DEFAULT = 1, 0

local frame            -- the event frame (nil until the probe first arms)
local armed = false    -- session state: watching casts and the next combat
local counts           -- { inCombat = bucket, outCombat = bucket }
local samples = {}     -- the meter samples, as report lines
local timers = {}      -- the pending sample timers
local combatSample     -- true once this combat's in-combat sample is scheduled
local anchorLine       -- the pace pet-fill anchor's answer, kept once found

local function newBucket() return { n = 0, secretID = 0, secretGUID = 0, pet = 0 } end
local function resetCounts() counts = { inCombat = newBucket(), outCombat = newBucket() } end
resetCounts()

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Probe", fmt, ...) end
end

-- ── printing a value ───────────────────────────────────────────────────────────────────────────

--- One value as report text. The secret test runs FIRST, so a secret never reaches tostring, nor
--- even a nil test (a secret boolean such as isLocalPlayer must not meet a comparison).
local function show(v)
    if Secrets.IsSealed(v) then return "<secret>" end
    if v == nil then return "nil" end
    local kind = type(v)
    if kind == "string" or kind == "number" or kind == "boolean" then return tostring(v) end
    return kind
end

local function yesNo(b) return b and "yes" or "no" end

local function secrecy(v)
    if Secrets.IsSecret(v) then return "secret" end
    if v == nil then return "nil" end
    return "plain"
end

-- ── the meter, read safely ─────────────────────────────────────────────────────────────────────

--- The client meter's function `name` through NS.Meter.Call (pcall'd). Answers ok plus up to two
--- results, or false plus what went wrong: "missing" when the function is not there, else
--- "raised: <error>".
local function call(name, ...)
    local ok, a, b = NS.Meter.Call(name, ...)
    if ok then return true, a, b end
    if a == "unavailable" then return false, "missing" end
    return false, "raised: " .. show(b)
end

local function hasMeter() return NS.Meter.Api() ~= nil end

local function enumValue(enumName, key, default)
    local e = Enum and Enum[enumName]
    local v = type(e) == "table" and Secrets.PlainNumber(e[key]) or nil
    return v or default
end

local function sessionCurrent() return enumValue("DamageMeterSessionType", "Current", SESSION_CURRENT_DEFAULT) end
local function damageDone() return enumValue("DamageMeterType", "DamageDone", DAMAGE_DONE_DEFAULT) end

local function field(t, key)
    if not Secrets.CanAccessTable(t) then return nil end
    return t[key]
end

--- A unit's source in the Current session: ok, source table (or nil), error text.
local function sourceOf(guid)
    local ok, src = call("GetCombatSessionSourceFromType", sessionCurrent(), damageDone(), guid, nil)
    if not ok then return false, nil, src end
    return true, src
end

-- ── the report's sections ──────────────────────────────────────────────────────────────────────

local function clientLines(out)
    local version, build, iface = NS.Compat.BuildInfo()
    out[#out + 1] = ("client: %s, version %s, build %s, interface %s"):format(show(NS.Compat.ClientKey()),
        show(version), show(build), show(iface))
    local apis = NS.Compat.ClientApis()
    out[#out + 1] = ("secrets system: %s; C_Spell.GetSpellTexture: %s; C_Spell.GetSpellInfo: %s"):format(
        yesNo(apis.secrets), yesNo(apis.spellTexture), yesNo(apis.spellInfo))
    out[#out + 1] = "combat log: protected, not used"
end

local function functionLines(out)
    local api = NS.Meter.Api()
    local names, have = {}, {}
    if Secrets.CanAccessTable(api) then
        for k, v in pairs(api) do
            if type(k) == "string" and type(v) == "function" then
                names[#names + 1] = k
                have[k] = true
            end
        end
    end
    table.sort(names)
    out[#out + 1] = ("C_DamageMeter functions (%d): %s"):format(#names, table.concat(names, ", "))
    local missing = {}
    for _, name in ipairs(Probe.EXPECTED_FUNCTIONS) do
        if not have[name] then missing[#missing + 1] = name end
    end
    if #missing > 0 then
        out[#out + 1] = "C_DamageMeter functions not found: " .. table.concat(missing, ", ")
    end
end

local function availabilityLine(out)
    local ok, available, reason = call("IsDamageMeterAvailable")
    if not ok then
        out[#out + 1] = "IsDamageMeterAvailable: " .. available
        return
    end
    out[#out + 1] = ("IsDamageMeterAvailable: ok, available %s, reason %s"):format(show(available), show(reason))
end

local function enumLines(out)
    for _, name in ipairs({ "DamageMeterType", "DamageMeterSessionType" }) do
        local e = Enum and Enum[name]
        if Secrets.CanAccessTable(e) then
            local parts = {}
            for k, v in pairs(e) do parts[#parts + 1] = show(k) .. "=" .. show(v) end
            table.sort(parts)
            out[#out + 1] = ("Enum.%s: %s"):format(name, table.concat(parts, ", "))
        else
            out[#out + 1] = ("Enum.%s: missing"):format(name)
        end
    end
end

local function sessionsLine(out)
    local ok, list = call("GetAvailableCombatSessions")
    if not ok then
        out[#out + 1] = "sessions: " .. list
        return
    end
    out[#out + 1] = ("sessions: %d"):format(Secrets.SafeIterate(list, function() end))
end

-- The top spells of one source, one indented line each; answers the spell count.
local function spellLines(out, spells)
    return Secrets.SafeIterate(spells, function(i, e)
        if i > TOP then return end
        out[#out + 1] = ("   spell %s total %s"):format(show(field(e, "spellID")), show(field(e, "totalAmount")))
    end)
end

local function sourceLines(out, who, guid)
    local ok, src, err = sourceOf(guid)
    if not ok then
        out[#out + 1] = ("%s source: %s"):format(who, err)
        return
    end
    if not Secrets.CanAccessTable(src) then
        out[#out + 1] = ("%s source: %s"):format(who, show(src))
        return
    end
    local spells = {}
    local n = spellLines(spells, src.combatSpells)
    out[#out + 1] = ("%s source: total %s, dps %s, spells %d"):format(who, show(src.totalAmount),
        show(src.amountPerSecond), n)
    for _, line in ipairs(spells) do out[#out + 1] = line end
end

local function unitSourceLines(out)
    sourceLines(out, "player", UnitGUID("player"))
    if not UnitExists("pet") then
        out[#out + 1] = "pet source: none (no pet)"
        return
    end
    sourceLines(out, "pet", UnitGUID("pet"))
end

local function sessionLines(out)
    local ok, sess = call("GetCombatSessionFromType", sessionCurrent(), damageDone())
    if not ok then
        out[#out + 1] = "current session: " .. sess
    elseif not Secrets.CanAccessTable(sess) then
        out[#out + 1] = "current session: " .. show(sess)
    else
        local rows = {}
        local n = Secrets.SafeIterate(sess.combatSources, function(i, s)
            if i > TOP then return end
            rows[#rows + 1] = ("   source %s class %s total %s local %s"):format(show(field(s, "name")),
                show(field(s, "classFilename")), show(field(s, "totalAmount")), show(field(s, "isLocalPlayer")))
        end)
        out[#out + 1] = ("current session: sources %d, duration %s"):format(n, show(sess.durationSeconds))
        for _, line in ipairs(rows) do out[#out + 1] = line end
    end
    local okD, dur = call("GetSessionDurationSeconds", sessionCurrent())
    out[#out + 1] = "GetSessionDurationSeconds(current): " .. (okD and show(dur) or dur)
end

-- ── the pet split ──────────────────────────────────────────────────────────────────────────────

-- The plain spell IDs of one source as a set, its plain total, and whether anything was secret.
local function plainSpells(src)
    local ids, sealed = {}, false
    if not Secrets.CanAccessTable(src) then return ids, 0, Secrets.IsSealed(src) end
    if Secrets.IsSealed(src.totalAmount) or Secrets.IsSealed(src.combatSpells) then return ids, 0, true end
    Secrets.SafeIterate(src.combatSpells, function(_, e)
        local id = Secrets.PlainNumber(field(e, "spellID"))
        if id then ids[id] = true elseif field(e, "spellID") ~= nil then sealed = true end
    end)
    return ids, Secrets.PlainNumber(src.totalAmount) or 0, sealed
end

local function anyShared(a, b)
    for id in pairs(a) do
        if b[id] then return true end
    end
    return false
end

--- The "pet is separate source" verdict, with its reason.
local function petSplit()
    if not UnitExists("pet") then return "unknown (no pet: summon it, fight, then run it again)" end
    local petGUID = Secrets.PlainString(UnitGUID("pet"))
    if not petGUID then return "unknown (the pet's GUID cannot be read now)" end
    local okP, petSrc = sourceOf(petGUID)
    local okM, playerSrc = sourceOf(UnitGUID("player"))
    if not (okP and okM) then return "unknown (the meter raised)" end
    local petIDs, petTotal, petSealed = plainSpells(petSrc)
    local playerIDs, _, playerSealed = plainSpells(playerSrc)
    if petSealed or playerSealed then return "unknown (the meter's values are secret: run it out of combat)" end
    if next(petIDs) == nil and petTotal == 0 then
        return "no (the pet's own source is empty: its damage may be folded into yours)"
    end
    if anyShared(petIDs, playerIDs) then return "no (your source also holds the pet's spells)" end
    return "yes (it cannot tell whether your own total also counts the pet's damage)"
end

-- ── the pace bar's pet fill ────────────────────────────────────────────────────────────────────

local function statusbarTexture()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return nil end
    local key = LSM.GetDefault and LSM:GetDefault("statusbar")
    return key and LSM:Fetch("statusbar", key, true) or nil
end

local function newBar(texture)
    local bar = CreateFrame("StatusBar", nil, UIParent)
    bar:Hide()
    bar:SetSize(100, 4)
    if texture then bar:SetStatusBarTexture(texture) end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.5)
    return bar
end

local function buildAnchor()
    local texture = statusbarTexture()
    local okA, a = pcall(newBar, texture)
    local okB, b = pcall(newBar, texture)
    if not (okA and okB) then return "could not build the bars: " .. show(okA and b or a) end
    local fill = a:GetStatusBarTexture()
    if not fill then return "unknown (the bar has no fill texture)" end
    local ok, err = pcall(b.SetPoint, b, "LEFT", fill, "RIGHT", 0, 0)
    if not ok then return "SetPoint raised: " .. show(err) end
    return "ok"
end

--- Whether a bar anchors to another bar's fill texture. Built once (a frame cannot be destroyed).
local function anchorCheck()
    if not anchorLine then anchorLine = buildAnchor() end
    return anchorLine
end

-- ── the casts and the samples ──────────────────────────────────────────────────────────────────

local function castLine(label, b)
    return ("casts %s: %d, secret spell IDs %d, secret castGUIDs %d, pet %d"):format(label, b.n, b.secretID,
        b.secretGUID, b.pet)
end

local function sampleLines(out)
    out[#out + 1] = "sampling: " .. (armed and "watching your next fight" or "off")
    out[#out + 1] = castLine("out of combat", counts.outCombat)
    out[#out + 1] = castLine("in combat", counts.inCombat)
    if #samples == 0 then
        out[#out + 1] = "meter samples: none yet"
        return
    end
    for _, line in ipairs(samples) do out[#out + 1] = line end
end

local function sourceSecrecy(who, guid)
    local ok, src, err = sourceOf(guid)
    if not ok then return ("%s %s"):format(who, err) end
    if not Secrets.CanAccessTable(src) then return ("%s source %s"):format(who, show(src)) end
    return ("%s total %s, dps %s, spells %s"):format(who, secrecy(src.totalAmount), secrecy(src.amountPerSecond),
        secrecy(src.combatSpells))
end

local function takeSample(tag)
    local line
    if not hasMeter() then
        line = "no C_DamageMeter"
    else
        line = sourceSecrecy("player", UnitGUID("player"))
        if UnitExists("pet") then line = line .. "; " .. sourceSecrecy("pet", UnitGUID("pet")) end
    end
    samples[#samples + 1] = ("meter sample %s: %s"):format(tag, line)
    debug("sample %s", tag)
end

-- ── the report ─────────────────────────────────────────────────────────────────────────────────

--- The report, as plain text lines. Reads the client now; writes nothing.
--- @return string[]
function Probe.Report()
    local out = {}
    clientLines(out)
    if not hasMeter() then
        out[#out + 1] = "C_DamageMeter: missing"
    else
        out[#out + 1] = "C_DamageMeter: present"
        functionLines(out)
        availabilityLine(out)
        enumLines(out)
        sessionsLine(out)
        unitSourceLines(out)
        sessionLines(out)
    end
    out[#out + 1] = "pet is separate source: " .. (hasMeter() and petSplit() or "unknown (no meter)")
    out[#out + 1] = "pace pet-fill anchor: " .. anchorCheck()
    sampleLines(out)
    return out
end

--- Write the report to the debug console and show it. Answers how many lines it wrote.
--- @return number
function Probe.Show()
    local lines = Probe.Report()
    local D = NS.DebugLog
    for _, line in ipairs(lines) do D:Add("Probe", line) end
    D:Show()
    return #lines
end

-- ── arming ─────────────────────────────────────────────────────────────────────────────────────

local function cancelTimers()
    local addon = NS.addon
    for _, handle in ipairs(timers) do
        if addon and addon.CancelTimer then addon:CancelTimer(handle) end
    end
    timers = {}
    combatSample = nil
end

local function schedule(fn, delay)
    local addon = NS.addon
    if not (addon and addon.ScheduleTimer) then return end
    timers[#timers + 1] = addon:ScheduleTimer(fn, delay)
end

local function unregister()
    if frame then frame:UnregisterAllEvents() end
end

local function sampleInCombat()
    if armed then takeSample("combat+" .. Probe.SAMPLE_IN_COMBAT .. "s") end
end

-- This combat's in-combat sample, once: a second edge or a second arm in the same combat adds none.
local function scheduleCombatSample()
    if combatSample then return end
    combatSample = true
    schedule(sampleInCombat, Probe.SAMPLE_IN_COMBAT)
end

local function sampleAfterCombat()
    if not armed then return end
    takeSample("afterCombat+" .. Probe.SAMPLE_AFTER_COMBAT .. "s")
    Probe.Disarm()
    NS.Print(L["The probe sampled your fight. Type %s to see the report."]:format(NS.SLASH_CMD .. " probe"))
end

local function onCast(unit, castGUID, spellID)
    local b = InCombatLockdown() and counts.inCombat or counts.outCombat
    b.n = b.n + 1
    if Secrets.IsSecret(spellID) then b.secretID = b.secretID + 1 end
    if Secrets.IsSecret(castGUID) then b.secretGUID = b.secretGUID + 1 end
    if unit == "pet" then b.pet = b.pet + 1 end
end

local function hear(event, ...)
    if not armed or NS.IsStoodDown() then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        onCast(...)
    elseif event == "PLAYER_REGEN_DISABLED" then
        scheduleCombatSample()
    elseif event == "PLAYER_REGEN_ENABLED" then
        combatSample = nil
        schedule(sampleAfterCombat, Probe.SAMPLE_AFTER_COMBAT)
    end
end

local function onEvent(_, event, ...)
    local t0 = Perf.on and debugprofilestop()
    hear(event, ...)
    if t0 then Perf.Note("probe", debugprofilestop() - t0) end
end

local function register()
    unregister()
    if not armed or NS.IsStoodDown() then return end
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
    end
    NS.SafeRegisterUnitEvent(frame, "UNIT_SPELLCAST_SUCCEEDED", NS.rejectedEvents, "player", "pet")
    NS.SafeRegisterEvent(frame, "PLAYER_REGEN_DISABLED", nil, NS.rejectedEvents)
    NS.SafeRegisterEvent(frame, "PLAYER_REGEN_ENABLED", nil, NS.rejectedEvents)
end

--- Arm the probe: watch casts and the next combat. `fresh` starts the counts and samples again.
--- Already in combat, this combat's in-combat sample is taken on its usual delay from now.
--- @param fresh boolean|nil
function Probe.Arm(fresh)
    if fresh then
        resetCounts()
        samples = {}
        cancelTimers()
    end
    armed = true
    register()
    if InCombatLockdown() then scheduleCombatSample() end
    debug("armed%s", fresh and " (fresh)" or "")
end

--- Stop watching. The counts and samples stay for the report.
function Probe.Disarm()
    armed = false
    unregister()
    cancelTimers()
    debug("disarmed")
end

--- Whether the probe watches casts and the next combat now.
--- @return boolean
function Probe.IsArmed() return armed end

--- The cast counts { inCombat = {n, secretID, secretGUID, pet}, outCombat = {...} }, for the suites.
function Probe.Counts() return counts end

--- The event frame (nil until the probe first armed), for the suites.
function Probe.Frame() return frame end

--- The lifecycle's stand-down: no registration and no timer. The armed flag stays, so stand-up
--- comes back watching if the probe was.
function Probe.Suspend()
    unregister()
    cancelTimers()
end

--- The lifecycle's stand-up: registered again from the CURRENT armed flag.
function Probe.Resume()
    register()
end

-- ── the verb ───────────────────────────────────────────────────────────────────────────────────

local function reportVerb()
    if not armed and #samples == 0 then Probe.Arm(false) end
    local n = Probe.Show()
    if armed then
        NS.Print(L["The probe report is in the debug console (%d lines). It also watches your next fight: fight for 20 seconds or more, then type %s again."]
            :format(n, NS.SLASH_CMD .. " probe"))
    else
        NS.Print(L["The probe report is in the debug console (%d lines)."]:format(n))
    end
end

local VERBS = {
    [""] = reportVerb,
    start = function()
        Probe.Arm(true)
        NS.Print(L["The probe watches your next fight. Fight for 20 seconds or more, then type %s."]
            :format(NS.SLASH_CMD .. " probe"))
    end,
    stop = function()
        Probe.Disarm()
        NS.Print(L["The probe stopped watching."])
    end,
}

--- `/kct probe [start|stop]`.
--- @param rest string|nil
function Probe.OnVerb(rest)
    local word = (type(rest) == "string" and rest or ""):match("^%s*(%S*)"):lower()
    local fn = VERBS[word]
    if fn then return fn() end
    NS.Print(L["Usage: /kct probe, /kct probe start or /kct probe stop"])
end
