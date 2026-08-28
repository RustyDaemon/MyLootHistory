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
