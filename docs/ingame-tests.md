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
  *Journal*, *Notes*, *Maps* and *Your Year* below.
- The world map has a *Footsteps: Today* button in its top right corner.
- Settings: Options > AddOns > Wayscribe.
- `/etrace` is the game's own event trace, for the "does this event fire?" checks.

**Reporting.** Tick the box and add a short note in *italics* under the test, with the date. Say what
you saw only if it differs from the expectation; for looks, a screenshot helps. Quoted texts are the
English client's; a German client shows the German ones.

**Start here:** the [beta session for the launch trackers](#beta-session-the-launch-trackers),
before the beta closes on October 21. After that, if time is short: the
[dungeon run with a reload](#dungeons-and-bosses), a [flight](#footsteps-on-the-world-map),
[`/ws stats` after two hours](#footsteps-on-the-world-map) and
[a journal file that didn't load](#backup).

## Beta session: the launch trackers

Wayscribe 1.0 adds trackers for the game's launch: first visits to zones, gold, reputation,
notable gear, Legacy Challenges, flight paths, guild, home, collections and PvP rank (what each
one records: [ARCHITECTURE.md §6.11](architecture/06.11-launch-trackers.md)). This one session
before the beta closes is all the testing they get before launch, and the rest
is [checked after launch](#after-launch).

**When:** in the stress test on October 19 if it lets you play, otherwise on October 20 or 21, with
the build from October 19 evening or later. **Who:** a **new level 1 character**, any race, with
developer mode on (`/ws dev`). **Route** (30 to 45 minutes): the starting area, the first town with
an inn, then the capital, for example Northshire, Goldshire and Stormwind, or Camp Narache, Bloodhoof
Village and Thunder Bluff. The texts below are the expected meaning, not the exact wording.

- [ ] **The probe**, right after logging in: `/ws probe`. → Lines starting with `firstVisit.`, `gold.`,
  `rep.`, `gear.`, `legacy.`, `flightPaths.`, `guild.`, `home.`, `collections.`, `pvpRank.` and `weaponSkill.`. None
  says "error". The probe is saved with the game's files, so nothing needs copying.
- [ ] **The starting zone.** → Today's page starts with the first visit to the starting zone.
- [ ] **Gear.** Equip a quest reward. → No entry unless it is blue or better, but `/ws trace` lists
  the change.
- [ ] **Reputation.** Turn in a few quests. → `/ws trace` lists reputation updates. An entry only if
  a standing changes (Neutral to Friendly).
- [ ] **Gold.** Sell something to a vendor, then buy something. → Today's page: one gold line with
  earned and spent.
- [ ] **Home.** Set your hearthstone at the town's inn. → An entry that the inn's place is now your
  home.
- [ ] **A new zone or city.** Walk into the next zone or the capital. → A first visit for it.
  `/reload` and walk out and in again. → No second entry.
- [ ] **A flight path.** Talk to the capital's flight master, and with the taxi map open, type
  `/ws probe` again. → An entry for the new flight path, and the probe's `flightPaths.` lines count
  the known nodes.
- [ ] **Weapon skills.** Open Character > Skills and type `/ws probe` with the *Weapon Skills*
  header open, then again with it closed. → Both times the same `weaponSkill.` lines, one for each
  weapon skill the tab lists, Defense included, no Dual Wield and no weapon the character hasn't
  learned, each with the rank/max the tab shows without the racial bonus. Hit a few mobs until your
  weapon skill gains a point, probe again. → Its rank is one higher.
- [ ] **At the end:** `/ws log` says "No errors recorded.", and `/ws trace` shows what each tracker saw.

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

## Dungeon maps

So far only Ragefire Chasm, Wailing Caverns, the Deadmines and the Hall of Thanes have a map.

- [ ] **Arrive.** Enter Ragefire Chasm (or Wailing Caverns) and type `/ws map`. → The journal opens
  on *Maps* with the dungeon's map across both pages. Everything is under fog but the entrance.
  Note whether the map shows at all (a blank or green square means the client lacks the file).
- [ ] **Reach a boss.** Pull a boss (a wipe is fine) with the map open. → Its room and the way to it
  clear within about a second. The rest stays fogged.
- [ ] **Right rooms?** After each boss, look at what cleared. → Note any boss whose room cleared in
  the wrong place, with the boss's name. (Ragefire Chasm's printed skulls mark later bosses; the
  fog follows Forever's.)
- [ ] **Outside.** Leave the dungeon, open the journal's *Maps* tab. → The dungeon is listed with
  "*N*% charted". The map shows what you found, under the same fog. *Unfold map* spreads it, *Fold
  map* goes back. The page buttons turn floors in the Deadmines.
- [ ] **Whole map.** Kill every boss of a dungeon. → A journal entry "Charted *dungeon* completely".
- [ ] **Older runs.** A character who ran a dungeon with an older Wayscribe logs in. → That
  dungeon's map already shows the rooms of the bosses killed back then.
- [ ] **Key binding.** Bind *Open or close the dungeon map* (Key Bindings > AddOns). → Inside a
  dungeon it opens the map; pressed again it closes.
- [ ] **German.** On a German client: tab *Karten*, "*N* % kartiert", the Deadmines are
  "Todesminen". Note whether the map's printed labels ("Goblin Foundry") show in German.
- [ ] **Hall of Thanes.** Run it. → The map is the hall seen from above (the game's minimap images).
  Note whether each boss's room cleared where you fought it: Faldrim, Infurnus, Plunder, Durgen.
- [ ] **Hidden.** Turn off *Show dungeon maps* (Options > AddOns > Wayscribe > Dungeon maps), then
  pull a boss you haven't reached. → No *Maps* tab, Your Year sits next to Notes; `/ws map` and the
  key binding print "Dungeon maps are turned off …". Turn it back on. → The tab is back and the
  boss's room is clear.
- [ ] **Look.** Note what the fog looks like: too dark, too blocky, does the edge read as unexplored?
  A screenshot helps.

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

- [ ] **Finish a known quest chain**, e.g. the druid's bear form or The Defias Brotherhood. →
  "Completed the quest chain: …" with the time.
- [ ] **How a chain entry reads.** `/ws simulate QUEST_CHAIN_COMPLETED chain=DEFIAS quest=166`. → An
  entry appears, marked as a test; `/ws simulate clear` removes it.

## Footsteps on the world map

Wayscribe draws where you walked as a dark red line on the world map.

- [ ] **Flight.** Take a flight path. → A thinner blue line from flight master to flight master, joined
  to the walk before and after. With Settings > *Record flight paths* off, a flight leaves no line.
- [ ] **Size.** After about two hours of play, `/ws stats`. → The "Footsteps: … KB packed" line is
  well under 10 KB. Note the number.
- [ ] **Speed.** Footsteps on or off (Settings > Tracking) makes no FPS difference with the map closed.
  With several days of trails, set the map button to *All* and open a continent map. → No stutter.
- [ ] **Footsteps settings.** The map dropdown and the flights checkbox work. *Delete all trails*
  asks first (try it only on a test character).

## Journeys and deaths

- [ ] **Hearthstone to another continent** (with a loading screen). → An entry "Hearthstone to …";
  each continent's map shows the hearthstone icon at its end.
- [ ] **Summon or boat.** → No entry, no icon; the line just breaks.

## Journal and windows

- [ ] **Live.** With the journal open on today, loot ore or level up. → The page updates without
  flicker.
- [ ] **Item names.** → Gathered items show their names, not "item 2770" (they may fill in a moment
  later).
- [ ] **Small icon.** → The minimap button shows the bolder icon centered in its gold ring, framed
  like the round button at the top right of the world map: parchment and quill fill the ring, the
  dashed trail is visible, no blue corners stick out past the ring. The Addon Compartment and the
  addon list show the same bolder icon.

## Your Year

The journal's third tab: a look back at the year, card by card.

- [ ] **Live.** With `/ws dev` on and the tab open, level up or loot ore. → The cards update.
- [ ] **The prompt** (optional; needs the computer's clock set to December 1). Log in and close the
  "Last session" window. → A "Your 2026 is ready!" popup and a chat line; *Show* opens the tab. The
  next login doesn't ask again.

## Notes and markers

The journal's second tab holds your own notes; every `/way` line in a note is a marker on the
world map.

- [ ] **A pasted list.** New note, paste a few lines from a website, in English, e.g.
  `/way Elwynn Forest 42.1 65.9 Goldshire` and below it `/way 48.0 41.9 Northshire`. → Both are
  markers in Elwynn Forest (also on a German client). The note says "2 places on the map".
- [ ] **No zone.** In a zone, write `/way 50 50` in a new note, then click another note. → The line
  now reads "/way <your zone> 50 50" and the marker is in your zone. A line with a made-up zone
  (`/way Atlantis 1 1`) is counted as "1 /way line not found".
- [ ] **Precision.** Compare a marker from `/way` with the map's own coordinates (lower left). →
  Within about 0.1.

## Backup

- [ ] **A journal file that didn't load.** On a test character with a note and a marker (see
  [Notes and markers](#notes-and-markers)):
  1. `/ws backup`, Ctrl+C, and paste the text into a file.
  2. Close the game. Move `Wayscribe.lua` and `Wayscribe.lua.bak` out of
     `WTF/Account/<account>/<realm>/<character>/SavedVariables/` (keep them).
  3. Log in. → A chat warning that the journal didn't load, mentioning `/ws restore`. `/ws log` has
     a line about it; BugSack has **nothing**.
  4. `/ws restore`, paste the backup with Ctrl+V, *Restore...*, confirm. → The interface reloads with
     the journal and the map trails back, and the notes too: the *Notes* tab lists them, the marker
     is on the map with its icon.
  5. Log out. → A new `Wayscribe.lua` is in that `SavedVariables` folder.

## Duels

The Duels tracker (0.9, §6.10). Developer mode (`/ws dev`) also logs every duel event to the chat
(lines starting with "duel"), so if an entry is wrong, `/ws duellog` shows what the game sent.

- [ ] **A duel you start.** Right-click a player's portrait > *Duel*, and fight until one of you
  gives up. → Today's page: "Won a duel against Name Surname (Class, level N)" (or "Lost …"), in
  the PvP color; `/ws log` stays empty.
- [ ] **A duel someone else starts**, with them not targeted (Esc before the challenge). → The
  entry still has their class and level when their nameplate was on screen; otherwise just their
  name.
- [ ] **A flight.** Run out of the duel area until the duel ends. → "Fled from a duel against …"
  (and for them "… who fled", if they log it too).
- [ ] **A declined challenge.** Challenge someone who declines or lets it run out. → No entry.
- [ ] **Duel to the death**, if Forever offers it (`/makgora`). → "… a duel to the death …".
- [ ] **The Duels tab** between Maps and Your Year (`/ws duels`). → *All duels* with the
  won–lost record, by class and the latest duels; each opponent with a class icon (or a colored
  square), the page buttons step through them, and a new duel shows up while the tab is open.
  Turning the tracker off in the settings hides the tab.
- [ ] **The Your Year card** (developer mode previews the year, `/ws year`). → *Duels* after
  *Deaths*: won and lost; with more duels the most frequent opponent, the nemesis and the
  easiest and toughest class.

## After launch

The launch trackers' checks that need more than a level 1 character (§6.11): reaching a new
standing, a rare and an epic item, a Legacy Challenge, a guild, a mount, a PvP rank. Each tracker
adds its checks here when it is built.

### Gold (§6.13)

- [ ] **Every source.** Loot coins, turn in a quest with a reward, sell, buy and repair at a vendor.
  → Today's page has one gold line; its *earned* and *spent* add up to the change in your bags.
- [ ] **Mail and the auction house.** Take gold from the mailbox, post an auction (the deposit) and
  collect a sale. → Taking and collecting count as earned, the deposit as spent.
- [ ] **A trade.** Give another player some silver in a trade. → Counted once, as spent.
- [ ] **Between sessions.** Log out with developer mode on, log in on another character, mail this
  one some copper, log back in. → No gold change in today's line; `/ws trace` shows
  `Gold enable: ... -> taken`, and opening the mail counts as earned.
- [ ] **Your Year.** → A *Gold* card before *Time played*, with earned, spent, the best day and the
  most held at once.

### Reputation (§6.14)

- [ ] **A new standing.** Turn in quests until a faction reaches Friendly or Honored. → One entry
  "Reached Honored with *faction*", in *Progress*; `/ws trace` shows `changed=` and `recorded 1`.
- [ ] **Collapsed headers.** Collapse every header in the reputation window, then gain reputation.
  → The entry still comes; the trace's `factions` count doesn't drop.
- [ ] **Falling.** Kill guards of a neutral town (Booty Bay, Gadgetzan) until it is Hostile. → "Fell to
  Hostile with *faction*". Climb back to Neutral and fall again. → No second entry.
- [ ] **A new faction.** Meet a faction for the first time (it appears in the reputation window).
  → No entry.
- [ ] **A female character, German client.** → The standing reads as the reputation window names
  it.
- [ ] **Your Year.** → A *Reputation* card after *Quests*, with the factions at Exalted, Revered and
  Honored and the faction climbed most.

### Notable gear (§6.15)

- [ ] **First look.** Log in a character that wears a rare or epic item. → No entry; `/ws trace` shows
  `first look` with `worn=` the number of items worn. Equip another epic. → "Equipped an epic item:
  *name*", without the first-time badge: the one worn at the first look was the first.
- [ ] **The first rare.** On a character that wore no rare at its first look, equip a rare (blue) item. → "Equipped your first rare item: *name*", in
  *Progress*, with the first-time badge; the trace shows `first rare`. Equip another rare. → No entry
  (`later rare`).
- [ ] **Epics.** On a character that wore no epic at its first look, equip an epic item, then a second
  one. → "Equipped your first epic item: *name*",
  then "Equipped an epic item: *name*". Take one off and put it back on. → No entry (`known`).
- [ ] **Quality at equip time.** Equip an item the client hasn't seen this session (just looted).
  → The trace shows its `quality=`, not `no quality`; if it says `no quality`, the look a second
  later (or the next loading screen) writes the entry.
- [ ] **Bags.** Swap a bag. → No trace line.
- [ ] **Your Year.** → A *Notable gear* card after *Bosses*, with the epics worn and the dates of the
  first rare and the first epic.

### Legacy Challenges (§6.16)

- [ ] **First look.** Log in a character above level 1 that has completed a challenge of its own.
  → "Completed a Legacy Challenge: *name*" on the game's date, in *Progress*, without a time;
  "Played in the WoW: Forever Beta" makes none. `/ws trace` shows `back-filled <n>` and
  `new=` with `64283:account`.
- [ ] **Level 1.** Log in a brand-new character. → No entry; the trace shows `first look`.
- [ ] **Earned in play.** Complete a challenge. → The entry with its time; the trace shows
  `earned=<id>` and `recorded 1`. Check that `ACHIEVEMENT_EARNED` fires for an account-wide one
  (a class or profession rank), and whether it does when another character earned it first.
- [ ] **Another character.** Complete a challenge on an alt, then log in the first character. → No
  entry; the trace shows it `:account` (or `:other`).
- [ ] **Relog.** Log out and in. → Nothing repeats (`unchanged`).
- [ ] **Your Year.** → A *Legacy Challenges* card after *Reputation*, with the count and the latest.

### Flight paths (§6.17)

- [ ] **First flight path.** On a fresh character, talk to the first flight master. → "New flight
  path: *name*" in *Travel*; `/ws trace` shows `source="map"`, `known=1`, the `current` node's ID
  and `recorded 1`. Note whether `CHAT_MSG_SYSTEM` joins `TAXIMAP_OPENED` in the same look.
- [ ] **Older character.** Open the taxi map on a character that knows several paths. → No entry;
  the trace shows `first look`. Then learn a new one. → Its entry, `new=` with its ID.
- [ ] **Learned without a look.** Learn a path with Wayscribe off (or the tracker switched off),
  then open the map at another flight master on that continent. → Its entry.
- [ ] **Other continent.** Open the first taxi map on another continent. → No entry (`first look`),
  unless it is the only node known there.
- [ ] **Old frame.** If the old taxi frame ever opens instead of the flight map, the trace shows
  `source="frame"` and names the nodes.
- [ ] **Relog.** Log out and in, open the map again. → Nothing repeats (`unchanged`).
- [ ] **Your Year.** → The Footsteps card has "*n* flight paths learned".

### Guild (§6.18)

- [ ] **First look.** Log in a character that is in a guild. → No entry; `/ws trace` shows
  `inGuild=true`, the guild's `name` and `first look`. Note whether the login look reads
  `name missing` first, and whether a `retry` or a `PLAYER_GUILD_UPDATE` look then reads the name.
- [ ] **Leave.** Leave the guild (`/gquit`). → "Left the guild <*name*>" in *Adventure* right away;
  the trace shows `Guild PLAYER_GUILD_UPDATE: inGuild=false -> left`. If the entry waits for the
  next loading screen instead, Forever fires the event without the `player` unit (§6.18).
- [ ] **Join.** Accept a guild invite. → "Joined the guild <*name*>"; the trace shows
  `Guild PLAYER_GUILD_UPDATE: ... -> joined`.
- [ ] **Nearby players.** Stand next to a player who leaves or joins a guild. → No `Guild` trace line.
- [ ] **Rank.** Get promoted or demoted. → No entry; the trace shows `unchanged`.
- [ ] **Offline change.** Leave (or join) on this character while Wayscribe is off, then log in with
  it on. → The entries on the login day.
- [ ] **Relog.** Log out and in. → Nothing repeats (`unchanged`), also when the login look reads
  `name missing`.

### Home (§6.19)

- [ ] **First look.** Log in. → No entry; `/ws trace` shows `bind="<inn's place>"` and `first look`
  (or `unchanged` on a character Wayscribe already knows).
- [ ] **New inn.** Bind the hearthstone at another innkeeper. → "Hearthstone bound to *place*" in
  *Travel*; the trace shows `CONFIRM_BINDER` (`unchanged`), then `HEARTHSTONE_BOUND` and `moved`.
  Note whether `HEARTHSTONE_BOUND` fires at all, and whether the place matches the hearthstone's
  tooltip.
- [ ] **Same inn.** Bind again at the same innkeeper. → No entry (`unchanged`).
- [ ] **Language.** Log out, switch the client to German, log in. → No entry; the trace shows
  `taken at login` with the German place. Switch back the same way.
- [ ] **Relog.** Log out and in. → Nothing repeats (`unchanged`).

### Collections (§6.20)

- [ ] **First look.** Log in a character that owns a mount. → No entry; `/ws trace` shows
  `mounts=<n> collected=<owned>` and `first look` (or `unchanged` on a character Wayscribe knows).
- [ ] **New mount.** Learn a mount. → "New mount: *name*" in *Progress*, marked as a first only if the
  character owned no mount at its first look; the trace shows `NEW_MOUNT_ADDED` (note whether `COMPANION_LEARNED` comes too),
  `new=<mountID>` and `recorded 1`.
- [ ] **Another character.** Learn a mount on an alt, then log in the first character. → Note
  whether the mount reads as collected there: if it does, it makes an entry (§6.20, the price).
- [ ] **Pets and toys.** Learn a companion pet (Prairie Dog Whistle, Cat Carrier) or a toy, then run
  `/ws probe`. → If `collections.pets` or `collections.toys` counts it, pets and toys can join
  Collections (§6.20); if it still reads `0 of 0`, they stay out.
- [ ] **Relog.** Log out and in. → Nothing repeats (`unchanged`).
- [ ] **Your Year.** → A *Mounts* card after *Legacy Challenges*, with the count and the first mount.

### PvP rank (§6.21)

- [ ] **First look.** Log in. → No entry; `/ws trace` shows `rank=<n> season=<season>` and
  `first look` (or `unchanged` on a character Wayscribe knows).
- [ ] **New rank.** Earn honor until the rank goes up (the character frame's PvP tab). → "Reached
  PvP rank *n*: *title*" in *PvP*, the title as the PvP tab shows it; the trace shows
  `PLAYER_PVP_RANK_CHANGED` and/or `MAJOR_FACTION_RENOWN_LEVEL_CHANGED` (note which) and
  `recorded <n>`.
- [ ] **Other renown.** Complete a Legacy Challenge that raises the Legacy Track. → No PvP rank look
  for it in the trace.
- [ ] **Season.** Note what `GetCurrentArenaSeason()` reads at launch (the beta read 0) and whether
  a season change resets the rank. → The first look in the new season ends `new season`, no entry.
- [ ] **Relog.** Log out and in. → Nothing repeats (`unchanged`).
- [ ] **Your Year.** → A *PvP rank* card after *Duels*, with the highest rank and its title.

## Already verified

Done on builds 70235, 70245 and 70291 (2026-10-06 to 09); no need to repeat. Details are in
[ARCHITECTURE.md §12](architecture/12-forever-beta.md) and
[forever-probe.md](forever-probe.md).

- **Probe:** all needed APIs, events, gather and travel spell names, and the libraries are there. A
  profession reports its parent skill line (Skinning 393). `C_QuestLine` knows no Vanilla quests, so
  only the curated chains count. The world-to-map math matches the client exactly. Coverage finds
  50 zones, Forever's Zephras Isle included.
- **Professions:** learning Skinning makes an entry.
- **Names:** `/ws probe` shows `has.surnames = true`, and your character is saved with first name,
  surname and realm.
- **Journal:** looks like the spellbook (frame, parchment, headers, page buttons); the X closes it
  in combat too. The day list has month headings, "Today" and "Yesterday", a shadow on the selected
  day and a scroll bar only when needed; the page arrows turn one day, stop at the ends and play the
  page sound. The filter hides a category and its empty days, and stays after `/reload`; so do the
  window's size and position. Times follow the game's 24-hour clock setting both ways.
- **Windows:** the login recap at the first login of a day, with *Open journal*, *Don't show at
  login* and `/ws recap`; the settings page (toggles, date format, Data buttons, *Export...*); the
  minimap button (click, right-click, drag, hide); the Addon Compartment entry and the key binding.
- **Icon:** the quill-on-a-map icon shows in the addon list, on the minimap button, in the Addon
  Compartment, as the journal's portrait on both tabs and on Your Year's first card.
- **Footsteps:** the trail lies on the roads you took, on the full and the small map, and grows while
  the map is open. Fighting while moving leaves no gap; the day page shows the distance; the trail
  shows on the zone and the continent map, none on the world map. Standing still leaves no gap; a
  hearthstone draws no line; a ghost isn't followed; `/reload` keeps the trail (with a small gap). The map's icons sit above the lines, the map button
  sits top right, and *Show on the map* opens the map in front of the journal at the day's zone,
  showing only that day; after closing the map, the button says *Today* again.
- **Journeys and deaths:** a hearthstone within a zone makes an entry and an icon at both ends. A
  death outdoors makes an entry ("Died in Red Cloud Mesa, Mulgore") and a skull with a tooltip;
  releasing and being resurrected makes no second one. Yesterday's skull shows under *Last 7 days*
  with its date, and *Today* hides it.
- **Quests:** a turned-in quest shows as "Quests turned in: 1".
- **Your Year:** rollups are rebuilt silently after updating; `/ws stats` matches the saved file's
  size; the tabs look like the default UI's; all cards and icons show in the preview; the Footsteps
  card measures the share of Azeroth. The text export copies correctly, umlauts included. With
  `/ws dev` off, the tab says the year opens on December 1.
- **Backup:** a very active year (2.47 million characters) pastes back in 2.8 s and is checked in
  1.2 s. A real backup matches `/ws stats`; the Settings buttons open it; it's refused for a journal
  with entries; Reset then restore brings everything back; a journal whose file was moved away is
  restored without `/ws accept`, map trails included. Another character's backup becomes this
  character's journal after a confirmation that says whose it was.
- **Notes:** the probe on build 70291 says `worldMap.canvasClicks = true`, `worldMap.strata =
  MEDIUM` and `gameRule.worldMapTrackingPinDisabled = false` (the game's own map pin is on).
  Writing (umlaut and `|` included), Enter and Escape, saving through `/reload`, dropping blank
  notes; Alt+click with its popup in front of the map, in combat too, with no blocked message;
  hovering and clicking a marker, picking its icon, `/ws mark` (and its message in a dungeon),
  *Show on the map*, hiding the markers, deleting a note, and the backup's count of notes. A note
  with several `/way` lines shows all of them on the map.
