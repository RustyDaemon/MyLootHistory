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

local retentionOrder = { 0, 30, 90, 180, 365, 730 }
local retentionValues = {}

for i = 1, #retentionOrder do
    local days = retentionOrder[i]
    retentionValues[days] = (days == 0) and L["C_RetentionForever"] or L["C_RetentionValue"](days)
end

local function alertsDisabled()
    return not MLH.db.char.config.alerts.enabled
end

local mainOptions = {
    name = 'My Loot History',
    type = 'group',
    args = {
        openSettingsButton = {
            type = 'execute',
            name = L["C_OpenSettings"],
            func = function ()
                HideUIPanel(SettingsPanel)
                MLH:openSettings()
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
            desc = L["C_ResizableWindow_Desc"],
            get = function (_)
                return MLH.db.char.config.resizableReportWindow
            end,
            set = function (_, value)
                MLH.db.char.config.resizableReportWindow = value
                MLH:refreshReport()
            end
        },
        showHUDCheckBox = {
            order = 12,
            type = "toggle",
            name = L["C_ShowHUD"],
            desc = L["C_ShowHUD_Desc"],
            get = function (_)
                return MLH.db.char.config.showHUD
            end,
            set = function (_, value)
                MLH.db.char.config.showHUD = value
                MLH:applyHUD()
            end
        },
        lockHUDCheckBox = {
            order = 13,
            type = "toggle",
            name = L["C_LockHUD"],
            desc = L["C_LockHUD_Desc"],
            disabled = function () return not MLH.db.char.config.showHUD end,
            get = function (_)
                return MLH.db.char.config.hudLocked
            end,
            set = function (_, value)
                MLH.db.char.config.hudLocked = value
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
                    name = L["C_IgnoreZeroPriceItems"],
                    desc = L["C_IgnoreZeroPriceItems_Desc"],
                    get = function (_)
                        return MLH.db.char.config.ignoreItemsWithZeroPrice
                    end,
                    set = function (_, value)
                        MLH.db.char.config.ignoreItemsWithZeroPrice = value
                    end
                },
                questRewardsInRatesCheckBox = {
                    order = 3.5,
                    width = "double",
                    type = "toggle",
                    name = L["C_QuestRewardsInRates"],
                    desc = L["C_QuestRewardsInRates_Desc"],
                    get = function (_)
                        return MLH.db.char.config.questRewardsInRates
                    end,
                    set = function (_, value)
                        MLH.db.char.config.questRewardsInRates = value
                        MLH:updateHUD()
                        MLH:refreshReport()
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
        groupAlerts = {
            type = 'group',
            order = 22,
            name = L["C_Alerts"],
            args = {
                alertsEnabledCheckBox = {
                    order = 1,
                    width = "double",
                    type = "toggle",
                    name = L["C_AlertsEnabled"],
                    desc = L["C_AlertsEnabled_Desc"],
                    get = function (_)
                        return MLH.db.char.config.alerts.enabled
                    end,
                    set = function (_, value)
                        MLH.db.char.config.alerts.enabled = value
                    end
                },
                alertsCollectiblesCheckBox = {
                    order = 2,
                    width = "double",
                    type = "toggle",
                    name = L["C_AlertsCollectibles"],
                    desc = L["C_AlertsCollectibles_Desc"],
                    disabled = alertsDisabled,
                    get = function (_)
                        return MLH.db.char.config.alerts.collectibles
                    end,
                    set = function (_, value)
                        MLH.db.char.config.alerts.collectibles = value
                    end
                },
                alertsMinQualitySelect = {
                    order = 3,
                    width = "double",
                    type = "select",
                    name = L["C_AlertsMinQuality"],
                    desc = L["C_AlertsMinQuality_Desc"],
                    disabled = alertsDisabled,
                    values = function ()
                        return {
                            [0] = L["C_Off"],
                            [3] = MLH:getQualityName(3),
                            [4] = MLH:getQualityName(4),
                            [5] = MLH:getQualityName(5),
                        }
                    end,
                    sorting = { 0, 3, 4, 5 },
                    get = function (_)
                        return MLH.db.char.config.alerts.minQuality or 0
                    end,
                    set = function (_, value)
                        MLH.db.char.config.alerts.minQuality = value
                    end
                },
                alertsMinValueRange = {
                    order = 4,
                    width = "double",
                    type = "range",
                    name = L["C_AlertsMinValue"],
                    desc = L["C_AlertsMinValue_Desc"],
                    disabled = alertsDisabled,
                    min = 0,
                    max = 1000000,
                    softMax = 10000,
                    step = 1,
                    bigStep = 50,
                    get = function (_)
                        return MLH.db.char.config.alerts.minValue or 0
                    end,
                    set = function (_, value)
                        MLH.db.char.config.alerts.minValue = value
                    end
                },
                alertsSoundCheckBox = {
                    order = 5,
                    width = "double",
                    type = "toggle",
                    name = L["C_AlertsSound"],
                    desc = L["C_AlertsSound_Desc"],
                    disabled = alertsDisabled,
                    get = function (_)
                        return MLH.db.char.config.alerts.sound
                    end,
                    set = function (_, value)
                        MLH.db.char.config.alerts.sound = value
                    end
                },
                alertsChatCheckBox = {
                    order = 6,
                    width = "double",
                    type = "toggle",
                    name = L["C_AlertsChat"],
                    desc = L["C_AlertsChat_Desc"],
                    disabled = alertsDisabled,
                    get = function (_)
                        return MLH.db.char.config.alerts.chat
                    end,
                    set = function (_, value)
                        MLH.db.char.config.alerts.chat = value
                    end
                },
                alertsPreviewButton = {
                    order = 10,
                    type = "execute",
                    name = L["C_AlertsPreview"],
                    desc = L["C_AlertsPreview_Desc"],
                    disabled = alertsDisabled,
                    func = function ()
                        MLH:previewDropAlert()
                    end
                },
            }
        },
        groupHidden = {
            type = 'group',
            order = 22.5,
            name = L["C_HiddenItems"],
            args = {
                hiddenItemsText = {
                    order = 1,
                    type = 'description',
                    name = L["C_HiddenItems_Desc"],
                },
                hiddenItemsList = {
                    order = 2,
                    type = "list",
                    actionText = L["C_Unhide"],
                    emptyText = L["C_NoHiddenItems"],
                    values = function ()
                        local values = {}

                        for _, item in ipairs(MLH:getHiddenItemList()) do
                            local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.itemId)

                            values[#values+1] = {
                                text = (icon and ("|T"..icon..":16:16:0:0|t ") or "")..item.name,
                                value = item.itemId,
                            }
                        end

                        return values
                    end,
                    func = function (_, itemID)
                        MLH:setItemHidden(itemID, false)
                        MLH:refreshReport()
                    end
                },
            }
        },
        groupData = {
            type = 'group',
            order = 23,
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

                        if (value <= 0) then return end

                        MLH.UI:confirm({
                            title = L["C_RetentionPromptTitle"],
                            text = L["C_RetentionPrompt"](value),
                            acceptText = L["C_RetentionPromptAccept"],
                            cancelText = L["C_Cancel"],
                            danger = true,
                            onAccept = function ()
                                local entries, records = MLH:pruneHistory()

                                if (entries > 0) then
                                    print(L["M_HistoryPruned"](entries, records, value))
                                end

                                MLH:refreshSettings()
                            end,
                            onCancel = function ()
                                MLH.db.char.config.retentionDays = previous
                                MLH:refreshSettings()
                            end,
                        })
                    end
                },
                clearData = {
                    order = 10,
                    type = "execute",
                    name = L["C_ClearData"],
                    desc = L["C_ClearData_Desc"],
                    func = function ()
                        MLH.UI:confirm({
                            title = L["M_ClearDataPromptTitle"],
                            text = L["M_ClearDataPrompt"],
                            acceptText = L["M_ClearDataAccept"],
                            cancelText = L["C_Cancel"],
                            danger = true,
                            onAccept = function ()
                                MLH:resetData()
                                MLH:refreshSettings()
                            end,
                        })
                    end
                }
            }
        },
        groupDebug = {
            type = 'group',
            order = 24,
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

-- Drawn by settings/Window.lua, not by AceConfigDialog, so it is not registered.
MLH.settingsOptions = generalOptions

function MLH:initConfig()
    ACFG:RegisterOptionsTable("MyLootHistory_MainOptions", mainOptions)

    ACFGDLG:AddToBlizOptions("MyLootHistory_MainOptions", "My Loot History")
end

function MLH:getStatisticsText()
    local itemsFound = self.db.char.foundItems
    local itemTypesAmount = #itemsFound
    local totalAmount = 0
    local seenZones, zonesAmount = {}, 0

    for i = 1, itemTypesAmount do
        local lootData = itemsFound[i].lootData

        for j = 1, #lootData do
            local entry = lootData[j]

            totalAmount = totalAmount + (tonumber(entry.quantity) or 1)

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
