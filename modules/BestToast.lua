local _, NS = ...
-- modules/BestToast.lua — the new-best toast (Race mode spec §8, plan Task C2), ported from DPS Race
-- @f8078c7 (modules/BestToast.lua) onto Combat Trail's records: when a saved race or fight is the new
-- best on its board, a toast near the top of the screen says so and by how much, whether or not the
-- HUD or the Race window is shown. The HUD's fight-over card and the Race window's result card stay as
-- they are; the toast is the alert for a player looking elsewhere.
--
-- THE TRIGGERS. A race: RACE_RESULT with a stored record whose race part is "complete" (Retail only,
-- `toast.races`). A fight: FIGHT_SAVED with a record that has NO race part (a race toasts on its own
-- result, so the same pull never toasts twice), on both clients (`toast.fights`). Either way
-- Bests.Delta must say it is a new best AND name a percentage: a board's first race or fight is a new
-- best with nothing to beat, and does not toast (spec §8). A race counts on its race board, a fight on
-- its fight board (Bests.Key). The all-races board decides, so a flagged race may toast, and its flags
-- show on the toast's last line as the Race window's chips word them. One toast per record, queued
-- under its record id.
--
-- THE SHELL is LibKa0s-Toast-1.0 through core/ToastSetup.lua: one at a time, the countdown
-- (`toast.duration`) paused under the pointer, the close mark and a right-click, the scale
-- (`toast.scale`) and the sound (`toast.sound`, `toast.soundKey`: Default is the shell's alert, any
-- other a LibSharedMedia sound). This file keeps the content (the builder below), the triggers and the
-- placement rules: the toast moves only while it is *Test toast*'s sample (or test mode's preview),
-- and its point is stored in `profile.toast.point` in UIParent's units (the shell hands it over;
-- Master controls' *Reset position* clears it).
--
-- PLAIN VALUES ONLY. The payload is text made from the stored record (every number on it went through
-- NS.Secrets on its way in) and the previous best's; nothing here reads the meter. The frame's size is
-- this file's constants, never read back off a FontString.
--
-- THE LAYOUT (DPS Race's DR-04): every size scaled by SCALE (the padding, the faces, the chips, the
-- gaps). The trophy is as tall as the three rows (the headline, the two chips, the DPS line); the rows
-- are fixed-height slots, their text centered in them, one equal ROW_GAP between each pair, and the
-- same PAD above the first and below the last. The class and spec icons sit between "New best:" and
-- the spec and class words. A race's chips are its dummy kind and its length; a fight's, what it was
-- against (in its content's hue) and its length.

local BestToast = {}
NS.BestToast = BestToast

local L = NS.L
local MIDDOT = " \194\183 "
local RETAIL = { "retail" }

-- The key a sample from *Test toast* queues under.
BestToast.SAMPLE = "sample"

-- The frame's geometry (the shell's frame; the close mark is the shell's, top-right, 18 px, 4 px in).
local SCALE = 1.25
BestToast.SCALE = SCALE
BestToast.PAD = 13                      -- every edge, so the top and bottom padding match
BestToast.GAP = 10                      -- between the trophy and the rows
BestToast.ROW_GAP = 6                   -- one gap between each pair of rows
BestToast.TITLE_H = 17                  -- the headline's slot: its 15 px face and a pixel each side
BestToast.CHIP_H = 16 * SCALE           -- the chips' row
BestToast.TEXT_H = 15                   -- the DPS line's (and the flags') slot
BestToast.CLASS_ICON = 16               -- the class and spec icons, a pixel under the headline's slot
local ICON_GAP = 4                      -- between "New best:", the two icons and the words
local CHIP_GAP = math.floor(4 * SCALE + 0.5)
local CHIP_PAD = 14 * SCALE             -- a chip's width past its words
-- The three rows, and the trophy as tall as them.
BestToast.ROWS_H = BestToast.TITLE_H + BestToast.ROW_GAP + BestToast.CHIP_H + BestToast.ROW_GAP
    + BestToast.TEXT_H
local CLOSE_ROOM = 32                   -- the words' right inset, clear of the close mark
local CONTENT_W = 355                   -- the rows' width right of the trophy
BestToast.WIDTH = BestToast.PAD + BestToast.ROWS_H + BestToast.GAP + CONTENT_W + BestToast.PAD
BestToast.HEIGHT = BestToast.PAD + BestToast.ROWS_H + BestToast.PAD
BestToast.FLAGS_HEIGHT = BestToast.ROW_GAP + BestToast.TEXT_H   -- the flags' line, when any
local TROPHY_FALLBACK = "Interface\\Icons\\Achievement_Dungeon_GloryoftheHero"

local toast       -- the shell's instance (or the seam's stub)
local kindOf = {} -- record id -> "races" | "fights": each toast queued, so a kind switched off drops its own

local function debug(fmt, ...)
    if NS.Debug then NS.Debug("Toast", fmt, ...) end
end

local function setting(key) return NS.GetSetting("toast." .. key) end

--- Whether a race's new best toasts: Retail, and `toast.races` (absent on WoW Forever).
local function racesOn() return NS.Compat.ForClient(RETAIL) and setting("races") == true end

--- Whether a fight's new best toasts: `toast.fights`, on both clients.
local function fightsOn() return setting("fights") == true end

-- ── the payload ─────────────────────────────────────────────────────────────────────────────────

local function field(t, key)
    local v = type(t) == "table" and t[key] or nil
    return type(v) == "table" and v or {}
end

local function isRace(record) return NS.RaceRecord.IsRace(record) end

local function flagsText(record)
    local States = NS.RaceWindowStates
    if not (isRace(record) and States and States.FlagChips) then return nil end
    local chips = States.FlagChips(record.race)
    if #chips == 0 then return nil end
    local words = {}
    for i, chip in ipairs(chips) do words[i] = chip.text end
    return table.concat(words, MIDDOT)
end

--- "104.2K DPS, +4.2% better than previous best (100.0K)" in the gain's green; the DPS alone, in the
--- text color, when there is no previous best to name. A race's DPS is its race DPS.
--- @return string text, table color
local function detailText(record, pct, prev)
    local C = NS.ResultsTable.COLORS
    local dps = NS.Format.Number(NS.RaceRecord.Dps(record) or 0)
    local prevDps = prev and NS.RaceRecord.Dps(prev)
    if type(pct) == "number" and type(prevDps) == "number" then
        local sign = pct < 0 and "" or "+"
        return L["%s DPS, %s better than previous best (%s)"]:format(dps, sign .. NS.Format.Pct(pct),
            NS.Format.Number(prevDps)), pct < 0 and C.red or C.green
    end
    return L["%s DPS"]:format(dps), C.text
end

--- "New best:" in the best blue, as an escaped string.
local function titleText()
    local Tbl = NS.ResultsTable
    return ("|c%s%s|r"):format(Tbl.Hex(Tbl.COLORS.blue), L["New best:"])
end

--- The spec and the class ("Beast Mastery Hunter") in the class color, as an escaped string: the words
--- after the class and spec icons.
local function whoText(who)
    local Tbl = NS.ResultsTable
    local class = Tbl.ClassName(who.class)
    local words = who.specName and (tostring(who.specName) .. " " .. tostring(class or "")) or tostring(class or "?")
    return ("|c%s%s|r"):format(Tbl.Hex(Tbl.ClassColor(who.class)), (words:gsub("%s+$", "")))
end

--- The two chips: a race's dummy kind and length, a fight's target (in its content's hue) and length.
local function chipsOf(record)
    local Tbl, Format = NS.ResultsTable, NS.Format
    local dummy = Tbl.CONTENT_COLORS.dummy or Tbl.CONTENT_NEUTRAL
    if isRace(record) then
        return { { NS.Dummies.Label(NS.Bests.RaceKind(record)), dummy },
                 { Format.Length(record.race.length), Tbl.COLORS.text } }
    end
    local _, hue = Tbl.ContentChip(record)
    return { { NS.ResultsFights.TargetName(record), hue },
             { Format.Length(record.duration), Tbl.COLORS.text } }
end

--- What the toast says about `record`, beating `prev` by `pct` percent: plain strings only.
--- @param record table  a stored race (complete) or fight
--- @param pct number|nil  Bests.Delta's percentage
--- @param prev table|nil  the previous best (Bests.Delta's third return)
--- @return table payload  { recordID, title, who, class, specIcon, chips = { { text, color } x2 },
---                          detail, detailColor, flags }
function BestToast.Payload(record, pct, prev)
    local Tbl = NS.ResultsTable
    local detail, detailColor = detailText(record, pct, prev)
    local who = field(record, "who")
    local _, specIcon = Tbl.SpecInfo(who.specID, who.specName, who.specIcon)
    return {
        recordID    = record.id,
        title       = titleText(),
        who         = whoText(who),
        class       = who.class,
        specIcon    = specIcon,
        chips       = chipsOf(record),
        detail      = detail,
        detailColor = detailColor,
        flags       = flagsText(record),
    }
end

-- ── the content ─────────────────────────────────────────────────────────────────────────────────

--- A row's text in a slot `h` tall, its words centered in it, anchored once at `y` on the frame.
local function slotText(frame, font, color, x, y, h)
    local fs = NS.Style.ScaledText(frame, font, SCALE, color)
    fs:SetHeight(h)
    if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    return fs
end

-- A boxed chip, as the Race window's are, at the toast's scale.
local function newChip(frame)
    local Style = NS.Style
    local chip = Style.FlatBox(frame)
    chip:SetHeight(BestToast.CHIP_H)
    chip.label = Style.ScaledText(chip, Style.FONT.TEXT, SCALE, nil, "CENTER")
    chip.label:SetPoint("CENTER", chip, "CENTER", 0, 0)
    return chip
end

local function setChip(chip, text, color)
    local Style = NS.Style
    text = text or ""
    color = color or NS.ResultsTable.COLORS.text
    chip.label:SetText(text)
    Style.Paint(chip.label, color)
    Style.TintBox(chip, color, Style.CHIP_EDGE_A)
    local w = chip.label.GetStringWidth and chip.label:GetStringWidth()
    chip:SetWidth(math.floor((type(w) == "number" and w or 0) + CHIP_PAD + 0.5))
    chip:SetShown(text ~= "")
end

-- The trophy and the headline's three parts: "New best:", the class and spec icons, the words.
local function makeHeadline(frame, w, left)
    local Style, B = NS.Style, BestToast
    w.icon = frame:CreateTexture(nil, "ARTWORK")
    w.icon:SetSize(B.ROWS_H, B.ROWS_H)
    w.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", B.PAD, -B.PAD)
    w.icon:SetTexture(NS.Icon("ph:trophy") or TROPHY_FALLBACK)
    Style.Vertex(w.icon, NS.ResultsTable.COLORS.blue, 1)
    w.title = slotText(frame, Style.FONT.TITLE, nil, left, -B.PAD, B.TITLE_H)
    w.class = frame:CreateTexture(nil, "ARTWORK")
    w.class:SetSize(B.CLASS_ICON, B.CLASS_ICON)
    w.class:SetPoint("LEFT", w.title, "RIGHT", ICON_GAP, 0)
    w.spec = frame:CreateTexture(nil, "ARTWORK")
    w.spec:SetSize(B.CLASS_ICON, B.CLASS_ICON)
    w.spec:SetPoint("LEFT", w.class, "RIGHT", 2, 0)
    -- Both cropped and edged in the HUD's icon.border: a toast floats over the game world.
    Style.EdgeClassIcon(w.class, true)
    Style.EdgeIcon(w.spec, true)
    w.who = Style.ScaledText(frame, Style.FONT.TITLE, SCALE)
    w.who:SetHeight(B.TITLE_H)
    if w.who.SetJustifyV then w.who:SetJustifyV("MIDDLE") end
    w.who:SetPoint("LEFT", w.spec, "RIGHT", ICON_GAP, 0)
    w.who:SetPoint("RIGHT", frame, "RIGHT", -CLOSE_ROOM, 0)
end

-- The rows, made once on the shell's frame (stashed on it) and filled on every toast. Every row is
-- anchored to the frame at its own y, so the gaps and the padding are the constants above and never
-- what a string measured.
local function makeRows(frame)
    local Style, B = NS.Style, BestToast
    local w = {}
    local left = B.PAD + B.ROWS_H + B.GAP
    local chipY = -(B.PAD + B.TITLE_H + B.ROW_GAP)
    local detailY = chipY - B.CHIP_H - B.ROW_GAP
    makeHeadline(frame, w, left)
    w.chips = { newChip(frame), newChip(frame) }
    w.chips[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", left, chipY)
    w.chips[2]:SetPoint("LEFT", w.chips[1], "RIGHT", CHIP_GAP, 0)
    w.detail = slotText(frame, Style.FONT.TEXT, nil, left, detailY, B.TEXT_H)
    w.detail:SetPoint("RIGHT", frame, "RIGHT", -B.PAD, 0)
    local flagColor = NS.RaceWindowStates and NS.RaceWindowStates.FLAG_COLOR or NS.ResultsTable.COLORS.amber
    w.flags = slotText(frame, Style.FONT.TEXT, flagColor, left, detailY - B.FLAGS_HEIGHT, B.TEXT_H)
    w.flags:SetPoint("RIGHT", frame, "RIGHT", -B.PAD, 0)
    frame.combatTrail = w
    return w
end

--- The class icon (the character-creation atlas) and the spec icon, each hidden when the client has
--- nothing to draw; a hidden one takes no room: each element anchors to the last one shown, so the
--- words close up on "New best:" one ICON_GAP away.
local function setIcons(frame, w, p)
    local hasClass = p.class ~= nil and NS.ResultsTable.SetClassIcon(w.class, p.class) or false
    if not hasClass then w.class:Hide() end
    local hasSpec = p.specIcon ~= nil
    w.spec:SetTexture(p.specIcon)
    w.spec:SetShown(hasSpec)
    w.spec:ClearAllPoints()
    if hasClass then
        w.spec:SetPoint("LEFT", w.class, "RIGHT", 2, 0)
    else
        w.spec:SetPoint("LEFT", w.title, "RIGHT", ICON_GAP, 0)
    end
    local last = hasSpec and w.spec or hasClass and w.class or w.title
    w.who:ClearAllPoints()
    w.who:SetPoint("LEFT", last, "RIGHT", ICON_GAP, 0)
    w.who:SetPoint("RIGHT", frame, "RIGHT", -CLOSE_ROOM, 0)
end

--- The shell's builder: fill the rows, answer the frame's size from the constants above.
local function build(frame, p)
    if type(p) ~= "table" then return false end
    local w = frame.combatTrail or makeRows(frame)
    w.title:SetText(p.title or "")
    w.who:SetText(p.who or "")
    setIcons(frame, w, p)
    local chips = type(p.chips) == "table" and p.chips or {}
    for i, chip in ipairs(w.chips) do
        local c = chips[i] or {}
        setChip(chip, c[1], c[2])
    end
    w.detail:SetText(p.detail or "")
    NS.Style.Paint(w.detail, p.detailColor or NS.ResultsTable.COLORS.text)
    w.flags:SetText(p.flags or "")
    w.flags:SetShown(p.flags ~= nil)
    return BestToast.WIDTH, BestToast.HEIGHT + (p.flags and BestToast.FLAGS_HEIGHT or 0)
end

-- ── placement ───────────────────────────────────────────────────────────────────────────────────

local function store() return NS.db and NS.db.profile and NS.db.profile.toast end

-- A copy, so the shell never holds the profile's own table.
local function getPosition()
    local t = store()
    local pt = t and t.point
    if type(pt) ~= "table" then return nil end
    return { pt[1], pt[2], pt[3], pt[4] }
end

local function setPosition(pt)
    local t = store()
    if not t then return end
    if type(pt) ~= "table" then
        t.point = nil
        return
    end
    t.point = { tostring(pt[1]), tostring(pt[2] or pt[1]), tonumber(pt[3]) or 0, tonumber(pt[4]) or 0 }
end

-- The toast moves only while it is a sample from *Test toast* or test mode's preview: a real toast
-- never moves, so the key is the whole rule.
local function draggable()
    local _, key = toast:Current()
    return key == BestToast.SAMPLE or key == NS.TOAST_PREVIEW
end

local DEFAULT_SOUND = NS.defaults.profile.toast.soundKey

local function lsm()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

--- The Toast sound row's list: Default first, then every LibSharedMedia sound, read as the list is
--- drawn, since a media pack may register after this file loads.
--- @return table { { value, text } }
function BestToast.SoundValues()
    local out = { { value = DEFAULT_SOUND, text = L[DEFAULT_SOUND] } }
    local media = lsm()
    local keys = {}
    for key in pairs(media and media:HashTable("sound") or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a):upper() < tostring(b):upper() end)
    for _, key in ipairs(keys) do
        if key ~= DEFAULT_SOUND then out[#out + 1] = { value = key, text = key } end
    end
    return out
end

--- The file the picked sound names, read as a toast shows (Toast's d.soundFile). Nil for Default, a
--- key LibSharedMedia does not know, or no library: the shell then plays its own alert.
--- @return string|number|nil
function BestToast.SoundFile()
    local key, media = setting("soundKey"), lsm()
    if key == nil or key == DEFAULT_SOUND or not media then return nil end
    local ok, file = pcall(media.Fetch, media, "sound", key, true)
    return ok and file or nil
end

toast = NS.NewToast({
    name        = "CombatTrailBestToast",
    build       = build,
    width       = BestToast.WIDTH,
    height      = BestToast.HEIGHT,
    duration    = function() return setting("duration") end,
    scale       = function() return setting("scale") end,
    sound       = function() return setting("sound") end,
    soundFile   = BestToast.SoundFile,
    draggable   = draggable,
    getPosition = getPosition,
    setPosition = setPosition,
    debug       = function(tag, fmt, ...) debug("%s " .. fmt, tag, ...) end,
})

-- ── the triggers ────────────────────────────────────────────────────────────────────────────────

-- A record that may be a new best over an earlier one on its board: toast it if it is, under its
-- kind ("races" | "fights").
local function offer(record, kind)
    local pct, isNew, prev = NS.Bests.Delta(record)
    if not (isNew and pct ~= nil) then return false end
    debug("new best %s: %+.1f%%", tostring(record.id), pct)
    local shown = toast:Show(BestToast.Payload(record, pct, prev), { key = record.id }) == true
    if shown and record.id ~= nil then kindOf[record.id] = kind end
    return shown
end

--- A kind switched off: every toast of that kind goes, waiting or on screen; the other kind's stay.
--- @param kind string  "races" | "fights"
local function dropKind(kind)
    for id, k in pairs(kindOf) do
        if k == kind then
            toast:Remove(id)
            kindOf[id] = nil
        end
    end
end

--- A race's result (RACE_RESULT's stored record): toast a complete race that is a new best over an
--- earlier one, with `toast.races` on (Retail).
--- @param record table|nil
--- @return boolean shown  queued
function BestToast.OnRace(record)
    if not racesOn() or not isRace(record) or record.race.status ~= "complete" then return false end
    return offer(record, "races")
end

--- A saved fight (FIGHT_SAVED's record): toast a fight, never a race, that is a new best over an
--- earlier one on its fight board, with `toast.fights` on (both clients).
--- @param record table|nil
--- @return boolean shown  queued
function BestToast.OnFight(record)
    if not fightsOn() or type(record) ~= "table" or isRace(record) then return false end
    return offer(record, "fights")
end

-- ── the settings and the lifecycle ──────────────────────────────────────────────────────────────

--- *Test toast*: a sample toast queued as a real one is (its countdown, its sound), movable while it
--- shows. A sample already waiting or on screen is replaced. The sample is the player now, a fight on
--- a training dummy 4.2% over a previous best.
--- @return boolean shown
function BestToast.Test()
    local who = NS.Identity and NS.Identity.Who and NS.Identity.Who() or {}
    local dps = 100000
    local record = { id = BestToast.SAMPLE, who = who, duration = 120, dps = math.floor(dps * 1.042),
                     identity = { content = "dummy", targetName = L["Training Dummy"] } }
    toast:Remove(BestToast.SAMPLE)
    return toast:Show(BestToast.Payload(record, 4.2, { dps = dps }), { key = BestToast.SAMPLE }) == true
end

--- Re-read the scale and the stored point.
function BestToast.Refresh() toast:Refresh() end

--- Master controls' *Reset position*: the stored point goes, the toast goes back to the shell's.
function BestToast.ResetPosition() toast:ResetPosition() end

--- The stand-down: nothing on screen, nothing waiting.
function BestToast.Suspend()
    toast:Clear()
    kindOf = {}
end

--- The toast instance, for the suites.
function BestToast.Instance() return toast end

--- What the toast holds, for the diagnostics report and the suites.
function BestToast.Diagnose()
    local s = toast:Stats()
    return { shown = s.shown == true, waiting = s.waiting or 0, key = s.key }
end

do
    local bus = NS.NewBusTarget()
    if bus then
        bus:RegisterMessage(NS.MSG.FIGHT_SAVED, function(_, record) BestToast.OnFight(record) end)
        if NS.Compat.ForClient(RETAIL) then
            bus:RegisterMessage(NS.MSG.RACE_RESULT, function(_, record) BestToast.OnRace(record) end)
        end
        -- A profile switch or reset: its scale and its point; a kind switched off drops its own toasts.
        bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path)
            if path == "profile" then BestToast.Refresh() end
            if path == "toast.races" or path == "toast.fights" or path == "profile" then
                if not racesOn() then dropKind("races") end
                if not fightsOn() then dropKind("fights") end
            end
        end)
    end
end
