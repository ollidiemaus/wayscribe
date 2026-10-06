local _, ns = ...
local L, Compat, Store, Time = ns.L, ns.Compat, ns.Store, ns.Time
local StaticData = ns.StaticData

-- Ore, herbs and skins as per-day counters, never as records (docs/ARCHITECTURE.md §6.4):
--   gather[itemID] = items looted, nodes[kind] = nodes and corpses gathered.
-- A gather cast opens a short window; loot opened inside it counts. Only slots that are actually
-- looted (LOOT_SLOT_CLEARED) count, so full bags don't inflate the numbers.
local WINDOW = 5
local MAX_ITEMS_SHOWN = 6
local KINDS = { "mining", "herbalism", "skinning" }

local function itemName(itemID)
    return Compat.GetItemName(itemID) or L.UNKNOWN_ITEM:format(itemID)
end

-- itemID -> count: "Gathered 23× Copper Ore, 4× Rough Stone and 2 more"
ns.RecordTypes:RegisterCounter("gather", {
    category = "gathering",
    order = 20,
    render = function(bucket)
        local items = {}
        for itemID, count in pairs(bucket) do
            items[#items + 1] = { id = itemID, count = count }
        end
        table.sort(items, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.id < b.id
        end)
        local parts = {}
        for i = 1, math.min(#items, MAX_ITEMS_SHOWN) do
            parts[i] = L.GATHER_ITEM:format(items[i].count, itemName(items[i].id))
        end
        local text = table.concat(parts, L.LIST_SEPARATOR)
        if #items > MAX_ITEMS_SHOWN then
            text = L.LIST_AND:format(text, L.LIST_MORE:format(#items - MAX_ITEMS_SHOWN))
        end
        return L.COUNTER_GATHER:format(text)
    end,
})

-- kind -> count: "Ore deposits mined: 12 · Herbs picked: 5"
ns.RecordTypes:RegisterCounter("nodes", {
    category = "gathering",
    order = 10,
    render = function(bucket)
        local parts = {}
        for _, kind in ipairs(KINDS) do
            if bucket[kind] then
                parts[#parts + 1] = L["NODES_" .. kind:upper()]:format(bucket[kind])
            end
        end
        if #parts == 0 then return nil end
        return table.concat(parts, " · ")
    end,
})

local Gathering = ns.Trackers:New("Gathering", { label = L.TRACKER_GATHERING, tooltip = L.TRACKER_GATHERING_TIP })

-- Spell IDs and, for ranks and versions not listed, spell names in the client's language.
function Gathering:BuildSpellKinds()
    self.kindById, self.kindByName = {}, {}
    for _, kind in ipairs(KINDS) do
        for _, spellID in ipairs(StaticData.GatherSpells[kind]) do
            self.kindById[spellID] = kind
            local name = Compat.GetSpellName(spellID)
            if name then
                self.kindByName[name] = kind
            end
        end
    end
end

function Gathering:OnEnable()
    self:BuildSpellKinds()
    self.window, self.loot, self.lastNode = nil, nil, nil
    self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    self:RegisterEvent("LOOT_READY")
    self:RegisterEvent("LOOT_SLOT_CLEARED")
    self:RegisterEvent("LOOT_CLOSED")
end

function Gathering:KindOfSpell(spellID)
    if not spellID then return nil end
    local kind = self.kindById[spellID]
    if kind then return kind end
    local name = Compat.GetSpellName(spellID)
    return name and self.kindByName[name]
end

function Gathering:UNIT_SPELLCAST_SUCCEEDED(_, castGUID, spellID)
    local kind = self:KindOfSpell(Compat.Safe(spellID, "number"))
    if kind then
        self.window = { kind = kind, expires = Time.Now() + WINDOW, cast = Compat.Safe(castGUID, "string") }
    end
end

-- Fallback when the cast was hidden (secret spell ID): loot from a game object made of ore or herbs.
local function kindFromLoot(slots, source)
    if not (source and source:find("^GameObject")) then return nil end
    for _, item in pairs(slots) do
        local classID, subclassID = Compat.GetItemClass(item.itemID)
        if classID == StaticData.TRADE_GOODS_CLASS and StaticData.GatherItemSubclasses[subclassID] then
            return StaticData.GatherItemSubclasses[subclassID]
        end
    end
    return nil
end

-- May fire more than once for one loot window; the snapshot is simply taken again.
function Gathering:LOOT_READY()
    local window = self.window
    if window and Time.Now() > window.expires then
        window = nil
    end
    local slots, source = Compat.GetLootSlots()
    local kind = window and window.kind or kindFromLoot(slots, source)
    if not kind then
        self.loot = nil
        return
    end
    self.loot = { kind = kind, slots = slots }
    -- One node, even when a vein takes several casts or the window opens twice.
    local node = source or window.cast or window
    if node ~= self.lastNode then
        self.lastNode = node
        Store:Count("nodes", kind, 1)
    end
end

function Gathering:LOOT_SLOT_CLEARED(slot)
    local loot = self.loot
    local item = loot and loot.slots[Compat.Safe(slot, "number")]
    if item then
        loot.slots[slot] = nil
        Store:Count("gather", item.itemID, item.quantity)
    end
end

function Gathering:LOOT_CLOSED()
    self.loot = nil
    self.window = nil
end
