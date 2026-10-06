local _, ns = ...
local L, Compat, Store, YearCards = ns.L, ns.Compat, ns.Store, ns.YearCards

local ICON = "Interface\\Icons\\Spell_Holy_PowerInfusion"

ns.RecordTypes:Register("LEVEL_UP", {
    version = 1,
    category = "progress",
    fields = { level = "number", map = "number?" },
    -- The range of levels reached, and when the highest was first reached (Your Year).
    rollup = function(rollup, data, record)
        rollup.minLevel = math.min(rollup.minLevel or data.level, data.level)
        if data.level > (rollup.maxLevel or 0) then
            rollup.maxLevel = data.level
            rollup.maxLevelAt = record.ts
        end
    end,
    -- Months come in order, so a later month only wins with a higher level.
    merge = function(target, source)
        if source.minLevel then
            target.minLevel = math.min(target.minLevel or source.minLevel, source.minLevel)
        end
        if source.maxLevel and source.maxLevel > (target.maxLevel or 0) then
            target.maxLevel, target.maxLevelAt = source.maxLevel, source.maxLevelAt
        end
    end,
    render = function(data)
        return L.LEVEL_UP:format(data.level)
    end,
})

-- "+49 levels gained, from 11 to 60. Reached level 60 on Saturday, October 3, 2026"
YearCards:Register({
    id = "levels",
    order = 10,
    build = function(summary)
        local rollup = summary.rollup
        if not rollup.maxLevel then return nil end
        local from = (rollup.minLevel or rollup.maxLevel) - 1
        local gained = rollup.maxLevel - from
        local card = {
            title = L.CARD_LEVELS, icon = ICON,
            big = "+" .. gained,
            caption = YearCards.Pattern("CARD_LEVELS_GAINED", gained):format(from, rollup.maxLevel),
            lines = {},
        }
        if rollup.maxLevelAt then
            card.lines[1] = L.CARD_LEVELS_REACHED:format(rollup.maxLevel, YearCards.Date(rollup.maxLevelAt))
        end
        return card
    end,
})

local Level = ns.Trackers:New("Level", { label = L.TRACKER_LEVEL })

function Level:OnEnable()
    -- Baseline only: levels gained while the addon was off are not back-filled with wrong dates.
    local current = Compat.GetPlayerLevel()
    local known = Store:GetState("level")
    if current and (type(known) ~= "number" or current > known) then
        Store:SetState("level", current)
    end
    self:RegisterEvent("PLAYER_LEVEL_UP")
end

function Level:PLAYER_LEVEL_UP(newLevel)
    local level = Compat.Safe(newLevel, "number")
    if level then
        self:Record(level)
    else
        -- The event argument was secret; UnitLevel has caught up a moment later.
        self:After(1, function(module)
            local current = Compat.GetPlayerLevel()
            if current then
                module:Record(current)
            end
        end)
    end
end

-- The saved "level" state makes duplicate events and replays harmless.
function Level:Record(level)
    local known = Store:GetState("level")
    if type(known) == "number" and level <= known then return end
    Store:SetState("level", level)
    Store:Append("LEVEL_UP", { level = level, map = Compat.GetPlayerMapID() })
end
