local addonName, NS = ...
-- modules/Sizing.lua — smooth resizing (standalone-windows, Resizing): the one pattern every
-- resizable window this addon owns is sized by. The Results window is the first (plan Task 4.1); the
-- ability timeline follows (Task 4.3). The DPS HUD has no grip (its width is `hud.width`, its height
-- its body's stack). Ported from DPS Race @045f479 (modules/Sizing.lua) unchanged in behavior.
--
-- WHY. NS.MakeResizable (LibKa0s-Core-1.0) runs a window's onResize on every OnSizeChanged, and while
-- the grip is dragged that is every frame. A window whose relayout is a full redraw (the fight list
-- rebinding every row) then falls behind the cursor.
--
-- THE PATTERN. A window hands Sizing.MakeResizable its bounds and five functions:
--   size(w, h)   on every size change: track the clamped size, which everything else lays out from
--   layout()     cheap: re-anchor and resize what the new size needs; nothing rebound, nothing redrawn
--   redraw()     the full layout
--   done(w, h)   once when the grip is released, after redraw: persist the size (and anything else a
--                finished resize owes)
--   canResize()  optional, the grip's gate
-- While the grip is held a size change runs `layout`, at most once a frame: GetTime() names the frame,
-- and a second change in the same frame waits for one C_Timer.After(0). The release runs `redraw` once,
-- then `done`; so does a hide while the grip is held, which no mouse-up follows. A size change the
-- grip did not start (the stored size at build, Reset position) runs `redraw` at once.
--
-- PLAIN DATA ONLY. Nothing here reads a frame's geometry: the sizes are the ones OnSizeChanged hands
-- the library, and every window lays out from what `size` tracked.

local Sizing = {}
NS.Sizing = Sizing

-- What each window's grip is doing, by frame: { dragging, pending, stamp, w, h } (w, h: the last size
-- OnSizeChanged handed on). Weak: a window is never freed, but a suite's instances are.
local states = setmetatable({}, { __mode = "k" })

-- The frame's name for "this frame": GetTime() answers one value for the whole of a client frame.
local function frameStamp()
    return type(GetTime) == "function" and GetTime() or nil
end

local function cheap(s, opts)
    s.pending = false
    s.stamp = frameStamp()
    opts.layout()
end

-- A size change while the grip is held: the cheap layout now, or once next frame if one ran this frame.
local function whileDragging(s, opts)
    local now = frameStamp()
    if now == nil or s.stamp ~= now then return cheap(s, opts) end
    if s.pending then return end
    if not (C_Timer and C_Timer.After) then return cheap(s, opts) end
    s.pending = true
    C_Timer.After(0, function()
        if s.pending and s.dragging then cheap(s, opts) end
    end)
end

-- The grip's own mouse-down and mouse-up, hooked after the library's: a left press the gate allows
-- starts a drag, any release ends one (the library has already run `released` by then).
local function hookGrip(grip, frame, s, canResize)
    if type(grip) ~= "table" or type(grip.HookScript) ~= "function" then return end
    grip:HookScript("OnMouseDown", function(_, button)
        if button ~= nil and button ~= "LeftButton" then return end
        if canResize and not canResize(frame) then return end
        s.dragging, s.pending, s.stamp = true, false, nil
    end)
    grip:HookScript("OnMouseUp", function() s.dragging, s.pending = false, false end)
end

-- A window hidden while its grip is held (Escape, Alt-Z or a stand-down) never sees the grip's
-- mouse-up. The hide ends the drag instead, as a release would: sizing stopped, the full redraw, and
-- the last size the drag reached handed on to be stored.
local function hookHide(frame, s, opts)
    if type(frame.HookScript) ~= "function" then return end
    frame:HookScript("OnHide", function()
        if not s.dragging then return end
        s.dragging, s.pending = false, false
        if type(frame.StopMovingOrSizing) == "function" then frame:StopMovingOrSizing() end
        opts.redraw()
        if opts.done then opts.done(s.w, s.h) end
    end)
end

--- Make `frame` resizable from the library's grip, laid out cheaply while the grip is dragged and in
--- full once when it is released. Answers the grip (nil with no library, as NS.MakeResizable does).
--- @param frame table
--- @param opts table  { minWidth, minHeight, size(w, h), layout(), redraw(), done(w, h), canResize()? }
--- @return table|nil grip
function Sizing.MakeResizable(frame, opts)
    local s = { dragging = false, pending = false }
    states[frame] = s
    local function changed(w, h)
        s.w, s.h = w, h
        opts.size(w, h)
        if s.dragging then return whileDragging(s, opts) end
        opts.redraw()
    end
    local function released(w, h)
        s.dragging, s.pending = false, false
        opts.redraw()
        if opts.done then opts.done(w, h) end
    end
    -- owner: the grip takes this addon's skin's `icon.grip` tint and follows a skin switch, like the
    -- library's own windows.
    local grip = NS.MakeResizable and NS.MakeResizable(frame, {
        minWidth = opts.minWidth, minHeight = opts.minHeight, canResize = opts.canResize,
        onResize = changed, onResizeStop = released, owner = addonName,
    }) or nil
    hookGrip(grip, frame, s, opts.canResize)
    if grip then hookHide(frame, s, opts) end
    return grip
end

--- Whether `frame`'s grip is being dragged now.
function Sizing.IsSizing(frame)
    local s = states[frame]
    return s ~= nil and s.dragging == true
end
