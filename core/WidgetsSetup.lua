local addonName, NS = ...
-- core/WidgetsSetup.lua — NS.MakeDropdown / NS.OpenMenu / NS.CloseMenu / NS.MakeTestStrip /
-- NS.MakeSimStrip / NS.ShowCopy from LibKa0s-Widgets-1.0: the Results window's filter-bar dropdowns
-- and its row menu, the test-mode and sim strips a window lays over data that is not the player's,
-- and the copy window the fight detail's talent loadout opens (plan milestone 4).
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
-- answers nil; NS.CloseMenu is a no-op, because there is no menu that could be open; NS.ShowCopy
-- answers false and its caller prints the text instead.

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

--- The strip's height, for a window laying its content out below it (the library publishes it).
NS.TEST_STRIP_HEIGHT = (W and W.TEST_STRIP and W.TEST_STRIP.HEIGHT) or 18

--- The test-mode strip (the library's W.TestStrip, born hidden and unanchored), or nil when the
--- library is absent. The caller anchors it and shows it. Its mark is the catalog's info icon.
--- @param parent table the frame to parent it to
--- @param text string the localized line it says
--- @return table|nil
function NS.MakeTestStrip(parent, text)
    if not W then return nil end
    -- onEnd (LibKa0s Widgets minor 21): the strip's right-click menu ends the preview, the test
    -- mode and the sim alike (Preview.Stop stops the sim's script and its stepper too).
    local function endMode() if NS.Preview and NS.Preview.IsActive() then NS.Preview.Stop() end end
    return W.TestStrip(parent, { text = text, icon = NS.Icon("info"), owner = addonName, onEnd = endMode })
end

--- The simulation strip: the same widget in its sim flavor (kind = "sim", the library's cyan wash), born
--- hidden and unanchored, or nil when the library is absent. A running sim shows this one and never the
--- test strip. Its right-click menu ends the preview, the sim's script and stepper with it.
--- @param parent table the frame to parent it to
--- @param text string the localized line it says
--- @return table|nil
function NS.MakeSimStrip(parent, text)
    if not W then return nil end
    local function endMode() if NS.Preview and NS.Preview.IsActive() then NS.Preview.Stop() end end
    return W.TestStrip(parent, { kind = "sim", text = text, icon = NS.Icon("info"), owner = addonName, onEnd = endMode })
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
