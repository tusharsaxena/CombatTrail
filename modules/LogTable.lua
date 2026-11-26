local _, NS = ...
-- modules/LogTable.lua — the Combat Sequence's table, its half that draws nothing (CombatTrail #11, plan
-- item CL-11b; the spec's addendum, *The table*; the Combat Sequence, CSEQ-1): what each cell of a line
-- says and in which color, which lines a view shows, and the feed that walks the ring for a live view
-- (its sort, its follow and pause, its display throttle). The frames are modules/LogTable_View.lua's;
-- the homes are the DPS HUD's docked section (modules/Hud_Log.lua), the detached companion
-- (modules/LogWindow.lua) and the Results fight detail's section (modules/Results_Log.lua), all three
-- over this one component. Its settings are the Combat Sequence page's (settings/Log.lua).
--
-- THE COLUMNS. Time · Event · Spell, plus Info where the home has room (Columns: `opts.info`), every
-- one left-aligned in its header and its cells (owner feedback round 4, R4-CT-02). Time and Event always show; the others follow
-- `sequence.view.columns.*`, and a home too narrow for them drops Info, so Spell keeps SPELL_MIN. There is
-- no Source or Target column (owner feedback item 3, 2026-11-25), and no Amount (the Combat Sequence:
-- no line carries one): a line's `u` stays in the data, for the chips (Pet) and the categories.
--   Time   from the pull (seconds, `-` before it for a pre-pull line) or the clock time
--          (`sequence.view.timeFormat` "pull" | "clock")
--   Event  CAST, BUFF+, BUFF-, DEBUFF+, DEBUFF-, DIES. The fight's start and end, the hits and heals
--          and a target's buffs are no lines; a saved log's old ones are dropped at read time
--          (CombatLog.IsRetired).
--   Spell  the spell's icon and name, one character apart (blank for a death)
--   Info   Interrupted
--
-- THE COLORS (the spec's board D), each a skin token (core/SkinSetup.lua's `ct.log.*`) with its Ka0s
-- Default value. A CAST row is plain, with the `ct.log.wash.cd` wash for a spell whose base cooldown is
-- long (Casts.IsLong); BUFF± green (BUFF- dimmed), DEBUFF+ orange with its wash (DEBUFF- dimmed, no
-- wash), DIES red. COLOR-BLIND SAFETY: every kind differs by its tag's text as well as its hue, and
-- `sequence.view.washes` off draws no wash. No who colors: with no Source or Target column they drew
-- nothing, and the owner removed them (SM-CT-LG27, R4-CT-08; schema step 12 drops `sequence.colors`).
-- THE PET'S ROWS (owner feedback round 5, R5-CT-04) carry Spell breakdown's pet marks: a pet's cast names
-- its spell in the pet color (`hud.spells.petColor`, a data hue) and, while `hud.spells.paw` is on, draws
-- the paw between the icon and the name (LogTable_View), so the shape tells it as well as the hue.
--
-- WHAT IS SHOWN is a view's own `show` table, shaped as `sequence.show.*`: each category of
-- CombatLog.CategoryOf on or off, and the auto attacks (Auto Shot, Shoot: no category) off by default.
-- A retired line never shows. What is shown never changes what is captured or saved.
-- THE CHIPS (LogTable.CHIPS: Casts, Pet, Buffs, Debuffs, each over the categories it covers) filter a
-- view's lines. The Results section's open on `sequence.results.chips` and count their lines
-- (modules/Results_Log.lua). The live views' (the detached window's strip under its status line,
-- the docked section's under its heading, shown by default and hidden by its filter mark,
-- `sequence.drawer.chips`) are each view's own `show`, SEEDED from `sequence.show.*` (the What
-- to show page, so `sequence.show` is those chips' defaults) when the view is built, when the section is
-- opened, at each FIGHT_STARTED and at a `sequence.show` write; a click turns every category the chip covers
-- on or off in that view alone for the session (LogTable.ToggleChip), never written to the settings. A
-- chip is lit while any category it covers shows (LogTable.ChipOn).
--
-- THE FEED (a live view over modules/CombatLog.lua's ring). `shown` is the newest sequence number the
-- view has revealed; each repaint tick (NS.Constants.LOG.REPAINT, the view's own timer) moves it toward
-- CombatLog.Seq() by `sequence.view.throttle`:
--   "instant"   every line at the next tick
--   "every"     at most one shown line every `sequence.view.throttleMs` ms (50-1000), a hidden line free
--   "batch"     every queued line together, once every `sequence.view.throttleMs` ms
-- THE THROTTLE ONLY DELAYS THE DISPLAY: the capture and the store never wait on it and drop nothing,
-- and a queue the throttle could not drain before the ring moved past it is skipped to the ring's
-- oldest line. FOLLOW: the view keeps the newest line in view, at the top (`sequence.view.sort` "newest",
-- the default) or the bottom ("oldest"). Scrolling away from it PAUSES: the view holds at the line it
-- was on (`anchor`) however many come in, until Resume or a scroll back to it. A view's rows are the
-- `rows` lines counted from its top line (`anchor` or `shown`), `offset` lines in.
--
-- SECRETS. A line holds plain numbers only. Nothing here compares, counts or stores a secret. Spell
-- names and icons come through C_Spell, pcall'd, from the line's plain spell ID.

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
    [K.DEBUFF_OFF] = L["DEBUFF-"], [K.DIES] = L["DIES"],
}
-- The tag's color token per kind.
LogTable.TAG_COLOR = {
    [K.CAST] = "ct.text", [K.BUFF_ON] = "ct.log.buff", [K.BUFF_OFF] = "ct.log.buffOff",
    [K.DEBUFF_ON] = "ct.log.debuff", [K.DEBUFF_OFF] = "ct.log.debuffOff", [K.DIES] = "ct.log.hit",
}
-- The row wash per kind (a long-cooldown CAST's is decided per spell).
LogTable.WASH = { [K.DEBUFF_ON] = "ct.log.wash.debuff" }
LogTable.CD_WASH = "ct.log.wash.cd"

local FLAG_WORDS = { { F.INTERRUPTED, L["Interrupted"] } }

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
local PET = CL.UNIT.pet
local petHue = {}   -- the pet color as a data hue, refilled per pet row (reused)

-- A pet's cast: Spell breakdown's pet marks (owner feedback round 5, R5-CT-04), the name in the pet
-- color (`hud.spells.petColor`, NS.HudAppearance.Swatch) and the paw while `hud.spells.paw` is on.
local function petMarks(c, e)
    c.paw = false
    if e.k ~= K.CAST or e.u ~= PET then return end
    local A = NS.HudAppearance
    petHue[1], petHue[2], petHue[3] = A.Swatch("spells", "petColor")
    c.spellColor, c.paw = petHue, A.On("hud.spells.paw")
end

-- Spell: the spell's icon and name (blank for a line with no spell, a death).
local function spell(c, e)
    c.icon, c.spellID, c.spellColor = nil, nil, OFF[e.k] and "ct.dim" or "ct.text"
    if e.id then
        c.spellID = e.id
        c.spell = NS.HudBreakdown.SpellName(e.id)
        c.icon = NS.HudBreakdown.SpellIcon(e.id)
    else
        c.spell = ""
    end
    petMarks(c, e)
end

--- Fill `c` (a reused table) with line `e`'s cells: time, tag, tagColor, spell, spellColor (a token, or the
--- pet color's hue on a pet's cast), spellID, icon, paw, info, wash (a token or nil). `ctx`: startT, startClock, timeFormat, washes.
--- @return table c
function LogTable.Cells(e, ctx, c)
    c = c or {}
    c.time = LogTable.Time(e, ctx)
    c.tag, c.tagColor = LogTable.TAG[e.k] or "", LogTable.TAG_COLOR[e.k] or "ct.text"
    spell(c, e)
    c.info = LogTable.Info(e.f)
    local w = LogTable.WASH[e.k]
    if e.k == K.CAST and LogTable.LongCooldown(e.id) then w = LogTable.CD_WASH end
    c.wash = ctx.washes ~= false and w or nil
    return c
end

-- ── what is shown ───────────────────────────────────────────────────────────────────────────────

--- Whether line `e` shows under `show` (`sequence.show`: its categories and autoAttacks). A retired line
--- has no category, so it never shows.
function LogTable.Shows(e, show)
    local cat = CL.CategoryOf(e.k, e.u, e.id)
    if cat == nil then return e.k == K.CAST and show.autoAttacks == true end
    return show[cat] ~= false
end

-- ── the chips ───────────────────────────────────────────────────────────────────────────────────

--- The chips, left to right: their key, their label and the saved categories each one covers (the
--- Results section's and the live views' alike).
LogTable.CHIPS = {
    { key = "casts", label = "Casts", cats = { "casts" } },
    { key = "pet", label = "Pet", cats = { "petCasts" } },
    { key = "buffs", label = "Buffs", cats = { "playerBuffs" } },
    { key = "debuffs", label = "Debuffs", cats = { "playerDebuffs", "targetDebuffs" } },
}
--- Each chip's tooltip line (an L key).
LogTable.CHIP_TIPS = {
    casts = "Your casts.",
    pet = "Your pet's casts.",
    buffs = "Buffs gained and lost on you.",
    debuffs = "Debuffs on you, and the debuffs you put on your target, gained and lost.",
}
--- The line the aura chips and settings add on WoW Forever (R5-CT-07, an L key): its client refuses an
--- addon the auras in combat (docs/forever-quirks.md), so those rows hold only what changed out of it.
LogTable.FOREVER_AURA_NOTE = "WoW Forever hides buffs and debuffs from addons during combat, so these rows show only what changes before the pull and after combat."
-- The chips and the saved categories that note belongs to.
local AURA_KEYS = { buffs = true, debuffs = true, playerBuffs = true, playerDebuffs = true, targetDebuffs = true }

--- The WoW Forever aura note for chip or category `key`, or nil (another key, or Retail).
--- @return string|nil
function LogTable.AuraNote(key)
    if not AURA_KEYS[key] or not NS.Compat.IsForever() then return nil end
    return L[LogTable.FOREVER_AURA_NOTE]
end

--- A chip's tooltip lines after its title: its own line, the WoW Forever aura note where it applies,
--- then `click` (the view's click hint, an L key), into a new table.
--- @return table
function LogTable.ChipTip(title, key, click)
    local tip = { title, L[LogTable.CHIP_TIPS[key]] }
    local note = LogTable.AuraNote(key)
    if note then tip[#tip + 1] = note end
    tip[#tip + 1] = L[click]
    return tip
end
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

--- Whether a write to `path` re-seeds a live view's chips: the log opened (`sequence.drawer.shown`), moved
--- (`sequence.home`), What to show (`sequence.show.*`) or the profile.
--- @return boolean
function LogTable.Reseeds(path)
    return path == "sequence.drawer.shown" or path == "sequence.home" or path == "profile" or path == "sequence.show"
        or path:find("^sequence%.show%.") ~= nil
end

-- ── the live homes' shared reads (the docked drawer and the detached window) ───────────────────

local function setting(path)
    return NS.GetSetting and NS.GetSetting(path)
end

--- The sort a live view draws in: `sequence.view.sort`, "newest" (the default) or "oldest".
function LogTable.SortOf()
    local s = setting("sequence.view.sort")
    return LogTable.SORTS[s] and s or "newest"
end

--- `show` (a reused table) refilled from `sequence.show`, the What to show page: a live view's chips'
--- seed.
function LogTable.ReadShow(show)
    local s = setting("sequence.show")
    for k in pairs(show) do show[k] = nil end
    if type(s) == "table" then for k, v in pairs(s) do show[k] = v end end
    return show
end

--- `ctx` (a reused table) refilled for a live view whose window starts at `startT` (GetTime()): the
--- time format, the clock time of the start and the wash switch.
function LogTable.LiveContext(ctx, startT)
    ctx.startT = startT
    ctx.timeFormat = setting("sequence.view.timeFormat")
    ctx.startClock = nil
    if startT and type(time) == "function" then ctx.startClock = time() - (GetTime() - startT) end
    ctx.washes = setting("sequence.view.washes") ~= false
    return ctx
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

--- The feed's top line: `anchor` while paused, else `shown`.
local function feedTop(feed)
    return math.min(feed.anchor or feed.shown, feed.shown)
end

--- The view's lines: up to `rows` sequence numbers into `out` (newest first), from the feed's top line
--- (`anchor` while paused, else `shown`) down, `offset` shown lines in, none older than `from`
--- (GetTime()). Answers how many, and whether any shown line lies past them (older).
--- @return number n, boolean more
function LogTable.Collect(feed, rows, from, accept, out)
    local n, skip = 0, feed.offset
    for seq = feedTop(feed), CL.First(), -1 do
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

local RING = NS.Constants.LOG.RING

--- How many lines the view holds, from the window's floor `from` up to the feed's top line, each
--- `accept`ed: the scroll indicator's length (owner feedback item 6). KEPT ON THE FEED, never walked
--- whole on a paint: `feed.count` moves on by the lines that arrived since the last count, and
--- `feed.acc[slot]` remembers whether each counted line was accepted, so a line the ring lets go is
--- taken off again. A new floor (each pull, CombatLog.Window), a top that went back (the ring
--- emptied) or a new filter (LogTable.Refilter: a chip, a What to show write) counts again from the
--- floor. Plain counts only; the `acc` slots are reused once the ring has been round.
--- @return number
function LogTable.Count(feed, from, accept)
    local first, top, acc = CL.First(), feedTop(feed), feed.acc
    if not acc then acc = {}; feed.acc = acc end
    if feed.cTop == nil or feed.cFrom ~= from or top < feed.cTop then
        feed.cFrom, feed.count, feed.cLow, feed.cTop = from, 0, first, first - 1
    end
    -- The lines the ring let go since the last count (their slots still hold their marks).
    for seq = feed.cLow, math.min(first - 1, feed.cTop) do
        if acc[(seq - 1) % RING + 1] then feed.count = feed.count - 1 end
    end
    feed.cLow = math.max(feed.cLow, first)
    for seq = math.max(feed.cTop + 1, first), top do
        local e = CL.Line(seq)
        local on = e ~= nil and (from == nil or e.at >= from) and accept(e) == true
        acc[(seq - 1) % RING + 1] = on
        if on then feed.count = feed.count + 1 end
    end
    feed.cTop = top
    return feed.count
end

--- The home's filter changed (its chips, a What to show write): the next LogTable.Count counts again.
function LogTable.Refilter(feed)
    if feed then feed.cTop = nil end
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
