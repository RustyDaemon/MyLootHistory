--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local ADB = LibStub("AceDB-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

local defaults = {
    char = {
        foundItems = {},
        foundGold = {},
        thisSessionStart = time(),

        minimapData = {
            hide = false,
        },

        config = {
            showLastLooted = false,
            showZone = false,
            showItemID = false,
            showTooltip = true,
            showAdditionalTooltipData = false,
            reportIconSize = 24,
            ignoreItemsWithZeroPrice = true,
            resizableReportWindow = false,
            debug = {
                printLootedSummary = false,
                printOtherDebugInfo = false,
            },
        },

        params = {
            selectedRangeValue = 2,
            selectedQualityValue = 0,
            selectedExactItemQuality = false,
            selectedZoneID = 0, -- 0 is "any zone"
            searchText = "",
            sortKey = "quantity",
            sortDescending = true,
        },

        dbVersion = 1,
    },
}

-- itemId -> index into db.char.foundItems, built once per session and kept in step with
-- inserts. Never saved: it is derived data, and the saved table is what it is derived from.
local itemIndex = nil

local function getItemIndex(foundItems)
    if (itemIndex) then return itemIndex end

    itemIndex = {}

    for i = 1, #foundItems do
        local itemID = foundItems[i].itemId

        -- first entry wins, matching the linear scan this replaces
        if (itemIndex[itemID] == nil) then
            itemIndex[itemID] = i
        end
    end

    return itemIndex
end

function MLH:initDatabase()
    self.db = ADB:New("MyLootHistoryDB", defaults)
    itemIndex = nil
end

function MLH:addGold(quantity, zoneID)
    table.insert(self.db.char.foundGold, {
        quantity = quantity,
        foundOn = time(),
        zoneID = zoneID
    })
end

function MLH:addItem(itemID, quantity, itemLink, itemTexture, itemQuality, itemName, zoneID, sellPrice)
    local foundItems = self.db.char.foundItems
    local index = getItemIndex(foundItems)[itemID]
    local totalQuantity = 0

    local newLootDataObj = {
        quantity = quantity,
        foundOn = time(),
        zoneID = zoneID,
        sellPrice = sellPrice or 0,
    }

    if (index == nil) then
        local newItem = {
            itemId = itemID,
            itemLink = itemLink,
            itemName = itemName,
            itemTexture = itemTexture,
            quality = itemQuality,
            lootData = { newLootDataObj },
        }

        table.insert(foundItems, newItem)
        itemIndex[itemID] = #foundItems

        return quantity
    end

    local lootData = foundItems[index].lootData
    table.insert(lootData, newLootDataObj)

    for i = 1, #lootData do
        totalQuantity = totalQuantity + lootData[i].quantity
    end

    return totalQuantity
end

function MLH:resetData()
    self.db.char.foundItems = {}
    self.db.char.foundGold = {}
    itemIndex = nil
    MLH:updateStatisticsTextData()

    if (self.db.char.config.debug.printOtherDebugInfo) then
        print(L["M_DataWasCleared"])
    end
end
