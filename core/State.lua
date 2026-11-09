local _, NS = ...
-- core/State.lua — session-only state: never in SavedVariables, reset by every /reload.

NS.State = NS.State or {
    -- The debug-logging flag (debug-logging-§5): default off, window-independent, never persisted.
    debug = false,
}
