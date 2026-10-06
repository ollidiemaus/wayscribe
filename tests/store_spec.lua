local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local DAY = 24 * 3600

local function fresh()
    local ns = Stubs.LoadAddon()
    Stubs.Login()
    ns.RecordTypes:Register("TEST_DUNGEON", {
        version = 1,
        fields = { instanceID = "number" },
        firstKey = function(data) return "DUNGEON:" .. data.instanceID end,
        rollup = function(rollup, data)
            rollup.dungeons = rollup.dungeons or {}
            rollup.dungeons[data.instanceID] = (rollup.dungeons[data.instanceID] or 0) + 1
        end,
        render = function(data) return "dungeon " .. data.instanceID end,
    })
    return ns, ns.Store
end

describe("append", function()
    it("partitions records by month and day", function()
        local ns, Store = fresh()
        local record = Store:Append("TEST_DUNGEON", { instanceID = 389 })
        T.eq(record.id, 1)
        T.eq(record.v, 1)
        local month = ns.charDB.months[202610]
        T.eq(month.days[20261003].records[1], record)
        T.same(Store:GetDayKeys(), { 20261003 })
    end)

    it("issues increasing ids and keeps newest days first", function()
        local _, Store = fresh()
        Store:Append("TEST_DUNGEON", { instanceID = 1 })
        Stubs.Advance(DAY)
        Store:Append("TEST_DUNGEON", { instanceID = 2 })
        Stubs.Advance(30 * DAY)
        local last = Store:Append("TEST_DUNGEON", { instanceID = 3 })
        T.eq(last.id, 3)
        T.same(Store:GetDayKeys(), { 20261103, 20261004, 20261003 })
    end)

    it("marks the first occurrence and keeps it in firsts", function()
        local _, Store = fresh()
        local first = Store:Append("TEST_DUNGEON", { instanceID = 389 })
        local second = Store:Append("TEST_DUNGEON", { instanceID = 389 })
        T.truthy(first.first)
        T.falsy(second.first)
        T.eq(Store:GetFirst("DUNGEON:389"), first.id)
    end)

    it("updates the month rollup in the same call", function()
        local ns, Store = fresh()
        Store:Append("TEST_DUNGEON", { instanceID = 389 })
        Store:Append("TEST_DUNGEON", { instanceID = 389 })
        local rollup = ns.charDB.months[202610].rollup
        T.eq(rollup.records.TEST_DUNGEON, 2)
        T.eq(rollup.dungeons[389], 2)
    end)

    it("rejects invalid data and unknown types without writing", function()
        local ns, Store = fresh()
        T.eq(Store:Append("TEST_DUNGEON", { instanceID = "389" }), nil)
        T.eq(Store:Append("NOPE", {}), nil)
        T.eq(ns.charDB.meta.seq, 0)
        T.eq(#Store:GetDayKeys(), 0)
    end)

    it("skips a dedupe key seen this session", function()
        local _, Store = fresh()
        T.truthy(Store:Append("TEST_DUNGEON", { instanceID = 1 }, { dedupeKey = "boss:1" }))
        local record, reason = Store:Append("TEST_DUNGEON", { instanceID = 1 }, { dedupeKey = "boss:1" })
        T.eq(record, nil)
        T.eq(reason, "duplicate")
    end)

    it("tells listeners about new records", function()
        local ns, Store = fresh()
        local seen
        ns.Bus:On("RECORD_ADDED", "test", function(_, record) seen = record end)
        local record = Store:Append("TEST_DUNGEON", { instanceID = 1 })
        T.eq(seen, record)
    end)

    it("writes nothing in safe mode", function()
        local ns, Store = fresh()
        ns.safeMode = "test"
        T.eq(Store:Append("TEST_DUNGEON", { instanceID = 1 }), nil)
        T.falsy(Store:Count("gather", 2770, 1))
        T.falsy(Store:SetState("x", 1))
        T.eq(Store:StartSession(Stubs.Now()), nil)
        T.eq(ns.charDB.meta.seq, 0)
    end)
end)

describe("counters", function()
    it("adds per day and per month", function()
        local ns, Store = fresh()
        Store:Count("gather", 2770, 3)
        Store:Count("gather", 2770, 2)
        Store:Count("gather", 2835)
        local day = Store:GetDay(20261003)
        T.eq(day.counters.gather[2770], 5)
        T.eq(day.counters.gather[2835], 1)
        T.eq(ns.charDB.months[202610].rollup.counters.gather[2770], 5)
    end)

    it("rejects secret keys and amounts", function()
        local _, Store = fresh()
        T.falsy(Store:Count("gather", Stubs.SECRET, 1))
        T.falsy(Store:Count("gather", 2770, Stubs.SECRET))
        T.eq(Store:GetDay(20261003), nil)
    end)
end)

describe("reads", function()
    it("returns a day's records in time order even if appended out of order", function()
        local _, Store = fresh()
        local now = Stubs.Now()
        local late = Store:Append("TEST_DUNGEON", { instanceID = 1 }, { ts = now + 60 })
        local early = Store:Append("TEST_DUNGEON", { instanceID = 2 }, { ts = now })
        local records = Store:GetDayRecords(20261003)
        T.eq(records[1], early)
        T.eq(records[2], late)
    end)

    it("summarizes a year from month rollups and sessions", function()
        local _, Store = fresh() -- login started a session at 12:00
        Store:Append("LEVEL_UP", { level = 11 })
        Stubs.Advance(3600)
        Store:EndSession(Stubs.Now())
        Stubs.Advance(40 * DAY)
        Store:StartSession(Stubs.Now())
        Store:Append("LEVEL_UP", { level = 12 })
        Store:Count("gather", 2770, 4)
        Stubs.Advance(1800)
        Store:EndSession(Stubs.Now())

        local year = Store:GetYearSummary(2026)
        T.eq(year.months, 2)
        T.eq(year.sessions, 2)
        T.eq(year.playSeconds, 3600 + 1800)
        T.eq(year.activeDays, 2)
        T.eq(year.rollup.records.LEVEL_UP, 2)
        T.eq(year.rollup.maxLevel, 12)
        T.eq(year.rollup.counters.gather[2770], 4)
    end)

    it("reports stats", function()
        local _, Store = fresh()
        Store:Append("TEST_DUNGEON", { instanceID = 1 })
        Store:Append("TEST_DUNGEON", { instanceID = 2 }, { simulated = true })
        local stats = Store:GetStats()
        T.eq(stats.records, 2)
        T.eq(stats.days, 1)
        T.eq(stats.simulated, 1)
        T.eq(stats.seq, 2)
    end)
end)

describe("simulated data", function()
    it("can be removed again, including what it changed in firsts and rollups", function()
        local ns, Store = fresh()
        Store:Append("TEST_DUNGEON", { instanceID = 389 }, { simulated = true })
        local real = Store:Append("TEST_DUNGEON", { instanceID = 389 })
        Stubs.Advance(DAY)
        Store:Append("TEST_DUNGEON", { instanceID = 43 }, { simulated = true })
        T.falsy(real.first)

        T.eq(Store:RemoveSimulated(), 2)
        T.truthy(real.first, "the real record is the first one now")
        T.eq(Store:GetFirst("DUNGEON:389"), real.id)
        T.eq(Store:GetFirst("DUNGEON:43"), nil)
        T.same(Store:GetDayKeys(), { 20261003 })
        T.eq(ns.charDB.months[202610].rollup.records.TEST_DUNGEON, 1)
    end)
end)
