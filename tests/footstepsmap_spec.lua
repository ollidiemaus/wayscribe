local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local DAY = 24 * 3600
local WIDTH, HEIGHT = 1000, 668 -- the stub map's canvas

-- opts.noMap: a client without the world map's data providers.
local function start(opts)
    opts = opts or {}
    local ns = Stubs.LoadAddon(opts)
    local map = not opts.noMap and Stubs.InstallWorldMap() or nil
    Stubs.InstallScrollBox()
    Stubs.Login()
    return ns, map
end

local function wait(seconds)
    for _ = 1, seconds do Stubs.Advance(1) end
end

-- Walks in a straight line between two points of map `mapID` (u, v), 20 yards a second.
local function walkOnMap(mapID, u1, v1, u2, v2, continent)
    local x1, y1 = Stubs.MapToWorld(mapID, u1, v1)
    local x2, y2 = Stubs.MapToWorld(mapID, u2, v2)
    local steps = math.max(1, math.floor(math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) / 20))
    for i = 0, steps do
        Stubs.SetPosition(continent or 1, x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps)
        Stubs.Advance(1)
    end
end

-- A walk that is stored right away (the player stops for a minute).
local function trail(mapID, u1, v1, u2, v2, continent)
    walkOnMap(mapID, u1, v1, u2, v2, continent)
    wait(61)
end

local function shown(pool)
    local list = {}
    for i = 1, pool.used do
        if pool.lines[i]:IsShown() then list[#list + 1] = pool.lines[i] end
    end
    return list
end

local function trails(ns)
    return shown(ns.FootstepsMap.view.trails)
end

local function live(ns)
    return shown(ns.FootstepsMap.view.liveTrail)
end

local function near(actual, expected, what)
    if math.abs(actual - expected) > 0.5 then
        error(what .. ": expected " .. expected .. ", got " .. actual, 2)
    end
end

-- A line from map point (u1, v1) to (u2, v2) on the stub canvas.
local function expectLine(line, u1, v1, u2, v2)
    near(line.x1, u1 * WIDTH, "x1")
    near(line.y1, -v1 * HEIGHT, "y1")
    near(line.x2, u2 * WIDTH, "x2")
    near(line.y2, -v2 * HEIGHT, "y2")
end

describe("world map", function()
    it("draws today's trails on the map", function()
        local ns, map = start()
        trail(1412, 0.2, 0.5, 0.6, 0.5)
        map:Show()
        local lines = trails(ns)
        T.eq(#lines, 1, "a straight walk is one line")
        expectLine(lines[1], 0.2, 0.5, 0.6, 0.5)
        T.eq(lines[1].thickness, 2.5)
        T.eq(lines[1].color[4], 0.9)
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("cuts trails at the map's edge", function()
        local ns, map = start()
        trail(1412, 0.8, 0.3, 1.3, 0.3)
        map:Show()
        local lines = trails(ns)
        T.eq(#lines, 1)
        expectLine(lines[1], 0.8, 0.3, 1, 0.3)
    end)

    it("draws the same trail on the continent map", function()
        local ns, map = start()
        trail(1412, 0.2, 0.5, 0.6, 0.5)
        map:Show()
        map:SetMapID(1414)
        local lines = trails(ns)
        T.eq(#lines, 1)
        local x1, y1 = Stubs.MapToWorld(1412, 0.2, 0.5)
        local x2, y2 = Stubs.MapToWorld(1412, 0.6, 0.5)
        local u1, v1 = Stubs.WorldToMap(1414, x1, y1)
        local u2, v2 = Stubs.WorldToMap(1414, x2, y2)
        expectLine(lines[1], u1, v1, u2, v2)
    end)

    it("draws nothing where it can't place a trail", function()
        local ns, map = start()
        trail(1412, 0.2, 0.5, 0.6, 0.5, 0) -- the same coordinates, on the other continent
        map:Show()
        T.eq(#trails(ns), 0)
        trail(1412, 0.2, 0.5, 0.6, 0.5)
        map:SetMapID(947) -- the whole world: no world coordinates
        T.eq(#trails(ns), 0)
        map:SetMapID(1412)
        T.eq(#trails(ns), 1)
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("grows the trail being recorded while the map is open", function()
        local ns, map = start()
        map:Show()
        walkOnMap(1412, 0.2, 0.5, 0.21, 0.5)
        local growing = #live(ns)
        T.truthy(growing >= 2, "one line per step: " .. growing)
        walkOnMap(1412, 0.21, 0.5, 0.22, 0.5)
        T.truthy(#live(ns) > growing)
        T.eq(#trails(ns), 0)
        wait(61)
        T.eq(#live(ns), 0, "the stored trail replaces the live one")
        T.eq(#trails(ns), 1)
    end)

    -- In game, lines drawn into an open map only showed after a zoom (build 70235).
    it("settles lines drawn into an open map on the next frame, like a zoom does", function()
        local ns, map = start()
        map:Show()
        local frame = ns.FootstepsMap.view.frame
        walkOnMap(1412, 0.2, 0.5, 0.21, 0.5)
        Stubs.Advance(0)
        T.truthy(frame.scale ~= nil, "the line layer was rescaled")
        local lines = live(ns)
        T.truthy(#lines >= 2)
        for _, line in ipairs(lines) do
            T.truthy(line.thicknessSets >= 2, "the width is set again after drawing")
            T.eq(line.thickness, 2.5)
        end
    end)

    it("keeps lines equally wide at every zoom", function()
        local ns, map = start()
        trail(1412, 0.2, 0.5, 0.6, 0.5)
        map:Show()
        map:Zoom(2)
        T.eq(trails(ns)[1].thickness, 1.25)
    end)

    it("shows older days lighter in the last 7 days, and nothing when off", function()
        local ns, map = start()
        trail(1412, 0.2, 0.2, 0.6, 0.2)
        Stubs.Advance(DAY)
        trail(1412, 0.2, 0.5, 0.6, 0.5)
        map:Show()
        T.eq(#trails(ns), 1, "today only")

        local button = ns.FootstepsMap.button
        T.eq(button.text, "Footsteps: Today")
        button:Click()
        T.eq(ns.accountDB.settings.footstepsMode, "week")
        T.eq(button.text, "Footsteps: Last 7 days")
        local lines = trails(ns)
        T.eq(#lines, 2)
        local alphas = { lines[1].color[4], lines[2].color[4] }
        table.sort(alphas)
        T.same(alphas, { 0.5, 0.9 })

        button:Click()
        T.eq(button.text, "Footsteps: All")
        T.eq(#trails(ns), 2)
        button:Click()
        T.eq(button.text, "Footsteps: Off")
        T.eq(#trails(ns), 0)
        button:Click()
        T.eq(button.text, "Footsteps: Today")
    end)
end)

describe("from the journal", function()
    it("shows a day's footsteps on the map that holds them", function()
        local ns, map = start()
        trail(1412, 0.2, 0.5, 0.3, 0.5)
        Stubs.Advance(DAY)
        ns.Journal:Open(20261003)
        local link = ns.Journal.ui.pathLink
        T.truthy(link:IsShown())
        map.mapID = 1414
        link:Click()
        T.truthy(map:IsShown())
        T.eq(map:GetMapID(), 1412, "the zone, since the whole trail fits in it")
        T.eq(ns.FootstepsMap:GetMode(), "day")
        T.eq(ns.FootstepsMap.button.text, "Footsteps: 2026-10-03")
        T.eq(#trails(ns), 1)
        T.eq(trails(ns)[1].color[4], 0.9, "the picked day is drawn strongly")

        map:Hide()
        T.eq(ns.FootstepsMap:GetMode(), "today", "back to the usual trails once the map closes")
        map:Show()
        T.eq(#trails(ns), 0)
    end)

    it("opens the continent for a trail that leaves the zone", function()
        local ns, map = start()
        trail(1412, 0.8, 0.5, 1.4, 0.5)
        ns.Journal:Open()
        ns.Journal.ui.pathLink:Click()
        T.eq(map:GetMapID(), 1414)
    end)

    it("offers the map only for days with footsteps", function()
        local ns = start()
        ns.Store:Count("gather", 2770, 1)
        ns.Journal:Open()
        T.falsy(ns.Journal.ui.pathLink:IsShown())
        walkOnMap(1412, 0.2, 0.5, 0.21, 0.5)
        Stubs.Advance(1) -- the journal redraws on the next frame
        T.truthy(ns.Journal.ui.pathLink:IsShown(), "the trail being recorded counts")
    end)

    it("hides the link on a client without the world map's data providers", function()
        local ns = start({ noMap = true })
        trail(1412, 0.2, 0.5, 0.3, 0.5)
        ns.Journal:Open()
        T.falsy(ns.Journal.ui.pathLink:IsShown())
        T.falsy(ns.FootstepsMap:ShowDay(20261003))
        local printed = Stubs.Printed()
        T.truthy(printed[#printed]:find("no place for them"))
    end)
end)
