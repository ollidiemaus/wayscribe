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
