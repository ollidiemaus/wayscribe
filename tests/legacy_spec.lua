local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local BETA, NOVICE, BARRENS, MULGORE, DELVER = 64283, 61499, 100, 101, 102

-- What a level 10 Tauren reads: the account's beta challenge, a challenge it earned before Wayscribe,
-- and three still to do, one of them account-wide.
local function challenges()
    return {
        { id = BETA, name = "Played in the WoW: Forever Beta", category = 15596, done = true, account = true,
            date = { year = 2026, month = 9, day = 25 } },
        { id = NOVICE, name = "Novice Warrior", category = 15597, account = true },
        { id = BARRENS, name = "Into the Barrens", category = 15597, done = true,
            date = { year = 2026, month = 9, day = 28 } },
        { id = MULGORE, name = "Hero of Mulgore", category = 15597 },
        { id = DELVER, name = "Deep Delver", category = 15598 },
    }
end

local function challenge(id)
    for _, row in ipairs(Stubs.state.challenges) do
        if row.id == id then return row end
    end
end

-- Logs in with `list` (the default unless false) and lets the first look happen.
local function start(list, opts)
    local ns = Stubs.LoadAddon(opts)
    if list ~= false then Stubs.SetChallenges(list or challenges()) end
    Stubs.Login()
    Stubs.Advance(1)
    return ns
end

local function earn(id, alreadyEarned)
    Stubs.EarnChallenge(id, alreadyEarned)
    Stubs.Advance(1)
end

local function look()
    Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
    Stubs.Advance(1)
end

-- The entries as they read, "*" before a first, "~" before a back-filled one.
local function entries(ns)
    local texts = {}
    for _, record in ipairs(ns.Store:GetRecordsOfType("LEGACY_CHALLENGE")) do
        texts[#texts + 1] = (record.bf and "~" or "") .. (record.first and "*" or "") .. ns.RecordTypes:Render(record)
    end
    return texts
end

local function card(ns)
    local cards, ids, found = ns.YearCards:Build(2026), {}, nil
    for i, built in ipairs(cards) do
        ids[built.id] = i
        if built.id == "legacy" then found = built end
    end
    return found, ids
end

local function settle(ns)
    Stubs.Fire("PLAYER_LOGOUT")
    return ns
end

describe("legacy challenges", function()
    it("back-fill what this character completed before, on the game's date and without a time", function()
        local ns = start()
        T.same(entries(ns), { "~*Completed a Legacy Challenge: Into the Barrens" },
            "the account's beta challenge is not this character's")
        local record = ns.Store:GetRecordsOfType("LEGACY_CHALLENGE")[1]
        T.eq(ns.Time.DayKey(record.ts), 20260928)
        local page = ns.DayView.Build(20260928, function() return true end)
        T.eq(#page.entries, 1)
        T.eq(page.entries[1].time, nil, "a back-filled entry only knows its day")
        T.eq(ns.RecordTypes:Get("LEGACY_CHALLENGE").category, "progress")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("take everything silently at a level 1 character's first look", function()
        local ns = start(nil, { level = 1 })
        T.same(entries(ns), {}, "a brand-new character has earned nothing")
        earn(MULGORE)
        T.same(entries(ns), { "*Completed a Legacy Challenge: Hero of Mulgore" })
    end)

    it("record a challenge as it is earned, an account-wide one too", function()
        local ns = start()
        earn(MULGORE)
        earn(NOVICE, true)
        T.same(entries(ns), { "~*Completed a Legacy Challenge: Into the Barrens",
            "*Completed a Legacy Challenge: Hero of Mulgore", "*Completed a Legacy Challenge: Novice Warrior" })
        local today = ns.Time.DayKey(Stubs.Now())
        local page = ns.DayView.Build(today, function() return true end)
        T.eq(#page.entries, 2)
        T.truthy(page.entries[1].time, "earned during play has its time")
    end)

    it("record one entry per challenge, ever", function()
        local ns = start()
        earn(MULGORE)
        Stubs.Fire("ACHIEVEMENT_EARNED", MULGORE)
        Stubs.Advance(1)
        earn(BARRENS)
        T.same(entries(ns), { "~*Completed a Legacy Challenge: Into the Barrens",
            "*Completed a Legacy Challenge: Hero of Mulgore" })
    end)

    it("make no entry for an earned ID that isn't among the challenges", function()
        local ns = start()
        Stubs.Fire("ACHIEVEMENT_EARNED", 5000) -- not in any category: a guild achievement, say
        Stubs.Advance(1)
        T.same(entries(ns), { "~*Completed a Legacy Challenge: Into the Barrens" })
        earn(MULGORE)
        T.same(entries(ns), { "~*Completed a Legacy Challenge: Into the Barrens",
            "*Completed a Legacy Challenge: Hero of Mulgore" }, "nothing was kept for the next look")
    end)

    it("record an earned challenge whose row can't be read, with its name read by ID", function()
        local ns = start()
        local read = _G.GetAchievementInfo
        _G.GetAchievementInfo = function(categoryOrID, index)
            if index and read(categoryOrID, index) == MULGORE then return nil end
            return read(categoryOrID, index)
        end
        earn(MULGORE)
        T.same(entries(ns), { "~*Completed a Legacy Challenge: Into the Barrens",
            "*Completed a Legacy Challenge: Hero of Mulgore" })
    end)

    it("make no entry for a challenge another character of the account earned", function()
        start()
        Stubs.Fire("PLAYER_LOGOUT")
        -- Played on another character: an account-wide challenge, and one Forever says it earned.
        challenge(NOVICE).done, challenge(NOVICE).date = true, { year = 2026, month = 10, day = 3 }
        challenge(DELVER).done, challenge(DELVER).byMe = true, false
        challenge(DELVER).date = { year = 2026, month = 10, day = 3 }
        local ns = Stubs.Relog()
        Stubs.Advance(1)
        T.same(entries(ns), { "~*Completed a Legacy Challenge: Into the Barrens" })
    end)

    it("catch a missed event at the next look, and record a change found at login on the login day", function()
        local ns = start()
        local row = challenge(MULGORE)
        row.done, row.date = true, { year = 2026, month = 10, day = 3 } -- ACHIEVEMENT_EARNED never came
        earn(DELVER)
        T.same(entries(ns), { "~*Completed a Legacy Challenge: Into the Barrens",
            "*Completed a Legacy Challenge: Hero of Mulgore", "*Completed a Legacy Challenge: Deep Delver" })
        settle(ns)
        row = challenge(NOVICE)
        row.account = false
        row.done, row.date = true, { year = 2026, month = 10, day = 3 } -- earned while Wayscribe was off
        Stubs.SetTime(os.time({ year = 2026, month = 10, day = 5, hour = 12 }))
        ns = Stubs.Relog()
        Stubs.Advance(1)
        local records = ns.Store:GetRecordsOfType("LEGACY_CHALLENGE", 20261005, 20261005)
        T.eq(#records, 1, "on the login day")
        T.eq(records[1].data.challenge, NOVICE)
        T.falsy(records[1].bf)
    end)

    it("keep the challenge's name from when the entry was written", function()
        local ns = start()
        earn(MULGORE)
        challenge(MULGORE).name = "Something else"
        T.same(entries(ns)[2], "*Completed a Legacy Challenge: Hero of Mulgore")
    end)

    it("give Your Year a card after Reputation: how many, and the latest", function()
        local ns = start()
        Stubs.SetTime(os.time({ year = 2026, month = 11, day = 7, hour = 12 }))
        earn(MULGORE)
        ns.Store:Append("REPUTATION", { faction = 81, standing = 6, name = "Thunder Bluff" })
        local built, ids = card(ns)
        T.eq(built.title, "Legacy Challenges")
        T.eq(built.big, "2")
        T.eq(built.caption, "challenges completed")
        T.same(built.lines, { "Latest: Hero of Mulgore, Saturday, November 7, 2026" })
        T.eq(ids.legacy, ids.reputation + 1, "after Reputation")
        ns.Store:Rebuild()
        T.same(card(ns).lines, built.lines, "the card comes back from the entries")
    end)

    it("give one challenge a card in the singular, and none to a year without any", function()
        local ns = start()
        local built = card(ns)
        T.eq(built.caption, "challenge completed")
        T.same(built.lines, { "Latest: Into the Barrens, Monday, September 28, 2026" })
        ns = start(nil, { level = 1 })
        T.eq(card(ns), nil)
    end)

    it("read in German", function()
        local ns = start(nil, { locale = "deDE" })
        earn(MULGORE)
        T.same(entries(ns), { "~*Vermächtnis-Herausforderung abgeschlossen: Into the Barrens",
            "*Vermächtnis-Herausforderung abgeschlossen: Hero of Mulgore" })
        local built = card(ns)
        T.eq(built.title, "Vermächtnis-Herausforderungen")
        T.eq(built.caption, "Herausforderungen abgeschlossen")
        T.same(built.lines, { "Zuletzt: Hero of Mulgore, Samstag, 3. Oktober 2026" })
    end)

    it("write nothing and log no error when the API is missing, errors or is secret", function()
        local ns = start(false)
        Stubs.Fire("ACHIEVEMENT_EARNED", MULGORE)
        look()
        Stubs.SetChallenges(challenges())
        _G.GetCategoryList = function() error("no categories") end
        earn(MULGORE)
        _G.GetCategoryList = function() return Stubs.SECRET end
        look()
        Stubs.SetChallenges(Stubs.state.challenges)
        _G.GetAchievementInfo = function() error("no challenge") end
        look()
        _G.GetAchievementInfo = function() return Stubs.SECRET end
        earn(DELVER)
        T.same(entries(ns), {})
        T.eq(#ns.Log:GetEntries(), 0)
        Stubs.SetChallenges(Stubs.state.challenges)
        look()
        T.same(entries(ns), { "~*Completed a Legacy Challenge: Into the Barrens",
            "*Completed a Legacy Challenge: Hero of Mulgore", "*Completed a Legacy Challenge: Deep Delver" },
            "the first readable look back-fills, and keeps what was earned meanwhile")
    end)

    it("stop listening when switched off", function()
        local ns = start()
        ns.Trackers:SetWanted("LegacyChallenges", false)
        earn(MULGORE)
        T.same(entries(ns), { "~*Completed a Legacy Challenge: Into the Barrens" })
        ns.Trackers:SetWanted("LegacyChallenges", true)
        Stubs.Advance(1)
        T.same(entries(ns), { "~*Completed a Legacy Challenge: Into the Barrens",
            "*Completed a Legacy Challenge: Hero of Mulgore" }, "found at the next look")
    end)

    it("repeat nothing after a reload, or when the journal comes back without the tracker's state", function()
        start()
        earn(MULGORE)
        local ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        ns.Store:SetState("legacy", nil)
        ns = Stubs.Relog()
        Stubs.Advance(1)
        T.same(entries(ns), { "~*Completed a Legacy Challenge: Into the Barrens",
            "*Completed a Legacy Challenge: Hero of Mulgore" }, "the journal knows them")
    end)

    it("repeat nothing after a backup is restored", function()
        local ns = start()
        earn(MULGORE)
        local text
        ns.Backup:Make({}, function(result) text = result end)
        T.truthy(ns.Schema:ResetCharacter())
        ns = Stubs.Relog(nil, true)
        local found
        ns.Backup:Read(text, function(result) found = result end)
        T.truthy(ns.Backup:Restore(found))
        ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        T.same(entries(ns), { "~*Completed a Legacy Challenge: Into the Barrens",
            "*Completed a Legacy Challenge: Hero of Mulgore" })
    end)

    it("trace each look in developer mode", function()
        local accountDB = { schema = 1, log = {}, characters = {}, settings = {
            devMode = true } }
        local ns = start(nil, { accountDB = accountDB, only = "LegacyChallenges" })
        earn(MULGORE)
        challenge(NOVICE).done = true
        challenge(DELVER).done = true
        look()
        Stubs.Fire("ACHIEVEMENT_EARNED", MULGORE)
        Stubs.Advance(1)
        _G.GetCategoryList = nil
        look()
        local traced = {}
        for i, line in ipairs(ns.Trace:GetLines()) do traced[i] = line:gsub("^%S+ %S+ ", "") end
        T.same(traced, {
            'LegacyChallenges enable+PLAYER_ENTERING_WORLD: challenges=5 completed=2 new="100 64283:account" -> back-filled 1',
            'LegacyChallenges ACHIEVEMENT_EARNED: challenges=5 completed=3 earned="101" new="101" -> recorded 1',
            'LegacyChallenges PLAYER_ENTERING_WORLD: challenges=5 completed=5 new="102 61499:account" -> recorded 1',
            'LegacyChallenges ACHIEVEMENT_EARNED: challenges=5 completed=5 earned="101" -> unchanged',
            "LegacyChallenges PLAYER_ENTERING_WORLD: challenges=missing -> no challenges",
        })
    end)
end)
