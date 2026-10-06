local _, ns = ...

-- Packs integer lists into short printable strings, so bulk data (Footsteps trails) is one string
-- constant in the SavedVariables file instead of thousands of tables (docs/ARCHITECTURE.md §6.8).
--
-- Each number is zigzag-encoded (so small negatives stay small) and written as a varint: every
-- character carries 5 bits of the value, plus a 6th bit that says "more characters follow".
-- Arithmetic only (no bit library), so it behaves the same in WoW and in plain Lua tests.
local Codec = {}
ns.Codec = Codec

-- URL-safe base64 alphabet: no quotes or backslashes, so the saved file needs no escaping.
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local CHAR = {}
local VALUE = {}
for i = 1, #ALPHABET do
    local char = ALPHABET:sub(i, i)
    CHAR[i - 1] = char
    VALUE[char:byte()] = i - 1
end

local DATA_RANGE = 32 -- 5 payload bits per character
local MAX_SAFE = 2 ^ 52 -- zigzag doubles the value; stay inside exact double precision

local function zigzag(n)
    if n >= 0 then
        return n * 2
    end
    return -n * 2 - 1
end

local function unzigzag(z)
    if z % 2 == 0 then
        return math.floor(z / 2)
    end
    return -math.floor((z + 1) / 2)
end

local function writeVarint(out, n)
    repeat
        local chunk = n % DATA_RANGE
        n = math.floor(n / DATA_RANGE)
        if n > 0 then
            chunk = chunk + DATA_RANGE
        end
        out[#out + 1] = CHAR[chunk]
    until n == 0
end

local function checkInteger(value)
    if type(value) ~= "number" or value % 1 ~= 0 or value >= MAX_SAFE or value <= -MAX_SAFE then
        error("Codec only stores integers below 2^52, got " .. tostring(value), 3)
    end
end

function Codec.EncodeInts(list)
    local out = {}
    for i = 1, #list do
        checkInteger(list[i])
        writeVarint(out, zigzag(list[i]))
    end
    return table.concat(out)
end

-- Returns the list, or nil plus a reason for malformed input.
function Codec.DecodeInts(text)
    if type(text) ~= "string" then return nil, "not a string" end
    local list = {}
    local value, scale = 0, 1
    local pending = false
    for i = 1, #text do
        local digit = VALUE[text:byte(i)]
        if not digit then
            return nil, "invalid character at " .. i
        end
        if digit >= DATA_RANGE then
            value = value + (digit - DATA_RANGE) * scale
            scale = scale * DATA_RANGE
            pending = true
        else
            value = value + digit * scale
            list[#list + 1] = unzigzag(value)
            value, scale = 0, 1
            pending = false
        end
    end
    if pending then
        return nil, "truncated number"
    end
    return list
end

-- points is a flat list {x1, y1, x2, y2, ...} of integers. Consecutive points are close
-- together, so storing differences keeps almost every number to one or two characters.
function Codec.EncodePath(points)
    if #points % 2 ~= 0 then
        error("EncodePath needs x,y pairs", 2)
    end
    local deltas = {}
    local lastX, lastY = 0, 0
    for i = 1, #points, 2 do
        local x, y = points[i], points[i + 1]
        checkInteger(x)
        checkInteger(y)
        deltas[i] = x - lastX
        deltas[i + 1] = y - lastY
        lastX, lastY = x, y
    end
    return Codec.EncodeInts(deltas)
end

function Codec.DecodePath(text)
    local deltas, reason = Codec.DecodeInts(text)
    if not deltas then return nil, reason end
    if #deltas % 2 ~= 0 then return nil, "odd number of coordinates" end
    local points = {}
    local x, y = 0, 0
    for i = 1, #deltas, 2 do
        x = x + deltas[i]
        y = y + deltas[i + 1]
        points[i] = x
        points[i + 1] = y
    end
    return points
end
