# Developing Wayscribe

Notes for working on the addon. What it does for players is in the [README](../README.md).

| Document | What's in it |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | How the addon is built and why: layers, data layout, trackers, UI, decisions |
| [ingame-tests.md](ingame-tests.md) | The checks that need the real Forever client, and which are still open |
| [forever-probe.md](forever-probe.md) | Raw `/ws probe` output from the Forever beta |

## Tests and lint

Tests and lint need only Lua 5.1 (what WoW runs); newer Lua works for the tests too.

```bash
lua tests/run.lua
```

```bash
luacheck .
```

CI runs both on Lua 5.1.5 on every push and pull request. Homebrew no longer has Lua 5.1, so to get
the same locally, build it with [hererocks](https://github.com/luarocks/hererocks) into a folder
outside the repository:

```bash
pip3 install hererocks
hererocks ~/.lua51 -l 5.1 -r latest
~/.lua51/bin/luarocks install luacheck
```

Then run `~/.lua51/bin/lua tests/run.lua` and `~/.lua51/bin/luacheck .`, or
`source ~/.lua51/bin/activate` to put them first on the PATH of that shell.

The tests run the real addon files against `tests/wow_stubs.lua`, a small fake of the WoW API (clock,
frames and events, `C_Timer`, secret values, instances, groups, professions, loot). Each area has a
`tests/<area>_spec.lua`.

## Trying it in game

Link or copy the repository into the Forever client's AddOns folder as `Wayscribe` (on the beta:
`_classic_beta_/Interface/AddOns/Wayscribe`). The client only loads what the TOC lists, so `docs/`
and `tests/` do no harm there.

The minimap button needs the libraries in `Libs/`, which the packager fetches (see `.pkgmeta`). For
a local copy, put LibStub, CallbackHandler-1.0, LibDataBroker-1.1 and LibDBIcon-1.0 there yourself.
Without them, everything except the minimap button works. An unpackaged copy also reports its
version as the literal `@project-version@` (in `/ws probe`, for example); only the packager fills
it in.

### Developer commands

| Command | What it does |
|---|---|
| `/ws dev` | Toggle developer mode: errors also go to BugSack; enables `simulate` and `backup sample`; previews this year's Your Year before December |
| `/ws probe` | Which game APIs this client offers and what they return right now. Saved to `WayscribeDB.probe`; paste it into [forever-probe.md](forever-probe.md) |
| `/ws simulate LEVEL_UP level=12` | Add a test entry through the real write path (any record type, `key=value` fields) |
| `/ws simulate clear` | Remove all simulated entries |
| `/ws backup sample [days]` | The backup of a made-up year (365 days by default), to time the clipboard with; it can be checked but not restored |
| `/etrace` | The client's event trace, for questions like "does this event fire?" |

`/ws stats`, `/ws log` and `/ws rebuild` work without developer mode (see the README).

### Saved data

| File | Holds |
|---|---|
| `WTF/Account/<account>/SavedVariables/Wayscribe.lua` | `WayscribeDB`: settings, error log, the last probe, one canary per character |
| `WTF/Account/<account>/<realm>/<character>/SavedVariables/Wayscribe.lua` | `WayscribeCharDB` (the journal) and `WayscribeFootstepsDB` (the trails) |

The client writes these files only on logout and `/reload`. Trails are packed strings; to decode
one outside the game, load the addon the way the specs do
(`require("wow_stubs").LoadAddon().Codec.DecodePath(p)`, with `tests/` on `package.path`).

## Dungeon map data

`StaticData/DungeonMaps.lua` is generated (docs/dungeon-maps.md). The dungeons, and what can't be
looked up (hand-placed bosses, the title banner to leave out of the fog), are in
`tools/dungeonmaps/dungeons.py`. Then, with Python 3 and curl:

```bash
python3 tools/dungeonmaps/build.py
```

It downloads what it needs once into `tools/dungeonmaps/.cache/` (never committed): Forever's and
retail's tables and Forever's map tiles from wago.tools, and AzerothCore's spawn and entrance
positions. Then it writes the Lua file and, for every floor, a review page
(`.cache/review/<instanceID>.html`) with the map, its sections in color and the bosses where they
were placed. `python3 tools/dungeonmaps/build.py 389 43` builds only those review pages.

## Adding a tracker

A feature is one file (ARCHITECTURE.md §6):

1. `Trackers/<Name>.lua`: its record types (`ns.RecordTypes:Register`) or counters
   (`RegisterCounter`), the tracker (`ns.Trackers:New`) with its events, and its Your Year card
   (`ns.YearCards:Register`), if it has one.
2. Its strings in both `Locales/enUS.lua` and `Locales/deDE.lua` (every `_ONE` pattern needs a German
   one too; a test checks).
3. One line in `Wayscribe.toc`, in the Trackers block.
4. A `tests/<name>_spec.lua`, and the file in `tests/run.lua`'s list.

Every game value goes through `Compat.Safe` or `Compat.Call` (secret values), and new APIs are
feature-detected in `Compat`, never assumed (ARCHITECTURE.md §1, §5).

## Releasing

Releases go to CurseForge (project `1731716`) and to GitHub Releases. There is no Wago upload.

`.github/workflows/release.yml` runs the [BigWigsMods packager](https://github.com/BigWigsMods/packager)
on every pushed tag. It:

- fetches the libraries listed under `externals` in `.pkgmeta` into `Libs/` (the repository never
  holds them), so players get them inside the zip;
- replaces `@project-version@` in the TOC with the tag name, exactly as written: tag `0.1.0` gives
  version `0.1.0`, tag `v0.1.0` gives `v0.1.0`;
- leaves out `docs/`, `tests/` and `README.md`;
- uploads the zip to the CurseForge project named by `## X-Curse-Project-ID` in the TOC, then
  creates the GitHub release.

A tag containing `alpha` or `beta` (e.g. `0.1.0-beta`) is uploaded to CurseForge as that release
type, any other tag as a full release.

What the workflow relies on (all set up):

- `## X-Curse-Project-ID: 1731716` in `Wayscribe.toc`.
- The repository secret `CF_API_KEY`: a CurseForge API token, made in the author console under
  Settings > API tokens.
- Read and write permissions for workflows (repository Settings > Actions > General), so the
  workflow's own token can create the GitHub release.

The CurseForge project description is the [README](../README.md), pasted by hand: it's written for
players, and CurseForge takes Markdown. The packager doesn't update it, so paste it again when the
README changes.

To release, tag the commit on `main` and push the tag; the run shows under the repository's Actions:

```bash
git tag 0.1.0
```

```bash
git push origin 0.1.0
```
