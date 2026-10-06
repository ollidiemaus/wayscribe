local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local DAY = 24 * 3600

describe("rebuild", function()
    it("reproduces exactly what the incremental updates built", function()
        local ns = Stubs.LoadAddon()
        Stubs.Login()
        ns.RecordTypes:Register("TEST_BOSS", {
            version = 1,
            fields = { encounterID = "number" },
            firstKey = function(data) return "BOSS:" .. data.encounterID end,
            rollup = function(rollup) rollup.bosses = (rollup.bosses or 0) + 1 end,
        })
        local Store = ns.Store
        for i = 1, 40 do
            Store:Append("TEST_BOSS", { encounterID = i % 7 })
            Store:Count("gather", i % 3, i)
            if i % 5 == 0 then Store:Append("LEVEL_UP", { level = 10 + i / 5 }) end
            Stubs.Advance(DAY / 3)
        end
        local incremental = Stubs.Copy(ns.charDB)

        -- Wreck every derived value, then rebuild from the facts.
        ns.charDB.firsts = { ["BOSS:1"] = 999 }
        for _, month in pairs(ns.charDB.months) do
            month.rollup = { records = { TEST_BOSS = -1 }, counters = {} }
            for _, day in pairs(month.days) do
                for _, record in ipairs(day.records) do record.first = not record.first end
                for i = #day.records, 2, -1 do
                    day.records[i], day.records[i - 1] = day.records[i - 1], day.records[i]
                end
            end
        end

        T.eq(Store:Rebuild(), 48)
        T.same(ns.charDB, incremental)
    end)

    it("rebuilds the day list from the saved months", function()
        local ns = Stubs.LoadAddon()
        Stubs.Login()
        ns.Store:Append("LEVEL_UP", { level = 11 })
        Stubs.Advance(2 * DAY)
        ns.Store:Append("LEVEL_UP", { level = 12 })
        ns.Index:Build(ns.charDB)
        T.same(ns.Store:GetDayKeys(), { 20261005, 20261003 })
    end)

    it("keeps records whose type no longer exists", function()
        local ns = Stubs.LoadAddon()
        Stubs.Login()
        local day = ns.Store:GetOrCreateDay(Stubs.Now())
        day.records[1] = { id = 1, ts = Stubs.Now(), type = "REMOVED_FEATURE", v = 1, data = { x = 1 } }
        ns.charDB.meta.seq = 1
        T.eq(ns.Store:Rebuild(), 1)
        T.eq(day.records[1].type, "REMOVED_FEATURE")
    end)
end)
