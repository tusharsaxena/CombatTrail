local _, NS = ...
-- modules/MockFights.lua — the sample data test mode and the sim draw (spec §7 "Test mode", §8 "Sim
-- mode", plan Task 5.1): a made-up fight history for the Results window (about forty fights across
-- the content kinds, mockup §5), and the made-up fight the HUD and the lanes play. Ported from DPS
-- Race @045f479 (modules/MockRuns.lua) without its race: no length board, no late cast, no status
-- other than a stored fight's "final".
--
-- MADE FRESH, KEPT IN MEMORY, NEVER STORED. Every table here is built on the call, for two made-up
-- hunters on the player's realm. Nothing is written to NS.db: the Results window reads the history
-- through modules/Results_Source.lua's sample seam, the HUD hears the sample fight from
-- modules/Preview.lua and modules/Sim.lua, never from the bus, and no talent loadout is interned
-- (a sample record carries none).
--
-- ONE FIGHT, ONE PLAN. A sample fight is built the way a real one comes about: a PLAN of what
-- happened (its casts and every damage hit, from the client's rotation in modules/MockRotations.lua,
-- with a generator seeded from the fight's id), and everything a window draws is read from that
-- plan: the record's spells, casts, cooldowns and usage, the chart's steps, the HUD's live and final
-- reads, the lanes' icons. The seed makes it repeatable: the same id always plans the same fight.
-- Never math.random here.
--
-- CLIENTS (clients-§4). Each board declares the clients it exists on: Mythic+, delves, arenas and
-- the training dummies (an empty catalog on WoW Forever, defaults/Dummies.lua) are Retail's, so the
-- Forever history holds none of them. The figures are scaled per client, picked once at FILE SCOPE.

local MockFights = {}
NS.MockFights = MockFights

local L = NS.L

-- The first damage lands this long after combat entry (the HUD's clock starts there).
MockFights.FIRST_HIT = 1.0

-- How a plan varies a rotation: a spell's luck over the fight (either way), the drift of its first
-- cast (s) and of its cadence (a fraction), the chance a cast is skipped, the chance one is
-- interrupted (the lanes' mark), the crit chance (a crit doubles the hit), a direct hit's flight
-- time (s), and how far behind the pet's cast follows the player's (Kill Command).
local LUCK, DRIFT_FROM, DRIFT_EVERY, SKIP, INTERRUPT, CRIT, TRAVEL, ECHO = 0.16, 0.25, 0.06, 0.05, 0.02, 0.25, 0.3, 0.1
local HOUR = 3600
local RETAIL = { "retail" }

-- The client's figures (clients-§5): a Retail fight's DPS is in the hundreds of thousands, a
-- Forever one's in the hundreds; the level, the spec and the item levels follow.
local FOREVER = NS.Compat.IsForever()
local CLIENT = FOREVER and {
    scale = 4, level = 60, raid = { 9, "40 Player" },
    stats = { v = 1, stamina = 4100, armor = 3900, critRating = 0, crit = 18.20, hasteRating = 0, haste = 0 },
    -- A sample carries its gear inline, never a set in db.global.gearSets (Loadouts.GearOf reads both).
    gear = { [1] = "16939", [5] = "16942", [7] = "16938", [13] = "19991", [18] = "18855" },
} or {
    scale = 1000, level = 90, raid = { 15, "Heroic" }, specID = 253, specName = "Beast Mastery",
    stats = { v = 1, primaryStat = 2, primary = 41800, stamina = 182000, armor = 24100, critRating = 5120,
              crit = 24.31, hasteRating = 6480, haste = 21.60, masteryRating = 4380, mastery = 42.15,
              versRating = 2310, vers = 7.11 },
    gear = { [1] = "212000", [5] = "212002", [7] = "212004", [13] = "212454", [16] = "212395" },
}
MockFights.SCALE = CLIENT.scale

-- The two made-up hunters: the main one every sample fight of the HUD and the sim is fought by.
local CHARS = {
    me = { name = "Samplehunter", ilvl = FOREVER and 66.2 or 721.4, pet = "Grimfang" },
    alt = { name = "Mockarrow", ilvl = FOREVER and 63.0 or 716.0, pet = "Ashpaw" },
}

-- ── the boards ──────────────────────────────────────────────────────────────────────────────────
-- What a fight was against, as a fight's snapshot and encounter carry it (modules/Identity.lua reads
-- them into the identity, so a sample's board key is a real one's). Names are made up.

local function raid(encounterID, name, creatureID, diff)
    return {
        where = { instanceType = "raid", instanceName = "The Voidspire", instanceID = 2912,
                  difficultyID = diff[1], difficultyName = L[diff[2]] },
        encounter = { id = encounterID, name = name, difficultyID = diff[1] },
        target = { name = name, creatureID = creatureID },
    }
end

local function keystone()
    return { instanceType = "party", instanceName = "Windrunner Spire", instanceID = 2805, difficultyID = 8,
             difficultyName = L["Mythic Keystone"], keystoneLevel = 12 }
end

local function boards()
    local out = {
        vorasius = raid(3176, "Vorasius", 240432, CLIENT.raid),
        averzian = raid(3177, "Imperator Averzian", 240435, CLIENT.raid),
        -- The sim's "first" scenario fights here: no history row names it.
        salhadaar = raid(3179, "Fallen-King Salhadaar", 240437, CLIENT.raid),
        dungeon = {
            where = { instanceType = "party", instanceName = "Murder Row", instanceID = 2813, difficultyID = 1,
                      difficultyName = L["Normal"] },
            encounter = { id = 3101, name = "Gutterlord Vex", difficultyID = 1 },
            target = { name = "Gutterlord Vex", creatureID = 241102 },
        },
        bg = { where = { instanceType = "pvp", instanceName = "Warsong Gulch", instanceID = 489, difficultyID = 0,
                         maxPlayers = 10, pvpBracket = "10" },
               target = { name = "Sampleshaman" } },
        world = { where = { instanceType = "none", instanceName = "Eversong Woods", difficultyID = 0 },
                  target = { name = "Gorehide Alpha", creatureID = 247010 } },
    }
    if not NS.Compat.ForClient(RETAIL) then return out end
    out.vorasiusM = raid(3176, "Vorasius", 240432, { 16, "Mythic" })
    out.gale = { where = keystone(), encounter = { id = 3056, name = "Restless Gale", difficultyID = 8 },
                 target = { name = "Restless Gale", creatureID = 231606 } }
    out.ravager = { where = keystone(), target = { name = "Spire Ravager", creatureID = 245017 } }
    out.delve = { where = { instanceType = "scenario", instanceName = "The Sinkhole", instanceID = 2689,
                            difficultyID = 208, difficultyName = L["Delves"], isDelve = true, delveTier = 8 },
                  target = { name = "Nerubian Overseer", creatureID = 244001 } }
    out.arena = { where = { instanceType = "arena", instanceName = "Nagrand Arena", instanceID = 1505,
                            difficultyID = 0, maxPlayers = 3, pvpBracket = "r3" },
                  target = { name = "Samplerogue" } }
    out.dummy = { where = { instanceType = "none", instanceName = "Silvermoon City", difficultyID = 0 },
                  target = { name = NS.DummyName(31146), creatureID = 31146 } }
    return out
end

--- The board `key` as a fight carries it ({ where, encounter?, target }), or nil when this client
--- has no such board.
function MockFights.Board(key)
    return boards()[key]
end

-- The history: { who, board, ago (hours), len (s), dps (thousands on Retail), chart?, note?,
-- noMajor? (missed its long cooldowns), noPet?, dry? (no potion) }. A board this client lacks is
-- left out of its history.
local HISTORY = {
    { "me", "vorasius", 2, 252, 186.9, chart = true, note = "Sample note: every cooldown in the opener" },
    { "me", "vorasius", 50, 271, 182.9 },
    { "me", "vorasius", 74, 266, 179.4, dry = true },
    { "me", "vorasius", 98, 259, 176.0 },
    { "me", "vorasius", 122, 280, 171.2 },
    { "me", "vorasius", 146, 290, 168.5, noMajor = true },
    { "alt", "vorasius", 30, 248, 168.0 },
    { "me", "vorasiusM", 3, 310, 162.4, chart = true },
    { "me", "vorasiusM", 51, 322, 158.8 },
    { "me", "averzian", 2.2, 338, 172.2, chart = true },
    { "me", "averzian", 50.5, 351, 169.9 },
    { "me", "averzian", 74.3, 344, 166.1 },
    { "alt", "averzian", 31, 360, 155.3 },
    { "alt", "averzian", 160, 372, 149.0 },
    { "me", "gale", 20, 126, 169.0, chart = true },
    { "me", "gale", 44, 131, 165.2 },
    { "alt", "gale", 68, 140, 151.7 },
    { "me", "ravager", 20.2, 48, 238.3 },
    { "me", "ravager", 20.4, 41, 225.0 },
    { "me", "ravager", 44.1, 52, 231.6 },
    { "me", "dungeon", 26, 95, 158.2 },
    { "me", "dungeon", 140, 102, 150.1 },
    { "alt", "dungeon", 92, 99, 147.4 },
    { "me", "delve", 6, 74, 162.0 },
    { "me", "delve", 30, 81, 158.6 },
    { "me", "delve", 54, 69, 160.3, note = "Sample note: tier 8 with the bountiful key" },
    { "me", "bg", 9, 64, 121.4 },
    { "me", "bg", 33, 58, 117.9 },
    { "me", "bg", 105, 71, 124.0 },
    { "me", "arena", 10, 92, 98.2 },
    { "me", "arena", 34, 105, 95.6 },
    { "me", "world", 12, 41, 142.0 },
    { "me", "world", 60, 36, 139.5 },
    { "alt", "world", 84, 44, 131.8 },
    { "me", "dummy", 1, 90, 178.0, chart = true, note = "Sample note: a clean dummy pull" },
    { "me", "dummy", 2.5, 90, 166.2, noPet = true },
    { "me", "dummy", 25, 90, 174.4 },
    { "me", "dummy", 49, 120, 172.9 },
    { "me", "dummy", 145, 60, 169.3 },
    { "alt", "dummy", 26, 90, 160.1 },
}
MockFights.HISTORY = HISTORY

-- ── who ─────────────────────────────────────────────────────────────────────────────────────────

--- A made-up hunter as a record's `who` carries it ("me", the main one, or "alt"), on the player's
--- realm and client.
--- @param key string|nil
--- @return table who
function MockFights.Character(key)
    local c = CHARS[key] or CHARS.me
    local me = NS.Identity.Who()
    return { name = c.name, realm = me.realm, client = NS.Compat.ClientKey(), class = "HUNTER",
             level = CLIENT.level, specID = CLIENT.specID, specName = CLIENT.specName and L[CLIENT.specName],
             ilvl = c.ilvl, petName = c.pet, petFamily = "Wolf" }
end

--- The identity a fight against board `key` resolves to (modules/Identity.lua's own Resolve).
--- @return table|nil identity
function MockFights.Identity(key)
    local b = MockFights.Board(key)
    if not b then return nil end
    return NS.Identity.Resolve({ snapshot = { target = b.target, where = b.where }, encounter = b.encounter })
end

-- ── the plan: one fight ─────────────────────────────────────────────────────────────────────────

-- A repeatable generator for `id` (Park-Miller): 0 <= r() < 1, the same sequence for the same id.
local function seeded(id)
    local MOD, text = 2147483647, tostring(id)
    local state = 7
    for i = 1, #text do state = (state * 31 + text:byte(i)) % MOD end
    state = math.max(1, state)
    local function r()
        state = (state * 16807) % MOD
        return state / MOD
    end
    for _ = 1, 4 do r() end
    return r
end

local function either(r, spread) return (r() * 2 - 1) * spread end
local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

local function rowOn(row, o)
    if row.major and o.noMajor then return false end
    if (row.pet or row.echo) and o.noPet then return false end
    if row.use == "potion" and o.dry then return false end
    return true
end

local function addHit(plan, at, id, size, pet, r)
    if at > plan.length then return end
    local amount = size * (r() < CRIT and 2 or 1)
    plan.hits[#plan.hits + 1] = { t = math.max(MockFights.FIRST_HIT, at), id = id, amount = amount, pet = pet }
end

local function addCast(plan, t, id, pet, cut)
    plan.casts[#plan.casts + 1] = { t = round1(t), spellID = id, unit = pet and "pet" or "player",
                                    interrupted = cut == true }
end

-- One cast's damage: a direct hit after its flight, or its ticks; an echo's lands as the pet's.
local function castHits(plan, row, t, size, r)
    if row.none or not row.hit then return end
    local id, pet = row.id, row.pet == true
    if row.echo then id, pet, t = row.echo, true, t + ECHO end
    if not row.ticks then return addHit(plan, t + TRAVEL, id, size, pet, r) end
    for i = 1, row.ticks do addHit(plan, t + i * row.gap, id, size, pet, r) end
end

-- One cast of `row` at `t`: the lanes' casts, the usage's uses and the damage.
local function castOnce(plan, row, t, size, r)
    if row.passive then return castHits(plan, row, t, size, r) end
    local cut = not row.none and r() < INTERRUPT
    addCast(plan, t, row.id, row.pet, cut)
    if cut then return end
    if row.echo then addCast(plan, t + ECHO, row.echo, true, false) end
    if row.use then plan.uses[#plan.uses + 1] = { row = row, t = round1(t) } end
    castHits(plan, row, t, size, r)
end

-- One rotation row through the fight. Its first cast is never skipped.
local function playRow(plan, row, r)
    local size = (row.hit or 0) * (1 + either(r, LUCK))
    local every = row.every * (1 + either(r, DRIFT_EVERY))
    local t, first = math.max(0, row.from + either(r, DRIFT_FROM)), true
    if not row.passive then plan.cooldowns[row.id] = row.cd or 0 end
    if row.echo then plan.cooldowns[row.echo] = 0 end
    while t < plan.length do
        if first or r() >= SKIP then castOnce(plan, row, t, size, r) end
        first = false
        t = t + every
    end
end

local function byTime(a, b)
    if a.t ~= b.t then return a.t < b.t end
    return a.id < b.id
end

-- The hits scaled to `damage` exactly (the largest takes the rounding), in time order.
local function settle(plan, damage)
    local sum = 0
    for _, h in ipairs(plan.hits) do sum = sum + h.amount end
    if sum <= 0 then return end
    local kept, top = 0, plan.hits[1]
    for _, h in ipairs(plan.hits) do
        h.amount = math.floor(h.amount * damage / sum)
        kept = kept + h.amount
        if h.amount > top.amount then top = h end
    end
    top.amount = top.amount + damage - kept
    table.sort(plan.hits, byTime)
end

--- The plan of one fight: what was cast and every damage hit, `damage` in all over `length` s.
--- @param o table  { id, length, damage, noMajor?, noPet?, dry? }
--- @return table plan  { id, length, casts, cooldowns, hits, uses }
function MockFights.Plan(o)
    local plan = { id = o.id, length = o.length, casts = {}, cooldowns = {}, hits = {}, uses = {} }
    local r = seeded(o.id)
    for _, row in ipairs(NS.MOCK_ROTATION) do
        if rowOn(row, o) then playRow(plan, row, r) end
    end
    settle(plan, math.floor(o.damage))
    table.sort(plan.casts, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.spellID < b.spellID
    end)
    return plan
end

-- ── what the plan's meter holds ─────────────────────────────────────────────────────────────────

local function byTotal(a, b)
    if a.total ~= b.total then return a.total > b.total end
    return a.spellID < b.spellID
end

--- The plan's totals `t` seconds into the fight: the player's, the pet's, and each spell's.
--- @return number player, number pet, table spells  { { spellID, total, isPet } }, highest first
function MockFights.TotalAt(plan, t)
    local player, pet, rows, index = 0, 0, {}, {}
    for _, h in ipairs(plan.hits) do
        if h.t > t then break end
        if h.pet then pet = pet + h.amount else player = player + h.amount end
        local key = (h.pet and "p" or "") .. h.id
        local row = index[key]
        if not row then
            row = { spellID = h.id, total = 0, isPet = h.pet }
            index[key], rows[#rows + 1] = row, row
        end
        row.total = row.total + h.amount
    end
    table.sort(rows, byTotal)
    return player, pet, rows
end

-- One source's part of a read, over `secs` seconds; nil with no spell of its own.
local function part(spells, isPet, total, secs)
    local list, max = {}, 0
    for _, sp in ipairs(spells) do
        if sp.isPet == isPet then
            list[#list + 1] = { spellID = sp.spellID, total = sp.total, dps = sp.total / secs }
            max = math.max(max, sp.total)
        end
    end
    if #list == 0 then return nil end
    return { total = total, dps = total / secs, maxAmount = max, spells = list }
end

--- The live read `t` seconds into the fight, in Meter.ReadLive's shape (plain, where a real one is
--- opaque); a source with no hit yet is nil, as the meter has no row for it.
--- @return table live  { player = {total, dps, rung, maxAmount, spells}|nil, pet = {...}|nil }
function MockFights.LiveAt(plan, t)
    t = math.min(t, plan.length)
    local player, pet, spells = MockFights.TotalAt(plan, t)
    local secs = math.max(1, t)
    local p = part(spells, false, player, secs)
    if p then p.rung = "sample" end
    return { player = p, pet = part(spells, true, pet, secs) }
end

--- The read after combat, in Meter.ReadFinal's shape, over `duration` seconds.
--- @return table final  { duration, player, pet|nil, merged = { total, dps, spells } }
function MockFights.FinalOf(plan, duration)
    local player, pet, spells = MockFights.TotalAt(plan, math.huge)
    local p = part(spells, false, player, duration) or { total = 0, dps = 0, spells = {} }
    local q = part(spells, true, pet, duration)
    local merged = {}
    for i, sp in ipairs(spells) do merged[i] = { spellID = sp.spellID, total = sp.total, isPet = sp.isPet } end
    return { duration = duration, player = p, pet = q,
             merged = { total = player + pet, dps = (player + pet) / duration, spells = merged } }
end

--- The plan's casts by `t` seconds (modules/Casts.lua's list shape) and their base cooldowns.
--- @return table casts, table cooldowns
function MockFights.CastsAt(plan, t)
    local out = {}
    for _, c in ipairs(plan.casts) do
        if c.t > t then break end
        out[#out + 1] = c
    end
    return out, plan.cooldowns
end

--- A chart store for the whole plan (modules/Slices.lua's Seed shape): the running totals at each
--- step's boundary, plain.
--- @return table rec
function MockFights.Slices(plan)
    local step, hits = NS.Slices.STEP, plan.hits
    local values, pet, i, k, player, petTotal = {}, {}, 1, 1, 0, 0
    while NS.Slices.Boundary(k) <= plan.length + 1e-6 do
        local at = NS.Slices.Boundary(k)
        while i <= #hits and hits[i].t <= at do
            local h = hits[i]
            if h.pet then petTotal = petTotal + h.amount else player = player + h.amount end
            i = i + 1
        end
        values[k], pet[k] = player, petTotal
        k = k + 1
    end
    return { step = step, values = values, pet = pet, count = k - 1, filled = k - 1, next = k, open = false }
end

--- Fill fight `fightID`'s open chart store up to `t` seconds, one read per step (test mode's held
--- HUD draws its chart so far).
function MockFights.FillSlices(fightID, plan, t)
    local k = 1
    while NS.Slices.Boundary(k) <= t + 1e-6 do
        local player, pet = MockFights.TotalAt(plan, NS.Slices.Boundary(k))
        NS.Slices.Record(fightID, NS.Slices.Boundary(k), player, pet)
        k = k + 1
    end
end

-- ── the record ──────────────────────────────────────────────────────────────────────────────────

-- What the plan used (modules/Usage.lua's record shape): the trinket and the potion it cast, the
-- food it ate before the pull.
local function usageOf(plan)
    local used, candidates, byItem = {}, {}, {}
    for _, row in ipairs(NS.MOCK_ROTATION) do
        if row.use then candidates[#candidates + 1] = { itemID = row.item, kind = row.use, slot = row.slot } end
    end
    for _, u in ipairs(plan.uses) do
        local e = byItem[u.row.item]
        if not e then
            e = { itemID = u.row.item, kind = u.row.use, slot = u.row.slot, times = {}, n = 0, src = "cast" }
            byItem[u.row.item], used[#used + 1] = e, e
        end
        e.n = e.n + 1
        e.times[#e.times + 1] = u.t
    end
    used[#used + 1] = { kind = "food", n = 1, src = "buff" }
    return { v = NS.Usage.VERSION, used = used, candidates = candidates, edited = false }
end

local function buildOf()
    local _, build = NS.Compat.BuildInfo()
    return NS.Secrets.PlainString(build)
end

local function copy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

--- A sample fight's record in the stored shape (modules/Recorder.lua's header), never stored, and
--- the plan it was read from.
--- @param o table  { id, t (epoch), who, board, length, damage | dps, note?, noMajor?, noPet?, dry? }
--- @param plan table|nil  MockFights.Plan's; made here when nil
--- @return table record, table plan
function MockFights.Record(o, plan)
    plan = plan or MockFights.Plan({ id = o.id, length = o.length, damage = o.damage or o.dps * o.length,
                                     noMajor = o.noMajor, noPet = o.noPet, dry = o.dry })
    local final = MockFights.FinalOf(plan, o.length)
    local ident = MockFights.Identity(o.board)
    local merged = final.merged.total
    local record = {
        schema = NS.Recorder.CT_SCHEMA, id = o.id, t = o.t or time(), duration = o.length, who = o.who,
        identity = ident, boardKey = NS.Identity.BoardKey(ident),
        damage = { merged = merged, player = final.player.total, pet = final.pet and final.pet.total },
        dps = round1(merged / o.length), meterDps = round1(merged / math.ceil(o.length)),
        spells = NS.CastCodec.EncodeSpells(final.merged.spells), casts = NS.CastCodec.Encode(plan.casts),
        cooldowns = plan.cooldowns, gear = copy(CLIENT.gear), stats = copy(CLIENT.stats), usage = usageOf(plan),
        note = o.note, client = NS.Compat.ClientKey(), build = buildOf(), version = NS.version,
        status = "final", sample = true,
    }
    return record, plan
end

--- The sample history for the Results window: { fights, slices }, built fresh (Source.Use's shape).
--- @return table dataset
function MockFights.Dataset()
    local now, have = time(), boards()
    local data = { fights = {}, slices = {} }
    for i, h in ipairs(HISTORY) do
        if have[h[2]] then
            local record, plan = MockFights.Record({
                id = ("sample-%02d"):format(i), t = math.floor(now - h[3] * HOUR), who = MockFights.Character(h[1]),
                board = h[2], length = h[4], dps = h[5] * CLIENT.scale, note = h.note and L[h.note] or nil,
                noMajor = h.noMajor, noPet = h.noPet, dry = h.dry,
            })
            data.fights[#data.fights + 1] = record
            if h.chart then data.slices[record.id] = MockFights.Slices(plan) end
        end
    end
    return data
end

-- ── the HUD's sample fight ──────────────────────────────────────────────────────────────────────

--- A sample fight as modules/Fight.lua's would read to the HUD: flagged `sample`, carrying its plan
--- (the HUD reads its live figures and casts from it, never the meter) and the snapshot and
--- encounter its identity resolves from. The caller stamps startT and firstHitT.
--- @param o table  { id, board, who, plan }
--- @return table fight
function MockFights.Fight(o)
    local b = MockFights.Board(o.board) or MockFights.Board("vorasius")
    return { id = o.id, sample = true, plan = o.plan, sessions = {},
             snapshot = { who = o.who, target = b.target, where = b.where }, encounter = b.encounter }
end

--- A sample fight against `data` (the sample history) on board `o.board`: its DPS set `o.factor`
--- against the main hunter's best there (a board with none fights at the main hunter's best DPS of
--- the history's first row).
--- @param o table  { id, board, length, factor? }
--- @param data table  MockFights.Dataset's
--- @return table sample  { fight, plan, who, ident, best|nil, dps }
function MockFights.Sample(o, data)
    local who = MockFights.Character("me")
    local ident = MockFights.Identity(o.board) or MockFights.Identity("vorasius")
    local probe = { who = who, boardKey = NS.Identity.BoardKey(ident), identity = ident, status = "final" }
    local key = NS.Bests.Key(probe)
    local best = key and NS.Bests.Compute(data and data.fights or {})[key] or nil
    local dps = HISTORY[1][5] * CLIENT.scale
    if best and o.factor then dps = best.dps * o.factor end
    local plan = MockFights.Plan({ id = o.id, length = o.length, damage = dps * o.length })
    local fight = MockFights.Fight({ id = o.id, board = o.board, who = who, plan = plan })
    return { fight = fight, plan = plan, who = who, ident = ident, best = best, dps = dps, board = o.board }
end
