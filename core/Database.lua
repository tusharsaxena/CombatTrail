local addonName, NS = ...
-- core/Database.lua — AceDB setup, the profile callbacks and the schemaVersion migration runner.

-- Step 3 asks the call-out major to rewrite its own retired glow choice (its MigrateGlow), so the
-- mapping is the library's and never a copy here; nil without the library, and the step then only
-- drops the retired keys.
local Callout = LibStub and LibStub("LibKa0s-Callout-1.0", true)

-- ── v4: undo the retired step onto the skin's defaults (owner, 2026-11-23) ───────────────────────
-- A step of 2026-11-20 (never released) wrote `skin.defaultsMoved` on each profile it reached and
-- moved the values below onto the skin. It is gone; these are their own values again by default, so a
-- profile that stores none needs nothing. v4 rewrites only what that step could have stored, in a
-- profile carrying its record, then clears the record. Runs once, at the ladder.
--   { the path, what the step left there, the owner's own }
NS.OWN_LOOKS = {
    { "hud.clock.fontFlags", "@skin", "" },
    { "hud.spells.borderStyleFromSkin", true, false },
    { "hud.spells.borderColorFromSkin", true, false },
    { "hud.chart.bestColorFromSkin", true, false },
    { "lanes.player.bgTextureFromSkin", true, false },
    { "lanes.player.tickColorFromSkin", true, false },
    { "lanes.player.nowColorFromSkin", true, false },
    { "lanes.pet.bgTextureFromSkin", true, false },
    { "lanes.pet.tickColorFromSkin", true, false },
    { "lanes.pet.nowColorFromSkin", true, false },
    { "callout.font", "Skin font", "Ka0s Oxanium SemiBold" },
    { "callout.outline", "@skin", "THICKOUTLINE" },
    { "callout.fontShadowFromSkin", true, false },
    { "callout.numberColorFromSkin", true, false },
}

-- The table holding `path`'s last segment in `t`, and that segment; nil where a table is missing.
local function walk(t, path)
    local parent, leaf = t, nil
    for seg in path:gmatch("[^.]+") do
        if leaf ~= nil then
            parent = rawget(parent, leaf)
            if type(parent) ~= "table" then return nil end
        end
        leaf = seg
    end
    return parent, leaf
end

--- v4 on one stored profile. Answers true when the retired step had reached it.
--- @param profile table  the profile root
--- @return boolean
function NS.RestoreOwnLooks(profile)
    local skin = type(profile) == "table" and rawget(profile, "skin")
    if type(skin) ~= "table" or rawget(skin, "defaultsMoved") ~= true then return false end
    for _, entry in ipairs(NS.OWN_LOOKS) do
        local parent, leaf = walk(profile, entry[1])
        if parent ~= nil and rawget(parent, leaf) == entry[2] then parent[leaf] = entry[3] end
    end
    skin.defaultsMoved = nil
    return true
end

-- Beside a retired glow string, a stored intensity or thickness EQUAL to its default is AceDB's copy
-- (savedvariables-§1: AceDB writes defaults into the stored profile it initializes, so presence is
-- not a choice), never the player's: those keys are new with the boolean glow, so no player set one
-- under the old choice. Cleared before MigrateGlow, which keeps any valid one it finds, so the
-- choice's own look (strong: 70%, 5 px) lands. A value that differs from the default is kept.
local function clearCopiedGlowDefaults(t)
    local legacy = Callout and Callout.GLOW_LEGACY and Callout.GLOW_LEGACY[t.glow]
    local D = legacy and NS.defaults and NS.defaults.profile and NS.defaults.profile.callout
    if not D then return end
    for key in pairs(legacy) do
        if key ~= "glow" and t[key] ~= nil and t[key] == D[key] then t[key] = nil end
    end
end

-- The runner's target: the highest step's `to` (savedvariables-§1). Distinct from the FIGHT RECORD
-- format version (modules/Recorder.lua's CT_SCHEMA, spec §5), which never migrates settings. A
-- CT_SCHEMA bump takes no step: CT_SCHEMA 3 -> 4 (Race mode's optional `race` part) leaves every stored
-- record as it is, and an older one simply reads as a fight.
NS.SCHEMA_VERSION = 5

-- Each step is idempotent against a fresh default profile. A profile-scoped step sets
-- `perProfile = true` and runs once for every stored profile.
local STEPS = {
    { to = 1, run = function() end },   -- 0 -> 1: the first release's shape, a no-op
    -- 1 -> 2: the v0.2 fight record (CT_SCHEMA 2: the target's level and NPC ID, the gear set). The
    -- addon was unpublished, so the store is emptied once rather than migrated (plan decision D1):
    -- the fights, their order, the loadouts and the gear sets. Through NS.db.global, which AceDB
    -- always has (the raw SavedVariables' `global` can be nil on a fresh install); idempotent, and
    -- harmless on a fresh install. Every other account-wide key (usage.hidden, minimap, the skin
    -- notice) is kept.
    { to = 2, run = function()
        local g = NS.db.global
        g.fights, g.fightOrder, g.loadouts, g.gearSets = {}, {}, {}, {}
    end },
    -- 2 -> 3, per profile: the race call-out at LibKa0s-Callout-1.0 3.4 (callout plan row C11).
    -- `callout.glow` was "off" | "soft" | "strong" and is a boolean row now: the library's
    -- Callout:MigrateGlow rewrites the stored choice as the keys it implied (glow, glowIntensity,
    -- glowThickness, each only where no valid one is stored), before the Schema's boot check reads
    -- the bool row. `callout.texts` and `callout.muted` lose their rows (SchemaRows' texts = false: the
    -- words are the addon's), and the instance would still read a stored own text or mute, so both
    -- tables are dropped rather than left behind. A stored voice is kept as it is. Idempotent: a
    -- fresh profile has no `callout` table stored, and a migrated one has a boolean glow and no texts.
    -- The retired choice named no color, offset or swatch, so none is stored: since Callout minor 4
    -- (LibKa0s v1.102.0) a migrated Soft or Strong reads the defaults for them, Glow color ticked in
    -- the black swatch at Combat Trail's 1, 1 (SD-CT-DEF; it was each word's kind color at 0, 0). The owner's defaults; no step.
    { to = 3, perProfile = true, run = function(_, profile)
        local t = type(profile) == "table" and profile.callout
        if type(t) ~= "table" then return end
        clearCopiedGlowDefaults(t)
        if Callout and Callout.MigrateGlow then Callout:MigrateGlow(t) end
        t.texts, t.muted = nil, nil
    end },
    -- 3 -> 4, per profile: what the retired skin-defaults step wrote goes back (NS.RestoreOwnLooks).
    { to = 4, perProfile = true, run = function(_, profile) NS.RestoreOwnLooks(profile) end },
    -- 4 -> 5, per profile: the Combat Log keys the owner's feedback retired (2026-11-25, CLF-1). The
    -- Source and Target columns are gone (item 3), so their toggles `log.view.columns.source` and
    -- `.target` go; the drawer's fold is gone (item 14), so `log.drawer.collapsed` and the folded line's
    -- `log.drawer.strip` go. Nothing is carried across: each served only what was removed. Idempotent:
    -- a fresh profile stores none of them.
    { to = 5, perProfile = true, run = function(_, profile) NS.DropRetiredLogKeys(profile) end },
}
NS.__migrationSteps = STEPS   -- test seam only

--- Step 5's body: `profile.log`'s retired keys (the Source and Target column toggles, the drawer's
--- fold and its folded line) dropped. A profile with no `log` table is left alone.
function NS.DropRetiredLogKeys(profile)
    local log = type(profile) == "table" and profile.log
    if type(log) ~= "table" then return end
    local view = log.view
    local cols = type(view) == "table" and view.columns
    if type(cols) == "table" then cols.source, cols.target = nil, nil end
    if type(log.drawer) == "table" then log.drawer.collapsed, log.drawer.strip = nil, nil end
end

--- A profile switch, copy or reset replaces the whole profile wholesale: the stored `enabled` can
--- flip, so re-take the hold and re-decide (slash-commands-§7: these callbacks are SETUP and stay live
--- while disabled). One line per act (debug-logging-§10).
function NS.OnProfileChanged(event, _db, key)
    NS.Debug("Set", "%s '%s'", event or "profile", key or (NS.db and NS.db:GetCurrentProfile()) or "?")
    -- The first-run skin picker goes down first, unmarked (core/SkinSetup.lua), so a preview it had
    -- pending is put back before the new profile's skin is applied below.
    if NS.HideSkinPicker then NS.HideSkinPicker() end
    -- FIRST, before anything redraws: the new profile's skin (core/SkinSetup.lua). Skin:SetChoice
    -- repaints every recorded frame of this owner and fires OnLooksChanged whether or not a window
    -- was ever built, so the skin cannot depend on one.
    if NS.ApplySkinChoice then NS.ApplySkinChoice() end
    NS.SyncEnabledHold()
    -- The first-run skin picker: a new or reset profile starts from the defaults, `pickerSeen` false,
    -- so it shows again over the new profile's skin; one that has seen it stays down. After the
    -- hold, so a profile with the addon switched off shows nothing.
    if NS.MaybeShowSkinPicker then NS.MaybeShowSkinPicker() end
    -- Announced through settings/Schema.lua, the message's one sender.
    if NS.AnnounceSettingsChanged then NS.AnnounceSettingsChanged("profile", key) end
end

function NS:InitDB()
    NS.db = LibStub("AceDB-3.0"):New(addonName .. "DB", NS.defaults, true)
    local db = NS.db
    if db.RegisterCallback then
        db.RegisterCallback(NS, "OnProfileChanged", function(event, d, key) NS.OnProfileChanged(event, d, key) end)
        db.RegisterCallback(NS, "OnProfileCopied", function(event, d, key) NS.OnProfileChanged(event, d, key) end)
        db.RegisterCallback(NS, "OnProfileReset", function(event, d) NS.OnProfileChanged(event, d) end)
    end
end

function NS:RunMigrations()
    local db = NS.db
    local g, sv = db.global, _G[addonName .. "DB"]
    for _, step in ipairs(STEPS) do
        if (g.schemaVersion or 0) < step.to then
            if step.perProfile then
                for _, profile in pairs(sv and sv.profiles or {}) do step.run(sv, profile) end
            else
                step.run(sv)
            end
            -- The runner owns the stamp; reached only if the step returned.
            g.schemaVersion = step.to
        end
    end
end
