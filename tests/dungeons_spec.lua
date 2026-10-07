local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local MINUTE = 60
local GROUP = {
    { guid = "Player-1-000000B1", name = "Xy", realm = nil, class = "PRIEST" },
    { guid = "Player-1-000000B2", name = "Ab", realm = "Other", class = "WARRIOR" },
    { guid = "Player-1-000000B3", name = "Cd", realm = nil, class = "ROGUE" },
    { guid = "Player-1-000000B4", name = "Ef", realm = nil, class = "SHAMAN" },
}

local NAMES = { [389] = "Ragefire Chasm", [43] = "Wailing Caverns" }

local function enter(id, instanceType, name)
    Stubs.SetInstance(id, instanceType or "party", name or NAMES[id])
    Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
end

local function leave()
    Stubs.SetInstance()
    Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
end

-- What the client sends for one kill: both events, like ForeverChronicle observed.
local function kill(encounterID, name)
    Stubs.Fire("ENCOUNTER_END", encounterID, name, 1, 5, 1)
    Stubs.Fire("BOSS_KILL", encounterID, name)
end

local function ofType(ns, typeName)
    local found = {}
    for _, dayKey in ipairs(ns.Store:GetDayKeys()) do
        for _, record in ipairs(ns.Store:GetDayRecords(dayKey)) do
            if record.type == typeName then found[#found + 1] = record end
        end
    end
    return found
end

local function start()
    local ns = Stubs.LoadAddon({ level = 15 })
    Stubs.SetGroup(GROUP)
    Stubs.Login()
    return ns
end

describe("a full Ragefire Chasm run", function()
    it("produces the expected entries, including after a mid-run /reload", function()
        start()
        enter(389, "party", "Ragefire Chasm")
        local entered = Stubs.Now()
        Stubs.Advance(5 * MINUTE)
        kill(2732, "Oggleflint")
        Stubs.Advance(5 * MINUTE)
        kill(2733, "Taragaman the Hungerer")

        local ns = Stubs.Relog(nil, true) -- /reload in the middle of the run
        Stubs.Advance(5 * MINUTE)
        kill(2734, "Jergosh the Invoker")
        Stubs.Advance(5 * MINUTE)
        kill(2735, "Bazzalan")
        local lastKill = Stubs.Now()
        Stubs.Advance(2 * MINUTE)
        leave()

        local bosses = ofType(ns, "BOSS_KILLED")
        T.eq(#bosses, 4, "one entry per boss despite two events per kill")
        T.eq(ns.RecordTypes:Render(bosses[1]), "Defeated Oggleflint for the first time")
        T.same(bosses[4].data.roster, { 1, 2, 3, 4 })
        T.eq(bosses[4].data.instanceID, 389)

        local runs = ofType(ns, "DUNGEON_COMPLETED")
        T.eq(#runs, 1, "one run, not two halves")
        local run = runs[1]
        T.same(run.data.bosses, { 2732, 2733, 2734, 2735 })
        T.same(run.data.roster, { 1, 2, 3, 4 })
        T.eq(run.data.dur, lastKill - entered)
        T.eq(run.ts, lastKill, "dated at the last final boss, not at leaving")
        T.truthy(run.first)
        T.eq(ns.RecordTypes:Render(run), "First clear of Ragefire Chasm with Xy, Ab, Cd and Ef (20 min)")
        T.eq(#ofType(ns, "DUNGEON_VISITED"), 0)
        T.eq(ns.Store:GetState("activeRun"), nil)
        T.eq(ns.Store:GetFirst("DUNGEON:389"), run.id)
    end)

    it("a second clear is not a first", function()
        local ns = start()
        enter(389)
        kill(2733, "Taragaman the Hungerer")
        leave()
        Stubs.Advance(60 * MINUTE)
        enter(389)
        kill(2733, "Taragaman the Hungerer")
        leave()
        local runs = ofType(ns, "DUNGEON_COMPLETED")
        T.eq(#runs, 2)
        T.falsy(runs[2].first)
        T.eq(ns.RecordTypes:Render(runs[2]):find("^Cleared Ragefire Chasm"), 1)
        T.eq(ns.charDB.months[202610].rollup.dungeons[389], 2)
    end)
end)

describe("open runs", function()
    it("a corpse run continues the same run", function()
        local ns = start()
        enter(389)
        kill(2732, "Oggleflint")
        leave() -- released after a wipe
        Stubs.Advance(4 * MINUTE)
        enter(389)
        kill(2733, "Taragaman the Hungerer")
        leave()
        local runs = ofType(ns, "DUNGEON_COMPLETED")
        T.eq(#runs, 1)
        T.same(runs[1].data.bosses, { 2732, 2733 })
    end)

    it("closes as visited once the player stays out for 30 minutes", function()
        local ns = start()
        enter(389, "party", "Ragefire Chasm")
        Stubs.Advance(10 * MINUTE)
        kill(2732, "Oggleflint")
        Stubs.Advance(MINUTE)
        leave()
        local left = Stubs.Now()
        Stubs.Advance(29 * MINUTE)
        T.eq(#ofType(ns, "DUNGEON_VISITED"), 0, "still resumable")
        Stubs.Advance(2 * MINUTE)
        local visits = ofType(ns, "DUNGEON_VISITED")
        T.eq(#visits, 1)
        T.eq(visits[1].ts, left)
        T.eq(visits[1].data.dur, 11 * MINUTE)
        T.eq(ns.RecordTypes:Render(visits[1]), "Visited Ragefire Chasm and defeated 1 boss with Xy, Ab, Cd and Ef")
    end)

    it("entering another instance closes the previous run", function()
        local ns = start()
        enter(389, "party", "Ragefire Chasm")
        kill(2732, "Oggleflint")
        leave()
        Stubs.Advance(5 * MINUTE)
        enter(43, "party", "Wailing Caverns")
        T.eq(#ofType(ns, "DUNGEON_VISITED"), 1)
        T.eq(ns.Store:GetState("activeRun").instanceID, 43)
    end)

    it("a relog within 30 minutes continues the run, a later one starts a new run", function()
        start()
        enter(389, "party", "Ragefire Chasm")
        kill(2732, "Oggleflint")
        Stubs.Advance(MINUTE)
        local ns = Stubs.Relog({ now = Stubs.Now() + 10 * MINUTE }) -- disconnect inside
        T.same(ns.Store:GetState("activeRun").bosses, { 2732 })

        Stubs.Advance(MINUTE)
        ns = Stubs.Relog({ now = Stubs.Now() + 2 * 3600 }) -- logged out inside, back much later
        local visits = ofType(ns, "DUNGEON_VISITED")
        T.eq(#visits, 1)
        T.same(ns.Store:GetState("activeRun").bosses, {}, "a new run in the same instance")
    end)

    it("a boss killed again after a reset starts a new run", function()
        local ns = start()
        enter(389)
        kill(2732, "Oggleflint")
        Stubs.Advance(20 * MINUTE)
        kill(2732, "Oggleflint")
        T.eq(#ofType(ns, "DUNGEON_VISITED"), 1)
        T.same(ns.Store:GetState("activeRun").bosses, { 2732 })
    end)

    it("a short visit without kills leaves no entry", function()
        local ns = start()
        enter(389)
        Stubs.Advance(30)
        leave()
        Stubs.Advance(31 * MINUTE)
        T.eq(ns.Store:GetStats().records, 0)
    end)

    it("zoning back in after a clear is not a new visit", function()
        local ns = start()
        enter(389)
        kill(2733, "Taragaman the Hungerer")
        leave()
        enter(389)
        Stubs.Advance(5 * MINUTE)
        leave()
        Stubs.Advance(31 * MINUTE)
        T.eq(#ofType(ns, "DUNGEON_COMPLETED"), 1)
        T.eq(#ofType(ns, "DUNGEON_VISITED"), 0)
    end)
end)

describe("instance data", function()
    it("knows wings that share one instance", function()
        local ns = start()
        enter(189, "party", "Scarlet Monastery")
        kill(446, "Houndmaster Loksey")
        kill(447, "Arcanist Doan")
        leave()
        local run = ofType(ns, "DUNGEON_COMPLETED")[1]
        T.eq(run.data.wing, "library")
        T.eq(ns.Store:GetFirst("DUNGEON:189:library"), run.id)
        T.truthy(ns.RecordTypes:Render(run):find("^First clear of Scarlet Monastery %(Library%) with"))
    end)

    it("an instance without data still records the run as visited", function()
        local ns = start()
        enter(2784, "party", "Demon Fall Canyon")
        kill(3023, "Grimroot")
        leave()
        Stubs.Advance(31 * MINUTE)
        T.eq(#ofType(ns, "DUNGEON_VISITED"), 1)
        T.eq(#ofType(ns, "DUNGEON_COMPLETED"), 0)
    end)

    it("tracks raids and their roster", function()
        local ns = start()
        local raid = {}
        for i = 1, 39 do
            raid[i] = { guid = string.format("Player-1-%08X", i), name = "Raider" .. i, class = "MAGE" }
        end
        Stubs.SetGroup(raid)
        enter(409, "raid", "Molten Core")
        kill(672, "Ragnaros")
        leave()
        local run = ofType(ns, "DUNGEON_COMPLETED")[1]
        T.eq(#run.data.roster, 39)
        T.truthy(ns.RecordTypes:Render(run):find("Raider1, Raider2, Raider3, Raider4 and 35 others", 1, true))
    end)

    it("names Forever's players with their surnames", function()
        local ns = Stubs.LoadAddon({ level = 15, surname = "Brightwood" })
        Stubs.SetGroup({
            { guid = "Player-1-000000B1", name = "Xy", surname = "Ashford", class = "PRIEST" },
            { guid = "Player-1-000000B2", name = "Ab", surname = "Stonebrook", class = "WARRIOR" },
        })
        Stubs.Login()
        enter(389)
        kill(2735, "Bazzalan")
        leave()
        local run = ofType(ns, "DUNGEON_COMPLETED")[1]
        T.truthy(ns.RecordTypes:Render(run):find("with Xy Ashford and Ab Stonebrook", 1, true))
        T.eq(ns.Players:Get(1).realm, nil)
    end)

    it("listens for boss kills only inside an instance", function()
        local ns = start()
        local dungeons = ns.Trackers:Get("Dungeons")
        T.falsy(dungeons.frame:IsEventRegistered("ENCOUNTER_END"))
        enter(389)
        T.truthy(dungeons.frame:IsEventRegistered("ENCOUNTER_END"))
        leave()
        T.falsy(dungeons.frame:IsEventRegistered("ENCOUNTER_END"))
    end)

    it("counts companions per month and per year", function()
        local ns = start()
        enter(389)
        kill(2733, "Taragaman the Hungerer")
        leave()
        local year = ns.Store:GetYearSummary(2026)
        T.eq(year.rollup.dungeons[389], 1)
        T.eq(year.rollup.companions[1], 1)
        T.eq(year.rollup.companions[4], 1)
    end)
end)
