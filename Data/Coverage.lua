local _, ns = ...
local Geometry, Codec, Paths = ns.Geometry, ns.Codec, ns.Paths

-- "% of Azeroth walked" (docs/ARCHITECTURE.md §6.8, §8). A year's ground trails are laid on a grid
-- of CELL-yard squares; the squares they pass through are counted against the squares of the zone
-- maps the client knows. Flights don't count: they pass over the land, they don't walk it.
--
-- Derived data like the indexes, but never saved: the first request for a year decodes its trails
-- in the background, a few milliseconds per frame, and keeps the walked squares in memory. A trail
-- added later is laid on top; deleting the trails starts over.
--
-- Bus message: COVERAGE_READY(year), when a background measurement finishes.
local CELL = 100      -- yards: about how far you see a path, and wide enough for a road
local BUDGET_MS = 4   -- per frame
local OFFSET = 2 ^ 20 -- cell indices are far smaller (world yards / CELL)
local SPAN = 2 * OFFSET

local Coverage = { CELL = CELL, states = {} }
ns.Coverage = Coverage

-- The zone maps per continent, with the squares they cover together: { byContinent = { [c] =
-- { rects, cells } }, cells, count }. Asked from the client once; nil while it can't answer.
function Coverage:GetZones()
    if self.zones then return self.zones end
    local rects = ns.Compat.GetZoneRects()
    if not rects or #rects == 0 then return nil end
    local zones = { byContinent = {}, cells = 0, count = #rects }
    for _, rect in ipairs(rects) do
        rect.cells = (rect.maxX - rect.minX) * (rect.maxY - rect.minY) / (CELL * CELL)
        local group = zones.byContinent[rect.c]
        if not group then
            group = { rects = {} }
            zones.byContinent[rect.c] = group
        end
        group.rects[#group.rects + 1] = rect
    end
    for _, group in pairs(zones.byContinent) do
        group.cells = Geometry.UnionArea(group.rects) / (CELL * CELL)
        zones.cells = zones.cells + group.cells
    end
    self.zones = zones
    return zones
end

-- Lays one stored trail on the year's squares, counting each square once and each zone it lies in.
local function addSegment(state, zones, segment)
    local group = segment.f ~= true and zones.byContinent[segment.c]
    local points = group and Codec.DecodePath(segment.p)
    if not points then return end
    local cells = state.visited[segment.c]
    if not cells then
        cells = {}
        state.visited[segment.c] = cells
    end
    local function mark(i, j)
        local key = (i + OFFSET) * SPAN + (j + OFFSET)
        if cells[key] then return end
        cells[key] = true
        local x, y, inside = (i + 0.5) * CELL, (j + 0.5) * CELL, false
        for _, rect in ipairs(group.rects) do
            if x >= rect.minX and x <= rect.maxX and y >= rect.minY and y <= rect.maxY then
                inside = true
                state.perZone[rect] = (state.perZone[rect] or 0) + 1
            end
        end
        if inside then state.walked = state.walked + 1 end
    end
    for i = 3, #points - 1, 2 do
        Geometry.WalkCells(points[i - 2], points[i - 1], points[i], points[i + 1], CELL, mark)
    end
end

-- { walked, total, percent, zone = { map, percent } }: the zone with the most walked squares.
local function result(state, zones)
    local top, topCount
    for rect, count in pairs(state.perZone) do
        if not topCount or count > topCount or (count == topCount and rect.map < top.map) then
            top, topCount = rect, count
        end
    end
    return {
        walked = state.walked, total = zones.cells,
        percent = zones.cells > 0 and math.min(100, state.walked / zones.cells * 100) or 0,
        zone = top and { map = top.map, percent = math.min(100, topCount / top.cells * 100) } or nil,
    }
end

------------------------------------------------------------------------------------------------
-- Measuring in the background

local function overBudget(job)
    return job.deadline ~= nil and debugprofilestop() > job.deadline
end

local function measure(job)
    local state, zones = job.state, job.zones
    local year = job.year
    for _, segment in ipairs(Paths:GetSegments(year * 10000 + 101, year * 10000 + 1231)) do
        addSegment(state, zones, segment)
        if overBudget(job) then coroutine.yield() end
    end
    -- Trails stored while measuring weren't in the list.
    for _, segment in ipairs(job.added) do
        addSegment(state, zones, segment)
    end
end

function Coverage:Resume()
    local job = self.job
    if not job then return end
    job.deadline = type(debugprofilestop) == "function" and debugprofilestop() + BUDGET_MS or nil
    local ok, err = coroutine.resume(job.co)
    if not ok then
        ns.Log:Error("coverage", err)
    end
    if not ok or coroutine.status(job.co) == "dead" then
        self.job = nil
        self.frame:SetScript("OnUpdate", nil)
        if ok then
            self.states[job.year] = job.state
            job.done = true
            if job.announce then ns.Bus:Fire("COVERAGE_READY", job.year) end
        end
    end
end

function Coverage:Start(year, zones)
    local job = {
        year = year, zones = zones, added = {},
        state = { visited = {}, walked = 0, perZone = {} },
    }
    job.co = coroutine.create(function() measure(job) end)
    self.job = job
    self.frame = self.frame or CreateFrame("Frame")
    self.frame:SetScript("OnUpdate", function() Coverage:Resume() end)
    self:Resume()
    job.announce = true -- finished later, not within this call
    return job
end

------------------------------------------------------------------------------------------------
-- Public

-- The year's coverage, or nil plus whether it is being measured (false: this client can't tell).
function Coverage:Get(year)
    local state = self.states[year]
    local zones = self:GetZones()
    if state and zones then return result(state, zones) end
    if not zones then return nil, false end
    local job = self.job
    if not (job and job.year == year) then
        job = self:Start(year, zones)
    end
    if job.done then return result(job.state, zones) end
    return nil, true
end

function Coverage:OnPathAdded(segment, dayKey)
    local year = math.floor(dayKey / 10000)
    local job = self.job
    if job and job.year == year then
        job.added[#job.added + 1] = segment
    elseif self.states[year] and self.zones then
        addSegment(self.states[year], self.zones, segment)
    end
end

function Coverage:OnPathsWiped()
    self.states = {}
    if self.job then
        self.job = nil
        self.frame:SetScript("OnUpdate", nil)
    end
end

ns.Bus:On("PATH_ADDED", Coverage, Coverage.OnPathAdded)
ns.Bus:On("PATH_WIPED", Coverage, Coverage.OnPathsWiped)
