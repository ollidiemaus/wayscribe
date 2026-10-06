local T = require("testlib")
local Stubs = require("wow_stubs")
local serialize = require("serialize")
local describe, it = T.describe, T.it

local GUID = "Player-1-0000AAAA"
local TODAY = 20261003

local function start(opts)
    local ns = Stubs.LoadAddon(opts)
    Stubs.Login()
    return ns
end

-- One sampler tick per second.
local function wait(seconds)
    for _ = 1, seconds do Stubs.Advance(1) end
end

-- Moves the player through the points, one per second (the sampler's rate).
local function walk(points, continent)
    for _, point in ipairs(points) do
        Stubs.SetPosition(continent or 1, point[1], point[2])
        Stubs.Advance(1)
    end
end

-- `steps` points after (fromX, fromY), evenly spaced up to (toX, toY).
local function line(fromX, fromY, toX, toY, steps)
    local points = {}
    for i = 1, steps do
        points[i] = { fromX + (toX - fromX) * i / steps, fromY + (toY - fromY) * i / steps }
    end
    return points
end

local function trails(ns, dayKey)
    return ns.Paths:GetDay(dayKey or TODAY)
end

local function decode(ns, segment)
    return ns.Codec.DecodePath(segment.p)
end

local function travel(ns, dayKey)
    local day = ns.Store:GetDay(dayKey or TODAY)
    return day and day.counters.travel
end

describe("recording", function()
    it("stores a walk once the player stops", function()
        local ns = start()
        Stubs.SetPosition(1, -2900, -200)
        Stubs.Advance(1)
        walk(line(-2900, -200, -2900, -10, 19)) -- 10 yards a second
        T.eq(#trails(ns), 0, "still walking: nothing stored yet")
        T.truthy(ns.Paths:GetLive())
        wait(61)
        local list = trails(ns)
        T.eq(#list, 1)
        T.eq(list[1].c, 1)
        T.eq(list[1].f, nil)
        T.eq(list[1].d, 19)
        T.same(decode(ns, list[1]), { -2900, -200, -2900, -10 }, "a straight walk keeps its two ends")
        T.same(travel(ns), { ground = 190 })
        T.eq(ns.Paths:GetLive(), nil)
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("writes nothing for standing around", function()
        local ns = start()
        walk({ { 100, 100 }, { 103, 101 }, { 101, 97 }, { 100, 100 } })
        wait(120)
        T.eq(#trails(ns), 0)
        T.eq(travel(ns), nil)
    end)

    it("keeps the shape of a curve within a few yards", function()
        local ns = start()
        local points = {}
        for i = 0, 40 do
            local angle = i / 40 * math.pi
            points[#points + 1] = { 1000 + 150 * math.cos(angle), 2000 + 150 * math.sin(angle) }
        end
        walk(points)
        wait(61)
        local stored = decode(ns, trails(ns)[1])
        T.truthy(#stored / 2 > 4 and #stored / 2 < 41, "simplified, not flattened: " .. #stored / 2)
        for i = 1, #stored - 1, 2 do
            local radius = math.sqrt((stored[i] - 1000) ^ 2 + (stored[i + 1] - 2000) ^ 2)
            T.truthy(math.abs(radius - 150) < 4, "point off the curve by " .. math.abs(radius - 150))
        end
    end)

    it("keeps a trail through a moment without a position", function()
        local ns = start()
        walk(line(0, 0, 0, 100, 10))
        Stubs.SetPosition()
        wait(10)
        walk(line(0, 100, 0, 200, 10))
        wait(61)
        T.eq(#trails(ns), 1)
        T.same(decode(ns, trails(ns)[1]), { 0, 10, 0, 200 })
    end)

    it("continues where the last trail stopped after a pause", function()
        local ns = start()
        walk(line(0, 0, 0, 100, 10))
        wait(61)
        walk(line(0, 100, 100, 100, 10))
        wait(61)
        local list = trails(ns)
        T.eq(#list, 2)
        local second = decode(ns, list[2])
        T.same({ second[1], second[2] }, { 0, 100 }, "no gap between the two")
        T.same(travel(ns), { ground = 190 })
    end)

    it("starts afresh after a teleport", function()
        local ns = start()
        walk(line(0, 0, 0, 100, 10))
        walk(line(3000, 0, 3000, 100, 10))
        wait(61)
        local list = trails(ns)
        T.eq(#list, 2)
        T.same(decode(ns, list[2]), { 3000, 10, 3000, 100 })
        T.same(travel(ns), { ground = 180 }, "the jump is not a distance traveled")
    end)

    it("flags flights and joins them to the walk before and after", function()
        local ns = start()
        walk(line(0, 0, 0, 50, 5))
        Stubs.SetTaxi(true)
        walk(line(0, 50, 0, 950, 30))
        Stubs.SetTaxi(false)
        walk(line(0, 950, 50, 950, 5))
        wait(61)
        local list = trails(ns)
        T.eq(#list, 3)
        T.eq(list[1].f, nil)
        T.eq(list[2].f, true)
        T.eq(list[3].f, nil)
        T.same(decode(ns, list[2]), { 0, 50, 0, 950 })
        T.same(travel(ns), { ground = 90, flight = 900 })
    end)

    it("leaves flights out when they shouldn't be recorded", function()
        local ns = start()
        ns.Options:Set("footstepsFlights", false)
        Stubs.SetTaxi(true)
        walk(line(0, 0, 0, 900, 30))
        Stubs.SetTaxi(false)
        wait(61)
        T.eq(#trails(ns), 0)
    end)

    it("ends a trail at death and doesn't follow the ghost", function()
        local ns = start()
        walk(line(0, 0, 0, 100, 10))
        Stubs.SetDead(true)
        walk(line(0, 100, 0, 600, 50))
        T.eq(#trails(ns), 1)
        T.eq(ns.Paths:GetLive(), nil)
    end)

    it("stops sampling inside instances", function()
        local ns = start()
        walk(line(0, 0, 0, 100, 10))
        Stubs.SetInstance(389, "party", "Ragefire Chasm")
        Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
        T.eq(#trails(ns), 1, "the loading screen ends the trail")
        T.eq(ns.Trackers:Get("HeroPath").ticker, nil)
        walk(line(0, 100, 0, 300, 20))
        T.eq(#trails(ns), 1)
        Stubs.SetInstance()
        Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
        T.truthy(ns.Trackers:Get("HeroPath").ticker)
    end)

    it("splits at midnight, so each day keeps its own trails", function()
        local ns = start({ now = os.time({ year = 2026, month = 10, day = 3, hour = 23, min = 59, sec = 50 }) })
        walk(line(0, 0, 0, 200, 20))
        wait(61)
        T.eq(#trails(ns, 20261003), 1)
        T.eq(#trails(ns, 20261004), 1)
        local first, second = decode(ns, trails(ns, 20261003)[1]), decode(ns, trails(ns, 20261004)[1])
        T.same({ second[1], second[2] }, { first[#first - 1], first[#first] }, "the new day continues the trail")
    end)

    it("stores the trail at logout and survives a reload as plain data", function()
        start()
        walk(line(0, 0, 0, 100, 10))
        local ns = Stubs.Relog(nil, true)
        T.eq(#trails(ns), 1)
        T.same(travel(ns), { ground = 90 })
        T.eq(WayscribeDB.characters[GUID].paths, 1, "the canary counts trails")
        T.same(serialize.RoundTrip(WayscribePathDB), WayscribePathDB)
    end)

    it("turning Footsteps off keeps what was recorded", function()
        local ns = start()
        walk(line(0, 0, 0, 100, 10))
        ns.Trackers:SetWanted("HeroPath", false)
        T.eq(#trails(ns), 1)
        walk(line(0, 100, 0, 300, 20))
        T.eq(#trails(ns), 1)
    end)
end)

describe("journal", function()
    it("shows the distance of the day", function()
        local ns = start()
        walk(line(0, 0, 0, 190, 19))
        wait(61)
        T.same(ns.RecordTypes:RenderCounters(ns.Store:GetDay(TODAY).counters), { "Traveled 180 yards" })
        ns.Store:Count("travel", "ground", 4000)
        ns.Store:Count("travel", "flight", 2640)
        T.same(ns.RecordTypes:RenderCounters(ns.Store:GetDay(TODAY).counters),
            { "Traveled 2.4 miles · Flight paths: 1.5 miles" })
    end)

    it("uses metres and kilometres in German", function()
        local ns = start({ locale = "deDE" })
        ns.Store:Count("travel", "ground", 190)
        T.same(ns.RecordTypes:RenderCounters(ns.Store:GetDay(TODAY).counters), { "Zurückgelegt: 174 m" })
        ns.Store:Count("travel", "ground", 1200)
        T.same(ns.RecordTypes:RenderCounters(ns.Store:GetDay(TODAY).counters), { "Zurückgelegt: 1,3 km" })
    end)

    it("reports trails in /ws stats", function()
        local ns = start()
        walk(line(0, 0, 0, 100, 10))
        wait(61)
        ns.Slash:Handle("stats")
        local printed = Stubs.Printed()
        T.truthy(printed[#printed]:find("Footsteps: 1 trails on 1 days, 0.0 KB packed"), printed[#printed])
    end)
end)

-- A deterministic pseudo-random sequence (Park-Miller), the same on every Lua version.
local function random(seed)
    local value = seed
    return function()
        value = (value * 16807) % 2147483647
        return value / 2147483647
    end
end

-- Two hours of questing: rides between quest hubs, running around while questing with stops for
-- fights, and standing in town. Headings wander like a player steering, never quite straight.
local function playTwoHours()
    local rnd = random(20261006)
    local x, y, heading = -2900, -200, 0
    local seconds = 0
    while seconds < 7200 do
        local roll = rnd()
        local kind = roll < 0.35 and "ride" or (roll < 0.8 and "quest" or "town")
        local length = math.floor(60 + rnd() * (kind == "quest" and 340 or 180))
        local speed = kind == "ride" and 14 or 7
        local turn = kind == "ride" and 0.25 or 1.0
        for _ = 1, length do
            if kind == "town" or (kind == "quest" and rnd() < 0.3) then
                -- standing: in town, or fighting
                if kind == "quest" then heading = heading + (rnd() - 0.5) * 3 end
            else
                heading = heading + (rnd() - 0.5) * turn
                x, y = x + math.cos(heading) * speed, y + math.sin(heading) * speed
            end
            Stubs.SetPosition(1, x, y)
            Stubs.Advance(1)
            seconds = seconds + 1
        end
    end
    Stubs.Fire("PLAYER_LOGOUT")
end

describe("size budget (release exit criterion)", function()
    it("keeps two hours of play under 10 KB of packed trails", function()
        local ns = start()
        playTwoHours()
        local stats = ns.Paths:GetStats()
        -- About 3.2 KB in 10 trails when this was written (2026-10-06).
        T.truthy(stats.segments > 5, "the session is split into several trails: " .. stats.segments)
        T.truthy(stats.bytes < 10 * 1024, "packed " .. stats.bytes .. " bytes")
        local saved = #serialize.Serialize(WayscribePathDB)
        T.truthy(saved < 12 * 1024, "saved " .. saved .. " bytes")
    end)
end)

describe("guards", function()
    local function account(paths)
        return { schema = 1, settings = { trackers = {} }, log = {},
            characters = { [GUID] = { name = "Tester", realm = "Forever", seq = 0, paths = paths } } }
    end

    local function journal()
        return { schema = 1, meta = { seq = 0, guid = GUID, name = "Tester", realm = "Forever" },
            state = {}, players = {}, months = {}, firsts = {} }
    end

    it("keeps trails read-only when they didn't load but had been saved, the journal works", function()
        local ns = start({ accountDB = account(5), charDB = journal() })
        T.eq(ns.Schema.pathSafeKind, "missing")
        T.falsy(ns.Paths:IsWritable())
        T.truthy(ns.Store:IsWritable(), "the journal is not affected")
        T.eq(ns.safeMode, nil)
        local printed = Stubs.Printed()
        T.truthy(printed[#printed]:find("Footsteps are read%-only: this character's trails did not load, although 5"))
        walk(line(0, 0, 0, 100, 10))
        Stubs.Fire("PLAYER_LOGOUT")
        T.eq(WayscribePathDB, nil, "nothing is written over the file")
        T.eq(WayscribeDB.characters[GUID].paths, 5)

        T.truthy(ns.Schema:Accept())
        ns = Stubs.Relog()
        T.truthy(ns.Paths:IsWritable(), "/ws accept starts new trails")
    end)

    it("leaves trails from a newer version untouched", function()
        local saved = { schema = 9, seq = 3, months = { future = true } }
        local before = Stubs.Copy(saved)
        local ns = start({ pathDB = saved })
        T.eq(ns.Schema.pathSafeKind, "newer")
        T.falsy(ns.Paths:IsWritable())
        T.truthy(ns.Store:IsWritable())
        walk(line(0, 0, 0, 100, 10))
        Stubs.Fire("PLAYER_LOGOUT")
        T.eq(WayscribePathDB, saved)
        T.same(WayscribePathDB, before)
    end)

    it("starts trails for a character that never had any", function()
        local ns = start({ accountDB = account(nil), charDB = journal() })
        T.eq(ns.Schema.pathSafeKind, nil)
        T.truthy(ns.Paths:IsWritable())
        T.same(WayscribePathDB, { schema = 1, seq = 0, months = {} })
    end)

    it("records nothing while the journal is read-only", function()
        local ns = start({ accountDB = account(nil), charDB = journal() })
        ns.SetSafeMode("test")
        walk(line(0, 0, 0, 100, 10))
        wait(61)
        T.eq(ns.Paths:GetStats().segments, 0)
    end)

    it("deletes trails and keeps the journal", function()
        local ns = start()
        walk(line(0, 0, 0, 100, 10))
        wait(61)
        T.truthy(ns.Paths:Wipe())
        T.eq(ns.Paths:GetStats().segments, 0)
        T.same(travel(ns), { ground = 90 }, "the day's distance stays in the journal")
    end)

    it("resetting the journal resets the trails too", function()
        local ns = start()
        walk(line(0, 0, 0, 100, 10))
        wait(61)
        T.truthy(ns.Schema:ResetCharacter())
        T.eq(ns.Paths:GetStats().segments, 0)
        T.eq(ns.Store:GetStats().records, 0)
    end)
end)
