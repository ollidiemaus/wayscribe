local _, ns = ...
local L, Compat, Paths, Time, Geometry, Codec = ns.L, ns.Compat, ns.Paths, ns.Time, ns.Geometry, ns.Codec
local MapPlacement = ns.MapPlacement

-- Footsteps on the world map (docs/ARCHITECTURE.md §6.8). A MapCanvas data provider, the default
-- map's extension point for addons, draws the trails as lines on the map canvas:
--   * points are placed by UI/MapPlacement.lua: on the default map with the shown map's transform
--     (its continent only, clipped to the map); on OpenMap's stitched map one API call each,
--     every continent, past the host map's edge, above OpenMap's art, on a frame spanning the
--     stitched world that only moves when OpenMap switches the map underneath. A trail breaks
--     where a point can't be placed;
--   * lines are simplified to the zoom, newest trails first, up to MAX_LINES; no line is shorter
--     than MIN_LINE_PIXELS on screen;
--   * drawing is spread over frames (BUDGET_MS each), so even "All" never stalls the map;
--   * the trail being recorded grows while the map is open, with a tail line to the player;
--   * redrawn when the map underneath changes (on the stitched map: only moved), the map switches
--     between OpenMap's and the default, or the zoom settles far from the drawn one; never on a
--     pan. A redraw for the zoom draws over the lines shown, so the map is never blank meanwhile;
--   * journal records with places draw markers on the days shown (RecordTypes' markers): a skull
--     for a death, a spell's icon where a hearthstone journey left and arrived.
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
local MARKER_SIZE = 16 -- pixels on screen
local MAX_PARENTS = 10

-- used: lines of the drawing now; shown: lines on the map, more than used while a redraw draws
-- over an older drawing.
local function newPool(sublevel)
    return { lines = {}, used = 0, shown = 0, sublevel = sublevel }
end

-- day: a day picked in the journal, shown until the map closes; job: the drawing coroutine;
-- placement: world -> shown map (MapPlacement.For), nil while nothing can be drawn; scale: screen
-- units per drawing frame unit (the canvas scale times the frame's own); drawnScale: the scale
-- the lines were drawn for; liveFrom: index of the live trail's last point a line ends at;
-- tail: the line from there to the player; markers: icons of journal records (deaths, journeys).
local view = {
    trails = newPool(1), liveTrail = newPool(2), liveFrom = 1,
    markers = { frames = {}, used = 0 },
}
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

------------------------------------------------------------------------------------------------
-- Lines

-- Hides the lines past the ones in use.
local function trimPool(pool)
    for i = pool.used + 1, pool.shown do
        pool.lines[i]:Hide()
    end
    pool.shown = pool.used
end

local function clearPool(pool)
    pool.used = 0
    trimPool(pool)
end

-- Canvas coordinates a..d (already clipped where they need to be) as a line of `style`.
local function placeLine(line, a, b, c, d, style, alpha)
    local spec = STYLES[style]
    line.style = style
    line:SetStartPoint("TOPLEFT", view.frame, a * view.width, -b * view.height)
    line:SetEndPoint("TOPLEFT", view.frame, c * view.width, -d * view.height)
    line:SetThickness(spec.width / view.scale)
    line:SetColorTexture(spec.color[1], spec.color[2], spec.color[3], alpha)
    line:Show()
end

-- A line in canvas coordinates (0..1 across the map), clipped to the map where the placement
-- says so. False once MAX_LINES are in use.
local function drawLine(pool, u1, v1, u2, v2, style, alpha)
    local a, b, c, d = view.placement:Line(u1, v1, u2, v2)
    if not a then return true end
    if view.trails.used + view.liveTrail.used >= MAX_LINES then return false end
    pool.used = pool.used + 1
    local line = pool.lines[pool.used]
    if not line then
        line = view.frame:CreateLine(nil, "ARTWORK", nil, pool.sublevel)
        pool.lines[pool.used] = line
    end
    if pool.used > pool.shown then pool.shown = pool.used end
    placeLine(line, a, b, c, d, style, alpha)
    return true
end

-- World points of `continent` from index `first` on, as connected lines at least minLength long
-- on the canvas: a shorter step is merged with the next. finish: also connect the last point,
-- however close. A point that can't be placed breaks the trail: no line leads to or from it, and
-- the run before it ends at its last placed point. Returns false once MAX_LINES are in use, else
-- true and the index of the last point drawn to (or a run starts at).
local function drawTrail(pool, points, first, continent, style, alpha, finish)
    local placement = view.placement
    local min2 = view.minLength * view.minLength
    local fromU, fromV = placement:At(continent, points[first], points[first + 1])
    local anchor = first
    local lastU, lastV, lastI -- the last placed point, not drawn to yet
    for i = first + 2, #points - 1, 2 do
        local u, v = placement:At(continent, points[i], points[i + 1])
        if not u then
            if lastU then
                if not drawLine(pool, fromU, fromV, lastU, lastV, style, alpha) then return false end
                anchor = lastI
            end
            fromU, fromV, lastU = nil, nil, nil
        elseif not fromU then
            fromU, fromV, anchor = u, v, i
        else
            local du, dv = (u - fromU) * view.width, (v - fromV) * view.height
            if du * du + dv * dv >= min2 or (finish and i >= #points - 1) then
                if not drawLine(pool, fromU, fromV, u, v, style, alpha) then return false end
                fromU, fromV, anchor, lastU = u, v, i, nil
            else
                lastU, lastV, lastI = u, v, i
            end
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
        local u1, v1 = view.placement:At(live.c, points[from], points[from + 1])
        local u2, v2 = view.placement:At(live.c, points[last], points[last + 1])
        if u1 and u2 then a, b, c, d = view.placement:Line(u1, v1, u2, v2) end
    end
    if not a then
        if view.tail then view.tail:Hide() end
        return
    end
    view.tail = view.tail or view.frame:CreateLine(nil, "ARTWORK", nil, view.liveTrail.sublevel)
    placeLine(view.tail, a, b, c, d, live.f and "flight" or "ground", RECENT_ALPHA)
end

-- A run of placed points (drawing frame units, MapPlacement's Runs) as connected lines at least
-- minLength long; the last point is always drawn to.
local function drawRun(pool, run, style, alpha)
    local min2 = view.minLength * view.minLength
    local width, height = view.width, view.height
    local fromX, fromY = run[1], run[2]
    for i = 3, #run - 1, 2 do
        local x, y = run[i], run[i + 1]
        local dx, dy = x - fromX, y - fromY
        if dx * dx + dy * dy >= min2 or i >= #run - 1 then
            if not drawLine(pool, fromX / width, fromY / height, x / width, y / height, style, alpha) then
                return false
            end
            fromX, fromY = x, y
        end
    end
    return true
end

-- On the stitched map: the trail's kept runs, simplified to the zoom.
local function drawRuns(segment, style, alpha)
    local tolerance = view.pixel * LOD_PIXELS
    for _, run in ipairs(view.placement:Runs(segment)) do
        if #run >= 4 then
            if not drawRun(view.trails, Geometry.Simplify(run, tolerance), style, alpha) then return false end
        end
    end
    return true
end

local function drawSegment(segment, recentFrom)
    local alpha = segment.t >= recentFrom and RECENT_ALPHA or OLDER_ALPHA
    local style = segment.f and "flight" or "ground"
    if view.placement.Runs then return drawRuns(segment, style, alpha) end
    local points = Codec.DecodePath(segment.p)
    if not points or #points < 4 then return true end
    -- Detail finer than LOD_PIXELS on screen, in yards.
    local yards = view.placement:YardsPerUnit(segment.c, points[1], points[2])
    local tolerance = yards and yards * view.pixel * LOD_PIXELS or STORED_TOLERANCE
    if tolerance > STORED_TOLERANCE then
        points = Geometry.Simplify(points, tolerance)
    end
    if #points < 4 then return true end
    return (drawTrail(view.trails, points, 1, segment.c, style, alpha, true))
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
        if view.placement:Covers(segment.c) then
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
        trimPool(view.trails) -- the lines of an older drawing it drew over
    end
end

-- Above the map art and its explored areas (OpenMap's art on its stitched map); pins stay on top.
local function ensureFrame(map, placement)
    local canvas = map:GetCanvas()
    view.frame = view.frame or CreateFrame("Frame", nil, canvas)
    placement:Attach(view.frame, canvas)
    view.frame:SetFrameLevel(placement:FrameLevel(map, "PIN_FRAME_LEVEL_MAP_EXPLORATION", 1, 1))
end

local function clearMarkers()
    local markers = view.markers
    for i = 1, markers.used do
        markers.frames[i]:Hide()
    end
    markers.used = 0
end

-- keepTrails: the stored trails stay shown until a new drawing has drawn over them.
function FootstepsMap:Clear(keepTrails)
    stopJob()
    if keepTrails then view.trails.used = 0 else clearPool(view.trails) end
    clearPool(view.liveTrail)
    clearMarkers()
    if view.tail then view.tail:Hide() end
    view.liveRef, view.liveFrom = nil, 1
    view.placement = nil
end

function FootstepsMap:IsDrawing()
    return view.placement ~= nil and self.map ~= nil and self.map:IsShown()
end

local function screenScale(map, placement)
    return (Compat.Call(map.GetCanvasScale, map) or 1) * placement.frameScale
end

-- inPlace: for the same map at another zoom, drawn over the lines shown.
function FootstepsMap:Redraw(inPlace)
    local keep = inPlace == true and view.placement ~= nil
    self:Clear(keep)
    local map = self.map
    local mode = self:GetMode()
    local placement = map and map:IsShown() and mode ~= "off" and MapPlacement.For(map)
    if not placement then
        clearPool(view.trails)
        return
    end
    ensureFrame(map, placement)
    view.placement = placement
    view.width, view.height = placement.width, placement.height
    -- Detail for this zoom, in drawing frame units.
    view.scale = screenScale(map, placement)
    view.drawnScale = view.scale
    view.pixel = 1 / view.scale
    view.minLength = view.pixel * MIN_LINE_PIXELS
    local segments = Paths:GetSegments(dayRange(mode))
    local since = recentFrom(mode)
    view.job = coroutine.create(function() drawStored(segments, since) end)
    view.frame:SetScript("OnUpdate", resume)
    resume()
    self:DrawLive()
    self:DrawMarkers()
end

-- The trail being recorded, from its last drawn point on, plus the tail to the player.
function FootstepsMap:DrawLive()
    local live = Paths:GetLive()
    if live ~= view.liveRef then
        clearPool(view.liveTrail)
        view.liveRef, view.liveFrom = live, 1
    end
    if not (live and view.placement and view.placement:Covers(live.c) and covers(self:GetMode(), live.day)) then
        if view.tail then view.tail:Hide() end
        return
    end
    if #live.points < 4 then return end
    local ok, anchor = drawTrail(view.liveTrail, live.points, view.liveFrom, live.c, live.f and "flight" or "ground",
        RECENT_ALPHA)
    if ok then view.liveFrom = anchor end
    drawTail(live)
end

-- The map underneath changed, or was laid out again. On the stitched map the same drawing only
-- moves to the new map (MapPlacement's Attach); otherwise it's drawn again.
function FootstepsMap:Refresh()
    local map, drawn = self.map, view.placement
    local placement = drawn and map and map:IsShown() and MapPlacement.For(map)
    if not (placement and placement:SameSpace(drawn)) then
        self:Redraw()
        return
    end
    view.placement = placement
    placement:Attach(view.frame, map:GetCanvas())
    self:UpdateThickness()
end

-- Lines keep their width on screen at every zoom.
function FootstepsMap:UpdateThickness()
    if not (self.map and view.placement) then return end
    view.scale = screenScale(self.map, view.placement)
    for _, pool in ipairs({ view.trails, view.liveTrail }) do
        for i = 1, pool.used do
            local line = pool.lines[i]
            line:SetThickness(STYLES[line.style].width / view.scale)
        end
    end
    if view.tail and view.tail.style then
        view.tail:SetThickness(STYLES[view.tail.style].width / view.scale)
    end
    for i = 1, view.markers.used do
        view.markers.frames[i]:SetSize(MARKER_SIZE / view.scale, MARKER_SIZE / view.scale)
    end
end

-- Detail follows the zoom: after zooming far enough in or out, the trails are drawn again once
-- the zoom has settled, so zoomed-out lines stay long enough to show and zoomed-in ones get detail.
-- The scale is the one on screen, so OpenMap's switch to a map underneath with a scale of its own
-- isn't a zoom; checked again once settled, as a switch passes through the new map's own scale.
local function farFromDrawn()
    if not (view.drawnScale and FootstepsMap:IsDrawing()) then return false end
    local ratio = view.scale / view.drawnScale
    return ratio >= REDRAW_ZOOM or ratio <= 1 / REDRAW_ZOOM
end

function FootstepsMap:OnCanvasScaleChanged()
    self:UpdateThickness()
    if not farFromDrawn() then return end
    view.zoomGeneration = (view.zoomGeneration or 0) + 1
    local generation = view.zoomGeneration
    C_Timer.After(ZOOM_SETTLE, function()
        if view.zoomGeneration == generation and farFromDrawn() then
            ns.SafeCall("footsteps:zoom", self.Redraw, self, true)
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
    if not self:IsDrawing() or not covers(mode, dayKey) or not view.placement:Covers(segment.c) then return end
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

-- A menu of the modes, and whether the player's notes show, where the client has the default
-- UI's menus; otherwise each click shows the next mode.
function FootstepsMap:OnButtonClick(button)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(button, function(_, root)
            for _, mode in ipairs(MODES) do
                root:CreateRadio(self.ModeLabel(mode),
                    function(value) return self:GetMode() == value end,
                    function(value) self:SetMode(value) end,
                    mode)
            end
            if root.CreateDivider then root:CreateDivider() end
            root:CreateCheckbox(L.NOTES_ON_MAP,
                function() return ns.NotesMap:IsShownOnMap() end,
                function() ns.NotesMap:SetShownOnMap(not ns.NotesMap:IsShownOnMap()) end)
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
-- Markers: what journal records put on the map (a skull for a death, a spell's icon where a
-- journey left and arrived), each with its title and time on mouseover.

local function showMarkerTooltip(frame)
    if not GameTooltip then return end
    local ts = frame.record.ts
    local when = Time.FormatClock(ts, Compat.Uses24HourClock())
    local dayKey = Time.DayKey(ts)
    if dayKey ~= Time.DayKey(Time.Now()) then
        when = L.MARKER_WHEN:format(Time.FormatDay(dayKey), when)
    end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(frame.title)
    GameTooltip:AddLine(when, 1, 1, 1)
    GameTooltip:Show()
end

-- marker = { c, x, y, icon, title } from the record's type.
local function placeMarker(record, marker)
    if type(marker.x) ~= "number" or type(marker.y) ~= "number" then return end
    local u, v = view.placement:At(marker.c, marker.x, marker.y)
    if not (u and view.placement:Shows(u, v)) then return end
    local markers = view.markers
    markers.used = markers.used + 1
    local frame = markers.frames[markers.used]
    if not frame then
        frame = CreateFrame("Frame", nil, view.frame)
        frame.icon = frame:CreateTexture(nil, "OVERLAY")
        frame.icon:SetAllPoints()
        frame:EnableMouse(true)
        frame:SetScript("OnEnter", showMarkerTooltip)
        frame:SetScript("OnLeave", hideTooltip)
        markers.frames[markers.used] = frame
    end
    frame.record, frame.title = record, marker.title
    frame.icon:SetTexture(marker.icon)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", view.frame, "TOPLEFT", u * view.width, -v * view.height)
    frame:SetSize(MARKER_SIZE / view.scale, MARKER_SIZE / view.scale)
    frame:Show()
end

-- The markers of the days shown, where they can be placed.
function FootstepsMap:DrawMarkers()
    clearMarkers()
    if not view.placement then return end
    local fromDay, toDay = dayRange(self:GetMode())
    for _, typeName in ipairs(ns.RecordTypes:MarkerTypes()) do
        for _, record in ipairs(ns.Store:GetRecordsOfType(typeName, fromDay, toDay)) do
            for _, marker in ipairs(ns.RecordTypes:Markers(record)) do
                placeMarker(record, marker)
            end
        end
    end
end

function FootstepsMap:OnRecordAdded(record)
    local def = ns.RecordTypes:Get(record.type)
    if def and def.markers and self:IsDrawing() then
        self:DrawMarkers()
    end
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
        FootstepsMap:Refresh()
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
    -- (OpenMap says so as its map opens too, after the drawing for it is made)
    MapPlacement.OnStitchedChanged(self, function()
        if not MapPlacement.Matches(view.placement) then self:RedrawIfShown() end
    end)
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

-- The most detailed map that holds all of a day's trails on the continent with most of them,
-- and their bounds there: { c, minX, maxX, minY, maxY } in yards.
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
        if not mapID or fits(MapPlacement.Transform(mapID), best) then break end
        mapID = Compat.GetParentMap(mapID)
    end
    return mapID, best
end

-- The bounds of box on map mapID (u1, v1, u2, v2), or nil.
local function boundsOn(mapID, box)
    local transform = mapID and box and MapPlacement.Transform(mapID)
    if not (transform and transform.continent == box.c) then return nil end
    local u1, v1 = Geometry.ToMap(transform, box.minX, box.minY)
    local u2, v2 = Geometry.ToMap(transform, box.maxX, box.maxY)
    return math.min(u1, u2), math.min(v1, v2), math.max(u1, u2), math.max(v1, v2)
end

-- Opens the world map at the day's trails (OpenMap's stitched map glides there). Returns whether
-- it did.
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
    local mapID, box = self:MapForDay(dayKey)
    MapPlacement.Open(mapID, boundsOn(mapID, box))
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
ns.Bus:On("RECORD_ADDED", FootstepsMap, FootstepsMap.OnRecordAdded)
