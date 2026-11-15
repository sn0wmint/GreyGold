# Changelog

Every change to Grey Gold, newest first. Corrections are listed too, small ones included, so you always know exactly what changed and why.

None of the fixes below involve Grey Gold selling something it shouldn't, or you getting less gold than you should. What gets sold follows the game's own rule: grey (Poor) quality with a sell value, the items that show the gold coin icon. The vendor pays you exactly what it always would. The fixes are about the statistics Grey Gold keeps on top of that.

## 2.2.1 (2026-11-15)

**Accuracy update.** Grey Gold's bookkeeping went through a new round of stress tests: items moved in the middle of a sale, prices the game hasn't loaded yet, and several mobs looted at once. The rules are now stricter in each of these cases, and each one is covered by an automated test.

### Fixed

- **Every sale is double-checked against your bags.** A sale is recorded only when the item has left its slot *and* your bags really hold fewer of it. Before, a junk item that moved to another slot during the second or so that auto-sell runs (dragged by you, or sorted by a bag addon) could appear in your stats as sold when it wasn't, or be counted twice when it was. The gold you received was always correct; only the totals were affected.
- **Closing a vendor and opening one again straight away** can no longer make a sale count twice or be filed under the second visit. The run that was cut short is counted first.
- **No more zero-value sales.** If the game hasn't loaded an item's price yet, Grey Gold now waits for it instead of selling the item and recording it as worth nothing. If the price never arrives, the item stays in your bags, one chat line tells you, and `/greygold sell` tries again.
- **Each mob gets credit for its own loot.** When the same grey item comes from several corpses at once (area loot, or very fast looting), each mob is now credited with its own copies. Before, they could all be credited to one of them. Zone totals were not affected. Mob totals recorded earlier stay as they are: there is no reliable way to tell afterwards which copies came from which mob, and Grey Gold doesn't guess.

### Improved

- **Dropped by** now says exactly which months it is showing, for example "showing October 2026 to November 2026". Mob totals are stored per month, which is what lets them be kept forever without growing your save file. So a "This week" that crosses into a new month shows both months, and the footer now says so.
- **Clearer README, FAQ and CurseForge page:**
  - Grey Gold has always sold by the coin-icon rule, so grey armour and weapons in your bags are sold like any other grey item. The FAQ now says this plainly and points to the **Never sell** list and the **Shift** key for pieces you want to keep. Gear you are wearing is never touched.
  - The buyback answer now explains the game's own limit. The vendor's Buyback tab holds only your last 12 sold stacks and is cleared when you log out, so on a visit that sells more than 12 stacks, the earliest ones can no longer be bought back.
  - The mob and zone views are described as exactly what they are: totals of the junk you sold, by where it came from. They don't measure gold per hour or the value of the rest of your loot.
  - The description in the AddOns list now says "junk gold", since junk is what Grey Gold tracks.
  - A direct link to Grey Gold's CurseForge page.
- The test suite grew from 234 to 271 checks and runs automatically on GitHub for every change.

## 2.2.0 (2026-11-15)

### New

- **Achievements:** fifteen milestones from your first 10 silver up to 200 gold, then one every 100 gold. Each one has its own title: you start at **Pocket Change**, pass **Trash Baron** at 45 gold, and end up a **Grey Gold Magnate**. The Achievements window shows when you reached each one, which character got there, and how far you are from the next.
- **History by month and year**, next to daily and weekly, plus a "best month" record.
- **Dropped by:** a new view on the Zones tab that ranks mobs, chests and fishing catches by the junk gold they gave you. These totals are kept per month, forever.

### Improved

- The sales log keeps 5,000 sales per character (was 2,000).
- A buyback now also lowers "bag slots freed".
- The window redraws at most once per frame during a burst of sales.
- The minimap tooltip reuses the junk count Grey Gold already keeps, instead of scanning your bags again.
- The "Milestone celebrations" option is now called "Achievement announcements".
- README rewritten, with new screenshots of every tab.

## 2.1.0 (2026-11-14)

### New

- **Log tab:** every sale with its date and time, and the mob, chest, fishing catch, container, mail, trade or bank it came from. Hand sales, buybacks and re-sales are marked.
- **Where your junk came from:** Grey Gold notes the origin of each junk item as it arrives in your bags. When you sell, the oldest copies are matched first, so a stack from three different mobs becomes three Log rows.
- **Farmed in:** a new Zones view showing where you looted your junk, next to **Sold in**. Only junk you looted yourself gets zone credit.
- **Date filters** on the Items and Zones tabs: Today, This week, last 30 days and All time.
- **Hand sales count:** grey items you sell yourself are recorded once the vendor pays for them. Destroyed or equipped greys never count, and nothing better than grey is ever recorded.
- **Buybacks** take the sale back out of your totals.
- Next-milestone progress bar on the Overview and in the minimap tooltip.
- **Junk in your bags right now:** a data feed for Bagnon's data bar (and similar addons), and a small label next to the default backpack.
- When your bags are full, a chat hint names your cheapest junk stack. Grey Gold never deletes anything itself.
- The window title shows the version number.

### Improved

- Buying an item back while auto-sell is still running stops the run, so that item isn't sold again straight away. `/greygold sell` sells the rest.
- Buying back an item whose sale hasn't been recorded yet cancels that sale, not an older one.
- Stricter hand-sale matching: if a grey and a non-grey item of the same price leave your bags at the same moment, the payment goes to the non-grey item. An equipped grey is never counted as sold.
- Only an item that was on your cursor a moment ago can count as destroyed.
- Spells cast at your current target no longer get mistaken for the name of a chest you opened.
- Re-selling an item after buying it back counts as the same vendor visit.
- The Settings tab moved from 5th to 6th place. Shorter Settings labels and clearer Zones wording.

## 2.0.0 (2026-11-14): first release

- Sells every grey item with a sell value the moment you open any vendor, in batches of 12 every 0.2 seconds, and stops the moment the vendor window closes, so nothing is ever used or equipped by accident.
- **Never sell** list, hold **Shift** to skip selling once, and an optional chat summary.
- Stats window with Overview, History, Items and Zones (where you sold) tabs, plus records, streaks and milestones.
- Minimap button and addon compartment entry.
- MIT license.
