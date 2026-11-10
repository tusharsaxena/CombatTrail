local _, NS = ...
-- defaults/Dummies.lua — the training dummies, per client (spec §5, Identity): creature ID -> the
-- dummy's name. A fight whose primary target is one of these is "dummy" content (modules/Identity.lua),
-- whatever zone it was fought in. Data only.
--
-- From DPS Race @045f479 (defaults/Dummies.lua), without its race-only dummy categories (single,
-- cleave, boss-level, ...): Combat Trail boards a dummy by its creature ID like any other target, so a
-- category has nothing to group. DPS Race's own-dummies list (modules/DummyList.lua, a profile setting
-- and its capture verb) is not ported: the catalog is the seed, and a missing dummy is added here.
-- A row is added from a MEASUREMENT (a creature ID read in game), never guessed; each keeps the date
-- and the places DPS Race measured it.
--
-- PICKED ONCE (clients-§5): the client's list is chosen here, at FILE SCOPE, into NS.DUMMIES, and
-- nothing downstream asks which client it runs on again.
--
-- Forever is EMPTY BY DECISION (spec §5): no dummy creature ID has been measured on WoW Forever, and
-- the Retail IDs are not assumed to carry over. A Forever dummy reads as open-world content until its
-- ID is measured in game and added to that list.
--
-- LOAD-BEARING: reads NS.Compat (core/Compat.lua) at FILE SCOPE.

NS.Dummies = {
    Retail = {
        [31146] = "Raider's Training Dummy",         -- 2026-11-01, City of Ironforge, Orgrimmar, Shrine of Seven Stars, Stormwind City, The Exodar, Thunder Bluff
        [65310] = "Turnip Punching Bag",             -- 2026-11-01, Silvermoon City
        [67127] = "Training Dummy",                  -- 2026-11-01, Shrine of Seven Stars
        [114832] = "PvP Training Dummy",              -- 2026-11-01, Stormwind City
        [126781] = "Training Dummy",                  -- 2026-11-01, Tiragarde Sound
        [131983] = "Raider's Training Dummy",         -- 2026-11-01, Tiragarde Sound
        [131989] = "Training Dummy",                  -- 2026-11-01, Tiragarde Sound
        [131992] = "Dungeoneer's Training Dummy",     -- 2026-11-01, Tiragarde Sound
        [144078] = "Dungeoneer's Training Dummy",     -- 2026-11-01, Zuldazar
        [144081] = "Training Dummy",                  -- 2026-11-01, Zuldazar
        [144082] = "Training Dummy",                  -- 2026-11-01, Zuldazar
        [144085] = "Training Dummy",                  -- 2026-11-01, Zuldazar
        [144086] = "Raider's Training Dummy",         -- 2026-11-01, Zuldazar
        [153285] = "Training Dummy",                  -- 2026-11-01, City of Ironforge, Orgrimmar, The Exodar, Thunder Bluff
        [153292] = "Training Dummy",                  -- 2026-11-01, Stormwind City
        [189617] = "Boulderfist",                     -- 2026-11-01, Valdrakken
        [189632] = "Animated Duelist",                -- 2026-11-01, Valdrakken
        [194643] = "Dungeoneer's Training Dummy",     -- 2026-11-01, Valdrakken
        [194644] = "Dungeoneer's Training Dummy",     -- 2026-11-01, Valdrakken
        [194648] = "Training Dummy",                  -- 2026-11-01, Valdrakken
        [194649] = "Normal Tank Dummy",               -- 2026-11-01, Valdrakken
        [196394] = "Tuskarr Training Dummy",          -- 2026-11-01, Silvermoon City
        [197833] = "PvP Training Dummy",              -- 2026-11-01, Valdrakken
        [198594] = "Cleave Training Dummy",           -- 2026-11-01, Valdrakken
        [199057] = "Black Dragon's Challenge Dummy",  -- 2026-11-01, Silvermoon City
        [216458] = "Sparring Dummy",                  -- 2026-11-01, Bel'ameth
        [219250] = "PvP Training Dummy",              -- 2026-11-01, Dornogal
        [225976] = "Normal Tank Dummy",               -- 2026-11-01, Dornogal
        [225977] = "Dungeoneer's Training Dummy",     -- 2026-11-01, Dornogal
        [225978] = "Crystalmaw",                      -- 2026-11-01, Dornogal
        [225982] = "Cleave Training Dummy",           -- 2026-11-01, Dornogal
        [225983] = "Dungeoneer's Training Dummy",     -- 2026-11-01, Dornogal
        [225984] = "Training Dummy",                  -- 2026-11-01, Dornogal
        [225985] = "Kelpfist",                        -- 2026-11-01, Dornogal
        [243166] = "Normal Tank Dummy",               -- 2026-11-01, Silvermoon City
        [243167] = "Dungeoneer's Training Dummy",     -- 2026-10-23, Silvermoon
        [243168] = "Dungeoneer's Training Dummy",     -- 2026-10-23, Silvermoon
        [243205] = "Reinforced Golem",                -- 2026-10-23, Silvermoon
        [243206] = "Heavyweight Golem",               -- 2026-11-01, Silvermoon City
        [243207] = "Training Dummy",                  -- 2026-11-01, Silvermoon City
        [243208] = "Cleave Training Dummy",           -- 2026-10-23, Silvermoon
        [243211] = "PvP Training Dummy",              -- MultiMeters, 2026-09-26
    },
    Forever = {
        -- Empty by decision: no Forever dummy creature ID is measured yet (see the header).
    },
}

NS.DUMMIES = NS.Compat.IsForever() and NS.Dummies.Forever or NS.Dummies.Retail

--- The training dummy's name for a creature ID, or nil: not a dummy on this client, or an ID that is
--- nil or secret (a secret as a table key raises in the client, so it is refused first).
--- @param creatureID number|nil
--- @return string|nil
function NS.DummyName(creatureID)
    if not NS.Secrets.IsSafeKey(creatureID) then return nil end
    return NS.DUMMIES[creatureID]
end
