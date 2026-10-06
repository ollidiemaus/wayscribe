local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local HOUR = 3600
local DAY = 24 * HOUR

-- Saturday 3 Oct: login at 12:00, level 12 and some ore. Sunday 4 Oct: a boss.
local function twoDays(opts)
    opts = opts or {}
    local ns = Stubs.LoadAddon({ level = 11, locale = opts.locale })
    if opts.scrollBox ~= false then Stubs.InstallScrollBox() end
    Stubs.Login()
    Stubs.state.itemNames[2770] = "Copper Ore"
    Stubs.Fire("PLAYER_LEVEL_UP", 12)
    ns.Store:Count("gather", 2770, 3)
    Stubs.Advance(DAY)
    ns.Store:Append("BOSS_KILLED", { encounterID = 2733, name = "Taragaman the Hungerer" })
    return ns
end

local function page(ns)
    return Stubs.Texts(ns.DayView.ui.content)
end

local function title(ns)
    return ns.DayView.ui.title:GetText(), ns.DayView.ui.subtitle:GetText()
end

-- The texts of the day list's rows, top to bottom.
local function listTexts(ns)
    local ui = ns.Journal.ui
    local rows = ui.scrollBox and ui.scrollBox.rows or ui.fixedRows
    local texts = {}
    for _, row in ipairs(rows) do
        if row:IsShown() then
            local detail = row.detail:GetText()
            texts[#texts + 1] = row.label:GetText() .. (detail ~= "" and (" | " .. detail) or "")
        end
    end
    return texts
end

local function rowFor(ns, dayKey)
    for _, row in ipairs(ns.Journal.ui.scrollBox.rows) do
        if row.dayKey == dayKey then return row end
    end
end

local function chip(ns, category)
    for _, button in ipairs(ns.Journal.ui.chips) do
        if button.category == category then return button end
    end
end

describe("the book", function()
    it("opens on the newest day, with the day list grouped by month", function()
        local ns = twoDays()
        ns.Journal:Toggle()
        local heading, subtitle = title(ns)
        T.eq(heading, "Sunday, October 4, 2026")
        T.eq(subtitle, "Today · played 12 h 0 min", "the session started yesterday")
        T.same(page(ns), {
            "12:00 PM", "Defeated Taragaman the Hungerer for the first time",
            "Sessions: 12:00 PM - now",
        })
        T.same(listTexts(ns), { "October 2026", "Sunday 4 | Today", "Saturday 3 | Yesterday" })
        T.truthy(rowFor(ns, 20261004).selected:IsShown())
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("shows a day's entries, counters and sessions", function()
        local ns = twoDays()
        ns.Journal:Open(20261003)
        local heading, subtitle = title(ns)
        T.eq(heading, "Saturday, October 3, 2026")
        T.eq(subtitle, "Yesterday · played 12 h 0 min", "the session runs on past midnight")
        T.same(page(ns), {
            "12:00 PM", "Reached level 12",
            "Gathered 3× Copper Ore",
            "Sessions: 12:00 PM - now",
        })
    end)

    it("selects a day from the list and turns pages", function()
        local ns = twoDays()
        ns.Journal:Toggle()
        local ui = ns.Journal.ui
        T.truthy(ui.older:IsEnabled())
        T.falsy(ui.newer:IsEnabled(), "already at the newest day")

        rowFor(ns, 20261003):Click()
        T.eq(title(ns), "Saturday, October 3, 2026")
        T.truthy(rowFor(ns, 20261003).selected:IsShown())
        T.falsy(rowFor(ns, 20261004).selected:IsShown())
        T.eq(ui.scrollBox.scrolledTo.dayKey, 20261003)
        T.falsy(ui.older:IsEnabled(), "the oldest day")

        ui.newer:Click()
        T.eq(title(ns), "Sunday, October 4, 2026")
        ui.older:Click()
        T.eq(title(ns), "Saturday, October 3, 2026")
    end)

    it("says so when the journal is empty", function()
        local ns = Stubs.LoadAddon()
        Stubs.InstallScrollBox()
        Stubs.Login()
        ns.Journal:Toggle()
        T.same(page(ns), { "Your journal is still empty. Go on an adventure!" })
        T.eq(title(ns), "")
        T.falsy(ns.Journal.ui.older:IsEnabled())
    end)

    it("shows why it is read-only", function()
        local ns = twoDays()
        ns.SetSafeMode("test reason")
        ns.Journal:Toggle()
        T.eq(ns.Journal.ui.banner:GetText(), "Read-only mode: test reason")
    end)
end)

describe("filters", function()
    it("hide a category on the page and days with nothing else, and are saved", function()
        local ns = twoDays()
        Stubs.Advance(DAY)
        ns.Store:Count("gather", 2770, 1) -- Monday: only ore
        ns.Journal:Toggle()
        T.same(listTexts(ns), { "October 2026", "Monday 5 | Today", "Sunday 4 | Yesterday", "Saturday 3" })

        chip(ns, "gathering"):Click()
        T.falsy(chip(ns, "gathering").shown)
        T.eq(ns.accountDB.settings.journalHidden.gathering, true)
        T.same(listTexts(ns), { "October 2026", "Sunday 4 | Yesterday", "Saturday 3" })
        T.eq(title(ns), "Sunday, October 4, 2026", "the shown day moved to the newest visible one")

        ns.Journal:Select(20261003)
        T.same(page(ns), { "12:00 PM", "Reached level 12", "Sessions: 12:00 PM - now" })

        chip(ns, "gathering"):Click()
        T.eq(ns.accountDB.settings.journalHidden.gathering, nil)
        T.same(listTexts(ns), { "October 2026", "Monday 5 | Today", "Sunday 4 | Yesterday", "Saturday 3" })
    end)

    it("hiding everything leaves a note instead of a page", function()
        local ns = twoDays()
        ns.Journal:Toggle()
        for _, button in ipairs(ns.Journal.ui.chips) do button:Click() end
        T.same(listTexts(ns), {})
        T.same(page(ns), { "Nothing to show with these filters." })
    end)

    it("has a chip for every category in use, in a fixed order", function()
        local ns = twoDays()
        ns.Journal:Toggle()
        local labels = {}
        for i, button in ipairs(ns.Journal.ui.chips) do labels[i] = button.label:GetText() end
        T.same(labels, { "Progress", "Adventure", "Quests", "Gathering" })
    end)
end)

describe("live updates", function()
    it("redraw once on the next frame, and follow a new day", function()
        local ns = twoDays()
        ns.Journal:Toggle()
        Stubs.Fire("PLAYER_LEVEL_UP", 13)
        T.eq(#page(ns), 3, "not redrawn yet")
        Stubs.Advance(0)
        T.same(page(ns), {
            "12:00 PM", "Defeated Taragaman the Hungerer for the first time",
            "12:00 PM", "Reached level 13",
            "Sessions: 12:00 PM - now",
        })

        Stubs.Advance(DAY)
        Stubs.Fire("PLAYER_LEVEL_UP", 14)
        Stubs.Advance(0)
        T.eq(title(ns), "Monday, October 5, 2026", "the reader of the newest day keeps reading the newest day")
        T.same(listTexts(ns), { "October 2026", "Monday 5 | Today", "Sunday 4 | Yesterday", "Saturday 3" })
    end)

    it("stay on an older day the reader chose", function()
        local ns = twoDays()
        ns.Journal:Open(20261003)
        Stubs.Advance(DAY)
        Stubs.Fire("PLAYER_LEVEL_UP", 13)
        Stubs.Advance(0)
        T.eq(title(ns), "Saturday, October 3, 2026")
    end)
end)

describe("entries", function()
    it("back-filled entries have no time and simulated ones are marked", function()
        local ns = twoDays()
        local today = ns.Time.DayKey(Stubs.Now())
        ns.Store:Append("QUEST_CHAIN_COMPLETED", { chain = "DEFIAS", quest = 166 }, { ts = Stubs.Now(), backfill = true })
        ns.Slash:Handle("dev")
        ns.Slash:Handle("simulate LEVEL_UP level=30")
        ns.Journal:Open(today)
        T.same(page(ns), {
            "12:00 PM", "Defeated Taragaman the Hungerer for the first time",
            "Completed the quest chain: The Defias Brotherhood",
            "12:00 PM", "[sim] Reached level 30",
            "Sessions: 12:00 PM - now",
        })
    end)

    it("follow the game's 24-hour clock setting", function()
        local ns = twoDays()
        Stubs.state.cvars.timeMgrUseMilitaryTime = "1"
        ns.Journal:Open(20261003)
        T.same(page(ns), { "12:00", "Reached level 12", "Gathered 3× Copper Ore", "Sessions: 12:00 - now" })
    end)

    it("read in German", function()
        local ns = twoDays({ locale = "deDE" })
        ns.Journal:Open(20261003)
        T.same({ title(ns) }, { "Samstag, 3. Oktober 2026", "Gestern · 12 Std. 0 Min. gespielt" })
        T.same(page(ns), {
            "12:00", "Stufe 12 erreicht",
            "Gesammelt: 3× Copper Ore",
            "Sitzungen: 12:00 - jetzt",
        })
        T.same(listTexts(ns), { "Oktober 2026", "Sonntag, 4. | Heute", "Samstag, 3. | Gestern" })
    end)
end)

describe("sessions on a page", function()
    it("count the part of each session that falls on the day", function()
        local ns = Stubs.LoadAddon({ level = 11, now = os.time({ year = 2026, month = 10, day = 3, hour = 23 }) })
        Stubs.Login()
        Stubs.Fire("PLAYER_LEVEL_UP", 12)
        Stubs.Advance(2 * HOUR) -- until 01:00 on Sunday
        Stubs.Fire("PLAYER_LOGOUT")
        local isVisible = function() return true end
        local saturday = ns.DayView.Build(20261003, isVisible)
        T.eq(saturday.subtitle, "Yesterday · played 1 h 0 min")
        T.eq(saturday.sessions, "Sessions: 11:00 PM - 1:00 AM")
        local sunday = ns.DayView.Build(20261004, isVisible)
        T.eq(sunday.subtitle, "Today · played 1 h 0 min")
    end)
end)

describe("without a ScrollBox", function()
    it("shows the rows around the selection and still turns pages", function()
        local ns = twoDays({ scrollBox = false })
        T.falsy(ns.Compat.has.scrollBox)
        ns.Journal:Toggle()
        T.same(listTexts(ns), { "October 2026", "Sunday 4 | Today", "Saturday 3 | Yesterday" })
        ns.Journal.ui.older:Click()
        T.eq(title(ns), "Saturday, October 3, 2026")
        T.truthy(ns.Journal.ui.fixedRows[3].selected:IsShown())
        T.eq(#ns.Log:GetEntries(), 0)
    end)
end)

describe("window", function()
    it("remembers its size", function()
        local ns = twoDays()
        ns.Journal:Toggle()
        local frame = _G.WayscribeJournalFrame
        frame:SetSize(700, 480)
        frame:GetScript("OnDragStop")(frame)
        T.eq(ns.accountDB.settings.journal.width, 700)
        T.eq(ns.accountDB.settings.journal.height, 480)

        Stubs.Relog()
        Stubs.ns.Journal:Toggle()
        T.eq(_G.WayscribeJournalFrame:GetWidth(), 700)
        T.eq(_G.WayscribeJournalFrame:GetHeight(), 480)
    end)

    it("opens at the login recap's day", function()
        local ns = twoDays()
        ns.LoginRecap:Show({ day = 20261003, lines = { "x" } })
        _G.WayscribeLoginRecapFrame.openButton:Click()
        T.truthy(_G.WayscribeJournalFrame:IsShown())
        T.eq(title(ns), "Saturday, October 3, 2026")
    end)
end)
