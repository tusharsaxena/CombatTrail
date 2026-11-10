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

    -- A unit's GUID (`/kct probe` asks the meter for the player's and the pet's sources by GUID). The
    -- scripted meter (tests/mock_meter.lua) answers its own player and pet GUIDs over this one.
    M.__unitGUIDs = { player = "Player-1-00000001" }
    M.UnitGUID = function(unit) return M.__unitGUIDs[unit] end

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

    -- Where the player is and what against (modules/Identity.lua). GetInstanceInfo answers the
    -- client's ten values out of M.__instance; a test sets its fields. The open world by default.
    M.__instance = { name = "Isle of Dorn", type = "none", difficultyID = 0, difficultyName = "",
                     maxPlayers = 0, instanceID = 2552 }
    M.GetInstanceInfo = function()
        local i = M.__instance
        return i.name, i.type, i.difficultyID, i.difficultyName, i.maxPlayers, 0, false, i.instanceID,
               i.groupSize, i.lfgID
    end
    M.__difficulties = { [1] = "Normal", [8] = "Mythic Keystone", [15] = "Heroic", [16] = "Mythic",
                         [208] = "Delves" }
    M.GetDifficultyInfo = function(id) return M.__difficulties[id] end
    -- The Mythic+ keystone level (C_ChallengeMode.GetActiveKeystoneInfo's first value), nil when none.
    M.__keystone = nil
    M.C_ChallengeMode = { GetActiveKeystoneInfo = function() return M.__keystone, {}, false end }
    -- A delve's tier, as the client's objective-tracker widget shows it: one ScenarioHeaderDelves
    -- widget whose tierText is M.__delveTier (nil: no widget).
    M.__delveTier = nil
    M.C_UIWidgetManager = {
        GetObjectiveTrackerWidgetSetID = function() return 252 end,
        GetAllWidgetsBySetID = function(setID)
            if setID ~= 252 or M.__delveTier == nil then return {} end
            return { { widgetID = 6183, widgetType = 29 } }
        end,
        GetScenarioHeaderDelvesWidgetVisualizationInfo = function(widgetID)
            if widgetID ~= 6183 or M.__delveTier == nil then return nil end
            return { tierText = M.__delveTier }
        end,
    }
    -- The PvP match's rules (the bracket qualifier): each false until a test sets it.
    M.__pvp = { ratedBG = false, ratedArena = false, soloShuffle = false, blitz = false }
    M.C_PvP = {
        IsRatedBattleground = function() return M.__pvp.ratedBG end,
        IsRatedArena        = function() return M.__pvp.ratedArena end,
        IsSoloShuffle       = function() return M.__pvp.soloShuffle end,
        IsRatedSoloRBG      = function() return M.__pvp.blitz end,
    }
    -- A unit's classification ("normal", "elite", "worldboss", ...) and a pet's family.
    M.__classifications, M.__families = {}, {}
    M.UnitClassification = function(unit) return M.__classifications[unit] end
    M.UnitCreatureFamily = function(unit) return M.__families[unit] end
    -- The player's item level: overall, then equipped.
    M.__ilvl = { overall = 640.25, equipped = 638.96 }
    M.GetAverageItemLevel = function() return M.__ilvl.overall, M.__ilvl.equipped end

    -- The gear and the talents a fight was fought with (modules/Loadouts.lua): the equipped links by
    -- slot and the talent APIs over one settable table (DPS Race's fakes). A case edits M.__gear or
    -- M.__talents before the snapshot; nil = an empty slot, or no active config.
    M.__gear = {
        [1] = "|cnIQ4:|Hitem:212001::::::::80:267::6:2:10390:1540::::::|h[Hood of the Test]|h|r",
        [5] = "|cnIQ4:|Hitem:212005::::::::80:267::6:2:10390:1540::::::|h[Robe of the Test]|h|r",
        [16] = "|cnIQ3:|Hitem:212016::::::::80:267::6:1:10390::::::|h[Staff of the Test]|h|r",
        [4] = "|cnIQ1:|Hitem:6833::::::::80:267::::::::|h[White Tuxedo Shirt]|h|r",
    }
    M.GetInventoryItemLink = function(unit, slot)
        if unit ~= "player" then return nil end
        return M.__gear[slot]
    end
    M.__talents = {
        configID = 7001, savedConfigID = 7002, configName = "Active", savedName = "Raid ST",
        heroSpecID = 58, heroName = "Diabolist", importString = "C0PAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    }
    M.C_ClassTalents = {
        GetActiveConfigID = function() return M.__talents and M.__talents.configID end,
        GetLastSelectedSavedConfigID = function() return M.__talents and M.__talents.savedConfigID end,
        GetActiveHeroTalentSpec = function() return M.__talents and M.__talents.heroSpecID end,
    }
    M.C_Traits = {
        GetConfigInfo = function(id)
            local t = M.__talents
            if not t then return nil end
            if id == t.savedConfigID and t.savedName then return { ID = id, name = t.savedName } end
            if id == t.configID then return { ID = id, name = t.configName } end
            return nil
        end,
        GetSubTreeInfo = function(_, id)
            local t = M.__talents
            return t and id == t.heroSpecID and { ID = id, name = t.heroName } or nil
        end,
        GenerateImportString = function(id)
            local t = M.__talents
            return t and id == t.configID and t.importString or nil
        end,
    }

    -- What a fight used (modules/Usage.lua): the on-use slots (the item ID out of M.__gear's link),
    -- the item data, the bags and the helpful auras. Empty by default; a case fills them:
    --   M.__itemSpells  [itemID] = its use spell ID
    --   M.__itemInfo    [itemID] = { classID, subclassID }
    --   M.__bags        [bag] = { size = n, [slot] = { itemID, stackCount } }
    --   M.__auras       { { spellId, name }, ... }, the player's helpful auras in order
    M.__itemSpells, M.__itemInfo, M.__bags, M.__auras = {}, {}, {}, {}
    M.__itemCalls = 0
    M.GetInventoryItemID = function(unit, slot)
        local link = M.GetInventoryItemLink(unit, slot)
        return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    end
    M.C_Item = {
        GetItemSpell = function(itemID)
            local id = M.__itemSpells[itemID]
            if id then return "Spell " .. id, id end
            return nil
        end,
        GetItemInfoInstant = function(itemID)
            M.__itemCalls = M.__itemCalls + 1
            local i = M.__itemInfo[itemID]
            if not i then return nil end
            return itemID, "Consumable", "Consumable", "", 134400, i[1], i[2]
        end,
    }
    M.C_Container = {
        GetContainerNumSlots = function(bag)
            local b = M.__bags[bag]
            return b and b.size or 0
        end,
        GetContainerItemInfo = function(bag, slot)
            local b = M.__bags[bag]
            local s = b and b[slot]
            if not s then return nil end
            return { itemID = s[1], stackCount = s[2] }
        end,
    }
    M.C_UnitAuras = {
        GetAuraDataByIndex = function(unit, i, filter)
            if unit ~= "player" or filter ~= "HELPFUL" then return nil end
            local a = M.__auras[i]
            return a and { spellId = a[1], name = a[2] } or nil
        end,
    }

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
