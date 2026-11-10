local addonName, NS = ...
-- settings/General.lua — the General page: `Master controls` first (options-ui-§15), then `Look and
-- skin` (the library's Skin tab with the global font scale under it, skinning-§3), and `Keybindings`
-- last (options-ui-§20, its rows NS.BINDINGS, core/LauncherSetup.lua's); and the landing page's
-- spec, NS.LANDING (options-ui-§5).

local L = NS.L
local H = NS.Helpers
local D = NS.defaults.profile
local PAGE = "general"

-- ── The landing page ────────────────────────────────────────────────────────────────────────────
-- Logo, tagline and the command list; the library draws all three pool-safely (options-ui-§19).
NS.LANDING = {
    logo     = NS.Constants.LOGO,
    notes    = function() return NS.Meta("Notes") or "" end,
    sections = { {
        heading = L["Slash Commands"],
        rows    = function() return NS.Slash:LandingRows() end,   -- from NS.COMMANDS
    } },
}

-- ── The global reset ────────────────────────────────────────────────────────────────────────────
-- options-ui-§12's one wording, verbatim. The fight history is account-wide (db.global), so a profile
-- reset never reaches it; the profile is all the popup speaks of.
StaticPopupDialogs["COMBATTRAIL_RESET_ALL"] = {
    text         = L["Reset this profile to the addon's defaults? Everything you have configured or added in it is discarded — your other profiles are not affected."],
    button1      = L["Yes"],
    button2      = L["No"],
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept     = function()
        NS.Helpers.RestoreAllDefaults()
        NS.Print(L["All settings reset to defaults."])
    end,
}

--- `Reset all settings` and `/kct resetall` both ask first, through this one popup.
function NS.ShowResetAll()
    return StaticPopup_Show("COMBATTRAIL_RESET_ALL")
end

-- ── Master controls ─────────────────────────────────────────────────────────────────────────────
-- Composed from ONE declaration, the canonical rows in canonical order (options-ui-§15), under the
-- `general.` prefix. No General visibility, Master scale or Master opacity: the lanes and the HUD each
-- carry their own (spec §4, §6). The session rows (debug console, test mode, sim mode) take their
-- paths verbatim under `general.` too, so `/kct list` shows Master controls as one group.
local G = D.general
local DEBUG_CONSOLE_PATH = "general.debugConsole"
local TEST_MODE_PATH = "general.testMode"
local SIM_MODE_PATH = "general.simMode"

local masterRows, masterTail = H.MasterControls({
    page             = PAGE,
    prefix           = "general.",
    addonName        = NS.BRAND,          -- the Enable row reads "Enable Ka0s Combat Trail"
    omit             = { visibility = true, scale = true, alpha = true },
    debugConsolePath = DEBUG_CONSOLE_PATH,
    minimapPath      = NS.MINIMAP_PATH,
    testModePath     = TEST_MODE_PATH,
    -- Sim mode beside Test mode (LibKa0s compose minor 19): the launcher's own pair, so the box, the
    -- launcher's Sim mode entry and `/kct sim` are one act. The row's get / set are its own.
    simPath          = SIM_MODE_PATH,
    isSimMode        = function() return NS.IsSimMode() end,
    toggleSim        = function() return NS.ToggleSim() end,
    defaults         = { enabled = G.enabled, locked = G.locked },
    notes            = {
        testMode = L["It fills the lanes, the HUD and the Results window with sample data."],
    },
    resetPositionTooltip = L["Move the lanes, the DPS HUD and the Results window back to where they started."],
    onResetPosition  = function() NS.ResetPositions() end,
    onResetAll       = function() NS.ShowResetAll() end,
    -- The addon's own rows on this tab, after the canonical block (options-ui-§16: never interleaved).
    extra            = {
        { path = "general.hudInCombat", type = "bool", startsLine = true,
          label = L["Show DPS HUD in combat"], default = G.hudInCombat,
          tooltip = L["Open the DPS HUD whenever you enter combat. Off, it opens only when you show it."],
          onChange = function(v) NS.OnHudInCombatChanged(v) end },
        { path = "general.debug", type = "bool", sessionOnly = true, default = false,
          label = L["Debug logging"],
          tooltip = L["Write this session's developer log to the debug console. A reload turns it off."] },
    },
})

-- Rows whose storage is not a profile path: the console (session), test mode and debug logging
-- (session), and the minimap button (LibDBIcon's own `hide`, inverted -- launcher-§3).
local ownStorage = {
    [NS.MINIMAP_PATH] = {
        get = function() return NS.Launcher:IsShown() end,
        set = function(shown) NS.Launcher:SetShown(shown and true or false) end,
    },
    [TEST_MODE_PATH] = {
        get = function() return NS.IsTestMode() end,
        set = function(on) NS.SetTestMode(on) end,
    },
    ["general.debug"] = {
        get = function() return NS.DebugLog:IsEnabled() == true end,
        set = function(on)
            if (on and true or false) ~= (NS.DebugLog:IsEnabled() == true) then NS.DebugLog:SetEnabled(on and true or false) end
        end,
    },
}
do
    local console = NS.DebugLog:ConsoleCheckbox()
    ownStorage[DEBUG_CONSOLE_PATH] = { get = console.get, set = console.set }
end

-- Each composed row's reaction, attached here because the composer cannot know them.
local reactions = {
    ["general.enabled"] = function(v) NS.ApplyEnabled(v) end,
    ["general.locked"]  = function(v) NS.ApplyLocked(v) end,
}

for _, row in ipairs(masterRows) do
    row.onChange = reactions[row.path] or row.onChange
    local own = ownStorage[row.path]
    if own then row.get, row.set = own.get, own.set end
    -- options-ui-§15: Test mode "is ended by Reset all settings (the row declares default = false)".
    -- The composer emits the row without one, so the reset's session-row walk would skip it; the
    -- host stamps it here.
    if row.path == TEST_MODE_PATH and row.default == nil then row.default = false end
end
NS.RegisterSchemaRows(masterRows)

-- ── Look and skin ── (skinning-§2/§3, core/SkinSetup.lua) the skin this addon wears, per profile. The
-- tab is the library's O.AppearanceTab, relabeled, which draws every `skin.*` row below itself (its
-- choice grids, the Scope's check boxes, the Font and texture dropdowns), so each carries
-- `skipRender`; they stay schema rows so the defaults resolve, every reset reaches them, and
-- `/kct get|set skin.skin` validates against `values`. The global font is the tab's Font dropdown
-- (`skin.font`). The global font scale is this addon's own row, drawn under the library's controls.
--
-- Each onChange applies ONLY its own half (core/SkinSetup.lua says why): the tab and another addon's
-- "Copy to every Ka0s addon" call Skin:SetChoice before they write, so the write is a no-op, and a
-- bare `/kct set` still repaints.
local SKIN = NS.SKIN_TAB_KEY
local SKIN_SPEC = {
    owner = addonName, get = NS.SkinChoice, set = NS.WriteSkinChoice, key = SKIN,
    strings = { TAB_LABEL = L["Look and skin"] },
}
local SKIN_TAB = H.AppearanceTab(SKIN_SPEC)
local SD = D.skin

--- A validator for a row whose value is one of `options`' values.
local function oneOf(options)
    return function(v)
        for _, o in ipairs(options) do if o.value == v then return true end end
        return false
    end
end

NS.RegisterSchemaRows({
    { path = "skin.source", page = PAGE, group = SKIN, type = "string", skipRender = true,
      label = L["Skin source"], default = SD.source, values = NS.SKIN_SOURCE_OPTIONS,
      validate = oneOf(NS.SKIN_SOURCE_OPTIONS),
      tooltip = L["Where this addon's look comes from: the Ka0s skin chosen below, or EllesmereUI."],
      onChange = function(v) NS.ApplySkinChoice(v, nil) end },
    { path = "skin.skin", page = PAGE, group = SKIN, type = "string", skipRender = true,
      label = L["Skin"], default = SD.skin, values = NS.SKIN_OPTIONS, validate = oneOf(NS.SKIN_OPTIONS),
      tooltip = L["The Ka0s skin this addon wears. Changes every window and panel right away."],
      onChange = function(v) NS.ApplySkinChoice(nil, v) end },
    -- The Scope's two exceptions (LibKa0s-Skin-1.0 minor 5).
    { path = "skin.ignorePanel", page = PAGE, group = SKIN, type = "bool", skipRender = true,
      label = L["Ignore settings panel"], default = SD.ignorePanel,
      tooltip = L["Keep this addon's settings panel in the game's own look. Its windows still wear the skin."],
      onChange = function(v) NS.ApplySkinIgnore(v, nil) end },
    { path = "skin.ignoreFonts", page = PAGE, group = SKIN, type = "bool", skipRender = true,
      label = L["Ignore fonts"], default = SD.ignoreFonts,
      tooltip = L["Keep every font in this addon as the game draws it. The skin still colors the text."],
      onChange = function(v) NS.ApplySkinIgnore(nil, v) end },
    -- The Font and texture overrides (LibKa0s-Skin-1.0 minor 6): free text, not a list of `values`,
    -- because a media pack may register its keys after this file loads and `/kct set` takes any key;
    -- "" is the skin's own.
    { path = "skin.font", page = PAGE, group = SKIN, type = "string", skipRender = true,
      label = L["Font"], default = SD.font,
      tooltip = L["The font this addon's text uses, over the skin's own. Empty keeps the skin's."],
      onChange = function(v) NS.ApplySkinOverride(v, nil) end },
    { path = "skin.texture", page = PAGE, group = SKIN, type = "string", skipRender = true,
      label = L["Texture"], default = SD.texture,
      tooltip = L["The texture this addon's bars use, over the skin's own. Empty keeps the skin's."],
      onChange = function(v) NS.ApplySkinOverride(nil, v) end },
    -- The Font outline (LibKa0s-Skin-1.0 minor 9, ruling D-06), drawn by the tab as its "Font outline"
    -- dropdown. The library's three modes, in its order, so `/kct set skin.outline` validates them.
    { path = "skin.outline", page = PAGE, group = SKIN, type = "string", skipRender = true,
      label = L["Font outline"], default = SD.outline, values = NS.SKIN_OUTLINE_OPTIONS,
      validate = oneOf(NS.SKIN_OUTLINE_OPTIONS),
      tooltip = L["Where the skin outlines this addon's text: all of it, its HUD text only, or nowhere."],
      onChange = function(v) NS.ApplySkinOutline(v) end },
    -- The first-run skin picker's memory: set when the picker closes, so it shows once per profile.
    -- Drawn by nothing; a reset puts it back to false.
    { path = "skin.pickerSeen", page = PAGE, group = SKIN, type = "bool", skipRender = true,
      label = L["Skin picker seen"], default = SD.pickerSeen,
      tooltip = L["Whether the first-run skin picker was closed on this profile."] },
    -- The global font scale: every text this addon draws, on top of each element's own size. Drawn
    -- under the library's controls by the tab's render below. Readers redraw off SETTINGS_CHANGED.
    { path = "general.fontScale", page = PAGE, group = SKIN, type = "number", startsLine = true,
      label = L["Global font scale"], default = G.fontScale, min = 0.5, max = 1.5, step = 0.05,
      isPercent = true,
      tooltip = L["Scales every text in the lanes, the DPS HUD and the Results window, on top of each element's own size."] },
})

-- The tab keyed by the skin rows' group takes that group's place in the strip and is handed its rows
-- (RenderTabbedSchema's host tab): the library's controls first, then the drawable rows the library
-- does not draw, which is the font scale.
local LOOK_TAB = {
    key = SKIN, label = SKIN_TAB.label, tooltip = SKIN_TAB.tooltip,
    render = function(ctx, rows)
        H.AppearanceRows(ctx, SKIN_SPEC)
        local own = {}
        for _, r in ipairs(rows or {}) do
            if not r.skipRender then own[#own + 1] = r end
        end
        if #own > 0 then H.RenderRows(ctx, own, nil, nil, { noHeadings = true }) end
    end,
}

-- The page's host tabs, in strip order: Look and skin in its group's place, Keybindings last
-- (options-ui-§20), drawn from NS.BINDINGS (core/LauncherSetup.lua, Bindings.xml's order).
NS.GENERAL_TABS = { LOOK_TAB, H.KeybindingsTab({ bindings = NS.BINDINGS }) }

-- ── The page ────────────────────────────────────────────────────────────────────────────────────
local function build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then return nil end
    local ctx = H.CreatePanel("CombatTrailGeneralPanel", L["General"], {
        pageKey         = PAGE,
        defaultsButton  = true,
        -- A page reset (options-ui-§13). Defaults never reaches a key: the game keeps them, not the
        -- profile (options-ui-§20).
        defaultsTooltip = L["Restore every General setting on this profile to its addon default: Master controls and the look and skin."]
            .. " " .. H.KEYBINDS_UNCHANGED,
    })
    ctx.panel.defaultsOnClick = function() H.RestoreDefaults(PAGE, ctx) end
    -- Every page renders through the tabbed renderer, a one-tab page included (options-ui-§13).
    H.SetRenderer(ctx, function(c)
        H.ClearScroll(c)
        H.RenderTabbedSchema(c, PAGE, { [H.MASTER_GROUP] = masterTail }, nil, { tabs = NS.GENERAL_TABS })
    end)
    return Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, L["General"])
end

NS.RegisterOptionsPage(PAGE, L["General"], build)
