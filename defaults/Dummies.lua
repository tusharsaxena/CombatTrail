local _, NS = ...
-- defaults/Dummies.lua — the training dummies' seed, per client (spec §5, Identity; race spec §9):
-- creature ID -> { name, category }. A fight whose primary target is a dummy is "dummy" content
-- (modules/Identity.lua), whatever zone it was fought in. Data only: modules/Dummies.lua answers the
-- seed together with the player's own list (a profile setting) and the captures.
--
-- From DPS Race @f8078c7 (defaults/Dummies.lua), categories included: single, cleave, dungeoneer,
-- boss and pvp (modules/Dummies.lua's CATEGORIES). A category matters only to races, whose boards
-- split by it; a fight's board is its target's, whatever the category.
-- A row is added from a MEASUREMENT (a creature ID read in game, `/ct dummy capture`), never
-- guessed; each keeps the date and the places DPS Race measured it.
--
-- PICKED ONCE (clients-§5): the client's seed is chosen here, at FILE SCOPE, into NS.DUMMY_SEED, and
-- nothing downstream asks which client it runs on again.
--
-- Forever is EMPTY BY DECISION (spec §5): no dummy creature ID has been measured on WoW Forever, and
-- the Retail IDs are not assumed to carry over. A Forever dummy reads as open-world content until the
-- player adds it to their own list (the History page's Training dummies tab, `/ct dummy add`) or its
-- ID is measured in game and added here.
--
-- LOAD-BEARING: reads NS.Compat (core/Compat.lua) at FILE SCOPE.

NS.DummySeeds = {
    Retail = {
        [31146] = { name = "Raider's Training Dummy",        category = "boss"       },  -- 2026-11-01, City of Ironforge, Orgrimmar, Shrine of Seven Stars, Stormwind City, The Exodar, Thunder Bluff
        [65310] = { name = "Turnip Punching Bag",            category = "boss"       },  -- 2026-11-01, Silvermoon City
        [67127] = { name = "Training Dummy",                 category = "single"     },  -- 2026-11-01, Shrine of Seven Stars
        [114832] = { name = "PvP Training Dummy",             category = "pvp"        },  -- 2026-11-01, Stormwind City
        [126781] = { name = "Training Dummy",                 category = "single"     },  -- 2026-11-01, Tiragarde Sound
        [131983] = { name = "Raider's Training Dummy",        category = "boss"       },  -- 2026-11-01, Tiragarde Sound
        [131989] = { name = "Training Dummy",                 category = "single"     },  -- 2026-11-01, Tiragarde Sound
        [131992] = { name = "Dungeoneer's Training Dummy",    category = "dungeoneer" },  -- 2026-11-01, Tiragarde Sound
        [144078] = { name = "Dungeoneer's Training Dummy",    category = "dungeoneer" },  -- 2026-11-01, Zuldazar
        [144081] = { name = "Training Dummy",                 category = "single"     },  -- 2026-11-01, Zuldazar
        [144082] = { name = "Training Dummy",                 category = "single"     },  -- 2026-11-01, Zuldazar
        [144085] = { name = "Training Dummy",                 category = "single"     },  -- 2026-11-01, Zuldazar
        [144086] = { name = "Raider's Training Dummy",        category = "boss"       },  -- 2026-11-01, Zuldazar
        [153285] = { name = "Training Dummy",                 category = "single"     },  -- 2026-11-01, City of Ironforge, Orgrimmar, The Exodar, Thunder Bluff
        [153292] = { name = "Training Dummy",                 category = "single"     },  -- 2026-11-01, Stormwind City
        [189617] = { name = "Boulderfist",                    category = "boss"       },  -- 2026-11-01, Valdrakken
        [189632] = { name = "Animated Duelist",               category = "boss"       },  -- 2026-11-01, Valdrakken
        [194643] = { name = "Dungeoneer's Training Dummy",    category = "dungeoneer" },  -- 2026-11-01, Valdrakken
        [194644] = { name = "Dungeoneer's Training Dummy",    category = "dungeoneer" },  -- 2026-11-01, Valdrakken
        [194648] = { name = "Training Dummy",                 category = "single"     },  -- 2026-11-01, Valdrakken
        [194649] = { name = "Normal Tank Dummy",              category = "single"     },  -- 2026-11-01, Valdrakken
        [196394] = { name = "Tuskarr Training Dummy",         category = "boss"       },  -- 2026-11-01, Silvermoon City
        [197833] = { name = "PvP Training Dummy",             category = "pvp"        },  -- 2026-11-01, Valdrakken
        [198594] = { name = "Cleave Training Dummy",          category = "cleave"     },  -- 2026-11-01, Valdrakken
        [199057] = { name = "Black Dragon's Challenge Dummy", category = "boss"       },  -- 2026-11-01, Silvermoon City
        [216458] = { name = "Sparring Dummy",                 category = "single"     },  -- 2026-11-01, Bel'ameth
        [219250] = { name = "PvP Training Dummy",             category = "pvp"        },  -- 2026-11-01, Dornogal
        [225976] = { name = "Normal Tank Dummy",              category = "single"     },  -- 2026-11-01, Dornogal
        [225977] = { name = "Dungeoneer's Training Dummy",    category = "dungeoneer" },  -- 2026-11-01, Dornogal
        [225978] = { name = "Crystalmaw",                     category = "boss"       },  -- 2026-11-01, Dornogal
        [225982] = { name = "Cleave Training Dummy",          category = "cleave"     },  -- 2026-11-01, Dornogal
        [225983] = { name = "Dungeoneer's Training Dummy",    category = "dungeoneer" },  -- 2026-11-01, Dornogal
        [225984] = { name = "Training Dummy",                 category = "single"     },  -- 2026-11-01, Dornogal
        [225985] = { name = "Kelpfist",                       category = "boss"       },  -- 2026-11-01, Dornogal
        [243166] = { name = "Normal Tank Dummy",              category = "single"     },  -- 2026-11-01, Silvermoon City
        [243167] = { name = "Dungeoneer's Training Dummy",    category = "dungeoneer" },  -- 2026-10-23, Silvermoon
        [243168] = { name = "Dungeoneer's Training Dummy",    category = "dungeoneer" },  -- 2026-10-23, Silvermoon
        [243205] = { name = "Reinforced Golem",               category = "boss"       },  -- 2026-10-23, Silvermoon
        [243206] = { name = "Heavyweight Golem",              category = "boss"       },  -- 2026-11-01, Silvermoon City
        [243207] = { name = "Training Dummy",                 category = "single"     },  -- 2026-11-01, Silvermoon City
        [243208] = { name = "Cleave Training Dummy",          category = "cleave"     },  -- 2026-10-23, Silvermoon
        [243211] = { name = "PvP Training Dummy",             category = "pvp"        },  -- MultiMeters, 2026-09-26
    },
    Forever = {
        -- Empty by decision: no Forever dummy creature ID is measured yet (see the header).
    },
}

NS.DUMMY_SEED = NS.Compat.IsForever() and NS.DummySeeds.Forever or NS.DummySeeds.Retail
