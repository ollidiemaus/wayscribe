local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local Geometry = Stubs.LoadAddon().Geometry

local function near(actual, expected, message)
    if math.abs(actual - expected) > 1e-6 then
        error((message or "values differ") .. ": expected " .. expected .. ", got " .. actual, 2)
    end
end

describe("simplify", function()
    it("reduces a straight walk to its ends", function()
        local points = {}
        for i = 0, 50 do
            points[#points + 1] = i * 9
            points[#points + 1] = 100 + i * 4
        end
        T.same(Geometry.Simplify(points, 3), { 0, 100, 450, 300 })
    end)

    it("keeps a corner", function()
        local points = { 0, 0, 10, 0, 20, 0, 30, 0, 30, 10, 30, 20, 30, 30 }
        T.same(Geometry.Simplify(points, 3), { 0, 0, 30, 0, 30, 30 })
    end)

    it("drops wobble within the tolerance and keeps what's beyond it", function()
        T.same(Geometry.Simplify({ 0, 0, 10, 2, 20, -2, 30, 0 }, 3), { 0, 0, 30, 0 })
        T.same(Geometry.Simplify({ 0, 0, 10, 8, 20, 0 }, 3), { 0, 0, 10, 8, 20, 0 })
    end)

    it("leaves tiny trails alone", function()
        T.same(Geometry.Simplify({}, 3), {})
        T.same(Geometry.Simplify({ 5, 5 }, 3), { 5, 5 })
        T.same(Geometry.Simplify({ 5, 5, 6, 6 }, 3), { 5, 5, 6, 6 })
    end)

    it("handles a trail that returns to its start", function()
        local points = { 0, 0, 50, 0, 50, 50, 0, 50, 0, 0 }
        T.same(Geometry.Simplify(points, 3), points)
    end)
end)

describe("quantize and length", function()
    it("rounds to whole yards and drops repeated points", function()
        T.same(Geometry.Quantize({ 1.4, 2.6, 1.2, 2.5, -3.5, 7.49 }), { 1, 3, -3, 7 })
    end)

    it("measures a trail", function()
        T.eq(Geometry.Length({ 0, 0, 3, 4, 3, 10 }), 11)
        T.eq(Geometry.Length({ 0, 0 }), 0)
    end)
end)

describe("map transform", function()
    -- Like the client: map u runs west to east (world -y), v north to south (world -x).
    local transform = Geometry.MapTransform(-255.0, 2029.9, -255.0, 2029.9 - 5137.5, -255.0 - 3425, 2029.9)

    it("maps the world onto the map, whatever way the axes run", function()
        local u, v = Geometry.ToMap(transform, -2894.3, -238.8)
        T.truthy(math.abs(u - 0.4416) < 0.0001, "u " .. u)
        T.truthy(math.abs(v - 0.7706) < 0.0001, "v " .. v)
        u, v = Geometry.ToMap(transform, -255.0, 2029.9)
        near(u, 0)
        near(v, 0)
        T.eq(transform.width, 5137.5)
        T.eq(transform.height, 3425)
    end)

    it("refuses a map without area", function()
        T.eq(Geometry.MapTransform(0, 0, 0, 0, 0, 0), nil)
    end)
end)

describe("clipping", function()
    it("keeps a line inside the map", function()
        T.same({ Geometry.ClipToUnit(0.1, 0.2, 0.3, 0.4) }, { 0.1, 0.2, 0.3, 0.4 })
    end)

    it("cuts a line at the map's edge", function()
        local x1, y1, x2, y2 = Geometry.ClipToUnit(0.5, 0.5, 1.5, 0.5)
        T.same({ x1, y1, x2, y2 }, { 0.5, 0.5, 1, 0.5 })
        x1, y1, x2, y2 = Geometry.ClipToUnit(-1, 0.5, 2, 0.5)
        T.same({ x1, y1, x2, y2 }, { 0, 0.5, 1, 0.5 })
    end)

    it("drops a line outside the map, even one passing a corner", function()
        T.eq(Geometry.ClipToUnit(1.2, 0.1, 1.5, 0.9), nil)
        T.eq(Geometry.ClipToUnit(0.8, -0.5, 1.5, 0.3), nil)
    end)
end)
