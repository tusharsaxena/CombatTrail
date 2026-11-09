local _, NS = ...
-- settings/Lanes.lua — the Lanes page, registered in its place in the panel's order (General, Lanes,
-- DPS HUD, History, Profiles). Plan Task 1.4 fills it with the lane dropdown and
-- its seven tabs (spec §4); until then its one tab says so.

local L = NS.L
local PAGE = "lanes"

NS.RegisterTabbedPage({
    key             = PAGE,
    title           = L["Lanes"],
    panelName       = "CombatTrailLanesPanel",
    defaultsTooltip = L["Restore every Lanes setting on this profile to its addon default."],
    -- The placeholder tab: a page with no group and no host tab is an authoring defect the renderer
    -- reports (options-ui-§13). Plan Task 1.4 replaces it with the page's schema tabs.
    tabs            = { {
        key = L["Lanes"], label = L["Lanes"],
        render = function(ctx) NS.Helpers.TextRow(ctx, L["The lane settings arrive with the lanes."]) end,
    } },
})
