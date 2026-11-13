-- tests/test_race_window_board.lua — the race board's figures on the Race window (race window redesign
-- plan Tasks W6 and W7, modules/RaceWindow_Board.lua): the best's straight line at the race clock (Best
-- by now) and at each quarter (the Checkpoints), Against your best's rows and their diffs, Top races'
-- ranks (Bests.Ranked, this race's row under the top three), the idle body's Top races, the two
-- tables' one column grid, the section headings in the DPS HUD's face, the countdown's color over
-- the race (ClockColor), and the layout's fit: every body's stack under the window's own content
-- height, a taller (matched) window only growing the space above the running body's Cancel, and the
-- result card spreading its tables into it (Spread). Retail only: the Race window is absent on WoW
-- Forever.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local F = dofile(T.root .. "/tests/race_fixture.lua")(T)
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local function forever() return T.NS.Compat.IsForever() end

-- A fresh instance with the kit's paint recorder (distinct font strings and textures).
local function fresh(opts)
    opts = opts or {}
    local mutate = opts.mutate
    opts.mutate = function(m)
        installPaint(m)
        if mutate then mutate(m) end
    end
    local S = F.fresh(opts)
    assert(S.NS.SetByPath("race.autoShow", false))
    S.NS.RaceWindow.HideAwayFromDummy()
    return S
end

local function body(S)
    local ui = S.NS.RaceWindow.__ui()
    return ui and ui.body[ui.current] or nil
end

local WHO = { name = "Aella", realm = "Realm", client = "retail", specID = 71, specName = "Arms", ilvl = 316.8 }

-- A stored race in the record's shape (plain numbers), on the single-target 1:00 board.
local function race(id, t, score, opts)
    opts = opts or {}
    local who = {}
    for k, v in pairs(WHO) do who[k] = v end
    if opts.ilvl then who.ilvl = opts.ilvl end
    local length = opts.length or 60
    return { id = id, t = t, status = "final", who = who, identity = {},
             race = { kind = "single", length = length, status = opts.status or "complete", score = score,
                      dps = score / (opts.endedAt or length), endedAt = opts.endedAt, flags = {} } }
end

-- ── the best's straight line ───────────────────────────────────────────────────────────────────

test("race window board: Best by now and the Checkpoints read the best's straight line", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local B = NS.RaceWindowBoard
    local line = NS.HudBest.RaceCurve(race("best", 1, 22020000))
    assertEqual(B.ByNow(line, 40), 14680000, "22.02M over 1:00, at 0:40")
    local cps = B.Checkpoints(line, 40)
    local want = { 5505000, 11010000, 16515000, 22020000 }
    for i, cp in ipairs(cps) do
        F.near(cp.damage, want[i], "checkpoint " .. i)
        assertEqual(cp.t, 15 * i, "at each quarter of the length")
    end
    assertTrue(cps[1].passed and cps[2].passed, "0:15 and 0:30 are behind the clock")
    assertFalse(cps[3].passed)
    assertTrue(cps[3].next, "0:45 is the next one")
    assertFalse(cps[4].next, "one next only")
    assertEqual(B.ByNow(line, 75), 22020000, "held at the score past the buzzer")
    local done = B.Checkpoints(line, 60)
    for i = 1, 4 do assertFalse(done[i].next, "the buzzer: nothing left") end
end)

-- ── Against your best ──────────────────────────────────────────────────────────────────────────

test("race window board: Against your best sets this race beside the best before it", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local C = NS.HudStates.COLORS
    local best = race("best", 1000, 22020000)
    local mine = race("mine", 2000, 11060000, { ilvl = 318.3 })
    local rows = NS.RaceWindowBoard.Compare(mine, best)
    assertEqual(#rows, 4)
    local labels = {}
    for i, r in ipairs(rows) do labels[i] = r.cells[1] end
    assertEqual(table.concat(labels, ","), "Score,DPS,Item level,Date", "no time raced row (owner, 2026-11-13)")
    assertEqual(rows[1].cells[2], "11.06M")
    assertEqual(rows[1].cells[3], "22.02M")
    assertEqual(rows[1].cells[4], "-10.96M", "the score's diff, signed")
    assertTrue(rows[1].colors[4] == C.red, "behind: red")
    assertEqual(rows[2].cells[4], NS.Format.SignedPct((11060000 / 22020000 - 1) * 100), "the DPS diff in percent")
    assertEqual(rows[3].cells[4], "+1.5", "item level")
    assertTrue(rows[3].colors[4] == C.green, "above: green")
    assertEqual(rows[4].cells[4], "", "the date has no diff")
    local level = NS.RaceWindowBoard.Compare(race("level", 3000, 22020000), best)
    assertTrue(level[1].colors[4] == C.dim, "level: dim")
    -- Ahead of it.
    local ahead = NS.RaceWindowBoard.Compare(race("fast", 3000, 23000000), best)
    assertEqual(ahead[1].cells[4], "+980.0K")
    assertTrue(ahead[2].colors[4] == C.green)
end)

test("race window board: an incomplete race's shorter time shows on its chips, not in the table", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local best = race("best", 1000, 22020000)
    local short = race("short", 3000, 9000000, { status = "incomplete", endedAt = 41 })
    short.race.flags = { incomplete = true }
    local compare = NS.RaceWindowBoard.Compare(short, best)
    assertEqual(#compare, 4)
    local chips = NS.RaceWindowStates.ResultChips({ race = short.race, record = short, isNew = false,
                                                    delta = -50, compare = compare })
    local texts = {}
    for i, c in ipairs(chips) do texts[i] = c.text end
    local all = table.concat(texts, " | ")
    assertTrue(all:find("Time " .. NS.Format.RaceTime(short.race), 1, true) ~= nil, "the Time chip: " .. all)
    assertTrue(all:find("vs best", 1, true) == nil, "Against your best has the DPS Diff: " .. all)
    -- With no Against your best to carry it, the behind chip still says so.
    local alone = NS.RaceWindowStates.ResultChips({ race = short.race, record = short, isNew = false, delta = -50 })
    assertEqual(alone[1].text, "-50.0% vs best")
    -- A new best keeps its mark beside the table.
    local fast = race("fast", 3000, 23000000)
    local won = NS.RaceWindowStates.ResultChips({ race = fast.race, record = fast, isNew = true, delta = 4.5,
                                                  compare = NS.RaceWindowBoard.Compare(fast, best) })
    assertEqual(won[1].text, "New best +4.5%")
end)

-- ── one grid, the DPS HUD's headings ──────────────────────────────────────────────────────────────

test("race window board: Against your best and Top races stand on one column grid", function()
    if forever() then return end
    local S = fresh()
    local B, f = S.NS.RaceWindowBoard, S.M.CreateFrame("Frame")
    local compare, board = B.NewCompare(f), B.NewBoard(f)
    for _, width in ipairs({ 236, 300 }) do
        local a, b = compare:Grid(width), board:Grid(width)
        assertEqual(#a, 4)
        for i = 1, 4 do
            assertEqual(a[i].x, b[i].x, "column " .. i .. "'s left edge at " .. width)
            assertEqual(a[i].w, b[i].w, "column " .. i .. "'s width at " .. width)
        end
        assertEqual(a[1].w, B.LEAD_W)
    end
end)

test("race window board: every section heading is the DPS HUD's", function()
    if forever() then return end
    local S = fresh()
    local RW = S.NS.RaceWindow
    local SECTION = S.NS.Style.FONT.SECTION
    assertEqual(S.NS.RaceWindowBoard.CAPTION_H, S.NS.Style.SECTION_H)
    F.whole(S, 30)
    RW.Show()
    local w = body(S).w
    assertEqual(w.againstCap.title.__template, SECTION, "Against your best")
    assertEqual(w.boardCap.title.__template, SECTION, "Top races")
    assertEqual(w.boardCap.title:GetText(), "Top races")
    RW.Act.newRace()
    w = body(S).w
    for _, fs in ipairs({ w.lengthCap, w.targetCap, w.best.caption, w.boardCap.title }) do
        assertEqual(fs.__template, SECTION, tostring(fs:GetText()))
    end
    assertEqual(w.boardCap.title:GetText(), "Top races")
end)

-- ── the countdown's color ─────────────────────────────────────────────────────────────────────

test("race window board: the countdown turns green to yellow to red over the race", function()
    if forever() then return end
    local S = fresh()
    local B, C = S.NS.RaceWindowBoard, S.NS.HudStates.COLORS
    local function is(c, r, g, b) return math.abs(r - c[1]) < 1e-9 and math.abs(g - c[2]) < 1e-9 and math.abs(b - c[3]) < 1e-9 end
    assertTrue(is(C.green, B.ClockColor(60, 60)), "0%: green")
    assertTrue(is(C.green, B.ClockColor(30, 60)), "50%: still green")
    -- Half the race to 10 s left is the blend: its midpoint (20 s left of 1:00) is the yellow.
    assertTrue(is(C.amber, B.ClockColor(20, 60)), "the blend's midpoint: yellow")
    local r, g = B.ClockColor(25, 60)
    assertTrue(r > C.green[1] and g ~= C.green[2] and not is(C.amber, B.ClockColor(25, 60)), "between: a blend")
    assertTrue(is(C.red, B.ClockColor(10, 60)), "10 s left: red")
    assertTrue(is(C.red, B.ClockColor(10.05, 60)), "the countdown shows 0:10.0: red with it")
    assertFalse(is(C.red, B.ClockColor(10.1, 60)), "0:10.1: not yet")
    assertTrue(is(C.red, B.ClockColor(0, 60)), "0 s left: red")
    -- A race whose green half runs into the last 10 s: green, then red wins.
    assertTrue(is(C.green, B.ClockColor(14, 15)), "0:15, 1 s in: green")
    assertTrue(is(C.green, B.ClockColor(10.5, 15)), "0:15, 10.5 s left: green")
    assertTrue(is(C.red, B.ClockColor(10, 15)), "0:15, 10 s left: red, though under half the race")
    assertTrue(is(C.red, B.ClockColor(5, 15)), "0:15, 5 s left: red")
end)

-- ── Top races ──────────────────────────────────────────────────────────────────────────────────

test("race window board: Top races ranks the board's races, this one's row under the top three", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    local list = {
        race("a", 100, 20000000), race("b", 200, 22000000), race("c", 300, 19000000),
        race("d", 400, 18000000), race("e", 500, 21000000),
        race("other", 600, 30000000, { length = 30 }),                         -- another board
        race("lost", 700, 99000000, { status = "incomplete", endedAt = 20 }),   -- counts on no board
    }
    local mine = list[4]
    local ranked = NS.Bests.Ranked(mine, list)
    local ids = {}
    for i, r in ipairs(ranked) do ids[i] = r.id end
    assertEqual(table.concat(ids, ","), "b,e,a,c,d", "the board's races, best race DPS first")
    local rows = NS.RaceWindowBoard.Rows(mine, ranked)
    assertEqual(#rows, 4, "the top three and this race")
    assertEqual(rows[1].record.id, "b")
    assertEqual(rows[4].rank, 5, "this race's rank")
    assertTrue(rows[4].me)
    assertFalse(rows[1].me == true)
    assertEqual(rows[4].cells[1], "5")
    assertEqual(rows[4].cells[2], "18.00M")
    -- In the top three: its own row, highlighted, and nothing after.
    local top = NS.RaceWindowBoard.Rows(list[1], ranked)
    assertEqual(#top, 3)
    assertTrue(top[3].me, "third")
    -- Not counted (incomplete): the top three alone, and no row of its own.
    local alone = NS.RaceWindowBoard.Rows(list[7], NS.Bests.Ranked(list[7], list))
    assertEqual(#alone, 3, "an incomplete race is not on its board's list")
    for _, r in ipairs(alone) do assertFalse(r.me == true) end
    -- A race the records do not hold yet joins its own list.
    local fresh1 = race("new", 800, 25000000)
    assertEqual(NS.Bests.Ranked(fresh1, list)[1].id, "new")
    assertEqual(NS.RaceWindowBoard.Note("single", 60, "Arms"),
        NS.Dummies.Label("single") .. " \194\183 1:00 \194\183 Arms")
end)

test("race window board: the result card's Top races ranks a race outside the top three", function()
    if forever() then return end
    local S = fresh()
    local RW = S.NS.RaceWindow
    RW.Show()
    -- Four races on one board, each slower than the last: the fourth is outside the top three.
    local later = os.time()
    local dmg = { 2000000, 1800000, 1600000, 1400000 }
    for i, d in ipairs(dmg) do
        later = later + 100
        local at = later
        S.M.time = function() return at end
        local t0 = 100 + (i - 1) * 100
        assertTrue(F.arm(S, 30, t0))
        local start = F.pull(S, t0 + 1, 24 + i, { damage = d, dps = d / 30, duration = 31,
                                                 spells = { { id = 133, dmg = d, dps = d / 30 } } })
        F.damage(S, 24 + i, start + 1, start + 30, 1)
        F.settle(S, start + 31)
        if i < #dmg then RW.Act.newRace() end
    end
    assertEqual(S.NS.Race.State(), "result")
    local w = body(S).w
    local rows = w.board:Texts()
    assertEqual(#rows, 4, "the top three and this race")
    assertEqual(rows[4]:sub(1, 2), "4|")
    assertEqual(w.board:Highlighted(), 4)
    assertTrue(w.againstCap.title:IsShown(), "an earlier best: Against your best")
    assertEqual(RW.View().prev.race.score, 2000000, "the best before it")
    local note = w.boardCap.note:GetText()
    assertTrue(note:find(S.NS.Format.Length(30), 1, true) ~= nil, note)
end)

-- ── the idle body ──────────────────────────────────────────────────────────────────────────────

test("race window board: the idle body shows Top races only once the board has races", function()
    if forever() then return end
    local S = fresh()
    local RW = S.NS.RaceWindow
    RW.Show()
    RW.Act.pickLength(30)
    local w = body(S).w
    assertNil(RW.View().board, "no race on the board")
    assertFalse(w.boardCap.title:IsShown())
    assertEqual(#w.board:Texts(), 0)
    local armAlone = w.arm
    RW.Show()
    F.whole(S, 30)
    RW.Act.newRace()
    assertEqual(S.NS.Race.State(), "idle")
    w = body(S).w
    assertTrue(w.arm == armAlone, "the same body")
    assertTrue(w.boardCap.title:IsShown(), "Top races under Your best")
    local rows = w.board:Texts()
    assertEqual(#rows, 1)
    assertEqual(rows[1]:sub(1, 2), "1|")
    assertNil(w.board:Highlighted(), "no race of its own to mark")
    RW.Act.pickLength(60)
    assertFalse(w.boardCap.title:IsShown(), "another length, another board")
end)

-- ── the layout's fit ───────────────────────────────────────────────────────────────────────────

test("race window board: every body's stack fits the window's own content height", function()
    if forever() then return end
    local S = fresh()
    local St, A = S.NS.RaceWindowStates, S.NS.HudAppearance
    for _, mode in ipairs({ "left", "elapsed", "both" }) do
        assertTrue(St.RunningNeed(mode) <= St.CONTENT_H, mode .. ": " .. St.RunningNeed(mode) .. " > " .. St.CONTENT_H)
    end
    -- The largest clock the Appearance rows offer (32).
    S.NS.db.profile.hud.clock.fontSize = 32
    A.Changed()
    assertTrue(St.RunningNeed("left") <= St.CONTENT_H, "the largest clock still fits")
    assertTrue(St.RESULT_H <= St.CONTENT_H, "the result card, two lines of chips")
    -- At its own height the result card never spreads below its least.
    local rowH, gap = St.ResultLayout(St.CONTENT_H, 46 + 8 + 41 + 8, 4, 4)
    assertTrue(rowH >= S.NS.RaceWindowBoard.ROW_H and gap >= 8, rowH .. "/" .. gap)
end)

test("race window board: Spread grows the rows, then the gaps, each to its cap", function()
    if forever() then return end
    local S = fresh()
    local B = S.NS.RaceWindowBoard
    local rowH, gap = B.Spread(0, 10, 3, 8)
    assertEqual(rowH, B.ROW_H)
    assertEqual(gap, 8, "no spare: the stack at its least")
    rowH, gap = B.Spread(76, 10, 3, 8)
    assertEqual(rowH, B.ROW_H + 3, "half the spare at most to the rows")
    assertEqual(gap, 8 + math.floor((76 - 30) / 3), "the rest over the gaps")
    rowH, gap = B.Spread(1000, 10, 3, 8)
    assertEqual(rowH, B.ROW_MAX)
    assertEqual(gap, B.GAP_MAX, "the rest stays above the buttons")
    rowH, gap = B.Spread(-20, 10, 3, 8)
    assertEqual(rowH, B.ROW_H, "a short content: never under the least")
    assertEqual(gap, 8)
end)

-- Every frame records its anchors: the kit's keep none (the paint recorder's regions keep their own).
local function tracked()
    return fresh({ mutate = function(m)
        local function track(r)
            rawset(r, "__points", {})
            rawset(r, "ClearAllPoints", function(self) rawset(self, "__points", {}) end)
            rawset(r, "SetPoint", function(self, ...)
                local list = rawget(self, "__points")
                list[#list + 1] = { ... }
            end)
            return r
        end
        local create = m.CreateFrame
        m.CreateFrame = function(...) return track(create(...)) end
    end })
end

local function topOf(region) return region.__points[1] and region.__points[1][5] end

test("race window board: a taller window keeps the stack's top, spreads its gaps and keeps the buttons at the foot", function()
    if forever() then return end
    local S = tracked()
    local RW = S.NS.RaceWindow
    F.whole(S, 30)
    RW.Act.newRace()
    assertTrue(F.arm(S, 30, 200))
    local start = F.pull(S, 201, 26)
    F.damage(S, 26, start + 1, start + 10, 1)
    F.run(S, start + 10)
    RW.Show()
    RW.Attach("TOP")
    RW.Refresh()
    local w = body(S).w
    local own = RW.View().height
    local cell = w.cps.cells[1]
    local y = topOf(cell)
    local bestY = topOf(w.best.caption)
    local gap = body(S).gap
    assertTrue(type(y) == "number", "the checkpoints are placed")
    assertTrue(-y + S.NS.RaceWindowBoard.CP_H + 8 + S.NS.Style.BUTTON_H <= own, "the stack ends above Cancel")
    RW.Attach("RIGHT")
    RW.Refresh()
    assertTrue(RW.View().height > own, "matched: the HUD's taller height")
    assertEqual(topOf(w.best.caption), bestY, "the stack starts where it did")
    assertTrue(body(S).gap >= gap and body(S).gap <= S.NS.RaceWindowBoard.GAP_MAX, "its gaps grow, to their cap")
    assertEqual(topOf(cell), y - 2 * (body(S).gap - gap), "the checkpoints two grown gaps lower")
    local p = w.cancel.__points
    local anchored = false
    for _, pt in ipairs(p) do
        if pt[1] == "BOTTOMLEFT" and pt[2] == body(S).frame and pt[3] == "BOTTOMLEFT" then anchored = true end
    end
    assertTrue(anchored, "Cancel pinned to the body's foot, which fills the content")
end)

test("race window board: a taller window spreads the result card's tables down to its buttons", function()
    if forever() then return end
    local S = tracked()
    local RW = S.NS.RaceWindow
    local B = S.NS.RaceWindowBoard
    F.whole(S, 30)
    RW.Show()
    RW.Attach("TOP")
    RW.Refresh()
    local b = body(S)
    local St = S.NS.RaceWindowStates
    assertEqual(S.NS.Race.State(), "result")
    local own = RW.View().height
    local rowH, gap = St.ResultLayout(own, b.w.chips:Bottom(), 0, 1)
    assertEqual(b.rowH, rowH, "the card's rows as ResultLayout spreads them")
    assertEqual(b.gap, gap)
    S.NS.Hud.Height = function() return own + 300 end
    RW.Attach("RIGHT")
    RW.Refresh()
    assertTrue(RW.View().height > own, "matched: the HUD's taller height")
    assertEqual(b.rowH, B.ROW_MAX, "a far taller window: the rows at their cap")
    assertEqual(b.gap, B.GAP_MAX, "and the gaps at theirs")
    assertEqual(b.w.boardCap.title.__points[1][5], -(b.w.chips:Bottom() - 8 + B.GAP_MAX), "Top races a capped gap down")
    -- A fuller card at the window's own height, then a taller one: the rows and gaps grow with it.
    local r1, g1 = St.ResultLayout(St.CONTENT_H, 46 + 8 + 18 + 8, 4, 4)
    local r2, g2 = St.ResultLayout(St.CONTENT_H + 60, 46 + 8 + 18 + 8, 4, 4)
    assertTrue(r2 >= r1 and g2 >= g1 and (r2 > r1 or g2 > g1), r1 .. "/" .. g1 .. " -> " .. r2 .. "/" .. g2)
end)

-- ── the running body's colors, rows and mini pace bars (owner, 2026-11-13) ─────────────────────

-- A session of `damage`, for the DPS HUD's live read to answer.
local function session(damage)
    return { damage = damage, dps = damage / 30, duration = 31, spells = { { id = 348, dmg = damage, dps = damage / 30 } } }
end

-- A 0:30 race against a board best, run to 0:05 with the HUD reading `damage`: the running body.
local function running(S, damage)
    local RW = S.NS.RaceWindow
    F.whole(S, 30)
    RW.Act.newRace()
    assertTrue(F.arm(S, 30, 200))
    local start = F.pull(S, 201, 26, session(damage or 1000000))
    F.damage(S, 26, start + 1, start + 5, 1)
    RW.Show()
    RW.Refresh()
    assertEqual(S.NS.Race.State(), "running")
    return body(S), start
end

local function sameColor(fs, c, what)
    local r, g, b = fs:GetTextColor()
    assertTrue(r == c[1] and g == c[2] and b == c[3],
        ("%s: %s,%s,%s, not %s,%s,%s"):format(what, tostring(r), tostring(g), tostring(b), c[1], c[2], c[3]))
end

test("race window board: Best by now and the Checkpoints draw the best in blue, Current in white, labels in muted gold", function()
    if forever() then return end
    local S = fresh()
    local B, Style = S.NS.RaceWindowBoard, S.NS.Style
    local b, start = running(S)
    local w = b.w
    F.damage(S, 26, start + 6, start + 8, 1)
    S.NS.RaceWindow.Refresh()
    assertEqual(B.BEST_C.token, "ct.info", "the skin's blue")
    assertEqual(B.CURRENT_C.token, "ct.text", "the skin's text white")
    assertEqual(B.LABEL_C.token, "text.headingAlt", "the skin's muted gold")
    local blue, white, gold = Style.Tok("ct.info"), Style.Tok("ct.text"), Style.Tok("text.headingAlt")
    assertFalse(blue[1] == white[1] and blue[3] == white[3], "three distinct hues under the default skin")
    assertFalse(gold[3] == white[3])
    assertEqual(w.now.bestLabel:GetText(), "Best")
    assertEqual(w.now.youLabel:GetText(), "Current", "You renamed Current")
    sameColor(w.now.bestLabel, gold, "the Best label")
    sameColor(w.now.youLabel, gold, "the Current label")
    sameColor(w.now.value, blue, "Best by now's best")
    sameColor(w.now.you, white, "Best by now's Current")
    assertEqual(w.cps.cap.note:GetText(), "best \194\183 current")
    for i, cell in ipairs(w.cps.cells) do
        sameColor(cell.time, gold, "checkpoint " .. i .. "'s time")
        sameColor(cell.value, blue, "checkpoint " .. i .. "'s best")
        sameColor(cell.you, white, "checkpoint " .. i .. "'s Current")
    end
    assertTrue(w.cps.cells[1].passed, "0:07.5 is behind the clock")
    assertEqual(w.cps.cells[1].value:GetAlpha(), B.PASSED_A, "a passed best dims, its blue kept")
    assertEqual(w.cps.cells[2].value:GetAlpha(), 1)
end)

test("race window board: a checkpoint reads time, best, Current, then its mini bar; Best by now's bar sits over its card", function()
    if forever() then return end
    local S = tracked()
    local B = S.NS.RaceWindowBoard
    local b = running(S)
    local w = b.w
    local cw = math.floor((b.width - 3 * B.CP_GAP) / 4)
    for i, cell in ipairs(w.cps.cells) do
        local tY, vY, yY = cell.time.__points[1][5], cell.value.__points[1][5], cell.you.__points[1][5]
        assertEqual(cell.time.__points[1][2], cell, "each line anchored to its cell")
        assertEqual(cell.time.__points[1][1], "TOP", "the time is the top row")
        assertTrue(tY > vY and vY > yY, ("checkpoint %d: time %d, best %d, Current %d"):format(i, tY, vY, yY))
        local pace = cell.pace
        local pt = pace.bar.__points[1]
        assertEqual(pt[2], cell, "the bar stands on its cell (a plain frame)")
        assertTrue(pt[5] < yY - 10, "the bar is the bottom row")
        assertTrue(-pt[5] + B.CP_PACE_H <= B.CP_H, "inside the cell")
        assertEqual(pace.barW, math.floor(cw * B.CP_PACE_SHARE), "three quarters of the cell")
        assertEqual(pt[4], math.floor((cw - pace.barW) / 2), "centered")
        assertNil(pace.track, "no track")
        local _, _, _, a = pace.behind:GetStatusBarColor()
        assertEqual(a, 0, "no behind fill: only the red shortfall and the green grow from the tick")
    end
    local now = w.now
    local barY, cardY = now.pace.bar.__points[1][5], now.card.__points[1][5]
    assertEqual(now.pace.bar.__points[1][2], b.frame, "on the body's content frame")
    assertTrue(barY > cardY and barY - B.NOW_PACE_LINE + 2 == cardY, "the bar's line just above the card")
    assertEqual(now.pace.barW, b.width, "the card's full width")
    assertTrue(now.pace.track ~= nil and now.pace.tick ~= nil, "the HUD's track and tick")
    assertTrue(B.NOW_PACE_H < S.NS.HudChart.PACE_H - 4, "thinner than the HUD's")
end)

test("race window board: the mini pace bars take Current through SetValue on plain Bounds; a checkpoint's waits for its capture", function()
    if forever() then return end
    local S = fresh()
    local NS = S.NS
    assertTrue(NS.SetByPath("hud.paceRange", 1.2))
    local b, start = running(S)
    local w = b.w
    local function rangeIs(pace, ref, what)
        local lo, hi = NS.HudBest.Bounds(ref)
        local blo, bmid = pace.behind:GetMinMaxValues()
        local alo, ahi = pace.ahead:GetMinMaxValues()
        assertTrue(type(blo) == "number" and type(ahi) == "number", what .. ": a plain range")
        F.near(blo, ref * 0.8, what .. ": the HUD's Pace range")
        assertTrue(blo == lo and bmid == (lo + hi) / 2 and alo == bmid and ahi == hi, what .. ": HudBest.Bounds, split at the tick")
    end
    for i = 1, 4 do assertFalse(w.cps.cells[i].pace.bar:IsShown(), "checkpoint " .. i .. ": no bar before its capture") end
    assertEqual(w.now.pace.behind:GetValue(), 1000000, "Current to both halves")
    assertTrue(w.now.pace.behind:IsShown() and w.now.pace.ahead:IsShown())
    -- In combat: the reading is secret, the bars take it as it is, the range stays plain.
    S.meter.SetSecret(true)
    F.damage(S, 26, start + 6, start + 8, 1)
    NS.RaceWindow.Refresh()
    local v = NS.RaceWindow.View()
    assertTrue(T.isSecret(w.now.pace.behind:GetValue()) and T.isSecret(w.now.pace.ahead:GetValue()), "Best by now's bar: the secret")
    rangeIs(w.now.pace, v.byNow, "Best by now")
    local cell = w.cps.cells[1]
    assertTrue(cell.pace.bar:IsShown(), "0:07.5 captured: its bar shows")
    assertTrue(T.isSecret(cell.pace.behind:GetValue()) and T.isSecret(cell.pace.ahead:GetValue()), "the captured secret")
    rangeIs(cell.pace, v.checkpoints[1].damage, "the first checkpoint")
    for i = 2, 4 do assertFalse(w.cps.cells[i].pace.bar:IsShown(), "checkpoint " .. i .. " not reached") end
    S.meter.SetSecret(false)
end)

-- Every frame under `f` and every region of each, for an anchor survey.
local function under(f, out)
    out[#out + 1] = f
    for _, r in ipairs({ f:GetRegions() }) do out[#out + 1] = r end
    for _, c in ipairs({ f:GetChildren() }) do under(c, out) end
    return out
end

test("race window board: nothing on the running body is anchored to a bar that took the reading", function()
    if forever() then return end
    local S = tracked()
    S.meter.SetSecret(false)
    local b = running(S)
    local all = under(b.frame, {})
    local bars = {}
    for _, o in ipairs(all) do
        if rawget(o, "__frameType") == "StatusBar" then
            bars[o] = o
            bars[o:GetStatusBarTexture()] = o
        end
    end
    local n, inner = 0, 0
    for _, o in ipairs(all) do
        local points = rawget(o, "__points") or {}
        local rels = {}
        for _, pt in ipairs(points) do rels[#rels + 1] = pt[2] end
        if rawget(o, "__allPoints") then rels[#rels + 1] = rawget(o, "__allPoints") end
        for _, rel in ipairs(rels) do
            n = n + 1
            local bar = bars[rel]
            if bar then
                -- The HUD's own technique inside one bar: its red shortfall hangs off its fill.
                assertEqual(rawget(o, "__owner"), bar, "only a bar's own shortfall is anchored to it")
                inner = inner + 1
            end
        end
    end
    assertTrue(n > 40, "the survey saw the body's anchors: " .. n)
    assertEqual(inner, 2 * 5, "each of the five mini bars' shortfall, to its fill and its half")
end)

-- ── any size: the grip's widths and heights (owner, 2026-11-13) ────────────────────────────────

-- Every frame records its anchors and its sizes (the kit's keep neither).
local function sized()
    return fresh({ mutate = function(m)
        local function track(r)
            rawset(r, "__points", {})
            rawset(r, "ClearAllPoints", function(self) rawset(self, "__points", {}) end)
            rawset(r, "SetPoint", function(self, ...)
                local list = rawget(self, "__points")
                list[#list + 1] = { ... }
            end)
            local setW, setH, setSize = r.SetWidth, r.SetHeight, r.SetSize
            rawset(r, "SetWidth", function(self, w) rawset(self, "__w", w); return setW(self, w) end)
            rawset(r, "SetHeight", function(self, h) rawset(self, "__h", h); return setH(self, h) end)
            rawset(r, "SetSize", function(self, w, h)
                rawset(self, "__w", w); rawset(self, "__h", h)
                return setSize(self, w, h)
            end)
            return r
        end
        local create = m.CreateFrame
        m.CreateFrame = function(...) return track(create(...)) end
    end })
end

-- The window `width` wide, on its own height (`taller` px over it) at TOP, or matched at RIGHT to a
-- HUD `taller` px over its least.
local function shape(S, width, taller, matched)
    local RW = S.NS.RaceWindow
    RW.Show()
    assertTrue(S.NS.SetByPath("raceWindow.width", width))
    local least = RW.Height()
    if matched then
        S.NS.Hud.Height = function() return least + taller end
        RW.Attach("RIGHT")
    else
        assertTrue(S.NS.SetByPath("raceWindow.height", least + taller))
        RW.Attach("TOP")
    end
    RW.Refresh()
    local v = RW.View()
    assertEqual(v.width, RW.Width() - 24, "the view's width")
    assertEqual(body(S).width, v.width, "the body's width follows it")
    return body(S), v
end

local SHAPES = { { 260, 0 }, { 400, 0 }, { 260, 160, true }, { 400, 160, true }, { 400, 240 } }

local function shapeName(s) return ("%dx+%d%s"):format(s[1], s[2], s[3] and " matched" or "") end

local function left(r) return r.__points[1][4] end
local function top(r) return -r.__points[1][5] end

-- A row of regions inside 0..width, in order, none over the next.
local function rowFits(list, width, what)
    local x = 0
    for i, r in ipairs(list) do
        local l, w = left(r), r.__w
        assertTrue(type(w) == "number" and w > 0, what .. " " .. i .. ": sized")
        assertTrue(l >= x and l + w <= width, ("%s %d: %d+%d in %d (after %d)"):format(what, i, l, w, width, x))
        x = l + w
    end
end

test("race window board: the running body fills every size without clipping or overlap", function()
    if forever() then return end
    for _, s in ipairs(SHAPES) do
        local S = sized()
        local St, B = S.NS.RaceWindowStates, S.NS.RaceWindowBoard
        local b, v = (function()
            running(S)
            return shape(S, s[1], s[2], s[3])
        end)()
        local w, name = b.w, shapeName(s)
        rowFits(w.cps.cells, b.width, name .. " checkpoint")
        rowFits(w.chips:Items(), b.width, name .. " chip")
        local chipsEnd = w.chips:Bottom()
        local bestTop = top(w.best.caption)
        local nowTop, cpsTop = top(w.now.cap.title), top(w.cps.cap.title)
        assertEqual(bestTop, chipsEnd, name .. ": Best to beat under the chips")
        assertTrue(bestTop + St.BEST_CAPTION_H + St.BEST_CARD_H <= nowTop, name .. ": Best by now under it")
        assertTrue(nowTop + B.CAPTION_H + B.NOW_PACE_LINE + B.NOW_H <= cpsTop, name .. ": the Checkpoints under that")
        local cpsEnd = cpsTop + B.CAPTION_H + B.CP_H
        assertTrue(cpsEnd + 2 + S.NS.Style.BUTTON_H <= v.height, name .. ": clear of Cancel, " .. cpsEnd .. " in " .. v.height)
        assertTrue(b.gap >= 8 and b.gap <= B.GAP_MAX, name .. ": the gaps at their least or grown to the cap " .. b.gap)
        if s[2] > 0 then assertTrue(b.gap > 8, name .. ": a taller window spreads the gaps") end
        assertEqual(w.now.pace.barW, b.width, name .. ": Best by now's bar the full width")
    end
end)

test("race window board: two lines of running chips at the largest clock still clear Cancel", function()
    if forever() then return end
    local S = sized()
    local St, B = S.NS.RaceWindowStates, S.NS.RaceWindowBoard
    S.NS.db.profile.hud.clock.fontSize = 32
    S.NS.HudAppearance.Changed()
    running(S)
    -- A chip too wide to sit beside the board's at the least width (a shared session's, worded long).
    local chipsOf = St.RunningChips
    St.RunningChips = function(r)
        local list = chipsOf(r)
        list[#list + 1] = { text = S.NS.L["Shared session"] .. " (an earlier pull)", color = St.FLAG_COLOR }
        return list
    end
    local b, v = shape(S, 260, 0)
    assertEqual(b.w.chips.lines, 2, "the second chip wraps at the least width: " .. table.concat(b.w.chips:Texts(), "|"))
    assertTrue(St.RunningNeed("left", 2) > St.CONTENT_H, "at GAP it would clip: " .. St.RunningNeed("left", 2))
    assertTrue(St.RunningFloor("left", 2) + 4 <= St.CONTENT_H, "the gaps give way instead, with slack: "
        .. St.RunningFloor("left", 2) .. " of " .. St.CONTENT_H)
    assertTrue(b.gap < 8 and b.gap >= 2, "compressed: " .. b.gap)
    local cpsEnd = top(b.w.cps.cap.title) + B.CAPTION_H + B.CP_H
    assertTrue(cpsEnd + b.gap + S.NS.Style.BUTTON_H <= v.height, cpsEnd .. " in " .. v.height)
    -- Wider, the chips go back to one line and the gaps open up again.
    local tight = b.gap
    b, v = shape(S, 400, 0)
    assertEqual(b.w.chips.lines, 1)
    assertEqual(b.gap, St.RunningGap(v.height, b.w.chips:Bottom()))
    assertTrue(b.gap >= 8 and b.gap > tight, "one line: " .. b.gap)
end)

test("race window board: the idle body fills every size, its gaps and Top races' rows spread in a taller one", function()
    if forever() then return end
    for _, s in ipairs(SHAPES) do
        local S = sized()
        local B = S.NS.RaceWindowBoard
        F.whole(S, 30)
        S.NS.RaceWindow.Act.newRace()
        local b, v = shape(S, s[1], s[2], s[3])
        local w, at, name = b.w, b.at, shapeName(s)
        assertEqual(S.NS.RaceWindow.__ui().current, "idle")
        rowFits({ w.presets[1], w.presets[2], w.presets[3] }, b.width, name .. " preset")
        assertTrue(w.board.shown[1] ~= nil, name .. ": Top races shows")
        assertEqual(top(w.targetCap), at.target)
        assertEqual(top(w.card.frame), at.card)
        assertEqual(top(w.best.caption), at.best)
        assertEqual(top(w.boardCap.title), at.board)
        assertEqual(top(w.arm), at.arm)
        assertTrue(at.card + 46 <= at.best and at.best + 60 <= at.board, name .. ": in order")
        assertTrue(at.board + B.SectionHeight(B.TOP_N, at.rowH) < at.arm, name .. ": Arm Race under Top races")
        assertTrue(at.bottom <= v.height, name .. ": " .. at.bottom .. " in " .. v.height)
        assertTrue(at.gap <= B.GAP_MAX and at.rowH <= B.ROW_MAX, name .. ": capped")
        if s[2] > 0 then assertTrue(at.gap > 8 or at.rowH > B.ROW_H, name .. ": a taller window spreads") end
    end
end)

test("race window board: the result and Stop! bodies' buttons and chips follow the width", function()
    if forever() then return end
    for _, width in ipairs({ 260, 400 }) do
        local S = sized()
        F.whole(S, 30)
        local b = shape(S, width, 0)
        assertEqual(S.NS.RaceWindow.__ui().current, "result")
        rowFits(b.footer, b.width, width .. " result button")
        local last = b.footer[#b.footer]
        assertTrue(left(last) + last.__w >= b.width - 4, width .. ": the row spans the width")
        rowFits(b.w.chips:Items(), b.width, width .. " result chip")
        assertEqual(b.w.board:Grid(b.width)[4].x + b.w.board:Grid(b.width)[4].w <= b.width, true)
    end
end)

test("race window board: the Stop! and waiting bodies add the Checkpoints, all four by the buzzer, when they fit", function()
    if forever() then return end
    for _, width in ipairs({ 260, 400 }) do
        local S = sized()
        local B = S.NS.RaceWindowBoard
        F.whole(S, 30)
        S.NS.RaceWindow.Act.newRace()
        shape(S, width, 0)
        assertTrue(F.arm(S, 30, 200))
        local start = F.pull(S, 201, 26, session(1000000))
        F.damage(S, 26, start + 1, start + 30, 1)
        S.NS.RaceWindow.Refresh()
        assertEqual(S.NS.RaceWindow.__ui().current, "stop")
        local b, v = body(S), S.NS.RaceWindow.View()
        assertTrue(b.cpsShown, width .. ": Stop! shows the Checkpoints")
        for i = 1, 4 do
            assertTrue(v.checkpoints[i].passed, width .. ": checkpoint " .. i .. " passed by the buzzer")
            assertTrue(v.checkpoints[i].hasYou, width .. ": checkpoint " .. i .. " captured")
            assertTrue(b.w.cps.cells[i].pace.bar:IsShown(), width .. ": its mini bar")
        end
        rowFits(b.w.cps.cells, b.width, width .. " stop checkpoint")
        rowFits(b.footer, b.width, width .. " stop button")
        local cpsTop = top(b.w.cps.cap.title)
        assertTrue(cpsTop >= b.noteBottom, width .. ": under the note")
        assertTrue(cpsTop + B.CAPTION_H + B.CP_H + 8 + S.NS.Style.BUTTON_H <= v.height, width .. ": clear of the buttons")
        assertTrue(b.shownKey:find(tostring(b.width), 1, true) ~= nil, width .. ": the chips re-wrap on a resize")
        F.run(S, start + 33)
        S.NS.RaceWindow.Refresh()
        assertEqual(S.NS.RaceWindow.__ui().current, "waiting")
        b = body(S)
        assertTrue(b.cpsShown, width .. ": waiting shows them too")
        assertTrue(top(b.w.cps.cap.title) + B.CAPTION_H + B.CP_H + 8 + S.NS.Style.BUTTON_H <= S.NS.RaceWindow.View().height)
        rowFits(b.footer, b.width, width .. " waiting button")
    end
end)

-- ── the running body's look, round 5 (owner, 2026-11-13) ───────────────────────────────────────

test("race window board: the time bar is the DPS HUD's pace bar's look: no border, its track, height and tick", function()
    if forever() then return end
    local S = sized()
    local St, Chart, Style = S.NS.RaceWindowStates, S.NS.HudChart, S.NS.Style
    local b = running(S)
    local bar = b.w.bar
    assertNil(bar.track:GetBackdrop(), "no border")
    local track = S.M.__paint(bar.bg)
    local want = Style.Tok("ct.pace.track")
    assertTrue(track.color and track.color[1] == want[1] and track.color[4] == want[4], "the pace bar's track")
    assertEqual(bar.track.__h, Chart.PACE_H - 4, "the pace bar's height")
    assertEqual(top(bar.track), St.RunningTop(S.NS.GetSetting("race.clock")) + 2, "2px down its line, as the pace bar")
    local tick = Style.Tok("ct.pace.tick")
    for i, mark in ipairs(bar.marks) do
        local m = S.M.__paint(mark)
        assertTrue(m.color and m.color[1] == tick[1] and m.color[4] == tick[4], "quarter " .. i .. ": the tick's hue")
        assertEqual(mark.__w, 2, "the tick's width")
        assertEqual(mark.__h, Chart.PACE_H, "standing 2px over and under the bar")
        assertEqual(mark.__points[1][4], math.floor(b.width * i / 4 + 0.5), "at its quarter")
    end
    assertEqual(bar.fillW, math.floor(b.width * (1 - bar.share)), "still emptying")
end)

test("race window board: Best to beat labels its Damage and DPS in gold, a matched pair, the line kept", function()
    if forever() then return end
    local S = sized()
    local Best = S.NS.RaceWindowBest
    local best = running(S).w.best
    local gold = S.NS.Style.Tok("text.headingAlt")
    assertEqual(best.damageLabel:GetText(), "Damage")
    assertEqual(best.dpsLabel:GetText(), "DPS")
    sameColor(best.damageLabel, gold, "Damage's label")
    sameColor(best.dpsLabel, gold, "DPS's label")
    assertEqual(best.dps.__template, best.damage.__template, "one face for both figures")
    local r1, g1, b1 = best.dps:GetTextColor()
    local r2, g2, b2 = best.damage:GetTextColor()
    assertTrue(r1 == r2 and g1 == g2 and b1 == b2, "one color for both")
    assertTrue(best.dps:IsShown() and best.damage:IsShown() and best.line:IsShown(), "both figures and the line")
    assertTrue(best.line:GetText() ~= "", "the date and item level line")
    assertEqual(best.damage.__points[1][4], best.damageLabel.__points[1][4] + Best.LABEL_W, "Damage's value after its label")
    assertEqual(best.dps.__points[1][4], best.dpsLabel.__points[1][4] + Best.LABEL_W, "DPS's value after its label")
    assertEqual(best.dps.__points[1][3], "TOP", "DPS in the card's right half")
end)

test("race window board: Best by now's figures never run under their labels, at any width", function()
    if forever() then return end
    for _, width in ipairs({ 260, 400, 600 }) do
        local S = sized()
        local Best = S.NS.RaceWindowBest
        running(S)
        local now = shape(S, width, 0).w.now
        -- Each half: label at its left edge, the value LABEL_W after it and ending at the half's edge.
        for _, pair in ipairs({ { now.bestLabel, now.value, "TOPLEFT", "TOP" }, { now.youLabel, now.you, "TOP", "TOPRIGHT" } }) do
            local lab, fig = pair[1], pair[2]
            local l, f1, f2 = lab.__points[1], fig.__points[1], fig.__points[2]
            assertEqual(l[2], now.card, "the label on the card")
            assertEqual(f1[2], now.card, "the value's left on the card (never on a label)")
            assertEqual(f2[2], now.card, "and its right")
            assertEqual(f1[3], pair[3])
            assertEqual(f2[3], pair[4], "the value ends at its half's edge")
            assertEqual(f1[4], l[4] + Best.LABEL_W, width .. ": the value LABEL_W after its label")
        end
        assertTrue(Best.LABEL_W >= #("Current") * 6, "LABEL_W fits the longer label")
    end
end)

test("race window board: a checkpoint's time is a size above its figures, set apart over the best, the bar 90% wide", function()
    if forever() then return end
    local S = sized()
    local B, FONT = S.NS.RaceWindowBoard, S.NS.Style.FONT
    local b = running(S)
    for i, cell in ipairs(b.w.cps.cells) do
        assertEqual(cell.time.__template, FONT.HEADING, "checkpoint " .. i .. ": the time a step up (12px)")
        assertEqual(cell.value.__template, FONT.TEXT, "over the figures' text face (10px)")
        assertEqual(cell.you.__template, FONT.TEXT)
        local tY, vY, yY = -cell.time.__points[1][5], -cell.value.__points[1][5], -cell.you.__points[1][5]
        assertTrue(vY - tY >= 12 + 3, "space under the time: " .. (vY - tY))
        local barTop = -cell.pace.bar.__points[1][5]
        assertTrue(barTop - (yY + 10) >= 4, "a gap over the bar: " .. (barTop - yY - 10))
        assertTrue(barTop + B.CP_PACE_H + 4 <= B.CP_H, "inside the cell")
    end
    assertEqual(B.CP_PACE_SHARE, 0.9)
    local cw = math.floor((b.width - 3 * B.CP_GAP) / 4)
    assertEqual(b.w.cps.cells[1].pace.barW, math.floor(cw * 0.9))
end)
