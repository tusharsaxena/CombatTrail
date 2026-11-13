local addonName, NS = ...
-- core/ToastSetup.lua — NS.NewToast from LibKa0s-Toast-1.0: the alert-toast shell under the new-best
-- toast (modules/BestToast.lua, Race mode plan Task C2), ported from DPS Race @f8078c7. The shell owns
-- the queue, the lifetime (the countdown, its hover pause, the close mark and the right-click), the T5
-- alert tier, the drag and the sound; the addon owns what the toast says, when it shows, and the
-- settings it reads.
--
-- A seam, nothing else (library-stack-§7): one file leases the major, and every descriptor it builds
-- carries this addon's folder as its skin owner (`d.owner`).
--
-- DEGRADED (the library absent): NS.NewToast answers NS.ToastStub, the instance's surface with every
-- member a no-op answering what an empty toast answers, so no toast ever shows and nothing raises.
-- tests/test_toast.lua holds the stub to a live instance.

local Toast = LibStub and LibStub("LibKa0s-Toast-1.0", true)

--- The key the shell's Preview shows under (its own constant; the stub's stand-in when absent).
NS.TOAST_PREVIEW = Toast and Toast.PREVIEW or "preview"

-- The instance's surface, each member a no-op (the library's docs/api/Toast, the degradation stub).
NS.ToastStub = {
    Show = function() return false end, Dismiss = function() end, Remove = function() return 0 end,
    Clear = function() end, Hold = function() end, Release = function() end,
    Preview = function() end, Pause = function() end, Resume = function() end,
    Attach = function() end, Refresh = function() end, ResetPosition = function() end,
    SetStack = function() return 1, "DOWN" end, Visible = function() return {} end,
    FrameFor = function() return nil end,
    Current = function() return nil end, Frame = function() return nil end,
    Stats = function() return { built = false, shown = false, waiting = 0, held = false,
        paused = false, sticky = false, keys = {}, visible = 0, visibleKeys = {},
        stack = 1, grow = "DOWN" } end,
}

--- A toast for descriptor `d` (the library's Toast:New; `d.owner` defaults to this addon), or the
--- stub when the library is absent.
--- @param d table  the descriptor: d.build is required
--- @return table instance
function NS.NewToast(d)
    if not Toast then return NS.ToastStub end
    d.owner = d.owner or addonName
    return Toast:New(d)
end
