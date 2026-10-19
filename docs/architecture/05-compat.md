# 5. Compat layer

Part of the [Wayscribe architecture](../ARCHITECTURE.md); other sections are listed there.

`Compat` runs once at `PLAYER_LOGIN` and exposes:

```lua
Compat.has = {
    encounterEvents = …,   -- ENCOUNTER_END fires for dungeon bosses
    questLines      = …,   -- C_QuestLine.GetQuestLineInfo returns data for Vanilla quests
    unitPosition    = …,   -- UnitPosition("player") works outdoors
    mapWorldPos     = …,   -- C_Map.GetWorldPosFromMapPos / GetMapPosFromWorldPos
    professionsAPI  = …,   -- GetProfessions/GetProfessionInfo (Mainline) vs GetSkillLineInfo (Classic)
    settingsAPI     = …,   -- Settings.RegisterVerticalLayoutCategory
    lootSourceInfo  = …,   -- GetLootSourceInfo
    taxiState       = …,   -- UnitOnTaxi
    worldMapCanvas  = …,   -- the world map's data provider extension point
    mapChildren     = …,   -- C_Map.GetMapChildrenInfo: the zone maps coverage counts against
    mapExploration  = …,   -- C_MapExplorationInfo.GetExploredMapTextures: the zones explored (first visits)
    panelTabs       = …,   -- PanelTabButtonTemplate + PanelTemplates_*: the journal's tabs
    surnames        = …,   -- characters have a surname, returned where other clients return the realm
}
Compat.Safe(v [, expectedType])  -- -> v, or nil if issecretvalue(v) or the type is wrong. Every game value goes through this.
Compat.Call(fn, ...)             -- pcall + Safe on each return value, for APIs that may error or return secrets
Compat.CallWithRaw(fn, type, ...) -- -> first value through Safe, the raw value (for the launch trace), true if the call ran
Compat.GetPlayerWorldPosition()  -- -> continentID, x, y in world yards (UnitPosition, else map position); nil in instances
Compat.GetWorldPosFromMapPos(mapID, u, v) -- -> continentID, x, y of a map point
Compat.GetMapAtWorldPos(continentID, x, y) -- -> the most detailed uiMapID there
Compat.GetParentMap(mapID)       -- -> parentMapID
Compat.GetZoneRects()            -- -> { { map, c, minX, maxX, minY, maxY } } of every zone map, in world yards
Compat.GetZoneOf(mapID)          -- -> the zone a map lies in (itself, or the nearest zone above it)
Compat.GetExploredZones()        -- -> { [zoneMapID] = true } for every zone with explored-area textures
Compat.GetExploredTextureCounts() -- -> { [zoneMapID] = { textures, hover } } of every zone with explored-area textures
Compat.GetMoney()                -- -> copper, or nil when missing, erroring or secret; the raw value second (trace)
Compat.GetFactionStandings()     -- -> { [factionID] = { name, reaction } } of the reputation list, or nil; raw row count second
Compat.GetFactionStanding(id)    -- -> name, reaction of one faction read by ID (collapsed headers), or nil
Compat.GetLegacyChallenges()     -- -> { [id] = { name, done, day, account, byMe } }, or nil; raw category list second; true third when every row was read
Compat.GetLegacyChallengeName(id) -- -> one challenge's name read by ID, or nil
Compat.GetTaxiNodes()            -- -> { { id, name, current } } known at the open taxi map, or nil; { source, map, nodes } second
Compat.GetMounts()               -- -> { [mountID] = { name, collected } } of the mount journal, or nil; raw ID list second
Compat.GetPvPRank()              -- -> PvP rank (renown of Compat.PVP_RANK_FACTION, 2800), arena season, or nil each; raw values third/fourth
Compat.GetPvPRankTitle(rank)     -- -> the client's title of a PvP rank for the player's faction and sex, or nil
Compat.GetGlobalStringForPlayer(key) -- -> global string `key`, its _FEMALE form for a female character when there is one
Compat.GetBindLocation()         -- -> the hearthstone's inn, its place in the client's language, or nil; raw value second
Compat.GetGuild()                -- -> in a guild (true/false, nil unreadable), its name (nil until loaded); raw values third/fourth
Compat.GetEquippedItem(slot)     -- -> itemID (false empty, nil unreadable), quality (nil until loaded); raw values third/fourth
Compat.GetContinentOf(mapID)     -- -> the continent a map lies in, or nil
Compat.IsOnTaxi() / Compat.IsDeadOrGhost()
Compat.HasWorldMapCanvas()       -- WorldMapFrame takes MapCanvas data providers
Compat.GetProfessionSnapshot()   -- -> { [skillLineID] = { rank, max, name } }
Compat.GetWeaponSkills()         -- -> { [skillLineID] = { rank, max, name } } of the Weapon Skills lines (trained points), or nil; then the set of lines that read secret
Compat.GetWeaponSkillName(id)    -- -> a skill line's name from the Skills tab by ID, or nil
Compat.GetInstance()             -- -> instanceID, type, difficultyID, name
Compat.GetGroupMembers()         -- -> array of { guid, name, realm, class }; with surnames: "First Surname", no realm
Compat.GetLootSlots()            -- -> { [slot] = { itemID, quantity } }, sourceGUID
Compat.GetItemName(itemID)       -- -> name, or nil and the item is requested (ITEM_NAMES_LOADED follows)
Compat.GetItemClass(itemID)      -- -> classID, subclassID (locale-free)
Compat.GetSpellName(spellID) / Compat.GetSkillLineName(skillLineID)
Compat.GetQuestTitle(questID)    -- C_QuestLog title, nil until the client has the quest
Compat.GetQuestLineEnd(questID)  -- questLineID, name if questID is the last quest of a line
Compat.Uses24HourClock()         -- the game's clock setting, nil without one
```

**`/ws probe`** prints a capability report (which APIs exist and what they return right now). We run
it on the Forever beta and paste the result into [forever-probe.md](../forever-probe.md). Every
"verify on beta" item in §12 maps to one probe line.
