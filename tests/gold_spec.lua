local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

-- Logs in holding `money` copper and lets the tracker take its first look.
local function start(money, opts)
    local ns = Stubs.LoadAddon(opts)
    if money then Stubs.SetMoney(money) end
    Stubs.Login()
    return ns
end

local function change(copper)
    Stubs.SetMoney(copper)
    Stubs.Fire("PLAYER_MONEY")
end

local function today(ns)
    return ns.Store:GetDay(ns.Time.DayKey(Stubs.Now()))
end

local function gold(ns)
    local day = today(ns)
    local bucket = day and day.counters.gold or {}
    return { earned = bucket.earned, spent = bucket.spent }
end

local function lines(ns)
    local day = today(ns)
    return day and ns.RecordTypes:RenderCounters(day.counters) or {}
end

describe("gold", function()
    it("count increases as earned and decreases as spent, in copper", function()
        local ns = start(10000)
        T.same(gold(ns), {}, "the first look takes the amount silently")
        change(42500)
        change(31000)
        change(31050)
        T.same(gold(ns), { earned = 32550, spent = 11500 })
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("show one Progress line in the game's coin format", function()
        local ns = start(10000)
        change(42005)
        change(31000)
        T.same(lines(ns), { "Gold: 3g 20s 5c earned, 1g 10s 5c spent" })
        T.eq(ns.RecordTypes:CounterCategory("gold"), "progress")
    end)

    it("read naturally on a day with only earnings or only spending", function()
        local ns = start(0)
        change(123456789)
        T.same(lines(ns), { "Gold: 12,345g 67s 89c earned" })
        Stubs.Advance(86400)
        change(123456700)
        T.same(lines(ns), { "Gold: 89c spent" })
    end)

    it("catch a missed event at the next one, and take money changed between sessions silently", function()
        local ns = start(10000)
        Stubs.SetMoney(15000) -- PLAYER_MONEY never came
        change(20000)
        T.same(gold(ns), { earned = 10000 })
        ns = Stubs.Relog()
        T.same(gold(ns), { earned = 10000 }, "a reload changes nothing")
        Stubs.Fire("PLAYER_LOGOUT")
        Stubs.SetMoney(90000) -- mail opened on another addon-less login
        ns = Stubs.Relog()
        T.same(gold(ns), { earned = 10000 }, "taken silently at login")
        change(80000)
        T.same(gold(ns), { earned = 10000, spent = 10000 })
    end)

    it("take the amount again when the world loads, in case it wasn't known at login", function()
        local ns = Stubs.LoadAddon()
        Stubs.SetMoney(0)
        Stubs.Fire("ADDON_LOADED", "Wayscribe")
        Stubs.Fire("PLAYER_LOGIN")
        Stubs.SetMoney(5000000)
        Stubs.Fire("PLAYER_ENTERING_WORLD", true, false)
        change(5000100)
        T.same(gold(ns), { earned = 100 })
    end)

    it("lead a year of only spending with what was spent", function()
        local ns = start(50000)
        change(20000)
        for _, card in ipairs(ns.YearCards:Build(2026)) do
            if card.id == "gold" then
                T.eq(card.big, "3g")
                T.eq(card.caption, "spent")
                T.same(card.lines, { "Most held at once: 5g" })
            end
        end
    end)

    it("stop listening when switched off, and take the amount silently when switched on", function()
        local ns = start(10000)
        ns.Trackers:SetWanted("Gold", false)
        change(50000)
        T.same(gold(ns), {})
        ns.Trackers:SetWanted("Gold", true)
        change(60000)
        T.same(gold(ns), { earned = 10000 })
    end)

    it("write nothing and log no error when GetMoney is missing, errors or is secret", function()
        local ns = start(nil)
        Stubs.Fire("PLAYER_MONEY")
        _G.GetMoney = function() error("no money") end
        Stubs.Fire("PLAYER_MONEY")
        Stubs.SetMoney(Stubs.SECRET)
        Stubs.Fire("PLAYER_MONEY")
        change(10000)
        T.same(gold(ns), {}, "the first readable amount is the first look")
        Stubs.SetMoney(Stubs.SECRET)
        Stubs.Fire("PLAYER_MONEY")
        change(12000)
        T.same(gold(ns), { earned = 2000 })
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("give Your Year a gold card before Time played", function()
        local ns = start(50000)
        change(80000)   -- Oct 3: 3g earned
        change(20000)   -- 6g spent
        Stubs.Advance(86400)
        change(520000)  -- Oct 4: 50g earned, 52g held
        change(510000)
        Stubs.SetTime(os.time({ year = 2026, month = 11, day = 2, hour = 12 }))
        change(530000)  -- Nov 2: 2g earned, 53g held
        local cards, ids = ns.YearCards:Build(2026), {}
        local card
        for i, built in ipairs(cards) do
            ids[built.id] = i
            if built.id == "gold" then card = built end
        end
        T.eq(card.title, "Gold")
        T.eq(card.big, "55g")
        T.eq(card.caption, "earned")
        T.same(card.lines, { "Spent: 7g", "Best day: Sunday, October 4, 2026 (50g earned)", "Most held at once: 53g" })
        T.truthy(ids.gold < ids.time, "before Time played")
        ns.Store:Rebuild()
        T.same(ns.YearCards:Build(2026)[ids.gold].lines[2], "Best day: Sunday, October 4, 2026 (50g earned)",
            "the best day comes back from the counters")
    end)

    it("keep the earlier day as the best on a tie, in a month and across months", function()
        local ns = start(100000)
        change(150000)  -- Oct 3: 5g earned
        Stubs.Advance(86400)
        change(200000)  -- Oct 4: 5g earned, then 20g spent
        change(0)
        Stubs.SetTime(os.time({ year = 2026, month = 11, day = 2, hour = 12 }))
        change(50000)   -- Nov 2: 5g earned
        local function bestDay()
            for _, built in ipairs(ns.YearCards:Build(2026)) do
                if built.id == "gold" then return built.lines[2] end
            end
        end
        T.eq(bestDay(), "Best day: Saturday, October 3, 2026 (5g earned)")
        ns.Store:Rebuild()
        T.eq(bestDay(), "Best day: Saturday, October 3, 2026 (5g earned)", "and after a rebuild")
    end)

    it("trace each look in developer mode", function()
        local accountDB = { schema = 1, settings = { devMode = true }, log = {},
            characters = {} }
        local ns = start(10000, { accountDB = accountDB, only = "Gold" })
        change(12000)
        change(12000)
        Stubs.SetMoney(Stubs.SECRET)
        Stubs.Fire("PLAYER_MONEY")
        local traced = {}
        for i, line in ipairs(ns.Trace:GetLines()) do traced[i] = line:gsub("^%S+ %S+ ", "") end
        T.same(traced, {
            "Gold enable: money=10000 saved=missing -> first look",
            "Gold PLAYER_ENTERING_WORLD: money=10000 saved=10000 -> taken",
            "Gold PLAYER_MONEY: money=12000 saved=10000 -> earned",
            "Gold PLAYER_MONEY: money=12000 saved=12000 -> unchanged",
            "Gold PLAYER_MONEY: money=secret saved=12000 -> no money",
        })
    end)

    it("read in German", function()
        local ns = start(0, { locale = "deDE" })
        change(123456789)
        change(123456700)
        T.same(lines(ns), { "Gold: 12.345G 67S 89K verdient, 89K ausgegeben" })
        local card
        for _, built in ipairs(ns.YearCards:Build(2026)) do
            if built.id == "gold" then card = built end
        end
        T.eq(card.caption, "verdient")
        T.same(card.lines, { "Ausgegeben: 89K", "Bester Tag: Samstag, 3. Oktober 2026 (12.345G 67S 89K verdient)",
            "Höchster Besitz: 12.345G 67S 89K" })
    end)
end)
