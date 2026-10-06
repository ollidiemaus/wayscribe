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
