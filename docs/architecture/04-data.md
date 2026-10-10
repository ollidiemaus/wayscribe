# 4. Data layer

Part of the [Wayscribe architecture](../ARCHITECTURE.md); other sections are listed there.

The data layer is the most important part of the addon and gets the most tests.

## 4.1 SavedVariables split

| SV | Scope | Contents | Why separate |
|---|---|---|---|
| `WayscribeDB` | Account | Settings, minimap position, error log, per-character canaries (§4.6) | Small. Shared across characters. A separate file, so it can vouch for the character files. |
| `WayscribeCharDB` | Character | Journal records, counters, sessions, indexes, tracker state, the player's notes | The core data. |
| `WayscribeFootstepsDB` | Character | Footsteps trails (string-packed), written only through `Paths` | The largest and fastest-growing data. Isolating it means it can be wiped, pruned or moved to load-on-demand without touching the journal. It has its own schema version and read-only guard (§4.6). It lives in the same file as the journal (one `Wayscribe.lua` per character), so a file that fails to load takes both. |

## 4.2 `WayscribeCharDB` layout

```lua
WayscribeCharDB = {
    schema = 1,                         -- migration version (see 4.6)
    meta = {
        guid = "Player-…", name = "…", realm = "…", class = "MAGE", race = "Troll",
        created = 1759400000,           -- first time the addon saw this character
        seq = 1234,                     -- last issued record id (monotonic)
        rollup = 2,                     -- version of the rollups' shape (§4.5)
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

    -- Interned players (records hold small integers instead of names). Forever's names include the
    -- surname ("Xy Ashford"); their realm isn't known, so it's left out.
    players = {
        [3] = { guid = "Player-…", name = "Xy Ashford", class = "PRIEST" },
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
            rollup   = { records = { LEVEL_UP = 2, DUNGEON_COMPLETED = 1 },   -- count per type
                         counters = { gather = { [2770] = 23 } },              -- the days' counters summed
                         activeDays = 1, firsts = 1,                           -- generic (Index)
                         minLevel = 11, maxLevel = 12, maxLevelAt = 1759493100, -- type-specific
                         dungeons = { [389] = 1 }, dungeonNames = { [389] = "Ragefire Chasm" },
                         dungeonFirsts = { [389] = 1759490900 }, companions = { [3] = 1, [7] = 1 } },
        },
    },

    firsts = { ["DUNGEON:389"] = 1201, ["PROF:186"] = 1103 },   -- first-occurrence index

    -- The player's own notes (§4.9); each /way line of a text is a marker on the world map.
    notes = {
        seq = 2,                        -- last issued note id (monotonic)
        list = {
            { id = 1, created = 1759490000, edited = 1759490200, title = "Buy linen", text = "…" },
            { id = 2, created = 1759493000, edited = 1759493100, title = "Hidden Books", icon = 3,
              text = "/way Elwynn Forest 49.0 86.4 The Kaldorei\n/way 52.3 41.0 Upstairs" },
        },
    },
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
- **Rollups hold everything a year's recap needs** (§8): a count per record type, the summed
  counters, the days with entries and the firsts (kept by `Index` for every type), plus the fields
  each type's `rollup` adds (level range, dungeon names and first clears, first boss kills, deaths
  per map, professions learned and highest ranks, curated chains). Play time comes from the
  month's sessions. So a month's days could move to an archive without changing its recap.

## 4.3 Record types: the extension point

Every record type is registered once, and that registration is its contract:

```lua
ns.RecordTypes:Register("DUNGEON_COMPLETED", {
    version  = 1,
    category = "adventure",               -- journal filter group
    fields   = { instanceID = "number", roster = "table", dur = "number?" },
    firstKey = function(data, r) return "DUNGEON:" .. data.instanceID end,  -- enables "First time" badge
    rollup   = function(monthRollup, data, r) ... end, -- O(1) update of the month rollup (r.first is set already)
    merge    = function(yearRollup, monthRollup) ... end, -- combines type-specific rollup fields
    render   = function(data, r) ... end,  -- -> text, icon (localized, at display time)
    markers  = function(data, r) ... end,  -- optional: { { c, x, y, icon, title }, ... } on the map
    upcast   = { [1] = function(data) ... end },  -- optional: version 1 shape -> version 2
})
```

The Store uses `fields` to validate (types, missing and unknown fields, no secrets, nothing a saved
file can't hold), plus `firstKey` and `rollup` to maintain indexes. The UI uses `render`. Neither
layer has a per-type `if/else`. Counters register the same way (`RecordTypes:RegisterCounter(path,
{ order, category, render })`), so the day page can show each one as a summary line.

## 4.4 Write path

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

## 4.5 Read path

```lua
Store:GetDayKeys()                    -- sorted array (built in memory at load, never persisted)
Store:GetDay(dayKey)                  -- records (time-sorted) + counters
Store:GetSessions(fromTs, toTs)       -- overlapping sessions; the open one ends now
Store:GetMonthSummary(ym) / Store:GetYearSummary(y) -- rollups + play time; year = sum of 12 months
Store:GetFirst(key)
Store:GetYears()                      -- years with entries, newest first
Store:GetPlayByDay(fromTs, toTs)      -- seconds played per day, a session split at midnight
```

- The day index is rebuilt at load from month and day keys. That costs a few hundred iterations per year
  of data, so there's nothing to persist or corrupt.
- `firsts` and `rollup` **are** persisted for speed, but they are treated as caches. `/ws rebuild`
  (and any migration that needs it) recomputes them from records and counters. A rollup schema change is
  therefore just "bump version and rebuild": `Index.ROLLUP_VERSION` is stamped into `meta.rollup`,
  and a journal with an older one is rebuilt once at login. A read-only journal is left as it is.
- The journal UI asks only for the days that are visible, so the ScrollBox is virtualized.

## 4.6 Schema, migrations, safe mode

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
  explains the problem, and `/ws log` shows the error. The SV table is left exactly as it was loaded,
  so logout writes back the same data. The client also keeps `<Addon>.lua.bak` as a one-step backup.
- If `meta.guid` doesn't match `UnitGUID("player")` (for example, a WTF folder copied to another
  character), the journal is shown read-only until the player confirms with `/ws accept`.
- **Missing-DB guard.** The account-wide `WayscribeDB.characters[guid]` keeps a tiny canary per
  character: name, realm, last `seq`, the notes' `seq` (§4.9), last save time. It's written to a
  different SV file than the journal.
  - If the character DB loads as `nil` or empty but the canary shows records or notes, the journal
    file failed to load (or was moved). The addon goes into safe mode, records nothing, and warns the
    player right away. An addon can't stop the client from rewriting the file at logout, but the
    file on disk is still intact during this session. The warning says to copy
    `WTF/…/SavedVariables/Wayscribe.lua` (or its `.bak`) somewhere safe **before logging out**, or
    to paste a backup with `/ws restore` (§4.8).
  - The same canary detects **renames and realm transfers**. Per-character SV files are stored under
    the character name, so a renamed character starts with an empty file. Wayscribe recognizes the
    GUID and shows how to move the old file.
  - This doesn't help if *every* SV file fails to load (canary and journal look like a first
    install), or when the files are gone (a new computer, a deleted WTF folder). The backup (§4.8)
    covers that: a string the player keeps outside the game and pastes back.
  - **Trails** (`WayscribeFootstepsDB`) get the same checks with their own outcome: a newer schema, a
    failed migration, an unexpected shape, or trails missing while the canary counted some
    (`characters[guid].paths`, the trail `seq`) make **only the trails** read-only, with a chat
    warning. The journal keeps recording. `/ws accept` starts new trails. When the journal itself
    is missing, its own guard has already warned, and the trails are left alone.
- Migrations need **no persistent snapshot inside the SV**. Build-then-swap happens in memory, so if
  the client crashes before saving, the old file is still on disk and the migration simply runs again
  next login. (ForeverChronicle keeps a full DB copy inside its SV during migrations, which doubles
  the file size. This design avoids that.)

## 4.7 Size budget and growth plan

Estimates for an active player (about 2 h/day):

| Data | Per day | Per year | Notes |
|---|---|---|---|
| Journal records + counters | ~2–4 KB | ~1 MB | 20–50 records/day, counters aggregated |
| Footsteps trails (packed, simplified) | ~3–6 KB | ~1–2 MB | See §6.8 |
| Indexes / rollups | — | < 50 KB | Months × small tables |

That's roughly 2–3 MB per character per year, which is comfortable for a few years. The growth plan is
designed now but built later:

- **Phase A (now):** everything lives in the main addon. Partition keys are already month-based.
- **Phase B (when real data says so):** a load-on-demand companion, `Wayscribe_Archive`, with its own
  per-character SV. Once a month, out of combat at login, closed **years** (and Footsteps months older
  than N) move from the hot DB into the archive. Browsing an archived year runs
  `C_AddOns.LoadAddOn("Wayscribe_Archive")` on demand. Because rollups stay in the hot DB, the yearly recap
  never needs the archive.
- `/ws stats` reports record counts and how big the journal and the trails are in the saved file, so
  Phase B can be decided on real numbers. `Codec.SavedSize` writes them the way build 70235 does
  (`["key"] = value,` per line, no indentation); it came within one byte of a real 3.4 KB file.
