local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

-- Logs in in `guild` (nil: not in a guild) and lets the login settle.
local function start(guild, opts)
    local ns = Stubs.LoadAddon(opts)
    Stubs.SetGuild(guild ~= nil, guild)
    Stubs.Login()
    Stubs.Advance(1)
    return ns
end

-- The guild changes and the game says so.
local function change(inGuild, name, rank)
    Stubs.SetGuild(inGuild, name, rank)
    Stubs.Fire("PLAYER_GUILD_UPDATE", "player")
    Stubs.Advance(1)
end

local function entries(ns)
    local texts = {}
    for _, record in ipairs(ns.Store:GetRecordsOfType("GUILD")) do texts[#texts + 1] = ns.RecordTypes:Render(record) end
    return texts
end

describe("guild", function()
    it("take the guild the character is already in silently, then record leaving it and joining another", function()
        local ns = start("Red Hand")
        T.same(entries(ns), {}, "joined before Wayscribe")
        change(false, nil)
        T.same(entries(ns), { "Left the guild <Red Hand>" })
        change(true, "Bloodfang")
        T.same(entries(ns), { "Left the guild <Red Hand>", "Joined the guild <Bloodfang>" })
        T.eq(ns.RecordTypes:Get("GUILD").category, "adventure")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("take a missing name right after login for not loaded yet, not for leaving", function()
        start("Red Hand")
        Stubs.Fire("PLAYER_LOGOUT")
        Stubs.SetGuild(true, nil) -- the name hasn't loaded yet
        local ns = Stubs.Relog()
        Stubs.Advance(30)
        T.same(entries(ns), {})
        change(true, "Red Hand")
        T.same(entries(ns), {})
        change(true, nil)
        change(false, nil)
        T.same(entries(ns), { "Left the guild <Red Hand>" })
    end)

    it("look again while the name is missing, and find a change then", function()
        local ns = start("Red Hand")
        Stubs.SetGuild(true, nil)
        Stubs.Fire("PLAYER_GUILD_UPDATE", "player")
        Stubs.Advance(1)
        Stubs.state.guild.name = "Bloodfang" -- loaded without another event
        Stubs.Advance(4.75)
        T.same(entries(ns), {}, "the retry waits its own delay, not the look delay")
        Stubs.Advance(0.25)
        T.same(entries(ns), { "Left the guild <Red Hand>", "Joined the guild <Bloodfang>" })
    end)

    it("make no entry for a rank change, or for another unit's update", function()
        local ns = start("Red Hand")
        change(true, "Red Hand", "Officer")
        Stubs.SetGuild(false, nil)
        Stubs.Fire("PLAYER_GUILD_UPDATE", "party1")
        Stubs.Advance(1)
        T.same(entries(ns), {})
    end)

    it("record joining a first guild", function()
        local ns = start(nil)
        change(true, "Red Hand")
        T.same(entries(ns), { "Joined the guild <Red Hand>" })
    end)

    it("record a change found at login on the login day", function()
        start("Red Hand")
        Stubs.Fire("PLAYER_LOGOUT")
        Stubs.SetGuild(true, "Bloodfang") -- left and joined while Wayscribe was off
        Stubs.SetTime(os.time({ year = 2026, month = 10, day = 5, hour = 12 }))
        local ns = Stubs.Relog()
        Stubs.Advance(1)
        T.same(entries(ns), { "Left the guild <Red Hand>", "Joined the guild <Bloodfang>" })
        local today = ns.Time.DayKey(Stubs.Now())
        T.eq(#ns.Store:GetRecordsOfType("GUILD", today, today), 2, "on the login day")
    end)

    it("read in German", function()
        local ns = start("Red Hand", { locale = "deDE" })
        change(false, nil)
        change(true, "Blutfang")
        T.same(entries(ns), { "Die Gilde <Red Hand> verlassen", "Der Gilde <Blutfang> beigetreten" })
    end)

    it("write nothing and log no error when the APIs are missing, error or are secret", function()
        local ns = Stubs.LoadAddon()
        Stubs.Login()
        Stubs.Advance(1)
        Stubs.Fire("PLAYER_GUILD_UPDATE", "player")
        Stubs.Advance(1)
        _G.IsInGuild = function() error("no guild") end
        Stubs.Fire("PLAYER_GUILD_UPDATE", "player")
        Stubs.Advance(1)
        _G.IsInGuild = function() return Stubs.SECRET end
        Stubs.Fire("PLAYER_GUILD_UPDATE", "player")
        Stubs.Advance(1)
        _G.IsInGuild = function() return true end
        _G.GetGuildInfo = function() error("no info") end
        Stubs.Fire("PLAYER_GUILD_UPDATE", "player")
        Stubs.Advance(30)
        _G.GetGuildInfo = function() return Stubs.SECRET end
        Stubs.Fire("PLAYER_GUILD_UPDATE", Stubs.SECRET)
        Stubs.Advance(30)
        T.same(entries(ns), {})
        T.eq(#ns.Log:GetEntries(), 0)
        change(true, "Red Hand")
        change(false, nil)
        T.same(entries(ns), { "Left the guild <Red Hand>" }, "the first readable guild is the first look")
    end)

    it("stop listening when switched off", function()
        local ns = start("Red Hand")
        ns.Trackers:SetWanted("Guild", false)
        change(false, nil)
        T.same(entries(ns), {})
        ns.Trackers:SetWanted("Guild", true)
        Stubs.Advance(1)
        T.same(entries(ns), { "Left the guild <Red Hand>" }, "found at the next look")
    end)

    it("repeat nothing after a relog, or when the journal comes back without the tracker's state", function()
        start("Red Hand")
        change(false, nil)
        local ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        T.same(entries(ns), { "Left the guild <Red Hand>" })
        ns.Store:SetState("guild", nil)
        ns = Stubs.Relog()
        Stubs.Advance(1)
        T.same(entries(ns), { "Left the guild <Red Hand>" })
    end)

    it("repeat nothing after a backup is restored", function()
        local ns = start("Red Hand")
        change(true, "Bloodfang")
        local text
        ns.Backup:Make({}, function(result) text = result end)
        T.truthy(ns.Schema:ResetCharacter())
        ns = Stubs.Relog(nil, true)
        local found
        ns.Backup:Read(text, function(result) found = result end)
        T.truthy(ns.Backup:Restore(found))
        ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        change(true, "Bloodfang", "Officer")
        T.same(entries(ns), { "Left the guild <Red Hand>", "Joined the guild <Bloodfang>" })
    end)

    it("trace each look in developer mode", function()
        local accountDB = { schema = 1, log = {}, characters = {}, settings = { devMode = true } }
        start("Red Hand", { accountDB = accountDB, only = "Guild" })
        local ns = Stubs.ns
        change(true, nil)
        Stubs.Advance(5)
        change(true, "Red Hand", "Officer")
        change(false, nil)
        local traced = {}
        for i, line in ipairs(ns.Trace:GetLines()) do traced[i] = line:gsub("^%S+ %S+ ", "") end
        T.same(traced, {
            'Guild enable+PLAYER_ENTERING_WORLD: inGuild=true name="Red Hand" -> first look',
            "Guild PLAYER_GUILD_UPDATE: inGuild=true name=missing -> name missing",
            "Guild retry: inGuild=true name=missing -> name missing",
            'Guild retry+PLAYER_GUILD_UPDATE: inGuild=true name="Red Hand" -> unchanged',
            "Guild PLAYER_GUILD_UPDATE: inGuild=false -> left",
        })
    end)
end)
