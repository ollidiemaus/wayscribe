local _, ns = ...

-- The only place that knows how this client exposes things (docs/ARCHITECTURE.md §5).
-- Code elsewhere asks Compat.has.X; it never branches on the game flavor.
local Compat = { has = {} }
ns.Compat = Compat

local function isSecret(value)
    local check = issecretvalue
    return check ~= nil and check(value) == true
end
Compat.IsSecret = isSecret

-- Every game value passes through here before it is compared, concatenated or stored:
-- Forever has Midnight-style secret values, and touching one raises an error.
function Compat.Safe(value, expectedType)
    if value == nil or isSecret(value) then return nil end
    if expectedType and type(value) ~= expectedType then return nil end
    return value
end

local function sanitizeAll(...)
    if select("#", ...) == 0 then return end
    return Compat.Safe((...)), sanitizeAll(select(2, ...))
end

local function afterCall(ok, ...)
    if not ok then return nil end
    return sanitizeAll(...)
end

-- pcall that also drops secret return values; returns nil if fn is missing or errors.
function Compat.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return afterCall(pcall(fn, ...))
end

do
    local version, build, _, interface = Compat.Call(GetBuildInfo)
    Compat.clientVersion = type(version) == "string" and version or "?"
    Compat.clientBuild = type(build) == "string" and build or "?"
    Compat.interface = type(interface) == "number" and interface or 0
    -- Forever reports WOW_PROJECT_MAINLINE, so only the interface number tells it apart.
    Compat.isForever = Compat.interface >= 16000 and Compat.interface < 20000
end

function Compat.EventExists(event)
    local utils = C_EventUtils
    if utils and utils.IsEventValid then
        return Compat.Call(utils.IsEventValid, event) == true
    end
    -- Older engines: probe with a scratch frame (the Mainline engine errors on unknown events).
    local frame = Compat.scratchFrame
    if not frame then
        frame = CreateFrame("Frame")
        Compat.scratchFrame = frame
    end
    local ok = pcall(frame.RegisterEvent, frame, event)
    if ok then
        frame:UnregisterEvent(event)
    end
    return ok
end

-- Resolved at PLAYER_LOGIN; the full list is printed by /ws probe.
function Compat:Detect()
    local has = self.has
    has.secretValues = issecretvalue ~= nil
    has.encounterEvents = self.EventExists("ENCOUNTER_END")
    has.bossKillEvent = self.EventExists("BOSS_KILL")
    has.questLines = C_QuestLine ~= nil and C_QuestLine.GetQuestLineInfo ~= nil
    has.unitPosition = type(UnitPosition) == "function"
    has.mapPlayerPosition = C_Map ~= nil and C_Map.GetPlayerMapPosition ~= nil
    has.mapWorldPos = C_Map ~= nil and C_Map.GetWorldPosFromMapPos ~= nil and C_Map.GetMapPosFromWorldPos ~= nil
    if GetProfessions and GetProfessionInfo then
        has.professions = "modern"
    elseif GetNumSkillLines and GetSkillLineInfo then
        has.professions = "legacy"
    else
        has.professions = false
    end
    has.settingsAPI = Settings ~= nil and Settings.RegisterVerticalLayoutCategory ~= nil
    has.lootSourceInfo = type(GetLootSourceInfo) == "function"
    has.scrollBox = type(CreateScrollBoxListLinearView) == "function" and ScrollUtil ~= nil
    has.addonCompartment = AddonCompartmentFrame ~= nil
end

function Compat.GetPlayerIdentity()
    local guid = Compat.Call(UnitGUID, "player")
    local name, realm = Compat.Call(UnitFullName, "player")
    if type(realm) ~= "string" or realm == "" then
        realm = Compat.Call(GetRealmName)
    end
    local _, classFile = Compat.Call(UnitClass, "player")
    return {
        guid = type(guid) == "string" and guid ~= "" and guid or nil,
        name = type(name) == "string" and name or nil,
        realm = type(realm) == "string" and realm or nil,
        class = type(classFile) == "string" and classFile or nil,
    }
end

function Compat.GetPlayerLevel()
    local level = Compat.Call(UnitLevel, "player")
    return type(level) == "number" and level > 0 and level or nil
end

function Compat.GetPlayerMapID()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local mapID = Compat.Call(C_Map.GetBestMapForUnit, "player")
    return type(mapID) == "number" and mapID or nil
end
