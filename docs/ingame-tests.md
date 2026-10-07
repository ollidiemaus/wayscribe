# In-game tests

Wayscribe is an addon that keeps an automatic journal of your character: it records what happens
while you play (levels, dungeons, bosses, professions, quests, deaths, where you walked) and shows it
day by day. The [README](../README.md) has the full tour.

The unit tests cover the logic. The checks below need the real Forever client: does the game fire
the events, does it look right, is it fast enough.

## Setup

1. Put the Wayscribe folder you were given (with its `Libs/` folder) into
   `_classic_beta_/Interface/AddOns/`.
2. In game, type `/ws dev` once. Errors then also show up in BugSack (if you have it), and a few test
   commands unlock. It stays on until you type it again.
3. After each session, `/ws log` should say "No errors recorded." If not, note what it shows.

**Where things are**
- `/ws` opens the journal: the day list on the left, the selected day on the right, the tabs
  *Journal* and *Your Year* below.
- The world map has a *Footsteps: Today* button in its top right corner.
- Settings: Options > AddOns > Wayscribe.
- `/etrace` is the game's own event trace, for the "does this event fire?" checks.

**Reporting.** Tick the box and add a short note in *italics* under the test, with the date. Say what
you saw only if it differs from the expectation; for looks, a screenshot helps. Quoted texts are the
English client's; a German client shows the German ones.

**Start here** if time is short: the [dungeon run with a reload](#dungeons-and-bosses), a
[flight](#footsteps-on-the-world-map), [`/ws stats` after two hours](#footsteps-on-the-world-map)
and [a journal file that didn't load](#backup).

## Dungeons and bosses

- [ ] **A full dungeon run with a `/reload` halfway** (most important). Run Ragefire Chasm (or any
  dungeon) to the end and `/reload` once in the middle. → One "Defeated *boss* for the first time"
  per boss, and on leaving **one** entry "First clear of Ragefire Chasm with *your group*
  (*xx* min)".
- [ ] **Full names.** After a dungeon run with a group, look at its entry. → Your companions are
  named with first name and surname ("with Xy Ashford and Ab Stonebrook"), also in an entry made
  before this update.
- [ ] **Corpse run.** In a dungeon, die, release, run back within 30 minutes and finish. → Still one
  run entry.
- [ ] **Leave early.** Leave a dungeon before the last boss and stay out for 30 minutes. → "Visited
  *dungeon* and defeated *N* bosses", dated when you left.
- [ ] **Die in a dungeon.** → "Died in *dungeon*". No skull on the map (there's no position inside).
- [ ] **Position inside.** In a dungeon, run `/ws probe`. → Note what the `unitPosition` line says
  (probably nil).
- [ ] **Dungeon finder**, if Forever has one. With `/etrace` open, finish a finder dungeon. → Note
  whether `LFG_COMPLETION_REWARD` or `SCENARIO_COMPLETED` fires at the end.

## Professions and gathering

- [ ] **Skill up to 75.** → The day shows "Skill gains: Mining +*N*", and an entry "Mining reached
  75".
- [ ] **Gather.** Mine a vein that takes several hits, pick a herb, skin a creature. → "Ore deposits
  mined: 1", "Herbs picked: 1", "Creatures skinned: 1", and the items under "Gathered …".
- [ ] **Full bags.** Leave an item in the loot window because your bags are full. → It isn't counted.
- [ ] **Gather spell.** With `/etrace` open, mine a vein. → Note the spell ID that
  `UNIT_SPELLCAST_SUCCEEDED` shows, and whether it's readable or hidden (secret).
- [ ] **First Aid.** Learn First Aid, then `/ws probe`. → Is there a `profession.…` line for it?

## Quests

- [ ] **Turn in a quest.** → The day shows "Quests turned in: 1".
- [ ] **Finish a known quest chain**, e.g. the druid's bear form or The Defias Brotherhood. →
  "Completed the quest chain: …" with the time.
- [ ] **How a chain entry reads.** `/ws simulate QUEST_CHAIN_COMPLETED chain=DEFIAS quest=166`. → An
  entry appears, marked as a test; `/ws simulate clear` removes it.

## Footsteps on the world map

Wayscribe draws where you walked as a dark red line on the world map.

- [ ] **Flight.** Take a flight path. → A thinner blue line from flight master to flight master, joined
  to the walk before and after. With Settings > *Record flight paths* off, a flight leaves no line.
- [ ] **Combat.** Fight a few mobs while moving. → The line has no gaps.
- [ ] **Distance.** → The day page shows "Traveled *x* miles" (and "Flight paths: …" after a flight).
- [ ] **Size.** After about two hours of play, `/ws stats`. → The "Footsteps: … KB packed" line is
  well under 10 KB. Note the number.
- [ ] **Speed.** Footsteps on or off (Settings > Tracking) makes no FPS difference with the map closed.
  With several days of trails, set the map button to *All* and open a continent map. → No stutter.
- [ ] **Map levels.** → The trail shows on the zone and the continent map. The world map (all of
  Azeroth) shows none, and no error.
- [ ] **From the journal.** On a day with trails, click *Show on the map*. → The map opens in front of
  the journal, at that day's zone, showing only that day. After closing the map, the button says
  *Today* again.
- [ ] **Footsteps settings.** The map dropdown and the flights checkbox work. *Delete all trails*
  asks first (try it only on a test character).

## Journeys and deaths

- [ ] **Hearthstone to another continent** (with a loading screen). → An entry "Hearthstone to …";
  each continent's map shows the hearthstone icon at its end.
- [ ] **Summon or boat.** → No entry, no icon; the line just breaks.
- [ ] **Die at a named place**, e.g. Red Cloud Mesa. → "Died in Red Cloud Mesa, Mulgore".
- [ ] **Release and resurrect.** → No second death entry.
- [ ] **Yesterday's death.** The next day, set the map button to *Last 7 days*. → Yesterday's skull
  shows, with the date in its tooltip. *Today* hides it.

## Journal and windows

- [ ] **Day list.** → Month headings, "Today" and "Yesterday", a soft shadow on the selected day. The
  scroll bar appears only when there are more days than fit.
- [ ] **Turning pages.** → The arrows move one day, are disabled at the ends, and play the page sound.
- [ ] **Filter.** Click *Filter* at the top and untick *Gathering*. → Ore lines disappear, and days
  with nothing else leave the list. After `/reload` it's still off.
- [ ] **Resize and move.** Drag the corner and the title bar. → The page art stretches and long
  entries wrap. After `/reload`, size and position are kept.
- [ ] **Live.** With the journal open on today, loot ore or level up. → The page updates without
  flicker.
- [ ] **Item names.** → Gathered items show their names, not "item 2770" (they may fill in a moment
  later).
- [ ] **Clock.** → Times read `14:05` with the game's 24-hour clock on, `2:05 PM` with it off.
- [ ] **Login recap.** At the first login of a new day. → A "Last session" window lists your previous
  session. *Open journal* opens that day; *Don't show at login* works; `/ws recap` shows it again.
- [ ] **Settings page.** → The toggles, the date format and the Data buttons work. *Reset journal*
  only on a test character.
- [ ] **Minimap button.** → Left-click opens the journal, right-click the settings, dragging moves it,
  and the settings can hide it.
- [ ] **Addon Compartment and key binding.** → The entry in the addons button at the minimap opens
  the journal; so does a key set under Options > Keybindings > AddOns > Wayscribe.
- [ ] **Export button.** Settings > Data > *Export...* → Opens the same window as `/ws export`.

## Your Year

The journal's second tab: a look back at the year, card by card.

- [ ] **Live.** With `/ws dev` on and the tab open, level up or loot ore. → The cards update.
- [ ] **The prompt** (optional; needs the computer's clock set to December 1). Log in and close the
  "Last session" window. → A "Your 2026 is ready!" popup and a chat line; *Show* opens the tab. The
  next login doesn't ask again.

## Backup

- [ ] **A journal file that didn't load.** On a test character:
  1. `/ws backup`, Ctrl+C, and paste the text into a file.
  2. Close the game. Move `Wayscribe.lua` and `Wayscribe.lua.bak` out of
     `WTF/Account/<account>/<realm>/<character>/SavedVariables/` (keep them).
  3. Log in. → A chat warning that the journal didn't load, mentioning `/ws restore`. `/ws log` has
     a line about it; BugSack has **nothing**.
  4. `/ws restore`, paste the backup with Ctrl+V, *Restore...*, confirm. → The interface reloads with
     the journal and the map trails back.
  5. Log out. → A new `Wayscribe.lua` is in that `SavedVariables` folder.
- [ ] **Another character** (optional). On a new character, restore the test character's backup. →
  The confirmation says it belongs to another character; after the reload the journal is this
  character's (its name is in the `/ws export` header).

## Already verified

Done on builds 70235 and 70245 (2026-10-06 and 07); no need to repeat. Details are in
[ARCHITECTURE.md §12](ARCHITECTURE.md#12-verify-on-the-forever-beta-run-ws-probe) and
[forever-probe.md](forever-probe.md).

- **Probe:** all needed APIs, events, gather and travel spell names, and the libraries are there. A
  profession reports its parent skill line (Skinning 393). `C_QuestLine` knows no Vanilla quests, so
  only the curated chains count. The world-to-map math matches the client exactly. Coverage finds
  50 zones, Forever's Zephras Isle included.
- **Professions:** learning Skinning makes an entry.
- **Names:** `/ws probe` shows `has.surnames = true`, and your character is saved with first name,
  surname and realm.
- **Journal:** looks like the spellbook (frame, parchment, headers, page buttons); the filter menu
  opens; times use the 24-hour clock.
- **Icon:** the quill-on-a-map icon shows in the addon list, on the minimap button, in the Addon
  Compartment, as the journal's portrait on both tabs and on Your Year's first card.
- **Footsteps:** the trail lies on the roads you took, on the full and the small map, and grows while
  the map is open. Standing still leaves no gap; a hearthstone draws no line; a ghost isn't followed;
  `/reload` keeps the trail (with a small gap). The map's icons sit above the lines, the map button
  sits top right, and *Show on the map* opens the right zone.
- **Journeys and deaths:** a hearthstone within a zone makes an entry and an icon at both ends. A
  death outdoors makes an entry and a skull with a tooltip.
- **Your Year:** rollups are rebuilt silently after updating; `/ws stats` matches the saved file's
  size; the tabs look like the default UI's; all cards and icons show in the preview; the Footsteps
  card measures the share of Azeroth. The text export copies correctly, umlauts included. With
  `/ws dev` off, the tab says the year opens on December 1.
- **Backup:** a very active year (2.47 million characters) pastes back in 2.8 s and is checked in
  1.2 s. A real backup matches `/ws stats`; the Settings buttons open it; it's refused for a journal
  with entries; Reset then restore brings everything back; a journal whose file was moved away is
  restored without `/ws accept`, map trails included.
