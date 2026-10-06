# Wayscribe

An automatic journal for your **WoW Forever** character. Wayscribe records what happens while you play,
groups it by day, shows your last session when you log in, and draws where you went on the world map
(**Footsteps**). A yearly "Wrapped" is next.

```
Saturday, October 3, 2026
Today · played 2 h 10 min

 2:05 PM  Defeated Taragaman the Hungerer for the first time
 2:31 PM  First clear of Ragefire Chasm with Xy, Ab and Cd (42 min)
 3:10 PM  Mining reached 75
 4:02 PM  Completed the quest chain: The Defias Brotherhood
          Ore deposits mined: 12
          Gathered 23× Copper Ore, 4× Rough Stone
          Skill gains: Mining +23
          Quests turned in: 7
          Traveled 4.1 miles · Flight paths: 2.3 miles
```

Everything stays in your SavedVariables. Nothing is sent anywhere.

## Status

**0.4 Footsteps** (in progress). It tracks:

- level ups
- professions: learned, skill points per day, ranks 75/150/225/300
- gathering: ore, herbs and skins per day
- boss kills, including world bosses
- dungeon and raid runs with your group, duration and first clears
- deaths: where and when, in the journal and as a skull on the map
- quests turned in per day, and well-known quest chains (attunements, class quests, famous
  storylines). Chains added in a later version are filled in for the day you finished them.
- **Footsteps**: where you walked, rode and flew, as trails on the world map (today, the last 7
  days or everything), and the distance per day. Each journal day with trails opens the map at that
  day's route. Two hours of play take about 3 KB.

The journal is a book: a day list grouped by month on the left, the selected day on the right,
filters per category, full dates in English or German. There's also a login recap, a settings page
(Options > AddOns > Wayscribe), a minimap button, an Addon Compartment entry and a key binding
(Key Bindings > AddOns, unbound by default).
See the roadmap in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#11-roadmap).

## Commands

| Command | What it does |
|---|---|
| `/ws` or `/wayscribe` | Open or close the journal |
| `/ws settings` | Open the settings page |
| `/ws recap` | Show the last session again |
| `/ws probe` | Show which game APIs this client offers (also saved to `WayscribeDB.probe`) |
| `/ws stats` | Entries, days, months and sessions in this character's journal, and the size of its footsteps |
| `/ws log` | The last recorded errors |
| `/ws rebuild` | Recompute firsts and monthly summaries from the journal entries, and fill in quest chains finished before they were known |
| `/ws dev` | Toggle developer mode (errors also go to BugSack; enables `simulate`) |
| `/ws simulate LEVEL_UP level=12` | Add a test entry through the real write path; `/ws simulate clear` removes them |
| `/ws accept` | Resolve a read-only situation (journal of another character, or a journal or footsteps that didn't load) |

## Development

Tests and lint need only Lua 5.1 (what WoW runs); newer Lua works for the tests too.

```bash
lua tests/run.lua
```

```bash
luacheck .
```

CI runs both on Lua 5.1.5. Homebrew no longer has Lua 5.1, so to get the same locally, build it
with [hererocks](https://github.com/luarocks/hererocks) into a folder outside the repository:

```bash
pip3 install hererocks
hererocks ~/.lua51 -l 5.1 -r latest
~/.lua51/bin/luarocks install luacheck
```

Then run `~/.lua51/bin/lua tests/run.lua` and `~/.lua51/bin/luacheck .`, or
`source ~/.lua51/bin/activate` to put them first on the PATH of that shell.

To try it in game, link the repository into the Forever client's AddOns folder as `Wayscribe`.
The minimap button needs the libraries in `Libs/`, which the packager fetches (see `.pkgmeta`). For a
local copy, put LibStub, CallbackHandler-1.0, LibDataBroker-1.1 and LibDBIcon-1.0 there yourself.
Without them, everything except the minimap button works.
The architecture, design decisions and the list of APIs still to verify on the Forever client
are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). The checks that need the real client are in
[docs/ingame-tests.md](docs/ingame-tests.md).
