local _, NS = ...
-- modules/Hud_States.lua — the DPS HUD's two bodies (spec §6, mockup §2): `live` (the fight in
-- progress; with nothing to pace against the HUD's state reads noBest) and `over` (the fight-over
-- card). Each is built on first show into the HUD's content frame and answers Update(view), and the
-- live body SetLive(live); modules/Hud.lua owns the shell, decides which body shows and builds the
-- view. Adapted from DPS Race @045f479 (modules/Hud_States.lua) without its race: no idle, armed,
-- Stop! or waiting body, no race length, no late-cast flags, no buttons in the bodies (the title
-- bar's controls are the HUD's acts).
--
-- THE STACK, top down, each part switched by its `hud.layout.*` key: the clock, the target line, the
-- Damage and DPS boxes, and on the over card the chips. Every position is a constant offset worked
-- out from the parts shown; Update answers the stack's height (body.height), which the shell sizes
-- the window from. The pace bar, the damage chart and the spell rows (plan Task 3.2) stack under it
-- from body.height down. No body reads the size or position of anything that has displayed a meter
-- value; the chips measure their own text (GetStringWidth on a label that only ever holds plain
-- copy), never a value.
--
-- SECRETS. The live body hands each opaque meter value to NS.Format.Number and the result straight
-- to SetText: no concatenation, no comparison but the nil test spec §3 allows. The pet's figure is a
-- label and a value side by side, never one joined string. The over card's values are plain (the
-- after-combat read, or the stored record).

local States = {}
NS.HudStates = States

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT
local Secrets = NS.Secrets

-- The HUD's palette, every entry a live skin color (modules/Style.lua): the body text and its dim
-- gray, the header gold, and the meaning hues (core/SkinSetup.lua's owner tokens).
local C = {
    text  = Style.Tok("ct.text"),
    dim   = Style.Tok("ct.dim"),
    gold  = Style.GOLD,
    amber = Style.Tok("ct.caution"),
    red   = Style.Tok("sem.statusBad"),
    green = Style.Tok("ct.ahead"),
    info  = Style.Tok("ct.info"),
}
States.COLORS = C

-- The flat box a figure stands in: a faint wash under a faint edge (the skin's Card, D-3).
local BOX = { bg = "list.boxDim", border = "ct.box.border" }

-- The clock (mockup: 44px, centered) and the stack's pitches.
local CLOCK_SIZE = 40
local CLOCK_H = CLOCK_SIZE + 10
local TARGET_H = 18
local KPI_HEIGHT = 46
local KPI_PAD, KPI_CAPTION_H = 5, 14
local GAP = 8
local CHIP_HEIGHT, CHIP_GAP = 18, 5
States.CLOCK_SIZE, States.KPI_HEIGHT, States.GAP = CLOCK_SIZE, KPI_HEIGHT, GAP
local DASH = "\226\128\148"   -- "no figure"

-- ── widgets ─────────────────────────────────────────────────────────────────────────────────────

-- The fight clock: the one label kept in its own monospace face and size, the skin's `font.mono`
-- (Ka0s Default's JetBrains Mono), drawn again on a skin change. HUD Appearance (plan Task 3.2)
-- takes its face, size and color over.
local bigTexts = setmetatable({}, { __mode = "k" })   -- fs -> its size

local function monoFace()
    local name = NS.Skin.Token("font.mono")
    return (type(name) == "string" and NS.MediaFont and NS.MediaFont(name))
        or (NS.Constants and NS.Constants.FONT_MONO) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

Style.OnLooks(function()
    local face = monoFace()
    for fs, size in pairs(bigTexts) do fs:SetFont(face, size, "") end
end)

local function bigText(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(monoFace(), size, "")
    bigTexts[fs] = size
    fs:SetTextColor(Style.Rgb(color))
    fs:SetJustifyH("CENTER")
    return fs
end

--- A flat box through the skin's Card, its slots remapped to `tokens` (default BOX).
local function card(parent, tokens)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    NS.Skin.Card(f, { tokens = tokens or BOX })
    return f
end
States.Card = card

-- The width a plain label takes: its own measurement (it never holds a meter value), else an
-- estimate from its length, for a client or a harness that cannot answer yet.
local function textWidth(fs, s)
    local w = fs.GetStringWidth and fs:GetStringWidth()
    if type(w) == "number" and w > 0 then return w end
    return #s * 6
end

--- A figure in a box: a small caption over a large value (LootHistory's Insights card), and a row
--- under the value for the pet's figure, shown only while there is one: a "Pet" label and the
--- value beside it, two strings, so a secret value is never joined to text.
local function kpi(parent, label, valueColor)
    local f = card(parent)
    f:SetHeight(KPI_HEIGHT)
    local k = { frame = f, petRow = false }
    k.label = Style.Text(f, FONT.CAPTION, nil, "CENTER")
    k.label:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
    k.label:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -7)
    k.label:SetText(label)
    k.value = Style.Text(f, FONT.FIGURE, valueColor or C.text, "CENTER")
    k.petLabel = Style.Text(f, FONT.CAPTION, nil, "RIGHT")
    k.petLabel:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -2, KPI_PAD)
    k.petLabel:SetText(L["Pet"])
    k.petValue = Style.Text(f, FONT.CAPTION, C.green, "LEFT")
    k.petValue:SetPoint("BOTTOMLEFT", f, "BOTTOM", 2, KPI_PAD)
    return k
end

-- Show or hide the box's pet row; the value moves up over it and the box grows by its height.
local function setPetRow(k, on)
    on = on and true or false
    k.petLabel:SetShown(on)
    k.petValue:SetShown(on)
    if k.petRow == on and k.placed then return end
    k.petRow, k.placed = on, true
    local y = KPI_PAD + (on and KPI_CAPTION_H or 0)
    k.value:ClearAllPoints()
    k.value:SetPoint("BOTTOMLEFT", k.frame, "BOTTOMLEFT", 8, y)
    k.value:SetPoint("BOTTOMRIGHT", k.frame, "BOTTOMRIGHT", -8, y)
end

local function kpiHeight(petRow)
    return KPI_HEIGHT + (petRow and KPI_CAPTION_H or 0)
end

-- Two boxes side by side at `y`, halves by anchor (no width needed), `h` high.
local function placePair(a, b, parent, y, h)
    a.frame:ClearAllPoints()
    a.frame:SetHeight(h)
    a.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    a.frame:SetPoint("TOPRIGHT", parent, "TOP", -4, y)
    b.frame:ClearAllPoints()
    b.frame:SetHeight(h)
    b.frame:SetPoint("TOPLEFT", parent, "TOP", 4, y)
    b.frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
end

-- ── chips ───────────────────────────────────────────────────────────────────────────────────────

local function newChip(parent)
    local f = Style.FlatBox(parent)
    f:SetHeight(CHIP_HEIGHT)
    f.label = Style.Text(f, FONT.TEXT, C.text, "CENTER")
    f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if not self.tip or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.tip, Style.Rgb("gtip.value"))
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return f
end

local Chips = {}
Chips.__index = Chips

local function chips(parent)
    return setmetatable({ parent = parent, y = 0, pool = NS.Pool.New(), width = 276, shown = {}, lines = 0 },
        Chips)
end

--- Lay out `list` ({ text, color, tip }) left to right from `y`, wrapping at the body's width.
function Chips:Set(list, y)
    NS.Pool.ReleaseAll(self.pool)
    self.shown, self.lines, self.y = {}, 0, y or self.y
    local x, row, parent = 0, self.y, self.parent
    for i, item in ipairs(list or {}) do
        local chip = NS.Pool.Acquire(self.pool, function() return newChip(parent) end)
        local s, c = item.text, item.color or C.text
        chip.label:SetText(s)
        Style.Paint(chip.label, c)
        Style.TintBox(chip, c, Style.CHIP_EDGE_A)
        chip.tip, chip.text = item.tip, s
        local w = math.floor(textWidth(chip.label, s) + 14)
        if x > 0 and x + w > self.width then x, row = 0, row - CHIP_HEIGHT - CHIP_GAP end
        self.lines = math.floor((self.y - row) / (CHIP_HEIGHT + CHIP_GAP) + 0.5) + 1
        chip:SetWidth(w)
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", parent, "TOPLEFT", x, row)
        chip:Show()
        x = x + w + CHIP_GAP
        self.shown[i] = chip
    end
end

--- The chips' height, the GAP under them included; 0 with none. Config only.
function Chips:Height()
    local n = self.lines
    if n == 0 then return 0 end
    return n * CHIP_HEIGHT + (n - 1) * CHIP_GAP + GAP
end

--- The chip texts drawn now, in order (the suites read these).
function Chips:Texts()
    local out = {}
    for i, chip in ipairs(self.shown) do out[i] = chip.text end
    return out
end

-- ── the over card's chips ───────────────────────────────────────────────────────────────────────

-- What each FIGHT_SKIPPED reason says on the card (modules/Recorder.lua's four).
local SKIP_TEXT = {
    filtered = "Not saved: filtered out",
    lost     = "Not saved: the meter lost this fight",
    unknown  = "Not saved: no readable character",
}

--- The "Not saved" chip's words for `reason`; with `showReason` false, the bare "Not saved".
--- @param reason string|nil  "short" | "filtered" | "lost" | "unknown"
--- @param showReason boolean
--- @param minLength number|nil  the recording filter's minimum, for "short"
--- @return string
function States.SkipText(reason, showReason, minLength)
    if not showReason then return L["Not saved"] end
    if reason == "short" then return L["Not saved: shorter than %d s"]:format(tonumber(minLength) or 0) end
    local key = SKIP_TEXT[reason]
    if key then return L[key] end
    return L["Not saved"]
end

--- The over card's chips (spec §6): a New best (with its gain over the best before it), then Saved,
--- or Not saved and why. Nothing while the recorder has not answered yet.
--- @param v table  the HUD's view
--- @return table list  { { text, color, tip }, ... }
function States.OverChips(v)
    local list = {}
    if v.newBest then
        local text = L["New best"]
        if type(v.delta) == "number" then text = L["New best %s"]:format(NS.Format.SignedPct(v.delta)) end
        list[#list + 1] = { text = text, color = C.gold, tip = L["Your best DPS on this boss or target, for this character and spec."] }
    end
    if v.saved == true then
        list[#list + 1] = { text = L["Saved"], color = C.green, tip = L["Stored in your fight history."] }
    elseif v.saved == false then
        list[#list + 1] = { text = States.SkipText(v.skipReason, v.showSkipReason, v.minLength), color = C.amber,
                            tip = L["Every fight is tracked live; only the ones that pass History > Recording filters are stored."] }
    end
    return list
end

-- ── the shared top of both bodies ───────────────────────────────────────────────────────────────

local function newBody(parent, key)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()
    return { key = key, frame = f, w = {}, height = 0 }
end

-- The clock, the target line and the two boxes every body has.
local function buildTop(body, dpsLabel, dpsColor)
    local f, w = body.frame, body.w
    w.clock = bigText(f, CLOCK_SIZE, C.text)
    w.target = Style.Text(f, FONT.TEXT, C.dim, "CENTER")
    w.damage = kpi(f, L["Damage"])
    w.dps = kpi(f, dpsLabel, dpsColor)
end

-- Lay the top out for the view's layout toggles; answers the y (positive, down) under it.
local function placeTop(body, v)
    local f, w, layout = body.frame, body.w, v.layout or {}
    local y = 0
    w.clock:SetShown(layout.clock ~= false)
    if layout.clock ~= false then
        w.clock:ClearAllPoints()
        w.clock:SetPoint("TOP", f, "TOP", 0, -4)
        y = y + CLOCK_H
    end
    w.target:SetShown(layout.target ~= false)
    if layout.target ~= false then
        w.target:ClearAllPoints()
        w.target:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        w.target:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
        y = y + TARGET_H
    end
    local figures = layout.figures ~= false
    w.damage.frame:SetShown(figures)
    w.dps.frame:SetShown(figures)
    if figures then
        local h = kpiHeight(v.hasPet)
        placePair(w.damage, w.dps, f, -y, h)
        y = y + h + GAP
    end
    return y
end

local function setValue(fs, value)
    if value == nil then fs:SetText(DASH) else fs:SetText(NS.Format.Number(value)) end
end

-- ── LIVE ────────────────────────────────────────────────────────────────────────────────────────

local Builders = {}

function Builders.live(parent)
    local body = newBody(parent, "live")
    buildTop(body, L["DPS \194\183 Live"])

    function body.Update(self, v)
        setPetRow(self.w.damage, v.hasPet)
        setPetRow(self.w.dps, v.hasPet)
        self.w.dps.petLabel:SetShown(false)
        self.w.dps.petValue:SetShown(false)
        self.height = placeTop(self, v)
        self.w.clock:SetText(NS.Format.Clock(v.clock))
        self.w.target:SetText(v.targetLine or "")
        -- The pace bar's slot (plan Task 3.2): shown only while there is a fight to pace against.
        self.paceShown = v.pace ~= nil
        self:SetLive(v.live)
    end

    --- The live figures: opaque values, straight to the formatter and the labels.
    function body.SetLive(self, live)
        local player = type(live) == "table" and live.player or nil
        local pet = type(live) == "table" and live.pet or nil
        setValue(self.w.damage.value, player and player.total)
        setValue(self.w.dps.value, player and player.dps)
        setValue(self.w.damage.petValue, pet and pet.total)
    end
    return body
end

-- ── OVER ────────────────────────────────────────────────────────────────────────────────────────

-- The card's plain figures: the merged damage and DPS (spec §6: after combat everything merges in
-- plain Lua), and the pet's damage when it had any. Dashes for a fight the meter lost.
local function overFigures(w, v)
    local merged = v.final and v.final.merged or nil
    local pet = v.final and v.final.pet or nil
    setValue(w.damage.value, merged and Secrets.PlainNumber(merged.total))
    setValue(w.dps.value, merged and Secrets.PlainNumber(merged.dps))
    setValue(w.damage.petValue, pet and Secrets.PlainNumber(pet.total))
end

function Builders.over(parent)
    local body = newBody(parent, "over")
    buildTop(body, L["DPS"], C.green)
    body.w.chips = chips(body.frame)

    function body.Update(self, v)
        local w = self.w
        setPetRow(w.damage, v.hasPet)
        setPetRow(w.dps, v.hasPet)
        w.dps.petLabel:SetShown(false)
        w.dps.petValue:SetShown(false)
        local y = placeTop(self, v)
        w.clock:SetText(NS.Format.Clock(v.clock))
        w.target:SetText(v.targetLine or "")
        overFigures(w, v)
        w.chips.width = v.width or w.chips.width
        w.chips:Set(States.OverChips(v), -y)
        self.height = y + w.chips:Height()
        self.paceShown = v.pace ~= nil
    end
    return body
end

--- Build one body into `parent`.
--- @param key string  "live" | "over"
--- @param parent table
--- @return table|nil body  { key, frame, w, height, Update(view), SetLive(live)? }
function States.Build(key, parent)
    local builder = Builders[key]
    if not builder then return nil end
    return builder(parent)
end
