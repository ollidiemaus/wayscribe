local _, ns = ...

-- Plain math on Footsteps trails (docs/ARCHITECTURE.md §6.8): simplification, length, the
-- world-to-map transform, clipping, and the grid cells and areas the coverage stat counts. Trails
-- are flat lists { x1, y1, x2, y2, ... } in world yards. No WoW API here, so all of it is tested
-- in plain Lua.
local Geometry = {}
ns.Geometry = Geometry

local sqrt, floor = math.sqrt, math.floor

function Geometry.Distance(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return sqrt(dx * dx + dy * dy)
end

function Geometry.Length(points)
    local length = 0
    for i = 3, #points - 1, 2 do
        length = length + Geometry.Distance(points[i - 2], points[i - 1], points[i], points[i + 1])
    end
    return length
end

-- Squared distance from point p to the line segment a-b.
local function distanceToSegment2(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local length2 = dx * dx + dy * dy
    local t = 0
    if length2 > 0 then
        t = ((px - ax) * dx + (py - ay) * dy) / length2
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    local ex, ey = ax + t * dx - px, ay + t * dy - py
    return ex * ex + ey * ey
end

-- Douglas-Peucker: keeps only the points the trail can't lose without straying more than
-- `tolerance` yards from where it went. The first and last points always stay. Iterative, so a
-- long trail can't overflow the stack. Returns a new list.
function Geometry.Simplify(points, tolerance)
    local count = floor(#points / 2)
    local keep = { [1] = true, [count] = true }
    local stack = { 1, count }
    local limit = tolerance * tolerance
    while #stack > 0 do
        local last = table.remove(stack)
        local first = table.remove(stack)
        local ax, ay = points[2 * first - 1], points[2 * first]
        local bx, by = points[2 * last - 1], points[2 * last]
        local worst, index = limit, nil
        for i = first + 1, last - 1 do
            local distance = distanceToSegment2(points[2 * i - 1], points[2 * i], ax, ay, bx, by)
            if distance > worst then
                worst, index = distance, i
            end
        end
        if index then
            keep[index] = true
            stack[#stack + 1] = first
            stack[#stack + 1] = index
            stack[#stack + 1] = index
            stack[#stack + 1] = last
        end
    end
    local result = {}
    for i = 1, count do
        if keep[i] then
            result[#result + 1] = points[2 * i - 1]
            result[#result + 1] = points[2 * i]
        end
    end
    return result
end

-- Whole yards, without repeating a point: what the codec stores.
function Geometry.Quantize(points)
    local result = {}
    local lastX, lastY
    for i = 1, #points - 1, 2 do
        local x, y = floor(points[i] + 0.5), floor(points[i + 1] + 0.5)
        if x ~= lastX or y ~= lastY then
            result[#result + 1] = x
            result[#result + 1] = y
            lastX, lastY = x, y
        end
    end
    return result
end

-- The transform from world yards to a map's 0..1 coordinates, given where three of the map's
-- corners lie in the world: (0,0), (1,0) and (0,1). Maps are axis-aligned with the world, but the
-- world's x runs north, so the general 2x2 inverse is used instead of assuming an orientation.
-- Also returns the map's size in yards. nil for a degenerate map.
function Geometry.MapTransform(x00, y00, x10, y10, x01, y01)
    local ux, uy = x10 - x00, y10 - y00 -- one map width, in the world
    local vx, vy = x01 - x00, y01 - y00 -- one map height, in the world
    local det = ux * vy - vx * uy
    if det == 0 then return nil end
    return {
        ox = x00, oy = y00,
        a = vy / det, b = -vx / det, c = -uy / det, d = ux / det,
        width = sqrt(ux * ux + uy * uy), height = sqrt(vx * vx + vy * vy),
    }
end

-- World yards -> map u, v (0..1 inside the map).
function Geometry.ToMap(transform, x, y)
    local dx, dy = x - transform.ox, y - transform.oy
    return transform.a * dx + transform.b * dy, transform.c * dx + transform.d * dy
end

-- One edge of Liang-Barsky clipping: narrows t0..t1, or returns nil if the line is outside.
local function clipEdge(p, q, t0, t1)
    if p == 0 then
        if q < 0 then return nil end
        return t0, t1
    end
    local r = q / p
    if p < 0 then
        if r > t1 then return nil end
        if r > t0 then t0 = r end
    else
        if r < t0 then return nil end
        if r < t1 then t1 = r end
    end
    return t0, t1
end

-- The part of the line from (x1, y1) to (x2, y2) inside the unit square, or nil.
function Geometry.ClipToUnit(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local t0, t1 = clipEdge(-dx, x1, 0, 1)
    if t0 then t0, t1 = clipEdge(dx, 1 - x1, t0, t1) end
    if t0 then t0, t1 = clipEdge(-dy, y1, t0, t1) end
    if t0 then t0, t1 = clipEdge(dy, 1 - y1, t0, t1) end
    if not t0 then return nil end
    return x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
end

------------------------------------------------------------------------------------------------
-- Coverage: a grid of square cells `size` yards wide; cell (i, j) holds x from i * size to
-- (i + 1) * size and y from j * size to (j + 1) * size.

-- Calls visit(i, j) for every cell the line from (x1, y1) to (x2, y2) passes through, in order,
-- the start's cell first (Amanatides-Woo traversal: a diagonal skips no cell).
function Geometry.WalkCells(x1, y1, x2, y2, size, visit)
    local i, j = floor(x1 / size), floor(y1 / size)
    local lastI, lastJ = floor(x2 / size), floor(y2 / size)
    visit(i, j)
    local dx, dy = x2 - x1, y2 - y1
    local stepI, stepJ = dx > 0 and 1 or -1, dy > 0 and 1 or -1
    local huge = math.huge
    local nextX, nextY, deltaX, deltaY = huge, huge, huge, huge
    if dx ~= 0 then
        nextX = ((dx > 0 and (i + 1) or i) * size - x1) / dx
        deltaX = size / math.abs(dx)
    end
    if dy ~= 0 then
        nextY = ((dy > 0 and (j + 1) or j) * size - y1) / dy
        deltaY = size / math.abs(dy)
    end
    for _ = 1, math.abs(lastI - i) + math.abs(lastJ - j) do
        -- Rounding can't take a step past the last cell's row or column.
        if j == lastJ or (i ~= lastI and nextX < nextY) then
            i = i + stepI
            nextX = nextX + deltaX
        else
            j = j + stepJ
            nextY = nextY + deltaY
        end
        visit(i, j)
    end
end

local function sortedUnique(values)
    table.sort(values)
    local unique = {}
    for _, value in ipairs(values) do
        if value ~= unique[#unique] then unique[#unique + 1] = value end
    end
    return unique
end

-- Whether a rectangle { minX, maxX, minY, maxY } of `rects` contains the point.
function Geometry.InAnyRect(rects, x, y)
    for _, rect in ipairs(rects) do
        if x >= rect.minX and x <= rect.maxX and y >= rect.minY and y <= rect.maxY then
            return true
        end
    end
    return false
end

-- The area the rectangles cover together, overlaps counted once: the edges cut the plane into a
-- grid of pieces, and each piece is either inside some rectangle or not.
function Geometry.UnionArea(rects)
    local xs, ys = {}, {}
    for _, rect in ipairs(rects) do
        xs[#xs + 1], xs[#xs + 2] = rect.minX, rect.maxX
        ys[#ys + 1], ys[#ys + 2] = rect.minY, rect.maxY
    end
    xs, ys = sortedUnique(xs), sortedUnique(ys)
    local area = 0
    for a = 1, #xs - 1 do
        local x = (xs[a] + xs[a + 1]) / 2
        for b = 1, #ys - 1 do
            if Geometry.InAnyRect(rects, x, (ys[b] + ys[b + 1]) / 2) then
                area = area + (xs[a + 1] - xs[a]) * (ys[b + 1] - ys[b])
            end
        end
    end
    return area
end
