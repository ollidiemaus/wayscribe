local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

-- Durotar and Thunder Bluff (cities are zone maps directly under the continent, UiMap.db2 of build
-- 70374) and a cave in Mulgore, next to the stub's Mulgore and Kalimdor.
local EXTRA = {
    [1411] = { name = "Durotar", parent = 1414, type = 3 },
    [1456] = { name = "Thunder Bluff", parent = 1414, type = 3 },
    [9001] = { name = "Palemane Rock", parent = 1412, type = 5 },
}

local function withMaps(fn)
    for mapID, map in pairs(EXTRA) do Stubs.MAPS[mapID] = map end
    local ok, err = pcall(fn)
    for mapID in pairs(EXTRA) do Stubs.MAPS[mapID] = nil end
    if not ok then error(err, 0) end
end

-- Logs in on `map` and lets the first look happen.
local function start(map, opts)
    local ns = Stubs.LoadAddon(opts)
    Stubs.SetBestMap(map)
    if opts and opts.setup then opts.setup() end
    Stubs.Login()
    Stubs.Advance(1)
    return ns
end

local function walkTo(map, event)
    Stubs.SetBestMap(map)
    Stubs.Fire(event or "ZONE_CHANGED_NEW_AREA")
    Stubs.Advance(1)
end

local function visits(ns)
    local maps = {}
    for _, record in ipairs(ns.Store:GetRecordsOfType("FIRST_VISIT")) do maps[#maps + 1] = record.data.map end
    return maps
end

describe("first visits", function()
    it("start a level 1 character's journal with its starting zone", function()
        local ns = start(1412, { level = 1 })
        local list = ns.Store:GetRecordsOfType("FIRST_VISIT")
        T.eq(#list, 1)
        T.same(list[1].data, { map = 1412 })
        T.truthy(list[1].first)
        T.eq(ns.RecordTypes:Render(list[1]), "First time in Mulgore")
        T.eq(ns.RecordTypes:CategoryOf("FIRST_VISIT"), "travel")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("keep the first look silent above level 1, then record each new zone once", function()
        withMaps(function()
            local ns = start(1412)
            T.same(visits(ns), {})
            walkTo(1456)
            walkTo(1412)
            walkTo(1456)
            T.same(visits(ns), { 1456 }, "a city is a zone of its own, and the first zone was known")
            T.eq(ns.RecordTypes:Render(ns.Store:GetRecordsOfType("FIRST_VISIT")[1]), "First time in Thunder Bluff")
        end)
    end)

    it("take the zones the world map shows explored as visited", function()
        withMaps(function()
            local ns = start(1412, { setup = function() Stubs.SetExplored({ [1411] = true }) end })
            walkTo(1411)
            T.same(visits(ns), {})
            walkTo(1456)
            T.same(visits(ns), { 1456 })
        end)
    end)

    it("still record a level 1 character's starting zone when its map shows it explored", function()
        local ns = start(1412, { level = 1, setup = function() Stubs.SetExplored({ [1412] = true }) end })
        T.same(visits(ns), { 1412 })
    end)

    it("count a smaller map as the zone it lies in", function()
        withMaps(function()
            local ns = start(9001, { level = 1 })
            T.same(visits(ns), { 1412 })
        end)
    end)

    it("leave out instances and zones flown over, and count the zone where a flight lands", function()
        withMaps(function()
            local ns = start(1412)
            Stubs.SetInstance(43, "party", "Wailing Caverns")
            walkTo(1411, "PLAYER_ENTERING_WORLD")
            T.same(visits(ns), {}, "inside an instance")
            Stubs.SetInstance()
            Stubs.SetBestMap(1412)
            Stubs.SetTaxi(true)
            walkTo(1456)
            T.same(visits(ns), {}, "on a taxi")
            Stubs.SetTaxi(false)
            Stubs.Fire("PLAYER_CONTROL_GAINED")
            Stubs.Advance(1)
            T.same(visits(ns), { 1456 })
        end)
    end)

    it("look once for a burst of events", function()
        withMaps(function()
            local ns = start(1412)
            Stubs.SetBestMap(1456)
            Stubs.Fire("ZONE_CHANGED_NEW_AREA")
            Stubs.Fire("PLAYER_ENTERING_WORLD")
            Stubs.Fire("ZONE_CHANGED_NEW_AREA")
            Stubs.Advance(1)
            T.same(visits(ns), { 1456 })
        end)
    end)

    it("never repeat a visit, after a reload or when the journal comes back without the tracker's state", function()
        start(1412, { level = 1 })
        local ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        T.same(visits(ns), { 1412 })
        ns.Store:SetState("visits", nil)
        ns = Stubs.Relog({ level = 1 })
        Stubs.Advance(1)
        T.same(visits(ns), { 1412 }, "the journal's own firsts know the zone")
    end)

    it("stay silent without the map APIs", function()
        withMaps(function()
            local ns = Stubs.LoadAddon()
            _G.C_MapExplorationInfo = nil
            Stubs.SetBestMap(1412)
            Stubs.Login()
            Stubs.Advance(1)
            T.eq(ns.Compat.has.mapExploration, false)
            walkTo(1456)
            T.same(visits(ns), { 1456 }, "without explored zones, only the first zone is known")
            _G.C_Map.GetMapInfo = function() error("no maps") end
            walkTo(1411)
            T.same(visits(ns), { 1456 })
            Stubs.SetBestMap(nil)
            _G.C_Map.GetBestMapForUnit = function() return nil end
            Stubs.Fire("ZONE_CHANGED_NEW_AREA")
            Stubs.Advance(1)
            T.eq(#ns.Log:GetEntries(), 0)
        end)
    end)

    it("add a line to the Footsteps card", function()
        withMaps(function()
            local ns = start(1412, { level = 1 })
            walkTo(1456)
            ns.Store:Count("travel", "ground", 1760)
            local footsteps
            for _, card in ipairs(ns.YearCards:Build(2026)) do
                if card.id == "footsteps" then footsteps = card end
            end
            T.same(footsteps.lines, { "2 zones visited for the first time" })
        end)
    end)

    it("read in German", function()
        local ns = start(1412, { level = 1, locale = "deDE" })
        T.eq(ns.RecordTypes:Render(ns.Store:GetRecordsOfType("FIRST_VISIT")[1]), "Zum ersten Mal in Mulgore")
        ns.Store:Count("travel", "ground", 1760)
        for _, card in ipairs(ns.YearCards:Build(2026)) do
            if card.id == "footsteps" then T.same(card.lines, { "1 Zone zum ersten Mal besucht" }) end
        end
    end)
end)
