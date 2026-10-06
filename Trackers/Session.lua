local _, ns = ...
local Compat, Store, Time = ns.Compat, ns.Store, ns.Time

-- Play sessions drive the login recap (0.2) and play-time stats. A /reload continues the same
-- session; only a real login starts a new one (docs/ARCHITECTURE.md §6.1).
local Session = ns.Trackers:New("Session", { internal = true })

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
