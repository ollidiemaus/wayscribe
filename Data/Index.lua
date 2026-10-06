local _, ns = ...

-- Derived data (docs/ARCHITECTURE.md §4.5):
--   * the sorted day list lives in memory only and is rebuilt at every load,
--   * `firsts` and month rollups are saved for speed but are caches: Rebuild recomputes them
--     from records and counters, so a rollup change is just "bump ROLLUP_VERSION and rebuild".
local Index = {
    -- 2 (0.5): days with entries, firsts, level range, dungeon names and first clears, first boss
    -- kills, death places, professions learned and curated chains, for Your Year
    -- (docs/ARCHITECTURE.md §8).
    ROLLUP_VERSION = 2,
}
ns.Index = Index

local dayKeys = {} -- newest first
local dayKnown = {}

function Index.NewRollup()
    return { records = {}, counters = {} }
end

function Index:Build(db)
    dayKeys, dayKnown = {}, {}
    for _, month in pairs(db.months) do
        if type(month) == "table" and type(month.days) == "table" then
            for dayKey in pairs(month.days) do
                if type(dayKey) == "number" and not dayKnown[dayKey] then
                    dayKeys[#dayKeys + 1] = dayKey
                    dayKnown[dayKey] = true
                end
            end
        end
    end
    table.sort(dayKeys, function(a, b) return a > b end)
end

function Index:AddDay(dayKey)
    if dayKnown[dayKey] then return end
    dayKnown[dayKey] = true
    -- New days are almost always the newest, so search from the front.
    local position = 1
    while dayKeys[position] and dayKeys[position] > dayKey do
        position = position + 1
    end
    table.insert(dayKeys, position, dayKey)
end

function Index:RemoveDay(dayKey)
    if not dayKnown[dayKey] then return end
    dayKnown[dayKey] = nil
    for i = 1, #dayKeys do
        if dayKeys[i] == dayKey then
            table.remove(dayKeys, i)
            return
        end
    end
end

function Index:GetDayKeys()
    return dayKeys
end

function Index:ApplyRecord(db, month, record, def)
    local rollup = month.rollup
    rollup.records[record.type] = (rollup.records[record.type] or 0) + 1
    if def.firstKey then
        local ok, key = pcall(def.firstKey, record.data, record)
        if not ok then
            ns.Log:Error("firstKey:" .. record.type, key)
        elseif type(key) == "string" and db.firsts[key] == nil then
            db.firsts[key] = record.id
            record.first = true
            rollup.firsts = (rollup.firsts or 0) + 1
        end
    end
    if def.rollup then
        local ok, err = pcall(def.rollup, rollup, record.data, record)
        if not ok then
            ns.Log:Error("rollup:" .. record.type, err)
        end
    end
end

function Index:ApplyCount(month, path, key, amount)
    local counters = month.rollup.counters
    local bucket = counters[path]
    if not bucket then
        bucket = {}
        counters[path] = bucket
    end
    bucket[key] = (bucket[key] or 0) + amount
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do
        if type(key) == "number" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

local function byTime(a, b)
    if a.ts ~= b.ts then return a.ts < b.ts end
    return a.id < b.id
end

function Index:RebuildDay(db, month, day)
    local count = 0
    if type(day.records) == "table" then
        table.sort(day.records, byTime)
        for _, record in ipairs(day.records) do
            record.first = nil
            local def = ns.RecordTypes:Get(record.type)
            if def then
                self:ApplyRecord(db, month, record, def)
            end
            count = count + 1
        end
    end
    if type(day.counters) == "table" then
        for path, bucket in pairs(day.counters) do
            for key, amount in pairs(bucket) do
                self:ApplyCount(month, path, key, amount)
            end
        end
    end
    return count
end

-- Recomputes firsts, "first" flags and month rollups in chronological order. Records of
-- unknown types are kept untouched (they may come from a removed feature).
function Index:Rebuild(db)
    db.firsts = {}
    local total = 0
    for _, monthKey in ipairs(sortedKeys(db.months)) do
        local month = db.months[monthKey]
        if type(month) == "table" and type(month.days) == "table" then
            month.rollup = Index.NewRollup()
            for _, dayKey in ipairs(sortedKeys(month.days)) do
                local day = month.days[dayKey]
                if type(day) == "table" then
                    month.rollup.activeDays = (month.rollup.activeDays or 0) + 1
                    total = total + self:RebuildDay(db, month, day)
                end
            end
        end
    end
    db.meta.rollup = Index.ROLLUP_VERSION
    self:Build(db)
    return total
end

-- Rollups written by an older version lack fields that newer ones fill: they are rebuilt once.
-- Returns whether it rebuilt.
function Index:Upgrade(db)
    if db.meta.rollup == Index.ROLLUP_VERSION then return false end
    self:Rebuild(db)
    return true
end
