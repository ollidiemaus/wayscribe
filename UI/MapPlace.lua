local _, ns = ...
local Compat, Geometry = ns.Compat, ns.Geometry

-- Where a point of the game world (continent, yards) goes on the world map's canvas, for
-- Footsteps with its markers (UI/FootstepsMap.lua) and the notes' markers (UI/NotesMap.lua);
-- docs/ARCHITECTURE.md §6.8.
--   * On the default map: three corners of the shown map give a world-to-map transform, so a
--     point needs no API call; only the shown map's continent can be placed, inside 0..1.
--   * On OpenMap's stitched map (docs/adr/0001-openmap-via-its-public-api.md): every point is
--     placed with OpenMapAPI.CanvasFromWorldPos, one call each, on every continent, and may land
--     past the host map's 0..1; nil means it can't be placed. Frames go above OpenMap's art.
-- Opening the map at a place is here too: the stitched map glides there instead.
local MapPlace = {}
ns.MapPlace = MapPlace

local PROBE_YARDS = 100 -- how far apart the two points are that measure the stitched scale
local FIT = 0.8         -- of the stitched view the shown box fills
local MAX_ZOOM = 16

local transforms = {}

-- The world-to-map transform of a map, with its continent; nil for maps spanning several
-- continents (the world map) or without world coordinates.
function MapPlace.Transform(mapID)
    local cached = transforms[mapID]
    if cached == nil then
        cached = false
        local c1, x00, y00 = Compat.GetWorldPosFromMapPos(mapID, 0, 0)
        local c2, x10, y10 = Compat.GetWorldPosFromMapPos(mapID, 1, 0)
        local c3, x01, y01 = Compat.GetWorldPosFromMapPos(mapID, 0, 1)
        local transform = c1 and c1 == c2 and c1 == c3 and Geometry.MapTransform(x00, y00, x10, y10, x01, y01)
        if transform then
            transform.continent = c1
            cached = transform
        end
        transforms[mapID] = cached
    end
    return cached or nil
end

------------------------------------------------------------------------------------------------
-- Placements: For(map) answers for the map as it shows now; a new one after every change.

local Default, Stitched = {}, {}
Default.__index, Stitched.__index = Default, Stitched

function Default:Covers(continent) return continent == self.continent end

-- Map u, v of a world point (0..1 inside the map), or nil.
function Default:At(continent, x, y)
    if continent ~= self.continent then return nil end
    return Geometry.ToMap(self.transform, x, y)
end

function Default:YardsPerUnit()
    return self.transform.width / self.width
end

function Stitched:Covers(continent) return type(continent) == "number" end

function Stitched:At(continent, x, y)
    local u, v = Compat.Call(self.api.CanvasFromWorldPos, continent, x, y)
    if type(u) ~= "number" or type(v) ~= "number" then return nil end
    return u, v
end

-- Yards per canvas unit around a point, measured by placing two points; nil where they can't be.
function Stitched:YardsPerUnit(continent, x, y)
    local cached = self.scales[continent]
    if cached then return cached end
    local u1, v1 = self:At(continent, x, y)
    if not u1 then return nil end
    local u2, v2 = self:At(continent, x + PROBE_YARDS, y)
    if not u2 then u2, v2 = self:At(continent, x - PROBE_YARDS, y) end
    if not u2 then return nil end
    local du, dv = (u2 - u1) * self.width, (v2 - v1) * self.height
    local distance = math.sqrt(du * du + dv * dv)
    if distance <= 0 then return nil end
    self.scales[continent] = PROBE_YARDS / distance
    return self.scales[continent]
end

-- How points go on map's canvas now; nil where nothing can be placed (the whole world on the
-- default map, or a canvas without a size). Fields: stitched, clip (lines and markers stay
-- inside 0..1), width and height of the canvas.
function MapPlace.For(map)
    local canvas = map:GetCanvas()
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    if not (width > 0 and height > 0) then return nil end
    local api = Compat.StitchedMap()
    if api then
        return setmetatable({ stitched = true, api = api, scales = {}, width = width, height = height }, Stitched)
    end
    local transform = MapPlace.Transform(map:GetMapID())
    if not transform then return nil end
    return setmetatable({
        clip = true, transform = transform, continent = transform.continent, width = width, height = height,
    }, Default)
end

-- The frame level for a frame of drawings on the canvas: `over` levels above OpenMap's art on
-- the stitched map; otherwise overPin above the default map's pin level `pin`, or `over` above
-- the canvas.
function MapPlace.FrameLevel(map, place, pin, overPin, over)
    if place.stitched then
        local top = Compat.Call(place.api.ArtTopLevel)
        if type(top) == "number" then return top + over end
    end
    local levels = map.GetPinFrameLevelsManager and Compat.Call(map.GetPinFrameLevelsManager, map)
    local level = type(levels) == "table" and Compat.Call(levels.GetValidFrameLevel, levels, pin)
    if type(level) == "number" then return level + overPin end
    return map:GetCanvas():GetFrameLevel() + over
end

------------------------------------------------------------------------------------------------
-- Opening the map

-- Glides the stitched view to a box of map mapID (u1, v1 to u2, v2) at a zoom that fits it.
local function glide(api, mapID, u1, v1, u2, v2)
    if type(api.WorldFromMap) ~= "function" or type(api.ShowWorld) ~= "function" then return false end
    local wu1, wv1 = Compat.Call(api.WorldFromMap, mapID, u1, v1)
    local wu2, wv2 = Compat.Call(api.WorldFromMap, mapID, u2, v2)
    if not (type(wu1) == "number" and type(wv1) == "number" and type(wu2) == "number" and type(wv2) == "number") then
        return false
    end
    local extent = math.max(math.abs(wu2 - wu1), math.abs(wv2 - wv1))
    local zoom = extent > 0 and math.min(MAX_ZOOM, math.max(1, FIT / extent)) or MAX_ZOOM
    return Compat.Call(api.ShowWorld, (wu1 + wu2) / 2, (wv1 + wv2) / 2, zoom) == true
end

-- Opens the world map in front of the journal at mapID (or as it is). On the stitched map the
-- view glides to the box of mapID (u1, v1 to u2, v2; default: all of it) instead.
function MapPlace.Open(mapID, u1, v1, u2, v2)
    local map = WorldMapFrame
    if not map:IsShown() then
        if type(OpenWorldMap) == "function" then
            OpenWorldMap(mapID)
        elseif type(ToggleWorldMap) == "function" then
            ToggleWorldMap()
        end
    end
    local api = mapID and Compat.StitchedMap()
    if not (api and glide(api, mapID, u1 or 0, v1 or 0, u2 or 1, v2 or 1)) and mapID and map:GetMapID() ~= mapID then
        map:SetMapID(mapID)
    end
    if map.Raise then map:Raise() end
end

-- Calls fn() whenever the world map switches between OpenMap's stitched map and the default.
function MapPlace.OnStitchedChanged(owner, fn)
    local api = Compat.OpenMapAPI()
    if not (api and type(api.RegisterCallback) == "function") then return end
    Compat.Call(api.RegisterCallback, owner, "OpenMap_StitchedChanged", function()
        ns.SafeCall("map:stitched", fn)
    end)
end
