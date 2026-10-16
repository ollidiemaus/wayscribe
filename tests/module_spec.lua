local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

describe("error boundary", function()
    it("disables a module after repeated errors and unregisters its events", function()
        local ns = Stubs.LoadAddon()
        local module = ns.NewModule("broken")
        function module:OnEnable() self:RegisterEvent("BAG_UPDATE") end
        function module:BAG_UPDATE() error("bug in handler") end
        module:Enable()

        for _ = 1, 9 do Stubs.Fire("BAG_UPDATE") end
        T.truthy(module.enabled, "still enabled after 9 errors")
        Stubs.Fire("BAG_UPDATE")
        T.falsy(module.enabled, "disabled after 10 errors")
        T.falsy(module.frame:IsEventRegistered("BAG_UPDATE"))
        T.eq(#ns.Log:GetEntries(), 10)
        T.truthy(ns.Log:GetEntries()[1].message:find("bug in handler"))
    end)

    it("does not leave a half-enabled module listening", function()
        local ns = Stubs.LoadAddon()
        local module = ns.NewModule("half")
        function module:OnEnable()
            self:RegisterEvent("BAG_UPDATE")
            error("failed during enable")
        end
        T.falsy(module:Enable())
        T.falsy(module.enabled)
        T.falsy(module.frame:IsEventRegistered("BAG_UPDATE"))
    end)

    it("logs secret error values without touching them", function()
        local ns = Stubs.LoadAddon()
        local module = ns.NewModule("secretive")
        module.enabled = true
        function module:BAG_UPDATE() error(Stubs.SECRET) end
        module:RegisterEvent("BAG_UPDATE")
        Stubs.Fire("BAG_UPDATE")
        T.truthy(ns.Log:GetEntries()[1].message:find("<secret value>"))
    end)

    it("TryRegisterEvent survives events this client doesn't have", function()
        local ns = Stubs.LoadAddon({ unknownEvents = { LFG_COMPLETION_REWARD = true } })
        local module = ns.NewModule("optional")
        T.falsy(module:TryRegisterEvent("LFG_COMPLETION_REWARD"))
        T.truthy(module:TryRegisterEvent("ENCOUNTER_END"))
    end)
end)

describe("tracker settings", function()
    it("a tracker switched off in settings registers nothing", function()
        local ns = Stubs.LoadAddon({ accountDB = { schema = 1, settings = { trackers = { Level = false } }, log = {}, characters = {} } })
        Stubs.Login()
        local level = ns.Trackers:Get("Level")
        T.falsy(level.enabled)
        T.falsy(level.frame and level.frame:IsEventRegistered("PLAYER_LEVEL_UP"))

        ns.Trackers:SetWanted("Level", true)
        T.truthy(level.enabled)
        T.truthy(level.frame:IsEventRegistered("PLAYER_LEVEL_UP"))
        T.eq(ns.accountDB.settings.trackers.Level, true)
    end)

    it("internal trackers can't be switched off", function()
        local ns = Stubs.LoadAddon()
        Stubs.Login()
        ns.Trackers:SetWanted("Session", false)
        T.truthy(ns.Trackers:Get("Session").enabled)
    end)

    it("never registers the combat log, which Forever blocks", function()
        Stubs.LoadAddon()
        Stubs.Login()
        for _, frame in ipairs(Stubs.state.frames) do
            T.falsy(frame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED"))
        end
    end)
end)

describe("debounce", function()
    -- A switched-on module whose debounced work notes when it ran.
    local function noisy()
        local ns = Stubs.LoadAddon()
        local module = ns.NewModule("noisy")
        module.runs = {}
        function module:Work() self.runs[#self.runs + 1] = Stubs.Now() end
        module:Enable()
        return module, ns
    end

    it("runs the work once per burst, on one timer", function()
        local module = noisy()
        local start, armed = Stubs.Now(), Stubs.state.timersArmed
        for _ = 1, 20 do module:Debounce("work", 1, module.Work) end
        T.eq(Stubs.state.timersArmed - armed, 1, "one timer for twenty requests")
        Stubs.Advance(1)
        T.same(module.runs, { start + 1 })
        Stubs.Advance(5)
        T.eq(#module.runs, 1, "and only once")
    end)

    it("counts the delay from the last request, on one timer more for a burst spread over time", function()
        local module = noisy()
        local start, armed = Stubs.Now(), Stubs.state.timersArmed
        for _ = 1, 4 do
            module:Debounce("work", 1, module.Work)
            Stubs.Advance(0.25)
        end
        Stubs.Advance(0.5)
        T.same(module.runs, {}, "not a delay after the first request")
        Stubs.Advance(0.25)
        T.same(module.runs, { start + 1.75 }, "a delay after the last one, at 0.75")
        T.eq(Stubs.state.timersArmed - armed, 2)
    end)

    it("runs the work once when time jumps past its due time", function()
        local module = noisy()
        for _ = 1, 4 do
            module:Debounce("work", 1, module.Work)
            Stubs.Advance(0.25)
        end
        Stubs.Advance(30)
        T.eq(#module.runs, 1, "in that step")
        Stubs.Advance(30)
        T.eq(#module.runs, 1, "and only then")
    end)

    it("drops the work when the module is switched off before it runs, even if switched on again", function()
        local module = noisy()
        module:Debounce("work", 1, module.Work)
        module:Disable()
        Stubs.Advance(1)
        T.same(module.runs, {}, "off when it was due")
        module:Enable()
        module:Debounce("work", 1, module.Work)
        module:Disable()
        module:Enable()
        Stubs.Advance(5)
        T.same(module.runs, {}, "on again when it was due")
        module:Debounce("work", 1, module.Work)
        Stubs.Advance(1)
        T.eq(#module.runs, 1, "a request after that runs")
    end)

    it("waits the last request's delay, longer or shorter than the one before", function()
        local module = noisy()
        local start = Stubs.Now()
        module:Debounce("work", 1, module.Work)
        module:Debounce("work", 5, module.Work)
        Stubs.Advance(4)
        T.same(module.runs, {}, "the longer delay wins")
        Stubs.Advance(1)
        T.same(module.runs, { start + 5 })

        module:Debounce("work", 5, module.Work)
        Stubs.Advance(1)
        module:Debounce("work", 1, module.Work)
        Stubs.Advance(1)
        T.same(module.runs, { start + 5, start + 7 }, "the shorter one too")
        Stubs.Advance(5)
        T.eq(#module.runs, 2, "and the longer request's timer runs nothing")
    end)

    it("keeps each key apart, and catches the work's errors", function()
        local module, ns = noisy()
        function module:Fail() error("bug in work") end
        module:Debounce("work", 1, module.Work)
        module:Debounce("fail", 1, module.Fail)
        Stubs.Advance(1)
        T.eq(#module.runs, 1)
        T.truthy(ns.Log:GetEntries()[1].message:find("timer: .*bug in work"))
    end)
end)
