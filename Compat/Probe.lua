local _, ns = ...
local Compat = ns.Compat

-- /ws probe: what this client actually offers. The report is printed and also kept in
-- WayscribeDB.probe so it can be copied out of the SavedVariables file (docs/ARCHITECTURE.md §12).
local Probe = {}
ns.Probe = Probe

-- COMBAT_LOG_EVENT_UNFILTERED is deliberately missing: registering it on Forever pops a
-- protected-action warning.
local EVENTS = {
    "BOSS_KILL", "CHAT_MSG_SKILL", "ENCOUNTER_END", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT",
    "LFG_COMPLETION_REWARD", "LOOT_CLOSED", "LOOT_READY", "LOOT_SLOT_CLEARED", "PLAYER_DEAD",
    "PLAYER_LEVEL_UP", "QUEST_TURNED_IN", "SCENARIO_COMPLETED", "SKILL_LINES_CHANGED",
    "TRADE_SKILL_LIST_UPDATE", "UNIT_SPELLCAST_SUCCEEDED", "ZONE_CHANGED_NEW_AREA",
}

local LIBRARIES = { "LibStub", "CallbackHandler-1.0", "LibDataBroker-1.1", "LibDBIcon-1.0" }

local function describe(value)
    if value == nil then return "nil" end
    if type(value) == "number" then
        return value % 1 == 0 and string.format("%d", value) or string.format("%.4f", value)
    end
    return tostring(value)
end

local function readMapPosition(lines, mapID)
    local position = Compat.Call(C_Map.GetPlayerMapPosition, mapID, "player")
    if type(position) ~= "table" then
        lines[#lines + 1] = "map.position = " .. describe(position)
        return
    end
    local x, y = Compat.Safe(position.x, "number"), Compat.Safe(position.y, "number")
    lines[#lines + 1] = "map.position = " .. (x and y and string.format("%.4f, %.4f", x, y) or "secret")
    if Compat.has.mapWorldPos then
        local continentID, world = Compat.Call(C_Map.GetWorldPosFromMapPos, mapID, position)
        local wx = type(world) == "table" and Compat.Safe(world.x, "number")
        local wy = type(world) == "table" and Compat.Safe(world.y, "number")
        lines[#lines + 1] = "map.world = continent " .. describe(continentID)
            .. (wx and wy and string.format(" at %.1f, %.1f", wx, wy) or " (no position)")
    end
end

-- What 0.2's trackers rely on: profession values, gather spell names in this client's language.
local function addTrackerInputs(add)
    for skillLine, info in pairs(Compat.GetProfessionSnapshot() or {}) do
        add("profession." .. skillLine, describe(info.name) .. " " .. describe(info.rank) .. "/" .. describe(info.max)
            .. " (skill line name: " .. describe(Compat.GetSkillLineName(skillLine)) .. ")")
    end
    -- StaticData is plain tables with no dependencies, so the probe may read it.
    for _, kind in ipairs({ "mining", "herbalism", "skinning" }) do
        for _, spellID in ipairs(ns.StaticData.GatherSpells[kind]) do
            add("spell." .. kind .. "." .. spellID, Compat.GetSpellName(spellID))
        end
    end
    -- Library minor versions, nil when missing (an unpackaged copy has no Libs folder).
    local libStub = LibStub
    for _, name in ipairs(LIBRARIES) do
        local minor
        if name == "LibStub" then
            minor = libStub and libStub.minor
        elseif libStub then
            minor = select(2, libStub(name, true))
        end
        add("lib." .. name, minor)
    end
end

local function collect()
    local lines = {}
    local function add(key, value)
        lines[#lines + 1] = key .. " = " .. describe(value)
    end

    add("addon", ns.version)
    add("client", Compat.clientVersion .. " (build " .. Compat.clientBuild .. ")")
    add("interface", Compat.interface)
    add("isForever", Compat.isForever)
    add("WOW_PROJECT_ID", Compat.Safe(WOW_PROJECT_ID))

    local keys = {}
    for key in pairs(Compat.has) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        add("has." .. key, Compat.has[key])
    end
    for _, event in ipairs(EVENTS) do
        add("event." .. event, Compat.EventExists(event))
    end

    local mapID = Compat.GetPlayerMapID()
    add("map.best", mapID)
    if mapID and Compat.has.mapPlayerPosition then
        readMapPosition(lines, mapID)
    end
    if Compat.has.unitPosition then
        -- Printed in return order. The first value matches C_Map's world vector .x (verified on
        -- build 70235), even though Blizzard's documentation calls it posY.
        local first, second, _, instanceID = Compat.Call(UnitPosition, "player")
        lines[#lines + 1] = "unitPosition = " .. (first and second
            and string.format("%.1f, %.1f (instance %s)", first, second, describe(instanceID)) or "nil")
    end

    local instanceName, instanceType, difficultyID, _, _, _, _, instanceID = Compat.Call(GetInstanceInfo)
    lines[#lines + 1] = "instance = " .. describe(instanceName) .. " / " .. describe(instanceType)
        .. " / difficulty " .. describe(difficultyID) .. " / id " .. describe(instanceID)

    if Compat.has.professions == "modern" then
        -- prof1, prof2, archaeology, fishing, cooking (nil where not learned)
        local slots = { Compat.Call(GetProfessions) }
        local parts = {}
        for i = 1, 5 do parts[i] = describe(slots[i]) end
        add("professions", table.concat(parts, ", "))
    end
    add("level", Compat.GetPlayerLevel())
    add("secret.UnitLevel", Compat.IsSecret(UnitLevel and UnitLevel("player")))
    addTrackerInputs(add)
    return lines
end

function Probe:Run()
    Compat:Detect()
    local ok, lines = pcall(collect)
    if not ok then
        ns.Log:Error("probe", lines)
        lines = { "probe failed: " .. ns.Log.ToText(lines) }
    end
    if ns.accountDB then
        ns.accountDB.probe = { ts = time(), lines = lines }
    end
    for _, line in ipairs(lines) do
        ns.Print(line)
    end
    return lines
end
