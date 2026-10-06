# Wayscribe — Architecture Plan

An automatic, per-character journal for **WoW Forever**. It records what happens while you play,
groups it by day, and powers a login recap, a **Footsteps** travel map and a yearly "Wrapped".

> The name **Wayscribe** was decided on 2026-10-06, after checking that it's free on CurseForge, Wago,
> WoWInterface and GitHub. It's baked into the SavedVariables names, the folder name and the slash
> commands.

---

## 1. Design principles

These six rules drive every decision below. If a future feature conflicts with one of them, change the
feature, not the rule.

1. **Store facts, derive narratives.** We persist small, typed facts (`LEVEL_UP {level=12}`), never
   finished sentences. Text, "first time" badges, rollups and recaps are computed from facts. This keeps
   the DB small and localizable, and lets a later release reinterpret old data. For example, a new
   quest-chain definition can light up chains that were completed months ago.
2. **One write path.** Trackers never touch SavedVariables. Every journal write goes through `Store`,
   every Footsteps trail through `Paths`; both validate, partition and broadcast what they keep.
3. **Never destroy data you don't understand.** If loading or migrating fails, or the data comes from a
   newer addon version, the addon goes **read-only (safe mode)**. Because the client saves whatever is
   in memory on logout, a crash at load followed by a "fresh start" would wipe the journal. Safe mode
   prevents that.
4. **Detect capabilities, not flavors.** Forever runs the Mainline engine but ships Vanilla content, and
   its `WOW_PROJECT_ID` has already changed once during the beta (1 in early builds, 18 in build 70235).
   Branching on flavor broke AutoPotion (`a70aac7`). Code asks `Compat.has.X`, never `isRetail`.
5. **Pay only for what's enabled.** A disabled tracker unregisters all of its events. Context-only events
   (roster, encounters) are registered only while that context is active, for example inside an instance.
6. **Failures stay local.** Each tracker runs in an error boundary. A broken tracker logs itself, disables
   itself and leaves the rest of the addon running.

### Hard constraints of the platform

| Fact | Consequence for the design |
|---|---|
| SavedVariables (SV) are loaded once before `ADDON_LOADED` and written **only** on clean logout or `/reload`. There is no flush API. | Everything lives in memory during play. A client crash loses that session, and nothing can prevent it. Writes are cheap table inserts. |
| SV files are Lua source parsed at login. Many small tables and unique constants are slow to load, and very large SV files have historically hit `constant table overflow`. | Bulk data (Footsteps trails) is **string-packed**. Records stay compact. Old data can move to a load-on-demand archive. |
| `SavedVariablesPerCharacter` loads only the current character's file. | The journal is per-character by nature, so it gets automatic partitioning for free. |
| Metatables, functions and userdata are not saved. | The SV tables hold plain data only. Behavior lives in modules that read and write those tables. |
| **Confirmed:** registering `COMBAT_LOG_EVENT_UNFILTERED` on Forever triggers a protected-action popup (ForeverChronicle had to remove it). | **Never register CLEU.** Use high-level events such as `ENCOUNTER_END`, `BOSS_KILL`, `PLAYER_LEVEL_UP`, `QUEST_TURNED_IN` and `LOOT_*`. |
| **Confirmed:** Forever has Midnight-style **secret values** (`issecretvalue` exists). Spellcast event arguments, aura data, and some unit, map and quest values can be secret at times. Comparing, concatenating or storing a secret value raises an error. | Every game value passes `Compat.Safe(v)` at the tracker boundary: it returns `nil` for secrets and wrong types. `Store` validation rejects secrets as a second line of defense. A missing value degrades the record, never the session. |
| **Reported:** early Forever beta builds wrote SavedVariables to disk but sometimes didn't restore them at the next startup. According to a Blizzard forum report, this stopped from client build `1.60.1.70009`. | A missing character DB is never silently treated as a first install while there's evidence that data existed (see §4.6, missing-DB guard). The client build is stored in `meta` for diagnosis. |

---

## 2. Layer overview

```mermaid
flowchart LR
    WoW["WoW events"] --> T["Trackers<br/>(one per feature)"]
    C["Compat<br/>capabilities + API shims"] -.-> T
    SD["StaticData<br/>dungeons, chains, gather spells"] -.-> T
    T -->|"Store:Append / Store:Count<br/>Paths:AddSegment"| S["Store + Paths<br/>(single write paths)"]
    S --> DB[("SavedVariables<br/>WayscribeDB / WayscribeCharDB / WayscribeFootstepsDB")]
    S --> IX["Indexes + Rollups<br/>(rebuildable caches)"]
    S -->|"RECORD_ADDED"| BUS(("Internal bus"))
    BUS --> UI["UI: Journal, Login recap,<br/>Footsteps, Wrapped"]
    UI -->|"read API"| S
    RT["RecordTypes registry<br/>schema, render, rollup"] -.-> S
    RT -.-> UI
```

| Layer | Responsibility | May depend on |
|---|---|---|
| **Core** | Namespace, lifecycle, module base, event frames, internal bus, error boundary, logging, time/day keys, geometry (pure math on trails) | — |
| **Compat** | Capability detection (`Compat.has.*`), thin API shims (position, professions, instance info), `/wayscribe probe` | Core |
| **Data** | `Store`, `Paths` (Footsteps trails), `Schema` (migrations, safe mode), `RecordTypes`, `Index`, `Players` (interning), `Codec` | Core |
| **StaticData** | Plain tables: dungeon → final encounter, quest chains, gather spell IDs | — |
| **Trackers** | Translate game events into facts, holding only the minimal state they need | Core, Compat, Data (write API), StaticData |
| **UI** | Journal window, login recap, settings, minimap, keybind, Footsteps map, Wrapped | Core, Data (read API), RecordTypes |

Dependencies point one way only. UI never calls trackers, and trackers never call UI. They talk through
the Store and the bus.

---

## 3. Core runtime

### 3.1 Lifecycle

| Event | What happens |
|---|---|
| `ADDON_LOADED` (ours) | `Schema:Load()` creates or migrates the three SV tables, decides on safe mode and builds the in-memory indexes. |
| `PLAYER_LOGIN` | Resolve `Compat` capabilities. Enable each tracker whose setting is on. Register settings, minimap button and slash commands. |
| `PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)` | The Session tracker starts or resumes a session. The login recap is shown if this is the initial login and the first one of the day. |
| `PLAYER_LOGOUT` | Close open sessions, segments and runs, and stamp `lastSeen`. This handler must be tiny and must not error, because it is the last chance to write before the SV file is saved. |

### 3.2 Modules and event dispatch

- A **Module** base class gives each tracker its own hidden event frame plus
  `self:RegisterEvent(ev)`, `self:RegisterUnitEvent(ev, "player")` and `self:UnregisterAllEvents()`.
  The client dispatches natively, so we don't need a central fan-out loop. With per-module frames,
  `RegisterUnitEvent` filters never collide.
- Handlers are `self[event](self, ...)`, called through `xpcall` with our error handler, which feeds the
  [error boundary](#34-error-boundary).
- Use `RegisterUnitEvent(..., "player")` for every `UNIT_*` event. Otherwise the event fires for every
  nameplate and party member.
- Trackers with **context-scoped events** subscribe on context enter and unsubscribe on context exit.
  For example, the Dungeon tracker registers `ENCOUNTER_END` and `GROUP_ROSTER_UPDATE` only while inside
  an instance.

### 3.3 Internal bus and deferral

- Tiny callback registry (or CallbackHandler-1.0). Messages: `RECORD_ADDED`, `COUNTER_CHANGED`,
  `DAY_CHANGED`, `SETTINGS_CHANGED`, `SAFE_MODE`, `REBUILT` (after `/ws rebuild`, so trackers can
  derive what older facts imply, see §6.7), `LOGOUT` (sent before the canary is stamped, so what it
  writes is counted), and for Footsteps `PATH_ADDED`, `PATH_LIVE`, `PATH_POINT`, `PATH_WIPED` (§6.8).
- `ns.Defer(fn)`: work that doesn't need to happen in combat (UI refresh, index maintenance beyond O(1),
  loading the archive) is queued and flushed on `PLAYER_REGEN_ENABLED`.
- UI refresh is **coalesced**: a dirty flag plus one `C_Timer.After(0, ...)`, so 20 loot events produce
  one redraw.
- Noisy events (`SKILL_LINES_CHANGED`, `BAG_UPDATE`) are **debounced**: snapshot once, ~0.5 s after the
  burst.

### 3.4 Error boundary

- Errors are written to a ring buffer in `WayscribeDB.log` (last 50 entries, each with timestamp, module,
  message and trimmed stack). The `/wayscribe log` command shows them.
- A module that errors 10 times in one session is disabled for the rest of the session, with a single
  chat notice.
- In dev mode (`/wayscribe dev`), errors are also forwarded to `geterrorhandler()` so BugSack sees them.

### 3.5 Time

- All timestamps are `time()` epoch seconds.
- Day key: integer `YYYYMMDD` (`20261003`). Month key: `YYYYMM`. Both are computed from local time when
  the record is written. Days roll over at **calendar midnight** (decided). There's no configurable
  rollover hour, so a day key never depends on a setting.
- Short dates (login recap) follow a setting: locale default (deDE → `03.10.2026`) or a manual
  override. Journal pages spell the date out from locale tables, because `date("%A")` is always
  English in the client: "Saturday, October 3, 2026" / "Samstag, 3. Oktober 2026". The weekday is
  computed from the day key (Sakamoto's method), so it needs no `time()` call.
- Times of day follow the game's 24-hour clock setting (`timeMgrUseMilitaryTime`), else the
  language's habit (enUS `2:05 PM`, deDE `14:05`).

---

## 4. Data layer

The data layer is the most important part of the addon and gets the most tests.

### 4.1 SavedVariables split

| SV | Scope | Contents | Why separate |
|---|---|---|---|
| `WayscribeDB` | Account | Settings, minimap position, error log, per-character canaries (§4.6) | Small. Shared across characters. A separate file, so it can vouch for the character files. |
| `WayscribeCharDB` | Character | Journal records, counters, sessions, indexes, tracker state | The core data. |
| `WayscribeFootstepsDB` | Character | Footsteps trails (string-packed), written only through `Paths` | The largest and fastest-growing data. Isolating it means it can be wiped, pruned or moved to load-on-demand without touching the journal. It has its own schema version and read-only guard (§4.6). It lives in the same file as the journal (one `Wayscribe.lua` per character), so a file that fails to load takes both. |

### 4.2 `WayscribeCharDB` layout

```lua
WayscribeCharDB = {
    schema = 1,                         -- migration version (see 4.6)
    meta = {
        guid = "Player-…", name = "…", realm = "…", class = "MAGE", race = "Troll",
        created = 1759400000,           -- first time the addon saw this character
        seq = 1234,                     -- last issued record id (monotonic)
        addonVersion = "0.2.0",         -- last version that wrote this DB
    },

    -- Resumable tracker state (survives /reload and relog)
    state = {
        session      = { m = 202610, i = 1 },              -- the open session: month + index
        level        = 12,
        professions  = { [186] = { rank = 52, max = 75, name = "Mining" } },  -- snapshot (§6.3)
        activeRun    = { instanceID = 389, name = "Ragefire Chasm", start = 1759490500,
                         bosses = { 2732, 2733 }, killedAt = { [2732] = 1759490800, … },
                         roster = { 3, 7 }, left = nil, completed = nil },     -- §6.6
        lastCleared  = { instanceID = 389, ts = 1759493000 },
        lastRecapDay = 20261003,                           -- login popup bookkeeping (§7)
    },

    -- Interned players (records hold small integers instead of names)
    players = {
        [3] = { guid = "Player-…", name = "Xy", realm = "…", class = "PRIEST" },
    },

    -- Partitioned journal: month -> day -> records + counters
    months = {
        [202610] = {
            days = {
                [20261003] = {
                    records = {
                        { id = 1201, ts = 1759490900, type = "DUNGEON_COMPLETED", v = 1,
                          data = { instanceID = 389, roster = { 3, 7 }, dur = 2710 }, first = true },
                        { id = 1202, ts = 1759493100, type = "LEVEL_UP", v = 1,
                          data = { level = 12, map = 1411 } },
                    },
                    counters = {                  -- high-frequency facts are aggregated, not listed
                        gather = { [2770] = 23, [2835] = 4 },     -- itemID -> count
                        nodes  = { mining = 12 },
                        quests = { [840] = 1, [841] = 1 },        -- questID -> turned in today
                    },
                },
            },
            sessions = { { s = 1759489000, e = 1759497000 } },
            rollup   = { levelsGained = 2, dungeons = { [389] = 1 }, bosses = 4,
                         gather = { [2770] = 23 }, companions = { [3] = 1, [7] = 1 },
                         playSeconds = 8000, activeDays = 1 },
        },
    },

    firsts = { ["DUNGEON:389"] = 1201, ["PROF:186"] = 1103 },   -- first-occurrence index
}
```

Why this shape:

- **Month and day partitions** keep every read and write bounded. Rendering a day touches one table.
  The yearly recap touches 12 rollups. Moving a closed year into an archive moves whole month tables,
  with no per-record migration.
- **Records vs counters.** A *record* is something worth its own journal line, such as a level-up, a
  dungeon or a boss. A *counter* is something that happens a lot, such as ore looted or quests turned in.
  Counters are summed per day and shown as one summary line ("Gathered 23× Copper Ore, 4× Rough Stone").
  This keeps the DB small. The rule of thumb: a new tracker that would emit more than ~20 records per hour
  should use counters.
- Records carry `v` (the record-type version) so renderers can handle or upcast older shapes.
- **Player interning:** dungeon groups repeat, and a small integer is much cheaper than a name or GUID
  repeated in every record. It also makes "top companions" a simple count.

### 4.3 Record types: the extension point

Every record type is registered once, and that registration is its contract:

```lua
ns.RecordTypes:Register("DUNGEON_COMPLETED", {
    version  = 1,
    category = "adventure",               -- journal filter group
    fields   = { instanceID = "number", roster = "table", dur = "number?" },
    firstKey = function(data, r) return "DUNGEON:" .. data.instanceID end,  -- enables "First time" badge
    rollup   = function(monthRollup, data, r) ... end, -- O(1) update of the month rollup
    merge    = function(yearRollup, monthRollup) ... end, -- combines type-specific rollup fields
    render   = function(data, r) ... end,  -- -> text, icon (localized, at display time)
    markers  = function(data, r) ... end,  -- optional: { { c, x, y, icon, title }, ... } on the map (0.4)
    upcast   = { [1] = function(data) ... end },  -- optional: version 1 shape -> version 2
})
```

The Store uses `fields` to validate (strict in dev mode, cheap type checks in release), plus `firstKey`
and `rollup` to maintain indexes. The UI uses `render`. Neither layer has a per-type `if/else`.

### 4.4 Write path

```lua
Store:Append(type, data [, opts])   -- milestone record; returns the record
Store:Count(path, key, n)           -- counters: Store:Count("gather", itemID, 3)
Store:SetState(tracker, tbl)        -- resumable tracker state
```

`Append` options: `ts` (default now), `dedupeKey`, `simulated` (`/ws simulate`, record flag `sim`)
and `backfill` (derived later from older facts; record flag `bf`, see §6.7). `Append` runs these
steps, each O(1):

1. Refuse if in safe mode.
2. Look up the record type. An unknown type is a programming error and is logged.
3. Build the record: `id = ++meta.seq`, `ts`, `v`.
4. Validate.
5. Optionally check `opts.dedupeKey` against a small in-memory recent-keys set. This guards against
   double-firing events (`ENCOUNTER_END` plus `BOSS_KILL`), and against trackers replaying state after
   a `/reload`.
6. Insert into `months[m].days[d].records`.
7. Update `firsts` (and set `r.first = true` if new), the month rollup and the in-memory day index.
8. Fire `RECORD_ADDED`.

### 4.5 Read path

```lua
Store:GetDayKeys()                    -- sorted array (built in memory at load, never persisted)
Store:GetDay(dayKey)                  -- records (time-sorted) + counters
Store:GetSessions(fromTs, toTs)       -- overlapping sessions; the open one ends now
Store:GetMonthSummary(ym) / Store:GetYearSummary(y) -- rollups + play time; year = sum of 12 months
Store:GetFirst(key)
```

- The day index is rebuilt at load from month and day keys. That costs a few hundred iterations per year
  of data, so there's nothing to persist or corrupt.
- `firsts` and `rollup` **are** persisted for speed, but they are treated as caches. `/wayscribe rebuild`
  (and any migration that needs it) recomputes them from records and counters. A rollup schema change is
  therefore just "bump version and rebuild".
- The journal UI asks only for the days that are visible, so the ScrollBox is virtualized.

### 4.6 Schema, migrations, safe mode

```text
ADDON_LOADED
 ├─ DB missing, canary says data existed → SAFE MODE + warning (don't overwrite; see guard below)
 ├─ DB missing             → create fresh at CURRENT_SCHEMA
 ├─ db.schema > CURRENT    → SAFE MODE (data from a newer addon version — never downgrade-write)
 └─ db.schema < CURRENT    → for v = schema+1 .. CURRENT:
                                ok = pcall(migrations[v], db)   -- builds new tables, swaps at end
                                if not ok → SAFE MODE, log, stop
```

- Migrations are **build-then-swap**. They construct the new structure off to the side and assign it at
  the end, so a failure never leaves the DB half-mutated. They are idempotent, and each one has a fixture
  test (old shape → new shape).
- In **safe mode**, trackers stay disabled, the journal is read-only (if the data was readable), a banner
  explains the problem, and `/wayscribe log` shows the error. The SV table is left exactly as it was loaded,
  so logout writes back the same data. The client also keeps `<Addon>.lua.bak` as a one-step backup.
- If `meta.guid` doesn't match `UnitGUID("player")` (for example, a WTF folder copied to another
  character), the journal is shown read-only until the player confirms with `/ws accept`.
- **Missing-DB guard.** The account-wide `WayscribeDB.characters[guid]` keeps a tiny canary per
  character: name, realm, last `seq`, last save time. It's written to a different SV file than the
  journal.
  - If the character DB loads as `nil` or empty but the canary shows records, the journal file
    failed to load (or was moved). The addon goes into safe mode, records nothing, and warns the
    player right away. An addon can't stop the client from rewriting the file at logout, but the
    file on disk is still intact during this session. The warning says to copy
    `WTF/…/SavedVariables/Wayscribe.lua` (or its `.bak`) somewhere safe **before logging out**.
  - The same canary detects **renames and realm transfers**. Per-character SV files are stored under
    the character name, so a renamed character starts with an empty file. Wayscribe recognizes the
    GUID and shows how to move the old file.
  - This doesn't help if *every* SV file fails to load (canary and journal look like a first
    install), so an export or backup option stays on the roadmap.
  - **Trails** (`WayscribeFootstepsDB`, 0.4) get the same checks with their own outcome: a newer schema, a
    failed migration, an unexpected shape, or trails missing while the canary counted some
    (`characters[guid].paths`, the trail `seq`) make **only the trails** read-only, with a chat
    warning. The journal keeps recording. `/ws accept` starts new trails. When the journal itself
    is missing, its own guard has already warned, and the trails are left alone.
- Migrations need **no persistent snapshot inside the SV**. Build-then-swap happens in memory, so if
  the client crashes before saving, the old file is still on disk and the migration simply runs again
  next login. (ForeverChronicle keeps a full DB copy inside its SV during migrations, which doubles
  the file size. This design avoids that.)

### 4.7 Size budget and growth plan

Estimates for an active player (about 2 h/day):

| Data | Per day | Per year | Notes |
|---|---|---|---|
| Journal records + counters | ~2–4 KB | ~1 MB | 20–50 records/day, counters aggregated |
| Footsteps trails (packed, simplified) | ~3–6 KB | ~1–2 MB | See §6.8 |
| Indexes / rollups | — | < 50 KB | Months × small tables |

That's roughly 2–3 MB per character per year, which is comfortable for a few years. The growth plan is
designed now but built later:

- **Phase A (v1):** everything lives in the main addon. Partition keys are already month-based.
- **Phase B (when real data says so):** a load-on-demand companion, `Wayscribe_Archive`, with its own
  per-character SV. Once a month, out of combat at login, closed **years** (and Footsteps months older
  than N) move from the hot DB into the archive. Browsing an archived year runs
  `C_AddOns.LoadAddOn("Wayscribe_Archive")` on demand. Because rollups stay in the hot DB, the yearly recap
  never needs the archive.
- `/wayscribe stats` reports record counts and approximate serialized size per SV, so we can decide when to
  build Phase B from real numbers.

---

## 5. Compat layer

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
    taxiState       = …,   -- UnitOnTaxi (0.4)
    worldMapCanvas  = …,   -- the world map's data provider extension point (0.4)
}
Compat.Safe(v [, expectedType])  -- -> v, or nil if issecretvalue(v) or the type is wrong. Every game value goes through this.
Compat.Call(fn, ...)             -- pcall + Safe on each return value, for APIs that may error or return secrets
Compat.GetPlayerWorldPosition()  -- -> continentID, x, y in world yards (UnitPosition, else map position); nil in instances
Compat.GetWorldPosFromMapPos(mapID, u, v) -- -> continentID, x, y of a map point (0.4)
Compat.GetMapAtWorldPos(continentID, x, y) -- -> the most detailed uiMapID there (0.4)
Compat.GetParentMap(mapID)       -- -> parentMapID (0.4)
Compat.IsOnTaxi() / Compat.IsDeadOrGhost()
Compat.HasWorldMapCanvas()       -- WorldMapFrame takes MapCanvas data providers (0.4)
Compat.GetProfessionSnapshot()   -- -> { [skillLineID] = { rank, max, name } }
Compat.GetInstance()             -- -> instanceID, type, difficultyID, name
Compat.GetGroupMembers()         -- -> array of { guid, name, realm, class }
Compat.GetLootSlots()            -- -> { [slot] = { itemID, quantity } }, sourceGUID
Compat.GetItemName(itemID)       -- -> name, or nil and the item is requested (ITEM_NAMES_LOADED follows)
Compat.GetItemClass(itemID)      -- -> classID, subclassID (locale-free)
Compat.GetSpellName(spellID) / Compat.GetSkillLineName(skillLineID)
Compat.GetQuestTitle(questID)    -- C_QuestLog title, nil until the client has the quest
Compat.GetQuestLineEnd(questID)  -- questLineID, name if questID is the last quest of a line (0.3)
Compat.Uses24HourClock()         -- the game's clock setting, nil without one
```

**`/wayscribe probe`** prints a capability report (which APIs exist and what they return right now). We run
it on the Forever beta and paste the result into `docs/forever-probe.md`. Every "verify on beta" item in
§12 maps to one probe line.

---

## 6. Trackers (v1 feature set)

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

### 6.1 Session (always on, internal)
- Initial login opens a session. On `/reload` (`isReloadingUi`), the session is resumed. Logout stamps
  `e`.
- Produces `months[m].sessions` and `playSeconds` in the rollup. This drives the login recap and the
  "most active day" stat in Wrapped.

### 6.2 Level ups
- `PLAYER_LEVEL_UP(level)` → `LEVEL_UP {level, map}`.

### 6.3 Professions (learn + skill gains)
- **Snapshot-diff pattern.** On `SKILL_LINES_CHANGED`, `CHAT_MSG_SKILL` (used only as a trigger; the
  text is never parsed, so it works in every locale) and `TRADE_SKILL_LIST_UPDATE`, take a debounced
  snapshot with `Compat.GetProfessionSnapshot()`, diff it against `state.professions`, and save the new
  snapshot. The first snapshot after login waits 3 s, because profession data may still be loading.
- The very first snapshot of a character is a **silent baseline**: professions learned before
  Wayscribe are not dated today.
- New skill line → `PROFESSION_LEARNED {skillLine}` (milestone, `firstKey`).
- Skill crossing 75/150/225/300 → `PROFESSION_RANK {skillLine, rank}` (milestone). The month rollup
  keeps the highest rank per profession for Wrapped.
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

### 6.4 Gathering (ores, herbs, skins)
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

### 6.5 Boss kills
- `ENCOUNTER_END(encounterID, name, difficultyID, groupSize, success)` with `success == 1`, or
  `BOSS_KILL(encounterID, name)` → `BOSS_KILLED {encounterID, name, instanceID, difficultyID, roster}`
  with `firstKey = "BOSS:"..encounterID`.
- Both events stay registered everywhere (they are rare), so world bosses count too. `instanceID` is
  only stored inside an instance.
- The localized boss name is **captured from the event**: no API maps an encounter ID back to a name.
- The same encounter reported again within 120 s is the second event of one kill and is skipped.
  Events aren't replayed after a `/reload`, so an in-memory window is enough. (The plan had
  `dedupeKey = "boss:"..encounterID..":"..runStart`, but that would make Boss kills depend on the
  Dungeons tracker being on.)

### 6.6 Dungeon and raid runs
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

### 6.7 Quest chains
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
### 6.8 Footsteps

The travel map, built in 0.4: `Trackers/Footsteps.lua` records, `UI/FootstepsMap.lua` draws, and the
data layer stores *trails* (`Data/Paths.lua`, `WayscribeFootstepsDB`). Trails are the source of truth;
everything else is derived from them or counted next to them.

**Sampling** (`Trackers/Footsteps.lua`). A `C_Timer.NewTicker(1)` runs only while the feature is on,
the player is outdoors (instance type `none`) and trails can be saved. It doesn't use `OnUpdate`.
- `Compat.GetPlayerWorldPosition()` → `continentID, x, y` in world yards (`UnitPosition`, else the
  map position through `C_Map.GetWorldPosFromMapPos`). World coordinates are independent of any one
  map, so the same trail renders on zone and continent maps.
- A point is kept only after moving **8 yards** from the last kept one, so a standing player costs
  one API call per second and writes nothing. The trail being recorded lives in memory
  (`Paths:SetLive`) and grows on screen while the map is open.
- A **trail** (segment) ends on: a loading screen, a continent change, a jump faster than 100 yd/s
  from the previous second's sample (a teleport; measured from the last *kept* point, a hearthstone
  cast standing still looked like a walk in game), taxi start or end (flight trails are flagged), death (ghosts aren't followed), more
  than 60 s without moving, **midnight** (so every trail belongs to one day), 1800 recorded points
  (bounds the work at the end), turning the feature off, and logout (through the bus's `LOGOUT`).
  A position that is hidden for a moment (combat?) doesn't end the trail unless the pause gets long.
- The next trail **starts where the last one ended** if the player is within 30 yards of it on the
  same continent, so pauses, flights and midnight leave no gaps on the map.
- When a trail ends it is simplified with **Douglas-Peucker** (3 yards), rounded to whole yards and
  packed with the polyline codec. A trail shorter than 8 yards (a pause right after a reload) isn't
  stored.
- Flights are recorded only with *Record flight paths* on (default on).
- **Journeys by spell.** A cast (`UNIT_SPELLCAST_SUCCEEDED`, player only) of a travel spell from
  `StaticData/Travel.lua` notes where it was cast: the hearthstones (with Forever's own), Astral
  Recall, Teleport: Moonglade, the mage teleports (and Forever's Teleport: Dalaran), and the
  engineering and other transporters (Everlook, Gadgetzan, and Forever's New Avalon and Mt. Hyjal),
  matched by ID or by name in the client's language. IDs from build 70235's `SpellName.db2`. When a trail next starts more than 30 yards
  away (or on another continent) within 60 s, the journey is recorded as
  `TELEPORT {spell, map, sub, c, x, y, fc?, fx?, fy?}` (category *travel*), dated at the arrival:
  "Hearthstone to Bloodhoof" / "Ruhestein nach Bloodhoof". The arrival's subzone is read 2 s later,
  once the client has caught up. Cast inside an instance, only the arrival has a position. A jump
  without a recognized cast (a summon, a boat's loading screen, a secret spell ID) only breaks
  the trail.

**Storage** (`WayscribeFootstepsDB`, written only through `Data/Paths.lua`):
```lua
WayscribeFootstepsDB = {
    schema = 1, seq = 42,                   -- seq: trails ever stored (the canary's count, §4.6)
    months = { [202610] = { days = { [20261003] = {
        { c = 1, t = 1759490000, d = 640, f = nil, p = "Bx3_a9…" },   -- continent, start, seconds moving, flight, points
    } } } },
}
```
- Day partitions under month partitions, like the journal: a day's trails need no date math, and a
  closed year moves as whole month tables.
- `p` is the **polyline codec** (`Data/Codec.lua`): whole yards, delta-encoded, zigzag, varints in a
  64-character printable alphabet. Arithmetic only (no `bit` library), unit-tested in plain Lua 5.1.
- **Distance** goes into the journal as the day counter `travel` (`ground` / `flight` → yards),
  rendered "Traveled 2.4 miles · Flight paths: 5.1 miles" (km in German). The journal, the login
  recap and Wrapped get distances without decoding a single trail.
- **Measured:** two hours of simulated questing (rides, running around between fights, standing in
  town; about 80 minutes of movement) pack into **about 3.2 KB** in 10 trails. The 0.4 exit criterion
  is 10 KB; the unit test `footsteps > size budget` keeps it.

**Rendering** (`UI/FootstepsMap.lua`): a `MapCanvas` data provider on `WorldMapFrame`, the official
extension point that HandyNotes also uses.
- The map's corners (0,0), (1,0) and (0,1) in the world (three `C_Map.GetWorldPosFromMapPos` calls,
  cached per map) give an affine **world → map transform** (`Core/Geometry.lua`), so drawing needs no
  API call per point. Maps without world coordinates (the whole world) draw nothing.
- Lines (pooled `Line` regions on a frame over the canvas, above the explored-area art) are
  **clipped** to the map (Liang-Barsky) and simplified to the zoom (level of detail: about one screen
  pixel). Their width is divided by the canvas zoom, so they look the same at every zoom.
- **No line shorter than 3 pixels** (found in game): on the small map next to the quest log, the
  trail being recorded (8 yards a point, under a pixel there) broke up, while fullscreen and zoomed
  maps were fine. Shorter steps are merged until they are long enough, and one tail line runs from
  the last drawn point to the player. After a zoom by 1.5× or more, the trails are drawn again for
  the new scale once the zoom has settled.
- Trails are drawn **newest first** up to 5000 lines, in a coroutine that works at most 4 ms per
  frame, so even "All" never stalls the map. The trail being recorded is drawn line by line.
- Ground trails are dark red, flights thinner and blue; today's trails (or the picked day's) are
  strong, older ones lighter.
- **Filters:** Today (default), Last 7 days, All, Off, set by a button in the map's upper right corner
  (Forever shows its own coordinates in the lower left)
  (a menu where the client has `MenuUtil`, else each click picks the next one) or in settings.
- **Markers:** record types with a `markers` function (§4.3) put icons on the map for the days
  shown, each with its title and time (and date, if not today) on mouseover, sized for the screen
  at every zoom: a skull for a death (§6.9), the spell's icon where a journey by spell left and
  where it arrived. The map reads them through `Store:GetRecordsOfType`; a new one while the map is
  open shows at once.
- **Day → path link:** a journal day with trails shows a *Show on the map* button. It opens the world
  map at the most detailed map that holds the whole day (the zone, else its parents) and shows that
  day until the map closes. `C_Map.GetMapPosFromWorldPos` answers with the continent, so
  `Compat.GetMapAtWorldPos` walks down with `C_Map.GetMapInfoAtPosition` to find the zone.

**Coverage** (the "% of Azeroth walked" stat and a fog-of-war look) moves to 0.5 with Wrapped, its
only consumer. It will be rasterized from the trails into chunked bitsets in a coroutine and cached
in memory, persisted only if profiling says so.

### 6.9 Deaths
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
- The month rollup's record count per type already counts deaths, for Wrapped.

---

## 7. UI

| Piece | Design |
|---|---|
| **Journal window** | Built from the default UI's own pieces, so it looks like Forever's spellbook: `PortraitFrameTemplate` (title, book portrait, close button), Forever's two-page spellbook parchment (`spellbook-page-left/right-c60`, else the retail `spellbook-background-evergreen-*`), spellbook headers (`SystemFont_Huge2` in `SPELLBOOK_FONT_COLOR` over the `spellbook-divider` ornament), spellbook page buttons with "Page 3/12" (`PAGE_NUMBER_WITH_MAX`), the `WowStyle1FilterDropdownTemplate` filter menu and `MinimalScrollBar`s that hide when not needed. Each piece is checked first (`C_XMLUtil.GetTemplateInfo`, `C_Texture.GetAtlasInfo`); without it, plain colors, a dialog border and toggle chips stand in (`UI/Theme.lua`). Forever's page art carries the spellbook's dark top bar in its upper 9% and dark rims at the edges: the pages start under the title bar, the filter menu sits in that bar, and the text lives on a "paper" frame inside the rims (shares of the page size measured from the textures, so it scales with the window). Movable and resizable; size and position are kept in `settings.journal`. Left page: "Scoopz's journal" above the virtualized **day list** (`ScrollBox` + `DataProvider`), newest first, grouped by month; without ScrollBox, a fixed set of rows follows the selection. Right page (`UI/DayView.lua`): the long date, "Today · played 2 h 10 min", the milestones in time order with their time and category marker, then counter summaries, then the day's sessions. Page 1 is the oldest day. Category filters are saved in `settings.journalHidden`. A reader on the newest day follows a new day as it starts. A day with Footsteps trails shows *Show on the map* at the bottom of its page (§6.8). There is no tab bar: Footsteps lives on the world map, and Wrapped (0.5) decides whether the journal gets tabs. |
| **World map** | Footsteps trails and death skulls on `WorldMapFrame` through a MapCanvas data provider, plus a "Footsteps: Today" button that picks the filter (§6.8, §6.9). Without the data provider API, nothing is added and the journal hides its map link. |
| **Login recap** | On `isInitialLogin` and `state.lastRecapDay ~= today`, 3 s after the loading screen, show the previous session: date, duration, rendered milestones and the counter totals of its day(s) (counters are per day, so they can include another session that day). Simulated entries are left out; an empty session shows nothing. Buttons: *Open journal* (at that day), *Close*, and a *Don't show at login* checkbox wired to the setting. Setting `showLoginRecap` defaults to **on**. `/ws recap` shows it any time. |
| **Settings** | Blizzard `Settings` API: `RegisterVerticalLayoutCategory`, and `RegisterProxySetting` for every control, so the page reads and writes `ns.Options` / `ns.Trackers` and never owns data. Sections: **General** (login recap, minimap button, date format dropdown), **Tracking** (one toggle per tracker, generated from the registry; Footsteps is one of them), **Footsteps** (what the world map shows, record flight paths, delete all trails with a confirmation popup), **Data** (stats, error log, rebuild indexes, reset with a confirmation popup and a reload; reset deletes the trails too). Without the API the page is skipped and `/ws settings` says so. |
| **Minimap button** | LibDataBroker-1.1 + LibDBIcon-1.0, position and hidden flag in `WayscribeDB.settings.minimap`. Placeholder icon: `Interface\Icons\INV_Misc_Book_09`. Left-click toggles the journal, right-click opens settings. Skipped when the libraries are missing. The Addon Compartment entry comes from the TOC (`AddonCompartmentFunc`), so it works without libraries. |
| **Keybind** | `Bindings.xml`: `WAYSCRIBE_TOGGLE` under the AddOns category, unbound by default and configurable in the game's Keybindings menu. `BINDING_HEADER_WAYSCRIBE` and `BINDING_NAME_WAYSCRIBE_TOGGLE` are localized. |
| **Slash** | `/wayscribe` or `/ws` (toggle), plus `settings`, `recap`, `probe`, `stats`, `log`, `rebuild`, `dev`, `simulate <TYPE> …`, `accept`. |
| **Wrapped** | See §8. |

All UI listens to bus messages. None of it polls.

---

## 8. Yearly recap ("Wrapped")

- Data comes from `Store:GetYearSummary(year)` (12 month rollups), plus `firsts` and Footsteps coverage.
  It's cheap and needs no archive.
- It's shown as a card slideshow (next and previous). Cards include:
  - Levels gained (from → to) and the day you hit max level
  - Dungeons cleared, with your most-run dungeon and its first clear date
  - Bosses defeated
  - Top 3 companions (most shared runs)
  - Ores, herbs and skins totals, plus the top item
  - Professions learned and maxed
  - Quest chains completed
  - Distance traveled and % of Azeroth walked (Footsteps)
  - Most active month and day, and total play time
- It becomes available from December 1st, with a one-time "Your 2026 is ready" prompt. It can also be
  opened any time from the tab for any past year.
- New cards plug in through a `RecapCards:Register{ id, order, build = function(yearRollup) … end }`
  registry. It's the same extension pattern as trackers.

---

## 9. Repository layout

```text
Wayscribe.toc
Bindings.xml               -- key binding (loaded by the client, not listed in the TOC)
embeds.xml                 -- libs in Libs/ (fetched by the packager via .pkgmeta, git-ignored)
Locales/   enUS.lua deDE.lua
Core/      Init.lua Log.lua Time.lua Geometry.lua Bus.lua Options.lua Module.lua Trackers.lua Slash.lua Lifecycle.lua
Compat/    Compat.lua Probe.lua
Data/      Codec.lua RecordTypes.lua Players.lua Index.lua Store.lua Paths.lua Schema.lua
StaticData/ Dungeons.lua Gathering.lua QuestChains.lua Travel.lua
Trackers/  Session.lua Level.lua Professions.lua Gathering.lua Bosses.lua Dungeons.lua
           QuestChains.lua Footsteps.lua Deaths.lua
UI/        Journal.lua LoginRecap.lua Settings.lua Minimap.lua
           Theme.lua DayView.lua FootstepsMap.lua Wrapped.lua
tests/     run.lua testlib.lua wow_stubs.lua serialize.lua <area>_spec.lua …
docs/      ARCHITECTURE.md forever-probe.md
.pkgmeta  .luacheckrc  .github/workflows/{ci.yml,release.yml}
```

TOC essentials:

```text
## Interface: 16001
## Title: Wayscribe
## Notes: An automatic journal of your character's adventures.
## Author: ollidiemaus
## Version: @project-version@
## SavedVariables: WayscribeDB
## SavedVariablesPerCharacter: WayscribeCharDB, WayscribeFootstepsDB
## IconTexture: Interface\Icons\INV_Misc_Book_09
## AddonCompartmentFunc: Wayscribe_OnAddonCompartmentClick
```

The load order in the TOC is Core → Compat → Data → StaticData → Trackers → UI. Load order is the only
dependency mechanism in WoW, so it must match the layer diagram.

---

## 10. Libraries and tooling

- **Libraries (minimal):** localization is a small in-house table (`Locales/*.lua`). Since 0.2,
  LibStub, CallbackHandler-1.0, LibDataBroker-1.1 and LibDBIcon-1.0 power the minimap button. They are
  `.pkgmeta` externals that the packager fetches into `Libs/` (git-ignored), and they are **optional at
  runtime**: an unpackaged copy without `Libs/` loses only the minimap button. `/ws probe` lists the
  loaded versions.
  - No AceDB: the Store has requirements AceDB doesn't cover (partitioning, migrations, safe mode).
  - No AceAddon: the Module base is about 60 lines.
  - No AceLocale: two locales don't need it. Revisit if CurseForge community translations are wanted.
- **Static checks:** `luacheck` with a WoW globals list. The `.vscode` Lua settings come from AutoPotion.
  Keep UI builder functions small: Lua 5.1 allows at most 60 upvalues per function, and ForeverChronicle
  shipped a window that failed to load because of it.
- **Unit tests:** a dependency-free runner (`lua tests/run.lua`) with `tests/wow_stubs.lua` (fake clock,
  `CreateFrame` that can fire events and accepts any widget method so UI files load, `C_Timer`,
  `issecretvalue`, plus instance, group, profession, loot, item and spell doubles). It runs on Lua 5.1 in CI and on any
  local Lua 5.1+. Codec, Store, Schema/migrations, Index rebuild, Players interning, trackers and
  renderers are all exercised, so this is where "very stable read/write" gets proven. A test-only
  serializer round-trips the DB the way the client writes SavedVariables, which proves it holds plain
  data only. Migration tests use frozen fixture DBs from every past schema.
- **CI:** `ci.yml` runs luacheck and the tests on Lua 5.1 on every push and PR. `release.yml` is the
  BigWigsMods packager on tags, as in your other addons. `package-as: Wayscribe` keeps the folder name
  capitalized to match `Wayscribe.toc`, since the repository is the lowercase `wayscribe`.
- **In-game dev tools:** `/ws simulate LEVEL_UP level=12` (developer mode only) injects records through the real write path,
  flagged as test data and removable with `/ws simulate clear`,
  `/wayscribe stats`, `/wayscribe log`, `/wayscribe probe`, and `/wayscribe rebuild`.

---

## 11. Roadmap

| Release | Scope | Exit criteria |
|---|---|---|
| **0.1 Foundation** | Scaffolding, Core, Compat + probe, Data layer (Store, Schema, RecordTypes, Index, Players, Codec) with tests. Session + Level trackers. Bare journal list. Slash commands. | Tests green. Probe report from the Forever beta committed. A level-up survives logout, `/reload` and relog with no duplicates. |
| **0.2 Adventurer** | Professions, Gathering, Bosses, Dungeons (roster + firsts). Settings page, minimap button, keybind, login recap. | A full Ragefire Chasm run produces the expected entries, including after a mid-run `/reload`. |
| **0.3 Chronicler** | Journal UI polish (book look, filters, day view), quest chains (providers + retroactive rebuild), dates localized deDE/enUS. | A curated chain added after the fact back-fills correctly. |
| **0.4 Footsteps** | Sampler, segmenting, simplification, codec, world-map overlay, day → path link. Deaths in the journal and as skulls on the map. | 2 h of play stays under ~10 KB packed. No measurable frame-time cost. |
| **0.5 Wrapped** | Recap cards, December prompt, Footsteps coverage ("% of Azeroth walked"). Text export of the journal (a backup the player keeps outside WoW). Archive (Phase B) if `/wayscribe stats` from real users justifies it. | The recap renders from rollups alone. |

**Future tracker ideas** (each is a single-file addition): gold earned and spent, reputation
milestones, first mount, zones discovered, epic loot, talent milestones, PvP honor kills, guild join,
screenshots (`SCREENSHOT_SUCCEEDED` → "took a screenshot here").

---

## 12. Verify on the Forever beta (run `/ws probe`)

The first probe ran on client `1.60.1` build `70235` (2026-10-06), the 0.2 and 0.3 probes on the same build. The raw output is in
[forever-probe.md](forever-probe.md). "Exists" means the API or event is there. Whether an event
actually *fires* for Vanilla content still needs the matching gameplay test; those are listed per
release in [ingame-tests.md](ingame-tests.md).

| # | Question | Probe (build 70235) | Still open | Fallback if "no" |
|---|---|---|---|---|
| 1 | Do `ENCOUNTER_END` / `BOSS_KILL` fire for Vanilla dungeon bosses? | Both events exist. ForeverChronicle uses both and merges duplicates. | Kill a dungeon boss (0.2). | NPC-ID detection via `UNIT_HEALTH` on the current target (CLEU is not an option, §1). |
| 2 | Which profession API works? | ✅ `GetProfessions` / `GetProfessionInfo` (modern). ✅ With Skinning learned: the parent skill line **393**, rank 3/75, name "Kürschnerei"; it sits in `GetProfessions`' first slot (index 4). | Does First Aid show up in `GetProfessions`? | — |
| 3 | Does world position work outdoors? | ✅ `UnitPosition` works (instance 1 = Kalimdor). ✅ `C_Map.GetWorldPosFromMapPos` returns the same point. **UnitPosition's first return equals the world vector's `.x`.** ✅ 0.4: the Footsteps transform gives exactly the client's map position. | Behavior inside instances and in combat (0.4 keeps a trail through a short gap). | Zone-relative `uiMapID + x,y`. |
| 4 | Does `C_QuestLine` return data for Vanilla quests? | `C_QuestLine.GetQuestLineInfo` exists. ❌ The 0.3 probe got nothing for two Mulgore chain quests (747, 752). | Recheck on new client builds. | Curated chains carry the feature (already the first provider). |
| 5 | Which values are secret, and when? | `issecretvalue` exists. `UnitLevel` is not secret out of combat. ForeverChronicle saw secret aura data and spellcast arguments. | Values in combat and instances. | `Compat.Safe` everywhere. Capture IDs and resolve names later via `ns.Defer`. |
| 6 | Gather spell IDs, and does `GetLootSourceInfo` exist? | ✅ `GetLootSourceInfo` exists. ✅ All gather spell IDs exist and their names resolve in the client's language (0.2 probe, deDE: Bergbau / Kräuterkunde / Kürschnerei; 1235236 = Kräutersammeln). | Which spell ID a gather cast actually reports, and whether it's secret. | Name match is built in (§6.4); item subclass fallback for nodes. |
| 7 | Does an LFG or dungeon-finder completion event exist? | `LFG_COMPLETION_REWARD` and `SCENARIO_COMPLETED` exist. | Whether they fire for Vanilla dungeons. | Final-boss data table (already the primary signal). |
| 8 | Do SavedVariables survive a round trip on the current client build? | ✅ Account and character files written on `/reload` and logout, `.bak` holds the previous save, the session was resumed after the reload. ✅ A full relog added a second session (0.2). | Retest on every new client build. | Missing-DB guard (§4.6). |
| 9 | Does `WorldMapFrame` take a MapCanvas data provider, and where do the lines land? | ✅ `has.worldMapCanvas`; the trail was drawn in the right place, above the explored-area art. `C_Map.GetMapPosFromWorldPos` answers with the continent (worked around). ✅ Lines at least 3 pixels long stay whole on the small map too. ✅ The map's icons are drawn over the lines. ✅ The journal button opens the map at the zone. | — | No overlay; the journal hides its map link. |

Other findings:
- wago.tools lists build 70235 as product `wow_cn_beta`, so its DB2 tables (`DungeonEncounter`, `Map`,
  `SpellName`, `SkillLine`, `ItemSubClass`) can be read for this exact client. `StaticData/` cites them.
- `WOW_PROJECT_ID` is **18** on build 70235. Earlier beta builds reported 1 (Mainline), as recorded in
  AutoPotion. Code never branches on it.
- ScrollBox, the Settings API and the Addon Compartment are all available, so 0.2 and 0.3 can use them.

---

## 13. Decisions

### Decided (2026-10-06)

- **Flavor scope:** Forever only for now. The TOC declares `## Interface: 16001`. The capability-based
  Compat layer still keeps other flavors cheap to add later.
- **Day boundary:** calendar midnight in local time (§3.5). A session that runs past midnight
  continues on the next day's page.
- **Name:** Wayscribe. SVs `WayscribeDB` / `WayscribeCharDB` / `WayscribeFootstepsDB` (planned as
  `WayscribePathDB`, renamed in 0.4 before release), slash
  `/wayscribe` (alias `/ws`). "Diary" was taken on CurseForge.
- **Companion names:** stored and shown. There's no "hide names" toggle for now.

- **Travel map name:** **Footsteps** (in-game label). "Hero's Path" is taken by another addon and
  is Nintendo's term. (The code first kept `HeroPath` as an internal name; 0.4 dropped it, see below.)

### Decided during 0.2

- **Raids are runs too.** The Dungeons tracker follows party and raid instances. Raid finals (Ragnaros,
  Onyxia, Nefarian, Hakkar, Ossirian, C'Thun, Kel'Thuzad) are in the data table, and a raid night
  without its final boss is a "visited" entry with the bosses killed.
- **A run is written when it ends**, not at the final kill: the entry then has every boss and
  everyone who was there. It closes as soon as the player leaves after the final boss, so it still
  appears right away.
- **Captured names.** Boss and instance names are stored as captured from the client (localized),
  like quest titles in §6.7, because no API resolves those IDs to names later.
- **Libraries are packager externals**, not committed, and optional at runtime.

### Decided during 0.3

- **Curated chains before quest lines.** The plan asked `C_QuestLine` first. Curated chains now
  win: their names are chosen and translated, and only they can be matched again later, so a live
  entry and a back-filled one always agree on the chain's key.
- **Back-fill is automatic.** A release with new chain definitions back-fills at the next login
  (version check), not only on `/ws rebuild`, so players see old chains without knowing the command.
- **Back-filled entries carry no time.** Only the day of a turn-in is saved, so they're dated at the
  end of that day, flagged `bf`, and shown without a time.
- **No tabs yet.** With only the journal there is no tab bar; Footsteps (0.4) and Wrapped (0.5)
  bring it. (0.4 put Footsteps on the world map instead, see below.)
- **The default UI's look, verified first.** A first version drew its own leather and parchment
  from color textures, to depend on no art file; next to Forever's spellbook it looked foreign. The
  journal now uses the client's frame template, spellbook atlases, fonts and colors. The atlas
  names and `SPELLBOOK_FONT_COLOR` were checked against build 70235's `UiTextureAtlasMember` and
  `GlobalColor` tables (wago.tools), and the code checks each piece at runtime before using it,
  falling back to the color drawing.

### Decided during 0.4

- **Footsteps lives on the world map.** The plan had a Footsteps tab in the journal; the world map
  already is the place for routes, and a tab would only have pointed there. The journal links each
  day with trails to the map instead. Tabs are decided with Wrapped (0.5).
- **Trails split at midnight** and are stored per day (`months[m].days[d]`), not as one list per
  month, so a day's trails are a table lookup and every trail belongs to exactly one journal day.
- **Distance is a journal counter** (`travel`), written when a trail ends, so the journal, the login
  recap and Wrapped never decode trails.
- **Trails have their own guard.** A problem with `WayscribeFootstepsDB` makes only the trails read-only;
  the journal keeps working (§4.6).
- **Trails continue after a pause.** A trail ends after a minute without moving (and at midnight, on
  taxis, at death), but the next one starts at its last point when the player is still there, so
  the map shows one unbroken route.
- **Geometry is Core.** Douglas-Peucker, the world-to-map transform and clipping are pure math used
  by the recorder, the map and the probe, like `Time`.
- **One name: Footsteps.** Files, modules, the tracker id and the saved variables
  (`WayscribeFootstepsDB`) say Footsteps, like the game; the data layer calls what it stores *trails*
  (`Paths`). Renamed before release, so no saved file refers to the old `HeroPath` id or
  `WayscribePathDB`.
- **Deaths join 0.4.** A skull on the map where you died belongs to Footsteps, so the Deaths
  tracker (a future idea until then) came with it. Its records live in the journal, not with the
  trails: a death is a milestone, the map only reads it.
- **Journeys by spell join 0.4.** In game, a hearthstone drew a straight line across Mulgore. Besides
  breaking the trail there, a hearthstone or teleport now gets a journal entry ("Ruhestein nach
  Bloodhoof") and its spell's icon at both ends on the map. Only a recognized cast counts: a jump
  alone could be a summon or a boat.
- **Markers come from record types.** Deaths and journeys declare where they go on the map
  (`markers`, §4.3), so the map has no per-type code and a future tracker (a screenshot, a rare
  kill) can add icons the same way.
- **Coverage moves to 0.5.** "% of Azeroth walked" is a Wrapped card; it's built with Wrapped.

### Landscape (for positioning)

| Addon | Overlap | Gap we fill |
|---|---|---|
| **ForeverChronicle** (Forever + Retail, created late Sep 2026, ~300 downloads, All Rights Reserved) | Session/day/month/year diary in narrative prose, login recap, levels, quests, dungeons, bosses, gathering, professions, deaths, companions, minimap, slash | No movement trail, no quest-chain completion, no Wrapped-style stats recap, no keybinding, no Blizzard Settings panel. One account-wide SV with flat, unpartitioned event lists that store prose; its own preflight rates performance at 100k+ events 5/10. Its focus is a broad "memory" (search, resource atlas, vendors, trainers, notes, bags and bank), not a journal. |
| AutoBiographer (Classic/TBC, ~109K downloads) | Milestones and stats | No Forever support, no day-by-day journal, no travel map, no yearly recap |
| Hero's Path (Classic 1.15.5, inactive ~1 year) | Route recording | Not combined with a journal, not on Forever |
| Diary (abandoned) | Diary-style tracking | Dead project |
| AdventureHistory, CrossPaths (Retail) | Run logs, social tracking | Retail only, different focus |

**Positioning.** Wayscribe should *not* chase ForeverChronicle's breadth (search engine, resource
atlas, vendor and trainer memory, bag and bank). It should win on three things ForeverChronicle doesn't
have:

1. A **Footsteps trail map** (BotW-style), tied to journal days.
2. A **Wrapped** yearly recap.
3. A **lightweight, scalable core**: per-character partitioned storage, facts instead of prose,
   counters for high-volume events, and native Settings panel plus keybinding.

Its code is All Rights Reserved and forbids public derivative releases, so we take **no code, text,
icons or locale strings** from it. We only use the observable facts about which Forever APIs and
events work, which are listed in §12.
