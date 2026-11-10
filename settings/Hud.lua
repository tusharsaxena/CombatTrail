local _, NS = ...
-- settings/Hud.lua — the DPS HUD page (spec §6 and §8, the mockup's DPS HUD tabs, plan Task 3.3): six
-- tabs over every `hud.*` key, in strip order Behavior (when the HUD opens and fades, what the pace
-- compares against, the fight-over card), Layout (which parts the stack holds, and its size), Clock
-- and figures, Damage chart, Spell rows and Window (its chrome, background and border, its place and
-- its layer). The keys are modules/Hud.lua's and modules/Hud_Appearance.lua's (defaults/Profile.lua).
--
-- COMPOSED BLOCKS (options-ui-§16/§17): every font is the library's FontGroup, every status bar its
-- BarGroup and every color a ColorPair with its Use class color companion, all over this addon's
-- leaves and the profile's own defaults (`defaults`), so the clock keeps its plain "" flags (the
-- mono role: no flagsFromSkin) while the figures and the rows draw the skin's outline ("@skin"). The
-- clock draws the skin's HUD face by default, as DPS Race's does (v0.2 Task B2), and its stored size
-- scaled to DPS Race's single clock (Hud_States' ClockSize: 26 draws 40), which its size row says. The skin companions the composer has no row for (a font block's text color and
-- shadow, a backdrop swatch) are this addon's own rows in the block's `extra`, in its own words,
-- so they carry no `composed` mark (skinning-§6). The window has no Lock row: Lock frame is General >
-- Master controls' (`general.locked`), the one switch for the lanes and the HUD together.
--
-- WRITES: every row writes through the seam (NS.SetByPath), whose SETTINGS_CHANGED on a `hud.*` path
-- the HUD answers with Hud.Apply (a restyle and a redraw), so no row carries an onChange.

local L = NS.L
local H = NS.Helpers
local PAGE = "hud"
local D = NS.defaults.profile.hud

--- The six tabs, by the plan's key, in strip order.
NS.HUD_TAB_ORDER = { "behavior", "layout", "clock", "chart", "spells", "window" }
NS.HUD_TABS = {
    behavior = L["Behavior"], layout = L["Layout"], clock = L["Clock and figures"],
    chart = L["Damage chart"], spells = L["Spell rows"], window = L["Window"],
}
local TAB = NS.HUD_TABS

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

local SHOWS, SHOW_OK = choices(
    "auto", L["On each fight's first hit"], "always", L["Always"], "toggle", L["Only when you open it"])
local PACES, PACE_OK = choices(
    "best", L["Your best on this boss or target"], "last", L["Your last fight there"], "none", L["Nothing"])
local POINTS, POINT_OK = choices(
    "TOPLEFT", L["Top left"], "TOP", L["Top"], "TOPRIGHT", L["Top right"], "LEFT", L["Left"],
    "CENTER", L["Center"], "RIGHT", L["Right"], "BOTTOMLEFT", L["Bottom left"], "BOTTOM", L["Bottom"],
    "BOTTOMRIGHT", L["Bottom right"])
-- frame-layering-§1: a player-chosen strata offers BACKGROUND to HIGH, never DIALOG.
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH" }
local STRATAS, STRATA_OK = choices(
    "BACKGROUND", L["Background"], "LOW", L["Low"], "MEDIUM", L["Medium"], "HIGH", L["High"])

-- ── the rows ───────────────────────────────────────────────────────────────────────────────────

local function read(t, key)
    for part in key:gmatch("[^.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

local PLAYER_CLASS = { source = "player" }   -- every HUD surface describes the player
local out = {}
local group, subgroup
local function at(g, s) group, subgroup = g, s end

-- A hand row: `key` relative to `hud.`, its default read from the profile's defaults.
local function row(key, t)
    t.path, t.page, t.group, t.subgroup = "hud." .. key, PAGE, group, subgroup
    t.default = read(D, key)
    out[#out + 1] = t
    return t
end

-- A composed block: the library's words, but on the rows this addon appended (`extra`).
local function block(rows)
    for _, r in ipairs(rows) do
        if not r.own then r.composed = true end
        r.own = nil
        out[#out + 1] = r
    end
    return rows
end

-- A composer spec over block `name` (`hud.<name>.`), its defaults the profile's.
local function spec(name, t)
    t.prefix, t.page, t.group, t.subgroup, t.classColor = "hud." .. name .. ".", PAGE, group, subgroup, PLAYER_CLASS
    t.defaults = t.defaults or D[name]
    return t
end

-- A companion of this addon's own, appended to a block (`own`: not the library's words).
local function companion(name, key, label, tooltip)
    return { path = "hud." .. name .. "." .. key, type = "bool", startsLine = true, own = true,
             label = label, tooltip = tooltip, default = D[name][key] }
end

local function colorPair(name, key, label, tooltip, extra)
    local cc = "useClassColor" .. key:sub(1, 1):upper() .. key:sub(2)
    return block(H.ColorPair(spec(name, { key = key, companionKey = cc, label = label,
        defaults = { [key] = D[name][key], [cc] = D[name][cc] },
        tooltips = tooltip and { [key] = tooltip } or nil, extra = extra })))
end

-- A font block with the skin's text color and shadow companions after it (skinning-§6).
local function fontBlock(name, flagsFromSkin, tooltips)
    return block(H.FontGroup(spec(name, { fromSkin = true, flagsFromSkin = flagsFromSkin, tooltips = tooltips,
        extra = {
            companion(name, "fontColorFromSkin", L["Use the skin's color"],
                L["Draw this text in the skin's HUD text color. The Font color swatch is not read while this is on, and Use class color comes first."]),
            companion(name, "fontShadowFromSkin", L["Use the skin's shadow"],
                L["Draw this text with the skin's shadow. Font shadow is not read while this is on."]),
        } })))
end

-- Behavior
at(TAB.behavior, L["When it shows"])
row("show", { type = "string", label = L["Show the HUD"], values = SHOWS, validate = SHOW_OK,
    tooltip = L["On each fight's first hit: it opens when your damage starts and fades after the fight. Always: it stays up. Only when you open it: from /ct hud, the launcher or its key binding."] })
row("instancesOnly", { type = "bool", label = L["Only in instances"], startsLine = true,
    tooltip = L["When Show the HUD is On each fight's first hit, open it only inside a dungeon, raid or other instance. Always keeps it up everywhere."] })
row("fadeAfter", { type = "number", label = L["Fade after the fight (seconds, 0 = never)"], min = 0, max = 60, step = 1,
    startsLine = true,
    tooltip = L["How long the fight-over card stays after the fight ends before the HUD closes. 0 keeps it up until you close it."] })
row("holdOnMouse", { type = "bool", label = L["Stay open while the mouse is over it"],
    tooltip = L["Hold the HUD open while the pointer is over it, and fade it a moment after the pointer leaves."] })

at(TAB.behavior, L["Pace"])
row("paceAgainst", { type = "string", label = L["Pace compares against"], values = PACES, validate = PACE_OK,
    startsLine = true,
    tooltip = L["The stored fight the pace bar measures you against: your best on the same boss or target, the last fight you had there, or none, which hides the pace bar."] })
row("paceRange", { type = "number", label = L["Pace bar range"], min = 1.1, max = 2.0, step = 0.05,
    tooltip = L["How far either side of the pace the bar reaches: 1.5 runs from half the pace's damage so far to half again. The tick in the middle is the pace."] })

at(TAB.behavior, L["Fight-over card"])
row("overCard", { type = "bool", label = L["Show fight-over card"], startsLine = true,
    tooltip = L["Show the final damage, DPS and spell percentages once the fight ends. Off, a HUD that opened by itself closes when the fight ends."] })
row("showSkipReason", { type = "bool", label = L["Show why a fight was not saved"],
    tooltip = L["Say on the card why a fight was not stored, such as too short or filtered out. Needs Show fight-over card."] })

-- Layout
at(TAB.layout, L["Parts"])
row("layout.clock", { type = "bool", label = L["Show clock"], startsLine = true,
    tooltip = L["Show the fight's clock, counting up from the first hit."] })
row("layout.target", { type = "bool", label = L["Show target line"],
    tooltip = L["Show the encounter or target, the instance and the difficulty under the clock."] })
row("layout.figures", { type = "bool", label = L["Show damage and DPS boxes"], startsLine = true,
    tooltip = L["Show the Damage and DPS boxes, with your pet's figure beside them."] })
row("layout.pace", { type = "bool", label = L["Show pace bar"],
    tooltip = L["Show the bar that measures your damage so far against the pace. Hidden while there is nothing to pace against."] })
row("layout.chart", { type = "bool", label = L["Show damage chart"], startsLine = true,
    tooltip = L["Show your damage over the fight as columns, with the pace as a line and your long cooldowns as icons."] })
row("layout.spells", { type = "bool", label = L["Show spell rows"],
    tooltip = L["Show your spells and your pet's, one row each, in the order the damage meter gives them."] })

at(TAB.layout, L["Size"])
row("width", { type = "number", label = L["HUD width (px)"], min = NS.Hud.MIN_WIDTH, max = 600, step = 10, startsLine = true,
    tooltip = L["How wide the HUD is, in pixels. Its height follows the parts it shows."] })
row("scale", { type = "number", label = L["HUD scale"], min = 0.5, max = 2, step = 0.05, isPercent = true,
    tooltip = L["The size of the whole HUD, its text included."] })

-- Clock and figures
at(TAB.clock, L["Clock font"])
fontBlock("clock", false, { font = L["The face the clock is drawn in. A face with even-width digits keeps the clock from jumping as it counts."],
    fontSize = L["The clock's size. It draws about half again as tall as this, as DPS Race's clock does: 26 draws it 40 points high."] })
at(TAB.clock, L["Figures font"])
fontBlock("figures", true, { font = L["The face the Damage and DPS figures are drawn in."] })
at(TAB.clock, L["Fight-over card"])
colorPair("figures", "overColor", L["Final DPS color"], L["The color of the DPS figure on the fight-over card."])
at(TAB.clock, L["Box background"])
colorPair("figures", "boxBg", L["Background color"], L["The fill behind the Damage and DPS boxes."], {
    companion("figures", "boxBgFromSkin", L["Use the skin's background"],
        L["Fill the boxes in the skin's own color. The background swatch is not read while this is on."]) })
at(TAB.clock, L["Box border"])
colorPair("figures", "boxBorder", L["Border color"], L["The edge around the Damage and DPS boxes."], {
    companion("figures", "boxBorderFromSkin", L["Use the skin's color"],
        L["Draw the boxes' edge in the skin's own color. The border swatch is not read while this is on."]) })

-- Damage chart
at(TAB.chart, L["Size"])
row("chart.height", { type = "number", label = L["Chart height (px)"], min = 40, max = 200, step = 2, startsLine = true,
    tooltip = L["The height of the chart's plot, in pixels."] })
row("chart.columns", { type = "number", label = L["Maximum columns"], min = 8, max = NS.Slices.MAX, step = 1,
    tooltip = L["The most columns the chart draws. A long fight folds more seconds into each column."] })
at(TAB.chart, L["Columns"])
block(H.BarGroup(spec("chart", { fromSkin = true })))
at(TAB.chart, L["Burst windows"])
colorPair("chart", "burstColor", L["Burst column color"],
    L["The color of the columns in the seconds after you use a long cooldown."])
at(TAB.chart, L["Lines"])
colorPair("chart", "bestColor", L["Pace line color"], L["The color of the line that marks the pace."])
row("chart.zeroLine", { type = "bool", label = L["Show zero line"], startsLine = true,
    tooltip = L["Draw a thin line along the chart's bottom edge."] })
at(TAB.chart, L["Cooldowns"])
row("chart.cooldowns", { type = "bool", label = L["Show cooldown icons"], startsLine = true,
    tooltip = L["Mark each cast of a spell with a long cooldown with its icon along the top of the chart."] })
row("chart.cooldownMin", { type = "number", label = L["Shortest cooldown (seconds)"], min = 5, max = 600, step = 1,
    tooltip = L["The shortest base cooldown, in seconds, that earns an icon. Needs Show cooldown icons."] })

-- Spell rows
at(TAB.spells, L["Size"])
row("spells.rows", { type = "number", label = L["Spell rows shown (0 = all)"], min = 0, max = 40, step = 1,
    startsLine = true,
    tooltip = L["How many spells the HUD lists. 0 lists every one: as many as fit show, and the mouse wheel scrolls through the rest."] })
row("spells.rowHeight", { type = "number", label = L["Row height (px)"], min = 12, max = 40, step = 1,
    tooltip = L["The height of each spell row, in pixels."] })
at(TAB.spells, L["Icons"])
row("spells.icons", { type = "bool", label = L["Show spell icons"], startsLine = true,
    tooltip = L["Draw each spell's icon at the start of its row."] })
row("spells.paw", { type = "bool", label = L["Show pet paw"],
    tooltip = L["Mark your pet's spells with a paw."] })
at(TAB.spells, L["Player bars"])
block(H.BarGroup(spec("spells", { fromSkin = true,
    tooltips = { barTexture = L["The texture your spell rows' bars and the pace bar's fills are drawn with."] } })))
at(TAB.spells, L["Pet bars"])
colorPair("spells", "petColor", L["Pet bar color"],
    L["The color of your pet's spell rows and of its part of the pace bar."])
at(TAB.spells, L["Row font"])
fontBlock("spells", true, { font = L["The face the spell names and amounts are drawn in."] })

-- Window
at(TAB.window, L["Title bar and footer"])
row("window.titleBar", { type = "bool", label = L["Show title bar"], startsLine = true,
    tooltip = L["Show the bar along the top with the HUD's buttons, where you drag it from."] })
row("window.title", { type = "bool", label = L["Show title"],
    tooltip = L["Write Combat Trail in the title bar. Needs Show title bar."] })
row("window.footer", { type = "bool", label = L["Show footer"], startsLine = true,
    tooltip = L["Show the line along the bottom that says what the HUD is doing."] })
at(TAB.window, L["Background"])
colorPair("window", "bg", L["Background color"], L["The fill behind the whole HUD."], {
    companion("window", "bgFromSkin", L["Use the skin's background"],
        L["Fill the HUD in the skin's own color. The background swatch is not read while this is on."]) })
at(TAB.window, L["Border"])
colorPair("window", "border", L["Border color"], L["The edge around the whole HUD."], {
    companion("window", "borderFromSkin", L["Use the skin's color"],
        L["Draw the HUD's edge in the skin's own color. The border swatch is not read while this is on."]) })
at(TAB.window, L["Position"])
row("position.point", { type = "string", label = L["Point"], values = POINTS, validate = POINT_OK, startsLine = true,
    tooltip = L["The point of the HUD that is placed."] })
row("position.relPoint", { type = "string", label = L["Relative point"], values = POINTS, validate = POINT_OK,
    tooltip = L["The point of the screen it is placed at."] })
block(H.PositionBlock({ prefix = "hud.", page = PAGE, group = group, subgroup = subgroup,
    keys = { x = "position.x", y = "position.y" }, defaults = { x = D.position.x, y = D.position.y },
    tooltips = { x = L["Horizontal offset of the HUD from its point, in pixels. Dragging the title bar sets it too."],
                 y = L["Vertical offset of the HUD from its point, in pixels. Dragging the title bar sets it too."] } }))
at(TAB.window, L["Layer"])
row("window.strata", { type = "string", label = L["Frame strata"], values = STRATAS, validate = STRATA_OK,
    startsLine = true, tooltip = H.StrataTooltip(STRATA) })
row("window.alpha", { type = "number", label = L["HUD opacity"], min = 0.1, max = 1, step = 0.05, isPercent = true,
    tooltip = L["How opaque the whole HUD is."] })

-- One running order, so a composed block (which numbers its own rows) sorts where it is declared.
for i, r in ipairs(out) do r.order = i end
NS.RegisterSchemaRows(out)

NS.RegisterTabbedPage({
    key             = PAGE,
    title           = L["DPS HUD"],
    panelName       = "CombatTrailHudPanel",
    defaultsTooltip = L["Restore every DPS HUD setting on this profile to its addon default."],
})
