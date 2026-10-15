local _, ns = ...
local L, Compat, Store, Trace, YearCards = ns.L, ns.Compat, ns.Store, ns.Trace, ns.YearCards

-- Collections (docs/ARCHITECTURE.md §6.20): an entry for each new mount the character collects. A
-- look reads the mount journal's collected flag and compares it with the snapshot,
-- state.collections = { mounts = { [mountID] = true } }, so a missed event is caught at the next
-- look. The first look takes what is owned silently, also for a journal restored without the state.
-- The firsts key MOUNT marks the first mount, so a restored journal doesn't mark another.
local SETTLE = 1 -- seconds after an event; login and a loading screen are one look
local ICON = "Interface\\Icons\\Ability_Mount_RidingHorse"

local function mountName(data)
    return data.name or L.UNKNOWN_MOUNT:format(data.mount)
end

-- "New mount: Brown Horse"
ns.RecordTypes:Register("MOUNT", {
    version = 1,
    category = "progress",
    fields = { mount = "number", name = "string?" },
    firstKey = function() return "MOUNT" end,
    -- How many were collected, and the first mount (Your Year).
    rollup = function(rollup, data, record)
        local mounts = rollup.mounts or { n = 0 }
        rollup.mounts = mounts
        mounts.n = mounts.n + 1
        if record.first then mounts.first = { mount = data.mount, name = data.name, ts = record.ts } end
    end,
    merge = function(target, source)
        if not source.mounts then return end
        local mounts = target.mounts or { n = 0 }
        target.mounts = mounts
        mounts.n = mounts.n + source.mounts.n
        local other = source.mounts.first
        if other and (not mounts.first or other.ts < mounts.first.ts) then
            mounts.first = { mount = other.mount, name = other.name, ts = other.ts }
        end
    end,
    render = function(data)
        return L.MOUNT_NEW:format(mountName(data))
    end,
})

-- "4 mounts collected", then the first mount and its date. After Legacy Challenges.
YearCards:Register({
    id = "mounts",
    order = 88,
    build = function(summary)
        local mounts = summary.rollup.mounts
        if not mounts then return nil end
        local card = { title = L.CARD_MOUNTS, icon = ICON, lines = {},
            big = YearCards.Number(mounts.n), caption = YearCards.Pattern("CARD_MOUNTS_COLLECTED", mounts.n) }
        if mounts.first then
            card.lines[1] = L.CARD_MOUNTS_FIRST:format(mountName(mounts.first), YearCards.Date(mounts.first.ts))
        end
        return card
    end,
})

local Collections = ns.Trackers:New("Collections", {
    label = L.TRACKER_COLLECTIONS, tooltip = L.TRACKER_COLLECTIONS_TIP,
})

-- Each event asks for a look a second later; a burst of them is one look, which the launch trace
-- names by every event that asked.
function Collections:AskForLook(event)
    local asked = self.asked or {}
    self.asked = asked
    if not asked[event] then
        asked[event] = true
        asked[#asked + 1] = event
    end
    self:Debounce("look", SETTLE, self.Look)
end

function Collections:OnEnable()
    self.asked = nil
    self:TryRegisterEvent("NEW_MOUNT_ADDED")
    self:TryRegisterEvent("COMPANION_LEARNED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:AskForLook("enable")
end

function Collections:NEW_MOUNT_ADDED() self:AskForLook("NEW_MOUNT_ADDED") end
function Collections:COMPANION_LEARNED() self:AskForLook("COMPANION_LEARNED") end
function Collections:PLAYER_ENTERING_WORLD() self:AskForLook("PLAYER_ENTERING_WORLD") end

-- The mounts seen collected, as a copy, so a look that stops at a failed write leaves the state as
-- it was; nil before the first look.
local function knownMounts()
    local saved = Store:GetState("collections")
    if type(saved) ~= "table" or type(saved.mounts) ~= "table" then return nil end
    local known = {}
    for id in pairs(saved.mounts) do known[id] = true end
    return known
end

local function save(known)
    return Store:SetState("collections", { mounts = known })
end

-- Compares the collected mounts with the snapshot and writes an entry for each new one; returns how
-- the look ended and the new ones, for the trace.
local function compare(collected)
    if not Store:IsWritable() then return "read-only", {} end
    local known = knownMounts()
    if not known then
        known = {}
        for _, mount in ipairs(collected) do known[mount.id] = true end
        return save(known) and "first look" or "read-only", {}
    end
    local new, written = {}, 0
    for _, mount in ipairs(collected) do
        if not known[mount.id] then
            new[#new + 1] = mount.id
            local record, reason = Store:Append("MOUNT", { mount = mount.id, name = mount.name })
            -- What was written so far is kept, so the next look doesn't write it again.
            if not record then return save(known) and "not written: " .. tostring(reason) or "read-only", new end
            known[mount.id] = true
            written = written + 1
        end
    end
    if not save(known) then return "read-only", new end
    return written > 0 and "recorded " .. written or "unchanged", new
end

function Collections:Look()
    local asked = self.asked
    self.asked = nil
    local mounts, raw = Compat.GetMounts()
    local total, collected = 0, {}
    for id, mount in pairs(mounts or {}) do
        total = total + 1
        if mount.collected then collected[#collected + 1] = { id = id, name = mount.name } end
    end
    table.sort(collected, function(a, b) return a.id < b.id end)
    -- A look that reads no mount (no API, or the journal not loaded yet) is not a first look either.
    local outcome, new = "no mounts", nil
    if total > 0 then outcome, new = compare(collected) end
    local anyNew = new and #new > 0
    Trace:Add(self.id, asked and table.concat(asked, "+"), outcome, "mounts", mounts and total or raw,
        mounts and "collected", #collected, anyNew and "new", anyNew and table.concat(new, " "))
end
