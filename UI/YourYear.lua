local _, ns = ...
local L, Compat, Store, Time, Theme, YearCards, DayView =
    ns.L, ns.Compat, ns.Store, ns.Time, ns.Theme, ns.YearCards, ns.DayView

-- Your Year, the yearly recap (docs/ARCHITECTURE.md §8): the journal's second tab. The left page
-- lists the years, the selected one with its cards; the right page shows one card, and the
-- journal's page buttons turn through the year like a slideshow. A year opens on December 1 (past
-- years any time); developer mode previews the current one. At the first login after a year
-- opens, a one-time prompt says it's ready.
local YourYear = ns.NewModule("youryear")
YourYear.enabled = true
ns.YourYear = YourYear

local OPENS_MONTH = 12
local ROW_HEIGHT = 24
local ICON_SIZE = 56
local LINE_GAP = 8
local PROMPT_DELAY = 6 -- seconds after the loading screen: after the login recap (3 s)
local PROMPT = "WAYSCRIBE_YOUR_YEAR"

local ui = { rows = {}, lines = {} }
YourYear.ui = ui
-- year: the year shown; index: its card on the right page; cards: that year's cards.
local state = { index = 1, cards = {}, years = {} }
YourYear.state = state

-- The opening card: "1,234 entries in your journal, 87 of them firsts."
YearCards:Register({
    id = "overview",
    order = 0,
    build = function(summary)
        local entries = YearCards.Sum(summary.rollup.records)
        if entries == 0 and summary.playSeconds <= 0 then return nil end
        local card = {
            title = L.CARD_OVERVIEW, icon = Theme.ICON,
            big = YearCards.Number(entries), caption = YearCards.Plural("CARD_OVERVIEW_ENTRIES", entries),
            lines = {},
        }
        if summary.rollup.firsts > 0 then
            card.lines[#card.lines + 1] = YearCards.Plural("CARD_OVERVIEW_FIRSTS", summary.rollup.firsts)
        end
        card.lines[#card.lines + 1] = L.CARD_OVERVIEW_DAYS:format(YearCards.Plural("CARD_DAYS", summary.activeDays),
            YearCards.Plural("CARD_MONTHS", summary.months))
        return card
    end,
})

------------------------------------------------------------------------------------------------
-- Which years

-- Past years are open; the current one from December 1.
function YourYear.IsOpen(year)
    local current, month = Time.SplitDay(Time.DayKey(Time.Now()))
    return year < current or (year == current and month >= OPENS_MONTH)
end

-- { year, open, preview } for every year with entries, newest first. Developer mode opens the
-- current year early, marked as a preview.
function YourYear.Years()
    local list = {}
    for _, year in ipairs(Store.db and Store:GetYears() or {}) do
        local open = YourYear.IsOpen(year)
        list[#list + 1] = { year = year, open = open or ns.devMode, preview = not open and ns.devMode or nil }
    end
    return list
end

local function entryOf(year)
    for _, entry in ipairs(state.years) do
        if entry.year == year then return entry end
    end
    return nil
end

-- Shows `year` from its first card; nil for the newest open year.
function YourYear:Select(year)
    state.year = year
    state.index = 1
end

-- delta 1 is the next card, -1 the previous one. Returns whether it turned.
function YourYear:Turn(delta)
    local index = state.index + delta
    if index < 1 or index > #state.cards then return false end
    state.index = index
    return true
end

------------------------------------------------------------------------------------------------
-- The right page: one card, or why there is none

-- { title, subtitle, icon?, big?, caption?, lines }
function YourYear.BuildPage()
    local entry = state.year and entryOf(state.year)
    if not entry then
        return { title = L.YOUR_YEAR, subtitle = "", lines = { L.YOUR_YEAR_EMPTY } }
    end
    local subtitle = L.YOUR_YEAR_OF:format(entry.year)
    if not entry.open then
        local opens = Time.FormatLongDay(entry.year * 10000 + OPENS_MONTH * 100 + 1)
        return { title = subtitle, subtitle = "", lines = { L.YOUR_YEAR_LOCKED:format(opens) } }
    end
    if entry.preview then
        subtitle = subtitle .. " · " .. L.YOUR_YEAR_PREVIEW
    end
    local card = state.cards[state.index]
    if not card then
        return { title = subtitle, subtitle = "", lines = { L.YOUR_YEAR_NOTHING } }
    end
    return {
        title = card.title, subtitle = subtitle, icon = card.icon, big = card.big, caption = card.caption,
        lines = card.lines,
    }
end

local function getLine(index)
    local line = ui.lines[index]
    if not line then
        line = Theme.Text(ui.right, "text")
        line:SetWordWrap(true)
        ui.lines[index] = line
    end
    return line
end

local function showPage(page, paperWidth)
    local insets = DayView.INSETS
    local width = math.max(DayView.TextWidth(paperWidth or 0), 1)
    ui.title:SetText(page.title)
    ui.subtitle:SetText(page.subtitle)
    local y = insets.top + 82
    ui.icon:SetShown(page.icon ~= nil)
    ui.big:SetShown(page.big ~= nil)
    ui.caption:SetShown(page.caption ~= nil)
    if page.icon or page.big then
        ui.icon:SetTexture(page.icon)
        ui.big:SetText(page.big or "")
        ui.caption:SetText(page.caption or "")
        y = y + ICON_SIZE + 2 * LINE_GAP
    end
    for i, text in ipairs(page.lines) do
        local line = getLine(i)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", ui.right, "TOPLEFT", insets.spine, -y)
        line:SetWidth(width)
        line:SetText(text)
        line:Show()
        y = y + line:GetStringHeight() + LINE_GAP
    end
    for i = #page.lines + 1, #ui.lines do
        ui.lines[i]:Hide()
    end
end

------------------------------------------------------------------------------------------------
-- The left page: the years, and the cards of the one shown

local function onRowClick(row)
    if row.cardIndex then
        state.index = row.cardIndex
    elseif row.year ~= state.year then
        YourYear:Select(row.year)
    end
    ns.Journal:Refresh()
end

local function getRow(index)
    local row = ui.rows[index]
    if not row then
        local insets = DayView.INSETS
        local top = insets.top + 64 + (index - 1) * ROW_HEIGHT
        row = CreateFrame("Button", nil, ui.left)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", insets.outer - 10, -top)
        row:SetPoint("TOPRIGHT", -insets.spine, -top)
        row.selected = Theme.Highlight(row)
        Theme.Fill(row, Theme.INK, "HIGHLIGHT", 0, 0.06)
        row.label = Theme.Text(row, "text")
        row.label:SetPoint("LEFT", 10, 0)
        row.detail = Theme.Text(row, "small", Theme.INK_FADED)
        row.detail:SetPoint("RIGHT", -8, 0)
        row.detail:SetJustifyH("RIGHT")
        row:SetScript("OnClick", onRowClick)
        ui.rows[index] = row
    end
    return row
end

-- Rows that don't fit on the page are left out (a long list would need years of journal).
local function showList(paperHeight)
    local insets = DayView.INSETS
    local fits = math.max(1, math.floor(((paperHeight or 0) - insets.top - 64 - 14) / ROW_HEIGHT))
    local used = 0
    local function add(text, detail, year, cardIndex, heading)
        if used >= fits then return end
        used = used + 1
        local row = getRow(used)
        Theme.Style(row.label, heading and "heading" or "text")
        row.label:SetText(text)
        row.detail:SetText(detail or "")
        row.year, row.cardIndex = year, cardIndex
        row.selected:SetShown(cardIndex ~= nil and cardIndex == state.index)
        row:Show()
    end
    for _, entry in ipairs(state.years) do
        local detail = not entry.open and Time.FormatDay(entry.year * 10000 + OPENS_MONTH * 100 + 1) or nil
        add(L.YOUR_YEAR_OF:format(entry.year), detail, entry.year, nil, true)
        if entry.year == state.year then
            for i, card in ipairs(state.cards) do
                add(card.title, nil, entry.year, i)
            end
        end
    end
    for i = used + 1, #ui.rows do
        ui.rows[i]:Hide()
    end
end

------------------------------------------------------------------------------------------------
-- Drawing, called by the journal

-- Both pages' layers, on the journal's paper frames; hidden until the tab is chosen.
function YourYear:Create(leftPaper, rightPaper)
    local insets = DayView.INSETS
    ui.left = CreateFrame("Frame", nil, leftPaper)
    ui.left:SetAllPoints()
    ui.right = CreateFrame("Frame", nil, rightPaper)
    ui.right:SetAllPoints()

    ui.header = Theme.Text(ui.left, "title")
    ui.header:SetPoint("TOPLEFT", insets.outer, -insets.top)
    ui.header:SetPoint("TOPRIGHT", -insets.spine, -insets.top)
    ui.header:SetText(L.YOUR_YEAR)
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

    -- The card's icon with its big number beside it and the caption under the number.
    ui.icon = ui.right:CreateTexture(nil, "ARTWORK")
    ui.icon:SetSize(ICON_SIZE, ICON_SIZE)
    ui.icon:SetPoint("TOPLEFT", insets.spine, -(insets.top + 82))
    ui.big = Theme.Text(ui.right, "huge")
    ui.big:SetPoint("TOPLEFT", ui.icon, "TOPRIGHT", 14, 2)
    ui.caption = Theme.Text(ui.right, "text", Theme.INK_FADED)
    ui.caption:SetPoint("BOTTOMLEFT", ui.icon, "BOTTOMRIGHT", 14, 2)

    ui.left:Hide()
    ui.right:Hide()
end

function YourYear:SetShown(shown)
    if not ui.left then return end
    ui.left:SetShown(shown)
    ui.right:SetShown(shown)
end

-- Draws both pages. Returns the card's number and the year's card count for the page controls,
-- or nil when there are no cards to turn.
function YourYear:Refresh(paperWidth, paperHeight)
    state.years = YourYear.Years()
    local entry = state.year and entryOf(state.year)
    if not entry then
        -- The newest year that is open, else the newest one.
        entry = state.years[1]
        for _, candidate in ipairs(state.years) do
            if candidate.open then
                entry = candidate
                break
            end
        end
        state.year = entry and entry.year
        state.index = 1
    end
    state.cards = entry and entry.open and YearCards:Build(entry.year) or {}
    state.index = math.max(1, math.min(state.index, #state.cards))
    showList(paperHeight)
    showPage(YourYear.BuildPage(), paperWidth)
    if #state.cards == 0 then return nil end
    return state.index, #state.cards
end

------------------------------------------------------------------------------------------------
-- The one-time prompt

YourYear:RegisterEvent("PLAYER_ENTERING_WORLD")

function YourYear:PLAYER_ENTERING_WORLD(isInitialLogin)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if Compat.Safe(isInitialLogin) == true then
        self:After(PROMPT_DELAY, self.PromptIfDue)
    end
end

-- The year that opened most recently, if this character has entries in it and hasn't been told.
function YourYear:DueYear()
    if not Store:IsWritable() then return nil end
    local current, month = Time.SplitDay(Time.DayKey(Time.Now()))
    local year = month >= OPENS_MONTH and current or current - 1
    local told = Store:GetState("yourYearPrompted")
    if type(told) == "number" and told >= year then return nil end
    for _, known in ipairs(Store:GetYears()) do
        if known == year then return year end
    end
    return nil
end

local function showPrompt(year)
    StaticPopupDialogs[PROMPT] = StaticPopupDialogs[PROMPT] or {
        text = L.YOUR_YEAR_READY,
        button1 = L.YOUR_YEAR_SHOW,
        button2 = L.YOUR_YEAR_LATER,
        OnAccept = function(_, data) ns.Journal:OpenYear(data) end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show(PROMPT, year, nil, year)
end

-- Once per year: a chat line, and a popup that opens the year. Waits for the login recap to close.
function YourYear:PromptIfDue()
    local year = self:DueYear()
    if not year then return end
    if ns.LoginRecap:IsShown() then
        ns.Bus:On("RECAP_HIDDEN", self, function(module)
            ns.Bus:Off("RECAP_HIDDEN", module)
            module:PromptIfDue()
        end)
        return
    end
    Store:SetState("yourYearPrompted", year)
    ns.Print(L.YOUR_YEAR_READY_CHAT:format(year))
    if type(StaticPopup_Show) == "function" then
        showPrompt(year)
    end
end
