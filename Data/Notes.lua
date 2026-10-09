local _, ns = ...
local Time, Compat = ns.Time, ns.Compat

-- The player's own notes (docs/ARCHITECTURE.md §4.9), the single write path for them. They live
-- in the character's journal file next to the records, so a backup carries them:
--   WayscribeCharDB.notes = { seq = last id issued, list = { note, ... } }   -- oldest first
--   note = { id, created, edited, title, text, icon? }   -- icon: its markers' raid target icon
-- Notes are the player's words, not facts the addon derives, so they can be edited and deleted
-- (records can't).
--
-- A note's places are the /way lines of its text, in the notation websites share waypoints in
-- (TomTom's): "/way [zone | #uiMapID] x y [label]", one per line, x and y in percent of the
-- zone's map. Each is a marker on the world map. A line without a zone is in the zone of the /way
-- line above it that names one, else where the player is; when the player leaves the note, that
-- zone is written into the line (FillZones), so it stays right after the player moves on.
--
-- Bus message: NOTES_CHANGED(id).
-- The editors count letters; what is stored is capped in bytes (a letter takes up to 4).
local Notes = { TITLE_LETTERS = 60, TEXT_LETTERS = 8000, ICON_COUNT = 8 }
Notes.MAX_TITLE, Notes.MAX_TEXT = 4 * Notes.TITLE_LETTERS, 4 * Notes.TEXT_LETTERS
ns.Notes = Notes

local EMPTY = {}
local ICON_PATH = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local MAX_PARENTS = 5

-- The notes of a journal; nothing is written until the first note.
function Notes:Attach(db)
    self.db = db
end

function Notes:IsWritable()
    return self.db ~= nil and ns.Store:IsWritable()
end

local function book(db)
    local notes = db and db.notes
    return type(notes) == "table" and notes or EMPTY
end

local function isNote(note)
    return type(note) == "table" and type(note.id) == "number"
end

local function list(db)
    local notes = book(db).list
    return type(notes) == "table" and notes or EMPTY
end

local function validIcon(icon)
    return type(icon) == "number" and icon >= 1 and icon <= Notes.ICON_COUNT and icon % 1 == 0
end

-- The raid target icons (star, circle, diamond, triangle, moon, square, cross, skull): in every
-- client, and made to mark things.
function Notes.IconTexture(icon)
    return ICON_PATH .. (validIcon(icon) and icon or 1)
end

------------------------------------------------------------------------------------------------
-- /way lines

-- The lines of a text; joined with "\n" they are the text again.
local function splitLines(text)
    local lines, pos = {}, 1
    while true do
        local stop = text:find("\n", pos, true)
        if not stop then
            lines[#lines + 1] = text:sub(pos)
            return lines
        end
        lines[#lines + 1] = text:sub(pos, stop - 1)
        pos = stop + 1
    end
end

-- Where "/way " starts in a line (at its start or after a space or a sign: "1. /way ...",
-- "Elwynn: /way ..."), or nil.
local function wayAt(line)
    local from = 1
    while true do
        local at = line:find("/[Ww][Aa][Yy]%s", from)
        if not at then return nil end
        if at == 1 or not line:sub(at - 1, at - 1):find("[%w/]") then return at end
        from = at + 1
    end
end

-- "49.0", "49,0" or "49" as a percent.
local function percent(text)
    local value = tonumber((text:gsub(",", ".")))
    return value and value >= 0 and value <= 100 and value or nil
end

-- A /way line: { map = uiMapID?, zone = name or "", x, y (percent), label }, or nil.
function Notes.ParseWay(line)
    local at = type(line) == "string" and wayAt(line)
    if not at then return nil end
    local rest = line:sub(at + 4):match("^%s*(.-)%s*$")
    local map
    local id, after = rest:match("^#(%d+)%s*(.*)$")
    if id then map, rest = tonumber(id), after end
    local first, last, xs, ys = rest:find("(%d+[%.,]?%d*)[%s,]+(%d+[%.,]?%d*)")
    if not first then return nil end
    local x, y = percent(xs), percent(ys)
    if not (x and y) then return nil end
    return {
        map = map,
        zone = rest:sub(1, first - 1):match("^%s*(.-)[%s,:]*$"),
        x = x, y = y,
        label = rest:sub(last + 1):match("^[%s,:%.%-]*(.-)%s*$"),
    }
end

local clientNames, englishNames

-- A map by its name, in the client's language or in English (StaticData/Zones.lua), any case.
function Notes.FindMap(name)
    if type(name) ~= "string" or name == "" then return nil end
    if not clientNames then
        local names = Compat.GetMapNames()
        clientNames = names and next(names) and names or nil -- asked again until the client knows
    end
    if not englishNames then
        englishNames = {}
        for english, mapID in pairs(ns.StaticData.MapNames or EMPTY) do englishNames[english:lower()] = mapID end
    end
    local key = name:lower()
    return clientNames and clientNames[key] or englishNames[key]
end

-- How a /way line names a map: its name in the client's language, or #uiMapID when the name
-- doesn't lead back to it.
function Notes.ZoneLabel(mapID)
    local name = Compat.GetMapName(mapID)
    if name and not name:find("%d") and Notes.FindMap(name) == mapID then return name end
    return "#" .. mapID
end

-- "/way Mulgore 49.0 86.4" for a point (u, v from 0 to 1) of a map.
function Notes.WayLine(mapID, u, v, label)
    local line = ("/way %s %.1f %.1f"):format(Notes.ZoneLabel(mapID), u * 100, v * 100)
    if label and label ~= "" then line = line .. " " .. label end
    return line
end

-- The /way line of a place of the world, on the most detailed map there; nil without one.
function Notes.LineAt(continent, x, y, label)
    local mapID = Compat.GetMapAtWorldPos(continent, x, y)
    for _ = 1, MAX_PARENTS do
        if not mapID then return nil end
        local u, v = Compat.GetMapPosFromWorldPos(mapID, continent, x, y)
        if u and u >= 0 and u <= 1 and v >= 0 and v <= 1 then return Notes.WayLine(mapID, u, v, label) end
        mapID = Compat.GetParentMap(mapID)
    end
    return nil
end

-- Parsed once per text (and per zone the player is in, for lines that depend on it).
local parsed = setmetatable({}, { __mode = "k" })

-- A note's places, in text order, and how many /way lines found no place (an unknown zone, or
-- none to assume inside an instance). place = { c, x, y (world yards), map, u, v (percent),
-- label, line (its number in the text), assumed (the zone is where the player is) }.
function Notes.PlacesOf(note)
    local text = type(note.text) == "string" and note.text or ""
    local here = Compat.GetPlayerMapID()
    local cached = parsed[note]
    if cached and cached.text == text and cached.here == here then return cached.places, cached.unplaced end
    local places, unplaced, above = {}, 0, nil
    if text:find("/[Ww][Aa][Yy]%s") then
        for i, line in ipairs(splitLines(text)) do
            local way = Notes.ParseWay(line)
            if way then
                local mapID, assumed
                if way.map or way.zone ~= "" then
                    mapID = way.map or Notes.FindMap(way.zone)
                    above = mapID or false -- lines below an unknown zone are in it too
                elseif above ~= nil then
                    mapID = above or nil
                else
                    mapID, assumed = here, true
                end
                local c, x, y
                if mapID then c, x, y = Compat.GetWorldPosFromMapPos(mapID, way.x / 100, way.y / 100) end
                if c then
                    places[#places + 1] = {
                        c = c, x = x, y = y, map = mapID, u = way.x, v = way.y, label = way.label, line = i,
                        assumed = assumed,
                    }
                else
                    unplaced = unplaced + 1
                end
            end
        end
    end
    parsed[note] = { text = text, here = here, places = places, unplaced = unplaced }
    return places, unplaced
end

-- A note's text without its /way lines (for a preview).
function Notes.TextWithoutWays(text)
    local kept = {}
    for _, line in ipairs(splitLines(text or "")) do
        if not Notes.ParseWay(line) then kept[#kept + 1] = line end
    end
    return (table.concat(kept, "\n"):match("^%s*(.-)%s*$"))
end

------------------------------------------------------------------------------------------------
-- Reading

function Notes:Get(id)
    for _, note in ipairs(list(self.db)) do
        if isNote(note) and note.id == id then return note end
    end
    return nil
end

-- Every note, newest first: the order they were written in, so the list doesn't move while one
-- is being edited.
function Notes:GetAll()
    local all = {}
    for _, note in ipairs(list(self.db)) do
        if isNote(note) then all[#all + 1] = note end
    end
    table.sort(all, function(a, b)
        local createdA, createdB = tonumber(a.created) or 0, tonumber(b.created) or 0
        if createdA ~= createdB then return createdA > createdB end
        return a.id > b.id
    end)
    return all
end

-- Every place on a continent: { { note, place }, ... }.
function Notes:GetPlaced(continent)
    local placed = {}
    for _, note in ipairs(list(self.db)) do
        if isNote(note) then
            for _, place in ipairs((Notes.PlacesOf(note))) do
                if place.c == continent then placed[#placed + 1] = { note = note, place = place } end
            end
        end
    end
    return placed
end

-- How many notes there are, and how many have places on the map.
function Notes:Count()
    local count, placed = 0, 0
    for _, note in ipairs(list(self.db)) do
        if isNote(note) then
            count = count + 1
            if #Notes.PlacesOf(note) > 0 then placed = placed + 1 end
        end
    end
    return count, placed
end

-- Ids ever issued: the canary's count (§4.6), like the journal's seq.
function Notes:GetSeq()
    return tonumber(book(self.db).seq) or 0
end

-- Nothing written: a note left like this is dropped.
function Notes.IsBlank(note)
    return (note.title or "") == "" and (note.text or "") == ""
end

------------------------------------------------------------------------------------------------
-- Writing

-- Text the client can save, cut to `max` bytes without splitting a UTF-8 character.
local function cut(value, max)
    if value == nil then return "" end
    if Compat.Safe(value, "string") == nil then return nil end
    if #value <= max then return value end
    local stop = max
    while stop > 0 and value:byte(stop + 1) and value:byte(stop + 1) >= 0x80 and value:byte(stop + 1) < 0xC0 do
        stop = stop - 1
    end
    return value:sub(1, stop)
end

Notes.Cut = cut

local function ensureBook(db)
    if type(db.notes) ~= "table" then db.notes = {} end
    local notes = db.notes
    if type(notes.list) ~= "table" then notes.list = {} end
    if type(notes.seq) ~= "number" then
        local seq = 0
        for _, note in ipairs(notes.list) do
            if isNote(note) then seq = math.max(seq, note.id) end
        end
        notes.seq = seq
    end
    return notes
end

-- Adds a note: fields = { title?, text?, icon? }. Returns the note, or nil plus a reason.
function Notes:Add(fields)
    if not self:IsWritable() then return nil, "read-only" end
    fields = fields or EMPTY
    local title, text = cut(fields.title, Notes.MAX_TITLE), cut(fields.text, Notes.MAX_TEXT)
    if not (title and text) then
        ns.Log:Error("notes", "invalid note")
        return nil, "invalid note"
    end
    local notes = ensureBook(self.db)
    notes.seq = notes.seq + 1
    local now = Time.Now()
    local note = { id = notes.seq, created = now, edited = now, title = title, text = text }
    if validIcon(fields.icon) then note.icon = fields.icon end
    notes.list[#notes.list + 1] = note
    ns.Bus:Fire("NOTES_CHANGED", note.id)
    return note
end

-- Changes a note's title, text or marker icon. Returns the note, or nil plus a reason.
function Notes:Update(id, fields)
    if not self:IsWritable() then return nil, "read-only" end
    local note = self:Get(id)
    if not note then return nil, "no such note" end
    local changed = false
    for _, field in ipairs({ "title", "text" }) do
        if fields[field] ~= nil then
            local value = cut(fields[field], field == "title" and Notes.MAX_TITLE or Notes.MAX_TEXT)
            if not value then return nil, "invalid note" end
            changed = changed or value ~= note[field]
            note[field] = value
        end
    end
    if validIcon(fields.icon) and fields.icon ~= (note.icon or 1) then
        note.icon = fields.icon
        changed = true
    end
    if changed then
        note.edited = Time.Now()
        ns.Bus:Fire("NOTES_CHANGED", id)
    end
    return note
end

function Notes:Delete(id)
    if not self:IsWritable() then return false end
    local notes = list(self.db)
    for i, note in ipairs(notes) do
        if isNote(note) and note.id == id then
            table.remove(notes, i)
            ns.Bus:Fire("NOTES_CHANGED", id)
            return true
        end
    end
    return false
end

-- Writes the zone the player is in into the /way lines that took it (no zone, none above), so
-- the note says where they are. Called when the player leaves the note. Returns whether it did.
function Notes:FillZones(id)
    local note = self:IsWritable() and self:Get(id)
    if not note then return false end
    local zones = {}
    for _, place in ipairs((Notes.PlacesOf(note))) do
        if place.assumed then zones[place.line] = Notes.ZoneLabel(place.map) end
    end
    if not next(zones) then return false end
    local lines = splitLines(note.text)
    for i, zone in pairs(zones) do
        local at = wayAt(lines[i])
        lines[i] = lines[i]:sub(1, at + 3) .. " " .. zone .. lines[i]:sub(at + 4)
    end
    local text = table.concat(lines, "\n")
    if #text > Notes.MAX_TEXT then return false end -- never cut the note's end for it
    return self:Update(id, { text = text }) ~= nil
end

-- The first 0.7 test builds kept one place per note in c, x, y and map: it becomes a /way line
-- at the end of the text.
function Notes:Upgrade()
    if not self:IsWritable() then return end
    for _, note in ipairs(list(self.db)) do
        if isNote(note) and type(note.c) == "number" and type(note.x) == "number" and type(note.y) == "number" then
            local line = Notes.LineAt(note.c, note.x, note.y)
            if line then
                local text = type(note.text) == "string" and note.text or ""
                note.text = text == "" and line or (text .. "\n" .. line)
                note.c, note.x, note.y, note.map = nil, nil, nil, nil
            end
        end
    end
end

------------------------------------------------------------------------------------------------
-- Places

-- Where the player stands, with the subzone's name: { c, x, y, sub }; nil inside instances.
function Notes.PlayerPlace()
    local continent, x, y = Compat.GetPlayerWorldPosition()
    if not continent then return nil end
    return { c = continent, x = x, y = y, sub = Compat.GetSubZoneName() }
end

-- The day a note was written.
function Notes.DayOf(note)
    return Time.DayKey(tonumber(note.created) or 0)
end

ns.Bus:On("READY", Notes, Notes.Upgrade)
