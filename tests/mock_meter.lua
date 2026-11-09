-- tests/mock_meter.lua — a scripted C_DamageMeter modeling the 12.0 behavior DPS Race's probe measured
-- on Retail and Combat Trail assumes on WoW Forever (spec §3): every number, spell ID, GUID and flag is
-- SECRET while the combat restriction is on and plain after; sessions are addressable by ID; the
-- Current session is the newest one set. Ported from DPS Race @045f479 (tests/mock_meter.lua) for
-- `/kct probe` (plan Task 1.5); the meter adapter (plan Task 2.1) reads it too.
--
-- What differs from DPS Race's: the client's full list of eight functions (GetSessionDurationSeconds
-- and ResetAllCombatSessions join the six the adapter calls, as the kit's client_globals_live.lua and
-- the owner's Forever probe list them), a session may carry the PET as a source of its own, the
-- EnemyDamageTaken view answers by type and by ID, and the Dps meter type answers by ID as well.
--
-- Loaded by tests/run.lua as `dofile(root .. "/tests/mock_meter.lua")(Kit)`, so the secrets are the
-- kit's own wrappers (tests/_kit/secrets.lua): they raise on arithmetic, comparison between two
-- secrets, concat, indexing and calling. Install it on a mock BEFORE the addon loads, through
-- `T.load{ mutate = function(m) meter = T.mockMeter.install(m) end }`, so the Enum the addon
-- resolves at load time is this one.
--
-- The `issecretvalue` it installs is scoped to that instance's mock (the loader's environment reads
-- the mock first), which is Kit.installSecretValue's answer without touching the process-wide _G.
--
-- Controller:
--   SetSession(id, { damage, dps, duration, spells = { {id, dmg, dps}, ... }, others = {...},
--                    pet = { damage, dps, spells = {...} }, enemies = { {name, creatureID, damage}, ... } })
--       adds or replaces a session and makes it Current. `spells` keep the order given. `others` are
--       other sources in the session, each { guid, damage, dps }. `player = false` leaves the
--       player out of the session entirely (combat with no damage of theirs). `pet` is the pet's own
--       source, answered for the controller's pet GUID (SetPetGUID); absent, the pet's GUID answers
--       nil, as a client that folds the pet into its owner would. A nil `dps` (player, pet or
--       spell) answers no amountPerSecond. `enemies` is the session's EnemyDamageTaken view, one
--       source per enemy (name, sourceCreatureID, totalAmount), in the order given.
--       The live client's shapes (DPS Race's smoke test, 2026-10-23), each opt-in per session:
--         sourceDps = false   the player's source table carries no amountPerSecond
--         rowDps = false      the player's row in combatSources carries no amountPerSecond either
--         localFlagPlain = true  the row's isLocalPlayer stays PLAIN while every other value is secret
--         dpsType = true      the Dps meter type answers a source for the player
--         dpsTypeRate = false  that Dps-type source carries no amountPerSecond
--   RemoveSession(id) · SetCurrent(id|nil)
--   SetSecret(on)      the combat restriction: every value read while on is a secret wrapper.
--   SetSealed(id, on)  that one session answers secrets even with the restriction off.
--   SetAvailable(ok, reason) · SetRaise(fnName, message|nil) · SetPlayerGUID(guid) · SetPetGUID(guid)
--   Remove()           takes C_DamageMeter away (an older client).
--   calls              every API call, as { fn, args = {...} }.

return function(Kit)
    local MockMeter = {}

    local DAMAGE_DONE, DPS, ENEMY_TAKEN, OVERALL, CURRENT = 0, 1, 10, 0, 1

    local function newController()
        return {
            sessions  = {},
            order     = {},
            current   = nil,
            secret    = false,
            sealed    = {},
            available = true,
            reason    = nil,
            raise     = {},
            guid      = "Player-1-00000001",
            petGUID   = nil,
            calls     = {},
        }
    end

    local function wrapper(ctl, id)
        local on = ctl.secret or (id ~= nil and ctl.sealed[id])
        return function(v)
            if on then return Kit.secret(v) end
            return v
        end
    end

    local function maxSpell(spells)
        local m = 0
        for _, s in ipairs(spells or {}) do if s.dmg > m then m = s.dmg end end
        return m
    end

    local function sessionTable(ctl, id)
        local s = id and ctl.sessions[id]
        if not s then return nil end
        local w = wrapper(ctl, id)
        local sources, total, max = {}, 0, 0
        if s.player ~= false then
            sources[1] = {
                sourceGUID = w(ctl.guid), name = w("Testchar"), classFilename = "MAGE",
                isLocalPlayer = s.localFlagPlain and true or w(true), totalAmount = w(s.damage),
                amountPerSecond = s.rowDps ~= false and w(s.dps) or nil,
            }
            total, max = s.damage, s.damage
        end
        for _, o in ipairs(s.others or {}) do
            sources[#sources + 1] = {
                sourceGUID = w(o.guid), name = w("Other"), classFilename = "WARRIOR",
                isLocalPlayer = w(false), totalAmount = w(o.damage), amountPerSecond = w(o.dps),
            }
            total = total + o.damage
            if o.damage > max then max = o.damage end
        end
        return { combatSources = sources, maxAmount = w(max), totalAmount = w(total),
                 durationSeconds = w(s.duration) }
    end

    local function spellsOf(w, list)
        local spells = {}
        for i, sp in ipairs(list or {}) do
            spells[i] = { spellID = w(sp.id), totalAmount = w(sp.dmg), amountPerSecond = w(sp.dps) }
        end
        return spells
    end

    local function sourceTable(ctl, id, guid)
        local s = id and ctl.sessions[id]
        if not s then return nil end
        local w = wrapper(ctl, id)
        if s.pet and ctl.petGUID and guid == ctl.petGUID then
            return { combatSpells = spellsOf(w, s.pet.spells), maxAmount = w(maxSpell(s.pet.spells)),
                     totalAmount = w(s.pet.damage), amountPerSecond = w(s.pet.dps) }
        end
        if s.player == false or guid ~= ctl.guid then return nil end
        return { combatSpells = spellsOf(w, s.spells), maxAmount = w(maxSpell(s.spells)), totalAmount = w(s.damage),
                 amountPerSecond = s.sourceDps ~= false and w(s.dps) or nil }
    end

    -- The EnemyDamageTaken view of a session: one source per enemy, { name, creatureID, damage }.
    local function enemyTable(ctl, id)
        local s = id and ctl.sessions[id]
        if not s then return nil end
        local w = wrapper(ctl, id)
        local sources = {}
        for i, e in ipairs(s.enemies or {}) do
            sources[i] = { sourceGUID = w("Creature-0-1-2-3-" .. tostring(e.creatureID) .. "-" .. i),
                           name = w(e.name), sourceCreatureID = w(e.creatureID), isLocalPlayer = w(false),
                           totalAmount = w(e.damage), amountPerSecond = w(e.dps) }
        end
        return { combatSources = sources, durationSeconds = w(s.duration) }
    end

    -- The Dps meter type's source for the player: totalAmount the damage, amountPerSecond the rate.
    local function dpsSourceTable(ctl, id, guid)
        local s = id and ctl.sessions[id]
        if not s or not s.dpsType or s.player == false or guid ~= ctl.guid then return nil end
        local w = wrapper(ctl, id)
        return { combatSpells = {}, totalAmount = w(s.damage),
                 amountPerSecond = s.dpsTypeRate ~= false and w(s.dps) or nil }
    end

    local function record(ctl, fn, ...)
        ctl.calls[#ctl.calls + 1] = { fn = fn, args = { ... } }
        local msg = ctl.raise[fn]
        if msg then error(msg, 3) end
    end

    local function currentFor(ctl, sessionType)
        if sessionType == CURRENT then return ctl.current end
        return nil
    end

    local function buildApi(ctl)
        local api = {}
        function api.IsDamageMeterAvailable()
            record(ctl, "IsDamageMeterAvailable")
            return ctl.available, ctl.reason
        end
        function api.GetAvailableCombatSessions()
            record(ctl, "GetAvailableCombatSessions")
            local out = {}
            for i = #ctl.order, 1, -1 do               -- newest first, as the client lists them
                local id = ctl.order[i]
                local w = wrapper(ctl, nil)
                out[#out + 1] = { sessionID = id, name = w("Session " .. id),
                                  durationSeconds = w(ctl.sessions[id].duration) }
            end
            return out
        end
        function api.GetCombatSessionFromID(id, statType)
            record(ctl, "GetCombatSessionFromID", id, statType)
            if statType == ENEMY_TAKEN then return enemyTable(ctl, id) end
            if statType ~= DAMAGE_DONE then return nil end
            return sessionTable(ctl, id)
        end
        function api.GetCombatSessionFromType(sessionType, statType)
            record(ctl, "GetCombatSessionFromType", sessionType, statType)
            if statType == ENEMY_TAKEN then return enemyTable(ctl, currentFor(ctl, sessionType)) end
            if statType ~= DAMAGE_DONE then return nil end
            return sessionTable(ctl, currentFor(ctl, sessionType))
        end
        function api.GetCombatSessionSourceFromID(id, statType, guid, creatureID)
            record(ctl, "GetCombatSessionSourceFromID", id, statType, guid, creatureID)
            if statType == DPS then return dpsSourceTable(ctl, id, guid) end
            if statType ~= DAMAGE_DONE then return nil end
            return sourceTable(ctl, id, guid)
        end
        function api.GetCombatSessionSourceFromType(sessionType, statType, guid, creatureID)
            record(ctl, "GetCombatSessionSourceFromType", sessionType, statType, guid, creatureID)
            if statType == DPS then return dpsSourceTable(ctl, currentFor(ctl, sessionType), guid) end
            if statType ~= DAMAGE_DONE then return nil end
            return sourceTable(ctl, currentFor(ctl, sessionType), guid)
        end
        function api.GetSessionDurationSeconds(sessionType)
            record(ctl, "GetSessionDurationSeconds", sessionType)
            local id = currentFor(ctl, sessionType)
            local s = id and ctl.sessions[id]
            if not s then return nil end
            return wrapper(ctl, id)(s.duration)
        end
        function api.ResetAllCombatSessions()
            record(ctl, "ResetAllCombatSessions")
            ctl.sessions, ctl.order, ctl.current = {}, {}, nil
        end
        return api
    end

    local function addMethods(ctl, mocks)
        function ctl.SetSession(id, data)
            if not ctl.sessions[id] then ctl.order[#ctl.order + 1] = id end
            ctl.sessions[id] = data
            ctl.current = id
        end
        function ctl.RemoveSession(id)
            ctl.sessions[id] = nil
            for i = #ctl.order, 1, -1 do
                if ctl.order[i] == id then table.remove(ctl.order, i) end
            end
            if ctl.current == id then ctl.current = nil end
        end
        function ctl.SetCurrent(id) ctl.current = id end
        function ctl.SetSecret(on) ctl.secret = on and true or false end
        function ctl.SetSealed(id, on) ctl.sealed[id] = on and true or nil end
        function ctl.SetAvailable(ok, reason) ctl.available, ctl.reason = ok, reason end
        function ctl.SetRaise(fn, msg) ctl.raise[fn] = msg end
        function ctl.SetPlayerGUID(guid) ctl.guid = guid end
        function ctl.SetPetGUID(guid) ctl.petGUID = guid end
        function ctl.Remove() mocks.C_DamageMeter = nil end
        function ctl.CallsTo(fn)
            local out = {}
            for _, c in ipairs(ctl.calls) do if c.fn == fn then out[#out + 1] = c end end
            return out
        end
    end

    --- Install the scripted meter on one mock build and answer its controller.
    function MockMeter.install(mocks)
        local ctl = newController()
        addMethods(ctl, mocks)
        mocks.C_DamageMeter = buildApi(ctl)
        mocks.Enum = mocks.Enum or {}
        mocks.Enum.DamageMeterType = { DamageDone = DAMAGE_DONE, Dps = DPS, DamageTaken = 7,
                                       EnemyDamageTaken = ENEMY_TAKEN }
        mocks.Enum.DamageMeterSessionType = { Overall = OVERALL, Current = CURRENT, Expired = 2 }
        -- The player's and the pet's GUIDs are the controller's; any other unit is the base mock's
        -- answer, so a case can script a target alongside the meter.
        local priorGUID = mocks.UnitGUID
        mocks.UnitGUID = function(unit)
            if unit == "player" then return ctl.guid end
            if unit == "pet" and ctl.petGUID then return ctl.petGUID end
            return priorGUID and priorGUID(unit) or nil
        end
        mocks.issecretvalue = function(v) return Kit.isSecret(v) end
        mocks.C_RestrictedActions = {
            IsAddOnRestrictionActive = function() return ctl.secret end,
        }
        return ctl
    end

    return MockMeter
end
