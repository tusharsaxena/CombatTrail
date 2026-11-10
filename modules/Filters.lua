local _, NS = ...
-- modules/Filters.lua — the recording filters (spec §5, plan Task 2.5): every fight is tracked live,
-- but one is STORED only if it passes these. The minimum length (`history.minLength`, 30 s), bosses
-- only (`history.bossesOnly`, off) and one toggle per content kind (`history.content.<kind>`, every
-- kind on but scenarios). The content keys are modules/Identity.lua's Identity.CONTENT for this
-- client: Mythic+, delves and arenas are Retail-only, so on WoW Forever their toggles are absent
-- (clients-§4) and no identity ever names them there.
--
-- PURE over the identity (Identity.Resolve's plain table) and the settings, read at CALL time; the
-- recorder (modules/Recorder.lua) is the one caller.

local Filters = {}
NS.Filters = Filters

local function setting(key)
    return NS.GetSetting and NS.GetSetting("history." .. key)
end

--- Whether a fight with `identity`, `duration` seconds long, is stored.
--- @param identity table|nil  an Identity.Resolve result
--- @param duration number|nil  seconds
--- @return boolean ok
--- @return string|nil reason  "short" (under the minimum length) or "filtered" (bosses only, or its
---   content kind switched off); nil when it passes
function Filters.Passes(identity, duration)
    local minLength = tonumber(setting("minLength")) or 0
    if type(duration) ~= "number" or duration < minLength or duration <= 0 then return false, "short" end
    if type(identity) ~= "table" then return false, "filtered" end
    if setting("bossesOnly") == true and identity.isBoss ~= true then return false, "filtered" end
    local content = setting("content")
    if type(content) ~= "table" or content[identity.content] ~= true then return false, "filtered" end
    return true
end
