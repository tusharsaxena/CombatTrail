local addonName, NS = ...
-- core/Constants.lua — fixed values resolved at load: the monospace face, the logo path and the
-- frame-layering table.

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
--   MEDIUM             HUD           the DPS HUD (modules/Hud.lua): the persistent display, a movable
--                                    window, toplevel, so a click raises it among MEDIUM peers
--   HIGH               WINDOW        the Results window (modules/Results.lua): the on-demand browser,
--                                    toplevel; Blizzard's Settings panel shares this strata, and the
--                                    last one clicked is in front
--   DIALOG             MODAL         the ability timeline and the gear view, opened from the Results
--                                    window, so one strata above it, toplevel and clamped; each
--                                    re-raises a shown StaticPopup when it opens (frame-layering-§4)
--   DIALOG             (library)     Blizzard StaticPopups (reset, delete), the LibKa0s debug console
--                                    and perf panel
--   FULLSCREEN_DIALOG  (library)     the LibKa0s dropdown menu (the Results filter bars)
--   TOOLTIP            (Blizzard)    GameTooltip
--
-- A lane's icons sit at lane level + 1 .. lane level + LEVEL.ICON_BAND, re-ordered inside that band on
-- each push so the newest is on top (spec §4 Layering). Levels inside a window (base W): chrome W+1, content W+2 .. W+8, the library resize grip W+10.
-- The Results detail pane sits at body + LEVEL.DETAIL, the damage chart's overlay at its plot +
-- LEVEL.CHART_OVERLAY, and the Results window's dim cover under an open modal at W + LEVEL.COVER
-- (the standard's popover band over a window's own content).
C.LAYERS = {
    STRATA = { LANE = "LOW", HUD = "MEDIUM", WINDOW = "HIGH", MODAL = "DIALOG" },
    LEVEL  = { DETAIL = 2, CHART_OVERLAY = 2, COVER = 30, ICON_BAND = 8 },
}
