local addonName, NS = ...
-- core/Database.lua — AceDB setup, the profile callbacks and the schemaVersion migration runner.

-- The runner's target: the highest step's `to` (savedvariables-§1). Distinct from the FIGHT RECORD
-- format version (modules/Recorder.lua's CT_SCHEMA, spec §5), which never migrates settings.
NS.SCHEMA_VERSION = 1

-- Each step is idempotent against a fresh default profile. A profile-scoped step sets
-- `perProfile = true` and runs once for every stored profile.
local STEPS = {
    { to = 1, run = function() end },   -- 0 -> 1: the first release's shape, a no-op
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
