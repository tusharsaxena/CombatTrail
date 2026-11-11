local _, NS = ...
-- modules/ProbeCurve.lua — `/ct probe`'s "spell color curve" section (issue #7, probe first): whether
-- the client can map a live spell row's SECRET spell ID to a color natively, so the HUD could draw
-- the pet's rows in the pet color mid-combat without ever comparing the ID. Nothing here colors a
-- row; it only asks the client and describes the answers.
--
-- Out of combat (Report):
--   1. whether C_CurveUtil, CreateColorCurve, Enum.LuaCurveType.Step and CreateColor exist;
--   2. whether a step curve takes points and Evaluate(plain ID) answers the expected color for a
--      pet ID and a non-pet ID.
-- In the probe's samples (Sample, handed the first live spell row's spell ID, secret in combat):
--   3. whether curve:Evaluate(that ID) succeeds, and whether its answer is secret;
--   4. whether that color's channels unpack (GetRGBA) without raising, and are secret;
--   5. whether SetStatusBarColor takes them on a hidden StatusBar.
--
-- SECRETS (spec §3). Every answer is described through NS.Secrets first: a secret is said to be one,
-- never printed, compared or handed to tostring. Each client call runs in pcall.

local ProbeCurve = {}
NS.ProbeCurve = ProbeCurve

local Secrets = NS.Secrets

-- The trial's two colors, and its plain IDs: a pet spell (Claw, 16829, measured on the owner's
-- Forever Hunter) and one that is not (Auto Shot, 75).
local PLAYER = { 0.25, 0.55, 1, 1 }
local PET = { 0.4, 1, 0.4, 1 }
ProbeCurve.PET_ID, ProbeCurve.OTHER_ID = 16829, 75

local curve     -- the trial curve, built once (nil: not yet; false: it could not be built)
local whyNot    -- why it could not be, for the in-combat lines
local bar       -- the hidden StatusBar the color is handed to

local function errText(e)
    if Secrets.IsSealed(e) then return "<secret>" end
    return tostring(e)
end

local function yesNo(b) return b and "yes" or "no" end

local function colorOf(api, c) return api.color(c[1], c[2], c[3], c[4]) end

-- The curve's points: the player color from 0, the pet color on the pet ID alone.
local function addPoints(api, c)
    c:AddPoint(0, colorOf(api, PLAYER))
    c:AddPoint(ProbeCurve.PET_ID, colorOf(api, PET))
    c:AddPoint(ProbeCurve.PET_ID + 1, colorOf(api, PLAYER))
end

-- The step curve, or nil plus the step that raised.
local function build(api)
    local ok, c = pcall(api.create)
    if not ok then return nil, "CreateColorCurve raised: " .. errText(c) end
    if c == nil or Secrets.IsSealed(c) then return nil, "CreateColorCurve answered no curve" end
    local okType, errType = pcall(c.SetType, c, api.step)
    if not okType then return nil, "SetType(Step) raised: " .. errText(errType) end
    local okPoints, errPoints = pcall(addPoints, api, c)
    if not okPoints then return nil, "AddPoint raised: " .. errText(errPoints) end
    return c
end

local function near(a, b) return math.abs(a - b) < 0.01 end

-- Evaluate(id) on a plain ID, against the color `want`: "pet color yes (r, g, b)" or what failed.
local function plainCheck(id, want)
    local ok, color = pcall(curve.Evaluate, curve, id)
    if not ok then return "raised: " .. errText(color) end
    if color == nil or Secrets.IsSealed(color) then return "answered " .. (color == nil and "nil" or "a secret") end
    local okRGB, r, g, b = pcall(color.GetRGBA, color)
    if not okRGB then return "GetRGBA raised: " .. errText(r) end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return "GetRGBA answered no numbers" end
    local match = near(r, want[1]) and near(g, want[2]) and near(b, want[3])
    return ("%s (%.2f, %.2f, %.2f)"):format(yesNo(match), r, g, b)
end

--- The section's out-of-combat lines (checks 1 and 2). Builds the trial curve once.
--- @return table lines
function ProbeCurve.Lines()
    local api = NS.Compat.ColorCurveApi()
    local out = {}
    out[#out + 1] = ("spell color curve: C_CurveUtil %s, CreateColorCurve %s, Enum.LuaCurveType.Step %s, CreateColor %s")
        :format(yesNo(api.util), yesNo(api.create ~= nil), api.step == nil and "missing" or errText(api.step),
            yesNo(api.color ~= nil))
    if curve == nil then
        if not (api.create and api.step ~= nil and api.color) then
            curve, whyNot = false, "the API is missing"
        else
            local c, why = build(api)
            curve, whyNot = c or false, why
        end
    end
    if not curve then
        out[#out + 1] = "spell color curve: not built (" .. whyNot .. ")"
        return out
    end
    out[#out + 1] = ("spell color curve: Evaluate(%d) is the pet color: %s; Evaluate(%d) is the player color: %s")
        :format(ProbeCurve.PET_ID, plainCheck(ProbeCurve.PET_ID, PET), ProbeCurve.OTHER_ID,
            plainCheck(ProbeCurve.OTHER_ID, PLAYER))
    return out
end

local function statusBar()
    if bar then return bar end
    local ok, b = pcall(CreateFrame, "StatusBar", nil, UIParent)
    if not ok then return nil end
    b:Hide()
    b:SetSize(100, 4)
    bar = b
    return bar
end

local function secrecy(v)
    if Secrets.IsSealed(v) then return "secret" end
    if v == nil then return "nil" end
    return "plain"
end

-- Checks 4 and 5 on an Evaluate answer: its channels, then a StatusBar handed them.
local function channelLines(color)
    local okRGB, r, g, b, a = pcall(color.GetRGBA, color)
    if not okRGB then return "GetRGBA raised: " .. errText(r) end
    local text = ("GetRGBA ok (red %s)"):format(secrecy(r))
    local sb = statusBar()
    if not sb then return text .. "; no StatusBar to hand it to" end
    local okSet, err = pcall(sb.SetStatusBarColor, sb, r, g, b, a)
    return text .. "; SetStatusBarColor " .. (okSet and "took it" or ("raised: " .. errText(err)))
end

--- The section's sample line (checks 3 to 5) for spell ID `id` (the first live spell row's, secret in
--- combat). Builds the curve first if the report has not.
--- @param id any
--- @return string line
function ProbeCurve.Sample(id)
    if curve == nil then ProbeCurve.Lines() end
    local head = "spell color curve: spell ID " .. secrecy(id)
    if not curve then return head .. "; no curve (" .. whyNot .. ")" end
    if id == nil then return head .. "; no live spell row to try" end
    local ok, color = pcall(curve.Evaluate, curve, id)
    if not ok then return head .. "; Evaluate raised: " .. errText(color) end
    if color == nil then return head .. "; Evaluate answered nil" end
    if Secrets.IsSealed(color) then return head .. "; Evaluate answered a sealed color" end
    return head .. "; Evaluate ok; " .. channelLines(color)
end

--- Drop the trial curve, so the next report builds it again (the suites' seam).
function ProbeCurve.Reset()
    curve, whyNot = nil, nil
end
