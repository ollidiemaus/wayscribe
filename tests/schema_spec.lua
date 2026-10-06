local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local GUID = "Player-1-0000AAAA"

local function account(characters)
    return { schema = 1, settings = { trackers = {} }, log = {}, characters = characters or {} }
end

local function journal(extra)
    local db = {
        schema = 1,
        meta = { seq = 1, guid = GUID, name = "Tester", realm = "Forever", created = 1 },
        state = {},
        players = {},
        months = {
            [202610] = {
                days = {
                    [20261002] = {
                        records = { { id = 1, ts = 1790000000, type = "LEVEL_UP", v = 1, data = { level = 10 } } },
                        counters = {},
                    },
                },
                sessions = {},
                rollup = { records = { LEVEL_UP = 1 }, counters = {} },
            },
        },
        firsts = {},
    }
    for key, value in pairs(extra or {}) do db[key] = value end
    return db
end

describe("fresh install", function()
    it("creates both databases at the current schema", function()
        local ns = Stubs.LoadAddon()
        Stubs.Login()
        T.eq(ns.safeMode, nil)
        T.eq(WayscribeDB.schema, ns.Schema.ACCOUNT_CURRENT)
        T.eq(WayscribeCharDB.schema, ns.Schema.CHAR_CURRENT)
        T.eq(WayscribeCharDB.meta.guid, GUID)
        T.eq(WayscribeCharDB.meta.clientBuild, "70009")
        T.truthy(ns.Store:IsWritable())
        T.eq(WayscribeDB.characters[GUID].seq, 0)
    end)

    it("starts fresh when the canary shows no entries", function()
        local ns = Stubs.LoadAddon({ accountDB = account({ [GUID] = { name = "Tester", realm = "Forever", seq = 0 } }) })
        Stubs.Login()
        T.eq(ns.safeMode, nil)
        T.truthy(ns.Store:IsWritable())
    end)
end)

describe("safe mode", function()
    it("leaves a journal from a newer version untouched", function()
        local saved = journal({ schema = 99, futureThing = { a = 1 } })
        local before = Stubs.Copy(saved)
        local ns = Stubs.LoadAddon({ accountDB = account(), charDB = saved })
        Stubs.Login()
        T.eq(ns.Schema.safeKind, "newer")
        T.falsy(ns.Store:IsWritable())
        T.falsy(ns.Trackers:Get("Level").enabled, "no tracker may run")
        Stubs.Fire("PLAYER_LOGOUT")
        T.eq(WayscribeCharDB, saved)
        T.same(WayscribeCharDB, before)
    end)

    it("keeps the loaded data when a migration fails", function()
        local saved = journal()
        local before = Stubs.Copy(saved)
        local ns = Stubs.LoadAddon({ accountDB = account(), charDB = saved })
        ns.Schema.CHAR_CURRENT = 2
        ns.Schema.charMigrations[2] = function(db)
            local copy = Stubs.Copy(db)
            copy.months = nil -- half-way through building the new shape...
            error("boom")
        end
        Stubs.Login()
        T.eq(ns.Schema.safeKind, "failed")
        T.truthy(ns.Log:GetEntries()[1].message:find("boom"))
        T.falsy(ns.Trackers:Get("Session").enabled)
        Stubs.Fire("PLAYER_LOGOUT")
        T.eq(WayscribeCharDB, saved)
        T.same(WayscribeCharDB, before)
    end)

    it("swaps in the result of a successful migration and leaves the input alone", function()
        local saved = journal()
        local before = Stubs.Copy(saved)
        local ns = Stubs.LoadAddon({ accountDB = account(), charDB = saved })
        ns.Schema.CHAR_CURRENT = 2
        ns.Schema.charMigrations[2] = function(db)
            local copy = Stubs.Copy(db)
            copy.meta.migrated = true
            return copy
        end
        Stubs.Login()
        T.eq(ns.safeMode, nil)
        T.eq(WayscribeCharDB.schema, 2)
        T.truthy(WayscribeCharDB.meta.migrated)
        T.same(saved, before)
    end)

    it("rejects a migration that modifies its input in place", function()
        local ns = Stubs.LoadAddon({ accountDB = account(), charDB = journal() })
        ns.Schema.CHAR_CURRENT = 2
        ns.Schema.charMigrations[2] = function(db) db.meta.touched = true; return db end
        Stubs.Login()
        T.eq(ns.Schema.safeKind, "failed")
    end)

    it("refuses a journal with an unexpected shape", function()
        local saved = journal({ months = "oops" })
        local ns = Stubs.LoadAddon({ accountDB = account(), charDB = saved })
        Stubs.Login()
        T.eq(ns.Schema.safeKind, "corrupt")
        T.eq(WayscribeCharDB.months, "oops")
        T.eq(WayscribeCharDB.state, saved.state, "nothing was filled in either")
    end)

    it("keeps a newer account file untouched and works in memory", function()
        local savedAccount = account()
        savedAccount.schema = 5
        local ns = Stubs.LoadAddon({ accountDB = savedAccount })
        Stubs.Login()
        T.eq(ns.Schema.safeKind, "newer")
        T.eq(WayscribeDB, savedAccount)
        T.truthy(ns.accountDB ~= savedAccount)
    end)
end)

describe("missing-journal guard", function()
    it("does not start over when the account file says entries existed", function()
        local ns = Stubs.LoadAddon({ accountDB = account({ [GUID] = { name = "Tester", realm = "Forever", seq = 42 } }) })
        Stubs.Login()
        T.eq(ns.Schema.safeKind, "missing")
        T.truthy(ns.safeMode:find("42 entries"))
        T.eq(WayscribeCharDB, nil)
        T.falsy(ns.Store:IsWritable())
    end)

    it("recognizes a renamed character", function()
        local ns = Stubs.LoadAddon({ name = "Newname", accountDB = account({ [GUID] = { name = "Oldname", realm = "Forever", seq = 7 } }) })
        Stubs.Login()
        T.eq(ns.Schema.safeKind, "renamed")
        T.truthy(ns.safeMode:find("Oldname%-Forever"))
    end)

    it("/ws accept starts a new journal and resets the canary", function()
        local ns = Stubs.LoadAddon({ accountDB = account({ [GUID] = { name = "Tester", realm = "Forever", seq = 42 } }) })
        Stubs.Login()
        T.truthy(ns.Schema:Accept())
        T.eq(WayscribeCharDB.meta.seq, 0)
        T.eq(WayscribeDB.characters[GUID].seq, 0)
        ns = Stubs.Relog(nil, true)
        T.eq(ns.safeMode, nil)
        T.truthy(ns.Store:IsWritable())
    end)

    it("keeps the canary current on logout", function()
        local ns = Stubs.LoadAddon()
        Stubs.Login()
        ns.Store:Append("LEVEL_UP", { level = 11 })
        Stubs.Fire("PLAYER_LOGOUT")
        T.eq(WayscribeDB.characters[GUID].seq, 1)
    end)
end)

describe("foreign journal", function()
    it("shows another character's journal read-only until accepted", function()
        local saved = journal()
        saved.meta.guid = "Player-1-0000BBBB"
        saved.meta.name = "Other"
        local ns = Stubs.LoadAddon({ accountDB = account(), charDB = saved })
        Stubs.Login()
        T.eq(ns.Schema.safeKind, "foreign")
        T.truthy(ns.safeMode:find("Other%-Forever"))
        T.same(ns.Store:GetDayKeys(), { 20261002 }, "readable")
        T.falsy(ns.Store:IsWritable())

        T.truthy(ns.Schema:Accept())
        ns = Stubs.Relog(nil, true)
        T.eq(ns.safeMode, nil)
        T.eq(WayscribeCharDB.meta.guid, GUID)
    end)
end)
