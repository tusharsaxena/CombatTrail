-- tests/insights_fixture.lua — the Insights suites' shared history (Race mode plan Task D2): stored-shape
-- fight records, races among them, by two characters. Loaded with `dofile(T.root ..
-- "/tests/insights_fixture.lua")(T)`; every builder takes the instance's NS, so a suite stands a fresh
-- instance up per case. Not a suite: no test of its own.
--
-- THE HISTORY (`F.history(NS)`), oldest first:
--   f1  Tush (Fire), a raid boss board, 1000 DPS, three days ago
--   r1  Tush (Fire), a 3:00 race on a Cleave dummy, 1500 race DPS (its fight's 1400 aside), tail 9.2 s
--   f2  Tush (Fire), the same raid boss board, 1200 DPS (a new best, +20%), two days ago
--   r2  Tush (Fire), the same Cleave 3:00 board, 1600 race DPS (a new best, +6.7%), tail 4 s
--   f3  Lanfear (Destruction), a dungeon boss board, 800 DPS, yesterday
--   r3  Lanfear (Destruction), a 1:00 race on a Boss dummy, 1200 race DPS, a late Incinerate (29722,
--       flags it) and a late Feign Death (5384, on the stock ignore list), tail 25 s
--   r4  Tush (Fire), an incomplete 1:00 Cleave race, 41 s in combat, two hours ago

return function(T)
    local F = {}
    local DAY, HOUR = 86400, 3600
    -- Today at noon: every fixture day lands on its own local day, whatever the hour the suite runs.
    do
        local d = os.date("*t")
        F.NOW = os.time({ year = d.year, month = d.month, day = d.day, hour = 12, min = 0, sec = 0 })
    end
    F.DAY, F.HOUR = DAY, HOUR
    F.OTHER = 999001     -- no dummy on either client: a race on it reads its stored kind

    local CHARS = {
        tush = { name = "Tush", realm = "Area 52", class = "MAGE", specID = 63, specName = "Fire", ilvl = 640 },
        lan = { name = "Lanfear", realm = "Area 52", class = "WARLOCK", specID = 267, specName = "Destruction", ilvl = 638 },
    }

    local function whoOf(NS, key)
        local w = {}
        for k, v in pairs(CHARS[key or "tush"]) do w[k] = v end
        w.client = NS.Identity.Who().client
        return w
    end

    --- A character's key as the filters read it (Fights.CharKey).
    function F.charKey(NS, key)
        return NS.Bests.CharKey(whoOf(NS, key))
    end

    local n = 0
    --- A plain fight. `o`: id, dps, t, char ("tush" | "lan"), board ("e:<id>:<difficulty>"), content,
    --- name, duration.
    function F.fight(NS, o)
        o = o or {}
        n = n + 1
        local dps, duration = o.dps or 1000, o.duration or 120
        local board = o.board or "e:1111:15"
        return {
            schema = 4, id = o.id or ("fight-" .. n), t = o.t or (F.NOW - n), duration = duration, status = "final",
            who = whoOf(NS, o.char),
            identity = { content = o.content or "raid", targetName = o.name or "Grobbulus",
                         encounterID = tonumber(board:match("^e:(%d+)")),
                         encounterName = o.name or "Grobbulus", difficultyID = 15, difficultyName = "Heroic",
                         isBoss = true },
            boardKey = board, damage = { merged = dps * duration, player = dps * duration }, dps = dps,
        }
    end

    --- A saved race on a training dummy. `o`: id, length, status, raceDps (score over the length, or
    --- over `endedAt` when incomplete), endedAt, kind, char, flags, tail, t.
    function F.race(NS, o)
        o = o or {}
        n = n + 1
        local length = o.length or 180
        local secs = (o.status == "incomplete") and o.endedAt or length
        local score = (o.raceDps or 1500) * secs
        local r = {
            schema = 4, id = o.id or ("race-" .. n), t = o.t or (F.NOW - n), duration = length + 10, status = "final",
            who = whoOf(NS, o.char),
            identity = { content = "dummy", targetName = "Training Dummy", targetCreatureID = F.OTHER, difficultyID = 0 },
            damage = { merged = score, player = score }, dps = math.floor(score / (length + 10)),
        }
        r.boardKey = NS.Identity.BoardKey(r.identity)
        r.race = { length = length, kind = o.kind or "cleave", status = o.status or "complete", flags = o.flags or {},
                   score = score, tail = o.tail, endedAt = o.endedAt, combatEnd = 2.0, grace = 1.0, restartGap = 6 }
        return r
    end

    --- The suites' history (above), oldest first.
    function F.history(NS)
        local now = F.NOW
        return {
            F.fight(NS, { id = "f1", dps = 1000, t = now - 3 * DAY }),
            F.race(NS, { id = "r1", raceDps = 1500, t = now - 3 * DAY + HOUR, tail = 9.2 }),
            F.fight(NS, { id = "f2", dps = 1200, t = now - 2 * DAY }),
            F.race(NS, { id = "r2", raceDps = 1600, t = now - 2 * DAY + HOUR, tail = 4.0 }),
            F.fight(NS, { id = "f3", dps = 800, t = now - DAY, char = "lan", content = "dungeon", board = "e:2222:8",
                          name = "Vexamus" }),
            F.race(NS, { id = "r3", char = "lan", kind = "boss", length = 60, raceDps = 1200, t = now - DAY + HOUR,
                         tail = 25, flags = { lateCasts = { { t = 1.6, spellID = 29722 }, { t = 3.0, spellID = 5384 } } } }),
            F.race(NS, { id = "r4", status = "incomplete", length = 60, endedAt = 41, raceDps = 500, t = now - 2 * HOUR }),
        }
    end

    --- The ids of `list`, sorted and joined.
    function F.ids(list)
        local out = {}
        for i, r in ipairs(list or {}) do out[i] = r.id end
        table.sort(out)
        return table.concat(out, ",")
    end

    --- The labels of an options list, joined with "|".
    function F.labels(options)
        local out = {}
        for i, o in ipairs(options or {}) do out[i] = o.label end
        return table.concat(out, "|")
    end

    --- Store every record of `list` (Recorder.Save), then drop the cached boards.
    function F.store(NS, list)
        for _, r in ipairs(list) do T.assertTrue(NS.Recorder.Save(r), "saved " .. tostring(r.id)) end
        NS.Bests.Invalidate()
    end

    return F
end
