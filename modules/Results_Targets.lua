local _, NS = ...
-- modules/Results_Targets.lua — the fight detail's Targets section (issue #6): which enemies your
-- damage reached and how much each took, below Usage. One row per enemy name, highest first, over a
-- bar in the Results table's blue whose length is the row's amount against the top target's (as
-- Blizzard's meter and EllesmereUI's skin of it draw their Targets): the name at the left, then three
-- right-aligned columns in the amount's white, a little apart and with no separators (owner,
-- 2026-11-11): the amount, its DPS over the whole fight, and its share of the fight's target damage.
--
-- THE DATA is the record's `targets` (Recorder.Targets: the meter's EnemyDamageTaken view, read once
-- after combat, when it is plain; enemies of one name merged, as the meter and Blizzard's own damage
-- meter show them). It is a Results-only section: in combat the view is secret, so the HUD never
-- draws it. A fight with no targets (one stored before CT_SCHEMA 3, or a meter that answered none)
-- has no section at all: no heading, arrow or note, as the Damage profile does for a fight this
-- session holds no chart of.
--
-- MEASURED (docs/midnight-quirks.md, WoW Forever 2026-11-11): solo, the rows sum to your own total.
-- Whether a row counts only your damage or the group's is not measured yet.
--
-- PLAIN DATA ONLY: the stored list. Rows are laid out from the constants here, never from a size read
-- back; Rows is pure over the record.

local ResultsTargets = {}
NS.ResultsTargets = ResultsTargets

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT

ResultsTargets.ROW_H = 20      -- one row, its bar 2 px shorter
-- The right-hand columns, right to left: the share, the DPS, the amount; COL_GAP between them.
ResultsTargets.SHARE_W = 44
ResultsTargets.DPS_W = 72
ResultsTargets.AMOUNT_W = 56
ResultsTargets.COL_GAP = 8
ResultsTargets.TEXT_X = 4      -- the name and the amount, in from the bar's ends
ResultsTargets.TEXT_Y = 4      -- the text's top, down from the row's

local function Tbl() return NS.ResultsTable end

-- ── pure ────────────────────────────────────────────────────────────────────────────────────────

--- The section's rows for `record`: { name, total, share, dps, fill } in stored order (highest first):
--- share in percent of the listed targets' sum; dps the amount over the fight's whole length (nil
--- with no length), so enemies merged by name or across sessions add up; fill the bar's length, the
--- amount against the top target's (0..1). Empty for a record with no targets, or none readable.
--- @return table rows
function ResultsTargets.Rows(record)
    local list = type(record) == "table" and record.targets or nil
    local rows, sum, top = {}, 0, 0
    if type(list) ~= "table" then return rows end
    local duration = type(record.duration) == "number" and record.duration > 0 and record.duration or nil
    for _, t in ipairs(list) do
        if type(t) == "table" and type(t.name) == "string" and type(t.total) == "number" and t.total > 0 then
            rows[#rows + 1] = { name = t.name, total = t.total, dps = duration and t.total / duration or nil }
            sum = sum + t.total
            top = math.max(top, t.total)
        end
    end
    for _, row in ipairs(rows) do
        row.share = row.total / sum * 100
        row.fill = row.total / top
    end
    return rows
end

--- A row's three right-hand cells: the amount, its DPS ("42 DPS", "" without the fight's length)
--- and its share ("63.8%").
--- @return string amount, string dps, string share
function ResultsTargets.Cells(row)
    local dps = type(row.dps) == "number" and L["%s DPS"]:format(NS.Format.Rate(row.dps)) or ""
    return NS.Format.Number(row.total), dps, NS.Format.Pct(row.share)
end

--- The three columns' widths together, their gaps included.
function ResultsTargets.ColumnsWidth()
    local T = ResultsTargets
    return T.AMOUNT_W + T.DPS_W + T.SHARE_W + 2 * T.COL_GAP
end

-- ── the section ─────────────────────────────────────────────────────────────────────────────────

--- Build the Targets section's parts into the pane `p` (its content `c`), as `p.targets`.
function ResultsTargets.Build(p, c)
    local x = { rows = {}, list = {} }
    p.targets = x
    x.title = Style.Text(c, FONT.SECTION)
    x.title:SetText(L["Targets"])
    x.titleHover = p:AddHeading("targets", x.title).click
    return x
end

local function newRow(p)
    local row = {}
    -- Under the text (BORDER beneath the FontStrings' OVERLAY), as the Results table's bars are.
    row.bar = p.content:CreateTexture(nil, "BORDER", nil, 2)
    row.name = Style.Text(p.content, FONT.TEXT, Tbl().COLORS.text)
    row.amount = Style.Text(p.content, FONT.TEXT, Tbl().COLORS.text, "RIGHT")
    row.dps = Style.Text(p.content, FONT.TEXT, Tbl().COLORS.text, "RIGHT")
    row.share = Style.Text(p.content, FONT.TEXT, Tbl().COLORS.text, "RIGHT")
    return row
end

--- Read `p.record`'s targets and paint the rows (laid out by Layout).
function ResultsTargets.Fill(p)
    local x = p.targets
    x.list = ResultsTargets.Rows(p.record)
    for i, data in ipairs(x.list) do
        x.rows[i] = x.rows[i] or newRow(p)
        local row, amount, dps, share = x.rows[i], ResultsTargets.Cells(data)
        row.name:SetText(data.name)
        row.amount:SetText(amount)
        row.dps:SetText(dps)
        row.share:SetText(share)
    end
end

local function hideRows(x, from)
    for i = from, #x.rows do
        for _, part in ipairs({ "bar", "name", "amount", "dps", "share" }) do x.rows[i][part]:Hide() end
    end
end

local function place(region, parent, px, py)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", px, py)
end

--- The section at `y` across `cw` (its heading INDENT in after its arrow); folded, the heading alone;
--- a fight with no targets, nothing. Answers the y beneath.
function ResultsTargets.Layout(p, y, cw)
    local x = p.targets
    local n = #x.list
    local shown = n > 0
    x.title:SetShown(shown)
    local folded = p:Heading("targets", shown)
    if not shown then
        hideRows(x, 1)
        return y
    end
    y = y - Style.SECTION_GAP
    place(x.title, p.content, NS.ResultsDetail.INDENT, y)
    y = y - Style.SECTION_H
    if folded then
        hideRows(x, 1)
        return y
    end
    local T = ResultsTargets
    local tx, ty = T.TEXT_X, T.TEXT_Y
    -- The columns' right edges, right to left from the bar's end.
    local shareR = cw - tx
    local dpsR = shareR - T.SHARE_W - T.COL_GAP
    local amountR = dpsR - T.DPS_W - T.COL_GAP
    for i = 1, n do
        local row, data, ry = x.rows[i], x.list[i], y - (i - 1) * T.ROW_H
        place(row.bar, p.content, 0, ry)
        Style.Fill(row.bar, Tbl().BAR_COLOR, Tbl().BAR_ALPHA)
        row.bar:SetSize(math.max(1, math.floor(cw * data.fill + 0.5)), T.ROW_H - 2)
        place(row.name, p.content, tx, ry - ty)
        row.name:SetWidth(math.max(20, amountR - T.AMOUNT_W - T.COL_GAP - tx))
        for _, col in ipairs({ { row.amount, amountR, T.AMOUNT_W }, { row.dps, dpsR, T.DPS_W },
                               { row.share, shareR, T.SHARE_W } }) do
            place(col[1], p.content, col[2] - col[3], ry - ty)
            col[1]:SetWidth(col[3])
            col[1]:Show()
        end
        row.bar:Show()
        row.name:Show()
    end
    hideRows(x, n + 1)
    return y - n * ResultsTargets.ROW_H - 8
end
