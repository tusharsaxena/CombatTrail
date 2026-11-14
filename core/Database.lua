local addonName, NS = ...
-- core/Database.lua — AceDB setup, the profile callbacks and the schemaVersion migration runner.

-- Step 3 asks the call-out major to rewrite its own retired glow choice (its MigrateGlow), so the
-- mapping is the library's and never a copy here; nil without the library, and the step then only
-- drops the retired keys.
local Callout = LibStub and LibStub("LibKa0s-Callout-1.0", true)

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
