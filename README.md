<p align="center">
  <img src="media/grey-gold-logo.png" width="128" alt="Grey Gold logo">
</p>

# Grey Gold (WoW Forever)

Sells every junk item (grey quality, the items that show the gold coin icon) as soon as you open any vendor. It also keeps a history of what you sold, so you can browse your junk income by day, week, item and zone.

<p align="center">
  <img src="media/grey-gold-1-overview.png" width="600" alt="Grey Gold stats window, Overview tab: gold earned today, this week, this month and all time, a gold-per-day chart, and records">
</p>

## Installation

Pick **one** of the two ways below. Option A is the easiest.

### Option A: with the CurseForge app (easiest)

1. Install the free [CurseForge app](https://www.curseforge.com/download/app) and open it.
2. Choose **World of Warcraft**, then make sure **Forever** is selected as the game version (not Retail or Classic).
3. Search for **Grey Gold** and click **Install**.
4. Start (or fully restart) WoW. Done! The app also keeps the addon updated for you.

### Option B: install it yourself

1. **Download the zip.** Get the latest file from the addon's CurseForge page (**Files** tab).

2. **Find your AddOns folder.** Open the Battle.net app, select **World of Warcraft**, choose **WoW Forever** as the version, click the **gear icon** next to the Play button, and choose **Show in Explorer** (Mac: **Show in Finder**). In the folder that opens, go to:

   ```
   _forever_ > Interface > AddOns
   ```

   If `Interface` or `AddOns` doesn't exist yet, create it yourself (right-click > New > Folder). The names must be spelled exactly like this.

   > The usual location on Windows is `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`, and on Mac it's `/Applications/World of Warcraft/_forever_/Interface/AddOns`.

3. **Copy the addon in.** Open the zip (double-click it). Inside is a folder called `GreyGold`. Drag that **folder** into your `AddOns` folder.

   When you're done, it must look exactly like this:

   ```
   AddOns
   └── GreyGold
       ├── GreyGold.toc
       ├── GreyGold.lua
       └── ... (the other files)
   ```

   **Common mistakes:**
   - A folder inside a folder, like `AddOns\GreyGold\GreyGold\...` or `AddOns\GreyGold-2.0.0\GreyGold\...`. Move the inner `GreyGold` folder up so it sits directly in `AddOns`.
   - The wrong folder name. Downloads from GitHub are called something like `...-main`. Rename the folder to exactly `GreyGold`, or WoW won't load it.
   - The files dropped loose into `AddOns` without the `GreyGold` folder around them.

4. **Restart WoW completely.** Close the game and start it again; typing `/reload` is not enough for a newly installed addon.

5. **Check that it's turned on.** On the character select screen, click **AddOns** (bottom left) and make sure **Grey Gold** is ticked. If it says *Out of date*, tick **Load out of date AddOns** at the top of that list.

## Getting started

You don't need to set anything up. Just play:

1. **Open any vendor.** Grey Gold sells all your grey junk right away, and a chat message tells you how much you earned. (Want to keep your junk this one time? Hold **Shift** while you click the vendor.)
2. **See your stats.** Click the **gold coin button** on the edge of your minimap, or type `/greygold` in chat.
3. **Protect an item you want to keep.** Open the **Settings** tab and drag the item onto the **Never sell** slot. It will never be sold.
4. **Turn auto-selling off or on** any time: **Shift-click** the minimap button, or type `/greygold toggle`.

### Something not working?

| Problem | What to do |
| --- | --- |
| Grey Gold isn't in the AddOns list | Check the folder layout in step 3 above, then fully restart WoW. |
| It's in the list but marked *Out of date* | Tick **Load out of date AddOns** on the AddOns screen. |
| Nothing gets sold | Make sure auto-sell is **ON** (hover over the minimap button), that you weren't holding Shift, and that the item isn't on your Never sell list. Only **grey** items are sold. |
| I can't see the minimap button | Type `/greygold minimap` to show it again. |

### Updating and removing

- **Update:** with the CurseForge app, click **Update**. Manually, delete the old `GreyGold` folder and copy in the new one. Your history is saved separately, so it stays.
- **Remove:** delete the `GreyGold` folder from `AddOns`. To also delete your saved history, remove `GreyGold.lua` from `_forever_\WTF\Account\<your account>\SavedVariables\`.

## FAQ

**I sold something by mistake. Can I get it back?**
Yes, if you act before logging out. Open the vendor's **Buyback** tab: the game keeps your last 12 sold items there until you log out. Then add the item to your **Never sell** list so it doesn't happen again.

**Will it sell anything that isn't grey?**
No. Only grey (Poor quality) items that have a sell value are sold: the ones that show the gold coin icon at a vendor. Your gear, consumables and anything better than grey are never touched.

**What about grey items I want to keep, like transmog pieces?**
Put them on the **Never sell** list: drag the item onto the slot in the **Settings** tab, right-click it in the **Items** tab, or type `/greygold keep` followed by a space and shift-click the item into chat.

**Is it safe to use?**
Grey Gold only sells while a vendor window is open, using the same action as right-clicking an item at a vendor. It stops the moment you close the vendor.

**Does it share my data with anyone?**
No. Your history and settings are saved only on your own PC, and the addon never sends anything anywhere.

**Are the settings per character?**
No. Your settings and Never sell list are shared by all characters on your account. Your history is recorded per character, and the **Showing** dropdown lets you view one character or all of them together.

**Does it work with bag addons like Bagnon?**
Yes. Grey Gold reads your bags directly from the game, so it works the same with or without a bag addon.

**Does it work on Retail or Classic?**
Grey Gold is made for **WoW Forever**. Other game versions aren't supported.

**I hid the minimap button. How do I open the window now?**
Type `/greygold`, or use the addon list button next to the minimap (the addon compartment). `/greygold minimap` brings the button back.

## Minimap button

Drag the button to move it around the minimap edge. It works with round and square minimaps. The same actions are also available from the addon compartment.

| Action      | What it does             |
| ----------- | ------------------------ |
| Left-click  | Open the stats window    |
| Right-click | Open the Settings tab    |
| Shift-click | Turn auto-sell on or off |
| Hover       | See today, this week and all-time gold, plus the junk in your bags right now |

## Stats window (`/greygold`)

The **Showing** dropdown switches between **All characters** and any single character.

- **Overview**: tiles for today, this week, this month and all time; a gold-per-day chart (14 or 30 days; click a bar to open that day); and records:
  - best day and best week;
  - biggest vendor haul and priciest single sale;
  - current and longest selling streak;
  - bag slots freed, active days, average per active day, and the date tracking started.
- **History**: daily or weekly view with a chart and a list of periods. Selecting a period shows each item sold that day or week (quantity, gold, gold per item) and which zones you sold it in.
- **Items**: an all-time leaderboard you can sort and search. Shift-click links an item in chat; right-click protects it from selling.
- **Zones**: gold, visits, gold per visit and share for each zone you sold in.
- **Settings**: the options, the never-sell list (drag an item onto the slot), the slash commands, and a reset button. Reset clears the history for whichever scope the dropdown is showing.

When your lifetime junk gold passes 10g, 25g, 50g, 100g, 250g and so on, you get a milestone message and a coin sound.

<details>
<summary><b>Screenshots of every tab</b> (click to open)</summary>

**History**: every item sold on a chosen day or week, and where you sold it

<img src="media/grey-gold-2-history.png" width="600" alt="History tab: daily chart with the selected day highlighted, and the items sold that day">

**Items**: all-time leaderboard of your junk

<img src="media/grey-gold-3-items.png" width="600" alt="Items tab: sortable list of every junk item sold, with totals and price each">

**Zones**: where you sold your junk

<img src="media/grey-gold-4-zones.png" width="600" alt="Zones tab: gold, vendor visits and share for each zone you sold in">

**Settings**: options, never-sell list and commands

<img src="media/grey-gold-5-settings.png" width="600" alt="Settings tab: options, never-sell slot and the list of slash commands">

</details>

## Commands

| Command                 | What it does                                            |
| ----------------------- | ------------------------------------------------------- |
| `/greygold`             | Open or close the stats window                          |
| `/greygold toggle`      | Turn auto-sell on or off                                |
| `/greygold sell`        | Sell junk now (a vendor must be open)                   |
| `/greygold keep <item>` | Protect or unprotect an item (shift-click it into chat) |
| `/greygold quiet`       | Turn the chat summary on or off                         |
| `/greygold minimap`     | Show or hide the minimap button                         |
| `/greygold help`        | List the commands in chat                               |

`/junk` works as a shortcut for `/greygold`, so `/junk sell` and `/greygold sell` do the same thing.

Hold **Shift** while opening a vendor to skip auto-selling that one time.

## How it works

- An item counts as junk when it has Poor quality, has a sell value, and is not on your never-sell list. This is the same rule the game uses for the coin icon.
- Sales go out in batches of 12 every 0.2s, and failed sales are retried. Selling stops the moment the vendor window closes, because outside a vendor the game would use or equip the item instead.
- Only sales the server confirms (the item has left your bags) are recorded.
- History is saved account-wide in `GreyGoldDB`, one entry per item per day per character. No libraries are used, and the window is only built the first time you open it.

## Feedback and bug reports

Found a bug or have an idea? [Open an issue on GitHub](../../issues) or leave a comment on the CurseForge page.

To help me fix a bug quickly, please include:
- **Your Grey Gold version.** You can see it in the **Settings** tab, under About.
- **What you did and what happened.** For example: "I opened a vendor and nothing was sold."
- **Any error message.** If you don't see errors, type `/console scriptErrors 1` in chat to turn them on, then try again.

## Changelog

### 2.0.0: first release
- Auto-sells every grey item the moment you open a vendor, in quick batches, and stops when the vendor closes.
- Never sell list, Shift to skip selling once, and an optional chat summary.
- Stats window with Overview, History, Items and Zones tabs, plus records, streaks and milestones.
- Minimap button and addon compartment entry.

## License

MIT. See [LICENSE](LICENSE).

## Disclaimer

This addon is provided "as is", without warranty of any kind, express or implied. You use it at your own risk. To the fullest extent permitted by applicable law, the author accepts no responsibility or liability for any loss, damage or other consequence arising from its use, including items sold by mistake, lost gold or data, or any action taken against your game account.
