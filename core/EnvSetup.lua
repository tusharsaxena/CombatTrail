local addonName, NS = ...
-- core/EnvSetup.lua — TOC metadata and the addon's own version, from LibKa0s-Env-1.0.

local Env = LibStub and LibStub("LibKa0s-Env-1.0", true)

--- One TOC field for this addon, or nil.
function NS.Meta(field)
    if Env then return Env.GetAddOnMetadata(addonName, field) end
    local addons = _G.C_AddOns
    if addons and addons.GetAddOnMetadata then return addons.GetAddOnMetadata(addonName, field) end
    return nil
end

--- The addon's version: the TOC's, else the fallback core/Namespace.lua names (visible here, as an
--- argument, rather than buried in the library).
function NS.Version()
    if Env then return Env.Version(addonName, NS.FALLBACK_VERSION) or NS.FALLBACK_VERSION end
    return NS.Meta("Version") or NS.FALLBACK_VERSION
end

NS.version = NS.Version()
