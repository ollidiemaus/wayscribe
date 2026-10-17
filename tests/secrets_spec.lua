local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

-- Every event any module registers, delivered with secret arguments (docs/ARCHITECTURE.md §1).
-- In the client a secret number still says "number" to type() and then raises an error when it is
-- compared or added, so for the length of the sweep type() reports Stubs.SECRET as the kind being
-- swept. A handler that skips Compat.Safe/Call shows up as an error in the module's error boundary.

local SKIP = { ADDON_LOADED = true, PLAYER_LOGOUT = true }
local ARGS = 4

local function registeredEvents()
    local seen, events = {}, {}
    for _, frame in ipairs(Stubs.state.frames) do
        for event in pairs(frame.events or {}) do
            if not seen[event] and not SKIP[event] then
                seen[event] = true
                events[#events + 1] = event
            end
        end
    end
    table.sort(events)
    return events
end

local function sweep(kind)
    local accountDB = { schema = 1, log = {}, characters = {}, settings = { devMode = true } }
    local ns = Stubs.LoadAddon({ accountDB = accountDB })
    Stubs.Login()
    Stubs.Advance(10)

    local errors = {}
    local logError = ns.Log.Error
    ns.Log.Error = function(log, source, message)
        errors[#errors + 1] = tostring(source) .. ": " .. tostring(message)
        return logError(log, source, message)
    end
    local realType = type
    _G.type = function(value)
        if value == Stubs.SECRET then return kind end
        return realType(value)
    end

    local events = registeredEvents()
    local ok, err = pcall(function()
        for _, event in ipairs(events) do
            local secrets = {}
            for i = 1, ARGS do secrets[i] = Stubs.SECRET end
            Stubs.Fire(event, unpack(secrets, 1, ARGS))
            Stubs.Advance(10)
        end
    end)

    _G.type = realType
    ns.Log.Error = logError
    assert(ok, err)
    return events, errors
end

describe("secrets", function()
    for _, kind in ipairs({ "number", "string" }) do
        it("every registered event takes secret " .. kind .. " arguments without an error", function()
            local events, errors = sweep(kind)
            T.truthy(#events > 20, "found only " .. #events .. " registered events")
            T.eq(table.concat(errors, "\n"), "")
        end)
    end
end)
