# 10. Libraries and tooling

Part of the [Wayscribe architecture](../ARCHITECTURE.md); other sections are listed there.

How to run all of this: [DEVELOPMENT.md](../DEVELOPMENT.md).

- **Libraries (minimal):** localization is a small in-house table (`Locales/*.lua`). LibStub,
  CallbackHandler-1.0, LibDataBroker-1.1 and LibDBIcon-1.0 power the minimap button. They are
  `.pkgmeta` externals that the packager fetches into `Libs/` (git-ignored), and they are **optional
  at runtime**: an unpackaged copy without `Libs/` loses only the minimap button. `/ws probe` lists
  the loaded versions.
  - No AceDB: the Store has requirements AceDB doesn't cover (partitioning, migrations, safe mode).
  - No AceAddon: the Module base is about 120 lines.
  - No AceLocale: two locales don't need it. Revisit if CurseForge community translations are wanted.
- **Static checks:** `luacheck` with a WoW globals list. Keep UI builder functions small: Lua 5.1
  allows at most 60 upvalues per function, and ForeverChronicle shipped a window that failed to load
  because of it.
- **Unit tests:** a dependency-free runner (`lua tests/run.lua`) with `tests/wow_stubs.lua` (fake clock,
  `CreateFrame` that can fire events and accepts any widget method so UI files load, `C_Timer`,
  `issecretvalue`, plus instance, group, profession, loot, item and spell doubles). It runs on Lua 5.1
  in CI and on any local Lua 5.1+. Codec, Store, Schema/migrations, Index rebuild, Players interning,
  trackers and renderers are all exercised, so this is where "very stable read/write" gets proven. A
  test-only serializer round-trips the DB the way the client writes SavedVariables, which proves it
  holds plain data only. Migration tests use frozen fixture DBs from every past schema.
- **CI:** `ci.yml` runs luacheck and the tests on Lua 5.1 on every push and PR. `release.yml` runs
  the BigWigsMods packager on tags, which uploads to CurseForge and GitHub Releases (no Wago).
  The tag becomes the version (`@project-version@` in the TOC). `package-as: Wayscribe` keeps the folder name capitalized to
  match `Wayscribe.toc`, since the repository is the lowercase `wayscribe`.
- **In-game dev tools** (developer mode, `/ws dev`): `/ws simulate LEVEL_UP level=12` injects records
  through the real write path, flagged as test data and removable with `/ws simulate clear`; Your
  Year previews the current year before December; `/ws backup sample [days]` makes the backup of a
  made-up year to time the clipboard with (§4.8). Always available: `/ws probe`, `/ws stats`,
  `/ws log` and `/ws rebuild`.
