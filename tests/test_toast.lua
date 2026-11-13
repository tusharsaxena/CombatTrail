-- tests/test_toast.lua — the new-best toast (Race mode plan Task C2, modules/BestToast.lua on
-- LibKa0s-Toast-1.0 through core/ToastSetup.lua), ported from DPS Race @f8078c7 (its tests/test_toast.lua
-- and the toast-stub part of test_surface_parity.lua) and keyed on races (`toast.races`, Retail) and
-- fights (`toast.fights`, both clients): one toast per complete race or stored fight that beats an
-- earlier best on its board, whether or not a window is shown; none for an incomplete or lost race, a
-- record that is no best, a board's first, or with its toggle off; a race toasts once, on its result,
-- never again as a fight. Its words, its sound, *Test toast*, the stored place, the stand-down, the
-- History tab's rows per client, and the degraded stub.
--
-- Most cases store records of the shape the Recorder writes and send the race's RACE_RESULT as the race
-- engine does; one runs two real races through the fight pipeline (tests/race_fixture.lua).

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil
local F = dofile(T.root .. "/tests/race_fixture.lua")(T)
local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local function forever() return T.NS.Compat.IsForever() end

local function fresh(mutate)
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        if mutate then mutate(m) end
    end }
    return inst.NS, inst.mocks
end

--- `NS` with a fight's new best toasting: off by default (a race's is on), so a case about a fight
--- toast turns it on.
local function fightsOn(NS)
    assertTrue(NS.SetByPath("toast.fights", true))
    return NS
end

local n = 0
--- A stored-shape record: a fight on the boar's board, or with `o.race` a race on the boss dummy's
--- 60 s board (its race part: status, length, flags).
local function rec(NS, o)
    o = o or {}
    n = n + 1
    local r = {
        schema = 4, id = o.id or ("rec-" .. n), t = o.t or (1000 + n), duration = o.duration or 60, status = "final",
        who = { name = "Lanfear", realm = "Area 52", client = NS.Compat.ClientKey(), class = "WARLOCK",
                specID = 267, specName = "Destruction" },
        identity = { content = "world", targetName = "Angry Boar" }, boardKey = "c:1985:0",
        dps = o.dps or 1000, damage = { merged = (o.dps or 1000) * 60 },
    }
    if o.race then
        local length = o.length or 60
        r.identity = { content = "dummy", targetName = "Raider's Training Dummy", targetCreatureID = 31146 }
        r.boardKey = "c:31146:0"
        r.race = { length = length, kind = "boss", status = o.status or "complete", grace = 1, restartGap = 6,
                   score = (o.dps or 1000) * length, dps = o.dps or 1000,
                   flags = o.flags or { lateCasts = {}, reloaded = false, died = false } }
        if r.race.status == "incomplete" then r.race.endedAt = 20 end
    end
    return r
end

--- Store `r` (FIGHT_SAVED, as the Recorder sends it) and, for a race, send its RACE_RESULT.
local function save(NS, r)
    assertTrue(NS.Recorder.Save(r), "saved " .. tostring(r.id))
    if r.race then NS.SendBus(NS.MSG.RACE_RESULT, r, r.race) end
    return r
end

local function T_(NS) return NS.BestToast.Instance() end

local function shownKey(NS)
    local _, key = T_(NS):Current()
    return key
end

local function payload(NS)
    return (T_(NS):Current())
end

-- ── the races (Retail) ─────────────────────────────────────────────────────────────────────────

test("toast: a complete race that beats its board's best toasts once, whatever the windows show", function()
    if forever() then return end
    local NS = fresh()
    NS.Hud.Hide()
    save(NS, rec(NS, { race = true, id = "old", dps = 100000 }))
    assertNil(shownKey(NS), "a board's first race has nothing to beat")
    save(NS, rec(NS, { race = true, id = "new", dps = 110000 }))
    assertEqual(shownKey(NS), "new", "the new best's toast is on screen under its record id")
    local frame = T_(NS):Frame()
    assertTrue(frame:IsShown())
    assertEqual(frame:GetFrameStrata(), "HIGH", "frame-layering's T5 alert tier")
    assertEqual(T_(NS):Stats().waiting, 0, "one toast for the race: never again as a fight")
    save(NS, rec(NS, { race = true, id = "again", dps = 120000 }))
    assertEqual(shownKey(NS), "new", "one at a time")
    assertEqual(T_(NS):Stats().waiting, 1, "the next new best waits its turn")
end)

test("toast: none for an incomplete or lost race, a race that is no best, or with races off", function()
    if forever() then return end
    local NS = fresh()
    save(NS, rec(NS, { race = true, dps = 100000 }))
    save(NS, rec(NS, { race = true, dps = 90000 }))
    assertNil(shownKey(NS), "not a best")
    save(NS, rec(NS, { race = true, dps = 200000, status = "incomplete" }))
    assertNil(shownKey(NS), "an incomplete race never toasts")
    NS.SendBus(NS.MSG.RACE_RESULT, nil, { status = "lost", length = 60 })
    assertNil(shownKey(NS), "a lost race never toasts")
    assertTrue(NS.SetByPath("toast.races", false))
    save(NS, rec(NS, { race = true, dps = 300000 }))
    assertNil(shownKey(NS), "toast.races off")
    assertTrue(NS.SetByPath("toast.races", true))
    save(NS, rec(NS, { race = true, dps = 400000 }))
    assertTrue(shownKey(NS) ~= nil, "back on, the next new best toasts")
end)

test("toast: a race's payload names the spec and class, its dummy kind and length, the DPS and the gain", function()
    if forever() then return end
    local NS = fresh()
    local old = save(NS, rec(NS, { race = true, dps = 100000 }))
    local new = save(NS, rec(NS, { race = true, dps = 104200 }))
    local p = payload(NS)
    assertEqual(p.recordID, new.id)
    assertTrue(p.title:find("New best:", 1, true) ~= nil, p.title)
    assertTrue(p.who:find("Destruction", 1, true) ~= nil, p.who)
    assertEqual(p.class, "WARLOCK")
    assertEqual(p.chips[1][1], NS.Dummies.Label("boss"))
    assertEqual(p.chips[2][1], "1:00")
    local want = ("%s DPS, +%s better than previous best (%s)"):format(NS.Format.Number(104200),
        NS.Format.Pct(4.2), NS.Format.Number(old.dps))
    assertEqual(p.detail, want)
    assertEqual(p.detailColor, NS.ResultsTable.COLORS.green)
    assertNil(p.flags, "a clean race has no flags line")
end)

test("toast: a flagged race may toast, its flags on the last line as the Race window words them", function()
    if forever() then return end
    local NS = fresh()
    save(NS, rec(NS, { race = true, dps = 100000 }))
    local flagged = rec(NS, { race = true, dps = 120000,
        flags = { lateCasts = { { t = 1.4, spellID = 29722 } }, restartedAt = 7.5, reloaded = false, died = false } })
    save(NS, flagged)
    local p = payload(NS)
    assertTrue(p.flags ~= nil, "a flags line")
    local words = {}
    for i, chip in ipairs(NS.RaceWindowStates.FlagChips(flagged.race)) do words[i] = chip.text end
    assertEqual(p.flags, table.concat(words, " \194\183 "))
    -- A late cast the ignore list holds flags nothing: no line.
    local ignored = rec(NS, { race = true, dps = 130000,
        flags = { lateCasts = { { t = 1.4, spellID = 1856 } }, reloaded = false, died = false } })
    assertNil(NS.BestToast.Payload(ignored, 1, flagged).flags, "every late cast ignored: no flags line")
end)

-- ── the fights (both clients) ──────────────────────────────────────────────────────────────────

test("toast: a new fight best raises the toast; a board's first fight does not", function()
    local NS = fightsOn(fresh())
    save(NS, rec(NS, { id = "first", dps = 1000 }))
    assertNil(shownKey(NS), "a board's first fight has nothing to beat")
    save(NS, rec(NS, { id = "slower", dps = 900 }))
    assertNil(shownKey(NS), "not a best")
    save(NS, rec(NS, { id = "best", dps = 1100 }))
    assertEqual(shownKey(NS), "best")
    local p = payload(NS)
    assertEqual(p.chips[1][1], "Angry Boar", "what the fight was against")
    assertEqual(p.chips[2][1], "1:00", "the fight's length")
    assertEqual(p.detail, ("%s DPS, +%s better than previous best (%s)"):format(NS.Format.Number(1100),
        NS.Format.Pct(10), NS.Format.Number(1000)))
    assertNil(p.flags, "a fight has no flags")
end)

test("toast: each toggle silences its kind", function()
    local NS = fresh()
    assertTrue(NS.SetByPath("toast.fights", false))
    save(NS, rec(NS, { dps = 1000 }))
    save(NS, rec(NS, { dps = 2000 }))
    assertNil(shownKey(NS), "fights off: no fight toasts")
    if forever() then
        assertNil(NS.db.profile.toast.races, "no races key on WoW Forever")
        return
    end
    save(NS, rec(NS, { race = true, dps = 1000 }))
    save(NS, rec(NS, { race = true, dps = 2000 }))
    assertTrue(shownKey(NS) ~= nil, "fights off leaves races on")
    T_(NS):Clear()
    assertTrue(NS.SetByPath("toast.fights", true))
    assertTrue(NS.SetByPath("toast.races", false))
    save(NS, rec(NS, { race = true, dps = 3000 }))
    assertNil(shownKey(NS), "races off: no race toasts")
    save(NS, rec(NS, { dps = 3000 }))
    assertTrue(shownKey(NS) ~= nil, "races off leaves fights on")
end)

test("toast: a kind switched off drops its own toasts, waiting or shown, and keeps the other kind's", function()
    if forever() then return end
    local NS = fightsOn(fresh())
    save(NS, rec(NS, { dps = 1000 }))
    save(NS, rec(NS, { id = "fight-best", dps = 2000 }))
    save(NS, rec(NS, { race = true, dps = 1000 }))
    save(NS, rec(NS, { race = true, id = "race-best", dps = 2000 }))
    assertEqual(shownKey(NS), "fight-best")
    assertEqual(T_(NS):Stats().waiting, 1, "the race's toast waits behind the fight's")
    assertTrue(NS.SetByPath("toast.fights", false))
    assertEqual(shownKey(NS), "race-best", "the fight's toast went; the race's is up")
    assertEqual(T_(NS):Stats().waiting, 0)
    save(NS, rec(NS, { dps = 3000 }))
    save(NS, rec(NS, { race = true, id = "race-again", dps = 3000 }))
    assertEqual(T_(NS):Stats().waiting, 1, "a race's toast waits; the fight's never queued")
    assertTrue(NS.SetByPath("toast.races", false))
    assertNil(shownKey(NS), "races off: every race toast went")
    assertEqual(T_(NS):Stats().waiting, 0)
end)

test("toast: with no previous best to name, the DPS line is the DPS alone in the text color", function()
    local NS = fresh()
    local p = NS.BestToast.Payload(rec(NS, { dps = 104200 }), nil, nil)
    assertEqual(p.detail, NS.Format.Number(104200) .. " DPS")
    assertEqual(p.detailColor, NS.ResultsTable.COLORS.text)
end)

-- ── the whole race ─────────────────────────────────────────────────────────────────────────────

test("toast: two real races, the second faster, toast once on its result", function()
    if forever() then return end
    -- The epoch follows the race clock, so the second race is fought after the first.
    local S = F.fresh({ mutate = function(m)
        installPaint(m)
        m.time = function() return 1800000000 + math.floor(m.__now or 0) end
    end })
    local NS = S.NS
    assert(NS.SetByPath("race.autoShow", false))
    -- Every toast shown, by key (the headless timer queue fires the toast's own countdown at once,
    -- so what is on screen after the settle is not the question).
    local shows, inst = {}, T_(NS)
    local show = inst.Show
    inst.Show = function(self, p, opts)
        shows[#shows + 1] = opts and opts.key
        return show(self, p, opts)
    end
    F.whole(S, 30)
    assertEqual(NS.Race.State(), "result")
    assertEqual(#shows, 0, "the board's first race")
    assertTrue(NS.Race.Cancel(), "the result card dismissed")
    local faster = { damage = F.SESSION.damage * 2, dps = F.SESSION.dps * 2, duration = 39, spells = F.SESSION.spells }
    assertTrue(F.arm(S, 30, 200))
    local start = F.pull(S, 201, 26, faster)
    F.damage(S, 26, start + 1, start + 30, 1)
    F.settle(S, start + 31)
    assertEqual(NS.Race.State(), "result")
    local record = F.last(S, "RACE_RESULT")[2]
    assertTrue(record.race.dps > F.records(S)[2].race.dps, "the second race is the faster")
    assertEqual(table.concat(shows, ","), record.id, "one toast, the new best's: its FIGHT_SAVED is not a fight's")
end)

-- ── the sound ──────────────────────────────────────────────────────────────────────────────────

test("toast sound: Default plays the shell's alert; another key its file; an unknown key falls back", function()
    local inst = T.load()
    local NS = inst.NS
    assertEqual(NS.db.profile.toast.soundKey, "Default")
    assertNil(NS.BestToast.SoundFile(), "Default: no file, the shell's alert")
    inst.mocks.LibStub("LibSharedMedia-3.0"):Register("sound", "Bell", "Sound\\bell.ogg")
    assertTrue(NS.SetByPath("toast.soundKey", "Bell"))
    assertEqual(NS.BestToast.SoundFile(), "Sound\\bell.ogg", "resolved as the toast shows")
    assertTrue(NS.SetByPath("toast.soundKey", "Gone"))
    assertNil(NS.BestToast.SoundFile(), "a key LibSharedMedia does not know: Default")
end)

test("toast sound: the list leads with Default, then every LibSharedMedia sound in order", function()
    local inst = T.load()
    local media = inst.mocks.LibStub("LibSharedMedia-3.0")
    media:Register("sound", "zap", "Sound\\zap.ogg")
    media:Register("sound", "Bell", "Sound\\bell.ogg")
    local list = inst.NS.BestToast.SoundValues()
    assertEqual(list[1].value, "Default")
    local rest = {}
    for i = 2, #list do rest[#rest + 1] = list[i].value end
    local seen = table.concat(rest, ",")
    assertTrue(seen:find("Bell", 1, true) and seen:find("zap", 1, true)
        and seen:find("Bell", 1, true) < seen:find("zap", 1, true), seen)
end)

-- ── Test toast, the place, the stand-down ──────────────────────────────────────────────────────

test("toast: Test toast queues a sample, and a second click replaces it", function()
    local NS = fresh()
    assertTrue(NS.BestToast.Test())
    assertEqual(shownKey(NS), NS.BestToast.SAMPLE)
    assertTrue(payload(NS).detail:find("better than previous best", 1, true) ~= nil)
    assertTrue(NS.BestToast.Test())
    assertEqual(T_(NS):Stats().waiting, 0, "the second sample replaced the first")
end)

test("toast: Reset position (Master controls) clears the stored place", function()
    local NS = fresh()
    NS.db.profile.toast.point = { "TOP", "TOP", 10, -200 }
    NS.ResetPositions()
    assertNil(NS.db.profile.toast.point)
end)

test("toast: the stand-down takes the toast down and drops what waits; a best while down shows none", function()
    local NS = fightsOn(fresh())
    save(NS, rec(NS, { dps = 1000 }))
    save(NS, rec(NS, { dps = 2000 }))
    save(NS, rec(NS, { dps = 3000 }))
    assertTrue(shownKey(NS) ~= nil)
    assertTrue(NS.SetByPath("general.enabled", false))
    assertNil(shownKey(NS))
    assertEqual(T_(NS):Stats().waiting, 0)
    save(NS, rec(NS, { dps = 4000 }))
    assertNil(shownKey(NS), "nothing while stood down")
end)

-- ── the layout ─────────────────────────────────────────────────────────────────────────────────

test("toast: DPS Race's size: 25% larger, the trophy as tall as the three rows", function()
    local NS = fightsOn(fresh())
    local B = NS.BestToast
    assertEqual(B.SCALE, 1.25)
    assertEqual(B.ROWS_H, B.TITLE_H + B.ROW_GAP + B.CHIP_H + B.ROW_GAP + B.TEXT_H)
    assertEqual(B.HEIGHT, 90)
    assertEqual(B.WIDTH, B.PAD + B.ROWS_H + B.GAP + 355 + B.PAD)
    save(NS, rec(NS, { dps = 1000 }))
    save(NS, rec(NS, { dps = 2000 }))
    local w = T_(NS):Frame().combatTrail
    assertTrue(w ~= nil, "the rows are built on the shell's frame")
    assertEqual(w.title:GetText(), payload(NS).title)
    assertTrue(w.chips[1].label:GetText() == "Angry Boar")
    assertFalse(w.flags:IsShown(), "no flags line for a fight")
end)

test("toast: a real toast never moves; as Test toast's sample it drags", function()
    local NS = fightsOn(fresh())
    save(NS, rec(NS, { dps = 1000 }))
    save(NS, rec(NS, { dps = 2000 }))
    local frame = T_(NS):Frame()
    local moved = 0
    rawset(frame, "StartMoving", function() moved = moved + 1 end)
    rawset(frame, "StopMovingOrSizing", function() end)
    frame:__fire("OnDragStart", "LeftButton")
    assertEqual(moved, 0, "a real toast stays where it is")
    T_(NS):Dismiss()
    assertTrue(NS.BestToast.Test())
    assertTrue(T_(NS):Frame() == frame, "the shell's one frame")
    frame:__fire("OnDragStart", "LeftButton")
    assertEqual(moved, 1, "the sample drags")
end)

test("toast: the class and spec icons sit between New best: and the words", function()
    local NS = fresh(function(m) m.CLASS_ICON_TCOORDS = { WARLOCK = { 0.75, 1, 0.25, 0.5 } } end)
    local r = rec(NS, { dps = 2000 })
    r.who.specIcon = 136186
    local p = NS.BestToast.Payload(r, 10, rec(NS, { dps = 1000 }))
    T_(NS):Show(p, { key = "x" })
    local w = T_(NS):Frame().combatTrail
    assertTrue(w.class:IsShown(), "the class icon")
    assertTrue(w.spec:IsShown(), "the spec icon")
    local function at(region) return region.__points[1] end
    assertTrue(at(w.class)[2] == w.title and at(w.class)[3] == "RIGHT", "the class icon after New best:")
    assertTrue(at(w.spec)[2] == w.class and at(w.spec)[3] == "RIGHT", "the spec icon after the class icon")
    assertTrue(at(w.who)[2] == w.spec and at(w.who)[3] == "RIGHT", "the words after the icons")
end)

test("toast: a class or spec the client cannot draw takes no room", function()
    local NS = fresh(function(m) m.CLASS_ICON_TCOORDS = {} end)
    local p = NS.BestToast.Payload(rec(NS, { dps = 1 }), nil, nil)
    p.specIcon = nil
    T_(NS):Show(p, { key = "x" })
    local w = T_(NS):Frame().combatTrail
    assertFalse(w.class:IsShown(), "no coordinates for that class")
    assertFalse(w.spec:IsShown(), "no spec icon")
    local at = w.who.__points[1]
    assertTrue(at[2] == w.title and at[3] == "RIGHT" and at[4] == 4, "the words one gap after New best:")
    T_(NS):Clear()
    p = NS.BestToast.Payload(rec(NS, { dps = 1 }), nil, nil)
    p.specIcon = 136186
    T_(NS):Show(p, { key = "y" })
    at = w.spec.__points[1]
    assertTrue(w.spec:IsShown() and at[2] == w.title and at[3] == "RIGHT" and at[4] == 4,
        "a spec icon without a class icon sits one gap after New best:")
    assertTrue(w.who.__points[1][2] == w.spec, "the words after the spec icon")
end)

test("toast: the rows' text draws larger than the same font unscaled, each row at its font's size", function()
    local NS = fightsOn(fresh())
    save(NS, rec(NS, { dps = 1000 }))
    save(NS, rec(NS, { dps = 2000 }))
    local frame = T_(NS):Frame()
    local w = frame.combatTrail
    local function size(fs) local _, s = fs:GetFont() return s end
    local S = NS.Style
    -- The same fonts unscaled, on the same frame under the same skin.
    local title, text = size(S.Text(frame, S.FONT.TITLE)), size(S.Text(frame, S.FONT.TEXT))
    assertTrue(size(w.title) > title, "the headline: " .. tostring(size(w.title)) .. " vs " .. tostring(title))
    assertEqual(size(w.who), size(w.title), "the spec and class at the headline's size")
    assertTrue(size(w.detail) > text, "the DPS line: " .. tostring(size(w.detail)) .. " vs " .. tostring(text))
    assertEqual(size(w.chips[1].label), size(w.detail), "a chip's word at the DPS line's size")
    if not forever() then
        assertEqual(size(w.title), S.FONT_SIZE[S.FONT.TITLE] * 1.25, "Retail: 1.25 times the headline's font")
        assertEqual(size(w.detail), S.FONT_SIZE[S.FONT.TEXT] * 1.25, "Retail: 1.25 times the text font")
    end
end)

-- ── the settings ───────────────────────────────────────────────────────────────────────────────

test("toast: the History page's New-best toast tab, the races row on Retail only", function()
    local NS = fresh()
    local paths = {}
    for _, row in ipairs(NS.Schema) do
        if row.page == "history" and row.group == NS.HISTORY_TABS.toast then paths[#paths + 1] = row.path end
    end
    local want = "toast.fights,toast.sound,toast.soundKey,toast.duration,toast.scale"
    if not forever() then want = "toast.races," .. want end
    assertEqual(table.concat(paths, ","), want)
    assertEqual(NS.db.profile.toast.fights, false, "a fight's new best is off by default")
    if forever() then assertNil(NS.defaults.profile.toast.races) else assertEqual(NS.defaults.profile.toast.races, true) end
end)

-- ── the seam ───────────────────────────────────────────────────────────────────────────────────

test("toast: the stub answers every member a live toast has, as an empty toast does", function()
    local NS = T.NS
    local live = NS.BestToast.Instance()
    local stub = NS.ToastStub
    for name, fn in pairs(getmetatable(live) and getmetatable(live).__index or live) do
        if type(fn) == "function" and name:match("^%u") then
            assertTrue(type(stub[name]) == "function", "the stub lacks " .. name)
        end
    end
    assertFalse(stub.Show())
    assertNil(stub.Current())
    assertEqual(stub.Stats().waiting, 0)
end)
