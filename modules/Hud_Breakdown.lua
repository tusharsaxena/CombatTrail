local _, NS = ...
-- modules/Hud_Breakdown.lua — the DPS HUD's spell rows (spec §6, plan Task 3.2): pooled, laid out from
-- config, filled either LIVE (opaque values in the meter's order, no share) or from the fight's
-- PLAIN after-combat read (merged player and pet, highest first, each with its share of the fight).
-- Adapted from DPS Race @045f479 (modules/Hud_Breakdown.lua) for two sources: the player's rows,
-- then the pet's, each pet row marked by the paw and drawn in `hud.spells.petColor`. On WoW Forever
-- the pet folds into the player's source and each row carries the meter's creature name, secret in
-- combat: live, the share column draws that name (blank on the owner's rows), never a color.
--
-- THE LIVE PATH TOUCHES NO NUMBER. A live value is secret for the whole fight, so a row hands it to
-- three native seams and nowhere else: the bar's SetMinMaxValues / SetValue (the widget scales it),
-- NS.Format.Number (the client's formatter abbreviates it) and the name and icon lookups (C_Spell
-- takes a secret spell ID, pcall'd). No sort, no share, no sum, no comparison, no truth test: the
-- one question asked of a live value is `== nil`. Every bar, the pet's included, is scaled to the
-- PLAYER source's own `maxAmount` (spec §6: a C-side clamp; a pet spell past it draws full); with no
-- player source the pet's own `maxAmount` scales them. The row COUNT is plain: the live tables are
-- modules/Meter.lua's own Lua arrays, built by Secrets.SafeIterate.
--
-- NO GEOMETRY IS READ BACK. A frame handed a secret has secret geometry, so a row is placed from its
-- index and the configured row height, and nothing here asks a row, a bar or a label its size.
--
-- THE SCROLL. Both fills take a plain row offset and a row count (modules/Hud_States.lua works them
-- out from `hud.bars`, the window's room and the wheel), so the list never decides what is visible.
--
-- THE LOOK (modules/Hud_Appearance.lua, `hud.spells.*`) is applied once per Appearance stamp: the
-- row height, the icons, the bar's texture and the player's and the pet's colors, the text's font
-- (the share column too: the amount's color, face and flags, a little smaller).

local Breakdown = {}
NS.HudBreakdown = Breakdown

local L = NS.L
local Style = NS.Style

Breakdown.ROW_GAP = 2
Breakdown.PAW = 12
local PCT_WIDTH = 44
Breakdown.PCT_SMALLER = 2   -- the share's size under the amount's (points)
local pctFont = {}          -- refilled per restyle: ApplyFont keeps nothing of it

--- The configured row height.
function Breakdown.RowHeight()
    return NS.HudAppearance.Number("hud.spells.rowHeight", 12, 40)
end

--- The pitch from one row's top to the next (config, never a measured size).
function Breakdown.Pitch()
    return Breakdown.RowHeight() + Breakdown.ROW_GAP
end

--- The rows as drawn at `px` UI units a physical pixel (Compat.PixelSize's): the row's height, the
--- pitch and the gap between, each a whole number of pixels, so every row and every gap draws the
--- same thickness at a UI scale that is not round (owner, 2026-11-11: an 18 px row and its 2 px gap
--- fell on fractions of a pixel and came out 1, 2 or 3 pixels apart). The pitch rounds DOWN, so n
--- snapped rows never take more than Height(n), the room the layout gave them; the row's height
--- rounds to the nearest pixel, short of the pitch by one pixel at least while there is a gap.
--- @param px number|nil  1 when left out
--- @return number rowHeight, number pitch, number gap
function Breakdown.Snapped(px)
    px = (type(px) == "number" and px > 0) and px or 1
    local pitch = math.max(1, math.floor(Breakdown.Pitch() / px + 1e-6))
    local h = math.max(1, math.floor(Breakdown.RowHeight() / px + 0.5))
    if Breakdown.ROW_GAP > 0 then h = math.min(h, pitch - 1) else h = math.min(h, pitch) end
    h = math.max(1, h)
    return h * px, pitch * px, (pitch - h) * px
end

-- `v` UI units to the nearest whole pixel at `px`.
local function snap(v, px)
    return math.floor(v / px + 0.5) * px
end

--- A spell's name through C_Spell (a secret ID is passed through, the name only ever reaching
--- SetText), or the localized "Unknown spell".
--- @param id any  a spell ID, possibly secret
--- @return any
function Breakdown.SpellName(id)
    if id == nil then return L["Unknown spell"] end
    local ok, name = pcall(NS.Compat.SpellName, id)
    if ok and name ~= nil then return name end
    return L["Unknown spell"]
end

--- A spell's icon, or nil: a lookup that fails leaves the icon blank.
--- @param id any  a spell ID, possibly secret
--- @return any
function Breakdown.SpellIcon(id)
    if id == nil then return nil end
    local ok, icon = pcall(NS.Compat.SpellTexture, id)
    if ok then return icon end
    return nil
end

--- How many rows the live read can draw: the player's spells and then the pet's (plain counts of
--- modules/Meter.lua's own arrays).
--- @param live table|nil  NS.Meter.ReadLive's
--- @return number
function Breakdown.LiveCount(live)
    if type(live) ~= "table" then return 0 end
    local n = 0
    for _, part in ipairs({ live.player or false, live.pet or false }) do
        if part and type(part.spells) == "table" then n = n + #part.spells end
    end
    return n
end

-- A row's hover: the client's spell tooltip for its ID (possibly secret, handed on untouched).
local function rowEnter(row)
    if row.spellID == nil or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    if not pcall(GameTooltip.SetSpellByID, GameTooltip, row.spellID) then return GameTooltip:Hide() end
    GameTooltip:Show()
end

local function newRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    -- Every other row faintly tinted, under the icon and the bar's track (owner, 2026-11-11: the fight
    -- list's stripe, Style.Stripe), on the HUD and in the fight detail alike.
    -- Down through the gap under the row, so the bands join up (DPS Race's, 2026-11-11).
    -- Its anchors are restyle's: the gap it reaches down through is the snapped one.
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetTexture(Style.WHITE)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    Style.EdgeIcon(row.icon, true)
    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    row.track = bar:CreateTexture(nil, "BACKGROUND")
    row.track:SetAllPoints(bar)
    Style.Fill(row.track, "ct.list.track")
    row.bar = bar
    row.paw = bar:CreateTexture(nil, "OVERLAY")
    row.paw:SetSize(Breakdown.PAW, Breakdown.PAW)
    row.name = Style.PlainText(bar, Style.FONT.TEXT, "LEFT")
    row.amount = Style.PlainText(bar, Style.FONT.TEXT, "RIGHT")
    row.pct = Style.PlainText(bar, Style.FONT.TEXT, "RIGHT")
    row:EnableMouse(true)
    row:SetScript("OnEnter", rowEnter)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
end

-- The row's look, once per Appearance stamp and pixel size: its height (snapped, Breakdown.Snapped),
-- the stripe down through the gap, the icon's size, the bar's texture and border, the spell text's
-- font. The fill's color is set per fill (the player's or the pet's).
local function restyle(row, px)
    local A = NS.HudAppearance
    if row.stamp == A.stamp and row.px == px then return end
    row.stamp, row.px, row.mode = A.stamp, px, nil
    local h, _, gap = Breakdown.Snapped(px)
    row:SetHeight(h)
    row.stripe:ClearAllPoints()
    row.stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.stripe:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -gap)
    row.iconSize = math.max(8, h - 2 * px)
    row.icon:SetSize(row.iconSize, row.iconSize)
    row.look = A.Bar("spells")
    row.petLook = A.PetColor()
    A.PaintBar(row.bar, row.look)
    -- The bar's border (Spell rows > Bar border; owner, 2026-11-11): off by default, drawn round the
    -- bar alone, never the icon.
    A.PaintEdge(row, row.bar, A.Border("spells"), px)
    local font = A.Font("spells")
    A.ApplyFont(row.name, font)
    A.ApplyFont(row.amount, font)
    -- The share: the amount's color, face and flags (owner, 2026-11-11), PCT_SMALLER points smaller
    -- so it stays the quieter figure.
    pctFont.path, pctFont.flags, pctFont.shadow, pctFont.shadowFromSkin = font.path, font.flags, font.shadow,
        font.shadowFromSkin
    pctFont.size = math.max(6, font.size - Breakdown.PCT_SMALLER)
    pctFont.r, pctFont.g, pctFont.b, pctFont.a = font.r, font.g, font.b, font.a
    A.ApplyFont(row.pct, pctFont)
end

-- The row's anchors for its mode: the icon, the paw and the share column on or off. Set only when
-- the mode changes; every anchor is relative to the row's own children, never a measured size.
local function setMode(row, icons, paw, pct)
    local mode = (icons and "i" or "-") .. (paw and "w" or "-") .. (pct and "p" or "-")
    if row.mode == mode then return end
    row.mode = mode
    local bar = row.bar
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", row, "TOPLEFT", icons and snap((row.iconSize or 16) + 3, row.px or 1) or 0, 0)
    bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.pct:ClearAllPoints()
    row.pct:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    row.pct:SetWidth(PCT_WIDTH)
    row.pct:SetShown(pct)
    row.amount:ClearAllPoints()
    if pct then
        row.amount:SetPoint("RIGHT", row.pct, "LEFT", -4, 0)
    else
        row.amount:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    end
    row.paw:ClearAllPoints()
    row.paw:SetPoint("LEFT", bar, "LEFT", 4, 0)
    row.paw:SetShown(paw)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", bar, "LEFT", paw and (Breakdown.PAW + 7) or 6, 0)
    row.name:SetPoint("RIGHT", row.amount, "LEFT", -6, 0)
    row.icon:SetShown(icons)
end

local List = {}
List.__index = List

--- A list of spell rows drawn into `parent`, top down.
--- @param parent table
--- @return table list
function Breakdown.New(parent)
    return setmetatable({ parent = parent, pool = NS.Pool.New(), rows = {} }, List)
end

--- Release every row.
function List:Clear()
    NS.Pool.ReleaseAll(self.pool, function(row) row.spellID = nil end)
    self.rows = {}
end

--- The rows drawn now, in order (the suites read them: icon, bar, paw, name, amount, pct, isPet).
function List:Rows()
    return self.rows
end

--- The height `n` rows take (config only).
function Breakdown.Height(n)
    if n <= 0 then return 0 end
    return n * Breakdown.Pitch() - Breakdown.ROW_GAP
end

--- How many whole rows fit `room` pixels: the inverse of Height (config only, never a measured
--- size), 0 for no room. Height(Capacity(room)) never exceeds `room`.
--- @param room number
--- @return number
function Breakdown.Capacity(room)
    room = tonumber(room) or 0
    if room <= 0 then return 0 end
    return math.max(0, math.floor((room + Breakdown.ROW_GAP) / Breakdown.Pitch()))
end

-- One pooled row at index `i`, styled and in its mode.
-- `rank`: the spell's place in the whole list (the offset plus `i`), which the stripe follows so its
-- tint stays with its spell on the wheel; `i` when left out.
function List:acquire(i, isPet, pct, rank)
    local parent = self.parent
    local row = NS.Pool.Acquire(self.pool, function() return newRow(parent) end)
    local px = NS.Compat.PixelSize(parent)
    restyle(row, px)
    local _, pitch = Breakdown.Snapped(px)
    local y = -(i - 1) * pitch
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    Style.Stripe(row.stripe, rank or i)
    local A = NS.HudAppearance
    setMode(row, A.On("hud.spells.icons"), isPet and A.On("hud.spells.paw"), pct)
    if isPet then row.paw:SetTexture(NS.Icon("ph:paw-print")) end
    local c = isPet and row.petLook or row.look
    row.bar:SetStatusBarColor(c.r, c.g, c.b, c.a)
    row.isPet = isPet and true or false
    row:Show()
    self.rows[i] = row
    return row
end

local function setIcon(row, id)
    if row.icon:IsShown() then row.icon:SetTexture(Breakdown.SpellIcon(id)) end
end

-- The live entries in drawing order: the player's spells, then the pet's ({ spell, isPet }). A row
-- of the player's that the meter PLAINLY names a creature on (`creature`: a folded source's pet row,
-- WoW Forever, read out of combat), or that the live folded split marked `isPet` (Meter.ReadLive),
-- draws as the pet's where it stands. In combat the name is secret
-- (the owner's rows carry "", the pet's its name), so no row can be colored by it: the share column,
-- empty live, draws the name instead (ShowLive), blank on the owner's rows.
local function liveEntries(live)
    local out = {}
    local function add(part, isPet)
        if type(part) ~= "table" or type(part.spells) ~= "table" then return end
        for _, s in ipairs(part.spells) do
            out[#out + 1] = { s = s, pet = isPet or s.creature == true or s.isPet == true }
        end
    end
    add(live.player, false)
    add(live.pet, true)
    return out
end

-- The scale every live bar takes: the player source's maxAmount, else the pet's (opaque).
local function liveMax(live)
    local player, pet = live.player, live.pet
    if type(player) == "table" and player.maxAmount ~= nil then return player.maxAmount end
    if type(pet) == "table" then return pet.maxAmount end
    return nil
end

--- Draw the live breakdown: `n` rows from the one after `offset` (a plain row count off the wheel),
--- the player's spells in the meter's order, then the pet's. Every value is opaque and goes only to
--- a widget setter or the formatter.
--- @param live table|nil  NS.Meter.ReadLive's
--- @param n number  rows to show
--- @param offset number|nil  rows skipped from the top (default 0)
--- @return number drawn
function List:ShowLive(live, n, offset)
    self:Clear()
    if type(live) ~= "table" then return 0 end
    local entries, max = liveEntries(live), liveMax(live)
    -- The pet's name column: while a pet is out and a row carries a name to draw.
    local names = live.petOut == true
    offset = offset or 0
    for i = 1, n do
        local e = entries[offset + i]
        if not e then break end
        local s = e.s
        local row = self:acquire(i, e.pet, names, offset + i)
        if max ~= nil then row.bar:SetMinMaxValues(0, max) end
        if s.total ~= nil then row.bar:SetValue(s.total) else row.bar:SetValue(0) end
        row.name:SetText(Breakdown.SpellName(s.spellID))
        row.amount:SetText(NS.Format.Number(s.total))
        -- The meter's creature name, untouched (only `== nil` is asked of it): "" on the owner's rows.
        if names and s.creatureName ~= nil then row.pct:SetText(s.creatureName) else row.pct:SetText("") end
        if names then
            local c = row.petLook
            row.pct:SetTextColor(c.r, c.g, c.b, 1)
        end
        setIcon(row, s.spellID)
        row.spellID = s.spellID   -- a handle for the hover only: tested for nil, never compared
    end
    return #self.rows
end

--- Draw the fight's after-combat breakdown: `spells` plain and sorted highest first ({ spellID,
--- total, isPet }, modules/Meter.lua ReadFinal's merged list or Recorder.Spells), each with its share
--- of `total` (the merged damage), the bars scaled to the top spell.
--- @param spells table
--- @param total number
--- @param n number
--- @param offset number|nil
--- @return number drawn
function List:ShowFinal(spells, total, n, offset)
    self:Clear()
    if type(spells) ~= "table" or not spells[1] then return 0 end
    local top = tonumber(spells[1].total) or 0
    total = tonumber(total) or 0
    offset = offset or 0
    for i = 1, math.min(n, #spells - offset) do
        local s = spells[offset + i]
        local dmg = tonumber(s.total) or 0
        local row = self:acquire(i, s.isPet == true, true, offset + i)
        row.bar:SetMinMaxValues(0, top > 0 and top or 1)
        row.bar:SetValue(dmg)
        row.name:SetText(Breakdown.SpellName(s.spellID))
        row.amount:SetText(NS.Format.Number(dmg))
        row.pct:SetText(total > 0 and NS.Format.Pct(dmg / total * 100) or "")
        row.pct:SetTextColor(pctFont.r, pctFont.g, pctFont.b, pctFont.a)   -- off the live tint (restyle filled it)
        setIcon(row, s.spellID)
        row.spellID = s.spellID
    end
    return #self.rows
end
