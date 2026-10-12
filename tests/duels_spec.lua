local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local KANGAL = { guid = "Player-1-000000C1", name = "Kangal", surname = "Mooran", class = "WARRIOR", level = 6 }
local ANN = { guid = "Player-1-000000C2", name = "Ann", surname = "Lee", class = "ROGUE", level = 9 }

-- Forever names: the player is "Tester Brightwood", like the result lines name them.
local function start(opts)
    opts = opts or {}
    opts.name, opts.surname = "Tester", "Brightwood"
    local ns = Stubs.LoadAddon(opts)
    if opts.scrollBox then Stubs.InstallScrollBox() end
    Stubs.Login()
    return ns
end

local function duels(ns)
    return ns.Store:GetRecordsOfType("DUEL")
end

local function listening(ns)
    return ns.Duels.frame ~= nil and ns.Duels.frame:IsEventRegistered("CHAT_MSG_SYSTEM")
end

local function result(text)
    Stubs.Fire("DUEL_FINISHED")
    Stubs.Fire("CHAT_MSG_SYSTEM", text)
end

describe("duels", function()
    it("notes a duel the player challenged and won, with the opponent's class and level", function()
        local ns = start()
        Stubs.SetBestMap(1412)
        Stubs.SetSubZone("Bloodhoof Village")
        Stubs.SetUnit("target", KANGAL)
        StartDuel("target", true)
        T.truthy(listening(ns), "system chat, while a duel is under way")
        Stubs.Fire("CHAT_MSG_SYSTEM", "Duel starting: 3")
        Stubs.Advance(23)
        Stubs.SetUnit("target", nil)
        result("Tester Brightwood has defeated Kangal Mooran in a duel")
        local list = duels(ns)
        T.eq(#list, 1)
        local data = list[1].data
        T.eq(ns.Players:Get(data.p).name, "Kangal Mooran")
        T.same(data, { p = data.p, cls = "WARRIOR", lv = 6, ml = 10, won = true, map = 1412, sub = "Bloodhoof Village", dur = 20 })
        T.eq(ns.RecordTypes:Render(list[1]), "Won a duel against Kangal Mooran (Warrior, level 6)")
        T.eq(ns.RecordTypes:CategoryOf("DUEL"), "pvp")
        T.falsy(listening(ns), "and not after it")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("notes a loss when challenged, and a flight either way", function()
        local ns = start()
        Stubs.SetUnit("nameplate3", KANGAL)
        Stubs.Fire("DUEL_REQUESTED", "Kangal Mooran")
        result("Kangal Mooran has defeated Tester Brightwood in a duel")
        Stubs.Fire("DUEL_REQUESTED", "Bo Stone") -- nowhere to be seen
        result("Bo Stone has fled from Tester Brightwood in a duel")
        Stubs.Fire("DUEL_REQUESTED", "Bo Stone")
        result("Tester Brightwood has fled from Bo Stone in a duel")
        local list = duels(ns)
        T.eq(#list, 3)
        T.eq(list[1].data.won, false)
        T.eq(list[1].data.cls, "WARRIOR")
        T.eq(ns.RecordTypes:Render(list[1]), "Lost a duel against Kangal Mooran (Warrior, level 6)")
        local bo = list[2].data
        T.same({ bo.p, bo.name, bo.cls, bo.won, bo.fled }, { nil, "Bo Stone", nil, true, true })
        T.eq(ns.RecordTypes:Render(list[2]), "Won a duel against Bo Stone, who fled")
        T.eq(ns.RecordTypes:Render(list[3]), "Fled from a duel against Bo Stone")
    end)

    it("notes a duel to the death", function()
        local ns = start()
        Stubs.SetUnit("target", KANGAL)
        StartDuel("target", true, true) -- the dialog's call
        result("Tester Brightwood has defeated Kangal Mooran in a duel")
        Stubs.Fire("DUEL_TO_THE_DEATH_REQUESTED", "Kangal Mooran")
        result("Kangal Mooran has defeated Tester Brightwood in a duel")
        local list = duels(ns)
        T.eq(ns.RecordTypes:Render(list[1]), "Won a duel to the death against Kangal Mooran (Warrior, level 6)")
        T.eq(ns.RecordTypes:Render(list[2]), "Lost a duel to the death against Kangal Mooran (Warrior, level 6)")
    end)

    it("leaves no entry for a declined challenge or someone else's duel", function()
        local ns = start()
        Stubs.SetUnit("target", KANGAL)
        StartDuel("target", true)
        Stubs.Fire("DUEL_FINISHED") -- declined: no result line
        Stubs.Advance(3)
        T.falsy(listening(ns))
        Stubs.Fire("CHAT_MSG_SYSTEM", "Tester Brightwood has defeated Kangal Mooran in a duel")
        StartDuel("target", true)
        Stubs.Fire("CHAT_MSG_SYSTEM", "Ann Lee has defeated Bo Stone in a duel")
        Stubs.Fire("CHAT_MSG_SYSTEM", Stubs.SECRET)
        Stubs.Fire("CHAT_MSG_SYSTEM", "You are now away.")
        T.truthy(listening(ns), "still waiting for the player's own")
        Stubs.Advance(1800)
        T.falsy(listening(ns), "a challenge nobody finished is forgotten")
        T.eq(#duels(ns), 0)
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("finds an opponent the challenge only named, once the duel is over", function()
        local ns = start()
        StartDuel("Kangal Mooran") -- /duel Kangal Mooran, not in sight
        Stubs.SetUnit("softenemy", KANGAL)
        result("Tester Brightwood has defeated Kangal Mooran in a duel")
        local data = duels(ns)[1].data
        T.eq(ns.Players:Get(data.p).name, "Kangal Mooran")
        T.eq(data.lv, 6)
    end)

    it("reads the result lines in the client's language", function()
        local ns = start({ locale = "deDE" })
        _G.DUEL_WINNER_KNOCKOUT = "%1$s hat %2$s in einem Duell besiegt."
        _G.DUEL_WINNER_RETREAT = "%2$s ist vor %1$s aus einem Duell geflüchtet."
        _G.LOCALIZED_CLASS_NAMES_MALE.WARRIOR = "Krieger"
        Stubs.SetUnit("target", KANGAL)
        StartDuel("target", true)
        result("Kangal Mooran hat Tester Brightwood in einem Duell besiegt.")
        StartDuel("target", true)
        result("Kangal Mooran ist vor Tester Brightwood aus einem Duell geflüchtet.")
        local list = duels(ns)
        T.eq(ns.RecordTypes:Render(list[1]), "Duell gegen Kangal Mooran (Krieger, Stufe 6) verloren")
        T.eq(ns.RecordTypes:Render(list[2]), "Duell gegen Kangal Mooran (Krieger, Stufe 6) gewonnen, der Gegner ist geflüchtet")
    end)

    it("stops noting duels when the tracker is turned off", function()
        local ns = start()
        ns.Trackers:SetWanted("Duels", false)
        Stubs.SetUnit("target", KANGAL)
        StartDuel("target", true)
        result("Tester Brightwood has defeated Kangal Mooran in a duel")
        T.eq(#duels(ns), 0)
    end)
end)

-- Eight duels, an hour apart: Kangal 3-1, Bo Stone (never seen) 0-3, Ann 1-0.
local function season(opts)
    local ns = start(opts)
    local kangal = ns.Players:Intern(KANGAL.guid, "Kangal Mooran", nil, "WARRIOR")
    local ann = ns.Players:Intern(ANN.guid, "Ann Lee", nil, "ROGUE")
    local bo = { name = "Bo Stone", cls = "MAGE", lv = 8 }
    local function duel(opponent, won, extra)
        local data = { won = won, ml = 10, sub = "Bloodhoof Village", map = 1412 }
        for key, value in pairs(opponent) do data[key] = value end
        for key, value in pairs(extra or {}) do data[key] = value end
        ns.Store:Append("DUEL", data)
        Stubs.Advance(3600)
    end
    duel({ p = kangal, cls = "WARRIOR", lv = 5 }, true)
    duel(bo, false)
    duel({ p = kangal, cls = "WARRIOR", lv = 5 }, true)
    duel(bo, false, { fled = true })
    duel({ p = kangal, cls = "WARRIOR", lv = 6 }, false)
    duel(bo, false)
    duel({ p = kangal, cls = "WARRIOR", lv = 6 }, true, { death = true })
    duel({ p = ann, cls = "ROGUE", lv = 9 }, true)
    return ns
end

local function card(ns, year)
    for _, built in ipairs(ns.YearCards:Build(year or 2026)) do
        if built.id == "duels" then
            local flat = { built.title, built.big, built.caption }
            for _, line in ipairs(built.lines) do flat[#flat + 1] = line end
            return flat
        end
    end
end

describe("duels card", function()
    it("adds up the year: the result, the rival, the nemesis, the easiest and toughest class", function()
        local ns = season()
        T.same(card(ns), {
            "Duels", "8", "duels",
            "4 won, 4 lost (50%)",
            "Most often against Kangal Mooran (4 duels)",
            "Nemesis: Bo Stone (beat you 3 times)",
            "Easiest class: Warrior (3 of 4 won)",
            "Toughest class: Mage (0 of 3 won)",
        })
    end)

    it("keeps to what one duel can say, and is left out without duels", function()
        local ns = start()
        T.eq(card(ns), nil)
        ns.Store:Append("DUEL", { name = "Bo Stone", won = true })
        T.same(card(ns), { "Duels", "1", "duel", "1 won, 0 lost (100%)" })
    end)

    it("reads in German", function()
        local ns = season({ locale = "deDE" })
        _G.LOCALIZED_CLASS_NAMES_MALE.WARRIOR, _G.LOCALIZED_CLASS_NAMES_MALE.MAGE = "Krieger", "Magier"
        T.same(card(ns), {
            "Duelle", "8", "Duelle",
            "4 gewonnen, 4 verloren (50 %)",
            "Am häufigsten gegen Kangal Mooran (4 Duelle)",
            "Erzfeind: Bo Stone (hat dich 3-mal besiegt)",
            "Leichteste Klasse: Krieger (3 von 4 gewonnen)",
            "Schwerste Klasse: Magier (0 von 3 gewonnen)",
        })
    end)
end)

-- The left page's rows: "label | detail".
local function listTexts(ns)
    local texts = {}
    for _, row in ipairs(ns.DuelsView.ui.rows or {}) do
        if row:IsShown() then
            texts[#texts + 1] = row.label:GetText() .. " | " .. row.detail:GetText()
        end
    end
    return texts
end

-- The right page: title, subtitle, then its lines ("label | detail").
local function pageTexts(ns)
    local ui = ns.DuelsView.ui
    local texts = { ui.title:GetText(), ui.subtitle:GetText() }
    for _, line in ipairs(ui.lines) do
        if line.label:IsShown() then
            local detail = line.detail:IsShown() and line.detail:GetText() or ""
            texts[#texts + 1] = line.label:GetText() .. (detail ~= "" and (" | " .. detail) or "")
        end
    end
    return texts
end

local function day(ns, hoursAfterStart)
    return ns.Time.FormatDay(ns.Time.DayKey(Stubs.Now() - 8 * 3600 + hoursAfterStart * 3600))
end

describe("duels page", function()
    it("sits between Maps and Your Year, and /ws duels opens it at all duels", function()
        local ns = season({ scrollBox = true })
        ns.Slash:Handle("duels")
        T.eq(ns.Journal.state.tab, "duels")
        T.eq(_G.WayscribeJournalFrameTab4.text, "Duels")
        T.eq(_G.WayscribeJournalFrameTab4.lastPoint[2], _G.WayscribeJournalFrameTab3)
        T.eq(_G.WayscribeJournalFrameTab5.text, "Your Year")
        T.same(listTexts(ns), { "All duels | 4–4", "Kangal Mooran | 3–1", "Bo Stone | 0–3", "Ann Lee | 1–0" })
        local page = pageTexts(ns)
        T.same({ page[1], page[2], page[3], page[4], page[5], page[6], page[7] }, {
            "All duels", "8 duels · 4 won · 4 lost · 50%",
            "By class", "Warrior | 3–1 · 75%", "Mage | 0–3 · 0%", "Rogue | 1–0 · 100%",
            "Recent duels",
        })
        T.eq(page[8], "Won · Ann Lee | " .. day(ns, 7))
        T.eq(page[9], "Won to the death · Kangal Mooran | " .. day(ns, 6))
        T.eq(#page, 9 + 6, "the eight latest")
        T.eq(ns.Journal.ui.pageText:GetText(), "Page 1/4")
        T.falsy(ns.Journal.ui.older:IsEnabled())
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("turns to each opponent, with every duel against them", function()
        local ns = season()
        ns.Journal:OpenDuels()
        ns.Journal:Turn(-1)
        local page = pageTexts(ns)
        T.eq(page[1], "Kangal Mooran")
        T.eq(page[2], "Warrior, level 6 · 4 duels · 3 won · 1 lost · 75%")
        T.eq(page[3], "Every duel")
        T.eq(page[4], "Won to the death · Bloodhoof Village, Mulgore | " .. day(ns, 6))
        T.eq(page[5], "Lost · Bloodhoof Village, Mulgore | " .. day(ns, 4))
        T.eq(#page, 7)
        T.eq(ns.Journal.ui.pageText:GetText(), "Page 2/4")
        ns.Journal:Turn(-1)
        T.eq(pageTexts(ns)[1], "Bo Stone")
        T.eq(pageTexts(ns)[2], "Mage, level 8 · 3 duels · 0 won · 3 lost · 0%")
        T.eq(pageTexts(ns)[4], "Lost · Bloodhoof Village, Mulgore | " .. day(ns, 5))
        T.eq(pageTexts(ns)[5], "Fled · Bloodhoof Village, Mulgore | " .. day(ns, 3))
        ns.Journal:Turn(-1)
        ns.Journal:Turn(-1)
        T.eq(pageTexts(ns)[1], "Ann Lee", "the last one stays")
        T.falsy(ns.Journal.ui.newer:IsEnabled())
        ns.DuelsView.ui.rows[1]:Click()
        T.eq(pageTexts(ns)[1], "All duels")
    end)

    it("follows a new duel while it is open", function()
        local ns = season()
        ns.Journal:OpenDuels()
        Stubs.SetUnit("target", ANN)
        StartDuel("target", true)
        result("Ann Lee has defeated Tester Brightwood in a duel")
        Stubs.Advance(0)
        T.eq(pageTexts(ns)[2], "9 duels · 4 won · 5 lost · 44%")
        T.same(listTexts(ns)[4], "Ann Lee | 1–1")
    end)

    it("says how to duel while there are none", function()
        local ns = start()
        ns.Journal:OpenDuels()
        T.same(listTexts(ns), {})
        T.eq(pageTexts(ns)[3]:find("No duels yet", 1, true), 1)
        T.eq(ns.Journal.ui.pageText:GetText(), "")
    end)

    it("is gone while the tracker is off, and /ws duels says how to turn it on", function()
        local ns = season()
        ns.Journal:OpenDuels()
        ns.Trackers:SetWanted("Duels", false)
        Stubs.Advance(0)
        T.eq(ns.Journal.state.tab, "journal")
        T.falsy(_G.WayscribeJournalFrameTab4:IsShown())
        T.eq(_G.WayscribeJournalFrameTab5.lastPoint[2], _G.WayscribeJournalFrameTab3, "Your Year next to Maps")
        ns.Slash:Handle("duels")
        T.eq(ns.Journal.state.tab, "journal")
        T.truthy(Stubs.Printed()[#Stubs.Printed()]:find("Duels tracker is turned off", 1, true))
        ns.Trackers:SetWanted("Duels", true)
        Stubs.Advance(0)
        T.truthy(_G.WayscribeJournalFrameTab4:IsShown())
    end)

    it("shows the duels on the day's page too", function()
        local ns = season()
        ns.Journal:Open()
        local found = false
        for _, text in ipairs(Stubs.Texts(ns.DayView.ui.content)) do
            if text:find("Won a duel to the death against Kangal Mooran (Warrior, level 6)", 1, true) then found = true end
        end
        T.truthy(found)
    end)
end)
