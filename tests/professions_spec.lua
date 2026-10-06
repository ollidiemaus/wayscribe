local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local MINING, HERBALISM = 186, 182

local function records(ns)
    return ns.Store:GetDayRecords(20261003)
end

-- Login plus the delayed first snapshot.
local function start(professions)
    Stubs.LoadAddon()
    Stubs.SetProfessions(professions or {})
    Stubs.Login()
    Stubs.Advance(3)
    return Stubs.ns
end

local function skillChanged(professions)
    Stubs.SetProfessions(professions)
    Stubs.Fire("SKILL_LINES_CHANGED")
    Stubs.Advance(1)
end

describe("professions", function()
    it("takes a silent baseline the first time", function()
        local ns = start({ { skillLine = MINING, name = "Mining", rank = 52, max = 75 } })
        T.eq(#records(ns), 0)
        T.same(ns.Store:GetState("professions"), { [MINING] = { rank = 52, max = 75, name = "Mining" } })
    end)

    it("records a newly learned profession", function()
        local ns = start()
        skillChanged({ { skillLine = MINING, name = "Mining", rank = 1, max = 75 } })
        local list = records(ns)
        T.eq(#list, 1)
        T.eq(list[1].type, "PROFESSION_LEARNED")
        T.truthy(list[1].first)
        T.eq(ns.RecordTypes:Render(list[1]), "Learned Mining")
    end)

    it("counts skill points and records rank milestones", function()
        local ns = start({ { skillLine = MINING, name = "Mining", rank = 70, max = 150 } })
        skillChanged({ { skillLine = MINING, name = "Mining", rank = 80, max = 150 } })
        local list = records(ns)
        T.eq(#list, 1)
        T.same(list[1].data, { skillLine = MINING, rank = 75 })
        T.eq(ns.RecordTypes:Render(list[1]), "Mining reached 75")
        local day = ns.Store:GetDay(20261003)
        T.eq(day.counters.skill[MINING], 10)
        T.same(ns.RecordTypes:RenderCounters(day.counters), { "Skill gains: Mining +10" })
        T.eq(ns.charDB.months[202610].rollup.professionRanks[MINING], 75)
    end)

    it("takes one snapshot per burst of events", function()
        local ns = start({ { skillLine = MINING, name = "Mining", rank = 10, max = 75 } })
        local calls = 0
        local original = GetProfessions
        _G.GetProfessions = function(...) calls = calls + 1 return original(...) end
        Stubs.SetProfessions({ { skillLine = MINING, name = "Mining", rank = 11, max = 75 } })
        Stubs.Fire("SKILL_LINES_CHANGED")
        Stubs.Fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 11.")
        Stubs.Fire("SKILL_LINES_CHANGED")
        Stubs.Advance(1)
        T.eq(calls, 1)
        T.eq(ns.Store:GetDay(20261003).counters.skill[MINING], 1)
    end)

    it("doesn't forget a profession missing from one snapshot", function()
        local ns = start({ { skillLine = MINING, name = "Mining", rank = 40, max = 75 } })
        skillChanged({}) -- data not loaded yet
        skillChanged({ { skillLine = MINING, name = "Mining", rank = 40, max = 75 } })
        T.eq(#records(ns), 0, "not learned again")
    end)

    it("records nothing when a profession was unlearned and learned again", function()
        local ns = start({ { skillLine = MINING, name = "Mining", rank = 120, max = 150 } })
        skillChanged({ { skillLine = MINING, name = "Mining", rank = 1, max = 75 } })
        T.eq(#records(ns), 0)
        T.eq(ns.Store:GetState("professions")[MINING].rank, 1)
    end)

    it("reconciles changes made while the addon was off at the next login", function()
        start({ { skillLine = MINING, name = "Mining", rank = 140, max = 150 } })
        Stubs.SetProfessions({
            { skillLine = MINING, name = "Mining", rank = 150, max = 225 },
            { skillLine = HERBALISM, name = "Herbalism", rank = 1, max = 75 },
        })
        local ns = Stubs.Relog()
        Stubs.Advance(3)
        local types = {}
        for _, record in ipairs(records(ns)) do types[#types + 1] = record.type end
        table.sort(types)
        T.same(types, { "PROFESSION_LEARNED", "PROFESSION_RANK" })
        T.eq(ns.Store:GetDay(20261003).counters.skill[MINING], 10)
    end)

    it("shows a skill line name from the game when it has one", function()
        local ns = start()
        _G.C_TradeSkillUI = { GetTradeSkillDisplayName = function(id) return id == MINING and "Bergbau" or nil end }
        skillChanged({ { skillLine = MINING, name = "Mining", rank = 1, max = 75 } })
        T.eq(ns.RecordTypes:Render(records(ns)[1]), "Learned Bergbau")
        _G.C_TradeSkillUI = nil
    end)
end)
