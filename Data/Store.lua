local _, ns = ...
local Time = ns.Time

-- The single write path for journal data (docs/ARCHITECTURE.md §4.4, §4.5). Trackers never touch
-- WayscribeCharDB directly. Layout: months[YYYYMM] = { days = { [YYYYMMDD] = { records, counters } },
-- sessions, rollup }.
local Store = {}
ns.Store = Store

-- Dedupe keys seen this session (e.g. one kill reported by two events). In memory only.
local recentKeys = {}

-- Attaching makes the journal readable; writing additionally needs no safe mode.
function Store:Attach(db)
    self.db = db
    recentKeys = {}
    ns.Index:Build(db)
    ns.Players:Attach(db.players)
end

function Store:IsWritable()
    return self.db ~= nil and ns.safeMode == nil
end

function Store:GetOrCreateMonth(monthKey)
    local month = self.db.months[monthKey]
    if not month then
        month = { days = {}, sessions = {}, rollup = ns.Index.NewRollup() }
        self.db.months[monthKey] = month
    end
    return month
end

function Store:GetOrCreateDay(ts)
    local dayKey = Time.DayKey(ts)
    local month = self:GetOrCreateMonth(Time.MonthOfDay(dayKey))
    local day = month.days[dayKey]
    if not day then
        day = { records = {}, counters = {} }
        month.days[dayKey] = day
        ns.Index:AddDay(dayKey)
    end
    return day, month, dayKey
end

-- Adds a milestone record. data must be a fresh table owned by the journal from now on.
-- opts.ts: timestamp (default now); opts.dedupeKey: skip if seen this session;
-- opts.simulated: mark as test data (/ws simulate). Returns the record, or nil plus a reason.
function Store:Append(typeName, data, opts)
    if not self:IsWritable() then return nil, "read-only" end
    local def = ns.RecordTypes:Get(typeName)
    if not def then
        ns.Log:Error("store", "unknown record type " .. tostring(typeName))
        return nil, "unknown record type"
    end
    local ok, reason = ns.RecordTypes:Validate(def, data)
    if not ok then
        ns.Log:Error("store", typeName .. ": " .. reason)
        return nil, reason
    end
    local dedupeKey = opts and opts.dedupeKey
    if dedupeKey then
        if recentKeys[dedupeKey] then return nil, "duplicate" end
        recentKeys[dedupeKey] = true
    end

    local db = self.db
    local ts = (opts and opts.ts) or Time.Now()
    db.meta.seq = db.meta.seq + 1
    local record = { id = db.meta.seq, ts = ts, type = typeName, v = def.version, data = data }
    if opts and opts.simulated then
        record.sim = true
    end
    local day, month = self:GetOrCreateDay(ts)
    day.records[#day.records + 1] = record
    ns.Index:ApplyRecord(db, month, record, def)
    ns.Bus:Fire("RECORD_ADDED", record)
    return record
end

-- Adds amount to a per-day counter, e.g. Store:Count("gather", itemID, 3).
function Store:Count(path, key, amount, ts)
    if not self:IsWritable() then return false end
    amount = amount or 1
    if type(path) ~= "string" or ns.Compat.Safe(key) == nil or ns.Compat.Safe(amount, "number") == nil
        or (type(key) ~= "string" and type(key) ~= "number") then
        ns.Log:Error("store", "invalid counter " .. tostring(path))
        return false
    end
    local day, month = self:GetOrCreateDay(ts or Time.Now())
    local bucket = day.counters[path]
    if not bucket then
        bucket = {}
        day.counters[path] = bucket
    end
    bucket[key] = (bucket[key] or 0) + amount
    ns.Index:ApplyCount(month, path, key, amount)
    ns.Bus:Fire("COUNTER_CHANGED", path, key, amount)
    return true
end

-- Resumable tracker state (snapshots, an open dungeon run, ...).
function Store:GetState(key)
    return self.db and self.db.state[key]
end

function Store:SetState(key, value)
    if not self:IsWritable() then return false end
    self.db.state[key] = value
    return true
end

------------------------------------------------------------------------------------------------
-- Sessions: months[m].sessions = { { s = start, e = end }, ... }; state.session points at the
-- current one by month and index (never by table reference, which the client can't save).

function Store:StartSession(ts)
    if not self:IsWritable() then return nil end
    local monthKey = Time.MonthKey(ts)
    local month = self:GetOrCreateMonth(monthKey)
    local session = { s = ts }
    month.sessions[#month.sessions + 1] = session
    self.db.state.session = { m = monthKey, i = #month.sessions }
    return session
end

function Store:GetCurrentSession()
    local ref = self.db and self.db.state.session
    if type(ref) ~= "table" then return nil end
    local month = self.db.months[ref.m]
    local session = month and month.sessions and month.sessions[ref.i]
    return type(session) == "table" and session or nil
end

-- After a /reload the same game session continues.
function Store:ResumeSession()
    if not self:IsWritable() then return nil end
    local session = self:GetCurrentSession()
    if session then
        session.e = nil
    end
    return session
end

function Store:EndSession(ts)
    if not self:IsWritable() then return end
    local session = self:GetCurrentSession()
    if session then
        session.e = ts
    end
end

------------------------------------------------------------------------------------------------
-- Reads

function Store:GetDayKeys()
    return ns.Index:GetDayKeys()
end

function Store:GetMonth(monthKey)
    return self.db and self.db.months[monthKey]
end

function Store:GetDay(dayKey)
    local month = self:GetMonth(Time.MonthOfDay(dayKey))
    return month and month.days[dayKey]
end

local function byTime(a, b)
    if a.ts ~= b.ts then return a.ts < b.ts end
    return a.id < b.id
end

-- A time-sorted copy of the day's records (a changed system clock can append out of order).
function Store:GetDayRecords(dayKey)
    local day = self:GetDay(dayKey)
    local records = {}
    if not day then return records end
    for i, record in ipairs(day.records) do
        records[i] = record
    end
    table.sort(records, byTime)
    return records
end

-- Records with fromTs <= ts <= toTs (time-sorted), plus the summed counters of every day the range
-- touches. Counters are kept per day, so they can include other sessions of the same day.
function Store:GetActivity(fromTs, toTs)
    local records, counters = {}, {}
    local firstDay, lastDay = Time.DayKey(fromTs), Time.DayKey(toTs)
    for _, dayKey in ipairs(self:GetDayKeys()) do
        if dayKey >= firstDay and dayKey <= lastDay then
            local day = self:GetDay(dayKey)
            for _, record in ipairs(day.records) do
                if record.ts >= fromTs and record.ts <= toTs then
                    records[#records + 1] = record
                end
            end
            for path, bucket in pairs(day.counters) do
                counters[path] = counters[path] or {}
                for key, amount in pairs(bucket) do
                    counters[path][key] = (counters[path][key] or 0) + amount
                end
            end
        end
    end
    table.sort(records, byTime)
    return records, counters
end

-- The most recent session before the current one (for the login recap), or nil.
function Store:GetPreviousSession()
    if not self.db then return nil end
    local current = self.db.state.session
    local monthKeys = {}
    for monthKey, month in pairs(self.db.months) do
        if type(monthKey) == "number" and type(month.sessions) == "table" then
            monthKeys[#monthKeys + 1] = monthKey
        end
    end
    table.sort(monthKeys, function(a, b) return a > b end)
    for _, monthKey in ipairs(monthKeys) do
        local sessions = self.db.months[monthKey].sessions
        for i = #sessions, 1, -1 do
            local isCurrent = type(current) == "table" and current.m == monthKey and current.i == i
            if not isCurrent and type(sessions[i]) == "table" and type(sessions[i].s) == "number" then
                return sessions[i]
            end
        end
    end
    return nil
end

function Store:GetFirst(key)
    return self.db and self.db.firsts[key]
end

local function sessionSeconds(sessions, now)
    local seconds, count = 0, 0
    for _, session in ipairs(sessions) do
        if type(session.s) == "number" then
            local stop = session.e or now
            if stop > session.s then
                seconds = seconds + (stop - session.s)
            end
            count = count + 1
        end
    end
    return seconds, count
end

-- Month rollup plus what is derived on read: play time, session count, active days.
function Store:GetMonthSummary(monthKey)
    local month = self:GetMonth(monthKey)
    if not month then return nil end
    local activeDays = 0
    for _ in pairs(month.days) do activeDays = activeDays + 1 end
    local playSeconds, sessions = sessionSeconds(month.sessions, Time.Now())
    return { rollup = month.rollup, playSeconds = playSeconds, sessions = sessions, activeDays = activeDays }
end

local function addCounts(target, source)
    for key, amount in pairs(source) do
        target[key] = (target[key] or 0) + amount
    end
end

-- Sums the 12 month summaries; type-specific rollup fields are combined by each type's merge().
function Store:GetYearSummary(year)
    local summary = { rollup = ns.Index.NewRollup(), playSeconds = 0, sessions = 0, activeDays = 0, months = 0 }
    for month = 1, 12 do
        local monthSummary = self:GetMonthSummary(year * 100 + month)
        if monthSummary then
            summary.months = summary.months + 1
            summary.playSeconds = summary.playSeconds + monthSummary.playSeconds
            summary.sessions = summary.sessions + monthSummary.sessions
            summary.activeDays = summary.activeDays + monthSummary.activeDays
            local source = monthSummary.rollup
            addCounts(summary.rollup.records, source.records)
            for path, bucket in pairs(source.counters) do
                summary.rollup.counters[path] = summary.rollup.counters[path] or {}
                addCounts(summary.rollup.counters[path], bucket)
            end
            for _, def in pairs(ns.RecordTypes.defs) do
                if def.merge then
                    local ok, err = pcall(def.merge, summary.rollup, source)
                    if not ok then ns.Log:Error("merge:" .. def.name, err) end
                end
            end
        end
    end
    return summary
end

function Store:GetStats()
    local stats = { months = 0, days = 0, records = 0, sessions = 0, simulated = 0, seq = 0 }
    local db = self.db
    if not db then return stats end
    stats.seq = db.meta.seq
    for _, month in pairs(db.months) do
        stats.months = stats.months + 1
        stats.sessions = stats.sessions + #month.sessions
        for _, day in pairs(month.days) do
            stats.days = stats.days + 1
            stats.records = stats.records + #day.records
            for _, record in ipairs(day.records) do
                if record.sim then stats.simulated = stats.simulated + 1 end
            end
        end
    end
    return stats
end

------------------------------------------------------------------------------------------------
-- Maintenance

function Store:Rebuild()
    if not self:IsWritable() then return nil end
    return ns.Index:Rebuild(self.db)
end

-- Removes /ws simulate test data, then rebuilds everything derived from it.
function Store:RemoveSimulated()
    if not self:IsWritable() then return nil end
    local removed = 0
    for _, month in pairs(self.db.months) do
        for dayKey, day in pairs(month.days) do
            local kept = {}
            for _, record in ipairs(day.records) do
                if record.sim then
                    removed = removed + 1
                else
                    kept[#kept + 1] = record
                end
            end
            day.records = kept
            if #kept == 0 and next(day.counters) == nil then
                month.days[dayKey] = nil
                ns.Index:RemoveDay(dayKey)
            end
        end
    end
    ns.Index:Rebuild(self.db)
    return removed
end
