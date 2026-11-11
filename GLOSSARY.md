# Wayscribe

An automatic journal of one character's life in WoW Forever: it records what happens while the player
plays and shows it day by day.

## Language

### The journal

**Tracker**:
One feature that turns what happens in the game into journal entries, such as level ups, dungeon runs
or duels. The player can switch each one off.
_Avoid_: Module, logger, recorder

**Look**:
One reading of the game's current state by a tracker, such as the zone the character stands in,
which it compares with what it saw before. An event only says when to look.
_Avoid_: Check, scan, poll

**Entry**:
One line on a day page for a moment that happens only a handful of times in a character's life, such
as a level up, a new standing or a first visit.
_Avoid_: Event, log line

**Counter**:
A daily total of something that happens many times a day, such as profession skill points, weapon
skill points or gold earned. Most are shown as one line on the day page; jumps are shown only in Your
Year.
_Avoid_: Stat, tally

**First**:
An entry marked as the first time the character did that thing, such as a dungeon's first clear or
the first mount.

**First visit**:
The first time the character enters a zone or city.
_Avoid_: Discovered, explored (the game's own words for sub-areas)

**Home**:
The inn the character's hearthstone is set to.
_Avoid_: Bind point, hearth location

**Notable gear**:
The first rare item and every epic item the character equips.
_Avoid_: Loot, epic loot (what was looted is not tracked)

**Collection**:
What the character owns in Forever's Collections window: mounts, pets and toys.

**Weapon skill**:
A combat skill in the game's Weapon Skills list, Defense included, that rises by use up to five
points per character level. Separate from professions.
_Avoid_: Weapon proficiency, combat skill

**Jump**:
A press of the Jump key that lifts the character off the ground. Swimming or flying up, a press in
mid-air and the repeat hops of a held key are not jumps.
_Avoid_: Hop, bounce

**Legacy Challenge**:
Forever's own milestone, shown in place of achievements, which the game dates when it is completed.
_Avoid_: Achievement

### Footsteps

**Footsteps**:
The record of where the character went, shown as trails on the world map.
_Avoid_: Route, breadcrumbs

**Trail**:
One continuous stretch of Footsteps, on foot or in flight.
_Avoid_: Line (a trail is drawn as many lines)

### Notes

**Note**:
The player's own words in the journal: a title and a text the player can edit and delete. Not a
fact Wayscribe records.
_Avoid_: Memo, entry (entries are what Wayscribe records)

**Place**:
A spot in the world that a `/way` line of a note names, by zone and coordinates. A line whose zone
can't be found is not a place.
_Avoid_: Waypoint, location, pin

**Marker**:
An icon on the world map at a spot: a note's place, with its note's icon, or where an entry
happened, such as a death or a hearthstone journey.
_Avoid_: Pin, waypoint

**Waypoint**:
A spot that TomTom or the game's own map pin guides the player to with an arrow. A place becomes a
waypoint only when the player sends it there.
_Avoid_: Place, marker (for what Wayscribe keeps itself)

### Knowing a feature works

**In-game check**:
A test that needs the real Forever client: does the game fire the event, does it look right, is it
fast enough.
_Avoid_: Playtest, playtesting, manual test

**Probed**:
Said of a feature whose game APIs and events are confirmed to exist on the Forever client, by
`/ws probe` or by Forever's own UI source. Says nothing about whether they fire in play.
_Avoid_: Tested, checked

**Unit-tested**:
Said of a feature whose logic is covered by the specs against the fake game API, including secret
and missing values.

**Launch trace**:
In developer mode, one line for each look a launch tracker took: when, the event that asked, the
values it read and how the look ended. Shown by `/ws trace`; the evidence for a wrong entry.
_Avoid_: Debug log, duel log (the older trace of raw duel events)

**Verified**:
Said of a feature whose in-game checks have passed.
_Avoid_: Tested, confirmed (for anything short of a passed in-game check)
