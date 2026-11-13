-- LibKa0s-Callout-1.0 — CalloutSettings.lua: the settings section a consumer drops into its own panel.
--
-- ── WHAT IT IS ───────────────────────────────────────────────────────────────────────────────
--
-- The Look, Sound and Texts rows of one call-out, a live preview and its two test buttons, and the
-- unlock-to-move toggle (the owner's decisions of 2026-11-13, docs/superpowers/plans/2026-11-13-
-- callout.md, row L4). A file of the Callout major, paired on Callout.lua's minor the way
-- WidgetsCopyWindow.lua is on Widgets', so a section from one vendored copy never pairs with a
-- call-out from another without saying so. A payload without this file loads whole and its
-- instances have no BuildSettings.
--
-- ── THE TWO BUILDS ───────────────────────────────────────────────────────────────────────────
--
-- WITH the host's LibKa0s-Options-1.0 instance (`opts.options`), `parent` is a page ctx (what the
-- instance's CreatePanel answers, or the ctx a RenderTabbedSchema host tab's render is handed), and
-- every control is the Options instance's own: the rows are ordinary path-less schema rows (the
-- W15 arm, read and written through each row's `get` / `set`, which call the instance's Get / Set),
-- drawn by `O.RenderRows`, so they are the panel's dropdowns, sliders, checkboxes, edit boxes and
-- color swatches, in the host's skin, under its combat lock. The font row is the one media picker
-- (`Ka0sMedia_Font`, options-ui-§23). Options-ui-§13 puts every section on a tab: `SettingsTabs`
-- answers the three tab entries for the host's `RenderTabbedSchema` (`opts.tabs`), each drawing
-- its tab through `BuildSettings(ctx, { options, tab })`; with no `opts.tab` the three sections are
-- drawn one under another, each under its heading, for a host that gives the call-out one tab.
--
-- WITHOUT one, `parent` is a plain frame and the section is built of plain frames, one control per
-- line: a check button for a toggle, a value between - and + buttons for a number, a button that
-- steps through the choices for a list, a swatch that opens the client's color picker for a color.
-- The per-key text boxes are the Options build's alone.
--
-- ── THE PREVIEW ──────────────────────────────────────────────────────────────────────────────
--
-- Over each tab: a sample line ("5  GO!  STOP", each in its kind's color) drawn in the chosen face,
-- outline and shadow at the chosen size up to PREVIEW_MAX, repainted on every write (a refresher in
-- the page's `refreshers`, which the Options instance's write runs); "Test countdown" counts the
-- real call-out down from 5 to GO; "Play" shows the stock text picked beside it, with its voice.
-- The picked text is session state, never saved. "Unlock to move" is the instance's SetLocked: the
-- real call-out shows its sample and takes the mouse until locked again (never saved either).
--
-- ── WORDS ────────────────────────────────────────────────────────────────────────────────────
--
-- Every word is `lib.SETTINGS_STRINGS`, US English; a host passes `opts.L` keyed to it (read with
-- rawget, because a Ka0s locale table answers an unknown key with the key). A stock text's own word
-- (READY, GO!) is the call-out's `STOCK` text.
--
-- Depends on the Callout shell (Callout.lua's `lib.__methods`) and, for the Options build, on the
-- host's Options instance it is handed. LibSharedMedia-3.0, LibKa0s-Media-1.0 and C_VoiceChat are
-- each read at build time and optional.

local lib = LibStub and LibStub("LibKa0s-Callout-1.0", true)
if not lib or type(lib.__methods) ~= "table" then return end

local SETTINGS_MINOR = 1
if lib.__settingsMinor and lib.__settingsMinor >= SETTINGS_MINOR
  and lib.__settingsShellMinor == lib.MINOR then return end
lib.__settingsMinor      = SETTINGS_MINOR
lib.__settingsShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.CalloutSettings = SETTINGS_MINOR

local METHODS = lib.__methods

lib.SETTINGS_STRINGS = {
  TAB_LOOK = "Look", TAB_SOUND = "Sound", TAB_TEXTS = "Texts",
  TAB_LOOK_TIP = "How the call-out looks: its face, size, outline, shadow, glow and animation.",
  TAB_SOUND_TIP = "What the call-out says: a bundled voice, the game's text to speech, or nothing.",
  TAB_TEXTS_TIP = "Each kind's color, and each stock text's own words and voice.",
  PREVIEW = "Preview",
  TEST_COUNTDOWN = "Test countdown",
  TEST_COUNTDOWN_TIP = "Counts the call-out down from 5 to GO!, where it shows in play.",
  PLAY = "Play",
  PLAY_TIP = "Shows the text picked in Text to play, with its voice.",
  PLAY_KEY = "Text to play",
  PLAY_KEY_TIP = "The stock text Play shows. Not saved.",
  UNLOCK = "Unlock to move",
  UNLOCK_TIP = "Shows the call-out with a drag strip so you can move it. Lock it again when it is in place. Not saved.",
  RESET_POSITION = "Reset position",
  RESET_POSITION_TIP = "Puts the call-out back in its default place.",
  FONT = "Font", FONT_TIP = "The call-out's face. Skin font is your skin's, Game default the game's own.",
  SIZE = "Size", SIZE_TIP = "The height of the call-out's text, 32 to 200.",
  OUTLINE = "Outline", OUTLINE_TIP = "The outline drawn around each letter.",
  OUTLINE_NONE = "None", OUTLINE_OUTLINE = "Outline", OUTLINE_THICK = "Thick outline",
  OUTLINE_MONO = "Monochrome",
  SHADOW = "Shadow", SHADOW_TIP = "A black shadow behind the text.",
  SHADOW_X = "Shadow X offset", SHADOW_Y = "Shadow Y offset",
  SHADOW_OFFSET_TIP = "How far the shadow sits from the text, -20 to 20.",
  GLOW = "Glow", GLOW_TIP = "A halo in the text's color behind it.",
  GLOW_OFF = "Off", GLOW_SOFT = "Soft", GLOW_STRONG = "Strong",
  ANIM = "Animation", ANIM_TIP = "How a call-out arrives on screen.",
  ANIM_SLAM = "Slam", ANIM_PULSE = "Pulse", ANIM_GLOW = "Glow", ANIM_BLINK = "Blink",
  ANIM_SHAKE = "Shake", ANIM_NONE = "None",
  HOLD = "Hold (seconds)", HOLD_TIP = "How long a call-out stays before it fades, 0.2 to 10 seconds.",
  VOICE = "Voice",
  VOICE_TIP = "A bundled voice, the game's text to speech (the voices your system has installed), or off.",
  TTS_VOICE = "Text to speech voice", TTS_VOICE_TIP = "Which of the game's voices speaks.",
  TTS_RATE = "Speech rate", TTS_RATE_TIP = "How fast text to speech speaks, -10 to 10.",
  TTS_VOLUME = "Speech volume", TTS_VOLUME_TIP = "How loud text to speech speaks, 0 to 100.",
  CHANNEL = "Sound channel", CHANNEL_TIP = "The game's volume slider the voice follows.",
  CHANNEL_MASTER = "Master", CHANNEL_SFX = "Sound effects", CHANNEL_DIALOG = "Dialog",
  SPEAK_FROM = "Speak numbers from",
  SPEAK_FROM_TIP = "Countdown numbers above this are shown but not spoken, 1 to 20.",
  COLORS = "Colors",
  KIND_NUMBER = "Numbers", KIND_INFO = "Information", KIND_GO = "Go", KIND_STOP = "Stop",
  KIND_WARN = "Warnings", KIND_ERROR = "Errors",
  KIND_TIP = "The color of every call-out of this kind.",
  STOCK_TEXTS = "Stock texts",
  TEXT_TIP = "Your own words for %s. Empty shows %s.",
  MUTE = "Mute %s", MUTE_TIP = "%s shows without its voice.",
}

local PREVIEW_MAX = 64            -- the preview's text is at most this tall
local PREVIEW_COUNTDOWN = 5       -- Test countdown's first number
local SAMPLE = { { "5", "number" }, { "GO", "go" }, { "STOP", "stop" } }
local KIND_WORD = { number = "KIND_NUMBER", info = "KIND_INFO", go = "KIND_GO", stop = "KIND_STOP",
  warn = "KIND_WARN", error = "KIND_ERROR" }
lib.SETTINGS_TABS = { "look", "sound", "texts" }
local TAB_WORD = { look = "TAB_LOOK", sound = "TAB_SOUND", texts = "TAB_TEXTS" }

-- The plain build's line pitch and column.
local PLAIN_LINE, PLAIN_LABEL_W, PLAIN_CONTROL_W, PLAIN_PAD = 26, 200, 160, 8

-- ── small readers ────────────────────────────────────────────────────────────────────────────

local function word(L, key)
  local v = type(L) == "table" and rawget(L, key)
  if type(v) == "string" then return v end
  return lib.SETTINGS_STRINGS[key]
end

local function resolve(major) return LibStub and LibStub(major, true) end

local function hex(r, g, b)
  local function c(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
  return ("%02x%02x%02x"):format(c(r), c(g), c(b))
end

-- A color for a path-less swatch: both shapes in one table, so the host's colorDecode reads it
-- whichever it expects (named keys, the library's default, or an array).
local function bothShapes(r, g, b) return { r, g, b, 1, r = r, g = g, b = b, a = 1 } end

local function fromEither(c)
  if type(c) ~= "table" then return nil end
  local r, g, b = c.r or c[1], c.g or c[2], c.b or c[3]
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
  return r, g, b
end

-- ── the choices ──────────────────────────────────────────────────────────────────────────────

local function listOf(L, pairs_)
  local out = {}
  for i, p in ipairs(pairs_) do out[i] = { value = p[1], text = word(L, p[2]) } end
  return out
end

local function outlineValues(L)
  return listOf(L, { { "NONE", "OUTLINE_NONE" }, { "OUTLINE", "OUTLINE_OUTLINE" },
    { "THICKOUTLINE", "OUTLINE_THICK" }, { "MONOCHROME", "OUTLINE_MONO" } })
end

local function glowValues(L)
  return listOf(L, { { "off", "GLOW_OFF" }, { "soft", "GLOW_SOFT" }, { "strong", "GLOW_STRONG" } })
end

local function animValues(L)
  return listOf(L, { { "slam", "ANIM_SLAM" }, { "pulse", "ANIM_PULSE" }, { "glow", "ANIM_GLOW" },
    { "blink", "ANIM_BLINK" }, { "shake", "ANIM_SHAKE" }, { "none", "ANIM_NONE" } })
end

local function channelValues(L)
  return listOf(L, { { "Master", "CHANNEL_MASTER" }, { "SFX", "CHANNEL_SFX" }, { "Dialog", "CHANNEL_DIALOG" } })
end

--- Every face the font row offers, in order: the skin's and the game's first, then every
--- LibSharedMedia face (or, without it, every LibKa0s-Media-1.0 face), as `{ value, text }`.
local function fontChoices()
  local names, seen = {}, {}
  local function add(n)
    if type(n) == "string" and not seen[n] then seen[n] = true; names[#names + 1] = n end
  end
  local LSM = resolve("LibSharedMedia-3.0")
  if LSM and type(LSM.List) == "function" then
    for _, n in ipairs(LSM:List("font") or {}) do add(n) end
  end
  local Media = resolve("LibKa0s-Media-1.0")
  if #names == 0 and Media and type(Media.FONTS) == "table" then
    for n in pairs(Media.FONTS) do add(n) end
  end
  add(lib.FONT_DEFAULT)
  table.sort(names)
  local out = { { value = lib.FONT_SKIN, text = lib.FONT_SKIN }, { value = lib.FONT_GAME, text = lib.FONT_GAME } }
  for _, n in ipairs(names) do
    if n ~= lib.FONT_SKIN and n ~= lib.FONT_GAME then out[#out + 1] = { value = n, text = n } end
  end
  return out
end

local function stockValues()
  local out = {}
  for i, key in ipairs(lib.STOCK_ORDER) do out[i] = { value = key, text = lib.STOCK[key].text } end
  return out
end

-- ── the rows ─────────────────────────────────────────────────────────────────────────────────
--
-- Path-less schema rows (Options' W15 arm): each reads and writes through the instance. `tab` is
-- the tab's key; `group` its label, so RenderRows draws a heading per tab when all three are drawn.

local function setting(inst, key)
  return function() return inst:Get(key) end, function(v) inst:Set(key, v) end
end

local function row(list, tab, group, subgroup, t)
  t.tab, t.group, t.subgroup = tab, group, subgroup
  list[#list + 1] = t
  return t
end

local function slider(inst, label, tip, key, lo, hi, step)
  local get, set = setting(inst, key)
  return { type = "number", label = label, tooltip = tip, min = lo, max = hi, step = step,
    get = get, set = set, key = key }
end

local function choice(inst, label, tip, key, values)
  local get, set = setting(inst, key)
  return { type = "string", label = label, tooltip = tip, values = values, get = get, set = set, key = key }
end

local function lookRows(inst, L, out)
  local g = word(L, "TAB_LOOK")
  local fontGet, fontSet = setting(inst, "font")
  row(out, "look", g, nil, { type = "string", label = word(L, "FONT"), tooltip = word(L, "FONT_TIP"),
    dialogControl = "Ka0sMedia_Font", values = fontChoices, get = fontGet, set = fontSet, key = "font",
    startsLine = true })
  row(out, "look", g, nil, slider(inst, word(L, "SIZE"), word(L, "SIZE_TIP"), "size", lib.SIZE_MIN, lib.SIZE_MAX, 1))
  row(out, "look", g, nil, choice(inst, word(L, "OUTLINE"), word(L, "OUTLINE_TIP"), "outline", outlineValues(L)))
  row(out, "look", g, nil, choice(inst, word(L, "GLOW"), word(L, "GLOW_TIP"), "glow", glowValues(L)))
  local shadowGet, shadowSet = setting(inst, "shadow")
  row(out, "look", g, nil, { type = "bool", label = word(L, "SHADOW"), tooltip = word(L, "SHADOW_TIP"),
    get = shadowGet, set = shadowSet, key = "shadow", startsLine = true })
  local noShadow = function() return not inst:Get("shadow") end
  local x = row(out, "look", g, nil, slider(inst, word(L, "SHADOW_X"), word(L, "SHADOW_OFFSET_TIP"), "shadowX", -20, 20, 1))
  local y = row(out, "look", g, nil, slider(inst, word(L, "SHADOW_Y"), word(L, "SHADOW_OFFSET_TIP"), "shadowY", -20, 20, 1))
  x.disabledIf, y.disabledIf, x.startsLine = noShadow, noShadow, true
  local anim = row(out, "look", g, nil, choice(inst, word(L, "ANIM"), word(L, "ANIM_TIP"), "anim", animValues(L)))
  anim.startsLine = true
  row(out, "look", g, nil, slider(inst, word(L, "HOLD"), word(L, "HOLD_TIP"), "hold", 0.2, 10, 0.1))
end

local function soundRows(inst, L, out)
  local g = word(L, "TAB_SOUND")
  local voices = {}
  for i, v in ipairs(inst:Voices()) do voices[i] = { value = v.key, text = v.name } end
  local voice = row(out, "sound", g, nil, choice(inst, word(L, "VOICE"), word(L, "VOICE_TIP"), "voice", voices))
  voice.startsLine = true
  row(out, "sound", g, nil, choice(inst, word(L, "CHANNEL"), word(L, "CHANNEL_TIP"), "channel", channelValues(L)))
  local from = row(out, "sound", g, nil, slider(inst, word(L, "SPEAK_FROM"), word(L, "SPEAK_FROM_TIP"),
    "speakFrom", 1, lib.MAX_FROM, 1))
  from.startsLine = true
  -- Text to speech: only on a client that has it and lists a voice; drawn disabled off "tts".
  local tts = inst:TtsVoices()
  if #tts == 0 then return end
  local notTts = function() return inst:Get("voice") ~= lib.TTS end
  local list = {}
  for i, v in ipairs(tts) do list[i] = { value = v.voiceID, text = v.name } end
  local pick = row(out, "sound", g, nil, { type = "number", label = word(L, "TTS_VOICE"), tooltip = word(L, "TTS_VOICE_TIP"),
    values = list, key = "ttsVoice", startsLine = true, disabledIf = notTts,
    get = function()
      local want = inst:Get("ttsVoice")
      for _, v in ipairs(tts) do if v.voiceID == want then return want end end
      return tts[1].voiceID
    end,
    set = function(v) inst:Set("ttsVoice", v) end })
  local rate = row(out, "sound", g, nil, slider(inst, word(L, "TTS_RATE"), word(L, "TTS_RATE_TIP"), "ttsRate", -10, 10, 1))
  local vol = row(out, "sound", g, nil, slider(inst, word(L, "TTS_VOLUME"), word(L, "TTS_VOLUME_TIP"), "ttsVolume", 0, 100, 1))
  rate.disabledIf, vol.disabledIf, rate.startsLine = notTts, notTts, true
  return pick
end

--- A copy of a table setting with one key changed (nil removes it), written back whole.
local function writeKeyed(inst, key, k, v)
  local t = inst:Get(key)
  t[k] = v
  inst:Set(key, t)
end

local function textsRows(inst, L, out, withText)
  local g = word(L, "TAB_TEXTS")
  local colors = word(L, "COLORS")
  for i, kind in ipairs(lib.KINDS) do
    row(out, "texts", g, colors, { type = "color", label = word(L, KIND_WORD[kind]), tooltip = word(L, "KIND_TIP"),
      hasAlpha = false, key = "colors." .. kind, startsLine = i == 1,
      get = function() return bothShapes(inst:GetColor(kind)) end,
      set = function(c)
        local r, gg, b = fromEither(c)
        if r then inst:SetColor(kind, r, gg, b) end
      end })
  end
  local stock = word(L, "STOCK_TEXTS")
  for _, key in ipairs(lib.STOCK_ORDER) do
    local shown = lib.STOCK[key].text
    if withText then
      row(out, "texts", g, stock, { type = "string", dialogControl = "EditBox", label = shown, startsLine = true,
        tooltip = word(L, "TEXT_TIP"):format(shown, shown), key = "texts." .. key,
        get = function() return inst:Get("texts")[key] or "" end,
        set = function(v)
          local text = type(v) == "string" and v:match("^%s*(.-)%s*$") or ""
          writeKeyed(inst, "texts", key, text ~= "" and text or nil)
        end })
    end
    row(out, "texts", g, stock, { type = "bool", label = word(L, "MUTE"):format(shown),
      tooltip = word(L, "MUTE_TIP"):format(shown), key = "muted." .. key, startsLine = not withText,
      get = function() return inst:Get("muted")[key] == true end,
      set = function(v) writeKeyed(inst, "muted", key, v and true or nil) end })
  end
end

--- The section's rows: path-less schema rows bound to this instance, Look, Sound then Texts, or
--- one tab's (`opts.tab`). `opts.L` overrides the words; `opts.plain` leaves the text boxes out.
function METHODS:SettingsRows(opts)
  opts = type(opts) == "table" and opts or {}
  local out = {}
  local tab = opts.tab
  if tab == nil or tab == "look" then lookRows(self, opts.L, out) end
  if tab == nil or tab == "sound" then soundRows(self, opts.L, out) end
  if tab == nil or tab == "texts" then textsRows(self, opts.L, out, not opts.plain) end
  return out
end

-- ── the preview ──────────────────────────────────────────────────────────────────────────────

local VIEW = setmetatable({}, { __mode = "k" })   -- instance -> its session state (the play pick)

local function session(inst)
  local v = VIEW[inst]
  if not v then v = { play = "GO" }; VIEW[inst] = v end
  return v
end

--- The sample line, each word in its kind's color.
local function sampleText(inst)
  local parts = {}
  for i, s in ipairs(SAMPLE) do
    local text = s[1] == "GO" and lib.STOCK.GO.text or s[1] == "STOP" and lib.STOCK.STOP.text or s[1]
    parts[i] = "|cff" .. hex(inst:GetColor(s[2])) .. text .. "|r"
  end
  return table.concat(parts, "  ")
end

--- Paint a FontString (or an AceGUI Label, through its SetFont) in the chosen look.
local function paintPreview(inst, target, fs)
  local look = inst:Look()
  local size = math.min(look.size, PREVIEW_MAX)
  if type(target.SetFont) == "function" then target:SetFont(look.font, size, look.flags) end
  if type(target.SetText) == "function" then target:SetText(sampleText(inst)) end
  if not (fs and type(fs.SetShadowOffset) == "function") then return end
  if look.shadow then
    fs:SetShadowOffset(look.shadowX, look.shadowY)
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
  else
    fs:SetShadowOffset(0, 0)
  end
end

--- Show `what` (a stock key, a number or a custom spec; READY by default) silently, as a preview
--- of the look on the real call-out.
function METHODS:Preview(what)
  return self:Show(what or "READY", { voice = false })
end

--- Count the real call-out down from `from` (5) to GO!.
function METHODS:TestCountdown(from)
  local n = tonumber(from) or PREVIEW_COUNTDOWN
  return self:Countdown{ endsAt = GetTime() + n, from = n }
end

local function playPicked(inst) return inst:Show(session(inst).play) end

-- The preview block's own rows: the text Play shows, and the unlock toggle. Session state only.
local function previewRows(inst, L)
  local v = session(inst)
  return {
    { type = "string", label = word(L, "PLAY_KEY"), tooltip = word(L, "PLAY_KEY_TIP"), values = stockValues(),
      key = "play", startsLine = true, sessionOnly = true,
      get = function() return v.play end, set = function(k) if lib.STOCK[k] then v.play = k end end },
    { type = "bool", label = word(L, "UNLOCK"), tooltip = word(L, "UNLOCK_TIP"), key = "unlocked", sessionOnly = true,
      get = function() return inst:Locked() == false end, set = function(on) inst:SetLocked(not on) end },
  }
end

-- ── the Options build ────────────────────────────────────────────────────────────────────────

local function optionsPreview(inst, O, ctx, L, view)
  local label = O.TextRow(ctx, sampleText(inst), { justify = "CENTER" })
  view.preview = label
  if label then
    local function repaint() paintPreview(inst, label, label.label) end
    repaint()
    if type(ctx.refreshers) == "table" then ctx.refreshers[#ctx.refreshers + 1] = repaint end
    view.repaint = repaint
  end
  O.InlineButtonPair(ctx,
    { text = word(L, "TEST_COUNTDOWN"), tooltip = word(L, "TEST_COUNTDOWN_TIP"),
      onClick = function() inst:TestCountdown() end },
    { text = word(L, "PLAY"), tooltip = word(L, "PLAY_TIP"), onClick = function() playPicked(inst) end })
  O.RenderRows(ctx, previewRows(inst, L), nil, nil, { noHeadings = true })
  O.InlineButtonPair(ctx, { text = word(L, "RESET_POSITION"), tooltip = word(L, "RESET_POSITION_TIP"),
    onClick = function() inst:ResetPosition() end })
end

-- What the Options build calls on the host's instance, each checked before anything is drawn.
local OPTIONS_MEMBERS = { "EnsureScroll", "TextRow", "InlineButtonPair", "RenderRows" }

local function buildOptions(inst, ctx, opts)
  local O, L = opts.options, opts.L
  local view = { kind = "options" }
  for _, member in ipairs(OPTIONS_MEMBERS) do
    if type(O[member]) ~= "function" then return nil end   -- an instance without it builds nothing
  end
  if not O.EnsureScroll(ctx) then return nil end
  optionsPreview(inst, O, ctx, L, view)
  view.rows = inst:SettingsRows({ tab = opts.tab, L = L })
  O.RenderRows(ctx, view.rows, nil, nil, { noHeadings = opts.tab ~= nil })
  return view
end

--- The three tab entries for the host's `RenderTabbedSchema` (`opts.tabs`): `{ key, label,
--- tooltip, render }` each, keyed `opts.keyPrefix .. "look"` (and sound, texts; the prefix is
--- "callout." by default), each drawing its tab through BuildSettings. `opts.options` is required.
function METHODS:SettingsTabs(opts)
  opts = type(opts) == "table" and opts or {}
  local prefix = type(opts.keyPrefix) == "string" and opts.keyPrefix or "callout."
  local out = {}
  for i, tab in ipairs(lib.SETTINGS_TABS) do
    out[i] = { key = prefix .. tab, label = word(opts.L, TAB_WORD[tab]),
      tooltip = word(opts.L, TAB_WORD[tab] .. "_TIP"), before = opts.before,
      render = function(ctx) self:BuildSettings(ctx, { options = opts.options, tab = tab, L = opts.L }) end }
  end
  return out
end

-- ── the plain build ──────────────────────────────────────────────────────────────────────────

local function plainLabel(parent, text, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PLAIN_PAD, y)
  fs:SetWidth(PLAIN_LABEL_W)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

local function plainButton(parent, text, x, y, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, PLAIN_LINE - 4)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function valueText(r)
  local v = r.get()
  if type(r.values) == "table" then
    for _, item in ipairs(r.values) do if item.value == v then return item.text end end
  end
  if r.type == "number" then return (r.step or 1) < 1 and ("%.1f"):format(v) or tostring(v) end
  return tostring(v)
end

local function cycle(r, dir)
  local list, v = r.values, r.get()
  local at = 1
  for i, item in ipairs(list) do if item.value == v then at = i end end
  at = (at - 1 + dir) % #list + 1
  r.set(list[at].value)
end

local function nudge(r, dir)
  local v = r.get() + dir * (r.step or 1)
  v = math.max(r.min, math.min(r.max, v))
  r.set(math.floor(v / (r.step or 1) + 0.5) * (r.step or 1))
end

local PLAIN = {}

PLAIN.bool = function(parent, r, y, refresh)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", PLAIN_PAD + PLAIN_LABEL_W, y + 2)
  cb:SetScript("OnClick", function(self) r.set(self:GetChecked() and true or false); refresh() end)
  return cb, function() cb:SetChecked(r.get() and true or false) end
end

PLAIN.number = function(parent, r, y, refresh)
  if type(r.values) == "table" then return PLAIN.string(parent, r, y, refresh) end
  local x = PLAIN_PAD + PLAIN_LABEL_W
  local minus = plainButton(parent, "-", x, y, PLAIN_LINE, function() nudge(r, -1); refresh() end)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", parent, "TOPLEFT", x + PLAIN_LINE + 4, y - 4)
  local plus = plainButton(parent, "+", x + PLAIN_LINE + 60, y, PLAIN_LINE, function() nudge(r, 1); refresh() end)
  return { minus = minus, text = text, plus = plus }, function() text:SetText(valueText(r)) end
end

PLAIN.string = function(parent, r, y, refresh)
  if type(r.values) == "function" then r = setmetatable({ values = r.values() }, { __index = r }) end
  local b = plainButton(parent, "", PLAIN_PAD + PLAIN_LABEL_W, y, PLAIN_CONTROL_W, function() cycle(r, 1); refresh() end)
  return b, function() b:SetText(valueText(r)) end
end

PLAIN.color = function(parent, r, y, refresh)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(PLAIN_LINE - 6, PLAIN_LINE - 6)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", PLAIN_PAD + PLAIN_LABEL_W, y)
  local tex = b:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(b)
  if tex.SetColorTexture then tex:SetColorTexture(1, 1, 1, 1) end
  b:SetScript("OnClick", function()
    local cpf = ColorPickerFrame
    if not (cpf and type(cpf.SetupColorPickerAndShow) == "function") then return end
    local r0, g0, b0 = fromEither(r.get())
    local function apply()
      r.set({ cpf:GetColorRGB() })
      refresh()
    end
    cpf:SetupColorPickerAndShow({ r = r0, g = g0, b = b0, hasOpacity = false, swatchFunc = apply,
      cancelFunc = function() r.set({ r0, g0, b0 }); refresh() end })
  end)
  return b, function()
    local cr, cg, cb = fromEither(r.get())
    if tex.SetVertexColor then tex:SetVertexColor(cr, cg, cb, 1) end
  end
end

local function plainHeading(parent, text, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PLAIN_PAD, y)
  fs:SetText(text)
  return fs
end

local function plainPreview(inst, parent, L, view, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PLAIN_PAD, y)
  fs:SetHeight(PREVIEW_MAX + PLAIN_PAD)
  view.preview = fs
  y = y - PREVIEW_MAX - PLAIN_PAD * 2
  view.testButton = plainButton(parent, word(L, "TEST_COUNTDOWN"), PLAIN_PAD, y, PLAIN_CONTROL_W,
    function() inst:TestCountdown() end)
  view.playButton = plainButton(parent, word(L, "PLAY"), PLAIN_PAD + PLAIN_CONTROL_W + PLAIN_PAD, y,
    PLAIN_CONTROL_W, function() playPicked(inst) end)
  view.resetButton = plainButton(parent, word(L, "RESET_POSITION"), PLAIN_PAD + (PLAIN_CONTROL_W + PLAIN_PAD) * 2,
    y, PLAIN_CONTROL_W, function() inst:ResetPosition() end)
  return y - PLAIN_LINE
end

local function plainRow(parent, r, y, view, refresh)
  local make = PLAIN[r.type]
  if not make then return y end
  plainLabel(parent, r.label, y - 4)
  local control, sync = make(parent, r, y, refresh)
  view.controls[#view.controls + 1] = { row = r, control = control, sync = sync }
  return y - PLAIN_LINE
end

local function buildPlain(inst, parent, opts)
  if type(parent) ~= "table" or type(parent.CreateFontString) ~= "function" then return nil end
  local L = opts.L
  local view = { kind = "plain", controls = {} }
  local function refresh()
    paintPreview(inst, view.preview, view.preview)
    for _, c in ipairs(view.controls) do c.sync() end
  end
  view.refresh = refresh
  local y = plainPreview(inst, parent, L, view, -PLAIN_PAD)
  for _, r in ipairs(previewRows(inst, L)) do y = plainRow(parent, r, y, view, refresh) end
  view.rows = inst:SettingsRows({ tab = opts.tab, L = L, plain = true })
  local heading
  for _, r in ipairs(view.rows) do
    if opts.tab == nil and r.group ~= heading then   -- one tab draws no heading of its own
      heading = r.group
      y = y - PLAIN_PAD
      plainHeading(parent, heading, y)
      y = y - PLAIN_LINE
    end
    y = plainRow(parent, r, y, view, refresh)
  end
  view.height = PLAIN_PAD - y
  refresh()
  return view
end

-- ── the entry point ──────────────────────────────────────────────────────────────────────────

--- Build the settings section into `parent`. With `opts.options` (the host's LibKa0s Options
--- instance) `parent` is a page ctx and the rows are that instance's own; without, `parent` is a
--- frame and the section is plain frames. `opts.tab` ("look", "sound" or "texts") draws one tab;
--- `opts.L` overrides the words. Answers the view (`kind`, `rows`, `preview`, and for the plain
--- build `controls`, `refresh` and `height`), or nil when there is nothing to build into.
function METHODS:BuildSettings(parent, opts)
  opts = type(opts) == "table" and opts or {}
  if opts.tab ~= nil and not TAB_WORD[opts.tab] then return nil end
  if type(opts.options) == "table" then
    if type(parent) ~= "table" then return nil end
    return buildOptions(self, parent, opts)
  end
  return buildPlain(self, parent, opts)
end
