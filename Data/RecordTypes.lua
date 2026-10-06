local _, ns = ...

-- Every journal fact has a registered type; the registration is its contract
-- (docs/ARCHITECTURE.md §4.3):
--   version   number >= 1, bumped when the data shape changes
--   category  journal filter group ("progress", "adventure", ...)
--   fields    { name = "number" | "string" | "boolean" | "table", optional with a trailing "?" }
--   firstKey  function(data, record) -> string, enables the "first time" badge
--   rollup    function(monthRollup, data, record), O(1) update of the month summary
--   merge     function(target, source), combines type-specific rollup fields (year summary)
--   render    function(data, record) -> text [, icon], localized at display time
--   upcast    { [fromVersion] = function(data) -> data in version fromVersion + 1 }
local RecordTypes = { defs = {} }
ns.RecordTypes = RecordTypes

local FIELD_TYPES = { number = true, string = true, boolean = true, table = true }
local MAX_DEPTH = 4

function RecordTypes:Register(name, def)
    assert(type(name) == "string" and name ~= "", "record type needs a name")
    assert(not self.defs[name], "duplicate record type " .. name)
    assert(type(def.version) == "number" and def.version >= 1, name .. ": version must be >= 1")
    def.fields = def.fields or {}
    for field, spec in pairs(def.fields) do
        local base = spec:gsub("%?$", "")
        assert(FIELD_TYPES[base], name .. "." .. field .. ": unknown field type " .. tostring(spec))
    end
    def.name = name
    def.category = def.category or "misc"
    self.defs[name] = def
    return def
end

function RecordTypes:Get(name)
    return self.defs[name]
end

-- Nested tables (e.g. a roster) may only hold plain, non-secret data the client can save.
local function checkPlain(value, depth)
    if ns.Compat.IsSecret(value) then return false, "secret value" end
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then return true end
    if kind ~= "table" then return false, "cannot store a " .. kind end
    if depth > MAX_DEPTH then return false, "nested too deeply" end
    if getmetatable(value) ~= nil then return false, "tables with metatables are not saved" end
    for key, item in pairs(value) do
        local keyType = type(key)
        if keyType ~= "string" and keyType ~= "number" then return false, "unsupported key type " .. keyType end
        local ok, reason = checkPlain(item, depth + 1)
        if not ok then return false, reason end
    end
    return true
end

-- Returns true, or false plus a reason. Rejects secrets, wrong types, missing and unknown fields.
function RecordTypes:Validate(def, data)
    if type(data) ~= "table" then return false, "data must be a table" end
    for field, spec in pairs(def.fields) do
        local optional = spec:sub(-1) == "?"
        local expected = optional and spec:sub(1, -2) or spec
        local value = data[field]
        if value == nil then
            if not optional then return false, "missing field " .. field end
        elseif ns.Compat.IsSecret(value) then
            return false, "secret value in " .. field
        elseif type(value) ~= expected then
            return false, field .. " should be a " .. expected .. ", got a " .. type(value)
        elseif expected == "table" then
            local ok, reason = checkPlain(value, 1)
            if not ok then return false, field .. ": " .. reason end
        end
    end
    for field in pairs(data) do
        if def.fields[field] == nil then return false, "unknown field " .. tostring(field) end
    end
    return true
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do
        result[key] = copy(item)
    end
    return result
end

-- The record's data in the current shape of its type. Older records are upcast on a copy;
-- the stored record is never rewritten here.
function RecordTypes:CurrentData(def, record)
    local version = record.v or 1
    if version >= def.version or not def.upcast then
        return record.data
    end
    local data = copy(record.data)
    for from = version, def.version - 1 do
        local step = def.upcast[from]
        if step then
            data = step(data) or data
        end
    end
    return data
end

-- Never errors: a broken renderer or unknown type shows a placeholder line instead.
function RecordTypes:Render(record)
    local def = self.defs[record.type]
    if not def or not def.render then
        return ns.L.ENTRY_UNREADABLE:format(tostring(record.type))
    end
    local ok, text, icon = pcall(function()
        return def.render(self:CurrentData(def, record), record)
    end)
    if not ok or type(text) ~= "string" then
        if not ok then
            ns.Log:Error("render:" .. tostring(record.type), text)
        end
        return ns.L.ENTRY_UNREADABLE:format(tostring(record.type))
    end
    return text, icon
end
