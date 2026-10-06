local _, ns = ...
local L, Compat, Store, Time, RecordTypes, Theme, DayView =
    ns.L, ns.Compat, ns.Store, ns.Time, ns.RecordTypes, ns.Theme, ns.DayView

-- The journal window, built like the default UI's spellbook (docs/ARCHITECTURE.md §7): a portrait
-- frame with a filter menu in its top bar and an open book below. The left page lists the days
-- (newest first, grouped by month), the right page shows the selected day, with page controls to
-- turn to the next older or newer one. The list is a virtualized ScrollBox where the client has
-- one; otherwise a fixed set of rows follows the selection.
local Journal = {}
ns.Journal = Journal

local WIDTH, HEIGHT = 900, 620
local MIN_WIDTH, MIN_HEIGHT = 720, 480
local TITLE_BAR = 22   -- the frame's title bar
local TOP_BAR = 60     -- title bar plus a bar for the filter, when the page art has none
local BOOK_SIDE = 7    -- frame border around the pages
local ROW_HEIGHT = 24
local CHIP_HEIGHT = 20
local CHIP_WIDTH = 96
local GOLD, GREY = { 1, 0.82, 0 }, { 0.5, 0.5, 0.5 } -- text on the frame's dark top bar

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

------------------------------------------------------------------------------------------------
-- Filters, saved per account: settings.journalHidden[category] = true hides a category.

local function hiddenCategories()
    return ns.Options:Table("journalHidden")
end

local function visibilityFilter()
    local hidden = hiddenCategories()
    return function(category)
        return hidden[category] ~= true
    end
end

function Journal:IsCategoryShown(category)
    return hiddenCategories()[category] ~= true
end

function Journal:SetCategoryShown(category, shown)
    hiddenCategories()[category] = not shown or nil
    state.listDirty = true
    self:Refresh()
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
-- Day list (the left page)

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
        row.selected = Theme.Highlight(row)
        Theme.Fill(row, Theme.INK, "HIGHLIGHT", 0, 0.06)
        row.label = Theme.Text(row, "text")
        row.label:SetPoint("LEFT", 10, 0)
        row.detail = Theme.Text(row, "small", Theme.INK_FADED)
        row.detail:SetPoint("RIGHT", -8, 0)
        row.detail:SetJustifyH("RIGHT")
        row:SetScript("OnClick", onRowClick)
    end
    row.dayKey = element.dayKey
    if element.monthKey then
        Theme.Style(row.label, "heading")
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

-- The list's area on the left page's paper, below its header.
local function listInsets()
    local insets = DayView.INSETS
    return insets.outer, insets.top + 64, insets.spine, 14
end

local function createScrollList(page)
    local left, top, right, bottom = listInsets()
    local box = CreateFrame("Frame", nil, page, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", left - 10, -top)
    box:SetPoint("BOTTOMRIGHT", -(right + 16), bottom)
    local bar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", initRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    if ScrollUtil.AddManagedScrollBarVisibilityBehavior then
        ScrollUtil.AddManagedScrollBarVisibilityBehavior(box, bar)
    end
    ui.scrollBox = box
end

-- Without a ScrollBox: as many rows as fit, showing the part of the list around the selection.
local function showFixedList()
    local left, top, right, bottom = listInsets()
    local available = (ui.paperHeight or 0) - top - bottom
    local count = math.max(1, math.floor(available / ROW_HEIGHT))
    local selectedIndex = indexOf(state.elements, state.byDay[state.selected]) or 1
    local first = math.max(1, math.min(selectedIndex - math.floor(count / 2), #state.elements - count + 1))
    ui.fixedRows = ui.fixedRows or {}
    for i = 1, math.max(count, #ui.fixedRows) do
        local element = i <= count and state.elements[first + i - 1]
        local row = ui.fixedRows[i]
        if element then
            if not row then
                row = CreateFrame("Button", nil, ui.listPaper)
                row:SetHeight(ROW_HEIGHT)
                row:SetPoint("TOPLEFT", left - 10, -(top + (i - 1) * ROW_HEIGHT))
                row:SetPoint("TOPRIGHT", -right, -(top + (i - 1) * ROW_HEIGHT))
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

-- "Scoopz's journal" above the list, like a spellbook category header.
local function createListHeader(paper)
    local insets = DayView.INSETS
    ui.listTitle = Theme.Text(paper, "title")
    ui.listTitle:SetPoint("TOPLEFT", insets.outer, -insets.top)
    ui.listTitle:SetPoint("TOPRIGHT", -insets.spine, -insets.top)
    ui.listTitle:SetWordWrap(false)
    local divider = Theme.Divider(paper)
    divider:SetPoint("TOPLEFT", ui.listTitle, "BOTTOMLEFT", -12, -4)
    divider:SetPoint("TOPRIGHT", ui.listTitle, "BOTTOMRIGHT", 12, -4)
end

------------------------------------------------------------------------------------------------
-- Filter: the default UI's filter menu in the top bar, or a row of toggle chips.

local function setupFilterMenu(dropdown)
    local categories = Theme.FilterCategories(RecordTypes:Categories())
    dropdown:SetupMenu(function(_, root)
        for _, category in ipairs(categories) do
            root:CreateCheckbox(Theme.CategoryLabel(category),
                function(value) return Journal:IsCategoryShown(value) end,
                function(value) Journal:SetCategoryShown(value, not Journal:IsCategoryShown(value)) end,
                category)
        end
    end)
end

local function updateChip(chip)
    local shown = Journal:IsCategoryShown(chip.category)
    chip.shown = shown
    chip.label:SetTextColor(unpack(shown and GOLD or GREY))
    chip.marker:SetAlpha(shown and 1 or 0.25)
end

local function onChipClick(chip)
    Journal:SetCategoryShown(chip.category, not Journal:IsCategoryShown(chip.category))
    updateChip(chip)
end

local function createChip(parent, category, index)
    local chip = CreateFrame("Button", nil, parent)
    chip.category = category
    chip:SetSize(CHIP_WIDTH, CHIP_HEIGHT)
    chip:SetPoint("RIGHT", -(index - 1) * (CHIP_WIDTH + 4), 0)
    Theme.Fill(chip, { 0, 0, 0 }, "BACKGROUND", 0, 0.35)
    Theme.Fill(chip, { 1, 1, 1 }, "HIGHLIGHT", 0, 0.08)
    local color = Theme.CategoryColor(category)
    chip.marker = chip:CreateTexture(nil, "ARTWORK")
    chip.marker:SetSize(8, 8)
    chip.marker:SetPoint("LEFT", 6, 0)
    chip.marker:SetColorTexture(color[1], color[2], color[3], 1)
    chip.label = chip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chip.label:SetPoint("LEFT", chip.marker, "RIGHT", 5, 0)
    chip.label:SetText(Theme.CategoryLabel(category))
    chip:SetScript("OnClick", onChipClick)
    updateChip(chip)
    return chip
end

-- In a bar of its own above the book; layoutPages moves it into the page art's top bar.
local function createFilter(frame)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetSize(1, CHIP_HEIGHT + 4)
    bar:SetFrameLevel(frame:GetFrameLevel() + 20)
    ui.filterBar = bar
    if Compat.has.filterDropdown then
        local dropdown = CreateFrame("DropdownButton", nil, bar, "WowStyle1FilterDropdownTemplate")
        dropdown:SetPoint("RIGHT")
        setupFilterMenu(dropdown)
        ui.filter = dropdown
        return
    end
    -- Rightmost chip first, so they read left to right in category order.
    local categories = Theme.FilterCategories(RecordTypes:Categories())
    ui.chips = {}
    for i = #categories, 1, -1 do
        ui.chips[i] = createChip(bar, categories[i], #categories - i + 1)
    end
end

------------------------------------------------------------------------------------------------
-- Day page and page controls (the right page)

local function showPage()
    local page = state.selected and DayView.Build(state.selected, visibilityFilter())
    local hasDays = Store.db ~= nil and #Store:GetDayKeys() > 0
    DayView:Show(page, ui.paperWidth, hasDays and L.JOURNAL_NOTHING_SHOWN or L.JOURNAL_EMPTY)
    -- Page 1 is the oldest day, like the first page of a diary.
    local index = indexOf(state.days, state.selected)
    local pattern = type(PAGE_NUMBER_WITH_MAX) == "string" and PAGE_NUMBER_WITH_MAX or L.PAGE_NUMBER
    ui.pageText:SetText(index and pattern:format(#state.days - index + 1, #state.days) or "")
    ui.older:SetEnabled(index ~= nil and index < #state.days)
    ui.newer:SetEnabled(index ~= nil and index > 1)
    ui.pathLink:SetShown(state.selected ~= nil and ns.FootstepsMap:CanShow() and ns.Paths:HasDay(state.selected))
end

local function showTooltip(button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(button.tooltip)
    GameTooltip:Show()
end

local function hideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

-- The spellbook's page buttons (the same art as the default UI's PagingControls).
local function createPageButton(page, direction, tooltip, step)
    local button = CreateFrame("Button", nil, page)
    button:SetSize(32, 32)
    local art = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-"
    button:SetNormalTexture(art .. "Up")
    button:SetPushedTexture(art .. "Down")
    button:SetDisabledTexture(art .. "Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button.tooltip = tooltip
    button:SetScript("OnClick", function() Journal:Turn(step) end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", hideTooltip)
    return button
end

-- "Show on the map" for days with footsteps: the default UI's button, level with the page controls.
-- (Plain text in ink was too easy to miss.)
local function createPathLink(paper)
    local insets = DayView.INSETS
    local link = CreateFrame("Button", nil, paper, "UIPanelButtonTemplate")
    link:SetPoint("BOTTOMLEFT", insets.spine, insets.bottom - 35)
    link:SetText(L.FOOTSTEPS_SHOW_DAY)
    local width = link:GetTextWidth()
    link:SetSize(math.max(type(width) == "number" and width or 0, 100) + 24, 22)
    link.tooltip = L.FOOTSTEPS_SHOW_DAY_TIP
    link:SetScript("OnClick", function() Journal:ShowPath() end)
    link:SetScript("OnEnter", showTooltip)
    link:SetScript("OnLeave", hideTooltip)
    ui.pathLink = link
end

local function createPageControls(paper)
    local insets = DayView.INSETS
    ui.newer = createPageButton(paper, "Next", L.PAGE_NEWER, -1)
    ui.newer:SetPoint("BOTTOMRIGHT", -insets.outer + 6, insets.bottom - 40)
    ui.older = createPageButton(paper, "Prev", L.PAGE_OLDER, 1)
    ui.older:SetPoint("RIGHT", ui.newer, "LEFT", -4, 0)
    ui.pageText = Theme.Text(paper, "text")
    ui.pageText:SetPoint("RIGHT", ui.older, "LEFT", -8, 0)
    ui.pageText:SetJustifyH("RIGHT")
    createPathLink(paper)
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
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        saveGeometry(frame)
    end)
end

-- The default UI's portrait frame, or a plain dialog border on a client without it.
local function createFrame()
    if Compat.has.portraitFrame then
        local frame = CreateFrame("Frame", "WayscribeJournalFrame", UIParent, "PortraitFrameTemplate")
        frame:SetTitle(L.JOURNAL_TITLE)
        frame:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Book_09")
        return frame
    end
    local frame = CreateFrame("Frame", "WayscribeJournalFrame", UIParent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -14)
    title:SetText(L.JOURNAL_TITLE)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    return frame
end

local function setupWindow(frame)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
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
end

-- Two pages with a paper frame inside each: the part of the art meant for text.
local function createPages(frame)
    local book = CreateFrame("Frame", nil, frame)
    local left = CreateFrame("Frame", nil, book)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMRIGHT", book, "BOTTOM")
    ui.rims = Theme.Page(left, "left")
    local right = CreateFrame("Frame", nil, book)
    right:SetPoint("TOPLEFT", book, "TOP")
    right:SetPoint("BOTTOMRIGHT")
    ui.rightRims = Theme.Page(right, "right")
    -- Page art with its own top bar starts right under the title bar.
    ui.bookTop = ui.rims.top > 0 and TITLE_BAR or TOP_BAR
    book:SetPoint("TOPLEFT", BOOK_SIDE, -ui.bookTop)
    book:SetPoint("BOTTOMRIGHT", -BOOK_SIDE, BOOK_SIDE)
    ui.leftPage, ui.rightPage = left, right
    -- A read-only journal says why, in the top bar; on the page so the art doesn't cover it.
    ui.banner = left:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    ui.banner:SetJustifyH("LEFT")
    ui.banner:SetMaxLines(2)
    ui.listPaper = CreateFrame("Frame", nil, left)
    ui.rightPaper = CreateFrame("Frame", nil, right)

    createListHeader(ui.listPaper)
    if Compat.has.scrollBox then
        createScrollList(ui.listPaper)
    end
    DayView:Create(ui.rightPaper)
    createPageControls(ui.rightPaper)
end

-- The rims scale with the page, so the paper, the filter and the banner move on every resize.
local function layoutPages()
    local width = (ui.frame:GetWidth() - 2 * BOOK_SIDE) / 2
    local height = ui.frame:GetHeight() - ui.bookTop - BOOK_SIDE
    local left, right = ui.rims, ui.rightRims
    ui.listPaper:ClearAllPoints()
    ui.listPaper:SetPoint("TOPLEFT", left.outer * width, -left.top * height)
    ui.listPaper:SetPoint("BOTTOMRIGHT", -left.spine * width, left.bottom * height)
    ui.rightPaper:ClearAllPoints()
    ui.rightPaper:SetPoint("TOPLEFT", right.spine * width, -right.top * height)
    ui.rightPaper:SetPoint("BOTTOMRIGHT", -right.outer * width, right.bottom * height)
    ui.paperWidth = width * (1 - right.spine - right.outer)
    ui.paperHeight = height * (1 - left.top - left.bottom)

    ui.filterBar:ClearAllPoints()
    ui.banner:ClearAllPoints()
    local band = left.top * height
    if band > 0 then
        local barY = -(band - ui.filterBar:GetHeight()) / 2
        ui.filterBar:SetPoint("TOPRIGHT", ui.rightPage, "TOPRIGHT", -(right.outer * width + 12), barY)
        ui.banner:SetPoint("LEFT", ui.leftPage, "TOPLEFT", 64, -band / 2)
        ui.banner:SetPoint("RIGHT", ui.leftPage, "TOPRIGHT", -16, -band / 2)
    else
        ui.filterBar:SetPoint("TOPRIGHT", ui.frame, "TOPRIGHT", -14, -28)
        ui.banner:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", 64, -30)
        ui.banner:SetPoint("RIGHT", ui.frame, "CENTER")
    end
end

local function createWindow()
    Theme.Resolve()
    local frame = createFrame()
    ui.frame = frame
    restoreGeometry(frame)
    setupWindow(frame)
    createPages(frame)
    createFilter(frame)
    createResizeGrip(frame)
    frame:Hide()
    tinsert(UISpecialFrames, "WayscribeJournalFrame") -- closes with Escape
    frame:SetScript("OnShow", function() Journal:Refresh() end)
    frame:SetScript("OnSizeChanged", function() Journal:RequestRefresh() end)
end

local function updateHeaders()
    ui.banner:SetText(ns.safeMode and L.SAFE_MODE_BANNER:format(ns.safeMode) or "")
    local name = Store.db and Store.db.meta.name
    ui.listTitle:SetText(name and L.JOURNAL_OF:format(name) or L.JOURNAL_TITLE)
end

------------------------------------------------------------------------------------------------
-- Public

function Journal:Refresh()
    state.refreshPending = false
    if not ui.frame or not ui.frame:IsShown() then return end
    layoutPages()
    updateHeaders()
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

-- The selected day's footsteps on the world map.
function Journal:ShowPath()
    if state.selected then
        ns.SafeCall("footsteps:show", ns.FootstepsMap.ShowDay, ns.FootstepsMap, state.selected)
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
-- Whether a day has footsteps decides the page's map link.
ns.Bus:On("PATH_ADDED", Journal, Journal.RequestRefresh)
ns.Bus:On("PATH_LIVE", Journal, Journal.RequestRefresh)
ns.Bus:On("PATH_WIPED", Journal, Journal.RequestRefresh)
