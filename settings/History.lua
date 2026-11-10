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

-- The Usage "never show" list (modules/Usage.lua, spec §7): one plain string of item IDs, written whole
-- through the seam by Usage.Hide and Usage.Unhide (the Results detail's right-click in its Usage edit).
-- Global, as the fight store it filters is. Drawn by nothing yet (skipRender): plan Task 4.5 moves it to
-- the page's Usage tab and draws it there as the library's ID list.
NS.RegisterSchemaRows({
    { path = NS.Usage.HIDDEN_PATH, page = PAGE, group = L["History"], type = "string", skipRender = true,
      label = L["Hidden items"], default = NS.defaults.global.usage.hidden,
      validate = function(v) return NS.Usage.ParseHidden(v) ~= nil end,
      normalize = function(v) return NS.Usage.NormalizeHidden(v) end,
      tooltip = L["Account-wide: shared by every profile. Item IDs, comma-separated, that the Results window's Usage never lists, on any fight. A fight that used one still records it, so taking it off the list brings it back."] },
})
