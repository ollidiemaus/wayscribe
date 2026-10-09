local _, ns = ...
local L, Compat, Store, Time, Theme, DayView, Notes =
    ns.L, ns.Compat, ns.Store, ns.Time, ns.Theme, ns.DayView, ns.Notes

-- The journal's second tab: the player's own notes (docs/ARCHITECTURE.md §7.9). The left page lists
-- them, newest first, under a New note button; the right page is the open note, written straight
-- onto the paper: its title, when it was written and how many places it has, and its text. Every
-- keystroke is saved; a note left without title and text is dropped. Each /way line of the text
-- is a marker on the world map (UI/NotesMap.lua), with the icon picked here; leaving a note writes
-- the player's zone into the lines that took it.
local NotesView = {}
ns.NotesView = NotesView

local ROW_HEIGHT = 24
local LIST_TOP = 70        -- below the header and the New note button
local SCROLLBAR = 20
local ICON_SIZE = 18
local BODY_TOP = 64        -- the text, under the subtitle
local BODY_TOP_PLACED = 88 -- the text, under the marker icons
local DELETE_POPUP = "WAYSCRIBE_DELETE_NOTE"

local ui = { icons = {} }
NotesView.ui = ui
-- notes: all notes, newest first; selected: the open note's id; shownId: the note the editors hold.
local state = { notes = {} }
NotesView.state = state

local function indexOf(id)
    for i, note in ipairs(state.notes) do
        if note.id == id then return i end
    end
    return nil
end

------------------------------------------------------------------------------------------------
-- Text, shared with the export

function NotesView.Title(note)
    return note.title ~= nil and note.title ~= "" and note.title or L.NOTES_UNTITLED
end

-- "Written Friday, October 9, 2026 · edited 2:05 PM · 3 places on the map · 1 /way line not
-- found"
function NotesView.Subtitle(note)
    local created, edited = tonumber(note.created) or 0, tonumber(note.edited) or 0
    local parts = { L.NOTES_WRITTEN:format(Time.FormatLongDay(Time.DayKey(created))) }
    if edited - created >= 60 then
        local editedDay = Time.DayKey(edited)
        if editedDay == Time.DayKey(Time.Now()) then
            parts[#parts + 1] = L.NOTES_EDITED_AT:format(Time.FormatClock(edited, Compat.Uses24HourClock()))
        else
            parts[#parts + 1] = L.NOTES_EDITED_ON:format(Time.FormatDay(editedDay))
        end
    end
    local places, unplaced = Notes.PlacesOf(note)
    if #places > 0 then parts[#parts + 1] = ns.YearCards.Plural("NOTES_PLACES", #places) end
    if unplaced > 0 then parts[#parts + 1] = ns.YearCards.Plural("NOTES_UNPLACED", unplaced) end
    return table.concat(parts, " · ")
end

-- "Today", "Yesterday" or the short date.
local function listDate(note)
    local dayKey = Notes.DayOf(note)
    return Time.RelativeDay(dayKey) or Time.FormatDay(dayKey)
end

------------------------------------------------------------------------------------------------
-- Selecting, adding, deleting

-- A note left blank was started and never written: it goes.
local function dropIfBlank(id)
    local note = id and Notes:Get(id)
    if note and Notes.IsBlank(note) and Notes:IsWritable() then
        Notes:Delete(id)
    end
end

local function clearFocus()
    if ui.titleBox then
        ui.titleBox:ClearFocus()
        ui.body:ClearFocus()
    end
end

-- Leaving a note: /way lines that took the player's zone get it written in, and the editor shows
-- that (it isn't being written then, so the cursor can't jump).
local function fillZones(id)
    if not (id and Notes:FillZones(id)) then return end
    if state.shownId == id and ui.body then
        ui.body:SetText(Notes:Get(id).text)
    end
end

function NotesView:Select(id)
    if state.selected ~= id then
        clearFocus()
        fillZones(state.selected)
        dropIfBlank(state.selected)
    end
    state.selected = id
end

-- Leaving the tab or closing the journal: the editors let go of the keyboard.
function NotesView:Leave()
    clearFocus()
    fillZones(state.selected)
    dropIfBlank(state.selected)
end

-- A new, empty note, open with the cursor in its title.
function NotesView:New()
    local note = Notes:Add({})
    if not note then return end
    self:Select(note.id)
    ns.Journal:Refresh()
    ui.titleBox:SetFocus()
end

function NotesView:Delete(id)
    local index = indexOf(id)
    if not Notes:Delete(id) then return end
    if state.selected == id then
        local neighbour = index and (state.notes[index + 1] or state.notes[index - 1])
        state.selected = neighbour and neighbour.id
    end
    ns.Journal:Refresh()
end

local function confirmDelete()
    local note = state.selected and Notes:Get(state.selected)
    if not note then return end
    if Notes.IsBlank(note) or type(StaticPopup_Show) ~= "function" then
        NotesView:Delete(note.id)
        return
    end
    StaticPopupDialogs[DELETE_POPUP] = StaticPopupDialogs[DELETE_POPUP] or {
        text = L.NOTES_DELETE_CONFIRM,
        button1 = L.NOTES_DELETE,
        button2 = L.CANCEL,
        OnAccept = function(_, id) NotesView:Delete(id) end,
        showAlert = true,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show(DELETE_POPUP, NotesView.Title(note), nil, note.id)
end

-- step 1 turns back (the next older note), -1 on (a newer one). Returns whether it turned.
function NotesView:Turn(step)
    local index = indexOf(state.selected)
    local target = index and state.notes[index + step]
    if not target then return false end
    self:Select(target.id)
    return true
end

------------------------------------------------------------------------------------------------
-- The left page: the notes

local function onRowClick(row)
    NotesView:Select(row.noteId)
    ns.Journal:Refresh()
end

local function initRow(row, element)
    if not row.label then
        row.selected = Theme.Highlight(row)
        Theme.Fill(row, Theme.INK, "HIGHLIGHT", 0, 0.06)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(14, 14)
        row.icon:SetPoint("LEFT", 8, 0)
        row.detail = Theme.Text(row, "small", Theme.INK_FADED)
        row.detail:SetPoint("RIGHT", -8, 0)
        row.detail:SetJustifyH("RIGHT")
        row.label = Theme.Text(row, "text")
        row.label:SetPoint("LEFT", 28, 0)
        row.label:SetPoint("RIGHT", row.detail, "LEFT", -6, 0)
        row.label:SetWordWrap(false)
        row:SetScript("OnClick", onRowClick)
    end
    local note = element.note
    row.noteId = note.id
    row.label:SetText(NotesView.Title(note))
    row.detail:SetText(listDate(note))
    row.icon:SetShown(#Notes.PlacesOf(note) > 0)
    row.icon:SetTexture(Notes.IconTexture(note.icon))
    row.selected:SetShown(note.id == state.selected)
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

-- Without a ScrollBox: as many rows as fit, around the open note.
local function showFixedList(paperHeight)
    local left, top, right, bottom = listInsets()
    local count = math.max(1, math.floor(((paperHeight or 0) - top - bottom) / ROW_HEIGHT))
    local selected = indexOf(state.selected) or 1
    local first = math.max(1, math.min(selected - math.floor(count / 2), #state.notes - count + 1))
    ui.fixedRows = ui.fixedRows or {}
    for i = 1, math.max(count, #ui.fixedRows) do
        local note = i <= count and state.notes[first + i - 1]
        local row = ui.fixedRows[i]
        if note then
            if not row then
                row = CreateFrame("Button", nil, ui.left)
                row:SetHeight(ROW_HEIGHT)
                row:SetPoint("TOPLEFT", left - 10, -(top + (i - 1) * ROW_HEIGHT))
                row:SetPoint("TOPRIGHT", -right, -(top + (i - 1) * ROW_HEIGHT))
                ui.fixedRows[i] = row
            end
            initRow(row, { note = note })
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
    for i, note in ipairs(state.notes) do elements[i] = { note = note } end
    ui.scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    local index = indexOf(state.selected)
    if index then
        ui.scrollBox:ScrollToElementData(elements[index], ScrollBoxConstants and ScrollBoxConstants.AlignNearest)
    end
end

------------------------------------------------------------------------------------------------
-- The right page: the open note

local function save(field, value)
    local id = state.shownId
    if id and Notes:IsWritable() then
        Notes:Update(id, { [field] = value })
    end
end

local function updateHints()
    ui.titleHint:SetShown(ui.titleBox:GetText() == "")
    ui.bodyHint:SetShown(ui.body:GetText() == "")
end

-- Keeps the line with the cursor in view, once the box has grown to the new text.
local function followCursor(_, _, y, _, height)
    C_Timer.After(0, function()
        local scroll = ui.bodyScroll
        local top, offset, visible = -(y or 0), scroll:GetVerticalScroll(), scroll:GetHeight()
        local range = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or 0
        local target
        if top < offset then
            target = top
        elseif top + (height or 0) > offset + visible then
            target = top + (height or 0) - visible
        end
        if target then scroll:SetVerticalScroll(math.max(0, math.min(target, range))) end
    end)
end

local function styleEditBox(box, kind)
    Theme.Style(box, kind)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", box.ClearFocus)
end

local function createTitle(page)
    local insets = DayView.INSETS
    local box = CreateFrame("EditBox", nil, page)
    box:SetPoint("TOPLEFT", insets.spine, -insets.top + 4)
    box:SetPoint("TOPRIGHT", -insets.outer, -insets.top + 4)
    box:SetHeight(28)
    styleEditBox(box, "title")
    box:SetMaxLetters(Notes.TITLE_LETTERS)
    box:SetScript("OnTextChanged", function(self, userInput)
        updateHints()
        if userInput then save("title", self:GetText()) end
    end)
    local function toBody() ui.body:SetFocus() end
    box:SetScript("OnEnterPressed", toBody)
    box:SetScript("OnTabPressed", toBody)
    ui.titleBox = box
    ui.titleHint = Theme.Text(page, "title", Theme.INK_FADED)
    ui.titleHint:SetPoint("LEFT", box, "LEFT", 0, 0)
    ui.titleHint:SetText(L.NOTES_UNTITLED)
    local divider = Theme.Divider(page)
    divider:SetPoint("TOPLEFT", insets.spine - 12, -(insets.top + 26))
    divider:SetPoint("TOPRIGHT", -(insets.outer - 12), -(insets.top + 26))
    ui.subtitle = Theme.Text(page, "small", Theme.INK_FADED)
    ui.subtitle:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 12, -4)
    ui.subtitle:SetPoint("TOPRIGHT", divider, "BOTTOMRIGHT", -12, -4)
    ui.subtitle:SetWordWrap(false)
end

-- The marker's icon, for a note with a place: the eight raid target icons in a row.
local function createIcons(page)
    local insets = DayView.INSETS
    ui.iconLabel = Theme.Text(page, "small", Theme.INK_FADED)
    ui.iconLabel:SetPoint("TOPLEFT", insets.spine, -(insets.top + 62))
    ui.iconLabel:SetText(L.NOTES_MARKER)
    for i = 1, Notes.ICON_COUNT do
        local button = CreateFrame("Button", nil, page)
        button:SetSize(ICON_SIZE, ICON_SIZE)
        if i == 1 then
            button:SetPoint("LEFT", ui.iconLabel, "RIGHT", 8, 0)
        else
            button:SetPoint("LEFT", ui.icons[i - 1], "RIGHT", 4, 0)
        end
        button:SetNormalTexture(Notes.IconTexture(i))
        button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        button:SetScript("OnClick", function()
            if state.shownId then Notes:Update(state.shownId, { icon = i }) end
        end)
        button.icon = i
        ui.icons[i] = button
    end
end

local function createBody(page)
    local native = Compat.has.scrollFrameBar
    local scroll = CreateFrame("ScrollFrame", nil, page, not native and "UIPanelScrollFrameTemplate" or nil)
    if native then
        local bar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 0)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, 0)
        ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
        scroll:EnableMouseWheel(true)
        bar:Hide()
        local onRangeChanged = scroll:GetScript("OnScrollRangeChanged")
        scroll:SetScript("OnScrollRangeChanged", function(frame, horizontal, vertical)
            if onRangeChanged then onRangeChanged(frame, horizontal, vertical) end
            bar:SetShown((vertical or 0) > 0.5)
        end)
    end
    local body = CreateFrame("EditBox", nil, scroll)
    body:SetMultiLine(true)
    styleEditBox(body, "text")
    body:SetMaxLetters(Notes.TEXT_LETTERS)
    body:SetScript("OnTextChanged", function(self, userInput)
        updateHints()
        if userInput then save("text", self:GetText()) end
    end)
    body:SetScript("OnCursorChanged", followCursor)
    body:SetScript("OnEditFocusLost", function() fillZones(state.shownId) end)
    scroll:SetScrollChild(body)
    -- A click anywhere under the text writes on.
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function()
        if body:IsEnabled() then
            body:SetFocus()
            body:SetCursorPosition(#(body:GetText() or ""))
        end
    end)
    ui.bodyScroll, ui.body = scroll, body
    ui.bodyHint = Theme.Text(scroll, "text", Theme.INK_FADED)
    ui.bodyHint:SetPoint("TOPLEFT", 0, 0)
    ui.bodyHint:SetText(L.NOTES_WRITE_HERE)
    NotesView.PlaceBody(BODY_TOP)
end

-- The text starts under the subtitle, or under the marker icons.
function NotesView.PlaceBody(top)
    local insets = DayView.INSETS
    ui.bodyScroll:ClearAllPoints()
    ui.bodyScroll:SetPoint("TOPLEFT", insets.spine, -(insets.top + top))
    ui.bodyScroll:SetPoint("BOTTOMRIGHT", -(insets.outer + SCROLLBAR), insets.bottom)
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

-- The default UI's button, fitted to its text.
local function createButton(parent, text, tooltip, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(text)
    local width = button:GetTextWidth()
    button:SetSize(math.max(type(width) == "number" and width or 0, 60) + 24, 22)
    button.tooltip = tooltip
    button:SetScript("OnClick", onClick)
    if tooltip then
        button:SetScript("OnEnter", showTooltip)
        button:SetScript("OnLeave", hideTooltip)
    end
    return button
end

-- Level with the journal's page controls, like its Show on the map.
local function createButtons(page)
    local insets = DayView.INSETS
    ui.mapButton = createButton(page, L.FOOTSTEPS_SHOW_DAY, L.NOTES_SHOW_ON_MAP_TIP,
        function() ns.NotesMap:ShowNote(state.shownId) end)
    ui.mapButton:SetPoint("BOTTOMLEFT", insets.spine, insets.bottom - 35)
    ui.deleteButton = createButton(page, L.NOTES_DELETE, nil, confirmDelete)
    ui.deleteButton:SetPoint("BOTTOMLEFT", insets.spine, insets.bottom - 35)
end

local function setWritable(writable)
    ui.titleBox:SetEnabled(writable)
    ui.body:SetEnabled(writable)
    ui.deleteButton:SetEnabled(writable)
    for _, button in ipairs(ui.icons) do button:SetEnabled(writable) end
end

local function showIcons(note)
    local placed = #Notes.PlacesOf(note) > 0
    ui.iconLabel:SetShown(placed)
    for _, button in ipairs(ui.icons) do
        button:SetShown(placed)
        button:SetAlpha(button.icon == (note.icon or 1) and 1 or 0.35)
    end
    NotesView.PlaceBody(placed and BODY_TOP_PLACED or BODY_TOP)
end

local function showNote(note, paperWidth)
    local shown = note ~= nil
    ui.editor:SetShown(shown)
    ui.empty:SetShown(not shown)
    if not shown then
        state.shownId = nil
        ui.empty:SetText(Store.db and L.NOTES_EMPTY or "")
        return
    end
    if state.shownId ~= note.id then
        -- Another note: fill the editors. The one being written is never set again (the cursor
        -- would jump).
        state.shownId = note.id
        ui.titleBox:SetText(note.title or "")
        ui.body:SetText(note.text or "")
        ui.body:SetCursorPosition(0)
        ui.bodyScroll:SetVerticalScroll(0)
        updateHints()
    end
    ui.body:SetWidth(math.max(DayView.TextWidth(paperWidth or 0), 1))
    ui.subtitle:SetText(NotesView.Subtitle(note))
    showIcons(note)
    local onMap = #Notes.PlacesOf(note) > 0 and ns.NotesMap:CanShow()
    ui.mapButton:SetShown(onMap)
    ui.deleteButton:ClearAllPoints()
    if onMap then
        ui.deleteButton:SetPoint("LEFT", ui.mapButton, "RIGHT", 6, 0)
    else
        ui.deleteButton:SetPoint("BOTTOMLEFT", DayView.INSETS.spine, DayView.INSETS.bottom - 35)
    end
    setWritable(Notes:IsWritable())
end

------------------------------------------------------------------------------------------------
-- Drawing, called by the journal

-- Both pages' layers on the journal's paper frames; hidden until the tab is chosen.
function NotesView:Create(leftPaper, rightPaper)
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
    ui.newButton = createButton(ui.left, L.NOTES_NEW, L.NOTES_NEW_TIP, function() NotesView:New() end)
    ui.newButton:SetPoint("TOPLEFT", insets.outer - 4, -(insets.top + 38))
    if Compat.has.scrollBox then
        createScrollList(ui.left)
    end

    ui.editor = CreateFrame("Frame", nil, ui.right)
    ui.editor:SetAllPoints()
    createTitle(ui.editor)
    createIcons(ui.editor)
    createBody(ui.editor)
    createButtons(ui.editor)
    ui.empty = Theme.Text(ui.right, "text", Theme.INK_FADED)
    ui.empty:SetPoint("TOPLEFT", insets.spine, -(insets.top + 8))
    ui.empty:SetPoint("TOPRIGHT", -insets.outer, -(insets.top + 8))
    ui.empty:SetWordWrap(true)

    ui.left:Hide()
    ui.right:Hide()
end

function NotesView:SetShown(shown)
    if not ui.left then return end
    if not shown and ui.left:IsShown() then self:Leave() end
    ui.left:SetShown(shown)
    ui.right:SetShown(shown)
end

-- Draws both pages. Returns the open note's place in the list (1 = newest) and the number of
-- notes, for the page controls.
function NotesView:Refresh(paperWidth, paperHeight)
    state.notes = Notes:GetAll()
    if not indexOf(state.selected) then
        state.selected = state.notes[1] and state.notes[1].id
    end
    local name = Store.db and Store.db.meta.name
    ui.header:SetText(name and L.NOTES_OF:format(name) or L.NOTES)
    ui.newButton:SetEnabled(Notes:IsWritable())
    showList(paperHeight)
    showNote(state.selected and Notes:Get(state.selected), paperWidth)
    return indexOf(state.selected), #state.notes
end

-- A /reload or logout with the journal open doesn't hide it first.
ns.Bus:On("LOGOUT", NotesView, NotesView.Leave)
