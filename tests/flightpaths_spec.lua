local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local KALIMDOR, EASTERN = 1464, 1465 -- the flight maps' taxi map IDs
local TB, CROSSROADS, RATCHET, ORGRIMMAR, UNDERCITY, TARREN = 22, 25, 80, 23, 11, 68
local CURRENT, REACHABLE, UNREACHABLE = 0, 1, 2

local NAMES = {
    [TB] = "Thunder Bluff, Mulgore", [CROSSROADS] = "Crossroads, The Barrens", [RATCHET] = "Ratchet, The Barrens",
    [ORGRIMMAR] = "Orgrimmar, Durotar", [UNDERCITY] = "Undercity, Tirisfal", [TARREN] = "Tarren Mill, Hillsbrad",
}

-- The nodes of a flight map: `states` = { [nodeID] = state }.
local function nodes(states)
    local list = {}
    for id, state in pairs(states) do list[#list + 1] = { id = id, name = NAMES[id], state = state } end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- Logs in (level 10 unless opts.level) and lets the login settle.
local function start(opts)
    local ns = Stubs.LoadAddon(opts)
    Stubs.SetBestMap(1412) -- Mulgore, in Kalimdor
    Stubs.Login()
    Stubs.Advance(1)
    return ns
end

-- Opens the flight map (or the old taxi frame with opts.frame) on `states`, then closes it.
local function visit(states, opts)
    opts = opts or {}
    Stubs.OpenTaxiMap(nodes(states), opts.map or KALIMDOR, opts.frame)
    Stubs.Advance(1)
    Stubs.CloseTaxiMap()
end

local function entries(ns)
    local texts = {}
    for _, record in ipairs(ns.Store:GetRecordsOfType("FLIGHT_PATH")) do
        texts[#texts + 1] = (record.first and "*" or "") .. ns.RecordTypes:Render(record)
    end
    return texts
end

local function contains(list, wanted)
    for _, item in ipairs(list) do
        if item == wanted then return end
    end
    error(("%q not in { %s }"):format(wanted, table.concat(list, " | ")), 2)
end

local function footsteps(ns)
    for _, built in ipairs(ns.YearCards:Build(2026)) do
        if built.id == "footsteps" then return built end
    end
end

-- An older character's Kalimdor: three nodes known, standing at Thunder Bluff.
local OLDER = { [TB] = CURRENT, [CROSSROADS] = REACHABLE, [ORGRIMMAR] = REACHABLE, [RATCHET] = UNREACHABLE }

describe("flight paths", function()
    it("record a fresh character's first flight path, the only node it knows", function()
        local ns = start({ level = 4 })
        visit({ [TB] = CURRENT, [CROSSROADS] = UNREACHABLE, [ORGRIMMAR] = UNREACHABLE })
        T.same(entries(ns), { "*New flight path: Thunder Bluff, Mulgore" })
        T.eq(ns.RecordTypes:Get("FLIGHT_PATH").category, "travel")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("take an older character's first map on a continent silently, and record the next one learned", function()
        local ns = start()
        visit(OLDER)
        T.same(entries(ns), {}, "known before Wayscribe")
        visit({ [TB] = REACHABLE, [CROSSROADS] = REACHABLE, [ORGRIMMAR] = REACHABLE, [RATCHET] = CURRENT })
        T.same(entries(ns), { "*New flight path: Ratchet, The Barrens" })
        visit({ [TB] = REACHABLE, [CROSSROADS] = CURRENT, [ORGRIMMAR] = REACHABLE, [RATCHET] = REACHABLE })
        T.same(entries(ns), { "*New flight path: Ratchet, The Barrens" }, "nothing new")
    end)

    it("record a flight path learned without a look at the next flight master", function()
        local ns = start()
        visit(OLDER)
        -- Ratchet learned while Wayscribe was off; seen next at the Crossroads.
        visit({ [TB] = REACHABLE, [CROSSROADS] = CURRENT, [ORGRIMMAR] = REACHABLE, [RATCHET] = REACHABLE })
        T.same(entries(ns), { "*New flight path: Ratchet, The Barrens" })
    end)

    it("take the first map on each continent silently", function()
        local ns = start()
        visit(OLDER)
        visit({ [UNDERCITY] = CURRENT, [TARREN] = REACHABLE }, { map = EASTERN })
        T.same(entries(ns), {})
        visit({ [UNDERCITY] = REACHABLE, [TARREN] = CURRENT }, { map = EASTERN })
        T.same(entries(ns), {})
        local fresh = start({ level = 12 })
        visit(OLDER)
        visit({ [UNDERCITY] = CURRENT }, { map = EASTERN })
        T.same(entries(fresh), { "*New flight path: Undercity, Tirisfal" }, "the only node known: just learned")
    end)

    it("read the old taxi frame when it opens instead", function()
        local ns = start()
        visit(OLDER, { frame = true })
        visit({ [TB] = REACHABLE, [CROSSROADS] = REACHABLE, [ORGRIMMAR] = REACHABLE, [RATCHET] = CURRENT },
            { frame = true })
        T.same(entries(ns), { "*New flight path: Ratchet, The Barrens" })
    end)

    it("look again on the chat line, which never makes an entry on its own", function()
        local ns = start({ level = 4 })
        Stubs.Fire("CHAT_MSG_SYSTEM", ERR_NEWTAXIPATH)
        Stubs.Advance(1)
        T.same(entries(ns), {}, "no taxi map open")
        Stubs.OpenTaxiMap(nodes(OLDER), KALIMDOR)
        Stubs.Advance(1)
        Stubs.state.taxiNodes[#Stubs.state.taxiNodes].state = REACHABLE -- Ratchet, learned with the map open
        Stubs.Fire("CHAT_MSG_SYSTEM", ERR_NEWTAXIPATH)
        Stubs.Fire("CHAT_MSG_SYSTEM", "You feel rested.")
        Stubs.Advance(1)
        T.same(entries(ns), { "*New flight path: Ratchet, The Barrens" })
    end)

    it("keep the node's name from when the entry was written", function()
        local ns = start({ level = 4 })
        visit({ [TB] = CURRENT })
        NAMES[TB] = "Something else"
        visit({ [TB] = CURRENT, [CROSSROADS] = REACHABLE })
        NAMES[TB] = "Thunder Bluff, Mulgore"
        T.same(entries(ns), { "*New flight path: Thunder Bluff, Mulgore", "*New flight path: Crossroads, The Barrens" })
    end)

    it("give the Footsteps card a line with how many were learned", function()
        local ns = start({ level = 4 })
        ns.Store:Count("travel", "ground", 5000)
        visit({ [TB] = CURRENT })
        contains(footsteps(ns).lines, "1 flight path learned")
        visit({ [TB] = CURRENT, [CROSSROADS] = REACHABLE })
        contains(footsteps(ns).lines, "2 flight paths learned")
        ns.Store:Rebuild()
        contains(footsteps(ns).lines, "2 flight paths learned")
    end)

    it("read in German", function()
        local ns = start({ level = 4, locale = "deDE" })
        ns.Store:Count("travel", "ground", 5000)
        visit({ [TB] = CURRENT })
        visit({ [TB] = CURRENT, [CROSSROADS] = REACHABLE })
        T.same(entries(ns), { "*Neue Flugroute: Thunder Bluff, Mulgore", "*Neue Flugroute: Crossroads, The Barrens" })
        contains(footsteps(ns).lines, "2 Flugrouten entdeckt")
    end)

    it("write nothing and log no error when the APIs are missing, error or are secret", function()
        local ns = start({ level = 4 })
        Stubs.Fire("TAXIMAP_OPENED")
        Stubs.Advance(1)
        Stubs.OpenTaxiMap(nodes({ [TB] = CURRENT }), KALIMDOR)
        _G.GetTaxiMapID = function() error("no map") end
        _G.NumTaxiNodes = function() return Stubs.SECRET end
        Stubs.Fire("TAXIMAP_OPENED")
        Stubs.Advance(1)
        Stubs.OpenTaxiMap(nodes({ [TB] = CURRENT }), KALIMDOR)
        _G.C_TaxiMap.GetAllTaxiNodes = function() return Stubs.SECRET end
        _G.TaxiNodeGetType = function() error("no type") end
        Stubs.Fire("TAXIMAP_OPENED")
        Stubs.Advance(1)
        Stubs.OpenTaxiMap(nodes({ [TB] = CURRENT, [CROSSROADS] = REACHABLE }), KALIMDOR)
        _G.C_TaxiMap.GetAllTaxiNodes = function() return { { nodeID = Stubs.SECRET, name = "x", state = 0 } } end
        Stubs.Fire("TAXIMAP_OPENED")
        Stubs.Advance(1)
        T.same(entries(ns), {})
        T.eq(#ns.Log:GetEntries(), 0)
        visit({ [TB] = CURRENT })
        T.same(entries(ns), { "*New flight path: Thunder Bluff, Mulgore" }, "the first readable map is the first look")
    end)

    it("stop listening when switched off", function()
        local ns = start()
        visit(OLDER)
        ns.Trackers:SetWanted("FlightPaths", false)
        visit({ [TB] = REACHABLE, [CROSSROADS] = REACHABLE, [ORGRIMMAR] = REACHABLE, [RATCHET] = CURRENT })
        T.same(entries(ns), {})
        ns.Trackers:SetWanted("FlightPaths", true)
        visit({ [TB] = REACHABLE, [CROSSROADS] = CURRENT, [ORGRIMMAR] = REACHABLE, [RATCHET] = REACHABLE })
        T.same(entries(ns), { "*New flight path: Ratchet, The Barrens" }, "found at the next flight master")
    end)

    it("repeat nothing after a relog, or when the journal comes back without the tracker's state", function()
        start({ level = 4 })
        visit({ [TB] = CURRENT })
        local ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        visit({ [TB] = CURRENT, [CROSSROADS] = REACHABLE })
        ns.Store:SetState("flightPaths", nil)
        ns = Stubs.Relog()
        Stubs.Advance(1)
        visit({ [TB] = CURRENT })
        visit({ [TB] = CURRENT, [CROSSROADS] = REACHABLE })
        T.same(entries(ns), { "*New flight path: Thunder Bluff, Mulgore", "*New flight path: Crossroads, The Barrens" })
    end)

    it("repeat nothing after a backup is restored", function()
        local ns = start({ level = 4 })
        visit({ [TB] = CURRENT })
        local text
        ns.Backup:Make({}, function(result) text = result end)
        T.truthy(ns.Schema:ResetCharacter())
        ns = Stubs.Relog(nil, true)
        local found
        ns.Backup:Read(text, function(result) found = result end)
        T.truthy(ns.Backup:Restore(found))
        ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        visit({ [TB] = CURRENT })
        T.same(entries(ns), { "*New flight path: Thunder Bluff, Mulgore" })
    end)

    it("trace each look in developer mode", function()
        local accountDB = { schema = 1, log = {}, characters = {}, settings = { trackers = { FirstVisits = false, Guild = false,
            Gold = false, Reputation = false, Gear = false, LegacyChallenges = false, Home = false,
            Collections = false }, devMode = true } }
        local ns = start({ accountDB = accountDB })
        visit(OLDER)
        Stubs.OpenTaxiMap(nodes({ [TB] = REACHABLE, [CROSSROADS] = REACHABLE, [ORGRIMMAR] = REACHABLE,
            [RATCHET] = CURRENT }), KALIMDOR)
        Stubs.Fire("CHAT_MSG_SYSTEM", ERR_NEWTAXIPATH)
        Stubs.Advance(1)
        Stubs.CloseTaxiMap()
        visit({ [TB] = REACHABLE, [RATCHET] = CURRENT }, { frame = true })
        Stubs.Fire("CHAT_MSG_SYSTEM", ERR_NEWTAXIPATH)
        Stubs.Advance(1)
        local traced = {}
        for i, line in ipairs(ns.Trace:GetLines()) do traced[i] = line:gsub("^%S+ %S+ ", "") end
        T.same(traced, {
            'FlightPaths TAXIMAP_OPENED: source="map" map=1464 nodes=4 known=3 current=22 -> first look',
            'FlightPaths TAXIMAP_OPENED+CHAT_MSG_SYSTEM: source="map" map=1464 nodes=4 known=4 current=80'
                .. ' new="80" -> recorded 1',
            'FlightPaths TAXIMAP_OPENED: source="frame" map=1414 nodes=2 known=2 current="Ratchet, The Barrens"'
                .. ' -> first look',
            "FlightPaths CHAT_MSG_SYSTEM: source=missing -> no taxi map",
        })
    end)
end)
