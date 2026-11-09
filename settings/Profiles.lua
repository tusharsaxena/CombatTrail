local _, NS = ...
-- settings/Profiles.lua — the Profiles sub-page: AceDBOptions' own table, drawn by AceConfigDialog into
-- the library's panel. One of the two untabbed pages (options-ui-§13).

local L = NS.L
local PAGE = "profiles"
local APP = "CombatTrail-Profiles"

local function build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then return nil end
    if not LibStub then return nil end
    local H = NS.Helpers
    if not (H and H.CreatePanel) then return nil end
    local AceDBOptions    = LibStub("AceDBOptions-3.0", true)
    local AceConfig       = LibStub("AceConfig-3.0", true)
    local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
    local AceGUI          = NS.AceGUI or LibStub("AceGUI-3.0", true)
    if not (AceDBOptions and AceConfig and AceConfigDialog and AceGUI) then return nil end
    if not (NS.db and NS.db.profile) then return nil end

    AceConfig:RegisterOptionsTable(APP, AceDBOptions:GetOptionsTable(NS.db))
    -- No Defaults button: a profile page has no defaults of its own to restore.
    local ctx = H.CreatePanel("CombatTrailProfilesPanel", L["Profiles"], {
        pageKey        = PAGE,
        defaultsButton = false,
    })
    -- One container for the panel's life, parented onto the library's body (never onto an AceGUI
    -- widget's own frame -- options-ui-§19).
    local container = AceGUI:Create("SimpleGroup")
    container:SetLayout("Fill")
    container.frame:SetParent(ctx.body)
    container.frame:ClearAllPoints()
    container.frame:SetPoint("TOPLEFT", ctx.body, "TOPLEFT", 8, -8)
    container.frame:SetPoint("BOTTOMRIGHT", ctx.body, "BOTTOMRIGHT", -8, 8)
    -- AceConfigDialog acquires the manager's widgets from AceGUI itself, past the Options instance's
    -- owner proxy, so the tree is painted for this addon's skin right after it is drawn (skinning-§3;
    -- nothing while the settings panel is left the client's). Each widget goes back to the shared
    -- pool stock when the next Open releases it, and a skin switch re-renders the page.
    H.SetRenderer(ctx, function()
        container.frame:Show()
        AceConfigDialog:Open(APP, container)
        NS.SkinPaintAceTree(container)
    end)
    return Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, L["Profiles"])
end

NS.RegisterOptionsPage(PAGE, L["Profiles"], build)
