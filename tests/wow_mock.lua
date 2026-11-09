-- tests/wow_mock.lua — a THIN extender over the kit's tests/_kit/mock_base.lua: only the fakes this
-- addon needs and the kit does not carry (testing-§1). Plain per-key overwrite on a fresh table.
-- Later tasks add the meter, unit and item fakes their modules read.
--
-- Loaded as `assert(loadfile(root .. "/tests/wow_mock.lua"))(root)`, so the kit path resolves from
-- any working directory. `build()` answers a fresh mock per call, which is what lets a suite stand a
-- whole isolated instance up per case.

local root = ... or "."
local base = dofile(root .. "/tests/_kit/mock_base.lua")
-- The kit's binding model (kit revision 42): the installer keeps no state of its own, so it is read
-- once and run on every fresh mock.
local installBindings = dofile(root .. "/tests/_kit/mock_bindings.lua")
-- The kit's frame-layer recorder (kit revision 42), on every mock: the addon sets levels relative to a
-- parent (core/Constants.lua LAYERS), and the base alone answers GetFrameLevel with the frame itself.
local installLayers = dofile(root .. "/tests/_kit/mock_layers.lua")

local function build()
    local M = base()
    local libs = M.__libs

    -- A NAMED frame is a global in the client, which is how a key binding's `CLICK <name>` finds its
    -- button (launcher-§6). The base records the name only; publish it the way the client does.
    local baseCreateFrame = M.CreateFrame
    M.__frameByName = {}
    M.CreateFrame = function(frameType, name, parent, template)
        local f = baseCreateFrame(frameType, name, parent, template)
        if type(name) == "string" and name ~= "" then
            M.__frameByName[name] = f
            M[name] = f
        end
        return f
    end
    installLayers(M)

    -- Units beyond the base's player (modules/LaneCasts.lua reads the pet's name). A test sets
    -- M.__unitExists.pet and M.__unitNames.pet; the player's name stays the capture context's.
    M.__unitExists.pet = false
    M.__unitNames = {}
    M.UnitName = function(unit)
        if unit == nil or unit == "player" then return M.__context.name end
        return M.__unitNames[unit]
    end

    -- C_Spell: a spell's icon is a made-up file id per plain ID (136000 + id), nil for anything else.
    -- A suite that hands a secret ID replaces GetSpellTexture with one that reveals it.
    M.C_Spell = {
        GetSpellTexture = function(id)
            if type(id) == "number" then return 136000 + id end
            return nil
        end,
        GetSpellName = function(id)
            if type(id) == "number" then return "Spell " .. id end
            return nil
        end,
    }

    -- A spell's base cooldown in ms (modules/LaneRender.lua's long-cooldown glow): 0 unless a test
    -- sets M.__baseCooldowns[id]; every ask is counted per ID, so a suite can hold the cache to one.
    M.__baseCooldowns, M.__baseCooldownCalls = {}, {}
    M.GetSpellBaseCooldown = function(id)
        M.__baseCooldownCalls[id] = (M.__baseCooldownCalls[id] or 0) + 1
        return M.__baseCooldowns[id] or 0, 0
    end
    -- The player's spell haste in percent (the lanes' haste-adjusted GCD ticks): 0 unless set.
    M.__haste = 0
    M.UnitSpellHaste = function() return M.__haste end

    -- The lanes' visibility rules (modules/LaneVisibility.lua): mounted, resting, in a vehicle, in a
    -- pet battle, in a delve. Each answers a settable field, false until a test sets it.
    M.__mounted, M.__resting, M.__inVehicle, M.__petBattle, M.__inDelve = false, false, false, false, false
    M.IsMounted = function() return M.__mounted end
    M.IsResting = function() return M.__resting end
    M.UnitInVehicle = function(unit) return unit == "player" and M.__inVehicle end
    M.C_PetBattles = { IsInBattle = function() return M.__petBattle end }
    M.C_PartyInfo = { IsDelveInProgress = function() return M.__inDelve end }

    -- TOC metadata, read through LibKa0s-Env-1.0 (core/EnvSetup.lua).
    M.__toc = {
        Version = "0.1.0",
        Title   = "Ka0s Combat Trail",
        Notes   = "Your casts as a scrolling trail, a live DPS HUD on every fight, and a history of your fights.",
    }
    M.C_AddOns = {
        GetAddOnMetadata = function(_, field) return M.__toc[field] end,
        IsAddOnLoaded    = function() return true, true end,
    }

    -- LibSharedMedia-3.0: a recording registry (core/MediaSetup.lua registers the shipped faces).
    local media = { font = {}, statusbar = {}, border = {}, background = {}, sound = {} }
    libs["LibSharedMedia-3.0"] = {
        MediaType = { FONT = "font", STATUSBAR = "statusbar", BORDER = "border",
                      BACKGROUND = "background", SOUND = "sound" },
        Register  = function(_, kind, key, path)
            media[kind] = media[kind] or {}
            media[kind][key] = path
            return true
        end,
        Fetch     = function(_, kind, key) return media[kind] and media[kind][key] end,
        List      = function(_, kind)
            local out = {}
            for key in pairs(media[kind] or {}) do out[#out + 1] = key end
            table.sort(out)
            return out
        end,
        HashTable = function(_, kind) return media[kind] or {} end,
    }

    -- LibDataBroker-1.1 and LibDBIcon-1.0: the launcher's one object, registered twice (launcher-§1).
    local brokers = {}
    libs["LibDataBroker-1.1"] = {
        NewDataObject       = function(_, name, obj) brokers[name] = obj return obj end,
        GetDataObjectByName = function(_, name) return brokers[name] end,
        __objects           = brokers,
    }
    libs["LibDBIcon-1.0"] = {
        objects  = {},
        __shown  = {},
        Register = function(self, name, broker, db) self.objects[name] = { broker = broker, db = db } end,
        Refresh  = function(self, name, db)
            local o = self.objects[name]
            if o then o.db = db end
        end,
        Hide     = function(self, name) self.__shown[name] = false end,
        Show     = function(self, name) self.__shown[name] = true end,
    }

    -- The Profiles page's AceConfig trio (settings/Profiles.lua): the kit loads no lib from libs/, so
    -- these stand in for AceDBOptions' table and AceConfigDialog's draw.
    libs["AceDBOptions-3.0"] = {
        GetOptionsTable = function(_, db) return { type = "group", name = "Profiles", args = {}, __db = db } end,
    }
    local registered = {}
    libs["AceConfig-3.0"] = {
        RegisterOptionsTable = function(_, name, tbl) registered[name] = tbl end,
        __registered = registered,
    }
    libs["AceConfigDialog-3.0"] = {
        Open = function(self, name, container)
            self.__opens = (self.__opens or 0) + 1
            self.__lastOpen = { name = name, container = container }
        end,
        Close = function() end,
        SetDefaultSize = function() end,
    }
    libs["AceConfigRegistry-3.0"] = {
        NotifyChange = function() end,
        RegisterOptionsTable = function() end,
    }

    -- The client's key-binding API, from the kit (the Keybindings tab, options-ui-§20). Its
    -- GetBindingName reads M and the real _G, but this addon's BINDING_NAME_ globals are rawset into
    -- the instance's environment (M._G, made after build), so the name is read there first, as the
    -- client reads its one global table.
    M.GetBindingName = function(command)
        local env = rawget(M, "_G")
        local v = type(env) == "table" and rawget(env, "BINDING_NAME_" .. tostring(command)) or nil
        if v ~= nil then return v end
        return command
    end
    installBindings(M)

    return M
end

return { build = build }
