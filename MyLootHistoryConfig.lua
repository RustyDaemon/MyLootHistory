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
                    end
                },
                ignoreItemsWithZeroSellPriceCheckBox = {
                    order = 2,
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
                        return MLH.db.char.config.reportIconSize
                    end,
                    set = function (_, value)
                        MLH.db.char.config.reportIconSize = value
                    end
                }
            }
        },
        groupDebug = {
            type = 'group',
            order = 22,
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
        groupStatistics = MLH.groupStatistics,
        groupFaq = MLH.groupFaq,
    }
}

function MLH:initConfig()
    ACFG:RegisterOptionsTable("MyLootHistory_MainOptions", mainOptions)
    ACFG:RegisterOptionsTable("MyLootHistory_GeneralOptions", generalOptions)

    ACFGDLG:AddToBlizOptions("MyLootHistory_MainOptions", "My Loot History")

    self:updateStatisticsTextData()
end

function MLH:updateStatisticsTextData()
    local itemsFound = self.db.char.foundItems
    local itemTypesAmount = #itemsFound
    local totalAmount = 0
    local zones = {}

    for i = 1, itemTypesAmount do
        for j = 1, #itemsFound[i].lootData do
            totalAmount = totalAmount + itemsFound[i].lootData[j].quantity

            local zoneID = itemsFound[i].lootData[j].zoneID or itemsFound[i].lootData[j].zone --shoud be zoneID
            local zoneIndex = -1

            for k = 1, #zones do
                if (zones[k] == zoneID) then
                    zoneIndex = k
                    break
                end
            end

            if (zoneIndex == -1) then
                table.insert(zones, zoneID)
            end
        end
    end

    generalOptions["args"]["groupStatistics"]["args"]["statisticsText"]["name"] = L["M_TotalDifferentItemsGathered"]..itemTypesAmount
    ..'\n'..L["M_TotalQuantityGathered"]..totalAmount..'\n'..L["M_TotalZonesLooted"]..#zones
end
