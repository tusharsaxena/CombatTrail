local _, NS = ...
-- modules/CombatLog.lua — the Combat Log's capture and store (CombatTrail #11, plan item CL-11a): what
-- the addon may read of a fight, as one line each, into an in-memory ring the log views read, and a
-- compact copy of each fight's lines saved with its record. No view is built here (CL-11b).
--
-- THE SOURCES. Neither client lets an addon read the real combat log: WoW Forever forbids registering
-- COMBAT_LOG_EVENT_UNFILTERED and Retail 12.x seals it, so it is never registered, on either client.
-- The lines come only from what the addon may read:
--   * CASTS: the player's and the pet's, from the lanes' own capture (modules/LaneCasts.lua's
--     listener, as modules/Casts.lua hears them). No second UNIT_SPELLCAST_* registration. The
--     auto-repeat swings and shots (Casts.AUTO) reach the ring but are never saved.
--   * AURAS: gained and lost on `player` and on `target`, from UNIT_AURA's update info. A gain is
--     read off the added aura's data; a loss is told by its aura instance, which this file maps to
--     the spell it was given for (gains it heard, and the auras on at the fight's start or at a target
--     change, walked once). On the target only its buffs and the debuffs the player or the pet put on
--     it. A full update is walked again without a line (a target change is not a gain).
--   * HITS AND HEALS ON YOU: UNIT_COMBAT for `player` (WOUND and HEAL), with its school and its
--     critical, glancing or crushing mark. The amount is kept plain when it is plain; a sealed one is
--     saved as "s" (CombatLog.SEALED), never compared, counted or stored as a number.
--   * DEATHS AND BOUNDARIES: the fight's start, each combat end (PLAYER_REGEN_ENABLED) and the
--     player's death (PLAYER_DEAD). The addon knows no target's death, so none is logged.
-- Every client event goes through NS.SafeRegisterUnitEvent / NS.SafeRegisterEvent on this file's
-- own frame, and only while a fight is open and `log.enabled` is on: an event the client refuses
-- costs only itself and is named by CombatLog.Diagnose (UNIT_COMBAT is the one this probes, #11).
--
-- SECRETS. A sealed aura (its table, its spell ID or its instance) ends that aura's handling: its
-- name or ID is never guessed, and it produces no line. A sealed spell ID on a cast produces no line.
-- A sealed hit or heal amount is kept in the ring as the client gave it (`x`, for a view to hand to
-- a FontString, display only) and saved as "s".
--
-- THE RING holds the session's newest NS.Constants.LOG.RING lines, each { n (its sequence number),
-- at (GetTime()), k (CombatLog.KIND), u (CombatLog.UNIT), id?, a?, s?, f?, x? }. Its slots are
-- reused once it is full, so a busy fight allocates nothing per line after the first RING. A view
-- reads it by sequence number (CombatLog.Seq, CombatLog.Line) and redraws when the number moves:
-- appending a line is the whole of "marking it dirty".
--
-- A FIGHT'S LOG. FIGHT_STARTED opens a capture that freezes the settings at the start (save a log,
-- the lines kept, the categories saved) and takes the pre-pull casts still in the ring (from
-- Casts.PREPULL seconds before the start, never from before the last capture's end). FIGHT_ENDED
-- "final" closes it into its list at once and parks it (CombatLog.KEEP_FINISHED); the recorder takes
-- it with CombatLog.Finish(fightID). A lost fight's capture is dropped. The stand-down drops all.
--
-- THE SAVED LOG (the record's `log`, CT_SCHEMA 6) is an array, oldest first, of
-- { t (seconds from the fight's start, to the tenth), k, id?, u?, a?, s?, f? }: no string but "s",
-- names and icons resolved at display time from the spell ID. At most the frozen `lines`, the newest
-- kept; `logDropped` on the record counts the lines of saved categories that were not kept. A fight
-- saved before CT_SCHEMA 6, or with saving off, has no `log`, and CombatLog.Of answers nil for it.

local CombatLog = {}
NS.CombatLog = CombatLog

local Secrets = NS.Secrets
local Perf = NS.Perf
local C = NS.Constants.LOG

--- The line kinds (`k`). BUFF_ON / BUFF_OFF are BUFF+ and BUFF− in a view.
CombatLog.KIND = { CAST = 1, BUFF_ON = 2, BUFF_OFF = 3, DEBUFF_ON = 4, DEBUFF_OFF = 5, HIT = 6, HEAL = 7,
                   DIES = 8, START = 9, END = 10 }
--- The units (`u`): whose cast, whose aura, who was hit.
CombatLog.UNIT = { player = 1, pet = 2, target = 3 }
--- The marks (`f`), summed: a critical, a glancing or crushing blow, an interrupted cast.
CombatLog.FLAG = { CRIT = 1, GLANCING = 2, CRUSHING = 4, INTERRUPTED = 8 }
--- What a sealed amount is saved as.
CombatLog.SEALED = "s"
--- The categories a fight's log saves (`log.store.categories.<key>`), in the settings' order.
CombatLog.CATEGORIES = { "casts", "petCasts", "playerBuffs", "playerDebuffs", "targetBuffs", "targetDebuffs",
                         "hits", "heals", "deaths" }
--- How many closed fights' logs wait for the recorder.
CombatLog.KEEP_FINISHED = 4
--- The most auras walked per unit and filter when the instance map is (re)built.
CombatLog.AURA_LIMIT = 40
-- The most entries read from one update-info list (a guard, never a shape).
local LIST_LIMIT = 255

local K, U, F = CombatLog.KIND, CombatLog.UNIT, CombatLog.FLAG
local UNIT_BY_CODE = { "player", "pet", "target" }

local ring = {}         -- [slot] = line, slot = (n - 1) % C.RING + 1
local seq = 0           -- lines appended this session
local captures = {}     -- [fightID] = { fight, startT, from, store, lines, cats, n }
local finished = {}     -- [fightID] = { log, dropped }
local finishedOrder = {}
local lastEnd = -math.huge
local auras = { player = {}, target = {} }   -- [auraInstanceID] = spellID (a debuff's negated)
local frame             -- the event frame (nil until a fight first opens one)
local registered = false
local refused = {}      -- [event] = true: the client refused it this session

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("CombatLog", fmt, ...) end
end

-- ── the categories ──────────────────────────────────────────────────────────────────────────────

local CATEGORY = {
    [K.BUFF_ON] = { "playerBuffs", nil, "targetBuffs" }, [K.BUFF_OFF] = { "playerBuffs", nil, "targetBuffs" },
    [K.DEBUFF_ON] = { "playerDebuffs", nil, "targetDebuffs" },
    [K.DEBUFF_OFF] = { "playerDebuffs", nil, "targetDebuffs" },
}

--- The category a line is saved under, or nil: a boundary is always saved ("boundary"), an auto
--- attack never (nil).
--- @return string|nil
function CombatLog.CategoryOf(k, u, id)
    if k == K.START or k == K.END then return "boundary" end
    if k == K.CAST then
        if id and NS.Casts and NS.Casts.AUTO[id] then return nil end
        return u == U.pet and "petCasts" or "casts"
    end
    if k == K.HIT then return "hits" end
    if k == K.HEAL then return "heals" end
    if k == K.DIES then return "deaths" end
    local by = CATEGORY[k]
    return by and u and by[u] or nil
end

-- ── the ring ────────────────────────────────────────────────────────────────────────────────────

local function endOf(fight)
    return type(fight) == "table" and (fight.closedT or fight.combatEndT) or nil
end

-- Count the line toward every open capture whose window it falls in and whose settings save it.
local function count(at, k, u, id)
    if next(captures) == nil then return end
    local cat = CombatLog.CategoryOf(k, u, id)
    if not cat or cat == "boundary" then return end
    for _, cap in pairs(captures) do
        local stop = endOf(cap.fight)
        if at >= cap.from and (stop == nil or at <= stop) and cap.cats[cat] then cap.n = cap.n + 1 end
    end
end

-- One line into the ring: the slot's table is reused once the ring is full.
local function append(at, k, u, id, a, s, f, x)
    seq = seq + 1
    local slot = (seq - 1) % C.RING + 1
    local e = ring[slot]
    if e then
        e.n, e.at, e.k, e.u, e.id, e.a, e.s, e.f, e.x = seq, at, k, u, id, a, s, f, x
    else
        ring[slot] = { n = seq, at = at, k = k, u = u, id = id, a = a, s = s, f = f, x = x }
    end
    count(at, k, u, id)
end

--- The newest line's sequence number (0 before any). A view redraws when it moves.
--- @return number
function CombatLog.Seq()
    return seq
end

--- The line with sequence number `n`, while the ring still holds it, else nil. The table is the
--- ring's own and is reused: read it, never keep it.
--- @return table|nil
function CombatLog.Line(n)
    if type(n) ~= "number" or n < 1 or n > seq or n <= seq - C.RING then return nil end
    local e = ring[(n - 1) % C.RING + 1]
    return e and e.n == n and e or nil
end

--- The oldest sequence number the ring still holds (seq + 1 when it is empty).
--- @return number
function CombatLog.First()
    return math.max(1, seq - C.RING + 1)
end

--- How many lines the ring holds now (the suites' bound check).
function CombatLog.__ringCount()
    local n = 0
    for _ in pairs(ring) do n = n + 1 end
    return math.min(n, seq)
end

-- ── the casts (the lanes' listener) ─────────────────────────────────────────────────────────────

--- One cast: `unit` "player" or "pet", `spellID` as the event gave it (a sealed one is no line),
--- `t` GetTime(), `interrupted` whether the cast in flight was interrupted.
function CombatLog.OnCast(unit, spellID, t, interrupted)
    local u = (unit == "player" or unit == "pet") and U[unit] or nil
    local id = u and Secrets.PlainNumber(spellID)
    if not id or type(t) ~= "number" then return end
    append(t, K.CAST, u, id, nil, nil, interrupted == true and F.INTERRUPTED or nil, nil)
end

-- ── the auras ───────────────────────────────────────────────────────────────────────────────────

local function api(name)
    local ns = C_UnitAuras
    return type(ns) == "table" and ns[name] or nil
end

local function passResults(ok, ...)
    if ok then return ... end
    return nil
end

-- Whether the player or the pet put this aura on (a target's debuff is logged only then).
local function fromMe(aura)
    if Secrets.PlainTruth(aura.isFromPlayerOrPlayerPet) then return true end
    local src = Secrets.PlainString(aura.sourceUnit)
    return src == "player" or src == "pet"
end

-- An aura's instance and map value (its spell ID, negated for a debuff), or nil when anything is
-- sealed, or when it is a target's debuff someone else put on. `harmful` is the walk's filter; an
-- added aura says it itself (isHarmful, else a plain isHelpful of false).
local function mapped(unit, aura, harmful)
    if Secrets.IsSealed(aura) or not Secrets.CanAccessTable(aura) then return nil end
    local inst, id = Secrets.PlainNumber(aura.auraInstanceID), Secrets.PlainNumber(aura.spellId)
    if not inst or not id then return nil end
    if harmful == nil then
        harmful = Secrets.PlainTruth(aura.isHarmful) or Secrets.PlainEquals(aura.isHelpful, false)
    end
    if harmful and unit == "target" and not fromMe(aura) then return nil end
    return inst, harmful and -id or id
end

local FILTERS = { "HELPFUL", "HARMFUL" }

local function clear(map)
    for key in pairs(map) do map[key] = nil end
end

-- The unit's auras now, into its map, without a line. A raise (WoW Forever's sealed read raises,
-- docs/forever-quirks.md) or a sealed aura ends that filter's walk.
local function walk(unit)
    local map, get = auras[unit], api("GetAuraDataByIndex")
    clear(map)
    if type(get) ~= "function" then return end
    for _, filter in ipairs(FILTERS) do
        local harmful = filter == "HARMFUL"
        for i = 1, CombatLog.AURA_LIMIT do
            local aura = passResults(pcall(get, unit, i, filter))
            if aura == nil or Secrets.IsSealed(aura) or not Secrets.CanAccessTable(aura) then break end
            local inst, v = mapped(unit, aura, harmful)
            if inst then map[inst] = v end
        end
    end
end

local function added(unit, list, at)
    if not Secrets.CanAccessTable(list) then return end
    local map, u = auras[unit], U[unit]
    for i = 1, LIST_LIMIT do
        local aura = list[i]
        if aura == nil then break end
        local inst, v = mapped(unit, aura)
        if inst and map[inst] == nil then
            map[inst] = v
            append(at, v < 0 and K.DEBUFF_ON or K.BUFF_ON, u, v < 0 and -v or v, nil, nil, nil, nil)
        end
    end
end

local function removed(unit, list, at)
    if not Secrets.CanAccessTable(list) then return end
    local map, u = auras[unit], U[unit]
    for i = 1, LIST_LIMIT do
        local raw = list[i]
        if raw == nil then break end
        local inst = Secrets.PlainNumber(raw)
        local v = inst and map[inst]
        if v then
            map[inst] = nil
            append(at, v < 0 and K.DEBUFF_OFF or K.BUFF_OFF, u, v < 0 and -v or v, nil, nil, nil, nil)
        end
    end
end

--- UNIT_AURA for `player` or `target`: its added auras are gains, its removed instances losses; a full
--- update (or no update info) walks the unit again without a line.
function CombatLog.OnAura(unit, info, at)
    if unit ~= "player" and unit ~= "target" then return end
    if Secrets.IsSealed(info) or not Secrets.CanAccessTable(info) or Secrets.PlainTruth(info.isFullUpdate) then
        return walk(unit)
    end
    added(unit, info.addedAuras, at)
    removed(unit, info.removedAuraInstanceIDs, at)
end

-- ── hits and heals ──────────────────────────────────────────────────────────────────────────────

local ACTION = { WOUND = K.HIT, HEAL = K.HEAL }
local MARK = { CRITICAL = F.CRIT, GLANCING = F.GLANCING, CRUSHING = F.CRUSHING }

--- UNIT_COMBAT for `player`: a WOUND is a hit, a HEAL a heal; every other action (a miss, a dodge, an
--- immune) is no line. A sealed action says nothing and is no line.
function CombatLog.OnCombat(unit, action, descriptor, amount, school, at)
    if Secrets.PlainString(unit) ~= "player" then return end
    local k = ACTION[Secrets.PlainString(action) or ""]
    if not k then return end
    local a, x = Secrets.PlainNumber(amount), nil
    if a == nil and Secrets.IsSealed(amount) then a, x = CombatLog.SEALED, amount end
    append(at, k, U.player, nil, a, Secrets.PlainNumber(school), MARK[Secrets.PlainString(descriptor) or ""], x)
end

-- ── the events ──────────────────────────────────────────────────────────────────────────────────

-- Each handler takes `at` (GetTime()) first, then the event's own arguments.
local HANDLERS = {
    UNIT_AURA = function(at, unit, info) CombatLog.OnAura(Secrets.PlainString(unit), info, at) end,
    UNIT_COMBAT = function(at, unit, action, descriptor, amount, school)
        CombatLog.OnCombat(unit, action, descriptor, amount, school, at)
    end,
    PLAYER_DEAD = function(at) append(at, K.DIES, U.player, nil, nil, nil, nil, nil) end,
    PLAYER_REGEN_ENABLED = function(at) append(at, K.END, nil, nil, nil, nil, nil, nil) end,
    PLAYER_TARGET_CHANGED = function() walk("target") end,
}

local function onEvent(_, event, ...)
    local t0 = Perf.on and debugprofilestop()
    local handler = HANDLERS[event]
    if handler then handler(GetTime(), ...) end
    if t0 then Perf.Note("combatLog", debugprofilestop() - t0) end
end

-- What is registered, and on which units.
local UNIT_EVENTS = { { "UNIT_AURA", "player", "target" }, { "UNIT_COMBAT", "player" } }
local EVENTS = { "PLAYER_DEAD", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED" }

local function wanted()
    if NS.IsStoodDown and NS.IsStoodDown() then return false end
    return next(captures) ~= nil
end

local function register()
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
    end
    for _, spec in ipairs(UNIT_EVENTS) do
        local event = spec[1]
        if not refused[event] and not NS.SafeRegisterUnitEvent(frame, event, NS.rejectedEvents, spec[2], spec[3]) then
            refused[event] = true
            debug("%s refused by the client", event)
        end
    end
    for _, event in ipairs(EVENTS) do
        if not refused[event] and not NS.SafeRegisterEvent(frame, event, nil, NS.rejectedEvents) then
            refused[event] = true
            debug("%s refused by the client", event)
        end
    end
    registered = true
    walk("player")
    walk("target")
end

--- Make the registrations match: the events while a fight's capture is open, else none.
function CombatLog.Sync()
    local want = wanted()
    if want == registered then return end
    if want then return register() end
    if frame then frame:UnregisterAllEvents() end
    registered = false
    clear(auras.player)
    clear(auras.target)
end

--- What the capture registers and what the client refused (the diagnostics' and `/ct probe`'s line).
--- @return table  { registered = boolean, refused = { event, ... } (sorted), lines = number }
function CombatLog.Diagnose()
    local out = {}
    for event in pairs(refused) do out[#out + 1] = event end
    table.sort(out)
    return { registered = registered, refused = out, lines = seq }
end

--- The event frame (nil until a fight first opened one), for the suites and the perf runner.
function CombatLog.EventFrame()
    return frame
end

-- ── a fight's capture ───────────────────────────────────────────────────────────────────────────

local function setting(path)
    return NS.GetSetting and NS.GetSetting("log." .. path)
end

-- The lines a fight keeps: the setting, whole and inside its range.
local function linesKept()
    local v = Secrets.PlainNumber(setting("store.lines")) or C.MAX_PER_FIGHT
    return math.max(C.MIN_PER_FIGHT, math.min(C.MAX_LINES, math.floor(v)))
end

local function categories()
    local out = { boundary = true }
    for _, key in ipairs(CombatLog.CATEGORIES) do out[key] = setting("store.categories." .. key) ~= false end
    return out
end

-- The latest end among the captures still open, or of the last one closed.
local function floorAt()
    local f = lastEnd
    for _, cap in pairs(captures) do
        local e = endOf(cap.fight)
        if e and e > f then f = e end
    end
    return f
end

-- The pre-pull casts still in the ring, counted toward the new capture.
local function countPrepull(cap)
    for n = seq, CombatLog.First(), -1 do
        local e = CombatLog.Line(n)
        if not e or e.at < cap.from then break end
        local cat = CombatLog.CategoryOf(e.k, e.u, e.id)
        if cat and cat ~= "boundary" and cap.cats[cat] then cap.n = cap.n + 1 end
    end
end

--- A fight started at `startT` (GetTime()): its lines are held from the pre-pull on, and the events
--- registered. Nothing happens while `log.enabled` is off.
--- @param fightID string
--- @param startT number
--- @param fight table|nil  the fight table, read again at the end for when it stopped
function CombatLog.Begin(fightID, startT, fight)
    if type(fightID) ~= "string" or type(startT) ~= "number" or setting("enabled") == false then return end
    local prepull = NS.Casts and NS.Casts.PREPULL or 0
    local cap = { fight = fight or { startT = startT }, startT = startT,
                  from = math.max(startT - prepull, floorAt()), store = setting("store.enabled") ~= false,
                  lines = linesKept(), cats = categories(), n = 0 }
    countPrepull(cap)
    captures[fightID] = cap
    append(startT, K.START, nil, nil, nil, nil, nil, nil)
    CombatLog.Sync()
end

local function tenth(x)
    return math.floor(x * 10 + 0.5) / 10
end

-- A saved line out of a ring line.
local function saved(e, startT)
    return { t = tenth(e.at - startT), k = e.k, id = e.id, u = e.u, a = e.a, s = e.s, f = e.f }
end

-- The capture's lines up to `to` that its settings save, oldest first, at most its `lines` (the
-- newest), and how many lines of saved categories were not kept.
local function listOf(cap, to)
    local picked = {}
    for n = CombatLog.First(), seq do
        local e = CombatLog.Line(n)
        if e and e.at >= cap.from and e.at <= to then
            local cat = CombatLog.CategoryOf(e.k, e.u, e.id)
            if cat and cap.cats[cat] then picked[#picked + 1] = e end
        end
    end
    local skip = math.max(0, #picked - cap.lines)
    local log, kept = {}, 0
    for i = skip + 1, #picked do
        local e = picked[i]
        log[#log + 1] = saved(e, cap.startT)
        if e.k ~= K.START and e.k ~= K.END then kept = kept + 1 end
    end
    return log, math.max(0, cap.n - kept)
end

local function close(fightID)
    local cap = captures[fightID]
    if not cap then return nil end
    captures[fightID] = nil
    local to = endOf(cap.fight) or GetTime()
    if to > lastEnd then lastEnd = to end
    CombatLog.Sync()
    if not cap.store then return { dropped = 0 } end
    local log, dropped = listOf(cap, to)
    debug("fight %s: %d line(s) kept, %d dropped", fightID, #log, dropped)
    return { log = log, dropped = dropped }
end

local function park(fightID, done)
    finished[fightID] = done
    finishedOrder[#finishedOrder + 1] = fightID
    while #finishedOrder > CombatLog.KEEP_FINISHED do
        finished[table.remove(finishedOrder, 1)] = nil
    end
end

local function unpark(fightID)
    local done = finished[fightID]
    finished[fightID] = nil
    for i = #finishedOrder, 1, -1 do
        if finishedOrder[i] == fightID then table.remove(finishedOrder, i) end
    end
    return done
end

--- The fight's saved log and how many lines were dropped; nil when it has none (saving off, lost,
--- never begun, or taken already). Answers once.
--- @return table|nil log, number|nil dropped
function CombatLog.Finish(fightID)
    local done = unpark(fightID) or close(fightID)
    if not done or not done.log then return nil end
    return done.log, done.dropped
end

--- Let a fight's capture go without a log (a lost or skipped fight). Its end still bounds the next
--- fight's pre-pull, as a closed one's does.
function CombatLog.Drop(fightID)
    unpark(fightID)
    local cap = captures[fightID]
    if cap then
        captures[fightID] = nil
        local to = endOf(cap.fight) or GetTime()
        if to > lastEnd then lastEnd = to end
        CombatLog.Sync()
    end
end

--- The fight open now (its capture's start), for a live view: startT, or nil with none open.
--- @return number|nil
function CombatLog.LiveStart()
    local newest
    for _, cap in pairs(captures) do
        if not newest or cap.startT > newest then newest = cap.startT end
    end
    return newest
end

-- ── a stored fight's log ────────────────────────────────────────────────────────────────────────

--- A stored record's log, or nil (a fight saved before CT_SCHEMA 6, or with saving off), and how many
--- lines it dropped (0 when none were).
--- @param record table|nil
--- @return table|nil log, number dropped
function CombatLog.Of(record)
    local log = type(record) == "table" and record.log or nil
    if type(log) ~= "table" then return nil, 0 end
    return log, Secrets.PlainNumber(record.logDropped) or 0
end

--- The unit token a line's `u` stands for, or nil.
function CombatLog.UnitOf(u)
    return UNIT_BY_CODE[u]
end

-- ── the lifecycle ───────────────────────────────────────────────────────────────────────────────

--- The stand-down: every registration, capture, parked log and ring line goes.
function CombatLog.Suspend()
    captures, finished, finishedOrder = {}, {}, {}
    ring, seq, lastEnd = {}, 0, -math.huge
    if frame then frame:UnregisterAllEvents() end
    registered = false
    clear(auras.player)
    clear(auras.target)
end

--- The stand-up: rebuilt from the current state (no fight is open after a stand-down).
function CombatLog.Resume()
    CombatLog.Sync()
end

-- ── wiring ──────────────────────────────────────────────────────────────────────────────────────

NS.LaneCasts.Listen("log", CombatLog.OnCast)

local busTarget = NS.NewBusTarget()
if busTarget then
    busTarget:RegisterMessage(NS.MSG.FIGHT_STARTED, function(_, fight)
        if type(fight) == "table" then CombatLog.Begin(fight.id, fight.startT, fight) end
    end)
    busTarget:RegisterMessage(NS.MSG.FIGHT_ENDED, function(_, fight, _, reason)
        if type(fight) ~= "table" then return end
        if reason == "final" then
            local done = close(fight.id)
            if done then park(fight.id, done) end
        else
            CombatLog.Drop(fight.id)
        end
    end)
end
