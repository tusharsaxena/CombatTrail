local _, NS = ...
-- core/PoolSetup.lua — NS.Pool, the free/active widget pool from LibKa0s-Pool-1.0 (the HUD and the
-- Results window pool their rows through it).

local Pool = LibStub and LibStub("LibKa0s-Pool-1.0", true)

-- Degrade, never error: the array shape, the members the windows call, nothing more.
NS.Pool = Pool or {
    New = function() return { free = {}, active = {} } end,
    Acquire = function(pool, factory)
        local o = table.remove(pool.free)
        if not o then o = factory() end
        pool.active[#pool.active + 1] = o
        o:Show()
        return o
    end,
    ReleaseAll = function(pool, before)
        local active = pool.active
        for i = #active, 1, -1 do
            local o = active[i]
            if before then before(o) end
            o:Hide()
            pool.free[#pool.free + 1] = o
            active[i] = nil
        end
    end,
    Counts = function(pool) return #pool.free, #pool.active end,
}
