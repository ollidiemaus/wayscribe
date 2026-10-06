local _, ns = ...
local L, Compat, Store, Time = ns.L, ns.Compat, ns.Store, ns.Time
local StaticData = ns.StaticData

-- Quests turned in and the quest chains they complete (docs/ARCHITECTURE.md §6.7):
--   * Every turn-in is a counter, quests[questID] per day. That list is the fact chains derive from.
--   * Chain providers are asked in order. Curated chains come first: their names are chosen and
--     localized, and they can be matched again later. The client's quest lines are the fallback,
--     live only, because that API answers for the player's map at the time.
--   * Retroactive: after curated chains are added, the next login (and /ws rebuild) scans the saved
--     quest IDs and back-fills each chain on the day its final quest was turned in.
local BACKFILL_DELAY = 5

local function chainKey(data)
    if data.chain then return "CHAIN:" .. data.chain end
    return "QUESTLINE:" .. tostring(data.questLine)
end

local function chainName(data)
    local name = data.chain and rawget(L, "CHAIN_" .. data.chain)
    return name or data.title or Compat.GetQuestTitle(data.quest) or L.UNKNOWN_CHAIN:format(data.quest)
end

ns.RecordTypes:Register("QUEST_CHAIN_COMPLETED", {
    version = 1,
    category = "quests",
    fields = { chain = "string?", questLine = "number?", quest = "number", title = "string?" },
    firstKey = chainKey,
    render = function(data)
        return L.QUEST_CHAIN_COMPLETED:format(chainName(data))
    end,
})

-- questID -> times turned in that day: "Quests turned in: 7"
ns.RecordTypes:RegisterCounter("quests", {
    category = "quests",
    order = 40,
    render = function(bucket)
        local total = 0
        for _, count in pairs(bucket) do
            total = total + count
        end
        return L.COUNTER_QUESTS:format(total)
    end,
})

-- final questID -> curated chain id
local function curatedIndex()
    local index = {}
    for _, chain in ipairs(StaticData.QuestChains) do
        for _, questID in ipairs(chain.finals) do
            index[questID] = chain.id
        end
    end
    return index
end

-- Each provider returns the record data of the chain questID completes, or nil.
local PROVIDERS = {
    {
        retroactive = true,
        match = function(tracker, questID)
            local id = tracker.curated[questID]
            return id and { chain = id, quest = questID }
        end,
    },
    {
        match = function(_, questID)
            local lineID, name = Compat.GetQuestLineEnd(questID)
            return lineID and { questLine = lineID, quest = questID, title = name or Compat.GetQuestTitle(questID) }
        end,
    },
}

local QuestChains = ns.Trackers:New("QuestChains", { label = L.TRACKER_QUESTS, tooltip = L.TRACKER_QUESTS_TIP })

function QuestChains:OnEnable()
    self.curated = curatedIndex()
    self:RegisterEvent("QUEST_TURNED_IN")
    ns.Bus:On("REBUILT", self, self.Backfill)
    -- New chain definitions since the last login light up chains finished long ago.
    if Store:GetState("questChains") ~= StaticData.QuestChainsVersion then
        self:After(BACKFILL_DELAY, function(module)
            module:Backfill()
            Store:SetState("questChains", StaticData.QuestChainsVersion)
        end)
    end
end

function QuestChains:OnDisable()
    ns.Bus:Off("REBUILT", self)
end

function QuestChains:QUEST_TURNED_IN(questID)
    questID = Compat.Safe(questID, "number")
    if not questID then return end
    Store:Count("quests", questID, 1)
    for _, provider in ipairs(PROVIDERS) do
        local data = provider.match(self, questID)
        if data then
            self:Complete(data)
            return
        end
    end
end

-- A chain is completed once; the firsts index knows whether it already is.
function QuestChains:Complete(data, opts)
    if Store:GetFirst(chainKey(data)) then return nil end
    return Store:Append("QUEST_CHAIN_COMPLETED", data, opts)
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do
        if type(key) == "number" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

-- Quests that already completed a chain, whichever provider recorded it.
local function creditedQuests(dayKeys)
    local credited = {}
    for _, dayKey in ipairs(dayKeys) do
        for _, record in ipairs(Store:GetDay(dayKey).records) do
            local quest = record.type == "QUEST_CHAIN_COMPLETED" and type(record.data) == "table" and record.data.quest
            if quest then
                credited[quest] = true
            end
        end
    end
    return credited
end

local function matchRetroactive(tracker, questID)
    for _, provider in ipairs(PROVIDERS) do
        local data = provider.retroactive and provider.match(tracker, questID)
        if data then return data end
    end
    return nil
end

-- Adds the chains whose final quest is among the saved turn-ins but which have no entry yet. Only
-- the day is known, so the entry is dated at its end and flagged as back-filled. Returns the count.
function QuestChains:Backfill()
    if not Store:IsWritable() then return 0 end
    self.curated = curatedIndex()
    local dayKeys = Store:GetDayKeys()
    local credited = creditedQuests(dayKeys)
    local added = 0
    for i = #dayKeys, 1, -1 do -- oldest first
        local dayKey = dayKeys[i]
        local quests = Store:GetDay(dayKey).counters.quests
        for _, questID in ipairs(type(quests) == "table" and sortedKeys(quests) or {}) do
            local data = not credited[questID] and matchRetroactive(self, questID)
            local ts = math.min(Time.DayEnd(dayKey), Time.Now())
            if data and self:Complete(data, { ts = ts, backfill = true }) then
                credited[questID] = true
                added = added + 1
            end
        end
    end
    if added > 0 then
        ns.Print(L.CHAINS_BACKFILLED:format(added))
    end
    return added
end
