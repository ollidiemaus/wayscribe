local addonName, ns = ...
local Charted = ns.Charted

-- One floor of a dungeon map under its fog (docs/dungeon-maps.md), fitted into any size: the
-- client's own map tiles by file ID, then fog over the cells of every section not found yet. The
-- fog cells of a row are merged into one texture, and a soft dot sits on each fog cell at the edge
-- of what was found, so the border looks inked, not cut out. A section found while the map is
-- shown fades out.
local DungeonMap = {}
DungeonMap.__index = DungeonMap
ns.DungeonMap = DungeonMap

local ART_W, ART_H, ART_TILE = 1002, 668, 256
local MINIMAP_TILE = 512
local FOG_SHADE = 0.8   -- the parchment a little darker: unexplored, not blank
local DOT = "Interface\\AddOns\\" .. addonName .. "\\Media\\FogDot"
local DOT_CELLS = 2.2   -- a dot's size in cells
local FADE = 1.2        -- seconds a found section takes to clear

function DungeonMap.Create(parent)
    local self = setmetatable({ tiles = {}, fog = {}, fogUsed = 0, fading = {} }, DungeonMap)
    local frame = CreateFrame("Frame", nil, parent)
    if frame.SetClipsChildren then frame:SetClipsChildren(true) end
    self.frame = frame
    self.fogLayer = CreateFrame("Frame", nil, frame)
    self.fogLayer:SetAllPoints()
    frame:SetScript("OnUpdate", function(_, elapsed) self:Fade(elapsed) end)
    frame:Hide()
    return self
end

------------------------------------------------------------------------------------------------
-- The art

local function tile(self, i)
    local texture = self.tiles[i]
    if not texture then
        texture = self.frame:CreateTexture(nil, "BACKGROUND")
        self.tiles[i] = texture
    end
    texture:ClearAllPoints()
    texture:SetTexCoord(0, 1, 0, 1)
    texture:Show()
    return texture
end

-- A retail dungeon map: 4 x 3 tiles of 256 px, of which the top-left 1002 x 668 is the map.
local function drawArt(self, floor, scale)
    for i, fileID in ipairs(floor.art) do
        local row, col = math.floor((i - 1) / 4), (i - 1) % 4
        local texture = tile(self, i)
        texture:SetTexture(fileID)
        texture:SetSize(ART_TILE * scale, ART_TILE * scale)
        texture:SetPoint("TOPLEFT", self.frame, "TOPLEFT", col * ART_TILE * scale, -row * ART_TILE * scale)
    end
    return #floor.art
end

-- Forever's own instances: a block of minimap tiles, cropped.
local function drawMinimap(self, floor, scale)
    local cols, rows = floor.tiles[1], floor.tiles[2]
    local x0, y0 = floor.crop[1] * cols * MINIMAP_TILE, floor.crop[2] * rows * MINIMAP_TILE
    local used = 0
    for i, fileID in ipairs(floor.minimap) do
        if fileID > 0 then
            used = used + 1
            local row, col = math.floor((i - 1) / cols), (i - 1) % cols
            local texture = tile(self, used)
            texture:SetTexture(fileID)
            texture:SetSize(MINIMAP_TILE * scale, MINIMAP_TILE * scale)
            texture:SetPoint("TOPLEFT", self.frame, "TOPLEFT", (col * MINIMAP_TILE - x0) * scale,
                -(row * MINIMAP_TILE - y0) * scale)
        end
    end
    return used
end

-- The floor's size in its own pixels.
local function naturalSize(floor)
    if floor.art then return ART_W, ART_H end
    local cols, rows = floor.tiles[1], floor.tiles[2]
    return (floor.crop[3] - floor.crop[1]) * cols * MINIMAP_TILE, (floor.crop[4] - floor.crop[2]) * rows * MINIMAP_TILE
end
DungeonMap.NaturalSize = naturalSize

------------------------------------------------------------------------------------------------
-- The fog

local function fogTexture(self, section)
    self.fogUsed = self.fogUsed + 1
    local texture = self.fog[self.fogUsed]
    if not texture then
        texture = self.fogLayer:CreateTexture(nil, "ARTWORK")
        self.fog[self.fogUsed] = texture
    end
    texture.section = section
    texture:ClearAllPoints()
    texture:SetAlpha(1)
    texture:Show()
    return texture
end

function DungeonMap:DrawFog()
    for i = 1, self.fogUsed do self.fog[i]:Hide() end
    self.fogUsed = 0
    self.fading = {}
    local floor = self.floor
    local cols, rows = floor.grid[1], floor.grid[2]
    local cells = Charted.Cells(floor)
    local shown = Charted:Revealed(self.instanceID)
    local cw, ch = self.width / cols, self.height / rows
    local r, g, b = floor.fog[1] * FOG_SHADE, floor.fog[2] * FOG_SHADE, floor.fog[3] * FOG_SHADE
    local function fogged(row, col)
        if row < 0 or col < 0 or row >= rows or col >= cols then return nil end
        local section = cells[row * cols + col + 1]
        if section and section > 0 and not shown[section] then return section end
        return nil
    end
    for row = 0, rows - 1 do
        local col = 0
        while col < cols do
            local section = fogged(row, col)
            if section then
                local first = col
                while col < cols and fogged(row, col) == section do col = col + 1 end
                local texture = fogTexture(self, section)
                texture:SetVertexColor(1, 1, 1, 1)
                texture:SetColorTexture(r, g, b, 1)
                texture:SetPoint("TOPLEFT", self.fogLayer, "TOPLEFT", first * cw, -row * ch)
                texture:SetSize((col - first) * cw + 0.5, ch + 0.5)
            else
                col = col + 1
            end
        end
    end
    -- Soft dots along the edge of the fog.
    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local section = fogged(row, col)
            if section and not (fogged(row - 1, col) and fogged(row + 1, col) and fogged(row, col - 1) and fogged(row, col + 1)) then
                local texture = fogTexture(self, section)
                texture:SetTexture(DOT)
                texture:SetVertexColor(r, g, b, 1)
                texture:SetSize(DOT_CELLS * cw, DOT_CELLS * ch)
                texture:SetPoint("CENTER", self.fogLayer, "TOPLEFT", (col + 0.5) * cw, -(row + 0.5) * ch)
            end
        end
    end
end

-- Sections just found clear over FADE seconds; then the fog is drawn again around them.
function DungeonMap:Reveal(instanceID, sections)
    if instanceID ~= self.instanceID or not self.frame:IsShown() then return end
    local any = false
    for _, n in ipairs(sections) do
        self.fading[n] = 0
        any = true
    end
    if not any then return end
    self.fadeLeft = FADE
end

function DungeonMap:Fade(elapsed)
    if not self.fadeLeft then return end
    self.fadeLeft = self.fadeLeft - (elapsed or 0)
    local alpha = math.max(0, self.fadeLeft / FADE)
    for i = 1, self.fogUsed do
        local texture = self.fog[i]
        if self.fading[texture.section] then texture:SetAlpha(alpha) end
    end
    if self.fadeLeft <= 0 then
        self.fadeLeft = nil
        self:DrawFog()
    end
end

------------------------------------------------------------------------------------------------
-- Public

-- Draws floor `index` of instanceID's map as large as fits into width x height. Returns the size
-- drawn (0, 0 without that floor).
function DungeonMap:Show(instanceID, index, width, height)
    local map = Charted.Map(instanceID)
    local floor = map and map.floors[index]
    if not floor or (width or 0) <= 0 or (height or 0) <= 0 then
        self.frame:Hide()
        return 0, 0
    end
    local naturalW, naturalH = naturalSize(floor)
    local scale = math.min(width / naturalW, height / naturalH)
    self.instanceID, self.index, self.floor = instanceID, index, floor
    self.width, self.height = naturalW * scale, naturalH * scale
    self.frame:SetSize(self.width, self.height)
    local used = floor.art and drawArt(self, floor, scale) or drawMinimap(self, floor, scale)
    for i = used + 1, #self.tiles do self.tiles[i]:Hide() end
    if not self.fadeLeft then self:DrawFog() end -- a fade draws the fog again when it ends
    self.frame:Show()
    return self.width, self.height
end

function DungeonMap:Hide()
    self.frame:Hide()
end
