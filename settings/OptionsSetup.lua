local addonName, NS = ...
-- settings/OptionsSetup.lua — the LibKa0s-Options-1.0 descriptor; NS.Helpers IS the library instance.

--- Named ONCE and enforced twice -- by the library through skipRestoreAll, and by the stub's reset.
--- The global reset IS a profile reset (options-ui-§12), so the walk keeps only what a profile reset
--- cannot reach: the session rows, whose storage is their own set(). The Minimap row is vetoed out of
--- every reset (launcher-§3).
local function vetoedFromResetAll(row)
    if row.page == "profiles" or row.path == NS.MINIMAP_PATH then return true end
    return not row.sessionOnly
end

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)

local descriptor = {
    parentTitle   = NS.BRAND,
    mainPanelName = "CombatTrailMainPanel",
    -- The FOLDER name, never a display label: the route to the library's own art (options-ui-§1).
    addonName     = addonName,

    get          = function(path) return NS.GetSetting(path) end,
    set          = function(path, value) return NS.SetByPath(path, value) end,   -- the single write seam
    applyDefault = function(row) return NS.ApplyDefault(row) end,
    allRows      = function() return NS.Schema end,
    -- The Lanes page leaves a linked Pet lane's mirrored rows off its tabs (LanesPage.ShownRows).
    rowsForPage  = function(pageKey, filter)
        local rows = NS.SchemaForPage(pageKey, filter)
        local page = NS.LanesPage
        if page and page.ShownRows then rows = page.ShownRows(pageKey, filter, rows) end
        return rows
    end,

    skipRestoreAll = vetoedFromResetAll,
    resetProfile   = function()
        local db = NS.db
        if not (db and db.ResetProfile) then return false end
        db:ResetProfile()
        return true
    end,
    profilesPage = true,
    bulkBegin = function(act, scope) NS.Bulk.Begin(act, scope) end,
    bulkEnd   = function(act, scope, count, err, info) NS.Bulk.End(act, scope, count, err, info) end,

    colorDecode = function(c)
        c = type(c) == "table" and c or {}
        return c.r or 1, c.g or 1, c.b or 1, c.a or 1
    end,
    colorEncode = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end,

    -- The landing body is the LIBRARY's (options-ui-§5, §19): NS.LANDING is declared in
    -- settings/General.lua and read at render time.
    buildMain     = function(ctx) NS.Helpers.BuildLandingPage(ctx, NS.LANDING) end,
    getLSM        = function() return LibStub and LibStub("LibSharedMedia-3.0", true) end,
    -- C_Timer.After, NOT the addon's AceTimer: stand-down's CancelAllTimers would cancel a pending
    -- drag-throttle callback, leaving the widget's own `armed` flag stuck true until /reload. The
    -- panel stays live while disabled; the library keeps its own flag and ignores the return.
    scheduleTimer = function(fn, delay) C_Timer.After(delay, fn) end,
    validate      = function() NS.ValidateSchema() end,
    onAceGUI      = function(AceGUI) NS.AceGUI = AceGUI end,
    print         = function(line) NS.Print(line) end,
    -- The combat lock's refusals are the library's `Cfg` lines (debug-logging-§4).
    debug         = function(tag, fmt, ...) NS.Debug(tag, fmt, ...) end,
}

--- One schema page (Lanes, DPS HUD, History): its panel, its page-wide Defaults button, and every
--- render through the tabbed renderer, a one-tab page included (options-ui-§13). Everything here is
--- resolved at CALL time, so it serves the library-absent load too, where NS.RegisterOptionsPage is
--- the stub's no-op.
--- `redrawOnDefaults` is for a page with a row a selector on another tab switches: its Defaults can
--- change what the tab on screen draws, and the library watches only the selectors a render drew
--- (options-ui-§22). The redraw answers the page's own reset, as the global reset's does; it is no
--- selector's `onChange`, so the switching itself stays the library's.
--- `tabs` are host tabs the strip draws by their own render (RenderTabbedSchema's `opts.tabs`): the
--- one a page has before its rows arrive, and any bespoke tab after.
--- A page that edits one instance out of many (the Lanes page, options-ui-§14) passes `unit`, a
--- function answering the selected instance, which every render hands the rows filter as the ctx's
--- `unit`, and `banner(ctx)`, which draws the band's picker before the strip, on every render a tab
--- click included. `afterDefaults()` runs after the page's Defaults, for what no row holds.
--- `clients` declares a page one client has (clients-§4, the Race mode page's `{ "retail" }`): the
--- library never queues it on another, so its builder never runs there.
--- @param spec table { key, title, panelName, defaultsTooltip, afterGroup?, beforeGroup?, tabs?, redrawOnDefaults?, unit?, banner?, afterDefaults?, clients? }
NS.pageCtx = NS.pageCtx or {}   -- each built page's ctx, by key, for a page that repaints off the bus
function NS.RegisterTabbedPage(spec)
    NS.RegisterOptionsPage(spec.key, spec.title, function(mainCategory)
        if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then return nil end
        local H = NS.Helpers
        local ctx = H.CreatePanel(spec.panelName, spec.title, {
            pageKey         = spec.key,
            defaultsButton  = true,
            defaultsTooltip = spec.defaultsTooltip,
        })
        ctx.panel.defaultsOnClick = function()
            H.RestoreDefaults(spec.key, ctx)
            if spec.afterDefaults then spec.afterDefaults() end
            if spec.redrawOnDefaults then H.RefreshPanel(ctx, true) end
        end
        local opts = { beforeGroup = spec.beforeGroup, tabs = spec.tabs }
        local function render(c)
            H.ClearScroll(c)
            if spec.unit then c.unit = spec.unit() end
            if spec.banner then spec.banner(c) end
            H.RenderTabbedSchema(c, spec.key, spec.afterGroup, nil, opts)
        end
        -- A tab click redraws the banner too, so it re-enters through the whole render.
        if spec.banner then opts.rerender = render end
        H.SetRenderer(ctx, render)
        NS.pageCtx[spec.key] = ctx
        return Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, spec.title)
    end, spec.clients and { clients = spec.clients } or nil)
end

if not lib then
    -- The LOAD-COMPLETING stub (options-ui-§1): every member a page file touches at load, the global
    -- reset kept real, everything else a no-op or one honest line. The composers are HOLLOW and
    -- answer {} (anti-pattern #73); no widget maker, flow engine or LAYOUT constant is copied here.
    local MISSING = NS.LIBKA0S_MISSING .. ", so the settings panel is unavailable."
    local Helpers = {}
    NS.Helpers = Helpers
    Helpers.MASTER_GROUP   = "Master controls"
    Helpers.LSMValues      = function() return function() return {} end end
    Helpers.MasterControls = function() return {}, function() end end
    Helpers.ColorPair, Helpers.FontGroup = function() return {} end, function() return {} end
    Helpers.BorderGroup, Helpers.BarGroup = function() return {} end, function() return {} end
    Helpers.PositionBlock  = function() return {}, function() end end
    Helpers.RestoreAllDefaults = function()
        NS.Bulk.Run("reset", "all", function(info)
            for _, row in ipairs(NS.Schema) do
                if not vetoedFromResetAll(row) then NS.ApplyDefault(row) end
            end
            if descriptor.resetProfile() then info.profileReset = true end
        end)
    end
    for _, name in ipairs({
        "CreatePanel", "EnsureDefaultsButton", "EnsureScroll", "ClearScroll", "Section", "AddSpacer",
        "TextRow", "LabelFont", "BuildLandingPage", "AttachTooltip", "InlineButtonPair", "RenderField", "RenderRows",
        "RenderSchema", "RenderGrid", "SessionCheckbox", "SetRenderer", "RefreshAllPanels",
        "RefreshScalars", "RefreshPanel", "RestoreDefaults", "PatchAlwaysShowScrollbar",
        "RegisterOptionsPage", "CreateOptionsPanel", "OpenOptionsPanel", "SetChromeHeight", "TabStrip",
        "PageBanner", "RenderTabbedSchema", "SelectTab", "ChoiceGrid", "IdInput", "IdList", "NavRail",
        "Drawer", "Relayout", "KeybindingsTab", "KeybindRows",
    }) do
        Helpers[name] = function() end
    end
    Helpers.ResolveId         = function() return nil end
    Helpers.UnnamedCandidates = function() return nil end
    Helpers.ID_NAME_HINT      = {}
    Helpers.StrataTooltip     = function() return "" end
    Helpers.ResetAllTooltip   = function() return "" end
    Helpers.KEYBINDS_UNCHANGED = "Key bindings are not changed."
    -- The Skin tab (LibKa0s v1.78.0, OptionsAppearance; skinning-§3): every Options stub owes both
    -- members, adopted or not. On this path RenderTabbedSchema draws no tabs and EnsureScroll answers
    -- nil, so the entry is inert and AppearanceRows answers nil, as the live one does when it cannot
    -- draw. Labeled "Skin" since OptionsAppearance minor 3; the key stays "Appearance".
    Helpers.AppearanceTab  = function() return { key = "Appearance", label = "Skin", render = function() end } end
    Helpers.AppearanceRows = function() return nil end
    -- The first-run skin picker (LibKa0s v1.79.0, OptionsSkinPicker minor 1): without the library there
    -- is no skin to pick, so SkinPicker draws nothing and answers nil (never "queued": there is no
    -- queue), and HideSkinPicker is a no-op.
    Helpers.SkinPicker     = function() return nil end
    Helpers.HideSkinPicker = function() end
    -- The reserved `/ct skin` verb (LibKa0s v1.82.0, OptionsSkinPicker minor 3, ruling D-16): no picker
    -- without the library, so it answers nil, "absent" and NS.RunSkinVerb prints the library-absent line.
    Helpers.SkinVerb       = function() return nil, "absent" end
    Helpers.SkinNotice = function() return nil, "unavailable" end
    NS.RegisterOptionsPage = function() end
    NS.CreateOptionsPanel  = function() NS.Print(MISSING) end
    NS.OpenOptionsPanel    = NS.CreateOptionsPanel
    return
end

-- NS.Helpers IS the instance, decorated in place -- never a copy-across.
NS.Helpers = lib:New(descriptor)
local Helpers = NS.Helpers

-- The three entry points the rest of the addon calls.
NS.RegisterOptionsPage = function(key, name, builder, opts) Helpers.RegisterOptionsPage(key, name, builder, opts) end
NS.CreateOptionsPanel  = function() Helpers.CreateOptionsPanel() end
NS.OpenOptionsPanel    = function() Helpers.OpenOptionsPanel() end   -- the `config` verb
