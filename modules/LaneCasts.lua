local _, NS = ...
-- modules/LaneCasts.lua — the lanes' cast capture (spec §4): every cast of the player and the pet a
-- lane shows, sent as one LANE_PUSH(laneKey, item) each. The lane key IS the unit token ("player",
-- "pet"). modules/LaneRender.lua (plan Task 1.2) draws what this sends; nothing here draws.
--
-- THE SOURCE is UNIT_SPELLCAST_SUCCEEDED for `player` and `pet` (CastTrail's baseline), deduped by
-- castGUID. A cast-time spell's UNIT_SPELLCAST_START (or _EMPOWER_START) opens a cast in flight; an
-- _INTERRUPTED or _FAILED for THAT cast pushes its icon with interrupted = true (the red ✕, when the
-- lane's `markInterrupted` is on). An instant that fails never opened a cast and pushes nothing, and
-- neither does a press that fails while another cast is in flight: its castGUID is not the open one.
--
-- SECRETS (spec §3, Review Focus 1). In combat a spell ID or a castGUID may arrive secret. Each is
-- converted through NS.Secrets before anything compares, keys or truth-tests it:
--   * a secret spell ID still pushes: its texture is asked of the C side with the secret itself, in
--     pcall (NS.Compat.SpellTexture), and the payload's spellID is nil. It is never ignored (an ignore
--     list is keyed by plain IDs) and never cached.
--   * a secret castGUID skips the dedupe (it can be neither compared nor a key). Its interrupt is
--     marked only on _INTERRUPTED with a cast in flight; a secret _FAILED is dropped, because without
--     the castGUID it cannot be told apart from a failed press during the cast.
--   * the pet's name is read through Secrets.PlainString; a secret name reads as no name.
--
-- LISTENERS (LaneCasts.Listen). The fight record (modules/Casts.lua) hears the same casts from here
-- rather than registering UNIT_SPELLCAST_* a second time: every cast the rules above keep (a
-- SUCCEEDED once per castGUID, an interrupt of the cast in flight) is handed to each listener as
-- (unit, spellID, t, interrupted) BEFORE the lane's own switches (enabled, ignore list, the
-- interrupt mark), which decide only what a lane shows. The spell ID is handed raw: it may be secret.
--
-- REGISTRATION follows CURRENT settings (slash-commands-§7): nothing while stood down, and otherwise
-- the cast events for the units of the lanes whose `enabled` is on, and both units while a listener
-- is on (the record hears a lane that shows nothing), on one unit-filter frame through
-- NS.SafeRegisterUnitEvent (events-frames-taint-§1). LaneCasts.Sync() rebuilds it on login, on every
-- SETTINGS_CHANGED that can move it, and at stand-up; the lifecycle's stand-down calls Suspend.
-- Never COMBAT_LOG_EVENT_UNFILTERED: it is protected for addons on both clients.

local LaneCasts = {}
NS.LaneCasts = LaneCasts

local Secrets = NS.Secrets
local Perf = NS.Perf
local L = NS.L

--- The lanes, in order. Each lane's key is the unit token its casts are heard for.
LaneCasts.LANES = { "player", "pet" }
local IS_LANE = { player = true, pet = true }

--- How many plain castGUIDs each lane remembers for the dedupe (a ring: the oldest goes first). A
--- repeat of the same castGUID arrives within the same cast, so a short memory is enough.
LaneCasts.SEEN_MAX = 32

-- The events, and what each one means for a lane.
local EVENTS = {
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED",
}
local KIND = {
    UNIT_SPELLCAST_SUCCEEDED     = "succeeded",
    UNIT_SPELLCAST_START         = "start",
    UNIT_SPELLCAST_EMPOWER_START = "start",
    UNIT_SPELLCAST_INTERRUPTED   = "interrupted",
    UNIT_SPELLCAST_FAILED        = "failed",
}

local frame          -- the unit-filter frame (nil until a lane first registers)
local listeners = {} -- { { key, fn } }, in the order they listened
local registered     -- the unit set registered now, as a string key ("" = nothing), nil = unknown
local busTarget      -- this module's own bus receiver (architecture-§4)

-- Per lane: the dedupe ring { set = { [guid] = true }, ring = { guid... }, at = n, count = n } and the
-- cast in flight { guid = plain string|nil, secret = bool } or nil.
local state = {}

local function laneState(laneKey)
    local s = state[laneKey]
    if not s then
        s = { set = {}, ring = {}, at = 0, count = 0, flight = nil }
        state[laneKey] = s
    end
    return s
end

local function laneConfig(laneKey)
    local db = NS.db
    local lanes = db and db.profile and db.profile.lanes
    return lanes and lanes[laneKey]
end

-- ── dedupe ──────────────────────────────────────────────────────────────────────────────────────

local function seen(s, guid)
    return s.set[guid] == true
end

local function remember(s, guid)
    if s.set[guid] then return end
    local at = s.at % LaneCasts.SEEN_MAX + 1
    local old = s.ring[at]
    if old ~= nil then
        s.set[old] = nil
        s.count = s.count - 1
    end
    s.ring[at], s.at = guid, at
    s.set[guid] = true
    s.count = s.count + 1
end

--- How many castGUIDs a lane remembers now (the suites' bound check).
function LaneCasts.__seenCount(laneKey)
    return laneState(laneKey).count
end

-- ── the push ────────────────────────────────────────────────────────────────────────────────────

--- Whether `spellID` is on the lane's ignore list. A secret or missing ID is never ignored: the list
--- is keyed by plain IDs, and a secret is never a key.
--- @param laneKey string
--- @param spellID any
--- @return boolean
function LaneCasts.IsIgnored(laneKey, spellID)
    local id = Secrets.PlainNumber(spellID)
    if not id then return false end
    local cfg = laneConfig(laneKey)
    local ignore = cfg and cfg.ignore
    return type(ignore) == "table" and ignore[id] == true
end

local function push(laneKey, spellID, interrupted, t)
    local ok, texture = pcall(NS.Compat.SpellTexture, spellID)
    if not ok then texture = nil end
    NS.SendBus(NS.MSG.LANE_PUSH, laneKey, {
        texture     = texture,
        spellID     = Secrets.PlainNumber(spellID),
        t           = t,
        interrupted = interrupted == true,
    })
end

-- ── the handlers, one per kind ──────────────────────────────────────────────────────────────────
-- Each gets (s, guid, secretGUID, kind): `guid` is the plain castGUID or nil, and `secretGUID` says a
-- castGUID arrived but may not be looked at. Each answers whether the event is a cast: nil (none),
-- false (a cast), true (an interrupted cast).

local function onStart(s, guid, secretGUID)
    if guid or secretGUID then s.flight = { guid = guid, secret = secretGUID } end
    return nil
end

-- Whether the event's castGUID is the cast in flight. A plain one must match; a secret one counts only
-- when the cast in flight was heard with a secret castGUID too.
local function isFlight(s, guid, secretGUID)
    local f = s.flight
    if not f then return false end
    if guid then return f.guid == guid end
    return secretGUID and f.secret
end

-- A plain castGUID heard before is no new cast; a new one is remembered.
local function fresh(s, guid)
    if not guid then return true end
    if seen(s, guid) then return false end
    remember(s, guid)
    return true
end

local function onSucceeded(s, guid, secretGUID)
    if isFlight(s, guid, secretGUID) then s.flight = nil end
    if not fresh(s, guid) then return nil end
    return false
end

local function onEnded(s, guid, secretGUID, kind)
    if not isFlight(s, guid, secretGUID) then return nil end
    -- A secret castGUID's _FAILED cannot be told from a failed press during the cast: dropped.
    if secretGUID and kind == "failed" then return nil end
    s.flight = nil
    if not fresh(s, guid) then return nil end
    return true
end

local HANDLERS = {
    start       = onStart,
    succeeded   = onSucceeded,
    interrupted = onEnded,
    failed      = onEnded,
}

local function tell(unit, spellID, t, interrupted)
    for _, l in ipairs(listeners) do l.fn(unit, spellID, t, interrupted) end
end

-- UNIT_SPELLCAST_*(unit, castGUID, spellID). The unit token is plain; the other two may be secret.
local function hear(event, unit, castGUID, spellID)
    local kind = KIND[event]
    if not kind or not IS_LANE[unit] or NS.IsStoodDown() then return end
    local guid = Secrets.PlainString(castGUID)
    local secretGUID = guid == nil and castGUID ~= nil
    local interrupted = HANDLERS[kind](laneState(unit), guid, secretGUID, kind)
    if interrupted == nil then return end
    local t = GetTime()
    tell(unit, spellID, t, interrupted)
    local cfg = laneConfig(unit)
    if not cfg or cfg.enabled == false then return end
    if interrupted and cfg.markInterrupted == false then return end
    if LaneCasts.IsIgnored(unit, spellID) then return end
    push(unit, spellID, interrupted, t)
end

local function onEvent(_, event, ...)
    local t0 = Perf.on and debugprofilestop()
    hear(event, ...)
    if t0 then Perf.Note("laneCast", debugprofilestop() - t0) end
end

-- ── registration ────────────────────────────────────────────────────────────────────────────────

-- The units the CURRENT settings ask for, in lane order (none while stood down or before the store);
-- every lane's unit while a listener is on.
local function wantedUnits()
    local out = {}
    if not NS.db or NS.IsStoodDown() then return out end
    for _, laneKey in ipairs(LaneCasts.LANES) do
        local cfg = laneConfig(laneKey)
        if #listeners > 0 or (cfg and cfg.enabled ~= false) then out[#out + 1] = laneKey end
    end
    return out
end

local function ensureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", onEvent)
    return frame
end

local function unregisterAll()
    if frame then frame:UnregisterAllEvents() end
    registered = ""
end

--- Make the registrations match the current settings. Cheap when they already do.
function LaneCasts.Sync()
    local units = wantedUnits()
    local key = table.concat(units, ",")
    if key == registered then return end
    unregisterAll()
    registered = key
    if #units == 0 then return end
    local f = ensureFrame()
    for _, event in ipairs(EVENTS) do
        NS.SafeRegisterUnitEvent(f, event, NS.rejectedEvents, units[1], units[2])
    end
end

--- The lifecycle's stand-down: every registration goes, and no cast stays in flight.
function LaneCasts.Suspend()
    unregisterAll()
    state = {}
end

--- The lifecycle's stand-up: rebuilt from the CURRENT settings, never from a snapshot.
function LaneCasts.Resume()
    registered = nil
    LaneCasts.Sync()
end

--- Hand every cast the lanes' rules keep to `fn(unit, spellID, t, interrupted)` as well, under `key`
--- (one listener per key: listening again replaces it). `spellID` may be secret; `t` is GetTime().
--- @param key string
--- @param fn function
function LaneCasts.Listen(key, fn)
    LaneCasts.Unlisten(key)
    listeners[#listeners + 1] = { key = key, fn = fn }
    if registered ~= nil then LaneCasts.Sync() end
end

--- Stop handing casts to the listener under `key`.
function LaneCasts.Unlisten(key)
    for i = #listeners, 1, -1 do
        if listeners[i].key == key then table.remove(listeners, i) end
    end
    if registered ~= nil then LaneCasts.Sync() end
end

--- The unit-filter frame (nil until a lane first registered), for the suites.
function LaneCasts.Frame()
    return frame
end

-- A settings write that can move the registration: a lane's switch, or a whole profile change.
local function onSettingsChanged(_, path)
    if path == "profile" or (type(path) == "string" and path:match("^lanes%.[^.]+%.enabled$")) then
        LaneCasts.Sync()
    end
end

busTarget = NS.NewBusTarget()
if busTarget then busTarget:RegisterMessage(NS.MSG.SETTINGS_CHANGED, onSettingsChanged) end

-- ── the pet and the labels ──────────────────────────────────────────────────────────────────────

--- The pet's name, or nil when there is no pet (or its name may not be looked at).
--- @return string|nil
function LaneCasts.PetName()
    if not UnitExists("pet") then return nil end
    local name = Secrets.PlainString(UnitName("pet"))
    if name == "" then return nil end
    return name
end

--- The text a lane's label shows: the typed label, else the lane's own name (the pet's name on the
--- Pet lane, "Pet" while there is none; "You" on the Player lane).
--- @param laneKey string
--- @return string
function LaneCasts.LabelText(laneKey)
    local cfg = laneConfig(laneKey)
    local text = cfg and cfg.labelText
    if type(text) == "string" and text ~= "" then return text end
    if laneKey == "pet" then return LaneCasts.PetName() or L["Pet"] end
    return L["You"]
end
