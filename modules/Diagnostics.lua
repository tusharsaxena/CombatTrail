local _, NS = ...
-- modules/Diagnostics.lua — this addon's sections of `/ct diagnostics` (debug-logging-§14, plan Task
-- 5.2), ported from DPS Race @045f479 and cut to Combat Trail's state. The library writes the markers,
-- the identity header (brand, version, client build, locale, the running LibKa0s minors, the state
-- flags), the per-section pcall and the cap; core/DebugLogSetup.lua hands it these sections at RUN
-- time, so this file loads with the modules.
--
-- READ STATE, NEVER ACT: no hold, no event, no timer, no write, safe in combat. Each section reads
-- through the modules' own query and Diagnose functions. `out:add` formats %s-only and runs every
-- argument through safeToString, so the values go in RAW. While stood down a runtime section says so
-- in one line and reads nothing; the stored settings and the store's counts still print.
--
-- RACE MODE (Retail, race plan Task E1): a `race` section after the fight's, absent on WoW Forever
-- (clients-§4): the race state, its fight and session, the pending races (db.global.pendingRaces), the
-- race boards held, the Race window, the countdown and the sample race. The toast's line is in the
-- windows section, on both clients.

NS.Diagnostics = NS.Diagnostics or {}
local Diag = NS.Diagnostics

local function stoodDown()
    local LC = NS.lifecycle
    return LC ~= nil and LC:IsDown()
end

-- One line for a runtime section while stood down; true when it wrote it.
local function down(out)
    if not stoodDown() then return false end
    out:add("Diag", "stood down: runtime state released")
    return true
end

local function onOff(v) return v and "on" or "off" end

local function identity(out)
    local db, LC = NS.db, NS.lifecycle
    local g = db and db.global
    out:add("Diag", "schema stored=%s code=%s fightFormat=%s", g and g.schemaVersion, NS.SCHEMA_VERSION,
        NS.Recorder.CT_SCHEMA)
    out:add("Diag", "profile=%s", db and db:GetCurrentProfile())
    out:add("Diag", "enabled=%s stoodDown=%s", NS.GetSetting("general.enabled"), LC and LC:IsDown())
    out:joined("Diag", "holds", LC and LC:Holds() or {})
end

local function settings(out)
    out:nonDefaults(NS.Schema, function(row) return NS.GetSetting(row.path) end, nil, nil,
        { always = { "general.enabled" } })
end

-- The store: stored configuration, so it prints stood down too.
local function store(out)
    out:add("Diag", "fights stored=%s loadouts=%s gearSets=%s bytes~%s", NS.Recorder.Count(),
        NS.Loadouts.Count(), NS.Loadouts.GearCount(), NS.Retention.EstimateBytes())
end

local function lanes(out)
    out:add("Diag", "lanes player=%s pet=%s", onOff(NS.GetSetting("lanes.player.enabled") ~= false),
        onOff(NS.GetSetting("lanes.pet.enabled") ~= false))
    if down(out) then return end
    local casts = NS.LaneCasts.Diagnose()
    out:add("Diag", "cast events=%s listeners=%s", casts.registered, casts.listeners)
    for _, key in ipairs(NS.LaneCasts.LANES) do
        local frame = NS.LaneRender.Frame(key)
        local shown = NS.LaneVisibility.Decide(key)
        out:add("Diag", "lane %s shown=%s decides=%s icons=%s mode=%s unlocked=%s", key,
            frame ~= nil and frame:IsShown(), shown, NS.LaneRender.Count(key),
            NS.GetSetting("lanes." .. key .. ".anchor.mode"), NS.LaneAnchor.IsUnlocked())
    end
end

local function fight(out)
    if down(out) then return end
    local cur = NS.Fight.Current()
    out:add("Diag", "fight state=%s id=%s session=%s meter=%s chart fights=%s", NS.Fight.State(),
        cur and cur.id, cur and cur.sessionID, (NS.Meter.IsAvailable()), NS.Slices.Held())
    out:add("Diag", "probe armed=%s", NS.Probe.IsArmed())
end

local function windows(out)
    if down(out) then return end
    local hud = NS.Hud.Diagnose()
    out:add("Diag", "hud state=%s body=%s pinned=%s locked=%s", hud.state, hud.body, hud.pinned, hud.locked)
    local results = NS.Results.Diagnose()
    out:add("Diag", "results shown=%s rows=%s selected=%s detail=%s", results.shown, results.rows,
        results.selected, results.detailOpen)
    local tl = NS.ResultsTimeline.Diagnose()
    out:add("Diag", "timeline shown=%s rows=%s zoom=%s", tl.shown, tl.rows, tl.zoom)
    out:add("Diag", "compare shown=%s gear shown=%s", NS.ResultsCompare.IsShown(), NS.ResultsGear.IsShown())
    local toast = NS.BestToast.Diagnose()
    out:add("Diag", "toast shown=%s waiting=%s key=%s", toast.shown, toast.waiting, toast.key)
end

-- The pending races (one slot per character) and the race boards the store's bests hold.
local function pendingCount()
    local g = NS.db and NS.db.global
    local n = 0
    for _ in pairs(g and type(g.pendingRaces) == "table" and g.pendingRaces or {}) do n = n + 1 end
    return n
end

local function raceBoards()
    local n = 0
    for key in pairs(NS.Bests.Board()) do
        if tostring(key):find("|race:", 1, true) then n = n + 1 end
    end
    return n
end

local function race(out)
    if down(out) then return end
    local R = NS.Race
    local f = R.Fight()
    out:add("Diag", "race state=%s mode=%s fight=%s session=%s pending=%s boards=%s", R.State(),
        onOff(NS.RaceMode.On()), f and f.id, f and f.sessionID, pendingCount(), raceBoards())
    local w = NS.RaceWindow.Diagnose()
    out:add("Diag", "race window shown=%s body=%s attached=%s side=%s ticking=%s", w.shown, w.body, w.attached,
        w.side, w.ticking)
    local c = NS.Countdown.Diagnose()
    out:add("Diag", "countdown shown=%s scheduled=%s owner=%s", c.shown, c.scheduled, c.owner)
    local sample = NS.RaceSample.Diagnose()
    out:add("Diag", "race sample=%s state=%s live=%s", sample.on, sample.state, sample.live)
end

local function preview(out)
    if down(out) then return end
    local p = NS.Preview.Diagnose()
    out:add("Diag", "test active=%s mode=%s phase=%s scenario=%s ticking=%s", p.active, p.mode, p.phase,
        p.scenario, p.ticking)
end

local function rejected(out)
    out:list("Diag", "rejected events", NS.rejectedEvents or {})
end

--- The sections, in report order (debug-logging-§14's content order: identity, settings, domain
--- state, rejected events).
function Diag.Sections()
    local out = {
        { "identity", identity },
        { "settings", settings },
        { "store", store },
        { "lanes", lanes },
        { "fight", fight },
        { "windows", windows },
        { "preview", preview },
        { "rejected", rejected },
    }
    -- Race mode's section, after the fight's, on Retail only (clients-§4).
    if NS.Compat.ForClient({ "retail" }) then table.insert(out, 6, { "race", race }) end
    return out
end
