local _, NS = ...
-- defaults/IgnoreSeeds.lua — the spells each lane hides out of the box, per client (spec §4, Ignored
-- spells): the auto-repeat attacks, whose every swing or shot fires UNIT_SPELLCAST_SUCCEEDED and is
-- never a press. Data only.
--
-- PICKED ONCE (clients-§5): the client's list is chosen here, at FILE SCOPE, into NS.IGNORE_SEEDS,
-- and nothing downstream asks which client it runs on again. defaults/Profile.lua builds each lane's
-- `ignore` set from it, and the Lanes page's "reset to seed" (plan Task 1.4) restores it.
--
-- player  Auto Attack 6603, Auto Shot 75, Shoot 5019 (a wand), on both clients.
-- pet     Auto Attack 6603, on both clients. The pet's own melee swings do not fire SUCCEEDED on
--         Retail; any further pet auto-attack ID a client turns out to send is added to that client's
--         list when `/ct probe` reports it (spec §10's in-game check list).
--
-- LOAD-BEARING: reads NS.Compat (core/Compat.lua) at FILE SCOPE, and defaults/Profile.lua reads
-- NS.IGNORE_SEEDS at FILE SCOPE, so this file sits between them.

NS.IgnoreSeeds = {
    Retail = {
        player = { 6603, 75, 5019 },
        pet    = { 6603 },
    },
    Forever = {
        player = { 6603, 75, 5019 },
        pet    = { 6603 },
    },
}

NS.IGNORE_SEEDS = NS.Compat.IsForever() and NS.IgnoreSeeds.Forever or NS.IgnoreSeeds.Retail

--- A lane's seed list as the stored set shape, { [spellID] = true }: a fresh table per call, so the
--- two lanes' defaults (and a reset) never share one.
--- @param laneKey string "player" | "pet"
--- @return table
function NS.IgnoreSeedSet(laneKey)
    local out = {}
    for _, id in ipairs(NS.IGNORE_SEEDS[laneKey] or {}) do out[id] = true end
    return out
end
