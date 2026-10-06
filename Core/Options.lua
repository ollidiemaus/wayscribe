local _, ns = ...

-- Account-wide settings (WayscribeDB.settings) with their defaults. Tracker toggles live in
-- settings.trackers and belong to ns.Trackers.
local Options = {}
ns.Options = Options

local DEFAULTS = {
    showLoginRecap = true,
    dateFormat = "", -- "" = the format of the client's language
}

local function settings()
    return ns.accountDB and ns.accountDB.settings
end

function Options:Get(key)
    local stored = settings()
    local value = stored and stored[key]
    if value == nil then
        return DEFAULTS[key]
    end
    return value
end

-- A value equal to the default is stored as nil, so the saved file only holds real choices.
function Options:Set(key, value)
    local stored = settings()
    if not stored then return end
    if value == DEFAULTS[key] then
        value = nil
    end
    stored[key] = value
    ns.Bus:Fire("SETTINGS_CHANGED", key, self:Get(key))
end

-- A sub-table owned by a library, e.g. LibDBIcon's { hide, minimapPos }.
function Options:Table(key)
    local stored = settings()
    if not stored then return {} end
    if type(stored[key]) ~= "table" then
        stored[key] = {}
    end
    return stored[key]
end
