local _, NS = ...
-- modules/Usage.lua — what the player used in a fight (spec §7, plan Task 2.4): on-use gear (trinkets
-- and any slot with a use) and consumables (potions, flasks, phials, augment runes, oils, food), for
-- the record's `usage` and the Results detail's list. Ported from DPS Race @045f479 (modules/Usage.lua)
-- without its race: the snapshot is the fight's start, not an arm.
--
-- THE SIGNALS, STACKED (DPS Race's design, from its probe of 2026-10-26):
--   at the start    a snapshot (FIGHT_STARTED): the equipped slots whose item has a use spell, the bag
--                   consumables with a use spell and their counts, and the player's helpful auras. It
--                   rides the fight table as `fight.usageSnap`, in memory only.
--   during it       the fight's cast list (modules/Casts.lua): a cast of an on-use slot's or a
--                   consumable's spell is a use, at its time.
--   at the end      the bag counts again: a consumable whose count dropped with no cast was used, its
--                   time unknown. A fight parked while the next one starts has its end counts taken
--                   then (`fight.usageAfter`), so the next fight's potion is never the parked one's.
-- An aura at the start whose spell is a bag consumable's (a flask, a phial) was used before the pull;
-- the Well Fed aura is food, found by its spell ID (Usage.WELL_FED_SPELLS) or by the client's own name
-- for it (the name of Usage.WELL_FED_SPELL, so it matches in every client language; the English word
-- only when the client cannot name that spell). No weapon enchant is listed, and the item-cooldown compare is not used (a
-- shared cooldown made DPS Race's probe's false positive). DPS Race's early-cast give-back is gone: the
-- snapshot is taken at the fight's start, so a potion drunk before it is already out of the counts.
--
-- SECRETS. The snapshot is read at combat entry, so a value may come back secret (an aura in combat):
-- every client value passes through NS.Secrets on its way in, a sealed aura ends the aura walk, and a
-- bag stack that cannot be read makes the after counts unknown (no bag detection), never a false drop.
-- Each client function is read bare at CALL time and pcall'd.
--
-- THE RECORD (Usage.ForFight): { v = 1, used = { { itemID?, kind, slot?, times?, n, src } }, candidates
-- = { { itemID, kind, slot? } }, edited = bool }, src "cast", "bag", "buff" or "manual" (a tick the
-- player added). Detection (Usage.Detect) is pure over the snapshot, the casts and the after counts.
--
-- THE PLAYER'S EDIT (Usage.SetUsed, plan Task 4.4, from the Results detail's Usage Edit): the ticks
-- replace the used list, a detected entry keeping its times and source, and the record is marked
-- edited. A stored fight changes in the store (FIGHTS_CHANGED); a sample fight (test mode, the sim)
-- in memory only, as its note does (Results_Source.Touched).
--
-- THE HIDDEN ITEMS ("never show", spec §7): item IDs the player never wants listed, written whole
-- through the schema seam at Usage.HIDDEN_PATH as one plain string ("12345,67890"; the History page's
-- Usage tab, plan Task 4.5, and the detail's right-click in the edit). Account-wide, like the fight
-- store it filters. Detection still records a hidden item, so taking it off the list brings it back
-- on every fight that used it.

local Usage = {}
NS.Usage = Usage

local Secrets = NS.Secrets
local L = NS.L

-- The record's own format.
Usage.VERSION = 1
-- Every kind an entry may carry.
Usage.KINDS = { gear = true, potion = true, flask = true, food = true, other = true }
-- The hidden items' setting (global: the fight store it filters is).
Usage.HIDDEN_PATH = "global.usage.hidden"
-- The equipment slots a use is looked for in: every one, the tabard included (a use tabard exists).
Usage.SLOTS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
-- The bags read: the backpack, the four bags and the reagent bag.
Usage.BAGS = { 0, 1, 2, 3, 4, 5 }
-- Consumable (item class 0) subclasses by kind; any other is "other" (8 and 0 among them).
Usage.KIND_BY_SUBCLASS = { [1] = "potion", [2] = "flask", [3] = "flask", [5] = "food" }
-- How many helpful auras a snapshot's walk reads at most.
local AURA_LIMIT = 255
-- Well Fed: the spell whose name is the client's word for the buff, and the buff spell IDs known to
-- be it. The same on both clients (clients-§5: one list, picked once); unverified in game.
Usage.WELL_FED_SPELL = 19705
Usage.WELL_FED_SPELLS = { [19705] = true }

local fedName   -- the client's name for Well Fed, once read plain (false: the client cannot name it)

-- A secret answer (the read in combat) is never kept: the next look asks again.
local function wellFedName()
    if fedName == nil then
        local ok, v = pcall(NS.Compat.SpellName, Usage.WELL_FED_SPELL)
        local plain = ok and Secrets.PlainString(v) or nil
        if plain then
            fedName = plain
        elseif not Secrets.IsSealed(v) then
            fedName = false
        end
    end
    return fedName or L["Well Fed"]
end

-- Whether a start aura is Well Fed: by its plain spell ID, else by name.
local function isWellFed(aura)
    if aura.spellID and Usage.WELL_FED_SPELLS[aura.spellID] then return true end
    return aura.name ~= nil and aura.name == wellFedName()
end

-- What each item is, asked once per session ({ [itemID] = { subclass, spellID } | false }): an item's
-- class and use spell do not change. Only a definite answer is kept (a consumable whose use spell the
-- client has not loaded yet is asked again next time).
local items = {}

local lastFight   -- the last fight that started, until it ends (its end counts at the next start)

local function passResults(ok, ...)
    if ok then return ... end
    return nil
end

--- Call a client function if it exists, pcall'd. Answers its results, or nothing.
local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    return passResults(pcall(fn, ...))
end

local function api(ns, name)
    return type(ns) == "table" and ns[name] or nil
end

--- An item's use spell ID, or nil (no use, or unreadable).
local function itemSpell(itemID)
    local _, spellID = ask(api(C_Item, "GetItemSpell"), itemID)
    return Secrets.PlainNumber(spellID)
end

--- A consumable's kind by its subclass.
function Usage.KindOf(subclass)
    return Usage.KIND_BY_SUBCLASS[subclass] or "other"
end

-- ── the snapshot (client reads) ─────────────────────────────────────────────────────────────────

local function snapshotGear()
    local gear = {}
    for _, slot in ipairs(Usage.SLOTS) do
        local itemID = Secrets.PlainNumber(ask(GetInventoryItemID, "player", slot))
        local spellID = itemID and itemSpell(itemID)
        if spellID then gear[#gear + 1] = { slot = slot, itemID = itemID, spellID = spellID } end
    end
    return gear
end

-- Whether an item is a consumable (class 0) with a use spell: { subclass, spellID }, or false.
local function consumable(itemID)
    local known = items[itemID]
    if known ~= nil then return known end
    local _, _, _, _, _, classID, subclass = ask(api(C_Item, "GetItemInfoInstant"), itemID)
    classID = Secrets.PlainNumber(classID)
    if classID ~= 0 then
        if classID ~= nil then items[itemID] = false end
        return false
    end
    local spellID = itemSpell(itemID)
    if not spellID then return false end
    items[itemID] = { subclass = Secrets.PlainNumber(subclass) or 0, spellID = spellID }
    return items[itemID]
end

-- Every stack in the bags as (itemID, count), through `fn`; answers false when a stack could not be
-- read (a count that cannot be trusted).
local function eachStack(fn)
    local numSlots, itemInfo = api(C_Container, "GetContainerNumSlots"), api(C_Container, "GetContainerItemInfo")
    if not numSlots or not itemInfo then return false end
    for _, bag in ipairs(Usage.BAGS) do
        for slot = 1, Secrets.PlainNumber(ask(numSlots, bag)) or 0 do
            local info = ask(itemInfo, bag, slot)
            if info ~= nil and not Secrets.CanAccessTable(info) then return false end
            local itemID = info and Secrets.PlainNumber(info.itemID)
            local count = info and Secrets.PlainNumber(info.stackCount)
            if itemID and not count then return false end
            if itemID then fn(itemID, count) end
        end
    end
    return true
end

--- The bag counts now, { [itemID] = total }, or nil when the bags could not be read whole.
--- @return table|nil
function Usage.BagCounts()
    local counts = {}
    local ok = eachStack(function(itemID, count) counts[itemID] = (counts[itemID] or 0) + count end)
    return ok and counts or nil
end

local function snapshotBags()
    local bags = {}
    eachStack(function(itemID, count)
        local c = consumable(itemID)
        if not c then return end
        local b = bags[itemID]
        if not b then
            b = { count = 0, subclass = c.subclass, spellID = c.spellID }
            bags[itemID] = b
        end
        b.count = b.count + count
    end)
    return bags
end

local function snapshotAuras()
    local auras, get = {}, api(C_UnitAuras, "GetAuraDataByIndex")
    for i = 1, AURA_LIMIT do
        local aura = ask(get, "player", i, "HELPFUL")
        if Secrets.IsSealed(aura) or not Secrets.CanAccessTable(aura) then break end
        auras[#auras + 1] = { spellID = Secrets.PlainNumber(aura.spellId), name = Secrets.PlainString(aura.name) }
    end
    return auras
end

--- What the player could use and has on, now. Held in memory, never stored.
--- @return table snap  { gear = { { slot, itemID, spellID } }, bags = { [itemID] = { count, subclass,
---                     spellID } }, auras = { { spellID?, name? } } }
function Usage.Snapshot()
    return { gear = snapshotGear(), bags = snapshotBags(), auras = snapshotAuras() }
end

-- ── detection (pure) ────────────────────────────────────────────────────────────────────────────

local function sortedKeys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- The bag consumables by use spell: { [spellID] = { itemID, ... } } in item order.
local function bagsBySpell(bags)
    local out = {}
    for _, itemID in ipairs(sortedKeys(bags)) do
        local id = bags[itemID].spellID
        out[id] = out[id] or {}
        out[id][#out[id] + 1] = itemID
    end
    return out
end

-- How many of `itemID` left the bags between the start and the end (0 when unknown).
local function drop(snap, after, itemID)
    if type(after) ~= "table" then return 0 end
    return math.max(0, snap.bags[itemID].count - (after[itemID] or 0))
end

-- Which of the items sharing a use spell a cast used: the first whose count dropped, else the first.
local function pickItem(snap, after, list)
    for _, itemID in ipairs(list) do
        if drop(snap, after, itemID) > 0 then return itemID end
    end
    return list[1]
end

-- The player's casts of on-use and consumable spells: { [itemID] = { t, ... } }.
local function castTimes(snap, casts, after)
    local gearBy, bagBy, times = {}, bagsBySpell(snap.bags), {}
    for _, g in ipairs(snap.gear) do gearBy[g.spellID] = gearBy[g.spellID] or g.itemID end
    for _, c in ipairs(casts or {}) do
        local id = c.spellID
        local itemID = c.unit ~= "pet" and (gearBy[id] or (bagBy[id] and pickItem(snap, after, bagBy[id])))
        if itemID then
            times[itemID] = times[itemID] or {}
            table.insert(times[itemID], c.t)
        end
    end
    return times
end

local function castEntry(itemID, kind, slot, times)
    return { itemID = itemID, kind = kind, slot = slot, times = times, n = #times, src = "cast" }
end

-- The gear used, in slot order, then the consumables cast, in item order.
local function detectCasts(snap, times, used)
    for _, g in ipairs(snap.gear) do
        local t = times[g.itemID]
        if t and not used[g.itemID] then used[g.itemID] = castEntry(g.itemID, "gear", g.slot, t) end
    end
    for _, itemID in ipairs(sortedKeys(snap.bags)) do
        local t = times[itemID]
        if t and not used[itemID] then used[itemID] = castEntry(itemID, Usage.KindOf(snap.bags[itemID].subclass), nil, t) end
    end
end

-- A consumable whose count dropped with no cast: used n times, the time unknown.
local function detectBags(snap, after, used)
    for _, itemID in ipairs(sortedKeys(snap.bags)) do
        local n = drop(snap, after, itemID)
        if n > 0 and not used[itemID] then
            used[itemID] = { itemID = itemID, kind = Usage.KindOf(snap.bags[itemID].subclass), n = n, src = "bag" }
        end
    end
end

-- The auras at the start: a consumable's own buff (a flask), and Well Fed (food, no item).
local function detectAuras(snap, used, list)
    local bagBy, fed = bagsBySpell(snap.bags), false
    for _, aura in ipairs(snap.auras) do
        local found = aura.spellID and bagBy[aura.spellID]
        local itemID = found and found[1]
        if itemID and not used[itemID] then
            used[itemID] = { itemID = itemID, kind = Usage.KindOf(snap.bags[itemID].subclass), n = 1, src = "buff" }
            list[#list + 1] = used[itemID]
        elseif not fed and isWellFed(aura) then
            fed = true
            list[#list + 1] = { kind = "food", n = 1, src = "buff" }
        end
    end
end

-- The detected entries in order: gear, consumables cast, bag drops, then the start's auras.
local function ordered(snap, used, extra)
    local list = {}
    for _, g in ipairs(snap.gear) do
        local e = used[g.itemID]
        if e and e.kind == "gear" and e.slot == g.slot then list[#list + 1] = e end
    end
    for _, src in ipairs({ "cast", "bag" }) do
        for _, itemID in ipairs(sortedKeys(snap.bags)) do
            local e = used[itemID]
            if e and e.src == src and e.kind ~= "gear" then list[#list + 1] = e end
        end
    end
    for _, e in ipairs(extra) do list[#list + 1] = e end
    return list
end

--- What was used, detected from the start's snapshot, the fight's casts (modules/Casts.lua's list)
--- and the bag counts at its end (nil when unreadable: no bag detection).
--- @return table used  { { itemID?, kind, slot?, times?, n, src }, ... }
function Usage.Detect(snap, casts, after)
    local used, extra = {}, {}
    detectCasts(snap, castTimes(snap, casts, after), used)
    detectBags(snap, after, used)
    detectAuras(snap, used, extra)
    return ordered(snap, used, extra)
end

--- Every on-use gear item (slot order) and every bag consumable with a use spell (item order) at the
--- start.
--- @return table candidates  { { itemID, kind, slot? }, ... }
function Usage.Candidates(snap)
    local out = {}
    for _, g in ipairs(snap.gear) do out[#out + 1] = { itemID = g.itemID, kind = "gear", slot = g.slot } end
    for _, itemID in ipairs(sortedKeys(snap.bags)) do
        out[#out + 1] = { itemID = itemID, kind = Usage.KindOf(snap.bags[itemID].subclass) }
    end
    return out
end

--- The usage record, or nil without a snapshot.
--- @return table|nil record  { v, used, candidates, edited }
function Usage.Build(snap, casts, after)
    if type(snap) ~= "table" then return nil end
    return { v = Usage.VERSION, used = Usage.Detect(snap, casts, after), candidates = Usage.Candidates(snap),
             edited = false }
end

-- ── a fight's own ───────────────────────────────────────────────────────────────────────────────

--- The fight's usage record (the recorder, after combat): its start's snapshot, its casts, and its
--- end counts (taken when the next fight started, else now). nil when the fight has no snapshot.
--- @param fight table
--- @param casts table|nil  modules/Casts.lua's list
--- @return table|nil record
function Usage.ForFight(fight, casts)
    if type(fight) ~= "table" then return nil end
    local after = fight.usageAfter
    if after == nil then after = Usage.BagCounts() end
    return Usage.Build(fight.usageSnap, casts, after)
end

local function onStarted(_, fight)
    if type(fight) ~= "table" then return end
    -- The fight before is parked or split off: its end counts are these.
    if lastFight and lastFight ~= fight and lastFight.usageAfter == nil then
        lastFight.usageAfter = Usage.BagCounts() or false
    end
    lastFight = fight
    fight.usageSnap = Usage.Snapshot()
end

local function onEnded(_, fight)
    if fight == lastFight then lastFight = nil end
end

--- The lifecycle's stand-down: the last fight is forgotten (its table goes with the fight).
function Usage.Suspend()
    lastFight = nil
end

-- ── the player's edit ───────────────────────────────────────────────────────────────────────────

-- Whether a detected entry is the one a tick names: by item, else food by kind; in each case in the
-- tick's slot when it names one (a pair of one trinket shares one item ID), so an entry with no slot or
-- another never answers it.
local function same(e, tick)
    if tick.slot ~= nil and e.slot ~= tick.slot then return false end
    if tick.itemID then return e.itemID == tick.itemID end
    return e.itemID == nil and e.kind == tick.kind
end

-- The first entry of `list` the tick names that `taken` has not had yet; marks it taken.
local function find(list, tick, taken)
    for i, e in ipairs(list or {}) do
        if not taken[i] and type(e) == "table" and same(e, tick) then
            taken[i] = true
            return e
        end
    end
    return nil
end

-- What a ticked-again entry with no item had been detected as: only detection lists food.
local RETICKED = { food = "buff" }

-- A ticked entry nothing detected: used once, no time.
local function fresh(tick)
    local src = tick.itemID == nil and RETICKED[tick.kind] or "manual"
    return { itemID = tick.itemID, kind = tick.kind, slot = tick.slot, n = 1, src = src }
end

-- An unticked food (no item) has no candidate to stand for it: it joins the candidates, so its row
-- stays in the list and can be ticked again.
local function keepRows(u, taken)
    if type(u.candidates) ~= "table" then u.candidates = {} end
    for i, e in ipairs(type(u.used) == "table" and u.used or {}) do
        if not taken[i] and type(e) == "table" and e.itemID == nil and RETICKED[e.kind]
                and not find(u.candidates, e, {}) then
            u.candidates[#u.candidates + 1] = { kind = e.kind, slot = e.slot }
        end
    end
end

-- A tick from the window with its plain fields only, or nil.
local function clean(tick)
    if type(tick) ~= "table" then return nil end
    local kind = Secrets.PlainString(tick.kind)
    return { itemID = Secrets.PlainNumber(tick.itemID), slot = Secrets.PlainNumber(tick.slot),
             kind = Usage.KINDS[kind] and kind or "other" }
end

--- Replace a fight's used list with the player's ticks: an entry already detected keeps its times and
--- source (each detected entry answers one tick, matched by item and by slot); a newly ticked one is
--- "manual", used once, no time, except food ticked again, which keeps what it was detected as. An
--- unticked food joins the candidates, so its row stays. Marks the record edited and announces the
--- change: FIGHTS_CHANGED for a stored fight, the sample's own redraw for a sample one.
--- @param record table
--- @param list table  { { itemID?, kind, slot? }, ... }
--- @return boolean stored
function Usage.SetUsed(record, list)
    local u = type(record) == "table" and record.usage
    if type(u) ~= "table" or type(list) ~= "table" then return false end
    local out, taken = {}, {}
    for _, raw in ipairs(list) do
        local tick = clean(raw)
        if tick then out[#out + 1] = find(u.used, tick, taken) or fresh(tick) end
    end
    keepRows(u, taken)
    u.used, u.edited = out, true
    local Source = NS.ResultsSource
    if Source and Source.IsMock() then
        Source.Touched()
    else
        NS.SendBus(NS.MSG.FIGHTS_CHANGED)
    end
    return true
end

-- ── the hidden items ────────────────────────────────────────────────────────────────────────────

--- The hidden items' IDs in `text` ("12345, 67890"), ascending and each once; nil when `text` is not
--- a string or holds anything but positive whole numbers between the commas. Pure.
--- @return table|nil ids
function Usage.ParseHidden(text)
    if type(text) ~= "string" then return nil end
    local ids, seen = {}, {}
    for token in (text .. ","):gmatch("([^,]*),") do
        local word = token:match("^%s*(.-)%s*$")
        if word ~= "" then
            local id = word:match("^%d+$") and tonumber(word)
            if not id or id < 1 then return nil end
            if not seen[id] then seen[id], ids[#ids + 1] = true, id end
        end
    end
    table.sort(ids)
    return ids
end

-- The parsed list of the last stored text, so a redraw parses it once.
local hiddenText, hiddenList, hiddenSet

local function readHidden()
    local text = NS.GetSetting(Usage.HIDDEN_PATH)
    if text ~= hiddenText or not hiddenList then
        hiddenText, hiddenList, hiddenSet = text, Usage.ParseHidden(text) or {}, {}
        for _, id in ipairs(hiddenList) do hiddenSet[id] = true end
    end
    return hiddenList, hiddenSet
end

--- The hidden items' IDs, ascending. A copy.
function Usage.HiddenList()
    local out = {}
    for i, id in ipairs((readHidden())) do out[i] = id end
    return out
end

--- The hidden items as a set, { [itemID] = true }. Read only.
function Usage.HiddenSet()
    local _, set = readHidden()
    return set
end

--- Whether a used entry or a candidate is listed: never a hidden item, never an enchant entry.
--- @param e table
--- @param hidden table|nil  Usage.HiddenSet() (read now when nil)
function Usage.Shown(e, hidden)
    if type(e) ~= "table" or e.kind == "enchant" then return false end
    return not (e.itemID and (hidden or Usage.HiddenSet())[e.itemID])
end

--- The stored text for `ids`: ascending, comma-separated ("201,6948"). Sorts `ids` in place.
function Usage.JoinHidden(ids)
    table.sort(ids)
    local words = {}
    for i, id in ipairs(ids) do words[i] = tostring(id) end
    return table.concat(words, ",")
end

--- The row's normalize: `text` as Usage.JoinHidden writes it, or nil (refused) when it does not parse.
function Usage.NormalizeHidden(text)
    local ids = Usage.ParseHidden(text)
    return ids and Usage.JoinHidden(ids) or nil
end

local function writeHidden(ids)
    return NS.SetByPath(Usage.HIDDEN_PATH, Usage.JoinHidden(ids))
end

--- Hide an item everywhere the usage is shown (the setting, written whole through the seam).
--- @return boolean changed
function Usage.Hide(itemID)
    itemID = Secrets.PlainNumber(itemID)
    if not itemID or itemID < 1 or itemID % 1 ~= 0 or Usage.HiddenSet()[itemID] then return false end
    local ids = Usage.HiddenList()
    ids[#ids + 1] = itemID
    return writeHidden(ids) and true or false
end

--- Show a hidden item again.
--- @return boolean changed
function Usage.Unhide(itemID)
    if not Usage.HiddenSet()[itemID] then return false end
    local ids = {}
    for _, id in ipairs(Usage.HiddenList()) do
        if id ~= itemID then ids[#ids + 1] = id end
    end
    return writeHidden(ids) and true or false
end

-- Append each entry's item ID in `entries` to `out`, once.
local function appendItemIDs(entries, out, seen)
    for _, e in ipairs(type(entries) == "table" and entries or {}) do
        local id = type(e) == "table" and e.itemID
        if type(id) == "number" and not seen[id] then seen[id], out[#out + 1] = true, id end
    end
end

--- Every item the stored fights list (used or a candidate), each once, newest fight first: the names
--- the History page's ID list can resolve and suggest (plan Task 4.5; the client has no item-name
--- search).
--- @return table ids
function Usage.KnownItems()
    local out, seen = {}, {}
    for _, record in ipairs(NS.Recorder.List()) do
        local u = type(record.usage) == "table" and record.usage or nil
        if u then
            appendItemIDs(u.used, out, seen)
            appendItemIDs(u.candidates, out, seen)
        end
    end
    return out
end

local busTarget = NS.NewBusTarget()
if busTarget then
    busTarget:RegisterMessage(NS.MSG.FIGHT_STARTED, onStarted)
    busTarget:RegisterMessage(NS.MSG.FIGHT_ENDED, onEnded)
end
