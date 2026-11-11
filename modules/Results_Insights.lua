local _, NS = ...
-- modules/Results_Insights.lua — the Results window's Insights tab (Race mode plan Task D2, spec §7;
-- closes CT issue #2): a filter bar, the stat cards and the chart sections over every saved fight the
-- filters pass, all fed by one stats pass. Ported from DPS Race @f8078c7 (modules/Results_Insights.lua),
-- LootHistory's Insights tab in Combat Trail's terms, and rebased on fight records with races as a
-- filter.
--
-- THREE HALVES. modules/Results_InsightsData.lua is the pure half (the filters, the faceted options,
-- the stats pass); LibKa0s-Charts-1.0 draws the widgets through NS.ChartsHost() (core/ChartsSetup.lua);
-- this file builds the tab, turns the stats into the renderers' rows and lays the sections out.
--
-- THE SECTIONS. The general ones run on every fight: DPS Progression, the board tabs (each board the
-- fights compare on; Spec Comparison and Consistency under a picked tab), By Character, By Character
-- x Content and Recent New Bests. Under the Races filter (Retail) the race-only ones join them: the
-- tabs become DPS Race's Target x Length boards, the split is by dummy kind, and Races By Character x
-- Length, Late Casts, Races Per Day and Damage Tail After The Buzzer show. The Clean races card counts
-- races only and shows under Races and All, never under Fights or on WoW Forever (ruling X12).
--
-- THE VIEW CONTRACT is the fight list's, so the shell (modules/Results.lua) treats both tabs alike:
-- frame, Layout, Resize, Refresh, Count, SetFilter, SampleView. The shell refreshes the shown tab on
-- FIGHT_SAVED, FIGHTS_CHANGED, a SETTINGS_CHANGED on the late-cast ignore list, the Training dummies
-- list or the profile, and a source swap (test mode, the sim): Refresh re-reads
-- NS.ResultsSource.All(), so the samples fill the tab.
--
-- THE FILTERS open wide (results.insights, defaults/Profile.lua). Each dropdown lists what the OTHER
-- filters leave, with counts (InsightsData.Options), and a selection that no fight matches falls back
-- to its stock value (InsightsData.Normalize), the dropdown just changed never. Save / Reset / Clear
-- keep the view at `results.insights` (named non-setting state, docs/schema.md). Closed, a dropdown
-- names the choices it holds (InsightsData.ClosedLabel); open, each row keeps its count.
--
-- POOLED. Every widget a section draws comes from the chart context's pools: a layout pass releases
-- them all, then each section acquires what it shows, so a second pass builds no frame. Resize (the
-- grip held) re-plans the bar and the scroll frame only; the release's Layout redraws.

local Insights = {}
NS.ResultsInsights = Insights

local L = NS.L
local Tbl = NS.ResultsTable
local C = Tbl.COLORS
local Format = NS.Format
local RETAIL = { "retail" }

local function Data() return NS.InsightsData end
local function Races() return NS.ResultsRaces end

local FILTER_H = 32         -- one row of the filter bar
-- The bar's first-row dropdowns, left to right, their least widths and their clients.
local DROPDOWNS = {
    { key = "character", width = 110 }, { key = "spec", width = 96 }, { key = "content", width = 96 },
    { key = "days", width = 100 }, { key = "kind", width = 110, clients = RETAIL },
}
-- Under Races (Retail): the race length and the dummy kind.
local RACE_DROPDOWNS = { { key = "length", width = 88 }, { key = "dummyKind", width = 100 } }
-- On Retail, unless the view lists fights only: the race checks.
local CHECKS = {
    { key = "cleanOnly", label = "Clean only", width = 84 },
    { key = "includeIncomplete", label = "Include incomplete", width = 128 },
}
local VIEW_BUTTONS = {
    { key = "save", label = "Save", act = "SaveView",
      tip = "Save these filters as this profile's default view of Insights." },
    { key = "reset", label = "Reset", act = "ResetView",
      tip = "Delete the saved view and go back to the stock one: every character, spec, content and date, fights and races." },
    { key = "clear", label = "Clear", act = "ClearView",
      tip = "Go back to the saved view (the stock one when none is saved). The saved view is kept." },
}
local VIEW_BUTTON_W = 52
local GAP = 6
local MARGIN = GAP + 2      -- the bar's left margin, and its right one once the dropdowns stretch

local PAD = 8               -- the content's inner margin
local CARD_COLS, CARD_GAP = 4, 8
local WHEEL_STEP = 40       -- px one notch of the mouse wheel moves
local PROGRESS_DAYS_FROM = 60   -- the progression buckets by day above this many fights
local LIST_VALUE_W = { late = 48, bests = 120 }
local BOARD_TAB_W, BOARD_TAB_H = 140, 22
local BOARD_TAB_CHARS = 22

-- ── the filter bar, planned (pure) ──────────────────────────────────────────────────────────────

--- The first-row dropdowns this client has, in order: { key, width }.
function Insights.Dropdowns()
    local out = {}
    for _, spec in ipairs(DROPDOWNS) do
        if NS.Compat.ForClient(spec.clients) then out[#out + 1] = spec end
    end
    return out
end

-- The second group under `filters`: the race dropdowns under Races, then the race checks.
local function secondGroup(filters)
    local items = {}
    if Data().UnderRaces(filters) then
        for _, s in ipairs(RACE_DROPDOWNS) do items[#items + 1] = { key = s.key, kind = "dropdown", w = s.width } end
    end
    if Data().RaceChecks(filters) then
        for _, s in ipairs(CHECKS) do items[#items + 1] = { key = s.key, kind = "check", w = s.width } end
    end
    return items
end

-- Place the bar's controls by the dropdowns' `widths`. One row: the dropdowns, the second group,
-- then Save / Reset / Clear. Two rows: the dropdowns on the first; the second group and the buttons
-- on the second, the buttons right-aligned under the last dropdown (or after the group, when wider).
local function placeBar(oneRow, widths, items)
    local plan = { dropdowns = {}, row2 = {}, buttons = {}, widths = widths, oneRow = oneRow,
                   y = oneRow and -6 or -(FILTER_H - 2) }
    local x = MARGIN
    for _, spec in ipairs(Insights.Dropdowns()) do
        plan.dropdowns[spec.key] = x
        x = x + widths[spec.key] + GAP
    end
    local lastRight = x - GAP
    if not oneRow then x = MARGIN end
    for _, it in ipairs(items) do
        plan.row2[#plan.row2 + 1] = { key = it.key, kind = it.kind, x = x, w = it.w }
        x = x + it.w + GAP
    end
    local buttonsEnd = x + #VIEW_BUTTONS * (VIEW_BUTTON_W + GAP) - GAP
    local right = oneRow and buttonsEnd or math.max(lastRight, buttonsEnd)
    plan.right = math.max(right, lastRight)
    for i = #VIEW_BUTTONS, 1, -1 do
        plan.buttons[VIEW_BUTTONS[i].key] = right
        right = right - VIEW_BUTTON_W - GAP
    end
    return plan
end

-- The least widths grown by `extra` px between them, in proportion; the last takes the rounding.
local function stretched(extra)
    local dropdowns, total = Insights.Dropdowns(), 0
    for _, spec in ipairs(dropdowns) do total = total + spec.width end
    local widths, given = {}, 0
    for i, spec in ipairs(dropdowns) do
        local add = i == #dropdowns and extra - given or math.floor(extra * spec.width / total)
        widths[spec.key] = spec.width + add
        given = given + add
    end
    return widths
end

--- The bar's plan across `width` (the window body's) under `filters`: one row when everything fits
--- on it, else two. The dropdowns take their least widths, then share what is left, so the bar ends
--- MARGIN short of its right edge. Pure: no frame is read.
--- @return table plan  { oneRow, dropdowns = { [key] = x }, widths, row2 = { { key, kind, x, w } },
---   buttons (right x), y, right }
function Insights.BarPlan(width, filters)
    local items, widths = secondGroup(filters), {}
    for _, spec in ipairs(Insights.Dropdowns()) do widths[spec.key] = spec.width end
    local plan = placeBar(true, widths, items)
    local oneRow = type(width) == "number" and width - MARGIN >= plan.right
    if not oneRow then plan = placeBar(false, widths, items) end
    local extra = type(width) == "number" and math.floor(width - MARGIN - plan.right) or 0
    if extra <= 0 then return plan end
    return placeBar(oneRow, stretched(extra), items)
end

-- ── words ───────────────────────────────────────────────────────────────────────────────────────

local SEP = " \194\183 "
local DASH = "\226\128\148"

local function who(record)
    return type(record.who) == "table" and record.who or {}
end

local function specName(specID, fallback)
    return (Tbl.SpecInfo(specID, fallback)) or L["Unknown spec"]
end

-- "Beast Mastery · Cleave · 3:00", "Fire · Raider's Training Dummy": a board as the tooltips name it.
local function recordBoard(record)
    local w = who(record)
    return specName(w.specID, w.specName) .. SEP .. Data().ScopeLabel(record)
end

local function pct(x)
    return Format.Pct((x or 0) * 100)
end

-- Seconds as practice time: "1h 20m", or "12m 30s" under an hour.
local function duration(secs)
    secs = math.floor((secs or 0) + 0.5)
    local h, m = math.floor(secs / 3600), math.floor(secs % 3600 / 60)
    if h > 0 then return L["%dh %02dm"]:format(h, m) end
    return L["%dm %02ds"]:format(m, secs % 60)
end

local function dps(v)
    return Format.Number(v)
end

local function fightsWord(n)
    return n == 1 and L["1 fight"] or L["%d fights"]:format(n)
end

local function racesWord(n)
    return n == 1 and L["1 race"] or L["%d races"]:format(n)
end

-- ONE DATE FORMAT: the day as the fight list writes it ("26 Oct"), its year added only when it is not
-- this year's, and the time after it where the moment matters (a fight's hover). A strip's axis label
-- is the day alone; its hover names the year.
local DAY_FMT, TIME_FMT = "%d %b", " %H:%M"

local function dayText(t)
    local text = Tbl.Date(t, DAY_FMT)
    if Tbl.Date(t, "%Y") ~= Tbl.Date(time(), "%Y") then text = text .. Tbl.Date(t, " %Y") end
    return text
end

local function whenText(t)
    return dayText(t) .. Tbl.Date(t, TIME_FMT)
end

-- ── the cards (LootHistory's: 4 a row, a wide one spans 2, the figure gold unless it means more) ──

-- Three even rows: the counts, then the context, then the two wide ones (Insights.CardGrid). The
-- Clean races card shows only where races are in view on Retail (ruling X12).
local CARDS = {
    { key = "count", caption = "Fights" },
    { key = "time", caption = "Time in combat" },
    { key = "avg", caption = "Avg % of board best" },
    { key = "clean", caption = "Clean races", when = function(f) return Data().RaceChecks(f) end },
    { key = "newBests", caption = "New bests set" },
    { key = "chars", caption = "Characters" },
    { key = "specs", caption = "Specs" },
    { key = "activeDays", caption = "Active days" },
    { key = "best", caption = "Best DPS", wide = true },
    { key = "span", caption = "Date range", wide = true },
}
Insights.CARDS = CARDS

--- The cards shown under `filters`, in order.
function Insights.Cards(filters)
    local out = {}
    for _, def in ipairs(CARDS) do
        if not def.when or def.when(filters) then out[#out + 1] = def end
    end
    return out
end

-- A share's figure color: green at GOOD_SHARE or above, red under POOR_SHARE, else the gold default.
local GOOD_SHARE, POOR_SHARE = 0.9, 0.7

local function shareColor(x)
    if x >= GOOD_SHARE then return C.green end
    if x < POOR_SHARE then return C.red end
    return nil
end

-- The count card's caption: what the view holds.
local function countCaption(f)
    if Data().UnderRaces(f) then return L["Races"] end
    if not Races().On() or f.kind == "fights" then return L["Fights"] end
    return L["Fights and races"]
end

-- Each card's figure, its hover (lines: a title, then strings), its caption when it changes, and its
-- figure's color when it means something (nil: gold). `f` is the view's filters.
local CARD_FILL = {
    count = function(t, f)
        local caption = countCaption(f)
        return tostring(t.count), { caption, L["The fights these filters pass; a race is a fight."] }, caption
    end,
    time = function(t, f)
        if Data().UnderRaces(f) then
            return duration(t.time), { L["Time raced"],
                L["The race lengths added up; an incomplete race counts its time in combat."] }, L["Time raced"]
        end
        return duration(t.time), { L["Time in combat"], L["The fights' lengths added up; a race counts its time raced."] }
    end,
    best = function(t)
        local b = t.best
        if not b then return DASH, { L["Best DPS"], L["No fight with a DPS in these filters."] } end
        local board = recordBoard(b.record)
        return dps(b.dps), { L["Best DPS"], board, whenText(b.record.t) },
            L["Best DPS"] .. SEP .. board, Tbl.ClassColor(who(b.record).class)
    end,
    avg = function(t)
        if t.oneBoard then
            return dps(t.avgDps), { L["Avg DPS"], L["The fights' average, all on one board."] }, L["Avg DPS"]
        end
        if not t.avgPct then return DASH, { L["Avg % of board best"], L["No fight with a DPS in these filters."] } end
        return pct(t.avgPct), { L["Avg % of board best"],
            L["Each fight against the best on its own board (character, spec and what it was against), averaged."] },
            nil, shareColor(t.avgPct)
    end,
    clean = function(t)
        if t.races == 0 then return DASH, { L["Clean races"], L["No race in these filters."] } end
        return pct(t.clean / t.races), { L["Clean races"],
            L["%d of %d races carry no flag."]:format(t.clean, t.races),
            L["Late casts on the ignore list do not flag a race."] }, nil, shareColor(t.clean / t.races)
    end,
    newBests = function(t)
        return tostring(t.newBests), { L["New bests set"],
            L["Fights that beat an earlier best on their board, within these filters. A board's first fight does not count."] },
            nil, t.newBests > 0 and C.green or nil
    end,
    chars = function(t)
        return tostring(t.chars), { L["Characters"], L["The characters with a fight in these filters."] }
    end,
    specs = function(t)
        return tostring(t.specs), { L["Specs"], L["The specs with a fight in these filters."] }
    end,
    activeDays = function(t)
        return tostring(t.activeDays), { L["Active days"], L["%d days with a fight."]:format(t.activeDays) }
    end,
    span = function(t)
        if not t.first then return DASH end
        local text = L["%s to %s"]:format(dayText(t.first), dayText(t.last))
        return text, { L["Date range"], text, fightsWord(t.count) }
    end,
}

-- A row's cards share the whole row when they leave columns empty (fractional spans).
local function stretchRow(cells, row, cols)
    local used, members = 0, {}
    for _, c in ipairs(cells) do
        if c.row == row then used, members[#members + 1] = used + c.span, c end
    end
    if used == 0 or used >= cols then return end
    local col = 0
    for _, c in ipairs(members) do
        c.col, c.span = col, c.span * cols / used
        col = col + c.span
    end
end

--- The cards' grid: each def's { col, row, span } across `cols` columns (a wide def spans 2, and
--- moves to the next row when it does not fit), and the number of rows. Any row left short (the last,
--- or one a wide card left; nine cards without the Clean races card) is shared out among its cards,
--- so no row stands half empty. Pure.
--- @return table cells, number rows
function Insights.CardGrid(defs, cols)
    local cells, col, row = {}, 0, 0
    for i, def in ipairs(defs) do
        local span = def.wide and 2 or 1
        if col + span > cols then col, row = 0, row + 1 end
        cells[i] = { col = col, row = row, span = span }
        col = col + span
    end
    if #cells == 0 then return cells, 0 end
    for r = 0, row do stretchRow(cells, r, cols) end
    return cells, row + 1
end

-- ── the sections, each one turning the stats into its renderer's rows ───────────────────────────

-- One column per fight in date order, its height the fight's % of its board's best (raw DPS on one
-- board), in its class color; above PROGRESS_DAYS_FROM fights, one column per day (the day's average).
local function progressionPerFight(list, raw)
    local out, lastDay = {}, nil
    for i, e in ipairs(list) do
        local r = e.record
        local day = Tbl.Date(r.t, "%Y-%m-%d")
        out[i] = { count = raw and e.dps or e.pct, color = Tbl.ClassColor(who(r).class),
                   label = day ~= lastDay and Tbl.Date(r.t, DAY_FMT) or nil,
                   info = { recordBoard(r), whenText(r.t), L["%s DPS"]:format(dps(e.dps)),
                            L["%s of board best"]:format(pct(e.pct)) } }
        lastDay = day
    end
    return out
end

-- A day is keyed with its year, so the same date a year apart is two columns; the hover names the year.
local function progressionPerDay(list, raw)
    local out, byDay = {}, {}
    for _, e in ipairs(list) do
        local day = Tbl.Date(e.record.t, "%Y-%m-%d")
        local b = byDay[day]
        if not b then
            b = { label = Tbl.Date(e.record.t, DAY_FMT), sum = 0, n = 0, day = dayText(e.record.t) }
            byDay[day] = b
            out[#out + 1] = b
        end
        b.sum, b.n = b.sum + (raw and e.dps or e.pct), b.n + 1
    end
    for _, b in ipairs(out) do
        b.count = b.sum / b.n
        local avg = raw and L["Avg %s DPS"]:format(dps(b.count)) or L["Avg %s of board best"]:format(pct(b.count))
        b.info = { b.day, fightsWord(b.n), avg }
    end
    return out
end

-- The progression's legend: one chip per spec in its class color, in the order the specs first
-- fought, the hover naming its count. Two specs of one class share a color, so the name tells them apart.
local function progressionLegend(list)
    local rows, bySpec = {}, {}
    for _, e in ipairs(list) do
        local w = who(e.record)
        local key = w.specID or w.specName or "?"
        local row = bySpec[key]
        if not row then
            row = { label = specName(w.specID, w.specName), color = Tbl.ClassColor(w.class), n = 0 }
            bySpec[key], rows[#rows + 1] = row, row
        end
        row.n = row.n + 1
    end
    for _, row in ipairs(rows) do row.value = fightsWord(row.n) end
    return rows
end

local function layoutProgression(self, stats, y, w, pad)
    local list, raw = stats.progression, stats.totals.oneBoard ~= nil
    local buckets = #list > PROGRESS_DAYS_FROM and progressionPerDay(list, raw) or progressionPerFight(list, raw)
    local H = self.headers
    H.progression:SetText(raw and L["DPS Progression"] or L["DPS Progression (% of board best)"])
    y = self.ctx:renderStrip(self.ctx:Pool("progression"), H.progression, self.strips.progression, buckets,
        y, w, pad, (not raw) and 1 or nil)
    if #buckets == 0 then return y end
    return self.ctx:renderLegend(self.ctx:Pool("progressionLegend"), progressionLegend(list),
        y + NS.Charts.K.SECTION_GAP, w, pad, pad)
end

-- A spec row's hover: its character and spec, then the figures.
local function specTip(r, ...)
    local lines = { r.name .. SEP .. specName(r.specID, r.spec) }
    for _, line in ipairs({ ... }) do lines[#lines + 1] = line end
    lines[#lines + 1] = fightsWord(r.n)
    return lines
end

-- On the board tab shown: the specs side by side, by best DPS.
local function layoutSpecs(self, board, y, w, pad)
    local rows = {}
    for _, r in ipairs(board.specs) do
        rows[#rows + 1] = { label = specName(r.specID, r.spec), color = Tbl.ClassColor(r.class), frac = r.best,
                            value = dps(r.best),
                            tip = specTip(r, L["Best %s DPS"]:format(dps(r.best)), L["Avg %s DPS"]:format(dps(r.avg))) }
    end
    return self.ctx:renderBarSection(self.ctx:Pool("specs"), self.headers.specs, rows, y, w, pad)
end

-- On the board tab shown: per spec with three fights or more, a range from its worst fight to its
-- best with a mark at its average, the most consistent first. The value is the average fight's share
-- of the spec's best.
local function layoutConsistency(self, board, y, w, pad)
    local rows = {}
    for _, r in ipairs(board.consistency) do
        rows[#rows + 1] = { label = specName(r.specID, r.spec), color = Tbl.ClassColor(r.class), lo = r.worst,
                            hi = r.best, mark = r.avg, value = pct(r.avgPct),
                            tip = specTip(r, L["Best %s DPS"]:format(dps(r.best)), L["Avg %s DPS"]:format(dps(r.avg)),
                                L["Worst %s DPS"]:format(dps(r.worst)), L["Spread (CV) %s"]:format(r.cv and pct(r.cv) or DASH)) }
    end
    return self.ctx:renderRangeSection(self.ctx:Pool("consistency"), self.headers.consistency, rows, y, w, pad,
        self.ctx:Pool("consistencyScale"), dps)
end

-- A board tab: LootHistory's tab look in the small font, the skin's `tab.onText` and `tab.onLine`
-- underline when picked, `tab.text` when not. Pooled through the chart context; the click and the
-- hover are the bind's.
local function makeBoardTab(ctx, parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(BOARD_TAB_W, BOARD_TAB_H)
    b.label = Tbl.Text(b, Tbl.FONT.TEXT, nil, "CENTER")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
    b.underline = b:CreateTexture(nil, "OVERLAY")
    NS.Style.Fill(b.underline, "tab.onLine")
    b.underline:SetHeight(2)
    b.underline:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 8, 0)
    b.underline:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 0)
    b:SetScript("OnClick", function(self2) if self2._onClick then self2._onClick() end end)
    b:SetScript("OnEnter", function(self2) ctx:showTip(self2, self2._tip) end)
    b:SetScript("OnLeave", function() ctx.hideTip() end)
    return b
end

local function findBoard(tabs, key)
    for _, t in ipairs(tabs) do
        if t.key == key then return t end
    end
    return nil
end

-- The board tabs from the cursor, wrapping at the content's edge, and a rule under them.
local function placeBoardTabs(self, tabs, y, w, pad)
    local pool, x = self.ctx:Pool("boardTabs"), pad
    local list = { { key = Data().OVERALL, overall = true, n = #self.filtered } }
    for _, t in ipairs(tabs) do list[#list + 1] = t end
    for _, t in ipairs(list) do
        if x > pad and x + BOARD_TAB_W > w - pad then x, y = pad, y - BOARD_TAB_H end
        local b = self.ctx:acquire(pool, makeBoardTab)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, y)
        local on = t.key == self.boardKey
        local name = t.overall and L["Overall"] or t.label
        b.label:SetText((NS.Charts.truncate(name, BOARD_TAB_CHARS)))
        NS.Style.Paint(b.label, on and "tab.onText" or "tab.text")
        b.underline:SetShown(on)
        b._tip, b._onClick = { name, fightsWord(t.n) }, function() self:SelectBoard(t.key) end
        x = x + BOARD_TAB_W
    end
    y = y - BOARD_TAB_H
    self.boardRule:ClearAllPoints()
    self.boardRule:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y)
    self.boardRule:SetWidth(math.max(1, w - pad * 2))
    self.boardRule:Show()
    return y - NS.Charts.K.BAR_GAP * 2
end

-- The board tabs, then Spec Comparison and Consistency on the tab picked: the tab last picked this
-- session while it stays present, else Overall. Nothing with no fight holding a DPS figure.
local function layoutBoards(self, stats, y, w, pad)
    local tabs = stats.boardTabs
    if #tabs == 0 then return y end
    local want = Insights.lastBoard or Data().OVERALL
    local board = findBoard(tabs, want)
    self.boardKey = board and want or Data().OVERALL
    self.headers.boards:SetText(Data().UnderRaces(self.filters) and L["By Target \195\151 Length"] or L["By Board"])
    y = self.ctx:placeHeader(self.headers.boards, y, pad)
    y = placeBoardTabs(self, tabs, y, w, pad)
    -- Everything under the tabs reads the tab picked; Overall reads every board.
    self.scoped = Data().Compute(Data().Scope(self.filtered, self.boardKey))
    if not board then return y end      -- Overall: DPS compares only within a board
    y = layoutSpecs(self, board, y, w, pad)
    return layoutConsistency(self, board, y, w, pad)
end

-- The fights (the races under Races) per character, in its class color.
local function layoutCharacters(self, stats, y, w, pad)
    local rows = {}
    local word = Data().UnderRaces(self.filters) and racesWord or fightsWord
    for _, e in ipairs(stats.byChar) do
        rows[#rows + 1] = { label = e.name, color = Tbl.ClassColor(e.class), frac = e.n, value = tostring(e.n),
                            tip = { e.name .. "-" .. tostring(e.realm or "?"), word(e.n) } }
    end
    self.headers.chars:SetText(Data().UnderRaces(self.filters) and L["Races By Character"] or L["By Character"])
    return self.ctx:renderBarSection(self.ctx:Pool("chars"), self.headers.chars, rows, y, w, pad)
end

-- The splits of each character's fights: by content kind in the content hues, by dummy kind in DPS
-- Race's kind hues (under Races), by race length in the length hues. `of` names the character
-- entry's counts; `color` and `name` read one key.
local SPLITS = {
    charContent = { of = "byContent",
                    color = function(k) return Tbl.CONTENT_COLORS[k] or Tbl.CONTENT_NEUTRAL end,
                    name = function(k) return Tbl.ContentLabel(k) end },
    charTarget = { of = "byCategory",
                   color = function(k) return Races().KIND_COLORS[k] or Races().KIND_COLORS.other end,
                   name = function(k) return NS.Dummies.Label(k) end },
    charLength = { of = "byLength", color = function(k) return Races().LengthColor(k) end,
                   name = function(k) return Format.Length(k) end },
}

-- A split section: one stacked bar per character over `keys` in order, then the keys' legend.
local function layoutSplit(self, key, header, split, y, w, pad)
    local spec, top, rows, legend = SPLITS[key], 1, {}, {}
    for _, e in ipairs(split.rows) do top = math.max(top, e.n) end
    for _, e in ipairs(split.rows) do
        local segs = {}
        for _, k in ipairs(split.keys) do
            local n = e[spec.of][k]
            if n then
                segs[#segs + 1] = { frac = n / top, color = spec.color(k), tip = L["%s: %d"]:format(spec.name(k), n) }
            end
        end
        if #segs > 0 then
            rows[#rows + 1] = { label = e.name, labelColor = Tbl.ClassColor(e.class), value = tostring(e.n), segments = segs }
        end
    end
    y = self.ctx:renderStackedBarSection(self.ctx:Pool(key), header, rows, y, w, pad)
    if #rows == 0 then return y end
    for _, k in ipairs(split.keys) do legend[#legend + 1] = { label = spec.name(k), color = spec.color(k) } end
    return self.ctx:renderLegend(self.ctx:Pool(key .. "Legend"), legend, y + NS.Charts.K.SECTION_GAP, w, pad)
end

-- Each character's fights split by content, or under Races its races by dummy kind.
local function layoutCharSplit(self, stats, y, w, pad)
    local H = self.headers.charSplit
    if Data().UnderRaces(self.filters) then
        H:SetText(L["Races By Character \195\151 Target"])
        return layoutSplit(self, "charTarget", H, stats.byCharTarget, y, w, pad)
    end
    H:SetText(L["By Character \195\151 Content"])
    return layoutSplit(self, "charContent", H, stats.byCharContent, y, w, pad)
end

-- Under Races: each character's races split by length.
local function layoutCharLength(self, stats, y, w, pad)
    return layoutSplit(self, "charLength", self.headers.charLength, stats.byCharLength, y, w, pad)
end

-- A list panel across the content, or nothing (the panel hidden) with no rows.
local function listSection(self, key, rows, y, w, pad)
    local panel = self.panels[key]
    if #rows == 0 then panel:Hide(); return y end
    local h = self.ctx:renderListPanel(self.ctx:Pool(key), panel, rows, y, w - pad * 2, pad, LIST_VALUE_W[key])
    return y - h - NS.Charts.K.SECTION_GAP
end

-- A Late Casts row's right-click: the ignore list's own menu (LateIgnore.Menu) over a race part
-- holding that one cast, so it offers Ignore or Stop ignoring as the Race window's chip does. Never
-- on the samples, never for a cast with no spell ID (it cannot be ignored).
local function lateMenu(id)
    return function(row, button)
        if button ~= "RightButton" or NS.ResultsSource.IsMock() then return end
        NS.LateIgnore.Menu({ flags = { lateCasts = { { spellID = id } } } }, row)
    end
end

local function lateRow(e, ignored)
    local name = e.unknown and L["Unknown spell"] or NS.HudBreakdown.SpellName(e.id)
    local n = e.count == 1 and L["1 late cast"] or L["%d late casts"]:format(e.count)
    local row = { name = name, right = tostring(e.count), onClick = (not e.unknown) and lateMenu(e.id) or nil }
    if ignored then
        row.name, row.nameColor = L["%s (ignored)"]:format(name), C.dim
        row.tip = { name, n, L["On the ignore list: no flag. Right-click to stop ignoring it."] }
    elseif e.unknown then
        row.tip = { name, n, L["No spell ID was recorded, so it cannot be ignored."] }
    else
        row.tip = { name, n, L["Each one flags its race. Right-click to ignore it."] }
    end
    return row
end

-- Under Races: the late casts by spell, the counted ones first, the ignored ones dimmed and tagged.
-- The panel shows ten rows (K.LIST_MAX); the ignored ones keep up to half of them however many spells
-- count, so the right-click that stops ignoring one is never cut off.
local function layoutLateCasts(self, stats, y, w, pad)
    local counted, ignored = stats.lateBySpell.counted, stats.lateBySpell.ignored
    local max = NS.Charts.K.LIST_MAX
    local nIgnored = math.min(#ignored, math.max(max - #counted, math.floor(max / 2)))
    local rows = {}
    for n = 1, math.min(#counted, max - nIgnored) do rows[#rows + 1] = lateRow(counted[n], false) end
    for n = 1, nIgnored do rows[#rows + 1] = lateRow(ignored[n], true) end
    return listSection(self, "late", rows, y, w, pad)
end

-- Under Races: the races per day, the days with none included.
local function layoutPerDay(self, stats, y, w, pad)
    local buckets = {}
    for i, d in ipairs(stats.byDay) do
        buckets[i] = { count = d.n, label = Tbl.Date(d.day, DAY_FMT), info = L["%s: %s"]:format(dayText(d.day), racesWord(d.n)) }
    end
    return self.ctx:renderStrip(self.ctx:Pool("perDay"), self.headers.perDay, self.strips.perDay, buckets, y, w, pad)
end

-- Under Races: the damage tail after the buzzer in 5 s buckets, the last open-ended.
local function layoutTail(self, stats, y, w, pad)
    local rows = {}
    for i, b in ipairs(stats.tail) do
        local label = b.hi and L["%d-%d s"]:format(b.lo, b.hi) or L["%d+ s"]:format(b.lo)
        rows[i] = { label = label, color = C.blue, frac = b.n, value = tostring(b.n),
                    tip = { label, racesWord(b.n), L["Damage still landing after the buzzer, and counted."] } }
    end
    return self.ctx:renderBarSection(self.ctx:Pool("tail"), self.headers.tail, rows, y, w, pad)
end

-- Recent New Bests' clicks: the left opens the fight on the Fights tab, the right its row menu.
local function bestClick(self, record)
    return function(row, button)
        local hooks = self.hooks
        if button == "RightButton" then
            if hooks.menu then hooks.menu(record, row) end
        elseif hooks.open then
            hooks.open(record)
        end
    end
end

-- The newest new bests first: date, spec, board, DPS and the gain over the best before.
local function layoutNewBests(self, stats, y, w, pad)
    local rows, list = {}, stats.newBests
    for i = #list, 1, -1 do
        local e = list[i]
        local r = e.record
        local gain = e.gain and L["%+.1f%%"]:format(e.gain) or DASH
        rows[#rows + 1] = {
            name = dayText(r.t) .. SEP .. recordBoard(r),
            nameColor = Tbl.ClassColor(who(r).class),
            right = L["%s  %s"]:format(dps(e.dps), gain),
            tip = { recordBoard(r), whenText(r.t), L["%s DPS, up from %s"]:format(dps(e.dps), dps(e.prevDps)),
                    L["Click to open the fight \194\183 right-click for options"] },
            onClick = bestClick(self, r),
        }
    end
    return listSection(self, "bests", rows, y, w, pad)
end

-- In draw order; `races` marks a race-only section (shown under the Races filter only).
local SECTIONS = {
    { fn = layoutProgression }, { fn = layoutBoards, boards = true }, { fn = layoutCharacters },
    { fn = layoutCharSplit }, { fn = layoutCharLength, races = true }, { fn = layoutLateCasts, races = true },
    { fn = layoutPerDay, races = true }, { fn = layoutTail, races = true }, { fn = layoutNewBests },
}

-- The sections' headings (the list panels carry their own titles); some are re-worded per view.
local HEADERS = {
    { key = "progression", title = "DPS Progression" },
    { key = "boards", title = "By Board" },
    { key = "specs", title = "Spec Comparison" },
    { key = "consistency", title = "Consistency" },
    { key = "chars", title = "By Character" },
    { key = "charSplit", title = "By Character \195\151 Content" },
    { key = "charLength", title = "Races By Character \195\151 Length" },
    { key = "perDay", title = "Races Per Day" },
    { key = "tail", title = "Damage Tail After The Buzzer" },
}
local PANELS = { { key = "late", title = "Late Casts" }, { key = "bests", title = "Recent New Bests" } }

-- ── the view ────────────────────────────────────────────────────────────────────────────────────

local View = {}
View.__index = View

local function checkbox(view, parent, spec)
    local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    b:SetSize(20, 20)
    b.label = Tbl.Text(b, Tbl.FONT.TEXT)
    b.label:SetPoint("LEFT", b, "RIGHT", 1, 0)
    Tbl.SetCheckLabel(b, L[spec.label])
    b:SetScript("OnClick", function() view:SetFilter(spec.key, not view.filters[spec.key]) end)
    -- The skin's check box, after the click script.
    NS.Skin.Checkbox(b)
    b.key = spec.key
    return b
end

local function dropdown(view, bar, spec)
    local dd = NS.MakeDropdown(bar, spec.width)
    if dd then
        dd.onSelect = function(value) view:SetFilter(spec.key, value) end
        view.dropdowns[spec.key] = dd
    end
end

-- The bar: the first-row dropdowns this client has, and on Retail the race dropdowns and checks
-- (laid out or hidden per view by View:layoutBar), then Save / Reset / Clear.
local function buildBar(view)
    local bar = CreateFrame("Frame", nil, view.frame)
    bar:SetPoint("TOPLEFT", view.frame, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", view.frame, "TOPRIGHT", 0, 0)
    bar:SetHeight(FILTER_H)
    local line = bar:CreateTexture(nil, "ARTWORK")
    NS.Skin.Divider(line)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    view.rule = line
    view.dropdowns, view.checks, view.viewButtons = {}, {}, {}
    for _, spec in ipairs(Insights.Dropdowns()) do dropdown(view, bar, spec) end
    if Races().On() then
        for _, spec in ipairs(RACE_DROPDOWNS) do dropdown(view, bar, spec) end
        for _, spec in ipairs(CHECKS) do view.checks[spec.key] = checkbox(view, bar, spec) end
    end
    for _, spec in ipairs(VIEW_BUTTONS) do
        local b = NS.Style.Button(bar, L[spec.label], function() view[spec.act](view) end)
        b:SetWidth(VIEW_BUTTON_W)
        b.tip = { L[spec.label], L[spec.tip] }
        view.viewButtons[spec.key] = b
    end
    view.bar = bar
end

-- The scroll frame under the bar, its content, and the chrome the sections place: the cards, the
-- headings, the strips, the board tabs' rule, the list panels and the empty state.
local function buildBody(view)
    local frame = view.frame
    view.scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    view.content = CreateFrame("Frame", nil, view.scrollFrame)
    view.content:SetSize(1, 1)
    view.scrollFrame:SetScrollChild(view.content)
    view.scrollFrame:EnableMouseWheel(true)
    view.scrollFrame:SetScript("OnMouseWheel", function(_, delta) view:Scroll(delta) end)
    view.cards, view.headers, view.panels, view.chrome = {}, {}, {}, {}
    view.empty = Tbl.Text(frame, Tbl.FONT.EMPTY, nil, "CENTER")
    view.empty:SetText(NS.Charts and L["No fights match these filters."]
        or (NS.LIBKA0S_MISSING .. ", so the charts are unavailable."))
    view.empty:Hide()
    if not NS.Charts then return end   -- the library-absent load: the filters and the count, no charts
    local ctx = NS.Charts:New(view.content, NS.ChartsHost())
    view.ctx = ctx
    for _, def in ipairs(CARDS) do
        view.cards[def.key] = ctx:card(view.content, L[def.caption])
        view.chrome[#view.chrome + 1] = view.cards[def.key].frame
    end
    for _, def in ipairs(HEADERS) do
        view.headers[def.key] = ctx:sectionHeader(view.content, L[def.title])
        view.chrome[#view.chrome + 1] = view.headers[def.key]
    end
    view.strips = { progression = ctx:strip(view.content), perDay = ctx:strip(view.content) }
    for _, def in ipairs(PANELS) do
        view.panels[def.key] = ctx:listPanel(view.content, L[def.title])
        view.chrome[#view.chrome + 1] = view.panels[def.key]
    end
    view.chrome[#view.chrome + 1] = view.strips.progression
    view.chrome[#view.chrome + 1] = view.strips.perDay
    view.boardRule = view.content:CreateTexture(nil, "ARTWORK")
    NS.Skin.Divider(view.boardRule)
    view.boardRule:SetHeight(1)
    view.chrome[#view.chrome + 1] = view.boardRule
end

--- The Insights tab in `parent`.
--- @param parent table
--- @param hooks table  { open(record), menu(record, row), count(text) }
--- @return table view
function Insights.Build(parent, hooks)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    local view = setmetatable({ frame = frame, hooks = hooks or {}, filters = {}, barH = FILTER_H, scroll = 0,
                                filtered = {} }, View)
    buildBar(view)
    buildBody(view)
    view:ApplyView(Insights.SavedView())
    return view
end

-- ── saved views (LootHistory's Save / Reset / Clear) ────────────────────────────────────────────
--   Save   stores the filters as the profile's view (results.insights).
--   Reset  deletes the saved view, so the stock one applies (defaults/Profile.lua).
--   Clear  returns to the saved view, or the stock one when there is none; the saved view is kept.

--- The profile's view (the stock one where the profile is not there yet).
function Insights.SavedView()
    local p = NS.db and NS.db.profile
    local r = p and p.results
    return type(r) == "table" and type(r.insights) == "table" and r.insights or Data().Stock()
end

--- The view now, as a plain copy (results.insights' shape).
function View:CaptureView()
    local out = {}
    for k in pairs(Data().Stock()) do out[k] = self.filters[k] end
    return out
end

--- Apply `v` (results.insights' shape), or the stock view for nil. A stored key the tab does not know
--- is dropped; a missing one takes its stock value. Normalize (on Refresh) falls a selection with no
--- fights back, in the live filters only.
function View:ApplyView(v)
    self.filters = Data().Merged(v)
    if self.built then self:Redraw() end
end

-- While the window shows the sample history (test mode, the sim) Save and Reset refuse with one line,
-- so nothing the samples set reaches the profile (modules/Results_Source.lua).
local function sampleRefusal()
    if not NS.ResultsSource.IsMock() then return false end
    NS.Print(L["Not saved: the Results window is showing sample fights."])
    return true
end

--- Enter (`on`) or leave the sample history's view: entering keeps the player's view to restore, and
--- opens on the stock one (the samples are other characters' fights).
function View:SampleView(on)
    if on then
        if not self.realView then self.realView = self:CaptureView() end
        self:ApplyView(nil)
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
    p.results.insights = v
    return true
end

function View:SaveView()
    if sampleRefusal() then return false end
    if not writeView(self:CaptureView()) then return false end
    NS.Print(L["The Insights view is saved."])
    return true
end

function View:ResetView()
    if sampleRefusal() then return false end
    if not writeView(nil) then return false end
    self:ApplyView(nil)
    NS.Print(L["The Insights view is back to the one the addon ships with."])
    return true
end

function View:ClearView()
    self:ApplyView(Insights.SavedView())
    return true
end

-- ── layout ──────────────────────────────────────────────────────────────────────────────────────

-- Place one second-group control, or hide it.
local function placeItem(self, control, item, y)
    control:ClearAllPoints()
    control:SetPoint("TOPLEFT", self.bar, "TOPLEFT", item.x, y + (item.kind == "dropdown" and 2 or 0))
    if item.kind == "dropdown" then control:SetWidth(item.w) end
    control:Show()
end

-- The second group: each control placed by the plan, every other one hidden.
function View:layoutRow2(plan)
    local placed = {}
    for _, item in ipairs(plan.row2) do
        local control = item.kind == "check" and self.checks[item.key] or self.dropdowns[item.key]
        if control then
            placeItem(self, control, item, plan.y)
            placed[item.key] = true
        end
    end
    for _, spec in ipairs(RACE_DROPDOWNS) do
        local dd = self.dropdowns[spec.key]
        if dd and not placed[spec.key] then dd:Hide() end
    end
    for key, b in pairs(self.checks) do
        if not placed[key] then b:Hide() end
    end
end

-- Lay the bar out by Insights.BarPlan at `width`: re-anchored and the dropdowns re-sized, nothing
-- repainted, so Resize runs it too. Answers its height.
function View:layoutBar(width)
    local plan = Insights.BarPlan(width, self.filters)
    for _, spec in ipairs(Insights.Dropdowns()) do
        local dd = self.dropdowns[spec.key]
        if dd then
            dd:ClearAllPoints()
            dd:SetPoint("TOPLEFT", self.bar, "TOPLEFT", plan.dropdowns[spec.key], -6)
            dd:SetWidth(plan.widths[spec.key])
        end
    end
    self:layoutRow2(plan)
    for _, spec in ipairs(VIEW_BUTTONS) do
        local b = self.viewButtons[spec.key]
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", self.bar, "TOPLEFT", plan.buttons[spec.key], plan.y)
    end
    self.barH = plan.oneRow and FILTER_H or (2 * FILTER_H - 6)
    self.bar:SetHeight(self.barH)
    return self.barH
end

-- The scroll frame under the bar, filling the rest of the tab.
function View:placeScroll(width, height)
    self.viewH = math.max(1, height - self.barH)
    self.scrollFrame:ClearAllPoints()
    self.scrollFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -self.barH)
    self.scrollFrame:SetSize(math.max(1, width), self.viewH)
    self.empty:ClearAllPoints()
    self.empty:SetPoint("TOP", self.frame, "TOP", 0, -(self.barH + 24))
end

-- The cards on Insights.CardGrid's 4 columns from `y`; answers the cursor under them.
function View:layoutCards(y, w)
    local colW = (w - PAD * 2 - CARD_GAP * (CARD_COLS - 1)) / CARD_COLS
    local cardH = NS.Charts.K.CARD_H
    local defs = Insights.Cards(self.filters)
    local cells, nRows = Insights.CardGrid(defs, CARD_COLS)
    for i, def in ipairs(defs) do
        local cell, card = cells[i], self.cards[def.key]
        local cw = math.floor(colW * cell.span + CARD_GAP * (cell.span - 1))
        card.frame:ClearAllPoints()
        card.frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", math.floor(PAD + cell.col * (colW + CARD_GAP)),
            y - cell.row * (cardH + CARD_GAP))
        card.frame:SetWidth(cw)
        card.frame:Show()
        local value, tip, caption, color = CARD_FILL[def.key](self.stats.totals, self.filters)
        card.label:SetText(caption or L[def.caption])
        self.ctx:setCard(card, value, tip, cw - 12, color)
    end
    return y - nRows * (cardH + CARD_GAP) + CARD_GAP - 14
end

--- Bind and place every section off the stats for `w`; answers the cursor under the last. With no
--- fight the empty state shows and everything else hides.
function View:LayoutCharts(y, w, pad)
    if not self.ctx then
        self.empty:Show()
        return y
    end
    self.ctx:ReleaseAll()
    for _, region in ipairs(self.chrome) do region:Hide() end
    local stats = self.stats
    if not stats or stats.totals.count == 0 then
        self.empty:Show()
        return y
    end
    self.empty:Hide()
    self.scoped = nil
    y = self:layoutCards(y, w)
    local races = Data().UnderRaces(self.filters)
    for _, section in ipairs(SECTIONS) do
        if races or not section.races then y = section.fn(self, stats, y, w, pad) end
        if section.boards then stats = self.scoped or stats end
    end
    return y
end

-- Draw the content at the width laid out: the cards and the sections, then the scroll clamped.
function View:draw()
    local w = math.max(1, self.width or 1)
    self.content:SetWidth(w)
    local y = self:LayoutCharts(-PAD, w, PAD)
    self.contentH = -y + PAD
    self.content:SetHeight(math.max(1, self.contentH))
    self:Scroll(0)
end

--- Lay the tab out at `width` x `height`: the bar, the scroll frame, the cards and the sections.
function View:Layout(width, height)
    self.width, self.height = width, height
    self:layoutBar(width)
    self:placeScroll(width, height)
    self:draw()
end

--- While the window is being sized (modules/Sizing.lua): the bar re-planned and the scroll frame
--- sized, nothing rebound or redrawn; the release's Layout redraws.
function View:Resize(width, height)
    self.width, self.height = width, height
    self:layoutBar(width)
    self:placeScroll(width, height)
    self:Scroll(0)
end

--- The bar's height.
function View:BarHeight()
    return self.barH
end

--- One mouse-wheel notch (`delta` > 0 scrolls up), clamped to the content.
function View:Scroll(delta)
    local top = math.max(0, (self.contentH or 0) - (self.viewH or 0))
    self.scroll = math.max(0, math.min(top, (self.scroll or 0) - (delta or 0) * WHEEL_STEP))
    self.scrollFrame:SetVerticalScroll(self.scroll)
end

-- ── the data ────────────────────────────────────────────────────────────────────────────────────

-- Put the filters on the controls: each dropdown closed on its ClosedLabel (the choices, not the
-- fights); a dropdown whose facet does not apply under the view keeps its last list (it is hidden).
function View:paintFilters(options)
    for key, dd in pairs(self.dropdowns) do
        local list, value = options[key], self.filters[key]
        if list then
            dd:SetOptions(list)
            dd:SelectValue(value)
            local closed = Data().ClosedLabel(list, value)
            if closed then dd:SetValue(value, closed) end
        end
    end
    for key, b in pairs(self.checks) do b:SetChecked(self.filters[key] == true) end
end

--- The count text for the footer: the fights the filters pass ("12 fights"), the races under Races.
function View:CountText()
    local n = #self.filtered
    if Data().UnderRaces(self.filters) then return racesWord(n) end
    return fightsWord(n)
end

--- Re-read the source: the options (a selection with no fights falls back, `self.keep` never), the
--- filtered fights, the stats and the footer's count. The shell lays the tab out after it.
function View:Refresh()
    local all, now = NS.ResultsSource.All(), time()
    local f, options = Data().Normalize(all, self.filters, now, self.keep)
    self.filters, self.keep = f, nil
    self:paintFilters(options)
    self.filtered = Data().Filter(all, f, now)
    self.stats = Data().Compute(self.filtered)
    self.built = true
    if self.hooks.count then self.hooks.count(self:CountText()) end
end

--- Refresh, then lay out again at the size laid out (a filter or a view changed while the tab
--- shows: the bar's second group follows the kind filter).
function View:Redraw()
    self:Refresh()
    if self.width then self:Layout(self.width, self.height) end
end

--- Set one filter and redraw: the dropdown changed keeps its value through the fallback.
function View:SetFilter(key, value)
    if Data().Stock()[key] == nil then return false end
    self.filters[key] = value
    self.keep = key
    self:Redraw()
    return true
end

--- Show the board tab `key` ("race:cleave|180", "fight:<board key>"): kept while the filters leave
--- it present, and for the session (Insights.lastBoard, here and in the next tab built); never saved.
function View:SelectBoard(key)
    self.boardKey = key
    Insights.lastBoard = key
    if self.width then self:draw() end
end

--- How many fights pass the filters now.
function View:Count()
    return #self.filtered
end
