local _, NS = ...
-- modules/RaceVerb.lua — `/ct race` (Race mode, plan Task B3; Retail only): the words a race takes from
-- chat, and the copy that says why an arm was refused. Ported from DPS Race @f8078c7 (its
-- settings/Slash.lua's arm, cancel and ignore verbs and modules/Format.lua's ParseLength and
-- ArmRefusal), worded in Combat Trail's vocabulary: a race, the fight it rides.
--
--   arm [length]     a typed length ("90", "1:30", "3m", "1m30s"; 0:10 to 15:00), else the length the
--                    next race arms at (Race.DefaultLength); every refusal answers one line
--   cancel           the armed or running race (its part comes off the fight), or the result card
--   show|hide|toggle the Race window, through NS.SetRaceWindowShown (core/CombatTrail.lua), the handler
--                    every surface that shows it shares
--   ignore [show|add|remove|defaults] <spell ID, link or name>   the late-cast ignore list
--                    (modules/LateIgnore.lua): every write goes through its row, so the seam
--
-- settings/Slash.lua declares the verb for Retail only (clients-§4) and refuses every word but
-- `ignore` while the addon is stood down (ruling X10); this file answers the rest. Race mode off
-- (NS.RaceMode.On()) refuses the arm and the window in one line; `cancel` and `ignore` still answer,
-- since a race under way runs on and the list scores saved races. The arm's own chat line is the bus's
-- (Task C2), so a successful arm prints nothing here.

local RaceVerb = {}
NS.RaceVerb = RaceVerb

local L = NS.L

local function out(line) NS.Print(line) end

-- ── the typed length ────────────────────────────────────────────────────────────────────────────

-- The shapes a typed race length may take: "90", "90s", "3m", "1:30", "1m30s".
local LENGTH_SHAPES = {
    { "^(%d+)$", function(n) return n end },
    { "^(%d+)s$", function(n) return n end },
    { "^(%d+)m$", function(m) return m * 60 end },
    { "^(%d+):([0-5]%d)$", function(m, s) return m * 60 + s end },
    { "^(%d+)m(%d+)s?$", function(m, s) if s < 60 then return m * 60 + s end end },
}

--- A race length typed by the player, in seconds, or nil when it is none of the accepted shapes. The
--- range (0:10 to 15:00) is Race.Arm's to enforce: it answers "bad_length".
--- @param text string
--- @return number|nil
function RaceVerb.ParseLength(text)
    if type(text) ~= "string" then return nil end
    local s = text:lower():gsub("%s+", "")
    for _, shape in ipairs(LENGTH_SHAPES) do
        local a, b = s:match(shape[1])
        if a then return shape[2](tonumber(a), tonumber(b)) end
    end
    return nil
end

-- ── why an arm was refused ──────────────────────────────────────────────────────────────────────

local REFUSALS = {
    client     = "Race mode is not available on this client.",
    off        = "Race mode is off. Turn it on at the top of the Race mode settings page.",
    busy       = "A race is already armed or running.",
    pending    = "A race is still waiting for its result: let it finish, or type /ct race cancel.",
    bad_length = "A race lasts from 0:10 to 15:00.",
    in_combat  = "Leave combat to arm a race.",
    settling   = "The last fight is still being read. Arm again in a moment.",
}

--- The line that says why Race.Arm refused.
--- @param reason string  one of Race.Arm's reasons
--- @param detail string|nil  the client's own reason, for "meter_unavailable"
--- @return string
function RaceVerb.ArmRefusal(reason, detail)
    if reason == "meter_unavailable" then
        if type(detail) == "string" and detail ~= "" then
            return L["Blizzard's damage meter is unavailable: %s"]:format(detail)
        end
        return L["Blizzard's damage meter is not available on this client."]
    end
    if reason == "disabled" then return NS.StoodDownRefusal() or L["Combat Trail is turned off."] end
    local key = REFUSALS[reason]
    if key then return L[key] end
    return L["The race could not be armed."]
end

-- ── arm and cancel ──────────────────────────────────────────────────────────────────────────────

local function arm(text)
    local Race = NS.Race
    if not NS.RaceMode.On() then return out(RaceVerb.ArmRefusal("off")) end
    local length
    if text ~= "" then
        length = RaceVerb.ParseLength(text)
        if not length or length < Race.MIN_LENGTH or length > Race.MAX_LENGTH then
            return out(RaceVerb.ArmRefusal("bad_length"))
        end
    end
    -- The Race window's own acts (DPS Race's doArm): a typed length becomes its pick, and a bare arm
    -- arms what it shows, so the verb, the Arm Race button and auto-arm agree (spec §4.1). Act.arm
    -- says a refusal itself.
    local Act = NS.RaceWindow and NS.RaceWindow.Act
    if Act then
        if length then Act.pickLength(length) end
        return Act.arm()
    end
    local ok, reason, detail = Race.Arm(length)
    if not ok then out(RaceVerb.ArmRefusal(reason, detail)) end
end

-- What `cancel` did, said in the state it found (Race.Cancel answers only whether it acted).
local CANCELED = {
    armed    = "Race canceled.",
    running  = "Race canceled: the fight goes on as a plain dummy fight.",
    stopping = "Race canceled: the fight goes on as a plain dummy fight.",
    result   = "Result closed. The race stays in your history.",
}

local function cancel()
    local state = NS.Race.State()
    if not NS.Race.Cancel() then return out(L["Nothing to cancel."]) end
    out(L[CANCELED[state] or "Race canceled."])
end

-- ── ignore: the late-cast ignore list ───────────────────────────────────────────────────────────

local function ignoreUsage()
    out(L["Usage: %s race ignore [show|add|remove|defaults] <spell ID, link or name>"]:format(NS.SLASH_CMD))
end

local function showIgnored()
    local ids = NS.LateIgnore.List()
    if #ids == 0 then return out(L["The late-cast ignore list is empty."]) end
    out(L["Late-cast ignore list:"])
    for _, id in ipairs(ids) do out("  " .. NS.LateIgnore.Label(id)) end
end

-- What a typed spell is, or nil after the one line that says why (none typed: the usage).
local function typedSpell(text)
    local id, reason = NS.LateIgnore.Resolve(text)
    if id then return id end
    if reason == "empty" then return ignoreUsage() end
    if reason == "ambiguous" then
        return out(L["More than one spell is named '%s'. Use its spell ID or a shift-clicked link."]:format(text))
    end
    out(L["No spell named '%s' is known. Use its spell ID or a shift-clicked link."]:format(text))
end

local function ignoreAdd(text)
    local LI, id = NS.LateIgnore, typedSpell(text)
    if not id then return end
    if LI.IsIgnored(id) then return out(L["%s is already ignored."]:format(LI.Label(id))) end
    if LI.Ignore(id) then out(L["Late casts of %s no longer flag a race."]:format(LI.Label(id))) end
end

local function ignoreRemove(text)
    local LI, id = NS.LateIgnore, typedSpell(text)
    if not id then return end
    -- A variant ignored through 8690 takes 8690 off, so the line names what was removed.
    local covering = LI.Covering(id)
    if not covering then return out(L["%s is not on the list."]:format(LI.Label(id))) end
    if LI.Unignore(id) then out(L["Late casts of %s flag a race again."]:format(LI.Label(covering))) end
end

local IGNORE_VERBS = {
    show = showIgnored,
    add = ignoreAdd,
    remove = ignoreRemove,
    defaults = function()
        if NS.LateIgnore.Reset() then out(L["The late-cast ignore list is back to its defaults."]) end
        showIgnored()
    end,
}

local function ignore(rest)
    local word, text = tostring(rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = word:lower()
    if word == "" then word = "show" end
    local fn = IGNORE_VERBS[word]
    if not fn then return ignoreUsage() end
    fn(text)
end

-- ── the verb ────────────────────────────────────────────────────────────────────────────────────

local function usage()
    out(L["Usage: %s race arm [length] | cancel | show | hide | toggle | ignore [show|add|remove|defaults]"]
        :format(NS.SLASH_CMD))
end

local VERBS = {
    arm = arm,
    cancel = cancel,
    show = function() NS.SetRaceWindowShown("show") end,
    hide = function() NS.SetRaceWindowShown("hide") end,
    toggle = function() NS.SetRaceWindowShown("toggle") end,
    ignore = ignore,
}

--- `/ct race <word> [rest]`; a bare or unknown word prints the usage.
function RaceVerb.OnVerb(rest)
    local word, text = tostring(rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local fn = VERBS[word:lower()]
    if not fn then return usage() end
    fn(text)
end
