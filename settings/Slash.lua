local _, NS = ...
-- settings/Slash.lua — the ordered NS.COMMANDS table and the LibKa0s-Slash-1.0 descriptor; `/ct` and
-- `/combattrail` both reach the one dispatcher.

NS.Slash = NS.Slash or {}
local Sl = NS.Slash
local L = NS.L

local function out(line) NS.Print(line) end

local cli   -- built at the bottom, once NS.COMMANDS exists; handlers reach it at CALL time
local doEnabled, doDebug, doPerf, doSetVerb
local doResults, doHud, doLock, doTest, doSim, doPurge, doProbe, doLane, doIgnore

--- A feature verb's handler behind the stand-down: the dispatcher refuses every feature verb while the
--- `disabled` hold is taken, and this answers the `perf` hold's line (slash-commands-§7, "Which
--- refusal, by hold") before the handler can act.
local function feature(fn)
    return function(rest)
        local line = NS.StoodDownRefusal()
        if line then return out(line) end
        return fn(rest)
    end
end

-- Positional triples {name, desc, fn}: a table of named fields is invisible to the library. The
-- reserved verbs mean the same thing in every Ka0s addon (slash-commands-§2); `diagnostics` has no
-- alias of any kind. The feature verbs (spec §8) follow `version`; the dispatcher refuses each of
-- them with the one line while the addon is disabled (slash-commands-§2, §7).
NS.COMMANDS = {
    { "help",        L["Show this help"],                          function() cli:PrintHelp() end },
    { "config",      L["Open the settings panel"],                 function() NS.OpenOptionsPanel() end },
    -- The reserved `skin` verb (LibKa0s v1.82.0's O.SkinVerb, ruling D-16), right after `config`: the
    -- skin picker a new profile shows, on demand (core/SkinSetup.lua's NS.RunSkinVerb). Not a live
    -- verb, so the dispatcher refuses it while disabled; behind feature() for the perf hold's line.
    { "skin",        L["Choose a skin: open the skin picker"],     feature(function() NS.RunSkinVerb() end) },
    { "enable",      L["Turn the addon on"],                       function() doEnabled(true) end },
    { "disable",     L["Turn the addon off without unloading it"], function() doEnabled(false) end },
    { "list",        L["List every setting"],                      function() cli:CliList() end },
    { "get",         L["Read one setting: /ct get path"],         function(rest) cli:CliGet(rest) end },
    { "set",         L["Write one setting: /ct set path value"],  function(rest) cli:CliSet(rest) end },
    { "reset",       L["Reset one setting: /ct reset path"],      function(rest) cli:CliReset(rest) end },
    { "resetall",    L["Reset every setting (asks first)"],        function() NS.ShowResetAll() end },
    { "debug",       L["Debug console; on/off set logging, diagnostics writes the report"],
                                                                   function(rest) doDebug(rest) end },
    { "diagnostics", L["Write the diagnostics report to the debug console"],
                                                                   function() NS.DebugLog:RunDiagnostics() end },
    { "perf",        L["Performance capture; try /ct perf help"], function(rest) doPerf(rest) end },
    { "version",     L["Print the addon version"],                 function() cli:CliVersion() end },
    -- Feature verbs (spec §8). Each handler sits behind feature(), below.
    { "results",     L["Open the Results window, with your fight history"],
                                                                   feature(function(rest) doResults(rest) end) },
    { "hud",         L["The DPS HUD: /ct hud show or hide"],      feature(function(rest) doHud(rest) end) },
    { "lock",        L["Lock the lanes and the DPS HUD in place"], feature(function() doLock(true) end) },
    { "unlock",      L["Unlock the lanes and the DPS HUD to move them"],
                                                                   feature(function() doLock(false) end) },
    { "test",        L["Test mode: sample data in the lanes, the HUD and the Results window"],
                                                                   feature(function() doTest() end) },
    { "sim",         L["Sim mode: a made-up fight played in real time"],
                                                                   feature(function(rest) doSim(rest) end) },
    { "purge",       L["Delete stored fights older than the History page's limit"],
                                                                   feature(function(rest) doPurge(rest) end) },
    { "probe",       L["Check what this client reports for the meter, casts and your pet"],
                                                                   feature(function(rest) doProbe(rest) end) },
    -- Settings verbs over the lanes' own rows: not behind feature(), and live while disabled
    -- (HOST_LIVE_VERBS below), as the schema CLI that writes the same rows is.
    { "lane",        L["Turn a lane on or off: /ct lane player|pet on|off"],
                                                                   function(rest) doLane(rest) end },
    { "ignore",      L["A lane's ignore list: /ct ignore add|remove <spell> [player|pet]"],
                                                                   function(rest) doIgnore(rest) end },
}

--- Run one verb's handler by name: the launcher's Enabled entry reaches `enable`/`disable` through
--- here, so the menu and the verb are one handler (launcher-§2).
function NS.RunVerb(verb, rest)
    for _, entry in ipairs(NS.COMMANDS) do
        if entry[1] == verb then return entry[3](rest or "") end
    end
end

--- slash-commands-§2's thirteen reserved verbs: they answer while disabled. Named once, here, for the
--- library-absent stub's gate; the live dispatcher reads its own lib.LIVE_VERBS (pinned equal by
--- tests/test_slash.lua).
NS.SLASH_LIVE_VERBS = {
    help = true, config = true, version = true, enable = true, disable = true, debug = true,
    diagnostics = true, perf = true, get = true, set = true, list = true, reset = true, resetall = true,
}

--- The host verbs that also answer while disabled, on BOTH arms: the descriptor's `liveVerbs` below
--- (the library's LIVE_VERBS plus these) and the library-absent stub's gate. `lane` and `ignore` read
--- and write the lanes' own settings, as `get`/`set` do, so the addon declines slash-commands-§2's
--- feature-verb refusal for them: a player reads and repairs settings while the addon is off.
local HOST_LIVE_VERBS = { "lane", "ignore" }
local HOST_LIVE = {}
for _, verb in ipairs(HOST_LIVE_VERBS) do HOST_LIVE[verb] = true end

local SlashLib = LibStub and LibStub("LibKa0s-Slash-1.0", true)
local degraded = false

if not SlashLib then
    -- Degrade, never error: `/ct` is registered unconditionally, so something must answer it. The
    -- host verbs keep working; the schema CLI names the missing library. The ONE library string this
    -- stub carries is DISABLED_LINE_FORMAT, pinned by tests/test_slash.lua against the live major;
    -- every other line below is the stub's own plain wording, never a copy of the library's.
    degraded = true
    local MISSING = L["%s is unavailable: the LibKa0s library did not load."]
    SlashLib = { DISABLED_LINE_FORMAT = "%s is disabled \226\128\148 enable it with |cFFFFFF00%s|r" }
    Sl.__stubFormat = SlashLib.DISABLED_LINE_FORMAT
    function SlashLib.New(_, d)
        local stub = {}
        local function absent(verb) return function() out(MISSING:format(d.slash .. " " .. verb)) end end
        for _, verb in ipairs({ "List", "Get", "Set", "Reset", "ResetAll", "Profile" }) do
            stub["Cli" .. verb] = absent(verb:lower())
        end
        stub.SetRowAnnotator = function() end
        stub.ProfileSwitch = function() return false end
        stub.DisabledLine = function()
            return SlashLib.DISABLED_LINE_FORMAT:format(d.brandName, d.slash .. " enable")
        end
        local function version() return tostring(d.version and d.version() or "?") end
        stub.CliVersion = function() out(L["%s version %s"]:format(d.brandName, version())) end
        stub.LandingRows = function()
            local rows = {}
            for _, e in ipairs(d.commands) do rows[#rows + 1] = d.slash .. " " .. e[1] .. "  " .. e[2] end
            return rows
        end
        stub.HelpRows = function()
            local rows = {}
            for _, r in ipairs(stub.LandingRows()) do rows[#rows + 1] = "  " .. r end
            return rows
        end
        stub.PrintHelp = function()
            out(L["%s commands (reduced: the LibKa0s library is missing)"]:format(d.slash))
            for _, r in ipairs(stub.HelpRows()) do out(r) end
        end
        -- Minimal dispatch is the host's own routing (slash-commands-§1): split, look up, call.
        stub.OnSlash = function(_, msg)
            local raw = tostring(msg or ""):match("^%s*(.-)%s*$")
            if raw == "" then return NS.RunVerb("config") end
            local verb, rest = raw:match("^(%S+)%s*(.*)$")
            verb = verb:lower()
            verb = (d.aliases or {})[verb] or verb
            for _, e in ipairs(d.commands) do
                if e[1] == verb then
                    -- The disabled gate the live dispatcher applies: a feature verb refuses with the
                    -- one line while the `disabled` hold is taken (slash-commands-§7).
                    if d.isEnabled and not d.isEnabled() and not NS.SLASH_LIVE_VERBS[verb]
                        and not HOST_LIVE[verb] then
                        return out(stub.DisabledLine())
                    end
                    return e[3](rest or "")
                end
            end
            stub.PrintHelp()
        end
        return stub
    end
end

-- The live set: the library's reserved verbs, then this addon's own. The stub has no LIVE_VERBS and
-- reads NS.SLASH_LIVE_VERBS and HOST_LIVE_VERBS itself.
local liveVerbs = {}
for i, verb in ipairs(SlashLib.LIVE_VERBS or {}) do liveVerbs[i] = verb end
for _, verb in ipairs(HOST_LIVE_VERBS) do liveVerbs[#liveVerbs + 1] = verb end
Sl.LIVE_VERBS = liveVerbs

cli = SlashLib:New({
    -- The library takes the words as a player types them, the slash included.
    slash        = NS.SLASH_CMD,
    slashAliases = { "/" .. NS.SLASH_LONG },
    commands     = NS.COMMANDS,                       -- passed IN, never owned by the library
    aliases      = { options = "config" },
    -- The disabled gate: every verb not on the library's live list answers the one refusal line
    -- while the `disabled` hold is taken (slash-commands-§2, §7). Not IsStoodDown: the `perf` hold
    -- alone must not print the disabled line.
    isEnabled    = function() return not NS.IsDisabled() end,
    liveVerbs    = liveVerbs,
    brandName    = NS.BRAND,
    print        = function(line) out(line) end,
    version      = function() return NS.Version() end,
    get          = function(path) return NS.GetSetting(path) end,
    set          = function(path, value) return NS.SetByPath(path, value) end,   -- the single write seam
    findRow      = function(path) return NS.FindSchemaRow(path) end,
    allRows      = function() return NS.Schema end,
    applyDefault = function(row) return NS.ApplyDefault(row) end,
    bulkBegin    = function(act, scope) NS.Bulk.Begin(act, scope) end,
    bulkEnd      = function(act, scope, count, err, info) NS.Bulk.End(act, scope, count, err, info) end,
    groupKey     = function(row) return (row.page or "?") .. " \226\128\186 " .. (row.group or "?") end,
    format       = function(row, value) return NS.FormatSchemaValue(row, value) end,
    -- The dispatcher's own refusals land in the console as one `Cmd` line each (debug-logging-§4).
    debug        = function(tag, message) NS.Debug(tag, "%s", message) end,
})
Sl.__dispatcher = cli

--- A verb that writes one composed Master row (`enable`/`disable` the `general.enabled` row,
--- `lock`/`unlock` the `general.locked` row): through the seam, echoed by the CLI so the stored value is what the player reads
--- back (slash-commands-§2, §8). Degraded, the write goes through the seam's writeThrough list and is
--- acknowledged only if it landed (options-ui-§1); a written-through value runs no onChange, so the
--- caller's `react` stands in for it.
function doSetVerb(path, want, react)
    if not degraded and NS.FindSchemaRow(path) then
        cli:CliSet(path .. " " .. tostring(want))
        return
    end
    local ok, err = NS.SetByPath(path, want)
    if ok then
        if react then react(want) end
        out(L["%s = %s"]:format(path, tostring(want)))
    else
        out(tostring(err))
    end
end

function doEnabled(want)
    doSetVerb("general.enabled", want, NS.ApplyEnabled)
end

--- `diagnostics` is tested FIRST (debug-logging-§14), then `on`/`off`; any other word, or none,
--- toggles the WINDOW with the flag untouched. A retired `diag` is just an unknown word.
function doDebug(rest)
    if not NS.DebugLog:DebugVerb(rest) then NS.DebugLog:Toggle() end
end

--- `perf`: the reserved verb the HOST registers (performance-§4). The library returns lines.
function doPerf(rest)
    local lines = NS.Perf.OnCommand(rest)
    if type(lines) ~= "table" then return end
    for _, line in ipairs(lines) do out(line) end
end

-- ── the feature verbs (spec §8) ───────────────────────────────────────────────────────────────────
-- Each reaches its feature through the same handler the launcher's menu and the key bindings run
-- (core/CombatTrail.lua), never a copy. The dispatcher has already refused them while disabled; a
-- perf-held stand-down refuses inside feature() above.

--- The one line a verb answers before the task that builds its feature lands. `owner` is the module
--- the verb hands its words to once it exists: `NS[owner].OnVerb(rest)`.
local function delegate(owner)
    return function(rest)
        local m = NS[owner]
        if m and m.OnVerb then return m.OnVerb(rest) end
        out(L["That part of Combat Trail is not built yet."])
    end
end
doResults, doHud, doLane = delegate("Results"), delegate("Hud"), delegate("Lanes")
doIgnore, doPurge, doProbe = delegate("LaneIgnore"), delegate("Retention"), delegate("Probe")

--- `lock` / `unlock`: the Locked row (slash-commands-§8).
function doLock(want)
    doSetVerb("general.locked", want, NS.ApplyLocked)
end

--- `test`: test mode on or off, through the Master controls' row.
function doTest()
    NS.ToggleTestMode()
end

--- `sim [line]`: the sim's own grammar (core/CombatTrail.lua NS.RunSimVerb).
function doSim(rest)
    NS.RunSimVerb(rest)
end

function Sl:OnSlash(msg) return cli:OnSlash(msg) end
function Sl:PrintHelp() return cli:PrintHelp() end
function Sl:LandingRows() return cli:LandingRows() end
function Sl:DisabledLine() return cli:DisabledLine() end

--- Both chat commands on the one dispatcher, through AceConsole (never raw SLASH_*). AceConsole takes
--- the word without its slash, which is how core/Namespace.lua keeps NS.SLASH and NS.SLASH_LONG.
function Sl:Register()
    NS.addon:RegisterChatCommand(NS.SLASH, function(msg) Sl:OnSlash(msg) end)
    NS.addon:RegisterChatCommand(NS.SLASH_LONG, function(msg) Sl:OnSlash(msg) end)
end
