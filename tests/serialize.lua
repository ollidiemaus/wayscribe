-- Writes a table the way the WoW client writes SavedVariables, and reads it back. It is stricter
-- than the client on purpose: anything the client would drop or silently duplicate is an error,
-- which proves the journal holds plain data only.
local S = {}

local function write(value, seen, out)
    local kind = type(value)
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("non-finite number")
        end
        out[#out + 1] = string.format("%.17g", value)
    elseif kind == "string" then
        out[#out + 1] = string.format("%q", value)
    elseif kind == "boolean" then
        out[#out + 1] = tostring(value)
    elseif kind == "table" then
        if getmetatable(value) ~= nil then error("table with a metatable is not saved") end
        if seen[value] then error("table referenced twice; the client would save two copies") end
        seen[value] = true
        local entries = {}
        for key, item in pairs(value) do
            local keyType = type(key)
            if keyType ~= "string" and keyType ~= "number" then
                error("unsupported key type " .. keyType)
            end
            local parts = { "[" }
            write(key, seen, parts)
            parts[#parts + 1] = "]="
            write(item, seen, parts)
            entries[#entries + 1] = table.concat(parts)
        end
        table.sort(entries)
        out[#out + 1] = "{" .. table.concat(entries, ",") .. "}"
    else
        error("cannot save a " .. kind)
    end
end

function S.Serialize(value)
    if value == nil then return "nil" end
    local out = {}
    write(value, {}, out)
    return table.concat(out)
end

function S.Deserialize(text)
    local loader = loadstring or load
    local chunk = assert(loader("return " .. text))
    return chunk()
end

-- Simulates logout + next login: what survives is exactly what the client would write.
function S.RoundTrip(value)
    return S.Deserialize(S.Serialize(value))
end

return S
