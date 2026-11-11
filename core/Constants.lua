local addonName, NS = ...
-- core/Constants.lua — fixed values resolved at load: the monospace face, the logo path and the
-- frame-layering table, the fight timing and the shared bar palette.

NS.Constants = NS.Constants or {}
local C = NS.Constants

-- The debug console's face, from the shared catalog (library-stack-§8). The fallback is a REAL
-- client font, never nil: SetFont on a bad path draws nothing and raises nothing.
C.FONT_MONO = (NS.MediaFont and NS.MediaFont("JetBrains Mono")) or STANDARD_TEXT_FONT

-- The 128x128 uncompressed 32-bit logo (layout-§4): the TOC IconTexture, the minimap button and the
-- broker object's icon. Never a Blizzard icon or a file id (anti-pattern #82).
C.LOGO_128 = ("Interface\\AddOns\\%s\\media\\logos\\combattrail.logo.128.tga"):format(addonName)

-- THE LAYERS (frame-layering-§5). Every SetFrameStrata and SetFrameLevel in this addon reads this
-- table; no strata string and no bare level number sits at a call site. The addon's whole stack, low
-- to high, the library- and Blizzard-owned tiers it relies on included:
--
--   LOW                LANE          the Player and Pet cast lanes (modules/LaneRender.lua): the default
--                                    of each lane's configured strata (spec §4 Layering), below most
--                                    addon windows. A lane set to "HOST" (the unit-frame default) takes
--                                    its host's strata instead (host-matched surfaces); its icons stay in
--                                    the bounded band LEVEL.ICON_BAND above the lane, never a climbing count
--   max(lane, MEDIUM)  CHROME        a lane's edit overlay (modules/LaneAnchor.lua), shown in Edit Mode
--                                    and after /ct unlock: mouse-live chrome, so floored at MEDIUM over
--                                    a LOW lane (frame-layering-§2), fixed and re-lifted after every
--                                    strata the lane takes, at lane level + LEVEL.LANE_EDIT
--   MEDIUM             HUD           the DPS HUD (modules/Hud.lua): the persistent display, a movable
--                                    window, toplevel, so a click raises it among MEDIUM peers
--   HIGH               WINDOW        the Results window (modules/Results.lua): the on-demand browser,
--                                    toplevel; Blizzard's Settings panel shares this strata, and the
--                                    last one clicked is in front
--   HIGH               (library)     the new-best toast (modules/BestToast.lua, LibKa0s-Toast-1.0's
--                                    T5 alert tier)
--   DIALOG             MODAL         the ability timeline and the gear view, opened from the Results
--                                    window, so one strata above it, toplevel and clamped; each
--                                    re-raises a shown StaticPopup when it opens (frame-layering-§4)
--   DIALOG             (library)     Blizzard StaticPopups (reset, delete), the LibKa0s debug console
--                                    and perf panel
--   FULLSCREEN         SCREEN_ALERT  the race's center-screen countdown (modules/Countdown.lua, Race
--                                    mode): over every window, below every menu, never taking the mouse
--   FULLSCREEN_DIALOG  (library)     the LibKa0s dropdown menu (the Results filter bars)
--   TOOLTIP            (Blizzard)    GameTooltip
--
-- A lane sits at its parent's level + LEVEL.LANE + the lane's own level offset (0-50). Its icons sit
-- at lane level + 1 .. lane level + LEVEL.ICON_BAND, re-ordered inside that band on each push so the
-- newest is on top (spec §4 Layering); an icon's border, glow and ✕ are regions of the icon, so they
-- take no level of their own. A lane on a unit frame with strata "HOST" takes the host's level as
-- its base instead of its parent's. The lane's edit overlay sits at lane level + LEVEL.LANE_EDIT, over
-- the whole icon band. Levels inside a window (base W): chrome W+1, content W+2 .. W+8, the library resize grip W+10.
-- The Results detail pane sits at body + LEVEL.DETAIL, the damage chart's overlay at its plot +
-- LEVEL.CHART_OVERLAY, and the Results window's dim cover under an open modal at W + LEVEL.COVER
-- (the standard's popover band over a window's own content).
-- THE FIGHT'S TIMING (spec §5, modules/Fight.lua). GRACE: a re-entry into combat this many seconds
-- after the combat end (Feign Death, Vanish, Shadowmeld) carries the same fight on. SETTLE: the quiet,
-- in seconds without a damage update for the fight's sessions, before its after-combat read. TICK:
-- FIGHT_TICK's period in combat (4 Hz), which the HUD redraws on.
C.FIGHT = { GRACE = 4, SETTLE = 2, TICK = 0.25 }

C.LAYERS = {
    STRATA = { LANE = "LOW", CHROME = "MEDIUM", HUD = "MEDIUM", WINDOW = "HIGH", MODAL = "DIALOG",
                SCREEN_ALERT = "FULLSCREEN" },
    LEVEL  = { LANE = 1, DETAIL = 2, CHART_OVERLAY = 2, COVER = 30, ICON_BAND = 8, LANE_EDIT = 10 },
}

-- THE BAR PALETTE (v0.2, DPS Race parity): the source of every bar default, shared with DPS Race's
-- BAR_BLUE family so the two addons draw the same bars. Arrays {r, g, b[, a]} as Style takes them.
-- defaults/Profile.lua copies them into each block (its own table, so a written swatch never reaches
-- another block or this one). No skin overrides a fill: these are host and data hues, the same in
-- every skin (R:palette#9).
--   BAR, BAR_A       the player's bars and chart columns, and the opacity every bar fill takes
--   PET              the pet's rows and pace fill: the green darkened so white row text keeps ~3.5:1
--   PLAYER_LINE,     lifted shades of the two hues for 1-2 px lines (icon edges, timeline ticks),
--   PET_LINE         where the bar shade reads too dark
--   THIS_BAR,        the compare's bars: this fight (gold) and the other side (blue), DPS Race's bytes,
--   BEST_BAR         at BAR_A
--   THIS_TEXT,       the same two sides as text hues
--   BEST_TEXT
--   PACE             the pace line over the chart: DPS Race's neutral (the ct.chart.diag value, D13)
C.PALETTE = {
    BAR = { 0.36, 0.37, 0.84, 1 }, BAR_A = 0.9,
    PET = { 0.24, 0.60, 0.30, 1 },
    PLAYER_LINE = { 0.50, 0.52, 1.0, 1 }, PET_LINE = { 0.40, 0.85, 0.45, 1 },
    THIS_BAR = { 0.682, 0.569, 0, 1 }, BEST_BAR = { 0.329, 0.549, 0.839, 1 },
    THIS_TEXT = { 1, 0.82, 0 }, BEST_TEXT = { 0.35, 0.66, 1 },
    PACE = { 0.9, 0.9, 0.92, 0.4 },
}
