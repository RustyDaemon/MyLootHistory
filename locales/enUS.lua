--[[
My Loot History addon
Copyright (C) 2024 Rustam (https://github.com/RustamIrzaev)

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
L["C_IgnoreZeroPriceItems"] = "Ignore items with 0 sell price"
L["C_IgnoreZeroPriceItems_Desc"] = "Ignore items with zero (0) sell price in the report"
L["C_IgnoreQuestItems"] = "Ignore Quest items"
L["C_IgnoreQuestItems_Desc"] = "Ignore quest items in the report"
L["C_ShowItemID"] = "Show Item ID"
L["C_ShowItemID_Desc"] = "Show or hide the Item ID value"
L["C_ShowItemTooltip"] = "Show item tooltip"
L["C_ShowItemTooltip_Desc"] = "Show or hide the item tooltip on mouse hover"
L["C_ShowAdditionalTooltipData"] = "Show additional tooltip data"
L["C_ShowAdditionalTooltipData_Desc"] = "Show or hide the additional tooltip data like item total quantity gathered, etc."
L["C_IconSize"] = "Icon size"
L["C_PrintLootedSummary"] = "Print looted summary"
L["C_PrintLootedSummary_Desc"] = "Print looted summary in the chat window (for debug purposes). This is visible only to you"
L["C_PrintOtherDebugInfo"] = "Print other debug info"
L["C_PrintOtherDebugInfo_Desc"] = "Like 'not my item' or so"
L["C_ClearData"] = "|cFFFF0000!!|r Clear data"
L["C_ClearData_Desc"] = "Clear all gathered data: items and gold. Forever. This action cannot be undone"

-- faq
L["F_WhatFor"] = "What is this addon for?"
L["F_WhatFor_Desc"] = "The addon that track everything you looted and show you the report with the gathered data. This is useful for the gold farming, for example, to track how much gold you got during the farm session. Or to track how many items you got from the specific zone, etc."
L["F_SortingFiltering"] = "Sorting and filtering"
L["F_SortingFiltering_Desc"] = "Everything can be filtered by a date and by a quality.\n\n"..
  "* Items quality can be filtered by a specific quality ('Exact quality checkbox') or by a quality range (for example, from Uncommon and further).\n"..
  "* Dates can be filtered by a specific date or by a date range. For example, 'Today' or 'This month'. \n\n"..
  "Sorting is made by descending order by default."
L["F_CanILinkToChat"] = "Can I link the item from the report?"
L["F_CanILinkToChat_Desc"] = "Yes, you can. Just Shift+click on the item icon and it will be linked to the chat. The chat should be opened."
L["F_Restrinctions"] = "Any known restrictions?"
L["F_Restrinctions_Desc"] = "As for now, the addon can't track upgraded items (the items that has been upgraded during the looting)."

-- messages
L["M_DataWasCleared"] = "Loot data and gold have been erased"
L["M_ClearDataPrompt"] = "Are you sure you want to clear the history of everything you looted? This includes items and gold and cannot be undone"

L["M_TotalDifferentItemsGathered"] = "Total different items gathered: "
L["M_TotalQuantityGathered"] = "Total quantity gathered: "
L["M_TotalZonesLooted"] = "Total zones looted: "

-- report
L["R_ReportDateRange"] = "Report date range"
L["R_MinimumItemQuality"] = "Minimum Item quality"
L["R_ExactItemQuality"] = "Exact item quality"
L["R_LootSomething"] = "Loot something"
L["R_Items"] = "Items: "
L["R_Quantity"] = "Quantity: "
L["R_SellPrice"] = "Sell price: "
L["R_GoldEarned"] = "Gold earned: "
L["R_Looted"] = "Looted: "
L["R_TotalQuantityGathered"] = "Total quantity gathered:"
L["R_NothingIsHereYet"] = "Nothing is here yet.\n  Loot something or change the filters :)"

-- report date range
L["RR_ThisSesion"] = "This session"
L["RR_Today"] = "Today"
L["RR_Yesterday"] = "Yesterday"
L["RR_WedToWed"] = "This reset (Wed-to-Wed)"
L["RR_ThisMonth"] = "This month"
L["RR_AllTheTime"] = "All the time"