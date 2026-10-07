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

describe("names", function()
    it("uses the name and realm where the second value is the realm", function()
        local ns = Stubs.LoadAddon({ name = "Tester", realm = "Forever" })
        Stubs.SetGroup({ { guid = "Player-1-000000B1", name = "Xy", realm = "Other", class = "PRIEST" } })
        Stubs.Login()
        T.falsy(ns.Compat.has.surnames)
        local me = ns.Compat.GetPlayerIdentity()
        T.eq(me.name, "Tester")
        T.eq(me.realm, "Forever")
        local member = ns.Compat.GetGroupMembers()[1]
        T.eq(member.name, "Xy")
        T.eq(member.realm, "Other")
    end)

    it("joins Forever's first name and surname, and takes the realm from GetRealmName", function()
        local ns = Stubs.LoadAddon({ name = "Tester", surname = "Brightwood", realm = "Forever" })
        Stubs.SetGroup({
            { guid = "Player-1-000000B1", name = "Xy", surname = "Ashford", realm = "Other", class = "PRIEST" },
            { guid = "Player-1-000000B2", name = "Ab", class = "WARRIOR" },
        })
        Stubs.Login()
        T.truthy(ns.Compat.has.surnames)
        local me = ns.Compat.GetPlayerIdentity()
        T.eq(me.name, "Tester Brightwood")
        T.eq(me.realm, "Forever")
        local members = ns.Compat.GetGroupMembers()
        T.eq(members[1].name, "Xy Ashford")
        T.eq(members[1].realm, nil, "the surname is not a realm")
        T.eq(members[2].name, "Ab", "a unit without a surname keeps its name")
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

    it("probe checks the footsteps' map math against the client's own map position", function()
        local ns = Stubs.LoadAddon()
        _G.C_Map.GetBestMapForUnit = function() return 1412 end
        Stubs.SetPosition(1, Stubs.MapToWorld(1412, 0.4416, 0.7706))
        Stubs.Login()
        local found = {}
        for _, line in ipairs(ns.Probe:Run()) do found[line] = true end
        T.truthy(found["map.position = 0.4416, 0.7706"])
        T.truthy(found["map.fromWorld = 0.4416, 0.7706 (5138 x 3425 yd)"])
        T.truthy(found["map.atWorld = 1412"])
        T.truthy(found["map.parent = 1414"])
        T.truthy(found["taxi = false"])
    end)

    it("finds the player's world position with or without UnitPosition", function()
        local ns = Stubs.LoadAddon()
        _G.C_Map.GetBestMapForUnit = function() return 1412 end
        Stubs.SetPosition(1, -2894.3, -238.8)
        Stubs.Login()
        T.same({ ns.Compat.GetPlayerWorldPosition() }, { 1, -2894.3, -238.8 })
        ns.Compat.has.unitPosition = false
        local continent, x, y = ns.Compat.GetPlayerWorldPosition()
        T.eq(continent, 1)
        T.truthy(math.abs(x + 2894.3) < 0.001 and math.abs(y + 238.8) < 0.001, "through the map position")
        _G.UnitPosition = function() return Stubs.SECRET, Stubs.SECRET, 0, 1 end
        ns.Compat.has.unitPosition = true
        T.eq(ns.Compat.GetPlayerWorldPosition(), nil, "a hidden position is no position")
    end)

    it("trims spell names, which can come with stray spaces", function()
        local ns = Stubs.LoadAddon()
        Stubs.state.spellNames[23491] = " Extrem sicherer Transporter: Gadgetzan"
        Stubs.state.spellNames[1] = "  "
        T.eq(ns.Compat.GetSpellName(23491), "Extrem sicherer Transporter: Gadgetzan")
        T.eq(ns.Compat.GetSpellName(1), nil)
        T.eq(ns.Compat.GetSpellName(2), nil)
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
