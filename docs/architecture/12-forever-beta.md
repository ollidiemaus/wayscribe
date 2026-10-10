# 12. Verify on the Forever beta (run `/ws probe`)

Part of the [Wayscribe architecture](../ARCHITECTURE.md); other sections are listed there.

The probes ran on client `1.60.1` build `70235` (2026-10-06); the raw output is in
[forever-probe.md](../forever-probe.md). "Exists" means the API or event is there. Whether an event
actually *fires* for Vanilla content still needs a gameplay test; those are in
[ingame-tests.md](../ingame-tests.md).

| # | Question | Probe (build 70235) | Still open | Fallback if "no" |
|---|---|---|---|---|
| 1 | Do `ENCOUNTER_END` / `BOSS_KILL` fire for Vanilla dungeon bosses? | Both events exist. ForeverChronicle uses both and merges duplicates. | Kill a dungeon boss. | NPC-ID detection via `UNIT_HEALTH` on the current target (CLEU is not an option, §1). |
| 2 | Which profession API works? | ✅ `GetProfessions` / `GetProfessionInfo` (modern). ✅ With Skinning learned: the parent skill line **393**, rank 3/75, name "Kürschnerei"; it sits in `GetProfessions`' first slot (index 4). | Does First Aid show up in `GetProfessions`? | — |
| 3 | Does world position work outdoors? | ✅ `UnitPosition` works (instance 1 = Kalimdor). ✅ `C_Map.GetWorldPosFromMapPos` returns the same point. **UnitPosition's first return equals the world vector's `.x`.** ✅ The Footsteps transform gives exactly the client's map position. | Behavior inside instances and in combat (a trail survives a short gap). | Zone-relative `uiMapID + x,y`. |
| 4 | Does `C_QuestLine` return data for Vanilla quests? | `C_QuestLine.GetQuestLineInfo` exists. ❌ Nothing for two Mulgore chain quests (747, 752). | Recheck on new client builds. | Curated chains carry the feature (already the first provider). |
| 5 | Which values are secret, and when? | `issecretvalue` exists. `UnitLevel` is not secret out of combat. ForeverChronicle saw secret aura data and spellcast arguments. | Values in combat and instances. | `Compat.Safe` everywhere. Capture IDs and resolve names later. |
| 6 | Gather spell IDs, and does `GetLootSourceInfo` exist? | ✅ `GetLootSourceInfo` exists. ✅ All gather spell IDs exist and their names resolve in the client's language (deDE: Bergbau / Kräuterkunde / Kürschnerei; 1235236 = Kräutersammeln). | Which spell ID a gather cast actually reports, and whether it's secret. | Name match is built in (§6.4); item subclass fallback for nodes. |
| 7 | Does an LFG or dungeon-finder completion event exist? | `LFG_COMPLETION_REWARD` and `SCENARIO_COMPLETED` exist. | Whether they fire for Vanilla dungeons. | Final-boss data table (already the primary signal). |
| 8 | Do SavedVariables survive a round trip on the current client build? | ✅ Account and character files written on `/reload` and logout, `.bak` holds the previous save, the session was resumed after the reload. ✅ A full relog added a second session. | Retest on every new client build. | Missing-DB guard (§4.6). |
| 9 | Does `WorldMapFrame` take a MapCanvas data provider, and where do the lines land? | ✅ `has.worldMapCanvas`; the trail was drawn in the right place, above the explored-area art. `C_Map.GetMapPosFromWorldPos` answers with the continent (worked around). ✅ Lines at least 3 pixels long stay whole on the small map too. ✅ The map's icons are drawn over the lines. ✅ The journal button opens the map at the zone. | — | No overlay; the journal hides its map link. |
| 10 | Does `C_Map.GetMapChildrenInfo` list the zone maps, and how big is Azeroth then? | ✅ 50 zones: Kalimdor 23 (71 sq mi), Eastern Kingdoms 26 (45 sq mi), and Forever's **Zephras Isle** on a world map of its own (2991, 7 sq mi; `UiMap` 2521 under Azeroth). A short session read 0.1%, Mulgore 2.2%. | — | No "% of Azeroth walked" line; the rest of the Footsteps card stays. |
| 11 | Is `PanelTabButtonTemplate` there for the journal's tabs? | ✅ `has.panelTabs`; the tabs show under the journal like the default UI's. | — | Plain buttons under the frame. |
| 12 | Can a backup of megabytes be pasted back into an addon? | ✅ `OnChar` fires for every pasted character, also past the field's limit. The client inserts a paste character by character, about 2.6 ns per character the field already holds: a field without a limit grows with the square (55.6 s for 200 KB). Holding 32 bytes, 2,474,487 characters arrive in 2.8 s. A multi-line box can't draw 2.4 MB of text. | — | Split the backup by year (months are independent partitions). |
| 13 | Can a controller reach and use the journal? | ❌ Build 70245 (2026-10-08). Forever's controller mode only focuses windows its frame manager (`GamepadMode.FrameControlsManager`) knows, from `ShowUIPanel` or `FrameShown`; otherwise the focus button says "There is no interface window to focus". An addon can't read the controller itself (`Frame:EnableGamePadButton` is protected). A test build that called `FrameShown` for the login recap could be navigated, but every focus change raised "Wayscribe has been blocked from an action only available to the Blizzard UI": the manager and SmartNavigation then run tainted and call protected functions (`SmartNavigation:ShowCursor`/`HideCursor` call `SetGamePadCursorControl`). Closing the recap with the controller froze the client. Withdrawn (`git stash`: "controller support via FrameControlsManager"). | Recheck when Blizzard opens the manager to addons. | Keyboard and mouse only. |
| 14 | Can an addon take Alt+clicks on the world map and name a note in a popup? | Source of build 70291: `MapCanvasMixin:AddCanvasClickHandler` exists and calls handlers through `securecallfunction`; the map's strata and its own pin come from game rules (`WorldMapFrameStrata`, `WorldMapTrackingPinDisabled`). ✅ Build 70291 (2026-10-09): `worldMap.canvasClicks = true`, `worldMap.strata = MEDIUM`, `gameRule.worldMapTrackingPinDisabled = false` (the game's own pin is on). In game, Alt+click in and out of combat shows the popup in front of the map with no "blocked" message, and a plain click still zooms in. | — | `/ws mark` and New note still work; no Alt+click. |

Other findings:
- wago.tools lists build 70235 as product `wow_cn_beta`, so its DB2 tables (`DungeonEncounter`, `Map`,
  `SpellName`, `SkillLine`, `ItemSubClass`) can be read for this exact client. `StaticData/` cites them.
- `WOW_PROJECT_ID` is **18** on build 70235. Earlier beta builds reported 1 (Mainline), as recorded in
  AutoPotion. Code never branches on it.
- ScrollBox, the Settings API and the Addon Compartment are all available, and the UI uses them.
- Forever's characters have a **first name and a surname**. `UnitName` and `UnitFullName` return the
  surname as their second value, where other clients return the realm; `GetRealmName` still names the
  realm ([AllTheThings #2630](https://github.com/ATTWoWAddon/AllTheThings/issues/2630)). Wayscribe up
  to 0.6 stored the surname as the realm and named companions by their first name only.
  `Compat.has.surnames` (a second value from `UnitName("player")`) now joins both into the name;
  saved players are repaired at login. ✅ Confirmed on build 70245: `has.surnames = true`, and the
  probe character is saved as "Scoopz Scoopz" on "Classic Beta PvE" (before: "Scoopz" on "Scoopz").
