-- LibKa0s-WaypointArrow-1.0 — WaypointArrowSettings.lua: the settings rows a consumer drops into its own schema.
--
-- ── WHAT IT IS ───────────────────────────────────────────────────────────────────────────────
--
-- The arrow's Style, "Use the skin's colors", Far color, Near color and Scale, as ordinary schema
-- rows (the owner's decisions of 2026-11-14, Skill Master
-- docs/superpowers/plans/2026-11-14-feedback-round8.md, row L1). A file of the WaypointArrow major,
-- paired on WaypointArrow.lua's minor the way CalloutSettings.lua is on Callout's, so rows from one
-- vendored copy never pair with an arrow from another without saying so. A payload without this
-- file loads whole and has no SettingsRows.
--
-- ── WHY ROWS WITH THE HOST'S PATHS ───────────────────────────────────────────────────────────
--
-- The Callout's section reads and writes through its instance, because the instance owns its
-- settings table. The arrow owns none: a host keeps the five values at its own paths, in its own
-- profile, beside the rest of its page, so a profile switch, copy or reset reaches them the way it
-- reaches every other row. `SettingsRows(opts)` therefore answers PATH rows (`path`, `type`,
-- `default`, `label`, `desc`, `values`, `min`, `max`, `step`, `disabledIf`, `onChange`) that a host
-- registers in its schema like its own; each row also carries `key`, the arrow setting it holds.
-- The two color rows are `disabledIf` the "Use the skin's colors" path, so they gray out while the
-- skin's colors are drawn. A row's `onChange(value)` hands the value to `opts.arrow:Configure` (when
-- an instance is given), then calls `opts.onChange(key, value)`.
--
-- ── WORDS ────────────────────────────────────────────────────────────────────────────────────
--
-- Every word is `lib.SETTINGS_STRINGS`, US English; a host passes `opts.L` keyed to it (read with
-- rawget, because a Ka0s locale table answers an unknown key with the key).

local lib = LibStub and LibStub("LibKa0s-WaypointArrow-1.0", true)
if not lib or type(lib.__methods) ~= "table" then return end

-- Minor 1: the rows (plan row L1).
local SETTINGS_MINOR = 1
if lib.__settingsMinor and lib.__settingsMinor >= SETTINGS_MINOR
  and lib.__settingsShellMinor == lib.MINOR then return end
lib.__settingsMinor      = SETTINGS_MINOR
lib.__settingsShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.WaypointArrowSettings = SETTINGS_MINOR

lib.SETTINGS_STRINGS = {
  STYLE = "Arrow style",
  STYLE_TIP = "How the arrow is drawn. Raised floats over the world on a soft shadow; On the ground lies flat, tilted toward you.",
  STYLE_FLAT = "Flat", STYLE_RIDGE = "Ridge", STYLE_RAISED = "Raised", STYLE_FACETED = "Faceted",
  STYLE_GROUND = "On the ground",
  USE_SKIN = "Use the skin's colors",
  USE_SKIN_TIP = "The arrow fades from the skin's accent color, far away, to its good color as you arrive. Off: your own two colors.",
  FAR = "Far color", FAR_TIP = "The arrow's color 300 yards away or more. Not read while Use the skin's colors is on.",
  NEAR = "Near color", NEAR_TIP = "The arrow's color 30 yards away or closer. Not read while Use the skin's colors is on.",
  SCALE = "Arrow scale", SCALE_TIP = "The size of the arrow and its distance, 0.5 to 2.",
}

local STYLE_WORD = { flat = "STYLE_FLAT", ridge = "STYLE_RIDGE", raised = "STYLE_RAISED",
  faceted = "STYLE_FACETED", ground = "STYLE_GROUND" }
lib.SCALE_STEP = 0.05

local function word(L, key)
  local v = type(L) == "table" and rawget(L, key)
  if type(v) == "string" then return v end
  return lib.SETTINGS_STRINGS[key]
end

--- The style row's choices, in STYLES order: `{ value, text }` each.
function lib.StyleValues(L)
  local out = {}
  for i, style in ipairs(lib.STYLES) do out[i] = { value = style, text = word(L, STYLE_WORD[style]) } end
  return out
end

local function colorDefault(opts, c)
  if type(opts.encodeColor) == "function" then return opts.encodeColor(c[1], c[2], c[3], c[4] or 1) end
  return { c[1], c[2], c[3], c[4] or 1 }
end

local function onChangeFor(opts, key)
  local arrow, notify = opts.arrow, opts.onChange
  return function(value)
    if type(arrow) == "table" and type(arrow.Configure) == "function" then arrow:Configure({ [key] = value }) end
    if type(notify) == "function" then notify(key, value) end
  end
end

-- One row per setting, in this order; `make(opts, L)` answers the row's own fields.
local ROWS = {
  { key = "style", make = function(_, L)
      return { type = "string", label = word(L, "STYLE"), desc = word(L, "STYLE_TIP"),
        values = lib.StyleValues(L), default = lib.DEFAULTS.style }
    end },
  { key = "useSkinColors", make = function(_, L)
      return { type = "bool", label = word(L, "USE_SKIN"), desc = word(L, "USE_SKIN_TIP"),
        default = lib.DEFAULTS.useSkinColors }
    end },
  { key = "farColor", color = true, make = function(opts, L)
      return { type = "color", hasAlpha = false, label = word(L, "FAR"), desc = word(L, "FAR_TIP"),
        default = colorDefault(opts, lib.DEFAULTS.farColor) }
    end },
  { key = "nearColor", color = true, make = function(opts, L)
      return { type = "color", hasAlpha = false, label = word(L, "NEAR"), desc = word(L, "NEAR_TIP"),
        default = colorDefault(opts, lib.DEFAULTS.nearColor) }
    end },
  { key = "scale", make = function(_, L)
      return { type = "number", label = word(L, "SCALE"), desc = word(L, "SCALE_TIP"),
        min = lib.SCALE_MIN, max = lib.SCALE_MAX, step = lib.SCALE_STEP, commitOn = "change",
        default = lib.DEFAULTS.scale }
    end },
}

--- The arrow's settings rows, for the host's schema. `opts.paths` names the host's path for each
--- setting (`style`, `useSkinColors`, `farColor`, `nearColor`, `scale`); a setting with no path has
--- no row. `opts.page`, `opts.group` and `opts.subgroup` are copied onto every row; `opts.L`
--- overrides the words; `opts.encodeColor(r, g, b, a)` shapes the color rows' defaults the way the
--- host stores colors (`{ r, g, b, a }` without it); `opts.arrow` (an instance) is configured on
--- every change, then `opts.onChange(key, value)` is called. Answers a fresh list.
function lib.SettingsRows(opts)
  opts = type(opts) == "table" and opts or {}
  local paths = type(opts.paths) == "table" and opts.paths or {}
  local out = {}
  for _, spec in ipairs(ROWS) do
    local path = paths[spec.key]
    if type(path) == "string" and path ~= "" then
      local row = spec.make(opts, opts.L)
      row.path, row.key = path, spec.key
      row.page, row.group, row.subgroup = opts.page, opts.group, opts.subgroup
      row.onChange = onChangeFor(opts, spec.key)
      if spec.color and type(paths.useSkinColors) == "string" then row.disabledIf = paths.useSkinColors end
      out[#out + 1] = row
    end
  end
  return out
end

--- The same rows from an instance: `opts.arrow` is this one.
function lib.__methods:SettingsRows(opts)
  local o = {}
  for k, v in pairs(type(opts) == "table" and opts or {}) do o[k] = v end
  o.arrow = self
  return lib.SettingsRows(o)
end
