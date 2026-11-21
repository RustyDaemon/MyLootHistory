<!-- The source for My Loot History's CurseForge page: edited here, then pasted into the project's fields there. Reflects 2.6.0. -->

# Name

My Loot History

# Summary

Tracks every item, coin and currency you loot, with gold per hour, sessions, sources and drop alerts, in a report you actually want to look at. Retail and WoW Forever.

# Categories

Check these against CurseForge's category dropdown before saving.

- Primary: Auction & Economy
- Also: Bags & Inventory, Data Export, Tooltip

# Game versions

Retail 12.1.5 and WoW Forever, from the same download (`## Interface: 120105, 16001`).

# Description

**Know exactly what your farming is worth.**

My Loot History tracks every item, coin and currency you loot, and turns it into a report you actually want to look at.

Works on Retail and WoW Forever, from the same download.

## Why you want it

- **Gold per hour, live.** See if this spot is still worth farming, without leaving the game.
- **Every drop, remembered.** Items, currencies and coins, with quantity, value, zone and date.
- **Know where things drop from.** The tooltip tells you which mob is actually paying for your farm.
- **Compare last night's farm to tonight's.** Sessions are saved, not thrown away.
- **All your characters in one view.** Or just this one. Your choice.

## The report

Type `/mlh` and you get one clean window:

- **Live stat cards**: time farmed, items per hour, gold per hour, and what you're looking at is worth. Click the Session card to start a new session (it asks first).
- **An hourly graph**: see _when_ you were earning, not just how much.
- **A value bar on every row**: spot the three items paying for the whole session at a glance.
- **A gold row with a tooltip**: the coins you picked up, the gold from quest rewards and the total, for the time and zone shown.
- **A Currencies tab**: earned, per hour, what you're holding, and how close you are to the weekly or seasonal cap.
- **Filters and sorting**: by character, date range, session, zone, name or quality. Sort any column.
- **All characters or just this one.** Switch "Show loot from" to All characters and an item three alts have looted is one row, with a Character column saying who found most of it.
- **Right-click a row** to show only one zone's loot, or to hide an item. A hidden item's history is kept, and one click in the settings brings it back.
- **Export to CSV**: whatever you're looking at, exactly as you filtered it.

It is resizable, remembers its size and position, closes on Escape, says why when it's empty, and stays fast even with thousands of items.

## The session HUD

Three numbers on your screen, no window needed: time farmed, items per hour and gold per hour. Drag it anywhere and lock it. Left click opens the report, right click starts a fresh session (it asks first) when you move to a new spot. Turn it on with `/mlh hud`.

Go AFK or rest in an inn or a city and the clock pauses (the HUD says so), so a break doesn't drag your gold per hour down. What you loot or craft meanwhile is still recorded, just left out of the per-hour figures. Switch it off in the settings if you'd rather count every minute.

## Drop alerts

Loot a mount, pet, toy, an Epic, or anything worth more than the gold you set, and a small toast pops up with the item and what it's worth. It tells you when gear is a **new appearance**, and when a mount, pet or toy is one you **already own**. Hover a toast to keep it on screen, click to dismiss it, Shift+click to link the item in chat.

## Share your farm

`/mlh share`, or the chat button in the report, posts one line: time farmed, items, gold, gold per hour and the best drop, linked. It goes to your group, or only to you when you're solo, unless you name a channel.

## Tooltips everywhere

Hover any item (in your bags, at a vendor, in the auction house, in chat) and see how many you've looted before and when the last one dropped. No report needed.

## Prices

Vendor price by default. Install [Auctionator](https://www.curseforge.com/wow/addons/auctionator) and switch the price source to get an auction house column too, both side by side.

## Settings

`/mlh config`, the gear in the report, a right click on the minimap button, or the addon's page in the game's options (AddOns tab) opens the settings.

- **General**: Show minimap button, Resizable window, Show session HUD, Lock the HUD, Pixel font (the addon's own font for English, German, French, Spanish, Portuguese and Italian; takes effect after a reload).
- **Report**: Show last looted date row, Show zone column, Ignore items with 0 sell price, Count quest rewards in gold per hour, Pause while away or resting, Show session bar, Price source, Show Item ID, Show item tooltip, Show additional tooltip data, Add a line to item tooltips, Track currencies, Icon size, Record where loot came from, Show source column.
- **Drop alerts**: Alert on notable drops, Mounts, pets and toys, Quality at least, Worth at least (gold), Play a sound, Also print to chat, and a Preview button.
- **Hidden items**: every item you hid, with Unhide to bring its history back. Shared by all your characters.
- **Data**: Keep history for (Forever, or from 30 days to two years), and Clear data.
- **Debug**: Print looted summary, Print other debug info.
- **Statistics** and **FAQ** pages.

The game's options page also shows your current session at a glance. Broker displays such as Titan Panel, ElvUI and ChocolateBar show the session's gold per hour.

## Slash commands

- `/mlh`: open the report
- `/mlh config`: open the settings
- `/mlh session`: print time, items per hour and gold per hour
- `/mlh session reset`: start a new session now
- `/mlh share [channel]`: post the session line in chat (party, raid, instance, guild or say)
- `/mlh hud`: show or hide the HUD
- `/mlh hud lock`: lock or unlock the HUD in place
- `/mlh web`: print the addon's site
- `/mlh help`: list the commands

## Good to know

- Quest rewards (gold, items and currencies) are kept in your history under the quest's name, but left out of gold per hour unless you switch that on in the settings.
- Loot sources are recorded from the moment you install: older loot has no source to show.
- An upgraded drop (302 → 323 item level) is valued as what actually dropped.

## Links

- Website: [mlh.rustydaemon.com](https://mlh.rustydaemon.com)
- Source and issues: [GitHub](https://github.com/RustyDaemon/MyLootHistory)
- Questions, bugs and ideas: [Discord](https://discord.gg/B5tyg8Bwyy)

# Logo

`assets/icon.png`.

# Screenshots

Already in `assets/screenshots/`:

- `main.png`: the report window, with looted items, value, source and zone.
- `secondary.png`: the Currencies tab.
- `report.png`: the CSV export window.
- `hud.png`: the session HUD.

Still to take in game:

1. **A drop alert.** A toast for an Epic or a mount, ideally with "New appearance" or "Already owned".
2. **The settings window.** `/mlh config` on the Report or Drop alerts page.
3. **The item tooltip line.** An item in the bags with "looted 47x, last on 3 Aug" in its tooltip.
4. **All characters.** The report with "Show loot from" on All characters and the Character column showing.
5. **The shared line.** The chat line `/mlh share` posts, the best drop linked.
6. **The game's options page.** The addon's page in the AddOns tab, with the current session.
