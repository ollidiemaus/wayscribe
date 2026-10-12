local _, ns = ...
local L, Compat, Store, Time, Theme, DayView, Duels =
    ns.L, ns.Compat, ns.Store, ns.Time, ns.Theme, ns.DayView, ns.Duels

-- The journal's Duels tab (docs/ARCHITECTURE.md §7.1): every duel the character finished, added
-- up. The left page lists "All duels" and then each opponent, most dueled first; the right page
-- shows the one picked: for all duels the record, by class, and the latest ones; for an opponent
-- the record against them and every duel with them. The page buttons step through the list.
local DuelsView = {}
ns.DuelsView = DuelsView

local ROW_HEIGHT = 24
local LIST_TOP = 38      -- below the header
local BODY_TOP = 70      -- the page's lines, under the title and a subtitle of up to two lines
local LINE_GAP = 6
local SECTION_GAP = 10
local MARKER_SIZE = 14
local RECENT = 8         -- duels on the "All duels" page
local HISTORY = 14       -- duels on an opponent's page

local ui = { lines = {} }
DuelsView.ui = ui
-- stats: Duels.Collect(), redone when a duel is added or the tab opens (dirty); key: the opponent
-- shown, nil for all duels.
local state = { dirty = true }
DuelsView.state = state

local function stats()
    if state.dirty or not state.stats then
        state.stats = Duels.Collect()
        state.dirty = false
    end
    return state.stats
end

-- The list's entries: all duels, then the opponents.
local function entries()
    local list = { { all = true } }
    for _, opponent in ipairs(stats().opponents) do
        list[#list + 1] = { key = opponent.key, opponent = opponent }
    end
    return list
end

local function indexOf(list, key)
    if key == nil then return 1 end
    for i, entry in ipairs(list) do
        if entry.key == key then return i end
    end
    return nil
end

local function opponentOf(key)
    for _, opponent in ipairs(stats().opponents) do
        if opponent.key == key then return opponent end
    end
    return nil
end

-- "5–2"
local function record(won, total)
    return L.DUELS_RECORD:format(won, total - won)
end

-- "37 duels · 24 won · 13 lost · 65%"
local function summary(won, total)
    local count = total == 1 and L.DUELS_COUNT_ONE or L.DUELS_COUNT:format(total)
    return table.concat({ count, L.DUELS_WON:format(won), L.DUELS_LOST:format(total - won), Duels.Rate(won, total) }, " · ")
end

local function dateOf(rec)
    return Time.FormatDay(Time.DayKey(rec.ts))
end

------------------------------------------------------------------------------------------------
-- Selecting

-- key: an opponent's key from Duels.Collect(), nil for all duels.
function DuelsView:Select(key)
    state.key = key
end

-- step 1 turns back (up the list), -1 on. Returns whether it turned.
function DuelsView:Turn(step)
    local list = entries()
    local target = list[(indexOf(list, state.key) or 1) - step]
    if not target then return false end
    state.key = target.key
    return true
end

------------------------------------------------------------------------------------------------
-- The right page

-- { title, subtitle, lines = { { text, detail?, heading?, class?, wrap? } } }
function DuelsView.BuildPage()
    local all = stats()
    if all.total == 0 then
        return { title = L.DUELS_ALL, subtitle = "", lines = { { text = L.DUELS_EMPTY, wrap = true } } }
    end
    local opponent = state.key ~= nil and opponentOf(state.key)
    local lines = {}
    if not opponent then
        lines[#lines + 1] = { text = L.DUELS_BY_CLASS, heading = true }
        for _, class in ipairs(all.classes) do
            lines[#lines + 1] = {
                text = Compat.GetClassName(class.class) or class.class, class = class.class,
                detail = record(class.won, class.n) .. " · " .. Duels.Rate(class.won, class.n),
            }
        end
        lines[#lines + 1] = { text = L.DUELS_RECENT, heading = true }
        for i = 1, math.min(RECENT, #all.records) do
            local data = all.records[i].data
            local name = Duels.NameOf(data.p or data.name)
            lines[#lines + 1] = { text = Duels.ResultText(data) .. " · " .. name, detail = dateOf(all.records[i]) }
        end
        return { title = L.DUELS_ALL, subtitle = summary(all.won, all.total), lines = lines }
    end
    lines[#lines + 1] = { text = L.DUELS_HISTORY, heading = true }
    local shown, total = 0, 0
    for _, rec in ipairs(all.records) do
        local data = rec.data
        if (data.p or data.name) == opponent.key then
            total = total + 1
            if shown < HISTORY then
                shown = shown + 1
                local place = Duels.PlaceOf(data)
                local text = Duels.ResultText(data)
                if place then text = text .. " · " .. place end
                lines[#lines + 1] = { text = text, detail = dateOf(rec) }
            end
        end
    end
    if total > shown then
        lines[#lines + 1] = { text = L.DUELS_MORE:format(total - shown) }
    end
    local parts = {}
    local class = Compat.GetClassName(opponent.class)
    if class and opponent.level then
        parts[1] = L.DUEL_CLASS_LEVEL:format(class, opponent.level)
    elseif opponent.level then
        parts[1] = L.DUEL_LEVEL:format(opponent.level)
    elseif class then
        parts[1] = class
    end
    parts[#parts + 1] = summary(opponent.won, opponent.n)
    return { title = opponent.name, subtitle = table.concat(parts, " · "), lines = lines }
end

-- The class's icon, or a square of its color; hidden without a class.
local function showMarker(marker, class)
    if not class then
        marker:Hide()
        return
    end
    local atlas = "classicon-" .. class:lower()
    if Compat.HasAtlas(atlas) then
        marker:SetAtlas(atlas, false)
    else
        local r, g, b = Compat.GetClassColor(class)
        marker:SetColorTexture(r or 0.5, g or 0.5, b or 0.5, 1)
    end
    marker:Show()
end

local function getLine(index)
    local line = ui.lines[index]
    if not line then
        line = {
            label = Theme.Text(ui.right, "text"),
            detail = Theme.Text(ui.right, "small", Theme.INK_FADED),
            marker = ui.right:CreateTexture(nil, "ARTWORK"),
        }
        line.detail:SetJustifyH("RIGHT")
        line.marker:SetSize(MARKER_SIZE, MARKER_SIZE)
        ui.lines[index] = line
    end
    return line
end

local function hideLine(line)
    line.label:Hide()
    line.detail:Hide()
    line.marker:Hide()
end

-- Lines that don't fit on the paper are left out.
local function showPage(page, paperWidth, paperHeight)
    local insets = DayView.INSETS
    local width = math.max(DayView.TextWidth(paperWidth or 0), 1)
    local bottom = (paperHeight or 0) - insets.bottom
    ui.title:SetText(page.title)
    ui.subtitle:SetText(page.subtitle)
    local y = insets.top + BODY_TOP
    local used = 0
    for i, spec in ipairs(page.lines) do
        local line = getLine(i)
        if spec.heading and i > 1 then y = y + SECTION_GAP end
        Theme.Style(line.label, spec.heading and "heading" or "text")
        local left = insets.spine + (spec.class and MARKER_SIZE + 6 or 0)
        line.detail:SetText(spec.detail or "")
        local detailWidth = spec.detail and (line.detail:GetStringWidth() or 0) + 8 or 0
        line.label:ClearAllPoints()
        line.label:SetPoint("TOPLEFT", ui.right, "TOPLEFT", left, -y)
        line.label:SetWidth(math.max(width - (left - insets.spine) - detailWidth, 1))
        line.label:SetWordWrap(spec.wrap == true)
        line.label:SetText(spec.text)
        local height = line.label:GetStringHeight() or 0
        if paperHeight and y + height > bottom then break end
        line.detail:ClearAllPoints()
        line.detail:SetPoint("TOPRIGHT", ui.right, "TOPLEFT", insets.spine + width, -y)
        line.marker:ClearAllPoints()
        line.marker:SetPoint("LEFT", line.label, "LEFT", -(MARKER_SIZE + 6), 0)
        showMarker(line.marker, spec.class)
        line.label:Show()
        line.detail:SetShown(spec.detail ~= nil)
        used = i
        y = y + height + LINE_GAP
    end
    for i = used + 1, #ui.lines do
        hideLine(ui.lines[i])
    end
end

------------------------------------------------------------------------------------------------
-- The left page: all duels, then the opponents

local function onRowClick(row)
    DuelsView:Select(row.key)
    ns.Journal:Refresh()
end

local function initRow(row, entry)
    if not row.label then
        row.selected = Theme.Highlight(row)
        Theme.Fill(row, Theme.INK, "HIGHLIGHT", 0, 0.06)
        row.marker = row:CreateTexture(nil, "ARTWORK")
        row.marker:SetSize(MARKER_SIZE, MARKER_SIZE)
        row.marker:SetPoint("LEFT", 8, 0)
        row.detail = Theme.Text(row, "small", Theme.INK_FADED)
        row.detail:SetPoint("RIGHT", -8, 0)
        row.detail:SetJustifyH("RIGHT")
        row.label = Theme.Text(row, "text")
        row.label:SetWordWrap(false)
        row:SetScript("OnClick", onRowClick)
    end
    row.key = entry.key
    local all = stats()
    local opponent = entry.opponent
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", opponent and 8 + MARKER_SIZE + 6 or 8, 0)
    row.label:SetPoint("RIGHT", row.detail, "LEFT", -6, 0)
    row.label:SetText(opponent and opponent.name or L.DUELS_ALL)
    row.detail:SetText(opponent and record(opponent.won, opponent.n) or record(all.won, all.total))
    showMarker(row.marker, opponent and opponent.class)
    row.selected:SetShown(entry.key == state.key)
end

-- As many rows as fit, around the one shown.
local function showList(list, paperHeight)
    local insets = DayView.INSETS
    local top, bottom = insets.top + LIST_TOP, 14
    local count = math.max(1, math.floor(((paperHeight or 0) - top - bottom) / ROW_HEIGHT))
    local selected = indexOf(list, state.key) or 1
    local first = math.max(1, math.min(selected - math.floor(count / 2), #list - count + 1))
    ui.rows = ui.rows or {}
    for i = 1, math.max(count, #ui.rows) do
        local entry = i <= count and list[first + i - 1]
        local row = ui.rows[i]
        if entry then
            if not row then
                row = CreateFrame("Button", nil, ui.left)
                row:SetHeight(ROW_HEIGHT)
                row:SetPoint("TOPLEFT", insets.outer - 10, -(top + (i - 1) * ROW_HEIGHT))
                row:SetPoint("TOPRIGHT", -insets.spine, -(top + (i - 1) * ROW_HEIGHT))
                ui.rows[i] = row
            end
            initRow(row, entry)
            row:Show()
        elseif row then
            row:Hide()
        end
    end
end

------------------------------------------------------------------------------------------------
-- Drawing, called by the journal

function DuelsView:Create(leftPaper, rightPaper)
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

    ui.title = Theme.Text(ui.right, "title")
    ui.title:SetPoint("TOPLEFT", insets.spine, -insets.top)
    ui.title:SetPoint("TOPRIGHT", -insets.outer, -insets.top)
    ui.title:SetWordWrap(false)
    local rule = Theme.Divider(ui.right)
    rule:SetPoint("TOPLEFT", ui.title, "BOTTOMLEFT", -12, -4)
    rule:SetPoint("TOPRIGHT", ui.title, "BOTTOMRIGHT", 12, -4)
    ui.subtitle = Theme.Text(ui.right, "small", Theme.INK_FADED)
    ui.subtitle:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 12, -4)
    ui.subtitle:SetPoint("TOPRIGHT", rule, "BOTTOMRIGHT", -12, -4)
    ui.subtitle:SetWordWrap(true)
    ui.subtitle:SetMaxLines(2)

    ui.left:Hide()
    ui.right:Hide()
end

-- The numbers are counted again each time the tab opens.
function DuelsView:SetShown(shown)
    if not ui.left then return end
    if shown and not ui.right:IsShown() then state.dirty = true end
    ui.left:SetShown(shown)
    ui.right:SetShown(shown)
end

-- Draws both pages. Returns the shown entry's place in the list and the list's length, for the
-- page controls; nil without duels.
function DuelsView:Refresh(paperWidth, paperHeight)
    local list = entries()
    if not indexOf(list, state.key) then
        state.key = nil -- an opponent from another character, or before a rebuild
    end
    local name = Store.db and Store.db.meta.name
    ui.header:SetText(name and L.DUELS_OF:format(name) or L.TAB_DUELS)
    local empty = stats().total == 0
    showList(empty and {} or list, paperHeight)
    showPage(DuelsView.BuildPage(), paperWidth, paperHeight)
    if empty then return nil, 0 end
    return indexOf(list, state.key), #list
end

function DuelsView:OnRecordAdded(rec)
    if rec.type == "DUEL" then state.dirty = true end
end

function DuelsView:OnChanged()
    state.dirty = true
end

ns.Bus:On("RECORD_ADDED", DuelsView, DuelsView.OnRecordAdded)
ns.Bus:On("REBUILT", DuelsView, DuelsView.OnChanged)
