local _, NS = ...
-- modules/Results_InsightsData.lua — the Insights tab's pure half (Race mode plan Task D2, spec §7):
-- its filters, the faceted dropdown options with their counts, and the one stats pass that feeds the
-- cards and the chart sections. Ported from DPS Race @f8078c7 (modules/Results_InsightsData.lua) and
-- rebased on Combat Trail's fight records: every saved fight, a race being a fight with a race part
-- (modules/RaceRecord.lua). No frames: modules/Results_Insights.lua draws what this returns.
--
-- THE FILTERS mirror the Results list's (modules/Results_Fights.lua): character, spec, content and
-- date, then on Retail the Fights / Races / All filter. Under Races the race length and the dummy
-- kind apply too, and on Retail Clean only (no flagged race) and Include incomplete judge every race
-- in view (under Fights there is none). On WoW Forever there is no race control (clients-§4): a race
-- saved in the account-wide history counts as a fight there, with its race DPS.
--
-- A RACE CONTRIBUTES ITS RACE DPS (spec §7): every DPS here is NS.RaceRecord.Dps, the figure its race
-- board ranks. BOARD-RELATIVE: DPS compares only within a board (modules/Bests.lua Key: a fight's
-- character x spec x encounter board, a race's character x spec x dummy kind x length), so every
-- figure that mixes boards is a fight's % of its board's best, that best taken over the fights given
-- (the filtered set, not the whole store); raw DPS is for one board only. An incomplete race is
-- counted but never holds a DPS figure, as on its board.
--
-- PURE over plain stored records but for what it reads at CALL time: NS.L for the labels, date() and
-- time() for the local day a fight falls on, and the late-cast ignore list through
-- ResultsRaces.IsFlagged and RaceScoring.SplitLate, never a race's raw list. So a change to the list
-- re-scores every figure here on the next call. IsFlagged is memoized per record within one Options
-- or Compute call, never across calls, because the list can change in between.
--
-- ONE PASS. Compute walks the fights once, handing each to every REDUCERS entry, then runs the
-- FINALIZERS over what they gathered (the boards, sorted lists, gap days). A new section is one
-- reducer and one finalizer.

local InsightsData = {}
NS.InsightsData = InsightsData

local L = NS.L
local SEP = " \194\183 "

local function Fights() return NS.ResultsFights end
local function Races() return NS.ResultsRaces end

--- The view the addon ships (defaults/Profile.lua `results.insights`, the only place a default is
--- written): every character, spec, content and date, fights and races, Clean only off, Include
--- incomplete off. Insights is the cross-character view.
function InsightsData.Stock()
    return NS.defaults.profile.results.insights
end

--- The order Normalize checks the dropdowns in: the bar's, but the race length and the dummy kind
--- before the Fights / Races / All filter they sit under, so a race length no race has falls back
--- rather than the Races filter that offers it.
InsightsData.ORDER = { "character", "spec", "content", "days", "length", "dummyKind", "kind" }

--- The Overall board tab's key: every board.
InsightsData.OVERALL = "all"

local TAIL_EDGES = { 5, 10, 15, 20 }   -- the damage tail's buckets: 0-5, 5-10, 10-15, 15-20, 20+ s
local CONSISTENT_MIN = 3                -- a board tab's Consistency: the least fights on a board
local MAX_DAYS = 3660                   -- the per-day strip's longest span, a guard against a stray date
local UNKNOWN = "unknown"               -- a late cast with no spell ID (sealed): counted, never ignored

local function isRace(record) return NS.RaceRecord.IsRace(record) end

local function who(record)
    return type(record.who) == "table" and record.who or {}
end

local function ident(record)
    return type(record.identity) == "table" and record.identity or {}
end

--- Whether `f` lists races only (Retail, the kind filter on Races): the race-only filters and
--- sections apply then.
function InsightsData.UnderRaces(f)
    return Races().UnderRaces(f)
end

--- Whether the race checks (Clean only, Include incomplete) are offered under `f`: on Retail, unless
--- the view lists fights only.
function InsightsData.RaceChecks(f)
    return Races().On() and not (type(f) == "table" and f.kind == "fights")
end

-- ── the filters ─────────────────────────────────────────────────────────────────────────────────

-- `f` over the stock view, as a new table: only the known keys, a missing one at its stock value.
local function merged(f)
    f = type(f) == "table" and f or {}
    local out = {}
    for k, def in pairs(InsightsData.Stock()) do
        local v = f[k]
        if v == nil then v = def end
        out[k] = v
    end
    return out
end
InsightsData.Merged = merged

-- ResultsRaces.IsFlagged, memoized for one call.
local function flaggedMemo()
    local memo = {}
    return function(record)
        local v = memo[record]
        if v == nil then
            v = Races().IsFlagged(record)
            memo[record] = v
        end
        return v
    end
end

local function kindOf(record) return isRace(record) and "races" or "fights" end
local function raceLength(record) return isRace(record) and record.race.length or nil end

-- The value facets, in bar order: each one's value for a record and whether it applies under `f`
-- (a facet that does not apply passes every fight and offers no list).
local FACETS = {
    { key = "character", of = function(r) return Fights().CharKey(r) end },
    { key = "spec", of = function(r) return who(r).specID end },
    { key = "content", of = function(r) return ident(r).content end },
    { key = "kind", of = kindOf, applies = function() return Races().On() end },
    { key = "length", of = raceLength, applies = InsightsData.UnderRaces },
    { key = "dummyKind", of = function(r) return Races().KindOf(r) end, applies = InsightsData.UnderRaces },
}
local DATE = #FACETS + 1     -- the date range's slot after the value facets

local function applies(facet, f)
    return facet.applies == nil or facet.applies(f) and true or false
end

-- Whether `record` passes what no dropdown sets: a final fight, and on Retail the two race checks.
local function passesChecks(record, f, flagged)
    if type(record) ~= "table" or record.status ~= "final" then return false end
    if not (isRace(record) and InsightsData.RaceChecks(f)) then return true end
    if not f.includeIncomplete and record.race.status ~= "complete" then return false end
    return not (f.cleanOnly and flagged(record))
end

-- The one dropdown `record` fails (its slot: a FACETS index or DATE), 0 when it fails none, false
-- when it fails two or more (then it counts toward no dropdown's options).
local function missedSlot(record, f, since)
    local missed = 0
    for i, facet in ipairs(FACETS) do
        local want = f[facet.key]
        if want ~= "all" and applies(facet, f) and facet.of(record) ~= want then
            if missed ~= 0 then return false end
            missed = i
        end
    end
    if since and (record.t or 0) < since then
        if missed ~= 0 then return false end
        missed = DATE
    end
    return missed
end

--- The fights that pass `f`, in the order given.
--- @param records table  stored records
--- @param f table|nil  the stock view's shape; a missing key is its stock value
--- @param now number|nil  the epoch the date range is measured from (time())
--- @return table records
function InsightsData.Filter(records, f, now)
    f = merged(f)
    local flagged, since = flaggedMemo(), Fights().Since(f.days, now)
    local out = {}
    for _, r in ipairs(records or {}) do
        if passesChecks(r, f, flagged) and missedSlot(r, f, since) == 0 then out[#out + 1] = r end
    end
    return out
end

-- ── the faceted options ─────────────────────────────────────────────────────────────────────────

local function find(list, value)
    for _, o in ipairs(list) do
        if o.value == value then return o end
    end
    return nil
end

local function byLabel(a, b) return a.label < b.label end

local function charList(pool)
    local seen, list, names = {}, {}, {}
    for _, r in ipairs(pool) do
        local key = Fights().CharKey(r)
        if not seen[key] then
            seen[key] = true
            local w = who(r)
            local name = tostring(w.name or "?")
            names[name] = (names[name] or 0) + 1
            list[#list + 1] = { value = key, label = name, realm = tostring(w.realm or "?"),
                                color = NS.ResultsTable.ClassColor(w.class) }
        end
    end
    for _, o in ipairs(list) do if names[o.label] > 1 then o.label = o.label .. "-" .. o.realm end end
    table.sort(list, byLabel)
    return list
end

local function specList(pool)
    local seen, list = {}, {}
    for _, r in ipairs(pool) do
        local w = who(r)
        local kind = type(w.specID)
        if (kind == "number" or kind == "string") and not seen[w.specID] then
            seen[w.specID] = true
            local name = NS.ResultsTable.SpecInfo(w.specID, w.specName)
            list[#list + 1] = { value = w.specID, label = name or tostring(w.specID) }
        end
    end
    table.sort(list, byLabel)
    return list
end

local function contentList(pool)
    local present, list = {}, {}
    for _, r in ipairs(pool) do
        local c = ident(r).content
        if c then present[c] = true end
    end
    for _, key in ipairs(NS.Identity.ContentKeys()) do
        if present[key] then list[#list + 1] = { value = key, label = NS.ResultsTable.ContentLabel(key) } end
    end
    return list
end

local function kindList()
    return { { value = "fights", label = L["Fights only"] }, { value = "races", label = L["Races only"] } }
end

local function lengthList(pool)
    local seen, values = {}, {}
    for _, r in ipairs(pool) do
        local len = raceLength(r)
        if type(len) == "number" and not seen[len] then seen[len], values[#values + 1] = true, len end
    end
    table.sort(values)
    local list = {}
    for i, len in ipairs(values) do list[i] = { value = len, label = NS.Format.Length(len) } end
    return list
end

local function dummyKindList(pool)
    local present, list = {}, {}
    for _, r in ipairs(pool) do
        local k = Races().KindOf(r)
        if k then present[k] = true end
    end
    for _, key in ipairs(NS.Dummies.CATEGORIES) do
        if present[key] then list[#list + 1] = { value = key, label = NS.Dummies.Label(key) } end
    end
    if present.other then list[#list + 1] = { value = "other", label = NS.Dummies.Label("other") } end
    return list
end

local LISTS = { character = charList, spec = specList, content = contentList, kind = kindList,
                length = lengthList, dummyKind = dummyKindList }

-- The "all" head of each list, in this client's words.
local function heads()
    local forever = not NS.Compat.ForClient({ "retail" })
    return {
        character = L["All characters"], spec = forever and L["All talent trees"] or L["All specs"],
        content = L["All content"], kind = L["Fights and races"], length = L["Any race length"],
        dummyKind = L["All dummy kinds"],
    }
end

-- Each option's count among `pool`, written into its label: "Beast Mastery (28)".
local function countInto(list, pool, facet)
    local n = {}
    for _, r in ipairs(pool) do
        local v = facet.of(r)
        if v ~= nil then n[v] = (n[v] or 0) + 1 end
    end
    for _, o in ipairs(list) do
        o.count, o.name = n[o.value] or 0, o.label
        o.label = L["%s (%d)"]:format(o.label, o.count)
    end
end

-- One value facet's options: the values in `pool`, the current selection kept (at 0) when it is not
-- among them, each with its count, led by the "all" head with the pool's size and the number of
-- choices under it (the closed dropdown's figure, InsightsData.ClosedLabel).
local function facetOptions(facet, pool, records, want, head)
    local lister = LISTS[facet.key]
    local list = lister(pool)
    if want ~= "all" and not find(list, want) then
        list[#list + 1] = find(lister(records), want) or { value = want, label = tostring(want) }
    end
    countInto(list, pool, facet)
    table.insert(list, 1, { value = "all", count = #pool, name = head, choices = #list,
                            label = L["%s (%d)"]:format(head, #pool) })
    return list
end

-- The date ranges: all four, always (they nest, so a 0-count range is shown, never hidden).
local function dateOptions(pool, now)
    local list = Fights().DayOptions()
    for _, o in ipairs(list) do
        local since, n = Fights().Since(o.value, now), 0
        for _, r in ipairs(pool) do
            if since == nil or (r.t or 0) >= since then n = n + 1 end
        end
        o.count, o.name = n, o.label
        o.label = L["%s (%d)"]:format(o.label, n)
    end
    return list
end

--- Each dropdown's options under `f`, faceted: a dropdown lists the values present in the fights
--- that pass every OTHER filter, each with its count ({ value, label, count, name, color? }), led by
--- its "all" head (no "current" head: Insights is the cross-character view). The current selection
--- is always offered, at 0 when nothing matches it. A facet that does not apply under `f` (the race
--- ones on WoW Forever, the length and the dummy kind outside Races) has no list. One pass: each
--- fight is checked against every filter once, and counts toward a dropdown when it fails that
--- dropdown's filter alone (or none).
--- @return table options  { character, spec, content, days, kind?, length?, dummyKind? }
function InsightsData.Options(records, f, now)
    f = merged(f)
    records = records or {}
    local flagged, since = flaggedMemo(), Fights().Since(f.days, now)
    local pools = {}
    for i = 1, DATE do pools[i] = {} end
    for _, r in ipairs(records) do
        local missed = passesChecks(r, f, flagged) and missedSlot(r, f, since)
        if missed == 0 then
            for i = 1, DATE do pools[i][#pools[i] + 1] = r end
        elseif missed then
            pools[missed][#pools[missed] + 1] = r
        end
    end
    local out, head = { days = dateOptions(pools[DATE], now) }, heads()
    for i, facet in ipairs(FACETS) do
        if applies(facet, f) then
            out[facet.key] = facetOptions(facet, pools[i], records, f[facet.key], head[facet.key])
        end
    end
    return out
end

--- What a closed dropdown shows for `value` among its `options` (Options' lists): the All head with
--- the number of choices under it ("All characters (4)"), any other pick by its name alone. The date
--- ranges always number four, so their head shows its name alone. Nil when `value` is not offered.
--- @return string|nil
function InsightsData.ClosedLabel(options, value)
    local o = find(options or {}, value)
    if not o then return nil end
    if o.choices then return L["%s (%d)"]:format(o.name, o.choices) end
    return o.name or o.label
end

local function countOf(list, value)
    local o = find(list or {}, value)
    return o and o.count or 0
end

--- `f` with every selection that matches no fight set to its stock value, and the options under the
--- result. The dropdown the player just changed (`keep`) is never reset. The others are checked in
--- bar order, and the options are recomputed after each reset, so one reset cannot take a selection
--- that the reset before it would have saved. `f` itself is not written (a fallback never touches a
--- saved view).
--- @param keep string|nil  the key of the dropdown just changed
--- @return table f, table options
function InsightsData.Normalize(records, f, now, keep)
    f = merged(f)
    local stock = InsightsData.Stock()
    local options = InsightsData.Options(records, f, now)
    for _, key in ipairs(InsightsData.ORDER) do
        local list = options[key]
        if key ~= keep and list and f[key] ~= stock[key] and countOf(list, f[key]) == 0 then
            f[key] = stock[key]
            options = InsightsData.Options(records, f, now)
        end
    end
    return f, options
end

-- ── the stats pass: helpers ─────────────────────────────────────────────────────────────────────

local function midnight(t)
    local d = date("*t", t)
    return time({ year = d.year, month = d.month, day = d.day, hour = 0, min = 0, sec = 0 })
end

-- The next local midnight (time() normalizes day + 1, and a daylight saving change with it).
local function nextDay(t)
    local d = date("*t", t)
    return time({ year = d.year, month = d.month, day = d.day + 1, hour = 0, min = 0, sec = 0 })
end

local function size(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

--- The seconds a fight counts for: a race's time raced (its length, or its time in combat when
--- incomplete), else the fight's own length.
function InsightsData.Seconds(record)
    local s = Races().Seconds(record)
    if s == nil then s = record.duration end
    return type(s) == "number" and s or 0
end

local function tailBucket(tail)
    for i, edge in ipairs(TAIL_EDGES) do
        if tail < edge then return i end
    end
    return #TAIL_EDGES + 1
end

local function tally(map, casts)
    for _, cast in ipairs(casts) do
        local id = type(cast) == "table" and type(cast.spellID) == "number" and cast.spellID or UNKNOWN
        map[id] = (map[id] or 0) + 1
    end
end

-- What every reducer reads about one fight, worked out once: it holds a DPS figure when it has a
-- DPS and a board, and (a race) when it ran to the buzzer.
local function factsOf(record, flagged)
    local race = isRace(record)
    local dps = NS.RaceRecord.Dps(record)
    local key = NS.Bests.Key(record)
    local complete = type(dps) == "number" and dps > 0 and key ~= nil and not (race and record.race.status ~= "complete")
    return { race = race, complete = complete, dps = complete and dps or nil, key = key,
             flagged = race and flagged(record) or false }
end

local function charEntry(acc, record)
    local key = Fights().CharKey(record)
    local entry = acc.chars[key]
    if not entry then
        local w = who(record)
        entry = { key = key, name = tostring(w.name or "?"), realm = w.realm, class = w.class, n = 0,
                  byContent = {}, byCategory = {}, byLength = {} }
        acc.chars[key] = entry
        acc.charList[#acc.charList + 1] = entry
    end
    return entry
end

-- ── the stats pass: reducers (one call per fight each) ──────────────────────────────────────────

local REDUCERS = {
    -- The headline counts: the fights, their time, the races and the clean ones, the dates and days.
    function(acc, r, facts)
        acc.n = acc.n + 1
        acc.secs = acc.secs + InsightsData.Seconds(r)
        if facts.race then
            acc.races = acc.races + 1
            if not facts.flagged then acc.clean = acc.clean + 1 end
        end
        local d = r.t
        if type(d) ~= "number" then return end
        if not acc.first or d < acc.first then acc.first = d end
        if not acc.last or d > acc.last then acc.last = d end
        local day = midnight(d)
        acc.days[day] = (acc.days[day] or 0) + 1
    end,
    -- Who fought: each character with its content kinds and its races' dummy kinds, and the specs.
    function(acc, r, facts)
        local entry = charEntry(acc, r)
        entry.n = entry.n + 1
        local content = ident(r).content or "?"
        entry.byContent[content] = (entry.byContent[content] or 0) + 1
        acc.contents[content] = true
        if facts.race then
            local kind = Races().KindOf(r)
            entry.byCategory[kind] = (entry.byCategory[kind] or 0) + 1
            acc.categories[kind] = true
        end
        local spec = who(r).specID
        if spec ~= nil then acc.specs[spec] = true end
    end,
    -- The race lengths, per character.
    function(acc, r)
        local length = raceLength(r)
        if type(length) ~= "number" then return end
        local byLength = charEntry(acc, r).byLength
        byLength[length] = (byLength[length] or 0) + 1
        acc.lengths[length] = true
    end,
    -- The late casts by spell, split by the ignore list.
    function(acc, r, facts)
        if not facts.race then return end
        local counted, ignored = NS.RaceScoring.SplitLate(r.race, acc.set)
        tally(acc.lateCounted, counted)
        tally(acc.lateIgnored, ignored)
    end,
    -- The damage tail after the buzzer.
    function(acc, r, facts)
        local tail = facts.race and r.race.tail or nil
        if type(tail) ~= "number" then return end
        local i = tailBucket(tail)
        acc.tail[i] = acc.tail[i] + 1
    end,
    -- The fights with a DPS figure: every DPS figure reads these.
    function(acc, r, facts)
        if facts.complete then acc.complete[#acc.complete + 1] = { record = r, dps = facts.dps, key = facts.key } end
    end,
}

-- ── the stats pass: finalizers (once, in order) ─────────────────────────────────────────────────

-- Date order, then id: the order bests are set in (Bests' own).
local function earlier(a, b)
    local ta, tb = a.record.t or 0, b.record.t or 0
    if ta ~= tb then return ta < tb end
    return tostring(a.record.id) < tostring(b.record.id)
end

local function newBoard(e)
    local r = e.record
    local w = who(r)
    return { key = e.key, scope = InsightsData.ScopeKey(r), specID = w.specID, class = w.class, spec = w.specName,
             name = tostring(w.name or "?"), n = 0, sum = 0, first = r, worstDps = e.dps, pct = {} }
end

-- One fight, in date order, onto its board: a new best when it beats the board's best so far.
local function onBoard(out, e)
    local board = out.boards[e.key]
    if not board then
        board = newBoard(e)
        out.boards[e.key] = board
    elseif e.dps > board.bestDps then
        local gain = board.bestDps > 0 and (e.dps / board.bestDps - 1) * 100 or nil
        out.newBests[#out.newBests + 1] = { record = e.record, dps = e.dps, key = e.key, prev = board.best,
                                            prevDps = board.bestDps, gain = gain }
    end
    if not board.best or e.dps > board.bestDps then board.best, board.bestDps = e.record, e.dps end
    if e.dps < board.worstDps then board.worstDps = e.dps end
    board.n, board.sum = board.n + 1, board.sum + e.dps
    local best = out.totals.best
    if not best or e.dps > best.dps then out.totals.best = { record = e.record, dps = e.dps, key = e.key } end
end

-- Each fight's % of its board's best, and each board's average, spread (CV) and average %.
local function boardFigures(acc, out)
    local spread, pctSum = {}, {}
    for _, board in pairs(out.boards) do board.avg = board.sum / board.n end
    for _, e in ipairs(acc.complete) do
        local board = out.boards[e.key]
        e.pct = board.bestDps > 0 and e.dps / board.bestDps or 0
        board.pct[e.record.id] = e.pct
        spread[board] = (spread[board] or 0) + (e.dps - board.avg) ^ 2
        pctSum[board] = (pctSum[board] or 0) + e.pct
    end
    for _, board in pairs(out.boards) do
        board.cv = board.avg > 0 and math.sqrt(spread[board] / board.n) / board.avg or nil
        board.avgPct = pctSum[board] / board.n
    end
end

local CATEGORY_RANK = {}
for i, key in ipairs(NS.Dummies.CATEGORIES) do CATEGORY_RANK[key] = i end

-- The race tabs first, in the catalog's kind order then the shorter length; then the fight boards
-- by name.
local function inTabOrder(a, b)
    if a.race ~= b.race then return a.race end
    if a.race then
        local ra, rb = CATEGORY_RANK[a.category] or 99, CATEGORY_RANK[b.category] or 99
        if ra ~= rb then return ra < rb end
        if (a.length or 0) ~= (b.length or 0) then return (a.length or 0) < (b.length or 0) end
    end
    if a.label ~= b.label then return a.label:lower() < b.label:lower() end
    return a.key < b.key
end

local function byBest(a, b)
    if a.best ~= b.best then return a.best > b.best end
    return tostring(a.boardKey) < tostring(b.boardKey)
end

local function moreConsistent(a, b)
    if a.avgPct ~= b.avgPct then return a.avgPct > b.avgPct end
    return tostring(a.boardKey) < tostring(b.boardKey)
end

-- One spec's row on a board tab, off its board (a character's spec: boards are per character).
local function specRow(board)
    return { boardKey = board.key, specID = board.specID, class = board.class, spec = board.spec, name = board.name,
             record = board.best, best = board.bestDps, worst = board.worstDps, avg = board.avg, n = board.n,
             cv = board.cv, avgPct = board.avgPct }
end

--- A board tab's name: a race's dummy kind and length ("Cleave · 3:00"), a fight's encounter or target,
--- difficulty and tier (Fights.BoardLabel).
function InsightsData.ScopeLabel(record)
    if isRace(record) then
        return NS.Dummies.Label(Races().KindOf(record)) .. SEP .. NS.Format.Length(record.race.length)
    end
    return Fights().BoardLabel(record)
end

local function newTab(board)
    local r = board.first
    local race = isRace(r)
    return { key = board.scope, race = race, category = race and Races().KindOf(r) or nil,
             length = raceLength(r), label = InsightsData.ScopeLabel(r), n = 0, specs = {}, consistency = {} }
end

-- The board tabs: the boards gathered by what they were against (a race's dummy kind x length, a
-- fight's encounter board), each with its characters' specs best first (Spec Comparison) and those
-- with CONSISTENT_MIN fights or more, the most consistent first (Consistency).
local function boardTabs(out)
    local byScope = {}
    for _, board in pairs(out.boards) do
        local tab = byScope[board.scope]
        if not tab then
            tab = newTab(board)
            byScope[board.scope] = tab
            out.boardTabs[#out.boardTabs + 1] = tab
        end
        local row = specRow(board)
        tab.n = tab.n + board.n
        tab.specs[#tab.specs + 1] = row
        if board.n >= CONSISTENT_MIN then tab.consistency[#tab.consistency + 1] = row end
    end
    table.sort(out.boardTabs, inTabOrder)
    for _, tab in ipairs(out.boardTabs) do
        table.sort(tab.specs, byBest)
        table.sort(tab.consistency, moreConsistent)
    end
end

-- The cards that read the boards: the average % of board best, and the raw average on one board.
local function boardCards(acc, out)
    local t, n, pct, dps = out.totals, #acc.complete, 0, 0
    if n == 0 then return end
    for _, e in ipairs(acc.complete) do pct, dps = pct + e.pct, dps + e.dps end
    t.avgPct = pct / n
    local key = next(out.boards)
    if next(out.boards, key) == nil then
        t.oneBoard, t.avgDps = key, dps / n
    end
end

local function byCount(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if (a.id == nil) ~= (b.id == nil) then return a.id ~= nil end
    return (a.id or 0) < (b.id or 0)
end

local function lateList(map)
    local list = {}
    for id, count in pairs(map) do
        local unknown = id == UNKNOWN
        list[#list + 1] = { id = (not unknown) and id or nil, unknown = unknown or nil, count = count }
    end
    table.sort(list, byCount)
    return list
end

-- One entry per local day from the first fight's to the last's, the days with none included.
local function byDay(acc, out)
    if not acc.first then return end
    local day, last = midnight(acc.first), midnight(acc.last)
    if (last - day) / 86400 > MAX_DAYS then day = midnight(last - MAX_DAYS * 86400) end
    while day <= last do
        out.byDay[#out.byDay + 1] = { day = day, n = acc.days[day] or 0 }
        day = nextDay(day)
    end
end

-- The keys of `set` in `order`'s order, then any other (sorted), for a stacked bar's segments.
local function ordered(set, order)
    local out, seen = {}, {}
    for _, key in ipairs(order) do
        if set[key] then out[#out + 1], seen[key] = key, true end
    end
    local rest = {}
    for key in pairs(set) do if not seen[key] then rest[#rest + 1] = key end end
    table.sort(rest, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(rest) do out[#out + 1] = key end
    return out
end

local FINALIZERS = {
    -- The boards in date order, the new bests, the peak, then the board figures and the progression.
    function(acc, out)
        table.sort(acc.complete, earlier)
        for _, e in ipairs(acc.complete) do onBoard(out, e) end
        boardFigures(acc, out)
        out.progression = acc.complete
    end,
    function(_, out) boardTabs(out) end,
    boardCards,
    -- The headline cards.
    function(acc, out)
        local t = out.totals
        t.count, t.time, t.races, t.clean = acc.n, acc.secs, acc.races, acc.clean
        t.chars, t.specs, t.activeDays = #acc.charList, size(acc.specs), size(acc.days)
        t.first, t.last, t.newBests = acc.first, acc.last, #out.newBests
    end,
    -- The characters, most fights first; their content kinds in Identity's order, their races'
    -- dummy kinds in the catalog's.
    function(acc, out)
        table.sort(acc.charList, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a.key < b.key
        end)
        out.byChar = acc.charList
        out.byCharContent = { rows = acc.charList, keys = ordered(acc.contents, NS.Identity.ContentKeys()) }
        out.byCharTarget = { rows = acc.charList, keys = ordered(acc.categories, NS.Dummies.CATEGORIES) }
    end,
    -- Each character's races by length, the lengths shortest first.
    function(acc, out)
        local lengths = {}
        for length in pairs(acc.lengths) do lengths[#lengths + 1] = length end
        table.sort(lengths)
        out.byCharLength = { rows = acc.charList, keys = lengths }
    end,
    -- The late casts by spell, the counted and the ignored apart.
    function(acc, out)
        out.lateBySpell = { counted = lateList(acc.lateCounted), ignored = lateList(acc.lateIgnored) }
    end,
    byDay,
    -- The damage tail's buckets; the last is open-ended. None when no race had a tail.
    function(acc, out)
        local any = false
        for _, n in ipairs(acc.tail) do any = any or n > 0 end
        if not any then return end
        for i, n in ipairs(acc.tail) do
            out.tail[i] = { lo = TAIL_EDGES[i - 1] or 0, hi = TAIL_EDGES[i], n = n }
        end
    end,
}

-- ── the stats pass ──────────────────────────────────────────────────────────────────────────────

local function newAcc()
    local tail = {}
    for i = 1, #TAIL_EDGES + 1 do tail[i] = 0 end
    return {
        n = 0, secs = 0, races = 0, clean = 0, chars = {}, charList = {}, contents = {}, categories = {},
        specs = {}, days = {}, lengths = {}, lateCounted = {}, lateIgnored = {}, tail = tail, complete = {},
        set = NS.LateIgnore and NS.LateIgnore.Set() or nil,
    }
end

--- The board tab a fight sits under: "race:<kind>|<length>" for a race, "fight:<board key>" for a
--- fight.
function InsightsData.ScopeKey(record)
    if isRace(record) then
        return "race:" .. tostring(Races().KindOf(record)) .. "|" .. tostring(record.race.length)
    end
    return "fight:" .. tostring(record.boardKey or Fights().TargetKey(record))
end

--- The fights the board tab `key` reads: those under that tab, or every one for the Overall tab
--- (InsightsData.OVERALL, or nil).
function InsightsData.Scope(records, key)
    if key == nil or key == InsightsData.OVERALL then return records end
    local out = {}
    for _, r in ipairs(records or {}) do
        if type(r) == "table" and InsightsData.ScopeKey(r) == key then out[#out + 1] = r end
    end
    return out
end

--- Everything the cards and the sections show, in one pass over `records` (already filtered:
--- InsightsData.Filter).
--- @return table stats  { totals (the cards: count, time, races, clean, best { record, dps, key },
---   avgPct, avgDps and oneBoard on one board, newBests, chars, specs, first, last, activeDays),
---   boards ([Bests.Key] = { best, bestDps, worstDps, avg, cv, n, first, avgPct, scope, pct }),
---   progression ({ record, dps, key, pct } in date order), boardTabs ({ key, race, category, length,
---   label, n, specs, consistency }), byChar, byCharContent / byCharTarget / byCharLength ({ rows,
---   keys }), lateBySpell ({ counted, ignored }, each { id, unknown?, count }), byDay ({ day, n }),
---   tail ({ lo, hi?, n }, empty with no tail), newBests ({ record, dps, key, prev, prevDps, gain }) }
function InsightsData.Compute(records)
    local flagged, acc = flaggedMemo(), newAcc()
    for _, r in ipairs(records or {}) do
        if type(r) == "table" then
            local facts = factsOf(r, flagged)
            for i = 1, #REDUCERS do REDUCERS[i](acc, r, facts) end
        end
    end
    local out = {
        totals = { count = 0, time = 0, races = 0, clean = 0, newBests = 0, chars = 0, specs = 0, activeDays = 0 },
        boards = {}, progression = {}, boardTabs = {}, byChar = {}, lateBySpell = { counted = {}, ignored = {} },
        byDay = {}, tail = {}, newBests = {},
    }
    for i = 1, #FINALIZERS do FINALIZERS[i](acc, out) end
    return out
end
