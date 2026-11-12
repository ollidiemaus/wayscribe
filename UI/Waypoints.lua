local _, ns = ...
local Compat, Notes = ns.Compat, ns.Notes

-- Sends a note's places (docs/ARCHITECTURE.md §7.9) where something guides the player to them:
-- TomTom when it is loaded, else the game's own map pin, tracked so its arrow starts. Writes
-- nothing to the journal or any saved variable. The notes tab's buttons and the map's markers
-- call it.
--
-- TomTom is looked up when it is used, so installing or removing it needs nothing else, and every
-- call into it is protected: an error in TomTom stays out of the journal, and goes to /ws log.
local Waypoints = {}
ns.Waypoints = Waypoints

local SOURCE = "Wayscribe"

-- TomTom's table, when it is loaded.
local function tomTom()
    local addon = TomTom
    if type(addon) == "table" and type(addon.AddWaypoint) == "function" then return addon end
    return nil
end

-- "tomtom", "pin" (the game's map pin), or nil when there is nothing to send to.
function Waypoints.Target()
    if tomTom() then return "tomtom" end
    if Compat.HasUserWaypoint() then return "pin" end
    return nil
end

-- Whether a place of a note can be sent: TomTom takes every map, the game's pin not every one.
function Waypoints.CanSend(place, target)
    target = target or Waypoints.Target()
    if not (place and place.map) then return false end
    if target == "tomtom" then return true end
    if target == "pin" then return Compat.CanSetUserWaypoint(place.map) end
    return false
end

-- The waypoint's title: the line's label, else the note's title.
local function titleOf(note, place)
    if place.label and place.label ~= "" then return place.label end
    return Notes.Title(note)
end

-- Adds a place to TomTom with TomTom's own defaults, so its settings decide whether the waypoint
-- is kept, cleared on arrival and announced. Returns the waypoint, or nil.
-- With keepArrow, a new waypoint doesn't take the arrow either.
local function addToTomTom(addon, note, place, keepArrow)
    local options = { title = titleOf(note, place), from = SOURCE }
    if keepArrow then options.crazy = false end
    local waypoint = Compat.CallAddon("tomtom:AddWaypoint", addon.AddWaypoint, addon, place.map, place.u / 100, place.v / 100, options)
    return type(waypoint) == "table" and waypoint or nil
end

-- TomTom returns the waypoint already at the same map, spot and title without touching the arrow,
-- so the arrow is pointed explicitly.
local function pointArrow(addon, waypoint)
    if type(addon.SetCrazyArrow) ~= "function" then return false end
    local ok, message = pcall(addon.SetCrazyArrow, addon, waypoint, waypoint.arrivaldistance, waypoint.title)
    if not ok then Compat.ReportAddonError("tomtom:SetCrazyArrow", message) end
    return ok
end

-- Makes a place of a note a waypoint. Returns whether it did.
function Waypoints.Send(note, place)
    local target = Waypoints.Target()
    if not Waypoints.CanSend(place, target) then return false end
    if target == "tomtom" then
        local addon = tomTom()
        local waypoint = addToTomTom(addon, note, place)
        return waypoint ~= nil and pointArrow(addon, waypoint)
    end
    return Compat.SetUserWaypoint(place.map, place.u / 100, place.v / 100)
end

-- Whether Send all is offered: TomTom is loaded and takes two places of the note or more (the
-- game's pin holds one place).
function Waypoints.CanSendAll(note)
    if not tomTom() then return false end
    local count = 0
    for _, place in ipairs(Notes.PlacesOf(note)) do
        if Waypoints.CanSend(place, "tomtom") then count = count + 1 end
    end
    return count >= 2
end

-- TomTom only: adds every place of a note without moving the arrow, then points it once, at the
-- place nearest the player on the player's continent, else at the note's first place (TomTom's
-- own search for the closest would also weigh other addons' waypoints). Returns how many it added.
function Waypoints.SendAll(note)
    local addon = tomTom()
    if not addon then return 0 end
    local continent, x, y = Compat.GetPlayerWorldPosition()
    local count, first, nearest, nearestDistance = 0, nil, nil, nil
    for _, place in ipairs(Notes.PlacesOf(note)) do
        local waypoint = Waypoints.CanSend(place, "tomtom") and addToTomTom(addon, note, place, true)
        if waypoint then
            count = count + 1
            first = first or waypoint
            if place.c == continent then
                local distance = (place.x - x) ^ 2 + (place.y - y) ^ 2
                if not nearestDistance or distance < nearestDistance then
                    nearest, nearestDistance = waypoint, distance
                end
            end
        end
    end
    local target = nearest or first
    if target then pointArrow(addon, target) end
    return count
end
