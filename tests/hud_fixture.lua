-- tests/hud_fixture.lua — the DPS HUD suites' shared driver (plan Task 3.2): a fresh instance on the
-- scripted meter (tests/mock_meter.lua) with the kit's paint recorder, the player targeting a boar so
-- a fight has a board key, an optional pet the meter answers for, and the steps of a fight through
-- the real state machine (combat entry, the first hit, the ticks, the settle). Loaded by
-- tests/test_hud_chart.lua, test_hud_pace.lua, test_hud_breakdown.lua and test_hud_appearance.lua
-- as `dofile(T.root .. "/tests/hud_fixture.lua")(T)`.

return function(T)
    local H = {}
    local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")

    H.BOAR_GUID = "Creature-0-1-2-3-1985-0000AAAA"
    H.PET_GUID = "Pet-0-1-2-3-4"

    --- A fresh instance; opts.pet summons a pet the meter answers for, opts.mutate runs on the mock.
    function H.fresh(opts)
        opts = opts or {}
        local meter
        local inst = T.load{ mutate = function(m)
            installPaint(m)
            meter = T.mockMeter.install(m)
            m.__unitExists.target = true
            m.__unitGUIDs.target = H.BOAR_GUID
            m.__unitNames.target = "Angry Boar"
            if opts.pet then
                m.__unitExists.pet = true
                m.__unitGUIDs.pet = H.PET_GUID
                m.__unitNames.pet = "Wolf"
            end
            if opts.mutate then opts.mutate(m) end
        end }
        if opts.pet then meter.SetPetGUID(H.PET_GUID) end
        return inst, meter, inst.NS.Hud
    end

    function H.at(inst, t) inst.mocks.__now = t end

    --- Write one profile path under `hud.` and announce it, as the settings seam does.
    function H.setHud(inst, path, value)
        local node = inst.NS.db.profile.hud
        local parts = {}
        for part in path:gmatch("[^.]+") do parts[#parts + 1] = part end
        for i = 1, #parts - 1 do
            if type(node[parts[i]]) ~= "table" then node[parts[i]] = {} end
            node = node[parts[i]]
        end
        node[parts[#parts]] = value
        inst.NS.AnnounceSettingsChanged("hud." .. path, value)
    end

    function H.enter(inst, t)
        H.at(inst, t)
        inst.mocks.InCombatLockdown = function() return true end
        inst.mocks.__inCombat = true
        inst.mocks.__fire("PLAYER_REGEN_DISABLED")
    end

    function H.leave(inst, t)
        H.at(inst, t)
        inst.mocks.InCombatLockdown = function() return false end
        inst.mocks.__inCombat = false
        inst.mocks.__fire("PLAYER_REGEN_ENABLED")
    end

    function H.hit(inst, t, id)
        H.at(inst, t)
        inst.mocks.__fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, id)
    end

    --- Let the clock reach t and run whatever timers are due by then.
    function H.run(inst, t)
        H.at(inst, t)
        inst.mocks.__fireTimers()
    end

    --- A fight on session `id` from `t0`: combat entry, the first damage a second in, a tick.
    function H.start(inst, meter, id, session, t0)
        meter.SetSession(id, session)
        H.enter(inst, t0)
        H.run(inst, t0 + 0.25)
        H.hit(inst, t0 + 1, id)
        H.run(inst, t0 + 1.25)
    end

    --- Ticks every quarter second from `from` to `to`.
    function H.tick(inst, from, to)
        local t = from
        while t <= to + 1e-9 do
            H.run(inst, t)
            t = t + 0.25
        end
    end

    --- The rest of it: combat ends at t0 + len, the settle runs, the fight ends "final".
    function H.finish(inst, t0, len)
        H.leave(inst, t0 + len)
        H.run(inst, t0 + len + 5)
        H.run(inst, t0 + len + 7)
    end

    function H.whole(inst, meter, id, session, t0, len)
        H.start(inst, meter, id, session, t0)
        H.finish(inst, t0, len)
    end

    local guid = 0
    --- A cast the lanes' capture hears (modules/LaneCasts.lua -> modules/Casts.lua).
    function H.cast(inst, t, unit, id)
        H.at(inst, t)
        guid = guid + 1
        inst.mocks.__fire("UNIT_SPELLCAST_SUCCEEDED", unit, "Cast-" .. guid, id)
    end

    --- The body on screen now ("live" or "over").
    function H.body(Hud, key)
        local ui = Hud.__ui()
        return ui and ui.body[key or ui.current] or nil
    end

    function H.near(got, want, msg)
        T.assertTrue(type(got) == "number" and math.abs(got - want) < 1e-6,
            (msg or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got))
    end

    return H
end
