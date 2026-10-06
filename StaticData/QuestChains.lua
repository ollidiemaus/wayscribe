local _, ns = ...

ns.StaticData = ns.StaticData or {}

-- Well-known Vanilla quest chains (docs/ARCHITECTURE.md §6.7). A chain is complete when one of its
-- final quests is turned in; there is one final per faction or class variant. The name is the
-- locale string CHAIN_<id>. Quest IDs: Wowhead Classic.
--
-- Bump QuestChainsVersion whenever chains are added: the next login then back-fills chains whose
-- final quest was turned in before they were defined here.
ns.StaticData.QuestChainsVersion = 1

ns.StaticData.QuestChains = {
    -- Attunements and keys
    { id = "ONYXIA", finals = { 6502, 6602 } },        -- Drakefire Amulet / Blood of the Black Dragon Champion
    { id = "UBRS", finals = { 4743 } },                -- Seal of Ascension
    { id = "SCHOLOMANCE", finals = { 5505, 5511 } },   -- The Key to Scholomance (Alliance / Horde)
    { id = "AHNQIRAJ", finals = { 8743 } },            -- Bang a Gong!

    -- Storylines
    { id = "DEFIAS", finals = { 166 } },               -- The Defias Brotherhood
    { id = "MISSING_DIPLOMAT", finals = { 1266 } },    -- The Missing Diplomat
    { id = "TIRION", finals = { 5944 } },              -- In Dreams

    -- Class quests and legendaries
    { id = "BEAR_FORM", finals = { 6001, 6002 } },     -- Body and Heart (Alliance / Horde)
    { id = "DREADSTEED", finals = { 7631 } },          -- Dreadsteed of Xoroth
    { id = "CHARGER", finals = { 7647 } },             -- Judgment and Redemption
    { id = "THUNDERFURY", finals = { 7787 } },         -- Rise, Thunderfury!
}
