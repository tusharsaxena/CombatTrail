local _, NS = ...
-- modules/Results_Detail.lua — one fight in full (spec §7, mockup §5's right-hand pane): who and
-- against what, where and when; the figures (Damage, DPS, Blizzard's Meter DPS, and the Delta or
-- "Leads by" box); the damage chart while this session holds it; the spell breakdown with each
-- spell's share and the pet's spells marked by the paw; Gear and Talents (modules/Results_Loadout.lua);
-- Usage (modules/Results_Usage.lua); the note; and the buttons Timeline, Compare vs best, Add note,
-- Share and Delete. Placed by the shell (modules/Results.lua) beside the list, or in its place with a
-- Back control. Adapted from DPS Race @045f479 (modules/Results_Detail.lua) without its race: no
-- timing strip, no flags, no late casts; and without its folding sections (spec §7 asks for one fold
-- arrow, the window's, which hides the whole detail).
--
-- PLAIN NUMBERS ONLY. A stored fight went through NS.Secrets on its way in (spec §5), so its figures
-- may be divided and compared here: the shares, the Delta. The chart's columns are the in-session
-- slices (modules/Slices.lua), copied in combat and handed to the chart's StatusBars untouched; the
-- scale is the plain player damage the record holds.
--
-- THE DELTA BOX reads the list's Delta column for the fight (its group under the view's grouping, or
-- the whole view with none) through the shell's `deltaContext` hook (View:DeltaContext); a fight the
-- filters leave out falls back to its board among every fight (Detail.BoardContext). The group's
-- leader shows "Leads by" and its lead over the runner-up; every other fight "Delta" and its gap.
-- The trophy chip beside the name marks a fight that holds the personal best on its board.
--
-- THE SEAMS. Timeline (plan Task 4.3, NS.ResultsTimeline) and Compare vs best (Task 4.4,
-- NS.ResultsCompare) stay grayed until their module exists; Share until modules/Share.lua answers
-- (never on a sample fight); Add note and Delete are the shell's (the note box and the delete's
-- confirmation).
--
-- LAYOUT FROM CONFIG. Every block is placed from the constants here and the widths the shell hands
-- it; nothing reads a size back. The content scrolls (the mouse wheel); the buttons stay put.

local Detail = {}
NS.ResultsDetail = Detail

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT

Detail.PADX = 12
Detail.BUTTON_H = 20
Detail.KPI_H = 46
Detail.KPI_GAP = 6
Detail.ICON = 28
Detail.LINE_H = 14
Detail.CHIP_ICON = 14
-- The buttons along the foot, left to right (Delete at the right edge), and their widths.
Detail.BUTTONS = {
    { key = "timeline", label = "Timeline", width = 70, style = "primary" },
    { key = "compare", label = "Compare vs best", width = 104 },
    { key = "addNote", label = "Add Note", width = 70 },
    { key = "share", label = "Share", width = 58 },
}
Detail.DELETE_W = 60

local DASH = "\226\128\148"
local SEP = " \194\183 "

local function Tbl() return NS.ResultsTable end
local function Fights() return NS.ResultsFights end

-- ── pure ────────────────────────────────────────────────────────────────────────────────────────

local function who(record) return type(record.who) == "table" and record.who or {} end
local function ident(record) return type(record.identity) == "table" and record.identity or {} end

--- The header's meta line (spec §7): "Vorasius · The Voidspire · Heroic · Mythic+ 12 · ilvl 721.4 ·
--- 4:12 · 10 Nov 2026 21:14 · pet Grimfang · build 120105 · v0.1.0", every part the record has.
--- @param record table
--- @return string
function Detail.Meta(record)
    local i, w = ident(record), who(record)
    local parts = { Fights().TargetName(record) }
    if i.instanceName and i.instanceName ~= parts[1] then parts[#parts + 1] = i.instanceName end
    if type(i.difficultyName) == "string" and i.difficultyName ~= "" then parts[#parts + 1] = i.difficultyName end
    parts[#parts + 1] = Fights().TierText(record)
    if type(w.ilvl) == "number" then parts[#parts + 1] = L["ilvl %s"]:format(Tbl().Ilvl(w.ilvl)) end
    parts[#parts + 1] = NS.Format.Length(record.duration)
    parts[#parts + 1] = Tbl().Date(record.t, "%d %b %Y %H:%M")
    if w.petName then parts[#parts + 1] = L["pet %s"]:format(w.petName) end
    if record.build then parts[#parts + 1] = L["build %s"]:format(tostring(record.build)) end
    if record.version then parts[#parts + 1] = "v" .. tostring(record.version) end
    local out = {}
    for k = 1, #parts + 1 do
        local s = parts[k]
        if type(s) == "string" and s ~= "" then out[#out + 1] = s end
    end
    return table.concat(out, SEP)
end

--- The fight's board among `records` as a Delta context (the fallback when the list's filters leave
--- the fight out): the fights on its board (character, spec and board key, modules/Bests.lua).
--- @return table|nil ctx
function Detail.BoardContext(record, records)
    local key = NS.Bests.Key(record)
    if not key then return nil end
    local board = {}
    for _, other in ipairs(records or {}) do
        if type(other) == "table" and NS.Bests.Key(other) == key then board[#board + 1] = other end
    end
    return Fights().Context(board)
end

--- The Delta box: its label, its figure, the figure's color and whether the fight leads its group.
--- The leader reads "Leads by" and its lead over the runner-up (a dash alone in its group); every
--- other fight "Delta" and its gap to the leader.
--- @return string label, string text, table color, boolean leads
function Detail.DeltaBox(record, ctx)
    local C = Tbl().COLORS
    if type(ctx) ~= "table" then return L["Delta"], DASH, C.dim, false end
    if Fights().IsTop(record, ctx) then
        local second = ctx.second and tonumber(ctx.second.dps)
        if not second or second <= 0 then return L["Leads by"], DASH, C.dim, true end
        return L["Leads by"], NS.Format.SignedPct((ctx.top / second - 1) * 100), C.green, true
    end
    local pct = Fights().Delta(record, ctx.top)
    if pct == nil then return L["Delta"], DASH, C.dim, false end
    return L["Delta"], NS.Format.SignedPct(pct), pct < 0 and C.red or C.green, false
end

--- The pet's share of the fight's damage, as a percentage, or nil with no pet damage.
function Detail.PetShare(record)
    local d = type(record.damage) == "table" and record.damage or {}
    local pet, total = tonumber(d.pet), tonumber(d.merged)
    if not pet or pet <= 0 or not total or total <= 0 then return nil end
    return pet / total * 100
end

--- The chart's view for a stored fight (modules/Hud_Chart.lua's OverView over the in-session slices,
--- scaled to the record's plain player damage), or nil when this session holds none.
--- @param record table
--- @return table|nil view
function Detail.ChartView(record)
    if not NS.Slices.Drawable(record) then return nil end
    local d = record.damage
    local player = tonumber(d.player) or tonumber(d.merged)
    local final = { duration = record.duration, player = { total = player } }
    local casts = NS.CastCodec.Decode(record.casts)
    local cooldowns = NS.HudChart.Cooldowns(casts, record.cooldowns)
    return NS.HudChart.OverView({ id = record.id }, nil, final, cooldowns)
end

-- ── the pane ────────────────────────────────────────────────────────────────────────────────────

local Pane = {}
Pane.__index = Pane

-- A hover frame laid over `region` (a text or a texture takes no mouse of its own), its tooltip the
-- lines `lines()` answers at hover time, under it.
local function hoverOver(p, region, lines)
    local f = CreateFrame("Frame", nil, p.content)
    f:SetAllPoints(region)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        local tip = p.record and lines(p.record)
        if not (tip and tip[1] and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(tip[1], Style.Rgb("gtip.title"))
        Style.AddTipLines(GameTooltip, tip, 2)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() Tbl().HideTip() end)
    return f
end

local function kpi(p, label, color, tip)
    local f = NS.HudStates.Card(p.content)
    f:SetHeight(Detail.KPI_H)
    local k = { frame = f, label = Style.Text(f, FONT.CAPTION, nil, "CENTER"),
                value = Style.Text(f, FONT.FIGURE, color, "CENTER") }
    k.label:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -7)
    k.label:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -7)
    k.label:SetText(label)
    k.value:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 5)
    k.value:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 5)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        local lines = p.record and NS.ResultsTips.Detail(tip, p.record, p.deltaCtx)
        if not (lines and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(lines[1], Style.Rgb("gtip.title"))
        Style.AddTipLines(GameTooltip, lines, 2)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() Tbl().HideTip() end)
    return k
end

local function buildHeader(p, c)
    local w, C = p.w, Tbl().COLORS
    w.class = c:CreateTexture(nil, "ARTWORK")
    w.class:SetSize(Detail.ICON, Detail.ICON)
    Style.EdgeClassIcon(w.class)
    w.spec = c:CreateTexture(nil, "ARTWORK")
    w.spec:SetSize(Detail.ICON, Detail.ICON)
    Style.EdgeIcon(w.spec)
    w.name = Style.Text(c, FONT.NAME, C.text)
    w.specName = Style.Text(c, FONT.HEADING, C.dim)
    w.specName:SetPoint("LEFT", w.name, "RIGHT", 6, 0)
    w.best = CreateFrame("Frame", nil, c)
    w.best:SetSize(110, Detail.CHIP_ICON + 4)
    w.bestIcon = w.best:CreateTexture(nil, "ARTWORK")
    w.bestIcon:SetSize(Detail.CHIP_ICON, Detail.CHIP_ICON)
    w.bestIcon:SetPoint("RIGHT", w.best, "RIGHT", 0, 0)
    w.bestIcon:SetTexture(NS.Icon("ph:trophy"))
    Style.Vertex(w.bestIcon, C.gold, 1)
    w.bestText = Style.Text(w.best, FONT.TEXT, C.gold, "RIGHT")
    w.bestText:SetPoint("RIGHT", w.bestIcon, "LEFT", -4, 0)
    w.bestText:SetText(L["Personal best"])
    w.meta = Style.Text(c, FONT.TEXT, C.dim)
    w.meta:SetWordWrap(true)
    w.meta:SetJustifyV("TOP")
    w.damage = kpi(p, L["Damage"], C.text, "damage")
    w.dps = kpi(p, L["DPS"], C.green, "dps")
    w.meterDps = kpi(p, L["Meter DPS"], C.dim, "meterDps")
    w.deltaBox = kpi(p, L["Delta"], C.dim, "delta")
    w.bestHover = hoverOver(p, w.best, function() return { L["Personal best"], L["This fight holds your best DPS on its board."] } end)
    w.metaHover = hoverOver(p, w.meta, function(r) return NS.ResultsTips.Detail("meta", r) end)
end

local function buildChart(p, c)
    local w, C = p.w, Tbl().COLORS
    w.chartTitle = Style.Text(c, FONT.SECTION)
    w.chartTitle:SetText(L["Damage profile"])
    w.chartCaption = Style.Text(c, FONT.CAPTION, nil, "RIGHT")
    w.chart = NS.HudChart.New(c)
    w.chart:SetShown(false)
    w.chartNote = Style.Text(c, FONT.TEXT, C.dim)
    w.chartNote:SetWordWrap(true)
    w.chartNote:SetText(L["Damage chart is only kept for fights recorded this session."])
    w.chartHover = hoverOver(p, w.chartTitle, function(r) return NS.ResultsTips.Detail("chart", r) end)
end

local function buildBreakdown(p, c)
    local w = p.w
    w.spellsTitle = Style.Text(c, FONT.SECTION)
    w.spellsTitle:SetText(L["Spell breakdown"])
    w.petShare = Style.Text(c, FONT.CAPTION, nil, "RIGHT")
    w.listHost = CreateFrame("Frame", nil, c)
    w.list = NS.HudBreakdown.New(w.listHost)
    w.spellsHover = hoverOver(p, w.spellsTitle, function(r) return NS.ResultsTips.Detail("breakdown", r) end)
end

local function buildNote(p, c)
    local w, C = p.w, Tbl().COLORS
    w.noteTitle = Style.Text(c, FONT.SECTION)
    w.noteTitle:SetText(L["Note"])
    w.note = Style.Text(c, FONT.TEXT, C.text)
    w.note:SetWordWrap(true)
    w.note:SetJustifyV("TOP")
end

local BUTTON_TIPS = {
    timeline = { "Timeline", "Every cast of the fight along its length, beside the fight it is compared with." },
    compare = { "Compare vs best", "This fight beside the best on its board, or the runner-up when it is the best." },
    addNote = { "Add Note", "A short note of your own on this fight." },
    share = { "Share", "One line about this fight in a chat channel you pick." },
    delete = { "Delete", "Delete this fight. It asks first." },
}

local function tipOf(key)
    local t = BUTTON_TIPS[key]
    return { L[t[1]], L[t[2]] }
end

local function buildButtons(p)
    local w, f, hooks = p.w, p.frame, p.hooks
    local act = {
        timeline = function() if hooks.timeline then hooks.timeline(p) end end,
        compare = function() if hooks.compare then hooks.compare(p) end end,
        addNote = function() if hooks.note then hooks.note(p.record) end end,
        share = function(b) if hooks.share then hooks.share(p.record, b) end end,
    }
    local x = Detail.PADX
    for _, spec in ipairs(Detail.BUTTONS) do
        local b = Style.Button(f, L[spec.label], function(self) if p.record then act[spec.key](self) end end, spec.style)
        b:SetSize(spec.width, Detail.BUTTON_H)
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 8)
        b.tip = tipOf(spec.key)
        w[spec.key] = b
        x = x + spec.width + 4
    end
    w.delete = Style.Button(f, L["Delete"], function()
        if p.record and hooks.delete then hooks.delete(p.record) end
    end, "danger")
    w.delete:SetSize(Detail.DELETE_W, Detail.BUTTON_H)
    w.delete:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -Detail.PADX, 8)
    w.delete.tip = tipOf("delete")
    w.back = Style.Button(f, L["Back"], function() if hooks.back then hooks.back() end end)
    w.back:SetSize(70, Detail.BUTTON_H)
    w.back:SetPoint("TOPLEFT", f, "TOPLEFT", Detail.PADX, -8)
    w.back.tip = { L["Back"], L["Back to the list of fights."] }
end

--- The detail pane in `parent`.
--- @param parent table
--- @param hooks table  { back(), note(record), share(record, button), delete(record), timeline(pane),
---                       compare(pane), canShare() -> bool, deltaContext(record) -> ctx|nil }
--- @return table pane
function Detail.Build(parent, hooks)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    -- Its own band over the list it sits beside (core/Constants.lua LAYERS), set before any child is
    -- built so every child is born in it.
    frame:SetFrameLevel((parent:GetFrameLevel() or 0) + NS.Constants.LAYERS.LEVEL.DETAIL)
    NS.Skin.Card(frame, { tokens = { bg = "ct.pane.bg", border = "divider" } })
    local p = setmetatable({ frame = frame, hooks = hooks or {}, w = {}, scroll = 0, width = 400, height = 400 }, Pane)
    p.scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    p.content = CreateFrame("Frame", nil, p.scrollFrame)
    p.scrollFrame:SetScrollChild(p.content)
    p.scrollFrame:EnableMouseWheel(true)
    p.scrollFrame:SetScript("OnMouseWheel", function(_, delta) p:Scroll(delta) end)
    p.w.empty = Style.Text(frame, FONT.EMPTY, nil, "CENTER")
    p.w.empty:SetPoint("CENTER", frame, "CENTER", 0, 0)
    p.w.empty:SetText(L["Select a fight to see its detail."])
    local c = p.content
    buildHeader(p, c)
    buildChart(p, c)
    buildBreakdown(p, c)
    NS.ResultsLoadout.Build(p, c)
    NS.ResultsUsage.Build(p, c)
    buildNote(p, c)
    buildButtons(p)
    return p
end

-- ── drawing one fight ───────────────────────────────────────────────────────────────────────────

function Pane:fillHeader(record)
    local w, me = self.w, who(record)
    Tbl().SetClassIcon(w.class, me.class)
    local specName, specIcon = Tbl().SpecInfo(me.specID, me.specName)
    w.spec:SetTexture(specIcon)
    w.spec:SetShown(specIcon ~= nil)
    w.name:SetText(me.name or "?")
    Style.Paint(w.name, Tbl().ClassColor(me.class))
    w.specName:SetText(specName and (SEP:sub(2) .. specName) or "")
    w.best:SetShown(NS.ResultsSource.IsBest(record))
    w.meta:SetText(Detail.Meta(record))
end

function Pane:fillDelta(record)
    local ctx = self.hooks.deltaContext and self.hooks.deltaContext(record)
    self.deltaCtx = ctx or Detail.BoardContext(record, NS.ResultsSource.All())
    local label, text, color = Detail.DeltaBox(record, self.deltaCtx)
    local k = self.w.deltaBox
    k.label:SetText(label)
    k.value:SetText(text)
    Style.Paint(k.value, color)
end

--- Redraw the Delta box for the fight shown: the list's filters or grouping changed.
function Pane:RefreshDelta()
    if self.record then self:fillDelta(self.record) end
end

function Pane:fillFigures(record)
    local w, d = self.w, type(record.damage) == "table" and record.damage or {}
    w.damage.value:SetText(type(d.merged) == "number" and NS.Format.Number(d.merged) or DASH)
    w.dps.value:SetText(type(record.dps) == "number" and NS.Format.Number(record.dps) or DASH)
    w.meterDps.value:SetText(type(record.meterDps) == "number" and NS.Format.Number(record.meterDps) or DASH)
    self:fillDelta(record)
end

function Pane:fillSpells(record)
    local spells = NS.Recorder.Spells(record)
    local total = type(record.damage) == "table" and record.damage.merged or 0
    self.spellCount = self.w.list:ShowFinal(spells, total, #spells)
    local pet = Detail.PetShare(record)
    self.w.petShare:SetText(pet and L["Pet %s"]:format(NS.Format.Pct(pet)) or "")
end

-- The buttons' states for `record`: a seam's button grayed until its module exists.
function Pane:fillButtons(record)
    local w, hooks = self.w, self.hooks
    local TL, CMP = NS.ResultsTimeline, NS.ResultsCompare
    local hasCasts = type(record.casts) == "string" and record.casts ~= ""
    Style.SetEnabled(w.timeline, TL ~= nil and type(TL.Open) == "function" and hasCasts)
    Style.SetEnabled(w.compare, CMP ~= nil and type(CMP.Open) == "function")
    Style.SetEnabled(w.share, hooks.canShare ~= nil and hooks.canShare() == true)
    local hasNote = type(record.note) == "string" and record.note ~= ""
    w.addNote.label:SetText(hasNote and L["Edit Note"] or L["Add Note"])
end

local PARTS = { "timeline", "compare", "addNote", "share", "delete" }

--- Draw `record` (nil clears the pane to its prompt). The same fight drawn again (a saved note, a
--- store change) keeps the scroll; another fight starts at the top.
function Pane:Show(record)
    local same = record ~= nil and record == self.record
    self.record = type(record) == "table" and record or nil
    local has = self.record ~= nil
    self.scrollFrame:SetShown(has)
    self.w.empty:SetShown(not has)
    for _, key in ipairs(PARTS) do self.w[key]:SetShown(has) end
    if not has then return end
    self:fillHeader(record)
    self:fillFigures(record)
    self:fillSpells(record)
    self.chartView = Detail.ChartView(record)
    NS.ResultsLoadout.Fill(self)
    NS.ResultsUsage.Fill(self)
    self.noteText = type(record.note) == "string" and record.note or ""
    self.w.note:SetText(self.noteText)
    self:fillButtons(record)
    if not same then self.scroll = 0 end
    self:Layout(self.width, self.height, self.narrow)
end

-- ── layout ──────────────────────────────────────────────────────────────────────────────────────
-- Each block below places its widgets at `y` (negative, down from the content's top) across `cw`
-- and answers the y beneath it.

local function place(region, parent, x, y)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
end

-- A wrapped line's height, estimated from its length (the pane reads no text size back).
local function wrappedLines(text, width, charW)
    local perLine = math.max(10, math.floor(width / charW))
    local n = 0
    for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do n = n + math.max(1, math.ceil(#line / perLine)) end
    return n
end
Detail.WrappedLines = wrappedLines

function Pane:layoutHeader(y, cw)
    local w, c = self.w, self.content
    place(w.class, c, 0, y)
    place(w.spec, c, Detail.ICON + 4, y)
    local nameX = (w.spec:IsShown() and 2 or 1) * (Detail.ICON + 4) + 4
    w.name:ClearAllPoints()
    w.name:SetPoint("LEFT", c, "TOPLEFT", nameX, y - Detail.ICON / 2)
    w.best:ClearAllPoints()
    w.best:SetPoint("RIGHT", c, "TOPLEFT", cw, y - Detail.ICON / 2)
    y = y - Detail.ICON - 6
    place(w.meta, c, 0, y)
    w.meta:SetWidth(cw)
    local lines = wrappedLines(w.meta:GetText() or "", cw, 5.4)
    w.meta:SetHeight(lines * Detail.LINE_H)
    y = y - lines * Detail.LINE_H - 8
    local box = math.floor((cw - 3 * Detail.KPI_GAP) / 4)
    for i, k in ipairs({ w.damage, w.dps, w.meterDps, w.deltaBox }) do
        place(k.frame, c, (i - 1) * (box + Detail.KPI_GAP), y)
        k.frame:SetWidth(box)
    end
    return y - Detail.KPI_H
end

-- A section's heading at `y` (SECTION_GAP under the block above), its caption at the right edge.
function Pane:heading(title, caption, y, cw)
    y = y - Style.SECTION_GAP
    place(title, self.content, 0, y)
    if caption then
        caption:ClearAllPoints()
        caption:SetPoint("TOPRIGHT", self.content, "TOPLEFT", cw, y - 4)
    end
    return y - Style.SECTION_H
end

-- The chart while this session holds it; the session-only note when it does not.
function Pane:layoutChart(y, cw)
    local w, view = self.w, self.chartView
    y = self:heading(w.chartTitle, w.chartCaption, y, cw)
    w.chartCaption:SetText(view and L["this session only"] or "")
    w.chart:SetShown(view ~= nil)
    w.chartNote:SetShown(view == nil)
    if not view then
        place(w.chartNote, self.content, 0, y)
        w.chartNote:SetWidth(cw)
        return y - Detail.LINE_H - 4
    end
    -- The chart's own heading line is the section's: its plot starts under this heading.
    local h = w.chart:Place(self.content, y + NS.HudChart.HEAD_H, cw)
    w.chart.title:Hide()
    w.chart:Draw(view)
    return y + NS.HudChart.HEAD_H - h - 4
end

function Pane:layoutSpells(y, cw)
    local w = self.w
    y = self:heading(w.spellsTitle, w.petShare, y, cw)
    local n = self.spellCount or 0
    place(w.listHost, self.content, 0, y)
    w.listHost:SetSize(cw, math.max(1, NS.HudBreakdown.Height(n)))
    if n == 0 then return y end
    return y - NS.HudBreakdown.Height(n)
end

function Pane:layoutNote(y, cw)
    local w, note = self.w, self.noteText or ""
    w.noteTitle:SetShown(note ~= "")
    w.note:SetShown(note ~= "")
    if note == "" then return y end
    y = self:heading(w.noteTitle, nil, y, cw)
    place(w.note, self.content, 0, y)
    w.note:SetWidth(cw)
    local lines = wrappedLines(note, cw, 5.4)
    w.note:SetHeight(lines * Detail.LINE_H)
    return y - lines * Detail.LINE_H
end

-- The scroll frame's top: under the Back control when narrow.
local function topOf(narrow)
    return narrow and (Detail.BUTTON_H + 16) or 10
end

--- Lay the pane out for `width` x `height`; `narrow` (the detail in the list's place) shows Back.
function Pane:Layout(width, height, narrow)
    self.width, self.height, self.narrow = width, height, narrow and true or false
    self.w.back:SetShown(self.narrow)
    local top = topOf(self.narrow)
    local cw = math.max(100, width - 2 * Detail.PADX)
    self.viewH = math.max(1, height - top - Detail.BUTTON_H - 18)
    self.scrollFrame:ClearAllPoints()
    self.scrollFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", Detail.PADX, -top)
    self.scrollFrame:SetSize(cw, self.viewH)
    self.content:SetWidth(cw)
    if not self.record then return end
    local y = self:layoutHeader(0, cw)
    y = self:layoutChart(y, cw)
    y = self:layoutSpells(y, cw)
    y = NS.ResultsLoadout.Layout(self, y, cw)
    y = NS.ResultsUsage.Layout(self, y, cw)
    y = self:layoutNote(y, cw)
    self.contentH = -y + 8
    self.content:SetHeight(math.max(1, self.contentH))
    self:Scroll(0)
end

--- While the window is being sized (modules/Sizing.lua): the scroll frame to `width` x `height` and
--- the scroll clamped to it; the content keeps its blocks until the release's Layout.
function Pane:Resize(width, height)
    self.width, self.height = width, height
    self.viewH = math.max(1, height - topOf(self.narrow) - Detail.BUTTON_H - 18)
    self.scrollFrame:SetSize(math.max(100, width - 2 * Detail.PADX), self.viewH)
    self:Scroll(0)
end

--- One mouse-wheel notch (`delta` > 0 scrolls up), clamped to the content.
function Pane:Scroll(delta)
    local top = math.max(0, (self.contentH or 0) - (self.viewH or 0))
    self.scroll = math.max(0, math.min(top, (self.scroll or 0) - (delta or 0) * 3 * NS.HudBreakdown.Pitch()))
    self.scrollFrame:SetVerticalScroll(self.scroll)
end

--- The fight drawn now, or nil.
function Pane:Record()
    return self.record
end
