local _, ns = ...
local Time, Compat = ns.Time, ns.Compat

-- The player's own notes (docs/ARCHITECTURE.md §4.9), the single write path for them. They live
-- in the character's journal file next to the records, so a backup carries them:
--   WayscribeCharDB.notes = { seq = last id issued, list = { note, ... } }   -- oldest first
--   note = { id, created, edited, title, text,
--            c, x, y, map, icon }   -- a place: continent, world yards, the map placed on, marker icon
-- A marker on the world map is a note with a place. Notes are the player's words, not facts the
-- addon derives, so they can be edited and deleted (records can't).
--
-- Bus message: NOTES_CHANGED(id).
-- The editors count letters; what is stored is capped in bytes (a letter takes up to 4).
local Notes = { TITLE_LETTERS = 60, TEXT_LETTERS = 8000, ICON_COUNT = 8 }
Notes.MAX_TITLE, Notes.MAX_TEXT = 4 * Notes.TITLE_LETTERS, 4 * Notes.TEXT_LETTERS
ns.Notes = Notes

local EMPTY = {}
local ICON_PATH = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

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

function Notes.HasPlace(note)
    return type(note.c) == "number" and type(note.x) == "number" and type(note.y) == "number"
end

-- The raid target icons (star, circle, diamond, triangle, moon, square, cross, skull): in every
-- client, and made to mark things.
function Notes.IconTexture(icon)
    if type(icon) ~= "number" or icon < 1 or icon > Notes.ICON_COUNT or icon % 1 ~= 0 then icon = 1 end
    return ICON_PATH .. icon
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

-- The notes with a place on a continent.
function Notes:GetPlaced(continent)
    local placed = {}
    for _, note in ipairs(list(self.db)) do
        if isNote(note) and Notes.HasPlace(note) and note.c == continent then placed[#placed + 1] = note end
    end
    return placed
end

-- How many notes there are, and how many have a place.
function Notes:Count()
    local count, placed = 0, 0
    for _, note in ipairs(list(self.db)) do
        if isNote(note) then
            count = count + 1
            if Notes.HasPlace(note) then placed = placed + 1 end
        end
    end
    return count, placed
end

-- Ids ever issued: the canary's count (§4.6), like the journal's seq.
function Notes:GetSeq()
    return tonumber(book(self.db).seq) or 0
end

-- Nothing written and nowhere placed: a note left like this is dropped.
function Notes.IsBlank(note)
    return (note.title or "") == "" and (note.text or "") == "" and not Notes.HasPlace(note)
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

local function wholeYards(value)
    value = Compat.Safe(value, "number")
    return value and math.floor(value + 0.5)
end

-- { c, x, y, map?, icon? } as stored, or nil when it isn't a place.
local function placeOf(fields)
    local c, x, y = Compat.Safe(fields.c, "number"), wholeYards(fields.x), wholeYards(fields.y)
    if not (c and x and y) then return nil end
    local map = Compat.Safe(fields.map, "number")
    local icon = Compat.Safe(fields.icon, "number")
    if not icon or icon < 1 or icon > Notes.ICON_COUNT or icon % 1 ~= 0 then icon = 1 end
    return { c = c, x = x, y = y, map = map, icon = icon }
end

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

-- Adds a note: fields = { title?, text?, c?, x?, y?, map?, icon? }. Returns the note, or nil plus
-- a reason.
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
    local place = placeOf(fields)
    if place then
        note.c, note.x, note.y, note.map, note.icon = place.c, place.x, place.y, place.map, place.icon
    end
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
    if fields.title ~= nil then
        local title = cut(fields.title, Notes.MAX_TITLE)
        if not title then return nil, "invalid note" end
        changed = changed or title ~= note.title
        note.title = title
    end
    if fields.text ~= nil then
        local text = cut(fields.text, Notes.MAX_TEXT)
        if not text then return nil, "invalid note" end
        changed = changed or text ~= note.text
        note.text = text
    end
    if fields.icon ~= nil and Notes.HasPlace(note) then
        local place = placeOf({ c = note.c, x = note.x, y = note.y, icon = fields.icon })
        changed = changed or place.icon ~= note.icon
        note.icon = place.icon
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

------------------------------------------------------------------------------------------------
-- Places

-- A place of the world: the most detailed map there is looked up for its name.
function Notes.PlaceAt(continent, x, y)
    return { c = continent, x = x, y = y, map = Compat.GetMapAtWorldPos(continent, x, y) }
end

-- Where the player stands, with the subzone's name; nil inside instances.
function Notes.PlayerPlace()
    local continent, x, y = Compat.GetPlayerWorldPosition()
    if not continent then return nil end
    local place = Notes.PlaceAt(continent, x, y)
    place.map = Compat.GetPlayerMapID() or place.map
    place.sub = Compat.GetSubZoneName()
    return place
end

-- The zone a note was placed in, or nil.
function Notes.ZoneName(note)
    return type(note.map) == "number" and Compat.GetMapName(note.map) or nil
end

-- The day a note was written.
function Notes.DayOf(note)
    return Time.DayKey(tonumber(note.created) or 0)
end
