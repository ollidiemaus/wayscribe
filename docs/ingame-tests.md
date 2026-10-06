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
- [ ] **Hearthstone or a portal.** No line across the jump. *2026-10-06: a hearthstone within
  Mulgore (no loading screen) drew a straight 688-yard line. The jump was measured from the last
  kept point, and the 10 s cast standing still made it look like a walk. Jumps are now measured
  from the previous second's sample. Check again.*
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

### Deaths

- [x] **Die outdoors.** The journal shows "In Mulgore gestorben" (with the time), and the map shows a
  skull where you died. Mouseover: "Hier gestorben" and the time; the skull keeps its size when
  zooming. With the map open while dying, the skull appears at once. *Entry, skull and tooltip
  shown (2026-10-06).*
- [ ] **Next day / Letzte 7 Tage:** yesterday's skull shows with the date in its tooltip; "Heute"
  hides it.
- [ ] **Die in a dungeon.** The journal names the dungeon ("In Flammenschlund gestorben" or
  similar); no skull, since there is no position inside.
- [ ] **Release and resurrect** don't add a second entry.
