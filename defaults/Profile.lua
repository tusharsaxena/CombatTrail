local _, NS = ...
-- defaults/Profile.lua — the AceDB defaults tree: the only place a default is hardcoded
-- (savedvariables-§2). Every schema row's `default` reads from here.
--
-- The skeleton (plan Task 0.1): one sub-table per settings page, each filled by the task that builds
-- its feature: `general` (Task 0.2), `lanes` (1.1), `hud` (3.1), `history` (2.5) and `results` (4.1).
--
-- LOAD-BEARING: reads NS.IGNORE_SEEDS (defaults/IgnoreSeeds.lua) and NS.Compat at FILE SCOPE.

local function rgba(r, g, b, a) return { r = r, g = g, b = b, a = a } end

-- Where a lane may show (spec §4, Visibility). Delves and arenas are Retail-only, so on WoW Forever
-- the keys are ABSENT, not false (clients-§4): the Lanes page builds its rows from these keys.
local function where()
    local w = { world = true, dungeon = true, raid = true, bg = true }
    if NS.Compat.ForClient({ "retail" }) then
        w.delve, w.arena = true, true
    end
    return w
end

-- What the recording filters store, per content kind (spec §5): every kind on but scenarios. The
-- keys are modules/Identity.lua's Identity.CONTENT for this client (a suite holds the two equal):
-- Mythic+, delves and arenas are Retail-only, so on WoW Forever their keys are ABSENT (clients-§4).
local function content()
    local c = { raid = true, dungeon = true, bg = true, world = true, dummy = true, scenario = false }
    if NS.Compat.ForClient({ "retail" }) then
        c.mplus, c.delve, c.arena = true, true, true
    end
    return c
end

-- One lane's every setting (spec §4's table, tab by tab). The two lanes differ only where `over` says.
local function lane(key, over)
    local d = {
        enabled   = true,
        -- Size and position. direction "left": newest at the right edge, scrolling left (as CastTrail).
        direction = "left", scale = 1, width = 480, seconds = 12, iconSize = 28, spacing = 0,
        -- Anchoring: "free" | "dock" (to the other lane: target, gap) | "unit" (the lane's unit frame,
        -- or `frameName` when set). strata "LOW" (or "HOST" = match the host in unit-frame mode),
        -- levelOffset added to the strata's relative base (spec §4, Layering).
        anchor    = { mode = "free", point = "CENTER", relPoint = "CENTER", x = 0, y = -200,
                      target = key == "pet" and "player" or "pet", gap = 4, frameName = "" },
        strata    = "LOW", levelOffset = 0,
        -- Icons. Every color has its Use class color companion (`<part>ClassColor`, options-ui-§17,
        -- off), and the icon border its style (`borderTexture`, an LSM statusbar key, "" = flat).
        border = true, borderTexture = "", borderColor = rgba(1, 0.82, 0, 0.9), borderClassColor = false,
        borderSize = 1, zoom = 0.08,
        markInterrupted = true, glowLongCD = true, glowMinCD = 29, glowColor = rgba(1, 0.82, 0, 1),
        glowClassColor = false,
        tooltip = true, showName = false, fade = 0.2, stack = false,
        -- Background and border ("" texture = the skin's own)
        background = true, bgTexture = "", bgColor = rgba(0, 0, 0, 0.35), bgClassColor = false,
        laneBorder = false, laneBorderTexture = "", laneBorderColor = rgba(0, 0, 0, 1),
        laneBorderClassColor = false, laneBorderSize = 1,
        padding = 0,
        -- Ticks and labels. tickSpacing "gcd15" (1.5 s) | "haste" (haste-adjusted GCD) | "1s".
        ticks = true, tickSpacing = "gcd15", tickColor = rgba(1, 1, 1, 0.25), tickClassColor = false,
        tickWidth = 1, now = true, nowColor = rgba(1, 1, 1, 0.6), nowClassColor = false,
        -- labelText "" = the lane's own name (the pet's name on the Pet lane, modules/LaneCasts.lua).
        -- The label's font is the Lanes page's composed Font block (labelFont "" = the skin's font).
        label = true, labelText = NS.L["You"], labelFont = "", labelSize = 12, labelOutline = "OUTLINE",
        labelColor = rgba(1, 1, 1, 1), labelClassColor = false, labelShadow = false, labelPosition = "LEFT",
        -- Visibility. show "always" | "combat" | "combatOrTarget" | "never".
        visibility = { show = "always", hideAfter = 5, where = where(), hideMounted = true,
                       hideVehicle = true, hidePetBattle = true, hideResting = false,
                       alphaCombat = 1, alphaOOC = 1 },
        -- Ignored spells: { [spellID] = true }, seeded per client; a seed the player removes is
        -- stored as false, which AceDB keeps because it differs from the default.
        ignore = NS.IgnoreSeedSet(key),
    }
    for k, v in pairs(over or {}) do d[k] = v end
    return d
end

NS.defaults = {
    profile = {
        -- Master controls (General > Master controls) and the global font scale (General > Look and
        -- skin). The debug flag is NOT here: it is session-only (NS.State.debug, debug-logging-§5), as
        -- are test mode and the sim. Nor is the minimap button: LibDBIcon's `hide` is global (below).
        general = {
            enabled     = true,
            locked      = false,
            hudInCombat = true,
            fontScale   = 1,
        },
        -- The Player and Pet lanes, one block per lane (spec §4). The Pet lane docks under the Player
        -- lane by default (the mockup), with its own colors and a smaller icon.
        lanes = {
            player = lane("player"),
            pet    = lane("pet", {
                iconSize    = 24,
                anchor      = { mode = "dock", point = "TOP", relPoint = "BOTTOM", x = 0, y = -236,
                                target = "player", gap = 4, frameName = "" },
                borderColor = rgba(0.4, 1, 0.4, 0.9),
                labelText   = "",
            }),
        },
        -- The live DPS HUD (spec §6, modules/Hud.lua). Behavior: when it opens ("auto" on every
        -- fight's first hit, "always", or "toggle": only when the player opens it), the seconds it
        -- stays after the fight (0 keeps the card up), whether the pointer holds it, whether it opens
        -- only inside an instance, what the pace compares against ("best" on the same board, the
        -- "last" fight there, or "none"), the pace bar's range (plan Task 3.2), whether the fight-over
        -- card shows and whether it says why a fight was not saved. Layout: its width, its scale and
        -- one switch per part of the stack (the clock, the target line, the Damage and DPS boxes, the
        -- pace bar, the damage chart and the spell rows). Its place: a point on UIParent, written by
        -- the title bar's drag (the mockup's top right).
        -- The look (plan Task 3.2, modules/Hud_Appearance.lua), one block per mockup tab, each in the
        -- composer's shapes (options-ui-§16 and §17: a font block, a bar block, a swatch with its
        -- `useClassColor<Key>`; a `<key>FromSkin` companion on draws the skin's own, and every font
        -- block's text color and shadow follow the skin by default, skinning-§6). Clock and
        -- figures: the clock's font (the mono role, no outline, 32 points: the composed Font size
        -- row's top), the figures' font, the over card's DPS color and the boxes' background and
        -- border. Damage chart: the plot's height and most
        -- columns, the columns' bar, the burst-window and best-line colors, the cooldown icons (and
        -- their minimum base cooldown, seconds) and the zero line. Spell rows: how many (0 = every
        -- one, the wheel scrolls), their height, the icons and the pet's paw, the player's bar, the
        -- pet's color and the rows' font. Window: the title bar and its title, the background and
        -- border, the footer, the strata and the opacity. ("Lock position" is general.locked.)
        hud = {
            show = "auto", fadeAfter = 8, holdOnMouse = true, instancesOnly = false,
            paceAgainst = "best", paceRange = 1.5, overCard = true, showSkipReason = true,
            width = 300, scale = 1,
            layout = { clock = true, target = true, figures = true, pace = true, chart = true, spells = true },
            position = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -60, y = -160 },
            clock = { font = "JetBrains Mono", fontSize = 32, fontColor = rgba(0.92, 0.91, 0.88, 1),
                      useClassColorFont = false, fontFlags = "", fontShadow = false, fontFromSkin = false,
                      fontColorFromSkin = true, fontShadowFromSkin = true },
            figures = { font = "Ka0s Prototype", fontSize = 20, fontColor = rgba(0.93, 0.93, 0.95, 1),
                        useClassColorFont = false, fontFlags = "@skin", fontShadow = true, fontFromSkin = true,
                        fontColorFromSkin = true, fontShadowFromSkin = true,
                        overColor = rgba(0.29, 0.82, 0.42, 1), useClassColorOverColor = false,
                        boxBg = rgba(0.06, 0.07, 0.09, 0.8), useClassColorBoxBg = false, boxBgFromSkin = true,
                        boxBorder = rgba(0.16, 0.17, 0.2, 1), useClassColorBoxBorder = false,
                        boxBorderFromSkin = true },
            chart = { height = 90, columns = 48,
                      barTexture = "Ka0s Default", barAlpha = 1, barColor = rgba(0.35, 0.37, 0.66, 1),
                      useClassColorBar = false, barTextureFromSkin = true,
                      burstColor = rgba(0.79, 0.65, 0.23, 1), useClassColorBurstColor = false,
                      bestColor = rgba(0.62, 0.82, 1, 0.55), useClassColorBestColor = false,
                      cooldowns = true, cooldownMin = 29, zeroLine = true },
            spells = { rows = 8, rowHeight = 22, icons = true, paw = true,
                       barTexture = "Ka0s Default", barAlpha = 0.6, barColor = rgba(0.43, 0.43, 0.71, 1),
                       useClassColorBar = false, barTextureFromSkin = true,
                       petColor = rgba(0.31, 0.67, 0.35, 0.55), useClassColorPetColor = false,
                       font = "Ka0s Prototype", fontSize = 12, fontColor = rgba(1, 1, 1, 1),
                       useClassColorFont = false, fontFlags = "@skin", fontShadow = false, fontFromSkin = true,
                       fontColorFromSkin = true, fontShadowFromSkin = true },
            window = { titleBar = true, title = true,
                       bg = rgba(0.06, 0.06, 0.08, 0.94), useClassColorBg = false, bgFromSkin = true,
                       border = rgba(0.24, 0.24, 0.27, 1), useClassColorBorder = false, borderFromSkin = true,
                       footer = true, strata = "MEDIUM", alpha = 1 },
        },
        -- The recording filters and retention (spec §5; modules/Filters.lua, modules/Retention.lua):
        -- the minimum length in seconds, bosses only, one toggle per content kind (content(), above),
        -- the days a fight is kept (0 = for ever), whether a fight holding a best is kept past them,
        -- and the store's cap (0 = none).
        history = {
            minLength = 30, bossesOnly = false, content = content(),
            days = 7, keepBests = true, maxFights = 500,
        },
        -- The Results window (spec §7; modules/Results.lua, modules/Results_Fights.lua): the saved view
        -- (the filters, the grouping and the sort Save view stores; "current" is the logged-in
        -- character, `days` 0 is all time), where the window stands, its list's width and its height,
        -- and its fold (the detail in the list's place, "collapsed", or beside it, "expanded"), written
        -- by its drag, its grip and its fold arrow and put back by Master controls' Reset position;
        -- its scale; and whether Share appends the fight's talents link.
        results = {
            view = { character = "current", spec = "all", content = "all", board = "all", difficulty = "all",
                     days = 7, bossesOnly = false, group = "board", sort = "date", desc = true },
            window = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0, width = 920, height = 520,
                       view = "collapsed" },
            scale = 1,
            shareTalents = true,
        },
        -- The skin this addon wears (skinning-§2: per addon, per profile; core/SkinSetup.lua): the
        -- source and the skin, the client's default skin (WoW Forever on Forever, Ka0s Default on
        -- Retail, spec §8); the Scope's two exceptions (the settings panel left the client's, the
        -- fonts skinned); the font and texture overrides, an LSM key each, "" for the skin's own; the
        -- Font outline, "hud" text only, "all" text or "off"; and `pickerSeen`, false on every profile
        -- so the first-run skin picker shows once.
        skin = { source = "ka0s", skin = NS.DEFAULT_SKIN, ignorePanel = true, ignoreFonts = false,
                 font = "", texture = "", outline = "hud", pickerSeen = false },
    },
    global = {
        -- 0, never the current version: AceDB strips a value equal to its default at logout and
        -- would backfill it onto a legacy account (savedvariables-§1).
        schemaVersion = 0,
        -- The fight store, keyed by fight id, and its newest-first order (modules/Recorder.lua, spec
        -- §5). Global: a fight belongs to the installation, and a profile switch must not hide a
        -- character's history.
        fights = {},
        fightOrder = {},
        -- The items the Results detail's Usage never lists (modules/Usage.lua, spec §7's "never show"
        -- list): item IDs, comma-separated. Global, as the fight store it filters is.
        usage = { hidden = "" },
        -- LibDBIcon's own table, handed straight to :Register (launcher-§3). Global, because the
        -- button belongs to the installation and a profile switch must not move it.
        minimap = { hide = false },
    },
}
