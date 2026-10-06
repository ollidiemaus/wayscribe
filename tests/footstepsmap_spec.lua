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

local function length(line)
    return math.sqrt((line.x2 - line.x1) ^ 2 + (line.y2 - line.y1) ^ 2)
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
        near(tail.x2, u * WIDTH, "tail x")
        near(tail.y2, -v * HEIGHT, "tail y")
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

local function skulls(ns)
    local deaths, list = ns.FootstepsMap.view.deaths, {}
    for i = 1, deaths.used do
        if deaths.markers[i]:IsShown() then list[#list + 1] = deaths.markers[i] end
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
        local list = skulls(ns)
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
        T.eq(#skulls(ns), 0, "today only")
        ns.FootstepsMap.button:Click()
        T.eq(#skulls(ns), 1, "the last 7 days")
        local tooltip = installTooltip()
        skulls(ns)[1].scripts.OnEnter(skulls(ns)[1])
        T.same(tooltip.lines, { "Died here", "2026-10-03, 12:00 PM" })
        _G.GameTooltip = nil
        ns.FootstepsMap.button:Click()
        ns.FootstepsMap.button:Click()
        T.eq(#skulls(ns), 0, "off")
    end)

    it("adds a skull when you die with the map open, and keeps its size at every zoom", function()
        local ns, map = start()
        map:Show()
        dieAt(1412, 0.5, 0.5)
        T.eq(#skulls(ns), 1)
        map:Zoom(2)
        T.eq(skulls(ns)[1].width, 8)
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
        T.eq(#skulls(ns), 0)
        map:SetMapID(1414)
        T.eq(#skulls(ns), 1, "the continent shows the one outside the zone")
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
