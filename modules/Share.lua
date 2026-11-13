local _, NS = ...
-- modules/Share.lua — Share (spec §7, mockup §9): one line about a stored fight, sent to a chat
-- channel the player picks from a menu, only out of combat, with the fight's talents link after it
-- when History > Results window's "Include talents link when sharing" (`results.shareTalents`) is on.
-- Adapted from DPS Race @045f479 (modules/Share.lua); its race's lines came with Race mode (race plan
-- Task C2, DPS Race @f8078c7).
--
-- THE LINE (mockup §9's party line): "Combat Trail · Vorasius HC · 4:12 · 186.9K DPS · Beast
-- Mastery 721.4 · top: Kill Command 25.4%, Barbed Shot 17.1%". What the fight was against and its
-- difficulty (the keystone level, the delve tier after it), the length, the DPS, the spec (the class
-- where the client has none) and the item level, then the two spells that did the most of the
-- fight's merged damage. A line past one chat message (Share.MAX_CHAT bytes) drops its top spells,
-- then is cut, so it always fits. A RACE shares in the same shape: its length is the race length,
-- its DPS the race DPS (RaceRecord.Dps), and an incomplete race says so after it (spec §9).
--
-- THE RACE'S OWN LINES (Race mode, Retail only), printed to the player's own chat, never sent: on the
-- arm (RACE_ARMED: "Armed: 1:00 on Raider's Training Dummy. First hit starts the clock."), and when
-- the race resolves (RACE_RESULT): the score line ("1.54M damage · 51.3K DPS in 0:30 on Raider's
-- Training Dummy — new best (+2.4%) · 1 late cast · tail +3.1s", the delta only for a complete race,
-- the late casts the ignore list leaves), or for a lost race the line that says it could not be read.
--
-- PLAIN VALUES ONLY. A stored fight's fields went through NS.Secrets on their way in (spec §5), so
-- everything here formats plain values; nothing reads the meter. Every `|` in text that reaches a
-- channel is replaced, so a target's name or a spell's can never carry a chat escape into someone
-- else's chat; the talents link's escapes are the link's own.

local Share = {}
NS.Share = Share

local L = NS.L

local SEP = " \194\183 "
local WHISPER_POPUP = "COMBATTRAIL_SHARE_WHISPER"
-- The client sends at most this many bytes in one chat message.
Share.MAX_CHAT = 255
-- How many spells the line names.
Share.TOP_SPELLS = 2

-- The channels the menu offers, in its order, and when each is open to the player. Each test reads
-- the client function bare at call time.
local function asks(name)
    return function()
        local fn = _G[name]
        return type(fn) == "function" and fn() == true
    end
end

Share.CHANNELS = {
    { key = "SAY",     label = "Say" },
    { key = "PARTY",   label = "Party",   open = asks("IsInGroup") },
    { key = "RAID",    label = "Raid",    open = asks("IsInRaid") },
    { key = "GUILD",   label = "Guild",   open = asks("IsInGuild") },
    { key = "WHISPER", label = "Whisper\226\128\166" },
}

-- The short names of the difficulties a raid or a dungeon line names (DifficultyID), else the
-- difficulty's own name.
local DIFFICULTY_SHORT = {
    [1] = "N", [2] = "HC", [3] = "N", [4] = "N", [5] = "HC", [6] = "HC", [7] = "LFR", [8] = "M+",
    [9] = "N", [14] = "N", [15] = "HC", [16] = "M", [17] = "LFR", [23] = "M", [24] = "TW", [33] = "TW",
}

local function clean(s)
    return (tostring(s or ""):gsub("|", "/"))
end

local function ident(record)
    return type(record.identity) == "table" and record.identity or {}
end

local function who(record)
    return type(record.who) == "table" and record.who or {}
end

--- What the fight was against and where: "Vorasius HC", "Restless Gale M+ 12", "Angry Boar".
--- @param record table
--- @return string
function Share.Against(record)
    local i = ident(record)
    local parts = { NS.ResultsFights.TargetName(record) }
    local short = DIFFICULTY_SHORT[i.difficultyID]
    if type(i.keystoneLevel) == "number" then
        parts[#parts + 1] = L["M+ %d"]:format(i.keystoneLevel)
    elseif short then
        parts[#parts + 1] = short
    elseif type(i.difficultyName) == "string" and i.difficultyName ~= "" then
        parts[#parts + 1] = i.difficultyName
    end
    if type(i.delveTier) == "number" then parts[#parts + 1] = L["T%d"]:format(i.delveTier) end
    return table.concat(parts, " ")
end

--- "Beast Mastery 721.4": the spec (the class with none) and the item level.
local function whoText(record)
    local w = who(record)
    local name = w.specName or NS.ResultsTable.ClassName(w.class)
    if type(w.ilvl) == "number" then return ("%s %s"):format(tostring(name), NS.ResultsTable.Ilvl(w.ilvl)) end
    return tostring(name)
end

--- "top: Kill Command 25.4%, Barbed Shot 17.1%", or nil for a fight with no spells.
local function topText(record, count)
    local spells = NS.Recorder.Spells(record)
    local total = type(record.damage) == "table" and tonumber(record.damage.merged) or 0
    if not spells[1] or total <= 0 or count <= 0 then return nil end
    local parts = {}
    for i = 1, math.min(count, #spells) do
        local s = spells[i]
        parts[i] = ("%s %s"):format(tostring(NS.HudBreakdown.SpellName(s.spellID)),
            NS.Format.Pct((tonumber(s.total) or 0) / total * 100))
    end
    return L["top: %s"]:format(table.concat(parts, ", "))
end

-- A race's length and DPS are the race's (and an incomplete race says so); a fight's its own.
local function lineWith(record, count)
    local race = NS.RaceRecord.IsRace(record) and record.race or nil
    local parts = {
        L["Combat Trail"],
        Share.Against(record),
        NS.Format.Length(race and race.length or record.duration),
        L["%s DPS"]:format(NS.Format.Number(NS.RaceRecord.Dps(record) or 0)),
    }
    if race and race.status == "incomplete" then parts[#parts + 1] = L["incomplete"] end
    parts[#parts + 1] = whoText(record)
    parts[#parts + 1] = topText(record, count)
    return clean(table.concat(parts, SEP))
end

-- The line alone, at most MAX_CHAT bytes: fewer top spells first, then a cut.
local function plainLine(record)
    for count = Share.TOP_SPELLS, 0, -1 do
        local line = lineWith(record, count)
        if #line <= Share.MAX_CHAT then return line end
    end
    return lineWith(record, 0):sub(1, Share.MAX_CHAT)
end

--- The fight's talents link ([<spec>: <loadout>]), or nil when it has no talent string.
--- @param record table
--- @return string|nil
function Share.TalentsLink(record)
    local talents = NS.ResultsLoadout.TalentsOf(record)
    if not talents then return nil end
    local w = who(record)
    local name = talents.name or L["Talents"]
    local text = w.specName and ("%s: %s"):format(w.specName, name) or name
    return NS.ResultsLoadout.Hyperlink(talents, NS.ResultsLoadout.Level(record), text)
end

local function includeTalents()
    return NS.GetSetting("results.shareTalents") == true
end

--- The one line a fight is shared as, or nil for a record with nothing to share. `withTalents`
--- appends the talents link when the fight has one and both fit in one chat message.
--- @param record table
--- @param withTalents boolean|nil
--- @return string|nil
function Share.Line(record, withTalents)
    if type(record) ~= "table" or record.status ~= "final" then return nil end
    local line = plainLine(record)
    local link = withTalents and Share.TalentsLink(record) or nil
    if link and #line + 1 + #link <= Share.MAX_CHAT then return line .. " " .. link end
    return line
end

--- What a share sends, in order: the line, with the talents link after it when the setting is on and
--- the fight has one (in the same message when both fit in one, else a second; a link too long for a
--- message of its own is left out). nil for a record with no line.
--- @param record table
--- @return table|nil messages
function Share.Messages(record)
    local line = Share.Line(record, false)
    if not line then return nil end
    local link = includeTalents() and Share.TalentsLink(record) or nil
    if not link then return { line } end
    if #link > Share.MAX_CHAT then
        if NS.Debug then NS.Debug("Share", "talents link of %d bytes dropped", #link) end
        return { line }
    end
    if #line + 1 + #link <= Share.MAX_CHAT then return { line .. " " .. link } end
    return { line, link }
end

-- ── sending ─────────────────────────────────────────────────────────────────────────────────────

local function fighting()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return true end
    if type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") then return true end
    -- The chat lockdown (encounters, rated PvP): the client refuses to send then too.
    return NS.Compat.ChatLocked()
end

local function refuseInCombat()
    NS.Print(L["You can share a fight once you are out of combat."])
    return false
end

--- Send `record`'s line to one channel. Refused in combat.
--- @param record table
--- @param channel string  "SAY" | "PARTY" | "RAID" | "GUILD" | "WHISPER"
--- @param target string|nil  the whisper's recipient
--- @return boolean sent
function Share.Send(record, channel, target)
    local messages = Share.Messages(record)
    if not messages then return false end
    if fighting() then return refuseInCombat() end
    local send = NS.Compat.ChatSender()
    if type(send) ~= "function" then return false end
    for _, text in ipairs(messages) do
        local ok, err = pcall(send, text, channel, nil, target)
        if not ok then
            if NS.Debug then NS.Debug("Share", "send to %s failed: %s", channel, tostring(err)) end
            return false
        end
    end
    return true
end

local function acceptWhisper(dialog, record)
    local box = NS.Compat.PopupEditBox(dialog)
    local name = box and box:GetText()
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return false end
    return Share.Send(record, "WHISPER", name)
end
Share.AcceptWhisper = acceptWhisper

-- The whisper's recipient: a name typed into the popup, the targeted player's offered first.
-- Who a whisper goes to, as the client addresses them: on Retail "Name-Realm" when the target is from
-- another realm, on WoW Forever the full regional name ("First Surname", client-quirks §5). Plain or nil.
local function whisperName(unit)
    if not NS.Compat.ForClient({ "retail" }) then
        return NS.Secrets.PlainString((NS.Compat.UnitCharacterName(unit)))
    end
    local name, realm = UnitName(unit)
    name, realm = NS.Secrets.PlainString(name), NS.Secrets.PlainString(realm)
    if name and realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

StaticPopupDialogs[WHISPER_POPUP] = {
    text         = L["Whisper this fight to:"],
    button1      = L["Send"],
    button2      = L["Cancel"],
    hasEditBox   = true,
    maxLetters   = 64,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnShow       = function(self)
        local box = NS.Compat.PopupEditBox(self)
        local isPlayer = type(UnitIsPlayer) == "function" and UnitIsPlayer("target")
        local name = isPlayer and whisperName("target")
        if box and name then box:SetText(name) end
    end,
    OnAccept     = function(self, record) acceptWhisper(self, record) end,
    EditBoxOnEnterPressed = function(box, record)
        acceptWhisper(box:GetParent(), record)
        box:GetParent():Hide()
    end,
}
Share.WHISPER_POPUP = WHISPER_POPUP

local function pick(record, channel)
    if channel == "WHISPER" then
        if fighting() then return refuseInCombat() end
        StaticPopup_Show(WHISPER_POPUP, nil, nil, record)
        return true
    end
    return Share.Send(record, channel)
end

--- Add the channels to a menu description (the Share button's menu, or the row menu's Share
--- submenu), the ones the player is not in grayed.
--- @param desc table  a menu description (NS.OpenMenu's, MenuUtil's shape)
--- @param record table
function Share.FillMenu(desc, record)
    for _, c in ipairs(Share.CHANNELS) do
        local button = desc:CreateButton(L[c.label], function() pick(record, c.key) end)
        if c.open and not c.open() then button:SetEnabled(false) end
    end
end

--- The detail's Share button: a menu of channels, the ones the player is not in grayed. Refused in
--- combat with one line. With no menu on this client the line goes to the player's own chat.
--- @param record table
--- @param owner table|nil  the region the menu opens at
--- @return boolean opened
function Share.Prompt(record, owner)
    local line = Share.Line(record, false)
    if not line then return false end
    if fighting() then return refuseInCombat() end
    if not NS.CanOpenMenu() then
        NS.Print(line)
        return true
    end
    NS.OpenMenu(owner or UIParent, function(root)
        root:CreateTitle(L["Share to"])
        Share.FillMenu(root, record)
    end)
    return true
end

-- ── the race's own lines (Race mode, Retail only) ───────────────────────────────────────────────

local EMDASH = " \226\128\148 "

--- "Armed: 1:00 on Raider's Training Dummy. First hit starts the clock." `targetName` is the target at
--- the arm (no fight exists yet), the dummy kind's name with none.
--- @param race table  the race part
--- @param targetName string|nil
--- @return string
function Share.ArmedLine(race, targetName)
    local length = type(race) == "table" and race.length or nil
    return clean(L["Armed: %s on %s. First hit starts the clock."]:format(NS.Format.Length(length),
        targetName or L["your target"]))
end

local function deltaText(pct, isNew)
    if isNew then
        if pct then return L["new best (+%.1f%%)"]:format(pct) end
        return L["new best"]
    end
    if pct then return L["%+.1f%% vs best"]:format(pct) end
    return nil
end

-- The tail of the score line: the delta, the counted late casts, incomplete, the damage tail.
local function resultTail(race, pct, isNew)
    local tail = {}
    tail[#tail + 1] = deltaText(pct, isNew)
    -- The counted late casts only: the ignore list's never flag a race.
    local late = #(NS.RaceScoring.SplitLate(race))
    if late > 0 then tail[#tail + 1] = late == 1 and L["1 late cast"] or L["%d late casts"]:format(late) end
    if race.status == "incomplete" then tail[#tail + 1] = L["incomplete"] end
    if type(race.tail) == "number" then tail[#tail + 1] = L["tail +%.1fs"]:format(race.tail) end
    return tail
end

--- The score line the player sees when a race resolves: "1.54M damage · 51.3K DPS in 0:30 on
--- Raider's Training Dummy — new best (+2.4%) · 1 late cast · tail +3.1s".
--- @param record table  a stored race (complete or incomplete)
--- @param pct number|nil  Bests.Delta's percentage
--- @param isNew boolean|nil  Bests.Delta's new-best answer
--- @return string
function Share.ResultLine(record, pct, isNew)
    local race = type(record.race) == "table" and record.race or {}
    local line = L["%s damage \194\183 %s DPS in %s on %s"]:format(NS.Format.Number(tonumber(race.score) or 0),
        NS.Format.Number(NS.RaceRecord.Dps(record) or 0), NS.Format.Length(race.length),
        NS.ResultsFights.TargetName(record))
    local tail = resultTail(race, pct, isNew)
    if #tail == 0 then return clean(line) end
    return clean(line .. EMDASH .. table.concat(tail, SEP))
end

--- RACE_RESULT: the score line for a stored race, the delta only for a complete one; the lost line
--- for a race that could not be read (its pull, if stored, is a plain fight).
--- @param record table|nil
--- @param race table|nil  the race part
--- @return string|nil printed
function Share.OnRaceResult(record, race)
    local status = type(race) == "table" and race.status or nil
    if status == "lost" or not NS.RaceRecord.IsRace(record) then
        if status ~= "lost" then return nil end
        local line = L["Couldn't read the race's result, so it is not saved as a race."]
        NS.Print(line)
        return line
    end
    local pct, isNew
    if record.race.status == "complete" then pct, isNew = NS.Bests.Delta(record) end
    local line = Share.ResultLine(record, pct, isNew)
    NS.Print(line)
    return line
end

-- The target at the arm, by name (plain), or nil.
local function armTarget()
    local snap = NS.Identity.Snapshot()
    local target = type(snap) == "table" and snap.target or nil
    return type(target) == "table" and target.name or nil
end

if NS.Compat.ForClient({ "retail" }) then
    local bus = NS.NewBusTarget()
    if bus then
        bus:RegisterMessage(NS.MSG.RACE_ARMED, function(_, race) NS.Print(Share.ArmedLine(race, armTarget())) end)
        bus:RegisterMessage(NS.MSG.RACE_RESULT, function(_, record, race) Share.OnRaceResult(record, race) end)
    end
end
