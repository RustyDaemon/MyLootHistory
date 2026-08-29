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

By default the value of your loot is the vendor price. If you have [Auctionator](https://www.curseforge.com/wow/addons/auctionator) installed, switching the price source in the settings adds an **AH column** beside it - the vendor price keeps its own column, so you can see both at once, and an item the auction house has no price for shows a dash rather than pretending to be worth nothing.

## What did last night's farm make?

Sessions are kept, not just the one you are in. Start a new one and the old one is filed; log in tomorrow and yesterday's is still there. Pick one out of the session picker beside the date range and the whole report - rows, totals and the cards at the top - describes that session: when it ran, how long for, and what it was worth.

A session stores only the window it covered, so its numbers are always worked out from the loot itself and can never drift out of step with your history.

## All my characters at once

Switch **Show loot from** to *All characters* and the report covers the whole account. An item three of your characters have looted is one row, not three: the quantities add up, a Character column says who found most of it, and the tooltip lists all of them.

Nothing is moved between characters - each one's history stays exactly where it has always been, and this is only a way of reading all of them together. Switch back and the view narrows again. A character who last played under a very old version has their records brought up to the current shape the first time they are read, keeping the quantity, the date and the zone.

## Where did this drop from?

Loot is recorded with what it came from: the creature it dropped off, the container it was in, or that you crafted or gathered it. Switch on the **From** column to see the main source per row, and the item tooltip lists every one of them with a count - which is how you find out that the thing paying for your farm comes off one particular mob.

It is recorded from the moment you install this version; loot picked up before then has no source to show. Recording it can be switched off in the settings, and anything the client will not name honestly is shown as what kind of thing it was rather than guessed at.

Names are learned from what you target or hover, and kept for the whole account - so the first time you target a mob, every drop it has ever given you is named, including the ones recorded before you knew what it was called.

## Was this worth picking up before?

Hover any item in the game - in your bags, at a vendor, in the auction house, or a link in chat - and the tooltip tells you how many you have looted before and when the last one was. No need to open the report at all. It can be switched off in the settings.

## What? I can filter all those?

Yes! And history changes according to you filters. It will show you how much gold you looted and how many items you gathered depending on filters you selected. For example, if you looted 3xHochenblume yesterday and 1xHochenblume today, you will see the exact history.

- by character: this one, or every character on the account
- by date or date range:
  - Current session, or any session you have finished
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

And you can sort it: click a column header to sort by quality, name, quantity, value, auction value, character, source, zone or the last looted date, and click it again to reverse the order. The search text, the sort column and its direction are remembered per character.

## What can be configured

- Show/hide minimap button
- Make the report window resizable
- Show looted date in the report
- Show the zone column in the report
- Show the session cards and the activity graph at the top of the report
- Show currencies in the report
- Price source: vendor price alone, or an extra auction house column through Auctionator
- Record where loot came from, and show the source column in the report
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

## Building a release

`tools/build.ps1` (Windows) and `tools/build.sh` (bash) produce the same package: they validate the `.toc`, check that every file it lists exists on disk, run luacheck and the tests if those are installed, stage the addon into `dist/MyLootHistory` without the dev-only files, and zip it as `dist/MyLootHistory-<version>.zip`. They also print the metadata the CurseForge upload form asks for - game version and the newest changelog entry.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build.ps1
```

The `-ExecutionPolicy Bypass` is what to use if PowerShell refuses with *"tools\build.ps1 cannot be loaded because running scripts is disabled on this system"* - it applies to that one process only and changes nothing on the machine. Without that restriction, `.\tools\build.ps1` works directly.

Options, either way of invoking it:

- `-Version 1.5.0` - rewrites `## Version:` in the `.toc` before packaging
- `-Clean` - removes `dist\` first

```bash
./tools/build.sh                 # same thing under bash
./tools/build.sh --version 1.5.0
./tools/build.sh --clean
```

Tests alone run with [busted](https://lunarmodules.github.io/busted/) from the repo root (`luarocks install busted`):

```
busted
```

## License

MyLootHistory is licensed under the GNU General Public License version 3. See License file for details.
