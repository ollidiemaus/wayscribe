local _, ns = ...
local Time = ns.Time

-- The single write path for Footsteps trails (docs/ARCHITECTURE.md §6.8). WayscribeFootstepsDB is kept
-- apart from the journal, so it can be wiped, pruned or archived on its own:
--   months[YYYYMM].days[YYYYMMDD] = { { c = continent, t = start, d = seconds moving,
--                                       f = true for a flight, p = packed points }, ... }
-- The trail being recorded right now lives only in memory (SetLive) until it ends.
--
-- Bus messages: PATH_ADDED(segment, dayKey), PATH_LIVE(live or nil), PATH_POINT(live), PATH_WIPED.
local Paths = {}
ns.Paths = Paths

local EMPTY = {}

function Paths:Attach(db)
    self.db = db
    self.live = nil
end

-- Set by Schema when the trails didn't load cleanly; the journal keeps working.
function Paths:SetReadOnly(reason)
    self.readOnly = self.readOnly or reason
end

function Paths:IsWritable()
    return self.db ~= nil and self.readOnly == nil and ns.Store:IsWritable()
end

local function isNumber(value)
    return ns.Compat.Safe(value, "number") ~= nil
end

-- Only these fields, as plain values: the client must be able to save what we keep.
local function sanitize(segment)
    if type(segment) ~= "table" or not (isNumber(segment.c) and isNumber(segment.t) and isNumber(segment.d)) then
        return nil
    end
    if ns.Compat.Safe(segment.p, "string") == nil or segment.p == "" then return nil end
    if segment.f ~= nil and segment.f ~= true then return nil end
    return { c = segment.c, t = segment.t, d = segment.d, f = segment.f, p = segment.p }
end

-- Stores a finished trail on the day it started. Returns the stored segment, or nil plus a reason.
function Paths:AddSegment(segment)
    if not self:IsWritable() then return nil, "read-only" end
    local stored = sanitize(segment)
    if not stored then
        ns.Log:Error("paths", "invalid segment")
        return nil, "invalid segment"
    end
    local dayKey = Time.DayKey(stored.t)
    local monthKey = Time.MonthOfDay(dayKey)
    local month = self.db.months[monthKey]
    if not month then
        month = { days = {} }
        self.db.months[monthKey] = month
    end
    local day = month.days[dayKey]
    if not day then
        day = {}
        month.days[dayKey] = day
    end
    day[#day + 1] = stored
    self.db.seq = self.db.seq + 1
    ns.Bus:Fire("PATH_ADDED", stored, dayKey)
    return stored
end

------------------------------------------------------------------------------------------------
-- The trail being recorded: { c, t, f, day, points, n }, owned by the recorder.

function Paths:SetLive(live)
    self.live = live
    ns.Bus:Fire("PATH_LIVE", live)
end

function Paths:GetLive()
    return self.live
end

-- The recorder added a point to the live trail.
function Paths:LiveMoved()
    ns.Bus:Fire("PATH_POINT", self.live)
end

------------------------------------------------------------------------------------------------
-- Reads

local function daysOf(month)
    return type(month) == "table" and type(month.days) == "table" and month.days or EMPTY
end

-- The stored trails of one day, oldest first. Don't modify the list.
function Paths:GetDay(dayKey)
    local month = self.db and self.db.months[Time.MonthOfDay(dayKey)]
    local day = daysOf(month)[dayKey]
    return type(day) == "table" and day or EMPTY
end

local function readable(segment)
    return type(segment) == "table" and type(segment.c) == "number" and type(segment.t) == "number"
        and type(segment.p) == "string"
end

-- Trails of the days fromDay..toDay (nil = no limit on that side), oldest first.
function Paths:GetSegments(fromDay, toDay)
    local found = {}
    if not self.db then return found end
    local fromMonth = fromDay and Time.MonthOfDay(fromDay)
    local toMonth = toDay and Time.MonthOfDay(toDay)
    for monthKey, month in pairs(self.db.months) do
        if type(monthKey) == "number" and (not fromMonth or monthKey >= fromMonth) and (not toMonth or monthKey <= toMonth) then
            for dayKey, day in pairs(daysOf(month)) do
                if type(dayKey) == "number" and type(day) == "table"
                    and (not fromDay or dayKey >= fromDay) and (not toDay or dayKey <= toDay) then
                    for _, segment in ipairs(day) do
                        if readable(segment) then found[#found + 1] = segment end
                    end
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.t < b.t end)
    return found
end

-- Whether there is anything to show for a day, including the trail being recorded.
function Paths:HasDay(dayKey)
    if #self:GetDay(dayKey) > 0 then return true end
    return self.live ~= nil and self.live.day == dayKey
end

-- Trails, days with trails and the size of the packed points (what /ws stats reports).
function Paths:GetStats()
    local stats = { segments = 0, days = 0, bytes = 0, seq = self.db and self.db.seq or 0 }
    if not self.db then return stats end
    for _, month in pairs(self.db.months) do
        for _, day in pairs(daysOf(month)) do
            if type(day) == "table" and #day > 0 then
                stats.days = stats.days + 1
                for _, segment in ipairs(day) do
                    if readable(segment) then
                        stats.segments = stats.segments + 1
                        stats.bytes = stats.bytes + #segment.p
                    end
                end
            end
        end
    end
    return stats
end

------------------------------------------------------------------------------------------------
-- Maintenance

-- Settings > Footsteps > Delete: all trails go, the journal (and its distance lines) stays.
function Paths:Wipe()
    if not self:IsWritable() then return false end
    self.db.months = {}
    self.db.seq = 0
    ns.Bus:Fire("PATH_WIPED")
    return true
end
