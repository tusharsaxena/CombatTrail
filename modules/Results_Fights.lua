local _, NS = ...
-- modules/Results_Fights.lua — the Results window's fight list (spec §7, mockup §5): the filter bar
-- (character, spec, content, encounter or target, difficulty, date range, Bosses only, Group by, Save
-- view) over the pooled, sortable fight table (modules/Results_Table.lua). A click selects a fight
-- and a right-click opens its menu; the shell (modules/Results.lua) places the list. Adapted from DPS
-- Race @045f479 (modules/Results_Runs.lua) without its race: no race length, no dummy category, no
-- late-cast flags, no Include incomplete (every stored fight is final), so the Status column has one
-- tag, Best, and no Complete, Flagged or Incomplete.
--
-- THE VIEW is `results.view` (defaults/Profile.lua): the filters, the grouping and the sort. Each
-- build opens on the profile's saved view; Save view writes the view on screen there, and Reset view
-- puts the shipped one back. "current" (the character filter's default) is a value of its own,
-- resolved when the filter runs against the logged-in character (NS.Identity.Who).
--
-- FACETED FILTERS. Each dropdown lists the values found among the fights that pass every OTHER
-- filter, so no choice ever leads to an empty list it could have warned about. The content list
-- walks Identity.ContentKeys(), so a content kind the client does not have (Mythic+, delves and arenas
-- on WoW Forever, clients-§4) is never offered there.
--
-- THE DELTA COLUMN. Each fight's DPS against the best DPS in its own group of the fights the filters
-- pass (with no grouping, the whole list): the group's leader reads a green "0.0%" (DPS Race's, v0.2
-- Task C2), every other fight its signed gap. Recomputed on every redraw; nothing is stored on a
-- record. The Status column carries the trophy instead: "Best" on the fight that holds the best on its
-- board (character x spec x board key, modules/Bests.lua), whatever the filters.
--
-- CLIENTS (clients-§4, v0.2 plan Task A4). WoW Forever has no specializations: there the predominant
-- talent tree stands in for the spec (modules/Identity.lua, who.specID "tree:<class>:<index>"), so
-- the Spec dropdown and the Spec grouping are on both clients, worded as a talent tree on Forever
-- (D11). A fight with no tree has no spec and is listed under none.
--
-- Filter, Options, the groups and the columns are pure over stored records, so the suites drive them
-- bare.

local Fights = {}
NS.ResultsFights = Fights

local L = NS.L
local Tbl = NS.ResultsTable
local Style = NS.Style

local DAY = 86400
local DASH = "\226\128\148"
local SEP = " \194\183 "

-- The view keys (results.view's shape) the filters read, the grouping and the sort aside.
Fights.FILTERS = { "character", "spec", "content", "board", "difficulty", "days", "bossesOnly" }
-- Every key a saved view holds.
Fights.VIEW_KEYS = { "character", "spec", "content", "board", "difficulty", "days", "bossesOnly", "group",
                     "sort", "desc" }

local FILTER_H = 32         -- one row of the filter bar
local RETAIL = { "retail" }
-- The bar's dropdowns, left to right, and their least widths (BarPlan), each declared for its clients.
local DROPDOWN_SPECS = {
    { key = "character", width = 120 }, { key = "spec", width = 100 },
    { key = "content", width = 100 }, { key = "board", width = 150 }, { key = "difficulty", width = 100 },
    { key = "days", width = 100 }, { key = "group", width = 150 },
}
local VIEW_BUTTON_W = 80
local GAP = 6
local MARGIN = GAP + 2      -- the bar's left margin, and its right one once the dropdowns stretch

--- A spec label in this client's words: Retail's `retail`, WoW Forever's `forever` (a talent tree).
local function specWords(retail, forever)
    return NS.Compat.ForClient(RETAIL) and L[retail] or L[forever]
end

--- The bar's dropdowns this client has, in order: { key, width }.
function Fights.Dropdowns()
    local out = {}
    for _, spec in ipairs(DROPDOWN_SPECS) do
        if NS.Compat.ForClient(spec.clients) then out[#out + 1] = spec end
    end
    return out
end

--- The view the addon ships (defaults/Profile.lua, the only place a default is written).
function Fights.StockView()
    return NS.defaults.profile.results.view
end

-- ── pure: a fight's facts ───────────────────────────────────────────────────────────────────────

local function ident(record)
    return type(record) == "table" and type(record.identity) == "table" and record.identity or {}
end

local function who(record)
    return type(record) == "table" and type(record.who) == "table" and record.who or {}
end

--- The character a fight belongs to (NS.Bests.CharKey's "name|realm|client"), or "?".
function Fights.CharKey(record)
    return NS.Bests.CharKey(who(record)) or "?"
end

--- What a fight was against, difficulty aside: "e:<encounterID>", "c:<creatureID>", "i:<instanceID>"
--- (a PvP instance), else "n:<name>" (the Encounter or target filter's value).
function Fights.TargetKey(record)
    local i = ident(record)
    if i.encounterID then return "e:" .. tostring(i.encounterID) end
    if i.targetCreatureID then return "c:" .. tostring(i.targetCreatureID) end
    if i.pvpBracket and i.instanceID then return "i:" .. tostring(i.instanceID) end
    return "n:" .. tostring(i.targetName or "")
end

--- The name of what a fight was against: the encounter, the primary target, or a PvP instance.
function Fights.TargetName(record)
    local i = ident(record)
    if i.encounterID and i.encounterName then return i.encounterName end
    if i.pvpBracket and i.instanceID and not i.targetCreatureID and i.instanceName then return i.instanceName end
    return i.targetName or L["Unknown target"]
end

--- The difficulty a fight was at (0 for none: the open world).
function Fights.DifficultyOf(record)
    local d = ident(record).difficultyID
    return type(d) == "number" and d or 0
end

--- The tier text that sets a board apart beyond its difficulty: the keystone, the delve tier or the
--- PvP bracket, else nil.
function Fights.TierText(record)
    local i = ident(record)
    if type(i.keystoneLevel) == "number" then return L["Mythic+ %d"]:format(i.keystoneLevel) end
    if type(i.delveTier) == "number" then return L["Tier %d"]:format(i.delveTier) end
    if type(i.pvpBracket) == "string" then return L["Bracket %s"]:format(i.pvpBracket) end
    return nil
end

--- "<target> · <difficulty> · <tier>": a board's name (the Board group header).
function Fights.BoardLabel(record)
    local parts = { Fights.TargetName(record) }
    local d = ident(record).difficultyName
    if type(d) == "string" and d ~= "" then parts[#parts + 1] = d end
    parts[#parts + 1] = Fights.TierText(record)
    return table.concat(parts, SEP)
end

--- The epoch the date range starts at, or nil for all time: `days` 1 is today (from midnight), more
--- is that many days back from now, 0 is all time.
function Fights.Since(days, now)
    now = now or time()
    days = tonumber(days) or 0
    if days <= 0 then return nil end
    if days > 1 then return now - days * DAY end
    local t = date("*t", now)
    return time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 })
end

--- The logged-in character and spec, as the "current" values resolve: { char, specID }.
function Fights.Current()
    local ok, me = pcall(NS.Identity.Who)
    me = ok and type(me) == "table" and me or {}
    return { char = NS.Bests.CharKey(me), specID = me.specID }
end

-- ── pure: the filter ────────────────────────────────────────────────────────────────────────────

local function charPasses(record, want, ctx)
    if want == "all" then return true end
    if want == "current" then return ctx.current.char ~= nil and Fights.CharKey(record) == ctx.current.char end
    return Fights.CharKey(record) == want
end

local function specPasses(record, want, ctx)
    if want == "all" then return true end
    local id = who(record).specID
    if want == "current" then return ctx.current.specID == nil or id == ctx.current.specID end
    return id == want
end

-- One predicate per filter key: each answers whether the fight passes it.
local PASS = {
    character = function(r, v, ctx) return charPasses(r, v, ctx) end,
    spec = function(r, v, ctx) return specPasses(r, v, ctx) end,
    content = function(r, v) return v == "all" or ident(r).content == v end,
    board = function(r, v) return v == "all" or Fights.TargetKey(r) == v end,
    difficulty = function(r, v) return v == "all" or Fights.DifficultyOf(r) == v end,
    days = function(r, _, ctx) return ctx.since == nil or (r.t or 0) >= ctx.since end,
    bossesOnly = function(r, v) return not v or ident(r).isBoss == true end,
}

-- `view` over the stock view: a key it leaves out takes its shipped value.
local function full(view)
    local f = {}
    for k, v in pairs(Fights.StockView()) do f[k] = v end
    for k, v in pairs(type(view) == "table" and view or {}) do f[k] = v end
    return f
end

local function passes(record, f, ctx, skip)
    if type(record) ~= "table" or record.status ~= "final" then return false end
    for _, key in ipairs(Fights.FILTERS) do
        if key ~= skip and not PASS[key](record, f[key], ctx) then return false end
    end
    return true
end

local function context(f, now, current)
    return { since = Fights.Since(f.days, now), current = current or Fights.Current() }
end

--- The fights that pass every filter of `view`, in the order given.
--- @param records table  stored records
--- @param view table|nil  results.view's shape (a missing key is the shipped value)
--- @param now number|nil  the epoch the date range is measured from (time())
--- @param current table|nil  Fights.Current()'s answer (read when nil)
--- @param skip string|nil  one filter key left out (the facets)
--- @return table records
function Fights.Filter(records, view, now, current, skip)
    local f = full(view)
    local ctx = context(f, now, current)
    local out = {}
    for _, record in ipairs(records or {}) do
        if passes(record, f, ctx, skip) then out[#out + 1] = record end
    end
    return out
end

--- The fights the window lists under `view`: the source's (the store, or the sample history) that
--- pass its filters, newest first.
--- @param view table|nil
--- @param now number|nil
--- @return table records
function Fights.Rows(view, now)
    return Fights.Filter(NS.ResultsSource.All(), view, now)
end

-- ── pure: the options ───────────────────────────────────────────────────────────────────────────

local function byLabel(a, b) return a.label < b.label end

local function charOptions(records)
    local seen, list, names = {}, {}, {}
    for _, r in ipairs(records) do
        local key = Fights.CharKey(r)
        if not seen[key] then
            seen[key] = true
            local w = who(r)
            local name = tostring(w.name or "?")
            names[name] = (names[name] or 0) + 1
            list[#list + 1] = { value = key, label = name, realm = tostring(w.realm or "?"),
                                color = Tbl.ClassColor(w.class) }
        end
    end
    -- Two characters of one name on different realms read as Name-Realm.
    for _, o in ipairs(list) do if names[o.label] > 1 then o.label = o.label .. "-" .. o.realm end end
    table.sort(list, byLabel)
    return list
end

local function specOptions(records)
    local seen, list = {}, {}
    for _, r in ipairs(records) do
        local w = who(r)
        local kind = type(w.specID)
        if (kind == "number" or kind == "string") and not seen[w.specID] then
            seen[w.specID] = true
            local name = Tbl.SpecInfo(w.specID, w.specName)
            list[#list + 1] = { value = w.specID, label = name or tostring(w.specID) }
        end
    end
    table.sort(list, byLabel)
    return list
end

-- In Identity.ContentKeys()'s order: a kind this client does not have is never listed.
local function contentOptions(records)
    local present, list = {}, {}
    for _, r in ipairs(records) do
        local c = ident(r).content
        if c then present[c] = true end
    end
    for _, key in ipairs(NS.Identity.ContentKeys()) do
        if present[key] then list[#list + 1] = { value = key, label = Tbl.ContentLabel(key) } end
    end
    return list
end

local function boardOptions(records)
    local seen, list = {}, {}
    for _, r in ipairs(records) do
        local key = Fights.TargetKey(r)
        if not seen[key] then
            seen[key] = true
            list[#list + 1] = { value = key, label = Fights.TargetName(r) }
        end
    end
    table.sort(list, byLabel)
    return list
end

local function difficultyOptions(records)
    local seen, values, names = {}, {}, {}
    for _, r in ipairs(records) do
        local d = Fights.DifficultyOf(r)
        if not seen[d] then
            seen[d] = true
            values[#values + 1] = d
            local name = ident(r).difficultyName
            names[d] = type(name) == "string" and name ~= "" and name or nil
        end
    end
    table.sort(values)
    local list = {}
    for i, d in ipairs(values) do list[i] = { value = d, label = names[d] or L["No difficulty"] } end
    return list
end

local OPTION_LISTS = { character = charOptions, spec = specOptions, content = contentOptions,
                       board = boardOptions, difficulty = difficultyOptions }

--- `list` led by its "all" entry, and by a "current" one before it when `current` is given.
--- @return table list  the same table
function Fights.WithAll(list, label, current)
    table.insert(list, 1, { value = "all", label = label })
    if current then table.insert(list, 1, { value = "current", label = current }) end
    return list
end

--- The date range dropdown's options.
function Fights.DayOptions()
    return {
        { value = 1, label = L["Today"] }, { value = 7, label = L["Last 7 days"] },
        { value = 30, label = L["Last 30 days"] }, { value = 0, label = L["All time"] },
    }
end

-- The Group by modes, in the dropdown's order, each declared for its clients.
local GROUP_SPECS = { { key = "board" }, { key = "character" }, { key = "spec" },
                      { key = "content" }, { key = "none" } }

--- The Group by modes this client has, in order.
function Fights.GroupOrder()
    local out = {}
    for _, g in ipairs(GROUP_SPECS) do
        if NS.Compat.ForClient(g.clients) then out[#out + 1] = g.key end
    end
    return out
end
local GROUP_LABELS = {
    board = "Group: Encounter + difficulty", character = "Group: Character",
    content = "Group: Content", none = "Group: None",
}

--- Each dropdown's options under `view`, faceted: a list reads the fights that pass every filter but
--- its own. Each value list is led by its "all" entry. The `spec` list holds Retail's specs, or WoW
--- Forever's predominant talent trees.
--- @return table { character, spec, content, board, difficulty, days, group }
function Fights.Options(records, view, now, current)
    current = current or Fights.Current()
    local function facet(key) return OPTION_LISTS[key](Fights.Filter(records, view, now, current, key)) end
    local groups = {}
    for i, mode in ipairs(Fights.GroupOrder()) do
        groups[i] = { value = mode, label = mode == "spec" and specWords("Group: Spec", "Group: Talent tree")
                      or L[GROUP_LABELS[mode]] }
    end
    return {
        character = Fights.WithAll(facet("character"), L["All characters"], L["Current character"]),
        spec = Fights.WithAll(facet("spec"), specWords("All specs", "All talent trees"),
                              specWords("Current spec", "Current talent tree")),
        content = Fights.WithAll(facet("content"), L["All content"]),
        board = Fights.WithAll(facet("board"), L["All encounters and targets"]),
        difficulty = Fights.WithAll(facet("difficulty"), L["All difficulties"]),
        days = Fights.DayOptions(),
        group = groups,
    }
end

-- ── grouping (LootHistory's Group by) ──────────────────────────────────────────────────────────
-- One entry per mode: `of(record)` answers the group's key, its header label and its rank (the
-- groups' order, ascending). The header's value is in its own color: a character or a spec in the
-- class color, a content kind in its chip's hue.

--- `text` wrapped in an inline color escape of `color`.
function Fights.Colored(text, color)
    return ("|c%s%s|r"):format(Tbl.Hex(color), text)
end

local function boardGroup(r)
    local label = Fights.BoardLabel(r)
    return r.boardKey or ("?" .. Fights.TargetKey(r)), label, label:lower()
end

local function charGroup(r)
    local w = who(r)
    local name = tostring(w.name or "?")
    return Fights.CharKey(r), Fights.Colored(name, Tbl.ClassColor(w.class)), name:lower()
end

local function specGroup(r)
    local w = who(r)
    local class, spec = Tbl.ClassName(w.class), Tbl.SpecInfo(w.specID, w.specName)
    local label = spec and (class .. SEP .. spec) or class
    return tostring(w.class) .. "|" .. tostring(w.specID), Fights.Colored(label, Tbl.ClassColor(w.class)),
        label:lower()
end

local CONTENT_RANK = {}
for i, c in ipairs(NS.Identity.CONTENT) do CONTENT_RANK[c.key] = i end

local function contentGroup(r)
    local key = ident(r).content or "?"
    local text, color = Tbl.ContentLabel(key), Tbl.CONTENT_COLORS[key] or Tbl.CONTENT_NEUTRAL
    return key, Fights.Colored(text, color), ("%03d"):format(CONTENT_RANK[key] or 99)
end

Fights.GROUPS = {
    board = { of = boardGroup },
    character = { of = charGroup },
    spec = { of = specGroup },
    content = { of = contentGroup },
}

--- The grouping for `mode`, or nil for none: a mode this client does not have groups as none.
function Fights.GroupSpec(mode)
    for _, key in ipairs(Fights.GroupOrder()) do
        if key == mode then return Fights.GROUPS[mode] end
    end
    return nil
end

-- ── the Delta column ────────────────────────────────────────────────────────────────────────────
-- A context is { top, first, second }: the best DPS of a group, the fight that sets it and the next
-- one below it (nil when there is none). The fight detail's Delta or "Leads by" box (plan Task 4.2)
-- reads the same contexts through View:DeltaContext.

local function dpsOf(record)
    local dps = type(record) == "table" and record.dps
    return type(dps) == "number" and dps > 0 and dps or nil
end

-- `a` ranks above `b`: higher DPS; on a tie the earlier fight (it set the mark first), then the id,
-- as a best's board ranks them (modules/Bests.lua).
local function leads(a, b)
    local da, db = dpsOf(a), dpsOf(b)
    if da ~= db then return da > db end
    local ta, tb = a.t or 0, b.t or 0
    if ta ~= tb then return ta < tb end
    return tostring(a.id) < tostring(b.id)
end

--- The two fights with the highest DPS in `records`: the leader and its runner-up, either nil.
--- @return table|nil first, table|nil second
function Fights.Leaders(records)
    local first, second
    for _, r in ipairs(records or {}) do
        if dpsOf(r) then
            if not first or leads(r, first) then
                first, second = r, first
            elseif not second or leads(r, second) then
                second = r
            end
        end
    end
    return first, second
end

--- One group's context over `records`.
function Fights.Context(records)
    local first, second = Fights.Leaders(records)
    return { top = first and dpsOf(first), first = first, second = second }
end

--- `records` split by `groupOf(record)`: { [key] = { record, ... } }.
function Fights.ByGroup(records, groupOf)
    local out = {}
    for _, r in ipairs(records or {}) do
        local key = groupOf(r)
        out[key] = out[key] or {}
        out[key][#out[key] + 1] = r
    end
    return out
end

--- Whether `record` is the fight that sets its context's best.
function Fights.IsTop(record, ctx)
    local first = type(ctx) == "table" and ctx.first or nil
    return type(record) == "table" and first ~= nil and (first == record or first.id == record.id)
end

--- How far a fight's DPS sits from its group's best, as a percentage: 0 on the best, negative below
--- it. nil for a fight with no DPS, or a group with none.
--- @return number|nil pct
function Fights.Delta(record, top)
    local dps = dpsOf(record)
    if not dps or type(top) ~= "number" or top <= 0 then return nil end
    if dps == top then return 0 end
    return (dps / top - 1) * 100
end

local C = Tbl.COLORS

--- The Delta cell: "0.0%" in green on the group's leader and on a fight level with it, every other
--- fight its signed gap in red; a dash with nothing to measure.
--- @return string text, table color
function Fights.DeltaText(record, ctx)
    if type(ctx) ~= "table" then return DASH, C.dim end
    if Fights.IsTop(record, ctx) then return L["%.1f%%"]:format(0), C.green end
    local pct = Fights.Delta(record, ctx.top)
    if pct == nil then return DASH, C.dim end
    if pct == 0 then return L["%.1f%%"]:format(0), C.green end
    return L["%+.1f%%"]:format(pct), pct < 0 and C.red or C.green
end

--- The Delta cell's tooltip. `grouped` is whether the list is grouped (the best is its group's) or
--- flat (the best is the whole list's).
function Fights.DeltaTip(record, ctx, grouped)
    local pct = type(ctx) == "table" and Fights.Delta(record, ctx.top) or nil
    if pct == nil then
        return { DASH, grouped and L["No fight in this group to compare with."]
            or L["No fight in view to compare with."] }
    end
    local where = grouped and L["The best in this group: %s DPS."] or L["The best in view: %s DPS."]
    local lines = { L["%+.1f%% vs the best"]:format(pct), where:format(NS.ResultsTips.Grouped(ctx.top)) }
    if Fights.IsTop(record, ctx) then
        lines[1] = grouped and L["The best fight in its group."] or L["The best fight in view."]
        local second = ctx.second and dpsOf(ctx.second)
        if second then lines[#lines + 1] = L["Leads the next one by %s."]:format(NS.Format.SignedPct((ctx.top / second - 1) * 100)) end
    end
    if NS.ResultsSource.IsBest(record) then lines[#lines + 1] = { L["Your best on this board."], C.gold[1], C.gold[2], C.gold[3] } end
    return lines
end

-- ── the Status and Note columns (v0.2 Task C2, DPS Race's) ─────────────────────────────────────

-- The Status tag of the best on its board: its word, DPS Race's best blue and the trophy.
Fights.STATUS_ICON = "ph:trophy"

--- The Status cell: "Best", in the best blue with the trophy, on the fight that holds the best on its
--- board (NS.ResultsSource.IsBest: the store's or the sample's); "" on every other fight.
--- @return string text, table|nil color, string|nil icon
function Fights.StatusText(record)
    if NS.ResultsSource.IsBest(record) then return L["Best"], C.blue, Fights.STATUS_ICON end
    return "", nil, nil
end

--- The Status column's sort value: 1 for the best on its board, nil (last) for the rest.
function Fights.StatusSort(record)
    return NS.ResultsSource.IsBest(record) and 1 or nil
end

--- The Status cell's tooltip: the board, then what the tag means.
function Fights.StatusTip(record)
    if NS.ResultsSource.IsBest(record) then
        return { L["Best"], Fights.BoardLabel(record), L["Your best on this board."] }
    end
    return { DASH, Fights.BoardLabel(record), L["Another fight holds your best on this board."] }
end

Fights.NOTE_CHARS = 10
local ELLIPSIS = "\226\128\166"

local function noteOf(record)
    local note = type(record) == "table" and record.note
    if type(note) ~= "string" or note == "" then return nil end
    return note
end

--- The Note cell's text: the note's first NOTE_CHARS characters (UTF-8 characters, never a byte cut
--- through one), an ellipsis after them when the note is longer; "" with no note.
function Fights.NoteCell(record)
    local note = noteOf(record)
    if not note then return "" end
    local n, cut = 0, nil
    for pos in note:gmatch("()[^\128-\191]") do
        n = n + 1
        if n > Fights.NOTE_CHARS then
            cut = pos - 1
            break
        end
    end
    if not cut then return note end
    return note:sub(1, cut) .. ELLIPSIS
end

--- The Note column's sort value: the note in lower case, nil (last) with none.
function Fights.NoteSort(record)
    local note = noteOf(record)
    return note and note:lower() or nil
end

--- The Note cell's tooltip: "Note", then the whole note (wrapped by the tooltip).
function Fights.NoteTip(record)
    local note = noteOf(record)
    if not note then return { L["No note"], L["This fight has no note. Add one from its detail or the row's right-click menu."] } end
    return { L["Note"], note }
end

-- ── the columns ─────────────────────────────────────────────────────────────────────────────────

local function numberText(v)
    if type(v) ~= "number" then return DASH, C.dim end
    return NS.Format.Number(v), C.text
end

local function damageOf(record)
    local d = type(record.damage) == "table" and record.damage.merged
    return type(d) == "number" and d or nil
end

-- The target cell: what the fight was against, "+N" after it for the others that took damage.
local function targetText(record)
    local name, others = Fights.TargetName(record), ident(record).otherTargets
    if type(others) == "number" and others > 0 then name = L["%s +%d"]:format(name, others) end
    return name, C.text
end

-- The Delta column's scan: each group's context, kept on `view` for the cells, the tooltips and the
-- fight detail (View:DeltaContext).
local function deltaScan(view)
    return function(list, groupOf)
        view.contexts, view.ids, view.groupOf, view.grouped = {}, {}, groupOf, false
        local groups = Fights.ByGroup(list, groupOf)
        for key, records in pairs(groups) do
            if key ~= true then view.grouped = true end
            view.contexts[key] = Fights.Context(records)
        end
        for _, r in ipairs(list) do view.ids[r.id] = true end
    end
end

Fights.TARGET_W = 150
Fights.CONTENT_W = 90
-- DPS Race's Used and Note widths; the Status column fits its one boxed tag, "Best" and the trophy.
Fights.STATUS_W = 60
Fights.USED_W = 70
Fights.NOTE_W = 80
-- The Character column (v0.2 Task C1): a fixed width a twelve-letter name fits, the target column
-- taking the window's slack; its header's right edge drags it between the least and the most.
Fights.CHARACTER_W = 104
Fights.CHARACTER_MIN = 70
Fights.CHARACTER_MAX = 240

-- `results.columns`, the widths the header edges were dragged to (named state, docs/schema.md), or nil.
local function columnStore()
    local p = NS.db and NS.db.profile
    local r = p and p.results
    if type(r) ~= "table" then return nil end
    if type(r.columns) ~= "table" then r.columns = {} end
    return r.columns
end

--- The dragged column widths, `{ [key] = px }` (empty: every column at its shipped width).
--- @return table
function Fights.ColumnWidths()
    return columnStore() or {}
end

--- A header edge's release: column `key` stays `w` px wide.
function Fights.StoreColumnWidth(key, w)
    local store = columnStore()
    if store and type(w) == "number" then store[key] = math.floor(w + 0.5) end
end

--- Every column back to its shipped width (Reset position).
function Fights.ClearColumnWidths()
    local store = columnStore()
    if not store then return end
    for k in pairs(store) do store[k] = nil end
end

--- The fight table's columns (mockup §5, v0.2 Task C2): date, class and spec icons, character, item
--- level, encounter or target, content, length, damage, DPS, delta, status, used and note. `view`
--- (optional) keeps the Delta column's contexts (View:DeltaContext).
function Fights.Columns(view)
    view = view or {}
    view.contexts, view.ids = {}, {}
    view.groupOf = function() return true end
    local function ctxOf(r) return view.contexts[view.groupOf(r)] end
    return {
        { key = "date", label = L["Date"], width = 80, desc = true,
          sort = function(r) return r.t end,
          text = function(r) return Tbl.Date(r.t, "%d %b %H:%M") end },
        { key = "clsSpec", label = L["Class"], width = 40, kind = "icons" },
        { key = "character", label = L["Character"], width = Fights.CHARACTER_W, desc = false,
          resize = { min = Fights.CHARACTER_MIN, max = Fights.CHARACTER_MAX },
          sort = function(r) return tostring(who(r).name or ""):lower() end,
          text = function(r) return who(r).name or "?", Tbl.ClassColor(who(r).class) end },
        { key = "ilvl", label = L["iLvl"], width = 40, desc = true,
          sort = function(r) return who(r).ilvl end,
          text = function(r) return Tbl.Ilvl(who(r).ilvl) end },
        { key = "target", label = L["Encounter or target"], flex = true, min = Fights.TARGET_W, desc = false,
          sort = function(r) return Fights.TargetName(r):lower() end,
          text = targetText },
        { key = "content", label = L["Content"], width = Fights.CONTENT_W, kind = "badge", desc = false,
          sort = function(r) return CONTENT_RANK[ident(r).content] or 99 end,
          text = Tbl.ContentChip },
        { key = "len", label = L["Length"], width = 44, desc = true,
          sort = function(r) return r.duration end,
          text = function(r) return NS.Format.Length(r.duration), C.text end },
        { key = "damage", label = L["Damage"], width = 60, desc = true,
          sort = damageOf, bar = damageOf,
          text = function(r) return numberText(damageOf(r)) end },
        { key = "dps", label = L["DPS"], width = 62, desc = true,
          sort = dpsOf, bar = dpsOf,
          text = function(r) return numberText(dpsOf(r)) end },
        { key = "delta", label = L["Delta"], width = 64, desc = true,
          scan = deltaScan(view),
          sort = function(r)
              local ctx = ctxOf(r)
              return ctx and Fights.Delta(r, ctx.top)
          end,
          text = function(r) return Fights.DeltaText(r, ctxOf(r)) end,
          tip = function(r) return Fights.DeltaTip(r, ctxOf(r), view.grouped) end },
        { key = "status", label = L["Status"], width = Fights.STATUS_W, kind = "badge", desc = false,
          sort = Fights.StatusSort, text = Fights.StatusText, tip = Fights.StatusTip },
        -- What the fight used: the gear first, "+n" past what fits, a dash for nothing; sorted by how
        -- many, a fight with no usage record last either way.
        { key = "used", label = L["Used"], width = Fights.USED_W, kind = "items", desc = true,
          sort = function(r) return NS.ResultsUsage.Count(r) end,
          items = function(r) return NS.ResultsUsage.Icons(r) end },
        { key = "note", label = L["Note"], width = Fights.NOTE_W, desc = false,
          sort = Fights.NoteSort, text = function(r) return Fights.NoteCell(r), C.dim end,
          tip = Fights.NoteTip },
    }
end

-- ── the view ────────────────────────────────────────────────────────────────────────────────────

local View = {}
View.__index = View

local function checkbox(view, parent, key, label)
    local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    b:SetSize(20, 20)
    b.label = Tbl.Text(b, Tbl.FONT.TEXT)
    b.label:SetPoint("LEFT", b, "RIGHT", 1, 0)
    Tbl.SetCheckLabel(b, label)
    b:SetScript("OnClick", function() view:SetFilter(key, not view.filters[key]) end)
    -- The skin's check box, after the click script.
    NS.Skin.Checkbox(b)
    return b
end

local function buildBar(view)
    local bar = CreateFrame("Frame", nil, view.frame)
    bar:SetPoint("TOPLEFT", view.frame, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", view.frame, "TOPRIGHT", 0, 0)
    bar:SetHeight(2 * FILTER_H - 6)
    view.dropdowns = {}
    for _, spec in ipairs(Fights.Dropdowns()) do
        local dd = NS.MakeDropdown(bar, spec.width)
        if dd then
            dd.onSelect = function(value) view:SetFilter(spec.key, value) end
            view.dropdowns[spec.key] = dd
        end
    end
    view.bossesOnly = checkbox(view, bar, "bossesOnly", L["Bosses only"])
    view.save = Style.Button(bar, L["Save view"], function() view:SaveView() end)
    view.save.tip = { L["Save view"], L["Save these filters, the grouping and the sort as this profile's view of your fights."] }
    view.reset = Style.Button(bar, L["Reset view"], function() view:ResetView() end)
    view.reset.tip = { L["Reset view"], L["Go back to the view the addon ships with: your character, the last 7 days, grouped by encounter and difficulty, newest first."] }
    for _, b in ipairs({ view.save, view.reset }) do b:SetWidth(VIEW_BUTTON_W) end
    view.bar = bar
end

--- The fight list in `parent`.
--- @param parent table
--- @param hooks table  { select(record), selected() -> id|nil, menu(record, row), count(text),
---                       changed() after every redraw }
--- @return table view
function Fights.Build(parent, hooks)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    local view = setmetatable({ frame = frame, hooks = hooks or {}, filters = {}, delta = {},
                                barH = 2 * FILTER_H - 6 }, View)
    buildBar(view)
    view.listHost = CreateFrame("Frame", nil, frame)
    view.list = Tbl.New(view.listHost, Fights.Columns(view.delta), {
        sortKey = "date", sortDesc = true,
        onClick = function(r) if view.hooks.select then view.hooks.select(r) end end,
        onRightClick = function(r, row) if view.hooks.menu then view.hooks.menu(r, row) end end,
        empty = L["No fights match these filters."],
        widths = Fights.ColumnWidths, onColumnResize = Fights.StoreColumnWidth,
    })
    view:ApplyView(Fights.SavedView())
    return view
end

-- ── saved views (LootHistory's Save / Reset) ───────────────────────────────────────────────────
-- The list's view (its filters, its grouping and its sort) is the profile's `results.view`. Every
-- build applies it. Save view stores the view on screen there; Reset view stores the shipped one and
-- applies it.

--- The profile's view (the shipped one where the profile is not there yet).
function Fights.SavedView()
    local p = NS.db and NS.db.profile
    local r = p and p.results
    return type(r) == "table" and type(r.view) == "table" and r.view or Fights.StockView()
end

--- The view now, as a plain copy (results.view's shape).
function View:CaptureView()
    local v = {}
    for _, k in ipairs(Fights.VIEW_KEYS) do v[k] = self.filters[k] end
    v.sort, v.desc = self.list.sortKey, self.list.sortDesc
    return v
end

--- Apply `v` (results.view's shape); a key it leaves out takes its shipped value, and a sort on a
--- column this version does not have falls back to the shipped one.
function View:ApplyView(v)
    local f = full(v)
    for _, k in ipairs(Fights.VIEW_KEYS) do self.filters[k] = f[k] end
    local stock = Fights.StockView()
    local sortKey = self.list:column(f.sort) and f.sort or stock.sort
    self.list.sortKey, self.list.sortDesc = sortKey, f.desc ~= false
    self.list:paintHeader()
    if self.shownOnce then self:Refresh() end
end

-- While the window shows the sample history (test mode, a sim) the view is the sample's: Save and
-- Reset refuse with one line, so nothing the samples set reaches the profile.
local function sampleRefusal()
    if not NS.ResultsSource.IsMock() then return false end
    NS.Print(L["Not saved: the Results window is showing sample fights."])
    return true
end

-- The sample history spans several characters, so it opens on all of them; the view the player had
-- comes back when the store does (View:SampleView, the shell's OnSourceChanged).
Fights.SAMPLE_VIEW = { character = "all", spec = "all", days = 0 }

--- Enter (`on`) or leave the sample history's view: entering keeps the player's view to restore.
function View:SampleView(on)
    if on then
        if not self.realView then self.realView = self:CaptureView() end
        local v = self:CaptureView()
        for k, x in pairs(Fights.SAMPLE_VIEW) do v[k] = x end
        self:ApplyView(v)
    elseif self.realView then
        local real = self.realView
        self.realView = nil
        self:ApplyView(real)
    end
end

local function writeView(v)
    local p = NS.db and NS.db.profile
    if not p then return false end
    if type(p.results) ~= "table" then p.results = {} end
    p.results.view = v
    return true
end

function View:SaveView()
    if sampleRefusal() then return false end
    if not writeView(self:CaptureView()) then return false end
    NS.Print(L["The Results view is saved."])
    return true
end

function View:ResetView()
    if sampleRefusal() then return false end
    local stock = {}
    for k, v in pairs(Fights.StockView()) do stock[k] = v end
    writeView(stock)
    self:ApplyView(stock)
    NS.Print(L["The Results view is back to the one the addon ships with."])
    return true
end

-- ── the bar's layout ────────────────────────────────────────────────────────────────────────────

-- The configured widths grown by `extra` px between them, in proportion to each; the last takes the
-- rounding, so the shares add up to `extra` exactly.
local function stretched(dropdowns, extra)
    local total = 0
    for _, spec in ipairs(dropdowns) do total = total + spec.width end
    local widths, given = {}, 0
    for i, spec in ipairs(dropdowns) do
        local add = i == #dropdowns and extra - given or math.floor(extra * spec.width / total)
        widths[spec.key] = spec.width + add
        given = given + add
    end
    return widths
end

--- The bar's least width: every dropdown at its configured width, the gaps and both margins.
function Fights.BarMinWidth()
    local w = 2 * MARGIN - GAP
    for _, spec in ipairs(Fights.Dropdowns()) do w = w + spec.width + GAP end
    return w
end

--- Plan the bar, pure (no frame is read), across `width`: the dropdowns on the first row at their
--- configured widths, sharing what the bar has beyond them, so the last ends MARGIN short of the
--- bar's right edge; Bosses only on the second row at the left, Save view and Reset view on it at the
--- right, under the last dropdown's right edge. Answers each dropdown's x and width, the second row's
--- y, the check box's x and each button's right x, all from the bar's left.
function Fights.BarPlan(width)
    local extra = type(width) == "number" and math.floor(width - Fights.BarMinWidth()) or 0
    local dropdowns = Fights.Dropdowns()
    local widths = stretched(dropdowns, math.max(0, extra))
    local plan = { dropdowns = {}, widths = widths, y = -(FILTER_H - 2), check = MARGIN, buttons = {} }
    local x = MARGIN
    for _, spec in ipairs(dropdowns) do
        plan.dropdowns[spec.key] = x
        x = x + widths[spec.key] + GAP
    end
    plan.right = x - GAP
    plan.buttons.reset = plan.right
    plan.buttons.save = plan.right - VIEW_BUTTON_W - GAP
    return plan
end

-- Lay the bar out by Fights.BarPlan at `width`: re-anchored and the dropdowns re-sized, nothing
-- repainted, so the cheap layout runs it too.
function View:layoutBar(width)
    local plan = Fights.BarPlan(width)
    for _, spec in ipairs(Fights.Dropdowns()) do
        local dd = self.dropdowns[spec.key]
        if dd then
            dd:ClearAllPoints()
            dd:SetPoint("TOPLEFT", self.bar, "TOPLEFT", plan.dropdowns[spec.key], -6)
            dd:SetWidth(plan.widths[spec.key])
        end
    end
    self.bossesOnly:ClearAllPoints()
    self.bossesOnly:SetPoint("TOPLEFT", self.bar, "TOPLEFT", plan.check, plan.y)
    for key, b in pairs({ save = self.save, reset = self.reset }) do
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", self.bar, "TOPLEFT", plan.buttons[key], plan.y)
    end
    return self.barH
end

--- Lay the list out: the bar across `width`, the table beneath it.
function View:Layout(width, height)
    local barH = self:layoutBar(width)
    self.listHost:ClearAllPoints()
    self.listHost:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -barH)
    self.listHost:SetSize(width, math.max(1, height - barH))
    self.list:Layout(width, math.max(1, height - barH))
end

--- While the window is being sized (modules/Sizing.lua): the bar re-planned across `width` and the
--- table resized beneath it, nothing rebound.
function View:Resize(width, height)
    self:layoutBar(width)
    local h = math.max(1, height - self.barH)
    self.listHost:SetSize(width, h)
    self.list:Resize(width, h)
end

--- The bar's height.
function View:BarHeight()
    return self.barH
end

-- Put the filter values on the controls.
function View:paintFilters(options)
    for _, spec in ipairs(Fights.Dropdowns()) do
        local dd = self.dropdowns[spec.key]
        if dd then
            dd:SetOptions(options[spec.key])
            dd:SelectValue(self.filters[spec.key])
        end
    end
    self.bossesOnly:SetChecked(self.filters.bossesOnly == true)
end

--- Re-read the source and redraw: options, filtered list, count, selection.
function View:Refresh()
    self.shownOnce = true
    local all, now = NS.ResultsSource.All(), time()
    local current = Fights.Current()
    self:paintFilters(Fights.Options(all, self.filters, now, current))
    self.filtered = Fights.Filter(all, self.filters, now, current)
    local n = #self.filtered
    self.countText = n == 1 and L["1 fight"] or L["%d fights"]:format(n)
    if self.hooks.count then self.hooks.count(self.countText) end
    self.list.selected = self.hooks.selected and self.hooks.selected() or nil
    self.list.data = self.filtered
    self.list:SetGroup(Fights.GroupSpec(self.filters.group))
    if self.hooks.changed then self.hooks.changed() end
end

--- What the Delta column measured `record` against (Fights.Context's shape: its group under the
--- grouping now, or the whole list with none), or nil when the filters leave the fight out.
function View:DeltaContext(record)
    local d = self.delta
    if type(record) ~= "table" or not (d.ids and d.ids[record.id]) then return nil end
    return d.contexts[d.groupOf(record)]
end

--- Set one filter (or the grouping) and redraw.
function View:SetFilter(key, value)
    if Fights.StockView()[key] == nil then return false end
    self.filters[key] = value
    self:Refresh()
    return true
end

--- How many fights pass the filters now.
function View:Count()
    return self.filtered and #self.filtered or 0
end
