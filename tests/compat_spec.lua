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

    it("CallWithRaw keeps the raw value next to the safe one, and says whether the call ran", function()
        local function pack(...) return { n = select("#", ...), ... } end
        local got = pack(Compat.CallWithRaw(function(a, b) return a + b end, "number", 2, 3))
        T.eq(got[1], 5)
        T.eq(got[2], 5)
        T.eq(got[3], true)
        got = pack(Compat.CallWithRaw(function() return SECRET end, "number"))
        T.eq(got[1], nil)
        T.eq(got[2], SECRET, "a secret stays raw")
        T.eq(got[3], true)
        got = pack(Compat.CallWithRaw(function() return "x" end, "number"))
        T.eq(got[1], nil)
        T.eq(got[2], "x", "a value of another type stays raw")
        got = pack(Compat.CallWithRaw(function() return nil end, "number"))
        T.eq(got[3], true, "a call that returns nothing still ran")
        got = pack(Compat.CallWithRaw(function() error("boom") end, "number"))
        T.eq(got[1], nil)
        T.eq(got[3], nil)
        T.eq(Compat.CallWithRaw(nil, "number"), nil)
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

    it("finds a nearby player by full name or first name, with their level", function()
        local ns = Stubs.LoadAddon({ name = "Tester", surname = "Brightwood" })
        Stubs.Login()
        Stubs.SetUnit("nameplate7", { guid = "Player-1-000000C1", name = "Kangal", surname = "Mooran", class = "WARRIOR", level = 6 })
        local found = ns.Compat.FindNearbyPlayer("Kangal Mooran")
        T.eq(found.guid, "Player-1-000000C1")
        T.eq(found.name, "Kangal Mooran")
        T.eq(found.class, "WARRIOR")
        T.eq(found.level, 6)
        T.eq(ns.Compat.FindNearbyPlayer("Kangal").guid, "Player-1-000000C1")
        T.eq(ns.Compat.FindNearbyPlayer("Bo"), nil)
        T.eq(ns.Compat.FindNearbyPlayer(Stubs.SECRET), nil)
        T.eq(ns.Compat.GetClassName("WARRIOR"), "Warrior")
        T.eq(ns.Compat.GetClassName("NOPE"), nil)
    end)
end)

describe("global strings", function()
    it("turn a format into a pattern, in either argument order", function()
        local ns = Stubs.LoadAddon()
        local pattern, order = ns.Compat.FormatToPattern("%1$s has defeated %2$s in a duel")
        T.eq(pattern, "^(.+) has defeated (.+) in a duel$")
        T.same(order, { 1, 2 })
        pattern, order = ns.Compat.FormatToPattern("%2$s ist vor %1$s aus einem Duell geflüchtet.")
        T.eq(pattern, "^(.+) ist vor (.+) aus einem Duell geflüchtet%.$")
        T.same(order, { 2, 1 })
        pattern, order = ns.Compat.FormatToPattern("%s (100%) %s: %d")
        T.eq(pattern, "^(.+) %(100%%%) (.+): (%-?%d+)$")
        T.same(order, { 1, 2, 3 })
    end)

    it("parse a line into its arguments by position, in the client's language", function()
        local ns = Stubs.LoadAddon()
        _G.DUEL_WINNER_RETREAT = "%2$s ist vor %1$s aus einem Duell geflüchtet." -- read at the first parse
        T.same(ns.Compat.ParseGlobalString("DUEL_WINNER_RETREAT", "Bo Stone ist vor Tester aus einem Duell geflüchtet."),
            { "Tester", "Bo Stone" })
        T.same(ns.Compat.ParseGlobalString("DUEL_COUNTDOWN", "Duel starting: 3"), { "3" })
        T.eq(ns.Compat.ParseGlobalString("DUEL_COUNTDOWN", "You are now away."), nil)
        T.eq(ns.Compat.ParseGlobalString("DUEL_COUNTDOWN", Stubs.SECRET), nil)
        T.eq(ns.Compat.ParseGlobalString("NO_SUCH_STRING", "Duel starting: 3"), nil)
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

    it("probe reads what the launch trackers rely on, and names what is missing or secret", function()
        local ns = Stubs.LoadAddon()
        _G.C_Map.GetBestMapForUnit = function() return 1412 end
        Stubs.SetExplored({ [1412] = { { isShownByMouseOver = true }, { isShownByMouseOver = true } } })
        Stubs.state.cvars.onlyShowCollectedItemsInJournal = "1"
        _G.GetMoney = function() return 12345 end
        _G.C_Reputation = {
            GetNumFactions = function() return 3 end,
            GetFactionDataByIndex = function(index)
                return ({ { isHeader = true, isCollapsed = true, name = "Horde" },
                    { factionID = 81, name = "Thunder Bluff", reaction = 5 },
                    { factionID = 530, name = "Darkspear Trolls", reaction = 4 } })[index]
            end,
            GetFactionDataByID = function(id)
                if id == 81 then return { factionID = 81, reaction = 5 } end
                if id == 2800 then return { name = "PvP Rank Points", reaction = 4 } end
            end,
        }
        _G.FACTION_STANDING_LABEL5, _G.FACTION_STANDING_LABEL5_FEMALE = "Friendly", "Friendly"
        _G.GetInventoryItemID = function(_, slot) return ({ [1] = 6125, [16] = 2361 })[slot] end
        _G.GetInventoryItemQuality = function(_, slot) return slot == 16 and Stubs.SECRET or 1 end
        _G.GetCategoryList = function() return { 92 } end
        _G.GetCategoryNumAchievements = function() return 2 end
        _G.GetAchievementInfo = function(_, index)
            if index == 1 then return 6, "Level 10", 0, true, 10, 14, 26, "", 0, "", "", false, false end
            return 7, "Level 20", 0, false
        end
        _G.IsInGuild = function() return false end
        _G.GetBindLocation = function() return "Bloodhoof Village" end
        Stubs.Login()
        local found = {}
        for _, line in ipairs(ns.Probe:Run()) do found[line] = true end
        _G.FACTION_STANDING_LABEL5, _G.FACTION_STANDING_LABEL5_FEMALE = nil, nil
        T.truthy(found["event.PLAYER_MONEY = true"])
        T.truthy(found["firstVisit.map.0 = 1412 Mulgore (type 3)"])
        T.truthy(found["firstVisit.zone = 1412"])
        T.truthy(found["firstVisit.explored = 0 of 1 zones (textures/hover-only): 1412 2/2"])
        T.truthy(found["gold.money = 12345"])
        T.truthy(found["rep.list = 2 factions, 1 headers (1 collapsed)"])
        T.truthy(found["rep.sample = 81 Thunder Bluff, reaction 5 Friendly / Friendly"])
        T.truthy(found["rep.sampleByID = 5"])
        T.truthy(found["rep.2800 = PvP Rank Points, reaction 4"])
        T.truthy(found["rep.2802 = nil"])
        T.truthy(found["gear.slots = 1:6125/q1 16:2361/qsecret"])
        T.truthy(found["legacy.challenges = 2 in 1 categories, 1 completed, 0 by this character"])
        T.truthy(found["legacy.sample = 6 Level 10, 10/14/26, by me false"])
        T.truthy(found["flightPaths.taxiMap = missing"])
        T.truthy(found["guild.inGuild = false"])
        T.truthy(found["guild.name = missing"])
        T.truthy(found["home.bind = Bloodhoof Village"])
        T.truthy(found["collections.mounts = missing"])
        T.truthy(found["collections.toys = missing of missing"])
        T.truthy(found["collections.hasAnyToy = missing"])
        T.truthy(found["collections.onlyShowCollected = 1"])
        T.truthy(found["pvpRank.level = missing"])
    end)
end)
