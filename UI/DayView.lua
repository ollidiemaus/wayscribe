local _, ns = ...
local L, Compat, Store, Time, RecordTypes, Theme = ns.L, ns.Compat, ns.Store, ns.Time, ns.RecordTypes, ns.Theme

-- One day's page of the journal (docs/ARCHITECTURE.md §7): its entries in time order, then the
-- day's counter lines, then the sessions played that day. Build() is the model and Show() draws
-- it, so the page can be checked without a client.
local DayView = {}
ns.DayView = DayView

local TIME_WIDTH = 60
local MARKER_SIZE = 6
local ICON_SIZE = 14
local TEXT_INDENT = TIME_WIDTH + 16
local LINE_GAP = 5
local SECTION_GAP = 12

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
-- Drawing

local ui = {}
local rows = {}
DayView.ui = ui

function DayView:Create(parent)
    ui.title = Theme.Text(parent, "title")
    ui.title:SetPoint("TOPLEFT", 16, -14)
    ui.title:SetPoint("TOPRIGHT", -16, -14)
    ui.subtitle = Theme.Text(parent, "small", Theme.INK_FADED)
    ui.subtitle:SetPoint("TOPLEFT", ui.title, "BOTTOMLEFT", 0, -4)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(Theme.INK_FADED[1], Theme.INK_FADED[2], Theme.INK_FADED[3], 0.5)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 16, -58)
    rule:SetPoint("TOPRIGHT", -16, -58)

    ui.scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    ui.scroll:SetPoint("TOPLEFT", 16, -66)
    ui.scroll:SetPoint("BOTTOMRIGHT", -30, 40)
    ui.content = CreateFrame("Frame", nil, ui.scroll)
    ui.content:SetSize(1, 1)
    ui.scroll:SetScrollChild(ui.content)
end

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
        row.icon:SetPoint("TOPLEFT", content, "TOPLEFT", TIME_WIDTH + 4, -y + 1)
        row.icon:SetTexture(line.icon)
        row.icon:Show()
    elseif line.category then
        local color = Theme.CategoryColor(line.category)
        row.marker:ClearAllPoints()
        row.marker:SetPoint("TOPLEFT", content, "TOPLEFT", TIME_WIDTH + 8, -y - 4)
        row.marker:SetColorTexture(color[1], color[2], color[3], 1)
        row.marker:Show()
    end
end

-- line = { text, time?, icon?, category?, faded? }. Returns the y below it.
local function placeRow(index, y, width, line)
    local row = getRow(index)
    local content = ui.content
    local indent = line.category and TEXT_INDENT or 0
    row.text:ClearAllPoints()
    row.text:SetPoint("TOPLEFT", content, "TOPLEFT", indent, -y)
    row.text:SetWidth(math.max(width - indent, 1))
    row.text:SetTextColor(unpack(line.faded and Theme.INK_FADED or Theme.INK))
    row.text:SetText(line.text)
    row.text:Show()
    if line.time then
        row.time:ClearAllPoints()
        row.time:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row.time:SetText(line.time)
        row.time:Show()
    else
        row.time:Hide()
    end
    placeMarker(row, line, y)
    return y + row.text:GetStringHeight() + LINE_GAP
end

-- page = DayView.Build(...) or nil; emptyText is shown when there is no page at all.
function DayView:Show(page, width, emptyText)
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
