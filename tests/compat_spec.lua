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

    it("probe asks the quest line API about the quests in the log", function()
        local ns = Stubs.LoadAddon()
        _G.C_QuestLog.GetNumQuestLogEntries = function() return 3 end
        _G.C_QuestLog.GetInfo = function(index)
            return ({ { isHeader = true, title = "Mulgore" }, { questID = 747 }, { questID = 748 } })[index]
        end
        _G.C_QuestLine = {
            GetQuestLineInfo = function(questID)
                if questID == 747 then return { questLineID = 12, questLineName = "The Hunt" } end
            end,
            GetQuestLineQuests = function() return { 747, 750 } end,
        }
        Stubs.state.questTitles[747] = "The Hunt Begins"
        Stubs.Login()
        local found = {}
        for _, line in ipairs(ns.Probe:Run()) do found[line] = true end
        T.truthy(found["questLine.747 = 12 The Hunt (2 quests, last 750)"])
        T.truthy(found["questTitle.747 = The Hunt Begins"])
        T.truthy(found["questLine.748 = nil"])
        T.truthy(found["questLog.asked = 2"])
    end)
end)
