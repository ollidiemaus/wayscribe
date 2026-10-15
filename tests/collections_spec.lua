local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local HORSE, PINTO, WOLF, RAPTOR = 6, 18, 14, 27

-- The mount journal of a character that owns the Brown Horse.
local function mounts()
    return {
        { id = HORSE, name = "Brown Horse", collected = true },
        { id = PINTO, name = "Pinto" },
        { id = WOLF, name = "Timber Wolf" },
        { id = RAPTOR, name = "Emerald Raptor" },
    }
end

local function mount(id)
    for _, row in ipairs(Stubs.state.mounts) do
        if row.id == id then return row end
    end
end

-- Logs in with `list` (the default unless false) and lets the first look happen.
local function start(list, opts)
    local ns = Stubs.LoadAddon(opts)
    if list ~= false then Stubs.SetMounts(list or mounts()) end
    Stubs.Login()
    Stubs.Advance(1)
    return ns
end

local function collect(id)
    Stubs.CollectMount(id)
    Stubs.Advance(1)
end

local function look()
    Stubs.Fire("PLAYER_ENTERING_WORLD", false, false)
    Stubs.Advance(1)
end

-- The entries as they read, "*" before a first.
local function entries(ns)
    local texts = {}
    for _, record in ipairs(ns.Store:GetRecordsOfType("MOUNT")) do
        texts[#texts + 1] = (record.first and "*" or "") .. ns.RecordTypes:Render(record)
    end
    return texts
end

local function card(ns)
    local cards, ids, found = ns.YearCards:Build(2026), {}, nil
    for i, built in ipairs(cards) do
        ids[built.id] = i
        if built.id == "mounts" then found = built end
    end
    return found, ids
end

describe("collections", function()
    it("take the mounts owned already silently, then record each new one, the first as a first", function()
        local ns = start()
        T.same(entries(ns), {}, "owned before Wayscribe")
        collect(PINTO)
        collect(WOLF)
        T.same(entries(ns), { "*New mount: Pinto", "New mount: Timber Wolf" })
        T.eq(ns.RecordTypes:Get("MOUNT").category, "progress")
        local today = ns.Time.DayKey(Stubs.Now())
        local page = ns.DayView.Build(today, function() return true end)
        T.truthy(page.entries[1].time, "collected during play has its time")
        T.eq(#ns.Log:GetEntries(), 0)
    end)
    it("catch a missed event at the next look, and record a mount found at login on the login day", function()
        local ns = start()
        mount(PINTO).collected = true -- NEW_MOUNT_ADDED never came
        look()
        T.same(entries(ns), { "*New mount: Pinto" })
        Stubs.Fire("PLAYER_LOGOUT")
        mount(WOLF).collected = true -- collected while Wayscribe was off
        ns = Stubs.Relog({ now = Stubs.Now() + 86400 })
        Stubs.Advance(1)
        T.same(entries(ns), { "*New mount: Pinto", "New mount: Timber Wolf" })
        local loginDay = ns.Time.DayKey(Stubs.Now())
        T.same(#ns.Store:GetRecordsOfType("MOUNT", loginDay, loginDay), 1)
    end)

    it("record a first mount on a character that owned none", function()
        local list = mounts()
        list[1].collected = nil
        local ns = start(list)
        collect(HORSE)
        T.same(entries(ns), { "*New mount: Brown Horse" })
    end)

    it("write nothing and log no error when the API is missing, errors or is secret", function()
        local ns = start(false)
        Stubs.Fire("NEW_MOUNT_ADDED", HORSE)
        Stubs.Advance(1)
        Stubs.SetMounts(mounts())
        _G.C_MountJournal.GetMountIDs = function() error("no journal") end
        look()
        _G.C_MountJournal.GetMountIDs = function() return Stubs.SECRET end
        look()
        Stubs.SetMounts(Stubs.state.mounts)
        _G.C_MountJournal.GetMountInfoByID = function() error("no mount") end
        look()
        _G.C_MountJournal.GetMountInfoByID = function() return Stubs.SECRET end
        look()
        Stubs.SetMounts({})
        look()
        T.same(entries(ns), {})
        T.eq(#ns.Log:GetEntries(), 0)
        Stubs.SetMounts(mounts())
        look()
        collect(PINTO)
        T.same(entries(ns), { "*New mount: Pinto" }, "the first readable look is the first look")
    end)

    it("take no mount as uncollected before its collected flag is loaded", function()
        local ns = Stubs.LoadAddon()
        Stubs.SetMounts(mounts())
        local info = _G.C_MountJournal.GetMountInfoByID
        _G.C_MountJournal.GetMountInfoByID = function(id) return (info(id)) end -- names only, as at login
        Stubs.Login()
        Stubs.Advance(1)
        _G.C_MountJournal.GetMountInfoByID = info
        look()
        T.same(entries(ns), {}, "the Brown Horse was owned before")
    end)

    it("stop listening when switched off, and find the mount at the next look once switched on", function()
        local ns = start()
        ns.Trackers:SetWanted("Collections", false)
        collect(PINTO)
        T.same(entries(ns), {})
        ns.Trackers:SetWanted("Collections", true)
        Stubs.Advance(1)
        T.same(entries(ns), { "*New mount: Pinto" })
    end)

    it("repeat nothing after a reload, or when the journal comes back without the tracker's state", function()
        start()
        collect(PINTO)
        local ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        T.same(entries(ns), { "*New mount: Pinto" })
        ns.Store:SetState("collections", nil)
        ns = Stubs.Relog()
        Stubs.Advance(1)
        collect(WOLF)
        T.same(entries(ns), { "*New mount: Pinto", "New mount: Timber Wolf" }, "the journal knows its first")
    end)

    it("repeat nothing after a backup is restored", function()
        local ns = start()
        collect(PINTO)
        local text
        ns.Backup:Make({}, function(result) text = result end)
        T.truthy(ns.Schema:ResetCharacter())
        ns = Stubs.Relog(nil, true)
        local found
        ns.Backup:Read(text, function(result) found = result end)
        T.truthy(ns.Backup:Restore(found))
        ns = Stubs.Relog(nil, true)
        Stubs.Advance(1)
        collect(WOLF)
        T.same(entries(ns), { "*New mount: Pinto", "New mount: Timber Wolf" })
    end)

    it("show the mounts collected and the first mount in Your Year, after Legacy Challenges", function()
        local ns = Stubs.LoadAddon()
        Stubs.SetMounts(mounts())
        Stubs.SetChallenges({ { id = 100, name = "Into the Barrens", category = 1, done = true,
            date = { year = 2026, month = 9, day = 28 } } })
        Stubs.Login()
        Stubs.Advance(1)
        collect(PINTO)
        collect(WOLF)
        local built, ids = card(ns)
        T.eq(built.title, "Mounts")
        T.eq(built.big, "2")
        T.eq(built.caption, "mounts collected")
        T.same(built.lines, { "First mount: Pinto, Saturday, October 3, 2026" })
        T.eq(ids.mounts, ids.legacy + 1)
    end)

    it("read in German", function()
        local ns = start(nil, { locale = "deDE" })
        collect(PINTO)
        T.same(entries(ns), { "*Neues Reittier: Pinto" })
        local built = card(ns)
        T.eq(built.title, "Reittiere")
        T.eq(built.caption, "Reittier gesammelt")
        T.same(built.lines, { "Erstes Reittier: Pinto, Samstag, 3. Oktober 2026" })
    end)

    it("trace each look in developer mode", function()
        local accountDB = { schema = 1, log = {}, characters = {}, settings = {
            trackers = { FirstVisits = false, Gold = false, Reputation = false, Gear = false, LegacyChallenges = false,
                Guild = false, Home = false, PvPRank = false }, devMode = true } }
        local ns = start(nil, { accountDB = accountDB })
        collect(PINTO)
        mount(WOLF).collected = true
        mount(RAPTOR).collected = true
        Stubs.Fire("COMPANION_LEARNED")
        look()
        _G.C_MountJournal = nil
        look()
        local traced = {}
        for i, line in ipairs(ns.Trace:GetLines()) do traced[i] = line:gsub("^%S+ %S+ ", "") end
        T.same(traced, {
            "Collections enable+PLAYER_ENTERING_WORLD: mounts=4 collected=1 -> first look",
            'Collections NEW_MOUNT_ADDED: mounts=4 collected=2 new="18" -> recorded 1',
            'Collections COMPANION_LEARNED+PLAYER_ENTERING_WORLD: mounts=4 collected=4 new="14 27" -> recorded 2',
            "Collections PLAYER_ENTERING_WORLD: mounts=missing -> no mounts",
        })
    end)
end)
