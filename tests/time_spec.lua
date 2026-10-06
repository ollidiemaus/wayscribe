local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local ns = Stubs.LoadAddon()
local Time = ns.Time

local function at(year, month, day, hour, minute)
    return os.time({ year = year, month = month, day = day, hour = hour, min = minute or 0 })
end

describe("keys", function()
    it("builds integer day and month keys in local time", function()
        T.eq(Time.DayKey(at(2026, 10, 3, 12)), 20261003)
        T.eq(Time.MonthKey(at(2026, 10, 3, 12)), 202610)
    end)

    it("rolls over at calendar midnight", function()
        T.eq(Time.DayKey(at(2026, 10, 3, 23, 59)), 20261003)
        T.eq(Time.DayKey(at(2026, 10, 4, 0, 1)), 20261004)
        T.eq(Time.DayKey(at(2026, 12, 31, 23, 59)), 20261231)
        T.eq(Time.MonthKey(at(2027, 1, 1, 0, 1)), 202701)
    end)

    it("splits keys back into parts", function()
        T.eq(Time.MonthOfDay(20261003), 202610)
        T.eq(Time.YearOfMonth(202610), 2026)
        local year, month, day = Time.SplitDay(20261003)
        T.eq(year, 2026)
        T.eq(month, 10)
        T.eq(day, 3)
    end)
end)

describe("formatting", function()
    it("uses the German pattern from the user's example", function()
        T.eq(Time.FormatDay(20261003, "DD.MM.YYYY"), "03.10.2026")
    end)

    it("falls back to the locale default", function()
        T.eq(Time.FormatDay(20261003), "2026-10-03")
    end)

    it("prefers the player's setting", function()
        ns.accountDB = { settings = { dateFormat = "MM/DD/YYYY" } }
        T.eq(Time.FormatDay(20261003), "10/03/2026")
        ns.accountDB = nil
    end)

    it("uses DD.MM.YYYY on a German client", function()
        local german = Stubs.LoadAddon({ locale = "deDE" })
        T.eq(german.Time.FormatDay(20261002), "02.10.2026")
    end)
end)
