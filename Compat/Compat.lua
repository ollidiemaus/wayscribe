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
    -- Forever's WOW_PROJECT_ID was Mainline's in early beta builds and is 18 since build 70235, so
    -- only the interface number tells it apart.
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

-- Whether an XML template exists: true or false, or nil when the client can't tell.
function Compat.HasTemplate(name)
    local getInfo = C_XMLUtil and C_XMLUtil.GetTemplateInfo
    if not getInfo then return nil end
    return Compat.Call(getInfo, name) ~= nil
end

-- Whether a texture atlas exists (atlas names are checked against the client's own list).
function Compat.HasAtlas(name)
    local getInfo = C_Texture and C_Texture.GetAtlasInfo
    return getInfo ~= nil and Compat.Call(getInfo, name) ~= nil
end

-- Resolved at PLAYER_LOGIN; the full list is printed by /ws probe.
function Compat:Detect()
    local has = self.has
    has.secretValues = issecretvalue ~= nil
    has.encounterEvents = self.EventExists("ENCOUNTER_END")
    has.bossKillEvent = self.EventExists("BOSS_KILL")
    has.questLines = C_QuestLine ~= nil and C_QuestLine.GetQuestLineInfo ~= nil and C_QuestLine.GetQuestLineQuests ~= nil
    has.questTitles = C_QuestLog ~= nil and C_QuestLog.GetTitleForQuestID ~= nil
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
    has.scrollBox = type(CreateScrollBoxListLinearView) == "function" and type(CreateDataProvider) == "function"
        and ScrollUtil ~= nil and ScrollUtil.InitScrollBoxListWithScrollBar ~= nil
        and self.HasTemplate("WowScrollBoxList") ~= false and self.HasTemplate("MinimalScrollBar") ~= false
    -- The journal's native look (docs/ARCHITECTURE.md §7): the default UI's frame, scroll bar and
    -- filter menu. Each is only used when this client can confirm it exists.
    has.portraitFrame = self.HasTemplate("PortraitFrameTemplate") == true
    has.scrollFrameBar = has.scrollBox and ScrollUtil.InitScrollFrameWithScrollBar ~= nil
    has.filterDropdown = self.HasTemplate("WowStyle1FilterDropdownTemplate") == true
    has.addonCompartment = AddonCompartmentFrame ~= nil
    has.itemInfoInstant = C_Item ~= nil and C_Item.GetItemInfoInstant ~= nil
    has.spellNames = (C_Spell ~= nil and C_Spell.GetSpellName ~= nil) or type(GetSpellInfo) == "function"
    has.tradeSkillNames = C_TradeSkillUI ~= nil and C_TradeSkillUI.GetTradeSkillDisplayName ~= nil
    has.taxiState = type(UnitOnTaxi) == "function"
    has.worldMapCanvas = self.HasWorldMapCanvas()
    -- 0.5: the zone maps the coverage stat measures against, and the journal's tabs.
    has.mapChildren = has.mapWorldPos and C_Map.GetMapChildrenInfo ~= nil
    has.panelTabs = self.HasTemplate("PanelTabButtonTemplate") == true and type(PanelTemplates_SetNumTabs) == "function"
        and type(PanelTemplates_SetTab) == "function"
    -- Forever's characters have a first name and a surname, and the unit name functions return the
    -- surname where other clients return the realm. UnitName never returns the player's own realm,
    -- so a second value there is a surname.
    local _, surname = self.Call(UnitName, "player")
    has.surnames = type(surname) == "string" and surname ~= ""
end

-- The default world map with its data provider extension point (Footsteps, docs/ARCHITECTURE.md
-- §6.8). Asked again when Blizzard_WorldMap loads later than this addon.
function Compat.HasWorldMapCanvas()
    return type(WorldMapFrame) == "table" and type(WorldMapFrame.AddDataProvider) == "function"
        and type(MapCanvasDataProviderMixin) == "table" and type(CreateFromMixins) == "function"
        and Compat.has.mapWorldPos == true and type(CreateVector2D) == "function"
end

local function text(value)
    return type(value) == "string" and value ~= "" and value or nil
end

-- guid, name, realm (nil on the player's own realm) and class file of a unit; any may be nil.
-- With surnames, UnitFullName's second value is the surname: the name is "First Surname", and the
-- realm isn't known.
local function unitInfo(unit)
    local name, second = Compat.Call(UnitFullName, unit)
    local _, classFile = Compat.Call(UnitClass, unit)
    name, second = text(name), text(second)
    local realm = second
    if Compat.has.surnames then
        realm = nil
        if name and second then name = name .. " " .. second end
    end
    return { guid = text(Compat.Call(UnitGUID, unit)), name = name, realm = realm, class = text(classFile) }
end

function Compat.GetPlayerIdentity()
    local info = unitInfo("player")
    info.realm = info.realm or text(Compat.Call(GetRealmName))
    return info
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

------------------------------------------------------------------------------------------------
-- World positions (Footsteps). The world is in yards per continent (the Map.db2 instance:
-- 0 = Eastern Kingdoms, 1 = Kalimdor). x is UnitPosition's first value, which equals C_Map's
-- world vector .x (verified on build 70235): north is +x, west is +y.

-- Where a point of a map (u, v from 0 to 1) lies in the world: continentID, x, y; or nil.
function Compat.GetWorldPosFromMapPos(mapID, u, v)
    if not (Compat.has.mapWorldPos and type(CreateVector2D) == "function") then return nil end
    local continentID, world = Compat.Call(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(u, v))
    if type(continentID) ~= "number" or type(world) ~= "table" then return nil end
    local x, y = Compat.Safe(world.x, "number"), Compat.Safe(world.y, "number")
    if not (x and y) then return nil end
    return continentID, x, y
end

-- continentID, x, y of the player; nil inside instances or while the client hides it.
function Compat.GetPlayerWorldPosition()
    if Compat.has.unitPosition then
        local x, y, _, continentID = Compat.Call(UnitPosition, "player")
        if type(x) == "number" and type(y) == "number" and type(continentID) == "number" then
            return continentID, x, y
        end
        return nil
    end
    local mapID = Compat.GetPlayerMapID()
    if not (mapID and Compat.has.mapPlayerPosition) then return nil end
    local position = Compat.Call(C_Map.GetPlayerMapPosition, mapID, "player")
    if type(position) ~= "table" then return nil end
    local u, v = Compat.Safe(position.x, "number"), Compat.Safe(position.y, "number")
    if not (u and v) then return nil end
    return Compat.GetWorldPosFromMapPos(mapID, u, v)
end

local MAX_MAP_DEPTH = 5

-- The most detailed map showing a world position, or nil. C_Map.GetMapPosFromWorldPos answers
-- with the continent (1414 for a point in Mulgore on build 70235), so this walks down through
-- the maps at that point.
function Compat.GetMapAtWorldPos(continentID, x, y)
    if not (Compat.has.mapWorldPos and type(CreateVector2D) == "function") then return nil end
    local world = CreateVector2D(x, y)
    local mapID, position = Compat.Call(C_Map.GetMapPosFromWorldPos, continentID, world)
    if type(mapID) ~= "number" then return nil end
    for _ = 1, MAX_MAP_DEPTH do
        local u = type(position) == "table" and Compat.Safe(position.x, "number")
        local v = type(position) == "table" and Compat.Safe(position.y, "number")
        local info = u and v and Compat.Call(C_Map.GetMapInfoAtPosition, mapID, u, v)
        local child = type(info) == "table" and Compat.Safe(info.mapID, "number")
        if not child or child == mapID then break end
        local _, childPosition = Compat.Call(C_Map.GetMapPosFromWorldPos, continentID, world, child)
        mapID, position = child, childPosition
    end
    return mapID
end

-- The subzone the player is in ("Red Cloud Mesa"), in the client's language, or nil. No API turns
-- a subzone back into a name later, so callers keep the text (like boss names).
function Compat.GetSubZoneName()
    return text(Compat.Call(GetSubZoneText))
end

-- A map's name in the client's language (a zone, a dungeon), or nil.
function Compat.GetMapName(mapID)
    local info = C_Map and C_Map.GetMapInfo and Compat.Call(C_Map.GetMapInfo, mapID)
    return type(info) == "table" and text(Compat.Safe(info.name, "string")) or nil
end

function Compat.GetParentMap(mapID)
    local info = C_Map and C_Map.GetMapInfo and Compat.Call(C_Map.GetMapInfo, mapID)
    local parent = type(info) == "table" and Compat.Safe(info.parentMapID, "number")
    return parent and parent > 0 and parent or nil
end

local ZONE_MAP_TYPE = 3 -- Enum.UIMapType.Zone
local AZEROTH = 947      -- the top of Forever's maps (UiMap.db2 of build 70235)

-- The top of the player's chain of maps (the world), or nil before the player's map is known.
local function worldRoot()
    local root = Compat.GetPlayerMapID()
    for _ = 1, MAX_MAP_DEPTH do
        local parent = root and Compat.GetParentMap(root)
        if not parent then break end
        root = parent
    end
    return root
end

-- A point of the world on a map: u, v from 0 to 1 (outside that range: off the map); or nil.
function Compat.GetMapPosFromWorldPos(mapID, continentID, x, y)
    if not (Compat.has.mapWorldPos and type(CreateVector2D) == "function") then return nil end
    local _, position = Compat.Call(C_Map.GetMapPosFromWorldPos, continentID, CreateVector2D(x, y), mapID)
    local u = type(position) == "table" and Compat.Safe(position.x, "number")
    local v = type(position) == "table" and Compat.Safe(position.y, "number")
    if not (u and v) then return nil end
    return u, v
end

-- Zones first, then continents, then other maps with a place in the world (Enum.UIMapType); no
-- worlds and dungeons.
local NAME_PREFERENCE = { [3] = 1, [2] = 2, [6] = 3, [5] = 4 }

-- Every map of the player's world by its name in the client's language, lowercased:
-- { [name] = uiMapID } (the notes' /way lines, docs/ARCHITECTURE.md §4.9). nil without the API.
function Compat.GetMapNames()
    if not Compat.has.mapChildren then return nil end
    local children = Compat.Call(C_Map.GetMapChildrenInfo, worldRoot() or AZEROTH, nil, true)
    if type(children) ~= "table" or #children == 0 then
        children = Compat.Call(C_Map.GetMapChildrenInfo, AZEROTH, nil, true) -- the player stands on no map
    end
    if type(children) ~= "table" then return nil end
    local names, ranks = {}, {}
    for _, info in ipairs(children) do
        local mapID = type(info) == "table" and Compat.Safe(info.mapID, "number")
        local rank = mapID and NAME_PREFERENCE[Compat.Safe(info.mapType, "number")]
        local name = rank and (text(Compat.Safe(info.name, "string")) or Compat.GetMapName(mapID))
        if name then
            local key = name:lower()
            if not ranks[key] or rank < ranks[key] then
                names[key], ranks[key] = mapID, rank
            end
        end
    end
    return names
end

-- Every zone map of the world the player is in, as { map, c, minX, maxX, minY, maxY } in world
-- yards: what "% of Azeroth walked" is measured against (docs/ARCHITECTURE.md §6.8). The zones
-- are asked from the client, so zones Forever adds count too. nil without the API or before the
-- player's map is known.
function Compat.GetZoneRects()
    if not Compat.has.mapChildren then return nil end
    local root = worldRoot()
    if not root then return nil end
    local zoneType = type(Enum) == "table" and type(Enum.UIMapType) == "table" and Enum.UIMapType.Zone or ZONE_MAP_TYPE
    local children = Compat.Call(C_Map.GetMapChildrenInfo, root, zoneType, true)
    if type(children) ~= "table" then return nil end
    local rects = {}
    for _, info in ipairs(children) do
        local mapID = type(info) == "table" and Compat.Safe(info.mapID, "number")
        local c1, x1, y1 = Compat.GetWorldPosFromMapPos(mapID, 0, 0)
        local c2, x2, y2 = Compat.GetWorldPosFromMapPos(mapID, 1, 1)
        if mapID and c1 and c1 == c2 and x1 ~= x2 and y1 ~= y2 then
            rects[#rects + 1] = {
                map = mapID, c = c1,
                minX = math.min(x1, x2), maxX = math.max(x1, x2), minY = math.min(y1, y2), maxY = math.max(y1, y2),
            }
        end
    end
    return rects
end

function Compat.IsOnTaxi()
    return Compat.Call(UnitOnTaxi, "player") == true
end

function Compat.IsDeadOrGhost()
    return Compat.Call(UnitIsDeadOrGhost, "player") == true
end

------------------------------------------------------------------------------------------------
-- Instances, groups, professions, spells and items

-- instanceID (Map.db2 ID, also outdoors: 0 = Eastern Kingdoms, 1 = Kalimdor), instanceType
-- ("none", "party", "raid", ...), difficultyID, localized name.
function Compat.GetInstance()
    local name, instanceType, difficultyID, _, _, _, _, instanceID = Compat.Call(GetInstanceInfo)
    if type(instanceID) ~= "number" then return nil end
    return instanceID, text(instanceType) or "none", type(difficultyID) == "number" and difficultyID or nil, text(name)
end

-- Everyone in the player's party or raid except the player: array of { guid, name, realm, class }.
function Compat.GetGroupMembers()
    local members = {}
    local inRaid = Compat.Call(IsInRaid) == true
    local count = Compat.Call(inRaid and GetNumGroupMembers or GetNumSubgroupMembers)
    if type(count) ~= "number" then return members end
    local prefix = inRaid and "raid" or "party"
    local me = Compat.Call(UnitGUID, "player")
    for i = 1, count do
        local info = unitInfo(prefix .. i)
        if info.guid and info.guid ~= me then
            members[#members + 1] = info
        end
    end
    return members
end

-- { [skillLineID] = { rank, max, name } } for the learned professions, or nil without a usable API.
function Compat.GetProfessionSnapshot()
    if Compat.has.professions ~= "modern" then return nil end
    local snapshot = {}
    -- prof1, prof2, archaeology, fishing, cooking; nil where not learned.
    local slots = { Compat.Call(GetProfessions) }
    for i = 1, 5 do
        if type(slots[i]) == "number" then
            local name, _, rank, maxRank, _, _, skillLine = Compat.Call(GetProfessionInfo, slots[i])
            if type(skillLine) == "number" and type(rank) == "number" then
                snapshot[skillLine] = { rank = rank, max = type(maxRank) == "number" and maxRank or nil, name = text(name) }
            end
        end
    end
    return snapshot
end

function Compat.GetSkillLineName(skillLine)
    local api = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName
    return text(Compat.Call(api, skillLine))
end

-- Trimmed: some names come with stray spaces (23491 " Extrem sicherer Transporter: Gadgetzan" on
-- build 70235's German client).
function Compat.GetSpellName(spellID)
    local name
    if C_Spell and C_Spell.GetSpellName then
        name = Compat.Call(C_Spell.GetSpellName, spellID)
    else
        name = Compat.Call(GetSpellInfo, spellID)
    end
    return text(type(name) == "string" and name:match("^%s*(.-)%s*$") or nil)
end

-- A spell's icon (a file ID or path), or nil.
function Compat.GetSpellIcon(spellID)
    local icon
    if C_Spell and C_Spell.GetSpellTexture then
        icon = Compat.Call(C_Spell.GetSpellTexture, spellID)
    else
        icon = Compat.Call(GetSpellTexture, spellID)
    end
    return (type(icon) == "number" or type(icon) == "string") and icon or nil
end

-- Item class and subclass IDs are locale-free (7/7 = Metal & Stone, 7/9 = Herb, 7/6 = Leather).
function Compat.GetItemClass(itemID)
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local _, _, _, _, _, classID, subclassID = Compat.Call(C_Item.GetItemInfoInstant, itemID)
    return classID, subclassID
end

-- The game's own clock setting (Game Menu > Options > 24-hour clock); nil when the client has none.
function Compat.Uses24HourClock()
    local getCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
    local value = Compat.Call(getCVar, "timeMgrUseMilitaryTime")
    if value == "1" then return true end
    if value == "0" then return false end
    return nil
end

------------------------------------------------------------------------------------------------
-- Quests

-- A quest's title in the client's language; nil when the client hasn't loaded it.
function Compat.GetQuestTitle(questID)
    if not Compat.has.questTitles then return nil end
    return text(Compat.Call(C_QuestLog.GetTitleForQuestID, questID))
end

-- If questID ends a quest line of at least two quests: its questLineID and name. On Vanilla content
-- this may never match (docs/ARCHITECTURE.md §12 #4); the curated chains don't need it.
function Compat.GetQuestLineEnd(questID)
    if not Compat.has.questLines then return nil end
    local info = Compat.Call(C_QuestLine.GetQuestLineInfo, questID, Compat.GetPlayerMapID())
    if type(info) ~= "table" then return nil end
    local lineID = Compat.Safe(info.questLineID, "number")
    if not lineID then return nil end
    local quests = Compat.Call(C_QuestLine.GetQuestLineQuests, lineID)
    if type(quests) ~= "table" or #quests < 2 or Compat.Safe(quests[#quests], "number") ~= questID then
        return nil
    end
    return lineID, text(Compat.Safe(info.questLineName, "string"))
end

------------------------------------------------------------------------------------------------
-- Item names load asynchronously. A miss asks the client for the item; once data arrives, the bus
-- message ITEM_NAMES_LOADED tells the UI to redraw. The event is only watched while names are
-- pending.

local NAMES_SETTLE = 0.3
local namesFrame
local namesNotifyPending = false

local function onItemData()
    if namesNotifyPending then return end
    namesNotifyPending = true
    C_Timer.After(NAMES_SETTLE, function()
        namesNotifyPending = false
        namesFrame:UnregisterAllEvents()
        ns.Bus:Fire("ITEM_NAMES_LOADED")
    end)
end

local function watchItemData()
    if not namesFrame then
        namesFrame = CreateFrame("Frame")
        namesFrame:SetScript("OnEvent", onItemData)
    end
    pcall(namesFrame.RegisterEvent, namesFrame, "GET_ITEM_INFO_RECEIVED")
    pcall(namesFrame.RegisterEvent, namesFrame, "ITEM_DATA_LOAD_RESULT")
end

function Compat.GetItemName(itemID)
    if not C_Item then return nil end
    local name = text(Compat.Call(C_Item.GetItemNameByID, itemID))
    if not name and C_Item.RequestLoadItemDataByID then
        watchItemData()
        Compat.Call(C_Item.RequestLoadItemDataByID, itemID)
    end
    return name
end

------------------------------------------------------------------------------------------------
-- Loot

-- The open loot window as { [slot] = { itemID, quantity } } (money and currencies left out), plus
-- the GUID of what is being looted when the client tells us.
function Compat.GetLootSlots()
    local slots = {}
    local source
    local count = Compat.Call(GetNumLootItems)
    if type(count) ~= "number" then return slots end
    for slot = 1, count do
        local link = Compat.Call(GetLootSlotLink, slot)
        local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if itemID then
            local _, _, quantity = Compat.Call(GetLootSlotInfo, slot)
            slots[slot] = { itemID = itemID, quantity = type(quantity) == "number" and quantity > 0 and quantity or 1 }
        end
        source = source or text(Compat.Call(GetLootSourceInfo, slot))
    end
    return slots, source
end
