-- tests/test_share.lua — Share (plan Task 4.2, spec §7, mockup §9): the one-line chat summary of a
-- stored fight, at most one chat message long, the talents link after it when the setting is on,
-- the channel menu, the refusal in combat, and the row menu's Share now live. Race mode (race plan
-- Task C2, DPS Race @f8078c7's test_share.lua race cases): a race's line in the same shape, and the
-- race's own lines printed on the arm and at its result.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local SEP = " \194\183 "

-- A fresh instance whose chat sender records what it was handed.
local function fresh(mutate)
    local inst = T.load{ mutate = function(m)
        m.__sent = {}
        m.C_ChatInfo = m.C_ChatInfo or {}
        m.C_ChatInfo.SendChatMessage = function(text, channel, _, target)
            m.__sent[#m.__sent + 1] = { text = text, channel = channel, target = target }
        end
        m.__popups = {}
        m.StaticPopup_Show = function(name, _, _, data) m.__popups[#m.__popups + 1] = { name = name, data = data } end
        if mutate then mutate(m) end
    end }
    return inst.NS, inst.mocks
end

local function rec(NS, o)
    o = o or {}
    local ident = { content = "raid", targetName = o.target or "Vorasius", encounterID = 3176,
                    encounterName = o.target or "Vorasius", difficultyID = o.difficultyID or 15,
                    difficultyName = "Heroic", keystoneLevel = o.keystone, isBoss = true }
    local merged = 186900 * 252
    return {
        schema = 1, id = o.id or "s1", t = os.time(), duration = 252, status = "final",
        who = { name = "Ka0shunter", realm = "Silvermoon", class = "HUNTER", specID = 253,
                specName = o.specName or "Beast Mastery", ilvl = 721.4 },
        identity = ident, boardKey = NS.Identity.BoardKey(ident),
        damage = { merged = merged, player = merged }, dps = 186900,
        spells = NS.CastCodec.EncodeSpells(o.spells or {
            { spellID = 34026, total = math.floor(merged * 0.254), isPet = false },
            { spellID = 217200, total = math.floor(merged * 0.171), isPet = false },
            { spellID = 193455, total = math.floor(merged * 0.10), isPet = false } }),
    }
end

test("share: line format and length <= 255", function()
    local NS = fresh()
    local r = rec(NS)
    local line = NS.Share.Line(r, false)
    local want = table.concat({ "Combat Trail", "Vorasius HC", "4:12", NS.Format.Number(186900) .. " DPS",
        "Beast Mastery 721.4", "top: Spell 34026 25.4%, Spell 217200 17.1%" }, SEP)
    assertEqual(line, want)
    assertTrue(#line <= NS.Share.MAX_CHAT)
    -- A keystone names its level; the difficulty's short name otherwise.
    assertEqual(NS.Share.Against(rec(NS, { keystone = 12, difficultyID = 8 })), "Vorasius M+ 12")
    -- A name that would run past one chat message drops the top spells, then is cut.
    local long = rec(NS, { target = ("Very Long Name "):rep(30) })
    local cut = NS.Share.Line(long, false)
    assertTrue(#cut <= NS.Share.MAX_CHAT, "cut to one message: " .. #cut)
    assertTrue(cut:find("top:", 1, true) == nil, "the top spells went first")
    -- A chat escape never reaches the channel.
    assertTrue(NS.Share.Line(rec(NS, { target = "Evil|cffff0000Name" }), false):find("|", 1, true) == nil)
    assertNil(NS.Share.Line({ status = "lost" }, false), "nothing to share")
end)

test("share: talents link appended when enabled", function()
    local NS = fresh()
    local r = rec(NS)
    r.loadout = NS.Loadouts.Store({ importString = "CQQAAAAAA", specID = 253, name = "Raid" })
    local with = NS.Share.Line(r, true)
    local plain = NS.Share.Line(r, false)
    assertTrue(with:sub(1, #plain) == plain, "the line, then the link")
    assertTrue(with:find("|Htalentbuild:253:80:CQQAAAAAA|h[Beast Mastery: Raid]|h|r", 1, true) ~= nil, with)
    assertTrue(#with <= NS.Share.MAX_CHAT)
    assertEqual(NS.GetSetting("results.shareTalents"), true, "on by default (mockup §4)")
    local msgs = NS.Share.Messages(r)
    assertEqual(#msgs, 1)
    assertEqual(msgs[1], with)
    NS.db.profile.results.shareTalents = false
    msgs = NS.Share.Messages(r)
    assertEqual(#msgs, 1)
    assertEqual(msgs[1], plain, "the line alone when the setting is off")
    -- The link carries the level the fight was fought at (the talent tree's points come from it),
    -- and the logged-in character's for a record that holds none.
    r.who.level = 70
    assertTrue(NS.Share.TalentsLink(r):find("talentbuild:253:70:", 1, true) ~= nil, "the fight's level")
    r.who.level = nil
    assertTrue(NS.Share.TalentsLink(r):find("talentbuild:253:80:", 1, true) ~= nil, "the character's level")
    -- No loadout: the line alone either way.
    NS.db.profile.results.shareTalents = true
    assertEqual(NS.Share.Messages(rec(NS))[1], plain)
end)

test("share: send goes out of combat only, and the menu grays the channels the player is not in", function()
    local NS, M = fresh(function(m)
        m.IsInGroup = function() return false end
        m.IsInRaid = function() return false end
        m.IsInGuild = function() return true end
    end)
    local r = rec(NS)
    assertTrue(NS.Share.Send(r, "GUILD"))
    assertEqual(M.__sent[1].channel, "GUILD")
    assertEqual(M.__sent[1].text, NS.Share.Messages(r)[1])
    M.InCombatLockdown = function() return true end
    M.__resetPrinted()
    assertFalse(NS.Share.Send(r, "SAY"), "refused in combat")
    assertEqual(#M.__sent, 1)
    assertEqual(#M.__printed(), 1, "one line says why")
    M.InCombatLockdown = function() return false end
    local items = {}
    local desc = { CreateButton = function(_, label, fn)
        local b = { label = label, fn = fn, enabled = true }
        function b.SetEnabled(_, on) b.enabled = on end
        items[#items + 1] = b
        return b
    end }
    NS.Share.FillMenu(desc, r)
    local by = {}
    for _, b in ipairs(items) do by[b.label] = b end
    assertTrue(by.Say.enabled)
    assertFalse(by.Party.enabled, "not in a group")
    assertFalse(by.Raid.enabled)
    assertTrue(by.Guild.enabled)
    by["Whisper\226\128\166"].fn()
    assertEqual(M.__popups[#M.__popups].name, NS.Share.WHISPER_POPUP, "the whisper asks for a name")
end)

test("share: the row menu's Share is live for a stored fight", function()
    local NS = fresh()
    local r = rec(NS, { id = "a" })
    assertTrue(NS.Recorder.Save(r))
    local share
    local saved = NS.OpenMenu
    NS.OpenMenu = function(_, fill)
        local root = {}
        function root.CreateTitle() end
        function root.CreateButton(_, text)
            local item = { label = text, enabled = true, subs = 0 }
            function item.SetEnabled(_, on) item.enabled = on and true or false end
            function item.CreateButton() item.subs = item.subs + 1 return { SetEnabled = function() end } end
            if text == "Share" then share = item end
            return item
        end
        fill(root)
    end
    NS.Results.RowMenu(r)
    NS.OpenMenu = saved
    assertTrue(share ~= nil and share.enabled, "Share is live")
    assertEqual(share.subs, #NS.Share.CHANNELS, "one entry per channel")
end)

test("share: the whisper box offers the target as the client addresses them (realm on Retail, full regional name on Forever)", function()
    local NS, M = fresh(function(m)
        m.UnitIsPlayer = function(unit) return unit == "target" end
        m.UnitName = function(unit) if unit == "target" then return "Kaos", "Stormborn" end end
    end)
    local dialog = M.StaticPopupDialogs[NS.Share.WHISPER_POPUP]
    local text
    local box = { SetText = function(_, t) text = t end }
    dialog.OnShow({ editBox = box })
    if NS.Compat.IsForever() then
        assertEqual(text, (NS.Compat.UnitCharacterName("target")), "through Compat.UnitCharacterName")
    else
        assertEqual(text, "Kaos-Stormborn", "a cross-realm target keeps its realm")
    end
end)

test("share: forever: the line names the predominant talent tree (D5)", function()
    local NS, m = fresh()
    T.Loader.MockClient.apply(m, "forever")
    m.GetNumTalentTabs = function() return 3 end
    m.GetTalentTabInfo = function(i)
        return ({ "Beast Mastery", "Marksmanship", "Survival" })[i], 132164 + i, ({ 5, 41, 5 })[i], "bg"
    end
    local r = rec(NS)
    r.who = NS.Identity.Who()
    r.who.ilvl = 66.2
    local line = NS.Share.Line(r, false)
    assertTrue(line:find("Marksmanship 66.2", 1, true) ~= nil, line)
    m.GetNumTalentTabs, m.GetTalentTabInfo = nil, nil
    r.who = NS.Identity.Who()
    r.who.ilvl = 66.2
    line = NS.Share.Line(r, false)
    assertTrue(line:find(NS.ResultsTable.ClassName(r.who.class) .. " 66.2", 1, true) ~= nil,
               "no tree: the class names the player: " .. line)
    T.Loader.MockClient.apply(m)
end)

-- ── Race mode (race plan Task C2) ──────────────────────────────────────────────────────────────

local F = dofile(T.root .. "/tests/race_fixture.lua")(T)

local function forever() return T.NS.Compat.IsForever() end

--- A stored race of the record's shape: 30 s on the boss dummy, a late cast, a tail.
local function raceRec(NS, over)
    local r = rec(NS)
    r.identity = { content = "dummy", targetName = "Raider's Training Dummy", targetCreatureID = 31146 }
    r.boardKey = NS.Identity.BoardKey(r.identity)
    r.race = { length = 30, kind = "boss", status = "complete", score = 1539711, dps = 51323.7, tail = 3.1,
               grace = 1, restartGap = 6, flags = { lateCasts = { { t = 1.4, spellID = 29722 } } } }
    for k, v in pairs(over or {}) do r.race[k] = v end
    return r
end

local function capture(NS)
    local lines = {}
    NS.Print = function(line) lines[#lines + 1] = line end
    return lines
end

test("share: a race's line names its race length and race DPS, and an incomplete race says so", function()
    local NS = fresh()
    local r = raceRec(NS)
    local line = NS.Share.Line(r, false)
    assertTrue(line:find(SEP .. "0:30" .. SEP, 1, true) ~= nil, "the race length, not the fight's: " .. line)
    assertTrue(line:find(NS.Format.Number(51323.7) .. " DPS", 1, true) ~= nil, "the race DPS: " .. line)
    assertTrue(line:find("incomplete", 1, true) == nil)
    local inc = raceRec(NS, { status = "incomplete", endedAt = 20, dps = 76985.6 })
    line = NS.Share.Line(inc, false)
    assertTrue(line:find(NS.Format.Number(76985.6) .. " DPS" .. SEP .. "incomplete" .. SEP, 1, true) ~= nil, line)
    assertTrue(line:find("DPS Race", 1, true) == nil and line:find("run", 1, true) == nil, "Combat Trail's words")
end)

test("share: arming prints the armed line with the length and the target", function()
    if forever() then return end
    local S = F.fresh()
    local lines = capture(S.NS)
    assertTrue(F.arm(S, 60))
    assertEqual(lines[#lines], "Armed: 1:00 on Raider's Training Dummy. First hit starts the clock.")
end)

test("share: a result prints the score line with the delta, the flags and the tail", function()
    local NS = fresh()
    local r = raceRec(NS)
    local line = NS.Share.ResultLine(r, 2.4, true)
    assertEqual(line, NS.Format.Number(1539711) .. " damage \194\183 " .. NS.Format.Number(51323.7)
        .. " DPS in 0:30 on Raider's Training Dummy \226\128\148 new best (+2.4%) \194\183 1 late cast \194\183 tail +3.1s")
    local slower = NS.Share.ResultLine(raceRec(NS, { flags = { lateCasts = {} } }), -3.2, false)
    assertTrue(slower:find("\226\128\148 -3.2% vs best \194\183 tail +3.1s", 1, true) ~= nil, slower)
    local early = raceRec(NS, { status = "incomplete", endedAt = 20, flags = { lateCasts = {} } })
    early.race.tail = nil
    local inc = NS.Share.ResultLine(early, nil, nil)
    assertTrue(inc:find("\226\128\148 incomplete$") ~= nil, inc)
end)

test("share: the score line counts only the late casts the ignore list leaves", function()
    local NS = fresh()
    local r = raceRec(NS, { flags = { lateCasts = { { t = 1.2, spellID = 5384 }, { t = 1.4, spellID = 29722 } } } })
    assertTrue(NS.Share.ResultLine(r, 2.4, true):find("\194\183 1 late cast \194\183", 1, true) ~= nil)
    r.race.flags.lateCasts[2].spellID = 1856
    assertNil(NS.Share.ResultLine(r, 2.4, true):find("late", 1, true), "all ignored: no late casts")
end)

test("share: the race's own result is printed once, when it resolves", function()
    if forever() then return end
    local S = F.fresh()
    assert(S.NS.SetByPath("race.autoShow", false))
    local lines = capture(S.NS)
    F.whole(S, 30)
    assertEqual(S.NS.Race.State(), "result")
    local n = 0
    for _, l in ipairs(lines) do
        if l:find(" damage \194\183 ", 1, true) then n = n + 1 end
    end
    assertEqual(n, 1, "one score line")
    assertTrue(lines[#lines]:find("new best", 1, true) ~= nil, "a board's first race is a new best: " .. lines[#lines])
end)

test("share: a lost race prints that it could not be read, and has no score line", function()
    local NS = fresh()
    local lines = capture(NS)
    assertEqual(NS.Share.OnRaceResult(nil, { status = "lost", length = 30 }),
        "Couldn't read the race's result, so it is not saved as a race.")
    assertEqual(#lines, 1)
    assertNil(NS.Share.OnRaceResult(nil, nil), "nothing to say about nothing")
end)

test("share: on WoW Forever a saved race still shares, and no race line is printed", function()
    if not forever() then return end
    local NS = fresh()
    local lines = capture(NS)
    assertTrue(NS.Share.Line(raceRec(NS), false) ~= nil, "a saved race in the shared history shares")
    NS.SendBus(NS.MSG.RACE_ARMED, { length = 30 })
    NS.SendBus(NS.MSG.RACE_RESULT, raceRec(NS), { status = "complete" })
    assertEqual(#lines, 0, "no race receiver on WoW Forever")
end)
