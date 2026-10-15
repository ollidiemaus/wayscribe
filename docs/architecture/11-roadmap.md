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
| **0.9 Duels** | Duels in the journal, a Duels tab (all duels, by class, each opponent) and a Your Year card, from the challenge (`StartDuel` hook, `DUEL_REQUESTED`) and the client's result line (§6.10). | Win, loss, flight, a declined challenge and German lines (unit tests); duels in game (open, [ingame-tests.md](../ingame-tests.md#duels)). |
| **1.0 Launch** (in progress) | Trackers for Forever's launch (§6.11–6.21): first visits, gold, reputation, notable gear, Legacy Challenges, flight paths, guild, home, collections, PvP rank (stretch). The launch probe in `/ws probe`, a dev-mode trace (`/ws trace`). | Probed and unit-tested, and each fails silent (§6.11); a short beta session on a fresh character; the rest in game after launch ([ingame-tests.md](../ingame-tests.md)). |

## 1.0 Launch plan

Decided on 2026-10-15. The beta ends on 2026-10-21 (PDT) and Forever launches on 2026-11-04
(November 5, 00:00 CET). There is no client in between, and beta characters don't carry over.

- **One branch** (`1.0-launch`), one commit per tracker, one pull request.
- **Order, which is also the cut line:** first visits, gold, reputation, notable gear, Legacy
  Challenges, flight paths, guild, home, collections, PvP rank (stretch). Whatever isn't done by
  the freeze waits until after launch.
- **By Oct 17:** the launch probe. `/ws probe` reads every API these trackers need and shows its live
  values (§12 row 16).
- **By Oct 19, evening:** every tracker's event handling is done. After that, only texts, cards and
  looks change until launch.
- **Oct 19 to 21:** one session on a fresh level 1 character, in the stress test on Oct 19 if it lets
  players in, or on Oct 20/21. The checklist is at the top of [ingame-tests.md](../ingame-tests.md).
- **Built so far:** first visits (§6.12), gold (§6.13).
- **Left out for launch:** screenshots (not wanted), talents (Retail-style trees plus Forever's
  Legacy trees, with no clear moment), learned spells (too many), honor kills (only an unloaded frame
  reads them), battlegrounds (no battleground browser in Forever's UI), and the game's "Discovered"
  messages for subzones (first visits cover zones).

## Next
- **First public release:** CurseForge and GitHub Releases are set up; pushing the first tag
  publishes it (see [DEVELOPMENT.md](../DEVELOPMENT.md#releasing)).
- **The archive** (Phase B, §4.7), once `/ws stats` from real players says it's needed.
- **Tracker ideas** after launch (each a single-file addition): talent milestones, PvP honor kills,
  battlegrounds, learned spells as a counter, Legacy Track levels.
- **Footsteps:** a fog-of-war look on the map from the walked squares (§6.8).
- **Dungeon maps:** the old dungeons' map art is still in Forever's files; maps in the journal
  whose fog lifts room by room (plan: [dungeon-maps.md](../dungeon-maps.md)).
