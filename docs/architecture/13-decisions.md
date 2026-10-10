# 13. Decisions

Part of the [Wayscribe architecture](../ARCHITECTURE.md); other sections are listed there.

The choices that shaped the addon, by topic. Each says what was decided and why.

## Scope and names

- **Forever only for now.** The TOC declares `## Interface: 16001`. The capability-based Compat
  layer still keeps other flavors cheap to add later.
- **Name: Wayscribe** (2026-10-06, after checking that it's free on CurseForge, Wago, WoWInterface
  and GitHub; "Diary" was taken). It's baked into the SavedVariables names, the folder name and the
  slash commands (`/wayscribe`, alias `/ws`).
- **Footsteps** for the travel map ("Hero's Path" is taken by another addon and is Nintendo's term)
  and **Your Year** for the recap ("Wrapped" is Spotify's word). Game and code use the same names:
  `Footsteps`, `WayscribeFootstepsDB`, `YourYear`, `YearCards`. The data layer calls what Footsteps
  stores *trails* (`Paths`). The renames happened before any release, so no saved file refers to the
  old `HeroPath` id or `WayscribePathDB`.
- **Companion names** are stored and shown. There's no "hide names" toggle for now.

## Data

- **Day boundary:** calendar midnight in local time (§3.5). A session that runs past midnight
  continues on the next day's page.
- **Captured names.** Boss, instance, subzone and quest-line names are stored as captured from the
  client (localized), because no API resolves those IDs to names later.
- **Rollups carry the recap.** The fields Your Year's cards need are in the rollups (version 2),
  including days with entries. Older rollups are rebuilt once at login instead of waiting for
  `/ws rebuild`.
- **Distance is a journal counter** (`travel`), written when a trail ends, so the journal, the login
  recap and Your Year never decode trails.
- **Trails split at midnight** and are stored per day (`months[m].days[d]`), not as one list per
  month, so a day's trails are a table lookup and every trail belongs to exactly one journal day.
- **Trails have their own guard.** A problem with `WayscribeFootstepsDB` makes only the trails
  read-only; the journal keeps working (§4.6).
- **Geometry is Core.** Douglas-Peucker, the world-to-map transform, clipping and the coverage grid
  are pure math used by the recorder, the map, the probe and Your Year, like `Time`.
- **No archive (Phase B) yet.** It waits for real numbers: `/ws stats` reports the saved file's
  size, measured the way the client writes it. The first beta day (15 sessions) saved 3.4 KB.
- **Libraries are packager externals**, not committed, and optional at runtime.

## Trackers

- **Raids are runs too.** The Dungeons tracker follows party and raid instances. Raid finals
  (Ragnaros, Onyxia, Nefarian, Hakkar, Ossirian, C'Thun, Kel'Thuzad) are in the data table, and a
  raid night without its final boss is a "visited" entry with the bosses killed.
- **A run is written when it ends**, not at the final kill: the entry then has every boss and
  everyone who was there. It closes as soon as the player leaves after the final boss, so it still
  appears right away.
- **Curated chains before quest lines.** Their names are chosen and translated, and only they can be
  matched again later, so a live entry and a back-filled one always agree on the chain's key.
- **Back-fill is automatic.** A release with new chain definitions back-fills at the next login
  (version check), not only on `/ws rebuild`, so players see old chains without knowing the command.
  Only the day of a turn-in is saved, so back-filled entries are dated at the end of that day,
  flagged `bf`, and shown without a time.
- **Trails continue after a pause.** A trail ends after a minute without moving (and at midnight, on
  taxis, at death), but the next one starts at its last point when the player is still there, so
  the map shows one unbroken route.
- **Deaths are journal records.** A death is a milestone; the map only reads it for its skull.
- **Only a recognized cast is a journey.** A hearthstone or teleport gets a journal entry and its
  spell's icon at both ends on the map. A jump alone could be a summon or a boat, so it only breaks
  the trail.
- **Markers come from record types.** Deaths and journeys declare where they go on the map
  (`markers`, §4.3), so the map has no per-type code and a future tracker (a screenshot, a rare
  kill) can add icons the same way.
- **Cards live with their trackers**, like record types and counters: one file still adds a
  feature, its Your Year card included. Only the opening card is the UI's own.

## UI

- **The default UI's look, verified first.** A first version drew its own leather and parchment
  from color textures; next to Forever's spellbook it looked foreign. The journal now uses the
  client's frame template, spellbook atlases, fonts and colors. The atlas names and
  `SPELLBOOK_FONT_COLOR` were checked against build 70235's `UiTextureAtlasMember` and
  `GlobalColor` tables (wago.tools), and the code checks each piece at runtime before using it,
  falling back to the color drawing.
- **Footsteps lives on the world map**, not in a journal tab: the world map already is the place for
  routes. The journal links each day with trails to the map instead.
- **Your Year is a tab in the journal**, not a window of its own. The book already has a list page
  and a page to turn; years and their cards fit both, and the page buttons make the slideshow.
- **The current year opens on December 1**; developer mode previews it. The prompt also catches up
  in the new year for a player who didn't log in during December, and it never covers the login
  recap.
- **Coverage on a 100-yard grid, ground only, against the client's zone maps** (§6.8): no list of
  zones to maintain, and Forever's own zones count. Sparse sets of squares in memory instead of
  chunked bitsets: a year of walking is thousands of squares. Not saved.
- **The export is a copy to read**: rendered pages, not facts, so it can't be imported, and it says
  so. It goes through the clipboard because addons can't write files. Everything is the default;
  month and year are there if a long journal makes the edit box slow.

## Backup

- **One string, no compression.** A very active simulated year backs up to 2.5 MB with its
  footsteps (1.06 MB without). In game it pasted back in 2.8 s and was checked in 1.2 s (§4.8), so
  splitting by year and LibDeflate aren't needed.
- **A backup is a snapshot of its first frame.** It is built over many frames, so `meta`, `state`
  and `players` are copied first and newer records are left out: ids, `seq` and the trackers'
  state always agree in a backup.
- **"No entries" means no records** (`seq` 0). Counters, sessions and trails recorded next to such a
  journal (the minutes after a fresh install, or a character that only ever had Footsteps on) are
  replaced, and the confirmation says how many days and trails that is. A journal with entries
  still needs Reset first.
- **Trails go with the journal**, or on their own into missing or empty ones, so a player who
  walked a few steps after a fresh install doesn't have to Reset before getting the trails back.
- **Read-only journals refuse a restore** unless the missing-journal guard made them read-only
  (missing, renamed). Newer, failed and corrupt data is what principle 3 protects; a foreign
  journal has entries.
- **A paste field that holds 32 bytes.** The client pays for what the field holds with every pasted
  character (§4.8, *The paste*): a 4,000-byte box (the WeakAuras way) took 28.3 s for the 2.4 MB
  sample, a field without a limit 55.6 s for 200 KB. With 32 bytes held, the cost is the `OnChar`
  call, about 1 µs per character.
- **One-line fields for backup strings.** A multi-line box with the 2.4 MB backup drew nothing until
  clicked. The export (pages of text) keeps its multi-line box.
- **Samples can't be restored.** `/ws backup sample` exists to time the clipboard; restoring a
  made-up year into a real character is refused.
- **Guard findings are warnings, not errors** (§3.4). In the missing-journal test, BugSack showed
  the guard's own log entry; a journal that didn't load is the player's situation, not a bug.

## Notes

- **A note's places are its `/way` lines** (the player's choice): one list, one editor, as many
  places per note as lines, in the notation guides already use, so a list copied from a website
  becomes markers as it is. Deleting a line deletes its marker; there's nothing else to keep in
  step. The cost: one icon per note, and a place moves by editing its numbers.
- **A line without a zone** takes the zone named above it, else where the player is (the player's
  choice), and that zone is written into the line when the note is left: the text always says where
  its places are. English zone names come from a static table, since guides are mostly in English
  and the client only knows its own language's names.
- **Alt+click always starts a new note** (the player's choice); more places are added as lines.
- **`/way` only inside notes** (the player's choice): in chat it belongs to TomTom and others.
- **Per character**, in the journal's file, so the backup carries them and the guard protects them.
  Account-wide markers (herb spots for an alt) would need the account file and a backup of their
  own.
- **Not records.** Notes change and disappear; records don't. A table of their own keeps rollups,
  firsts and Your Year free of them, and needs no schema change.
- **A Notes tab** (between Journal and Your Year), not a note on each day page: a notebook for reminders, routes and plans, which
  rarely belong to one day. Each note still knows the day it was written.
- **Alt+click**: Ctrl+click is the default map's own pin, HandyNotes uses Alt+right-click.
- **Raid target icons** for markers: in every client since Vanilla, recognizable at 18 pixels.
- **No minimap markers and no waypoint yet**: the minimap needs its own math or a library. The
  default map's pin is on in Forever (build 70291, §12 #14), so a note could offer "Set as waypoint"
  later; the ruleset can still turn it off (`WorldMapTrackingPinDisabled`), so it would be checked.

## Landscape (for positioning)

| Addon | Overlap | Gap we fill |
|---|---|---|
| **ForeverChronicle** (Forever + Retail, created late Sep 2026, ~300 downloads, All Rights Reserved) | Session/day/month/year diary in narrative prose, login recap, levels, quests, dungeons, bosses, gathering, professions, deaths, companions, minimap, slash | No movement trail, no quest-chain completion, no yearly stats recap, no keybinding, no Blizzard Settings panel. One account-wide SV with flat, unpartitioned event lists that store prose; its own preflight rates performance at 100k+ events 5/10. Its focus is a broad "memory" (search, resource atlas, vendors, trainers, notes, bags and bank), not a journal. |
| AutoBiographer (Classic/TBC, ~109K downloads) | Milestones and stats | No Forever support, no day-by-day journal, no travel map, no yearly recap |
| Hero's Path (Classic 1.15.5, inactive ~1 year) | Route recording | Not combined with a journal, not on Forever |
| Diary (abandoned) | Diary-style tracking | Dead project |
| AdventureHistory, CrossPaths (Retail) | Run logs, social tracking | Retail only, different focus |

**Positioning.** Wayscribe should *not* chase ForeverChronicle's breadth (search engine, resource
atlas, vendor and trainer memory, bag and bank). It should win on three things ForeverChronicle doesn't
have:

1. A **Footsteps trail map** (BotW-style), tied to journal days.
2. **Your Year**, a yearly recap.
3. A **lightweight, scalable core**: per-character partitioned storage, facts instead of prose,
   counters for high-volume events, and native Settings panel plus keybinding.

Its code is All Rights Reserved and forbids public derivative releases, so we take **no code, text,
icons or locale strings** from it. We only use the observable facts about which Forever APIs and
events work, which are listed in §12.
