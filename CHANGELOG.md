## 1.1.1
- Loot is now recognised from every "you picked this up" message the client sends, not just the plain one: stacks (`x20`), items pushed straight into your bags, and items you craft or gather are all tracked. Previously only the single-item message was matched.
- Quantities are read from the client's own message format instead of an English-only pattern, so a stack no longer records as 1 on a non-English client.
- Looking up an item on loot no longer scans the whole history; it uses an index. Noticeable on characters with a lot of loot.
- Opening the report and changing a filter no longer copies the entire database first.
- Removed two settings that could never do anything: "Ignore Quest items" (quest items are always skipped) and the unreachable "show last looted time".
- The addon no longer defines `MLH`, `getDate` and 12 other names as globals. `getDate` was defined twice, with the report file's copy silently overwriting the one `DateUtils-1.0` uses; it is now `DateUtils-1.0:getDate`.
- The quality filter list is built from named enum values rather than an offset from the end of the enum.

## 1.1.0
- Updated to 12.1.0 (Interface 120100).
- Fixed the report quantity: a row now shows the total number of items looted instead of the number of loot events. The sell price summary was understated for every stackable item and is now correct too.
- Fixed an error on money loot when the locale money pattern matched nothing (ruRU).
- Fixed items looted on a cold item cache being stored without a name, icon, quality or sell price. Item data is now awaited before the record is written.
- The looted quantity is stored as a number instead of a string.
- Migrated to `C_Item.GetItemInfo`, `C_Item.GetItemInfoFromHyperlink` and `C_Item.GetItemQualityColor`.
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