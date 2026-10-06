local _, ns = ...
local L, Compat, Store, Time, RecordTypes, Theme = ns.L, ns.Compat, ns.Store, ns.Time, ns.RecordTypes, ns.Theme

-- One day's page of the journal (docs/ARCHITECTURE.md §7): its entries in time order, then the
-- day's counter lines, then the sessions played that day. Build() is the model and Show() draws
-- it, so the page can be checked without a client.
local DayView = {}
ns.DayView = DayView

-- Whether a filter (isVisible(category) -> boolean) leaves anything on this day.
function DayView.HasVisible(dayKey, isVisible)
    local day = Store:GetDay(dayKey)
    if not day then return false end
    for _, record in ipairs(day.records) do
        if isVisible(RecordTypes:CategoryOf(record.type)) then return true end
    end
    for path, bucket in pairs(day.counters) do
        if RecordTypes.counters[path] and type(bucket) == "table" and next(bucket) ~= nil
            and isVisible(RecordTypes:CounterCategory(path)) then
            return true
        end
    end
    return false
end

-- "12:00 - 13:05, 20:15 - now" and the seconds played within this day.
local function sessionsOf(dayKey, use24Hour)
    local from, to = Time.DayStart(dayKey), Time.DayEnd(dayKey)
    local spans, played = {}, 0
    for _, session in ipairs(Store:GetSessions(from, to)) do
        played = played + math.max(0, math.min(session.e, to + 1) - math.max(session.s, from))
        local stop = session.open and L.PAGE_NOW or Time.FormatClock(session.e, use24Hour)
        spans[#spans + 1] = L.PAGE_SESSION_RANGE:format(Time.FormatClock(session.s, use24Hour), stop)
    end
    return spans, played
end

-- { dayKey, title, subtitle, entries = { { time?, text, icon?, category } }, counters, sessions? }
function DayView.Build(dayKey, isVisible)
    local use24Hour = Compat.Uses24HourClock()
    local page = { dayKey = dayKey, title = Time.FormatLongDay(dayKey), entries = {} }
    for _, record in ipairs(Store:GetDayRecords(dayKey)) do
        local category = RecordTypes:CategoryOf(record.type)
        if isVisible(category) then
            local text, icon = RecordTypes:Render(record)
            if record.sim then
                text = L.ENTRY_SIMULATED .. " " .. text
            end
            page.entries[#page.entries + 1] = {
                -- A back-filled entry only knows its day.
                time = not record.bf and Time.FormatClock(record.ts, use24Hour) or nil,
                text = text, icon = icon, category = category,
            }
        end
    end
    local day = Store:GetDay(dayKey)
    page.counters = RecordTypes:CounterLines(day and day.counters, isVisible)

    local spans, played = sessionsOf(dayKey, use24Hour)
    local parts = { Time.RelativeDay(dayKey) }
    if played > 0 then
        parts[#parts + 1] = L.PAGE_PLAYED:format(Time.FormatDuration(played))
    end
    page.subtitle = table.concat(parts, " · ")
    if #spans > 0 then
        page.sessions = L.PAGE_SESSIONS:format(table.concat(spans, L.LIST_SEPARATOR))
    end
    return page
end

------------------------------------------------------------------------------------------------
-- Drawing: a spellbook-style header (date, divider, subtitle) above a scrolling list of lines.

-- Space between the edges of the paper (the page without its rims) and the text; the bottom
-- leaves room for the page controls.
DayView.INSETS = { spine = 26, outer = 30, top = 18, bottom = 46 }
local SCROLLBAR = 20

local ui = {}
local rows = {}
DayView.ui = ui

-- The width of the text column on paper `paperWidth` wide.
function DayView.TextWidth(paperWidth)
    return paperWidth - DayView.INSETS.spine - DayView.INSETS.outer - SCROLLBAR
end

-- The default UI's thin scroll bar, shown only when the page doesn't fit; or the classic one.
local function createScroll(parent)
    local insets = DayView.INSETS
    local native = Compat.has.scrollFrameBar
    local scroll = CreateFrame("ScrollFrame", nil, parent, not native and "UIPanelScrollFrameTemplate" or nil)
    scroll:SetPoint("TOPLEFT", insets.spine, -(insets.top + 70))
    scroll:SetPoint("BOTTOMRIGHT", -(insets.outer + SCROLLBAR), insets.bottom)
    if native then
        local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 0)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, 0)
        ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
        scroll:EnableMouseWheel(true)
        bar:Hide() -- until the page is longer than the space it has
        local onRangeChanged = scroll:GetScript("OnScrollRangeChanged")
        scroll:SetScript("OnScrollRangeChanged", function(frame, horizontal, vertical)
            if onRangeChanged then onRangeChanged(frame, horizontal, vertical) end
            bar:SetShown((vertical or 0) > 0.5)
        end)
        ui.scrollBar = bar
    end
    return scroll
end

-- parent is the right page's paper.
function DayView:Create(parent)
    local insets = DayView.INSETS
    ui.title = Theme.Text(parent, "title")
    ui.title:SetPoint("TOPLEFT", insets.spine, -insets.top)
    ui.title:SetPoint("TOPRIGHT", -insets.outer, -insets.top)
    ui.title:SetWordWrap(false)
    local divider = Theme.Divider(parent)
    divider:SetPoint("TOPLEFT", ui.title, "BOTTOMLEFT", -12, -4)
    divider:SetPoint("TOPRIGHT", ui.title, "BOTTOMRIGHT", 12, -4)
    ui.subtitle = Theme.Text(parent, "small", Theme.INK_FADED)
    ui.subtitle:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 12, -4)

    ui.scroll = createScroll(parent)
    ui.content = CreateFrame("Frame", nil, ui.scroll)
    ui.content:SetSize(1, 1)
    ui.scroll:SetScrollChild(ui.content)
end

local TIME_WIDTH = 64
local MARKER_SIZE = 6
local ICON_SIZE = 16
local TEXT_INDENT = TIME_WIDTH + 18
local LINE_GAP = 6
local SECTION_GAP = 14

local function getRow(index)
    local row = rows[index]
    if not row then
        local content = ui.content
        row = {
            time = Theme.Text(content, "small", Theme.INK_FADED),
            text = Theme.Text(content, "text"),
            marker = content:CreateTexture(nil, "ARTWORK"),
            icon = content:CreateTexture(nil, "ARTWORK"),
        }
        row.time:SetJustifyH("RIGHT")
        row.time:SetWidth(TIME_WIDTH)
        row.text:SetWordWrap(true)
        row.marker:SetSize(MARKER_SIZE, MARKER_SIZE)
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)
        rows[index] = row
    end
    return row
end

local function hideRow(row)
    row.time:Hide()
    row.text:Hide()
    row.marker:Hide()
    row.icon:Hide()
end

-- The category's marker (or the entry's icon) between the time column and the text.
local function placeMarker(row, line, y)
    local content = ui.content
    row.marker:Hide()
    row.icon:Hide()
    if line.icon then
        row.icon:ClearAllPoints()
        row.icon:SetPoint("TOPLEFT", content, "TOPLEFT", TIME_WIDTH + 1, -y + 1)
        row.icon:SetTexture(line.icon)
        row.icon:Show()
    elseif line.category then
        local color = Theme.CategoryColor(line.category)
        row.marker:ClearAllPoints()
        row.marker:SetPoint("TOPLEFT", content, "TOPLEFT", TIME_WIDTH + 6, -y - 5)
        row.marker:SetColorTexture(color[1], color[2], color[3], 1)
        row.marker:Show()
    end
end

-- line = { text, time?, icon?, category?, faded? }. Returns the y below it.
local function placeRow(index, y, width, line)
    local row = getRow(index)
    local content = ui.content
    local indent = line.category and TEXT_INDENT or 0
    Theme.Style(row.text, line.faded and "small" or "text", line.faded and Theme.INK_FADED or Theme.INK)
    row.text:ClearAllPoints()
    row.text:SetPoint("TOPLEFT", content, "TOPLEFT", indent, -y)
    row.text:SetWidth(math.max(width - indent, 1))
    row.text:SetText(line.text)
    row.text:Show()
    if line.time then
        row.time:ClearAllPoints()
        row.time:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y - 1)
        row.time:SetText(line.time)
        row.time:Show()
    else
        row.time:Hide()
    end
    placeMarker(row, line, y)
    return y + row.text:GetStringHeight() + LINE_GAP
end

-- page = DayView.Build(...) or nil; emptyText is shown when there is no page at all.
function DayView:Show(page, paperWidth, emptyText)
    local width = DayView.TextWidth(paperWidth)
    ui.content:SetWidth(width)
    if not page or page.dayKey ~= self.shownDay then
        ui.scroll:SetVerticalScroll(0)
    end
    self.shownDay = page and page.dayKey
    ui.title:SetText(page and page.title or "")
    ui.subtitle:SetText(page and page.subtitle or "")

    local used, y = 0, 0
    local function add(line, gap)
        used = used + 1
        y = placeRow(used, y + (gap or 0), width, line)
    end
    if not page then
        add({ text = emptyText, faded = true })
    else
        for _, entry in ipairs(page.entries) do
            add(entry)
        end
        for i, line in ipairs(page.counters) do
            add(line, i == 1 and #page.entries > 0 and SECTION_GAP or nil)
        end
        if #page.entries == 0 and #page.counters == 0 then
            add({ text = L.PAGE_EMPTY, faded = true })
        end
        if page.sessions then
            add({ text = page.sessions, faded = true }, SECTION_GAP)
        end
    end
    for i = used + 1, #rows do
        hideRow(rows[i])
    end
    ui.content:SetHeight(math.max(y, 1))
end
