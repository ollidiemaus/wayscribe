local _, ns = ...
local L, Compat, Store = ns.L, ns.Compat, ns.Store

ns.RecordTypes:Register("LEVEL_UP", {
    version = 1,
    category = "progress",
    fields = { level = "number", map = "number?" },
    rollup = function(rollup, data)
        rollup.maxLevel = math.max(rollup.maxLevel or 0, data.level)
    end,
    merge = function(target, source)
        if source.maxLevel then
            target.maxLevel = math.max(target.maxLevel or 0, source.maxLevel)
        end
    end,
    render = function(data)
        return L.LEVEL_UP:format(data.level)
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
