-- tests/test_timeline.lua — the ability timeline (plan Task 4.3, spec §7): the pure rows (one per
-- ability and caster across both fights, long cooldowns first, then by count), the packed casts
-- decoded, the pet toggle, the compared fight's lanes on its own start, the compare target (picked,
-- best, runner-up), the axis and zoom arithmetic; and the window: opened from the detail's Timeline
-- button over the Results window under its cover, its lanes and strips, the zoom and pan controls and
-- the wheel, Escape going to it first, and closing with the Results window.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local NOW = os.time()

-- The spells: a 3:00 cooldown, a 45 s one, a 13 s one, a filler, and the pet's filler.
local BIG, MID, SHORT, FILLER, PET = 1122, 6353, 17962, 29722, 3110
local COOLDOWNS = { [BIG] = 180000, [MID] = 45000, [SHORT] = 13000 }

local function fresh()
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        m.StaticPopup_Show = function() end
        m.StaticPopup_Hide = function() end
    end }
    return inst.NS, inst.mocks
end

-- A packed cast list from { { t, spellID, pet? }, ... }.
local function pack(NS, list)
    local casts = {}
    for n, c in ipairs(list) do
        casts[n] = { t = c[1], spellID = c[2], unit = c[3] and "pet" or "player", interrupted = false }
    end
    return NS.CastCodec.Encode(casts)
end

-- This fight: BIG once, MID twice (one pre-pull), SHORT once, FILLER three times, the pet's twice.
local THIS = { { -1.5, MID }, { 1, BIG }, { 2, FILLER }, { 4, SHORT }, { 5, FILLER }, { 6, PET, true },
               { 9, FILLER }, { 12, PET, true }, { 50, MID } }
-- The compared fight: no BIG, MID once, SHORT twice, FILLER once.
local OTHER = { { 0.5, MID }, { 3, SHORT }, { 8, FILLER }, { 20, SHORT } }

local n = 0
--- A stored-shape record on the logged-in character, on one boss board. `o`: id, dps, casts (a list
--- for pack), duration, t.
local function rec(NS, o)
    n = n + 1
    local me = NS.Identity.Who()
    local who = { name = me.name, realm = me.realm, client = me.client, class = me.class or "HUNTER",
                  specID = me.specID, specName = me.specName, ilvl = 721.4 }
    local ident = { content = "raid", targetName = "Vorasius", encounterID = 3176, encounterName = "Vorasius",
                    instanceName = "The Voidspire", difficultyID = 15, difficultyName = "Heroic", isBoss = true }
    local dps = o.dps or 1000
    local duration = o.duration or 60
    return {
        schema = 1, id = o.id, t = o.t or (NOW - n * 3600), duration = duration, status = "final",
        who = who, identity = ident, boardKey = NS.Identity.BoardKey(ident),
        damage = { merged = dps * duration, player = dps * duration }, dps = dps, meterDps = dps,
        build = "120105", version = "0.1.0",
        spells = NS.CastCodec.EncodeSpells({ { spellID = FILLER, total = dps * duration, isPet = false } }),
        casts = o.casts and pack(NS, o.casts) or nil, cooldowns = COOLDOWNS,
    }
end

local function save(NS, ...)
    for _, r in ipairs({ ... }) do assertTrue(NS.Recorder.Save(r), "saved " .. tostring(r.id)) end
end

local function key(row) return (row.pet and "p" or "") .. row.spellID end
local function keys(rows)
    local out = {}
    for i, row in ipairs(rows) do out[i] = key(row) end
    return table.concat(out, ",")
end

-- The Results window on fight `id`, its Timeline button clicked: the timeline's built window.
local function open(NS, id)
    assertTrue(NS.Results.ShowFight(id))
    local pane = NS.Results.__ui().detail
    assertTrue(pane.w.timeline:IsEnabled(), "the Timeline button is live for a fight with casts")
    pane.w.timeline:__fire("OnClick")
    local ui = NS.ResultsTimeline.__ui()
    assertTrue(ui ~= nil, "the timeline was built")
    return ui, pane
end

local function marksIn(NS, lane, id)
    local out = {}
    for _, d in ipairs(NS.ResultsTimeline.Marks()) do
        if d.lane == lane and (id == nil or d.cast.spellID == id) then out[#out + 1] = d end
    end
    return out
end

-- ── pure ────────────────────────────────────────────────────────────────────────────────────────

test("timeline: rows order long CDs first", function()
    local NS = T.NS
    local D = NS.ResultsTimelineData
    local rows = D.Rows(rec(NS, { id = "a", casts = THIS }), rec(NS, { id = "b", casts = OTHER }))
    -- BIG (3:00) then MID (45 s); then by this fight's count: FILLER 3, the pet 2, SHORT 1.
    assertEqual(keys(rows), BIG .. "," .. MID .. "," .. FILLER .. ",p" .. PET .. "," .. SHORT)
    local by = {}
    for _, row in ipairs(rows) do by[key(row)] = row end
    assertEqual(by[tostring(BIG)].cd, 180000)
    assertEqual(by[tostring(SHORT)].cd, 13000, "a short cooldown is kept, not sorted on")
    assertEqual(by[tostring(FILLER)].countA, 3)
    assertEqual(by[tostring(FILLER)].countB, 1)
    assertEqual(by[tostring(BIG)].countB, 0, "the compared fight never cast it: an empty lane")
    assertEqual(#by[tostring(BIG)].b, 0)
    assertEqual(D.CooldownLine(by[tostring(BIG)]), "3:00 cooldown")
    assertEqual(D.CooldownLine(by[tostring(SHORT)]), "", "no cooldown line under 29 s")
    -- A tie on this fight's count goes to the compared fight's, then the player before the pet.
    local tie = D.Rows(rec(NS, { id = "c", casts = { { 1, SHORT }, { 2, FILLER } } }),
        rec(NS, { id = "d", casts = { { 1, FILLER }, { 2, FILLER } } }))
    assertEqual(keys(tie), FILLER .. "," .. SHORT)
end)

test("timeline: decodes packed casts", function()
    local NS = T.NS
    local D = NS.ResultsTimelineData
    local r = rec(NS, { id = "a", casts = THIS })
    assertEqual(type(r.casts), "string", "the record holds the packed string")
    local built = D.Build(r, nil)
    assertEqual(built.len, 60, "the axis is the fight's length")
    assertEqual(#built.stripA, #THIS, "every cast is an icon")
    assertEqual(built.stripA[1].t, -1.5, "the pre-pull cast first, at its negative time")
    assertEqual(built.stripA[1].spellID, MID)
    assertTrue(built.stripA[6].pet, "the pet's cast is marked")
    assertEqual(#built.stripB, 0, "no compared fight: an empty strip")
    local by = {}
    for _, row in ipairs(built.rows) do by[key(row)] = row end
    assertEqual(table.concat(by[tostring(MID)].a, ","), "-1.5,50", "each row's times in order")
    assertTrue(D.Has(r))
    assertFalse(D.Has(rec(NS, { id = "none" })), "no casts stored")
    assertFalse(D.Has(nil))
    -- A pre-pull cast sits at 0:00 and a tail past the end at the end.
    assertEqual(D.MarkX(-1.5, 60, 602), 1)
    assertEqual(D.MarkX(90, 60, 602), 601)
    assertEqual(D.MarkX(30, 60, 602), 301)
    assertNil(D.MarkX(nil, 60, 602))
end)

test("timeline: pet toggle hides pet rows", function()
    local NS = T.NS
    local D = NS.ResultsTimelineData
    local r = rec(NS, { id = "a", casts = THIS })
    local on = D.Build(r, nil, { showPet = true })
    local off = D.Build(r, nil, { showPet = false })
    assertTrue(keys(on.rows):find("p" .. PET, 1, true) ~= nil, "the pet's row with the toggle on")
    assertTrue(keys(off.rows):find("p" .. PET, 1, true) == nil, "and gone with it off")
    assertEqual(#off.rows, #on.rows - 1)
    assertEqual(#off.stripA, #THIS - 2, "the pet's icons go with its row")
    assertTrue(D.HasPet(r, nil))
    assertFalse(D.HasPet(rec(NS, { id = "b", casts = OTHER }), nil))
    assertEqual(#D.Build(r).rows, #on.rows, "shown unless turned off")
end)

test("timeline: compare lanes align to their own fight start", function()
    local NS = T.NS
    local D = NS.ResultsTimelineData
    -- Two fights days apart, a long one and a short one, each with a cast 5 s in.
    local a = rec(NS, { id = "a", t = NOW - 86400 * 3, duration = 40, casts = { { 5, FILLER } } })
    local b = rec(NS, { id = "b", t = NOW, duration = 90, casts = { { 5, FILLER }, { 80, FILLER } } })
    local built = D.Build(a, b)
    assertEqual(built.len, 90, "the axis is the longer fight's")
    local row = built.rows[1]
    assertEqual(row.a[1], 5)
    assertEqual(row.b[1], 5, "the compared fight's times are from its own start")
    assertEqual(D.MarkX(row.a[1], built.len, 400), D.MarkX(row.b[1], built.len, 400), "the same x")
end)

test("timeline: a race runs on the race clock, from its first hit, with its buzzer (ruling X9)", function()
    local NS = T.NS
    local D = NS.ResultsTimelineData
    -- A 30 s race whose first hit came 2 s after combat entry, 40 s from combat entry to its end.
    local race = rec(NS, { id = "race", duration = 40, casts = { { 1, MID }, { 2, BIG }, { 7, FILLER } } })
    race.race = { length = 30, status = "complete", flags = {}, firstHit = 2 }
    local fight = rec(NS, { id = "fight", duration = 30, casts = { { 7, FILLER } } })
    local built = D.Build(race, fight)
    local filler
    for _, row in ipairs(built.rows) do if row.spellID == FILLER then filler = row end end
    if NS.Compat.IsForever() then
        -- No race controls on WoW Forever: a saved race lists as a fight, on the fight's clock.
        assertEqual(built.len, 40)
        assertNil(built.buzzer, "no buzzer line")
        assertEqual(built.stripA[1].t, 1)
        assertEqual(filler.a[1], 7)
        return
    end
    assertEqual(built.len, 38, "the race's own clock: 40 s from combat entry less its first 2")
    assertEqual(built.buzzer, 30, "the buzzer at the race length")
    assertEqual(built.stripA[1].t, -1, "a cast before the first hit sits before the race clock's zero")
    assertEqual(built.stripA[2].t, 0, "the opener on 0:00")
    assertEqual(filler.a[1], 5, "the lanes on the race clock too")
    assertEqual(filler.b[1], 7, "a compared fight stays on its own clock")
    -- A race saved without its offset (or an older one) is not shifted, and keeps its buzzer.
    race.race.firstHit = nil
    built = D.Build(race, nil)
    assertEqual(built.len, 40)
    assertEqual(built.buzzer, 30)
    assertEqual(built.stripA[1].t, 1)
    -- A race shorter than its length (incomplete) still spans to the buzzer.
    race.duration = 12
    assertEqual(D.Build(race, nil).len, 30)
    assertNil(D.Build(fight, nil).buzzer, "a fight has no buzzer")
end)

test("timeline: the compare target is the pick, else the best, else the runner-up", function()
    local NS = fresh()
    local D = NS.ResultsTimelineData
    save(NS, rec(NS, { id = "best", dps = 3000, casts = OTHER }), rec(NS, { id = "mid", dps = 2000, casts = THIS }),
        rec(NS, { id = "low", dps = 1000, casts = THIS }))
    local other, kind = D.CompareTarget(NS.Recorder.Get("mid"))
    assertEqual(other and other.id, "best")
    assertEqual(kind, "best")
    other, kind = D.CompareTarget(NS.Recorder.Get("best"))
    assertEqual(other and other.id, "mid", "the best is compared with the runner-up")
    assertEqual(kind, "runnerUp")
    NS.Results.Show()
    assertTrue(NS.Results.CompareWith("low"))
    other, kind = D.CompareTarget(NS.Recorder.Get("mid"))
    assertEqual(other and other.id, "low")
    assertEqual(kind, "picked")
    other = D.CompareTarget(NS.Recorder.Get("low"))
    assertEqual(other and other.id, "best", "a pick is never compared with itself")
    assertEqual(D.KindLabel("runnerUp"), "Runner-up")
    assertTrue(D.OtherLabel(other, "best"):find("^Best \194\183 ") ~= nil, "what it is, then its date")
    assertNil(D.OtherLabel(nil, "best"))
    local _, label, note = D.Legend(NS.Recorder.Get("mid"), nil, nil)
    assertEqual(label, "No fight to compare with")
    assertTrue(note ~= nil, "a note under the bar")
end)

test("timeline: the axis, the zoom and the stacking arithmetic", function()
    local D = T.NS.ResultsTimelineData
    assertEqual(table.concat(D.Ticks(60, 1), ","), "0,15,30,45,60")
    assertEqual(table.concat(D.Ticks(60, 2), ","), "0,10,20,30,40,50,60", "a round step zoomed in")
    assertEqual(D.ZoomAt(0), 1)
    assertEqual(D.ZoomAt(99), D.ZOOMS[#D.ZOOMS])
    assertEqual(D.ClampPos(0.9, 2), 0.5, "the view stays on the axis")
    assertEqual(D.ClampPos(-1, 2), 0)
    assertEqual(D.Rezoom(0, 1, 2), 0.25, "the middle stays in the middle")
    assertEqual(D.Rezoom(0, 1, 2, 0), 0, "zoomed about the left edge")
    assertEqual(D.CursorAt(50, 0, 100), 0.5)
    assertNil(D.CursorAt(150, 0, 100), "off the lanes")
    assertEqual(D.PosRange(1), 0)
    assertEqual(D.BarBand(1), 0)
    assertTrue(D.BarBand(2) > 0, "the scrollbar's band zoomed in")
    local rows, count, over = D.Stack({ 0, 5, 10, 40 }, 15, 2)
    assertEqual(table.concat(rows, ","), "1,2,1,1", "too close stacks onto the next row; past the cap, overlaps")
    assertEqual(count, 2)
    assertTrue(over[3], "the third icon went past the cap")
    local cw, laneX, laneW = D.LaneGeometry(640)
    assertEqual(cw, 640 - 2 * D.PAD)
    assertEqual(laneX, D.NAME_W + D.GAP)
    assertEqual(laneW, cw - laneX - D.COUNT_GAP - D.COUNT_W)
end)

-- ── the window ──────────────────────────────────────────────────────────────────────────────────

test("timeline: opens from the detail over the Results window, under its cover", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "best", dps = 3000, casts = OTHER }), rec(NS, { id = "this", dps = 1000, casts = THIS }))
    local ui = open(NS, "this")
    assertTrue(NS.ResultsTimeline.IsShown())
    assertTrue(NS.Results.IsCovered(), "the Results window wears its dim cover")
    local _, _, _, _, width, height = NS.Results.Placement()
    assertEqual(ui.width, math.max(NS.ResultsTimelineData.MIN_WIDTH, width), "the Results window's size")
    assertEqual(ui.height, math.max(NS.ResultsTimelineData.MIN_HEIGHT, height))
    assertEqual(#ui.rows, 5)
    assertEqual(ui.record.id, "this")
    assertEqual(ui.other.id, "best", "compared with the best on its board")
    assertTrue(ui.legendB:GetText():find("^Best") ~= nil, "the legend says what it is")
    assertEqual(#marksIn(NS, "a", FILLER), 3, "this fight's ticks on the top lane")
    assertEqual(#marksIn(NS, "b", SHORT), 2, "the compared fight's on the bottom lane")
    assertEqual(#NS.ResultsTimeline.Icons(), #THIS + #OTHER, "every cast an icon in the strips")
    assertTrue(ui.petToggle:IsShown(), "the pet toggle, a pet having cast")
    -- The first pair is the long cooldown, its cooldown under its name.
    local first = ui.pairs.active[1]
    assertEqual(first.row.spellID, BIG)
    assertEqual(first.cd:GetText(), "3:00 cooldown")
    assertEqual(first.countA:GetText(), "1")
    assertEqual(first.countB:GetText(), "0")
    -- Closing it takes the cover down.
    ui.close:__fire("OnClick")
    assertFalse(NS.ResultsTimeline.IsShown())
    assertFalse(NS.Results.IsCovered())
end)

test("timeline: pet toggle hides pet rows in the window, the zoom kept", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "this", casts = THIS }))
    local ui = open(NS, "this")
    NS.ResultsTimeline.ZoomBy(2)
    local zoom = NS.ResultsTimeline.Zoom()
    assertTrue(zoom > 1)
    local before = #ui.rows
    ui.petToggle:__fire("OnClick")
    assertFalse(NS.ResultsTimeline.showPet)
    assertEqual(#ui.rows, before - 1, "the pet's row is gone")
    for _, d in ipairs(NS.ResultsTimeline.Icons()) do assertFalse(d.cast.pet == true, "no pet icon") end
    assertEqual(NS.ResultsTimeline.Zoom(), zoom, "the zoom is kept")
    ui.petToggle:__fire("OnClick")
    assertEqual(#ui.rows, before)
    -- The detail moves to another fight: the timeline follows it.
    save(NS, rec(NS, { id = "solo", casts = OTHER }))
    NS.Results.ShowFight("solo")
    assertEqual(ui.record.id, "solo", "the timeline followed the detail")
    assertTrue(ui.petToggle:IsShown(), "the compared fight has a pet cast")
    -- Neither fight with a pet cast: no toggle.
    local NS2 = fresh()
    save(NS2, rec(NS2, { id = "x", dps = 2000, casts = OTHER }), rec(NS2, { id = "y", casts = OTHER }))
    local ui2 = open(NS2, "y")
    assertFalse(ui2.petToggle:IsShown(), "no pet, no toggle")
end)

test("timeline: zoom, pan and the wheel", function()
    local NS, M = fresh()
    save(NS, rec(NS, { id = "this", casts = THIS }))
    local ui = open(NS, "this")
    local TL = NS.ResultsTimeline
    assertEqual(TL.Zoom(), 1)
    assertFalse(ui.bar:IsShown(), "no scrollbar at 1x")
    assertFalse(ui.scrollLeft:IsEnabled(), "no pan at 1x")
    assertTrue(TL.ZoomBy(1))
    assertEqual(TL.Zoom(), 1.5)
    assertTrue(ui.bar:IsShown(), "the scrollbar zoomed in")
    assertTrue(ui.pos > 0, "a button's zoom keeps the view's middle")
    assertTrue(ui.scrollLeft:IsEnabled())
    for _ = 1, 8 do ui.scrollLeft:__fire("OnClick") end
    assertEqual(ui.pos, 0)
    assertFalse(ui.scrollLeft:IsEnabled(), "at 0:00 nothing to the left")
    assertTrue(ui.scrollRight:IsEnabled())
    local pos = ui.pos
    ui.scrollRight:__fire("OnClick")
    assertTrue(ui.pos > pos, "panned toward the end")
    -- Shift+wheel pans; Ctrl+wheel zooms (Ctrl first); the plain wheel scrolls.
    M.__modifiers.shift = true
    pos = ui.pos
    TL.Wheel(1)
    assertTrue(ui.pos < pos, "Shift+wheel up pans toward 0:00")
    M.__modifiers.ctrl = true
    TL.Wheel(1)
    assertEqual(TL.Zoom(), 2, "Ctrl+wheel up zooms in")
    M.__modifiers.ctrl, M.__modifiers.shift = false, false
    TL.Wheel(-1)
    assertEqual(TL.Zoom(), 2, "the plain wheel never zooms")
    assertTrue(TL.ResetZoom())
    assertEqual(TL.Zoom(), 1)
    assertEqual(ui.pos, 0)
    assertFalse(TL.ResetZoom(), "already at 1x")
    -- Another fight goes back to 1x.
    TL.ZoomBy(3)
    save(NS, rec(NS, { id = "next", casts = OTHER }))
    NS.Results.ShowFight("next")
    assertEqual(TL.Zoom(), 1, "a new fight starts at 1x")
end)

test("timeline: Escape goes to it first, and it closes with the Results window", function()
    local NS, M = fresh()
    save(NS, rec(NS, { id = "this", casts = THIS }))
    local ui = open(NS, "this")
    local results = NS.Results.__ui().frame
    -- The close stack hides both: the timeline's own OnHide, then the Results window's, which shows
    -- itself again while the cover is up.
    ui.frame:Hide()
    ui.frame:__fire("OnHide")
    results:Hide()
    results:__fire("OnHide")
    assertTrue(results:IsShown(), "the Results window stays: the Escape was the timeline's")
    assertFalse(NS.ResultsTimeline.IsShown())
    if M.__fireTimers then M.__fireTimers() end
    assertFalse(NS.Results.IsCovered(), "the cover goes once the close settles")
    -- Open again, then close the Results window: the timeline goes with it.
    open(NS, "this")
    NS.Results.Hide()
    assertFalse(NS.ResultsTimeline.IsShown(), "closes with the Results window")
end)

test("timeline: the empty cases", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "this", casts = THIS }), rec(NS, { id = "bare", dps = 9000 }))
    local ui = open(NS, "this")
    assertEqual(ui.other.id, "bare", "the best has no casts")
    assertTrue(ui.note:IsShown(), "a note: its blue lanes stay empty")
    assertEqual(ui.pairs.active[1].countB:GetText(), "", "no compared count without its casts")
    -- The detail moves to the fight with no casts while the window is open.
    NS.Results.ShowFight("bare")
    assertTrue(ui.empty:IsShown())
    assertEqual(ui.empty:GetText(), "No casts recorded for this fight.")
    assertFalse(NS.Results.__ui().detail.w.timeline:IsEnabled(), "and its button is off")
end)

test("timeline: a stand-down refuses the open", function()
    local NS = fresh()
    save(NS, rec(NS, { id = "this", casts = THIS }))
    NS.Results.ShowFight("this")
    local pane = NS.Results.__ui().detail
    NS.SetByPath("general.enabled", false)
    assertFalse(NS.ResultsTimeline.Open(pane), "nothing opens while stood down")
end)
