local _, NS = ...
-- modules/LateIgnore.lua — the late-cast ignore list (Race mode, plan Task B1): the spells a cast after
-- the grace never flags (Feign Death, Vanish, a hearthstone out of the fight). One plain string of
-- spell IDs, the profile's `race.lateIgnore`, written WHOLE through the seam (NS.SetByPath), as the
-- Usage tab's hidden items are (modules/Usage.lua). Ported from DPS Race @f8078c7
-- (modules/LateIgnore.lua), unchanged in behavior; the known spells read Combat Trail's store (each
-- saved race's `race.flags.lateCasts`), and the menu takes a record or its race part. Its schema row,
-- its settings section and the `/ct race ignore` verb are Task B3's; the right-click on a Results row
-- and in the detail is Task D1's.
--
-- READ TIME. A race keeps every late cast it recorded (modules/Race.lua); RaceScoring.Flags and
-- RaceRecord.Flagged read this list each time they judge a race, so a change re-scores every saved
-- race, and a profile switch re-scores them by the other profile's list. A cache keyed on the flags
-- (modules/Bests.lua's clean board) listens for SETTINGS_CHANGED on PATH and on "profile". This file
-- posts nothing on the bus: the seam announces. On both clients: a saved race is account-wide.
--
-- THE HEARTHSTONE. 8690 in the list stands for every hearthstone variant (defaults/Hearthstones.lua):
-- one entry, expanded only in Set(). A variant can also be listed on its own while 8690 is not.
-- A late cast stored with no spell ID (a sealed one) is never ignored.

local LateIgnore = {}
NS.LateIgnore = LateIgnore

LateIgnore.PATH = "race.lateIgnore"
--- The list a new profile starts with (defaults/Profile.lua, the one place it is written).
LateIgnore.DEFAULT = NS.defaults.profile.race.lateIgnore
--- The spell that stands for every hearthstone variant.
LateIgnore.HEARTHSTONE = 8690

local HEARTH = LateIgnore.HEARTHSTONE
local HEARTH_SET = {}
for _, id in ipairs(NS.HEARTHSTONE_SPELLS or {}) do HEARTH_SET[id] = true end

--- Whether `id` is one of the hearthstone variants (8690 among them).
function LateIgnore.IsHearthstone(id)
    return HEARTH_SET[id] == true
end

-- ── the stored text ─────────────────────────────────────────────────────────────────────────────

--- The spell IDs in `text` ("5384, 1856"), ascending and each once; nil when `text` is not a string
--- or holds anything but positive whole numbers between the commas. Pure.
--- @return table|nil ids
function LateIgnore.Parse(text)
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

-- `ids` without the hearthstone variants 8690 already covers (a fresh array, order kept).
local function compact(ids)
    local whole = false
    for _, id in ipairs(ids) do
        if id == HEARTH then whole = true end
    end
    local out = {}
    for _, id in ipairs(ids) do
        if not whole or id == HEARTH or not HEARTH_SET[id] then out[#out + 1] = id end
    end
    return out
end

--- The stored text for `ids`: ascending, comma-separated ("66,1856"). Sorts `ids` in place.
function LateIgnore.Join(ids)
    table.sort(ids)
    local words = {}
    for i, id in ipairs(ids) do words[i] = tostring(id) end
    return table.concat(words, ",")
end

--- The row's normalize: `text` as Join writes it, with any variant 8690 covers dropped, or nil
--- (refused) when it does not parse.
function LateIgnore.Normalize(text)
    local ids = LateIgnore.Parse(text)
    return ids and LateIgnore.Join(compact(ids)) or nil
end

-- The parsed list of the last stored text and its expanded set, so the flags of a whole history are
-- judged against one parse.
local listText, listIds, listSet

local function read()
    local text = NS.GetSetting(LateIgnore.PATH)
    if text ~= listText or not listIds then
        listText, listIds, listSet = text, compact(LateIgnore.Parse(text) or {}), {}
        for _, id in ipairs(listIds) do
            listSet[id] = true
            if id == HEARTH then
                for variant in pairs(HEARTH_SET) do listSet[variant] = true end
            end
        end
    end
    return listIds, listSet
end

--- The listed spell IDs, ascending, 8690 standing for every hearthstone. A copy.
function LateIgnore.List()
    local out = {}
    for i, id in ipairs((read())) do out[i] = id end
    return out
end

--- The ignored spells as a set, { [spellID] = true }, with 8690 expanded to every hearthstone. Read
--- only: it is the cached set, the same table until the stored text changes.
function LateIgnore.Set()
    local _, set = read()
    return set
end

--- Whether a late cast of `id` is ignored. A cast with no spell ID (sealed) never is.
--- @param id number|nil
--- @param set table|nil  LateIgnore.Set() (read now when nil)
function LateIgnore.IsIgnored(id, set)
    if type(id) ~= "number" then return false end
    return (set or LateIgnore.Set())[id] == true
end

--- The list's entry that ignores `id`: `id` itself, or 8690 for a variant listed only through it; nil
--- when `id` is not ignored.
function LateIgnore.Covering(id)
    if not LateIgnore.IsIgnored(id) then return nil end
    for _, listed in ipairs((read())) do
        if listed == id then return id end
    end
    return HEARTH
end

-- ── the writes ──────────────────────────────────────────────────────────────────────────────────

local function write(ids)
    return NS.SetByPath(LateIgnore.PATH, LateIgnore.Join(compact(ids)))
end

local function plainId(id)
    if NS.Secrets and NS.Secrets.PlainNumber then id = NS.Secrets.PlainNumber(id) end
    return type(id) == "number" and id >= 1 and id % 1 == 0 and id or nil
end

--- Ignore `id`'s late casts (8690: every hearthstone's).
--- @return boolean changed
function LateIgnore.Ignore(id)
    id = plainId(id)
    if not id or LateIgnore.IsIgnored(id) then return false end
    local ids = LateIgnore.List()
    ids[#ids + 1] = id
    return write(ids) and true or false
end

--- Count `id`'s late casts again. A variant ignored only through 8690 takes 8690 off the list: there is
--- no other way to count it, and it is never an undo that does nothing.
--- @return boolean changed
function LateIgnore.Unignore(id)
    local covering = LateIgnore.Covering(id)
    if not covering then return false end
    local ids = {}
    for _, listed in ipairs((read())) do
        if listed ~= covering then ids[#ids + 1] = listed end
    end
    return write(ids) and true or false
end

--- Back to the six defaults (one write of the default).
--- @return boolean written
function LateIgnore.Reset()
    return NS.SetByPath(LateIgnore.PATH, LateIgnore.DEFAULT) and true or false
end

-- ── what a typed spell is ───────────────────────────────────────────────────────────────────────

-- A plain spell ID's name and icon, through the compat family (core/Compat.lua); nil when unreadable.
local function spellName(id)
    local ok, name = pcall(NS.Compat.SpellName, id)
    return ok and type(name) == "string" and name or nil
end

local function spellIcon(id)
    local ok, icon = pcall(NS.Compat.SpellTexture, id)
    return ok and icon or nil
end

--- One spell as a line names it: "Feign Death (5384)", "Hearthstone, all variants (8690)" for 8690,
--- "Unknown spell (424242)" when the client cannot name it.
function LateIgnore.Label(id)
    local name = spellName(id) or NS.L["Unknown spell"]
    if id == HEARTH then return NS.L["%s, all variants (%d)"]:format(name, id) end
    return NS.L["%s (%d)"]:format(name, id)
end

-- The hearthstone a typed name stands for, or nil when it is no hearthstone's name (the word itself,
-- or any variant's name in the client's locale). Several variants share a name (8690, 191329 and
-- 401802 are all "Hearthstone"), so the name lookup below would answer "ambiguous". The answer is
-- 8690, unless 8690 is off the list and a variant carrying the name is listed on its own: then that
-- variant (the lowest), so `remove <its name>` finds what is listed.
local function hearthByName(want)
    for _, id in ipairs((read())) do
        local name = id ~= HEARTH and HEARTH_SET[id] and spellName(id)
        if name and name:lower() == want then return id end
    end
    if want == "hearthstone" then return HEARTH end
    for id in pairs(HEARTH_SET) do
        local name = spellName(id)
        if name and name:lower() == want then return HEARTH end
    end
    return nil
end

--- Typed text to a spell ID: a number, a spell link, a hearthstone's name (8690, or a variant listed
--- on its own that carries the name), else the options library's spell lookup over `candidates`
--- (KnownSpells by default). The first three need no library, so they resolve on a degraded load too.
--- Answers `id, name, icon` or `nil, reason` ("empty", "notFound", "ambiguous"): the ID list's own
--- resolver shape.
--- @param text string|number
--- @param candidates function|nil
function LateIgnore.Resolve(text, candidates)
    if type(text) == "number" then text = tostring(text) end
    text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    if text == "" then return nil, "empty" end
    local id = tonumber(text:match("^%d+$") or text:match("spell:(%d+)") or "")
    if id then
        if id < 1 then return nil, "notFound" end
        return id, spellName(id), spellIcon(id)
    end
    local hearth = hearthByName(text:lower())
    if hearth then return hearth, spellName(hearth), spellIcon(hearth) end
    local H = NS.Helpers
    if not (H and H.ResolveId) then return nil, "notFound" end
    local found, name, icon = H.ResolveId("spell", text, candidates or LateIgnore.KnownSpells)
    if found == nil then return nil, name or "notFound" end
    return found, name, icon
end

-- Every saved race that recorded a late cast, newest first (by the record's start, `t`).
local function racesWithLateCasts()
    local fights = NS.db and NS.db.global and NS.db.global.fights
    local list = {}
    for _, record in pairs(type(fights) == "table" and fights or {}) do
        local race = type(record) == "table" and record.race
        local flags = type(race) == "table" and race.flags
        if type(flags) == "table" and type(flags.lateCasts) == "table" then list[#list + 1] = record end
    end
    table.sort(list, function(a, b) return (tonumber(a.t) or 0) > (tonumber(b.t) or 0) end)
    return list
end

--- The spells a typed name can match beyond the ones the character knows (the client's name lookup
--- finds only those): every spell a saved race cast late, newest race first, each once, then the
--- defaults. The hearthstones are matched by name before this list is read.
--- @return table ids
function LateIgnore.KnownSpells()
    local out, seen = {}, {}
    local function add(id)
        if type(id) == "number" and not seen[id] then seen[id], out[#out + 1] = true, id end
    end
    for _, record in ipairs(racesWithLateCasts()) do
        for _, cast in ipairs(record.race.flags.lateCasts) do add(type(cast) == "table" and cast.spellID) end
    end
    for _, id in ipairs(LateIgnore.Parse(LateIgnore.DEFAULT) or {}) do add(id) end
    return out
end

-- ── the menu (the Race window's late-cast chip, the Results detail's Flags box and row menu) ─────

-- The race part out of a record, or the part itself.
local function partOf(x)
    if type(x) ~= "table" then return nil end
    if type(x.race) == "table" then return x.race end
    return x
end

-- What one menu entry ignores or counts again: an Ignore per counted spell, an undo per ignored one.
local function ignoreEntry(id)
    local name = spellName(id) or NS.L["Unknown spell"]
    return { text = NS.L["Ignore %s for late casts"]:format(name), id = id, ignore = true }
end

local function undoEntry(id, covering)
    local L = NS.L
    local text = covering == HEARTH and L["Stop ignoring all hearthstones"]
        or L["Stop ignoring %s"]:format(spellName(id) or L["Unknown spell"])
    return { text = text, id = id, ignore = false }
end

--- What a race's late-cast menu offers: one *Ignore <spell> for late casts* per spell its counted
--- casts name, then one *Stop ignoring <spell>* per spell the list leaves uncounted (*Stop ignoring
--- all hearthstones* when 8690 covers it: Unignore takes 8690 off). Each entry once, in the recorded
--- order; a sealed cast (no spell ID) offers nothing.
--- @param x table  a record or its race part
--- @return table entries  { { text, id, ignore = bool } }
function LateIgnore.MenuEntries(x)
    local out, seen = {}, {}
    local counted, ignored = NS.RaceScoring.SplitLate(partOf(x))
    for _, cast in ipairs(counted) do
        local id = plainId(cast.spellID)
        if id and not seen[id] then seen[id], out[#out + 1] = true, ignoreEntry(id) end
    end
    for _, cast in ipairs(ignored) do
        local covering = LateIgnore.Covering(cast.spellID)
        if covering and not seen[covering] then
            seen[covering], out[#out + 1] = true, undoEntry(cast.spellID, covering)
        end
    end
    return out
end

--- Whether `x` (a record or its race part) has anything for the menu to offer.
function LateIgnore.Offers(x)
    return #LateIgnore.MenuEntries(x) > 0
end

--- Add the race's entries to `root` (a menu, or a submenu's button): each one writes through Ignore
--- or Unignore, and the SETTINGS_CHANGED that write announces redraws whatever shows the race.
--- @return number count
function LateIgnore.FillMenu(root, x)
    local entries = LateIgnore.MenuEntries(x)
    for _, e in ipairs(entries) do
        local id, ignore = e.id, e.ignore
        root:CreateButton(e.text, function()
            if ignore then LateIgnore.Ignore(id) else LateIgnore.Unignore(id) end
        end)
    end
    return #entries
end

--- Open the race's late-cast menu on `owner`, titled *Late casts*. Nothing opens with no menu (a
--- client or a harness without one) or nothing to offer.
--- @return boolean opened
function LateIgnore.Menu(x, owner)
    if not (owner and NS.CanOpenMenu()) then return false end
    if not LateIgnore.Offers(x) then return false end
    NS.OpenMenu(owner, function(root)
        root:CreateTitle(NS.L["Late casts"])
        LateIgnore.FillMenu(root, x)
    end)
    return true
end
