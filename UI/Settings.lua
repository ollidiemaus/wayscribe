local _, ns = ...
local L = ns.L

-- Wayscribe's page under Options > AddOns (docs/ARCHITECTURE.md §7). The tracking section is built
-- from the tracker registry, so a new tracker gets its toggle without touching this file. Every
-- row gets and sets its value through ns.Options, ns.Trackers or the module that owns it, so the
-- page never owns data. Without the Settings API (or if it changed), the page is skipped and /ws
-- covers everything.
--
-- A canvas page with controls of our own, not the game's vertical list: with Forever's controller
-- interface on, a list page made the game hang when the settings closed, and so did opening the
-- game's dropdown menu (forever-notes, "The game's settings list hangs the game on close"). So in
-- that interface a dropdown steps to its next choice instead of opening the menu. The rows are
-- built at login, before the settings window is open, so the controller cursor's CreateFrame hook
-- has no open window to refresh while they're made (wow-addon-standards T10).
local SettingsPanel = {}
ns.SettingsPanel = SettingsPanel

local DATE_FORMATS = { "", "YYYY-MM-DD", "DD.MM.YYYY", "DD/MM/YYYY", "MM/DD/YYYY" }
local FOOTSTEPS_MODES = { "today", "week", "all", "off" }
local RESET_POPUP = "WAYSCRIBE_RESET_JOURNAL"
local DELETE_TRAILS_POPUP = "WAYSCRIBE_DELETE_TRAILS"

local MARGIN = 8          -- between the page's sides and the columns
local GUTTER = 24         -- between the two columns
local TOP = 54            -- the title bar above the rows
local SCROLLBAR_ROOM = 26 -- right of the rows, for the scroll bar
local HEADER_HEIGHT = 36
local SECTION_GAP = 16
local ROW_HEIGHT = 26
local LABEL_X = 7
local LABEL_GAP = 8
local DROPDOWN_WIDTH = 160
local BUTTON_HEIGHT = 22
local BUTTON_MIN_WIDTH = 90
local BUTTON_TEXT_ROOM = 24

local function showTooltip(owner, title, text)
    if not text then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddLine(text, nil, nil, nil, true)
    GameTooltip:Show()
end

local function hideTooltip()
    GameTooltip:Hide()
end

local function playToggle(checked)
    if PlaySound and SOUNDKIT then
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end
end

------------------------------------------------------------------------------------------------
-- The page: rows in two columns ("left", "right") or across both ("wide"), on a scroll child.

local Page = {}
Page.__index = Page

local function newPage(title)
    local frame = CreateFrame("Frame")
    frame:Hide()
    local page = setmetatable({ frame = frame, controls = {}, y = { left = 0, right = 0 } }, Page)

    local titleText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -22)
    titleText:SetJustifyH("LEFT")
    titleText:SetText(title)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOP", frame, "TOP", 0, -50)

    local template = ns.Compat.HasTemplate("ScrollFrameTemplate") ~= false and "ScrollFrameTemplate"
        or "UIPanelScrollFrameTemplate"
    local scroll = CreateFrame("ScrollFrame", nil, frame, template)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -TOP)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SCROLLBAR_ROOM, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    page.content = content

    frame:SetScript("OnShow", function() page:Refresh() end)
    return page
end

-- The row named label, or nil (for tests and /ws).
function Page:Find(label)
    for _, control in ipairs(self.controls) do
        if control.label == label then return control end
    end
end

function Page:Height()
    return math.max(self.y.left, self.y.right)
end

function Page:Refresh()
    for _, control in ipairs(self.controls) do
        if control.refresh then control.refresh() end
    end
end

local function newRow(page, column, height)
    local row = CreateFrame("Frame", nil, page.content)
    local content = page.content
    if column == "wide" then
        local y = page:Height()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", MARGIN, -y)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -MARGIN, -y)
        page.y.left, page.y.right = y + height, y + height
    else
        local y = page.y[column]
        if column == "left" then
            row:SetPoint("TOPLEFT", content, "TOPLEFT", MARGIN, -y)
            row:SetPoint("TOPRIGHT", content, "TOP", -GUTTER / 2, -y)
        else
            row:SetPoint("TOPLEFT", content, "TOP", GUTTER / 2, -y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -MARGIN, -y)
        end
        page.y[column] = y + height
    end
    row:SetHeight(height)
    content:SetHeight(page:Height())
    return row
end

-- Lets both columns go on below whatever either holds so far.
function Page:Align()
    local y = self:Height()
    self.y.left, self.y.right = y, y
end

function Page:Header(column, text)
    local y = column == "wide" and self:Height() or self.y[column]
    if y > 0 then
        if column == "wide" then
            self.y.left, self.y.right = y + SECTION_GAP, y + SECTION_GAP
        else
            self.y[column] = y + SECTION_GAP
        end
    end
    local row = newRow(self, column, HEADER_HEIGHT)
    local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", LABEL_X, 8)
    title:SetPoint("RIGHT", row, "RIGHT")
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText(text)
end

-- A row with a name on the left, a hover highlight and a tooltip; the control goes on its right.
local function optionRow(page, column, label, tooltip)
    local row = newRow(page, column, ROW_HEIGHT)
    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints(row)
    highlight:SetColorTexture(1, 1, 1, 0.1)
    highlight:Hide()
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", row, "LEFT", LABEL_X, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetText(label)

    local control = { row = row, text = text, label = label }
    function control.enter()
        highlight:Show()
        showTooltip(row, label, tooltip)
    end
    function control.leave()
        highlight:Hide()
        hideTooltip()
    end
    row:EnableMouse(true)
    row:SetScript("OnEnter", control.enter)
    row:SetScript("OnLeave", control.leave)
    page.controls[#page.controls + 1] = control
    return control
end

local function place(control, widget)
    widget:SetPoint("RIGHT", control.row, "RIGHT", 0, 0)
    control.text:SetPoint("RIGHT", widget, "LEFT", -LABEL_GAP, 0)
end

-- get() returns true or false; set(value) stores it. A click on the row toggles it too.
function Page:Checkbox(column, label, tooltip, get, set)
    local control = optionRow(self, column, label, tooltip)
    control.kind, control.get, control.set = "checkbox", get, set
    local template = ns.Compat.HasTemplate("SettingsCheckboxTemplate") ~= false and "SettingsCheckboxTemplate"
        or "UICheckButtonTemplate"
    local checkbox = CreateFrame("CheckButton", nil, control.row, template)
    checkbox:SetScript("OnClick", function(button)
        local checked = button:GetChecked() and true or false
        set(checked)
        playToggle(checked)
        checkbox:SetChecked(get() == true)
    end)
    checkbox:SetScript("OnEnter", control.enter)
    checkbox:SetScript("OnLeave", control.leave)
    control.row:SetScript("OnMouseUp", function()
        if checkbox:IsEnabled() then checkbox:Click() end
    end)
    function control.refresh() checkbox:SetChecked(get() == true) end
    place(control, checkbox)
end

local function nextChoice(value, choices)
    for index, choice in ipairs(choices) do
        if choice.value == value then return choices[index % #choices + 1] end
    end
    return choices[1]
end

local function labelOf(value, choices)
    for _, choice in ipairs(choices) do
        if choice.value == value then return choice.label end
    end
    return choices[1] and choices[1].label or ""
end

-- choices() returns { { value = ..., label = ... }, ... } in menu order (asked again on each
-- refresh and menu, so a label can show today's date). With the controller interface on, or
-- without the game's dropdown, a click steps to the next choice instead of opening a menu.
function Page:Dropdown(column, label, tooltip, get, set, choices)
    local control = optionRow(self, column, label, tooltip)
    control.kind, control.get, control.set, control.choices = "dropdown", get, set, choices
    local dropdown
    local function step()
        set(nextChoice(get(), choices()).value)
        control.refresh()
    end
    if ns.Compat.has.dropdownButton then
        dropdown = CreateFrame("DropdownButton", nil, control.row, "WowStyle2DropdownTemplate")
        dropdown:SetWidth(DROPDOWN_WIDTH)
        dropdown:SetupMenu(function(_, root)
            local create = root.CreateHighlightRadio or root.CreateRadio
            for _, choice in ipairs(choices()) do
                create(root, choice.label,
                    function() return get() == choice.value end,
                    function() set(choice.value) end)
            end
        end)
        local openMenu = dropdown.OpenMenu
        function dropdown:OpenMenu(...)
            if not ns.Compat.IsControllerUI() then return openMenu(self, ...) end
            if self:IsEnabled() then step() end
        end
        dropdown:HookScript("OnEnter", control.enter)
        dropdown:HookScript("OnLeave", control.leave)
        function control.refresh()
            dropdown:GenerateMenu()
        end
    else
        dropdown = CreateFrame("Button", nil, control.row, "UIPanelButtonTemplate")
        dropdown:SetSize(DROPDOWN_WIDTH, BUTTON_HEIGHT)
        dropdown:SetScript("OnClick", step)
        dropdown:SetScript("OnEnter", control.enter)
        dropdown:SetScript("OnLeave", control.leave)
        function control.refresh() dropdown:SetText(labelOf(get(), choices())) end
    end
    place(control, dropdown)
end

function Page:Button(column, label, text, tooltip, onClick)
    local control = optionRow(self, column, label, tooltip)
    control.kind, control.onClick = "button", onClick
    local button = CreateFrame("Button", nil, control.row, "UIPanelButtonTemplate")
    button:SetText(text)
    button:SetSize(math.max(BUTTON_MIN_WIDTH, button:GetTextWidth() + BUTTON_TEXT_ROOM), BUTTON_HEIGHT)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", control.enter)
    button:SetScript("OnLeave", control.leave)
    place(control, button)
end

------------------------------------------------------------------------------------------------
-- What's on it

-- A confirmation popup that runs onAccept.
local function confirm(name, text, onAccept)
    StaticPopupDialogs[name] = StaticPopupDialogs[name] or {
        text = text,
        button1 = L.RESET_ACCEPT,
        button2 = L.CANCEL,
        OnAccept = onAccept,
        showAlert = true,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show(name)
end

local function dateFormatChoices()
    local today = ns.Time.DayKey(ns.Time.Now())
    local choices = {}
    for _, pattern in ipairs(DATE_FORMATS) do
        local label
        if pattern == "" then
            label = L.SETTINGS_DATE_LOCALE:format(ns.Time.FormatDay(today, L.DATE_FORMAT))
        else
            label = ns.Time.FormatDay(today, pattern)
        end
        choices[#choices + 1] = { value = pattern, label = label }
    end
    return choices
end

local function footstepsModeChoices()
    local choices = {}
    for _, mode in ipairs(FOOTSTEPS_MODES) do
        choices[#choices + 1] = { value = mode, label = ns.FootstepsMap.ModeLabel(mode) }
    end
    return choices
end

local function option(key)
    return function() return ns.Options:Get(key) end, function(value) ns.Options:Set(key, value) end
end

local function addGeneral(page, column)
    page:Header(column, L.SETTINGS_GENERAL)
    local get, set = option("showLoginRecap")
    page:Checkbox(column, L.SETTINGS_LOGIN_RECAP, L.SETTINGS_LOGIN_RECAP_TIP, get, set)
    page:Checkbox(column, L.SETTINGS_MINIMAP, L.SETTINGS_MINIMAP_TIP,
        function() return ns.Minimap:IsShown() end,
        function(value) ns.Minimap:SetShown(value) end)
    get, set = option("dateFormat")
    page:Dropdown(column, L.SETTINGS_DATE_FORMAT, L.SETTINGS_DATE_FORMAT_TIP, get, set, dateFormatChoices)
end

local function confirmDeleteTrails()
    confirm(DELETE_TRAILS_POPUP, L.DELETE_TRAILS_CONFIRM, function()
        if not ns.Paths:Wipe() then
            ns.Print(L.SAFE_MODE_BANNER:format(tostring(ns.Paths.readOnly or ns.safeMode)))
        end
    end)
end

-- The Footsteps tracker's own toggle is in the tracking section, like every tracker's.
local function addFootsteps(page, column)
    page:Header(column, L.SETTINGS_FOOTSTEPS)
    page:Dropdown(column, L.SETTINGS_FOOTSTEPS_MODE, L.SETTINGS_FOOTSTEPS_MODE_TIP,
        function() return ns.Options:Get("footstepsMode") end,
        function(value) ns.FootstepsMap:SetMode(value) end,
        footstepsModeChoices)
    local get, set = option("footstepsFlights")
    page:Checkbox(column, L.SETTINGS_FOOTSTEPS_FLIGHTS, L.SETTINGS_FOOTSTEPS_FLIGHTS_TIP, get, set)
    page:Button(column, L.SETTINGS_FOOTSTEPS_DELETE, L.SETTINGS_FOOTSTEPS_DELETE_BUTTON,
        L.SETTINGS_FOOTSTEPS_DELETE_TIP, confirmDeleteTrails)
end

local function addNotes(page, column)
    page:Header(column, L.SETTINGS_NOTES)
    page:Checkbox(column, L.SETTINGS_NOTES_ON_MAP, L.SETTINGS_NOTES_ON_MAP_TIP,
        function() return ns.NotesMap:IsShownOnMap() end,
        function(value) ns.NotesMap:SetShownOnMap(value) end)
end

local function addMaps(page, column)
    page:Header(column, L.SETTINGS_MAPS)
    local get, set = option("dungeonMaps")
    page:Checkbox(column, L.SETTINGS_MAPS_SHOWN, L.SETTINGS_MAPS_SHOWN_TIP, get, set)
end

local function confirmReset()
    confirm(RESET_POPUP, L.RESET_CONFIRM, function()
        if ns.Schema:ResetCharacter() then
            ReloadUI()
        else
            ns.Print(L.SAFE_MODE_BANNER:format(tostring(ns.safeMode)))
        end
    end)
end

local function addData(page, column)
    page:Header(column, L.SETTINGS_DATA)
    page:Button(column, L.SETTINGS_STATS, L.SETTINGS_SHOW, L.SETTINGS_STATS_TIP,
        function() ns.Slash:Handle("stats") end)
    page:Button(column, L.SETTINGS_LOG, L.SETTINGS_SHOW, L.SETTINGS_LOG_TIP, function() ns.Slash:Handle("log") end)
    page:Button(column, L.SETTINGS_REBUILD, L.SETTINGS_REBUILD_BUTTON, L.SETTINGS_REBUILD_TIP,
        function() ns.Slash:Handle("rebuild") end)
    page:Button(column, L.SETTINGS_EXPORT, L.SETTINGS_EXPORT_BUTTON, L.SETTINGS_EXPORT_TIP,
        function() ns.Export:Open() end)
    page:Button(column, L.SETTINGS_BACKUP, L.SETTINGS_BACKUP_BUTTON, L.SETTINGS_BACKUP_TIP,
        function() ns.Export:OpenBackup() end)
    page:Button(column, L.SETTINGS_RESTORE, L.SETTINGS_RESTORE_BUTTON, L.SETTINGS_RESTORE_TIP,
        function() ns.Export:OpenRestore() end)
    page:Button(column, L.SETTINGS_RESET, L.SETTINGS_RESET_BUTTON, L.SETTINGS_RESET_TIP, confirmReset)
end

-- Every tracker the player can turn off, the first half in the left column, the rest in the right.
local function addTracking(page)
    page:Align()
    page:Header("wide", L.SETTINGS_TRACKING)
    local trackers = {}
    for _, tracker in ipairs(ns.Trackers.list) do
        if not tracker.internal then trackers[#trackers + 1] = tracker end
    end
    local half = math.ceil(#trackers / 2)
    for index, tracker in ipairs(trackers) do
        page:Checkbox(index <= half and "left" or "right", tracker.label, tracker.tooltip,
            function() return ns.Trackers:IsWanted(tracker) end,
            function(value) ns.Trackers:SetWanted(tracker.id, value) end)
    end
end

function SettingsPanel:Register()
    if self.category or not ns.Compat.has.settingsAPI then return end
    local page = newPage(L.ADDON_TITLE)
    addGeneral(page, "left")
    addFootsteps(page, "left")
    addNotes(page, "left")
    addMaps(page, "left")
    addData(page, "right")
    addTracking(page)
    local category = Settings.RegisterCanvasLayoutCategory(page.frame, L.ADDON_TITLE)
    Settings.RegisterAddOnCategory(category)
    self.page, self.category = page, category
end

-- A value changed elsewhere (the map's buttons, /ws) shows when the page is open.
function SettingsPanel:OnSettingsChanged()
    if self.page and self.page.frame:IsVisible() then self.page:Refresh() end
end

function SettingsPanel:Open()
    local category = self.category
    if not (category and ns.SafeCall("settings:open", Settings.OpenToCategory, category:GetID())) then
        ns.Print(L.SETTINGS_UNAVAILABLE)
    end
end

ns.Bus:On("READY", SettingsPanel, SettingsPanel.Register)
ns.Bus:On("SETTINGS_CHANGED", SettingsPanel, SettingsPanel.OnSettingsChanged)
