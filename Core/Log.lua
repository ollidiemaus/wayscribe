local _, ns = ...

local Log = {}
ns.Log = Log

local MAX_ENTRIES = 50
local MAX_MESSAGE_LENGTH = 500

-- Errors raised before the account DB is loaded are kept here and moved over on Attach.
local entries = {}

-- tostring() on a secret value is not allowed, so describe it instead.
local function toText(value)
    local isSecret = issecretvalue
    if isSecret and isSecret(value) then
        return "<secret value>"
    end
    return tostring(value)
end
Log.ToText = toText

function Log:Attach(store)
    for i = 1, #entries do
        store[#store + 1] = entries[i]
    end
    entries = store
    self:Trim()
end

function Log:Trim()
    while #entries > MAX_ENTRIES do
        table.remove(entries, 1)
    end
end

local function add(source, message)
    local text = toText(message)
    if #text > MAX_MESSAGE_LENGTH then
        text = text:sub(1, MAX_MESSAGE_LENGTH) .. "..."
    end
    entries[#entries + 1] = { ts = time(), source = toText(source), message = text }
    Log:Trim()
    return text
end

-- Something the player meets, not a bug: a journal that didn't load, a backup from a newer
-- version. It goes to /ws log only, in developer mode too.
function Log:Warn(source, message)
    add(source, message)
end

function Log:Error(source, message)
    local text = add(source, message)

    -- In developer mode, also hand the error to the default handler so BugSack & co. see it.
    if ns.devMode and geterrorhandler then
        local handler = geterrorhandler()
        if handler then
            pcall(handler, toText(source) .. ": " .. text)
        end
    end
end

function Log:GetEntries()
    return entries
end

local function finish(source, ok, ...)
    if ok then
        return true, ...
    end
    Log:Error(source, (...))
    return false
end

-- pcall that records failures; returns true plus the function's results, or false.
function ns.SafeCall(source, fn, ...)
    return finish(source, pcall(fn, ...))
end
