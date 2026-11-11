-- tests/test_results_sections.lua — the fight detail's folding sections (v0.2 plan Task C3, ported
-- from DPS Race's tests/test_results_sections.lua): every section heading's arrow (chevron-down open,
-- chevron-right folded), a click on the arrow or on the heading's text folding and opening it, a
-- folded section's body hidden and the sections under it moved up by exactly that body's height, the
-- state stored in profile.results.collapsedSections and read back by a rebuilt pane, kept by Reset
-- position, and Add Note opening a folded Note.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local NOW = os.time()

local function fresh(mutate)
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        m.StaticPopup_Show = function() end
        m.StaticPopup_Hide = function() end
        if mutate then mutate(m) end
    end }
    return inst.NS, inst.mocks
end

-- A stored fight on the logged-in character with one spell, a note and one used potion.
local function rec(NS, id, note)
    local me = NS.Identity.Who()
    local ident = { content = "raid", targetName = "Vorasius", encounterID = 3176, encounterName = "Vorasius",
                    instanceName = "The Voidspire", difficultyID = 15, difficultyName = "Heroic", isBoss = true }
    return {
        schema = 2, id = id, t = NOW - 60, duration = 60, status = "final",
        who = { name = me.name, realm = me.realm, client = me.client, class = me.class or "HUNTER",
                specID = me.specID, specName = me.specName, ilvl = 721.4 },
        identity = ident, boardKey = NS.Identity.BoardKey(ident),
        damage = { merged = 60000, player = 60000 }, dps = 1000, meterDps = 990, build = "120105",
        version = "0.1.0", note = note,
        spells = NS.CastCodec.EncodeSpells({ { spellID = 34026, total = 60000, isPet = false } }),
        usage = { v = 1, edited = false, candidates = {},
                  used = { { itemID = 211001, kind = "potion", times = { 3 }, n = 1, src = "cast" } } },
        targets = { { name = "Redridge Brute", total = 40000 }, { name = "Redridge Mystic", total = 20000 } },
    }
end

local function open(NS, note)
    assertTrue(NS.Recorder.Save(rec(NS, "a", note == nil and "pulled early" or note)))
    -- The session's chart, so the Damage profile section is there to fold.
    NS.Slices.Seed("a", { step = 2, values = { 2000, 4000, 6000 }, pet = {}, count = 3, filled = 3 })
    assertTrue(NS.Results.ShowFight("a"))
    return NS.Results.__ui().detail
end

local function y(region) return region.__points[1][5] end
local function x(region) return region.__points[1][4] end

-- Each section's heading, a part of its body, and the hover over the heading's text.
local function parts(d)
    local w = d.w
    return {
        chart = { w.chartTitle, w.chart.plot, w.chartHover },
        spells = { w.spellsTitle, w.listHost, w.spellsHover },
        loadout = { d.lo.title, d.lo.talents, d.lo.titleHover },
        usage = { d.usage.title, d.usage.items[1], d.usage.titleHover },
        targets = { d.targets.title, d.targets.rows[1].name, d.targets.titleHover },
        note = { w.noteTitle, w.note, w.noteHover },
    }
end

-- The heading under each section's (the one its fold moves up), the last section's none.
local NEXT = { chart = "spells", spells = "loadout", loadout = "usage", usage = "targets", targets = "note" }

test("sections: every heading has an arrow, open (chevron-down) by default, its text after it", function()
    local NS = fresh()
    local D = NS.ResultsDetail
    local d = open(NS)
    assertEqual(table.concat(D.SECTIONS, ","), "chart,spells,loadout,usage,targets,note")
    assertEqual(D.ARROW, 14)
    assertEqual(D.INDENT, D.ARROW + 2)
    local p = parts(d)
    for _, key in ipairs(D.SECTIONS) do
        local arrow = d.heads[key]
        assertTrue(arrow ~= nil, key .. " has no arrow")
        assertTrue(arrow:IsShown(), key .. "'s arrow is hidden")
        assertEqual(arrow.iconName, "chevron-down", key)
        assertEqual(arrow.tip, "Collapse this section", key)
        assertFalse(D.IsCollapsed(key), key)
        assertEqual(x(p[key][1]), D.INDENT, key .. "'s heading text is not after its arrow")
        assertTrue(p[key][2]:IsShown(), key .. "'s body is hidden")
    end
    -- A fresh profile folds nothing.
    assertNil(next(NS.defaults.profile.results.collapsedSections), "the default folds nothing")
end)

test("sections: the arrow folds a section, hides its body, stores it, and moves the next heading up", function()
    local NS = fresh()
    local D = NS.ResultsDetail
    local d = open(NS)
    local p = parts(d)
    local L, U = NS.ResultsLoadout, NS.ResultsUsage
    -- What each body takes below its heading, by the layout's own numbers.
    local body = {
        -- The chart's block under the section's heading line, which is its own (Pane:layoutChart).
        chart = d.w.chart.blockH - NS.HudChart.HEAD_H + 4,
        spells = NS.HudBreakdown.Height(1),
        loadout = L.LINE_H + 4 + L.BUTTON_H + 8,
        usage = U.ROW_H + 8,
        targets = 2 * NS.ResultsTargets.ROW_H + 8,
    }
    for _, key in ipairs(D.SECTIONS) do
        local nextKey = NEXT[key]
        local before = nextKey and y(p[nextKey][1])
        local contentH = d.contentH
        d.heads[key]:__fire("OnClick")
        assertTrue(D.IsCollapsed(key), key .. " did not fold")
        assertEqual(NS.db.profile.results.collapsedSections[key], true, key .. " is stored")
        assertEqual(d.heads[key].iconName, "chevron-right", key)
        assertEqual(d.heads[key].tip, "Expand this section", key)
        assertTrue(p[key][1]:IsShown(), key .. "'s heading went with its body")
        assertFalse(p[key][2]:IsShown(), key .. "'s body is still shown")
        if nextKey then
            assertEqual(y(p[nextKey][1]) - before, body[key], key .. ": the next heading moved by the body")
        else
            assertTrue(d.contentH < contentH, key .. ": the content shrank")
        end
        -- Open again: stored as nothing, the body back where it was.
        d.heads[key]:__fire("OnClick")
        assertFalse(D.IsCollapsed(key))
        assertNil(NS.db.profile.results.collapsedSections[key], key .. ": open is stored as nil")
        assertEqual(d.heads[key].iconName, "chevron-down", key)
        assertTrue(p[key][2]:IsShown(), key .. "'s body came back")
        if nextKey then assertEqual(y(p[nextKey][1]), before, key .. ": the next heading went back") end
    end
end)

test("sections: a left click on the heading's text folds it; a right click does not", function()
    local NS = fresh()
    local D = NS.ResultsDetail
    local d = open(NS)
    local p = parts(d)
    for _, key in ipairs(D.SECTIONS) do
        local hover = p[key][3]
        assertTrue(hover ~= nil, key .. " has no heading hover")
        hover:__fire("OnMouseUp", "RightButton")
        assertFalse(D.IsCollapsed(key), key .. ": a right click folded it")
        hover:__fire("OnMouseUp", "LeftButton")
        assertTrue(D.IsCollapsed(key), key .. ": the heading's text did not fold it")
        assertFalse(p[key][2]:IsShown(), key)
        hover:__fire("OnMouseUp", "LeftButton")
        assertFalse(D.IsCollapsed(key), key)
    end
end)

test("sections: a rebuilt pane reads the folds back; Reset position keeps them", function()
    local NS = fresh()
    local D = NS.ResultsDetail
    NS.db.profile.results.collapsedSections = { spells = true, usage = true }
    local d = open(NS)
    assertTrue(D.IsCollapsed("spells"))
    assertEqual(d.heads.spells.iconName, "chevron-right")
    assertFalse(d.w.listHost:IsShown(), "the stored fold hides the breakdown")
    assertFalse(d.usage.items[1]:IsShown(), "and the usage rows")
    assertFalse(d.usage.edit:IsShown(), "a folded Usage hides its Edit")
    assertEqual(d.heads.chart.iconName, "chevron-down", "the others open")
    NS.Results.ResetPosition()
    assertTrue(D.IsCollapsed("spells"), "Reset position keeps the folds")
    assertTrue(D.IsCollapsed("usage"))
    -- An old profile with no table: made on first use.
    NS.db.profile.results.collapsedSections = nil
    assertFalse(D.IsCollapsed("chart"))
    D.SetCollapsed("chart", true)
    assertEqual(NS.db.profile.results.collapsedSections.chart, true)
end)

test("sections: the Note's arrow shows with a note only; Add Note opens a folded Note", function()
    local NS = fresh()
    local D = NS.ResultsDetail
    local d = open(NS, "")
    assertFalse(d.heads.note:IsShown(), "no note, no Note heading and no arrow")
    D.SetCollapsed("note", true)
    d.w.addNote:__fire("OnClick")
    assertFalse(D.IsCollapsed("note"), "Add Note opens the Note")
end)
