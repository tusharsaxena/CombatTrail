local _, NS = ...
-- core/Compat.lua — the compat family's root and only file (compat): every version-variant client
-- call the addon makes outside LibKa0s's majors, and every LibKa0s-Compat-1.0 member it consumes,
-- behind NS.Compat. No other file names these APIs. The family has no other file.
--
-- Routed through LibKa0s-Compat-1.0 (library-stack-§7), each with its library-absent stub:
--   Compat.IsRetail()  Compat.IsForever()  Compat.ClientKey()  Compat.ForClient(clients)
--                                the client checks (clients-§3): the ONLY place this addon asks which
--                                client it runs on; a per-client feature is declared with
--                                `clients = { "retail" }` and answered by ForClient (clients-§4)
--   Compat.IsSecret(v)  Compat.CanAccess(v)  Compat.IsSafeKey(v)   the three secret-value guards
--   Compat.GetSpecialization()  Compat.GetSpecializationInfo(index)
--                                C_SpecializationInfo first, then the deprecated globals (both are
--                                gone on WoW Forever, where the stubs answer nil)
--   Compat.UnitCharacterName(unit)  Compat.RealmKey()
--                                a character's whole name and the player's realm key (client-quirks
--                                §5: "First Surname" and the ruleset on WoW Forever)
-- Hand-written ladders across clients and patches:
--   Compat.SpellTexture(id)      C_Spell.GetSpellTexture, then the bare global; the id is passed through
--                                untouched, so the caller runs it in pcall (it may be secret)
--   Compat.CanAccessTable(t)     canaccesstable, then issecrettable, then "readable"
--   Compat.ChatSender()          C_ChatInfo.SendChatMessage, then the bare global (deprecated 11.2.0)
--   Compat.NumberFormatterCandidates()  C_StringUtil's abbreviated-number formatter constructor,
--                                then its numeric-rule constructor, every one present (Format
--                                checks each and takes the first that passes)
--   Compat.PopupEditBox(dialog)  a StaticPopup's edit box: the GetEditBox method, then the editBox /
--                                EditBox field
--   Compat.KeystoneLevel()  Compat.DelveTierText()  Compat.PvpRules()
--                                a fight's tier qualifiers (modules/Identity.lua): the Mythic+ level
--                                and the delve tier (Retail-only, nil on Forever), the PvP match rules
--   Compat.TalentTrees()  Compat.TalentApis()
--                                WoW Forever's talent trees (name, icon, points each), which stand in
--                                for a specialization there (v0.2 plan Task A4, D5): the talent tabs
--                                (GetNumTalentTabs / GetTalentTabInfo), then C_Traits' trait groups;
--                                and every answer those APIs give, raw, for `/ct probe`. Nil on Retail
--   Compat.BuildInfo()  Compat.ClientApis()   the probe's client line: GetBuildInfo, and whether the
--                                secrets system and C_Spell's lookups exist (modules/Probe.lua)
-- Every client global is read at CALL time, so a client (or the harness's mock) that adds the API
-- later is seen.
--
-- THE GUARDS HAVE ONE CALLER. core/Secrets.lua binds them at FILE SCOPE (so this file loads first)
-- and stays the only file that inspects a value that may be secret (spec §3): no other file reaches
-- NS.Compat's guards.

NS.Compat = NS.Compat or {}
local Compat = NS.Compat

local CompatLib = LibStub and LibStub("LibKa0s-Compat-1.0", true)

-- ---------------------------------------------------------------------------
-- The client: LibKa0s-Compat-1.0's, with the stub arm (clients-§3)
-- ---------------------------------------------------------------------------
--
-- The stub re-implements the library's body: both project constants read BARE and at CALL time.
-- WOW_PROJECT_CAMELOT is nil on Retail, so the nil guard is what keeps a client that defines neither
-- constant from reading as Forever (nil == nil).

local function isForeverStub()
    return WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
end

local function isRetailStub()
    return WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and not isForeverStub()
end

local function clientKeyStub()
    if isForeverStub() then return "forever" end
    if isRetailStub() then return "retail" end
    return nil
end

local CLIENT_TOKENS = { retail = true, forever = true, both = true }

local function forClientStub(clients)
    if clients == nil or clients == "both" then return true end
    if type(clients) ~= "table" then error('ForClient: unknown client "' .. tostring(clients) .. '"', 2) end
    for _, token in ipairs(clients) do
        if not CLIENT_TOKENS[token] then error('ForClient: unknown client "' .. tostring(token) .. '"', 2) end
    end
    local key = clientKeyStub()
    for _, token in ipairs(clients) do
        if token == "both" or token == key then return true end
    end
    return false
end

--- Whether this is a WoW Forever client.
--- @return boolean
Compat.IsForever = CompatLib and CompatLib.IsForever or isForeverStub

--- Whether this is a Retail client (the mainline project id and NOT Forever).
--- @return boolean
Compat.IsRetail = CompatLib and CompatLib.IsRetail or isRetailStub

--- The client's key: "retail", "forever", or nil when the project constants say neither.
--- @return string|nil
Compat.ClientKey = CompatLib and CompatLib.ClientKey or clientKeyStub

--- Whether a `clients` declaration (nil, "both", or an array of "retail" / "forever" / "both")
--- includes this client. An unknown token raises.
--- @param clients nil|string|string[]
--- @return boolean
Compat.ForClient = CompatLib and CompatLib.ForClient or forClientStub

-- ---------------------------------------------------------------------------
-- The secret guards: LibKa0s-Compat-1.0's, with the stub arm
-- ---------------------------------------------------------------------------
--
-- THE GUARD ARM is a deliberate, documented duplication (LibKa0s docs/api/Compat/version-1-docs.md,
-- "Guards: the stub re-implements the body"). "The library is missing" is not "the client has no
-- secrets system": a stub answering IsSecret -> false on a 12.x client would send a secret into a
-- comparison mid-pull, on exactly the degraded path the stub exists to survive. The client globals
-- are read BARE and at CALL time, as the library reads them, so the harness's mock reaches both arms.

local function isSecretStub(v)
    local fn = issecretvalue
    if not fn then return false end
    return fn(v) and true or false
end

local function canAccessStub(v)
    local fn = canaccessvalue
    if fn then return fn(v) and true or false end
    return not isSecretStub(v)
end

local function isSafeKeyStub(v)
    if isSecretStub(v) then return false end
    return v ~= nil
end

--- Whether `v` is a secret value. False on a client without the secrets system.
--- @param v any
--- @return boolean
Compat.IsSecret = CompatLib and CompatLib.IsSecret or isSecretStub

--- Whether this context may look at `v`. A plain value always answers true.
--- @param v any
--- @return boolean
Compat.CanAccess = CompatLib and CompatLib.CanAccess or canAccessStub

--- Whether `v` may be a table KEY right now (not secret, not nil).
--- @param v any
--- @return boolean
Compat.IsSafeKey = CompatLib and CompatLib.IsSafeKey or isSafeKeyStub

--- Whether this context may read the CONTENTS of table `t` (the caller has checked it is a table).
--- No LibKa0s major carries it. Without either client global every table is readable.
--- @param t table
--- @return boolean
function Compat.CanAccessTable(t)
    local can = canaccesstable
    if can then return can(t) and true or false end
    local isSecretTable = issecrettable
    if isSecretTable then return not isSecretTable(t) end
    return true
end

-- ---------------------------------------------------------------------------
-- The player's specialization: LibKa0s-Compat-1.0's, with the stub arm
-- ---------------------------------------------------------------------------
-- The stubs walk the library's two rungs: C_SpecializationInfo where it exists, else the deprecated
-- global. Both read the client at CALL time.

local function getSpecializationStub()
    local api = C_SpecializationInfo
    if api and api.GetSpecialization then return (api.GetSpecialization()) end
    local bare = GetSpecialization
    if bare then return (bare()) end
    return nil
end

local function getSpecializationInfoStub(index)
    if not index then return nil end
    local api = C_SpecializationInfo
    if api and api.GetSpecializationInfo then return api.GetSpecializationInfo(index) end
    local bare = GetSpecializationInfo
    if bare then return bare(index) end
    return nil
end

--- The player's active specialization index, or nil.
--- @return number|nil
Compat.GetSpecialization = CompatLib and CompatLib.GetSpecialization or getSpecializationStub

--- The specialization's info for `index` (specID, name, description, icon, role, ...), or nil.
--- @param index number
Compat.GetSpecializationInfo = CompatLib and CompatLib.GetSpecializationInfo or getSpecializationInfoStub

-- ---------------------------------------------------------------------------
-- The talent trees (WoW Forever): the predominant tree stands in for a specialization
-- ---------------------------------------------------------------------------
--
-- WoW Forever answers one class-wide specialization, so its spec is no spec (its icon is the class
-- icon). Its talents are the classic trees. Two readers, in order, each guarded and pcall'd: the
-- talent tabs (GetNumTalentTabs / GetTalentTabInfo, in neither of the kit's client sets, so they are
-- tried in case the client has them), then the active config's tree in C_Traits, whose groups are the
-- trees (Forever's own talent frame: C_Traits.GetGroupDisplayInfoByTreeID, the points spent from
-- C_Traits.GetGroupCurrencyInfo). Which one answers on the client is what `/ct probe` dumps.
--
-- SECRETS. Every value is read through NS.Secrets (bound at CALL time; core/Secrets.lua loads after
-- this file). A tree whose points are sealed makes the whole answer sealed: points are only ever
-- compared plain, so a partial read is never picked from.

local FOREVER = { "forever" }

local function plainNumber(v) return NS.Secrets.PlainNumber(v) end
local function plainString(v) return NS.Secrets.PlainString(v) end
local function sealed(v) return NS.Secrets.IsSealed(v) end

--- An icon as a plain file ID or path, or nil.
local function plainIcon(v) return plainNumber(v) or plainString(v) end

-- One talent tab's { name, icon, points }, or nil plus "sealed" when its points are not plain.
-- GetTalentTabInfo has two shapes across clients: (name, icon, points, background) and
-- (id, name, description, icon, points, ...); a plain number first is the second.
local function tabRow(a, b, c, d, e)
    local name, icon, points = a, b, c
    if plainNumber(a) then name, icon, points = b, d, e end
    if sealed(points) or sealed(name) then return nil, "sealed" end
    points = plainNumber(points)
    if not points then return nil end
    return { name = plainString(name), icon = plainIcon(icon), points = points }
end

local function tabTrees()
    local count, info = GetNumTalentTabs, GetTalentTabInfo
    if type(count) ~= "function" or type(info) ~= "function" then return nil end
    local ok, raw = pcall(count)
    if not ok then return nil end
    if sealed(raw) then return nil, "sealed" end
    local n = plainNumber(raw)
    if not n or n < 1 then return nil end
    local out = {}
    for i = 1, n do
        local okRow, a, b, c, d, e = pcall(info, i)
        if not okRow then return nil end
        local row, why = tabRow(a, b, c, d, e)
        if not row then return nil, why end
        out[i] = row
    end
    return out
end

-- A table answer that is there but cannot be read: a sealed one, never indexed.
local function sealedTable(t)
    return sealed(t) or (type(t) == "table" and not Compat.CanAccessTable(t))
end

-- A table answer that can be read, or nil plus "sealed" when it is there but sealed.
local function readableTable(t)
    if sealedTable(t) then return nil, "sealed" end
    if type(t) ~= "table" then return nil end
    return t
end

-- The spec group's combat config, or nil (plus "sealed" when the group or the ID was secret).
local function combatConfigID(spec)
    local okG, group = pcall(spec.GetActiveSpecGroup)
    if okG and sealed(group) then return nil, "sealed" end
    group = okG and plainNumber(group)
    if not group then return nil end
    local okC, id = pcall(spec.GetCombatConfigIDForSpecGroup, group)
    if okC and sealed(id) then return nil, "sealed" end
    return okC and plainNumber(id) or nil
end

-- The active config: the active spec group's combat config, else C_ClassTalents' active config. Nil
-- plus "sealed" when the only answer there was secret.
local function activeConfigID()
    local spec, why = C_SpecializationInfo, nil
    if spec and type(spec.GetActiveSpecGroup) == "function" and type(spec.GetCombatConfigIDForSpecGroup) == "function" then
        local id
        id, why = combatConfigID(spec)
        if id then return id end
    end
    local talents = C_ClassTalents
    if talents and type(talents.GetActiveConfigID) == "function" then
        local ok, id = pcall(talents.GetActiveConfigID)
        if ok and sealed(id) then return nil, "sealed" end
        id = ok and plainNumber(id)
        if id then return id end
    end
    return nil, why
end

-- The config's first tree, or nil (plus "sealed" when the config info, its tree list or the ID was
-- sealed: an inaccessible table is never indexed).
local function treeIDOf(configID)
    local traits = C_Traits
    if not (configID and traits and type(traits.GetConfigInfo) == "function") then return nil end
    local ok, raw = pcall(traits.GetConfigInfo, configID)
    if not ok then return nil end
    local info, why = readableTable(raw)
    if not info then return nil, why end
    local ids
    ids, why = readableTable(info.treeIDs)
    if not ids then return nil, why end
    local id = ids[1]
    if sealed(id) then return nil, "sealed" end
    return plainNumber(id)
end

-- A group display's icon, under whichever field the client names it (unverified: the probe says).
local ICON_FIELDS = { "iconFileID", "icon", "iconTexture", "iconID" }
local function groupIcon(display)
    for _, k in ipairs(ICON_FIELDS) do
        local icon = plainIcon(display[k])
        if icon then return icon end
    end
    return nil
end

local function byOrder(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.id < b.id
end

-- The tree's groups as { id, name, icon, order } rows in display order, and their IDs; a third value
-- "sealed" when the list or a row was sealed (the rows are then empty: a partial tree is no tree).
local function displayedGroups(treeID)
    local ok, raw = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
    local rows, ids = {}, {}
    local displays, why = readableTable(ok and raw or nil)
    if not displays then return rows, ids, why end
    for _, d in ipairs(displays) do
        if sealedTable(d) or (type(d) == "table" and sealed(d.groupID)) then return {}, {}, "sealed" end
        local id = type(d) == "table" and plainNumber(d.groupID)
        if id then
            rows[#rows + 1] = { id = id, name = plainString(d.displayName), icon = groupIcon(d),
                                order = plainNumber(d.orderIndex) or #rows + 1 }
        end
    end
    table.sort(rows, byOrder)
    for i, r in ipairs(rows) do ids[i] = r.id end
    return rows, ids
end

-- One group's currency row: its groupID and points spent (the first currency's), or nil; a third
-- value "sealed" when the row, its currency list, the first currency or a value in them was sealed.
local function groupSpent(info)
    if sealedTable(info) then return nil, nil, "sealed" end
    if type(info) ~= "table" then return nil end
    if sealed(info.traitNodeGroupID) then return nil, nil, "sealed" end
    local id = plainNumber(info.traitNodeGroupID)
    if not id then return nil end
    local list = info.currencyInfos
    if sealedTable(list) then return nil, nil, "sealed" end
    local first = type(list) == "table" and list[1]
    if sealedTable(first) then return nil, nil, "sealed" end
    local v = type(first) == "table" and first.spent or nil
    if sealed(v) then return nil, nil, "sealed" end
    return id, plainNumber(v) or 0
end

-- groupID -> the points spent, or nil (plus "sealed" when any of it was sealed).
local function spentByGroup(configID, ids)
    local ok, raw = pcall(C_Traits.GetGroupCurrencyInfo, configID, ids)
    local infos, why = readableTable(ok and raw or nil)
    if not infos then return nil, why end
    local spent = {}
    for _, info in ipairs(infos) do
        local id, v, whyRow = groupSpent(info)
        if whyRow then return nil, whyRow end
        if id then spent[id] = v end
    end
    return spent
end

local function traitTrees()
    local traits = C_Traits
    if not (traits and type(traits.GetGroupDisplayInfoByTreeID) == "function"
            and type(traits.GetGroupCurrencyInfo) == "function") then
        return nil
    end
    local configID, why = activeConfigID()
    if not configID then return nil, why end
    local treeID
    treeID, why = treeIDOf(configID)
    if not treeID then return nil, why end
    local rows, ids
    rows, ids, why = displayedGroups(treeID)
    if #ids == 0 then return nil, why end
    local spent
    spent, why = spentByGroup(configID, ids)
    if not spent then return nil, why end
    local out = {}
    for i, r in ipairs(rows) do out[i] = { name = r.name, icon = r.icon, points = spent[r.id] or 0 } end
    return out
end

--- WoW Forever's talent trees in tree order, `{ { name, icon, points }, ... }` (points plain numbers,
--- name and icon plain or nil), or nil: on Retail (clients-§4), with no talent API, or where one
--- raises. A second value "sealed" says an answer was secret or an inaccessible table (in combat):
--- the config or spec group ID, the config info or its tree IDs, the group list or a row of it, or
--- a group's points. The caller may then keep its last plain read rather than treat the trees as
--- absent. A sealed table is never indexed.
--- @return table|nil trees, string|nil why
function Compat.TalentTrees()
    if not Compat.ForClient(FOREVER) then return nil end
    local trees, why = tabTrees()
    if trees then return trees end
    local traits, whyTraits = traitTrees()
    if traits then return traits end
    return nil, why or whyTraits
end

-- The raw answers `/ct probe` prints: each a packed pcall result { ok, ... , n = count }.
local function pack(...) return { n = select("#", ...), ... } end

local function packed(fn, ...)
    if type(fn) ~= "function" then return nil end
    return pack(pcall(fn, ...))
end

local function tabAnswers(out)
    out.tabCountFn, out.tabInfoFn = type(GetNumTalentTabs), type(GetTalentTabInfo)
    out.tabCount = packed(GetNumTalentTabs)
    local n = out.tabCount and out.tabCount[1] and plainNumber(out.tabCount[2])
    out.tabs = {}
    for i = 1, math.min(n or 0, 5) do out.tabs[i] = packed(GetTalentTabInfo, i) end
end

local function specAnswers(out)
    out.specIndex = packed(Compat.GetSpecialization)
    local index = out.specIndex and out.specIndex[1] and plainNumber(out.specIndex[2])
    out.specInfo = index and packed(Compat.GetSpecializationInfo, index) or nil
    local spec = C_SpecializationInfo or {}
    out.specGroup = packed(spec.GetActiveSpecGroup)
    local group = out.specGroup and out.specGroup[1] and plainNumber(out.specGroup[2])
    out.combatConfig = group and packed(spec.GetCombatConfigIDForSpecGroup, group) or nil
    out.activeConfig = packed((C_ClassTalents or {}).GetActiveConfigID)
end

local function traitAnswers(out)
    out.configID = activeConfigID()
    out.treeID = treeIDOf(out.configID)
    local traits = C_Traits or {}
    out.groups = out.treeID and packed(traits.GetGroupDisplayInfoByTreeID, out.treeID) or nil
    if out.treeID and type(traits.GetGroupDisplayInfoByTreeID) == "function" then
        local _, ids = displayedGroups(out.treeID)
        out.groupIDs = ids
        out.currency = #ids > 0 and packed(traits.GetGroupCurrencyInfo, out.configID, ids) or nil
    end
end

--- Every talent API's answer on WoW Forever, raw (a value may be secret: the probe prints through
--- NS.Secrets), plus TalentTrees()' own: { tabCountFn, tabInfoFn, tabCount, tabs, specIndex, specInfo,
--- specGroup, combatConfig, activeConfig, configID, treeID, groups, groupIDs, currency, trees }. Each
--- raw answer is a packed pcall { ok, ..., n }, nil where the function is missing. Nil on Retail.
--- @return table|nil
function Compat.TalentApis()
    if not Compat.ForClient(FOREVER) then return nil end
    local out = {}
    tabAnswers(out)
    specAnswers(out)
    traitAnswers(out)
    out.trees = Compat.TalentTrees()
    return out
end

-- ---------------------------------------------------------------------------
-- Spells
-- ---------------------------------------------------------------------------

--- The file id of a spell's icon, or nil (exactly one value; it may be secret). Hand-written rather
--- than LibKa0s-Compat-1.0's GetSpellTexture: the library guards the identifier domain with type()
--- first, and a cast lane is handed a spell ID that may be SECRET in combat (spec §4). The C side
--- takes a secret identifier and answers a texture the lane only ever hands to SetTexture, so this
--- passes the id through untouched, never testing it, and the caller runs it in pcall.
--- @param id any
--- @return number|nil
function Compat.SpellTexture(id)
    if id == nil then return nil end
    local spell = C_Spell
    if spell and spell.GetSpellTexture then return (spell.GetSpellTexture(id)) end
    local bare = GetSpellTexture
    if bare then return (bare(id)) end
    return nil
end

--- A spell's name, or nil. For a PLAIN spell ID only (the lanes' name under an icon); the caller
--- runs it in pcall.
--- @param id number
--- @return string|nil
function Compat.SpellName(id)
    if id == nil then return nil end
    local spell = C_Spell
    if spell and spell.GetSpellName then return (spell.GetSpellName(id)) end
    local bare = GetSpellInfo
    if bare then return (bare(id)) end
    return nil
end

--- A spell's base cooldown in milliseconds, or nil (the lanes' long-cooldown glow). It may answer a
--- secret in combat; the caller runs it in pcall and reads it through NS.Secrets.
--- @param id number
--- @return number|nil
function Compat.SpellBaseCooldown(id)
    if id == nil then return nil end
    local fn = GetSpellBaseCooldown
    if fn then return (fn(id)) end
    return nil
end

--- The player's spell haste in percent, or nil (the lanes' haste-adjusted GCD ticks). It may answer
--- a secret in combat; the caller runs it in pcall and reads it through NS.Secrets.
--- @return number|nil
function Compat.SpellHaste()
    local fn = UnitSpellHaste
    if fn then return (fn("player")) end
    return nil
end

-- ---------------------------------------------------------------------------
-- The lanes' visibility context (modules/LaneVisibility.lua)
-- ---------------------------------------------------------------------------

--- Whether the player is in a pet battle. False where the client has no pet battles.
--- @return boolean
function Compat.InPetBattle()
    local pb = C_PetBattles
    if pb and type(pb.IsInBattle) == "function" then return pb.IsInBattle() == true end
    return false
end

--- Whether the player rides a vehicle.
--- @return boolean
function Compat.InVehicle()
    local fn = UnitInVehicle
    if type(fn) == "function" then return fn("player") == true end
    return false
end

--- Whether a delve is in progress. Delves are Retail-only (clients-§4): always false on WoW Forever.
--- @return boolean
function Compat.InDelve()
    if not Compat.ForClient({ "retail" }) then return false end
    local party = C_PartyInfo
    if party and type(party.IsDelveInProgress) == "function" then return party.IsDelveInProgress() == true end
    return false
end

-- ---------------------------------------------------------------------------
-- Who and where a fight was (modules/Identity.lua)
-- ---------------------------------------------------------------------------
--
-- A character's name and realm: LibKa0s-Compat-1.0's identity readers (minor 4, client-quirks §5),
-- each with its library-absent stub. On WoW Forever names are unique per region, a character is its
-- first name and surname together, and UnitName's second value is the SURNAME, never a realm; the
-- realm is its ruleset. The stubs re-implement the two rules this addon depends on (the whole name,
-- never the second value as a realm) and, without the library, take the realm label for the ruleset.

local function regionalNamesStub()
    local fn = RegionalUniqueNamesEnabled
    return type(fn) == "function" and fn() == true
end

local function unitCharacterNameStub(unit)
    local read = UnitName
    if not unit or type(read) ~= "function" then return nil, nil end
    local name, second = read(unit)
    if name == nil then return nil, nil end
    if not regionalNamesStub() then return name, second end
    if isSecretStub(name) or isSecretStub(second) or type(second) ~= "string" or second == "" then
        return name, nil
    end
    return name .. " " .. second, nil
end

local function realmKeyStub()
    local fn = GetRealmName
    local realm = type(fn) == "function" and fn() or nil
    if type(realm) ~= "string" or realm == "" then return nil end
    return realm
end

--- A unit's character name and realm (two values; either may be secret in combat, so the caller
--- reads both through NS.Secrets). With regional names the name is the whole "First Surname".
--- @param unit string
--- @return string|nil name, string|nil realm
Compat.UnitCharacterName = CompatLib and CompatLib.UnitCharacterName or unitCharacterNameStub

--- The player's realm key: the ruleset with regional names (WoW Forever), else GetRealmName().
--- @return string|nil
Compat.RealmKey = CompatLib and CompatLib.RealmKey or realmKeyStub

--- The active Mythic+ keystone's level (C_ChallengeMode.GetActiveKeystoneInfo's first value), raw:
--- the caller reads it through NS.Secrets and runs this in pcall. Mythic+ is Retail-only
--- (clients-§4): always nil on WoW Forever.
--- @return number|nil
function Compat.KeystoneLevel()
    if not Compat.ForClient({ "retail" }) then return nil end
    local cm = C_ChallengeMode
    if not (cm and type(cm.GetActiveKeystoneInfo) == "function") then return nil end
    return (cm.GetActiveKeystoneInfo())
end

--- The tier of the delve in progress, as the objective tracker's ScenarioHeaderDelves widget writes
--- it (its tierText, raw: the caller reads it through NS.Secrets and runs this in pcall). Without the
--- visualization enum every widget of the tracker's set is asked. Delves are Retail-only
--- (clients-§4): always nil on WoW Forever. Not verified in-game (plan's smoke list).
--- @return string|nil
function Compat.DelveTierText()
    if not Compat.InDelve() then return nil end
    local wm = C_UIWidgetManager
    if not (wm and type(wm.GetObjectiveTrackerWidgetSetID) == "function"
            and type(wm.GetAllWidgetsBySetID) == "function"
            and type(wm.GetScenarioHeaderDelvesWidgetVisualizationInfo) == "function") then
        return nil
    end
    local setID = wm.GetObjectiveTrackerWidgetSetID()
    local widgets = setID and wm.GetAllWidgetsBySetID(setID)
    if type(widgets) ~= "table" then return nil end
    local vis = Enum and Enum.UIWidgetVisualizationType
    local kind = vis and vis.ScenarioHeaderDelves
    for _, w in ipairs(widgets) do
        if kind == nil or w.widgetType == kind then
            local info = wm.GetScenarioHeaderDelvesWidgetVisualizationInfo(w.widgetID)
            if type(info) == "table" and info.tierText ~= nil then return info.tierText end
        end
    end
    return nil
end

--- The PvP match's rules, each a plain boolean (false where the client has no such call): a rated
--- battleground, a rated arena, Solo Shuffle and Battleground Blitz. Solo Shuffle and rated arenas
--- are arena brackets, Retail-only (clients-§4): false on WoW Forever.
--- @return table { ratedBG, ratedArena, soloShuffle, blitz }
function Compat.PvpRules()
    local pvp = type(C_PvP) == "table" and C_PvP or {}
    local function on(name) return type(pvp[name]) == "function" and pvp[name]() == true end
    local arenas = Compat.ForClient({ "retail" })
    return {
        ratedBG     = on("IsRatedBattleground"),
        ratedArena  = arenas and on("IsRatedArena"),
        soloShuffle = arenas and on("IsSoloShuffle"),
        blitz       = on("IsRatedSoloRBG"),
    }
end

-- ---------------------------------------------------------------------------
-- The client line of `/ct probe` (modules/Probe.lua)
-- ---------------------------------------------------------------------------

--- The client's version string, build number and interface number (GetBuildInfo), or nothing where
--- the call is missing or raises.
--- @return string|nil version, string|nil build, number|nil interface
function Compat.BuildInfo()
    local fn = GetBuildInfo
    if type(fn) ~= "function" then return nil end
    local ok, version, build, _, iface = pcall(fn)
    if not ok then return nil end
    return version, build, iface
end

--- Which of the version-variant APIs the probe reports this client carries: the secrets system
--- (issecretvalue) and C_Spell's texture and info lookups.
--- @return table { secrets = boolean, spellTexture = boolean, spellInfo = boolean }
function Compat.ClientApis()
    local spell = type(C_Spell) == "table" and C_Spell or nil
    return {
        secrets      = type(issecretvalue) == "function",
        spellTexture = spell ~= nil and type(spell.GetSpellTexture) == "function",
        spellInfo    = spell ~= nil and type(spell.GetSpellInfo) == "function",
    }
end

-- ---------------------------------------------------------------------------
-- Chat and number formatting
-- ---------------------------------------------------------------------------

--- The function that sends one chat message, `(text, chatType, languageID, target)`, or nil where
--- the client has none. The caller runs it in pcall.
--- @return function|nil
function Compat.ChatSender()
    local info = C_ChatInfo
    if info and type(info.SendChatMessage) == "function" then return info.SendChatMessage end
    local bare = SendChatMessage
    if type(bare) == "function" then return bare end
    return nil
end

--- Whether the client refuses chat messages now (Midnight's chat lockdown: encounters, rated PvP);
--- false where the client has no such lockdown.
--- @return boolean
function Compat.ChatLocked()
    local info = C_ChatInfo
    if not (info and type(info.InChatMessagingLockdown) == "function") then return false end
    local ok, locked = pcall(info.InChatMessagingLockdown)
    return ok and locked == true
end

-- The client's number-formatter constructors, in the order modules/Format.lua tries them.
local FORMATTER_CONSTRUCTORS = { "CreateAbbreviatedNumberFormatter", "CreateNumericRuleFormatter" }

--- The client's number-formatter constructors that exist here, in order, as { name, make } (make
--- takes no argument and answers a new instance that takes a secret and abbreviates natively). An
--- empty list where the client has none. modules/Format.lua builds each in pcall, sets its
--- breakpoints and checks it, and uses the first that passes.
--- @return table
function Compat.NumberFormatterCandidates()
    local util = C_StringUtil
    local out = {}
    if type(util) ~= "table" then return out end
    for _, name in ipairs(FORMATTER_CONSTRUCTORS) do
        local make = util[name]
        if type(make) == "function" then out[#out + 1] = { name = name, make = make } end
    end
    return out
end

--- A StaticPopup dialog's edit box, or nil: the GetEditBox method on current clients, the editBox
--- (or EditBox) field before it.
--- @param dialog table|nil
--- @return table|nil
function Compat.PopupEditBox(dialog)
    if dialog == nil then return nil end
    if type(dialog.GetEditBox) == "function" then return dialog:GetEditBox() end
    return dialog.editBox or dialog.EditBox
end
