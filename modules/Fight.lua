local _, NS = ...
-- modules/Fight.lua — the fight state machine (spec §5, plan Task 2.2): IDLE -> COMBAT -> SETTLING ->
-- IDLE, one fight per meter session. Adapted from DPS Race @045f479 (modules/Race.lua) without its
-- race: no arming, no buzzer, no countdown, no late casts, no race length. A fight starts at combat
-- entry and ends after combat, when the meter has gone quiet.
--
-- THE RULES (spec §5):
--   * A fight binds to the first meter session that appeared at or after its combat entry
--     (Meter.SessionsAfter over the IDs Meter stamps on first sight). The list is read at combat entry,
--     on every meter event in combat, and on the tick while nothing is bound yet.
--   * Feign Death, Vanish: a re-entry within Constants.FIGHT.GRACE seconds of the combat end carries
--     the same fight on. A re-entry later than that closes the fight (it is PARKED: read out of combat
--     at the next settle, because a read in combat is sealed) and starts a new one.
--   * A new session while a fight is bound is a new fight (the meter split it), except when the
--     fight's encounter is still the active one: then it is merged, and the sessions are summed after
--     combat. An encounter that started after the fight's session was bound (an encounter starting
--     mid-combat) does not merge a session that appears within GRACE seconds of its start: that is
--     the meter splitting at the pull, so the boss part is its own fight and takes the encounter; if
--     the meter does not split, the whole fight carries the encounter.
--   * A meter reset (DAMAGE_METER_RESET, or a successful list read without a session of the fight)
--     makes the fight and every parked one "lost" at once. A list read that FAILED is no evidence.
--   * The settle: SETTLING ends at the later of GRACE after the combat end and SETTLE seconds without a
--     damage update for the fight's sessions; then every parked fight and the current one are read
--     with Meter.ReadFinal (merged across their sessions) and end in the order they started. A read
--     still sealed is retried every RETRY seconds, SEALED_RETRIES times, then the fight is lost.
--
-- SECRETS. Event arguments (the meter type, a session ID, an encounter's fields) may be secret: each
-- passes through NS.Secrets before anything compares or keys it. A secret session ID cannot say which
-- session updated, so it counts as the fight's own (the quiet waits longer, never shorter) and the
-- list, whose IDs are plain in combat, is read instead (at most once per TICK).
--
-- INPUTS come only from modules/Watchers.lua, with `t` from GetTime(). OUTPUTS are FIGHT_STARTED,
-- FIGHT_FIRST_HIT, FIGHT_TICK and FIGHT_ENDED (core/Bus.lua), each sent after the state has moved. Timers are the
-- addon object's AceTimers, so the stand-down's CancelAllTimers takes them too; Suspend drops the fight
-- in memory without a message (no record was opened), and the stand-up starts IDLE.
--
-- THE RACE'S THREE SEAMS (Race mode, modules/Race.lua). Fight.ShareSessions(set): while a race is armed,
-- an in-combat update naming a session of `set` (the ones the client held at the arm) binds an unbound
-- fight to it, marked `sharedSession` (ruling X3: a pull that carried on a session alive at the arm;
-- plain fights never bind one). Fight.Hurry(id): *Stop Now* reads the race's fight without the settle's
-- wait (ruling X5), at once while settling, at the combat end while in combat. Fight.Adopt(spec): a race
-- resumed after a /reload gets back the fight its meter session belongs to (Task B2).

local Fight = {}
NS.Fight = Fight

local Secrets = NS.Secrets
local C = NS.Constants.FIGHT

local STATE = { IDLE = "idle", COMBAT = "combat", SETTLING = "settling" }
Fight.STATE = STATE

--- A sealed after-combat read is retried this often, this many times, before the fight is lost.
Fight.RETRY = 0.5
Fight.SEALED_RETRIES = 10

local state = STATE.IDLE
local cur              -- the fight in progress (COMBAT or SETTLING), or nil
local parked = {}      -- fights closed in combat, waiting for the next settle's read, oldest first
local encounter        -- the active encounter (ENCOUNTER_START to ENCOUNTER_END), or nil
local seq = 0          -- fight IDs this session
local tickTimer, settleTimer
local sealedTries = 0
local lastScan = -math.huge
local shareable        -- the session IDs an unbound fight may bind as shared (Fight.ShareSessions), or nil

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Fight", fmt, ...) end
end

local function isDown()
    return NS.IsStoodDown ~= nil and NS.IsStoodDown()
end

local function setState(to)
    state = to
    if NS.Watchers and NS.Watchers.Sync then NS.Watchers.Sync() end
end

-- ── timers ──────────────────────────────────────────────────────────────────────────────────────

local function cancel(handle)
    local addon = NS.addon
    if handle and addon and addon.CancelTimer then addon:CancelTimer(handle) end
end

local function stopTick()
    cancel(tickTimer)
    tickTimer = nil
end

local function stopSettle()
    cancel(settleTimer)
    settleTimer = nil
end

local onSettle, onTick     -- the timer callbacks, defined below

local function scheduleSettle(delay)
    stopSettle()
    local addon = NS.addon
    if addon and addon.ScheduleTimer then settleTimer = addon:ScheduleTimer(onSettle, math.max(0, delay)) end
end

local function startTick()
    if tickTimer then return end
    local addon = NS.addon
    if addon and addon.ScheduleRepeatingTimer then tickTimer = addon:ScheduleRepeatingTimer(onTick, C.TICK) end
end

-- ── the fight table ─────────────────────────────────────────────────────────────────────────────

local function snapshot()
    local Identity = NS.Identity
    if Identity and Identity.Snapshot then return Identity.Snapshot() end
    return nil
end

-- A new fight from `t`. `scanFrom` is the time its sessions are looked for from (its combat entry, or
-- the chain's, for a fight split off in combat).
local function newFight(t, scanFrom)
    seq = seq + 1
    return { id = ("%d-%d"):format(time(), seq), startT = t, scanFrom = scanFrom or t, sessions = {},
             sessionSet = {}, encounter = encounter, snapshot = snapshot() }
end

local function addSession(f, id)
    if f.sessionID == nil then f.sessionID = id end
    f.sessions[#f.sessions + 1] = id
    f.sessionSet[id] = true
end

-- Whether session `id` belongs to the current fight or a parked one.
local function owned(id)
    if cur and cur.sessionSet[id] then return true end
    for _, f in ipairs(parked) do
        if f.sessionSet[id] then return true end
    end
    return false
end

-- Whether any of the fight's sessions is missing from a successful read.
local function goneFrom(f, all)
    for _, id in ipairs(f.sessions) do
        if not all[id] then return true end
    end
    return false
end

-- ── ending ──────────────────────────────────────────────────────────────────────────────────────

local function toIdle()
    stopTick()
    stopSettle()
    cur, parked, sealedTries = nil, {}, 0
    setState(STATE.IDLE)
end

-- Every fight in progress (parked first, then the current one) ends lost, now.
local function loseAll(why)
    local fights = parked
    if cur then fights[#fights + 1] = cur end
    debug("%d fight(s) lost: %s", #fights, why)
    toIdle()
    for _, f in ipairs(fights) do NS.SendBus(NS.MSG.FIGHT_ENDED, f, nil, "lost") end
end

-- ── the after-combat read, merged across a fight's sessions ─────────────────────────────────────

local function rate(total, duration)
    if duration > 0 then return total / duration end
    return 0
end

local function byTotal(a, b)
    if a.total ~= b.total then return a.total > b.total end
    if a.spellID ~= b.spellID then return a.spellID < b.spellID end
    return (b.isPet and not a.isPet) and true or false
end

-- Sum `spells` into `into` by spell ID (and pet flag), through the `index` of rows already there.
local function addSpells(into, index, spells)
    for _, sp in ipairs(spells) do
        local key = sp.isPet and ("p" .. sp.spellID) or sp.spellID
        local row = index[key]
        if row then
            row.total = row.total + sp.total
        else
            row = { spellID = sp.spellID, total = sp.total, isPet = sp.isPet }
            index[key] = row
            into[#into + 1] = row
        end
    end
end

-- One part (`player` or `pet`) summed over the reads; nil when no read has it.
local function sumPart(reads, key, duration)
    local total, spells, index, any = 0, {}, {}, false
    for _, r in ipairs(reads) do
        local part = r[key]
        if part then
            any = true
            total = total + part.total
            addSpells(spells, index, part.spells)
        end
    end
    if not any then return nil end
    for _, sp in ipairs(spells) do sp.dps, sp.isPet = rate(sp.total, duration), nil end
    table.sort(spells, byTotal)
    return { total = total, dps = rate(total, duration), spells = spells }
end

local function mergeReads(reads)
    if #reads == 1 then return reads[1] end
    local duration, spells, index = 0, {}, {}
    for _, r in ipairs(reads) do
        duration = duration + r.duration
        addSpells(spells, index, r.merged.spells)
    end
    table.sort(spells, byTotal)
    local player, pet = sumPart(reads, "player", duration), sumPart(reads, "pet", duration)
    local total = player.total + (pet and pet.total or 0)
    return { duration = duration, player = player, pet = pet,
             merged = { total = total, dps = rate(total, duration), spells = spells } }
end

-- A fight's read: the merged final, or nil plus Meter.ReadFinal's reason ("unbound" with no session).
local function readFight(f)
    if #f.sessions == 0 then return nil, "unbound" end
    local reads = {}
    for i, id in ipairs(f.sessions) do
        local final, err = NS.Meter.ReadFinal(id)
        if not final then return nil, err end
        reads[i] = final
    end
    return mergeReads(reads)
end

-- Read every fight waiting; a sealed one asks for a retry (true) while tries remain.
local function readAll(fights)
    local out = {}
    for i, f in ipairs(fights) do
        local final, err = readFight(f)
        if err == "sealed" and sealedTries < Fight.SEALED_RETRIES then
            sealedTries = sealedTries + 1
            debug("fight %s still sealed (try %d)", f.id, sealedTries)
            return nil, true
        end
        if not final then debug("fight %s lost: %s", f.id, tostring(err)) end
        out[i] = final or false
    end
    return out, false
end

local function finishAll()
    local fights = parked
    fights[#fights + 1] = cur
    local finals, retry = readAll(fights)
    if retry then
        parked[#parked] = nil          -- the current fight goes back where it was
        return scheduleSettle(Fight.RETRY)
    end
    toIdle()
    for i, f in ipairs(fights) do
        local final = finals[i] or nil
        NS.SendBus(NS.MSG.FIGHT_ENDED, f, final, final and "final" or "lost")
    end
end

-- When the settle may read: GRACE after the combat end, and SETTLE after the last damage update.
local function settleDue()
    local from = cur.combatEndT
    local last = cur.lastUpdateT
    if last == nil or last < from then last = from end
    return math.max(from + C.GRACE, last + C.SETTLE)
end

onSettle = function()
    settleTimer = nil
    if isDown() or state ~= STATE.SETTLING or not cur then return end
    local now, due = GetTime(), settleDue()
    if now < due and not cur.hurry then return scheduleSettle(due - now) end
    finishAll()
end

-- ── binding sessions ────────────────────────────────────────────────────────────────────────────

-- Whether a new session merges into fight `f`: its encounter is the active one, and the session is
-- not the meter's split at an encounter that started mid-fight.
local function mergesInto(f, t)
    if encounter == nil or f.encounter ~= encounter then return false end
    if f.encounterMid and t - encounter.startT <= C.GRACE then return false end
    return true
end

-- The meter split: the current fight is parked, a new one takes session `id` (and the encounter that
-- started mid-fight, if that is what split it).
local function split(id, t)
    local old = cur
    if old.encounterMid and old.encounter == encounter then old.encounter, old.encounterMid = nil, nil end
    old.closedT = t
    parked[#parked + 1] = old
    cur = newFight(t, old.scanFrom)
    addSession(cur, id)
    debug("session %d split off: fight %s parked, fight %s started", id, old.id, cur.id)
    if NS.Meter.NewLiveFight then NS.Meter.NewLiveFight() end
    NS.SendBus(NS.MSG.FIGHT_STARTED, cur)
end

local function adopt(id, t, via)
    if cur.sessionID == nil then
        addSession(cur, id)
        cur.boundBy = via or "event"
        debug("fight %s bound to session %d", cur.id, id)
    elseif mergesInto(cur, t) then
        addSession(cur, id)
        debug("session %d merged into fight %s (same encounter)", id, cur.id)
    else
        split(id, t)
    end
end

-- Read the list: lose the fight if a session of its is gone, else adopt every new session. `via` says
-- what asked ("tick" from the tick while unbound), kept on the fight as `boundBy` when it binds.
local function scan(t, via)
    if not cur then return end
    lastScan = t
    local all, ok = NS.Meter.SessionIDs()
    if not ok then return end
    if goneFrom(cur, all) then return loseAll("session gone") end
    for _, id in ipairs(NS.Meter.SessionsAfter(cur.scanFrom, all)) do
        if not owned(id) then adopt(id, t, via) end
    end
end

-- ── starting ────────────────────────────────────────────────────────────────────────────────────

local function begin(t)
    cur = newFight(t)
    sealedTries = 0
    local first = NS.Meter.SessionAfter(t)
    if first ~= nil and not owned(first) then
        addSession(cur, first)
        cur.boundBy = "entry"
    end
    if NS.Meter.NewLiveFight then NS.Meter.NewLiveFight() end
    debug("fight %s started at %.2f (session %s)", cur.id, t, tostring(cur.sessionID))
    setState(STATE.COMBAT)
    startTick()
    NS.SendBus(NS.MSG.FIGHT_STARTED, cur)
    scan(t)
end

onTick = function()
    if isDown() or state ~= STATE.COMBAT or not cur then return end
    if cur.sessionID == nil then scan(GetTime(), "tick") end
    if not cur then return end
    NS.Meter.ShareLive(true)
    NS.SendBus(NS.MSG.FIGHT_TICK, cur)
    NS.Meter.ShareLive(false)
end

-- ── queries ─────────────────────────────────────────────────────────────────────────────────────

--- The current state (one of Fight.STATE).
function Fight.State()
    return state
end

--- The fight's live AceTimer handles { tick, settle } (either nil when not running), for the suites.
function Fight.Timers()
    return { tick = tickTimer, settle = settleTimer }
end

--- The fight in progress, or nil while idle. Fields: id, sessionID (nil until bound), sessions,
--- startT (the combat entry), firstHitT (the first damage update), encounter, snapshot.
function Fight.Current()
    if state == STATE.IDLE then return nil end
    return cur
end

--- Whether an encounter is active (ENCOUNTER_START heard, its ENCOUNTER_END not yet). Watchers holds
--- ENCOUNTER_END in idle while it is, so an encounter that ends with the player out of combat (dead,
--- the raid fighting on) does not name the next fight.
function Fight.EncounterActive()
    return encounter ~= nil
end

-- ── inputs (modules/Watchers.lua) ───────────────────────────────────────────────────────────────

--- PLAYER_REGEN_DISABLED: a new fight from IDLE; from SETTLING, the same fight within the grace,
--- else the settling one is parked and a new one starts.
function Fight.OnCombatStart(t)
    if isDown() or state == STATE.COMBAT then return end
    NS.SendBus(NS.MSG.COMBAT_ENTERED, t)
    if state == STATE.IDLE then return begin(t) end
    stopSettle()
    if t - cur.combatEndT <= C.GRACE then
        debug("combat again %.2fs after it ended: fight %s carries on", t - cur.combatEndT, cur.id)
        cur.combatEndT = nil
        setState(STATE.COMBAT)
        startTick()
        return scan(t)
    end
    cur.closedT = cur.combatEndT
    parked[#parked + 1] = cur
    begin(t)
end

--- PLAYER_REGEN_ENABLED: the fight settles (at once, for a fight *Stop Now* hurried).
function Fight.OnCombatEnd(t)
    if isDown() or state ~= STATE.COMBAT then return end
    cur.combatEndT = t
    stopTick()
    setState(STATE.SETTLING)
    scheduleSettle(cur.hurry and 0 or C.GRACE)
end

-- A damage update was heard for the current fight at `t`; the first one for a bound session is the
-- fight's first hit, said once on the bus.
local function heard(t)
    cur.lastUpdateT = t
    if cur.firstHitT == nil and cur.sessionID ~= nil then
        cur.firstHitT = t
        NS.SendBus(NS.MSG.FIGHT_FIRST_HIT, cur)
    end
end

-- An unbound fight takes a session the race allowed (Fight.ShareSessions) when an update in combat
-- names it: the pull carried on a session alive at the arm.
local function bindShared(id)
    if id == nil or cur.sessionID ~= nil or not shareable or not shareable[id] or owned(id) then return end
    addSession(cur, id)
    cur.sharedSession, cur.boundBy = true, "shared"
    debug("fight %s bound to session %d, alive at the race's arm (shared)", cur.id, id)
end

--- DAMAGE_METER_COMBAT_SESSION_UPDATED(statType, sessionID). Only damage counts: a plain other type
--- is ignored; a secret one is taken as damage.
function Fight.OnMeterUpdate(t, statType, sessionID)
    if isDown() or not cur then return end
    local stat, id = Secrets.PlainNumber(statType), Secrets.PlainNumber(sessionID)
    if stat ~= nil and stat ~= NS.Meter.STAT_DAMAGE_DONE then return end
    if state == STATE.COMBAT then
        local unknown = id == nil or not owned(id)
        if (id ~= nil and unknown) or (id == nil and t - lastScan >= C.TICK) then scan(t) end
        if cur then bindShared(id) end
    end
    if cur and (id == nil or cur.sessionSet[id]) then heard(t) end
end

--- DAMAGE_METER_CURRENT_SESSION_UPDATED: the meter made a session; in combat, look for it.
function Fight.OnSessionCreated(t)
    if isDown() or state ~= STATE.COMBAT then return end
    scan(t)
end

--- DAMAGE_METER_RESET: every fight in progress is lost.
function Fight.OnMeterReset()
    if isDown() or (cur == nil and #parked == 0) then return end
    loseAll("meter reset")
end

--- ENCOUNTER_START(encounterID, name, difficultyID, groupSize). In combat while IDLE it starts a fight;
--- a fight without an encounter takes it (mid-fight, if its session is already bound).
function Fight.OnEncounterStart(t, encounterID, name, difficultyID, groupSize)
    if isDown() then return end
    encounter = { id = Secrets.PlainNumber(encounterID), name = Secrets.PlainString(name),
                  difficultyID = Secrets.PlainNumber(difficultyID), groupSize = Secrets.PlainNumber(groupSize),
                  startT = t }
    debug("encounter %s started", tostring(encounter.id))
    if state == STATE.IDLE then
        if UnitAffectingCombat("player") then return begin(t) end
        return setState(STATE.IDLE)    -- the idle set now hears this encounter's end
    end
    if cur.encounter == nil then
        cur.encounter = encounter
        cur.encounterMid = cur.sessionID ~= nil
    end
end

--- ENCOUNTER_END(encounterID, name, difficultyID, groupSize, success): the encounter is over.
function Fight.OnEncounterEnd(t, _, _, _, _, success)
    if isDown() or encounter == nil then return end
    encounter.endT = t
    encounter.success = Secrets.PlainNumber(success) == 1
    encounter = nil
    if state == STATE.IDLE then setState(STATE.IDLE) end
end

-- ── the race's seams (modules/Race.lua) ─────────────────────────────────────────────────────────

--- The sessions an unbound fight may bind as shared, `{ [id] = true }`, or nil for none (the rule for
--- every plain fight). Set by an armed race, cleared when it starts, ends or is canceled.
--- @param set table|nil
function Fight.ShareSessions(set)
    shareable = type(set) == "table" and set or nil
end

-- Whether fight `id` is the current one or a parked one.
local function holds(id)
    if cur and cur.id == id then return true end
    for _, f in ipairs(parked) do
        if f.id == id then return true end
    end
    return false
end

--- *Stop Now* for the race's fight `id`: settling, every waiting fight is read now (a sealed read
--- still retries); in combat, the settle runs at the combat end with no wait. Nothing else moves.
--- @param id string  the fight's id
--- @return boolean acted
function Fight.Hurry(id)
    if isDown() or state == STATE.IDLE or not holds(id) then return false end
    cur.hurry = true
    if state == STATE.SETTLING then
        stopSettle()
        finishAll()
    end
    return true
end

-- The resumed fight's table: the race's kept fields, on a fresh id. New sessions are looked for from
-- the resume (the sessions the stand-up primed are older than any).
local function adoptedFight(spec, now)
    seq = seq + 1
    local f = { id = ("%d-%d"):format(time(), seq), startT = spec.startT or now, scanFrom = now, sessions = {},
                sessionSet = {}, snapshot = spec.snapshot, stats = spec.stats, gearSet = spec.gearSet,
                firstHitT = spec.firstHitT, lastUpdateT = spec.lastUpdateT, sharedSession = spec.sharedSession,
                raceBaseline = spec.raceBaseline, boundBy = spec.boundBy or "resume", resumed = true }
    if spec.talents ~= nil then f.loadout = { talents = spec.talents } end
    for _, id in ipairs(spec.sessions) do addSession(f, id) end
    return f
end

--- A race resumed after a /reload or a stand-up (Race.Resume, race plan Task B2): the fight it rode,
--- rebuilt from what the race kept and bound to its sessions. In combat it is the current fight
--- (COMBAT, the tick on, the combat end settling it as ever); out of combat the combat ended unheard,
--- so it is read now, without the settle's wait (as Hurry reads), on the next timer. No FIGHT_STARTED
--- or FIGHT_FIRST_HIT: the fight began before the reload, and its casts, usage and chart went with it.
--- @param spec table  { sessions (plain IDs, at least one), startT, firstHitT, lastUpdateT?, snapshot,
---                    stats?, talents?, gearSet?, sharedSession?, raceBaseline?, boundBy?, inCombat }
--- @return table|nil fight  nil while stood down, while a fight is in progress, or with no session
function Fight.Adopt(spec)
    if isDown() or state ~= STATE.IDLE or type(spec) ~= "table" or type(spec.sessions) ~= "table"
        or spec.sessions[1] == nil then
        return nil
    end
    local now = GetTime()
    cur, parked, sealedTries = adoptedFight(spec, now), {}, 0
    debug("fight %s resumed on session %s (%s)", cur.id, tostring(cur.sessionID),
        spec.inCombat and "in combat" or "read now")
    if spec.inCombat then
        setState(STATE.COMBAT)
        startTick()
    else
        cur.combatEndT, cur.hurry = now, true
        setState(STATE.SETTLING)
        scheduleSettle(0)
    end
    return cur
end

-- ── the lifecycle (core/LifecycleSetup.lua) ─────────────────────────────────────────────────────

--- The stand-down: the fight in memory goes, silently, with its timers; the state is IDLE.
function Fight.Suspend()
    stopTick()
    stopSettle()
    cur, parked, encounter, sealedTries, shareable = nil, {}, nil, 0, nil
    state = STATE.IDLE
end

--- The stand-up: nothing to rebuild; a combat already under way is not picked up (Review Focus 4),
--- unless a race was under way: Race.Resume adopts its fight (Fight.Adopt).
function Fight.Resume()
    state = STATE.IDLE
end
