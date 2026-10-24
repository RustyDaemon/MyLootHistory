--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")

local MLH_MMIcon = LibStub("LibDBIcon-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

local retentionOrder = { 0, 30, 90, 180, 365, 730 }
local retentionValues = {}

for i = 1, #retentionOrder do
    local days = retentionOrder[i]
    retentionValues[days] = (days == 0) and L["C_RetentionForever"] or L["C_RetentionValue"](days)
end

local function config()
    return MLH.db.char.config
end

local function alertsConfig()
    return MLH.db.char.config.alerts
end

local function debugConfig()
    return MLH.db.char.config.debug
end

local function alertsDisabled()
    return not alertsConfig().enabled
end

local function refreshReport()
    MLH:refreshReport()
end

-- A checkbox for the value at `key` in the table where() returns, labelled by the locale's `label` and
-- `label`_Desc. apply(), when given, puts a change into effect once it is saved. extra holds any other
-- fields the option needs, such as disabled.
local function toggle(order, where, key, label, apply, extra)
    local option = {
        order = order,
        type = "toggle",
        name = L[label],
        desc = L[label.."_Desc"],
        get = function (_)
            return where()[key]
        end,
        set = function (_, value)
            where()[key] = value

            if (apply) then apply(value) end
        end,
    }

    for field, value in pairs(extra or {}) do option[field] = value end

    return option
end

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
        resizableReportWindowCheckBox = toggle(11, config, "resizableReportWindow", "C_ResizableWindow",
            refreshReport),
        showHUDCheckBox = toggle(12, config, "showHUD", "C_ShowHUD", function () MLH:applyHUD() end),
        lockHUDCheckBox = toggle(13, config, "hudLocked", "C_LockHUD", nil, {
            disabled = function () return not config().showHUD end,
        }),
        -- windows already built keep their font, so it only fully applies after a reload
        pixelFontCheckBox = toggle(14, config, "pixelFont", "C_PixelFont", function ()
            MLH.UI:confirm({
                title = L["C_ReloadPromptTitle"],
                text = L["C_ReloadPrompt"],
                acceptText = L["C_ReloadPromptAccept"],
                cancelText = L["C_ReloadPromptLater"],
                onAccept = ReloadUI,
            })
        end),
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
                showLastLootedRowCheckBox = toggle(1, config, "showLastLooted", "C_ShowLastLootedRow",
                    refreshReport),
                showZoneColumnCheckBox = toggle(2, config, "showZone", "C_ShowZoneColumn", refreshReport),
                ignoreItemsWithZeroSellPriceCheckBox = toggle(3, config, "ignoreItemsWithZeroPrice",
                    "C_IgnoreZeroPriceItems"),
                questRewardsInRatesCheckBox = toggle(4, config, "questRewardsInRates", "C_QuestRewardsInRates",
                    function ()
                        MLH:updateHUD()
                        MLH:refreshReport()
                    end),
                showSessionBarCheckBox = toggle(5, config, "showSessionBar", "C_ShowSessionBar", refreshReport),

                priceSourceSelect = {
                    order = 6,
                    type = "select",
                    name = L["C_PriceSource"],
                    desc = L["C_PriceSource_Desc"],
                    values = function ()
                        return MLH:getPriceSources()
                    end,
                    sorting = { "vendor", "auctionator" },
                    get = function (_)
                        return config().priceSource or "vendor"
                    end,
                    set = function (_, value)
                        config().priceSource = value
                        MLH:clearPriceCache()
                        MLH:refreshReport()
                    end
                },

                showItemIDCheckBox = toggle(7, config, "showItemID", "C_ShowItemID", refreshReport),
                showItemTooltipCheckBox = toggle(8, config, "showTooltip", "C_ShowItemTooltip"),
                showAdditionalTooltipDataCheckBox = toggle(9, config, "showAdditionalTooltipData",
                    "C_ShowAdditionalTooltipData"),
                gameTooltipLineCheckBox = toggle(10, config, "gameTooltipLine", "C_GameTooltipLine"),
                trackCurrencyCheckBox = toggle(11, config, "trackCurrency", "C_TrackCurrency"),

                iconSizeRange = {
                    type = "range",
                    order = 12,
                    name = L["C_IconSize"],
                    min = 8,
                    max = 64,
                    step = 1,
                    softMin = 12,
                    softMax = 24,
                    get = function (_)
                        return config().reportIconSize
                    end,
                    set = function (_, value)
                        config().reportIconSize = value
                        MLH:refreshReport()
                    end
                },

                trackLootSourceCheckBox = toggle(13, config, "trackLootSource", "C_TrackLootSource", function ()
                    MLH:applySourceTracking()
                    MLH:refreshReport()
                end),
                showSourceColumnCheckBox = toggle(14, config, "showSource", "C_ShowSourceColumn", refreshReport, {
                    disabled = function () return not config().trackLootSource end,
                }),
            }
        },
        groupAlerts = {
            type = 'group',
            order = 22,
            name = L["C_Alerts"],
            args = {
                alertsEnabledCheckBox = toggle(1, alertsConfig, "enabled", "C_AlertsEnabled"),
                alertsCollectiblesCheckBox = toggle(2, alertsConfig, "collectibles", "C_AlertsCollectibles", nil, {
                    disabled = alertsDisabled,
                }),
                alertsMinQualitySelect = {
                    order = 3,
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
                        return alertsConfig().minQuality or 0
                    end,
                    set = function (_, value)
                        alertsConfig().minQuality = value
                    end
                },
                alertsMinValueRange = {
                    order = 4,
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
                        return alertsConfig().minValue or 0
                    end,
                    set = function (_, value)
                        alertsConfig().minValue = value
                    end
                },
                alertsSoundCheckBox = toggle(5, alertsConfig, "sound", "C_AlertsSound", nil, {
                    disabled = alertsDisabled,
                }),
                alertsChatCheckBox = toggle(6, alertsConfig, "chat", "C_AlertsChat", nil, {
                    disabled = alertsDisabled,
                }),
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
                    type = "select",
                    name = L["C_RetentionDays"],
                    desc = L["C_RetentionDays_Desc"],
                    values = retentionValues,
                    sorting = retentionOrder,
                    get = function (_)
                        return config().retentionDays or 0
                    end,
                    set = function (_, value)
                        local previous = config().retentionDays or 0

                        config().retentionDays = value

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
                                config().retentionDays = previous
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
                printDebugLootedInfo = toggle(1, debugConfig, "printLootedSummary", "C_PrintLootedSummary"),
                printDebugOtherInfo = toggle(2, debugConfig, "printOtherDebugInfo", "C_PrintOtherDebugInfo"),
            }
        },
        groupStatistics = MLH.groupStatistics,
        groupFaq = MLH.groupFaq,
    }
}

-- Drawn by settings/Window.lua.
MLH.settingsOptions = generalOptions
