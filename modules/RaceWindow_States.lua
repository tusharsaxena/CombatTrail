local _, NS = ...
-- modules/RaceWindow_States.lua — the Race window's six bodies (Race mode spec §4.1 and §4.2, plan Task
-- C1): idle (the length presets, Custom, the target card, Your best, Arm Race and why it cannot arm),
-- armed (the length and what starts the clock), running (the race clock, the pace bar against the race
-- board's best and the race's chips), Stop! (the tail, the time in combat, the late casts so far, Stop
-- Now and Cancel), waiting (the same figures and the sticky-combat hint) and the result card (score,
-- race DPS, the verdict and flag chips, the pace bar, New Race / Open / Share / Delete). Ported from DPS
-- Race @f8078c7 (modules/Hud_States.lua) without what the DPS HUD draws for every fight: no live Damage
-- or DPS boxes, no damage chart and no spell rows (spec §4.2, "no duplicated widgets"; the DPS HUD opens
-- for a race whatever its own visibility settings say, ruling X7). modules/RaceWindow.lua owns the shell,
-- picks the body and builds the view; each body is built on first show into its content frame and
-- answers Update(view).
--
-- THE LOOK IS THE DPS HUD'S (spec §4.3 and §8). Every part is drawn with the HUD's own helpers: the
-- boxes are NS.HudStates.Card restyled by the `hud.figures` box swatches, the figures take the
-- `hud.figures` font block, the race clocks the `hud.clock` block (a pair at its size, one clock alone
-- at HudStates.ClockSize's, the elapsed clock green and the time left red), the buttons Style.Button
-- (the picked length in the primary look), the chips the HUD's flat boxes, the pace bar
-- NS.HudChart.NewPace. Each body restyles once per Appearance stamp. The positions are DPS Race's
-- constants, every one config: nothing reads the size of a region a value was written to.
--
-- PLAIN VALUES ONLY, BUT ONE. The clocks, the tail and the time in combat are GetTime() figures, the
-- result's are the stored record's. The running pace bar is handed the live total opaque (the bar's
-- SetValue is the only place it goes), as the DPS HUD's is.
--
-- RETAIL ONLY (clients-§4): nothing here loads on WoW Forever.

if not NS.Compat.ForClient({ "retail" }) then return end

local States = {}
NS.RaceWindowStates = States

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT
local C = NS.HudStates.COLORS
local DASH = "\226\128\148"
local DOT = " \194\183 "

-- ── the stack's constants (DPS Race's) ──────────────────────────────────────────────────────────
-- The idle body, top down, in blocks BLOCK_GAP apart: Race Length (its caption and two rows of
-- presets), Target (its caption and card, and the amber warning under it when one shows), Your best
-- (modules/RaceWindow_Best.lua), then ARM_GAP above Arm Race and the refusal line under it.
local PRESET_TOP, PRESET_H, PRESET_GAP = 14, 20, 6
local BLOCK_GAP, ARM_GAP = 8, 14
local CARD_H = 46
local IDLE_TARGET_Y = PRESET_TOP + 2 * PRESET_H + PRESET_GAP + BLOCK_GAP
local IDLE_CARD_Y = IDLE_TARGET_Y + 14
local IDLE_WARN_Y = IDLE_CARD_Y + CARD_H + 4
local BEST_CAPTION_H, BEST_CARD_H = 14, 38
local BEST_H = BEST_CAPTION_H + BEST_CARD_H
local IDLE_BEST_Y_PLAIN = IDLE_CARD_Y + CARD_H + BLOCK_GAP
local IDLE_BEST_Y_WARNED = IDLE_WARN_Y + 28
local IDLE_ARM_Y_PLAIN = IDLE_BEST_Y_PLAIN + BEST_H + ARM_GAP
local IDLE_ARM_Y, ARM_H, REASON_H = 220, 24, 14
local IDLE_ARM_Y_WARNED = math.min(IDLE_ARM_Y, IDLE_BEST_Y_WARNED + BEST_H + ARM_GAP)
States.BEST_CAPTION_H, States.BEST_CARD_H = BEST_CAPTION_H, BEST_CARD_H

--- The content every body fits in: the idle body's whole stack, its tallest (DPS Race's floor, less
--- the Results button the DPS HUD's chart control replaces). The window's content height.
States.CONTENT_H = IDLE_ARM_Y + ARM_H + 4 + REASON_H

local GAP, ROW_GAP = 8, 4
local KPI_H, KPI_CAPTIONED_H, KPI_PAD, KPI_CAPTION_H = 46, 60, 5, 14
local CHIP_H, CHIP_GAP = 18, 5
local STOP_KPI_Y, STOP_CHIPS_Y, STOP_NOTE_Y = 56, 124, 152
local WAITING_KPI_Y, WAITING_HINT_Y = 40, 108
local HINT_PADX, HINT_PADY, HINT_ADVANCE, HINT_LINE_H = 8, 6, 5.4, 12
local HEAD_GAP, SECTION_H = NS.HudStates.HEAD_GAP, NS.HudStates.SECTION_H
-- The width the bodies lay out at when the shell hands none: 260 less 12 on each side.
local WIDTH = 236
States.WIDTH = WIDTH

-- ── the tooltips' words (DPS Race's Hud_Tips, in Combat Trail's words) ──────────────────────────
-- Fixed words, no figures: a tooltip reads nothing off the screen.
local Tips = {
    lengthCap = { L["Race length"], L["How long the next race runs. Pick a preset or Custom; the choice stays for your next race."] },
    preset = { L["Race length"], L["Race for this long. Your bests are kept per race length, so each length has its own."] },
    custom = { L["Custom"], L["Set a race length of your own. Click, then type it in."] },
    customBox = { L["Custom length"], L["Type a length from 10 seconds to 15 minutes, such as 90, 1:30 or 3m, then press Enter. Escape backs out."] },
    target = { L["Target"], L["The training dummy you have targeted, its dummy kind and its creature ID. The kind decides which board the race counts on."] },
    arm = { L["Arm Race"], L["Get this race ready. The clock starts on your first hit. When you can't arm, the line under this button says why."] },
    armedClock = { L["Race length"], L["The length of this race. It starts counting down when your first hit lands."] },
    armedSub = { L["First hit"], L["Nothing counts until your damage lands, so pre-cast and pre-pot as you would on a pull."] },
    cancel = { L["Cancel"], L["Drop the race. The pull goes on as a plain dummy fight, saved under your recording filters."] },
    clock = { L["Race clock"], L["The race's clock. Race mode > Race clock picks what shows here."] },
    elapsed = { L["Elapsed"], L["How long this race has run."] },
    left = { L["Time left"], L["How long until the buzzer."] },
    pace = { L["Pace bar"], L["Your damage against your best's average on this race board at this point in the race. The tick in the middle is on pace: green is ahead of it, red behind. Your damage and DPS are on the DPS HUD."] },
    resultPace = { L["Pace bar"], L["This race's score against the best you had on this race board before it. The tick in the middle is level with that best: green is ahead of it, red behind."] },
    stop = { L["STOP"], L["The buzzer has gone: stop casting. Damage still landing counts, but a cast that starts after the grace flags the race."] },
    damageStopped = { L["Damage stopped"], L["How long after the buzzer your last damage landed, as far as the race has seen."] },
    combatEnded = { L["Combat ended"], L["Combat ended before the buzzer, this far into the race, so the race is incomplete."] },
    inCombat = { L["In combat"], L["How long you have stayed in combat since the buzzer. The result is read when combat ends."] },
    outOfCombat = { L["Out of combat"], L["Combat is over, so the result can be read."] },
    pending = { L["Result pending"], L["The damage meter can only be read once combat ends, so the result waits for that. Stop Now takes it as soon as it can."] },
    stopNow = { L["Stop Now"], L["Take the result now instead of waiting out the damage tail. Out of combat it is read at once; in combat it is read the moment combat ends, and damage up to then counts."] },
    lateChip = L["Casts that started after the grace. The result flags them unless the spell is on the late-cast ignore list."],
    graceChip = L["How long after the buzzer a cast may start before it is flagged. Set it on the Race mode page."],
    resultScore = { L["Score"], L["This race's damage: the whole fight's, as the damage meter read it after combat."] },
    resultDps = { L["Race DPS"], L["The score over the race length, or over the time raced when the race is incomplete. It is the figure the race board ranks."] },
    newBestChip = L["This race beat your best on this race board, by this much."],
    firstBestChip = L["This race sets the best on this race board: there was no earlier race to beat."],
    behindChip = L["How far this race fell short of your best on this race board."],
    tiedChip = L["This race matched your best on this race board."],
    newRace = { L["New Race"], L["Back to the Arm Race screen at this length. This race stays saved."] },
    open = { L["Open"], L["Open this race in the Results window, with its chart and its spells."] },
    share = { L["Share"], L["Pick a chat channel and post this race's result there."] },
    delete = { L["Delete"], L["Remove this race from your history, after a confirmation. A best it holds goes with it."] },
}
States.TIPS = Tips

local function act(name, ...)
    local W = NS.RaceWindow
    local fn = W and W.Act and W.Act[name]
    if fn then return fn(...) end
end

-- ── widgets ─────────────────────────────────────────────────────────────────────────────────────

-- A tooltip ({ title, line, ... } or one string) shown above any frame, hooked so a hover the frame
-- already has stays.
local function showTip(f)
    local tip = f.tip
    if not (tip and GameTooltip) then return end
    if type(tip) ~= "table" then tip = { tostring(tip) } end
    GameTooltip:SetOwner(f, "ANCHOR_TOP")
    GameTooltip:SetText(tip[1], Style.Rgb("gtip.value"))
    Style.AddTipLines(GameTooltip, tip, 2, Style.Rgb("gtip.title"))
    GameTooltip:Show()
end

local function addTip(frame, tip)
    frame.tip = tip
    if frame.raceTip then return frame end
    frame.raceTip = true
    frame:EnableMouse(true)
    frame:HookScript("OnEnter", showTip)
    frame:HookScript("OnLeave", function(self) if self.tip and GameTooltip then GameTooltip:Hide() end end)
    return frame
end
States.AddTip = addTip

-- A label takes no mouse, so its tooltip sits on an empty frame over it.
local function tipZone(parent, region, tip)
    local zone = CreateFrame("Frame", nil, parent)
    zone:SetAllPoints(region)
    return addTip(zone, tip)
end

-- A label that may wrap (a body's notes run to two lines).
local function text(parent, font, color, justify)
    local fs = Style.Text(parent, font, color, justify)
    fs:SetWordWrap(true)
    return fs
end

-- A section label: the header gold.
local function caption(parent, label, y)
    local fs = Style.Text(parent, FONT.HEADER)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    fs:SetText(label)
    return fs
end

local function button(parent, label, onClick, style, tip)
    local b = Style.Button(parent, label, onClick, style)
    b.tip = tip
    return b
end

-- The picked length draws in the primary look (DPS Race's selected preset).
local function setSelected(b, on)
    Style.SetButtonStyle(b, on and "primary" or "normal")
end

-- The width a plain label takes: its own measurement (it only ever holds plain copy), else an
-- estimate from its length.
local function textWidth(fs, s)
    local w = fs.GetStringWidth and fs:GetStringWidth()
    if type(w) == "number" and w > 0 then return w end
    return #s * 6
end

local function rgba(c)
    local r, g, b, a = Style.Rgba(c)
    return { r = r, g = g, b = b, a = a }
end

-- A figure in a box: a caption over a value in the `hud.figures` face, and with `captioned` a row
-- under the value (k.caption).
local function kpi(body, parent, label, captioned)
    local f = NS.HudStates.Card(parent)
    f:SetHeight(captioned and KPI_CAPTIONED_H or KPI_H)
    local k = { frame = f }
    k.label = Style.Text(f, FONT.CAPTION, nil, "CENTER")
    k.label:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
    k.label:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -7)
    k.label:SetText(label)
    k.value = Style.PlainText(f, FONT.FIGURE, "CENTER")
    local valueY = KPI_PAD + (captioned and KPI_CAPTION_H or 0)
    k.value:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, valueY)
    k.value:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, valueY)
    if captioned then
        k.caption = Style.Text(f, FONT.CAPTION, nil, "CENTER")
        k.caption:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, KPI_PAD)
        k.caption:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, KPI_PAD)
    end
    body.boxes[#body.boxes + 1] = f
    body.figures[#body.figures + 1] = k
    return k
end

local function setKpi(k, value, cap)
    k.value:SetText(value)
    if k.caption then k.caption:SetText(cap or "") end
end

-- Two boxes side by side at `y`, halves by anchor.
local function kpiPair(body, y, leftLabel, rightLabel, captioned)
    local f = body.frame
    local a, b = kpi(body, f, leftLabel, captioned), kpi(body, f, rightLabel, captioned)
    a.frame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
    a.frame:SetPoint("TOPRIGHT", f, "TOP", -4, y)
    b.frame:SetPoint("TOPLEFT", f, "TOP", 4, y)
    b.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
    return a, b
end

-- A race clock or STOP: a label the `hud.clock` block draws, at `scale` of its size, in `color`.
local function clock(body, parent, scale, color)
    local fs = Style.PlainText(parent, FONT.FIGURE, "CENTER")
    body.clocks[#body.clocks + 1] = { fs = fs, scale = scale, color = color }
    return fs
end

-- ── chips ───────────────────────────────────────────────────────────────────────────────────────

local function newChip(parent)
    local f = Style.FlatBox(parent)
    f:SetHeight(CHIP_H)
    f.label = Style.Text(f, FONT.TEXT, C.text, "CENTER")
    f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if not self.tip or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local r, g, b = Style.Rgb("gtip.value")
        GameTooltip:SetText(self.tip, r, g, b, 1, true)
        for _, line in ipairs(self.tipLines or {}) do GameTooltip:AddLine(line[1], line[2], line[3], line[4], true) end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    -- A chip with a menu (the late casts') opens it on a right-click.
    f:SetScript("OnMouseUp", function(self, mouse)
        if mouse == "RightButton" and self.menu then self.menu(self) end
    end)
    return f
end

local Chips = {}
Chips.__index = Chips

local function chips(parent, y)
    return setmetatable({ parent = parent, y = y, pool = NS.Pool.New(), width = WIDTH, shown = {}, lines = 0 }, Chips)
end

--- Lay out `list` ({ text, color, tip, tipLines?, menu? }) left to right from the chips' `y`,
--- wrapping at the body's width.
function Chips:Set(list)
    NS.Pool.ReleaseAll(self.pool)
    self.shown, self.lines = {}, 0
    local x, y, parent = 0, self.y, self.parent
    for i, item in ipairs(list or {}) do
        local chip = NS.Pool.Acquire(self.pool, function() return newChip(parent) end)
        local s, c = item.text, item.color or C.text
        chip.label:SetText(s)
        Style.Paint(chip.label, c)
        Style.TintBox(chip, c, Style.CHIP_EDGE_A)
        -- Set on every acquire, nil included: a pooled chip never keeps the last item's menu.
        chip.tip, chip.text, chip.tipLines, chip.menu = item.tip, s, item.tipLines, item.menu
        local w = math.floor(textWidth(chip.label, s) + 14)
        if x > 0 and x + w > self.width then x, y = 0, y - CHIP_H - CHIP_GAP end
        self.lines = math.floor((self.y - y) / (CHIP_H + CHIP_GAP) + 0.5) + 1
        chip:SetWidth(w)
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        chip:Show()
        x = x + w + CHIP_GAP
        self.shown[i] = chip
    end
end

--- How far below the body's top the chips end, the GAP under them included. Config only.
function Chips:Bottom()
    local n = self.lines
    return -self.y + (n > 0 and n * CHIP_H + (n - 1) * CHIP_GAP + GAP or 0)
end

--- The chip texts drawn now, in order (the suites read these).
function Chips:Texts()
    local out = {}
    for i, chip in ipairs(self.shown) do out[i] = chip.text end
    return out
end

--- The chip items drawn now, in order (the suites read their tips and menus).
function Chips:Items() return self.shown end

-- ── the target card ─────────────────────────────────────────────────────────────────────────────

local BADGE = { bg = "ct.callout.bg", border = "ct.callout.border" }

local function targetCard(body, parent, y)
    local f = NS.HudStates.Card(parent)
    f:SetHeight(CARD_H)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    local card = { frame = f }
    card.name = Style.Text(f, FONT.HEADING)
    card.name:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
    card.name:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -7)
    card.badge = NS.HudStates.Card(f, BADGE)
    card.badge:SetHeight(16)
    card.badge:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 6)
    card.badgeText = Style.Text(card.badge, FONT.TEXT, C.amber, "CENTER")
    card.badgeText:SetPoint("CENTER", card.badge, "CENTER", 0, 0)
    card.id = Style.Text(f, FONT.CAPTION, nil, "RIGHT")
    card.id:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    addTip(f, Tips.target)
    body.boxes[#body.boxes + 1] = f
    return card
end

--- The target card's three lines for `target` (Identity's target snapshot, or nil).
--- @return string name, string badge, string id
function States.TargetText(target)
    target = type(target) == "table" and target or {}
    local Dummies = NS.Dummies
    local kind = Dummies.CategoryOf(target.creatureID)
    local name = target.name or L["No target"]
    local id = type(target.creatureID) == "number" and ("#%d"):format(target.creatureID) or ""
    return name, Dummies.Label(kind), id
end

local function setTarget(card, target)
    local name, badge, id = States.TargetText(target)
    card.name:SetText(name)
    card.badgeText:SetText(badge)
    card.badge:SetWidth(math.floor(textWidth(card.badgeText, badge) + 12))
    card.id:SetText(id)
end

-- ── a body ──────────────────────────────────────────────────────────────────────────────────────

local function newBody(parent, key)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()
    return { key = key, frame = f, w = {}, boxes = {}, figures = {}, clocks = {}, width = WIDTH }
end

-- The body's look, once per Appearance stamp: the boxes' swatches, the figures' block, the clocks'.
local function restyle(body)
    local A = NS.HudAppearance
    if body.stamp == A.stamp then return end
    body.stamp = A.stamp
    for _, f in ipairs(body.boxes) do A.ApplyBox(f) end
    local figures = A.Font("figures")
    for _, k in ipairs(body.figures) do A.ApplyFont(k.value, figures) end
    for _, c in ipairs(body.clocks) do
        local font = A.Font("clock")
        if c.scale then font.size = NS.HudStates.ClockSize(font.size) end
        A.ApplyFont(c.fs, font, c.color and rgba(c.color) or nil)
    end
end
States.Restyle = restyle

--- The equal buttons' width and the first one's left edge for `n` across `width`, ROW_GAP between.
--- @return number each, number x0
function States.RowWidths(width, n)
    local each = math.max(1, math.floor((width - (n - 1) * ROW_GAP) / n))
    local spare = width - n * each - (n - 1) * ROW_GAP
    return each, math.max(0, math.floor(spare / 2))
end

-- `buttons` across the foot of `f`, all the same width.
local function layoutRow(buttons, f, width)
    local each, x = States.RowWidths(width, #buttons)
    for _, b in ipairs(buttons) do
        b:ClearAllPoints()
        b:SetSize(each, Style.BUTTON_H)
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 0)
        x = x + each + ROW_GAP
    end
end

-- A row of equal buttons across the foot of the body: { label, act, style, tip }.
local function footerButtons(body, specs)
    local out = {}
    for i, spec in ipairs(specs) do
        out[i] = button(body.frame, spec[1], function() act(spec[2]) end, spec[3], spec.tip)
    end
    body.footer = out
    layoutRow(out, body.frame, body.width)
    return out
end

local function wideButton(body, label, name, style, tip)
    local b = button(body.frame, label, function() act(name) end, style, tip)
    b:SetPoint("BOTTOMLEFT", body.frame, "BOTTOMLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", body.frame, "BOTTOMRIGHT", 0, 0)
    return b
end

local Builders = {}

-- ── IDLE ────────────────────────────────────────────────────────────────────────────────────────

local function buildPresets(body)
    local f, w = body.frame, body.w
    w.presets = {}
    for i, n in ipairs(NS.Race.LENGTHS) do
        w.presets[i] = button(f, NS.Format.Length(n), function() act("pickLength", n) end, nil,
            { NS.Format.Length(n), Tips.preset[2] })
        w.presets[i].length = n
    end
    w.custom = button(f, L["Custom"], function() act("openCustom") end, nil, Tips.custom)
    w.customBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    w.customBox:SetAutoFocus(false)
    w.customBox:SetFontObject(FONT.TEXT)
    NS.Skin.EditBox(w.customBox, { padInput = false })
    w.customBox:SetJustifyH("CENTER")
    w.customBox:SetMaxLetters(6)
    w.customBox:SetScript("OnEnterPressed", function(self) act("customLength", self:GetText()) end)
    w.customBox:SetScript("OnEscapePressed", function() act("closeCustom") end)
    addTip(w.customBox, Tips.customBox)
    w.customBox:Hide()
end

-- The presets in a 3-column grid, Custom in the sixth cell, at the body's width.
local function layoutPresets(body)
    local cell = math.floor((body.width - 2 * PRESET_GAP) / 3)
    local w = body.w
    local all = { w.presets[1], w.presets[2], w.presets[3], w.presets[4], w.presets[5], w.custom }
    for i, b in ipairs(all) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        b:ClearAllPoints()
        b:SetSize(cell, PRESET_H)
        b:SetPoint("TOPLEFT", body.frame, "TOPLEFT", col * (cell + PRESET_GAP), -PRESET_TOP - row * (PRESET_H + PRESET_GAP))
    end
    w.customBox:ClearAllPoints()
    w.customBox:SetAllPoints(w.custom)
end

-- Your best and Arm Race step down under the amber warning and back up without one.
local function placeArm(body, warned)
    if body.warned == warned then return end
    body.warned = warned
    local w, f = body.w, body.frame
    NS.RaceWindowBest.Place(w.best, f, -(warned and IDLE_BEST_Y_WARNED or IDLE_BEST_Y_PLAIN))
    local y = warned and IDLE_ARM_Y_WARNED or IDLE_ARM_Y_PLAIN
    w.arm:ClearAllPoints()
    w.arm:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
    w.arm:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
end

local function updatePresets(w, v)
    local isPreset = false
    for _, b in ipairs(w.presets) do
        setSelected(b, b.length == v.length)
        isPreset = isPreset or b.length == v.length
    end
    setSelected(w.custom, not isPreset)
    w.custom.label:SetText(isPreset and L["Custom"] or NS.Format.Length(v.length))
    w.customBox:SetShown(v.editing == true)
    w.custom:SetShown(v.editing ~= true)
end

function Builders.idle(parent)
    local body = newBody(parent, "idle")
    local f, w = body.frame, body.w
    w.lengthCap = caption(f, L["Race length"], 0)
    w.lengthTip = tipZone(f, w.lengthCap, Tips.lengthCap)
    buildPresets(body)
    w.targetCap = caption(f, L["Target"], -IDLE_TARGET_Y)
    w.card = targetCard(body, f, -IDLE_CARD_Y)
    w.warn = text(f, FONT.TEXT, C.amber)
    w.warn:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -IDLE_WARN_Y)
    w.warn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -IDLE_WARN_Y)
    w.best = NS.RaceWindowBest.Build(body, f, -IDLE_BEST_Y_PLAIN)
    w.arm = button(f, L["Arm Race"], function() act("arm") end, "primary", Tips.arm)
    w.arm:SetHeight(ARM_H)
    w.arm.label:SetFontObject(FONT.TITLE)
    w.reason = text(f, FONT.TEXT, C.amber, "CENTER")
    w.reason:SetPoint("TOPLEFT", w.arm, "BOTTOMLEFT", 0, -4)
    w.reason:SetPoint("TOPRIGHT", w.arm, "BOTTOMRIGHT", 0, -4)
    placeArm(body, false)
    layoutPresets(body)

    function body.Update(self, v)
        restyle(self)
        updatePresets(self.w, v)
        setTarget(self.w.card, v.target)
        self.w.warn:SetText(v.warning or "")
        placeArm(self, v.warning ~= nil)
        NS.RaceWindowBest.Update(self.w.best, v.best)
        Style.SetEnabled(self.w.arm, v.blocker == nil)
        self.w.reason:SetText(v.blocker and NS.RaceVerb.ArmRefusal(v.blocker, v.detail) or "")
    end
    return body
end

-- ── ARMED ───────────────────────────────────────────────────────────────────────────────────────

function Builders.armed(parent)
    local body = newBody(parent, "armed")
    local f, w = body.frame, body.w
    w.clock = clock(body, f, true, C.text)
    w.clock:SetPoint("TOP", f, "TOP", 0, -4)
    w.clockTip = tipZone(f, w.clock, Tips.armedClock)
    w.sub = Style.Text(f, FONT.CAPTION, nil, "CENTER")
    w.sub:SetPoint("TOP", f, "TOP", 0, -52)
    w.sub:SetText(L["First hit starts the clock"])
    w.subTip = tipZone(f, w.sub, Tips.armedSub)
    w.card = targetCard(body, f, -74)
    w.note = text(f, FONT.TEXT, C.dim)
    w.note:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -128)
    w.note:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -128)
    w.note:SetText(L["Pre-cast and pre-pot as you would on a pull. The clock starts when damage lands, not when you press the button."])
    w.cancel = wideButton(body, L["Cancel"], "cancel", nil, Tips.cancel)
    function body.Update(self, v)
        restyle(self)
        self.w.clock:SetText(NS.Format.Clock(v.length or 0))
        setTarget(self.w.card, v.target)
    end
    return body
end

-- ── RUNNING ─────────────────────────────────────────────────────────────────────────────────────

local PAIR = { "elapsed", "left", "elapsedCap", "leftCap", "elapsedTip", "leftTip" }

-- The race clock (`race.clock`): "left" or "elapsed" is one large clock; anything else is the pair.
local function setClocks(w, v)
    local mode = v.clockMode
    local both = mode ~= "left" and mode ~= "elapsed"
    for _, key in ipairs(PAIR) do w[key]:SetShown(both) end
    w.single:SetShown(not both and mode == "left")
    w.singleElapsed:SetShown(not both and mode == "elapsed")
    w.clockTip:SetShown(not both)
    w.clockTip.tip = mode == "elapsed" and Tips.elapsed or Tips.left
    w.elapsed:SetText(NS.Format.Clock(v.elapsed or 0))
    w.left:SetText(NS.Format.Clock(v.timeLeft or 0))
    w.single:SetText(NS.Format.Clock(v.timeLeft or 0))
    w.singleElapsed:SetText(NS.Format.Clock(v.elapsed or 0))
end

--- The top the running body's stack starts at for the clock mode: the pair's line and caption, or one
--- large clock. Config only (the `hud.clock` block's size).
--- @param mode string|nil  `race.clock`
--- @return number
function States.RunningTop(mode)
    local size = NS.HudAppearance.Font("clock").size
    if mode == "left" or mode == "elapsed" then return 12 + NS.HudStates.ClockSize(size) end
    return 26 + size
end

local function buildClocks(body)
    local f, w = body.frame, body.w
    w.single = clock(body, f, true, C.red)
    w.single:SetPoint("TOP", f, "TOP", 0, -4)
    w.singleElapsed = clock(body, f, true, C.green)
    w.singleElapsed:SetPoint("TOP", f, "TOP", 0, -4)
    w.clockTip = tipZone(f, w.single, Tips.left)
    -- The pair: elapsed (green) in the left half, time left (red) in the right, a caption under each.
    w.elapsed = clock(body, f, false, C.green)
    w.elapsed:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -6)
    w.elapsed:SetPoint("TOPRIGHT", f, "TOP", -4, -6)
    w.left = clock(body, f, false, C.red)
    w.left:SetPoint("TOPLEFT", f, "TOP", 4, -6)
    w.left:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -6)
    w.elapsedCap = Style.Text(f, FONT.CAPTION, nil, "CENTER")
    w.elapsedCap:SetPoint("TOP", w.elapsed, "BOTTOM", 0, -3)
    w.elapsedCap:SetText(L["Elapsed"])
    w.leftCap = Style.Text(f, FONT.CAPTION, nil, "CENTER")
    w.leftCap:SetPoint("TOP", w.left, "BOTTOM", 0, -3)
    w.leftCap:SetText(L["Left"])
    w.elapsedTip = tipZone(f, w.elapsed, Tips.elapsed)
    w.leftTip = tipZone(f, w.left, Tips.left)
end

-- The pace section at `top`: its heading, the bar under it (none without a best), then the chips.
local function placePace(body, v, top)
    local w, f = body.w, body.frame
    local y = top + HEAD_GAP
    w.paceTitle:ClearAllPoints()
    w.paceTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
    w.paceNote:ClearAllPoints()
    w.paceNote:SetPoint("BOTTOMRIGHT", w.paceTitle, "BOTTOMLEFT", body.width, 0)
    local pv = v.pace
    w.pace:SetShown(pv ~= nil)
    w.paceNote:SetText(pv and L["vs best pace"] or (v.paceWhy or ""))
    y = y + SECTION_H
    if pv then
        w.pace:Place(f, -y, body.width)
        w.pace:Set(pv.lo, pv.hi, pv.total)
        y = y + NS.HudChart.PACE_H
    end
    return y + GAP
end

function Builders.running(parent)
    local body = newBody(parent, "running")
    local f, w = body.frame, body.w
    buildClocks(body)
    w.paceTitle = Style.Text(f, FONT.SECTION)
    w.paceTitle:SetText(L["Pace"])
    w.paceNote = Style.Text(f, FONT.CAPTION, nil, "RIGHT")
    w.pace = NS.HudChart.NewPace(f)
    addTip(w.pace.over, Tips.pace)
    w.chips = chips(f, 0)
    w.cancel = wideButton(body, L["Cancel"], "cancel", nil, Tips.cancel)
    function body.Update(self, v)
        restyle(self)
        setClocks(self.w, v)
        local y = placePace(self, v, States.RunningTop(v.clockMode))
        self.w.chips.y = -y
        self.w.chips.width = self.width
        self.w.chips:Set(v.chips)
    end
    return body
end

-- ── STOP! and WAITING ───────────────────────────────────────────────────────────────────────────

-- The two figures both bodies share, each with its caption row: the tail (or the time in combat at
-- an early end) and the time in combat since the buzzer (or a dash once combat is over). Plain
-- GetTime() figures, the unit joined to the figure's string.
local function setStopFigures(w, v)
    w.tail.frame.tip = v.endedEarly and Tips.combatEnded or Tips.damageStopped
    w.combat.frame.tip = v.inCombat and Tips.inCombat or Tips.outOfCombat
    if v.endedEarly then
        w.tail.label:SetText(L["Combat ended"])
        setKpi(w.tail, NS.Format.Length(v.endedAt or 0), L["into the race"])
    else
        w.tail.label:SetText(L["Damage stopped"])
        setKpi(w.tail, NS.Format.Seconds(v.tail) .. L["s"], L["after the buzzer"])
    end
    if v.inCombat then
        w.combat.label:SetText(L["In combat"])
        setKpi(w.combat, NS.Format.Seconds(v.sinceBuzzer or 0) .. L["s"], L["since the buzzer"])
    else
        w.combat.label:SetText(L["Out of combat"])
        setKpi(w.combat, DASH, L["combat ended"])
    end
end

local function stopButtons(body)
    local links = footerButtons(body, {
        { L["Stop Now"], "stopNow", "primary", tip = Tips.stopNow },
        { L["Cancel"], "cancel", "danger", tip = Tips.cancel },
    })
    body.w.stopNow, body.w.cancel = links[1], links[2]
end

local function figurePair(body, y)
    local w = body.w
    w.tail, w.combat = kpiPair(body, y, L["Damage stopped"], L["In combat"], true)
    addTip(w.tail.frame, Tips.damageStopped)
    addTip(w.combat.frame, Tips.inCombat)
end

--- How many of the late casts so far count (the ignore list's are left out) and the first one's offset.
--- @return number n, number first
function States.CountedLate(list)
    local LI = NS.LateIgnore
    local set, n, first = LI.Set(), 0, nil
    for _, cast in ipairs(type(list) == "table" and list or {}) do
        if not LI.IsIgnored(cast.spellID, set) then
            n = n + 1
            first = first or cast.t
        end
    end
    return n, first or 0
end

--- The Stop! body's chips: the late casts so far (when any count) and the grace.
--- @return table list
function States.StopChips(v)
    local late, first = States.CountedLate(v.lateCasts)
    local list = {}
    if late == 1 then
        list[1] = { text = L["1 late cast \194\183 +%.1fs"]:format(first), color = C.amber, tip = Tips.lateChip }
    elseif late > 1 then
        list[1] = { text = L["%d late casts \194\183 +%.1fs"]:format(late, first), color = C.amber, tip = Tips.lateChip }
    end
    list[#list + 1] = { text = L["Grace %.1fs"]:format(v.grace or 0), color = C.info, tip = Tips.graceChip }
    return list
end

function Builders.stop(parent)
    local body = newBody(parent, "stop")
    local f, w = body.frame, body.w
    w.big = clock(body, f, true, C.red)
    w.big:SetPoint("TOP", f, "TOP", 0, -2)
    w.big:SetText(L["STOP"])
    w.bigTip = tipZone(f, w.big, Tips.stop)
    figurePair(body, -STOP_KPI_Y)
    w.chips = chips(f, -STOP_CHIPS_Y)
    w.note = text(f, FONT.TEXT, C.dim)
    w.note:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -STOP_NOTE_Y)
    w.note:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -STOP_NOTE_Y)
    stopButtons(body)
    function body.Update(self, v)
        restyle(self)
        setStopFigures(self.w, v)
        Style.SetEnabled(self.w.stopNow, v.stopNow ~= true)
        -- Redrawn while combat may hold for minutes: the chips and the note only when they change.
        local late, first = States.CountedLate(v.lateCasts)
        local key = ("%d|%.1f|%.1f"):format(late, first, v.grace or 0)
        if key == self.shownKey then return end
        self.shownKey = key
        self.w.chips.width = self.width
        self.w.chips:Set(States.StopChips(v))
        self.w.note:SetText(L["Damage still landing (DoTs, travel time) counts. Casts that start more than %.1fs after the buzzer are flagged on the result."]:format(v.grace or 0))
    end
    return body
end

--- How many lines `s` wraps to in `width` pixels at HINT_ADVANCE a character (an estimate, never a
--- measure: a greedy word wrap).
--- @return number
function States.HintLines(s, width)
    local perLine = math.max(1, math.floor(width / HINT_ADVANCE))
    local lines, len = 1, 0
    for word in tostring(s):gmatch("%S+") do
        local n = #word
        if len == 0 then
            len = n
        elseif len + 1 + n <= perLine then
            len = len + 1 + n
        else
            lines, len = lines + 1, n
        end
    end
    return lines
end

--- The hint box's height for `s` across a body `width` wide.
--- @return number
function States.HintHeight(s, width)
    return States.HintLines(s, width - 2 * HINT_PADX) * HINT_LINE_H + 2 * HINT_PADY
end

local function waitingTitle(v)
    if not v.inCombat then return L["Reading the result"] end
    if v.stopNow then return L["Reading when combat ends"] end
    return L["Waiting for combat to end"]
end

function Builders.waiting(parent)
    local body = newBody(parent, "waiting")
    local f, w = body.frame, body.w
    w.title = Style.Text(f, FONT.TITLE, nil, "CENTER")
    w.title:SetPoint("TOP", f, "TOP", 0, -10)
    w.titleTip = tipZone(f, w.title, Tips.pending)
    figurePair(body, -WAITING_KPI_Y)
    w.hint = NS.HudStates.Card(f, { bg = "ct.callout.bg", border = "ct.callout.border" })
    w.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -WAITING_HINT_Y)
    w.hint:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -WAITING_HINT_Y)
    w.hintText = text(w.hint, FONT.TEXT, Style.Tok("ct.callout.text"))
    w.hintText:SetPoint("TOPLEFT", w.hint, "TOPLEFT", HINT_PADX, -HINT_PADY)
    w.hintText:SetPoint("TOPRIGHT", w.hint, "TOPRIGHT", -HINT_PADX, -HINT_PADY)
    w.hintText:SetJustifyV("TOP")
    stopButtons(body)
    function body.Update(self, v)
        restyle(self)
        self.w.title:SetText(waitingTitle(v))
        setStopFigures(self.w, v)
        Style.SetEnabled(self.w.stopNow, v.stopNow ~= true)
        self.w.hint:SetShown(v.hint ~= nil)
        self.w.hintText:SetText(v.hint or "")
        if v.hint ~= self.hintShown then
            self.hintShown = v.hint
            self.w.hint:SetHeight(States.HintHeight(v.hint or "", self.width))
        end
    end
    return body
end

-- ── RESULT ──────────────────────────────────────────────────────────────────────────────────────

-- A flag's short chip label (the full text is its tooltip).
local FLAG_CHIP = {
    lateCasts = function(_, flag) return flag.count == 1 and L["1 late cast"] or L["%d late casts"]:format(flag.count) end,
    restarted = function(race) return L["Restarted +%.1fs"]:format(race.flags.restartedAt) end,
    reloaded = function() return L["Reloaded"] end,
    sessionFromList = function() return L["Session by list"] end,
    sharedSession = function() return L["Shared session"] end,
    incomplete = function(race)
        if race.flags.died then return L["Incomplete: died"] end
        return L["Incomplete (combat ended at %s)"]:format(NS.Format.Length(race.endedAt or 0))
    end,
    lost = function() return L["Lost"] end,
    died = function() return L["Died"] end,
}

--- A race part's flags as chips: { key, text = the short label, tip = the full text }, in
--- RaceScoring.Flags' order (the new-best toast reads them too, Task C2).
--- @param race table
--- @return table chips
function States.FlagChips(race)
    local list = {}
    if type(race) ~= "table" then return list end
    if type(race.flags) ~= "table" then race = { status = race.status, flags = {} } end
    for _, flag in ipairs(NS.RaceScoring.Flags(race, NS.HudBreakdown.SpellName)) do
        local skip = flag.key == "died" and race.status == "incomplete"
        local short = FLAG_CHIP[flag.key]
        if short and not skip then list[#list + 1] = { key = flag.key, text = short(race, flag), tip = flag.text } end
    end
    return list
end

--- The amber the flag chips draw in.
States.FLAG_COLOR = C.amber

-- The late casts' right-click and tooltip lines (none on a sample).
local function lateExtras(v)
    local LI, record, lines = NS.LateIgnore, v.record, {}
    local menu = record and not record.sample and LI.Offers(record) and function(owner) LI.Menu(record, owner) end or nil
    local ignored = NS.RaceScoring.IgnoredText(v.race, NS.HudBreakdown.SpellName)
    if ignored then lines[#lines + 1] = { ignored, Style.Rgb(C.dim) } end
    if menu then lines[#lines + 1] = { L["Right-click to ignore a spell for late casts, or count it again."], Style.Rgb(C.dim) } end
    return menu, lines[1] and lines or nil
end

-- Every late cast ignored: no flag, a gray "N ignored" chip in its place that keeps the tooltip and
-- the undo.
local function ignoredChip(race, menu, lines)
    local _, ignored = NS.RaceScoring.SplitLate(race)
    if #ignored == 0 then return nil end
    return { text = L["%d ignored"]:format(#ignored), color = C.dim, menu = menu, tipLines = lines,
             tip = L["Late casts on the ignore list: they flag nothing."] }
end

-- The verdict against the race board's best before the race (Bests.Delta). A new best with no figure
-- had nothing to beat; a delta of 0 is a tie.
local function verdictChip(v)
    if v.isNew then
        if v.delta then return { text = L["New best +%.1f%%"]:format(v.delta), color = C.green, tip = Tips.newBestChip } end
        return { text = L["New best"], color = C.green, tip = Tips.firstBestChip }
    end
    if not v.delta then return nil end
    local tied = v.delta == 0
    return { text = L["%+.1f%% vs best"]:format(v.delta), color = tied and C.dim or C.red,
             tip = tied and Tips.tiedChip or Tips.behindChip }
end

--- The result card's chips: the verdict, the ignored casts, the flags, the race's time.
--- @param v table  the view (race, record, isNew, delta)
--- @return table list
function States.ResultChips(v)
    local race, list = v.race or {}, {}
    list[1] = verdictChip(v)
    local menu, lines = lateExtras(v)
    local flags = States.FlagChips(race)
    if not (flags[1] and flags[1].key == "lateCasts") then list[#list + 1] = ignoredChip(race, menu, lines) end
    for _, chip in ipairs(flags) do
        local late = chip.key == "lateCasts"
        list[#list + 1] = { text = chip.text, color = C.amber, tip = chip.tip,
                            menu = late and menu or nil, tipLines = late and lines or nil }
    end
    if race.status ~= "lost" and type(race.score) == "number" then
        list[#list + 1] = { text = L["Time %s"]:format(NS.Format.RaceTime(race)), color = C.info,
                            tip = L["The race length, then how long your damage kept landing after the buzzer (DoTs, travel time). An incomplete race shows its time in combat against the length."] }
    end
    return list
end

local function resultFigures(w, v)
    local race = v.race or {}
    local lost = race.status == "lost" or type(race.score) ~= "number"
    setKpi(w.score, lost and DASH or NS.Format.Number(race.score))
    setKpi(w.dps, lost and DASH or NS.Format.Number(v.dps or 0))
    return lost
end

-- The pace section under the chips: its heading and the bar, the score against the best before.
local function placeResultPace(body, v, top)
    local w, f = body.w, body.frame
    local pv = v.pace
    w.paceTitle:SetShown(pv ~= nil)
    w.pace:SetShown(pv ~= nil)
    if not pv then return end
    local y = top + HEAD_GAP
    w.paceTitle:ClearAllPoints()
    w.paceTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
    w.pace:Place(f, -(y + SECTION_H), body.width)
    w.pace:Set(pv.lo, pv.hi, pv.total)
end

function Builders.result(parent)
    local body = newBody(parent, "result")
    local f, w = body.frame, body.w
    w.score, w.dps = kpiPair(body, 0, L["Score"], L["Race DPS"], false)
    addTip(w.score.frame, Tips.resultScore)
    addTip(w.dps.frame, Tips.resultDps)
    w.chips = chips(f, -KPI_H - GAP)
    w.lost = Style.Text(f, FONT.TEXT, C.red)
    w.paceTitle = Style.Text(f, FONT.SECTION)
    w.paceTitle:SetText(L["Pace"])
    w.pace = NS.HudChart.NewPace(f)
    addTip(w.pace.over, Tips.resultPace)
    local links = footerButtons(body, {
        { L["New Race"], "newRace", "primary", tip = Tips.newRace },
        { L["Open"], "open", tip = Tips.open },
        { L["Share"], "share", tip = Tips.share },
        { L["Delete"], "delete", "danger", tip = Tips.delete },
    })
    w.newRace, w.open, w.share, w.delete = links[1], links[2], links[3], links[4]
    function body.Update(self, v)
        restyle(self)
        local ww = self.w
        ww.chips.width = self.width
        ww.chips:Set(States.ResultChips(v))
        local lost = resultFigures(ww, v)
        local top = ww.chips:Bottom()
        ww.lost:ClearAllPoints()
        ww.lost:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -top)
        ww.lost:SetText(lost and L["Couldn't read the result"] or "")
        placeResultPace(self, v, top)
        Style.SetEnabled(ww.open, v.record ~= nil)
        Style.SetEnabled(ww.share, v.canShare == true)
        Style.SetEnabled(ww.delete, v.record ~= nil)
    end
    return body
end

--- The running body's chips: the race's dummy kind and length, and a flag already known (a shared
--- session: its live total holds damage from before the arm, so it is never paced).
--- @param race table
--- @return table list
function States.RunningChips(race)
    race = type(race) == "table" and race or {}
    local list = { { text = NS.Dummies.Label(race.kind) .. DOT .. NS.Format.Length(race.length), color = C.info,
                     tip = L["The race board this race counts on: the dummy's kind and the race length, for this character and spec."] } }
    local flags = type(race.flags) == "table" and race.flags or {}
    if flags.sharedSession then
        list[#list + 1] = { text = L["Shared session"], color = C.amber,
                            tip = L["Shared session: the pull carried on a meter session from before the arm"] }
    end
    return list
end

--- Build one body into `parent`.
--- @param key string  idle | armed | running | stop | waiting | result
--- @return table|nil body  { key, frame, w, width, Update(view) }
function States.Build(key, parent)
    local builder = Builders[key]
    if not builder then return nil end
    return builder(parent)
end
