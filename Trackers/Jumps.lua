local _, ns = ...
local L, Compat, Store, Time, Trace, YearCards = ns.L, ns.Compat, ns.Store, ns.Time, ns.Trace, ns.YearCards

-- Jumps (docs/ARCHITECTURE.md §6.23): every press of the Jump key that lifts the character off the
-- ground, summed per day as the counter jumps = { count }. No event says the player jumped: the Jump
-- key binding calls JumpOrAscendStart, which is hooked once. A press only adds to a number here;
-- the number is written about once a minute, at midnight, at logout and when the tracker is
-- switched off.
local ICON = "Interface\\Icons\\INV_Gizmo_RocketBoot_01"
local FLUSH_INTERVAL = 60

-- Whether `count` jumps on `day` beat the best day so far: more jumps, or the earlier day on a tie.
local function beats(count, day, best)
    return not best or count > best.count or (count == best.count and day < best.day)
end

-- No day-page line: jumps are shown only in Your Year. The month rollup keeps the month's best day
-- (the most jumps) as jumpsBest = { count, day }, so a rebuild restores it.
ns.RecordTypes:RegisterCounter("jumps", {
    rollup = function(rollup, _, dayCount, dayKey)
        if beats(dayCount, dayKey, rollup.jumpsBest) then rollup.jumpsBest = { count = dayCount, day = dayKey } end
    end,
    merge = function(target, source)
        local other = source.jumpsBest
        if other and beats(other.count, other.day, target.jumpsBest) then
            target.jumpsBest = { count = other.count, day = other.day }
        end
    end,
})

-- The days of the year with play time.
local function daysPlayed(year)
    local days = 0
    for _ in pairs(Store:GetPlayByDay(Time.DayStart(year * 10000 + 101), Time.DayEnd(year * 10000 + 1231))) do
        days = days + 1
    end
    return days
end

-- "1,204 jumps" (big), the best day and the average per day played, left out under one.
-- After Footsteps.
YearCards:Register({
    id = "jumps",
    order = 92,
    build = function(summary)
        local total = (summary.rollup.counters.jumps or {}).count or 0
        if total <= 0 then return nil end
        local card = {
            title = L.CARD_JUMPS, icon = ICON,
            big = YearCards.Number(total), caption = YearCards.Pattern("CARD_JUMPS_CAPTION", total),
            lines = {},
        }
        local best = summary.rollup.jumpsBest
        if best then
            card.lines[1] = L.CARD_JUMPS_BEST_DAY:format(Time.FormatLongDay(best.day),
                YearCards.Plural("CARD_JUMPS_COUNT", best.count))
        end
        local days = daysPlayed(summary.year)
        local average = days > 0 and math.floor(total / days + 0.5) or 0
        if average >= 1 then
            card.lines[#card.lines + 1] = L.CARD_JUMPS_AVERAGE:format(YearCards.Plural("CARD_JUMPS_COUNT", average))
        end
        return card
    end,
})

local Jumps = ns.Trackers:New("Jumps", { label = L.TRACKER_JUMPS, tooltip = L.TRACKER_JUMPS_TIP })

-- Presses since the last flush: the jumps, and the presses skipped by reason.
local counted, falling, swimming, flying, taxi, vehicle = 0, 0, 0, 0, 0, 0

function Jumps:OnEnable()
    self:HookJump()
    self:RegisterEvent("PLAYER_LOGOUT")
    self:Arm()
end

-- What was pressed until now is written; the presses while off are dropped.
function Jumps:OnDisable()
    self:Flush("disable")
end

-- Fires for /reload too.
function Jumps:PLAYER_LOGOUT()
    self:Flush("PLAYER_LOGOUT")
end

-- A post-hook can't be removed: it stays, and Dispatch drops the presses while the tracker is off.
function Jumps:HookJump()
    if self.hooked or type(hooksecurefunc) ~= "function" or type(JumpOrAscendStart) ~= "function" then return end
    self.hooked = true
    hooksecurefunc("JumpOrAscendStart", function()
        Jumps:Dispatch("JUMP")
    end)
end

-- A press is a jump unless the character is already in the air, in water, flying, on a flight path
-- or in a vehicle, read in that order at the press. A secret or missing state reads as not so. Runs
-- on every press: it only adds to a number.
function Jumps:JUMP()
    if Compat.IsFalling() then
        falling = falling + 1
    elseif Compat.IsSwimming() then
        swimming = swimming + 1
    elseif Compat.IsFlying() then
        flying = flying + 1
    elseif Compat.IsOnTaxi() then
        taxi = taxi + 1
    elseif Compat.IsInVehicle() then
        vehicle = vehicle + 1
    else
        counted = counted + 1
    end
end

-- Starts a flush window: a minute, or up to midnight when that comes first, so a window lies
-- within one day and its jumps are written on that day.
function Jumps:Arm()
    local now = Time.Now()
    self.since = now
    local untilMidnight = Time.DayEnd(Time.DayKey(now)) + 1 - now
    self.window = untilMidnight <= FLUSH_INTERVAL and "midnight" or "minute"
    self:Debounce("flush", math.min(FLUSH_INTERVAL, untilMidnight), self.Tick)
end

function Jumps:Tick()
    self:Flush(self.window)
    self:Arm()
end

-- Writes the jumps of the window on its day; nothing when there were none. In developer mode a
-- window with a press leaves one trace line (§6.11): the jumps and the presses skipped by reason.
function Jumps:Flush(event)
    local skipped = falling + swimming + flying + taxi + vehicle
    if counted + skipped > 0 then
        local outcome = "none counted"
        if counted > 0 then
            outcome = Store:Count("jumps", "count", counted, self.since) and "written" or "read-only"
        end
        Trace:Add(self.id, event, outcome, "counted", counted, "skipped", skipped, falling > 0 and "falling", falling,
            swimming > 0 and "swimming", swimming, flying > 0 and "flying", flying, taxi > 0 and "taxi", taxi,
            vehicle > 0 and "vehicle", vehicle)
    end
    counted, falling, swimming, flying, taxi, vehicle = 0, 0, 0, 0, 0, 0
end
