# Wayscribe

An automatic journal for your **WoW Forever** character. Wayscribe records what happens while you play,
groups it by day and shows your last session when you log in. Upcoming releases add the **Footsteps**
travel map and a yearly "Wrapped".

```
03.10.2026
  Defeated Taragaman the Hungerer for the first time
  First clear of Ragefire Chasm with Xy, Ab and Cd (42 min)
  Mining reached 75
  Reached level 12
  Ore deposits mined: 12
  Gathered 23× Copper Ore, 4× Rough Stone
  Skill gains: Mining +23
```

Everything stays in your SavedVariables. Nothing is sent anywhere.

## Status

**0.2 Adventurer** (in progress). It tracks:

- level ups
- professions: learned, skill points per day, ranks 75/150/225/300
- gathering: ore, herbs and skins per day
- boss kills, including world bosses
- dungeon and raid runs with your group, duration and first clears

It also has a login recap, a settings page (Options > AddOns > Wayscribe), a minimap button, an
Addon Compartment entry and a key binding (Key Bindings > AddOns, unbound by default).
See the roadmap in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#11-roadmap).

## Commands

| Command | What it does |
|---|---|
| `/ws` or `/wayscribe` | Open or close the journal |
| `/ws settings` | Open the settings page |
| `/ws recap` | Show the last session again |
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
The minimap button needs the libraries in `Libs/`, which the packager fetches (see `.pkgmeta`). For a
local copy, put LibStub, CallbackHandler-1.0, LibDataBroker-1.1 and LibDBIcon-1.0 there yourself.
Without them, everything except the minimap button works.
The architecture, design decisions and the list of APIs still to verify on the Forever client
are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). The checks that need the real client are in
[docs/ingame-tests.md](docs/ingame-tests.md).
