local _, ns = ...
local Compat, Geometry = ns.Compat, ns.Geometry

-- Where a point of the game world (continent, yards) goes on the world map's canvas, for
-- Footsteps with its markers (UI/FootstepsMap.lua) and the notes' markers (UI/NotesMap.lua);
-- docs/ARCHITECTURE.md §6.8.
--   * On the default map: three corners of the shown map give a world-to-map transform, so a
--     point needs no API call; only the shown map's continent can be placed, inside 0..1.
--   * On OpenMap's stitched map (docs/adr/0001-openmap-via-its-public-api.md): every point is
--     placed with OpenMapAPI.CanvasFromWorldPos, one call each, on every continent; nil means it
--     can't be placed. Drawings live on a frame spanning the whole stitched world, laid on the
--     canvas by the host map's rectangle there (two OpenMapAPI.WorldFromMap calls): when OpenMap
--     switches the host map as the view moves, only that frame moves and scales, nothing is
--     placed or drawn again. A stored trail's placed points are kept, so a redraw for the zoom
--     calls nothing either. Frames go above OpenMap's art.
-- Opening the map at a spot is here too: the stitched map glides there instead.
local MapPlacement = {}
ns.MapPlacement = MapPlacement

local FIT = 0.8         -- of the stitched view the shown box fills
local MAX_ZOOM = 48     -- OpenMap's deepest zoom; it keeps the view inside its own limits too
-- The world frame's scale stays within this factor of 1, and its sides in proportion within
-- ASPECT_SLACK; past either, a new world frame size is picked and everything is drawn again.
local MAX_FRAME_SCALE = 50
local ASPECT_SLACK = 0.01

local transforms = {}

-- The world-to-map transform of a map, with its continent; nil for maps spanning several
-- continents (the world map) or without world coordinates.
function MapPlacement.Transform(mapID)
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
-- Both kinds answer:
--   Covers(c)             whether points of continent c can be placed at all
--   At(c, x, y)           u, v (0..1 across the drawing frame), or nil
--   Line(u1, v1, u2, v2)  the part of a line to draw, or nil
--   Shows(u, v)           whether a marker at u, v is drawn
--   Attach(frame, canvas) lays the drawing frame on the canvas
--   SameSpace(other)      whether drawings made for placement `other` stay right with this one
--                         once the frame is attached again (nothing to place or draw again)
--   FrameLevel(map, pin, overPin, over)  the level for a frame of drawings on the canvas
-- Fields: continent (the one continent placed; nil: every continent), width and height of the
-- drawing frame, frameScale (its scale on the canvas), stitched.
-- The default map's also answer YardsPerUnit(); the stitched map's Runs(segment).

local Default, Stitched = {}, {}
Default.__index, Stitched.__index = Default, Stitched

-- The drawing frame is the canvas: 0..1 is the shown map.
function Default:Covers(continent) return continent == self.continent end

function Default:At(continent, x, y)
    if continent ~= self.continent then return nil end
    return Geometry.ToMap(self.transform, x, y)
end

-- Clipped to the map.
function Default:Line(u1, v1, u2, v2) return Geometry.ClipToUnit(u1, v1, u2, v2) end

function Default:Shows(u, v) return u >= 0 and u <= 1 and v >= 0 and v <= 1 end

function Default:YardsPerUnit()
    return self.transform.width / self.width
end

function Default:Attach(frame, canvas)
    frame:ClearAllPoints()
    frame:SetScale(1)
    frame:SetAllPoints(canvas)
end

-- Another map has another transform and clipping: drawn again.
function Default:SameSpace() return false end

-- overPin levels above the default map's pin level `pin`, else `over` above the canvas.
function Default:FrameLevel(map, pin, overPin, over)
    local levels = map.GetPinFrameLevelsManager and Compat.Call(map.GetPinFrameLevelsManager, map)
    local level = type(levels) == "table" and Compat.Call(levels.GetValidFrameLevel, levels, pin)
    if type(level) == "number" then return level + overPin end
    return map:GetCanvas():GetFrameLevel() + over
end

-- The drawing frame spans the stitched world: 0..1 is all of it (OpenMap's u, v), width by
-- height units, the size the first host map gave it. A new space when a host map needs the frame
-- scaled too far or out of proportion; points placed for an older space are placed again.
local space -- { width, height, id }
local spaces = 0
local runs = setmetatable({}, { __mode = "k" }) -- segment -> { p, space, runs }

-- The host map's rectangle on the stitched world: l, t, r, b; nil if it has none.
local function hostRect(api, mapID)
    if type(api.WorldFromMap) ~= "function" then return nil end
    local l, t = Compat.Call(api.WorldFromMap, mapID, 0, 0)
    local r, b = Compat.Call(api.WorldFromMap, mapID, 1, 1)
    if not (type(l) == "number" and type(t) == "number" and type(r) == "number" and type(b) == "number") then
        return nil
    end
    if not (r > l and b > t) then return nil end
    return l, t, r, b
end

local function stitched(api, map, width, height)
    local l, t, r, b = hostRect(api, map:GetMapID())
    if not l then return nil end
    -- Canvas units per stitched-world unit, across and down.
    local perU, perV = width / (r - l), height / (b - t)
    local scale = space and perU / space.width
    if not (scale and scale < MAX_FRAME_SCALE and scale > 1 / MAX_FRAME_SCALE
            and math.abs(perV / space.height - scale) <= ASPECT_SLACK * scale) then
        spaces = spaces + 1
        space = { width = perU, height = perV, id = spaces }
        scale = 1
    end
    return setmetatable({
        api = api, l = l, t = t, r = r, b = b, stitched = true,
        space = space.id, width = space.width, height = space.height, frameScale = scale,
    }, Stitched)
end

function Stitched:Covers(continent) return type(continent) == "number" end

function Stitched:At(continent, x, y)
    local hx, hy = Compat.CallAddon("openmap:CanvasFromWorldPos", self.api.CanvasFromWorldPos, continent, x, y)
    if type(hx) ~= "number" or type(hy) ~= "number" then return nil end
    return self.l + hx * (self.r - self.l), self.t + hy * (self.b - self.t)
end

-- The view shows past the host map: nothing is clipped.
function Stitched:Line(u1, v1, u2, v2) return u1, v1, u2, v2 end

function Stitched:Shows() return true end

-- The stitched world's origin goes where the host map's rectangle puts it. Offsets are in the
-- frame's own (scaled) units.
function Stitched:Attach(frame, canvas)
    frame:ClearAllPoints()
    frame:SetScale(self.frameScale)
    frame:SetSize(self.width, self.height)
    frame:SetPoint("TOPLEFT", canvas, "TOPLEFT", -self.l * self.width, self.t * self.height)
end

function Stitched:SameSpace(other)
    return other ~= nil and other.stitched == true and other.space == self.space
end

-- A stored trail's points as runs of placed points, in drawing frame units ({ x1, y1, x2, ... },
-- with their bounds minX, maxX, minY, maxY); a point that can't be placed ends a run. Kept until the trail or the space changes.
function Stitched:Runs(segment)
    local kept = runs[segment]
    if kept and kept.p == segment.p and kept.space == self.space then return kept.runs end
    local list, run = {}, nil
    local points = ns.Codec.DecodePath(segment.p)
    for i = 1, points and #points - 1 or 0, 2 do
        local u, v = self:At(segment.c, points[i], points[i + 1])
        if u then
            if not run then
                run = {}
                list[#list + 1] = run
            end
            local x, y = u * self.width, v * self.height
            if #run == 0 then
                run.minX, run.maxX, run.minY, run.maxY = x, x, y, y
            else
                run.minX, run.maxX = math.min(run.minX, x), math.max(run.maxX, x)
                run.minY, run.maxY = math.min(run.minY, y), math.max(run.maxY, y)
            end
            run[#run + 1] = x
            run[#run + 1] = y
        else
            run = nil
        end
    end
    runs[segment] = { p = segment.p, space = self.space, runs = list }
    return list
end

-- `over` levels above OpenMap's art.
function Stitched:FrameLevel(map, pin, overPin, over)
    local top = Compat.CallAddon("openmap:ArtTopLevel", self.api.ArtTopLevel)
    if type(top) == "number" then return top + over end
    return Default.FrameLevel(self, map, pin, overPin, over)
end

-- How points go on map's canvas now; nil where nothing can be placed (the whole world on the
-- default map, a host map that isn't on the stitched world, or a canvas without a size).
function MapPlacement.For(map)
    local canvas = map:GetCanvas()
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    if not (width > 0 and height > 0) then return nil end
    local api = Compat.StitchedMap()
    if api then return stitched(api, map, width, height) end
    local transform = MapPlacement.Transform(map:GetMapID())
    if not transform then return nil end
    return setmetatable({
        transform = transform, continent = transform.continent, width = width, height = height, frameScale = 1,
    }, Default)
end

-- Whether placement is still the right kind for the map: stitched while OpenMap's map shows.
function MapPlacement.Matches(placement)
    return placement ~= nil and (placement.stitched == true) == (Compat.StitchedMap() ~= nil)
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
function MapPlacement.Open(mapID, u1, v1, u2, v2)
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

local function onOpenMap(owner, event, source, fn)
    local api = Compat.OpenMapAPI()
    if not (api and type(api.RegisterCallback) == "function") then return end
    Compat.CallAddon("openmap:RegisterCallback", api.RegisterCallback, owner, event, function()
        ns.SafeCall(source, fn)
    end)
end

-- Calls fn() whenever the world map switches between OpenMap's stitched map and the default.
function MapPlacement.OnStitchedChanged(owner, fn)
    onOpenMap(owner, "OpenMap_StitchedChanged", "map:stitched", fn)
end

-- Calls fn() as OpenMap's stitched view moves (a few times a second at most).
function MapPlacement.OnViewChanged(owner, fn)
    onOpenMap(owner, "OpenMap_ViewChanged", "map:view", fn)
end

-- On the stitched map: the view's centre and half its width and height, in drawing frame units;
-- nil when not known. scale: screen units per drawing frame unit.
function MapPlacement.View(placement, map, scale)
    if not (placement and placement.stitched and type(placement.api.GetView) == "function") then return nil end
    local u, v = Compat.Call(placement.api.GetView)
    local container = map.ScrollContainer
    local width = container and Compat.Call(container.GetWidth, container)
    local height = container and Compat.Call(container.GetHeight, container)
    if not (type(u) == "number" and type(v) == "number" and type(width) == "number" and width > 0
            and type(height) == "number" and height > 0 and scale > 0) then
        return nil
    end
    return u * placement.width, v * placement.height, width / 2 / scale, height / 2 / scale
end
