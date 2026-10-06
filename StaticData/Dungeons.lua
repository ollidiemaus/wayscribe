local _, ns = ...

ns.StaticData = ns.StaticData or {}

-- The boss kills that complete an instance (docs/ARCHITECTURE.md §6.6), keyed by instanceID
-- (GetInstanceInfo's 8th return) and then encounterID (ENCOUNTER_END's 1st argument). The value is
-- true, or a wing key where several wings share one instanceID. Some dungeons list one encounter
-- per difficulty variant. Source: DungeonEncounter.db2 of client 1.60.1.70235.
--
-- An instance missing here still gets runs; they end as "visited" instead of "cleared".
ns.StaticData.Dungeons = {
    -- Dungeons
    [389] = { [2733] = true, [2735] = true },                      -- Ragefire Chasm: Taragaman, Bazzalan
    [43] = { [591] = true, [592] = true },                         -- Wailing Caverns: Verdan, Mutanus
    [36] = { [2747] = true },                                      -- Deadmines: Edwin VanCleef
    [33] = { [2755] = true },                                      -- Shadowfang Keep: Archmage Arugal
    [48] = { [2910] = true, [2767] = true, [2891] = true },        -- Blackfathom Deeps: Aku'mai
    [34] = { [2760] = true },                                      -- Stormwind Stockade: Bazil Thredd
    [90] = { [2772] = true, [2940] = true },                       -- Gnomeregan: Mekgineer Thermaplugg
    [47] = { [2778] = true },                                      -- Razorfen Kraul: Charlga Razorflank
    [189] = {                                                      -- Scarlet Monastery
        [2779] = "graveyard",                                      -- Bloodmage Thalnos
        [447] = "library",                                         -- Arcanist Doan
        [448] = "armory",                                          -- Herod
        [450] = "cathedral",                                       -- High Inquisitor Whitemane
    },
    [129] = { [2785] = true },                                     -- Razorfen Downs: Amnennar the Coldbringer
    [70] = { [554] = true },                                       -- Uldaman: Archaedas
    [209] = { [600] = true },                                      -- Zul'Farrak: Chief Ukorz Sandscalp
    [349] = { [429] = true },                                      -- Maraudon: Princess Theradras
    [109] = { [3584] = true, [493] = true, [2959] = true },        -- Sunken Temple: Shade of Eranikus
    [230] = { [2790] = true },                                     -- Blackrock Depths: Emperor Dagran Thaurissan
    [229] = { [275] = "lower", [3069] = "upper" },                 -- Blackrock Spire: Wyrmthalak, Drakkisath
    [429] = { [346] = "east", [361] = "west", [368] = "north" },   -- Dire Maul: Alzzin, Tortheldrin, King Gordok
    [289] = { [2801] = true },                                     -- Scholomance: Darkmaster Gandling
    [329] = { [478] = "living", [484] = "undead" },                -- Stratholme: Balnazzar, Baron Rivendare

    -- Raids
    [409] = { [672] = true },                                      -- Molten Core: Ragnaros
    [249] = { [1084] = true },                                     -- Onyxia's Lair: Onyxia
    [469] = { [617] = true },                                      -- Blackwing Lair: Nefarian
    [309] = { [793] = true },                                      -- Zul'Gurub: Hakkar
    [509] = { [723] = true },                                      -- Ruins of Ahn'Qiraj: Ossirian the Unscarred
    [531] = { [717] = true },                                      -- Ahn'Qiraj Temple: C'Thun
    [533] = { [1114] = true },                                     -- Naxxramas: Kel'Thuzad
}
