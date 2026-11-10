local _, NS = ...
-- modules/Loadouts.lua — the gear and the talents a fight was fought with (spec §5 record size, §7
-- gear view, plan Task 2.4, v0.2 plan Task A3). Ported from DPS Race @045f479 (modules/Loadouts.lua
-- and its Recorder's SnapshotLoadout), reshaped to the spec's record: both are stored once, the record
-- holding a key to each. The talent loadouts live in db.global.loadouts (`record.loadout`), the
-- equipment sets in db.global.gearSets (`record.gearSet`).
--
-- THE SNAPSHOT (Loadouts.Snapshot): every equipped item but the shirt and the tabard (cosmetic), each
-- as its item string with the link's color, name and trailing empty fields trimmed
-- ("212001::::::::80:267::6:2:10390:1540"; about a third of a full link), and the active talent
-- loadout: its spec, name (the player's saved loadout's, else the active config's), hero tree and
-- import string. Each client value passes through NS.Secrets; a sealed one is absent. Each client
-- function is read bare at CALL time and pcall'd. FIGHT_STARTED takes the talents only, as
-- `fight.loadout`, and the gear set current at the pull as `fight.gearSet` (D10).
--
-- THE EQUIPMENT SETS. Loadouts.Recon reads the gear and interns it as the CURRENT set: the same gear
-- finds its stored set, other gear (another item, an enchant, a gem, an upgrade) is a new one. It runs
-- on PLAYER_ENTERING_WORLD (login, /reload, a zone change: whatever changed while the addon was not
-- watching), on PLAYER_EQUIPMENT_CHANGED and on UNIT_INVENTORY_CHANGED for the player, each through
-- ONE coalesced AceTimer on the addon object (RECON_DELAY): a set swap fires the equipment event per
-- slot, and the burst interns one set at its end. A recon that ran in combat (a weapon swap), where a
-- link may come back sealed and be left out, is read again at PLAYER_REGEN_ENABLED. The stand-up arms one too, and the pull runs a
-- pending one at once, so a swap just before it counts. With no set known at the pull (links not yet
-- cached), the pull reconciles itself. The events are registered by Loadouts.Sync (from
-- NS.RegisterGameEvents) and dropped by Suspend, with the timer (core/LifecycleSetup.lua).
--
-- THE KEY is a small pure string hash (djb2, as eight hex digits): of the import string for a
-- loadout, of the canonical gear (each "slot=item" in slot order, joined by \31) for a set. Two
-- different entries that hash alike are told apart by their import string or canonical form, and the
-- later one takes the next free "<hash>-<n>". ORPHANS: a loadout or a set no stored fight refers to is
-- dropped by Sweep (the retention's purge and a delete call it, plan Task 2.5); the current set and
-- the live fight's are kept.

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

-- Drop every key of `s` not in `used`; answers how many went.
local function dropUnused(s, used)
    local n = 0
    for key in pairs(s) do
        if not used[key] then
            s[key] = nil
            n = n + 1
        end
    end
    return n
end

-- The keys `field` names across `fights`.
local function usedBy(fights, field)
    local used = {}
    for _, rec in pairs(fights) do
        if type(rec) == "table" and rec[field] ~= nil then used[rec[field]] = true end
    end
    return used
end

local sweepGear

--- Drop every stored loadout and every equipment set no fight in `fights` refers to ({ [id] = record },
--- by `record.loadout` and `record.gearSet`; db.global.fights when nil). The current set and the live
--- fight's are kept. Drops nothing when there is no fight store to read.
--- @return number dropped
function Loadouts.Sweep(fights)
    if fights == nil then fights = NS.db and NS.db.global and NS.db.global.fights end
    local s = store()
    if not s or type(fights) ~= "table" then return 0 end
    local n = dropUnused(s, usedBy(fights, "loadout"))
    if n > 0 then debug("dropped %d orphaned loadout(s)", n) end
    return n + sweepGear(fights)
end

-- ── the equipment sets ──────────────────────────────────────────────────────────────────────────

--- How long a recon waits for the rest of a burst (seconds).
Loadouts.RECON_DELAY = 0.5

local currentSet   -- the key of the set the player wears, nil before the first recon reads one

--- db.global.gearSets, or nil before the DB exists.
local function gearStore()
    local g = NS.db and NS.db.global
    if not g then return nil end
    if type(g.gearSets) ~= "table" then g.gearSets = {} end
    return g.gearSets
end

-- A set as the store keeps it, a plain { [slot] = item string } over GEAR_SLOTS, and its canonical
-- form; nil without one plain item.
local function setOf(gear)
    if type(gear) ~= "table" or Secrets.IsSealed(gear) then return nil end
    local set, parts = {}, {}
    for _, slot in ipairs(Loadouts.GEAR_SLOTS) do
        local item = Secrets.PlainString(gear[slot])
        if item and item ~= "" then
            set[slot] = item
            parts[#parts + 1] = slot .. "=" .. item
        end
    end
    if #parts == 0 then return nil end
    return set, table.concat(parts, "\31")
end

local function canonOf(set)
    local _, canon = setOf(set)
    return canon
end

--- Store an equipment set once ({ [slot] = trimmed item string }) and answer its key; nil with no
--- item to store.
--- @param gear table|nil
--- @return string|nil key
function Loadouts.StoreGear(gear)
    local s = gearStore()
    local set, canon = setOf(gear)
    if not s or not set then return nil end
    local base = Loadouts.Hash(canon)
    local key, n = base, 1
    while s[key] ~= nil do
        if canonOf(s[key]) == canon then return key end
        n = n + 1
        key = base .. "-" .. n
    end
    s[key] = set
    debug("gear set %s stored", key)
    return key
end

--- The stored set under `key`: { [slot] = item string }, or nil.
function Loadouts.GetGear(key)
    local s = gearStore()
    local e = s and Secrets.IsSafeKey(key) and s[key] or nil
    return type(e) == "table" and e or nil
end

--- A record's gear: its stored set (`record.gearSet`), else the gear it carries inline (the sample
--- fights, modules/MockFights.lua); nil when it has neither.
--- @param record table|nil
--- @return table|nil gear  { [slot] = item string }
function Loadouts.GearOf(record)
    if type(record) ~= "table" then return nil end
    local set = record.gearSet ~= nil and Loadouts.GetGear(record.gearSet) or nil
    if set then return set end
    return type(record.gear) == "table" and record.gear or nil
end

--- The key of the set the player wears now, as the last recon found it; nil before one read any.
function Loadouts.CurrentGearSet()
    return currentSet
end

--- Read the gear and intern it as the current set. Answers its key (nil when nothing was readable).
--- @return string|nil key
function Loadouts.Recon()
    currentSet = Loadouts.StoreGear(snapshotGear())
    return currentSet
end

--- How many sets the store holds.
function Loadouts.GearCount()
    local n = 0
    for _ in pairs(gearStore() or {}) do n = n + 1 end
    return n
end

sweepGear = function(fights)
    local s = gearStore()
    if not s then return 0 end
    local used = usedBy(fights, "gearSet")
    if currentSet then used[currentSet] = true end
    local live = NS.Fight and NS.Fight.Current and NS.Fight.Current()
    if type(live) == "table" and live.gearSet ~= nil then used[live.gearSet] = true end
    local n = dropUnused(s, used)
    if n > 0 then debug("dropped %d orphaned gear set(s)", n) end
    return n
end

--- Test seam: set the current set's key.
function Loadouts.__setCurrent(key)
    currentSet = key
end

-- ── the event wiring ────────────────────────────────────────────────────────────────────────────

--- The client's events a recon follows. UNIT_INVENTORY_CHANGED is per unit, the player's only.
--- PLAYER_REGEN_ENABLED asks for one only when a recon ran in combat, where a link may be sealed.
Loadouts.RECON_EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED" }

local eventFrame, reconTimer
local owed   -- a recon ran in combat: read the gear again once combat ends

local function cancelRecon()
    local addon = NS.addon
    if reconTimer and addon and addon.CancelTimer then addon:CancelTimer(reconTimer) end
    reconTimer = nil
end

local function runRecon()
    reconTimer = nil
    if NS.IsStoodDown and NS.IsStoodDown() then return end
    if Secrets.PlainTruth(ask(InCombatLockdown)) == true then owed = true end
    Loadouts.Recon()
end

--- Ask for a recon RECON_DELAY from now; a second ask while one is pending joins it.
function Loadouts.ScheduleRecon()
    if reconTimer then return end
    local addon = NS.addon
    if not (addon and addon.ScheduleTimer) then return end
    reconTimer = addon:ScheduleTimer(runRecon, Loadouts.RECON_DELAY)
end

local function onEvent(_, event)
    if NS.IsStoodDown and NS.IsStoodDown() then return end
    if event == "PLAYER_REGEN_ENABLED" then
        if not owed then return end
        owed = nil
    end
    Loadouts.ScheduleRecon()
end

--- Register the recon's events and ask for one (at login and every stand-up, from
--- NS.RegisterGameEvents). Cheap again when already registered.
function Loadouts.Sync()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", onEvent)
    end
    eventFrame:UnregisterAllEvents()
    for _, event in ipairs(Loadouts.RECON_EVENTS) do
        NS.SafeRegisterEvent(eventFrame, event, nil, NS.rejectedEvents)
    end
    NS.SafeRegisterUnitEvent(eventFrame, "UNIT_INVENTORY_CHANGED", NS.rejectedEvents, "player")
    Loadouts.ScheduleRecon()
end

--- The lifecycle's stand-down: no registration, no timer. The current set stays known.
function Loadouts.Suspend()
    if eventFrame then eventFrame:UnregisterAllEvents() end
    cancelRecon()
end

-- The pull: the talents now, and the gear set current at it (a pending recon runs first).
local function onFightStarted(_, fight)
    if type(fight) ~= "table" then return end
    local talents = snapshotTalents()
    fight.loadout = talents and { talents = talents } or nil
    if reconTimer then
        cancelRecon()
        Loadouts.Recon()
    end
    fight.gearSet = Loadouts.CurrentGearSet() or Loadouts.Recon()
end

local busTarget = NS.NewBusTarget()
if busTarget then
    busTarget:RegisterMessage(NS.MSG.FIGHT_STARTED, onFightStarted)
end
