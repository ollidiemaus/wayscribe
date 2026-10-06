local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local DAY = 24 * 3600

-- Yesterday: a session with a level up and some ore. Then logout.
local function playedYesterday()
    local ns = Stubs.LoadAddon({ level = 11, now = os.time({ year = 2026, month = 10, day = 2, hour = 20 }) })
    Stubs.Login()
    Stubs.Advance(600)
    Stubs.Fire("PLAYER_LEVEL_UP", 12)
    ns.Store:Count("gather", 2770, 4)
    Stubs.state.itemNames[2770] = "Copper Ore"
    Stubs.Advance(3000)
    return ns
end

local function recapFrame()
    return _G.WayscribeLoginRecapFrame
end

describe("login recap", function()
    it("shows the previous session at the first login of the day", function()
        playedYesterday()
        local ns = Stubs.Relog({ now = Stubs.Now() + DAY / 2 })
        T.eq(recapFrame(), nil, "waits for the loading screen to settle")
        Stubs.Advance(3)
        local frame = recapFrame()
        T.truthy(frame and frame:IsShown())
        T.same(Stubs.Texts(frame), {
            "Last session",
            "2026-10-02 · 1 h 0 min",
            "Don't show at login",
            "- Reached level 12",
            "- Gathered 4× Copper Ore",
        })
        T.eq(ns.Store:GetState("lastRecapDay"), 20261003)
    end)

    it("appears once a day", function()
        playedYesterday()
        Stubs.Relog({ now = Stubs.Now() + DAY / 2 })
        Stubs.Advance(3)
        recapFrame():Hide()
        Stubs.Advance(600)
        Stubs.Relog()
        Stubs.Advance(3)
        T.falsy(recapFrame() and recapFrame():IsShown())
    end)

    it("doesn't appear after a /reload or when switched off", function()
        playedYesterday()
        Stubs.Relog({ now = Stubs.Now() + DAY / 2 }, true)
        Stubs.Advance(3)
        T.eq(recapFrame(), nil, "reload")

        playedYesterday()
        Stubs.ns.Options:Set("showLoginRecap", false)
        Stubs.Relog({ now = Stubs.Now() + DAY / 2 })
        Stubs.Advance(3)
        T.eq(recapFrame(), nil, "setting off")
    end)

    it("stays away when there is nothing to tell", function()
        Stubs.LoadAddon()
        Stubs.Login()
        Stubs.Advance(600)
        Stubs.Relog({ now = Stubs.Now() + DAY })
        Stubs.Advance(3)
        T.eq(recapFrame(), nil)
    end)

    it("leaves out simulated entries", function()
        local ns = Stubs.LoadAddon({ now = os.time({ year = 2026, month = 10, day = 2, hour = 20 }) })
        Stubs.Login()
        ns.Slash:Handle("dev")
        ns.Slash:Handle("simulate LEVEL_UP level=30")
        Stubs.Advance(600)
        ns = Stubs.Relog({ now = Stubs.Now() + DAY })
        T.eq(ns.LoginRecap:Collect(true), nil)
    end)

    it("the checkbox switches it off, /ws recap shows it anyway", function()
        playedYesterday()
        local ns = Stubs.Relog({ now = Stubs.Now() + DAY / 2 })
        Stubs.Advance(3)
        local checkbox
        for _, frame in ipairs(Stubs.state.frames) do
            if frame.scripts.OnClick and frame.GetChecked and frame.checked ~= nil then checkbox = frame end
        end
        checkbox:SetChecked(true)
        checkbox:Click()
        T.eq(ns.Options:Get("showLoginRecap"), false)
        recapFrame():Hide()
        ns.Slash:Handle("recap")
        T.truthy(recapFrame():IsShown())
    end)
end)
