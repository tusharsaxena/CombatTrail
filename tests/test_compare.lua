-- tests/test_compare.lua — the compare (plan Task 4.4, spec §7, mockup §7): which fight a fight is
-- compared with (the best on its board, the runner-up when it is the best, the session's pick over
-- both until it is cleared), the spells matched side by side, the figures, the Different loadout mark,
-- the gear line; and the window: opened from the detail's Compare button over the Results window under
-- its cover, following the detail, Clear pick, and closing with the Results window.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local NOW = os.time()
local KC, BS, PET = 34026, 217200, 16827

local function fresh()
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        m.StaticPopup_Show = function() end
        m.StaticPopup_Hide = function() end
    end }
    return inst.NS, inst.mocks
end

--- The record's gear set key: `o.gear` stored as a set, unless the record carries it inline.
local function gearSetOf(NS, o)
    if o.inline or type(o.gear) ~= "table" then return nil end
    return NS.Loadouts.StoreGear(o.gear)
end

local n = 0
--- A stored-shape record on the logged-in character, on one boss board. `o`: id, dps, duration,
--- spells ({ { spellID, total, isPet } }), gear, loadout, encounterID.
local function rec(NS, o)
    n = n + 1
    local me = NS.Identity.Who()
    local who = { name = me.name, realm = me.realm, client = me.client, class = me.class or "HUNTER",
                  specID = me.specID, specName = me.specName, ilvl = 721.4 }
    local ident = { content = "raid", targetName = "Vorasius", encounterID = o.encounterID or 3176,
                    encounterName = "Vorasius", instanceName = "The Voidspire", difficultyID = 15,
                    difficultyName = "Heroic", isBoss = true }
    local dps, duration = o.dps or 1000, o.duration or 60
    local merged = dps * duration
    return {
        schema = 1, id = o.id, t = NOW - n * 60, duration = duration, status = "final",
        who = who, identity = ident, boardKey = NS.Identity.BoardKey(ident),
        damage = { merged = merged, player = merged }, dps = dps, meterDps = dps,
        build = "120105", version = "0.1.0", loadout = o.loadout,
        -- The gear as the recorder stores it, a set by key (v0.2 plan Task A3); `inline` = a sample's.
        gear = o.inline and o.gear or nil, gearSet = gearSetOf(NS, o),
        spells = NS.CastCodec.EncodeSpells(o.spells or { { spellID = KC, total = merged, isPet = false } }),
    }
end

local function save(NS, ...)
    for _, r in ipairs({ ... }) do assertTrue(NS.Recorder.Save(r), "saved " .. tostring(r.id)) end
end

-- The Results window on fight `id`, its detail pane.
local function detailOn(NS, id)
    assertTrue(NS.Results.ShowFight(id))
    return NS.Results.__ui().detail
end

-- ── which fight ─────────────────────────────────────────────────────────────────────────────────

test("compare: vs best, runner-up when best", function()
    local NS = fresh()
    local Cmp = NS.ResultsCompare
    save(NS, rec(NS, { id = "best", dps = 3000 }), rec(NS, { id = "mid", dps = 2000 }),
        rec(NS, { id = "low", dps = 1000 }), rec(NS, { id = "elsewhere", dps = 9000, encounterID = 9999 }))
    local other, kind = Cmp.Pick(NS.Recorder.Get("mid"))
    assertEqual(other and other.id, "best")
    assertEqual(kind, "best")
    other, kind = Cmp.Pick(NS.Recorder.Get("best"))
    assertEqual(other and other.id, "mid", "the best is compared with the runner-up")
    assertEqual(kind, "runnerUp")
    assertNil(Cmp.Pick(NS.Recorder.Get("elsewhere")), "alone on its board: nothing to compare with")
    assertTrue(Cmp.SameBoard(NS.Recorder.Get("mid"), NS.Recorder.Get("low")))
    assertFalse(Cmp.SameBoard(NS.Recorder.Get("mid"), NS.Recorder.Get("elsewhere")))
    -- The detail's button says which, and is grayed with nothing to compare with.
    local pane = detailOn(NS, "mid")
    assertTrue(pane.w.compare:IsEnabled())
    assertEqual(pane.w.compare.label:GetText(), "Compare", "the label is Compare whatever the target (C3)")
    pane = detailOn(NS, "best")
    assertEqual(pane.w.compare.label:GetText(), "Compare")
    pane = detailOn(NS, "elsewhere")
    assertFalse(pane.w.compare:IsEnabled(), "no fight to compare with")
    -- The timeline asks the same one answer.
    local tl, tk = NS.ResultsTimelineData.CompareTarget(NS.Recorder.Get("best"))
    assertEqual(tl and tl.id, "mid")
    assertEqual(tk, "runnerUp")
end)

test("compare: session pick overrides until cleared", function()
    local NS = fresh()
    local Cmp = NS.ResultsCompare
    save(NS, rec(NS, { id = "best", dps = 3000 }), rec(NS, { id = "mid", dps = 2000 }),
        rec(NS, { id = "low", dps = 1000 }), rec(NS, { id = "elsewhere", dps = 9000, encounterID = 9999 }))
    local pane = detailOn(NS, "mid")
    assertTrue(NS.Results.CompareWith("elsewhere"), "a pick from another board")
    local other, kind = Cmp.Pick(NS.Recorder.Get("mid"))
    assertEqual(other and other.id, "elsewhere", "the pick wins over the best, on any board")
    assertEqual(kind, "picked")
    other = Cmp.Pick(NS.Recorder.Get("low"))
    assertEqual(other and other.id, "elsewhere", "it steers every fight's compare")
    other = Cmp.Pick(NS.Recorder.Get("elsewhere"))
    assertNil(other, "never the picked fight with itself (alone on its board)")
    assertEqual(pane.w.compare.label:GetText(), "Compare", "the detail redrew on the pick")
    -- The window opens on the pick, says it is on another board, and offers Clear pick.
    pane.w.compare:__fire("OnClick")
    local ui = NS.ResultsCompare.__ui()
    assertTrue(NS.ResultsCompare.IsShown())
    assertTrue(ui.legendB:GetText():find("Picked", 1, true) ~= nil, ui.legendB:GetText())
    assertEqual(ui.note:GetText(), "On another board")
    assertTrue(ui.clear:IsShown(), "Clear pick while a pick is in use")
    ui.clear:__fire("OnClick")
    assertNil(NS.Results.Pick(), "cleared")
    other, kind = Cmp.Pick(NS.Recorder.Get("mid"))
    assertEqual(other and other.id, "best", "back to the best")
    assertEqual(kind, "best")
    assertTrue(ui.legendB:GetText():find("Best", 1, true) ~= nil, "the open window followed the clear")
    assertFalse(ui.clear:IsShown())
    assertEqual(ui.note:GetText(), "")
    -- A deleted pick goes with its fight.
    NS.Results.CompareWith("low")
    NS.Results.DeleteFight("low")
    assertNil(NS.Results.Pick())
end)

-- ── the figures ─────────────────────────────────────────────────────────────────────────────────

test("compare: spells side by side, matched by spell and caster", function()
    local NS = fresh()
    local Cmp = NS.ResultsCompare
    local a = rec(NS, { id = "a", dps = 1100, spells = {
        { spellID = KC, total = 40000, isPet = false }, { spellID = BS, total = 20000, isPet = false },
        { spellID = PET, total = 6000, isPet = true } } })
    local b = rec(NS, { id = "b", dps = 1000, spells = {
        { spellID = KC, total = 50000, isPet = false }, { spellID = PET, total = 10000, isPet = true },
        { spellID = 999, total = 0, isPet = false } } })
    local rows = Cmp.Spells(a, b)
    assertEqual(#rows, 4, "every spell either fight cast")
    assertEqual(rows[1].spellID, KC)
    assertEqual(rows[1].aTotal, 40000)
    assertEqual(rows[1].bTotal, 50000)
    assertEqual(rows[1].delta, -10000)
    assertEqual(math.floor(rows[1].deltaPct + 0.5), -20)
    assertEqual(rows[2].spellID, BS)
    assertNil(rows[2].bTotal, "the other fight never cast it")
    assertNil(rows[2].deltaPct, "no % against nothing")
    assertEqual(rows[3].spellID, PET)
    assertTrue(rows[3].pet, "the pet's spell, matched to the pet's")
    assertEqual(math.floor(rows[3].deltaPct + 0.5), -40)
    assertEqual(rows[4].spellID, 999, "a spell this fight never cast last")
    -- The shares are of each fight's own damage.
    assertEqual(math.floor(rows[1].aShare * 10 + 0.5), math.floor(40000 / 66000 * 1000 + 0.5))
    -- The bars share one scale: the largest total of either side.
    assertEqual(Cmp.MaxTotal(rows), 50000)
    local bw, aw = Cmp.BarWidths(rows[1], 50000, 100)
    assertEqual(bw, 100)
    assertEqual(aw, 80)
    local kpis = Cmp.Kpis(a, b)
    assertEqual(kpis[1].key, "damage", "Damage first, as on the HUD (owner, 2026-11-11)")
    assertEqual(kpis[2].key, "dps")
    assertEqual(math.floor(kpis[2].pct * 10 + 0.5), 100, "+10.0% DPS")
    assertEqual(kpis[3].key, "length")
    assertEqual(kpis[3].pct, 0)
    assertEqual(Cmp.ChangeText(kpis[2].pct), "+10.0%")
    assertEqual(Cmp.PairText("dps", 1100, 1000), NS.Format.Number(1000) .. " \194\187 " .. NS.Format.Number(1100))
    assertEqual(Cmp.PairText("length", 60, 75), "1:15 \194\187 1:00")
    assertEqual(Cmp.ChangeText(nil), "\226\128\148")
    assertNil(Cmp.Pct(5, 0), "no % of zero")
end)

test("compare: different loadout mark", function()
    local NS = fresh()
    local Cmp = NS.ResultsCompare
    local raid = NS.Loadouts.Store({ importString = "CQQAAAA", specID = 253, name = "Raid" })
    local aoe = NS.Loadouts.Store({ importString = "CQQBBBB", specID = 253, name = "AoE" })
    local a = rec(NS, { id = "a", dps = 1000, loadout = raid })
    local b = rec(NS, { id = "b", dps = 2000, loadout = aoe })
    local c = rec(NS, { id = "c", dps = 1500, loadout = raid })
    local none = rec(NS, { id = "none", dps = 500 })
    assertTrue(Cmp.DifferentLoadout(a, b))
    assertFalse(Cmp.DifferentLoadout(a, c), "the same loadout")
    assertFalse(Cmp.DifferentLoadout(a, none), "unknown is never marked")
    save(NS, a, b, c, none)
    local pane = detailOn(NS, "a")
    pane.w.compare:__fire("OnClick")
    local ui = NS.ResultsCompare.__ui()
    assertTrue(ui.chip:IsShown(), "a vs the best b: different loadouts")
    local lines = Cmp.LoadoutLines(NS.Recorder.Get("a"), NS.Recorder.Get("b"))
    assertEqual(lines[2], "This fight: Raid")
    assertEqual(lines[3], "The other fight: AoE")
    NS.Results.CompareWith("c")
    assertFalse(ui.chip:IsShown(), "the pick c wore the same loadout")
end)

-- ── the window ──────────────────────────────────────────────────────────────────────────────────

test("compare: the window opens over the Results window, follows the detail and closes with it", function()
    local NS, M = fresh()
    save(NS, rec(NS, { id = "best", dps = 3000, gear = { [13] = "212001", [1] = "212002" } }),
        rec(NS, { id = "mid", dps = 2000, gear = { [13] = "212009", [1] = "212002:7000" } }),
        rec(NS, { id = "low", dps = 1000 }))
    local pane = detailOn(NS, "mid")
    pane.w.compare:__fire("OnClick")
    local ui = NS.ResultsCompare.__ui()
    assertTrue(ui ~= nil, "built")
    assertTrue(NS.ResultsCompare.IsShown())
    assertEqual(ui.frame:GetFrameStrata(), NS.Constants.LAYERS.STRATA.MODAL, "one strata above the Results window")
    assertTrue(ui.frame:IsToplevel())
    assertTrue(NS.Results.IsCovered(), "the Results window wears its cover")
    local special = false
    for _, name in ipairs(M.UISpecialFrames) do if name == "CombatTrailCompare" then special = true end end
    assertTrue(special, "Escape closes it")
    assertEqual(#NS.ResultsCompare.Rows(), 1, "one spell row")
    assertEqual(ui.kpis[1].key, "damage", "the Damage box left of the DPS box, as on the HUD")
    assertEqual(ui.kpis[2].key, "dps")
    assertTrue(ui.kpis[2].value:GetText():find("\194\187", 1, true) ~= nil, "other -> this")
    assertEqual(ui.kpis[2].change:GetText(), "-33.3%")
    -- Each box: its label, its figures and its change, centered, the change on the bottom line
    -- (owner, 2026-11-11).
    for _, part in ipairs({ "label", "value", "change" }) do
        assertEqual(ui.kpis[1][part]:GetJustifyH(), "CENTER", part .. " centered")
    end
    assertEqual(ui.kpis[1].change.__points[1][1], "BOTTOMLEFT", "the change on the box's bottom line")
    assertEqual(ui.kpis[1].label.__points[1][1], "TOPLEFT", "the label on its top line")
    -- Every spell row on a white background, so its stripe shows.
    assertEqual(ui.rows[1].bg:GetTexture(), NS.Style.WHITE)
    -- The gear line: the trinket changed, the head's enchant differs.
    local texts = {}
    for _, g in ipairs(ui.gearItems) do if g.text:IsShown() then texts[#texts + 1] = g.text:GetText() end end
    assertEqual(#texts, 2)
    assertEqual(texts[1], "Head \194\183 enchant differs")
    assertEqual(texts[2], "Trinket 1 \194\183 another item")
    assertFalse(ui.gearNone:IsShown())
    -- The detail moves to the best: the window follows (compared with the runner-up now).
    NS.Results.ShowFight("best")
    assertTrue(ui.legendB:GetText():find("Runner-up", 1, true) ~= nil, ui.legendB:GetText())
    -- Opening the timeline closes the compare: one modal, one cover.
    NS.ResultsTimeline.Open(NS.Results.__ui().detail)
    assertFalse(NS.ResultsCompare.IsShown(), "one modal at a time")
    assertTrue(NS.Results.IsCovered(), "the timeline keeps the cover")
    NS.ResultsTimeline.Hide()
    -- Open again, then the Results window closes: the compare closes with it and the cover goes.
    NS.Results.__ui().detail.w.compare:__fire("OnClick")
    assertTrue(NS.ResultsCompare.IsShown())
    NS.Results.Hide()
    assertFalse(NS.ResultsCompare.IsShown(), "closed with the Results window")
    assertFalse(NS.Results.IsCovered())
    -- A record with no other fight on the board: nothing to compare.
    assertNil(NS.ResultsCompare.Pick(nil))
end)

test("compare: an upgraded item is on the gear line", function()
    local NS = fresh()
    local up, before = "212060:::::::::::1:200", "212060:::::::::::1:100"
    save(NS, rec(NS, { id = "best", dps = 3000, gear = { [14] = before } }),
        rec(NS, { id = "mid", dps = 2000, gear = { [14] = up } }))
    local levels = { [up] = 727, [before] = 714 }
    NS.ResultsGear.IlvlOf = function(item) return levels[item] end
    detailOn(NS, "mid").w.compare:__fire("OnClick")
    local ui = NS.ResultsCompare.__ui()
    local texts = {}
    for _, g in ipairs(ui.gearItems) do if g.text:IsShown() then texts[#texts + 1] = g.text:GetText() end end
    assertEqual(#texts, 1, "the same item ID, another item level")
    local P, Style = NS.Constants.PALETTE, NS.Style
    assertEqual(texts[1], "Trinket 2 \194\183 " .. Style.HueEscape(P.BEST_TEXT) .. "714|r \194\187 "
        .. Style.HueEscape(P.THIS_TEXT) .. "727|r", "the other's level in blue, this one's in yellow")
    assertEqual(NS.ResultsCompare.GearText({ slot = 14, item = up, otherItem = before, diff = {} }, 727, 714),
        "Trinket 2 \194\183 714 \194\187 727", "plain without the tint")
    assertFalse(ui.gearNone:IsShown())
end)

test("compare: the gear line reads stored sets, a sample's inline gear, and one set on both says no change", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "best", dps = 3000, gear = { [13] = "212001" }, inline = true }),
        rec(NS, { id = "mid", dps = 2000, gear = { [13] = "212009" } }),
        rec(NS, { id = "low", dps = 1000, gear = { [13] = "212009" } }))
    detailOn(NS, "mid").w.compare:__fire("OnClick")
    local ui = NS.ResultsCompare.__ui()
    local function texts()
        local out = {}
        for _, g in ipairs(ui.gearItems) do if g.text:IsShown() then out[#out + 1] = g.text:GetText() end end
        return out
    end
    assertEqual(texts()[1], "Trinket 1 \194\183 another item", "a set against an inline sample")
    NS.Results.CompareWith("low")
    assertEqual(#texts(), 0, "the same set")
    assertTrue(ui.gearNone:IsShown())
    assertEqual(ui.gearNone:GetText(), "No gear changed.", "recorded on both, through the sets")
end)

test("compare: Escape closes the compare first and the Results window stays", function()
    local NS, M = fresh()
    save(NS, rec(NS, { id = "best", dps = 3000 }), rec(NS, { id = "mid", dps = 2000 }))
    local pane = detailOn(NS, "mid")
    pane.w.compare:__fire("OnClick")
    local ui = NS.ResultsCompare.__ui()
    -- The close stack hides both; the covered Results window shows itself again.
    local results = NS.Results.__ui().frame
    ui.frame:Hide()
    ui.frame:__fire("OnHide")
    results:Hide()
    results:__fire("OnHide")
    if M.__fireTimers then M.__fireTimers() end
    assertFalse(NS.ResultsCompare.IsShown())
    assertTrue(NS.Results.IsShown(), "the Results window stayed")
    assertTrue(NS.Results.__ui().frame:IsShown())
    assertFalse(NS.Results.IsCovered(), "the cover went once the compare's close settled")
end)

-- ── v0.2 Task C4: the button's tip, the colors by side, what was used ───────────────────────────

test("compare: the Compare button's tooltip names the fight it compares with", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "best", dps = 3000 }), rec(NS, { id = "mid", dps = 2000 }),
        rec(NS, { id = "elsewhere", dps = 9000, encounterID = 9999 }))
    local pane = detailOn(NS, "mid")
    assertEqual(pane.w.compare.tip[1], "Compare")
    assertEqual(pane.w.compare.tip[2], "This fight beside the best on its board.")
    pane = detailOn(NS, "best")
    assertEqual(pane.w.compare.tip[2], "This fight beside the runner-up on its board. This fight is the best.")
    NS.Results.CompareWith("elsewhere")
    pane = detailOn(NS, "mid")
    assertEqual(pane.w.compare.tip[2], "This fight beside the fight you picked with Compare With This Fight.")
    assertEqual(pane.w.compare.label:GetText(), "Compare", "the label stays Compare")
end)

-- Whether paint color `c` is palette entry `p` at alpha `a`.
local function sameHue(c, p, a, what)
    assertTrue(c ~= nil, what .. ": painted")
    for i = 1, 3 do assertTrue(math.abs(c[i] - p[i]) < 1e-6, what .. " channel " .. i) end
    if a then assertTrue(math.abs((c[4] or 1) - a) < 1e-6, what .. " alpha") end
end

-- Whether `text` writes the other fight in blue, then the arrow, then this one in yellow.
local function sidesTinted(NS, text, what)
    local P, Style = NS.Constants.PALETTE, NS.Style
    local blue, yellow = Style.HueEscape(P.BEST_TEXT), Style.HueEscape(P.THIS_TEXT)
    local b = text:find(blue, 1, true)
    local y = text:find(yellow, 1, true)
    assertTrue(b ~= nil, what .. ": the other side in blue: " .. text)
    assertTrue(y ~= nil, what .. ": this side in yellow: " .. text)
    assertTrue(b < y, what .. ": the other side first: " .. text)
end

test("compare: this fight is yellow and the other blue, in the best and the runner-up cases alike", function()
    local NS, M = fresh()
    local P = NS.Constants.PALETTE
    save(NS, rec(NS, { id = "best", dps = 3000 }), rec(NS, { id = "mid", dps = 2000 }))
    detailOn(NS, "mid").w.compare:__fire("OnClick")
    local ui = NS.ResultsCompare.__ui()
    local function check(case)
        local row = NS.ResultsCompare.Rows()[1]
        sameHue(M.__paint(row.barA).color, P.THIS_BAR, P.BAR_A, case .. " this fight's bar")
        sameHue(M.__paint(row.barB).color, P.BEST_BAR, P.BAR_A, case .. " the other's bar")
        sameHue(M.__paint(ui.legendA).textColor, P.THIS_TEXT, nil, case .. " this fight's legend")
        sameHue(M.__paint(ui.legendB).textColor, P.BEST_TEXT, nil, case .. " the other's legend")
        for i = 1, 3 do sidesTinted(NS, ui.kpis[i].value:GetText(), case .. " box " .. i) end
        sidesTinted(NS, row.figure:GetText(), case .. " the row's figure")
        sidesTinted(NS, ui.headFigure:GetText(), case .. " the figure header")
        sidesTinted(NS, ui.headBars:GetText(), case .. " the bars header")
    end
    check("vs best:")
    NS.Results.ShowFight("best")
    assertEqual(ui.kind, "runnerUp")
    check("vs runner-up:")
    -- The pure pair stays plain: the tooltips write it.
    assertEqual(NS.ResultsCompare.PairText("dps", 1100, 1000), NS.Format.Number(1000) .. " \194\187 " .. NS.Format.Number(1100))
    -- A skin switch repaints the window; the bars stay the palette's (a data hue).
    local W = dofile(T.root .. "/tests/_kit/skin_switch.lua")
    local Skin = M.LibStub("LibKa0s-Skin-1.0")
    Skin:RegisterSkin({ key = W.PROBE_KEY, label = "Probe", tokens = W.probeTokens(Skin) })
    Skin:SetChoice("CombatTrail", "ka0s", W.PROBE_KEY)
    local row = NS.ResultsCompare.Rows()[1]
    sameHue(M.__paint(row.barA).color, P.THIS_BAR, P.BAR_A, "under the probe skin, this fight's bar")
    sameHue(M.__paint(row.barB).color, P.BEST_BAR, P.BAR_A, "under the probe skin, the other's bar")
end)

local TRINKET, POTION, FLASK, HIDDEN = 212456, 211001, 212283, 5512
local function usage(used) return { v = 1, used = used, candidates = {} } end

test("compare: trinkets and consumables used by both fights, side by side", function()
    local NS, M = fresh()
    local Cmp, P = NS.ResultsCompare, NS.Constants.PALETTE
    local mid = rec(NS, { id = "mid", dps = 2000 })
    mid.usage = usage({
        { itemID = POTION, kind = "potion", times = { 3 }, n = 1, src = "cast" },
        { itemID = TRINKET, kind = "gear", slot = 13, times = { 5, 95 }, n = 2, src = "cast" },
        { itemID = HIDDEN, kind = "other", times = { 1 }, n = 1, src = "cast" },
        { kind = "enchant", n = 1, src = "buff" },
    })
    local best = rec(NS, { id = "best", dps = 3000 })
    best.usage = usage({
        { itemID = FLASK, kind = "flask", n = 1, src = "buff" },
        { itemID = TRINKET, kind = "gear", slot = 13, times = { 4 }, n = 1, src = "cast" },
    })
    local bare = rec(NS, { id = "bare", dps = 1000 })
    bare.usage = usage({})
    local old = rec(NS, { id = "old", dps = 500 })
    save(NS, mid, best, bare, old)
    assertTrue(NS.Usage.Hide(HIDDEN), "a hidden item is never listed")
    local rows = Cmp.UsageRows(NS.Recorder.Get("mid"), NS.Recorder.Get("best"))
    assertEqual(#rows, 3, "the trinket, the potion and the flask; never a hidden item or an enchant")
    assertEqual(rows[1].itemID, TRINKET, "gear first")
    assertTrue(rows[1].a ~= nil and rows[1].b ~= nil, "the trinket on both sides")
    assertEqual(rows[2].itemID, POTION, "then this fight's consumables")
    assertNil(rows[2].b, "the other fight drank no potion")
    assertEqual(rows[3].itemID, FLASK, "then the other's")
    assertNil(rows[3].a)
    -- The window: a row for each, this side yellow, the other blue, a missing side "not used".
    detailOn(NS, "mid").w.compare:__fire("OnClick")
    local ui = Cmp.__ui()
    assertEqual(ui.usageTitle:GetText(), "Trinkets and consumables")
    local shown = Cmp.UsageLines()
    assertEqual(#shown, 3)
    assertEqual(shown[1].this:GetText(), "x2 at 0:05, 1:35")
    assertEqual(shown[1].other:GetText(), "at 0:04")
    sameHue(M.__paint(shown[1].this).textColor, P.THIS_TEXT, nil, "this fight's uses")
    sameHue(M.__paint(shown[1].other).textColor, P.BEST_TEXT, nil, "the other's uses")
    assertEqual(shown[2].other:GetText(), "not used")
    assertEqual(shown[3].this:GetText(), "not used")
    assertEqual(shown[3].other:GetText(), "active at the start")
    assertEqual(shown[1].name:GetText(), NS.ResultsUsage.Name({ itemID = TRINKET }))
    assertFalse(ui.usageNone:IsShown())
    -- The window grows a line for each row.
    local _, h1 = Cmp.Size(1, 1, 1)
    local _, h3 = Cmp.Size(1, 1, 3)
    assertEqual(h3 - h1, 2 * Cmp.USAGE_ROW_H)
    assertEqual(ui.height, select(2, Cmp.Size(1, 1, 3)), "sized for its three usage rows")
    -- Nothing used on either side, and not recorded on both.
    -- A side with no usage record says so in its column.
    NS.Results.CompareWith("old")
    shown = Cmp.UsageLines()
    assertEqual(#shown, 2, "this fight's trinket and potion")
    assertEqual(shown[1].other:GetText(), "not recorded")
    assertEqual(shown[1].this:GetText(), "x2 at 0:05, 1:35")
    local NS2 = fresh()
    local a, b = rec(NS2, { id = "a", dps = 2000 }), rec(NS2, { id = "b", dps = 3000 })
    a.usage, b.usage = usage({}), usage({})
    local c, d = rec(NS2, { id = "c", dps = 1000, encounterID = 9999 }), rec(NS2, { id = "d", dps = 1500, encounterID = 9999 })
    save(NS2, a, b, c, d)
    detailOn(NS2, "a").w.compare:__fire("OnClick")
    local ui2 = NS2.ResultsCompare.__ui()
    assertEqual(#NS2.ResultsCompare.UsageLines(), 0)
    assertTrue(ui2.usageNone:IsShown())
    assertEqual(ui2.usageNone:GetText(), "None used")
    detailOn(NS2, "c")
    assertTrue(ui2.usageNone:IsShown())
    assertEqual(ui2.usageNone:GetText(), "Usage not recorded for both fights.")
end)

test("compare: the Different loadout tooltip writes a Forever fight's talent points", function()
    local NS = fresh()
    local Cmp = NS.ResultsCompare
    local raid = NS.Loadouts.Store({ importString = "CQQAAAA", specID = 253, name = "Raid" })
    local aoe = NS.Loadouts.Store({ importString = "CQQBBBB", specID = 253, name = "AoE" })
    local a = rec(NS, { id = "a", dps = 1000, loadout = raid })
    local b = rec(NS, { id = "b", dps = 2000, loadout = aoe })
    a.who.class, a.who.trees = "HUNTER", { 31, 20, 0 }
    local lines = Cmp.LoadoutLines(a, b)
    assertEqual(lines[2], "This fight: " .. NS.ResultsLoadout.TalentsText(NS.ResultsLoadout.TalentsOf(a), a.who))
    assertTrue(lines[2]:find("31/20/0", 1, true) ~= nil, lines[2])
    assertEqual(lines[3], "The other fight: AoE")
end)
