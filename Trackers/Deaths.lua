local _, ns = ...
local L, Compat, Store, Time = ns.L, ns.Compat, ns.Store, ns.Time

-- Deaths (docs/ARCHITECTURE.md §6.9): where and when the character died. Outdoors the corpse's
-- position is kept in world yards, like Footsteps' trails, so the Footsteps map marks it with a
-- skull. Who killed you would need the combat log, which Forever doesn't allow addons (§1), so an
-- entry says where, not who. Inside instances there is no position: the entry names the map only.
local REPEAT = 10 -- seconds: PLAYER_DEAD again this soon is the same death
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

-- "Red Cloud Mesa, Mulgore", or whichever of the two is known.
local function placeOf(data)
    local zone = data.map and Compat.GetMapName(data.map)
    local sub = data.sub
    if sub and zone and sub ~= zone then
        return L.PLACE_IN_ZONE:format(sub, zone)
    end
    return sub or zone
end

ns.RecordTypes:Register("DEATH", {
    version = 1,
    category = "adventure",
    -- map: uiMapID (its name is looked up when shown); sub: the subzone's name as the client gave
    -- it (no API names it later); c, x, y: continent and world yards
    fields = { map = "number?", sub = "string?", c = "number?", x = "number?", y = "number?" },
    render = function(data)
        local place = placeOf(data)
        return place and L.DEATH_IN:format(place) or L.DEATH
    end,
    markers = function(data)
        if not data.c then return nil end
        return { { c = data.c, x = data.x, y = data.y, icon = SKULL, title = L.DEATH_TOOLTIP } }
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
    local data = { map = Compat.GetPlayerMapID(), sub = Compat.GetSubZoneName() }
    local continent, x, y = Compat.GetPlayerWorldPosition()
    if continent then
        data.c, data.x, data.y = continent, math.floor(x + 0.5), math.floor(y + 0.5)
    end
    Store:Append("DEATH", data)
end
