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
