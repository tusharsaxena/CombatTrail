-- tests/test_results_races.lua — races in the one history (Race mode plan Task D1, spec §7): the
-- Fights / Races / All filter and the race-only filters under Races (length, dummy kind, Hide flagged,
-- Include incomplete, Only best), the race groupings (length, target x length, spec x target x
-- length), a race row's race DPS, score, length chip and flag chip (ruling X11: no Status column),
-- an incomplete race compared but never leading, the race detail's Timing and Flags sections and its
-- figures, the late-cast right-click on a row, `/ct results races`, and (Review focus 3) saved races
-- listed as fights with their race DPS on WoW Forever and with Race mode off. Runs under both kit
-- profiles: every race control is Retail's and absent on WoW Forever, while the records are
-- account-wide.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

local DAY = 86400
local NOW = os.time()
local DUMMY = 31146          -- Raider's Training Dummy, a "boss" dummy on Retail; a plain NPC on Forever
local OTHER = 999001         -- no dummy on either client: a race on it reads its stored kind

local function forever() return T.NS.Compat.IsForever() end

local function fresh(mutate)
    local inst = T.load{ mutate = function(m)
        installPaint(m)
        m.__popups = {}
        m.StaticPopup_Show = function(name, _, _, data) m.__popups[#m.__popups + 1] = { name = name, data = data } end
        if mutate then mutate(m) end
    end }
    return inst.NS, inst.mocks
end

local n = 0
local function whoOf(NS, o)
    local me = NS.Identity.Who()
    local who = { name = me.name, realm = me.realm, client = me.client, class = me.class or "MAGE",
                  specID = o.specID or me.specID, specName = me.specName, ilvl = 640.5 }
    if o.mine == false then who.name, who.class = "Altchar", "WARLOCK" end
    return who
end

--- A plain dummy fight (no race part). `o`: id, dps, days, creatureID.
local function fightRec(NS, o)
    o = o or {}
    n = n + 1
    local ident = { content = "dummy", targetName = "Raider's Training Dummy", targetCreatureID = o.creatureID or DUMMY,
                    difficultyID = 0 }
    local dps = o.dps or 1000
    return {
        schema = 4, id = o.id or ("fight-" .. n), t = o.t or (NOW - (o.days or 0) * DAY - n), duration = 60,
        status = "final", who = whoOf(NS, o), identity = ident, boardKey = NS.Identity.BoardKey(ident),
        damage = { merged = dps * 60, player = dps * 60 }, dps = dps,
    }
end

--- A saved race: a dummy fight with its race part. `o`: id, length, status, score, endedAt, kind,
--- creatureID, flags, tail, combatEnd, days, t, specID, mine, casts.
local function raceRec(NS, o)
    o = o or {}
    local length = o.length or 60
    local score = o.score or 600000
    local r = fightRec(NS, { id = o.id, days = o.days, t = o.t, creatureID = o.creatureID, specID = o.specID,
                             mine = o.mine, dps = math.floor(score / (length + 4)) })
    r.duration = length + 4
    r.damage = { merged = score, player = score }
    r.race = { length = length, kind = o.kind or "boss", status = o.status or "complete", flags = o.flags or {},
               score = score, tail = o.tail or 1.5, endedAt = o.endedAt, combatEnd = o.combatEnd or 2.0, grace = 1.0,
               restartGap = 6 }
    r.casts = o.casts
    return r
end

local function save(NS, ...)
    for _, r in ipairs({ ... }) do assertTrue(NS.Recorder.Save(r), "saved " .. tostring(r.id)) end
end

local function ids(list)
    local out = {}
    for i, r in ipairs(list) do out[i] = r.id end
    table.sort(out)
    return table.concat(out, ",")
end

local function values(options)
    local out = {}
    for _, o in ipairs(options or {}) do out[#out + 1] = tostring(o.value) end
    return table.concat(out, ",")
end

local function view(extra)
    local v = { character = "all", days = 0 }
    for k, x in pairs(extra or {}) do v[k] = x end
    return v
end

local function open(NS)
    NS.Results.Show()
    local ui = NS.Results.__ui()
    assertTrue(ui ~= nil, "the window was built")
    return ui, ui.list
end

local function drawn(v)
    local out = {}
    for _, row in ipairs(v.list:Visible()) do
        if row.record then out[row.record.id] = row end
    end
    return out
end

local function strip(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- ── the Fights / Races / All filter ─────────────────────────────────────────────────────────────

test("results: Races shows only races, Fights only fights, All both", function()
    local NS = fresh()
    local F = NS.ResultsFights
    local race, plain = raceRec(NS, { id = "race" }), fightRec(NS, { id = "plain" })
    local all = { race, plain }
    assertEqual(NS.db.profile.results.view.kind, "all", "the shipped view lists both")
    assertEqual(ids(F.Filter(all, view(), NOW)), "plain,race")
    assertEqual(ids(F.Filter(all, view({ kind = "all" }), NOW)), "plain,race")
    if forever() then
        -- No Races filter on WoW Forever: a saved race passes as a fight, whatever a view holds.
        assertEqual(ids(F.Filter(all, view({ kind = "races" }), NOW)), "plain,race")
        assertEqual(ids(F.Filter(all, view({ kind = "fights" }), NOW)), "plain,race")
        return
    end
    assertEqual(ids(F.Filter(all, view({ kind = "races" }), NOW)), "race")
    assertEqual(ids(F.Filter(all, view({ kind = "fights" }), NOW)), "plain")
    local options = F.Options(all, view(), NOW)
    assertEqual(values(options.kind), "all,fights,races", "the filter's three choices")
end)

test("results: under Races the length, dummy kind, Hide flagged and Include incomplete filters apply", function()
    local NS = fresh()
    if forever() then return end
    local F = NS.ResultsFights
    local short = raceRec(NS, { id = "short", length = 30 })
    local long = raceRec(NS, { id = "long", length = 120 })
    local single = raceRec(NS, { id = "single", creatureID = OTHER, kind = "single" })
    local late = raceRec(NS, { id = "late", flags = { lateCasts = { { t = 2.5, spellID = 133 } } } })
    local inc = raceRec(NS, { id = "inc", status = "incomplete", endedAt = 20 })
    local plain = fightRec(NS, { id = "plain" })
    local all = { short, long, single, late, inc, plain }
    local races = view({ kind = "races" })
    assertEqual(ids(F.Filter(all, races, NOW)), "inc,late,long,short,single", "Include incomplete is on by default")
    assertEqual(ids(F.Filter(all, view({ kind = "races", length = 30 }), NOW)), "short")
    assertEqual(ids(F.Filter(all, view({ kind = "races", dummyKind = "single" }), NOW)), "single")
    assertEqual(ids(F.Filter(all, view({ kind = "races", hideFlagged = true }), NOW)), "inc,long,short,single",
        "Hide flagged leaves the late cast out; an incomplete race is Include incomplete's")
    assertEqual(ids(F.Filter(all, view({ kind = "races", includeIncomplete = false }), NOW)), "late,long,short,single")
    -- Outside Races the race filters stand aside: a view saved with them lists every fight.
    assertEqual(ids(F.Filter(all, view({ kind = "all", length = 30, hideFlagged = true }), NOW)),
        "inc,late,long,plain,short,single")
    local options = F.Options(all, races, NOW)
    assertEqual(values(options.length), "all,30,60,120", "the lengths present, shortest first")
    assertEqual(values(options.dummyKind), "all,single,boss", "the kinds present, in the catalog's order")
end)

test("results: only bests keeps each board's best", function()
    local NS = fresh()
    if forever() then return end
    local F = NS.ResultsFights
    local low = raceRec(NS, { id = "low", score = 300000 })
    local high = raceRec(NS, { id = "high", score = 900000 })
    local other = raceRec(NS, { id = "other", length = 30, score = 100000 })
    local inc = raceRec(NS, { id = "inc", status = "incomplete", endedAt = 10, score = 990000 })
    local plain = fightRec(NS, { id = "plain", dps = 99999 })
    save(NS, low, high, other, inc, plain)
    local all = NS.ResultsSource.All()
    assertEqual(ids(F.Filter(all, view({ kind = "races", onlyBest = true }), NOW)), "high,other",
        "one best per race board; an incomplete race never holds one")
end)

-- ── a race row ──────────────────────────────────────────────────────────────────────────────────

test("results: a race row shows its race DPS, length chip and flags", function()
    local NS = fresh()
    local late = raceRec(NS, { id = "late", score = 600000, flags = { lateCasts = { { t = 2.5, spellID = 133 } } } })
    local inc = raceRec(NS, { id = "inc", status = "incomplete", endedAt = 20, score = 200000, days = 0 })
    local plain = fightRec(NS, { id = "plain", dps = 777 })
    save(NS, late, inc, plain)
    local _, v = open(NS)
    v:SetFilter("character", "all")
    v:SetFilter("days", 0)
    local rows = drawn(v)
    local row = rows.late
    assertTrue(row ~= nil, "the race is listed")
    assertEqual(row.cells.dps.fs:GetText(), NS.Format.Number(10000), "the race DPS: score over the race length")
    assertEqual(row.cells.damage.fs:GetText(), NS.Format.Number(600000), "the score")
    assertEqual(rows.inc.cells.dps.fs:GetText(), NS.Format.Number(10000), "incomplete: over the time raced")
    assertEqual(rows.inc.cells.len.fs:GetText(), "0:20", "an incomplete race's length is its time raced")
    local cell = row.cells.target
    if forever() then
        assertFalse(cell.chip1:IsShown(), "no race chip on WoW Forever: the race lists as a fight")
        return
    end
    assertTrue(cell.chip1:IsShown(), "the length chip")
    assertEqual(cell.chip1.fs:GetText(), "1:00")
    assertTrue(cell.chip2:IsShown(), "the flag chip")
    assertEqual(cell.chip2.fs:GetText(), "Flagged")
    assertEqual(rows.inc.cells.target.chip2.fs:GetText(), "Incomplete")
    assertFalse(rows.plain.cells.target.chip1:IsShown(), "a plain fight has no chip")
    local chips = NS.ResultsRaces.Chips(late)
    assertEqual(chips[2].icon, "ph:flag")
    assertEqual(chips[1].color, NS.ResultsRaces.LengthColor(60))
    local died = raceRec(NS, { status = "incomplete", endedAt = 5, flags = { died = true } })
    assertEqual(NS.ResultsRaces.Chips(died)[2].text, "Died")
    assertEqual(NS.ResultsRaces.Chips(died)[2].icon, "ph:skull")
    local clean = raceRec(NS, {})
    assertEqual(#NS.ResultsRaces.Chips(clean), 1, "a clean complete race: the length chip alone")
end)

test("results: the race lengths take DPS Race's colors, and any other length a neutral gray", function()
    local NS = fresh()
    local R = NS.ResultsRaces
    assertEqual(R.LengthColor(30)[1], 0.86)
    assertEqual(R.LengthColor(300)[3], 0.92)
    assertEqual(R.LengthColor(45), R.LENGTH_NEUTRAL)
    assertEqual(R.LengthColor(nil), R.LENGTH_NEUTRAL)
end)

test("results: an incomplete race is compared but never leads its group", function()
    local NS = fresh()
    local F = NS.ResultsFights
    local done = raceRec(NS, { id = "done", score = 300000 })
    local inc = raceRec(NS, { id = "inc", status = "incomplete", endedAt = 10, score = 200000 })
    local first, second = F.Leaders({ done, inc })
    assertEqual(first, done, "the complete race leads though its DPS is lower")
    assertNil(second, "an incomplete race is no runner-up either")
    local ctx = F.Context({ done, inc })
    assertTrue(F.Delta(inc, ctx.top) > 0, "the incomplete race is still compared: " .. tostring(F.Delta(inc, ctx.top)))
end)

-- ── the race groupings ──────────────────────────────────────────────────────────────────────────

test("results: group by length, by target and length, and by spec, target and length", function()
    local NS = fresh()
    local F = NS.ResultsFights
    local order = table.concat(F.GroupOrder(), ",")
    if forever() then
        assertTrue(order:find("length", 1, true) == nil, "no race grouping on WoW Forever: " .. order)
        assertNil(F.GroupSpec("targetLength"))
        return
    end
    for _, mode in ipairs({ "length", "targetLength", "specTargetLength" }) do
        assertTrue(F.GroupSpec(mode) ~= nil, mode .. " is a grouping")
    end
    local a = raceRec(NS, { length = 120 })
    local b = raceRec(NS, { length = 30 })
    local c = raceRec(NS, { length = 30, creatureID = OTHER, kind = "single" })
    local plain = fightRec(NS, {})
    local len = F.GroupSpec("length")
    local ka, la, ra = len.of(a)
    local kb, _, rb = len.of(b)
    assertTrue(ka ~= kb, "one group per length")
    assertTrue(rb < ra, "shortest first")
    assertTrue(strip(la):find("2:00", 1, true) ~= nil, la)
    local kp, _, rp = len.of(plain)
    assertTrue(rp > ra, "a fight with no race length groups last: " .. tostring(kp))
    local tl = F.GroupSpec("targetLength")
    assertTrue(select(1, tl.of(b)) ~= select(1, tl.of(c)), "the kind sets the groups apart")
    assertTrue(select(3, tl.of(c)) < select(3, tl.of(b)), "single target before boss, the catalog's order")
    local stl = F.GroupSpec("specTargetLength")
    local other = raceRec(NS, { length = 30, specID = 64 })
    assertTrue(select(1, stl.of(b)) ~= select(1, stl.of(other)), "the spec sets the groups apart")
end)

test("results: under the date groupings a race is measured on its race board, not the dummy's fights", function()
    local NS = fresh()
    if forever() then return end
    local race = raceRec(NS, { id = "race", score = 60000 })
    local plain = fightRec(NS, { id = "plain", dps = 99999 })
    save(NS, race, plain)
    local _, v = open(NS)
    v:SetFilter("character", "all")
    v:SetFilter("days", 0)
    v:SetFilter("group", "date")
    local ctx = v:DeltaContext(NS.Recorder.Get("race"))
    assertTrue(ctx ~= nil, "the race has a context")
    assertEqual(ctx.first.id, "race", "the race leads its race board, the plain fight is apart")
end)

-- ── the race detail ─────────────────────────────────────────────────────────────────────────────

test("results: the race detail has Timing and Flags", function()
    local NS = fresh()
    local r = raceRec(NS, { id = "r", flags = { lateCasts = { { t = 2.5, spellID = 133 } }, sharedSession = true } })
    local plain = fightRec(NS, { id = "plain" })
    save(NS, r, plain)
    assertTrue(NS.Results.ShowFight("r"))
    local p = NS.Results.__ui().detail
    local x = p.race
    assertTrue(x ~= nil, "the race sections were built")
    if forever() then
        assertFalse(x.timingTitle:IsShown(), "no race section on WoW Forever")
        assertFalse(x.flagsTitle:IsShown())
        return
    end
    assertTrue(x.timingTitle:IsShown(), "Timing")
    assertEqual(x.timingTitle:GetText(), "Timing")
    assertTrue(x.flagsTitle:IsShown(), "Flags")
    assertTrue(x.box:IsShown(), "the flags box")
    local keys = {}
    for i, line in ipairs(x.lines) do keys[i] = line.key end
    assertEqual(table.concat(keys, ","), "lateCasts,sharedSession", "Scoring's order")
    assertTrue(x.lines[1].text:find("still counts", 1, true) ~= nil, x.lines[1].text)
    assertTrue(x.axisRace:GetText():find("1:00", 1, true) ~= nil, "the race axis names its length")
    assertTrue(p.heads.timing:IsShown() and p.heads.flags:IsShown(), "each heading has its arrow")
    -- A plain fight: no heading, arrow or box.
    assertTrue(NS.Results.ShowFight("plain"))
    assertFalse(x.timingTitle:IsShown())
    assertFalse(x.flagsTitle:IsShown())
    assertFalse(p.heads.timing:IsShown())
    assertFalse(p.heads.flags:IsShown())
    -- Timing folds.
    assertTrue(NS.Results.ShowFight("r"))
    p:ToggleSection("timing")
    assertTrue(NS.ResultsDetail.IsCollapsed("timing"))
    assertFalse(x.strip:IsShown(), "folded: the heading alone")
end)

test("results: the timing strip places the buzzer, grace, tail, late casts and combat end", function()
    local NS = fresh()
    local RD = NS.ResultsRaceDetail
    local r = raceRec(NS, { tail = 3, combatEnd = 4, flags = { lateCasts = { { t = 2, spellID = 133 } }, restartedAt = 7 } })
    local m = RD.Timing(r)
    assertEqual(m.length, 60)
    assertEqual(m.raceFill, 1)
    assertEqual(m.span, 12, "two 6 s steps at least")
    assertEqual(m.grace, 1 / 12)
    assertEqual(m.tail, 3 / 12)
    assertEqual(m.combatEnd, 4 / 12)
    assertEqual(m.restart, 7 / 12)
    assertEqual(m.late[1], 2 / 12)
    assertFalse(m.lateIgnored[1], "a counted late cast")
    local far = raceRec(NS, { combatEnd = 15 })
    assertEqual(RD.Timing(far).span, 18, "a mark past 12 s widens the axis in whole steps")
    local inc = raceRec(NS, { status = "incomplete", endedAt = 15 })
    local mi = RD.Timing(inc)
    assertEqual(mi.raceFill, 0.25, "an incomplete race fills to where combat ended")
    assertEqual(mi.endInRace, 0.25)
    assertNil(mi.grace, "nothing after a buzzer it never reached")
    assertNil(RD.Timing(fightRec(NS, {})), "a fight has no timing")
    local pos = RD.Place(m, 223)
    assertEqual(pos.raceW, 120, "the race segment 1.2 to the after-buzzer's 1")
    assertEqual(pos.postX, 123)
    assertEqual(pos.buzzer, 120)
end)

test("results: the detail's figures are the race's: score, race DPS, DPS · Incomplete", function()
    local NS = fresh()
    local inc = raceRec(NS, { id = "inc", status = "incomplete", endedAt = 20, score = 200000 })
    save(NS, inc)
    assertTrue(NS.Results.ShowFight("inc"))
    local w = NS.Results.__ui().detail.w
    assertEqual(w.damage.value:GetText(), NS.Format.Number(200000))
    assertEqual(w.dps.value:GetText(), NS.Format.Number(10000))
    assertEqual(w.dps.label:GetText(), "DPS \194\183 Incomplete")
    local lines = NS.ResultsDetail.Meta(inc)
    if not forever() then
        assertTrue(lines[2]:find("Boss", 1, true) ~= nil, "the dummy kind: " .. lines[2])
        assertTrue(lines[2]:find("0:20 / 1:00", 1, true) ~= nil, "the race's time: " .. lines[2])
    end
end)

test("results: the Delta box's runner-up reads its race DPS", function()
    local NS = fresh()
    local a = raceRec(NS, { id = "a", score = 1200000 })
    local b = raceRec(NS, { id = "b", length = 30, score = 300000 })
    local ctx = NS.ResultsFights.Context({ a, b })
    local label, text = NS.ResultsDetail.DeltaBox(a, ctx)
    assertEqual(label, "Leads by")
    assertEqual(text, NS.Format.SignedPct(100), "20000 against 10000 race DPS")
end)

test("results: the Compare and the DPS tip read the race DPS", function()
    local NS = fresh()
    local a = raceRec(NS, { id = "a", score = 1200000 })
    local b = raceRec(NS, { id = "b", score = 600000 })
    local kpis = NS.ResultsCompare.Kpis(a, b)
    assertEqual(kpis[2].key, "dps")
    assertEqual(kpis[2].a, 20000)
    assertEqual(kpis[2].b, 10000)
    local tip = NS.ResultsTips.Cell({ key = "dps" }, a)
    assertTrue(tip[2]:find("race length", 1, true) ~= nil, tostring(tip[2]))
end)

-- ── the late-cast right-click ───────────────────────────────────────────────────────────────────

local function menuOf(NS, record)
    local items
    local saved = NS.OpenMenu
    NS.OpenMenu = function(_, fill)
        items = {}
        local root = {}
        function root.CreateTitle(_, text) items[#items + 1] = { label = text, title = true } end
        function root.CreateButton(_, text, onClick)
            local item = { label = text, onClick = onClick, enabled = true, sub = {} }
            function item.SetEnabled(_, on) item.enabled = on and true or false end
            function item.CreateButton(_, t2, fn2)
                item.sub[#item.sub + 1] = { label = t2, onClick = fn2 }
                return { SetEnabled = function() end }
            end
            items[#items + 1] = item
            return item
        end
        fill(root)
    end
    NS.Results.RowMenu(record)
    NS.OpenMenu = saved
    return items
end

local function find(items, label)
    for _, item in ipairs(items) do
        if strip(item.label) == label then return item end
    end
    return nil
end

test("results: the row menu offers Ignore for late casts only for a race with a late cast", function()
    local NS = fresh()
    local late = raceRec(NS, { id = "late", flags = { lateCasts = { { t = 2.5, spellID = 133 } } } })
    local clean = raceRec(NS, { id = "clean" })
    save(NS, late, clean)
    local item = find(menuOf(NS, NS.Recorder.Get("late")), "Ignore for late casts")
    if forever() then
        assertNil(item, "no late-cast menu on WoW Forever")
        return
    end
    assertTrue(item ~= nil, "the submenu")
    assertEqual(#item.sub, 1, "one spell to ignore")
    assertNil(find(menuOf(NS, NS.Recorder.Get("clean")), "Ignore for late casts"), "nothing to offer")
    item.sub[1].onClick()
    assertTrue(NS.LateIgnore.Set()[133], "the spell is on the ignore list")
    assertFalse(NS.ResultsRaces.IsFlagged(NS.Recorder.Get("late")), "re-scored: no flag")
end)

test("results: an ignore-list edit re-scores Hide flagged in the list", function()
    local NS = fresh()
    if forever() then return end
    local late = raceRec(NS, { id = "late", flags = { lateCasts = { { t = 2.5, spellID = 133 } } } })
    save(NS, late)
    local _, v = open(NS)
    v:SetFilter("character", "all")
    v:SetFilter("days", 0)
    v:SetFilter("kind", "races")
    v:SetFilter("hideFlagged", true)
    assertEqual(v:Count(), 0, "the flagged race is hidden")
    NS.LateIgnore.Ignore(133)
    assertEqual(v:Count(), 1, "the list redrew: the race is clean now")
end)

-- ── the slash verb ──────────────────────────────────────────────────────────────────────────────

test("results: /ct results races opens the list on the Races filter", function()
    local NS, M = fresh()
    NS.Results.OnVerb("races")
    if forever() then
        assertFalse(NS.Results.IsShown(), "no races verb on WoW Forever")
        local said = table.concat(M.__printed(), "\n")
        assertTrue(said:find("Usage: /ct results", 1, true) ~= nil, said)
        assertTrue(said:find("races", 1, true) == nil, "the usage line names no races word: " .. said)
        return
    end
    assertTrue(NS.Results.IsShown())
    assertEqual(NS.Results.__ui().list.filters.kind, "races")
end)

-- ── Review focus 3 ──────────────────────────────────────────────────────────────────────────────

test("results: saved races list on WoW Forever with no race control", function()
    local NS = fresh()
    local race = raceRec(NS, { id = "race", score = 600000 })
    save(NS, race)
    local ui, v = open(NS)
    v:SetFilter("character", "all")
    v:SetFilter("days", 0)
    assertEqual(v:Count(), 1, "the race lists")
    assertEqual(drawn(v).race.cells.dps.fs:GetText(), NS.Format.Number(10000), "with its race DPS")
    local present = not forever()
    assertEqual(v.raceBar ~= nil and v.raceBar.kind ~= nil, present, "the Fights / Races / All control")
    assertEqual(v.raceBar ~= nil and v.raceBar.onlyBest ~= nil, present, "Only best")
    local modes = table.concat(NS.ResultsFights.GroupOrder(), ",")
    assertEqual(modes:find("targetLength", 1, true) ~= nil, present, "the race groupings: " .. modes)
    assertTrue(ui ~= nil)
end)

test("results: Race mode off still lists saved races", function()
    local NS = fresh()
    if not forever() then assertTrue(NS.SetByPath("race.enabled", false)) end
    local race = raceRec(NS, { id = "race" })
    save(NS, race)
    local _, v = open(NS)
    v:SetFilter("character", "all")
    v:SetFilter("days", 0)
    assertEqual(v:Count(), 1)
    if forever() then return end
    v:SetFilter("kind", "races")
    assertEqual(v:Count(), 1, "the Races filter reads the record, never the switch")
    assertTrue(v.raceBar.kind ~= nil, "the filter is there with Race mode off")
end)

-- ── the bar ─────────────────────────────────────────────────────────────────────────────────────

test("results: the Races bar fits the window's least width", function()
    local NS = fresh()
    local F = NS.ResultsFights
    local w = F.BarMinWidth()
    local plan = F.BarPlan(w, { kind = "races" })
    local saveLeft = plan.buttons.save - 60
    local last = 0
    for _, item in ipairs(plan.row2) do last = math.max(last, item.x + item.w) end
    assertTrue(last <= saveLeft, ("the second row ends at %d, Save starts at %d"):format(last, saveLeft))
    if forever() then
        assertEqual(#plan.row2, 1, "Bosses only alone on WoW Forever")
        return
    end
    local keys = {}
    for i, item in ipairs(plan.row2) do keys[i] = item.key end
    assertEqual(table.concat(keys, ","), "kind,length,dummyKind,hideFlagged,includeIncomplete,onlyBest")
    local fights = F.BarPlan(w, { kind = "all" })
    keys = {}
    for i, item in ipairs(fights.row2) do keys[i] = item.key end
    assertEqual(table.concat(keys, ","), "kind,bossesOnly", "outside Races: the kind and Bosses only")
    assertTrue(NS.Results.MIN_WIDTH >= w, "the window still fits the bar")
end)

test("results: switching to Races shows the race filters and hides Bosses only", function()
    local NS = fresh()
    if forever() then return end
    local _, v = open(NS)
    assertTrue(v.bossesOnly:IsShown(), "Bosses only under All")
    assertFalse(v.raceBar.onlyBest:IsShown(), "no Only best under All")
    rawset(v.raceBar.includeIncomplete, "SetChecked", function(self, on) self.__checked = on end)
    v:SetFilter("kind", "races")
    assertFalse(v.bossesOnly:IsShown(), "Bosses only stands aside under Races")
    assertTrue(v.raceBar.onlyBest:IsShown())
    assertTrue(v.raceBar.hideFlagged:IsShown())
    assertEqual(v.filters.includeIncomplete, true, "Include incomplete on by default")
    assertTrue(v.raceBar.includeIncomplete.__checked == true, "and its box says so")
    v:SetFilter("bossesOnly", true)
    local race = raceRec(NS, { id = "race" })
    save(NS, race)
    v:SetFilter("character", "all")
    v:SetFilter("days", 0)
    assertEqual(v:Count(), 1, "a saved Bosses only never empties the Races list")
end)

-- ── review fixes ────────────────────────────────────────────────────────────────────────────────

test("results: a race row's chips and target text follow a column drag", function()
    local NS = fresh()
    if forever() then return end
    local late = raceRec(NS, { id = "late", flags = { lateCasts = { { t = 2.5, spellID = 133 } } } })
    save(NS, late)
    local _, v = open(NS)
    v:SetFilter("character", "all")
    v:SetFilter("days", 0)
    local function placed()
        local cell = drawn(v).late.cells.target
        local _, _, _, textX = cell.fs:GetPoint(1)
        return cell.x, textX
    end
    local x1, textX = placed()
    local lead = textX - x1
    assertTrue(lead > 0, "the text after the chips: " .. tostring(lead))
    v.list:DragColumn("character", NS.ResultsFights.CHARACTER_MIN)
    v.list:EndColumnDrag("character")
    local x2, textX2 = placed()
    assertTrue(x2 ~= x1, "the drag moved the target column: " .. tostring(x2))
    assertEqual(textX2 - x2, lead, "the text still after the chips")
end)

test("results: an incomplete race's Delta is shown muted, compared but never the best", function()
    local NS = fresh()
    local F = NS.ResultsFights
    local C = NS.ResultsTable.COLORS
    local done = raceRec(NS, { id = "done", score = 300000 })
    local low = raceRec(NS, { id = "low", score = 150000 })
    local inc = raceRec(NS, { id = "inc", status = "incomplete", endedAt = 10, score = 200000 })
    local ctx = F.Context({ done, low, inc })
    local _, color = F.DeltaText(inc, ctx)
    assertEqual(color, C.dim, "muted, though its DPS is above the best's")
    local _, lowColor = F.DeltaText(low, ctx)
    assertEqual(lowColor, C.red, "a complete race below the best keeps its red")
    local _, _, boxColor = NS.ResultsDetail.DeltaBox(inc, ctx)
    assertEqual(boxColor, C.dim, "the detail's Delta box says the same")
    local tip = table.concat((function()
        local out = {}
        for i, line in ipairs(F.DeltaTip(inc, ctx, true)) do out[i] = type(line) == "table" and line[1] or line end
        return out
    end)(), "\n")
    assertTrue(tip:find("never sets the best", 1, true) ~= nil, tip)
end)

test("results: the sample history's clean board drops on an ignore-list edit", function()
    local NS = fresh()
    if forever() then return end      -- the late-cast ignore list is Race mode's, Retail only
    local S = NS.ResultsSource
    local fast = raceRec(NS, { id = "fast", score = 900000, flags = { lateCasts = { { t = 2.5, spellID = 133 } } } })
    local slow = raceRec(NS, { id = "slow", score = 300000 })
    assertTrue(S.Use({ fights = { fast, slow } }))
    assertEqual(S.CleanFor(slow), slow, "the late cast keeps the faster race off the clean board")
    NS.LateIgnore.Ignore(133)
    assertEqual(S.CleanFor(slow), fast, "the edit dropped the sample's clean board")
    S.Use(nil)
end)
