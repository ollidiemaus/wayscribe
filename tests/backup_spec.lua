local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local HOUR = 3600
local GUID = "Player-1-0000AAAA"
local ALPHABET_ONLY = "^[A-Za-z0-9_%-]*$"

local function at(month, day, hour)
    return os.time({ year = 2026, month = month, day = day, hour = hour or 12 })
end

-- A year of play through the real write paths: every fourth day from January 1 to October 1, two
-- hours with a level, a boss, a dungeon with two companions, a death, a hearthstone, gathering,
-- quests, skill and travel, and five trails (the last one a flight). On October 6 at 20:00 a
-- session is being played.
local function playYear(opts)
    opts = opts or {}
    local ns = Stubs.LoadAddon({ level = 10, now = at(1, 1, 18), accountDB = opts.accountDB, locale = opts.locale })
    Stubs.Login()
    local Store, Paths, Codec = ns.Store, ns.Paths, ns.Codec
    local xy = ns.Players:Intern("Player-1-0000000X", "Xy", "Forever", "PRIEST")
    local ab = ns.Players:Intern("Player-1-000000AB", "Äb", "Forever", "WARRIOR")
    Store:SetState("professions", { [186] = { rank = 1, max = 75, name = "Mining" } })
    local seed = 7
    local function random(n)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed % n
    end
    for i = 0, 68 do
        local ts = at(1, 1 + 4 * i, 18)
        Stubs.SetTime(ts)
        if i > 0 then Store:StartSession(ts) end
        Store:Append("LEVEL_UP", { level = math.min(60, 11 + i), map = 1412 })
        Store:Append("BOSS_KILLED", { encounterID = 2700 + i % 9, name = "Boss " .. i % 9, instanceID = 389 })
        Store:Append("DUNGEON_COMPLETED", {
            instanceID = 389 + i % 5, name = "Dungeon " .. i % 5, roster = { xy, ab }, bosses = { 2700 + i % 9 },
            dur = 1800 + i,
        })
        Store:Append("DEATH", { map = 1412, sub = "Red Cloud Mesa", c = 1, x = -2894 - i, y = -238 + i })
        Store:Append("TELEPORT", { spell = 8690, map = 1412, sub = "Bloodhoof", c = 1, x = -2300, y = -400 })
        Store:Count("gather", 2770, 3 + i % 4)
        Store:Count("nodes", "mining", 2)
        Store:Count("quests", 800 + i, 1)
        Store:Count("skill", 186, 2)
        Store:Count("travel", "ground", 2000 + i)
        Store:Count("travel", "flight", 900)
        for t = 1, 5 do
            local points = {}
            local x, y = -3000 + random(500), -300 + random(500)
            for p = 1, 80, 2 do
                x, y = x + random(41) - 20, y + random(41) - 20
                points[p], points[p + 1] = x, y
            end
            Paths:AddSegment({ c = 1, t = ts + t * 600, d = 300, f = t == 5 or nil, p = Codec.EncodePath(points) })
        end
        Stubs.SetTime(ts + 2 * HOUR)
        Store:EndSession(Stubs.Now())
    end
    Stubs.SetTime(at(10, 6, 20))
    Store:StartSession(Stubs.Now())
    return ns
end

-- The backup string, made synchronously (no frame clock in the tests).
local function makeBackup(ns, opts)
    local text, header
    ns.Backup:Make(opts or {}, function(result, detail) text, header = result, detail end)
    T.truthy(text, tostring(header))
    return text, header
end

local function readBackup(ns, text)
    local found, reason
    ns.Backup:Read(text, function(result, detail) found, reason = result, detail end)
    return found, reason
end

local function payloadOf(ns, text)
    local _, pos = ns.Backup.Deserialize(text, 6)
    return ns.Backup.Deserialize(text, pos)
end

-- The journal without its sessions: they change on purpose (the one being played goes on).
local function withoutSessions(db)
    local copy = Stubs.Copy(db)
    copy.state.session = nil
    for _, month in pairs(copy.months) do month.sessions = nil end
    return copy
end

describe("serializer", function()
    it("round-trips plain data, using only the codec's characters", function()
        local ns = Stubs.LoadAddon()
        local bytes = {}
        for i = 0, 255 do bytes[#bytes + 1] = string.char(i) end
        local values = {
            0, 1, -1, 31, 32, 2 ^ 52 - 1, -(2 ^ 52 - 1), 2 ^ 60, 0.5, 1 / 3, -1e-300, 1e300, true, false,
            "", "Kürschnerei", "|cffffffff|r \"quoted\"\n", table.concat(bytes), string.rep("Ab9_-", 30),
            { 1, 2, nil, 4 }, { [1.5] = "x", [-3] = true, [0] = 0, a = { b = { c = {} } } },
        }
        for i, value in ipairs(values) do
            local text = ns.Backup.Serialize(value)
            T.truthy(text:find(ALPHABET_ONLY), "value " .. i .. ": " .. text)
            local back, pos = ns.Backup.Deserialize(text)
            T.same(back, value, "value " .. i)
            T.eq(pos, #text + 1)
        end
    end)

    it("names a repeated string once", function()
        local ns = Stubs.LoadAddon()
        local once = #ns.Backup.Serialize({ "DUNGEON_COMPLETED" })
        local tenTimes = #ns.Backup.Serialize({
            "DUNGEON_COMPLETED", "DUNGEON_COMPLETED", "DUNGEON_COMPLETED", "DUNGEON_COMPLETED", "DUNGEON_COMPLETED",
            "DUNGEON_COMPLETED", "DUNGEON_COMPLETED", "DUNGEON_COMPLETED", "DUNGEON_COMPLETED", "DUNGEON_COMPLETED",
        })
        T.eq(tenTimes, once + 9 * 2, "every repeat is two characters")
    end)

    it("refuses what a saved file can't hold", function()
        local ns = Stubs.LoadAddon()
        local loop = {}
        loop.self = loop
        T.errors(function() ns.Backup.Serialize({ print }) end, "function")
        T.errors(function() ns.Backup.Serialize(0 / 0) end, "number")
        T.errors(function() ns.Backup.Serialize(math.huge) end, "number")
        T.errors(function() ns.Backup.Serialize(loop) end, "holds itself")
        T.errors(function() ns.Backup.Serialize({ [true] = 1 }) end, "key")
        local shared = {}
        T.same(ns.Backup.Deserialize(ns.Backup.Serialize({ shared, shared })), { {}, {} }, "two copies, like the client")
    end)

    it("rejects malformed text", function()
        local ns = Stubs.LoadAddon()
        T.errors(function() ns.Backup.Deserialize("M") end)
        T.errors(function() ns.Backup.Deserialize("RB") end, "unknown string")
        T.errors(function() ns.Backup.Deserialize("Q") end, "unexpected")
        T.errors(function() ns.Backup.Deserialize("S9ab") end, "truncated")
    end)

    it("checks with Adler-32", function()
        local ns = Stubs.LoadAddon()
        T.eq(ns.Backup.Adler32("Wikipedia"), 300286872)
        T.eq(ns.Backup.Adler32(""), 1)
        local long = string.rep("z", 100000)
        local a = (1 + 122 * 100000) % 65521
        T.eq(ns.Backup.Adler32(long) % 65536, a)
    end)
end)

describe("making a backup", function()
    it("/ws backup shows the string selected, with what it holds", function()
        local ns = playYear()
        ns.Slash:Handle("backup")
        local frame = _G.WayscribeBackupFrame
        T.truthy(frame:IsShown())
        local text = ns.Export:GetBackupText()
        T.truthy(text:find("^WSB1:"))
        T.truthy(text:sub(6):find(ALPHABET_ONLY), "only the codec's characters after the magic")
        local texts = Stubs.Texts(frame)
        T.eq(texts[1], "Back up journal")
        T.eq(texts[3], "With footsteps")
        T.truthy(texts[4]:find("^345 entries on 69 days, 345 trails · %d+%.%d KB$"), texts[4])
    end)

    it("holds facts only: no rollups, firsts or the rollup version", function()
        local ns = playYear()
        local text, header = makeBackup(ns)
        T.eq(header.entries, 345)
        T.eq(header.count, 345)
        T.eq(header.length, #text - #("WSB1:" .. ns.Backup.Serialize(header)))
        local payload = payloadOf(ns, text)
        T.eq(payload.journal.firsts, nil)
        T.eq(payload.journal.meta.rollup, nil)
        T.eq(payload.journal.meta.seq, 345)
        for _, month in pairs(payload.journal.months) do
            T.eq(month.rollup, nil)
        end
        T.same(payload.trails, ns.footstepsDB)
        T.same(payload.journal.players, ns.charDB.players)
    end)

    it("ends the session being played in the backup, not in the journal", function()
        local ns = playYear()
        local live = ns.Store:GetCurrentSession()
        local text = makeBackup(ns)
        T.eq(live.e, nil, "still open in the journal")
        local payload = payloadOf(ns, text)
        local ref = payload.journal.state.session
        T.same(payload.journal.months[ref.m].sessions[ref.i], { s = live.s, e = ns.Time.Now() })
    end)

    it("leaves the footsteps out when asked, or when they can't be read", function()
        local ns = playYear()
        local text, header = makeBackup(ns, { trails = false })
        T.eq(header.count, nil)
        T.eq(payloadOf(ns, text).trails, nil)

        ns.Slash:Handle("backup")
        local frame = _G.WayscribeBackupFrame
        local check
        for _, f in ipairs(Stubs.state.frames) do
            if f.frameType == "CheckButton" then check = f end
        end
        check:SetChecked(false)
        check:Click()
        T.truthy(Stubs.Texts(frame)[4]:find("^345 entries on 69 days · "), "journal only now")

        ns.Paths.db = nil
        ns.Export:OpenBackup()
        T.eq(Stubs.Texts(frame)[3], "Footsteps can't be read and are left out")
        T.falsy(check:GetChecked())
    end)

    it("backs up a read-only journal too", function()
        local ns = playYear()
        local saved = Stubs.Copy(ns.charDB)
        saved.meta.guid = "Player-1-0000BBBB"
        ns = Stubs.LoadAddon({ charDB = saved })
        Stubs.Login()
        T.truthy(ns.safeMode)
        local _, header = makeBackup(ns)
        T.eq(header.guid, "Player-1-0000BBBB")
        T.eq(header.entries, 345)
    end)

    it("says why when there is no journal to back up", function()
        local ns = Stubs.LoadAddon({ accountDB = {
            schema = 1, settings = { trackers = {} }, log = {}, characters = { [GUID] = { name = "Tester", realm = "Forever", seq = 9 } },
        } })
        Stubs.Login()
        ns.Slash:Handle("backup")
        local printed = Stubs.Printed()
        T.truthy(printed[#printed]:find("no journal to back up"))
        T.eq(_G.WayscribeBackupFrame, nil)
    end)

    it("makes a sample year in developer mode that can be checked, not restored", function()
        local ns = Stubs.LoadAddon()
        Stubs.Login()
        ns.Slash:Handle("backup sample")
        T.truthy(Stubs.Printed()[#Stubs.Printed()]:find("developer mode"))
        T.eq(_G.WayscribeBackupFrame, nil)

        ns.Slash:Handle("dev")
        ns.Slash:Handle("backup sample 30")
        local frame = _G.WayscribeBackupFrame
        T.eq(Stubs.Texts(frame)[3], "A made-up year of 30 days, for testing")
        T.truthy(Stubs.Texts(frame)[4]:find("^1,200 entries on 30 days, 300 trails · "))
        T.eq(ns.Store:GetStats().records, 0, "the journal is untouched")
        local found = readBackup(ns, ns.Export:GetBackupText())
        T.eq(found.header.entries, 1200)
        local plan = ns.Backup:Plan(found)
        T.truthy(plan.refused:find("sample for testing"))
        T.falsy(ns.Backup:Restore(found))
        T.eq(ns.charDB.meta.seq, 0)
    end)

    it("works in the background, a few milliseconds per frame, while the journal goes on", function()
        local ns = playYear()
        local expected = makeBackup(ns)
        local clock = 0
        _G.debugprofilestop = function()
            clock = clock + 1
            return clock
        end
        local text
        ns.Backup:Make({}, function(result) text = result end)
        T.eq(text, nil, "not done within one frame")
        local frame = ns.Backup.frames.make
        local frames = 1
        while frame:GetScript("OnUpdate") do
            -- A new entry and a counter today, between two frames: not in this backup, no error.
            if frames == 3 then ns.Store:Append("LEVEL_UP", { level = 60 }) end
            frame:GetScript("OnUpdate")()
            frames = frames + 1
        end
        T.truthy(frames > 10, "spread over " .. frames .. " frames")
        T.truthy(text)
        T.eq(ns.charDB.meta.seq, 346)
        T.same(payloadOf(ns, text), payloadOf(ns, expected), "the journal as it was when the backup started")
    end)
end)

describe("restoring", function()
    it("a simulated year survives backup, wipe and restore exactly", function()
        local ns = playYear()
        local cards = ns.YearCards:Build(2026)
        local text = makeBackup(ns)
        local made = Stubs.Now()
        local journal, trails = Stubs.Copy(WayscribeCharDB), Stubs.Copy(WayscribeFootstepsDB)
        local live = journal.state.session

        Stubs.SetTime(made + 60)
        T.truthy(ns.Schema:ResetCharacter())
        ns = Stubs.Relog(nil, true)
        T.eq(ns.Store:GetStats().records, 0)
        T.eq(ns.Paths:GetCount(), 0)

        Stubs.SetTime(made + 120)
        local found = readBackup(ns, text)
        T.truthy(found)
        T.truthy(ns.Backup:Restore(found))
        ns = Stubs.Relog(nil, true)
        T.eq(ns.safeMode, nil)
        T.truthy(ns.Store:IsWritable())

        -- The same facts, and caches rebuilt equal to the originals.
        local restored = WayscribeCharDB
        T.same(withoutSessions(restored), withoutSessions(journal))
        T.same(restored.firsts, journal.firsts)
        for monthKey, month in pairs(journal.months) do
            T.same(restored.months[monthKey].rollup, month.rollup, "rollup of " .. monthKey)
        end
        T.same(WayscribeFootstepsDB, trails)
        -- Your Year tells the same year, but for the time played: this session goes on.
        local again = ns.YearCards:Build(2026)
        T.eq(#again, #cards)
        for i, card in ipairs(cards) do
            if card.id ~= "time" then T.same(again[i], card, card.id) end
        end

        -- Sessions: the one played during the backup ended with it; this game session goes on.
        local before = journal.months[202610].sessions
        local after = restored.months[202610].sessions
        T.eq(#after, #before + 1)
        for i = 1, #before - 1 do T.same(after[i], before[i]) end
        T.same(after[live.i], { s = before[live.i].s, e = made })
        T.same(after[#after], { s = made + 60 })
        T.same(restored.state.session, { m = 202610, i = #after })

        local canary = WayscribeDB.characters[GUID]
        T.eq(canary.seq, 345)
        T.eq(canary.paths, 345)
    end)

    it("restores a journal that didn't load, without /ws accept", function()
        local ns = playYear()
        local text = makeBackup(ns)
        Stubs.Fire("PLAYER_LOGOUT") -- the canary counts the entries
        local journal = Stubs.Copy(WayscribeCharDB)
        local account = Stubs.Copy(WayscribeDB)
        ns = Stubs.LoadAddon({ accountDB = account })
        Stubs.Login()
        T.eq(ns.Schema.safeKind, "missing")
        local found = readBackup(ns, text)
        local plan = ns.Backup:Plan(found)
        T.truthy(plan.journal and plan.trails and plan.missing)
        T.falsy(plan.foreign)
        T.truthy(ns.Backup:Restore(found))
        ns = Stubs.Relog(nil, true)
        T.eq(ns.safeMode, nil)
        T.eq(ns.Paths.readOnly, nil)
        T.truthy(ns.Store:IsWritable())
        T.same(withoutSessions(WayscribeCharDB), withoutSessions(journal))
        T.eq(ns.Paths:GetCount(), 345)
        for _, entry in ipairs(ns.Log:GetEntries()) do
            T.truthy(entry.source ~= "backup", entry.message)
        end
    end)

    it("restores a renamed character's journal under the new name", function()
        local ns = playYear()
        local text = makeBackup(ns)
        Stubs.Fire("PLAYER_LOGOUT")
        ns = Stubs.LoadAddon({ name = "Newname", accountDB = Stubs.Copy(WayscribeDB) })
        Stubs.Login()
        T.eq(ns.Schema.safeKind, "renamed")
        T.truthy(ns.Backup:Restore(readBackup(ns, text)))
        ns = Stubs.Relog({ name = "Newname" }, true)
        T.eq(ns.safeMode, nil)
        T.eq(WayscribeCharDB.meta.name, "Newname")
        T.eq(WayscribeDB.characters[GUID].name, "Newname")
    end)

    it("gives another character's backup this character's identity, after asking", function()
        local ns = playYear()
        local text = makeBackup(ns)
        ns = Stubs.LoadAddon({ guid = "Player-1-0000CCCC", name = "Alt" })
        Stubs.Login()
        local found = readBackup(ns, text)
        T.truthy(ns.Backup:Plan(found).foreign)
        T.truthy(ns.Backup:Restore(found))
        ns = Stubs.Relog({ guid = "Player-1-0000CCCC", name = "Alt" }, true)
        T.eq(ns.safeMode, nil)
        T.eq(WayscribeCharDB.meta.guid, "Player-1-0000CCCC")
        T.eq(WayscribeCharDB.meta.name, "Alt")
        T.eq(WayscribeCharDB.meta.seq, 345)
    end)

    it("replaces what a journal without entries recorded since the login, trails included", function()
        local ns = playYear()
        local text = makeBackup(ns)
        ns = Stubs.LoadAddon({ now = at(10, 7, 9) })
        Stubs.Login()
        local login = ns.Store:GetCurrentSession().s
        ns.Store:Count("travel", "ground", 40)
        ns.Paths:AddSegment({ c = 1, t = Stubs.Now(), d = 30, p = ns.Codec.EncodePath({ 0, 0, 40, 0 }) })
        local found = readBackup(ns, text)
        local plan = ns.Backup:Plan(found)
        T.truthy(plan.journal and plan.trails)
        T.eq(plan.replacesDays, 1)
        T.eq(plan.replacesTrails, 1)
        T.truthy(ns.Backup:Restore(found))
        ns = Stubs.Relog(nil, true)
        T.eq(ns.Paths:GetCount(), 345)
        T.eq(ns.Store:GetDay(20261007), nil)
        T.same(ns.Store:GetCurrentSession(), { s = login }, "this game session goes on")
    end)

    it("refuses a journal with entries, but fills its empty footsteps", function()
        local ns = playYear()
        local text = makeBackup(ns)
        local found = readBackup(ns, text)
        local plan = ns.Backup:Plan(found)
        T.truthy(plan.refused:find("already has entries"))
        local before = Stubs.Copy(WayscribeCharDB)
        T.same({ ns.Backup:Restore(found) }, { nil, plan.refused })
        T.same(WayscribeCharDB, before, "nothing changed")

        ns.Paths:Wipe()
        plan = ns.Backup:Plan(found)
        T.truthy(plan.trails)
        T.falsy(plan.journal)
        T.truthy(ns.Backup:Restore(found))
        ns = Stubs.Relog(nil, true)
        T.eq(ns.Paths:GetCount(), 345)
        T.eq(WayscribeCharDB.meta.seq, 345)
    end)

    it("leaves read-only footsteps alone and restores the journal", function()
        local ns = playYear()
        local text = makeBackup(ns)
        local newer = { schema = 99, seq = 3, months = {} }
        ns = Stubs.LoadAddon({ footstepsDB = newer })
        Stubs.Login()
        local found = readBackup(ns, text)
        local plan = ns.Backup:Plan(found)
        T.truthy(plan.journal)
        T.falsy(plan.trails)
        T.truthy(plan.keepsTrails)
        T.truthy(ns.Backup:Restore(found))
        T.eq(WayscribeFootstepsDB, newer)
    end)

    it("refuses into a journal it can't read", function()
        local ns = playYear()
        local text = makeBackup(ns)
        local saved = Stubs.Copy(WayscribeCharDB)
        saved.schema = 99
        ns = Stubs.LoadAddon({ charDB = saved, accountDB = Stubs.Copy(WayscribeDB) })
        Stubs.Login()
        local plan = ns.Backup:Plan(readBackup(ns, text))
        T.truthy(plan.refused:find("^The journal is read%-only"))
        T.eq(WayscribeCharDB, saved)
    end)

    it("keeps entries of unknown types and upgrades an older backup", function()
        local ns = playYear()
        ns.charDB.months[202601].days[20260101].records[1].type = "FROM_THE_FUTURE"
        local text = makeBackup(ns)
        ns = Stubs.LoadAddon()
        ns.Schema.CHAR_CURRENT = 2
        ns.Schema.charMigrations[2] = function(db)
            local copy = Stubs.Copy(db)
            copy.meta.upgraded = true
            return copy
        end
        Stubs.Login()
        local found = readBackup(ns, text)
        T.truthy(found.journal.meta.upgraded)
        T.eq(found.journal.schema, 2)
        T.truthy(ns.Backup:Restore(found))
        T.eq(ns.charDB.months[202601].days[20260101].records[1].type, "FROM_THE_FUTURE")
    end)
end)

describe("checking a pasted backup", function()
    it("catches a backup that was cut off", function()
        local ns = playYear()
        local text = makeBackup(ns)
        local found, reason = readBackup(ns, text:sub(1, 5000))
        T.eq(found, nil)
        T.truthy(reason:find("^The backup is incomplete: [%d,]+ of [%d,]+ characters arrived"), reason)
    end)

    it("catches a changed character", function()
        local ns = playYear()
        local text = makeBackup(ns)
        local position = #text - 300
        local swapped = text:sub(position, position) == "A" and "B" or "A"
        local found, reason = readBackup(ns, text:sub(1, position - 1) .. swapped .. text:sub(position + 1))
        T.eq(found, nil)
        T.truthy(reason:find("damaged"))
        T.truthy(select(2, readBackup(ns, text .. "AB")):find("damaged"), "too long")
    end)

    it("ignores line breaks and spaces a text editor added", function()
        local ns = playYear()
        local text = makeBackup(ns)
        local wrapped = {}
        for i = 1, #text, 76 do wrapped[#wrapped + 1] = text:sub(i, i + 75) end
        T.truthy(readBackup(ns, "  " .. table.concat(wrapped, "\r\n") .. "\n"))
    end)

    it("tells other text and newer versions apart", function()
        local ns = playYear()
        local text = makeBackup(ns)
        T.truthy(select(2, readBackup(ns, "Wayscribe: the journal of Tester")):find("isn't a Wayscribe backup"))
        T.truthy(select(2, readBackup(ns, "WSB2:" .. text:sub(6))):find("newer Wayscribe version"))
        T.truthy(select(2, readBackup(ns, "WSB1:Q")):find("damaged"))

        local payload = payloadOf(ns, text)
        payload.journal.schema = 99
        local body = ns.Backup.Serialize(payload)
        local header = ns.Backup.Deserialize(text, 6)
        header.length, header.sum = #body, ns.Backup.Adler32(body)
        local found, reason = readBackup(ns, "WSB1:" .. ns.Backup.Serialize(header) .. body)
        T.eq(found, nil)
        T.truthy(reason:find("newer Wayscribe version"))
    end)
end)

describe("restore window", function()
    -- Like the client: the field keeps its first 31 bytes, OnChar sees every character, and the
    -- window reads the paste on the next frame.
    local function paste(text)
        local field
        for _, frame in ipairs(Stubs.state.frames) do
            if frame.frameType == "EditBox" and frame.parent and frame.parent.parent == _G.WayscribeRestoreFrame then
                field = frame
            end
        end
        field:SetText(text:sub(1, 31))
        local onChar = field:GetScript("OnChar")
        for i = 1, #text do onChar(field, text:sub(i, i)) end
        _G.WayscribeRestoreFrame:GetScript("OnUpdate")()
        return field
    end

    it("checks a paste, asks, restores and reloads", function()
        local ns = playYear()
        local text = makeBackup(ns)
        ns = Stubs.LoadAddon({ guid = "Player-1-0000CCCC", name = "Alt" })
        Stubs.Login()
        _G.StaticPopupDialogs = {}
        local shown, shownText
        _G.StaticPopup_Show = function(name, textArg) shown, shownText = name, textArg end
        local reloaded = false
        _G.ReloadUI = function() reloaded = true end

        ns.Slash:Handle("restore")
        T.truthy(_G.WayscribeRestoreFrame:IsShown())
        T.same({ ns.Export:GetRestoreStatus() }, { "Waiting for a backup.", "waiting" })
        _G.WayscribeRestoreFrame:GetScript("OnUpdate")()
        T.eq(ns.Export:GetRestoreStatus(), "Waiting for a backup.", "an empty field is no paste")
        local field = paste(text)
        T.eq(field:GetText(), "", "read once, then emptied")
        T.same({ ns.Export:GetRestoreStatus() }, {
            "Backup of Tester-Forever from Tuesday, October 6, 2026: 345 entries on 69 days, 345 trails."
                .. " The journal and its footsteps can be restored.",
            "good",
        })

        ns.Export:ConfirmRestore()
        T.eq(shown, "WAYSCRIBE_RESTORE_BACKUP")
        T.eq(shownText, table.concat({
            "Restore the backup of Tester-Forever from Tuesday, October 6, 2026: 345 entries on 69 days, 345 trails?",
            "",
            "It belongs to another character (Tester-Forever) and becomes this character's journal.",
            "The interface reloads afterwards.",
        }, "\n"))
        StaticPopupDialogs[shown].OnAccept()
        T.truthy(reloaded)
        T.falsy(_G.WayscribeRestoreFrame:IsShown())
        T.eq(ns.charDB.meta.seq, 345)
        _G.StaticPopupDialogs, _G.StaticPopup_Show, _G.ReloadUI = nil, nil, nil
    end)

    it("reads text typed or set without OnChar from the field", function()
        local ns = playYear()
        local text = makeBackup(ns)
        ns.Export:OpenRestore()
        local field
        for _, frame in ipairs(Stubs.state.frames) do
            if frame.frameType == "EditBox" and frame.parent and frame.parent.parent == _G.WayscribeRestoreFrame then
                field = frame
            end
        end
        field:SetText(text)
        _G.WayscribeRestoreFrame:GetScript("OnUpdate")()
        T.truthy(ns.Export:GetRestoreStatus():find("^Backup of Tester%-Forever"))
    end)

    it("says in red what's wrong, and offers nothing to confirm", function()
        local ns = playYear()
        ns.Export:OpenRestore()
        paste("WSB1:abc")
        local status, color = ns.Export:GetRestoreStatus()
        T.truthy(status:find("damaged"))
        T.eq(color, "bad")
        paste(makeBackup(ns))
        status, color = ns.Export:GetRestoreStatus()
        T.truthy(status:find("^Backup of Tester%-Forever .* This journal already has entries"), status)
        T.eq(color, "bad")
        ns.Export:ConfirmRestore()
        T.eq(_G.StaticPopupDialogs, nil, "nothing to confirm")
    end)

    it("prints how long the paste and the check took, in developer mode", function()
        local ns = playYear()
        ns.Slash:Handle("dev")
        ns.Export:OpenRestore()
        paste("WSB1:abc")
        T.eq(Stubs.Printed()[#Stubs.Printed()], "|cffd4a017Wayscribe|r: 8 characters: the paste took 0.0 s, the check 0.0 s.")
    end)

    it("reads in German", function()
        local ns = playYear({ locale = "deDE" })
        local text = makeBackup(ns)
        Stubs.Fire("PLAYER_LOGOUT")
        ns = Stubs.LoadAddon({ locale = "deDE", accountDB = Stubs.Copy(WayscribeDB) })
        Stubs.Login()
        ns.Export:OpenRestore()
        paste(text)
        T.eq(ns.Export:GetRestoreStatus(),
            "Sicherung von Tester-Forever vom Dienstag, 6. Oktober 2026: 345 Einträge an 69 Tagen, 345 Spuren."
            .. " Das Tagebuch und seine Fußspuren können wiederhergestellt werden.")
    end)
end)
