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
    "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_UNGHOST",
    -- 1.0 Launch trackers (docs/ARCHITECTURE.md §6.11)
    "PLAYER_MONEY", "UPDATE_FACTION", "PLAYER_EQUIPMENT_CHANGED", "ACHIEVEMENT_EARNED", "TAXIMAP_OPENED",
    "UI_INFO_MESSAGE", "PLAYER_GUILD_UPDATE", "HEARTHSTONE_BOUND", "CONFIRM_BINDER", "NEW_MOUNT_ADDED",
    "COMPANION_LEARNED", "NEW_PET_ADDED", "NEW_TOY_ADDED", "PLAYER_PVP_RANK_CHANGED",
    "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
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
    -- 0.4: the travel spells Footsteps recognizes, and the subzone deaths and journeys name.
    for _, spellID in ipairs(ns.StaticData.TravelSpells) do
        add("spell.travel." .. spellID, Compat.GetSpellName(spellID))
    end
    add("subZone", Compat.GetSubZoneName())
    add("cvar.timeMgrUseMilitaryTime", Compat.Uses24HourClock())
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

-- 0.3: does C_QuestLine know Vanilla quests (docs/ARCHITECTURE.md §12 #4)? Asked for the quests in
-- the player's log, since those are on the current map.
local MAX_QUESTS = 5
local function addQuestLines(add)
    local log = C_QuestLog
    if not (log and log.GetNumQuestLogEntries and log.GetInfo) then
        add("questLog", "no C_QuestLog")
        return
    end
    local mapID = Compat.GetPlayerMapID()
    local asked = 0
    for index = 1, Compat.Call(log.GetNumQuestLogEntries) or 0 do
        local info = Compat.Call(log.GetInfo, index)
        local isQuest = type(info) == "table" and Compat.Safe(info.isHeader) ~= true
        local questID = isQuest and Compat.Safe(info.questID, "number")
        if questID and asked < MAX_QUESTS then
            asked = asked + 1
            add("questTitle." .. questID, Compat.GetQuestTitle(questID))
            local line = Compat.has.questLines and Compat.Call(C_QuestLine.GetQuestLineInfo, questID, mapID)
            local lineID = type(line) == "table" and Compat.Safe(line.questLineID, "number")
            if lineID then
                local quests = Compat.Call(C_QuestLine.GetQuestLineQuests, lineID)
                local count = type(quests) == "table" and #quests or 0
                add("questLine." .. questID, lineID .. " " .. describe(Compat.Safe(line.questLineName)) .. " ("
                    .. count .. " quests, last " .. describe(count > 0 and Compat.Safe(quests[count]) or nil) .. ")")
            else
                add("questLine." .. questID, nil)
            end
        end
    end
    add("questLog.asked", asked)
end

-- 0.4 Footsteps: the current map's corners in the world, and the player's map position computed
-- from the world position through them, next to the client's own answer. The two must match.
local function addFootsteps(add, mapID)
    if Compat.has.taxiState then
        add("taxi", Compat.IsOnTaxi())
    end
    add("deadOrGhost", Compat.IsDeadOrGhost())
    add("worldMap.frame", type(WorldMapFrame) == "table")
    if not mapID then return end
    local corners = {}
    for i, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 } }) do
        local continentID, x, y = Compat.GetWorldPosFromMapPos(mapID, corner[1], corner[2])
        corners[i] = { continentID, x, y }
    end
    local parts = {}
    for i, corner in ipairs(corners) do
        parts[i] = corner[2] and string.format("%s:%.1f,%.1f", describe(corner[1]), corner[2], corner[3]) or "nil"
    end
    add("map.corners", table.concat(parts, " "))
    local transform = corners[3][2] and ns.Geometry.MapTransform(corners[1][2], corners[1][3], corners[2][2],
        corners[2][3], corners[3][2], corners[3][3])
    local continentID, x, y = Compat.GetPlayerWorldPosition()
    if transform and continentID then
        local u, v = ns.Geometry.ToMap(transform, x, y)
        add("map.fromWorld", string.format("%.4f, %.4f (%.0f x %.0f yd)", u, v, transform.width, transform.height))
    end
    add("map.atWorld", continentID and Compat.GetMapAtWorldPos(continentID, x, y) or nil)
    add("map.parent", Compat.GetParentMap(mapID))
end

-- 0.5 Your Year: the zone maps "% of Azeroth walked" counts against, per continent, with the
-- area they cover together (square miles).
local SQUARE_MILE = 1760 * 1760
local function addCoverage(add)
    local rects = Compat.GetZoneRects()
    if not rects then
        add("coverage.zones", nil)
        return
    end
    local byContinent = {}
    for _, rect in ipairs(rects) do
        byContinent[rect.c] = byContinent[rect.c] or {}
        table.insert(byContinent[rect.c], rect)
    end
    add("coverage.zones", #rects)
    for continentID, list in pairs(byContinent) do
        add("coverage.continent." .. continentID, string.format("%d zones, %.0f sq mi",
            #list, ns.Geometry.UnionArea(list) / SQUARE_MILE))
    end
end

-- 0.7 Notes: Alt+click on the map, the map's strata (a game rule can change it), whether this
-- ruleset turns off the default map's own pin, and the popup that names a new note.
local function addNotes(add)
    local map = WorldMapFrame
    add("worldMap.canvasClicks", type(map) == "table" and type(map.AddCanvasClickHandler) == "function")
    add("worldMap.strata", type(map) == "table" and Compat.Call(map.GetFrameStrata, map) or nil)
    local rule = type(Enum) == "table" and type(Enum.GameRule) == "table" and Enum.GameRule.WorldMapTrackingPinDisabled
    local active = rule and C_GameRules and Compat.Call(C_GameRules.IsGameRuleActive, rule)
    add("gameRule.worldMapTrackingPinDisabled", active)
    add("staticPopup", type(StaticPopup_Show) == "function")
end

-- 1.0 Launch: what the new trackers would read (docs/ARCHITECTURE.md §6.11). APIs are looked up by
-- name, so one this client lacks reads "missing" instead of breaking the probe.
local function lookup(path)
    local value = _G
    for part in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return value
end

local function call(path, ...)
    return Compat.Call(lookup(path), ...)
end

-- An API's first return value, with "missing", "error" and "secret" told apart from nil.
local function probeValue(path, ...)
    local fn = lookup(path)
    if type(fn) ~= "function" then return "missing" end
    local ok, value = pcall(fn, ...)
    if not ok then return "error" end
    if Compat.IsSecret(value) then return "secret" end
    return value
end

local function gameRule(name)
    local rule = type(Enum) == "table" and type(Enum.GameRule) == "table" and Enum.GameRule[name]
    return rule and call("C_GameRules.IsGameRuleActive", rule)
end

-- First visits: the best map and the maps above it, with their types (3 = zone, 2 = continent),
-- the zone the tracker takes from them, and the zones the world map shows explored: how many count,
-- of the zones that return explored-area textures, with each zone's textures and how many of them
-- the map only shows under the mouse.
local function addFirstVisits(add, mapID)
    add("firstVisit.zone", Compat.GetZoneOf(mapID))
    local depth = 0
    while mapID and depth < 4 do
        local info = call("C_Map.GetMapInfo", mapID)
        if type(info) ~= "table" then break end
        add("firstVisit.map." .. depth, mapID .. " " .. describe(Compat.Safe(info.name)) .. " (type "
            .. describe(Compat.Safe(info.mapType)) .. ")")
        local parent = Compat.Safe(info.parentMapID, "number")
        mapID = parent ~= 0 and parent or nil
        depth = depth + 1
    end
    local counts = Compat.GetExploredTextureCounts()
    if not counts then
        add("firstVisit.explored", "missing")
        return
    end
    local zones, parts = {}, {}
    for zone in pairs(counts) do zones[#zones + 1] = zone end
    table.sort(zones)
    for _, zone in ipairs(zones) do
        parts[#parts + 1] = string.format("%d %d/%d", zone, counts[zone].textures, counts[zone].hover)
    end
    add("firstVisit.explored", #zones > 0 and table.concat(parts, ", ") .. " (textures/hover-only)" or "none")
end

-- Reputation: the rows the reputation list shows (collapsed headers hide their factions), one
-- faction read by index and again by ID, and Forever's two tracks that are reputations inside.
local function addReputation(add)
    local count = probeValue("C_Reputation.GetNumFactions")
    add("rep.rows", count)
    if type(count) ~= "number" then return end
    local headers, collapsed, factions, sample = 0, 0, 0, nil
    for index = 1, count do
        local data = call("C_Reputation.GetFactionDataByIndex", index)
        if type(data) == "table" then
            local isHeader = Compat.Safe(data.isHeader) == true
            if isHeader then headers = headers + 1 end
            if Compat.Safe(data.isCollapsed) == true then collapsed = collapsed + 1 end
            if not isHeader or Compat.Safe(data.isHeaderWithRep) == true then
                factions = factions + 1
                sample = sample or data
            end
        end
    end
    add("rep.list", string.format("%d factions, %d headers (%d collapsed)", factions, headers, collapsed))
    if sample then
        local id, reaction = Compat.Safe(sample.factionID, "number"), Compat.Safe(sample.reaction, "number")
        add("rep.sample", describe(id) .. " " .. describe(Compat.Safe(sample.name)) .. ", reaction "
            .. describe(reaction) .. " " .. describe(reaction and _G["FACTION_STANDING_LABEL" .. reaction]) .. " / "
            .. describe(reaction and _G["FACTION_STANDING_LABEL" .. reaction .. "_FEMALE"]))
        local byID = id and call("C_Reputation.GetFactionDataByID", id)
        add("rep.sampleByID", type(byID) == "table" and Compat.Safe(byID.reaction) or nil)
    end
    for _, factionID in ipairs({ Compat.PVP_RANK_FACTION, Compat.LEGACY_TRACK_FACTION }) do
        local data = call("C_Reputation.GetFactionDataByID", factionID)
        add("rep." .. factionID, type(data) == "table" and (describe(Compat.Safe(data.name)) .. ", reaction "
            .. describe(Compat.Safe(data.reaction))) or nil)
    end
end

-- Notable gear: each worn item and its quality (3 = rare, 4 = epic).
local function addGear(add)
    local parts = {}
    for slot = 1, 19 do
        local itemID = call("GetInventoryItemID", "player", slot)
        if itemID then
            parts[#parts + 1] = slot .. ":" .. describe(itemID) .. "/q"
                .. describe(probeValue("GetInventoryItemQuality", "player", slot))
        end
    end
    add("gear.slots", #parts > 0 and table.concat(parts, " ") or probeValue("GetInventoryItemID", "player", 1))
end

-- Legacy Challenges: how many there are, how many are done, and how many by this character
-- (the game may count them per account), with one completed challenge and its date.
local function addLegacyChallenges(add)
    add("legacy.panelDisabled", gameRule("AchievementsPanelDisabled"))
    add("legacy.track", probeValue("C_MajorFactions.GetCurrentRenownLevel", Compat.LEGACY_TRACK_FACTION))
    local categories = call("GetCategoryList")
    if type(categories) ~= "table" then
        add("legacy.categories", probeValue("GetCategoryList"))
        return
    end
    local total, completed, mine, sample = 0, 0, 0, nil
    for _, categoryID in ipairs(categories) do
        local count = Compat.Safe(categoryID, "number") and call("GetCategoryNumAchievements", categoryID)
        for index = 1, type(count) == "number" and count or 0 do
            local id, name, _, done, month, day, year, _, _, _, _, _, byMe = call("GetAchievementInfo", categoryID, index)
            if id then
                total = total + 1
                if done then completed = completed + 1 end
                if byMe then mine = mine + 1 end
                if done and not sample then
                    sample = string.format("%s %s, %s/%s/%s, by me %s", describe(id), describe(name), describe(month),
                        describe(day), describe(year), describe(byMe))
                end
            end
        end
    end
    add("legacy.challenges", string.format("%d in %d categories, %d completed, %d by this character", total,
        #categories, completed, mine))
    add("legacy.sample", sample)
end

-- Flight paths: the nodes are only readable at a flight master, so run the probe once with the
-- taxi map open. Forever has two taxi maps: the old frame (NumTaxiNodes) and the flight map.
local function addFlightPaths(add)
    add("flightPaths.oldFrame", probeValue("NumTaxiNodes"))
    local taxiMapID = call("GetTaxiMapID")
    add("flightPaths.taxiMap", taxiMapID or probeValue("GetTaxiMapID"))
    local nodes = taxiMapID and call("C_TaxiMap.GetAllTaxiNodes", taxiMapID)
    if type(nodes) == "table" then
        local byState = {}
        for _, node in ipairs(nodes) do
            local state = describe(type(node) == "table" and Compat.Safe(node.state) or nil)
            byState[state] = (byState[state] or 0) + 1
        end
        local parts = {}
        for state, n in pairs(byState) do parts[#parts + 1] = "state " .. state .. ": " .. n end
        table.sort(parts)
        add("flightPaths.nodes", #nodes .. " (" .. table.concat(parts, ", ") .. ")")
    end
end

-- Collections: mounts as the mount journal knows them, then pets and toys. Whether the character
-- has any toy, and the journal's "collected only" filter, tell a "0 of 0" that means nothing owned
-- from one that means the API doesn't answer.
local function addCollections(add)
    local ids = call("C_MountJournal.GetMountIDs")
    if type(ids) == "table" then
        local collected, first = 0, nil
        for _, mountID in ipairs(ids) do
            local name, _, _, _, _, _, _, _, _, _, isCollected = call("C_MountJournal.GetMountInfoByID", mountID)
            if isCollected then
                collected = collected + 1
                first = first or name
            end
        end
        add("collections.mounts", string.format("%d in the journal, %d collected%s", #ids, collected,
            first and " (" .. first .. ")" or ""))
    else
        add("collections.mounts", probeValue("C_MountJournal.GetMountIDs"))
    end
    local pets, owned = call("C_PetJournal.GetNumPets")
    add("collections.pets", pets and describe(owned) .. " of " .. describe(pets) or probeValue("C_PetJournal.GetNumPets"))
    add("collections.toys", describe(probeValue("C_ToyBox.GetNumLearnedDisplayedToys")) .. " of "
        .. describe(probeValue("C_ToyBox.GetNumTotalDisplayedToys")))
    add("collections.hasAnyToy", probeValue("C_ToyBoxInfo.HasAnyToy"))
    add("collections.onlyShowCollected", probeValue("C_CVar.GetCVar", "onlyShowCollectedItemsInJournal"))
end

-- Each weapon skill line Compat reads, with the category the game gives it by ID.
local function addWeaponSkills(add)
    local skills = Compat.GetWeaponSkills()
    if not skills then
        add("weaponSkills", nil)
        return
    end
    local ids = {}
    for id in pairs(skills) do ids[#ids + 1] = id end
    table.sort(ids)
    add("weaponSkills", #ids .. " lines")
    for _, id in ipairs(ids) do
        local skill = skills[id]
        local info = C_SkillInfo.GetSkillLineInfoByID and Compat.Call(C_SkillInfo.GetSkillLineInfoByID, id)
        local category = type(info) == "table" and Compat.Safe(info.skillLineCategoryID) or nil
        add("weaponSkill." .. id, describe(skill.name) .. ", category " .. describe(category) .. ", "
            .. describe(skill.rank) .. "/" .. describe(skill.max))
    end
end

local function addLaunchTrackers(add, mapID)
    addWeaponSkills(add)
    addFirstVisits(add, mapID)
    add("gold.money", probeValue("GetMoney"))
    addReputation(add)
    addGear(add)
    addLegacyChallenges(add)
    addFlightPaths(add)
    add("guild.inGuild", probeValue("IsInGuild"))
    add("guild.name", probeValue("GetGuildInfo", "player"))
    add("home.bind", probeValue("GetBindLocation"))
    addCollections(add)
    local rank = call("C_MajorFactions.GetMajorFactionProgressionInfo", Compat.PVP_RANK_FACTION)
    add("pvpRank.level", type(rank) == "table" and Compat.Safe(rank.renownLevel)
        or probeValue("C_MajorFactions.GetMajorFactionProgressionInfo", Compat.PVP_RANK_FACTION))
    add("pvpRank.season", probeValue("GetCurrentArenaSeason"))
    add("jumps.hook", type(hooksecurefunc) == "function" and type(JumpOrAscendStart) == "function")
    add("jumps.falling", probeValue("IsFalling"))
    add("jumps.swimming", probeValue("IsSwimming"))
    add("jumps.flying", probeValue("IsFlying"))
    add("jumps.vehicle", probeValue("UnitInVehicle", "player"))
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
    addQuestLines(add)
    addFootsteps(add, mapID)
    addCoverage(add)
    addNotes(add)
    addLaunchTrackers(add, mapID)
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
