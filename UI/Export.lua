local _, ns = ...
local L, Store, Time, DayView, YearCards = ns.L, ns.Store, ns.Time, ns.DayView, ns.YearCards

-- The journal leaves the game through the clipboard; addons can't write files (docs/ARCHITECTURE.md
-- §4.8, §7). Three windows share one look:
--   * the export: the journal as plain text, a copy to read, selected for Ctrl+C,
--   * the backup: the character's facts as one string, selected for Ctrl+C,
--   * the restore: an empty box to paste a backup into, checked before anything changes.
local Export = {}
ns.Export = Export

local RANGES = { "month", "year", "all" }
local VALID_RANGE = { month = true, year = true, all = true }
local WIDTH, HEIGHT = 640, 480
local PADDING = 20
local BUTTON_WIDTH = 120
local PASTE_KEPT = 4000 -- bytes the restore box holds; a paste arrives in full through OnChar
local RESTORE_POPUP = "WAYSCRIBE_RESTORE_BACKUP"

local export, backup, restore -- the windows, made when first opened

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
            YearCards.Plural("EXPORT_DAYS", #days)),
        "",
    }
    for _, dayKey in ipairs(days) do
        pageLines(out, dayKey)
    end
    return table.concat(out, "\n"), #days
end

------------------------------------------------------------------------------------------------
-- Windows

local function createTextBox(frame, top)
    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetPoint("TOPLEFT", PADDING, top)
    box:SetPoint("BOTTOMRIGHT", -PADDING, PADDING + 32)
    box:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    box:SetBackdropColor(0, 0, 0, 0.6)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(0)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(WIDTH - 2 * PADDING - 40)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    scroll:SetScrollChild(editBox)
    return editBox, scroll
end

-- A movable dialog: title, hint, a text box from `top` down, and a Close button.
local function createWindow(name, titleText, hintText, top)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
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
    tinsert(UISpecialFrames, name)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -PADDING)
    title:SetText(titleText)
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -46)
    hint:SetPoint("TOPRIGHT", -PADDING, -46)
    hint:SetJustifyH("LEFT")
    hint:SetText(hintText)

    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(BUTTON_WIDTH, 22)
    close:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    close:SetText(L.CLOSE)
    close:SetScript("OnClick", function() frame:Hide() end)

    local window = { frame = frame }
    window.box, window.scroll = createTextBox(frame, top)
    return window
end

-- A box that can't be changed, only selected and copied.
local function keepText(window)
    window.box:SetScript("OnTextChanged", function(box, userInput)
        if userInput then
            box:SetText(window.text or "")
            box:HighlightText()
        end
    end)
end

local function setText(window, text)
    window.text = text
    window.box:SetText(text)
    window.box:SetCursorPosition(0)
    window.box:HighlightText()
    window.box:SetFocus()
    window.scroll:SetVerticalScroll(0)
end

------------------------------------------------------------------------------------------------
-- Export

local function createExport()
    local window = createWindow("WayscribeExportFrame", L.EXPORT_TITLE, L.EXPORT_HINT, -108)
    window.rangeButtons = {}
    for i, range in ipairs(RANGES) do
        local button = CreateFrame("Button", nil, window.frame, "UIPanelButtonTemplate")
        button:SetSize(BUTTON_WIDTH, 22)
        button:SetPoint("TOPLEFT", PADDING + (i - 1) * (BUTTON_WIDTH + 6), -76)
        button:SetText(L["EXPORT_RANGE_" .. range:upper()])
        button:SetScript("OnClick", function() Export:Open(range) end)
        button.range = range
        window.rangeButtons[i] = button
    end
    window.summary = window.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.summary:SetPoint("LEFT", window.rangeButtons[#RANGES], "RIGHT", 12, 0)
    keepText(window)
    return window
end

-- Opens the window with the text of `range` (default: everything), selected for copying.
-- Works on a read-only journal too: reading is all it does.
function Export:Open(range)
    if not VALID_RANGE[range] then range = "all" end
    if not Store.db then
        ns.Print(L.EXPORT_NOTHING)
        return
    end
    export = export or createExport()
    local text, days = Export.BuildText(range)
    export.frame.range = range
    for _, button in ipairs(export.rangeButtons) do
        button:SetEnabled(button.range ~= range)
    end
    export.summary:SetText(YearCards.Plural("EXPORT_DAYS", days))
    setText(export, text)
    export.frame:Show()
end

function Export:GetText()
    return export and export.text
end

------------------------------------------------------------------------------------------------
-- Backup

local function kilobytes(bytes)
    return L.BACKUP_SIZE:format((string.format("%.1f", bytes / 1024):gsub("%.", L.DECIMAL_POINT)))
end

-- "1,234 entries on 56 days, 78 trails" from a backup's header.
local function contents(header, withTrails)
    local entries = YearCards.Plural("BACKUP_ENTRIES", header.entries or 0)
    local days = YearCards.Plural("CARD_DAYS", header.days or 0)
    if withTrails and header.count then
        return L.BACKUP_CONTENTS_TRAILS:format(entries, days, YearCards.Plural("BACKUP_TRAILS", header.count))
    end
    return L.BACKUP_CONTENTS:format(entries, days)
end

local function createBackup()
    local window = createWindow("WayscribeBackupFrame", L.BACKUP_TITLE, L.BACKUP_HINT, -108)
    local frame = window.frame
    local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", PADDING - 4, -74)
    check:SetScript("OnClick", function(button) Export:OpenBackup(button:GetChecked()) end)
    window.check = check
    window.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    window.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.summary:SetPoint("LEFT", window.label, "RIGHT", 16, 0)
    keepText(window)
    return window
end

-- Milliseconds, where the client can tell (developer mode prints how long things took).
local function clock()
    return type(debugprofilestop) == "function" and debugprofilestop() or nil
end

local function since(started)
    return started and (clock() - started) / 1000 or 0
end

local function backupReady(token, text, header)
    if backup.token ~= token or not backup.frame:IsShown() then return end
    if not text then
        setText(backup, header)
        return
    end
    backup.summary:SetText(contents(header, true) .. " · " .. kilobytes(#text))
    setText(backup, text)
    if ns.devMode then ns.Print(L.BACKUP_TIMING:format(since(token.started), kilobytes(#text))) end
end

local function showBackup(label, checked, enabled)
    backup = backup or createBackup()
    backup.check:SetChecked(checked)
    backup.check:SetEnabled(enabled)
    backup.label:SetText(label)
    backup.summary:SetText("")
    setText(backup, L.BACKUP_PREPARING)
    backup.frame:Show()
    local token = { started = clock() }
    backup.token = token
    return function(text, header) backupReady(token, text, header) end
end

-- /ws backup and Settings > Data: the backup string, made in the background and then selected.
-- With the footsteps unless withTrails is false, or they can't be read.
function Export:OpenBackup(withTrails)
    local problem = ns.Backup:CanMake()
    if problem then
        ns.Print(problem)
        return
    end
    local readable = ns.Paths.db ~= nil
    withTrails = readable and withTrails ~= false
    local done = showBackup(readable and L.BACKUP_WITH_FOOTSTEPS or L.BACKUP_NO_FOOTSTEPS, withTrails, readable)
    ns.Backup:Make({ trails = withTrails }, done)
end

-- /ws backup sample [days]: a made-up year in the same window, to time the clipboard with.
function Export:OpenSample(days)
    ns.Backup:MakeSample(days, showBackup(L.BACKUP_SAMPLE:format(days), true, false))
end

function Export:GetBackupText()
    return backup and backup.text
end

------------------------------------------------------------------------------------------------
-- Restore

local function owner(found)
    local meta = found.journal.meta
    return tostring(meta.name or found.header.name) .. "-" .. tostring(meta.realm or found.header.realm)
end

local function madeOn(found)
    return Time.FormatLongDay(Time.DayKey(found.header.made))
end

local function readyText(plan)
    if plan.refused then return plan.refused end
    if plan.journal and plan.trails then return L.RESTORE_READY_ALL end
    if plan.trails then return L.RESTORE_READY_TRAILS end
    if plan.keepsTrails then return L.RESTORE_READY_JOURNAL .. " " .. L.RESTORE_KEEPS_TRAILS end
    return L.RESTORE_READY_JOURNAL
end

local function confirmText(found, plan)
    local header = found.header
    local lines = {}
    if plan.journal then
        lines[1] = L.RESTORE_CONFIRM:format(owner(found), madeOn(found), contents(header, plan.trails))
    else
        lines[1] = L.RESTORE_CONFIRM_TRAILS:format(owner(found), madeOn(found),
            YearCards.Plural("BACKUP_TRAILS", header.count or 0))
    end
    lines[2] = ""
    if plan.foreign then
        lines[#lines + 1] = L.RESTORE_CONFIRM_FOREIGN:format(owner(found))
    end
    local replaced = {}
    if plan.replacesDays > 0 then replaced[#replaced + 1] = YearCards.Plural("EXPORT_DAYS", plan.replacesDays) end
    if plan.replacesTrails > 0 then replaced[#replaced + 1] = YearCards.Plural("BACKUP_TRAILS", plan.replacesTrails) end
    if #replaced > 0 then
        lines[#lines + 1] = L.RESTORE_CONFIRM_REPLACES:format(YearCards.List(replaced))
    end
    if plan.missing then
        lines[#lines + 1] = L.RESTORE_CONFIRM_MISSING
    end
    lines[#lines + 1] = L.RESTORE_CONFIRM_RELOAD
    return table.concat(lines, "\n")
end

-- A paste arrives as one OnChar per character, all within one frame. The box keeps only the first
-- few thousand bytes (a multi-line box with megabytes of text would stall the client), so the
-- characters are collected here and handed over on the next frame. Typed text arrives a
-- character per frame and is read from the box instead.
local pasted, pastedAt

local function finishPaste(box)
    box:SetScript("OnUpdate", nil)
    local text = table.concat(pasted)
    pasted = nil
    local shown = box:GetText() or ""
    Export:CheckRestore(#text >= #shown and text or shown, since(pastedAt))
end

local function onChar(box, char)
    if not pasted then
        pasted, pastedAt = {}, clock()
        box:SetScript("OnUpdate", finishPaste)
    end
    pasted[#pasted + 1] = char
end

local function createRestore()
    local window = createWindow("WayscribeRestoreFrame", L.RESTORE_TITLE, L.RESTORE_HINT, -112)
    local frame = window.frame
    window.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.status:SetPoint("TOPLEFT", PADDING, -72)
    window.status:SetPoint("TOPRIGHT", -PADDING, -72)
    window.status:SetHeight(34)
    window.status:SetJustifyH("LEFT")
    window.status:SetJustifyV("TOP")
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_WIDTH, 22)
    button:SetPoint("BOTTOMRIGHT", -PADDING - BUTTON_WIDTH - 8, PADDING)
    button:SetText(L.RESTORE_BUTTON)
    button:SetScript("OnClick", function() Export:ConfirmRestore() end)
    window.button = button
    window.box:SetMaxBytes(PASTE_KEPT)
    window.box:SetScript("OnChar", onChar)
    return window
end

-- /ws restore and Settings > Data: an empty box to paste a backup into.
function Export:OpenRestore()
    restore = restore or createRestore()
    restore.found, restore.token = nil, nil
    restore.box:SetText("")
    restore.status:SetText(L.RESTORE_WAITING)
    restore.button:SetEnabled(false)
    restore.frame:Show()
    restore.box:SetFocus()
end

-- Decodes and checks the pasted text in the background, then says what a restore would do.
-- pasteSeconds: how long the paste took (developer mode prints it).
function Export:CheckRestore(text, pasteSeconds)
    local window = restore
    if not window then return end
    window.found = nil
    window.button:SetEnabled(false)
    window.status:SetText(L.RESTORE_CHECKING)
    window.box:HighlightText() -- the next paste replaces it
    local token = {}
    window.token = token
    local started = clock()
    ns.Backup:Read(text, function(found, reason)
        if window.token ~= token then return end
        if ns.devMode then
            ns.Print(L.RESTORE_TIMING:format(#text, pasteSeconds or 0, since(started)))
        end
        if not found then
            window.status:SetText(reason)
            return
        end
        local plan = ns.Backup:Plan(found)
        window.found = found
        window.status:SetText(L.RESTORE_FOUND:format(owner(found), madeOn(found), contents(found.header, true))
            .. " " .. readyText(plan))
        window.button:SetEnabled(not plan.refused)
    end)
end

function Export:ConfirmRestore()
    local found = restore and restore.found
    if not found then return end
    local plan = ns.Backup:Plan(found)
    if plan.refused then
        restore.status:SetText(plan.refused)
        restore.button:SetEnabled(false)
        return
    end
    StaticPopupDialogs[RESTORE_POPUP] = StaticPopupDialogs[RESTORE_POPUP] or {
        text = "%s",
        button1 = L.RESTORE_ACCEPT,
        button2 = L.CANCEL,
        OnAccept = function() Export:ApplyRestore() end,
        showAlert = true,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show(RESTORE_POPUP, confirmText(found, plan))
end

-- Confirmed: swap the backup in and reload, so the trackers start on it and the client writes it.
function Export:ApplyRestore()
    local found = restore and restore.found
    if not found then return end
    local ok, reason = ns.Backup:Restore(found)
    if not ok then
        ns.Print(L.RESTORE_FAILED:format(reason))
        return
    end
    restore.found = nil
    restore.frame:Hide()
    ReloadUI()
end

function Export:GetRestoreStatus()
    return restore and restore.status:GetText()
end
