--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local L = LibStub("AceLocale-3.0"):NewLocale("MyLootHistory", "enUS", true, true)

-- core
L["_MoneyPattern"] = "%d+"

L["_IntroMessage"] = function (addonName)
  return '|cFF00DD00'..addonName..'|r loaded. Happy looting! |cFFFF0000♥|r'
end

-- debug
L["D_AddedAndTotal"] = function (itemLink, totalAmount)
  return 'Added '..itemLink..'. Total quantity: '..totalAmount
end

L["D_NotMyItem"] = "not my item"
L["D_NotMyCurrency"] = "not my currency"
L["D_QuestItem"] = "quest item"
L["D_ZeroSellPrice"] = "sell price is 0"
L["D_NoMoneyMatched"] = "money pattern matched nothing"

-- minimap
L["MM_IconTitle"] = "My Loot History"
L["MM_Title"] = "|cFFFFFFFFMy Loot History|r"
L["MM_Separator"] = "|cFFAAAAAA---|r"
L["MM_LeftClickForReport"] = "|cFF00FF00Left click|r to open the report"
L["MM_RightClickForSettings"] = "|cFF00FF00Right click|r to open settings"

-- configuration
L["C_Report"] = "Report"
L["C_Debug"] = "Debug"
L["C_Statistics"] = "Statistics"
L["C_FAQ"] = "FAQ"
L["C_DetailedSettingsHeader"] = "Detailed settings"

L["C_ShowMinimapButton"] = "Show minimap button"
L["C_ShowMinimapButton_Desc"] = "Show or hide the minimap button"
L["C_ResizableWindow"] = "Resizable window"
L["C_ResizableWindow_Desc"] = "Make the report window resizable"
L["C_ShowLastLootedRow"] = "Show last looted date row"
L["C_ShowLastLootedRow_Desc"] = "Show or hide the last looted date row"
L["C_ShowZoneColumn"] = "Show zone column"
L["C_ShowZoneColumn_Desc"] = "Show the zone an item was mostly looted in. The full breakdown is always in the item tooltip"
L["C_TrackLootSource"] = "Record where loot came from"
L["C_TrackLootSource_Desc"] = "Remember what each drop came off - the creature, the container, or that it was crafted or gathered. Only loot picked up from now on can carry it; switching this off stops the recording and leaves what is already stored alone"
L["C_ShowSourceColumn"] = "Show source column"
L["C_ShowSourceColumn_Desc"] = "Show what an item mostly came from. The full breakdown is always in the item tooltip"
L["C_IgnoreZeroPriceItems"] = "Ignore items with 0 sell price"
L["C_IgnoreZeroPriceItems_Desc"] = "Ignore items with zero (0) sell price in the report"
L["C_ShowItemID"] = "Show Item ID"
L["C_ShowItemID_Desc"] = "Show or hide the Item ID value"
L["C_ShowItemTooltip"] = "Show item tooltip"
L["C_ShowItemTooltip_Desc"] = "Show or hide the item tooltip on mouse hover"
L["C_ShowAdditionalTooltipData"] = "Show additional tooltip data"
L["C_ShowAdditionalTooltipData_Desc"] = "Show or hide the additional tooltip data like item total quantity gathered, etc."
L["C_ShowSessionBar"] = "Show session bar"
L["C_ShowSessionBar_Desc"] = "Show the live session line at the top of the report: elapsed time, items per hour and gold per hour. Click it to start a new session"
L["C_ShowCurrency"] = "Show currencies in the report"
L["C_ShowCurrency_Desc"] = "List the currencies you picked up under the items, and include them in the CSV export"
L["C_TrackCurrency"] = "Track currencies"
L["C_TrackCurrency_Desc"] = "Record currencies (Valorstones, Crests, and so on) as they are picked up. Turning this off stops new records; the ones already stored are kept"
L["C_GameTooltipLine"] = "Add a line to item tooltips"
L["C_GameTooltipLine_Desc"] = "Add 'looted 47x, last on 3 Aug' to any item tooltip in the game for items you have looted before"
L["C_PriceSource"] = "Price source"
L["C_PriceSource_Desc"] = "Adds a second value column with auction house prices, next to the vendor price. Needs Auctionator installed; an item the chosen source has no price for shows a dash"
L["C_IconSize"] = "Icon size"
L["C_PrintLootedSummary"] = "Print looted summary"
L["C_PrintLootedSummary_Desc"] = "Print looted summary in the chat window (for debug purposes). This is visible only to you"
L["C_PrintOtherDebugInfo"] = "Print other debug info"
L["C_PrintOtherDebugInfo_Desc"] = "Like 'not my item' or so"
L["C_Data"] = "Data"
L["C_RetentionDays"] = "Keep history for"
L["C_RetentionDays_Desc"] = "Drop loot older than this on login, so the saved data stops growing forever. 'Forever' keeps everything, which is what the addon has always done"
L["C_RetentionForever"] = "Forever"
L["C_RetentionValue"] = function (days)
  return days < 365 and (days..' days') or (days == 365 and '1 year' or (days / 365)..' years')
end
L["C_RetentionPrompt"] = function (days)
  return 'Keep only the last '..days..' days? Everything older is removed from this character\'s history and cannot be recovered.'
end
L["C_ClearData"] = "|cFFFF0000!!|r Clear data"
L["C_ClearData_Desc"] = "Clear all gathered data: items and gold. Forever. This action cannot be undone"

-- faq
L["F_WhatFor"] = "What is this addon for?"
L["F_WhatFor_Desc"] = "The addon that track everything you looted and show you the report with the gathered data. This is useful for the gold farming, for example, to track how much gold you got during the farm session. Or to track how many items you got from the specific zone, etc."
L["F_SortingFiltering"] = "Sorting and filtering"
L["F_SortingFiltering_Desc"] = "Everything can be filtered by a name, a date, a quality and a zone.\n\n"..
  "* Type in the search box to keep only the items whose name contains what you typed.\n"..
  "* Items quality can be filtered by a specific quality ('Exact quality checkbox') or by a quality range (for example, from Uncommon and further).\n"..
  "* Dates can be filtered by a specific date or by a date range. For example, 'Today' or 'This month'. \n"..
  "* The zone dropdown lists every zone you have ever looted in. Picking one narrows the quantities and the gold to that zone.\n\n"..
  "Click a column header to sort by it, click it again to reverse the order. The choice is remembered per character."
L["F_Session"] = "What is the session line at the top of the report?"
L["F_Session_Desc"] = "It is the live half of the addon: how long you have been playing since you logged in, how many items that is per hour, and how much gold per hour "..
  "(the value of what you looted plus the coins you picked up).\n\n"..
  "Click the line to start a new session from that moment, which is what you want when you move to a new farming spot. "..
  "The same numbers are on the minimap button tooltip and behind '/mlh session'."
L["F_CanILinkToChat"] = "Can I link the item from the report?"
L["F_CanILinkToChat_Desc"] = "Yes, you can. Just Shift+click on the item icon and it will be linked to the chat. The chat should be opened."
L["F_Restrinctions"] = "Any known restrictions?"
L["F_Restrinctions_Desc"] = "As for now, the addon can't track upgraded items (the items that has been upgraded during the looting)."
L["F_Website"] = "Where can I read more?"
L["F_Website_Desc"] = "The site has the full guide, the FAQ and the changelog. The address is in the box below - click it and press Ctrl+C to copy it."
L["F_WebsiteLabel"] = "Website"

-- messages
L["M_DataWasCleared"] = "Loot data and gold have been erased"
L["M_HistoryPruned"] = function (entries, records, days)
  return 'Removed '..entries..' loot entries older than '..days..' days'
    ..(records > 0 and (', and '..records..' items that had nothing left') or '')
end
L["M_Website"] = function (website)
  return '|cFF00DD00My Loot History|r: '..website
end

L["M_Help"] = function (website)
  return '|cFF00DD00My Loot History|r\n'
    ..'|cFFFFD100/mlh|r - open the report\n'
    ..'|cFFFFD100/mlh config|r - open the settings\n'
    ..'|cFFFFD100/mlh session|r - print the current session line\n'
    ..'|cFFFFD100/mlh session reset|r - start a new session from now\n'
    ..'|cFFFFD100/mlh web|r - the addon site: '..website
end

L["M_ClearDataPrompt"] = "Are you sure you want to clear the history of everything you looted? This includes items and gold and cannot be undone"

L["M_TotalDifferentItemsGathered"] = "Total different items gathered: "
L["M_TotalQuantityGathered"] = "Total quantity gathered: "
L["M_TotalZonesLooted"] = "Total zones looted: "
L["M_TotalCurrenciesGathered"] = "Total different currencies gathered: "

-- report
L["R_ReportDateRange"] = "Report date range"
L["R_MinimumItemQuality"] = "Minimum Item quality"
L["R_ExactItemQuality"] = "Exact item quality"
L["R_LootSomething"] = "Loot something"
L["R_Items"] = "Items: "
L["R_Quantity"] = "Quantity: "
L["R_SellPrice"] = "Sell price: "
L["R_MarketPrice"] = "AH: "
L["R_GoldEarned"] = "Gold earned: "
L["R_TotalQuantityGathered"] = "Total quantity gathered:"
L["R_NothingIsHereYet"] = "Nothing is here yet.\n  Loot something or change the filters :)"
L["R_Search"] = "Search"
L["R_Zone"] = "Zone"
L["R_UnknownZone"] = "Unknown zone"
L["R_LootedIn"] = "Looted in:"
L["R_Currencies"] = "Currencies"
L["R_CurrenciesCount"] = "Currencies: "

-- session
L["S_SessionBar"] = function (duration, quantity, itemsPerHour, total, goldPerHour)
  return '|cFFFFD100Session|r '..duration..'  |cFFAAAAAA·|r  '..quantity..' items ('..itemsPerHour..'/h)'
    ..'  |cFFAAAAAA·|r  '..total..' ('..goldPerHour..'/h)'
end

L["S_SessionLine"] = function (duration, quantity, itemsPerHour, total, goldPerHour, currencyQuantity)
  return 'Session '..duration..': '..quantity..' items ('..itemsPerHour..'/h), '..total
    ..' ('..goldPerHour..'/h), '..currencyQuantity..' currency'
end

L["S_SessionTooltip"] = "Click to start a new session from now. The one you were in is filed under the session picker"

-- session history
L["S_LiveSession"] = "Current session"

L["S_SessionEntry"] = function (startedOn, duration, value)
  return startedOn..'  ·  '..duration..'  ·  '..value..'g'
end

L["S_SessionPicker"] = "Session"
L["S_PastSession"] = function (startedOn)
  return 'Session of '..startedOn
end

-- price sources
L["S_PriceVendor"] = "Vendor price"
L["S_PriceAuctionator"] = "Auctionator"
L["S_PriceUnavailable"] = "(not installed)"

-- tooltip
L["T_LootedSummary"] = function (quantity, lastDate)
  return 'My Loot History: looted '..quantity..'x, last on '..lastDate
end

L["T_MostlyIn"] = function (zoneName)
  return 'Mostly in '..zoneName
end

-- report columns
L["R_ColQuality"] = "Q"
L["R_ColItem"] = "Item"
L["R_ColQuantity"] = "Qty"
L["R_ColValue"] = "Value"
L["R_ColZone"] = "Zone"
L["R_ColLooted"] = "Looted"
L["R_ColValueMarket"] = "AH"
L["R_ColCharacter"] = "Character"
L["R_ColSource"] = "From"

-- account-wide history
L["R_ScopeCharacter"] = "This character"
L["R_ScopeAccount"] = "All characters"
L["R_Scope"] = "Show loot from"

L["R_SeveralCharacters"] = function (count)
  return count..' characters'
end

L["R_LootedBy"] = "Looted by:"
L["R_DroppedBy"] = "From:"

-- loot sources, for the drops the client named nothing better than their kind
L["R_SourceCreature"] = "A creature"
L["R_SourceObject"] = "An object"
L["R_SourceContainer"] = "A container"
L["R_SourcePlayer"] = "Traded"
L["R_SourceCrafted"] = "Crafted or gathered"
L["R_SourcePushed"] = "Quest or container"

L["R_SortBy"] = function (columnName)
  return 'Click to sort by "'..columnName..'". Click again to reverse the order'
end

-- report window chrome
L["R_SearchPlaceholder"] = "Item name..."
L["R_ResetFilters"] = "Reset filters"
L["R_Close"] = "Close"
L["R_Settings"] = "Settings"
L["R_ResizeHint"] = "Drag to resize"
L["R_ShiftClickToLink"] = "Shift+click to link it in chat"
L["R_Money"] = "Money"
L["R_GoldEarnedShort"] = "Gold looted"

L["R_MostlyFrom"] = function (zoneName)
  return 'Mostly from '..zoneName
end

L["R_ExportTooltip"] = "Copy everything the filters are showing as CSV"

-- stat cards
L["G_Session"] = "SESSION"
L["G_ItemsPerHour"] = "ITEMS / HOUR"
L["G_GoldPerHour"] = "GOLD / HOUR"
L["G_InView"] = "IN VIEW"
L["G_SinceLogin"] = "click to start a new one"
L["G_ItemsPerHourTooltip"] = "How fast you are picking things up, measured over the whole session"
L["G_GoldPerHourTooltip"] = "The value of everything you looted plus the coins, per hour of this session"
L["G_InViewTooltip"] = "What the rows below add up to, coins included. It follows the filters"

L["G_ItemsTotal"] = function (quantity)
  return quantity..' items this session'
end

L["G_ValueSoFar"] = function (gold)
  return gold..' gold so far'
end

-- activity graph
L["G_Last24h"] = "LAST 24 HOURS"
L["G_Peak"] = "peak "

L["G_BarTooltip"] = function (quantity, gold)
  return quantity..' items, worth about '..gold..' gold'
end

-- short date range labels, for the segmented control in the filter bar
L["RS_Session"] = "Session"
L["RS_Today"] = "Today"
L["RS_Yesterday"] = "Yest."
L["RS_Reset"] = "Reset"
L["RS_Month"] = "Month"
L["RS_All"] = "All"

-- export
L["R_Export"] = "Export CSV"
L["R_ExportTitle"] = "My Loot History - CSV export"

L["R_ExportHint"] = function (itemCount)
  return itemCount..' item(s), matching the filters in the report. Press Ctrl+C to copy'
end

-- report date range
L["RR_ThisSesion"] = "This session"
L["RR_Today"] = "Today"
L["RR_Yesterday"] = "Yesterday"
L["RR_WedToWed"] = "This reset (Wed-to-Wed)"
L["RR_ThisMonth"] = "This month"
L["RR_AllTheTime"] = "All the time"

-- report zone filter
L["RR_AnyZone"] = "Any zone"