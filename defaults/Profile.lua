local _, NS = ...
-- defaults/Profile.lua — the AceDB defaults tree: the only place a default is hardcoded
-- (savedvariables-§2). Every schema row's `default` reads from here.
--
-- The skeleton (plan Task 0.1): one sub-table per settings page, each filled by the task that builds
-- its feature: `general` (Task 0.2), `lanes` (1.1), `hud` (3.1), `history` (2.5) and `results` (4.1).

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
        -- The Player and Pet lanes, one block per lane (spec §4).
        lanes = {},
        -- The live DPS HUD (spec §6).
        hud = {},
        -- The recording filters and retention (spec §5).
        history = {},
        -- The Results window's saved view (spec §7).
        results = {},
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
        -- LibDBIcon's own table, handed straight to :Register (launcher-§3). Global, because the
        -- button belongs to the installation and a profile switch must not move it.
        minimap = { hide = false },
    },
}
