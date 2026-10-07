# In-game tests

These checks need the real Forever client; the unit tests can't answer them. Each item says what it
proves, and where the answer goes. Tick items off here when they're done.

Setup: copy the addon with its `Libs/` folder into `Interface/AddOns/Wayscribe` (see README). Turn on
`/ws dev` so errors also reach BugSack, and check `/ws log` after each session.

## 0.2 Adventurer (open)

Probe results from 2026-10-06 are already in [forever-probe.md](forever-probe.md): APIs, events,
gather spell names and libraries are all present.

### Dungeons and bosses (release exit criterion)

- [ ] **Full Ragefire Chasm run with a `/reload` in the middle.** Expect one "… zum ersten Mal
  besiegt" entry per boss and, on leaving, "… zum ersten Mal abgeschlossen mit …
  (xx Min.)" as **one** entry. Answers §12 #1: do `ENCOUNTER_END` / `BOSS_KILL` fire for Vanilla
  bosses?
- [ ] **Corpse run.** Die, release, run back in within 30 min, finish: still one run.
- [ ] **Leave before the final boss.** After 30 min outside, a "… besucht und N Bosse besiegt" entry
  appears, dated when you left.
- [ ] **Dungeon finder**, if Forever has one: do `LFG_COMPLETION_REWARD` or `SCENARIO_COMPLETED` fire
  at the end? (§12 #7; `/etrace` shows events.)

### Professions and gathering

- [x] **Learn a gathering profession.** Expect "Bergbau erlernt" (or similar). *Skinning learned
  2026-10-06: `PROFESSION_LEARNED {skillLine = 393}` with the first-time mark.*
- [x] **`/ws probe` with professions learned.** Paste into forever-probe.md. Answers §12 #2: is the
  skill line ID the parent (186) or a child (2946), and does First Aid show up? *The parent: 393
  Kürschnerei 3/75. First Aid is still open (not learned yet).*
- [ ] **Skill up and reach 75.** Expect "Fertigkeitspunkte: Bergbau +N" in the day and "Bergbau auf
  75 gebracht".
- [ ] **Mine a vein that takes several hits, pick a herb, skin a mob.** Expect one node each and the
  looted items under "Gesammelt: …". Leave one item in the loot window with full bags: it must not
  count.
- [ ] **Which spell ID does a gather cast report, and is it secret?** Watch
  `UNIT_SPELLCAST_SUCCEEDED` in `/etrace` while mining. (§12 #6)

### UI

- [ ] **Login recap.** At the first login of the next day, the "Letzte Sitzung" popup lists the last
  session. *Tagebuch öffnen* and the *nicht mehr zeigen* checkbox work; `/ws recap` shows it again.
- [ ] **Settings page** (Options > AddOns > Wayscribe): toggles, date format dropdown, the data
  buttons. Try *Tagebuch zurücksetzen* only on a test character.
- [ ] **Minimap button**: left-click opens the journal, right-click the settings, drag moves it,
  hiding it in settings works.
- [ ] **Addon Compartment** entry and the **key binding** (Key Bindings > AddOns > Wayscribe).
- [ ] **Journal** shows the day's counter lines, and item names fill in once loaded.

### Secret values

- [ ] After a session with lots of combat, `/ws log` has no errors from trackers. (§12 #5)

## 0.3 Chronicler (open)

Unit tests cover the exit criterion (a curated chain added after the fact back-fills on the right
day, once). These checks need the client.

### Journal

- [x] **It looks like the spellbook.** `/ws` next to the spellbook: the same frame (portrait with
  the book icon, title "Wayscribe"), the same two-page parchment, headers in the spellbook's dark
  brown with the ornament line, "Seite 3/12" with the spellbook's arrow buttons. Screenshot it. Do
  the text margins fit the page art (nothing on the torn edge or the spine)? *Yes (2026-10-06,
  after moving the text off the page art's top bar and darkening the secondary text). The filter
  menu opens with the four categories; times and sessions show in 24-hour format.*
- [ ] **Day list.** Month headings, "Heute"/"Gestern" on the right, the selected day has a soft
  shadow. The thin scroll bar appears only with more days than fit.
- [ ] **Turning pages.** The arrows move one day, are disabled at the ends and play the page sound.
- [ ] **Filter menu.** *Filter* in the top bar opens checkboxes per category. Turn off *Sammeln*:
  ore lines disappear, days with only ore leave the list. After `/reload` it's still off.
- [ ] **Resize and move.** Drag the corner grip and the title bar; after `/reload` size and position
  are kept. The parchment stretches with the window; long entries wrap at the new width.
- [ ] **Live updates.** With the journal open on today, loot ore or level up: the page updates
  without flicker.
- [ ] **Times** show as `14:05` with the 24-hour clock on and `2:05 PM` with it off.
- [ ] **Login recap** *Tagebuch öffnen* opens the journal at the recap's day.

### Quest chains

- [x] **`/ws probe` with a few quests in the log.** Paste the `questLine.*` and `questTitle.*` lines
  into forever-probe.md. Answers §12 #4: does `C_QuestLine` know Vanilla quests? *No: nothing for
  747 and 752 (2026-10-06), so only curated chains count.*
- [ ] **Turn in any quest.** The day shows "Quests abgegeben: 1".
- [ ] **Complete a curated chain**, the easiest being the druid bear form (Body and Heart) or the
  Defias Brotherhood. Expect "Questreihe abgeschlossen: …" with the time.
- [ ] **Back-fill on a real journal.** Developer mode, then
  `/ws simulate QUEST_CHAIN_COMPLETED chain=DEFIAS quest=166` shows how a chain entry reads;
  `/ws simulate clear` removes it.

## 0.4 Footsteps (open)

Unit tests cover the size half of the exit criterion: two hours of simulated questing pack into
about 3.2 KB (budget 10 KB). These checks need the client.

### Probe

- [x] **`/ws probe` outdoors, standing in a zone.** Paste the new lines (`has.taxiState`,
  `has.worldMapCanvas`, `worldMap.frame`, `taxi`, `map.corners`, `map.fromWorld`, `map.atWorld`,
  `map.parent`) into forever-probe.md. `map.fromWorld` must match `map.position` to about three
  decimals: that proves the world-to-map transform. (§12 #3, #9) *Exact match, 0.4422, 0.7712
  (2026-10-06). `map.atWorld` gave the continent, not the zone; fixed by walking down the maps.*
- [ ] **`/ws probe` inside a dungeon.** Is `unitPosition` nil there? (§12 #3)

### Recording

- [x] **Walk and ride for a few minutes, then open the world map.** A dark red line follows your
  way, ending where you stand, and keeps growing while the map stays open. Does it lie on the roads
  you took (not mirrored or shifted)? *2026-10-06: in the right place, and complete on the
  full-screen map. On the small map (with the quest log) at its default zoom, the trail being
  recorded broke up; zooming in showed it. Cause: its lines (8 yards a point) are under a pixel
  there. A first fix (re-laying out the lines after drawing) didn't help; lines are now at least
  3 pixels long, with a tail to the player, and drawn again after zooming. Rechecked: the line
  stays whole and follows you on the small map too.*
- [x] **Stand still for a minute, then walk on.** The line continues without a gap. *Yes (2026-10-06).*
- [ ] **Take a flight.** The flight is a thinner blue line from flight master to flight master, the
  walk before and after joins it. With *Record flight paths* off, the flight leaves no line.
- [x] **Hearthstone or a portal.** No line across the jump. *2026-10-06: a hearthstone within
  Mulgore (no loading screen) drew a straight 688-yard line. The jump was measured from the last
  kept point, and the 10 s cast standing still made it look like a walk. Jumps are now measured
  from the previous second's sample. Check again: no line, and see "Journeys" below.* *Rechecked
  with the 0.5 copy: the trail ends 18 s before the cast finished, and no stored step covers the
  340-yard jump (2026-10-06).*
- [x] **Die and run back as a ghost.** The ghost's way is not drawn. *Yes; after resurrecting, the
  trail goes on from the respawn spot (2026-10-06).*
- [ ] **Fight a few mobs while moving.** The line has no gaps from combat. (Is the position
  secret in combat? §12 #5)
- [x] **`/reload` while walking.** The trail so far stays on the map; recording goes on. *Yes,
  with a small gap where the reload was (2026-10-06): a reload ends the trail, and the new one
  starts where you are once the UI is back.*
- [ ] **Day page.** The journal shows "Zurückgelegt: 2,4 km" (and "Flugrouten: …" after a
  flight).
- [ ] **`/ws stats` after about two hours of play.** The "Fußspuren: … KB gepackt" line should be
  well under 10 KB (exit criterion). Note the number here.
- [ ] **Frame time.** With the map closed, the FPS doesn't change between Footsteps on and off
  (exit criterion). With "Alle" on a continent map, opening the map doesn't stutter. *No frame rate
  change noticed in the first sessions (about 63-66 FPS, map open or closed); "Alle" with a few
  days of trails is still to try.*

### Map

- [x] **Where the lines land.** Above the map art and explored areas, below the quest and flight
  master icons? Zooming in keeps the lines equally thin. *Yes: the map's icons are drawn over the
  lines (2026-10-06).*
- [x] **The "Fußspuren: Heute" button** (upper right of the map) isn't hidden behind the map's own
  controls. *At first it sat in the lower left, over the client's own coordinates; moved to the
  upper right, which looks good (2026-10-06).* Its menu switches between Heute, Letzte 7 Tage, Alle and Aus; older days are lighter.
- [ ] **Zone, continent, world.** The trail shows on the zone and the continent map; the world map
  (all of Azeroth) shows none and no error.
- [ ] **From the journal.** On a day with trails, the *Auf der Karte zeigen* button (now a real
  button; the text link was easy to miss) opens the map at that day's zone with only that day
  (*opens Mulgore, 2026-10-06*); does the map come up in front of the journal? After closing the
  map, it shows "Heute" again.
- [ ] **Settings:** the Fußspuren section (map dropdown, flights, *Alle Spuren löschen* with its
  confirmation). Try deleting only on a test character.

### Journeys

- [x] **`/ws probe`:** the `spell.travel.*` lines name Ruhestein, Astraler Rückruf and the mage
  teleports in German; `subZone` names where you stand. *All eight named, `subZone = Bloodhoof`
  (2026-10-06). The list has since grown (Moonglade, Dalaran, the transporters): all 19 named in
  German in the next probe.*
- [x] **Hearthstone within a zone** (e.g. to Bloodhoof). The journal shows "Ruhestein nach
  Bloodhoof" under *Reisen*, at the time you arrived. The map shows the hearthstone's icon where
  you cast it and where you arrived; mouseover: "Ruhestein nach Bloodhoof" and "Mit Ruhestein
  angekommen". No line between them. *Worked, icons shown at both ends (2026-10-06); the saved
  `TELEPORT` has spell 8690, both places and `sub = "Bloodhoof"`.*
- [ ] **Hearthstone to another continent** (a loading screen): the entry appears; each continent's
  map shows its end.
- [ ] **A summon or a boat** (no travel spell): no entry, no icon, just a break in the trail.

### Deaths

- [ ] **Die in a named spot** (e.g. Red Cloud Mesa): the entry reads "In Red Cloud Mesa, Mulgore
  gestorben".
- [x] **Die outdoors.** The journal shows "In Mulgore gestorben" (with the time), and the map shows a
  skull where you died. Mouseover: "Hier gestorben" and the time; the skull keeps its size when
  zooming. With the map open while dying, the skull appears at once. *Entry, skull and tooltip
  shown (2026-10-06).*
- [ ] **Next day / Letzte 7 Tage:** yesterday's skull shows with the date in its tooltip; "Heute"
  hides it.
- [ ] **Die in a dungeon.** The journal names the dungeon ("In Flammenschlund gestorben" or
  similar); no skull, since there is no position inside.
- [ ] **Release and resurrect** don't add a second entry.

## 0.5 Your Year (open)

Unit tests cover the exit criterion: a played year's cards come out the same after every day of the
journal was deleted, so the recap renders from rollups (and sessions) alone. They also cover the
prompt's timing (December 1, the January catch-up, once per year, after the login recap). These
checks need the client.

### Probe and upgrade

- [x] **`/ws probe` outdoors.** Paste `has.mapChildren`, `has.panelTabs`, `coverage.zones` and the
  `coverage.continent.*` lines into forever-probe.md. Do the zones and square miles look like
  Kalimdor and the Eastern Kingdoms (roughly 20-25 zones each)? An unexpected continent ID with a
  few zones would inflate the total. (§12 #10, #11) *Both true; Kalimdor 23 zones, Eastern
  Kingdoms 26, plus continent 2991 with one zone: Forever's Zephras Isle (UiMap 2521, under
  Azeroth), which belongs in the count (2026-10-06).*
- [x] **First login after updating.** The rollups are rebuilt once, silently: `/ws log` stays
  empty, the journal looks the same, and the saved file has `["rollup"] = 2` under `meta`. *Yes:
  `rollup = 2`, no new log entries (2026-10-06).*
- [x] **`/ws stats`.** The new line "Gespeicherte Datei: Tagebuch etwa … KB, Fußspuren etwa … KB"
  should match the size of `Wayscribe.lua` in the character's SavedVariables folder (after a
  `/reload`, to within a few percent). *The estimate, run on the saved file, gives 4,055 bytes for
  the 4,056-byte file (2026-10-06).*

### The tab

- [x] **Tabs under the journal**: "Tagebuch" and "Dein Jahr" look like the spellbook's or the
  character frame's tabs, sit right under the frame, and switch. On "Dein Jahr" the filter menu is
  gone; back on "Tagebuch" it returns. Screenshot it. *Screenshots 2026-10-06: the default UI's
  tabs under the frame, the chosen one raised.*
- [ ] **Before December**: "Dein 2026" says when it opens (Dienstag, 1. Dezember 2026).
- [x] **Preview with `/ws dev`**: the page switches to the cards at once, subtitle "Dein 2026 ·
  Vorschau". Read every card in German: do the texts read well, and do all icons show (no green
  squares)? Is the big number large but inside the page? Turn the cards with the page buttons
  ("Seite 3/11", page sound) and by clicking them in the list. *Seven cards on this character
  (Blick, Stufen, Tode, Berufe, Quests, Fußspuren, Spielzeit), all icons shown, big numbers inside
  the page, "Vorige Karte" / "Nächste Karte" on the buttons (2026-10-06). The dungeon, boss,
  companion and gathering cards need a character with those.*
- [x] **Footsteps card**: briefly "Wird gemessen …", then "Du bist x % von Azeroth abgelaufen" and
  "Am meisten erkundet: Mulgore (y %)". Note x and y here. No stutter while it measures. *x =
  0,1 %, y = 2,2 % after 5,7 km (2026-10-06).*
- [ ] **Live**: with the tab open, level up or loot ore: the cards update.

### Prompt

- [ ] Optional, needs the computer's clock set to December 1 (or later): at login, after the
  "Letzte Sitzung" window is closed, the popup "Dein 2026 ist fertig!" appears with a chat line;
  *Anzeigen* opens the tab. The next login doesn't ask again.

### Export

- [x] **`/ws export`**: the window opens with the text selected. Ctrl+C, paste into a text editor:
  dates, times and German umlauts come through, entries line up under their times. *Dieser
  Monat* / *Dieses Jahr* / *Alles* switch the text. Escape closes it. *Looks good (2026-10-06).*
- [ ] **Settings > Daten > Tagebuch exportieren** opens the same window.

## 0.6 Backup (open)

Unit tests cover the first half of the exit criterion: a simulated year of journal and trails
survives backup, Reset and restore with the same facts, the same caches and the same Your Year
cards. They also cover the rules: a journal with entries is refused, a missing, renamed or empty
one is restored, another character's backup takes this character's identity, read-only trails are
left alone, and a cut-off, changed or wrapped paste is caught or tolerated. These checks need the
client.

### The clipboard (done: one string is enough)

First build (2026-10-07): a multi-line box for the backup, the paste collected from `OnChar`.

- [x] **`/ws dev`, then `/ws backup sample`.** *"Sicherung in 3,7 s erstellt (2416,5 KB)". The text
  was invisible until clicking into the box, and Ctrl+A lagged briefly and hid it again: the
  multi-line box can't draw 2.4 MB. Now a one-line field.*
- [x] **The same text in a text editor**: *2,474,487 characters arrived through Ctrl+C.*
- [x] **Ctrl+C, `/ws restore`, Ctrl+V.** *Every character came through `OnChar` (2,474,487), but the
  window froze: "Das Einfügen dauerte 28,3 s, die Prüfung 1,2 s". About 11 µs per character,
  one script call each: too slow. The box kept only its first 4,000 bytes, which looked like a
  cut-off paste. The sample's *Wiederherstellen...* stays disabled on purpose (a made-up year
  must not go into a real journal), but the reason was easy to miss. Now: a one-line field
  without a limit, read once per paste, and the reason in red.*

Second build: one-line fields, the restore field without a limit and no script per character.

- [x] **The paste, step by step.** *7 days: 49,899 characters, 3.3 s; 30 days: 205,724 characters,
  55.6 s (2026-10-07). 4.1 times the characters took 16.8 times as long: the square. The client
  inserts a paste character by character and works through everything the field holds each time,
  about 2.6 ns per character held. The 365-day step would have taken about two hours and was
  rightly skipped.*

Third build: the field holds 32 bytes, the paste is collected from `OnChar`.

- [x] **`/ws backup sample`**: the field shows the beginning of the backup (`WSB1:…`), selected.
  *Right away for 7 and 30 days; for the year, "Die Sicherung wird erstellt ..." first, then the
  backup (2026-10-07).*
- [x] **The paste, step by step.** *7 days: 49,899 characters, paste 0.1 s, check 0.0 s; 30 days:
  205,724, 0.2 s, 0.1 s; the year: 2,474,487, 2.8 s, 1.2 s (2026-10-07). In line with the size; a
  very active year pastes back and is checked in about 4 s. One string is enough.*

### A real backup

- [ ] **`/ws backup`** on the test character: "Mit Fußspuren" is ticked and the line beside it
  matches `/ws stats` (entries, days, trails). Unticking it makes a smaller backup without trails.
- [ ] **Settings > Daten**: *Tagebuch sichern* and *Sicherung wiederherstellen* open the same windows.
- [ ] **Into the same character**: pasted into `/ws restore`, the status says in red "Dieses Tagebuch
  hat schon Einträge …" and *Wiederherstellen...* stays disabled.

### A journal that didn't load (release exit criterion)

- [ ] Make a backup with footsteps and save it in a file. With the game closed, **move**
  `Wayscribe.lua` (and its `.bak`) out of the character's `SavedVariables` folder; keep them. Log
  in: the read-only warning now mentions `/ws restore`. Paste the backup into `/ws restore`, click
  *Wiederherstellen...*: the popup names the backup and says that the file which didn't load is
  overwritten. Confirm: the interface reloads, the journal is back (same days and entries, same
  Your Year cards), there is no read-only banner and no `/ws accept` was needed. `/ws log` shows
  no `backup` errors.
- [ ] After that reload: the world map shows the trails again (*Letzte 7 Tage* / *Alle*), and after
  logging out a new `Wayscribe.lua` is in the folder.

### Other characters

- [ ] Optional, on a new character: restore the test character's backup. The popup says it belongs
  to another character; after the reload the journal is this character's (its name in the export
  header).
