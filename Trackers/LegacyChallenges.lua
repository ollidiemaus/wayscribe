local _, ns = ...
local L, Compat, Store, Time, Trace, YearCards = ns.L, ns.Compat, ns.Store, ns.Time, ns.Trace, ns.YearCards

-- Legacy Challenges (docs/ARCHITECTURE.md §6.16): an entry for each challenge the character
-- completes, once per challenge (the firsts key LEGACY:<id>). A look reads every challenge through
-- the achievement API and compares the completed ones with state.legacy = { done = { [id] = true } },
-- so a missed event is caught at the next look. The first look is not silent: what this character
-- completed before is back-filled on the game's date. Forever's wasEarnedByMe is true for the
-- account's challenges too, so only ACHIEVEMENT_EARNED proves an account-wide challenge is this
-- character's; at a look those are taken silently, and so is everything at a level 1 character's
-- first look.
local SETTLE = 1 -- seconds after an event; login and a loading screen are one look
local ICON = "Interface\\Icons\\Achievement_General"

local function challengeName(data)
    return data.name or L.UNKNOWN_CHALLENGE:format(data.challenge)
end

-- "Completed a Legacy Challenge: Into the Barrens"
ns.RecordTypes:Register("LEGACY_CHALLENGE", {
    version = 1,
    category = "progress",
    fields = { challenge = "number", name = "string?" },
    firstKey = function(data) return "LEGACY:" .. data.challenge end,
    -- How many were completed, and the latest (Your Year).
    rollup = function(rollup, data, record)
        local legacy = rollup.legacy or { n = 0 }
        rollup.legacy = legacy
        legacy.n = legacy.n + 1
        if not legacy.latest or record.ts >= legacy.latest.ts then
            legacy.latest = { challenge = data.challenge, name = data.name, ts = record.ts }
        end
    end,
    merge = function(target, source)
        if not source.legacy then return end
        local legacy = target.legacy or { n = 0 }
        target.legacy = legacy
        legacy.n = legacy.n + source.legacy.n
        local other = source.legacy.latest
        if other and (not legacy.latest or other.ts >= legacy.latest.ts) then
            legacy.latest = { challenge = other.challenge, name = other.name, ts = other.ts }
        end
    end,
    render = function(data)
        return L.LEGACY_COMPLETED:format(challengeName(data))
    end,
})

-- "3 challenges completed", then the latest and its date. After Reputation.
YearCards:Register({
    id = "legacy",
    order = 87,
    build = function(summary)
        local legacy = summary.rollup.legacy
        if not legacy then return nil end
        local card = { title = L.CARD_LEGACY, icon = ICON, lines = {},
            big = YearCards.Number(legacy.n), caption = YearCards.Pattern("CARD_LEGACY_COMPLETED", legacy.n) }
        local latest = legacy.latest
        card.lines[1] = L.CARD_LEGACY_LATEST:format(challengeName(latest), YearCards.Date(latest.ts))
        return card
    end,
})

local Legacy = ns.Trackers:New("LegacyChallenges", { label = L.TRACKER_LEGACY, tooltip = L.TRACKER_LEGACY_TIP })

-- Each event asks for a look a second later; a burst of them is one look, which the launch trace
-- names by every event that asked.
function Legacy:AskForLook(event)
    local asked = self.asked or {}
    self.asked = asked
    if not asked[event] then
        asked[event] = true
        asked[#asked + 1] = event
    end
    self:Debounce("look", SETTLE, self.Look)
end

function Legacy:OnEnable()
    self.asked = nil
    self:TryRegisterEvent("ACHIEVEMENT_EARNED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:AskForLook("enable")
end

-- The challenge this character just earned; kept until a look can read the challenges.
function Legacy:ACHIEVEMENT_EARNED(id)
    id = Compat.Safe(id, "number")
    if id then
        self.earned = self.earned or {}
        self.earned[id] = true
    end
    self:AskForLook("ACHIEVEMENT_EARNED")
end

function Legacy:PLAYER_ENTERING_WORLD()
    self:AskForLook("PLAYER_ENTERING_WORLD")
end

local function sortedKeys(...)
    local keys, seen = {}, {}
    for i = 1, select("#", ...) do
        for key in pairs((select(i, ...))) do
            if not seen[key] then
                seen[key] = true
                keys[#keys + 1] = key
            end
        end
    end
    table.sort(keys)
    return keys
end

-- A back-filled challenge is dated at the end of the game's day (only the day is known), never later
-- than now; one without a date is dated now.
local function backfillOpts(challenge)
    return { ts = challenge.day and math.min(Time.DayEnd(challenge.day), Time.Now()) or nil, backfill = true }
end

-- Compares the completed challenges with the snapshot and writes an entry for each new one this
-- character earned; returns how the look ended and the new ones, for the trace. A failed write
-- keeps nothing of the look, so the next one starts from the same snapshot.
local function compare(challenges, earned)
    if not Store:IsWritable() then return "read-only", {} end
    local saved = Store:GetState("legacy")
    local first = type(saved) ~= "table" or type(saved.done) ~= "table"
    -- A copy, so a look that stops at a failed write leaves the saved snapshot as it was.
    local known = {}
    for id in pairs(first and {} or saved.done) do known[id] = true end
    local silent = first and Compat.GetPlayerLevel() == 1
    local new, written, outcome = {}, 0, nil
    for _, id in ipairs(sortedKeys(challenges, earned)) do
        local challenge = challenges[id] or { done = true } -- earned, but its row can't be read
        local isNew = challenge.done and not known[id]
        if isNew or earned[id] then
            local mine = earned[id] or not (challenge.account or challenge.byMe == false)
            if isNew then
                new[#new + 1] = id .. (mine and "" or challenge.account and ":account" or ":other")
            end
            if mine and not (silent and not earned[id]) and not Store:GetFirst("LEGACY:" .. id) then
                local data = { challenge = id, name = challenge.name or Compat.GetLegacyChallengeName(id) }
                local record, reason = Store:Append("LEGACY_CHALLENGE", data,
                    first and not earned[id] and backfillOpts(challenge) or nil)
                -- What was written so far has its firsts key, so the next look doesn't repeat it.
                if not record then
                    outcome = "not written: " .. tostring(reason)
                    break
                end
                written = written + 1
            end
            known[id] = true
        end
    end
    if outcome then return outcome, new end
    if not Store:SetState("legacy", { done = known }) then return "read-only", new end
    if first then return written > 0 and "back-filled " .. written or "first look", new end
    if written > 0 then return "recorded " .. written, new end
    return #new > 0 and "not this character's" or "unchanged", new
end

function Legacy:Look()
    local asked, earned = self.asked, self.earned or {}
    self.asked = nil
    local challenges, raw = Compat.GetLegacyChallenges()
    local total, completed = 0, 0
    for _, challenge in pairs(challenges or {}) do
        total = total + 1
        if challenge.done then completed = completed + 1 end
    end
    local earnedList = sortedKeys(earned)
    -- A look that reads no challenge (no API, or not loaded yet) is not a first look either, and
    -- keeps what was earned for the next one.
    local outcome, new = "no challenges", nil
    if total > 0 then
        outcome, new = compare(challenges, earned)
        -- A look that wrote nothing (read-only, or a failed write) keeps them for the next one.
        if outcome ~= "read-only" and not outcome:find("^not written") then self.earned = nil end
    end
    local anyNew = new and #new > 0
    Trace:Add(self.id, asked and table.concat(asked, "+"), outcome, "challenges", challenges and total or raw,
        challenges and "completed", completed, #earnedList > 0 and "earned", table.concat(earnedList, " "),
        anyNew and "new", anyNew and table.concat(new, " "))
end
