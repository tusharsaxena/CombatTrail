local _, NS = ...
-- modules/RaceWindow_Board.lua — the race board's figures the Race window's bodies draw beside the
-- best (race window redesign plan Tasks W6 and W7): on the running body, Best by now (the best's
-- straight line at the race clock) and the Checkpoints (the best's damage at each quarter of the
-- length; the Stop! and waiting bodies show them too, all four taken by the buzzer); on the result card, Against your best (this race beside the best before it: score, race
-- DPS, item level and date, with the difference; the time raced is the Time chip's, owner 2026-11-13)
-- and Top races; on the idle body, Top races too. Top races is the top three races on the race board
-- for this character and spec, as the board ranks them (NS.Bests.Ranked: every race that counts,
-- best first), and on the result card this race's own row under them, with its rank, when it is not
-- in the top three. The running clock's color over the race (ClockColor) is worked out here too.
--
-- STORED NUMBERS AND PLAIN MATH ONLY. Every figure worked on is a stored record's (plain since
-- NS.Secrets took it in), the race best's straight line (NS.HudBest.RaceCurve) or the race clock
-- (GetTime()). The one live figure, the player's damage (Current) beside Best by now and in each
-- Checkpoint, is handed in by modules/RaceWindow.lua (the DPS HUD's last read, opaque: a secret in
-- combat) with a plain flag beside it saying whether there is one. It goes to two C-side sinks only:
-- a label through NS.Format.Number, and the mini pace bars' StatusBar:SetValue (NS.HudChart's pace bar,
-- thinner, owner 2026-11-13), whose range is plain (NS.HudBest.Bounds around the best's figure, the
-- DPS HUD's Pace range). It is never compared, computed on or tested: the client clamps it in the
-- bar, so the green or red is where the fill ends, and nothing in Lua says ahead or behind; a
-- checkpoint passed is the clock's word, never the damage's. A bar handed it has secret geometry, so
-- nothing is anchored to one: each bar stands on a plain frame (the body's content, a checkpoint's
-- cell). The pure helpers (Checkpoints, ByNow, Compare, Rows, Spread, ClockColor) answer plain values
-- the suites read; the widgets draw them.
--
-- THE LOOK IS THE BODIES' (modules/RaceWindow_States.lua) AND THE DPS HUD'S: the section headings in
-- FONT.SECTION on Style.SECTION_H, the HUD's "Damage profile" and "Spell breakdown" (a note at the
-- heading's bottom edge, right), the cards the HUD's boxes, the tables plain rows in the text face, a
-- diff in the meaning green or red. On the running body every best figure is the skin's blue
-- (ct.info), every Current figure the text white (ct.text), and their labels and a checkpoint's time
-- the skin's muted gold (text.headingAlt). Both tables stand on ONE column grid (a lead column LEAD_W wide,
-- three equal columns after it), so Against your best's and Top races' columns line up. Every
-- position is config (the row height, the grid, the cell sizes) against the width the shell hands the
-- body (it follows the grip; every Place takes it): nothing reads the size of a region a value was
-- written to.
--
-- RETAIL ONLY (clients-§4): nothing here loads on WoW Forever.

if not NS.Compat.ForClient({ "retail" }) then return end

local Board = {}
NS.RaceWindowBoard = Board

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT
local C = NS.HudStates.COLORS
local Chart = NS.HudChart
local DASH = "\226\128\148"
-- The running body's figures (owner, 2026-11-13): the best's in the skin's blue, the player's in the
-- text white, their labels and a checkpoint's time in the skin's muted gold.
local BEST_C, CURRENT_C, LABEL_C = C.info, C.text, Style.Tok("text.headingAlt")
Board.BEST_C, Board.CURRENT_C, Board.LABEL_C = BEST_C, CURRENT_C, LABEL_C
local DOT = " \194\183 "

-- ── the layout's constants ──────────────────────────────────────────────────────────────────────
Board.CAPTION_H = Style.SECTION_H   -- a section's heading line (FONT.SECTION), the DPS HUD's
Board.ROW_H = 14              -- a table row at its least, the header row included
Board.ROW_MAX = 18            -- a table row at its most, when a taller window spreads the stack
Board.GAP_MAX = 24            -- the clear space over a section heading at its most, likewise
Board.NOW_H = 22              -- the Best by now card
Board.NOW_PACE_H = 4          -- Best by now's mini pace bar (the DPS HUD's is 8), on a line 4px taller
Board.NOW_PACE_LINE = Board.NOW_PACE_H + 4
Board.CP_H, Board.CP_GAP = 54, 4   -- a Checkpoint: the time, the best's figure, Current, the mini bar
-- The three text rows' tops in a cell: the time a step up (FONT.HEADING, 12px), 3px clear under it,
-- then the best's and Current (FONT.TEXT, 10px); the mini bar's line 2px under that (its bar 2px
-- further: 4px clear).
Board.CP_ROWS = { 4, 19, 31 }
Board.CP_PACE_Y = 43           -- the mini pace bar's line top in a cell
Board.CP_PACE_H = 3            -- its bar, on a line 4px taller
Board.CP_PACE_SHARE = 0.9      -- its width, of the cell's, centered
Board.PASSED_A = 0.55          -- a passed checkpoint's best figure, dimmed (its blue kept)
Board.TOP_N = 3               -- the races Top races lists above this race's own row
Board.LEAD_W = 64             -- the grid's lead column: Against your best's labels, Top races' ranks
local TEXT_PX = 10            -- FONT.TEXT's line, centered in a row

-- The running clock's color (ClockColor): green for the first GREEN_SHARE of the race, red for the
-- last RED_AT seconds, blended green -> yellow -> red between.
Board.GREEN_SHARE = 0.5
Board.RED_AT = 10

-- ── the pure helpers ────────────────────────────────────────────────────────────────────────────

--- The best's damage by `elapsed` on its straight line (score x elapsed / length, held at the score).
--- @param line table  NS.HudBest.RaceCurve's
--- @param elapsed number
--- @return number
function Board.ByNow(line, elapsed)
    return line:damageAt(tonumber(elapsed) or 0)
end

--- The four checkpoints at 25, 50, 75 and 100% of the best's length: { t, damage, passed, next },
--- `passed` once the race clock reached it, `next` the first one it has not.
--- @param line table  NS.HudBest.RaceCurve's
--- @param elapsed number
--- @return table list
function Board.Checkpoints(line, elapsed)
    elapsed = tonumber(elapsed) or 0
    local list, nextSet = {}, false
    for i = 1, 4 do
        local t = line.duration * i / 4
        local passed = elapsed >= t
        local isNext = not passed and not nextSet
        nextSet = nextSet or isNext
        list[i] = { t = t, damage = line:damageAt(t), passed = passed, next = isNext }
    end
    return list
end

-- A difference's color: green above, red below, the dim gray level.
local function signColor(d)
    if d > 0 then return C.green end
    if d < 0 then return C.red end
    return C.dim
end

local function signedNumber(d)
    if d > 0 then return "+" .. NS.Format.Number(d) end
    if d < 0 then return NS.Format.Number(d) end
    return "0"
end

local function signedTenth(d) return L["%+.1f"]:format(d) end

local function number(v) return type(v) == "number" and v or nil end

-- A figure row: the two figures in `fmt`, the difference in `diff` colored by its sign.
local function figureRow(label, a, b, fmt, diff)
    local row = { cells = { label, a and fmt(a) or DASH, b and fmt(b) or DASH, "" }, colors = {} }
    if a and b then
        local d = a - b
        row.cells[4], row.colors[4] = diff(d), signColor(d)
    end
    return row
end

-- The race DPS row: the difference as a share of the best's, as the vs best chip has it.
local function dpsRow(a, b)
    local row = { cells = { L["DPS"], a and NS.Format.Number(a) or DASH, b and NS.Format.Number(b) or DASH, "" },
                  colors = {} }
    if a and b and b > 0 then
        local pct = (a / b - 1) * 100
        row.cells[4], row.colors[4] = NS.Format.SignedPct(pct), signColor(pct)
    end
    return row
end

local function ilvlOf(record)
    local who = type(record.who) == "table" and record.who or {}
    return number(who.ilvl)
end

local function dateOf(record) return NS.ResultsTable.Date(record.t, "%d %b") end

--- Against your best: this race beside `prev` (the best on its board before it, NS.Bests.Before),
--- the rows Score, DPS, Item level and Date, each { cells = { label, this, best, diff },
--- colors = { [4] = the diff's } }. The date has no diff. No time raced row: a complete race's is
--- always its length, and an incomplete one's is on the Time chip and the incomplete flag's.
--- @param record table  this race's record
--- @param prev table  the best before it
--- @return table rows
function Board.Compare(record, prev)
    local Dps = NS.RaceRecord.Dps
    local mine, theirs = record.race, prev.race
    return {
        figureRow(L["Score"], number(mine.score), number(theirs.score), NS.Format.Number, signedNumber),
        dpsRow(number(Dps(record)), number(Dps(prev))),
        figureRow(L["Item level"], ilvlOf(record), ilvlOf(prev), NS.ResultsTable.Ilvl, signedTenth),
        { cells = { L["Date"], dateOf(record), dateOf(prev), "" }, colors = {} },
    }
end

local function boardRow(rank, r, me)
    local score = type(r.race) == "table" and number(r.race.score) or nil
    return { rank = rank, record = r, me = me,
             cells = { tostring(rank), score and NS.Format.Number(score) or DASH,
                       NS.Format.Number(NS.RaceRecord.Dps(r)), dateOf(r) }, colors = {} }
end

local function same(a, b) return a ~= nil and b ~= nil and (a == b or a.id == b.id) end

--- Top races' rows: the top `n` (default TOP_N) of `ranked` (NS.Bests.Ranked's), and `record`'s
--- own row with its rank after them when it ranks below; `me` marks this race's row wherever it is.
--- Each { rank, record, me, cells = { rank, score, DPS, date } }.
--- @param record table|nil  this race (nil on the idle body)
--- @param ranked table
--- @param n number|nil
--- @return table rows
function Board.Rows(record, ranked, n)
    n = n or Board.TOP_N
    local rows = {}
    for i, r in ipairs(ranked or {}) do
        local me = same(r, record)
        if i <= n then
            rows[#rows + 1] = boardRow(i, r, me)
        elseif me then
            rows[#rows + 1] = boardRow(i, r, true)
            break
        end
    end
    return rows
end

--- The board's words beside its caption: the dummy kind and the length, and the spec when given.
--- @return string
function Board.Note(kind, length, spec)
    local parts = { NS.Dummies.Label(kind), NS.Format.Length(length) }
    if type(spec) == "string" and spec ~= "" then parts[#parts + 1] = spec end
    return table.concat(parts, DOT)
end

--- A table's height for `rows` data rows, its header row included, at `rowH` (default ROW_H).
--- @return number
function Board.TableHeight(rows, rowH)
    return (rows + 1) * (rowH or Board.ROW_H)
end

--- A captioned table's height (its heading, its header, `rows` rows) at `rowH` (default ROW_H).
--- @return number
function Board.SectionHeight(rows, rowH)
    return Board.CAPTION_H + Board.TableHeight(rows, rowH)
end

--- How a stack spends `spare` pixels (config only: the content's height less the stack at its
--- least): first its `rows` table rows grow, by half the spare at most, up to ROW_MAX; then the
--- clear space over each of its `gaps` headings (and the buttons') grows from `gap` up to GAP_MAX.
--- What is left stays above the buttons.
--- @param spare number
--- @param rows number  the table rows drawn, the header rows included
--- @param gaps number  the gaps that may grow
--- @param gap number  a gap at its least
--- @return number rowH, number gap
function Board.Spread(spare, rows, gaps, gap)
    spare = math.max(0, math.floor(tonumber(spare) or 0))
    local rowH = Board.ROW_H
    if rows > 0 then
        rowH = math.min(Board.ROW_MAX, Board.ROW_H + math.floor(spare / (2 * rows)))
        spare = spare - (rowH - Board.ROW_H) * rows
    end
    if gaps > 0 then gap = math.min(Board.GAP_MAX, gap + math.floor(spare / gaps)) end
    return rowH, gap
end

-- ── the running clock's color ──────────────────────────────────────────────────────────────────

-- The time left as the countdown draws it (Format.Clock's tenths, truncated), so the color turns on
-- the very beat the figure does.
local function shownLeft(timeLeft)
    local left = tonumber(timeLeft) or 0
    if left < 0 then left = 0 end
    return math.floor(left * 10 + 1e-6) / 10
end

local function mix(a, b, t)
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

--- The countdown's and the time bar's color at `timeLeft` of `length` (plain GetTime() figures):
--- green (ct.ahead) while the first GREEN_SHARE of the race runs, red (sem.statusBad) for the last
--- RED_AT seconds, and between them a blend, green to yellow (ct.caution) to red, reaching red as the
--- countdown shows RED_AT. A race so short that its green half runs into the last RED_AT seconds is
--- red there: red wins.
--- @param timeLeft number
--- @param length number
--- @return number r, number g, number b
function Board.ClockColor(timeLeft, length)
    local left = shownLeft(timeLeft)
    if left <= Board.RED_AT then return mix(C.red, C.red, 0) end
    local greenTill = (tonumber(length) or 0) * (1 - Board.GREEN_SHARE)
    if left >= greenTill then return mix(C.green, C.green, 0) end
    local t = (greenTill - left) / (greenTill - Board.RED_AT)
    if t < 0.5 then return mix(C.green, C.amber, t * 2) end
    return mix(C.amber, C.red, (t - 0.5) * 2)
end

-- ── a section caption ───────────────────────────────────────────────────────────────────────────

--- A section heading in FONT.SECTION (the DPS HUD's), a dim note at its right (`note` fixed words,
--- or set later).
--- @return table cap  { title, note }
function Board.NewCaption(parent, title, note)
    local cap = { parent = parent }
    cap.title = Style.Text(parent, FONT.SECTION)
    cap.title:SetText(title)
    cap.note = Style.Text(parent, FONT.CAPTION, nil, "RIGHT")
    cap.note:SetText(note or "")
    return cap
end

--- Put the heading at `y` (pixels below the parent's top), its note on the heading's bottom edge
--- at `width`'s right end (the body's width, required: it follows the grip), as the DPS HUD's chart
--- and spell rows have theirs.
function Board.PlaceCaption(cap, y, width)
    local p = cap.parent
    cap.title:ClearAllPoints()
    cap.title:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -y)
    cap.note:ClearAllPoints()
    cap.note:SetPoint("BOTTOMRIGHT", cap.title, "BOTTOMLEFT", width, 0)
end

function Board.ShowCaption(cap, on)
    cap.title:SetShown(on)
    cap.note:SetShown(on)
end

-- ── a table ─────────────────────────────────────────────────────────────────────────────────────

local Table = {}
Table.__index = Table

-- One row's cells and the band behind it (this race's highlight).
local function newRow(parent, cols, font)
    local row = { cells = {} }
    row.band = parent:CreateTexture(nil, "BACKGROUND")
    Style.Fill(row.band, C.info, 0.18)
    row.band:Hide()
    for i, col in ipairs(cols) do row.cells[i] = Style.Text(parent, font, font == FONT.TEXT and C.text or nil, col.justify) end
    return row
end

--- A table of `cols` ({ head, w?, justify }: a column without `w` shares the width left), its header
--- row in the caption face over `max` rows in the text face. Both of the window's tables pass the
--- same widths (the lead column LEAD_W, three shared), so they stand on one grid.
--- @return table tbl
function Board.NewTable(parent, cols, max)
    local t = setmetatable({ parent = parent, cols = cols, rows = {}, shown = {} }, Table)
    t.header = newRow(parent, cols, FONT.CAPTION)
    for i, col in ipairs(cols) do t.header.cells[i]:SetText(col.head) end
    for i = 1, max do t.rows[i] = newRow(parent, cols, FONT.TEXT) end
    return t
end

-- The columns' left edges and widths across `width`.
local function columns(cols, width)
    local fixed, shared = 0, 0
    for _, col in ipairs(cols) do
        if col.w then fixed = fixed + col.w else shared = shared + 1 end
    end
    local each = shared > 0 and math.floor((width - fixed) / shared) or 0
    local out, x = {}, 0
    for i, col in ipairs(cols) do
        local w = col.w or each
        out[i] = { x = x, w = w }
        x = x + w
    end
    return out
end

-- A row at `y`, `rowH` tall: the band over the whole row, the text line centered in it.
local function placeRow(row, parent, at, y, width, rowH)
    row.band:ClearAllPoints()
    row.band:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    row.band:SetSize(width, rowH)
    local inset = math.floor((rowH - TEXT_PX) / 2)
    for i, fs in ipairs(row.cells) do
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", at[i].x, -(y + inset))
        fs:SetWidth(at[i].w)
    end
end

--- The grid's columns across `width`: { x, w } per column (the suites read it).
function Table:Grid(width)
    return columns(self.cols, width)
end

--- Put the table at `y` across `width`, each row `rowH` tall (default ROW_H).
function Table:Place(y, width, rowH)
    rowH = rowH or Board.ROW_H
    local at = columns(self.cols, width)
    self.rowH = rowH
    placeRow(self.header, self.parent, at, y, width, rowH)
    for i, row in ipairs(self.rows) do placeRow(row, self.parent, at, y + i * rowH, width, rowH) end
end

local function showRow(row, on)
    for _, fs in ipairs(row.cells) do fs:SetShown(on) end
    if not on then row.band:Hide() end
end

--- Draw `list` (rows of { cells, colors?, me? }), hiding the rows left over; nil or {} hides the table.
function Table:Set(list)
    list = list or {}
    showRow(self.header, list[1] ~= nil)
    self.shown = {}
    for i, row in ipairs(self.rows) do
        local item = list[i]
        showRow(row, item ~= nil)
        if item then
            for j, fs in ipairs(row.cells) do
                fs:SetText(item.cells[j] or "")
                Style.Paint(fs, (item.colors and item.colors[j]) or C.text)
            end
            row.band:SetShown(item.me == true)
            self.shown[i] = item
        end
    end
end

--- The rows drawn now, as their cell texts (the suites read these).
function Table:Texts()
    local out = {}
    for i, item in ipairs(self.shown) do out[i] = table.concat(item.cells, "|") end
    return out
end

--- Which drawn row is highlighted (this race's), or nil.
function Table:Highlighted()
    for i, row in ipairs(self.rows) do
        if self.shown[i] and row.band:IsShown() then return i end
    end
    return nil
end

--- Against your best's table: the row label, This race, Best, Diff.
function Board.NewCompare(parent)
    return Board.NewTable(parent, {
        { head = "", w = Board.LEAD_W, justify = "LEFT" }, { head = L["This race"], justify = "RIGHT" },
        { head = L["Best"], justify = "RIGHT" }, { head = L["Diff"], justify = "RIGHT" },
    }, 4)
end

--- Top races' table: the rank, Score, DPS, Date; `max` rows (the top three and this race's). The
--- rank takes the lead column, so Score, DPS and Date stand under This race, Best and Diff.
function Board.NewBoard(parent, max)
    return Board.NewTable(parent, {
        { head = L["#"], w = Board.LEAD_W, justify = "LEFT" }, { head = L["Score"], justify = "RIGHT" },
        { head = L["DPS"], justify = "RIGHT" }, { head = L["Date"], justify = "RIGHT" },
    }, max or Board.TOP_N + 1)
end

-- ── Best by now ─────────────────────────────────────────────────────────────────────────────────

-- A labeled figure in the Best by now card: Best to beat's (NS.RaceWindowBest.Figure), the card's
-- half from `from` to `to`, its label (muted gold) then its value a fixed LABEL_W after it, every edge
-- the card's: Current may be secret, so nothing is measured off or anchored to its text.
local function nowFigure(card, from, x, to, toX, label, color)
    return NS.RaceWindowBest.Figure(card, from, x, to, toX, label, color, FONT.HEADING)
end

--- The Best by now section: its caption ("at m:ss" beside it), a mini pace bar (the DPS HUD's,
--- thinner: its track and its on-pace tick) and a card with the best's damage by now (Best, blue)
--- beside the player's own now (Current, white: the DPS HUD's last read). Its box restyles with the
--- body's; the bar restyles itself on the Appearance stamp.
--- @return table now  { cap, pace, card, value, you, bestLabel, youLabel }
function Board.NewByNow(body, parent)
    local now = { cap = Board.NewCaption(parent, L["Best by now"]) }
    local tip = { L["Best by now"], L["Where your best on this race board stood at this second of its race, read off its straight line: its score over the race length, times the time raced. Beside it, Current: your own damage so far, as the DPS HUD last read it. The bar over it is the DPS HUD's pace bar, thinner: green past the middle tick, red short of it."] }
    now.pace = Chart.NewPace(parent, { barH = Board.NOW_PACE_H, tip = false })
    NS.RaceWindowStates.AddTip(now.pace.bar, tip)
    local card = NS.HudStates.Card(parent)
    card:SetHeight(Board.NOW_H)
    now.card = card
    now.bestLabel, now.value = nowFigure(card, "LEFT", 8, "CENTER", -4, L["Best"], BEST_C)
    now.youLabel, now.you = nowFigure(card, "CENTER", 4, "RIGHT", -8, L["Current"], CURRENT_C)
    now.you:SetText(DASH)
    NS.RaceWindowStates.AddTip(card, tip)
    body.boxes[#body.boxes + 1] = card
    return now
end

--- Put the section at `y` across `width`: the caption, the mini pace bar's line, the card, each
--- anchored to the body's content frame (plain); answers the y under it.
function Board.PlaceByNow(now, y, width)
    local p = now.cap.parent
    Board.PlaceCaption(now.cap, y, width)
    y = y + Board.CAPTION_H
    now.pace:Place(p, -y, width)
    y = y + Board.NOW_PACE_LINE
    now.card:ClearAllPoints()
    now.card:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -y)
    now.card:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -y)
    return y + Board.NOW_H
end

function Board.ShowByNow(now, on)
    Board.ShowCaption(now.cap, on)
    now.pace:SetShown(on)
    now.card:SetShown(on)
end

--- Draw the best's damage by now at `elapsed`, and the player's `you` (opaque: a label's text and
--- the bar's value only) when `hasYou` (plain) says there is one, else a dash and a bar with its
--- halves hidden. The bar's range is HudBest.Bounds around `ref` (plain; default `damage`, the
--- best's by now), at the DPS HUD's Pace range.
function Board.SetByNow(now, damage, elapsed, you, hasYou, ref)
    now.cap.note:SetText(L["at %s"]:format(NS.Format.Length(math.floor(tonumber(elapsed) or 0))))
    now.value:SetText(NS.Format.Number(damage))
    now.pace:SetRange(NS.HudBest.Bounds(ref or damage))
    if hasYou then
        now.you:SetText(NS.Format.Number(you))
        now.pace:SetTotal(you)
    else
        now.you:SetText(DASH)
        now.pace:Blank()
    end
end

-- ── Checkpoints ─────────────────────────────────────────────────────────────────────────────────

-- A cell, top to bottom: the time (muted gold, a size above the figures), the best's figure (blue), Current (white), each line
-- anchored to the cell; then the mini pace bar on its own line, bare (no track: only the green or the
-- red grows from the tick), hidden until the checkpoint is captured.
local function newCell(parent)
    local cell = Style.FlatBox(parent)
    cell:SetHeight(Board.CP_H)
    local rows = Board.CP_ROWS
    cell.time = Style.Text(cell, FONT.HEADING, LABEL_C, "CENTER")
    cell.time:SetPoint("TOP", cell, "TOP", 0, -rows[1])
    cell.value = Style.Text(cell, FONT.TEXT, BEST_C, "CENTER")
    cell.value:SetPoint("TOP", cell, "TOP", 0, -rows[2])
    cell.you = Style.Text(cell, FONT.TEXT, CURRENT_C, "CENTER")
    cell.you:SetPoint("TOP", cell, "TOP", 0, -rows[3])
    cell.you:SetText(DASH)
    cell.pace = Chart.NewPace(cell, { barH = Board.CP_PACE_H, bare = true, tip = false })
    cell.pace:SetShown(false)
    return cell
end

--- The Checkpoints section: its caption and four cells, each the time, the best's damage there,
--- Current at it, and a mini pace bar of the two.
--- @return table cps  { cap, cells }
function Board.NewCheckpoints(parent)
    local cps = { cap = Board.NewCaption(parent, L["Checkpoints"], L["best \194\183 current"]), cells = {} }
    for i = 1, 4 do cps.cells[i] = newCell(parent) end
    local tip = { L["Checkpoints"], L["Your best's damage at each quarter of the race, off its straight line, and under it yours as the clock passed that quarter (the DPS HUD's reading then). A quarter not reached yet shows a dash. Once it is passed, the bar under them grows from its middle tick: green as far as you were ahead of your best there, red as far behind. The passed ones dim and are outlined green; the one the clock is in is outlined amber."] }
    for _, cell in ipairs(cps.cells) do NS.RaceWindowStates.AddTip(cell, tip) end
    return cps
end

--- Put the section at `y` across `width`; answers the y under it.
function Board.PlaceCheckpoints(cps, y, width)
    local p = cps.cap.parent
    Board.PlaceCaption(cps.cap, y, width)
    local w = math.floor((width - 3 * Board.CP_GAP) / 4)
    local barW = math.floor(w * Board.CP_PACE_SHARE)
    for i, cell in ipairs(cps.cells) do
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", p, "TOPLEFT", (i - 1) * (w + Board.CP_GAP), -(y + Board.CAPTION_H))
        cell:SetWidth(w)
        cell.pace:Place(cell, -Board.CP_PACE_Y, barW, math.floor((w - barW) / 2))
    end
    return y + Board.CAPTION_H + Board.CP_H
end

function Board.ShowCheckpoints(cps, on)
    Board.ShowCaption(cps.cap, on)
    for _, cell in ipairs(cps.cells) do cell:SetShown(on) end
end

-- A cell's Current and its mini pace bar: the reading (opaque) to the label and the bar, the bar's
-- range HudBest.Bounds around the best's figure there (`cp.paceRef`, plain, default `cp.damage`); a dash
-- and no bar before the capture (`cp.hasYou`, plain).
local function setCurrent(cell, cp)
    cell.pace:SetShown(cp.hasYou == true)
    if not cp.hasYou then
        cell.you:SetText(DASH)
        return
    end
    cell.you:SetText(NS.Format.Number(cp.you))
    cell.pace:SetRange(NS.HudBest.Bounds(cp.paceRef or cp.damage))
    cell.pace:SetTotal(cp.you)
end

--- Draw Board.Checkpoints' list: the passed ones' best figure dim (its blue at a lower alpha) and
--- their box outlined green, the one in progress outlined amber; under each best figure the player's reading at that quarter (`cp.you`, opaque)
--- and its mini pace bar when `cp.hasYou` (plain), else a dash and no bar.
function Board.SetCheckpoints(cps, list)
    for i, cell in ipairs(cps.cells) do
        local cp = list[i]
        cell.time:SetText(NS.Format.Length(cp.t))
        cell.value:SetText(NS.Format.Number(cp.damage))
        cell.value:SetAlpha(cp.passed and Board.PASSED_A or 1)
        setCurrent(cell, cp)
        -- Outlined green once passed, amber while the clock runs through it (the owner, 2026-11-13).
        local edge = (cp.passed and C.green) or (cp.next and C.amber) or C.dim
        Style.TintBox(cell, edge, (cp.passed or cp.next) and Style.CHIP_EDGE_A or 0.25)
        cell.passed, cell.next = cp.passed, cp.next
    end
end
