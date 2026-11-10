local _, NS = ...
-- modules/MockRotations.lua — the sample rotation (data only): a hunter and the hunter's pet, one
-- table per client, each row one spell that feeds BOTH a sample fight's casts (the lanes, the
-- timeline) and its damage (the HUD, the Results window). modules/MockFights.lua builds both from
-- the same rows, as a real fight makes both. Ported from DPS Race @045f479
-- (modules/MockRotations.lua), cut to the one class the samples fight with: the mockup's Beast
-- Mastery hunter and its pet on Retail, a hunter of the older ranks on WoW Forever.
--
-- PICKED ONCE (clients-§5): the client's rotation is chosen here, at FILE SCOPE, into
-- NS.MOCK_ROTATION, and nothing downstream asks which client it runs on again.
--
-- A ROW: { id (the spell cast), hit (a hit's size against the other rows), from (the first cast,
-- seconds from the fight's start), every (seconds between casts), cd (the base cooldown, ms), ticks +
-- gap (damage over time: this many hits, `gap` seconds apart, after each cast), pet (the pet's own
-- cast and damage), echo (the pet's cast that carries this player cast's damage, a tenth of a second
-- later: Kill Command), passive (damage with no cast of its own: the auto attacks, Beast Cleave),
-- none (a cast that deals no damage of its own: Bestial Wrath), major (a long cooldown), use + item +
-- slot (an on-use trinket or a potion: the Usage section's sample) }.
--
-- The spell and item IDs are the clients' own as far as they are known; the Forever ranks are
-- UNVERIFIED in game (a sample with a wrong ID draws the question-mark icon, nothing else breaks).
-- Names and icons come from the client (C_Spell), as for a real fight.

NS.MockRotations = {
    Retail = {
        { id = 19574, from = 0.4, every = 90, cd = 90000, none = true, major = true },     -- Bestial Wrath
        { id = 359844, from = 0.9, every = 120, cd = 120000, none = true, major = true },  -- Call of the Wild
        { id = 217200, hit = 0.9, from = 1.2, every = 6, cd = 12000, ticks = 4, gap = 2 },  -- Barbed Shot
        { id = 34026, hit = 3.0, from = 1.6, every = 7.5, cd = 7500, echo = 83381 },       -- Kill Command
        { id = 193455, hit = 1.5, from = 2.4, every = 3, cd = 0 },                         -- Cobra Shot
        { id = 466930, hit = 1.4, from = 3.2, every = 10, cd = 10000 },                    -- Black Arrow
        { id = 53351, hit = 2.2, from = 8.0, every = 10, cd = 10000 },                     -- Kill Shot
        { id = 2643, hit = 0.8, from = 5.0, every = 9, cd = 0 },                           -- Multi-Shot
        { id = 75, hit = 0.3, from = 1.0, every = 2.6, passive = true },                   -- Auto Shot
        { id = 16827, hit = 0.9, from = 1.3, every = 3, cd = 0, pet = true },              -- Claw
        { id = 118459, hit = 0.6, from = 5.2, every = 4.5, passive = true, pet = true },   -- Beast Cleave
        { id = 201754, hit = 0.4, from = 1.4, every = 6, passive = true, pet = true },     -- Stomp
        { id = 6603, hit = 0.3, from = 1.1, every = 2, passive = true, pet = true },       -- Auto Attack
        { id = 443124, from = 0.5, every = 120, cd = 120000, none = true, use = "gear", item = 212454, slot = 13 },
        { id = 431932, from = 1.0, every = 300, cd = 300000, none = true, use = "potion", item = 212265 },
    },
    Forever = {
        { id = 19574, from = 0.4, every = 120, cd = 120000, none = true, major = true },   -- Bestial Wrath
        { id = 3045, from = 0.9, every = 300, cd = 300000, none = true, major = true },    -- Rapid Fire
        { id = 25295, hit = 0.5, from = 1.2, every = 15, cd = 0, ticks = 5, gap = 3 },      -- Serpent Sting
        { id = 20904, hit = 3.0, from = 1.8, every = 6, cd = 6000 },                       -- Aimed Shot
        { id = 25294, hit = 1.8, from = 3.0, every = 10, cd = 10000 },                     -- Multi-Shot
        { id = 14287, hit = 1.2, from = 4.2, every = 6, cd = 6000 },                       -- Arcane Shot
        { id = 75, hit = 1.0, from = 1.0, every = 2.8, passive = true },                   -- Auto Shot
        { id = 3009, hit = 0.8, from = 1.3, every = 3, cd = 0, pet = true },               -- Claw
        { id = 17253, hit = 0.9, from = 2.0, every = 10, cd = 10000, pet = true },         -- Bite
        { id = 6603, hit = 0.5, from = 1.1, every = 2, passive = true, pet = true },       -- Auto Attack
        { id = 24352, from = 0.5, every = 120, cd = 120000, none = true, use = "gear", item = 19991, slot = 13 },
        { id = 17531, from = 1.0, every = 120, cd = 120000, none = true, use = "potion", item = 13444 },
    },
}

NS.MOCK_ROTATION = NS.Compat.IsForever() and NS.MockRotations.Forever or NS.MockRotations.Retail
