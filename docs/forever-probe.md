# Forever probe results

Output of `/ws probe`, copied from `WayscribeDB.probe` in the account SavedVariables file.
The interpretation is in [ARCHITECTURE.md §12](ARCHITECTURE.md#12-verify-on-the-forever-beta-run-ws-probe).

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
