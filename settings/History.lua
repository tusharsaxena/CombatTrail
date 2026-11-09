local _, NS = ...
-- settings/History.lua — the History page, registered in its place in the panel's order (General, Lanes,
-- DPS HUD, History, Profiles). Plan Task 4.5 fills it with the Recording filters,
-- Retention, Results window and Usage tabs (spec §5, §7); until then its one tab says so.

local L = NS.L
local PAGE = "history"

NS.RegisterTabbedPage({
    key             = PAGE,
    title           = L["History"],
    panelName       = "CombatTrailHistoryPanel",
    defaultsTooltip = L["Restore every History setting on this profile to its addon default. Stored fights are not touched."],
    -- The placeholder tab: a page with no group and no host tab is an authoring defect the renderer
    -- reports (options-ui-§13). Plan Task 4.5 replaces it with the page's schema tabs.
    tabs            = { {
        key = L["History"], label = L["History"],
        render = function(ctx) NS.Helpers.TextRow(ctx, L["The History settings arrive with the fight history."]) end,
    } },
})
