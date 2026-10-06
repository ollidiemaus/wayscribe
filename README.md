# Wayscribe

An automatic journal for your **WoW Forever** character. Wayscribe records what happens while you play,
groups it by day, and (in upcoming releases) adds a login recap, the **Footsteps** travel map and a
yearly "Wrapped".

```
03.10.2026
  Ragefire Chasm with Xy, Ab
  Reached level 12
```

Everything stays in your SavedVariables. Nothing is sent anywhere.

## Status

**0.1 Foundation.** Data layer, session and level tracking, a plain journal window, slash commands.
See the roadmap in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#11-roadmap).

## Commands

| Command | What it does |
|---|---|
| `/ws` or `/wayscribe` | Open or close the journal |
| `/ws probe` | Show which game APIs this client offers (also saved to `WayscribeDB.probe`) |
| `/ws stats` | Entries, days, months and sessions in this character's journal |
| `/ws log` | The last recorded errors |
| `/ws rebuild` | Recompute firsts and monthly summaries from the journal entries |
| `/ws dev` | Toggle developer mode (errors also go to BugSack; enables `simulate`) |
| `/ws simulate LEVEL_UP level=12` | Add a test entry through the real write path; `/ws simulate clear` removes them |
| `/ws accept` | Resolve a read-only situation (journal of another character, or a journal that didn't load) |

## Development

Tests and lint need only Lua 5.1 (what WoW runs); newer Lua works for the tests too.

```bash
lua tests/run.lua
```

```bash
luacheck .
```

To try it in game, link the repository into the Forever client's AddOns folder as `Wayscribe`.
The architecture, design decisions and the list of APIs still to verify on the Forever client
are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
