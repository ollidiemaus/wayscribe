local _, ns = ...
local L, Store, Time, RecordTypes = ns.L, ns.Store, ns.Time, ns.RecordTypes

-- 0.1: a plain day-by-day list, newest day first. The book-style journal with a virtualized day
-- list comes in 0.3 (docs/ARCHITECTURE.md §7). Uses UIPanelScrollFrameTemplate because it is
-- proven on the Forever client; /ws probe reports whether ScrollBox is available too.
local Journal = {}
ns.Journal = Journal

local MAX_DAYS = 60
local WIDTH, HEIGHT = 440, 520
local LINE_GAP = 4
local DAY_GAP = 12
local ENTRY_INDENT = 14

local frame, scrollFrame, content, banner
local lines = {}
local refreshPending = false

local function createWindow()
    frame = CreateFrame("Frame", "WayscribeJournalFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
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
    frame:Hide()
    tinsert(UISpecialFrames, "WayscribeJournalFrame") -- closes with Escape

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText(L.JOURNAL_TITLE)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    banner = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    banner:SetPoint("TOPLEFT", 22, -46)
    banner:SetPoint("TOPRIGHT", -22, -46)
    banner:SetJustifyH("LEFT")
    banner:SetTextColor(1, 0.35, 0.35)

    scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 22, -66)
    scrollFrame:SetPoint("BOTTOMRIGHT", -40, 20)
    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(WIDTH - 62, 1)
    scrollFrame:SetScrollChild(content)

    frame:SetScript("OnShow", function() Journal:Refresh() end)
end

local function getLine(index)
    local line = lines[index]
    if not line then
        line = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line:SetJustifyH("LEFT")
        line:SetWordWrap(true)
        lines[index] = line
    end
    return line
end

-- Lays out one text line below the previous one and returns the new bottom offset.
local function placeLine(index, y, text, fontObject, indent)
    local line = getLine(index)
    line:SetFontObject(fontObject)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", content, "TOPLEFT", indent, -y)
    line:SetWidth(content:GetWidth() - indent)
    line:SetText(text)
    line:Show()
    return y + line:GetStringHeight() + LINE_GAP
end

local function entryText(record)
    local text = RecordTypes:Render(record)
    if record.sim then
        text = L.ENTRY_SIMULATED .. " " .. text
    end
    return text
end

function Journal:Refresh()
    refreshPending = false
    if not frame or not frame:IsShown() then return end
    banner:SetText(ns.safeMode and L.SAFE_MODE_BANNER:format(ns.safeMode) or "")

    local used, y = 0, 0
    local dayKeys = Store.db and Store:GetDayKeys() or {}
    if #dayKeys == 0 then
        used = used + 1
        y = placeLine(used, y, L.JOURNAL_EMPTY, "GameFontDisable", 0)
    end
    for i = 1, math.min(#dayKeys, MAX_DAYS) do
        local dayKey = dayKeys[i]
        if i > 1 then y = y + DAY_GAP end
        used = used + 1
        y = placeLine(used, y, Time.FormatDay(dayKey), "GameFontNormalLarge", 0)
        for _, record in ipairs(Store:GetDayRecords(dayKey)) do
            used = used + 1
            y = placeLine(used, y, entryText(record), "GameFontHighlight", ENTRY_INDENT)
        end
        for _, text in ipairs(RecordTypes:RenderCounters((Store:GetDay(dayKey) or {}).counters)) do
            used = used + 1
            y = placeLine(used, y, text, "GameFontHighlightSmall", ENTRY_INDENT)
        end
    end
    if #dayKeys > MAX_DAYS then
        used = used + 1
        y = placeLine(used, y + DAY_GAP, L.JOURNAL_MORE_DAYS:format(#dayKeys - MAX_DAYS), "GameFontDisableSmall", 0)
    end
    for i = used + 1, #lines do
        lines[i]:Hide()
    end
    content:SetHeight(math.max(y, 1))
end

-- Many records in one frame (e.g. loot) cause a single redraw on the next frame.
function Journal:RequestRefresh()
    if refreshPending or not frame or not frame:IsShown() then return end
    refreshPending = true
    C_Timer.After(0, function() Journal:Refresh() end)
end

function Journal:Toggle()
    if not frame then
        createWindow()
    end
    frame:SetShown(not frame:IsShown())
end

ns.Bus:On("RECORD_ADDED", Journal, Journal.RequestRefresh)
ns.Bus:On("COUNTER_CHANGED", Journal, Journal.RequestRefresh)
ns.Bus:On("ITEM_NAMES_LOADED", Journal, Journal.RequestRefresh)
ns.Bus:On("SETTINGS_CHANGED", Journal, Journal.RequestRefresh)
ns.Bus:On("SAFE_MODE", Journal, Journal.RequestRefresh)
