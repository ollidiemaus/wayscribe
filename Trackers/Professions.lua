local _, ns = ...
local L, Compat, Store, YearCards = ns.L, ns.Compat, ns.Store, ns.YearCards

-- Snapshot-diff (docs/ARCHITECTURE.md §6.3): after skill events settle, the learned professions are
-- compared with the saved snapshot. Chat text is never parsed, so this works in every language,
-- and changes made while the addon was off are reconciled at the next login without duplicates.
local RANKS = { 75, 150, 225, 300 }
local SETTLE = 0.5
-- Profession data can still be loading right after login.
local FIRST_SNAPSHOT_DELAY = 3
local ICON = "Interface\\Icons\\Trade_BlackSmithing"

local function skillName(skillLine)
    local name = Compat.GetSkillLineName(skillLine)
    if name then return name end
    local known = Store:GetState("professions")
    local entry = type(known) == "table" and known[skillLine]
    return type(entry) == "table" and entry.name or L.UNKNOWN_SKILL:format(skillLine)
end

ns.RecordTypes:Register("PROFESSION_LEARNED", {
    version = 1,
    category = "progress",
    fields = { skillLine = "number" },
    firstKey = function(data) return "PROF:" .. data.skillLine end,
    -- The professions learned (Your Year).
    rollup = function(rollup, data)
        rollup.professionsLearned = rollup.professionsLearned or {}
        rollup.professionsLearned[data.skillLine] = true
    end,
    merge = function(target, source)
        for skillLine in pairs(source.professionsLearned or {}) do
            target.professionsLearned = target.professionsLearned or {}
            target.professionsLearned[skillLine] = true
        end
    end,
    render = function(data)
        return L.PROFESSION_LEARNED:format(skillName(data.skillLine))
    end,
})

ns.RecordTypes:Register("PROFESSION_RANK", {
    version = 1,
    category = "progress",
    fields = { skillLine = "number", rank = "number" },
    firstKey = function(data) return "PROFRANK:" .. data.skillLine .. ":" .. data.rank end,
    rollup = function(rollup, data)
        rollup.professionRanks = rollup.professionRanks or {}
        rollup.professionRanks[data.skillLine] = math.max(rollup.professionRanks[data.skillLine] or 0, data.rank)
    end,
    merge = function(target, source)
        if not source.professionRanks then return end
        target.professionRanks = target.professionRanks or {}
        for skillLine, rank in pairs(source.professionRanks) do
            target.professionRanks[skillLine] = math.max(target.professionRanks[skillLine] or 0, rank)
        end
    end,
    render = function(data)
        return L.PROFESSION_RANK:format(skillName(data.skillLine), data.rank)
    end,
})

-- skillLine -> points gained that day: "Skill gains: Mining +23, Herbalism +5"
ns.RecordTypes:RegisterCounter("skill", {
    category = "progress",
    order = 30,
    render = function(bucket)
        local parts = {}
        for skillLine, gained in pairs(bucket) do
            parts[#parts + 1] = L.SKILL_GAIN:format(skillName(skillLine), gained)
        end
        table.sort(parts)
        return L.COUNTER_SKILL:format(table.concat(parts, L.LIST_SEPARATOR))
    end,
})

-- "+275 skill points. Learned Mining and Herbalism. Mining reached 225. Skill gains: ..."
YearCards:Register({
    id = "professions",
    order = 70,
    build = function(summary)
        local rollup = summary.rollup
        local skill = rollup.counters.skill
        local points = YearCards.Sum(skill)
        local learned = {}
        for skillLine in pairs(rollup.professionsLearned or {}) do
            learned[#learned + 1] = skillName(skillLine)
        end
        table.sort(learned)
        local ranks = {}
        for skillLine, rank in pairs(rollup.professionRanks or {}) do
            ranks[#ranks + 1] = { name = skillName(skillLine), rank = rank }
        end
        if points == 0 and #learned == 0 and #ranks == 0 then return nil end
        local card = { title = L.CARD_PROFESSIONS, icon = ICON, lines = {} }
        if points > 0 then
            card.big, card.caption = YearCards.Number(points), YearCards.Plural("CARD_PROFESSIONS_POINTS", points)
        else
            card.big, card.caption = YearCards.Number(#learned), YearCards.Plural("CARD_PROFESSIONS_LEARNED_COUNT", #learned)
        end
        if #learned > 0 then
            card.lines[#card.lines + 1] = L.PROFESSION_LEARNED:format(YearCards.List(learned))
        end
        table.sort(ranks, function(a, b)
            if a.rank ~= b.rank then return a.rank > b.rank end
            return a.name < b.name
        end)
        for _, entry in ipairs(ranks) do
            card.lines[#card.lines + 1] = L.PROFESSION_RANK:format(entry.name, entry.rank)
        end
        if points > 0 then
            card.lines[#card.lines + 1] = ns.RecordTypes.counters.skill.render(skill)
        end
        return card
    end,
})

local Professions = ns.Trackers:New("Professions", { label = L.TRACKER_PROFESSIONS, tooltip = L.TRACKER_PROFESSIONS_TIP })

function Professions:OnEnable()
    if Compat.has.professions ~= "modern" then return end
    self:TryRegisterEvent("SKILL_LINES_CHANGED")
    self:TryRegisterEvent("CHAT_MSG_SKILL") -- only a trigger; the text is never read
    self:TryRegisterEvent("TRADE_SKILL_LIST_UPDATE")
    self:Debounce("snapshot", FIRST_SNAPSHOT_DELAY, self.Snapshot)
end

function Professions:SKILL_LINES_CHANGED()
    self:Debounce("snapshot", SETTLE, self.Snapshot)
end
Professions.CHAT_MSG_SKILL = Professions.SKILL_LINES_CHANGED
Professions.TRADE_SKILL_LIST_UPDATE = Professions.SKILL_LINES_CHANGED

function Professions:Snapshot()
    local current = Compat.GetProfessionSnapshot()
    if not current then return end
    local known = Store:GetState("professions")
    if type(known) ~= "table" then
        -- First run: a baseline only. Professions learned before Wayscribe aren't dated today.
        Store:SetState("professions", current)
        return
    end
    for skillLine, now in pairs(current) do
        self:Compare(skillLine, known[skillLine], now)
        known[skillLine] = now
    end
    -- A profession missing from the snapshot stays saved: its data may just not be loaded yet,
    -- and forgetting it would report it as newly learned later.
    Store:SetState("professions", known)
end

function Professions:Compare(skillLine, before, now)
    if type(before) ~= "table" or type(before.rank) ~= "number" then
        Store:Append("PROFESSION_LEARNED", { skillLine = skillLine })
        return
    end
    -- A lower rank means it was unlearned and learned again: nothing to record.
    if now.rank <= before.rank then return end
    Store:Count("skill", skillLine, now.rank - before.rank)
    for _, rank in ipairs(RANKS) do
        if before.rank < rank and now.rank >= rank then
            Store:Append("PROFESSION_RANK", { skillLine = skillLine, rank = rank })
        end
    end
end
