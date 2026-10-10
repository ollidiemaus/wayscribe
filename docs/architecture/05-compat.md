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
    panelTabs       = …,   -- PanelTabButtonTemplate + PanelTemplates_*: the journal's tabs
    surnames        = …,   -- characters have a surname, returned where other clients return the realm
}
Compat.Safe(v [, expectedType])  -- -> v, or nil if issecretvalue(v) or the type is wrong. Every game value goes through this.
Compat.Call(fn, ...)             -- pcall + Safe on each return value, for APIs that may error or return secrets
Compat.GetPlayerWorldPosition()  -- -> continentID, x, y in world yards (UnitPosition, else map position); nil in instances
Compat.GetWorldPosFromMapPos(mapID, u, v) -- -> continentID, x, y of a map point
Compat.GetMapAtWorldPos(continentID, x, y) -- -> the most detailed uiMapID there
Compat.GetParentMap(mapID)       -- -> parentMapID
Compat.GetZoneRects()            -- -> { { map, c, minX, maxX, minY, maxY } } of every zone map, in world yards
Compat.IsOnTaxi() / Compat.IsDeadOrGhost()
Compat.HasWorldMapCanvas()       -- WorldMapFrame takes MapCanvas data providers
Compat.GetProfessionSnapshot()   -- -> { [skillLineID] = { rank, max, name } }
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
