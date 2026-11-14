# Grey Gold (WoW Forever)

Sells every junk item (grey quality, the items that show the gold coin icon) as soon as you open any vendor. It also keeps a history of what you sold, so you can browse your junk income by day, week, item and zone.

## Install

Put this folder in `World of Warcraft\_forever_\Interface\AddOns\` as `GreyGold`. The folder name must match the `.toc` file. After adding the addon or changing its `.toc`, fully restart the game; for edits to the Lua files only, `/reload` is enough.

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

## License

MIT. See [LICENSE](LICENSE).

## Disclaimer

This addon is provided "as is", without warranty of any kind, express or implied. You use it at your own risk. To the fullest extent permitted by applicable law, the author accepts no responsibility or liability for any loss, damage or other consequence arising from its use, including items sold by mistake, lost gold or data, or any action taken against your game account.
