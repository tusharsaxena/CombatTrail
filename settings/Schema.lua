local _, NS = ...
-- settings/Schema.lua — the schema array, the ONE write seam every path goes through, and the page
-- filter, over LibKa0s-Schema-1.0 (architecture-§5). Page files register their rows into NS.Schema.

NS.Schema = NS.Schema or {}

-- The Minimap button row (launcher-§3). Its CLI name says SHOWN, because the composed checkbox reads
-- "Minimap button" and ticks while the button shows; it stores at LibDBIcon's own `global.minimap.hide`
-- through the row's get/set (settings/General.lua), never in the profile, and no reset ever touches it
-- (anti-pattern #83). It sits under `general.` with the rest of Master controls so `/ct list` groups it
-- there.
NS.MINIMAP_PATH = "general.minimap.shown"
local RESET_EXEMPT = { [NS.MINIMAP_PATH] = true }

-- ── The library-absent runtime ─────────────────────────────────────────────────────────────────
-- Answers every member this file binds. Copies none of the library's logging or bulk tally: a
-- degraded write stores, reacts and announces, and that is all.
local Stub = {}

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

function Stub.SplitPath(path)
    local parts = {}
    for seg in tostring(path or ""):gmatch("[^%.]+") do parts[#parts + 1] = seg end
    return parts
end

function Stub.Read(root, path, first)
    local parts = type(path) == "table" and path or Stub.SplitPath(path)
    first = first or 1
    if type(root) ~= "table" or #parts < first then return nil end
    local node = root
    for i = first, #parts do
        if type(node) ~= "table" then return nil end
        node = node[parts[i]]
    end
    return node
end

function Stub.Write(root, path, value, first)
    local parts = type(path) == "table" and path or Stub.SplitPath(path)
    first = first or 1
    if type(root) ~= "table" or #parts < first then return end
    local node = root
    for i = first, #parts - 1 do
        if type(node[parts[i]]) ~= "table" then node[parts[i]] = {} end
        node = node[parts[i]]
    end
    node[parts[#parts]] = value
end

local function stubFind(rows, path)
    if type(path) ~= "string" then return nil end
    for _, row in ipairs(rows) do
        if type(row) == "table" and row.path == path then return row end
    end
end

local function stubStore(d, row, path, value, id)
    if type(row.set) == "function" then row.set(value) return true end
    if row.sessionOnly then return true end
    local parts = Stub.SplitPath(path)
    local root, first = d.resolveRoot(parts, id)
    if type(root) ~= "table" then return false end
    Stub.Write(root, parts, copy(value), first)
    return true
end

function Stub.New(_, d)
    local S, rows = {}, d.rows
    local through = {}
    for _, p in ipairs(d.writeThrough or {}) do through[p] = { path = p, writeThrough = true } end
    function S.AllRows() return rows end
    function S.FindRow(path) return stubFind(rows, path) end
    function S.AddRows(list)
        for _, row in ipairs(list or {}) do rows[#rows + 1] = row end
        return #(list or {})
    end
    function S.Get(path, id)
        local row = stubFind(rows, path)
        if row and type(row.get) == "function" then return row.get(id) end
        if type(path) ~= "string" or (row and row.sessionOnly) then return nil end
        local parts = Stub.SplitPath(path)
        local root, first = d.resolveRoot(parts, id)
        return Stub.Read(root, parts, first)
    end
    function S.Set(path, value, id)
        local row = stubFind(rows, path) or through[path]
        if not row then return false, "Setting not found: " .. tostring(path) end
        if row.validate and not row.validate(value, id) then return false, "Invalid value for " .. path end
        if not stubStore(d, row, path, value, id) then return false, "Setting has nowhere to be stored yet: " .. path end
        if row.onChange then row.onChange(value, id) end
        if d.announce then d.announce(row, path, value, id) end
        return true
    end
    function S.ApplyDefault(row, id)
        if type(row) ~= "table" or type(row.path) ~= "string" or row.default == nil then return false end
        if RESET_EXEMPT[row.path] then return false end
        return S.Set(row.path, copy(row.default), id)
    end
    function S.BulkBegin() end
    function S.BulkEnd() end
    function S.BulkRun(_, _, fn) fn({ profileReset = false }) end
    function S.Validate() return 0, 0, 0 end
    return S
end

local SchemaLib = LibStub and LibStub("LibKa0s-Schema-1.0", true) or Stub
NS.__schemaLib = SchemaLib

-- ── The runtime ────────────────────────────────────────────────────────────────────────────────
local SlashLib = LibStub and LibStub("LibKa0s-Slash-1.0", true)

--- One formatter for the `[Set]` line and the CLI echo, so the two never disagree.
function NS.FormatSchemaValue(row, value)
    if SlashLib and SlashLib.FormatValue then return SlashLib.FormatValue(row, value) end
    return tostring(value)
end

--- The one sender of SETTINGS_CHANGED (architecture-§4): the write seam's tail below, and
--- core/Database.lua's profile callbacks, which announce a wholesale profile change as
--- ("profile", key) through this same function.
function NS.AnnounceSettingsChanged(path, value)
    NS.SendBus(NS.MSG.SETTINGS_CHANGED, path, value)
end

local S = SchemaLib:New({
    rows = NS.Schema,
    -- `global.<...>` paths live in the global store; everything else in the active profile.
    resolveRoot = function(parts)
        if parts[1] == "global" then return NS.db and NS.db.global, 2 end
        return NS.db and NS.db.profile, 1
    end,
    -- The post-write tail: one bus message per stored write. Session rows (debug console, debug
    -- logging, test mode, sim mode) announce nothing -- nothing downstream stores or redraws from
    -- them.
    announce = function(row, path, value)
        if row.sessionOnly then return end
        NS.AnnounceSettingsChanged(path, value)
    end,
    debug        = function(tag, fmt, ...) NS.Debug(tag, fmt, ...) end,
    debugEnabled = function() return NS.State.debug end,
    format       = function(row, value) return NS.FormatSchemaValue(row, value) end,
    print        = function(line) NS.Print(line) end,
    resetExempt  = RESET_EXEMPT,
    -- options-ui-§1 route (a): on a load where the Master-controls composer is hollow, the host
    -- verbs that write these composed rows still land.
    writeThrough = { "general.enabled", "general.locked" },
})
NS.SchemaRuntime = S

NS.RegisterSchemaRows = function(rows) return S.AddRows(rows) end
NS.FindSchemaRow      = S.FindRow
NS.SetByPath          = S.Set
NS.ApplyDefault       = S.ApplyDefault
NS.Bulk               = { Begin = S.BulkBegin, End = S.BulkEnd, Run = S.BulkRun }

--- A setting's current value, falling back to the shipped default when the store cannot answer yet
--- (before InitDB) so a load-time reader never sees nil for a row that has a default.
function NS.GetSetting(path)
    local v = S.Get(path)
    if v ~= nil then return v end
    local row = S.FindRow(path)
    if row and row.default ~= nil then return row.default end
    local parts = SchemaLib.SplitPath(path)
    if parts[1] == "global" then return SchemaLib.Read(NS.defaults and NS.defaults.global, parts, 2) end
    return SchemaLib.Read(NS.defaults and NS.defaults.profile, parts, 1)
end

--- The rows of one page, grouped by tab in first-appearance order, then by `order`, then in
--- declaration order (table.sort is not stable, so the position is the last key).
--- `filter` is the page's instance (the library passes the page ctx's `unit` when it renders): on
--- the Lanes page it is the lane in the band's picker, and a row stamped with another `lane` is left
--- out. A Defaults press passes none, so it reaches every lane (options-ui-§13).
function NS.SchemaForPage(pageKey, filter)
    local out, groupIndex, position = {}, {}, {}
    for _, row in ipairs(NS.Schema) do
        if row.page == pageKey and not row.hidden
            and (filter == nil or row.lane == nil or row.lane == filter) then
            out[#out + 1] = row
            position[row] = #out
            local g = row.group or ""
            if groupIndex[g] == nil then groupIndex[g] = #out end
        end
    end
    table.sort(out, function(a, b)
        local ga, gb = groupIndex[a.group or ""], groupIndex[b.group or ""]
        if ga ~= gb then return ga < gb end
        local oa, ob = a.order or 0, b.order or 0
        if oa ~= ob then return oa < ob end
        return position[a] < position[b]
    end)
    return out
end

-- The page keys a row may name: the sub-pages, in their panel order (settings/General.lua first,
-- settings/Profiles.lua last); `race` is the Race mode page, Retail's alone (settings/Race.lua).
local VALID_PAGES = { general = true, lanes = true, hud = true, history = true, race = true, profiles = true }

-- The Minimap row declares no stored `shown`: it answers no root here, and its stored key
-- (`global.minimap.hide`) is checked against the defaults by the suite instead (architecture-§5).
local function defaultsRoot(parts, row)
    if RESET_EXEMPT[row.path] then return nil end
    if parts[1] == "global" then return NS.defaults and NS.defaults.global, 2 end
    return NS.defaults and NS.defaults.profile, 1
end

--- The load-time shape check: errors, resolved, missing.
function NS.ValidateSchema()
    return S.Validate({ pages = VALID_PAGES, defaultsRoot = defaultsRoot })
end
