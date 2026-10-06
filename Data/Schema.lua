local _, ns = ...
local L = ns.L

-- Loading, migrating and protecting the SavedVariables (docs/ARCHITECTURE.md §4.6).
--
--   ADDON_LOADED  LoadAccount + LoadCharacter + LoadPaths: shape checks and migrations only.
--   PLAYER_LOGIN  VerifyIdentity: needs the player's GUID, so the missing-journal guard,
--                 rename and foreign-journal checks run here, then the Store is attached.
--                 VerifyPaths: the same guard for the Footsteps trails, then Paths is attached.
--
-- Rule: never destroy data we don't understand. Any problem puts the addon into safe mode and
-- leaves the loaded tables exactly as they were, so logout writes back the same data. A problem
-- with the trails (WayscribeFootstepsDB) only makes the trails read-only; the journal keeps working.
local Schema = {
    CHAR_CURRENT = 1,
    ACCOUNT_CURRENT = 1,
    PATH_CURRENT = 1,
    -- [n] upgrades schema n-1 to n. Each step returns a NEW table and must not modify its input
    -- (build-then-swap), so a failing step leaves the loaded data untouched.
    charMigrations = {},
    accountMigrations = {},
    pathMigrations = {},
    safeKind = nil, -- "newer" | "failed" | "corrupt" | "missing" | "renamed" | "foreign"
    pathSafeKind = nil, -- "newer" | "failed" | "corrupt" | "missing"
}
ns.Schema = Schema

local CHAR_TABLES = { "meta", "state", "players", "months", "firsts" }
local ACCOUNT_TABLES = { "settings", "log", "characters" }
local PATH_TABLES = { "months" }

local function newAccountDB()
    return {
        schema = Schema.ACCOUNT_CURRENT,
        settings = { trackers = {} },
        log = {},
        characters = {},
    }
end

local function newCharDB(identity)
    return {
        schema = Schema.CHAR_CURRENT,
        meta = {
            seq = 0,
            rollup = ns.Index.ROLLUP_VERSION,
            created = time(),
            guid = identity.guid,
            name = identity.name,
            realm = identity.realm,
            class = identity.class,
        },
        state = {},
        players = {},
        months = {},
        firsts = {},
    }
end

local function newFootstepsDB()
    return { schema = Schema.PATH_CURRENT, seq = 0, months = {} }
end

-- Type check first, fill second: a table with one wrong field is left completely untouched.
local function checkAndFill(db, fields)
    for _, field in ipairs(fields) do
        local value = db[field]
        if value ~= nil and type(value) ~= "table" then
            return false, field .. " is a " .. type(value)
        end
    end
    for _, field in ipairs(fields) do
        if db[field] == nil then
            db[field] = {}
        end
    end
    return true
end

-- Returns the migrated table, or nil plus a problem kind and detail.
local function migrate(db, current, migrations)
    local version = db.schema
    if type(version) ~= "number" then
        return nil, "corrupt", "schema version missing"
    end
    if version > current then
        return nil, "newer", "schema " .. version .. " > " .. current
    end
    local working = db
    while version < current do
        local step = migrations[version + 1]
        if not step then
            return nil, "failed", "no migration to schema " .. (version + 1)
        end
        local ok, result = pcall(step, working)
        if not ok or type(result) ~= "table" or result == working then
            return nil, "failed", "migration to schema " .. (version + 1) .. ": " .. ns.Log.ToText(result)
        end
        version = version + 1
        result.schema = version
        working = result
    end
    return working
end

local REASONS = {
    newer = function() return L.SAFE_MODE_NEWER_SCHEMA end,
    failed = function() return L.SAFE_MODE_MIGRATION_FAILED end,
    corrupt = function() return L.SAFE_MODE_CORRUPT end,
    missing = function(seq) return L.SAFE_MODE_MISSING:format(seq or 0) end,
    renamed = function(name, realm) return L.SAFE_MODE_RENAMED:format(tostring(name), tostring(realm)) end,
    foreign = function(owner) return L.SAFE_MODE_FOREIGN:format(tostring(owner)) end,
}

function Schema:Fail(kind, detail, ...)
    ns.Log:Error("schema", kind .. (detail and (": " .. detail) or ""))
    self.safeKind = self.safeKind or kind
    ns.SetSafeMode(REASONS[kind](...))
end

local PATH_REASONS = {
    newer = function() return L.PATHS_NEWER_SCHEMA end,
    failed = function() return L.PATHS_MIGRATION_FAILED end,
    corrupt = function() return L.PATHS_CORRUPT end,
    missing = function(count) return L.PATHS_MISSING:format(count or 0) end,
}

function Schema:FailPaths(kind, detail, ...)
    ns.Log:Error("schema", "trails " .. kind .. (detail and (": " .. detail) or ""))
    self.pathSafeKind = self.pathSafeKind or kind
    local reason = PATH_REASONS[kind](...)
    ns.Paths:SetReadOnly(reason)
    ns.Print(L.PATHS_READ_ONLY:format(reason))
end

function Schema:LoadAccount()
    local raw = WayscribeDB
    if raw == nil then
        WayscribeDB = newAccountDB()
    elseif type(raw) ~= "table" then
        -- Holds only settings and canaries; keep the unreadable value for inspection.
        WayscribeDB = newAccountDB()
        WayscribeDB.quarantined = raw
    else
        local migrated, kind, detail = migrate(raw, self.ACCOUNT_CURRENT, self.accountMigrations)
        local ok = migrated ~= nil
        if migrated then
            local field
            ok, field = checkAndFill(migrated, ACCOUNT_TABLES)
            if not ok then
                kind, detail = "corrupt", field
            end
        end
        if not ok then
            -- Work on an in-memory copy; the saved account table stays exactly as loaded.
            ns.accountDB = newAccountDB()
            ns.Log:Attach(ns.accountDB.log)
            self:Fail(kind, detail)
            return
        end
        WayscribeDB = migrated
    end
    local account = WayscribeDB
    if type(account.settings.trackers) ~= "table" then
        account.settings.trackers = {}
    end
    ns.accountDB = account
    ns.devMode = account.settings.devMode == true
    ns.Log:Attach(account.log)
end

function Schema:LoadCharacter()
    local raw = WayscribeCharDB
    if raw == nil then
        -- Fresh character or a journal that failed to load: VerifyIdentity decides.
        self.charMissing = true
        return
    end
    if type(raw) ~= "table" then
        return self:Fail("corrupt", "journal root is a " .. type(raw))
    end
    local migrated, kind, detail = migrate(raw, self.CHAR_CURRENT, self.charMigrations)
    if not migrated then
        return self:Fail(kind, detail)
    end
    local ok, field = checkAndFill(migrated, CHAR_TABLES)
    if not ok then
        return self:Fail("corrupt", field)
    end
    if type(migrated.meta.seq) ~= "number" then
        return self:Fail("corrupt", "meta.seq missing")
    end
    WayscribeCharDB = migrated
    ns.charDB = migrated
end

-- WayscribeFootstepsDB is left exactly as loaded when it can't be used, like the journal.
function Schema:LoadPaths()
    local raw = WayscribeFootstepsDB
    if raw == nil then
        self.pathsMissing = true
        return
    end
    if type(raw) ~= "table" then
        return self:FailPaths("corrupt", "trails root is a " .. type(raw))
    end
    local migrated, kind, detail = migrate(raw, self.PATH_CURRENT, self.pathMigrations)
    if not migrated then
        return self:FailPaths(kind, detail)
    end
    local ok, field = checkAndFill(migrated, PATH_TABLES)
    if not ok then
        return self:FailPaths("corrupt", field)
    end
    if type(migrated.seq) ~= "number" then
        return self:FailPaths("corrupt", "seq missing")
    end
    WayscribeFootstepsDB = migrated
    ns.footstepsDB = migrated
end

function Schema:VerifyIdentity()
    local me = ns.Compat.GetPlayerIdentity()
    self.identity = me
    if ns.safeMode and not ns.charDB then return end

    local canary = me.guid and ns.accountDB.characters[me.guid]
    if self.charMissing then
        if type(canary) == "table" and type(canary.seq) == "number" and canary.seq > 0 then
            if canary.name ~= me.name or canary.realm ~= me.realm then
                return self:Fail("renamed", nil, canary.name, canary.realm)
            end
            return self:Fail("missing", nil, canary.seq)
        end
        WayscribeCharDB = newCharDB(me)
        ns.charDB = WayscribeCharDB
        self.charMissing = nil
    end

    local db = ns.charDB
    local meta = db.meta
    if meta.guid and me.guid and meta.guid ~= me.guid then
        -- Readable, but someone else's: show it read-only until /ws accept.
        ns.Store:Attach(db)
        local owner = tostring(meta.name) .. "-" .. tostring(meta.realm)
        return self:Fail("foreign", meta.guid, owner)
    end

    meta.guid = meta.guid or me.guid
    meta.name = me.name or meta.name
    meta.realm = me.realm or meta.realm
    meta.class = me.class or meta.class
    meta.addonVersion = ns.version
    meta.clientBuild = ns.Compat.clientBuild
    meta.interface = ns.Compat.interface
    ns.Store:Attach(db)
    -- Rollups are caches: ones from an older version are rebuilt from the records (§4.5).
    ns.Index:Upgrade(db)
    self:TouchCanary()
end

-- Missing trails with a canary that counted some: they didn't load. Without the journal there's
-- nothing to check against (its own guard has already warned), so the trails stay unattached.
function Schema:VerifyPaths()
    if self.pathsMissing then
        if ns.safeMode then return end
        local me = self.identity or ns.Compat.GetPlayerIdentity()
        local canary = me.guid and ns.accountDB.characters[me.guid]
        local saved = type(canary) == "table" and type(canary.paths) == "number" and canary.paths or 0
        if saved > 0 then
            return self:FailPaths("missing", nil, saved)
        end
        WayscribeFootstepsDB = newFootstepsDB()
        ns.footstepsDB = WayscribeFootstepsDB
        self.pathsMissing = nil
    end
    if ns.footstepsDB then
        ns.Paths:Attach(ns.footstepsDB)
    end
end

-- The account file vouches for each character's journal and trails (missing-data guard).
function Schema:TouchCanary()
    if not ns.Store:IsWritable() then return end
    local meta = ns.charDB.meta
    if not meta.guid then return end
    local canary = ns.accountDB.characters[meta.guid]
    if type(canary) ~= "table" then
        canary = {}
        ns.accountDB.characters[meta.guid] = canary
    end
    canary.name = meta.name
    canary.realm = meta.realm
    canary.seq = meta.seq
    if ns.Paths:IsWritable() then
        canary.paths = ns.Paths.db.seq
    end
    canary.savedAt = time()
end

-- Settings > Data > Reset: an empty journal and no trails for this character, chosen by the
-- player behind a confirmation. The caller reloads the UI so every tracker starts afresh.
function Schema:ResetCharacter()
    if not ns.Store:IsWritable() then return false end
    WayscribeCharDB = newCharDB(self.identity or ns.Compat.GetPlayerIdentity())
    ns.charDB = WayscribeCharDB
    ns.Store:Attach(WayscribeCharDB)
    WayscribeFootstepsDB = newFootstepsDB()
    ns.footstepsDB = WayscribeFootstepsDB
    ns.Paths:Attach(WayscribeFootstepsDB)
    self:TouchCanary()
    return true
end

-- /ws accept: the player resolves a guard situation. Takes effect after /reload.
function Schema:Accept()
    local me = self.identity or ns.Compat.GetPlayerIdentity()
    local kind = self.safeKind
    local accepted = false
    if kind == "foreign" and ns.charDB then
        ns.charDB.meta.guid = me.guid
        ns.charDB.meta.name = me.name
        ns.charDB.meta.realm = me.realm
        accepted = true
    elseif (kind == "missing" or kind == "renamed") and me.guid then
        WayscribeCharDB = newCharDB(me)
        ns.charDB = WayscribeCharDB
        ns.accountDB.characters[me.guid] = { name = me.name, realm = me.realm, seq = 0, savedAt = time() }
        accepted = true
    end
    if self.pathSafeKind == "missing" then
        WayscribeFootstepsDB = newFootstepsDB()
        local canary = me.guid and ns.accountDB.characters[me.guid]
        if type(canary) == "table" then
            canary.paths = 0
        end
        accepted = true
    end
    return accepted
end
