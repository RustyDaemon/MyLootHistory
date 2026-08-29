--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")

local ACFG = LibStub("AceConfig-3.0")
local ACFGDLG = LibStub("AceConfigDialog-3.0")
local MLH_MMIcon = LibStub("LibDBIcon-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

-- How long a character's history is kept. 0 is "forever", and the dropdown lists it first
-- because it is the default and the only choice that never deletes anything.
local retentionOrder = { 0, 30, 90, 180, 365, 730 }
local retentionValues = {}

for i = 1, #retentionOrder do
    local days = retentionOrder[i]
    retentionValues[days] = (days == 0) and L["C_RetentionForever"] or L["C_RetentionValue"](days)
end

local mainOptions = {
    name = 'My Loot History',
    type = 'group',
    args = {
        openSettingsButton = {
            type = 'execute',
            name = 'Open settings',
            func = function ()
                HideUIPanel(SettingsPanel)
                ACFGDLG:Open("MyLootHistory_GeneralOptions")
            end
        }
    }
}

local generalOptions = {
    name = "My Loot History",
    type = "group",
    args = {
        minimapButtonCheckBox = {
            order = 10,
            type = "toggle",
            name = L["C_ShowMinimapButton"],
            desc = L["C_ShowMinimapButton_Desc"],
            get = function (_)
                return not MLH.db.char.minimapData.hide
            end,
            set = function (_, value)
                MLH.db.char.minimapData.hide = not value
                if (value) then
                    MLH_MMIcon:Show("MyLootHistory")
                else
                    MLH_MMIcon:Hide("MyLootHistory")
                end
            end
        },
        resizableReportWindowCheckBox = {
            order = 11,
            type = "toggle",
            name = L["C_ResizableWindow"],
            desc = "Make the report window resizable",
            get = function (_)
                return MLH.db.char.config.resizableReportWindow
            end,
            set = function (_, value)
                MLH.db.char.config.resizableReportWindow = value
                MLH:refreshReport()
            end
        },
        detailedHeader = {
            type = 'header',
            name = L["C_DetailedSettingsHeader"],
            order = 20,
        },
        groupReport = {
            type = 'group',
            order = 21,
            name = L["C_Report"],
            args = {
                showLastLootedRowCheckBox = {
                    order = 1,
                    width = "double",
                    type = "toggle",
                    -- descStyle = "inline",
                    name = L["C_ShowLastLootedRow"],
                    desc = L["C_ShowLastLootedRow_Desc"],
                    get = function (_)
                        return MLH.db.char.config.showLastLooted
                    end,
                    set = function (_, value)
                        MLH.db.char.config.showLastLooted = value
                        MLH:refreshReport()
                    end
                },
                showZoneColumnCheckBox = {
                    order = 2,
                    width = "double",
                    type = "toggle",
                    name = L["C_ShowZoneColumn"],
                    desc = L["C_ShowZoneColumn_Desc"],
                    get = function (_)
                        return MLH.db.char.config.showZone
                    end,
                    set = function (_, value)
                        MLH.db.char.config.showZone = value
                        MLH:refreshReport()
                    end
                },
                trackLootSourceCheckBox = {
                    order = 21,
                    width = "double",
                    type = "toggle",
                    name = L["C_TrackLootSource"],
                    desc = L["C_TrackLootSource_Desc"],
                    get = function (_)
                        return MLH.db.char.config.trackLootSource
                    end,
                    set = function (_, value)
                        MLH.db.char.config.trackLootSource = value
                        MLH:applySourceTracking()
                        MLH:refreshReport()
                    end
                },
                showSourceColumnCheckBox = {
                    order = 22,
                    width = "double",
                    type = "toggle",
                    name = L["C_ShowSourceColumn"],
                    desc = L["C_ShowSourceColumn_Desc"],
                    -- the column can only show what was recorded, so it follows the switch above
                    disabled = function () return not MLH.db.char.config.trackLootSource end,
                    get = function (_)
                        return MLH.db.char.config.showSource
                    end,
                    set = function (_, value)
                        MLH.db.char.config.showSource = value
                        MLH:refreshReport()
                    end
                },
                ignoreItemsWithZeroSellPriceCheckBox = {
                    order = 3,
                    width = "double",
                    type = "toggle",
                    -- descStyle = "inline",
                    name = L["C_IgnoreZeroPriceItems"],
                    desc = L["C_IgnoreZeroPriceItems_Desc"],
                    get = function (_)
                        return MLH.db.char.config.ignoreItemsWithZeroPrice
                    end,
                    set = function (_, value)
                        MLH.db.char.config.ignoreItemsWithZeroPrice = value
                    end
                },

                showSessionBarCheckBox = {
                    order = 4,
                    width = "double",
                    type = "toggle",
                    name = L["C_ShowSessionBar"],
                    desc = L["C_ShowSessionBar_Desc"],
                    get = function (_)
                        return MLH.db.char.config.showSessionBar
                    end,
                    set = function (_, value)
                        MLH.db.char.config.showSessionBar = value
                        MLH:refreshReport()
                    end
                },

                showCurrencyCheckBox = {
                    order = 5,
                    width = "double",
                    type = "toggle",
                    name = L["C_ShowCurrency"],
                    desc = L["C_ShowCurrency_Desc"],
                    get = function (_)
                        return MLH.db.char.config.showCurrency
                    end,
                    set = function (_, value)
                        MLH.db.char.config.showCurrency = value
                        MLH:refreshReport()
                    end
                },

                priceSourceSelect = {
                    order = 6,
                    width = "double",
                    type = "select",
                    name = L["C_PriceSource"],
                    desc = L["C_PriceSource_Desc"],
                    values = function ()
                        return MLH:getPriceSources()
                    end,
                    sorting = { "vendor", "auctionator" },
                    get = function (_)
                        return MLH.db.char.config.priceSource or "vendor"
                    end,
                    set = function (_, value)
                        MLH.db.char.config.priceSource = value
                        MLH:clearPriceCache()
                        MLH:refreshReport()
                    end
                },

                showItemIDCheckBox = {
                    order = 7,
                    width = "double",
                    type = "toggle",
                    name = L["C_ShowItemID"],
                    desc = L["C_ShowItemID_Desc"],
                    get = function (_)
                        return MLH.db.char.config.showItemID
                    end,
                    set = function (_, value)
                        MLH.db.char.config.showItemID = value
                        MLH:refreshReport()
                    end
                },

                showItemTooltipCheckBox = {
                    order = 9,
                    width = "double",
                    type = "toggle",
                    name = L["C_ShowItemTooltip"],
                    desc = L["C_ShowItemTooltip_Desc"],
                    get = function (_)
                        return MLH.db.char.config.showTooltip
                    end,
                    set = function (_, value)
                        MLH.db.char.config.showTooltip = value
                    end
                },

                showAdditionalTooltipDataCheckBox = {
                    order = 10,
                    width = "double",
                    type = "toggle",
                    name = L["C_ShowAdditionalTooltipData"],
                    desc = L["C_ShowAdditionalTooltipData_Desc"],
                    get = function (_)
                        return MLH.db.char.config.showAdditionalTooltipData
                    end,
                    set = function (_, value)
                        MLH.db.char.config.showAdditionalTooltipData = value
                    end
                },

                gameTooltipLineCheckBox = {
                    order = 11,
                    width = "double",
                    type = "toggle",
                    name = L["C_GameTooltipLine"],
                    desc = L["C_GameTooltipLine_Desc"],
                    get = function (_)
                        return MLH.db.char.config.gameTooltipLine
                    end,
                    set = function (_, value)
                        MLH.db.char.config.gameTooltipLine = value
                    end
                },

                trackCurrencyCheckBox = {
                    order = 12,
                    width = "double",
                    type = "toggle",
                    name = L["C_TrackCurrency"],
                    desc = L["C_TrackCurrency_Desc"],
                    get = function (_)
                        return MLH.db.char.config.trackCurrency
                    end,
                    set = function (_, value)
                        MLH.db.char.config.trackCurrency = value
                    end
                },

                iconSizeRange = {
                    type = "range",
                    order = 13,
                    name = L["C_IconSize"],
                    min = 8,
                    max = 64,
                    step = 1,
                    softMin = 12,
                    softMax = 24,
                    get = function (_)
                        return MLH.db.char.config.reportIconSize
                    end,
                    set = function (_, value)
                        MLH.db.char.config.reportIconSize = value
                        MLH:refreshReport()
                    end
                }
            }
        },
        groupData = {
            type = 'group',
            order = 22,
            name = L["C_Data"],
            args = {
                retentionSelect = {
                    order = 1,
                    width = "double",
                    type = "select",
                    name = L["C_RetentionDays"],
                    desc = L["C_RetentionDays_Desc"],
                    values = retentionValues,
                    sorting = retentionOrder,
                    get = function (_)
                        return MLH.db.char.config.retentionDays or 0
                    end,
                    set = function (_, value)
                        local previous = MLH.db.char.config.retentionDays or 0

                        MLH.db.char.config.retentionDays = value

                        -- Forever removes nothing, so it needs no confirmation; anything else
                        -- takes effect now rather than at the next login, and that deletes.
                        if (value <= 0) then return end

                        StaticPopupDialogs["PROMPT_PRUNE_HISTORY"] = {
                            text = L["C_RetentionPrompt"](value),
                            button1 = YES,
                            button2 = NO,
                            OnAccept = function ()
                                local entries, records = MLH:pruneHistory()

                                if (entries > 0) then
                                    print(L["M_HistoryPruned"](entries, records, value))
                                end
                            end,
                            OnCancel = function ()
                                MLH.db.char.config.retentionDays = previous
                            end,
                            whileDead = true,
                            hideOnEscape = true,
                            showAlert = true,
                            enterClicksFirstButton = false,
                        }

                        StaticPopup_Show("PROMPT_PRUNE_HISTORY")
                    end
                },
                clearData = {
                    order = 10,
                    type = "execute",
                    name = L["C_ClearData"],
                    desc = L["C_ClearData_Desc"],
                    func = function ()
                        StaticPopupDialogs["PROMPT_CLEAR_DATA"] = {
                            text = L["M_ClearDataPrompt"],
                            button1 = YES,
                            button2 = NO,
                            OnAccept = function()
                                MLH:resetData()
                            end,
                            OnCancel = function (_,_, reason) end,
                            whileDead = true,
                            hideOnEscape = true,
                            showAlert = true,
                            enterClicksFirstButton = false,
                          }

                          StaticPopup_Show("PROMPT_CLEAR_DATA")
                    end
                }
            }
        },
        groupDebug = {
            type = 'group',
            order = 23,
            name = L["C_Debug"],
            args = {
                printDebugLootedInfo = {
                    order = 1,
                    width = "double",
                    type = "toggle",
                    name = L["C_PrintLootedSummary"],
                    desc = L["C_PrintLootedSummary_Desc"],
                    get = function (_)
                        return MLH.db.char.config.debug.printLootedSummary
                    end,
                    set = function (_, value)
                        MLH.db.char.config.debug.printLootedSummary = value
                    end
                },
                printDebugOtherInfo = {
                    order = 2,
                    width = "double",
                    type = "toggle",
                    name = L["C_PrintOtherDebugInfo"],
                    desc = L["C_PrintOtherDebugInfo_Desc"],
                    get = function (_)
                        return MLH.db.char.config.debug.printOtherDebugInfo
                    end,
                    set = function (_, value)
                        MLH.db.char.config.debug.printOtherDebugInfo = value
                    end
                }
            }
        },
        groupStatistics = MLH.groupStatistics,
        groupFaq = MLH.groupFaq,
    }
}

function MLH:initConfig()
    ACFG:RegisterOptionsTable("MyLootHistory_MainOptions", mainOptions)
    ACFG:RegisterOptionsTable("MyLootHistory_GeneralOptions", generalOptions)

    ACFGDLG:AddToBlizOptions("MyLootHistory_MainOptions", "My Loot History")
end

-- The statistics page walks the whole history, so it is read when that page is drawn and
-- never while looting: this used to be recomputed on every single loot message, which on a
-- long history meant a full scan - plus a linear search through the zone list per entry -
-- for every pickup.
function MLH:getStatisticsText()
    local itemsFound = self.db.char.foundItems
    local itemTypesAmount = #itemsFound
    local totalAmount = 0
    local seenZones, zonesAmount = {}, 0

    for i = 1, itemTypesAmount do
        local lootData = itemsFound[i].lootData

        for j = 1, #lootData do
            local entry = lootData[j]

            -- an entry written by a very old version can carry no quantity
            totalAmount = totalAmount + (tonumber(entry.quantity) or 1)

            -- ... and no zone, which is a group of its own rather than a nil table key
            local zoneID = entry.zoneID or entry.zone or false

            if (not seenZones[zoneID]) then
                seenZones[zoneID] = true
                zonesAmount = zonesAmount + 1
            end
        end
    end

    local currencyTypesAmount = #(self.db.char.foundCurrency or {})

    return L["M_TotalDifferentItemsGathered"]..itemTypesAmount
        ..'\n'..L["M_TotalQuantityGathered"]..totalAmount..'\n'..L["M_TotalZonesLooted"]..zonesAmount
        ..'\n'..L["M_TotalCurrenciesGathered"]..currencyTypesAmount
    ..'\n\n'..self:getSessionLine()
end
