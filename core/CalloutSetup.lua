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
-- libs/LibKa0s/media/sounds/ (tests/test_vendor_sync.lua holds the copy to the line, and
-- tests/test_countdown.lua holds NS.CALLOUT_PACKS to it, in order). Passing them as
-- `d.packs` means the instance offers only those and never plays any other.
--
-- DEGRADED (the library absent): NS.NewCallout answers NS.CalloutStub, the instance's surface with every
-- member a no-op answering what an idle call-out answers (the library's docs/api/Callout, The
-- degradation stub), so nothing shows, nothing speaks and nothing raises. It is defined here, in the
-- file that loads before the one calling New (modules/Countdown.lua), as the library's stub rule
-- asks. tests/test_countdown.lua holds the stub to a live instance.
--
-- THE DRAG STRIP'S MARKS (LibKa0s#100, Callout minor 5, SD-CT-100): while the call-out is unlocked
-- (its settings tab's *Unlock to move*), its drag strip reads `?` · settings · close
-- (standalone-windows, *The drag strip's marks*). The close (`onClose`, NS.CalloutClose) locks the
-- call-out, so its sample and strip go, and turns the race's center countdown off
-- (`race.centerCountdown`, through the seam), and a chat line says where to turn it back on; the
-- call-out's other settings are kept. The settings mark (`onSettings`, NS.CalloutSettings) opens the
-- Race mode page on its Callout tab. A descriptor that names its own keeps it.
--
-- Nothing here reads a meter value: a call-out says a number of seconds or a stock word.

local Callout = LibStub and LibStub("LibKa0s-Callout-1.0", true)

--- The voice packs this copy ships: the CLAUDE.md `LibKa0s sounds:` line.
NS.CALLOUT_PACKS = {
    "callout/male-arena-john", "callout/female-kathleen", "callout/female-kristin", "callout/female-cori",
    "callout/female-bella", "callout/male-joe", "callout/male-john", "callout/male-norman",
}

-- The instance's surface, each member a no-op (the library's docs/api/Callout, the degradation stub).
NS.CalloutStub = {
    Countdown = function() return false end, Cancel = function() return false end,
    Running = function() return false, nil end, Show = function() return false end,
    Hide = function() end, Suspend = function() end, Resume = function() end,
    Suspended = function() return false end, Get = function() return nil end,
    Set = function() return false end, GetColor = function() return 1, 1, 1 end,
    GetGlowColor = function() return 1, 1, 1 end,
    SetColor = function() return false end, Apply = function() end, SetLocked = function() end,
    Locked = function() return true end, ResetPosition = function() end,
    Voices = function() return {} end, TtsVoices = function() return {} end,
    Frame = function() return nil end, Look = function() return {} end,
    Preview = function() return false end, TestCountdown = function() return false end,
    SettingsRows = function() return {} end, SchemaRows = function() return {}, {} end,
    SettingsTabs = function() return {} end, SettingsTab = function() return nil end,
    BuildSettings = function() return nil end,
    Stats = function() return { built = false, shown = false, running = false, awake = false,
        suspended = false, locked = true, logged = 0 } end,
}

-- The Race mode page and its call-out tab (settings/Race.lua: the page key, and the tab's group key).
local RACE_PAGE, CALLOUT_TAB = "race", "callout"

--- The drag strip's close: the call-out locked (its sample and strip go) and the race's center
--- countdown turned off through the seam, with one chat line saying how to turn it back on.
function NS.CalloutClose()
    if NS.Callout and NS.Callout.SetLocked then NS.Callout:SetLocked(true) end
    if NS.GetSetting and NS.GetSetting("race.centerCountdown") == false then return end
    if NS.SetByPath and NS.SetByPath("race.centerCountdown", false) and NS.Print then
        local L = NS.L or {}
        NS.Print(L["Center-screen countdown off. Turn it back on in Race mode > Race > Countdown."])
    end
end

--- The drag strip's settings mark: the Race mode page, on its Callout tab.
function NS.CalloutSettings()
    local H = NS.Helpers
    if not (H and type(H.OpenOptionsPanel) == "function") then return NS.OpenSettings and NS.OpenSettings() end
    H.OpenOptionsPanel(RACE_PAGE)
    if type(H.SelectTab) == "function" then H.SelectTab(RACE_PAGE, CALLOUT_TAB) end
end

--- A call-out for descriptor `d` (the library's Callout:New; `d.addon`, `d.skin`, `d.packs`,
--- `d.debug`, `d.onClose` and `d.onSettings` default to this addon's), or the stub when the library
--- is absent.
--- @param d table  the descriptor: d.db is required
--- @return table instance
function NS.NewCallout(d)
    if not Callout then return NS.CalloutStub end
    d.addon = d.addon or addonName
    d.skin = d.skin or addonName
    d.packs = d.packs or NS.CALLOUT_PACKS
    d.debug = d.debug or function(_, msg) if NS.Debug then NS.Debug("Callout", "%s", tostring(msg)) end end
    d.onClose = d.onClose or function() NS.CalloutClose() end
    d.onSettings = d.onSettings or function() NS.CalloutSettings() end
    return Callout:New(d)
end
