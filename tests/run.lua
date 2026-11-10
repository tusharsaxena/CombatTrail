-- tests/run.lua — this addon's load list, lifecycle kick and suite list, on the vendored kit
-- (testing-§1). Run from the repo root: `lua tests/run.lua` (`--list` writes docs/test-cases.md),
-- and `KA0S_KIT_CLIENT=forever lua tests/run.lua` for the WoW Forever profile (clients-§6).

local root = (arg and arg[0] and arg[0]:match("^(.*)/tests/run%.lua$")) or "."
package.path = root .. "/tests/?.lua;" .. package.path

local Kit     = dofile(root .. "/tests/_kit/framework.lua")
local Loader  = dofile(root .. "/tests/_kit/loader.lua")
local mockmod = assert(loadfile(root .. "/tests/wow_mock.lua"))(root)
-- The scripted C_DamageMeter, built on the kit's secret wrappers (`/kct probe` and the meter adapter).
local MockMeter = dofile(root .. "/tests/mock_meter.lua")(Kit)

Loader.addonName = "CombatTrail"

-- The vendored library's files, read out of LibKa0s.xml in its own order rather than remembered:
-- omit one and its module refuses to register, the host takes its stub, and the suite measures the
-- stub -- green, and testing nothing (testing-§9). The floor list below fails loudly if the .xml
-- ever stops naming a module this addon consumes.
local LIB_FILES = Loader.xmlFiles(root .. "/libs/LibKa0s/LibKa0s.xml")
do
    local EXPECTED = {
        "Core.lua", "CorePixel.lua", "Compat.lua", "Env.lua", "Lifecycle.lua", "Bus.lua", "Schema.lua",
        "Pool.lua", "Media.lua", "Widgets.lua", "WidgetsDropdown.lua", "DebugLog.lua",
        "DebugLogDiagnostics.lua", "DebugLogGates.lua", "Slash.lua", "SlashParse.lua", "Launcher.lua",
        "Options.lua", "OptionsRegistry.lua", "OptionsWidgets.lua", "OptionsFlow.lua", "OptionsTabs.lua",
        "OptionsTabbed.lua", "OptionsCombat.lua", "OptionsCompose.lua", "OptionsScroll.lua",
        "OptionsKeybinds.lua", "Perf.lua", "PerfSampler.lua", "PerfCommands.lua", "PerfPanel.lua",
        "Sim.lua", "OptionsAppearance.lua", "OptionsSkinPicker.lua", "OptionsSkinPickerRows.lua",
        "OptionsSwitch.lua", "OptionsMedia.lua",
        -- The skin engine core/SkinSetup.lua registers the owner with (skinning-§1).
        "Skin.lua", "SkinOwnerTokens.lua", "SkinDefs.lua", "SkinDefsOthers.lua", "SkinPaint.lua",
        "SkinPaintExtras.lua", "SkinPaintHud.lua", "SkinAceConfirm.lua", "SkinPaintControls.lua",
        "SkinEUI.lua", "SkinAce.lua",
    }
    local present = {}
    for _, path in ipairs(LIB_FILES) do present[path:match("([^/]+)$")] = true end
    local missing = {}
    for _, name in ipairs(EXPECTED) do
        if not present[name] then missing[#missing + 1] = name end
    end
    assert(#missing == 0, "libs/LibKa0s/LibKa0s.xml is missing " .. table.concat(missing, ", "))
end

-- The addon's own files come from the TOC, so this runner cannot drift from what the client loads.
local ADDON_FILES = Loader.tocFiles(root .. "/CombatTrail.toc")

local function rooted(list)
    local out = {}
    for i, rel in ipairs(list) do out[i] = root .. "/" .. rel end
    return out
end

-- THE SKIN LIBRARY'S LOGIN RETRY, SETTLED AS THE CLIENT SETTLES IT. The first RegisterOwner
-- (core/SkinSetup.lua) makes LibKa0s-Skin-1.0's EllesmereUI retry frame, registered for ADDON_LOADED
-- and PLAYER_LOGIN; the client fires PLAYER_LOGIN once, beside OnEnable, and the frame unregisters
-- both. Delivering it there puts the frame where every real session has it.
local function settleSkinLogin(mocks)
    local skinLib = mocks.LibStub("LibKa0s-Skin-1.0", true)
    local retry = skinLib and skinLib.__euiEventFrame
    if retry and retry.__fire then retry:__fire("OnEvent", "PLAYER_LOGIN") end
end

--- One isolated instance: a fresh mock, a fresh NS, the client's lifecycle.
---   opts.libFiles  the LibKa0s files to load ({} = the library-absent load)
---   opts.mutate    function(mocks) run before anything loads
---   opts.init      false = load the files only (no OnInitialize)
---   opts.enable    false = initialize but do not enable
local function loadInstance(opts)
    opts = opts or {}
    local mocks = mockmod.build()
    if opts.mutate then opts.mutate(mocks) end
    -- `_G` inside a loaded chunk is the mocked environment, as in the client it is the one global table.
    mocks._G = Loader.makeEnv(mocks)
    _G.CombatTrailDB, _G.CombatTrailPerfDB = nil, nil
    local NS = {}
    Loader.loadAll(opts.libFiles or LIB_FILES, NS, mocks)
    Loader.loadAll(rooted(ADDON_FILES), NS, mocks)
    if opts.init ~= false then
        local AceAddon = mocks.LibStub("AceAddon-3.0")
        AceAddon:InitializeAddon(NS)                 -- OnInitialize: DB, migrations, latch
        if opts.enable ~= false then
            settleSkinLogin(mocks)                   -- PLAYER_LOGIN, to the skin's retry frame
            AceAddon:EnableAddon(NS)                 -- OnEnable: the game events
            if mocks.__fireTimers then mocks.__fireTimers() end
        end
    end
    return { NS = NS, mocks = mocks }
end

local shared = loadInstance()

local SUITES = {
    "test_load",
    "test_loadorder",
    "test_vendor_sync",
    "test_settings",
    "test_slash",
    "test_lane_casts",
    "test_lane_layout",
    "test_lane_render",
    "test_lane_anchor",
    "test_lane_visibility",
    "test_lanes_page",
    "test_probe",
    "test_meter",
    "test_fight",
    "test_identity",
    "test_cast_codec",
    "test_casts",
    "test_usage",
    "test_stats",
    "test_loadouts",
    { name = "test_eol", dir = "tests/_kit/" },
    { name = "test_prose", dir = "tests/_kit/" },
    { name = "test_layout_cap", dir = "tests/_kit/" },
    { name = "test_lizard_sighted", dir = "tests/_kit/" },
    { name = "test_client_globals", dir = "tests/_kit/" },
    -- The diagnostics contract, against this addon's dispatcher (Kit.diagnostics below). The skin
    -- switch is a declared skip until a surface of this addon's own is painted (milestones 1 to 4).
    { name = "test_diagnostics_contract", dir = "tests/_kit/" },
    { name = "test_skin_switch", dir = "tests/_kit/" },
    { name = "test_skin_values", dir = "tests/_kit/" },
}

_G.CT_TEST = Kit.expose{
    root             = root,
    NS               = shared.NS,
    mocks            = shared.mocks,
    load             = loadInstance,
    libFiles         = LIB_FILES,
    loadedAddonFiles = ADDON_FILES,
    Loader           = Loader,
    secret           = Kit.secret,
    isSecret         = Kit.isSecret,
    reveal           = Kit.reveal,
    installSecretValue = Kit.installSecretValue,
    mockMeter        = MockMeter,
}

-- The diagnostics contract runs against THIS addon's dispatcher (debug-logging-§14).
local contractInst
local function contract()
    contractInst = contractInst or loadInstance()
    return contractInst
end
Kit.diagnostics = {
    brand       = "Ka0s Combat Trail",
    dispatch    = function(line) contract().NS.Slash:OnSlash(line) end,
    console     = function() return contract().NS.DebugLog end,
    setDebug    = function(on) contract().NS.State.debug = on and true or false end,
    setDisabled = function(off) contract().NS.SetByPath("general.enabled", not off) end,
}

-- The typed-value gate (skinning-§1): no row of this addon's own yet, so every color, face and texture
-- in the tracked source is one a kit category takes.
Kit.skinValues = { root = root, rows = {} }

Kit.run{ dir = root .. "/tests/", suites = SUITES }
