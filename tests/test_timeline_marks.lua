-- tests/test_timeline_marks.lua — the ability timeline's cast marks (v0.2 plan Task D1,
-- modules/Results_TimelineMarks.lua): By ability draws each cast as its ability's icon by default, with
-- the Casts icon's tooltip, or as a tick line (`results.timelineMarks`, its History row and the two
-- words on the By ability heading line, which redraw an open window keeping its zoom); a player's cast
-- in PALETTE.PLAYER_LINE and a pet's in PALETTE.PET_LINE, a tick tinted and an icon edged, the Casts
-- strips' icons edged the same; the lanes' clip padded so an icon at 0:00 shows whole; the icons along
-- a zoomed axis and moved, not re-pooled, while the grip is held. And the fights' own colors, THIS and
-- OTHER, the palette's text hues under every kit profile (the B1 review's Timeline.THIS fix).

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local NOW = os.time()
local FRAME = 1 / 60

-- The spells: a 3:00 cooldown, a 45 s one, a 13 s one, a filler, and the pet's filler.
local BIG, MID, SHORT, FILLER, PET = 1122, 6353, 17962, 29722, 3110
local COOLDOWNS = { [BIG] = 180000, [MID] = 45000, [SHORT] = 13000 }
-- This fight: a pre-pull MID, the pet's filler twice. The best: no pet.
local THIS = { { -1.5, MID }, { 1, BIG }, { 2, FILLER }, { 4, SHORT }, { 5, FILLER }, { 6, PET, true },
               { 9, FILLER }, { 12, PET, true }, { 50, MID } }
local BEST = { { 0.5, MID }, { 3, SHORT }, { 8, FILLER }, { 20, SHORT } }

-- Frames record where they are put, how big and whether they take the mouse (the kit's frames
-- no-op those setters), so the marks' geometry can be read back.
local function recordGeometry(m)
    local create = m.CreateFrame
    m.CreateFrame = function(kind, ...)
        local f = create(kind, ...)
        rawset(f, "__points", {})
        rawset(f, "SetPoint", function(self, ...) local p = rawget(self, "__points"); p[#p + 1] = { ... } end)
        rawset(f, "ClearAllPoints", function(self) rawset(self, "__points", {}) end)
        rawset(f, "SetSize", function(self, w, h) rawset(self, "__w", w); rawset(self, "__h", h) end)
        rawset(f, "SetWidth", function(self, w) rawset(self, "__w", w) end)
        rawset(f, "SetHeight", function(self, h) rawset(self, "__h", h) end)
        rawset(f, "EnableMouse", function(self, on) rawset(self, "__mouse", on and true or false) end)
        return f
    end
end

local function fresh()
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        recordGeometry(m)
        m.StaticPopup_Show = function() end
        m.StaticPopup_Hide = function() end
    end }
    return inst.NS, inst.mocks
end

local function pack(NS, list)
    local casts = {}
    for n, c in ipairs(list) do
        casts[n] = { t = c[1], spellID = c[2], unit = c[3] and "pet" or "player", interrupted = false }
    end
    return NS.CastCodec.Encode(casts)
end

local n = 0
local function rec(NS, o)
    n = n + 1
    local me = NS.Identity.Who()
    local who = { name = me.name, realm = me.realm, client = me.client, class = me.class or "HUNTER",
                  specID = me.specID, specName = me.specName, ilvl = 721.4 }
    local ident = { content = "raid", targetName = "Vorasius", encounterID = 3176, encounterName = "Vorasius",
                    instanceName = "The Voidspire", difficultyID = 15, difficultyName = "Heroic", isBoss = true }
    local dps, duration = o.dps or 1000, 60
    return {
        schema = 1, id = o.id, t = o.t or (NOW - n * 3600), duration = duration, status = "final",
        who = who, identity = ident, boardKey = NS.Identity.BoardKey(ident),
        damage = { merged = dps * duration, player = dps * duration }, dps = dps, meterDps = dps,
        build = "120105", version = "0.1.0",
        spells = NS.CastCodec.EncodeSpells({ { spellID = FILLER, total = dps * duration, isPet = false } }),
        casts = pack(NS, o.casts), cooldowns = COOLDOWNS,
    }
end

-- The timeline open on "this", compared with "best"; `mode` stored first when given.
local function opened(mode)
    local NS, M = fresh()
    if mode then NS.db.profile.results.timelineMarks = mode end
    for _, r in ipairs({ rec(NS, { id = "best", dps = 3000, casts = BEST }), rec(NS, { id = "this", casts = THIS }) }) do
        assertTrue(NS.Recorder.Save(r), "saved " .. r.id)
    end
    assertTrue(NS.Results.ShowFight("this"))
    NS.Results.__ui().detail.w.timeline:__fire("OnClick")
    local ui = assert(NS.ResultsTimeline.__ui(), "the timeline was never built")
    assertEqual(ui.other and ui.other.id, "best")
    return NS, ui, M
end

local function marksIn(NS, lane, id)
    local out = {}
    for _, d in ipairs(NS.ResultsTimeline.Marks()) do
        if d.lane == lane and (id == nil or d.cast.spellID == id) then out[#out + 1] = d end
    end
    return out
end

local function last(region)
    local p = rawget(region, "__points")
    return p[#p]
end
local function rgb(c) return ("%.2f,%.2f,%.2f"):format(c[1], c[2], c[3]) end

-- ── the colors and the setting ──────────────────────────────────────────────────────────────────

test("timeline marks: the fights' colors are the palette's text hues under this kit profile", function()
    local NS = fresh()
    local TL, P = NS.ResultsTimeline, NS.Constants.PALETTE
    -- Not the skin's gold copied at load: on WoW Forever the default skin is the client's own.
    assertEqual(rgb(TL.THIS), "1.00,0.82,0.00", "this fight gold")
    assertEqual(rgb(TL.THIS), rgb(P.THIS_TEXT))
    assertEqual(rgb(TL.OTHER), rgb(P.BEST_TEXT), "the compared fight blue")
end)

test("timeline marks: the caster colors are the palette's lines, and the row defaults to icons", function()
    local NS = fresh()
    local TL, P = NS.ResultsTimeline, NS.Constants.PALETTE
    assertEqual(rgb(TL.PLAYER_LINE), "0.50,0.52,1.00")
    assertEqual(rgb(TL.PET_LINE), "0.40,0.85,0.45")
    assertTrue(TL.PLAYER_LINE == P.PLAYER_LINE and TL.PET_LINE == P.PET_LINE, "the palette's own entries")
    assertTrue(TL.CasterColor(false) == TL.PLAYER_LINE and TL.CasterColor(true) == TL.PET_LINE)
    assertEqual(TL.MARK_A, 0.95)
    assertEqual(NS.defaults.profile.results.timelineMarks, "icon")
    assertEqual(TL.MarkMode(), "icon")
    local row = assert(NS.FindSchemaRow("results.timelineMarks"), "a schema row")
    assertEqual(row.default, "icon")
    assertEqual(row.page, "history")
    assertEqual(row.group, NS.HISTORY_TABS.results, "on the Results window tab")
    assertFalse(row.validate("foo"), "only icon or tick")
    assertTrue(row.validate("tick"))
    assertFalse(NS.SetByPath("results.timelineMarks", "foo"))
    assertTrue(NS.SetByPath("results.timelineMarks", "tick"))
    assertEqual(TL.MarkMode(), "tick")
    NS.ApplyDefault(row)
    assertEqual(NS.db.profile.results.timelineMarks, "icon", "Defaults puts icons back")
end)

-- ── icons ───────────────────────────────────────────────────────────────────────────────────────

test("timeline marks: by default every cast in By ability is its ability's icon on the lanes' layer", function()
    local NS, ui = opened()
    local TL, D = NS.ResultsTimeline, NS.ResultsTimelineData
    assertEqual(#marksIn(NS, "a"), #THIS)
    assertEqual(#marksIn(NS, "b"), #BEST)
    local _, laneX, laneW = D.LaneGeometry(ui.width)
    for _, d in ipairs(TL.Marks()) do
        assertEqual(d.kind, "icon")
        assertNil(d.tex, "no tick")
        assertTrue(d.frame:GetParent() == ui.marks, "on the lanes' layer")
        assertEqual(rawget(d.frame, "__w"), TL.LANE_ICON)
        assertEqual(rawget(d.frame, "__h"), TL.LANE_ICON)
        assertTrue(TL.LANE_ICON <= D.LANE_H - 2, "inside its lane")
        assertEqual(d.frame.tex.__texture, NS.HudBreakdown.SpellIcon(d.cast.spellID))
        assertTrue(rawget(d.frame, "__mouse"), "it takes the mouse")
        assertEqual(d.x, laneX + D.MarkX(d.cast.t, 60, laneW))
    end
    assertEqual(#ui.markPool.active, 0, "no tick drawn")
    assertEqual(#ui.hitPool.active, 0)
    assertEqual(#TL.Icons(), #THIS + #BEST, "the Casts strips unchanged")
end)

test("timeline marks: a lane icon's tooltip is the Casts icon's for the same cast", function()
    local NS, ui = opened()
    local TL, Tbl = NS.ResultsTimeline, NS.ResultsTable
    local shown
    local real = Tbl.SpellTip
    Tbl.SpellTip = function(window, owner, id, lines) shown = { window = window, owner = owner, id = id, lines = lines } end
    local d = marksIn(NS, "a", BIG)[1]
    d.frame:__fire("OnEnter")
    assertTrue(shown.window == ui.frame and shown.owner == d.frame, "beside the window, level with the icon")
    assertEqual(shown.id, BIG)
    local lane = shown.lines
    local strip
    for _, c in ipairs(TL.Icons()) do
        if c.side == "a" and c.cast.spellID == BIG then
            c.frame:__fire("OnEnter")
            strip = shown.lines
        end
    end
    assertEqual(lane[1], "Cast at 0:01")
    assertEqual(lane[2][1], ui.thisLabel, "which fight")
    assertEqual(#lane, #strip, "no overlap line")
    assertEqual(lane[1], strip[1])
    assertEqual(lane[2][1], strip[2][1])
    -- The pet's says so.
    local pet = marksIn(NS, "a", PET)[1]
    pet.frame:__fire("OnEnter")
    Tbl.SpellTip = real
    assertEqual(shown.lines[1], "Cast at 0:06 (pet)")
end)

test("timeline marks: a pre-pull cast's icon sits whole inside the lanes' padded clip", function()
    local NS, ui = opened()
    local TL, D = NS.ResultsTimeline, NS.ResultsTimelineData
    local _, laneX, laneW = D.LaneGeometry(ui.width)
    local d = marksIn(NS, "a", MID)[1]
    assertEqual(d.cast.t, -1.5)
    local at = last(d.frame)
    assertEqual(at[4], d.x - laneX + TL.CLIP_PAD, "the layer starts CLIP_PAD left of the lanes")
    assertTrue(at[4] >= TL.LANE_ICON / 2, "its left half inside the clip")
    assertEqual(last(ui.lanesClip)[4], laneX - TL.CLIP_PAD)
    assertEqual(rawget(ui.lanesClip, "__w"), laneW + 2 * TL.CLIP_PAD)
    assertEqual(rawget(ui.marks, "__w"), laneW + 2 * TL.CLIP_PAD)
    assertTrue(TL.CLIP_PAD < D.GAP and TL.CLIP_PAD < D.COUNT_GAP, "clear of the name cell and the counts")
end)

-- ── the caster colors ───────────────────────────────────────────────────────────────────────────

test("timeline marks: a player's cast is edged PLAYER_LINE and a pet's PET_LINE, in the lanes and the Casts strips", function()
    local NS, ui = opened()
    local TL = NS.ResultsTimeline
    local function check()
        for _, d in ipairs(TL.Marks()) do
            local want = d.cast.pet and TL.PET_LINE or TL.PLAYER_LINE
            assertEqual(rgb(d.frame.edge.__color), rgb(want), "a lane icon's edge")
            assertEqual(d.frame.edge.__color[4], 1, "opaque")
            assertEqual(d.frame.edge:GetWidth(), TL.LANE_ICON + 2, "1 px each side")
        end
        local pets = 0
        for _, d in ipairs(TL.Icons()) do
            local want = d.cast.pet and TL.PET_LINE or TL.PLAYER_LINE
            assertEqual(rgb(d.frame.edge.__color), rgb(want), "a Casts icon's edge")
            assertEqual(d.frame.edge:GetWidth(), TL.CAST_ICON + 2)
            if d.cast.pet then pets = pets + 1 end
        end
        assertEqual(pets, 2)
    end
    check()
    -- Pooled frames move to other casts: the best on top, then back.
    NS.Results.ShowFight("best")
    NS.Results.ShowFight("this")
    assertTrue(ui.frame:IsShown())
    check()
    -- The pet toggle off and on: a frame that held a pet's cast now holds the player's.
    TL.SetShowPet(false)
    for _, d in ipairs(TL.Marks()) do assertEqual(rgb(d.frame.edge.__color), rgb(TL.PLAYER_LINE)) end
    TL.SetShowPet(true)
    check()
end)

test("timeline marks: in tick mode a pet's tick is PET_LINE and a player's PLAYER_LINE in both lanes", function()
    local NS = opened("tick")
    local TL = NS.ResultsTimeline
    for _, d in ipairs(TL.Marks()) do
        assertEqual(d.kind, "tick")
        local want = d.cast.pet and TL.PET_LINE or TL.PLAYER_LINE
        assertEqual(rgb(d.tex.__vertex), rgb(want))
        assertEqual(d.tex.__vertex[4], TL.MARK_A)
    end
    assertEqual(rgb(marksIn(NS, "a", PET)[1].tex.__vertex), rgb(TL.PET_LINE))
    assertEqual(rgb(marksIn(NS, "b", FILLER)[1].tex.__vertex), rgb(TL.PLAYER_LINE), "the side no longer tints")
    assertEqual(rgb(marksIn(NS, "a", FILLER)[1].tex.__vertex), rgb(TL.PLAYER_LINE))
end)

-- ── switching ───────────────────────────────────────────────────────────────────────────────────

test("timeline marks: the setting written while the window is open redraws it as ticks, keeping the zoom", function()
    local NS, ui = opened()
    local TL, D = NS.ResultsTimeline, NS.ResultsTimelineData
    TL.ZoomBy(2)
    TL.Pan(-1)
    local pos = ui.pos
    assertTrue(pos > 0)
    assertTrue(NS.SetByPath("results.timelineMarks", "tick"))
    assertEqual(TL.Zoom(), 2, "the zoom kept")
    assertEqual(ui.pos, pos, "the pan kept")
    assertEqual(#TL.Marks(), #THIS + #BEST)
    assertEqual(#ui.laneIconPool.active, 0, "no icon left")
    local _, laneX, laneW = D.LaneGeometry(ui.width)
    for _, d in ipairs(TL.Marks()) do
        assertEqual(d.kind, "tick")
        assertEqual(d.tex.__texture, "Interface\\Buttons\\WHITE8x8")
        assertEqual(d.tex:GetWidth(), TL.MARK_W)
        assertEqual(d.tex:GetHeight(), D.LANE_H)
        assertTrue(rawget(d.hit, "__mouse"), "a hover frame")
        assertEqual(d.x, laneX + D.MarkX(d.cast.t, 60, 2 * laneW))
    end
    local shown
    local real = NS.ResultsTable.SideTip
    NS.ResultsTable.SideTip = function(_, _, lines) shown = lines end
    local tick = marksIn(NS, "a", BIG)[1]
    tick.hit:__fire("OnEnter")
    NS.ResultsTable.SideTip = real
    assertEqual(shown[2], "Cast at 0:01", "the tick's tooltip")
    assertTrue(NS.SetByPath("results.timelineMarks", "icon"))
    assertEqual(TL.Marks()[1].kind, "icon", "and back")
    assertEqual(TL.Zoom(), 2)
    -- A closed window draws nothing; the next open reads the mode.
    TL.Hide()
    assertTrue(NS.SetByPath("results.timelineMarks", "tick"))
    NS.Results.__ui().detail.w.timeline:__fire("OnClick")
    assertEqual(TL.Marks()[1].kind, "tick", "the open reads the stored mode")
end)

test("timeline marks: the two words on the By ability heading line switch the marks", function()
    local NS, ui = opened()
    local TL, D, Style = NS.ResultsTimeline, NS.ResultsTimelineData, NS.Style
    assertEqual(ui.marksIcons.label:GetText(), "Icons")
    assertEqual(ui.marksTicks.label:GetText(), "Ticks")
    -- At the lanes' right edge, on the By ability heading's line.
    local _, laneX, laneW = D.LaneGeometry(ui.width)
    local at = last(ui.marksTicks)
    assertEqual(at[1], "TOPRIGHT")
    assertEqual(at[4], laneX + laneW)
    assertEqual(at[5], -TL.Layout().lanesHead)
    local function gold(b)
        local r, g, bl = b.label:GetTextColor()
        return rgb({ r, g, bl }) == rgb(Style.GOLD)
    end
    assertTrue(gold(ui.marksIcons), "the mode shown is gold")
    assertFalse(gold(ui.marksTicks))
    ui.marksTicks:__fire("OnClick")
    assertEqual(NS.db.profile.results.timelineMarks, "tick", "written through the seam")
    assertEqual(TL.Marks()[1].kind, "tick")
    assertTrue(gold(ui.marksTicks))
    assertFalse(gold(ui.marksIcons))
    ui.marksIcons:__fire("OnClick")
    assertEqual(TL.Marks()[1].kind, "icon")
end)

-- ── the zoom and the grip ───────────────────────────────────────────────────────────────────────

test("timeline marks: zoomed in, the icons follow the zoomed axis; a drag of the grip moves them without re-pooling", function()
    local NS, ui, M = opened()
    local TL, D = NS.ResultsTimeline, NS.ResultsTimelineData
    TL.ZoomBy(1)
    local zoom = TL.Zoom()
    local _, laneX, laneW = D.LaneGeometry(ui.width)
    for _, d in ipairs(TL.Marks()) do assertEqual(d.x, laneX + D.MarkX(d.cast.t, 60, zoom * laneW)) end
    local frames = {}
    for k, d in ipairs(TL.Marks()) do frames[k] = d.frame end
    local churn = 0
    local release = NS.Pool.ReleaseAll
    rawset(NS.Pool, "ReleaseAll", function(pool, ...)
        churn = churn + 1
        return release(pool, ...)
    end)
    ui.frame.resizeGrip:__fire("OnMouseDown", "LeftButton")
    for k = 1, 5 do
        M.__now = M.__now + FRAME
        ui.frame:__fire("OnSizeChanged", 1000 + 20 * k, 560)
    end
    rawset(NS.Pool, "ReleaseAll", release)
    assertEqual(churn, 0, "nothing re-pooled while the grip is held")
    _, laneX, laneW = D.LaneGeometry(ui.width)
    assertEqual(ui.width, 1100, "the tracked size followed the drag")
    for k, d in ipairs(TL.Marks()) do
        assertTrue(d.frame == frames[k], "the same frame")
        assertEqual(d.x, laneX + D.MarkX(d.cast.t, 60, zoom * laneW))
        assertEqual(last(d.frame)[4], d.x - laneX + TL.CLIP_PAD)
    end
    ui.frame.resizeGrip:__fire("OnMouseUp")
end)
