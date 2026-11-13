local addonName, NS = ...
-- core/CalloutSetup.lua — NS.NewCallout from LibKa0s-Callout-1.0: the big center-screen call-out
-- under the race's last seconds and its buzzer (modules/Countdown.lua, callout plan row C2). The
-- instance owns the frame, its look, its animation, its saved place and its voice; the addon owns
-- when it speaks and what it says.
--
-- A seam, nothing else (library-stack-§7): one file leases the major, and every descriptor it builds
-- carries this addon's folder (where the voice packs and the bundled faces are found), its skin owner
-- (the "Skin font" face and the drag strip's colors), the voice packs this copy ships and the debug
-- sink.
--
-- THE PACKS are the root CLAUDE.md's `LibKa0s sounds:` line, the folders the re-vendor kept under
-- libs/LibKa0s/media/sounds/ (tests/test_vendor_sync.lua holds the copy to it). Passing them as
-- `d.packs` means the instance offers only those and never plays any other.
--
-- DEGRADED (the library absent): NS.NewCallout answers NS.CalloutStub, the instance's surface with every
-- member a no-op answering what an idle call-out answers (the library's docs/api/Callout, The
-- degradation stub), so nothing shows, nothing speaks and nothing raises. It is defined here, in the
-- file that loads before the one calling New (modules/Countdown.lua), as the library's stub rule
-- asks. tests/test_countdown.lua holds the stub to a live instance.
--
-- Nothing here reads a meter value: a call-out says a number of seconds or a stock word.

local Callout = LibStub and LibStub("LibKa0s-Callout-1.0", true)

--- The voice packs this copy ships: the CLAUDE.md `LibKa0s sounds:` line.
NS.CALLOUT_PACKS = { "callout/female-kathleen", "callout/male-joe" }

-- The instance's surface, each member a no-op (the library's docs/api/Callout, the degradation stub).
NS.CalloutStub = {
    Countdown = function() return false end, Cancel = function() return false end,
    Running = function() return false, nil end, Show = function() return false end,
    Hide = function() end, Suspend = function() end, Resume = function() end,
    Suspended = function() return false end, Get = function() return nil end,
    Set = function() return false end, GetColor = function() return 1, 1, 1 end,
    SetColor = function() return false end, Apply = function() end, SetLocked = function() end,
    Locked = function() return true end, ResetPosition = function() end,
    Voices = function() return {} end, TtsVoices = function() return {} end,
    Frame = function() return nil end, Look = function() return {} end,
    Preview = function() return false end, TestCountdown = function() return false end,
    SettingsRows = function() return {} end, SettingsTabs = function() return {} end,
    BuildSettings = function() return nil end,
    Stats = function() return { built = false, shown = false, running = false, awake = false,
        suspended = false, locked = true, logged = 0 } end,
}

--- The library's settings defaults, copied whole (defaults/Profile.lua seeds `profile.callout` with
--- it), or an empty table without the library.
--- @return table
function NS.CalloutDefaults()
    local function copy(v)
        if type(v) ~= "table" then return v end
        local t = {}
        for k, x in pairs(v) do t[k] = copy(x) end
        return t
    end
    return copy(Callout and Callout.DEFAULTS or {})
end

--- A call-out for descriptor `d` (the library's Callout:New; `d.addon`, `d.skin`, `d.packs` and
--- `d.debug` default to this addon's), or the stub when the library is absent.
--- @param d table  the descriptor: d.db is required
--- @return table instance
function NS.NewCallout(d)
    if not Callout then return NS.CalloutStub end
    d.addon = d.addon or addonName
    d.skin = d.skin or addonName
    d.packs = d.packs or NS.CALLOUT_PACKS
    d.debug = d.debug or function(_, msg) if NS.Debug then NS.Debug("Callout", "%s", tostring(msg)) end end
    return Callout:New(d)
end
