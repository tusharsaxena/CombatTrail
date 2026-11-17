local addonName, NS = ...
-- core/WidgetsSetup.lua — NS.MakeDropdown / NS.OpenMenu / NS.CloseMenu / NS.MakeTestStrip /
-- NS.MakeSimStrip / NS.MakeFooter / NS.ShowCopy from LibKa0s-Widgets-1.0: the Results window's
-- filter-bar dropdowns and its row menu, the test-mode and sim strips the library docks under a
-- window's title bar over data that is not the player's, the windows' footers, and the copy window
-- the fight detail's talent loadout opens (plan milestone 4).
--
-- A seam, nothing else (library-stack-§7): one file leases the major, so the art the dropdown draws
-- is resolved once, here. The library is vendored and cannot know which folder it was copied into,
-- so the chevron and the tick arrive as resolved paths from the addon's own media seam
-- (core/MediaSetup.lua); NS.Icon answering nil is a real answer, and the library falls back to the
-- Blizzard chevron and tick. No option this addon builds carries a glyph, so no glyph face is passed.
--
-- THE POPUP IS A PROCESS-WIDE SINGLETON parented to UIParent, so hiding a window does not reach it.
-- Every non-click close path of a window with a dropdown calls NS.CloseMenu(): the Results window's
-- OnHide (also the Escape path through UISpecialFrames) and its tab switch.
--
-- DEGRADED (the library absent): NS.MakeDropdown answers nil and the filter bar draws no dropdown at
-- all rather than a dead control that opens no menu; the filters stay at "all". NS.MakeTestStrip
-- answers nil; NS.MakeFooter answers a bare frame with the same lines and no hairline; NS.CloseMenu
-- is a no-op, because there is no menu that could be open; NS.ShowCopy answers false and its caller
-- prints the text instead.

local W = LibStub and LibStub("LibKa0s-Widgets-1.0", true)

--- One flat-skin dropdown, or nil when the library is absent. Nil is a real answer: the caller
--- draws no control.
--- @param parent table the frame to parent it to
--- @param width number the collapsed button's width
--- @return table|nil
function NS.MakeDropdown(parent, width)
    if not W then return nil end
    return W.Dropdown(parent, width, {
        chevron = NS.Icon("chevron-down"),
        check   = NS.Icon("confirm"),
        owner   = addonName,
    })
end

-- ── the context menus (cause A2) ─────────────────────────────────────────────────────────────────
-- A row's right-click wears the skin through W.ContextMenu (Widgets minor 21), the shared Ka0s menu
-- opened at the cursor. A `fill(root)` is written against MenuUtil's own description (CreateTitle,
-- CreateButton, and on a button SetEnabled and a nested CreateButton), recorded here, then turned
-- into rows once and handed to one W.ContextMenu call: a button with a nested level is a `submenu`
-- row (Widgets minor 23, cascading menus), so its rows open beside it, any depth, while the parent
-- stays drawn, and the library draws the client's submenu arrow on it.
-- Without the library the same `fill` goes to the client's menu.

--- A level of a description: the recorder a `fill` writes to, and each button's own nested level.
local function newLevel()
    local level = { items = {} }
    function level:CreateTitle(text)
        self.items[#self.items + 1] = { label = text, title = true }
        return {}
    end
    function level:CreateButton(text, onClick)
        local sub = newLevel()
        sub.label, sub.onClick, sub.enabled = text, onClick, true
        function sub.SetEnabled(_, on) sub.enabled = on and true or false end
        self.items[#self.items + 1] = sub
        return sub
    end
    return level
end

local menuRows

--- One W.ContextMenu row: a title, or a button with its click and its disabled state; a button with
--- a nested level is a submenu row whose child rows are that level's (the library opens them).
local function menuRow(item)
    if item.title then return { label = item.label, title = true } end
    local row = { label = item.label, disabled = item.enabled == false or nil }
    if #item.items > 0 then
        row.submenu = menuRows(item)
    else
        row.onClick = item.onClick
    end
    return row
end

--- A recorded level's rows, its nested levels as `submenu` rows.
menuRows = function(level)
    local rows = {}
    for i, item in ipairs(level.items) do rows[i] = menuRow(item) end
    return rows
end

--- True when a context menu can open: the Ka0s menu, or the client's without the library.
function NS.CanOpenMenu()
    if W then return true end
    return MenuUtil ~= nil and MenuUtil.CreateContextMenu ~= nil
end

--- A context menu at the cursor: `fill(root)` adds its rows as it would to a MenuUtil description.
--- @param owner table  the client menu's owner region
--- @param fill function
function NS.OpenMenu(owner, fill)
    if not W then
        MenuUtil.CreateContextMenu(owner, function(_, root) fill(root) end)
        return
    end
    local level = newLevel()
    fill(level)
    W.ContextMenu(owner, menuRows(level), { owner = addonName, cursor = true })
end

-- THE DOCK (LibKa0s-Widgets-1.0 minor 27; preview-mode, *Where the strip sits*). `dock` is
-- { titleBar, window, onOffset }: the library docks the strip directly under that title bar, full
-- width (dock = "title"), on the window's top edge while the title bar is hidden, and places it again
-- on every show, hide and resize of either. The host never anchors it; everything below the title bar
-- moves down by `strip:BodyOffset()` (the strip's height while it shows, 0 while hidden).
local function docked(opts, dock)
    if type(dock) == "table" and dock.titleBar then
        opts.dock, opts.titleBar, opts.window, opts.onOffset = "title", dock.titleBar, dock.window, dock.onOffset
    end
    return opts
end

-- Its right-click menu ends the preview (LibKa0s Widgets minor 21, onEnd): the test mode and the sim
-- alike (Preview.Stop stops the sim's script and its stepper too).
local function endMode() if NS.Preview and NS.Preview.IsActive() then NS.Preview.Stop() end end

--- The test-mode strip (the library's W.TestStrip, born hidden, docked by `dock`), or nil when the
--- library is absent. The caller shows it. Its mark is the catalog's info icon.
--- @param parent table the frame to parent it to
--- @param text string the localized line it says
--- @param dock table|nil { titleBar, window, onOffset } (THE DOCK)
--- @return table|nil
function NS.MakeTestStrip(parent, text, dock)
    if not W then return nil end
    return W.TestStrip(parent, docked({ text = text, icon = NS.Icon("info"), owner = addonName, onEnd = endMode }, dock))
end

--- The simulation strip: the same widget in its sim flavor (kind = "sim", the library's cyan wash), born
--- hidden and docked by `dock`, or nil when the library is absent. A running sim shows this one and
--- never the test strip.
--- @param parent table the frame to parent it to
--- @param text string the localized line it says
--- @param dock table|nil { titleBar, window, onOffset } (THE DOCK)
--- @return table|nil
function NS.MakeSimStrip(parent, text, dock)
    if not W then return nil end
    return W.TestStrip(parent, docked({ kind = "sim", text = text, icon = NS.Icon("info"), owner = addonName,
        onEnd = endMode }, dock))
end

-- ── the footer (LibKa0s-Widgets-1.0 minor 27; standalone-windows, *The footer*) ─────────────────

--- A window footer's height, read where the library publishes it (FOOTER.HEIGHT, 24 under every
--- skin); the same figure with no library, so a degraded window lays out the same.
NS.FOOTER_HEIGHT = (W and W.FOOTER and W.FOOTER.HEIGHT) or 24

-- With no library (a degraded install only): a bare frame of the same height across the bottom edge
-- with the same two lines and setters, and no hairline, so the host's writes run unchanged.
local function bareFooter(parent, opts)
    local foot = CreateFrame("Frame", nil, parent)
    foot:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    foot:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    foot:SetHeight(NS.FOOTER_HEIGHT)
    foot.left = foot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    foot.left:SetPoint("LEFT", foot, "LEFT", 8, 0)
    foot.right = foot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    foot.right:SetPoint("RIGHT", foot, "RIGHT", opts.grip and -22 or -8, 0)
    foot.left:SetText(opts.left or "")
    foot.SetLeft = function(self, t) self.left:SetText(t or "") end
    foot.SetRight = function(self, t) self.right:SetText(t or "") end
    foot.SetGrip = function(self, on) self.__grip = on and true or nil end
    foot.__grip = opts.grip and true or nil
    return foot
end

--- A window's footer: the library's W.Footer (no fill, a hairline in the skin's `divider` along its
--- top, the left and right lines in `text.muted`, FOOTER.HEIGHT tall across `parent`'s bottom edge,
--- born shown, painted for this addon's skin owner), or the bare stand-in with no library. The host
--- writes its lines (foot.left / foot.right, or SetLeft / SetRight) and shows or hides it whole.
--- `opts.grip` true keeps the right line clear of the window's resize grip (foot:SetGrip moves it).
--- @param parent table the window
--- @param opts table|nil { left = string, grip = boolean }
--- @return table the footer
function NS.MakeFooter(parent, opts)
    local o = {}
    for k, v in pairs(opts or {}) do o[k] = v end
    if not (W and type(W.Footer) == "function") then return bareFooter(parent, o) end
    o.owner = addonName
    return W.Footer(parent, o)
end

-- The one copy window, its frame built on the first ShowCopy (the library's lazy handle), over the
-- window that asked for it.
local copyWindow, copyAnchor

--- Show `text` selected in the copy window (Ctrl+C copies it, Escape closes it), titled `title`, over
--- `anchor` when it is shown.
--- @param text string
--- @param title string
--- @param anchor table|nil  the window to center it over
--- @return boolean shown  false on a degraded install
function NS.ShowCopy(text, title, anchor)
    if not (W and W.CopyWindow) then return false end
    copyAnchor = anchor
    copyWindow = copyWindow or W.CopyWindow({
        addonName = addonName, name = addonName .. "CopyWindow", width = 520, height = 150, title = title,
        anchorTo = function() return copyAnchor end,
    })
    if not copyWindow then return false end
    local f = copyWindow:Show(text)
    if f and f.title then f.title:SetText(title) end
    return true
end

--- Close the shared popup menu behind every dropdown in the process, if one is open. Safe when none
--- ever opened, and a no-op on a degraded install.
function NS.CloseMenu()
    if W then W.CloseMenu() end
end
