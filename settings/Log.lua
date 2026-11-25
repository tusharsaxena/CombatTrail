local _, NS = ...
-- settings/Log.lua — the Combat Log page (CombatTrail #11, plan item CL-11c2; the spec's addendum,
-- *Settings*): eight tabs over every `log.*` key a player chooses, in strip order Combat Log (the
-- master switch, the log open now, opened at each fight's start, where it lives), Docked drawer (its
-- filter chips, its rows), Detached window (its rows, its lock, scale and opacity; a standalone
-- window, owner feedback item 11, so no attach, side, HUD-height match or pin), Order and display (the sort, the display throttle, the rows' text size and height, the
-- time, the columns), What to show (the live views' categories, the auto attacks),
-- Colors (row washes, the who colors), Storage (a log with each fight, the lines kept,
-- the categories saved) and Results (the Log section's chips, the jump to the Timeline). The keys are
-- modules/CombatLog.lua's, modules/LogTable.lua's, modules/LogTable_View.lua's, modules/Hud_Log.lua's,
-- modules/LogWindow.lua's and modules/Results_Log.lua's (defaults/Profile.lua).
--
-- NOT HERE: `log.window.position`, `log.window.width` and `log.window.height`, the detached window's
-- geometry, which only its drag and its grip choose (written raw, as the Race window's own place is).
--
-- WRITES: every row writes through the seam (NS.SetByPath), whose SETTINGS_CHANGED on a `log.` path
-- the drawer (a HUD refresh), the detached window (a relayout) and the Results Log section (a redraw)
-- answer, so no row carries an onChange. A fight freezes its Storage settings at its start, so a
-- change there takes hold from the next fight (CombatLog's capture).

local L = NS.L
local H = NS.Helpers
local PAGE = "log"
local D = NS.defaults.profile.log
local LOG = NS.Constants.LOG

--- The eight tabs, by key, in strip order.
NS.LOG_TAB_ORDER = { "log", "drawer", "window", "display", "show", "colors", "store", "results" }
NS.LOG_TABS = {
    log = L["Combat Log"], drawer = L["Docked drawer"], window = L["Detached window"],
    display = L["Order and display"], show = L["What to show"], colors = L["Colors"], store = L["Storage"],
    results = L["Results"],
}
local TAB = NS.LOG_TABS

-- ── value lists ────────────────────────────────────────────────────────────────────────────────

local function choices(...)
    local list, ok = {}, {}
    for i = 1, select("#", ...), 2 do
        local value, text = select(i, ...)
        list[#list + 1] = { value = value, text = text }
        ok[value] = true
    end
    return list, function(v) return ok[v] == true end
end

local HOMES, HOME_OK = choices("docked", L["Docked in the DPS HUD"], "detached", L["In its own window"])
local SORTS, SORT_OK = choices("newest", L["Newest first"], "oldest", L["Oldest first"])
local THROTTLES, THROTTLE_OK = choices(
    "instant", L["Instant"], "every", L["At most one row every N ms"], "batch", L["In batches every N ms"])
local TIMES, TIME_OK = choices("pull", L["From the pull"], "clock", L["Clock time"])

-- ── the rows ───────────────────────────────────────────────────────────────────────────────────

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

-- A hand row: `key` relative to `log.`, its default read from the profile's defaults.
local function row(key, t)
    t.path, t.page, t.group, t.subgroup = "log." .. key, PAGE, group, subgroup
    t.default = read(D, key)
    out[#out + 1] = t
    return t
end

local function on(path) return NS.GetSetting(path) ~= false end

-- Combat Log
at(TAB.log, L["Combat Log"])
row("enabled", { type = "bool", label = L["Enable the Combat Log"], startsLine = true,
    tooltip = L["Record your casts, your pet's casts, the buffs you gain and lose, the debuffs on you and your target, and your death during each fight, in order, and show them in the DPS HUD's Log drawer or its own window. Off, nothing is recorded and the HUD's Log control is hidden."] })
row("drawer.shown", { type = "bool", label = L["Show the Combat Log"],
    tooltip = L["Open the log now, docked in the DPS HUD or in its own window. The HUD's Log control and /ct log toggle it too."] })
row("drawer.autoOpen", { type = "bool", label = L["Open it when a fight starts"], startsLine = true,
    tooltip = L["Open the log at the start of each fight, even if you closed it during the last one."] })
at(TAB.log, L["Where it lives"])
row("home", { type = "string", label = L["Where the log lives"], values = HOMES, validate = HOME_OK, startsLine = true,
    tooltip = L["Docked: a drawer under the DPS HUD's spell rows, at the HUD's width. In its own window: a wider companion window with an Info column. The drawer's detach mark and the window's dock mark switch it too."] })

-- Docked drawer
at(TAB.drawer, L["Docked drawer"])
row("drawer.chips", { type = "bool", label = L["Show the filter chips"], startsLine = true,
    tooltip = L["Show the Casts, Pet, Buffs and Debuffs chips under the drawer's heading. The eye in the drawer's heading shows and hides them too."] })
row("drawer.rows", { type = "number", label = L["Rows shown"], min = NS.HudLog.MIN_ROWS, max = NS.HudLog.MAX_ROWS,
    step = 1, startsLine = true,
    tooltip = L["How many events the drawer shows at a time; older ones scroll with the mouse wheel. The DPS HUD keeps one height with the drawer in it, and dragging its corner sets these rows too."] })

-- Detached window
at(TAB.window, L["Rows"])
row("window.fill", { type = "bool", label = L["Fill the window with rows"], startsLine = true,
    tooltip = L["Show as many events as the window's height holds. Off, the window shows Rows shown and is as tall as they need."] })
row("window.rows", { type = "number", label = L["Rows shown"], min = NS.LogWindow.MIN_ROWS, max = NS.LogWindow.MAX_ROWS,
    step = 1, disabledIf = function() return on("log.window.fill") end,
    tooltip = L["How many events the window shows at a time. Needs Fill the window with rows off."] })
at(TAB.window, L["Place"])
row("window.locked", { type = "bool", label = L["Lock the window"], startsLine = true,
    tooltip = L["Stop the window from being dragged or resized. General > Master controls' Lock frame locks it too."] })
at(TAB.window, L["Look"])
row("window.scale", { type = "number", label = L["Window scale"], min = 0.5, max = 2, step = 0.05, isPercent = true,
    startsLine = true,
    tooltip = L["The size of the window, its text included."] })
row("window.alpha", { type = "number", label = L["Window opacity"], min = 0.1, max = 1, step = 0.05, isPercent = true,
    tooltip = L["How opaque the window is, its background and its text together, over the DPS HUD's own opacity."] })

-- Order and display
at(TAB.display, L["Order"])
row("view.sort", { type = "string", label = L["Sort order"], values = SORTS, validate = SORT_OK, startsLine = true,
    tooltip = L["Newest first puts the newest event at the top; oldest first puts it at the bottom. A click on the Time header flips it. Either way the log keeps the newest event in view until you scroll away."] })
row("view.throttle", { type = "string", label = L["Show new rows"], values = THROTTLES, validate = THROTTLE_OK,
    startsLine = true,
    tooltip = L["How fast new events appear in the drawer and the window. Instant shows each at the next repaint; at most one row every N ms lets them in one at a time; in batches shows every waiting event together, every N ms. This only slows the display: every event is still recorded and saved."] })
row("view.throttleMs", { type = "number", label = L["N (ms)"], min = 50, max = 1000, step = 10,
    disabledIf = function() return NS.GetSetting("log.view.throttle") == "instant" end,
    tooltip = L["The milliseconds between new rows, or between batches. Needs Show new rows other than Instant."] })
at(TAB.display, L["Size"])
row("view.fontSize", { type = "number", label = L["Text size"], min = NS.LogTable.FONT_MIN, max = NS.LogTable.FONT_MAX,
    step = 1, startsLine = true,
    tooltip = L["The size of the events' text, in points. Larger text widens the columns."] })
row("view.rowHeight", { type = "number", label = L["Row height (px)"], min = NS.LogTable.ROW_H_MIN,
    max = NS.LogTable.ROW_H_MAX, step = 1,
    tooltip = L["The height of each event's row, in pixels. Taller rows make the drawer and the window taller."] })
at(TAB.display, L["Time"])
row("view.timeFormat", { type = "string", label = L["Time"], values = TIMES, validate = TIME_OK, startsLine = true,
    tooltip = L["From the pull: seconds since the fight started. Clock time: the time of day."] })
at(TAB.display, L["Columns"])
row("view.columns.info", { type = "bool", label = L["Show the Info column"], startsLine = true,
    tooltip = L["Show Interrupted, for a cast that was cut short, in its own column, where there is room: the detached window and the Results fight detail."] })
row("view.columns.spell", { type = "bool", label = L["Show the Spell column"], startsLine = true,
    tooltip = L["Show the spell and its icon. Time and Event always show."] })

-- What to show
at(TAB.show, L["Events"])
row("show.casts", { type = "bool", label = L["Your casts"], startsLine = true,
    tooltip = L["Show the spells you cast."] })
row("show.petCasts", { type = "bool", label = L["Your pet's casts"],
    tooltip = L["Show the spells your pet casts."] })
row("show.playerBuffs", { type = "bool", label = L["Buffs gained / lost on you"], startsLine = true,
    tooltip = L["Show the buffs you gain, and when each one ends."] })
row("show.playerDebuffs", { type = "bool", label = L["Debuffs on you"],
    tooltip = L["Show the debuffs put on you, and when each one ends."] })
row("show.targetDebuffs", { type = "bool", label = L["Your debuffs on your target"], startsLine = true,
    tooltip = L["Show the debuffs you put on your target, and when each one ends."] })
row("show.deaths", { type = "bool", label = L["Deaths"],
    tooltip = L["Show your death."] })
at(TAB.show, L["Filters"])
row("show.autoAttacks", { type = "bool", label = L["Show auto attacks"], startsLine = true,
    tooltip = L["Show Auto Shot and Shoot among your casts. Off, they are hidden. A fight's saved log never keeps them."] })

-- Colors
at(TAB.colors, L["Color-blind safety"])
row("view.washes", { type = "bool", label = L["Row washes"], startsLine = true,
    tooltip = L["Tint the rows of debuffs going on and of long-cooldown casts. Off, every row has the plain stripe."] })
at(TAB.colors, L["You"])
for _, r in ipairs(H.ColorPair({
    prefix = "log.colors.", page = PAGE, group = group, subgroup = subgroup, classColor = { source = "player" },
    key = "you", companionKey = "useClassColorYou", label = L["Your color"], colorFromSkin = false,
    defaults = { you = D.colors.you, useClassColorYou = D.colors.useClassColorYou },
    tooltips = { you = L["The color kept for \"You\". No part of the log draws it now."] },
})) do
    r.composed = true
    out[#out + 1] = r
end
at(TAB.colors, L["Targets"])
row("colors.hostile", { type = "color", hasAlpha = false, label = L["Hostile target color"], startsLine = true,
    tooltip = L["The color kept for a target you can attack. No part of the log draws it now."] })
row("colors.hostileFromSkin", { type = "bool", label = L["Use the skin's color"],
    tooltip = L["Take the hostile target color from the skin. The swatch is not read while this is on."] })
row("colors.friendly", { type = "color", hasAlpha = false, label = L["Friendly target color"], startsLine = true,
    tooltip = L["The color kept for a target you cannot attack. No part of the log draws it now."] })
row("colors.friendlyFromSkin", { type = "bool", label = L["Use the skin's color"],
    tooltip = L["Take the friendly target color from the skin. The swatch is not read while this is on."] })

-- Storage
at(TAB.store, L["Storage"])
row("store.enabled", { type = "bool", label = L["Save a log with each fight"], startsLine = true,
    tooltip = L["Keep each stored fight's Combat Log, for the Log section of its Results detail. Takes hold from the next fight."] })
row("store.lines", { type = "number", label = L["Lines kept per fight"], min = LOG.MIN_PER_FIGHT, max = LOG.MAX_LINES,
    step = 50, startsLine = true,
    tooltip = L["The most lines a fight's saved log keeps, the newest. More lines make the saved history larger."] })
row("store.fights", { type = "number", label = L["Fights that keep their log (0 = all)"], min = 0,
    max = LOG.MAX_FIGHTS, step = 10, startsLine = true,
    tooltip = L["Only the newest stored fights keep their saved log; an older fight stays in the history without it. 0 keeps every fight's log. Applied when the history is next tidied: at login, once a day, or with /ct purge."] })
at(TAB.store, L["Saved"])
local SAVED = {
    { "casts", L["Your casts"] }, { "petCasts", L["Your pet's casts"] },
    { "playerBuffs", L["Buffs gained / lost on you"] }, { "playerDebuffs", L["Debuffs on you"] },
    { "targetDebuffs", L["Your debuffs on your target"] }, { "deaths", L["Deaths"] },
}
for i, c in ipairs(SAVED) do
    row("store.categories." .. c[1], { type = "bool", label = c[2], startsLine = i % 2 == 1 or nil,
        tooltip = L["Save these lines with each fight. Separate from What to show, which only filters the live views."] })
end

-- Results
at(TAB.results, L["Log section"])
row("results.jumpToCast", { type = "bool", label = L["Jump to the Timeline on clicking a cast"], startsLine = true,
    tooltip = L["A click on a CAST row on a fight's Log section opens the ability timeline at that cast."] })
at(TAB.results, L["Chips each fight opens on"])
for i, chip in ipairs(NS.ResultsLog.CHIPS) do
    row("results.chips." .. chip.key, { type = "bool", label = L[chip.label], startsLine = i % 2 == 1 or nil,
        tooltip = L["Turn this chip on when a fight's Log section opens. A click on the chip still turns it on or off for the fight shown."] })
end

-- One running order, so a composed block (which numbers its own rows) sorts where it is declared.
for i, r in ipairs(out) do r.order = i end
NS.RegisterSchemaRows(out)

NS.RegisterTabbedPage({
    key             = PAGE,
    title           = L["Combat Log"],
    panelName       = "CombatTrailLogPanel",
    defaultsTooltip = L["Restore every Combat Log setting on this profile to its addon default."],
})
