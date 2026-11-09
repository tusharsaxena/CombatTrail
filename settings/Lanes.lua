local _, NS = ...
-- settings/Lanes.lua — the Lanes page (spec §4, options-ui-§13/§14): the lane picker in the band,
-- and seven tabs under it that edit the lane it names: General, Size and position, Icons, Background
-- and border, Ticks and labels, Visibility and Ignored spells. Also the `/kct lane` verb
-- (NS.Lanes.OnVerb), which writes the same Enable row.
--
-- ONE ROW PER LANE AND SETTING. Every setting is registered twice, `lanes.player.<key>` and
-- `lanes.pet.<key>`, each row stamped with its `lane`. The band's picker is session state (never
-- stored, options-ui-§13): each render hands it to the rows filter as the page ctx's `unit`
-- (NS.SchemaForPage), so every control on screen is bound to the picked lane's own path, and the
-- CLI, the resets and the Defaults reach both lanes as ordinary rows. Picking a lane keeps the tab.
--
-- THE ACTS on the lane (unlock, copy from the other lane, reset, preview) sit on the General tab,
-- the page's first (options-ui-§14's escape). The ignore list is no schema row: the Ignored spells
-- tab draws it through modules/LaneIgnore.lua, and the page's Defaults and Reset lane put it back to
-- its starting spells there.
--
-- COMPOSED BLOCKS (options-ui-§16/§17): the label's Font block, the icon border and the lane border
-- are the library's groups over this addon's keys (`keys`), and every color is a ColorPair with its
-- Use class color companion. The border style rows pick a statusbar texture, which is what the lanes
-- draw their edges with (modules/LaneRender.lua). The skin-following companions (`<key>FromSkin`)
-- arrive with the lanes' skin surfaces (plan Task 5.2).
--
-- WRITES: every row writes through the seam (NS.SetByPath), whose SETTINGS_CHANGED the lane modules
-- already redraw from, so no row carries an onChange.

local L = NS.L
local H = NS.Helpers
local PAGE = "lanes"
local LANES = { "player", "pet" }
local IS_LANE = { player = true, pet = true }
local OTHER = { player = "pet", pet = "player" }
local LANE_NAME = { player = L["Player lane"], pet = L["Pet lane"] }

--- The seven tabs, by the plan's key, in strip order.
NS.LANES_TAB_ORDER = { "general", "size", "icons", "bg", "ticks", "vis", "ignore" }
NS.LANES_TABS = {
    general = L["General"], size = L["Size and position"], icons = L["Icons"],
    bg = L["Background and border"], ticks = L["Ticks and labels"], vis = L["Visibility"],
    ignore = L["Ignored spells"],
}
local TAB = NS.LANES_TABS

local LanesPage = {}
NS.LanesPage = LanesPage
local selected = "player"   -- the band's picker: session state, never stored

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

local DIRECTIONS, DIRECTION_OK = choices(
    "left", L["Newest at the right, moving left"], "right", L["Newest at the left, moving right"],
    "up", L["Newest at the bottom, moving up"], "down", L["Newest at the top, moving down"])
local MODES, MODE_OK = choices(
    "free", L["Free"], "dock", L["Docked to the other lane"], "unit", L["Unit frame"])
local POINTS, POINT_OK = choices(
    "TOPLEFT", L["Top left"], "TOP", L["Top"], "TOPRIGHT", L["Top right"], "LEFT", L["Left"],
    "CENTER", L["Center"], "RIGHT", L["Right"], "BOTTOMLEFT", L["Bottom left"], "BOTTOM", L["Bottom"],
    "BOTTOMRIGHT", L["Bottom right"])
local SPACINGS, SPACING_OK = choices(
    "gcd15", L["Every 1.5 seconds"], "haste", L["Your global cooldown, with haste"], "1s", L["Every second"])
local LABEL_SIDES, LABEL_SIDE_OK = choices(
    "LEFT", L["Left"], "RIGHT", L["Right"], "TOP", L["Top"], "BOTTOM", L["Bottom"])
local SHOWS, SHOW_OK = choices(
    "always", L["Always"], "combat", L["In combat only"], "combatOrTarget", L["In combat or with a target"],
    "never", L["Never"])

-- frame-layering-§1: a player-chosen strata offers BACKGROUND to HIGH. Match host joins them while
-- the lane is on a unit frame (spec §4), or while it is stored.
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH" }
local STRATA_TEXT = { BACKGROUND = L["Background"], LOW = L["Low"], MEDIUM = L["Medium"],
                      HIGH = L["High"], HOST = L["Match host"] }
local STRATA_OK = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, HOST = true }

local function strataValues(lane)
    return function()
        local out = {}
        for i, k in ipairs(STRATA) do out[i] = { value = k, text = STRATA_TEXT[k] } end
        local P = "lanes." .. lane .. "."
        if NS.GetSetting(P .. "anchor.mode") == "unit" or NS.GetSetting(P .. "strata") == "HOST" then
            out[#out + 1] = { value = "HOST", text = STRATA_TEXT.HOST }
        end
        return out
    end
end

-- The Where rows, in the Visibility tab's order. Delves and arenas are Retail-only: on WoW Forever
-- their keys are absent from the defaults (defaults/Profile.lua), so their rows are never built.
local WHERE = {
    { "world", L["Open world"] }, { "dungeon", L["Dungeons"] }, { "raid", L["Raids"] },
    { "delve", L["Delves"], { "retail" } }, { "bg", L["Battlegrounds"] }, { "arena", L["Arenas"], { "retail" } },
}

-- ── the rows of one lane ───────────────────────────────────────────────────────────────────────

local function read(t, key)
    for part in key:gmatch("[^.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

local PLAYER_CLASS = { source = "player" }

-- One lane's rows, built tab by tab into `out` (declaration order is the drawn order).
local function laneRows(lane)
    local D = NS.defaults.profile.lanes[lane]
    local P = "lanes." .. lane .. "."
    local out = {}
    local group, subgroup
    local function at(g, s) group, subgroup = g, s end
    -- A hand row: `key` relative to the lane, its default read from the lane's defaults.
    local function row(key, t)
        t.path, t.page, t.group, t.subgroup = P .. key, PAGE, group, subgroup
        t.default = read(D, key)
        out[#out + 1] = t
        return t
    end
    -- A composed block: the library's words, this lane's keys.
    local function block(rows)
        for _, r in ipairs(rows) do
            r.composed = true
            out[#out + 1] = r
        end
        return rows
    end
    local function spec(t)
        t.prefix, t.page, t.group, t.subgroup, t.classColor = P, PAGE, group, subgroup, PLAYER_CLASS
        return t
    end
    local function colorPair(key, companion, label)
        return block(H.ColorPair(spec({ key = key, companionKey = companion, label = label,
            defaults = { [key] = D[key], [companion] = D[companion] } })))
    end
    -- A border style row picks a statusbar texture: the edges are strips (modules/LaneRender.lua).
    local function statusbarStyle(rows, tooltip)
        for _, r in ipairs(rows) do
            if r.dialogControl == "Ka0sMedia_Border" then
                r.dialogControl, r.values, r.tooltip = "Ka0sMedia_Statusbar", H.LSMValues("statusbar"), tooltip
            end
        end
    end

    -- General
    at(TAB.general, L["Lane"])
    row("enabled", { type = "bool", label = L["Enable this lane"],
        tooltip = L["Show this lane and listen for its casts. Off, it draws nothing and listens for nothing."] })

    -- Size and position
    at(TAB.size, L["Size"])
    row("direction", { type = "string", label = L["Direction"], values = DIRECTIONS, validate = DIRECTION_OK,
        tooltip = L["Which edge the newest cast appears at, and which way the casts move away from it."] })
    row("scale", { type = "number", label = L["Scale"], min = 0.5, max = 2, step = 0.05, isPercent = true,
        tooltip = L["The size of the whole lane, its icons, ticks and label included."] })
    row("width", { type = "number", label = L["Lane length"], min = 100, max = 1200, step = 10, startsLine = true,
        tooltip = L["How long the lane is, in pixels, from the now edge to the far end."] })
    row("seconds", { type = "number", label = L["Seconds shown"], min = 3, max = 30, step = 1,
        tooltip = L["How many seconds a cast takes to cross the lane."] })
    row("iconSize", { type = "number", label = L["Icon size"], min = 12, max = 64, step = 1, startsLine = true,
        tooltip = L["The size of each cast's icon, in pixels. The lane is this tall, or this wide when it runs up or down."] })
    row("spacing", { type = "number", label = L["Icon spacing"], min = 0, max = 20, step = 1,
        tooltip = L["The smallest gap between two icons, in pixels. A fast burst of casts pushes older icons along to keep it."] })

    at(TAB.size, L["Position"])
    local mode = P .. "anchor.mode"
    row("anchor.mode", { type = "string", label = L["Anchor"], values = MODES, validate = MODE_OK,
        tooltip = L["Free: the lane sits where you put it. Docked: it follows the other lane. Unit frame: it follows your unit frame (the pet's for the Pet lane), from ElvUI, Shadowed Unit Frames, Cell, PitBull, UnhaltedUnitFrames or the game's own."] })
    row("anchor.frameName", { type = "string", label = L["Frame by name"],
        shownWhen = { path = mode, equals = "unit" },
        tooltip = L["The name of any frame to sit on instead of the one found for you. Empty finds it for you."] })
    row("anchor.point", { type = "string", label = L["Point"], values = POINTS, validate = POINT_OK, startsLine = true,
        tooltip = L["The point of the lane that is placed."] })
    row("anchor.relPoint", { type = "string", label = L["Relative point"], values = POINTS, validate = POINT_OK,
        tooltip = L["The point it is placed at: on the screen, on the other lane or on the unit frame."] })
    row("anchor.gap", { type = "number", label = L["Gap"], min = 0, max = 50, step = 1, startsLine = true,
        shownWhen = { path = mode, equals = { "dock", "unit" } },
        tooltip = L["The space between the lane and what it follows, in pixels."] })
    block(H.PositionBlock(spec({ keys = { x = "anchor.x", y = "anchor.y" }, subgroup = L["Position"],
        defaults = { x = D.anchor.x, y = D.anchor.y },
        tooltips = { x = L["Horizontal offset of the lane's own place, in pixels. A docked lane, or one on its unit frame, uses it when what it follows is missing."],
                     y = L["Vertical offset of the lane's own place, in pixels. A docked lane, or one on its unit frame, uses it when what it follows is missing."] } })))

    at(TAB.size, L["Layer"])
    row("strata", { type = "string", label = L["Frame strata"], values = strataValues(lane),
        validate = function(v) return STRATA_OK[v] == true end, startsLine = true,
        tooltip = H.StrataTooltip(STRATA) .. " " .. L["Match host draws the lane on its unit frame's strata, and is offered while the lane is on one."] })
    row("levelOffset", { type = "number", label = L["Frame level"], min = 0, max = 50, step = 1,
        tooltip = L["Added to the lane's level on its strata. Raise it to draw this lane over a frame on the same strata."] })

    -- Icons
    at(TAB.icons, L["Icons"])
    row("zoom", { type = "number", label = L["Icon zoom"], min = 0, max = 0.4, step = 0.01, isPercent = true,
        tooltip = L["How much of each icon's edge is cropped away."] })
    row("fade", { type = "number", label = L["Fade portion"], min = 0, max = 1, step = 0.05, isPercent = true,
        tooltip = L["How much of the lane, at its far end, icons fade out over. 0 never fades."] })
    row("markInterrupted", { type = "bool", label = L["Mark interrupted casts"], startsLine = true,
        tooltip = L["Draw a red X on a cast that was interrupted or canceled after it started."] })
    row("stack", { type = "bool", label = L["Stack repeated casts"],
        tooltip = L["Fold a cast of the same spell as the newest icon into it, with a count, instead of a new icon."] })
    row("tooltip", { type = "bool", label = L["Show spell tooltip"], startsLine = true,
        tooltip = L["Show the spell's tooltip while the mouse is over its icon. Off, the icons let the mouse through."] })
    row("showName", { type = "bool", label = L["Show spell name"],
        tooltip = L["Write each spell's name under its icon."] })

    at(TAB.icons, L["Border"])
    local iconBorder = block(H.BorderGroup(spec({ show = true,
        keys = { borderShow = "border", borderStyle = "borderTexture", borderSize = "borderSize",
                 borderColor = "borderColor", useClassColorBorder = "borderClassColor" },
        defaults = { borderShow = D.border, borderStyle = D.borderTexture, borderSize = D.borderSize,
                     borderColor = D.borderColor, useClassColorBorder = D.borderClassColor } })))
    statusbarStyle(iconBorder, L["The texture each icon's border is drawn with. Empty draws it flat."])

    at(TAB.icons, L["Glow"])
    row("glowLongCD", { type = "bool", label = L["Glow long cooldowns"], startsLine = true,
        tooltip = L["Ring the icon of a spell with a long cooldown, read from the spell's base cooldown."] })
    row("glowMinCD", { type = "number", label = L["Long cooldown (s)"], min = 5, max = 300, step = 1,
        tooltip = L["The shortest base cooldown, in seconds, that glows."] })
    colorPair("glowColor", "glowClassColor", L["Glow color"])

    -- Background and border
    at(TAB.bg, L["Background"])
    row("background", { type = "bool", label = L["Show background"], startsLine = true,
        tooltip = L["Fill the lane behind its icons."] })
    row("bgTexture", { type = "string", label = L["Background texture"], dialogControl = "Ka0sMedia_Statusbar",
        values = H.LSMValues("statusbar"),
        tooltip = L["The texture the background is drawn with, tinted by its color. Empty fills it flat."] })
    colorPair("bgColor", "bgClassColor", L["Background color"])
    row("padding", { type = "number", label = L["Padding"], min = 0, max = 20, step = 1, startsLine = true,
        tooltip = L["Space between the lane's edge and its icons, in pixels."] })

    at(TAB.bg, L["Border"])
    local laneBorder = block(H.BorderGroup(spec({ show = true,
        keys = { borderShow = "laneBorder", borderStyle = "laneBorderTexture", borderSize = "laneBorderSize",
                 borderColor = "laneBorderColor", useClassColorBorder = "laneBorderClassColor" },
        defaults = { borderShow = D.laneBorder, borderStyle = D.laneBorderTexture, borderSize = D.laneBorderSize,
                     borderColor = D.laneBorderColor, useClassColorBorder = D.laneBorderClassColor } })))
    statusbarStyle(laneBorder, L["The texture the lane's border is drawn with. Empty draws it flat."])

    -- Ticks and labels
    at(TAB.ticks, L["Ticks"])
    row("ticks", { type = "bool", label = L["Show GCD ticks"], startsLine = true,
        tooltip = L["Draw a thin line across the lane at each global cooldown back from now."] })
    row("tickSpacing", { type = "string", label = L["Tick spacing"], values = SPACINGS, validate = SPACING_OK,
        tooltip = L["How far apart the ticks are. With haste, they follow your global cooldown, read out of combat."] })
    row("tickWidth", { type = "number", label = L["Tick width"], min = 1, max = 6, step = 1, startsLine = true,
        tooltip = L["How thick each tick is, in pixels."] })
    colorPair("tickColor", "tickClassColor", L["Tick color"])

    at(TAB.ticks, L["Now line"])
    row("now", { type = "bool", label = L["Show now line"], startsLine = true,
        tooltip = L["Draw a line at the edge where each cast appears."] })
    colorPair("nowColor", "nowClassColor", L["Now line color"])

    at(TAB.ticks, L["Label"])
    row("label", { type = "bool", label = L["Show label"], startsLine = true,
        tooltip = L["Name the lane beside it."] })
    row("labelPosition", { type = "string", label = L["Label position"], values = LABEL_SIDES, validate = LABEL_SIDE_OK,
        tooltip = L["Which side of the lane the label sits on."] })
    row("labelText", { type = "string", label = L["Label text"], startsLine = true,
        tooltip = lane == "pet" and L["The label's words. Empty shows your pet's name, or Pet with no pet out."]
            or L["The label's words. Empty shows You."] })

    at(TAB.ticks, L["Label font"])
    block(H.FontGroup(spec({
        keys = { font = "labelFont", fontSize = "labelSize", fontColor = "labelColor",
                 useClassColorFont = "labelClassColor", fontFlags = "labelOutline", fontShadow = "labelShadow" },
        defaults = { font = D.labelFont, fontSize = D.labelSize, fontColor = D.labelColor,
                     useClassColorFont = D.labelClassColor, fontFlags = D.labelOutline, fontShadow = D.labelShadow },
        tooltips = { font = L["The face the label is drawn in. Empty uses the skin's font."] } })))

    -- Visibility
    at(TAB.vis, L["When"])
    row("visibility.show", { type = "string", label = L["Show the lane"], values = SHOWS, validate = SHOW_OK,
        tooltip = L["When the lane shows. In combat or with a target also shows it while you have something targeted."] })
    row("visibility.hideAfter", { type = "number", label = L["Hide after combat (s)"], min = 0, max = 60, step = 1,
        tooltip = L["How long the lane stays after combat ends, in seconds, when it shows in combat only."] })
    row("visibility.alphaCombat", { type = "number", label = L["Opacity in combat"], min = 0, max = 1, step = 0.05,
        isPercent = true, startsLine = true, tooltip = L["How opaque the whole lane is while you are in combat."] })
    row("visibility.alphaOOC", { type = "number", label = L["Opacity out of combat"], min = 0, max = 1, step = 0.05,
        isPercent = true, tooltip = L["How opaque the whole lane is out of combat."] })

    at(TAB.vis, L["Where"])
    for _, w in ipairs(WHERE) do
        if D.visibility.where[w[1]] ~= nil then
            row("visibility.where." .. w[1], { type = "bool", label = w[2], clients = w[3],
                tooltip = L["Show the lane here. Off, it hides here whatever the rules above say."] })
        end
    end

    at(TAB.vis, L["Hide when"])
    row("visibility.hideMounted", { type = "bool", label = L["Mounted"], startsLine = true,
        tooltip = L["Hide the lane while you are mounted."] })
    row("visibility.hideVehicle", { type = "bool", label = L["In a vehicle"],
        tooltip = L["Hide the lane while you are in a vehicle."] })
    row("visibility.hidePetBattle", { type = "bool", label = L["In a pet battle"], startsLine = true,
        tooltip = L["Hide the lane during a pet battle."] })
    row("visibility.hideResting", { type = "bool", label = L["Resting"],
        tooltip = L["Hide the lane while you rest in a city or an inn."] })

    -- One running order, so a composed block (which numbers its own rows) sorts where it is declared.
    for i, r in ipairs(out) do
        r.lane, r.order = lane, i
    end
    return out
end

for _, lane in ipairs(LANES) do NS.RegisterSchemaRows(laneRows(lane)) end

--- The schema rows of one lane, in page order.
function LanesPage.Rows(lane)
    local out = {}
    for _, row in ipairs(NS.SchemaForPage(PAGE, lane)) do
        if row.lane == lane then out[#out + 1] = row end
    end
    return out
end

-- ── the acts ───────────────────────────────────────────────────────────────────────────────────

local function redraw()
    local ctx = NS.pageCtx and NS.pageCtx[PAGE]
    if ctx then H.RefreshPanel(ctx, true) end
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

--- The lane the band's picker names.
function LanesPage.Selected() return selected end

--- Pick the lane every tab edits (the band's picker; session only). Keeps the tab.
function LanesPage.Select(lane)
    if not IS_LANE[lane] then return false end
    selected = lane
    redraw()
    return true
end

-- What Copy from leaves alone: where the lane sits, its own words, its switch. The ignore list is
-- no row, so it stays the lane's own too.
local COPY_SKIP = { enabled = true, labelText = true }

--- Copy every setting of lane `from` onto lane `to`, but its place (anchor), its label text and its
--- switch, through the write seam.
function LanesPage.CopyFrom(from, to)
    if not (IS_LANE[from] and IS_LANE[to]) or from == to then return false end
    local prefix = "lanes." .. to .. "."
    NS.Bulk.Run("copy", "lanes." .. to, function()
        for _, row in ipairs(LanesPage.Rows(to)) do
            local rel = row.path:sub(#prefix + 1)
            if not COPY_SKIP[rel] and not rel:match("^anchor%.") then
                NS.SetByPath(row.path, copy(NS.GetSetting("lanes." .. from .. "." .. rel)))
            end
        end
    end)
    redraw()
    NS.Print(L["The %s now looks like the %s."]:format(LANE_NAME[to], LANE_NAME[from]))
    return true
end

--- Reset lane's accept: every row of that lane to its default, and its ignore list to its starting
--- spells. The other lane is untouched.
function LanesPage.AcceptReset(lane)
    if not IS_LANE[lane] then return false end
    NS.Bulk.Run("reset", "lanes." .. lane, function()
        for _, row in ipairs(LanesPage.Rows(lane)) do NS.ApplyDefault(row) end
    end)
    NS.LaneIgnore.ResetToSeed(lane)
    redraw()
    NS.Print(L["The %s is back to its defaults."]:format(LANE_NAME[lane]))
    return true
end

StaticPopupDialogs["COMBATTRAIL_RESET_LANE"] = {
    text         = L["Reset the %s to its defaults? Every setting on its tabs goes back, and so does its ignore list. The other lane is not affected."],
    button1      = L["Yes"],
    button2      = L["No"],
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept     = function(_, lane) LanesPage.AcceptReset(lane) end,
}

--- Reset lane asks first, naming the lane.
function LanesPage.ConfirmReset(lane)
    return StaticPopup_Show("COMBATTRAIL_RESET_LANE", LANE_NAME[lane], nil, lane)
end

-- The preview's casts: icon file IDs the client ships, oldest first, the third one interrupted.
local PREVIEW = { 135808, 136048, 135812, 136075, 132369 }
local PREVIEW_STEP = 1.6

--- Fill a lane with a few made-up casts, so its look shows on screen. Nothing is recorded.
function LanesPage.Preview(lane)
    local R = NS.LaneRender
    if not (IS_LANE[lane] and R) then return 0 end
    if NS.GetSetting("lanes." .. lane .. ".enabled") == false then
        NS.Print(L["The %s is switched off. Enable it to see the preview."]:format(LANE_NAME[lane]))
        return 0
    end
    R.Clear(lane)
    local now = GetTime()
    for i, texture in ipairs(PREVIEW) do
        R.Push(lane, { texture = texture, t = now - (#PREVIEW - i) * PREVIEW_STEP, interrupted = i == 3 })
    end
    local n = #(R.__icons(lane) or {})
    if n == 0 then
        NS.Print(L["The %s is hidden by its Visibility tab right now. Unlock the lanes to see it."]:format(LANE_NAME[lane]))
    end
    return n
end

-- ── `/kct lane player|pet on|off` ──────────────────────────────────────────────────────────────

--- The `lane` verb (settings/Slash.lua): the lane's Enable row, through the seam. With no on or off,
--- it flips the lane.
function NS.Lanes.OnVerb(rest)
    local lane, state = tostring(rest or ""):lower():match("^%s*(%S*)%s*(%S*)")
    local path = "lanes." .. tostring(lane) .. ".enabled"
    local want
    if state == "on" then want = true
    elseif state == "off" then want = false
    elseif state == "" then want = NS.GetSetting(path) == false end
    if not IS_LANE[lane] or want == nil then
        return NS.Print(L["Usage: /kct lane player|pet on|off"])
    end
    NS.SetByPath(path, want)
    NS.Print((want and L["The %s is on."] or L["The %s is off."]):format(LANE_NAME[lane]))
end

-- ── the page ───────────────────────────────────────────────────────────────────────────────────

-- The General tab: the lane's rows, then its acts (options-ui-§14's General escape).
local UNLOCK_ROW = {
    type = "bool", page = PAGE, group = TAB.general, subgroup = L["Lane"], label = L["Unlock the lanes"],
    tooltip = L["Show the lanes' move boxes so you can drag them, as /kct unlock does. Both lanes unlock together."],
    get = function() return NS.LaneAnchor ~= nil and NS.LaneAnchor.IsUnlocked() end,
    set = function(on) if NS.LaneAnchor then NS.LaneAnchor.SetUnlocked(on and true or false) end end,
}

local GENERAL_TAB = {
    key = TAB.general, label = TAB.general,
    render = function(ctx, rows)
        local drawn = {}
        for _, r in ipairs(rows or {}) do drawn[#drawn + 1] = r end
        drawn[#drawn + 1] = UNLOCK_ROW
        H.RenderRows(ctx, drawn, nil, nil, { noHeadings = true })
        local lane = selected
        H.InlineButtonPair(ctx,
            { text = L["Copy from %s"]:format(LANE_NAME[OTHER[lane]]),
              tooltip = L["Give this lane every setting of the other lane, except where it sits, its label text and its switch."],
              onClick = function() LanesPage.CopyFrom(OTHER[lane], lane) end },
            { text = L["Reset lane"],
              tooltip = L["Put every setting of this lane back to its default, its ignore list included. Asks first."],
              onClick = function() LanesPage.ConfirmReset(lane) end })
        H.InlineButtonPair(ctx,
            { text = L["Preview lane"],
              tooltip = L["Fill this lane with a few made-up casts, so you can see its look while you change it."],
              onClick = function() LanesPage.Preview(lane) end }, nil)
    end,
}

-- The Ignored spells tab: the lane's list, with an add box, and the way back to its starting spells.
local IGNORE_TAB = {
    key = TAB.ignore, label = TAB.ignore,
    tooltip = L["The spells this lane never shows."],
    render = function(ctx)
        local lane = selected
        H.IdList(ctx, {
            kind      = "spell",
            label     = L["Add a spell"],
            tooltip   = L["Type a spell's ID or name, or shift-click its link, to stop this lane showing it."],
            entries   = function()
                local out = {}
                for i, id in ipairs(NS.LaneIgnore.Entries(lane)) do out[i] = { id = id } end
                return out
            end,
            onAdd     = function(id) NS.LaneIgnore.Add(lane, id) end,
            onRemove  = function(id) NS.LaneIgnore.Remove(lane, id) end,
            emptyText = L["This lane ignores no spells."],
        })
        H.InlineButtonPair(ctx,
            { text = L["Reset to starting spells"],
              tooltip = L["Put this lane's list back to the spells it ignores out of the box."],
              onClick = function()
                  NS.LaneIgnore.ResetToSeed(lane)
                  redraw()
              end }, nil)
    end,
}

--- The page's two host tabs, General (in its group's place) and Ignored spells (last).
LanesPage.HOST_TABS = { GENERAL_TAB, IGNORE_TAB }

NS.RegisterTabbedPage({
    key             = PAGE,
    title           = L["Lanes"],
    panelName       = "CombatTrailLanesPanel",
    defaultsTooltip = L["Restore every setting of both lanes on this profile to its addon default, their ignore lists included."],
    tabs            = LanesPage.HOST_TABS,
    unit            = function() return selected end,
    banner          = function(ctx)
        H.PageBanner(ctx, {
            label    = L["Lane"],
            list     = { player = LANE_NAME.player, pet = LANE_NAME.pet },
            order    = LANES,
            value    = selected,
            tooltip  = L["The lane every tab below edits."],
            onSelect = function(lane) LanesPage.Select(lane) end,
        })
    end,
    afterDefaults   = function()
        for _, lane in ipairs(LANES) do NS.LaneIgnore.ResetToSeed(lane) end
    end,
    -- The Defaults can change what a selector picks (the anchor mode), so the page redraws.
    redrawOnDefaults = true,
})
