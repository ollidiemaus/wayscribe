local addonName, ns = ...

-- Wires the layers together in the order docs/ARCHITECTURE.md §3.1 describes.
local Lifecycle = ns.NewModule("lifecycle")
Lifecycle.enabled = true
ns.Lifecycle = Lifecycle

Lifecycle:RegisterEvent("ADDON_LOADED")
Lifecycle:RegisterEvent("PLAYER_LOGIN")
Lifecycle:RegisterEvent("PLAYER_LOGOUT")

function Lifecycle:ADDON_LOADED(name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    ns.Schema:LoadAccount()
    ns.Schema:LoadCharacter()
    ns.Schema:LoadPaths()
end

function Lifecycle:PLAYER_LOGIN()
    ns.Compat:Detect()
    ns.Schema:VerifyIdentity()
    ns.Schema:VerifyPaths()
    ns.Trackers:EnableAll()
    ns.Bus:Fire("READY")
end

-- Keep this tiny: it is the last chance to change data before the client saves it. LOGOUT comes
-- first, so what it writes (the last Footsteps trail) is counted in the canary.
function Lifecycle:PLAYER_LOGOUT()
    ns.Bus:Fire("LOGOUT")
    ns.Schema:TouchCanary()
end
