local addonName, ns = ...

ns.name = addonName
ns.version = "dev"
do
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if getMetadata then
        local ok, version = pcall(getMetadata, addonName, "Version")
        if ok and type(version) == "string" and version ~= "" then
            ns.version = version
        end
    end
end

-- Set by Schema when the journal must not be written (reason text for the player), see
-- docs/ARCHITECTURE.md §4.6. Everything that writes checks Store:IsWritable() instead of this.
ns.safeMode = nil
ns.devMode = false

local PREFIX = "|cffd4a017Wayscribe|r: "

function ns.Print(message)
    local text = PREFIX .. tostring(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    else
        print(text)
    end
end

-- The first reason wins: a second problem found later must not hide the original one.
function ns.SetSafeMode(reason)
    if ns.safeMode then return end
    ns.safeMode = reason
    ns.Print(ns.L.SAFE_MODE_BANNER:format(reason))
    ns.Bus:Fire("SAFE_MODE", reason)
end
