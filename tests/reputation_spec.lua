local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local HATED, HOSTILE, UNFRIENDLY, NEUTRAL, FRIENDLY, HONORED, REVERED, EXALTED = 1, 2, 3, 4, 5, 6, 7, 8
local BLUFF, DARKSPEAR, BOOTY_BAY, CENARION = 81, 530, 21, 609

-- A Tauren's list, as the beta showed it: factions under a header, plus Booty Bay further down.
local function factions()
    return {
        { factionID = 1169, name = "Horde", isHeader = true },
        { factionID = BLUFF, name = "Thunder Bluff", reaction = FRIENDLY },
        { factionID = DARKSPEAR, name = "Darkspear Trolls", reaction = NEUTRAL },
        { factionID = 1118, name = "Classic", isHeader = true },
        { factionID = BOOTY_BAY, name = "Booty Bay", reaction = NEUTRAL },
    }
end

-- Logs in with `list` (the default list unless false) and lets the first look happen.
local function start(list, opts)
    local ns = Stubs.LoadAddon(opts)
    if list ~= false then Stubs.SetFactions(list or factions()) end
    Stubs.Login()
    Stubs.Advance(1)
    return ns
end

local function reach(factionID, reaction)
    Stubs.SetReaction(factionID, reaction)
    Stubs.Fire("UPDATE_FACTION")
    Stubs.Advance(1)
end

-- The entries as they read.
local function entries(ns)
    local texts = {}
    for _, record in ipairs(ns.Store:GetRecordsOfType("REPUTATION")) do
        texts[#texts + 1] = ns.RecordTypes:Render(record)
    end
    return texts
end

local function card(ns)
    local cards, ids, found = ns.YearCards:Build(2026), {}, nil
    for i, built in ipairs(cards) do
        ids[built.id] = i
        if built.id == "reputation" then found = built end
    end
    return found, ids
end

describe("reputation", function()
    it("keep the first look silent, then record each new standing up with a faction", function()
        local ns = start()
        T.same(entries(ns), {}, "the standings at the first look are older than the tracker")
        reach(BLUFF, HONORED)
        reach(DARKSPEAR, FRIENDLY)
        T.same(entries(ns), { "Reached Honored with Thunder Bluff", "Reached Friendly with Darkspear Trolls" })
        T.eq(ns.Store:GetRecordsOfType("REPUTATION")[1].type, "REPUTATION")
        T.eq(ns.RecordTypes:Get("REPUTATION").category, "progress")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("record the first fall to Hostile and to Hated, not to Unfriendly, and nothing when climbing back or falling again", function()
        local ns = start()
        reach(DARKSPEAR, UNFRIENDLY)
        reach(BOOTY_BAY, HOSTILE)
        reach(BOOTY_BAY, NEUTRAL)
        reach(BOOTY_BAY, HATED)
        reach(BLUFF, HONORED)
        reach(BLUFF, NEUTRAL)
        reach(BLUFF, HONORED)
        reach(BOOTY_BAY, HOSTILE)
        T.same(entries(ns), { "Fell to Hostile with Booty Bay", "Fell to Hated with Booty Bay",
            "Reached Honored with Thunder Bluff" })
    end)

    it("never record a standing the faction held at the first look, after falling back from it", function()
        local list = factions()
        list[2].reaction = EXALTED
        local ns = start(list)
        reach(BLUFF, REVERED)
        reach(BLUFF, EXALTED)
        T.same(entries(ns), {})
    end)

    it("record no entry for meeting a faction, only for its next standings", function()
        local ns = start()
        local list = factions()
        list[#list + 1] = { factionID = CENARION, name = "Cenarion Circle", reaction = FRIENDLY }
        Stubs.SetFactions(list)
        Stubs.Fire("UPDATE_FACTION")
        Stubs.Advance(1)
        T.same(entries(ns), {})
        reach(CENARION, HONORED)
        T.same(entries(ns), { "Reached Honored with Cenarion Circle" })
    end)

    it("catch a missed event at the next look, with every standing passed", function()
        local ns = start()
        Stubs.SetReaction(DARKSPEAR, REVERED) -- UPDATE_FACTION never came
        Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
        Stubs.Advance(1)
        T.same(entries(ns), { "Reached Friendly with Darkspear Trolls", "Reached Honored with Darkspear Trolls",
            "Reached Revered with Darkspear Trolls" })
    end)

    it("look once for a burst of updates", function()
        local ns = start()
        Stubs.SetReaction(BLUFF, HONORED)
        for _ = 1, 5 do Stubs.Fire("UPDATE_FACTION") end
        Stubs.SetReaction(BLUFF, REVERED)
        Stubs.Fire("UPDATE_FACTION")
        Stubs.Advance(1)
        T.same(entries(ns), { "Reached Honored with Thunder Bluff", "Reached Revered with Thunder Bluff" })
    end)

    it("leave out PvP Rank Points and the Legacy Track", function()
        local list = factions()
        list[#list + 1] = { factionID = 2800, name = "PvP Rank Points", reaction = NEUTRAL }
        list[#list + 1] = { factionID = 2802, name = "Legacy Track", reaction = NEUTRAL }
        local ns = start(list)
        reach(2800, EXALTED)
        reach(2802, FRIENDLY)
        T.same(entries(ns), {})
    end)

    it("read the factions under a collapsed header by ID", function()
        local ns = start()
        local list = factions()
        list[2].reaction = HONORED
        list[2].hidden, list[3].hidden = true, true
        Stubs.SetFactions(list)
        Stubs.Fire("UPDATE_FACTION")
        Stubs.Advance(1)
        T.same(entries(ns), { "Reached Honored with Thunder Bluff" })
    end)

    it("name the standing the way the client does, in the female form for a female character", function()
        local ns = start(nil, { sex = 3 })
        _G.FACTION_STANDING_LABEL6 = "Honored"
        _G.FACTION_STANDING_LABEL6_FEMALE = "Honored (f)"
        local ok, err = pcall(function()
            reach(BLUFF, HONORED)
            T.same(entries(ns), { "Reached Honored (f) with Thunder Bluff" })
            Stubs.state.player.sex = 2
            T.same(entries(ns), { "Reached Honored with Thunder Bluff" }, "the label is read at display time")
        end)
        _G.FACTION_STANDING_LABEL6, _G.FACTION_STANDING_LABEL6_FEMALE = nil, nil
        if not ok then error(err, 0) end
    end)

    it("keep the faction's name from when the entry was written", function()
        local ns = start()
        reach(BLUFF, HONORED)
        _G.C_Reputation = nil
        T.same(entries(ns), { "Reached Honored with Thunder Bluff" })
    end)

    it("give Your Year a reputation card after Quests", function()
        local list = factions()
        list[#list + 1] = { factionID = CENARION, name = "Cenarion Circle", reaction = NEUTRAL }
        local ns = start(list)
        reach(BLUFF, EXALTED)   -- Honored, Revered, Exalted
        reach(DARKSPEAR, HONORED) -- Friendly, Honored
        Stubs.SetTime(os.time({ year = 2026, month = 11, day = 2, hour = 12 }))
        reach(CENARION, HONORED) -- Friendly, Honored
        reach(BOOTY_BAY, HOSTILE)
        ns.Store:Count("quests", 26, 1)
        ns.Store:Count("travel", "ground", 1760)
        local built, ids = card(ns)
        T.eq(built.title, "Reputation")
        T.eq(built.big, "8")
        T.eq(built.caption, "new standings")
        T.same(built.lines, { "Exalted: Thunder Bluff", "Honored: Cenarion Circle and Darkspear Trolls",
            "Climbed most: Thunder Bluff (3 standings)" })
        T.eq(ids.reputation, ids.quests + 1, "after Quests")
        T.truthy(ids.reputation < ids.footsteps, "before Footsteps")
        ns.Store:Rebuild()
        T.same(card(ns).lines, built.lines, "the card comes back from the entries")
    end)

    it("make no card in a year without new standings", function()
        local ns = start()
        T.eq(card(ns), nil)
    end)

    it("read in German", function()
        local ns = start(nil, { locale = "deDE" })
        reach(BLUFF, HONORED)
        reach(BOOTY_BAY, HOSTILE)
        T.same(entries(ns), { "Wohlwollend bei Thunder Bluff erreicht", "Auf Feindselig bei Booty Bay gefallen" })
        local built = card(ns)
        T.eq(built.caption, "neue Rufstufen")
        T.same(built.lines, { "Wohlwollend: Thunder Bluff", "Am weitesten aufgestiegen: Thunder Bluff (1 Stufe)" })
    end)

    it("write nothing and log no error when the API is missing, errors or is secret", function()
        local ns = start(false)
        Stubs.Fire("UPDATE_FACTION")
        Stubs.Advance(1)
        Stubs.SetFactions(factions())
        _G.C_Reputation.GetNumFactions = function() error("no factions") end
        Stubs.Fire("UPDATE_FACTION")
        Stubs.Advance(1)
        _G.C_Reputation.GetNumFactions = function() return Stubs.SECRET end
        Stubs.Fire("UPDATE_FACTION")
        Stubs.Advance(1)
        Stubs.SetFactions(factions())
        Stubs.Fire("UPDATE_FACTION")
        Stubs.Advance(1)
        T.same(entries(ns), {}, "the first readable list is the first look")
        Stubs.SetReaction(BLUFF, Stubs.SECRET)
        _G.C_Reputation.GetFactionDataByID = function() error("no faction") end
        Stubs.Fire("UPDATE_FACTION")
        Stubs.Advance(1)
        _G.C_Reputation.GetFactionDataByIndex = function() error("no faction") end
        Stubs.Fire("UPDATE_FACTION")
        Stubs.Advance(1)
        T.same(entries(ns), {})
        Stubs.SetFactions(factions())
        reach(BLUFF, HONORED)
        T.same(entries(ns), { "Reached Honored with Thunder Bluff" }, "a secret reaction was skipped, not taken")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("stop listening when switched off", function()
        local ns = start()
        ns.Trackers:SetWanted("Reputation", false)
        reach(BLUFF, HONORED)
        T.same(entries(ns), {})
        ns.Trackers:SetWanted("Reputation", true)
        Stubs.Advance(1)
        T.same(entries(ns), { "Reached Honored with Thunder Bluff" }, "found at the next look")
    end)

    it("record a change found at login on the login day", function()
        start()
        Stubs.Fire("PLAYER_LOGOUT")
        Stubs.SetReaction(DARKSPEAR, FRIENDLY) -- earned while Wayscribe was off
        Stubs.SetTime(os.time({ year = 2026, month = 10, day = 5, hour = 12 }))
        local ns = Stubs.Relog()
        Stubs.Advance(1)
        T.same(entries(ns), { "Reached Friendly with Darkspear Trolls" })
        local today = ns.Time.DayKey(Stubs.Now())
        T.eq(#ns.Store:GetRecordsOfType("REPUTATION", today, today), 1, "on the login day")
    end)

    it("repeat nothing after a reload, or when the journal comes back without the tracker's state", function()
        start()
        reach(BLUFF, HONORED)
        local ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        T.same(entries(ns), { "Reached Honored with Thunder Bluff" })
        ns.Store:SetState("reputation", nil)
        ns = Stubs.Relog()
        Stubs.Advance(1)
        reach(BLUFF, NEUTRAL)
        reach(BLUFF, HONORED)
        T.same(entries(ns), { "Reached Honored with Thunder Bluff" }, "the journal's own firsts know it")
    end)

    it("repeat nothing after a backup is restored", function()
        local ns = start()
        reach(BLUFF, HONORED)
        local text
        ns.Backup:Make({}, function(result) text = result end)
        T.truthy(ns.Schema:ResetCharacter())
        ns = Stubs.Relog(nil, true)
        local found
        ns.Backup:Read(text, function(result) found = result end)
        T.truthy(ns.Backup:Restore(found))
        ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        reach(BLUFF, NEUTRAL)
        reach(BLUFF, HONORED)
        T.same(entries(ns), { "Reached Honored with Thunder Bluff" })
    end)

    it("trace each look in developer mode", function()
        local accountDB = { schema = 1, log = {}, characters = {},
            settings = { trackers = { FirstVisits = false, Gold = false, Gear = false, LegacyChallenges = false }, devMode = true } }
        local ns = start(nil, { accountDB = accountDB })
        reach(BLUFF, HONORED)
        Stubs.Fire("UPDATE_FACTION")
        Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
        Stubs.Advance(1)
        _G.C_Reputation = nil
        Stubs.Fire("UPDATE_FACTION")
        Stubs.Advance(1)
        local traced = {}
        for i, line in ipairs(ns.Trace:GetLines()) do traced[i] = line:gsub("^%S+ %S+ ", "") end
        T.same(traced, {
            "Reputation enable+PLAYER_ENTERING_WORLD: rows=5 factions=3 -> first look",
            'Reputation UPDATE_FACTION: rows=5 factions=3 changed="81:5>6" -> recorded 1',
            "Reputation UPDATE_FACTION+PLAYER_ENTERING_WORLD: rows=5 factions=3 -> unchanged",
            "Reputation UPDATE_FACTION: rows=missing factions=0 -> no factions",
        })
    end)
end)
