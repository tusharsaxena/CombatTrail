local _, NS = ...
-- modules/Identity.lua — what a fight was (spec §5, plan Task 2.3): who fought, where, against what,
-- and the board key that groups it with the fights it is compared against. Adapted from DPS Race
-- @045f479 (modules/Recorder.lua's snapshots) without its race: no arm-time snapshot, no dummy
-- categories, no dummy-type boards.
--
-- TWO READS.
--   * Identity.Snapshot() at combat entry (modules/Fight.lua stores it as fight.snapshot): who the
--     player is (name, realm, class, spec, item level, pet), the target, and where (the instance,
--     its difficulty, the keystone level, the delve tier, the PvP bracket). Where is read here, at
--     the start, because a keystone ends, a delve closes and a battleground ports the player out
--     before the after-combat read.
--   * Identity.Resolve(fight, final, enemies) after combat, out of plain values: the encounter
--     (fight.encounter, from ENCOUNTER_START), the primary target (the meter's EnemyDamageTaken list,
--     NS.Meter.ReadEnemies, highest first; the snapshot's target when the list is empty), the content
--     and the boss flag. Without a snapshot, where is read at that moment.
--
-- THE BOARD KEY (spec §5): "e:<encounterID>:<difficultyID>" for an encounter, else
-- "c:<creatureID>:<difficultyID>" for the primary target, then one tier qualifier where difficulty
-- alone does not separate content: ":k<keystone level>", ":d<delve tier>" or ":p<PvP bracket>". The
-- open world takes none. In a battleground or an arena the primary target is usually a player, who
-- has no creature ID: there the board is the instance's, "i:<instanceID>:<difficultyID>:p<bracket>"
-- (the plan names only "e:" and "c:"; a PvP fight against players would otherwise never have a
-- board). A fight with no readable target is "Unknown target" and has no key, so it is never a best.
--
-- CLIENTS (clients-§4). Delves, Mythic+ and arenas are Retail-only: on WoW Forever isDelve,
-- delveTier and keystoneLevel are never set, and an arena is filed as "bg" content. NS.Compat answers
-- those questions (core/Compat.lua); Identity.CONTENT declares the content kinds per client.
--
-- SECRETS. The snapshot runs in combat, where a unit's GUID, name and classification may be secret:
-- every client value passes through NS.Secrets on its way in, and a sealed field is absent. A secret
-- is never parsed, compared or used as a key. Every client call is read BARE at CALL time and
-- pcall'd, so a client without one yields an absent field, never a Lua error.
--
-- NAMES (client-quirks §5). A character is read through NS.Compat.UnitCharacterName: on WoW Forever
-- it is the whole "First Surname", and the realm is the ruleset (NS.Compat.RealmKey). A name is never
-- split, and UnitName's second value is never read as a realm.

local Identity = {}
NS.Identity = Identity

local Secrets = NS.Secrets
local L = NS.L

local RETAIL = { "retail" }

--- The content kinds, in the order the History filters list them, each declared for its clients.
Identity.CONTENT = {
    { key = "raid" },
    { key = "dungeon" },
    { key = "mplus", clients = RETAIL },
    { key = "delve", clients = RETAIL },
    { key = "bg" },
    { key = "arena", clients = RETAIL },
    { key = "world" },
    { key = "dummy" },
    { key = "scenario" },
}

-- GetInstanceInfo's instance type -> content, before the keystone, delve and dummy checks.
local CONTENT_OF_TYPE = { raid = "raid", party = "dungeon", pvp = "bg", arena = "arena",
                          scenario = "scenario", none = "world" }

--- The content keys this client has, in Identity.CONTENT's order.
--- @return string[]
function Identity.ContentKeys()
    local out = {}
    for _, c in ipairs(Identity.CONTENT) do
        if NS.Compat.ForClient(c.clients) then out[#out + 1] = c.key end
    end
    return out
end

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Identity", fmt, ...) end
end

local function passResults(ok, ...)
    if ok then return ... end
    debug("client call raised: %s", tostring((...)))
    return nil
end

--- Call a client function if it exists, pcall'd. Answers its results, or nothing.
local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    return passResults(pcall(fn, ...))
end

--- A plain number to one decimal, or nil.
local function round1(v)
    v = Secrets.PlainNumber(v)
    if not v then return nil end
    return math.floor(v * 10 + 0.5) / 10
end

--- The creature ID out of a Creature or Vehicle GUID (its sixth field), or nil: for a player, a pet,
--- no GUID, or a secret one, which is never parsed.
local function creatureOf(guid)
    guid = Secrets.PlainString(guid)
    if not guid then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

-- A unit's whole character name, plain, or nil.
local function nameOf(unit)
    return Secrets.PlainString((ask(NS.Compat.UnitCharacterName, unit)))
end

-- ── who ─────────────────────────────────────────────────────────────────────────────────────────

local function readSpec(who)
    local Compat = NS.Compat
    local index = Secrets.PlainNumber(ask(Compat.GetSpecialization))
    if not index then return end
    local specID, specName = ask(Compat.GetSpecializationInfo, index)
    who.specID = Secrets.PlainNumber(specID)
    who.specName = Secrets.PlainString(specName)
end

local function readPet(who)
    if not Secrets.PlainTruth(ask(UnitExists, "pet")) then return end
    who.petName = nameOf("pet")
    who.petFamily = Secrets.PlainString(ask(UnitCreatureFamily, "pet"))
end

-- Who the player is: { name, realm, class, level, specID, specName, ilvl, petName, petFamily, client }.
-- The level is what a fight's talentbuild link carries (the tree's points come from it).
local function readWho()
    local Compat = NS.Compat
    local who = { name = nameOf("player"), realm = Secrets.PlainString(ask(Compat.RealmKey)),
                  client = Compat.ClientKey() }
    local _, classToken = ask(UnitClass, "player")
    who.class = Secrets.PlainString(classToken)
    who.level = Secrets.PlainNumber(ask(UnitLevel, "player"))
    -- GetAverageItemLevel answers (overall, equipped); the fight's is the equipped one.
    local overall, equipped = ask(GetAverageItemLevel)
    who.ilvl = round1(equipped) or round1(overall)
    readSpec(who)
    readPet(who)
    return who
end

-- ── the target ──────────────────────────────────────────────────────────────────────────────────

-- The target at combat entry: { name, creatureID, classification, isDummy }, or nil with no target.
local function readTarget()
    if not Secrets.PlainTruth(ask(UnitExists, "target")) then return nil end
    local t = {
        creatureID     = creatureOf(ask(UnitGUID, "target")),
        name           = nameOf("target"),
        classification = Secrets.PlainString(ask(UnitClassification, "target")),
    }
    local dummy = NS.DummyName(t.creatureID)
    t.isDummy = dummy ~= nil
    if t.name == nil then t.name = dummy end
    return t
end

-- ── where ───────────────────────────────────────────────────────────────────────────────────────

-- The PvP bracket of a battleground or arena: "ss" Solo Shuffle, "bz" Battleground Blitz, else the
-- instance's size with an "r" before it when rated ("r10", "40"). nil outside PvP instances.
local function bracketOf(w)
    if w.instanceType ~= "pvp" and w.instanceType ~= "arena" then return nil end
    local rules = ask(NS.Compat.PvpRules) or {}
    if rules.soloShuffle then return "ss" end
    if rules.blitz then return "bz" end
    local size = (w.maxPlayers or 0) > 0 and tostring(math.floor(w.maxPlayers)) or "0"
    return ((rules.ratedBG or rules.ratedArena) and "r" or "") .. size
end

-- The Retail-only tiers (clients-§4): the delve and its tier, the keystone level in a dungeon.
local function readRetailTiers(w)
    local Compat = NS.Compat
    if not Compat.ForClient(RETAIL) then return end
    w.isDelve = ask(Compat.InDelve) == true
    if w.isDelve then
        local text = Secrets.PlainString(ask(Compat.DelveTierText))
        w.delveTier = text and tonumber(text:match("%d+")) or nil
    end
    if w.instanceType == "party" then
        local level = Secrets.PlainNumber(ask(Compat.KeystoneLevel))
        if level and level > 0 then w.keystoneLevel = level end
    end
end

-- Where the player is: { instanceType, instanceName, instanceID, difficultyID, difficultyName,
-- maxPlayers, isDelve, delveTier, keystoneLevel, pvpBracket }.
local function readWhere()
    local name, instanceType, difficultyID, difficultyName, maxPlayers, _, _, instanceID = ask(GetInstanceInfo)
    local w = {
        instanceName   = Secrets.PlainString(name),
        instanceType   = Secrets.PlainString(instanceType) or "none",
        difficultyID   = Secrets.PlainNumber(difficultyID) or 0,
        difficultyName = Secrets.PlainString(difficultyName),
        maxPlayers     = Secrets.PlainNumber(maxPlayers),
        instanceID     = Secrets.PlainNumber(instanceID),
    }
    if w.difficultyName == "" then w.difficultyName = nil end
    readRetailTiers(w)
    w.pvpBracket = bracketOf(w)
    return w
end

-- ── the snapshot ────────────────────────────────────────────────────────────────────────────────

--- Who, against what and where, read now (combat entry). Secret-safe: a sealed field is absent.
--- @return table snap  { who, target|nil, where }
function Identity.Snapshot()
    return { who = readWho(), target = readTarget(), where = readWhere() }
end

--- Who the player is now (the snapshot's `who`): the Results window's "current character" and
--- "current spec" filters read it out of combat.
--- @return table who  { name, realm, class, level, specID, specName, ilvl, petName, petFamily, client }
function Identity.Who()
    return readWho()
end

-- ── the identity ────────────────────────────────────────────────────────────────────────────────

-- The enemy that took the most damage, and how many others did: the meter's list is highest first.
-- A row whose name and creature ID are both unreadable (secret) is skipped, as is one that took none.
local function primaryOf(enemies)
    local first, others = nil, 0
    if type(enemies) ~= "table" then return nil, 0 end
    for _, e in ipairs(enemies) do
        local name, creatureID = Secrets.PlainString(e.name), Secrets.PlainNumber(e.creatureID)
        local total = Secrets.PlainNumber(e.total)
        if (name or creatureID) and (total == nil or total > 0) then
            if first then others = others + 1 else first = { name = name, creatureID = creatureID } end
        end
    end
    return first, others
end

-- The difficulty's name: the instance's own when it is the instance's difficulty, else the client's.
local function difficultyNameOf(id, where)
    if id == where.difficultyID and where.difficultyName then return where.difficultyName end
    if id == 0 then return nil end
    local name = Secrets.PlainString((ask(GetDifficultyInfo, id)))
    if name == "" then return nil end
    return name
end

local function contentOf(ident)
    if NS.DummyName(ident.targetCreatureID) then return "dummy" end
    local kind = ident.instanceType
    if kind == "party" and ident.keystoneLevel then return "mplus" end
    if ident.isDelve then return "delve" end
    if kind == "arena" and not NS.Compat.ForClient(RETAIL) then return "bg" end
    return CONTENT_OF_TYPE[kind] or "world"
end

-- The primary target onto `ident`: the meter's, else the snapshot's, else the encounter's name (an
-- encounter is a readable identity, spec §5, so it is never unknown), else Unknown target.
local function resolveTarget(ident, snap, enemies)
    local first, others = primaryOf(enemies)
    if not first and type(snap.target) == "table" and (snap.target.name or snap.target.creatureID) then
        first, others = snap.target, 0
    end
    ident.otherTargets = others
    if not first then
        if ident.encounterID then
            ident.targetName = ident.encounterName or L["Unknown target"]
            return
        end
        ident.targetName, ident.unknown = L["Unknown target"], true
        return
    end
    ident.targetCreatureID = first.creatureID
    ident.targetName = first.name or NS.DummyName(first.creatureID) or ident.encounterName
    if ident.targetName == nil then ident.targetName = L["Unknown target"] end
end

-- A boss fight: an encounter, or a world boss the player had targeted (never a boss-level dummy).
local function isBoss(ident, snap)
    if ident.encounterID then return true end
    if ident.content == "dummy" then return false end
    local t = snap.target
    return type(t) == "table" and t.classification == "worldboss" and t.creatureID ~= nil
        and t.creatureID == ident.targetCreatureID
end

local WHERE_FIELDS = { "instanceType", "instanceName", "instanceID", "isDelve", "delveTier", "keystoneLevel",
                       "pvpBracket" }

--- The fight's identity, out of plain values (after combat).
--- @param fight table  the fight (modules/Fight.lua): its encounter and snapshot are read
--- @param _ table|nil  the final read (Meter.ReadFinal's shape); the identity takes nothing from it
--- @param enemies table|nil  Meter.ReadEnemies' list, highest first ({} or nil: none readable)
--- @return table identity  { encounterID?, encounterName?, difficultyID, difficultyName?, instanceType,
---   instanceName?, instanceID?, isDelve?, delveTier?, keystoneLevel?, pvpBracket?, content,
---   targetName, targetCreatureID?, otherTargets, isBoss, unknown? }
function Identity.Resolve(fight, _, enemies)
    fight = type(fight) == "table" and fight or {}
    local snap = type(fight.snapshot) == "table" and fight.snapshot or {}
    local where = type(snap.where) == "table" and snap.where or readWhere()
    local ident = {}
    for _, k in ipairs(WHERE_FIELDS) do ident[k] = where[k] end
    local enc = type(fight.encounter) == "table" and fight.encounter or {}
    ident.encounterID = enc.id
    ident.encounterName = enc.id and enc.name or nil
    ident.difficultyID = (enc.id and enc.difficultyID) or where.difficultyID or 0
    ident.difficultyName = difficultyNameOf(ident.difficultyID, where)
    resolveTarget(ident, snap, enemies)
    ident.content = contentOf(ident)
    ident.isBoss = isBoss(ident, snap)
    return ident
end

--- The board key of an identity (spec §5), or nil when its target is unknown.
--- @param ident table|nil  an Identity.Resolve result
--- @return string|nil
function Identity.BoardKey(ident)
    if type(ident) ~= "table" then return nil end
    local diff = ident.difficultyID or 0
    local key
    if ident.encounterID then
        key = ("e:%d:%d"):format(ident.encounterID, diff)
    elseif ident.targetCreatureID then
        key = ("c:%d:%d"):format(ident.targetCreatureID, diff)
    elseif ident.pvpBracket and ident.instanceID and not ident.unknown then
        key = ("i:%d:%d"):format(ident.instanceID, diff)
    else
        return nil
    end
    if ident.keystoneLevel then return key .. ":k" .. ident.keystoneLevel end
    if ident.delveTier then return key .. ":d" .. ident.delveTier end
    if ident.pvpBracket then return key .. ":p" .. ident.pvpBracket end
    return key
end
