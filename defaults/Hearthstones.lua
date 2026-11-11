local _, NS = ...
-- defaults/Hearthstones.lua — every hearthstone variant's spell ID (Race mode, plan Task B1): the
-- late-cast ignore list's 8690 entry stands for all of them (modules/LateIgnore.lua). Data, not
-- settings: the list's default is in defaults/Profile.lua (`race.lateIgnore`). Ported unchanged from
-- DPS Race @f8078c7 (defaults/Hearthstones.lua).
--
-- Built from the wago.tools DB2 exports of 2026-10-28 (the Retail build it served then, 12.1.5.70575), by
-- four rules:
--   1. every spell whose SpellCategories ChargeCategory is 2309, the shared hearthstone cooldown
--      (8690 and the toys);
--   2. plus every spell with a SpellEffect of Effect 252 (teleport) and ImplicitTarget 9 (the bind
--      point) that a toy or an item casts (ItemEffect, ItemXItemEffect);
--   3. plus the Dalaran Hearthstone 222695 and the Garrison Hearthstone 171253 (cooldowns of their own,
--      fixed destinations);
--   4. minus the class spell Astral Recall 556 (a player can add it), and minus the teleports home no
--      item casts or that are test data: 1 and 3 ("(OLD)"), 70195 ("[PH]"), 307896 ("TEST"), 1223998
--      ("[DNT]"), 49493 (Mole Machine Port to Hearth) and 188816 (Teleport): no ItemEffect casts
--      either one, and neither is on the hearthstone cooldown.
-- Scrolls of Recall and the other consumables and items that send a player home on the hearthstone's
-- cooldown are kept (DPS Race's owner call, 2026-10-28).
--
-- To refresh it for a new build: download SpellCategories, SpellEffect, SpellName, ItemEffect and
-- ItemXItemEffect from wago.tools, re-run the four rules, diff the result against this table, and
-- update it and its pin test (tests/test_late_ignore.lua: the count, 8690, 222695 and 171253 in, 556
-- out). The names in the comments are enUS, for review only.

NS.HEARTHSTONE_SPELLS = {
    8690,     -- Hearthstone
    222695,   -- Dalaran Hearthstone
    171253,   -- Garrison Hearthstone
    39937,    -- There's No Place Like Home
    48129,    -- Scroll of Recall
    54403,    -- Scourgestone
    60320,    -- Scroll of Recall
    60321,    -- Scroll of Recall
    75136,    -- Ethereal Portal
    94719,    -- The Innkeeper's Daughter
    136508,   -- Dark Portal
    191329,   -- Hearthstone
    231504,   -- Town Portal
    231505,   -- Town Portal
    278244,   -- Greatfather Winter's Hearthstone
    278559,   -- Headless Horseman's Hearthstone
    279066,   -- Weary Spirit Binding Return
    279741,   -- Scroll of Luxurious Recall
    285362,   -- Lunar Elder's Hearthstone
    285424,   -- Peddlefeet's Lovely Hearthstone
    286031,   -- Noble Gardener's Hearthstone
    286331,   -- Fire Eater's Hearthstone
    286353,   -- Brewfest Reveler's Hearthstone
    298068,   -- Holographic Digitalization Hearthstone
    300047,   -- Mountebank's Colorful Cloak
    308742,   -- Eternal Traveler's Hearthstone
    326064,   -- Ardenweald Hearthstone
    340200,   -- Necrolord Hearthstone
    342122,   -- Venthyr Sinstone
    345393,   -- Kyrian Hearthstone
    350944,   -- Town Portal
    363799,   -- Dominated Hearthstone
    366945,   -- Enlightened Hearthstone
    367013,   -- Broker Translocation Matrix
    375357,   -- Timewalker's Hearthstone
    391042,   -- Ohn'ir Windsage's Hearthstone
    401802,   -- Hearthstone
    412555,   -- Path of the Naaru
    420418,   -- Deepdweller's Earthen Hearthstone
    422284,   -- Hearthstone of the Flame
    431644,   -- Stone of the Hearth
    438606,   -- Draenic Hologem
    463481,   -- Notorious Thread's Hearthstone
    1217281,  -- Redeployment Module
    1220729,  -- Explosive Hearthstone
    1240219,  -- P.O.S.T. Master's Express Hearthstone
    1242509,  -- Cosmic Hearthstone
    1250878,  -- Timerunner's Hearthstone
    1254117,  -- Lightforged Phase Beacon
    1261979,  -- Lightcalled Hearthstone
    1270583,  -- Naaru's Enfold
    1270814,  -- Preyseeker's Hearthstone
    1273401,  -- Corewarden's Hearthstone
    1286909,  -- Mycomancer's Hearthspore
    1299014,  -- Mycomancer's Hearthspore
    1299513,  -- Lightveil Hearth Beacon
    1310234,  -- Hiveborne Hearthstone
    1310840,  -- Wood-Cursed Hearthstone
    1311934,  -- Shadeweaver's Hearthstone
}
