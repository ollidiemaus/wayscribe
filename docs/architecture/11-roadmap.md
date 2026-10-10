# 11. Releases and roadmap

Part of the [Wayscribe architecture](../ARCHITECTURE.md); other sections are listed there.

All releases so far are pre-releases, tested on the Forever beta. What still needs checking in the
game is in [ingame-tests.md](../ingame-tests.md).

| Release | Scope | Proven by |
|---|---|---|
| **0.1 Foundation** | Core, Compat + probe, the data layer (Store, Schema, RecordTypes, Index, Players, Codec) with tests. Session + Level trackers. Bare journal list. Slash commands. | Tests; the probe from the Forever beta; a level-up survives logout, `/reload` and relog with no duplicates. |
| **0.2 Adventurer** | Professions, Gathering, Bosses, Dungeons (roster + firsts). Settings page, minimap button, keybind, login recap. | A full Ragefire Chasm run with a mid-run `/reload` (in game, still open). |
| **0.3 Chronicler** | The spellbook-style journal (filters, day pages), quest chains with back-fill, dates in English and German. | A curated chain added after the fact back-fills on the right day (unit test). |
| **0.4 Footsteps** | Trails on the world map, the day → map link, deaths and journeys as markers. | 2 h of play under 10 KB packed (unit test: 3.2 KB); no measurable frame-time cost (in game). |
| **0.5 Your Year** | Year cards, December prompt, % of Azeroth walked. Text export. | The recap renders from rollups alone (unit test). |
| **0.6 Backup** | A restorable backup string, and restoring it into an empty or missing journal (§4.8). | A simulated year survives backup, wipe and restore (unit test); a missing journal restored in game. |
| **0.7 Notes** | The player's own notes: a Notes tab in the journal, whose `/way` lines are markers on the world map (Alt+click, `/ws mark`), carried by the backup (§4.9, §7.9). | Notes survive relog, backup and restore, and a missing journal with only notes is guarded (unit tests); Alt+click places a note in game, with no taint error. |

**Next:**
- **First public release:** CurseForge and GitHub Releases are set up; pushing the first tag
  publishes it (see [DEVELOPMENT.md](../DEVELOPMENT.md#releasing)).
- **The archive** (Phase B, §4.7), once `/ws stats` from real players says it's needed.
- **Tracker ideas** (each a single-file addition): gold earned and spent, reputation milestones,
  first mount, zones discovered, epic loot, talent milestones, PvP honor kills, guild join,
  screenshots (`SCREENSHOT_SUCCEEDED` → "took a screenshot here").
- **Footsteps:** a fog-of-war look on the map from the walked squares (§6.8).
- **Dungeon maps:** the old dungeons' map art is still in Forever's files; maps in the journal
  whose fog lifts room by room (plan: [dungeon-maps.md](../dungeon-maps.md)).
