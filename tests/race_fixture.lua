-- tests/race_fixture.lua — the race suites' shared driver (Race mode plan Task B1, R:tests#1): a fresh
-- instance on the scripted meter (tests/mock_meter.lua), the player targeting a training dummy (Retail's
-- Raider's Training Dummy, creature 31146, a "boss" dummy), a recorder of the race's and the fight's
-- bus messages, and the steps of a pull through the REAL state machines: the events fire (the regen
-- edges, the meter's session updates, the player's casts), never a Race.On* call, so Fight and Race
-- each hear what the client would send them. Loaded by tests/test_race.lua as
-- `dofile(T.root .. "/tests/race_fixture.lua")(T)`; Tasks B2, B3, C1, C2 and E1 reuse it. F.reload is
-- the /reload (B2): a new instance on the same SavedVariables.
--
-- THE CLOCK. The kit's timer queue fires every queued timer at once, whatever its delay; Fight's settle
-- and the race's buzzer each re-check GetTime() and wait again when serviced early, so F.run(t) (set
-- the clock, then service the queue a few rounds) drives them to the second, as the client would.

return function(T)
    local F = {}

    F.DUMMY = 31146
    F.DUMMY_GUID = "Creature-0-1-2-3-31146-0000AAAA"
    F.BOAR_GUID = "Creature-0-1-2-3-1985-0000BBBB"

    -- DPS Race's probe run 8 (its tests/race_clock.lua F.SESSION): a 39 s session.
    F.SESSION = { damage = 1539711, dps = 39479.8, duration = 39,
                  spells = { { id = 29722, dmg = 1000000, dps = 25641 }, { id = 116858, dmg = 500000, dps = 12820 },
                             { id = 348, dmg = 39711, dps = 1018 } } }

    -- Every race and fight message, in the order heard: { name, ... }.
    local NAMES = { "RACE_STATE_CHANGED", "RACE_ARMED", "RACE_STARTED", "RACE_BUZZER", "RACE_RESULT",
                    "RACE_CANCELED", "FIGHT_STARTED", "FIGHT_FIRST_HIT", "FIGHT_ENDED", "FIGHT_SAVED",
                    "FIGHT_SKIPPED" }

    local function listen(NS)
        local heard = {}
        local rx = NS.NewBusTarget()
        for _, key in ipairs(NAMES) do
            rx:RegisterMessage(NS.MSG[key], function(_, ...)
                heard[#heard + 1] = { key, ... }
            end)
        end
        return heard
    end

    --- A fresh instance. opts.target: the target's GUID (the dummy's by default; false for none);
    --- opts.mutate runs on the mock before the load. Answers the fixture's state table `S`:
    --- { inst, NS, M, meter, heard }.
    function F.fresh(opts)
        opts = opts or {}
        local meter
        local inst = T.load{ mutate = function(m)
            meter = T.mockMeter.install(m)
            if opts.target ~= false then
                m.__unitExists.target = true
                m.__unitGUIDs.target = opts.target or F.DUMMY_GUID
                m.__unitNames.target = opts.target and "Angry Boar" or "Raider's Training Dummy"
            end
            if opts.mutate then opts.mutate(m) end
        end }
        local S = { inst = inst, NS = inst.NS, M = inst.mocks, meter = meter }
        S.heard = listen(inst.NS)
        S.M.__now = 100
        return S
    end

    --- A /reload (Task B2): a new instance on the SAME SavedVariables, the client's meter still holding
    --- `opts.sessions` ({ [id] = session }; session 25 = F.SESSION by default, {} for none), the clock
    --- at `opts.now` (S's clock by default) and in combat when `opts.inCombat`. The new state table is
    --- listening before OnEnable runs, so it hears what the resume sends. opts.target and opts.mutate
    --- as F.fresh's.
    function F.reload(S, opts)
        opts = opts or {}
        local saved = _G.CombatTrailDB
        local now = opts.now or (S and S.M.__now) or 100
        local meter
        local inst = T.load{ init = false, mutate = function(m)
            meter = T.mockMeter.install(m)
            if opts.target ~= false then
                m.__unitExists.target = true
                m.__unitGUIDs.target = opts.target or F.DUMMY_GUID
                m.__unitNames.target = opts.target and "Angry Boar" or "Raider's Training Dummy"
            end
            m.__now = now
            m.__inCombat = opts.inCombat and true or false
            m.InCombatLockdown = function() return m.__inCombat end
            if opts.mutate then opts.mutate(m) end
        end }
        for id, session in pairs(opts.sessions or { [25] = F.SESSION }) do meter.SetSession(id, session) end
        _G.CombatTrailDB = saved
        local AceAddon = inst.mocks.LibStub("AceAddon-3.0")
        AceAddon:InitializeAddon(inst.NS)
        local R = { inst = inst, NS = inst.NS, M = inst.mocks, meter = meter }
        R.heard = listen(inst.NS)
        AceAddon:EnableAddon(inst.NS)
        return R
    end

    --- This character's pending race slot (db.global.pendingRaces), or nil.
    function F.slot(S)
        local slots = S.NS.db.global.pendingRaces
        local key = S.NS.Bests.CharKey(S.NS.Identity.Who())
        return type(slots) == "table" and key and slots[key] or nil
    end

    function F.at(S, t) S.M.__now = t end

    --- Set the clock to `t` and service the timer queue (three rounds: a timer serviced early
    --- re-queues itself for its own time).
    function F.run(S, t)
        F.at(S, t)
        for _ = 1, 3 do S.M.__fireTimers() end
    end

    function F.enter(S, t)
        F.at(S, t)
        S.M.InCombatLockdown = function() return true end
        S.M.__inCombat = true
        S.M.__fire("PLAYER_REGEN_DISABLED")
    end

    function F.leave(S, t)
        F.at(S, t)
        S.M.InCombatLockdown = function() return false end
        S.M.__inCombat = false
        S.M.__fire("PLAYER_REGEN_ENABLED")
    end

    --- A damage update for session `id` (a DAMAGE_METER_COMBAT_SESSION_UPDATED of DamageDone).
    function F.hit(S, t, id)
        F.at(S, t)
        S.M.__fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, id)
    end

    function F.die(S, t)
        F.at(S, t)
        S.M.__fire("PLAYER_DEAD")
    end

    local guid = 0
    --- A player cast event: kind "start" | "empower" | "channel" | "succeeded" | "interrupted" |
    --- "channelStop"; `castGUID` defaults to a fresh one.
    local EVENT = { start = "UNIT_SPELLCAST_START", empower = "UNIT_SPELLCAST_EMPOWER_START",
                    channel = "UNIT_SPELLCAST_CHANNEL_START", succeeded = "UNIT_SPELLCAST_SUCCEEDED",
                    interrupted = "UNIT_SPELLCAST_INTERRUPTED", channelStop = "UNIT_SPELLCAST_CHANNEL_STOP" }
    function F.cast(S, t, kind, spellID, castGUID)
        F.at(S, t)
        if castGUID == nil then
            guid = guid + 1
            castGUID = "Cast-" .. guid
        end
        S.M.__fire(EVENT[kind], "player", castGUID, spellID)
    end

    --- Arm at `t` (100 by default) for `length` (30 by default). Answers Race.Arm's answers.
    function F.arm(S, length, t)
        F.at(S, t or 100)
        return S.NS.Race.Arm(length or 30)
    end

    --- The pull: session `id` (25) set, combat entry at `t0` (101), the first hit at t0 + 1.
    function F.pull(S, t0, id, session)
        t0, id = t0 or 101, id or 25
        S.meter.SetSession(id, session or F.SESSION)
        F.enter(S, t0)
        F.run(S, t0 + 0.25)
        F.hit(S, t0 + 1, id)
        return t0 + 1
    end

    --- Damage every `step` seconds on session `id` from `from` to `to`, servicing the timers each time.
    function F.damage(S, id, from, to, step)
        local t = from
        while t <= to + 1e-9 do
            F.hit(S, t, id)
            F.run(S, t)
            t = t + (step or 1)
        end
    end

    --- Combat ends at `t`, then the settle runs to its end (the grace and the quiet after it).
    function F.settle(S, t)
        F.leave(S, t)
        F.run(S, t + 4.1)
        F.run(S, t + 7)
    end

    --- A whole race: armed for `length` at 100, pulled at 101 (the first hit at 102), damage each
    --- second to the buzzer, combat ending `after` seconds past it, settled. Answers the first hit.
    function F.whole(S, length, after)
        length = length or 30
        assert(F.arm(S, length))
        local start = F.pull(S)
        F.damage(S, 25, start + 1, start + length, 1)
        F.settle(S, start + length + (after or 1))
        return start
    end

    --- The names heard, as "A,B,C" (RACE_STATE_CHANGED left out unless `withStates`).
    function F.trail(S, withStates)
        local out = {}
        for _, h in ipairs(S.heard) do
            if withStates or h[1] ~= "RACE_STATE_CHANGED" then out[#out + 1] = h[1] end
        end
        return table.concat(out, ",")
    end

    --- The race states visited, as "from>to,...".
    function F.states(S)
        local out = {}
        for _, h in ipairs(S.heard) do
            if h[1] == "RACE_STATE_CHANGED" then out[#out + 1] = h[3] .. ">" .. h[4] end
        end
        return table.concat(out, ",")
    end

    --- The last message heard under `key`, as its payload list (nil when none).
    function F.last(S, key)
        for i = #S.heard, 1, -1 do
            if S.heard[i][1] == key then return S.heard[i] end
        end
        return nil
    end

    --- How many messages were heard under `key`.
    function F.count(S, key)
        local n = 0
        for _, h in ipairs(S.heard) do
            if h[1] == key then n = n + 1 end
        end
        return n
    end

    --- The stored records, newest first.
    function F.records(S)
        local out = {}
        local g = S.NS.db.global
        for _, id in ipairs(g.fightOrder) do out[#out + 1] = g.fights[id] end
        return out
    end

    --- The path of the first secret key or value in `v`, or nil.
    function F.findSecret(v, path, seen)
        path, seen = path or "", seen or {}
        if T.isSecret(v) then return path ~= "" and path or "(root)" end
        if type(v) ~= "table" or seen[v] then return nil end
        seen[v] = true
        for k, x in pairs(v) do
            if T.isSecret(k) then return path .. "[secret key]" end
            local found = F.findSecret(x, path .. "." .. tostring(k), seen)
            if found then return found end
        end
        return nil
    end

    function F.near(got, want, msg)
        T.assertTrue(type(got) == "number" and math.abs(got - want) < 1e-6,
            (msg or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got))
    end

    return F
end
