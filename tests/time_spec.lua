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

describe("calendar", function()
    it("knows the weekday without asking the clock", function()
        T.eq(Time.Weekday(20261003), 7, "a Saturday")
        T.eq(Time.Weekday(20261004), 1, "a Sunday")
        T.eq(Time.Weekday(20270101), 6, "a Friday")
        T.eq(Time.Weekday(20280229), 3, "a leap day, Tuesday")
        for dayKey = 20261001, 20261031 do
            local t = os.date("*t", Time.DayStart(dayKey) + 12 * 3600)
            T.eq(Time.Weekday(dayKey), t.wday, tostring(dayKey))
        end
    end)

    it("finds the first and last second of a day", function()
        T.eq(Time.DayStart(20261003), at(2026, 10, 3, 0))
        T.eq(Time.DayEnd(20261003), at(2026, 10, 4, 0) - 1)
        T.eq(Time.DayKey(Time.DayEnd(20261231) + 1), 20270101)
    end)
end)

describe("long dates", function()
    it("are spelled out in English", function()
        T.eq(Time.FormatLongDay(20261003), "Saturday, October 3, 2026")
        T.eq(Time.FormatListDay(20261003), "Saturday 3")
        T.eq(Time.FormatMonth(202610), "October 2026")
        T.eq(Time.FormatMonth(202701), "January 2027")
    end)

    it("are spelled out in German", function()
        local german = Stubs.LoadAddon({ locale = "deDE" })
        T.eq(german.Time.FormatLongDay(20261003), "Samstag, 3. Oktober 2026")
        T.eq(german.Time.FormatListDay(20260301), "Sonntag, 1.")
        T.eq(german.Time.FormatMonth(202603), "März 2026")
    end)

    it("name today and yesterday", function()
        Stubs.SetTime(at(2026, 10, 3, 0, 30))
        T.eq(Time.RelativeDay(20261003), "Today")
        T.eq(Time.RelativeDay(20261002), "Yesterday")
        T.eq(Time.RelativeDay(20261001), nil)
        Stubs.SetTime(at(2027, 1, 1, 9))
        T.eq(Time.RelativeDay(20261231), "Yesterday")
    end)
end)

describe("clock", function()
    it("uses the language's habit unless told otherwise", function()
        local ts = at(2026, 10, 3, 14, 5)
        T.eq(Time.FormatClock(ts), "2:05 PM")
        T.eq(Time.FormatClock(at(2026, 10, 3, 0, 7)), "12:07 AM")
        T.eq(Time.FormatClock(at(2026, 10, 3, 12, 0)), "12:00 PM")
        T.eq(Time.FormatClock(ts, true), "14:05")
        local german = Stubs.LoadAddon({ locale = "deDE" })
        T.eq(german.Time.FormatClock(ts), "14:05")
        T.eq(german.Time.FormatClock(ts, false), "2:05 PM")
    end)
end)
