local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local HOUR = 3600

local function at(month, day, hour, minute)
    return os.time({ year = 2026, month = month, day = day, hour = hour or 12, min = minute or 0 })
end

-- A year of play through the real write paths. March 1, 12:00-14:00: level 11, a first Ragefire
-- Chasm clear with Xy and Ab, a first boss kill, a death in Mulgore, ore, Mining to 75, two quests
-- completing the Defias chain, travel and a hearthstone. October 3, 20:00 to 01:30: levels 12-14,
-- Ragefire again and a first Wailing Caverns with Xy, a visit without the final boss, the old boss
-- again and a new one, three deaths.
local function playYear(opts)
    opts = opts or {}
    local ns = Stubs.LoadAddon({ level = 10, now = at(3, 1), locale = opts.locale })
    Stubs.Login()
    local Store, Players = ns.Store, ns.Players
    Stubs.state.itemNames[2770] = "Copper Ore"
    local xy = Players:Intern("Player-1-0000000X", "Xy")
    local ab = Players:Intern("Player-1-000000AB", "Ab")
    Store:SetState("professions", { [186] = { rank = 1, max = 75, name = "Mining" } })

    Stubs.Fire("PLAYER_LEVEL_UP", 11)
    Store:Append("DUNGEON_COMPLETED", { instanceID = 389, name = "Ragefire Chasm", roster = { xy, ab }, dur = 2400 })
    Store:Append("BOSS_KILLED", { encounterID = 2733, name = "Taragaman the Hungerer" })
    Store:Append("DEATH", { map = 1412 })
    Store:Count("nodes", "mining", 3)
    Store:Count("gather", 2770, 7)
    Store:Count("gather", 2835, 2)
    Store:Append("PROFESSION_LEARNED", { skillLine = 186 })
    Store:Count("skill", 186, 74)
    Store:Append("PROFESSION_RANK", { skillLine = 186, rank = 75 })
    Store:Count("quests", 166, 1)
    Store:Count("quests", 167, 1)
    Store:Append("QUEST_CHAIN_COMPLETED", { chain = "DEFIAS", quest = 166 })
    Store:Count("travel", "ground", 3520)
    Store:Count("travel", "flight", 1760)
    Store:Append("TELEPORT", { spell = 8690 })
    Stubs.Advance(2 * HOUR)
    Store:EndSession(Stubs.Now())

    Stubs.SetTime(at(10, 3, 20))
    Store:StartSession(Stubs.Now())
    Stubs.Fire("PLAYER_LEVEL_UP", 12)
    Store:Append("DUNGEON_COMPLETED", { instanceID = 389, name = "Ragefire Chasm", roster = { xy }, dur = 1800 })
    Store:Append("DUNGEON_COMPLETED", { instanceID = 43, name = "Wailing Caverns", roster = { xy }, dur = 3600 })
    Store:Append("DUNGEON_VISITED", { instanceID = 48, name = "Blackfathom Deeps", dur = 300 })
    Store:Append("BOSS_KILLED", { encounterID = 2733, name = "Taragaman the Hungerer" })
    Store:Append("BOSS_KILLED", { encounterID = 1443, name = "Mutanus" })
    Stubs.Fire("PLAYER_LEVEL_UP", 13)
    Store:Append("DEATH", { map = 1412 })
    Store:Append("DEATH", { map = 1412 })
    Store:Append("DEATH", { map = 1411 })
    Stubs.Advance(3 * HOUR)
    Stubs.Fire("PLAYER_LEVEL_UP", 14)
    Stubs.Advance(2.5 * HOUR)
    Store:EndSession(Stubs.Now())
    Stubs.SetTime(at(12, 5))
    return ns
end

-- id -> { title, big, caption, lines... } for a compact comparison.
local function cardsOf(ns, year)
    local list, ids = {}, {}
    for _, card in ipairs(ns.YearCards:Build(year or 2026)) do
        ids[#ids + 1] = card.id
        local flat = { card.title, card.big, card.caption }
        for _, line in ipairs(card.lines) do flat[#flat + 1] = line end
        list[card.id] = flat
    end
    return list, ids
end

describe("cards", function()
    it("tell the year from its facts, one card per tracker, in order", function()
        local ns = playYear()
        local cards, ids = cardsOf(ns)
        T.same(ids, {
            "overview", "levels", "dungeons", "bosses", "companions", "deaths", "gathering", "professions",
            "quests", "footsteps", "time",
        })
        T.same(cards.overview, {
            "The year at a glance", "19", "entries in your journal", "7 of them were firsts", "Adventures on 2 days in 2 months",
        })
        T.same(cards.levels, {
            "Levels", "+4", "levels gained, from 10 to 14", "Reached level 14 on Saturday, October 3, 2026",
        })
        T.same(cards.dungeons, {
            "Dungeons and raids", "3", "runs completed", "2 different dungeons and raids",
            "Most often: Ragefire Chasm, 2 times", "First clear of Ragefire Chasm: Sunday, March 1, 2026",
            "Plus 1 visit without the final boss",
        })
        T.same(cards.bosses, { "Bosses", "3", "bosses defeated", "2 of them for the first time" })
        T.same(cards.companions, {
            "Companions", "2", "companions in dungeons and raids", "Xy: 3 runs together", "Ab: 1 run together",
        })
        T.same(cards.deaths, { "Deaths", "4", "deaths", "Most dangerous place: Mulgore (3 deaths)" })
        T.same(cards.gathering, {
            "Gathering", "3", "times mined, picked or skinned", "Ore deposits mined: 3", "9 items in all",
            "Most gathered: 7× Copper Ore",
        })
        T.same(cards.professions, {
            "Professions", "74", "skill points gained", "Learned Mining", "Mining reached 75", "Skill gains: Mining +74",
        })
        T.same(cards.quests, { "Quests", "2", "quests turned in", "1 quest chain completed", "The Defias Brotherhood" })
        T.same(cards.footsteps, {
            "Footsteps", "2.0 miles", "traveled over land", "Flight paths: 1.0 miles", "1 journey by hearthstone or teleport",
        })
        T.same(cards.time, {
            "Time played", "7 h 30 min", "in 2 sessions on 2 days", "Most active month: October (5 h 30 min)",
            "Most active day: Saturday, October 3, 2026 (4 h 0 min)", "Longest session: 5 h 30 min",
        })
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("render from the month rollups alone, without a single day of the journal", function()
        local ns = playYear()
        local before = cardsOf(ns)
        for _, month in pairs(ns.charDB.months) do
            month.days = {}
        end
        ns.Index:Build(ns.charDB)
        T.same(cardsOf(ns), before)
    end)

    it("leave out what didn't happen, and an empty year has none", function()
        local ns = Stubs.LoadAddon({ now = at(12, 1) })
        Stubs.Login()
        T.same({ cardsOf(ns, 2025) }, { {}, {} })
        Stubs.Fire("PLAYER_LEVEL_UP", 11)
        local _, ids = cardsOf(ns)
        T.same(ids, { "overview", "levels" }, "no time has passed in the open session yet")
        Stubs.Advance(600)
        _, ids = cardsOf(ns)
        T.same(ids, { "overview", "levels", "time" })
    end)

    it("read in German, with German numbers", function()
        local ns = playYear({ locale = "deDE" })
        for _ = 1, 1200 do ns.Store:Count("quests", 1, 1) end
        local cards = cardsOf(ns)
        T.same(cards.quests, { "Quests", "1.202", "Quests abgegeben", "1 Questreihe abgeschlossen", "Die Defias-Bruderschaft" })
        T.same(cards.levels, { "Stufen", "+4", "Stufen aufgestiegen, von 10 auf 14", "Stufe 14 erreicht am Samstag, 3. Oktober 2026" })
        T.same(cards.footsteps, {
            "Fußspuren", "3,2 km", "über Land zurückgelegt", "Flugrouten: 1,6 km", "1 Reise per Ruhestein oder Teleport",
        })
        T.eq(cards.dungeons[5], "Am häufigsten: Ragefire Chasm, 2-mal")
    end)

    it("lose only themselves when one breaks", function()
        local ns = playYear()
        ns.YearCards:Register({ id = "broken", order = 5, build = function() error("boom") end })
        local _, ids = cardsOf(ns)
        T.eq(ids[2], "levels")
        T.truthy(ns.Log:GetEntries()[1].message:find("boom"))
    end)
end)

describe("rollups", function()
    it("from an older version are rebuilt once at login", function()
        local journal = {
            schema = 1,
            meta = { seq = 2, guid = "Player-1-0000AAAA", name = "Tester", realm = "Forever", created = 1 },
            state = {}, players = {}, firsts = { ["BOSS:7"] = 2 },
            months = {
                [202610] = {
                    days = {
                        [20261002] = {
                            records = {
                                { id = 1, ts = at(10, 2, 9), type = "LEVEL_UP", v = 1, data = { level = 10 } },
                                { id = 2, ts = at(10, 2, 10), type = "BOSS_KILLED", v = 1, data = { encounterID = 7 }, first = true },
                            },
                            counters = {},
                        },
                    },
                    sessions = {},
                    rollup = { records = { LEVEL_UP = 1, BOSS_KILLED = 1 }, counters = {}, maxLevel = 10 },
                },
            },
        }
        local ns = Stubs.LoadAddon({ charDB = journal })
        Stubs.Login()
        local rollup = ns.charDB.months[202610].rollup
        T.eq(ns.charDB.meta.rollup, ns.Index.ROLLUP_VERSION)
        T.eq(rollup.minLevel, 10)
        T.eq(rollup.maxLevelAt, at(10, 2, 9))
        T.eq(rollup.bossFirsts, 1)
        T.eq(rollup.activeDays, 1)
        T.eq(rollup.firsts, 1)
        T.falsy(ns.Index:Upgrade(ns.charDB), "only once")
    end)

    it("are current in a new journal", function()
        local ns = Stubs.LoadAddon()
        Stubs.Login()
        T.eq(ns.charDB.meta.rollup, ns.Index.ROLLUP_VERSION)
    end)
end)

describe("card helpers", function()
    it("format numbers, percentages and plurals", function()
        local ns = Stubs.LoadAddon()
        local YearCards = ns.YearCards
        T.eq(YearCards.Number(0), "0")
        T.eq(YearCards.Number(999), "999")
        T.eq(YearCards.Number(1234), "1,234")
        T.eq(YearCards.Number(1234567), "1,234,567")
        T.eq(YearCards.Number(-4321), "-4,321")
        T.eq(YearCards.Percent(12.345), "12.3%")
        T.eq(YearCards.Percent(0.04), "under 0.1%")
        T.eq(YearCards.Percent(0), "0.0%")
        T.eq(YearCards.Plural("CARD_RUNS_TOGETHER", 1), "1 run together")
        T.eq(YearCards.Plural("CARD_RUNS_TOGETHER", 1500), "1,500 runs together")
        T.eq(YearCards.List({ "A", "B", "C", "D", "E" }, 3), "A, B, C and 2 more")
        T.eq(YearCards.List({ "A", "B" }), "A and B")
        T.same(YearCards.Ranked({ a = 1, b = 3, c = 3, d = 2 }, 3), { "b", "c", "d" })
        T.same({ YearCards.Top({ [5] = 2, [3] = 2, [9] = 1 }) }, { 3, 2 })
    end)

    it("have every singular in German that English has", function()
        local en = Stubs.LoadAddon().L
        local de = Stubs.LoadAddon({ locale = "deDE" }).L
        for key in pairs(en) do
            if type(key) == "string" and key:find("_ONE$") then
                T.truthy(rawget(de, key) ~= en[key], key .. " is not translated")
            end
        end
    end)
end)
