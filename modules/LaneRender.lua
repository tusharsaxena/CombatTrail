local _, NS = ...
-- modules/LaneRender.lua — the lanes' frames (spec §4): one frame per lane, its background, border,
-- GCD ticks, "now" line and label, and the pooled cast icons that scroll across it. What a lane shows
-- arrives as LANE_PUSH(laneKey, item) from modules/LaneCasts.lua; where each icon sits is
-- modules/LaneLayout.lua's pure math. Nothing here listens to a game event.
--
-- THE ICONS come from one NS.Pool per lane and are kept newest first. OnUpdate is set on the lane
-- only while it holds an icon and cleared the frame the last one expires, so an idle lane costs
-- nothing (spec §2 anti-goals). An expired icon goes back to its pool's free list one at a time
-- (releaseOne below: LibKa0s-Pool-1.0 has no per-object release, so this writes the pool's own plain
-- { free, active } shape, which the library documents as its contract). A lane holds MAX_ICONS at
-- most, whatever arrives.
--
-- LAYERING (spec §4, frame-layering; LOAD-BEARING, the regression CastTrail's `level % 200` made):
--   * the lane's strata and level are modules/LaneAnchor.lua's: its configured strata (default
--     LAYERS.STRATA.LANE, "LOW"; "HOST" takes its host's), at its parent's (or host's) level +
--     LEVEL.LANE + levelOffset;
--   * its icons sit in the bounded band lane level + 1 .. lane level + LEVEL.ICON_BAND, re-ordered on
--     every push so the newest is on top, never a counter that climbs;
--   * an icon's border, glow, ✕ and texts are regions of the icon, so they take no level at all.
-- Every SetFrameLevel here is a parent's level plus a LAYERS offset; none is an absolute number.
--
-- SECRETS (spec §3). An item's texture may be secret: it only ever goes to SetTexture. Its spellID is
-- plain or nil (LaneCasts converted it), so the glow, the name, the tooltip and the stack compare only
-- plain IDs. A base cooldown or a haste read in combat may come back secret: it is read through
-- NS.Secrets, and a secret is neither used nor cached (the next read out of combat fills it).
--
-- PLACEMENT is modules/LaneAnchor.lua's (free, docked or on a unit frame), and WHETHER A LANE SHOWS
-- is modules/LaneVisibility.lua's: each Apply asks LaneVisibility.Decide and shows or hides the lane
-- (ApplyVisibility). A hidden lane holds no icon and takes no push.
--
-- THE SKIN (skinning-§6, plan Task 5.2). Every lane color a skin describes, and the label's face,
-- flags and shadow, follow the skin through a `<key>FromSkin` companion (on by default): the icon
-- border's style, thickness and color (`icon.borderStyle`, `icon.borderSize`, `icon.border`), the
-- glow (`glow.color`), the background (`bar.bg`), the lane border (S.BarBorder over `bar.borderStyle`
-- and `bar.borderSize`, `bar.border`), and the label (`hud.font`, S.FontFlags for a stored "@skin",
-- S.HudLabelColor, S.HudShadow through S.HudFont). A class color comes first; a companion off, or a
-- skin that states nothing, draws the stored value. The edges are strips, so a skin's border style
-- draws flat (a texture picked on the Lanes page draws only while its companion is off, or under a
-- skin whose bar border is None). The ticks and the now line are thin flat lines and keep their
-- stored colors (skinning-§9's Leave class). A skin switch re-applies every lane (OnLooksChanged).
--
-- Stand-down (core/LifecycleSetup.lua) calls Suspend: every icon released, every lane hidden, no
-- OnUpdate. Resume rebuilds from the CURRENT settings.

local LaneRender = {}
NS.LaneRender = LaneRender

local Pool = NS.Pool
local Secrets = NS.Secrets
local Perf = NS.Perf
local Layout = NS.LaneLayout
local LAYERS = NS.Constants.LAYERS

--- The most icons one lane holds at once; the oldest go first beyond it.
LaneRender.MAX_ICONS = 64

local LANES = { "player", "pet" }
local FRAME_NAMES = { player = "CombatTrailPlayerLane", pet = "CombatTrailPetLane" }
-- The Pet lane's label while there is no pet; the "now" line's width; the glow's reach.
local LABEL_DIM = 0.5
local NOW_WIDTH = 2
local GLOW_SIZE = 2
local NONE = { r = 0, g = 0, b = 0, a = 0 }

local lanes = {}     -- [laneKey] = { key, frame, pool, factory, icons = {newest first}, ticks = {}, ... }
local cdCache = {}   -- [plain spellID] = base cooldown in ms (plain, read out of combat)
local haste          -- the last plain spell haste, in percent

local function cfgOf(laneKey)
    local db = NS.db
    local all = db and db.profile and db.profile.lanes
    return all and all[laneKey]
end

local function enabledNow(laneKey)
    local cfg = cfgOf(laneKey)
    return cfg ~= nil and cfg.enabled ~= false and not NS.IsStoodDown()
end

local function rgba(c)
    if type(c) ~= "table" then c = NONE end
    return c.r, c.g, c.b, c.a
end

-- Each color's Use class color companion (options-ui-§17). The lanes draw the player's own casts, so
-- the class is the player's; an unresolvable class falls through to the swatch, and the swatch's
-- alpha applies under either.
local CLASS_COLOR_OF = {
    borderColor = "borderClassColor", glowColor = "glowClassColor", bgColor = "bgClassColor",
    laneBorderColor = "laneBorderClassColor", tickColor = "tickClassColor",
    nowColor = "nowClassColor", labelColor = "labelClassColor",
}

-- The skin's color for each color a skin describes, read while its `<key>FromSkin` is on.
local SKIN_COLOR_OF = {
    borderColor     = function(S) return S.Color("icon.border") end,
    glowColor       = function(S) return S.GlowColor() end,
    bgColor         = function(S) return S.Color("bar.bg") end,
    laneBorderColor = function(S) return S.Color("bar.border") end,
    labelColor      = function(S) return S.HudLabelColor() end,
}

-- The skin's color for `key`, or nil (companion off, no skin token, or a facade that answers none).
local function skinTint(cfg, key)
    local read = SKIN_COLOR_OF[key]
    local S = NS.Skin
    if not (read and S) or cfg[key .. "FromSkin"] ~= true then return nil end
    local ok, r, g, b, a = pcall(read, S)
    if not ok or type(r) ~= "number" then return nil end
    return r, g, b, a or 1
end

--- A lane color as drawn: the class color while its companion is on (the swatch's alpha kept), else
--- the skin's while its FromSkin companion is on, else the swatch `cfg[key]`.
local function tint(cfg, key)
    local r, g, b, a = rgba(cfg[key])
    if cfg[CLASS_COLOR_OF[key]] == true and NS.ClassColor then
        local cr, cg, cb = NS.ClassColor("player")
        if cr ~= nil then return cr, cg, cb, a end
    end
    local sr, sg, sb, sa = skinTint(cfg, key)
    if sr ~= nil then return sr, sg, sb, sa end
    return r, g, b, a
end

local function num(v, default)
    if type(v) == "number" and v == v then return v end
    return default
end

local function media(kind, key)
    if type(key) ~= "string" or key == "" then return nil end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    return LSM and LSM:Fetch(kind, key, true) or nil
end

local function fontFace(key)
    local face = media("font", key)
    if face then return face end
    local skinFace = NS.Skin and NS.Skin.GetFont and NS.Skin.GetFont()
    if type(skinFace) == "string" and skinFace ~= "" then return skinFace end
    return STANDARD_TEXT_FONT
end

-- The label's face: the skin's `hud.font` while `labelFontFromSkin` is on (S.Resolve answers the
-- stored pick while the owner ignores fonts), else the stored pick ("" = the skin's body font).
local function labelFace(cfg)
    local S = NS.Skin
    if cfg.labelFontFromSkin == true and S and S.Resolve then
        local ok, key = pcall(S.Resolve, "hud.font", cfg.labelFont, true)
        local face = ok and media("font", key) or nil
        if face then return face end
    end
    return fontFace(cfg.labelFont)
end

-- The icon border's texture (nil = flat), thickness and whether it shows. While
-- `borderTextureFromSkin` is on the skin's icon border style and thickness draw: "None" hides it,
-- any other style draws flat strips.
local function iconEdge(cfg)
    local size = math.max(1, num(cfg.borderSize, 1))
    local tex, shown = media("statusbar", cfg.borderTexture), cfg.border ~= false
    local S = NS.Skin
    if cfg.borderTextureFromSkin ~= true or not (S and S.Resolve) then return tex, size, shown end
    local okStyle, style = pcall(S.Resolve, "icon.borderStyle", cfg.borderTexture, true)
    if okStyle and type(style) == "string" and style ~= cfg.borderTexture then
        tex = nil
        if style == "None" then shown = false end
    end
    local okSize, skinSize = pcall(S.Resolve, "icon.borderSize", size, true)
    if okSize and type(skinSize) == "number" then size = math.max(1, skinSize) end
    return tex, size, shown
end

-- The lane border's texture (nil = flat), thickness and whether it shows, through S.BarBorder: a
-- skin's real bar border style wins while `laneBorderTextureFromSkin` is on; its None hands back the
-- stored three.
local function laneEdge(cfg)
    local stored, show = cfg.laneBorderTexture, cfg.laneBorder == true
    local size = math.max(1, num(cfg.laneBorderSize, 1))
    local S = NS.Skin
    if S and S.BarBorder then
        local ok, style, skinShow, skinSize = pcall(S.BarBorder, stored, show, size,
            cfg.laneBorderTextureFromSkin == true)
        if ok and style ~= stored then
            return nil, skinShow == true, math.max(1, num(skinSize, size))
        end
    end
    return media("statusbar", stored), show, size
end

-- ── edges (an icon's border and glow, the lane's border): four strips round a frame ────────────

local EDGE_KEYS = { "top", "bottom", "left", "right" }

local function newEdges(owner, layer, sublevel)
    local e = {}
    for i = 1, 4 do e[i] = owner:CreateTexture(nil, layer, nil, sublevel) end
    return e
end

-- Strips `size` thick, `out` pixels outside the frame's bounds.
local function placeEdges(e, frame, size, out)
    for i, key in ipairs(EDGE_KEYS) do
        local t = e[i]
        t:ClearAllPoints()
        if key == "top" or key == "bottom" then
            local p = key == "top" and "TOP" or "BOTTOM"
            local dy = key == "top" and out or -out
            t:SetPoint(p .. "LEFT", frame, p .. "LEFT", -out, dy)
            t:SetPoint(p .. "RIGHT", frame, p .. "RIGHT", out, dy)
            t:SetHeight(size)
        else
            local p = key == "left" and "LEFT" or "RIGHT"
            local dx = key == "left" and -out or out
            t:SetPoint("TOP" .. p, frame, "TOP" .. p, dx, out)
            t:SetPoint("BOTTOM" .. p, frame, "BOTTOM" .. p, dx, -out)
            t:SetWidth(size)
        end
    end
end

local function paintEdges(e, cfg, key, texture)
    local r, g, b, a = tint(cfg, key)
    for i = 1, 4 do
        local t = e[i]
        if texture then
            t:SetTexture(texture)
            t:SetVertexColor(r, g, b, a)
        else
            t:SetColorTexture(r, g, b, a)
        end
    end
end

local function showEdges(e, shown)
    for i = 1, 4 do e[i]:SetShown(shown) end
end

-- ── the long-cooldown glow ─────────────────────────────────────────────────────────────────────

-- A plain spell's base cooldown in ms, cached; nil when it came back secret (not cached, retried).
local function baseCooldown(id)
    local ms = cdCache[id]
    if ms ~= nil then return ms end
    local ok, v = pcall(NS.Compat.SpellBaseCooldown, id)
    if not ok or Secrets.IsSealed(v) then return nil end
    ms = type(v) == "number" and v or 0
    cdCache[id] = ms
    return ms
end

local function wantsGlow(spellID, cfg)
    if not spellID or cfg.glowLongCD == false then return false end
    local ms = baseCooldown(spellID)
    return ms ~= nil and ms >= num(cfg.glowMinCD, 29) * 1000
end

-- ── one icon ───────────────────────────────────────────────────────────────────────────────────

local function onEnter(self)
    local id = self.spellID
    if not id then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetSpellByID(id)
    GameTooltip:Show()
end

local function onLeave()
    GameTooltip:Hide()
end

local function newIcon(lane)
    local f = CreateFrame("Frame", nil, lane)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints(f)
    f.border = newEdges(f, "OVERLAY", 1)
    f.glow = newEdges(f, "OVERLAY", 2)
    f.mark = f:CreateTexture(nil, "OVERLAY", nil, 3)
    f.mark:SetAllPoints(f)
    f.count = f:CreateFontString(nil, "OVERLAY")
    f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.name = f:CreateFontString(nil, "OVERLAY")
    f.name:SetPoint("TOP", f, "BOTTOM", 0, -1)
    return f
end

local function paintMark(f)
    local path = NS.Icon and NS.Icon("ph:x")
    if path then f.mark:SetTexture(path) end
    local r, g, b, a = NS.SkinColor("ct.lane.cross")
    if r then f.mark:SetVertexColor(r, g, b, a) end
end

local function setTooltip(f, on)
    f:EnableMouse(on)
    f:SetScript("OnEnter", on and onEnter or nil)
    f:SetScript("OnLeave", on and onLeave or nil)
end

local function refreshName(f, cfg)
    local text
    if cfg.showName == true and f.spellID then
        local ok, v = pcall(NS.Compat.SpellName, f.spellID)
        text = ok and Secrets.PlainString(v) or nil
    end
    f.name:SetText(text or "")
    f.name:SetShown(text ~= nil)
end

--- Every look a lane setting decides, on one icon (a push, and every Apply on the live ones).
local function styleIcon(f, cfg, face)
    local size = math.max(1, num(cfg.iconSize, 28))
    f:SetSize(size, size)
    local z = math.min(0.45, math.max(0, num(cfg.zoom, 0)))
    f.tex:SetTexCoord(z, 1 - z, z, 1 - z)
    local edgeTex, edgeSize, edgeShown = iconEdge(cfg)
    placeEdges(f.border, f, edgeSize, 0)
    paintEdges(f.border, cfg, "borderColor", edgeTex)
    showEdges(f.border, edgeShown)
    placeEdges(f.glow, f, GLOW_SIZE, GLOW_SIZE)
    paintEdges(f.glow, cfg, "glowColor")
    showEdges(f.glow, wantsGlow(f.spellID, cfg))
    paintMark(f)
    f.count:SetFont(face, math.max(8, math.floor(size * 0.4)), "OUTLINE")
    f.name:SetFont(face, math.max(8, math.floor(size * 0.35)), "OUTLINE")
    setTooltip(f, cfg.tooltip ~= false)
    refreshName(f, cfg)
end

local function setItem(f, item, cfg)
    f.t = num(item.t, GetTime())
    f.spellID = item.spellID
    f.interrupted = item.interrupted == true
    f.n = 1
    f.tex:SetTexture(item.texture)
    f.mark:SetShown(f.interrupted)
    f.count:SetText("")
    f.count:Hide()
    showEdges(f.glow, wantsGlow(f.spellID, cfg))
    refreshName(f, cfg)
end

-- ── the pool ───────────────────────────────────────────────────────────────────────────────────

-- One icon back to the free list (the pool's documented plain shape; see the header).
local function releaseOne(pool, f)
    f:Hide()
    local active = pool.active
    for i = #active, 1, -1 do
        if active[i] == f then
            table.remove(active, i)
            break
        end
    end
    pool.free[#pool.free + 1] = f
end

-- Every icon from position `from` on (the oldest) goes back to the pool.
local function expireFrom(st, from)
    local icons = st.icons
    for i = #icons, from, -1 do
        releaseOne(st.pool, icons[i])
        icons[i] = nil
    end
end

-- The band: the newest at lane level + ICON_BAND, each older one a level lower, the rest at + 1.
local function restack(st)
    local base = st.frame:GetFrameLevel()
    local band = LAYERS.LEVEL.ICON_BAND
    for i, f in ipairs(st.icons) do
        f:SetFrameLevel(base + math.max(1, band - i + 1))
    end
end

-- ── motion ─────────────────────────────────────────────────────────────────────────────────────

local function layoutIcons(st, now)
    local cfg, frame, icons = st.cfg, st.frame, st.icons
    local pad = math.max(0, num(cfg.padding, 0))
    local speed = Layout.Speed(cfg)
    local prev
    for i = 1, #icons do
        local f = icons[i]
        local d = Layout.Distance(now - f.t, prev, cfg)
        if Layout.Expired(d, cfg) then
            expireFrom(st, i)
            break
        end
        local x, y = Layout.Offset(d, cfg)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", frame, "TOPLEFT", x + pad, y - pad)
        f:SetAlpha(Layout.Alpha(d / speed, cfg))
        prev = d
    end
end

local function onUpdate(frame)
    local st = frame.__ctLane
    local t0 = Perf.on and debugprofilestop()
    layoutIcons(st, GetTime())
    if #st.icons == 0 then frame:SetScript("OnUpdate", nil) end
    if t0 then Perf.Note("laneRender", debugprofilestop() - t0) end
end

local function arm(st)
    if #st.icons > 0 and not st.frame:GetScript("OnUpdate") then
        st.frame:SetScript("OnUpdate", onUpdate)
    end
end

-- ── the lane's own surfaces ────────────────────────────────────────────────────────────────────

local function hasteNow()
    if not InCombatLockdown() then
        local ok, v = pcall(NS.Compat.SpellHaste)
        local plain = ok and Secrets.PlainNumber(v) or nil
        if plain then haste = plain end
    end
    return haste
end

-- Where a line `d` pixels from the now edge sits inside the lane: x, y, w, h.
local function linePoint(d, cfg, thick)
    local pad = math.max(0, num(cfg.padding, 0))
    local length = math.max(1, num(cfg.width, 480))
    local icon = math.max(1, num(cfg.iconSize, 28))
    local dir = cfg.direction
    if dir == "right" then return pad + d - thick / 2, -pad, thick, icon end
    if dir == "down" then return pad, -(pad + d - thick / 2), icon, thick end
    if dir == "up" then return pad, -(pad + length - d - thick / 2), icon, thick end
    return pad + length - d - thick / 2, -pad, thick, icon
end

local function placeLine(t, frame, d, cfg, thick)
    local x, y, w, h = linePoint(d, cfg, thick)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    t:SetSize(w, h)
end

local function applyTicks(st, cfg)
    local offsets = {}
    if cfg.ticks ~= false then
        st.step = Layout.TickStep(cfg, cfg.tickSpacing == "haste" and hasteNow() or nil)
        offsets = Layout.TickOffsets(cfg, st.step)
    end
    local thick = math.max(1, num(cfg.tickWidth, 1))
    for i, d in ipairs(offsets) do
        local t = st.ticks[i]
        if not t then
            t = st.frame:CreateTexture(nil, "BORDER", nil, 1)
            st.ticks[i] = t
        end
        t:SetColorTexture(tint(cfg, "tickColor"))
        placeLine(t, st.frame, d, cfg, thick)
        t:Show()
    end
    for i = #offsets + 1, #st.ticks do st.ticks[i]:Hide() end
    st.tickCount = #offsets
end

local function applyBackground(st, cfg)
    local tex = media("statusbar", cfg.bgTexture)
    if tex then
        st.bg:SetTexture(tex)
        st.bg:SetVertexColor(tint(cfg, "bgColor"))
    else
        st.bg:SetColorTexture(tint(cfg, "bgColor"))
    end
    st.bg:SetShown(cfg.background ~= false)
    local edgeTex, edgeShown, edgeSize = laneEdge(cfg)
    placeEdges(st.edges, st.frame, edgeSize, 0)
    paintEdges(st.edges, cfg, "laneBorderColor", edgeTex)
    showEdges(st.edges, edgeShown)
    st.now:SetColorTexture(tint(cfg, "nowColor"))
    placeLine(st.now, st.frame, 0, cfg, NOW_WIDTH)
    st.now:SetShown(cfg.now ~= false)
end

local LABEL_POINTS = {
    LEFT   = { "RIGHT", "LEFT", -4, 0 },
    RIGHT  = { "LEFT", "RIGHT", 4, 0 },
    TOP    = { "BOTTOMLEFT", "TOPLEFT", 0, 2 },
    BOTTOM = { "TOPLEFT", "BOTTOMLEFT", 0, -2 },
}

-- The label's words, and the Pet lane's dim while there is no pet to name.
local function labelText(st, cfg)
    local fs = st.label
    fs:SetText(NS.LaneCasts.LabelText(st.key))
    local typed = type(cfg.labelText) == "string" and cfg.labelText ~= ""
    local dim = st.key == "pet" and not typed and NS.LaneCasts.PetName() == nil
    fs:SetAlpha(dim and LABEL_DIM or 1)
end

-- The label's stored shadow: the HUD text's shadow color at the one-pixel offset, or none.
local function storedShadow(cfg)
    if cfg.labelShadow ~= true then return false end
    local r, g, b, a = NS.SkinColor("ct.hud.shadow")
    if not r then return true end
    return { 1, -1, r, g, b, a or 1 }
end

local labelFont = {}   -- refilled per call: S.HudFont keeps nothing of it

local function applyLabel(st, cfg)
    local fs = st.label
    -- Face, size, flags and shadow through S.HudFont, the one way a 12.0.7 client draws a HUD
    -- string's shadow; a stored "@skin" flag resolves through S.FontFlags inside it.
    labelFont.face, labelFont.size = labelFace(cfg), math.max(6, num(cfg.labelSize, 12))
    labelFont.flags = type(cfg.labelOutline) == "string" and cfg.labelOutline or ""
    labelFont.shadow, labelFont.shadowFromSkin = storedShadow(cfg), cfg.labelShadowFromSkin == true
    NS.Skin.HudFont(fs, labelFont)
    fs:SetTextColor(tint(cfg, "labelColor"))
    local p = LABEL_POINTS[cfg.labelPosition] or LABEL_POINTS.LEFT
    fs:ClearAllPoints()
    fs:SetPoint(p[1], st.frame, p[2], p[3], p[4])
    labelText(st, cfg)
    fs:SetShown(cfg.label ~= false)
end

-- ── the lane frame ─────────────────────────────────────────────────────────────────────────────

-- Whether a lane shows now, and its opacity (modules/LaneVisibility.lua).
local function visibleNow(laneKey)
    local V = NS.LaneVisibility
    if not V then return true, 1 end
    return V.Decide(laneKey)
end

local function build(laneKey)
    local frame = CreateFrame("Frame", FRAME_NAMES[laneKey], UIParent)
    frame:Hide()
    frame:SetClampedToScreen(true)
    local st = { key = laneKey, frame = frame, pool = Pool.New(), icons = {}, ticks = {} }
    st.factory = function() return newIcon(frame) end
    st.bg = frame:CreateTexture(nil, "BACKGROUND")
    st.bg:SetAllPoints(frame)
    st.edges = newEdges(frame, "BORDER", 2)
    st.now = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    st.label = frame:CreateFontString(nil, "OVERLAY")
    frame.__ctLane = st
    lanes[laneKey] = st
    return st
end

--- The lane's frame, built on first ask (hidden until an Apply shows it).
--- @param laneKey string "player" | "pet"
--- @return table frame
function LaneRender.Get(laneKey)
    local st = lanes[laneKey] or build(laneKey)
    return st.frame
end

--- Release every icon of a lane and stop its OnUpdate.
function LaneRender.Clear(laneKey)
    local st = lanes[laneKey]
    if not st then return end
    Pool.ReleaseAll(st.pool)
    st.icons = {}
    st.frame:SetScript("OnUpdate", nil)
end

--- Re-read a lane's settings: size, layer, place, surfaces, and every live icon restyled. A lane
--- switched off (or the addon stood down) is cleared and hidden.
function LaneRender.Apply(laneKey)
    local cfg = cfgOf(laneKey)
    if not cfg then return end
    if not enabledNow(laneKey) then
        if lanes[laneKey] then
            LaneRender.Clear(laneKey)
            lanes[laneKey].frame:Hide()
        end
        return
    end
    LaneRender.Get(laneKey)
    local st = lanes[laneKey]
    st.cfg = cfg
    local frame = st.frame
    frame:SetSize(Layout.LaneSize(cfg))
    frame:SetScale(math.max(0.1, num(cfg.scale, 1)))
    -- The strata, the level and the point (modules/LaneAnchor.lua).
    if NS.LaneAnchor then NS.LaneAnchor.Apply(laneKey) end
    applyBackground(st, cfg)
    applyTicks(st, cfg)
    applyLabel(st, cfg)
    local face = fontFace(cfg.labelFont)
    for _, f in ipairs(st.icons) do styleIcon(f, cfg, face) end
    restack(st)
    LaneRender.ApplyVisibility(laneKey)
    if frame:IsShown() then
        layoutIcons(st, GetTime())
        arm(st)
    end
end

--- Show or hide a built lane, and set its opacity, as modules/LaneVisibility.lua decides. A lane
--- that hides lets go of its icons.
--- @param laneKey string
function LaneRender.ApplyVisibility(laneKey)
    local st = lanes[laneKey]
    if not (st and st.cfg) or not enabledNow(laneKey) then return end
    local shown, alpha = visibleNow(laneKey)
    st.frame:SetAlpha(alpha)
    if shown then
        if not st.frame:IsShown() then st.frame:Show() end
    elseif st.frame:IsShown() or #st.icons > 0 then
        LaneRender.Clear(laneKey)
        st.frame:Hide()
    end
end

--- Every lane from the current settings (login, stand-up, a profile change).
function LaneRender.Sync()
    for _, laneKey in ipairs(LANES) do LaneRender.Apply(laneKey) end
    if NS.Debug then NS.Debug("Lanes", "lanes synced") end
end

-- A repeat of the newest cast folds into its icon (the `stack` setting): the count goes up and the
-- icon starts again from the now edge.
local function stackOnto(st, item)
    local top = st.icons[1]
    if st.cfg.stack ~= true or not top or not item.spellID or item.interrupted or top.interrupted then
        return false
    end
    if top.spellID ~= item.spellID then return false end
    top.n = top.n + 1
    top.t = num(item.t, GetTime())
    top.count:SetText(tostring(top.n))
    top.count:Show()
    return true
end

-- Haste moves the ticks: re-read out of combat on each push while the lane uses it.
local function refreshHasteTicks(st)
    local cfg = st.cfg
    if cfg.ticks == false or cfg.tickSpacing ~= "haste" then return end
    if Layout.TickStep(cfg, hasteNow()) ~= st.step then applyTicks(st, cfg) end
end

--- Show one cast on a lane.
--- @param laneKey string
--- @param item table { texture, spellID|nil, t, interrupted }
function LaneRender.Push(laneKey, item)
    if type(item) ~= "table" or not enabledNow(laneKey) then return end
    local st = lanes[laneKey]
    if not (st and st.cfg) then
        LaneRender.Apply(laneKey)
        st = lanes[laneKey]
        if not (st and st.cfg) then return end
    end
    -- A hidden lane takes no push, unless the cast itself changed the answer (the pull's first cast).
    if not st.frame:IsShown() then
        LaneRender.ApplyVisibility(laneKey)
        if not st.frame:IsShown() then return end
    end
    local t0 = Perf.on and debugprofilestop()
    if not stackOnto(st, item) then
        local f = Pool.Acquire(st.pool, st.factory)
        styleIcon(f, st.cfg, fontFace(st.cfg.labelFont))
        setItem(f, item, st.cfg)
        table.insert(st.icons, 1, f)
        if #st.icons > LaneRender.MAX_ICONS then expireFrom(st, LaneRender.MAX_ICONS + 1) end
        restack(st)
    end
    refreshHasteTicks(st)
    labelText(st, st.cfg)
    layoutIcons(st, GetTime())
    arm(st)
    if t0 then Perf.Note("laneRender", debugprofilestop() - t0) end
end

--- The lifecycle's stand-down: no icon, no OnUpdate, every lane hidden.
function LaneRender.Suspend()
    for _, st in pairs(lanes) do
        LaneRender.Clear(st.key)
        st.frame:Hide()
    end
end

--- The lifecycle's stand-up: rebuilt from the CURRENT settings.
function LaneRender.Resume()
    LaneRender.Sync()
end

-- ── the bus ────────────────────────────────────────────────────────────────────────────────────

local function onPush(_, laneKey, item)
    LaneRender.Push(laneKey, item)
end

-- A lane's own setting re-applies that lane; a profile change re-applies both.
local function onSettingsChanged(_, path)
    if type(path) ~= "string" then return end
    if path == "profile" then return LaneRender.Sync() end
    local laneKey = path:match("^lanes%.([^.]+)%.")
    if laneKey and FRAME_NAMES[laneKey] then
        LaneRender.Apply(laneKey)
        -- The other lane may dock to this one: it follows a switch or a size change.
        for _, other in ipairs(LANES) do
            if other ~= laneKey and lanes[other] then LaneRender.Apply(other) end
        end
    end
end

local busTarget = NS.NewBusTarget()
if busTarget then
    busTarget:RegisterMessage(NS.MSG.LANE_PUSH, onPush)
    busTarget:RegisterMessage(NS.MSG.SETTINGS_CHANGED, onSettingsChanged)
end

-- A skin switch: every built lane re-applies over the new skin's tokens (the header's THE SKIN).
NS.Skin.OnLooksChanged(function()
    for _, laneKey in ipairs(LANES) do
        if lanes[laneKey] then LaneRender.Apply(laneKey) end
    end
end)

-- ── for the suites ─────────────────────────────────────────────────────────────────────────────

--- The lane's live icons, newest first.
function LaneRender.__icons(laneKey)
    local st = lanes[laneKey]
    local out = {}
    for i, f in ipairs(st and st.icons or {}) do out[i] = f end
    return out
end

--- The lane's frame when it was built, else nil (never builds one: the diagnostics report reads it).
function LaneRender.Frame(laneKey)
    return lanes[laneKey] and lanes[laneKey].frame or nil
end

function LaneRender.__pool(laneKey) return lanes[laneKey] and lanes[laneKey].pool end

--- The lane's shown ticks, nearest the now edge first.
function LaneRender.__ticks(laneKey)
    local st = lanes[laneKey]
    local out = {}
    for i = 1, st and st.tickCount or 0 do out[i] = st.ticks[i] end
    return out
end

function LaneRender.__label(laneKey) return lanes[laneKey] and lanes[laneKey].label end
function LaneRender.__bg(laneKey) return lanes[laneKey] and lanes[laneKey].bg end
function LaneRender.__now(laneKey) return lanes[laneKey] and lanes[laneKey].now end
