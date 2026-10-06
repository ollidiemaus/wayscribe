local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local DAY = 24 * 3600

-- Saturday, October 3: login at 12:00, level 12 and some ore. Sunday, October 4: a boss.
local function twoDays(opts)
    opts = opts or {}
    local ns = Stubs.LoadAddon({ level = 11, locale = opts.locale, charDB = opts.charDB })
    Stubs.Login()
    Stubs.state.itemNames[2770] = "Copper Ore"
    Stubs.Fire("PLAYER_LEVEL_UP", 12)
    ns.Store:Count("gather", 2770, 3)
    Stubs.Advance(DAY)
    ns.Store:Append("BOSS_KILLED", { encounterID = 2733, name = "Taragaman the Hungerer" })
    return ns
end

describe("export", function()
    it("writes every day like its page, oldest first", function()
        local ns = twoDays()
        local text, days = ns.Export.BuildText("all")
        T.eq(days, 2)
        T.eq(text, table.concat({
            "Wayscribe: the journal of Tester (Forever)",
            "Exported 2026-10-04 · Everything · 2 days",
            "",
            "Saturday, October 3, 2026 · played 12 h 0 min",
            "  12:00 PM  Reached level 12",
            "            Gathered 3× Copper Ore",
            "  Sessions: 12:00 PM - now",
            "",
            "Sunday, October 4, 2026 · played 12 h 0 min",
            "  12:00 PM  Defeated Taragaman the Hungerer for the first time",
            "  Sessions: 12:00 PM - now",
            "",
        }, "\n"))
    end)

    it("keeps to the chosen range and every category, whatever the journal's filter", function()
        local ns = twoDays()
        ns.Journal:SetCategoryShown("gathering", false)
        T.truthy(ns.Export.BuildText("month"):find("Gathered 3× Copper Ore", 1, true))
        Stubs.Advance(30 * DAY)
        local text, days = ns.Export.BuildText("month")
        T.eq(days, 0)
        T.eq(text, "Wayscribe: the journal of Tester (Forever)\nExported 2026-11-03 · This month · 0 days\n")
        T.eq(select(2, ns.Export.BuildText("year")), 2)
    end)

    it("opens a window with the text selected, from /ws export", function()
        local ns = twoDays()
        ns.Slash:Handle("export year")
        local frame = _G.WayscribeExportFrame
        T.truthy(frame:IsShown())
        T.eq(ns.Export:GetText(), (ns.Export.BuildText("year")))
        T.eq(frame.range, "year")
        ns.Slash:Handle("export nonsense")
        T.eq(frame.range, "all")
        T.truthy(Stubs.Texts(frame)[1] == "Export journal")
    end)

    it("works on a read-only journal too", function()
        local ns = twoDays()
        local saved = Stubs.Copy(ns.charDB)
        saved.meta.guid = "Player-1-0000BBBB"
        ns = Stubs.LoadAddon({ charDB = saved })
        Stubs.Login()
        T.truthy(ns.safeMode)
        ns.Export:Open()
        T.truthy(ns.Export:GetText():find("Reached level 12", 1, true))
    end)

    it("reads in German", function()
        local ns = twoDays({ locale = "deDE" })
        local lines = {}
        for line in (ns.Export.BuildText("all") .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
        T.same({ lines[1], lines[2], lines[4], lines[5] }, {
            "Wayscribe: das Tagebuch von Tester (Forever)",
            "Exportiert am 04.10.2026 · Alles · 2 Tage",
            "Samstag, 3. Oktober 2026 · 12 Std. 0 Min. gespielt",
            "  12:00  Stufe 12 erreicht",
        })
    end)
end)
