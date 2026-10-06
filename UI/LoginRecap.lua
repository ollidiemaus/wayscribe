local _, ns = ...
local L, Compat, Store, Time, RecordTypes = ns.L, ns.Compat, ns.Store, ns.Time, ns.RecordTypes

-- "Last session" popup at the first login of a day (docs/ARCHITECTURE.md §7): the previous
-- session's entries plus the counter totals of its day(s).
local LoginRecap = ns.NewModule("loginrecap")
LoginRecap.enabled = true
ns.LoginRecap = LoginRecap

-- Lets the loading screen and the chat spam of other addons settle first.
local SHOW_DELAY = 3
local MAX_LINES = 12
local WIDTH = 400
local PADDING = 20
local LINE_GAP = 4

local frame, subtitle, dontShow
local lines = {}

LoginRecap:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Only the loading screen of the actual login matters.
function LoginRecap:PLAYER_ENTERING_WORLD(isInitialLogin)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if Compat.Safe(isInitialLogin) == true then
        self:After(SHOW_DELAY, self.ShowIfDue)
    end
end

-- What the popup shows: { day, duration?, lines }, or nil when there is nothing to recap.
-- force (from /ws recap) skips the setting and the once-a-day rule.
function LoginRecap:Collect(force)
    if not Store.db then return nil end
    if not force then
        if not Store:IsWritable() or not ns.Options:Get("showLoginRecap") then return nil end
        local today = Time.DayKey(Time.Now())
        if Store:GetState("lastRecapDay") == today then return nil end
        Store:SetState("lastRecapDay", today)
    end
    local session = Store:GetPreviousSession()
    if not session then return nil end
    -- A session without an end crashed; everything until now belongs to it or to this login.
    local records, counters = Store:GetActivity(session.s, session.e or Time.Now())
    local recap = { day = Time.DayKey(session.s), duration = session.e and (session.e - session.s), lines = {} }
    for _, record in ipairs(records) do
        if not record.sim then
            recap.lines[#recap.lines + 1] = RecordTypes:Render(record)
        end
    end
    for _, text in ipairs(RecordTypes:RenderCounters(counters)) do
        recap.lines[#recap.lines + 1] = text
    end
    if #recap.lines == 0 then return nil end
    return recap
end

function LoginRecap:ShowIfDue()
    local recap = self:Collect()
    if recap then
        self:Show(recap)
    end
end

local function createButton(parent, text, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(120, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function createWindow()
    frame = CreateFrame("Frame", "WayscribeLoginRecapFrame", UIParent, "BackdropTemplate")
    frame:SetWidth(WIDTH)
    frame:SetPoint("TOP", 0, -140)
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
    tinsert(UISpecialFrames, "WayscribeLoginRecapFrame")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -PADDING)
    title:SetText(L.RECAP_TITLE)
    subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)

    local open = createButton(frame, L.RECAP_OPEN, function()
        frame:Hide()
        ns.Journal:Toggle()
    end)
    open:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, PADDING)
    local close = createButton(frame, L.CLOSE, function() frame:Hide() end)
    close:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, PADDING)

    dontShow = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    dontShow:SetSize(24, 24)
    dontShow:SetPoint("BOTTOMLEFT", PADDING - 4, PADDING + 26)
    dontShow:SetScript("OnClick", function(button)
        ns.Options:Set("showLoginRecap", not button:GetChecked())
    end)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", dontShow, "RIGHT", 2, 0)
    label:SetText(L.RECAP_DONT_SHOW)
end

local function placeLine(index, y, text)
    local line = lines[index]
    if not line then
        line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line:SetJustifyH("LEFT")
        line:SetWordWrap(true)
        lines[index] = line
    end
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 4, -y)
    line:SetWidth(WIDTH - 2 * PADDING - 8)
    line:SetText(text)
    line:Show()
    return y + line:GetStringHeight() + LINE_GAP
end

function LoginRecap:Show(recap)
    if not frame then
        createWindow()
    end
    local when = Time.FormatDay(recap.day)
    subtitle:SetText(recap.duration and L.RECAP_SUBTITLE:format(when, Time.FormatDuration(recap.duration)) or when)
    dontShow:SetChecked(not ns.Options:Get("showLoginRecap"))

    local y, used = 64, 0
    for i = 1, math.min(#recap.lines, MAX_LINES) do
        used = used + 1
        y = placeLine(used, y, "- " .. recap.lines[i])
    end
    if #recap.lines > MAX_LINES then
        used = used + 1
        y = placeLine(used, y, L.RECAP_MORE:format(#recap.lines - MAX_LINES))
    end
    for i = used + 1, #lines do
        lines[i]:Hide()
    end
    frame:SetHeight(y + 2 * PADDING + 52)
    frame:Show()
end
