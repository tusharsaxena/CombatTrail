local addonName, NS = ...
-- modules/Hud_Appearance.lua — the DPS HUD's configured look (spec §6 and §8, plan Task 3.2): the
-- clock, the live figures and their boxes, the damage chart, the spell rows and the pace bar's fills,
-- and the window itself, every key under `hud.*` that the mockup's DPS HUD tabs name (Layout, Clock
-- and figures, Damage chart, Spell rows, Window). This file turns a stored block into what a widget
-- setter takes; the parts (modules/Hud_States.lua, Hud_Chart.lua, Hud_Breakdown.lua, Hud.lua) call
-- it. Adapted from DPS Race @045f479 (modules/Hud_Appearance.lua), trimmed to Combat Trail's blocks.
--
-- THE BLOCKS are the composer's shapes (LibKa0s-Options-1.0 OptionsCompose, options-ui-§16 and
-- §17), so the DPS HUD page (plan Task 3.3) builds its rows from FontGroup, BarGroup and ColorPair
-- over these very leaves: a font block is `font`, `fontSize`, `fontColor`, `useClassColorFont`,
-- `fontFlags`, `fontShadow` and `fontFromSkin`, plus the two text companions skinning-§6 asks of every
-- HUD string, `fontColorFromSkin` and `fontShadowFromSkin` (on: the skin's S.HudTextColor and
-- S.HudShadow draw, a class color still first); a bar block `barTexture`, `barAlpha`, `barColor`,
-- `useClassColorBar` and `barTextureFromSkin`; a swatch `<key>` with its `useClassColor<Key>`.
--   hud.clock    the fight clock's font block (the mono role: its flags never follow the outline)
--   hud.figures  the Damage and DPS figures' font block, the over card's DPS color (`overColor`),
--                and the boxes' background and border (`boxBg`, `boxBorder`, each with a
--                `<key>FromSkin` companion: on, the skin's Card draws it)
--   hud.chart    the plot's height and its most columns, the columns' bar block, the
--                pace-line color, the cooldown icons and their threshold, the zero line
--   hud.spells   the rows shown (0: every one, the wheel scrolls), the row height, the icons, the
--                pet's paw, the player rows' bar block, the pet rows' color, the rows' font block
--   hud.window   the title bar and its title, the background and border (each with its
--                `<key>FromSkin`), the footer, the strata and the opacity
-- The pace bar draws in the spell rows' look: the player's fill in their bar block, the pet's in
-- `hud.spells.petColor` (spec §6: pet spells in green).
--
-- MEDIA BY NAME, through LibSharedMedia at call time; a name it does not know falls back to the
-- shipped default's, and then to the client's own face or a flat texture, never to nothing. A
-- `<key>FromSkin` companion on draws the skin's token through S.Resolve (`hud.font` for a face,
-- `bar.texture` for a bar), leaving the stored pick for when it goes off.
--
-- RESTYLING IS STAMPED. Changed() bumps Appearance.stamp; a part compares its own stamp and restyles
-- once, not on every 4 Hz redraw. A skin switch reaches every block through Style.OnLooks. Nothing
-- here reads a meter value or a frame's geometry.

local Appearance = {}
NS.HudAppearance = Appearance

local FALLBACK_BAR = "Interface\\Buttons\\WHITE8x8"
local FALLBACK_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local NONE = { r = 1, g = 1, b = 1, a = 1 }

Appearance.stamp = 0

local function setting(path)
    if NS.Hud and NS.Hud.Setting then return NS.Hud.Setting(path) end
    return nil
end

local function lsm()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- The shared media library's own file for `name`, where LSM cannot answer (no LSM loaded yet).
local OWN = { font = "Font", statusbar = "Texture" }

-- The path LSM holds for `name` of media `kind`, else the shared media library's, else nil.
local function fetch(kind, name)
    if type(name) ~= "string" or name == "" then return nil end
    local media = lsm()
    if media then
        local ok, path = pcall(media.Fetch, media, kind, name, true)
        if ok and type(path) == "string" then return path end
    end
    local lib = LibStub and LibStub("LibKa0s-Media-1.0", true)
    local fn = lib and lib[OWN[kind]]
    if type(fn) ~= "function" then return nil end
    local ok, path = pcall(fn, addonName, name)
    if ok and type(path) == "string" then return path end
    return nil
end

-- The shipped default under `path` (defaults/Profile.lua, the only place a default is written).
local function shipped(path)
    local node = NS.defaults and NS.defaults.profile
    for part in path:gmatch("[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

--- A swatch through its class-color companion: the stored color, or the player's class color while
--- the companion is on (the swatch's alpha kept either way, options-ui-§17). Every surface here
--- describes the player.
--- @param path string  the swatch's full path ("hud.chart.burstColor")
--- @param companion string  the companion's full path
--- @return number r, number g, number b, number a
function Appearance.Color(path, companion)
    local c = setting(path)
    if type(c) ~= "table" then c = shipped(path) or NONE end
    local r, g, b, a = c.r or 1, c.g or 1, c.b or 1, c.a or 1
    if companion and setting(companion) == true and NS.ClassColor then
        local cr, cg, cb = NS.ClassColor("player")
        if cr ~= nil then return cr, cg, cb, a end
    end
    return r, g, b, a
end

-- "useClassColor" + the key with its first letter raised: the composer's companion name.
local function companionOf(key)
    return "useClassColor" .. key:sub(1, 1):upper() .. key:sub(2)
end

--- The swatch `key` of block `block` ("hud.<block>.<key>") through its companion.
function Appearance.Swatch(block, key)
    local p = "hud." .. block .. "."
    return Appearance.Color(p .. key, p .. companionOf(key))
end

-- The LSM name a media leaf draws: the skin's while its companion is on and the skin answers.
local function mediaKey(p, leaf, token)
    local stored = setting(p .. leaf)
    local S = NS.Skin
    if setting(p .. leaf .. "FromSkin") == true and S and type(S.Resolve) == "function" then
        local ok, v = pcall(S.Resolve, token, nil, true)
        if ok and type(v) == "string" and v ~= "" then return v, stored end
    end
    return stored, stored
end

-- The skin's HUD text color for the block at `p` while its `fontColorFromSkin` is on and no class
-- color comes first (skinning-§6); nil leaves the stored color (a degraded facade answers nil too).
local function skinText(p)
    local S = NS.Skin
    if setting(p .. "fontColorFromSkin") ~= true or setting(p .. "useClassColorFont") == true then return nil end
    if not (S and type(S.HudTextColor) == "function") then return nil end
    return S.HudTextColor()
end

--- One font block, resolved: { path, size, flags, shadow, shadowFromSkin, r, g, b, a }.
--- @param block string  "clock" | "figures" | "spells"
--- @return table
function Appearance.Font(block)
    local p = "hud." .. block .. "."
    local name, stored = mediaKey(p, "font", "hud.font")
    local path = fetch("font", name) or fetch("font", stored) or fetch("font", shipped(p .. "font"))
        or (block == "clock" and NS.Constants.FONT_MONO) or FALLBACK_FONT
    local r, g, b, a = skinText(p)
    if r == nil then r, g, b, a = Appearance.Color(p .. "fontColor", p .. "useClassColorFont") end
    local flags = setting(p .. "fontFlags")
    if type(flags) ~= "string" then flags = "" end
    return { path = path, size = math.max(6, tonumber(setting(p .. "fontSize")) or 12), flags = flags,
             shadow = setting(p .. "fontShadow") == true,
             shadowFromSkin = setting(p .. "fontShadowFromSkin") == true, r = r, g = g, b = b, a = a }
end

local fontOpts = {}   -- refilled per call: S.HudFont keeps nothing of it

--- Draw `fs` in a resolved font block through S.HudFont (the one way a 12.0.7 client draws a HUD
--- string's shadow), then its color; `color` ({ r, g, b, a }) overrides the block's.
--- @param fs table  a FontString
--- @param font table  Appearance.Font's
--- @param color table|nil
function Appearance.ApplyFont(fs, font, color)
    fontOpts.face, fontOpts.size, fontOpts.flags = font.path, font.size, font.flags
    fontOpts.shadow, fontOpts.shadowFromSkin = font.shadow, font.shadowFromSkin == true
    NS.Skin.HudFont(fs, fontOpts)
    local c = color or font
    fs:SetTextColor(c.r, c.g, c.b, c.a)
end

--- A bar block at `hud.<block>.`: { texture, r, g, b, a, fromSkin }, the alpha the block's opacity.
--- @param block string  "chart" | "spells"
--- @return table
function Appearance.Bar(block)
    local p = "hud." .. block .. "."
    local name, stored = mediaKey(p, "barTexture", "bar.texture")
    local r, g, b = Appearance.Color(p .. "barColor", p .. "useClassColorBar")
    local alpha = tonumber(setting(p .. "barAlpha")) or 1
    return { texture = fetch("statusbar", name) or fetch("statusbar", stored) or FALLBACK_BAR,
             r = r, g = g, b = b, a = alpha, fromSkin = setting(p .. "barTextureFromSkin") == true }
end

--- Paint a StatusBar in a bar look, `color` ({ r, g, b, a }) replacing its fill color.
--- @param bar table  a StatusBar
--- @param look table  Appearance.Bar's
--- @param color table|nil
function Appearance.PaintBar(bar, look, color)
    bar:SetStatusBarTexture(look.texture)
    local c = color or look
    bar:SetStatusBarColor(c.r, c.g, c.b, c.a)
    if NS.Skin.BarGloss then NS.Skin.BarGloss(bar, look.fromSkin) end
end

--- The pet's rows and fills: the spell rows' bar look in `hud.spells.petColor`.
--- @return table { r, g, b, a }
function Appearance.PetColor()
    local r, g, b, a = Appearance.Swatch("spells", "petColor")
    return { r = r, g = g, b = b, a = a }
end

--- A configured number, held to [lo, hi].
function Appearance.Number(path, lo, hi)
    local v = tonumber(setting(path)) or tonumber(shipped(path)) or lo
    return math.max(lo, math.min(hi, v))
end

--- A configured switch (on unless stored false).
function Appearance.On(path)
    return setting(path) ~= false
end

-- A backdrop frame's color and edge from swatches at `p .. bg` / `p .. border`, each drawn while its
-- `<key>FromSkin` companion is off (on, the skin's own paint stands).
local function paintBackdrop(f, p, bg, border)
    if setting(p .. bg .. "FromSkin") ~= true and f.SetBackdropColor then
        f:SetBackdropColor(Appearance.Color(p .. bg, p .. companionOf(bg)))
    end
    if setting(p .. border .. "FromSkin") ~= true and f.SetBackdropBorderColor then
        f:SetBackdropBorderColor(Appearance.Color(p .. border, p .. companionOf(border)))
    end
end

--- A figure box's background and border (`hud.figures.boxBg`, `boxBorder`).
--- @param f table  a box frame (a BackdropTemplate frame the skin's Card painted)
function Appearance.ApplyBox(f)
    paintBackdrop(f, "hud.figures.", "boxBg", "boxBorder")
end

--- The window's own look: its background and border, its strata and its opacity.
--- @param f table  the HUD's frame
function Appearance.ApplyWindow(f)
    paintBackdrop(f, "hud.window.", "bg", "border")
    local strata = setting("hud.window.strata")
    if type(strata) ~= "string" or strata == "" then strata = NS.Constants.LAYERS.STRATA.HUD end
    f:SetFrameStrata(strata)
    f:SetAlpha(Appearance.Number("hud.window.alpha", 0.1, 1))
end

--- A HUD look changed: every part restyles on its next draw, and the HUD redraws now.
function Appearance.Changed()
    Appearance.stamp = Appearance.stamp + 1
    if NS.Hud and NS.Hud.Refresh then NS.Hud.Refresh() end
end

-- A skin switch: the skin's own tokens (a FromSkin companion, a Card's paint) changed under the
-- blocks, so each part restyles over them, and the HUD redraws now (an over card has no tick).
NS.Style.OnLooks(function() Appearance.Changed() end)
