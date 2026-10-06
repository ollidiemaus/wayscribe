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
        local settings = ns.accountDB and ns.accountDB.settings
        pattern = (settings and settings.dateFormat) or ns.L.DATE_FORMAT
    end
    local year, month, day = Time.SplitDay(dayKey)
    return (pattern
        :gsub("YYYY", string.format("%04d", year))
        :gsub("MM", string.format("%02d", month))
        :gsub("DD", string.format("%02d", day)))
end
