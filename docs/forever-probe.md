# Forever probe results

Output of `/ws probe`, copied from `WayscribeDB.probe` in the account SavedVariables file.
The interpretation is in [ARCHITECTURE.md §12](architecture/12-forever-beta.md).

## Client 1.60.1, build 70235 (2026-10-06)

Level 1 Tauren Druid, outdoors in Mulgore, no professions learned.

```text
addon = @project-version@
client = 1.60.1 (build 70235)
interface = 16001
isForever = true
WOW_PROJECT_ID = 18
has.addonCompartment = true
has.bossKillEvent = true
has.encounterEvents = true
has.lootSourceInfo = true
has.mapPlayerPosition = true
has.mapWorldPos = true
has.professions = modern
has.questLines = true
has.scrollBox = true
has.secretValues = true
has.settingsAPI = true
has.unitPosition = true
event.BOSS_KILL = true
event.CHAT_MSG_SKILL = true
event.ENCOUNTER_END = true
event.LFG_COMPLETION_REWARD = true
event.LOOT_READY = true
event.LOOT_SLOT_CLEARED = true
event.PLAYER_DEAD = true
event.PLAYER_LEVEL_UP = true
event.QUEST_TURNED_IN = true
event.SCENARIO_COMPLETED = true
event.SKILL_LINES_CHANGED = true
event.TRADE_SKILL_LIST_UPDATE = true
event.UNIT_SPELLCAST_SUCCEEDED = true
map.best = 1412
map.position = 0.4416, 0.7706
map.world = continent 1 at -2894.3, -238.8
unitPosition = -238.8, -2894.3 (instance 1)
instance = Kalimdor / none / difficulty 0 / id 1
professions = nil, nil, nil, nil, nil
level = 1
secret.UnitLevel = false
```

Notes:
- The `unitPosition` line of this run printed the two values swapped: that probe version named them
  `y, x` and printed `x, y`. In return order, `UnitPosition` gave `-2894.3, -238.8`, the same point as
  `map.world`. Probes from now on print in return order.
- `addon = @project-version@` is expected for an unpackaged copy; the packager fills in the version.

## Client 1.60.1, build 70235, Wayscribe 0.2 (2026-10-06)

Same character (level 1 Tauren Druid in Mulgore, no professions), German client, with the four
libraries in `Libs/`.

```text
addon = @project-version@
client = 1.60.1 (build 70235)
interface = 16001
isForever = true
WOW_PROJECT_ID = 18
has.addonCompartment = true
has.bossKillEvent = true
has.encounterEvents = true
has.itemInfoInstant = true
has.lootSourceInfo = true
has.mapPlayerPosition = true
has.mapWorldPos = true
has.professions = modern
has.questLines = true
has.scrollBox = true
has.secretValues = true
has.settingsAPI = true
has.spellNames = true
has.tradeSkillNames = true
has.unitPosition = true
event.BOSS_KILL = true
event.CHAT_MSG_SKILL = true
event.ENCOUNTER_END = true
event.GET_ITEM_INFO_RECEIVED = true
event.ITEM_DATA_LOAD_RESULT = true
event.LFG_COMPLETION_REWARD = true
event.LOOT_CLOSED = true
event.LOOT_READY = true
event.LOOT_SLOT_CLEARED = true
event.PLAYER_DEAD = true
event.PLAYER_LEVEL_UP = true
event.QUEST_TURNED_IN = true
event.SCENARIO_COMPLETED = true
event.SKILL_LINES_CHANGED = true
event.TRADE_SKILL_LIST_UPDATE = true
event.UNIT_SPELLCAST_SUCCEEDED = true
event.ZONE_CHANGED_NEW_AREA = true
map.best = 1412
map.position = 0.4416, 0.7708
map.world = continent 1 at -2895.4, -238.3
unitPosition = -2895.4, -238.3 (instance 1)
instance = Kalimdor / none / difficulty 0 / id 1
professions = nil, nil, nil, nil, nil
level = 1
secret.UnitLevel = false
spell.mining.2575 = Bergbau
spell.mining.2576 = Bergbau
spell.mining.3564 = Bergbau
spell.mining.10248 = Bergbau
spell.mining.1235230 = Bergbau
spell.herbalism.2366 = Kräuterkunde
spell.herbalism.2368 = Kräuterkunde
spell.herbalism.3570 = Kräuterkunde
spell.herbalism.11993 = Kräuterkunde
spell.herbalism.1235236 = Kräutersammeln
spell.skinning.8613 = Kürschnerei
spell.skinning.8617 = Kürschnerei
spell.skinning.8618 = Kürschnerei
spell.skinning.10768 = Kürschnerei
lib.LibStub = 2
lib.CallbackHandler-1.0 = 8
lib.LibDataBroker-1.1 = 4
lib.LibDBIcon-1.0 = 56
```

Notes:
- Every gather spell ID from `StaticData/Gathering.lua` exists. The names come back in the client's
  language (Bergbau, Kräuterkunde, Kürschnerei), and 1235236 is Kräutersammeln, Forever's herb
  gathering spell. Matching by name therefore works on a German client.
- All four libraries loaded: LibStub 2, CallbackHandler-1.0 8, LibDataBroker-1.1 4, LibDBIcon-1.0 56.
- `unitPosition` now prints in return order and equals `map.world`.
- A full relog after this run added a second session to the journal, as expected.

## Client 1.60.1, build 70235, Wayscribe 0.3 (2026-10-06)

Same character (level 1 Tauren Druid in Mulgore), German client, two quests in the log. Every line
the 0.2 probe printed came back the same (positions differ by a few yards), plus
`has.questTitles = true`. The lines new in 0.3:

```text
has.questTitles = true
cvar.timeMgrUseMilitaryTime = true
questTitle.747 = Die Jagd beginnt
questLine.747 = nil
questTitle.752 = Eine bescheidene Bitte
questLine.752 = nil
questLog.asked = 2
```

Notes:
- `C_QuestLine.GetQuestLineInfo` returns nothing for 747 (The Hunt Begins) and 752 (A Humble Task),
  although both are the first quests of short Mulgore chains in Vanilla. Forever's client doesn't
  seem to have quest line data for Vanilla quests, so the curated chains carry the feature. The quest
  line provider stays: it costs nothing and would pick up lines if Blizzard adds them.
- Quest titles resolve in the client's language through `C_QuestLog.GetTitleForQuestID`.
- The game's 24-hour clock setting is readable (on, on this German client), so journal times
  follow it.
- The same session saved the journal window's size and position, and the back-fill check stored
  `state.questChains = 1` at login without errors.

## Client 1.60.1, build 70235, Wayscribe 0.4 (2026-10-06)

Same character (level 1 Tauren Druid), standing in Mulgore, German client. Every line the 0.3
probe printed came back the same, plus `has.taxiState = true` and `has.worldMapCanvas = true`.
The lines new in 0.4:

```text
has.taxiState = true
has.worldMapCanvas = true
event.PLAYER_CONTROL_LOST = true
event.PLAYER_CONTROL_GAINED = true
event.PLAYER_UNGHOST = true
map.best = 1412
map.position = 0.4422, 0.7712
map.world = continent 1 at -2896.8, -242.5
unitPosition = -2896.8, -242.5 (instance 1)
taxi = false
deadOrGhost = false
worldMap.frame = true
map.corners = 1:266.7,2479.2 1:266.7,-3675.0 1:-3835.4,2479.2
map.fromWorld = 0.4422, 0.7712 (6154 x 4102 yd)
map.atWorld = 1414
map.parent = 1414
```

Notes:
- **The world-to-map transform is right:** Footsteps' own math (`map.fromWorld`, from the map's
  corners and `UnitPosition`) gives exactly the client's `map.position`. Mulgore is 6154 × 4102
  yards; its corners confirm that north is +x and west is +y.
- `C_Map.GetMapPosFromWorldPos` without a map ID answers with the continent (1414 Kalimdor), not
  the zone. `Compat.GetMapAtWorldPos` now walks down with `C_Map.GetMapInfoAtPosition`, so the
  journal's map button opens Mulgore.
- The world map takes MapCanvas data providers. The session's trail (one trail of 1807 yards over
  six minutes, stored at logout) was drawn on Mulgore in the right place, above the explored-area
  art.

## Client 1.60.1, build 70235, Wayscribe 0.4, Skinning learned (2026-10-06)

Same character, now level 2, after learning Skinning, standing in Mulgore. Every other line came
back as in the 0.4 probe above. The lines that changed:

```text
map.position = 0.4875, 0.8099
map.fromWorld = 0.4875, 0.8098 (6154 x 4102 yd)
map.atWorld = 1412
professions = 4, nil, nil, nil, nil
level = 2
profession.393 = Kürschnerei 3/75 (skill line name: Kürschnerei)
```

Notes:
- **Answers §12 #2:** `GetProfessionInfo` returns the classic parent skill line (393 Skinning), not
  one of Forever's child lines (2937–2948). Rank and maximum come back (3/75), and
  `C_TradeSkillUI.GetTradeSkillDisplayName` names it in the client's language.
- `GetProfessions` reports the profession at index 4 in its first slot (prof1).
- The journal recorded `PROFESSION_LEARNED {skillLine = 393}` with the first-time mark, and the real
  level-up to 2 with its map (1412).
- `map.atWorld` now names the zone (1412), after the fix that walks down from the continent.

## Client 1.60.1, build 70235, Wayscribe 0.4, travel spells (2026-10-06)

Same character (level 2), standing in Bloodhoof. The lines new since the Skinning probe:

```text
spell.travel.8690 = Ruhestein
spell.travel.556 = Astraler Rückruf
spell.travel.3561 = Teleportieren: Stormwind
spell.travel.3562 = Teleportieren: Ironforge
spell.travel.3563 = Teleportieren: Undercity
spell.travel.3565 = Teleportieren: Darnassus
spell.travel.3566 = Teleportieren: Thunder Bluff
spell.travel.3567 = Teleportieren: Orgrimmar
subZone = Bloodhoof
```

Notes:
- Every travel spell resolves to its German name, so journeys are matched by name as well as ID.
- `GetSubZoneText` answers outdoors ("Bloodhoof"); deaths and journeys keep this text.
- The travel spell list was then extended from build 70235's `SpellName.db2` (via wago.tools):
  Teleport: Moonglade 18960, Forever's Teleport: Dalaran 1297659, Dimensional Ripper - Everlook
  23486 (not 23442, which is its effect), Ultrasafe Transporter: Gadgetzan 23489/23491, and
  Forever's hearthstones and transporters. The next probe prints their names.

## Client 1.60.1, build 70235, Wayscribe 0.4, extended travel spells (2026-10-06)

Same character, in Bloodhoof, after the travel spell list grew:

```text
spell.travel.8690 = Ruhestein
spell.travel.1235126 = Ruhestein der Argentumdämmerung
spell.travel.1312670 = Bröckelnder Ruhestein
spell.travel.556 = Astraler Rückruf
spell.travel.18960 = Teleportieren: Moonglade
spell.travel.3561 = Teleportieren: Stormwind
spell.travel.3562 = Teleportieren: Ironforge
spell.travel.3563 = Teleportieren: Undercity
spell.travel.3565 = Teleportieren: Darnassus
spell.travel.3566 = Teleportieren: Thunder Bluff
spell.travel.3567 = Teleportieren: Orgrimmar
spell.travel.1297659 = Teleportieren: Dalaran
spell.travel.23486 = Dimensionszerfetzer-Everlook
spell.travel.23489 = Extrem sicherer Transporter nach Gadgetzan
spell.travel.23491 =  Extrem sicherer Transporter: Gadgetzan
spell.travel.1226213 = Halbwegs sicherer Transporter: Neu-Avalon
spell.travel.1266932 = EZ-Thro-Feldtransporter: Gadgetzan
spell.travel.1266934 = EZ- und SAF-Feldtransporter: Hyjal
spell.travel.1266936 = Dimensionstransporter: Hyjal
subZone = Bloodhoof
```

Notes:
- All 19 travel spells exist on the client and have German names, including Forever's own
  (Hearthstone of the Dawn is "Ruhestein der Argentumdämmerung").
- 23491's name starts with a space in the client's data. `Compat.GetSpellName` now trims names, so
  the journal never shows it.

## Client 1.60.1, build 70235, Wayscribe 0.5 (2026-10-06)

Scoopz in Bloodhoof, Mulgore, with the 0.5 copy (`/ws probe`; the lines new in 0.5):

```text
has.mapChildren = true
has.panelTabs = true
map.best = 1412
coverage.zones = 50
coverage.continent.1 = 23 zones, 71 sq mi
coverage.continent.0 = 26 zones, 45 sq mi
coverage.continent.2991 = 1 zones, 7 sq mi
```

Notes:
- `C_Map.GetMapChildrenInfo` lists the zone maps, so "% of Azeroth walked" works (§12 #10): 23
  zones in Kalimdor, 26 in the Eastern Kingdoms, about 123 square miles in all, roughly 38,000
  squares of 100 yards.
- Continent 2991 is **Zephras Isle**, one of Forever's own zones: `Map.db2` 2991 "Zephras Isle"
  (not instanced) and `UiMap.db2` 2521 "Zephras Isle", a zone directly under Azeroth (947), checked
  on wago.tools for build 70235. It counts, as intended for zones Forever adds. (`UiMap` 2665 with
  the same name is a legacy taxi map, not a world zone, and isn't listed.)
- `PanelTabButtonTemplate` and `PanelTemplates_SetNumTabs` / `SetTab` exist (§12 #11): the journal
  shows the default UI's tabs.
- After a short session with the hearthstone: "Du bist 0,1 % von Azeroth abgelaufen", most walked
  zone Mulgore with 2.2%.

## Client 1.60.1, build 70245, surnames (2026-10-07)

Scoopz in Bloodhoof, Mulgore, with the surname fix (`/ws probe`; the line new with it):

```text
client = 1.60.1 (build 70245)
has.surnames = true
```

Notes:
- `UnitName("player")` returns the surname as its second value, as reported for other addons
  (AllTheThings #2630). The journal and the account file now name the character "Scoopz Scoopz" on
  realm "Classic Beta PvE" (from `GetRealmName`); before the fix they said "Scoopz" on realm
  "Scoopz".
- Every other probe line is the same as on build 70235.

## Client 1.60.1, build 70291, Wayscribe 0.7 (2026-10-09)

Scoopz in Bloodhoof, Mulgore, with the 0.7 copy (`/ws probe`; the lines new in 0.7):

```text
client = 1.60.1 (build 70291)
worldMap.canvasClicks = true
worldMap.strata = MEDIUM
gameRule.worldMapTrackingPinDisabled = false
staticPopup = true
```

Notes:
- The map takes click handlers (`AddCanvasClickHandler`), so Alt+click starts a note (§12 #14).
  In game the popup showed in front of the map, also in combat, with no "blocked" message.
- The map's strata is `MEDIUM`, below the journal's `HIGH`: a marker's click brings the journal up
  in front of the map without changing anything.
- Forever's ruleset leaves the default map's own pin on (`WorldMapTrackingPinDisabled` is false), so
  Ctrl+click still sets the game's pin, and a note could later offer "Set as waypoint".
- Every other probe line is the same as on build 70245.

## Client 1.60.1, build 70374, the launch probe (2026-10-15)

Scoopz, a level 2 Tauren Druid with Skinning, in Bloodhoof Village, Mulgore, right after login.
English client, with the copy of `bf97f95` (`/ws probe`; the lines new since build 70291):

```text
addon = 0.0.6-5-gbf97f95
client = 1.60.1 (build 70374)
has.filterDropdown = true
has.portraitFrame = true
has.scrollFrameBar = true
event.PLAYER_MONEY = true
event.UPDATE_FACTION = true
event.PLAYER_EQUIPMENT_CHANGED = true
event.ACHIEVEMENT_EARNED = true
event.TAXIMAP_OPENED = true
event.UI_INFO_MESSAGE = true
event.PLAYER_GUILD_UPDATE = true
event.HEARTHSTONE_BOUND = true
event.CONFIRM_BINDER = true
event.NEW_MOUNT_ADDED = true
event.COMPANION_LEARNED = true
event.NEW_PET_ADDED = true
event.NEW_TOY_ADDED = true
event.PLAYER_PVP_RANK_CHANGED = true
event.MAJOR_FACTION_RENOWN_LEVEL_CHANGED = true
firstVisit.map.0 = 1412 Mulgore (type 3)
firstVisit.map.1 = 1414 Kalimdor (type 2)
firstVisit.map.2 = 947 Azeroth (type 1)
gold.money = 5
rep.rows = 5
rep.list = 4 factions, 1 headers (0 collapsed)
rep.sample = 530 Darkspear Trolls, reaction 5 Friendly / Friendly
rep.sampleByID = 5
rep.2800 = nil
rep.2802 = nil
gear.slots = 5:6139/q0 6:3363/q0 7:6124/q0 9:1370/q0 16:35/q1
legacy.panelDisabled = false
legacy.track = 16
legacy.challenges = 112 in 29 categories, 1 completed, 1 by this character
legacy.sample = 64283 Played in the WoW: Forever Beta, 10/9/26, by me true
flightPaths.oldFrame = 0
flightPaths.taxiMap = -1
flightPaths.nodes = 0 ()
guild.inGuild = false
guild.name = nil
home.bind = Bloodhoof Village
collections.mounts = 136 in the journal, 0 collected
collections.pets = 0 of 0
collections.toys = 0 of 0
pvpRank.level = 0
pvpRank.season = 0
```

At level 3, at the Thunder Bluff flight master with the taxi map open, with the hearthstone bound
there (the lines that changed):

```text
map.best = 1456
firstVisit.map.0 = 1456 Thunder Bluff (type 3)
flightPaths.oldFrame = 22
flightPaths.taxiMap = 1464
flightPaths.nodes = 22 (state 0: 1, state 2: 21)
home.bind = Thunder Bluff
```

At level 3 in Camp Taurajo, The Barrens, with the copy of `8bf0930` (First visits and the launch
trace built; the lines new or changed):

```text
addon = 0.0.6-7-g8bf0930
has.mapExploration = true
map.best = 1413
firstVisit.zone = 1413
firstVisit.map.0 = 1413 The Barrens (type 3)
firstVisit.explored = 5 zones: 1412 1413 1416 1429 1450
home.bind = Camp Taurajo
```

And the launch trace of two logins there (`WayscribeDB.trace`):

```text
2026-10-15 14:40:08 FirstVisits enable+PLAYER_ENTERING_WORLD: taxi=false instance="none" map=1413 zone=1413 -> recorded before
2026-10-15 14:41:47 FirstVisits enable+PLAYER_ENTERING_WORLD: taxi=false instance="none" map=1413 zone=1413 -> recorded before
```

Notes:
- No launch line reads `missing`, `error` or `secret`, and every launch event registers. What this
  means for each tracker is in §12 row 16. The error log has nothing new since 2026-10-07.
- The client was English this time, so spell, faction and place names came back in English, and
  the German `_FEMALE` standing labels weren't exercised.
- The worn items' qualities match Forever's item data (`Novice's Robe` and the rest Poor, `Bent
  Staff` Common).
- `GetAchievementInfo` gives the year as `26`, counted from 2000.
- `C_Reputation` doesn't know factions 2800 and 2802 by ID, but `C_MajorFactions` reads both: Legacy
  Track renown 16 on a level 2 character with one challenge (so not earned by this character), and
  PvP rank renown 0 in season 0.
- The taxi map is 1464, Forever's taxi map of Kalimdor (a `UiMap` without a parent), not the
  world map's 1414. The old frame (`NumTaxiNodes`) answers too, with the same 22 nodes. Only
  Thunder Bluff was known (state 0); the 21 others are state 2.
- `firstVisit.explored` lists Alterac Mountains (1416), Elwynn Forest (1429) and Moonglade (1450),
  though the character has only been to Mulgore, Thunder Bluff and the Barrens: the journal knows
  only those three, and all 108 Footsteps trails are on Kalimdor. They don't share area bits with
  Mulgore (`AreaTable`, build 70374). Forever's map hides textures with `isShownByMouseOver` until
  the mouse is over them (`MapExplorationDataProvider`), while `Compat.GetExploredZones` counts any
  texture: a possible cause, which the next section rules out.
- First visits wrote The Barrens at 14:21, marked as a first. Its silent first look, in Thunder
  Bluff, kept 1412, 1416, 1429, 1450 and 1456 in `state.visits`, so a first visit to the three
  zones above would be silent. Both trace lines rightly end `recorded before`.
- Pets and toys read `0 of 0` in every run, which doesn't settle them. `C_PetJournal.GetNumPets` is
  filtered (Forever's own pet window reads the same), and Forever has the
  `onlyShowCollectedItemsInJournal` setting, so a character without pets or toys can't tell
  "doesn't work" from "nothing to show".

## Client 1.60.1, build 70374, Wayscribe 962ac39 (2026-10-15)

Scoopz, level 3, in the Southern Barrens near Camp Taurajo, with the copy of `962ac39`
(hover-only textures left out of the explored zones, two new collections lines). The lines new or
changed at 15:07:

```text
addon = 0.0.6-9-g962ac39
firstVisit.explored = 5 of 5 zones (textures/hover-only): 1412 3/0, 1413 1/0, 1416 1/0, 1429 1/0, 1450 1/0
collections.hasAnyToy = false
collections.onlyShowCollected = 1
```

At 15:08 on the Southern Gold Road, away from a flight master, the taxi map read differently (and
the `flightPaths.nodes` line was left out):

```text
flightPaths.taxiMap = nil
```

The launch trace of that session:

```text
2026-10-15 15:06:54 FirstVisits enable+PLAYER_ENTERING_WORLD: taxi=false instance="none" map=1414 zone=missing -> no zone
2026-10-15 15:06:56 FirstVisits ZONE_CHANGED_NEW_AREA: taxi=false instance="none" map=1413 zone=1413 -> recorded before
2026-10-15 15:07:24 FirstVisits enable+PLAYER_ENTERING_WORLD: taxi=false instance="none" map=1413 zone=1413 -> recorded before
```

Notes:
- Hover-only textures are ruled out: Alterac Mountains, Elwynn Forest and Moonglade each return one
  texture, and none of them is hover-only, so `Compat.GetExploredZones` still counts them. The cause
  is unknown. Whether a brand-new character gets them too is untested; if it does, the first look on
  a level 1 character can't take the explored zones.
- Pets and toys: `onlyShowCollectedItemsInJournal` is on and `HasAnyToy` is false, so `0 of 0`
  means the journals list only what the character owns, and it owns none. Whether a learned pet or
  toy shows up is still untested.
- Away from a flight master `GetTaxiMapID` gave `nil` this time and `-1` before. Both mean no taxi
  map.
- At the login, a second after `PLAYER_ENTERING_WORLD`, the best map was still Kalimdor, so the look
  found no zone and wrote nothing. `ZONE_CHANGED_NEW_AREA` two seconds later looked again. The
  Southern Gold Road is part of the Barrens, so no entry. The error log has nothing new.

## Client 1.60.1, build 70374, a brand-new character (2026-10-15)

Mato, a level 1 Tauren Druid created at 15:23, in Camp Narache, Mulgore, right after entering the
world, with the copy of `0456417`. The lines that differ from the 15:08 run on Scoopz, without the
position, quest and profession lines:

```text
addon = 0.0.6-10-g0456417
level = 1
firstVisit.zone = 1412
firstVisit.map.0 = 1412 Mulgore (type 3)
firstVisit.explored = 3 of 3 zones (textures/hover-only): 1416 1/0, 1429 1/0, 1450 1/0
gold.money = 0
gear.slots = 5:6139/q0 7:6124/q0 16:35/q1
flightPaths.taxiMap = -1
flightPaths.nodes = 0 ()
home.bind = Camp Narache
```

The launch trace of that session:

```text
2026-10-15 15:23:24 FirstVisits enable+PLAYER_ENTERING_WORLD: taxi=false instance="none" map=1414 zone=missing -> no zone
2026-10-15 15:23:37 FirstVisits ZONE_CHANGED_NEW_AREA: taxi=false instance="none" map=1412 zone=1412 level=1 explored={1416,1429,1450} -> recorded
```

Notes:
- A brand-new character's map shows Alterac Mountains, Elwynn Forest and Moonglade explored too,
  one texture each and none hover-only, before it has taken a step. Its first look kept
  them in `state.visits`, so it would never get a first visit for them; since then a level 1
  character's first look takes no explored zones (§6.12). Both characters are Tauren Druids, so the
  cause may still be race or class.
- The journal's first entry is the first visit to Mulgore, marked as a first. The login's look,
  a second after `PLAYER_ENTERING_WORLD`, still found Kalimdor as the best map, and the zone change
  13 seconds later took Mulgore.
- `legacy.*` reads as on Scoopz: "Played in the WoW: Forever Beta" (64283) is completed on
  10/9/26 with *wasEarnedByMe* true, six days before this character existed. The flag doesn't
  tell an account's challenges from the character's.
- `rep.*` reads as on Scoopz (4 factions under 1 header, Darkspear Trolls Friendly), and
  `collections.*` too (pets and toys `0 of 0`, no toy). The error log has nothing new.
