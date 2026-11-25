-- tests/test_log_table.lua — the Combat Log's table and the DPS HUD's docked drawer (CombatTrail #11,
-- plan item CL-11b; the spec's addendum; the owner's feedback of 2026-11-25, CLF-1): the cells each kind
-- of line draws and their color tokens, the school names and colors, a heal's Healing (item 4), the
-- time column, the switches that turn school colors and row washes off; what is shown (the categories,
-- the auto attacks, the least amount, never a sealed one hidden, an old boundary never); the feed
-- (newest first, pause on a scroll and Resume, the display throttle instant / every N ms / batch, which
-- never touches the capture or the saved log); the live view reset at each pull (item 5); the columns
-- laid to a width, no Source or Target, every one centered (items 3 and 8); then the drawer: the Log
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
    return { startT = 100, targetName = "Angry Boar", schoolColors = o.schoolColors, washes = o.washes,
             timeFormat = o.timeFormat, startClock = o.startClock }
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

test("log table: a hit on you is red with its school and Info; a heal green with a plus, reading Healing", function()
    local _, NS = fresh()
    local LT, U, F = NS.LogTable, NS.CombatLog.UNIT, NS.CombatLog.FLAG
    local hit = LT.Cells(line(NS, "HIT", { u = U.player, a = 1234, s = 4, f = F.CRIT }), ctx())
    assertEqual(hit.tag, "HIT")
    assertEqual(hit.wash, "ct.log.wash.hit")
    assertEqual(hit.amountColor, "ct.log.hit")
    assertEqual(hit.spell, "Fire", "the school, the client giving no spell")
    assertEqual(hit.spellColor, "ct.school.fire")
    assertEqual(hit.info, "Critical")
    assertTrue(hit.big, "a critical takes the larger face")
    assertTrue(hit.amount:find("%*$") ~= nil, "and its star: " .. hit.amount)
    local heal = LT.Cells(line(NS, "HEAL", { u = U.player, a = 500, s = 2 }), ctx())
    assertEqual(heal.tag, "HEAL")
    assertEqual(heal.amountColor, "ct.log.heal")
    assertTrue(heal.amount:sub(1, 1) == "+", "a heal reads +: " .. heal.amount)
    assertNil(heal.wash, "a heal has no wash")
    assertEqual(heal.spell, "Healing (Holy)", "a school other than Physical is named")
    assertEqual(heal.spellColor, "ct.log.heal", "in the heal color, not the school's")
    local plain = LT.Cells(line(NS, "HIT", { u = U.player, a = 10, s = 4 }), ctx({ schoolColors = false }))
    assertEqual(plain.spellColor, "ct.text", "school colors off: the body text")
    local glance = LT.Cells(line(NS, "HIT", { u = U.player, a = 10, s = 1, f = F.GLANCING }), ctx())
    assertEqual(glance.info, "Glancing")
    assertFalse(glance.big)
end)

test("log table: a sealed amount goes to the label as given, a saved one reads sealed", function()
    local _, NS = fresh()
    local LT, U = NS.LogTable, NS.CombatLog.UNIT
    local x = T.secret(4321)
    local live = LT.Cells(line(NS, "HIT", { u = U.player, a = NS.CombatLog.SEALED, x = x, s = 1 }), ctx())
    assertTrue(live.amount ~= nil and live.amount ~= "", "the ring's sealed amount reaches the label")
    local saved = LT.Cells({ k = NS.CombatLog.KIND.HIT, u = U.player, t = 3, a = NS.CombatLog.SEALED, s = 1 }, ctx())
    assertEqual(saved.amount, "sealed")
    assertEqual(saved.time, "3.0", "a saved line's own seconds")
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

test("log table: a heal reads Healing, never Physical (item 4)", function()
    -- THE CAUSE (read off the code, CLF-1): UNIT_COMBAT's HEAL reports school 1 (Physical) or nothing,
    -- the capture keeps the client's school as given (CombatLog.OnCombat), and the view drew every HIT
    -- and HEAL's school through LogTable.School, so an ordinary heal read "Physical". The fix is the view's.
    local inst, NS = fresh()
    local LT, U = NS.LogTable, NS.CombatLog.UNIT
    for _, mask in ipairs({ 1, false }) do
        local c = LT.Cells(line(NS, "HEAL", { u = U.player, a = 300, s = mask or nil }), ctx())
        -- red under: "Physical" in the school's color
        assertEqual(c.spell, "Healing", "school " .. tostring(mask))
        assertEqual(c.spellColor, "ct.log.heal")
    end
    assertEqual(LT.Cells(line(NS, "HEAL", { u = U.player, a = 300, s = 1 }), ctx({ schoolColors = false })).spellColor,
        "ct.log.heal", "a heal's color is its kind's, not a school color the switch turns off")
    assertEqual(LT.Cells(line(NS, "HIT", { u = U.player, a = 300, s = 1 }), ctx()).spell, "Physical",
        "a hit still names its school")
    -- End to end: the client's HEAL, school 1, through the capture and into a cell.
    begin(NS, "f1", 100)
    at(inst, 101)
    NS.CombatLog.OnCombat("player", "HEAL", "", 450, 1, 101)
    local e = NS.CombatLog.Line(NS.CombatLog.Seq())
    assertEqual(e.k, NS.CombatLog.KIND.HEAL)
    assertEqual(LT.Cells(e, ctx()).spell, "Healing")
    assertEqual(LT.Cells({ k = NS.CombatLog.KIND.HEAL, u = U.player, t = 2, a = 450, s = 1 }, ctx()).spell, "Healing",
        "a saved heal too")
end)

test("log table: an old boundary line draws no tag and never shows (item 10)", function()
    local _, NS = fresh()
    local LT = NS.LogTable
    assertEqual(LT.Cells(line(NS, "START"), ctx()).tag, "")
    for _, k in ipairs({ "START", "END" }) do
        assertTrue(NS.CombatLog.IsBoundary(line(NS, k)), k)
        assertFalse(LT.Shows(line(NS, k), NS.GetSetting("log.show")), k .. " never shows")
    end
    assertFalse(NS.CombatLog.IsBoundary(line(NS, "CAST")))
end)

test("log table: a multi-school mask takes its lowest school's color", function()
    local _, NS = fresh()
    local s = NS.LogTable.School(20)   -- Frost + Fire
    assertEqual(s.key, "fire")
    assertNil(NS.LogTable.School(0))
end)

-- ── what is shown ───────────────────────────────────────────────────────────────────────────────

test("log table: the categories, the auto attacks and the least amount decide what shows", function()
    local _, NS = fresh()
    local LT, U = NS.LogTable, NS.CombatLog.UNIT
    local show = NS.GetSetting("log.show")
    assertTrue(LT.Shows(line(NS, "CAST", { u = U.player, id = FIREBALL }), show))
    assertFalse(LT.Shows(line(NS, "CAST", { u = U.player, id = AUTO_SHOT }), show), "auto attacks hidden by default")
    assertTrue(LT.Shows(line(NS, "CAST", { u = U.player, id = AUTO_SHOT }), { autoAttacks = true }))
    assertFalse(LT.Shows(line(NS, "CAST", { u = U.pet, id = 17253 }), { petCasts = false }))
    assertFalse(LT.Shows(line(NS, "START"), {}), "an old boundary never shows")
    local min = { minAmount = 100 }
    assertFalse(LT.Shows(line(NS, "HIT", { u = U.player, a = 50 }), min), "under the least amount")
    assertTrue(LT.Shows(line(NS, "HIT", { u = U.player, a = 150 }), min))
    assertTrue(LT.Shows(line(NS, "HIT", { u = U.player, a = "s", x = T.secret(5) }), min),
        "a sealed amount is never compared: it shows")
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

test("log table columns: Time, Event, Spell/School, Amount and Info where there is room; no Source or Target", function()
    local _, NS = fresh()
    local LT = NS.LogTable
    -- red under: Source and Target in the order (owner feedback item 3)
    assertEqual(table.concat(LT.ORDER, ","), "time,event,spell,amount,info")
    assertEqual(keys(LT.Columns(236, {}, false)), "time,event,spell,amount", "the old default HUD's width")
    assertEqual(keys(LT.Columns(500, { source = true, target = true }, false)), "time,event,spell,amount",
        "no Info in the drawer, and an old stored toggle shows nothing")
    assertEqual(keys(LT.Columns(600, {}, true)), "time,event,spell,amount,info")
    assertEqual(keys(LT.Columns(220, {}, true)), "time,event,spell,amount", "too narrow: Info dropped")
    assertEqual(keys(LT.Columns(600, { amount = false }, true)), "time,event,spell,info", "the columns' switches")
    -- The two columns' share is gone from the least width the fixed columns take.
    local fixed = 0
    for key, w in pairs(LT.WIDTH) do if key ~= "info" then fixed = fixed + w end end
    assertEqual(fixed, 38 + 46 + 50, "Time, Event and Amount alone are fixed")
    local cols = LT.Columns(236, {}, false)
    for _, c in ipairs(cols) do
        if c.key == "spell" then assertTrue(c.w >= LT.SPELL_MIN, "Spell/School keeps its least width") end
    end
end)

test("log table columns: every column is centered, its header and its cells, in every home (item 8)", function()
    local _, NS = fresh()
    hudUp(NS)
    NS.HudLog.SetShown(true)
    local views = { NS.HudLog.__ui().table, NS.LogTable.New(NS.Hud.Frame(), { info = true }) }
    for i, view in ipairs(views) do
        view:Layout(600, 3, {})
        for _, key in ipairs(NS.LogTable.ORDER) do
            -- red under: the Amount column justified RIGHT, the others LEFT
            assertEqual(view.heads[key]:GetJustifyH(), "CENTER", "view " .. i .. " header " .. key)
            assertEqual(view:Rows()[1].text[key]:GetJustifyH(), "CENTER", "view " .. i .. " cell " .. key)
        end
    end
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
    assertTrue(NS.GetSetting("log.drawer.shown"), "saved open")
    local d = NS.HudLog.__ui()
    assertTrue(d ~= nil and d.frame:IsVisible(), "the drawer under the spell rows")
    assertEqual(NS.Hud.Height(), before + NS.HudLog.Height(), "the HUD grew by the drawer")
    local chips = NS.LogTable.ChipsHeight(NS.Hud.LogWidth()) + NS.LogTable.CHIP_GAP
    assertEqual(NS.HudLog.Height(), NS.HudLog.GAP + NS.HudLog.HEAD_H + chips + NS.LogTable.Height(10),
        "ten rows by default, under the chips (owner feedback item 16)")
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
    NS.db.profile.log.drawer.rows = 12
    NS.AnnounceSettingsChanged("log.drawer.rows", 12)
    assertEqual(#NS.HudLog.__ui().table:Rows(), 12)
    NS.db.profile.log.drawer.rows = 50
    assertEqual(NS.HudLog.Rows(), 20, "held to 20")
    NS.db.profile.log.drawer.rows = 1
    assertEqual(NS.HudLog.Rows(), 3, "and to 3")
end)

test("hud log: the drawer paints the newest fight's lines, newest at the top, and the Time header flips it", function()
    local inst, NS = fresh()
    hudUp(NS)
    NS.HudLog.SetShown(true)
    begin(NS, "f1", 100)
    NS.CombatLog.OnCast("player", FIREBALL, 101)
    NS.CombatLog.OnCombat("player", "WOUND", "", 2000, 4, 102)
    at(inst, 102.5)
    NS.HudLog.Paint()
    local rows = NS.HudLog.__ui().table:Rows()
    assertEqual(rows[1].text.event:GetText(), "HIT", "the newest at the top")
    assertEqual(rows[2].text.event:GetText(), "CAST")
    -- red under: the PULL row under the fight's first lines (owner feedback item 10)
    assertFalse(rows[3]:IsShown(), "no boundary row")
    local t = NS.HudLog.__ui().table
    click(t.sorter)
    assertEqual(NS.GetSetting("log.view.sort"), "oldest", "the Time header writes the sort")
    NS.HudLog.Paint()
    assertEqual(rows[1].text.event:GetText(), "CAST", "oldest first")
    assertEqual(rows[2].text.event:GetText(), "HIT", "the newest at the bottom")
end)

test("hud log: the chips show by default; the filter mark hides them, the HUD shrinking; a chip filters the drawer alone", function()
    local inst, NS = fresh()
    hudUp(NS)
    NS.HudLog.SetShown(true)
    local d = NS.HudLog.__ui()
    assertEqual(d.filter.iconName, "eye", "the header carries the filter mark")
    -- red under: the chips hidden until the eye is clicked (owner feedback item 9)
    assertTrue(NS.GetSetting("log.drawer.chips"), "on in a new profile")
    assertTrue(NS.HudLog.ChipsShown())
    assertTrue(d.chips.buttons.casts:IsShown(), "the chips row under the heading")
    local h, hud = NS.HudLog.Height(), NS.Hud.Height()
    local room = NS.LogTable.ChipsHeight(NS.Hud.LogWidth()) + NS.LogTable.CHIP_GAP
    click(d.filter)
    assertFalse(NS.GetSetting("log.drawer.chips"), "the eye writes its key")
    assertFalse(d.chips.buttons.casts:IsShown())
    assertEqual(NS.HudLog.Height(), h - room, "the drawer shrank by the chips")
    assertEqual(NS.Hud.Height(), hud - room, "and the HUD with it")
    click(d.filter)
    assertEqual(NS.HudLog.Height(), h, "the mark shows them again")
    begin(NS, "f1", 100)
    NS.CombatLog.OnCast("player", FIREBALL, 101)
    NS.CombatLog.OnCombat("player", "WOUND", "", 2000, 4, 102)
    at(inst, 102.5)
    NS.HudLog.Paint()
    local rows = d.table:Rows()
    assertEqual(rows[1].text.event:GetText(), "HIT")
    click(d.chips.buttons.taken)
    assertEqual(rows[1].text.event:GetText(), "CAST", "hits hidden in the drawer")
    assertTrue(NS.GetSetting("log.show.hits"), "never in the settings")
    assertEqual(d.chips.buttons.taken.styleName, "normal", "the drawer keeps its chips for the session")
    NS.SendBus(NS.MSG.FIGHT_STARTED, { id = "f2", startT = 103 })
    NS.HudLog.Paint()
    assertEqual(d.chips.buttons.taken.styleName, "primary", "a new fight seeds them from log.show")
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
    NS.SetByPath("log.view.sort", "oldest")
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
    assertNil(NS.GetSetting("log.drawer.collapsed"), "no key")
    assertNil(NS.GetSetting("log.drawer.strip"), "and none for the folded line")
    local printed
    local orig = NS.Print
    NS.Print = function(msg) printed = msg end
    NS.Slash:OnSlash("log fold")
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
    assertEqual(d.title:GetText(), "Combat Log")
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
    assertEqual(d.detach.iconName, "export")
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

test("hud log: a fight's start opens it when auto-open is on (the shipped default)", function()
    local _, NS = fresh({ logDrawer = true })
    assertTrue(NS.GetSetting("log.drawer.autoOpen"))
    assertTrue(NS.GetSetting("log.drawer.shown"), "shown by default (owner feedback item 1)")
    assertEqual(NS.defaults.profile.log.drawer.shown, true)
    assertEqual(NS.defaults.profile.log.drawer.rows, 10, "ten rows by default (item 16)")
    NS.HudLog.SetShown(false)
    assertFalse(NS.GetSetting("log.drawer.shown"))
    NS.SendBus(NS.MSG.FIGHT_STARTED, { id = "f9", startT = 100 })
    assertTrue(NS.GetSetting("log.drawer.shown"), "opened at the fight's start")
end)

test("hud log: /ct log toggles it and opens the HUD with it", function()
    local _, NS = fresh()
    assertFalse(NS.Hud.IsShown())
    NS.Slash:OnSlash("log")
    assertTrue(NS.GetSetting("log.drawer.shown"))
    assertTrue(NS.Hud.IsShown(), "the HUD opened with it")
    NS.Slash:OnSlash("log")
    assertFalse(NS.GetSetting("log.drawer.shown"), "toggled closed")
end)

test("hud log: with the Combat Log off there is no control and no drawer", function()
    local _, NS = fresh()
    local ui = hudUp(NS)
    NS.HudLog.SetShown(true)
    NS.db.profile.log.enabled = false
    NS.AnnounceSettingsChanged("log.enabled", false)
    assertFalse(ui.log:IsShown(), "the Log control hidden")
    assertEqual(NS.HudLog.Height(), 0)
    assertFalse(NS.HudLog.__ui().frame:IsShown())
    local found = false
    for _, b in ipairs(ui.header.right) do if b == ui.log then found = true end end
    assertFalse(found, "the strip closed up")
end)
