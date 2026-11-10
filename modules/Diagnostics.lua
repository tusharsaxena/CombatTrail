local _, NS = ...
-- modules/Diagnostics.lua — this addon's sections of `/kct diagnostics` (debug-logging-§14, plan Task
-- 5.2), ported from DPS Race @045f479 and cut to Combat Trail's state. The library writes the markers,
-- the identity header (brand, version, client build, locale, the running LibKa0s minors, the state
-- flags), the per-section pcall and the cap; core/DebugLogSetup.lua hands it these sections at RUN
-- time, so this file loads with the modules.
--
-- READ STATE, NEVER ACT: no hold, no event, no timer, no write, safe in combat. Each section reads
-- through the modules' own query and Diagnose functions. `out:add` formats %s-only and runs every
-- argument through safeToString, so the values go in RAW. While stood down a runtime section says so
-- in one line and reads nothing; the stored settings and the store's counts still print.

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
    out:add("Diag", "fights stored=%s loadouts=%s bytes~%s", NS.Recorder.Count(), NS.Loadouts.Count(),
        NS.Retention.EstimateBytes())
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
    return {
        { "identity", identity },
        { "settings", settings },
        { "store", store },
        { "lanes", lanes },
        { "fight", fight },
        { "windows", windows },
        { "preview", preview },
        { "rejected", rejected },
    }
end
