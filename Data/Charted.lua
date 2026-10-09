local _, ns = ...
local Time, Codec = ns.Time, ns.Codec

-- What the character has found inside the dungeons that have a map (docs/dungeon-maps.md), the
-- single write path for it. The saved facts are what lifted the fog, not the fog itself:
--   WayscribeCharDB.charted = { [instanceID] = { [trigger] = first seen (epoch seconds) } }
--   trigger = "enter" (arrived), an encounterID (a boss reached or killed), "area:<areaID>"
-- A map (StaticData/DungeonMaps.lua) cuts its floors into sections, and any of a section's
-- triggers lifts it. Since only triggers are saved, a later release can redraw the sections, or
-- add maps, without losing what was found: older runs and kills light up new maps (Backfill).
--
-- Bus message: CHARTED(instanceID, trigger).
local Charted = {}
ns.Charted = Charted

local EMPTY = {}
-- Per floor: its cells decoded, and the cells per section.
local decoded = setmetatable({}, { __mode = "k" })

function Charted:Attach(db)
    self.db = db
end

function Charted:IsWritable()
    return self.db ~= nil and ns.Store:IsWritable()
end

function Charted.Map(instanceID)
    local maps = ns.StaticData.DungeonMaps
    return maps and maps[instanceID]
end

-- A name table of the static data ({ enUS = , deDE = }) in the client's language.
function Charted.Name(names)
    if type(names) ~= "table" then return nil end
    return names[ns.Compat.Call(GetLocale) or "enUS"] or names.enUS
end

local function book(db)
    local charted = db and db.charted
    return type(charted) == "table" and charted or EMPTY
end

function Charted:Facts(instanceID)
    local facts = book(self.db)[instanceID]
    return type(facts) == "table" and facts or EMPTY
end

local function isTrigger(trigger)
    if trigger == "enter" then return true end
    if type(trigger) == "number" then return trigger > 0 and trigger % 1 == 0 end
    return type(trigger) == "string" and trigger:match("^area:%d+$") ~= nil
end

-- Notes that `trigger` happened in a dungeon with a map. Returns true the first time.
function Charted:Note(instanceID, trigger, ts, quiet)
    if not (self:IsWritable() and type(instanceID) == "number" and Charted.Map(instanceID) and isTrigger(trigger)) then
        return false
    end
    if type(self.db.charted) ~= "table" then self.db.charted = {} end
    local facts = self.db.charted[instanceID]
    if type(facts) ~= "table" then
        facts = {}
        self.db.charted[instanceID] = facts
    end
    if facts[trigger] ~= nil then return false end
    facts[trigger] = math.floor(ts or Time.Now())
    if not quiet then ns.Bus:Fire("CHARTED", instanceID, trigger) end
    return true
end

-- The instances with a map the character has found anything in.
function Charted:GetInstances()
    local list = {}
    for instanceID, facts in pairs(book(self.db)) do
        if type(facts) == "table" and next(facts) ~= nil and Charted.Map(instanceID) then
            list[#list + 1] = instanceID
        end
    end
    table.sort(list)
    return list
end

-- When the character first found something there.
function Charted:FirstSeen(instanceID)
    local first
    for _, ts in pairs(self:Facts(instanceID)) do
        if type(ts) == "number" and (not first or ts < first) then first = ts end
    end
    return first
end

------------------------------------------------------------------------------------------------
-- Sections and floors

-- The floor's section number per cell, row by row, and the cells per section.
function Charted.Cells(floor)
    local cached = decoded[floor]
    if cached then return cached.cells, cached.counts end
    local runs = Codec.DecodeInts(floor.cells) or EMPTY
    local cells, counts = {}, {}
    for i = 1, #runs - 1, 2 do
        local section, count = runs[i], runs[i + 1]
        for _ = 1, count do cells[#cells + 1] = section end
        if section > 0 then counts[section] = (counts[section] or 0) + count end
    end
    decoded[floor] = { cells = cells, counts = counts }
    return cells, counts
end

-- section number -> true for the sections whose fog has lifted.
function Charted:Revealed(instanceID)
    local map, facts, shown = Charted.Map(instanceID), self:Facts(instanceID), {}
    for n, section in ipairs(map and map.sections or EMPTY) do
        for _, trigger in ipairs(section) do
            if facts[trigger] ~= nil then
                shown[n] = true
                break
            end
        end
    end
    return shown
end

-- The share of a map's fogged cells that are revealed (0 to 1), over all its floors.
function Charted:Progress(instanceID)
    local map = Charted.Map(instanceID)
    if not map then return 0 end
    local shown, total, open = self:Revealed(instanceID), 0, 0
    for _, floor in ipairs(map.floors) do
        local _, counts = Charted.Cells(floor)
        for section, count in pairs(counts) do
            total = total + count
            if shown[section] then open = open + count end
        end
    end
    return total > 0 and open / total or 0
end

-- Every section revealed.
function Charted:IsComplete(instanceID)
    local map = Charted.Map(instanceID)
    if not map then return false end
    local shown = self:Revealed(instanceID)
    for n = 1, #map.sections do
        if not shown[n] then return false end
    end
    return true
end

-- The sections of a map that `trigger` lifts.
function Charted.SectionsOf(instanceID, trigger)
    local map, found = Charted.Map(instanceID), {}
    for n, section in ipairs(map and map.sections or EMPTY) do
        for _, t in ipairs(section) do
            if t == trigger then found[#found + 1] = n end
        end
    end
    return found
end

-- The floor to open the map at: where the section found last lies, else the first floor.
function Charted:CurrentFloor(instanceID)
    local map = Charted.Map(instanceID)
    if not map then return 1 end
    local latest, latestTs
    for trigger, ts in pairs(self:Facts(instanceID)) do
        if type(ts) == "number" and (not latestTs or ts > latestTs) then latest, latestTs = trigger, ts end
    end
    local sections = latest and Charted.SectionsOf(instanceID, latest) or EMPTY
    local wanted = {}
    for _, n in ipairs(sections) do wanted[n] = true end
    for index, floor in ipairs(map.floors) do
        local _, counts = Charted.Cells(floor)
        for section in pairs(counts) do
            if wanted[section] then return index end
        end
    end
    return 1
end

------------------------------------------------------------------------------------------------
-- Older runs light up the maps (and maps added in a later release)

-- Arrivals and kills already in the journal, noted once per version of the map data. Returns the
-- instances that changed.
function Charted:Backfill()
    local version = ns.StaticData.DungeonMapsVersion
    if not self:IsWritable() or not version or ns.Store:GetState("chartedMaps") == version then return EMPTY end
    local changed, seen = {}, {}
    local function note(instanceID, trigger, ts)
        if self:Note(instanceID, trigger, ts, true) and not seen[instanceID] then
            seen[instanceID] = true
            changed[#changed + 1] = instanceID
        end
    end
    for _, typeName in ipairs({ "DUNGEON_COMPLETED", "DUNGEON_VISITED" }) do
        for _, record in ipairs(ns.Store:GetRecordsOfType(typeName)) do
            local data = record.data
            note(data.instanceID, "enter", record.ts - (tonumber(data.dur) or 0))
            for _, encounterID in ipairs(type(data.bosses) == "table" and data.bosses or EMPTY) do
                note(data.instanceID, encounterID, record.ts)
            end
        end
    end
    for _, record in ipairs(ns.Store:GetRecordsOfType("BOSS_KILLED")) do
        note(record.data.instanceID, record.data.encounterID, record.ts)
    end
    ns.Store:SetState("chartedMaps", version)
    return changed
end
