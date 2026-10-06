local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local DAY = 24 * 3600
local BLOOD_OF_THE_CHAMPION = 6602 -- final quest of the Horde Onyxia attunement
local SIDE_QUEST = 840

local function start()
    local ns = Stubs.LoadAddon()
    Stubs.Login()
    Stubs.Advance(5) -- the first back-fill check after login
    return ns
end

local function turnIn(questID)
    Stubs.Fire("QUEST_TURNED_IN", questID, 100, 0)
end

local function chains(ns)
    local found = {}
    for _, dayKey in ipairs(ns.Store:GetDayKeys()) do
        for _, record in ipairs(ns.Store:GetDayRecords(dayKey)) do
            if record.type == "QUEST_CHAIN_COMPLETED" then found[#found + 1] = record end
        end
    end
    return found
end

-- A quest line API that knows one line: 5001 -> 5002 -> 5003.
local function installQuestLines()
    _G.C_QuestLine = {
        GetQuestLineInfo = function(questID)
            if questID >= 5001 and questID <= 5003 then
                return { questLineID = 77, questLineName = "The Long Road", questID = questID }
            end
        end,
        GetQuestLineQuests = function(lineID)
            if lineID == 77 then return { 5001, 5002, 5003 } end
        end,
    }
end

describe("quests turned in", function()
    it("are counted per day and shown as one line", function()
        local ns = start()
        turnIn(SIDE_QUEST)
        turnIn(841)
        turnIn(SIDE_QUEST) -- a repeatable quest
        local day = ns.Store:GetDay(20261003)
        T.same(day.counters.quests, { [SIDE_QUEST] = 2, [841] = 1 })
        T.same(ns.RecordTypes:RenderCounters(day.counters), { "Quests turned in: 3" })
        T.eq(#chains(ns), 0, "an ordinary quest ends no chain")
    end)

    it("ignore a secret quest ID", function()
        local ns = start()
        turnIn(Stubs.SECRET)
        T.eq(ns.Store:GetDay(20261003), nil)
        T.eq(#ns.Log:GetEntries(), 0)
    end)
end)

describe("curated chains", function()
    it("complete when their final quest is turned in, once", function()
        local ns = start()
        turnIn(BLOOD_OF_THE_CHAMPION)
        turnIn(BLOOD_OF_THE_CHAMPION)
        local found = chains(ns)
        T.eq(#found, 1)
        T.same(found[1].data, { chain = "ONYXIA", quest = BLOOD_OF_THE_CHAMPION })
        T.truthy(found[1].first)
        T.falsy(found[1].bf, "recorded live, so the time is known")
        T.eq(ns.RecordTypes:Render(found[1]), "Completed the quest chain: Onyxia's Lair attunement")
        T.eq(ns.Store:GetDay(20261003).counters.quests[BLOOD_OF_THE_CHAMPION], 2)
    end)

    it("have a German name", function()
        local ns = Stubs.LoadAddon({ locale = "deDE" })
        Stubs.Login()
        turnIn(BLOOD_OF_THE_CHAMPION)
        T.eq(ns.RecordTypes:Render(chains(ns)[1]), "Questreihe abgeschlossen: Zugang zu Onyxias Hort")
    end)

    it("every chain has a name in both languages", function()
        local english = Stubs.LoadAddon()
        local german = Stubs.LoadAddon({ locale = "deDE" })
        for _, chain in ipairs(english.StaticData.QuestChains) do
            T.truthy(rawget(english.L, "CHAIN_" .. chain.id), chain.id .. " in English")
            T.truthy(rawget(german.L, "CHAIN_" .. chain.id) ~= rawget(english.L, "CHAIN_" .. chain.id), chain.id .. " in German")
        end
    end)
end)

describe("quest lines from the client", function()
    it("complete a chain at the line's last quest", function()
        local ns = Stubs.LoadAddon()
        installQuestLines()
        Stubs.Login()
        turnIn(5001)
        turnIn(5002)
        T.eq(#chains(ns), 0)
        turnIn(5003)
        local found = chains(ns)
        T.eq(#found, 1)
        T.same(found[1].data, { questLine = 77, quest = 5003, title = "The Long Road" })
        T.eq(ns.RecordTypes:Render(found[1]), "Completed the quest chain: The Long Road")
    end)

    it("are not asked when the client has no quest line API", function()
        local ns = start()
        T.falsy(ns.Compat.has.questLines)
        turnIn(5003)
        T.eq(#chains(ns), 0)
    end)
end)

describe("back-fill", function()
    local NEW_FINAL = 9001

    -- Day 1: the player turns in NEW_FINAL, which no chain ends yet. Day 3: logout.
    local function playedBeforeTheChainExisted()
        local ns = start()
        turnIn(SIDE_QUEST)
        Stubs.Advance(600)
        turnIn(NEW_FINAL)
        Stubs.Advance(2 * DAY)
        turnIn(SIDE_QUEST)
        T.eq(#chains(ns), 0)
        return ns
    end

    local function addChain(ns)
        table.insert(ns.StaticData.QuestChains, { id = "NEW_CHAIN", finals = { NEW_FINAL } })
        ns.StaticData.QuestChainsVersion = ns.StaticData.QuestChainsVersion + 1
        ns.L.CHAIN_NEW_CHAIN = "A chain added later"
    end

    it("adds a chain defined after the fact on the day its final quest was turned in", function()
        playedBeforeTheChainExisted()
        local ns = Stubs.Relog({ setup = addChain })
        T.eq(#chains(ns), 0, "waits until the login has settled")
        Stubs.Advance(5)
        local found = chains(ns)
        T.eq(#found, 1)
        local record = found[1]
        T.same(record.data, { chain = "NEW_CHAIN", quest = NEW_FINAL })
        T.eq(ns.Time.DayKey(record.ts), 20261003, "dated on the day of the turn-in, not today")
        T.eq(record.ts, ns.Time.DayEnd(20261003))
        T.truthy(record.bf, "only the day is known")
        T.truthy(record.first)
        T.eq(ns.Store:GetFirst("CHAIN:NEW_CHAIN"), record.id)
        T.eq(ns.charDB.months[202610].rollup.records.QUEST_CHAIN_COMPLETED, 1)
        T.eq(ns.Store:GetState("questChains"), ns.StaticData.QuestChainsVersion)
        local printed = Stubs.Printed()
        T.truthy(printed[#printed]:find("1 quest chains you completed earlier"))
    end)

    it("doesn't add it twice: not at the next login, not on /ws rebuild", function()
        playedBeforeTheChainExisted()
        Stubs.Relog({ setup = addChain })
        Stubs.Advance(5)
        local ns = Stubs.Relog({ setup = addChain })
        Stubs.Advance(5)
        ns.Slash:Handle("rebuild")
        T.eq(#chains(ns), 1)
        T.truthy(chains(ns)[1].first, "rebuild keeps the first flag")
    end)

    it("runs on /ws rebuild too", function()
        local ns = playedBeforeTheChainExisted()
        addChain(ns)
        ns.Slash:Handle("rebuild")
        T.eq(#chains(ns), 1)
        T.eq(ns.Time.DayKey(chains(ns)[1].ts), 20261003)
    end)

    it("leaves a quest alone that a quest line already credited", function()
        local ns = Stubs.LoadAddon()
        installQuestLines()
        Stubs.Login()
        turnIn(5003)
        T.eq(#chains(ns), 1)
        table.insert(ns.StaticData.QuestChains, { id = "LONG_ROAD", finals = { 5003 } })
        ns.Slash:Handle("rebuild")
        T.eq(#chains(ns), 1)
    end)

    it("is dated now when the final quest was turned in today", function()
        local ns = start()
        turnIn(NEW_FINAL)
        addChain(ns)
        ns.Slash:Handle("rebuild")
        T.eq(chains(ns)[1].ts, Stubs.Now())
    end)

    it("doesn't run while the tracker is off", function()
        local ns = playedBeforeTheChainExisted()
        ns.Trackers:SetWanted("QuestChains", false)
        addChain(ns)
        ns.Slash:Handle("rebuild")
        T.eq(#chains(ns), 0)
    end)
end)
