-- tests/test_insights.lua — the Results window's Insights tab (modules/Results_Insights.lua, Race mode
-- plan Task D2, spec §7; CT issue #2), ported from DPS Race @f8078c7 (tests/test_insights.lua's tab
-- half and its host cases) onto Combat Trail's fight records: the tab strip and `/ct results insights`,
-- the faceted filter bar with its counts, the cards (the Clean races card under Races and All only,
-- ruling X12), the general sections over every fight and the race-only ones under the Races filter,
-- the board tabs, Recent New Bests opening its fight, Late Casts' right-click, the empty state,
-- Save / Clear / Reset at `results.insights`, the sample history, a resize, the bar's fit, a load with
-- no library, and the chart host (core/ChartsSetup.lua). The library's own chart primitives are
-- LibKa0s's suite's (LibKa0s-Charts-1.0), not re-pinned here. Runs under both kit profiles: on WoW
-- Forever there is no Races filter, no race check and no race-only section.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local F = dofile(T.root .. "/tests/insights_fixture.lua")(T)
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local function forever() return T.NS.Compat.IsForever() end

--- A fresh instance with `list` stored (the fixture's history by default) and, unless `opts.closed`,
--- the Results window open on Insights.
local function tab(list, opts)
    opts = opts or {}
    local inst = T.load{ libFiles = opts.libFiles, mutate = function(m) installPaint(m) end }
    local NS, M = inst.NS, inst.mocks
    F.store(NS, list or F.history(NS))
    if opts.closed then return NS, M end
    assertTrue(NS.Results.ShowTab("insights"))
    local ui = NS.Results.__ui()
    assertTrue(ui.insights ~= nil, "the tab was built")
    return NS, M, ui, ui.insights
end

local function active(pane, name)
    return pane.ctx:Pool(name).active
end

local function sameRgb(NS, M, fs, token)
    local got = M.__paint(fs).textColor or {}
    local r, g, b = NS.Style.Rgb(token)
    return math.abs((got[1] or -1) - r) < 1e-6 and math.abs((got[2] or -1) - g) < 1e-6 and math.abs((got[3] or -1) - b) < 1e-6
end

local function fireClick(row, button)
    row:GetScript("OnMouseUp")(row, button)
end

-- ── the tab ─────────────────────────────────────────────────────────────────────────────────────

test("insights tab: built on its first show, its label lit while it shows; /ct results insights opens it", function()
    local NS, M = tab(nil, { closed = true })
    NS.Results.Show()
    local ui = NS.Results.__ui()
    assertEqual(NS.Results.Tab(), "fights", "the window opens on Fights")
    assertNil(ui.insights, "not built before it is shown")
    NS.Results.OnVerb("insights")
    assertEqual(NS.Results.Tab(), "insights")
    assertTrue(ui.insights ~= nil and ui.insights.frame:IsShown())
    assertFalse(ui.list.frame:IsShown(), "the list stands aside")
    assertFalse(ui.detail.frame:IsShown())
    assertTrue(sameRgb(NS, M, ui.tabs.insights.label, "tab.onText"), "the shown tab in tab.onText")
    assertTrue(sameRgb(NS, M, ui.tabs.fights.label, "tab.text"), "the other in tab.text")
    assertTrue(ui.tabs.insights.underline:IsShown())
    assertFalse(ui.tabs.fights.underline:IsShown())
    -- A fight opened from anywhere goes back to the Fights tab.
    NS.Results.ShowFight("f1")
    assertEqual(NS.Results.Tab(), "fights")
    assertFalse(ui.insights.frame:IsShown())
    assertEqual(NS.Results.Selected(), "f1")
    ui.tabs.insights:__fire("OnClick")
    assertEqual(NS.Results.Tab(), "insights", "the tab button switches")
    assertEqual(NS.Results.Diagnose().tab, "insights")
end)

test("insights tab: the dropdowns list the stored fights with their counts, led by All", function()
    local NS, _, ui, pane = tab()
    local n = forever() and 7 or 6
    local dd = pane.dropdowns
    assertEqual(F.labels(dd.character._options), ("All characters (%d)|Lanfear (2)|Tush (%d)"):format(n, n - 2))
    assertEqual(dd.character.text:GetText(), "All characters (2)", "closed, it names its choices")
    assertEqual(dd.days.text:GetText(), "All time")
    assertEqual(dd.character._value, "all", "no Current head: the cross-character view")
    assertEqual(pane:Count(), n)
    assertEqual(ui.footLeft:GetText():match("^(.-) \194\183"), ("%d fights"):format(n), "the footer counts them")
    assertEqual(dd.kind ~= nil, not forever(), "Fights / Races / All on Retail only")
    assertEqual(pane.checks.cleanOnly ~= nil, not forever(), "Clean only on Retail only")
    assertTrue(NS.ResultsInsights ~= nil)
end)

test("insights tab: a filter redraws the cards and narrows the other dropdowns", function()
    local _, _, ui, pane = tab()
    local n = forever() and 7 or 6
    assertEqual(pane.cards.count.value:GetText(), tostring(n))
    assertTrue(pane:SetFilter("spec", 267))
    assertEqual(pane:Count(), 2)
    assertEqual(pane.cards.count.value:GetText(), "2", "the card redrawn")
    assertEqual(ui.footLeft:GetText():match("^(.-) \194\183"), "2 fights", "the footer follows the filter")
    assertEqual(pane.dropdowns.spec.text:GetText(), "Destruction", "a pick by its name alone")
    assertEqual(F.labels(pane.dropdowns.character._options), "All characters (2)|Lanfear (2)",
        "the other dropdowns list what this filter leaves")
    assertFalse(pane:SetFilter("group", "none"), "not an Insights filter")
end)

test("insights tab: the cards state their figures, each hover naming its value", function()
    local NS, _, _, pane = tab()
    local c = pane.cards
    local caption = forever() and "Fights" or "Fights and races"
    assertEqual(c.count.label:GetText(), caption)
    assertEqual(c.count.frame._tip[1], caption)
    assertEqual(c.time.value:GetText(), forever() and "13m 41s" or "13m 00s", "fights' lengths and the time raced")
    assertEqual(c.time.label:GetText(), "Time in combat")
    assertEqual(c.newBests.value:GetText(), "2")
    assertEqual(c.chars.value:GetText(), "2")
    assertEqual(c.specs.value:GetText(), "2")
    assertEqual(c.activeDays.value:GetText(), forever() and "4" or "3")
    assertEqual(c.avg.value:GetText(), "96.2%", "each fight's share of its own board's best, averaged")
    local fire = NS.ResultsTable.SpecInfo(63, "Fire")
    assertEqual(c.best.label:GetText(), "Best DPS \194\183 " .. fire .. " \194\183 Cleave \194\183 3:00",
        "the race's board names the peak")
    assertEqual(c.best.value:GetText(), NS.Format.Number(1600), "a race's race DPS")
    -- One board alone: the raw average.
    pane:SetFilter("content", "raid")
    assertEqual(c.avg.label:GetText(), "Avg DPS")
    assertEqual(c.avg.value:GetText(), NS.Format.Number(1100))
end)

test("insights: the Clean races card counts races only, under Races and All, never under Fights", function()
    local _, _, _, pane = tab()
    local clean = pane.cards.clean
    if forever() then
        assertFalse(clean.frame:IsShown(), "no race check on WoW Forever")
        return
    end
    assertTrue(clean.frame:IsShown(), "under All")
    assertEqual(clean.value:GetText(), "66.7%", "the late Incinerate flags one race of three")
    assertEqual(clean.frame._tip[2], "2 of 3 races carry no flag.")
    pane:SetFilter("kind", "races")
    assertTrue(clean.frame:IsShown(), "under Races")
    assertEqual(pane.cards.count.label:GetText(), "Races")
    assertEqual(pane.cards.time.label:GetText(), "Time raced")
    pane:SetFilter("kind", "fights")
    assertFalse(clean.frame:IsShown(), "under Fights: a fight carries no flag")
    assertEqual(pane.cards.count.label:GetText(), "Fights")
end)

test("insights: the race-only sections show under the Races filter only", function()
    local _, _, _, pane = tab()
    local H, P = pane.headers, pane.panels
    assertTrue(H.progression:IsShown(), "DPS Progression runs on all fights")
    assertTrue(H.chars:IsShown(), "and By Character")
    assertTrue(H.charSplit:IsShown())
    assertEqual(H.charSplit:GetText(), "By Character \195\151 Content")
    assertTrue(H.boards:IsShown())
    assertEqual(H.boards:GetText(), "By Board")
    assertTrue(P.bests:IsShown(), "and Recent New Bests")
    for _, key in ipairs({ "charLength", "perDay", "tail" }) do
        assertFalse(H[key]:IsShown(), key .. " is race-only")
    end
    assertFalse(P.late:IsShown(), "Late Casts is race-only")
    if forever() then
        assertFalse(pane:SetFilter("length", 60) and pane.dropdowns.length ~= nil, "no race filter on WoW Forever")
        return
    end
    pane:SetFilter("kind", "races")
    for _, key in ipairs({ "charLength", "perDay", "tail" }) do
        assertTrue(H[key]:IsShown(), key .. " under Races")
    end
    assertTrue(P.late:IsShown())
    assertEqual(H.boards:GetText(), "By Target \195\151 Length")
    assertEqual(H.charSplit:GetText(), "Races By Character \195\151 Target")
    assertTrue(pane.dropdowns.length:IsShown(), "the race length under Races")
    pane:SetFilter("kind", "all")
    assertFalse(H.tail:IsShown())
    assertFalse(pane.dropdowns.length:IsShown(), "and hidden outside it")
end)

test("insights tab: a tab per board, Overall first, the sections under it read the tab picked", function()
    local NS, _, _, pane = tab()
    local tabs = active(pane, "boardTabs")
    assertEqual(#tabs, 5, "Overall, then one per board")
    assertEqual(tabs[1].label:GetText(), "Overall")
    assertEqual(tabs[2].label:GetText(), "Cleave \194\183 3:00", "the races first, in the catalog's order")
    assertEqual(tabs[3].label:GetText(), "Boss-level \194\183 1:00")
    assertEqual(tabs[4].label:GetText(), "Grobbulus \194\183 Heroic", "then the fight boards by name")
    assertEqual(pane.boardKey, NS.InsightsData.OVERALL)
    assertTrue(tabs[1].underline:IsShown())
    assertEqual(#active(pane, "specs"), 0, "Overall: DPS compares only within a board")
    tabs[2]:GetScript("OnClick")(tabs[2])
    assertEqual(pane.boardKey, "race:cleave|180")
    local specs = active(pane, "specs")
    assertEqual(#specs, 1)
    assertEqual(specs[1].label:GetText(), NS.ResultsTable.SpecInfo(63, "Fire"))
    assertEqual(#active(pane, "chars"), 1, "the sections under the tabs read the tab picked")
    assertEqual(#active(pane, "bests"), 1, "its one new best")
    assertTrue(active(pane, "boardTabs")[2].underline:IsShown(), "the pick redrawn")
    -- Kept for the session in a new tab, nothing saved.
    local again = NS.ResultsInsights.Build(NS.Results.__ui().body, {})
    again:Refresh()
    again:Layout(900, 500)
    assertEqual(again.boardKey, "race:cleave|180")
    -- Back to Overall once the filters leave it out.
    pane:SetFilter("character", F.charKey(NS, "lan"))
    assertEqual(pane.boardKey, NS.InsightsData.OVERALL)
end)

test("insights tab: a Recent New Bests row opens its fight on the Fights tab; a right-click its row menu", function()
    local NS, _, _, pane = tab()
    local rows = active(pane, "bests")
    assertEqual(#rows, 2)
    assertTrue(rows[1].name:GetText():find("Cleave", 1, true) ~= nil, "the newest first: r2")
    local menued
    NS.Results.RowMenu = function(record) menued = record.id end
    fireClick(rows[1], "RightButton")
    assertEqual(menued, "r2")
    assertEqual(NS.Results.Tab(), "insights", "a right-click stays")
    fireClick(rows[1], "LeftButton")
    assertEqual(NS.Results.Tab(), "fights")
    assertEqual(NS.Results.Selected(), "r2")
end)

test("insights tab: Late Casts lists the counted spells, then the ignored ones dimmed; a right-click ignores", function()
    local NS, _, _, pane = tab()
    if forever() then return end
    pane:SetFilter("kind", "races")
    local rows = active(pane, "late")
    assertEqual(#rows, 2)
    assertEqual(rows[1].name:GetText(), NS.HudBreakdown.SpellName(29722))
    assertEqual(rows[2].name:GetText(), NS.HudBreakdown.SpellName(5384) .. " (ignored)")
    local asked
    NS.LateIgnore.Menu = function(x) asked = x.flags.lateCasts[1].spellID end
    fireClick(rows[1], "LeftButton")
    assertNil(asked, "a left click does nothing")
    fireClick(rows[1], "RightButton")
    assertEqual(asked, 29722, "the ignore list's own menu, over that one cast")
end)

test("insights tab: with no fight the empty state shows, and every card and section hides", function()
    local _, _, _, pane = tab({})
    assertTrue(pane.empty:IsShown())
    assertEqual(pane.empty:GetText(), "No fights match these filters.")
    for key, card in pairs(pane.cards) do assertFalse(card.frame:IsShown(), key) end
    for key, h in pairs(pane.headers) do assertFalse(h:IsShown(), key) end
    assertEqual(pane:Count(), 0)
end)

test("insights tab: Save, Clear and Reset keep the view at results.insights", function()
    local NS, _, _, pane = tab()
    local p = NS.db.profile
    pane:SetFilter("spec", 63)
    assertTrue(pane:SaveView())
    assertEqual(p.results.insights.spec, 63, "saved")
    pane:SetFilter("spec", 267)
    pane:ClearView()
    assertEqual(pane.filters.spec, 63, "Clear: back to the saved view")
    assertEqual(p.results.insights.spec, 63, "which stays saved")
    assertTrue(pane:ResetView())
    assertEqual(pane.filters.spec, "all", "Reset: the stock view")
    assertNil(p.results.insights, "the saved view gone")
    assertEqual(NS.ResultsInsights.SavedView().spec, "all", "the shipped one answers")
    -- A fallback never writes the saved view.
    pane:SetFilter("character", F.charKey(NS, "lan"))
    pane:SetFilter("spec", 63)
    assertNil(p.results.insights)
end)

test("insights tab: the sample history fills the tab; Save refuses, and the player's view comes back", function()
    local NS, _, _, pane = tab()
    pane:SetFilter("spec", 267)
    NS.ResultsSource.Use({ fights = { F.fight(NS, { id = "sample", dps = 2000 }) } })
    assertEqual(pane:Count(), 1, "the sample's one fight")
    assertEqual(pane.filters.spec, "all", "the samples open on the stock view")
    assertFalse(pane:SaveView(), "Save refuses over the samples")
    assertFalse(pane:ResetView())
    NS.ResultsSource.Restore()
    assertEqual(pane.filters.spec, 267, "the player's view back")
    assertEqual(pane:Count(), 2)
end)

test("insights tab: Resize re-plans the bar and the scroll frame and rebinds nothing", function()
    local NS, _, _, pane = tab()
    local released = 0
    local release = pane.ctx.ReleaseAll
    pane.ctx.ReleaseAll = function(...) released = released + 1; return release(...) end
    local ui = NS.Results.__ui()
    ui.frame:SetSize(1400, 700)
    pane:Resize(1400, 600)
    assertEqual(released, 0, "nothing redrawn while the grip is held")
    assertEqual(pane.width, 1400)
    pane:Layout(1400, 600)
    assertEqual(released, 1, "the release's layout redraws")
end)

test("insights tab: the bar fits the window's least width, and takes one row in the expanded view", function()
    local NS = tab(nil, { closed = true })
    local I, R = NS.ResultsInsights, NS.Results
    local narrow = R.MinWidth("collapsed") - 2
    for _, kind in ipairs({ "all", "races", "fights" }) do
        local plan = I.BarPlan(narrow, { kind = kind })
        assertTrue(plan.right <= narrow, ("%s: the bar ends at %d of %d"):format(kind, plan.right, narrow))
        local last = 0
        for _, item in ipairs(plan.row2) do last = math.max(last, item.x + item.w) end
        assertTrue(last <= plan.buttons.save - 52, kind .. ": the second group ends before Save")
    end
    assertTrue(I.BarPlan(R.MinWidth("expanded") - 2, { kind = "races" }).oneRow, "the expanded window: one row")
    assertEqual(#I.BarPlan(narrow, { kind = "races" }).row2, forever() and 0 or 4,
        "under Races: the race length, the dummy kind and the two checks (Retail)")
end)

test("insights tab: a load with no library keeps the tab and says why there are no charts", function()
    local NS = tab(nil, { libFiles = {}, closed = true })
    NS.Results.ShowTab("insights")
    local ui = NS.Results.__ui()
    assertTrue(ui ~= nil, "the window builds without the library")
    local pane = ui.insights
    assertTrue(pane ~= nil)
    assertNil(pane.ctx, "no chart context")
    assertTrue(pane.empty:IsShown())
    assertTrue(pane.empty:GetText():find("charts are unavailable", 1, true) ~= nil)
    assertTrue(next(pane.dropdowns) == nil, "no dropdown without the widget library")
    assertEqual(pane:Count(), forever() and 7 or 6, "the filters and the count still work")
end)

test("insights charts: the host pools through NS.Pool and draws in the window's look", function()
    local NS, M = tab(nil, { closed = true })
    local host = NS.ChartsHost()
    local Style, Tbl = NS.Style, NS.ResultsTable
    assertEqual(host.pool, NS.Pool)
    assertEqual(host.fonts.label, Style.FONT.TEXT)
    assertEqual(host.fonts.figure, Style.FONT.FIGURE)
    assertEqual(host.fonts.heading, Style.FONT.CHART)
    assertEqual(host.colors.heading, Tbl.COLORS.gold)
    assertEqual(host.colors.body, Tbl.COLORS.text)
    assertEqual(host.colors.track, Style.Tok("chart.track"))
    assertEqual(host.colors.rule, Style.Tok("section.rule"))
    assertEqual(host.colors.bar, Style.Tok("ct.chart.bar"))
    assertEqual(host.palette(), NS.Skin.Token("chart.series"), "the skin's palette, read when a chart draws")
    assertEqual(host.fill, Style.Fill)
    assertTrue(host.panel(M.UIParent) ~= nil, "the window's flat panel")
end)
