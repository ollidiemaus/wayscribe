local _, ns = ...
local L, Compat, Notes, Waypoints, MapPlacement = ns.L, ns.Compat, ns.Notes, ns.Waypoints, ns.MapPlacement

-- The notes' places as markers on the world map (docs/ARCHITECTURE.md §7.9). A MapCanvas data
-- provider of its own, next to Footsteps':
--   * every /way line of a note that can be placed on the shown map (UI/MapPlacement.lua: its
--     continent on the default map, every continent on OpenMap's stitched map) is a marker with
--     the note's icon, at Blizzard's own map pin level (above OpenMap's art on its stitched map),
--     sized for the screen at every zoom; mouseover shows the
--     line's label and the note; a click opens the note in the journal, Ctrl+click sends its place
--     to TomTom or the game's map pin (UI/Waypoints.lua);
--   * Alt+click on the map starts a note at that spot: a popup asks for its title (the zone's
--     name to begin with), and the note's text starts with the spot's /way line;
--   * the journal's Show on the map opens the map at a note's first place and shows the note's
--     markers even while the others are hidden.
local NotesMap = {}
ns.NotesMap = NotesMap

local MARKER_SIZE = 18     -- pixels on screen
local FOCUS_SCALE = 1.5    -- the marker the journal opened the map for
local CLICK_PRIORITY = 100 -- asked before the default map's own click handlers (its pin: 90)
local PREVIEW_BYTES = 300  -- of a note's text in the tooltip
local NEW_POPUP = "WAYSCRIBE_NEW_NOTE"
local AROUND = 0.1         -- of the zone shown around a note's place on OpenMap's stitched map

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
    view.placement = nil
end

-- At the default map's pin level for its own waypoint: above the trails and the map's labels.
-- On OpenMap's stitched map: above its art and the trails.
-- On the stitched map the frame spans the stitched world (UI/MapPlacement.lua's Attach).
local function ensureFrame(map, placement)
    local canvas = map:GetCanvas()
    view.frame = view.frame or CreateFrame("Frame", nil, canvas)
    placement:Attach(view.frame, canvas)
    view.frame:SetFrameLevel(placement:FrameLevel(map, "PIN_FRAME_LEVEL_WAYPOINT_LOCATION", 0, 2))
end

local function hideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function keyDown(fn)
    return Compat.Call(fn) == true
end

-- The line's label (else the note's title), the note, the start of its text without the /way
-- lines, where: "Mulgore 49.0, 86.4", and what a click and a Ctrl+click do.
local function showTooltip(marker)
    local note, place = Notes:Get(marker.noteId), marker.place
    if not (note and place and GameTooltip) then return end
    GameTooltip:SetOwner(marker, "ANCHOR_RIGHT")
    local title = Notes.Title(note)
    if place.label ~= "" then
        GameTooltip:SetText(place.label)
        GameTooltip:AddLine(title, 1, 0.82, 0, true)
    else
        GameTooltip:SetText(title)
    end
    local text = Notes.TextWithoutWays(note.text)
    if text ~= "" then
        local preview = Notes.Cut(text, PREVIEW_BYTES)
        GameTooltip:AddLine(preview ~= text and preview .. "..." or text, 1, 1, 1, true)
    end
    GameTooltip:AddLine(L.NOTES_PLACE:format(Compat.GetMapName(place.map) or "?", place.u, place.v), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L.NOTES_MARKER_HINT, 0.25, 1, 0.25, true)
    local target = Waypoints.Target()
    if Waypoints.CanSend(place, target) then
        GameTooltip:AddLine(target == "tomtom" and L.NOTES_MARKER_SEND_TOMTOM or L.NOTES_MARKER_SEND_PIN, 0.25, 1, 0.25, true)
    end
    GameTooltip:Show()
end

-- Ctrl+click sends the place where it can be sent; otherwise a click opens the note. The marker
-- takes the click, so the game's own Ctrl+click doesn't also pin the spot under the cursor.
local function onMarkerClick(marker)
    hideTooltip()
    local note = Notes:Get(marker.noteId)
    if note and keyDown(IsControlKeyDown) and Waypoints.CanSend(marker.place) then
        Waypoints.Send(note, marker.place)
        return
    end
    ns.Journal:OpenNotes(marker.noteId)
end

local function markerSize(marker)
    local size = MARKER_SIZE / (view.scale or 1)
    return marker.noteId == view.focus and size * FOCUS_SCALE or size
end

local function placeMarker(note, place)
    local u, v = view.placement:At(place.c, place.x, place.y)
    if not (u and view.placement:Shows(u, v)) then return end
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
    marker.noteId, marker.place = note.id, place
    marker.icon:SetTexture(Notes.IconTexture(note.icon))
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", view.frame, "TOPLEFT", u * view.width, -v * view.height)
    local size = markerSize(marker)
    marker:SetSize(size, size)
    marker:Show()
end

function NotesMap:Redraw()
    clear()
    view.placement = nil
    local map = self.map
    if not (map and map:IsShown()) then return end
    local placement = MapPlacement.For(map)
    if not placement then return end
    ensureFrame(map, placement)
    view.placement = placement
    view.width, view.height = placement.width, placement.height
    view.scale = (Compat.Call(map.GetCanvasScale, map) or 1) * placement.frameScale
    local all = self:IsShownOnMap()
    -- The shown map's continent; on the stitched map (continent nil) every continent.
    for _, placed in ipairs(Notes:GetPlaced(placement.continent)) do
        if all or placed.note.id == view.focus then placeMarker(placed.note, placed.place) end
    end
end

function NotesMap:RedrawIfShown()
    if self.map and self.map:IsShown() then self:Redraw() end
end

-- The map underneath changed: on the stitched map the markers only move with their frame.
function NotesMap:Refresh()
    local map, drawn = self.map, view.placement
    local placement = drawn and map and map:IsShown() and MapPlacement.For(map)
    if not (placement and placement:SameSpace(drawn)) then
        self:Redraw()
        return
    end
    view.placement = placement
    placement:Attach(view.frame, map:GetCanvas())
    self:UpdateSize()
end

-- Markers keep their size on screen at every zoom.
function NotesMap:UpdateSize()
    if not (self.map and view.placement) then return end
    view.scale = (Compat.Call(self.map.GetCanvasScale, self.map) or 1) * view.placement.frameScale
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

-- Adds the note the popup named, its text the spot's /way line. Returns it.
function NotesMap:AddAt(place, title)
    title = type(title) == "string" and title:match("^%s*(.-)%s*$") or ""
    return Notes:Add({ title = title, text = Notes.LineAt(place.c, place.x, place.y) })
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

-- The map's click handlers: true stops the click there (no zooming into the zone).
function NotesMap:OnCanvasClick(button, u, v)
    if button ~= "LeftButton" or not keyDown(IsAltKeyDown) or keyDown(IsControlKeyDown) or keyDown(IsShiftKeyDown) then
        return false
    end
    local mapID = self.map and self.map:GetMapID()
    local transform = mapID and MapPlacement.Transform(mapID)
    local continent, x, y
    if transform and type(u) == "number" and type(v) == "number" then
        continent, x, y = Compat.GetWorldPosFromMapPos(mapID, u, v)
    end
    if not continent then
        ns.Print(L.NOTES_NO_PLACE)
    elseif not Notes:IsWritable() then
        ns.Print(L.NOTES_READ_ONLY)
    else
        self:AskTitle({ c = continent, x = x, y = y, map = Compat.GetMapAtWorldPos(continent, x, y) })
    end
    return true
end

------------------------------------------------------------------------------------------------
-- From the journal

function NotesMap:CanShow()
    return self.provider ~= nil
end

-- Opens the world map at a note's first place, on the map its /way line names. Returns whether
-- it did.
function NotesMap:ShowNote(id)
    local note = id and Notes:Get(id)
    local first = note and Notes.PlacesOf(note)[1]
    if not first then return false end
    if not self.provider then
        ns.Print(L.FOOTSTEPS_NO_MAP)
        return false
    end
    if Compat.Call(InCombatLockdown) == true then
        ns.Print(L.FOOTSTEPS_IN_COMBAT)
        return false
    end
    view.focus = note.id
    local u, v = first.u / 100, first.v / 100
    MapPlacement.Open(first.map, u - AROUND, v - AROUND, u + AROUND, v + AROUND)
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
        NotesMap:Refresh()
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
    MapPlacement.OnStitchedChanged(self, function()
        if not MapPlacement.Matches(view.placement) then self:RedrawIfShown() end
    end)
end

function NotesMap:OnSettingsChanged(key)
    if key == "notesOnMap" then self:RedrawIfShown() end
end

ns.Bus:On("READY", NotesMap, NotesMap.Register)
ns.Bus:On("NOTES_CHANGED", NotesMap, NotesMap.RedrawIfShown)
ns.Bus:On("SETTINGS_CHANGED", NotesMap, NotesMap.OnSettingsChanged)
