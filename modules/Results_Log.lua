local _, NS = ...
-- modules/Results_Log.lua — the Results fight detail's Log tab (CombatTrail #11, plan item CL-11c; the
-- spec's addendum, home C): the fight's saved log (modules/CombatLog.lua's `record.log`) in the shared
-- table (modules/LogTable.lua, modules/LogTable_View.lua), the chips that filter it with each one's
-- count, and the Damage by spell panel beside it. Built, filled and laid out by the detail pane
-- (modules/Results_Detail.lua) through Build, Fill, Layout and Hide, as its other sections are.
--
-- THE LAYOUT. One line naming the fight (its target and level, its length) with the lines kept (and
-- those the cap dropped) at its right; the chips under it, wrapping; then the table, its rows filling
-- the tab's height, with the Info column. The Damage by spell panel stands beside the table where
-- the tab is SIDE_MIN wide or more (the expanded window's detail is not: the collapsed view's is),
-- else under it, UNDER_ROWS rows at most. Under the table, a hint names the cast click.
--
-- THE CHIPS: Casts, Pet, Buffs, Debuffs, Taken (hits on you) and Heals (on you), each with the count of
-- its lines in the saved log. They filter what is shown, never what is saved. Each fight opens on
-- `log.results.chips` (all on), and a click turns one on or off for the fight shown. A death follows
-- `log.show.deaths` and a hit or a heal under `log.show.minAmount` (a plain amount only) is hidden, as
-- in the live views. A log saved before owner feedback item 10 may hold the fight's PULL and END lines:
-- they are never shown or counted (CombatLog.IsBoundary), and the log on disk is left as it is.
--
-- THE TABLE is the live homes' component on a stored list: no feed, no follow. `log.view.sort` decides
-- the order (newest first by default, the Time header flips it, as everywhere), and the first page is
-- the top of that order. The wheel moves SCROLL lines at a time. The cells' context is the record's:
-- the pull's clock time (`record.t`). There is no Source or Target column (owner feedback item 3), so
-- `record.logTargets` is kept on the record and not drawn.
--
-- A CLICK ON A CAST ROW opens the ability timeline on the fight (modules/Results_Timeline.lua) and
-- jumps it to that cast (Timeline.FocusAt), while `log.results.jumpToCast` is on (the default) and the
-- fight has casts to draw.
--
-- DAMAGE BY SPELL is the record's own spell breakdown (Recorder.Spells, the read the Overview's Spell
-- breakdown uses: the meter is never read again) in the DPS HUD's spell rows (modules/Hud_Breakdown.lua):
-- the same bars, colors (the player's and the pet's) and order.
--
-- A FIGHT SAVED BEFORE THE LOG (CT_SCHEMA 5 and older), or with saving off, has no `log`: the tab says
-- "No log was saved for this fight" and draws nothing else.
--
-- PLAIN DATA ONLY. A saved line holds plain numbers and "s" for a sealed amount, which LogTable.Cells
-- draws as "sealed". The counts count lines, never amounts.

local ResultsLog = {}
NS.ResultsLog = ResultsLog

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT
local Secrets = NS.Secrets
local LogTable = NS.LogTable
local CL = NS.CombatLog
local K = CL.KIND

ResultsLog.TITLE_H = 18
ResultsLog.CHIP_H = 18
ResultsLog.CHIP_GAP = 4
ResultsLog.CHIP_PAD = LogTable.CHIP_PAD
ResultsLog.CHAR_W = LogTable.CHIP_CHAR_W
ResultsLog.GAP = 8
ResultsLog.SIDE_W = 190      -- the Damage by spell panel beside the table
ResultsLog.SIDE_MIN = 560    -- the least tab width that sets the panel beside the table
ResultsLog.UNDER_ROWS = 4    -- the panel's most rows under the table
ResultsLog.PANEL_HEAD = 18
ResultsLog.HINT_H = 14
ResultsLog.SCROLL = 3        -- lines a wheel notch moves

--- The chips, left to right: their key, their label and the saved categories each one covers (the
--- shared table's, LogTable.CHIPS, which the live views' chips use too).
ResultsLog.CHIPS = LogTable.CHIPS

local CHIP_TIPS = LogTable.CHIP_TIPS

local CHIP_OF = {}   -- [category] = chip key
for _, chip in ipairs(ResultsLog.CHIPS) do
    for _, cat in ipairs(chip.cats) do CHIP_OF[cat] = chip.key end
end

local function setting(path)
    return NS.GetSetting and NS.GetSetting(path)
end

-- ── pure ────────────────────────────────────────────────────────────────────────────────────────

--- The chip line `e` falls under, or nil (a retired boundary, a death, an auto attack), and its category.
--- @return string|nil chip, string|nil category
function ResultsLog.ChipOf(e)
    local cat = CL.CategoryOf(e.k, e.u, e.id)
    return cat and CHIP_OF[cat] or nil, cat
end

--- Each chip's count of lines in `log` (a saved log), into `out` (a reused table): lines, never amounts.
--- @return table out  [chip key] = count
function ResultsLog.Counts(log, out)
    out = out or {}
    for _, chip in ipairs(ResultsLog.CHIPS) do out[chip.key] = 0 end
    for _, e in ipairs(type(log) == "table" and log or {}) do
        local key = type(e) == "table" and ResultsLog.ChipOf(e) or nil
        if key then out[key] = out[key] + 1 end
    end
    return out
end

--- The chips a fight opens on (`log.results.chips`, each on unless false), into `out`.
--- @return table out  [chip key] = boolean
function ResultsLog.DefaultChips(out)
    out = out or {}
    for _, chip in ipairs(ResultsLog.CHIPS) do out[chip.key] = setting("log.results.chips." .. chip.key) ~= false end
    return out
end

--- Whether saved line `e` shows under the chips `chips` and `show` (`log.show`: its deaths and its
--- least amount). A retired boundary never shows.
--- @return boolean
function ResultsLog.Accept(e, chips, show)
    local key, cat = ResultsLog.ChipOf(e)
    if cat == "deaths" then return show.deaths ~= false end
    if not key or chips[key] == false then return false end
    local min = Secrets.PlainNumber(show.minAmount) or 0
    if min > 0 and (e.k == K.HIT or e.k == K.HEAL) then
        local a = Secrets.PlainNumber(e.a)
        if a and a < min then return false end
    end
    return true
end

--- The indices of `log`'s shown lines, in the order the table draws them top down (`sort` "newest":
--- the last line first; "oldest": the first), into `out`. Answers how many.
--- @return number n
function ResultsLog.Order(log, chips, show, sort, out)
    local n, total = 0, #log
    local from, to, step = total, 1, -1
    if sort == "oldest" then from, to, step = 1, total, 1 end
    for i = from, to, step do
        local e = log[i]
        if type(e) == "table" and ResultsLog.Accept(e, chips, show) then n = n + 1; out[n] = i end
    end
    for i = n + 1, #out do out[i] = nil end
    return n
end

--- The page of `rows` lines `offset` into `order` (n long), as View:Draw takes them: newest first, so
--- an "oldest" sort's page is handed over reversed (the view reverses it back). Answers how many.
--- @return number
function ResultsLog.Page(order, n, offset, rows, sort, out)
    local count = math.max(0, math.min(rows, n - offset))
    for j = 1, count do
        out[j] = order[offset + (sort == "oldest" and (count - j + 1) or j)]
    end
    for j = count + 1, #out do out[j] = nil end
    return count
end

--- The widest a scroll goes: the last page's offset.
function ResultsLog.MaxOffset(n, rows)
    return math.max(0, n - math.max(1, rows))
end

--- `ctx` (a reused table) refilled for stored `record`: the time format, the pull's clock time and the
--- color switches.
function ResultsLog.Context(record, ctx)
    ctx.startT = nil
    ctx.timeFormat = setting("log.view.timeFormat")
    ctx.startClock = Secrets.PlainNumber(record.t)
    ctx.schoolColors = setting("log.view.schoolColors") ~= false
    ctx.washes = setting("log.view.washes") ~= false
    return LogTable.ReadColors(ctx)
end

--- How many of a saved log's lines are events: a retired boundary is not one.
--- @return number
function ResultsLog.Lines(log)
    local n = 0
    for _, e in ipairs(type(log) == "table" and log or {}) do
        if type(e) == "table" and not CL.IsBoundary(e) then n = n + 1 end
    end
    return n
end

--- The title line's right-hand caption: "212 lines" and, when the cap dropped some, "40 not kept".
function ResultsLog.Caption(log, dropped)
    local text = L["%d lines"]:format(ResultsLog.Lines(log))
    if (tonumber(dropped) or 0) > 0 then text = text .. " \194\183 " .. L["%d not kept"]:format(dropped) end
    return text
end

--- The title line: the fight's target, its level where the record has one, and its length.
function ResultsLog.Title(record)
    local parts = { NS.ResultsFights.TargetName(record) }
    parts[#parts + 1] = NS.ResultsFights.LevelWords(record)
    parts[#parts + 1] = NS.Format.Length(record.duration)
    return table.concat(parts, " \194\183 ")
end

--- A chip's estimated width for `text` (nothing is measured): the shared table's.
ResultsLog.ChipWidth = LogTable.ChipWidth

--- Whether the Damage by spell panel stands beside the table on a tab `width` wide.
function ResultsLog.Beside(width)
    return (tonumber(width) or 0) >= ResultsLog.SIDE_MIN
end

-- ── the tab ─────────────────────────────────────────────────────────────────────────────────────

local function write(path, value)
    if NS.SetByPath then NS.SetByPath(path, value) end
end

local function canJump(p)
    local g = p.log
    return setting("log.results.jumpToCast") ~= false and g.hasCasts and p.hooks.timelineAt ~= nil
end

-- A click on a row: a CAST row opens the timeline on its moment.
local function onClick(p, e)
    if e.k ~= K.CAST or not canJump(p) then return end
    p.hooks.timelineAt(p, e.t)
end

local function chipText(chip, count)
    return ("%s %d"):format(L[chip.label], count or 0)
end

local function paintChip(g, chip)
    local b = g.chips[chip.key]
    Style.SetButtonStyle(b, g.chipOn[chip.key] and "primary" or "normal")
end

local function buildChips(p, f)
    local g = p.log
    for _, chip in ipairs(ResultsLog.CHIPS) do
        local b = Style.Button(f, chipText(chip, 0), function() ResultsLog.ToggleChip(p, chip.key) end)
        b:SetHeight(ResultsLog.CHIP_H)
        b.tip, b.tipBody = { L[chip.label], L[CHIP_TIPS[chip.key]], L["Click to show or hide them."] }, true
        g.chips[chip.key] = b
    end
end

local function buildPanel(g, f)
    g.spellsTitle = Style.Text(f, FONT.CHART)
    g.spellsTitle:SetText(L["Damage by spell"])
    g.spellsHost = CreateFrame("Frame", nil, f)
    g.spells = NS.HudBreakdown.New(g.spellsHost)
end

--- Build the Log tab into pane `p` (its frame), as `p.log`. Hidden until the tab is shown.
function ResultsLog.Build(p)
    local f = CreateFrame("Frame", nil, p.frame)
    f:Hide()
    local g = { frame = f, chips = {}, chipOn = {}, counts = {}, order = {}, seqs = {}, ctx = {}, show = {},
                offset = 0, n = 0, rows = 1 }
    p.log = g
    g.lineOf = function(i) return g.log and g.log[i] or nil end
    g.title = Style.Text(f, FONT.HEADING, "ct.text")
    g.caption = Style.Text(f, FONT.CAPTION, nil, "RIGHT")
    buildChips(p, f)
    g.table = LogTable.New(f, {
        info = true,
        onSort = function() write("log.view.sort", LogTable.SortOf() == "newest" and "oldest" or "newest") end,
        onScroll = function(away) ResultsLog.Scroll(p, away) end,
        onClick = function(e) onClick(p, e) end,
    })
    buildPanel(g, f)
    g.hint = Style.Text(f, FONT.CAPTION)
    g.hint:SetText(L["Click a CAST row to see it on the Timeline."])
    g.none = Style.Text(f, FONT.EMPTY, nil, "CENTER")
    g.none:SetPoint("CENTER", f, "CENTER", 0, 0)
    g.none:SetText(L["No log was saved for this fight"])
    return g
end

-- The shown lines again from the log, the chips and `log.show`, the scroll kept in range.
local function reorder(g)
    if not g.log then g.n = 0; return end
    g.sort = LogTable.SortOf()
    g.n = ResultsLog.Order(g.log, g.chipOn, LogTable.ReadShow(g.show), g.sort, g.order)
    g.offset = math.max(0, math.min(g.offset, ResultsLog.MaxOffset(g.n, g.rows)))
end

--- Fill the tab for the pane's fight. The same fight drawn again (`same`) keeps its chips and scroll;
--- another opens on `log.results.chips` at the top.
function ResultsLog.Fill(p, same)
    local g, record = p.log, p.record
    if not g or not record then return end
    local log, dropped = CL.Of(record)
    if log and ResultsLog.Lines(log) == 0 then log = nil end
    g.log, g.dropped = log, dropped
    if not same then
        ResultsLog.DefaultChips(g.chipOn)
        g.offset = 0
    end
    ResultsLog.Counts(log, g.counts)
    for _, chip in ipairs(ResultsLog.CHIPS) do
        local b = g.chips[chip.key]
        b.chipText = chipText(chip, g.counts[chip.key])
        b.label:SetText(b.chipText)
        paintChip(g, chip)
    end
    g.title:SetText(ResultsLog.Title(record))
    g.caption:SetText(log and ResultsLog.Caption(log, dropped) or "")
    g.spellList = NS.Recorder.Spells(record)
    g.total = type(record.damage) == "table" and record.damage.merged or 0
    g.hasCasts = NS.ResultsTimelineData.Has(record)
    ResultsLog.Context(record, g.ctx)
    reorder(g)
end

-- The chips laid left to right from `y`, wrapping at `cw`: the y under them.
local function layChips(g, y, cw)
    local x, rowY = 0, y
    for _, chip in ipairs(ResultsLog.CHIPS) do
        local b = g.chips[chip.key]
        local w = ResultsLog.ChipWidth(b.chipText or "")
        if x > 0 and x + w > cw then x, rowY = 0, rowY - ResultsLog.CHIP_H - ResultsLog.CHIP_GAP end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", g.frame, "TOPLEFT", x, rowY)
        b:SetWidth(w)
        b:Show()
        x = x + w + ResultsLog.CHIP_GAP
    end
    return rowY - ResultsLog.CHIP_H - ResultsLog.GAP
end

local function setShown(g, has)
    for _, b in pairs(g.chips) do b:SetShown(has) end
    g.table.frame:SetShown(has)
    g.spellsTitle:SetShown(has)
    g.spellsHost:SetShown(has)
    g.none:SetShown(not has)
    if not has then g.hint:Hide() end
end

-- The Damage by spell panel at (x, y), `w` wide with `room` px under its heading: its rows drawn.
local function layPanel(g, x, y, w, room, most)
    g.spellsTitle:ClearAllPoints()
    g.spellsTitle:SetPoint("TOPLEFT", g.frame, "TOPLEFT", x, y)
    g.spellsHost:ClearAllPoints()
    g.spellsHost:SetPoint("TOPLEFT", g.frame, "TOPLEFT", x, y - ResultsLog.PANEL_HEAD)
    local n = math.min(#g.spellList, NS.HudBreakdown.Capacity(room), most or math.huge)
    g.spellsHost:SetSize(w, math.max(1, NS.HudBreakdown.Height(n)))
    g.spellRows = g.spells:ShowFinal(g.spellList, g.total, n)
end

-- The panel's height under the table (its heading and up to UNDER_ROWS rows), 0 with no spells.
local function underHeight(g)
    local n = math.min(#g.spellList, ResultsLog.UNDER_ROWS)
    if n == 0 then return 0 end
    return ResultsLog.GAP + ResultsLog.PANEL_HEAD + NS.HudBreakdown.Height(n)
end

--- Lay the tab out in its pane at `top` (px down from the pane's top), `cw` x `h`, and draw it.
function ResultsLog.Layout(p, x, top, cw, h)
    local g = p.log
    local f = g.frame
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", p.frame, "TOPLEFT", x, -top)
    f:SetSize(cw, h)
    f:Show()
    g.title:ClearAllPoints()
    g.title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    g.title:SetWidth(cw)
    g.caption:ClearAllPoints()
    g.caption:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -2)
    local has = g.log ~= nil
    setShown(g, has)
    if not has then return end
    local y = layChips(g, -ResultsLog.TITLE_H - 2, cw)
    local beside = ResultsLog.Beside(cw) and #g.spellList > 0
    local tableW = beside and (cw - ResultsLog.SIDE_W - ResultsLog.GAP) or cw
    g.beside, g.tableW = beside, tableW
    local jump = canJump(p)
    g.hint:SetShown(jump)
    local below = (beside and 0 or underHeight(g)) + (jump and ResultsLog.HINT_H or 0)
    local room = h + y - below
    g.rows = math.max(1, math.floor((room - LogTable.HEAD_H) / LogTable.RowH()))
    g.table.frame:ClearAllPoints()
    g.table.frame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
    g.table.frame:SetWidth(tableW)
    g.table:Layout(tableW, g.rows, setting("log.view.columns"))
    local tableBottom = y - LogTable.Height(g.rows)
    if beside then
        layPanel(g, tableW + ResultsLog.GAP, y, ResultsLog.SIDE_W, h + y - ResultsLog.PANEL_HEAD)
    else
        layPanel(g, 0, tableBottom - ResultsLog.GAP, cw, NS.HudBreakdown.Height(ResultsLog.UNDER_ROWS), ResultsLog.UNDER_ROWS)
    end
    g.spellsTitle:SetShown(#g.spellList > 0)
    g.hint:ClearAllPoints()
    g.hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    reorder(g)
    ResultsLog.Draw(p)
end

--- Paint the table's page: `rows` shown lines from the scroll's offset, in the sort's order.
function ResultsLog.Draw(p)
    local g = p.log
    if not (g and g.log) then return end
    local n = ResultsLog.Page(g.order, g.n, g.offset, g.rows, g.sort, g.seqs)
    g.table:SetSort(g.sort)
    g.table:Draw(g.seqs, n, g.lineOf, g.ctx, L["No lines match the chips."])
end

--- Hide the tab (another tab shown, or no fight).
function ResultsLog.Hide(p)
    if p.log then p.log.frame:Hide() end
end

--- Turn chip `key` on or off for the fight shown, back to the top of the list.
function ResultsLog.ToggleChip(p, key)
    local g = p.log
    if not (g and g.log) then return end
    g.chipOn[key] = not g.chipOn[key]
    for _, chip in ipairs(ResultsLog.CHIPS) do if chip.key == key then paintChip(g, chip) end end
    g.offset = 0
    reorder(g)
    ResultsLog.Draw(p)
end

--- The wheel: `away` (1 or -1, LogTable_View's, from the newest line) moved into the list's own
--- direction, SCROLL lines a notch, kept in range.
function ResultsLog.Scroll(p, away)
    local g = p.log
    if not (g and g.log) then return end
    local down = g.sort == "oldest" and -away or away
    g.offset = math.max(0, math.min(ResultsLog.MaxOffset(g.n, g.rows), g.offset + down * ResultsLog.SCROLL))
    ResultsLog.Draw(p)
end

--- A `log.` setting moved (the sort, the colors, the columns, what is shown): the shown tab laid out
--- and drawn again, its chips and scroll kept.
function ResultsLog.Refresh(p)
    local g = p.log
    if not (g and p.record and g.frame:IsShown()) then return end
    ResultsLog.Context(p.record, g.ctx)
    p:Layout(p.width, p.height, p.narrow)
end
