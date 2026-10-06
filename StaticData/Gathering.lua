local _, ns = ...

ns.StaticData = ns.StaticData or {}

-- Spells cast to gather from a node or a corpse, by kind. The Gathering tracker also matches by
-- spell name (looked up from these IDs, so in the client's language): every rank and any other
-- version of "Mining" counts too. On client 1.60.1.70235 the Vanilla IDs are named Mining,
-- Herbalism and Skinning; 1235230 (Mining) and 1235236 (Herb Gathering) are Forever's own.
ns.StaticData.GatherSpells = {
    mining = { 2575, 2576, 3564, 10248, 1235230 },
    herbalism = { 2366, 2368, 3570, 11993, 1235236 },
    skinning = { 8613, 8617, 8618, 10768 },
}

-- Trade Goods (item class 7) subclasses that identify a node when the cast itself wasn't visible
-- (a secret spell ID). Class and subclass IDs are locale-free.
ns.StaticData.GatherItemSubclasses = {
    [7] = "mining",    -- Metal & Stone
    [9] = "herbalism", -- Herb
}
ns.StaticData.TRADE_GOODS_CLASS = 7
