local _, ns = ...

ns.StaticData = ns.StaticData or {}

-- Spells that carry the caster far away (docs/ARCHITECTURE.md §6.8): a cast of one followed by a
-- jump of the player's position gets a journal entry and two map icons. The Footsteps tracker also
-- matches by spell name (looked up from these IDs, so in the client's language), so other spells of
-- the same name count too: Forever's further "Hearthstone" (1303762, 1315212), "Teleport: Moonglade"
-- (19027) and "Teleport: Dalaran" (1297660, 1308652). IDs from SpellName.db2 of client
-- 1.60.1.70235 (wago.tools); /ws probe prints their names on the client.
-- Left out: "Teleport to ..." spells (boss and NPC effects) and the Lunar Festival's teleports,
-- which its NPCs cast on the player.
ns.StaticData.TravelSpells = {
    -- Hearthstones
    8690,    -- Hearthstone
    1235126, -- Hearthstone of the Dawn (Forever)
    1312670, -- Crumbling Hearthstone (Forever)
    -- Class spells
    556,     -- Astral Recall (shaman)
    18960,   -- Teleport: Moonglade (druid)
    3561,    -- Teleport: Stormwind (mage)
    3562,    -- Teleport: Ironforge
    3563,    -- Teleport: Undercity
    3565,    -- Teleport: Darnassus
    3566,    -- Teleport: Thunder Bluff
    3567,    -- Teleport: Orgrimmar
    1297659, -- Teleport: Dalaran (Forever)
    -- Engineering and other items
    23486,   -- Dimensional Ripper - Everlook
    23489,   -- Ultrasafe Transporter - Gadgetzan
    23491,   -- Ultrasafe Transporter: Gadgetzan
    1226213, -- Semisafe Transporter: New Avalon (Forever)
    1266932, -- EZ-Thro Field Transporter: Gadgetzan (Forever)
    1266934, -- EZ and SAF Field Transporter: Mt. Hyjal (Forever)
    1266936, -- Dimensional Transporter - Mt. Hyjal (Forever)
}
