local _, ns = ...
local L, Store, Time, Theme, DayView, Charted, DungeonMap =
    ns.L, ns.Store, ns.Time, ns.Theme, ns.DayView, ns.Charted, ns.DungeonMap

-- The journal's Maps tab (docs/dungeon-maps.md): the dungeons the character has been in, each a
-- map under fog that lifted where they went. The left page lists them, the right page shows the
-- open one: its name, how much is charted, and a floor of its map; the page buttons turn floors.
-- Unfolded, the map spreads across both pages (the book's spread is about 3:2, like the art).
local MapsView = {}
ns.MapsView = MapsView

local ROW_HEIGHT = 24
local LIST_TOP = 38       -- below the header
local MAP_TOP = 88        -- the map, under the title, the subtitle (two lines at most) and the floor
local SPREAD_TOP = 26     -- the unfolded map, under its title line
local BUTTON_ROW = 46     -- the paper's bottom margin, where the page controls sit

local ui = {}
MapsView.ui = ui
-- instances: the charted dungeons, by name; selected: the open one; floor: its shown floor;
-- unfolded: the map spread across both pages.
local state = { instances = {}, floor = 1 }
MapsView.state = state

local function indexOf(instanceID)
    for i, id in ipairs(state.instances) do
        if id == instanceID then return i end
    end
    return nil
end

local function nameOf(instanceID)
    local map = Charted.Map(instanceID)
    return map and Charted.Name(map) or L.UNKNOWN_INSTANCE:format(instanceID)
end

local function floorCount()
    local map = state.selected and Charted.Map(state.selected)
    return map and #map.floors or 0
end

function MapsView.Percent(instanceID)
    return L.MAPS_PERCENT:format(math.floor(Charted:Progress(instanceID) * 100 + 0.5))
end

-- "62% charted · 3 of 4 bosses found · first entered on Saturday, October 3, 2026"
function MapsView.Subtitle(instanceID)
    local map, facts = Charted.Map(instanceID), Charted:Facts(instanceID)
    local parts = { L.MAPS_CHARTED:format(math.floor(Charted:Progress(instanceID) * 100 + 0.5)) }
    local bosses, found = 0, 0
    for _, section in ipairs(map.sections) do
        if section[1] ~= "enter" and type(section[1]) == "number" then
            bosses = bosses + 1
            for _, trigger in ipairs(section) do
                if facts[trigger] then
                    found = found + 1
                    break
                end
            end
        end
    end
    if bosses > 0 then parts[#parts + 1] = L.MAPS_BOSSES:format(found, bosses) end
    local first = Charted:FirstSeen(instanceID)
    if first then parts[#parts + 1] = L.MAPS_FIRST:format(Time.FormatDay(Time.DayKey(first))) end
    return table.concat(parts, " · ")
end

-- "The Upper Study" or "Floor 2", for a map with several floors.
local function floorTitle()
    local map = Charted.Map(state.selected)
    local floor = map and map.floors[state.floor]
    if not floor or #map.floors < 2 then return "" end
    return Charted.Name(floor) or L.MAPS_FLOOR:format(state.floor)
end

------------------------------------------------------------------------------------------------
-- Selecting

function MapsView:Select(instanceID, floor)
    if state.selected ~= instanceID then state.unfolded = false end
    state.selected = instanceID
    state.floor = floor or (instanceID and Charted:CurrentFloor(instanceID)) or 1
end

-- step 1 turns back (the floor above), -1 on. Returns whether it turned.
function MapsView:Turn(step)
    local target = state.floor - step
    if target < 1 or target > floorCount() then return false end
    state.floor = target
    return true
end

function MapsView:SetUnfolded(unfolded)
    state.unfolded = unfolded == true and state.selected ~= nil
    ns.Journal:Refresh()
end

------------------------------------------------------------------------------------------------
-- The left page: the dungeons

local function onRowClick(row)
    MapsView:Select(row.instanceID)
    ns.Journal:Refresh()
end

local function initRow(row, element)
    if not row.label then
        row.selected = Theme.Highlight(row)
        Theme.Fill(row, Theme.INK, "HIGHLIGHT", 0, 0.06)
        row.detail = Theme.Text(row, "small", Theme.INK_FADED)
        row.detail:SetPoint("RIGHT", -8, 0)
        row.detail:SetJustifyH("RIGHT")
        row.label = Theme.Text(row, "text")
        row.label:SetPoint("LEFT", 8, 0)
        row.label:SetPoint("RIGHT", row.detail, "LEFT", -6, 0)
        row.label:SetWordWrap(false)
        row:SetScript("OnClick", onRowClick)
    end
    row.instanceID = element.instanceID
    row.label:SetText(nameOf(element.instanceID))
    row.detail:SetText(MapsView.Percent(element.instanceID))
    row.selected:SetShown(element.instanceID == state.selected)
end

local function listInsets()
    local insets = DayView.INSETS
    return insets.outer, insets.top + LIST_TOP, insets.spine, 14
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

-- Without a ScrollBox: as many rows as fit, around the open dungeon.
local function showFixedList(paperHeight)
    local left, top, right, bottom = listInsets()
    local count = math.max(1, math.floor(((paperHeight or 0) - top - bottom) / ROW_HEIGHT))
    local selected = indexOf(state.selected) or 1
    local first = math.max(1, math.min(selected - math.floor(count / 2), #state.instances - count + 1))
    ui.fixedRows = ui.fixedRows or {}
    for i = 1, math.max(count, #ui.fixedRows) do
        local instanceID = i <= count and state.instances[first + i - 1]
        local row = ui.fixedRows[i]
        if instanceID then
            if not row then
                row = CreateFrame("Button", nil, ui.left)
                row:SetHeight(ROW_HEIGHT)
                row:SetPoint("TOPLEFT", left - 10, -(top + (i - 1) * ROW_HEIGHT))
                row:SetPoint("TOPRIGHT", -right, -(top + (i - 1) * ROW_HEIGHT))
                ui.fixedRows[i] = row
            end
            initRow(row, { instanceID = instanceID })
            row:Show()
        elseif row then
            row:Hide()
        end
    end
end

local function showList(paperHeight)
    if not ui.scrollBox then
        showFixedList(paperHeight)
        return
    end
    local elements = {}
    for i, instanceID in ipairs(state.instances) do elements[i] = { instanceID = instanceID } end
    ui.scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    local index = indexOf(state.selected)
    if index then
        ui.scrollBox:ScrollToElementData(elements[index], ScrollBoxConstants and ScrollBoxConstants.AlignNearest)
    end
end

------------------------------------------------------------------------------------------------
-- The right page and the spread

local function showTooltip(button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(button.tooltip)
    GameTooltip:Show()
end

local function hideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function createButton(parent, text, tooltip, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(text)
    local width = button:GetTextWidth()
    button:SetSize(math.max(type(width) == "number" and width or 0, 60) + 24, 22)
    button.tooltip = tooltip
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", hideTooltip)
    return button
end

local function createPage(page)
    local insets = DayView.INSETS
    ui.title = Theme.Text(page, "title")
    ui.title:SetPoint("TOPLEFT", insets.spine, -insets.top)
    ui.title:SetPoint("TOPRIGHT", -insets.outer, -insets.top)
    ui.title:SetWordWrap(false)
    local divider = Theme.Divider(page)
    divider:SetPoint("TOPLEFT", insets.spine - 12, -(insets.top + 26))
    divider:SetPoint("TOPRIGHT", -(insets.outer - 12), -(insets.top + 26))
    ui.subtitle = Theme.Text(page, "small", Theme.INK_FADED)
    ui.subtitle:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 12, -4)
    ui.subtitle:SetPoint("TOPRIGHT", divider, "BOTTOMRIGHT", -12, -4)
    ui.subtitle:SetWordWrap(true)
    ui.subtitle:SetMaxLines(2)
    ui.floorName = Theme.Text(page, "text")
    ui.floorName:SetPoint("TOPLEFT", insets.spine, -(insets.top + 64))
    ui.floorName:SetPoint("TOPRIGHT", -insets.outer, -(insets.top + 64))
    ui.floorName:SetWordWrap(false)
    -- The map, clickable to unfold it.
    ui.mapArea = CreateFrame("Button", nil, page)
    ui.mapArea:SetScript("OnClick", function() MapsView:SetUnfolded(true) end)
    ui.map = DungeonMap.Create(ui.mapArea)
    ui.map.frame:SetPoint("TOP", ui.mapArea, "TOP")
    ui.unfold = createButton(page, L.MAPS_UNFOLD, L.MAPS_UNFOLD_TIP, function() MapsView:SetUnfolded(true) end)
    ui.unfold:SetPoint("BOTTOMLEFT", insets.spine, insets.bottom - 35)
    ui.empty = Theme.Text(page, "text", Theme.INK_FADED)
    ui.empty:SetPoint("TOPLEFT", insets.spine, -(insets.top + 8))
    ui.empty:SetPoint("TOPRIGHT", -insets.outer, -(insets.top + 8))
    ui.empty:SetWordWrap(true)
end

-- Both pages, under the same page controls: the map as large as the book allows.
local function createSpread(leftPaper, rightPaper)
    local insets = DayView.INSETS
    local spread = CreateFrame("Frame", nil, rightPaper)
    spread:SetPoint("TOPLEFT", leftPaper, "TOPLEFT", insets.outer - 12, -insets.top)
    spread:SetPoint("BOTTOMRIGHT", rightPaper, "BOTTOMRIGHT", -(insets.outer - 12), BUTTON_ROW)
    spread:SetFrameLevel(rightPaper:GetFrameLevel() + 5)
    ui.spreadTitle = Theme.Text(spread, "heading")
    ui.spreadTitle:SetPoint("TOPLEFT", 12, 0)
    ui.spreadTitle:SetPoint("TOPRIGHT", -12, 0)
    ui.spreadTitle:SetWordWrap(false)
    ui.spreadMap = DungeonMap.Create(spread)
    ui.spreadMap.frame:SetPoint("TOP", spread, "TOP", 0, -SPREAD_TOP)
    ui.fold = createButton(rightPaper, L.MAPS_FOLD, L.MAPS_FOLD_TIP, function() MapsView:SetUnfolded(false) end)
    ui.fold:SetPoint("BOTTOMLEFT", insets.spine, insets.bottom - 35)
    ui.fold:SetFrameLevel(spread:GetFrameLevel() + 1)
    ui.spread = spread
end

local function showPage(paperWidth, paperHeight)
    local insets = DayView.INSETS
    local instanceID = state.selected
    ui.page:SetShown(not state.unfolded)
    ui.spread:SetShown(state.unfolded == true)
    ui.fold:SetShown(state.unfolded == true)
    ui.left:SetShown(not state.unfolded)
    if not instanceID then
        ui.title:SetText("")
        ui.subtitle:SetText("")
        ui.floorName:SetText("")
        ui.map:Hide()
        ui.unfold:Hide()
        ui.empty:SetText(Store.db and L.MAPS_EMPTY or "")
        ui.empty:Show()
        return
    end
    ui.empty:Hide()
    if state.unfolded then
        local floor = floorTitle()
        ui.spreadTitle:SetText(floor ~= "" and L.MAPS_SPREAD_TITLE:format(nameOf(instanceID), floor) or nameOf(instanceID))
        -- Both pages; a client that hasn't laid the frame out yet gets the papers' size.
        local width = ui.spread:GetWidth() or 0
        if width <= 0 then width = 2 * (paperWidth or 0) end
        local height = ui.spread:GetHeight() or 0
        if height <= 0 then height = (paperHeight or 0) - insets.top - BUTTON_ROW end
        height = height - SPREAD_TOP
        ui.spreadMap:Show(instanceID, state.floor, width, height)
        return
    end
    ui.title:SetText(nameOf(instanceID))
    ui.subtitle:SetText(MapsView.Subtitle(instanceID))
    ui.floorName:SetText(floorTitle())
    local width = (paperWidth or 0) - insets.spine - insets.outer
    local height = (paperHeight or 0) - insets.top - MAP_TOP - insets.bottom
    ui.mapArea:ClearAllPoints()
    ui.mapArea:SetPoint("TOPLEFT", insets.spine, -(insets.top + MAP_TOP))
    ui.mapArea:SetSize(math.max(width, 1), math.max(height, 1))
    local _, drawn = ui.map:Show(instanceID, state.floor, width, height)
    ui.mapArea:SetHeight(math.max(drawn, 1))
    ui.unfold:Show()
end

------------------------------------------------------------------------------------------------
-- Drawing, called by the journal

function MapsView:Create(leftPaper, rightPaper)
    local insets = DayView.INSETS
    ui.left = CreateFrame("Frame", nil, leftPaper)
    ui.left:SetAllPoints()
    ui.right = CreateFrame("Frame", nil, rightPaper)
    ui.right:SetAllPoints()
    ui.header = Theme.Text(ui.left, "title")
    ui.header:SetPoint("TOPLEFT", insets.outer, -insets.top)
    ui.header:SetPoint("TOPRIGHT", -insets.spine, -insets.top)
    ui.header:SetWordWrap(false)
    local divider = Theme.Divider(ui.left)
    divider:SetPoint("TOPLEFT", ui.header, "BOTTOMLEFT", -12, -4)
    divider:SetPoint("TOPRIGHT", ui.header, "BOTTOMRIGHT", 12, -4)
    if ns.Compat.has.scrollBox then
        createScrollList(ui.left)
    end
    ui.page = CreateFrame("Frame", nil, ui.right)
    ui.page:SetAllPoints()
    createPage(ui.page)
    createSpread(leftPaper, ui.right)
    ui.left:Hide()
    ui.right:Hide()
end

function MapsView:SetShown(shown)
    if not ui.left then return end
    ui.left:SetShown(shown and not state.unfolded)
    ui.right:SetShown(shown)
end

-- Draws the tab. Returns the shown floor and the number of floors, for the page controls.
function MapsView:Refresh(paperWidth, paperHeight)
    local list = Charted:GetInstances()
    table.sort(list, function(a, b) return nameOf(a) < nameOf(b) end)
    state.instances = list
    if not indexOf(state.selected) then
        self:Select(list[1])
    end
    local name = Store.db and Store.db.meta.name
    ui.header:SetText(name and L.MAPS_OF:format(name) or L.TAB_MAPS)
    showList(paperHeight)
    showPage(paperWidth, paperHeight)
    if not state.selected then return nil, 0 end
    return state.floor, floorCount()
end

-- A section found while its map is shown fades out; then the list's numbers follow.
function MapsView:OnCharted(instanceID, trigger)
    local sections = Charted.SectionsOf(instanceID, trigger)
    if ui.map then
        ui.map:Reveal(instanceID, sections)
        ui.spreadMap:Reveal(instanceID, sections)
    end
    ns.Journal:RequestRefresh()
end

ns.Bus:On("CHARTED", MapsView, MapsView.OnCharted)
