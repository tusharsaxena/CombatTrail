local _, NS = ...
-- modules/LogTable.lua — the Combat Log's table, its half that draws nothing (CombatTrail #11, plan item
-- CL-11b; the spec's addendum, *The table*): what each cell of a line says and in which color, which
-- lines a view shows, and the feed that walks the ring for a live view (its sort, its follow and pause,
-- its display throttle). The frames are modules/LogTable_View.lua's; the homes are the DPS HUD's docked
-- drawer (modules/Hud_Log.lua), the detached companion (modules/LogWindow.lua) and the Results fight
-- detail's Log tab (modules/Results_Log.lua), all three over this one component. Its settings are the
-- Combat Log page's (settings/Log.lua).
--
-- THE COLUMNS. Time · Event · Spell/School · Amount, plus Info where the home has room (Columns:
-- `opts.info`), every one centered in its header and its cells. Time and Event always show; the others
-- follow `log.view.columns.*`, and a home too narrow for them drops Info, so Spell/School keeps
-- SPELL_MIN. There is no Source or Target column (owner feedback item 3, 2026-11-25): a line's `u`
-- stays in the data, for the chips (Pet) and the categories, and is never a column.
--   Time          from the pull (seconds, `-` before it for a pre-pull line) or the clock time
--                 (`log.view.timeFormat` "pull" | "clock")
--   Event         CAST, BUFF+, BUFF-, DEBUFF+, DEBUFF-, HIT, HEAL, DIES. The fight's start and end are
--                 no lines (item 10); a saved log's old PULL / END lines are dropped at read time.
--   Spell/School  the spell's icon and name; for a hit the school (the client gives no spell); for a
--                 heal "Healing" in the heal color, naming a school only when the client reports one
--                 other than Physical (item 4: UNIT_COMBAT's HEAL reports school 1, Physical, or nil)
--   Amount        a hit's (red) or a heal's (green, "+") amount; `*` after a critical's plain amount
--   Info          Critical, Glancing, Crushing, Interrupted
--
-- THE COLORS (the spec's board D), each a skin token (core/SkinSetup.lua's `ct.log.*` and `ct.school.*`)
-- with its Ka0s Default value. A CAST row is plain, with the `ct.log.wash.cd` wash for a spell whose
-- base cooldown is long (Casts.IsLong); BUFF± green (BUFF- dimmed), DEBUFF+ orange with its wash
-- (DEBUFF- dimmed, no wash), HIT a red wash and a red amount, HEAL green with "+" and its "Healing"
-- cell. A hit's school name is in its school's color. COLOR-BLIND SAFETY: every kind differs by its
-- tag's text and its wash as well as its hue, and `log.view.schoolColors` / `log.view.washes` off draw
-- the names in the body text and no wash. WoW's fonts have no bold weight and FRIZQT__ has no star
-- glyph: a critical carries its `*` and the row's larger amount face instead (the view's Cells.big).
-- The who colors (`log.colors.*`, LogTable.ReadColors) are still read into each view's ctx, but with
-- no Source or Target column nothing draws them now.
--
-- WHAT IS SHOWN is a view's own `show` table, shaped as `log.show.*`: each category of
-- CombatLog.CategoryOf on or off, the auto attacks (Auto Shot, Shoot: no category) off by default, and
-- a hit or heal under `log.show.minAmount` hidden, judged on a PLAIN amount only. A sealed amount is
-- never compared: it always shows. A retired boundary never shows. What is shown never changes what is
-- captured or saved.
-- THE CHIPS (LogTable.CHIPS: Casts, Pet, Buffs, Debuffs, Taken, Heals, each over the categories it
-- covers) filter a view's lines. The Results Log tab's open on `log.results.chips` and count their
-- lines (modules/Results_Log.lua). The live views' (the detached window's strip under its status line,
-- the drawer's under its heading, shown by default and hidden by its filter mark, `log.drawer.chips`)
-- are each view's own `show`, SEEDED from `log.show.*` (the What
-- to show page, so `log.show` is those chips' defaults) when the view is built, when the log is opened,
-- at each FIGHT_STARTED and at a `log.show` write; a click turns every category the chip covers on
-- or off in that view alone for the session (LogTable.ToggleChip), never written to the settings. A
-- chip is lit while any category it covers shows (LogTable.ChipOn).
--
-- THE FEED (a live view over modules/CombatLog.lua's ring). `shown` is the newest sequence number the
-- view has revealed; each repaint tick (NS.Constants.LOG.REPAINT, the view's own timer) moves it toward
-- CombatLog.Seq() by `log.view.throttle`:
--   "instant"   every line at the next tick
--   "every"     at most one shown line every `log.view.throttleMs` ms (50-1000), a hidden line free
--   "batch"     every queued line together, once every `log.view.throttleMs` ms
-- THE THROTTLE ONLY DELAYS THE DISPLAY: the capture and the store never wait on it and drop nothing,
-- and a queue the throttle could not drain before the ring moved past it is skipped to the ring's
-- oldest line. FOLLOW: the view keeps the newest line in view, at the top (`log.view.sort` "newest",
-- the default) or the bottom ("oldest"). Scrolling away from it PAUSES: the view holds at the line it
-- was on (`anchor`) however many come in, until Resume or a scroll back to it. A view's rows are the
-- `rows` lines counted from its top line (`anchor` or `shown`), `offset` lines in.
--
-- SECRETS. A sealed amount is in the ring as the client gave it (`x`) and goes through NS.Format.Number
-- to the label alone (FontString display, docs/midnight-quirks.md); a saved one ("s") reads "sealed".
-- Nothing here compares, counts or stores a secret. Spell names and icons come through C_Spell,
-- pcall'd, from the line's plain spell ID.

local LogTable = {}
NS.LogTable = LogTable

local L = NS.L
local Secrets = NS.Secrets
local CL = NS.CombatLog
local K, F = CL.KIND, CL.FLAG

LogTable.SORTS = { newest = true, oldest = true }
LogTable.THROTTLES = { instant = true, every = true, batch = true }
LogTable.MIN_MS, LogTable.MAX_MS = 50, 1000

-- ── the cells ───────────────────────────────────────────────────────────────────────────────────

LogTable.TAG = {
    [K.CAST] = L["CAST"], [K.BUFF_ON] = L["BUFF+"], [K.BUFF_OFF] = L["BUFF-"], [K.DEBUFF_ON] = L["DEBUFF+"],
    [K.DEBUFF_OFF] = L["DEBUFF-"], [K.HIT] = L["HIT"], [K.HEAL] = L["HEAL"], [K.DIES] = L["DIES"],
}
-- The tag's color token per kind.
LogTable.TAG_COLOR = {
    [K.CAST] = "ct.text", [K.BUFF_ON] = "ct.log.buff", [K.BUFF_OFF] = "ct.log.buffOff",
    [K.DEBUFF_ON] = "ct.log.debuff", [K.DEBUFF_OFF] = "ct.log.debuffOff", [K.HIT] = "ct.log.hit",
    [K.HEAL] = "ct.log.heal", [K.DIES] = "ct.log.hit",
}
-- The row wash per kind (a long-cooldown CAST's is decided per spell).
LogTable.WASH = { [K.HIT] = "ct.log.wash.hit", [K.DEBUFF_ON] = "ct.log.wash.debuff" }
LogTable.CD_WASH = "ct.log.wash.cd"

--- The schools by their bit, lowest first, each with its token and its words.
LogTable.SCHOOLS = {
    { bit = 1, key = "physical", name = L["Physical"] }, { bit = 2, key = "holy", name = L["Holy"] },
    { bit = 4, key = "fire", name = L["Fire"] }, { bit = 8, key = "nature", name = L["Nature"] },
    { bit = 16, key = "frost", name = L["Frost"] }, { bit = 32, key = "shadow", name = L["Shadow"] },
    { bit = 64, key = "arcane", name = L["Arcane"] },
}

--- The school a mask names: its lowest school (its token), and the client's name for the whole mask
--- where it has one (GetSchoolString, plain), else that school's.
--- @return table|nil school, string|nil words
function LogTable.School(mask)
    mask = Secrets.PlainNumber(mask)
    if not mask or mask < 1 then return nil, nil end
    for _, s in ipairs(LogTable.SCHOOLS) do
        if math.floor(mask / s.bit) % 2 == 1 then
            local words = s.name
            if mask ~= s.bit and type(GetSchoolString) == "function" then
                local ok, got = pcall(GetSchoolString, mask)
                words = ok and Secrets.PlainString(got) or words
            end
            return s, words
        end
    end
    return nil, nil
end

local FLAG_WORDS = { { F.CRIT, L["Critical"] }, { F.GLANCING, L["Glancing"] }, { F.CRUSHING, L["Crushing"] },
                     { F.INTERRUPTED, L["Interrupted"] } }

--- The Info words for a line's marks ("" for none).
function LogTable.Info(f)
    f = Secrets.PlainNumber(f) or 0
    if f == 0 then return "" end
    local out = {}
    for _, pair in ipairs(FLAG_WORDS) do
        if math.floor(f / pair[1]) % 2 == 1 then out[#out + 1] = pair[2] end
    end
    return table.concat(out, ", ")
end

local function isCrit(f)
    f = Secrets.PlainNumber(f)
    return f ~= nil and f % 2 == 1
end

--- Seconds as the Time column says them: "12.3", "1:05.3", "-1.2" before the pull.
function LogTable.Seconds(t)
    t = Secrets.PlainNumber(t) or 0
    local neg = t < 0
    t = math.abs(t)
    local s
    if t >= 60 then s = ("%d:%04.1f"):format(math.floor(t / 60), t - 60 * math.floor(t / 60))
    else s = ("%.1f"):format(t) end
    return neg and "-" .. s or s
end

-- A line's seconds from the pull: a saved line's `t`, a ring line's `at` against the view's start.
local function since(e, ctx)
    if e.t ~= nil then return e.t end
    return (e.at or 0) - (ctx.startT or e.at or 0)
end

--- The Time cell: from the pull, or the clock time where the view knows the pull's (ctx.startClock).
function LogTable.Time(e, ctx)
    local t = since(e, ctx)
    if ctx.timeFormat == "clock" and ctx.startClock and type(date) == "function" then
        return date("%H:%M:%S", math.floor(ctx.startClock + t))
    end
    return LogTable.Seconds(t)
end

local cooldowns = {}   -- [spellID] = base cooldown ms, or false: plain answers only

--- Whether a cast's spell has a long base cooldown (Casts.IsLong), cached per spell: a sealed answer is
--- neither used nor cached.
function LogTable.LongCooldown(id)
    if type(id) ~= "number" then return false end
    local ms = cooldowns[id]
    if ms == nil then
        local ok, v = pcall(NS.Compat.SpellBaseCooldown, id)
        if ok and Secrets.IsSealed(v) then return false end
        ms = ok and Secrets.PlainNumber(v) or false
        cooldowns[id] = ms
    end
    return ms ~= false and NS.Casts.IsLong(ms)
end

local OFF = { [K.BUFF_OFF] = true, [K.DEBUFF_OFF] = true }

local PHYSICAL = 1

--- A heal's Spell/School words: "Healing", naming the school only when the client reports one other
--- than Physical. UNIT_COMBAT's HEAL gives school 1 (Physical) or nothing for an ordinary heal, which
--- read as "Physical" before (owner feedback item 4): the capture keeps what the client gave, and the
--- view words it.
--- @return string
function LogTable.HealWords(mask)
    mask = Secrets.PlainNumber(mask)
    if not mask or mask == PHYSICAL then return L["Healing"] end
    local _, words = LogTable.School(mask)
    return words and L["Healing (%s)"]:format(words) or L["Healing"]
end

-- Spell/School: the spell's icon and name, the school for a hit, "Healing" for a heal.
local function spell(c, e, ctx)
    c.icon, c.spellID, c.spellColor = nil, nil, OFF[e.k] and "ct.dim" or "ct.text"
    if e.k == K.HEAL then
        c.spell, c.spellColor = LogTable.HealWords(e.s), "ct.log.heal"
    elseif e.k == K.HIT then
        local s, words = LogTable.School(e.s)
        c.spell = words or ""
        if s and ctx.schoolColors ~= false then c.spellColor = "ct.school." .. s.key end
    elseif e.id then
        c.spellID = e.id
        c.spell = NS.HudBreakdown.SpellName(e.id)
        c.icon = NS.HudBreakdown.SpellIcon(e.id)
    else
        c.spell = ""
    end
end

-- Amount: a plain amount abbreviated ("+" on a heal, "*" after a critical), a sealed one as the client
-- gave it (the ring's `x`, to the label alone) or "sealed" (a saved one).
local function amount(c, e)
    c.amount, c.big = "", false
    if e.k ~= K.HIT and e.k ~= K.HEAL then return end
    c.amountColor = e.k == K.HIT and "ct.log.hit" or "ct.log.heal"
    c.big = isCrit(e.f)
    local a = Secrets.PlainNumber(e.a)
    if a then
        c.amount = (e.k == K.HEAL and "+" or "") .. NS.Format.Number(a) .. (c.big and "*" or "")
    elseif e.x ~= nil then
        c.amount = NS.Format.Number(e.x)
    elseif e.a == CL.SEALED then
        c.amount = L["sealed"]
    end
end

--- Fill `c` (a reused table) with line `e`'s cells: time, tag, tagColor, spell, spellColor, spellID,
--- icon, amount, amountColor, big, info, wash (a token or nil). `ctx`: startT, startClock, timeFormat,
--- schoolColors, washes.
--- @return table c
function LogTable.Cells(e, ctx, c)
    c = c or {}
    c.time = LogTable.Time(e, ctx)
    c.tag, c.tagColor = LogTable.TAG[e.k] or "", LogTable.TAG_COLOR[e.k] or "ct.text"
    spell(c, e, ctx)
    amount(c, e)
    c.info = LogTable.Info(e.f)
    local w = LogTable.WASH[e.k]
    if e.k == K.CAST and LogTable.LongCooldown(e.id) then w = LogTable.CD_WASH end
    c.wash = ctx.washes ~= false and w or nil
    return c
end

-- ── what is shown ───────────────────────────────────────────────────────────────────────────────

--- Whether line `e` shows under `show` (`log.show`: its categories, autoAttacks and minAmount).
function LogTable.Shows(e, show)
    local cat = CL.CategoryOf(e.k, e.u, e.id)
    if cat == nil then return e.k == K.CAST and show.autoAttacks == true end
    if show[cat] == false then return false end
    local min = Secrets.PlainNumber(show.minAmount) or 0
    if min > 0 and (e.k == K.HIT or e.k == K.HEAL) then
        local a = Secrets.PlainNumber(e.a)
        if a and a < min then return false end
    end
    return true
end

-- ── the chips ───────────────────────────────────────────────────────────────────────────────────

--- The chips, left to right: their key, their label and the saved categories each one covers (the
--- Results Log tab's and the live views' alike).
LogTable.CHIPS = {
    { key = "casts", label = "Casts", cats = { "casts" } },
    { key = "pet", label = "Pet", cats = { "petCasts" } },
    { key = "buffs", label = "Buffs", cats = { "playerBuffs", "targetBuffs" } },
    { key = "debuffs", label = "Debuffs", cats = { "playerDebuffs", "targetDebuffs" } },
    { key = "taken", label = "Taken", cats = { "hits" } },
    { key = "heals", label = "Heals", cats = { "heals" } },
}
--- Each chip's tooltip line (an L key).
LogTable.CHIP_TIPS = {
    casts = "Your casts.",
    pet = "Your pet's casts.",
    buffs = "Buffs gained and lost, on you and on your target.",
    debuffs = "Debuffs on you, and the debuffs you put on your target.",
    taken = "Hits taken: the damage done to you.",
    heals = "Heals taken: the healing done to you.",
}
LogTable.CHIP_PAD = 14     -- a chip's width past its text's
LogTable.CHIP_CHAR_W = 5.6 -- the chip label's width per character (estimated: nothing is read back)

local CHIP_BY_KEY = {}
for _, chip in ipairs(LogTable.CHIPS) do CHIP_BY_KEY[chip.key] = chip end

--- A chip's estimated width for `text` (nothing is measured).
function LogTable.ChipWidth(text)
    return math.floor(#tostring(text) * LogTable.CHIP_CHAR_W + LogTable.CHIP_PAD + 0.5)
end

--- Whether chip `key` is lit in a view's `show`: any category it covers shows.
--- @return boolean
function LogTable.ChipOn(show, key)
    local chip = CHIP_BY_KEY[key]
    if not chip then return false end
    for _, cat in ipairs(chip.cats) do
        if show[cat] ~= false then return true end
    end
    return false
end

--- Turn chip `key` on or off in a view's `show` (every category it covers), for that view alone and
--- never in the settings. Answers whether it is on now.
--- @return boolean
function LogTable.ToggleChip(show, key)
    local chip = CHIP_BY_KEY[key]
    if not chip then return false end
    local on = not LogTable.ChipOn(show, key)
    for _, cat in ipairs(chip.cats) do show[cat] = on end
    return on
end

--- Whether a write to `path` re-seeds a live view's chips: the log opened (`log.drawer.shown`), moved
--- (`log.home`), What to show (`log.show.*`) or the profile.
--- @return boolean
function LogTable.Reseeds(path)
    return path == "log.drawer.shown" or path == "log.home" or path == "profile" or path == "log.show"
        or path:find("^log%.show%.") ~= nil
end

-- ── the live homes' shared reads (the docked drawer and the detached window) ───────────────────

local function setting(path)
    return NS.GetSetting and NS.GetSetting(path)
end

--- The sort a live view draws in: `log.view.sort`, "newest" (the default) or "oldest".
function LogTable.SortOf()
    local s = setting("log.view.sort")
    return LogTable.SORTS[s] and s or "newest"
end

--- `show` (a reused table) refilled from `log.show`, the What to show page: a live view's chips'
--- seed.
function LogTable.ReadShow(show)
    local s = setting("log.show")
    for k in pairs(show) do show[k] = nil end
    if type(s) == "table" then for k, v in pairs(s) do show[k] = v end end
    return show
end

-- A stored swatch `{ r, g, b }` into `hue` (a reused array), or nil when there is none.
local function swatch(path, hue)
    local c = setting(path)
    if type(c) ~= "table" then return nil end
    hue[1], hue[2], hue[3] = tonumber(c.r) or 1, tonumber(c.g) or 1, tonumber(c.b) or 1
    return hue
end

local ownYou, ownHostile, ownFriendly = {}, {}, {}

--- `ctx`'s who colors refilled from `log.colors`: "You" in its own swatch while Use class color is off,
--- the hostile and friendly target in theirs while Use the skin's color is off; nil keeps the default
--- (the class color, the skin's `ct.log.hostile` and `ct.log.friendly`).
function LogTable.ReadColors(ctx)
    ctx.youColor = setting("log.colors.useClassColorYou") == false and swatch("log.colors.you", ownYou) or nil
    ctx.hostileColor = setting("log.colors.hostileFromSkin") == false and swatch("log.colors.hostile", ownHostile) or nil
    ctx.friendlyColor = setting("log.colors.friendlyFromSkin") == false
        and swatch("log.colors.friendly", ownFriendly) or nil
    return ctx
end

--- `ctx` (a reused table) refilled for a live view whose window starts at `startT` (GetTime()): the
--- time format, the clock time of the start and the color switches.
function LogTable.LiveContext(ctx, startT)
    ctx.startT = startT
    ctx.timeFormat = setting("log.view.timeFormat")
    ctx.startClock = nil
    if startT and type(time) == "function" then ctx.startClock = time() - (GetTime() - startT) end
    ctx.schoolColors = setting("log.view.schoolColors") ~= false
    ctx.washes = setting("log.view.washes") ~= false
    return LogTable.ReadColors(ctx)
end

-- ── the feed ────────────────────────────────────────────────────────────────────────────────────

--- A live view's feed over the ring: nothing revealed yet, following.
function LogTable.NewFeed()
    return { shown = CL.Seq(), offset = 0, anchor = nil, budget = 0, at = nil, batchAt = nil }
end

--- Whether the feed is paused (scrolled away from the newest line).
function LogTable.Paused(feed)
    return feed.anchor ~= nil
end

local function throttleMs(ms)
    ms = Secrets.PlainNumber(ms) or 250
    return math.max(LogTable.MIN_MS, math.min(LogTable.MAX_MS, ms))
end

-- "every": the budget earned since the last tick, spent one shown line at a time (a hidden line free).
local function drip(feed, top, now, ms, accept)
    feed.budget = math.min(feed.budget + (now - (feed.at or now)) * 1000 / ms, top - feed.shown)
    while feed.shown < top do
        local e = CL.Line(feed.shown + 1)
        local costs = e ~= nil and accept(e)
        if costs and feed.budget < 1 then break end
        if costs then feed.budget = feed.budget - 1 end
        feed.shown = feed.shown + 1
    end
    if feed.shown >= top then feed.budget = 0 end
end

--- One repaint tick: `feed.shown` moved toward the ring's newest line by `mode` ("instant" | "every" |
--- "batch", every `ms`), at `now` (GetTime()). `accept(e)` says whether a line shows. Answers whether
--- anything new was revealed.
--- @return boolean
function LogTable.Advance(feed, now, mode, ms, accept)
    local top, was = CL.Seq(), feed.shown
    if feed.shown < CL.First() - 1 then feed.shown = CL.First() - 1 end
    if top < feed.shown then feed.shown = top end     -- the ring was emptied (a stand-down)
    ms = throttleMs(ms)
    if mode == "every" then
        drip(feed, top, now, ms, accept)
    elseif mode == "batch" then
        if feed.batchAt == nil or (now - feed.batchAt) * 1000 >= ms then
            feed.shown, feed.batchAt = top, now
        end
    else
        feed.shown = top
    end
    feed.at = now
    return feed.shown ~= was
end

--- The view's lines: up to `rows` sequence numbers into `out` (newest first), from the feed's top line
--- (`anchor` while paused, else `shown`) down, `offset` shown lines in, none older than `from`
--- (GetTime()). Answers how many, and whether any shown line lies past them (older).
--- @return number n, boolean more
function LogTable.Collect(feed, rows, from, accept, out)
    local n, skip = 0, feed.offset
    local top = math.min(feed.anchor or feed.shown, feed.shown)
    for seq = top, CL.First(), -1 do
        local e = CL.Line(seq)
        if not e or (from and e.at < from) then break end
        if accept(e) then
            if skip > 0 then skip = skip - 1
            elseif n < rows then n = n + 1; out[n] = seq
            else
                for i = n + 1, #out do out[i] = nil end
                return n, true
            end
        end
    end
    for i = n + 1, #out do out[i] = nil end
    return n, false
end

--- Scroll the view `away` lines from the newest (negative: toward it). Away from it pauses at the line
--- on top now; back to it resumes.
function LogTable.Scroll(feed, away)
    local offset = feed.offset + away
    if offset <= 0 then return LogTable.Resume(feed) end
    if feed.anchor == nil then feed.anchor = feed.shown end
    feed.offset = offset
end

--- Back to following: the newest line in view.
function LogTable.Resume(feed)
    feed.offset, feed.anchor = 0, nil
end

--- Clear the cooldown cache (the suites).
function LogTable.__reset()
    cooldowns = {}
end
