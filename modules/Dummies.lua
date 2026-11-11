local _, NS = ...
-- modules/Dummies.lua — the training dummies (race plan Task A2, race spec §9): the client's seed
-- (defaults/Dummies.lua), the player's own list on top of it, and what the game said about each
-- creature `/ct dummy` captured. Ported from DPS Race @f8078c7 (defaults/Dummies.lua's lookups and
-- modules/DummyList.lua) into the core, on BOTH clients: a dummy on either list makes a fight "dummy"
-- content (modules/Identity.lua) with Race mode off and on WoW Forever too.
--
-- THE ROW. One plain string, the profile's `dummies.custom`, written WHOLE through the seam
-- (NS.SetByPath) as the Usage list is (modules/Usage.lua), so the CLI's get/set/reset and the History
-- page's Defaults reach it like any row: "243300:cleave,-243205", ascending by creature ID.
-- `id:category` marks a creature as a dummy; `-id` switches a built-in off. A built-in is never
-- recategorized. A creature added without a category is single target.
--
-- READ TIME. Lookup reads this list each time it is asked (one parse cached by the stored text), so a
-- change, or a profile switch, answers at once. A fight's content is decided once, at
-- Identity.Resolve, and stays frozen in its record (race plan ruling X8); a race's dummy kind is read
-- through CategoryOf by creature ID at read time.
--
-- THE CAPTURES. `global.dummies.captures[creatureID]`: data, not a setting, beside the fight store
-- (global, because a creature is the same on every profile). Written by Capture (`/ct dummy add` and
-- `capture`, the tab's Add your target), never by a fight. A sealed field is left out.
--
-- SECRETS. A creature ID reaches a table key only through NS.Secrets.IsSafeKey or PlainNumber; every
-- client read passes NS.Secrets and is pcall'd, so a sealed or missing answer is an absent field.

local Dummies = {}
NS.Dummies = Dummies

local Secrets = NS.Secrets
local L = NS.L

Dummies.PATH = "dummies.custom"
Dummies.DEFAULT = NS.defaults.profile.dummies.custom

--- The categories a dummy can be given, in display order. A creature that is no dummy has none; its
--- label is Other (Dummies.Label).
Dummies.CATEGORIES = { "single", "cleave", "dungeoneer", "boss", "pvp" }
local KIND = {}
for _, k in ipairs(Dummies.CATEGORIES) do KIND[k] = true end

local LABELS = {
    single = L["Single target"], cleave = L["Cleave"], dungeoneer = L["Dungeoneer"],
    boss = L["Boss-level"], pvp = L["PvP"], other = L["Other"],
}

--- The largest creature ID a list entry takes: above it a number has no integer form to write back.
Dummies.MAX_ID = 2 ^ 31 - 1

--- A category's display label; an unknown key, or none, labels as Other.
--- @param category string|nil
--- @return string
function Dummies.Label(category)
    return LABELS[category] or LABELS.other
end

local function seed() return NS.DUMMY_SEED end
local function builtIn(id) return seed()[id] ~= nil end

--- The client's seed entry for a creature ID, a fresh copy, whatever the player's list says.
--- @return table|nil  { name, category }
function Dummies.BuiltIn(id)
    if not Secrets.IsSafeKey(id) then return nil end
    local d = seed()[id]
    return d and { name = d.name, category = d.category } or nil
end

-- ── the stored text ─────────────────────────────────────────────────────────────────────────────

-- One token of the stored text as an entry, or nil when it does not parse.
local function parseToken(word)
    local hid = word:match("^%-(%d+)$")
    local num, kind = word:match("^(%d+)%s*:%s*(%a+)$")
    local id = tonumber(hid or num)
    if not id or id < 1 or id > Dummies.MAX_ID or (num and not KIND[kind]) then return nil end
    return hid and { id = id, hidden = true } or { id = id, category = kind }
end

--- The entries in `text`, ascending by creature ID and each ID once (the last one written wins), as
--- { id, category } for a dummy and { id, hidden = true } for a switched-off built-in; nil when `text`
--- is not a string or an entry does not parse. Pure.
--- @return table|nil entries
function Dummies.Parse(text)
    if type(text) ~= "string" then return nil end
    local byId = {}
    for token in (text .. ","):gmatch("([^,]*),") do
        local word = token:match("^%s*(.-)%s*$"):lower()
        if word ~= "" then
            local e = parseToken(word)
            if not e then return nil end
            byId[e.id] = e
        end
    end
    local out = {}
    for _, e in pairs(byId) do out[#out + 1] = e end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- `entries` without what cannot apply: a custom entry for a built-in, a hide for a non-built-in.
local function applicable(entries)
    local out = {}
    for _, e in ipairs(entries) do
        if (e.hidden and builtIn(e.id)) or (not e.hidden and not builtIn(e.id)) then out[#out + 1] = e end
    end
    return out
end

--- The stored text for `entries`: ascending, comma-separated ("243300:cleave,-243205").
function Dummies.Join(entries)
    table.sort(entries, function(a, b) return a.id < b.id end)
    local words = {}
    for i, e in ipairs(entries) do
        words[i] = e.hidden and ("-" .. e.id) or (e.id .. ":" .. e.category)
    end
    return table.concat(words, ",")
end

--- The row's normalize: `text` as Join writes it, with what cannot apply dropped, or nil (refused)
--- when it does not parse.
function Dummies.Normalize(text)
    local entries = Dummies.Parse(text)
    return entries and Dummies.Join(applicable(entries)) or nil
end

-- The parse of the last stored text, by ID.
local listText, listById

local function read()
    local text = NS.GetSetting and NS.GetSetting(Dummies.PATH) or nil
    if text ~= listText or not listById then
        listText, listById = text, {}
        for _, e in ipairs(applicable(Dummies.Parse(text) or {})) do listById[e.id] = e end
    end
    return listById
end

local function copyOf(e) return { id = e.id, category = e.category, hidden = e.hidden } end

--- This profile's entry for `id`, a copy: { id, category } or { id, hidden = true }; nil when the
--- profile leaves the creature as the seed has it.
function Dummies.Entry(id)
    if not Secrets.IsSafeKey(id) then return nil end
    local e = read()[id]
    return e and copyOf(e) or nil
end

--- Every entry, ascending by ID (copies).
function Dummies.Entries()
    local out = {}
    for _, e in pairs(read()) do out[#out + 1] = copyOf(e) end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- ── the answers ─────────────────────────────────────────────────────────────────────────────────

--- The dummy a creature ID is now, as a fresh copy: the seed, as the player's list adds to it and
--- switches it off. A custom entry's name is its capture's, nil when it was never captured.
--- @param id number|nil  a plain number; nil or a secret answers nil
--- @return table|nil  { name, category }
function Dummies.Lookup(id)
    if not Secrets.IsSafeKey(id) then return nil end
    local own = read()[id]
    if own then
        if own.hidden then return nil end
        return { name = Dummies.NameOf(id), category = own.category }
    end
    return Dummies.BuiltIn(id)
end

--- The dummy's name for a creature ID, or nil: no dummy now, or one never named (a custom dummy
--- that was never captured).
--- @return string|nil
function Dummies.Name(id)
    local d = Dummies.Lookup(id)
    return d and d.name or nil
end

--- The dummy's category now ("single" | "cleave" | "dungeoneer" | "boss" | "pvp"), or nil when the
--- creature is no dummy.
--- @return string|nil
function Dummies.CategoryOf(id)
    local d = Dummies.Lookup(id)
    return d and d.category or nil
end

-- ── the writes ──────────────────────────────────────────────────────────────────────────────────

local function write(byId)
    local entries = {}
    for _, e in pairs(byId) do entries[#entries + 1] = e end
    return NS.SetByPath(Dummies.PATH, Dummies.Join(entries)) and true or false
end

local function copy()
    local out = {}
    for id, e in pairs(read()) do out[id] = copyOf(e) end
    return out
end

local function plainId(id)
    id = Secrets.PlainNumber(id)
    return type(id) == "number" and id >= 1 and id <= Dummies.MAX_ID and id % 1 == 0 and id or nil
end

-- A switched-off built-in back on; nil when it is on already.
local function restore(list, id)
    if not (list[id] and list[id].hidden) then return nil end
    list[id] = nil
    return write(list) and "restored" or nil
end

--- Mark creature `id` as a dummy of `category` (single target when none is given). A switched-off
--- built-in is switched back on (the category is the seed's); a built-in already on changes nothing.
--- A custom entry takes the new category.
--- @return string|nil outcome  "added" | "restored" | "changed" | nil (nothing to do or refused)
function Dummies.Add(id, category)
    id = plainId(id)
    if not id then return nil end
    local list = copy()
    if builtIn(id) then return restore(list, id) end
    category = category or "single"
    if not KIND[category] then return nil end
    local had = list[id]
    if had and had.category == category then return nil end
    list[id] = { id = id, category = category }
    return write(list) and (had and "changed" or "added") or nil
end

--- Stop counting creature `id` as a dummy: a custom entry goes, a built-in is switched off.
--- @return string|nil outcome  "removed" | "hidden" | nil (not a dummy now)
function Dummies.Remove(id)
    id = plainId(id)
    if not id then return nil end
    local list = copy()
    if builtIn(id) then
        if list[id] and list[id].hidden then return nil end
        list[id] = { id = id, hidden = true }
        return write(list) and "hidden" or nil
    end
    if not list[id] then return nil end
    list[id] = nil
    return write(list) and "removed" or nil
end

--- Back to the seed alone (one write of the default, as `/ct reset dummies.custom` does).
function Dummies.Defaults()
    return NS.SetByPath(Dummies.PATH, Dummies.DEFAULT) and true or false
end

--- A typed category word as a category key ("Cleave", "boss", "Boss-level"), or nil.
function Dummies.CategoryWord(word)
    word = type(word) == "string" and word:match("^%s*(.-)%s*$"):lower() or ""
    if KIND[word] then return word end
    for _, k in ipairs(Dummies.CATEGORIES) do
        if LABELS[k]:lower() == word then return k end
    end
    return nil
end

-- ── the captures ────────────────────────────────────────────────────────────────────────────────

local function passResults(ok, ...)
    if ok then return ... end
    return nil
end

local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    return passResults(pcall(fn, ...))
end

local function store()
    local g = NS.db and NS.db.global
    if type(g) ~= "table" then return nil end
    g.dummies = type(g.dummies) == "table" and g.dummies or {}
    g.dummies.captures = type(g.dummies.captures) == "table" and g.dummies.captures or {}
    return g.dummies.captures
end

-- The player's position on map `mapID` as two plain fractions, or nil (no map, no API, a sealed read).
local function playerXY(mapID)
    local map = C_Map
    if not (mapID and type(map) == "table") then return nil end
    local pos = ask(map.GetPlayerMapPosition, mapID, "player")
    if type(pos) ~= "table" or type(pos.GetXY) ~= "function" then return nil end
    local ok, px, py = pcall(pos.GetXY, pos)
    if not ok then return nil end
    return Secrets.PlainNumber(px), Secrets.PlainNumber(py)
end

-- A map fraction as a percentage to two places, or nil.
local function percent(v)
    return v and math.floor(v * 10000 + 0.5) / 100 or nil
end

-- A zone text, plain and non-empty, or nil.
local function zoneText(fn)
    local text = Secrets.PlainString((ask(fn)))
    if text == "" then return nil end
    return text
end

-- Where the player stands: { mapID, zone, subzone, x, y }.
local function where()
    local map = C_Map
    local mapID = type(map) == "table" and Secrets.PlainNumber(ask(map.GetBestMapForUnit, "player")) or nil
    local x, y = playerXY(mapID)
    return { mapID = mapID, zone = zoneText(GetZoneText), subzone = zoneText(GetSubZoneText),
             x = percent(x), y = percent(y) }
end

-- PvP flagged, or nil when the answer is sealed or not a boolean.
local function pvpOf(unit)
    local pvp = ask(UnitIsPVP, unit)
    if Secrets.IsSealed(pvp) or type(pvp) ~= "boolean" then return nil end
    return pvp
end

--- What the game says now about `unit` and where the player stands: every field a sealed read leaves
--- out. Reads only.
--- @param unit string|nil  "target" when nil
--- @return table|nil read  { creatureID, name, level, classification, health, creatureType, pvp,
---   faction, reaction, mapID, zone, subzone, x, y }; nil when the unit is no creature
function Dummies.Read(unit)
    unit = unit or "target"
    if not Secrets.PlainTruth(ask(UnitExists, unit)) then return nil end
    local id = NS.Identity.UnitCreatureID(unit)
    if not id then return nil end
    local w = where()
    return {
        creatureID = id,
        name = Secrets.PlainString((ask(NS.Compat.UnitCharacterName, unit))),
        level = Secrets.PlainNumber(ask(UnitLevel, unit)),
        classification = Secrets.PlainString(ask(UnitClassification, unit)),
        health = Secrets.PlainNumber(ask(UnitHealthMax, unit)),
        creatureType = Secrets.PlainString(ask(UnitCreatureType, unit)),
        pvp = pvpOf(unit),
        faction = Secrets.PlainString((ask(UnitFactionGroup, unit))),
        reaction = Secrets.PlainNumber(ask(UnitReaction, unit, "player")),
        mapID = w.mapID, zone = w.zone, subzone = w.subzone, x = w.x, y = w.y,
    }
end

local DETAIL_FIELDS = { "name", "level", "classification", "health", "creatureType", "pvp", "faction", "reaction" }

-- The read's details and place onto capture `c`, at `now`.
local function fillCapture(c, r, now)
    for _, key in ipairs(DETAIL_FIELDS) do
        if r[key] ~= nil then c[key] = r[key] end
    end
    if r.mapID then
        c.places = type(c.places) == "table" and c.places or {}
        c.places[r.mapID] = { zone = r.zone, subzone = r.subzone, x = r.x, y = r.y, date = now }
    end
end

--- Save what the game says about a creature under its creature ID: the latest details, the first and
--- last dates, a count, and one line per map it was captured on.
--- @param r table|nil  a Dummies.Read; the target is read now when nil
--- @return table|nil capture, table|nil read  the stored record and the read; nil with no creature or
---   no store
function Dummies.Capture(r)
    r = r or Dummies.Read("target")
    local captures = store()
    if not (captures and type(r) == "table" and r.creatureID) then return nil end
    local now = time()
    local c = captures[r.creatureID] or { first = now, count = 0, places = {} }
    fillCapture(c, r, now)
    c.last, c.count = now, (c.count or 0) + 1
    c.addon = NS.Version and NS.Version() or nil
    local _, build = ask(NS.Compat.BuildInfo)
    c.build = tonumber(Secrets.PlainString(build) or "")
    captures[r.creatureID] = c
    return c, r
end

--- The capture of creature `id`, or nil (read only).
function Dummies.Captured(id)
    local captures = store()
    if not (captures and Secrets.IsSafeKey(id)) then return nil end
    return captures[id]
end

--- The name `id` goes by: its capture's, else the seed's, else nil.
function Dummies.NameOf(id)
    local c = Dummies.Captured(id)
    if c and type(c.name) == "string" then return c.name end
    local d = Secrets.IsSafeKey(id) and seed()[id]
    return d and d.name or nil
end

-- The lowest creature ID a capture or the seed names `want` (lowercase), or nil.
local function lowestNamed(want)
    local found
    local function consider(cid, name)
        if type(name) == "string" and name:lower() == want and (not found or cid < found) then found = cid end
    end
    for cid, c in pairs(store() or {}) do
        if type(c) == "table" then consider(cid, c.name) end
    end
    for cid, d in pairs(seed()) do consider(cid, d.name) end
    return found
end

--- A typed creature: a number, else a captured or seeded name (case-insensitive; the lowest ID when
--- several share it). Answers `id` or `nil, reason` ("empty", "notFound").
function Dummies.Resolve(text)
    if type(text) == "number" then text = tostring(text) end
    text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    if text == "" then return nil, "empty" end
    local digits = text:match("^%d+$")
    if digits then
        local id = tonumber(digits)
        if id < 1 or id > Dummies.MAX_ID then return nil, "notFound" end
        return id
    end
    local found = lowestNamed(text:lower())
    if found then return found end
    return nil, "notFound"
end

-- ── `/ct dummy` ──────────────────────────────────────────────────────────────────────────────────
-- Every list write goes through the writes above, so through the seam; a capture goes to the global
-- store. Live while the addon is disabled (settings/Slash.lua's HOST_LIVE_VERBS), on both clients.

local function out(line) NS.Print(line) end

local function usage()
    out(L["Usage: %s dummy [show|add|remove|capture|defaults] [category or creature ID]"]:format(NS.SLASH_CMD))
end

-- "Angry Boar (99999)", or "Creature 99999" when it was never captured and is no built-in.
local function dummyName(id)
    local name = Dummies.NameOf(id)
    if name then return L["%s (%d)"]:format(name, id) end
    return L["Creature %d"]:format(id)
end

-- The capture's level part ("level 70 elite", "skull level"), or nil with no level.
local function captureLevel(r)
    if not r.level then return nil end
    local lvl = r.level == -1 and L["skull level"] or L["level %d"]:format(r.level)
    if r.classification and r.classification ~= "normal" then return L["%s %s"]:format(lvl, r.classification) end
    return lvl
end

-- The capture's place part ("Zone, Subzone 12.3, 45.6"), or nil with no zone.
local function captureWhere(r)
    local place = r.subzone and r.zone and L["%s, %s"]:format(r.zone, r.subzone) or r.zone
    if place and r.x and r.y then place = L["%s %.1f, %.1f"]:format(place, r.x, r.y) end
    return place
end

--- The capture as one line: what the game said, then where.
function Dummies.CaptureLine(r)
    local parts = { dummyName(r.creatureID) }
    local function add(part) if part then parts[#parts + 1] = part end end
    add(captureLevel(r))
    if r.health then add(L["%s health"]:format(NS.Format.Number(r.health))) end
    add(r.creatureType)
    if r.pvp ~= nil then add(r.pvp and L["PvP flagged"] or L["not PvP flagged"]) end
    add(captureWhere(r))
    return table.concat(parts, " \194\183 ")
end

local function targetExists()
    return Secrets.PlainTruth(ask(UnitExists, "target")) == true
end

-- The target as a creature, captured, or nil after the one line that says why.
local function capturedTarget()
    if not targetExists() then return out(L["Target a creature first."]) end
    local r = Dummies.Read("target")
    if not r then return out(L["Your target is not a creature, so it cannot be a training dummy."]) end
    Dummies.Capture(r)
    return r
end

local function showDummies()
    local own, off = {}, {}
    for _, e in ipairs(Dummies.Entries()) do
        if e.hidden then off[#off + 1] = e else own[#own + 1] = e end
    end
    local seeded = 0
    for _ in pairs(seed()) do seeded = seeded + 1 end
    if #own == 0 then
        out(L["No training dummies of your own. Target one and type %s dummy add."]:format(NS.SLASH_CMD))
    else
        out(L["Your training dummies:"])
        for _, e in ipairs(own) do out(L["  %s \194\183 %s"]:format(dummyName(e.id), Dummies.Label(e.category))) end
    end
    out(L["Built-in training dummies: %d, %d switched off."]:format(seeded, #off))
    for _, e in ipairs(off) do out(L["  %s (off)"]:format(dummyName(e.id))) end
end

-- What `add` says, by its outcome.
local function addLine(outcome, id, label)
    local name = dummyName(id)
    if outcome == "added" or outcome == "changed" then
        return out(L["%s is a training dummy now: %s."]:format(name, label))
    end
    if outcome == "restored" then return out(L["%s is a training dummy again: %s."]:format(name, label)) end
    if builtIn(id) then return out(L["%s is already a built-in training dummy: %s."]:format(name, label)) end
    out(L["%s is already a training dummy: %s."]:format(name, label))
end

local function addVerb(word)
    local category = Dummies.CategoryWord(word)
    if word ~= "" and not category then
        return out(L["'%s' is no category. Use single, cleave, dungeoneer, boss or pvp."]:format(word))
    end
    local r = capturedTarget()
    if not r then return end
    local outcome = Dummies.Add(r.creatureID, category)
    out(L["Saved: %s"]:format(Dummies.CaptureLine(r)))
    addLine(outcome, r.creatureID, Dummies.Label(Dummies.CategoryOf(r.creatureID) or category or "single"))
end

-- The creature `remove` names: a typed one, else the target; nil after the one line that says why.
local function removeTarget(text)
    if text ~= "" then
        local id = Dummies.Resolve(text)
        if not id then return out(L["No creature '%s' is known. Use its creature ID."]:format(text)) end
        return id
    end
    if not targetExists() then return usage() end
    local id = NS.Identity.UnitCreatureID("target")
    if not id then return out(L["Your target is not a creature, so it cannot be a training dummy."]) end
    return id
end

local function removeVerb(text)
    local id = removeTarget(text)
    if not id then return end
    local outcome = Dummies.Remove(id)
    if outcome == "removed" then return out(L["%s is no longer a training dummy."]:format(dummyName(id))) end
    if outcome == "hidden" then
        return out(L["%s, a built-in training dummy, is switched off. %s dummy add on it brings it back."]
            :format(dummyName(id), NS.SLASH_CMD))
    end
    out(L["%s is not a training dummy."]:format(dummyName(id)))
end

local VERBS = {
    show = showDummies,
    capture = function()
        local r = capturedTarget()
        if r then out(L["Saved: %s"]:format(Dummies.CaptureLine(r))) end
    end,
    add = addVerb,
    remove = removeVerb,
    defaults = function()
        if Dummies.Defaults() then out(L["Your training dummies are cleared: only the built-in ones count."]) end
        showDummies()
    end,
}

--- `/ct dummy [show|add|remove|capture|defaults] [category or creature ID]`; a bare verb shows the list.
function Dummies.OnVerb(rest)
    local word, text = tostring(rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = word:lower()
    if word == "" then word = "show" end
    local fn = VERBS[word]
    if not fn then return usage() end
    fn(text)
end
