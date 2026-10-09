local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

-- The parts of the 11.x Settings API the panel uses, recording what was registered.
local function installSettingsAPI()
    local api = { settings = {}, initializers = {}, dropdowns = {} }
    _G.Settings = {
        VarType = { Boolean = "boolean", String = "string" },
        RegisterVerticalLayoutCategory = function(name)
            api.category = { name = name, GetID = function() return 77 end }
            return api.category, { AddInitializer = function(_, init) api.initializers[#api.initializers + 1] = init end }
        end,
        RegisterProxySetting = function(_, variable, varType, name, default, get, set)
            local setting = { variable = variable, varType = varType, name = name, default = default, get = get, set = set }
            api.settings[variable] = setting
            return setting
        end,
        CreateCheckbox = function(_, setting) setting.control = "checkbox" end,
        CreateDropdown = function(_, setting, options) setting.control = "dropdown"; api.dropdowns[setting.variable] = options end,
        CreateControlTextContainer = function()
            local container = { data = {} }
            function container:Add(value, label) self.data[#self.data + 1] = { value = value, label = label } end
            function container:GetData() return self.data end
            return container
        end,
        RegisterAddOnCategory = function(category) api.registered = category end,
        OpenToCategory = function(id) api.opened = id end,
    }
    _G.CreateSettingsListSectionHeaderInitializer = function(text) return { header = text } end
    _G.CreateSettingsButtonInitializer = function(name, _, onClick) return { button = name, onClick = onClick } end
    return api
end

-- LibStub with LibDataBroker and LibDBIcon doubles.
local function installIconLibraries()
    local libs = { icon = { shown = {} } }
    libs.broker = { NewDataObject = function(_, name, object) libs.object = object; libs.name = name; return object end }
    function libs.icon:Register(name, _, db) self.db = db; self.shown[name] = not db.hide end
    function libs.icon:Show(name) self.shown[name] = true end
    function libs.icon:Hide(name) self.shown[name] = false end
    libs.icon.layout = {}
    for _, part in ipairs({ "Border", "Background", "Icon" }) do
        libs.icon["SetButton" .. part] = function(self, name, texture, size, point, x, y)
            self.layout[part] = { name, texture, size, point, x, y }
        end
    end
    _G.LibStub = function(major)
        if major == "LibDataBroker-1.1" then return libs.broker, 6 end
        if major == "LibDBIcon-1.0" then return libs.icon, 56 end
    end
    return libs
end

local function start(opts)
    local ns = Stubs.LoadAddon(opts)
    local api = installSettingsAPI()
    local libs = installIconLibraries()
    Stubs.Login()
    return ns, api, libs
end

describe("settings page", function()
    it("registers one toggle per tracker, built from the registry", function()
        local ns, api = start()
        T.eq(api.registered, api.category)
        T.eq(api.category.name, "Wayscribe")
        for _, id in ipairs({ "Level", "Professions", "Gathering", "Bosses", "Dungeons" }) do
            local setting = api.settings["Wayscribe_Tracker_" .. id]
            T.truthy(setting, id)
            T.eq(setting.control, "checkbox")
            T.eq(setting.get(), true)
        end
        T.eq(api.settings.Wayscribe_Tracker_Session, nil, "internal trackers have no toggle")

        api.settings.Wayscribe_Tracker_Gathering.set(false)
        T.falsy(ns.Trackers:Get("Gathering").enabled)
        T.eq(api.settings.Wayscribe_Tracker_Gathering.get(), false)
        T.eq(ns.accountDB.settings.trackers.Gathering, false)
    end)

    it("stores the date format and only real choices", function()
        local ns, api = start()
        local setting = api.settings.Wayscribe_DateFormat
        local options = api.dropdowns.Wayscribe_DateFormat()
        T.eq(options[1].value, "")
        T.eq(options[1].label, "Language default (2026-10-03)")
        T.eq(options[3].label, "03.10.2026")

        setting.set("DD.MM.YYYY")
        T.eq(ns.Time.FormatDay(20261003), "03.10.2026")
        setting.set("")
        T.eq(ns.accountDB.settings.dateFormat, nil)
        T.eq(ns.Time.FormatDay(20261003), "2026-10-03")
    end)

    it("the login recap toggle is saved", function()
        local ns, api = start()
        api.settings.Wayscribe_LoginRecap.set(false)
        T.eq(ns.accountDB.settings.showLoginRecap, false)
        T.eq(api.settings.Wayscribe_LoginRecap.get(), false)
    end)

    it("has data buttons that run the slash commands", function()
        local _, api = start()
        local buttons = {}
        for _, init in ipairs(api.initializers) do
            if init.button then buttons[init.button] = init end
        end
        T.truthy(buttons["Delete all trails"])
        T.truthy(buttons["Reset journal"])
        buttons["Export journal"].onClick()
        T.truthy(_G.WayscribeExportFrame:IsShown())
        buttons["Back up journal"].onClick()
        T.truthy(_G.WayscribeBackupFrame:IsShown())
        buttons["Restore backup"].onClick()
        T.truthy(_G.WayscribeRestoreFrame:IsShown())
        buttons["Journal statistics"].onClick()
        local printed = Stubs.Printed()
        T.truthy(printed[#printed - 3]:find("entries on"))
        T.eq(printed[#printed - 2]:match(": (.*)$"), "Notes: 0, 0 of them on the map.")
        T.truthy(printed[#printed - 1]:find("Footsteps: 0 trails"))
        T.truthy(printed[#printed]:find("Saved file: journal about"))
    end)

    it("has a notes section: whether the world map shows them", function()
        local ns, api = start()
        local onMap = api.settings.Wayscribe_NotesOnMap
        T.eq(onMap.get(), true)
        onMap.set(false)
        T.eq(ns.accountDB.settings.notesOnMap, false)
        T.falsy(ns.NotesMap:IsShownOnMap())
    end)

    it("has a dungeon maps section: whether the journal shows them", function()
        local ns, api = start()
        local shown = api.settings.Wayscribe_DungeonMaps
        T.eq(shown.get(), true)
        shown.set(false)
        T.eq(ns.accountDB.settings.dungeonMaps, false)
        T.truthy(ns.Trackers:IsWanted(ns.Trackers:Get("DungeonMaps")), "the tracker stays on")
    end)

    it("has a footsteps section: what the map shows, flights, and deleting trails", function()
        local ns, api = start()
        local mode = api.settings.Wayscribe_FootstepsMode
        T.eq(mode.get(), "today")
        local labels = {}
        for i, option in ipairs(api.dropdowns.Wayscribe_FootstepsMode()) do labels[i] = option.label end
        T.same(labels, { "Today", "Last 7 days", "All", "Off" })
        mode.set("all")
        T.eq(ns.accountDB.settings.footstepsMode, "all")

        local flights = api.settings.Wayscribe_FootstepsFlights
        T.eq(flights.get(), true)
        flights.set(false)
        T.eq(ns.accountDB.settings.footstepsFlights, false)
        T.truthy(api.settings.Wayscribe_Tracker_Footsteps, "Footsteps can be turned off like any tracker")

        _G.StaticPopupDialogs = {}
        local shown
        _G.StaticPopup_Show = function(name) shown = name end
        for _, init in ipairs(api.initializers) do
            if init.button == "Delete all trails" then init.onClick() end
        end
        T.eq(shown, "WAYSCRIBE_DELETE_TRAILS")
        ns.Paths:AddSegment({ c = 1, t = Stubs.Now(), d = 5, p = ns.Codec.EncodePath({ 0, 0, 10, 0 }) })
        StaticPopupDialogs[shown].OnAccept()
        T.eq(ns.Paths:GetStats().segments, 0)
        _G.StaticPopupDialogs, _G.StaticPopup_Show = nil, nil
    end)

    it("/ws settings opens the page, or says it isn't there", function()
        local ns, api = start()
        ns.Slash:Handle("settings")
        T.eq(api.opened, 77)

        ns = Stubs.LoadAddon()
        Stubs.Login()
        ns.Slash:Handle("settings")
        local printed = Stubs.Printed()
        T.truthy(printed[#printed]:find("isn't available"))
    end)
end)

describe("minimap button", function()
    it("registers a launcher that remembers its position table", function()
        local ns, _, libs = start()
        T.eq(libs.name, "Wayscribe")
        T.eq(libs.icon.db, ns.accountDB.settings.minimap)
        T.truthy(libs.icon.shown.Wayscribe)
    end)

    it("centers its icon in Forever's ring, laid out like Blizzard's world map button", function()
        local ns, _, libs = start()
        T.eq(libs.object.icon, ns.Theme.ICON_SMALL)
        T.same(libs.icon.layout.Border, { "Wayscribe", nil, 54 })
        T.same(libs.icon.layout.Background, { "Wayscribe", nil, 25, "TOPLEFT", 3, -4 })
        T.same(libs.icon.layout.Icon, { "Wayscribe", nil, 20, "TOPLEFT", 7, -6 })
    end)

    it("keeps LibDBIcon's own layout outside Forever", function()
        local _, _, libs = start({ interface = 120100 })
        T.truthy(libs.icon.shown.Wayscribe)
        T.eq(next(libs.icon.layout), nil)
    end)

    it("can be hidden from the settings page", function()
        local ns, api, libs = start()
        api.settings.Wayscribe_Minimap.set(false)
        T.falsy(libs.icon.shown.Wayscribe)
        T.eq(ns.accountDB.settings.minimap.hide, true)
        T.eq(api.settings.Wayscribe_Minimap.get(), false)
    end)

    it("left-click toggles the journal, right-click opens settings", function()
        local _, api, libs = start()
        libs.object.OnClick(nil, "LeftButton")
        T.truthy(_G.WayscribeJournalFrame:IsShown())
        libs.object.OnClick(nil, "RightButton")
        T.eq(api.opened, 77)
    end)

    it("works without the libraries", function()
        local ns = Stubs.LoadAddon()
        Stubs.Login()
        T.eq(#ns.Log:GetEntries(), 0)
        ns.Minimap:SetShown(false)
        T.eq(ns.accountDB.settings.minimap.hide, true)
    end)
end)

describe("other ways in", function()
    it("the addon compartment and the key binding toggle the journal", function()
        start()
        Wayscribe_OnAddonCompartmentClick("Wayscribe", "LeftButton")
        T.truthy(_G.WayscribeJournalFrame:IsShown())
        Wayscribe_ToggleJournal()
        T.falsy(_G.WayscribeJournalFrame:IsShown())
        T.eq(BINDING_NAME_WAYSCRIBE_TOGGLE, "Open or close the journal")
    end)
end)

describe("reset", function()
    it("starts an empty journal that the next login accepts", function()
        local ns = Stubs.LoadAddon({ level = 11 })
        Stubs.Login()
        Stubs.Fire("PLAYER_LEVEL_UP", 12)
        T.truthy(ns.Schema:ResetCharacter())
        T.eq(ns.Store:GetStats().records, 0)
        ns = Stubs.Relog()
        T.eq(ns.safeMode, nil, "the canary agrees with the empty journal")
        T.eq(ns.charDB.meta.seq, 0)
    end)

    it("refuses in safe mode", function()
        local ns = Stubs.LoadAddon()
        Stubs.Login()
        ns.safeMode = "test"
        T.falsy(ns.Schema:ResetCharacter())
    end)
end)
