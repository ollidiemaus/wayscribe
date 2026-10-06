local _, ns = ...
local L, Compat, Store, Time, YearCards = ns.L, ns.Compat, ns.Store, ns.Time, ns.YearCards

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
    -- Deaths per map, for the most dangerous place of the year (Your Year).
    rollup = function(rollup, data)
        if data.map then
            rollup.deathMaps = rollup.deathMaps or {}
            rollup.deathMaps[data.map] = (rollup.deathMaps[data.map] or 0) + 1
        end
    end,
    merge = function(target, source)
        if not source.deathMaps then return end
        target.deathMaps = target.deathMaps or {}
        for map, count in pairs(source.deathMaps) do
            target.deathMaps[map] = (target.deathMaps[map] or 0) + count
        end
    end,
    render = function(data)
        local place = placeOf(data)
        return place and L.DEATH_IN:format(place) or L.DEATH
    end,
    markers = function(data)
        if not data.c then return nil end
        return { { c = data.c, x = data.x, y = data.y, icon = SKULL, title = L.DEATH_TOOLTIP } }
    end,
})

-- "14 deaths. Most dangerous place: The Barrens (5 deaths)."
YearCards:Register({
    id = "deaths",
    order = 50,
    build = function(summary)
        local deaths = summary.rollup.records.DEATH or 0
        if deaths == 0 then return nil end
        local card = {
            title = L.CARD_DEATHS, icon = SKULL,
            big = YearCards.Number(deaths), caption = YearCards.Plural("CARD_DEATHS_COUNT", deaths),
            lines = {},
        }
        local map, count = YearCards.Top(summary.rollup.deathMaps)
        local zone = map and count > 1 and Compat.GetMapName(map)
        if zone then
            card.lines[1] = L.CARD_DEATHS_PLACE:format(zone, YearCards.Plural("CARD_DEATHS_TIMES", count))
        end
        return card
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
