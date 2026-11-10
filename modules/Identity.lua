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
-- THE BOARD KEY (spec §5, v0.2 plan Task A2 and decision D3): "e:<encounterID>:<difficultyID>" for
-- an encounter; "c:<creatureID>:<difficultyID>" for a world boss (a boss without an encounter, whose
-- level is no part of its board); else the primary target by NPC ID, level and name,
-- "t:<npcID>:<level|?>:<name>:<difficultyID>". Then one tier qualifier where difficulty alone does not
-- separate content: ":k<keystone level>", ":d<delve tier>" or ":p<PvP bracket>". The open world
-- takes none. In a battleground or an arena the primary target is usually a player, who has no
-- creature ID: there the board is the instance's, "i:<instanceID>:<difficultyID>:p<bracket>". Any
-- other named target with no NPC ID falls back to the name alone, "n:<name>:<difficultyID>". A fight
-- with no readable target is "Unknown target" and has no key, so it is never a best.
--
-- THE LEVEL in the key is the combat-entry snapshot's (the target's UnitLevel; -1 is a skull), taken
-- only when the snapshot's target is the primary (their plain creature IDs are equal). The HUD builds
-- its pace key from the same snapshot in combat (Hud.PaceRecord), so the live key and the stored one
-- agree. A level sealed at entry is "?" in both, and is never re-read after combat.
--
-- THE SPEC. On Retail it is the client's specialization. WoW Forever answers one class-wide spec, so
-- there the predominant talent tree stands in for it (v0.2 plan Task A4, D5): who.trees holds each
-- tree's points, and who.specID ("tree:<class>:<index>"), specName and specIcon are the tree with
-- the most points (a tie goes to the first; none with points, no spec). NS.Compat.TalentTrees reads
-- the trees; a read sealed in combat (a secret ID or point count, or an inaccessible table) keeps the
-- session's last plain one, which Identity.Prime takes at login and every stand-up.
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

-- The spec on Retail: the client's specialization.
local function readSpec(who)
    local Compat = NS.Compat
    local index = Secrets.PlainNumber(ask(Compat.GetSpecialization))
    if not index then return end
    local specID, specName = ask(Compat.GetSpecializationInfo, index)
    who.specID = Secrets.PlainNumber(specID)
    who.specName = Secrets.PlainString(specName)
end

-- WoW Forever's last plain talent-tree read: a read sealed in combat keeps it (talents change out of
-- combat only), where a missing or raising API is no trees.
local lastTrees

--- The tree with the most points, or nil when none has any: a tie goes to the first tree.
--- @param trees table  { { name, icon, points }, ... }, points plain
--- @return number|nil index
function Identity.Predominant(trees)
    local best
    for i, t in ipairs(trees) do
        if t.points > 0 and (not best or t.points > trees[best].points) then best = i end
    end
    return best
end

-- The spec on WoW Forever (v0.2 plan Task A4, D5): the class-wide spec the client answers is never
-- read. The trees' points are stored (who.trees), and the predominant tree stands in for the spec:
-- who.specID "tree:<class>:<index>" (never a Retail spec ID), who.specName and who.specIcon its own.
local function readTrees(who)
    local trees, why = ask(NS.Compat.TalentTrees)
    if trees then lastTrees = trees elseif why == "sealed" then trees = lastTrees end
    if type(trees) ~= "table" or #trees == 0 then return end
    local points = {}
    for i, t in ipairs(trees) do points[i] = t.points end
    who.trees = points
    local best = Identity.Predominant(trees)
    if not best then return end
    who.specID = ("tree:%s:%d"):format(tostring(who.class or "?"), best)
    who.specName = trees[best].name
    who.specIcon = trees[best].icon
end

--- WoW Forever: read the talent trees now, so the session's first sealed read (the combat-entry
--- snapshot) has a last plain one to keep. At login and every stand-up (NS.RegisterGameEvents).
--- Nothing on Retail; a read that is itself sealed or absent keeps what was there.
function Identity.Prime()
    if NS.Compat.ForClient(RETAIL) then return end
    readTrees({})
end

local function readPet(who)
    if not Secrets.PlainTruth(ask(UnitExists, "pet")) then return end
    who.petName = nameOf("pet")
    who.petFamily = Secrets.PlainString(ask(UnitCreatureFamily, "pet"))
end

-- Who the player is: { name, realm, class, level, specID, specName, specIcon?, trees?, ilvl, petName,
-- petFamily, client } (specIcon and trees on WoW Forever only).
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
    if Compat.ForClient(RETAIL) then readSpec(who) else readTrees(who) end
    readPet(who)
    return who
end

-- ── the target ──────────────────────────────────────────────────────────────────────────────────

-- The target at combat entry: { name, creatureID, level, classification, isDummy }, or nil with no
-- target. The level is plain or absent (a sealed one is never compared); -1 is a skull level.
local function readTarget()
    if not Secrets.PlainTruth(ask(UnitExists, "target")) then return nil end
    local t = {
        creatureID     = creatureOf(ask(UnitGUID, "target")),
        name           = nameOf("target"),
        level          = Secrets.PlainNumber(ask(UnitLevel, "target")),
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

-- A zone text, plain and non-empty, or nil.
local function zoneText(fn)
    local text = Secrets.PlainString((ask(fn)))
    if text == "" then return nil end
    return text
end

-- Where the player is: { instanceType, instanceName, instanceID, difficultyID, difficultyName,
-- maxPlayers, isDelve, delveTier, keystoneLevel, pvpBracket, zone, subzone }. In the open world the
-- instance's name is the continent; the zone and subzone (GetZoneText, GetSubZoneText) name the place.
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
    w.zone, w.subzone = zoneText(GetZoneText), zoneText(GetSubZoneText)
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
--- @return table who  { name, realm, class, level, specID, specName, specIcon?, trees?, ilvl, petName,
---                      petFamily, client }
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

-- The snapshot target's level when it is the primary `first` (the meter's list carries no level):
-- the same table, or plain creature IDs that are equal. Both IDs passed Secrets on the way in.
local function levelOf(first, t)
    if type(t) ~= "table" or t.level == nil then return nil end
    if first == t or (first.creatureID ~= nil and first.creatureID == t.creatureID) then return t.level end
    return nil
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
    ident.targetLevel = levelOf(first, snap.target)
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
                       "pvpBracket", "zone", "subzone" }

--- The fight's identity, out of plain values (after combat).
--- @param fight table  the fight (modules/Fight.lua): its encounter and snapshot are read
--- @param _ table|nil  the final read (Meter.ReadFinal's shape); the identity takes nothing from it
--- @param enemies table|nil  Meter.ReadEnemies' list, highest first ({} or nil: none readable)
--- @return table identity  { encounterID?, encounterName?, difficultyID, difficultyName?, instanceType,
---   instanceName?, instanceID?, isDelve?, delveTier?, keystoneLevel?, pvpBracket?, zone?, subzone?,
---   content, targetName, targetCreatureID?, targetLevel?, otherTargets, isBoss, unknown? }
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

-- The key's head, before its tier qualifier, or nil: see THE BOARD KEY above.
local function keyHead(ident, diff)
    if ident.encounterID then return ("e:%d:%d"):format(ident.encounterID, diff) end
    local npc = ident.targetCreatureID
    if npc and ident.isBoss then return ("c:%d:%d"):format(npc, diff) end
    if ident.unknown then return nil end
    local name = type(ident.targetName) == "string" and ident.targetName or nil
    if npc then
        local level = type(ident.targetLevel) == "number" and ("%d"):format(ident.targetLevel) or "?"
        return ("t:%d:%s:%s:%d"):format(npc, level, name or "", diff)
    end
    if ident.pvpBracket and ident.instanceID then return ("i:%d:%d"):format(ident.instanceID, diff) end
    if name then return ("n:%s:%d"):format(name, diff) end
    return nil
end

--- The board key of an identity (spec §5), or nil when its target is unknown.
--- @param ident table|nil  an Identity.Resolve result
--- @return string|nil
function Identity.BoardKey(ident)
    if type(ident) ~= "table" then return nil end
    local diff = ident.difficultyID or 0
    local key = keyHead(ident, diff)
    if not key then return nil end
    if ident.keystoneLevel then return key .. ":k" .. ident.keystoneLevel end
    if ident.delveTier then return key .. ":d" .. ident.delveTier end
    if ident.pvpBracket then return key .. ":p" .. ident.pvpBracket end
    return key
end
