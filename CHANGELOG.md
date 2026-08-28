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