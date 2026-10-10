# 8. Your Year (yearly recap)

Part of the [Wayscribe architecture](../ARCHITECTURE.md); other sections are listed there.

The yearly recap, shown as the journal's third tab: "Your Year" / "Dein Jahr", each year
"Your 2026" / "Dein 2026". In the code `YourYear` (UI) and `YearCards` (data).

- **Cards from rollups.** `YearCards:Build(year)` hands `Store:GetYearSummary(year)` to each card:
  the 12 month rollups merged (§4.2), play time and sessions, and `byMonth`. Cards never read day
  records, so a year renders the same with its days archived. A unit test proves it by deleting
  every day of a played year and comparing the cards. Two inputs besides rollups: the months'
  sessions (most active day, longest session) and Footsteps coverage (§6.8), measured in the
  background.
- **Registry.** `ns.YearCards:Register{ id, order, build = function(summary) -> card or nil }`, the
  same pattern as record types: each tracker registers its card next to its facts. A card is
  `{ title, icon, big, caption, lines }`; `nil` leaves it out (nothing happened), a failing one only
  loses itself. Helpers format numbers ("1,234" / "1.234"), percentages and plurals (every `_ONE`
  pattern has a German one; a test checks).
- **The cards** (order): *The year at a glance* (entries, how many were firsts, days and months with
  entries) · *Levels* (+N, from → to, the day the highest was reached) · *Dungeons and raids* (runs
  completed, how many different, most often, its first clear, visits without the final boss) ·
  *Bosses* (defeated, how many for the first time) · *Companions* (how many, top 3 with runs
  together) · *Deaths* (how many, the most dangerous zone) · *Gathering* (nodes, items, top item) ·
  *Professions* (skill points, learned, highest ranks, gains per profession) · *Quests* (turned in,
  curated chains by name) · *Footsteps* (distance over land, flight paths, journeys by hearthstone,
  % of Azeroth walked and the most walked zone) · *Time played* (total, sessions, most active
  month and day, longest session).
- **Shown in the journal**, as its third tab (§7.1): years on the left, the card on the right, the
  page buttons turn cards like a slideshow ("Page 3/11").
- **Opens on December 1.** Past years open any time; the current year from December 1. Developer
  mode (`/ws dev`) previews it early, marked "preview".
- **One prompt per year.** At the first login after a year opens (December 1, or the next login in
  the new year if December went by), if the character has entries in that year: a chat line and a
  popup ("Your 2026 is ready!", *Show* / *Later*). It waits for the login recap to close.
  `state.yourYearPrompted` keeps the year, per character.
