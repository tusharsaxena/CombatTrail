local _, NS = ...
-- modules/Loadouts.lua — the gear and the talents a fight was fought with (spec §5 record size, §7
-- gear view, plan Task 2.4). Ported from DPS Race @045f479 (modules/Loadouts.lua and its Recorder's
-- SnapshotLoadout), reshaped to the spec's record: the gear rides each record as trimmed item strings,
-- and only the talent loadout is stored once, in db.global.loadouts, the record holding its hash.
--
-- THE SNAPSHOT (Loadouts.Snapshot, at FIGHT_STARTED, riding the fight table as `fight.loadout`): every
-- equipped item but the shirt and the tabard (cosmetic), each as its item string with the link's
-- colour, name and trailing empty fields trimmed ("212001::::::::80:267::6:2:10390:1540"; about a
-- third of a full link), and the active talent loadout: its spec, name (the player's saved loadout's,
-- else the active config's), hero tree and import string. Each client value passes through NS.Secrets;
-- a sealed one is absent. Each client function is read bare at CALL time and pcall'd.
--
-- THE KEY is a small pure string hash (djb2, as eight hex digits) of the import string. Two different
-- loadouts that hash alike are told apart by their import strings, and the later one takes the next
-- free "<hash>-<n>". ORPHANS: a loadout no stored fight refers to is dropped by Sweep (the retention's
-- purge and a delete call it, plan Task 2.5).

local Loadouts = {}
NS.Loadouts = Loadouts

local Secrets = NS.Secrets

-- The equipment slots a snapshot records, in slot order: 1-18 without the shirt (4).
Loadouts.GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Loadouts", fmt, ...) end
end

local function passResults(ok, ...)
    if ok then return ... end
    return nil
end

local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    return passResults(pcall(fn, ...))
end

local function api(ns, name)
    return type(ns) == "table" and ns[name] or nil
end

-- ── the item strings ────────────────────────────────────────────────────────────────────────────

--- An item link's item string without its "item:" prefix and trailing empty fields; nil for anything
--- that is not an item link.
--- @param link string|nil
--- @return string|nil
function Loadouts.TrimItem(link)
    if type(link) ~= "string" then return nil end
    local body = link:match("item:([%d:%-]+)")
    if not body then return nil end
    body = body:gsub(":+$", "")
    return body ~= "" and body or nil
end

--- The client's item string for a trimmed one (what GetItemInfo and a tooltip take).
function Loadouts.ItemString(trimmed)
    return "item:" .. tostring(trimmed)
end

-- ── the snapshot ────────────────────────────────────────────────────────────────────────────────

local function snapshotGear()
    local gear, any = {}, false
    for _, slot in ipairs(Loadouts.GEAR_SLOTS) do
        local item = Loadouts.TrimItem(Secrets.PlainString(ask(GetInventoryItemLink, "player", slot)))
        if item then
            gear[slot] = item
            any = true
        end
    end
    return any and gear or nil
end

local function currentSpecID()
    local Compat = NS.Compat
    local specIndex = Secrets.PlainNumber(ask(Compat.GetSpecialization))
    if not specIndex then return nil end
    return Secrets.PlainNumber((ask(Compat.GetSpecializationInfo, specIndex)))
end

-- A trait config's name, or nil.
local function configName(traits, id)
    if type(id) ~= "number" then return nil end
    local info = ask(traits.GetConfigInfo, id)
    return Secrets.CanAccessTable(info) and Secrets.PlainString(info.name) or nil
end

-- The hero talent tree: its SubTreeID and its name, read while its config is the active one.
local function heroOf(t, talents, traits, configID)
    t.heroSpecID = Secrets.PlainNumber(ask(talents.GetActiveHeroTalentSpec))
    if not t.heroSpecID then return end
    local info = ask(traits.GetSubTreeInfo, configID, t.heroSpecID)
    t.heroName = Secrets.CanAccessTable(info) and Secrets.PlainString(info.name) or nil
end

--- The active talent loadout: { specID, name, heroSpecID, heroName, importString }, nil without the
--- APIs or an active config.
local function snapshotTalents()
    local talents, traits = C_ClassTalents, C_Traits
    if type(talents) ~= "table" or type(traits) ~= "table" then return nil end
    local configID = Secrets.PlainNumber(ask(talents.GetActiveConfigID))
    if not configID then return nil end
    local specID = currentSpecID()
    local t = { specID = specID }
    local saved = specID and Secrets.PlainNumber(ask(talents.GetLastSelectedSavedConfigID, specID))
    t.name = configName(traits, saved) or configName(traits, configID)
    heroOf(t, talents, traits, configID)
    t.importString = Secrets.PlainString(ask(api(traits, "GenerateImportString"), configID))
    if t.importString == "" then t.importString = nil end
    return t
end

--- What the player is wearing and the talents they run.
--- @return table|nil loadout  { gear = { [slot] = itemString }|nil, talents = { specID, name, heroSpecID,
---                            heroName, importString }|nil }; nil when neither could be read
function Loadouts.Snapshot()
    local gear, talents = snapshotGear(), snapshotTalents()
    if not gear and not talents then return nil end
    return { gear = gear, talents = talents }
end

-- ── the talent store ────────────────────────────────────────────────────────────────────────────

--- djb2 over `s`, as eight lowercase hex digits.
--- @param s string
--- @return string
function Loadouts.Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    -- Two 16-bit halves: %x converts through a C long, 32 bits on 64-bit Windows, so a value of
    -- 2^31 or more would not format as itself.
    return ("%04x%04x"):format(math.floor(h / 65536), h % 65536)
end

--- db.global.loadouts, or nil before the DB exists.
local function store()
    local g = NS.db and NS.db.global
    if not g then return nil end
    if type(g.loadouts) ~= "table" then g.loadouts = {} end
    return g.loadouts
end

-- A loadout as the store keeps it: its plain fields only.
local function entryOf(talents)
    if type(talents) == "string" then talents = { importString = talents } end
    if type(talents) ~= "table" then return nil end
    local s = Secrets.PlainString(talents.importString)
    if not s or s == "" then return nil end
    return { importString = s, specID = Secrets.PlainNumber(talents.specID), name = Secrets.PlainString(talents.name),
             heroSpecID = Secrets.PlainNumber(talents.heroSpecID), heroName = Secrets.PlainString(talents.heroName) }
end

--- Store a talent loadout once (a snapshot's `talents`, or a bare import string) and answer its key;
--- nil with no import string to store.
--- @param talents table|string|nil
--- @return string|nil key
function Loadouts.Store(talents)
    local s, entry = store(), entryOf(talents)
    if not s or not entry then return nil end
    local base = Loadouts.Hash(entry.importString)
    local key, n = base, 1
    while s[key] ~= nil do
        if type(s[key]) == "table" and s[key].importString == entry.importString then return key end
        n = n + 1
        key = base .. "-" .. n
    end
    s[key] = entry
    return key
end

--- The stored loadout under `key`: { importString, specID?, name?, heroSpecID?, heroName? }, or nil.
function Loadouts.Get(key)
    local s = store()
    local e = s and key ~= nil and s[key] or nil
    return type(e) == "table" and e or nil
end

--- How many loadouts the store holds.
function Loadouts.Count()
    local n = 0
    for _ in pairs(store() or {}) do n = n + 1 end
    return n
end

--- Drop every stored loadout no fight in `fights` refers to ({ [id] = record }, by `record.loadout`;
--- db.global.fights when nil). Drops nothing when there is no fight store to read.
--- @return number dropped
function Loadouts.Sweep(fights)
    if fights == nil then fights = NS.db and NS.db.global and NS.db.global.fights end
    local s = store()
    if not s or type(fights) ~= "table" then return 0 end
    local used = {}
    for _, rec in pairs(fights) do
        if type(rec) == "table" and rec.loadout ~= nil then used[rec.loadout] = true end
    end
    local n = 0
    for key in pairs(s) do
        if not used[key] then
            s[key] = nil
            n = n + 1
        end
    end
    if n > 0 then debug("dropped %d orphaned loadout(s)", n) end
    return n
end

local busTarget = NS.NewBusTarget()
if busTarget then
    busTarget:RegisterMessage(NS.MSG.FIGHT_STARTED, function(_, fight)
        if type(fight) == "table" then fight.loadout = Loadouts.Snapshot() end
    end)
end
