local _, NS = ...
-- modules/CombatLog.lua — the Combat Sequence's capture and store (CombatTrail #11, plan item CL-11a; the
-- Combat Sequence, CSEQ-1, 2026-11-25): what the addon may read of a fight, as one line each, into an
-- in-memory ring the views read, and a compact copy of each fight's lines saved with its record. No
-- view is built here (CL-11b). The file keeps its old name; the player sees "Combat Sequence".
--
-- THE SOURCES. Neither client lets an addon read the real combat log: WoW Forever forbids registering
-- COMBAT_LOG_EVENT_UNFILTERED and Retail 12.x seals it, so it is never registered, on either client.
-- So no line carries an amount: the hits and heals the addon could hear were only those TAKEN
-- (UNIT_COMBAT on `player`), which read as the player's own, so UNIT_COMBAT is never registered either
-- (the owner's Combat Sequence ruling, 2026-11-25). The lines come only from what the addon may read:
--   * CASTS: the player's and the pet's, from the lanes' own capture (modules/LaneCasts.lua's
--     listener, as modules/Casts.lua hears them). No second UNIT_SPELLCAST_* registration. The
--     auto-repeat swings and shots (Casts.AUTO) reach the ring but are never saved.
--   * AURAS: the buffs and debuffs gained and lost on `player`, and the debuffs the player or the pet
--     put on `target` (no target buff is a line). A gain is read off the added aura's data; a loss is
--     told by its aura instance, which this file maps to the spell it was given for (gains it heard,
--     and the auras on at the capture's registration or at a target change, walked once, silently).
--     UNIT_AURA's update info (`addedAuras`, `removedAuraInstanceIDs`) gives them where the client
--     sends it. A FULL UPDATE, or a UNIT_AURA with no usable update info (WoW Forever's, if it sends
--     none: docs/forever-quirks.md), is a DIFF: the unit is walked into a scratch map and compared with
--     the current one (an instance only in the scratch map is a gain, one only in the current map a
--     loss), gains first in walk order, then losses by ascending instance; then the two maps swap.
--     AN INCOMPLETE WALK LOGS NOTHING (a sealed or unreadable aura, a raising read, AURA_LIMIT reached):
--     what it cannot read is skipped and the walk goes on, its entries are added to the current map
--     with no line, so neither a false loss nor, on the next complete diff, a false gain is drawn. A
--     target change walks the new target silently, and the target is diffed only while its plain GUID
--     is the one its map was walked for (a full update for a new target can come before the change).
--   * DEATHS: the player's (PLAYER_DEAD). The addon knows no target's death, so none is logged.
-- RETIRED LINES. A log saved before this file's present shape may hold kinds nothing captures now: the
-- fight's START and END (owner feedback item 10), HIT and HEAL (the Combat Sequence), and a BUFF± on the
-- target. Every read drops them (CombatLog.IsRetired), and no saved log is rewritten.
-- Every client event goes through NS.SafeRegisterUnitEvent / NS.SafeRegisterEvent on this file's
-- own frame, and only while a fight is open and `sequence.enabled` is on: an event the client refuses
-- costs only itself and is named by CombatLog.Diagnose.
--
-- THE AURA TALLY (owner feedback round 5, R5-CT-03). WoW Forever's real fights showed only CAST rows,
-- and which read drops the auras cannot be told offline, so the capture counts what UNIT_AURA brings
-- (per unit; usable update info, none, a full update, sealed info), each added aura and why it drew no
-- line (its table, instance, spell ID or, on the target, its source sealed; a target debuff someone else
-- put on; a target buff), each removed instance (lined, never mapped, sealed), the walks (complete or
-- not, a raised read, an unreadable aura) and the lines drawn. Plain counts only, zeroed at each
-- registration (the first open capture), so after a fight they describe that fight: CombatLog.Diagnose's
-- `auras`, printed by `/ct diagnostics` (modules/Diagnostics.lua).
--
-- SECRETS. A sealed aura (its table, its spell ID or its instance) ends that aura's handling: its
-- name or ID is never guessed, and it produces no line. A sealed spell ID on a cast produces no line.
-- Only plain numbers are compared or used as keys: a map's key is an instance that passed
-- Secrets.PlainNumber, its value a spell ID that passed it. No secret is compared, counted or stored.
--
-- THE RING holds the session's newest NS.Constants.LOG.RING lines, each { n (its sequence number),
-- at (GetTime()), k (CombatLog.KIND), u (CombatLog.UNIT), id?, f?, g? }. Its slots are reused once it is
-- full, so a busy fight allocates nothing per line after the first RING. A view reads it by sequence
-- number (CombatLog.Seq, CombatLog.Line) and redraws when the number moves: appending a line is the
-- whole of "marking it dirty".
--
-- WHICH TARGET. A line on the target (`u` 3) carries `g`, its index into the session's target list
-- (CombatLog.Targets): each target the capture saw, { name? (plain, nil when the client sealed it),
-- friendly? (true when the player could not attack it) }, noted at the capture's registration and at
-- each PLAYER_TARGET_CHANGED, once per name and reaction (at most TARGET_LIMIT; past it a line has no
-- `g`). So a target swap mid-fight never renames the rows before it.
--
-- A FIGHT'S LOG. FIGHT_STARTED opens a capture that freezes the settings at the start (save a log,
-- the lines kept, the categories saved) and takes the pre-pull casts still in the ring (from
-- Casts.PREPULL seconds before the start, never from before the last capture's end). FIGHT_ENDED
-- "final" closes it into its list at once and parks it (CombatLog.KEEP_FINISHED); the recorder takes
-- it with CombatLog.Finish(fightID). A lost fight's capture is dropped. The stand-down drops all.
-- EACH CAPTURE KEEPS ITS OWN LIST of the lines it saves (`keep`, at most its `lines`, its slots reused
-- once full), appended as each line arrives, so the saved log never depends on what else the shared
-- ring held: a fight with heavy unsaved traffic (auto attacks, categories not saved) still keeps its
-- `lines` newest saved lines.
--
-- THE SAVED LOG (the record's `log`, CT_SCHEMA 6) is an array, oldest first, of
-- { t (seconds from the fight's start, to the tenth), k, id?, u?, f?, g? }: no string, names and icons
-- resolved at display time from the spell ID. A line saved earlier may still carry `a` (an amount) or
-- `s` (a school): no view reads them. At most the frozen `lines`, the newest kept; `logDropped` on the
-- record counts the lines of saved categories that were not kept. `logTargets` on the record is the
-- fight's own target list, { { name?, friendly? }, ... }, which a saved line's `g` indexes. A fight
-- saved before CT_SCHEMA 6, or with saving off, has no `log`, and CombatLog.Of answers nil for it.
--
-- THE SAMPLE SEAM (owner feedback round 4, R4-CT-01). Test mode and the sim show a made-up sequence
-- (modules/MockFights.lua SequenceOf, fed by modules/Preview.lua) in the live views: CombatLog.UseSample
-- swaps what the views read (CombatLog.Seq, Line, First, Window and Targets) to a private sample ring,
-- CombatLog.SampleAppend adds a line to it, and CombatLog.EndSample drops it and gives the views the
-- real ring back. A sample line never reaches the real ring, a capture or a saved log: the captures
-- read the real ring alone (their pre-pull too), and the real ring goes on filling meanwhile. Each swap
-- tells the views (CombatLog.Watch), which start their feeds over, as a real fight's start does.

local CombatLog = {}
NS.CombatLog = CombatLog

local Secrets = NS.Secrets
local Perf = NS.Perf
local C = NS.Constants.LOG

--- The line kinds (`k`). BUFF_ON / BUFF_OFF are BUFF+ and BUFF− in a view. The numbers never move,
--- because saved logs carry them. HIT, HEAL, START and END are RETIRED: never captured, kept only so a
--- log saved before can be read past them (CombatLog.IsRetired).
CombatLog.KIND = { CAST = 1, BUFF_ON = 2, BUFF_OFF = 3, DEBUFF_ON = 4, DEBUFF_OFF = 5, HIT = 6, HEAL = 7,
                   DIES = 8, START = 9, END = 10 }
--- The units (`u`): whose cast, whose aura.
CombatLog.UNIT = { player = 1, pet = 2, target = 3 }
--- The marks (`f`): an interrupted cast. Bits 1, 2 and 4 (the hits' critical, glancing and crushing
--- marks) are reserved, because saved data may carry them, and never reused.
CombatLog.FLAG = { INTERRUPTED = 8 }
--- The categories a fight's log saves (`sequence.store.categories.<key>`), in the settings' order.
CombatLog.CATEGORIES = { "casts", "petCasts", "playerBuffs", "playerDebuffs", "targetDebuffs", "deaths" }
--- How many closed fights' logs wait for the recorder.
CombatLog.KEEP_FINISHED = 4
--- The most auras walked per unit and filter: a walk that reaches it is incomplete.
CombatLog.AURA_LIMIT = 40
--- The most targets the session's list notes (a guard: one entry per name and reaction).
CombatLog.TARGET_LIMIT = 500
-- The most entries read from one update-info list (a guard, never a shape).
local LIST_LIMIT = 255

local K, U, F = CombatLog.KIND, CombatLog.UNIT, CombatLog.FLAG
local UNIT_BY_CODE = { "player", "pet", "target" }

local ring = {}         -- [slot] = line, slot = (n - 1) % C.RING + 1
local seq = 0           -- lines appended this session
local captures = {}     -- [fightID] = { fight, startT, from, store, lines, cats, n, keep, head }
local targets = {}      -- the session's targets: [g] = { name?, friendly? }
local targetAt = {}     -- [name .. reaction] = g
local curTarget         -- the target now (its g), or nil
local finished = {}     -- [fightID] = { log, dropped }
local finishedOrder = {}
local lastEnd = -math.huge
local viewStart, viewFrom   -- the newest capture begun this session: its start and its pre-pull floor
local auras = { player = {}, target = {} }   -- the current maps: [auraInstanceID] = spellID (a debuff's negated)
local spare = { player = {}, target = {} }   -- the diff's scratch maps, swapped with the current ones
local order, orderN = {}, 0                  -- the last walk's new instances, in walk order (reused)
local fades = {}                             -- a diff's lost instances, sorted (reused)
local targetOf          -- the target's plain GUID when its map was last walked, or nil
local frame             -- the event frame (nil until a fight first opens one)
local registered = false
local refused = {}      -- [event] = true: the client refused it this session
local sample            -- the sample seam's ring while it is up: { ring, seq, startT, from, targets }
local watchers = {}     -- [key] = fn: the views told of each swap
--- The aura tally's counters, in the order `/ct diagnostics` prints them (R5-CT-03).
CombatLog.TALLY = { "evPlayer", "evTarget", "info", "none", "full", "sealedInfo", "gainSeen", "gainLined",
    "gainSealedTable", "gainSealedInstance", "gainSealedSpell", "gainSealedSource", "gainNotYours",
    "gainTargetBuff", "lossSeen", "lossLined", "lossUnknown", "lossSealed", "walkComplete",
    "walkIncomplete", "walkRaised", "walkUnreadable" }
local tally = {}        -- [counter] = count since the last registration
for _, key in ipairs(CombatLog.TALLY) do tally[key] = 0 end

local function bump(key) tally[key] = tally[key] + 1 end
-- An added aura's reason for no line, by mapped()'s second answer.
local DROP = { table = "gainSealedTable", inst = "gainSealedInstance", spell = "gainSealedSpell",
               source = "gainSealedSource", other = "gainNotYours", buff = "gainTargetBuff" }
-- The tally's line count per kind.
local LINED = { [CombatLog.KIND.BUFF_ON] = "gainLined", [CombatLog.KIND.DEBUFF_ON] = "gainLined",
                [CombatLog.KIND.BUFF_OFF] = "lossLined", [CombatLog.KIND.DEBUFF_OFF] = "lossLined" }

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("CombatLog", fmt, ...) end
end

-- ── the categories ──────────────────────────────────────────────────────────────────────────────

-- [kind] = { the player's, the pet's, the target's }: no target buff is a category.
local CATEGORY = {
    [K.BUFF_ON] = { "playerBuffs" }, [K.BUFF_OFF] = { "playerBuffs" },
    [K.DEBUFF_ON] = { "playerDebuffs", nil, "targetDebuffs" },
    [K.DEBUFF_OFF] = { "playerDebuffs", nil, "targetDebuffs" },
}
local RETIRED = { [K.HIT] = true, [K.HEAL] = true, [K.START] = true, [K.END] = true }

--- Whether a line is retired: a kind nothing captures now (HIT, HEAL, the PULL and END boundaries), or
--- a BUFF± on the target, from a log saved before. Every view drops it at read time.
--- @return boolean
function CombatLog.IsRetired(e)
    if type(e) ~= "table" then return false end
    local k = e.k
    if RETIRED[k] then return true end
    return (k == K.BUFF_ON or k == K.BUFF_OFF) and e.u == U.target
end

--- The category a line is saved under, or nil: an auto attack and a retired line never (nil).
--- @return string|nil
function CombatLog.CategoryOf(k, u, id)
    if k == K.CAST then
        if id and NS.Casts and NS.Casts.AUTO[id] then return nil end
        return u == U.pet and "petCasts" or "casts"
    end
    if k == K.DIES then return "deaths" end
    local by = CATEGORY[k]
    return by and u and by[u] or nil
end

-- ── the ring ────────────────────────────────────────────────────────────────────────────────────

local function endOf(fight)
    return type(fight) == "table" and (fight.closedT or fight.combatEndT) or nil
end

-- Line `e` into capture `cap`'s own list of saved lines: at most its `lines`, the slots reused once
-- it is full (the oldest goes). A copy of the plain fields: the ring's table is reused.
local function keep(cap, e)
    cap.head = cap.head + 1
    local slot = (cap.head - 1) % cap.lines + 1
    local c = cap.keep[slot]
    if c then
        c.at, c.k, c.u, c.id, c.f, c.g = e.at, e.k, e.u, e.id, e.f, e.g
    else
        cap.keep[slot] = { at = e.at, k = e.k, u = e.u, id = e.id, f = e.f, g = e.g }
    end
end

-- Whether line `e` falls in capture `cap`'s window and its settings save it: its category, or nil.
local function savedBy(cap, e)
    local cat = CombatLog.CategoryOf(e.k, e.u, e.id)
    if not cat or not cap.cats[cat] or e.at < cap.from then return nil end
    local stop = endOf(cap.fight)
    if stop ~= nil and e.at > stop then return nil end
    return cat
end

-- Keep the line in every open capture whose window it falls in and whose settings save it, and count
-- it there.
local function count(e)
    if next(captures) == nil then return end
    for _, cap in pairs(captures) do
        if savedBy(cap, e) then
            if cap.store then keep(cap, e) end
            cap.n = cap.n + 1
        end
    end
end

-- One line into the ring: the slot's table is reused once the ring is full. A line on the target
-- carries the target now (`g`).
local function append(at, k, u, id, f)
    seq = seq + 1
    local g = u == U.target and curTarget or nil
    local slot = (seq - 1) % C.RING + 1
    local e = ring[slot]
    if e then
        e.n, e.at, e.k, e.u, e.id, e.f, e.g = seq, at, k, u, id, f, g
    else
        e = { n = seq, at = at, k = k, u = u, id = id, f = f, g = g }
        ring[slot] = e
    end
    if LINED[k] then bump(LINED[k]) end
    count(e)
end

-- ── the targets ─────────────────────────────────────────────────────────────────────────────────

-- The target now as the session's list knows it (noted once per name and reaction), or nil with no
-- target (or the list full). Plain answers only: a sealed name is noted as no name.
local function noteTarget()
    if type(UnitExists) == "function" and not Secrets.PlainTruth(UnitExists("target")) then return nil end
    local okName, raw = pcall(UnitName, "target")
    local name = okName and Secrets.PlainString(raw) or nil
    local friendly = false
    if type(UnitCanAttack) == "function" then
        local ok, hostile = pcall(UnitCanAttack, "player", "target")
        friendly = ok and Secrets.PlainEquals(hostile, false) or false
    end
    local key = (name or "") .. (friendly and "|f" or "|h")
    local g = targetAt[key]
    if g then return g end
    if #targets >= CombatLog.TARGET_LIMIT then return nil end
    g = #targets + 1
    targets[g] = { name = name, friendly = friendly or nil }
    targetAt[key] = g
    return g
end

--- The session's target list, [g] = { name?, friendly? }: what a ring line's `g` indexes. The table is
--- this file's own: read it, never change it.
--- @return table
function CombatLog.Targets()
    if sample then return sample.targets end
    return targets
end

-- Line `n` of ring `r`, whose newest is `top`, while it still holds it.
local function lineOf(r, top, n)
    if type(n) ~= "number" or n < 1 or n > top or n <= top - C.RING then return nil end
    local e = r[(n - 1) % C.RING + 1]
    return e and e.n == n and e or nil
end

--- The newest line's sequence number (0 before any). A view redraws when it moves. The sample's
--- while the sample seam is up.
--- @return number
function CombatLog.Seq()
    if sample then return sample.seq end
    return seq
end

--- The line with sequence number `n`, while the ring still holds it, else nil (the sample's while the
--- seam is up). The table is the ring's own and is reused: read it, never keep it.
--- @return table|nil
function CombatLog.Line(n)
    if sample then return lineOf(sample.ring, sample.seq, n) end
    return lineOf(ring, seq, n)
end

--- The oldest sequence number the ring still holds (seq + 1 when it is empty).
--- @return number
function CombatLog.First()
    return math.max(1, CombatLog.Seq() - C.RING + 1)
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
    append(t, K.CAST, u, id, interrupted == true and F.INTERRUPTED or nil)
end

-- ── the auras ───────────────────────────────────────────────────────────────────────────────────

local function api(name)
    local ns = C_UnitAuras
    return type(ns) == "table" and ns[name] or nil
end

-- Whether the player or the pet put this aura on (a target's debuff is logged only then).
local function fromMe(aura)
    if Secrets.PlainTruth(aura.isFromPlayerOrPlayerPet) then return true end
    local src = Secrets.PlainString(aura.sourceUnit)
    return src == "player" or src == "pet"
end

-- An aura's instance and map value (its spell ID, negated for a debuff), or nil and why (a DROP key)
-- when anything is sealed, when it is a buff on the target, or when it is a target's debuff someone
-- else put on ("source" when who put it on cannot be read plain).
-- `harmful` is the walk's filter; an added aura says it itself (isHarmful, else a plain isHelpful of
-- false).
local function mapped(unit, aura, harmful)
    if Secrets.IsSealed(aura) or not Secrets.CanAccessTable(aura) then return nil, "table" end
    local inst, id = Secrets.PlainNumber(aura.auraInstanceID), Secrets.PlainNumber(aura.spellId)
    if not inst then return nil, "inst" end
    if not id then return nil, "spell" end
    if harmful == nil then
        harmful = Secrets.PlainTruth(aura.isHarmful) or Secrets.PlainEquals(aura.isHelpful, false)
    end
    if unit == "target" and not harmful then return nil, "buff" end
    if unit == "target" and not fromMe(aura) then
        local sealed = Secrets.IsSealed(aura.isFromPlayerOrPlayerPet) or Secrets.IsSealed(aura.sourceUnit)
        return nil, sealed and "source" or "other"
    end
    return inst, harmful and -id or id
end

-- The filters each unit's walk reads: the target's buffs are no line, so its walk reads HARMFUL alone.
local FILTERS = { player = { "HELPFUL", "HARMFUL" }, target = { "HARMFUL" } }

local function clear(map)
    for key in pairs(map) do map[key] = nil end
end

-- Whether a walked aura can be read whole: its table, its instance and its spell ID all plain. One
-- that cannot is skipped and makes the walk incomplete (its absence from the map would read as a
-- loss). A target's aura the player and the pet plainly did not put on is never mapped, so it cannot
-- make the walk incomplete either.
local function readable(unit, aura)
    if Secrets.IsSealed(aura) or not Secrets.CanAccessTable(aura) then return false end
    if unit == "target" and not fromMe(aura) then return true end
    return not Secrets.IsSealed(aura.auraInstanceID) and not Secrets.IsSealed(aura.spellId)
end

-- One filter of the unit walked into `map`, each new instance noted in walk order. Answers whether the
-- walk ran to the list's end (GetAuraDataByIndex answering nil) before AURA_LIMIT with every aura read.
-- A raise (WoW Forever's sealed read, docs/forever-quirks.md) or an unreadable aura is skipped and the
-- walk goes on, incomplete: every aura it can read is still mapped (a silent walk's map is whole but
-- for the skipped ones).
local function walkFilter(unit, map, get, filter)
    local harmful, complete = filter == "HARMFUL", true
    for i = 1, CombatLog.AURA_LIMIT do
        local ok, aura = pcall(get, unit, i, filter)
        if not ok or (aura ~= nil and not readable(unit, aura)) then
            bump(ok and "walkUnreadable" or "walkRaised")
            complete = false
        elseif aura == nil then
            return complete
        else
            local inst, v = mapped(unit, aura, harmful)
            if inst and map[inst] == nil then
                map[inst] = v
                orderN = orderN + 1
                order[orderN] = inst
            end
        end
    end
    return false
end

-- The target's GUID now, plain, or nil (no target, or a sealed GUID: never compared).
local function targetGUID()
    if type(UnitGUID) ~= "function" then return nil end
    local ok, g = pcall(UnitGUID, "target")
    return ok and Secrets.PlainString(g) or nil
end

-- The unit's auras now into `map` (emptied first), every filter walked. Answers whether every filter's
-- walk was complete.
local function walkInto(unit, map)
    clear(map)
    orderN = 0
    if unit == "target" then targetOf = targetGUID() end
    local get = api("GetAuraDataByIndex")
    if type(get) ~= "function" then return false end
    local complete = true
    for _, filter in ipairs(FILTERS[unit]) do
        if not walkFilter(unit, map, get, filter) then complete = false end
    end
    bump(complete and "walkComplete" or "walkIncomplete")
    return complete
end

-- The unit's auras now, into its current map, without a line: the capture's registration and a
-- target change (a new target is not a burst of gains).
local function walk(unit)
    walkInto(unit, auras[unit])
end

-- The diff's gains: each instance of the new map the current one lacks, in walk order.
local function diffGains(unit, cur, new, at)
    local u = U[unit]
    for i = 1, orderN do
        local inst = order[i]
        if cur[inst] == nil then
            local v = new[inst]
            append(at, v < 0 and K.DEBUFF_ON or K.BUFF_ON, u, v < 0 and -v or v, nil)
        end
    end
end

-- The diff's losses: each instance of the current map the new one lacks, by ascending instance.
local function diffFades(unit, cur, new, at)
    local n = 0
    for inst in pairs(cur) do
        if new[inst] == nil then
            n = n + 1
            fades[n] = inst
        end
    end
    for i = #fades, n + 1, -1 do fades[i] = nil end
    if n == 0 then return end
    table.sort(fades)
    local u = U[unit]
    for i = 1, n do
        local v = cur[fades[i]]
        append(at, v < 0 and K.DEBUFF_OFF or K.BUFF_OFF, u, v < 0 and -v or v, nil)
    end
end

-- A full update, or UNIT_AURA with no usable update info: the unit walked into its scratch map and
-- compared with the current one, then the two swapped (never reallocated). An incomplete walk draws
-- no line: its entries join the current map, which keeps the rest. The target is diffed only when its
-- plain GUID is the one its map was walked for; else (a new target whose PLAYER_TARGET_CHANGED has not
-- come yet, or a GUID that cannot be read plain) it is walked silently.
local function diff(unit, at)
    if unit == "target" then
        local g = targetGUID()
        if g == nil or g ~= targetOf then return walk(unit) end
    end
    local cur, new = auras[unit], spare[unit]
    if not walkInto(unit, new) then
        for inst, v in pairs(new) do cur[inst] = v end
        clear(new)
        return
    end
    diffGains(unit, cur, new, at)
    diffFades(unit, cur, new, at)
    auras[unit], spare[unit] = new, cur
    clear(cur)
end

local function added(unit, list, at)
    if not Secrets.CanAccessTable(list) then return end
    local map, u = auras[unit], U[unit]
    for i = 1, LIST_LIMIT do
        local aura = list[i]
        if aura == nil then break end
        bump("gainSeen")
        local inst, v = mapped(unit, aura)
        if not inst then bump(DROP[v]) end
        if inst and map[inst] == nil then
            map[inst] = v
            append(at, v < 0 and K.DEBUFF_ON or K.BUFF_ON, u, v < 0 and -v or v, nil)
        end
    end
end

local function removed(unit, list, at)
    if not Secrets.CanAccessTable(list) then return end
    local map, u = auras[unit], U[unit]
    for i = 1, LIST_LIMIT do
        local raw = list[i]
        if raw == nil then break end
        bump("lossSeen")
        local inst = Secrets.PlainNumber(raw)
        local v = inst and map[inst]
        if not v then bump(inst and "lossUnknown" or "lossSealed") end
        if v then
            map[inst] = nil
            append(at, v < 0 and K.DEBUFF_OFF or K.BUFF_OFF, u, v < 0 and -v or v, nil)
        end
    end
end

-- Whether a list in the update info is there but cannot be read.
local function unreadable(list)
    if list == nil then return false end
    return Secrets.IsSealed(list) or not Secrets.CanAccessTable(list)
end

-- UNIT_AURA's update info named, for the tally and the diff alike (one read per event): none, sealed
-- (the table or a list), a full update (a sealed isFullUpdate is taken as one), or usable info. Anything
-- but usable info leaves the unit to be diffed.
local function shapeOf(info)
    if info == nil then return "none" end
    if Secrets.IsSealed(info) or not Secrets.CanAccessTable(info) then return "sealedInfo" end
    local full = info.isFullUpdate
    if Secrets.IsSealed(full) or Secrets.PlainTruth(full) then return "full" end
    if unreadable(info.addedAuras) or unreadable(info.removedAuraInstanceIDs) then return "sealedInfo" end
    return "info"
end

--- UNIT_AURA for `player` or `target`: its added auras are gains, its removed instances losses
--- (`updatedAuraInstanceIDs`, a refresh, is no line). A full update or no usable update info diffs the
--- unit while the capture is registered (else walks it silently).
function CombatLog.OnAura(unit, info, at)
    if unit ~= "player" and unit ~= "target" then return end
    bump(unit == "player" and "evPlayer" or "evTarget")
    local shape = shapeOf(info)
    bump(shape)
    if shape ~= "info" then
        if registered then return diff(unit, at) end
        return walk(unit)
    end
    added(unit, info.addedAuras, at)
    removed(unit, info.removedAuraInstanceIDs, at)
end

-- ── the events ──────────────────────────────────────────────────────────────────────────────────

-- Each handler takes `at` (GetTime()) first, then the event's own arguments.
local HANDLERS = {
    UNIT_AURA = function(at, unit, info) CombatLog.OnAura(Secrets.PlainString(unit), info, at) end,
    PLAYER_DEAD = function(at) append(at, K.DIES, U.player, nil, nil) end,
    PLAYER_TARGET_CHANGED = function()
        curTarget = noteTarget()
        walk("target")
    end,
}

local function onEvent(_, event, ...)
    local t0 = Perf.on and debugprofilestop()
    local handler = HANDLERS[event]
    if handler then handler(GetTime(), ...) end
    if t0 then Perf.Note("combatLog", debugprofilestop() - t0) end
end

-- What is registered, and on which units. Never UNIT_COMBAT, never COMBAT_LOG_EVENT_UNFILTERED.
local UNIT_EVENTS = { { "UNIT_AURA", "player", "target" } }
local EVENTS = { "PLAYER_DEAD", "PLAYER_TARGET_CHANGED" }

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
    for key in pairs(tally) do tally[key] = 0 end
    curTarget = noteTarget()
    walk("player")
    walk("target")
end

local function clearMaps()
    for _, unit in ipairs({ "player", "target" }) do
        clear(auras[unit])
        clear(spare[unit])
    end
    targetOf = nil
end

--- Make the registrations match: the events while a fight's capture is open, else none.
function CombatLog.Sync()
    local want = wanted()
    if want == registered then return end
    if want then return register() end
    if frame then frame:UnregisterAllEvents() end
    registered, curTarget = false, nil
    clearMaps()
end

--- What the capture registers and what the client refused (`/ct diagnostics`' fight section line).
--- @return table  { registered = boolean, refused = { event, ... } (sorted), lines = number, auras = { [counter]
---                = number } (the aura tally since the last registration, CombatLog.TALLY's keys) }
function CombatLog.Diagnose()
    local out = {}
    for event in pairs(refused) do out[#out + 1] = event end
    table.sort(out)
    local counts = {}
    for key, n in pairs(tally) do counts[key] = n end
    return { registered = registered, refused = out, lines = seq, auras = counts }
end

--- The event frame (nil until a fight first opened one), for the suites and the perf runner.
function CombatLog.EventFrame()
    return frame
end

-- ── a fight's capture ───────────────────────────────────────────────────────────────────────────

local function setting(path)
    return NS.GetSetting and NS.GetSetting("sequence." .. path)
end

-- The lines a fight keeps: the setting, whole and inside its range.
local function linesKept()
    local v = Secrets.PlainNumber(setting("store.lines")) or C.MAX_PER_FIGHT
    return math.max(C.MIN_PER_FIGHT, math.min(C.MAX_LINES, math.floor(v)))
end

local function categories()
    local out = {}
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

-- The pre-pull lines still in the (real) ring, kept and counted toward the new capture, oldest first.
local function countPrepull(cap)
    local oldest = seq + 1
    for n = seq, math.max(1, seq - C.RING + 1), -1 do
        local e = lineOf(ring, seq, n)
        if not e or e.at < cap.from then break end
        oldest = n
    end
    for n = oldest, seq do
        local e = lineOf(ring, seq, n)
        if e and savedBy(cap, e) then
            if cap.store then keep(cap, e) end
            cap.n = cap.n + 1
        end
    end
end

--- A fight started at `startT` (GetTime()): its lines are held from the pre-pull on, and the events
--- registered. Nothing happens while `sequence.enabled` is off.
--- @param fightID string
--- @param startT number
--- @param fight table|nil  the fight table, read again at the end for when it stopped
function CombatLog.Begin(fightID, startT, fight)
    if type(fightID) ~= "string" or type(startT) ~= "number" or setting("enabled") == false then return end
    local prepull = NS.Casts and NS.Casts.PREPULL or 0
    local cap = { fight = fight or { startT = startT }, startT = startT,
                  from = math.max(startT - prepull, floorAt()), store = setting("store.enabled") ~= false,
                  lines = linesKept(), cats = categories(), n = 0, keep = {}, head = 0 }
    countPrepull(cap)
    captures[fightID] = cap
    if viewStart == nil or startT >= viewStart then viewStart, viewFrom = startT, cap.from end
    CombatLog.Sync()
end

local function tenth(x)
    return math.floor(x * 10 + 0.5) / 10
end

-- A saved line out of a kept line; `g` re-indexed into the fight's own target list.
local function saved(e, startT, g)
    return { t = tenth(e.at - startT), k = e.k, id = e.id, u = e.u, f = e.f, g = g }
end

-- A kept line's session target (`g`) in the fight's own list `out`, by `map` [session g] = fight g.
local function ownTarget(g, map, out)
    if not g or not targets[g] then return nil end
    if not map[g] then
        local t = targets[g]
        out[#out + 1] = { name = t.name, friendly = t.friendly }
        map[g] = #out
    end
    return map[g]
end

-- The capture's kept lines up to `to`, oldest first (at most its `lines`, the newest), how many lines
-- of saved categories were not kept, and the fight's target list its lines index.
local function listOf(cap, to)
    local total = math.min(cap.head, cap.lines)
    local log, kept, over, own, map = {}, 0, 0, {}, {}
    for i = cap.head - total + 1, cap.head do
        local e = cap.keep[(i - 1) % cap.lines + 1]
        if e.at <= to then
            log[#log + 1] = saved(e, cap.startT, ownTarget(e.g, map, own))
            kept = kept + 1
        else
            over = over + 1
        end
    end
    return log, math.max(0, cap.n - over - kept), own
end

local function close(fightID)
    local cap = captures[fightID]
    if not cap then return nil end
    captures[fightID] = nil
    local to = endOf(cap.fight) or GetTime()
    if to > lastEnd then lastEnd = to end
    CombatLog.Sync()
    if not cap.store then return { dropped = 0 } end
    local log, dropped, own = listOf(cap, to)
    debug("fight %s: %d line(s) kept, %d dropped", fightID, #log, dropped)
    return { log = log, dropped = dropped, targets = own }
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

--- The fight's saved log, how many lines were dropped and the fight's target list (what its lines'
--- `g` index); nil when it has none (saving off, lost, never begun, or taken already). Answers once.
--- @return table|nil log, number|nil dropped, table|nil targets
function CombatLog.Finish(fightID)
    local done = unpark(fightID) or close(fightID)
    if not done or not done.log then return nil end
    return done.log, done.dropped, done.targets
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

--- The fight a live view shows (modules/Hud_Log.lua, plan item CL-11b): the newest capture begun this
--- session, open or closed, as its start and the first moment its lines are held from (its pre-pull
--- floor), both GetTime() seconds. A view draws the ring's lines from `from` on, timed from `startT`.
--- So THE LIVE VIEW RESETS AT EACH PULL (owner feedback item 5): FIGHT_STARTED moves the window to the
--- new fight, whose floor is Casts.PREPULL seconds before it and never before the last fight's end,
--- and no line of an earlier fight is drawn; lines that arrive after the combat ends still show,
--- until the next pull moves it again. nil before any fight, and after a stand-down.
--- @return number|nil startT, number|nil from
function CombatLog.Window()
    if sample then return sample.startT, sample.from end
    return viewStart, viewFrom
end

-- ── the sample seam (R4-CT-01) ──────────────────────────────────────────────────────────────────

local function swapped()
    for _, fn in pairs(watchers) do fn() end
end

--- A live view's hook, `fn()` on each swap of the sample seam (it starts its feed over). One per `key`.
function CombatLog.Watch(key, fn)
    watchers[key] = type(fn) == "function" and fn or nil
end

--- The views read a fresh, empty sample ring, its fight started at `startT` (GetTime()), its lines'
--- `g` indexing `targetList` ({ { name?, friendly? }, ... }). A sample already up is replaced.
function CombatLog.UseSample(startT, targetList)
    if type(startT) ~= "number" then return end
    sample = { ring = {}, seq = 0, startT = startT, from = startT,
               targets = type(targetList) == "table" and targetList or {} }
    swapped()
end

--- One line into the sample ring (none while the seam is down): `at` GetTime(), then the line's kind,
--- unit, spell, marks and target as a ring line carries them. Answers whether it was added.
--- @return boolean
function CombatLog.SampleAppend(at, k, u, id, f, g)
    if not sample or type(at) ~= "number" then return false end
    local s = sample
    s.seq = s.seq + 1
    local slot = (s.seq - 1) % C.RING + 1
    local e = s.ring[slot]
    if e then
        e.n, e.at, e.k, e.u, e.id, e.f, e.g = s.seq, at, k, u, id, f, g
    else
        s.ring[slot] = { n = s.seq, at = at, k = k, u = u, id = id, f = f, g = g }
    end
    return true
end

--- The sample ring dropped: the views read the real ring again.
function CombatLog.EndSample()
    if not sample then return end
    sample = nil
    swapped()
end

--- Whether the sample seam is up.
--- @return boolean
function CombatLog.SampleActive()
    return sample ~= nil
end

-- ── a stored fight's log ────────────────────────────────────────────────────────────────────────

--- A stored record's log, or nil (a fight saved before CT_SCHEMA 6, or with saving off), how many
--- lines it dropped (0 when none were) and its target list (nil when it has none).
--- @param record table|nil
--- @return table|nil log, number dropped, table|nil targets
function CombatLog.Of(record)
    local log = type(record) == "table" and record.log or nil
    if type(log) ~= "table" then return nil, 0, nil end
    local own = type(record.logTargets) == "table" and record.logTargets or nil
    return log, Secrets.PlainNumber(record.logDropped) or 0, own
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
    targets, targetAt, curTarget = {}, {}, nil
    viewStart, viewFrom = nil, nil
    if frame then frame:UnregisterAllEvents() end
    registered = false
    clearMaps()
    CombatLog.EndSample()
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
