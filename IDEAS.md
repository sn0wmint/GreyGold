# Ideas for upcoming features

Not planned for a release yet. Recorded so they don't get lost. This file is
left out of release zips (see `.gitattributes`).

## More achievement categories

The Achievements window (2.2.0) has one category, Gold. New ones are added by
registering entries in `Achievements.lua` (`ns.RegisterAchievement`), each with a
`progress` function; storage and the window need no changes. Ideas, all based on
data the sales log already records (from 2.1.0 on):

- **Zones:** sell junk farmed in a zone (e.g. 1g from Elwynn Forest).
- **Regions:** junk farmed in 10 different zones, or in every zone of a continent.
  Needs the continent recorded at loot time (the game can report it).
- **Items:** sell 100 of one grey item, or 50 different grey items.
- **Mobs:** junk from 25 kinds of mob, or 100 junk items from one mob type.
- **Sources:** first fishing junk, junk from 10 chests, junk from a dungeon.
- **Habits:** a 7-day selling streak, a 1g vendor visit, a full bag sold at once.

Names use the game's own zones, mobs and items (see the lore guideline below).

## Zone collection journal

Each zone gets a collection page listing the grey items that actually drop
there. Every item you find fills its slot on that zone's page.

- Builds on the loot origin added in 2.1.0: each sale already knows the zone
  the item was looted in.
- Open questions: where the list of a zone's grey items comes from (a bundled
  list, or only items you have found yourself), and how to show slots you
  haven't found yet.

## Permanent discovery progress

Finding an item records it in the journal for good. Selling it later does not
remove the discovery.

- Needs its own saved record of discoveries (item, zone, first found), kept
  apart from the sales history, so resetting history doesn't wipe it.

## Lore-friendly presentation

Themes and descriptions based on established Warcraft items, creatures,
factions and places. For example, a zone page could open with a short line
about that zone and the creatures whose junk fills it.

- Keep to the game's own lore and names. No made-up lore presented as
  official.
