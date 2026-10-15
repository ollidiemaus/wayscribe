local _, ns = ...
local L, Compat, Store, Trace, YearCards = ns.L, ns.Compat, ns.Store, ns.Trace, ns.YearCards

-- Notable gear (docs/ARCHITECTURE.md §6.15): the first rare item the character equips, and every
-- epic or better item, once per item. The tracker keeps every item it has seen worn,
-- state.gear = { items = { [itemID] = true } }, so re-equipping an item or a second copy repeats
-- nothing, and what is worn at the first look is taken silently. "Seen before" is also the journal's:
-- the first rare is the firsts key GEAR:RARE, and a journal restored without the state gives its
-- epics back as seen.
local ICON = "Interface\\Icons\\INV_Chest_Plate16"
local FIRST_SLOT, LAST_SLOT = 1, 19 -- INVSLOT_HEAD to INVSLOT_TABARD; the bag slots come after
local RARE, EPIC, LEGENDARY, ARTIFACT = 3, 4, 5, 6 -- Heirloom (7) and WoW Token (8) aren't found gear

local function itemName(data)
    return data.name or Compat.GetItemName(data.item) or L.UNKNOWN_ITEM:format(data.item)
end

local function isEpic(quality)
    return quality >= EPIC and quality <= ARTIFACT
end

-- "Equipped your first rare item: Thrash Blade", "Equipped an epic item: Ironfoe"
ns.RecordTypes:Register("GEAR", {
    version = 1,
    category = "progress",
    fields = { item = "number", quality = "number", name = "string?" },
    firstKey = function(data) return data.quality == RARE and "GEAR:RARE" or "GEAR:EPIC" end,
    -- The epics worn, and the first rare and first epic (Your Year).
    rollup = function(rollup, data, record)
        local gear = rollup.gear or { epics = 0 }
        rollup.gear = gear
        if data.quality ~= RARE then gear.epics = gear.epics + 1 end
        if record.first then
            gear[data.quality == RARE and "rare" or "epic"] = { item = data.item, name = data.name, ts = record.ts }
        end
    end,
    merge = function(target, source)
        if not source.gear then return end
        local gear = target.gear or { epics = 0 }
        target.gear = gear
        gear.epics = gear.epics + source.gear.epics
        for _, key in ipairs({ "rare", "epic" }) do
            local other = source.gear[key]
            if other and (not gear[key] or other.ts < gear[key].ts) then
                gear[key] = { item = other.item, name = other.name, ts = other.ts }
            end
        end
    end,
    render = function(data, record)
        local pattern
        if data.quality == RARE then
            pattern = L.GEAR_FIRST_RARE
        elseif data.quality >= LEGENDARY then
            pattern = L.GEAR_LEGENDARY
        else
            pattern = record.first and L.GEAR_FIRST_EPIC or L.GEAR_EPIC
        end
        return pattern:format(itemName(data))
    end,
})

-- "2 epic items worn", then the dates of the first rare and the first epic. After Bosses.
YearCards:Register({
    id = "gear",
    order = 35,
    build = function(summary)
        local gear = summary.rollup.gear
        if not gear then return nil end
        local card = { title = L.CARD_GEAR, icon = ICON, lines = {} }
        if gear.epics > 0 then
            card.big, card.caption = YearCards.Number(gear.epics), YearCards.Pattern("CARD_GEAR_EPICS", gear.epics)
        end
        if gear.rare then
            card.lines[#card.lines + 1] = L.CARD_GEAR_FIRST_RARE:format(itemName(gear.rare), YearCards.Date(gear.rare.ts))
        end
        if gear.epic then
            card.lines[#card.lines + 1] = L.CARD_GEAR_FIRST_EPIC:format(itemName(gear.epic), YearCards.Date(gear.epic.ts))
        end
        return card
    end,
})

local Gear = ns.Trackers:New("Gear", { label = L.TRACKER_GEAR, tooltip = L.TRACKER_GEAR_TIP })

function Gear:OnEnable()
    self:TryRegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:AskForLook("enable")
end

function Gear:PLAYER_ENTERING_WORLD()
    self:AskForLook("PLAYER_ENTERING_WORLD")
end

-- The items seen worn, as a copy, so a look that stops at a failed write leaves the state as it was;
-- nil before the first look. Without the state, the journal's own entries are seen.
local function knownItems()
    local saved = Store:GetState("gear")
    if type(saved) ~= "table" or type(saved.items) ~= "table" then return nil end
    local known = {}
    for item in pairs(saved.items) do known[item] = true end
    return known
end

local function journalItems()
    local known = {}
    for _, record in ipairs(Store:GetRecordsOfType("GEAR")) do known[record.data.item] = true end
    return known
end

-- Takes one worn item into `known` and writes its entry if it is notable; returns how it ended.
local function consider(item, quality, known)
    if known[item] then return "known" end
    if not quality then return "no quality" end -- not loaded yet: the next look reads it again
    if quality ~= RARE and not isEpic(quality) or quality == RARE and Store:GetFirst("GEAR:RARE") then
        known[item] = true
        return quality == RARE and "later rare" or "not notable"
    end
    local first = not Store:GetFirst(quality == RARE and "GEAR:RARE" or "GEAR:EPIC")
    local record, reason = Store:Append("GEAR", { item = item, quality = quality, name = Compat.GetItemName(item) })
    if not record then return "not written: " .. tostring(reason) end
    known[item] = true
    if quality == RARE then return "first rare" end
    return first and "first epic" or "epic"
end

local function save(known)
    return Store:SetState("gear", { items = known })
end

-- One slot, on PLAYER_EQUIPMENT_CHANGED. Before the first look, the event asks for it instead, and
-- so does an item whose quality isn't loaded yet, to read it again a second later.
function Gear:PLAYER_EQUIPMENT_CHANGED(slot)
    slot = Compat.Safe(slot, "number")
    if not slot or slot < FIRST_SLOT or slot > LAST_SLOT then return end
    local known = knownItems()
    if not known then return self:AskForLook("PLAYER_EQUIPMENT_CHANGED") end
    local item, quality, rawItem, rawQuality = Compat.GetEquippedItem(slot)
    local outcome
    if item == nil then
        outcome = "unreadable"
    elseif item == false then
        outcome = "empty"
    elseif not Store:IsWritable() then
        outcome = "read-only"
    else
        outcome = consider(item, quality, known)
        if not save(known) then outcome = "read-only" end
        if outcome == "no quality" then self:AskForLook("PLAYER_EQUIPMENT_CHANGED") end
    end
    Trace:Add(self.id, "PLAYER_EQUIPMENT_CHANGED", outcome, "slot", slot, "item", rawItem, "quality", rawQuality)
end

-- Every slot: the first look takes what is worn, a later one catches what an event missed.
local function compare(worn)
    if not Store:IsWritable() then return "read-only", {} end
    local known = knownItems()
    if not known then
        known = journalItems()
        for _, slot in ipairs(worn) do known[slot.item] = true end
        return save(known) and "first look" or "read-only", {}
    end
    local new, written = {}, 0
    for _, slot in ipairs(worn) do
        if not known[slot.item] then new[#new + 1] = slot.item .. ":" .. tostring(slot.quality or "?") end
        local outcome = consider(slot.item, slot.quality, known)
        -- What was written so far is kept, so the next look doesn't write it again.
        if outcome:find("^not written") then return save(known) and outcome or "read-only", new end
        if outcome == "first rare" or outcome == "first epic" or outcome == "epic" then written = written + 1 end
    end
    if not save(known) then return "read-only", new end
    if written > 0 then return "recorded " .. written, new end
    return #new > 0 and "nothing notable" or "unchanged", new
end

function Gear:Look()
    local asked = self:TakeAsked()
    local worn = {}
    for slot = FIRST_SLOT, LAST_SLOT do
        local item, quality = Compat.GetEquippedItem(slot)
        if item then worn[#worn + 1] = { item = item, quality = quality } end
    end
    -- A look that reads no item (no API, or the inventory not loaded yet) is not a first look either.
    local outcome, new = "no items", nil
    if #worn > 0 then outcome, new = compare(worn) end
    local anyNew = new and #new > 0
    Trace:Add(self.id, asked, outcome, "worn", #worn,
        anyNew and "new", anyNew and table.concat(new, " "))
end
