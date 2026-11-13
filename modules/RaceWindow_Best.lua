local _, NS = ...
-- modules/RaceWindow_Best.lua — the Race window idle body's Your best card (Race mode spec §4.1, plan
-- Task C1): the best on the race board the next race would count on, the mark to beat between the
-- Target card and Arm Race. The running body draws the same card as Best to beat (race window
-- redesign plan Task W6), handed its view by modules/RaceWindow.lua for the race's own board. Ported from DPS Race @f8078c7 (modules/Hud_Best.lua) onto Combat Trail's
-- race boards; never NS.HudBest, which is the DPS HUD's pace data.
--
-- THE BOARD is character + spec + dummy kind + length (spec §5, Bests.RaceKey): the player read now
-- (Identity.Who), the kind of the dummy targeted now (Dummies.CategoryOf, the list's) and the length
-- Arm Race would arm. Its best is Bests.For on a probe of those, the cached board Results ranks too.
-- A target that is no training dummy has no race board: the card says to target one.
--
-- STORED NUMBERS ONLY: every figure is a stored record's (plain since NS.Secrets took it in), its
-- `race` part's score and race DPS (RaceRecord.Dps), so its width may be measured and its tooltip
-- may name it, in or out of combat. A click opens the record in the Results window.
--
-- RETAIL ONLY (clients-§4): nothing here loads on WoW Forever.

if not NS.Compat.ForClient({ "retail" }) then return end

local Best = {}
NS.RaceWindowBest = Best

local L = NS.L
local Style = NS.Style
local FONT = Style.FONT

-- The card's figures (owner, 2026-11-13): Damage (the score) and DPS (the race DPS) a matched pair on
-- one row, each half of the card a gold label and its value a fixed LABEL_W after it (sized for the
-- longer label, so a value never runs under its label at any width), the date and item level line
-- under them.
Best.LABEL_W = 44
local PAD_X, ROW_Y = 8, -7
local DOT = " \194\183 "

--- The view the idle body draws: { state = "noTarget" | "empty" | "best", record, who, kind, length }.
--- @param target table|nil  Identity's target snapshot
--- @param length number  the length Arm Race would arm
--- @return table
function Best.View(target, length)
    local v = { length = length }
    local id = type(target) == "table" and target.creatureID or nil
    local kind = NS.Dummies.CategoryOf(id)
    if not kind then
        v.state = "noTarget"
        return v
    end
    local who = NS.Identity.Who()
    v.who, v.kind = who, kind
    local probe = { who = who, identity = { targetCreatureID = id }, race = { kind = kind, length = length } }
    v.record = NS.Bests.For(probe)
    v.state = v.record and "best" or "empty"
    return v
end

-- The board the best is on, for the hover: spec, dummy kind, length.
local function boardText(v)
    local parts = {}
    local spec = type(v.who) == "table" and v.who.specName or nil
    if type(spec) == "string" then parts[#parts + 1] = spec end
    parts[#parts + 1] = NS.Dummies.Label(v.kind)
    parts[#parts + 1] = NS.Format.Length(v.length)
    return table.concat(parts, DOT)
end

-- The consumables the race used: every kind its usage carries but on-use gear.
local function consumables(record)
    local RU, out = NS.ResultsUsage, {}
    for _, e in ipairs(RU and RU.Entries(record) or {}) do
        if e.kind ~= "gear" then out[#out + 1] = e end
    end
    return out
end

local function times(e)
    local n = tonumber(e.n) or 1
    return n > 1 and ("x" .. n) or ""
end

--- A consumable's icon as inline markup at the caption line's 12 px, its art cropped past its edge.
function Best.ConsumableIcon(e)
    return "|T" .. tostring(NS.ResultsUsage.Icon(e)) .. ":12:12:0:0:64:64:5:59:5:59|t"
end

-- Line two: date, item level, the consumables' icons.
local function lineText(record)
    local Tbl = NS.ResultsTable
    local parts = { Tbl.Date(record.t, "%d %b") }
    local who = type(record.who) == "table" and record.who or {}
    if type(who.ilvl) == "number" then parts[#parts + 1] = L["ilvl %s"]:format(Tbl.Ilvl(who.ilvl)) end
    local icons = {}
    for _, e in ipairs(consumables(record)) do icons[#icons + 1] = Best.ConsumableIcon(e) .. times(e) end
    if #icons > 0 then parts[#parts + 1] = table.concat(icons, " ") end
    return table.concat(parts, DOT)
end

local function scoreOf(record) return type(record.race) == "table" and record.race.score or nil end

-- The hover: the board, then the race's stored figures and consumables.
local function tipOf(record, v)
    local Tbl, Format = NS.ResultsTable, NS.Format
    local tip = { L["Your best"], boardText(v), Tbl.Date(record.t, "%d %b %Y %H:%M"),
        L["Length: %s"]:format(Format.Length(record.race.length)),
        L["Score: %s"]:format(Format.Number(scoreOf(record))),
        L["Race DPS: %s"]:format(Format.Number(NS.RaceRecord.Dps(record))) }
    for _, e in ipairs(consumables(record)) do
        local n = times(e)
        tip[#tip + 1] = NS.ResultsUsage.InlineIcon(e) .. " " .. NS.ResultsUsage.Name(e) .. (n ~= "" and (" " .. n) or "")
    end
    tip[#tip + 1] = L["Click to open this race in Results."]
    return tip
end

local function open(card)
    local record = card.record
    local W = NS.RaceWindow
    if record and W and W.Act and W.Act.openBest then W.Act.openBest(record) end
end

--- Put the section at `y` (negative, from `parent`'s top): its caption, the card under it.
function Best.Place(b, parent, y)
    local CAPTION_H = NS.RaceWindowStates.BEST_CAPTION_H
    b.caption:ClearAllPoints()
    b.caption:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    b.caption:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    b.card:ClearAllPoints()
    b.card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y - CAPTION_H)
    b.card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y - CAPTION_H)
end

--- A labeled figure on one row of `card`: the label (the gold) at `x` from `from`, its value
--- LABEL_W after it to `toX` from `to`, in `color`. Every edge is the card's: the value's text is
--- never measured and nothing is placed off it (Best by now's Current, a secret in combat, is laid
--- out the same way, modules/RaceWindow_Board.lua).
--- @return table label, table value
function Best.Figure(card, from, x, to, toX, label, color, valueFont)
    local lab = Style.Text(card, FONT.CAPTION, Style.Tok("text.headingAlt"))
    lab:SetPoint("TOPLEFT", card, from == "LEFT" and "TOPLEFT" or "TOP", x, ROW_Y)
    lab:SetText(label)
    local fig = Style.Text(card, valueFont or FONT.TEXT, color, "LEFT")
    fig:SetPoint("TOPLEFT", card, from == "LEFT" and "TOPLEFT" or "TOP", x + Best.LABEL_W, ROW_Y)
    fig:SetPoint("TOPRIGHT", card, to == "RIGHT" and "TOPRIGHT" or "TOP", toX, ROW_Y)
    return lab, fig
end

--- Build the section into `parent` (the idle body's frame) at `y`, its caption in `font` (a
--- Style.FONT value; the Race window's bodies pass FONT.SECTION, the DPS HUD's headings, default
--- FONT.HEADER); its box restyles with the body's.
--- @return table b  { caption, card, damageLabel, damage, dpsLabel, dps, line, empty }
function Best.Build(body, parent, y, font)
    local dim = NS.HudStates.COLORS.dim
    local b = {}
    b.caption = Style.Text(parent, font or FONT.HEADER)
    b.caption:SetText(L["Your best"])
    local card = NS.HudStates.Card(parent)
    card:SetHeight(NS.RaceWindowStates.BEST_CARD_H)
    b.card = card
    Best.Place(b, parent, y)
    b.damageLabel, b.damage = Best.Figure(card, "LEFT", PAD_X, "CENTER", -4, L["Damage"], dim)
    b.dpsLabel, b.dps = Best.Figure(card, "CENTER", 4, "RIGHT", -PAD_X, L["DPS"], dim)
    b.line = Style.Text(card, FONT.CAPTION, dim)
    b.line:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 8, 5)
    b.line:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 5)
    b.empty = Style.Text(card, FONT.TEXT, dim)
    b.empty:SetPoint("LEFT", card, "LEFT", 8, 0)
    b.empty:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    NS.RaceWindowStates.AddTip(card, nil)
    card:SetScript("OnMouseUp", open)
    body.boxes[#body.boxes + 1] = card
    return b
end

--- Draw `v` (Best.View's) on the section.
function Best.Update(b, v)
    if not b then return end
    v = v or { state = "noTarget" }
    local record = v.state == "best" and v.record or nil
    b.card.record, b.card.tip = record, record and tipOf(record, v) or nil
    for _, fs in ipairs({ b.dps, b.damage, b.dpsLabel, b.damageLabel }) do fs:SetShown(record ~= nil) end
    b.line:SetShown(record ~= nil)
    b.empty:SetShown(record == nil)
    if not record then
        b.empty:SetText(v.state == "noTarget" and L["Target a training dummy to see your best."]
            or L["No race yet: this one sets the mark."])
        return
    end
    b.dps:SetText(NS.Format.Number(NS.RaceRecord.Dps(record)))
    b.damage:SetText(NS.Format.Number(scoreOf(record)))
    b.line:SetText(lineText(record))
end
