local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local RFC = 389
local RFC_BOSSES = { 2732, 2733, 2734, 2735 } -- Oggleflint, Taragaman, Jergosh, Bazzalan
local TEST_HOLD = 9001                       -- a made-up instance with a map that has an area

local function enter(id, name)
    Stubs.SetInstance(id, "party", name or "Ragefire Chasm")
    Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
end

local function leave()
    Stubs.SetInstance()
    Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
end

local function engage(encounterID) Stubs.Fire("ENCOUNTER_START", encounterID, "Boss", 1, 5) end

local function kill(encounterID)
    Stubs.Fire("ENCOUNTER_END", encounterID, "Boss", 1, 5, 1)
    Stubs.Fire("BOSS_KILL", encounterID, "Boss")
end

local function start(opts)
    local ns = Stubs.LoadAddon(opts or { level = 15 })
    Stubs.Login()
    return ns
end

-- Two cells: the entrance and a crypt that lifts when the player is in the subzone "Crypt".
local function addTestHold(ns)
    ns.StaticData.DungeonMaps[TEST_HOLD] = {
        enUS = "Test Hold", deDE = "Testfeste",
        sections = { { "enter" }, { "area:5001" } },
        floors = { { art = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }, fog = { 0.5, 0.4, 0.3 }, grid = { 2, 1 },
            cells = ns.Codec.EncodeInts({ 1, 1, 2, 1 }) } },
    }
    Stubs.SetAreaName(5001, "Crypt")
end

describe("map data", function()
    it("decodes every floor into its grid, and every section has cells and a name", function()
        local ns = Stubs.LoadAddon()
        T.truthy(next(ns.StaticData.DungeonMaps), "maps")
        for instanceID, map in pairs(ns.StaticData.DungeonMaps) do
            T.truthy(map.enUS and map.deDE, instanceID .. ": names")
            local used = {}
            for i, floor in ipairs(map.floors) do
                local cells = ns.Charted.Cells(floor)
                T.eq(#cells, floor.grid[1] * floor.grid[2], instanceID .. " floor " .. i .. ": cells")
                if floor.art then
                    T.eq(#floor.art, 12, "a dungeon map's tiles")
                else
                    T.eq(#floor.minimap, floor.tiles[1] * floor.tiles[2], "the minimap block")
                end
                T.eq(#floor.fog, 3, "the fog's color")
                for _, section in ipairs(cells) do
                    T.truthy(section >= 0 and section <= #map.sections, "a section the map has")
                    used[section] = true
                end
            end
            for n, section in ipairs(map.sections) do
                T.truthy(used[n], instanceID .. ": section " .. n .. " has cells")
                T.truthy(section[1] == "enter" or section.enUS, instanceID .. ": section " .. n .. " has a name")
            end
        end
    end)
end)

describe("charting a dungeon", function()
    it("lifts the entrance on arrival and a boss's room when the boss is reached", function()
        local ns = start()
        T.same(ns.Charted:GetInstances(), {})
        enter(RFC)
        T.eq(ns.Charted:Facts(RFC).enter, Stubs.Now())
        local arrived = ns.Charted:Progress(RFC)
        T.truthy(arrived > 0 and arrived < 1, "the entrance only")
        Stubs.Advance(300)
        engage(RFC_BOSSES[2]) -- a wipe counts: the room was reached
        T.eq(ns.Charted:Facts(RFC)[RFC_BOSSES[2]], Stubs.Now())
        T.truthy(ns.Charted:Progress(RFC) > arrived)
        T.same(ns.Charted:GetInstances(), { RFC })
        T.eq(ns.Charted:CurrentFloor(RFC), 1)
    end)

    it("keeps what was found over a reload, and the first time it was found", function()
        start()
        enter(RFC)
        local arrived = Stubs.Now()
        kill(RFC_BOSSES[1])
        local ns = Stubs.Relog(nil, true)
        Stubs.Advance(600)
        enter(RFC)
        T.eq(ns.Charted:Facts(RFC).enter, arrived)
        T.truthy(ns.Charted:Facts(RFC)[RFC_BOSSES[1]])
    end)

    it("notes nothing outdoors, or in an instance without a map", function()
        local ns = start()
        engage(RFC_BOSSES[1])
        enter(4242, "Somewhere Else")
        engage(RFC_BOSSES[1])
        T.same(ns.Charted:GetInstances(), {})
        T.eq(next(ns.charDB.charted), nil)
    end)

    it("lifts a subzone's section when the player walks into it", function()
        local ns = start()
        addTestHold(ns)
        enter(TEST_HOLD, "Test Hold")
        T.eq(ns.Charted:Progress(TEST_HOLD), 0.5)
        Stubs.SetSubZone("Crypt")
        Stubs.Fire("ZONE_CHANGED_INDOORS")
        T.truthy(ns.Charted:Facts(TEST_HOLD)["area:5001"])
        T.eq(ns.Charted:Progress(TEST_HOLD), 1)
    end)

    it("writes one journal entry when the whole map is found", function()
        local ns = start()
        enter(RFC)
        for _, id in ipairs(RFC_BOSSES) do kill(id) end
        local charted = ns.Store:GetRecordsOfType("DUNGEON_CHARTED")
        T.eq(#charted, 1)
        T.eq(ns.RecordTypes:Render(charted[1]), "Charted Ragefire Chasm completely")
        T.truthy(charted[1].first)
        T.eq(ns.Charted:Progress(RFC), 1)
        leave()
        enter(RFC)
        kill(RFC_BOSSES[1])
        T.eq(#ns.Store:GetRecordsOfType("DUNGEON_CHARTED"), 1, "once")
    end)

    it("stays off when its tracker is off", function()
        local ns = start()
        ns.Trackers:SetWanted("DungeonMaps", false)
        enter(RFC)
        engage(RFC_BOSSES[1])
        T.same(ns.Charted:GetInstances(), {})
    end)
end)

describe("older runs", function()
    -- A journal that 0.7 wrote: runs and kills, no maps yet.
    local function journalWithRuns(bosses)
        local ns = start()
        local ts = Stubs.Now()
        ns.Store:Append("DUNGEON_COMPLETED", { instanceID = RFC, name = "Ragefire Chasm", bosses = bosses, dur = 1800 },
            { ts = ts })
        ns.Store:Append("BOSS_KILLED", { encounterID = 2734, instanceID = RFC }, { ts = ts + 60 })
        ns.Store:SetState("chartedMaps", nil)
        ns.charDB.charted = {}
        return ts
    end

    it("light up the maps once, at the next login", function()
        local ts = journalWithRuns({ 2732, 2733 })
        local ns = Stubs.Relog()
        local facts = ns.Charted:Facts(RFC)
        T.eq(facts.enter, ts - 1800, "arrived when the run began")
        T.eq(facts[2732], ts)
        T.eq(facts[2734], ts + 60)
        T.eq(facts[2735], nil)
        T.eq(#ns.Store:GetRecordsOfType("DUNGEON_CHARTED"), 0)
        T.eq(ns.Store:GetState("chartedMaps"), ns.StaticData.DungeonMapsVersion)
    end)

    it("chart a whole map as one back-filled entry, dated at the last find", function()
        local ts = journalWithRuns({ 2732, 2733, 2735 })
        local ns = Stubs.Relog()
        local charted = ns.Store:GetRecordsOfType("DUNGEON_CHARTED")
        T.eq(#charted, 1)
        T.eq(charted[1].ts, ts + 60)
        T.truthy(charted[1].bf, "flagged as back-filled")
    end)
end)

describe("the Maps tab", function()
    it("/ws map inside a dungeon opens its map across both pages, under fog", function()
        local ns = start()
        enter(RFC)
        ns.Slash:Handle("map")
        T.eq(ns.Journal.state.tab, "maps")
        T.eq(ns.MapsView.state.selected, RFC)
        T.truthy(ns.MapsView.state.unfolded)
        local map = ns.MapsView.ui.spreadMap
        T.truthy(map.frame:IsShown())
        T.truthy(map.fogUsed > 0, "fog over what wasn't found")
        T.eq(ns.MapsView.ui.spreadTitle:GetText(), "Ragefire Chasm")

        -- Taragaman's room fades out, then the fog is drawn again around it.
        engage(RFC_BOSSES[2])
        local lifted = {}
        for _, n in ipairs(ns.Charted.SectionsOf(RFC, RFC_BOSSES[2])) do lifted[n] = true end
        map:Fade(2)
        for i = 1, map.fogUsed do
            T.falsy(lifted[map.fog[i].section], "no fog left over the boss's room")
        end
    end)

    it("lists the dungeons with how much of each is charted", function()
        local ns = start()
        enter(RFC)
        engage(RFC_BOSSES[1])
        leave()
        ns.Journal:OpenMaps()
        T.same(ns.MapsView.state.instances, { RFC })
        T.falsy(ns.MapsView.state.unfolded)
        T.eq(ns.MapsView.ui.title:GetText(), "Ragefire Chasm")
        T.truthy(ns.MapsView.ui.subtitle:GetText():find("^%d+%% charted · 1 of 4 bosses found · first entered "))
        T.truthy(ns.MapsView.ui.map.frame:IsShown())
        ns.MapsView.ui.unfold:Click()
        T.truthy(ns.MapsView.state.unfolded)
        ns.MapsView.ui.fold:Click()
        T.falsy(ns.MapsView.state.unfolded)
    end)

    it("says how a map starts while there is none", function()
        local ns = start()
        ns.Journal:OpenMaps()
        T.same(ns.MapsView.state.instances, {})
        T.truthy(ns.MapsView.ui.empty:GetText():find("^No maps yet"))
    end)

    it("reads in German", function()
        local ns = start({ level = 15, locale = "deDE" })
        enter(RFC, "Ragefireabgrund")
        ns.Journal:OpenMaps()
        T.eq(ns.MapsView.ui.title:GetText(), "Ragefireabgrund")
        T.truthy(ns.MapsView.ui.subtitle:GetText():find("kartiert · 0 von 4 Bossen gefunden · zuerst betreten am "))
        T.eq(_G.WayscribeJournalFrameTab3.text, "Karten")
    end)
end)

describe("with the maps hidden", function()
    local function entries(ns)
        local texts = {}
        for _, entry in ipairs(ns.DayView.Build(ns.Time.DayKey(Stubs.Now()), function() return true end).entries) do
            texts[#texts + 1] = entry.text
        end
        return table.concat(texts, "\n")
    end

    local function chartAll(ns)
        ns.Options:Set("dungeonMaps", false)
        enter(RFC)
        for _, id in ipairs(RFC_BOSSES) do kill(id) end
    end

    it("still charts in the background, and shows it all when they are back", function()
        local ns = start()
        chartAll(ns)
        T.eq(ns.Charted:Progress(RFC), 1, "every room noted")
        T.eq(#ns.Store:GetRecordsOfType("DUNGEON_CHARTED"), 1, "the entry is written")
        T.falsy(entries(ns):find("Charted Ragefire Chasm completely", 1, true), "but not shown")
        T.truthy(entries(ns):find("Defeated Boss", 1, true), "the kills are")
        ns.Options:Set("dungeonMaps", true)
        T.truthy(entries(ns):find("Charted Ragefire Chasm completely", 1, true))
    end)

    it("leave the entry out of the login recap", function()
        local ns = start()
        chartAll(ns)
        Stubs.Advance(600)
        ns = Stubs.Relog({ now = Stubs.Now() + 3600 })
        local recap = ns.LoginRecap:Collect(true)
        T.truthy(recap and #recap.lines > 0, "the run is recapped")
        for _, line in ipairs(recap.lines) do
            T.falsy(line:find("Charted", 1, true), line)
        end
    end)

    it("have no Maps tab, and /ws map says how to show them", function()
        local ns = start()
        ns.Options:Set("dungeonMaps", false)
        enter(RFC)
        ns.Slash:Handle("map")
        T.falsy(ns.Journal.ui.frame and ns.Journal.ui.frame:IsShown(), "no journal")
        T.truthy(Stubs.Printed()[#Stubs.Printed()]:find("Dungeon maps are turned off", 1, true))
        ns.Journal:Open()
        T.falsy(_G.WayscribeJournalFrameTab3:IsShown())
        T.eq(_G.WayscribeJournalFrameTab4.lastPoint[2], _G.WayscribeJournalFrameTab2, "Your Year next to Notes")
        ns.Options:Set("dungeonMaps", true)
        Stubs.Advance(0) -- the refresh on the next frame
        T.truthy(_G.WayscribeJournalFrameTab3:IsShown())
        T.eq(_G.WayscribeJournalFrameTab4.lastPoint[2], _G.WayscribeJournalFrameTab3)
    end)

    it("turn an open Maps tab to the journal", function()
        local ns = start()
        ns.Journal:OpenMaps()
        T.eq(ns.Journal.state.tab, "maps")
        ns.Options:Set("dungeonMaps", false)
        Stubs.Advance(0)
        T.eq(ns.Journal.state.tab, "journal")
        T.truthy(ns.Journal.ui.journalLeft:IsShown())
        T.falsy(ns.MapsView.ui.map.frame:IsShown())
    end)
end)

describe("the backup", function()
    it("carries what the maps found", function()
        local ns = start()
        enter(RFC)
        engage(RFC_BOSSES[1])
        local text
        ns.Backup:Make({}, function(result) text = result end)
        local _, pos = ns.Backup.Deserialize(text, 6)
        local payload = ns.Backup.Deserialize(text, pos)
        T.same(payload.journal.charted, ns.charDB.charted)
    end)
end)
