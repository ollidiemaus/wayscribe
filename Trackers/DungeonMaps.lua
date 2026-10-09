local _, ns = ...
local L, Compat, Store, Charted = ns.L, ns.Compat, ns.Store, ns.Charted

-- Dungeon maps (docs/dungeon-maps.md): what places the player inside a dungeon that has a map, so
-- its fog lifts. The game gives addons no position inside instances, so these are the signals:
-- arriving ("enter"), a boss engaged or killed (its encounterID: reaching a boss is enough, a wipe
-- counts), and a subzone entered ("area:<areaID>"). Data/Charted.lua keeps them. When the last
-- section of a map lifts, the journal says so: "Charted Wailing Caverns completely".
local INSTANCE_EVENTS = { "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }

local function mapName(instanceID)
    local map = Charted.Map(instanceID)
    return map and Charted.Name(map) or L.UNKNOWN_INSTANCE:format(instanceID)
end

ns.RecordTypes:Register("DUNGEON_CHARTED", {
    version = 1,
    category = "adventure",
    fields = { instanceID = "number" },
    firstKey = function(data) return "CHARTED:" .. data.instanceID end,
    render = function(data)
        return L.DUNGEON_CHARTED:format(mapName(data.instanceID))
    end,
})

local Maps = ns.Trackers:New("DungeonMaps", { label = L.TRACKER_MAPS, tooltip = L.TRACKER_MAPS_TIP })

local function latest(instanceID)
    local last
    for _, ts in pairs(Charted:Facts(instanceID)) do
        if type(ts) == "number" and (not last or ts > last) then last = ts end
    end
    return last
end

-- The whole map found: one journal entry, dated when its last section lifted.
function Maps:CheckComplete(instanceID, backfill)
    if Store:GetFirst("CHARTED:" .. instanceID) or not Charted:IsComplete(instanceID) then return end
    local opts = backfill and { ts = latest(instanceID), backfill = true } or nil
    Store:Append("DUNGEON_CHARTED", { instanceID = instanceID }, opts)
end

function Maps:OnEnable()
    self.inside = nil
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    -- Runs and kills from before the maps (or before this map) light them up.
    for _, instanceID in ipairs(Charted:Backfill()) do
        self:CheckComplete(instanceID, true)
    end
    self:Update()
end

function Maps:OnDisable()
    self.inside = nil
end

-- Inside a dungeon with a map, its events are registered and arriving is noted.
function Maps:Update()
    local instanceID, instanceType = Compat.GetInstance()
    local inside = instanceID and instanceType ~= "none" and Charted.Map(instanceID) and instanceID or nil
    if inside ~= self.inside then
        for _, event in ipairs(INSTANCE_EVENTS) do
            if inside then
                self:TryRegisterEvent(event)
            else
                self:UnregisterEvent(event)
            end
        end
        self.inside = inside
    end
    if inside then
        self:Found("enter")
        self:CheckArea()
    end
end

function Maps:PLAYER_ENTERING_WORLD()
    self:Update()
end
Maps.ZONE_CHANGED_NEW_AREA = Maps.PLAYER_ENTERING_WORLD

function Maps:Found(trigger)
    if self.inside and Charted:Note(self.inside, trigger) then
        self:CheckComplete(self.inside)
    end
end

-- A boss reached; the end of a fight and a kill count too (a /reload during the fight misses its
-- start).
function Maps:ENCOUNTER_START(encounterID)
    self:Found(Compat.Safe(encounterID, "number"))
end
Maps.ENCOUNTER_END = Maps.ENCOUNTER_START
Maps.BOSS_KILL = Maps.ENCOUNTER_START

-- A subzone with a section of its own. GetSubZoneText names it in the client's language, and so
-- does C_Map.GetAreaInfo for the area's ID.
function Maps:CheckArea()
    local here = self.inside and Compat.GetSubZoneName()
    if not here then return end
    for _, section in ipairs(Charted.Map(self.inside).sections) do
        for _, trigger in ipairs(section) do
            local areaID = type(trigger) == "string" and tonumber(trigger:match("^area:(%d+)$"))
            if areaID and Compat.GetAreaName(areaID) == here then
                self:Found(trigger)
            end
        end
    end
end
Maps.ZONE_CHANGED = Maps.CheckArea
Maps.ZONE_CHANGED_INDOORS = Maps.CheckArea
