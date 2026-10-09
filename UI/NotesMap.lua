local _, ns = ...
local L, Compat, Geometry, Notes = ns.L, ns.Compat, ns.Geometry, ns.Notes

-- Notes with a place, as markers on the world map (docs/ARCHITECTURE.md §7.9). A MapCanvas data
-- provider of its own, next to Footsteps':
--   * every note placed on the shown map's continent gets its icon there, at Blizzard's own
--     map pin level, sized for the screen at every zoom; mouseover shows its title, the start
--     of its text, when and where; a click opens it in the journal;
--   * Alt+click on the map starts a note at that spot: a popup asks for its title (the zone's
--     name to begin with), the rest is written in the journal;
--   * the journal's Show on the map opens the map at a note's place and shows that marker even
--     while the others are hidden.
local NotesMap = {}
ns.NotesMap = NotesMap

local MARKER_SIZE = 18     -- pixels on screen
local FOCUS_SCALE = 1.5    -- the marker the journal opened the map for
local CLICK_PRIORITY = 100 -- asked before the default map's own click handlers (its pin: 90)
local PREVIEW_BYTES = 300  -- of a note's text in the tooltip
local NEW_POPUP = "WAYSCRIBE_NEW_NOTE"

-- frames: pooled markers, used of them shown; focus: a note shown until the map closes.
local view = { frames = {}, used = 0 }
NotesMap.view = view

function NotesMap:IsShownOnMap()
    return ns.Options:Get("notesOnMap") == true
end

-- SETTINGS_CHANGED redraws.
function NotesMap:SetShownOnMap(shown)
    ns.Options:Set("notesOnMap", shown == true)
end

------------------------------------------------------------------------------------------------
-- Markers

local function clear()
    for i = 1, view.used do
        view.frames[i]:Hide()
    end
    view.used = 0
end

function NotesMap:Clear()
    clear()
end

-- At the default map's pin level for its own waypoint: above the trails and the map's labels.
local function ensureFrame(map)
    if view.frame then return end
    local canvas = map:GetCanvas()
    local frame = CreateFrame("Frame", nil, canvas)
    frame:SetAllPoints(canvas)
    local levels = map.GetPinFrameLevelsManager and Compat.Call(map.GetPinFrameLevelsManager, map)
    local level = type(levels) == "table"
        and Compat.Call(levels.GetValidFrameLevel, levels, "PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
    frame:SetFrameLevel(type(level) == "number" and level or canvas:GetFrameLevel() + 2)
    view.frame = frame
end

local function hideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function showTooltip(marker)
    local note = Notes:Get(marker.noteId)
    if not (note and GameTooltip) then return end
    GameTooltip:SetOwner(marker, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.NotesView.Title(note))
    local text = note.text or ""
    if text ~= "" then
        local preview = Notes.Cut(text, PREVIEW_BYTES)
        GameTooltip:AddLine(preview ~= text and preview .. "..." or text, 1, 1, 1, true)
    end
    GameTooltip:AddLine(ns.NotesView.Subtitle(note), 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine(L.NOTES_MARKER_HINT, 0.25, 1, 0.25, true)
    GameTooltip:Show()
end

local function onMarkerClick(marker)
    hideTooltip()
    ns.Journal:OpenNotes(marker.noteId)
end

local function markerSize(marker)
    local size = MARKER_SIZE / (view.scale or 1)
    return marker.noteId == view.focus and size * FOCUS_SCALE or size
end

local function placeMarker(note)
    local u, v = Geometry.ToMap(view.transform, note.x, note.y)
    if u < 0 or u > 1 or v < 0 or v > 1 then return end
    view.used = view.used + 1
    local marker = view.frames[view.used]
    if not marker then
        marker = CreateFrame("Button", nil, view.frame)
        marker.icon = marker:CreateTexture(nil, "OVERLAY")
        marker.icon:SetAllPoints()
        marker:RegisterForClicks("LeftButtonUp")
        marker:SetScript("OnEnter", showTooltip)
        marker:SetScript("OnLeave", hideTooltip)
        marker:SetScript("OnClick", onMarkerClick)
        view.frames[view.used] = marker
    end
    marker.noteId = note.id
    marker.icon:SetTexture(Notes.IconTexture(note.icon))
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", view.frame, "TOPLEFT", u * view.width, -v * view.height)
    local size = markerSize(marker)
    marker:SetSize(size, size)
    marker:Show()
end

function NotesMap:Redraw()
    clear()
    view.transform = nil
    local map = self.map
    if not (map and map:IsShown()) then return end
    local transform = ns.FootstepsMap.TransformFor(map:GetMapID())
    local canvas = map:GetCanvas()
    if not transform or canvas:GetWidth() <= 0 then return end
    ensureFrame(map)
    view.transform = transform
    view.width, view.height = canvas:GetWidth(), canvas:GetHeight()
    view.scale = Compat.Call(map.GetCanvasScale, map) or 1
    local all = self:IsShownOnMap()
    for _, note in ipairs(Notes:GetPlaced(transform.continent)) do
        if all or note.id == view.focus then placeMarker(note) end
    end
end

function NotesMap:RedrawIfShown()
    if self.map and self.map:IsShown() then self:Redraw() end
end

-- Markers keep their size on screen at every zoom.
function NotesMap:UpdateSize()
    if not self.map then return end
    view.scale = Compat.Call(self.map.GetCanvasScale, self.map) or 1
    for i = 1, view.used do
        local marker = view.frames[i]
        local size = markerSize(marker)
        marker:SetSize(size, size)
    end
end

------------------------------------------------------------------------------------------------
-- Alt+click: a new note at that spot

local function editBoxOf(dialog)
    if type(dialog.GetEditBox) == "function" then return dialog:GetEditBox() end
    return dialog.editBox or dialog.EditBox
end

-- Adds the note the popup named. Returns it.
function NotesMap:AddAt(place, title)
    title = type(title) == "string" and title:match("^%s*(.-)%s*$") or ""
    return Notes:Add({ title = title, c = place.c, x = place.x, y = place.y, map = place.map })
end

-- "A new note at Mulgore": the title, to begin with the zone's name. Without the default popups
-- the note is added with that name.
function NotesMap:AskTitle(place)
    local zone = place.map and Compat.GetMapName(place.map)
    if type(StaticPopup_Show) ~= "function" then
        self:AddAt(place, zone)
        return
    end
    StaticPopupDialogs[NEW_POPUP] = StaticPopupDialogs[NEW_POPUP] or {
        text = L.NOTES_NEW_AT,
        button1 = L.NOTES_SAVE,
        button2 = L.CANCEL,
        hasEditBox = true,
        maxLetters = Notes.TITLE_LETTERS,
        OnShow = function(dialog, data)
            local box = editBoxOf(dialog)
            if not box then return end
            box:SetText(data and data.title or "")
            box:HighlightText()
            box:SetFocus()
        end,
        OnAccept = function(dialog, data)
            local box = editBoxOf(dialog)
            NotesMap:AddAt(data, box and box:GetText())
        end,
        EditBoxOnEnterPressed = function(box, data)
            NotesMap:AddAt(data, box:GetText())
            box:GetParent():Hide()
        end,
        EditBoxOnEscapePressed = function(box)
            box:GetParent():Hide()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    place.title = zone or ""
    StaticPopup_Show(NEW_POPUP, zone or L.NOTES_THIS_PLACE, nil, place)
end

local function keyDown(fn)
    return Compat.Call(fn) == true
end

-- The map's click handlers: true stops the click there (no zooming into the zone).
function NotesMap:OnCanvasClick(button, u, v)
    if button ~= "LeftButton" or not keyDown(IsAltKeyDown) or keyDown(IsControlKeyDown) or keyDown(IsShiftKeyDown) then
        return false
    end
    local mapID = self.map and self.map:GetMapID()
    local transform = mapID and ns.FootstepsMap.TransformFor(mapID)
    local continent, x, y
    if transform and type(u) == "number" and type(v) == "number" then
        continent, x, y = Compat.GetWorldPosFromMapPos(mapID, u, v)
    end
    if not continent then
        ns.Print(L.NOTES_NO_PLACE)
    elseif not Notes:IsWritable() then
        ns.Print(L.NOTES_READ_ONLY)
    else
        self:AskTitle(Notes.PlaceAt(continent, x, y))
    end
    return true
end

------------------------------------------------------------------------------------------------
-- From the journal

function NotesMap:CanShow()
    return self.provider ~= nil
end

-- The note's own map when it still holds the place, else the most detailed one there.
local function mapFor(note)
    local transform = type(note.map) == "number" and ns.FootstepsMap.TransformFor(note.map)
    if transform and transform.continent == note.c then
        local u, v = Geometry.ToMap(transform, note.x, note.y)
        if u >= 0 and u <= 1 and v >= 0 and v <= 1 then return note.map end
    end
    return Compat.GetMapAtWorldPos(note.c, note.x, note.y)
end

-- Opens the world map at a note's place. Returns whether it did.
function NotesMap:ShowNote(id)
    local note = id and Notes:Get(id)
    if not (note and Notes.HasPlace(note)) then return false end
    if not self.provider then
        ns.Print(L.FOOTSTEPS_NO_MAP)
        return false
    end
    if Compat.Call(InCombatLockdown) == true then
        ns.Print(L.FOOTSTEPS_IN_COMBAT)
        return false
    end
    view.focus = note.id
    ns.FootstepsMap.OpenMap(mapFor(note))
    self:Redraw()
    return true
end

------------------------------------------------------------------------------------------------
-- Setup

local function createProvider()
    local provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:OnAdded(map)
        MapCanvasDataProviderMixin.OnAdded(self, map)
        NotesMap.map = map
        if type(map.AddCanvasClickHandler) == "function" then
            map:AddCanvasClickHandler(function(_, button, u, v)
                local ok, handled = ns.SafeCall("notes:click", NotesMap.OnCanvasClick, NotesMap, button, u, v)
                return ok and handled == true
            end, CLICK_PRIORITY)
            NotesMap.clicks = true
        end
    end
    function provider:RemoveAllData()
        NotesMap:Clear()
    end
    function provider:RefreshAllData()
        NotesMap:Redraw()
    end
    function provider:OnCanvasScaleChanged()
        NotesMap:UpdateSize()
    end
    -- The note the journal opened the map for is shown until the map closes.
    function provider:OnHide()
        view.focus = nil
        NotesMap:Clear()
    end
    return provider
end

-- Blizzard_WorldMap may load after this addon.
function NotesMap:WaitForMap()
    if self.waiting or WorldMapFrame ~= nil then return end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(_, _, name)
        if name == "Blizzard_WorldMap" then
            frame:UnregisterAllEvents()
            ns.SafeCall("notes:map", self.Register, self)
        end
    end)
    self.waiting = frame
end

function NotesMap:Register()
    if self.provider then return end
    if not Compat.HasWorldMapCanvas() then
        self:WaitForMap()
        return
    end
    self.provider = createProvider()
    WorldMapFrame:AddDataProvider(self.provider)
end

function NotesMap:OnSettingsChanged(key)
    if key == "notesOnMap" then self:RedrawIfShown() end
end

ns.Bus:On("READY", NotesMap, NotesMap.Register)
ns.Bus:On("NOTES_CHANGED", NotesMap, NotesMap.RedrawIfShown)
ns.Bus:On("SETTINGS_CHANGED", NotesMap, NotesMap.OnSettingsChanged)
