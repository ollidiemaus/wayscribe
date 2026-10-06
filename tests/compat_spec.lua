local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local SECRET = Stubs.SECRET

describe("Safe", function()
    local Compat = Stubs.LoadAddon().Compat

    it("drops secrets and wrong types", function()
        T.eq(Compat.Safe(nil), nil)
        T.eq(Compat.Safe(SECRET), nil)
        T.eq(Compat.Safe(5, "number"), 5)
        T.eq(Compat.Safe("x", "number"), nil)
        T.eq(Compat.Safe(false), false)
    end)

    it("Call sanitizes every return value and survives errors", function()
        local a, b, c, d = Compat.Call(function() return 1, SECRET, nil, "x" end)
        T.eq(a, 1)
        T.eq(b, nil)
        T.eq(c, nil)
        T.eq(d, "x")
        T.eq(Compat.Call(function() error("boom") end), nil)
        T.eq(Compat.Call(nil), nil)
    end)
end)

describe("flavor", function()
    it("detects Forever by interface number", function()
        T.truthy(Stubs.LoadAddon({ interface = 16001 }).Compat.isForever)
        T.falsy(Stubs.LoadAddon({ interface = 120100 }).Compat.isForever)
        T.falsy(Stubs.LoadAddon({ interface = 11509 }).Compat.isForever)
    end)
end)

describe("capabilities", function()
    it("checks events without breaking on unknown ones", function()
        local Compat = Stubs.LoadAddon({ unknownEvents = { LFG_COMPLETION_REWARD = true } }).Compat
        T.truthy(Compat.EventExists("ENCOUNTER_END"))
        T.falsy(Compat.EventExists("LFG_COMPLETION_REWARD"))
    end)

    it("prefers C_EventUtils when the client has it", function()
        local Compat = Stubs.LoadAddon().Compat
        _G.C_EventUtils = { IsEventValid = function(event) return event == "BOSS_KILL" end }
        T.truthy(Compat.EventExists("BOSS_KILL"))
        T.falsy(Compat.EventExists("ENCOUNTER_END"))
        _G.C_EventUtils = nil
    end)

    it("probe runs even when most APIs are missing", function()
        local ns = Stubs.LoadAddon()
        Stubs.Login()
        local lines = ns.Probe:Run()
        T.truthy(#lines > 10)
        T.eq(lines[1]:find("probe failed"), nil, lines[1])
        T.same(ns.accountDB.probe.lines, lines)
    end)
end)
