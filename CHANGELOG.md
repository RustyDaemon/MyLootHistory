## 2.0.0
- The report can show every character on the account at once. Switch "Show loot from" to All characters and an item three alts have looted is one row, with a Character column saying who found most of it and the full breakdown in the tooltip. Nothing is moved between characters: each one's history stays where it has always been, and the account view simply reads all of them.
- Sessions are kept. The one you are in is filed when you start a new one or log in again, and the session picker beside the date range lets you go back to it: last night's farm, with its own duration, its own items and its own gold. A session stores only the window it covered, so what it was worth is always worked out from the loot itself and can never drift.
- Loot now remembers where it came from: the creature it dropped off, the container it was in, or that it was crafted or gathered. There is an optional "From" column for it, and the item tooltip lists every source. Recording it can be switched off, and only loot picked up from now on can carry it.
- Auction house prices are a column of their own instead of replacing the vendor price, so both are visible at once, and the footer totals each of them.
- Fixed the filter controls running outside the window: they now flow onto a second line when the window is too narrow to hold them on one.
- Fixed the value and zone columns touching, and the sort arrow drawing as an empty box.
- Fixed two errors in the new window: the search box and the export window on some clients, and the date range control on every one of them.
- Fixed the report erroring on All characters when one of your characters last looted under a very old version. Those records are brought up to the current shape - quantity, date and zone all kept - the first time they are read.
- Fixed an error when hovering a unit the client will not let addons read, such as a quest object in a delve. It is skipped instead of being named.

## 1.5.0
- The report is a new window, drawn by the addon rather than assembled out of default widgets: a dark panel with the session across the top as four stat cards, the loot beneath it, and a footer that says what the view adds up to.
- Added an activity graph: one bar an hour for the last day, so you can see when you were earning and not only how much.
- Every row now carries a bar showing what share of the value it is, so the three things paying for the session are visible at a glance.
- The date range is a row of buttons instead of a dropdown, so switching between Today and This reset is one click.
- The item name, its zone and its dates share a row now, and the columns you have switched off move under the name instead of disappearing.
- Rows are recycled as you scroll, so a character with thousands of items opens as fast as a new one.
- The window remembers where you left it and how big it was.
- Searching hides the coins and the currencies that do not match, so a search matching nothing now says so.
- Settings that change what the report draws take effect immediately, with the report open.
- Fixed an error when hovering an item stored by an old version with no item link.
- Fixed the row highlight never appearing.

## 1.4.0
- Added a "keep history for" setting. Loot older than the chosen window is dropped on login, so the saved data stops growing forever. It is off by default: everything is kept until you say otherwise.
- Settings: retention and Clear data now live under a Data group of their own, instead of under Debug.
- Fixed an error on looting when the item link could not be read.
- Auction house prices are looked up by item link first, so gear and anything with bonus IDs is priced instead of falling through to its vendor value.
- A value that is still the vendor price under an auction house source is greyed, so it no longer reads as a market price.

## 1.3.0
- Added a live session line to the report: elapsed time, items per hour and gold per hour. Click it to start a new session.
- Item tooltips anywhere in the game now show how many you have looted before, and when.
- Currencies are tracked: Valorstones, Crests, Flightstones and the rest, with their zones and times.
- Optional Auctionator prices for the value column and the gold per hour figure.
- The CSV export now covers currencies too.

## 1.2.0
- Added a search box and sortable columns to the report. Your search text and sort order are remembered.
- Added a zone filter, an optional zone column and a per-zone breakdown in the tooltip.
- Added a value column, so the gold each row is worth is visible without hovering.
- Added a CSV export button.
- The report window now sizes itself to the columns you have switched on.

## 1.1.1
- Every kind of loot is tracked now: stacks, items pushed straight into your bags, and things you craft or gather.
- Stack sizes are recorded correctly on non-English clients.
- The report opens and filters faster on characters with a lot of history.
- Removed two settings that could never do anything.

## 1.1.0
- Updated to 12.1.0 (Interface 120100).
- Fixed report quantities: a row shows the number of items looted, not the number of times you looted them. The sell price summary was understated for stacks and is now correct.
- Fixed items looted on a cold cache being stored without a name, icon or quality.
- Fixed an error on money loot on some locales.
- Dropped the Classic and Wrath builds.

## 1.0.5
- Updated to 11.0.5.

## 1.0.4
- Updated to 11.0.2.

## 1.0.3
- Updated to 10.2.7.

## 1.0.2
- Updated to 10.2.5.

## 1.0.1
- The addon now adds itself to a compartment section.
- Added settings button in the report window.

## 1.0
- First public release.
