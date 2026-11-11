local _, NS = ...
-- modules/Race.lua — the race engine on the fight pipeline (Race mode, plan Task B1): IDLE -> ARMED ->
-- RUNNING -> STOPPING -> RESULT. Ported from DPS Race @f8078c7 (modules/Race.lua) onto Combat Trail's
-- fight: modules/Fight.lua owns the meter session, the settle and the read, so a race is a layer that
-- only annotates the fight it rides. It arms, starts its clock on the fight's first hit, runs the
-- buzzer, judges the casts after it, stamps a timeline, and leaves the fight its `race` part
-- (modules/RaceRecord.lua's shape), which modules/Recorder.lua saves with the fight.
--
-- THE FLOW, ON THE BUS (core/Bus.lua):
--   Arm            RACE_ARMED. Refused stood down, on WoW Forever, with Race mode off (Task B3), while
--                  armed or racing, while a race
--                  waits for its read, for a length outside 10 s - 15:00, in combat, while a fight is
--                  still settling (a pull inside its grace would carry that fight on, ruling X5) and
--                  with the meter unavailable. The sessions the client holds now are the arm's set,
--                  and the newest one's read is the baseline a shared session is netted against.
--   FIGHT_STARTED  on a training dummy (the fight's combat-entry target, NS.Dummies), the fight takes
--                  the race part; anything else cancels the arm (RACE_CANCELED "not_dummy") and the
--                  pull is a normal fight (Review focus 1).
--   FIGHT_FIRST_HIT  the clock: the fight's firstHitT (ruling X2). RUNNING, RACE_STARTED, the buzzer
--                  due at firstHitT + length. The arm's snapshots (stats, talents, gear set, usage)
--                  replace the fight's combat-entry reads (ruling X6), after FIGHT_STARTED's receivers
--                  have all run, so the order between them never matters.
--   the buzzer     STOPPING, RACE_BUZZER. The fight stays in combat; Fight reads it after its settle
--                  (ruling X5), or at once through Fight.Hurry for *Stop Now*.
--   combat ends    before the buzzer (or the player dies): STOPPING, the race incomplete at `endedAt`
--                  (ruling X4), even when Combat Trail's grace carries the fight on (Feign Death).
--   FIGHT_ENDED    Recorder pulls Race.Finalize first (ruling X1): the score, the DPS, the timing, the
--                  status; a shared session's read is netted first (ruling X3). Then Recorder saves:
--                  FIGHT_SAVED for the race's fight, or FIGHT_SKIPPED, moves the race to RESULT and
--                  sends RACE_RESULT(record or nil, race).
--   Cancel         RACE_CANCELED "canceled": the part comes off the fight, which ends as a plain dummy
--                  fight under the normal rules (spec §4.1). On a result it only dismisses it.
--
-- SECRETS. Nothing here reads a meter number in combat: the clock is an event's GetTime(), the buzzer a
-- timer, the tail and the restart are update stamps, and the score is the fight's plain read after
-- combat. An event argument that may be secret (the meter type, a session ID, a spell ID, a castGUID)
-- passes through NS.Secrets before it is compared or kept; a sealed late cast keeps its offset only.
--
-- RETAIL ONLY (clients-§4). The bus receivers below register only on Retail, Arm refuses on WoW
-- Forever, and modules/RaceWatchers.lua registers no event there. Timers are the addon object's
-- AceTimers, so the stand-down's CancelAllTimers takes the buzzer; Suspend drops the race silently.
--
-- AFTER A /RELOAD (Task B2). Nothing reaches the fight store mid-race (modules/Recorder.lua), but at
-- its first hit the race is written to db.global.pendingRaces[charKey] (Bests.CharKey of the pull's
-- `who`), one slot per character: its part (the SAME table, so every status and flag set on it is in
-- SavedVariables at once, as DPS Race's run was) and the fight's plain fields a record needs (its
-- sessions, combat entry, snapshot, stats, talents, gear set, a shared session's baseline). Each damage
-- update moves the slot's `lastDamage`; the result and a cancel clear it; an arm (never written) is
-- dropped by a /reload. Race.Resume (OnEnable and the stand-up) carries this character's slot on:
-- a session gone is lost; still in combat with time left it runs on with the buzzer re-armed; else it
-- waits for its read, flagged `reloaded` past the buzzer, incomplete before it when combat is already
-- over. Fight.Adopt gives it back the fight its session belongs to, which ends on the normal path
-- (FIGHT_ENDED, Recorder, Finalize). The casts, the usage and the chart before the reload are gone.

local Race = {}
NS.Race = Race

-- ── Race mode (Task B3) ─────────────────────────────────────────────────────────────────────────
-- The ONE gate every race surface asks: Retail, and the Race mode page's switch on. Off stops NEW
-- races only (spec §8): Arm refuses, no auto-show or auto-arm, the Race window stays hidden; a race
-- under way runs to its result, and a saved race is a fight that never asks this.
NS.RaceMode = NS.RaceMode or {}

--- Whether Race mode is on: Retail, and `race.enabled` (WoW Forever has neither the switch nor the key).
function NS.RaceMode.On()
    if not NS.Compat.ForClient({ "retail" }) then return false end
    local db = NS.db
    local race = db and db.profile and db.profile.race
    local on
    if type(race) == "table" then on = race.enabled end
    if on == nil then on = NS.defaults.profile.race.enabled end
    return on ~= false
end

local Secrets = NS.Secrets

local STATE = { IDLE = "idle", ARMED = "armed", RUNNING = "running", STOPPING = "stopping", RESULT = "result" }
Race.STATE = STATE

--- The length presets (s) and the custom bounds (10 s - 15:00).
Race.LENGTHS = { 30, 60, 120, 180, 300 }
Race.MIN_LENGTH, Race.MAX_LENGTH = 10, 900

--- Spells whose success repeats on its own once started (Auto Shot, a wand's Shoot): never a press.
Race.AUTO_REPEAT = { [75] = true, [5019] = true }

local RETAIL = { "retail" }

local state = STATE.IDLE
-- The race in progress. Fields: race (the part), fight (the fight it rides, from FIGHT_STARTED),
-- armSet (session IDs held at the arm), baseline (the newest of them, read at the arm), snaps (the
-- arm's snapshots), startedAt (the fight's firstHitT), buzzerAt, combatEndedAt (the regen edge after
-- the buzzer), lastDamage (s from the start), timeline, inFlight (the cast begun and not yet finished:
-- its plain spell ID and castGUID, either nil when sealed), buzzer (the timer), stopNow, record,
-- date (time() at the first hit), slot and slotKey (the pending slot, Task B2), resumedAt (the resume's
-- GetTime(): a restart gap never spans it).
local cur = {}

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Race", fmt, ...) end
end

local function isDown()
    return NS.IsStoodDown ~= nil and NS.IsStoodDown()
end

local function round2(v)
    if type(v) ~= "number" then return nil end
    return math.floor(v * 100 + 0.5) / 100
end

local function setState(to)
    local from = state
    state = to
    if NS.RaceWatchers and NS.RaceWatchers.Sync then NS.RaceWatchers.Sync() end
    NS.SendBus(NS.MSG.RACE_STATE_CHANGED, cur.race, from, to)
end

-- A race setting: the profile's, else the shipped default.
local function setting(key)
    local db = NS.db
    local race = db and db.profile and db.profile.race
    local v = type(race) == "table" and race[key] or nil
    if v == nil then v = NS.defaults.profile.race[key] end
    return v
end

-- ── the buzzer's timer ──────────────────────────────────────────────────────────────────────────

local function stopBuzzer()
    local addon = NS.addon
    if cur.buzzer and addon and addon.CancelTimer then addon:CancelTimer(cur.buzzer) end
    cur.buzzer = nil
end

local buzz   -- the timer callback, below

local function scheduleBuzzer(delay)
    stopBuzzer()
    local addon = NS.addon
    if addon and addon.ScheduleTimer then cur.buzzer = addon:ScheduleTimer(buzz, math.max(0, delay)) end
end

-- ── queries ─────────────────────────────────────────────────────────────────────────────────────

--- The current state (one of Race.STATE).
function Race.State()
    return state
end

--- The race part armed, raced or showing its result; nil when idle.
function Race.Current()
    if state == STATE.IDLE then return nil end
    return cur.race
end

--- The fight the race rides (from its pull), or nil.
function Race.Fight()
    if state == STATE.IDLE then return nil end
    return cur.fight
end

--- The stored record of the race on show (RESULT), or nil (none yet, or nothing was stored).
function Race.Result()
    if state ~= STATE.RESULT then return nil end
    return cur.record
end

local function live()
    return (state == STATE.RUNNING or state == STATE.STOPPING) and cur.startedAt ~= nil
end

--- Seconds since the clock started, while running or stopping.
function Race.Elapsed()
    if not live() then return nil end
    return GetTime() - cur.startedAt
end

--- Seconds until the buzzer while running; 0 once stopping.
function Race.TimeLeft()
    if not live() then return nil end
    if state == STATE.STOPPING then return 0 end
    return math.max(0, cur.race.length - (GetTime() - cur.startedAt))
end

--- Seconds since the buzzer while stopping; nil for a race that ended before it.
function Race.SinceBuzzer()
    if state ~= STATE.STOPPING or not cur.buzzerAt then return nil end
    return GetTime() - cur.buzzerAt
end

--- Seconds from the start to the race's last damage update, while running or stopping.
function Race.LastDamage()
    if not live() then return nil end
    return cur.lastDamage
end

--- Whether *Stop Now* was pressed for the race waiting for its read.
function Race.StopRequested()
    return state == STATE.STOPPING and cur.stopNow == true
end

--- The Race mode page's new default length: the length last armed is forgotten, so the next race arms
--- at the new default (DPS Race's ForgetLength).
function Race.ForgetLength()
    local db = NS.db
    if db and type(db.profile) == "table" and type(db.profile.race) == "table" then
        db.profile.race.lastLength = nil
    end
end

--- The length the next race arms at: the last one armed, else the profile's default.
function Race.DefaultLength()
    local last = setting("lastLength")
    if type(last) == "number" and last >= Race.MIN_LENGTH and last <= Race.MAX_LENGTH then return last end
    return setting("defaultLength")
end

-- ── the pending slot (db.global.pendingRaces, Task B2) ──────────────────────────────────────────

local function slots()
    local db = NS.db
    local g = db and db.global
    if type(g) ~= "table" then return nil end
    if type(g.pendingRaces) ~= "table" then g.pendingRaces = {} end
    return g.pendingRaces
end

local function plain(v)
    local Recorder = NS.Recorder
    if v == nil or not (Recorder and Recorder.PlainCopy) then return nil end
    return Recorder.PlainCopy(v)
end

-- The logged-in character's slot key, or nil with no readable name.
local function myKey()
    local Identity = NS.Identity
    if not (Identity and Identity.Who) then return nil end
    return NS.Bests.CharKey(Identity.Who())
end

-- Whether this character's slot holds a race not yet resumed.
local function slotWaiting()
    local store = slots()
    if store == nil or next(store) == nil then return false end
    local key = myKey()
    return key ~= nil and store[key] ~= nil
end

-- The race at its first hit (and again when it follows a split): the slot, written whole. A pull whose
-- character cannot be read is never written (no key; it could not be a record either).
local function persist()
    local f, store = cur.fight, slots()
    local snap = plain(f.snapshot)
    local key = NS.Bests.CharKey(type(snap) == "table" and snap.who or nil)
    if not (store and key) then return end
    local lo = type(f.loadout) == "table" and f.loadout or {}
    cur.slotKey = key
    cur.slot = { race = cur.race, startedAt = cur.startedAt, date = cur.date, lastDamage = cur.lastDamage,
                 sessions = plain(f.sessions), boundBy = Secrets.PlainString(f.boundBy),
                 sharedSession = f.sharedSession and true or nil, startT = Secrets.PlainNumber(f.startT),
                 snapshot = snap, stats = plain(f.stats), talents = plain(lo.talents),
                 gearSet = Secrets.PlainString(f.gearSet), baseline = plain(f.raceBaseline) }
    store[key] = cur.slot
end

-- The race is over (its result) or canceled: its slot goes.
local function unpersist()
    local store, key = slots(), cur.slotKey
    if store and key and store[key] == cur.slot then store[key] = nil end
    cur.slot, cur.slotKey = nil, nil
end

-- A damage update: the slot's last offset, and its sessions when the fight merged one.
local function persistStamp()
    local slot, f = cur.slot, cur.fight
    if not slot then return end
    slot.lastDamage = cur.lastDamage
    if f and type(slot.sessions) == "table" and #f.sessions ~= #slot.sessions then slot.sessions = plain(f.sessions) end
end

-- ── arming ──────────────────────────────────────────────────────────────────────────────────────

local function validLength(length)
    return type(length) == "number" and length >= Race.MIN_LENGTH and length <= Race.MAX_LENGTH
end

-- Why the race's own state refuses a new arm, or nil.
local function stateRefusal()
    if state == STATE.ARMED or state == STATE.RUNNING then return "busy" end
    if state == STATE.STOPPING or slotWaiting() then return "pending" end
    return nil
end

local function armRefusal(length)
    if isDown() then return "disabled" end
    if not NS.Compat.ForClient(RETAIL) then return "client" end
    if not NS.RaceMode.On() then return "off" end
    local refusal = stateRefusal()
    if refusal then return refusal end
    if not validLength(length) then return "bad_length" end
    if UnitAffectingCombat("player") then return "in_combat" end
    if NS.Fight.State() ~= NS.Fight.STATE.IDLE then return "settling" end
    local ok, why = NS.Meter.IsAvailable()
    if not ok then return "meter_unavailable", why end
    return nil
end

local function newest(set)
    local mark
    for id in pairs(set) do
        if mark == nil or id > mark then mark = id end
    end
    return mark
end

-- What session `id` holds now (the arm is out of combat, so the read is plain): its totals and each
-- spell's, keyed as Fight merges them (spell ID, "p" .. ID for the pet's). nil when there is no such
-- session or the read fails; consulted only if the pull carries on that session.
local function baselineOf(id)
    if id == nil then return nil end
    local final = NS.Meter.ReadFinal(id)
    if type(final) ~= "table" or type(final.merged) ~= "table" then return nil end
    local spells = {}
    for _, sp in ipairs(final.merged.spells or {}) do
        local key = sp.isPet and ("p" .. sp.spellID) or sp.spellID
        spells[key] = (spells[key] or 0) + sp.total
    end
    return { session = id, total = final.merged.total, player = final.player and final.player.total,
             pet = final.pet and final.pet.total, spells = spells }
end

-- The arm's snapshots, read out of combat (ruling X6).
local function armSnapshots()
    local snaps = {}
    if NS.Stats and NS.Stats.Read then snaps.stats = NS.Stats.Read() end
    local lo = NS.Loadouts and NS.Loadouts.Snapshot and NS.Loadouts.Snapshot()
    snaps.talents = type(lo) == "table" and lo.talents or nil
    if NS.Loadouts and NS.Loadouts.CurrentGearSet then snaps.gearSet = NS.Loadouts.CurrentGearSet() end
    if NS.Usage and NS.Usage.Snapshot then snaps.usageSnap = NS.Usage.Snapshot() end
    return snaps
end

local function newPart(length)
    return { length = length, status = "armed", grace = setting("grace"), restartGap = setting("restartGap"),
             flags = { lateCasts = {}, reloaded = false, died = false } }
end

local function remember(length)
    local db = NS.db
    if db and type(db.profile) == "table" and type(db.profile.race) == "table" then
        db.profile.race.lastLength = length
    end
end

--- Arm a race of `length` seconds (Race.DefaultLength() when nil) for the next pull.
--- @param length number|nil  10-900
--- @return boolean ok
--- @return string|nil reason  "disabled" | "client" | "off" | "busy" | "pending" | "bad_length" | "in_combat" |
---                            "settling" | "meter_unavailable"
--- @return string|nil detail  for "meter_unavailable": the client's own reason, verbatim
function Race.Arm(length)
    if length == nil then length = Race.DefaultLength() end
    local refusal, detail = armRefusal(length)
    if refusal then
        debug("arm refused: %s", refusal)
        return false, refusal, detail
    end
    cur = { race = newPart(length), timeline = NS.RaceTimeline.New() }
    cur.armSet = NS.Meter.SessionIDs()
    local mark = newest(cur.armSet)
    cur.baseline = baselineOf(mark)
    cur.snaps = armSnapshots()
    NS.Fight.ShareSessions(cur.armSet)
    remember(length)
    debug("armed %ds; newest session before the arm: %s", length, tostring(mark))
    setState(STATE.ARMED)
    NS.SendBus(NS.MSG.RACE_ARMED, cur.race)
    return true
end

-- ── canceling ───────────────────────────────────────────────────────────────────────────────────

-- Back to IDLE; `why` is RACE_CANCELED's reason, nil for a dismissed result.
local function drop(why)
    stopBuzzer()
    unpersist()
    if cur.fight and state ~= STATE.RESULT then cur.fight.race = nil end
    NS.Fight.ShareSessions(nil)
    setState(STATE.IDLE)
    cur = {}
    if why then NS.SendBus(NS.MSG.RACE_CANCELED, why) end
end

--- Cancel the armed or running race: its part comes off the fight, which goes on as a plain dummy
--- fight (spec §4.1). On a result card it dismisses the card; the saved race stays.
--- @return boolean acted
function Race.Cancel()
    if isDown() or state == STATE.IDLE then return false end
    debug("canceled in %s", state)
    drop(state ~= STATE.RESULT and "canceled" or nil)
    return true
end

-- ── the pull and the clock ──────────────────────────────────────────────────────────────────────

local function targetOf(fight)
    local snap = fight.snapshot
    return type(snap) == "table" and type(snap.target) == "table" and snap.target or nil
end

-- FIGHT_STARTED while armed: a dummy's fight takes the race part, any other pull cancels the arm.
local function bindFight(fight)
    if cur.fight and cur.fight ~= fight then cur.fight.race = nil end
    cur.fight = nil
    local target = targetOf(fight)
    if not (target and target.isDummy) then
        debug("fight %s is not on a training dummy: the arm is canceled", tostring(fight.id))
        return drop("not_dummy")
    end
    cur.fight = fight
    cur.race.kind = NS.Dummies.CategoryOf(target.creatureID) or "single"
    fight.race = cur.race
    debug("fight %s on a %s dummy: waiting for the first hit", tostring(fight.id), cur.race.kind)
end

-- The meter split the shared session's fight (a fresh session after the arm): the race follows the
-- fresh one, as DPS Race's did, and is no longer shared. The shared fight keeps its baseline, so it
-- is netted at its own read and never saves the fight before the arm a second time.
local function unshare(fight)
    local old = cur.fight
    old.race = nil
    cur.fight = fight
    fight.race = cur.race
    cur.race.flags.sharedSession = nil
    persist()
    debug("fight %s split off the shared session: the race follows it", tostring(fight.id))
end

local function onFightStarted(fight)
    if isDown() or type(fight) ~= "table" then return end
    if state == STATE.ARMED then return bindFight(fight) end
    local old = cur.fight
    if (state == STATE.RUNNING or state == STATE.STOPPING) and old and old ~= fight and old.sharedSession
        and fight.scanFrom == old.scanFrom then
        return unshare(fight)
    end
end

-- The arm's snapshots replace the fight's combat-entry reads (ruling X6).
local function handOver(fight)
    local s = cur.snaps or {}
    if s.stats ~= nil then fight.stats = s.stats end
    if s.talents ~= nil then fight.loadout = { talents = s.talents } end
    if s.gearSet ~= nil then fight.gearSet = s.gearSet end
    if s.usageSnap ~= nil then fight.usageSnap = s.usageSnap end
end

-- A shared session (ruling X3): flagged, and its baseline kept on the fight when it is the one read at
-- the arm, so Finalize nets the read against it.
local function markShared(fight)
    if not fight.sharedSession then return end
    cur.race.flags.sharedSession = true
    local base = cur.baseline
    if base and base.session == fight.sessionID then fight.raceBaseline = base end
end

local function begin(fight)
    local t = fight.firstHitT
    cur.startedAt = t
    cur.race.status = "running"
    markShared(fight)
    NS.Fight.ShareSessions(nil)
    handOver(fight)
    cur.timeline:AddDamage(t)
    cur.lastDamage = 0
    cur.date = time()
    persist()
    scheduleBuzzer(cur.race.length - (GetTime() - t))
    debug("clock started at %.2f (fight %s)", t, tostring(fight.id))
    setState(STATE.RUNNING)
    NS.SendBus(NS.MSG.RACE_STARTED, cur.race, fight)
end

local function onFirstHit(fight)
    if isDown() or state ~= STATE.ARMED or fight ~= cur.fight or type(fight.firstHitT) ~= "number" then return end
    begin(fight)
end

buzz = function()
    cur.buzzer = nil
    if isDown() or state ~= STATE.RUNNING then return end
    -- The buzzer's own time, not the moment the timer was serviced; a timer serviced early waits.
    local due, now = cur.startedAt + cur.race.length, GetTime()
    if now < due then return scheduleBuzzer(due - now) end
    cur.buzzerAt = due
    cur.race.status = "stopping"
    debug("buzzer at %.2f", due)
    setState(STATE.STOPPING)
    NS.SendBus(NS.MSG.RACE_BUZZER, cur.race)
end

-- Combat dropped (or the player died) before the buzzer: the race will be read as incomplete.
local function endEarly(t)
    stopBuzzer()
    cur.race.endedAt = round2(t - cur.startedAt)
    cur.race.status = "stopping"
    debug("combat ended before the buzzer, at +%.2f: incomplete", cur.race.endedAt)
    setState(STATE.STOPPING)
end

-- ── inputs (modules/RaceWatchers.lua) ───────────────────────────────────────────────────────────

local function racing()
    return state == STATE.RUNNING or state == STATE.STOPPING
end

--- PLAYER_REGEN_DISABLED: back in combat after the buzzer, the combat end is not the one read; back
--- in combat after an early end (no buzzer yet), the fight carries on (ruling X16).
function Race.OnCombatStart()
    if isDown() or state ~= STATE.STOPPING then return end
    cur.combatEndedAt = nil
    if not cur.buzzerAt then cur.carriedOn = true end
end

--- PLAYER_REGEN_ENABLED: before the buzzer the race is incomplete; after it, the combat end is kept.
function Race.OnCombatEnd(t)
    if isDown() or not racing() then return end
    if state == STATE.RUNNING then return endEarly(t) end
    cur.combatEndedAt = t
end

--- PLAYER_DEAD: before the buzzer the race is incomplete and marked died; after it, marked only.
function Race.OnDeath(t)
    if isDown() or not racing() then return end
    cur.race.flags.died = true
    if state == STATE.RUNNING then endEarly(t) end
end

-- One damage update for the race's fight at `t`: a stamp, its offset kept, and past the buzzer the
-- restart flagged the moment it is heard.
local function stamp(t)
    local race, buzzerAt = cur.race, cur.buzzerAt
    cur.timeline:AddDamage(t)
    cur.lastDamage = round2(t - cur.startedAt)
    persistStamp()
    if buzzerAt and not race.flags.restartedAt then
        race.flags.restartedAt = round2(cur.timeline:RestartAt(buzzerAt, race.restartGap, cur.resumedAt))
        if race.flags.restartedAt then debug("damage restarted at +%.2f", race.flags.restartedAt) end
    end
end

--- DAMAGE_METER_COMBAT_SESSION_UPDATED(statType, sessionID): a stamp for the race's fight. A secret
--- session ID counts as the fight's own, as Fight takes it (the tail reads longer, never shorter).
function Race.OnMeterUpdate(t, statType, sessionID)
    if isDown() or not racing() or not cur.fight then return end
    local stat, id = Secrets.PlainNumber(statType), Secrets.PlainNumber(sessionID)
    if stat ~= nil and stat ~= NS.Meter.STAT_DAMAGE_DONE then return end
    if id == nil or cur.fight.sessionSet[id] then stamp(t) end
end

--- DAMAGE_METER_RESET while armed: the arm-time sessions are gone, so none is shared or netted. A race
--- under way loses its fight through Fight (FIGHT_ENDED "lost").
function Race.OnMeterReset()
    if isDown() or state ~= STATE.ARMED then return end
    cur.armSet, cur.baseline = {}, nil
    NS.Fight.ShareSessions(nil)
end

-- ── casts after the buzzer ──────────────────────────────────────────────────────────────────────

local function judge(spellID, t)
    if state ~= STATE.STOPPING or not cur.buzzerAt then return end
    local race = cur.race
    local offset = t - cur.buzzerAt
    if not NS.RaceScoring.IsLateCast(offset, race.grace) then return end
    local list = race.flags.lateCasts
    list[#list + 1] = { t = round2(offset), spellID = spellID }
    debug("late cast %s at +%.2f", tostring(spellID), offset)
end

-- Whether an auto-repeat spell is repeating now: what a success with a sealed spell ID is taken as.
local function autoRepeating()
    for id in pairs(Race.AUTO_REPEAT) do
        local ok, on = pcall(NS.Compat.IsAutoRepeatSpell, id)
        if ok and Secrets.PlainTruth(on) then return true end
    end
    return false
end

-- Whether a cast event is the cast in flight's own: by castGUID when both are readable, else by
-- spell ID when both are, else assumed so (the player casts one spell at a time).
local function isInFlight(guid, id)
    local f = cur.inFlight
    if not f then return false end
    if f.guid and guid then return f.guid == guid end
    if f.id and id then return f.id == id end
    return true
end

local function onSucceeded(id, guid, t)
    if isInFlight(guid, id) then
        cur.inFlight = nil
        return
    end
    if id and Race.AUTO_REPEAT[id] then return end
    if not id and autoRepeating() then return end
    judge(id, t)
end

--- A player cast: kind "start" | "channel" | "succeeded" | "interrupted" | "channelStop", with the
--- event's spell ID and castGUID (either may be secret: only a plain copy is compared or kept). A cast
--- counts at its start; a success with no start in flight (an instant) counts at its own time, and
--- the in-flight cast's own success is that cast finishing, judged already. An interrupt clears the
--- cast in flight; a channel's stop clears a channel. Starts are tracked from RUNNING, so a cast begun
--- before the buzzer and finished after it is never late; an auto-repeat's success is never a press.
function Race.OnCast(kind, spellID, t, castGUID)
    if isDown() or not racing() then return end
    local id, guid = Secrets.PlainNumber(spellID), Secrets.PlainString(castGUID)
    if kind == "start" or kind == "channel" then
        cur.inFlight = { id = id, guid = guid, channel = kind == "channel" }
        judge(id, t)
    elseif kind == "succeeded" then
        onSucceeded(id, guid, t)
    elseif kind == "interrupted" or (kind == "channelStop" and cur.inFlight and cur.inFlight.channel) then
        if isInFlight(guid, id) then cur.inFlight = nil end
    end
end

-- ── stop now ────────────────────────────────────────────────────────────────────────────────────

--- *Stop Now* on the Stop! and waiting screens: the fight is read without the settle's wait (ruling
--- X5, Fight.Hurry): at once out of combat, at the combat end in combat. Damage that lands after the
--- read is not counted. Nothing here looks at a meter value.
--- @return boolean acted
function Race.StopNow()
    if isDown() or state ~= STATE.STOPPING or not cur.fight then return false end
    cur.stopNow = true
    debug("stop now: the fight is read without the wait")
    NS.Fight.Hurry(cur.fight.id)
    return true
end

-- ── the read (modules/Recorder.lua pulls it) ────────────────────────────────────────────────────

local function num(v)
    return Secrets.PlainNumber(v) or 0
end

-- `final`'s merged spells less what the session held at the arm (keyed as baselineOf keys them).
local function netSpells(spells, held)
    local out = {}
    for _, sp in ipairs(type(spells) == "table" and spells or {}) do
        local key = sp.isPet and ("p" .. sp.spellID) or sp.spellID
        local total = num(sp.total) - (held[key] or 0)
        if total > 0 then out[#out + 1] = { spellID = sp.spellID, total = total, isPet = sp.isPet } end
    end
    table.sort(out, function(a, b) return a.total > b.total end)
    return out
end

-- A shared session's read, netted in place: the damage the session held at the arm comes off the
-- totals and off each spell. The meter's own rate and the session's duration span both fights, so
-- they are dropped (the record then times the fight by its own clock, modules/Recorder.lua).
local function net(final, base)
    local merged = type(final.merged) == "table" and final.merged or {}
    merged.total = math.max(0, num(merged.total) - num(base.total))
    merged.spells = netSpells(merged.spells, base.spells or {})
    merged.dps = nil
    if type(final.player) == "table" then final.player.total = math.max(0, num(final.player.total) - num(base.player)) end
    if type(final.pet) == "table" then final.pet.total = math.max(0, num(final.pet.total) - num(base.pet)) end
    final.merged, final.duration = merged, nil
end

-- The race DPS. An incomplete race whose fight carried on past `endedAt` (combat again after the early
-- end, Feign Death inside Combat Trail's grace: ruling X16) keeps the whole fight's total as its score,
-- so its DPS divides by the fight's own race clock, the first hit to the fight's end, never
-- `endedAt`; no meter read is taken at the early combat end. Any other race (a resumed one included:
-- its fight's end is the /reload's, not combat's) is RaceScoring.Dps's.
local function raceDps(fight, race)
    if race.status ~= "incomplete" or not cur.carriedOn or type(race.score) ~= "number" then
        return NS.RaceScoring.Dps(race.score, race)
    end
    local stop = Secrets.PlainNumber(fight.combatEndT) or Secrets.PlainNumber(fight.closedT) or GetTime()
    local span = math.max(round2(stop - cur.startedAt) or 0, race.endedAt or 0)
    if span <= 0 then return 0 end
    return race.score / span
end

-- The race clock's zero on the fight clock (ruling X9): combat entry to the first hit. A resumed race's
-- adopted fight carries the pull's own offset (its startT moved with its first hit), or starts on the
-- first hit (0) when the slot kept no combat entry.
local function firstHitOffset(fight)
    local from, at = Secrets.PlainNumber(fight.startT), Secrets.PlainNumber(fight.firstHitT)
    if not (from and at) or at < from then return nil end
    return round2(at - from)
end

-- The race's figures out of the fight's plain read.
local function score(fight, final)
    local race = cur.race
    if state == STATE.RUNNING then
        -- Combat ended with no regen edge heard (a client that never sent it): as before the buzzer.
        stopBuzzer()
        race.endedAt = round2(num(fight.combatEndT or GetTime()) - cur.startedAt)
    end
    race.score = Secrets.PlainNumber(final.merged and final.merged.total)
    if cur.buzzerAt then
        race.tail = round2(cur.timeline:Tail(cur.buzzerAt))
        if cur.combatEndedAt then race.combatEnd = round2(cur.combatEndedAt - cur.buzzerAt) end
    end
    race.status = race.endedAt and "incomplete" or "complete"
    race.dps = raceDps(fight, race)
    race.firstHit = firstHitOffset(fight)
    race.flags.sessionFromList = fight.boundBy == "tick" or nil
end

--- FIGHT_ENDED's race half, asked by Recorder before it judges the fight (ruling X1): a shared
--- session's read is netted, and the race's fight gets its score, DPS, timing and status ("lost"
--- when the fight could not be read). A fight the armed race was waiting on that never hit drops
--- the part and the arm waits for the next pull. Any other fight is left as it is.
--- @param fight table
--- @param final table|nil  Meter.ReadFinal's merged shape (netted in place for a shared session)
--- @param reason string  "final" | "lost"
function Race.Finalize(fight, final, reason)
    if type(fight) ~= "table" then return end
    if fight.sharedSession and type(fight.raceBaseline) == "table" and type(final) == "table" then
        net(final, fight.raceBaseline)
    end
    if isDown() or fight ~= cur.fight then return end
    if state == STATE.ARMED then
        fight.race, cur.fight = nil, nil
        return
    end
    if not racing() then return end
    if reason ~= "final" or type(final) ~= "table" then
        cur.race.status = "lost"
    else
        score(fight, final)
    end
    debug("fight %s read: race %s", tostring(fight.id), cur.race.status)
end

-- The race's fight was saved (its record) or skipped (nil): the result.
local function toResult(record)
    stopBuzzer()
    unpersist()
    cur.record = record
    NS.Fight.ShareSessions(nil)
    setState(STATE.RESULT)
    NS.SendBus(NS.MSG.RACE_RESULT, record, cur.race)
end

local function onSaved(record)
    if not racing() or not cur.fight or type(record) ~= "table" then return end
    if record.id ~= nil and record.id == cur.fight.recordID then toResult(record) end
end

local function onSkipped(fight)
    if not racing() or not cur.fight or fight ~= cur.fight then return end
    toResult(nil)
end

-- ── the lifecycle (core/LifecycleSetup.lua) ─────────────────────────────────────────────────────

--- The stand-down: the race in memory goes, silently, with its timer; the state is IDLE. Its slot
--- stays, so the stand-up's Resume carries a race under way on (an arm, never written, is dropped).
function Race.Suspend()
    stopBuzzer()
    cur = {}
    state = STATE.IDLE
    if NS.Fight and NS.Fight.ShareSessions then NS.Fight.ShareSessions(nil) end
end

-- ── the resume (Task B2) ────────────────────────────────────────────────────────────────────────

local RESUMABLE = { running = true, stopping = true }

-- Whether a slot holds a race that can be carried on: a part with a valid length, running or
-- stopping, a session, and a clock (the first hit's GetTime() or its date). Its flags are made whole.
local function resumable(slot)
    if type(slot) ~= "table" or type(slot.race) ~= "table" or type(slot.sessions) ~= "table" then return false end
    local race = slot.race
    if not (validLength(race.length) and RESUMABLE[race.status]) then return false end
    if type(slot.sessions[1]) ~= "number" then return false end
    if type(slot.startedAt) ~= "number" and type(slot.date) ~= "number" then return false end
    if type(race.flags) ~= "table" then race.flags = {} end
    if type(race.flags.lateCasts) ~= "table" then race.flags.lateCasts = {} end
    return true
end

-- The start on this session's clock. GetTime() survives a /reload; after a restart of the machine it
-- does not, and the stored date stands in.
local function startOf(slot, now)
    local s = slot.startedAt
    if type(s) == "number" and s <= now then return s end
    local date = type(slot.date) == "number" and slot.date or time()
    return now - math.max(0, time() - date)
end

local function sessionsHeld(sessions)
    for _, id in ipairs(sessions) do
        if not NS.Meter.HasSession(id) then return false end
    end
    return true
end

-- A race resumed that cannot go on: lost, shown as its result, nothing stored.
local function lose(why)
    debug("the resumed race is lost: %s", why)
    cur.race.status = "lost"
    toResult(nil)
end

-- A race kept as running: still racing with `left` seconds (true), or now waiting for its read. Before
-- the buzzer and out of combat, combat ended while nothing listened: incomplete, ended no later than
-- now (the combat end's real time is unknowable).
local function resumeRunning(race, now, inCombat)
    local elapsed = now - cur.startedAt
    local left = race.length - elapsed
    if left > 0 and inCombat then return true, left end
    if left > 0 then race.endedAt = round2(elapsed) end
    race.status = "stopping"
    return false
end

-- The fight the race's session belongs to, back through Fight's seam, on the resumed clock.
local function adoptFight(slot, inCombat)
    local shift = cur.startedAt - (type(slot.startedAt) == "number" and slot.startedAt or cur.startedAt)
    local startT = type(slot.startT) == "number" and slot.startT + shift or cur.startedAt
    return NS.Fight.Adopt({
        sessions = slot.sessions, startT = startT, firstHitT = cur.startedAt,
        lastUpdateT = cur.lastDamage and cur.startedAt + cur.lastDamage or nil, snapshot = slot.snapshot,
        stats = slot.stats, talents = slot.talents, gearSet = slot.gearSet, sharedSession = slot.sharedSession,
        raceBaseline = slot.baseline, boundBy = slot.boundBy, inCombat = inCombat,
    })
end

local function resumeRace(slot, key, now)
    local race = slot.race
    cur = { race = race, timeline = NS.RaceTimeline.New(), slot = slot, slotKey = key, resumedAt = now,
            date = slot.date }
    cur.startedAt = startOf(slot, now)
    -- The last update before the reload, so the tail and a restart gap still measure from it.
    local last = Secrets.PlainNumber(slot.lastDamage)
    if last then
        cur.timeline:AddDamage(cur.startedAt + last)
        cur.lastDamage = last
    end
    if not sessionsHeld(slot.sessions) then return lose("session gone") end
    local inCombat = UnitAffectingCombat("player") and true or false
    local running, left = false, nil
    if race.status == "running" then running, left = resumeRunning(race, now, inCombat) end
    -- Past its buzzer and not yet read: what was cast during the reload went unseen.
    if not running and race.endedAt == nil then
        cur.buzzerAt = cur.startedAt + race.length
        race.flags.reloaded = true
    end
    local fight = adoptFight(slot, inCombat)
    if not fight then return lose("no fight to carry it") end
    cur.fight, fight.race, slot.startedAt = fight, race, cur.startedAt
    debug("resumed %s (%s)", running and "running" or "stopping", cur.buzzerAt and "past the buzzer" or "before it")
    if running then
        scheduleBuzzer(left)
        return setState(STATE.RUNNING)
    end
    setState(STATE.STOPPING)
end

--- Carry on this character's race a /reload (or a stand-down) left running or stopping: from OnEnable
--- (core/CombatTrail.lua) and the stand-up (core/LifecycleSetup.lua), after the meter's priming. Another
--- character's slot waits for that character; a slot that cannot be raced is cleared. Retail only.
function Race.Resume()
    if isDown() or state ~= STATE.IDLE or not NS.Compat.ForClient(RETAIL) then return end
    local store, key = slots(), myKey()
    local slot = store and key and store[key]
    if slot == nil then return end
    if not resumable(slot) then
        debug("the stored race cannot be resumed: cleared")
        store[key] = nil
        return
    end
    resumeRace(slot, key, GetTime())
end

-- The bus, on Retail only (clients-§4): a receiver of this module's own (architecture-§4).
local receiver = NS.Compat.ForClient(RETAIL) and NS.NewBusTarget and NS.NewBusTarget()
if receiver then
    receiver:RegisterMessage(NS.MSG.FIGHT_STARTED, function(_, fight) onFightStarted(fight) end)
    receiver:RegisterMessage(NS.MSG.FIGHT_FIRST_HIT, function(_, fight) onFirstHit(fight) end)
    receiver:RegisterMessage(NS.MSG.FIGHT_SAVED, function(_, record) onSaved(record) end)
    receiver:RegisterMessage(NS.MSG.FIGHT_SKIPPED, function(_, fight) onSkipped(fight) end)
end
