local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

-- Durotar and Thunder Bluff (zone maps under Kalimdor, UiMap.db2 of build 70374), next to the stub's
-- Mulgore and Kalimdor.
local EXTRA = {
    [1411] = { name = "Durotar", parent = 1414, type = 3 },
    [1456] = { name = "Thunder Bluff", parent = 1414, type = 3 },
}

local function withMaps(fn)
    for mapID, map in pairs(EXTRA) do Stubs.MAPS[mapID] = map end
    local ok, err = pcall(fn)
    for mapID in pairs(EXTRA) do Stubs.MAPS[mapID] = nil end
    if not ok then error(err, 0) end
end

-- Logs in on Mulgore, developer mode on or off, and lets First visits take its first look. The other
-- trackers are switched off, so the trace holds only First visits' looks.
local function start(devMode, opts)
    opts = opts or {}
    opts.only = "FirstVisits"
    opts.accountDB = { schema = 1, settings = { devMode = devMode or nil }, log = {}, characters = {} }
    local ns = Stubs.LoadAddon(opts)
    Stubs.SetBestMap(1412)
    if opts.setup then opts.setup() end
    Stubs.Login()
    Stubs.Advance(1)
    return ns
end

local function walkTo(map, event)
    Stubs.SetBestMap(map)
    Stubs.Fire(event or "ZONE_CHANGED_NEW_AREA")
    Stubs.Advance(1)
end

-- What `/ws trace <args>` prints, without the chat prefix and the lines' time stamps.
local function shown(ns, args)
    local before = #Stubs.Printed()
    ns.Slash:Handle("trace" .. (args and " " .. args or ""))
    local lines = {}
    for i = before + 1, #Stubs.Printed() do
        local line = Stubs.Printed()[i]:gsub("^|c%x+Wayscribe|r: ", "")
        lines[#lines + 1] = (line:gsub("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d ", ""))
    end
    return lines
end

describe("launch trace", function()
    it("keeps a line for each First visits look, with the events that asked and the zone it read", function()
        withMaps(function()
            local ns = start(true, { level = 1 })
            walkTo(1456)
            T.same(shown(ns), {
                'FirstVisits enable+PLAYER_ENTERING_WORLD: taxi=false instance="none" map=1412 zone=1412'
                    .. " level=1 explored={} -> recorded",
                'FirstVisits ZONE_CHANGED_NEW_AREA: taxi=false instance="none" map=1456 zone=1456 -> recorded',
            })
        end)
    end)

    it("keeps the looks that end without an entry, and says why", function()
        withMaps(function()
            local ns = start(true, { setup = function() Stubs.SetExplored({ [1456] = true, [1411] = true }) end })
            walkTo(1456)
            Stubs.SetInstance(43, "party", "Wailing Caverns")
            walkTo(1411, "PLAYER_ENTERING_WORLD")
            Stubs.SetInstance()
            Stubs.SetTaxi(true)
            walkTo(1412)
            T.same(shown(ns), {
                'FirstVisits enable+PLAYER_ENTERING_WORLD: taxi=false instance="none" map=1412 zone=1412'
                    .. " level=10 explored={1411,1456} -> first look",
                'FirstVisits ZONE_CHANGED_NEW_AREA: taxi=false instance="none" map=1456 zone=1456 -> known',
                'FirstVisits PLAYER_ENTERING_WORLD: taxi=false instance="party" map=1411 zone=1411 -> in an instance',
                'FirstVisits ZONE_CHANGED_NEW_AREA: taxi=true instance="none" map=1412 zone=1412 -> on a taxi',
            })
        end)
    end)

    it("names a zone recorded before, and a burst of events as one look", function()
        withMaps(function()
            local ns = start(true, { level = 1 })
            walkTo(1456)
            Stubs.SetBestMap(1412)
            Stubs.Fire("ZONE_CHANGED_NEW_AREA")
            Stubs.Fire("PLAYER_CONTROL_GAINED")
            Stubs.Fire("ZONE_CHANGED_NEW_AREA")
            Stubs.Advance(1)
            local lines = shown(ns)
            T.eq(#lines, 3)
            T.eq(lines[3], 'FirstVisits ZONE_CHANGED_NEW_AREA+PLAYER_CONTROL_GAINED: taxi=false instance="none"'
                .. " map=1412 zone=1412 -> recorded before")
        end)
    end)

    it("shows a missing value as missing and a secret one as secret", function()
        local ns = start(true)
        _G.C_Map.GetBestMapForUnit = function() return nil end
        Stubs.Fire("ZONE_CHANGED_NEW_AREA")
        Stubs.Advance(1)
        ns.Trace:Add("Gold", "PLAYER_MONEY", "taken", "money", Stubs.SECRET, "saved", nil, "held", 3000000000,
            "factions", { [72] = true, [Stubs.SECRET] = true, [69] = true })
        local lines = shown(ns)
        T.eq(lines[2], 'FirstVisits ZONE_CHANGED_NEW_AREA: taxi=false instance="none" map=missing zone=missing -> no zone')
        T.eq(lines[3], "Gold PLAYER_MONEY: money=secret saved=missing held=3000000000 factions={69,72,secret} -> taken")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("never raises, whatever a tracker hands it or the saved file holds", function()
        local ns = start(true)
        _G.WayscribeDB.trace = "broken"
        ns.Trace:Add("Guild", "PLAYER_GUILD_UPDATE", "joined", "guild", "Red|cffHand")
        ns.Trace:Add("Guild", "PLAYER_GUILD_UPDATE", "joined", true, 1)
        local lines = shown(ns)
        T.eq(lines[1], 'Guild PLAYER_GUILD_UPDATE: guild="Red||cffHand" -> joined')
        T.truthy(lines[2]:find("^Guild PLAYER_GUILD_UPDATE: trace error: .+ %-> joined$"), lines[2])
        T.eq(#lines, 2)
    end)

    it("keeps nothing outside developer mode, and says so", function()
        withMaps(function()
            local ns = start(false, { level = 1 })
            walkTo(1456)
            T.same(shown(ns), { "The launch trace only records in developer mode (/ws dev)." })
            ns.Slash:Handle("dev")
            T.same(shown(ns), { "The launch trace is empty. It fills as the launch trackers look at the game." })
            walkTo(1411)
            T.eq(#shown(ns), 1)
        end)
    end)

    it("keeps the last 500 lines with the time of each, shows the newest 20 and clears", function()
        local ns = start(true)
        T.same(shown(ns, "clear"), { "Launch trace cleared." })
        Stubs.SetTime(os.time({ year = 2026, month = 11, day = 4, hour = 18, min = 30, sec = 5 }))
        for i = 1, 510 do
            ns.Trace:Add("Gold", "PLAYER_MONEY", "taken", "money", i)
        end
        local saved = _G.WayscribeDB.trace
        T.eq(#saved, 500)
        T.eq(saved[1], "2026-11-04 18:30:05 Gold PLAYER_MONEY: money=11 -> taken")
        local lines = shown(ns)
        T.eq(#lines, 20)
        T.eq(lines[1], "Gold PLAYER_MONEY: money=491 -> taken")
        T.eq(lines[20], "Gold PLAYER_MONEY: money=510 -> taken")
        shown(ns, "clear")
        T.eq(_G.WayscribeDB.trace, nil)
        T.same(shown(ns), { "The launch trace is empty. It fills as the launch trackers look at the game." })
    end)

    it("speaks German", function()
        local ns = start(false, { locale = "deDE" })
        T.same(shown(ns), { "Das Launch-Protokoll zeichnet nur im Entwicklermodus auf (/ws dev)." })
        ns.Slash:Handle("dev")
        T.same(shown(ns, "clear"), { "Launch-Protokoll geleert." })
        T.same(shown(ns), { "Das Launch-Protokoll ist leer. Es füllt sich, sobald die Launch-Tracker ins Spiel schauen." })
    end)
end)
