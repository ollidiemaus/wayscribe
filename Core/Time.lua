local _, ns = ...

-- Day keys are integers YYYYMMDD and month keys YYYYMM, both in local time. Days roll over at
-- calendar midnight (docs/ARCHITECTURE.md §3.5), so a key never depends on a setting.
local Time = {}
ns.Time = Time

function Time.Now()
    return time()
end

function Time.DayKey(ts)
    local t = date("*t", ts)
    return t.year * 10000 + t.month * 100 + t.day
end

function Time.MonthKey(ts)
    local t = date("*t", ts)
    return t.year * 100 + t.month
end

function Time.MonthOfDay(dayKey)
    return math.floor(dayKey / 100)
end

function Time.YearOfMonth(monthKey)
    return math.floor(monthKey / 100)
end

function Time.SplitDay(dayKey)
    return math.floor(dayKey / 10000), math.floor(dayKey / 100) % 100, dayKey % 100
end

-- pattern uses DD, MM and YYYY, e.g. "DD.MM.YYYY". Defaults to the player's setting, then the locale.
function Time.FormatDay(dayKey, pattern)
    if not pattern then
        pattern = ns.Options:Get("dateFormat")
        if type(pattern) ~= "string" or pattern == "" then
            pattern = ns.L.DATE_FORMAT
        end
    end
    local year, month, day = Time.SplitDay(dayKey)
    return (pattern
        :gsub("YYYY", string.format("%04d", year))
        :gsub("MM", string.format("%02d", month))
        :gsub("DD", string.format("%02d", day)))
end

-- Local midnight and the last second of a day (a DST day is 23 or 25 hours long).
function Time.DayStart(dayKey)
    local year, month, day = Time.SplitDay(dayKey)
    return time({ year = year, month = month, day = day, hour = 0, min = 0, sec = 0 })
end

function Time.DayEnd(dayKey)
    local year, month, day = Time.SplitDay(dayKey)
    return time({ year = year, month = month, day = day, hour = 23, min = 59, sec = 59 })
end

-- The day `days` days later (or earlier, when negative). Noon keeps DST shifts out of the way.
function Time.ShiftDay(dayKey, days)
    local year, month, day = Time.SplitDay(dayKey)
    return Time.DayKey(time({ year = year, month = month, day = day + days, hour = 12, min = 0, sec = 0 }))
end

-- 1 = Sunday ... 7 = Saturday, like date("*t").wday. Sakamoto's method: arithmetic only.
local MONTH_OFFSETS = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
function Time.Weekday(dayKey)
    local year, month, day = Time.SplitDay(dayKey)
    if month < 3 then year = year - 1 end
    local floor = math.floor
    return (year + floor(year / 4) - floor(year / 100) + floor(year / 400) + MONTH_OFFSETS[month] + day) % 7 + 1
end

-- Long date patterns use {weekday}, {day}, {month} and {year}, so word order is the locale's choice.
local function fill(pattern, values)
    return (pattern:gsub("{(%a+)}", values))
end

local function dayValues(dayKey)
    local L = ns.L
    local year, month, day = Time.SplitDay(dayKey)
    return { weekday = L.WEEKDAYS[Time.Weekday(dayKey)], day = tostring(day), month = L.MONTHS[month], year = tostring(year) }
end

-- "Saturday, October 3, 2026" / "Samstag, 3. Oktober 2026"
function Time.FormatLongDay(dayKey)
    return fill(ns.L.DATE_LONG, dayValues(dayKey))
end

-- A day inside its month's group: "Saturday 3" / "Samstag, 3."
function Time.FormatListDay(dayKey)
    return fill(ns.L.DATE_LIST, dayValues(dayKey))
end

-- "October 2026" / "Oktober 2026"
function Time.FormatMonth(monthKey)
    local month = monthKey % 100
    return fill(ns.L.DATE_MONTH, { month = ns.L.MONTHS[month], year = tostring(Time.YearOfMonth(monthKey)) })
end

-- "Today", "Yesterday" or nil.
function Time.RelativeDay(dayKey)
    local today = Time.DayKey(Time.Now())
    if dayKey == today then return ns.L.TODAY end
    if dayKey == Time.DayKey(Time.DayStart(today) - 1) then return ns.L.YESTERDAY end
    return nil
end

-- "14:05" or "2:05 PM". use24Hour nil means the language's habit.
function Time.FormatClock(ts, use24Hour)
    local L = ns.L
    if use24Hour == nil then use24Hour = L.CLOCK_24H end
    local t = date("*t", ts)
    if use24Hour then
        return string.format("%02d:%02d", t.hour, t.min)
    end
    local hour = t.hour % 12
    return string.format("%d:%02d %s", hour == 0 and 12 or hour, t.min, t.hour < 12 and L.CLOCK_AM or L.CLOCK_PM)
end

function Time.FormatDuration(seconds)
    local minutes = math.floor(seconds / 60)
    if minutes < 1 then
        return ns.L.DURATION_UNDER_MINUTE
    elseif minutes < 60 then
        return ns.L.DURATION_MINUTES:format(minutes)
    end
    return ns.L.DURATION_HOURS:format(math.floor(minutes / 60), minutes % 60)
end
