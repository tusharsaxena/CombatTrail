-- tests/test_log_table.lua — the Combat Sequence's table and the DPS HUD's docked drawer (CombatTrail #11,
-- plan item CL-11b; the spec's addendum; the owner's feedback of 2026-11-25, CLF-1; the Combat Sequence,
-- CSEQ-1): the cells each of the six kinds draws and their color tokens, the washes (DEBUFF+ and a
-- long-cooldown CAST only), Info reading Interrupted alone, the time column, the wash switch; what is
-- shown (the categories, the auto attacks, no amount test, a retired line never); the chips (four, in
-- order, with their categories and tips); the feed
-- (newest first, pause on a scroll and Resume, the display throttle instant / every N ms / batch, which
-- never touches the capture or the saved log); the live view reset at each pull (item 5); the columns
-- laid to a width, no Source, Target or Amount, every one left-aligned (items 3 and round 4); then the drawer: the Log
-- control on the title bar (item 13), the HUD growing by the drawer and back, its section look (items 17
-- and 18), no fold (item 14), the chips on by default (item 9), the rows setting, the Time header's
-- sort, the auto-open at a fight's start, hidden and stopped with the HUD, `/ct log`, and the Combat
-- Log switched off. Runs under both kit profiles.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil = T.test, T.assertEqual, T.assertTrue, T.assertFalse,
    T.assertNil
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local FIREBALL, POLY, INTELLECT, AUTO_SHOT, COMBUST = 133, 118, 1459, 75, 190319

local function fresh(o)
    o = o or {}
    local inst = T.load{ logDrawer = o.logDrawer, mutate = function(m)
        installPaint(m)
        m.__unitExists.target = true
        m.__unitNames.target = "Angry Boar"
        m.UnitCanAttack = function() return true end
        m.GetSpellBaseCooldown = function(id) return id == COMBUST and 120000 or 0 end
        if o.mutate then o.mutate(m) end
    end }
    inst.mocks.__now = 100
    return inst, inst.NS
end

local function at(inst, t) inst.mocks.__now = t end

-- A fight's capture begun at `t` (no meter fight: the ring and the window are the capture's own).
local function begin(NS, id, t)
    NS.CombatLog.Begin(id or "f1", t or 100)
end

local function ctx(o)
    o = o or {}
    return { startT = 100, targetName = "Angry Boar", washes = o.washes, timeFormat = o.timeFormat,
             startClock = o.startClock }
end

local function line(NS, k, fields)
    local e = { k = NS.CombatLog.KIND[k], at = 105 }
    for key, v in pairs(fields or {}) do e[key] = v end
    return e
end

-- ── the cells ───────────────────────────────────────────────────────────────────────────────────

test("log table: a cast is a plain row with its spell, and no cell names a source or a target", function()
    local _, NS = fresh()
    local LT, U = NS.LogTable, NS.CombatLog.UNIT
    local c = LT.Cells(line(NS, "CAST", { u = U.player, id = FIREBALL }), ctx())
    assertEqual(c.tag, "CAST")
    assertEqual(c.tagColor, "ct.text", "a cast row is plain")
    assertEqual(c.spellID, FIREBALL)
    assertNil(c.wash, "no wash for a short cooldown")
    assertEqual(c.time, "5.0", "five seconds from the pull")
    -- red under: the Source and Target cells (owner feedback item 3)
    local p = LT.Cells(line(NS, "CAST", { u = U.pet, id = 17253 }), ctx())
    for _, cell in ipairs({ c, p }) do
        assertNil(cell.source, "no Source cell")
        assertNil(cell.target, "no Target cell")
    end
end)

test("log table: a long-cooldown cast wears the gold wash; washes off takes it away", function()
    local _, NS = fresh()
    local LT, U = NS.LogTable, NS.CombatLog.UNIT
    assertEqual(LT.Cells(line(NS, "CAST", { u = U.player, id = COMBUST }), ctx()).wash, "ct.log.wash.cd")
    assertNil(LT.Cells(line(NS, "CAST", { u = U.player, id = COMBUST }), ctx({ washes = false })).wash)
end)

test("log table: buffs green (off dimmed), a debuff you put on orange with its wash, on the target", function()
    local _, NS = fresh()
    local LT, U = NS.LogTable, NS.CombatLog.UNIT
    local on = LT.Cells(line(NS, "BUFF_ON", { u = U.player, id = INTELLECT }), ctx())
    assertEqual(on.tag, "BUFF+")
    assertEqual(on.tagColor, "ct.log.buff")
    local off = LT.Cells(line(NS, "BUFF_OFF", { u = U.player, id = INTELLECT }), ctx())
    assertEqual(off.tag, "BUFF-")
    assertEqual(off.tagColor, "ct.log.buffOff", "dimmed")
    assertEqual(off.spellColor, "ct.dim")
    local deb = LT.Cells(line(NS, "DEBUFF_ON", { u = U.target, id = POLY }), ctx())
    assertEqual(deb.tag, "DEBUFF+")
    assertEqual(deb.tagColor, "ct.log.debuff")
    assertEqual(deb.wash, "ct.log.wash.debuff")
    local gone = LT.Cells(line(NS, "DEBUFF_OFF", { u = U.target, id = POLY }), ctx())
    assertEqual(gone.tagColor, "ct.log.debuffOff")
    assertNil(gone.wash, "DEBUFF- has no wash")
end)

test("log table: a death is red with a blank spell; Info reads Interrupted and nothing else", function()
    local _, NS = fresh()
    local LT, U, F = NS.LogTable, NS.CombatLog.UNIT, NS.CombatLog.FLAG
    local dies = LT.Cells(line(NS, "DIES", { u = U.player }), ctx())
    assertEqual(dies.tag, "DIES")
    assertEqual(dies.tagColor, "ct.log.hit")
    assertEqual(dies.spell, "", "no spell")
    assertNil(dies.wash)
    local cut = LT.Cells(line(NS, "CAST", { u = U.player, id = FIREBALL, f = F.INTERRUPTED }), ctx())
    assertEqual(cut.info, "Interrupted")
    -- red under: Critical, Glancing or Crushing read off an old saved hit's marks
    assertEqual(LT.Info(1 + 2 + 4), "", "the hits' reserved bits read nothing")
    assertEqual(LT.Info(1 + 8), "Interrupted")
    for _, c in ipairs({ dies, cut }) do
        assertNil(c.amount, "no Amount cell")
        assertNil(c.amountColor)
        assertNil(c.big)
    end
    assertNil(LT.School, "no school")
    assertNil(LT.SCHOOLS)
    assertNil(LT.HealWords)
end)

test("log table: the six tags and their colors; a wash only on DEBUFF+ and a long-cooldown CAST", function()
    local _, NS = fresh()
    local LT, U = NS.LogTable, NS.CombatLog.UNIT
    local want = {
        { "CAST", U.player, FIREBALL, "CAST", "ct.text" }, { "CAST", U.pet, 17253, "CAST", "ct.text" },
        { "BUFF_ON", U.player, INTELLECT, "BUFF+", "ct.log.buff" },
        { "BUFF_OFF", U.player, INTELLECT, "BUFF-", "ct.log.buffOff" },
        { "DEBUFF_ON", U.player, POLY, "DEBUFF+", "ct.log.debuff" },
        { "DEBUFF_OFF", U.target, POLY, "DEBUFF-", "ct.log.debuffOff" },
        { "DIES", U.player, nil, "DIES", "ct.log.hit" },
    }
    for _, w in ipairs(want) do
        local c = LT.Cells(line(NS, w[1], { u = w[2], id = w[3] }), ctx())
        assertEqual(c.tag, w[4], w[1])
        assertEqual(c.tagColor, w[5], w[1])
        assertEqual(c.wash, w[1] == "DEBUFF_ON" and "ct.log.wash.debuff" or nil, w[1] .. "'s wash")
    end
    assertEqual(LT.Cells(line(NS, "CAST", { u = U.player, id = COMBUST }), ctx()).wash, "ct.log.wash.cd")
    local tags = {}
    for _ in pairs(LT.TAG) do tags[#tags + 1] = true end
    assertEqual(#tags, 6, "no HIT or HEAL tag")
    assertNil(LT.TAG[NS.CombatLog.KIND.HIT])
    assertNil(LT.WASH[NS.CombatLog.KIND.HIT], "no hit wash")
end)

test("log table: the time column from the pull, past a minute and before it, or the clock", function()
    local _, NS = fresh()
    local LT = NS.LogTable
    assertEqual(LT.Seconds(12.34), "12.3")
    assertEqual(LT.Seconds(65.3), "1:05.3")
    assertEqual(LT.Seconds(-1.2), "-1.2", "a pre-pull cast")
    local clock = LT.Time({ at = 105 }, ctx({ timeFormat = "clock", startClock = 0 }))
    assertTrue(clock:match("^%d%d:%d%d:%d%d$") ~= nil, "clock time: " .. tostring(clock))
end)

test("log table: an old saved HIT, HEAL, boundary or target BUFF line draws no tag and never shows", function()
    local _, NS = fresh()
    local LT, U = NS.LogTable, NS.CombatLog.UNIT
    local show = NS.GetSetting("sequence.show")
    assertEqual(LT.Cells(line(NS, "START"), ctx()).tag, "")
    assertEqual(LT.Cells({ k = NS.CombatLog.KIND.HIT, u = U.player, t = 3, a = 1234, s = 4 }, ctx()).tag, "")
    for _, e in ipairs({ line(NS, "START"), line(NS, "END"), { k = NS.CombatLog.KIND.HIT, u = U.player, t = 3, a = 9 },
                         { k = NS.CombatLog.KIND.HEAL, u = U.player, t = 4, a = 9, s = 2 },
                         line(NS, "BUFF_ON", { u = U.target, id = 1126 }), line(NS, "BUFF_OFF", { u = U.target, id = 1126 }) }) do
        assertTrue(NS.CombatLog.IsRetired(e), "kind " .. e.k)
        assertFalse(LT.Shows(e, show), "kind " .. e.k .. " never shows")
        assertFalse(LT.Shows(e, { autoAttacks = true }), "however the view is set")
    end
    assertFalse(NS.CombatLog.IsRetired(line(NS, "CAST")))
end)

-- ── what is shown ───────────────────────────────────────────────────────────────────────────────

test("log table: the categories and the auto attacks decide what shows; no amount test", function()
    local _, NS = fresh()
    local LT, U = NS.LogTable, NS.CombatLog.UNIT
    local show = NS.GetSetting("sequence.show")
    assertTrue(LT.Shows(line(NS, "CAST", { u = U.player, id = FIREBALL }), show))
    assertFalse(LT.Shows(line(NS, "CAST", { u = U.player, id = AUTO_SHOT }), show), "auto attacks hidden by default")
    assertTrue(LT.Shows(line(NS, "CAST", { u = U.player, id = AUTO_SHOT }), { autoAttacks = true }))
    assertFalse(LT.Shows(line(NS, "CAST", { u = U.pet, id = 17253 }), { petCasts = false }))
    assertFalse(LT.Shows(line(NS, "START"), {}), "an old boundary never shows")
    assertFalse(LT.Shows(line(NS, "BUFF_ON", { u = U.player, id = INTELLECT }), { playerBuffs = false }))
    assertTrue(LT.Shows(line(NS, "DEBUFF_OFF", { u = U.target, id = POLY }), show), "your debuff falling off the target")
    -- red under: an old stored least amount still hiding a line
    assertTrue(LT.Shows(line(NS, "CAST", { u = U.player, id = FIREBALL, a = 1 }), { minAmount = 100 }),
        "a stray stored minAmount is never read")
    assertNil(show.minAmount, "no least amount in What to show")
end)

test("log table: the chips are four, in order, with their categories and tips", function()
    local _, NS = fresh()
    local LT = NS.LogTable
    local got = {}
    for i, chip in ipairs(LT.CHIPS) do got[i] = chip.key .. "=" .. chip.label .. ":" .. table.concat(chip.cats, "+") end
    -- red under: the Taken and Heals chips (the hits and heals the Combat Sequence drops)
    assertEqual(table.concat(got, ","),
        "casts=Casts:casts,pet=Pet:petCasts,buffs=Buffs:playerBuffs,debuffs=Debuffs:playerDebuffs+targetDebuffs")
    assertEqual(LT.CHIP_TIPS.casts, "Your casts.")
    assertEqual(LT.CHIP_TIPS.pet, "Your pet's casts.")
    assertEqual(LT.CHIP_TIPS.buffs, "Buffs gained and lost on you.")
    assertEqual(LT.CHIP_TIPS.debuffs, "Debuffs on you, and the debuffs you put on your target, gained and lost.")
    assertNil(LT.CHIP_TIPS.taken)
    assertNil(LT.CHIP_TIPS.heals)
end)

-- ── the feed ────────────────────────────────────────────────────────────────────────────────────

local function all() return true end

local function casts(NS, n, t0)
    for i = 1, n do NS.CombatLog.OnCast("player", FIREBALL, (t0 or 100) + i * 0.1) end
end

test("log table feed: instant reveals every line, newest first; a scroll pauses and Resume follows", function()
    local _, NS = fresh()
    local LT, CL = NS.LogTable, NS.CombatLog
    begin(NS)
    local feed = LT.NewFeed()
    casts(NS, 5)
    assertTrue(LT.Advance(feed, 101, "instant", 0, all))
    assertEqual(feed.shown, CL.Seq())
    local out = {}
    local n, more = LT.Collect(feed, 3, 99, all, out)
    assertEqual(n, 3)
    assertTrue(more, "older lines past the rows")
    assertEqual(out[1], CL.Seq(), "the newest first")
    LT.Scroll(feed, 1)
    assertTrue(LT.Paused(feed), "scrolled away: paused")
    local held = feed.anchor
    casts(NS, 4, 102)
    LT.Advance(feed, 102, "instant", 0, all)
    LT.Collect(feed, 3, 99, all, out)
    assertEqual(out[1], held - 1, "paused, the view holds however many come in")
    LT.Resume(feed)
    LT.Collect(feed, 3, 99, all, out)
    assertEqual(out[1], CL.Seq(), "Resume: the newest in view again")
    LT.Scroll(feed, 1)
    LT.Scroll(feed, -1)
    assertFalse(LT.Paused(feed), "scrolled back to the newest: following")
end)

-- The scroll indicator's length (owner feedback item 6), kept on the feed: it must equal a full walk of
-- the window every time, through new lines, a pause, the ring letting old lines go, a new filter and a
-- new floor.
test("log table feed: the view's count moves on with the ring and always equals a full walk", function()
    local inst, NS = fresh()
    local LT, CL = NS.LogTable, NS.CombatLog
    begin(NS)
    local feed = LT.NewFeed()
    local function walk(from, accept)
        local n = 0
        for seq = math.min(feed.anchor or feed.shown, feed.shown), CL.First(), -1 do
            local e = CL.Line(seq)
            if not e or (from and e.at < from) then break end
            if accept(e) then n = n + 1 end
        end
        return n
    end
    local odd = function(e) return e.n % 2 == 1 end
    local filter = all
    local function check(from, msg)
        LT.Advance(feed, inst.mocks.__now, "instant", 0, filter)
        assertEqual(LT.Count(feed, from, filter), walk(from, filter), msg)
    end
    casts(NS, 30)
    check(99, "thirty lines")
    casts(NS, 5, 104)
    check(99, "five more, counted on")
    LT.Scroll(feed, 3)
    casts(NS, 7, 105)
    check(99, "paused: the lines past the anchor are not in the view")
    LT.Resume(feed)
    check(99, "resumed")
    filter = odd
    LT.Refilter(feed)
    check(99, "a new filter counts again")
    for i = 1, NS.Constants.LOG.RING + 300 do NS.CombatLog.OnCast("player", FIREBALL, 106 + i * 0.001) end
    check(99, "past the ring: the lines it let go come off")
    check(106.5, "a new floor counts from it")
    casts(NS, 3, 110)
    check(106.5, "and on from there")
end)

test("log table feed: every N ms shows at most one line each N ms; batch shows them together", function()
    local _, NS = fresh()
    local LT, CL = NS.LogTable, NS.CombatLog
    begin(NS)
    local feed = LT.NewFeed()
    LT.Advance(feed, 100, "every", 500, all)
    casts(NS, 6)
    local saved = CL.Seq()
    LT.Advance(feed, 100.5, "every", 500, all)
    assertEqual(saved - feed.shown, 5, "one line in half a second")
    LT.Advance(feed, 101.5, "every", 500, all)
    assertEqual(saved - feed.shown, 3, "two more in the next second")
    assertEqual(CL.Seq(), saved, "the throttle never touched the capture")
    local batch = LT.NewFeed()
    LT.Advance(batch, 102, "batch", 400, all)
    casts(NS, 3, 102)
    assertFalse(LT.Advance(batch, 102.1, "batch", 400, all), "held until the batch is due")
    assertTrue(LT.Advance(batch, 102.5, "batch", 400, all))
    assertEqual(batch.shown, CL.Seq(), "the queued lines together")
end)

test("log table feed: the display throttle never drops a line from the saved log", function()
    local inst, NS = fresh()
    local LT = NS.LogTable
    local fight = { id = "f1", startT = 100 }
    NS.CombatLog.Begin("f1", 100, fight)
    local feed = LT.NewFeed()
    for i = 1, 12 do
        NS.CombatLog.OnCast("player", FIREBALL, 100 + i * 0.05)
        LT.Advance(feed, 100 + i * 0.05, "every", 1000, all)
    end
    at(inst, 102)
    fight.closedT = 102
    local log = NS.CombatLog.Finish("f1")
    local n = 0
    for _, e in ipairs(log) do if e.k == NS.CombatLog.KIND.CAST then n = n + 1 end end
    assertEqual(n, 12, "every cast saved, whatever the view showed")
    assertTrue(feed.shown < NS.CombatLog.Seq(), "the view was still behind")
end)

local function hudUp(NS)
    NS.Hud.Show()
    return NS.Hud.__ui()
end

local function click(b) b:GetScript("OnClick")(b, "LeftButton") end

-- ── the live view resets at each pull (item 5) ──────────────────────────────────────────────────

test("log table feed: each pull clears the live view to the new fight, keeping its pre-pull floor", function()
    local inst, NS = fresh()
    local LT, CL = NS.LogTable, NS.CombatLog
    local fight1 = { id = "f1", startT = 100 }
    CL.Begin("f1", 100, fight1)
    CL.OnCast("player", FIREBALL, 101)
    CL.OnCast("player", FIREBALL, 105)
    fight1.combatEndT = 110
    at(inst, 111)
    CL.Finish("f1")
    CL.OnCast("player", POLY, 112)     -- after the combat ended: still this fight's view
    local feed, out = LT.NewFeed(), {}
    feed.shown = 0
    LT.Advance(feed, 112, "instant", 0, all)
    local _, from = CL.Window()
    assertEqual(LT.Collect(feed, 20, from, all, out), 3, "the fight's lines, and the one after its end")
    CL.OnCast("player", INTELLECT, 118)  -- two seconds before the next pull: its pre-pull floor
    at(inst, 120)
    CL.Begin("f2", 120, { id = "f2", startT = 120 })
    CL.OnCast("player", FIREBALL, 121)
    LT.Advance(feed, 121, "instant", 0, all)
    local startT
    startT, from = CL.Window()
    assertEqual(startT, 120)
    assertEqual(from, 110, "the floor: PREPULL before the pull, never before the last fight's end")
    local n = LT.Collect(feed, 20, from, all, out)
    local times = {}
    for i = 1, n do times[i] = CL.Line(out[i]).at end
    -- red under: an earlier fight's line (or its END boundary) under the new pull
    assertEqual(table.concat(times, ","), "121,118,112", "the new fight and its pre-pull floor only")
    assertEqual(LT.Time(CL.Line(out[2]), { startT = startT }), "-2.0", "a pre-pull line at a negative time")
end)

-- ── the columns ─────────────────────────────────────────────────────────────────────────────────

local function keys(cols)
    local out = {}
    for _, c in ipairs(cols) do out[#out + 1] = c.key end
    return table.concat(out, ",")
end

test("log table columns: Time, Event, Spell and Info where there is room; no Source, Target or Amount", function()
    local _, NS = fresh()
    local LT = NS.LogTable
    -- red under: Amount in the order (the Combat Sequence: no line carries one)
    assertEqual(table.concat(LT.ORDER, ","), "time,event,spell,info")
    assertEqual(LT.HEADS.spell, "Spell", "the head reads Spell: no row carries a school")
    assertNil(LT.HEADS.amount)
    for _, w in ipairs({ 162, 236, 390, 600, 900 }) do
        for _, info in ipairs({ false, true }) do
            assertTrue(keys(LT.Columns(w, { amount = true }, info)):find("amount") == nil,
                "no Amount at " .. w .. ", even with an old stored toggle")
        end
    end
    assertEqual(keys(LT.Columns(236, {}, false)), "time,event,spell", "the old default HUD's width")
    assertEqual(keys(LT.Columns(500, { source = true, target = true }, false)), "time,event,spell",
        "no Info in the drawer, and an old stored toggle shows nothing")
    assertEqual(keys(LT.Columns(600, {}, true)), "time,event,spell,info")
    assertEqual(keys(LT.Columns(250, {}, true)), "time,event,spell", "too narrow: Info dropped first")
    assertEqual(keys(LT.Columns(600, { spell = false }, true)), "time,event,info", "the columns' switch")
    -- The docked least width: Time, Event, the Spell column's least and two gaps (Amount's share gone).
    local fixed = 0
    for key, w in pairs(LT.WIDTH) do if key ~= "info" then fixed = fixed + w end end
    assertEqual(fixed, 38 + 46, "Time and Event alone are fixed")
    assertEqual(fixed + LT.SPELL_MIN + 2 * LT.COL_GAP, 162, "the docked table's least width")
    local cols = LT.Columns(236, {}, false)
    for _, c in ipairs(cols) do
        if c.key == "spell" then assertTrue(c.w >= LT.SPELL_MIN, "Spell keeps its least width") end
    end
end)

test("log table columns: every column is left-aligned, its header and its cells, in every home (round 4)", function()
    local _, NS = fresh()
    hudUp(NS)
    NS.HudLog.SetShown(true)
    local views = { NS.HudLog.__ui().table, NS.LogTable.New(NS.Hud.Frame(), { info = true }) }
    for i, view in ipairs(views) do
        view:Layout(600, 3, {})
        for _, key in ipairs(NS.LogTable.ORDER) do
            -- red under: a column centered (owner feedback item 8 of the last round) or right-aligned
            assertEqual(view.heads[key]:GetJustifyH(), "LEFT", "view " .. i .. " header " .. key)
            assertEqual(view:Rows()[1].text[key]:GetJustifyH(), "LEFT", "view " .. i .. " cell " .. key)
        end
    end
end)

test("log table columns: the icon is part of the Spell column, its name one character after it (round 4)", function()
    local _, NS = fresh()
    local LT = NS.LogTable
    hudUp(NS)
    assertEqual(LT.IconGap(1), 5, "one character of the 10 pt row font")
    assertEqual(LT.IconGap(1.6), 8, "scaled with the text size")
    for _, size in ipairs({ 10, 16 }) do
        NS.SetByPath("sequence.view.fontSize", size)
        local scale = LT.FontScale()
        local view = LT.New(NS.Hud.Frame(), { info = true })
        view:Layout(600, 3, {})
        local col
        for _, c in ipairs(view.cols) do if c.key == "spell" then col = c end end
        local r, icon = view:Rows()[1], LT.IconSize(view.rowH, scale)
        local _, _, _, ix = r.icon:GetPoint(1)
        local _, _, _, nx = r.text.spell:GetPoint(1)
        assertEqual(ix, col.x, "the icon at the Spell column's left edge, size " .. size)
        assertEqual(nx, col.x + icon + LT.IconGap(scale), "the name one character after the icon, size " .. size)
        local _, _, _, hx = view.heads.spell:GetPoint(1)
        assertEqual(hx, col.x, "the Spell header over the icon, at the column's left edge")
    end
end)

test("log table header: LootHistory's header band, 20 px, in every home (round 4)", function()
    local _, NS = fresh()
    hudUp(NS)
    local LT = NS.LogTable
    -- red under: the 14 px header with no band, which read as plain text
    assertEqual(LT.HEAD_H, 20, "the Results list's and LootHistory's header height")
    local banded, orig = {}, NS.Skin.SortHeaderBar
    NS.Skin.SortHeaderBar = function(bar, ...)
        banded[bar] = true
        return orig(bar, ...)
    end
    local view = LT.New(NS.Hud.Frame(), { info = true })
    NS.Skin.SortHeaderBar = orig
    assertTrue(banded[view.head], "the header frame wears the skin's sort-header band")
    view:Layout(600, 3, {})
    assertEqual(LT.Height(3), 20 + 3 * LT.RowH(), "every home's height counts the taller header")
end)

test("log table header: the Time sort triangle is the skin's arrow, rebuilt on a skin change (round 4)", function()
    local inst, NS = fresh()
    hudUp(NS)
    local LT, Style = NS.LogTable, NS.Style
    local view = LT.New(NS.Hud.Frame(), { info = true })
    view:Layout(600, 3, {})
    local function want(sort)
        local c = Style.Tok("icon.arrow")
        local up = sort == "oldest"
        return LT.HEADS.time .. " " .. Style.IconMarkup(up and "sort-up" or "sort-down",
            up and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up", c)
    end
    view:SetSort("newest")
    assertEqual(view.heads.time:GetText(), want("newest"), "sort-down in the skin's icon.arrow")
    view:SetSort("oldest")
    assertEqual(view.heads.time:GetText(), want("oldest"), "sort-up")
    local Skin = inst.mocks.LibStub("LibKa0s-Skin-1.0")
    local source, skin = Skin:GetChoice("CombatTrail")
    local before = view.heads.time:GetText()
    Skin:SetChoice("CombatTrail", "ka0s", "obsidian")
    assertTrue(view.heads.time:GetText() ~= before, "Obsidian's arrow is not Ka0s Default's")
    assertEqual(view.heads.time:GetText(), want("oldest"), "redrawn in the new skin's arrow")
    Skin:SetChoice("CombatTrail", source, skin)
    assertEqual(view.heads.time:GetText(), want("oldest"), "and back")
end)

-- ── the drawer ──────────────────────────────────────────────────────────────────────────────────

test("hud log: the title bar's Log control opens the drawer and the HUD grows by its height", function()
    local _, NS = fresh()
    local ui = hudUp(NS)
    assertTrue(ui.log ~= nil and ui.log:IsShown(), "the Log control on the title bar")
    -- red under: the chat mark, which read as chat (owner feedback item 13)
    assertEqual(ui.log.iconName, "ph:list-bullets")
    assertTrue(NS.Icon("ph:list-bullets") ~= nil, "vendored and declared")
    local before = NS.Hud.Height()
    assertEqual(NS.HudLog.Height(), 0, "closed: no room taken")
    click(ui.log)
    assertTrue(NS.GetSetting("sequence.drawer.shown"), "saved open")
    local d = NS.HudLog.__ui()
    assertTrue(d ~= nil and d.frame:IsVisible(), "the drawer under the spell rows")
    assertEqual(NS.Hud.Height(), before + NS.HudLog.Height(), "the HUD grew by the drawer")
    assertEqual(NS.HudLog.Height(), NS.HudLog.GAP + NS.HudLog.HEAD_H + NS.LogTable.Height(5),
        "five rows by default (round 4's R4-CT-07), no chips row (R4-CT-04)")
    assertTrue(NS.HudLog.Ticking(), "its repaint timer runs while it shows")
    click(ui.log)
    assertFalse(d.frame:IsShown(), "closed again")
    assertEqual(NS.Hud.Height(), before, "the HUD back to its height")
    assertFalse(NS.HudLog.Ticking(), "and the timer stops")
end)

test("hud log: the rows setting, 3 to 20, sizes the drawer", function()
    local _, NS = fresh()
    hudUp(NS)
    NS.HudLog.SetShown(true)
    NS.db.profile.sequence.drawer.rows = 12
    NS.AnnounceSettingsChanged("sequence.drawer.rows", 12)
    assertEqual(#NS.HudLog.__ui().table:Rows(), 12)
    NS.db.profile.sequence.drawer.rows = 50
    assertEqual(NS.HudLog.Rows(), 20, "held to 20")
    NS.db.profile.sequence.drawer.rows = 1
    assertEqual(NS.HudLog.Rows(), 3, "and to 3")
end)

test("hud log: the drawer paints the newest fight's lines, newest at the top, and the Time header flips it", function()
    local inst, NS = fresh()
    hudUp(NS)
    NS.HudLog.SetShown(true)
    begin(NS, "f1", 100)
    NS.CombatLog.OnCast("player", FIREBALL, 101)
    NS.CombatLog.OnAura("player", { addedAuras = { { auraInstanceID = 7, spellId = INTELLECT, isHelpful = true } } }, 102)
    at(inst, 102.5)
    NS.HudLog.Paint()
    local rows = NS.HudLog.__ui().table:Rows()
    assertEqual(rows[1].text.event:GetText(), "BUFF+", "the newest at the top")
    assertNil(rows[1].text.amount, "no Amount label on a row")
    assertEqual(rows[2].text.event:GetText(), "CAST")
    -- red under: the PULL row under the fight's first lines (owner feedback item 10)
    assertFalse(rows[3]:IsShown(), "no boundary row")
    local t = NS.HudLog.__ui().table
    click(t.sorter)
    assertEqual(NS.GetSetting("sequence.view.sort"), "oldest", "the Time header writes the sort")
    NS.HudLog.Paint()
    assertEqual(rows[1].text.event:GetText(), "CAST", "oldest first")
    assertEqual(rows[2].text.event:GetText(), "BUFF+", "the newest at the bottom")
end)

test("hud log: the chips are hidden by default; the filter mark shows them, the HUD growing; a chip filters the drawer alone", function()
    local inst, NS = fresh()
    hudUp(NS)
    NS.HudLog.SetShown(true)
    local d = NS.HudLog.__ui()
    assertEqual(d.filter.iconName, "eye", "the header carries the filter mark")
    -- red under: the chips shown in a new profile (owner feedback round 4, R4-CT-04)
    assertFalse(NS.GetSetting("sequence.drawer.chips"), "off in a new profile")
    assertFalse(NS.HudLog.ChipsShown())
    assertFalse(d.chips.buttons.casts:IsShown(), "no chips row under the heading")
    local h, hud = NS.HudLog.Height(), NS.Hud.Height()
    local room = NS.LogTable.ChipsHeight(NS.Hud.LogWidth()) + NS.LogTable.CHIP_GAP
    click(d.filter)
    assertTrue(NS.GetSetting("sequence.drawer.chips"), "the eye writes its key")
    assertTrue(d.chips.buttons.casts:IsShown(), "the chips row under the heading")
    assertEqual(NS.HudLog.Height(), h + room, "the drawer grew by the chips")
    assertEqual(NS.Hud.Height(), hud + room, "and the HUD with it")
    click(d.filter)
    assertEqual(NS.HudLog.Height(), h, "the mark hides them again")
    click(d.filter)
    begin(NS, "f1", 100)
    NS.CombatLog.OnCast("player", FIREBALL, 101)
    NS.CombatLog.OnAura("player", { addedAuras = { { auraInstanceID = 7, spellId = INTELLECT, isHelpful = true } } }, 102)
    at(inst, 102.5)
    NS.HudLog.Paint()
    local rows = d.table:Rows()
    assertEqual(rows[1].text.event:GetText(), "BUFF+")
    -- red under: the Taken and Heals chips still built
    assertNil(d.chips.buttons.taken, "no Taken chip")
    assertNil(d.chips.buttons.heals, "no Heals chip")
    click(d.chips.buttons.buffs)
    assertEqual(rows[1].text.event:GetText(), "CAST", "buffs hidden in the drawer")
    assertTrue(NS.GetSetting("sequence.show.playerBuffs"), "never in the settings")
    assertEqual(d.chips.buttons.buffs.styleName, "normal", "the drawer keeps its chips for the session")
    NS.SendBus(NS.MSG.FIGHT_STARTED, { id = "f2", startT = 103 })
    NS.HudLog.Paint()
    assertEqual(d.chips.buttons.buffs.styleName, "primary", "a new fight seeds them from log.show")
end)

test("hud log: the wheel pauses it, Resume follows again", function()
    local inst, NS = fresh()
    hudUp(NS)
    NS.HudLog.SetShown(true)
    begin(NS, "f1", 100)
    for i = 1, 12 do NS.CombatLog.OnCast("player", FIREBALL, 100 + i * 0.1) end
    at(inst, 102)
    NS.HudLog.Paint()
    local d = NS.HudLog.__ui()
    d.table.frame:GetScript("OnMouseWheel")(d.table.frame, -1)
    assertTrue(NS.LogTable.Paused(NS.HudLog.__feed()), "scrolled down, away from the newest: paused")
    assertTrue(d.resume:IsShown(), "Resume shows")
    click(d.resume)
    assertFalse(NS.LogTable.Paused(NS.HudLog.__feed()))
    assertFalse(d.resume:IsShown())
end)

-- Owner feedback item 6: Spell breakdown's scroll indicator on the drawer's rows, the wheel moving it a
-- line a notch, the thumb's share and place plain counts of the lines in view.
test("hud log: the rows carry Spell breakdown's scroll indicator; the wheel moves it a line a notch", function()
    local inst, NS = fresh()
    hudUp(NS)
    NS.HudLog.SetShown(true)
    begin(NS, "f1", 100)
    for i = 1, 4 do NS.CombatLog.OnCast("player", FIREBALL, 100 + i * 0.1) end
    at(inst, 102)
    NS.HudLog.Paint()
    local view = NS.HudLog.__ui().table
    local rows, S = NS.HudLog.Rows(), NS.HudStates
    assertFalse(view.scroll.on, "every line in view: no indicator")
    assertFalse(view.track:IsShown())
    for i = 1, 36 do NS.CombatLog.OnCast("player", FIREBALL, 101 + i * 0.01) end
    at(inst, 103)
    NS.HudLog.Paint()
    local h = rows * NS.LogTable.RowH()
    assertTrue(view.scroll.on and view.track:IsShown() and view.thumb:IsShown(), "40 lines in 10 rows: shown")
    assertEqual(view.scroll.h, h, "as tall as the rows")
    assertEqual(view.scroll.thumbH, math.max(S.THUMB_MIN, math.floor(h * rows / 40 + 0.5)), "the share in view")
    assertEqual(view.scroll.dy, 0, "newest first, following: at the top")
    assertEqual(view.scroll.x, NS.Hud.LogWidth() + S.THUMB_GAP, "in the gutter right of the rows")
    view.frame:GetScript("OnMouseWheel")(view.frame, -1)
    assertEqual(NS.HudLog.__feed().offset, 1, "one line a notch, as Spell breakdown")
    assertEqual(view.scroll.dy, math.floor((h - view.scroll.thumbH) * 1 / (40 - rows) + 0.5), "a line down")
    for _ = 1, 60 do view.frame:GetScript("OnMouseWheel")(view.frame, -1) end
    assertEqual(view.scroll.dy, h - view.scroll.thumbH, "the oldest page: at the bottom")
    NS.SetByPath("sequence.view.sort", "oldest")
    NS.HudLog.Paint()
    assertEqual(view.scroll.dy, 0, "oldest first, the oldest page is the top")
end)

test("hud log: no fold: no chevron, no folded line, no key, no verb (item 14)", function()
    local _, NS = fresh()
    hudUp(NS)
    NS.HudLog.SetShown(true)
    local d = NS.HudLog.__ui()
    -- red under: the header's chevron and the one-line strip
    assertNil(d.fold, "no chevron on the heading")
    assertNil(d.strip, "no folded line")
    assertNil(NS.HudLog.Collapsed, "no fold state")
    assertNil(NS.GetSetting("sequence.drawer.collapsed"), "no key")
    assertNil(NS.GetSetting("sequence.drawer.strip"), "and none for the folded line")
    local printed
    local orig = NS.Print
    NS.Print = function(msg) printed = msg end
    NS.Slash:OnSlash("sequence fold")
    NS.Print = orig
    assertTrue(printed ~= nil and printed:find("Usage") ~= nil, "fold is no verb now: the usage")
    assertTrue(printed:find("fold") == nil, "and the usage names no fold")
    assertTrue(d.table.frame:IsShown(), "the table stays")
end)

test("hud log: the drawer is a section like Spell breakdown: its heading, its count and marks, no seam (items 17, 18)", function()
    local inst, NS = fresh()
    local Style = NS.Style
    hudUp(NS)
    NS.HudLog.SetShown(true)
    begin(NS, "f1", 100)
    NS.CombatLog.OnCast("player", FIREBALL, 101)
    at(inst, 101.5)
    NS.HudLog.Paint()
    local d = NS.HudLog.__ui()
    -- red under: the 10px list-header title and the gold seam above it
    assertEqual(d.title.__template, Style.FONT.SECTION, "the sections' gold heading face")
    assertEqual(d.title:GetText(), "Combat Sequence")
    local function tipOf(b) return type(b.tip) == "table" and b.tip[1] or b.tip end
    assertEqual(tipOf(d.filter), "Show or hide the Combat Sequence's filter chips")
    assertEqual(tipOf(d.detach), "Detach the Combat Sequence into its own window")
    assertEqual(tipOf(NS.Hud.__ui().log), "Combat Sequence", "the title bar control's tip")
    assertNil(d.seam, "no separator or seam")
    assertEqual(NS.HudLog.HEAD_H, NS.HudStates.SECTION_H, "the sections' heading line")
    assertEqual(NS.HudLog.GAP, NS.HudStates.HEAD_GAP, "the sections' clear space over the heading")
    assertEqual(d.count.__template, Style.FONT.CAPTION, "the dim meta text")
    assertEqual(d.count:GetText(), "1 shown")
    local point, rel, relPoint = d.count:GetPoint(1)
    assertEqual(point .. "/" .. relPoint, "BOTTOMRIGHT/BOTTOMLEFT", "on the heading's bottom edge, as Spell breakdown's note")
    assertTrue(rel == d.title)
    -- The marks rest in the title bar's tint and light in its hover color, at its size.
    for _, b in ipairs({ d.filter, d.detach }) do
        local r, g, bl = b.icon:GetVertexColor()
        assertEqual(("%.2f,%.2f,%.2f"):format(r, g, bl), ("%.2f,%.2f,%.2f"):format(Style.REST[1], Style.REST[2], Style.REST[3]),
            b.iconName .. " at rest")
        b:GetScript("OnEnter")(b)
        r, g, bl = b.icon:GetVertexColor()
        assertEqual(("%.2f,%.2f,%.2f"):format(r, g, bl), ("%.2f,%.2f,%.2f"):format(Style.HOT[1], Style.HOT[2], Style.HOT[3]),
            b.iconName .. " under the pointer")
        b:GetScript("OnLeave")(b)
    end
    assertEqual(d.detach.iconName, "chevron-right")
end)

test("hud log: it hides and stops with the HUD, and comes back with it", function()
    local _, NS = fresh()
    hudUp(NS)
    NS.HudLog.SetShown(true)
    local d = NS.HudLog.__ui()
    NS.Hud.Hide()
    assertFalse(NS.Hud.Frame():IsShown(), "never up while the HUD is hidden: it is the HUD's child")
    assertTrue(d.hud == NS.Hud.Frame(), "the drawer is a child of the HUD's window")
    assertFalse(NS.HudLog.Ticking(), "no repaint while hidden")
    NS.Hud.Show()
    assertTrue(NS.Hud.Frame():IsShown() and d.frame:IsShown(), "back with the HUD")
    assertTrue(NS.HudLog.Ticking())
end)

test("hud log: a fight's start leaves a closed drawer closed (LG22: the open at the pull is the HUD's)", function()
    local _, NS = fresh({ logDrawer = true })
    assertTrue(NS.GetSetting("sequence.drawer.shown"), "shown by default (owner feedback item 1)")
    assertEqual(NS.defaults.profile.sequence.drawer.shown, true)
    assertEqual(NS.defaults.profile.sequence.drawer.rows, 5, "five rows by default (R4-CT-07)")
    NS.HudLog.SetShown(false)
    assertFalse(NS.GetSetting("sequence.drawer.shown"))
    NS.SendBus(NS.MSG.FIGHT_STARTED, { id = "f9", startT = 100 })
    assertFalse(NS.GetSetting("sequence.drawer.shown"), "the section no longer reopens itself")
end)

test("hud log: /ct sequence toggles it and opens the HUD with it", function()
    local _, NS = fresh()
    assertFalse(NS.Hud.IsShown())
    NS.Slash:OnSlash("sequence")
    assertTrue(NS.GetSetting("sequence.drawer.shown"))
    assertTrue(NS.Hud.IsShown(), "the HUD opened with it")
    NS.Slash:OnSlash("sequence")
    assertFalse(NS.GetSetting("sequence.drawer.shown"), "toggled closed")
end)

test("hud log: with the Combat Log off there is no control and no drawer", function()
    local _, NS = fresh()
    local ui = hudUp(NS)
    NS.HudLog.SetShown(true)
    NS.db.profile.sequence.enabled = false
    NS.AnnounceSettingsChanged("sequence.enabled", false)
    assertFalse(ui.log:IsShown(), "the Log control hidden")
    assertEqual(NS.HudLog.Height(), 0)
    assertFalse(NS.HudLog.__ui().frame:IsShown())
    local found = false
    for _, b in ipairs(ui.header.right) do if b == ui.log then found = true end end
    assertFalse(found, "the strip closed up")
end)
