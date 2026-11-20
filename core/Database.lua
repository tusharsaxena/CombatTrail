local addonName, NS = ...
-- core/Database.lua — AceDB setup, the profile callbacks and the schemaVersion migration runner.

-- Step 3 asks the call-out major to rewrite its own retired glow choice (its MigrateGlow), so the
-- mapping is the library's and never a copy here; nil without the library, and the step then only
-- drops the retired keys. The skin-defaults step asks it for its own one-time move (MoveToSkin).
local Callout = LibStub and LibStub("LibKa0s-Callout-1.0", true)
local Skin = LibStub and LibStub("LibKa0s-Skin-1.0", true)

-- ── the one-time step onto the skin's defaults (LibKa0s v1.108.0, R-2) ──────────────────────────
-- The skin-defaults audit (Ka0sAddonsCommonTasks docs/2026-11-20-SKIN_DEFAULTS_AUDIT, LibKa0s#97) and
-- the owner's rulings R-2, U-1 and U-14 of 2026-11-20 move three of this addon's defaults onto the
-- skin, and the call-out's look. AceDB stores no value equal to its default, so a profile that never
-- picked follows with no step; this step moves only a value still stored at its old default (a
-- profile written whole, or copied), and a picked value stays. Per profile, once, under the record
-- `skin.defaultsMoved` (defaults/Profile.lua, no schema row), from the boot over every stored profile
-- and from every profile event (skinning-§9, *Who moves, and the one step*). Skin.FollowOnce is not
-- the step: its record, `skin.fullSkinReset`, belongs to the v1.85.0 move this addon never needed.
--   hud.clock.fontFlags            ""    -> "@skin": the HUD fight clock is no race clock (U-14)
--   hud.spells.borderStyleFromSkin false -> true: the spell rows' border follows the skin (SD-SK-CT.3)
--   hud.spells.borderColorFromSkin false -> true
-- and the call-out's own list, Callout:FollowKeys / MoveToSkin over `profile.callout` (U-1: the face
-- and the outline, each only while still at its v1.107.0 value), with the library
-- present (it is absent in the degraded mode, core/CalloutSetup.lua, and on WoW Forever there is no
-- `callout` table).
NS.SKIN_DEFAULTS_FROM = {
    { "hud.clock.fontFlags", "" },
    { "hud.spells.borderStyleFromSkin", false },
    { "hud.spells.borderColorFromSkin", false },
}

-- The picks the same step keeps drawing. Four companions are new with this build and default on
-- (lanes.<k>.bgTextureFromSkin, tickColorFromSkin, nowColorFromSkin and hud.chart.bestColorFromSkin), and
-- while one is on its reader draws the skin's value, so a pick stored before it would stop showing. R-2:
-- a stored pick stays. Where the profile stores a value that differs from its default, the step writes
-- the companion false, so the pick keeps drawing. The pick's default is unchanged by this build, so it
-- is read from NS.defaults (defaults/Profile.lua) at the step, never copied here. A color is compared
-- per component: AceDB strips a component equal to its default, so a missing one is the default.
--   { the pick, the companion written false }
NS.SKIN_PICKS_KEPT = {
    { "lanes.player.bgTexture", "lanes.player.bgTextureFromSkin" },
    { "lanes.pet.bgTexture", "lanes.pet.bgTextureFromSkin" },
    { "lanes.player.tickColor", "lanes.player.tickColorFromSkin" },
    { "lanes.pet.tickColor", "lanes.pet.tickColorFromSkin" },
    { "lanes.player.nowColor", "lanes.player.nowColorFromSkin" },
    { "lanes.pet.nowColor", "lanes.pet.nowColorFromSkin" },
    { "hud.chart.bestColor", "hud.chart.bestColorFromSkin" },
}

-- The table holding `path`'s last segment in `t`, and that segment; nil where a table is missing.
local function walk(t, path)
    local parent, leaf = t, nil
    for seg in path:gmatch("[^.]+") do
        if leaf ~= nil then
            parent = parent[leaf]
            if type(parent) ~= "table" then return nil end
        end
        leaf = seg
    end
    return parent, leaf
end

-- Whether a stored value differs from its old default: a string by value, a color by any component
-- it stores (one it does not store is the default's).
local function differs(v, default)
    if type(default) ~= "table" then return v ~= nil and v ~= default end
    if type(v) ~= "table" then return false end
    for _, c in ipairs({ "r", "g", "b", "a" }) do
        if type(v[c]) == "number" and math.abs(v[c] - default[c]) > 1e-6 then return true end
    end
    return false
end

--- The one-time step onto the skin's defaults, on one profile. Answers true when it ran (the record
--- then written), false on a profile it already ran on or a value that is no profile.
--- @param profile table  the profile root
--- @return boolean
function NS.FollowSkinDefaults(profile)
    if type(profile) ~= "table" then return false end
    if type(profile.skin) == "table" and profile.skin.defaultsMoved == true then return false end
    local keys = {}
    for _, entry in ipairs(NS.SKIN_DEFAULTS_FROM) do
        local parent, leaf = walk(profile, entry[1])
        if parent ~= nil and parent[leaf] == entry[2] then keys[#keys + 1] = entry[1] end
    end
    if Skin and type(Skin.ResetToSkin) == "function" then
        Skin.ResetToSkin(profile, keys)
    else
        -- No Skin major: the same writes by hand, creating no table on the way.
        for _, path in ipairs(keys) do
            local parent, leaf = walk(profile, path)
            if type(parent[leaf]) == "boolean" then parent[leaf] = true else parent[leaf] = "@skin" end
        end
    end
    local defaults = NS.defaults and NS.defaults.profile
    for _, entry in ipairs(defaults and NS.SKIN_PICKS_KEPT or {}) do
        local parent, leaf = walk(profile, entry[1])
        local dParent, dLeaf = walk(defaults, entry[1])
        if parent ~= nil and dParent ~= nil and differs(parent[leaf], dParent[dLeaf]) then
            local cParent, cLeaf = walk(profile, entry[2])
            cParent[cLeaf] = false
        end
    end
    if Callout and type(Callout.MoveToSkin) == "function" and type(profile.callout) == "table" then
        -- The glow color stays where it is: Combat Trail's default is the swatch (SD-CT-DEF), so a
        -- stored `glowColorFromSkin = false` is this addon's default, not an old one to move.
        local glowFromSkin = profile.callout.glowColorFromSkin
        Callout:MoveToSkin(profile.callout)
        profile.callout.glowColorFromSkin = glowFromSkin
    end
    if type(profile.skin) ~= "table" then profile.skin = {} end
    profile.skin.defaultsMoved = true
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
NS.SCHEMA_VERSION = 3

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
    -- the black swatch at 1, -1 (it was each word's kind color at 0, 0). The owner's defaults; no step.
    { to = 3, perProfile = true, run = function(_, profile)
        local t = type(profile) == "table" and profile.callout
        if type(t) ~= "table" then return end
        clearCopiedGlowDefaults(t)
        if Callout and Callout.MigrateGlow then Callout:MigrateGlow(t) end
        t.texts, t.muted = nil, nil
    end },
}
NS.__migrationSteps = STEPS   -- test seam only

--- A profile switch, copy or reset replaces the whole profile wholesale: the stored `enabled` can
--- flip, so re-take the hold and re-decide (slash-commands-§7: these callbacks are SETUP and stay live
--- while disabled). One line per act (debug-logging-§10).
function NS.OnProfileChanged(event, _db, key)
    NS.Debug("Set", "%s '%s'", event or "profile", key or (NS.db and NS.db:GetCurrentProfile()) or "?")
    -- The one-time step onto the skin's defaults, on the profile now in force (a new, copied or reset
    -- one), before anything reads it.
    if NS.db and NS.db.profile then NS.FollowSkinDefaults(NS.db.profile) end
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
    -- The one-time step onto the skin's defaults, over every stored profile, each under its own
    -- record (NS.FollowSkinDefaults, above), after the ladder.
    for _, profile in pairs(sv and sv.profiles or {}) do NS.FollowSkinDefaults(profile) end
end
