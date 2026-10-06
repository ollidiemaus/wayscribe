local _, ns = ...
local L = ns.L

-- Wayscribe's page under Options > AddOns (docs/ARCHITECTURE.md §7). The tracking section is built
-- from the tracker registry, so a new tracker gets its toggle without touching this file. Every
-- setting is a proxy onto ns.Options or ns.Trackers, so the page never owns data. Without the
-- Settings API (or if it changed), the page is skipped and /ws covers everything.
local SettingsPanel = {}
ns.SettingsPanel = SettingsPanel

local DATE_FORMATS = { "", "YYYY-MM-DD", "DD.MM.YYYY", "DD/MM/YYYY", "MM/DD/YYYY" }
local RESET_POPUP = "WAYSCRIBE_RESET_JOURNAL"

local function varType(name)
    return Settings.VarType and Settings.VarType[name] or name:lower()
end

local function addHeader(layout, text)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function addCheckbox(category, key, label, tooltip, default, get, set)
    local setting = Settings.RegisterProxySetting(category, "Wayscribe_" .. key, varType("Boolean"), label, default, get, set)
    local create = Settings.CreateCheckbox or Settings.CreateCheckBox
    create(category, setting, tooltip)
end

local function addButton(layout, label, buttonText, onClick, tooltip)
    layout:AddInitializer(CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true))
end

local function dateFormatOptions()
    local container = Settings.CreateControlTextContainer()
    local today = ns.Time.DayKey(ns.Time.Now())
    for _, pattern in ipairs(DATE_FORMATS) do
        if pattern == "" then
            container:Add(pattern, L.SETTINGS_DATE_LOCALE:format(ns.Time.FormatDay(today, L.DATE_FORMAT)))
        else
            container:Add(pattern, ns.Time.FormatDay(today, pattern))
        end
    end
    return container:GetData()
end

local function addGeneral(category, layout)
    addHeader(layout, L.SETTINGS_GENERAL)
    addCheckbox(category, "LoginRecap", L.SETTINGS_LOGIN_RECAP, L.SETTINGS_LOGIN_RECAP_TIP, true,
        function() return ns.Options:Get("showLoginRecap") end,
        function(value) ns.Options:Set("showLoginRecap", value) end)
    addCheckbox(category, "Minimap", L.SETTINGS_MINIMAP, L.SETTINGS_MINIMAP_TIP, true,
        function() return ns.Minimap:IsShown() end,
        function(value) ns.Minimap:SetShown(value) end)
    local setting = Settings.RegisterProxySetting(category, "Wayscribe_DateFormat", varType("String"),
        L.SETTINGS_DATE_FORMAT, "",
        function() return ns.Options:Get("dateFormat") end,
        function(value) ns.Options:Set("dateFormat", value) end)
    local create = Settings.CreateDropdown or Settings.CreateDropDown
    create(category, setting, dateFormatOptions, L.SETTINGS_DATE_FORMAT_TIP)
end

local function addTracking(category, layout)
    addHeader(layout, L.SETTINGS_TRACKING)
    for _, tracker in ipairs(ns.Trackers.list) do
        if not tracker.internal then
            addCheckbox(category, "Tracker_" .. tracker.id, tracker.label, tracker.tooltip, tracker.default,
                function() return ns.Trackers:IsWanted(tracker) end,
                function(value) ns.Trackers:SetWanted(tracker.id, value) end)
        end
    end
end

local function confirmReset()
    StaticPopupDialogs[RESET_POPUP] = StaticPopupDialogs[RESET_POPUP] or {
        text = L.RESET_CONFIRM,
        button1 = L.RESET_ACCEPT,
        button2 = L.CANCEL,
        OnAccept = function()
            if ns.Schema:ResetCharacter() then
                ReloadUI()
            else
                ns.Print(L.SAFE_MODE_BANNER:format(tostring(ns.safeMode)))
            end
        end,
        showAlert = true,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show(RESET_POPUP)
end

local function addData(layout)
    addHeader(layout, L.SETTINGS_DATA)
    addButton(layout, L.SETTINGS_STATS, L.SETTINGS_SHOW, function() ns.Slash:Handle("stats") end, L.SETTINGS_STATS_TIP)
    addButton(layout, L.SETTINGS_LOG, L.SETTINGS_SHOW, function() ns.Slash:Handle("log") end, L.SETTINGS_LOG_TIP)
    addButton(layout, L.SETTINGS_REBUILD, L.SETTINGS_REBUILD_BUTTON, function() ns.Slash:Handle("rebuild") end,
        L.SETTINGS_REBUILD_TIP)
    addButton(layout, L.SETTINGS_RESET, L.SETTINGS_RESET_BUTTON, confirmReset, L.SETTINGS_RESET_TIP)
end

function SettingsPanel:Register()
    if self.category or not ns.Compat.has.settingsAPI then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory(L.ADDON_TITLE)
    addGeneral(category, layout)
    addTracking(category, layout)
    addData(layout)
    Settings.RegisterAddOnCategory(category)
    self.category = category
end

function SettingsPanel:Open()
    local category = self.category
    if not (category and ns.SafeCall("settings:open", Settings.OpenToCategory, category:GetID())) then
        ns.Print(L.SETTINGS_UNAVAILABLE)
    end
end

ns.Bus:On("READY", SettingsPanel, SettingsPanel.Register)
