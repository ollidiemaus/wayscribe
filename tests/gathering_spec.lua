local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local COPPER_ORE, ROUGH_STONE, PEACEBLOOM, LIGHT_LEATHER, LINEN = 2770, 2835, 2447, 2318, 2589
local VEIN = "GameObject-0-1-1-1-1731-0000000001"
local CORPSE = "Creature-0-1-1-1-3100-0000000002"

local function start()
    local ns = Stubs.LoadAddon()
    local state = Stubs.state
    state.spellNames = { [2575] = "Mining", [1235230] = "Mining", [2366] = "Herbalism", [8613] = "Skinning", [9999] = "Mining" }
    state.itemNames = { [COPPER_ORE] = "Copper Ore", [ROUGH_STONE] = "Rough Stone", [LIGHT_LEATHER] = "Light Leather" }
    state.itemClasses = { [COPPER_ORE] = { 7, 7 }, [PEACEBLOOM] = { 7, 9 }, [LINEN] = { 7, 5 } }
    Stubs.Login()
    return ns
end

local function cast(spellID)
    Stubs.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-" .. tostring(spellID), spellID)
end

-- Opens a loot window and loots every slot listed in `take` (default: all).
local function loot(source, items, take)
    Stubs.SetLoot({ source = source, items = items })
    Stubs.Fire("LOOT_READY", true)
    for slot = 1, #items do
        if not take or take[slot] then Stubs.LootSlot(slot) end
    end
    Stubs.Fire("LOOT_CLOSED")
    Stubs.SetLoot(nil)
end

local function counters(ns)
    local day = ns.Store:GetDay(20261003)
    return day and day.counters or {}
end

describe("gathering", function()
    it("counts what a gather cast loots, and the node", function()
        local ns = start()
        cast(2575)
        loot(VEIN, { { id = COPPER_ORE, quantity = 3 }, { id = ROUGH_STONE, quantity = 1 } })
        T.same(counters(ns).gather, { [COPPER_ORE] = 3, [ROUGH_STONE] = 1 })
        T.same(counters(ns).nodes, { mining = 1 })
        T.eq(ns.Store:GetStats().records, 0, "counters only, no entries")
        T.same(ns.RecordTypes:RenderCounters(counters(ns)), {
            "Ore deposits mined: 1",
            "Gathered 3× Copper Ore, 1× Rough Stone",
        })
    end)

    it("doesn't count what stays in the loot window", function()
        local ns = start()
        cast(2575)
        loot(VEIN, { { id = COPPER_ORE, quantity = 2 }, { id = ROUGH_STONE, quantity = 1 } }, { true, false })
        T.same(counters(ns).gather, { [COPPER_ORE] = 2 })
    end)

    it("ignores ordinary corpse loot", function()
        local ns = start()
        loot(CORPSE, { { id = LINEN, quantity = 1 } })
        T.eq(counters(ns).gather, nil)
    end)

    it("recognizes other ranks and versions by spell name", function()
        local ns = start()
        cast(9999) -- not in StaticData, but named "Mining"
        loot(VEIN, { { id = COPPER_ORE, quantity = 1 } })
        T.eq(counters(ns).nodes.mining, 1)
    end)

    it("counts skinning by its cast", function()
        local ns = start()
        cast(8613)
        loot(CORPSE, { { id = LIGHT_LEATHER, quantity = 2 } })
        T.same(counters(ns).nodes, { skinning = 1 })
        T.eq(counters(ns).gather[LIGHT_LEATHER], 2)
    end)

    it("falls back to the item type when the cast was secret", function()
        local ns = start()
        cast(Stubs.SECRET)
        loot("GameObject-0-1-1-1-1617-0000000003", { { id = PEACEBLOOM, quantity = 2 } })
        T.same(counters(ns).nodes, { herbalism = 1 })
        T.eq(counters(ns).gather[PEACEBLOOM], 2)
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("counts a vein mined in several casts as one node", function()
        local ns = start()
        cast(2575)
        loot(VEIN, { { id = COPPER_ORE, quantity = 1 } })
        cast(2575)
        loot(VEIN, { { id = COPPER_ORE, quantity = 2 } })
        T.eq(counters(ns).nodes.mining, 1)
        T.eq(counters(ns).gather[COPPER_ORE], 3)
    end)

    it("counts a node once when LOOT_READY fires twice", function()
        local ns = start()
        cast(2575)
        Stubs.SetLoot({ source = VEIN, items = { { id = COPPER_ORE, quantity = 1 } } })
        Stubs.Fire("LOOT_READY", true)
        Stubs.Fire("LOOT_READY", true)
        Stubs.LootSlot(1)
        Stubs.Fire("LOOT_CLOSED")
        T.eq(counters(ns).nodes.mining, 1)
        T.eq(counters(ns).gather[COPPER_ORE], 1)
    end)

    it("the gather window closes after a few seconds", function()
        local ns = start()
        cast(8613)
        Stubs.Advance(6)
        loot(CORPSE, { { id = LIGHT_LEATHER, quantity = 1 } })
        T.eq(counters(ns).gather, nil)
    end)

    it("asks for item names it doesn't have yet and redraws when they arrive", function()
        local ns = start()
        cast(2366)
        loot("GameObject-0-1-1-1-1617-0000000004", { { id = PEACEBLOOM, quantity = 1 } })
        T.same(ns.RecordTypes:RenderCounters(counters(ns))[2], "Gathered 1× item 2447")
        T.truthy(Stubs.state.requestedItems[PEACEBLOOM])

        local redraws = 0
        ns.Bus:On("ITEM_NAMES_LOADED", "test", function() redraws = redraws + 1 end)
        Stubs.state.itemNames[PEACEBLOOM] = "Peacebloom"
        Stubs.Fire("GET_ITEM_INFO_RECEIVED", PEACEBLOOM, true)
        Stubs.Fire("ITEM_DATA_LOAD_RESULT", PEACEBLOOM, true)
        Stubs.Advance(1)
        T.eq(redraws, 1)
        T.same(ns.RecordTypes:RenderCounters(counters(ns))[2], "Gathered 1× Peacebloom")
    end)

    it("summarizes many items", function()
        local ns = start()
        for itemID = 1, 8 do
            ns.Store:Count("gather", itemID, 10 - itemID)
            Stubs.state.itemNames[itemID] = "Item" .. itemID
        end
        local line = ns.RecordTypes:RenderCounters(counters(ns))[1]
        T.eq(line, "Gathered 9× Item1, 8× Item2, 7× Item3, 6× Item4, 5× Item5, 4× Item6 and 2 more")
    end)
end)
