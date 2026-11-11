local _, NS = ...
-- modules/Style.lua — the look the HUD and the Results window share with the other Ka0s windows
-- (LootHistory's browser is the reference; BankLedger and MultiMeters agree): Blizzard's font objects
-- for every label, the header gold, the title-bar geometry, and the title-bar controls that turn gold
-- under the pointer. Ported from DPS Race @045f479 (modules/Style.lua) without the new-best toast's
-- scaled text (no toast in Combat Trail).
--
-- FONT OBJECTS, NOT FONT FILES. A label takes one of Blizzard's font objects (`GameFontNormal` and its
-- family), never a path and a size, so it reads at the size and weight the rest of the collection
-- uses and follows the client's own font scaling. The one exception is a figure that is meant to be
-- read across the room: the HUD's fight clock, which keeps its own monospace size
-- (modules/Hud_States.lua), and the KPI figures, which take the large `GameFontNormalHuge` the way
-- LootHistory's Insights cards do above a small caption.
--
-- WORDS. Tabs, column headers, buttons and captions are Title Case, as LootHistory's are; prose is
-- Sentence case. Nothing is upper-cased in code: what a label says is its locale string.
--
-- STYLING ONLY. Nothing here reads a meter value or a frame's geometry; a label made here is handed
-- what its caller hands it, and the secret-value rules of the caller still hold.
--
-- THE SKIN (skinning-§3). Every color this addon draws is a token of the owner's skin
-- (core/SkinSetup.lua's NS.Skin): a library token, or one of this addon's own `ct.*` owner tokens
-- whose Ka0s Default value is the pixel the surface draws. A surface reads a color in one of three
-- ways:
--
--   Style.Tok(name)    a LIVE color table { r, g, b, a, token = name }, one per token, filled from
--                      the skin and refilled IN PLACE on every skin change, so a module-level
--                      palette (`local C = { text = Style.Tok("ct.text") }`) keeps its identity and
--                      every later read sees the new skin. The palettes the HUD and the Results
--                      window share are built from these.
--   Style.Paint(fs, c) a label's color AND face through the facade's S.Text, recorded, so the
--                      library replays it on a skin switch (no host repaint owed).
--   Style.OnLooks(fn)  a host repaint for what the library does not record (a color a call site
--                      composes from a live table, markup built into a string): run after the live
--                      tables are refilled, before the windows redraw.
--
-- Labels take the skin's faces: a Blizzard font object is still the size a label is made at, and
-- S.Text keeps that size (scaled by the skin's own size over the reference), so every layout holds.

local Style = {}
NS.Style = Style

-- The line a FONT.SECTION heading takes (16px, its gap under it included), and the clear space above
-- every heading but one at the very top (the owner's call, 2026-10-25: the detail read as cramped).
-- The Results detail and the HUD's running body and result card share both.
Style.SECTION_H = 22
Style.SECTION_GAP = 14

-- The font object each role draws in (Blizzard's; the client defines every one of them).
Style.FONT = {
    TITLE   = "GameFontNormal",          -- a window's title, centered in its title bar (gold)
    TAB     = "GameFontNormal",          -- a tab label (gold when active, gray when not)
    HEADER  = "GameFontNormalSmall",     -- a column header or a section label (gold)
    TEXT    = "GameFontHighlightSmall",  -- rows, cells, buttons, checkboxes, card text (white)
    HEADING = "GameFontHighlight",       -- a name that heads a card or a pane (white, 12px)
    -- The section headings of the Results detail and the HUD (the owner's call, 2026-10-25: a step
    -- above GameFontNormal, so the sections read apart).
    SECTION = "GameFontNormalLarge",     -- a section heading (gold, 16px; HEADER is 10px)
    -- An Insights chart's heading and its list panels' titles: LootHistory's Insights headings (the
    -- owner's call, 2026-10-28: SECTION read too large there).
    CHART   = "GameFontNormal",          -- an Insights chart heading (gold, 12px)
    NAME    = "GameFontHighlightLarge",  -- the character name heading the run detail (white, 16px)
    CAPTION = "GameFontDisableSmall",    -- footers, KPI captions, hints, axis labels (gray)
    FIGURE  = "GameFontNormalHuge",      -- a KPI figure (recolored by its caller)
    EMPTY   = "GameFontDisableLarge",    -- an empty list's message
}

-- ── live colors ─────────────────────────────────────────────────────────────────────────────────

local live = {}      -- token name -> its live color table
local looks = {}     -- the host repaints, in registration order

local function fill(t)
    local r, g, b, a = NS.Skin.Color(t.token)
    t[1], t[2], t[3], t[4] = r or 1, g or 1, b or 1, a or 1
end

--- The live color table for token `name`: { r, g, b, a, token = name }, shared by every caller and
--- refilled in place on a skin change (never replaced).
--- @param name string  a library or owner color token
--- @return table
function Style.Tok(name)
    local t = live[name]
    if not t then
        t = { token = name }
        fill(t)
        live[name] = t
    end
    return t
end

--- Refill every live color table from the skin now in force.
function Style.SyncColors()
    for _, t in pairs(live) do fill(t) end
end

--- Run `fn()` after every skin change, once the live tables hold the new skin.
--- @param fn function
--- @return function fn
function Style.OnLooks(fn)
    looks[#looks + 1] = fn
    return fn
end

-- One listener for the owner: the tables first, the host repaints next, then the windows redraw
-- (HudAppearance.Changed, plan Task 3.2: the HUD bodies, the rows and the Results tabs re-read every
-- color; until it exists the HUD redraws itself through Hud.Refresh).
NS.Skin.OnLooksChanged(function()
    Style.SyncColors()
    for _, fn in ipairs(looks) do fn() end
    if NS.HudAppearance and NS.HudAppearance.Changed then NS.HudAppearance.Changed()
    elseif NS.Hud and NS.Hud.Refresh then NS.Hud.Refresh() end
end)

--- `c`'s r, g, b (a live table or a token name), then `a` (default the color's own alpha).
function Style.Rgba(c, a)
    if type(c) == "string" then c = Style.Tok(c) end
    return c[1], c[2], c[3], a or c[4] or 1
end

--- `c`'s r, g, b only.
function Style.Rgb(c)
    if type(c) == "string" then c = Style.Tok(c) end
    return c[1], c[2], c[3]
end

-- ── textures tinted from the skin ───────────────────────────────────────────────────────────────
-- A texture the host colors itself (a rule, a wash, a mark, an icon's tint) through these two: the
-- color is drawn now and drawn again after every skin change, from the latest call's color (a pooled
-- texture takes its next item's). `c` is a live table or a token name; a data hue (a table with no
-- token) is drawn as given and stays.

local filled = setmetatable({}, { __mode = "k" })   -- texture -> { c, a }, SetColorTexture
local vertexed = setmetatable({}, { __mode = "k" }) -- texture -> { c, a }, SetVertexColor

--- `tex`:SetColorTexture in `c`, at alpha `a` (default the color's own).
local function remember(set, tex, c, a)
    local e = set[tex]
    if e then e[1], e[2] = c, a else set[tex] = { c, a } end
end

function Style.Fill(tex, c, a)
    remember(filled, tex, c, a)
    tex:SetColorTexture(Style.Rgba(c, a))
end

--- `tex`:SetVertexColor in `c`, at alpha `a` (default the color's own).
function Style.Vertex(tex, c, a)
    remember(vertexed, tex, c, a)
    tex:SetVertexColor(Style.Rgba(c, a))
end

Style.OnLooks(function()
    for tex, v in pairs(filled) do tex:SetColorTexture(Style.Rgba(v[1], v[2])) end
    for tex, v in pairs(vertexed) do tex:SetVertexColor(Style.Rgba(v[1], v[2])) end
end)

--- A "|cffrrggbb" escape for a DATA hue `c` (no token: the same under every skin), each channel
--- rounded to the byte. A token's escape is NS.SkinEscape's.
function Style.HueEscape(c)
    local function byte(v) return math.floor(v * 255 + 0.5) end
    return ("|cff%02x%02x%02x"):format(byte(c[1]), byte(c[2]), byte(c[3]))
end

-- ── boxes tinted with a meaning color ───────────────────────────────────────────────────────────
-- A chip, a badge and a status tag tint the DATA's color (a meaning token, or a rung-4 data hue):
-- this much of it fills the box, this much draws its edge (D-4: the data's color at the surface's
-- own opacity). Painted by the host on every bind, never by a recorded primitive, so a pooled box
-- takes the next item's color.

--- The plain white texture a tint (Style.Stripe, Style.Vertex) is drawn on.
Style.WHITE = "Interface\\Buttons\\WHITE8x8"
Style.FLAT = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
Style.TINT_FILL_A, Style.CHIP_EDGE_A, Style.BADGE_EDGE_A = 0.08, 0.55, 0.6

--- A 1px box for Style.TintBox, its colors unset.
function Style.FlatBox(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if f.SetBackdrop then f:SetBackdrop(Style.FLAT) end
    return f
end

--- Tint `f` (a Style.FlatBox) with `c` (a live table, or a data hue): the fill at TINT_FILL_A, the
--- edge at `edgeA`.
function Style.TintBox(f, c, edgeA)
    if not f.SetBackdropBorderColor then return end
    f:SetBackdropBorderColor(c[1], c[2], c[3], edgeA)
    f:SetBackdropColor(c[1], c[2], c[3], Style.TINT_FILL_A)
end

-- ── the list stripe ─────────────────────────────────────────────────────────────────────────────

--- The stripe's alpha for the row at `index` (1-based): the skin's `ct.list.stripe` on every even
--- row, none on the odd.
function Style.StripeAlpha(index)
    return index % 2 == 0 and Style.Tok("ct.list.stripe")[4] or 0
end

--- Stripe `tex` (a white texture) for the row at `index`.
function Style.Stripe(tex, index)
    if index % 2 == 0 then Style.Vertex(tex, "ct.list.stripe") else Style.Vertex(tex, "ct.list.stripe", 0) end
end

-- The header gold (Ka0s Default's `text.accent`, NORMAL_FONT_COLOR): the title, the column headers,
-- the active tab, the sort arrows and a hovered title-bar control are all this one color.
Style.GOLD = Style.Tok("text.accent")
-- A title-bar control at rest: the close control's own gray (`icon.tint`).
Style.REST = Style.Tok("icon.tint")

-- The title bar, the tab strip and a control slot (LootHistory and BankLedger: titleBarH 30,
-- tabStripH 26, 90px tabs on a 94px pitch; the close control's 18px slot). The bar's height is the
-- skin's `title.height`, read once: geometry every layout in the windows is built on, and the same in
-- every skin (SkinDefs), with 30 for a degraded load.
Style.TITLE_BAR_H = NS.Skin.Token("title.height") or 30
Style.TAB_STRIP_H = 26
Style.TAB_W, Style.TAB_PITCH = 90, 94
Style.CONTROL = 18
Style.CONTROL_PITCH = 22

-- The text role each font object answers when no color is named: the gold objects are headings (the
-- skin's title face), the white ones the highlight white, the gray ones the disabled gray (Ka0s
-- Default's text.heading, text.highlight and text.disabled are those objects' own colors).
local OBJECT_ROLE = {
    GameFontNormal = "heading", GameFontNormalSmall = "heading", GameFontNormalLarge = "heading",
    GameFontNormalHuge = "heading",
    GameFontHighlight = "text.highlight", GameFontHighlightSmall = "text.highlight",
    GameFontHighlightLarge = "text.highlight",
    GameFontDisableSmall = "disabled", GameFontDisableLarge = "disabled",
}
-- A gold token on a gold font object keeps the heading role (and its title face).
local GOLD_TOKEN = { ["text.heading"] = true, ["text.accent"] = true, ["title.text"] = true }
-- The library's text roles, by the token each draws.
local TOKEN_ROLE = { ["text.body"] = "body", ["text.muted"] = "muted", ["text.disabled"] = "disabled" }

local painted = setmetatable({}, { __mode = "k" })   -- fs -> the role or token last painted
local fontOf = setmetatable({}, { __mode = "k" })    -- fs -> the font object it was made in
local tinted = setmetatable({}, { __mode = "k" })    -- fs -> the token its color is

-- The token each library role draws, for the host's own tint (below).
local ROLE_TOKEN = { body = "text.body", muted = "text.muted", heading = "text.heading",
                     disabled = "text.disabled", title = "title.text", accent = "text.accent" }

local function tint(fs, token)
    local c = Style.Tok(token)
    if c[4] == 1 then fs:SetTextColor(c[1], c[2], c[3]) else fs:SetTextColor(c[1], c[2], c[3], c[4]) end
end

-- Every painted label's color again, after a switch (the library's replay has already put the role's
-- color and face back on each; this is the same color, for a label the library cannot see).
Style.OnLooks(function() for fs, token in pairs(tinted) do tint(fs, token) end end)

--- The S.Text role for a label in font object `font` colored `color` (a live table, a token name or
--- nil for the object's own role).
function Style.Role(font, color)
    local token = type(color) == "table" and color.token or color
    local own = OBJECT_ROLE[font] or "text.highlight"
    if token == nil then return own end
    if GOLD_TOKEN[token] and own == "heading" then return "heading" end
    return TOKEN_ROLE[token] or token
end

--- Paint `fs` through the skin: its color from `color` (a live table or a token name) and the face
--- of its role, recorded by the library so a skin switch repaints it. A label already painted the
--- same way is left alone, so a 4 Hz redraw calls nothing (`force` paints it again: a caller that
--- set another font object on it since). `font` is the object it was made in (default the one
--- Style.Text or Style.PlainText made it in).
--- @param fs table
--- @param color table|string
--- @param font string|nil
--- @param force boolean|nil
function Style.Paint(fs, color, font, force)
    if type(color) == "table" and not color.token then return Style.Hue(fs, color, force) end
    local role = Style.Role(font or fontOf[fs], color)
    if painted[fs] == role and not force then return end
    painted[fs] = role
    NS.Skin.Text(fs, role)
    -- The same color by the host's hand too, kept in `tinted` so a switch tints it again: the
    -- degraded facade's Text is a no-op, and the color must not wait on the library's replay.
    local token = ROLE_TOKEN[role] or role
    tinted[fs] = token
    tint(fs, token)
end

--- The color Style.Paint would give `fs`, alpha included, and nothing else: for a label that takes
--- its face and shadow from S.HudFont, which a forced Paint would put back on the role's face. Paint's
--- stamp is not consulted, because the color it remembers is not the one on the string.
--- @param fs table
--- @param color table|string
function Style.Recolor(fs, color)
    local c = color
    if type(c) ~= "table" or c.token then
        local role = Style.Role(fontOf[fs], c)
        c = Style.Tok(ROLE_TOKEN[role] or role)
    end
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local SkinLib = LibStub and LibStub("LibKa0s-Skin-1.0", true)

--- Color `fs` with a DATA hue `c` ({ r, g, b }, no token: a class color or a content kind's
--- hue, skinning rung 4), the same under every skin. The label keeps the skin's body face
--- (S.Font) and gives up any role it was painted in, so a skin switch never puts a role's color back
--- over the hue.
--- @param fs table
--- @param c table
function Style.Hue(fs, c, force)
    if painted[fs] ~= "hue" or force then
        if painted[fs] and SkinLib then SkinLib:Untrack(fs) end
        painted[fs], tinted[fs] = "hue", nil
        NS.Skin.Font(fs)
    end
    fs:SetTextColor(c[1], c[2], c[3])
end

--- A FontString in `font` (a Style.FONT value), never wrapping, painted through the skin: `color`
--- (a live table from Style.Tok, or a token name) recolors it; nil keeps the font object's own role.
--- @param parent table
--- @param font string  a font object's name
--- @param color table|string|nil
--- @param justify string|nil  "LEFT" (default) | "CENTER" | "RIGHT"
--- @return table
function Style.Text(parent, font, color, justify)
    font = font or Style.FONT.TEXT
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fontOf[fs] = font
    Style.Paint(fs, color, font)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

--- A FontString in `font` the skin never paints: a HUD Appearance block owns its face and color
--- (modules/Hud_Appearance.lua), and a recorded S.Text would put the skin's face back over the
--- player's on every switch.
function Style.PlainText(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or Style.FONT.TEXT)
    fontOf[fs] = font or Style.FONT.TEXT
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

--- The texture markup for a catalog icon tinted `color`, at the line's height, with a Blizzard
--- fallback when the catalog cannot answer (an inline texture ignores its FontString's color, so the
--- tint is in the markup: LootHistory's sort arrows).
--- @param name string  a catalog icon this addon declares
--- @param fallback string  a texture path the client always has
--- @param color table  a live color table (Style.Tok); markup is a string, so a caller that keeps it
---                     builds it again in a Style.OnLooks repaint
--- @return string
function Style.IconMarkup(name, fallback, color)
    local path = NS.Icon(name) or fallback
    local function byte(v) return math.floor(v * 255 + 0.5) end
    return ("|T%s:0:0:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(path, byte(color[1]), byte(color[2]), byte(color[3]))
end

-- ── tooltip bodies ──────────────────────────────────────────────────────────────────────────────
-- BULLETS FROM TWO LINES ON (the owner's call, 2026-10-26): every tooltip the addon draws itself puts
-- each line under its title on a bullet once there are two or more of them, a dim footer hint
-- included; a single line stays plain. Each line keeps its own color. Only the addon's own lines come
-- through here: the client's spell and item text (SetSpellByID, SetItemByID, SetHyperlink) never does.

Style.BULLET = "\226\128\162 "

--- The bullet `lines[first..]` take: Style.BULLET for two or more, "" for one.
--- @param lines table
--- @param first number
--- @return string
function Style.TipBullet(lines, first)
    return #lines - first >= 1 and Style.BULLET or ""
end

--- Add `lines[first..]` to `tip`, each a string (in `r, g, b`, the skin's `gtip.body` without) or
--- { text, r, g, b }, wrapped, on a bullet when there are two or more.
--- @param tip table  GameTooltip
--- @param lines table
--- @param first number
--- @param r number|nil
--- @param g number|nil
--- @param b number|nil
function Style.AddTipLines(tip, lines, first, r, g, b)
    local bullet = Style.TipBullet(lines, first)
    if r == nil then r, g, b = Style.Rgb("gtip.body") end
    for i = first, #lines do
        local l = lines[i]
        if type(l) == "table" then tip:AddLine(bullet .. tostring(l[1]), l[2] or r, l[3] or g, l[4] or b, true)
        else tip:AddLine(bullet .. tostring(l), r, g, b, true) end
    end
end

-- ── the title-bar controls ──────────────────────────────────────────────────────────────────────
-- ONE CONTROL AT A TIME (MultiMeters' HeaderControls). A strip remembers which control the pointer
-- is on; an enter names it and repaints the strip, a leave un-names it ONLY IF IT IS STILL THE ONE
-- NAMED: frames leave in no guaranteed order, so a leave arriving after the next control's enter
-- must not take the gold off the control the pointer is on now. Full alpha in both states.

local function paintControl(b, c)
    if b.icon then b.icon:SetVertexColor(c[1], c[2], c[3], 1) end
    if b.stroke then b.stroke:SetVertexColor(c[1], c[2], c[3], 1) end
    if b.glyph then b.glyph:SetTextColor(c[1], c[2], c[3], 1) end
end

--- Repaint every control of `strip` for the control under the pointer.
--- @param strip table  Style.NewStrip's
function Style.PaintStrip(strip)
    for _, b in ipairs(strip.controls) do paintControl(b, strip.hovered == b and Style.GOLD or Style.REST) end
end

local strips = setmetatable({}, { __mode = "k" })

--- A strip of title-bar controls sharing one hover state, repainted on a skin change.
--- @return table strip  { controls = {}, hovered = nil }
function Style.NewStrip()
    local strip = { controls = {} }
    strips[strip] = true
    return strip
end

Style.OnLooks(function() for strip in pairs(strips) do Style.PaintStrip(strip) end end)

--- Add `b` to `strip`: hooked (never replacing a script the control already has, such as the close
--- control's own tint, which this repaints after) so it turns gold under the pointer.
--- @param strip table
--- @param b table  a control with an `icon` texture and/or a `glyph` FontString (and a second
---                  texture, `stroke`, tinted with the icon: the timeline's `+`)
--- @return table b
function Style.AddToStrip(strip, b)
    if not b then return nil end
    strip.controls[#strip.controls + 1] = b
    local hook = b.HookScript and "HookScript" or "SetScript"
    b[hook](b, "OnEnter", function()
        strip.hovered = b
        Style.PaintStrip(strip)
    end)
    b[hook](b, "OnLeave", function()
        if strip.hovered == b then strip.hovered = nil end
        Style.PaintStrip(strip)
    end)
    paintControl(b, Style.REST)
    return b
end

--- The skin's icon border around a spell icon's texture `tex`, on a frame of its own, since a border
--- needs a frame (S.IconBorder, cause A1). Recorded, so a skin change reaches it. A caller hiding the
--- icon hides this with it. The icon is named (`opts.icon`), so the library's zoom crops its art's own
--- edge inside the 1 px outline: the bare edge frame has no `.icon` for it to find (R3-FIX, image 103).
--- With `hud` the edge is the HUD's `icon.border` (black under Ka0s Default), never a window icon's
--- `icon.outline` (gray): LibKa0s's `opts.hud` (R4-HUD, the owner's scope answer in R4_SIGNOFF.md).
--- @param parent table  a frame
--- @param tex table  the icon's Texture
--- @param hud boolean|nil  true for an icon on the DPS HUD; nil: a window's
--- @return table frame
function Style.IconEdge(parent, tex, hud)
    local edge = CreateFrame("Frame", nil, parent)
    edge:SetAllPoints(tex)
    NS.Skin.IconBorder(edge, { fromSkin = true, icon = tex, hud = hud == true })
    return edge
end

--- The crop a Blizzard icon's art takes inside an edge of this addon's own, or on the HUD: 0.08 per
--- side, the chart's and the timeline's, past the library's 0.07 zoom, so the icon's own rounded
--- native edge never shows inside the edge (R4-ZOOM, the owner's scope answer in R4_SIGNOFF.md).
Style.ICON_CROP = 0.08

--- Crop `tex`'s art by Style.ICON_CROP per side (an item, enchant or gem icon in its quality edge).
--- @param tex table  a Texture
--- @return table tex
function Style.CropIcon(tex)
    local c = Style.ICON_CROP
    tex:SetTexCoord(c, 1 - c, c, 1 - c)
    return tex
end

--- A standalone Blizzard icon, cropped (Style.CropIcon) and edged 1 px through S.IconBorder's
--- Texture form, which hangs the edge on a holder of its own over the icon and shows and hides it
--- with the icon: a window's `icon.outline`, or with `hud` the HUD's `icon.border`. The
--- icon rule (R5-ICON, LibKa0s docs/api/README.md "Icon art: the rule"). The library's 0.07 zoom
--- only tightens, so the 0.08 crop stands through every replay.
--- @param tex table  the icon's Texture
--- @param hud boolean|nil  true for an icon on the HUD; nil: a window's
--- @return table tex
function Style.EdgeIcon(tex, hud)
    Style.CropIcon(tex)
    NS.Skin.IconBorder(tex, { fromSkin = true, hud = hud == true })
    return tex
end

--- A class icon's edge: one cell of the character-creation sheet, cropped inside its cell by
--- ResultsTable.SetClassIcon, so the edge leaves its coords alone (zoom = false: the library's zoom
--- clamps in whole-texture space, which would cut 28% off a cell on the sheet's edge).
--- @param tex table  the class icon's Texture
--- @param hud boolean|nil  true for an icon on the HUD
--- @return table tex
function Style.EdgeClassIcon(tex, hud)
    NS.Skin.IconBorder(tex, { fromSkin = true, zoom = false, hud = hud == true })
    return tex
end

-- ── the header on the title band (R5-DR1) ────────────────────────────────────────────────────
-- Every window's header stands on the title band's own frame: LibKa0s's S.Band, which Shell lays at
-- its own inset (`win.borderSize` in from a flat edge, else 1) and `title.height`, and lays again on
-- a skin switch. S.Header anchors the title and the controls LEFT, CENTER or RIGHT to it at y 0, so
-- each sits on the band's vertical middle in every skin (feedback item 5 of Ka0sAddonsCommonTasks
-- docs/2026-11-03-SMOKE_ROUND5: -HEADER_H/2 off the frame's top was 1 px high of a band inset 1).
-- Recorded, so a switch places them again. The drag strip covers the band left of the controls.
-- With no library (a degraded load: S.Band answers nil, S.Header draws nothing) a host holder
-- stands where Shell would lay the band, and the same anchors are set once by hand.

local CONTROL_PAD = 6   -- the outermost control's gap to the band's right edge (S.Header's pad)

--- The window's title band: the library's, else the host's holder. Answers it and whether it is
--- the library's.
local function bandOf(f)
    local band = NS.Skin.Band and NS.Skin.Band(f)
    if band then return band, true end
    if not f.ctBand then
        local b = CreateFrame("Frame", nil, f)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
        b:SetHeight(Style.TITLE_BAR_H)
        b:EnableMouse(false)
        f.ctBand = b
    end
    return f.ctBand, false
end

--- Where the title band stands now, for a layout that sizes what hangs from its foot: its inset
--- from the frame's top and its height. The library's rule (NS.SkinBandGeometry, S.Band's own: flush
--- and 25 high while EllesmereUI paints the Shell), else the degraded holder's, 1 in and TITLE_BAR_H
--- high. Worked out, never read back off the frame (the window makes no geometry read as it lays out).
--- @return number inset, number height
function Style.BandGeometry()
    if NS.Skin.Band and NS.SkinBandGeometry then return NS.SkinBandGeometry() end
    return 1, Style.TITLE_BAR_H
end

--- The window's title band frame (S.Band, or the degraded holder), for what stands under it.
--- @param f table  the window
--- @return table band
function Style.Band(f)
    return (bandOf(f))
end

--- The header of `f` on its band. `spec.right` lists the title-bar controls outermost first, `spec.n`
--- of them (an entry may be nil: a slot kept for a control that could not be made); each is RIGHT on
--- the band, CONTROL_PAD in, one CONTROL_PITCH apart. `spec.title` is anchored by `spec.align`, else
--- the skin's `title.align` (CENTER with no library). `spec.drag` takes the band's rect up to the
--- controls.
--- @param f table  the window
--- @param spec table  { title = fs, align = "LEFT"|nil, right = { ... }, n = number, drag = frame }
function Style.Header(f, spec)
    local band, fromLib = bandOf(f)
    local n = spec.n or #(spec.right or {})
    local right = {}
    for i = 1, n do
        local b = spec.right[i]
        local x = CONTROL_PAD + (i - 1) * Style.CONTROL_PITCH
        if b then
            right[#right + 1] = { frame = b, width = Style.CONTROL, x = x }
            if not fromLib then
                b:ClearAllPoints()
                b:SetPoint("RIGHT", band, "RIGHT", -x, 0)
            end
        end
    end
    local reach = n > 0 and (CONTROL_PAD + (n - 1) * Style.CONTROL_PITCH + Style.CONTROL + 2) or 0
    local drag = spec.drag
    if drag then
        drag:ClearAllPoints()
        drag:SetPoint("TOPLEFT", band, "TOPLEFT", 0, 0)
        drag:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -reach, 0)
    end
    if fromLib then
        NS.Skin.Header(f, { title = spec.title, align = spec.align, right = right })
        return
    end
    local fs, align = spec.title, spec.align or "CENTER"
    if not fs then return end
    fs:ClearAllPoints()
    if align == "LEFT" then
        fs:SetPoint("LEFT", band, "LEFT", 8, 0)
        if drag then fs:SetPoint("RIGHT", drag, "RIGHT", -4, 0) end
    else
        fs:SetPoint("CENTER", band, "CENTER", 0, 0)
    end
    fs:SetJustifyH(align)
end

--- A title-bar control drawn from the shared catalog, a plain character beneath it when the catalog
--- cannot answer (standalone-windows), with its tooltip. Its tint is the strip's (AddToStrip).
--- @param parent table
--- @param name string  the catalog icon
--- @param glyph string  the plain character drawn when there is no icon
--- @param tip string  the tooltip
--- @param onClick function
--- @return table
function Style.ControlButton(parent, name, glyph, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(Style.CONTROL, Style.CONTROL)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.icon:SetSize(12, 12)
    b.glyph = b:CreateFontString(nil, "OVERLAY", Style.FONT.TEXT)
    b.glyph:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.tip = tip
    Style.SetControlIcon(b, name, glyph)
    b:SetScript("OnClick", function() onClick() end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.tip, Style.Rgb("gtip.value"))
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

--- Draw `name` on a control (the glyph when the catalog has no path). The tint is left as it is.
function Style.SetControlIcon(b, name, glyph)
    local path = NS.Icon(name)
    b.icon:SetShown(path ~= nil)
    b.glyph:SetShown(path == nil)
    if path then b.icon:SetTexture(path) else b.glyph:SetText(glyph) end
    b.iconName = name
end

-- ── the flat buttons ────────────────────────────────────────────────────────────────────────────
-- The skin's Button (LootHistory's bar button: a dark fill, the window's divider gray for an edge, a
-- white label that turns gold under the pointer), with the slots a style or a state paints from
-- another token: primary and danger keep a tinted box, and a disabled one its box and label faded
-- (the ct.*.off* tokens, core/SkinSetup.lua). Ported from DPS Race @045f479 (modules/Hud_States.lua's
-- buttons) for the Results window and the Race window (whose picked length takes the primary look).

local BUTTON_STYLES = {
    normal  = { on = {}, off = { bg = "ct.btn.offBg", border = "ct.btn.offBorder", disabled = "ct.btn.offText" } },
    primary = { primary = true,
                on = { bg = "ct.primary.bg", border = "ct.primary.border", hover = "ct.primary.hover" },
                off = { bg = "ct.primary.offBg", border = "ct.primary.offBorder", disabled = "ct.primary.offText" } },
    danger  = { on = { bg = "ct.danger.bg", border = "ct.danger.border", text = "ct.danger.text",
                       hover = "ct.danger.hover" },
                off = { bg = "ct.danger.offBg", border = "ct.danger.offBorder", disabled = "ct.danger.offText" } },
}
Style.BUTTON_H = 20

-- Paint `b` through the skin's Button for its style and state, only when either moved: the library
-- records the call and follows the hover and the enabled state itself.
local function paintButton(b)
    local on = b:IsEnabled() and true or false
    local key = b.styleName .. (on and ":on" or ":off")
    if b.painted == key then return end
    b.painted = key
    NS.Skin.Button(b, { primary = b.style.primary, tokens = on and b.style.on or b.style.off })
end

-- A button's tooltip (b.tip = { title, line, ... }), shown above it, disabled or not.
local function buttonTip(b)
    local tip = b.tip
    if not (tip and GameTooltip) then return end
    if type(tip) ~= "table" then tip = { tostring(tip) } end
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    GameTooltip:SetText(tip[1], Style.Rgb("gtip.value"))
    Style.AddTipLines(GameTooltip, tip, 2, Style.Rgb("gtip.title"))
    GameTooltip:Show()
end

--- A flat button: a label, a style ("normal" | "primary" | "danger"), and a click that a disabled
--- button never runs. Its label is the skin's button text in the body face.
--- @param parent table
--- @param label string
--- @param onClick function
--- @param style string|nil
--- @return table
function Style.Button(parent, label, onClick, style)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetHeight(Style.BUTTON_H)
    b.styleName = BUTTON_STYLES[style] and style or "normal"
    b.style = BUTTON_STYLES[b.styleName]
    b.label = Style.PlainText(b, Style.FONT.TEXT, "CENTER")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.label:SetText(label)
    b.text = b.label   -- the label the skin's Button paints (its `btn.text`)
    b:SetScript("OnClick", function(self)
        if self:IsEnabled() then onClick(self) end
    end)
    b:SetScript("OnEnter", buttonTip)
    b:SetScript("OnLeave", function(self)
        if self.tip and GameTooltip then GameTooltip:Hide() end
    end)
    paintButton(b)
    return b
end

--- Give a Style.Button another style ("normal" | "primary" | "danger"), repainting it: the Race
--- window's picked length draws in the primary look (DPS Race's selected preset).
--- @param b table
--- @param style string
function Style.SetButtonStyle(b, style)
    local name = BUTTON_STYLES[style] and style or "normal"
    if b.styleName == name then return end
    b.styleName, b.style = name, BUTTON_STYLES[name]
    paintButton(b)
end

--- Enable or disable a Style.Button, repainting it.
function Style.SetEnabled(b, on)
    b:SetEnabled(on and true or false)
    paintButton(b)
end
