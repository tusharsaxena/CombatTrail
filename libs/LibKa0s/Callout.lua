-- LibKa0s-Callout-1.0 — the big center-screen call-out: countdown numbers, stock and custom texts.
--
-- ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────
--
-- Combat Trail's race countdown drew its numbers off a chain of timers that drifted against the race
-- clock it was counting down to, and every other Ka0s addon that wants a "3, 2, 1, GO" or a big
-- "MOVE" would write the same frame, font, animation and voice again. This file is that call-out,
-- once (the owner's decisions of 2026-11-13, docs/superpowers/plans/2026-11-13-callout.md;
-- adoption issue LibKa0s#85).
--
-- ── THE CONTRACT ─────────────────────────────────────────────────────────────────────────────
--
-- `Callout:New(d)` answers one instance. `d.db` (required) is the host's profile table the instance
-- reads and writes its settings into, or a getter answering it (so a profile switch is followed);
-- `Callout.DEFAULTS` is the table a host seeds it from. Everything else in `d` is optional: `name`
-- (the frame's global name), `addon` and `vendorPath` (where the payload sits, for the voice packs
-- and the bundled fonts), `soundsBase` (the folder holding the packs, overriding the one `addon`
-- implies), `skin` (a registered skin owner, for the "Skin font" choice and the drag strip),
-- `label` (the drag strip's text) and `debug` (`debug(tag, msg)`). docs/api/Callout/version-1.1-docs.md
-- is the full contract.
--
-- ── TIMING ───────────────────────────────────────────────────────────────────────────────────
--
-- `Countdown{ endsAt, from, finish, onTick, onDone }`. The number shown is ALWAYS
-- `math.ceil(endsAt - GetTime())`, read in an OnUpdate while the countdown runs, so it flips on the
-- frame the true remaining time crosses the integer, and a host drawing its own clock off the same
-- `endsAt` can never disagree with it. There is no timer chain to drift. The OnUpdate is armed only
-- while a countdown runs or a call-out waits out its hold, on a clock frame of its own with no
-- parent (so hiding the UI does not stop a countdown's onDone), and is cleared the moment neither
-- is true. Animations are AnimationGroups, which the client runs; no Lua runs per frame for them.
--
-- ── SOUND ────────────────────────────────────────────────────────────────────────────────────
--
-- The `voice` setting is a pack key of `Callout.PACKS` (a folder under media/sounds/callout/),
-- "tts" (the client's text to speech, C_VoiceChat.SpeakText with the player's chosen voice from
-- C_VoiceChat.GetTtsVoices) or "off". Both calls are presence-checked at call time, and their
-- signatures are the same on Retail and WoW Forever (Blizzard's generated API documentation, live and
-- forever branches, read 2026-11-13: SpeakText(voiceID, text, rate, volume, overlap)), so nothing
-- here is version-variant and nothing routes through LibKa0s-Compat-1.0. A pack line the consumer
-- pruned away (PlaySoundFile answers false) is silence, reported once per file through `d.debug`.
--
-- ── DEPENDENCIES ─────────────────────────────────────────────────────────────────────────────
--
-- LibStub and LibKa0s-Core-1.0 minor 1 or newer, the gate every module here takes so a partial
-- payload is every module absent. LibKa0s-Media-1.0 (the bundled fonts), LibKa0s-Skin-1.0 (the skin's
-- font), LibKa0s-Widgets-1.0 (the drag strip) and LibSharedMedia-3.0 are each resolved at the call
-- that needs them and optional. No SavedVariables of its own, no secret value passes through it,
-- and nothing here is a protected call, so it works in combat.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Callout-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.Callout = MINOR

-- ── the voice packs ──────────────────────────────────────────────────────────────────────────
--
-- One row per bundled pack: the `voice` setting's key, the folder under media/sounds/callout/ its
-- lines sit in, and the name a settings row shows. Order is the settings row's order. A new pack is
-- a row here and a folder of LINES; nothing else names a pack.
lib.PACKS = {
  { key = "female", folder = "female-kathleen", name = "Female (Kathleen)" },
  { key = "male",   folder = "male-joe",        name = "Male (Joe)" },
}
lib.TTS, lib.OFF = "tts", "off"           -- the two `voice` values that are not a pack

local PACK = {}
for _, p in ipairs(lib.PACKS) do PACK[p.key] = p end

-- ── the texts ────────────────────────────────────────────────────────────────────────────────
--
-- The kinds, each with a default color the player can change.
lib.KINDS = { "number", "info", "go", "stop", "warn", "error" }
local KIND = {}
for _, k in ipairs(lib.KINDS) do KIND[k] = true end

-- The stock call-outs: key -> the text shown, its kind and what a voice says. Each key's pack line
-- is its lower-case name (`NEW_BEST` -> `new_best.ogg`); the numbers 1 to 20 are `1.ogg` .. `20.ogg`.
lib.STOCK = {
  READY     = { text = "READY",     kind = "info",  say = "Ready" },
  GO        = { text = "GO!",       kind = "go",    say = "Go" },
  START     = { text = "START",     kind = "go",    say = "Start" },
  STOP      = { text = "STOP",      kind = "stop",  say = "Stop" },
  WARNING   = { text = "WARNING",   kind = "warn",  say = "Warning" },
  ERROR     = { text = "ERROR",     kind = "error", say = "Error" },
  DONE      = { text = "DONE",      kind = "info",  say = "Done" },
  FINISH    = { text = "FINISH",    kind = "go",    say = "Finish" },
  NEW_BEST  = { text = "NEW BEST",  kind = "go",    say = "New best" },
  PAUSE     = { text = "PAUSED",    kind = "warn",  say = "Paused" },
  RESUME    = { text = "RESUME",    kind = "info",  say = "Resume" },
  CANCELED = { text = "CANCELED", kind = "stop",  say = "Canceled" },
  PULL      = { text = "PULL",      kind = "warn",  say = "Pull" },
  INTERRUPT = { text = "INTERRUPT", kind = "warn",  say = "Interrupt" },
  MOVE      = { text = "MOVE",      kind = "warn",  say = "Move" },
  DEFENSIVE = { text = "DEFENSIVE", kind = "warn",  say = "Defensive" },
  REBUFF    = { text = "REBUFF",    kind = "info",  say = "Rebuff" },
  EXPIRING  = { text = "EXPIRING",  kind = "warn",  say = "Expiring" },
  UPGRADE   = { text = "UPGRADE",   kind = "go",    say = "Upgrade" },
  TIME_UP   = { text = "TIME UP",   kind = "stop",  say = "Time up" },
  VICTORY   = { text = "VICTORY",   kind = "go",    say = "Victory" },
  FAILED    = { text = "FAILED",    kind = "error", say = "Failed" },
  LAST_TEN  = { text = "LAST TEN",  kind = "warn",  say = "Last ten seconds" },
}
lib.STOCK_ORDER = { "READY", "GO", "START", "STOP", "WARNING", "ERROR", "DONE", "FINISH", "NEW_BEST",
  "PAUSE", "RESUME", "CANCELED", "PULL", "INTERRUPT", "MOVE", "DEFENSIVE", "REBUFF", "EXPIRING",
  "UPGRADE", "TIME_UP", "VICTORY", "FAILED", "LAST_TEN" }

lib.MAX_FROM = 20                         -- the longest countdown, and the highest number with a line

-- Every line a pack carries, file names without the extension: the stock keys, then 1 .. 20.
lib.LINES = {}
for _, key in ipairs(lib.STOCK_ORDER) do lib.LINES[#lib.LINES + 1] = key:lower() end
for n = 1, lib.MAX_FROM do lib.LINES[#lib.LINES + 1] = tostring(n) end
lib.SOUND_EXT = ".ogg"

-- ── the choices ──────────────────────────────────────────────────────────────────────────────

lib.FONT_SKIN, lib.FONT_GAME = "Skin font", "Game default"   -- the two font values that are no face
lib.FONT_DEFAULT = "Ka0s Oxanium Bold"    -- a LibKa0s-Media-1.0 face, also its LSM name
lib.OUTLINES = { "NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROME" }
lib.GLOWS = { "off", "soft", "strong" }
lib.ANIMS = { "slam", "pulse", "glow", "blink", "shake", "none" }
lib.CHANNELS = { "Master", "SFX", "Dialog" }
lib.SIZE_MIN, lib.SIZE_MAX = 32, 200
-- frame-layering-§1's T5 non-interactive screen alert (`SCREEN_ALERT`): FULLSCREEN, mouse disabled
-- while locked. HIGH is the interactive toast's tier, and the Blizzard Settings panel (HIGH, toplevel)
-- would cover a call-out unlocked or tested from it.
lib.STRATA = "FULLSCREEN"
lib.WIDTH = 900                           -- the frame's width; its height follows the size

--- The settings a host seeds its profile with (AceDB copies a defaults table, so pass this one; a
--- host copying by hand copies `point` and `colors` too, never shares them).
lib.DEFAULTS = {
  font = lib.FONT_DEFAULT, size = 96, outline = "THICKOUTLINE",
  shadow = true, shadowX = 2, shadowY = -2,
  colors = {
    number = { 1, 1, 1 },        info = { 0.35, 0.75, 1 },  go = { 0.3, 1, 0.45 },
    stop   = { 1, 0.35, 0.3 },   warn = { 1, 0.78, 0.2 },   error = { 1, 0.2, 0.25 },
  },
  glow = "soft", anim = "slam", hold = 1.5,
  point = { "CENTER", "CENTER", 0, 180 },
  voice = "female", channel = "Master", speakFrom = 5,
  ttsVoice = false, ttsRate = 0, ttsVolume = 100,   -- false: the client's first voice
  texts = {},                                        -- key -> the player's own text for a stock key
  muted = {},                                        -- key -> true: that stock key shows unspoken
}

local TAG = "CALLOUT"
local GLOW_ALPHA = { off = 0, soft = 0.35, strong = 0.7 }
local GLOW_SCALE = { off = 1, soft = 1.04, strong = 1.1 }
local HEIGHT_FACTOR = 1.5                 -- the frame's height over the font size
local FADE = 0.25                         -- seconds a call-out takes to fade at the end of its hold
local HANDLE_GAP = 2
local HANDLE_LEVEL = 10                   -- the drag strip's level over the frame's

-- ── small readers ────────────────────────────────────────────────────────────────────────────

local function inList(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function between(lo, hi) return function(v) return finite(v) and v >= lo and v <= hi end end

local function oneOf(list) return function(v) return inList(list, v) end end

local function nonEmpty(v) return type(v) == "string" and v ~= "" end

-- The nine region points SetPoint takes. A stored anchor outside them would raise in SetPoint.
local ANCHOR = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

local function validPoint(pt)
  return type(pt) == "table" and ANCHOR[pt[1]] == true and (pt[2] == nil or ANCHOR[pt[2]] == true)
    and (pt[3] == nil or finite(pt[3])) and (pt[4] == nil or finite(pt[4]))
end

local function validVoice(v) return PACK[v] ~= nil or v == lib.TTS or v == lib.OFF end

local function validTexts(v)
  if type(v) ~= "table" then return false end
  for k, s in pairs(v) do
    if not (lib.STOCK[k] and type(s) == "string") then return false end
  end
  return true
end

local function validMuted(v)
  if type(v) ~= "table" then return false end
  for k, m in pairs(v) do
    if not (lib.STOCK[k] and type(m) == "boolean") then return false end
  end
  return true
end

-- What each setting may hold. A stored value that fails is read as the default (never written).
local VALID = {
  font = nonEmpty, size = between(lib.SIZE_MIN, lib.SIZE_MAX), outline = oneOf(lib.OUTLINES),
  shadow = function(v) return type(v) == "boolean" end,
  shadowX = between(-20, 20), shadowY = between(-20, 20),
  glow = oneOf(lib.GLOWS), anim = oneOf(lib.ANIMS), hold = between(0.2, 10),
  point = validPoint, voice = validVoice, channel = oneOf(lib.CHANNELS),
  speakFrom = function(v) return between(1, lib.MAX_FROM)(v) and v == math.floor(v) end,
  ttsVoice = function(v) return v == false or finite(v) end,
  ttsRate = between(-10, 10), ttsVolume = between(0, 100),
  texts = validTexts, muted = validMuted,
}
lib.SETTINGS = {}
for key in pairs(VALID) do lib.SETTINGS[#lib.SETTINGS + 1] = key end
table.sort(lib.SETTINGS)

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

local function validColor(c)
  return type(c) == "table" and finite(c[1]) and finite(c[2]) and finite(c[3])
end

local function debugOut(S, msg)
  local sink = S.d.debug
  if type(sink) == "function" then pcall(sink, TAG, msg) end
end

--- Report `what` through d.debug the first time only.
local function logOnce(S, what)
  if S.logged[what] then return end
  S.logged[what] = true
  debugOut(S, what)
end

--- A host callback, under pcall: a raise reaches the error handler and the call-out runs on.
local function call(S, fn, ...)
  if type(fn) ~= "function" then return end
  local ok, err = pcall(fn, ...)
  if ok then return end
  local handler = type(geterrorhandler) == "function" and geterrorhandler() or nil
  if handler then pcall(handler, err) end
  debugOut(S, "callback failed: " .. tostring(err))
end

-- ── the settings ─────────────────────────────────────────────────────────────────────────────

local function store(S)
  local t = S.d.db
  if type(t) == "function" then t = t() end
  return type(t) == "table" and t or nil
end

local function get(S, key)
  local t = store(S)
  local v = t and t[key]
  if v ~= nil and VALID[key](v) then return v end
  return lib.DEFAULTS[key]
end

--- The pack keys this instance offers, as a set: the packs whose folder `d.packs` names (the host's
--- `LibKa0s sounds:` line, each `callout/<folder>` or the bare folder), or every pack when `d.packs`
--- is not a table. Read once per instance: the shipped payload does not change in a session.
local function offered(S)
  if S.offered then return S.offered end
  local out, want = {}, S.d.packs
  local ships
  if type(want) == "table" then
    ships = {}
    for _, f in ipairs(want) do
      if type(f) == "string" then ships[(f:gsub("^callout/", ""))] = true end
    end
  end
  for _, p in ipairs(lib.PACKS) do
    if not ships or ships[p.folder] then out[p.key] = true end
  end
  S.offered = out
  return out
end

--- The voice as the instance speaks it. A stored (or default) pack the host does not ship reads as
--- the first pack it does ship, else off: an undeclared pack is never played.
local function voiceOf(S)
  local v = get(S, "voice")
  if not PACK[v] or offered(S)[v] then return v end
  for _, p in ipairs(lib.PACKS) do
    if offered(S)[p.key] then return p.key end
  end
  return lib.OFF
end

local function colorOf(S, kind)
  local t = store(S)
  local c = t and type(t.colors) == "table" and t.colors[kind]
  if validColor(c) then return c[1], c[2], c[3] end
  c = lib.DEFAULTS.colors[kind] or lib.DEFAULTS.colors.info
  return c[1], c[2], c[3]
end

-- ── the font ─────────────────────────────────────────────────────────────────────────────────

local function resolve(major) return LibStub and LibStub(major, true) end

local function gameFont()
  if type(STANDARD_TEXT_FONT) == "string" then return STANDARD_TEXT_FONT end
  return "Fonts\\FRIZQT__.TTF"
end

local function skinFont(S)
  local Skin = resolve("LibKa0s-Skin-1.0")
  local owner = S.d.skin
  if not (Skin and type(owner) == "string" and type(Skin.IsOwner) == "function" and type(Skin.For) == "function"
    and Skin:IsOwner(owner)) then
    return nil
  end
  local facade = Skin:For(owner)
  return facade and type(facade.GetFont) == "function" and facade.GetFont() or nil
end

--- A face by name: LibSharedMedia's, else LibKa0s-Media-1.0's bundled file of that name.
local function namedFont(S, name)
  local LSM = resolve("LibSharedMedia-3.0")
  local path = LSM and type(LSM.Fetch) == "function" and LSM:Fetch("font", name, true)
  if type(path) == "string" then return path end
  local Media = resolve("LibKa0s-Media-1.0")
  if Media and type(Media.Font) == "function" then return Media.Font(S.d.addon, name, S.d.vendorPath) end
  return nil
end

local function fontPath(S)
  local name = get(S, "font")
  if name == lib.FONT_GAME then return gameFont() end
  if name == lib.FONT_SKIN then return skinFont(S) or gameFont() end
  return namedFont(S, name) or namedFont(S, lib.FONT_DEFAULT) or gameFont()
end

local function fontFlags(S)
  local o = get(S, "outline")
  return o == "NONE" and "" or o
end

--- SetFont answers false for a face the client cannot load; the game's face stands in.
local function setFont(fs, path, size, flags)
  if fs:SetFont(path, size, flags) == false then fs:SetFont(gameFont(), size, flags) end
end

-- ── the animations ───────────────────────────────────────────────────────────────────────────
--
-- Each is a list of steps on the content frame (or, for "glow", on the halo behind the text). Built once
-- per instance, the first time it plays.
local ANIM_STEPS = {
  slam = {
    { type = "Scale", from = 2.2, to = 1, dur = 0.18, order = 1, smooth = "OUT" },
    { type = "Alpha", from = 0, to = 1, dur = 0.12, order = 1 },
  },
  pulse = {
    { type = "Scale", from = 1, to = 1.18, dur = 0.12, order = 1, smooth = "OUT" },
    { type = "Scale", from = 1.18, to = 1, dur = 0.18, order = 2, smooth = "IN" },
  },
  glow = {
    { type = "Alpha", from = 1, to = 0, dur = 0.6, order = 1, smooth = "OUT", halo = true },
  },
  blink = {
    { type = "Alpha", from = 1, to = 0.15, dur = 0.12, order = 1 },
    { type = "Alpha", from = 0.15, to = 1, dur = 0.12, order = 2 },
    { type = "Alpha", from = 1, to = 0.15, dur = 0.12, order = 3 },
    { type = "Alpha", from = 0.15, to = 1, dur = 0.12, order = 4 },
  },
  shake = {
    { type = "Translation", x = 14, dur = 0.04, order = 1 },
    { type = "Translation", x = -28, dur = 0.08, order = 2 },
    { type = "Translation", x = 28, dur = 0.08, order = 3 },
    { type = "Translation", x = -14, dur = 0.04, order = 4 },
  },
}

local STEP_SETUP = {
  Scale = function(a, s)
    a:SetScaleFrom(s.from, s.from)
    a:SetScaleTo(s.to, s.to)
    a:SetOrigin("CENTER", 0, 0)
  end,
  Alpha = function(a, s)
    a:SetFromAlpha(s.from)
    a:SetToAlpha(s.to)
  end,
  Translation = function(a, s) a:SetOffset(s.x or 0, s.y or 0) end,
}

local function buildGroup(target, steps)
  local ag = target:CreateAnimationGroup()
  for _, s in ipairs(steps) do
    local a = ag:CreateAnimation(s.type)
    a:SetDuration(s.dur)
    a:SetOrder(s.order or 1)
    if s.smooth then a:SetSmoothing(s.smooth) end
    STEP_SETUP[s.type](a, s)
  end
  return ag
end

local function animGroup(S, name)
  local ag = S.anims[name]
  if ag then return ag end
  local steps = ANIM_STEPS[name]
  if not steps then return nil end
  ag = buildGroup(steps[1].halo and S.halo or S.content, steps)
  if steps[1].halo then ag:SetToFinalAlpha(true) end
  S.anims[name] = ag
  return ag
end

local function stopAnims(S)
  for _, ag in pairs(S.anims) do ag:Stop() end
  if S.fade then S.fade:Stop() end
end

-- ── the frame ────────────────────────────────────────────────────────────────────────────────

local function paint(S, kind)
  local r, g, b = colorOf(S, kind)
  S.text:SetTextColor(r, g, b, 1)
  S.halo:SetTextColor(r, g, b, 1)
  S.halo:SetAlpha(GLOW_ALPHA[get(S, "glow")])
end

local function applyLook(S)
  local path, size, flags = fontPath(S), get(S, "size"), fontFlags(S)
  setFont(S.text, path, size, flags)
  setFont(S.halo, path, math.floor(size * GLOW_SCALE[get(S, "glow")] + 0.5), "THICKOUTLINE")
  if get(S, "shadow") then
    S.text:SetShadowOffset(get(S, "shadowX"), get(S, "shadowY"))
    S.text:SetShadowColor(0, 0, 0, 1)
  else
    S.text:SetShadowOffset(0, 0)
    S.text:SetShadowColor(0, 0, 0, 0)
  end
  S.frame:SetSize(lib.WIDTH, math.floor(size * HEIGHT_FACTOR + 0.5))
  paint(S, S.current and S.current.kind or "info")
end

local function applyPosition(S)
  local pt = get(S, "point")
  S.frame:ClearAllPoints()
  S.frame:SetPoint(pt[1], UIParent, pt[2] or pt[1], pt[3] or 0, pt[4] or 0)
end

local function savePosition(S)
  local point, _, relativePoint, x, y = S.frame:GetPoint(1)
  local t = store(S)
  if type(point) ~= "string" or not t then return end
  t.point = { point, type(relativePoint) == "string" and relativePoint or point,
    finite(x) and x or 0, finite(y) and y or 0 }
end

local function onDragStart(S)
  if S.locked then return end
  S.frame:StartMoving()
  S.moving = true
end

local function onDragStop(S)
  S.moving = nil
  S.frame:StopMovingOrSizing()
  savePosition(S)
end

--- A lock (or a Suspend) during a drag: the mouse-up never reaches a frame that no longer takes the
--- mouse, so the move ends here and the point is saved (Toast.lua's endDrag, the same shape).
local function endDrag(S)
  if not S.moving then return end
  S.moving = nil
  S.frame:StopMovingOrSizing()
  savePosition(S)
end

--- The drag strip over the frame while it is unlocked, when LibKa0s-Widgets-1.0 is present. It is a
--- child of the frame, which never animates (the animations play on S.content), and it ignores the
--- frame's alpha and sits HANDLE_LEVEL over it (frame-layering-§2).
local function buildHandle(S)
  local Widgets = resolve("LibKa0s-Widgets-1.0")
  if not (Widgets and type(Widgets.DragHandle) == "function") then return end
  local handle = Widgets.DragHandle(S.frame, {
    label = type(S.d.label) == "string" and S.d.label or "Call-out",
    moveFrame = S.frame, owner = S.d.skin, ignoreParentAlpha = true, level = HANDLE_LEVEL,
    canDrag = function() return not S.locked end,
    onDragStart = function() S.moving = true end,
    onDragStop = function() S.moving = nil; savePosition(S) end,
  })
  if not handle then return end
  handle:SetPoint("BOTTOM", S.frame, "TOP", 0, HANDLE_GAP)
  if type(handle.ApplyWidth) == "function" then handle:ApplyWidth() end
  handle:Hide()
  S.handle = handle
end

local function finishFade(S)
  S.frame:Hide()
  S.frame:SetAlpha(1)
  S.current = nil
end

local function buildFade(S)
  local ag = buildGroup(S.frame, { { type = "Alpha", from = 1, to = 0, dur = FADE, order = 1 } })
  ag:SetScript("OnFinished", function() finishFade(S) end)
  S.fade = ag
end

local tick   -- forward: the clock's OnUpdate calls it; defined with the countdown below

local function build(S)
  if S.frame then return S.frame end
  local f = CreateFrame("Frame", S.d.name, UIParent)
  S.frame = f
  f:Hide()
  f:SetFrameStrata(lib.STRATA)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(false)            -- never takes the mouse while locked
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() onDragStart(S) end)
  f:SetScript("OnDragStop", function() onDragStop(S) end)
  -- The text and its halo sit on an inner frame the animations play on, so the frame (the drag
  -- target, the fade, and the drag strip's parent) never scales, shakes or blinks.
  local content = CreateFrame("Frame", nil, f)
  content:SetAllPoints(f)
  S.content = content
  S.halo = content:CreateFontString(nil, "BACKGROUND")
  S.halo:SetPoint("CENTER", content, "CENTER", 0, 0)
  S.text = content:CreateFontString(nil, "OVERLAY")
  S.text:SetPoint("CENTER", content, "CENTER", 0, 0)
  S.clock = CreateFrame("Frame")   -- no parent: a hidden UI does not stop the countdown
  buildFade(S)
  buildHandle(S)
  applyLook(S)
  applyPosition(S)
  return f
end

-- ── the clock ────────────────────────────────────────────────────────────────────────────────

local function wake(S)
  if S.awake then return end
  S.awake = true
  S.clock:SetScript("OnUpdate", function() tick(S) end)
end

local function sleep(S)
  if not S.awake then return end
  S.awake = false
  S.clock:SetScript("OnUpdate", nil)
end

local function startFade(S)
  S.hideAt = nil
  if not S.locked then return end   -- unlocked, the sample stays up to be placed
  for _, ag in pairs(S.anims) do ag:Stop() end
  S.fade:Play()
end

local function hideNow(S)
  S.hideAt = nil
  if not S.frame then return end
  stopAnims(S)
  finishFade(S)
end

-- ── the sound ────────────────────────────────────────────────────────────────────────────────

local function soundsBase(S)
  if nonEmpty(S.d.soundsBase) then return S.d.soundsBase end
  if not nonEmpty(S.d.addon) then return nil end
  return "Interface\\AddOns\\" .. S.d.addon .. "\\" .. (S.d.vendorPath or "libs\\LibKa0s")
    .. "\\media\\sounds\\callout"
end

local function playFile(S, file)
  if type(PlaySoundFile) ~= "function" then
    logOnce(S, "no PlaySoundFile: call-outs are silent")
    return false
  end
  if PlaySoundFile(file, get(S, "channel")) == false then
    logOnce(S, "sound file missing, silent: " .. tostring(file))
    return false
  end
  return true
end

local function playLine(S, voice, line)
  local base = soundsBase(S)
  if not base then
    logOnce(S, "no d.addon or d.soundsBase: the voice packs cannot be found")
    return false
  end
  return playFile(S, base .. "\\" .. PACK[voice].folder .. "\\" .. line .. lib.SOUND_EXT)
end

--- The player's TTS voice when the client still has it, else the client's first voice.
local function ttsVoiceId(S, voices)
  local want = get(S, "ttsVoice")
  for _, v in ipairs(voices) do
    if v.voiceID == want then return want end
  end
  return voices[1] and voices[1].voiceID
end

local function ttsVoices()
  local vc = C_VoiceChat
  local list = vc and vc.GetTtsVoices and vc.GetTtsVoices()
  local out = {}
  if type(list) ~= "table" then return out end
  for _, v in ipairs(list) do
    if type(v) == "table" and finite(v.voiceID) then
      out[#out + 1] = { voiceID = v.voiceID, name = tostring(v.name or v.voiceID) }
    end
  end
  return out
end

local function speak(S, text)
  local vc = C_VoiceChat
  if not (vc and vc.SpeakText) then
    logOnce(S, "no C_VoiceChat.SpeakText: text to speech is silent")
    return false
  end
  local id = ttsVoiceId(S, ttsVoices())
  if not id then
    logOnce(S, "no text to speech voice installed")
    return false
  end
  vc.SpeakText(id, text, get(S, "ttsRate"), get(S, "ttsVolume"), true)
  return true
end

--- What an entry says, by the voice setting. Answers whether anything was played.
local function sound(S, entry)
  if entry.voice == false then return false end
  if entry.stock and get(S, "muted")[entry.key] then return false end
  local voice = voiceOf(S)
  if voice == lib.OFF then return false end
  if entry.sound then return playFile(S, entry.sound) end
  if entry.number and entry.number > get(S, "speakFrom") then return false end
  if voice == lib.TTS then return speak(S, entry.say or entry.text) end
  if entry.line then return playLine(S, voice, entry.line) end
  return false
end

-- ── the entries ──────────────────────────────────────────────────────────────────────────────

local function numberEntry(n)
  local s = tostring(n)
  return { key = s, text = s, kind = "number", say = s, line = s, number = n }
end

local function stockEntry(S, key)
  local stock = lib.STOCK[key]
  if not stock then return nil end
  local own = get(S, "texts")[key]
  return { key = key, text = nonEmpty(own) and own or stock.text, kind = stock.kind,
    say = stock.say, line = key:lower(), stock = true }
end

local function customEntry(spec)
  if spec.text == nil then return nil end
  return { text = tostring(spec.text), kind = KIND[spec.kind] and spec.kind or "info",
    sound = (nonEmpty(spec.sound) or finite(spec.sound)) and spec.sound or nil,
    voice = spec.voice, hold = spec.hold, anim = spec.anim, key = spec.key }
end

--- A stock key, a number from 1 to 20 (or its string), or a custom spec, as an entry; nil for none.
local function entryFor(S, what)
  local n = tonumber(what)
  if n and n == math.floor(n) and n >= 1 and n <= lib.MAX_FROM then return numberEntry(n) end
  if type(what) == "string" then return stockEntry(S, what) end
  if type(what) == "table" then return customEntry(what) end
  return nil
end

local function merge(entry, opts)
  if type(opts) ~= "table" then return entry end
  if opts.hold ~= nil then entry.hold = opts.hold end
  if opts.anim ~= nil then entry.anim = opts.anim end
  if opts.voice == false then entry.voice = false end
  return entry
end

--- Draw `entry` now, play its animation and its sound.
local function present(S, entry)
  build(S)
  S.current = entry
  S.text:SetText(entry.text)
  S.halo:SetText(entry.text)
  paint(S, entry.kind)
  stopAnims(S)
  S.frame:SetAlpha(1)
  S.frame:Show()
  local anim = inList(lib.ANIMS, entry.anim) and entry.anim or get(S, "anim")
  local ag = animGroup(S, anim)
  if ag then ag:Play() end
  sound(S, entry)
end

local function holdFor(S, entry)
  if VALID.hold(entry.hold) then return entry.hold end
  return get(S, "hold")
end

--- Show `entry` and fade it after its hold.
local function showHeld(S, entry)
  present(S, entry)
  S.hideAt = GetTime() + holdFor(S, entry)
  wake(S)
end

-- ── the countdown ────────────────────────────────────────────────────────────────────────────

local function finishCountdown(S, cd)
  local finish = cd.finish
  if finish == nil then finish = "GO" end
  local entry = finish ~= false and entryFor(S, finish)
  if entry then showHeld(S, entry) else startFade(S) end
  call(S, cd.onDone)
end

local function stepCountdown(S, now)
  local cd = S.cd
  local n = math.ceil(cd.endsAt - now)
  if n == cd.last or n > cd.from then return end
  cd.last = n
  if n >= 1 then
    S.hideAt = nil   -- the number replaces a held Show (or the last finish); its hold goes with it
    present(S, numberEntry(n))
    call(S, cd.onTick, n)
    return
  end
  S.cd = nil
  finishCountdown(S, cd)
end

tick = function(S)
  local now = GetTime()
  if S.cd then stepCountdown(S, now) end
  if S.hideAt and now >= S.hideAt then startFade(S) end
  if not (S.cd or S.hideAt) then sleep(S) end
end

-- ── the instance ─────────────────────────────────────────────────────────────────────────────

local STATE = setmetatable({}, { __mode = "k" })

local function state(self)
  local S = STATE[self]
  if not S then error(MAJOR .. ": call this on an instance from Callout:New", 3) end
  return S
end

local METHODS = {}

--- Count down to `spec.endsAt` (a GetTime() value): the number shown is ceil(endsAt - now), from
--- `spec.from` (at most 20; the default is 20) down to 1, then `spec.finish` (a stock key, a
--- custom spec, or false for none; "GO" when nil). `spec.onTick(n)` is called as each number
--- shows, `spec.onDone()` once at zero. A countdown already running is replaced. Answers false
--- (and does nothing) while suspended or for an endsAt that is not a number.
function METHODS:Countdown(spec)
  local S = state(self)
  if S.suspended or type(spec) ~= "table" or not finite(spec.endsAt) then return false end
  local from = tonumber(spec.from) or lib.MAX_FROM
  from = math.max(1, math.min(lib.MAX_FROM, math.floor(from)))
  build(S)
  -- A held call-out keeps its hold: through a lead-in (endsAt more than `from` away) it fades on its
  -- own schedule, and the first number replaces it (stepCountdown clears the hold).
  S.cd = { endsAt = spec.endsAt, from = from, finish = spec.finish,
    onTick = spec.onTick, onDone = spec.onDone }
  wake(S)
  tick(S)
  return true
end

--- Stop the countdown without its finish or its onDone, and take the call-out down.
function METHODS:Cancel()
  local S = state(self)
  local had = S.cd ~= nil
  S.cd = nil
  hideNow(S)
  sleep(S)
  return had
end

--- Whether a countdown runs, and the number it shows (nil before its first).
function METHODS:Running()
  local cd = state(self).cd
  if not cd then return false, nil end
  return true, cd.last
end

--- Show a stock key, a number 1-20, or a custom `{ text, kind, sound, voice = false, hold, anim }`.
--- `opts` may carry `hold`, `anim` and `voice = false`. It shows over a running countdown, whose
--- next number replaces it. Answers false for nothing to show, or while suspended.
function METHODS:Show(what, opts)
  local S = state(self)
  if S.suspended then return false end
  local entry = entryFor(S, what)
  if not entry then
    debugOut(S, "nothing to show for " .. tostring(what))
    return false
  end
  showHeld(S, merge(entry, opts))
  return true
end

--- Take the call-out down now (a running countdown goes on, and shows its next number).
function METHODS:Hide()
  local S = state(self)
  hideNow(S)
  if not S.cd then sleep(S) end
end

--- The stand-down: the countdown stops with no onDone, the call-out goes, the frame locks, and
--- Show and Countdown answer false until Resume.
function METHODS:Suspend()
  local S = state(self)
  S.suspended, S.cd = true, nil
  self:SetLocked(true)
  hideNow(S)
  sleep(S)
end

function METHODS:Resume() state(self).suspended = false end

function METHODS:Suspended() return state(self).suspended == true end

--- One setting, as the instance reads it: the host's stored value, or the default when it holds
--- none or one that is not valid.
function METHODS:Get(key)
  local S = state(self)
  if not VALID[key] then return nil end
  if key == "voice" then return voiceOf(S) end
  return copy(get(S, key))
end

--- Write one setting into the host's table and apply it. nil clears it back to the default. Answers
--- false for an unknown key, an invalid value or no table to write into.
function METHODS:Set(key, value)
  local S = state(self)
  local t = store(S)
  if not (t and VALID[key]) or (value ~= nil and not VALID[key](value)) then return false end
  if key == "voice" and PACK[value] and not offered(S)[value] then return false end   -- not shipped
  t[key] = copy(value)
  self:Apply()
  return true
end

function METHODS:GetColor(kind)
  return colorOf(state(self), KIND[kind] and kind or "info")
end

--- A kind's color, written as { r, g, b } into the host's `colors`; no r clears it to the default.
function METHODS:SetColor(kind, r, g, b)
  local S = state(self)
  local t = store(S)
  if not (t and KIND[kind]) then return false end
  if r == nil then
    if type(t.colors) == "table" then t.colors[kind] = nil end
  else
    if not validColor({ r, g, b }) then return false end
    if type(t.colors) ~= "table" then t.colors = {} end
    t.colors[kind] = { r, g, b }
  end
  self:Apply()
  return true
end

--- Re-read every setting onto the frame (after a profile switch, or the host's own write).
function METHODS:Apply()
  local S = state(self)
  if not S.frame then return end
  applyLook(S)
  applyPosition(S)
end

--- Unlocked, the frame takes the mouse, shows a sample and its drag strip, and a drag saves the
--- point; locked (the default), it is mouse-transparent and the sample goes.
function METHODS:SetLocked(locked)
  local S = state(self)
  locked = locked ~= false
  if locked == S.locked then return end
  S.locked = locked
  if not S.frame then
    if locked then return end
    build(S)
  end
  if locked then endDrag(S) end
  S.frame:EnableMouse(not locked)
  if S.handle then S.handle:SetShown(not locked) end
  if not locked then
    present(S, merge(entryFor(S, "READY"), { voice = false }))
    S.hideAt = nil
  elseif not S.cd then
    hideNow(S)
  end
end

function METHODS:Locked() return state(self).locked end

--- Forget the saved point: the frame goes back to the default.
function METHODS:ResetPosition()
  local S = state(self)
  local t = store(S)
  if t then t.point = nil end
  if S.frame then applyPosition(S) end
end

--- The `voice` choices, in order: the packs the host ships (`d.packs`), then text to speech and
--- off. A fresh list.
function METHODS:Voices()
  local S = state(self)
  local out = {}
  for _, p in ipairs(lib.PACKS) do
    if offered(S)[p.key] then out[#out + 1] = { key = p.key, name = p.name } end
  end
  out[#out + 1] = { key = lib.TTS, name = "Game text to speech" }
  out[#out + 1] = { key = lib.OFF, name = "Off" }
  return out
end

--- The client's text to speech voices, { voiceID, name } each; empty without C_VoiceChat.
function METHODS:TtsVoices()   -- luacheck: ignore 212/self
  return ttsVoices()
end

--- The frame, built on first use.
function METHODS:Frame() return build(state(self)) end

--- The look as the frame draws it: `{ font, size, flags, shadow, shadowX, shadowY, glow }`, the
--- font resolved to a file path. A fresh table, for a host's (or CalloutSettings.lua's) preview.
function METHODS:Look()
  local S = state(self)
  return { font = fontPath(S), size = get(S, "size"), flags = fontFlags(S), shadow = get(S, "shadow"),
    shadowX = get(S, "shadowX"), shadowY = get(S, "shadowY"), glow = get(S, "glow") }
end

--- The instance's state, for a host's diagnostics report and its suites.
function METHODS:Stats()
  local S = state(self)
  local cur, cd = S.current, S.cd
  local logged = 0
  for _ in pairs(S.logged) do logged = logged + 1 end
  return {
    built = S.frame ~= nil, shown = S.frame ~= nil and S.frame:IsShown() == true,
    running = cd ~= nil, number = cd and cd.last, endsAt = cd and cd.endsAt,
    key = cur and cur.key, text = cur and cur.text, kind = cur and cur.kind,
    awake = S.awake == true, suspended = S.suspended == true, locked = S.locked, logged = logged,
  }
end

--- A new call-out. `d.db` is required; every other field is optional (see the API document).
function lib:New(d)   -- luacheck: ignore 212/self
  if type(d) ~= "table" or (type(d.db) ~= "table" and type(d.db) ~= "function") then
    error(MAJOR .. ": New(d): d.db (the host's settings table, or a getter) is required", 2)
  end
  local inst = {}
  for name, fn in pairs(METHODS) do inst[name] = fn end
  STATE[inst] = { d = d, anims = {}, logged = {}, locked = true, suspended = false, awake = false }
  return inst
end

-- The method table every New copies, for this major's paired files (CalloutSettings.lua adds the
-- settings section to it) and nobody else. Private: a host calls methods on an instance.
lib.__methods = METHODS
