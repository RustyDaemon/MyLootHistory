# My Loot History

[![https://www.curseforge.com/wow/addons/my-loot-history](https://img.shields.io/badge/download-CurseForge-orange)](https://www.curseforge.com/wow/addons/my-loot-history) 

My Loot History is a World of Warcraft addon that tracks everything you looted. Even copper coins.

➡️ Get the addon: [CurseForge](https://www.curseforge.com/wow/addons/my-loot-history)

## What can be tracked

- every item you loot: weapons, junk, herbs and everything else
- every copper coin you loot
- every currency you pick up: Valorstones, Crests, Flightstones and the rest

> It does not track quest rewards or similar.

## What I can do else

- see a big report!
- with a full list of everything you looted: items, currencies and even coins
- with an item icon, name, quantity, value and the zone it mostly came from
- with a date when you looted a particular item (or date range)
- open a chat and link an item you want
- with a little gold summary
- export everything you are looking at to CSV
- oh! And you can filter this report

## The report

The window is drawn by the addon rather than assembled out of the default widgets, so it looks like one designed thing:

- **four stat cards across the top** - how long the session has been running, items per hour, gold per hour and what the rows below add up to
- **an activity graph** - one bar an hour for the last day, so you can see *when* you were earning and not only how much. Hover a bar for that hour's items and value
- **a value bar behind every row** - how much of the total that one item is worth, which is the fastest way to see the three things actually paying for the session
- **quality colours everywhere** - the icon border, the name and the marker down the left of each row
- **a footer** that says what the view adds up to, and which zone most of it came from

It remembers where you left it and how big it was, closes on Escape, and only ever builds as many rows as fit on screen - so a character with thousands of items opens as fast as a fresh one.

## How much gold per hour am I making?

The first three cards are live and keep counting while the window is open: how long you have been at it, how many items per hour that is, and **how much gold per hour** - the value of the loot plus the coins you picked up.

Click the session card to start a new session from that moment, which is what you want when you move to a new farming spot. The same numbers are on the minimap tooltip and behind `/mlh session`.

By default the value of your loot is the vendor price. If you have [Auctionator](https://www.curseforge.com/wow/addons/auctionator) installed, you can switch the report over to auction house prices in the settings - it is optional, and the vendor price is used for anything Auctionator has no price for.

## Was this worth picking up before?

Hover any item in the game - in your bags, at a vendor, in the auction house, or a link in chat - and the tooltip tells you how many you have looted before and when the last one was. No need to open the report at all. It can be switched off in the settings.

## What? I can filter all those?

Yes! And history changes according to you filters. It will show you how much gold you looted and how many items you gathered depending on filters you selected. For example, if you looted 3xHochenblume yesterday and 1xHochenblume today, you will see the exact history.

- by date or date range:
  - Current Session
  - Today
  - Yesterday
  - Wednesday-to-Wednesday
  - This month
  - All the time
- by item name: type in the search box. It matches currencies too, and hides the coin line, which has no name to match
- by zone: the dropdown lists every zone you have ever looted in
- by item quality
  - Poor
  - Common
  - Uncommon
  - Rare
  - Epic
  - Legendary
- by default, it filters as a 'item quality and upper'. But you can filter on 'Exact' item quality - there is a checkbox for that
- gold summary also updates according to date range you change

And you can sort it: click a column header to sort by quality, name, quantity, value, zone or the last looted date, and click it again to reverse the order. The search text, the sort column and its direction are remembered per character.

## What can be configured

- Show/hide minimap button
- Make the report window resizable
- Show looted date in the report
- Show the zone column in the report
- Show the session cards and the activity graph at the top of the report
- Show currencies in the report
- Price source for the value column: vendor price, or auction house prices through Auctionator
- Ignore items with 0 (zero) sell price
- Ignore quest items (note, this is a default state and it can't be changed)
- Show item ID in the report
- Show item tooltip on mouse hover in the report
- Show additional information in the tooltip (a 'Total gathered' summary and the zones it came from)
- Add the loot summary line to item tooltips everywhere in the game
- Track currencies
- Change icon size

## Some helpful additions

Besides, some additional features are available:

- print debug information
- reset everything (this will erase all looted information for items, currencies and gold)
- little FAQ
- small informative statistics (how many items were looted, how many total quantity is and in how many zones you looted them)

## Slash commands

- `/mlh` opens the report
- `/mlh config` opens the configuration window
- `/mlh session` prints the session summary: elapsed time, items per hour and gold per hour
- `/mlh session reset` starts a new session from now

## Limitations

- The addon can't track items that were upgraded during the looting at the moment (for example, you got 302 il item and it was instantly upgraded to 323 il)

## License

MyLootHistory is licensed under the GNU General Public License version 3. See License file for details.
