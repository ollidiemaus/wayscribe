local _, ns = ...
local L, Compat, Store = ns.L, ns.Compat, ns.Store

-- First visits (docs/ARCHITECTURE.md §6.12): the first time the character is in each zone. A city
-- is a zone of its own. Instances are the Dungeons tracker's, and a zone flown over on a taxi
-- counts when the player lands there. "Been there" is the journal's own firsts, so a restored
-- journal never repeats a visit.
--
-- The first look is silent: the zone the character stands in, and every zone its world map shows
-- explored, were visited before the tracker existed. They are kept in state.visits. A level 1
-- character's starting zone is the exception, and its first entry.
local SETTLE = 1 -- seconds after an event, when the best map has caught up with a loading screen

ns.RecordTypes:Register("FIRST_VISIT", {
    version = 1,
    category = "travel",
    fields = { map = "number" },
    firstKey = function(data)
        return "VISIT:" .. data.map
    end,
    render = function(data)
        local zone = Compat.GetMapName(data.map)
        return zone and L.FIRST_VISIT:format(zone) or L.FIRST_VISIT_UNNAMED
    end,
})

local FirstVisits = ns.Trackers:New("FirstVisits", {
    label = L.TRACKER_FIRST_VISITS, tooltip = L.TRACKER_FIRST_VISITS_TIP,
})

function FirstVisits:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:TryRegisterEvent("PLAYER_CONTROL_GAINED") -- a taxi landed
    self:Debounce("look", SETTLE, self.Look)
end

function FirstVisits:PLAYER_ENTERING_WORLD()
    self:Debounce("look", SETTLE, self.Look)
end

FirstVisits.ZONE_CHANGED_NEW_AREA = FirstVisits.PLAYER_ENTERING_WORLD
FirstVisits.PLAYER_CONTROL_GAINED = FirstVisits.PLAYER_ENTERING_WORLD

function FirstVisits:Look()
    if Compat.IsOnTaxi() then return end
    local _, instanceType = Compat.GetInstance()
    if instanceType ~= "none" then return end
    local zone = Compat.GetZoneOf(Compat.GetPlayerMapID())
    if not zone then return end
    local known = Store:GetState("visits")
    if type(known) ~= "table" then
        known = Compat.GetExploredZones() or {}
        known[zone] = Compat.GetPlayerLevel() ~= 1 or nil
        if not Store:SetState("visits", known) then return end
    end
    if known[zone] or Store:GetFirst("VISIT:" .. zone) then return end
    Store:Append("FIRST_VISIT", { map = zone })
end
