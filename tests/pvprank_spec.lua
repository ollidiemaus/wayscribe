local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

-- Logs in at PvP rank `rank` in arena season `season` (rank 0 in season 1 unless given) and lets
-- the first look happen; `false` leaves the game without the rank's API.
local function start(rank, season, opts)
    local ns = Stubs.LoadAddon(opts)
    if rank ~= false then Stubs.SetPvPRank(rank or 0, season or 1) end
    Stubs.Login()
    Stubs.Advance(1)
    return ns
end

local function reach(rank)
    Stubs.ReachPvPRank(rank)
    Stubs.Advance(1)
end

local function look()
    Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
    Stubs.Advance(1)
end

local function card(ns)
    local cards, ids, found = ns.YearCards:Build(2026), {}, nil
    for i, built in ipairs(cards) do
        ids[built.id] = i
        if built.id == "pvprank" then found = built end
    end
    return found, ids
end

local function entries(ns)
    local texts = {}
    for _, record in ipairs(ns.Store:GetRecordsOfType("PVP_RANK")) do texts[#texts + 1] = ns.RecordTypes:Render(record) end
    return texts
end

describe("pvp rank", function()
    it("take the rank the character has silently, then record each new highest rank", function()
        local ns = start(1)
        T.same(entries(ns), {}, "ranked before Wayscribe")
        reach(2)
        reach(3)
        T.same(entries(ns), { "Reached PvP rank 2: Grunt", "Reached PvP rank 3: Sergeant" })
        T.eq(ns.RecordTypes:Get("PVP_RANK").category, "pvp")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("make no entry for losing a rank, climbing back, or a new season", function()
        local ns = start(3)
        reach(2)
        reach(3)
        T.same(entries(ns), {}, "rank 3 was reached before")
        Stubs.state.pvpRank.season = 2 -- the season resets the rank
        reach(0)
        reach(1)
        T.same(entries(ns), { "Reached PvP rank 1: Scout" }, "the new season's first rank")
        Stubs.state.pvpRank.season = 3
        Stubs.state.pvpRank.rank = 2 -- the new season comes with a rank, found at the next look
        look()
        T.same(entries(ns), { "Reached PvP rank 1: Scout" })
    end)

    it("ignore other renown tracks", function()
        local ns = start(1)
        Stubs.state.pvpRank.rank = 2
        Stubs.Fire("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 2802, 17, 16)
        Stubs.Advance(1)
        T.same(entries(ns), {})
        Stubs.Fire("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 2800, 2, 1)
        Stubs.Advance(1)
        T.same(entries(ns), { "Reached PvP rank 2: Grunt" })
    end)

    it("catch a missed event at the next look, and record a rank found at login on the login day", function()
        local ns = start(1)
        Stubs.state.pvpRank.rank = 2 -- the rank events never came
        look()
        T.same(entries(ns), { "Reached PvP rank 2: Grunt" })
        Stubs.Fire("PLAYER_LOGOUT")
        Stubs.state.pvpRank.rank = 3 -- reached while Wayscribe was off
        ns = Stubs.Relog({ now = Stubs.Now() + 86400 })
        Stubs.Advance(1)
        T.same(entries(ns), { "Reached PvP rank 2: Grunt", "Reached PvP rank 3: Sergeant" })
        local loginDay = ns.Time.DayKey(Stubs.Now())
        T.same(#ns.Store:GetRecordsOfType("PVP_RANK", loginDay, loginDay), 1)
    end)

    it("name the rank for the Alliance, and by number when the client has no title for it", function()
        local ns = start(0, 1, { faction = "Alliance" })
        reach(1)
        reach(4)
        reach(6)
        T.same(entries(ns), { "Reached PvP rank 1: Private", "Reached PvP rank 4: Master Sergeant",
            "Reached PvP rank 6" })
    end)

    it("write nothing and log no error when the API is missing, errors or is secret", function()
        local ns = start(false)
        Stubs.Fire("PLAYER_PVP_RANK_CHANGED")
        Stubs.Advance(1)
        Stubs.SetPvPRank(1, 1)
        _G.GetCurrentArenaSeason = nil
        look()
        Stubs.SetPvPRank(1, 1)
        _G.C_MajorFactions.GetMajorFactionProgressionInfo = function() error("no faction") end
        look()
        _G.C_MajorFactions.GetMajorFactionProgressionInfo = function() return Stubs.SECRET end
        look()
        _G.C_MajorFactions.GetMajorFactionProgressionInfo = function() return { renownLevel = Stubs.SECRET } end
        look()
        _G.C_MajorFactions.GetMajorFactionProgressionInfo = function() return nil end
        look()
        _G.GetCurrentArenaSeason = function() return Stubs.SECRET end
        look()
        _G.GetCurrentArenaSeason = function() error("no season") end
        look()
        T.same(entries(ns), {})
        T.eq(#ns.Log:GetEntries(), 0)
        Stubs.SetPvPRank(2, 1)
        look()
        T.same(entries(ns), {}, "the first readable look is the first look")
        reach(3)
        T.same(entries(ns), { "Reached PvP rank 3: Sergeant" })
    end)

    it("stop listening when switched off, and find the rank at the next look once switched on", function()
        local ns = start(1)
        ns.Trackers:SetWanted("PvPRank", false)
        reach(2)
        T.same(entries(ns), {})
        ns.Trackers:SetWanted("PvPRank", true)
        Stubs.Advance(1)
        T.same(entries(ns), { "Reached PvP rank 2: Grunt" })
    end)

    it("repeat nothing after a reload, or when the journal comes back without the tracker's state", function()
        start(1)
        reach(2)
        local ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        T.same(entries(ns), { "Reached PvP rank 2: Grunt" })
        ns.Store:SetState("pvpRank", nil)
        ns = Stubs.Relog()
        Stubs.Advance(1)
        T.same(entries(ns), { "Reached PvP rank 2: Grunt" })
        reach(3)
        T.same(entries(ns), { "Reached PvP rank 2: Grunt", "Reached PvP rank 3: Sergeant" })
    end)

    it("repeat nothing after a backup is restored", function()
        local ns = start(1)
        reach(2)
        local text
        ns.Backup:Make({}, function(result) text = result end)
        T.truthy(ns.Schema:ResetCharacter())
        ns = Stubs.Relog(nil, true)
        local found
        ns.Backup:Read(text, function(result) found = result end)
        T.truthy(ns.Backup:Restore(found))
        ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        reach(3)
        T.same(entries(ns), { "Reached PvP rank 2: Grunt", "Reached PvP rank 3: Sergeant" })
    end)

    it("show the highest rank in Your Year, after Duels", function()
        local ns = start(0)
        reach(2)
        reach(3)
        Stubs.state.pvpRank.season = 2
        reach(0)
        reach(1)
        ns.Store:Append("DUEL", { name = "Kangal Mooran", won = true })
        local built, ids = card(ns)
        T.eq(built.title, "PvP rank")
        T.eq(built.big, "3")
        T.eq(built.caption, "Sergeant")
        T.same(built.lines, { "Reached Saturday, October 3, 2026, in season 1" })
        T.eq(ids.pvprank, ids.duels + 1)
    end)

    it("read in German", function()
        local ns = start(1, 1, { locale = "deDE" })
        reach(3)
        T.same(entries(ns), { "PvP-Rang 3 erreicht: Waffenträger" })
        local built = card(ns)
        T.eq(built.title, "PvP-Rang")
        T.eq(built.caption, "Waffenträger")
        T.same(built.lines, { "Erreicht am Samstag, 3. Oktober 2026, in Saison 1" })
    end)

    it("trace each look in developer mode", function()
        local accountDB = { schema = 1, log = {}, characters = {}, settings = {
            devMode = true } }
        local ns = start(1, 1, { accountDB = accountDB, only = "PvPRank" })
        reach(2)
        reach(1)
        Stubs.state.pvpRank.season = 2
        look()
        _G.C_MajorFactions.GetMajorFactionProgressionInfo = function() return { renownLevel = Stubs.SECRET } end
        look()
        _G.C_MajorFactions = nil
        look()
        local traced = {}
        for i, line in ipairs(ns.Trace:GetLines()) do traced[i] = line:gsub("^%S+ %S+ ", "") end
        T.same(traced, {
            "PvPRank enable+PLAYER_ENTERING_WORLD: rank=1 season=1 -> first look",
            "PvPRank MAJOR_FACTION_RENOWN_LEVEL_CHANGED+PLAYER_PVP_RANK_CHANGED: rank=2 season=1 -> recorded 2",
            "PvPRank MAJOR_FACTION_RENOWN_LEVEL_CHANGED+PLAYER_PVP_RANK_CHANGED: rank=1 season=1 -> unchanged",
            "PvPRank PLAYER_ENTERING_WORLD: rank=1 season=2 -> new season",
            "PvPRank PLAYER_ENTERING_WORLD: rank=secret season=2 -> unreadable",
            "PvPRank PLAYER_ENTERING_WORLD: rank=missing season=2 -> unreadable",
        })
    end)
end)
