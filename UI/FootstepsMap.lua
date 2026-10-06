local _, ns = ...
local L, Compat, Paths, Time, Geometry, Codec = ns.L, ns.Compat, ns.Paths, ns.Time, ns.Geometry, ns.Codec

-- Footsteps on the world map (docs/ARCHITECTURE.md §6.8). A MapCanvas data provider, the default
-- map's extension point for addons, draws the trails as lines on the map canvas:
--   * three corners of the shown map give a world-to-map transform, so a trail needs no API call
--     per point;
--   * lines are clipped to the map and simplified to the zoom, newest trails first, up to
--     MAX_LINES; no line is shorter than MIN_LINE_PIXELS on screen;
--   * drawing is spread over frames (BUDGET_MS each), so even "All" never stalls the map;
--   * the trail being recorded grows while the map is open, with a tail line to the player.
-- A button on the map picks which trails to show; the journal's day page can show one day.
local FootstepsMap = {}
ns.FootstepsMap = FootstepsMap

local MODES = { "today", "week", "all", "off" }
local VALID_MODE = { today = true, week = true, all = true, off = true }
local MAX_LINES = 5000
local BUDGET_MS = 4
local STORED_TOLERANCE = 3 -- yards: the detail trails are stored with
-- Sizes on screen are in pixels of the map's scroll container: one is 1 / canvas scale canvas units.
local LOD_PIXELS = 1       -- detail finer than this isn't drawn
-- Lines shorter than about a pixel don't show reliably (build 70235: the trail being recorded,
-- 8 yards a point, broke up on the small map), so shorter steps are merged until this long.
local MIN_LINE_PIXELS = 3
local REDRAW_ZOOM = 1.5    -- a zoom by this factor redraws with the detail of the new scale
local ZOOM_SETTLE = 0.3    -- seconds after the last zoom step
local STYLES = {
    ground = { width = 2.5, color = { 0.66, 0.12, 0.06 } },
    flight = { width = 1.5, color = { 0.16, 0.38, 0.78 } },
}
local RECENT_ALPHA, OLDER_ALPHA = 0.9, 0.5
local MAX_PARENTS = 10

local function newPool(sublevel)
    return { lines = {}, used = 0, sublevel = sublevel }
end

-- day: a day picked in the journal, shown until the map closes; job: the drawing coroutine;
-- transform: world -> shown map, nil while nothing can be drawn; drawnScale: the canvas scale the
-- lines were drawn for; liveFrom: index of the live trail's last point a line ends at; tail: the
-- line from there to the player.
local view = { trails = newPool(1), liveTrail = newPool(2), transforms = {}, liveFrom = 1 }
FootstepsMap.view = view

------------------------------------------------------------------------------------------------
-- What to show

function FootstepsMap:GetMode()
    if view.day then return "day" end
    local mode = ns.Options:Get("footstepsMode")
    return VALID_MODE[mode] and mode or "today"
end

-- SETTINGS_CHANGED redraws.
function FootstepsMap:SetMode(mode)
    view.day = nil
    ns.Options:Set("footstepsMode", mode)
end

function FootstepsMap.ModeLabel(mode)
    if mode == "day" then return Time.FormatDay(view.day) end
    return L["FOOTSTEPS_MODE_" .. mode:upper()]
end

-- First and last day of a mode; nil means no limit on that side.
local function dayRange(mode)
    local today = Time.DayKey(Time.Now())
    if mode == "day" then return view.day, view.day end
    if mode == "week" then return Time.ShiftDay(today, -6), today end
    if mode == "all" then return nil, nil end
    return today, today
end

local function covers(mode, dayKey)
    if mode == "off" then return false end
    local fromDay, toDay = dayRange(mode)
    return (not fromDay or dayKey >= fromDay) and (not toDay or dayKey <= toDay)
end

-- The world-to-map transform of a map, with its continent; nil for maps spanning several
-- continents (the world map) or without world coordinates.
local function transformFor(mapID)
    local cached = view.transforms[mapID]
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
        view.transforms[mapID] = cached
    end
    return cached or nil
end

------------------------------------------------------------------------------------------------
-- Lines

local function clearPool(pool)
    for i = 1, pool.used do
        pool.lines[i]:Hide()
    end
    pool.used = 0
end

-- Map coordinates a..d (already clipped) as a line of `style`.
local function placeLine(line, a, b, c, d, style, alpha)
    local spec = STYLES[style]
    line.style = style
    line:SetStartPoint("TOPLEFT", view.frame, a * view.width, -b * view.height)
    line:SetEndPoint("TOPLEFT", view.frame, c * view.width, -d * view.height)
    line:SetThickness(spec.width / view.scale)
    line:SetColorTexture(spec.color[1], spec.color[2], spec.color[3], alpha)
    line:Show()
end

-- A line in map coordinates (0..1), clipped to the map. False once MAX_LINES are in use.
local function drawLine(pool, u1, v1, u2, v2, style, alpha)
    local a, b, c, d = Geometry.ClipToUnit(u1, v1, u2, v2)
    if not a then return true end
    if view.trails.used + view.liveTrail.used >= MAX_LINES then return false end
    pool.used = pool.used + 1
    local line = pool.lines[pool.used]
    if not line then
        line = view.frame:CreateLine(nil, "ARTWORK", nil, pool.sublevel)
        pool.lines[pool.used] = line
    end
    placeLine(line, a, b, c, d, style, alpha)
    return true
end

-- World points from index `first` on, as connected lines at least minLength long on the canvas:
-- a shorter step is merged with the next. finish: also connect the last point, however close.
-- Returns false once MAX_LINES are in use, else true and the index of the last point drawn to.
local function drawTrail(pool, points, first, style, alpha, finish)
    local transform = view.transform
    local min2 = view.minLength * view.minLength
    local fromU, fromV = Geometry.ToMap(transform, points[first], points[first + 1])
    local anchor = first
    for i = first + 2, #points - 1, 2 do
        local u, v = Geometry.ToMap(transform, points[i], points[i + 1])
        local du, dv = (u - fromU) * view.width, (v - fromV) * view.height
        if du * du + dv * dv >= min2 or (finish and i >= #points - 1) then
            if not drawLine(pool, fromU, fromV, u, v, style, alpha) then return false end
            fromU, fromV, anchor = u, v, i
        end
    end
    return true, anchor
end

-- The live trail ends in one line from its last drawn point to the player, moved on every step.
local function drawTail(live)
    local points, from = live.points, view.liveFrom
    local last = #points - 1
    local a, b, c, d
    if last > from then
        local u1, v1 = Geometry.ToMap(view.transform, points[from], points[from + 1])
        local u2, v2 = Geometry.ToMap(view.transform, points[last], points[last + 1])
        a, b, c, d = Geometry.ClipToUnit(u1, v1, u2, v2)
    end
    if not a then
        if view.tail then view.tail:Hide() end
        return
    end
    view.tail = view.tail or view.frame:CreateLine(nil, "ARTWORK", nil, view.liveTrail.sublevel)
    placeLine(view.tail, a, b, c, d, live.f and "flight" or "ground", RECENT_ALPHA)
end

local function drawSegment(segment, recentFrom)
    local points = Codec.DecodePath(segment.p)
    if not points then return true end
    if view.tolerance > STORED_TOLERANCE then
        points = Geometry.Simplify(points, view.tolerance)
    end
    if #points < 4 then return true end
    local alpha = segment.t >= recentFrom and RECENT_ALPHA or OLDER_ALPHA
    return (drawTrail(view.trails, points, 1, segment.f and "flight" or "ground", alpha, true))
end

-- Today's trails (or the picked day's) are drawn strongest.
local function recentFrom(mode)
    if mode == "day" then return 0 end
    return Time.DayStart(Time.DayKey(Time.Now()))
end

------------------------------------------------------------------------------------------------
-- Drawing over several frames

local function stopJob()
    view.job = nil
    if view.frame then
        view.frame:SetScript("OnUpdate", nil)
    end
end

local function overBudget()
    return view.deadline ~= nil and debugprofilestop() > view.deadline
end

-- Newest first, so a full pool keeps the recent trails.
local function drawStored(segments, since)
    for i = #segments, 1, -1 do
        local segment = segments[i]
        if segment.c == view.transform.continent then
            if not drawSegment(segment, since) then return end
            if overBudget() then coroutine.yield() end
        end
    end
end

local function resume()
    local job = view.job
    if not job then return end
    view.deadline = type(debugprofilestop) == "function" and debugprofilestop() + BUDGET_MS or nil
    local ok, err = coroutine.resume(job)
    if not ok then
        ns.Log:Error("footsteps:map", err)
    end
    if (not ok or coroutine.status(job) == "dead") and view.job == job then
        stopJob()
    end
end

-- Above the map art and its explored areas; pins stay on top.
local function ensureFrame(map)
    if view.frame then return end
    local canvas = map:GetCanvas()
    local frame = CreateFrame("Frame", nil, canvas)
    frame:SetAllPoints(canvas)
    local levels = map.GetPinFrameLevelsManager and Compat.Call(map.GetPinFrameLevelsManager, map)
    local level = type(levels) == "table" and Compat.Call(levels.GetValidFrameLevel, levels, "PIN_FRAME_LEVEL_MAP_EXPLORATION")
    frame:SetFrameLevel((type(level) == "number" and level or canvas:GetFrameLevel()) + 1)
    view.frame = frame
end

function FootstepsMap:Clear()
    stopJob()
    clearPool(view.trails)
    clearPool(view.liveTrail)
    if view.tail then view.tail:Hide() end
    view.liveRef, view.liveFrom = nil, 1
end

function FootstepsMap:IsDrawing()
    return view.transform ~= nil and self.map ~= nil and self.map:IsShown()
end

function FootstepsMap:Redraw()
    self:Clear()
    view.transform = nil
    local map = self.map
    if not (map and map:IsShown()) then return end
    local mode = self:GetMode()
    local transform = mode ~= "off" and transformFor(map:GetMapID())
    local canvas = map:GetCanvas()
    if not transform or canvas:GetWidth() <= 0 then return end
    ensureFrame(map)
    view.transform = transform
    view.width, view.height = canvas:GetWidth(), canvas:GetHeight()
    -- Detail for this zoom, in canvas units.
    view.scale = Compat.Call(map.GetCanvasScale, map) or 1
    view.drawnScale = view.scale
    local pixel = 1 / view.scale
    view.tolerance = transform.width / view.width * pixel * LOD_PIXELS
    view.minLength = pixel * MIN_LINE_PIXELS
    local segments = Paths:GetSegments(dayRange(mode))
    local since = recentFrom(mode)
    view.job = coroutine.create(function() drawStored(segments, since) end)
    view.frame:SetScript("OnUpdate", resume)
    resume()
    self:DrawLive()
end

-- The trail being recorded, from its last drawn point on, plus the tail to the player.
function FootstepsMap:DrawLive()
    local live = Paths:GetLive()
    if live ~= view.liveRef then
        clearPool(view.liveTrail)
        view.liveRef, view.liveFrom = live, 1
    end
    if not (live and view.transform and live.c == view.transform.continent and covers(self:GetMode(), live.day)) then
        if view.tail then view.tail:Hide() end
        return
    end
    if #live.points < 4 then return end
    local ok, anchor = drawTrail(view.liveTrail, live.points, view.liveFrom, live.f and "flight" or "ground", RECENT_ALPHA)
    if ok then view.liveFrom = anchor end
    drawTail(live)
end

-- Lines keep their width on screen at every zoom.
function FootstepsMap:UpdateThickness()
    if not self.map then return end
    view.scale = Compat.Call(self.map.GetCanvasScale, self.map) or 1
    for _, pool in ipairs({ view.trails, view.liveTrail }) do
        for i = 1, pool.used do
            local line = pool.lines[i]
            line:SetThickness(STYLES[line.style].width / view.scale)
        end
    end
    if view.tail and view.tail.style then
        view.tail:SetThickness(STYLES[view.tail.style].width / view.scale)
    end
end

-- Detail follows the zoom: after zooming far enough in or out, the trails are drawn again once
-- the zoom has settled, so zoomed-out lines stay long enough to show and zoomed-in ones get detail.
function FootstepsMap:OnCanvasScaleChanged()
    self:UpdateThickness()
    if not (view.drawnScale and self:IsDrawing()) then return end
    local ratio = view.scale / view.drawnScale
    if ratio < REDRAW_ZOOM and ratio > 1 / REDRAW_ZOOM then return end
    view.zoomGeneration = (view.zoomGeneration or 0) + 1
    local generation = view.zoomGeneration
    C_Timer.After(ZOOM_SETTLE, function()
        if view.zoomGeneration == generation then
            ns.SafeCall("footsteps:zoom", self.RedrawIfShown, self)
        end
    end)
end

------------------------------------------------------------------------------------------------
-- Bus messages

function FootstepsMap:OnLive()
    if self:IsDrawing() then self:DrawLive() end
end

function FootstepsMap:OnAdded(segment, dayKey)
    local mode = self:GetMode()
    if not self:IsDrawing() or not covers(mode, dayKey) or segment.c ~= view.transform.continent then return end
    if view.job then
        self:Redraw() -- still drawing an older list: start over with the new trail in it
    else
        drawSegment(segment, recentFrom(mode))
    end
end

function FootstepsMap:RedrawIfShown()
    if self.map and self.map:IsShown() then self:Redraw() end
end

function FootstepsMap:OnSettingsChanged(key)
    if key == "footstepsMode" then
        self:UpdateButton()
        self:RedrawIfShown()
    end
end

------------------------------------------------------------------------------------------------
-- The button on the map

function FootstepsMap:UpdateButton()
    local button = self.button
    if not button then return end
    button:SetText(L.FOOTSTEPS_BUTTON:format(self.ModeLabel(self:GetMode())))
    local width = button:GetTextWidth()
    if type(width) == "number" then
        button:SetWidth(width + 24)
    end
end

-- A menu of the modes where the client has the default UI's menus; otherwise each click shows
-- the next mode.
function FootstepsMap:OnButtonClick(button)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(button, function(_, root)
            for _, mode in ipairs(MODES) do
                root:CreateRadio(self.ModeLabel(mode),
                    function(value) return self:GetMode() == value end,
                    function(value) self:SetMode(value) end,
                    mode)
            end
        end)
        return
    end
    local current = self:GetMode()
    local following = MODES[1]
    for i, mode in ipairs(MODES) do
        if mode == current then following = MODES[i % #MODES + 1] end
    end
    self:SetMode(following)
end

local function showTooltip(button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(L.FOOTSTEPS)
    GameTooltip:AddLine(L.FOOTSTEPS_BUTTON_TIP, 1, 1, 1, true)
    GameTooltip:Show()
end

local function hideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

-- In the map's upper right corner, above the canvas and its pins. (The lower left holds the
-- client's own coordinates on Forever.)
function FootstepsMap:CreateButton(map)
    local anchor = map.ScrollContainer or map
    local button = CreateFrame("Button", nil, map, "UIPanelButtonTemplate")
    button:SetSize(160, 22)
    button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -8, -8)
    button:SetFrameLevel(math.min(anchor:GetFrameLevel() + 500, 9000))
    button:SetScript("OnClick", function(owner) self:OnButtonClick(owner) end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", hideTooltip)
    self.button = button
    self:UpdateButton()
end

------------------------------------------------------------------------------------------------
-- Setup

local function createProvider()
    local provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:OnAdded(map)
        MapCanvasDataProviderMixin.OnAdded(self, map)
        FootstepsMap.map = map
    end
    function provider:RemoveAllData()
        FootstepsMap:Clear()
    end
    function provider:RefreshAllData()
        FootstepsMap:Redraw()
    end
    function provider:OnCanvasScaleChanged()
        FootstepsMap:OnCanvasScaleChanged()
    end
    -- A day picked in the journal is shown until the map closes.
    function provider:OnHide()
        view.day = nil
        FootstepsMap:Clear()
        FootstepsMap:UpdateButton()
    end
    return provider
end

-- Blizzard_WorldMap may load after this addon.
function FootstepsMap:WaitForMap()
    if self.waiting or WorldMapFrame ~= nil then return end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(_, _, name)
        if name == "Blizzard_WorldMap" then
            frame:UnregisterAllEvents()
            ns.SafeCall("footsteps:map", self.Register, self)
        end
    end)
    self.waiting = frame
end

function FootstepsMap:Register()
    if self.provider then return end
    if not Compat.HasWorldMapCanvas() then
        self:WaitForMap()
        return
    end
    self.provider = createProvider()
    WorldMapFrame:AddDataProvider(self.provider)
    self:CreateButton(WorldMapFrame)
end

------------------------------------------------------------------------------------------------
-- One day, from the journal

function FootstepsMap:CanShow()
    return self.provider ~= nil
end

local function extend(boxes, continent, points)
    local box = boxes[continent]
    if not box then
        box = { c = continent, n = 0 }
        boxes[continent] = box
    end
    for i = 1, #points - 1, 2 do
        local x, y = points[i], points[i + 1]
        if box.n == 0 then
            box.minX, box.maxX, box.minY, box.maxY = x, x, y, y
        else
            box.minX, box.maxX = math.min(box.minX, x), math.max(box.maxX, x)
            box.minY, box.maxY = math.min(box.minY, y), math.max(box.maxY, y)
        end
        box.n = box.n + 1
    end
end

local function fits(transform, box)
    if not transform or transform.continent ~= box.c then return false end
    for _, x in ipairs({ box.minX, box.maxX }) do
        for _, y in ipairs({ box.minY, box.maxY }) do
            local u, v = Geometry.ToMap(transform, x, y)
            if u < 0 or u > 1 or v < 0 or v > 1 then return false end
        end
    end
    return true
end

-- The most detailed map that holds all of a day's trails on the continent with most of them.
function FootstepsMap:MapForDay(dayKey)
    local boxes = {}
    for _, segment in ipairs(Paths:GetSegments(dayKey, dayKey)) do
        local points = Codec.DecodePath(segment.p)
        if points then extend(boxes, segment.c, points) end
    end
    local live = Paths:GetLive()
    if live and live.day == dayKey then
        extend(boxes, live.c, live.points)
    end
    local best
    for _, box in pairs(boxes) do
        if box.n > 0 and (not best or box.n > best.n) then best = box end
    end
    if not best then return nil end
    local mapID = Compat.GetMapAtWorldPos(best.c, (best.minX + best.maxX) / 2, (best.minY + best.maxY) / 2)
    for _ = 1, MAX_PARENTS do
        if not mapID or fits(transformFor(mapID), best) then break end
        mapID = Compat.GetParentMap(mapID)
    end
    return mapID
end

local function openMap(mapID)
    local map = WorldMapFrame
    if not map:IsShown() then
        if type(OpenWorldMap) == "function" then
            OpenWorldMap(mapID)
        elseif type(ToggleWorldMap) == "function" then
            ToggleWorldMap()
        end
    end
    if mapID and map:GetMapID() ~= mapID then
        map:SetMapID(mapID)
    end
    if map.Raise then map:Raise() end
end

-- Opens the world map at the day's trails. Returns whether it did.
function FootstepsMap:ShowDay(dayKey)
    if not self.provider then
        ns.Print(L.FOOTSTEPS_NO_MAP)
        return false
    end
    if Compat.Call(InCombatLockdown) == true then
        ns.Print(L.FOOTSTEPS_IN_COMBAT)
        return false
    end
    view.day = dayKey
    openMap(self:MapForDay(dayKey))
    self:UpdateButton()
    self:Redraw()
    return true
end

ns.Bus:On("READY", FootstepsMap, FootstepsMap.Register)
ns.Bus:On("PATH_ADDED", FootstepsMap, FootstepsMap.OnAdded)
ns.Bus:On("PATH_LIVE", FootstepsMap, FootstepsMap.OnLive)
ns.Bus:On("PATH_POINT", FootstepsMap, FootstepsMap.OnLive)
ns.Bus:On("PATH_WIPED", FootstepsMap, FootstepsMap.RedrawIfShown)
ns.Bus:On("SETTINGS_CHANGED", FootstepsMap, FootstepsMap.OnSettingsChanged)
