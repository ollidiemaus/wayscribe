local _, ns = ...
local L, Compat, Store, Paths, Time, Geometry, Codec = ns.L, ns.Compat, ns.Store, ns.Paths, ns.Time, ns.Geometry, ns.Codec
local StaticData = ns.StaticData

-- Footsteps (docs/ARCHITECTURE.md §6.8): where the character walked, rode and flew. A ticker samples
-- the world position once a second while outdoors; a point is kept only after moving MIN_STEP, so
-- standing still writes nothing. The growing trail lives in memory and is stored when it ends:
-- simplified (Douglas-Peucker), rounded to whole yards and packed into one string. Its distance
-- goes into the day's "travel" counter, so the journal and Wrapped never have to decode trails.
--
-- A trail ends on a loading screen, a continent change, a teleport, taxi start or end, death, a
-- minute without moving, midnight, MAX_POINTS, and logout. The next trail starts where the last
-- one stopped if the player is still there, so pauses leave no gaps on the map.
--
-- Journeys by spell (a hearthstone, a mage's teleport) get a TELEPORT entry: the cast is noted,
-- and when a trail next starts far from where it was cast, the entry records both places, which
-- the map marks with the spell's icon.
local SAMPLE_INTERVAL = 1
local MIN_STEP = 8      -- yards between kept points
local IDLE = 60         -- seconds without moving that end a trail
local TOLERANCE = 3     -- yards a stored trail may stray from the recorded one
local MAX_SPEED = 100   -- yards per second; anything faster is a teleport, not a journey
local MAX_POINTS = 1800 -- recorded points per trail (30 minutes at a gallop): bounds the work at the end
local JOIN = 30         -- a new trail starting this close to where the last one ended continues it
local TRAVEL_WINDOW = 60 -- seconds from a travel spell's cast to the arrival (loading screens included)
local TRAVEL_SETTLE = 2  -- seconds after arriving, when the subzone's name has caught up
local HEARTHSTONE_ICON = "Interface\\Icons\\INV_Misc_Rune_01"

-- Short distances in the language's small unit, long ones in its large unit with one decimal.
local function formatDistance(yards)
    if yards < L.DISTANCE_LARGE_YARDS then
        return L.DISTANCE_SMALL:format(math.floor(yards * L.DISTANCE_SMALL_FACTOR + 0.5))
    end
    local large = string.format("%.1f", yards / L.DISTANCE_LARGE_YARDS):gsub("%.", L.DECIMAL_POINT)
    return L.DISTANCE_LARGE:format(large)
end

-- "ground" and "flight" -> yards: "Traveled 2.4 miles · Flight paths: 5.1 miles"
ns.RecordTypes:RegisterCounter("travel", {
    category = "travel",
    order = 50,
    render = function(bucket)
        local parts = {}
        if bucket.ground then
            parts[#parts + 1] = L.TRAVEL_GROUND:format(formatDistance(bucket.ground))
        end
        if bucket.flight then
            parts[#parts + 1] = L.TRAVEL_FLIGHT:format(formatDistance(bucket.flight))
        end
        if #parts == 0 then return nil end
        return table.concat(parts, " · ")
    end,
})

local function round(value)
    return math.floor(value + 0.5)
end

local function spellName(spellID)
    return Compat.GetSpellName(spellID) or L.UNKNOWN_SPELL:format(spellID)
end

-- The arrival: the subzone ("Bloodhoof"), else the zone.
local function destination(data)
    return data.sub or (data.map and Compat.GetMapName(data.map))
end

ns.RecordTypes:Register("TELEPORT", {
    version = 1,
    category = "travel",
    -- spell; arrival: map, sub (as the client named it), c, x, y; departure: fc, fx, fy
    fields = {
        spell = "number", map = "number?", sub = "string?", c = "number?", x = "number?", y = "number?",
        fc = "number?", fx = "number?", fy = "number?",
    },
    render = function(data)
        local place = destination(data)
        local spell = spellName(data.spell)
        return place and L.TELEPORT_TO:format(spell, place) or L.TELEPORT_USED:format(spell)
    end,
    -- The spell's icon where the journey left and where it arrived.
    markers = function(data, record)
        local icon = Compat.GetSpellIcon(data.spell) or HEARTHSTONE_ICON
        local list = {}
        if data.fc then
            list[#list + 1] = { c = data.fc, x = data.fx, y = data.fy, icon = icon,
                title = ns.RecordTypes:Render(record) }
        end
        if data.c then
            list[#list + 1] = { c = data.c, x = data.x, y = data.y, icon = icon,
                title = L.TELEPORT_ARRIVED:format(spellName(data.spell)) }
        end
        return list
    end,
})

local Footsteps = ns.Trackers:New("Footsteps", { label = L.TRACKER_FOOTSTEPS, tooltip = L.TRACKER_FOOTSTEPS_TIP })

-- Travel spells by ID and, for other ranks and versions, by name in the client's language.
function Footsteps:BuildTravelSpells()
    self.travelById, self.travelByName = {}, {}
    for _, spellID in ipairs(StaticData.TravelSpells) do
        self.travelById[spellID] = true
        local name = Compat.GetSpellName(spellID)
        if name then
            self.travelByName[name] = true
        end
    end
end

function Footsteps:OnEnable()
    -- seen: the last sampled position, kept point or not; travel: a travel spell's cast on its way.
    self.live, self.anchor, self.seen, self.travel = nil, nil, {}, nil
    self:BuildTravelSpells()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    -- Lifecycle sends LOGOUT before it updates the canary, so the last trail is counted there.
    ns.Bus:On("LOGOUT", self, self.OnLogout)
    self:Update()
end

-- Turning Footsteps off keeps what was recorded so far.
function Footsteps:OnDisable()
    ns.Bus:Off("LOGOUT", self)
    self:StopTicker()
    self:Close()
end

function Footsteps:OnLogout()
    if self.enabled then
        self:Close()
    end
end

-- A travel spell's cast notes where it started; a secret spell ID just isn't recognized.
function Footsteps:UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
    spellID = Compat.Safe(spellID, "number")
    if not spellID then return end
    local known = self.travelById[spellID]
    if not known then
        local name = Compat.GetSpellName(spellID)
        known = name ~= nil and self.travelByName[name] == true
    end
    if not known then return end
    local continent, x, y = Compat.GetPlayerWorldPosition()
    self.travel = { spell = spellID, t = Time.Now(), c = continent, x = x, y = y }
end

-- A loading screen may have moved the player anywhere.
function Footsteps:PLAYER_ENTERING_WORLD()
    self:Close()
    self:Update()
end

function Footsteps:ZONE_CHANGED_NEW_AREA()
    self:Update()
end

-- The ticker only runs outdoors (instances hide the position anyway) and while trails can be saved.
function Footsteps:Update()
    local _, instanceType = Compat.GetInstance()
    if (instanceType == nil or instanceType == "none") and Paths:IsWritable() then
        self:StartTicker()
    else
        self:StopTicker()
        self:Close()
    end
end

function Footsteps:StartTicker()
    if self.ticker then return end
    self.ticker = C_Timer.NewTicker(SAMPLE_INTERVAL, function()
        if not self.enabled then return end
        local ok, err = pcall(self.Sample, self)
        if not ok then
            self:OnError("sample", err)
        end
    end)
end

function Footsteps:StopTicker()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function Footsteps:Sample()
    local now = Time.Now()
    local flying = Compat.IsOnTaxi()
    if Compat.IsDeadOrGhost() or (flying and not ns.Options:Get("footstepsFlights")) then
        return self:Close()
    end
    local continent, x, y = Compat.GetPlayerWorldPosition()
    local live = self.live
    if not continent then
        -- Hidden for a moment (combat?): keep the trail unless the pause gets long.
        if live and now - live.moved > IDLE then self:Close() end
        return
    end
    -- A teleport is measured against the last sample, not the last kept point: a hearthstone is
    -- cast standing still, and 700 yards after a 10 s cast would look like a walk (build 70235).
    local seen = self.seen
    local jumped = seen.c == continent and seen.t
        and Geometry.Distance(seen.x, seen.y, x, y) > MAX_SPEED * math.max(1, now - seen.t)
    seen.c, seen.x, seen.y, seen.t = continent, x, y, now
    if live and (jumped or live.c ~= continent or live.f ~= flying or now > live.dayEnd or live.n >= MAX_POINTS) then
        self:Close()
        live = nil
    end
    if live then
        local step = Geometry.Distance(live.x, live.y, x, y)
        if step >= MIN_STEP then
            self:AddPoint(live, x, y, step, now)
            return
        else
            if now - live.moved > IDLE then self:Close() end
            return
        end
    end
    self:Start(continent, x, y, flying, now)
end

local function append(live, x, y)
    local points = live.points
    points[#points + 1] = x
    points[#points + 1] = y
    live.n = live.n + 1
    live.x, live.y = x, y
end

-- After a travel spell, a trail that starts far from where it was cast is the arrival.
function Footsteps:CheckArrival(continent, x, y, now)
    local travel = self.travel
    if not travel then return end
    if now - travel.t > TRAVEL_WINDOW then
        self.travel = nil
        return
    end
    if travel.c == continent and Geometry.Distance(travel.x, travel.y, x, y) <= JOIN then return end
    self.travel = nil
    local data = { spell = travel.spell, c = continent, x = round(x), y = round(y) }
    if travel.c then
        data.fc, data.fx, data.fy = travel.c, round(travel.x), round(travel.y)
    end
    -- The subzone's name changes a moment after arriving; the entry is dated at the arrival.
    self:After(TRAVEL_SETTLE, function()
        data.map, data.sub = Compat.GetPlayerMapID(), Compat.GetSubZoneName()
        Store:Append("TELEPORT", data, { ts = now })
    end)
end

function Footsteps:Start(continent, x, y, flying, now)
    self:CheckArrival(continent, x, y, now)
    local day = Time.DayKey(now)
    local live = {
        c = continent, f = flying, t = now, moved = now, day = day, dayEnd = Time.DayEnd(day),
        points = {}, n = 0, length = 0,
    }
    local anchor = self.anchor
    self.anchor = nil
    if anchor and anchor.c == continent then
        local gap = Geometry.Distance(anchor.x, anchor.y, x, y)
        if gap <= JOIN then
            append(live, anchor.x, anchor.y)
            live.length = gap
        end
    end
    append(live, x, y)
    self.live = live
    Paths:SetLive(live)
end

function Footsteps:AddPoint(live, x, y, step, now)
    append(live, x, y)
    live.length = live.length + step
    live.moved = now
    Paths:LiveMoved()
end

-- Stores the live trail, if it went anywhere, and remembers where it ended.
function Footsteps:Close()
    local live = self.live
    if not live then return end
    self.live = nil
    Paths:SetLive(nil)
    self.anchor = { c = live.c, x = live.x, y = live.y }
    -- A trail that went nowhere (a pause right after a reload) isn't worth storing.
    if live.n < 2 or live.length < MIN_STEP then return end
    local points = Geometry.Quantize(Geometry.Simplify(live.points, TOLERANCE))
    if #points < 4 then return end
    local stored = Paths:AddSegment({
        c = live.c, t = live.t, d = live.moved - live.t, f = live.f or nil, p = Codec.EncodePath(points),
    })
    if stored then
        Store:Count("travel", live.f and "flight" or "ground", math.floor(live.length + 0.5), live.t)
    end
end
