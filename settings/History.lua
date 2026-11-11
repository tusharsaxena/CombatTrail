local _, NS = ...
-- settings/History.lua — the History page (spec §5, §7 and §8, the mockup's History tabs, plan Task
-- 4.5): four tabs in strip order. Recording filters holds what a fight must pass to be stored
-- (modules/Filters.lua: `history.minLength`, `history.bossesOnly`, one `history.content.<kind>` per
-- content kind this client has). History (internal key `retention`, plan decision D6) holds how long
-- and how many are kept (modules/Retention.lua and modules/Bests.lua: `history.days`,
-- `history.keepBests`, `history.maxFights`), then the stored count and size, then Purge history…
-- last. Results window holds the window's scale, its list's row height, whether it closes when combat
-- starts, whether Share appends the talents link and how the ability timeline's By ability lanes draw
-- a cast (`results.scale`, `results.rowHeight`, `results.closeInCombat`, `results.shareTalents`,
-- `results.timelineMarks`). Usage holds the "never show" list
-- (`global.usage.hidden`), drawn as the library's ID list.
--
-- NOT ROWS: `results.view` (the filters, the grouping and the sort Save view captures) and
-- `results.window` (the place and size the drag and the grip set, and the fold the arrow sets) and
-- `results.columns` (the widths a column header's edge was dragged to) are
-- window state, architecture-§5's named non-setting state (a remembered view, geometry only a drag or
-- a resize determines): no control here sets them, so no row addresses them, and Save view and the
-- drag keep writing them whole. The mockup's Default grouping, Default date range and Open on current
-- character are therefore the window's own Save view.
--
-- CLIENTS (clients-§4): the content rows are built from the profile's defaults, whose Mythic+, delve
-- and arena keys are ABSENT on WoW Forever, and each Retail-only row is declared `clients = { "retail" }`.
-- No label or tooltip on WoW Forever names a Retail-only feature, or a specialization: there the
-- predominant talent tree stands in for the spec, and the words name a talent tree (v0.2 plan D11).
--
-- WRITES: every row writes through the seam (NS.SetByPath). Filters and Retention read their keys at
-- call time; the Results window answers `results.scale`, `results.rowHeight` and
-- `results.timelineMarks` off SETTINGS_CHANGED (modules/Results.lua), so no row carries an onChange.

local L = NS.L
local PAGE = "history"
local D = NS.defaults.profile

--- The four tabs, by the plan's key, in strip order.
NS.HISTORY_TAB_ORDER = { "recording", "retention", "results", "usage" }
NS.HISTORY_TABS = {
    recording = L["Recording filters"], retention = L["History"], results = L["Results window"], usage = L["Usage"],
}
local TAB = NS.HISTORY_TABS

local HistoryPage = {}
NS.HistoryPage = HistoryPage

local RETAIL = { "retail" }

-- ── the rows ───────────────────────────────────────────────────────────────────────────────────

-- A whole number from `lo` to `hi`, the slider's range (the seam does not clamp a typed value).
local function whole(lo, hi)
    return function(v)
        return type(v) == "number" and v >= lo and v <= hi and v == math.floor(v)
    end
end

local function within(lo, hi)
    return function(v) return type(v) == "number" and v >= lo and v <= hi end
end

local function read(t, key)
    for part in key:gmatch("[^.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

local out = {}
local group, subgroup
local function at(g, s) group, subgroup = g, s end

-- A row at profile path `path`, its default read from the profile's defaults.
local function row(path, t)
    t.path, t.page, t.group, t.subgroup = path, PAGE, group, subgroup
    t.default = read(D, path)
    out[#out + 1] = t
    return t
end

-- The content kinds, in modules/Identity.lua's order, each with its label and its clients.
local CONTENT = {
    { "raid", L["Raids"] },
    { "dungeon", L["Dungeons"] },
    { "mplus", L["Mythic+ dungeons"], RETAIL },
    { "delve", L["Delves"], RETAIL },
    { "bg", L["Battlegrounds"] },
    { "arena", L["Arenas"], RETAIL },
    { "world", L["Open world"] },
    { "dummy", L["Training dummies"] },
    { "scenario", L["Scenarios"] },
}

-- Recording filters
at(TAB.recording, L["Which fights"])
row("history.minLength", { type = "number", label = L["Minimum fight length (seconds)"], min = 0, max = 300, step = 5,
    validate = whole(0, 300), startsLine = true,
    tooltip = L["A fight shorter than this is shown on the DPS HUD but not stored. The default is %d seconds."]
        :format(D.history.minLength) })
row("history.bossesOnly", { type = "bool", label = L["Bosses only"],
    tooltip = L["Store only boss encounters. Trash, the open world and training dummies are still shown on the DPS HUD."] })

at(TAB.recording, L["Content to store"])
for i, c in ipairs(CONTENT) do
    if D.history.content[c[1]] ~= nil then
        row("history.content." .. c[1], { type = "bool", label = c[2], clients = c[3], startsLine = i % 2 == 1,
            tooltip = L["Store the fights you have here. Off, they are still shown on the DPS HUD."] })
    end
end

-- The History tab (options-ui-§21's data-lifetime family: how long, then the readout, then the purge last)
at(TAB.retention, nil)
row("history.days", { type = "number", label = L["Keep history for (days, 0 = forever)"], min = 0, max = 365, step = 1,
    validate = whole(0, 365), startsLine = true,
    tooltip = L["Stored fights older than this many days are removed, at login and once a day while you play. 0 keeps every fight."] })
row("history.keepBests", { type = "bool", label = L["Never purge a fight that holds a best"],
    tooltip = NS.Compat.ForClient(RETAIL)
        and L["Keep a fight however old it is while it is your best on its board: your top DPS for one character and spec on one encounter or target at one difficulty."]
        or L["Keep a fight however old it is while it is your best on its board: your top DPS for one character and talent tree on one encounter or target at one difficulty."] })
row("history.maxFights", { type = "number", label = L["Maximum stored fights (0 = no limit)"], min = 0, max = 1000, step = 50,
    validate = whole(0, 1000), startsLine = true,
    tooltip = L["The most fights kept. Past it the oldest go first, except a fight that holds a best while Never purge a fight that holds a best is on. 0 keeps any number."] })

-- Results window
at(TAB.results, L["Size"])
row("results.scale", { type = "number", label = L["Window scale"], min = 0.5, max = 2, step = 0.05, isPercent = true,
    validate = within(0.5, 2), startsLine = true,
    tooltip = L["The size of the Results window, its text included, and of the ability timeline, the gear view and the compare that open over it."] })
row("results.rowHeight", { type = "number", label = L["Row height (px)"],
    min = NS.ResultsTable.ROW_H_MIN, max = NS.ResultsTable.ROW_H_MAX, step = 1,
    validate = whole(NS.ResultsTable.ROW_H_MIN, NS.ResultsTable.ROW_H_MAX),
    tooltip = L["The height of each row in the Results window's list of fights, in pixels."] })
at(TAB.results, L["Behavior"])
row("results.closeInCombat", { type = "bool", label = L["Close when combat starts"], startsLine = true,
    tooltip = L["Close the Results window, and the timeline, gear view and compare over it, when you enter combat. Open it again mid-fight and it stays open until the next pull."] })
at(TAB.results, L["Sharing"])
row("results.shareTalents", { type = "bool", label = L["Include talents link when sharing"], startsLine = true,
    tooltip = L["Add the fight's talents to the shared line as a link others can click to see the talent tree. When the line and the link would be too long for one chat message, the link follows as a second one."] })
-- The ability timeline (v0.2 Task D1, modules/Results_TimelineMarks.lua): how By ability draws each
-- cast, its ability's icon or a thin tick, in its caster's color either way. The timeline's two words
-- on the By ability heading line write the same row.
at(TAB.results, L["Ability timeline"])
row("results.timelineMarks", { type = "string", label = L["Casts in By ability"], startsLine = true,
    values = { { value = "icon", text = L["Ability icons"] }, { value = "tick", text = L["Tick lines"] } },
    validate = function(v) return NS.ResultsTimeline.MARK_MODES[v] == true end,
    tooltip = L["How the ability timeline's By ability lanes show each cast: the ability's icon (hover it for the spell and its time) or a thin tick line. Either way a pet's cast is green and yours blue. The timeline's Icons and Ticks words switch it too."] })

-- Usage: the "never show" list (modules/Usage.lua, spec §7). One plain string of item IDs written
-- WHOLE through the seam (a value, architecture-§5), so the CLI's get, set and reset and the page's
-- Defaults reach it like any row. Global, as the fight store it filters is. The row carries
-- skipRender: the tab draws it as the library's ID list (afterUsage). The page's Defaults empties it,
-- as DPS Race's does, and its tooltip says so first.
at(TAB.usage, nil)
out[#out + 1] = {
    path = NS.Usage.HIDDEN_PATH, page = PAGE, group = TAB.usage, type = "string", skipRender = true,
    label = L["Hidden items"], default = NS.defaults.global.usage.hidden,
    validate = function(v) return NS.Usage.ParseHidden(v) ~= nil end,
    normalize = function(v) return NS.Usage.NormalizeHidden(v) end,
    tooltip = L["Account-wide: shared by every profile. Item IDs, comma-separated, that the Results window's Usage never lists, on any fight. A fight that used one still records it, so taking it off the list brings it back."],
}

for i, r in ipairs(out) do r.order = i end
NS.RegisterSchemaRows(out)

-- ── the History tab's readout and act ───────────────────────────────────────────────────────────

local KB, MB = 1024, 1024 * 1024

--- About `bytes`, in words: "512 bytes", "2.0 KB", "3.1 MB".
function HistoryPage.SizeText(bytes)
    bytes = tonumber(bytes) or 0
    if bytes < KB then return L["%d bytes"]:format(bytes) end
    if bytes < MB then return L["%.1f KB"]:format(bytes / KB) end
    return L["%.1f MB"]:format(bytes / MB)
end

--- "Stored now: 142 fights, about 640.0 KB of saved variables."
function HistoryPage.StoredLine()
    local n = NS.Recorder.Count()
    local size = HistoryPage.SizeText(NS.Retention.EstimateBytes())
    if n == 1 then return L["Stored now: 1 fight, about %s of saved variables."]:format(size) end
    return L["Stored now: %d fights, about %s of saved variables."]:format(n, size)
end

--- The Purge history… tooltip (one function, so a suite reads the words the button carries).
function HistoryPage.PURGE_TOOLTIP()
    return L["Remove now the stored fights these settings no longer keep, as the purge at login does. Asks for confirmation."]
end

HistoryPage.POPUP = "COMBATTRAIL_PURGE_FIGHTS"

StaticPopupDialogs[HistoryPage.POPUP] = {
    text         = L["Remove the stored fights that Keep history for and Maximum stored fights no longer keep? This cannot be undone."],
    button1      = L["Remove"],
    button2      = L["Cancel"],
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept     = function() NS.Retention.OnVerb() end,
}

--- Purge history…: asks first, through the one popup. The answer runs `/ct purge`'s purge.
function HistoryPage.ConfirmPurge()
    return StaticPopup_Show(HistoryPage.POPUP)
end

-- After the History tab's rows: the readout, then Purge history… as the tab's last act, with no heading over
-- it (options-ui-§7, §21).
local function afterRetention(ctx)
    local H = NS.Helpers
    H.TextRow(ctx, HistoryPage.StoredLine())
    H.InlineButtonPair(ctx, {
        text    = L["Purge history\226\128\166"],
        tooltip = HistoryPage.PURGE_TOOLTIP(),
        onClick = function() HistoryPage.ConfirmPurge() end,
    })
end

-- Before the Recording filters' rows: what they decide.
local function beforeRecording(ctx)
    NS.Helpers.TextRow(ctx, L["Every fight is tracked live on the DPS HUD. A fight is stored only when it passes all of these."])
end

-- The Usage tab's list: a blurb, then the library's ID list (an add box over one line per hidden
-- item, each with its X). The widget never writes: Usage.Hide and Usage.Unhide write the whole value.
local function afterUsage(ctx)
    local H = NS.Helpers
    H.TextRow(ctx, L["Items the Results window's Usage never lists, on any fight. Right-click an item in a fight's Usage edit to add it here."])
    H.IdList(ctx, {
        kind        = "item",
        label       = L["Hide an item"],
        tooltip     = L["An item ID, a shift-clicked item link, or the name of an item a fight listed."],
        emptyText   = L["No item is hidden."],
        entries     = function()
            local list = {}
            for i, id in ipairs(NS.Usage.HiddenList()) do list[i] = { id = id } end
            return list
        end,
        candidates  = function() return NS.Usage.KnownItems() end,
        onAdd       = function(id) NS.Usage.Hide(id) end,
        onRemove    = function(id) NS.Usage.Unhide(id) end,
        removeStyle = "icon",
        columns     = 2,
    })
end

NS.RegisterTabbedPage({
    key             = PAGE,
    title           = L["History"],
    panelName       = "CombatTrailHistoryPanel",
    defaultsTooltip = L["Restore every History setting on this profile to its addon default, and empty the account-wide hidden items. Stored fights are not touched."],
    afterGroup      = { [TAB.retention] = afterRetention, [TAB.usage] = afterUsage },
    beforeGroup     = { [TAB.recording] = beforeRecording },
})

-- The stored count repaints when the store changes, and the hidden-items list when it changes from
-- anywhere (the detail's right-click, `/ct set` or `reset`); a hidden page is only flagged, and
-- repaints on its next show (the library's RefreshPanel).
local function repaint()
    local ctx = NS.pageCtx[PAGE]
    if ctx and NS.Helpers.RefreshPanel then NS.Helpers.RefreshPanel(ctx, true) end
end

do
    local bus = NS.NewBusTarget()
    if bus then
        bus:RegisterMessage(NS.MSG.FIGHTS_CHANGED, repaint)
        bus:RegisterMessage(NS.MSG.FIGHT_SAVED, repaint)
        bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path)
            if path == NS.Usage.HIDDEN_PATH then repaint() end
        end)
    end
end
