local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

-- Logs in with the hearthstone bound to `home` and lets the login settle.
local function start(home, opts)
    local ns = Stubs.LoadAddon(opts)
    Stubs.SetBindLocation(home)
    Stubs.Login()
    Stubs.Advance(1)
    return ns
end

-- The character talks to an innkeeper and binds the hearthstone there.
local function bind(home)
    Stubs.Fire("CONFIRM_BINDER", home)
    Stubs.Advance(1)
    Stubs.SetBindLocation(home)
    Stubs.Fire("HEARTHSTONE_BOUND")
    Stubs.Advance(1)
end

local function entries(ns)
    local texts = {}
    for _, record in ipairs(ns.Store:GetRecordsOfType("HOME")) do texts[#texts + 1] = ns.RecordTypes:Render(record) end
    return texts
end

describe("home", function()
    it("take the home the character already has silently, then record each new inn", function()
        local ns = start("Camp Narache")
        T.same(entries(ns), {}, "bound before Wayscribe")
        bind("Bloodhoof Village")
        T.same(entries(ns), { "Hearthstone bound to Bloodhoof Village" })
        bind("Bloodhoof Village")
        bind("Thunder Bluff")
        T.same(entries(ns), { "Hearthstone bound to Bloodhoof Village", "Hearthstone bound to Thunder Bluff" })
        T.eq(ns.RecordTypes:Get("HOME").category, "travel")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("take a home changed between sessions silently at login, also when the client's language changed", function()
        start("Camp Narache")
        Stubs.SetBindLocation("Bloodhoof Village") -- bound while Wayscribe was off
        local ns = Stubs.Relog()
        Stubs.Advance(1)
        T.same(entries(ns), {})
        Stubs.SetBindLocation("Bluthufdorf") -- the client now runs in German
        ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        T.same(entries(ns), {})
        bind("Donnerfels")
        T.same(entries(ns), { "Hearthstone bound to Donnerfels" })
    end)

    it("catch a missed bind event at the next look during play", function()
        local ns = start("Camp Narache")
        Stubs.SetBindLocation("Bloodhoof Village") -- HEARTHSTONE_BOUND never came
        Stubs.Advance(60)
        T.same(entries(ns), {})
        Stubs.Fire("PLAYER_ENTERING_WORLD", false, false) -- zoning into a dungeon
        Stubs.Advance(1)
        T.same(entries(ns), { "Hearthstone bound to Bloodhoof Village" })
        local today = ns.Time.DayKey(Stubs.Now())
        T.eq(#ns.Store:GetRecordsOfType("HOME", today, today), 1)
    end)

    it("read in German", function()
        local ns = start("Camp Narache", { locale = "deDE" })
        bind("Bluthufdorf")
        T.same(entries(ns), { "Ruhestein an Bluthufdorf gebunden" })
    end)

    it("write nothing and log no error when the API is missing, errors or is secret", function()
        local ns = Stubs.LoadAddon()
        Stubs.Login()
        Stubs.Advance(1)
        Stubs.Fire("HEARTHSTONE_BOUND")
        Stubs.Advance(1)
        _G.GetBindLocation = function() error("no inn") end
        Stubs.Fire("HEARTHSTONE_BOUND")
        Stubs.Advance(1)
        _G.GetBindLocation = function() return Stubs.SECRET end
        Stubs.Fire("HEARTHSTONE_BOUND")
        Stubs.Advance(1)
        _G.GetBindLocation = function() return "" end
        Stubs.Fire("HEARTHSTONE_BOUND")
        Stubs.Advance(1)
        T.same(entries(ns), {})
        T.eq(#ns.Log:GetEntries(), 0)
        bind("Camp Narache")
        bind("Bloodhoof Village")
        T.same(entries(ns), { "Hearthstone bound to Bloodhoof Village" }, "the first readable home is the first look")
    end)

    it("stop listening when switched off, and find the move at the next look once switched on", function()
        local ns = start("Camp Narache")
        ns.Trackers:SetWanted("Home", false)
        bind("Bloodhoof Village")
        T.same(entries(ns), {})
        ns.Trackers:SetWanted("Home", true)
        Stubs.Advance(1)
        T.same(entries(ns), { "Hearthstone bound to Bloodhoof Village" })
    end)

    it("repeat nothing after a relog, or when the journal comes back without the tracker's state", function()
        start("Camp Narache")
        bind("Bloodhoof Village")
        local ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        T.same(entries(ns), { "Hearthstone bound to Bloodhoof Village" })
        ns.Store:SetState("home", nil)
        ns = Stubs.Relog()
        Stubs.Advance(1)
        bind("Bloodhoof Village")
        T.same(entries(ns), { "Hearthstone bound to Bloodhoof Village" })
    end)

    it("repeat nothing after a backup is restored", function()
        local ns = start("Camp Narache")
        bind("Bloodhoof Village")
        local text
        ns.Backup:Make({}, function(result) text = result end)
        T.truthy(ns.Schema:ResetCharacter())
        ns = Stubs.Relog(nil, true)
        local found
        ns.Backup:Read(text, function(result) found = result end)
        T.truthy(ns.Backup:Restore(found))
        ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        bind("Bloodhoof Village")
        T.same(entries(ns), { "Hearthstone bound to Bloodhoof Village" })
    end)

    it("trace each look in developer mode", function()
        local accountDB = { schema = 1, log = {}, characters = {}, settings = { trackers = { FirstVisits = false,
            Gold = false, Reputation = false, Gear = false, LegacyChallenges = false, Guild = false,
            Collections = false, PvPRank = false }, devMode = true } }
        start("Camp Narache", { accountDB = accountDB })
        local ns = Stubs.ns
        bind("Bloodhoof Village")
        _G.GetBindLocation = function() return Stubs.SECRET end
        Stubs.Fire("HEARTHSTONE_BOUND")
        Stubs.Advance(1)
        local traced = {}
        for i, line in ipairs(ns.Trace:GetLines()) do traced[i] = line:gsub("^%S+ %S+ ", "") end
        T.same(traced, {
            'Home enable+PLAYER_ENTERING_WORLD: bind="Camp Narache" -> first look',
            'Home CONFIRM_BINDER: bind="Camp Narache" -> unchanged',
            'Home HEARTHSTONE_BOUND: bind="Bloodhoof Village" -> moved',
            "Home HEARTHSTONE_BOUND: bind=secret -> unreadable",
        })
        T.same(entries(ns), { "Hearthstone bound to Bloodhoof Village" })
    end)
end)
