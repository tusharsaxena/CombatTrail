local _, NS = ...
-- defaults/Profile.lua — the AceDB defaults tree: the only place a default is hardcoded
-- (savedvariables-§2). Every schema row's `default` reads from here.
--
-- The skeleton (plan Task 0.1): one sub-table per settings page, each filled by the task that builds
-- its feature: `general` (Task 0.2), `lanes` (1.1), `hud` (3.1), `history` (2.5) and `results` (4.1).
--
-- LOAD-BEARING: reads NS.IGNORE_SEEDS (defaults/IgnoreSeeds.lua), NS.Compat and NS.Constants.PALETTE
-- (core/Constants.lua) at FILE SCOPE.

local function rgba(r, g, b, a) return { r = r, g = g, b = b, a = a } end

-- A swatch copied out of the shared bar palette (core/Constants.lua): a fresh table per call, so
-- each block owns its own; `a` replaces the palette entry's alpha.
local PALETTE = NS.Constants.PALETTE
local function swatch(c, a) return rgba(c[1], c[2], c[3], a or c[4]) end

-- Where a lane may show (spec §4, Visibility). Delves and arenas are Retail-only, so on WoW Forever
-- the keys are ABSENT, not false (clients-§4): the Lanes page builds its rows from these keys.
local function where()
    local w = { world = true, dungeon = true, raid = true, bg = true }
    if NS.Compat.ForClient({ "retail" }) then
        w.delve, w.arena = true, true
    end
    return w
end

-- The lane's hide rules (spec §4, Visibility). Vehicles and pet battles are Retail-only (WoW Forever is
-- the vanilla-era game type), so on Forever those keys are ABSENT (clients-§4), like where()'s.
local function visibility()
    local v = { show = "always", hideAfter = 5, where = where(), hideMounted = true, hideResting = false,
                alphaCombat = 1, alphaOOC = 1 }
    if NS.Compat.ForClient({ "retail" }) then
        v.hideVehicle, v.hidePetBattle = true, true
    end
    return v
end

-- What the recording filters store, per content kind (spec §5): every kind on, scenarios too. The
-- keys are modules/Identity.lua's Identity.CONTENT for this client (a suite holds the two equal):
-- Mythic+, delves and arenas are Retail-only, so on WoW Forever their keys are ABSENT (clients-§4).
local function content()
    local c = { raid = true, dungeon = true, bg = true, world = true, dummy = true, scenario = true }
    if NS.Compat.ForClient({ "retail" }) then
        c.mplus, c.delve, c.arena = true, true, true
    end
    return c
end

-- Race mode's own keys (the Race mode page, race plan Task B3), Retail only, so ABSENT on WoW Forever
-- (clients-§4); the rest of the race table (the length, the scoring rules, the late-cast list) is on
-- both clients, as a saved race re-scores there too. The switch (Race mode on, which stops new races
-- only), auto-show near a dummy (on) and auto-arm on targeting one (off), the race clock's mode
-- ("both", "left" or "elapsed"), the countdown's cue, its center numbers and where they start (s),
-- and the buzzer's raid warning (DPS Race's defaults; the countdown and the buzzer are Task C2's).
local function raceMode(r)
    if NS.Compat.ForClient({ "retail" }) then
        r.enabled, r.autoShow, r.autoArm, r.clock = true, true, false, "both"
        r.countdownCue, r.centerCountdown, r.finalCountdown, r.buzzer = true, true, 10, true
    end
    return r
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
        -- Each style and color a skin describes follows it through its `<key>FromSkin` companion
        -- (skinning-§6, options-ui-§16: on by default, the composer's default too): the border's
        -- style and thickness (the composer's icon family), its color and the glow color.
        border = true, borderTexture = "", borderColor = rgba(1, 0.82, 0, 0.9), borderClassColor = false,
        borderSize = 1, borderTextureFromSkin = true, borderColorFromSkin = true, zoom = 0.08,
        markInterrupted = true, glowLongCD = true, glowMinCD = 29, glowColor = rgba(1, 0.82, 0, 1),
        glowClassColor = false, glowColorFromSkin = true,
        tooltip = true, showName = false, fade = 0.2, stack = false,
        -- Background and border ("" texture = flat); the background color, the lane border's style
        -- and thickness (the composer's bar family) and its color follow the skin while on.
        background = true, bgTexture = "", bgColor = rgba(0, 0, 0, 0.35), bgClassColor = false,
        bgColorFromSkin = true,
        laneBorder = false, laneBorderTexture = "", laneBorderColor = rgba(0, 0, 0, 1),
        laneBorderClassColor = false, laneBorderSize = 1, laneBorderTextureFromSkin = true,
        laneBorderColorFromSkin = true,
        padding = 0,
        -- Ticks and labels. tickSpacing "gcd15" (1.5 s) | "haste" (haste-adjusted GCD) | "1s".
        ticks = true, tickSpacing = "gcd15", tickColor = rgba(1, 1, 1, 0.25), tickClassColor = false,
        tickWidth = 1, now = true, nowColor = rgba(1, 1, 1, 0.6), nowClassColor = false,
        -- labelText "" = the lane's own name (the pet's name on the Pet lane, modules/LaneCasts.lua).
        -- The label's font is the Lanes page's composed Font block (labelFont "" = the skin's font):
        -- its face, flags ("@skin" = From skin, S.FontFlags), color and shadow follow the skin by
        -- default (labelFontFromSkin, labelColorFromSkin, labelShadowFromSkin).
        label = true, labelText = NS.L["You"], labelFont = "", labelSize = 12, labelOutline = "@skin",
        labelColor = rgba(1, 1, 1, 1), labelClassColor = false, labelShadow = false, labelPosition = "LEFT",
        labelFontFromSkin = true, labelColorFromSkin = true, labelShadowFromSkin = true,
        -- Visibility. show "always" | "combat" | "combatOrTarget" | "never".
        visibility = visibility(),
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
                -- Link to Player lane (modules/LaneRender.lua LINK_OWN): off, the Pet lane keeps its
                -- own look; on, it mirrors the Player lane's but where it sits, its label text, its
                -- switch and its ignore list.
                link        = false,
            }),
        },
        -- The live DPS HUD (spec §6, modules/Hud.lua). Behavior: when it opens ("auto" on every fight's first
        -- hit, "always", or "toggle": only when the player opens it), the seconds it stays after the fight (0
        -- keeps the card up), whether the pointer holds it, whether it opens only inside an instance, what
        -- the pace compares against ("best" on the same board, the "last" fight there, or "none"), the pace
        -- bar's range (plan Task 3.2), whether the fight-over card shows and whether it says why a fight was
        -- not saved. Layout: its width, its scale, its size mode (v0.2 Task B3: "fixed", the height derived
        -- from `bars` spell rows and set by the grip, or "auto", growing with the rows up to `bars` and then
        -- scrolling, toward `grow` "down" or "up"), and one switch per part of the stack (the clock, the
        -- target line, the Damage and DPS boxes, the pace bar, the damage chart and the spell rows). Its
        -- place: a point on UIParent, written by the title bar's drag (the mockup's top right).
        -- The look (plan Task 3.2, modules/Hud_Appearance.lua), one block per mockup tab, each in the
        -- composer's shapes (options-ui-§16 and §17: a font block, a bar block, a swatch with its
        -- `useClassColor<Key>`; a `<key>FromSkin` companion on draws the skin's own, and every font block's
        -- text color and shadow follow the skin by default, skinning-§6). Clock and figures: the clock's font
        -- (the mono role, no outline; the skin's HUD face and 26 points, which the HUD draws at DPS Race's
        -- single-clock 40, v0.2 Task B2), the figures' font, the over card's DPS color and the boxes'
        -- background and border. Damage chart: the plot's height and most columns, the columns' bar, the
        -- pace-line color, the cooldown icons (and their minimum base cooldown, seconds)
        -- and the zero line. Spell rows: their height (how many is the Layout's `bars`), the icons and the
        -- pet's paw, the player's bar, the pet's color and the rows' font. Window: the title bar and its
        -- title, the background and border, the footer, the strata and the opacity. ("Lock position" is
        -- general.locked.)
        hud = {
            show = "auto", fadeAfter = 8, holdOnMouse = true, instancesOnly = false,
            paceAgainst = "best", paceRange = 1.5, overCard = true, showSkipReason = true,
            width = 260, scale = 1, sizeMode = "fixed", bars = 5, grow = "down",
            layout = { clock = true, target = true, figures = true, pace = true, chart = true, spells = true },
            position = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -60, y = -160 },
            clock = { font = "JetBrains Mono", fontSize = 26, fontColor = rgba(0.92, 0.91, 0.88, 1),
                      useClassColorFont = false, fontFlags = "", fontShadow = false, fontFromSkin = true,
                      fontColorFromSkin = true, fontShadowFromSkin = true },
            figures = { font = "Ka0s Prototype", fontSize = 20, fontColor = rgba(0.93, 0.93, 0.95, 1),
                        useClassColorFont = false, fontFlags = "@skin", fontShadow = true, fontFromSkin = true,
                        fontColorFromSkin = true, fontShadowFromSkin = true,
                        overColor = rgba(0.29, 0.82, 0.42, 1), useClassColorOverColor = false,
                        overColorMatchDamage = true,
                        boxBg = rgba(0.06, 0.07, 0.09, 0.8), useClassColorBoxBg = false, boxBgFromSkin = true,
                        boxBorder = rgba(0.16, 0.17, 0.2, 1), useClassColorBoxBorder = false,
                        boxBorderFromSkin = true },
            chart = { height = 80, columns = 48,
                      barTexture = "Ka0s Default", barAlpha = PALETTE.BAR_A, barColor = swatch(PALETTE.BAR),
                      useClassColorBar = false, barTextureFromSkin = true,
                      bestColor = swatch(PALETTE.PACE), useClassColorBestColor = false,
                      cooldowns = true, cooldownMin = 29, zeroLine = true },
            spells = { rowHeight = 18, icons = true, paw = true,
                       barTexture = "Ka0s Default", barAlpha = PALETTE.BAR_A, barColor = swatch(PALETTE.BAR),
                       useClassColorBar = false, barTextureFromSkin = true,
                       petColor = swatch(PALETTE.PET, PALETTE.BAR_A), useClassColorPetColor = false,
                       -- The bars' border (owner, 2026-11-11): off; a flat 1 px edge in black when
                       -- shown, the skin's bar border while its companions are on.
                       borderShow = false, borderStyle = "Solid", borderSize = 1, borderColor = rgba(0, 0, 0, 1),
                       useClassColorBorder = false, borderStyleFromSkin = false, borderColorFromSkin = false,
                       font = "Ka0s Prototype", fontSize = 10, fontColor = rgba(1, 1, 1, 1),
                       useClassColorFont = false, fontFlags = "@skin", fontShadow = true, fontFromSkin = true,
                       fontColorFromSkin = true, fontShadowFromSkin = true },
            window = { titleBar = true, title = true,
                       bg = rgba(0.06, 0.06, 0.08, 0.94), useClassColorBg = false, bgFromSkin = true,
                       border = rgba(0.24, 0.24, 0.27, 1), useClassColorBorder = false, borderFromSkin = true,
                       footer = true, strata = "MEDIUM", alpha = 1 },
        },
        -- The recording filters and retention (spec §5; modules/Filters.lua, modules/Retention.lua):
        -- the minimum length in seconds (30 on Retail, 15 on WoW Forever, where fights run shorter),
        -- bosses only, one toggle per content kind (content(), above),
        -- the days a fight is kept (0 = for ever), whether a fight holding a best is kept past them,
        -- and the store's cap (0 = none).
        history = {
            minLength = NS.Compat.ForClient({ "forever" }) and 15 or 30, bossesOnly = false, content = content(),
            days = 7, keepBests = true, maxFights = 500,
        },
        -- The Results window (spec §7; modules/Results.lua, modules/Results_Fights.lua): the saved view
        -- (the filters, the grouping and the sort Save view stores; "current" is the logged-in
        -- character, `days` 0 is all time), where the window stands, its list's width and its height,
        -- and its fold (the detail in the list's place, "collapsed", or beside it, "expanded"), written
        -- by its drag, its grip and its fold arrow and put back by Master controls' Reset position;
        -- its scale, its list's row height (px); whether Share appends the fight's talents link; whether
        -- it closes when combat starts (v0.2 Task C1); and `columns`, the widths a header's edge was
        -- dragged to (`{ character = px }`; empty is the shipped width), put back by Reset position. The
        -- list's width has no shipped number: nothing stored opens the window at its least
        -- (Results.MIN_WIDTH, the filter bar's or the table's; owner, 2026-11-11), and a stored width is
        -- held to it; and `collapsedSections`, the
        -- fight detail's folded sections (v0.2 Task C3: `{ [section] = true }`, keys
        -- NS.ResultsDetail.SECTIONS, open stored as nothing), which Reset position keeps; and
        -- `timelineMarks`, how the ability timeline's By ability lanes draw a cast (v0.2 Task D1,
        -- modules/Results_TimelineMarks.lua): "icon" (its ability's icon) or "tick" (a thin line).
        results = {
            view = { character = "current", spec = "all", content = "all", board = "all", difficulty = "all",
                     days = 7, bossesOnly = false, group = "datechar", sort = "date", desc = true },
            window = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0, height = 520,
                       view = "collapsed" },
            scale = 1, rowHeight = 18,
            shareTalents = true, closeInCombat = true,
            columns = {},
            collapsedSections = {},
            timelineMarks = "icon",
        },
        -- The player's own training dummies (modules/Dummies.lua, race plan Task A2): one string of
        -- `id:category` (a dummy of the player's) and `-id` (a built-in switched off) entries, written
        -- whole through the seam. Empty: the client's seed alone (defaults/Dummies.lua).
        dummies = { custom = "" },
        -- Race mode (modules/Race.lua, race plan Task B1; Retail only, its page is Task B3's): the
        -- length a race arms at until the player picks one (s; `lastLength`, no default, is the last
        -- one armed, state the race writes, not a setting), the grace after the buzzer before a cast
        -- start is late (s) and the quiet after the buzzer before damage counts as restarted (s), both
        -- frozen into each race as it arms, and the seconds in combat after the buzzer before the
        -- Race window's drop-combat hint (DPS Race's). The late-cast ignore list (modules/LateIgnore.lua)
        -- is the one read at score time, never frozen, so an edit re-scores every saved race: spell
        -- IDs, ascending and comma-separated, 8690 standing for every hearthstone
        -- (defaults/Hearthstones.lua): Invisibility, Vanish, Feign Death, Hearthstone, Shadowmeld,
        -- Greater Invisibility. On both clients: a saved race (account-wide) re-scores on WoW Forever too.
        -- The Retail-only part (raceMode(), below, Task B3) adds the Race mode page's own keys.
        race = raceMode({ defaultLength = 60, grace = 1.0, restartGap = 6, hintDelay = 15,
                          lateIgnore = "66,1856,5384,8690,58984,110959" }),
        -- The Race window's place (Race mode, Task B3; Retail only, so ABSENT on WoW Forever,
        -- clients-§4): attached beside the DPS HUD, on its `side` ("RIGHT", "LEFT", "TOP", "BOTTOM");
        -- detached, it stands at `position` (modules/RaceWindow.lua, Task C1), written by its title
        -- bar's drag and put back by Master controls' Reset position.
        raceWindow = NS.Compat.ForClient({ "retail" }) and { attached = true, side = "RIGHT",
            position = { point = "CENTER", relPoint = "CENTER", x = 0, y = 160 } } or nil,
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
        -- What the game said about each creature `/ct dummy` captured, by creature ID
        -- (modules/Dummies.lua): data, not a setting. Global, as a creature is the same on every
        -- profile.
        dummies = { captures = {} },
        -- The race under way, per character (modules/Race.lua, race plan Task B2): written at its first
        -- hit and cleared at its result or a cancel, so Race.Resume carries it on after a /reload.
        -- Keyed by Bests.CharKey ("name|realm|client"); plain fields only. Data, not a setting.
        pendingRaces = {},
        -- LibDBIcon's own table, handed straight to :Register (launcher-§3). Global, because the
        -- button belongs to the installation and a profile switch must not move it.
        minimap = { hide = false },
    },
}
