local _, NS = ...
-- modules/Results_TimelineData.lua — the ability timeline's pure half (spec §7, plan Task 4.3): the
-- rows, the two icon strips, the span and its ticks, the zoom's arithmetic, the lanes' and strips'
-- geometry and the words its tooltips and legend carry. No frame is touched here; the window is
-- modules/Results_Timeline.lua, which loads after this file. Adapted from DPS Race @045f479
-- (modules/Results_TimelineData.lua) without its race: no race length, no buzzer; a fight's own
-- length is the axis, and each fight's casts are timed from that fight's own start, so the two
-- fights' lanes line up at 0:00 whatever day they were fought. A race (Retail) is the one exception
-- (ruling X9): its casts and its length run on the race clock, from its first hit (its part's
-- `firstHit`, modules/Results_Races.lua Clock), its axis reaches at least its length, and Build
-- answers that length as `buzzer`, where the window draws the buzzer line.
--
-- THE CASTS are the stored record's packed list (modules/CastCodec.lua), decoded here: { t, spellID,
-- unit = "player" | "pet", interrupted }, with the record's base cooldowns beside it (`cooldowns`,
-- { [id] = ms }). Every value is plain: it went through NS.Secrets on its way into the record.
--
-- THE ROWS. One per ability and caster that either fight cast, each fight's times and counts;
-- abilities with a base cooldown of 29 s or more first (NS.Casts.IsLong), the longest first; then
-- the rest by this fight's count, then the compared fight's; the player's before the pet's; then the
-- spell ID. A row's cooldown is this fight's, or the compared fight's when this fight never cast it.
-- With the pet toggle off (`opts.showPet == false`) the pet's rows and its icons are left out.
--
-- THE COMPARED FIGHT (until plan Task 4.4's compare owns it): the fight a row menu picked (Compare
-- With This Fight), else the best on the fight's board, else the runner-up when the fight is the
-- best, among the fights the Results window shows (the store, or the sample history in test mode).

local Data = {}
NS.ResultsTimelineData = Data

local L = NS.L
local Style = NS.Style
local SEP = " \194\183 "

-- ── the geometry (the window lays itself out from these, never from a size read back) ──────────
-- A 150 px name cell (the icon and the name on the top lane's line, the cooldown under it), 10 px,
-- the lanes, then each lane's count 10 px past its right end in a 26 px cell; each lane 16 px, 2 px
-- between a pair's lanes and 10 px between pairs.
Data.MIN_WIDTH = 640
Data.MIN_HEIGHT = 240
Data.PAD = 12
Data.NAME_W = 150
Data.COUNT_W = 26
Data.COUNT_GAP = 10
Data.GAP = 10
Data.LANE_H = 16
Data.LANE_GAP = 2
Data.PAIR_GAP = 10
Data.PAIR_H = 2 * Data.LANE_H + Data.LANE_GAP + Data.PAIR_GAP
Data.INSET = 1          -- half a tick: one at 0:00 or at the end stays inside its lane
-- The Casts strips: 14 px icons, closer than 15 px apart they stack onto another row 18 px on, 4 px
-- under the heading, a lane pair's gap between the two strips and 4 px over their own axis, at most
-- MAX_STACK rows a strip.
Data.CAST_PITCH = 15
Data.CAST_STEP = 18
Data.CASTS_PAD = 4
Data.STRIP_GAP = Data.LANE_GAP
Data.CASTS_AXIS_H = 16
Data.MAX_STACK = 12
-- The zoom steps (the time axis's width over the lanes'), and a Shift+wheel notch or an arrow's
-- click while zoomed: a quarter of the view. The scrollbar (zoomed only) is 10 px tall, 4 px under
-- the pinned axis.
Data.ZOOMS = { 1, 1.5, 2, 3, 4, 6, 8 }
Data.PAN = 0.25
Data.SCROLL_H = 10
Data.SCROLL_GAP = 4
-- The zoom level's color: the caption gray at 1x; above it from GOLD at the first step to HOT (the
-- Delta column's red) at the last.
Data.LEVEL_REST = Style.Tok("text.disabled")
Data.HOT = NS.ResultsTable.COLORS.red

-- ── the casts ───────────────────────────────────────────────────────────────────────────────────

-- A race's clock (modules/Results_Races.lua Clock), nil for a fight and on WoW Forever.
local function clockOf(record)
    local Races = NS.ResultsRaces
    return Races and Races.Clock(record) or nil
end

--- A fight's casts, decoded, in stored order (an empty list for none); a race's on its race clock
--- (ruling X9), from its first hit.
--- @param record table|nil
--- @return table casts  { { t, spellID, unit, interrupted }, ... }
function Data.Decode(record)
    if type(record) ~= "table" then return {} end
    local casts, clock = NS.CastCodec.Decode(record.casts), clockOf(record)
    return clock and NS.RaceRecord.OnClock(casts, clock.shift) or casts
end

--- Whether a fight has casts to draw (the detail's Timeline button is live only then).
function Data.Has(record)
    return #Data.Decode(record) > 0
end

local function keeps(c, showPet)
    return showPet ~= false or c.unit ~= "pet"
end

--- A fight's casts in time order (a copy), the pet's left out when `showPet` is false.
--- @return table casts  { { t, spellID, unit, pet, interrupted }, ... }
function Data.CastsOf(record, showPet)
    local out = {}
    for _, c in ipairs(Data.Decode(record)) do
        if keeps(c, showPet) then
            out[#out + 1] = { t = c.t, spellID = c.spellID, unit = c.unit, pet = c.unit == "pet",
                              interrupted = c.interrupted }
        end
    end
    table.sort(out, function(a, b) return (tonumber(a.t) or 0) < (tonumber(b.t) or 0) end)
    return out
end

--- Whether either fight has a pet cast (the pet toggle shows only then).
function Data.HasPet(record, other)
    for _, r in ipairs({ record, other }) do
        for _, c in ipairs(Data.Decode(r)) do
            if c.unit == "pet" then return true end
        end
    end
    return false
end

-- ── the rows ────────────────────────────────────────────────────────────────────────────────────

local function before(a, b)
    local ia, ib = NS.Casts.IsLong(a.cd), NS.Casts.IsLong(b.cd)
    if ia ~= ib then return ia end
    if ia and a.cd ~= b.cd then return a.cd > b.cd end
    if a.countA ~= b.countA then return a.countA > b.countA end
    if a.countB ~= b.countB then return a.countB > b.countB end
    if a.pet ~= b.pet then return not a.pet end
    return a.spellID < b.spellID
end

-- Each group of `record`'s casts into its row (made on first sight), on lane `side` ("a" this
-- fight, "b" the compared fight).
local function merge(rows, index, record, side, showPet)
    if type(record) ~= "table" then return end
    local kept = {}
    for _, c in ipairs(Data.Decode(record)) do
        if keeps(c, showPet) then kept[#kept + 1] = c end
    end
    for _, g in ipairs(NS.Casts.Group(kept, record.cooldowns)) do
        local key = g.unit .. ":" .. g.spellID
        local row = index[key]
        if not row then
            row = { spellID = g.spellID, unit = g.unit, pet = g.unit == "pet", cd = 0, a = {}, b = {},
                    countA = 0, countB = 0 }
            index[key] = row
            rows[#rows + 1] = row
        end
        row[side] = g.times
        if side == "a" then row.countA = g.count else row.countB = g.count end
        if row.cd == 0 then row.cd = g.cd end
    end
end

--- The timeline's rows: one per ability and caster either fight cast, with each fight's times.
--- @param record table  the fight shown (the top lanes)
--- @param other table|nil  the fight it is compared with (the bottom lanes)
--- @param showPet boolean|nil  false leaves the pet's abilities out
--- @return table rows  { { spellID, unit, pet, cd (ms, 0 unknown), a = { t, ... }, b = { t, ... }, countA, countB }, ... }
function Data.Rows(record, other, showPet)
    local rows, index = {}, {}
    merge(rows, index, record, "a", showPet)
    merge(rows, index, other, "b", showPet)
    table.sort(rows, before)
    return rows
end

-- A fight's length on its own clock: a race's from its first hit, and never short of its buzzer.
local function lengthOf(record)
    local n = type(record) == "table" and tonumber(record.duration) or nil
    n = n and n > 0 and n or 0
    local clock = clockOf(record)
    if not clock then return n end
    return math.max(n - clock.shift, clock.length)
end

--- The axis's span in seconds: the longer fight of the two (a picked fight may be on another board).
function Data.Span(record, other)
    return math.max(1, lengthOf(record), lengthOf(other))
end

--- Everything the window draws for a fight and the fight it is compared with.
--- @param record table|nil
--- @param other table|nil
--- @param opts table|nil  { showPet = boolean } (the pet's abilities shown unless false)
--- @return table  { rows, stripA, stripB, len, buzzer (a race's length: its buzzer line, else nil) }
function Data.Build(record, other, opts)
    local showPet = not (type(opts) == "table" and opts.showPet == false)
    local clock = clockOf(record)
    return {
        buzzer = clock and clock.length or nil,
        rows = record and Data.Rows(record, other, showPet) or {},
        stripA = Data.CastsOf(record, showPet),
        stripB = Data.CastsOf(other, showPet),
        len = Data.Span(record, other),
    }
end

--- The fight `record` is compared with, and what it is: "picked" (the row menu's Compare With This
--- Fight), "best" (the best on its board) or "runnerUp" (the fight is the best). Nil with none. The
--- compare's own answer (modules/Results_Compare.lua, Compare.Pick), so the timeline, the gear view
--- and the compare window never disagree.
--- @return table|nil other, string|nil kind
function Data.CompareTarget(record)
    if type(record) ~= "table" then return nil end
    return NS.ResultsCompare.Pick(record)
end

-- ── the axis and the zoom ───────────────────────────────────────────────────────────────────────

-- The round steps a zoomed axis labels in, in seconds.
local STEPS = { 1, 2, 5, 10, 15, 30, 60, 120, 300, 600 }

local function roundStep(raw)
    for _, step in ipairs(STEPS) do
        if step >= raw then return step end
    end
    return math.ceil(raw / 600) * 600
end

--- The axis's ticks: 0, the quarters and the end; zoomed in (`zoom` > 1), every round step that
--- leaves about a quarter of the lanes' width between labels, then the end (a step within half a step
--- of the end gives way to it).
function Data.Ticks(span, zoom)
    if not zoom or zoom <= 1 then return { 0, span / 4, span / 2, span * 3 / 4, span } end
    local step, out = roundStep(span / (4 * zoom)), {}
    local t = 0
    while t < span - step / 2 do
        out[#out + 1] = t
        t = t + step
    end
    out[#out + 1] = span
    return out
end

--- The zoom at step `i` of ZOOMS (clamped to the steps).
function Data.ZoomAt(i)
    local n = #Data.ZOOMS
    return Data.ZOOMS[math.max(1, math.min(n, tonumber(i) or 1))]
end

--- The view's left edge, a fraction of the zoomed axis, clamped so the view stays on the axis; a
--- value a rounding error short of either end (the thumb dragged there) snaps onto it.
function Data.ClampPos(pos, zoom)
    local hi = 1 - 1 / zoom
    pos = math.max(0, math.min(hi, tonumber(pos) or 0))
    if pos > hi - 1e-9 then return hi end
    if pos < 1e-9 then return 0 end
    return pos
end

--- The left edge after zooming from `from` to `to` about the point `at` of the way across the view
--- (0 its left edge, 1 its right; the middle without): that moment stays where it was, where it can.
function Data.Rezoom(pos, from, to, at)
    at = tonumber(at) or 0.5
    return Data.ClampPos((tonumber(pos) or 0) + at / from - at / to, to)
end

--- How far across a view `laneW` wide, its left edge at `laneLeft`, the point `x` is (0 to 1), or nil
--- off the view (a Ctrl+wheel over the names or the counts zooms about the middle).
function Data.CursorAt(x, laneLeft, laneW)
    if type(x) ~= "number" or type(laneLeft) ~= "number" or type(laneW) ~= "number" or laneW <= 0 then return nil end
    local at = (x - laneLeft) / laneW
    if at < 0 or at > 1 then return nil end
    return at
end

--- The left edge's range at `zoom` (the scrollbar's values, 0 to this): 0 at 1x.
function Data.PosRange(zoom)
    return math.max(0, 1 - 1 / (tonumber(zoom) or 1))
end

--- The band the scrollbar takes at the window's bottom at `zoom`: its height and gap zoomed in, else 0.
function Data.BarBand(zoom)
    return (tonumber(zoom) or 1) > 1 and Data.SCROLL_H + Data.SCROLL_GAP or 0
end

--- The zoom level's color at step `i` of ZOOMS: LEVEL_REST at 1x; above it GOLD at the first step to
--- HOT at the last, in even steps between.
--- @return table  { r, g, b }
function Data.ZoomColor(i)
    local n = #Data.ZOOMS
    i = math.max(1, math.min(n, tonumber(i) or 1))
    if i <= 1 then return Data.LEVEL_REST end
    local f, from, to = n > 2 and (i - 2) / (n - 2) or 1, Style.GOLD, Data.HOT
    return { from[1] + (to[1] - from[1]) * f, from[2] + (to[2] - from[2]) * f, from[3] + (to[3] - from[3]) * f }
end

--- A cast tick's middle x in a lane `width` wide: INSET + clamp(t, 0, span) / span x (width - 2 x INSET).
--- A pre-pull cast sits at 0:00, one past the fight's length (a tail) at the end. Nil without a time.
function Data.MarkX(t, span, width)
    if type(t) ~= "number" or type(span) ~= "number" or span <= 0 then return nil end
    local inset = Data.INSET
    return inset + math.max(0, math.min(span, t)) / span * math.max(0, width - 2 * inset)
end

--- The lanes' geometry in a window `width` wide: the content's width, the lanes' left (past the name
--- cell and the gap) and their width (all but the count cell after them, COUNT_GAP past their end).
--- @return number cw, number laneX, number laneW
function Data.LaneGeometry(width)
    local cw = math.max(100, (tonumber(width) or Data.MIN_WIDTH) - 2 * Data.PAD)
    local laneX = Data.NAME_W + Data.GAP
    return cw, laneX, math.max(40, cw - laneX - Data.COUNT_GAP - Data.COUNT_W)
end

-- The row whose last icon sits furthest left: the one an icon past the cap overlaps.
local function soonest(last)
    local best = 1
    for r = 2, #last do
        if last[r] < last[best] then best = r end
    end
    return best
end

--- The rows the icons at `xs` (their middles, left to right) stack onto: each on the first row whose
--- last icon is `pitch` or more to its left; past `cap` rows, on the row that frees first, overlapping.
--- @return table rows  { [n] = row (1 = the strip's base row) }
--- @return number count  the rows used (0 for no icons)
--- @return table over  { [n] = true } for each icon placed past the cap
function Data.Stack(xs, pitch, cap)
    local rows, last, over = {}, {}, {}
    for n, x in ipairs(xs) do
        local r = 1
        while last[r] and x - last[r] < pitch do r = r + 1 end
        if r > cap then r, over[n] = soonest(last), true end
        rows[n], last[r] = r, x
    end
    return rows, #last, over
end

--- A strip's height for `rows` rows of icons: one row at the least (an empty strip holds its note).
function Data.StripHeight(rows)
    return math.max(1, rows or 0) * Data.CAST_STEP
end

--- Where each part of the scrolling content starts, in px down from its top, for strips of `rowsA`
--- and `rowsB` rows: the Casts heading at 0, this fight's strip CASTS_PAD under it, the compared
--- fight's, their axis CASTS_PAD under it, the By ability heading under that and the first pair of
--- lanes under the heading.
--- @return table  { stripA, heightA, stripB, heightB, castsAxis, lanesHead, lanes }
function Data.Sections(rowsA, rowsB)
    local s = { stripA = Style.SECTION_H + Data.CASTS_PAD, heightA = Data.StripHeight(rowsA),
                heightB = Data.StripHeight(rowsB) }
    s.stripB = s.stripA + s.heightA + Data.STRIP_GAP
    s.castsAxis = s.stripB + s.heightB + Data.CASTS_PAD
    s.lanesHead = s.castsAxis + Data.CASTS_AXIS_H + Style.SECTION_GAP
    s.lanes = s.lanesHead + Style.SECTION_H
    return s
end

--- A strip's vertical middle, px down from the content's top (its label's line): `side` "a" this
--- fight's, "b" the compared fight's.
function Data.StripMid(s, side)
    if side == "a" then return s.stripA + s.heightA / 2 end
    return s.stripB + s.heightB / 2
end

-- ── the words ───────────────────────────────────────────────────────────────────────────────────

local function clock(t)
    return NS.ResultsUsage.Clock(tonumber(t) or 0)
end

--- A row's cooldown: m:ss when 29 s or more, else nothing.
function Data.CooldownText(row)
    if not (row and NS.Casts.IsLong(row.cd)) then return "" end
    return NS.Format.Length(row.cd / 1000)
end

--- The line under a row's name in its name cell: "1:30 cooldown" when 29 s or more, else nothing.
function Data.CooldownLine(row)
    local cd = Data.CooldownText(row)
    return cd ~= "" and L["%s cooldown"]:format(cd) or ""
end

--- A row's name: the spell's, "(pet)" after a pet's.
function Data.Name(row)
    local name = NS.HudBreakdown.SpellName(row.spellID)
    return row.pet and L["%s (pet)"]:format(name) or name
end

--- A fight's date, short ("10 Nov 21:14").
function Data.ShortLabel(record)
    return NS.ResultsTable.Date(type(record) == "table" and record.t, "%d %b %H:%M")
end

local KINDS = { picked = "Picked", runnerUp = "Runner-up", best = "Best" }

--- What the compared fight is: "Picked", "Runner-up" or "Best".
function Data.KindLabel(kind)
    return L[KINDS[kind] or "Best"]
end

--- The compared fight's label: what it is and its date ("Best · 08 Nov 20:40"), or nil with none.
function Data.OtherLabel(other, kind)
    if not other then return nil end
    return Data.KindLabel(kind) .. SEP .. Data.ShortLabel(other)
end

--- This fight's label ("This fight · 10 Nov 21:14").
function Data.ThisLabel(record)
    return L["This fight"] .. SEP .. Data.ShortLabel(record)
end

--- The legend bar's texts: this fight's, the compared fight's, and the note under the bar (nil with
--- nothing to say): no compared fight, or one with no casts.
--- @return string this, string other, string|nil note
function Data.Legend(record, other, kind)
    local this = Data.ThisLabel(record)
    local label = Data.OtherLabel(other, kind)
    if not label then
        return this, L["No fight to compare with"], L["No fight to compare with: the blue lanes stay empty."]
    end
    if not Data.Has(other) then
        return this, label, L["%s has no casts recorded: the blue lanes stay empty."]:format(Data.KindLabel(kind))
    end
    return this, label, nil
end

--- What follows the client's spell tooltip on a cast icon: its time on the fight's clock ("(pet)"
--- after a pet's), which fight it is, and, for an icon past the row cap, that it overlaps others.
--- Nil for anything but a cast.
--- @param cast table  { t, spellID, pet }
--- @param label string|nil  the fight's label (the legend's)
--- @param over boolean|nil  placed past MAX_STACK rows
--- @return table|nil
function Data.IconLines(cast, label, over)
    if type(cast) ~= "table" or type(cast.spellID) ~= "number" then return nil end
    local at = L["Cast at %s"]:format(clock(cast.t))
    local lines = { cast.pet and L["%s (pet)"]:format(at) or at }
    if label then lines[#lines + 1] = { label, Style.Rgb("ct.dim") } end
    if over then
        lines[#lines + 1] = { L["Too many casts here for %d rows: this icon overlaps others."]:format(Data.MAX_STACK),
                              Style.Rgb("gtip.title") }
    end
    return lines
end

--- A tick's tooltip: the spell, its time, then which fight it is. Nil for anything but a cast.
function Data.MarkLines(cast, label)
    if type(cast) ~= "table" or type(cast.spellID) ~= "number" then return nil end
    local name = NS.HudBreakdown.SpellName(cast.spellID)
    local lines = { cast.pet and L["%s (pet)"]:format(name) or name, L["Cast at %s"]:format(clock(cast.t)) }
    if label then lines[#lines + 1] = { label, Style.Rgb("ct.dim") } end
    return lines
end

local function castsLine(label, n)
    if n == 1 then return L["%s: 1 cast"]:format(label) end
    return L["%s: %d casts"]:format(label, n)
end

--- What follows the client's spell tooltip on a row's name: the ability's cooldown when 29 s or more,
--- then each fight's cast count (the compared fight's only when there is one).
--- @param row table  one of Data.Rows' rows
--- @param otherLabel string|nil
--- @return table
function Data.RowLines(row, otherLabel)
    local lines = {}
    local cd = Data.CooldownText(row)
    if cd ~= "" then lines[1] = { L["Cooldown %s"]:format(cd), Style.Rgb("gtip.title") } end
    lines[#lines + 1] = castsLine(L["This fight"], row.countA or 0)
    if otherLabel then lines[#lines + 1] = castsLine(otherLabel, row.countB or 0) end
    return lines
end

--- The `?` control's tooltip: its title, then the timeline's mouse controls (bullets, from two lines on).
function Data.HelpLines()
    return { L["Mouse controls"], L["Mouse wheel: scroll up and down"],
             L["Shift+mouse wheel: scroll left and right (zoomed in)"], L["Ctrl+mouse wheel: zoom in and out"] }
end
