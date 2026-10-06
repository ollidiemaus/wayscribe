local _, ns = ...

ns.StaticData = ns.StaticData or {}

-- Spells that carry the caster far away (docs/ARCHITECTURE.md §6.8): a cast of one followed by a
-- jump of the player's position gets a journal entry and two map icons. The Footsteps tracker also
-- matches by spell name (looked up from these IDs, so in the client's language), so other ranks and
-- Forever's own versions count too. Vanilla IDs; /ws probe prints their names on the client.
ns.StaticData.TravelSpells = {
    8690, -- Hearthstone
    556,  -- Astral Recall (shaman)
    3561, -- Teleport: Stormwind
    3562, -- Teleport: Ironforge
    3563, -- Teleport: Undercity
    3565, -- Teleport: Darnassus
    3566, -- Teleport: Thunder Bluff
    3567, -- Teleport: Orgrimmar
}
