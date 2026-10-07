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
Without them, everything except the minimap button works.

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

`.github/workflows/release.yml` runs the [BigWigsMods packager](https://github.com/BigWigsMods/packager)
on every pushed tag. It fetches the libraries from `.pkgmeta`, replaces `@project-version@` with the
tag, leaves out `docs/`, `tests/` and `README.md`, and uploads the zip. A tag containing `alpha` or
`beta` is uploaded as that release type, any other tag as a release.

Before the first public release:

- Add `## X-Curse-Project-ID:` and `## X-Wago-ID:` with the project IDs to `Wayscribe.toc`; the
  packager reads them to know where to upload.
- Set the repository secrets `CF_API_KEY` (CurseForge) and `WAGO_API_TOKEN` (Wago). GitHub Releases
  use the workflow's own token.
- Use the [README](../README.md) as the project description: it's written for players, and
  CurseForge takes Markdown.

Then tag and push:

```bash
git tag v0.6.0
```

```bash
git push origin v0.6.0
```
