-- tests/test_results_log.lua — the Results fight detail's Log section (CombatTrail #11, plan item
-- CL-11c; the spec's addendum, home C; owner feedback items 19 and 20): no tab strip, one scrolling
-- page with Log as a folding section under Targets, open by default; the Timeline reached by the
-- footer's button, grayed with no casts; the section's saved log in the shared table with the Info
-- column, the chips and their counts, a chip turning its lines off, the sort and the wheel; no Damage
-- by spell (Overview's Spell breakdown is the one spell list); a click on a CAST row opening the
-- timeline at that cast (zoomed, the moment in the middle, the focus line), and its switch; and a fight
-- saved before the log saying "No combat sequence was saved for this fight"; a saved log's retired lines (the PULL
-- and END, the hits, heals and target buffs the Combat Sequence dropped, CSEQ-1) never shown or counted.
-- Runs under both kit profiles.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local NOW = os.time()
local FIREBALL, POLY, INTELLECT, BITE, FROSTBOLT, MARK = 133, 118, 1459, 17253, 116, 1126

local function fresh()
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        m.StaticPopup_Show = function() end
        m.StaticPopup_Hide = function() end
    end }
    return inst.NS, inst.mocks
end

local function pack(NS, list)
    local casts = {}
    for i, c in ipairs(list) do
        casts[i] = { t = c[1], spellID = c[2], unit = c[3] and "pet" or "player", interrupted = false }
    end
    return NS.CastCodec.Encode(casts)
end

-- A saved log (oldest first) as one saved before owner feedback item 10 and the Combat Sequence: the
-- pull's line, two casts of yours, the pet's, a buff, a debuff on the target, two hits taken (one small,
-- one sealed), a heal, a buff on the target, the debuff's loss, a death, the end's line. The retired
-- lines (the boundaries, the hits, the heal and the target buff) stay on disk and are dropped at read.
local function savedLog(NS)
    local K, U = NS.CombatLog.KIND, NS.CombatLog.UNIT
    return {
        { t = 0, k = K.START },
        { t = 0.5, k = K.CAST, id = FIREBALL, u = U.player },
        { t = 1.2, k = K.BUFF_ON, id = INTELLECT, u = U.player },
        { t = 2, k = K.CAST, id = BITE, u = U.pet },
        { t = 3, k = K.DEBUFF_ON, id = POLY, u = U.target },
        { t = 4, k = K.HIT, u = U.player, a = 42, s = 1 },
        { t = 5, k = K.HIT, u = U.player, a = "s", s = 4 },
        { t = 6, k = K.HEAL, u = U.player, a = 120, s = 2 },
        { t = 7, k = K.BUFF_ON, id = MARK, u = U.target },
        { t = 8, k = K.DEBUFF_OFF, id = POLY, u = U.target },
        { t = 30.5, k = K.CAST, id = FROSTBOLT, u = U.player },
        { t = 40, k = K.DIES, u = U.player },
        { t = 41, k = K.END },
    }
end

local n = 0
local function rec(NS, o)
    o = o or {}
    n = n + 1
    local me = NS.Identity.Who()
    local ident = { content = "world", targetName = "Bluegill Raider", targetLevel = 29, instanceType = "none",
                    zone = "Stranglethorn Vale" }
    return {
        schema = NS.Recorder.CT_SCHEMA, id = o.id or ("l-" .. n), t = NOW - n * 60, duration = 60, status = "final",
        who = { name = me.name, realm = me.realm, client = me.client, class = "MAGE", petName = "Mockfang" },
        identity = ident, boardKey = NS.Identity.BoardKey(ident),
        damage = { merged = 60000, player = 50000, pet = 10000 }, dps = 1000, meterDps = 1000,
        build = "120105", version = "0.1.0",
        spells = NS.CastCodec.EncodeSpells(o.spells or {
            { spellID = FIREBALL, total = 30000, isPet = false }, { spellID = FROSTBOLT, total = 20000, isPet = false },
            { spellID = BITE, total = 10000, isPet = true } }),
        casts = not o.noCasts and pack(NS, { { 0.5, FIREBALL }, { 2, BITE, true }, { 30.5, FROSTBOLT } }) or nil,
        log = not o.noLog and (o.log or savedLog(NS)) or nil, logDropped = o.logDropped,
        targets = { { name = "Bluegill Raider", total = 60000 } },
    }
end

local function save(NS, ...)
    for _, r in ipairs({ ... }) do assertTrue(NS.Recorder.Save(r), "saved " .. tostring(r.id)) end
end

local function click(b) b:GetScript("OnClick")(b, "LeftButton") end

-- The Results window on fight `id` (collapsed: the detail in the list's place), and its Log section.
local function logTab(NS, id)
    assertTrue(NS.Results.ShowFight(id))
    local pane = NS.Results.__ui().detail
    return pane, pane.log
end

local function top(region) return select(5, region:GetPoint(1)) end

-- The Event column's text of every row on screen, top down.
local function events(g)
    local out = {}
    for _, r in ipairs(g.table:Rows()) do
        if r:IsShown() then out[#out + 1] = r.text.event:GetText() end
    end
    return table.concat(out, ",")
end

-- ── one page, no tabs (owner feedback item 19) ─────────────────────────────────────────────────

test("results log: the detail has no tab strip, only the one scrolling page", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "a" }))
    local pane = logTab(NS, "a")
    assertNil(NS.ResultsDetail.TABS, "no tab list")
    assertNil(NS.ResultsDetail.Tab, "no tab shown")
    assertNil(pane.tabs, "no tab buttons")
    assertNil(pane.tabRule, "no tab rule")
    assertNil(pane.ShowTab, "no tab switch")
    assertTrue(pane.scrollFrame:IsShown(), "the page")
end)

test("results log: Combat Sequence is a folding section under Targets, open by default", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "a" }))
    local pane, g = logTab(NS, "a")
    local D = NS.ResultsDetail
    local order = table.concat(D.SECTIONS, ",")
    assertTrue(order:find("targets,sequence", 1, true) ~= nil, "after Targets: " .. order)
    assertEqual(g.title:GetText(), "Combat Sequence")
    assertEqual(g.title:GetParent(), pane.content, "in the scrolling page")
    assertEqual(g.title:GetFont(), pane.targets.title:GetFont(), "the sections' gold heading")
    assertTrue(top(g.title) < top(pane.targets.title), "under Targets")
    assertEqual(top(g.title), top(pane.targets.title) - NS.Style.SECTION_H - NS.ResultsTargets.ROW_H - 8
        - NS.Style.SECTION_GAP, "the section after Targets' one row")
    local arrow = pane.heads.sequence
    assertTrue(arrow:IsShown())
    assertEqual(arrow.iconName, "chevron-down", "open")
    assertFalse(D.IsCollapsed("sequence"), "open by default")
    assertTrue(g.frame:IsShown(), "its body")
    assertTrue(g.table.frame:IsShown(), "the table")
    for _, b in pairs(g.chips) do assertTrue(b:IsShown(), "the chips") end
    click(arrow)
    assertTrue(D.IsCollapsed("sequence"), "the fold is stored")
    assertEqual(rawget(NS.db.profile.results.collapsedSections, "sequence"), true, "under the key sequence")
    assertNil(rawget(NS.db.profile.results.collapsedSections, "log"), "never the old key")
    assertFalse(g.frame:IsShown(), "folded: the heading alone")
    assertEqual(arrow.iconName, "chevron-right")
    click(arrow)
    assertTrue(g.frame:IsShown())
end)

test("results log: the footer's Timeline button opens the timeline, grayed with no casts", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "a" }), rec(NS, { id = "none", noCasts = true }))
    local pane = logTab(NS, "a")
    assertFalse(NS.ResultsTimeline.IsShown())
    click(pane.w.timeline)
    assertTrue(NS.ResultsTimeline.IsShown(), "the button is the window's way in")
    NS.ResultsTimeline.Hide()
    logTab(NS, "none")
    assertFalse(pane.canTimeline, "no casts: grayed")
    click(pane.w.timeline)
    assertFalse(NS.ResultsTimeline.IsShown())
end)

test("results log: no Damage by spell, Overview's Spell breakdown the one spell list (owner feedback item 20)", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "a" }))
    local pane, g = logTab(NS, "a")
    assertNil(g.spells, "no spell rows in the Log section")
    assertNil(g.spellsTitle, "no Damage by spell heading")
    assertNil(g.spellsHost)
    assertNil(NS.ResultsLog.Beside, "the side panel's layout is gone")
    assertNil(NS.ResultsLog.SIDE_W)
    assertNil(NS.L and rawget(NS.L, "Damage by spell"), "its words are gone")
    assertEqual(pane.w.spellsTitle:GetText(), "Spell breakdown")
    assertEqual(#pane.w.list:Rows(), 3, "the Overview's breakdown is drawn")
end)

-- ── the Log section ─────────────────────────────────────────────────────────────────────────────────

test("results log: the saved log in the table, newest first, with the Info column", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "a" }))
    local _, g = logTab(NS, "a")
    -- red under: the old PULL and END lines drawn (owner feedback item 10), or the HIT, HEAL and target
    -- BUFF lines the Combat Sequence retired
    assertEqual(events(g), "DIES,CAST,DEBUFF-,DEBUFF+,CAST,BUFF+,CAST", "every live event, newest at the top")
    local keys = {}
    for _, col in ipairs(g.table.cols) do keys[#keys + 1] = col.key end
    assertEqual(table.concat(keys, ","), "time,event,spell,info", "the Info column, and no Amount")
    for _, r in ipairs(g.table:Rows()) do assertNil(r.text.amount, "no Amount label") end
    assertEqual(g.caption:GetText(), "7 lines", "the retired lines are not counted")
end)

test("results log: the caption counts the lines the cap dropped", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "a", logDropped = 40 }))
    local _, g = logTab(NS, "a")
    assertEqual(g.caption:GetText(), "7 lines \194\183 40 not kept")
end)

test("results log: the chips carry their counts and filter what is shown", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "a" }))
    local _, g = logTab(NS, "a")
    -- red under: Taken and Heals chips, or a count that took in the retired lines
    local want = { casts = "Casts 2", pet = "Pet 1", buffs = "Buffs 1", debuffs = "Debuffs 2" }
    local chipCount = 0
    for _ in pairs(g.chips) do chipCount = chipCount + 1 end
    assertEqual(chipCount, 4, "four chips")
    for key, text in pairs(want) do assertEqual(g.chips[key].label:GetText(), text, key) end
    for key in pairs(want) do assertEqual(g.chips[key].styleName, "primary", key .. " on") end
    click(g.chips.debuffs)
    assertEqual(g.chips.debuffs.styleName, "normal", "off")
    assertEqual(events(g), "DIES,CAST,CAST,BUFF+,CAST", "the debuffs are hidden, both ends")
    click(g.chips.casts)
    click(g.chips.pet)
    assertEqual(events(g), "DIES,BUFF+")
    assertEqual(#NS.CombatLog.Of(NS.Recorder.Get("a")), 13, "a chip, or the read-time filter, never changes what is saved")
    click(g.chips.debuffs)
    assertEqual(events(g), "DIES,DEBUFF-,DEBUFF+,BUFF+")
end)

test("results log: each fight opens on log.results.chips, the same fight drawn again keeps them", function()
    local NS = fresh()
    NS.db.profile.sequence.results.chips.buffs = false
    save(NS, rec(NS, { id = "a" }), rec(NS, { id = "b" }))
    local pane, g = logTab(NS, "a")
    assertEqual(g.chips.buffs.styleName, "normal", "the default chips")
    assertTrue(("," .. events(g) .. ","):find(",BUFF+,", 1, true) == nil, "no buff line: " .. events(g))
    click(g.chips.debuffs)
    pane:Show(pane.record)
    assertFalse(g.chipOn.debuffs, "kept on a redraw of the same fight")
    assertTrue(NS.Results.ShowFight("b"))
    assertTrue(g.chipOn.debuffs, "another fight opens on the defaults")
    assertFalse(g.chipOn.buffs)
end)

test("results log: the pure halves: counts, the order, the page; retired lines never counted", function()
    local NS = fresh()
    local RL = NS.ResultsLog
    local log = savedLog(NS)
    local c = RL.Counts(log)
    assertEqual(c.casts, 2)
    assertEqual(c.pet, 1)
    assertEqual(c.buffs, 1, "the target's buff is not counted")
    assertEqual(c.debuffs, 2, "the debuff's gain and its loss")
    assertNil(c.taken, "no Taken count")
    assertNil(c.heals, "no Heals count")
    local K, U = NS.CombatLog.KIND, NS.CombatLog.UNIT
    local retired = { { t = 0, k = K.START }, { t = 1, k = K.HIT, u = U.player, a = 9 },
                      { t = 2, k = K.HEAL, u = U.player, a = 9 }, { t = 3, k = K.BUFF_ON, id = MARK, u = U.target },
                      { t = 4, k = K.BUFF_OFF, id = MARK, u = U.target }, { t = 5, k = K.END } }
    local none = RL.Counts(retired)
    for _, chip in ipairs(RL.CHIPS) do assertEqual(none[chip.key], 0, chip.key .. " counts none of them") end
    assertEqual(RL.Lines(retired), 0)
    local chips = RL.DefaultChips({})
    local order = {}
    assertEqual(RL.Order(log, chips, {}, "oldest", order), 7, "the six retired lines left out")
    assertEqual(order[1], 2, "oldest first: the first event on top, not the pull's line")
    local nNew = RL.Order(log, chips, {}, "newest", order)
    assertEqual(order[1], 12)
    local page = {}
    assertEqual(RL.Page(order, nNew, 2, 3, "newest", page), 3)
    assertEqual(table.concat(page, ","), "10,5,4")
    RL.Order(log, chips, {}, "oldest", order)
    RL.Page(order, 7, 0, 3, "oldest", page)
    assertEqual(table.concat(page, ","), "4,3,2", "handed over newest first, as View:Draw takes them")
    assertEqual(RL.Order(log, chips, { minAmount = 50 }, "newest", order), 7, "a stray stored minAmount is never read")
    assertEqual(RL.Order(log, chips, { deaths = false }, "newest", order), 6, "deaths follow log.show.deaths")
    assertEqual(RL.Lines(log), 7, "the events, never the retired lines")
    assertEqual(RL.MaxOffset(11, 4), 7)
    assertEqual(RL.MaxOffset(2, 4), 0)
end)

test("results log: the Time header flips the sort, oldest first starting at the first event", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "a" }))
    local _, g = logTab(NS, "a")
    g.table.sorter:GetScript("OnClick")(g.table.sorter)
    assertEqual(NS.GetSetting("sequence.view.sort"), "oldest")
    assertEqual(events(g), "CAST,BUFF+,CAST,DEBUFF+,DEBUFF-,CAST,DIES")
end)

test("results log: the wheel scrolls the list and stays on it", function()
    local NS = fresh()
    local K, U = NS.CombatLog.KIND, NS.CombatLog.UNIT
    local long = { { t = 0, k = K.START } }
    for i = 1, 200 do long[#long + 1] = { t = i * 0.5, k = K.CAST, id = FIREBALL, u = U.player } end
    save(NS, rec(NS, { id = "a", log = long }))
    local _, g = logTab(NS, "a")
    assertTrue(g.rows < 201, "a page shorter than the log")
    assertEqual(g.offset, 0)
    g.table:Wheel(-1)
    assertEqual(g.offset, NS.ResultsLog.SCROLL, "down: older lines")
    g.table:Wheel(1)
    g.table:Wheel(1)
    assertEqual(g.offset, 0, "never above the top")
    for _ = 1, 200 do g.table:Wheel(-1) end
    assertEqual(g.offset, NS.ResultsLog.MaxOffset(g.n, g.rows), "never past the last page")
    local shown = 0
    for _, r in ipairs(g.table:Rows()) do if r:IsShown() then shown = shown + 1 end end
    assertEqual(shown, g.rows, "the last page is full")
end)

test("results log: the rows carry Spell breakdown's scroll indicator, a line a notch (owner feedback item 6)", function()
    local NS = fresh()
    local K, U = NS.CombatLog.KIND, NS.CombatLog.UNIT
    local long = {}
    for i = 1, 60 do long[#long + 1] = { t = i * 0.5, k = K.CAST, id = FIREBALL, u = U.player } end
    save(NS, rec(NS, { id = "a", log = long }))
    local _, g = logTab(NS, "a")
    local view, S = g.table, NS.HudStates
    assertEqual(NS.ResultsLog.SCROLL, 1, "one line a notch")
    assertTrue(view.scroll.on and view.thumb:IsShown(), "60 lines past the page: shown")
    local h = g.rows * NS.LogTable.RowH()
    assertEqual(view.scroll.thumbH, math.max(S.THUMB_MIN, math.floor(h * g.rows / 60 + 0.5)))
    assertEqual(view.scroll.dy, 0, "the top page")
    assertEqual(view.scroll.x, g.tableW + S.THUMB_GAP, "in the gutter the table leaves")
    assertTrue(view.scroll.x + S.THUMB_W <= g.tableW + NS.ResultsLog.GUTTER, "inside the section's width")
    for _ = 1, 100 do view:Wheel(-1) end
    assertEqual(view.scroll.dy, h - view.scroll.thumbH, "the last page: at the bottom")
    save(NS, rec(NS, { id = "b" }))
    local _, g2 = logTab(NS, "b")
    assertFalse(g2.table.scroll.on, "a log that fits: no indicator")
end)

test("results log: the table takes the section's width less the scroll's gutter, a page of the view", function()
    local NS = fresh()
    local RL = NS.ResultsLog
    save(NS, rec(NS, { id = "a" }))
    local pane, g = logTab(NS, "a")
    pane:Layout(800, 500, true)
    assertEqual(g.tableW, 800 - 2 * NS.ResultsDetail.PADX - RL.GUTTER)
    pane:Layout(440, 500, false)
    assertEqual(g.tableW, 440 - 2 * NS.ResultsDetail.PADX - RL.GUTTER)
    assertTrue(g.rows <= RL.RowsFor(pane.viewH, NS.Style.SECTION_H), "a page of the view, less the chips")
    assertEqual(RL.RowsFor(10, 0), RL.ROWS_MIN, "a short view keeps the fewest rows")
    pane:Layout(440, 2000, false)
    assertTrue(g.rows > RL.ROWS_MIN, "a tall view: more rows")
end)

test("results log: a click on a CAST row opens the timeline at that cast", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "a" }))
    local _, g = logTab(NS, "a")
    assertTrue(g.hint:IsShown(), "the hint names the click")
    local castRow, auraRow
    for _, r in ipairs(g.table:Rows()) do
        if r:IsShown() and r.line and r.line.id == FROSTBOLT then castRow = r end
        if r:IsShown() and r.line and r.line.k == NS.CombatLog.KIND.DEBUFF_ON then auraRow = r end
    end
    assertTrue(castRow ~= nil and auraRow ~= nil)
    auraRow:GetScript("OnMouseUp")(auraRow, "LeftButton")
    assertFalse(NS.ResultsTimeline.IsShown(), "only a CAST row jumps")
    castRow:GetScript("OnMouseUp")(castRow, "RightButton")
    assertFalse(NS.ResultsTimeline.IsShown(), "a right click does not")
    castRow:GetScript("OnMouseUp")(castRow, "LeftButton")
    assertTrue(NS.ResultsTimeline.IsShown(), "the timeline opened")
    assertEqual(NS.ResultsTimeline.Focus(), 30.5, "the focus line at the cast")
    assertTrue(NS.ResultsTimeline.Zoom() >= NS.ResultsTimelineData.ZOOMS[NS.ResultsTimeline.FOCUS_ZOOM], "zoomed in")
    local ui = NS.ResultsTimeline.__ui()
    assertTrue(ui.focusLine.casts:IsShown(), "the line drawn")
    local zoom = NS.ResultsTimeline.Zoom()
    local mid = (ui.pos + 0.5 / zoom) * ui.span
    assertTrue(math.abs(mid - 30.5) < 0.01, "the cast in the middle of the view: " .. mid)
    NS.ResultsTimeline.Hide()
end)

test("results log: log.results.jumpToCast off, a cast row's click does nothing", function()
    local NS = fresh()
    NS.db.profile.sequence.results.jumpToCast = false
    save(NS, rec(NS, { id = "a" }))
    local _, g = logTab(NS, "a")
    assertFalse(g.hint:IsShown())
    for _, r in ipairs(g.table:Rows()) do
        if r:IsShown() and r.line and r.line.k == NS.CombatLog.KIND.CAST then
            r:GetScript("OnMouseUp")(r, "LeftButton")
        end
    end
    assertFalse(NS.ResultsTimeline.IsShown())
end)

test("results log: the timeline's focus math keeps the view on the axis", function()
    local NS = fresh()
    local D = NS.ResultsTimelineData
    assertEqual(D.FocusPos(30, 60, 4), 0.5 - 0.125)
    assertEqual(D.FocusPos(0, 60, 4), 0, "near the start: clamped")
    assertEqual(D.FocusPos(60, 60, 4), 1 - 0.25, "near the end: clamped")
    assertEqual(D.OnAxis({}, 12), 12, "a fight's time as it is")
    assertNil(D.OnAxis({}, nil))
end)

test("results log: a fight saved before the log says No combat sequence was saved for this fight", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "old", noLog = true }))
    local _, g = logTab(NS, "old")
    assertTrue(g.none:IsShown())
    assertEqual(g.none:GetText(), "No combat sequence was saved for this fight")
    assertFalse(g.table.frame:IsShown(), "no table")
    for _, b in pairs(g.chips) do assertFalse(b:IsShown(), "no chips") end
    assertFalse(g.hint:IsShown())
end)

test("results log: a fight whose saved log holds only retired lines says No combat sequence too", function()
    local NS = fresh()
    local K, U = NS.CombatLog.KIND, NS.CombatLog.UNIT
    save(NS, rec(NS, { id = "retired", log = { { t = 0, k = K.START }, { t = 1, k = K.HIT, u = U.player, a = 9 },
        { t = 2, k = K.HEAL, u = U.player, a = 9 }, { t = 3, k = K.BUFF_ON, id = MARK, u = U.target },
        { t = 4, k = K.END } } }))
    local _, g = logTab(NS, "retired")
    assertTrue(g.none:IsShown(), "the empty state, not an empty table")
    assertFalse(g.table.frame:IsShown(), "no table")
    for _, b in pairs(g.chips) do assertFalse(b:IsShown(), "no chips") end
end)

test("results log: a Combat Log setting redraws an open Log section", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "a" }))
    local _, g = logTab(NS, "a")
    NS.SetByPath("sequence.view.sort", "oldest")
    assertEqual(events(g):sub(1, 4), "CAST", "the write-through sort redrew it")
end)
