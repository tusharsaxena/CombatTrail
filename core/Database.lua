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
NS.SCHEMA_VERSION = 12

-- Each step is idempotent against a fresh default profile. A profile-scoped step sets
-- `perProfile = true` and runs once for every stored profile, handed `(sv, profile, fresh)`: `fresh`
-- is true on a fresh install (no stamp when the runner started).
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
    -- 5 -> 6, per profile: the keys of the HUD's and the log window's retired states (2026-11-25,
    -- CLF-2). The HUD is one window of one static height (owner feedback item 12), so the auto-grow
    -- `hud.sizeMode` and its `hud.grow` edge go; the detached log is a standalone window (item 11), so
    -- the attached state's `log.window.attached`, `.side`, `.matchHud` and `.pinned` go. Nothing is
    -- carried across: a HUD that grew is fixed at its bars, and a log window that stood beside the HUD
    -- stands at its own stored place. Idempotent: a fresh profile stores none of them.
    { to = 6, perProfile = true, run = function(_, profile) NS.DropRetiredWindowKeys(profile) end },
    -- 6 -> 7, per profile: the lanes lock apart (2026-11-25, CLF-3, owner feedback item 15). Until now
    -- `general.locked` also kept Edit Mode from unlocking the lanes; from here the lanes read their own
    -- `general.lanesLocked`, so each profile's stored lock is carried across and nobody's lanes unlock
    -- by surprise. `general.locked` stays: it is still the DPS HUD's and the windows' lock. Idempotent: a
    -- lanes lock already stored is kept, and a profile with no stored lock stores nothing.
    { to = 7, perProfile = true, run = function(_, profile) NS.CarryLanesLock(profile) end },
    -- 7 -> 8, per profile: the keys the Combat Sequence retired (2026-11-25, CSEQ-1). No line carries an
    -- amount or a school and no hit, heal or target buff is captured, so the Amount column's toggle
    -- `log.view.columns.amount`, `log.view.schoolColors`, `log.show.hits`, `.heals`, `.minAmount` and
    -- `.targetBuffs`, the same three under `log.store.categories`, and the Taken and Heals chips'
    -- `log.results.chips.taken` and `.heals` go. Nothing is carried across: each served only what was
    -- removed. Idempotent: a fresh profile stores none of them.
    { to = 8, perProfile = true, run = function(_, profile) NS.DropRetiredSequenceKeys(profile) end },
    -- 8 -> 9, per profile: the Combat Log is the Combat Sequence everywhere (2026-11-25, CSEQ-2), its
    -- keys included: the stored `log` table moves to `sequence` (a deep merge, a key already stored
    -- under `sequence` winning, unless it equals its default: AceDB's copy into the active profile), and the Results fold `results.collapsedSections.log` moves to `.sequence`
    -- the same way. Steps 5, 6 and 8 run before it, on `log`, so nothing retired is carried across.
    -- Idempotent: a second run finds no `log`, and a profile with neither is left alone.
    { to = 9, perProfile = true, run = function(_, profile) NS.MoveLogToSequence(profile) end },
    -- 9 -> 10, per profile: the HUD's width default drops to its least, 260 (owner feedback round 4,
    -- R4-CT-06: "start off with the window at min width for new profiles"). AceDB stores only what
    -- differs from the default, so a profile that has been used and never changed its width stores none
    -- and would shrink with the default; this step writes today's 390 into each one, so only a new profile
    -- starts at 260. A fresh install (stamped 0 when the runner started: every install that ever loaded
    -- was stamped at least 1) has no old profile and is left alone, and so is a profile table with
    -- nothing stored. A width equal to the new default is AceDB's copy into the active profile, never a
    -- choice (a 260 chosen under the old default reads the same, and is pinned too). Idempotent: a
    -- width of its own is kept.
    { to = 10, perProfile = true, run = function(_, profile, fresh)
        if not fresh then NS.PinHudWidth(profile) end
    end },
    -- 10 -> 11, per profile: "Open when a fight starts" is the DPS HUD's (owner, 2026-11-26, SM-CT-LG22,
    -- R4-CT-08). The Combat Sequence's `sequence.drawer.autoOpen` goes; a stored off is carried to
    -- `hud.openOnPull`, and an on or nothing stored leaves the new default, on (the old default carried).
    -- Idempotent: a second run finds no old key.
    { to = 11, perProfile = true, run = function(_, profile) NS.MoveOpenOnPull(profile) end },
    -- 11 -> 12, per profile: the Combat Sequence's who colors are removed (owner, 2026-11-26,
    -- SM-CT-LG27, R4-CT-08): `sequence.colors` (you, useClassColorYou, hostile, hostileFromSkin, friendly,
    -- friendlyFromSkin) goes whole; nothing drew them since the Source and Target columns went. The
    -- skin tokens `ct.log.hostile` and `ct.log.friendly` go too, and LibKa0s stores no per-token
    -- override, so no stored value names them. Idempotent: a fresh profile stores none.
    { to = 12, perProfile = true, run = function(_, profile) NS.DropWhoColors(profile) end },
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

--- Step 6's body: the HUD's `sizeMode` and `grow`, and the log window's `attached`, `side`, `matchHud`
--- and `pinned`, dropped. A profile with neither table is left alone.
function NS.DropRetiredWindowKeys(profile)
    if type(profile) ~= "table" then return end
    local hud = profile.hud
    if type(hud) == "table" then hud.sizeMode, hud.grow = nil, nil end
    local log = profile.log
    local w = type(log) == "table" and log.window
    if type(w) == "table" then w.attached, w.side, w.matchHud, w.pinned = nil, nil, nil, nil end
end

--- Step 8's body: `profile.log`'s keys the Combat Sequence retired (the Amount column's toggle, school
--- colors, the hits, heals, target buffs and least amount shown and saved, the Taken and Heals chips)
--- dropped. A profile with no `log` table is left alone.
function NS.DropRetiredSequenceKeys(profile)
    local log = type(profile) == "table" and profile.log
    if type(log) ~= "table" then return end
    local view, show, store, results = log.view, log.show, log.store, log.results
    if type(view) == "table" then
        view.schoolColors = nil
        if type(view.columns) == "table" then view.columns.amount = nil end
    end
    if type(show) == "table" then show.hits, show.heals, show.minAmount, show.targetBuffs = nil, nil, nil, nil end
    local cats = type(store) == "table" and store.categories
    if type(cats) == "table" then cats.hits, cats.heals, cats.targetBuffs = nil, nil, nil end
    local chips = type(results) == "table" and results.chips
    if type(chips) == "table" then chips.taken, chips.heals = nil, nil end
end

-- `from`'s keys copied into `into`, tables merged key by key. A value `into` already holds wins, unless
-- it equals its default in `dflt`: that is AceDB's copy into the active profile (savedvariables-§1, as
-- clearCopiedGlowDefaults above reads it), never a choice, so the moved value takes its place.
local function mergeInto(into, from, dflt)
    for k, v in pairs(from) do
        local have = rawget(into, k)
        -- Not `dflt[k] or nil`: a default of false is a default too (the drawer's chips, R4-CT-04).
        local d = nil
        if type(dflt) == "table" then d = dflt[k] end
        if have == nil then
            into[k] = v
        elseif type(have) == "table" then
            if type(v) == "table" then mergeInto(have, v, d) end
        elseif d ~= nil and have == d then
            into[k] = v
        end
    end
end

--- Step 9's body: `profile.log` moved to `profile.sequence` (deep merged, a key stored under
--- `sequence` winning unless it is only the default's copy), then cleared, and the Results fold `results.collapsedSections.log` moved to
--- `.sequence` the same way. A profile with neither `log` nor that fold is left alone.
function NS.MoveLogToSequence(profile)
    if type(profile) ~= "table" then return end
    local log = rawget(profile, "log")
    if type(log) == "table" then
        local seq = rawget(profile, "sequence")
        local D = NS.defaults and NS.defaults.profile and NS.defaults.profile.sequence
        if type(seq) == "table" then mergeInto(seq, log, D) else profile.sequence = log end
    end
    profile.log = nil
    local results = rawget(profile, "results")
    local folds = type(results) == "table" and rawget(results, "collapsedSections")
    if type(folds) ~= "table" or rawget(folds, "log") == nil then return end
    if rawget(folds, "sequence") == nil then folds.sequence = folds.log end
    folds.log = nil
end

--- Step 10's body: `profile.hud.width` written as 390, the width before R4-CT-06, on a stored profile
--- that keeps none (or only the default's copy). A profile with nothing stored, or with its own width,
--- is left alone.
NS.PINNED_HUD_WIDTH = 390
function NS.PinHudWidth(profile)
    if type(profile) ~= "table" or next(profile) == nil then return end
    local hud = rawget(profile, "hud")
    if type(hud) ~= "table" then
        hud = {}
        profile.hud = hud
    end
    local w = rawget(hud, "width")
    local D = NS.defaults and NS.defaults.profile and NS.defaults.profile.hud
    if w == nil or (D and w == D.width) then hud.width = NS.PINNED_HUD_WIDTH end
end

--- Step 11's body: `profile.sequence.drawer.autoOpen` dropped, a stored false carried to
--- `profile.hud.openOnPull`. A profile with no drawer table is left alone.
function NS.MoveOpenOnPull(profile)
    local seq = type(profile) == "table" and rawget(profile, "sequence")
    local drawer = type(seq) == "table" and rawget(seq, "drawer")
    if type(drawer) ~= "table" then return end
    local old = rawget(drawer, "autoOpen")
    drawer.autoOpen = nil
    if old ~= false then return end
    local hud = rawget(profile, "hud")
    if type(hud) ~= "table" then
        hud = {}
        profile.hud = hud
    end
    hud.openOnPull = false
end

--- Step 12's body: `profile.sequence.colors` dropped. A profile with no `sequence` table is left alone.
function NS.DropWhoColors(profile)
    local seq = type(profile) == "table" and rawget(profile, "sequence")
    if type(seq) == "table" then seq.colors = nil end
end

--- Step 7's body: `profile.general.locked`, when stored true, copied to `general.lanesLocked` where
--- the profile stores no lanes lock yet. A profile with no `general` table is left alone.
function NS.CarryLanesLock(profile)
    local g = type(profile) == "table" and profile.general
    if type(g) ~= "table" or g.lanesLocked ~= nil then return end
    if g.locked == true then g.lanesLocked = true end
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
    -- A fresh install: no stamp yet (0, the default). Every install that ever ran this loop was stamped
    -- at least 1 (the first release's step), so 0 means nothing was stored before this load.
    local fresh = (tonumber(g.schemaVersion) or 0) == 0
    for _, step in ipairs(STEPS) do
        if (g.schemaVersion or 0) < step.to then
            if step.perProfile then
                for _, profile in pairs(sv and sv.profiles or {}) do step.run(sv, profile, fresh) end
            else
                step.run(sv)
            end
            -- The runner owns the stamp; reached only if the step returned.
            g.schemaVersion = step.to
        end
    end
end
