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

- [ ] **Learn a gathering profession.** Expect "Bergbau erlernt" (or similar).
- [ ] **`/ws probe` with professions learned.** Paste into forever-probe.md. Answers §12 #2: is the
  skill line ID the parent (186) or a child (2946), and does First Aid show up?
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
