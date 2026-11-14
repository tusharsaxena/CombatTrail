local _, NS = ...
-- settings/Race.lua — the Race mode page (Race mode spec §8, plan Task B3), Retail only: three tabs in
-- strip order. Race holds the switch first (`race.enabled`: off stops new races, NS.RaceMode.On()),
-- then DPS Race's Race section in the order of a race: the length a race arms at, auto-show (and the
-- DPS HUD opening with it, drawn disabled while auto-show is off: disabledIf) and auto-arm near a
-- training dummy (modules/AutoArm.lua), the race clock's mode, the countdown (when the call-out
-- counts, and from what second; its look and voice are the call-out's own settings), the
-- buzzer's STOP with the sticky-combat hint's delay, and the scoring rules a new race freezes into its part
-- (grace, restart gap). Late-cast ignore list holds the list (modules/LateIgnore.lua), read when a
-- race's flags are, drawn as the library's spell ID list. Race window holds where the window stands:
-- attached beside the DPS HUD, and on which side (Task C1 reads both), and whether, on the left or
-- right, it takes the HUD's height (race window redesign plan Task W4); its width and height, written
-- by its grip, are rows the tab does not draw (skipRender). The Race window's look is the
-- DPS HUD page's appearance blocks (spec §8), so it has no styling rows here; its lock is Master
-- controls' Lock frame (general.locked), as every placed frame's is.
--
-- NOT HERE: the training dummies are the History page's (Task A2), and so is the New-best toast section
-- (Task C2, ruling X19: a fight's toast is on both clients and this page is Retail's, so the section
-- stands on a page both have, with only its races row Retail's).
--
-- CLIENTS (clients-§4). The page is declared `clients = { "retail" }` (the library never builds it on
-- WoW Forever), and its rows are registered only on Retail, each declared retail too: WoW Forever has
-- no row, no `/ct get` path and no label naming Race mode. The race table's shared keys (the length,
-- the scoring rules, the late-cast list) keep their defaults there, as a saved race re-scores on any
-- client (defaults/Profile.lua).
--
-- THE CALL-OUT'S TAB (callout plan rows C5, C11): one "Callout" tab after the Race tab,
-- LibKa0s-Callout-1.0's own settings section, drawn by its SettingsTab (a Preview block over the
-- Look and Sound side tabs, BuildSettings' `layout = "side"`) with this addon's Options instance
-- (NS.Helpers) on the host's write route. Its rows are the instance's SchemaRows("callout.",
-- { texts = false }), registered here as this page's rows (so `/ct get|set|list|reset`, the page's
-- Defaults, the global reset and the boot check all reach them), each declared retail like every
-- row here, and skipRender: the section draws its own copy of each, by the same path, read and
-- written through the Options descriptor, so through NS.SetByPath. Every row's group is the one
-- tab's key (`callout`), so the tab takes the group's place in the strip. `texts = false` leaves
-- out the stock texts' words and mutes (owner, 2026-11-14): the words the call-out says are the
-- addon's, so no row, and the seam refuses `callout.texts.*` and `callout.muted.*`. Their AceDB
-- defaults are seeded from the rows, before AceDB:New (the library's docs/api/Callout version 3.4,
-- Adopting it), and the drag's `callout.point` from the instance's default place; that path is the
-- schema's writeThrough (settings/Schema.lua).
--
-- WRITES: every row writes through the seam (NS.SetByPath). The race reads its keys at call time and
-- freezes grace and the restart gap into each race as it arms; a new default length forgets the last
-- one armed (Race.ForgetLength); auto-show, its DPS HUD row, auto-arm and the switch re-sync AutoArm,
-- and the switch going off (or a profile that has it off) cancels a race still armed.
-- The countdown re-arms the race's call-out off its rows' SETTINGS_CHANGED and the buzzer reads its row
-- as it says STOP (modules/Countdown.lua); the Race window reads its keys off SETTINGS_CHANGED (Task C1).

local L = NS.L
local PAGE = "race"
local RETAIL = { "retail" }

if not NS.Compat.ForClient(RETAIL) then return end

local D = NS.defaults.profile

--- The three tabs, in strip order.
NS.RACE_TABS = { race = L["Race"], late = L["Late-cast ignore list"], window = L["Race window"] }
local TAB = NS.RACE_TABS

local RacePage = {}
NS.RacePage = RacePage

-- ── the rows ───────────────────────────────────────────────────────────────────────────────────

local function within(lo, hi, step)
    return function(v)
        if type(v) ~= "number" or v < lo or v > hi then return false end
        return step == nil or math.abs(v / step - math.floor(v / step + 0.5)) < 1e-6
    end
end

local function oneOf(list)
    local set = {}
    for _, item in ipairs(list) do set[type(item) == "table" and item.value or item] = true end
    return function(v) return set[v] == true end
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

-- A row at profile path `path`, its default read from the profile's defaults, declared retail.
local function row(path, t)
    t.path, t.page, t.group, t.subgroup, t.clients = path, PAGE, group, subgroup, RETAIL
    t.default = read(D, path)
    out[#out + 1] = t
    return t
end

local function syncAutoArm() NS.AutoArm.Sync() end

-- The presets a race offers (Race.LENGTHS), as a numeric dropdown: "3:00" for 180.
local LENGTHS = {}
for i, n in ipairs(NS.Race.LENGTHS) do LENGTHS[i] = { value = n, text = NS.Format.Length(n) } end

local CLOCKS = {
    { value = "both", text = L["Elapsed and time left"] },
    { value = "left", text = L["Time left"] },
    { value = "elapsed", text = L["Elapsed"] },
}

local SIDES = {
    { value = "RIGHT", text = L["Right"] }, { value = "LEFT", text = L["Left"] },
    { value = "TOP", text = L["Top"] }, { value = "BOTTOM", text = L["Bottom"] },
}

-- Race: the switch first, then the race's own order.
at(TAB.race, L["Race mode"])
-- Off: an armed race (no first hit yet) is canceled with it; a race already running runs on to its result.
-- A profile switch, copy or reset that lands on Race mode off does the same (the bus receiver below),
-- so no race starts while Race mode is off.
local function cancelArmedIfOff()
    if not NS.RaceMode.On() and NS.Race.State() == NS.Race.STATE.ARMED then NS.Race.Cancel() end
end

local function onSwitch()
    syncAutoArm()
    cancelArmedIfOff()
end

row("race.enabled", { type = "bool", label = L["Race mode"], startsLine = true, onChange = onSwitch,
    tooltip = L["Time a fight on a training dummy against a set length, and keep your best on each dummy and length. Off, no new race starts: the Race window stays hidden and nothing is shown or armed by itself. Your saved races stay in your history."] })

at(TAB.race, L["Length"])
row("race.defaultLength", { type = "number", label = L["Default race length"], values = LENGTHS,
    validate = oneOf(LENGTHS), onChange = function() NS.Race.ForgetLength() end,
    tooltip = L["The race length the Race window offers until you pick another. The last length you arm is remembered until you change this."] })

at(TAB.race, L["Near a training dummy"])
row("race.autoShow", { type = "bool", label = L["Show the Race window near a training dummy"], startsLine = true,
    onChange = syncAutoArm,
    tooltip = L["Open the Race window by itself, with the DPS HUD beside it, while a training dummy is your target or has its nameplate up, outside instances. It closes a few seconds after the last one is gone, and stays closed once you close it until you next come near one."] })
-- Either row is auto-show (owner, 2026-11-13, race window redesign plan W29 decision D4): the Race
-- window never shows without the DPS HUD, so each opens both, and neither depends on the other.
row("race.autoShowHud", { type = "bool", label = L["Show the DPS HUD near a training dummy"], startsLine = true,
    onChange = syncAutoArm,
    tooltip = L["Open the DPS HUD by itself near a training dummy, with the Race window beside it: the Race window never shows without the DPS HUD, so this or Show the Race window near a training dummy opens both. The DPS HUD fades after a fight by its own rules and takes the Race window with it; both come back the next time a dummy is targeted or comes into view. Both close a few seconds after the last dummy is gone, unless a fight is on the DPS HUD or you opened or pinned it yourself. Once you close either, they stay closed until you next come near a dummy."] })
row("race.autoArm", { type = "bool", label = L["Arm on a training dummy"], startsLine = true, onChange = syncAutoArm,
    tooltip = L["Arm a race by itself when you target a training dummy out of combat, at the length Arm Race would use; your first hit starts it. Targeting anything else (or nothing) before the pull cancels it. Nothing arms in combat, in instances, over a result, or while a race waits for its result."] })

at(TAB.race, L["Clock"])
row("race.clock", { type = "string", label = L["Race clock"], values = CLOCKS, validate = oneOf(CLOCKS),
    startsLine = true,
    tooltip = L["What the Race window's clock shows while a race runs: the time elapsed and the time left side by side, or one of them alone, drawn larger."] })

at(TAB.race, L["Countdown"])
row("race.centerCountdown", { type = "bool", label = L["Center-screen countdown"], startsLine = true,
    tooltip = L["Large numbers in the middle of the screen for the last seconds of the race, one a second down to 1, like a pull timer. Only you see them."] })
row("race.finalCountdown", { type = "number", label = L["Center countdown from (seconds)"],
    min = NS.Countdown.MIN, max = NS.Countdown.MAX, step = 1, validate = within(NS.Countdown.MIN, NS.Countdown.MAX, 1),
    tooltip = L["How many seconds before the buzzer the center countdown starts. 3 to 20. Numbers above the call-out's Speak numbers from are shown, not said."] })

at(TAB.race, L["At the buzzer"])
row("race.buzzer", { type = "bool", label = L["STOP at the buzzer"], startsLine = true,
    tooltip = L["The call-out in the middle of the screen says STOP, in its voice, the moment the race ends."] })
row("race.hintDelay", { type = "number", label = L["Sticky-combat hint after (seconds)"], min = 5, max = 60, step = 1,
    validate = within(5, 60, 1),
    tooltip = L["How long combat may hold after the buzzer before the Race window suggests ways to drop it. 5 to 60 seconds."] })

at(TAB.race, L["Scoring rules"])
row("race.grace", { type = "number", label = L["Late-cast grace (seconds)"], min = 0, max = 5, step = 0.1,
    validate = within(0, 5, 0.1), startsLine = true,
    tooltip = L["A cast that starts later than this after the buzzer flags the race. 0 to 5 seconds. Applies to new races. Saved races keep the value they were raced with."] })
row("race.restartGap", { type = "number", label = L["Damage-restart gap (seconds)"], min = 3, max = 15, step = 1,
    validate = within(3, 15, 1),
    tooltip = L["Your damage going quiet for this long after the buzzer, then landing again, flags the race as damage restarted. 3 to 15 seconds. Applies to new races. Saved races keep the value they were raced with."] })

-- The call-out's tab (THE CALL-OUT'S TAB, above), in the library's own words ("Callout").
local CALLOUT_TAB = "callout"

local function copyOf(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copyOf(x) end
    return t
end

do
    local prefix = NS.Countdown.PREFIX
    local rows, named = NS.Callout:SchemaRows(prefix, { page = PAGE, texts = false })
    local Write = NS.__schemaLib.Write
    for _, r in ipairs(rows) do
        r.clients, r.skipRender = RETAIL, true
        r.group = CALLOUT_TAB
        if not r.sessionOnly then Write(D, r.path, copyOf(r.default)) end
        out[#out + 1] = r
    end
    if named[1] then Write(D, named[1], copyOf(NS.Callout:Get("point"))) end
end

-- Late-cast ignore list: one plain string of spell IDs written WHOLE through the seam (the Usage tab's
-- hidden items' shape, settings/History.lua), so the CLI and the page's Defaults reach it like any row.
-- It carries skipRender: the tab draws it as the library's ID list (afterLate).
at(TAB.late, nil)
row(NS.LateIgnore.PATH, { type = "string", label = L["Late-cast ignore list"], skipRender = true,
    validate = function(v) return NS.LateIgnore.Parse(v) ~= nil end,
    normalize = function(v) return NS.LateIgnore.Normalize(v) end,
    tooltip = L["Spell IDs, comma-separated, whose casts after the grace never flag a race. Applies to every saved race: a race keeps its casts, so taking a spell off the list flags them again. Unlike the grace, nothing is frozen into a race. 8690 stands for every hearthstone."] })

-- Race window: where it stands (Task C1).
at(TAB.window, nil)
row("raceWindow.attached", { type = "bool", label = L["Attach to the DPS HUD"], startsLine = true,
    tooltip = L["Keep the Race window beside the DPS HUD, moving with it. Off, it stands on its own wherever you drag it; Lock frame on the General page holds it in place."] })
row("raceWindow.side", { type = "string", label = L["Side of the DPS HUD"], values = SIDES, validate = oneOf(SIDES),
    tooltip = L["Which side of the DPS HUD the attached Race window stands on."] })
row("raceWindow.matchHud", { type = "bool", label = L["Match the DPS HUD's height"], startsLine = true,
    tooltip = L["Attached on the left or right of the DPS HUD, the Race window takes the HUD's height and keeps it as the HUD resizes, never shorter than it needs. Above or below the HUD, or on its own, it keeps its own height."] })
-- Its size, written by its grip (owner, 2026-11-13): skipRender, the grip is their control; the
-- tab's Defaults and the CLI reach them like any row.
row("raceWindow.width", { type = "number", label = L["Race window width (px)"], min = NS.RaceWindow.WIDTH,
    max = NS.RaceWindow.MAX_WIDTH, step = 1, validate = within(NS.RaceWindow.WIDTH, NS.RaceWindow.MAX_WIDTH, 1),
    skipRender = true })
row("raceWindow.height", { type = "number", label = L["Race window height (px)"], min = 0,
    max = NS.RaceWindow.MAX_HEIGHT, step = 1, validate = within(0, NS.RaceWindow.MAX_HEIGHT, 1),
    skipRender = true })

for i, r in ipairs(out) do r.order = i end
NS.RegisterSchemaRows(out)

-- ── the tabs' bodies ────────────────────────────────────────────────────────────────────────────

-- Before the Race tab's rows: the page's one history note (the plan's Words rule).
local function beforeRace(ctx)
    NS.Helpers.TextRow(ctx, L["Race mode is DPS Race, now part of Combat Trail: a race is a fight on a training dummy, timed to a set length and kept in your history."])
end

-- The Late-cast ignore list's body, after its one skipRender row: a blurb, the library's ID list (an
-- add box over one line per listed spell, each with its X), then the list's own reset. The widget
-- never writes: LateIgnore.Ignore, Unignore and Reset write the whole value. 8690 is one entry that
-- stands for every hearthstone, so its line says so.
local SPELL_KIND = { base = "spell", resolve = function(text, candidates) return NS.LateIgnore.Resolve(text, candidates) end }

local function ignoreEntries()
    local LI, list = NS.LateIgnore, {}
    local suffix = L["(all hearthstones, %d)"]:format(#(NS.HEARTHSTONE_SPELLS or {}))
    for i, id in ipairs(LI.List()) do
        list[i] = { id = id, suffix = id == LI.HEARTHSTONE and suffix or nil }
    end
    return list
end

--- The Reset list button's tooltip (one function, so a suite reads the words the button carries).
function RacePage.RESET_TOOLTIP()
    return L["Put the list back to its six defaults: Invisibility, Vanish, Feign Death, every hearthstone, Shadowmeld and Greater Invisibility. The other Race mode settings are not touched."]
end

local function afterLate(ctx)
    local H, LI = NS.Helpers, NS.LateIgnore
    H.TextRow(ctx, L["Spells whose casts after the grace never flag a race, on every saved race. Taking one off flags its casts again."])
    H.IdList(ctx, {
        kind        = SPELL_KIND,
        label       = L["Ignore a spell"],
        tooltip     = L["A spell ID, a shift-clicked spell link, or the name of a spell a race cast late. \"Hearthstone\" adds every hearthstone."],
        emptyText   = L["No spell is ignored: every late cast flags its race."],
        entries     = ignoreEntries,
        candidates  = function() return LI.KnownSpells() end,
        onAdd       = function(id) LI.Ignore(id) end,
        onRemove    = function(id) LI.Unignore(id) end,
        removeStyle = "icon",
        columns     = 2,
    })
    -- The page's Defaults resets every Race mode row with the list; this resets the list alone, in the
    -- one write `/ct race ignore defaults` makes.
    H.InlineButtonPair(ctx, {
        text    = L["Reset list"],
        tooltip = RacePage.RESET_TOOLTIP(),
        onClick = function() LI.Reset() end,
    })
end

NS.RegisterTabbedPage({
    key             = PAGE,
    title           = L["Race mode"],
    panelName       = "CombatTrailRacePanel",
    clients         = RETAIL,
    defaultsTooltip = L["Restore every Race mode setting on this profile to its addon default, the late-cast ignore list and the call-out's look and voice among them. Saved races are not touched."],
    afterGroup      = { [TAB.late] = afterLate },
    beforeGroup     = { [TAB.race] = beforeRace },
    tabs            = { NS.Callout:SettingsTab({ options = NS.Helpers, key = CALLOUT_TAB, prefix = NS.Countdown.PREFIX }) },
})

-- The ignore list repaints when it changes from anywhere (`/ct race ignore`, `/ct set`, a right-click)
-- or the profile does; a hidden page is only flagged, and repaints on its next show. A new profile
-- with Race mode off cancels an armed race, as the switch does.
local function repaint()
    local ctx = NS.pageCtx[PAGE]
    if ctx and NS.Helpers.RefreshPanel then NS.Helpers.RefreshPanel(ctx, true) end
end

do
    local bus = NS.NewBusTarget()
    if bus then
        bus:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, path)
            if path == "profile" then cancelArmedIfOff() end
            if path == NS.LateIgnore.PATH or path == "profile" then repaint() end
        end)
    end
end
