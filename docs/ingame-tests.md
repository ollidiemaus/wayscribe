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

- [ ] **The book opens and looks right.** `/ws`: leather cover, two parchment pages, readable dark
  text without shadows, the long date in the title font ("Samstag, 3. Oktober 2026"). Screenshot
  it.
- [ ] **Day list.** Month headings, "Heute"/"Gestern" on the right, mouse wheel and scroll bar work
  (ScrollBox). Clicking a day shows it; the selected row is highlighted.
- [ ] **Turning pages.** *< Älter* / *Neuer >* move one day and are disabled at the ends. Is the
  page-turn sound there?
- [ ] **Filter chips.** Turn off *Sammeln*: ore lines disappear, days with only ore leave the list.
  After `/reload` the filter is still off.
- [ ] **Resize and move.** Drag the corner grip and the cover; after `/reload` size and position
  are kept. Long entries wrap at the new width.
- [ ] **Live updates.** With the journal open on today, kill a mob with loot or level up: the page
  updates without flicker.
- [ ] **Times** show as `14:05` with the 24-hour clock on and `2:05 PM` with it off (Game Menu >
  Options > the clock setting), after reopening the journal.
- [ ] **Login recap** *Tagebuch öffnen* opens the journal at the recap's day.

### Quest chains

- [ ] **`/ws probe` with a few quests in the log.** Paste the `questLine.*` and `questTitle.*` lines
  into forever-probe.md. Answers §12 #4: does `C_QuestLine` know Vanilla quests?
- [ ] **Turn in any quest.** The day shows "Quests abgegeben: 1".
- [ ] **Complete a curated chain**, the easiest being the druid bear form (Body and Heart) or the
  Defias Brotherhood. Expect "Questreihe abgeschlossen: …" with the time.
- [ ] **Back-fill on a real journal.** Developer mode, then
  `/ws simulate QUEST_CHAIN_COMPLETED chain=DEFIAS quest=166` shows how a chain entry reads;
  `/ws simulate clear` removes it.
