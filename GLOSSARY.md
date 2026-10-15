# Wayscribe

An automatic journal of one character's life in WoW Forever: it records what happens while the player
plays and shows it day by day.

## Language

### The journal

**Tracker**:
One feature that turns what happens in the game into journal entries, such as level ups, dungeon runs
or duels. The player can switch each one off.
_Avoid_: Module, logger, recorder

**Entry**:
One line on a day page for a moment that happens only a handful of times in a character's life, such
as a level up, a new standing or a first visit.
_Avoid_: Event, log line

**Counter**:
A daily total of something that happens many times a day, shown as one line on the day page, such as
skill points gained or gold earned.
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

**Legacy Challenge**:
Forever's own milestone, shown in place of achievements, which the game dates when it is completed.
_Avoid_: Achievement

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

**Verified**:
Said of a feature whose in-game checks have passed.
_Avoid_: Tested, confirmed (for anything short of a passed in-game check)
