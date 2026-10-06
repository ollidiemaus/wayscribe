local _, ns = ...
local L, Compat, Store, Time, YearCards = ns.L, ns.Compat, ns.Store, ns.Time, ns.YearCards

-- Play sessions drive the login recap (0.2) and play-time stats. A /reload continues the same
-- session; only a real login starts a new one (docs/ARCHITECTURE.md §6.1).
local Session = ns.Trackers:New("Session", { internal = true })

local ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"

-- The finale of Your Year: "212 h 5 min in 320 sessions on 180 days", the most active month and
-- day, and the longest session. Play time comes from the months' sessions, not from day records.
YearCards:Register({
    id = "time",
    order = 100,
    build = function(summary)
        if summary.playSeconds <= 0 then return nil end
        local card = {
            title = L.CARD_TIME, icon = ICON,
            big = Time.FormatDuration(summary.playSeconds),
            caption = L.CARD_TIME_CAPTION:format(YearCards.Plural("CARD_SESSIONS", summary.sessions),
                YearCards.Plural("CARD_DAYS", summary.activeDays)),
            lines = {},
        }
        local seconds = {}
        for month, monthSummary in pairs(summary.byMonth) do
            seconds[month] = monthSummary.playSeconds
        end
        local month, monthSeconds = YearCards.Top(seconds)
        if summary.months > 1 and monthSeconds > 0 then
            card.lines[#card.lines + 1] = L.CARD_TIME_MONTH:format(L.MONTHS[month], Time.FormatDuration(monthSeconds))
        end
        local year = summary.year
        local played, longest = Store:GetPlayByDay(Time.DayStart(year * 10000 + 101), Time.DayEnd(year * 10000 + 1231))
        local day, daySeconds = YearCards.Top(played)
        if day then
            card.lines[#card.lines + 1] = L.CARD_TIME_DAY:format(Time.FormatLongDay(day), Time.FormatDuration(daySeconds))
        end
        if longest > 0 then
            card.lines[#card.lines + 1] = L.CARD_TIME_LONGEST:format(Time.FormatDuration(longest))
        end
        return card
    end,
})

function Session:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_LOGOUT")
end

function Session:PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
    if Compat.Safe(isInitialLogin) == true then
        Store:StartSession(Time.Now())
    elseif Compat.Safe(isReloadingUi) == true then
        if not Store:ResumeSession() then
            Store:StartSession(Time.Now())
        end
    end
    -- Other loading screens (portals, instances) don't touch the session.
end

-- Fires for /reload too; a reload re-opens the session on the next PLAYER_ENTERING_WORLD.
function Session:PLAYER_LOGOUT()
    Store:EndSession(Time.Now())
end
