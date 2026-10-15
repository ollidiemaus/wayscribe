local _, ns = ...
local L, Compat, Store, Trace, YearCards = ns.L, ns.Compat, ns.Store, ns.Trace, ns.YearCards

-- Reputation (docs/ARCHITECTURE.md §6.14): the first time the character reaches Friendly, Honored,
-- Revered or Exalted with a faction, and the first time it falls to Hostile or Hated. A look reads
-- every standing and compares it with the saved snapshot, state.reputation = { [factionID] =
-- { r = reaction, hi = highest, lo = lowest } }, so a missed event is caught at the next look, and
-- climbing back to a standing held before is no entry. Meeting a faction is no entry, and the first
-- look is silent. "Reached before" is also the journal's own firsts (REP:<faction>:<standing>), so
-- a restored journal never repeats one.
local SETTLE = 1 -- seconds after an event; a burst of UPDATE_FACTION is one look
local ICON = "Interface\\Icons\\Achievement_Reputation_01"
local FRIENDLY, HOSTILE, HONORED, EXALTED = 5, 2, 6, 8
-- Forever's progress tracks are factions too (PvP Rank Points, Legacy Track), but not standings.
local NOT_STANDINGS = { [2800] = true, [2802] = true }

-- The client's name for a standing, the female form for a female character.
local function standingLabel(reaction)
    local key = "FACTION_STANDING_LABEL" .. reaction
    local label = Compat.Call(UnitSex, "player") == 3 and Compat.Safe(_G[key .. "_FEMALE"], "string")
    return label or Compat.Safe(_G[key], "string") or L["STANDING_" .. reaction]
end

local function factionName(data)
    return data.name or L.UNKNOWN_FACTION:format(data.faction)
end

-- "Reached Honored with Thunder Bluff", "Fell to Hostile with Booty Bay"
ns.RecordTypes:Register("REPUTATION", {
    version = 1,
    category = "progress",
    fields = { faction = "number", standing = "number", name = "string?" },
    firstKey = function(data) return "REP:" .. data.faction .. ":" .. data.standing end,
    -- Per faction: the best standing reached, how many standings up and how many entries (Your Year).
    rollup = function(rollup, data)
        rollup.reputation = rollup.reputation or {}
        local faction = rollup.reputation[data.faction] or { n = 0, climbed = 0 }
        rollup.reputation[data.faction] = faction
        faction.n = faction.n + 1
        faction.name = data.name or faction.name
        if data.standing >= FRIENDLY then
            faction.climbed = faction.climbed + 1
            faction.best = math.max(faction.best or 0, data.standing)
        end
    end,
    merge = function(target, source)
        for id, other in pairs(source.reputation or {}) do
            target.reputation = target.reputation or {}
            local faction = target.reputation[id] or { n = 0, climbed = 0 }
            target.reputation[id] = faction
            faction.n, faction.climbed = faction.n + other.n, faction.climbed + other.climbed
            faction.name = other.name or faction.name
            if other.best then faction.best = math.max(faction.best or 0, other.best) end
        end
    end,
    render = function(data)
        local pattern = data.standing >= FRIENDLY and L.REPUTATION_UP or L.REPUTATION_DOWN
        return pattern:format(standingLabel(data.standing), factionName(data))
    end,
})

-- "5 new standings", the factions at Exalted, Revered and Honored, and the faction climbed most.
-- After Quests.
YearCards:Register({
    id = "reputation",
    order = 85,
    build = function(summary)
        local total, tiers, most = 0, {}, nil
        for id, faction in pairs(summary.rollup.reputation or {}) do
            total = total + faction.n
            local name = factionName({ faction = id, name = faction.name })
            if faction.best and faction.best >= HONORED then
                tiers[faction.best] = tiers[faction.best] or {}
                table.insert(tiers[faction.best], name)
            end
            if faction.climbed > 0 and (not most or faction.climbed > most.climbed
                or (faction.climbed == most.climbed and name < most.name)) then
                most = { name = name, climbed = faction.climbed }
            end
        end
        if total == 0 then return nil end
        local card = { title = L.CARD_REPUTATION, icon = ICON, lines = {},
            big = YearCards.Number(total), caption = YearCards.Pattern("CARD_REPUTATION_STANDINGS", total) }
        for standing = EXALTED, HONORED, -1 do
            local names = tiers[standing]
            if names then
                table.sort(names)
                card.lines[#card.lines + 1] = L.CARD_REPUTATION_TIER:format(standingLabel(standing), YearCards.List(names))
            end
        end
        if most then
            card.lines[#card.lines + 1] = YearCards.Pattern("CARD_REPUTATION_CLIMBED", most.climbed)
                :format(most.name, YearCards.Number(most.climbed))
        end
        return card
    end,
})

local Reputation = ns.Trackers:New("Reputation", {
    label = L.TRACKER_REPUTATION, tooltip = L.TRACKER_REPUTATION_TIP,
})

-- Each event asks for a look a second later; a burst of them is one look, which the launch trace
-- names by every event that asked.
function Reputation:AskForLook(event)
    local asked = self.asked or {}
    self.asked = asked
    if not asked[event] then
        asked[event] = true
        asked[#asked + 1] = event
    end
    self:Debounce("look", SETTLE, self.Look)
end

function Reputation:OnEnable()
    self.asked = nil
    self:TryRegisterEvent("UPDATE_FACTION")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:AskForLook("enable")
end

function Reputation:UPDATE_FACTION()
    self:AskForLook("UPDATE_FACTION")
end

function Reputation:PLAYER_ENTERING_WORLD()
    self:AskForLook("PLAYER_ENTERING_WORLD")
end

-- Every standing: the list's, and the known factions a collapsed header hides, read by ID.
local function readStandings(known)
    local standings, rows = Compat.GetFactionStandings()
    if not standings then return nil, rows end
    for id in pairs(known or {}) do
        if not standings[id] then
            local name, reaction = Compat.GetFactionStanding(id)
            if reaction then standings[id] = { name = name, reaction = reaction } end
        end
    end
    for id in pairs(NOT_STANDINGS) do standings[id] = nil end
    return standings, rows
end

-- The standings `faction` passed on its way from `known` to `reaction` that make an entry: up to
-- Friendly or better above the highest, down to Hostile or worse below the lowest.
local function newStandings(known, reaction)
    local passed = {}
    for standing = math.max(known.hi + 1, FRIENDLY), reaction do passed[#passed + 1] = standing end
    for standing = math.min(known.lo - 1, HOSTILE), reaction, -1 do passed[#passed + 1] = standing end
    return passed
end

-- Compares the standings with the snapshot and writes an entry for each new one; returns how the
-- look ended and what changed, for the trace.
local function compare(standings)
    if not Store:IsWritable() then return "read-only", {} end
    local saved = Store:GetState("reputation")
    local first = type(saved) ~= "table"
    -- A copy, so a look that stops at a failed write leaves the saved snapshot as it was.
    local known = {}
    for id, entry in pairs(first and {} or saved) do
        if type(entry) == "table" then known[id] = { r = entry.r, hi = entry.hi, lo = entry.lo } end
    end
    local changed, written = {}, 0
    for id, now in pairs(standings) do
        local before = known[id]
        if not before then
            known[id] = { r = now.reaction, hi = now.reaction, lo = now.reaction }
        elseif before.r ~= now.reaction then
            changed[#changed + 1] = id .. ":" .. tostring(before.r) .. ">" .. now.reaction
            for _, standing in ipairs(newStandings(before, now.reaction)) do
                if not Store:GetFirst("REP:" .. id .. ":" .. standing) then
                    local record, reason = Store:Append("REPUTATION", { faction = id, standing = standing, name = now.name })
                    if not record then return "not written: " .. tostring(reason), changed end
                    written = written + 1
                end
            end
            before.r = now.reaction
            before.hi, before.lo = math.max(before.hi, now.reaction), math.min(before.lo, now.reaction)
        end
    end
    if not Store:SetState("reputation", known) then return "read-only", changed end
    if first then return "first look", changed end
    if written > 0 then return "recorded " .. written, changed end
    return #changed > 0 and "known" or "unchanged", changed
end

function Reputation:Look()
    local asked = self.asked
    self.asked = nil
    local saved = Store:GetState("reputation")
    local standings, rows = readStandings(type(saved) == "table" and saved or nil)
    local outcome, changed, count = "no factions", nil, 0
    for _ in pairs(standings or {}) do count = count + 1 end
    if count > 0 then
        outcome, changed = compare(standings)
        table.sort(changed)
    end
    local anyChange = changed and #changed > 0
    Trace:Add(self.id, asked and table.concat(asked, "+"), outcome, "rows", rows, "factions", count,
        anyChange and "changed", anyChange and table.concat(changed, " "))
end
