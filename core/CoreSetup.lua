local addonName, NS = ...
-- core/CoreSetup.lua — NS.Print, the secret-safe stringifier, the SafeRegister* family and the window
-- chrome, from LibKa0s-Core-1.0; every tagged chat line leaves through here.

NS.Util = NS.Util or {}

-- The HOST owns the rejected-event list (events-frames-taint-§1): the library keeps no state, so the
-- addon surfaces this list in its diagnostics report.
NS.rejectedEvents = NS.rejectedEvents or {}

-- The one sentence every degradation stub opens with, so a library-absent load says the same thing
-- wherever it is noticed.
NS.LIBKA0S_MISSING = "The LibKa0s library is missing from this installation of Ka0s Combat Trail "
    .. "(expected in libs/LibKa0s)"

local lib = LibStub and LibStub("LibKa0s-Core-1.0", true)

if not lib then
    -- Degrade, never error. A nil printer takes every settings file with it, and a silent one makes
    -- /kct answer nothing, so keep a short fallback and say "missing" ONCE, on the first line printed.
    local function probeConcat(v) return table.concat({ v }) end
    function NS.IsConcatSafe(v) return (pcall(probeConcat, v)) end
    function NS.SafeToString(v)
        if v == nil or type(v) == "boolean" then return tostring(v) end
        if NS.IsConcatSafe(v) then return tostring(v) end
        return "<secret>"
    end

    local announced = false
    local function fallbackPrint(...)
        local chat = DEFAULT_CHAT_FRAME
        if not chat then return end
        if not announced then
            announced = true
            chat:AddMessage(NS.PREFIX .. " " .. NS.LIBKA0S_MISSING .. "; running on reduced fallbacks.")
        end
        local parts = { NS.PREFIX }
        for i = 1, select("#", ...) do parts[i + 1] = NS.SafeToString((select(i, ...))) end
        chat:AddMessage(table.concat(parts, " "))
    end
    NS.Print = fallbackPrint
    NS.Util.print = fallbackPrint

    -- The chrome degrades to NOTHING rather than to a hand-copied backdrop (standalone-windows):
    -- SKIN is an empty table so a window may index it, and MakeCloseButton answers nil exactly as
    -- Core's own does where CreateFrame is unavailable.
    NS.SKIN            = {}
    NS.ApplySkin       = function() end
    NS.MakeCloseButton = function() return nil end
    -- No grip: the window keeps its stored size (Core's own answer where it cannot build one).
    NS.MakeResizable   = function() return nil end
    NS.RaiseStaticPopups = function() end

    -- The SafeRegister* family as ONE-RUNG pcall bodies (events-frames-taint-§1).
    local function reject(rejected, event)
        if type(rejected) ~= "table" then return end
        for i = 1, #rejected do if rejected[i] == event then return end end
        rejected[#rejected + 1] = event
    end
    NS.SafeRegisterEvent = function(target, event, handler, rejected)
        local ok = pcall(target.RegisterEvent, target, event, handler)
        if not ok then reject(rejected, event) end
        return ok
    end
    NS.SafeRegisterUnitEvent = function(frame, event, rejected, unit1, unit2)
        local ok = pcall(frame.RegisterUnitEvent, frame, event, unit1, unit2)
        if not ok then reject(rejected, event) end
        return ok
    end
    NS.SafeRegisterEvents = function(target, events, handler, rejected)
        local n = 0
        for _, event in ipairs(events) do
            if NS.SafeRegisterEvent(target, event, handler, rejected) then n = n + 1 end
        end
        return n
    end
    return
end

NS.IsConcatSafe, NS.SafeToString = lib.IsConcatSafe, lib.SafeToString

-- Every event registration in the addon goes through these (events-frames-taint-§1).
NS.SafeRegisterEvent     = lib.SafeRegisterEvent
NS.SafeRegisterUnitEvent = lib.SafeRegisterUnitEvent
NS.SafeRegisterEvents    = lib.SafeRegisterEvents

-- The shared window edge, published flat so a re-skin lands everywhere at once (standalone-windows).
-- WRAPPED, TO SAY WHO IS ASKING (skinning-§1): with no skin table, Core paints the frame through the
-- skin owner core/SkinSetup.lua registers (Core minor 13: the owner's `S.Shell`), so the window wears
-- this addon's skin and follows a switch. A skin table of the caller's own is drawn as given.
NS.SKIN      = lib.SKIN
NS.ApplySkin = function(frame, skin)
    return lib.ApplySkin(frame, skin, addonName)
end
-- The bottom-right sizing grip the HUD is resized with (standalone-windows).
NS.MakeResizable = lib.MakeResizable
-- A toplevel DIALOG window re-raises a shown StaticPopup when it shows, so a confirmation shown first
-- is never buried under it (frame-layering-§4; the ability timeline).
NS.RaiseStaticPopups = lib.RaiseStaticPopups or function() end

-- WRAPPED, TO SAY WHO IS ASKING -- a MUST (standalone-windows, anti-patterns #64/#65). Core draws the
-- catalog's `close` mark only when told which addon FOLDER to build the path from. Every close
-- control in this addon is built through here, so this grep returns this definition and calls to
-- NS.MakeCloseButton and nothing else:
--   grep -rn 'MakeCloseButton(' --include='*.lua' . | grep -v '/libs/'
NS.MakeCloseButton = function(parent, onClick)
    return lib.MakeCloseButton(parent, onClick, addonName)
end

-- The prefix goes in as a FUNCTION so a later change to NS.PREFIX is not frozen in at load.
local printer = lib:New({ prefix = function() return NS.PREFIX end })

-- NS.Print and NS.Util.print MUST be the SAME function object: AceConsole's embed stamps its own
-- :Print over NS.Print, and core/CombatTrail.lua reclaims it from NS.Util.print (architecture-§2).
NS.Print = printer.Print
NS.Util.print = NS.Print
