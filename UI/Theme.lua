local addonName, ns = ...
local L, Compat = ns.L, ns.Compat

-- The journal looks like the default UI's spellbook (docs/ARCHITECTURE.md §7): the client's own
-- parchment pages, header divider, fonts and ink color. Each piece is checked against the client
-- (atlases by name, fonts by global) and falls back to plain colors, so a client without them
-- still gets a readable book.
local Theme = {}
ns.Theme = Theme

-- Wayscribe's icon (source: Media/Icon.svg).
Theme.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon"
-- The same picture redrawn bolder for the places that show it at about 20 px: the minimap button
-- and, through the TOC's IconTexture, the Addon Compartment and the addon list (source:
-- Media/IconSmall.svg).
Theme.ICON_SMALL = "Interface\\AddOns\\" .. addonName .. "\\Media\\IconSmall"

-- SPELLBOOK_FONT_COLOR on client 1.60.1.70235 (GlobalColor.db2), used when the global is missing.
local SPELLBOOK_INK = { 0.18, 0.106, 0.059 }

Theme.PAPER = { 0.94, 0.88, 0.74 }
Theme.PAPER_EDGE = { 0.78, 0.68, 0.50 }
Theme.INK = SPELLBOOK_INK
-- Secondary text (times, subtitles) is the same ink, lighter: like "Passive" in the spellbook.
Theme.INK_FADED = { SPELLBOOK_INK[1], SPELLBOOK_INK[2], SPELLBOOK_INK[3], 0.8 }

-- The default UI's ink, once the client's colors are loaded.
function Theme.Resolve()
    local color = SPELLBOOK_FONT_COLOR
    if type(color) == "table" and type(color.GetRGB) == "function" then
        local r, g, b = Compat.Call(color.GetRGB, color)
        if r and g and b then
            Theme.INK = { r, g, b }
            Theme.INK_FADED = { r, g, b, 0.8 }
        end
    end
end

-- Forever's spellbook pages first, then the retail spellbook's.
local PAGE_ATLASES = {
    left = { "spellbook-page-left-c60", "spellbook-background-evergreen-left" },
    right = { "spellbook-page-right-c60", "spellbook-background-evergreen-right" },
}

-- Where the parchment lies inside the page art, as shares of its size. Forever's pages carry the
-- spellbook's dark top bar in their upper 9% and dark rims on the outer edge and bottom (measured
-- from interface/spellbook/spellbookbackgroundpage{left,right}c60.blp of client 1.60.1.70235).
local NO_RIMS = { top = 0, bottom = 0, outer = 0, spine = 0 }
local ART_RIMS = {
    ["spellbook-page-left-c60"] = { top = 0.094, bottom = 0.03, outer = 0.035, spine = 0.01 },
    ["spellbook-page-right-c60"] = { top = 0.094, bottom = 0.03, outer = 0.025, spine = 0.01 },
}
local DIVIDER_ATLAS = "spellbook-divider"
local HIGHLIGHT_ATLAS = "spellbook-list-backplate"

-- Unknown categories (and "misc", entries of a removed type) sort last and have no filter.
local CATEGORIES = {
    progress = { order = 1, color = { 0.16, 0.30, 0.52 } },
    adventure = { order = 2, color = { 0.56, 0.14, 0.10 } },
    quests = { order = 3, color = { 0.62, 0.42, 0.04 } },
    gathering = { order = 4, color = { 0.20, 0.42, 0.16 } },
    travel = { order = 5, color = { 0.12, 0.38, 0.42 } },
}
local OTHER = { order = 99, color = Theme.INK_FADED }

function Theme.CategoryColor(category)
    return (CATEGORIES[category] or OTHER).color
end

function Theme.CategoryLabel(category)
    return rawget(L, "CATEGORY_" .. category:upper()) or category
end

-- The categories that get a filter, in display order.
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

-- The spellbook's fonts (header, entry name, sub text), with plainer ones as fallback.
local FONTS = {
    huge = { "Game40Font", "SystemFont_Huge4", "SystemFont_Huge2", "GameFontNormalHuge" }, -- Your Year's numbers
    title = { "SystemFont_Huge2", "GameFontNormalHuge" },
    heading = { "SystemFont_Large", "GameFontNormalLarge" },
    text = { "SystemFont_Med3", "GameFontHighlight" },
    small = { "SystemFont_Med1", "GameFontHighlightSmall" },
}

local function fontOf(kind)
    local choices = FONTS[kind] or FONTS.text
    for _, name in ipairs(choices) do
        if _G[name] then return name end
    end
    return choices[#choices]
end

-- Ink on paper: the font of `kind`, the color, and no shadow (it blurs dark text on paper). A font
-- object brings its own color and shadow, so this runs again whenever the font changes.
function Theme.Style(fontString, kind, color)
    fontString:SetFontObject(fontOf(kind))
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

-- The first atlas of `names` this client has, or nil.
local function firstAtlas(names)
    for _, name in ipairs(names) do
        if Compat.HasAtlas(name) then return name end
    end
    return nil
end

-- A spellbook page ("left" or "right") filling the frame; parchment colors without the art.
-- Returns the page's rims: { top, bottom, outer, spine } as shares of its size.
function Theme.Page(frame, side)
    local atlas = firstAtlas(PAGE_ATLASES[side])
    if atlas then
        local texture = frame:CreateTexture(nil, "BACKGROUND")
        texture:SetAllPoints()
        texture:SetAtlas(atlas, false)
        return ART_RIMS[atlas] or NO_RIMS
    end
    Theme.Fill(frame, Theme.PAPER_EDGE, "BACKGROUND")
    Theme.Fill(frame, Theme.PAPER, "BORDER", 2)
    return NO_RIMS
end

-- The ornament under a spellbook header, or a faint rule. Anchor it yourself.
function Theme.Divider(parent)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    if Compat.HasAtlas(DIVIDER_ATLAS) then
        texture:SetAtlas(DIVIDER_ATLAS, false)
        texture:SetHeight(11)
    else
        texture:SetColorTexture(Theme.INK_FADED[1], Theme.INK_FADED[2], Theme.INK_FADED[3], 0.5)
        texture:SetHeight(1)
    end
    return texture
end

-- The soft shadow the spellbook puts behind a header, used to mark the selected day.
function Theme.Highlight(frame)
    if Compat.HasAtlas(HIGHLIGHT_ATLAS) then
        local texture = frame:CreateTexture(nil, "BACKGROUND")
        texture:SetAllPoints()
        texture:SetAtlas(HIGHLIGHT_ATLAS, false)
        texture:SetAlpha(0.8)
        return texture
    end
    return Theme.Fill(frame, Theme.INK, "BACKGROUND", 0, 0.12)
end
