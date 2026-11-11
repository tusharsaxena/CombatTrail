local _, NS = ...
-- modules/Meter.lua — the ONLY file that names C_DamageMeter (plan Task 2.1, spec §3 and §5):
-- availability, the session list and which session a fight binds to, the live read of the player's
-- and the pet's sources (opaque), the after-combat read of one session (plain, player and pet merged)
-- and the session's enemies. Ported from DPS Race @045f479 (modules/Meter.lua) and rewritten for two
-- sources: DPS Race read the player alone and scored a race; Combat Trail reads the pet beside them
-- and records a fight.
--
-- Two reads, two contracts:
--   * ReadFinal(id) is the RECORD path. It runs after combat, converts every value through
--     NS.Secrets.PlainNumber and refuses the whole read ("sealed") if a single one is still secret:
--     a half-plain record would store a partial number. Only then are spells sorted and player and
--     pet summed.
--   * ReadLive(id) is the DISPLAY path. It runs in combat, when every number is secret, and therefore
--     does nothing to a value but copy it into a table (and ask `== nil` of it, for the live-DPS
--     rungs). No arithmetic, no comparison, no `#` on a client table, no sort: Blizzard's order is
--     kept, and the player and the pet stay two sources (the HUD can't sum them, spec §6).
--
-- THE PET (spec §6 and §12). The meter answers the pet as a source of its own, asked for by the pet's
-- GUID. ResolvePet() is that GUID while a pet exists (passed to the client as it comes, even opaque),
-- and remembers the last PLAIN one, so the after-combat read still finds the pet that fought after it
-- was dismissed. PET_SEPARATE is the seam for a client that folds the pet into its owner: false, and
-- ReadFinal reads no pet source and moves the player's rows that are the pet's to a pet part instead
-- (ReadFinal also does this whenever the pet's own source comes back empty, as on WoW Forever): a row
-- the meter names a creature on (creatureName, the pet's melee included), else a spell the cast set
-- NS.Casts.PetSpellSet() names. ReadLive flags the named rows for the breakdown. A pet read that raises
-- costs only the pet: the record keeps the player's part with no pet part, while a SEALED pet read
-- still seals the whole read, so the settle tries again.
--
-- WHICH SESSION. SessionAfter(t) is the session that appeared at or after time t (a fight's combat
-- entry, spec §5). The client gives a session no timestamp, so this file stamps each ID with GetTime()
-- the first time it reads the list; Prime() reads it once as the BASELINE (every ID held then counts
-- as older than any t). core/CombatTrail.lua's NS.RegisterGameEvents primes it on enable and on every
-- stand-up, and the stand-down forgets the stamps (this module is in core/LifecycleSetup.lua's
-- MODULES), so a session made while the addon was down is never mistaken for a new one. A /reload in
-- combat primes with that combat's session already held: the fight is not picked up (Review Focus 4).
--
-- Every client call is pcall'd (Meter.Call): a client that raises on an ID it no longer holds costs a
-- read, never a Lua error on the fight path. Globals are read bare at CALL time so the harness's
-- scripted meter (tests/mock_meter.lua) and a client that loses the namespace both reach the guards.
-- modules/Probe.lua reaches the client through Meter.Call and Meter.Api too.
--
-- Registers no event: modules/Fight.lua calls it, on modules/Watchers.lua's events.

local Meter = {}
NS.Meter = Meter

local Secrets = NS.Secrets
local Perf = NS.Perf

-- Resolved once at load: the enums do not change mid-session. The literals are the documented values,
-- for a client that ships the namespace without the enum; the enemy view has no documented literal,
-- so without the enum it is not read at all.
local ENUM = Enum
local METER_TYPE = ENUM and ENUM.DamageMeterType
local SESSION_TYPE = ENUM and ENUM.DamageMeterSessionType
Meter.STAT_DAMAGE_DONE = (METER_TYPE and METER_TYPE.DamageDone) or 0
Meter.STAT_DPS = (METER_TYPE and METER_TYPE.Dps) or 1
Meter.STAT_ENEMY_DAMAGE_TAKEN = METER_TYPE and METER_TYPE.EnemyDamageTaken or nil
Meter.SESSION_CURRENT = (SESSION_TYPE and SESSION_TYPE.Current) or 1

--- The pet-split seam (spec §12): true while the meter answers the pet as its own source.
Meter.PET_SEPARATE = true

-- The reason IsAvailable gives when the client has no meter API at all (Blizzard gives none then).
local NO_API_REASON = NS.L["Blizzard's damage meter is not available on this client."]

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Meter", fmt, ...) end
end

-- An error value as text, never handed to tostring while secret.
local function errorText(e)
    if Secrets.IsSealed(e) then return "<secret>" end
    return tostring(e)
end

--- The client's C_DamageMeter table, or nil on a client without it.
--- @return table|nil
function Meter.Api()
    local api = C_DamageMeter
    if type(api) ~= "table" then return nil end
    return api
end

--- Call C_DamageMeter[name](...) safely.
--- @return boolean ok
--- @return any a  the first result; on failure "unavailable" (no API or no such function) or "error"
--- @return any b  the second result; on "error" the client's error value, untouched
function Meter.Call(name, ...)
    local api = Meter.Api()
    local fn = api and api[name]
    if type(fn) ~= "function" then return false, "unavailable" end
    local ok, a, b = pcall(fn, ...)
    if not ok then
        debug("%s raised: %s", name, errorText(a))
        return false, "error", a
    end
    return true, a, b
end

-- Meter.Call with the failure folded to one reason string: "unavailable" or "error: <message>".
local function call(name, ...)
    local ok, a, b = Meter.Call(name, ...)
    if ok then return true, a, b end
    if a == "unavailable" then return false, a end
    return false, "error: " .. errorText(b)
end

-- ---------------------------------------------------------------------------
-- Availability and the session list
-- ---------------------------------------------------------------------------

--- Whether the built-in meter is usable. The reason is Blizzard's own, verbatim.
--- @return boolean ok, string|nil reason
function Meter.IsAvailable()
    local ok, available, reason = call("IsDamageMeterAvailable")
    if not ok then
        if available == "unavailable" then return false, NO_API_REASON end
        return false, available
    end
    if Secrets.PlainTruth(available) then return true, nil end
    return false, Secrets.PlainString(reason)
end

-- When each session ID was first read: { t, seq }. t = BASELINE for the IDs the priming read found.
local BASELINE = -math.huge
local seen, primed, seq = {}, false, 0

-- Stamp the IDs not seen before. The client lists newest first, so the list is stamped from its end:
-- of two sessions found in one read, the older gets the lower sequence number.
local function stamp(order, now)
    for i = #order, 1, -1 do
        local id = order[i]
        if not seen[id] then
            seq = seq + 1
            seen[id] = { t = primed and now or BASELINE, seq = seq }
        end
    end
end

--- Every session the client still holds, as a set of plain IDs. An ID is plain even in combat; one
--- that is not is skipped rather than keyed on. Each read stamps the IDs it finds first (SessionAfter)
--- and forgets the ones the client dropped. A read that failed (no API, or the client raised) answers
--- an empty set and ok = false, and touches no stamp: modules/Fight.lua takes only a SUCCESSFUL read
--- without its session as a meter reset, never a transient error.
--- @return table<number, boolean> ids
--- @return boolean ok
function Meter.SessionIDs()
    local out, order = {}, {}
    local ok, list = call("GetAvailableCombatSessions")
    if not ok then return out, false end
    Secrets.SafeIterate(list, function(_, e)
        if not Secrets.CanAccessTable(e) then return end
        local id = Secrets.PlainNumber(e.sessionID)
        if id and not out[id] then
            out[id] = true
            order[#order + 1] = id
        end
    end)
    stamp(order, GetTime())
    primed = true
    for id in pairs(seen) do
        if not out[id] then seen[id] = nil end
    end
    return out, true
end

--- Whether the client still holds session `id`.
--- @param id number|nil
--- @return boolean
function Meter.HasSession(id)
    if id == nil then return false end
    return Meter.SessionIDs()[id] == true
end

--- Read the session list as the baseline: every session held now is older than any fight to come.
function Meter.Prime()
    seen, primed, seq = {}, false, 0
    Meter.SessionIDs()
end

--- The stand-down (core/LifecycleSetup.lua): forget the stamps; the stand-up primes again.
function Meter.Suspend()
    seen, primed, seq = {}, false, 0
end

local function bySeq(a, b) return seen[a].seq < seen[b].seq end

--- Every session that appeared at or after time `t`, oldest first. Reads the list now, unless the
--- caller hands the set it just read (Meter.SessionIDs), so one look answers both questions.
--- @param t number  a GetTime() value
--- @param ids table<number, boolean>|nil  a set from Meter.SessionIDs
--- @return number[] sessionIDs
function Meter.SessionsAfter(t, ids)
    ids = ids or Meter.SessionIDs()
    local out = {}
    for id in pairs(ids) do
        local s = seen[id]
        if s and s.t >= t then out[#out + 1] = id end
    end
    table.sort(out, bySeq)
    return out
end

--- The first session that appeared at or after time `t`, or nil. Reads the list now.
--- @param t number  a GetTime() value
--- @return number|nil sessionID
function Meter.SessionAfter(t)
    return Meter.SessionsAfter(t)[1]
end

-- ---------------------------------------------------------------------------
-- The pet
-- ---------------------------------------------------------------------------

local lastPet   -- the last PLAIN pet GUID ResolvePet saw
local shared    -- Meter.ShareLive's one-dispatch read: { at = GetTime(), id, live } while open

--- The pet's GUID while a pet exists, else nil. In combat the GUID may be opaque: it is only ever
--- handed back to the client. The last plain one is kept for LastPet.
--- @return any guid
function Meter.ResolvePet()
    if not Secrets.PlainTruth(UnitExists("pet")) then return nil end
    local guid = UnitGUID("pet")
    local plainGUID = Secrets.PlainString(guid)
    if plainGUID then lastPet = plainGUID end
    return guid
end

--- The last plain pet GUID seen (the pet that fought, after it was dismissed), or nil.
--- @return string|nil
function Meter.LastPet()
    return lastPet
end

-- ---------------------------------------------------------------------------
-- The record path: one session by ID, after combat
-- ---------------------------------------------------------------------------

-- A read in progress: `sealed` latches the moment any present value is still secret.
local function plain(acc, v)
    if Secrets.IsSealed(v) then
        acc.sealed = true
        return nil
    end
    return Secrets.PlainNumber(v)
end

-- The player's own row in the session's sources: the local-player flag, else the GUID.
local function playerRow(session, guid)
    local row
    Secrets.SafeIterate(session.combatSources, function(_, src)
        if not Secrets.CanAccessTable(src) then return end
        if Secrets.PlainTruth(src.isLocalPlayer) or Secrets.PlainEquals(src.sourceGUID, guid) then
            row = src
            return false
        end
    end)
    return row
end

local function byTotal(a, b)
    if a.total ~= b.total then return a.total > b.total end
    if a.spellID ~= b.spellID then return a.spellID < b.spellID end
    return (b.isPet and not a.isPet) and true or false
end

-- One source's spells as plain { spellID, total, dps }, in the client's order.
local function readSpells(acc, source)
    local spells = {}
    if not Secrets.CanAccessTable(source) then return spells end
    Secrets.SafeIterate(source.combatSpells, function(_, e)
        if not Secrets.CanAccessTable(e) then
            acc.sealed = true
            return false
        end
        local id, dmg, dps = plain(acc, e.spellID), plain(acc, e.totalAmount), plain(acc, e.amountPerSecond)
        -- A secret creature name would credit a pet row to the owner: the read waits for it too.
        if Secrets.IsSealed(e.creatureName) then acc.sealed = true end
        if id then
            spells[#spells + 1] = { spellID = id, total = dmg or 0, dps = dps,
                                    creature = Secrets.NamesCreature(e.creatureName) }
        end
    end)
    return spells
end

-- One source by ID: ok plus the table (nil when the client holds none), or false plus the reason.
local function sourceByID(id, guid)
    local ok, src = call("GetCombatSessionSourceFromID", id, Meter.STAT_DAMAGE_DONE, guid, nil)
    if not ok then return false, src end
    if src ~= nil and not Secrets.CanAccessTable(src) then return false, "sealed" end
    return true, src
end

local function sessionByID(id)
    local ok, session = call("GetCombatSessionFromID", id, Meter.STAT_DAMAGE_DONE)
    if not ok then return nil, session end
    if session == nil then return nil, "missing" end
    if not Secrets.CanAccessTable(session) then return nil, "sealed" end
    return session, nil
end

-- A source's rate: the meter's own, else its total over the session's duration.
local function rateOf(total, meterRate, duration)
    if meterRate then return meterRate end
    if duration > 0 then return total / duration end
    return 0
end

-- The player's part: { total, meterRate, spells } from their row (else their source).
local function readPlayer(acc, session, source, guid)
    local row = playerRow(session, guid)
    local total = row and plain(acc, row.totalAmount)
    local meterRate = row and plain(acc, row.amountPerSecond)
    if total == nil and source ~= nil then total = plain(acc, source.totalAmount) end
    if meterRate == nil and source ~= nil then meterRate = plain(acc, source.amountPerSecond) end
    return { total = total or 0, meterRate = meterRate, spells = readSpells(acc, source) }
end

-- The pet's own source: { total, meterRate, spells }, or nil when it dealt nothing or its read raised
-- (the player's part stands; only a sealed pet read seals the whole read).
local function readPetSource(acc, id, petGUID)
    if petGUID == nil then return nil end
    local ok, src = sourceByID(id, petGUID)
    if not ok then
        if src == "sealed" then acc.sealed = true else debug("pet source of session %s: %s", id, src) end
        return nil
    end
    if src == nil then return nil end
    local part = { total = plain(acc, src.totalAmount) or 0, meterRate = plain(acc, src.amountPerSecond),
                   spells = readSpells(acc, src) }
    if part.total == 0 and #part.spells == 0 then return nil end
    return part
end

local AUTO_ATTACK = 6603

-- Whether a folded row is the pet's: the meter names a creature on it (its own mark, Auto Attack
-- included: the pet's melee is a row of its own), else the cast set names its spell. By the cast set
-- alone Auto Attack stays the owner's, since the set cannot tell whose melee it is.
local function petsRow(sp, set)
    if sp.creature then return true, "name" end
    if set and set[sp.spellID] and sp.spellID ~= AUTO_ATTACK then return true, "casts" end
    return false
end

-- No pet source (PET_SEPARATE = false, or an empty one): move the player's rows that are the pet's
-- (petsRow) to a pet part.
local function splitFolded(player)
    local set = NS.Casts and NS.Casts.PetSpellSet and NS.Casts.PetSpellSet()
    if type(set) ~= "table" then set = nil end
    local mine, theirs, petTotal, by = {}, {}, 0, { name = 0, casts = 0 }
    for _, sp in ipairs(player.spells) do
        local pets, why = petsRow(sp, set)
        if pets then
            theirs[#theirs + 1] = sp
            petTotal = petTotal + sp.total
            by[why] = by[why] + 1
        else
            mine[#mine + 1] = sp
        end
    end
    debug("folded split: %d player row(s), %d pet row(s) (%d by creature name, %d by cast set)",
        #mine, #theirs, by.name, by.casts)
    if #theirs == 0 then return nil end
    player.spells = mine
    player.total = math.max(0, player.total - petTotal)
    player.meterRate = nil         -- the meter's rate covered both; each part is total / duration now
    return { total = petTotal, spells = theirs }
end

-- A part as the result shapes it: plain totals, its rate, its spells by damage.
local function finish(part, duration)
    if not part then return nil end
    table.sort(part.spells, byTotal)
    return { total = part.total, dps = rateOf(part.total, part.meterRate, duration), spells = part.spells }
end

local function merge(player, pet)
    local spells = {}
    for _, sp in ipairs(player.spells) do spells[#spells + 1] = { spellID = sp.spellID, total = sp.total, isPet = false } end
    if pet then
        for _, sp in ipairs(pet.spells) do spells[#spells + 1] = { spellID = sp.spellID, total = sp.total, isPet = true } end
    end
    table.sort(spells, byTotal)
    return { total = player.total + (pet and pet.total or 0), dps = player.dps + (pet and pet.dps or 0),
             spells = spells }
end

-- Whether the caller asked for no pet at all (false). A caller's GUID may be opaque: the secret test
-- runs first, so it is never compared with false (client-quirks-§2).
local function noPet(petGUID)
    if petGUID == nil or Secrets.IsSealed(petGUID) then return false end
    return petGUID == false
end

-- Which pet GUID the record read asks for: the caller's, none (false), or the pet now / the last one.
-- Only nil tests touch a GUID that may be opaque: `ResolvePet() or lastPet` would be a boolean test.
local function petFor(petGUID)
    if not Meter.PET_SEPARATE or noPet(petGUID) then return nil end
    if petGUID ~= nil then return petGUID end
    local now = Meter.ResolvePet()
    if now ~= nil then return now end
    return lastPet
end

--- Read session `id` after combat. Every value in the result is a plain number. Spells are sorted by
--- damage, highest first; `merged` sums player and pet and marks the pet's spells. `dps` is the
--- meter's own rate where it gave one, else the total over the session's duration.
--- @param id number
--- @param petGUID string|false|nil  the pet to read (nil: the pet now, else the last one; false: none)
--- @return table|nil result  { duration, player = {total, dps, spells}, pet = {…}|nil,
---                              merged = { total, dps, spells = { {spellID, total, isPet}, ... } } }
--- @return string|nil err    "missing" | "sealed" | "unavailable" | "error: <message>"
function Meter.ReadFinal(id, petGUID)
    if id == nil then return nil, "missing" end
    local session, err = sessionByID(id)
    if err then return nil, err end
    local guid = UnitGUID("player")
    local okSrc, source = sourceByID(id, guid)
    if not okSrc then return nil, source end

    local acc = { sealed = false }
    local duration = plain(acc, session.durationSeconds) or 0
    local player = readPlayer(acc, session, source, guid)
    local pet
    if Meter.PET_SEPARATE then pet = readPetSource(acc, id, petFor(petGUID)) end
    if acc.sealed then return nil, "sealed" end
    -- No pet source of its own (the folding seam, or a client that folds: Forever's probe, 2026-11-10,
    -- showed an empty pet source): tag the pet's spells inside the player's source instead.
    if pet == nil and not noPet(petGUID) then pet = splitFolded(player) end

    local p, q = finish(player, duration), finish(pet, duration)
    return { duration = duration, player = p, pet = q, merged = merge(p, q) }
end

-- ---------------------------------------------------------------------------
-- The enemies: who took the damage, after combat
-- ---------------------------------------------------------------------------

local function byTaken(a, b)
    if a.total ~= b.total then return a.total > b.total end
    return (a.name or "") < (b.name or "")
end

local function readEnemy(acc, e)
    if not Secrets.CanAccessTable(e) then
        acc.sealed = true
        return nil
    end
    if Secrets.IsSealed(e.name) then acc.sealed = true end
    local creatureID = e.sourceCreatureID
    if creatureID == nil then creatureID = e.creatureID end
    local enemy = { name = Secrets.PlainString(e.name), creatureID = plain(acc, creatureID),
                    total = plain(acc, e.totalAmount) or 0 }
    return enemy
end

--- The enemies of session `id` by damage taken, highest first, as plain values. Empty with a reason
--- while sealed, missing or unreadable.
--- @param id number
--- @return table enemies  { {name, creatureID, total}, ... }
--- @return string|nil err
function Meter.ReadEnemies(id)
    local out = {}
    if id == nil then return out, "missing" end
    if Meter.STAT_ENEMY_DAMAGE_TAKEN == nil then return out, "unavailable" end
    local ok, session = call("GetCombatSessionFromID", id, Meter.STAT_ENEMY_DAMAGE_TAKEN)
    if not ok then return out, session end
    if session == nil then return out, "missing" end
    if not Secrets.CanAccessTable(session) then return out, "sealed" end
    local acc = { sealed = false }
    Secrets.SafeIterate(session.combatSources, function(_, e)
        local enemy = readEnemy(acc, e)
        if acc.sealed then return false end
        out[#out + 1] = enemy
    end)
    if acc.sealed then return {}, "sealed" end
    table.sort(out, byTaken)
    return out
end

-- ---------------------------------------------------------------------------
-- The display path: live, opaque
-- ---------------------------------------------------------------------------

-- THE PLAYER'S LIVE DPS FIGURE, a rung chain (DPS Race's). The live client's source table may carry
-- no amountPerSecond (DPS Race's smoke test, 2026-10-23), so the figure falls through, each rung an
-- opaque copy:
--   a) "source"    the source table's own amountPerSecond;
--   b) "localRow"  the session's combatSources row whose isLocalPlayer is plainly true, its rate;
--   c) "dpsType"   the Dps meter type's source for the player: its amountPerSecond only (its
--                  totalAmount is never taken for a rate: a dash beats a confident wrong number).
-- damage / elapsed is never computed: arithmetic on a secret. The rung that served is logged once per
-- fight (NewLiveFight resets it) and tried first on the next read. The pet's figure is its source's
-- own amountPerSecond, or nil.
local loggedRung, servedRung
local liveID   -- the session the current read is of (nil: the Current session)

-- Session `liveID` (or the Current one) for meter type `stat`.
local function liveSession(stat)
    if liveID ~= nil then return call("GetCombatSessionFromID", liveID, stat) end
    return call("GetCombatSessionFromType", Meter.SESSION_CURRENT, stat)
end

local function liveSource(stat, guid)
    if liveID ~= nil then return call("GetCombatSessionSourceFromID", liveID, stat, guid, nil) end
    return call("GetCombatSessionSourceFromType", Meter.SESSION_CURRENT, stat, guid, nil)
end

-- localRowDps's iterator, at file scope so no closure is made per read; it writes rowDps.
local rowDps
local function takeLocalRow(_, src)
    if not Secrets.CanAccessTable(src) then return end
    if Secrets.PlainTruth(src.isLocalPlayer) then
        rowDps = src.amountPerSecond
        return false
    end
end

local function localRowDps()
    local ok, session = liveSession(Meter.STAT_DAMAGE_DONE)
    if not ok or not Secrets.CanAccessTable(session) then return nil end
    rowDps = nil
    Secrets.SafeIterate(session.combatSources, takeLocalRow)
    local dps = rowDps
    rowDps = nil
    return dps
end

local function dpsTypeRate()
    local ok, src = liveSource(Meter.STAT_DPS, UnitGUID("player"))
    if not ok or not Secrets.CanAccessTable(src) then return nil end
    return src.amountPerSecond
end

local function sourceDps(source) return source.amountPerSecond end

local RUNGS = { { "source", sourceDps }, { "localRow", localRowDps }, { "dpsType", dpsTypeRate } }
local RUNG_FN = {}
for _, r in ipairs(RUNGS) do RUNG_FN[r[1]] = r[2] end

-- The live DPS figure (opaque) and the rung that served it, or nil, nil.
local function liveDps(source)
    local first = servedRung and RUNG_FN[servedRung]
    if first then
        local dps = first(source)
        if dps ~= nil then return dps, servedRung end
    end
    for _, r in ipairs(RUNGS) do
        if r[1] ~= servedRung then
            local dps = r[2](source)
            if dps ~= nil then
                servedRung = r[1]
                return dps, r[1]
            end
        end
    end
    servedRung = nil
    return nil, nil
end

--- A new fight: the next live read logs the rung that serves it (the fight watchers, on start).
function Meter.NewLiveFight()
    loggedRung, servedRung = nil, nil
end

-- One source's live part, every value copied untouched; nil when the client answers none.
local function livePart(guid)
    if guid == nil then return nil end
    local ok, source = liveSource(Meter.STAT_DAMAGE_DONE, guid)
    if not ok or not Secrets.CanAccessTable(source) then return nil end
    local spells = {}
    Secrets.SafeIterate(source.combatSpells, function(_, e)
        if not Secrets.CanAccessTable(e) then return end
        -- `creature` is plain: whether the meter PLAINLY names a creature on the row (out of combat;
        -- in combat the name is secret and may be the owner's "", so it says nothing). `creatureName`
        -- is the name itself, copied untouched: the breakdown hands it to a FontString, where the
        -- owner's "" draws nothing and the pet's draws its name.
        spells[#spells + 1] = { spellID = e.spellID, total = e.totalAmount, dps = e.amountPerSecond,
                                creature = Secrets.NamesCreature(e.creatureName), creatureName = e.creatureName }
    end)
    return { total = source.totalAmount, dps = source.amountPerSecond, maxAmount = source.maxAmount,
             spells = spells, source = source }
end

local function livePlayer()
    local part = livePart(UnitGUID("player"))
    if not part then return nil end
    local dps, rung = liveDps(part.source)
    part.dps, part.rung, part.source = dps, rung, nil
    local name = rung or "none"
    if name ~= loggedRung then
        loggedRung = name
        debug("live DPS from rung %s", name)
    end
    return part
end

--- Read the player's and the pet's live breakdowns from session `id` (nil: the Current session).
--- Every value is OPAQUE (secret in combat) and only copied; spells keep Blizzard's order. A source
--- the client does not answer (no session, no pet, no API) is nil.
--- @param id number|nil
--- @return table live  { player = {total, dps, rung, maxAmount, spells = { {spellID, total, dps, creature,
---                       creatureName} }}|nil,
---                       pet = {total, dps, maxAmount, spells}|nil }
function Meter.ReadLive(id)
    if shared and shared.at == GetTime() and shared.id == id and shared.live then return shared.live end
    local t0 = Perf.on and debugprofilestop()
    liveID = id
    local player = livePlayer()
    local pet = Meter.PET_SEPARATE and livePart(Meter.ResolvePet()) or nil
    if pet then pet.source = nil end
    -- A pet source with no rows (a plain count of this file's own array) is a folded one: its total
    -- would draw a confident 0 while the pet's damage sits in the owner's rows.
    if pet and #pet.spells == 0 then pet = nil end
    liveID = nil
    if t0 then Perf.Note("meter", debugprofilestop() - t0) end
    -- `petOut`: whether a pet exists (plain), so the breakdown knows to draw the pet's name column.
    local live = { player = player, pet = pet, petOut = Meter.ResolvePet() ~= nil }
    if shared and shared.at == GetTime() then shared.id, shared.live = id, live end
    return live
end

--- Fight's tick brackets FIGHT_TICK's receivers with this (true, then false), so the HUD and the
--- slices share one ReadLive of a session in that dispatch instead of asking the client twice. The
--- share holds only within the frame it was opened in (GetTime()), so a receiver that raised and
--- skipped the close cannot serve a stale read later. Its values stay opaque and are never kept.
--- @param on boolean
function Meter.ShareLive(on)
    shared = on and { at = GetTime() } or nil
end
