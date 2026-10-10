# 6. Trackers

Part of the [Wayscribe architecture](../ARCHITECTURE.md); other sections are listed there.

Each tracker is one file containing its record types, its event handling, its settings label and
default. **Adding a feature = one file + locale strings + one TOC line.** The settings page builds its
toggle automatically from the tracker registry.

```lua
-- The shape of a tracker file (simplified from Trackers/Level.lua)
local _, ns = ...
local L, Compat, Store = ns.L, ns.Compat, ns.Store

ns.RecordTypes:Register("LEVEL_UP", {
    version = 1, category = "progress",
    fields  = { level = "number", map = "number?" },
    rollup  = function(rollup, data) rollup.maxLevel = math.max(rollup.maxLevel or 0, data.level) end,
    render  = function(data) return L.LEVEL_UP:format(data.level) end,
})

local Level = ns.Trackers:New("Level", { label = L.TRACKER_LEVEL })

function Level:OnEnable() self:RegisterEvent("PLAYER_LEVEL_UP") end

function Level:PLAYER_LEVEL_UP(newLevel)
    local level = Compat.Safe(newLevel, "number")   -- secret or wrong type -> nil
    if level then
        Store:Append("LEVEL_UP", { level = level, map = Compat.GetPlayerMapID() })
    end
end
```

The real file also keeps a saved `level` state, so duplicate or replayed events can't create a
second entry, and it falls back to `UnitLevel` when the event argument is secret.

## 6.1 Session (always on, internal)
- Initial login opens a session. On `/reload` (`isReloadingUi`), the session is resumed. Logout stamps
  `e`.
- Produces `months[m].sessions`, from which play time is derived on read. This drives the login
  recap and Your Year's time card (most active month and day, longest session).

## 6.2 Level ups
- `PLAYER_LEVEL_UP(level)` → `LEVEL_UP {level, map}`.

## 6.3 Professions (learn + skill gains)
- **Snapshot-diff pattern.** On `SKILL_LINES_CHANGED`, `CHAT_MSG_SKILL` (used only as a trigger; the
  text is never parsed, so it works in every locale) and `TRADE_SKILL_LIST_UPDATE`, take a debounced
  snapshot with `Compat.GetProfessionSnapshot()`, diff it against `state.professions`, and save the new
  snapshot. The first snapshot after login waits 3 s, because profession data may still be loading.
- The very first snapshot of a character is a **silent baseline**: professions learned before
  Wayscribe are not dated today.
- New skill line → `PROFESSION_LEARNED {skillLine}` (milestone, `firstKey`).
- Skill crossing 75/150/225/300 → `PROFESSION_RANK {skillLine, rank}` (milestone). The month rollup
  keeps the highest rank per profession, and the professions learned, for Your Year.
- Every point gained → `Store:Count("skill", skillLine, delta)`. The day view shows "Mining +23".
- A profession missing from one snapshot stays in `state.professions`: its data may just not be loaded
  yet, and dropping it would report it as newly learned later. A lower rank (unlearned and learned
  again) records nothing.
- Because the snapshot is persisted, changes made while the addon was disabled are reconciled at the
  next login without duplicates.
- Forever's `SkillLine.db2` has child lines (2937–2948) under the classic professions, like Retail's
  expansion tiers. Whatever `GetProfessionInfo` returns is used as the key; on build 70235 that is
  the classic parent (393 for Skinning, §12 #2). Names come from
  `C_TradeSkillUI.GetTradeSkillDisplayName`, then the name cached in the snapshot.

## 6.4 Gathering (ores, herbs, skins)
- `UNIT_SPELLCAST_SUCCEEDED` (registered for `"player"` only) with a gather spell opens a **gather
  window** of 5 s, tagged as mining, herbalism or skinning. A spell matches by ID from
  `StaticData/Gathering.lua`, or by **name**: the names of those IDs are looked up at enable time in
  the client's language, so every rank and Forever's own versions count. On build 70235 the Vanilla
  IDs are named Mining, Herbalism and Skinning, and Forever adds 1235230 (Mining) and 1235236 (Herb
  Gathering).
- `LOOT_READY` inside that window snapshots the loot slots (`GetLootSlotLink`, plus `GetLootSourceInfo`
  for the source GUID). `LOOT_SLOT_CLEARED` counts only what was actually looted, so full bags don't
  inflate the numbers. `LOOT_CLOSED` ends the window.
- A node counts once per source GUID, so a vein mined in several casts (or a doubled `LOOT_READY`) is
  one node.
- **Fallback** when the cast is hidden (secret spell ID): loot from a `GameObject` source containing
  Metal & Stone (7/7) or Herb (7/9) items counts as mining or herbalism. Skinning needs the cast.
- Output is counters only: `Store:Count("gather", itemID, qty)` and `Store:Count("nodes", kind, 1)`.
  Item class and subclass IDs from `C_Item.GetItemInfoInstant` are locale-free.
- Item names load asynchronously. `Compat.GetItemName` requests a missing one and watches
  `GET_ITEM_INFO_RECEIVED` / `ITEM_DATA_LOAD_RESULT` until it arrives, then fires `ITEM_NAMES_LOADED` so
  the journal redraws.

## 6.5 Boss kills
- `ENCOUNTER_END(encounterID, name, difficultyID, groupSize, success)` with `success == 1`, or
  `BOSS_KILL(encounterID, name)` → `BOSS_KILLED {encounterID, name, instanceID, difficultyID, roster}`
  with `firstKey = "BOSS:"..encounterID`.
- Both events stay registered everywhere (they are rare), so world bosses count too. `instanceID` is
  only stored inside an instance.
- The localized boss name is **captured from the event**: no API maps an encounter ID back to a name.
- The same encounter reported again within 120 s is the second event of one kill and is skipped.
  Events aren't replayed after a `/reload`, so an in-memory window is enough. (A `dedupeKey` per
  dungeon run would have made Boss kills depend on the Dungeons tracker being on.)

## 6.6 Dungeon and raid runs
- A state machine driven by `PLAYER_ENTERING_WORLD` and `ZONE_CHANGED_NEW_AREA` plus
  `Compat.GetInstance()`. Party and raid instances are tracked.
  - **Enter an instance:** start or resume `state.activeRun`. It resumes if the instanceID is the
    same and at most 30 min have passed since we left, which covers reloads, disconnects and corpse
    runs. `PLAYER_LOGOUT` stamps the leave time, so a relog is judged the same way. While inside,
    `ENCOUNTER_END`, `BOSS_KILL`, `LFG_COMPLETION_REWARD` and `SCENARIO_COMPLETED` are registered.
  - **Roster:** the union of group members present at any boss kill, interned through `Players`.
    (No `GROUP_ROSTER_UPDATE`: someone who left before the first kill isn't a companion.)
  - **Completion:** a final encounter from `StaticData/Dungeons.lua` was killed (or the optional
    `LFG_COMPLETION_REWARD` / `SCENARIO_COMPLETED` fired). The run stays open while the player is
    inside, so later kills still join it, and closes on leaving as
    `DUNGEON_COMPLETED {instanceID, name, difficultyID, wing, roster, bosses, dur}` with
    `firstKey = "DUNGEON:"..instanceID[..":"..wing]`. The record is dated at the final kill.
  - **Leave without the final boss:** the run waits outside for 30 min (a timer, plus every zone
    change), then closes as `DUNGEON_VISITED` dated at leaving. This also covers instances without
    data: missing data degrades to "visited", it never causes an error.
  - **Not worth an entry:** a visit without kills shorter than 60 s, and zoning back in without
    kills within 30 min after a clear of the same instance.
  - **Reset:** the same boss killed again more than 2 min later means a new lockout, so the old
    run closes and a new one starts.
- **Finals data** (`StaticData/Dungeons.lua`) comes from `DungeonEncounter.db2` of build 70235 via
  wago.tools: all Vanilla dungeons and raids. Wings that share one instanceID (Scarlet Monastery,
  Blackrock Spire, Dire Maul, Stratholme) map their final boss to a wing key. Some dungeons list one
  encounter per difficulty variant (Blackfathom Deeps, Gnomeregan, Sunken Temple).
- The localized instance name is captured from `GetInstanceInfo` at the start of the run.
- The renderer turns these records into "First clear of Ragefire Chasm with Xy, Ab and Cd (42 min)".
- Rollups: `dungeons[instanceID]` and `companions[playerID]` (both run types count toward companions).

## 6.7 Quest chains
- Every `QUEST_TURNED_IN` does `Store:Count("quests", questID)`: the quest IDs turned in per day.
  That cheap fact is what chains are derived from.
- Pluggable **chain providers**, asked in order; the first match wins:
  1. **Curated data** (`StaticData/QuestChains.lua`): well-known Vanilla chains (attunements, keys,
     storylines, class quests, legendaries), each with one final quest per faction or variant. Its
     names are locale strings (`CHAIN_<id>`).
  2. **`C_QuestLine`** (if `Compat.has.questLines`): the turned-in quest is the last of a quest line
     with at least two quests. The line's name is captured at turn-in. On build 70235 the API has
     no data for Vanilla quests (§12 #4), so in practice only curated chains are recognized.
- The record is `QUEST_CHAIN_COMPLETED {chain | questLine, quest, title?}` with
  `firstKey = "CHAIN:"..chain` or `"QUESTLINE:"..questLine`. A chain is recorded once.
- **Retroactive.** The quest ID list makes curated chains reproducible. When a release adds chains,
  it bumps `StaticData.QuestChainsVersion`; the next login compares it with `state.questChains`
  and back-fills. `/ws rebuild` back-fills too (on the `REBUILT` message). A back-filled record is
  dated at the end of the day its final quest was turned in (or now, if that's today) and flagged
  `bf`: the journal shows no time of day for it. A quest that already completed a chain, through
  any provider, isn't credited again.

## 6.9 Deaths
- `PLAYER_DEAD` → `DEATH {map, sub?, c?, x?, y?}` in the journal (category *adventure*): the
  uiMapID from `C_Map.GetBestMapForUnit`, the subzone's name from `GetSubZoneText` and, outdoors,
  the corpse's continent and position in whole world yards, the same coordinates as Footsteps'
  trails. Inside instances there is no position, so only the map is kept.
- Rendered "Died in Red Cloud Mesa, Mulgore" / "In Red Cloud Mesa, Mulgore gestorben". The zone's
  name is looked up when shown (`Compat.GetMapName`); the subzone is kept as text, because no API
  names a subzone later (like boss names, §13).
- **No killer.** Who dealt the killing blow is only in the combat log, which Forever doesn't allow
  addons (§1), so an entry says where and when, not who.
- A second `PLAYER_DEAD` within 10 s is the same death.
- **On the Footsteps map**, a skull marks each death with a position on the days shown (the same
  Today / Last 7 days / All / picked day as the trails), through the record type's `markers`
  (§6.8).
- The month rollup counts deaths (per type) and deaths per map, for Your Year's most dangerous place.
