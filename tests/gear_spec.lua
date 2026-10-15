local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local HEAD, SHIRT, CHEST, FINGER, TRINKET1, TRINKET2, MAIN_HAND, BAG = 1, 4, 5, 11, 13, 14, 16, 20

local ITEMS = {
    shirt = { id = 45, quality = 1, name = "Tauren Shirt" },
    robe = { id = 6125, quality = 1, name = "Brawler's Harness" },
    green = { id = 5000, quality = 2, name = "Gnoll Punisher" },
    wornRing = { id = 1000, quality = 3, name = "Ring of Precision" },
    wornEpic = { id = 1001, quality = 4, name = "Hide of the Wild" },
    sword = { id = 2000, quality = 3, name = "Thrash Blade" },
    helm = { id = 2001, quality = 3, name = "Crown of Tyranny" },
    trinket = { id = 3000, quality = 4, name = "Hand of Justice" },
    ironfoe = { id = 3001, quality = 4, name = "Ironfoe" },
    thunderfury = { id = 4000, quality = 5, name = "Thunderfury" },
}

local function item(key, quality)
    local def = ITEMS[key]
    return { id = def.id, quality = quality == nil and def.quality or quality or nil }
end

-- What a level 10 Tauren wears at the first look: a rare ring and an epic chest among the whites.
local function worn()
    return { [SHIRT] = item("shirt"), [CHEST] = item("wornEpic"), [FINGER] = item("wornRing") }
end

-- Logs in wearing `slots` (the default unless false) and lets the first look happen.
local function start(slots, opts)
    local ns = Stubs.LoadAddon(opts)
    for _, def in pairs(ITEMS) do Stubs.state.itemNames[def.id] = def.name end
    if slots ~= false then Stubs.SetEquipment(slots or worn()) end
    Stubs.Login()
    Stubs.Advance(1)
    return ns
end

local function equip(slot, key, quality)
    Stubs.Equip(slot, key and item(key, quality) or nil)
end

-- The entries as they read, "*" before a first.
local function entries(ns)
    local texts = {}
    for _, record in ipairs(ns.Store:GetRecordsOfType("GEAR")) do
        texts[#texts + 1] = (record.first and "*" or "") .. ns.RecordTypes:Render(record)
    end
    return texts
end

local function card(ns)
    local cards, ids, found = ns.YearCards:Build(2026), {}, nil
    for i, built in ipairs(cards) do
        ids[built.id] = i
        if built.id == "gear" then found = built end
    end
    return found, ids
end

describe("gear", function()
    it("keep the first look silent, then record the first rare and every epic as it is equipped", function()
        local ns = start()
        T.same(entries(ns), {}, "what is worn already is older than the tracker")
        equip(MAIN_HAND, "sword")
        equip(HEAD, "helm")
        equip(TRINKET1, "trinket")
        equip(MAIN_HAND, "ironfoe")
        T.same(entries(ns), { "*Equipped your first rare item: Thrash Blade",
            "*Equipped your first epic item: Hand of Justice", "Equipped an epic item: Ironfoe" })
        T.eq(ns.RecordTypes:Get("GEAR").category, "progress")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("record nothing for re-equipping an item, a second copy, or what was worn at the first look", function()
        local ns = start()
        equip(TRINKET1, "trinket")
        equip(TRINKET1, nil)
        equip(TRINKET1, "trinket")
        equip(TRINKET2, "trinket")
        equip(CHEST, "robe")
        equip(CHEST, "wornEpic")
        equip(FINGER, nil)
        equip(FINGER, "wornRing")
        T.same(entries(ns), { "*Equipped your first epic item: Hand of Justice" })
    end)

    it("record nothing below rare, and a legendary as better than epic", function()
        local ns = start()
        equip(MAIN_HAND, "green")
        equip(MAIN_HAND, "thunderfury")
        equip(TRINKET1, "trinket")
        T.same(entries(ns), { "*Equipped a legendary item: Thunderfury", "Equipped an epic item: Hand of Justice" })
    end)

    it("ignore the bag slots", function()
        local ns = start()
        Stubs.state.equipment[BAG] = item("trinket")
        Stubs.Fire("PLAYER_EQUIPMENT_CHANGED", BAG, true)
        T.same(entries(ns), {})
    end)

    it("catch a missed event at the next look", function()
        local ns = start()
        Stubs.state.equipment[TRINKET1] = item("trinket") -- PLAYER_EQUIPMENT_CHANGED never came
        Stubs.state.equipment[MAIN_HAND] = item("sword")
        Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
        Stubs.Advance(1)
        T.same(entries(ns), { "*Equipped your first epic item: Hand of Justice",
            "*Equipped your first rare item: Thrash Blade" })
    end)

    it("leave an item whose quality isn't known yet for the next look", function()
        local ns = start()
        equip(TRINKET1, "trinket", false)
        T.same(entries(ns), {})
        Stubs.state.equipment[TRINKET1] = item("trinket")
        Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
        Stubs.Advance(1)
        T.same(entries(ns), { "*Equipped your first epic item: Hand of Justice" })
    end)

    it("read an item whose quality wasn't loaded again a second later", function()
        local ns = start()
        equip(TRINKET1, "trinket", false)
        Stubs.state.equipment[TRINKET1] = item("trinket") -- the client loads it
        Stubs.Advance(1)
        T.same(entries(ns), { "*Equipped your first epic item: Hand of Justice" })
    end)

    it("take nothing as the first look while the inventory reads empty", function()
        local ns = start({})
        Stubs.SetEquipment(worn())
        Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
        Stubs.Advance(1)
        equip(CHEST, "robe")
        equip(CHEST, "wornEpic")
        T.same(entries(ns), {}, "the first look that read an item was silent")
    end)

    it("keep the item's name from when the entry was written", function()
        local ns = start()
        equip(TRINKET1, "trinket")
        Stubs.state.itemNames = {}
        T.same(entries(ns), { "*Equipped your first epic item: Hand of Justice" })
    end)

    it("give Your Year a gear card after Bosses", function()
        local ns = start()
        equip(MAIN_HAND, "sword")
        Stubs.SetTime(os.time({ year = 2026, month = 11, day = 7, hour = 12 }))
        equip(TRINKET1, "trinket")
        equip(MAIN_HAND, "ironfoe")
        ns.Store:Append("BOSS_KILLED", { encounterID = 227, name = "Lord Roccor" })
        ns.Store:Count("quests", 26, 1)
        local built, ids = card(ns)
        T.eq(built.title, "Notable gear")
        T.eq(built.big, "2")
        T.eq(built.caption, "epic items worn")
        T.same(built.lines, { "First rare: Thrash Blade, Saturday, October 3, 2026",
            "First epic: Hand of Justice, Saturday, November 7, 2026" })
        T.eq(ids.gear, ids.bosses + 1, "after Bosses")
        ns.Store:Rebuild()
        T.same(card(ns).lines, built.lines, "the card comes back from the entries")
    end)

    it("give a year with only the first rare a card without a number", function()
        local ns = start()
        equip(MAIN_HAND, "sword")
        local built = card(ns)
        T.eq(built.big, nil)
        T.same(built.lines, { "First rare: Thrash Blade, Saturday, October 3, 2026" })
    end)

    it("make no card in a year without notable gear", function()
        local ns = start()
        T.eq(card(ns), nil)
    end)

    it("read in German", function()
        local ns = start(nil, { locale = "deDE" })
        equip(MAIN_HAND, "sword")
        equip(TRINKET1, "trinket")
        equip(TRINKET2, "ironfoe")
        T.same(entries(ns), { "*Deinen ersten seltenen Gegenstand angelegt: Thrash Blade",
            "*Deinen ersten epischen Gegenstand angelegt: Hand of Justice", "Epischen Gegenstand angelegt: Ironfoe" })
        local built = card(ns)
        T.eq(built.caption, "epische Gegenstände getragen")
        T.same(built.lines, { "Erster seltener: Thrash Blade, Samstag, 3. Oktober 2026",
            "Erster epischer: Hand of Justice, Samstag, 3. Oktober 2026" })
    end)

    it("write nothing and log no error when the API is missing, errors or is secret", function()
        local ns = start(false)
        Stubs.Fire("PLAYER_EQUIPMENT_CHANGED", TRINKET1, true)
        Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
        Stubs.Advance(1)
        Stubs.SetEquipment(worn())
        _G.GetInventoryItemID = function() error("no items") end
        equip(TRINKET1, "trinket")
        Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
        Stubs.Advance(1)
        _G.GetInventoryItemID = function() return Stubs.SECRET end
        Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
        Stubs.Advance(1)
        T.same(entries(ns), {})
        Stubs.SetEquipment(Stubs.state.equipment)
        Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
        Stubs.Advance(1)
        T.same(entries(ns), {}, "the first readable look is silent")
        _G.GetInventoryItemQuality = function() return Stubs.SECRET end
        equip(TRINKET2, "ironfoe")
        _G.GetInventoryItemQuality = function() error("no quality") end
        equip(MAIN_HAND, "sword")
        T.same(entries(ns), {})
        Stubs.SetEquipment(Stubs.state.equipment)
        Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
        Stubs.Advance(1)
        T.same(entries(ns), { "*Equipped your first epic item: Ironfoe", "*Equipped your first rare item: Thrash Blade" },
            "a secret quality was left for the next look")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("stop listening when switched off", function()
        local ns = start()
        ns.Trackers:SetWanted("Gear", false)
        equip(TRINKET1, "trinket")
        T.same(entries(ns), {})
        ns.Trackers:SetWanted("Gear", true)
        Stubs.Advance(1)
        T.same(entries(ns), { "*Equipped your first epic item: Hand of Justice" }, "found at the next look")
    end)

    it("record a change found at login on the login day", function()
        start()
        Stubs.Fire("PLAYER_LOGOUT")
        Stubs.state.equipment[TRINKET1] = item("trinket") -- equipped while Wayscribe was off
        Stubs.SetTime(os.time({ year = 2026, month = 10, day = 5, hour = 12 }))
        local ns = Stubs.Relog()
        Stubs.Advance(1)
        T.same(entries(ns), { "*Equipped your first epic item: Hand of Justice" })
        local today = ns.Time.DayKey(Stubs.Now())
        T.eq(#ns.Store:GetRecordsOfType("GEAR", today, today), 1, "on the login day")
    end)

    it("repeat nothing after a reload, or when the journal comes back without the tracker's state", function()
        start()
        equip(MAIN_HAND, "sword")
        equip(TRINKET1, "trinket")
        equip(TRINKET1, nil)
        local ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        ns.Store:SetState("gear", nil)
        ns = Stubs.Relog()
        Stubs.Advance(1)
        equip(MAIN_HAND, "helm")
        equip(TRINKET1, "trinket")
        T.same(entries(ns), { "*Equipped your first rare item: Thrash Blade",
            "*Equipped your first epic item: Hand of Justice" }, "the journal knows them")
    end)

    it("repeat nothing after a backup is restored", function()
        local ns = start()
        equip(MAIN_HAND, "sword")
        equip(TRINKET1, "trinket")
        equip(TRINKET1, nil) -- not worn at the restored journal's first look
        local text
        ns.Backup:Make({}, function(result) text = result end)
        T.truthy(ns.Schema:ResetCharacter())
        ns = Stubs.Relog(nil, true)
        local found
        ns.Backup:Read(text, function(result) found = result end)
        T.truthy(ns.Backup:Restore(found))
        ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        equip(MAIN_HAND, "helm")
        equip(TRINKET1, "trinket")
        T.same(entries(ns), { "*Equipped your first rare item: Thrash Blade",
            "*Equipped your first epic item: Hand of Justice" })
    end)

    it("trace each look in developer mode", function()
        local accountDB = { schema = 1, log = {}, characters = {},
            settings = { trackers = { FirstVisits = false, Gold = false, Reputation = false, LegacyChallenges = false,
                Guild = false, Home = false, Collections = false, PvPRank = false }, devMode = true } }
        local ns = start(nil, { accountDB = accountDB })
        equip(TRINKET1, "trinket")
        equip(TRINKET2, "trinket")
        equip(MAIN_HAND, "green")
        Stubs.state.equipment[MAIN_HAND] = item("sword")
        Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
        Stubs.Advance(1)
        _G.GetInventoryItemID = nil
        Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
        Stubs.Advance(1)
        local traced = {}
        for i, line in ipairs(ns.Trace:GetLines()) do traced[i] = line:gsub("^%S+ %S+ ", "") end
        T.same(traced, {
            "Gear enable+PLAYER_ENTERING_WORLD: worn=3 -> first look",
            "Gear PLAYER_EQUIPMENT_CHANGED: slot=13 item=3000 quality=4 -> first epic",
            "Gear PLAYER_EQUIPMENT_CHANGED: slot=14 item=3000 quality=4 -> known",
            "Gear PLAYER_EQUIPMENT_CHANGED: slot=16 item=5000 quality=2 -> not notable",
            'Gear PLAYER_ENTERING_WORLD: worn=6 new="2000:3" -> recorded 1',
            "Gear PLAYER_ENTERING_WORLD: worn=0 -> no items",
        })
    end)
end)
