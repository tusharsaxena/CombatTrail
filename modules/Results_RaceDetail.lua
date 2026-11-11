local _, NS = ...
-- modules/Results_RaceDetail.lua — a race's own parts of the fight detail (Race mode plan Task D1, spec
-- §7): the Timing section (the race and the time after its buzzer as two segments, with the grace,
-- the damage tail, each late cast, the end of combat and a restart marked on them), the Flags section
-- (each flag's line, its detail and what it means, in the caution callout), the race's figures (its
-- score and race DPS, "DPS · Incomplete" for a race that ended before the buzzer), and the late-cast
-- right-click: on the Flags box here, and on a race's row through Results.RowMenu (FillRowMenu).
-- Ported from DPS Race @f8078c7 (modules/Results_Detail.lua's timing strip and flags box) onto the
-- race part; the Delta box keeps Combat Trail's look ("Leads by" and the Personal best chip, one look,
-- spec §1), read through the race DPS.
--
-- THE SECTIONS' SHAPE is modules/Results_Targets.lua's: Build(p, c) makes the parts into the pane as
-- `p.race` and adds each heading's arrow; Fill(p) reads `p.record`; LayoutTiming / LayoutFlags place
-- them at `y` across `cw` and answer the y beneath. A fight, and every race on WoW Forever (where a
-- race lists as a fight, Review focus 3), has neither section: no heading, arrow or box.
--
-- THE RACE CLOCK (ruling X9). Every mark here is on the race's own clock, from its first hit: the race
-- part's tail, combatEnd, restartedAt and late-cast offsets are seconds after the buzzer, and endedAt
-- is seconds from the first hit, so the buzzer sits at the race length by construction.
--
-- PLAIN NUMBERS ONLY: the stored race part (every value went through NS.Secrets on its way in,
-- modules/RaceRecord.lua Plain). Laid out from the constants here, never from a size read back.

local RD = {}
NS.ResultsRaceDetail = RD

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT

RD.STRIP_GAP = 3        -- between the race segment and the after-the-buzzer one
RD.STRIP_RATIO = 1.2    -- the race segment's share against the after-buzzer one's 1
RD.SPAN_STEP = 6        -- the after-buzzer axis runs to a multiple of this, at least two of them
RD.STRIP_H = 34
RD.LINE_H = 14
RD.LINE_W = 2           -- every line on the strip (grace, late cast, combat end, restart)
RD.LINE_INSET = 4       -- a line's inset from the strip's top and bottom
RD.BAND_INSET = 10      -- the race fill's and the tail band's
RD.FLAG_PADX, RD.FLAG_PADY = 9, 7
RD.FLAG_GAP = 6
RD.FLAG_MAIN_H = 18
RD.FLAG_SUB_H = 12

-- The strip's hues are DATA hues (DPS Race's), the same under every skin.
RD.RACE = NS.HudChart.BUZZER   -- the race segment, and the buzzer line on the chart and the Timeline
RD.CYAN = { 0.3, 0.85, 1.0 }
RD.VIOLET = { 0.78, 0.5, 1.0 }
RD.IGNORED = { 0.55, 0.55, 0.55 }
local SEG = { bg = "ct.slot.empty", border = "divider" }
local CALLOUT = { bg = "ct.callout.bg", border = "ct.callout.border" }

local function Tbl() return NS.ResultsTable end
local function Races() return NS.ResultsRaces end
local function C() return Tbl().COLORS end
local function isRace(record) return NS.RaceRecord.IsRace(record) end

-- ── pure: the timing strip ──────────────────────────────────────────────────────────────────────

local function clamp01(x)
    if type(x) ~= "number" then return nil end
    return math.max(0, math.min(1, x))
end

-- The after-buzzer axis: long enough for every mark, in whole steps, at least two of them. `marks`
-- may hold holes (a mark the race does not have), so it is walked to `n`, never with ipairs.
local function spanFor(marks, n)
    local top = 0
    for i = 1, n do
        local v = marks[i]
        if type(v) == "number" and v > top then top = v end
    end
    local step = RD.SPAN_STEP
    return math.max(2 * step, step * math.ceil(top / step))
end

local function num(v) return type(v) == "number" and v or nil end

-- Each late cast's tick on the after-buzzer axis, the ignore list's marked (drawn gray).
local function lateTicks(m, late)
    local set = NS.LateIgnore.Set()
    for i, cast in ipairs(late) do
        m.late[i] = clamp01((tonumber(cast.t) or 0) / m.span)
        m.lateAt[i] = cast.t
        m.lateIgnored[i] = NS.LateIgnore.IsIgnored(cast.spellID, set) and true or false
    end
end

local function afterBuzzer(m, race, flags)
    local late = type(flags.lateCasts) == "table" and flags.lateCasts or {}
    local grace, tail = tonumber(race.grace) or 0, tonumber(race.tail) or 0
    local restart, combatEnd = num(flags.restartedAt), num(race.combatEnd)
    local marks, n = { grace, tail, combatEnd, restart }, 4
    for _, cast in ipairs(late) do
        n = n + 1
        marks[n] = cast.t
    end
    m.span = spanFor(marks, n)
    m.grace, m.tail = clamp01(grace / m.span), clamp01(tail / m.span)
    m.combatEnd = combatEnd and clamp01(combatEnd / m.span)
    m.restart = restart and clamp01(restart / m.span)
    lateTicks(m, late)
end

--- The strip as fractions of its two segments: the race (first hit to buzzer) and the time after the
--- buzzer (to `span` seconds). An incomplete race fills the race segment to where combat ended and
--- marks it there; it has nothing after a buzzer it never reached. nil for a fight.
--- @return table|nil model  { length, raceFill, endInRace?, span, grace?, tail?, combatEnd?, restart?,
---                            late = {f}, lateAt = {s}, lateIgnored = {bool} }
function RD.Timing(record)
    if not isRace(record) then return nil end
    local race = record.race
    local flags = type(race.flags) == "table" and race.flags or {}
    local length = type(race.length) == "number" and race.length > 0 and race.length or 1
    local m = { length = length, late = {}, lateAt = {}, lateIgnored = {} }
    if race.status ~= "complete" then
        m.raceFill = clamp01((tonumber(race.endedAt) or 0) / length)
        m.endInRace = m.raceFill
        m.span = 2 * RD.SPAN_STEP
        return m
    end
    m.raceFill = 1
    afterBuzzer(m, race, flags)
    return m
end

--- The strip's pixel positions for `width`, from Timing's fractions.
--- @return table { raceW, postW, postX, buzzer, raceFill, endInRace, grace, tailX, tailW, combatEnd,
---                 restart, late = {x}, lateIgnored = {bool} }
function RD.Place(model, width)
    local gap = RD.STRIP_GAP
    -- The 1e-6 keeps a whole share whole under the float division (220 * 1.2 / 2.2 is 120).
    local raceW = math.floor((width - gap) * RD.STRIP_RATIO / (RD.STRIP_RATIO + 1) + 1e-6)
    local postW = width - gap - raceW
    local postX = raceW + gap
    local function post(f) return f and (postX + f * postW) or nil end
    local p = { raceW = raceW, postW = postW, postX = postX, buzzer = raceW, late = {} }
    p.raceFill = model.raceFill * raceW
    p.endInRace = model.endInRace and model.endInRace * raceW
    p.grace = post(model.grace)
    p.tailX, p.tailW = postX, (model.tail or 0) * postW
    p.combatEnd = post(model.combatEnd)
    p.restart = post(model.restart)
    for i, f in ipairs(model.late) do p.late[i] = post(f) end
    p.lateIgnored = model.lateIgnored or {}
    return p
end

--- The line under the strip: the damage tail and the end of combat, or when combat ended.
--- @return string
function RD.TailText(record)
    local race = record.race
    if race.status ~= "complete" then
        return L["Combat ended at %s, before the buzzer."]:format(NS.Format.Length(race.endedAt))
    end
    local s = L["Damage stopped %ss after the buzzer"]:format(NS.Format.Seconds(race.tail))
    if type(race.combatEnd) == "number" then
        s = s .. " \194\183 " .. L["combat ended %ss"]:format(NS.Format.Seconds(race.combatEnd))
    end
    return s
end

-- ── pure: what the flags mean ───────────────────────────────────────────────────────────────────

local STILL_COUNTS = "The race still counts toward bests."

local function spellName(id)
    return NS.HudBreakdown.SpellName(id) or L["Unknown spell"]
end

local function lateLine(race, flag)
    local parts = {}
    for i, cast in ipairs(flag.casts) do
        parts[i] = L["%s started +%.1fs after the buzzer"]:format(tostring(spellName(cast.spellID)), cast.t or 0)
    end
    return L["%s (grace %.1fs)."]:format(table.concat(parts, "; "), race.grace or 0) .. " " .. L[STILL_COUNTS]
end

local function still(text) return function() return L[text] .. " " .. L[STILL_COUNTS] end end

-- What each flag means, under its own line in the box; a flag missing here says it all on its line.
local EXPLAIN = {
    lateCasts = lateLine,
    restarted = still("After the quiet gap past the buzzer: a new pull."),
    reloaded = function() return L[STILL_COUNTS] end,
    sessionFromList = still("The meter session was found by its place in Blizzard's list, not by its ID."),
    sharedSession = still("The pull carried on the meter session that was open before the race was armed, so its score is the session's total less what it held then."),
    incomplete = function() return L["It does not count toward bests."] end,
}

-- The late casts the ignore list leaves uncounted, as one dimmed line of the box: not a flag, but the
-- box keeps it (and so shows with no flag at all), as the undo's place. nil with none.
local function ignoredLine(race)
    local full = NS.RaceScoring.IgnoredText(race, NS.HudBreakdown.SpellName)
    if not full then return nil end
    local _, ignored = NS.RaceScoring.SplitLate(race)
    local parts = {}
    for i, cast in ipairs(ignored) do parts[i] = L["+%.1fs %s"]:format(cast.t or 0, tostring(spellName(cast.spellID))) end
    local n = #ignored
    return { key = "lateIgnored", dim = true, full = full, sub = table.concat(parts, ", "),
             main = n == 1 and L["1 ignored late cast"] or L["%d ignored late casts"]:format(n),
             text = L["On the late-cast ignore list, so no flag. Right-click to count a spell again."] }
end

--- A race's flags with what each means, in RaceScoring's order: { key, main, sub, text, full, dim? }.
--- The ignored late casts follow the counted ones (first when none counts) as one more line,
--- `lateIgnored`, dimmed. Empty for a fight.
--- @return table lines
function RD.FlagLines(record)
    local out = {}
    if not isRace(record) then return out end
    local race = record.race
    for _, flag in ipairs(NS.RaceScoring.Flags(race, NS.HudBreakdown.SpellName)) do
        local explain = EXPLAIN[flag.key]
        out[#out + 1] = { key = flag.key, main = flag.main or flag.text, sub = flag.sub or "",
                          text = explain and explain(race, flag) or "", full = flag.text }
    end
    local ignored = ignoredLine(race)
    if ignored then table.insert(out, (out[1] and out[1].key == "lateCasts") and 2 or 1, ignored) end
    return out
end

--- The detail's Damage and DPS figures and the DPS box's label: a race's score and race DPS ("DPS ·
--- Incomplete" when it ended before its buzzer), else the fight's damage and DPS.
--- @return number|nil damage, number|nil dps, string label
function RD.Figures(record)
    local d = type(record.damage) == "table" and record.damage or {}
    if not isRace(record) then
        return type(d.merged) == "number" and d.merged or nil, type(record.dps) == "number" and record.dps or nil,
            L["DPS"]
    end
    local label = record.race.status == "complete" and L["DPS"] or L["DPS \194\183 Incomplete"]
    local score = Races().Score(record) or (type(d.merged) == "number" and d.merged or nil)
    return score, NS.RaceRecord.Dps(record), label
end

-- ── the late-cast right-click ───────────────────────────────────────────────────────────────────

-- The race's late casts take a menu: Retail, a stored race (never the sample history's), and one
-- with something to offer.
local function offers(record)
    return Races().On() and isRace(record) and not NS.ResultsSource.IsMock() and NS.LateIgnore.Offers(record)
end

--- The row menu's *Ignore for late casts* submenu on `root` (Results.RowMenu), when the race offers it.
--- @return boolean added
function RD.FillRowMenu(root, record)
    if not offers(record) then return false end
    NS.LateIgnore.FillMenu(root:CreateButton(L["Ignore for late casts"]), record)
    return true
end

-- ── the sections ────────────────────────────────────────────────────────────────────────────────

local function mark(parent, color, alpha)
    local t = parent:CreateTexture(nil, "OVERLAY")
    Style.Fill(t, color, alpha or 1)
    t:SetWidth(RD.LINE_W)
    return t
end

local function legendItem(c, color, label)
    local item = { swatch = c:CreateTexture(nil, "ARTWORK"), fs = Style.Text(c, FONT.CAPTION), text = label }
    item.swatch:SetSize(9, 9)
    Style.Fill(item.swatch, color, 0.8)
    item.fs:SetText(label)
    return item
end

-- The legend's labels in build order, and its two rows by index: the bands, then the lines.
RD.LEGEND = { "Race", "Tail (damage still landing)", "Grace", "Late cast", "Combat ended", "Restart" }
RD.LEGEND_ROWS = { { 1, 2 }, { 3, 4, 5, 6 } }

local function buildTiming(p, c, x)
    x.timingTitle = Style.Text(c, FONT.SECTION)
    x.timingTitle:SetText(L["Timing"])
    p:AddHeading("timing", x.timingTitle)
    x.strip = CreateFrame("Frame", nil, c)
    x.strip:SetHeight(RD.STRIP_H)
    x.segA = NS.HudStates.Card(x.strip, SEG)
    x.segB = NS.HudStates.Card(x.strip, SEG)
    -- The marks' own frame above the segments: a child frame draws over its parent's textures.
    x.marks = CreateFrame("Frame", nil, x.strip)
    x.marks:SetAllPoints(x.strip)
    x.marks:SetFrameLevel((x.strip:GetFrameLevel() or 0) + 2)
    local cc = C()
    x.raceFill = mark(x.marks, RD.RACE, 0.5)
    x.tail = mark(x.marks, cc.amber, 0.45)
    x.grace = mark(x.marks, cc.green, 0.8)
    x.combatEnd = mark(x.marks, RD.CYAN)
    x.restart = mark(x.marks, RD.VIOLET)
    x.ticks = {}
    x.axisRace = Style.Text(c, FONT.CAPTION)
    x.axisLeft = Style.Text(c, FONT.CAPTION)
    x.axisMid = Style.Text(c, FONT.CAPTION, nil, "CENTER")
    x.axisRight = Style.Text(c, FONT.CAPTION, nil, "RIGHT")
    x.tailLine = Style.Text(c, FONT.TEXT, cc.text)
    local colors = { RD.RACE, cc.amber, cc.green, cc.red, RD.CYAN, RD.VIOLET }
    x.legend = {}
    for i, label in ipairs(RD.LEGEND) do x.legend[i] = legendItem(c, colors[i], L[label]) end
end

local function wrapped(parent, font, color)
    local fs = Style.Text(parent, font, color)
    fs:SetWordWrap(true)
    fs:SetJustifyV("TOP")
    return fs
end

local function buildFlags(p, c, x)
    x.flagsTitle = Style.Text(c, FONT.SECTION)
    x.flagsTitle:SetText(L["Flags"])
    p:AddHeading("flags", x.flagsTitle)
    x.box = NS.HudStates.Card(c, CALLOUT)
    x.box:EnableMouse(true)
    -- A right-click anywhere on the box opens the race's late-cast menu (never on a sample race).
    x.box:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and p.record and offers(p.record) then NS.LateIgnore.Menu(p.record, self) end
    end)
    x.rows = {}
end

--- Build the race sections' parts into the pane `p` (its content `c`), as `p.race`.
function RD.Build(p, c)
    local x = { lines = {} }
    p.race = x
    buildTiming(p, c, x)
    buildFlags(p, c, x)
    return x
end

-- One flag's three lines in the box, made the first time a race has that many flags.
local function flagRow(x, i)
    local row = x.rows[i]
    if row then return row end
    local main = Style.Tok("ct.callout.text")
    row = { main = wrapped(x.box, FONT.SECTION, main), sub = wrapped(x.box, FONT.CAPTION, C().amber),
            body = wrapped(x.box, FONT.TEXT, main) }
    x.rows[i] = row
    return row
end

local PARTS = { main = "main", sub = "sub", text = "body" }

--- Read `p.record`'s race (nothing for a fight, or on WoW Forever) and paint the flag lines.
function RD.Fill(p)
    local x, record = p.race, p.record
    local on = Races().On() and isRace(record)
    x.model = on and RD.Timing(record) or nil
    x.lines = on and RD.FlagLines(record) or {}
    local main = Style.Tok("ct.callout.text")
    local colors = { main = main, sub = C().amber, text = main }
    for i = 1, math.max(#x.lines, #x.rows) do
        local row, line = flagRow(x, i), x.lines[i] or {}
        for part, field in pairs(PARTS) do
            local fs, s = row[field], line[part] or ""
            fs:SetText(s)
            Style.Paint(fs, line.dim and RD.IGNORED or colors[part])
            fs:SetShown(s ~= "")
        end
    end
end

local function place(region, parent, px, py)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", px, py)
end

local function placeMark(tex, strip, px, inset)
    tex:ClearAllPoints()
    tex:SetShown(px ~= nil)
    if not px then return end
    tex:SetPoint("TOPLEFT", strip, "TOPLEFT", px, -inset)
    tex:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", px, inset)
end

local function layoutMarks(x, pos)
    x.segA:ClearAllPoints()
    x.segA:SetPoint("TOPLEFT", x.strip, "TOPLEFT", 0, 0)
    x.segA:SetSize(pos.raceW, RD.STRIP_H)
    x.segB:ClearAllPoints()
    x.segB:SetPoint("TOPLEFT", x.strip, "TOPLEFT", pos.postX, 0)
    x.segB:SetSize(pos.postW, RD.STRIP_H)
    placeMark(x.raceFill, x.strip, 0, RD.BAND_INSET)
    x.raceFill:SetWidth(math.max(1, pos.raceFill))
    placeMark(x.tail, x.strip, pos.tailW > 0 and pos.tailX or nil, RD.BAND_INSET)
    x.tail:SetWidth(math.max(1, pos.tailW))
    placeMark(x.grace, x.strip, pos.grace, RD.LINE_INSET)
    placeMark(x.combatEnd, x.strip, pos.combatEnd or pos.endInRace, RD.LINE_INSET)
    placeMark(x.restart, x.strip, pos.restart, RD.LINE_INSET)
    for i = 1, math.max(#pos.late, #x.ticks) do
        x.ticks[i] = x.ticks[i] or mark(x.marks, C().red)
        local tick = x.ticks[i]
        if pos.late[i] then Style.Fill(tick, pos.lateIgnored[i] and RD.IGNORED or C().red, 1) end
        placeMark(tick, x.strip, pos.late[i], RD.LINE_INSET)
    end
end

-- The legend in its rows; an item that would run past `cw` wraps onto the next line.
local function layoutLegend(p, x, y, cw)
    local row = 0
    for r, indices in ipairs(RD.LEGEND_ROWS) do
        if r > 1 then row = row + 1 end
        local px = 0
        for _, i in ipairs(indices) do
            local item = x.legend[i]
            local w = 14 + #item.text * 5.5
            if px > 0 and px + w > cw then px, row = 0, row + 1 end
            place(item.swatch, p.content, px, y - row * RD.LINE_H - 2)
            item.fs:ClearAllPoints()
            item.fs:SetPoint("LEFT", item.swatch, "RIGHT", 4, 0)
            px = px + w + 10
        end
    end
    return y - (row + 1) * RD.LINE_H
end

local TIMING_PARTS = { "strip", "axisRace", "axisLeft", "axisMid", "axisRight", "tailLine" }

local function showTiming(x, on)
    for _, key in ipairs(TIMING_PARTS) do x[key]:SetShown(on) end
    for _, item in ipairs(x.legend) do
        item.swatch:SetShown(on)
        item.fs:SetShown(on)
    end
end

local function layoutAxis(p, x, y, model)
    local pos = x.place
    place(x.axisRace, p.content, 0, y)
    x.axisRace:SetText(L["0:00 \226\128\148 race %s \226\128\148 buzzer"]:format(NS.Format.Length(model.length)))
    place(x.axisLeft, p.content, pos.postX, y)
    x.axisLeft:SetText(L["+%ds"]:format(0))
    x.axisMid:ClearAllPoints()
    x.axisMid:SetPoint("TOP", p.content, "TOPLEFT", pos.postX + pos.postW / 2, y)
    x.axisMid:SetText(L["+%ds"]:format(model.span / 2))
    x.axisRight:ClearAllPoints()
    x.axisRight:SetPoint("TOPRIGHT", p.content, "TOPLEFT", pos.postX + pos.postW, y)
    x.axisRight:SetText(L["+%ds"]:format(model.span))
end

--- The Timing section at `y` across `cw`; folded, the heading alone; a fight, nothing.
function RD.LayoutTiming(p, y, cw)
    local x, model = p.race, p.race.model
    local on = model ~= nil
    x.timingTitle:SetShown(on)
    local folded = p:Heading("timing", on)
    showTiming(x, on and not folded)
    if not on then return y end
    y = p:heading(x.timingTitle, nil, y, cw)
    if folded then return y end
    place(x.strip, p.content, 0, y)
    x.strip:SetWidth(cw)
    x.place = RD.Place(model, cw)
    layoutMarks(x, x.place)
    y = y - RD.STRIP_H - 4
    layoutAxis(p, x, y, model)
    y = y - RD.LINE_H - 2
    place(x.tailLine, p.content, 0, y)
    x.tailLine:SetWidth(cw)
    x.tailLine:SetText(RD.TailText(p.record))
    return layoutLegend(p, x, y - RD.LINE_H - 4, cw) - 8
end

-- One line of the box at `dy` under its top, `width` wide: the dy under it (unmoved when empty).
local function placeFlagPart(box, fs, text, dy, width, lineH, charW)
    if text == "" then return dy end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", box, "TOPLEFT", RD.FLAG_PADX, -dy)
    fs:SetWidth(width)
    local n = NS.ResultsDetail.WrappedLines(text, width, charW)
    fs:SetHeight(n * lineH)
    return dy + n * lineH
end

local function layoutFlagRows(x, cw)
    local inner, dy = cw - 2 * RD.FLAG_PADX, RD.FLAG_PADY
    for i, line in ipairs(x.lines) do
        local row = x.rows[i]
        if i > 1 then dy = dy + RD.FLAG_GAP end
        dy = placeFlagPart(x.box, row.main, line.main or "", dy, inner, RD.FLAG_MAIN_H, 8)
        dy = placeFlagPart(x.box, row.sub, line.sub or "", dy, inner, RD.FLAG_SUB_H, 4.8)
        dy = placeFlagPart(x.box, row.body, line.text or "", dy, inner, RD.LINE_H, 5.4)
    end
    return dy + RD.FLAG_PADY - 1
end

--- The Flags section at `y` across `cw`; folded, the heading alone; a race with no flag (or a fight),
--- nothing.
function RD.LayoutFlags(p, y, cw)
    local x = p.race
    local has = #x.lines > 0
    x.flagsTitle:SetShown(has)
    local folded = p:Heading("flags", has)
    x.box:SetShown(has and not folded)
    if not has then return y end
    y = p:heading(x.flagsTitle, nil, y, cw)
    if folded then return y end
    local h = layoutFlagRows(x, cw)
    place(x.box, p.content, 0, y)
    x.box:SetSize(cw, h)
    return y - h - 8
end
