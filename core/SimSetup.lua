local addonName, NS = ...
-- core/SimSetup.lua — the LibKa0s-Sim-1.0 seam (library-stack-§7). `/kct sim` plays a made-up fight
-- through the lanes, the HUD and into Results (plan Task 5.1). It drives the addon's own modules with
-- made-up data rather than faking a client answer, so every NS.Compat member is declared pure and the
-- seam wraps nothing. The seam still has to exist, because the library's session (the stepper window)
-- binds one. With no library NS.SimSeam is the inert stub and the sim builds no session.

local LibSim = LibStub and LibStub("LibKa0s-Sim-1.0", true)

local function newSeamStub()
    local seam = {}
    function seam.SetProvider() end
    function seam.Live(_, fn, ...) return fn(...) end
    function seam.Keys() return {} end
    function seam.Unwrapped() return {} end
    return seam
end

NS.SimLib = LibSim
if LibSim then
    local pure = {}
    for key, member in pairs(NS.Compat) do
        if type(member) == "function" then pure[key] = true end
    end
    NS.SimSeam = LibSim:NewSeam(NS.Compat, {
        name = addonName,
        pure = pure,
        debug = function(tag, fmt, ...) if NS.Debug then NS.Debug(tag, fmt, ...) end end,
    })
else
    NS.SimSeam = newSeamStub()
end
