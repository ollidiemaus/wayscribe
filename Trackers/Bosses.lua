local _, ns = ...
local L, Compat, Store, Time, Players, YearCards = ns.L, ns.Compat, ns.Store, ns.Time, ns.Players, ns.YearCards

local ICON = "Interface\\Icons\\INV_Misc_Head_Dragon_01"

-- Every boss kill, in dungeons, raids and the open world (docs/ARCHITECTURE.md §6.5). The localized
-- boss name is captured from the event, because no API maps an encounter ID back to a name.
ns.RecordTypes:Register("BOSS_KILLED", {
    version = 1,
    category = "adventure",
    fields = {
        encounterID = "number", name = "string?", instanceID = "number?", difficultyID = "number?", roster = "table?",
    },
    firstKey = function(data) return "BOSS:" .. data.encounterID end,
    -- Bosses defeated for the first time (Your Year).
    rollup = function(rollup, _, record)
        if record.first then
            rollup.bossFirsts = (rollup.bossFirsts or 0) + 1
        end
    end,
    merge = function(target, source)
        if source.bossFirsts then
            target.bossFirsts = (target.bossFirsts or 0) + source.bossFirsts
        end
    end,
    render = function(data, record)
        local name = data.name or L.UNKNOWN_BOSS:format(data.encounterID)
        return (record.first and L.BOSS_KILLED_FIRST or L.BOSS_KILLED):format(name)
    end,
})

-- "57 bosses defeated, 23 of them for the first time."
YearCards:Register({
    id = "bosses",
    order = 30,
    build = function(summary)
        local kills = summary.rollup.records.BOSS_KILLED or 0
        if kills == 0 then return nil end
        local card = {
            title = L.CARD_BOSSES, icon = ICON,
            big = YearCards.Number(kills), caption = YearCards.Plural("CARD_BOSSES_DEFEATED", kills),
            lines = {},
        }
        local firsts = summary.rollup.bossFirsts or 0
        if firsts > 0 then
            card.lines[1] = YearCards.Plural("CARD_BOSSES_FIRST", firsts)
        end
        return card
    end,
})

-- ENCOUNTER_END and BOSS_KILL can both report one kill; within this many seconds it counts once.
local DUPLICATE_WINDOW = 120

local Bosses = ns.Trackers:New("Bosses", { label = L.TRACKER_BOSSES, tooltip = L.TRACKER_BOSSES_TIP })

-- Both events are rare, so they stay registered everywhere: world bosses count too.
function Bosses:OnEnable()
    self.lastKill = {}
    self:TryRegisterEvent("ENCOUNTER_END")
    self:TryRegisterEvent("BOSS_KILL")
end

function Bosses:ENCOUNTER_END(encounterID, name, difficultyID, _, success)
    success = Compat.Safe(success)
    if success == 1 or success == true then
        self:Record(encounterID, name, difficultyID)
    end
end

function Bosses:BOSS_KILL(encounterID, name)
    self:Record(encounterID, name)
end

function Bosses:Record(encounterID, name, difficultyID)
    encounterID = Compat.Safe(encounterID, "number")
    if not encounterID then return end
    local now = Time.Now()
    local last = self.lastKill[encounterID]
    if last and now - last < DUPLICATE_WINDOW then return end
    self.lastKill[encounterID] = now

    name = Compat.Safe(name, "string")
    local instanceID, instanceType, instanceDifficulty = Compat.GetInstance()
    local inInstance = instanceType ~= nil and instanceType ~= "none"
    Store:Append("BOSS_KILLED", {
        encounterID = encounterID,
        name = name ~= "" and name or nil,
        instanceID = inInstance and instanceID or nil,
        difficultyID = Compat.Safe(difficultyID, "number") or (inInstance and instanceDifficulty or nil),
        roster = Players:InternAll(Compat.GetGroupMembers()),
    })
end
