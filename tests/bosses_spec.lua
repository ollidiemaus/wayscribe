local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local function kills(ns)
    local found = {}
    for _, record in ipairs(ns.Store:GetDayRecords(20261003)) do
        if record.type == "BOSS_KILLED" then found[#found + 1] = record end
    end
    return found
end

local function start()
    local ns = Stubs.LoadAddon()
    Stubs.Login()
    return ns
end

describe("boss kills", function()
    it("records a kill with the boss name, instance and group", function()
        local ns = start()
        Stubs.SetGroup({ { guid = "Player-1-000000B1", name = "Xy", class = "PRIEST" } })
        Stubs.SetInstance(36, "party", "Deadmines")
        Stubs.Fire("ENCOUNTER_END", 2747, "Edwin VanCleef", 1, 5, 1)
        local list = kills(ns)
        T.eq(#list, 1)
        T.same(list[1].data, { encounterID = 2747, name = "Edwin VanCleef", instanceID = 36, difficultyID = 1, roster = { 1 } })
        T.truthy(list[1].first)
        T.eq(ns.RecordTypes:Render(list[1]), "Defeated Edwin VanCleef for the first time")
        T.eq(ns.Players:Get(1).name, "Xy")
    end)

    it("counts a kill reported by ENCOUNTER_END and BOSS_KILL once", function()
        local ns = start()
        Stubs.Fire("ENCOUNTER_END", 2747, "Edwin VanCleef", 1, 5, 1)
        Stubs.Fire("BOSS_KILL", 2747, "Edwin VanCleef")
        T.eq(#kills(ns), 1)
    end)

    it("ignores wipes", function()
        local ns = start()
        Stubs.Fire("ENCOUNTER_END", 2747, "Edwin VanCleef", 1, 5, 0)
        T.eq(#kills(ns), 0)
    end)

    it("a later kill of the same boss is not a first", function()
        local ns = start()
        Stubs.Fire("BOSS_KILL", 2747, "Edwin VanCleef")
        Stubs.Advance(3600)
        Stubs.Fire("BOSS_KILL", 2747, "Edwin VanCleef")
        local list = kills(ns)
        T.eq(#list, 2)
        T.falsy(list[2].first)
        T.eq(ns.RecordTypes:Render(list[2]), "Defeated Edwin VanCleef")
    end)

    it("keeps world bosses without an instance", function()
        local ns = start()
        Stubs.Fire("BOSS_KILL", 3027, "Azuregos")
        local data = kills(ns)[1].data
        T.eq(data.instanceID, nil)
        T.eq(data.roster, nil, "no group, no roster")
    end)

    it("survives secret event arguments", function()
        local ns = start()
        Stubs.Fire("ENCOUNTER_END", Stubs.SECRET, "Edwin VanCleef", 1, 5, 1)
        T.eq(#kills(ns), 0, "no encounter ID, nothing to record")
        Stubs.Fire("ENCOUNTER_END", 2747, Stubs.SECRET, 1, 5, 1)
        local list = kills(ns)
        T.eq(#list, 1)
        T.eq(list[1].data.name, nil)
        T.eq(ns.RecordTypes:Render(list[1]), "Defeated boss 2747 for the first time")
        T.eq(#ns.Log:GetEntries(), 0)
    end)
end)
