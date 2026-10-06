local _, ns = ...
local L, Compat, Store, Paths, Time, Geometry, Codec = ns.L, ns.Compat, ns.Store, ns.Paths, ns.Time, ns.Geometry, ns.Codec

-- Footsteps (docs/ARCHITECTURE.md §6.8): where the character walked, rode and flew. A ticker samples
-- the world position once a second while outdoors; a point is kept only after moving MIN_STEP, so
-- standing still writes nothing. The growing trail lives in memory and is stored when it ends:
-- simplified (Douglas-Peucker), rounded to whole yards and packed into one string. Its distance
-- goes into the day's "travel" counter, so the journal and Wrapped never have to decode trails.
--
-- A trail ends on a loading screen, a continent change, a teleport, taxi start or end, death, a
-- minute without moving, midnight, MAX_POINTS, and logout. The next trail starts where the last
-- one stopped if the player is still there, so pauses leave no gaps on the map.
local SAMPLE_INTERVAL = 1
local MIN_STEP = 8      -- yards between kept points
local IDLE = 60         -- seconds without moving that end a trail
local TOLERANCE = 3     -- yards a stored trail may stray from the recorded one
local MAX_SPEED = 100   -- yards per second; anything faster is a teleport, not a journey
local MAX_POINTS = 1800 -- recorded points per trail (30 minutes at a gallop): bounds the work at the end
local JOIN = 30         -- a new trail starting this close to where the last one ended continues it

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

local Footsteps = ns.Trackers:New("Footsteps", { label = L.TRACKER_FOOTSTEPS, tooltip = L.TRACKER_FOOTSTEPS_TIP })

function Footsteps:OnEnable()
    self.live, self.anchor = nil, nil
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
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
    if live and (live.c ~= continent or live.f ~= flying or now > live.dayEnd or live.n >= MAX_POINTS) then
        self:Close()
        live = nil
    end
    if live then
        local step = Geometry.Distance(live.x, live.y, x, y)
        if step > MAX_SPEED * math.max(1, now - live.moved) then
            self:Close() -- teleported
        elseif step >= MIN_STEP then
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

function Footsteps:Start(continent, x, y, flying, now)
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
    if live.n < 2 then return end
    local points = Geometry.Quantize(Geometry.Simplify(live.points, TOLERANCE))
    if #points < 4 then return end
    local stored = Paths:AddSegment({
        c = live.c, t = live.t, d = live.moved - live.t, f = live.f or nil, p = Codec.EncodePath(points),
    })
    if stored then
        Store:Count("travel", live.f and "flight" or "ground", math.floor(live.length + 0.5), live.t)
    end
end
