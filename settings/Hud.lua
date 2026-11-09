local _, NS = ...
-- settings/Hud.lua — the DPS HUD page, registered in its place in the panel's order (General, Lanes,
-- DPS HUD, History, Profiles). Plan Task 3.3 fills it with the Behavior, Layout,
-- Clock and figures, Damage chart, Spell rows and Window tabs (spec §6); until then its one tab says so.

local L = NS.L
local PAGE = "hud"

NS.RegisterTabbedPage({
    key             = PAGE,
    title           = L["DPS HUD"],
    panelName       = "CombatTrailHudPanel",
    defaultsTooltip = L["Restore every DPS HUD setting on this profile to its addon default."],
    -- The placeholder tab: a page with no group and no host tab is an authoring defect the renderer
    -- reports (options-ui-§13). Plan Task 3.3 replaces it with the page's schema tabs.
    tabs            = { {
        key = L["DPS HUD"], label = L["DPS HUD"],
        render = function(ctx) NS.Helpers.TextRow(ctx, L["The DPS HUD settings arrive with the HUD."]) end,
    } },
})
