local _, ns = ...
local L, Codec, Time, Store, Paths, Index, Schema = ns.L, ns.Codec, ns.Time, ns.Store, ns.Paths, ns.Index, ns.Schema

-- A restorable backup of the character's facts (docs/ARCHITECTURE.md §4.8): one string the player
-- keeps outside the game and pastes back. Addons can't write files, so it goes through the
-- clipboard like the text export.
--
--   WSB1:<header><payload>
--
-- After the magic there are only the codec's 64 characters: nothing an edit box, chat or a text
-- editor treats specially (no "|", quotes or line breaks). The header (addon version, schema
-- versions, character, counts, the payload's length and its Adler-32 checksum) is read first, so a
-- truncated or garbled paste is caught before anything is touched.
--
-- Both parts are values in a small serializer for plain data: one tag character per value, then
--   N  integer, a zigzag varint      D  other number, as the text of %.17g (a string value)
--   T  true    F  false              M  table: array count, values, pair count, key/value pairs
--   S  string, defined here and numbered (1, 2, ...)    R  string, by its number
--   L  long string, not numbered (a trail's packed points are only used once)
-- A string's data is its length * 2 + 1 and its characters when they are all in the alphabet,
-- else its length * 2 and its bytes in base64.
--
-- Only facts go in: rollups, firsts and the day index are caches and are rebuilt on restore.
local Backup = { FORMAT = 1, BUDGET_MS = 10 }
ns.Backup = Backup

local MAGIC = "WSB" .. Backup.FORMAT .. ":"
local LONG = 40         -- longer strings aren't numbered
local CHUNK = 4096      -- checksum bytes between two looks at the clock
local MAX_SAFE = 2 ^ 52 -- like the codec: integers stay exact
local NOT_RAW = "[^A-Za-z0-9_%-]"

local floor = math.floor
local CHAR, VALUE = {}, {}
for i = 1, #Codec.ALPHABET do
    local char = Codec.ALPHABET:sub(i, i)
    CHAR[i - 1] = char
    VALUE[char:byte()] = i - 1
end

local B_TRUE, B_FALSE, B_INT, B_FLOAT = ("T"):byte(), ("F"):byte(), ("N"):byte(), ("D"):byte()
local B_STRING, B_REF, B_LONG, B_TABLE = ("S"):byte(), ("R"):byte(), ("L"):byte(), ("M"):byte()

local function fail(message)
    error(message, 0)
end

-- Inside a job, gives the frame back once the job has used its share of it.
local function pause(job)
    if job and job.deadline and debugprofilestop() > job.deadline then
        coroutine.yield()
    end
end

------------------------------------------------------------------------------------------------
-- Writing

local writeValue

local function encodeBytes(out, s)
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local value = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = CHAR[floor(value / 262144)]
        out[#out + 1] = CHAR[floor(value / 4096) % 64]
        if b then out[#out + 1] = CHAR[floor(value / 64) % 64] end
        if c then out[#out + 1] = CHAR[value % 64] end
    end
end

local function writeStringData(out, s)
    local raw = s:find(NOT_RAW) == nil
    Codec.WriteUint(out, #s * 2 + (raw and 1 or 0))
    if raw then
        out[#out + 1] = s
    else
        encodeBytes(out, s)
    end
end

local function writeString(w, s)
    local out = w.out
    if #s > LONG then
        out[#out + 1] = "L"
        return writeStringData(out, s)
    end
    local number = w.strings[s]
    if number then
        out[#out + 1] = "R"
        return Codec.WriteUint(out, number)
    end
    w.count = w.count + 1
    w.strings[s] = w.count
    out[#out + 1] = "S"
    writeStringData(out, s)
end

local function writeNumber(w, n)
    if n % 1 == 0 and n > -MAX_SAFE and n < MAX_SAFE then
        w.out[#w.out + 1] = "N"
        Codec.WriteInt(w.out, n)
    elseif n == n and n ~= math.huge and n ~= -math.huge then
        w.out[#w.out + 1] = "D"
        writeString(w, string.format("%.17g", n))
    else
        fail("can't back up the number " .. tostring(n))
    end
end

local function isArrayKey(key, count)
    return type(key) == "number" and key >= 1 and key <= count and key % 1 == 0
end

local function writeKey(w, key)
    local kind = type(key)
    if kind ~= "string" and kind ~= "number" then
        fail("can't back up a key of type " .. kind)
    end
    writeValue(w, key)
end

local function writeTable(w, t)
    if w.open[t] then fail("a table holds itself") end
    w.open[t] = true
    local out = w.out
    local count = 0
    while t[count + 1] ~= nil do
        count = count + 1
    end
    local pairsCount = 0
    for key in pairs(t) do
        if not isArrayKey(key, count) then pairsCount = pairsCount + 1 end
    end
    out[#out + 1] = "M"
    Codec.WriteUint(out, count)
    for i = 1, count do
        writeValue(w, t[i])
    end
    Codec.WriteUint(out, pairsCount)
    for key, value in pairs(t) do
        if not isArrayKey(key, count) then
            writeKey(w, key)
            writeValue(w, value)
        end
    end
    w.open[t] = nil
end

writeValue = function(w, value)
    local kind = type(value)
    if kind == "table" then
        writeTable(w, value)
    elseif kind == "string" then
        writeString(w, value)
    elseif kind == "number" then
        writeNumber(w, value)
    elseif kind == "boolean" then
        w.out[#w.out + 1] = value and "T" or "F"
    else
        fail("can't back up a " .. kind)
    end
end

local function newWriter(job)
    return { out = {}, strings = {}, count = 0, open = {}, job = job, entries = 0, days = 0, segments = 0 }
end

-- A table the caller writes pair by pair: no array part, then `count` key/value pairs.
local function beginMap(w, count)
    w.out[#w.out + 1] = "M"
    Codec.WriteUint(w.out, 0)
    Codec.WriteUint(w.out, count)
end

local function keyOrder(a, b)
    local kindA, kindB = type(a), type(b)
    if kindA ~= kindB then return kindA < kindB end
    if kindA == "number" or kindA == "string" then return a < b end
    return tostring(a) < tostring(b)
end

local function sortedKeys(t, skip)
    local keys = {}
    for key in pairs(t) do
        if key ~= skip then keys[#keys + 1] = key end
    end
    table.sort(keys, keyOrder)
    return keys
end

-- A month's days, in order, with a pause between two days. They go into a buffer of their own
-- and are counted as they go, since writeDay(w, dayKey, day) may leave one out.
local function writeDays(w, days, writeDay)
    local outer = w.out
    w.out = {}
    local written = 0
    for _, dayKey in ipairs(sortedKeys(days)) do
        local day = days[dayKey]
        if day ~= nil and writeDay(w, dayKey, day) then
            written = written + 1
        end
        pause(w.job)
    end
    local body = table.concat(w.out)
    w.out = outer
    beginMap(w, written)
    outer[#outer + 1] = body
end

-- months[YYYYMM] = { days = { [YYYYMMDD] = day }, ... }, the journal's and the trails' partitions.
-- A month's rollup is a cache and stays out; field(monthKey, name, value) may stand in for a value.
local function writeMonths(w, months, writeDay, field)
    local monthKeys = sortedKeys(months)
    beginMap(w, #monthKeys)
    for _, monthKey in ipairs(monthKeys) do
        writeKey(w, monthKey)
        local month = months[monthKey]
        if type(month) == "table" and type(month.days) == "table" then
            local names = sortedKeys(month, "rollup")
            beginMap(w, #names)
            for _, name in ipairs(names) do
                writeKey(w, name)
                if name == "days" then
                    writeDays(w, month.days, writeDay)
                else
                    writeValue(w, field and field(monthKey, name, month[name]) or month[name])
                end
            end
        else
            writeValue(w, month)
        end
    end
end

local function copy(t, without)
    local result = {}
    for key, value in pairs(t) do
        if key ~= without then result[key] = value end
    end
    return result
end

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do
        result[key] = deepCopy(item)
    end
    return result
end

local function isNewer(record, seq)
    return type(record) == "table" and type(record.id) == "number" and record.id > seq
end

-- The journal as it was when the backup started, however many frames it takes: records with a
-- higher id than the snapshot's counter (added today since, or back-filled into an older day)
-- are left out, and a day with nothing left is too.
local function journalDays(seq)
    return function(w, dayKey, day)
        if type(day) == "table" and type(day.records) == "table" then
            local newer = 0
            for _, record in ipairs(day.records) do
                if isNewer(record, seq) then newer = newer + 1 end
            end
            if newer > 0 then
                if newer == #day.records and (type(day.counters) ~= "table" or next(day.counters) == nil) then
                    return false
                end
                local kept = {}
                for _, record in ipairs(day.records) do
                    if not isNewer(record, seq) then kept[#kept + 1] = record end
                end
                day = copy(day)
                day.records = kept
            end
            w.entries = w.entries + #day.records
        end
        w.days = w.days + 1
        writeKey(w, dayKey)
        writeValue(w, day)
        return true
    end
end

local function writeTrailsDay(w, dayKey, day)
    if type(day) == "table" then
        w.segments = w.segments + #day
    end
    writeKey(w, dayKey)
    writeValue(w, day)
    return true
end

-- The session being played right now ends with the backup, in the backup: restored elsewhere, it
-- must not run on until the restore.
local function closeLiveSession(db, made)
    local session = Store.db == db and Store:IsWritable() and Store:GetCurrentSession()
    if not (session and session.e == nil) then return nil end
    local ref = db.state.session
    return function(monthKey, name, value)
        if name ~= "sessions" or monthKey ~= ref.m then return nil end
        local sessions = copy(value)
        sessions[ref.i] = copy(session)
        sessions[ref.i].e = made
        return sessions
    end
end

-- What changes during play, read when the backup starts: the record counter, the tracker state,
-- the players and the notes. Past days don't change, and later records are left out (journalDays).
local SNAPSHOT = { meta = true, state = true, players = true, notes = true }

local function snapshot(db)
    local now = { made = Time.Now(), seq = db.meta.seq }
    now.meta = type(db.meta) == "table" and copy(db.meta, "rollup") or db.meta
    now.state = deepCopy(db.state)
    now.players = deepCopy(db.players)
    now.notes = deepCopy(db.notes)
    return now
end

local function writeJournal(w, db, now)
    local names = sortedKeys(db, "firsts")
    beginMap(w, #names)
    for _, name in ipairs(names) do
        writeKey(w, name)
        if name == "months" and type(db.months) == "table" then
            writeMonths(w, db.months, journalDays(now.seq), closeLiveSession(db, now.made))
        elseif now[name] ~= nil and SNAPSHOT[name] then
            writeValue(w, now[name])
        else
            writeValue(w, db[name])
        end
    end
end

local function writeTrails(w, db)
    local names = sortedKeys(db)
    beginMap(w, #names)
    for _, name in ipairs(names) do
        writeKey(w, name)
        if name == "months" and type(db.months) == "table" then
            writeMonths(w, db.months, writeTrailsDay)
        else
            writeValue(w, db[name])
        end
    end
end

-- Adler-32 of text[from..], arithmetic only. The sums are reduced once per chunk: they stay far
-- below 2^53 until then.
local function adler32(text, from, job)
    local a, b = 1, 0
    local length = #text
    local byte = string.byte
    for start = from, length, CHUNK do
        for i = start, math.min(start + CHUNK - 1, length) do
            a = a + byte(text, i)
            b = b + a
        end
        a = a % 65521
        b = b % 65521
        pause(job)
    end
    return b * 65536 + a
end
Backup.Adler32 = function(text) return adler32(text, 1) end

------------------------------------------------------------------------------------------------
-- Reading

local readValue

local REST_CHARS = { [0] = 0, 2, 3 }

local function decodeBytes(text, pos, length)
    local stop = pos + floor(length / 3) * 4 + REST_CHARS[length % 3] - 1
    if stop > #text then fail("truncated text") end
    local parts = {}
    for i = pos, stop, 4 do
        local chars = math.min(4, stop - i + 1)
        local value = 0
        for j = 0, 3 do
            local digit = 0
            if j < chars then
                digit = VALUE[text:byte(i + j)]
                if not digit then fail("invalid character at " .. (i + j)) end
            end
            value = value * 64 + digit
        end
        local a, b, c = floor(value / 65536), floor(value / 256) % 256, value % 256
        if chars == 4 then
            parts[#parts + 1] = string.char(a, b, c)
        elseif chars == 3 then
            parts[#parts + 1] = string.char(a, b)
        else
            parts[#parts + 1] = string.char(a)
        end
    end
    return table.concat(parts), stop + 1
end

local function readUint(r)
    local n, nextPos = Codec.ReadUint(r.text, r.pos)
    if not n then fail(nextPos) end
    r.pos = nextPos
    return n
end

local function readStringData(r)
    local header = readUint(r)
    local length = floor(header / 2)
    if header % 2 == 1 then
        local s = r.text:sub(r.pos, r.pos + length - 1)
        if #s < length then fail("truncated text") end
        r.pos = r.pos + length
        return s
    end
    local s, nextPos = decodeBytes(r.text, r.pos, length)
    r.pos = nextPos
    return s
end

local function readTable(r)
    local t = {}
    for i = 1, readUint(r) do
        t[i] = readValue(r)
    end
    for _ = 1, readUint(r) do
        local key = readValue(r)
        if type(key) ~= "string" and type(key) ~= "number" then fail("a key of type " .. type(key)) end
        t[key] = readValue(r)
    end
    return t
end

readValue = function(r)
    r.steps = r.steps + 1
    if r.steps % 1024 == 0 then pause(r.job) end
    local tag = r.text:byte(r.pos)
    r.pos = r.pos + 1
    if tag == B_INT then
        local n, nextPos = Codec.ReadInt(r.text, r.pos)
        if not n then fail(nextPos) end
        r.pos = nextPos
        return n
    elseif tag == B_REF then
        local s = r.strings[readUint(r)]
        if not s then fail("unknown string at " .. r.pos) end
        return s
    elseif tag == B_TABLE then
        return readTable(r)
    elseif tag == B_STRING then
        local s = readStringData(r)
        r.count = r.count + 1
        r.strings[r.count] = s
        return s
    elseif tag == B_LONG then
        return readStringData(r)
    elseif tag == B_TRUE then
        return true
    elseif tag == B_FALSE then
        return false
    elseif tag == B_FLOAT then
        local text = readValue(r)
        local n = type(text) == "string" and tonumber(text)
        if not n then fail("not a number: " .. tostring(text)) end
        return n
    end
    fail(tag and ("unexpected character at " .. (r.pos - 1)) or "unexpected end")
end

local function newReader(text, pos, job)
    return { text = text, pos = pos, strings = {}, count = 0, steps = 0, job = job }
end

-- Plain data to text and back, for the tests and the header.
function Backup.Serialize(value)
    local w = newWriter()
    writeValue(w, value)
    return table.concat(w.out)
end

-- The value and the position after it; errors on malformed text.
function Backup.Deserialize(text, pos)
    local r = newReader(text, pos or 1)
    local value = readValue(r)
    return value, r.pos
end

------------------------------------------------------------------------------------------------
-- Jobs: a coroutine that works a few milliseconds per frame (like Data/Coverage.lua), so a long
-- journal never stalls the game. One job per kind ("make", "read"); a new one replaces the old.

local jobs = {}
local frames = {} -- per kind, for OnUpdate
Backup.frames = frames

local function resume(kind)
    local job = jobs[kind]
    if not job then return end
    job.deadline = type(debugprofilestop) == "function" and debugprofilestop() + Backup.BUDGET_MS or nil
    local ok, result, detail = coroutine.resume(job.co)
    if ok and coroutine.status(job.co) ~= "dead" then return end
    jobs[kind] = nil
    frames[kind]:SetScript("OnUpdate", nil)
    if not ok then
        ns.Log:Error("backup", result)
        result, detail = nil, job.failure
    end
    ns.SafeCall("backup:" .. kind, job.onDone, result, detail)
end

local function run(kind, work, onDone, failure)
    local job = { onDone = onDone, failure = failure }
    job.co = coroutine.create(function() return work(job) end)
    jobs[kind] = job
    frames[kind] = frames[kind] or CreateFrame("Frame")
    frames[kind]:SetScript("OnUpdate", function() resume(kind) end)
    resume(kind)
end

function Backup:IsBusy(kind)
    return jobs[kind] ~= nil
end

------------------------------------------------------------------------------------------------
-- Making a backup

-- nil if there is a journal to back up, else why not. A read-only journal is backed up too.
function Backup:CanMake()
    if not Store.db then return L.BACKUP_NOTHING end
    return nil
end

local function noteCount(notes)
    local count = 0
    for _, note in ipairs(type(notes) == "table" and type(notes.list) == "table" and notes.list or {}) do
        if type(note) == "table" then count = count + 1 end
    end
    return count > 0 and count or nil
end

local function make(job, db, trailsDB)
    local now = snapshot(db)
    local w = newWriter(job)
    beginMap(w, trailsDB and 2 or 1)
    writeKey(w, "journal")
    writeJournal(w, db, now)
    if trailsDB then
        writeKey(w, "trails")
        writeTrails(w, trailsDB)
    end
    local payload = table.concat(w.out)
    local meta = now.meta
    local header = {
        addon = ns.version, made = now.made, journal = db.schema, trails = trailsDB and trailsDB.schema or nil,
        guid = meta.guid, name = meta.name, realm = meta.realm, class = meta.class, seq = now.seq,
        entries = w.entries, days = w.days, count = trailsDB and w.segments or nil,
        notes = noteCount(now.notes),
        length = #payload, sum = adler32(payload, 1, job),
    }
    local text = MAGIC .. Backup.Serialize(header) .. payload
    return text, header
end

-- Builds the backup string in the background; onDone(text, header) or onDone(nil, reason).
-- opts.trails: with the Footsteps trails (default), if they can be read.
function Backup:Make(opts, onDone)
    local problem = self:CanMake()
    if problem then return onDone(nil, problem) end
    local trailsDB = not (opts and opts.trails == false) and Paths.db or nil
    run("make", function(job) return make(job, Store.db, trailsDB) end, onDone, L.BACKUP_FAILED)
end

-- A sample for testing (/ws backup sample, developer mode): a very active year made up in
-- memory and never stored, to time a long backup's way through the clipboard. 40 entries and 10
-- trails a day, like the measurement in docs/ARCHITECTURE.md §4.8. A restore checks it, then
-- refuses it.
local function sampleDay(journal, trails, start, random)
    local meta = journal.meta
    local function pick() return 1 + random(#journal.players) end
    local records = {}
    for r = 1, 40 do
        meta.seq = meta.seq + 1
        local kind, data = r % 5
        if kind == 0 then
            data, kind = { level = 10 + r, map = 1412 }, "LEVEL_UP"
        elseif kind == 1 then
            data, kind = { encounterID = 2700 + random(300), name = "Boss " .. random(300), instanceID = 389,
                roster = { pick(), pick(), pick(), pick() } }, "BOSS_KILLED"
        elseif kind == 2 then
            data, kind = { instanceID = 389 + random(40), name = "Dungeon " .. random(40), difficultyID = 1,
                roster = { pick(), pick(), pick(), pick() }, bosses = { 2700 + random(300), 2700 + random(300) },
                dur = 1800 + random(2000) }, "DUNGEON_COMPLETED"
        elseif kind == 3 then
            data, kind = { map = 1412, sub = "Red Cloud Mesa", c = 1, x = -2894 - random(3000), y = -238 + random(3000) }, "DEATH"
        else
            data, kind = { spell = 8690, map = 1412, sub = "Bloodhoof", c = 1, x = -2300, y = -400 }, "TELEPORT"
        end
        records[r] = { id = meta.seq, ts = start + r * 120, type = kind, v = 1, data = data }
    end
    local counters = { gather = {}, quests = {}, travel = { ground = 5000 + random(9000), flight = random(9000) } }
    for _ = 1, 5 do counters.gather[2770 + random(200)] = 1 + random(10) end
    for _ = 1, 10 do counters.quests[1000 + random(5000)] = 1 end
    local segments = {}
    for t = 1, 10 do
        local points, x, y = {}, -3000 + random(5000), -300 + random(5000)
        for p = 1, 300, 2 do
            x, y = x + random(41) - 20, y + random(41) - 20
            points[p], points[p + 1] = x, y
        end
        segments[t] = { c = 1, t = start + t * 600, d = 500 + random(300), f = t % 5 == 0 or nil, p = Codec.EncodePath(points) }
    end
    trails.seq = trails.seq + #segments
    return { records = records, counters = counters }, segments
end

local function sample(job, days)
    local seed = 11
    local function random(n)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed % n
    end
    local me = Schema.identity or ns.Compat.GetPlayerIdentity()
    local year = Time.YearOfMonth(Time.MonthKey(Time.Now()))
    local journal = {
        schema = Schema.CHAR_CURRENT, state = {}, players = {}, months = {},
        meta = { seq = 0, sample = true, guid = me.guid, name = me.name, realm = me.realm, class = me.class },
    }
    local trails = { schema = Schema.PATH_CURRENT, seq = 0, months = {} }
    for i = 1, 40 do
        journal.players[i] = { guid = string.format("Player-0-%08X", i), name = "Companion" .. i, class = "PRIEST" }
    end
    for d = 0, days - 1 do
        local start = time({ year = year, month = 1, day = 1 + d, hour = 18 })
        local dayKey, monthKey = Time.DayKey(start), Time.MonthKey(start)
        local month = journal.months[monthKey] or { days = {}, sessions = {} }
        journal.months[monthKey] = month
        trails.months[monthKey] = trails.months[monthKey] or { days = {} }
        month.days[dayKey], trails.months[monthKey].days[dayKey] = sampleDay(journal, trails, start, random)
        month.sessions[#month.sessions + 1] = { s = start, e = start + 7200 }
        pause(job)
    end
    return make(job, journal, trails)
end

function Backup:MakeSample(days, onDone)
    run("make", function(job) return sample(job, days) end, onDone, L.BACKUP_FAILED)
end

------------------------------------------------------------------------------------------------
-- Reading a backup back

local HEADER_FIELDS = {
    length = "number", sum = "number", made = "number", journal = "number",
    trails = "number?", seq = "number?", entries = "number?", days = "number?", count = "number?", notes = "number?",
    guid = "string?", name = "string?", realm = "string?", class = "string?", addon = "string?",
}

local function validHeader(header)
    if type(header) ~= "table" then return false end
    for field, kind in pairs(HEADER_FIELDS) do
        local value = header[field]
        local optional = kind:sub(-1) == "?"
        if not (value == nil and optional) and type(value) ~= (optional and kind:sub(1, -2) or kind) then
            return false
        end
    end
    return header.length >= 0 and header.length % 1 == 0
end

-- The journal or the trails of a backup, through the same migrations and checks as a saved file.
local function prepare(part, raw, prepareFn)
    local db, kind, detail = prepareFn(Schema, raw)
    if db then return db end
    Schema.Report(kind, "backup's " .. part .. " " .. kind .. (detail and (": " .. detail) or ""))
    return nil, kind == "newer" and L.RESTORE_NEWER or L.RESTORE_UNREADABLE
end

local function read(job, text)
    text = text:gsub("%s+", "")
    local version, start = text:match("^WSB(%d+):()")
    if not version then return nil, L.RESTORE_NOT_BACKUP end
    if tonumber(version) > Backup.FORMAT then return nil, L.RESTORE_NEWER end
    local r = newReader(text, start)
    local ok, header = pcall(readValue, r)
    if not ok or not validHeader(header) then return nil, L.RESTORE_DAMAGED end
    local length = #text - r.pos + 1
    if length < header.length then
        return nil, L.RESTORE_INCOMPLETE:format(ns.YearCards.Number(length), ns.YearCards.Number(header.length))
    end
    if length > header.length or adler32(text, r.pos, job) ~= header.sum then
        return nil, L.RESTORE_DAMAGED
    end
    local reader = newReader(text, r.pos, job)
    local payload = readValue(reader)
    if reader.pos ~= #text + 1 or type(payload) ~= "table" or type(payload.journal) ~= "table" then
        return nil, L.RESTORE_DAMAGED
    end
    local backup = { header = header }
    local reason
    backup.journal, reason = prepare("journal", payload.journal, Schema.PrepareCharacter)
    if not backup.journal then return nil, reason end
    if payload.trails ~= nil then
        backup.trails, reason = prepare("trails", payload.trails, Schema.PreparePaths)
        if not backup.trails then return nil, reason end
    end
    return backup
end

-- Decodes and checks a pasted backup completely, in the background; nothing is touched.
-- onDone(backup) with backup = { header, journal, trails? }, or onDone(nil, reason).
function Backup:Read(text, onDone)
    if type(text) ~= "string" then return onDone(nil, L.RESTORE_NOT_BACKUP) end
    run("read", function(job) return read(job, text) end, onDone, L.RESTORE_DAMAGED)
end

------------------------------------------------------------------------------------------------
-- Restoring: never over data. The journal goes into a journal with no entries or one that didn't
-- load (the missing-journal guard, renames included); the trails into missing or empty trails, or
-- along with a journal that had no entries (what was recorded since the login).

-- "missing" | "empty" | "entries" | "locked" (read-only for a reason a restore can't fix). The
-- player's notes count as entries: a restore would lose them.
local function journalTarget()
    local kind = Schema.safeKind
    if kind == "missing" or kind == "renamed" then return "missing" end
    if ns.safeMode or not Store.db then return "locked" end
    if Store.db.meta.seq == 0 and ns.Notes:Count() == 0 then return "empty" end
    return "entries"
end

-- "missing" | "empty" | "trails" | "locked"
local function trailsTarget()
    if Schema.pathSafeKind == "missing" or (Schema.pathsMissing and not Paths.db) then return "missing" end
    if Paths.readOnly or not Paths.db then return "locked" end
    if Paths:GetCount() == 0 then return "empty" end
    return "trails"
end

-- What a restore of this backup would do now: { journal, trails (booleans), foreign, missing,
-- replacesDays, replacesTrails, keepsTrails, refused (reason) }.
function Backup:Plan(backup)
    local plan = { journal = false, trails = false, replacesDays = 0, replacesTrails = 0 }
    local target = journalTarget()
    plan.journal = target == "missing" or target == "empty"
    plan.missing = target == "missing"
    if plan.journal and target == "empty" then
        plan.replacesDays = #Store:GetDayKeys()
    end
    if backup.trails then
        local trails = trailsTarget()
        plan.trails = (plan.journal or target == "entries")
            and (trails == "missing" or trails == "empty" or (trails == "trails" and target == "empty"))
        plan.keepsTrails = not plan.trails
        if plan.trails and trails == "trails" then
            plan.replacesTrails = Paths:GetCount()
        end
    end
    if backup.journal.meta.sample then
        plan.journal, plan.trails, plan.refused = false, false, L.RESTORE_SAMPLE
    elseif not (plan.journal or plan.trails) then
        if target == "entries" then
            plan.refused = L.RESTORE_HAS_ENTRIES
        else
            plan.refused = L.RESTORE_LOCKED:format(tostring(ns.safeMode or Paths.readOnly))
        end
    end
    local me = Schema.identity or ns.Compat.GetPlayerIdentity()
    local owner = backup.journal.meta.guid or backup.header.guid
    plan.foreign = owner ~= nil and me.guid ~= nil and owner ~= me.guid
    return plan
end

-- The game session goes on after the reload. In the restored journal it starts when the current
-- one started (or now, when nothing was recording), unless the backup already has it.
local function continueSession(journal)
    local current = Store.db and Store:GetCurrentSession()
    local start = current and current.s or Time.Now()
    local monthKey = Time.MonthKey(start)
    local month = journal.months[monthKey]
    if type(month) ~= "table" then
        month = {}
        journal.months[monthKey] = month
    end
    if type(month.days) ~= "table" then month.days = {} end
    if type(month.sessions) ~= "table" then month.sessions = {} end
    local ref = journal.state.session
    local known = type(ref) == "table" and ref.m == monthKey and month.sessions[ref.i]
    if type(known) == "table" and known.s == start then
        known.e = nil
        return
    end
    month.sessions[#month.sessions + 1] = { s = start }
    journal.state.session = { m = monthKey, i = #month.sessions }
end

-- Swaps the backup in, as Plan says, and rebuilds the caches; the caller reloads the UI right
-- after, so the trackers start on the restored state. Returns true and the plan, or nil plus a
-- reason (then nothing was changed).
function Backup:Restore(backup)
    local plan = self:Plan(backup)
    if plan.refused then return nil, plan.refused end
    local journal = plan.journal and backup.journal or nil
    local trails = plan.trails and backup.trails or nil
    if journal then
        local me = Schema.identity or ns.Compat.GetPlayerIdentity()
        local meta = journal.meta
        meta.guid, meta.name, meta.realm = me.guid or meta.guid, me.name or meta.name, me.realm or meta.realm
        meta.class = me.class or meta.class
        continueSession(journal)
        local ok, err = pcall(Index.Rebuild, Index, journal)
        if not ok then
            if Store.db then Index:Build(Store.db) end
            ns.Log:Error("backup", err)
            return nil, L.RESTORE_UNREADABLE
        end
    end
    -- The trackers close what they have open into the tables that are going away, and stop.
    ns.Trackers:DisableAll()
    Schema:SwapIn(journal, trails)
    return true, plan
end
