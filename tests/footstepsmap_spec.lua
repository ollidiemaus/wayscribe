local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local DAY = 24 * 3600
local WIDTH, HEIGHT = 1000, 668 -- the stub map's canvas

-- opts.noMap: a client without the world map's data providers.
-- opts.openMap: OpenMap's API on the map (Stubs.InstallOpenMap's opts); returned third.
-- opts.before(): runs just before the login (spell names, for example).
local function start(opts)
    opts = opts or {}
    local ns = Stubs.LoadAddon(opts)
    local map = not opts.noMap and Stubs.InstallWorldMap() or nil
    local openMap = opts.openMap and Stubs.InstallOpenMap(map, opts.openMap) or nil
    Stubs.InstallScrollBox()
    if opts.before then opts.before() end
    Stubs.Login()
    return ns, map, openMap
end

local function wait(seconds)
    for _ = 1, seconds do Stubs.Advance(1) end
end

-- Walks in a straight line between two points of map `mapID` (u, v), `pace` yards a second
-- (default 20).
local function walkOnMap(mapID, u1, v1, u2, v2, continent, pace)
    local x1, y1 = Stubs.MapToWorld(mapID, u1, v1)
    local x2, y2 = Stubs.MapToWorld(mapID, u2, v2)
    local steps = math.max(1, math.floor(math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) / (pace or 20)))
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

-- Where a line runs on the canvas: x1, y1, x2, y2 (its frame may span OpenMap's stitched world).
local function ends(line)
    local x1, y1 = Stubs.OnParent(line.parent, line.x1, line.y1)
    local x2, y2 = Stubs.OnParent(line.parent, line.x2, line.y2)
    return x1, y1, x2, y2
end

-- Where a marker's centre is on the canvas: x, y.
local function centre(marker)
    return Stubs.OnParent(marker:GetParent(), marker.lastPoint[4], marker.lastPoint[5])
end

local function length(line)
    local x1, y1, x2, y2 = ends(line)
    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

local function near(actual, expected, what)
    if math.abs(actual - expected) > 0.5 then
        error(what .. ": expected " .. expected .. ", got " .. actual, 2)
    end
end

-- A line from map point (u1, v1) to (u2, v2) on the stub canvas.
local function expectLine(line, u1, v1, u2, v2)
    local x1, y1, x2, y2 = ends(line)
    near(x1, u1 * WIDTH, "x1")
    near(y1, -v1 * HEIGHT, "y1")
    near(x2, u2 * WIDTH, "x2")
    near(y2, -v2 * HEIGHT, "y2")
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

    -- On the small map (canvas scale about 0.5), 8-yard steps are under a pixel: on build 70235
    -- such lines broke up. They are merged into lines of at least 3 pixels (6 canvas units here).
    it("never draws a line too short to show on screen, and keeps a tail to the player", function()
        local ns, map = start()
        map.canvasScale = 0.5
        map:Show()
        walkOnMap(1412, 0.2, 0.5, 0.25, 0.5, 1, 9)
        -- One more step of 9 yards (under 2 canvas units): too short for a line, so the tail bridges it.
        local position = Stubs.state.position
        Stubs.SetPosition(1, position.x, position.y - 9)
        Stubs.Advance(1)
        local lines = live(ns)
        T.truthy(#lines >= 3, "merged lines: " .. #lines)
        for _, line in ipairs(lines) do
            T.truthy(length(line) >= 6 - 1e-6, "line of " .. length(line) .. " canvas units")
        end
        local tail = ns.FootstepsMap.view.tail
        T.truthy(tail and tail:IsShown(), "the tail is drawn")
        position = Stubs.state.position
        local u, v = Stubs.WorldToMap(1412, position.x, position.y)
        local _, _, tailX, tailY = ends(tail)
        near(tailX, u * WIDTH, "tail x")
        near(tailY, -v * HEIGHT, "tail y")
        T.eq(tail.thickness, 5, "2.5 pixels at half scale")
    end)

    it("draws again with the detail of the new zoom", function()
        local ns, map = start()
        local x, y = Stubs.MapToWorld(1412, 0.5, 0.5)
        for i = 0, 60 do
            local angle = i / 60 * math.pi
            Stubs.SetPosition(1, x + 300 * math.cos(angle), y + 300 * math.sin(angle))
            Stubs.Advance(1)
        end
        wait(61)
        map.canvasScale = 0.5
        map:Show()
        local zoomedOut = #trails(ns)
        map:Zoom(0.6)
        Stubs.Advance(1)
        T.eq(#trails(ns), zoomedOut, "a small zoom keeps the lines")
        map:Zoom(4)
        Stubs.Advance(1)
        T.truthy(#trails(ns) > zoomedOut, "more detail zoomed in: " .. zoomedOut .. " -> " .. #trails(ns))
    end)

    it("arms one timer for a whole zoom animation and draws once it settles", function()
        local ns, map = start()
        local x, y = Stubs.MapToWorld(1412, 0.5, 0.5)
        for i = 0, 60 do
            local angle = i / 60 * math.pi
            Stubs.SetPosition(1, x + 300 * math.cos(angle), y + 300 * math.sin(angle))
            Stubs.Advance(1)
        end
        wait(61)
        map.canvasScale = 0.5
        map:Show()
        local zoomedOut = #trails(ns)
        local armed = Stubs.state.timersArmed
        for step = 1, 20 do
            map:Zoom(0.5 + step * 0.2) -- one call per frame of the animation, ending at 4.5
        end
        T.eq(Stubs.state.timersArmed - armed, 1, "one timer for twenty zoom steps")
        T.eq(#trails(ns), zoomedOut, "nothing drawn before the zoom settles")
        Stubs.Advance(1)
        T.truthy(#trails(ns) > zoomedOut, "drawn once settled")
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

-- The map's markers (skulls, spell icons) that are shown.
local function markers(ns)
    local pool, list = ns.FootstepsMap.view.markers, {}
    for i = 1, pool.used do
        if pool.frames[i]:IsShown() then list[#list + 1] = pool.frames[i] end
    end
    return list
end

local function installTooltip()
    local tooltip = { lines = {} }
    function tooltip:SetOwner() self.lines = {} end
    function tooltip:SetText(text) self.lines[#self.lines + 1] = text end
    function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tooltip:Show() end
    function tooltip:Hide() end
    _G.GameTooltip = tooltip
    return tooltip
end

local function dieAt(mapID, u, v)
    Stubs.SetPosition(1, Stubs.MapToWorld(mapID, u, v))
    Stubs.Fire("PLAYER_DEAD")
end

describe("deaths on the map", function()
    it("marks a death with a skull where it happened, its time on mouseover", function()
        local ns, map = start()
        dieAt(1412, 0.3, 0.6)
        map:Show()
        local list = markers(ns)
        T.eq(#list, 1)
        local point = list[1].lastPoint
        T.eq(point[1], "CENTER")
        near(point[4], 0.3 * WIDTH, "x")
        near(point[5], -0.6 * HEIGHT, "y")
        T.eq(list[1].width, 16)
        local tooltip = installTooltip()
        list[1].scripts.OnEnter(list[1])
        T.same(tooltip.lines, { "Died here", "12:00 PM" })
        _G.GameTooltip = nil
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("shows the deaths of the days shown, with the date when it isn't today", function()
        local ns, map = start()
        dieAt(1412, 0.3, 0.6)
        Stubs.Advance(DAY)
        map:Show()
        T.eq(#markers(ns), 0, "today only")
        ns.FootstepsMap.button:Click()
        T.eq(#markers(ns), 1, "the last 7 days")
        local tooltip = installTooltip()
        markers(ns)[1].scripts.OnEnter(markers(ns)[1])
        T.same(tooltip.lines, { "Died here", "2026-10-03, 12:00 PM" })
        _G.GameTooltip = nil
        ns.FootstepsMap.button:Click()
        ns.FootstepsMap.button:Click()
        T.eq(#markers(ns), 0, "off")
    end)

    it("adds a skull when you die with the map open, and keeps its size at every zoom", function()
        local ns, map = start()
        map:Show()
        dieAt(1412, 0.5, 0.5)
        T.eq(#markers(ns), 1)
        map:Zoom(2)
        T.eq(markers(ns)[1].width, 8)
    end)

    it("leaves out deaths elsewhere: off this map or without a position", function()
        local ns, map = start()
        dieAt(1412, 1.5, 0.5) -- on the continent, outside the zone
        Stubs.Advance(60)
        Stubs.SetInstance(389, "party", "Ragefire Chasm")
        Stubs.SetPosition()
        Stubs.Fire("PLAYER_DEAD")
        Stubs.SetInstance()
        map:Show()
        T.eq(#markers(ns), 0)
        map:SetMapID(1414)
        T.eq(#markers(ns), 1, "the continent shows the one outside the zone")
    end)
end)

describe("journeys on the map", function()
    it("marks a hearthstone with its icon where it left and where it arrived", function()
        local ns, map = start({ before = function()
            Stubs.state.spellNames[8690] = "Hearthstone"
            Stubs.state.spellIcons[8690] = 134414
        end })
        walkOnMap(1412, 0.3, 0.6, 0.31, 0.6)
        Stubs.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-1", 8690)
        Stubs.SetSubZone("Bloodhoof")
        Stubs.SetPosition(1, Stubs.MapToWorld(1412, 0.6, 0.3))
        wait(3)
        map:Show()
        local list = markers(ns)
        T.eq(#list, 2)
        local departure, arrival = list[1], list[2]
        T.eq(departure.icon.file, 134414)
        near(departure.lastPoint[4], 0.31 * WIDTH, "departure x")
        near(arrival.lastPoint[4], 0.6 * WIDTH, "arrival x")
        near(arrival.lastPoint[5], -0.3 * HEIGHT, "arrival y")
        local tooltip = installTooltip()
        departure.scripts.OnEnter(departure)
        T.eq(tooltip.lines[1], "Hearthstone to Bloodhoof")
        arrival.scripts.OnEnter(arrival)
        T.eq(tooltip.lines[1], "Arrived by Hearthstone")
        _G.GameTooltip = nil
        T.eq(#ns.Log:GetEntries(), 0)
    end)
end)

-- Map 1414's point (u, v), in yards.
local function kalimdor(u, v)
    return Stubs.MapToWorld(1414, u, v)
end

-- More maps of Kalimdor in the proportions of the stub canvas, as the client's are: 1413 inside
-- it, 1416 most of it. Removed again after fn.
local function withKalimdorMaps(fn)
    Stubs.MAPS[1413] = { name = "The Barrens", continent = 1, top = 2000, left = 0, width = 6000, height = 4000,
        parent = 1414, type = 3 }
    Stubs.MAPS[1416] = { name = "Most of Kalimdor", continent = 1, top = 5000, left = 8000, width = 15000,
        height = 10000, parent = 1414, type = 2 }
    local ok, err = pcall(fn)
    Stubs.MAPS[1413], Stubs.MAPS[1416] = nil, nil
    if not ok then error(err, 0) end
end

-- Counts the Footsteps redraws from now on: returns a function giving the count.
local function countRedraws(ns)
    local count, redraw = 0, ns.FootstepsMap.Redraw
    ns.FootstepsMap.Redraw = function(...)
        count = count + 1
        return redraw(...)
    end
    return function() return count end
end

describe("on OpenMap's stitched map", function()
    it("draws trails above OpenMap's art, past the edge of the map underneath", function()
        local ns, map = start({ openMap = {} })
        trail(1412, 0.8, 0.3, 1.3, 0.3)
        map:Show()
        local lines = trails(ns)
        T.eq(#lines, 1)
        expectLine(lines[1], 0.8, 0.3, 1.3, 0.3)
        T.truthy(ns.FootstepsMap.view.frame:GetFrameLevel() > 2000, "above the art")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("draws the trails of both continents, each in its place", function()
        local ns, map = start({ openMap = {} })
        map.mapID = 1414
        trail(1414, 0.2, 0.5, 0.3, 0.5)
        trail(1414, 0.6, 0.4, 0.7, 0.4, 0) -- the same yards in the Eastern Kingdoms: east of Kalimdor
        map:Show()
        local lines = trails(ns)
        T.eq(#lines, 2)
        expectLine(lines[1], 1.6, 0.4, 1.7, 0.4) -- newest first
        expectLine(lines[2], 0.2, 0.5, 0.3, 0.5)
    end)

    it("breaks a trail where OpenMap can't place a point", function()
        local ns, map = start({ openMap = {} })
        map.mapID = 1414
        -- Out past Kalimdor's yards and back.
        local corners = { { 0.90, 0.50 }, { 0.95, 0.45 }, { 1.05, 0.50 }, { 0.97, 0.55 }, { 0.92, 0.60 } }
        for i = 1, #corners - 1 do
            walkOnMap(1414, corners[i][1], corners[i][2], corners[i + 1][1], corners[i + 1][2], 1, 80)
        end
        wait(61)
        map:Show()
        local lines = trails(ns)
        T.truthy(#lines >= 2, "lines: " .. #lines)
        for _, line in ipairs(lines) do
            local x1, _, x2 = ends(line)
            T.truthy(x1 <= WIDTH + 0.5 and x2 <= WIDTH + 0.5, "no line out to the unplaced point")
            T.truthy(math.abs(x2 - x1) < 0.08 * WIDTH, "no line across the gap")
        end
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("runs a trail up to its last placed point before a break", function()
        local ns, map = start({ openMap = {} })
        map.mapID = 1414
        map:Show()
        -- Steps of about 21 yards, a line every three: the last two steps before Kalimdor's edge are
        -- too short for a line of their own.
        walkOnMap(1414, 0.9945, 0.5, 1.004, 0.5)
        local reach = 0
        for _, line in ipairs(live(ns)) do
            local x1, _, x2 = ends(line)
            reach = math.max(reach, x1, x2)
        end
        T.truthy(reach > 0.999 * WIDTH and reach <= WIDTH, "the trail reaches " .. reach)
    end)

    it("draws again when the map underneath changes or the maps switch, not on a pan", function()
        local ns, map, openMap = start({ openMap = {} })
        trail(1412, 0.2, 0.5, 0.6, 0.5)
        trail(1412, 0.2, 0.5, 0.6, 0.5, 0)
        map:Show()
        T.eq(#trails(ns), 2)
        local placed = openMap.placed
        openMap.Pan(0.3, 0.4)
        T.eq(openMap.placed, placed, "a pan places nothing again")
        T.eq(#trails(ns), 2)

        map:SetMapID(1414)
        local lines = trails(ns)
        T.eq(#lines, 2)
        local u1, v1 = Stubs.WorldToMap(1414, Stubs.MapToWorld(1412, 0.2, 0.5))
        local u2, v2 = Stubs.WorldToMap(1414, Stubs.MapToWorld(1412, 0.6, 0.5))
        expectLine(lines[2], u1, v1, u2, v2)

        openMap.SetStitched(false)
        T.eq(#trails(ns), 1, "Blizzard's map: Kalimdor's only")
        T.truthy(ns.FootstepsMap.view.frame:GetFrameLevel() < 2000, "at the map's own level")
        openMap.SetStitched(true)
        T.eq(#trails(ns), 2)
        T.truthy(ns.FootstepsMap.view.frame:GetFrameLevel() > 2000)
    end)

    it("only moves the drawing when OpenMap switches the map underneath", function()
        local ns, map, openMap = start({ openMap = {} })
        withKalimdorMaps(function()
            trail(1412, 0.2, 0.5, 0.6, 0.5)
            trail(1412, 0.2, 0.5, 0.6, 0.5, 0)
            map:Show()
            local redraws = countRedraws(ns)
            local lines = trails(ns)
            local first, placed = { lines[1].x1, lines[1].y1 }, openMap.placed
            map:SetMapID(1413)
            T.eq(redraws(), 0, "not drawn again")
            T.eq(openMap.placed, placed, "nothing placed again")
            local now = trails(ns)
            T.truthy(#now == 2 and now[1] == lines[1] and now[2] == lines[2], "the same lines")
            T.same({ lines[1].x1, lines[1].y1 }, first)
            local u1, v1 = Stubs.WorldToMap(1413, Stubs.MapToWorld(1412, 0.2, 0.5))
            local u2, v2 = Stubs.WorldToMap(1413, Stubs.MapToWorld(1412, 0.6, 0.5))
            expectLine(lines[2], u1, v1, u2, v2)
            near(lines[2].thickness * lines[2].parent:GetScale(), 2.5, "the same width on screen")

            -- OpenMap keeps the view as it switches: the new map's canvas scale makes up for its
            -- size, which is no zoom.
            map:SetMapID(1416)
            map:Zoom(15000 / 5137.5)
            Stubs.Advance(1)
            T.eq(redraws(), 0, "a switch isn't a zoom")
            local u, v = Stubs.WorldToMap(1416, Stubs.MapToWorld(1412, 0.2, 0.5))
            local x1, y1 = ends(lines[2])
            near(x1, u * WIDTH, "x on the new map")
            near(y1, -v * HEIGHT, "y on the new map")
            near(lines[2].thickness * lines[2].parent:GetScale() * map.canvasScale, 2.5, "the width on screen")

            openMap.SetStitched(true) -- OpenMap says so again as its map opens
            T.eq(redraws(), 0, "already drawn for the stitched map")
            T.eq(#ns.Log:GetEntries(), 0)
        end)
    end)

    it("draws only the trails around the view, and again as the view moves on", function()
        local ns, map, openMap = start({ openMap = {} })
        -- One trail in Kalimdor and the same yards in the Eastern Kingdoms, half the stitched world east.
        trail(1412, 0.2, 0.5, 0.6, 0.5)
        trail(1412, 0.2, 0.5, 0.6, 0.5, 0)
        local kalimdorU, v = openMap.WorldFromMap(1412, 0.4, 0.5)
        map.ScrollContainer:SetSize(500, 334)
        map.canvasScale = 2
        openMap.Pan(kalimdorU, v)
        map:Show()
        local lines = trails(ns)
        T.eq(#lines, 1, "Kalimdor's only")
        expectLine(lines[1], 0.2, 0.5, 0.6, 0.5)
        local redraws = countRedraws(ns)
        openMap.Pan(kalimdorU + 0.01, v)
        T.eq(redraws(), 0, "a short pan stays inside what's drawn")
        openMap.Pan(kalimdorU + 0.5, v) -- over to the Eastern Kingdoms
        T.eq(redraws(), 1)
        lines = trails(ns)
        T.eq(#lines, 1, "the Eastern Kingdoms' only")
        local x1 = ends(lines[1])
        T.truthy(x1 > WIDTH, "east of the map underneath: " .. x1)
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("draws over the lines shown for a new zoom, placing nothing again", function()
        local ns, map, openMap = start({ openMap = {} })
        local x, y = Stubs.MapToWorld(1412, 0.5, 0.5)
        for i = 0, 60 do
            local angle = i / 60 * math.pi
            Stubs.SetPosition(1, x + 300 * math.cos(angle), y + 300 * math.sin(angle))
            Stubs.Advance(1)
        end
        wait(61)
        map:Show()
        map:Zoom(4)
        Stubs.Advance(1)
        local zoomedIn = trails(ns)
        local placed = openMap.placed
        map:Zoom(0.5)
        Stubs.Advance(1)
        -- (the trail being recorded is placed again: a few points at most)
        T.truthy(openMap.placed - placed < 10, "the trail's 61 points are kept: " .. openMap.placed - placed)
        local zoomedOut = trails(ns)
        T.truthy(#zoomedOut < #zoomedIn, #zoomedIn .. " -> " .. #zoomedOut)
        T.eq(zoomedOut[1], zoomedIn[1], "the same lines, drawn over")
        local pool = ns.FootstepsMap.view.trails
        for i = pool.used + 1, #pool.lines do
            T.falsy(pool.lines[i]:IsShown(), "line " .. i .. " of the older drawing is hidden")
        end
    end)

    it("grows the trail being recorded past the map's edge, with its tail to the player", function()
        local ns, map = start({ openMap = {} })
        map:Show()
        walkOnMap(1412, 1.2, 0.5, 1.25, 0.5)
        T.truthy(#live(ns) >= 2, "lines: " .. #live(ns))
        local position = Stubs.state.position
        Stubs.SetPosition(1, position.x, position.y - 9) -- too short a step for a line
        Stubs.Advance(1)
        local tail = ns.FootstepsMap.view.tail
        T.truthy(tail and tail:IsShown())
        local u, v = Stubs.WorldToMap(1412, position.x, position.y - 9)
        T.truthy(u > 1, "past the edge")
        local _, _, tailX, tailY = ends(tail)
        near(tailX, u * WIDTH, "tail x")
        near(tailY, -v * HEIGHT, "tail y")
    end)

    it("keeps line widths on screen and draws detail for the settled zoom", function()
        local ns, map = start({ openMap = {} })
        local x, y = Stubs.MapToWorld(1412, 0.5, 0.5)
        for i = 0, 60 do
            local angle = i / 60 * math.pi
            Stubs.SetPosition(1, x + 300 * math.cos(angle), y + 300 * math.sin(angle))
            Stubs.Advance(1)
        end
        wait(61)
        map.canvasScale = 0.5
        map:Show()
        local zoomedOut = #trails(ns)
        map:Zoom(4)
        T.eq(trails(ns)[1].thickness, 2.5 / 4)
        Stubs.Advance(1)
        T.truthy(#trails(ns) > zoomedOut, "more detail zoomed in: " .. zoomedOut .. " -> " .. #trails(ns))
    end)

    it("marks deaths and journeys anywhere on the stitched world, above OpenMap's art", function()
        local ns, map = start({ openMap = {}, before = function()
            Stubs.state.spellNames[8690] = "Hearthstone"
            Stubs.state.spellIcons[8690] = 134414
        end })
        dieAt(1412, 1.5, 0.5)
        Stubs.Advance(60)
        walkOnMap(1412, 0.3, 0.6, 0.31, 0.6)
        Stubs.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-1", 8690)
        Stubs.SetSubZone("Bloodhoof")
        Stubs.SetPosition(0, kalimdor(0.5, 0.5))
        wait(3)
        map:Show()
        local list = markers(ns)
        T.eq(#list, 3)
        near((centre(list[1])), 1.5 * WIDTH, "the skull past the zone's edge")
        local u, v = Stubs.WorldToMap(1412, kalimdor(1.5, 0.5))
        local x, y = centre(list[3])
        near(x, u * WIDTH, "arrived in the Eastern Kingdoms: x")
        near(y, -v * HEIGHT, "y")
        T.truthy(list[1]:GetParent():GetFrameLevel() > 2000)
        map:Zoom(2)
        T.eq(list[1].width, 8)
        dieAt(1412, 0.5, 0.5)
        T.eq(#markers(ns), 4, "a new skull while the map is open")
    end)

    it("is left alone by an OpenMap too old to place points", function()
        local ns, map = start({ openMap = { version = 1 } })
        trail(1412, 0.8, 0.3, 1.3, 0.3)
        trail(1412, 0.2, 0.5, 0.6, 0.5, 0)
        map:Show()
        local lines = trails(ns)
        T.eq(#lines, 1)
        expectLine(lines[1], 0.8, 0.3, 1, 0.3)
        T.truthy(ns.FootstepsMap.view.frame:GetFrameLevel() < 2000)
        T.eq(#ns.Log:GetEntries(), 0)
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

    it("glides OpenMap's stitched map to the day's trails", function()
        local ns, map, openMap = start({ openMap = {} })
        trail(1412, 0.2, 0.5, 0.4, 0.6)
        ns.Journal:Open()
        ns.Journal.ui.pathLink:Click()
        T.truthy(map:IsShown())
        T.eq(#openMap.glides, 1)
        local glide = openMap.glides[1]
        -- The fake stitched world: Kalimdor's map 1414 squeezed into its west half.
        local u1, v1 = Stubs.WorldToMap(1414, Stubs.MapToWorld(1412, 0.2, 0.5))
        local u2, v2 = Stubs.WorldToMap(1414, Stubs.MapToWorld(1412, 0.4, 0.6))
        T.truthy(math.abs(glide.u - (u1 + u2) / 4) < 1e-4, "u: " .. glide.u)
        T.truthy(math.abs(glide.v - (v1 + v2) / 2) < 1e-4, "v: " .. glide.v)
        local extent = math.max(math.abs(u2 - u1) / 2, math.abs(v2 - v1))
        T.truthy(glide.zoom > 1 and glide.zoom * extent <= 1, "the trails fit: zoom " .. glide.zoom)
        T.eq(#trails(ns), 1)
    end)

    it("opens the map that holds the day when Blizzard's map shows, OpenMap or not", function()
        local ns, map, openMap = start({ openMap = { stitched = false } })
        trail(1412, 0.2, 0.5, 0.3, 0.5)
        map.mapID = 1414
        ns.Journal:Open()
        ns.Journal.ui.pathLink:Click()
        T.eq(map:GetMapID(), 1412)
        T.eq(#openMap.glides, 0)
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
