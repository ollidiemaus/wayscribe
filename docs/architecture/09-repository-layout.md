# 9. Repository layout

Part of the [Wayscribe architecture](../ARCHITECTURE.md); other sections are listed there.

```text
Wayscribe.toc
Bindings.xml               -- key binding (loaded by the client, not listed in the TOC)
embeds.xml                 -- libs in Libs/ (fetched by the packager via .pkgmeta, git-ignored)
Locales/   enUS.lua deDE.lua
Core/      Init.lua Log.lua Time.lua Geometry.lua Bus.lua Options.lua Module.lua Trackers.lua Slash.lua Lifecycle.lua
Compat/    Compat.lua Probe.lua
Data/      Codec.lua RecordTypes.lua Players.lua Notes.lua Index.lua Store.lua Paths.lua Coverage.lua YearCards.lua
           Schema.lua Backup.lua
StaticData/ Dungeons.lua DungeonMaps.lua (generated, see tools/) Gathering.lua QuestChains.lua Travel.lua
            Zones.lua
Trackers/  Session.lua Level.lua Professions.lua Gathering.lua Bosses.lua Dungeons.lua
           QuestChains.lua Footsteps.lua Deaths.lua DungeonMaps.lua
UI/        Theme.lua DayView.lua YourYear.lua NotesView.lua Journal.lua Export.lua FootstepsMap.lua
           NotesMap.lua DungeonMap.lua MapsView.lua LoginRecap.lua Settings.lua Minimap.lua
Media/     Icon.tga (128×128, 32-bit) IconSmall.tga (64×64, 32-bit), their .svg sources (not
           packaged), FogDot.tga
tests/     run.lua testlib.lua wow_stubs.lua serialize.lua <area>_spec.lua …
docs/      ARCHITECTURE.md (overview + index) architecture/<section>.md DEVELOPMENT.md ingame-tests.md
           forever-probe.md dungeon-maps.md
tools/     dungeonmaps/ (Python generator for StaticData/DungeonMaps.lua, not packaged)
README.md  -- for players (also the CurseForge description)
.pkgmeta  .luacheckrc  .github/workflows/{ci.yml,release.yml}
```

The TOC declares `## Interface: 16001`, `SavedVariables: WayscribeDB` and
`SavedVariablesPerCharacter: WayscribeCharDB, WayscribeFootstepsDB`, the icon and the
`AddonCompartmentFunc`. Its load order is Libraries → Locales → Core → Compat → Data → StaticData →
Trackers → UI, with `Core/Slash.lua` and `Core/Lifecycle.lua` last because they wire everything
together. Load order is the only dependency mechanism in WoW, so it must match the layer diagram.
