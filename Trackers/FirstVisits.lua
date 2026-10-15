local _, ns = ...
local L, Compat, Store, Trace = ns.L, ns.Compat, ns.Store, ns.Trace

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

-- Each event asks for a look one second later; a burst of them is one look, which the launch trace
-- names by every event that asked.
function FirstVisits:AskForLook(event)
    local asked = self.asked or {}
    self.asked = asked
    if not asked[event] then
        asked[event] = true
        asked[#asked + 1] = event
    end
    self:Debounce("look", SETTLE, self.Look)
end

function FirstVisits:OnEnable()
    self.asked = nil
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:TryRegisterEvent("PLAYER_CONTROL_GAINED") -- a taxi landed
    self:AskForLook("enable")
end

function FirstVisits:PLAYER_ENTERING_WORLD()
    self:AskForLook("PLAYER_ENTERING_WORLD")
end

function FirstVisits:ZONE_CHANGED_NEW_AREA()
    self:AskForLook("ZONE_CHANGED_NEW_AREA")
end

function FirstVisits:PLAYER_CONTROL_GAINED()
    self:AskForLook("PLAYER_CONTROL_GAINED")
end

-- Whether the zone in `look` is new to the character; returns how the look ended, for the trace.
-- The first look ever also reads the level and the explored zones into `look`.
local function visit(look)
    if look.taxi then return "on a taxi" end
    if look.instanceType ~= "none" then return "in an instance" end
    local zone = look.zone
    if not zone then return "no zone" end
    local known = Store:GetState("visits")
    if type(known) ~= "table" then
        look.first, look.level, look.explored = true, Compat.GetPlayerLevel(), Compat.GetExploredZones()
        known = {}
        for visited in pairs(look.explored or {}) do known[visited] = true end
        known[zone] = look.level ~= 1 or nil
        if not Store:SetState("visits", known) then return "read-only" end
    end
    if known[zone] then return look.first and "first look" or "known" end
    if Store:GetFirst("VISIT:" .. zone) then return "recorded before" end
    local record, reason = Store:Append("FIRST_VISIT", { map = zone })
    return record and "recorded" or "not written: " .. tostring(reason)
end

function FirstVisits:Look()
    local asked = self.asked
    self.asked = nil
    local map = Compat.GetPlayerMapID()
    local _, instanceType = Compat.GetInstance()
    local look = { taxi = Compat.IsOnTaxi(), instanceType = instanceType, zone = Compat.GetZoneOf(map) }
    local outcome = visit(look)
    Trace:Add(self.id, asked and table.concat(asked, "+"), outcome, "taxi", look.taxi, "instance", instanceType,
        "map", map, "zone", look.zone, look.first and "level", look.level, look.first and "explored", look.explored)
end
