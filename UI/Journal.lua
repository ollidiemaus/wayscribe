local _, ns = ...
local L, Compat, Store, Time, RecordTypes, Theme, DayView =
    ns.L, ns.Compat, ns.Store, ns.Time, ns.RecordTypes, ns.Theme, ns.DayView

-- The journal window, drawn as a book (docs/ARCHITECTURE.md §7). The left page holds the filter
-- chips and the day list (newest first, grouped by month); the right page shows the selected day,
-- with buttons to turn to the next older or newer one. The list is a virtualized ScrollBox where
-- the client has one; otherwise a fixed set of rows follows the selection.
local Journal = {}
ns.Journal = Journal

local WIDTH, HEIGHT = 780, 540
local MIN_WIDTH, MIN_HEIGHT = 640, 400
local INSET = 14       -- leather around the pages
local TOP = 40         -- title bar
local LIST_WIDTH = 230
local SPINE = 12
local ROW_HEIGHT = 20
local CHIP_HEIGHT = 20
local CHIP_GAP = 4
local PAGE_MARGIN = 46 -- the day page's text area: page padding plus its scroll bar

local ui = {}
Journal.ui = ui
-- days: visible day keys, newest first; elements: the list rows (month headings and days);
-- byDay: dayKey -> its element; selected: the day on the right page.
local state = { days = {}, elements = {}, byDay = {}, listDirty = true }
Journal.state = state

local function indexOf(list, value)
    for i, item in ipairs(list) do
        if item == value then return i end
    end
    return nil
end

-- Filters are saved per account: settings.journalHidden[category] = true hides a category.
local function visibilityFilter()
    local hidden = ns.Options:Table("journalHidden")
    return function(category)
        return hidden[category] ~= true
    end
end

local function buildList()
    local isVisible = visibilityFilter()
    local days, elements, byDay = {}, {}, {}
    local lastMonth
    for _, dayKey in ipairs(Store.db and Store:GetDayKeys() or {}) do
        if DayView.HasVisible(dayKey, isVisible) then
            local monthKey = Time.MonthOfDay(dayKey)
            if monthKey ~= lastMonth then
                elements[#elements + 1] = { monthKey = monthKey }
                lastMonth = monthKey
            end
            local element = { dayKey = dayKey }
            elements[#elements + 1] = element
            byDay[dayKey] = element
            days[#days + 1] = dayKey
        end
    end
    state.days, state.elements, state.byDay = days, elements, byDay
    state.listDirty = false
end

------------------------------------------------------------------------------------------------
-- Day list

local function updateRow(row)
    row.selected:SetShown(row.dayKey ~= nil and row.dayKey == state.selected)
end

local function onRowClick(row)
    if row.dayKey then
        Journal:Select(row.dayKey)
    end
end

-- Called for every row the list shows; a ScrollBox reuses rows, so everything is set each time.
local function initRow(row, element)
    if not row.label then
        row.selected = Theme.Fill(row, Theme.INK, "BACKGROUND", 0, 0.12)
        Theme.Fill(row, Theme.INK, "HIGHLIGHT", 0, 0.06)
        row.label = Theme.Text(row, "text")
        row.label:SetPoint("LEFT", 8, 0)
        row.detail = Theme.Text(row, "small", Theme.INK_FADED)
        row.detail:SetPoint("RIGHT", -6, 0)
        row.detail:SetJustifyH("RIGHT")
        row:SetScript("OnClick", onRowClick)
    end
    row.dayKey = element.dayKey
    if element.monthKey then
        Theme.Style(row.label, "label")
        row.label:SetText(Time.FormatMonth(element.monthKey))
        row.detail:SetText("")
        row:EnableMouse(false)
    else
        Theme.Style(row.label, "text")
        row.label:SetText(Time.FormatListDay(element.dayKey))
        row.detail:SetText(Time.RelativeDay(element.dayKey) or "")
        row:EnableMouse(true)
    end
    updateRow(row)
end

local function createScrollList(page, top)
    local box = CreateFrame("Frame", nil, page, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", 6, -top)
    box:SetPoint("BOTTOMRIGHT", -20, 8)
    local bar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", initRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    ui.scrollBox = box
end

-- Without a ScrollBox: as many rows as fit, showing the part of the list around the selection.
local function showFixedList()
    local available = ui.frame:GetHeight() - TOP - (ui.bannerHeight or 0) - INSET - ui.listTop - 8
    local count = math.max(1, math.floor(available / ROW_HEIGHT))
    local selectedIndex = indexOf(state.elements, state.byDay[state.selected]) or 1
    local first = math.max(1, math.min(selectedIndex - math.floor(count / 2), #state.elements - count + 1))
    ui.fixedRows = ui.fixedRows or {}
    for i = 1, math.max(count, #ui.fixedRows) do
        local element = i <= count and state.elements[first + i - 1]
        local row = ui.fixedRows[i]
        if element then
            if not row then
                row = CreateFrame("Button", nil, ui.listPage)
                row:SetHeight(ROW_HEIGHT)
                row:SetPoint("TOPLEFT", 6, -(ui.listTop + (i - 1) * ROW_HEIGHT))
                row:SetPoint("TOPRIGHT", -6, -(ui.listTop + (i - 1) * ROW_HEIGHT))
                ui.fixedRows[i] = row
            end
            initRow(row, element)
            row:Show()
        elseif row then
            row:Hide()
        end
    end
end

local function showList()
    if ui.scrollBox then
        local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
        ui.scrollBox:SetDataProvider(CreateDataProvider(state.elements), retain)
    else
        showFixedList()
    end
end

local function showSelection()
    if not ui.scrollBox then
        showFixedList()
        return
    end
    ui.scrollBox:ForEachFrame(updateRow)
    local element = state.byDay[state.selected]
    if element then
        ui.scrollBox:ScrollToElementData(element, ScrollBoxConstants and ScrollBoxConstants.AlignNearest)
    end
end

------------------------------------------------------------------------------------------------
-- Filter chips

local function updateChip(chip)
    local shown = ns.Options:Table("journalHidden")[chip.category] ~= true
    chip.shown = shown
    chip.label:SetTextColor(unpack(shown and Theme.INK or Theme.INK_FADED))
    chip.marker:SetAlpha(shown and 1 or 0.25)
end

local function onChipClick(chip)
    local hidden = ns.Options:Table("journalHidden")
    hidden[chip.category] = not hidden[chip.category] or nil
    updateChip(chip)
    state.listDirty = true
    Journal:Refresh()
end

local function createChip(page, category, column, line, width)
    local chip = CreateFrame("Button", nil, page)
    chip.category = category
    chip:SetSize(width, CHIP_HEIGHT)
    chip:SetPoint("TOPLEFT", 8 + column * (width + CHIP_GAP), -(8 + line * (CHIP_HEIGHT + CHIP_GAP)))
    Theme.Fill(chip, Theme.PAPER_EDGE, "BACKGROUND", 0, 0.6)
    Theme.Fill(chip, Theme.INK, "HIGHLIGHT", 0, 0.08)
    local color = Theme.CategoryColor(category)
    chip.marker = chip:CreateTexture(nil, "ARTWORK")
    chip.marker:SetSize(8, 8)
    chip.marker:SetPoint("LEFT", 6, 0)
    chip.marker:SetColorTexture(color[1], color[2], color[3], 1)
    chip.label = Theme.Text(chip, "small")
    chip.label:SetPoint("LEFT", chip.marker, "RIGHT", 5, 0)
    chip.label:SetText(Theme.CategoryLabel(category))
    chip:SetScript("OnClick", onChipClick)
    updateChip(chip)
    return chip
end

-- Two chips per line, one per category in use. Returns the height they take.
local function createFilters(page)
    local categories = Theme.FilterCategories(RecordTypes:Categories())
    local width = (LIST_WIDTH - 16 - CHIP_GAP) / 2
    ui.chips = {}
    for i, category in ipairs(categories) do
        ui.chips[i] = createChip(page, category, (i - 1) % 2, math.floor((i - 1) / 2), width)
    end
    return 8 + math.ceil(#categories / 2) * (CHIP_HEIGHT + CHIP_GAP) + 4
end

------------------------------------------------------------------------------------------------
-- Day page and navigation

local function pageWidth()
    return ui.frame:GetWidth() - 2 * INSET - LIST_WIDTH - SPINE - PAGE_MARGIN
end

local function showPage()
    local page = state.selected and DayView.Build(state.selected, visibilityFilter())
    local hasDays = Store.db ~= nil and #Store:GetDayKeys() > 0
    DayView:Show(page, pageWidth(), hasDays and L.JOURNAL_NOTHING_SHOWN or L.JOURNAL_EMPTY)
    local index = indexOf(state.days, state.selected)
    ui.older:SetEnabled(index ~= nil and index < #state.days)
    ui.newer:SetEnabled(index ~= nil and index > 1)
end

local function createNavButton(page, text, point, x, step)
    local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    button:SetSize(100, 22)
    button:SetPoint(point, x, 10)
    button:SetText(text)
    button:SetScript("OnClick", function() Journal:Turn(step) end)
    return button
end

------------------------------------------------------------------------------------------------
-- Window

local function geometry()
    return ns.Options:Table("journal")
end

local function saveGeometry(frame)
    local saved = geometry()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if type(point) == "string" and type(x) == "number" and type(y) == "number" then
        saved.point, saved.relativePoint = point, relativePoint
        saved.x, saved.y = math.floor(x + 0.5), math.floor(y + 0.5)
    end
    saved.width, saved.height = math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5)
end

local function restoreGeometry(frame)
    local saved = geometry()
    local width = type(saved.width) == "number" and math.max(saved.width, MIN_WIDTH) or WIDTH
    local height = type(saved.height) == "number" and math.max(saved.height, MIN_HEIGHT) or HEIGHT
    frame:SetSize(width, height)
    if type(saved.point) == "string" and type(saved.x) == "number" and type(saved.y) == "number" then
        frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x, saved.y)
    else
        frame:SetPoint("CENTER")
    end
end

local function createResizeGrip(frame)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
    elseif frame.SetMinResize then
        frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
    end
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        saveGeometry(frame)
    end)
end

local function createChrome(frame)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    if frame.SetDontSavePosition then
        frame:SetDontSavePosition(true) -- the position lives in settings.journal instead
    end
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        saveGeometry(frame)
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(unpack(Theme.COVER))
    frame:SetBackdropBorderColor(unpack(Theme.COVER_EDGE))

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText(L.JOURNAL_TITLE)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    ui.banner = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.banner:SetPoint("TOPLEFT", INSET + 4, -TOP)
    ui.banner:SetPoint("TOPRIGHT", -INSET - 4, -TOP)
    ui.banner:SetJustifyH("LEFT")
    ui.banner:SetTextColor(1, 0.45, 0.4)
end

local function createPages(frame)
    ui.book = CreateFrame("Frame", nil, frame)
    local left = CreateFrame("Frame", nil, ui.book)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LIST_WIDTH)
    Theme.Page(left)
    local spine = ui.book:CreateTexture(nil, "BACKGROUND")
    spine:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    spine:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 0, 0)
    spine:SetWidth(SPINE)
    spine:SetColorTexture(unpack(Theme.SPINE))
    local right = CreateFrame("Frame", nil, ui.book)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", SPINE, 0)
    right:SetPoint("BOTTOMRIGHT")
    Theme.Page(right)

    ui.listPage = left
    ui.listTop = createFilters(left)
    if Compat.has.scrollBox then
        createScrollList(left, ui.listTop)
    end
    DayView:Create(right)
    ui.older = createNavButton(right, L.PAGE_OLDER, "BOTTOMLEFT", 16, 1)
    ui.newer = createNavButton(right, L.PAGE_NEWER, "BOTTOMRIGHT", -16, -1)
end

local function createWindow()
    local frame = CreateFrame("Frame", "WayscribeJournalFrame", UIParent, "BackdropTemplate")
    ui.frame = frame
    restoreGeometry(frame)
    createChrome(frame)
    createPages(frame)
    createResizeGrip(frame)
    frame:Hide()
    tinsert(UISpecialFrames, "WayscribeJournalFrame") -- closes with Escape
    frame:SetScript("OnShow", function() Journal:Refresh() end)
    frame:SetScript("OnSizeChanged", function() Journal:RequestRefresh() end)
end

-- A read-only journal says why, above the pages.
local function updateBanner()
    ui.banner:SetText(ns.safeMode and L.SAFE_MODE_BANNER:format(ns.safeMode) or "")
    ui.bannerHeight = ns.safeMode and (ui.banner:GetStringHeight() + 6) or 0
    ui.book:ClearAllPoints()
    ui.book:SetPoint("TOPLEFT", INSET, -(TOP + ui.bannerHeight))
    ui.book:SetPoint("BOTTOMRIGHT", -INSET, INSET)
end

------------------------------------------------------------------------------------------------
-- Public

function Journal:Refresh()
    state.refreshPending = false
    if not ui.frame or not ui.frame:IsShown() then return end
    updateBanner()
    if state.listDirty then
        -- Whoever reads the newest day keeps reading the newest day when a new one starts.
        local followNewest = state.selected == nil or state.selected == state.days[1]
        buildList()
        if followNewest or not state.byDay[state.selected] then
            state.selected = state.days[1]
        end
        showList()
    end
    showPage()
    showSelection()
end

-- Many changes in one frame (a loot window, a rebuild) cause a single redraw on the next frame.
function Journal:RequestRefresh()
    if state.refreshPending or not ui.frame or not ui.frame:IsShown() then return end
    state.refreshPending = true
    C_Timer.After(0, function() Journal:Refresh() end)
end

function Journal:Select(dayKey)
    state.selected = dayKey
    showPage()
    showSelection()
end

-- step 1 turns to the next older day, -1 to the next newer one.
function Journal:Turn(step)
    local index = indexOf(state.days, state.selected)
    local target = index and state.days[index + step]
    if not target then return end
    self:Select(target)
    if SOUNDKIT then
        Compat.Call(PlaySound, SOUNDKIT.IG_ABILITY_PAGE_TURN)
    end
end

-- Opens the journal at dayKey, or at the newest day.
function Journal:Open(dayKey)
    if not ui.frame then
        createWindow()
    end
    state.listDirty = true
    state.selected = dayKey
    state.days = {} -- so the refresh keeps dayKey instead of following the newest day
    if ui.frame:IsShown() then
        self:Refresh()
    else
        ui.frame:Show()
    end
end

function Journal:Toggle()
    if ui.frame and ui.frame:IsShown() then
        ui.frame:Hide()
    else
        self:Open()
    end
end

-- A record on a day the list doesn't show yet changes the list; otherwise only the page.
function Journal:OnRecordAdded(record)
    if not state.byDay[Time.DayKey(record.ts)] then
        state.listDirty = true
    end
    self:RequestRefresh()
end

function Journal:OnCounterChanged()
    if not state.byDay[Time.DayKey(Time.Now())] then
        state.listDirty = true
    end
    self:RequestRefresh()
end

-- Names, settings, a rebuild or safe mode can change any line.
function Journal:OnChanged()
    state.listDirty = true
    self:RequestRefresh()
end

ns.Bus:On("RECORD_ADDED", Journal, Journal.OnRecordAdded)
ns.Bus:On("COUNTER_CHANGED", Journal, Journal.OnCounterChanged)
ns.Bus:On("ITEM_NAMES_LOADED", Journal, Journal.RequestRefresh)
ns.Bus:On("SETTINGS_CHANGED", Journal, Journal.OnChanged)
ns.Bus:On("SAFE_MODE", Journal, Journal.OnChanged)
ns.Bus:On("REBUILT", Journal, Journal.OnChanged)
