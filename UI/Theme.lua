local _, ns = ...
local L = ns.L

-- The journal's book look (docs/ARCHITECTURE.md §7): a leather cover, parchment pages, ink and one
-- color per filter category. Only color textures and the client's own fonts, so nothing depends on
-- an art file that a client might not ship.
local Theme = {}
ns.Theme = Theme

Theme.COVER = { 0.24, 0.14, 0.08 }
Theme.COVER_EDGE = { 0.72, 0.56, 0.30 }
Theme.PAPER = { 0.94, 0.88, 0.74 }
Theme.PAPER_EDGE = { 0.78, 0.68, 0.50 }
Theme.SPINE = { 0.36, 0.24, 0.13 }
Theme.INK = { 0.20, 0.13, 0.07 }
Theme.INK_FADED = { 0.50, 0.41, 0.30 }

-- Unknown categories (and "misc", entries of a removed type) sort last and have no filter chip.
local CATEGORIES = {
    progress = { order = 1, color = { 0.16, 0.32, 0.58 } },
    adventure = { order = 2, color = { 0.62, 0.16, 0.12 } },
    quests = { order = 3, color = { 0.60, 0.42, 0.04 } },
    gathering = { order = 4, color = { 0.22, 0.45, 0.18 } },
}
local OTHER = { order = 99, color = Theme.INK_FADED }

function Theme.CategoryColor(category)
    return (CATEGORIES[category] or OTHER).color
end

function Theme.CategoryLabel(category)
    return rawget(L, "CATEGORY_" .. category:upper()) or category
end

-- The categories that get a filter chip, in display order.
function Theme.FilterCategories(categories)
    local chips = {}
    for _, category in ipairs(categories) do
        if category ~= "misc" then chips[#chips + 1] = category end
    end
    table.sort(chips, function(a, b)
        local orderA, orderB = (CATEGORIES[a] or OTHER).order, (CATEGORIES[b] or OTHER).order
        if orderA ~= orderB then return orderA < orderB end
        return a < b
    end)
    return chips
end

local FONTS = {
    title = "QuestTitleFont",
    label = "GameFontNormal",
    text = "GameFontHighlight",
    small = "GameFontHighlightSmall",
}

-- Ink on paper: the font of `kind`, the color, and no shadow (it blurs dark text on paper). A font
-- object brings its own color and shadow, so this runs again whenever the font changes.
function Theme.Style(fontString, kind, color)
    local font = FONTS[kind] or FONTS.text
    if not _G[font] then font = FONTS.text end
    fontString:SetFontObject(font)
    fontString:SetTextColor(unpack(color or Theme.INK))
    fontString:SetShadowOffset(0, 0)
end

-- A left-aligned font string in ink.
function Theme.Text(parent, kind, color)
    local text = parent:CreateFontString(nil, "OVERLAY")
    Theme.Style(text, kind, color)
    text:SetJustifyH("LEFT")
    return text
end

-- A solid texture over the whole frame, inset by `inset` pixels.
function Theme.Fill(frame, color, layer, inset, alpha)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetPoint("TOPLEFT", inset or 0, -(inset or 0))
    texture:SetPoint("BOTTOMRIGHT", -(inset or 0), inset or 0)
    texture:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    return texture
end

-- A parchment page with a darker rim.
function Theme.Page(frame)
    Theme.Fill(frame, Theme.PAPER_EDGE, "BACKGROUND")
    Theme.Fill(frame, Theme.PAPER, "BORDER", 2)
end
