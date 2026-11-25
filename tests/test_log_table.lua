-- tests/test_log_table.lua — the Combat Log's table and the DPS HUD's docked drawer (CombatTrail #11,
-- plan item CL-11b; the spec's addendum): the cells each kind of line draws and their color tokens
-- (the player's class color and the HUD's pet color reused), the school names and colors, the time
-- column, the switches that turn school colors and row washes off; what is shown (the categories, the
-- auto attacks, the least amount, never a sealed one hidden); the feed (newest first, pause on a
-- scroll and Resume, the display throttle instant / every N ms / batch, which never touches the
-- capture or the saved log); the columns laid to a width; then the drawer: the Log control on the
-- title bar, the HUD growing by the drawer and back, the fold to one line with the newest event, the
-- rows setting, the Time header's sort, the auto-open at a fight's start, hidden and stopped with the
-- HUD, `/ct log`, and the Combat Log switched off. Runs under both kit profiles.

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

test("log table: a cast is yours in your class color, a pet's in the HUD's pet color", function()
    local _, NS = fresh()
    local LT, U = NS.LogTable, NS.CombatLog.UNIT
    local c = LT.Cells(line(NS, "CAST", { u = U.player, id = FIREBALL }), ctx())
    assertEqual(c.tag, "CAST")
    assertEqual(c.tagColor, "ct.text", "a cast row is plain")
    assertEqual(c.source, "You")
    local r, g, b = NS.ClassColor("player")
    if r then
        assertTrue(type(c.sourceColor) == "table" and c.sourceColor[1] == r and c.sourceColor[2] == g
            and c.sourceColor[3] == b, "You: the class color the HUD's class rows draw")
    end
    assertEqual(c.target, NS.LogTable.DASH, "the client names no target for a cast")
    assertEqual(c.spellID, FIREBALL)
    assertNil(c.wash, "no wash for a short cooldown")
    assertEqual(c.time, "5.0", "five seconds from the pull")
    local p = LT.Cells(line(NS, "CAST", { u = U.pet, id = 17253 }), ctx())
    local pet = NS.HudAppearance.PetColor()
    assertEqual(p.source, "Pet")
    assertTrue(p.sourceColor[1] == pet.r and p.sourceColor[2] == pet.g and p.sourceColor[3] == pet.b,
        "the pet: the HUD's own pet color, not a copy")
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
    assertEqual(on.target, "You", "a buff on you")
    assertEqual(on.source, LT.DASH)
    local off = LT.Cells(line(NS, "BUFF_OFF", { u = U.player, id = INTELLECT }), ctx())
    assertEqual(off.tag, "BUFF-")
    assertEqual(off.tagColor, "ct.log.buffOff", "dimmed")
    assertEqual(off.spellColor, "ct.dim")
    local deb = LT.Cells(line(NS, "DEBUFF_ON", { u = U.target, id = POLY }), ctx())
    assertEqual(deb.tag, "DEBUFF+")
    assertEqual(deb.tagColor, "ct.log.debuff")
    assertEqual(deb.wash, "ct.log.wash.debuff")
    assertEqual(deb.source, "You", "a debuff on the target is one you put on")
    assertEqual(deb.target, "Angry Boar")
    assertEqual(deb.targetColor, "ct.log.hostile", "a target you can attack")
    local gone = LT.Cells(line(NS, "DEBUFF_OFF", { u = U.target, id = POLY }), ctx())
    assertEqual(gone.tagColor, "ct.log.debuffOff")
    assertNil(gone.wash, "DEBUFF- has no wash")
    local friendly = ctx()
    friendly.targetFriendly = true
    assertEqual(LT.Cells(line(NS, "BUFF_ON", { u = U.target, id = 1126 }), friendly).targetColor, "ct.log.friendly")
end)

test("log table: a hit on you is red with its school and Info; a heal green with a plus", function()
    local _, NS = fresh()
    local LT, U, F = NS.LogTable, NS.CombatLog.UNIT, NS.CombatLog.FLAG
    local hit = LT.Cells(line(NS, "HIT", { u = U.player, a = 1234, s = 4, f = F.CRIT }), ctx())
    assertEqual(hit.tag, "HIT")
    assertEqual(hit.wash, "ct.log.wash.hit")
    assertEqual(hit.amountColor, "ct.log.hit")
    assertEqual(hit.source, LT.DASH, "the client gives no source")
    assertEqual(hit.target, "You")
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
    assertEqual(heal.spellColor, "ct.school.holy")
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

test("log table: the boundaries are muted rows with their words", function()
    local _, NS = fresh()
    local LT = NS.LogTable
    local s = LT.Cells(line(NS, "START"), ctx())
    assertEqual(s.tag, "PULL")
    assertEqual(s.tagColor, "ct.dim")
    assertEqual(s.spell, "Fight started")
    assertEqual(LT.Cells(line(NS, "END"), ctx()).spell, "Combat ended")
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
    assertTrue(LT.Shows(line(NS, "START"), { casts = false }), "a boundary always shows")
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

-- ── the columns ─────────────────────────────────────────────────────────────────────────────────

local function keys(cols)
    local out = {}
    for _, c in ipairs(cols) do out[#out + 1] = c.key end
    return table.concat(out, ",")
end

test("log table columns: a narrow home drops Source first; a wide one with Info shows them all", function()
    local _, NS = fresh()
    local LT = NS.LogTable
    assertEqual(keys(LT.Columns(236, {}, false)), "time,event,spell,amount", "the default HUD's width")
    assertEqual(keys(LT.Columns(296, {}, false)), "time,event,target,spell,amount", "a wider HUD keeps Target")
    assertEqual(keys(LT.Columns(500, {}, false)), "time,event,source,target,spell,amount", "no Info in the drawer")
    assertEqual(keys(LT.Columns(600, {}, true)), "time,event,source,target,spell,amount,info")
    assertEqual(keys(LT.Columns(600, { source = false, amount = false }, true)), "time,event,target,spell,info",
        "the columns' switches")
    local cols = LT.Columns(236, {}, false)
    for _, c in ipairs(cols) do
        if c.key == "spell" then assertTrue(c.w >= LT.SPELL_MIN, "Spell/School keeps its least width") end
    end
end)

-- ── the drawer ──────────────────────────────────────────────────────────────────────────────────

local function hudUp(NS)
    NS.Hud.Show()
    return NS.Hud.__ui()
end

local function click(b) b:GetScript("OnClick")(b, "LeftButton") end

test("hud log: the title bar's Log control opens the drawer and the HUD grows by its height", function()
    local _, NS = fresh()
    local ui = hudUp(NS)
    assertTrue(ui.log ~= nil and ui.log:IsShown(), "the Log control on the title bar")
    assertEqual(ui.log.iconName, "chat")
    local before = NS.Hud.Height()
    assertEqual(NS.HudLog.Height(), 0, "closed: no room taken")
    click(ui.log)
    assertTrue(NS.GetSetting("log.drawer.shown"), "saved open")
    local d = NS.HudLog.__ui()
    assertTrue(d ~= nil and d.frame:IsVisible(), "the drawer under the spell rows")
    assertEqual(NS.Hud.Height(), before + NS.HudLog.Height(), "the HUD grew by the drawer")
    assertEqual(NS.HudLog.Height(), NS.HudLog.GAP + NS.HudLog.SEAM + NS.HudLog.HEAD_H + NS.LogTable.Height(8),
        "eight rows by default")
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
    assertEqual(rows[3].text.event:GetText(), "PULL", "the fight's start under its first lines")
    local t = NS.HudLog.__ui().table
    click(t.sorter)
    assertEqual(NS.GetSetting("log.view.sort"), "oldest", "the Time header writes the sort")
    NS.HudLog.Paint()
    assertEqual(rows[1].text.event:GetText(), "PULL", "oldest first")
    assertEqual(rows[3].text.event:GetText(), "HIT", "the newest at the bottom")
end)

test("hud log: the filter mark opens the drawer's chips, the HUD growing by them; a chip filters the drawer alone", function()
    local inst, NS = fresh()
    hudUp(NS)
    NS.HudLog.SetShown(true)
    local d = NS.HudLog.__ui()
    assertEqual(d.filter.iconName, "eye", "the header carries the filter mark")
    assertFalse(d.chips.buttons.casts:IsShown(), "the chips start hidden: the drawer keeps its height")
    local h, hud = NS.HudLog.Height(), NS.Hud.Height()
    click(d.filter)
    assertTrue(NS.HudLog.ChipsShown())
    assertTrue(d.chips.buttons.casts:IsShown(), "the chips row under the header")
    local room = NS.LogTable.ChipsHeight(NS.Hud.LogWidth()) + NS.LogTable.CHIP_GAP
    assertEqual(NS.HudLog.Height(), h + room, "the drawer grew by the chips")
    assertEqual(NS.Hud.Height(), hud + room, "and the HUD with it")
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
    NS.HudLog.SetCollapsed(true)
    assertFalse(NS.HudLog.ChipsShown(), "folded: no chips row")
    NS.HudLog.SetCollapsed(false)
    click(d.filter)
    assertEqual(NS.HudLog.Height(), h, "the mark hides them again")
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

test("hud log: folded it is one line with the newest event, and the HUD shrinks to it", function()
    local inst, NS = fresh()
    hudUp(NS)
    NS.HudLog.SetShown(true)
    local open = NS.Hud.Height()
    begin(NS, "f1", 100)
    NS.CombatLog.OnCast("player", FIREBALL, 101)
    at(inst, 101.5)
    local d = NS.HudLog.__ui()
    click(d.fold)
    assertTrue(NS.GetSetting("log.drawer.collapsed"), "saved folded")
    assertEqual(NS.HudLog.Height(), NS.HudLog.GAP + NS.HudLog.SEAM + NS.HudLog.HEAD_H + NS.LogTable.ROW_H)
    assertTrue(NS.Hud.Height() < open, "the HUD shrank with it")
    assertFalse(d.table.frame:IsShown(), "the table folded away")
    NS.HudLog.Paint()
    assertEqual(d.strip:Rows()[1].text.event:GetText(), "CAST", "the one line: the newest event")
    assertEqual(d.fold.iconName, "chevron-down")
    click(d.fold)
    assertEqual(NS.Hud.Height(), open, "unfolded: back to its height")
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
    NS.Slash:OnSlash("log fold")
    assertTrue(NS.HudLog.Collapsed())
    NS.Slash:OnSlash("log unfold")
    assertFalse(NS.HudLog.Collapsed())
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
