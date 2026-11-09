local _, NS = ...
-- modules/LaneIgnore.lua — each lane's ignore list (spec §4, Ignored spells): add a spell by ID,
-- name or link, remove one, put the list back to its seed, and the `/kct ignore` verb. The Lanes
-- page's Ignored spells tab (settings/Lanes.lua) and the verb both go through here, so the two
-- cannot store it two ways.
--
-- THE STORED SHAPE is lanes.<key>.ignore = { [spellID] = true } (defaults/Profile.lua). A seed the
-- player removes is stored as false, not cleared: AceDB would put a cleared seed back from the
-- defaults at the next login. Any other removed ID is cleared. modules/LaneCasts.lua reads
-- `ignore[id] == true`, so false and nil both mean shown.
--
-- No schema row holds the list (a set is not one of the schema's value types), so every change
-- announces SETTINGS_CHANGED("lanes.<key>.ignore") itself, which is what the write seam would send.
-- The page's Defaults and Reset lane put the list back through ResetToSeed.

local L = NS.L

local LaneIgnore = {}
NS.LaneIgnore = LaneIgnore

local IS_LANE = { player = true, pet = true }
local LANE_NAME = { player = L["Player lane"], pet = L["Pet lane"] }

local function listOf(laneKey)
    local db = NS.db
    local lanes = db and db.profile and db.profile.lanes
    local cfg = lanes and lanes[laneKey]
    if type(cfg) ~= "table" then return nil end
    if type(cfg.ignore) ~= "table" then cfg.ignore = {} end
    return cfg.ignore
end

local function isSeed(laneKey, id)
    for _, seed in ipairs(NS.IGNORE_SEEDS[laneKey] or {}) do
        if seed == id then return true end
    end
    return false
end

local function changed(laneKey)
    NS.AnnounceSettingsChanged("lanes." .. laneKey .. ".ignore")
end

--- The spells a lane ignores, lowest ID first.
--- @param laneKey string "player" | "pet"
--- @return table ids
function LaneIgnore.Entries(laneKey)
    local out = {}
    for id, on in pairs(listOf(laneKey) or {}) do
        if on == true and type(id) == "number" then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

--- Ignore one spell on a lane. Answers whether it was added (false: already ignored, or no lane).
function LaneIgnore.Add(laneKey, id)
    local list = listOf(laneKey)
    id = tonumber(id)
    if not (list and id) or list[id] == true then return false end
    list[id] = true
    changed(laneKey)
    return true
end

--- Stop ignoring one spell on a lane. Answers whether it was on the list.
function LaneIgnore.Remove(laneKey, id)
    local list = listOf(laneKey)
    id = tonumber(id)
    if not (list and id) or list[id] ~= true then return false end
    if isSeed(laneKey, id) then list[id] = false else list[id] = nil end
    changed(laneKey)
    return true
end

--- Put a lane's list back to this client's seed (defaults/IgnoreSeeds.lua).
function LaneIgnore.ResetToSeed(laneKey)
    local list = listOf(laneKey)
    if not list then return end
    for id in pairs(list) do list[id] = nil end
    for id in pairs(NS.IgnoreSeedSet(laneKey)) do list[id] = true end
    changed(laneKey)
end

--- Typed text to a spell ID: an ID, a spell link, or a name the client knows (LibKa0s-Options'
--- ResolveId). Answers id, name, or nil and the library's reason.
function LaneIgnore.Resolve(text)
    local H = NS.Helpers
    if H and H.ResolveId then
        local id, name = H.ResolveId("spell", text)
        if id then return id, name end
    end
    -- The library-absent load: a number or a link still resolves.
    text = tostring(text or "")
    local id = tonumber(text:match("^%s*(%d+)%s*$")) or tonumber(text:match("spell:(%d+)"))
    if id then return id, nil end
    return nil, "notFound"
end

-- A spell as a line names it: "Growl (2649)", or the bare ID when the client cannot name it.
local function spellLabel(id, name)
    if type(name) == "string" and name ~= "" then return ("%s (%d)"):format(name, id) end
    return tostring(id)
end

-- `rest` split into the act, the spell's text and the lane (last word, default the Player lane).
local function parse(rest)
    local act, tail = tostring(rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local text, lane = tail:match("^(.-)%s+(%S+)$")
    if lane and IS_LANE[lane:lower()] then
        lane = lane:lower()
    elseif IS_LANE[tail:lower()] then
        text, lane = "", tail:lower()
    else
        text, lane = tail, "player"
    end
    return act:lower(), text, lane
end

local function usage()
    NS.Print(L["Usage: /kct ignore add|remove <spell> [player|pet], /kct ignore list [player|pet] or /kct ignore reset [player|pet]"])
end

local function listVerb(lane)
    local ids = LaneIgnore.Entries(lane)
    if #ids == 0 then return NS.Print(L["The %s ignores no spells."]:format(LANE_NAME[lane])) end
    local parts = {}
    for i, id in ipairs(ids) do
        local ok, name = pcall(NS.Compat.SpellName, id)
        parts[i] = spellLabel(id, ok and NS.Secrets.PlainString(name) or nil)
    end
    NS.Print(L["The %s ignores %s."]:format(LANE_NAME[lane], table.concat(parts, ", ")))
end

local function changeVerb(act, text, lane)
    if text == "" then return usage() end
    local id, name = LaneIgnore.Resolve(text)
    if not id then return NS.Print(L["No spell named '%s'."]:format(text)) end
    local label = spellLabel(id, name)
    if act == "add" then
        if LaneIgnore.Add(lane, id) then
            return NS.Print(L["The %s now ignores %s."]:format(LANE_NAME[lane], label))
        end
        return NS.Print(L["The %s already ignores %s."]:format(LANE_NAME[lane], label))
    end
    if LaneIgnore.Remove(lane, id) then
        return NS.Print(L["The %s no longer ignores %s."]:format(LANE_NAME[lane], label))
    end
    NS.Print(L["The %s does not ignore %s."]:format(LANE_NAME[lane], label))
end

--- `/kct ignore add|remove <spell> [player|pet]`, `list [lane]` and `reset [lane]`.
function LaneIgnore.OnVerb(rest)
    local act, text, lane = parse(rest)
    if act == "add" or act == "remove" then return changeVerb(act, text, lane) end
    if act == "list" then return listVerb(lane) end
    if act == "reset" then
        LaneIgnore.ResetToSeed(lane)
        return NS.Print(L["The %s ignores its starting spells again."]:format(LANE_NAME[lane]))
    end
    usage()
end
