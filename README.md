# Wayscribe

**An automatic journal for your WoW Forever character.**

Wayscribe writes down your adventures while you play. There's nothing to type and nothing to set
up: level ups, dungeon runs with your group, first boss kills, professions, gathering, quest chains,
deaths and hearthstone journeys are collected day by day, in a book that looks right at home next to
your spellbook. Your routes show up as footsteps on the world map, and at the end of the year,
**Your Year** looks back on all of it, card by card. And when you want to write something down
yourself, the book has pages for your own notes, and the map has room for your own markers.

```text
Saturday, October 3, 2026
Today · played 2 h 10 min

 2:05 PM  Defeated Taragaman the Hungerer for the first time
 2:31 PM  First clear of Ragefire Chasm with Xy, Ab and Cd (42 min)
 3:10 PM  Mining reached 75
 4:02 PM  Completed the quest chain: The Defias Brotherhood
          Ore deposits mined: 12
          Gathered 23× Copper Ore, 4× Rough Stone
          Skill gains: Mining +23
          Quests turned in: 7
          Traveled 4.1 miles · Flight paths: 2.3 miles
```

## Features

### A journal that writes itself

- One page per day: what happened, when, and how long you played.
- The day list on the left, grouped by month; the selected day on the right. Turn the pages like a
  book.
- Firsts are marked: your first kill of a boss, your first clear of a dungeon.
- Filters for Progress, Adventure, Quests, Gathering and Travel.
- Full dates in English or German, times in your game's 12- or 24-hour clock.

### What it records

- **Levels:** every level you reach.
- **Dungeons and raids:** each run with your group, how long it took, and your first clears. A run
  you leave early becomes a visit with the bosses you defeated. A `/reload`, a disconnect or a corpse
  run doesn't split it.
- **Bosses:** every boss you defeat, in dungeons, raids and the open world.
- **Professions:** the professions you learn, skill points per day, and the ranks 75, 150, 225 and
  300.
- **Gathering:** ore, herbs and skins per day. Only what actually ends up in your bags counts.
- **Quests:** quests turned in per day, and well-known quest chains: attunements, dungeon keys, class
  quests and storylines like The Defias Brotherhood or the redemption of Tirion Fordring. Chains
  added in a later version are filled in for the day you finished them.
- **Deaths:** where and when.
- **Journeys:** hearthstone, Astral Recall, mage teleports and transporters, from where to where.
- **Distance:** how far you walked, rode and flew each day.

Every tracker can be turned off in the settings.

### Footsteps: your routes on the world map

- Where you walked and rode appears as a dark red trail on the zone and continent maps; flights
  are thinner blue lines. Older days are drawn lighter.
- A button in the top right corner of the map picks what it shows: today, the last 7 days, all of
  it, or nothing.
- A skull marks where you died, and a spell icon where a hearthstone or teleport took off and
  where it landed. Hover over them for the time.
- Each journal day with trails has a *Show on the map* button that opens the map at that day's
  route.
- Light on your game: recording checks your position once a second, only outdoors, and two hours
  of play take about 3 KB.

### Your Year

The journal's third tab looks back on your year with a card for each part of it: the year at a
glance, levels, dungeons and raids, bosses, your most frequent companions, deaths and the most
dangerous place, gathering, professions, quests and quest chains, footsteps (with how much of
Azeroth you walked), and time played.

A year opens on December 1, with a "Your 2026 is ready!" message at your first login. Past years
open any time.

### Your notes and markers

- The journal's second tab is a notebook: *New note*, a title, and as much text as you like. Every
  word is saved as you type.
- **Mark places on the map:** Alt+click the world map, name the spot, and a marker appears there,
  on the zone and the continent map. Or type `/ws mark` to mark where you stand (`/ws mark Rare
  spawn` names it).
- A marker is a note with a place: hover over it to read it, click it to open it in the journal and
  write more. Pick one of the eight raid icons for it.
- *Show on the map* opens the map at a note's place. The map button's menu (or the settings) hides
  your markers when you want a clean map.
- Your notes belong to the character, and the backup and the text export include them.

### Login recap

At your first login of the day, a small window shows what happened in your last session. You can
turn it off right there, and `/ws recap` brings it back.

### Export and backup

- **Export** the journal as text to read outside the game: this month, this year or everything.
- **Back up** a character's journal and footsteps as one text to save in a file. `/ws restore`
  puts it back, on a new computer or when the saved file was lost. A backup only goes into an empty
  journal or one that didn't load; it never overwrites entries you have.

## Getting started

Install it, log in and play. Wayscribe records from the moment it's installed. To open the journal:

- type `/ws` (or `/wayscribe`),
- click the minimap button (right-click opens the settings),
- use the Addon Compartment (the addons button at the minimap), or
- set a key under Options > Keybindings > AddOns > Wayscribe (unbound by default).

The settings are under Options > AddOns > Wayscribe, or `/ws settings`.

## Commands

| Command | What it does |
|---|---|
| `/ws` | Open or close the journal |
| `/ws settings` | Open the settings |
| `/ws year` | Open Your Year (`/ws year 2026` for a given year) |
| `/ws notes` | Open your notes |
| `/ws mark` | Mark where you stand on the map (`/ws mark Rare spawn` gives it a title) |
| `/ws recap` | Show the last session again |
| `/ws export` | The journal as text to copy (`month`, `year` or `all`, the default) |
| `/ws backup` | A backup of this character's journal and footsteps, to copy and keep |
| `/ws restore` | Paste a backup back into an empty journal, or one that didn't load |
| `/ws stats` | How much is in this character's journal, and how big its saved file is |
| `/ws log` | The last errors, if there were any |
| `/ws rebuild` | Recompute firsts and summaries from the journal, and add quest chains finished earlier |
| `/ws accept` | Answer a read-only warning: take over a journal copied from another character, or start fresh |
| `/ws help` | List the commands |

## Your data

- **It stays on your computer.** Everything is in your SavedVariables. Nothing is sent anywhere,
  and other players can't see it.
- **One journal per character.** Each character has its own file.
- **Small.** Wayscribe saves short facts, not finished sentences, and packs the trails. Even a year
  of daily play stays a few megabytes.
- **Safe.** If a saved file doesn't load, or was written by a newer version, Wayscribe switches to
  read-only instead of starting over, and tells you what happened and what to do. Nothing is
  overwritten until you decide.
- **Make a backup now and then** (`/ws backup`). It's one text you can keep anywhere, and it brings
  back the journal, your notes and the footsteps if the game's files are ever lost.

## Good to know

- Wayscribe is made for **WoW Forever**. Other versions of the game aren't supported.
- It speaks **English and German**.
- Deaths say where and when, but not who: on Forever, addons can't read the combat log.
- What happened before you installed Wayscribe isn't in the journal. A quest chain counts when you
  turn in its last quest with Wayscribe installed.

## Feedback

Found a bug or have an idea? Open an issue on
[GitHub](https://github.com/ollidiemaus/wayscribe/issues), and include what `/ws log` says if
there was an error.

Want to look under the hood? The developer notes are in
[docs/DEVELOPMENT.md](https://github.com/ollidiemaus/wayscribe/blob/main/docs/DEVELOPMENT.md).
