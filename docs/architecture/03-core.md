# 3. Core runtime

Part of the [Wayscribe architecture](../ARCHITECTURE.md); other sections are listed there.

## 3.1 Lifecycle

| Event | What happens |
|---|---|
| `ADDON_LOADED` (ours) | `Schema:Load()` creates or migrates the three SV tables, decides on safe mode and builds the in-memory indexes. |
| `PLAYER_LOGIN` | Resolve `Compat` capabilities. Enable each tracker whose setting is on. Register settings, minimap button and slash commands. |
| `PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)` | The Session tracker starts or resumes a session. The login recap is shown if this is the initial login and the first one of the day. |
| `PLAYER_LOGOUT` | Close open sessions, segments and runs, and stamp `lastSeen`. This handler must be tiny and must not error, because it is the last chance to write before the SV file is saved. |

## 3.2 Modules and event dispatch

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

## 3.3 Internal bus and timing

- A tiny callback registry (`Core/Bus.lua`); each listener runs in its own error boundary. Messages:
  `READY`, `LOGOUT` (sent before the canary is stamped, so what it writes is counted), `SAFE_MODE`,
  `RECORD_ADDED`, `COUNTER_CHANGED`, `SETTINGS_CHANGED`, `ITEM_NAMES_LOADED`, `REBUILT` (after
  `/ws rebuild`, so trackers can derive what older facts imply, §6.7), the Footsteps messages
  `PATH_ADDED`, `PATH_LIVE`, `PATH_POINT` and `PATH_WIPED` (§6.8), `COVERAGE_READY` (a background
  measurement finished, §6.8), `RECAP_HIDDEN` (Your Year's prompt waits for the login recap, §8) and
  `NOTES_CHANGED` (a note was added, changed or deleted, §4.9).
- UI refresh is **coalesced**: a pending flag plus one `C_Timer.After(0, ...)`, so 20 loot events
  produce one redraw.
- Noisy events (`SKILL_LINES_CHANGED` and friends) are **debounced** (`Module:Debounce`): one snapshot,
  ~0.5 s after the burst.
- Long work (drawing trails, measuring coverage, making or checking a backup) runs in a coroutine with
  a budget of 4 to 10 ms per frame, so it never stalls the game.

## 3.4 Error boundary

- Errors are written to a ring buffer in `WayscribeDB.log` (last 50 entries, each with timestamp, module,
  message and trimmed stack). `/ws log` shows them.
- A module that errors 10 times in one session is disabled for the rest of the session, with a single
  chat notice.
- In developer mode (`/ws dev`), errors are also forwarded to `geterrorhandler()` so BugSack sees them.
- What the guards find in the saved data (a journal that didn't load, a rename, a newer version, an
  unexpected shape, a pasted backup the addon can't take) is a **warning** (`Log:Warn`): it goes to
  the log only, since it is the player's situation, not a bug, and the banner already explains it. A
  migration that throws is an error.

## 3.5 Time

- All timestamps are `time()` epoch seconds.
- Day key: integer `YYYYMMDD` (`20261003`). Month key: `YYYYMM`. Both are computed from local time when
  the record is written. Days roll over at **calendar midnight**. There's no configurable rollover
  hour, so a day key never depends on a setting.
- Short dates (login recap) follow a setting: locale default (deDE → `03.10.2026`) or a manual
  override. Journal pages spell the date out from locale tables, because `date("%A")` is always
  English in the client: "Saturday, October 3, 2026" / "Samstag, 3. Oktober 2026". The weekday is
  computed from the day key (Sakamoto's method), so it needs no `time()` call.
- Times of day follow the game's 24-hour clock setting (`timeMgrUseMilitaryTime`), else the
  language's habit (enUS `2:05 PM`, deDE `14:05`).
