local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local HOUR = 3600

local function at(year, month, day, hour)
    return os.time({ year = year, month = month, day = day, hour = hour or 12 })
end

-- Saturday, October 3, 2026, 12:00 to 14:00: level 12 and a first boss kill.
local function played(opts)
    opts = opts or {}
    local ns = Stubs.LoadAddon({ level = 11, now = opts.now or at(2026, 10, 3), locale = opts.locale })
    if opts.native then Stubs.InstallNativeUI() else Stubs.InstallScrollBox() end
    Stubs.Login()
    Stubs.Fire("PLAYER_LEVEL_UP", 12)
    ns.Store:Append("BOSS_KILLED", { encounterID = 2733, name = "Taragaman the Hungerer" })
    Stubs.Advance(2 * HOUR)
    ns.Store:EndSession(Stubs.Now())
    return ns
end

-- StaticPopup as far as the prompt uses it; returns the list of popups shown.
local function installPopups()
    local shown = {}
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(which, arg1, _, data)
        shown[#shown + 1] = { which = which, arg1 = arg1, data = data }
    end
    return shown
end

-- The left page's rows, top to bottom: "label | detail".
local function listTexts(ns)
    local texts = {}
    for _, row in ipairs(ns.YourYear.ui.rows) do
        if row:IsShown() then
            local detail = row.detail:GetText()
            texts[#texts + 1] = row.label:GetText() .. (detail ~= "" and (" | " .. detail) or "")
        end
    end
    return texts
end

-- The right page: title, subtitle, big number and caption (when shown), lines.
local function pageTexts(ns)
    local ui = ns.YourYear.ui
    local texts = { ui.title:GetText(), ui.subtitle:GetText() }
    if ui.big:IsShown() then
        texts[#texts + 1] = ui.big:GetText()
        texts[#texts + 1] = ui.caption:GetText()
    end
    for _, line in ipairs(ui.lines) do
        if line:IsShown() then texts[#texts + 1] = line:GetText() end
    end
    return texts
end

describe("Your Year tab", function()
    it("opens on December 1 with the year's cards, turned like pages", function()
        local ns = played()
        Stubs.SetTime(at(2026, 12, 1))
        ns.Journal:OpenYear()
        local ui = ns.Journal.ui
        T.same(listTexts(ns), { "Your 2026", "The year at a glance", "Levels", "Bosses", "Time played" })
        T.same(pageTexts(ns), {
            "The year at a glance", "Your 2026", "2", "entries in your journal", "One of them was a first",
            "Adventures on 1 day in 1 month",
        })
        T.eq(ui.pageText:GetText(), "Page 1/4")
        T.falsy(ui.older:IsEnabled(), "no card before the first")
        T.truthy(ui.newer:IsEnabled())
        T.eq(ui.newer.tooltip, "Next card")
        T.falsy(ui.journalRight:IsShown(), "the day page is hidden")
        T.falsy(ui.filterBar:IsShown(), "the journal's filter has nothing to filter here")

        ui.newer:Click()
        T.same(pageTexts(ns), { "Levels", "Your 2026", "+1", "level gained, from 11 to 12",
            "Reached level 12 on Saturday, October 3, 2026" })
        T.eq(ui.pageText:GetText(), "Page 2/4")

        ns.YourYear.ui.rows[5]:Click()
        T.same(pageTexts(ns), { "Time played", "Your 2026", "2 h 0 min", "in 1 session on 1 day",
            "Most active day: Saturday, October 3, 2026 (2 h 0 min)", "Longest session: 2 h 0 min" })
        T.falsy(ui.newer:IsEnabled(), "the last card")
        T.truthy(ns.YourYear.ui.rows[5].selected:IsShown())

        ns.Journal:SetTab("journal")
        T.truthy(ui.journalRight:IsShown())
        T.falsy(ns.YourYear.ui.right:IsShown())
        T.eq(ui.older.tooltip, "Older day")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("waits for December 1, unless in developer mode", function()
        local ns = played()
        ns.Journal:OpenYear()
        T.same(listTexts(ns), { "Your 2026 | 2026-12-01" })
        T.same(pageTexts(ns), { "Your 2026", "", "Your year opens on Tuesday, December 1, 2026. Until then, every adventure adds to it." })
        T.eq(ns.Journal.ui.pageText:GetText(), "")
        T.falsy(ns.Journal.ui.newer:IsEnabled())

        ns.Slash:Handle("dev")
        Stubs.Advance(0)
        T.eq(pageTexts(ns)[2], "Your 2026 · preview")
        T.eq(ns.Journal.ui.pageText:GetText(), "Page 1/4")
    end)

    it("shows past years any time, opening at the newest one that is open", function()
        played({ now = at(2025, 6, 1) })
        local ns = Stubs.Relog({ now = at(2026, 10, 3) })
        ns.Store:Append("LEVEL_UP", { level = 20 })
        ns.Journal:OpenYear()
        T.same(listTexts(ns), {
            "Your 2026 | 2026-12-01", "Your 2025", "The year at a glance", "Levels", "Bosses", "Time played",
        })
        T.eq(pageTexts(ns)[2], "Your 2025")

        ns.YourYear.ui.rows[1]:Click()
        T.same(listTexts(ns), { "Your 2026 | 2026-12-01", "Your 2025" })
        T.eq(pageTexts(ns)[1], "Your 2026")
    end)

    it("says so when there is nothing yet", function()
        local ns = Stubs.LoadAddon()
        Stubs.Login()
        ns.Slash:Handle("year")
        T.same(pageTexts(ns), { "Your Year", "", "Your journal has no entries yet. Your first year grows with your adventures." })
        T.same(listTexts(ns), {})
    end)

    it("uses the default UI's tabs where the client has them, else plain buttons", function()
        local ns = played({ native = true })
        ns.Journal:Toggle()
        local frame = ns.Journal.ui.frame
        T.eq(frame.numTabs, 2)
        T.eq(frame.selectedTab, 1)
        _G.WayscribeJournalFrameTab2:Click()
        T.eq(frame.selectedTab, 2)
        T.eq(ns.Journal.state.tab, "year")

        ns = played()
        ns.Journal:Toggle()
        T.falsy(_G.WayscribeJournalFrameTab1:IsEnabled(), "the chosen tab")
        T.truthy(_G.WayscribeJournalFrameTab2:IsEnabled())
        T.eq(_G.WayscribeJournalFrameTab2.text, "Your Year")
    end)

    it("/ws year opens it, and the journal opens at a day on the journal tab", function()
        local ns = played()
        Stubs.SetTime(at(2027, 1, 2))
        ns.Slash:Handle("year 2026")
        T.eq(ns.Journal.state.tab, "year")
        T.eq(pageTexts(ns)[2], "Your 2026")
        ns.Journal:Toggle()
        ns.Journal:Toggle()
        T.eq(ns.Journal.state.tab, "year", "reopening keeps the tab")
        ns.Journal:Open(20261003)
        T.eq(ns.Journal.state.tab, "journal")
    end)

    it("reads in German", function()
        local ns = played({ locale = "deDE" })
        Stubs.SetTime(at(2026, 12, 24))
        ns.Journal:OpenYear()
        T.same(listTexts(ns), { "Dein 2026", "Das Jahr auf einen Blick", "Stufen", "Bosse", "Spielzeit" })
        T.eq(_G.WayscribeJournalFrameTab2.text, "Dein Jahr")
    end)
end)

describe("Your Year prompt", function()
    it("tells once, at the first login after December 1", function()
        local ns = played()
        ns.Options:Set("showLoginRecap", false)
        ns = Stubs.Relog({ now = at(2026, 12, 1, 18) })
        local shown = installPopups()
        Stubs.Advance(6)
        T.eq(#shown, 1)
        T.same(shown[1], { which = "WAYSCRIBE_YOUR_YEAR", arg1 = 2026, data = 2026 })
        local printed = Stubs.Printed()
        T.truthy(printed[#printed]:find("Your 2026 is ready"), printed[#printed])
        T.eq(ns.Store:GetState("yourYearPrompted"), 2026)

        _G.StaticPopupDialogs.WAYSCRIBE_YOUR_YEAR.OnAccept(nil, 2026)
        T.eq(ns.Journal.state.tab, "year")
        T.truthy(ns.Journal.ui.frame:IsShown())

        Stubs.Relog({ now = at(2026, 12, 2) })
        shown = installPopups()
        Stubs.Advance(6)
        T.eq(#shown, 0, "once")
    end)

    it("waits for the login recap to close", function()
        played()
        local ns = Stubs.Relog({ now = at(2026, 12, 1, 18) })
        local shown = installPopups()
        Stubs.Advance(3)
        T.truthy(ns.LoginRecap:IsShown())
        Stubs.Advance(3)
        T.eq(#shown, 0)
        _G.WayscribeLoginRecapFrame:Hide()
        T.eq(#shown, 1)
        T.eq(shown[1].arg1, 2026)
    end)

    it("tells about last year in January, when December went by without a login", function()
        local ns = played()
        ns.Options:Set("showLoginRecap", false)
        Stubs.Relog({ now = at(2027, 1, 10) })
        local shown = installPopups()
        Stubs.Advance(6)
        T.eq(shown[1] and shown[1].arg1, 2026)
    end)

    it("stays quiet before December, after a /reload, and for a year without entries", function()
        local ns = played()
        ns.Options:Set("showLoginRecap", false)
        Stubs.Relog({ now = at(2026, 11, 30) })
        local shown = installPopups()
        Stubs.Advance(6)
        T.eq(#shown, 0, "November")

        Stubs.Relog({ now = at(2026, 12, 1) }, true)
        shown = installPopups()
        Stubs.Advance(6)
        T.eq(#shown, 0, "reload")

        Stubs.LoadAddon({ now = at(2026, 12, 1) })
        Stubs.Login()
        shown = installPopups()
        Stubs.Advance(6)
        T.eq(#shown, 0, "nothing written in 2026")
    end)
end)
