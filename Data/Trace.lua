local _, ns = ...
local Compat = ns.Compat

-- The launch trace (docs/ARCHITECTURE.md §6.11), developer mode only: one line for each look a
-- launch tracker takes, with the event that asked for it, the values it read and how it ended, so
-- a wrong entry after launch comes with the facts to fix it. Kept account-wide in
-- WayscribeDB.trace, oldest out first; /ws trace shows the last lines.
local Trace = {}
ns.Trace = Trace

local MAX_LINES = 500

local function describe(value)
    if Compat.IsSecret(value) then return "secret" end
    if value == nil then return "missing" end
    local kind = type(value)
    -- "||" is a literal "|" in chat, so a name can't start an escape code in /ws trace.
    if kind == "string" then return '"' .. value:gsub("|", "||") .. '"' end
    -- %.0f, not %d: Lua 5.1 formats %d through a C long, 32 bits on Windows.
    if kind == "number" and value % 1 == 0 and math.abs(value) < 2 ^ 53 then return string.format("%.0f", value) end
    return tostring(value)
end

local function kindOf(value)
    return Compat.IsSecret(value) and "secret" or type(value)
end

-- Numbers in order, then strings; anything else (secret keys too) is never compared.
local function before(a, b)
    local kindA, kindB = kindOf(a), kindOf(b)
    if kindA == kindB and (kindA == "number" or kindA == "string") then return a < b end
    return kindA < kindB
end

-- A table shows as its keys, sorted: the trackers' snapshots are sets of IDs.
local function describeValue(value)
    if type(value) ~= "table" or Compat.IsSecret(value) then return describe(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, before)
    for i, key in ipairs(keys) do keys[i] = describe(key) end
    return "{" .. table.concat(keys, ",") .. "}"
end

local function describePairs(...)
    local parts = {}
    for i = 1, select("#", ...), 2 do
        local name, value = select(i, ...)
        if name then parts[#parts + 1] = name .. "=" .. describeValue(value) end
    end
    return table.concat(parts, " ")
end

-- One look by a launch tracker: its id, the event(s) that asked for the look, how the look ended
-- ("recorded", "known", ...), then the values it read as name, value pairs. A pair whose name is
-- false or nil is left out (a value only some looks read); a nil value shows as "missing" and a
-- secret one as "secret". Values read through Compat.Call arrive with secrets already turned to nil.
-- Never raises: a fault in the trace must not count against the tracker that called it.
function Trace:Add(tracker, event, outcome, ...)
    local db = ns.accountDB
    if not (ns.devMode and db) then return end
    local ok, values = pcall(describePairs, ...)
    if not ok then values = "trace error: " .. ns.Log.ToText(values) end
    local line = date("%Y-%m-%d %H:%M:%S", time()) .. " " .. tostring(tracker) .. " " .. tostring(event) .. ": "
        .. values .. " -> " .. tostring(outcome)
    if type(db.trace) ~= "table" then db.trace = {} end
    local lines = db.trace
    lines[#lines + 1] = line
    while #lines > MAX_LINES do table.remove(lines, 1) end
end

function Trace:GetLines()
    local lines = ns.accountDB and ns.accountDB.trace
    return type(lines) == "table" and lines or {}
end

function Trace:Clear()
    if ns.accountDB then ns.accountDB.trace = nil end
end
