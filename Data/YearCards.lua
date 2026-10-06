local _, ns = ...
local L = ns.L

-- The cards of Your Year, the yearly recap (docs/ARCHITECTURE.md §8). Like record types, each
-- tracker registers its own card next to the facts it records:
--   id     unique name
--   order  position in the year, low first
--   build  function(summary) -> card, or nil when there is nothing to show. summary is
--          Store:GetYearSummary(year): month rollups and play time, never the day records, so a
--          year renders the same after its days were archived.
-- A card is { title, icon?, big?, caption?, lines = { text, ... } }: a big number with a caption
-- under it, then a few lines.
local YearCards = { list = {} }
ns.YearCards = YearCards

local function byOrder(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.id < b.id
end

function YearCards:Register(def)
    assert(type(def.id) == "string" and def.id ~= "", "card needs an id")
    assert(type(def.build) == "function", def.id .. ": build is required")
    for _, existing in ipairs(self.list) do
        assert(existing.id ~= def.id, "duplicate card " .. def.id)
    end
    def.order = def.order or 100
    self.list[#self.list + 1] = def
    table.sort(self.list, byOrder)
    return def
end

-- The year's cards in order. Never errors: a broken card only loses itself.
function YearCards:Build(year)
    local summary = ns.Store:GetYearSummary(year)
    local cards = {}
    for _, def in ipairs(self.list) do
        local ok, card = pcall(def.build, summary)
        if not ok then
            ns.Log:Error("card:" .. def.id, card)
        elseif type(card) == "table" and type(card.title) == "string" then
            card.id = def.id
            card.lines = card.lines or {}
            cards[#cards + 1] = card
        end
    end
    return cards
end

------------------------------------------------------------------------------------------------
-- Helpers for building cards

-- "1,234" / "1.234"
function YearCards.Number(value)
    local sign, digits = string.format("%d", math.floor(value + 0.5)):match("^(-?)(%d+)$")
    local head = #digits % 3
    local groups = { head > 0 and digits:sub(1, head) or nil }
    for i = head + 1, #digits, 3 do
        groups[#groups + 1] = digits:sub(i, i + 2)
    end
    return sign .. table.concat(groups, L.THOUSANDS_SEPARATOR)
end

-- "12.3%" / "12,3 %"; under 0.1 but above 0 shows "< 0.1%".
function YearCards.Percent(value)
    if value > 0 and value < 0.1 then
        return L.PERCENT_TINY
    end
    local number = string.format("%.1f", value):gsub("%.", L.DECIMAL_POINT)
    return L.PERCENT:format(number)
end

-- The key with the highest count (the lowest key on a tie), and its count; nil for an empty map.
function YearCards.Top(counts)
    local bestKey, bestCount
    for key, count in pairs(counts or {}) do
        if type(count) == "number" and (not bestCount or count > bestCount
            or (count == bestCount and tostring(key) < tostring(bestKey))) then
            bestKey, bestCount = key, count
        end
    end
    return bestKey, bestCount
end

-- The keys sorted by count, highest first (ties by key), at most `max`.
function YearCards.Ranked(counts, max)
    local keys = {}
    for key, count in pairs(counts or {}) do
        if type(count) == "number" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        if counts[a] ~= counts[b] then return counts[a] > counts[b] end
        return tostring(a) < tostring(b)
    end)
    for i = #keys, (max or #keys) + 1, -1 do
        keys[i] = nil
    end
    return keys
end

function YearCards.Sum(counts)
    local total = 0
    for _, count in pairs(counts or {}) do
        if type(count) == "number" then total = total + count end
    end
    return total
end

-- L[key .. "_ONE"] for 1, else L[key]. Every locale that translates `key` translates both.
function YearCards.Pattern(key, count)
    return count == 1 and rawget(L, key .. "_ONE") or L[key]
end

-- The pattern for `count`, formatted with the count as text (%s, with thousands separators):
-- "1 run" / "1,204 runs".
function YearCards.Plural(key, count, ...)
    return YearCards.Pattern(key, count):format(YearCards.Number(count), ...)
end

-- "A, B and C", or "A, B, C and 2 more" beyond `max`.
function YearCards.List(names, max)
    max = max or #names
    local shown = {}
    for i = 1, math.min(#names, max) do shown[i] = names[i] end
    if #names > max then
        return L.LIST_AND:format(table.concat(shown, L.LIST_SEPARATOR), L.LIST_MORE:format(#names - max))
    end
    if #shown <= 1 then return shown[1] or "" end
    local last = table.remove(shown)
    return L.LIST_AND:format(table.concat(shown, L.LIST_SEPARATOR), last)
end

-- The long date of a timestamp: "Saturday, October 3, 2026".
function YearCards.Date(ts)
    return ns.Time.FormatLongDay(ns.Time.DayKey(ts))
end
