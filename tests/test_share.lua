-- tests/test_share.lua — Share (plan Task 4.2, spec §7, mockup §9): the one-line chat summary of a
-- stored fight, at most one chat message long, the talents link after it when the setting is on,
-- the channel menu, the refusal in combat, and the row menu's Share now live.

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
