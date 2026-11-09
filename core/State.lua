local _, NS = ...
-- core/State.lua — session-only state: never in SavedVariables, reset by every /reload.

NS.State = NS.State or {
    -- The debug-logging flag (debug-logging-§5): default off, window-independent, never persisted.
    debug = false,
    -- Test mode and Sim mode until their modules arrive (core/CombatTrail.lua, plan Task 5.1).
    testMode = false,
    simMode = false,
}
