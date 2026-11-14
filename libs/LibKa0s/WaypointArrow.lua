-- LibKa0s-WaypointArrow-1.0 — a small movable arrow that points the way to a target, with the distance under it.
--
-- ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────
--
-- Skill Master drew its own waypoint arrow (owner feedback rounds 6 and 7) because the client's own
-- arrow follows a super-tracked pin and another addon answering TomTom's API hid it. Any Ka0s addon
-- that sets a waypoint wants the same frame, the same rotation math and the same care around secret
-- values, so it is written once here (the owner's decisions of 2026-11-14, Skill Master
-- docs/superpowers/plans/2026-11-14-feedback-round8.md, row L1). Skill Master is its one consumer;
-- the one-consumer promotion is a row in CLAUDE.md's register.
--
-- ── THE CONTRACT ─────────────────────────────────────────────────────────────────────────────
--
-- `WaypointArrow:New(d)` answers one instance. `d.addon` (or `d.mediaBase`) is required: it says
-- where the art sits. Everything else is optional: `name` (the frame's global name), `vendorPath`,
-- `parent`, `strata`, `skin` (a registered skin owner: the skin's colors and the text's role),
-- `point` (the saved position), `onMoved(point)` (a drag ended: persist the point), `canDrag()`,
-- `onClick(frame, button)`, `onEnter(frame)`, `onLeave(frame)`, `onArrive(target)`, `arrive`,
-- `near`, `far`, `format(yards)` and `debug(tag, msg)`. The instance owns no SavedVariables: the
-- host keeps its settings at its own paths (WaypointArrowSettings.lua's rows) and hands them over
-- with `Configure`. docs/api/WaypointArrow/version-1.1-docs.md is the full contract.
--
-- ── GEOMETRY ─────────────────────────────────────────────────────────────────────────────────
--
-- World coordinates (C_Map.GetWorldPosFromMapPos, UnitPosition): x points north, y points west.
-- GetPlayerFacing() is radians counter-clockwise from north. The bearing to the target, measured the
-- same way, is atan2(ty - py, tx - px): +y is west, so a target due west is +pi/2. The arrow's
-- rotation is bearing - facing, folded into -pi .. pi, and Texture:SetRotation turns
-- counter-clockwise for a positive angle, so the art, drawn pointing up (straight ahead), turns
-- towards the target. The ground look cannot turn (its art is tilted), so it picks one of 72
-- pre-drawn frames, one per 5 degrees, with SetTexCoord (`GroundFrame`, `GroundTexCoord`).
--
-- ── GUARDS ───────────────────────────────────────────────────────────────────────────────────
--
-- GetPlayerFacing can answer nil or a secret value (instances, some indoor places) and the
-- positions can be secret or unknown: every read is pcall'd and checked with issecretvalue, and a
-- value that is not a plain number is no value. With no facing the art hides and the distance
-- stays; with no distance (another continent, an instance) the target's label shows alone, dim.
-- Within `arrive` yards `onArrive(target)` is called and the target is cleared. The frame is never
-- secure and calls nothing protected, so it stays shown, and moves, in combat. Its OnUpdate is
-- armed only while it is shown.
--
-- ── DEPENDENCIES ─────────────────────────────────────────────────────────────────────────────
--
-- LibStub and LibKa0s-Core-1.0 minor 1 or newer, the gate every module here takes. LibKa0s-Skin-1.0
-- (the skin's colors, `Color`; the text's role, `For(owner).Text`) is resolved at the call that
-- needs it and optional: without it the colors are the custom ones and the text the game's font.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-WaypointArrow-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.WaypointArrow = MINOR

-- ── the looks ────────────────────────────────────────────────────────────────────────────────
--
-- Every file is tools/artwork/waypoint_arrow.py's, under media/waypoint/. A look is a BODY tinted
-- with the color and an OVERLAY drawn over it untinted (the highlights, the shading a multiply
-- cannot reach, the outline); raised adds a drop shadow that stays down and right while the arrow
-- turns; ground is an angle sheet.
lib.STYLES = { "flat", "ridge", "raised", "faceted", "ground" }
lib.DEFAULT_STYLE = "raised"
local LOOK = {
  flat    = { body = "arrow-fill", overlay = "flat-overlay" },
  ridge   = { body = "arrow-fill", overlay = "ridge-overlay" },
  raised  = { body = "arrow-fill", overlay = "raised-overlay", shadow = "raised-shadow" },
  faceted = { body = "arrow-fill", overlay = "faceted-overlay" },
  ground  = { body = "ground-body", overlay = "ground-overlay", sheet = true },
}
lib.MEDIA_DIR = "media\\waypoint"

lib.ART = 48                        -- the drawn size of the 48-unit art box, px, at scale 1
lib.SHADOW_BOX = 64                 -- raised's shadow canvas, units (the blur is never cut as it turns)
lib.SHADOW_OFFSET = { 1.5, -3 }     -- units, x right and y up: the mockup's translate(1.5 3)

--- The ground look's angle sheet, as the generator lays it out.
lib.GROUND = {
  frames = 72, step = 5, cols = 8, cellW = 64, cellH = 44, sheet = 512,
  box = { -1, 12, 49, 46.375 },     -- the units one cell covers, x0 y0 x1 y1 (y down)
}

-- ── the settings ─────────────────────────────────────────────────────────────────────────────

lib.SCALE_MIN, lib.SCALE_MAX = 0.5, 2
--- The settings a host seeds its own paths with. Colors are { r, g, b, a }; a keyed { r =, g =,
--- b = } is read as well. The far color is Ka0s Default's `text.accent`, the near its `sem.good`.
lib.DEFAULTS = {
  style = lib.DEFAULT_STYLE,
  useSkinColors = true,
  farColor = { 1, 0.82, 0, 1 },
  nearColor = { 0.35, 0.80, 0.45, 1 },
  scale = 1,
}
lib.SETTINGS = { "style", "useSkinColors", "farColor", "nearColor", "scale" }
lib.SKIN_FAR, lib.SKIN_NEAR = "text.accent", "sem.good"   -- the skin's tokens "Use the skin's colors" reads

-- ── the measures ─────────────────────────────────────────────────────────────────────────────

lib.ARRIVE, lib.NEAR, lib.FAR = 5, 30, 300   -- yards: arrival, the near color's edge, the far color's
lib.THROTTLE = 0.03                          -- seconds between two measures while shown
lib.SAMPLE_YARDS, lib.SAMPLE_ROTATION = 240, math.rad(35)   -- the sample: 35 degrees to the left
lib.STRATA = "MEDIUM"
lib.DEFAULT_POINT = { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 }
lib.STRINGS = { DISTANCE = "%d yd", SAMPLE = "Waypoint" }

local TAG = "ARROW"
local PAD_W, PAD_H, TEXT_GAP = 16, 22, 2
local DIM = 0.6                 -- the label's alpha with no distance and no skin

-- ── small readers ────────────────────────────────────────────────────────────────────────────

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end

local function plainNumber(v)
  return not isSecret(v) and type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function inList(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

--- r, g, b of a color in either shape ({ r, g, b, a } or { r =, g =, b = }), or nil.
local function rgbOf(c)
  if type(c) ~= "table" then return nil end
  local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
  if not (plainNumber(r) and plainNumber(g) and plainNumber(b)) then return nil end
  return r, g, b
end

local VALID = {
  style = function(v) return LOOK[v] ~= nil end,
  useSkinColors = function(v) return type(v) == "boolean" end,
  farColor = function(v) return rgbOf(v) ~= nil end,
  nearColor = function(v) return rgbOf(v) ~= nil end,
  scale = function(v) return plainNumber(v) and v >= lib.SCALE_MIN and v <= lib.SCALE_MAX end,
}

local function resolve(major) return LibStub and LibStub(major, true) end

-- ── the pure math ────────────────────────────────────────────────────────────────────────────

--- The arrow's rotation (radians, counter-clockwise, -pi .. pi) from the player at (px, py) facing
--- `facing` to the target at (tx, ty), world yards (x north, y west); nil when any input is not a
--- plain number.
function lib.Rotation(px, py, tx, ty, facing)
  if not (plainNumber(px) and plainNumber(py) and plainNumber(tx) and plainNumber(ty)
    and plainNumber(facing)) then return nil end
  local r = math.atan2(ty - py, tx - px) - facing
  -- One turn's range, so the same direction always reads the same angle.
  while r > math.pi do r = r - 2 * math.pi end
  while r <= -math.pi do r = r + 2 * math.pi end
  return r
end

--- Yards between two world points (x, y), or nil.
function lib.Distance(px, py, tx, ty)
  if not (plainNumber(px) and plainNumber(py) and plainNumber(tx) and plainNumber(ty)) then return nil end
  local dx, dy = tx - px, ty - py
  return math.sqrt(dx * dx + dy * dy)
end

--- The fade at `yards`: 0 at `near` or closer, 1 at `far` or more, linear between; 1 (the far color)
--- for a distance that is not a number.
function lib.Fade(yards, near, far)
  near, far = near or lib.NEAR, far or lib.FAR
  if not plainNumber(yards) then return 1 end
  if far <= near then return yards <= near and 0 or 1 end
  return math.max(0, math.min(1, (yards - near) / (far - near)))
end

--- The color at fade `t` between `nearC` (t = 0) and `farC` (t = 1), each in either shape:
--- r, g, b.
function lib.Mix(farC, nearC, t)
  local fr, fg, fb = rgbOf(farC)
  local nr, ng, nb = rgbOf(nearC)
  if not fr then fr, fg, fb = rgbOf(lib.DEFAULTS.farColor) end
  if not nr then nr, ng, nb = fr, fg, fb end
  return nr + (fr - nr) * t, ng + (fg - ng) * t, nb + (fb - nb) * t
end

--- The ground sheet's frame for `rotation` (radians, counter-clockwise): 0 .. 71, the nearest
--- 5 degrees; nil for a rotation that is not a number.
function lib.GroundFrame(rotation)
  if not plainNumber(rotation) then return nil end
  local G = lib.GROUND
  return math.floor(math.deg(rotation) / G.step + 0.5) % G.frames
end

--- The texcoords (left, right, top, bottom) of ground frame `k`.
function lib.GroundTexCoord(k)
  local G = lib.GROUND
  local col, row = k % G.cols, math.floor(k / G.cols)
  return col * G.cellW / G.sheet, (col + 1) * G.cellW / G.sheet,
    row * G.cellH / G.sheet, (row + 1) * G.cellH / G.sheet
end

-- ── the client reads ─────────────────────────────────────────────────────────────────────────

local function facing()
  if type(GetPlayerFacing) ~= "function" then return nil end
  local ok, f = pcall(GetPlayerFacing)
  if not ok or not plainNumber(f) then return nil end
  return f
end

local function xyOf(pos)
  if isSecret(pos) or type(pos) ~= "table" then return nil end
  if type(pos.GetXY) == "function" then
    local ok, x, y = pcall(pos.GetXY, pos)
    if ok then return x, y end
    return nil
  end
  return pos.x, pos.y
end

--- A map point's (0..1) world position: instance, x, y; or nil.
local function mapWorld(mapID, x, y)
  local api = C_Map
  if not (plainNumber(mapID) and plainNumber(x) and plainNumber(y)) then return nil end
  if type(api) ~= "table" or type(api.GetWorldPosFromMapPos) ~= "function"
    or type(CreateVector2D) ~= "function" then return nil end
  local ok, instance, pos = pcall(api.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
  if not ok or not plainNumber(instance) then return nil end
  local wx, wy = xyOf(pos)
  if not (plainNumber(wx) and plainNumber(wy)) then return nil end
  return instance, wx, wy
end

--- The player's world position: their best map, their place on it, that point in the world.
local function playerWorld()
  local api = C_Map
  if type(api) ~= "table" or type(api.GetBestMapForUnit) ~= "function"
    or type(api.GetPlayerMapPosition) ~= "function" then return nil end
  local okMap, mapID = pcall(api.GetBestMapForUnit, "player")
  if not okMap or not plainNumber(mapID) then return nil end
  local okPos, pos = pcall(api.GetPlayerMapPosition, mapID, "player")
  if not okPos then return nil end
  local x, y = xyOf(pos)
  return mapWorld(mapID, x, y)
end

lib.MapWorldPos, lib.PlayerWorldPos, lib.PlayerFacing = mapWorld, playerWorld, facing

-- ── the instance state ───────────────────────────────────────────────────────────────────────

local STATE = setmetatable({}, { __mode = "k" })

local function state(self)
  local S = STATE[self]
  if not S then error(MAJOR .. ": call this on an instance from WaypointArrow:New", 3) end
  return S
end

local function debugOut(S, msg)
  local sink = S.d.debug
  if type(sink) == "function" then pcall(sink, TAG, msg) end
end

--- A host callback, under pcall: a raise reaches the error handler and the arrow runs on.
local function call(S, fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if ok then return a end
  local handler = type(geterrorhandler) == "function" and geterrorhandler() or nil
  if handler then pcall(handler, a) end
  debugOut(S, "callback failed: " .. tostring(a))
  return nil
end

local function setting(S, key)
  local v = S.settings[key]
  if v ~= nil and VALID[key](v) then return v end
  return lib.DEFAULTS[key]
end

local function skinOwner(S)
  local Skin = resolve("LibKa0s-Skin-1.0")
  local owner = S.d.skin
  if not (Skin and type(owner) == "string" and type(Skin.Color) == "function") then return nil end
  return Skin, owner
end

local function skinColor(S, token)
  local Skin, owner = skinOwner(S)
  if not Skin then return nil end
  local r, g, b = Skin:Color(owner, token)
  if not (plainNumber(r) and plainNumber(g) and plainNumber(b)) then return nil end
  return { r, g, b }
end

--- The far and near colors in use: the skin's (`SKIN_FAR`, `SKIN_NEAR`) while "Use the skin's
--- colors" is on and a skin answers, else the custom pair.
local function colors(S)
  if setting(S, "useSkinColors") then
    local far, near = skinColor(S, lib.SKIN_FAR), skinColor(S, lib.SKIN_NEAR)
    if far then return far, near or far end
  end
  return setting(S, "farColor"), setting(S, "nearColor")
end

local function mediaBase(S)
  local d = S.d
  if type(d.mediaBase) == "string" and d.mediaBase ~= "" then
    return (d.mediaBase:gsub("\\$", "")) .. "\\"
  end
  return "Interface\\AddOns\\" .. d.addon .. "\\" .. (d.vendorPath or "libs\\LibKa0s") .. "\\" .. lib.MEDIA_DIR .. "\\"
end

-- ── the frame ────────────────────────────────────────────────────────────────────────────────

local function savePoint(S)
  local point, _, relPoint, x, y = S.frame:GetPoint(1)
  if type(point) ~= "string" then return end
  local p = { point = point, relPoint = type(relPoint) == "string" and relPoint or point,
    x = plainNumber(x) and x or 0, y = plainNumber(y) and y or 0 }
  S.point = p
  call(S, S.d.onMoved, { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y })
end

local ANCHOR = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

--- A saved point in either shape ({ point, relPoint, x, y } keyed, or Callout's { p, rp, x, y }), or nil.
local function pointOf(p)
  if type(p) ~= "table" then return nil end
  local point, relPoint, x, y = p.point or p[1], p.relPoint or p[2], p.x or p[3], p.y or p[4]
  if not ANCHOR[point] then return nil end
  if not ANCHOR[relPoint] then relPoint = point end
  return { point = point, relPoint = relPoint, x = plainNumber(x) and x or 0, y = plainNumber(y) and y or 0 }
end

local function applyPoint(S)
  local p = pointOf(S.point) or lib.DEFAULT_POINT
  S.frame:ClearAllPoints()
  S.frame:SetPoint(p.point, S.d.parent or UIParent, p.relPoint, p.x, p.y)
end

local function onDragStart(S)
  if S.d.canDrag ~= nil and not call(S, S.d.canDrag) then return end
  S.frame:StartMoving()
  S.moving = true
end

local function onDragStop(S)
  if not S.moving then return end
  S.moving = nil
  S.frame:StopMovingOrSizing()
  savePoint(S)
end

local onUpdate   -- forward: armed by present, disarmed by takeDown

local function texture(parent, sublevel)
  local t = parent:CreateTexture(nil, "ARTWORK", nil, sublevel)
  t:Hide()
  return t
end

local function build(S)
  if S.frame then return S.frame end
  local f = CreateFrame("Frame", S.d.name, S.d.parent or UIParent)
  S.frame = f
  f:Hide()
  f:SetFrameStrata(type(S.d.strata) == "string" and S.d.strata or lib.STRATA)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetSize(lib.ART + PAD_W, lib.ART + PAD_H)
  f:SetScript("OnDragStart", function() onDragStart(S) end)
  f:SetScript("OnDragStop", function() onDragStop(S) end)
  f:SetScript("OnMouseUp", function(_, button) call(S, S.d.onClick, f, button) end)
  f:SetScript("OnEnter", function() call(S, S.d.onEnter, f) end)
  f:SetScript("OnLeave", function() call(S, S.d.onLeave, f) end)
  -- The art box: the 48-unit box every look is drawn in, at the top of the frame.
  local box = CreateFrame("Frame", nil, f)
  box:SetSize(lib.ART, lib.ART)
  box:SetPoint("TOP", f, "TOP", 0, 0)
  S.box = box
  S.shadow, S.body, S.overlay = texture(box, 0), texture(box, 1), texture(box, 2)
  S.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  S.text:SetPoint("TOP", box, "BOTTOM", 0, -TEXT_GAP)
  S.textRole = nil
  return f
end

--- Lay the current look onto the three textures: files, sizes, anchors, and the coords a turn or a
--- frame starts from.
local function applyStyle(S)
  local style = setting(S, "style")
  local look = LOOK[style]
  local base, k = mediaBase(S), lib.ART / 48
  S.body:SetTexture(base .. look.body)
  S.overlay:SetTexture(base .. look.overlay)
  for _, t in ipairs({ S.body, S.overlay }) do
    t:ClearAllPoints()
    t:SetRotation(0)
    t:SetTexCoord(0, 1, 0, 1)
    if look.sheet then
      local G = lib.GROUND
      local b = G.box
      t:SetSize((b[3] - b[1]) * k, (b[4] - b[2]) * k)
      t:SetPoint("CENTER", S.box, "CENTER", ((b[1] + b[3]) / 2 - 24) * k, -((b[2] + b[4]) / 2 - 24) * k)
    else
      t:SetSize(lib.ART, lib.ART)
      t:SetPoint("CENTER", S.box, "CENTER", 0, 0)
    end
  end
  S.shadow:ClearAllPoints()
  if look.shadow then
    S.shadow:SetTexture(base .. look.shadow)
    S.shadow:SetSize(lib.SHADOW_BOX * k, lib.SHADOW_BOX * k)
    S.shadow:SetPoint("CENTER", S.box, "CENTER", lib.SHADOW_OFFSET[1] * k, lib.SHADOW_OFFSET[2] * k)
  end
  S.style = style
end

local function applyScale(S)
  S.frame:SetScale(setting(S, "scale"))
end

-- ── drawing ──────────────────────────────────────────────────────────────────────────────────

local function hideArt(S)
  S.body:Hide()
  S.overlay:Hide()
  S.shadow:Hide()
end

--- Turn the art to `rotation`: SetRotation for the rotated looks, a sheet frame for the ground.
local function turn(S, rotation)
  local look = LOOK[S.style]
  if look.sheet then
    local k = lib.GroundFrame(rotation)
    local l, r, t, b = lib.GroundTexCoord(k)
    S.body:SetTexCoord(l, r, t, b)
    S.overlay:SetTexCoord(l, r, t, b)
    S.frameIndex = k
    return
  end
  S.body:SetRotation(rotation)
  S.overlay:SetRotation(rotation)
  if look.shadow then S.shadow:SetRotation(rotation) end
  S.frameIndex = nil
end

local function paintArt(S, rotation, yards)
  if rotation == nil then
    S.rotation = nil
    return hideArt(S)
  end
  S.body:Show()
  S.overlay:Show()
  S.shadow:SetShown(LOOK[S.style].shadow ~= nil)
  turn(S, rotation)
  local far, near = colors(S)
  local r, g, b = lib.Mix(far, near, lib.Fade(yards, S.near, S.far))
  S.body:SetVertexColor(r, g, b, 1)
  S.rotation, S.color = rotation, { r, g, b }
end

--- The text's role, painted only when it changes (a skin records each call, and this runs every
--- tick): "body" with a distance, "muted" for the label alone.
local function paintRole(S, role)
  if S.textRole == role then return end
  S.textRole = role
  local Skin, owner = skinOwner(S)
  local facade = Skin and type(Skin.For) == "function" and Skin:For(owner) or nil
  if facade and type(facade.Text) == "function" then
    facade.Text(S.text, role)
    S.text:SetAlpha(1)
  else
    S.text:SetAlpha(role == "muted" and DIM or 1)
  end
end

local function formatYards(S, yards)
  local text = call(S, S.d.format, yards)
  if type(text) == "string" then return text end
  return lib.STRINGS.DISTANCE:format(math.floor(yards + 0.5))
end

local function paintText(S, yards, label)
  paintRole(S, yards and "body" or "muted")
  S.text:SetText(yards and formatYards(S, yards) or (type(label) == "string" and label or ""))
end

-- ── the measure ──────────────────────────────────────────────────────────────────────────────

--- The target's world point (static, so measured once per target).
local function targetWorld(t)
  if t.world then return t.world end
  if plainNumber(t.instance) and plainNumber(t.wx) and plainNumber(t.wy) then
    t.world = { t.instance, t.wx, t.wy }
  else
    local instance, x, y = mapWorld(t.mapID, t.x, t.y)
    if instance ~= nil then t.world = { instance, x, y } end
  end
  return t.world
end

--- yards and rotation to a target, each nil when unknown.
local function measureTarget(t)
  local w = targetWorld(t)
  local instance, px, py = playerWorld()
  if not (w and instance ~= nil and instance == w[1]) then return nil, nil end
  local yards = lib.Distance(px, py, w[2], w[3])
  return yards, yards and lib.Rotation(px, py, w[2], w[3], facing()) or nil
end

local function measure(S)
  if S.sample then return lib.SAMPLE_YARDS, lib.SAMPLE_ROTATION, S.sample.label end
  local t = S.target
  if not t then return nil end
  if t.provider then
    local ok, yards, rotation = pcall(t.provider)
    if not ok then return nil, nil, t.label end
    return plainNumber(yards) and yards or nil, plainNumber(rotation) and rotation or nil, t.label
  end
  local yards, rotation = measureTarget(t)
  return yards, rotation, t.label
end

local takeDown   -- forward: the arrival clears the target

local function arrived(S, yards)
  local arrive = S.d.arrive
  if arrive == false or S.sample or not yards then return false end
  return yards <= (plainNumber(arrive) and arrive or lib.ARRIVE)
end

--- One measure: the player's place and facing against the target, then the art and the text.
local function update(S)
  if not S.frame then return end
  local yards, rotation, label = measure(S)
  if not (S.sample or S.target) then return takeDown(S) end
  if arrived(S, yards) then
    local t = S.target
    S.target = nil
    takeDown(S)
    call(S, S.d.onArrive, t and t.spec)
    return
  end
  S.yards = yards
  paintArt(S, rotation, yards)
  paintText(S, yards, label)
end

onUpdate = function(S, elapsed)
  S.elapsed = S.elapsed + (elapsed or 0)
  if S.elapsed < lib.THROTTLE then return end
  S.elapsed = 0
  update(S)
end

local function present(S)
  if S.suspended then return end
  build(S)
  applyStyle(S)
  applyScale(S)
  applyPoint(S)
  S.frame:Show()
  S.elapsed = 0
  S.frame:SetScript("OnUpdate", function(_, elapsed) onUpdate(S, elapsed) end)
  update(S)
end

-- The frame down and its OnUpdate disarmed, explicitly: the one place it is disarmed. No OnHide
-- disarms it: the client fires OnHide on a shown child when its parent hides (Alt-Z, a cinematic)
-- and nothing re-arms it on the way back, while a hidden frame runs no OnUpdate anyway.
takeDown = function(S)
  if not S.frame then return end
  if S.moving then onDragStop(S) end
  S.frame:SetScript("OnUpdate", nil)
  S.frame:Hide()
end

-- ── the methods ──────────────────────────────────────────────────────────────────────────────

local METHODS = {}

--- Point at `spec`: `{ mapID, x, y }` (a map and a point on it, 0..1, as C_Map takes them) or
--- `{ instance, wx, wy }` (world yards, x north and y west), with an optional `label` (shown alone,
--- dim, while no distance can be measured). A shown arrow is retargeted. Answers false (and does
--- nothing) for a spec with neither, or while suspended.
function METHODS:SetTarget(spec)
  local S = state(self)
  if type(spec) ~= "table" then return false end
  local byMap = plainNumber(spec.mapID) and plainNumber(spec.x) and plainNumber(spec.y)
  local byWorld = plainNumber(spec.instance) and plainNumber(spec.wx) and plainNumber(spec.wy)
  if not (byMap or byWorld) then return false end
  S.target = { mapID = spec.mapID, x = spec.x, y = spec.y, instance = spec.instance, wx = spec.wx,
    wy = spec.wy, label = spec.label, spec = spec }
  if S.suspended then return false end
  if not S.sample then present(S) end
  return true
end

--- Point by `provider()`, which answers `yards, rotation` (rotation in radians, counter-clockwise
--- from straight ahead; either may be nil), read each measure under pcall. For a host that measures
--- its own way (a unit, a quest, a corpse). `label` as SetTarget's.
function METHODS:SetProvider(provider, label)
  local S = state(self)
  if type(provider) ~= "function" then return false end
  S.target = { provider = provider, label = label, spec = { provider = provider, label = label } }
  if S.suspended then return false end
  if not S.sample then present(S) end
  return true
end

--- Forget the target and hide (the sample, if shown, stays until HideSample).
function METHODS:Clear()
  local S = state(self)
  S.target = nil
  if S.sample then return end
  takeDown(S)
end

--- The spec handed to SetTarget or SetProvider, or nil.
function METHODS:Target()
  local t = state(self).target
  return t and t.spec or nil
end

--- Test mode (preview-mode): the arrow at the sample distance and angle, `label` under it while it
--- cannot measure. A real target set before or during it waits under the sample.
function METHODS:ShowSample(label)
  local S = state(self)
  if S.suspended then return false end
  S.sample = { label = type(label) == "string" and label or lib.STRINGS.SAMPLE }
  present(S)
  return true
end

--- Test mode ended: the sample goes, and a real target is pointed at again.
function METHODS:HideSample()
  local S = state(self)
  if not S.sample then return end
  S.sample = nil
  if S.target then return present(S) end
  takeDown(S)
end

function METHODS:SampleShown() return state(self).sample ~= nil end

--- Merge settings in: any of `style`, `useSkinColors`, `farColor`, `nearColor`, `scale`. A value
--- that is not valid reads as the default (never stored). A shown arrow takes them at once.
function METHODS:Configure(t)
  local S = state(self)
  if type(t) ~= "table" then return end
  for _, key in ipairs(lib.SETTINGS) do
    if t[key] ~= nil then S.settings[key] = t[key] end
  end
  self:Apply()
end

--- Configure from the host's own settings: `get(path)` for each key `paths` names
--- (`{ style = "waypoints.arrowStyle", ... }`); a key with no path is left as it is.
function METHODS:ConfigureFrom(get, paths)
  if type(get) ~= "function" or type(paths) ~= "table" then return end
  local t = {}
  for _, key in ipairs(lib.SETTINGS) do
    if type(paths[key]) == "string" then t[key] = get(paths[key]) end
  end
  self:Configure(t)
end

--- One setting as the arrow reads it: the configured value, else the default.
function METHODS:Get(key)
  local S = state(self)
  if not VALID[key] then return nil end
  return setting(S, key)
end

--- The far and near colors the arrow draws with now (after "Use the skin's colors"): two
--- { r, g, b } tables.
function METHODS:Colors()
  local far, near = colors(state(self))
  local fr, fg, fb = rgbOf(far)
  local nr, ng, nb = rgbOf(near)
  return { fr, fg, fb }, { nr, ng, nb }
end

--- Re-read every setting onto a built frame (after a skin change, or the host's own write).
function METHODS:Apply()
  local S = state(self)
  if not S.frame then return end
  applyStyle(S)
  applyScale(S)
  if S.frame:IsShown() then update(S) end
end

--- Move the frame to a saved point (`{ point, relPoint, x, y }`, keyed or positional); nil puts it
--- back at `DEFAULT_POINT`. Not handed to onMoved: the host already holds it.
function METHODS:SetPosition(point)
  local S = state(self)
  S.point = pointOf(point)
  if S.frame then applyPoint(S) end
end

--- The point the frame sits at now: a fresh `{ point, relPoint, x, y }`.
function METHODS:GetPosition()
  local p = pointOf(state(self).point) or lib.DEFAULT_POINT
  return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
end

--- Back to `DEFAULT_POINT`, and onMoved(nil) so the host forgets its saved point.
function METHODS:ResetPosition()
  local S = state(self)
  S.point = nil
  if S.frame then applyPoint(S) end
  call(S, S.d.onMoved, nil)
end

--- One measure now (a shown arrow measures on its own every THROTTLE seconds).
function METHODS:Update() update(state(self)) end

function METHODS:IsShown()
  local S = state(self)
  return S.frame ~= nil and S.frame:IsShown() == true
end

--- The stand-down: the arrow and the sample come down, the target is forgotten, and SetTarget,
--- SetProvider and ShowSample answer false until Resume.
function METHODS:Suspend()
  local S = state(self)
  S.suspended, S.sample, S.target = true, nil, nil
  takeDown(S)
end

function METHODS:Resume() state(self).suspended = false end

function METHODS:Suspended() return state(self).suspended == true end

--- The frame, built on first use.
function METHODS:Frame() return build(state(self)) end

--- The instance's state, for a host's diagnostics report and its suites.
function METHODS:Stats()
  local S = state(self)
  return {
    built = S.frame ~= nil, shown = S.frame ~= nil and S.frame:IsShown() == true,
    style = setting(S, "style"), scale = setting(S, "scale"),
    rotation = S.rotation, frameIndex = S.frameIndex, yards = S.yards,
    color = S.color and { S.color[1], S.color[2], S.color[3] } or nil,
    sample = S.sample ~= nil, target = S.target ~= nil, suspended = S.suspended == true,
    armed = S.frame ~= nil and S.frame:GetScript("OnUpdate") ~= nil,
  }
end

--- A new arrow. `d.addon` (or `d.mediaBase`) is required; every other field is optional (see the
--- API document).
function lib:New(d)   -- luacheck: ignore 212/self
  if type(d) ~= "table" or not ((type(d.addon) == "string" and d.addon ~= "")
    or (type(d.mediaBase) == "string" and d.mediaBase ~= "")) then
    error(MAJOR .. ": New(d): d.addon (or d.mediaBase), where the art sits, is required", 2)
  end
  local inst = {}
  for name, fn in pairs(METHODS) do inst[name] = fn end
  STATE[inst] = { d = d, settings = {}, suspended = false, elapsed = 0, point = pointOf(d.point),
    near = plainNumber(d.near) and d.near or lib.NEAR, far = plainNumber(d.far) and d.far or lib.FAR }
  return inst
end

--- Whether `style` is one of STYLES.
function lib.IsStyle(style) return inList(lib.STYLES, style) end

-- The method table every New copies, for this major's paired file and nobody else.
lib.__methods = METHODS
lib.__valid = VALID
