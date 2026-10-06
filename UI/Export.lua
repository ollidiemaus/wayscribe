local _, ns = ...
local L, Store, Time, DayView = ns.L, ns.Store, ns.Time, ns.DayView

-- The journal as plain text (docs/ARCHITECTURE.md §7), a reading copy the player keeps outside the
-- game. Addons can't write files, so the text is shown selected in a window and copied with Ctrl+C.
-- Each day reads like its journal page, oldest first, with every category.
local Export = {}
ns.Export = Export

local RANGES = { "month", "year", "all" }
local VALID_RANGE = { month = true, year = true, all = true }
local WIDTH, HEIGHT = 640, 480
local PADDING = 20
local BUTTON_WIDTH = 120

local frame, editBox, scroll, summary
local rangeButtons = {}

local function everything() return true end

-- The first and last day of a range; nil for no limit.
function Export.Range(range)
    local today = Time.DayKey(Time.Now())
    if range == "month" then return math.floor(today / 100) * 100 + 1, today end
    if range == "year" then return math.floor(today / 10000) * 10000 + 101, today end
    return nil, nil
end

local function pageLines(out, dayKey)
    local page = DayView.Build(dayKey, everything)
    local title = page.title
    if page.played > 0 then
        title = title .. " · " .. L.PAGE_PLAYED:format(Time.FormatDuration(page.played))
    end
    out[#out + 1] = title
    -- Times in one column, counter lines under the entries' texts.
    local width = 0
    for _, entry in ipairs(page.entries) do
        width = math.max(width, #(entry.time or ""))
    end
    for _, entry in ipairs(page.entries) do
        local time = entry.time or ""
        out[#out + 1] = "  " .. string.rep(" ", width - #time) .. time .. "  " .. entry.text
    end
    local indent = string.rep(" ", width + 4)
    for _, line in ipairs(page.counters) do
        out[#out + 1] = indent .. line.text
    end
    if page.sessions then
        out[#out + 1] = "  " .. page.sessions
    end
    out[#out + 1] = ""
end

-- The text of a range ("month", "year" or "all") and the number of days in it.
function Export.BuildText(range)
    local fromDay, toDay = Export.Range(range)
    local days = {}
    for _, dayKey in ipairs(Store:GetDayKeys()) do -- newest first
        if (not fromDay or dayKey >= fromDay) and (not toDay or dayKey <= toDay) then
            table.insert(days, 1, dayKey)
        end
    end
    local meta = Store.db.meta
    local out = {
        L.EXPORT_HEADER:format(tostring(meta.name), tostring(meta.realm)),
        L.EXPORT_SUBHEADER:format(Time.FormatDay(Time.DayKey(Time.Now())), L["EXPORT_RANGE_" .. range:upper()],
            ns.YearCards.Plural("EXPORT_DAYS", #days)),
        "",
    }
    for _, dayKey in ipairs(days) do
        pageLines(out, dayKey)
    end
    return table.concat(out, "\n"), #days
end

------------------------------------------------------------------------------------------------
-- Window

local function createRangeButtons()
    for i, range in ipairs(RANGES) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(BUTTON_WIDTH, 22)
        button:SetPoint("TOPLEFT", PADDING + (i - 1) * (BUTTON_WIDTH + 6), -76)
        button:SetText(L["EXPORT_RANGE_" .. range:upper()])
        button:SetScript("OnClick", function() Export:Open(range) end)
        button.range = range
        rangeButtons[i] = button
    end
    summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("LEFT", rangeButtons[#RANGES], "RIGHT", 12, 0)
end

-- A multi-line edit box that can't be changed, only selected and copied.
local function createTextBox()
    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetPoint("TOPLEFT", PADDING, -108)
    box:SetPoint("BOTTOMRIGHT", -PADDING, PADDING + 32)
    box:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    box:SetBackdropColor(0, 0, 0, 0.6)
    scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(0)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(WIDTH - 2 * PADDING - 40)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(frame.exportText or "")
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(editBox)
end

local function createWindow()
    frame = CreateFrame("Frame", "WayscribeExportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    tinsert(UISpecialFrames, "WayscribeExportFrame")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -PADDING)
    title:SetText(L.EXPORT_TITLE)
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -46)
    hint:SetPoint("TOPRIGHT", -PADDING, -46)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.EXPORT_HINT)

    createRangeButtons()
    createTextBox()
    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(BUTTON_WIDTH, 22)
    close:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    close:SetText(L.CLOSE)
    close:SetScript("OnClick", function() frame:Hide() end)
end

-- Opens the window with the text of `range` (default: everything), selected for copying.
-- Works on a read-only journal too: reading is all it does.
function Export:Open(range)
    if not VALID_RANGE[range] then range = "all" end
    if not Store.db then
        ns.Print(L.EXPORT_NOTHING)
        return
    end
    if not frame then createWindow() end
    local text, days = Export.BuildText(range)
    frame.exportText, frame.range = text, range
    for _, button in ipairs(rangeButtons) do
        button:SetEnabled(button.range ~= range)
    end
    summary:SetText(ns.YearCards.Plural("EXPORT_DAYS", days))
    editBox:SetText(text)
    editBox:SetCursorPosition(0)
    editBox:HighlightText()
    editBox:SetFocus()
    scroll:SetVerticalScroll(0)
    frame:Show()
end

function Export:GetText()
    return frame and frame.exportText
end
