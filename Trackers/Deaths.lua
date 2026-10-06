local _, ns = ...
local L, Compat, Store, Time = ns.L, ns.Compat, ns.Store, ns.Time

-- Deaths (docs/ARCHITECTURE.md §6.9): where and when the character died. Outdoors the corpse's
-- position is kept in world yards, like Footsteps' trails, so the Footsteps map marks it with a
-- skull. Who killed you would need the combat log, which Forever doesn't allow addons (§1), so an
-- entry says where, not who. Inside instances there is no position: the entry names the map only.
local REPEAT = 10 -- seconds: PLAYER_DEAD again this soon is the same death

ns.RecordTypes:Register("DEATH", {
    version = 1,
    category = "adventure",
    -- map: uiMapID (its name is looked up when shown); c, x, y: continent and world yards
    fields = { map = "number?", c = "number?", x = "number?", y = "number?" },
    render = function(data)
        local name = data.map and Compat.GetMapName(data.map)
        return name and L.DEATH_IN:format(name) or L.DEATH
    end,
})

local Deaths = ns.Trackers:New("Deaths", { label = L.TRACKER_DEATHS, tooltip = L.TRACKER_DEATHS_TIP })

function Deaths:OnEnable()
    self:RegisterEvent("PLAYER_DEAD")
end

function Deaths:PLAYER_DEAD()
    local now = Time.Now()
    if self.last and now - self.last < REPEAT then return end
    self.last = now
    local data = { map = Compat.GetPlayerMapID() }
    local continent, x, y = Compat.GetPlayerWorldPosition()
    if continent then
        data.c, data.x, data.y = continent, math.floor(x + 0.5), math.floor(y + 0.5)
    end
    Store:Append("DEATH", data)
end
