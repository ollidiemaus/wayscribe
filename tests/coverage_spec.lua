local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local function at(year, month, day)
    return os.time({ year = year, month = month, day = day, hour = 12 })
end

-- Standing in Mulgore, so the client's zone maps are the stubs' one zone: Mulgore, 3425 x 5137.5
-- yards (about 1760 squares of 100 yards).
local function start()
    local ns = Stubs.LoadAddon({ now = at(2026, 10, 3) })
    Stubs.SetBestMap(1412)
    Stubs.Login()
    return ns
end

local function trail(ns, points, opts)
    opts = opts or {}
    return ns.Paths:AddSegment({
        c = opts.c or 1, t = opts.t or Stubs.Now(), d = 60, f = opts.flight or nil, p = ns.Codec.EncodePath(points),
    })
end

local function cells(x1, y1, x2, y2, size)
    local Geometry = Stubs.LoadAddon().Geometry
    local visited = {}
    Geometry.WalkCells(x1, y1, x2, y2, size or 1, function(i, j) visited[#visited + 1] = i .. "," .. j end)
    return visited
end

describe("geometry", function()
    it("walks every grid square a line passes through, in order", function()
        T.same(cells(0.5, 0.5, 2.5, 1.5), { "0,0", "1,0", "1,1", "2,1" })
        T.same(cells(2.5, 0.5, 0.5, 0.5), { "2,0", "1,0", "0,0" })
        T.same(cells(1, 0.5, 0, 0.5), { "1,0", "0,0" }, "starting on an edge")
        T.same(cells(-0.5, -0.5, 0.5, -0.5), { "-1,-1", "0,-1" })
        T.same(cells(0.5, 0.5, 0.7, 0.2), { "0,0" })
        T.same(cells(-1000, 0, -1000, 250, 100), { "-10,0", "-10,1", "-10,2" })
    end)

    it("measures the area rectangles cover together", function()
        local Geometry = Stubs.LoadAddon().Geometry
        local a = { minX = 0, maxX = 10, minY = 0, maxY = 10 }
        local b = { minX = 5, maxX = 15, minY = 5, maxY = 15 }
        local c = { minX = 20, maxX = 30, minY = 0, maxY = 1 }
        local inside = { minX = 1, maxX = 2, minY = 1, maxY = 2 }
        T.eq(Geometry.UnionArea({ a }), 100)
        T.eq(Geometry.UnionArea({ a, b }), 175)
        T.eq(Geometry.UnionArea({ a, b, c, inside }), 185)
        T.eq(Geometry.UnionArea({}), 0)
    end)
end)

describe("coverage", function()
    it("counts the squares a year's ground trails pass through, against the zone maps", function()
        local ns = start()
        trail(ns, { -1000, 0, -1000, 1000 })
        local coverage = ns.Coverage:Get(2026)
        T.eq(coverage.walked, 11)
        T.eq(string.format("%.4f", coverage.total), "1759.5938")
        T.eq(string.format("%.4f", coverage.percent), "0.6251")
        T.eq(coverage.zone.map, 1412)
        T.eq(string.format("%.4f", coverage.zone.percent), "0.6251")
    end)

    it("leaves out flights, other years, squares outside every zone and squares walked twice", function()
        local ns = start()
        trail(ns, { -1000, 0, -1000, 1000 })
        trail(ns, { -1000, 1000, -1000, 0 })
        trail(ns, { -2000, 0, -2000, 1000 }, { flight = true })
        trail(ns, { 5000, 0, 5000, 1000 })
        trail(ns, { -3000, 0, -3000, 1000 }, { t = at(2025, 6, 1) })
        T.eq(ns.Coverage:Get(2026).walked, 11)
        T.eq(ns.Coverage:Get(2025).walked, 11)
    end)

    it("adds trails stored later, and starts over when the trails are deleted", function()
        local ns = start()
        trail(ns, { -1000, 0, -1000, 1000 })
        T.eq(ns.Coverage:Get(2026).walked, 11)
        trail(ns, { -2000, 0, -2000, 500 })
        T.eq(ns.Coverage:Get(2026).walked, 17)
        ns.Paths:Wipe()
        T.eq(ns.Coverage:Get(2026).walked, 0)
    end)

    it("measures in the background, a few milliseconds per frame", function()
        local ns = start()
        for i = 1, 3 do
            trail(ns, { -1000 * i, 0, -1000 * i, 100 })
        end
        local clock = 0
        _G.debugprofilestop = function()
            clock = clock + 3
            return clock
        end
        local ready
        ns.Bus:On("COVERAGE_READY", {}, function(_, year) ready = year end)
        T.same({ ns.Coverage:Get(2026) }, { nil, true })
        T.eq(ns.Coverage.frame:GetScript("OnUpdate") ~= nil, true, "drawing on")
        ns.Coverage.frame:GetScript("OnUpdate")()
        T.eq(ready, 2026)
        T.eq(ns.Coverage.frame:GetScript("OnUpdate"), nil)
        T.eq(ns.Coverage:Get(2026).walked, 6)
    end)

    it("can't tell without the client's zone maps", function()
        local ns = Stubs.LoadAddon({ now = at(2026, 10, 3) })
        Stubs.SetBestMap(1412)
        _G.C_Map.GetMapChildrenInfo = nil
        Stubs.Login()
        ns.Store:Count("travel", "ground", 2000)
        trail(ns, { -1000, 0, -1000, 1000 })
        T.same({ ns.Coverage:Get(2026) }, { nil, false })
        local cards = ns.YearCards:Build(2026)
        T.eq(cards[1].id, "footsteps")
        T.same(cards[1].lines, {})
    end)

    it("puts the share of Azeroth on the Footsteps card, or says it is measuring", function()
        local ns = start()
        ns.Store:Count("travel", "ground", 2000)
        trail(ns, { -1000, 0, -1000, 1000 })
        local function footsteps()
            for _, card in ipairs(ns.YearCards:Build(2026)) do
                if card.id == "footsteps" then return card.lines end
            end
        end
        T.same(footsteps(), { "You walked 0.6% of Azeroth", "Most walked zone: Mulgore (0.6%)" })

        trail(ns, { -2000, 0, -2000, 1000 }, { t = at(2026, 10, 4) })
        ns.Paths:Wipe()
        trail(ns, { -1000, 0, -1000, 100 })
        trail(ns, { -2000, 0, -2000, 100 })
        local clock = 0
        _G.debugprofilestop = function()
            clock = clock + 3
            return clock
        end
        T.same(footsteps(), { "Measuring how much of Azeroth you walked..." })
    end)

    it("is in the probe: the zones per continent and their area", function()
        local ns = start()
        ns.Slash:Handle("probe")
        local found = {}
        for _, line in ipairs(_G.WayscribeDB.probe.lines) do
            if line:find("^coverage%.") then found[#found + 1] = line end
        end
        T.same(found, { "coverage.zones = 1", "coverage.continent.1 = 1 zones, 6 sq mi" })
    end)
end)
