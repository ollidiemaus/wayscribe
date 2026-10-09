# Dungeon maps (plan)

A plan, nothing built yet. Forever has no dungeon maps. Wayscribe could draw them in the journal,
covered by fog that lifts as the character explores, and keep what was found, so a map can be read
again outside the dungeon. This page says whether that's possible on the client as it is
(build 70291, checked 2026-10-09), how it would work, and what still has to be tried in game.

## Verdict

**Possible, with one twist forced by the game.** The maps are still in the client's files, so
Wayscribe can show them without shipping any art. But Forever tells addons nothing about where the
player is inside an instance. So the fog can't lift step by step, as it does under Footsteps'
trails outdoors. It lifts **room by room**, when something the game reports places the player: the
entrance on arrival, each boss's room when the boss is engaged or killed, and named areas in the
few dungeons that have them. That is how the world map's own fog works too: it lifts a whole area
when you discover it, not a circle around your feet.

## What the client has

**1. No dungeon maps.** `UiMap.db2` of build 70291 holds 60 maps: the world, the continents, the
zones, cities and battlegrounds. None is a dungeon map (type 4), so `C_Map` knows no map for any
instance, and the world map shows none. Classic Era (1.15.9) is the same (54 maps).

**2. The art is still there.** The parchment maps that later expansions drew for the old dungeons
(12 tiles of 256 px, 1002 × 668 shown) are in build 70291's files. Forever's own tables
don't point to them; their file IDs come from retail's `UiMapArtTile` (build 12.1.0.69933). Fetched
for build 1.60.1.70291 from wago.tools and decoded, Ragefire Chasm (449736–449747) and the
Deadmines (449591…) are the familiar maps. An addon can show such a file with
`Texture:SetTexture(fileID)`, so **Wayscribe would ship file IDs, not images.**

| Instance | Retail map(s) with this art | Floors |
|---|---|---|
| Ragefire Chasm | 213 | 1 |
| Wailing Caverns | 279 | 1 |
| The Deadmines | 291, 292 | 2 |
| Shadowfang Keep | 310–316 | 7 |
| Blackfathom Deeps | 221–223 | 3 |
| The Stockade | 225 | 1 |
| Gnomeregan | 226–229 | 4 |
| Razorfen Kraul / Downs | 301 / 300 | 1 / 1 |
| Scarlet Monastery (four wings) | 302–305 | 4 |
| Uldaman | 230, 231 | 2 |
| Zul'Farrak | 219 | 1 |
| Maraudon | 280, 281 | 2 |
| Sunken Temple | 220 | 1 |
| Blackrock Depths | 242, 243 | 2 |
| Blackrock Spire | 250–255 | 6 |
| Dire Maul | 235–240 | 6 |
| Stratholme | 317, 318 | 2 |
| Scholomance (the old one) | 306–309 ("Legacy of Scholomance") | 4 |
| Molten Core, Onyxia's Lair | 232, 248 | 1, 1 |
| Blackwing Lair | 287–290 | 4 |
| Zul'Gurub, Ruins of Ahn'Qiraj | 233, 247 | 1, 1 |
| Ahn'Qiraj Temple | 319–321 | 3 |
| Naxxramas | 162–167 | 6 |

Retail also has maps for the dungeons Cataclysm and Mists rebuilt (Scarlet Halls, the new
Scholomance at 476–479). Forever's dungeons are the old ones, so the table picks the old layouts:
Scarlet Monastery's four wings and the "Legacy of Scholomance" maps show the old rooms (both
rendered and checked). Zul'Gurub's map is the one retail has, drawn after the Cataclysm rebuild,
so parts of it may differ from Forever's.

**3. Forever's new instances have no art,** as guides note for the Hall of Thanes. But the client
does have their **minimap images**. The Hall of Thanes' map file (WDT 7713294) lists 81 terrain
tiles, and their minimap textures (512 px) show its halls and caves from above. Tinted toward the
parchment, that could serve as a "survey sketch". Most new instances are built the same way (the
Ruins of Lordaeron, the Wetlands excavation site, Dalaran, the Burning of Andorhal). An instance
that is a single indoor building keeps its minimap images in `WMOMinimapTexture.db2` (156,027 rows
in build 70291) instead, and placing them needs the building's group bounds from its model file.
That is a spike of its own. Manor Mistmantle's map file lists nothing yet.

**4. No position inside instances.** Since patch 7.1, `UnitPosition` and `GetPlayerFacing` return
nil in instances ([warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/API_UnitPosition)), and
`C_Map.GetPlayerMapPosition` needs a map, which dungeons don't have. The author of
[Forever Simple World Map](https://www.curseforge.com/wow/addons/forever-simple-world-map) reports
the same on Forever. `GetUnitSpeed` gives a speed but no direction, so dead reckoning is out.
ARCHITECTURE §12 #3 still lists "behavior inside instances" as open, so Phase 0 checks it.

**5. What the game does tell inside:**
- **Entering:** `Compat.GetInstance()` gives the instance (`Map.db2` ID).
- **Bosses:** `ENCOUNTER_START` / `ENCOUNTER_END` / `BOSS_KILL` give the encounter ID. Wayscribe
  has recorded every kill since 0.2 (`BOSS_KILLED {encounterID, instanceID, …}`).
- **Named areas:** `GetSubZoneText()` / `ZONE_CHANGED_INDOORS`. But Forever's `AreaTable` gives
  most old dungeons a single area, the dungeon itself. Only the Deadmines (Ironclad Cove),
  Zul'Gurub (11 areas), Ruins of Ahn'Qiraj (6), Ruins of Lordaeron (4), the Wetlands excavation
  site (4) and Dalaran have areas inside.

**6. Where the bosses are.** Retail's `JournalEncounter` places each boss on these same maps (on
the Ragefire Chasm and Deadmines maps, the skulls in the art sit exactly there). 151 of the 280
encounter entries Forever has for the old instances match by name. The rest are in dungeons retail
rebuilt (Ragefire Chasm, Shadowfang Keep, Scarlet Monastery, Scholomance, the Stockade, Razorfen
Kraul and Downs) or listed on other maps (Zul'Farrak, Zul'Gurub, Ahn'Qiraj), and would be placed
by hand. Forever's encounter IDs are its own (Rhahk'Zor is 2741, not
retail's 2967), so matching happens once, offline, by name.

## How it would work

**Sections.** Each floor is cut into sections. Each section has one or more **triggers**:
- `enter`: the entrance, revealed on arrival;
- `enc:<encounterID>`: a boss's room and the way to it, revealed when the boss is engaged
  (`ENCOUNTER_START`, so a wipe still counts: you got there) or killed;
- `area:<name>`: a named area, revealed on entering it.

Sections are cut automatically and then adjusted by hand: the walkable parchment of the art is split
by walking distance to the anchors (entrance, bosses), so a corridor between two bosses is half
theirs each. It is fully drawn once both ends were reached, and trash halls lift with the nearest
boss.

**Only what was found.** Per character, nothing is revealed from data alone. Runs made before this
release count: at first login, the `BOSS_KILLED` and `DUNGEON_*` records already in the journal
reveal their sections, just as quest chains back-fill. A dungeon with a map is listed once the
character has been inside.

**No "you are here".** Without a position there is no arrow. The section reached last is
highlighted instead, and opening the map inside an instance shows that section's floor.

**Data.**
- Saved facts, `WayscribeCharDB.charted = { [instanceID] = { [trigger] = firstSeen } }`. The
  facts are triggers, not section numbers, so redrawing sections later never loses anything. It is
  tiny (a few hundred entries for a character who has seen every dungeon). The backup's generic walk
  carries it. Like notes, it needs no schema change.
- A journal record, `DUNGEON_CHARTED {instanceID}`, when the last section of a dungeon is
  revealed: "Charted Wailing Caverns completely", with the first-time mark, and a line on Your
  Year's dungeon card.
- Static data, `StaticData/DungeonMaps.lua`: per instance, its floors (the 12 art file IDs, or the
  minimap tiles and their grid), a grid of section numbers (64 × 42 cells of about 16 px,
  run-length packed), and the sections' triggers. That is about 40 KB for every old dungeon and
  raid. A script generates it from wago.tools tables, and an authoring page (local, not packaged)
  paints the sections on the composed maps. **The repository holds no Blizzard art**; the composed
  images stay on the developer's disk.

**Drawing.**
- The map: 12 textures by file ID in a 4 × 3 grid, cropped to 1002 × 668. Minimap-based maps:
  their tiles, desaturated and tinted.
- The fog: per grid cell. Hidden cells are covered with parchment-colored fog, merged into runs per
  row, with soft sprites along the edge so the border looks inked, not blocky. That is a few hundred
  textures at most, drawn once when a floor is shown. A section that is revealed while the map is
  open fades out. The same grid would take real positions if Forever ever gives them.
- **Where:** a new journal tab. Left page: the dungeons entered, each with "62% charted", its first
  clear and its runs (from the records already kept). Right page: the dungeon's floors and bosses
  (killed, how often, first on which day). Opening a map spreads it across both pages: the book's
  spread is about 3:2, like the art. Inside an instance it also opens with a key binding, `/ws map`
  and a button on the world map.

## Phases

| Phase | Scope | Done when |
|---|---|---|
| **0. Proof in game** (no code) | The test lines below, on the beta. | Both map pieces are visible; the probe shows what an instance gives. |
| **1. Tooling** | Generator (wago.tools tables → floors, file IDs, boss anchors), composed maps on disk, section authoring page; data for Ragefire Chasm, the Deadmines and Wailing Caverns. | The three dungeons' sections look right on their maps. |
| **2. 0.8 Dungeon maps** | `charted` facts with back-fill, `ENCOUNTER_START` and area triggers in the Dungeons tracker, `DUNGEON_CHARTED`, the journal tab, the map with fog, binding and `/ws map`, unit tests. | A Ragefire Chasm run lifts the entrance and four bosses' rooms, survives a `/reload`, reads the same outside, and the backup carries it. |
| **3. Every old dungeon and raid** | Data only: about 25 instances, 70 floors. | Each checked once in game against its run. |
| **4. Forever's new instances** | Minimap-based maps, with the Hall of Thanes as the spike. | The Hall of Thanes is drawn and lifts by its four bosses. |

**Phase 0 test lines.** On the beta, out of combat, paste:

```text
/run local f=CreateFrame("Frame",nil,UIParent)f:SetAllPoints()f:SetFrameStrata("DIALOG")for i,id in ipairs{449744,7726146}do local t=f:CreateTexture()t:SetSize(320,320)t:SetPoint("CENTER",(i*2-3)*170,0)t:SetTexture(id)end WST=f
```

You should see two squares: on the left, the middle of the Ragefire Chasm map (parchment, a
crossroads with a skull); on the right, a piece of the Hall of Thanes seen from above.
`/run WST:Hide()` removes them. A German client might show German map labels.

Then, **inside any dungeon**, paste:

```text
/run print(UnitPosition("player"))print(GetPlayerFacing(),GetUnitSpeed("player"),C_Map.GetBestMapForUnit("player"),GetSubZoneText(),GetInstanceInfo())
```

The first line is expected to be empty, and the second to start with `nil`. If numbers come back
instead, Forever gives positions after all, and the fog could follow your steps.

## Risks

- **The art is from later versions.** Its skulls and labels may not match Forever: Ragefire
  Chasm's four skulls mark the Cataclysm bosses' rooms, not Taragaman's and Bazzalan's. The map
  itself is right; the skulls are part of the picture and can't be removed.
- **Files in the build aren't always on the disk.** The client may stream files it doesn't have yet,
  so a map could show blank the first time. Phase 0 shows it.
- **Wings that share an instance** (Scarlet Monastery, Dire Maul, Blackrock Spire, Stratholme):
  arriving doesn't say which wing, so their entrances lift with the wing's first boss.
- **Blizzard adds maps after all.** If `C_Map.GetBestMapForUnit` ever returns a dungeon map inside an
  instance, the feature should use it, with the player's position. Then the fog could follow the
  player's steps. `Compat` checks for it.
- **Fan art** (the Hall of Thanes map by Santiago Reyes, Atlas Forever's maps) only with the
  artist's permission. The minimap route avoids the question.

## Decisions for you

1. Is room-by-room good enough, or not worth it without step-by-step?
2. The tab: its name ("Dungeons"? "Maps"?) and its place (between Notes and Your Year?).
3. Does an engaged boss reveal its room (my suggestion), or only a kill?
4. Raids too, or dungeons first?
5. Forever's new instances from minimap images in 0.8, or later?
